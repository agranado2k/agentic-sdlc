#!/bin/sh
# agents.kit.codex.config.sh — the KIT'S OWN tier -> model mapping, for a
# session running in the CODEX agent harness. Not shipped.
#
# scripts/agents.kit.config.sh beside this file is the same document for a
# Claude Code session, and its header carries the reasoning both share: why
# the kit maps its own tiers at all, why neither file reaches a consumer
# (bootstrap.sh's KIT_ONLY deletes both), and what the four tier words mean.
# Read that one first; this file records only what differs.
#
# WHAT DIFFERS, AND WHY THERE ARE TWO FILES. A tier's value answers "which
# model, on which agent harness" — and "which agent harness" is relative to
# the session asking. The planner is a local spawn from a Codex session and a
# crossing from a Claude Code one; the reviewer is the reverse. One file with
# both answers could not say which, so there are two, and
# scripts/agents.kit.sh picks by $AGENT_HARNESS_SELF. A session that does not
# say falls back to the Claude Code policy, which is how this repo is usually
# driven.
#
# THE SHAPE IS DELIBERATELY SYMMETRIC with the other file: each policy runs
# the work it is good at locally, and crosses to the other vendor for the two
# jobs where sharing the author's blind spots is the failure — reviewing a
# diff, and writing the test that is supposed to constrain it.
#
# ---------------------------------------------------------------------------
# THESE IDS ROT. The OpenAI ids below are this harness's own and rot on its
# schedule; the `claude-code:` values rot on Anthropic's.
#
# The OpenAI half was checked on 2026-09-22 against the roster the CLI itself
# fetched for this account (`~/.codex/models_cache.json`, fetched 2026-09-21)
# — the list that `--model` will actually accept here, which is a stronger
# claim than a docs page makes. It held seven: gpt-6-astra ("most capable,
# for complex demanding work"), gpt-5.6-sol ("reliable agentic workhorse"),
# gpt-5.6-terra ("balanced agentic coding"), gpt-5.6-luna and gpt-reserve
# (both "fast and affordable agentic coding"), gpt-5.5, and codex-auto-review.
# Re-check by reading that file, or `codex exec --help` for the flag. Both halves are
# PINNED — a floating alias would make a model change with no diff and no
# decision, which is the opposite of what a recorded policy is for. Every
# value here crosses to the other agent harness and so reaches a CLI, which
# takes the full id; the alias question the other policy documents does not
# arise on this side.
# ---------------------------------------------------------------------------

# The other agent harness, declared so `<harness>:<model>` is a crossing
# rather than a malformed id (ADR-0005), with what scripts/agent-dispatch.sh
# runs to reach it.
# VERIFIED against the installed CLI on 2026-09-22, not guessed: `-p/--print`
# is the non-interactive form, `--model <model>` takes "an alias for the
# latest model (e.g. 'fable', 'opus', or 'sonnet') or a model's full name
# (e.g. 'claude-fable-5')" — so the PINNED ids below are exactly what it
# wants, and the alias the other policy documents is only needed for the
# in-session spawn parameter, which this path never touches. Re-check with
# `claude --help` when that CLI moves.
AGENT_HARNESSES='claude-code'
AGENT_HARNESS_CLAUDE_CODE_CMD='claude -p {model_flag} < {prompt_file}'
AGENT_HARNESS_CLAUDE_CODE_MODEL_FLAG='--model {model}'

# ---------------------------------------------------------------------------
# 1. PLANNER — strongest reasoning available, and local here.
# ---------------------------------------------------------------------------
AGENT_TIER_PLANNER='gpt-6-astra'

# ---------------------------------------------------------------------------
# 2. IMPLEMENTER — the builder; best cost/capability for real coding work in
#    this session, so also local.
# ---------------------------------------------------------------------------
AGENT_TIER_IMPLEMENTER='gpt-5.6-sol'

# ---------------------------------------------------------------------------
# 3. MECHANICAL — cheapest capable model; the suite is the oracle, and
#    capability past "can follow the pattern" buys nothing. Local: a codemod
#    is not worth the latency of a crossing.
#
#    gpt-5.6-luna over gpt-reserve, which the roster describes identically
#    ("fast and affordable agentic coding"): luna is the one this account has
#    actually run, so it is the choice with evidence behind it rather than a
#    coin toss between two descriptions.
# ---------------------------------------------------------------------------
AGENT_TIER_MECHANICAL='gpt-5.6-luna'

# ---------------------------------------------------------------------------
# 4. REVIEWER — a DIFFERENT VENDOR, not merely a different model, for the
#    reason the other policy states in full: a reviewer that shares the
#    author's training shares the author's blind spots.
# ---------------------------------------------------------------------------
AGENT_TIER_REVIEWER='claude-code:claude-fable-5-1'
#    Vestigial while the reviewer is cross-vendor — a Codex session cannot be
#    running Fable — but mapped to a SECOND model anyway, so the rule still
#    has an answer if the reviewer is ever localised. ADR-0007's refusal in
#    scripts/agents.kit.sh is the net under both.
AGENT_TIER_REVIEWER_SELF_IMPLEMENTED='claude-code:claude-opus-5'

# ---------------------------------------------------------------------------
# OPTIONAL SECOND AXIS: TASK DOMAIN — same rules as the other policy. The
# vocabulary is open and local; an unmapped domain falls back to its tier
# silently and correctly.
# ---------------------------------------------------------------------------

# The tester. A domain rather than a fifth tier because the tier vocabulary is
# closed. It crosses for the same reason the reviewer does: the model that
# wrote the code is the worst reader of whether its test constrains anything.
AGENT_TIER_IMPLEMENTER_TESTS='claude-code:claude-opus-5'

# No AGENT_TIER_IMPLEMENTER_CONTENT here. The kit's prose is written from the
# Claude Code session, where that domain is mapped; a Codex session that ends
# up writing an article falls back to its implementer, which is the honest
# answer rather than a value copied across to look symmetric.
#
# No AGENT_TIER_IMPLEMENTER_CODE, for the reason the other file gives: the
# plain tier already resolves code work, and repeating the value under a
# domain name records a non-decision.
