# ADR-0038: Every unspecified item on the confirm-list carries a scope, and a missing one is outward

- **Status**: Accepted
- **Date**: 2026-10-25
- **Deciders**: the planner session for #873, under the operator's delegation of rulings; the line itself was drawn in the software factory's D-02 session (PRD-07, question 6); the merge of its pull request is the operator's yes
- **Supersedes / amends**: —
- **Superseded by**: —

## Context and problem statement

`/review-pr`'s Axis 2 lists every behavior change in a diff. A change no
spec asked for is a ⚠️ UNSPECIFIED item, and every one of them goes to the
operator (shared invariant §5). Most are small: a renamed variable, a test
written in a new shape, an internal error reworded. A few really matter: an
exit code, a flag, an output format, a rule another agent obeys. The
operator reads all of them the same way, so the few that matter sit among
the many that do not.

PRD-07 (factory item D-02) separates the two. Agent 7 marks each item with
its **scope**, and a later slice (K5) lets `/pr-iterate` decide the inside
items itself and log each decision in the PR body. The word `scope` and its
two values were declared by ADR-0037 clause 6, which left the rule to a
later record. This is that record. It is fixed before K5 because every
reader of the confirm-list has to read a missing scope the same way.

## Decision drivers

- **Fail closed.** A review that forgets the mark, or writes a word nobody
  declared, must send the item to the operator, not to an agent.
- **Keep the machine contract.** The confirm-list is lifted line by line by
  `/pr-iterate` and by the broker: one item per line, glyph and tag first.
  The scope cannot move the tag.
- **Classifying is not deciding.** Agent 7 sees the diff in fresh context
  and judges nothing it could act on. The scope says who may decide an
  item, never that it is decided.

## Considered options

1. **A scope word on every ⚠️ item, outward by default** *(chosen)*.
2. **A new tag for inside items** (`ℹ️ INTERNAL`): rejected. A new tag changes
   the confirm-list's machine contract and every reader of it, and an item
   with a misspelt tag would drop out of every count instead of reaching
   the operator.
3. **Inside by default, with the reviewer marking only the outward items**:
   rejected. A forgotten mark would hand an exit-code change to an agent.

## Decision outcome

Chosen: **a scope word on every ⚠️ item, outward by default**.

1. **The line.** `scope: inside` when the item's effect stays inside the
   change: a name, a structure, internal error wording, a test's shape.
   `scope: outward` when a user, a consumer or another skill sees or relies
   on it: an output format, a flag, an exit code, a rule an agent obeys.
   The two words are the vocabulary's `scope` field (`scripts/vocab.config.sh`).
2. **Where the word is written.** In `/review-pr`'s confirm-list (§5b), the
   scope is the first words of the item's arrow line:
   `→ scope: inside — no spec reference found. Desired?`. In the dispatched
   worker's report (`.agents/prompts/review-worker.md`), it is the first
   words after the tag, on the item's own line, because the broker keeps the
   tagged line and drops every line beneath it. The tag stays first in both,
   one item per line.
3. **Outward by default.** Every reader of the confirm-list reads an item
   with no scope, or with a word the vocabulary's `scope` field does not
   hold, as `outward`. Only the whole word `inside` counts: `insider` is
   outward.
4. **Agent 7 classifies and never resolves.** Neither does `/implement`.
   Only `/pr-iterate`'s session may decide an inside item, and only once K5
   gives it the decision log. Until then `/pr-iterate` keeps every ⚠️ item
   for the operator, as its hard rule 4 says. An outward item is always the
   operator's.
5. **The verdict counts outward items.** `/review-pr`'s Axis-2
   `review.verdict` records `data.outward`, the ⚠️ items read as outward,
   beside `data.unspecified`. The broker counts it the same way from a
   dispatched report. The verdict's outcome is unchanged: `confirm` when any
   item needs the operator.
6. **Shared invariant §5 does not move.** Behavior findings stay out of the
   autonomous fix loop. The scope only narrows which items an agent may
   later decide, and it narrows them toward the operator.

## Consequences

- **Good**: the operator can see the outward items first, and the trace
  counts them, so a later retro can measure how often an inside item turned
  out to matter.
- **Bad / trade-off**: the in-session list and the dispatched report put
  the word in two places (the arrow line, the tagged line). Both readers
  are told where to look, and the broker suite and the review-output suite
  hold each shape.
- **Neutral**: the CI review prompt (`templates/workflows/ai-review-prompt.md`)
  writes no scope yet. Its items read as outward, which is today's
  behavior.
- **Honest limitation**: the scope is Agent 7's judgement. An item marked
  inside that a consumer does rely on is a misclassification no check can
  catch. K5's rule that a later review marking it outward strikes the
  decision (process/R59) is the correction.

## More information

- Implemented in: #873 (PRD-07, process/R53 to R55). Held by
  `tests/review-pr-output.test.sh` section 24 and `tests/forge-broker.test.sh`
  section 26.
- Builds on ADR-0037 clause 6, which declared the `scope` field.
