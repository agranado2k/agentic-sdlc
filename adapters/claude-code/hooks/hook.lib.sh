#!/bin/sh
# hook.lib.sh — what the three trace hooks beside this file share.
#
# WHAT THESE HOOKS ARE. One agent harness can tell the decision trace three
# things nothing else knows: that a session began, what it spent, and that a
# subagent finished. Those are the agent harness's own events, so they live
# here in its adapter rather than in `scripts/trace.sh` (ADR-0008 clause 8:
# "the agent harness is the adapter's business"). Everything portable — the
# line format, the closed kind vocabulary, where the trace directory is — stays
# in the shared script, which these hooks call and never reimplement.
#
# DORMANT UNTIL SOMETHING NAMES THEM. Nothing under `adapters/` is on an
# execution path; a hook runs only once a settings file wires it (see
# ../README.md, "Wiring the session hooks"). In THIS kit that file is
# `.claude/settings.json`, which is kit-authoring only and never shipped. In
# your project it is yours to write, and until you write it these five files
# are reference material you can read.
#
# THE THREE RULES A HOOK HERE KEEPS, and why each one is not negotiable:
#
#   1. EXIT 0, ALWAYS. A hook is on the agent harness's critical path. A
#      non-zero exit is a signal to the agent harness about the SESSION, and
#      observability that can fail a session is worse than none (PRD #237,
#      story 15; ADR-0008 clause 4). Every call into the trace ends in `|| :`
#      and every hook ends in `exit 0`.
#   2. SILENT ON STDOUT. What a hook prints on stdout can reach the agent
#      harness's own parser. The trace's answers go to a file; nothing here
#      has anything to say. STDERR is a different stream and is deliberately
#      loud — ADR-0008 clause 4 wants a trace error visible, and the operator
#      is the reader.
#   3. TRACE_QUIET=1. An unconfigured trace prints one note per process, which
#      is the right nudge for an operator typing a command and pure noise on
#      every session start of a project that has decided not to trace.
#
# Sourced, not executed: `. "$(dirname "$0")/hook.lib.sh"` at the top of each
# hook. It defines functions, exports the trace's quiet variable and resolves
# two paths; it emits nothing of its own.

TRACE_QUIET=1
export TRACE_QUIET

# WHERE THINGS ARE, from this file's own location and never from the caller's
# cwd. A hook is invoked by the agent harness with a cwd of its own choosing,
# and `sh scripts/trace.sh` has to mean the script in THIS repository.
hook_here=$(cd "$(dirname "$0")" && pwd -P)
hook_repo=$(cd "$hook_here/../../.." && pwd -P)

# hook_trace <args…> — the plain shared script, run FROM THE REPO ROOT so that a
# relative TRACE_CONFIG (which is how this kit reaches its own never-shipped
# policy file) resolves against the repository rather than against wherever the
# agent harness happened to stand. `|| :` is rule 1: a trace error is loud on
# stderr and never in a status a caller acts on.
hook_trace() {
	(cd "$hook_repo" && sh scripts/trace.sh "$@") || :
}

# --- the payload ------------------------------------------------------------
# A hook is handed one JSON object on stdin. It arrives pretty-printed from
# this agent harness, and the fields these hooks read are ids and paths, so a
# whole JSON parser is not needed — and must not be needed, because the
# extractor is the one part of this adapter with a runtime and `node missing`
# has to stay a recorded reason rather than a dead hook.

hook_json=

# hook_read — the payload, into a shell variable. No temporary file, so there
# is nothing to clean up on a path that must never fail.
hook_read() { hook_json=$(cat 2>/dev/null) || hook_json=; }

# hook_field <key> — the payload's top-level string value for <key>, or empty.
#
# ANCHORED on the character before the key's opening quote — a `{`, a `,` or
# whitespace — for one specific reason: `transcript_path` is the PARENT
# session's file and `agent_transcript_path` is the subagent's own, and an
# unanchored pattern for the first one matches the tail of the second and
# silently reads the wrong transcript (the #246 spike's finding Q2).
#
# WHICH MATCH WINS, precisely, because the loose answer was wrong: sed's `.*`
# is greedy, so within ONE LINE the last occurrence wins, and across lines the
# first line that matches wins. On the pretty-printed payload this agent
# harness emits, one key per line, that is "the first occurrence". On a compact
# payload it is the last, and a key nested inside another object reads as
# top-level either way. Neither shape occurs here, and the anchoring above is
# what the one case that matters depends on (L-1, review of PR #291).
hook_field() {
	printf '%s\n' "$hook_json" |
		sed -n 's/.*[{,[:space:]]"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
		sed -n '1p'
}

# hook_id_ok <value> — is this an identifier this adapter may use?
#
# TWO REQUIREMENTS, and the second is why the class is this narrow. It has to
# be QUERYABLE — `scripts/trace.sh` matches a subject exactly, so a value with
# a space or a quote is one `show` could never find. And it has to be SAFE TO
# WRITE INTO A FILE THE AGENT HARNESS SOURCES AS SHELL: session-start.sh
# appends an export to the file `CLAUDE_ENV_FILE` names, and that file is read
# back into every later tool call of the session. An id carrying `;` or `$` is
# then arbitrary code in the operator's next command — reproduced against the
# first draft of this adapter, which wrote the value after the trace had
# already refused it as a malformed subject (H-1, review of PR #291).
#
# So: letters, digits, dot, dash, underscore, and nothing else. That is what a
# session id and an agent id are, and a payload is DATA — the root manual's
# trust boundary applied at the one place in this adapter where it is
# load-bearing. A value outside the class is refused, loudly, and the hook goes
# on to exit 0 like everything else here.
hook_id_ok() {
	case ${1:-} in
	'' | *[!A-Za-z0-9._-]*) return 1 ;;
	esac
	return 0
}

# hook_expand <path> — a leading `~` is the home directory of whoever ran the
# agent harness. The live capture's paths are absolute, and the `~` in the
# checked-in fixtures is the REDACTION's substitution rather than anything the
# agent harness emitted — so this branch guards a shape nothing here has been
# seen to produce, and `tests/trace-hooks.test.sh` section 16 is the case that
# keeps it honest rather than untested.
hook_expand() {
	case $1 in
	'~') printf '%s' "${HOME:-~}" ;;
	'~/'*) printf '%s/%s' "${HOME:-~}" "${1#\~/}" ;;
	*) printf '%s' "$1" ;;
	esac
}

# --- the session pointer ----------------------------------------------------

# hook_pointer — the per-toplevel pointer file `scripts/trace.sh` reads a
# session id back from, or nothing (status 1) when tracing is off or git cannot
# hash the path.
#
# THIS IS A DELIBERATE COUPLING, and it is the one thing in this file worth
# reviewing twice. The shared script derives that path from git's hash of the
# toplevel it itself lives in; nothing exposes it, so a writer has to derive it
# the same way. The check that the two derivations agree is not a comparison of
# strings — it is `tests/trace-hooks.test.sh`'s assertion that an emit made
# AFTER this hook carries the session, which is the only thing the pointer is
# for. GIT_DIR and GIT_WORK_TREE are scrubbed because git exports them into
# hooks and a pinned pair would answer for another repository.
hook_pointer() {
	_hp_dir=$( (cd "$hook_repo" && sh scripts/trace.sh dir) 2>/dev/null ) || _hp_dir=
	[ -n "$_hp_dir" ] || return 1
	_hp_top=$( (unset GIT_DIR GIT_WORK_TREE && git -C "$hook_repo" rev-parse --show-toplevel) 2>/dev/null ) || _hp_top=
	[ -n "$_hp_top" ] || _hp_top=$hook_repo
	_hp_key=$(printf '%s' "$_hp_top" |
		(unset GIT_DIR GIT_WORK_TREE && git hash-object --stdin) 2>/dev/null) || _hp_key=
	[ -n "$_hp_key" ] || return 1
	printf '%s/current/%s' "$_hp_dir" "$_hp_key"
}

# hook_point_at <session id> — write the pointer, or do nothing at all.
hook_point_at() {
	_pa_p=$(hook_pointer) || return 0
	mkdir -p "$(dirname "$_pa_p")" 2>/dev/null || return 0
	printf '%s\n' "$1" >"$_pa_p" 2>/dev/null || :
	return 0
}

# --- token counts -----------------------------------------------------------

# hook_tokens <transcript> <kind> [<field>=<value> …] — one event of <kind> per
# model in the transcript, carrying that model's four token counts, and exactly
# one event whatever happens. Four shapes, all of them exit 0:
#
#   the numbers      one event per model, tokens on it
#   node missing     one event, outcome=fail, the reason naming node
#   shape drift      one event, outcome=fail, the reason the extractor gave
#   nothing to read  one event, outcome=fail, saying the transcript had no
#                    assistant message with a usage block yet
#
# EVERY FAILURE SHAPE CARRIES outcome=fail AND NO TOKEN COUNTS. The counts,
# because a partial sum is the failure this whole path exists to avoid and an
# event saying "this is what I could not read" is worth more than one saying
# zero. The flag, because the last shape is the live gap subagent-stop.sh
# documents — a transcript read before it was flushed — and without a field to
# filter on it is indistinguishable from a subagent that genuinely spent
# nothing, so the holes cannot be counted and the ticket that closes them has
# no acceptance (M-6, review of PR #291).
hook_tokens() {
	_ht_file=$1
	_ht_kind=$2
	shift 2
	if ! command -v node >/dev/null 2>&1; then
		hook_trace emit kind="$_ht_kind" outcome=fail \
			reason='node is not on PATH, so the transcript could not be read for token counts' "$@"
		return 0
	fi
	# TWO STREAMS, KEPT APART. The first draft merged them, and a node that
	# prints a warning of its own — an ExperimentalWarning, a version shim's
	# notice — then fed that line to the row reader on the success path and
	# recorded it as the drift reason on the failure path (M-1, review of
	# PR #291). Never parse a stream the runtime shares. Without a scratch
	# file the two cannot be told apart, so that case takes the rows and lets
	# node's own stderr reach the operator instead of guessing.
	_ht_err=$(mktemp "${TMPDIR:-/tmp}/cc-hook.XXXXXX" 2>/dev/null) || _ht_err=
	if [ -n "$_ht_err" ]; then
		_ht_out=$(node "$hook_here/transcript-usage.mjs" "$_ht_file" 2>"$_ht_err")
		_ht_st=$?
		# THE EXTRACTOR'S OWN LINE, by its prefix, and only then the first
		# line: a runtime warning arrives BEFORE the refusal it precedes, so
		# "the first line" recorded node's chatter as the reason a key drifted.
		# One line, trimmed, either way — an event is capped at 4000 bytes
		# (craft §11's single write, made checkable) and a reason is a sentence.
		_ht_why=$(sed -n '/^x transcript-usage:/{p;q;}' "$_ht_err" 2>/dev/null | cut -c1-300)
		[ -n "$_ht_why" ] || _ht_why=$(sed -n '1p' "$_ht_err" 2>/dev/null | cut -c1-300)
		rm -f "$_ht_err"
	else
		_ht_out=$(node "$hook_here/transcript-usage.mjs" "$_ht_file")
		_ht_st=$?
		_ht_why=
	fi
	if [ "$_ht_st" != 0 ]; then
		hook_trace emit kind="$_ht_kind" outcome=fail \
			reason="${_ht_why:-the transcript usage extractor failed and said nothing}" "$@"
		return 0
	fi
	if [ -z "$_ht_out" ]; then
		hook_trace emit kind="$_ht_kind" outcome=fail \
			reason='the transcript carries no assistant message with a usage block — nothing to read yet' "$@"
		return 0
	fi
	printf '%s\n' "$_ht_out" | while read -r _ht_m _ht_i _ht_o _ht_w _ht_r; do
		[ -n "$_ht_m" ] || continue
		hook_trace emit kind="$_ht_kind" model="$_ht_m" \
			tok_in="$_ht_i" tok_out="$_ht_o" tok_cache_w="$_ht_w" tok_cache_r="$_ht_r" "$@"
	done
	return 0
}

# --- tool capture: the switch, and the blob store ---------------------------
# Everything below is read only by tool-post.sh. It sits here, beside the
# payload reader and the pointer, because it is the same kind of thing: what
# this adapter has to know about the shared script in order to speak to it.

# hook_policy — the trace policy file this repository's hooks read.
#
# The same two candidates `scripts/trace.sh` discovers when it is run from this
# repository, which is how `hook_trace` always runs it: an explicit
# TRACE_CONFIG (relative values against the repository, never against wherever
# the agent harness stood), else scripts/trace.config.sh beside the script. One
# answer for "is tracing on", reached from either side.
hook_policy() {
	if [ -n "${TRACE_CONFIG:-}" ]; then
		case $TRACE_CONFIG in
		/*) printf '%s' "$TRACE_CONFIG" ;;
		*) printf '%s/%s' "$hook_repo" "$TRACE_CONFIG" ;;
		esac
		return 0
	fi
	printf '%s/scripts/trace.config.sh' "$hook_repo"
}

# hook_tools_on — is tool capture asked for? Status 0 for yes, 1 for no.
#
# WHY A HOOK READS POLICY AT ALL, when every other answer here comes out of
# `scripts/trace.sh`: the shared script has no opinion on tool capture. An event
# is an event, whoever asked for it, and the agent harness is the adapter's
# business (ADR-0008 clause 8) — so the only reader of TRACE_TOOLS is the hook
# that would do the capturing. It reads the same file with the same precedence
# the shared script gives TRACE_DIR: the environment wins over the file, and an
# environment value of '' is the documented OFF even when the file says 1.
#
# SOURCING IS EXECUTING, which is why the file is the one this adapter's own
# repository names and never one found from a cwd the agent harness chose — the
# reason scripts/agents.lib.sh anchors its discovery the same way. A file that
# is missing or that cannot be read answers OFF, because OFF is the safe default
# for a switch whose ON state writes down everything every tool returned.
hook_tools_on() {
	if [ -n "${TRACE_TOOLS+set}" ]; then
		[ -n "$TRACE_TOOLS" ]
		return $?
	fi
	_ht_file=$(hook_policy)
	[ -f "$_ht_file" ] || return 1
	# The policy file's own output goes nowhere: only the printf below is this
	# substitution's answer, so a file that echoes cannot turn a switch on.
	_ht_want=$(
		. "$_ht_file" >/dev/null 2>&1
		printf '%s' "${TRACE_TOOLS:-}"
	)
	[ -n "$_ht_want" ]
}

# hook_dir — the resolved trace directory, or nothing (status 1) when tracing is
# off. Asked of the shared script itself, which is the only thing that knows how
# a relative policy value resolves against the root checkout.
#
# ASK IT ONCE. There is no cache here on purpose: a caller reads this through a
# command substitution, so anything remembered inside would be remembered in a
# subshell and thrown away — a cache that cannot work, paid for on every tool
# call (M-4, review of PR #295). The one caller resolves it once and hands it
# down.
hook_dir() {
	_hd_dir=$( (cd "$hook_repo" && sh scripts/trace.sh dir) 2>/dev/null ) || _hd_dir=
	[ -n "$_hd_dir" ] || return 1
	printf '%s' "$_hd_dir"
}

# hook_blob <trace directory> <staged file> — put those bytes in the trace's blob
# store and print `<hash> <bytes>`. The file is CONSUMED: it is renamed into the
# store, or left for the caller's scratch sweep when the store already holds that
# content. The directory is passed IN rather than resolved here, because a caller
# with two payloads would otherwise ask the shared script for it twice.
#
# WHY THIS ADAPTER LANDS A BLOB ITSELF, rather than through `emit --blob`. One
# emit carries one blob — `scripts/trace.sh` refuses a second, deliberately: the
# line format has room for one hash. A tool call has TWO payloads, its input and
# its result, and the acceptance for capturing one is ONE event, because a reader
# joining two half-events per tool call is exactly the volume the switch exists
# to contain. So the two payloads are stored here and the one event names both
# under its data map.
#
# THAT MAKES TWO WRITERS OF ONE STORE, which is a coupling — the same shape as
# hook_pointer above, and it is held the same way: not by comparing strings but
# by `tests/trace-hooks.test.sh` section 19, which hands the SHARED SCRIPT the
# same payload and asserts it lands at the same relative path under its own
# directory. The day trace.sh renames or re-lays-out the store, that goes red
# instead of the trace quietly growing a second store nobody reads. A `blob`
# subcommand on the shared script — store these bytes, print the name, write no
# event — would remove the coupling altogether, and is the ticket to file.
#
# The name is GIT's content hash, `--stdin` like trace_hash_file, so the blob is
# named the same thing `git hash-object` names it anywhere. Identical content is
# stored once and never rewritten, and the landing is a rename, so a reader never
# opens half a payload (craft §11).
hook_blob() {
	_hb_dir=$1
	[ -n "$_hb_dir" ] || return 1
	[ -f "$2" ] || return 1
	# FROM THE ADAPTER'S OWN REPOSITORY, never from the caller's cwd: `git
	# hash-object` answers in the object format of the repository it runs in, and
	# the agent harness chooses where a hook stands. Run in a sha256 repository
	# it named a payload sha256 while the shared script — which runs from
	# hook_repo — named the same bytes sha1, which is two addresses for one
	# payload in one store (M-2, review of PR #295).
	_hb_hash=$( (unset GIT_DIR GIT_WORK_TREE && git -C "$hook_repo" hash-object --stdin <"$2") 2>/dev/null ) || _hb_hash=
	[ -n "$_hb_hash" ] || return 1
	_hb_bytes=$(wc -c <"$2" 2>/dev/null | tr -d ' ')
	[ -n "$_hb_bytes" ] || return 1
	_hb_dest="$_hb_dir/blobs/$(printf '%.2s' "$_hb_hash")/$_hb_hash"
	if [ ! -f "$_hb_dest" ]; then
		mkdir -p "$(dirname "$_hb_dest")" 2>/dev/null || return 1
		mv "$2" "$_hb_dest" 2>/dev/null || return 1
	fi
	printf '%s %s' "$_hb_hash" "$_hb_bytes"
}
