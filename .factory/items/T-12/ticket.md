---
id: T-12
type: ticket
title: "/to-tickets: one VERSION-moving ticket per frontier"
parent: agentic-sdlc
class: toil
stage: ready
created: 2026-10-22
updated: 2026-10-22
deps: []
priority: 3
approved_by: "agranado"
approved_at: 2026-10-22
---

# T-12 · "/to-tickets: one VERSION-moving ticket per frontier"

GitHub issue: #833

Finding (retro F2, Q3, Q6 and Flow): parallel PRs that each move the shared layer collide on VERSION and get re-cut one after another.

Retro: retro-20261022T135553Z

## Evidence

- 8 `pr.iterate data.cause=conflict` iterations on 7 PRs (#805 #806 #807×2 #808 #810 #811 #825).
- Release-bound red on #808 and #821.
- 8 releases (v0.79.0–v0.86.0) in 2 days.
- The parallel frontier's lead times were 5–9 h, against under 1.5 h for the serial tail.

Runs: 20261021T160220Z-635741-b4c2f110 20261021T162220Z-1473130-4a7db2d6 20261021T164154Z-2258383-4ad1d852 20261021T181423Z-2292619-dd28197d 20261022T111547Z-42912-a826d322

## Behaviour

/to-tickets gains a rule: a frontier holds at most one ticket that moves a VERSION-listed file, or the frontier's bumps are deferred to one release ticket at its tail. Decide which in the ticket and record the choice. The hand-off's session cap and sequencing honour the rule.

## Acceptance

- A to-tickets contract suite leg pins the rule's text and fails without it.
- The next /retro's before-and-after section judges the edit by the query below.

Tier: planner
Confidence: medium
Class: toil
Targets: kind=pr.iterate data.cause=conflict
Label: ready-for-agent
