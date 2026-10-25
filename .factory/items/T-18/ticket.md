---
id: T-18
type: ticket
title: "/review-pr: lenses state the ADR-0025 bump rule; a failed lens is never audited"
parent: agentic-sdlc
class: toil
stage: done
created: 2026-10-23
updated: 2026-10-25
deps: []
priority: 3
links:
  pr: "#854"
approved_by: "agranado"
approved_at: 2026-10-25
review:
  outcome: approved
  commit: "1302955"
  by: "review-pr on #854"
  at: 2026-10-25
qa:
  outcome: pass
  by: "land.kit.sh (#854 landed, main workflows green)"
  at: 2026-10-25
---

# T-18 · /review-pr: lenses state the ADR-0025 bump rule; a failed lens is never audited

GitHub issue: #846

Finding (retro R1, Q2): review lenses keep raising "a skill edit owes a version bump", and every one is rejected under ADR-0025. The review skill also still lets its coordinator audit a lens that failed, which contradicts ADR-0035.

Retro: retro-20261023T103804Z

## Evidence

- pr:#841: the single reviewer raised it as high. pr:#844: the security lens raised it as medium (M-1). #843 answered it in its rulings. #792 and #807 earlier, in the previous window. Every one was rejected under ADR-0025.
- pr:#844 L-1: the line that lets the coordinator audit a refused or failed lens itself. That line was rejected only because #844 did not change it.
- Runs: 20261022T174023Z-3775106-bead96d2 20261022T193451Z-2947481-9fa81254 20261022T181106Z-446089-7229e0cd 20261022T204304Z-1876071-580b875c 20261022T210252Z-2644910-a2c5121a

## Behaviour

- The text every standards lens reads says that only the shared layer's file manifest owes a version bump, and that a skill is listed by name and owes none (ADR-0025). So a lens no longer raises a bump for a skill-only diff.
- When a lens is refused or fails, the review names it under "Lenses not run", and the coordinator does not audit its slice in its place (ADR-0035 clause 2).
- The review skill sits a few bytes under its size ceiling, so the edit must replace words rather than add them. Do not raise the ceiling.

## Acceptance

- The review skill's output suite asserts both sentences, red first.
- The docs gate is green with the skill under its ceiling.

## Demo

A lens slice over a skill-only diff carries the ADR-0025 sentence in the prompt the lens is given.

Targets: kind=finding.triage outcome=rejected

Tier: implementer
Confidence: medium
Label: none
Class: toil
