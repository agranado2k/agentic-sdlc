---
id: T-25
type: ticket
title: The review-pr output suite bait cases share one copy-and-edit helper
parent: agentic-sdlc
class: toil
stage: done
created: 2026-10-23
updated: 2026-10-25
deps: []
priority: 3
links:
  pr: "#864"
approved_by: "agranado"
approved_at: 2026-10-25
review:
  outcome: approved
  commit: "4de1b40"
  by: "review-pr on #864"
  at: 2026-10-25
qa:
  outcome: pass
  by: "land.kit.sh (#864 landed, main workflows green)"
  at: 2026-10-25
---

# T-25 · The review-pr output suite bait cases share one copy-and-edit helper

GitHub issue: #860

Toil from the 2026-10-23 wave: the /review-pr output suite grew four separate helpers that each copy the skill, apply an edit to the copy, and check what the suite's holder says about it. Each new rule added another near-copy.

Fold them into one helper the suite's bait cases all call, with every existing case kept and none weakened: a behaviour-preserving refactor of the suite alone (shared invariant §10, no behaviour change in the same commit). A case that cannot use the shared helper without changing what it asserts keeps its own and says why in one comment.

## Acceptance
the oracle: `sh tests/review-pr-output.test.sh`
- The suite passes, with the same count of passing cases as before the change.
- The suite defines one copy-and-edit helper, not four.

Class: toil
Tier: mechanical
Confidence: low
