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

if [ -n "$transcript" ] && [ -f "$transcript" ]; then
	hook_tokens "$transcript" session.usage "$@"
else
	hook_trace emit kind=session.usage outcome=fail \
		reason="the transcript the payload named cannot be read: ${transcript:-none named}" "$@"
fi

hook_trace emit kind=session.end harness=claude-code \
	reason="the agent harness ended the session (${why:-reason unstated})" "$@"

exit 0
