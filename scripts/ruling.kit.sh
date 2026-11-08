#!/bin/sh
# ruling.kit.sh — the kit's own ruling recorder. Kit-authoring only, never
# shipped (bootstrap.sh's KIT_ONLY list deletes it, beside scripts/risk.kit.sh).
#
# /pr-iterate's RISK.md says the plain `sh scripts/ruling.sh …`, and it has to:
# skills ship unstamped to every consumer. Typed literally in THIS repo, the
# recorder reads the trace through the shipped, empty scripts/trace.config.sh,
# finds it unconfigured and records nothing. This wrapper is the substitution
# AGENTS.md hard rule 10 names: the same arguments, with the kit's trace policy
# and the agents policy trace.kit.sh hands the trace — and RULING_SELF, so the
# `keep:` and `change:` commands `--unruled` prints name this wrapper.
AGENTS_CONFIG=$(sh scripts/agents.kit.sh --policy 2>/dev/null) && [ -n "$AGENTS_CONFIG" ] || {
	echo "x ruling.kit.sh: sh scripts/agents.kit.sh --policy named no agents policy — run from the kit's root" >&2
	exit 2
}
export AGENTS_CONFIG
RULING_SELF=scripts/ruling.kit.sh TRACE_CONFIG=scripts/trace.kit.config.sh exec sh scripts/ruling.sh "$@"
