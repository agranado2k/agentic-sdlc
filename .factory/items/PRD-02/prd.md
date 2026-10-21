---
id: PRD-02
type: prd
title: Stop after repeated identical failures
parent: D-01
stage: review
created: 2026-10-20
updated: 2026-10-21
---

# PRD-02 · Stop after repeated identical failures

## 1. Objective

Make `/pr-iterate` and `/implement` stop and escalate when the same failure comes back
unchanged after their fixes, instead of spending iterations on a loop that is not converging.

Today `/pr-iterate`'s only cap is "5 iterations completed without convergence (likely stuck) →
escalate". It counts iterations, not repeats. So a check that fails the same way three times
running uses three more iterations of fixes and pushes before the cap fires. `/implement` has no
cap at all: its full-suite run can fail on the same test after each edit with nothing telling it
to stop. `/retro`'s "Recurring failures" question finds such repeats only after the wave. This is
the software factory's D-03 Q19 proposal 2 (its research, row 34). A token budget per ticket
waits for cost data (its Q12) and is out of scope.

The test of done: a `/pr-iterate` run that sees the same failing check, with the same failure
signature, on its third consecutive iteration stops, records the stop in the trace, and
escalates. It pushes no fourth fix.

## 2. Users and scenarios

**U1 — the operator**, who gets the escalation. **U2 — the agent** running the loop.

Stories:

1. As the operator, I want a stuck loop to stop at the first clear sign it is stuck, so that I
   am called while the cause is still one change old, not five.
2. As the agent, I want a written rule for "the same failure again", so that I stop on evidence
   rather than on my own judgement of progress.

**UC1 — A check that does not move.** Actor: `/pr-iterate` on PR #820.
1. Iteration 1: `test (ubuntu)` fails with `tests/trace.sh: line 212: expected 3, got 2`. The
   agent pushes a fix.
2. Iteration 2: the same check fails with the same first error line. The agent pushes a second
   fix.
3. Iteration 3: the same check fails with the same line again. The agent stops, pushes nothing,
   and escalates `repeated identical failure: test (ubuntu), 3 iterations`, quoting the line.

Extensions:
- 2a. The check fails with a different first error line. The count restarts at 1.
- 3a. A different check fails at iteration 3. Only a repeat of the same signature counts.

**UC2 — A test that does not move.** Actor: `/implement`, at step 4's full-suite run.
1. The suite fails on `tests/stamp.sh: refuses a long line`. The agent edits.
2. It fails again on the same test with the same assertion, and again after a second edit.
3. The agent stops editing and reports the test, the assertion, and what each edit tried.

## 3. Model

A **failure signature** is a check's name, or a test's name, plus the first error line of its
log, with digits that are only run ids or timestamps removed. Two failures are identical when
their signatures are equal. The threshold is 3 consecutive identical failures, counted per
signature.

## 4. Rules

Area: process

Deltas against `docs/specs/process.md`, numbered after PRD-01's process/R15 to R17.

### ADDED

process/R18. WHEN `/pr-iterate` sees a failure with the same signature on 3 consecutive iterations, it SHALL push no further fix, and SHALL escalate naming the check, the count and the quoted error line. [UC1 3]
process/R19. WHEN a failure's signature differs from the previous iteration's, `/pr-iterate` SHALL restart that count. [UC1 2a, 3a]
process/R20. WHEN `/implement`'s full-suite run fails with the same signature 3 consecutive times, it SHALL stop editing and report the test, the assertion and each attempt, without pushing. [UC2 3]
process/R21. WHEN either skill stops under R18 or R20, it SHALL record the stop in the trace with `data.stop=repeated-failure` and the signature's check or test name, never the log text.

## 5. Slices (vertical, demoable, in order)

**Slice 1 — the stop in both loops.**
- *Covers:* process/R18, R19, R20, R21.
- *Accept:*
  - Suites assert each sentence is in its skill.
  - A signature fixture shows two logs that differ only in a run id are equal, and two that
    differ in the error are not.
- *Manual demo:* UC1, on a branch with a test made to fail the same way.

## 6. Non-goals (this PRD)

- **A token or cost budget per ticket** — *later*: it waits for priced session data (the
  factory's Q12). Reopen once `/retro`'s spend question has a few waves of it.
- **Changing the 5-iteration cap** — *never* here: it stays the backstop for loops that fail
  differently each time.

## 7. Technical constraints

Skill text and suites. If the signature needs a helper, it is a small POSIX `sh` script under
`scripts/`, with its own suite.

## 8. Decisions recorded for this PRD

- The software factory's D-03 Q19, proposal 2.
- **Derived while writing:** the threshold of 3 and the signature's shape. The maintainer
  confirms at approval.

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

- **Which trace kind carries R21's stop.** MVP: the loop's existing kind (`pr.iterate` for
  `/pr-iterate`, `note` for `/implement`) with `data.stop`. A new kind needs `TRACE_KINDS`.

## 10. Dogfood plan

One ticket. The software factory takes it with the release.
