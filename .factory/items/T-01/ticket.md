---
id: T-01
type: ticket
title: A review in which no lens ran records blocked, and /pr-iterate does not converge on it
parent: PRD-01
stage: ready
created: 2026-10-21
updated: 2026-10-21
deps: []
priority: 1
---

# T-01 · A review in which no lens ran records blocked, and /pr-iterate does not converge on it

GitHub issue: #796

## Behaviour

Part of PRD-01. Objective: an empty review can never stand in for a review.

When every standards lens slice is empty, `/review-pr` runs the single-reviewer pass over the whole diff and records no verdict until that pass returns. When no lens returned a report and no single-reviewer pass returned either (every slice empty and the pass's spawn failing, or every spawn failing), the review records `review.verdict outcome=blocked data.lenses=0` with the reason `no lens ran`. Its Verdict line reads `BLOCKED — no lens ran; this is not a review`. `/pr-iterate` reads that verdict as not converged and escalates it at the top of its report. A review where some lenses ran is unchanged.

## Acceptance

- A suite asserts each requirement's sentence is in the skill text it binds (`/review-pr` for R15 and R16, `/pr-iterate` for R17).
- A fixture review over a diff that no lens-slice rule selects (a new top-level directory) takes the single-reviewer path.
- The living process spec gains process/R15 to R17.
- Manual demo: PRD-01 UC1 2a, with the single-reviewer spawn made to fail.

Covers: process/R15, process/R16, process/R17
Tier: implementer
Confidence: high
Label: none
