---
id: T-02
type: ticket
title: Stop after three identical failures in /pr-iterate and /implement
parent: PRD-02
stage: ready
created: 2026-10-21
updated: 2026-10-21
deps: []
priority: 2
---

# T-02 · Stop after three identical failures in /pr-iterate and /implement

GitHub issue: #797

## Behaviour

Part of PRD-02. Objective: a loop that is not converging stops at the first clear sign, not after five iterations.

A failure signature is a check's or test's name plus the first error line of its log, with digits that are only run ids or timestamps removed. `/pr-iterate` that sees the same signature on 3 consecutive iterations pushes no further fix and escalates, naming the check, the count and the quoted error line; a different signature restarts the count. `/implement` whose full-suite run fails with the same signature 3 consecutive times stops editing and reports the test, the assertion and each attempt, without pushing. Either stop is traced on the loop's existing kind (`pr.iterate`, or `note` for `/implement`) with `data.stop=repeated-failure` and the check or test name, never the log text. The 5-iteration cap stays as the backstop.

Shared layer: if the signature is computed by a helper script that ships to consumers, the helper joins the shared-layer manifest and this ticket carries the minor bump, its update-recipe entry and the re-captured pinned transcripts (hard rule 3, the kit's ADR-0025).

## Acceptance

- Suites assert each requirement's sentence is in its skill.
- A signature fixture: two logs that differ only in a run id give equal signatures; two that differ in the error do not.
- The living process spec gains process/R18 to R21.
- Manual demo: PRD-02 UC1, on a branch with a test made to fail the same way.

Covers: process/R18, process/R19, process/R20, process/R21
Tier: implementer
Confidence: high
Label: none
