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
# Exits 0 unconditionally; says nothing on either stream. See hook.lib.sh.

set -u

. "$(dirname "$0")/hook.lib.sh"

hook_read

sid=$(hook_field session_id)
aid=$(hook_field agent_id)
atype=$(hook_field agent_type)
transcript=$(hook_expand "$(hook_field agent_transcript_path)")

set --
[ -n "$aid" ] && set -- subject="agent:$aid"
[ -n "$sid" ] && set -- "$@" related="session:$sid"
[ -n "$atype" ] && set -- "$@" data.agent_type="$atype"
[ -n "$transcript" ] && set -- "$@" data.transcript="$transcript"

if [ -n "$transcript" ] && [ -f "$transcript" ]; then
	hook_tokens "$transcript" agent.stop "$@"
else
	hook_trace emit kind=agent.stop \
		reason="the payload named no readable subagent transcript, so no tokens were read: ${transcript:-none named}" "$@"
fi

exit 0
