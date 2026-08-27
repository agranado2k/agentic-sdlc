#!/bin/sh
# tests/agents-tiers.test.sh — capability-tier resolution as a SEAM.
#
# `resolve_tier <tier>` is the seam: one question ("which execution model does
# this tier run on?"), asked by a skill about to spawn a subagent, by a script,
# and by this suite. It is a function in `scripts/agents.lib.sh` AND that file
# run directly, because the primary caller is an agent following a `SKILL.md`,
# and an agent runs commands rather than sourcing shell libraries.
#
# What is asserted is the RESOLUTION, so every case drives the real library
# against a real throwaway config file — the same config-as-data seam the guards
# use, pointed at by $AGENTS_CONFIG exactly as $GUARDS_CONFIG points at theirs.
#
# The load-bearing case is the UNCONFIGURED one. A kit that shipped model
# identifiers would ship rot; a kit that hard-failed on an unmapped tier would
# be ripped out on day one. So an unmapped tier warns once, prints nothing, and
# exits 0 — "nothing configured" resolves to "inherit the session's own model".
#
# The seam has a SECOND, optional axis: `resolve_tier <tier> [domain]`. The two
# vocabularies behave oppositely on purpose, and the suite is mostly about that
# asymmetry — the tier's is closed, so an unknown one is a caller bug (exit 2);
# the domain's is open project policy, so an unmapped one is a working state
# that falls back to the tier, silently. What the domain does NOT get is a free
# pass on its shape: it is interpolated into a variable name, so anything
# outside `[a-z][a-z0-9-]*` is refused before it reaches the eval.
#
# Usage: sh tests/agents-tiers.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$KIT/scripts/agents.lib.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

# A config with every tier mapped to a recognisable stand-in. Deliberately NOT
# a real model identifier: the kit never names one, and neither does its suite.
CONFIG_FULL=$(
	cat <<'EOF'
AGENT_TIER_PLANNER='model-for-planning'
AGENT_TIER_IMPLEMENTER='model-for-implementing'
AGENT_TIER_MECHANICAL='model-for-mechanical'
AGENT_TIER_REVIEWER='model-for-reviewing'
EOF
)

CONFIG_EMPTY=$(
	cat <<'EOF'
AGENT_TIER_PLANNER=''
AGENT_TIER_IMPLEMENTER=''
AGENT_TIER_MECHANICAL=''
AGENT_TIER_REVIEWER=''
EOF
)

# The SECOND dimension. A project that has decided prose and code deserve
# different models says so here, per tier — and says nothing at all about the
# tiers and domains it has no opinion about, which is the case the fallback
# exists for.
#
# `html-report` is in here deliberately: the token vocabulary allows a hyphen
# and shell variable names do not, so the resolver has to fold one into the
# other, and a suite that only ever tried single-word domains would not notice
# which way it folded.
CONFIG_DOMAINS=$(
	cat <<'EOF'
AGENT_TIER_PLANNER=''
AGENT_TIER_IMPLEMENTER='model-for-implementing'
AGENT_TIER_MECHANICAL='model-for-mechanical'
AGENT_TIER_REVIEWER='model-for-reviewing'

AGENT_TIER_IMPLEMENTER_CONTENT='model-for-writing-prose'
AGENT_TIER_IMPLEMENTER_HTML_REPORT='model-for-writing-html'
AGENT_TIER_REVIEWER_CONTENT='model-for-reading-prose'
AGENT_TIER_PLANNER_CONTENT='model-for-planning-prose'
EOF
)

# write_config <path> <contents>
write_config() {
	mkdir -p "$(dirname "$1")"
	printf '%s\n' "$2" >"$1"
}

# R_OUT / R_ERR / R_STATUS — stdout kept SEPARATE from stderr, because the whole
# contract is "the resolved value on stdout, diagnostics on stderr". A harness
# that merged them could not tell a warning from a model id.
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
		fail "$2 — got status $R_STATUS, stdout '$R_OUT'"
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

FULL="$SCRATCH/full.config.sh"
EMPTY="$SCRATCH/empty.config.sh"
DOMAINS="$SCRATCH/domains.config.sh"
write_config "$FULL" "$CONFIG_FULL"
write_config "$EMPTY" "$CONFIG_EMPTY"
write_config "$DOMAINS" "$CONFIG_DOMAINS"

# ---------------------------------------------------------------------------
banner "Usage — a caller that asks nothing gets an error, not a guess"
# ---------------------------------------------------------------------------
AGENTS_CONFIG="$FULL"
export AGENTS_CONFIG

resolve
[ "$R_STATUS" = 2 ] && pass "no tier argument exits 2" || fail "no tier argument exited $R_STATUS, expected 2"
assert_err_has "usage"

resolve implementer content extra
[ "$R_STATUS" = 2 ] && pass "a third argument exits 2" || fail "a third argument exited $R_STATUS, expected 2"
assert_err_has "usage"

# ---------------------------------------------------------------------------
banner "The vocabulary is closed — an unknown tier is a caller bug"
# ---------------------------------------------------------------------------
# Four names, fixed by the manual layer. A typo'd or invented tier must not fall
# back to the session model: silently running 'implementor' on whatever the
# session happens to be is exactly the cost blindness this whole seam exists to
# remove. Exit 2, and say what the four names are.
resolve implementor
[ "$R_STATUS" = 2 ] && pass "an unknown tier exits 2" || fail "unknown tier exited $R_STATUS, expected 2"
assert_err_has "implementor"
assert_err_has "planner"
assert_err_has "implementer"
assert_err_has "mechanical"
assert_err_has "reviewer"
[ -z "$R_OUT" ] && pass "an unknown tier prints nothing on stdout" || fail "unknown tier printed '$R_OUT'"

resolve ""
[ "$R_STATUS" = 2 ] && pass "an empty tier exits 2" || fail "empty tier exited $R_STATUS, expected 2"

# ---------------------------------------------------------------------------
banner "Configured — every tier resolves to its mapped value"
# ---------------------------------------------------------------------------
resolve planner
assert_resolved "model-for-planning" "planner resolves to its configured model"
assert_err_lacks "UNMAPPED"

resolve implementer
assert_resolved "model-for-implementing" "implementer resolves to its configured model"

resolve mechanical
assert_resolved "model-for-mechanical" "mechanical resolves to its configured model"

resolve reviewer
assert_resolved "model-for-reviewing" "reviewer resolves to its configured model"

# ---------------------------------------------------------------------------
banner "The optional DOMAIN — same tier, different medium, different model"
# ---------------------------------------------------------------------------
# The tier says how much judgement the work is worth. It does not say what the
# work is made OF, and "write the launch announcement" and "write the retry
# logic" are the same cost/benefit shape resolving to the same model for no
# reason other than the resolver having only one axis.
#
# So a second, OPTIONAL argument: the domain. `AGENT_TIER_<TIER>_<DOMAIN>` wins
# when it is set, and the plain `AGENT_TIER_<TIER>` catches everything else.
AGENTS_CONFIG="$DOMAINS"
export AGENTS_CONFIG

resolve implementer content
assert_resolved "model-for-writing-prose" "a mapped tier+domain resolves to the domain's model"
assert_err_lacks "UNMAPPED"

resolve reviewer content
assert_resolved "model-for-reading-prose" "the domain axis is per-tier, not a single global override"

# ---------------------------------------------------------------------------
banner "An unmapped domain falls back to the tier — silently"
# ---------------------------------------------------------------------------
# The domain vocabulary is OPEN, unlike the closed four tiers: it is project
# policy, invented by whoever writes the tickets, and a project that maps only
# 'content' has not made a mistake by leaving 'code' alone. So an unmapped
# domain is a WORKING state and not a warning — it means "no special opinion
# about this medium", which is exactly what the tier mapping already answers.
# Warning about it would train people to ignore the warning that matters.
resolve implementer code
assert_resolved "model-for-implementing" "an unmapped domain falls back to the plain tier mapping"
assert_err_lacks "UNMAPPED"
[ -z "$R_ERR_TEXT" ] && pass "…and says nothing at all on stderr" ||
	fail "an unmapped domain wrote to stderr: $R_ERR_TEXT"

resolve mechanical content
assert_resolved "model-for-mechanical" "a tier with no domain mappings at all still resolves"

# The fallback is per-VARIABLE, not per-tier-having-any-domain-at-all: the tier
# below is unmapped, its domain is mapped, and the domain must still win.
resolve planner content
assert_resolved "model-for-planning-prose" "a mapped domain resolves even when the plain tier is empty"
assert_err_lacks "UNMAPPED"

# …and the mirror: unmapped tier, unmapped domain, so the ordinary unmapped-tier
# warning fires unchanged. The domain adds no second diagnostic.
resolve planner code
[ "$R_STATUS" = 0 ] && pass "an unmapped tier+domain still exits 0" || fail "unmapped tier+domain exited $R_STATUS"
[ -z "$R_OUT" ] && pass "…and prints nothing (the spawn inherits the session's model)" ||
	fail "unmapped tier+domain printed '$R_OUT'"
assert_err_has "UNMAPPED"
assert_err_has "AGENT_TIER_PLANNER"

# ---------------------------------------------------------------------------
banner "A hyphenated domain token folds to an underscore in the variable"
# ---------------------------------------------------------------------------
# `html-report` is a legal token and `AGENT_TIER_IMPLEMENTER_HTML-REPORT` is not
# a legal variable name. The fold has to be pinned, or the same config would
# work or not work depending on which half of the kit last guessed.
resolve implementer html-report
assert_resolved "model-for-writing-html" "domain 'html-report' reads AGENT_TIER_IMPLEMENTER_HTML_REPORT"

# ---------------------------------------------------------------------------
banner "The domain is INTERPOLATED into a variable name, so its shape is checked"
# ---------------------------------------------------------------------------
# Everything above ends in an `eval` of a constructed name. The tier survives
# that because its vocabulary is closed and whitelisted; the domain's is open,
# so the shape check IS the whitelist. `[a-z][a-z0-9-]*` and nothing else —
# anything that could carry a `$`, a backtick, a quote or a semicolon into the
# eval is a caller bug, exit 2, and never a silent fallback to the tier.
for bad in 'CONTENT' 'Content' '9code' 'code_x' 'code.x' 'code/x' '-code' '' \
	'a;echo pwned' 'a$(echo pwned)' 'a`echo pwned`' 'a"b' "a'b" 'a b'; do
	resolve implementer "$bad"
	if [ "$R_STATUS" = 2 ]; then
		pass "malformed domain '$bad' exits 2"
	else
		fail "malformed domain '$bad' exited $R_STATUS, expected 2"
	fi
	[ -z "$R_OUT" ] && pass "…and resolves to nothing" || fail "malformed domain '$bad' printed '$R_OUT'"
done

# The message has to name the rule, not just say no: the caller is an agent
# reading stderr, and "invalid domain" without the shape is a dead end.
resolve implementer CONTENT
assert_err_has "domain"
assert_err_has "CONTENT"

# An unknown TIER is still a caller bug even when the domain is impeccable —
# the second axis does not soften the first.
resolve implementor content
[ "$R_STATUS" = 2 ] && pass "an unknown tier with a valid domain still exits 2" ||
	fail "unknown tier with a domain exited $R_STATUS, expected 2"
assert_err_has "unknown capability tier"

# ---------------------------------------------------------------------------
banner "No domain argument — byte-for-byte the behaviour that shipped at 0.5.0"
# ---------------------------------------------------------------------------
# The whole point of making the argument optional: every existing caller — the
# skills, the adapters' worked example, a consumer's own script — keeps working
# without being touched.
resolve implementer
assert_resolved "model-for-implementing" "one argument still resolves the plain tier mapping"
assert_err_lacks "UNMAPPED"

resolve planner
[ "$R_STATUS" = 0 ] && pass "one argument on an unmapped tier still exits 0" || fail "exited $R_STATUS"
assert_err_has "UNMAPPED"

# The sourced half of the seam takes the domain too — a caller that resolves
# several tiers in one process should not have to shell out to get the second
# axis.
sourced=$(sh -c ". '$LIB'; resolve_tier implementer content" 2>/dev/null)
[ "$sourced" = "model-for-writing-prose" ] && pass "the sourced function takes a domain too" ||
	fail "sourced resolve_tier with a domain printed '$sourced'"

# ---------------------------------------------------------------------------
banner "Unconfigured — warn, print nothing, and PASS"
# ---------------------------------------------------------------------------
AGENTS_CONFIG="$EMPTY"
export AGENTS_CONFIG

resolve implementer
[ "$R_STATUS" = 0 ] && pass "an unmapped tier still exits 0" || fail "unmapped tier exited $R_STATUS, expected 0"
[ -z "$R_OUT" ] && pass "an unmapped tier prints nothing — the caller passes no model and inherits the session's" ||
	fail "unmapped tier printed '$R_OUT' instead of nothing"
assert_err_has "UNMAPPED"
assert_err_has "AGENT_TIER_IMPLEMENTER"
assert_err_has "scripts/agents.config.sh"

# ---------------------------------------------------------------------------
banner "The warning fires ONCE per process, not once per lookup"
# ---------------------------------------------------------------------------
# A decomposition resolves four tiers in a row. Four identical warnings is noise
# people learn to scroll past, and a warning nobody reads is not a warning.
warned=$(sh -c ". '$LIB'; resolve_tier planner; resolve_tier implementer; resolve_tier mechanical; resolve_tier reviewer" 2>&1 >/dev/null | grep -c "UNMAPPED")
if [ "$warned" = 1 ]; then
	pass "four unmapped lookups in one process warn exactly once"
else
	fail "four unmapped lookups warned $warned time(s), expected exactly 1"
fi

# Sourcing is the other half of the seam: the same function, no subprocess.
sourced=$(sh -c ". '$LIB'; resolve_tier planner" 2>/dev/null)
[ -z "$sourced" ] && pass "resolve_tier is available to a sourcing caller" ||
	fail "sourced resolve_tier printed '$sourced'"

AGENTS_CONFIG="$FULL"
export AGENTS_CONFIG
sourced=$(sh -c ". '$LIB'; resolve_tier reviewer" 2>/dev/null)
[ "$sourced" = "model-for-reviewing" ] && pass "the sourced function resolves a configured tier too" ||
	fail "sourced resolve_tier printed '$sourced', expected 'model-for-reviewing'"

# ---------------------------------------------------------------------------
banner "The warning has a quiet switch, for the caller that loops"
# ---------------------------------------------------------------------------
AGENTS_CONFIG="$EMPTY"
export AGENTS_CONFIG
R_ERR=$(mktemp "$SCRATCH/err.XXXXXX")
R_OUT=$(AGENTS_TIER_QUIET=1 sh "$LIB" implementer 2>"$R_ERR")
R_STATUS=$?
R_ERR_TEXT=$(cat "$R_ERR")
rm -f "$R_ERR"
[ "$R_STATUS" = 0 ] && pass "AGENTS_TIER_QUIET=1 still exits 0" || fail "quiet mode exited $R_STATUS"
assert_err_lacks "UNMAPPED"

# ---------------------------------------------------------------------------
banner "Where the configuration comes from"
# ---------------------------------------------------------------------------
resolve_in() {
	_ri_dir=$1
	shift
	R_ERR=$(mktemp "$SCRATCH/err.XXXXXX")
	R_OUT=$(cd "$_ri_dir" && unset AGENTS_CONFIG && sh "$LIB" "$@" 2>"$R_ERR")
	R_STATUS=$?
	R_ERR_TEXT=$(cat "$R_ERR")
	rm -f "$R_ERR"
}

t_repo
write_config "$REPO/scripts/agents.config.sh" "$CONFIG_FULL"
resolve_in "$REPO" mechanical
assert_resolved "model-for-mechanical" "the repo root's scripts/agents.config.sh is found with no env var set"

# The explicit pointer wins over the repo's own file — that is what makes the
# whole thing testable in the first place.
AGENTS_CONFIG="$EMPTY"
export AGENTS_CONFIG
R_ERR=$(mktemp "$SCRATCH/err.XXXXXX")
R_OUT=$(cd "$REPO" && sh "$LIB" mechanical 2>"$R_ERR")
R_STATUS=$?
R_ERR_TEXT=$(cat "$R_ERR")
rm -f "$R_ERR"
[ -z "$R_OUT" ] && pass "AGENTS_CONFIG overrides the repo-root config" ||
	fail "AGENTS_CONFIG did not override the repo-root config (got '$R_OUT')"

# A caller that NAMED a file and got a different policy silently is worse off
# than one that got an error.
AGENTS_CONFIG="$SCRATCH/no-such.config.sh"
export AGENTS_CONFIG
resolve planner
[ "$R_STATUS" = 2 ] && pass "an AGENTS_CONFIG that does not exist is an error, not a silent fallback" ||
	fail "a missing AGENTS_CONFIG exited $R_STATUS, expected 2"
assert_err_has "does not exist"

# No config file anywhere: identical to an unconfigured one. A project that has
# deleted the file is not a project that wants a hard failure on every spawn.
unset AGENTS_CONFIG
t_repo
resolve_in "$REPO" implementer
[ "$R_STATUS" = 0 ] && pass "no config file at all still exits 0" || fail "no config file exited $R_STATUS"
[ -z "$R_OUT" ] && pass "no config file resolves to nothing (session model)" || fail "no config file printed '$R_OUT'"
assert_err_has "UNMAPPED"

# ---------------------------------------------------------------------------
banner "The config the kit actually ships"
# ---------------------------------------------------------------------------
# The mirror of the guards' shipped default: every tier EMPTY, so a fresh
# project inherits a warn-and-pass resolver rather than a model identifier that
# was already stale when it was written.
SHIPPED="$KIT/scripts/agents.config.sh"
[ -f "$SHIPPED" ] && pass "scripts/agents.config.sh ships with the kit" || fail "scripts/agents.config.sh is missing"

for var in AGENT_TIER_PLANNER AGENT_TIER_IMPLEMENTER AGENT_TIER_MECHANICAL AGENT_TIER_REVIEWER; do
	if grep -q "^$var=''" "$SHIPPED" 2>/dev/null; then
		pass "$var ships empty"
	else
		fail "$var is missing or non-empty in the shipped config"
	fi
done

# Sourcing it must be enough to define all four — a config that parses but
# defines nothing would leave every tier unmapped while looking installed.
(
	# shellcheck source=/dev/null
	. "$SHIPPED"
	[ "${AGENT_TIER_PLANNER-unset}" = "unset" ] && exit 1
	[ "${AGENT_TIER_IMPLEMENTER-unset}" = "unset" ] && exit 2
	[ "${AGENT_TIER_MECHANICAL-unset}" = "unset" ] && exit 3
	[ "${AGENT_TIER_REVIEWER-unset}" = "unset" ] && exit 4
	exit 0
)
case $? in
0) pass "sourcing the shipped config defines all four tier variables" ;;
*) fail "the shipped config does not define all four tier variables" ;;
esac

# The domain axis is documented where the mapping lives, because the config is
# the only file a consumer opens when they want to change what runs on what.
assert_file_has "$SHIPPED" "AGENT_TIER_<TIER>_<DOMAIN>" \
	"the optional second axis is documented where the mapping is edited"

# …and documented ONLY. The kit ships no domain mapping for the same reason it
# ships no tier mapping: it would be naming a model.
if grep -qE "^[[:space:]]*AGENT_TIER_[A-Z]+_[A-Z_]+=" "$SHIPPED"; then
	fail "the shipped config assigns a domain variable — the kit ships the axis, never a mapping"
	grep -nE "^[[:space:]]*AGENT_TIER_[A-Z]+_[A-Z_]+=" "$SHIPPED" | sed 's/^/        | /'
else
	pass "the shipped config assigns no domain variable"
fi

t_done "agents tier resolution"
