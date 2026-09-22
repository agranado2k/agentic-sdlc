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
# already exposed for exactly this case and delegates (and, for the reviewer
# tier, compares the answer — the section below). `"$@"` rather than a fixed one-argument form, so the
# resolver's WHOLE signature reaches it — including the optional task domain,
# which a wrapper that took `$1` alone would silently drop while still
# resolving every tier correctly. tests/agents-tiers.test.sh asserts the
# pass-through for exactly that reason.
#
# THE ONE THING THIS WRAPPER ADDS (#224, ADR-0007)
# ---------------------------------------------------------------------------
# The mapping's `self-implemented` reviewer is one model, chosen on the
# assumption that the session runs on the planner's — so on a session that
# runs on THAT model the answer is the implementer's own, the exact case the
# domain exists to avoid. The policy file cannot know who is asking; the caller
# can say. When $AGENT_SESSION_MODEL names the session's model (the same
# word the policy file uses) and the resolver's answer for the reviewer tier
# equals it, this wrapper warns once and falls back to the plain reviewer
# tier; when that too equals it, it warns that the review will share the
# author's model and prints nothing, so the spawn inherits the session and
# the report has to say so. With the variable unset, or for any tier but the
# reviewer, the wrapper is the exec it always was. This lives here and not in
# the shared resolver because the resolver is shared layer: moving the rule
# there is a release, and 0.21.0 is where it goes.
#
# Usage:
#   sh scripts/agents.kit.sh <tier> [domain]
#   AGENT_SESSION_MODEL=<model> sh scripts/agents.kit.sh reviewer [domain]
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

# THE FOLD, and the comparison that guards it.
#
# `--alias <tier> [domain]` prints the word the IN-SESSION spawn parameter
# takes, where `--model` prints the id a CLI takes. Both spellings name one
# model; they exist because the policy files PIN ids (`claude-opus-5`) so a
# roster moving is a decision someone commits, while the Agent/Task tool's
# parameter accepts only the family word (adapters/claude-code/README.md).
# The fold strips the vendor prefix and keeps the family.
#
# The ADR-0007 refusal reaches BOTH paths, and compares the session's model
# in BOTH spellings. A session that knows only its spawn word must be refused
# as surely as one that knows its pinned id — the policy files call this
# wrapper the net under the reviewer rule, and a net with one side open is
# not one.
fold_alias() {
	case "$1" in
	'') ;;
	*-*-*)
		_fa=${1#*-}
		printf '%s\n' "${_fa%%-*}"
		;;
	*) printf '%s\n' "$1" ;;
	esac
}
# same_as_session <value> — true when the value names the session's own model
# in either spelling.
same_as_session() {
	[ -n "${AGENT_SESSION_MODEL:-}" ] || return 1
	[ "$1" = "$AGENT_SESSION_MODEL" ] && return 0
	[ "$(fold_alias "$1")" = "$AGENT_SESSION_MODEL" ] && return 0
	[ "$(fold_alias "$1")" = "$(fold_alias "$AGENT_SESSION_MODEL")" ]
}
warn() { [ "${AGENTS_TIER_QUIET:-}" = 1 ] || printf 'agents.kit.sh: %s\n' "$1" >&2; }

if [ "${1:-}" = --alias ]; then
	shift
	[ $# -gt 0 ] || { echo "agents.kit.sh: --alias needs a tier" >&2; exit 2; }
	# The harness half FIRST: `--model` strips the prefix and warns, so by the
	# time the model half is in hand a crossing looks like a local answer. A
	# tier that crosses prints NOTHING — it cannot be spawned in session at
	# all, and a guess would send the work to the wrong vendor silently.
	# The harness probe is the one call whose stderr is dropped: it duplicates
	# the diagnostics the model call below prints, and a caller should see
	# each of them once. The model call keeps its stderr, so an unknown tier
	# still says why it exited 2 rather than failing in silence.
	_alias_harness=$(sh scripts/agents.lib.sh --harness "$@" 2>/dev/null) || {
		sh scripts/agents.lib.sh "$@" >/dev/null
		exit $?
	}
	[ -z "$_alias_harness" ] || exit 0
	_alias_value=$(sh scripts/agents.lib.sh "$@") || exit $?
	_alias_tier=$1
	if [ "$_alias_tier" = reviewer ] && same_as_session "$_alias_value"; then
		_alias_plain=$(sh scripts/agents.lib.sh reviewer 2>/dev/null) || exit $?
		if [ -n "$_alias_plain" ] && ! same_as_session "$_alias_plain"; then
			warn "reviewer${2:+ $2} resolves to the session's own model ($AGENT_SESSION_MODEL); falling back to the reviewer tier"
			fold_alias "$_alias_plain"
		else
			warn "no reviewer model differs from the session's own ($AGENT_SESSION_MODEL) — the review will share the author's model"
		fi
		exit 0
	fi
	fold_alias "$_alias_value"
	exit 0
fi
# The tier is not always $1: the resolver's signature admits a leading
# `--model` or `--harness` (ADR-0005 clause 4), and scripts/agents.config.sh
# documents `--model <tier>` as how you read the mapping's model half back. A
# guard that read $1 alone would let the refused answer through by the very
# spelling the policy file teaches. `--harness` asks a different question —
# a harness token is not a model — so only the model half is ever compared.
asked_tier=${1:-}
asked_domain=${2:-}
case "$asked_tier" in
--model) asked_tier=${2:-}; asked_domain=${3:-} ;;
--harness) asked_tier='' ;;
esac
if [ -z "${AGENT_SESSION_MODEL:-}" ] || [ "$asked_tier" != reviewer ]; then
	exec sh scripts/agents.lib.sh "$@"
fi
answer=$(sh scripts/agents.lib.sh "$@") || exit $?
if ! same_as_session "$answer"; then
	# An unmapped tier is zero bytes, never a bare newline: the caller's
	# `[ -n "$(...)" ]` is the whole protocol for "nothing".
	[ -n "$answer" ] && printf '%s\n' "$answer"
	exit 0
fi
plain=$(sh scripts/agents.lib.sh reviewer) || exit $?
if [ -n "$plain" ] && ! same_as_session "$plain"; then
	warn "reviewer${asked_domain:+ $asked_domain} resolves to the session's own model ($AGENT_SESSION_MODEL); falling back to the reviewer tier ($plain)"
	printf '%s\n' "$plain"
else
	warn "no reviewer model differs from the session's own ($AGENT_SESSION_MODEL) — the review will share the author's model"
fi
exit 0
