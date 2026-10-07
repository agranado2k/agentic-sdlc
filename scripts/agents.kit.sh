#!/bin/sh
# agents.kit.sh — the kit's own tier resolver. Kit-authoring only, never
# shipped (bootstrap.sh's KIT_ONLY list deletes it, the same as tests/ and
# scripts/agents.kit.config.sh beside it).
#
# WHY THIS EXISTS
# ---------------------------------------------------------------------------
# Every SKILL.md that spawns a subagent instructs the plain
# `sh scripts/agents.lib.sh <tier>`, and it has to: skills ship unstamped to
# every consumer (AGENTS.md, "The chain"), so none of them may name a
# kit-only file. That plain command is correct for a consumer project.
#
# Typed literally in THIS repo, it is not: scripts/agents.config.sh — the
# file the resolver falls back to — ships EMPTY here too, by principle (see
# that file's own comments), so the command resolves nothing and the spawn
# silently inherits the session's own model regardless of the ticket's tier.
# The kit's real mapping lives in scripts/agents.kit.config.sh, reached
# through the resolver's existing $AGENTS_CONFIG seam (resolution order #1 in
# scripts/agents.lib.sh):
#
#   AGENTS_CONFIG=scripts/agents.kit.config.sh sh scripts/agents.lib.sh <tier>
#
# That line is correct but easy to get wrong at the point of spawning — an
# environment prefix a session has to remember AND type correctly, every
# tier, every time a SKILL.md says to resolve one. This script is the
# substitution instead: one name, in place of scripts/agents.lib.sh, with the
# same argument. AGENTS.md hard rule 10 is what makes that substitution the
# one this repo's sessions actually make.
#
# scripts/agents.lib.sh itself is shared layer (see VERSION) and stays
# byte-identical to every project that runs it: this wrapper sets the seam
# already exposed for exactly this case and delegates. `"$@"` rather than a fixed one-argument form, so the
# resolver's WHOLE signature reaches it — including the optional task domain,
# which a wrapper that took `$1` alone would silently drop while still
# resolving every tier correctly. tests/agents-tiers.test.sh asserts the
# pass-through for exactly that reason.
#
# WHAT THIS WRAPPER NO LONGER ADDS (#224 → #226, ADR-0007)
# ---------------------------------------------------------------------------
# It used to carry the reviewer refusal: a session handed its own model to
# review with, because a `self-implemented` mapping answers one model chosen
# assuming the session runs on another. That lived here only because the
# resolver is shared layer and the fix was not a release. 0.22.0 is that
# release — the rule is in scripts/agents.lib.sh now, so every consumer gets
# it, and nothing of it is left here to drift from it.
#
# Usage:
#   sh scripts/agents.kit.sh <tier> [domain]
#   AGENT_SESSION_MODEL=<model> sh scripts/agents.kit.sh reviewer [domain]
#   AGENT_UNREACHABLE_MODELS='<id or spawn word> …' sh scripts/agents.kit.sh reviewer [domain]
#   AGENT_HARNESS_SELF=codex sh scripts/agents.kit.sh <tier> [domain]
#   sh scripts/agents.kit.sh --policy        # which policy file this session uses
#   sh scripts/agents.kit.sh --alias <tier> [domain]   # the in-session spawn word
set -eu
# WHICH POLICY. The operator drives this repo from two agent harnesses and
# each has its own tier policy — what is a local spawn in one is a crossing in
# the other, so one file could not answer both. $AGENT_HARNESS_SELF names the
# session's own harness, and this wrapper picks the file for it — overriding
# whatever $AGENTS_CONFIG the caller's environment carried, exactly as it
# always did: the wrapper's whole job is to set that seam itself, and a value
# that deferred to the environment would resolve the shipped empty file in
# any session that happened to export one. A harness with no policy file of
# its own falls back to the Claude Code policy, which is how this repo is
# usually driven — a missing file must not turn every tier into a silent
# inherit. To resolve some OTHER policy deliberately, call the resolver
# directly with $AGENTS_CONFIG, the way the suites do.
AGENTS_CONFIG=scripts/agents.kit.config.sh
case "${AGENT_HARNESS_SELF:-}" in
'' | claude-code) ;;
*)
	_kit_candidate="scripts/agents.kit.${AGENT_HARNESS_SELF}.config.sh"
	[ -f "$_kit_candidate" ] && AGENTS_CONFIG=$_kit_candidate
	;;
esac
export AGENTS_CONFIG
# `--policy` prints the file this selection chose and exits. Other kit-only
# scripts need the same answer before they call something that resolves —
# scripts/skill-dispatch.kit.sh does — and asking for it beats a second copy
# of the case block above, which is how hand-kept lists in this repo have
# drifted before.
if [ "${1:-}" = --policy ]; then
	printf '%s\n' "$AGENTS_CONFIG"
	exit 0
fi

# `--alias <tier> [domain]` prints the word an IN-SESSION spawn parameter
# takes, where `--model` prints the id a CLI takes. Both name one model; they
# exist because the policy files PIN ids so a roster moving is a decision
# someone commits, while the Agent/Task tool's parameter accepts only the
# family word (adapters/claude-code/README.md).
#
# The ADR-0007 refusal is NOT here any more: 0.22.0 moved it into
# scripts/agents.lib.sh, where every consumer's mapping gets it too. This
# path resolves through that resolver like any other caller, so the answer it
# folds is already the refused-and-fallen-back one — one implementation, and
# the fold is applied to whatever it decided.
# _kit_fold <id> — the spawn word for a pinned id: the family segment, second
# of three or more (`claude-sonnet-5-5` -> `sonnet`); an id with fewer
# segments is its own word. One definition, read by `--alias` below and by the
# bridge that runs it backwards.
_kit_fold() {
	case "$1" in
	*-*-*)
		_kit_word=${1#*-}
		printf '%s\n' "${_kit_word%%-*}"
		;;
	*) printf '%s\n' "$1" ;;
	esac
}

# THE BRIDGE, BACKWARDS (ADR-0013 clause 2). A session that saw a reviewer
# spawn fail saw it under the spawn WORD it passed, while the resolver
# compares $AGENT_UNREACHABLE_MODELS to this policy's pinned ids, exactly —
# so a word named there would skip nothing. This wrapper owns the
# id-to-word fold, so it maps each such word back to EVERY pinned id it
# covers before delegating: all of them, the safe side, because the caller
# cannot say which one ran. A name that is itself a pinned id, or that folds
# from none, passes untouched — the resolver warns about the second kind.
# A value that crosses to a declared agent harness has no spawn word, so it
# is no id a word can cover — and whether it crosses is the resolver's
# answer, not this wrapper's: the subshell sources scripts/agents.lib.sh and
# asks its agents_split_harness, the one membership test (#559), rather than
# keeping a second copy here that could drift from it. The values it walks
# are the resolver's agents_values, the one enumeration --ids reads too.
if [ -n "${AGENT_UNREACHABLE_MODELS:-}" ] && [ -f "$AGENTS_CONFIG" ]; then
	_kit_pinned=$(
		. scripts/agents.lib.sh
		agents_load_config >/dev/null 2>&1
		AGENTS_TIER_QUIET=1
		agents_values 2>/dev/null | while IFS= read -r _kit_v; do
			agents_split_harness "$_kit_v"
			[ -n "$_ah_harness" ] || printf '%s\n' "$_kit_v"
		done
	)
	_kit_ids=' '
	for _kit_v in $_kit_pinned; do
		_kit_ids="$_kit_ids$_kit_v "
	done
	_kit_unr=
	for _kit_n in $AGENT_UNREACHABLE_MODELS; do
		_kit_cover=
		case $_kit_ids in
		*" $_kit_n "*) ;;
		*)
			for _kit_v in $_kit_ids; do
				if [ "$(_kit_fold "$_kit_v")" = "$_kit_n" ]; then
					_kit_cover="$_kit_cover $_kit_v"
				fi
			done
			;;
		esac
		_kit_unr="$_kit_unr ${_kit_cover:-$_kit_n}"
	done
	AGENT_UNREACHABLE_MODELS=$_kit_unr
	export AGENT_UNREACHABLE_MODELS
fi

if [ "${1:-}" = --alias ]; then
	shift
	[ $# -gt 0 ] || { echo "agents.kit.sh: --alias needs a tier" >&2; exit 2; }
	# The harness half first: a tier that crosses cannot be spawned in session
	# at all, and a guess would send the work to the wrong vendor silently.
	_alias_harness=$(sh scripts/agents.lib.sh --harness "$@" 2>/dev/null) || {
		sh scripts/agents.lib.sh "$@" >/dev/null
		exit $?
	}
	[ -z "$_alias_harness" ] || exit 0
	_alias_value=$(sh scripts/agents.lib.sh "$@") || exit $?
	[ -z "$_alias_value" ] || _kit_fold "$_alias_value"
	exit 0
fi
# Everything else is the resolver's, verbatim — including the reviewer rule
# this wrapper used to carry. 0.22.0 moved that into scripts/agents.lib.sh,
# so the wrapper is once again what its header describes: the policy choice,
# and a delegation.
exec sh scripts/agents.lib.sh "$@"
