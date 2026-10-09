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
# THREE TIERS FOLLOW A FAMILY INSTEAD (the operator, 2026-10-08): the planner
# is `opus` and the mechanical tier `sonnet` (ADR-0018), and the reviewer
# `sonnet` too, with `opus` first on its fallback (ADR-0020) — the bare family
# word, "the newest in that family", not a pinned id. The rule above holds for
# every other tier. The trade: no diff and no decision when Opus or Sonnet
# moves, in exchange for the tiers where the operator wants the current model
# always being on it. The family word reaches both consumption paths unchanged: the
# in-session spawn parameter takes it (`--alias` folds it to itself), and
# `claude --model` documents "an alias for the latest model (e.g. 'fable',
# 'opus', or 'sonnet')", verified against `claude --help` on 2026-10-08. A
# mapped family word is also the policy's own spelling for a session on that
# tier: scripts/agents.kit.sh treats it and every pinned id that folds to it
# as one family, so a `sonnet` session — or a claude-sonnet-* one — is never
# handed the `sonnet` reviewer, and an Opus session never the `opus` fallback.
#
# The cost of pinning is that the two consumption paths take different
# spellings for a PINNED tier. `claude --model` (what scripts/agent-dispatch.sh
# runs when a tier crosses agent harnesses) is given the full id — it takes
# the family alias too, which is why the family-following tiers above need
# no bridge on that path. The IN-SESSION spawn parameter
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
# docs/capability-tiers.md, the kit-own article the root AGENTS.md points at):
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
#    2026-10-08 (ADR-0018): the newest Opus, by family word — it was the
#    pinned claude-fable-5-1.
# ---------------------------------------------------------------------------
AGENT_TIER_PLANNER='opus'

# ---------------------------------------------------------------------------
# 2. IMPLEMENTER — best cost/capability for real coding work. This is where
#    most of the kit's own sessions land.
# ---------------------------------------------------------------------------
AGENT_TIER_IMPLEMENTER='claude-opus-5-5'   # the builder

# ---------------------------------------------------------------------------
# 3. MECHANICAL — cheapest capable model. The suite is the oracle; capability
#    past "can follow the pattern" buys nothing here.
# ---------------------------------------------------------------------------
AGENT_TIER_MECHANICAL='sonnet'   # 2026-10-08 (ADR-0018): the newest Sonnet, by family word. It was claude-opus-5 from 2026-10-01, when three of three mechanical tickets that day (#352, #354, #388) on the cheapest model reviewed themselves or shipped untested rules (retro 20261001T150216Z)
#
# The cascade's cheap rung (#586, PRD #580; operator decision 2026-10-06,
# re-decided by ADR-0018). The rung is the mechanical tier's own model, the
# same word: the skill dispatcher, seeing the cascade model equal the tier's
# mapping, escalates a red rung to the IMPLEMENTER tier's model rather than
# drawing Sonnet twice. Bare, as written, it names no agent harness, so the
# dispatcher refuses the cascade and says so: the rung runs only once it
# names one the dispatcher can cross to.
AGENT_CASCADE_MECHANICAL='sonnet'

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
#    authenticates the reviewer is local.
#
#    2026-10-08 (ADR-0020, the operator: "always use the Sonnet family to
#    review"): THE REVIEWER FOLLOWS THE SONNET FAMILY, the family the
#    mechanical tier follows (ADR-0018), by the bare word. It was the pinned
#    claude-fable-5-1, and its `self-implemented` domain the pinned
#    claude-sonnet-5-5: over the retro window of 2026-10-08 the reviewer tier
#    cost 2.8 times the implementer tier, the review skill 56% of all spend.
#
#      plain `reviewer`, an Opus or a Fable session, or none named
#        -> sonnet, never the implementer's claude-opus-5-5
#      `reviewer self-implemented`, the same sessions
#        -> sonnet: the domain is deliberately unmapped below, so it falls
#           back to the plain tier — one decision, not two copies of it
#      either form, a session on the Sonnet family — `sonnet` (the mechanical
#      tier's word) or any pinned Sonnet id
#        -> the fallback's first entry, `opus`: refused its own family by the
#           kit wrapper's family bridge (ADR-0018 clause 4, widened by
#           ADR-0020), never handed nothing
#
#    The trade: a session that names nothing gets `sonnet` whatever it runs
#    on, so a mechanical session that does not say what it runs on is handed
#    its own family. Say what you run on — AGENT_SESSION_MODEL, the root
#    manual's "Before you spawn a reviewer" — and the bridge refuses it.
#
#    tests/agents-tiers.test.sh pins all of the above. The cross-vendor ids
#    (codex:gpt-5.6-sol for the reviewer, codex:gpt-6-astra for
#    self-implemented) come back when that CLI authenticates.
AGENT_TIER_REVIEWER='sonnet'
#
#    THE `self-implemented` DOMAIN IS UNMAPPED, deliberately. It names the
#    situation the plain lookup cannot see — the session itself implemented
#    the diff (`sh scripts/agents.kit.sh reviewer self-implemented`; the
#    glossary's "Task domain" entry) — and from 2026-10-05 (#546, ADR-0007
#    amended) to ADR-0020 it was the pinned claude-sonnet-5-5, a model no
#    pinned session tier ran on. With the reviewer itself on the Sonnet
#    family its answer is the plain tier's, so mapping it would repeat that
#    value as a second decision to keep in sync (the same reason there is no
#    AGENT_TIER_IMPLEMENTER_CODE, below). The domain still means something:
#    asked with it, the resolver walks the same candidates, and the session's
#    own family is refused by AGENT_SESSION_MODEL, not by a third model.
#
#    THE ORDERED FALLBACK (ADR-0013, #548) — the next answers when the
#    reviewer is refused (the session's own family) or named unreachable by
#    the caller in AGENT_UNREACHABLE_MODELS (a spawn that failed on its first
#    call: a rate limit, a logged-out CLI). The walk is the domain answer,
#    the plain reviewer, then this list in order; a spent list prints
#    nothing, never the session's own model.
#
#      opus               the newest Opus, by family word (ADR-0020): where a
#                         Sonnet session goes, and a Fable session whose
#                         Sonnet is unreachable. An Opus session — the
#                         implementer's claude-opus-5-5 or the planner's
#                         `opus` — is refused it by the bridge.
#      claude-fable-5-1   pinned: where an Opus session goes once Sonnet is
#                         unreachable. A Fable session (the content domain)
#                         is refused it exactly.
#
#    The cross-vendor reviewer (codex:gpt-5.6-sol) is deliberately NOT on the
#    list yet: an entry that crosses agent harnesses has no in-session spawn
#    word — `--alias` prints nothing for it, and an in-session spawn given
#    nothing inherits the session, the self-review the walk exists to
#    prevent. It joins when that CLI authenticates and the caller's dispatch
#    path is the one that reads it.
#
#    tests/agents-tiers.test.sh pins the list against the rule, not the ids:
#    walked to its end through the kit wrapper for every session tier — by
#    its value, by a mapped spawn word, and by a pinned id of the reviewer's
#    family — no answer is of the session's own family.
AGENT_TIER_REVIEWER_FALLBACK='opus claude-fable-5-1'

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

# The reviewer's `self-implemented` domain is a decline, recorded with its
# reasoning in the reviewer block above (ADR-0020).
#
# THERE IS DELIBERATELY NO AGENT_TIER_IMPLEMENTER_CODE. The plain tier above
# already resolves code work to 'opus'; naming the domain to repeat that value
# would record a non-decision as a decision, and would then have to be kept in
# sync with the tier it duplicates. The fallback IS the mapping for code.
#
# Same reasoning for the other three tiers: the planner is already on the
# strongest model available for either medium, the reviewer follows one family
# for every medium by the operator's ruling (ADR-0020), and mechanical work is
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
