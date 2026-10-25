---
id: T-19
type: ticket
title: Transcript usage prices a stop whose last line is half-written
parent: agentic-sdlc
class: toil
stage: done
created: 2026-10-23
updated: 2026-10-25
deps: []
priority: 3
links:
  pr: "#855"
approved_by: "agranado"
approved_at: 2026-10-25
review:
  outcome: approved
  commit: "7b9e014"
  by: "review-pr on #855"
  at: 2026-10-25
qa:
  outcome: pass
  by: "land.kit.sh (#855 landed, main workflows green)"
  at: 2026-10-25
---

# T-19 · Transcript usage prices a stop whose last line is half-written

GitHub issue: #848

Finding (retro R3, Q5): a subagent stop is left unpriced when its transcript is read while the last line is still being written.

Retro: retro-20261023T103804Z

## Evidence

- 11 reviewer stops on pr:#844 (2026-10-22) carry no model or tokens. Their reason reads "transcript-usage: line 28 is not JSON".
- Two more stops did the same on 2026-10-07.

## Behaviour

- The transcript usage reader ignores a last line that is not terminated and does not parse, and prices the complete lines before it.
- A malformed line anywhere other than the last one is still an error, as it is today.

## Acceptance

- The stop-hook suite has a fixture whose last line is half-written. It is priced from the complete lines, red first.
- The fixture with a malformed middle line still fails as before.

## Demo

The half-written fixture yields a stop with its model and token counts.

Tier: implementer
Confidence: high
Label: ready-for-agent
Class: toil
