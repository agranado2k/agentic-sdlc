---
id: T-04
type: ticket
title: /retro reports lead time, review wait and toil's share
parent: PRD-03
stage: ready
created: 2026-10-21
updated: 2026-10-21
deps: []
priority: 1
---

# T-04 · /retro reports lead time, review wait and toil's share

GitHub issue: #799

## Behaviour

Part of PRD-03, slice 2. Objective: show where tickets wait, and how much of the waiting is on the operator.

`/retro` gains a flow section. Per landed ticket in the window: lead time from its first `ticket.start` to its `merge.land`; per landed PR: review wait from its last `pr.iterate outcome=green` to its `merge.land`, or `n/a` for a PR with no green iteration (never zero). Each column shows the window's median and longest. Toil's share is the count of landed tickets whose `ticket.start` carries `data.class=toil`, as `toil: <n> of <m> landed`, or `toil: not recorded` when no ticket in the window carries a class. `ticket.start` accepts `data.class` from the consumer; the kit names no class of its own. Reads only events the trace already records.

## Acceptance

- A fixture trace of five landed tickets gives the expected lead times, review waits (one `n/a`) and toil line; a fixture with no class gives `toil: not recorded`.
- The living process spec gains process/R22 to R24.

Covers: process/R22, process/R23, process/R24
Tier: implementer
Confidence: high
Label: none
