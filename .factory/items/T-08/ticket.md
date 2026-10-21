---
id: T-08
type: ticket
title: /to-prd writes scenarios as use cases, and /to-tickets reads their main flows
parent: PRD-05
stage: ready
created: 2026-10-21
updated: 2026-10-21
deps: []
priority: 1
---

# T-08 · /to-prd writes scenarios as use cases, and /to-tickets reads their main flows

GitHub issue: #801

## Behaviour

Part of PRD-05. Objective: a PRD's flows carry their branches, and each requirement traces to the step that needs it.

`/to-prd`'s template writes each scenario as a use case: `UC<n> — <name>`, an actor, a goal, a numbered main flow, and extensions numbered from the step they branch from (`2a`). Each requirement a step checks ends with those steps in brackets (`[UC1 3a]`); a requirement no step reaches carries none. `/to-tickets` reads each use case's main flow as a candidate tracer bullet and sorts each extension's requirements onto the slice that builds that step or a later one. A PRD written before the change keeps its walkthrough scenarios and nothing refuses them; the coverage check is unchanged.

## Acceptance

- Suites assert the template's use-case shape and the bracket form in `/to-prd`, and the reading rule in `/to-tickets`.
- A suite shows a walkthrough-shaped PRD still passes the coverage check.
- The living process spec gains process/R33 to R36.

Covers: process/R33, process/R34, process/R35, process/R36
Tier: implementer
Confidence: high
Label: none
