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
# A REVIEWER SPAWN ON ANOTHER TYPE is refused too (#834), where the project
# wires a reviewer agent type: 66 of 177 reviewer-tier stops ran on wider
# types, whose Bash, Edit and Agent undo the offline reviewer contract.
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

# The prompt's JSON-string text, its first hook_prompt_bytes — the stop hook's
# bound.
# Inside a JSON string every quote is escaped, so `"prompt":"` with bare quotes
# can only be the key. The payload arrives compact (hook.lib.sh, "the
# payload"), so the key is read in that one spelling; no `"prompt":"`, no
# prompt to judge, and the spawn passes.
p=${hook_json#*'"prompt":"'}
[ "$p" != "$hook_json" ] || exit 0
p=$(printf '%s\n' "$p" | sed -n '1p' | cut -b "1-$hook_prompt_bytes")

if hook_spawn_in "$p"; then
	# A reviewer-tier spawn runs on the reviewer agent type (#834): a judging
	# context holds Read, Grep and Glob, and its parent emits the raise lines
	# it returns. Held only where the project wires that type — one that does
	# not exist is not one a session can be refused for missing. The type is
	# the payload's own key: every quote inside the prompt is escaped, so the
	# prompt cannot name it.
	[ "$hook_spawn_tier" = reviewer ] || exit 0
	[ -f "$hook_repo/.claude/agents/reviewer.md" ] || exit 0
	t=$(hook_field subagent_type)
	[ "$t" = reviewer ] && exit 0
	case $t in '' | [!a-z]* | *[!a-z0-9-]*) set -- ;; *) set -- data.agent_type="$t" ;; esac
	hook_deny spawn-guard "spawn-guard refused a tier=reviewer spawn on another agent type than reviewer" "$@"
	echo "spawn-guard: refused — a tier=reviewer spawn runs on the reviewer agent type (Read, Grep, Glob), and this one asked for '${t:-the default}'. Spawn it as the reviewer agent type, handing it its inputs as files to read; it returns its findings as raise lines and you emit them (/review-pr's LENS-RETURN.md). Work that runs a skill or spawns — the review coordinator — is planner work: stamp it tier=planner." >&2
	exit 2
fi

hook_deny spawn-guard "spawn-guard refused a spawn whose prompt carries no well-formed Trace-Spawn line"

echo "spawn-guard: refused — this spawn's prompt carries no well-formed Trace-Spawn line (or its first line is a Trace-Run line that is not well-formed, which hides the line under it), so its subagent's stop would be unattributed. Open the prompt with: Trace-Spawn: tier=<planner|implementer|mechanical|reviewer> domain=<domain|none> skill=<skill> ticket=<#N|none> — exactly four fields, one space apart, a skill and a domain [a-z][a-z0-9-]*; under a 'Trace-Run: <run id> [<parent run id>]' first line when you hand the subagent a run, as the first line itself when you have none." >&2
exit 2
