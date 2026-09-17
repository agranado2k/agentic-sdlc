#!/bin/sh
# guards.kit.sh — the kit's own pairing guard. Kit-authoring only, never
# shipped (bootstrap.sh's KIT_ONLY list deletes it, beside
# scripts/guards.kit.config.sh and the agents.kit pair that set the pattern).
#
# scripts/tdd-pairing-guard.sh reads its policy through discovery, and in this
# repo discovery finds scripts/guards.config.sh — which ships EMPTY on purpose,
# so run bare the guard is INACTIVE here. The kit's real pattern lives in
# scripts/guards.kit.config.sh, reached through the guard's existing
# $GUARDS_CONFIG seam (discovery order 1 in scripts/guards.lib.sh). This
# wrapper is that seam, set once, so that .githooks/pre-push, a CI job and an
# operator at a terminal all run the same command instead of each remembering
# an environment prefix — ADR-0003's reason for scripts/agents.kit.sh, applied
# to the guard.
#
# Usage:
#   sh scripts/guards.kit.sh <base sha> <head sha>
set -eu
GUARDS_CONFIG=scripts/guards.kit.config.sh exec sh scripts/tdd-pairing-guard.sh "$@"
