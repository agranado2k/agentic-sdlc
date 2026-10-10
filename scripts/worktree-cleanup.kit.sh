#!/bin/sh
# worktree-cleanup.kit.sh — the kit's own worktree cleanup. Kit-authoring only,
# never shipped (bootstrap.sh's KIT_ONLY list deletes it, beside the other
# *.kit.sh twins).
#
# scripts/worktree-cleanup.sh asks scripts/trace.sh whether a live session
# still holds a merged worktree (#680, the kit's ADR-0023). Run bare in THIS
# repo, the trace reads the shipped scripts/trace.config.sh — empty on purpose
# — sees no run, and a live session's worktree is pruned. The kit's policy is
# scripts/trace.kit.config.sh, reached through the trace's TRACE_CONFIG seam;
# this wrapper is that seam set once, so nobody has to remember an environment
# prefix (ADR-0003's reason for agents.kit.sh, applied to the cleanup). Paths
# are taken from where this file lives, so it reads the same policy from the
# root checkout or from inside a linked worktree.
#
# Usage:
#   sh scripts/worktree-cleanup.kit.sh [--dry-run]
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
TRACE_CONFIG="$here/trace.kit.config.sh" exec sh "$here/worktree-cleanup.sh" "$@"
