---
id: T-16
type: ticket
title: "/to-tickets: split a ticket spanning trace emitter, hook and guard"
parent: agentic-sdlc
class: toil
stage: proposed
created: 2026-10-22
updated: 2026-10-22
deps: [T-12]
priority: 3
---

# T-16 · "/to-tickets: split a ticket spanning trace emitter, hook and guard"

GitHub issue: #837

Finding (retro F6, Q5 and Q1): a ticket ran past one context window's worth of iteration and spend.

Retro: retro-20261022T135553Z

## Evidence

ticket:#798 / pr:#809 took 4 iterations and $14.79, against the wave median of 1 iteration and $5.75. It was stamped confidence `low`. It touched the trace emitter, the hook and the guard together.

## Behaviour

/to-tickets' sizing rule (rule 2) gains a concrete split: a ticket whose work spans more than one of the trace emitter, an agent-harness hook and a guard is split at the seam between them. A `low`-confidence tier stamp is a prompt to look for such a split before the quiz.

## Acceptance

- A to-tickets contract leg pins the rule's text and fails without it.

Blocked by: #833 (T-12)

Tier: planner
Confidence: low
Class: toil
Label: none
