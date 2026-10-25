---
id: T-23
type: ticket
title: /review-pr's skill regains 2000 bytes under its ceiling, no rule lost
parent: agentic-sdlc
class: toil
stage: done
created: 2026-10-23
updated: 2026-10-25
deps: []
priority: 3
links:
  pr: "#867"
approved_by: "agranado"
approved_at: 2026-10-25
review:
  outcome: approved
  commit: "f8ac4e2"
  by: "review-pr on #867"
  at: 2026-10-25
qa:
  outcome: pass
  by: "land.kit.sh (#867 landed, main workflows green)"
  at: 2026-10-25
---

# T-23 · /review-pr's skill regains 2000 bytes under its ceiling, no rule lost

GitHub issue: #863

Toil from the 2026-10-23 wave: /review-pr's skill sits at 40478 bytes under its 40500-byte ceiling in the docs gate's skill-ceiling policy, so the next one-line edit to the skill fails the gate. #854 landed with 22 bytes to spare.

Win back at least 2000 bytes of headroom with no rule lost: tighten the skill's prose in place (preferred), and lower nothing else. Every suite that asserts on the skill's text still passes. Moving text into a new file beside the skill is the fallback: it makes this ticket a shared-layer release, and it then waits for any other open release to land first. Raising the ceiling is not this ticket: that is a visible policy change for its own ticket, and only with the reason recorded.

## Acceptance
- The skill is at most 38500 bytes; the docs gate passes.
- Every suite that reads the skill passes unchanged in what it asserts.
- The PR lists each passage cut or reworded, so a reviewer can check no rule went with it.

Class: toil
Tier: implementer
Confidence: medium
