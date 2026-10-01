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
# hook can run BEFORE the subagent's transcript has its final assistant line.
# The fixtures were captured after the fact, so they hold the finished file.
# Ticket #308 measured it: in two of seven live stops the file was present and
# one turn short, and the final line landed 170 and 223 ms after this hook
# began. Read at once, such a file yields no usage at all, or — when the
# subagent had used a tool — the sum of the turns BEFORE the last one, a
# confident undercount that looks exactly like success.
#
# So the hook WAITS for the transcript to end on a final message (see
# hook.lib.sh's hook_final), polling, bounded by the policy value
# TRACE_AGENT_WAIT_MS. The shipped policy file leaves it empty — no wait, the
# read-at-once behaviour above — because how long a hook may hold a session is
# a project's decision; the kit's twin sets its own. When the bound passes the
# absence is recorded, outcome=fail and no partial sum, with the wait it gave
# in data.waited_ms.
#
# A PHANTOM STOP WRITES NOTHING (ticket #344). A payload whose transcript does
# not exist is not waited for and not recorded: every measured stop found its
# file already there, and in the kit's own trace every stop that named a missing
# file named one that never appeared — 1,418 of 1,614 stops in one retro window,
# about one every 30 seconds of a long session, under agent ids no transcript
# holds. No subagent's work stands behind one, so an event would only dilute
# every rate /retro reads off the agent.stop count; the adapter README records
# why the shape is no event rather than a new outcome word. A file that EXISTS
# and cannot be read is a real stop whose usage is lost: outcome=fail at once,
# naming that cause — it would never "become final", so it is not polled.
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

hook_wait_bound
# Nothing to write, nothing to wait for: with tracing off the bound is moot, and
# so is a typo in it — a project that traces nothing is not told on every stop.
if [ -n "$hook_wait_ms$hook_wait_bad" ] && ! hook_dir >/dev/null; then
	hook_wait_ms=
	hook_wait_bad=
fi
if [ -n "$hook_wait_bad" ]; then
	printf '%s\n' "x trace: TRACE_AGENT_WAIT_MS='$hook_wait_bad' is not a number of milliseconds — give a whole number from 1 to 99999 with no leading zero, or leave it empty for no wait. The subagent-stop hook did not wait." >&2
	set -- "$@" data.wait_refused="$hook_wait_bad"
fi

if [ -n "$transcript" ] && [ ! -e "$transcript" ] && [ ! -h "$transcript" ]; then
	: # a phantom: no event (see the header)
elif [ -n "$transcript" ] && { [ ! -f "$transcript" ] || [ ! -r "$transcript" ]; }; then
	hook_trace emit kind=agent.stop outcome=fail \
		reason="the subagent transcript exists but cannot be read as a file, so no tokens were read: $transcript" "$@"
elif [ -n "$transcript" ] && [ -n "$hook_wait_ms" ]; then
	if waited=$(hook_wait_final "$transcript" "$hook_wait_ms"); then
		hook_tokens "$transcript" agent.stop "$@" data.waited_ms="$waited"
	else
		hook_trace emit kind=agent.stop outcome=fail data.waited_ms="$waited" \
			reason="the subagent transcript did not end on a final message within the ${hook_wait_ms} ms bound, so no tokens were read — a partial sum would be an undercount" "$@"
	fi
elif [ -n "$transcript" ]; then
	hook_tokens "$transcript" agent.stop "$@"
else
	hook_trace emit kind=agent.stop \
		reason="the payload named no subagent transcript, so no tokens were read" "$@"
fi

exit 0
