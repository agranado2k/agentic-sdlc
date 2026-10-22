---
id: T-14
type: ticket
title: /pr-iterate emits every iteration and triages every re-review raise
parent: agentic-sdlc
class: toil
stage: proposed
created: 2026-10-22
updated: 2026-10-22
deps: []
priority: 3
---

# T-14 · /pr-iterate emits every iteration and triages every re-review raise

GitHub issue: #835

Finding (retro F4, Q2 and Q6): a re-review's findings go untriaged, and /pr-iterate skips iteration emits.

Retro: retro-20261022T135553Z

## Evidence

- pr:#809's second review raised 11 findings: one high (H-1), six medium and four low, all `posted=no`. None was triaged, and the PR reached green at iteration 4.
- pr.iterate iteration numbers skip with no emit in between: #808 1→7, #809 1→4, #810 1→4, #811 2→4.
- #770 (closed) made re-reviews record their raises. Triaging those raises is this ticket's separate ask.

Runs: 20261021T112121Z-4105734-714caf1f 20261021T153532Z-3833166-223fba27 20261021T114802Z-2043606-cdd699b1 20261021T164154Z-2258383-4ad1d852

## Behaviour

- /pr-iterate emits its `pr.iterate` event on every iteration.
- Every raise of a re-review gets a local `finding.triage` before the PR is reported green.

## Acceptance

- A chain-emits suite assertion holds the skill's text to both rules and fails without them.

Tier: implementer
Confidence: medium
Class: toil
Targets: kind=finding.raise data.severity=high data.posted=no
Label: none
