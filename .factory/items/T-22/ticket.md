---
id: T-22
type: ticket
title: Suites pass with TRACE_HARNESS and TRACE_MODEL exported
parent: agentic-sdlc
class: toil
stage: proposed
created: 2026-10-23
updated: 2026-10-23
deps: []
priority: 3
---

# T-22 · Suites pass with TRACE_HARNESS and TRACE_MODEL exported

GitHub issue: #861

Toil from the 2026-10-23 wave: three implementer sessions saw the fixture-builders and suite-budget suites fail in their own shells, because an agent session exports TRACE_HARNESS and TRACE_MODEL and those suites inherit them. CI, which exports neither, stayed green, so the failure is environmental and looks like a regression to whoever runs the suite.

A suite builds its own environment for the trace: neither suite reads an inherited TRACE_HARNESS or TRACE_MODEL, so each passes the same with those variables exported as without. Where the clearing belongs (each suite, or the shared test harness for every suite) is the implementer's call; say which in the PR.

## Acceptance
- Both suites pass with TRACE_HARNESS and TRACE_MODEL exported to any non-empty value, and pass without them.
- A case in each suite drives that: run with the variables exported, it fails before the fix and passes after.

Class: toil
Tier: implementer
Confidence: medium
