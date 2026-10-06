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

# assert_survived <label> — the caller reached the line AFTER the library call.
#
# What several cases below have to assert is not "what did it resolve" but "did
# the caller live". A library that kills the shell that sourced it fails in a
# way no value assertion can see: there is no output to compare, because there
# is no caller left to print it.
assert_survived() {
	if [ "$S_STATUS" = 0 ] && [ "$S_OUT" = "SURVIVED" ]; then
		pass "$1"
	else
		fail "$1 — got status $S_STATUS, stdout '$S_OUT'"
		printf '%s\n' "$S_ERR" | sed 's/^/        | /'
	fi
}

# capture <command...> — t_run_split under the name this suite has always used.
# `t_resolve_tier` (tests/lib.sh) always runs scripts/agents.lib.sh with sh;
# the cases below pick the shell and choose between executing and sourcing,
# so they need the whole command.
capture() { t_run_split "$@"; }

# capture_in <dir> <command...> — capture, run from <dir>. The cwd is an INPUT
# to these cases (it is exactly what discovery must and must not read), so the
# runner takes it explicitly; env tweaks like `unset AGENTS_CONFIG` belong
# inside the command, where the case states them. The cd happens inside
# t_run_split's own subshell, so it reaches the command and nothing else.
_capture_cd() { cd "$1" && shift && "$@"; }
capture_in() {
	_ci_dir=$1
	shift
	t_run_split _capture_cd "$_ci_dir" "$@"
}

# note <text> (tests/lib.sh) — a visible line that is neither a pass nor a fail.
#
# The per-shell cases below can only run against a shell that is installed.
# Silently skipping one would let a machine (or a CI image) quietly drop an
# entire axis while still printing ALL GREEN, so a skip says so out loud —
# per case here, and counted again beside the final summary, where a reader
# who only checks the last lines will actually see it.
SKIPPED=0

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
t_write_config "$FULL" "$CONFIG_FULL"
t_write_config "$EMPTY" "$CONFIG_EMPTY"
t_write_config "$DOMAINS" "$CONFIG_DOMAINS"

# ---------------------------------------------------------------------------
banner "Usage — a caller that asks nothing gets an error, not a guess"
# ---------------------------------------------------------------------------
AGENTS_CONFIG="$FULL"
export AGENTS_CONFIG

t_resolve_tier
[ "$S_STATUS" = 2 ] && pass "no tier argument exits 2" || fail "no tier argument exited $S_STATUS, expected 2"
s_assert_err_has "usage"

t_resolve_tier implementer content extra
[ "$S_STATUS" = 2 ] && pass "a third argument exits 2" || fail "a third argument exited $S_STATUS, expected 2"
s_assert_err_has "usage"

# ---------------------------------------------------------------------------
banner "The vocabulary is closed — an unknown tier is a caller bug"
# ---------------------------------------------------------------------------
# Four names, fixed by the manual layer. A typo'd or invented tier must not fall
# back to the session model: silently running 'implementor' on whatever the
# session happens to be is exactly the cost blindness this whole seam exists to
# remove. Exit 2, and say what the four names are.
t_resolve_tier implementor
[ "$S_STATUS" = 2 ] && pass "an unknown tier exits 2" || fail "unknown tier exited $S_STATUS, expected 2"
s_assert_err_has "implementor"
s_assert_err_has "planner"
s_assert_err_has "implementer"
s_assert_err_has "mechanical"
s_assert_err_has "reviewer"
[ -z "$S_OUT" ] && pass "an unknown tier prints nothing on stdout" || fail "unknown tier printed '$S_OUT'"

t_resolve_tier ""
[ "$S_STATUS" = 2 ] && pass "an empty tier exits 2" || fail "empty tier exited $S_STATUS, expected 2"

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
[ "$S_STATUS" = 2 ] && pass "unknown tier still exits 2 after a reassigning config loaded" ||
	fail "exited $S_STATUS, expected 2"
for _name in planner implementer mechanical reviewer; do
	case "$S_ERR" in
	*"$_name"*) pass "the closed-vocabulary message still names '$_name'" ;;
	*) fail "after a config reassigned the old global, the message lost '$_name': the diagnostics lie while the check holds" ;;
	esac
done
case "$S_ERR" in
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
[ "$S_STATUS" = 2 ] && pass "no-argument usage still exits 2 after a reassigning config loaded" ||
	fail "exited $S_STATUS, expected 2"
for _name in planner implementer mechanical reviewer; do
	case "$S_ERR" in
	*"$_name"*) pass "the usage text still names '$_name'" ;;
	*) fail "after a config reassigned the old global, the usage text lost '$_name'" ;;
	esac
done
case "$S_ERR" in
*"alpha beta"*) fail "the usage text repeats the config's reassigned vocabulary" ;;
*) pass "the config's fake vocabulary never reaches the usage text" ;;
esac

# ---------------------------------------------------------------------------
banner "Configured — every tier resolves to its mapped value"
# ---------------------------------------------------------------------------
t_resolve_tier planner
s_assert_resolved "model-for-planning" "planner resolves to its configured model"
s_assert_err_lacks "UNMAPPED"

t_resolve_tier implementer
s_assert_resolved "model-for-implementing" "implementer resolves to its configured model"

t_resolve_tier mechanical
s_assert_resolved "model-for-mechanical" "mechanical resolves to its configured model"

t_resolve_tier reviewer
s_assert_resolved "model-for-reviewing" "reviewer resolves to its configured model"

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

t_resolve_tier implementer content
s_assert_resolved "model-for-writing-prose" "a mapped tier+domain resolves to the domain's model"
s_assert_err_lacks "UNMAPPED"

t_resolve_tier reviewer content
s_assert_resolved "model-for-reading-prose" "the domain axis is per-tier, not a single global override"

# ---------------------------------------------------------------------------
banner "An unmapped domain falls back to the tier — silently"
# ---------------------------------------------------------------------------
# The domain vocabulary is OPEN, unlike the closed four tiers: it is project
# policy, invented by whoever writes the tickets, and a project that maps only
# 'content' has not made a mistake by leaving 'code' alone. So an unmapped
# domain is a WORKING state and not a warning — it means "no special opinion
# about this medium", which is exactly what the tier mapping already answers.
# Warning about it would train people to ignore the warning that matters.
t_resolve_tier implementer code
s_assert_resolved "model-for-implementing" "an unmapped domain falls back to the plain tier mapping"
s_assert_err_lacks "UNMAPPED"
[ -z "$S_ERR" ] && pass "…and says nothing at all on stderr" ||
	fail "an unmapped domain wrote to stderr: $S_ERR"

t_resolve_tier mechanical content
s_assert_resolved "model-for-mechanical" "a tier with no domain mappings at all still resolves"

# The fallback is per-VARIABLE, not per-tier-having-any-domain-at-all: the tier
# below is unmapped, its domain is mapped, and the domain must still win.
t_resolve_tier planner content
s_assert_resolved "model-for-planning-prose" "a mapped domain resolves even when the plain tier is empty"
s_assert_err_lacks "UNMAPPED"

# …and the mirror: unmapped tier, unmapped domain, so the ordinary unmapped-tier
# warning fires unchanged. The domain adds no second diagnostic.
t_resolve_tier planner code
[ "$S_STATUS" = 0 ] && pass "an unmapped tier+domain still exits 0" || fail "unmapped tier+domain exited $S_STATUS"
[ -z "$S_OUT" ] && pass "…and prints nothing (the spawn inherits the session's model)" ||
	fail "unmapped tier+domain printed '$S_OUT'"
s_assert_err_has "UNMAPPED"
s_assert_err_has "AGENT_TIER_PLANNER"

# ---------------------------------------------------------------------------
banner "A hyphenated domain token folds to an underscore in the variable"
# ---------------------------------------------------------------------------
# `html-report` is a legal token and `AGENT_TIER_IMPLEMENTER_HTML-REPORT` is not
# a legal variable name. The fold has to be pinned, or the same config would
# work or not work depending on which half of the kit last guessed.
t_resolve_tier implementer html-report
s_assert_resolved "model-for-writing-html" "domain 'html-report' reads AGENT_TIER_IMPLEMENTER_HTML_REPORT"

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
	t_resolve_tier implementer "$bad"
	if [ "$S_STATUS" = 2 ]; then
		pass "malformed domain '$bad' exits 2"
	else
		fail "malformed domain '$bad' exited $S_STATUS, expected 2"
	fi
	[ -z "$S_OUT" ] && pass "…and resolves to nothing" || fail "malformed domain '$bad' printed '$S_OUT'"
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
		LC_ALL=$_at_locale t_resolve_tier implementer "$bad"
		if [ "$S_STATUS" = 2 ] && [ -z "$S_OUT" ]; then
			pass "LC_ALL=$_at_locale: malformed domain '$bad' exits 2"
		else
			fail "LC_ALL=$_at_locale: malformed domain '$bad' exited $S_STATUS, stdout '$S_OUT', expected 2 and empty"
		fi
	done
done

# The message has to name the rule, not just say no: the caller is an agent
# reading stderr, and "invalid domain" without the shape is a dead end.
t_resolve_tier implementer CONTENT
s_assert_err_has "domain"
s_assert_err_has "CONTENT"

# An unknown TIER is still a caller bug even when the domain is impeccable —
# the second axis does not soften the first.
t_resolve_tier implementor content
[ "$S_STATUS" = 2 ] && pass "an unknown tier with a valid domain still exits 2" ||
	fail "unknown tier with a domain exited $S_STATUS, expected 2"
s_assert_err_has "unknown capability tier"

# ---------------------------------------------------------------------------
banner "No domain argument — byte-for-byte the behaviour that shipped at 0.6.0"
# ---------------------------------------------------------------------------
# The whole point of making the argument optional: every existing caller — the
# skills, the adapters' worked example, a consumer's own script — keeps working
# without being touched.
t_resolve_tier implementer
s_assert_resolved "model-for-implementing" "one argument still resolves the plain tier mapping"
s_assert_err_lacks "UNMAPPED"

t_resolve_tier planner
[ "$S_STATUS" = 0 ] && pass "one argument on an unmapped tier still exits 0" || fail "exited $S_STATUS"
s_assert_err_has "UNMAPPED"

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

t_resolve_tier implementer
[ "$S_STATUS" = 0 ] && pass "an unmapped tier still exits 0" || fail "unmapped tier exited $S_STATUS, expected 0"
[ -z "$S_OUT" ] && pass "an unmapped tier prints nothing — the caller passes no model and inherits the session's" ||
	fail "unmapped tier printed '$S_OUT' instead of nothing"
s_assert_err_has "UNMAPPED"
s_assert_err_has "AGENT_TIER_IMPLEMENTER"
s_assert_err_has "scripts/agents.config.sh"

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
capture env AGENTS_TIER_QUIET=1 sh "$LIB" implementer
[ "$S_STATUS" = 0 ] && pass "AGENTS_TIER_QUIET=1 still exits 0" || fail "quiet mode exited $S_STATUS"
s_assert_err_lacks "UNMAPPED"

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
	s_assert_resolved "model-for-implementing" "$shell_bin: running the file directly still resolves"
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
	[ "$S_OUT" = "model-for-reviewing" ] && pass "zsh: the sourced function resolves" ||
		fail "zsh: sourced resolve_tier printed '$S_OUT', expected 'model-for-reviewing'"
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
_set_e_body() { cd "$SCRATCH" && unset AGENTS_CONFIG && "$1" -c "set -e; . '$LIB'; resolve_tier planner; echo SURVIVED"; }
set_e_resolve() { t_run_split _set_e_body "$1"; }

for shell_bin in $SHELLS; do
	if ! command -v "$shell_bin" >/dev/null 2>&1; then
		note "$shell_bin is not installed here — its 'set -e' case did not run"
		continue
	fi
	set_e_resolve "$shell_bin"
	assert_survived "$shell_bin with 'set -e': an unmapped tier returns to the caller instead of killing it"
	s_assert_err_has "UNMAPPED"
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
_resolve_from_body() { _rf_cwd=$1; _rf_lib=$2; shift 2; cd "$_rf_cwd" && unset AGENTS_CONFIG && sh "$_rf_lib" "$@"; }
resolve_from() { t_run_split _resolve_from_body "$@"; }

# Order 2 — the root of the repo the LIBRARY lives in. The library goes in
# tools/ and the config in scripts/, so that only order 2 can join them: with
# both in scripts/ the case would pass on order 3 and prove nothing.
t_repo
OWN=$REPO
install_lib "$OWN/tools"
t_write_config "$OWN/scripts/agents.config.sh" "$CONFIG_FULL"
resolve_from "$OWN" "$OWN/tools/agents.lib.sh" mechanical
s_assert_resolved "model-for-mechanical" "the repo root's scripts/agents.config.sh is found with no env var set"

# Order 3 — a sibling agents.config.sh, for a library that is not in a repo at
# all. Run from a different directory to show the answer does not depend on
# where the caller stands.
LOOSE="$SCRATCH/loose"
install_lib "$LOOSE"
t_write_config "$LOOSE/agents.config.sh" "$CONFIG_FULL"
resolve_from "$SCRATCH" "$LOOSE/agents.lib.sh" reviewer
s_assert_resolved "model-for-reviewing" "a sibling agents.config.sh is found for a library outside any repo"

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
t_write_config "$FOREIGN/scripts/agents.config.sh" "$(
	cat <<'EOF'
echo "FOREIGN-CONFIG-EXECUTED" >&2
AGENT_TIER_MECHANICAL='model-the-foreign-repo-chose'
EOF
)"

resolve_from "$FOREIGN" "$OWN/tools/agents.lib.sh" mechanical
s_assert_resolved "model-for-mechanical" "the library's own repo supplies the mapping, not the cwd's repo"
s_assert_err_lacks "FOREIGN-CONFIG-EXECUTED"

# The same, with no config of its own to fall back on: the answer must be
# "nothing", never the stranger's mapping.
t_repo
BARE=$REPO
install_lib "$BARE/tools"
resolve_from "$FOREIGN" "$BARE/tools/agents.lib.sh" mechanical
[ -z "$S_OUT" ] && pass "a library with no config of its own resolves to nothing in a foreign repo" ||
	fail "resolved '$S_OUT' from the cwd's repo"
s_assert_err_lacks "FOREIGN-CONFIG-EXECUTED"

# ---------------------------------------------------------------------------
banner "A sourcing caller that has not said where it is discovers nothing"
# ---------------------------------------------------------------------------
# The consequence of anchoring on the library rather than the cwd. A file being
# sourced cannot portably learn its own path, so a sourcing caller that sets
# neither $AGENTS_CONFIG nor $_agents_here gives the resolver nothing to anchor
# on — and the alternative to "nothing" is the cwd's repo, which is the rule
# just removed. It warns and passes, exactly like any other unmapped state.
capture_in "$OWN" sh -c "unset AGENTS_CONFIG; . ./tools/agents.lib.sh; resolve_tier mechanical"
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && pass "a bare sourcing caller resolves to nothing rather than to the cwd's repo" ||
	fail "a bare sourcing caller got status $S_STATUS, stdout '$S_OUT'"
s_assert_err_has "UNMAPPED"

# …and saying where it is restores discovery, without ever consulting the cwd.
capture_in "$FOREIGN" sh -c "unset AGENTS_CONFIG; _agents_here='$OWN/tools'; . '$OWN/tools/agents.lib.sh'; resolve_tier mechanical"
[ "$S_OUT" = "model-for-mechanical" ] && pass "a sourcing caller that sets \$_agents_here gets its own repo's mapping" ||
	fail "a sourcing caller with \$_agents_here set printed '$S_OUT'"
s_assert_err_lacks "FOREIGN-CONFIG-EXECUTED"

# ---------------------------------------------------------------------------
banner "The explicit pointer, and the absence of any config at all"
# ---------------------------------------------------------------------------
# The explicit pointer wins over the library's own repo — that is what makes the
# whole thing testable in the first place.
AGENTS_CONFIG="$EMPTY"
export AGENTS_CONFIG
capture_in "$OWN" sh "$OWN/tools/agents.lib.sh" mechanical
[ -z "$S_OUT" ] && pass "AGENTS_CONFIG overrides the repo-root config" ||
	fail "AGENTS_CONFIG did not override the repo-root config (got '$S_OUT')"

# A caller that NAMED a file and got a different policy silently is worse off
# than one that got an error.
AGENTS_CONFIG="$SCRATCH/no-such.config.sh"
export AGENTS_CONFIG
t_resolve_tier planner
[ "$S_STATUS" = 2 ] && pass "an AGENTS_CONFIG that does not exist is an error, not a silent fallback" ||
	fail "a missing AGENTS_CONFIG exited $S_STATUS, expected 2"
s_assert_err_has "does not exist"

# No config file anywhere: identical to an unconfigured one. A project that has
# deleted the file is not a project that wants a hard failure on every spawn.
unset AGENTS_CONFIG
resolve_from "$BARE" "$BARE/tools/agents.lib.sh" implementer
[ "$S_STATUS" = 0 ] && pass "no config file at all still exits 0" || fail "no config file exited $S_STATUS"
[ -z "$S_OUT" ] && pass "no config file resolves to nothing (session model)" || fail "no config file printed '$S_OUT'"
s_assert_err_has "UNMAPPED"

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
# The kit follows its own rule (docs/capability-tiers.md, ADR-0014): the
# resolver's existing $AGENTS_CONFIG seam, pointed at the kit-only mapping,
# resolves all four tiers to a real value with no UNMAPPED warning. This is
# the seam a kit session actually types:
#   AGENTS_CONFIG=scripts/agents.kit.config.sh sh scripts/agents.lib.sh <tier>
KIT_CONFIG="$KIT/scripts/agents.kit.config.sh"
[ -f "$KIT_CONFIG" ] && pass "scripts/agents.kit.config.sh exists" || fail "scripts/agents.kit.config.sh is missing"
# Its vocabulary header points where the tier words are defined for the kit:
# the kit-own article they moved to (ADR-0014), not the root's section.
assert_file_has "$KIT_CONFIG" "docs/capability-tiers.md" "the kit config's vocabulary header points at the kit's tiers article"

AGENTS_CONFIG="$KIT_CONFIG"
export AGENTS_CONFIG
for tier in planner implementer mechanical reviewer; do
	t_resolve_tier "$tier"
	if [ "$S_STATUS" = 0 ] && [ -n "$S_OUT" ]; then
		pass "kit config resolves '$tier' to a non-empty value ('$S_OUT')"
	else
		fail "kit config did not resolve '$tier' — status $S_STATUS, stdout '$S_OUT'"
		printf '%s\n' "$S_ERR" | sed 's/^/        | /'
	fi
	s_assert_err_lacks "UNMAPPED"
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
t_resolve_tier implementer
KIT_IMPLEMENTER=$S_OUT

t_resolve_tier implementer content
if [ "$S_STATUS" = 0 ] && [ -n "$S_OUT" ] && [ "$S_OUT" != "$KIT_IMPLEMENTER" ]; then
	pass "kit config routes 'implementer content' ('$S_OUT') away from the plain tier ('$KIT_IMPLEMENTER')"
else
	fail "kit config did not route 'implementer content' — status $S_STATUS, stdout '$S_OUT', plain tier '$KIT_IMPLEMENTER'"
	printf '%s\n' "$S_ERR" | sed 's/^/        | /'
fi
s_assert_err_lacks "UNMAPPED"

t_resolve_tier implementer code
if [ "$S_STATUS" = 0 ] && [ "$S_OUT" = "$KIT_IMPLEMENTER" ]; then
	pass "kit config leaves 'implementer code' on the plain tier ('$S_OUT') — an unmapped domain is the ordinary case"
else
	fail "kit config resolved 'implementer code' to '$S_OUT', expected the plain tier's '$KIT_IMPLEMENTER'"
	printf '%s\n' "$S_ERR" | sed 's/^/        | /'
fi
s_assert_err_lacks "UNMAPPED"

# ---------------------------------------------------------------------------
banner "The judge domain — named by its contract, mapped by nobody (#275)"
# ---------------------------------------------------------------------------
# A judgment's cost ladder has a middle rung between a deterministic script
# and the session's model: a typed judge — state and typed questions in, typed
# answers with per-option probabilities out. The kit names that rung as a TASK
# DOMAIN, `judge` on the `mechanical` tier, and not as a fifth tier: the tier
# vocabulary is closed (ADR-0003) and a judge is a medium, not a size of work.
# ADR-0010 is the record, and it states two shapes — decide, among supplied
# options; rank-or-verify, over supplied candidates — and the negative: a
# decider is never handed a verification, and no typed judge takes the review
# verdict.
#
# The resolver needs no change for any of that — an unmapped domain already
# falls back to its tier in silence — so the first two cases PIN the seam: a
# consumer who maps AGENT_TIER_MECHANICAL_JUDGE gets their mapping, and one
# who has not decided is exactly where they were, the plain tier, with not a
# word on stderr beyond the fallback's own, which is nothing.
JUDGE="$SCRATCH/judge.config.sh"
t_write_config "$JUDGE" "$CONFIG_DOMAINS
AGENT_TIER_MECHANICAL_JUDGE='model-for-typed-judging'"

AGENTS_CONFIG="$DOMAINS"
export AGENTS_CONFIG
t_resolve_tier mechanical judge
s_assert_resolved "model-for-mechanical" "unmapped, 'mechanical judge' resolves to the plain tier's answer"
[ -z "$S_ERR" ] && pass "…and says nothing on stderr — the domain fallback's own silence, and no more" ||
	fail "unmapped 'mechanical judge' wrote to stderr: $S_ERR"

AGENTS_CONFIG="$JUDGE"
export AGENTS_CONFIG
t_resolve_tier mechanical judge
s_assert_resolved "model-for-typed-judging" "mapped in a throwaway policy file, 'mechanical judge' resolves to the mapping"
s_assert_err_lacks "UNMAPPED"
t_resolve_tier mechanical
s_assert_resolved "model-for-mechanical" "…and the plain tier is untouched by the judge mapping"

# The kit's own mapping DECLINES the domain, and says so. The kit names no
# model to a consumer by rule, and a typed judge weeks old on a price nobody
# has proven is the fastest-rotting identifier there is. Declining is a
# decision the resolver's silence would not record, so each kit policy file
# carries it as a comment that names the variable — and never assigns it.
AGENTS_CONFIG="$KIT_CONFIG"
export AGENTS_CONFIG
t_resolve_tier mechanical
KIT_MECHANICAL=$S_OUT
t_resolve_tier mechanical judge
if [ "$S_STATUS" = 0 ] && [ "$S_OUT" = "$KIT_MECHANICAL" ]; then
	pass "kit config leaves 'mechanical judge' on the plain tier ('$S_OUT') — declined, not mapped"
else
	fail "kit config resolved 'mechanical judge' to '$S_OUT' (status $S_STATUS), expected the plain tier's '$KIT_MECHANICAL'"
	printf '%s\n' "$S_ERR" | sed 's/^/        | /'
fi
[ -z "$S_ERR" ] && pass "…silently" || fail "'mechanical judge' on the kit config wrote to stderr: $S_ERR"

for policy in scripts/agents.kit.config.sh scripts/agents.kit.codex.config.sh; do
	grep -q '^[[:space:]]*AGENT_TIER_MECHANICAL_JUDGE=' "$KIT/$policy" &&
		fail "$policy assigns AGENT_TIER_MECHANICAL_JUDGE — the kit named a judge" ||
		pass "$policy assigns no AGENT_TIER_MECHANICAL_JUDGE"
	# The comment block that names the variable is the decision; it has to say
	# the reason in the kit's own words, or it is a TODO wearing a comment.
	# ADR-0010 clause 6 asks for those words exactly — "the kit names no
	# model" — so the probe holds the twins to them, not to a looser "names
	# no". The block is the run of comment lines from the first one naming the
	# variable to the next non-comment line (or EOF): a sed range, because awk's
	# paragraph mode is not the same awk everywhere.
	if sed -n '/^#.*AGENT_TIER_MECHANICAL_JUDGE/,/^[^#]/p' "$KIT/$policy" | grep -q 'names no model'; then
		pass "$policy declines AGENT_TIER_MECHANICAL_JUDGE in so many words"
	else
		fail "$policy does not decline AGENT_TIER_MECHANICAL_JUDGE in a comment saying the kit names no model — an omission, not a decision"
	fi
done

# The prose is the other half of the slice: the manual and the template
# describe the domain by its CONTRACT and name both shapes; the glossary's
# task-domain entry names them; the decision record is indexed and says the
# negative in so many words, citing the measurement behind it. Prose wraps,
# so each text is folded to one line before a phrase is looked for —
# assert_file_has is grep -F against a file and cannot see across a wrap.
says() { # <folded text> <phrase> <what the text is, for the label>
	case "$1" in
	*"$2"*) pass "$3 says $2" ;;
	*) fail "$3 does not say $2" ;;
	esac
}
# The kit's tier practice left its root for the kit-own article the root points
# at (ADR-0014), so for the kit that article is the tiers text; a consumer's
# stays in its manual's section.
for manual in docs/capability-tiers.md constitution/AGENTS.md.template; do
	case $manual in
	docs/*) tiers=$(tr '\n' ' ' <"$KIT/$manual") ;;
	*) tiers=$(sed -n '/^## Capability tiers/,/^## /p' "$KIT/$manual" | tr '\n' ' ') ;;
	esac
	for phrase in '`judge`' 'decide' 'rank-or-verify' 'per-option probabilities' 'never handed a verification' 'review verdict'; do
		says "$tiers" "$phrase" "$manual's tiers section"
	done
done
entry=$(awk '/^- \*\*Task domain\*\*/ { on = 1; print; next } on && /^- \*\*/ { exit } on { print }' "$KIT/docs/domain-glossary.md" | tr '\n' ' ')
for phrase in '`judge`' 'decide' 'rank-or-verify'; do
	says "$entry" "$phrase" "the glossary's task-domain entry"
done
# The shell's own glob answers this; an unmatched pattern stays literal, and
# the -f guard is what turns that into "no record".
for record in "$KIT"/docs/adr/[0-9][0-9][0-9][0-9]-*judge*.md; do break; done
if [ -f "$record" ]; then
	pass "a decision record for the judge domain exists ($(basename "$record"))"
	grep -qF "$(basename "$record")" "$KIT/docs/adr/INDEX.md" &&
		pass "…and docs/adr/INDEX.md indexes it" || fail "docs/adr/INDEX.md has no row for $(basename "$record")"
	folded=$(tr '\n' ' ' <"$record")
	for phrase in 'fifth tier' 'decide' 'rank-or-verify' 'never handed a verification' 'review verdict' 'view.centaurspec.com/oNa-l6LtDR'; do
		says "$folded" "$phrase" "the judge record"
	done
else
	fail "no decision record for the judge domain under docs/adr/ — the domain is a claim"
fi

# The consumer-shipped file is untouched by this: it still resolves every tier
# to EMPTY. The kit names no model to consumers, even while naming one to
# itself.
AGENTS_CONFIG="$SHIPPED"
export AGENTS_CONFIG
for tier in planner implementer mechanical reviewer; do
	t_resolve_tier "$tier"
	if [ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ]; then
		pass "scripts/agents.config.sh (shipped) still resolves '$tier' to EMPTY"
	else
		fail "scripts/agents.config.sh (shipped) resolved '$tier' to '$S_OUT', expected empty"
	fi
	s_assert_err_has "UNMAPPED"
done
unset AGENTS_CONFIG

# ---------------------------------------------------------------------------
banner "The reviewer is never the implementer — the kit's mapping, and the probe (#144)"
# ---------------------------------------------------------------------------
# The policy the root manual states, and which the review of PR #140 (H-1)
# deferred to this ticket: a review from the implementer's own model is an editorial pass
# wearing a second hat. Two halves, one probe. (1) The mapping resolves
# reviewer and implementer to different models. (2) The mapping names the
# reviewer for the case the plain lookup cannot see — the session itself
# implemented, on the reviewer's model — as the domain `self-implemented`,
# and that answer differs from the reviewer's. The probe runs on the kit's
# config and then on two throwaways that break each half, so it is proven
# able to fail before it is trusted.
reviewer_rule_gaps() { # <config>
	_rg_rev=$(AGENTS_CONFIG="$1" sh "$LIB" reviewer 2>/dev/null)
	_rg_imp=$(AGENTS_CONFIG="$1" sh "$LIB" implementer 2>/dev/null)
	_rg_self=$(AGENTS_CONFIG="$1" sh "$LIB" reviewer self-implemented 2>/dev/null)
	[ -z "$_rg_rev" ] &&
		echo "the reviewer tier is unmapped — the rule has nothing to compare"
	[ -n "$_rg_rev" ] && [ "$_rg_rev" = "$_rg_imp" ] &&
		echo "reviewer and implementer both map to '$_rg_rev'"
	[ -n "$_rg_rev" ] && [ "$_rg_self" = "$_rg_rev" ] &&
		echo "'reviewer self-implemented' resolves to the reviewer's own model '$_rg_rev' — no fallback for a diff the session wrote"
	return 0
}
gaps=$(reviewer_rule_gaps "$KIT_CONFIG")
[ -z "$gaps" ] &&
	pass "the kit's reviewer differs from its implementer, and 'reviewer self-implemented' differs from the reviewer" ||
	fail "the kit's own mapping breaks the reviewer rule — $(printf '%s' "$gaps" | tr '\n' ';')"
# The answers the kit's Claude Code policy has to give (#423, #546). Plain,
# with no session named, the reviewer is the content model, never the
# implementer's. The `self-implemented` answer is a model NO session tier
# runs on (ADR-0007, amended 2026-10-05): with two session models — the code
# model and the content model — one fixed answer can differ from both only if
# it is a third, and only then is it right for a session that never says what
# it runs on, or says it in a word the policy does not use. ADR-0007's
# refusal stays the net; it is no longer the route the common case takes.
_k_imp=$(AGENTS_CONFIG="$KIT_CONFIG" sh "$LIB" implementer 2>/dev/null)
_k_con=$(AGENTS_CONFIG="$KIT_CONFIG" sh "$LIB" implementer content 2>/dev/null)
_k_rev=$(AGENTS_CONFIG="$KIT_CONFIG" sh "$LIB" reviewer 2>/dev/null)
_k_self=$(AGENTS_CONFIG="$KIT_CONFIG" sh "$LIB" reviewer self-implemented 2>/dev/null)
[ -n "$_k_rev" ] && [ "$_k_rev" = "$_k_con" ] && [ "$_k_rev" != "$_k_imp" ] &&
	pass "the kit's plain reviewer is the content model '$_k_con', not the implementer's '$_k_imp'" ||
	fail "the kit's plain reviewer is '$_k_rev' — expected the content model '$_k_con', differing from the implementer '$_k_imp'"
_k_clash=
for _k_spec in planner implementer mechanical 'implementer content'; do
	# shellcheck disable=SC2086 # the tier and its optional domain, split on purpose
	_k_ses=$(AGENTS_CONFIG="$KIT_CONFIG" sh "$LIB" $_k_spec 2>/dev/null)
	[ -n "$_k_ses" ] && [ "$_k_ses" = "$_k_self" ] && _k_clash="$_k_clash '$_k_spec'"
done
[ -n "$_k_self" ] && [ -z "$_k_clash" ] &&
	pass "with no session named, 'reviewer self-implemented' is '$_k_self' — a model no session tier runs on" ||
	fail "with no session named, 'reviewer self-implemented' is '${_k_self:-nothing}' — the model of a session tier:${_k_clash:- none, it is unmapped}"
# The two session models the reviewer rule is about each get that answer as it
# stands: nothing to refuse, so nothing to fall back from, and nothing on stderr.
for _k_ses in "$_k_con" "$_k_imp"; do
	_k_out=$(env AGENTS_CONFIG="$KIT_CONFIG" AGENT_SESSION_MODEL="$_k_ses" sh "$LIB" reviewer self-implemented 2>/dev/null)
	_k_err=$(env AGENTS_CONFIG="$KIT_CONFIG" AGENT_SESSION_MODEL="$_k_ses" sh "$LIB" reviewer self-implemented 2>&1 >/dev/null)
	[ -n "$_k_out" ] && [ "$_k_out" = "$_k_self" ] && [ -z "$_k_err" ] &&
		pass "on a '$_k_ses' session, 'reviewer self-implemented' is '$_k_self' with no refusal to fall back from" ||
		fail "on a '$_k_ses' session, 'reviewer self-implemented' gave '$_k_out' (stderr: '$_k_err') — expected '$_k_self', unrefused"
done
# A session that names itself by its spawn word rather than the policy's
# pinned id matches nothing in ADR-0007's exact comparison, so the refusal
# cannot catch it — and it must still not be handed its own model. That is
# the case a third model exists for (#546).
_k_word=$(env -u AGENT_HARNESS_SELF -u AGENTS_CONFIG -C "$KIT" sh scripts/agents.kit.sh --alias implementer 2>/dev/null)
_k_ans=$(env AGENTS_CONFIG="$KIT_CONFIG" AGENT_SESSION_MODEL="$_k_word" sh "$LIB" reviewer self-implemented 2>/dev/null)
[ -n "$_k_word" ] && [ "$_k_word" != "$_k_imp" ] && [ -n "$_k_ans" ] && [ "$_k_ans" != "$_k_imp" ] &&
	pass "a session named by its spawn word '$_k_word' still gets '$_k_ans', not the implementer's '$_k_imp'" ||
	fail "a session named by its spawn word '$_k_word' got '${_k_ans:-nothing}' — the implementer's own model '$_k_imp', or nothing"
# Every model the policy maps can be a session's, so every one is asked: the
# self-implemented form never answers the session's own model, and the plain
# form either answers another model or nothing at all — never the session's.
for _k_tier in planner implementer mechanical; do
	_k_ses=$(AGENTS_CONFIG="$KIT_CONFIG" sh "$LIB" "$_k_tier" 2>/dev/null)
	[ -n "$_k_ses" ] || continue
	_k_ans=$(env AGENTS_CONFIG="$KIT_CONFIG" AGENT_SESSION_MODEL="$_k_ses" sh "$LIB" reviewer self-implemented 2>/dev/null)
	[ -n "$_k_ans" ] && [ "$_k_ans" != "$_k_ses" ] &&
		pass "on a '$_k_ses' session ($_k_tier), 'reviewer self-implemented' answers '$_k_ans', not the session's own" ||
		fail "on a '$_k_ses' session ($_k_tier), 'reviewer self-implemented' gave '$_k_ans' — the review shares the author's model, or names none"
	_k_ans=$(env AGENTS_CONFIG="$KIT_CONFIG" AGENT_SESSION_MODEL="$_k_ses" sh "$LIB" reviewer 2>/dev/null)
	[ "$_k_ans" != "$_k_ses" ] &&
		pass "on a '$_k_ses' session ($_k_tier), plain 'reviewer' answers '${_k_ans:-nothing}', never the session's own" ||
		fail "on a '$_k_ses' session ($_k_tier), plain 'reviewer' answered the session's own model '$_k_ans'"
done
# THE KIT'S FALLBACK (#548, ADR-0013 clause 5). The mapping names one, and no
# answer on the walk is ever a session's own model: for every session tier,
# each answer the walk gives is named unreachable in turn until the list is
# spent, and not one of those answers is the session's model. And every
# in-session entry on the list — one with no agent harness — is no session
# tier's model and shares no session tier's spawn word, so a session named by
# its spawn word, or not named at all, is never handed itself from the list.
_k_fb=$(. "$KIT_CONFIG"; printf '%s' "${AGENT_TIER_REVIEWER_FALLBACK:-}")
[ -n "$_k_fb" ] &&
	pass "the kit's mapping names a reviewer fallback ('$_k_fb')" ||
	fail "the kit's mapping names no AGENT_TIER_REVIEWER_FALLBACK — one outage still ends in a hand-picked reviewer"
_k_walk_bad=
for _k_spec in planner implementer mechanical 'implementer content'; do
	# shellcheck disable=SC2086 # the tier and its optional domain, split on purpose
	_k_ses=$(AGENTS_CONFIG="$KIT_CONFIG" sh "$LIB" $_k_spec 2>/dev/null)
	[ -n "$_k_ses" ] || continue
	for _k_dom in '' self-implemented; do
		_k_dead= _k_n=0
		while [ "$_k_n" -lt 12 ]; do
			# shellcheck disable=SC2086 # the optional domain, absent when empty
			_k_ans=$(env AGENTS_CONFIG="$KIT_CONFIG" AGENT_SESSION_MODEL="$_k_ses" AGENT_UNREACHABLE_MODELS="$_k_dead" AGENTS_TIER_QUIET=1 sh "$LIB" reviewer $_k_dom)
			[ -n "$_k_ans" ] || break
			[ "$_k_ans" = "$_k_ses" ] && _k_walk_bad="$_k_walk_bad '$_k_spec' reviewer${_k_dom:+ $_k_dom} -> $_k_ans;"
			_k_dead="$_k_dead $_k_ans"
			_k_n=$((_k_n + 1))
		done
		[ "$_k_n" -lt 12 ] || _k_walk_bad="$_k_walk_bad '$_k_spec' reviewer${_k_dom:+ $_k_dom} never spent;"
	done
done
[ -z "$_k_walk_bad" ] &&
	pass "walked to the end for every session tier, no answer is the session's own model" ||
	fail "the kit's walk answered a session its own model:$_k_walk_bad"
_k_fb_bad=
_k_fb_rest=$_k_fb
for _k_c in $_k_fb_rest; do
	case $_k_c in *:*) continue ;; esac
	_k_cw=$(printf '%s' "$_k_c" | sed 's/^[^-]*-//; s/-.*//')
	for _k_spec in planner implementer mechanical 'implementer content'; do
		# shellcheck disable=SC2086 # the tier and its optional domain, split on purpose
		_k_ses=$(AGENTS_CONFIG="$KIT_CONFIG" sh "$LIB" $_k_spec 2>/dev/null)
		_k_sw=$(printf '%s' "$_k_ses" | sed 's/^[^-]*-//; s/-.*//')
		[ "$_k_c" = "$_k_ses" ] && _k_fb_bad="$_k_fb_bad $_k_c is the '$_k_spec' model;"
		[ "$_k_cw" = "$_k_sw" ] && _k_fb_bad="$_k_fb_bad $_k_c shares the '$_k_spec' spawn word '$_k_sw';"
	done
done
[ -z "$_k_fb_bad" ] &&
	pass "every in-session fallback is no session tier's model, by id or by spawn word" ||
	fail "the kit's fallback can hand a session itself:$_k_fb_bad"
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
# An unmapped reviewer is not a pass — the rule has nothing to compare.
case "$(reviewer_rule_gaps "$EMPTY")" in
*"the reviewer tier is unmapped"*) pass "the probe reports a mapping with no reviewer at all, rather than passing vacuously" ;;
*) fail "the probe passed an unmapped reviewer" ;;
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

# ---------------------------------------------------------------------------
banner "The wrapper never hands a review to the session's own model (#224, ADR-0007)"
# ---------------------------------------------------------------------------
# The mapping's `self-implemented` answer is one model, chosen on the
# assumption that the session runs on the planner's — so on a session that
# runs on THAT model, the answer is the implementer's own, which is the case
# the domain exists to avoid. The config cannot know who is asking; the
# caller can say. When $AGENT_SESSION_MODEL names the session's model and the
# reviewer answer equals it, the wrapper warns once and falls back to the
# plain reviewer tier; when that too equals it, the wrapper warns that the
# review will share the author's model and prints nothing. Unset, nothing
# changes — every case above ran without it. Not the shared resolver: that
# half is 0.21.0's (the release ticket says so).
# t_run_split (tests/lib.sh) is the runner that keeps stdout and stderr apart —
# the whole contract here, since a warning merged into stdout would read as a
# model id. `env` carries the session model into the child without exporting it
# into this suite's own environment, where it would silently change every case
# that follows.
wrap() { # <session model or ''> <args...> — sets W_OUT W_STATUS W_ERR_TEXT
	_w_model=$1; shift
	if [ -n "$_w_model" ]; then
		t_run_split env AGENT_SESSION_MODEL="$_w_model" sh "$KIT_WRAPPER" "$@"
	else
		t_run_split sh "$KIT_WRAPPER" "$@"
	fi
	W_OUT=$S_OUT; W_STATUS=$S_STATUS; W_ERR_TEXT=$S_ERR
}
wrap '' reviewer; K_REV=$W_OUT
wrap '' reviewer self-implemented; K_SELF=$W_OUT
wrap '' implementer; K_IMP=$W_OUT
[ -n "$K_REV" ] && [ -n "$K_SELF" ] && [ "$K_REV" != "$K_SELF" ] &&
	pass "premise: the kit maps reviewer ('$K_REV') and reviewer self-implemented ('$K_SELF') to different models" ||
	fail "premise broken: reviewer='$K_REV' self-implemented='$K_SELF' — the section below cannot mean anything"

# (1) The session runs on the self-implemented answer: fall back to the plain reviewer, and say so.
wrap "$K_SELF" reviewer self-implemented
[ "$W_STATUS" = 0 ] && [ "$W_OUT" = "$K_REV" ] &&
	pass "on a '$K_SELF' session, 'reviewer self-implemented' falls back to the plain reviewer '$K_REV'" ||
	fail "on a '$K_SELF' session, 'reviewer self-implemented' gave '$W_OUT' (status $W_STATUS) — expected the plain reviewer '$K_REV'"
case "$W_ERR_TEXT" in
*"session's own model"*) pass "…and warns that the mapped answer was the session's own model" ;;
*) fail "…but did not warn — stderr: '$W_ERR_TEXT'" ;;
esac

# (2) The session runs on the plain reviewer's model and asks for the plain
# reviewer. Before #548 nothing differed and nothing was printed; the kit's
# mapping now names an ordered fallback (ADR-0013), so the walk answers its
# first entry — never the session's own model — and says what it skipped.
# The spent-list case is pinned against a throwaway policy further down.
wrap "$K_REV" reviewer
[ "$W_STATUS" = 0 ] && [ -n "$W_OUT" ] && [ "$W_OUT" != "$K_REV" ] &&
	pass "on a '$K_REV' session, 'reviewer' walks to the kit's fallback '$W_OUT', not the session's own model" ||
	fail "on a '$K_REV' session, 'reviewer' printed '${W_OUT:-nothing}' (status $W_STATUS) — the session's own model, or no next answer"
case "$W_ERR_TEXT" in
*"$K_REV"*"session's own model"*) pass "…and warns that it skipped the session's own model" ;;
*) fail "…but did not name the skip — stderr: '$W_ERR_TEXT'" ;;
esac

# (3) The session runs on a model the reviewer answer does NOT equal: unchanged.
# A word the config never uses, so the comparison is against the SESSION and
# not against some other tier's value that happens to coincide.
wrap "model-nobody-maps" reviewer self-implemented
[ "$W_STATUS" = 0 ] && [ "$W_OUT" = "$K_SELF" ] &&
	pass "on a session the mapping never names, 'reviewer self-implemented' is the mapped '$K_SELF', untouched" ||
	fail "on a session the mapping never names, 'reviewer self-implemented' gave '$W_OUT' — the refusal fired when nothing was equal"
case "$W_ERR_TEXT" in
*"session"*) fail "…and warned about the session when nothing was equal: '$W_ERR_TEXT'" ;;
*) pass "…with no warning" ;;
esac

# (4) A non-reviewer tier is never refused, even when it equals the session's model.
wrap "$K_IMP" implementer
[ "$W_STATUS" = 0 ] && [ "$W_OUT" = "$K_IMP" ] &&
	pass "on a '$K_IMP' session, 'implementer' still resolves to '$K_IMP' — only the reviewer is held to differ" ||
	fail "on a '$K_IMP' session, 'implementer' gave '$W_OUT' — the refusal leaked past the reviewer tier"

# (5) The quiet switch silences the refusal's warning too, and changes nothing else.
t_run_split env AGENT_SESSION_MODEL="$K_SELF" AGENTS_TIER_QUIET=1 sh "$KIT_WRAPPER" reviewer self-implemented
W_OUT=$S_OUT; W_ERR_TEXT=$S_ERR
[ "$W_OUT" = "$K_REV" ] && [ -z "$W_ERR_TEXT" ] &&
	pass "AGENTS_TIER_QUIET=1 keeps the fallback and drops the warning" ||
	fail "AGENTS_TIER_QUIET=1: stdout '$W_OUT', stderr '$W_ERR_TEXT'"

# (6) The flagged form is the same question. `--model reviewer` is what
# scripts/agents.config.sh tells a reader to use to read the mapping's model
# half back (ADR-0005 clause 4), and the wrapper forwards the WHOLE signature —
# so a guard that read $1 alone would let exactly the refused answer through,
# silently, by the spelling the policy file itself documents.
wrap "$K_SELF" --model reviewer self-implemented
[ "$W_STATUS" = 0 ] && [ "$W_OUT" = "$K_REV" ] &&
	pass "'--model reviewer self-implemented' is refused like the bare form, falling back to '$K_REV'" ||
	fail "'--model reviewer self-implemented' gave '$W_OUT' (status $W_STATUS) — the flagged spelling walks past the refusal"
case "$W_ERR_TEXT" in
*"self-implemented"*) pass "…and the warning names the domain that was asked for" ;;
*) fail "…but the warning does not name the domain — stderr: '$W_ERR_TEXT'" ;;
esac
# The harness half is a different question: a harness token is not a model, so
# it is never compared and never refused. This case and the empty-answer guard
# beside it are proved by CONSTRUCTION, not by observation: the wrapper pins its
# own policy file, and the kit maps no agent harness and no empty tier, so
# neither can be driven RED from here. #226 moves the rule into the shared
# resolver, where a throwaway policy file can reach both — that is where they
# earn a failing check.
wrap "$K_SELF" --harness reviewer
[ "$W_STATUS" = 0 ] &&
	case "$W_ERR_TEXT" in *"session's own model"*) false ;; *) true ;; esac &&
	pass "'--harness reviewer' passes through — a harness token is not a model to compare" ||
	fail "'--harness reviewer' was refused (status $W_STATUS, stderr '$W_ERR_TEXT') — the guard compared a harness token to a model"

# (7) The resolver's own exit codes survive the extra hop with the session named.
wrap "$K_SELF" reviewer SELF-IMPLEMENTED
[ "$W_STATUS" = 2 ] && pass "a malformed domain still exits 2 with the session model set" ||
	fail "a malformed domain exited $W_STATUS with the session model set, expected 2"
wrap "$K_SELF" janitor
[ "$W_STATUS" = 2 ] && pass "an unknown tier still exits 2 with the session model set" ||
	fail "an unknown tier exited $W_STATUS with the session model set, expected 2"

# ---------------------------------------------------------------------------
banner "The kit's two policy files — one per agent harness the operator works in"
# ---------------------------------------------------------------------------
# The operator drives this repo from two agent harnesses, and each has its own
# tier policy: a model that is local to one is a cross-harness dispatch from
# the other. One file each, and the wrapper picks by the session it runs in,
# so `sh scripts/agents.kit.sh <tier>` keeps meaning "this session's policy"
# wherever it is typed. Neither file ships (KIT_ONLY), which is the only
# reason either may name a real model id at all.
CC_CONFIG="$KIT/scripts/agents.kit.config.sh"
CX_CONFIG="$KIT/scripts/agents.kit.codex.config.sh"
for f in "$CC_CONFIG" "$CX_CONFIG"; do
	[ -f "$f" ] && pass "$(basename "$f") exists" || fail "$(basename "$f") is missing"
done
# Every tier resolves in BOTH policies — a half-filled one is a silent inherit
# at spawn time, the failure the mapping exists to prevent.
for f in "$CC_CONFIG" "$CX_CONFIG"; do
	_label=$(basename "$f")
	for tier in planner implementer mechanical reviewer; do
		t_run_split env AGENTS_CONFIG="$f" sh "$LIB" "$tier"
		[ "$S_STATUS" = 0 ] && [ -n "$S_OUT" ] &&
			pass "$_label: $tier resolves to '$S_OUT'" ||
			fail "$_label: $tier resolved nothing (status $S_STATUS)"
	done
	# The tests domain is the operator's fourth agent, the tester. It is a
	# domain and not a fifth tier because the tier vocabulary is closed.
	t_run_split env AGENTS_CONFIG="$f" sh "$LIB" implementer
	_plain=$S_OUT
	t_run_split env AGENTS_CONFIG="$f" sh "$LIB" implementer tests
	[ "$S_STATUS" = 0 ] && [ -n "$S_OUT" ] && [ "$S_OUT" != "$_plain" ] &&
		pass "$_label: 'implementer tests' resolves to '$S_OUT', not the plain '$_plain'" ||
		fail "$_label: 'implementer tests' gave '$S_OUT' against plain '$_plain' — the tester is not mapped"
	# The reviewer rule holds in both.
	gaps=$(reviewer_rule_gaps "$f")
	[ -z "$gaps" ] && pass "$_label: the reviewer rule holds" ||
		fail "$_label: the reviewer rule breaks — $(printf '%s' "$gaps" | tr '\n' ';')"
	# A tier that names an agent harness the policy does not declare cannot be
	# dispatched: the resolver says so, and a policy file must not ship that.
	_undeclared=0
	for tier in planner implementer mechanical reviewer; do
		t_run_split env AGENTS_CONFIG="$f" sh "$LIB" --harness "$tier"
		case "$S_ERR" in *undeclared* | *"not declared"*) _undeclared=$((_undeclared + 1)) ;; esac
	done
	[ "$_undeclared" = 0 ] && pass "$_label: every agent harness a tier names is declared in AGENT_HARNESSES" ||
		fail "$_label: $_undeclared tier(s) name an agent harness AGENT_HARNESSES does not declare"
done
# The reviewer crosses vendors in the Codex policy — the property the kit calls
# its highest-leverage wiring, here asserted rather than hoped for. The Claude
# Code policy's reviewer is local until the cross-vendor CLI authenticates from
# this host (#423); the reviewer rule above holds it to a model that is not the
# implementer's, which is what a local reviewer can still promise.
t_run_split env AGENTS_CONFIG="$CX_CONFIG" sh "$LIB" --harness reviewer
[ -n "$S_OUT" ] && pass "agents.kit.codex.config.sh: the reviewer runs on agent harness '$S_OUT', not the session's own" ||
	fail "agents.kit.codex.config.sh: the reviewer names no agent harness — the review shares the author's vendor"
t_run_split env AGENTS_CONFIG="$CC_CONFIG" sh "$LIB" --harness reviewer
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	pass "agents.kit.config.sh: the reviewer is local — no agent harness while the crossing cannot authenticate" ||
	fail "agents.kit.config.sh: the reviewer names agent harness '$S_OUT' (status $S_STATUS) — #423 maps it local"
# The two policies are different documents, not a copy with one word changed:
# what is local in one is the crossing in the other.
t_run_split env AGENTS_CONFIG="$CC_CONFIG" sh "$LIB" planner
CC_PLANNER=$S_OUT
t_run_split env AGENTS_CONFIG="$CX_CONFIG" sh "$LIB" planner
[ -n "$CC_PLANNER" ] && [ "$S_OUT" != "$CC_PLANNER" ] &&
	pass "the two policies disagree about the planner ('$CC_PLANNER' vs '$S_OUT') — each is its own session's answer" ||
	fail "both policies map the planner to '$S_OUT' — one of them is a copy, not a policy"

# ---------------------------------------------------------------------------
banner "The SHARED resolver refuses a review by the session's own model (#226)"
# ---------------------------------------------------------------------------
# ADR-0007 decided the shape and the kit built it in its own wrapper, because
# the resolver is shared layer and that fix was not a release. This is the
# release: the rule lives in scripts/agents.lib.sh now, so every consumer's
# `self-implemented` mapping stops having the blind spot the kit found in its
# own. Asserted against a THROWAWAY policy, never the kit's — a throwaway can
# break each half on purpose, and the kit's own answers are pinned above.
LOCALREV="$SCRATCH/local-reviewer.config.sh"
cat >"$LOCALREV" <<'LOCALREV_CFG'
AGENT_TIER_PLANNER='vendor-strong-9'
AGENT_TIER_IMPLEMENTER='vendor-mid-4'
AGENT_TIER_MECHANICAL='vendor-small-2'
AGENT_TIER_REVIEWER='vendor-strong-9'
AGENT_TIER_REVIEWER_SELF_IMPLEMENTED='vendor-mid-4'
LOCALREV_CFG
res() { t_run_split env AGENTS_CONFIG="$LOCALREV" sh "$LIB" "$@"; }
resolve_as() { # <session model> <args...>
	_ra_model=$1; shift
	t_run_split env AGENTS_CONFIG="$LOCALREV" AGENT_SESSION_MODEL="$_ra_model" sh "$LIB" "$@"
}
# The session runs the model `reviewer self-implemented` maps to.
resolve_as vendor-mid-4 reviewer self-implemented
[ "$S_STATUS" = 0 ] && [ "$S_OUT" = vendor-strong-9 ] &&
	pass "the resolver falls back to the plain reviewer when the mapped answer is the session's own" ||
	fail "resolved '$S_OUT' (status $S_STATUS) on a session running that very model"
case "$S_ERR" in
*"session's own model"*) pass "…and says so on stderr, where the value is not" ;;
*) fail "…silently — stderr was '$S_ERR'" ;;
esac
# The flagged spelling is the same question: the policy file documents
# `--model <tier>` as how the model half is read back (ADR-0005 clause 4).
resolve_as vendor-mid-4 --model reviewer self-implemented
[ "$S_OUT" = vendor-strong-9 ] &&
	pass "'--model reviewer self-implemented' is refused like the bare form" ||
	fail "the flagged spelling resolved '$S_OUT' — it walks past the refusal"
# Nothing differs: print nothing, and say why, so the caller's report can.
resolve_as vendor-strong-9 reviewer
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	pass "when no reviewer differs from the session, the resolver prints nothing" ||
	fail "printed '$S_OUT' — that is the author reviewing itself"
case "$S_ERR" in
*"share the author's model"*) pass "…and warns that the review would share the author's model" ;;
*) fail "…without saying why: '$S_ERR'" ;;
esac
# Only the reviewer, and only when the caller named a session.
resolve_as vendor-mid-4 implementer
[ "$S_OUT" = vendor-mid-4 ] &&
	pass "a non-reviewer tier equal to the session's model is never refused" ||
	fail "the implementer resolved '$S_OUT' — the refusal leaked past the reviewer tier"
t_run_split env AGENTS_CONFIG="$LOCALREV" AGENT_SESSION_MODEL= sh "$LIB" reviewer self-implemented
[ "$S_OUT" = vendor-mid-4 ] &&
	pass "with no session named there is nothing to compare, and the mapping answers" ||
	fail "an unnamed session changed the answer to '$S_OUT'"
# The harness half asks a different question and is never compared.
# HARNESS MODE IS REFUSED TOO, and must be: the dispatcher asks for the two
# halves in two calls, so a mode that skipped the refusal would answer the
# refused mapping's agent harness beside the fallback's model. The earlier
# wording here claimed the opposite and passed only because its fixture's
# reviewer differed from the session anyway — a fixture, not a contract.
resolve_as vendor-mid-4 --harness reviewer self-implemented
[ "$S_STATUS" = 0 ] &&
	case "$S_ERR" in *"session's own model"*) true ;; *) false ;; esac &&
	pass "--harness refuses on the same comparison, so both halves come from one mapping" ||
	fail "harness mode did not refuse a reviewer equal to the session: '$S_ERR'"
# What it is NOT is a comparison of the harness token: a tier whose model
# differs is untouched whatever agent harness it names.
resolve_as vendor-strong-9 --harness implementer
case "$S_ERR" in
*"session's own model"*) fail "a non-reviewer tier was refused in harness mode" ;;
*) pass "…and only the reviewer tier, as in model mode" ;;
esac

# A self-implemented domain mapped with the plain tier UNSET: the fallback has
# nothing to fall back to, so nothing is printed and the warning says which of
# the two shapes it is. Without this the `[ -n "$_ah_model" ]` guard on the
# fallback could be deleted with the suite still green.
DOMAINONLY="$SCRATCH/domain-only.config.sh"
printf "AGENT_TIER_REVIEWER_SELF_IMPLEMENTED='vendor-mid-4'\n" >"$DOMAINONLY"
t_run_split env AGENTS_CONFIG="$DOMAINONLY" AGENT_SESSION_MODEL=vendor-mid-4 sh "$LIB" reviewer self-implemented
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	pass "a domain-only mapping equal to the session prints nothing — there is no plain tier to fall back to" ||
	fail "a domain-only mapping resolved '$S_OUT' (status $S_STATUS)"
case "$S_ERR" in
*"share the author's model"*) pass "…and says the review would share the author's model, not that it fell back" ;;
*) fail "…with the wrong warning for that shape: '$S_ERR'" ;;
esac
# The quiet switch silences this warning like every other.
t_run_split env AGENTS_CONFIG="$LOCALREV" AGENT_SESSION_MODEL=vendor-mid-4 AGENTS_TIER_QUIET=1 sh "$LIB" reviewer self-implemented
[ "$S_OUT" = vendor-strong-9 ] && [ -z "$S_ERR" ] &&
	pass "AGENTS_TIER_QUIET=1 keeps the fallback and drops the warning" ||
	fail "quiet mode: stdout '$S_OUT', stderr '$S_ERR'"
# BOTH HALVES MOVE TOGETHER. The resolver answers a model and an agent
# harness through two calls, and the dispatcher combines them. If the refusal
# replaced only the model, a fallback that crosses vendors would arrive with
# the ORIGINAL mapping's harness — the remote model launched on the local
# agent harness, or the reverse. The substitution is of the whole mapping.
SPLITCFG="$SCRATCH/split-halves.config.sh"
cat >"$SPLITCFG" <<'SPLIT_CFG'
AGENT_HARNESSES='other'
AGENT_HARNESS_OTHER_CMD='true {model_flag} < {prompt_file}'
AGENT_HARNESS_OTHER_MODEL_FLAG='--model {model}'
AGENT_TIER_REVIEWER='other:remote-B'
AGENT_TIER_REVIEWER_SELF_IMPLEMENTED='local-A'
SPLIT_CFG
t_run_split env AGENTS_CONFIG="$SPLITCFG" AGENT_SESSION_MODEL=local-A sh "$LIB" reviewer self-implemented
_sh_model=$S_OUT
t_run_split env AGENTS_CONFIG="$SPLITCFG" AGENT_SESSION_MODEL=local-A sh "$LIB" --harness reviewer self-implemented
[ "$_sh_model" = remote-B ] && [ "$S_OUT" = other ] &&
	pass "a refused reviewer yields BOTH halves of its fallback ('$S_OUT:$_sh_model')" ||
	fail "the halves disagree: model '$_sh_model' with agent harness '$S_OUT' — the spawn would run the wrong pair"

# THE COMPARISON IS EXACT, never a family guess. A resolver that folded ids to
# a family word would have to know each vendor's ORDER — `claude-opus-5` puts
# the family second, `gpt-5.6-sol` puts the version there — and guessing wrong
# refuses two DIFFERENT models as if they were one. This file ships to every
# project, so it compares what the policy file actually says and nothing else;
# a caller that knows its own session by a different spelling says so in the
# spelling its policy uses.
EXACTCFG="$SCRATCH/exact.config.sh"
cat >"$EXACTCFG" <<'EXACT_CFG'
AGENT_TIER_REVIEWER='vendor-9.9-alpha'
AGENT_TIER_REVIEWER_SELF_IMPLEMENTED='vendor-9.9-beta'
EXACT_CFG
t_run_split env AGENTS_CONFIG="$EXACTCFG" AGENT_SESSION_MODEL=vendor-9.9-alpha sh "$LIB" reviewer self-implemented
[ "$S_OUT" = vendor-9.9-beta ] &&
	pass "two ids sharing everything but their last segment are DIFFERENT models, and neither is refused for the other" ||
	fail "resolved '$S_OUT' — a family guess refused a model the session is not running"

# The SHIPPED mapping is empty, so there is nothing to refuse and nothing changes.
t_run_split env AGENTS_CONFIG="$SHIPPED" AGENT_SESSION_MODEL=anything sh "$LIB" reviewer
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	pass "against the shipped empty mapping the rule is inert, as it must be" ||
	fail "the shipped mapping resolved '$S_OUT' with a session named"

# ---------------------------------------------------------------------------
banner "The reviewer's ordered fallback, past what the caller names unreachable (#548, ADR-0013)"
# ---------------------------------------------------------------------------
# ADR-0007 gave the reviewer one next answer: the plain tier. When that one is
# the session's own, or its vendor is out of credits, there was nothing past
# it. ADR-0013 adds an ordered list in the policy, AGENT_TIER_REVIEWER_FALLBACK,
# and a caller-held fact, AGENT_UNREACHABLE_MODELS: what a spawn found dead.
# The walk is the domain answer, the plain reviewer, then each fallback; the
# first candidate that is neither the session's model nor named unreachable is
# printed. Asserted against a throwaway policy whose every candidate is a
# different word, so each skip is visible in the answer.
FBCFG="$SCRATCH/fallback.config.sh"
cat >"$FBCFG" <<'FB_CFG'
AGENT_HARNESSES='other'
AGENT_HARNESS_OTHER_CMD='true {model_flag} < {prompt_file}'
AGENT_HARNESS_OTHER_MODEL_FLAG='--model {model}'
AGENT_TIER_PLANNER='vendor-strong-9'
AGENT_TIER_IMPLEMENTER='vendor-mid-4'
AGENT_TIER_MECHANICAL='vendor-small-2'
AGENT_TIER_REVIEWER='vendor-strong-9'
AGENT_TIER_REVIEWER_SELF_IMPLEMENTED='vendor-third-7'
AGENT_TIER_REVIEWER_FALLBACK='vendor-small-2 other:remote-B vendor-last-1'
FB_CFG
fb() { # <session model or ''> <unreachable or ''> <args...>
	_fb_ses=$1 _fb_unr=$2
	shift 2
	t_run_split env AGENTS_CONFIG="$FBCFG" AGENT_SESSION_MODEL="$_fb_ses" AGENT_UNREACHABLE_MODELS="$_fb_unr" sh "$LIB" "$@"
}
# (1) UNSET OR EMPTY, TODAY'S BEHAVIOUR. The LOCALREV cases above run with no
# fallback at all; an empty one must be indistinguishable from it, stderr too.
t_run_split env AGENTS_CONFIG="$LOCALREV" AGENT_SESSION_MODEL=vendor-strong-9 sh "$LIB" reviewer
_fb_base="$S_STATUS|$S_OUT|$S_ERR"
EMPTYFB="$SCRATCH/empty-fallback.config.sh"
{ cat "$LOCALREV"; echo "AGENT_TIER_REVIEWER_FALLBACK=''"; } >"$EMPTYFB"
t_run_split env AGENTS_CONFIG="$EMPTYFB" AGENT_SESSION_MODEL=vendor-strong-9 sh "$LIB" reviewer
[ "$S_STATUS|$S_OUT|$S_ERR" = "$_fb_base" ] &&
	pass "an empty AGENT_TIER_REVIEWER_FALLBACK answers exactly as an unset one, stderr and all" ||
	fail "an empty fallback changed the answer: '$S_STATUS|$S_OUT|$S_ERR' against '$_fb_base'"
# (2) A refused answer walks on, past the plain tier, to the first fallback.
fb vendor-strong-9 '' reviewer
[ "$S_STATUS" = 0 ] && [ "$S_OUT" = vendor-small-2 ] &&
	pass "a reviewer equal to the session walks to the first fallback 'vendor-small-2'" ||
	fail "a refused reviewer resolved '$S_OUT' (status $S_STATUS) — expected the first fallback"
case "$S_ERR" in
*vendor-strong-9*"session's own model"*) pass "…and the warning names what it skipped, and why" ;;
*) fail "…without naming the skip — stderr: '$S_ERR'" ;;
esac
# (3) The order: the domain answer, then the plain reviewer, then the list.
fb '' vendor-third-7 reviewer self-implemented
[ "$S_OUT" = vendor-strong-9 ] &&
	pass "an unreachable domain answer falls to the plain reviewer before any fallback" ||
	fail "an unreachable domain answer resolved '$S_OUT' — expected the plain reviewer 'vendor-strong-9'"
case "$S_ERR" in
*vendor-third-7*unreachable*) pass "…and says the domain answer was named unreachable" ;;
*) fail "…without naming the unreachable skip — stderr: '$S_ERR'" ;;
esac
# (4) An unreachable answer is skipped with no session named at all.
fb '' 'vendor-third-7 vendor-strong-9' reviewer self-implemented
[ "$S_OUT" = vendor-small-2 ] &&
	pass "two unreachable answers walk to the first fallback, with no session named" ||
	fail "resolved '$S_OUT' past two unreachable answers — expected 'vendor-small-2'"
# (5) A candidate equal to the session is skipped even INSIDE the list, and a
# `<harness>:<model>` fallback carries its own agent harness — both halves
# answer from the one candidate, as ADR-0007's substitution does.
fb vendor-small-2 vendor-strong-9 reviewer
_fb_model=$S_OUT
fb vendor-small-2 vendor-strong-9 --harness reviewer
[ "$_fb_model" = remote-B ] && [ "$S_OUT" = other ] &&
	pass "a fallback equal to the session is skipped, and 'other:remote-B' answers both halves" ||
	fail "past the session inside the list: model '$_fb_model', agent harness '$S_OUT' — expected remote-B on other"
# A harness-prefixed candidate is compared on its MODEL half only.
fb remote-B 'vendor-strong-9 vendor-small-2' reviewer
[ "$S_OUT" = vendor-last-1 ] &&
	pass "a session on 'remote-B' skips 'other:remote-B' — the comparison is on the model half" ||
	fail "a 'remote-B' session resolved '$S_OUT' — the harness prefix hid its own model"
fb '' 'vendor-strong-9 vendor-small-2 remote-B' reviewer
[ "$S_OUT" = vendor-last-1 ] &&
	pass "an unreachable name matches a harness-prefixed candidate on its model half" ||
	fail "naming 'remote-B' unreachable resolved '$S_OUT' — expected 'vendor-last-1'"
# (6) A spent list prints nothing, with ADR-0007's warning — never the session.
fb vendor-last-1 'vendor-strong-9 vendor-small-2 remote-B' reviewer
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	pass "a spent list prints nothing rather than the session's own model" ||
	fail "a spent list printed '$S_OUT' (status $S_STATUS)"
case "$S_ERR" in
*"share the author's model"*) pass "…and warns the review would share the author's model" ;;
*) fail "…without ADR-0007's warning — stderr: '$S_ERR'" ;;
esac
fb '' 'vendor-strong-9 vendor-small-2 remote-B vendor-last-1' reviewer
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	case "$S_ERR" in *"share the author's model"*) true ;; *) false ;; esac &&
	pass "a list spent on unreachable names alone prints nothing, with the same warning" ||
	fail "every candidate unreachable: stdout '$S_OUT', stderr '$S_ERR'"
# (7) Other tiers ignore both variables — answer, and stderr.
fb vendor-mid-4 vendor-mid-4 implementer
[ "$S_OUT" = vendor-mid-4 ] && [ -z "$S_ERR" ] &&
	pass "a non-reviewer tier ignores AGENT_UNREACHABLE_MODELS and the fallback, warning about neither" ||
	fail "the implementer resolved '$S_OUT' (stderr '$S_ERR') — the walk leaked past the reviewer tier"
# (8) A name that matches no candidate is warned about, never ignored in
# silence: a spawn word against a pinned id would hand back the dead model.
fb '' strong reviewer
[ "$S_OUT" = vendor-strong-9 ] &&
	pass "an unreachable name matching nothing changes no answer" ||
	fail "an unmatched name changed the answer to '$S_OUT'"
case "$S_ERR" in
*"'strong'"*"matches no"*) pass "…and is warned about by name" ;;
*) fail "…silently — stderr: '$S_ERR'" ;;
esac
fb '' vendor-strong-9 reviewer
case "$S_ERR" in
*"matches no"*) fail "a name that matched a candidate was warned about as matching none: '$S_ERR'" ;;
*) pass "a name that matched a candidate draws no match warning" ;;
esac
# (9) --model reaches the walk, as every spelling of the question must.
fb '' vendor-strong-9 --model reviewer
[ "$S_OUT" = vendor-small-2 ] &&
	pass "'--model reviewer' walks past an unreachable answer like the bare form" ||
	fail "'--model reviewer' resolved '$S_OUT' — the flagged spelling skips the walk"
# (10) The quiet switch keeps the walk and drops its warnings.
t_run_split env AGENTS_CONFIG="$FBCFG" AGENT_UNREACHABLE_MODELS='vendor-strong-9 nothing-at-all' AGENTS_TIER_QUIET=1 sh "$LIB" reviewer
[ "$S_OUT" = vendor-small-2 ] && [ -z "$S_ERR" ] &&
	pass "AGENTS_TIER_QUIET=1 keeps the walk and drops its warnings" ||
	fail "quiet walk: stdout '$S_OUT', stderr '$S_ERR'"
# (11) zsh does not word-split an unquoted expansion; a walk written as
# `for c in $list` would see one candidate there. The sourced function is what
# a zsh caller runs, so it is the one driven.
if command -v zsh >/dev/null 2>&1; then
	t_run_split env AGENTS_CONFIG="$FBCFG" AGENT_UNREACHABLE_MODELS='vendor-strong-9 vendor-small-2' zsh -c ". '$LIB'; resolve_tier reviewer"
	[ "$S_OUT" = remote-B ] &&
		pass "zsh: the walk splits the fallback and the unreachable list as sh does" ||
		fail "zsh: the walk resolved '$S_OUT', expected 'remote-B'"
else
	note "zsh is not installed here — the zsh walk case did not run"
fi

# ---------------------------------------------------------------------------
banner "The wrapper picks the policy for the session it runs in"
# ---------------------------------------------------------------------------
# $AGENT_HARNESS_SELF names the session's own agent harness. Unset, the
# wrapper assumes the harness this repo is usually driven from, so a plain
# invocation keeps working. The wrapper's own assignment still beats the
# caller's $AGENTS_CONFIG — the section above asserts exactly that, and this
# selection must not weaken it; a caller that wants another policy calls the
# resolver directly, as this suite does.
t_run_split env AGENT_HARNESS_SELF=codex sh "$KIT_WRAPPER" planner
CX_VIA_WRAPPER=$S_OUT
t_run_split env AGENTS_CONFIG="$CX_CONFIG" sh "$LIB" planner
[ -n "$CX_VIA_WRAPPER" ] && [ "$CX_VIA_WRAPPER" = "$S_OUT" ] &&
	pass "AGENT_HARNESS_SELF=codex answers from the codex policy ('$CX_VIA_WRAPPER')" ||
	fail "AGENT_HARNESS_SELF=codex gave '$CX_VIA_WRAPPER', the codex policy says '$S_OUT'"
t_run_split sh "$KIT_WRAPPER" planner
[ "$S_OUT" = "$CC_PLANNER" ] &&
	pass "unset, the wrapper answers from the claude-code policy ('$S_OUT'), as it always did" ||
	fail "unset, the wrapper gave '$S_OUT', not the claude-code policy's '$CC_PLANNER'"
t_run_split env AGENT_HARNESS_SELF=nothing-mapped sh "$KIT_WRAPPER" planner
[ "$S_OUT" = "$CC_PLANNER" ] &&
	pass "an agent harness with no policy file falls back to the default, rather than resolving nothing" ||
	fail "an unknown AGENT_HARNESS_SELF gave '$S_OUT' — expected the default policy's '$CC_PLANNER'"
# --policy is that same choice, asked for by name: other kit scripts need the
# answer before they call something that resolves, and a second copy of the
# case block is how this repo's hand-kept lists have drifted before.
t_run_split env AGENT_HARNESS_SELF=codex sh "$KIT_WRAPPER" --policy
[ "$S_STATUS" = 0 ] && [ "$S_OUT" = "scripts/agents.kit.codex.config.sh" ] &&
	pass "--policy names the codex policy for a codex session" ||
	fail "--policy gave '$S_OUT' for a codex session"
t_run_split sh "$KIT_WRAPPER" --policy
[ "$S_OUT" = "scripts/agents.kit.config.sh" ] &&
	pass "--policy names the claude-code policy by default" ||
	fail "--policy gave '$S_OUT' by default"

# The fold and the refusal are exercised against a PROBE policy, not against
# the kit's own data: the suite's own principle (line 39) is that it names no
# real model, and pinning the kit's current ids here would mean editing this
# file at every re-pin. The wrapper resolves `scripts/agents.kit.<self>.config.sh`
# and `scripts/agents.lib.sh` relative to the directory it runs in, so a
# scratch tree with those two names IS the seam.
PROBE="$SCRATCH/probe"
mkdir -p "$PROBE/scripts"
cp "$KIT/scripts/agents.kit.sh" "$KIT/scripts/agents.lib.sh" "$PROBE/scripts/"
cat >"$PROBE/scripts/agents.kit.probe.config.sh" <<'PROBE_CFG'
AGENT_TIER_PLANNER='vendor-strong-9'
AGENT_TIER_IMPLEMENTER='vendor-mid-4-20260101'
AGENT_TIER_MECHANICAL='vendor-small-2'
AGENT_TIER_REVIEWER='vendor-strong-9'
AGENT_TIER_REVIEWER_SELF_IMPLEMENTED='vendor-mid-4-20260101'
PROBE_CFG
probe() { (cd "$PROBE" && env AGENT_HARNESS_SELF=probe "$@" sh scripts/agents.kit.sh "${PROBE_ARGS:-}" >/dev/null 2>&1); }
# A pinned id folds to its family word, whatever the vendor prefix.
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=probe sh scripts/agents.kit.sh --alias implementer
[ "$S_OUT" = mid ] && pass "a pinned 'vendor-mid-4-20260101' folds to the spawn word 'mid'" ||
	fail "the fold gave '$S_OUT', expected 'mid'"
# THE REFUSAL REACHES --alias TOO. A session on the reviewer's own model must
# not be handed it by the in-session path either — the policy files call this
# wrapper "the net under both", and a net with one side open is not one.
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=probe AGENT_SESSION_MODEL=vendor-mid-4-20260101 sh scripts/agents.kit.sh --alias reviewer self-implemented
[ "$S_OUT" = strong ] &&
	pass "--alias reviewer self-implemented falls back when the mapped answer is the session's own model" ||
	fail "--alias gave '$S_OUT' on a session running that very model — the refusal does not reach the alias path"
# …and it is the POLICY FILE'S spelling that is compared, not a family guess.
# A session that names itself by the word a spawn parameter takes, while the
# policy pins a full id, is NOT refused — because a resolver that folded one
# into the other would have to know each vendor's id ORDER, and a wrong guess
# refuses two different models as if they were one. The caller names itself in
# the spelling its own policy uses; that is the contract, and it is what the
# recipe's arriving-from paragraph tells a consumer.
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=probe AGENT_SESSION_MODEL=mid sh scripts/agents.kit.sh --alias reviewer self-implemented
[ "$S_OUT" = mid ] &&
	pass "a spawn-word session against a pinned policy is not refused — the comparison is exact" ||
	fail "AGENT_SESSION_MODEL=mid gave '$S_OUT' — something folded one spelling into the other"
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=probe AGENT_SESSION_MODEL=vendor-mid-4-20260101 sh scripts/agents.kit.sh --alias reviewer self-implemented
[ "$S_OUT" = strong ] &&
	pass "naming itself in the policy's own spelling IS refused, and the fallback folds for the spawn" ||
	fail "the pinned spelling gave '$S_OUT'"
# An unknown tier still reports itself rather than exiting 2 in silence.
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=probe sh scripts/agents.kit.sh --alias janitor
[ "$S_STATUS" = 2 ] && [ -n "$S_ERR" ] &&
	pass "--alias on an unknown tier exits 2 and says why" ||
	fail "--alias janitor exited $S_STATUS with stderr '$S_ERR'"
# A local id with no vendor prefix is passed through, not swallowed.
printf "AGENT_TIER_MECHANICAL='plainword'\n" >>"$PROBE/scripts/agents.kit.probe.config.sh"
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=probe sh scripts/agents.kit.sh --alias mechanical
[ "$S_OUT" = plainword ] && pass "an id with no vendor prefix folds to itself" ||
	fail "an unprefixed id gave '$S_OUT'"

# THE WALK REACHES --alias, AND THE BRIDGE RUNS BACKWARDS (#548, ADR-0013).
# A session that saw a spawn fail saw it under the spawn WORD, and the
# resolver compares the policy's ids exactly — so the wrapper, which owns the
# id-to-word fold, maps a word named unreachable back to every pinned id it
# covers before delegating. Every one, the safe side: the caller cannot say
# which of them ran.
cat >"$PROBE/scripts/agents.kit.fb.config.sh" <<'PROBE_FB_CFG'
AGENT_TIER_PLANNER='vendor-strong-9'
AGENT_TIER_IMPLEMENTER='vendor-mid-4-20260101'
AGENT_TIER_MECHANICAL='vendor-small-2'
AGENT_TIER_REVIEWER='vendor-strong-9'
AGENT_TIER_REVIEWER_SELF_IMPLEMENTED='vendor-mid-4-20260101'
AGENT_TIER_REVIEWER_FALLBACK='vendor-strong-8 vendor-third-3 vendor-small-2'
PROBE_FB_CFG
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=fb AGENT_UNREACHABLE_MODELS=vendor-strong-9 sh scripts/agents.kit.sh --alias reviewer
[ "$S_OUT" = strong ] &&
	pass "--alias reaches the walk: an unreachable pinned id falls to the next candidate's word" ||
	fail "--alias with 'vendor-strong-9' unreachable gave '$S_OUT', expected 'strong' (vendor-strong-8)"
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=fb AGENT_UNREACHABLE_MODELS=strong sh scripts/agents.kit.sh reviewer
[ "$S_OUT" = vendor-third-3 ] &&
	pass "the spawn word 'strong' named unreachable skips both ids it covers, vendor-strong-9 and vendor-strong-8" ||
	fail "AGENT_UNREACHABLE_MODELS=strong through the wrapper resolved '$S_OUT' — expected 'vendor-third-3'"
case "$S_ERR" in
*"matches no"*) fail "…but the bridged word was still warned about as matching nothing: '$S_ERR'" ;;
*) pass "…and the bridged word draws no match warning" ;;
esac
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=fb AGENT_UNREACHABLE_MODELS=strong sh scripts/agents.kit.sh --alias reviewer
[ "$S_OUT" = third ] &&
	pass "--alias with the word 'strong' unreachable folds the answer past it, to 'third'" ||
	fail "--alias with 'strong' unreachable gave '$S_OUT', expected 'third'"
# A value that crosses to a DECLARED agent harness has no spawn word, so no
# word covers it — even when its model half folds to that word. Bridged, it
# would reach the resolver as 'other:vendor-strong-5', a name no candidate's
# model half equals, and draw a false "matches no" warning (PR #553 M-1).
cat >"$PROBE/scripts/agents.kit.fbx.config.sh" <<'PROBE_FBX_CFG'
AGENT_HARNESSES='other'
AGENT_TIER_PLANNER='vendor-strong-9'
AGENT_TIER_IMPLEMENTER='vendor-mid-4-20260101'
AGENT_TIER_MECHANICAL='vendor-small-2'
AGENT_TIER_REVIEWER='vendor-strong-9'
AGENT_TIER_REVIEWER_FALLBACK='other:vendor-strong-5 vendor-third-3'
PROBE_FBX_CFG
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=fbx AGENT_UNREACHABLE_MODELS=strong sh scripts/agents.kit.sh reviewer
case "$S_OUT|$S_ERR" in
*"matches no"*) fail "a crossing value was bridged as an id the word covers — stdout '$S_OUT', stderr '$S_ERR'" ;;
vendor-strong-5\|*) pass "a crossing value is no id a spawn word covers: the walk reaches 'other:vendor-strong-5', with no match warning" ;;
*) fail "the word 'strong' with a crossing fallback resolved '$S_OUT' — expected vendor-strong-5 (stderr '$S_ERR')" ;;
esac
# A prefix the resolver will not split — one whose SHAPE is wrong, here an
# upper-case 'Other' even though it is declared — is no agent harness to the
# resolver, so the value is one model id, and a word that folds from it covers
# it. The bridge follows the resolver's answer, not the bare declaration
# (#559, the one delta PR #582 names).
cat >"$PROBE/scripts/agents.kit.fbm.config.sh" <<'PROBE_FBM_CFG'
AGENT_HARNESSES='Other'
AGENT_TIER_REVIEWER='vendor-strong-9'
AGENT_TIER_REVIEWER_FALLBACK='Other:vendor-strong-5 vendor-third-3'
PROBE_FBM_CFG
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=fbm AGENT_UNREACHABLE_MODELS=strong sh scripts/agents.kit.sh reviewer
case "$S_OUT|$S_ERR" in
*"matches no"*) fail "a malformed-prefix value was not bridged as the id the resolver reads — stderr '$S_ERR'" ;;
vendor-third-3\|*) pass "a value whose prefix the resolver will not split is an id the word covers: the walk skips it to 'vendor-third-3'" ;;
*) fail "the word 'strong' with a malformed-prefix fallback resolved '$S_OUT' — expected vendor-third-3 (stderr '$S_ERR')" ;;
esac
# ONE membership test (#559). The probes above catch the bridge and the
# resolver disagreeing; these catch the second copy that could disagree.
# Whether a value crosses to a declared agent harness is the resolver's
# agents_split_harness's answer. So the wrapper reads no AGENT_HARNESSES of
# its own (comment lines are not code)…
_kit_code=$(sed 's/^[[:space:]]*#.*//' "$KIT_WRAPPER")
case "$_kit_code" in
*AGENT_HARNESSES*) fail "the kit wrapper reads AGENT_HARNESSES itself — a second copy of the resolver's membership test" ;;
*) pass "the kit wrapper holds no copy of the membership test: it reads no AGENT_HARNESSES" ;;
esac
# …and the answer it bridges by IS that function's, observed rather than
# grepped: a library copy whose sourced agents_split_harness says one bare
# value crosses (the override follows the direct-execution block, so the
# resolver executed by the wrapper still runs the real one). A wrapper that
# asks the library leaves that value unbridged, and the walk answers it; one
# that decided for itself would skip it too.
PROBE_ASK="$SCRATCH/probe-ask"
mkdir -p "$PROBE_ASK/scripts"
cp "$KIT/scripts/agents.kit.sh" "$KIT/scripts/agents.lib.sh" "$PROBE_ASK/scripts/"
cat >>"$PROBE_ASK/scripts/agents.lib.sh" <<'PROBE_ASK_LIB'
agents_split_harness() {
	_ah_harness= _ah_model=$1
	[ "$1" = vendor-strong-5 ] && _ah_harness=probe
	return 0
}
PROBE_ASK_LIB
cat >"$PROBE_ASK/scripts/agents.kit.ask.config.sh" <<'PROBE_ASK_CFG'
AGENT_TIER_REVIEWER='vendor-strong-9'
AGENT_TIER_REVIEWER_FALLBACK='vendor-strong-5 vendor-third-3'
PROBE_ASK_CFG
t_run_split env -C "$PROBE_ASK" AGENT_HARNESS_SELF=ask AGENT_UNREACHABLE_MODELS=strong sh scripts/agents.kit.sh reviewer
[ "$S_OUT" = vendor-strong-5 ] &&
	pass "the bridge asks the resolver's agents_split_harness: the value it says crosses is left unbridged" ||
	fail "the bridge did not take agents_split_harness's answer: resolved '$S_OUT', expected vendor-strong-5 (stderr '$S_ERR')"

# A pinned id and an unknown word pass the bridge untouched: the id still
# matches, and the unknown word reaches the resolver to be warned about.
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=fb AGENT_UNREACHABLE_MODELS='vendor-mid-4-20260101 nosuchword' sh scripts/agents.kit.sh reviewer self-implemented
[ "$S_OUT" = vendor-strong-9 ] &&
	case "$S_ERR" in *"'nosuchword'"*"matches no"*) true ;; *) false ;; esac &&
	pass "a pinned id passes the bridge and matches; an unknown word reaches the resolver's warning" ||
	fail "id and unknown word through the bridge: stdout '$S_OUT', stderr '$S_ERR'"

# --alias bridges the two spellings a PINNED id has to satisfy. The CLI takes
# the full id; the in-session spawn parameter takes the family word. Pinning
# is what makes a model change a decision someone committed rather than a
# roster moving underneath the policy, and this is what keeps it spawnable.
t_run_split sh "$KIT_WRAPPER" --alias planner
[ "$S_STATUS" = 0 ] && [ "$S_OUT" = fable ] &&
	pass "--alias planner is the spawn word 'fable' for the pinned claude-fable-5-1" ||
	fail "--alias planner gave '$S_OUT' (status $S_STATUS), expected 'fable'"
t_run_split sh "$KIT_WRAPPER" --alias implementer
[ "$S_OUT" = opus ] && pass "--alias implementer is 'opus'" || fail "--alias implementer gave '$S_OUT'"
t_run_split sh "$KIT_WRAPPER" --alias mechanical
[ "$S_OUT" = opus ] && pass "--alias mechanical is 'opus' — the tier moved off the cheapest model on 2026-10-01 (retro 20261001T150216Z)" ||
	fail "--alias mechanical gave '$S_OUT'"
t_run_split sh "$KIT_WRAPPER" --alias implementer content
[ "$S_OUT" = fable ] && pass "--alias carries the domain through" || fail "--alias with a domain gave '$S_OUT'"
# The reviewer is local since #423, on the content model, so it has a spawn word.
t_run_split sh "$KIT_WRAPPER" --alias reviewer
[ "$S_STATUS" = 0 ] && [ "$S_OUT" = fable ] &&
	pass "--alias reviewer is 'fable' — the local reviewer is spawnable in session" ||
	fail "--alias reviewer printed '$S_OUT' (status $S_STATUS), expected 'fable'"
# A value that is not an Anthropic id has no spawn word: it belongs to another
# agent harness, and printing a guess would be worse than printing nothing.
t_run_split env AGENT_HARNESS_SELF=codex sh "$KIT_WRAPPER" --alias reviewer
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	pass "--alias prints nothing for a tier that crosses agent harnesses — it is not spawnable in session" ||
	fail "--alias reviewer (Codex policy) printed '$S_OUT' (status $S_STATUS); a crossing has no in-session spawn word"
# Every alias it does print must be one the spawn parameter actually accepts.
for tier in planner implementer mechanical; do
	t_run_split sh "$KIT_WRAPPER" --alias "$tier"
	case "$S_OUT" in
	fable | opus | sonnet | haiku) pass "--alias $tier ('$S_OUT') is a word the spawn parameter accepts" ;;
	*) fail "--alias $tier gave '$S_OUT', which the spawn parameter does not accept" ;;
	esac
done
t_run_split env AGENT_HARNESS_SELF=codex AGENTS_CONFIG="$SHIPPED" sh "$KIT_WRAPPER" planner
[ "$S_OUT" = "$CX_VIA_WRAPPER" ] &&
	pass "the wrapper's own choice still beats an inherited AGENTS_CONFIG" ||
	fail "an inherited AGENTS_CONFIG overrode the wrapper's policy choice — got '$S_OUT'"

if [ "$SKIPPED" -gt 0 ]; then
	printf '  --    %s per-shell case(s) skipped above — this host proved less than a full-shell host would\n' "$SKIPPED"
fi
t_done "agents tier resolution"
