# ADR-0049: The lane handles a lane landing's escape once, with a revert pull request held for the operator

- **Status**: Accepted
- **Date**: 2026-11-08
- **Deciders**: the implementer session for #917 (PRD-10 slice 3, T-54), under the operator's standing delegation of rulings; the escape's handling is PRD-10 §5 and ADR-0047 clause 6, approved by the operator; the merge of this record's pull request is the operator's yes
- **Supersedes / amends**: amends ADR-0024 clause 1, which gains the kind `lane.escape`, and ADR-0019 clause 1, whose landing script gains the lane's escape reads; recorded as a new record because ADR-0024 takes no further in-place amendment and ADR-0019 is at its cap of five (ADR-0021 clause 5), as ADR-0036, ADR-0045 and ADR-0047 did
- **Superseded by**: —

## Context and problem statement

ADR-0047 lets a low-risk pull request land with no act of the operator's,
through the landing script's lane mode, and says an escaped mistake returns
to the operator (clause 6): one notice, and for a failed QA a revert pull
request held for them. It left the mechanism to PRD-10's third slice
(clause 10). The lane's second slice built the holds; nothing yet notices a
lane landing that turned out wrong.

An escape is a post-merge outcome (ADR-0036) against a pull request the lane
landed. The trace records it as a `merge.outcome`, written by the outcome
recorder, which ADR-0047 clause 7 already lets the lane run. What was
undecided: where in a lane run the escape is handled, how the lane finds
every escape when the trace's readers are asked one subject at a time, what
is recorded, and what a run does when handling fails.

## Decision drivers

- An escape is handled once: one revert pull request, one notice, one event,
  however many lane runs follow.
- Failing closed: an escape the lane could not hand back keeps the lane from
  landing anything until it can.
- The lane acts on the forge, so it reads no prose and writes none
  (runtime/R102): only closed tokens, numbers, shas and review area names.
- The lane runs the base branch's own code (ADR-0047 clause 4's `drift`).

## Considered options

1. **Handle escapes past `closed` and `drift`, as the third check** — chosen.
2. **Handle escapes before any check.** Rejected: a closed lane names no
   operator to notify, and a drifted run would open pull requests from code
   the base branch does not hold.
3. **A new trace subcommand that lists unhandled escapes.** Rejected: it adds
   a reader to ADR-0024 clause 7's list. The existing `show` reader taking a
   kind with no subject answers the same question.

## Decision outcome

Chosen option: 1.

1. **The kind `lane.escape`** (amending ADR-0024 clause 1): outcomes
   `revert`, `fix` and `notified`, its subject the escaped pull request, its
   outcome required. Any other outcome on it is refused, exit 2, writing
   nothing (runtime/R93). This slice writes only `revert`; `fix` (a revert
   that does not apply) and `notified` (an escape already undone) are #918's.
2. **`show --kind <kind>` with no subject** prints every event of that kind.
   A `show` naming neither a subject nor a kind is a usage error. It is the
   one way the lane sees escapes across every pull request (runtime/R92).
3. **Where it runs.** In lane mode, past `closed` and `drift`, the landing
   script runs `outcomes`, the outcome recorder, then reads `show` for
   `merge.land`, `merge.outcome` and `lane.escape` (amending ADR-0019
   clause 1, in lane mode only). An escape is a `merge.outcome` with outcome
   `qa-failed` on a pull request whose landed `merge.land` says
   `data.via=lane` with a merge sha, and that no `lane.escape` names as its
   subject.
4. **Handling one.** The escaped merge commit is reverted against its first
   parent in a throwaway worktree under the git directory, from the base,
   committed and pushed to `revert/lane-escape-pr-<N>`. The worktree is
   removed whatever happened. One pull request is opened from that branch,
   and one notice filed: a forge issue assigned to the lane policy's
   operator. Both bodies open with the escape's tokens: the outcome, the
   escaped pull request, the merge sha, its review areas, and in the
   notice the revert pull request. Then one `lane.escape outcome=revert` is
   recorded, the revert pull request in `related`, and the run prints
   `lane: escape pr:#<N> revert pr:#<M>` and goes on judging the pull
   request it was given (runtime/R94, R97).
5. **A failure records nothing and holds.** The recorder, the revert, the
   push, the pull request or the notice failing records no `lane.escape`,
   names the cause on standard error and holds the judged pull request with
   `escape`, exit 4 (runtime/R98). The next run tries again. It takes a
   revert pull request or branch an earlier run left, so one escape never
   gets two reverts.
6. **The revert is held.** A pull request a `lane.escape` names in
   `related`, or whose ticket one names, is held with `escape`
   (runtime/R99). The order is ADR-0047 clause 4's: `escape` sits third,
   after `drift`.
7. **The demotion is not lane state.** The escaped areas lose their low risk
   through the risk rule's earned record, which now holds a missed mistake
   (ADR-0045, ADR-0047 clause 6). The lane keeps no list of its own.

### Consequences

- Good: an escape reaches the operator once, as a notice and a revert they
  decide on, and until it does every lane run holds.
- Good: no new reader. `show` takes a kind, and the lane's reads stay the
  trace's own.
- Bad: every lane run past `drift` runs the outcome recorder, which reads
  git over the trace's landings. Its cost grows with the trace.
- Neutral: until #918 lands, a revert that does not apply holds every lane
  run with `escape`, and a `reverted` or `fixed` escape is left unhandled.

## Confirmation

`tests/trace.test.sh` section 22 holds the kind's row and its refusals, and
`show --kind` with no subject. `tests/land.test.sh` section 25 handles a
fixture escape and a second run that does nothing. It also covers each
failing forge call, the held revert and the order against `drift` and
`path`. Section 15 holds the landing script's reads to this record.
