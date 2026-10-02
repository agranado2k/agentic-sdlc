#!/bin/sh
# tool-pre.sh — the PreToolUse hook: leave a pending marker for the call.
#
# WHY IT EXISTS (ticket #409). A tool call the permission system refuses — or
# one a blocking PreToolUse hook such as the kill guard refuses — fires
# PreToolUse ONLY: no PostToolUse, no PostToolUseFailure, and the PreToolUse
# payload is emitted BEFORE the decision, so it carries no denial marker either
# (reproduced on claude 2.1.278; see tool-post.sh). Nothing that runs can say a
# call was denied; only the absence of what follows can. So this hook leaves a
# marker keyed by the call's tool-use id, tool-post.sh removes it when the call
# returns, and session-end.sh sweeps whatever is left into one
# `tool.use outcome=denied` each. See hook.lib.sh, "the pending marker".
#
# WHAT A MARKER HOLDS: the tool's name and the input head — the first 512 bytes
# of the input, scrubbed for one trace line by the same reader tool-post.sh
# uses. Never the full input: a denied call has nothing else to record, and the
# head is what a reader needs to tell which call it was.
#
# BEHIND TRACE_TOOLS, the switch tool-post.sh reads, and for a reason beyond
# cost: a marker is only meaningful beside a post-tool hook that removes it, so
# with capture off a marker would read every call as denied.
#
# NO NODE, NO MARKER. Without the reader tool-post.sh cannot read the call's id
# either and records `outcome=fail` with node named; a marker it can never
# remove would turn every such call into a false denial. A payload the reader
# refuses leaves no marker for the same reason, and tool-post.sh records the
# drift when the call returns.
#
# Exits 0 unconditionally and says nothing on stdout. See hook.lib.sh.

set -u

. "$(dirname "$0")/hook.lib.sh"

hook_tools_on || {
	cat >/dev/null 2>&1
	exit 0
}
tdir=$(hook_dir) || {
	cat >/dev/null 2>&1
	exit 0
}

hook_read

command -v node >/dev/null 2>&1 || exit 0

stage=
mkdir -p "$tdir/tmp" 2>/dev/null && stage=$(mktemp -d "$tdir/tmp/pre.XXXXXX" 2>/dev/null) || stage=
[ -n "$stage" ] || exit 0

if fields=$(printf '%s' "$hook_json" | node "$hook_here/tool-payload.mjs" "$stage" 2>/dev/null); then
	# One scalar the reader printed, the way tool-post.sh reads it.
	field() { printf '%s\n' "$fields" | sed -n "s/^$1 //p" | sed -n '1p'; }
	hook_pending_add "$tdir" "$(field session)" "$(field tool_use_id)" "$(field tool)" "$stage/head"
fi

rm -rf "$stage" 2>/dev/null || :
exit 0
