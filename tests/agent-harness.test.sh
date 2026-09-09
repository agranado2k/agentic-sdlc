#!/bin/sh
# tests/agent-harness.test.sh — the AGENT HARNESS axis of tier resolution.
#
# `resolve_tier` answered "which model does this tier run on?" and assumed the
# answer to a question it never asked: which AGENT HARNESS runs it. The
# assumption was invisible while every tier ran in the caller's own session,
# and it is exactly what a cross-vendor spawn has to state (ADR-0005).
#
# The axis lives in the VALUE — `<agent harness>:<model id>` — not in a second
# variable. `AGENT_TIER_<TIER>_HARNESS` was unavailable: that is already how
# the task-domain axis folds a domain named `harness`, so the two axes would
# collide in one namespace and the resolver could not tell a project that
# mapped an agent harness from one that mapped a medium.
#
# THE LOAD-BEARING CASES ARE THE OLD ONES. scripts/agents.lib.sh is shared
# layer: it is copied verbatim into every project bootstrapped from any
# release, and most of those map bare model ids and will never declare an agent
# harness. So the first section asserts that nothing moved for them, and the
# rest only then asks what the new form does.
#
# The second load-bearing case is a colon INSIDE a model id. Splitting on the
# first colon unconditionally would invent an agent harness out of a local
# runtime's `<name>:<tag>`. The project's AGENT_HARNESSES declaration is what
# makes the split decidable, and this suite holds the resolver to leaving an
# undeclared prefix alone.
#
# Usage: sh tests/agent-harness.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$KIT/scripts/agents.lib.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

# Stand-ins, never real model identifiers: the kit names none, and neither does
# its suite. The agent-harness TOKENS are real words, because an agent harness
# name is not a model id — it is the project's own declaration, and the point of
# the fixture is that the resolver reads the declaration rather than a list it
# carries.
CONFIG_BARE=$(
	cat <<'EOF'
AGENT_TIER_PLANNER='model-for-planning'
AGENT_TIER_IMPLEMENTER='model-for-implementing'
EOF
)

CONFIG_AXIS=$(
	cat <<'EOF'
AGENT_HARNESSES='alpha beta gamma'
AGENT_TIER_PLANNER='model-for-planning'
AGENT_TIER_IMPLEMENTER='beta:model-for-implementing'
AGENT_TIER_REVIEWER='gamma:model-for-reviewing'
AGENT_TIER_MECHANICAL='alpha:'
AGENT_TIER_IMPLEMENTER_CONTENT='alpha:model-for-writing-prose'
EOF
)

# The colon that is NOT an agent harness: the `<name>:<tag>` shape a local
# runtime uses, with a prefix nobody declared.
CONFIG_COLON=$(
	cat <<'EOF'
AGENT_HARNESSES='alpha beta'
AGENT_TIER_MECHANICAL='runtime-thing:8b'
EOF
)

# A project that declared NOTHING and writes a colon anyway: the pre-axis world
# exactly, where a colon is a character in an id and there is no declaration to
# measure it against. It must stay silent.
CONFIG_COLON_UNDECLARED=$(
	cat <<'EOF'
AGENT_TIER_MECHANICAL='runtime-thing:8b'
EOF
)

write_config() {
	mkdir -p "$(dirname "$1")"
	printf '%s\n' "$2" >"$1"
}

# stdout kept SEPARATE from stderr — the whole contract is "the answer on
# stdout, diagnostics on stderr", and a caller that merged them could not tell a
# warning from a model id.
resolve() {
	R_ERR=$(mktemp "$SCRATCH/err.XXXXXX")
	R_OUT=$(sh "$LIB" "$@" 2>"$R_ERR")
	R_STATUS=$?
	R_ERR_TEXT=$(cat "$R_ERR")
	rm -f "$R_ERR"
}

assert_resolved() {
	if [ "$R_STATUS" = 0 ] && [ "$R_OUT" = "$1" ]; then
		pass "$2"
	else
		fail "$2 — expected '$1', got status $R_STATUS, stdout '$R_OUT'"
		printf '%s\n' "$R_ERR_TEXT" | sed 's/^/        | /'
	fi
}

assert_status_is() {
	if [ "$R_STATUS" = "$1" ]; then
		pass "$2"
	else
		fail "$2 — expected status $1, got $R_STATUS"
		printf '%s\n' "$R_ERR_TEXT" | sed 's/^/        | /'
	fi
}

assert_err_has() {
	case "$R_ERR_TEXT" in
	*"$1"*) pass "stderr mentions '$1'" ;;
	*)
		fail "stderr does not mention '$1'"
		printf '%s\n' "$R_ERR_TEXT" | sed 's/^/        | /'
		;;
	esac
}

assert_err_lacks() {
	case "$R_ERR_TEXT" in
	*"$1"*)
		fail "stderr should NOT mention '$1'"
		printf '%s\n' "$R_ERR_TEXT" | sed 's/^/        | /'
		;;
	*) pass "stderr does not mention '$1'" ;;
	esac
}

# ---------------------------------------------------------------------------
banner "The old contract is untouched — a project that never declared one"
# ---------------------------------------------------------------------------
CFG="$SCRATCH/bare/agents.config.sh"
write_config "$CFG" "$CONFIG_BARE"
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

resolve implementer
assert_resolved 'model-for-implementing' "a bare mapping still resolves to the model id, with no flag"
assert_err_lacks "agent harness"

resolve --model implementer
assert_resolved 'model-for-implementing' "--model is the same answer, said explicitly"

resolve --harness implementer
assert_resolved '' "a bare mapping resolves to NO agent harness — meaning the caller's own"
assert_status_is 0 "and that emptiness is a success, not a failure"

# ---------------------------------------------------------------------------
banner "The axis — a value that names an agent harness"
# ---------------------------------------------------------------------------
CFG="$SCRATCH/axis/agents.config.sh"
write_config "$CFG" "$CONFIG_AXIS"
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

resolve --harness implementer
assert_resolved 'beta' "'beta:<id>' resolves its agent harness"
resolve --model implementer
assert_resolved 'model-for-implementing' "…and its model, without the prefix"

resolve --harness reviewer
assert_resolved 'gamma' "a second tier resolves a DIFFERENT agent harness — the point of the axis"

resolve --harness planner
assert_resolved '' "a bare tier beside prefixed ones still means the caller's own agent harness"
resolve --model planner
assert_resolved 'model-for-planning' "…and still resolves its model"

# ---------------------------------------------------------------------------
banner "The two optional axes compose"
# ---------------------------------------------------------------------------
# A task domain may legitimately change the agent harness as well as the model:
# the best prose model and the best coding model need not live at one vendor.
resolve --harness implementer content
assert_resolved 'alpha' "the domain override carries its own agent harness"
resolve --model implementer content
assert_resolved 'model-for-writing-prose' "…and its own model"

resolve --harness implementer code
assert_resolved 'beta' "an UNMAPPED domain falls back to the tier's agent harness, silently"
assert_err_lacks "not a declared"

# ---------------------------------------------------------------------------
banner "An agent harness with no model resolves — unset is a working state"
# ---------------------------------------------------------------------------
# The resolver's central contract is that an unmapped thing resolves to nothing
# and the caller omits the parameter. Refusing here would make an error of the
# one case the rest of the file treats as normal (ADR-0005 clause 6), so
# `alpha:` means "that agent harness, on its own default model".
resolve --harness mechanical
assert_resolved 'alpha' "'alpha:' resolves the agent harness"
resolve --model mechanical
assert_resolved '' "…and NO model, rather than refusing"
assert_status_is 0 "which is a success"
assert_err_has "no model"

# ---------------------------------------------------------------------------
banner "A colon is legal inside a model id — the split must be decidable"
# ---------------------------------------------------------------------------
CFG="$SCRATCH/colon/agents.config.sh"
write_config "$CFG" "$CONFIG_COLON"
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

resolve --model mechanical
assert_resolved 'runtime-thing:8b' "an UNDECLARED prefix leaves the value whole — it was never an agent harness"
assert_err_has "not a declared"

resolve --harness mechanical
assert_resolved '' "…and resolves no agent harness, rather than inventing 'runtime-thing'"

CFG="$SCRATCH/colon2/agents.config.sh"
write_config "$CFG" "$CONFIG_COLON_UNDECLARED"
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

resolve --model mechanical
assert_resolved 'runtime-thing:8b' "a project that declared NO agent harness keeps its colon'd id"
assert_err_lacks "not a declared"

# ---------------------------------------------------------------------------
banner "A caller that predates the axis is told when it drops one"
# ---------------------------------------------------------------------------
CFG="$SCRATCH/axis/agents.config.sh"
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

resolve implementer
assert_resolved 'model-for-implementing' "the no-flag caller still receives the model — the contract holds"
assert_err_has "DROPPED"

resolve --model implementer
assert_err_lacks "DROPPED"

resolve --harness implementer
assert_err_lacks "DROPPED"

# ---------------------------------------------------------------------------
banner "Bad input points at the thing that is actually wrong"
# ---------------------------------------------------------------------------
resolve --harnes implementer
assert_status_is 2 "a mistyped flag is refused"
assert_err_has "unknown option"
assert_err_lacks "unknown capability tier"

resolve --harness not-a-tier
assert_status_is 2 "the closed tier vocabulary still closes, whichever half is asked for"
assert_err_has "unknown capability tier"

resolve --harness implementer NOT-A-DOMAIN
assert_status_is 2 "the domain's shape check still runs behind the flag"
assert_err_has "malformed task domain"

unset AGENTS_CONFIG
t_done "agent harness axis"
