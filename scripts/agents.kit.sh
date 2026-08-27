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
# byte-identical to every project that runs it — this wrapper changes nothing
# about the resolver, it only sets the seam already exposed for exactly this
# case and delegates. `"$@"` rather than a fixed one-argument form, so the
# resolver's WHOLE signature reaches it — including the optional task domain,
# which a wrapper that took `$1` alone would silently drop while still
# resolving every tier correctly. tests/agents-tiers.test.sh asserts the
# pass-through for exactly that reason.
#
# Usage:
#   sh scripts/agents.kit.sh <tier> [domain]
set -eu
AGENTS_CONFIG=scripts/agents.kit.config.sh exec sh scripts/agents.lib.sh "$@"
