#!/bin/sh
# trace.kit.sh — the kit's own trace script. Kit-authoring only, never shipped
# (bootstrap.sh's KIT_ONLY list deletes it, the same as tests/ and
# scripts/trace.kit.config.sh beside it).
#
# Every SKILL.md that emits a decision says the plain `sh scripts/trace.sh …`,
# and it has to: skills ship unstamped to every consumer, so none of them may
# name a kit-only file. Typed literally in THIS repo, that command reads the
# shipped scripts/trace.config.sh — empty by principle — and writes nothing.
# The kit's own policy lives in scripts/trace.kit.config.sh, reached through
# the script's TRACE_CONFIG seam; this wrapper is the substitution, one name in
# place of scripts/trace.sh with the same arguments, which AGENTS.md hard rule
# 10 makes the one this repo's sessions actually make. `"$@"`, so the script's
# whole signature reaches it.
TRACE_CONFIG=scripts/trace.kit.config.sh exec sh scripts/trace.sh "$@"
