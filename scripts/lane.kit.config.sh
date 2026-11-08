#!/bin/sh
# lane.kit.config.sh — the KIT's own lane policy. Kit-authoring only, never
# shipped (bootstrap.sh's KIT_ONLY list deletes it).
#
# scripts/lane.config.sh ships empty to every consumer, and must: the kit
# cannot name a consumer's operator. This twin holds the kit's own values, the
# arrangement scripts/agents.kit.config.sh has with scripts/agents.config.sh,
# and the landing script's lane mode (scripts/land.kit.sh --lane) reads it at
# the base branch through the policy reader, never from a pull request's tree
# (ADR-0039, ADR-0047 clause 2).
#
# THE LANE IS CLOSED HERE until the operator lands their forge login below
# (ADR-0047 clause 2): an empty LANE_OPERATOR holds every lane run with
# `closed`. Only the operator lands that change; a lane run holds any pull
# request that touches this file (ADR-0047 clause 4, PRD-10's `path` hold).
#
# LANE_OPERATOR  the lane's operator, a forge login: 1 to 39 letters, digits
#                and single inner hyphens. Any other value reads as none.
# LANE_HOLD_PATTERNS  paths no lane run lands, whatever their risk (PRD-10's
#                `path` hold): the landing script, the risk rule, the hooks,
#                the Claude Code adapter and its wiring, and the CI workflows.
#                A `*` crosses a `/`; scripts/lane.config.sh says the shape.
# LANE_LAND_COMMAND  the landing script; /pr-iterate's lane step runs it with --lane,
#                the pull request and its ticket (PRD-10, process/R80). A
#                closed lane still holds every run it makes with `closed`.

LANE_OPERATOR=''
LANE_LAND_COMMAND='sh scripts/land.kit.sh'
LANE_HOLD_PATTERNS='scripts/land.kit.sh scripts/risk.sh scripts/risk.kit.sh .githooks/* adapters/claude-code/* .claude/settings.json .github/workflows/*'
