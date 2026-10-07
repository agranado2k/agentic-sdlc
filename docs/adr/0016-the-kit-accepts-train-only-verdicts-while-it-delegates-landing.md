# ADR-0016: The kit accepts train-only verdicts while it delegates landing

- **Status**: Accepted
- **Date**: 2026-10-06
- **Deciders**: Arthur Granado (the operator), ruling on #570
- **Supersedes / amends**: — (reads alongside ADR-0008's amendment of 2026-10-01, #385: a window of `train` verdicts is no human verdict)
- **Superseded by**: —

## Context and problem statement

`/merge-train` records a `feedback` event per landed slice, and `data.by`
says whether the verdict was the operator's or the train's own under a
delegating instruction (ADR-0008, amended 2026-10-01). `/retro` questions 7
(aim calibration) and 8 (stamp calibration) grade their rows against human
verdicts: an operator's `feedback`, a human dismissing a posted finding, a
human overriding a stamp at the quiz.

The operator delegates landing. Retro `retro-20261006T080718Z` found, for the
fourth window running, no human verdict on any landing — 0 operator, 2 train
and 38 `unasked` of 40 landings — and 0 dismissals of 255 posted findings.
Each window re-raised "no human verdict" as a finding, and each finding asked
the one person who had already chosen not to answer. #570 put the question to
the operator: ask for a verdict now and then, or accept train-only verdicts?

## Decision drivers

- A finding nobody will act on is noise that buries the findings somebody will.
- The calibration must not be lost: the first human verdict should be read.
- `/retro` ships unstamped, so whatever it reads must be a place every
  consumer project has.

## Considered options

1. **Accept train-only verdicts, recorded as a decision record the retro reads** *(chosen)*
2. **Ask the operator for a verdict on one landing in N, or on every release** —
   rejected by the operator on #570: delegated landings stay `unasked`.
3. **Leave the questions raising the finding** — rejected: four windows of the
   same finding with no ticket behind it is the loop failing, not the wave.

## Decision outcome

Chosen: **the kit accepts train-only verdicts while it delegates landing.**

1. A landing this kit delegates needs no operator verdict: the train's own
   verdict, or `unasked`, is accepted as the landing's feedback.
2. This record is the kit's answer to `/retro`'s train-only condition: with it
   binding, questions 7 and 8 answer
   `retired: no operator verdict in the window, and the project accepts train-only verdicts (<the record>)`
   for a window holding no operator verdict, and raise no finding for it.
3. The retirement is per window, not standing: the first window holding an
   operator verdict — an operator `feedback` for question 7, a dismissal or a
   quiz override for question 8 — is calibrated as before.
4. **Explicit non-goal**: this does not stop the train from recording
   `feedback`, nor the operator from giving a verdict; a landing with no
   `feedback` event at all is still a missing emit for question 6.

## Consequences

- **Good**: the retro stops re-raising a finding the operator has answered, and
  its findings list carries only what somebody will act on.
- **Bad / trade-off**: while no human grades a landing or a stamp, the aim and
  stamp calibrations measure nothing; the kit learns about its rubric only
  from the windows a human touches.
- **Neutral**: a consumer project takes the same behavior by recording a
  decision of its own; the skill names no kit file.
- **Honest limitation**: a train's verdict is the chain grading itself; the
  retired line says so by naming this record rather than implying a measurement.

## More information

- Ruling: #570 (operator's answer, 2026-10-06). Built by #572.
- Related: ADR-0008 (the `feedback` event and `data.by`); `/retro`'s
  `QUESTIONS.md`, questions 7 and 8.
