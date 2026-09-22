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
warn() { [ "${AGENTS_TIER_QUIET:-}" = 1 ] || printf 'agents.kit.sh: %s\n' "$1" >&2; }
answer=$(sh scripts/agents.lib.sh "$@") || exit $?
if [ "$answer" != "$AGENT_SESSION_MODEL" ]; then
	# An unmapped tier is zero bytes, never a bare newline: the caller's
	# `[ -n "$(...)" ]` is the whole protocol for "nothing".
	[ -n "$answer" ] && printf '%s\n' "$answer"
	exit 0
fi
plain=$(sh scripts/agents.lib.sh reviewer) || exit $?
if [ -n "$plain" ] && [ "$plain" != "$AGENT_SESSION_MODEL" ]; then
	warn "reviewer${asked_domain:+ $asked_domain} resolves to the session's own model ($AGENT_SESSION_MODEL); falling back to the reviewer tier ($plain)"
	printf '%s\n' "$plain"
else
	warn "no reviewer model differs from the session's own ($AGENT_SESSION_MODEL) — the review will share the author's model"
fi
exit 0
