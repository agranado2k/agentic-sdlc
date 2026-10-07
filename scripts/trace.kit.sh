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
#
# The AGENTS policy too (#569): a spawn's model is held to the ids the shipped
# resolver lists, and the resolver alone would read the shipped empty
# scripts/agents.config.sh and refuse every model. So the wrapper hands it the
# policy this session's agents wrapper chose — the one `sh scripts/agents.kit.sh
# <tier>` resolved the model from — overriding any inherited AGENTS_CONFIG,
# exactly as that wrapper does.
AGENTS_CONFIG=$(sh scripts/agents.kit.sh --policy) || exit 2
export AGENTS_CONFIG
TRACE_CONFIG=scripts/trace.kit.config.sh exec sh scripts/trace.sh "$@"
