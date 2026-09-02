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

# capture_in <dir> <command...> — capture, run from <dir>. The cwd is an INPUT
# to these cases (it is exactly what discovery must and must not read), so the
# runner takes it explicitly; env tweaks like `unset AGENTS_CONFIG` belong
# inside the command, where the case states them.
capture_in() {
	_ci_dir=$1
	shift
	R_ERR=$(mktemp "$SCRATCH/err.XXXXXX")
	R_OUT=$(cd "$_ci_dir" && "$@" 2>"$R_ERR")
	R_STATUS=$?
	R_ERR_TEXT=$(cat "$R_ERR")
	rm -f "$R_ERR"
}

# note <text> — a visible line that is neither a pass nor a fail.
#
# The per-shell cases below can only run against a shell that is installed.
# Silently skipping one would let a machine (or a CI image) quietly drop an
# entire axis while still printing ALL GREEN, so a skip says so out loud —
# per case here, and counted again beside the final summary, where a reader
# who only checks the last lines will actually see it.
SKIPPED=0
note() {
	printf '  --    %s\n' "$*"
	SKIPPED=$((SKIPPED + 1))
}

# SHELLS — the shells the per-shell axes below sweep.
#
# `sh` alone is the blind spot this suite had: every case above it invokes the
# library through `sh`, so nothing ever exercised a caller in bash or in zsh,
# and both differ from sh in ways this library depends on ($0 under zsh, and
# `set -e` semantics that are identical but were never checked at all).
SHELLS='sh bash zsh'

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

# …and the four names in the MESSAGES cannot be reassigned out from under the
# check. The accept-check is a literal `case` (0.6.0's fix), but a sourced
# config used to be able to reassign the module global the usage and error
# text read — so a sourcing caller whose config carried a stray assignment got
# diagnostics naming tiers that do not exist, from a resolver whose check was
# still correct. The message and the check must not be able to disagree: load
# a config that tries exactly that, then ask for an unknown tier, and every
# real name must still be on stderr.
cat >"$SCRATCH/reassign.config.sh" <<'EOF'
AGENT_TIERS='alpha beta'
AGENT_TIER_IMPLEMENTER='model-for-implementing'
EOF
capture sh -c "
	. '$LIB'
	AGENTS_CONFIG='$SCRATCH/reassign.config.sh'
	resolve_tier implementer >/dev/null 2>&1   # loads the config (memoized)
	resolve_tier no-such-tier
"
[ "$R_STATUS" = 2 ] && pass "unknown tier still exits 2 after a reassigning config loaded" ||
	fail "exited $R_STATUS, expected 2"
for _name in planner implementer mechanical reviewer; do
	case "$R_ERR_TEXT" in
	*"$_name"*) pass "the closed-vocabulary message still names '$_name'" ;;
	*) fail "after a config reassigned the old global, the message lost '$_name': the diagnostics lie while the check holds" ;;
	esac
done
case "$R_ERR_TEXT" in
*"alpha beta"*) fail "the message repeats the config's reassigned vocabulary — diagnostics follow the global, not the check" ;;
*) pass "the config's fake vocabulary never reaches the message" ;;
esac

# The USAGE text is the other converted message site, and the comment binds
# all three literal sites to move together — so it gets the same pin, or a
# regression that reintroduces a variable feeding only the usage line would
# pass every case above.
capture sh -c "
	. '$LIB'
	AGENTS_CONFIG='$SCRATCH/reassign.config.sh'
	resolve_tier implementer >/dev/null 2>&1   # loads the config (memoized)
	resolve_tier
"
[ "$R_STATUS" = 2 ] && pass "no-argument usage still exits 2 after a reassigning config loaded" ||
	fail "exited $R_STATUS, expected 2"
for _name in planner implementer mechanical reviewer; do
	case "$R_ERR_TEXT" in
	*"$_name"*) pass "the usage text still names '$_name'" ;;
	*) fail "after a config reassigned the old global, the usage text lost '$_name'" ;;
	esac
done
case "$R_ERR_TEXT" in
*"alpha beta"*) fail "the usage text repeats the config's reassigned vocabulary" ;;
*) pass "the config's fake vocabulary never reaches the usage text" ;;
esac

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

# 'CONTENT'/'Content' above only prove the shape check right in whatever locale
# invoked this suite — and that locale is typically LC_ALL=C in CI, the one
# locale where a bracket RANGE (the bug agents.lib.sh:216 warns about) would
# still look fine: `[!a-z]*` mis-collates case under en_US.UTF-8, not under C.
# So a regression back to a range passes the loop above unless the suite is run
# from an en_US.UTF-8 terminal. Pin both locales explicitly for these two
# tokens so the regression cannot ship green by accident of who runs the suite.
# en_US.UTF-8 may not be installed on a minimal CI image; skip that half rather
# than fail the suite over a missing locale.
for _at_locale in C en_US.UTF-8; do
	if [ "$_at_locale" != "C" ] && ! locale -a 2>/dev/null | grep -qi '^en_US\.utf-\?8$'; then
		continue
	fi
	for bad in CONTENT Content; do
		LC_ALL=$_at_locale resolve implementer "$bad"
		if [ "$R_STATUS" = 2 ] && [ -z "$R_OUT" ]; then
			pass "LC_ALL=$_at_locale: malformed domain '$bad' exits 2"
		else
			fail "LC_ALL=$_at_locale: malformed domain '$bad' exited $R_STATUS, stdout '$R_OUT', expected 2 and empty"
		fi
	done
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
banner "No domain argument — byte-for-byte the behaviour that shipped at 0.6.0"
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
banner "A caller running 'set -e' survives an unconfigured resolve"
# ---------------------------------------------------------------------------
# The third thing every case above the per-shell axes had in common: a shell
# with default options. Most consumer scripts and hooks run `set -e`, and under
# it a BARE call to a function that returns 1 terminates the caller before its
# status can even be read.
#
# agents_load_config returns 1 on the "no config anywhere" path — which is not
# an error, it is this kit's shipped default state. So the commonest caller, in
# the commonest project state, died before the UNMAPPED warning was ever
# printed: no value, no warning, no error, just a script that stopped.
#
# $SCRATCH is the working directory on purpose: no config beside it and no
# repository above it, which is exactly the state a resolve has to survive.
set_e_resolve() {
	R_ERR=$(mktemp "$SCRATCH/err.XXXXXX")
	R_OUT=$(cd "$SCRATCH" && unset AGENTS_CONFIG &&
		"$1" -c "set -e; . '$LIB'; resolve_tier planner; echo SURVIVED" 2>"$R_ERR")
	R_STATUS=$?
	R_ERR_TEXT=$(cat "$R_ERR")
	rm -f "$R_ERR"
}

for shell_bin in $SHELLS; do
	if ! command -v "$shell_bin" >/dev/null 2>&1; then
		note "$shell_bin is not installed here — its 'set -e' case did not run"
		continue
	fi
	set_e_resolve "$shell_bin"
	assert_survived "$shell_bin with 'set -e': an unmapped tier returns to the caller instead of killing it"
	assert_err_has "UNMAPPED"
done

# ---------------------------------------------------------------------------
banner "Where the configuration comes from"
# ---------------------------------------------------------------------------
# Every case here INSTALLS the library into the fixture rather than pointing at
# the kit's own copy from a borrowed working directory. That is not a detail:
# resolution orders 2 and 3 are anchored on where the LIBRARY lives, so a
# fixture that leaves it behind is not testing the rule it claims to.
#
# install_lib <dir> — put the library under test at <dir>/agents.lib.sh.
install_lib() {
	mkdir -p "$1"
	cp "$LIB" "$1/agents.lib.sh"
}

# resolve_from <cwd> <lib> <tier…> — run an INSTALLED library from a chosen
# working directory, with no AGENTS_CONFIG. The two are separate arguments on
# purpose: the whole trust question below is what happens when they disagree.
resolve_from() {
	_rf_cwd=$1
	_rf_lib=$2
	shift 2
	R_ERR=$(mktemp "$SCRATCH/err.XXXXXX")
	R_OUT=$(cd "$_rf_cwd" && unset AGENTS_CONFIG && sh "$_rf_lib" "$@" 2>"$R_ERR")
	R_STATUS=$?
	R_ERR_TEXT=$(cat "$R_ERR")
	rm -f "$R_ERR"
}

# Order 2 — the root of the repo the LIBRARY lives in. The library goes in
# tools/ and the config in scripts/, so that only order 2 can join them: with
# both in scripts/ the case would pass on order 3 and prove nothing.
t_repo
OWN=$REPO
install_lib "$OWN/tools"
write_config "$OWN/scripts/agents.config.sh" "$CONFIG_FULL"
resolve_from "$OWN" "$OWN/tools/agents.lib.sh" mechanical
assert_resolved "model-for-mechanical" "the repo root's scripts/agents.config.sh is found with no env var set"

# Order 3 — a sibling agents.config.sh, for a library that is not in a repo at
# all. Run from a different directory to show the answer does not depend on
# where the caller stands.
LOOSE="$SCRATCH/loose"
install_lib "$LOOSE"
write_config "$LOOSE/agents.config.sh" "$CONFIG_FULL"
resolve_from "$SCRATCH" "$LOOSE/agents.lib.sh" reviewer
assert_resolved "model-for-reviewing" "a sibling agents.config.sh is found for a library outside any repo"

# ---------------------------------------------------------------------------
banner "…and NOT from the repo the caller happens to be standing in"
# ---------------------------------------------------------------------------
# A config file is SOURCED — which is to say EXECUTED — so "where does the
# config come from" is a trust question, not a convenience one. Resolution used
# to ask `git rev-parse --show-toplevel` about the process's CURRENT DIRECTORY,
# which meant an operator resolving a tier while standing in a cloned
# third-party repo ran that clone's scripts/agents.config.sh. The root manual's
# trust boundary names cloned third-party repos as untrusted content, and
# untrusted content is data, never code to run.
#
# The fixture is the real shape of it: the operator's own project, invoked by
# absolute path, from inside somebody else's clone.
t_repo
FOREIGN=$REPO
write_config "$FOREIGN/scripts/agents.config.sh" "$(
	cat <<'EOF'
echo "FOREIGN-CONFIG-EXECUTED" >&2
AGENT_TIER_MECHANICAL='model-the-foreign-repo-chose'
EOF
)"

resolve_from "$FOREIGN" "$OWN/tools/agents.lib.sh" mechanical
assert_resolved "model-for-mechanical" "the library's own repo supplies the mapping, not the cwd's repo"
assert_err_lacks "FOREIGN-CONFIG-EXECUTED"

# The same, with no config of its own to fall back on: the answer must be
# "nothing", never the stranger's mapping.
t_repo
BARE=$REPO
install_lib "$BARE/tools"
resolve_from "$FOREIGN" "$BARE/tools/agents.lib.sh" mechanical
[ -z "$R_OUT" ] && pass "a library with no config of its own resolves to nothing in a foreign repo" ||
	fail "resolved '$R_OUT' from the cwd's repo"
assert_err_lacks "FOREIGN-CONFIG-EXECUTED"

# ---------------------------------------------------------------------------
banner "A sourcing caller that has not said where it is discovers nothing"
# ---------------------------------------------------------------------------
# The consequence of anchoring on the library rather than the cwd. A file being
# sourced cannot portably learn its own path, so a sourcing caller that sets
# neither $AGENTS_CONFIG nor $_agents_here gives the resolver nothing to anchor
# on — and the alternative to "nothing" is the cwd's repo, which is the rule
# just removed. It warns and passes, exactly like any other unmapped state.
capture_in "$OWN" sh -c "unset AGENTS_CONFIG; . ./tools/agents.lib.sh; resolve_tier mechanical"
[ "$R_STATUS" = 0 ] && [ -z "$R_OUT" ] && pass "a bare sourcing caller resolves to nothing rather than to the cwd's repo" ||
	fail "a bare sourcing caller got status $R_STATUS, stdout '$R_OUT'"
assert_err_has "UNMAPPED"

# …and saying where it is restores discovery, without ever consulting the cwd.
capture_in "$FOREIGN" sh -c "unset AGENTS_CONFIG; _agents_here='$OWN/tools'; . '$OWN/tools/agents.lib.sh'; resolve_tier mechanical"
[ "$R_OUT" = "model-for-mechanical" ] && pass "a sourcing caller that sets \$_agents_here gets its own repo's mapping" ||
	fail "a sourcing caller with \$_agents_here set printed '$R_OUT'"
assert_err_lacks "FOREIGN-CONFIG-EXECUTED"

# ---------------------------------------------------------------------------
banner "The explicit pointer, and the absence of any config at all"
# ---------------------------------------------------------------------------
# The explicit pointer wins over the library's own repo — that is what makes the
# whole thing testable in the first place.
AGENTS_CONFIG="$EMPTY"
export AGENTS_CONFIG
capture_in "$OWN" sh "$OWN/tools/agents.lib.sh" mechanical
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
resolve_from "$BARE" "$BARE/tools/agents.lib.sh" implementer
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
# ships no tier mapping: it would be naming a model. The domain half of the
# pattern allows digits too — AGENT_DOMAIN_SHAPE does — so the guard's charset
# has to match, or a token like 'code2' would evade it.
if grep -qE "^[[:space:]]*AGENT_TIER_[A-Z]+_[A-Z0-9_]+=" "$SHIPPED"; then
	fail "the shipped config assigns a domain variable — the kit ships the axis, never a mapping"
	grep -nE "^[[:space:]]*AGENT_TIER_[A-Z]+_[A-Z0-9_]+=" "$SHIPPED" | sed 's/^/        | /'
else
	pass "the shipped config assigns no domain variable"
fi

# ---------------------------------------------------------------------------
banner "The kit's own mapping — scripts/agents.kit.config.sh, never shipped"
# ---------------------------------------------------------------------------
# The kit follows its own rule (root AGENTS.md, "Capability tiers"): the
# resolver's existing $AGENTS_CONFIG seam, pointed at the kit-only mapping,
# resolves all four tiers to a real value with no UNMAPPED warning. This is
# the seam a kit session actually types:
#   AGENTS_CONFIG=scripts/agents.kit.config.sh sh scripts/agents.lib.sh <tier>
KIT_CONFIG="$KIT/scripts/agents.kit.config.sh"
[ -f "$KIT_CONFIG" ] && pass "scripts/agents.kit.config.sh exists" || fail "scripts/agents.kit.config.sh is missing"

AGENTS_CONFIG="$KIT_CONFIG"
export AGENTS_CONFIG
for tier in planner implementer mechanical reviewer; do
	resolve "$tier"
	if [ "$R_STATUS" = 0 ] && [ -n "$R_OUT" ]; then
		pass "kit config resolves '$tier' to a non-empty value ('$R_OUT')"
	else
		fail "kit config did not resolve '$tier' — status $R_STATUS, stdout '$R_OUT'"
		printf '%s\n' "$R_ERR_TEXT" | sed 's/^/        | /'
	fi
	assert_err_lacks "UNMAPPED"
done

# The kit's own SECOND axis, and the reason it has one. This repo writes two
# genuinely different kinds of artifact under a single `implementer` tier: the
# POSIX sh under scripts/ and the harness under scripts/docs-conformance/, and
# the PROSE that is most of the product — the manual, the constitution
# articles, the skills. One tier name was answering two questions.
#
# So `content` is mapped here and `code` deliberately is NOT. An unmapped
# domain falls back to the plain tier silently, which is the correct answer for
# code; writing AGENT_TIER_IMPLEMENTER_CODE to the same id the tier already
# resolves to would be a non-decision recorded as a decision — the mirror of
# the "a Domain: on every ticket" anti-pattern /to-tickets warns about.
resolve implementer
KIT_IMPLEMENTER=$R_OUT

resolve implementer content
if [ "$R_STATUS" = 0 ] && [ -n "$R_OUT" ] && [ "$R_OUT" != "$KIT_IMPLEMENTER" ]; then
	pass "kit config routes 'implementer content' ('$R_OUT') away from the plain tier ('$KIT_IMPLEMENTER')"
else
	fail "kit config did not route 'implementer content' — status $R_STATUS, stdout '$R_OUT', plain tier '$KIT_IMPLEMENTER'"
	printf '%s\n' "$R_ERR_TEXT" | sed 's/^/        | /'
fi
assert_err_lacks "UNMAPPED"

resolve implementer code
if [ "$R_STATUS" = 0 ] && [ "$R_OUT" = "$KIT_IMPLEMENTER" ]; then
	pass "kit config leaves 'implementer code' on the plain tier ('$R_OUT') — an unmapped domain is the ordinary case"
else
	fail "kit config resolved 'implementer code' to '$R_OUT', expected the plain tier's '$KIT_IMPLEMENTER'"
	printf '%s\n' "$R_ERR_TEXT" | sed 's/^/        | /'
fi
assert_err_lacks "UNMAPPED"

# The consumer-shipped file is untouched by this: it still resolves every tier
# to EMPTY. The kit names no model to consumers, even while naming one to
# itself.
AGENTS_CONFIG="$SHIPPED"
export AGENTS_CONFIG
for tier in planner implementer mechanical reviewer; do
	resolve "$tier"
	if [ "$R_STATUS" = 0 ] && [ -z "$R_OUT" ]; then
		pass "scripts/agents.config.sh (shipped) still resolves '$tier' to EMPTY"
	else
		fail "scripts/agents.config.sh (shipped) resolved '$tier' to '$R_OUT', expected empty"
	fi
	assert_err_has "UNMAPPED"
done
unset AGENTS_CONFIG

# ---------------------------------------------------------------------------
banner "The reviewer is never the implementer — the kit's mapping, and the probe (#144)"
# ---------------------------------------------------------------------------
# The policy the root manual states and ADR-0003 clause 4 defers to this
# ticket: a review from the implementer's own model is an editorial pass
# wearing a second hat. Two halves, one probe. (1) The mapping resolves
# reviewer and implementer to different models. (2) The mapping names the
# reviewer for the case the plain lookup cannot see — the session itself
# implemented, on the reviewer's model — as the domain `self-implemented`,
# and that answer differs from the reviewer's. The probe runs on the kit's
# config and then on two throwaways that break each half, so it is proven
# able to fail before it is trusted.
reviewer_rule_gaps() { # <config>
	_rg_rev=$(AGENTS_CONFIG="$1" AGENTS_QUIET=1 sh "$LIB" reviewer 2>/dev/null)
	_rg_imp=$(AGENTS_CONFIG="$1" AGENTS_QUIET=1 sh "$LIB" implementer 2>/dev/null)
	_rg_self=$(AGENTS_CONFIG="$1" AGENTS_QUIET=1 sh "$LIB" reviewer self-implemented 2>/dev/null)
	[ -n "$_rg_rev" ] && [ "$_rg_rev" = "$_rg_imp" ] &&
		echo "reviewer and implementer both map to '$_rg_rev'"
	[ -n "$_rg_rev" ] && [ "$_rg_self" = "$_rg_rev" ] &&
		echo "'reviewer self-implemented' resolves to the reviewer's own model '$_rg_rev' — no fallback for a diff the session wrote"
	return 0
}
gaps=$(reviewer_rule_gaps "$KIT_CONFIG")
[ -z "$gaps" ] &&
	pass "the kit's reviewer differs from its implementer, and 'reviewer self-implemented' differs from the reviewer" ||
	fail "the kit's own mapping breaks the reviewer rule — $gaps"
SAME="$SCRATCH/same.config.sh"
sed "s/^AGENT_TIER_REVIEWER=.*/AGENT_TIER_REVIEWER='model-for-implementing'/" "$FULL" >"$SAME"
case "$(reviewer_rule_gaps "$SAME")" in
*"both map to 'model-for-implementing'"*) pass "the probe reports a mapping where reviewer equals implementer" ;;
*) fail "the probe missed reviewer == implementer" ;;
esac
# $FULL maps no self-implemented domain, so the fallback IS the reviewer.
case "$(reviewer_rule_gaps "$FULL")" in
*"no fallback for a diff the session wrote"*) pass "the probe reports a mapping with no self-implemented answer" ;;
*) fail "the probe missed a missing self-implemented mapping" ;;
esac

# ---------------------------------------------------------------------------
banner "The kit's own wrapper — scripts/agents.kit.sh (f13 review M-2)"
# ---------------------------------------------------------------------------
# AGENTS.md hard rule 10: in this repo, `sh scripts/agents.kit.sh <tier>`
# replaces the plain `sh scripts/agents.lib.sh <tier>` a SKILL.md literally
# says, because the plain command resolves through the empty shipped config
# here too. The wrapper's whole job is setting $AGENTS_CONFIG itself, so it
# must resolve the kit's own mapping regardless of what the CALLER'S
# environment says — proved here by pointing AGENTS_CONFIG at the shipped
# (empty) file before invoking it. A pass that depended on the caller's
# environment instead of the wrapper's own assignment would be the bug this
# section exists to catch.
KIT_WRAPPER="$KIT/scripts/agents.kit.sh"
[ -f "$KIT_WRAPPER" ] && pass "scripts/agents.kit.sh exists" || fail "scripts/agents.kit.sh is missing"

AGENTS_CONFIG="$SHIPPED"
export AGENTS_CONFIG
for tier in planner implementer mechanical reviewer; do
	W_ERR=$(mktemp "$SCRATCH/wrap-err.XXXXXX")
	W_OUT=$(sh "$KIT_WRAPPER" "$tier" 2>"$W_ERR")
	W_STATUS=$?
	W_ERR_TEXT=$(cat "$W_ERR")
	rm -f "$W_ERR"
	if [ "$W_STATUS" = 0 ] && [ -n "$W_OUT" ]; then
		pass "scripts/agents.kit.sh resolves '$tier' to a non-empty value ('$W_OUT') despite AGENTS_CONFIG pointing at the shipped empty file"
	else
		fail "scripts/agents.kit.sh did not resolve '$tier' — status $W_STATUS, stdout '$W_OUT'"
		printf '%s\n' "$W_ERR_TEXT" | sed 's/^/        | /'
	fi
	case "$W_ERR_TEXT" in
	*UNMAPPED*) fail "scripts/agents.kit.sh warned UNMAPPED for '$tier' — it should have resolved" ;;
	*) pass "scripts/agents.kit.sh did not warn UNMAPPED for '$tier'" ;;
	esac
done

# The wrapper substitutes for scripts/agents.lib.sh, so it has to carry the
# WHOLE signature — including the optional domain. It forwards "$@" rather than
# a fixed one-argument form precisely so this holds, and this is the assertion
# that keeps it true: a wrapper that quietly dropped the second argument would
# still resolve every tier above and pass that entire section, while silently
# undoing the axis for every kit session that follows hard rule 10.
W_ERR=$(mktemp "$SCRATCH/wrap-err.XXXXXX")
W_PLAIN=$(sh "$KIT_WRAPPER" implementer 2>"$W_ERR")
rm -f "$W_ERR"
W_ERR=$(mktemp "$SCRATCH/wrap-err.XXXXXX")
W_OUT=$(sh "$KIT_WRAPPER" implementer content 2>"$W_ERR")
W_STATUS=$?
W_ERR_TEXT=$(cat "$W_ERR")
rm -f "$W_ERR"
if [ "$W_STATUS" = 0 ] && [ -n "$W_OUT" ] && [ "$W_OUT" != "$W_PLAIN" ]; then
	pass "scripts/agents.kit.sh passes the domain through — 'implementer content' resolves '$W_OUT', not the plain tier's '$W_PLAIN'"
else
	fail "scripts/agents.kit.sh dropped the domain — status $W_STATUS, stdout '$W_OUT', plain tier '$W_PLAIN'"
	printf '%s\n' "$W_ERR_TEXT" | sed 's/^/        | /'
fi

# …and the domain's exit codes survive the extra hop too: a malformed token is
# the resolver's error to report, and the wrapper must not swallow it.
W_ERR=$(mktemp "$SCRATCH/wrap-err.XXXXXX")
W_OUT=$(sh "$KIT_WRAPPER" implementer CONTENT 2>"$W_ERR")
W_STATUS=$?
W_ERR_TEXT=$(cat "$W_ERR")
rm -f "$W_ERR"
[ "$W_STATUS" = 2 ] && pass "scripts/agents.kit.sh propagates exit 2 for a malformed domain" ||
	fail "scripts/agents.kit.sh exited $W_STATUS for a malformed domain, expected 2"
case "$W_ERR_TEXT" in
*"malformed task domain"*) pass "scripts/agents.kit.sh propagates the resolver's diagnostic" ;;
*)
	fail "scripts/agents.kit.sh swallowed the resolver's diagnostic"
	printf '%s\n' "$W_ERR_TEXT" | sed 's/^/        | /'
	;;
esac
unset AGENTS_CONFIG

if [ "$SKIPPED" -gt 0 ]; then
	printf '  --    %s per-shell case(s) skipped above — this host proved less than a full-shell host would\n' "$SKIPPED"
fi
t_done "agents tier resolution"
