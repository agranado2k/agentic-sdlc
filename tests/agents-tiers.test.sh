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

# resolve <args> — the library, run as an agent runs it, streams kept apart
# (t_run_split in tests/lib.sh owns why).
resolve() { t_run_split sh "$LIB" "$@"; }




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
# `resolve` hard-codes `sh "$LIB"`; the cases below pick the shell and choose
# between executing and sourcing, so they need the whole command.
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
[ "$S_STATUS" = 2 ] && pass "no tier argument exits 2" || fail "no tier argument exited $S_STATUS, expected 2"
s_assert_err_has "usage"

resolve implementer content extra
[ "$S_STATUS" = 2 ] && pass "a third argument exits 2" || fail "a third argument exited $S_STATUS, expected 2"
s_assert_err_has "usage"

# ---------------------------------------------------------------------------
banner "The vocabulary is closed — an unknown tier is a caller bug"
# ---------------------------------------------------------------------------
# Four names, fixed by the manual layer. A typo'd or invented tier must not fall
# back to the session model: silently running 'implementor' on whatever the
# session happens to be is exactly the cost blindness this whole seam exists to
# remove. Exit 2, and say what the four names are.
resolve implementor
[ "$S_STATUS" = 2 ] && pass "an unknown tier exits 2" || fail "unknown tier exited $S_STATUS, expected 2"
s_assert_err_has "implementor"
s_assert_err_has "planner"
s_assert_err_has "implementer"
s_assert_err_has "mechanical"
s_assert_err_has "reviewer"
[ -z "$S_OUT" ] && pass "an unknown tier prints nothing on stdout" || fail "unknown tier printed '$S_OUT'"

resolve ""
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
resolve planner
s_assert_resolved "model-for-planning" "planner resolves to its configured model"
s_assert_err_lacks "UNMAPPED"

resolve implementer
s_assert_resolved "model-for-implementing" "implementer resolves to its configured model"

resolve mechanical
s_assert_resolved "model-for-mechanical" "mechanical resolves to its configured model"

resolve reviewer
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

resolve implementer content
s_assert_resolved "model-for-writing-prose" "a mapped tier+domain resolves to the domain's model"
s_assert_err_lacks "UNMAPPED"

resolve reviewer content
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
resolve implementer code
s_assert_resolved "model-for-implementing" "an unmapped domain falls back to the plain tier mapping"
s_assert_err_lacks "UNMAPPED"
[ -z "$S_ERR" ] && pass "…and says nothing at all on stderr" ||
	fail "an unmapped domain wrote to stderr: $S_ERR"

resolve mechanical content
s_assert_resolved "model-for-mechanical" "a tier with no domain mappings at all still resolves"

# The fallback is per-VARIABLE, not per-tier-having-any-domain-at-all: the tier
# below is unmapped, its domain is mapped, and the domain must still win.
resolve planner content
s_assert_resolved "model-for-planning-prose" "a mapped domain resolves even when the plain tier is empty"
s_assert_err_lacks "UNMAPPED"

# …and the mirror: unmapped tier, unmapped domain, so the ordinary unmapped-tier
# warning fires unchanged. The domain adds no second diagnostic.
resolve planner code
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
resolve implementer html-report
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
	resolve implementer "$bad"
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
		LC_ALL=$_at_locale resolve implementer "$bad"
		if [ "$S_STATUS" = 2 ] && [ -z "$S_OUT" ]; then
			pass "LC_ALL=$_at_locale: malformed domain '$bad' exits 2"
		else
			fail "LC_ALL=$_at_locale: malformed domain '$bad' exited $S_STATUS, stdout '$S_OUT', expected 2 and empty"
		fi
	done
done

# The message has to name the rule, not just say no: the caller is an agent
# reading stderr, and "invalid domain" without the shape is a dead end.
resolve implementer CONTENT
s_assert_err_has "domain"
s_assert_err_has "CONTENT"

# An unknown TIER is still a caller bug even when the domain is impeccable —
# the second axis does not soften the first.
resolve implementor content
[ "$S_STATUS" = 2 ] && pass "an unknown tier with a valid domain still exits 2" ||
	fail "unknown tier with a domain exited $S_STATUS, expected 2"
s_assert_err_has "unknown capability tier"

# ---------------------------------------------------------------------------
banner "No domain argument — byte-for-byte the behaviour that shipped at 0.6.0"
# ---------------------------------------------------------------------------
# The whole point of making the argument optional: every existing caller — the
# skills, the adapters' worked example, a consumer's own script — keeps working
# without being touched.
resolve implementer
s_assert_resolved "model-for-implementing" "one argument still resolves the plain tier mapping"
s_assert_err_lacks "UNMAPPED"

resolve planner
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

resolve implementer
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
write_config "$OWN/scripts/agents.config.sh" "$CONFIG_FULL"
resolve_from "$OWN" "$OWN/tools/agents.lib.sh" mechanical
s_assert_resolved "model-for-mechanical" "the repo root's scripts/agents.config.sh is found with no env var set"

# Order 3 — a sibling agents.config.sh, for a library that is not in a repo at
# all. Run from a different directory to show the answer does not depend on
# where the caller stands.
LOOSE="$SCRATCH/loose"
install_lib "$LOOSE"
write_config "$LOOSE/agents.config.sh" "$CONFIG_FULL"
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
write_config "$FOREIGN/scripts/agents.config.sh" "$(
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
resolve planner
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
resolve implementer
KIT_IMPLEMENTER=$S_OUT

resolve implementer content
if [ "$S_STATUS" = 0 ] && [ -n "$S_OUT" ] && [ "$S_OUT" != "$KIT_IMPLEMENTER" ]; then
	pass "kit config routes 'implementer content' ('$S_OUT') away from the plain tier ('$KIT_IMPLEMENTER')"
else
	fail "kit config did not route 'implementer content' — status $S_STATUS, stdout '$S_OUT', plain tier '$KIT_IMPLEMENTER'"
	printf '%s\n' "$S_ERR" | sed 's/^/        | /'
fi
s_assert_err_lacks "UNMAPPED"

resolve implementer code
if [ "$S_STATUS" = 0 ] && [ "$S_OUT" = "$KIT_IMPLEMENTER" ]; then
	pass "kit config leaves 'implementer code' on the plain tier ('$S_OUT') — an unmapped domain is the ordinary case"
else
	fail "kit config resolved 'implementer code' to '$S_OUT', expected the plain tier's '$KIT_IMPLEMENTER'"
	printf '%s\n' "$S_ERR" | sed 's/^/        | /'
fi
s_assert_err_lacks "UNMAPPED"

# The consumer-shipped file is untouched by this: it still resolves every tier
# to EMPTY. The kit names no model to consumers, even while naming one to
# itself.
AGENTS_CONFIG="$SHIPPED"
export AGENTS_CONFIG
for tier in planner implementer mechanical reviewer; do
	resolve "$tier"
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

# (2) The session runs on the plain reviewer's model and asks for the plain reviewer: nothing differs — print nothing, say why.
wrap "$K_REV" reviewer
[ "$W_STATUS" = 0 ] && [ -z "$W_OUT" ] &&
	pass "on a '$K_REV' session, 'reviewer' prints nothing rather than the session's own model" ||
	fail "on a '$K_REV' session, 'reviewer' printed '$W_OUT' (status $W_STATUS) — that is the implementer's own model"
case "$W_ERR_TEXT" in
*"share the author's model"*) pass "…and warns that the review will share the author's model" ;;
*) fail "…but did not say the review shares the author's model — stderr: '$W_ERR_TEXT'" ;;
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
	# And the reviewer crosses vendors in both — the property the kit calls its
	# highest-leverage wiring, here asserted rather than hoped for.
	t_run_split env AGENTS_CONFIG="$f" sh "$LIB" --harness reviewer
	[ -n "$S_OUT" ] && pass "$_label: the reviewer runs on agent harness '$S_OUT', not the session's own" ||
		fail "$_label: the reviewer names no agent harness — the review shares the author's vendor"
done
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
# own. Asserted against a THROWAWAY policy, never the kit's — the kit's
# reviewer crosses vendors, where there is nothing to refuse.
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
res reviewer self-implemented
[ "$S_OUT" = vendor-mid-4 ] &&
	pass "with no session named there is nothing to compare, and the mapping answers" ||
	fail "an unnamed session changed the answer to '$S_OUT'"
# The harness half asks a different question and is never compared.
resolve_as vendor-mid-4 --harness reviewer
[ "$S_STATUS" = 0 ] &&
	case "$S_ERR" in *"session's own model"*) false ;; *) true ;; esac &&
	pass "--harness is not a model, so it is not refused" ||
	fail "--harness reviewer was refused: '$S_ERR'"
# The quiet switch silences this warning like every other.
t_run_split env AGENTS_CONFIG="$LOCALREV" AGENT_SESSION_MODEL=vendor-mid-4 AGENTS_TIER_QUIET=1 sh "$LIB" reviewer self-implemented
[ "$S_OUT" = vendor-strong-9 ] && [ -z "$S_ERR" ] &&
	pass "AGENTS_TIER_QUIET=1 keeps the fallback and drops the warning" ||
	fail "quiet mode: stdout '$S_OUT', stderr '$S_ERR'"
# The SHIPPED mapping is empty, so there is nothing to refuse and nothing changes.
t_run_split env AGENTS_CONFIG="$SHIPPED" AGENT_SESSION_MODEL=anything sh "$LIB" reviewer
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	pass "against the shipped empty mapping the rule is inert, as it must be" ||
	fail "the shipped mapping resolved '$S_OUT' with a session named"

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
# …and the session may name itself in EITHER spelling: a session that knows
# only its spawn word must be refused as surely as one that knows the id.
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=probe AGENT_SESSION_MODEL=mid sh scripts/agents.kit.sh --alias reviewer self-implemented
[ "$S_OUT" = strong ] &&
	pass "the session's model matches in the spawn-word spelling too" ||
	fail "AGENT_SESSION_MODEL=mid gave '$S_OUT' — only the pinned spelling is compared"
t_run_split env -C "$PROBE" AGENT_HARNESS_SELF=probe AGENT_SESSION_MODEL=mid sh scripts/agents.kit.sh reviewer self-implemented
[ "$S_OUT" = vendor-strong-9 ] &&
	pass "and the model path matches the spawn-word spelling as well" ||
	fail "the model path gave '$S_OUT' for a spawn-word session"
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
[ "$S_OUT" = haiku ] && pass "--alias mechanical is 'haiku' — a dated id folds to its family too" ||
	fail "--alias mechanical gave '$S_OUT'"
t_run_split sh "$KIT_WRAPPER" --alias implementer content
[ "$S_OUT" = fable ] && pass "--alias carries the domain through" || fail "--alias with a domain gave '$S_OUT'"
# A value that is not an Anthropic id has no spawn word: it belongs to another
# agent harness, and printing a guess would be worse than printing nothing.
t_run_split sh "$KIT_WRAPPER" --alias reviewer
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	pass "--alias prints nothing for a tier that crosses agent harnesses — it is not spawnable in session" ||
	fail "--alias reviewer printed '$S_OUT' (status $S_STATUS); the reviewer crosses vendors and has no in-session spawn word"
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
