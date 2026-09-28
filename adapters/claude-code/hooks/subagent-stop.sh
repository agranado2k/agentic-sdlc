#!/bin/sh
# subagent-stop.sh — the SubagentStop hook: one subagent finished, and what it spent.
#
# The subject is the AGENT, not the session: a spawn is the decision the tier
# mapping exists for, and `show agent:<id>` should read as one worker's life.
# The session it ran inside is a `related` subject, so the session's own
# timeline still finds it.
#
# THE TWO TRANSCRIPTS. The payload carries both, and they are not
# interchangeable: `transcript_path` is the PARENT session's file, and
# `agent_transcript_path` is the subagent's own, under a `subagents/`
# directory of the session's project folder. Reading the parent's here would
# attribute the whole session's spend to every subagent that stopped — the
# #246 spike's Q2 finding, and the reason hook.lib.sh's field reader is
# anchored on the character before the key.
#
# OBSERVED, and NOT what the #246 spike's fixtures show: in a live session this
# hook can run BEFORE the subagent's transcript has its assistant line. The
# fixtures were captured after the fact, so they hold the finished file; a real
# SubagentStop found the file present, 12 lines long, and carrying no assistant
# message yet — the line landed a moment later. The event then says exactly
# that and carries the transcript path in its data map, so the numbers are
# recoverable, but the subagent's tokens are missing from the trace.
#
# Deliberately not worked around here. A hook that sleeps or retries is a hook
# that delays a session, and how long to wait is a decision with a timing guess
# in it — a ticket, not a line. Until then: a session's own session.usage is
# exact, and the sum with agent.stop is exact only when the file was ready.
#
# Exits 0 unconditionally and says nothing on stdout; stderr stays loud, which
# is where a trace error belongs. See hook.lib.sh.

set -u

. "$(dirname "$0")/hook.lib.sh"

hook_read

sid=$(hook_field session_id)
aid=$(hook_field agent_id)
atype=$(hook_field agent_type)
transcript=$(hook_expand "$(hook_field agent_transcript_path)")

# The ids are checked before they become a subject or a field: a payload is
# data (see hook.lib.sh's hook_id_ok), and an id that cannot be queried is one
# `show` could never match. `session=` is set explicitly for the reason
# session-end.sh gives — the pointer answers for the emits no hook can see, not
# for this one.
set --
[ -n "$aid" ] && hook_id_ok "$aid" && set -- subject="agent:$aid"
if [ -n "$sid" ] && hook_id_ok "$sid"; then
	set -- "$@" related="session:$sid" session="$sid"
fi
[ -n "$atype" ] && set -- "$@" data.agent_type="$atype"
[ -n "$transcript" ] && set -- "$@" data.transcript="$transcript"

if [ -n "$transcript" ] && [ -f "$transcript" ]; then
	hook_tokens "$transcript" agent.stop "$@"
else
	hook_trace emit kind=agent.stop \
		reason="the payload named no readable subagent transcript, so no tokens were read: ${transcript:-none named}" "$@"
fi

exit 0
