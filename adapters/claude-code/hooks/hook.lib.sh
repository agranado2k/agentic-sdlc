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
# your project it is yours to write, and until you write it these four files
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
#      has anything to say.
#   3. TRACE_QUIET=1. An unconfigured trace prints one note per process, which
#      is the right nudge for an operator typing a command and pure noise on
#      every session start of a project that has decided not to trace.
#
# Sourced, not executed: `. "$(dirname "$0")/hook.lib.sh"` at the top of each
# hook. It defines functions and sets two variables; it runs nothing.

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
# silently reads the wrong transcript (the #246 spike's finding Q2). The first
# match wins; a repeated key would be drift, and the extractor is where drift
# is reported.
hook_field() {
	printf '%s\n' "$hook_json" |
		sed -n 's/.*[{,[:space:]]"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
		sed -n '1p'
}

# hook_expand <path> — a leading `~` is the agent harness's own shorthand for
# the home directory of whoever ran it, and a path is only useful here if it
# can be opened.
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
# one event whatever happens. Three shapes, all of them exit 0:
#
#   the numbers      one event per model, tokens on it
#   node missing     one event, outcome=fail, the reason naming node
#   shape drift      one event, outcome=fail, the reason the extractor gave
#
# The fail shapes carry NO token counts, deliberately: a partial sum is the
# failure this whole path exists to avoid, and an event that says "this is what
# I could not read" is worth more than one that says zero.
hook_tokens() {
	_ht_file=$1
	_ht_kind=$2
	shift 2
	if ! command -v node >/dev/null 2>&1; then
		hook_trace emit kind="$_ht_kind" outcome=fail \
			reason='node is not on PATH, so the transcript could not be read for token counts' "$@"
		return 0
	fi
	# Combined streams on purpose: on success the extractor writes only the
	# rows, and on failure its first line is the reason this event carries.
	_ht_out=$(node "$hook_here/transcript-usage.mjs" "$_ht_file" 2>&1)
	_ht_st=$?
	if [ "$_ht_st" != 0 ]; then
		# One line, trimmed: an event is capped at 4000 bytes (craft §11's
		# single write, made checkable), and a reason is a sentence.
		_ht_why=$(printf '%s\n' "$_ht_out" | sed -n '1p' | cut -c1-300)
		hook_trace emit kind="$_ht_kind" outcome=fail \
			reason="${_ht_why:-the transcript usage extractor failed and said nothing}" "$@"
		return 0
	fi
	if [ -z "$_ht_out" ]; then
		hook_trace emit kind="$_ht_kind" \
			reason='the transcript carries no assistant message with a usage block' "$@"
		return 0
	fi
	printf '%s\n' "$_ht_out" | while read -r _ht_m _ht_i _ht_o _ht_w _ht_r; do
		[ -n "$_ht_m" ] || continue
		hook_trace emit kind="$_ht_kind" model="$_ht_m" \
			tok_in="$_ht_i" tok_out="$_ht_o" tok_cache_w="$_ht_w" tok_cache_r="$_ht_r" "$@"
	done
	return 0
}
