---
id: T-11
type: ticket
title: Trace refuses malformed review emits (finding.raise, review.verdict)
parent: agentic-sdlc
class: toil
stage: proposed
created: 2026-10-22
updated: 2026-10-22
deps: []
priority: 3
---

# T-11 · Trace refuses malformed review emits (finding.raise, review.verdict)

GitHub issue: #832

Finding (retro F1, Q6 and Q3): review events with missing or out-of-vocabulary fields reach the trace. `trace.sh emit` does not refuse them, and `verify` does not flag them.

Retro: retro-20261022T135553Z

## Evidence

- Three `finding.raise` events: pr:#788 M-1 has no `data.severity`, and its reason says LOW under an M id. pr:#821 L-0 has no severity and no agent, and its reason is "x" (a reviewer's probe). pr:#826 has no `data.id` and `data.severity=LOW` in upper case.
- Three `review.verdict` events: pr:#806 and pr:#810 have no `data.axis`. pr:#811, written through the broker, has no `outcome`.

## Behaviour

A rule with a failing check:
- `trace.sh emit` refuses (exit 2) a `finding.raise` whose `data.id` is not `[CHML]-N`, or whose `data.severity` is outside the severity words `vocab.sh` declares.
- It also refuses a `review.verdict` with no `outcome` or no `data.axis`.
- `verify` advises on events of those shapes already in the trace, which are history and stay.

## Acceptance

- The trace suite has a leg per malformed shape that drives the refusal RED, then green.
- The forge broker's suite asserts that its verdict carries an outcome.
- This moves the shared layer, so it ships as a release: a VERSION bump and an UPDATING.md entry.

Tier: implementer
Confidence: high
Class: toil
Label: ready-for-agent
