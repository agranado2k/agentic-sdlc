#!/bin/sh
# tool-post.sh — the PostToolUse and PostToolUseFailure hooks: one tool call, one event.
#
# ONE SCRIPT FOR BOTH EVENTS, because the only difference between them is the
# outcome and which key the result arrived under. The event records:
#
#   data.tool          the tool's name
#   data.tool_use_id   the call's own id, the one the transcript names it by
#   data.input_head    the first 512 bytes of the input, on the line itself
#   data.input_blob    the FULL input, in the blob store, named by git's hash
#   data.result_blob   the FULL result, the same way
#   data.result_bytes  how big that result was, so a reader knows before opening
#   outcome            ok when the call returned, fail when it did not
#
# BEHIND ITS OWN SWITCH. TRACE_TOOLS in the policy file, empty as shipped: a
# tool call is the least decision-bearing line in the trace and there are
# hundreds per session, and a tool result is the contents of whatever was read
# (ADR-0008 clause 8). With the switch empty this hook starts, exits 0 and
# writes nothing — the whole cost a project that did not ask for it pays.
#
# TWO OUTCOMES, NOT THREE. `denied` has no payload to read: a tool call the
# permission system refuses fires PreToolUse ONLY — no PostToolUse, no
# PostToolUseFailure — and the PreToolUse payload is emitted BEFORE the decision,
# so it carries no denial marker. Reproduced on claude 2.1.278 with a deny rule
# in a throwaway project. So a denied call is invisible here, deliberately and
# not silently: recording it needs a pending marker written at PreToolUse and
# swept by something that knows the call never completed, which is a mechanism
# of its own and a ticket rather than a line. An INTERRUPTED call does reach
# PostToolUseFailure (`is_interrupt` on the payload) and reads as fail.
#
# THERE IS NO PreToolUse HOOK BESIDE THIS ONE, for one measured reason: both post
# payloads carry the full `tool_input` themselves, so a pre hook would have
# nothing to add to the event and nothing of its own to emit — an extra process
# per tool call for no line. See the ticket's report and ../README.md.
#
# EVERY FAILURE IS ONE EVENT AND EXIT 0. A hook is on the agent harness's
# critical path (hook.lib.sh's rule 1), so a payload this hook cannot read, an
# id it must refuse, or a blob store that will not take the bytes each become one
# `tool.use` with `outcome=fail` and a reason — never a non-zero exit, and never
# a silent drop, because a capture that stopped without saying so is a hole
# nobody can count.
#
# Exits 0 unconditionally and says nothing on stdout; stderr stays loud, which
# is where a trace error belongs. See hook.lib.sh.

set -u

. "$(dirname "$0")/hook.lib.sh"

# THE SWITCH FIRST, and the payload drained rather than read: with tool capture
# off this hook must cost one process and no memory, whatever the agent harness
# is about to write down that pipe. Draining it is politeness to the writer, not
# a use of the bytes.
hook_tools_on || {
	cat >/dev/null 2>&1
	exit 0
}

# AND THEN THE DIRECTORY. Tracing off is not a failure to record — it is the
# documented no-op, and the note about it belongs to the operator typing a
# command, not to a session start (TRACE_QUIET, rule 3).
tdir=$(hook_dir) || {
	cat >/dev/null 2>&1
	exit 0
}

hook_read

# THE STAGING DIRECTORY sits INSIDE the trace directory, and only there, so
# landing a payload in the blob store is a rename rather than a copy across
# filesystems — the same reason scripts/trace.sh stages a blob under its own tmp/. Its own subdirectory
# per call, so two tool calls finishing at once cannot overwrite each other's
# three files.
stage=
if mkdir -p "$tdir/tmp" 2>/dev/null; then
	stage=$(mktemp -d "$tdir/tmp/tool.XXXXXX" 2>/dev/null) || stage=
fi

# AND NOWHERE ELSE. A first draft fell back to TMPDIR when that failed, which
# reads as robustness and is the opposite: on another filesystem the landing
# `mv` becomes copy-and-unlink, so a reader can open half a payload at the
# address its whole content will have — the one thing a content-addressed store
# must never allow (craft §11, and the reason trace_blob_name stages inside the
# trace directory too; M-3, review of PR #295). A trace directory that cannot
# stage is a recorded failure.
if [ -z "$stage" ]; then
	hook_trace emit kind=tool.use outcome=fail \
		reason="no scratch could be staged inside the trace directory, and a blob landed from anywhere else could be published half-written, so nothing was stored"
	exit 0
fi

if ! command -v node >/dev/null 2>&1; then
	hook_trace emit kind=tool.use outcome=fail \
		reason='node is not on PATH, so the tool payload could not be read — one line of JSON whose values are arbitrary text needs a parser'
	rmdir "$stage" 2>/dev/null || :
	exit 0
fi

# The reader's two streams stay apart for the reason hook_tokens keeps them
# apart: a runtime that prints a warning of its own would otherwise be read as
# a row on the success path and as the drift reason on the failure path.
err=$(mktemp "${TMPDIR:-/tmp}/cc-tool-err.XXXXXX" 2>/dev/null) || err=
if [ -n "$err" ]; then
	fields=$(printf '%s' "$hook_json" | node "$hook_here/tool-payload.mjs" "$stage" 2>"$err")
	status=$?
	why=$(sed -n '/^x tool-payload:/{p;q;}' "$err" 2>/dev/null | cut -c1-300)
	[ -n "$why" ] || why=$(sed -n '1p' "$err" 2>/dev/null | cut -c1-300)
	rm -f "$err"
else
	fields=$(printf '%s' "$hook_json" | node "$hook_here/tool-payload.mjs" "$stage")
	status=$?
	why=
fi

if [ "$status" != 0 ]; then
	hook_trace emit kind=tool.use outcome=fail \
		reason="${why:-the tool payload reader failed and said nothing}"
	rm -rf "$stage" 2>/dev/null || :
	exit 0
fi

# field <name> — one scalar the reader printed, or empty. A `sed` per field
# rather than a `while read` loop, because a loop in a pipeline runs in a
# subshell and every variable it set would die with it.
field() { printf '%s\n' "$fields" | sed -n "s/^$1 //p" | sed -n '1p'; }

tool=$(field tool)
tuid=$(field tool_use_id)
sid=$(field session)
event=$(field event)
from=$(field result_from)

# THE PAYLOAD IS DATA (the root manual's trust boundary). The two values that
# become join columns are checked against this adapter's identifier class before
# they reach an event — a value with a space or a quote is one `show` could never
# match, and the refusal never quotes the value, so a reason cannot carry what
# was refused. The session id is different in kind: it is IDENTITY, not the
# record, so an unusable one is simply omitted and the trace's own fallbacks (the
# exported TRACE_SESSION, then the pointer file) answer for it.
# AND SHORT ENOUGH TO FIT ON A LINE. The class check says nothing about length,
# and an event over 4000 bytes is REFUSED by the shared script — so a 5000-
# character id that is otherwise perfectly well formed stored two blobs and
# produced no line at all, which is the one outcome this hook promises never to
# have (M-1, review of PR #295). The bound is generous by two orders of
# magnitude against the ids this agent harness emits (~30 characters), and what
# it protects is the line, so a refusal event — which carries no id — always fits.
ID_MAX=256
id_usable() { hook_id_ok "$1" && [ "${#1}" -le "$ID_MAX" ]; }

why=
if ! hook_id_ok "$tuid"; then
	why='the payload named a tool_use_id that is not a plain identifier (letters, digits, dot, dash, underscore), and an id show could never match is not written'
elif [ "${#tuid}" -gt "$ID_MAX" ]; then
	why="the payload named a tool_use_id longer than $ID_MAX characters, which would push the event past the trace's own cap and cost the whole line"
elif ! hook_id_ok "$tool"; then
	why='the payload named a tool_name that is not a plain identifier, and a join column is not invented from it'
elif [ "${#tool}" -gt "$ID_MAX" ]; then
	why="the payload named a tool_name longer than $ID_MAX characters, which would push the event past the trace's own cap and cost the whole line"
fi
if [ -n "$why" ]; then
	hook_trace emit kind=tool.use outcome=fail reason="$why"
	rm -rf "$stage" 2>/dev/null || :
	exit 0
fi

# THE OUTCOME, from the event the operator wired when it is one of the two this
# script serves, and from the payload itself otherwise: `result_from` is a fact
# about the bytes that were stored, and the two have agreed on every payload
# observed. An unknown event name is not a reason to lose the call.
case $event in
PostToolUse) outcome=ok ;;
PostToolUseFailure) outcome=fail ;;
*) case $from in error) outcome=fail ;; *) outcome=ok ;; esac ;;
esac

# THE TWO BLOBS. A store that will not take the bytes is one event saying so:
# the hashes are what makes the event worth anything, and an event naming a blob
# nobody can open would be worse than one that says the store refused.
ib=$(hook_blob "$tdir" "$stage/input") || ib=
rb=$(hook_blob "$tdir" "$stage/result") || rb=
if [ -z "$ib" ] || [ -z "$rb" ]; then
	hook_trace emit kind=tool.use outcome=fail \
		reason="the trace's blob store could not take this tool call's payloads, so the event would have named blobs nobody can open"
	rm -rf "$stage" 2>/dev/null || :
	exit 0
fi

set -- kind=tool.use harness=claude-code outcome="$outcome"
# `session=` as well as `subject=`, for the reason session-end.sh gives: the
# pointer file is per-toplevel and answers for the emits no hook can see, never
# for one whose payload holds the authoritative id. The SUBJECT is the session
# rather than the call, so `show session:<id>` reads a session's tool calls in
# order; the call's own id is a data key, which is what joins it to a transcript.
[ -n "$sid" ] && id_usable "$sid" && set -- "$@" subject="session:$sid" session="$sid"
hook_trace emit "$@" \
	data.tool="$tool" data.tool_use_id="$tuid" \
	data.input_head="$(cat "$stage/head" 2>/dev/null)" \
	data.input_blob="${ib%% *}" \
	data.result_blob="${rb%% *}" data.result_bytes="${rb##* }"

rm -rf "$stage" 2>/dev/null || :
exit 0
