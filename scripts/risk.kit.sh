#!/bin/sh
# risk.kit.sh — the kit's own risk rule. Kit-authoring only, never shipped
# (bootstrap.sh's KIT_ONLY list deletes it, beside scripts/trace.kit.sh).
#
# /pr-iterate says the plain `sh scripts/risk.sh …`, and it has to: skills ship
# unstamped to every consumer. Typed literally in THIS repo, the rule reads the
# trace through the shipped, empty scripts/trace.config.sh, finds it
# unconfigured, calls every area unlearned and records nothing. This wrapper is
# the substitution AGENTS.md hard rule 10 names: the same arguments, with the
# kit's trace policy and the agents policy trace.kit.sh hands the trace.
AGENTS_CONFIG=$(sh scripts/agents.kit.sh --policy 2>/dev/null) && [ -n "$AGENTS_CONFIG" ] || {
	echo "x risk.kit.sh: sh scripts/agents.kit.sh --policy named no agents policy — run from the kit's root" >&2
	exit 2
}
export AGENTS_CONFIG
TRACE_CONFIG=scripts/trace.kit.config.sh exec sh scripts/risk.sh "$@"
