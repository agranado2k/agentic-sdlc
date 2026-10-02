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
# `summary` totals it twice. The anchor is the trace's OWN record: this
# session's `session.usage` events, each saying how far it read for ITS model
# (#408). Only the subject is asked, so another session's events can never
# anchor this one. The extractor reads them on stdin under --resume and counts
# each model after the last of them that names it; a fail event says nothing
# about how far it read and is passed over, so the next end counts from the
# last read that succeeded. One anchor per model, because the events are
# written one per model: an end killed between two of them has recorded the
# first model and not the second, and the second must start where ITS last
# event did — not after messages nobody recorded. No anchor — a fresh session,
# a new model, or a trace that is off — means the whole file for that model,
# which is exactly what a first read should be.
#
# `after` is the last anchor of any model, and only tells the hook an earlier
# read exists: an empty read is then "nothing new", carrying it forward. The
# value came out of a file, so it is held to the identifier class before it
# goes near a command line.
#
# THE SAME LINES ARE THE RECORDED ROLLUP GAPS (#407). The extractor reads them
# on stdin under --rollup, so a compaction's gap an earlier end recorded is
# never recorded again; a gap event carries no last_msg, so it never anchors.
after=
recorded=
if [ $# -gt 0 ]; then
	recorded=$(hook_trace show "session:$sid" --kind session.usage)
	after=$(printf '%s\n' "$recorded" |
		sed -n 's/.*,"data":{.*"last_msg":"\([^"]*\)".*/\1/p' | sed -n '$p')
	hook_id_ok "$after" || after=
fi

if [ -n "$transcript" ] && [ -f "$transcript" ]; then
	printf '%s\n' "$recorded" |
		hook_tokens "$transcript" session.usage --rollup --resume ${after:+--after "$after"} "$@"
else
	hook_trace emit kind=session.usage outcome=fail \
		reason="the transcript the payload named cannot be read: ${transcript:-none named}" "$@"
fi

# How many phantom stops this session had since its last end (#410).
phantoms=$(hook_phantom_take "$sid") && set -- "$@" data.phantoms="$phantoms"

hook_trace emit kind=session.end harness=claude-code \
	reason="the agent harness ended the session (${why:-reason unstated})" "$@"

exit 0
