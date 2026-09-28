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
# Exits 0 unconditionally; says nothing on either stream. See hook.lib.sh.

set -u

. "$(dirname "$0")/hook.lib.sh"

hook_read

sid=$(hook_field session_id)
src=$(hook_field source)
cwd=$(hook_field cwd)
transcript=$(hook_expand "$(hook_field transcript_path)")

if [ -z "$sid" ]; then
	# No id is a FACT worth recording: the event says the session could not be
	# named rather than inventing a subject nothing will ever join on.
	hook_trace emit kind=session.start outcome=fail \
		reason='the SessionStart payload named no session_id, so this session has no identity in the trace'
	exit 0
fi

# The transcript is POINTED AT, never copied: the chain of thought stays where
# the agent harness keeps it and the trace stays one short line (PRD #237,
# story 22).
hook_trace emit kind=session.start subject="session:$sid" harness=claude-code \
	data.source="$src" data.cwd="$cwd" data.transcript="$transcript"

hook_point_at "$sid"

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
	printf 'export TRACE_SESSION=%s\n' "$sid" >>"$CLAUDE_ENV_FILE" 2>/dev/null || :
fi

exit 0
