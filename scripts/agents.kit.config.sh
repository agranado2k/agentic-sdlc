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
# Claude Haiku 4.5 is `claude-haiku-4-5-20251001`.
#
# A Claude Code older than the model REFUSES it, and not only locally: the
# warning is "isn't described by this version's model catalog", and the call
# behind it fails with `API Error: 400 … Claude Code 2.1.259 does not support
# this model; version 2.1.280 or newer is required. Run 'claude update'`. So
# the id is right and the CLI is behind — but an operator on an older CLI
# gets a failed spawn, not a fallback. It bites only where the full id
# reaches a CLI: the cross-harness path, and `--model`. An in-session spawn
# takes the family word `--alias` prints, so it is unaffected either way.
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
# pair is what scripts/agent-dispatch.sh runs when a tier names it. The tests
# agent below crosses over, and the reviewer did until #423 and will again: the
# cross-vendor review the kit calls its highest-leverage property is reachable
# locally here, not only in CI, once that CLI authenticates from this host.
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
AGENT_TIER_MECHANICAL='claude-opus-5'   # 2026-10-01: moved off the cheapest model — three of three mechanical tickets that day (#352, #354, #388) reviewed themselves or shipped untested rules and needed a rescue session (retro 20261001T150216Z); the operator chose Opus 5 for the tier, Opus 5.5 stays the implementer

# ---------------------------------------------------------------------------
# 4. REVIEWER — strongest reasoning, in fresh context, and DIFFERENT from
#    whatever implemented the diff. A cheap verdict is a rubber stamp, and a
#    reviewer sharing the implementer's model is one editorial pass wearing a
#    second hat.
# ---------------------------------------------------------------------------
#    The kit's answer to that is a DIFFERENT VENDOR, not just a different
#    model: a reviewer that shares the author's training shares the author's
#    blind spots. It is suspended, not abandoned. On 2026-10-01 every reviewer
#    crossing this host attempted returned 401 — 4 of 4 in the third retro
#    window — so a reviewer mapped to the other vendor answered nothing and the
#    review fell to whatever the session happened to run on. Until that CLI
#    authenticates the reviewer is local:
#
#      plain `reviewer`, no session named
#        -> claude-fable-5-1, never the implementer's claude-opus-5-5
#      `reviewer self-implemented`, any session this policy maps
#        -> claude-sonnet-5-5, the model no session tier runs on
#
#    tests/agents-tiers.test.sh pins both. The plain form still has no second
#    answer: a claude-fable-5-1 session asking plain `reviewer` is refused its
#    own model and gets NOTHING, with a warning — a session that wrote the
#    diff asks `reviewer self-implemented`. The cross-vendor ids
#    (codex:gpt-5.6-sol for the reviewer, codex:gpt-6-astra for
#    self-implemented) come back when that CLI authenticates — ask the
#    operator again on 2026-10-08.
AGENT_TIER_REVIEWER='claude-fable-5-1'
#
#    The case the plain lookup cannot see: the session ITSELF implemented the
#    diff — every /implement session that writes its own code or prose. It is
#    resolved through the domain axis below, as `sh scripts/agents.kit.sh
#    reviewer self-implemented` — a domain that names a situation rather than
#    a medium, which the open vocabulary allows and the glossary's "Task
#    domain" entry records.
#
#    2026-10-05 (#546, ADR-0007 amended): moved off claude-opus-5-5 to a THIRD
#    model. The session models are two — claude-opus-5-5 (implementer) and
#    claude-fable-5-1 (planner, content) — and one fixed answer can differ
#    from both only if it is neither. While it named claude-opus-5-5 it was
#    right only for a fable session: every implementer session that day got
#    its own model back, was saved by ADR-0007's refusal ONLY when it named
#    itself by this file's pinned id (`opus`, the spawn word, matches
#    nothing), and fell back to claude-fable-5-1 — which was out of usage
#    credits all day, so every session overrode the reviewer by hand with
#    sonnet. This value is that override, recorded: right for every session
#    this file maps, whether or not it says what it runs on. The cost is
#    strength — a mid-tier read where a fable session used to get opus —
#    chosen over a stronger review that does not run. The refusal
#    (scripts/agents.lib.sh since 0.22.0) stays as the net, now for a
#    session on this model itself. Verified 2026-10-05: claude-sonnet-5-5 is
#    the model the Claude Code harness's `sonnet` spawn word ran that day,
#    and `--alias` prints `sonnet` for it.
#
#    An ORDERED fallback — a next answer when this one is refused or
#    unreachable, never the session's own — is the shared resolver's to
#    carry, not this file's: decided in ADR-0013, built by its follow-up.
AGENT_TIER_REVIEWER_SELF_IMPLEMENTED='claude-sonnet-5-5'

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
# the other vendor, for the reason the reviewer did until #423 and will again.
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

# THERE IS DELIBERATELY NO AGENT_TIER_MECHANICAL_JUDGE EITHER — and unlike
# `code` above, that is a DECLINE, not a fallback. `judge` is the one domain
# the kit names itself (ADR-0010): the middle rung of a judgment's cost
# ladder, between a deterministic script and the session's model — a typed
# judge specified by its contract, state and typed questions in, typed
# answers with per-option probabilities out, in two shapes: decide, among
# supplied options (the chain's triage questions), and rank-or-verify, over
# supplied candidates. Every triage question the chain asks could run on one.
#
# The kit names no model for it all the same — to a consumer by rule, and to
# itself here by decision: the field is weeks old, no price on it is proven,
# and a typed judge is the fastest-rotting identifier there is; this file is
# exactly where such a name would rot. Unmapped, `mechanical judge` resolves
# to the mechanical tier above in silence, which is what a consumer who has
# not decided gets too — and this paragraph is what turns the resolver's
# silence into a recorded decision rather than an omission. Map it here the
# day a judge earns it, say which SHAPE it answers, and never hand a decider
# a verification: the record says why, with the measurement.
