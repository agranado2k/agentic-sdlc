---
id: PRD-03
type: prd
title: Runs record their context, and /retro measures flow and checks learning-loop edits
parent: D-01
stage: review
created: 2026-10-20
updated: 2026-10-21
---

# PRD-03 · Runs record their context, and /retro measures flow and checks learning-loop edits

## 1. Objective

Have every run record the context it ran in (the kit's version, the model, the tools), and have
`/retro` report three flow measures it lacks (lead time, review wait and toil's share). Also have
`/retro` check every lens or skill edit against the trace, before and after, by a measure fixed
when the edit was proposed.

`/retro` already reports PR iterations to green and cost per tier (Q1), cost per ticket (Q5),
and the operator's verdicts (Q7). It does not report how long a ticket takes from start to land,
how long a green PR waits for its human, or how much of the landed work is toil. And no
learning-loop edit is ever checked: a lens is changed to catch a kind of finding, and nobody
counts whether that kind then drops. Such a count is only fair when both windows ran under the
same models and kit, and `trace.sh begin` records neither today. The `row` schema has `model`
and `harness`, but they are filled only when a caller passes them.

These come from the software factory's D-03 Q19 proposal 3 (research row 6), Q12 and Q20 (its
metrics, with review wait as research row 15, the bottleneck its S-1 says to measure first), and
Q17 with its refinement (the before-and-after check: fixed, cited, like with like, after
Harness², arXiv 2610.14224).

The test of done:
- A `/retro` over a window with five landed tickets prints a lead time and a review wait for
  each, and toil's share.
- For a merged lens edit whose ticket names a `Targets:` query, `/retro` prints the rate before
  and after, or `inconclusive` when the windows ran under different tier mappings.

## 2. Users and scenarios

**U1 — the operator**, reading `/retro`. **U2 — an agent proposing a lens or skill edit.**

Stories:

1. As the operator, I want each run to say which kit and model it ran under, so that a
   comparison across time compares like with like.
2. As the operator, I want lead time, review wait and toil's share, so that I can see where
   tickets wait. Review wait is time spent waiting on me.
3. As the operator, I want each lens or skill edit checked by a measure fixed in advance, so
   that whoever proposes an edit cannot move the bar it is judged by.

**UC1 — Read the flow.** Actor: the operator, running `/retro` after a wave of five tickets.
1. `/retro` reads the window.
2. Its flow section prints, per landed ticket, the lead time from the first `ticket.start` to
   `merge.land`, and the review wait from the last `pr.iterate outcome=green` to `merge.land`.
   Each column shows its median and its longest.
3. It prints `toil: 2 of 5 landed` from `ticket.start`'s `data.class`.

Extensions:
- 2a. A PR had no green iteration before its merge. Its review wait is reported as `n/a`, not as zero.
- 3a. No `ticket.start` in the window carries `data.class`. The line reads `toil: not recorded`.

**UC2 — Check a lens edit.** Actor: the operator, two waves after merging T-61. T-61 tightened
the security lens and carries `Targets: kind=finding.raise data.agent=security
data.severity=high`.
1. `/retro` finds T-61's `merge.land` and its `Targets:` line.
2. It counts the matching events per landed PR in the window before the landing and in the
   window after, of equal length.
3. Every `run.start` in both windows records the same tier → model mapping and kit version. It
   prints `T-61 security/high: 0.8 → 0.3 per PR`.

Extensions:
- 3a. The models differ between the windows. It prints `T-61: inconclusive — tier mapping
  changed`.
- 3b. The rate did not drop. `/retro` files a finding naming T-61, which can reopen or revert
  it.
- 3c. A run in the window failed. It is left out of both counts, not counted as zero.

**UC3 — Propose an edit with its evidence.** Actor: `/retro` itself, proposing a lens edit.
1. The candidate ticket names the trace events behind it by run id, and its `Targets:` query.
2. A candidate with no cited events is not filed.

## 3. Model

- `run.start` gains `data.kit`, the `VERSION` file's `shared-layer:` value as written (`0.78.0`), `model` and `harness`,
  where the harness exposes them. `spawn` gains `data.tools`, the spawned agent type's tool list.
- `ticket.start` accepts `data.class`. A consumer marks toil there, and the kit names no class
  of its own.
- A ticket that edits a review lens or a skill carries a `Targets:` line: a `trace.sh` filter
  over kinds and data fields, checked like any stamp line.

## 4. Rules

Area: runtime

Deltas against `docs/specs/runtime.md`, which ends at R27.

### ADDED

runtime/R28. WHEN `trace.sh begin` opens a run, its `run.start` SHALL carry `data.kit`, read from `VERSION`. [UC2 3]
runtime/R29. WHEN the harness exposes the session's model or its own name, `run.start` SHALL carry `model` and `harness`, and SHALL leave out a value the harness does not expose, never guessing it. [UC2 3]
runtime/R30. WHEN a spawn is recorded, its `spawn` event SHALL carry `data.tools`, the tool list of the agent type it spawned as.

Area: process

Deltas against `docs/specs/process.md`, numbered after PRD-02's process/R18 to R21.

### ADDED

process/R22. `/retro` SHALL report, per landed ticket in the window, the lead time from its first `ticket.start` to its `merge.land`, with the window's median and longest. [UC1 2]
process/R23. `/retro` SHALL report, per landed PR, the review wait from its last `pr.iterate outcome=green` to its `merge.land`, and SHALL report `n/a` for a PR with no green iteration. [UC1 2, 2a]
process/R24. `/retro` SHALL report toil's share of landed tickets from `ticket.start`'s `data.class=toil`, and `not recorded` when no ticket in the window carries a class. [UC1 3, 3a]
process/R25. WHEN a landed ticket carries a `Targets:` line, `/retro` SHALL report that query's count per landed PR in the window before its landing and in an equal window after. [UC2 2, 3]
process/R26. IF the two windows of R25 differ in tier → model mapping or in kit version, THEN `/retro` SHALL report the comparison as inconclusive, and SHALL leave failed runs out of both counts. [UC2 3a, 3c]
process/R27. IF R25's after-rate is not below its before-rate, THEN `/retro` SHALL file a finding naming the ticket. [UC2 3b]
process/R28. A lens or skill edit that `/retro` proposes SHALL cite the trace events behind it by run id and carry its `Targets:` line, and SHALL NOT be filed without them. [UC3 1, 2]

## 5. Slices (vertical, demoable, in order)

**Slice 1 — runs record their context.**
- *Covers:* runtime/R28, R29, R30.
- *Accept:* a trace suite asserts `run.start` carries `data.kit`, and `model` when the harness
  variable is set and none when it is not. It asserts `spawn` carries `data.tools`.

**Slice 2 — the flow measures.**
- *Covers:* process/R22, R23, R24.
- *Accept:* a fixture trace of five tickets gives the expected lead times, review waits and toil
  line.

**Slice 3 — the before-and-after check.**
- *Covers:* process/R25, R26, R27, R28.
- *Also:* `Targets:` joins the stamp vocabulary, `scripts/vocab.config.sh`.
- *Accept:* fixture traces give a drop, no drop (a finding), and a changed mapping
  (inconclusive).

## 6. Non-goals (this PRD)

- **An eval set** — *later*: the first escaped defect or reverted ticket starts one (the
  factory's Q17).
- **A scheduled weekly `/retro`** — *later* (its Q20): `/retro` runs per wave. Reopen when the
  before-and-after check has windows worth comparing.
- **A `stats` command or a dashboard** — *never* here: `/retro` is the one reader of the trace.

## 7. Technical constraints

POSIX `sh` and the trace's existing reader. The trace stays append-only, and no field holds
untrusted text. The kit's ADR-0008 holds: the trace is written by skills and read only by `/retro`.

## 8. Decisions recorded for this PRD

- The software factory's D-03 Q12, Q17 and its refinement, Q19 proposal 3, and Q20.
- **Derived while writing:**
  - Review wait is measured from the last green iteration to the merge, because the merge
    is the kit's human gate (shared invariant §7) and the trace records no human review.
  - Toil is a consumer's class on `ticket.start`, because the kit has no toil concept.

  The maintainer confirms both at approval.

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

- **How a run learns its model under Claude Code.** MVP: the adapter's session hook passes it
  where the hook payload carries it.
- **Window length for R25.** MVP: equal to `/retro`'s window, before and after the landing.

## 10. Dogfood plan

Three tickets in slice order. The software factory wires its session hooks (its PRD-08 Slice
5) before it takes this release, so its first `/retro` after the update has priced, versioned
runs.
