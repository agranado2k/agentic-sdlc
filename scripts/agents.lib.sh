#!/bin/sh
# agents.lib.sh — THE capability-tier resolver. One implementation, many callers.
#
# Answers one question: "which execution model does this tier run on?"
#
#   sh scripts/agents.lib.sh <tier> [domain]   -> prints the mapped model id,
#                                                  or nothing if it is unmapped
#   . scripts/agents.lib.sh; resolve_tier …    -> the same, as a shell function;
#      set AGENTS_CONFIG=<file> or _agents_here=<dir> BEFORE sourcing, as its
#      own statement (a prefix assignment on `.` is dropped by bash and zsh)
#
# tier    CLOSED: planner | implementer | mechanical | reviewer. Unknown: exit 2.
# domain  OPEN local policy, shape `[a-z][a-z0-9-]*`; hyphens fold to `_` in
#         the variable name. Unmapped: falls back to the tier, silently.
#
# Config resolution, first hit wins: 1. $AGENTS_CONFIG (set but missing is
# exit 2) · 2. <this file's repo root>/scripts/agents.config.sh · 3. <this
# file's dir>/agents.config.sh. Orders 2–3 anchor on THIS file, never on the
# caller's cwd; a sourcing caller that set neither variable gets nothing.
# Variable resolution, first NON-EMPTY wins: AGENT_TIER_<TIER>_<DOMAIN> (only
# with a domain) · AGENT_TIER_<TIER>.
#
# Exit: 0 resolved (a value, or deliberately nothing — an unmapped tier warns
# once per process, AGENTS_TIER_QUIET=1 silences it, the caller spawns with no
# model) · 2 usage error, unknown tier, bad domain, or a missing named config.
#
# Shared layer (see VERSION): the mechanism ships and is copied verbatim; the
# mapping in scripts/agents.config.sh is yours and a kit update never
# overwrites it; the kit names no model — the root manual's "Capability
# tiers" section says why. The design's history: the agentic-sdlc repository's
# diary, entry of 2026-09-03.

# The domain's SHAPE, written once so the usage text and the error text cannot
# drift apart. It does NOT drive the case pattern that enforces the shape —
# that pattern spells out the alphabet, for the locale reason documented where
# it lives — so this string and that pattern are kept in sync by hand. The
# four tier names are likewise spelled at their three literal sites (the
# check, the usage text, the unknown-tier error) and move together: a sourced
# config could reassign a global, so there is no list variable to reassign.
AGENT_DOMAIN_SHAPE='[a-z][a-z0-9-]*'

# MODULE GLOBALS, and why they diverge from guards.lib.sh's convention.
#
# guards.lib.sh takes its "directory of the calling script" as a PARAMETER,
# because it is only ever sourced by a script that knows where it lives. This
# file is also EXECUTED directly (`sh scripts/agents.lib.sh implementer` — the
# seam an agent following a SKILL.md actually uses), and in that case the only
# thing that knows the directory is `$0`, which is read at the bottom of the
# file, long after resolve_tier's signature is fixed at one argument: the tier.
# Threading the directory through as a second parameter would put a value the
# CALLER cannot supply into the caller's hands. So it is a global, set once by
# the direct-execution branch, and settable by a sourcing caller — which is the
# only way such a caller gets orders 2 and 3 at all.
#
# It defaults to EMPTY on purpose: empty means orders 2 and 3 are both
# skipped, so a sourcing caller that has not said where it is gets
# $AGENTS_CONFIG or nothing — never a config from whatever directory the
# process happens to be standing in.
#
# The other two globals are per-process memos: config loading and the unmapped
# warning both have to happen at most once no matter how many tiers a single
# process resolves.
_agents_here=${_agents_here:-}
_agents_config_loaded=0
_agents_config_tried=0
_agents_warned=0

agents_usage() {
	echo "usage: agents.lib.sh <tier> [domain]" >&2
	echo "  tier is one of: planner implementer mechanical reviewer" >&2
	echo "  domain is an optional $AGENT_DOMAIN_SHAPE token naming the medium of the work." >&2
}

# agents_load_config — source the mapping, once per process.
#
# Returns 0 when a config was loaded, 1 when none exists anywhere (not an
# error — see the unconfigured default above), 2 when an explicitly named one
# is missing.
#
# The MISS is memoized too, not only the hit: an unconfigured project is the
# common case, and one process resolves several tiers.
#
# Only the genuine "no config anywhere" miss is remembered. An explicitly named
# AGENTS_CONFIG that does not exist keeps failing on every call, loudly: that is
# a caller error, and a caller error that reports itself once and then goes
# quiet is worse than one that keeps saying so.
agents_load_config() {
	[ "$_agents_config_loaded" = 1 ] && return 0
	[ "$_agents_config_tried" = 1 ] && return 1

	if [ -n "${AGENTS_CONFIG:-}" ]; then
		if [ ! -f "$AGENTS_CONFIG" ]; then
			echo "x agents: AGENTS_CONFIG=$AGENTS_CONFIG does not exist." >&2
			return 2
		fi
		. "$AGENTS_CONFIG"
		_agents_config_loaded=1
		return 0
	fi

	# Orders 2 and 3 are both anchored on $_agents_here — where the LIBRARY
	# lives — and never on the directory the caller happens to be standing in.
	#
	# A config file is SOURCED, which is to say EXECUTED, so this is a trust
	# question and not a convenience one. Order 2 used to ask `git rev-parse
	# --show-toplevel` about the process's CURRENT DIRECTORY: resolving a tier
	# with the cwd inside a cloned third-party repo therefore ran that clone's
	# scripts/agents.config.sh. The root manual's trust boundary names cloned
	# third-party repos as untrusted content, and untrusted content is data,
	# never code to run. Asking git about $_agents_here takes the cwd out of
	# the trust path altogether rather than validating it, and it keeps working
	# when the cwd is in no repository at all.
	#
	# When $_agents_here is EMPTY there is nothing to anchor on, so both orders
	# are skipped and a caller gets $AGENTS_CONFIG or nothing — never the
	# process's current directory in order-3 clothes.
	if [ -n "$_agents_here" ]; then
		_al_root=$(git -C "$_agents_here" rev-parse --show-toplevel 2>/dev/null) || _al_root=
		if [ -n "$_al_root" ] && [ -f "$_al_root/scripts/agents.config.sh" ]; then
			. "$_al_root/scripts/agents.config.sh"
			_agents_config_loaded=1
			return 0
		fi

		if [ -f "$_agents_here/agents.config.sh" ]; then
			. "$_agents_here/agents.config.sh"
			_agents_config_loaded=1
			return 0
		fi
	fi

	_agents_config_tried=1
	return 1
}

# resolve_tier <tier> [domain] — print the mapped model id on stdout,
# diagnostics on stderr. Stdout carries the ANSWER and nothing else, so a caller
# can use it directly: `model=$(sh scripts/agents.lib.sh implementer content)`.
resolve_tier() {
	if [ $# -lt 1 ] || [ $# -gt 2 ] || [ -z "${1:-}" ]; then
		agents_usage
		return 2
	fi

	# The accept-check is a LITERAL `case`, not a loop over a variable holding
	# the list, for two independent reasons.
	#
	# PORTABILITY, the one that was actually broken: `for t in $list`
	# relies on the shell word-splitting an unquoted expansion, and zsh does not
	# (SH_WORD_SPLIT is off by default). Under `zsh scripts/agents.lib.sh
	# implementer` the loop saw ONE word — the whole string — so every real tier
	# name was rejected as unknown. A `case` compares patterns, never words, and
	# behaves identically in sh, bash, ksh and zsh.
	#
	# TRUST, a smaller share of it: a sourced config is trusted code — it
	# could redefine resolve_tier wholesale, so this literal is NOT a security
	# boundary against a hostile config. What it does buy: the accepted set
	# can no longer drift via a reassigned global or a shell's splitting
	# rules. The MESSAGES spell the same four names as literals too (no
	# global survives for a config to reassign), so check and diagnostics
	# cannot disagree — the four names are spelled at their three literal sites (see AGENT_DOMAIN_SHAPE's comment).
	_rt_tier=$1
	_rt_domain=${2:-}
	case "$_rt_tier" in
	planner | implementer | mechanical | reviewer) _rt_known=1 ;;
	*) _rt_known=0 ;;
	esac
	if [ "$_rt_known" = 0 ]; then
		echo "x agents: unknown capability tier '$_rt_tier'." >&2
		echo "  The vocabulary is closed: planner implementer mechanical reviewer." >&2
		echo "  It is defined in the manual layer; a ticket that needs another word needs a manual change first." >&2
		return 2
	fi

	# The domain's shape check, run only when one was actually passed. It is the
	# tier whitelist's counterpart: the tier is safe to interpolate because it is
	# one of four literals, and the domain is safe to interpolate because
	# NOTHING outside [a-z0-9-] gets past this case. Order matters — the tier is
	# checked first, so `implementor content` reports the typo that is actually
	# wrong rather than the argument that is fine.
	#
	# The alphabet is spelled out rather than written `[!a-z]`, and that is not
	# fussiness. A bracket RANGE in a shell pattern is resolved by the current
	# locale's collation, and in the en_US.UTF-8 that a developer's terminal
	# defaults to, `a-z` interleaves the cases — so `[!a-z]*` accepts `CONTENT`,
	# reads a variable nobody wrote, and silently falls back. The check that is
	# the whitelist for an `eval` cannot be one whose meaning moves with $LANG.
	if [ $# -eq 2 ]; then
		case $_rt_domain in
		'' | [!abcdefghijklmnopqrstuvwxyz]* | *[!abcdefghijklmnopqrstuvwxyz0123456789-]*)
			echo "x agents: malformed task domain '$_rt_domain'." >&2
			echo "  A domain is a $AGENT_DOMAIN_SHAPE token — e.g. code, content, html-report." >&2
			echo "  The vocabulary is open (it is your project's policy); the token's shape is not," >&2
			echo "  because it is interpolated into the variable name this resolver reads." >&2
			return 2
			;;
		esac
	fi

	# `|| _rt_load=$?` rather than a bare call, and it is load-bearing. Most
	# consumer scripts and hooks run `set -e`, under which a BARE call to a
	# function that returns 1 terminates the caller before its status can be
	# read — and 1 is agents_load_config's NORMAL "no config anywhere" answer,
	# the state every freshly bootstrapped project is in. A bare call therefore
	# killed the commonest caller in the commonest state, and killed it
	# silently: no value, no warning, no error. A command in an AND-OR list is
	# exempt from `set -e`, so here the status survives to be read.
	_rt_load=0
	agents_load_config || _rt_load=$?
	[ "$_rt_load" = 2 ] && return 2

	# Tier name -> variable name. The tier is already whitelisted above, so the
	# eval can only ever expand one of four literal variable names.
	_rt_upper=$(printf '%s' "$_rt_tier" | tr 'a-z' 'A-Z')

	# The domain-qualified variable first, when there is one. `tr` folds the
	# token's legal hyphens into the underscores a variable name needs, and the
	# shape check above guarantees there is nothing else left to fold.
	_rt_value=
	if [ -n "$_rt_domain" ]; then
		_rt_dupper=$(printf '%s' "$_rt_domain" | tr 'a-z-' 'A-Z_')
		eval "_rt_value=\${AGENT_TIER_${_rt_upper}_${_rt_dupper}:-}"
	fi

	# Unset or empty falls through to the tier — the same test for both, because
	# a project that mapped a domain to '' has said "no opinion here" just as
	# clearly as one that never named it.
	if [ -z "$_rt_value" ]; then
		eval "_rt_value=\${AGENT_TIER_${_rt_upper}:-}"
	fi

	if [ -z "$_rt_value" ]; then
		if [ "$_agents_warned" = 0 ] && [ "${AGENTS_TIER_QUIET:-}" != "1" ]; then
			_agents_warned=1
			echo "!  agents: capability tier '$_rt_tier' is UNMAPPED — no model configured." >&2
			echo "   Set AGENT_TIER_${_rt_upper} in scripts/agents.config.sh to map it." >&2
			echo "   Until then every tier runs on the session's own model, and the planner's" >&2
			echo "   cost/benefit decision has no effect on what anything actually costs." >&2
		fi
		return 0
	fi

	printf '%s\n' "$_rt_value"
	return 0
}

# Direct execution: the seam an agent following a SKILL.md actually uses, since
# an agent runs commands rather than sourcing shell libraries. Sourcing callers
# fall through with only the functions defined.
#
# THE $0 TEST ALONE IS NOT ENOUGH, and the shell it fails in is the shell most
# operators type into. zsh sets $0 to the SOURCED FILE'S path (FUNCTION_ARGZERO,
# on by default), so `source scripts/agents.lib.sh` matched the pattern below:
# the library ran resolve_tier against the SHELL'S own arguments and then
# `exit`ed, killing the interactive session that sourced it. sh, bash and ksh
# all leave $0 as the caller's own, so there the pattern already tells the truth.
#
# ZSH_EVAL_CONTEXT is zsh's own answer to the question. It is a colon-joined
# stack of what the shell is currently doing, and every file being sourced
# pushes a `file` component onto it — `cmdarg:file`, `toplevel:file`,
# `toplevel:shfunc:file`. zsh EXECUTING this script is plain `toplevel`, with no
# `file`. Nothing else sets the variable, so under sh/bash/ksh it is empty and
# this test costs one unmatched `case`.
_agents_sourced=0
case "${ZSH_EVAL_CONTEXT:-}" in
*:file | *:file:*) _agents_sourced=1 ;;
esac

if [ "$_agents_sourced" = 0 ]; then
	case "$0" in
	*/agents.lib.sh | agents.lib.sh)
		_agents_here=$(dirname "$0")
		resolve_tier "$@"
		exit $?
		;;
	esac
fi
