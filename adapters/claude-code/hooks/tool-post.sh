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
#   reason             on a fail, the error's first non-empty line, scrubbed of
#                      what the trace refuses and capped at 300 characters
#
# BEHIND ITS OWN SWITCH. TRACE_TOOLS in the policy file, empty as shipped: a
# tool call is the least decision-bearing line in the trace and there are
# hundreds per session, and a tool result is the contents of whatever was read
# (the kit's ADR-0008 clause 8). With the switch empty this hook starts, exits 0 and
# writes nothing — the whole cost a project that did not ask for it pays.
#
# TWO OUTCOMES HERE; THE THIRD IS SWEPT. `denied` has no payload to read: a
# tool call the permission system refuses fires PreToolUse ONLY — no
# PostToolUse, no PostToolUseFailure — and the PreToolUse payload is emitted
# BEFORE the decision, so it carries no denial marker. Reproduced on claude
# 2.1.278 with a deny rule in a throwaway project. So tool-pre.sh leaves a
# pending marker per call, this hook removes the call's marker when it returns,
# and session-end.sh sweeps what is left into one `tool.use outcome=denied`
# each (#409). An INTERRUPTED call does reach PostToolUseFailure (`is_interrupt`
# on the payload) and reads as fail.
#
# THE PRE HOOK WRITES NO EVENT: both post payloads carry the full `tool_input`
# themselves, so the event is still written here, once, and the marker is only
# the evidence that a call began.
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
# command, not to a session start (TRACE_QUIET, rule 3). A refused policy's
# line is discarded too: this hook runs on every tool call, and the session
# hooks already say it once (hook_dir).
tdir=$(hook_dir 2>/dev/null) || {
	cat >/dev/null 2>&1
	exit 0
}

hook_read

# THE STAGING DIRECTORY sits INSIDE the trace directory: the reader below
# writes the full input and result there before `scripts/trace.sh blob` stores
# them, so a tool's payload never leaves the directory whose access the
# operator chose. Its own subdirectory per call, so two tool calls finishing at
# once cannot overwrite each other's three files. The landing is the shared
# script's — it stages its own copy and renames that into the store — so
# nothing here is ever moved into the store, and the whole directory is swept
# at the end.
stage=
if mkdir -p "$tdir/tmp" 2>/dev/null; then
	stage=$(mktemp -d "$tdir/tmp/tool.XXXXXX" 2>/dev/null) || stage=
fi
if [ -z "$stage" ]; then
	hook_trace emit kind=tool.use outcome=fail \
		reason="no scratch could be staged inside the trace directory, so the tool payload had nowhere private to be read into, and nothing was stored"
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
	# The call returned, so it was not denied: its marker goes even though
	# the reader refused the payload, on the plain field reader's ids (#409).
	hook_pending_drop "$tdir" "$(hook_field session_id)" "$(hook_field tool_use_id)"
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
errfirstline=$(field error_first_line)

# THE RUN HANDED OVER AT SPAWN (#474; see hook_run_handed): read from the
# transcript of the agent this call belongs to — the subagent's own when the
# payload names one, the session's otherwise — so a subagent's calls carry the
# run its spawn prompt named, and one handed none never borrows the run handed
# to its session.
# With none handed, the shared script resolves the run as it always has.
if own=$(hook_agent_transcript "$(hook_expand "$(field transcript)")" "$(field agent)"); then
	hook_run_handed "$own" || :
fi

# THE CALL RETURNED, so tool-pre.sh's marker for it goes now, before anything
# below can refuse the event: a refused event is still not a denied call (#409).
hook_pending_drop "$tdir" "$sid" "$tuid"

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

# THE TWO BLOBS, through the shared script's own store: `blob` prints
# `<hash> <bytes>` and writes no event, so both payloads are stored before the
# ONE event that names them. A store that will not take the bytes prints
# nothing, and that is one event saying so: the hashes are what makes the event
# worth anything, and an event naming a blob nobody can open would be worse
# than one that says the store refused. hook_trace runs the script from the
# adapter's own repository, so the name is that repository's object format and
# never the one of wherever the agent harness stood (M-2, review of PR #295).
ib=$(hook_trace blob "$stage/input")
rb=$(hook_trace blob "$stage/result")
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
# WHEN A TOOL CALL FAILS, the error's first non-empty line is the reason. The
# reader already made it one line with nothing the trace refuses; it goes as one
# argument, unescaped, and trace.sh escapes it for JSON.
if [ "$outcome" = fail ] && [ -n "$errfirstline" ]; then
	set -- "$@" reason="$errfirstline"
fi
hook_trace emit "$@" \
	data.tool="$tool" data.tool_use_id="$tuid" \
	data.input_head="$(cat "$stage/head" 2>/dev/null)" \
	data.input_blob="${ib%% *}" \
	data.result_blob="${rb%% *}" data.result_bytes="${rb##* }"

rm -rf "$stage" 2>/dev/null || :
exit 0
