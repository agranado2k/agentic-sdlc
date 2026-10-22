---
id: T-05
type: ticket
title: "/retro checks a lens or skill edit before and after, by its Targets: query"
parent: PRD-03
stage: done
created: 2026-10-21
updated: 2026-10-22
deps: [T-03, T-04]
priority: 3
links:
  pr: "#823"
review:
  outcome: approved
  commit: "062d3ca"
  by: "review-pr (sonnet) on #823"
  at: 2026-10-22
qa:
  outcome: pass
  by: "merge-train (#823 landed, suite green)"
  at: 2026-10-22
---

# T-05 · /retro checks a lens or skill edit before and after, by its Targets: query

GitHub issue: #802

## Behaviour

Part of PRD-03, slice 3. Objective: a learning-loop edit is judged by a measure fixed when it was proposed.

A ticket that edits a review lens or a skill may carry a `Targets:` line: a trace filter over kinds and data fields (for example `kind=finding.raise data.agent=security data.severity=high`). `Targets:` joins the stamp vocabulary and is checked like any stamp line. For a landed ticket carrying one, `/retro` counts the query's matches per landed PR in the window before its landing and in an equal window after, and prints `<ticket> <label>: <before> → <after> per PR`. If the two windows differ in kit version or in tier → model mapping (read from the runs' recorded context and their spawns' models), it prints `inconclusive` with the reason. Failed runs are left out of both counts. An after-rate not below the before-rate files a finding naming the ticket. A lens or skill edit `/retro` itself proposes cites the trace events behind it by run id and carries its `Targets:` line, and is not filed without both.

## Acceptance

- Fixture traces give a drop, no drop (a finding filed), a changed mapping (inconclusive), and a failed run excluded.
- A suite asserts R28's filing rule is in `/retro`.
- The living process spec gains process/R25 to R28.

Covers: process/R25, process/R26, process/R27, process/R28
Tier: implementer
Confidence: low
Label: none
