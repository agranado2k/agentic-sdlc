# ADR-0022: The Codex session's reviewer follows the Sonnet family too

- **Status**: Accepted
- **Date**: 2026-10-10
- **Deciders**: the implementer session for #691, on the operator's direction of 2026-10-09 ("always use the Sonnet family to review") and the standing delegation of rulings
- **Supersedes / amends**: supersedes ADR-0020 clause 5's third non-goal (the Codex session's policy, `scripts/agents.kit.codex.config.sh`, "is not touched by this record"); ADR-0020 clauses 1 to 4 and its bridge are unchanged
- **Superseded by**: —

## Context and problem statement

ADR-0020 moved the Claude Code session's reviewer to the Sonnet family after
the pinned Fable reviewer refused every spawn on 2026-10-09 (14 of 14, out of
usage credits). Its clause 5 left the Codex session's policy out, because that
agent harness was logged out (#669, finding L-6). That policy's reviewer
stayed pinned to `claude-code:claude-fable-5-1`, with no fallback. A Codex
session asking for a review on such a day had no next answer.

Widening a decision's scope is not a narrowing or a clarification, so it is
recorded here rather than as an in-place amendment of ADR-0020 (the record
conventions in `docs/adr/INDEX.md`).

## Decision drivers

- The operator's ruling names the review, not the session it is asked from.
- ADR-0013: a reviewer has an ordered fallback, never nothing while a candidate remains.
- The reviewer in this policy always crosses to another agent harness, so every candidate has to carry its agent harness.
- No change to the shared layer and none to the kit wrapper's bridge.

## Considered options

1. **Follow ADR-0020: `claude-code:sonnet`, fallback `claude-code:opus claude-code:claude-fable-5-1`, `self-implemented` unmapped** *(chosen)*.
2. **Keep the pinned Fable reviewer, add a fallback.** Rejected. It goes against the ruling, and the pinned model is the one that ran out of credits.
3. **Also widen the bridge to fold crossing values**, so a session named `claude-sonnet-5-5` is refused its family here. Rejected. PR #553 M-1 kept crossing values out of the bridge on purpose, and no Codex session runs on a Claude model, so the case has no caller.

## Decision outcome

Chosen: **option 1.**

1. In `scripts/agents.kit.codex.config.sh`, `AGENT_TIER_REVIEWER='claude-code:sonnet'` and `AGENT_TIER_REVIEWER_FALLBACK='claude-code:opus claude-code:claude-fable-5-1'`. Every candidate carries its agent harness, so a fallen-back review still crosses (ADR-0013). `AGENT_TIER_REVIEWER_SELF_IMPLEMENTED` is unset, as in ADR-0020 clause 1.
2. **The bare family word is workable on this side.** The crossing runs `claude -p --model <model>`, and that CLI's `--model` takes "an alias for the latest model (e.g. 'fable', 'opus', or 'sonnet')" (the policy file records the check). `scripts/agent-dispatch.sh --dry-run` shows `claude -p --model sonnet`, and `opus` for a session named `sonnet`. The trace accepts the recorded model, because `--ids` lists `sonnet` and `opus` for this policy.
3. **The answers**, through `AGENT_HARNESS_SELF=codex sh scripts/agents.kit.sh`: a Codex session (`gpt-*`), an Opus session (`opus` or `claude-opus-5-5`) or none named gets `sonnet` on `claude-code` for `reviewer` and `reviewer self-implemented`. A Sonnet session named `sonnet` gets `opus`. An Opus session whose Sonnet is unreachable gets `claude-fable-5-1`.
4. **A session is named in the policy's own words** (`sonnet`, `opus`). ADR-0020 clause 2's bridge never folds a value that crosses to another agent harness, and every reviewer candidate here crosses, so a session named `claude-sonnet-5-5` is compared exactly and handed `sonnet`.

## Consequences

- **Good**: a Codex session's review has the same ordered fallback as a Claude Code session's, and follows new Sonnet models with no re-pin.
- **Bad / trade-off**: the reviewer floats here as well. A model change reaches the Codex review with no diff, as ADR-0020 already accepted for the other policy.
- **Honest limitation**: clause 4. Its only caller would be a Codex session running a Claude model, which cannot happen.
- **Not verified live**: Codex is logged out (2026-10-08), so no review was dispatched from a Codex session under this mapping. The dispatch dry run and `tests/agents-tiers.test.sh` hold it, and the first live Codex review is its proof.

## More information

- Implemented in: the PR for #691 (`feat/691-codex-reviewer-policy`), held by `tests/agents-tiers.test.sh`.
- Related: ADR-0007 (the refusal), ADR-0013 (the walk), ADR-0018 (family-following tiers), ADR-0020 (the Claude Code session's reviewer).
