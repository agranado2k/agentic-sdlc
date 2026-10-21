---
id: PRD-01
type: prd
title: A review in which no lens ran is a block
parent: D-01
stage: approved
created: 2026-10-20
updated: 2026-10-21
approved_by: "Arthur Granado"
approved_at: 2026-10-21
---

# PRD-01 · A review in which no lens ran is a block

## 1. Objective

Make `/review-pr` record a review in which no standards lens returned a report as `blocked`,
not as `pass`, so that an empty review can never stand in for a review.

Today an empty lens slice records no spawn and is "not counted as a clean audit", and the
summary names it under `Lenses not run:`. That holds for one lens. But nothing says what
happens when **no** lens ran: every slice empty, every spawn failed, or a review where
`data.lenses=0` was recorded with no single-reviewer pass. The verdict line still allows `pass`
there ("`pass` is a verdict"). A diff whose paths no lens rule selects, such as a new top-level
directory, would then get an Axis-1 `pass` that nobody audited. This is the software factory's
D-03 Q19 proposal 1 (its research, row 2).

The test of done: a review over a diff whose every slice is empty, and on which no
single-reviewer pass ran, records `review.verdict outcome=blocked` with `reason` naming no lens
run, and its Verdict line says so.

## 2. Users and scenarios

**U1 — the operator**, reading the PR. **U2 — `/pr-iterate`**, deciding whether a PR has
converged.

Stories:

1. As the operator, I want a review that audited nothing to say it blocked, so that a green
   review always means somebody read the code.
2. As `/pr-iterate`, I want a no-lens review not to count as converged, so that the loop does
   not hand the operator an unaudited PR as ready.

**UC1 — A diff no lens selects.** Actor: `/review-pr`, on PR #812, which only adds
`setup/new-tool/`.
1. `scripts/lens-slice.sh` writes six slices of 0 files each.
2. No lens spawns. The review runs the single-reviewer pass over the whole diff, and the pass
   returns.
3. The verdict is recorded from that pass, `data.agent=single-reviewer`, as today.

Extensions:
- 2a. The single-reviewer pass cannot run (its spawn fails twice). The review records
  `review.verdict outcome=blocked data.lenses=0`, `reason='no lens ran'`. The Verdict line reads
  `BLOCKED — no lens ran; this is not a review`.
- 2b. Two lenses' spawns fail and four return. The verdict is decided on the four as today, and
  the summary names the two under `Lenses not run:`.

**UC2 — The loop does not converge on it.** Actor: `/pr-iterate`, on PR #812 after UC1 2a.
1. Its own `/review-pr` run records `blocked` for no lens run.
2. It reports the PR as not converged and escalates `no lens ran` at the top of its report.

## 3. Model

No new event kind. `review.verdict` already carries `outcome=pass|blocked`, `data.lenses` and
`data.roster`. A no-lens review is one with `data.lenses=0` and no single-reviewer pass.

## 4. Rules

Area: process

Deltas against `docs/specs/process.md`, which ends at R14.

### ADDED

process/R15. WHERE every lens slice is empty, `/review-pr` SHALL run the single-reviewer pass over the whole diff, and SHALL NOT record a verdict before that pass returns. [UC1 2]
process/R16. IF no Axis-1 lens returned a report and no single-reviewer pass returned, THEN `/review-pr` SHALL record `review.verdict outcome=blocked data.lenses=0` with the reason `no lens ran`, and its Verdict line SHALL say that no lens ran. [UC1 2a]
process/R17. WHEN `/pr-iterate`'s review records a verdict blocked because no lens ran, `/pr-iterate` SHALL NOT report the PR as converged, and SHALL escalate it at the top of its report. [UC2 1, 2]

## 5. Slices (vertical, demoable, in order)

**Slice 1 — the block, and the loop that honours it.**
- *Covers:* process/R15, R16, R17.
- *Accept:*
  - A suite under `tests/` asserts each requirement's sentence is in the skill text it binds.
  - A fixture review over a diff that no `scripts/lens-slice.config.sh` rule selects shows the
    single-reviewer path.
- *Manual demo:* UC1 2a, with the single-reviewer spawn made to fail.

## 6. Non-goals (this PRD)

- **A minimum number of lenses for a pass** — *later*: one returned lens is still a review.
  Reopen if `/retro`'s review-signal question shows one-lens reviews let defects through.
- **Changing what each lens's slice selects** — *never* here: that is policy data in each
  consumer's `scripts/lens-slice.config.sh`.

## 7. Technical constraints

Skill text and suites only. No change to `scripts/trace.sh`'s kinds or outcomes.

## 8. Decisions recorded for this PRD

- The software factory's D-03 Q18 (improvements go upstream) and Q19 (proposal 1 of 4). See
  D-01's sources.
- **Derived while writing:** R15 makes the all-empty case run the single-reviewer pass rather
  than block at once, because the skill already has that pass for an unaudited lens. The
  maintainer confirms at approval.

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

- **Whether the forge review workflow (`ai-review.yml`) needs the same rule.** MVP: no, since it
  is advisory and runs one reviewer.

## 10. Dogfood plan

One ticket. The software factory takes it through `UPDATING.md` with the release.
