#!/bin/sh
# session-end.sh — the SessionEnd hook: what this session spent, then that it ended.
#
# One `session.usage` event PER MODEL with the four token counts, then one
# `session.end`. The usage events come first so that a reader of the trail sees
# the spend inside the session rather than after it.
#
# COST IS NOT WRITTEN HERE, and that is a decision rather than an omission
# (ADR-0008 clause 6). The transcript's own final line carries the agent
# harness's cost figure and it would be one `sed` away; it is an interpretation
# of a vendor's price list on the day it was written, and a price edit could
# never reach it afterwards. Token counts are facts. `summary` and `export`
# price them on read, from a table the operator owns.
#
# Exits 0 unconditionally and says nothing on stdout; stderr stays loud, which
# is where a trace error belongs. See hook.lib.sh.

set -u

. "$(dirname "$0")/hook.lib.sh"

hook_read

sid=$(hook_field session_id)
why=$(hook_field reason)
transcript=$(hook_expand "$(hook_field transcript_path)")

# The subject, once, as positional arguments — so that a session with no id
# still produces events, without an unquoted expansion standing in for a
# conditional argument.
#
# `session=` AS WELL AS `subject=`, and that is not redundancy. The pointer file
# is per-toplevel, so a second session starting in the same checkout overwrites
# it; a hook that let the pointer answer for its OWN event would then file this
# session's end under the other session's id while its subject said this one,
# and `summary --by session` would be quietly wrong. The hook holds the
# authoritative id — it is on the payload — so it says it (M-2, review of
# PR #291). The pointer remains what answers for the emits no hook can see.
set --
[ -n "$sid" ] && hook_id_ok "$sid" && set -- subject="session:$sid" session="$sid"

# HOW FAR AN EARLIER END OF THIS SESSION ALREADY READ (#307). A resumed session
# keeps its id and appends to its one transcript, and every run ends with this
# hook — so without an anchor the second end re-counts the first run and
# `summary` totals it twice. The anchor is the trace's OWN record: the last
# `session.usage` event filed under this session's subject that says how far
# it read. Only the subject is asked, so another session's events can never
# anchor this one; a fail event says nothing about how far it read and is
# passed over, so the next end counts from the last read that succeeded. No
# anchor — a fresh session, or a trace that is off — means the whole file,
# which is exactly what a first end should read. The value came out of a file,
# so it is held to the identifier class before it goes near a command line.
after=
if [ $# -gt 0 ]; then
	after=$(hook_trace show "session:$sid" --kind session.usage 2>/dev/null |
		sed -n 's/.*,"data":{.*"last_msg":"\([^"]*\)".*/\1/p' | sed -n '$p')
	hook_id_ok "$after" || after=
fi

if [ -n "$transcript" ] && [ -f "$transcript" ]; then
	hook_tokens "$transcript" session.usage ${after:+--after "$after"} "$@"
else
	hook_trace emit kind=session.usage outcome=fail \
		reason="the transcript the payload named cannot be read: ${transcript:-none named}" "$@"
fi

hook_trace emit kind=session.end harness=claude-code \
	reason="the agent harness ended the session (${why:-reason unstated})" "$@"

exit 0
