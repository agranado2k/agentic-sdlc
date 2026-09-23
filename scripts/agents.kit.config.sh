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
# THIS FILE IS THE CLAUDE CODE SESSION'S POLICY. The operator drives this repo
# from two agent harnesses, and each is its own document: a model that is
# local here is a cross-harness dispatch there, and the reverse. The Codex
# session's policy is scripts/agents.kit.codex.config.sh beside this file,
# and scripts/agents.kit.sh picks between them by $AGENT_HARNESS_SELF, so one
# command means "this session's policy" wherever it is typed.
#
# THE SUITE'S BUDGET IS DERIVED UNDER THIS FILE TOO. tests/lib.sh runs every
# suite inside the budget a dispatched worker gets (ADR-0006, #209), and
# reads the six AGENT_BUDGET_* variables from here — never from the
# environment's $AGENTS_CONFIG. None is set: the dispatcher's defaults are
# the kit's answer for its own suite, re-measured by #209 with room to spare.
# Set one here, in the shape scripts/agents.config.sh documents, to tighten
# the suite's ceiling for every developer at once.
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
#
# Checked 2026-09-23 against platform.claude.com/docs/en/docs/about-claude/models/overview:
# Claude Opus 5.5 is `claude-opus-5-5`, Claude Fable 5.1 is `claude-fable-5-1`,
# Claude Haiku 4.5 is `claude-haiku-4-5-20251001`. A LOCAL Claude Code whose
# model catalog predates a release rejects the newer id with "isn't described
# by this version's model catalog; update Claude Code" — that is the CLI being
# stale, not the id being wrong, and it only bites the cross-harness path,
# since an in-session spawn takes the family word `--alias` prints.
#
# The local values below are PINNED IDS, not the `fable`/`opus` aliases. An
# alias silently follows the roster: the day Fable 6 ships, every `fable` here
# becomes a different model with no diff and no decision, which is the opposite
# of what a recorded policy is for. Pinning means the move is a commit someone
# made on purpose.
#
# The cost of pinning is that the two consumption paths take different
# spellings. `claude --model` (what scripts/agent-dispatch.sh runs when a tier
# crosses agent harnesses) takes the full id. The IN-SESSION spawn parameter
# — the Agent/Task tool, adapters/claude-code/README.md — takes only the
# family word. `sh scripts/agents.kit.sh --alias <tier> [domain]` is the
# bridge: it resolves the tier and prints the spawn word for it, so a session
# spawning a subagent asks for that and a dispatch uses the id verbatim.
#
# Values that cross to another agent harness are that harness's own ids and
# rot on its schedule instead.
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
# THE OTHER AGENT HARNESS. Declaring it is what makes `<harness>:<model>` a
# crossing rather than a malformed model id (ADR-0005), and the CMD/MODEL_FLAG
# pair is what scripts/agent-dispatch.sh runs when a tier names it. Both the
# reviewer and the tests agent below cross over, which is the point: the
# cross-vendor review the kit calls its highest-leverage property is reachable
# locally here, not only in CI.
# ---------------------------------------------------------------------------
# VERIFIED against the installed CLI on 2026-09-22, not guessed: `codex exec`
# is the non-interactive form, `-m, --model <MODEL>` is its model flag, and
# its own help says the prompt "is read from stdin" when no prompt argument
# is given — which is what `< {prompt_file}` supplies. Re-check with
# `codex exec --help` when that CLI moves.
AGENT_HARNESSES='codex'
AGENT_HARNESS_CODEX_CMD='codex exec {model_flag} < {prompt_file}'
AGENT_HARNESS_CODEX_MODEL_FLAG='--model {model}'

# ---------------------------------------------------------------------------
# 1. PLANNER — strongest reasoning available. A wrong decomposition is paid
#    for by every downstream ticket, so this is the one tier where "most
#    expensive" is the cost-saving choice.
# ---------------------------------------------------------------------------
AGENT_TIER_PLANNER='claude-fable-5-1'

# ---------------------------------------------------------------------------
# 2. IMPLEMENTER — best cost/capability for real coding work. This is where
#    most of the kit's own sessions land.
# ---------------------------------------------------------------------------
AGENT_TIER_IMPLEMENTER='claude-opus-5-5'   # the builder

# ---------------------------------------------------------------------------
# 3. MECHANICAL — cheapest capable model. The suite is the oracle; capability
#    past "can follow the pattern" buys nothing here.
# ---------------------------------------------------------------------------
AGENT_TIER_MECHANICAL='claude-haiku-4-5-20251001'

# ---------------------------------------------------------------------------
# 4. REVIEWER — strongest reasoning, in fresh context, and DIFFERENT from
#    whatever implemented the diff. A cheap verdict is a rubber stamp, and a
#    reviewer sharing the implementer's model is one editorial pass wearing a
#    second hat.
# ---------------------------------------------------------------------------
#    Here that is taken literally: the reviewer is a DIFFERENT VENDOR, not
#    just a different model. A reviewer that shares the author's training
#    shares the author's blind spots, and the kit's own docs call the
#    cross-provider leg the highest-leverage wiring available. The dispatcher
#    makes it reachable from a local session, so it no longer has to wait for
#    CI to hold the secrets.
AGENT_TIER_REVIEWER='codex:gpt-5.6-sol'
#
#    The case the plain lookup cannot see: the session ITSELF implemented, on
#    the model this tier maps to — a planner-tier session writing a ticket's
#    diff is exactly that, and this wave met it on every PR. Then the
#    reviewer above IS the implementer, and the rule needs a second answer.
#    It is resolved through the domain axis below, as
#    `sh scripts/agents.kit.sh reviewer self-implemented` — a domain that
#    names a situation rather than a medium, which the open vocabulary
#    allows and the glossary's "Task domain" entry records — and
#    tests/agents-tiers.test.sh holds it to differing from the reviewer.
#    With the reviewer on another vendor this is close to vestigial — a
#    Claude session cannot be running gpt-5.6-sol — but it stays mapped, and
#    to a SECOND model rather than the same one: if the reviewer is ever
#    localised again, the rule still has an answer, and ADR-0007's refusal in
#    scripts/agents.kit.sh is the net under both.
AGENT_TIER_REVIEWER_SELF_IMPLEMENTED='codex:gpt-6-astra'

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
AGENT_TIER_IMPLEMENTER_CONTENT='claude-fable-5-1'

# THE TESTS DOMAIN — the operator's fourth agent, the "tester". It is a domain
# and not a fifth tier because the tier vocabulary is CLOSED (an unknown tier
# is exit 2, and widening it is a manual change, a resolver change and a
# release). Writing the failing test is implementer work by tier — one
# behaviour, test-first, through a seam — but the medium changes the answer:
# a test is a specification, and the model that wrote the code is the worst
# reader of whether its test actually constrains anything. So it crosses to
# the other vendor, for the same reason the reviewer does.
AGENT_TIER_IMPLEMENTER_TESTS='codex:gpt-5.6-sol'

# The third domain this repo maps, AGENT_TIER_REVIEWER_SELF_IMPLEMENTED,
# sits in the reviewer block above with its reasoning.
#
# THERE IS DELIBERATELY NO AGENT_TIER_IMPLEMENTER_CODE. The plain tier above
# already resolves code work to 'opus'; naming the domain to repeat that value
# would record a non-decision as a decision, and would then have to be kept in
# sync with the tier it duplicates. The fallback IS the mapping for code.
#
# Same reasoning for the other three tiers: planner and reviewer are already on
# the strongest model available for either medium, and mechanical work is
# oracle-checked whatever it is made of. Add a domain here when — and only
# when — the medium would change the answer.
