#!/bin/sh
# session-start.sh — the SessionStart hook: a session begins, and says who it is.
#
# It does three things, in this order, and the order matters: the event first,
# because that is the record; then the pointer file, because a later emit from
# this working tree reads the session id back from it; then the export, because
# that is the agent-harness facility that beats the pointer when it exists.
#
# SESSION IDENTITY, most specific first (PRD #237's implementation decision,
# settled by the #246 spike):
#
#   1. THE ENV FILE. The hook's environment carries CLAUDE_ENV_FILE, pointing
#      at a shell file this agent harness sources for every later tool call in
#      the session — subagents included. A line appended there puts
#      TRACE_SESSION in scope for every emit the session makes afterwards,
#      which is the identity path that needs no file lookup and no guessing.
#   2. THE POINTER FILE, the fallback the shared script reads on its own. It is
#      per-toplevel, so two sessions in one checkout would overwrite each
#      other's — which is exactly why the env file is preferred where it
#      exists, and why this hook writes both. The spike did not establish
#      whether the env file survives a resumed or compacted session, so the
#      fallback stays.
#
# Exits 0 unconditionally and says nothing on stdout; stderr stays loud, which
# is where a trace error belongs. See hook.lib.sh.

set -u

. "$(dirname "$0")/hook.lib.sh"

hook_read

# How far the ROOT checkout — the one these hooks execute from, even when the
# session opened in a linked worktree — is behind the last fetched origin/main:
# recorded on the event below, and said on stderr past the policy threshold.
# No origin/main is no field and no note (hook.lib.sh).
behind=
root=$(hook_root) && behind=$(hook_behind "$root") || behind=
[ -z "$behind" ] || hook_behind_warn "$behind" "$root"

sid=$(hook_field session_id)
src=$(hook_field source)
cwd=$(hook_field cwd)
transcript=$(hook_expand "$(hook_field transcript_path)")

# THE PAYLOAD IS DATA. An unusable id is refused BEFORE it reaches either of
# the two files below, and the reason never quotes the value: the export goes
# into a file the agent harness sources as shell, so a value carrying `;` would
# be code in the operator's next command, and a value carrying a newline would
# make the refusal event itself unwritable. Both cases are one event and exit 0.
why=
if [ -z "$sid" ]; then
	why='the SessionStart payload named no session_id'
elif ! hook_id_ok "$sid"; then
	why='the SessionStart payload named a session_id that is not a plain identifier (letters, digits, dot, dash, underscore), and it is refused rather than written into a file the agent harness sources'
fi
if [ -n "$why" ]; then
	hook_trace emit kind=session.start outcome=fail \
		reason="$why — this session has no identity in the trace"
	exit 0
fi

# The transcript is POINTED AT, never copied: the chain of thought stays where
# the agent harness keeps it and the trace stays one short line (PRD #237,
# story 22). `session=` as well as `subject=`, so the event names the session
# the PAYLOAD gave it rather than whatever the pointer file happens to say —
# see session-end.sh for the two-sessions-in-one-checkout case that matters.
hook_trace emit kind=session.start subject="session:$sid" session="$sid" \
	harness=claude-code data.source="$src" data.cwd="$cwd" data.transcript="$transcript" \
	${behind:+"data.behind=$behind"} ${behind:+"data.behind_of=root"}

hook_point_at "$sid"

# Single-quoted, though hook_id_ok has already forbidden everything that would
# need quoting: the guard is the rule and this is the belt beside it.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
	printf "export TRACE_SESSION='%s'\n" "$sid" >>"$CLAUDE_ENV_FILE" 2>/dev/null || :
fi

exit 0
