#!/bin/sh
# agents.kit.config.sh — the KIT'S OWN tier -> model mapping. Not shipped.
#
# scripts/agents.config.sh ships EMPTY to every consumer, by principle: the kit
# names no model, because model identifiers rot on a vendor's schedule and a
# kit that shipped one would be shipping a lie with a timer on it (see that
# file's own comments — read them first, this file keeps the same shape).
#
# But the kit repo is itself a project that spawns subagents (f12 self-host:
# the kit follows its own constitution), and an unmapped resolver means every
# one of THIS repo's agents silently inherits the session model regardless of
# the tier its ticket was stamped with — the exact cost blindness the tier
# mechanism exists to remove, happening inside the tool that preaches it.
#
# So the kit carries its OWN mapping, in a file that is kit-authoring only and
# never reaches a consumer (bootstrap.sh's KIT_ONLY list deletes this file at
# stamp time, the same way it deletes tests/ and the kit's own CI). Resolve it
# with the resolver's existing $AGENTS_CONFIG seam (resolution order #1 in
# scripts/agents.lib.sh):
#
#   AGENTS_CONFIG=scripts/agents.kit.config.sh sh scripts/agents.lib.sh <tier>
#
# ---------------------------------------------------------------------------
# THESE IDS ROT. Last checked 2026-08-27, against the Claude Code harness's
# Agent/Task spawn tool (the `model` parameter — see
# adapters/claude-code/README.md for the wiring). Re-check them whenever that
# harness's model roster moves: a name below that the harness no longer
# accepts fails the spawn, not silently — but it fails at spawn time, which is
# later than a reviewer reading this file would like. The four aliases as of
# this check: `fable` (Claude Fable 5 — strongest, Mythos-class), `opus`
# (strongest coding workhorse), `sonnet` (strong general mid-tier), `haiku`
# (cheapest capable).
# ---------------------------------------------------------------------------
# THE VOCABULARY (same shape as scripts/agents.config.sh; repeated here only as
# the shape of the decision each variable encodes — the words are defined in
# the root AGENTS.md's "Capability tiers" section):
#
#   planner      Judgement over breadth. Decomposition, design, architecture,
#                triage of an ambiguous bug. Reads a lot, writes little, and a
#                wrong answer costs a whole wave of downstream work.
#   implementer  Judgement over depth. Building one ticket test-first through
#                seams it has to find. The default for real work.
#   mechanical   No judgement required, and a checkable definition of done. A
#                rename across call sites, a codemod, a dependency bump, the
#                contract half of an expand-migrate-contract. Cheap is correct
#                here: the test suite is the oracle, not the model.
#   reviewer     Judgement over a finished diff, in fresh context. Adversarial
#                reading rather than production. Undersizing this one is how a
#                review becomes a rubber stamp — and it must differ from the
#                model that implemented, or the "adversarial" part is theater.

# ---------------------------------------------------------------------------
# 1. PLANNER — strongest reasoning available. A wrong decomposition is paid
#    for by every downstream ticket, so this is the one tier where "most
#    expensive" is the cost-saving choice.
# ---------------------------------------------------------------------------
AGENT_TIER_PLANNER='fable'

# ---------------------------------------------------------------------------
# 2. IMPLEMENTER — best cost/capability for real coding work. This is where
#    most of the kit's own sessions land.
# ---------------------------------------------------------------------------
AGENT_TIER_IMPLEMENTER='opus'

# ---------------------------------------------------------------------------
# 3. MECHANICAL — cheapest capable model. The suite is the oracle; capability
#    past "can follow the pattern" buys nothing here.
# ---------------------------------------------------------------------------
AGENT_TIER_MECHANICAL='haiku'

# ---------------------------------------------------------------------------
# 4. REVIEWER — strongest reasoning, in fresh context, and DIFFERENT from
#    whatever implemented the diff. A cheap verdict is a rubber stamp, and a
#    reviewer sharing the implementer's model is one editorial pass wearing a
#    second hat.
# ---------------------------------------------------------------------------
AGENT_TIER_REVIEWER='fable'

# ---------------------------------------------------------------------------
# OPTIONAL SECOND AXIS: TASK DOMAIN
# ---------------------------------------------------------------------------
# The resolver takes an optional second argument, the task DOMAIN
# (`sh scripts/agents.kit.sh <tier> <domain>`): it prefers
# AGENT_TIER_<TIER>_<DOMAIN> and falls back to the plain tier variable above
# when that is unset or empty. The tier is a cost/benefit shape and says
# nothing about what the work is made OF, which is what the domain adds.
#
# Unlike the four tier names, the domain vocabulary is OPEN and local: these
# tokens are THIS repo's, chosen because they change the answer, and an
# unmapped one falls back to the tier silently and correctly.
#
# scripts/agents.config.sh — the file consumers get — still assigns nothing
# here, on either axis. A domain mapping is still a model identifier, and the
# kit names one only to itself.

# The kit's product is mostly PROSE: the root manual and the AGENTS.md
# template, the constitution articles, every SKILL.md, UPDATING.md. Writing it
# is `implementer` work by tier — one ticket, test-first, seams to find — but
# it is not code, and the strongest prose model available is a different answer
# from the strongest coding one.
AGENT_TIER_IMPLEMENTER_CONTENT='fable'

# THERE IS DELIBERATELY NO AGENT_TIER_IMPLEMENTER_CODE. The plain tier above
# already resolves code work to 'opus'; naming the domain to repeat that value
# would record a non-decision as a decision, and would then have to be kept in
# sync with the tier it duplicates. The fallback IS the mapping for code.
#
# Same reasoning for the other three tiers: planner and reviewer are already on
# the strongest model available for either medium, and mechanical work is
# oracle-checked whatever it is made of. Add a domain here when — and only
# when — the medium would change the answer.
