---
id: T-17
type: ticket
title: A subagent stop with no run records its Trace-Spawn ticket
parent: agentic-sdlc
class: toil
stage: done
created: 2026-10-23
updated: 2026-10-25
deps: []
priority: 3
links:
  pr: "#856"
approved_by: "agranado"
approved_at: 2026-10-25
review:
  outcome: approved
  commit: "a812a15"
  by: "review-pr on #856"
  at: 2026-10-25
qa:
  outcome: pass
  by: "land.kit.sh (#856 landed, main workflows green)"
  at: 2026-10-25
---

# T-17 · A subagent stop with no run records its Trace-Spawn ticket

GitHub issue: #847

Finding (retro R2, Q5 and Q6): 80% of the window's subagent spend cannot be traced to a ticket. The orchestrating session had no run open, so the stops of the ticket sessions it spawned were filed under no run, and later under the merge train's run.

Retro: retro-20261023T103804Z

## Evidence

- Subagent stops tied to a ticket or a PR: $16.24 of $83.27. The remaining $67.03 is under no ticket.
- Implementer stops from 16:08 to 17:41 on 2026-10-22 carry no run. Later ones carry the train's run.
- Related: #580 (closed 2026-10-07) built spend attribution through the `Trace-Run:` line. This evidence comes after it: a spawn with no `Trace-Run:` line still carries `Trace-Spawn: … ticket=#N`.

## Behaviour

- When a subagent's spawn prompt carries no `Trace-Run:` line, its stop event records the ticket its `Trace-Spawn:` line names, as `data.ticket`.
- The retro's per-ticket spend joins on that ticket when no run ties the stop to one.
- A stop that has a run is unchanged.

## Acceptance

- The trace-hooks suite has a stop leg with a `Trace-Spawn: … ticket=#7` line and no `Trace-Run:` line, red first.
- The retro's spend question names `data.ticket` as its fallback join, asserted by its suite.

## Demo

A stop with no run, spawned for ticket #7, shows `data.ticket=#7` in the trace.

Tier: implementer
Confidence: medium
Label: none
Class: toil
