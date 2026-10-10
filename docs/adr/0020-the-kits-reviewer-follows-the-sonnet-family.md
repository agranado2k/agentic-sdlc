# ADR-0020: The kit's reviewer tier follows the Sonnet family

- **Status**: Accepted
- **Date**: 2026-10-09
- **Deciders**: the operator (Arthur Granado), ruling of 2026-10-08
- **Supersedes / amends**: supersedes ADR-0018 clause 1 for the reviewer ("a reviewer value is never a family word") and widens its clause 4 bridge; supersedes the 2026-10-05 amendment of ADR-0007 (#546), under which the `self-implemented` domain named a third, pinned model no session tier ran on
- **Superseded by**: — (clause 5's third non-goal, the Codex session's policy, superseded by ADR-0022 on 2026-10-10: that policy's reviewer follows the Sonnet family too)

## Context and problem statement

The retro of 2026-10-08 (`retro-20261008T160141Z`) measured the reviewer tier at
2.8 times the implementer tier's spend over its window, $114.96 against
$41.46. The review skill alone was 56% of all spend. Every review lens and the
behavior reviewer resolved to the pinned top model (`claude-fable-5-1`), while
only the `self-implemented` domain landed on the Sonnet family, as the pinned
`claude-sonnet-5-5`.

The operator ruled on 2026-10-08: "always use the Sonnet family to review". That
is a family-following tier, the mechanism ADR-0018 introduced for the planner
and the mechanical tier. But ADR-0018 clause 1 says a reviewer value is never a
family word, and its clause 4 bridge assumed that: it let a session named by a
mapped family word refuse the pinned ids of that family, and it never had to
refuse a candidate that was itself a family word.

ADR-0007 still holds: a review never runs on the session's own model. With the
reviewer on `sonnet`, a session on the Sonnet family has to be handed a
different family, whether it names itself by the word or by a pinned Sonnet
id.

## Decision drivers

- The operator's ruling: the reviewer runs the newest Sonnet, plain and self-implemented.
- ADR-0007: a session is never handed its own model as reviewer, and ADR-0013: the next answer is an ordered fallback, never nothing while a candidate remains.
- No shared-layer change. The resolver compares exactly by design, so the family logic stays in the kit wrapper, as ADR-0018 clause 4 put it there.
- One decision in one place. A domain mapped to the plain tier's value is a second copy to keep in sync.

## Considered options

1. **Map the reviewer to `sonnet`, leave `self-implemented` unmapped, and make the fallback `opus claude-fable-5-1`; widen the wrapper's bridge to whole families** *(chosen)*.
2. **Pin the reviewer to the current Sonnet id.** Rejected. The ruling is "the Sonnet family", and ADR-0018 already records the trade of following a family for the tiers where the operator wants the current model.
3. **Keep a separate `self-implemented` mapping.** Rejected. It would name the same word as the plain tier, and the refusal of a Sonnet session's own family is the bridge's job, not a third model's.
4. **Fallback `claude-opus-5-5` (pinned) instead of `opus`.** Rejected. The reviewer follows families now, and the bridge has to treat `opus` and `claude-opus-5-5` as one family anyway, because the planner maps `opus`.

## Decision outcome

Chosen: **option 1.**

1. In `scripts/agents.kit.config.sh`, `AGENT_TIER_REVIEWER='sonnet'` and `AGENT_TIER_REVIEWER_FALLBACK='opus claude-fable-5-1'`. `AGENT_TIER_REVIEWER_SELF_IMPLEMENTED` is unset, so the domain falls back to the plain tier. The implementer, the `content` and `tests` domains stay pinned (ADR-0018 clause 1 holds for them).
2. **The kit wrapper's bridge reads a name's whole family**, for the reviewer tier only. A name whose family word the policy maps (the word itself, or any pinned id that folds to it, whether the policy maps that id or not) stands for the word and every mapped pinned id that folds to it. An unmapped word named unreachable stands for the pinned ids that fold to it (ADR-0013 clause 2). An unmapped word named as the session stays exact (ADR-0007). Of that family, only the reviewer walk's own candidates are passed on, so no spurious "matches no reviewer candidate" warning is drawn.
3. **The answers**, through `sh scripts/agents.kit.sh`: an Opus session (`opus` or `claude-opus-5-5`), a Fable session or none named gets `sonnet` for `reviewer` and `reviewer self-implemented`. A Sonnet session (`sonnet` or any `claude-sonnet-*` id) gets `opus`. An Opus session whose Sonnet is unreachable gets `claude-fable-5-1`.
4. **`--ids` is unchanged in shape**: `sonnet` and `opus` were already listed (ADR-0018 clause 3), so a reviewer spawn records the word the resolver printed, and the trace accepts it.
5. **Explicit non-goal**: consumers. The shipped `scripts/agents.config.sh` stays empty, `scripts/agents.lib.sh` does not change, and the Codex session's policy (`scripts/agents.kit.codex.config.sh`) is not touched by this record.

## Consequences

- **Good**: the review fan-out (six lenses and the behavior reviewer) runs on Sonnet, which is what the ruling was for. It also follows the family, so a new Sonnet reaches review with no re-pin.
- **Good**: `/implement`'s reviewer for an Opus implementer no longer depends on the self-implemented third model. Plain and self-implemented are the same answer.
- **Bad / trade-off**: a session that names nothing gets `sonnet` whatever it runs on. A mechanical session that does not say what it runs on is reviewed by its own family. The root manual's "say what you run on" is the guard, and the bridge refuses the family once the session does.
- **Bad / trade-off**: a weaker reviewer than Fable on the plain path. The operator chose the cost; `/retro` is where a drop in review signal will show.
- **Honest limitation**: as with ADR-0018, the bridge lives only in the kit wrapper. A session calling `scripts/agents.lib.sh` directly, against hard rule 10, gets the exact comparison: a `claude-sonnet-*` session is handed `sonnet`.

## More information

- Implemented in: the PR for #660 (`feat/660-reviewer-family`); held by `tests/agents-tiers.test.sh`.
- Building it found the family walk in that suite read `$KIT_WRAPPER` before the suite set it, so the walk ran empty and passed vacuously; the suite now sets it first and counts the answers it walked.
- Related: ADR-0007 (the refusal), ADR-0013 (the walk), ADR-0018 (family-following tiers and the bridge).
