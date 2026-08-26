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

# assert_survived <label> — the caller reached the line AFTER the library call.
#
# What several cases below have to assert is not "what did it resolve" but "did
# the caller live". A library that kills the shell that sourced it fails in a
# way no value assertion can see: there is no output to compare, because there
# is no caller left to print it.
assert_survived() {
	if [ "$R_STATUS" = 0 ] && [ "$R_OUT" = "SURVIVED" ]; then
		pass "$1"
	else
		fail "$1 — got status $R_STATUS, stdout '$R_OUT'"
		printf '%s\n' "$R_ERR_TEXT" | sed 's/^/        | /'
	fi
}

# capture <command...> — run it, keeping stdout and stderr apart, exactly as
# `resolve` does. `resolve` hard-codes `sh "$LIB"`; the cases below need to pick
# the shell and to choose between executing and sourcing, so they need a runner
# that takes the whole command.
capture() {
	R_ERR=$(mktemp "$SCRATCH/err.XXXXXX")
	R_OUT=$("$@" 2>"$R_ERR")
	R_STATUS=$?
	R_ERR_TEXT=$(cat "$R_ERR")
	rm -f "$R_ERR"
}

# note <text> — a visible line that is neither a pass nor a fail.
#
# The per-shell cases below can only run against a shell that is installed.
# Silently skipping one would let a machine (or a CI image) quietly drop an
# entire axis while still printing ALL GREEN, so a skip says so out loud.
note() { printf '  --    %s\n' "$*"; }

# SHELLS — the shells the per-shell axes below sweep.
#
# `sh` alone is the blind spot this suite had: every case above it invokes the
# library through `sh`, so nothing ever exercised a caller in bash or in zsh,
# and both differ from sh in ways this library depends on ($0 under zsh, and
# `set -e` semantics that are identical but were never checked at all).
SHELLS='sh bash zsh'

FULL="$SCRATCH/full.config.sh"
EMPTY="$SCRATCH/empty.config.sh"
write_config "$FULL" "$CONFIG_FULL"
write_config "$EMPTY" "$CONFIG_EMPTY"

# ---------------------------------------------------------------------------
banner "Usage — a caller that asks nothing gets an error, not a guess"
# ---------------------------------------------------------------------------
AGENTS_CONFIG="$FULL"
export AGENTS_CONFIG

resolve
[ "$R_STATUS" = 2 ] && pass "no tier argument exits 2" || fail "no tier argument exited $R_STATUS, expected 2"
assert_err_has "usage"

resolve implementer extra
[ "$R_STATUS" = 2 ] && pass "a second argument exits 2" || fail "a second argument exited $R_STATUS, expected 2"

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
banner "The executed seam works in EVERY shell, not just sh"
# ---------------------------------------------------------------------------
# Every case above this line reaches the library through `sh`, and that is the
# blind spot. `sh scripts/agents.lib.sh <tier>` is the seam every SKILL.md
# names — an agent runs commands rather than sourcing shell libraries — but the
# operator who runs it by hand runs it in their own shell, and a project's own
# scripts run it in theirs.
#
# zsh is where that stops being theoretical: it does not word-split an unquoted
# parameter expansion (SH_WORD_SPLIT is off by default), so a membership test
# written as `for t in $AGENT_TIERS` sees ONE word there — the whole string —
# and every real tier name is reported as unknown.
AGENTS_CONFIG="$FULL"
export AGENTS_CONFIG

for shell_bin in $SHELLS; do
	if ! command -v "$shell_bin" >/dev/null 2>&1; then
		note "$shell_bin is not installed here — its direct-execution case did not run"
		continue
	fi
	capture "$shell_bin" "$LIB" implementer
	assert_resolved "model-for-implementing" "$shell_bin: running the file directly still resolves"
done

# ---------------------------------------------------------------------------
banner "…and SOURCING must not kill the caller, in every shell either"
# ---------------------------------------------------------------------------
# The other half of the same guard. The library decides "was I executed or was I
# sourced?" by looking at $0 — and $0 does not mean the same thing in every
# shell. zsh sets it to the SOURCED FILE'S path (FUNCTION_ARGZERO, on by
# default), so `source scripts/agents.lib.sh` matched the "I was executed"
# pattern: the library ran resolve_tier against the SHELL'S own arguments, and
# then `exit`ed — taking the caller's shell with it. An operator whose shell is
# zsh lost their session to a library that only claimed to define functions.
#
# Two cases, deliberately. The first is portable and runs anywhere: `sh -c CODE
# ARGV0` sets $0 to ARGV0, which puts plain sh in exactly the position zsh puts
# itself in — a file being sourced whose $0 is its own path — alongside the
# ZSH_EVAL_CONTEXT value zsh really exports there. It pins the MECHANISM on
# every machine. The second drives a real zsh and is the black-box proof. It is
# the one that can be skipped for want of a zsh, which is why it is not the
# only one.
ZSH_EVAL_CONTEXT='toplevel:file'
export ZSH_EVAL_CONTEXT
capture sh -c '. "$0"; echo SURVIVED' "$LIB"
assert_survived "a sourced library whose \$0 is its own path returns control to the caller"
unset ZSH_EVAL_CONTEXT

if command -v zsh >/dev/null 2>&1; then
	capture zsh -c "source '$LIB'; echo SURVIVED"
	assert_survived "zsh: sourcing the library does not run the CLI and does not exit the shell"

	capture zsh -c "source '$LIB'; resolve_tier reviewer"
	[ "$R_OUT" = "model-for-reviewing" ] && pass "zsh: the sourced function resolves" ||
		fail "zsh: sourced resolve_tier printed '$R_OUT', expected 'model-for-reviewing'"
else
	note "zsh is not installed here — the real-shell sourcing case did not run"
fi

capture bash -c "source '$LIB'; echo SURVIVED"
assert_survived "bash: sourcing the library returns control to the caller"

capture sh -c ". '$LIB'; echo SURVIVED"
assert_survived "sh: sourcing the library returns control to the caller"

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

t_done "agents tier resolution"
