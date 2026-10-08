#!/bin/sh
# spawn-guard.sh — the PreToolUse hook on the agent harness's spawn tool: a
# spawn whose prompt carries no well-formed Trace-Spawn line is refused before
# the subagent starts (#627).
#
# WHY IT EXISTS. After #615, 43 of 108 subagent stops — 63 % of their cost —
# were still unattributed: a spawn made outside the chain's spawn sites carried
# no Trace-Spawn line, and the line was prose nothing enforced. This makes it a
# mechanism: the refusal names the line it wants, and the session adds it.
#
# WHAT IT WANTS is the line subagent-stop.sh reads, held by the same parser
# (hook.lib.sh, hook_spawn_in), so it refuses exactly the prompts whose stop
# would be `unattributed`:
#   Trace-Spawn: tier=<tier> domain=<domain|none> skill=<skill> ticket=<#N|none>
# as the prompt's second line under a well-formed `Trace-Run: <run id>
# [<parent run id>]` first line, or as its first line when the session has no
# run open to hand over. Whether a run is open is not asked: the payload's cwd
# is the session's, not the checkout the run was begun in (#478), so the hook
# cannot tell, and it never refuses a spawn for lacking a Trace-Run line.
#
# NEVER IN THE WAY OF A SESSION THAT TRACES NOTHING. Tracing off, or a trace
# policy the shared script refuses, and every spawn passes: there is no trace
# for the line to attribute a stop in. A payload with no prompt it can read
# passes too — a guard that cannot read is not a guard that refuses.
#
# THE RECORD. One `note` with outcome=denied on the session, naming the rule
# and the call — the kill guard's shape (tool-pre-guard.sh). Exit 2, the agent
# harness's block status, is the only non-zero exit; its stderr goes back to
# the spawning session as the reason. Nothing is ever said on stdout.

set -u

. "$(dirname "$0")/hook.lib.sh"

hook_read

case $(hook_field tool_name) in Agent | Task) ;; *) exit 0 ;; esac

# Tracing off (1) or an ask that failed (2): never block.
hook_dir >/dev/null 2>&1 || exit 0

# The prompt's JSON-string text, its first 4096 bytes — the stop hook's bound.
# Inside a JSON string every quote is escaped, so `"prompt":"` with bare quotes
# can only be the key.
p=${hook_json#*'"prompt":"'}
if [ "$p" = "$hook_json" ]; then
	p=${hook_json#*'"prompt": "'}
	[ "$p" != "$hook_json" ] || exit 0
fi
p=$(printf '%s\n' "$p" | sed -n '1p' | cut -b 1-4096)

hook_spawn_in "$p" && exit 0

sid=$(hook_field session_id)
tuid=$(hook_field tool_use_id)
set -- kind=note harness=claude-code outcome=denied data.rule=spawn-guard
hook_id_ok "$sid" && set -- "$@" subject="session:$sid" session="$sid"
hook_id_ok "$tuid" && set -- "$@" data.tool_use_id="$tuid"
hook_trace emit "$@" reason="spawn-guard refused a spawn whose prompt carries no well-formed Trace-Spawn line"

echo "spawn-guard: refused — this spawn's prompt carries no well-formed Trace-Spawn line, so its subagent's stop would be unattributed. Open the prompt with: Trace-Spawn: tier=<planner|implementer|mechanical|reviewer> domain=<domain|none> skill=<skill> ticket=<#N|none> — exactly four fields, one space apart, a skill and a domain [a-z][a-z0-9-]*; under a 'Trace-Run: <run id> [<parent run id>]' first line when you hand the subagent a run, as the first line itself when you have none." >&2
exit 2
