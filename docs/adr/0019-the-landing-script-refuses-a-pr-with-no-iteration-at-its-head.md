# ADR-0019: The landing script refuses a PR with no iteration at its head

- **Status**: Accepted
- **Date**: 2026-10-08
- **Deciders**: the implementer session for #630, on the operator's standing delegation of rulings (2026-10-08); the merge of its pull request is the operator's yes
- **Supersedes / amends**: ADR-0008 clause 7, in one respect — it names one more operator-run reader of the trace (clause 1 below)
- **Superseded by**: — (amended 2026-10-10 for #673: the same check, the same way, for a `review.verdict` at the head, overridden by `--no-review '<reason>'`; see the amendment below)

## Context and problem statement

`/pr-iterate` is the loop that drives an open PR to green, and it records one
`pr.iterate` event per iteration. Retro `retro-20261007T180238Z` found #625 and
#626 landed with no `pr.iterate` at their head commit, and #615 landed seven
minutes after an iteration that saw no checks. The landing script
(`scripts/land.kit.sh`) checked the forge — green, mergeable, clean — and never
asked whether the loop had looked at the commit it was about to merge.

The only record of an iteration is the trace. ADR-0008 clause 7 keeps every
chain skill from reading it, and names the operator and `/retro` as its readers;
the landing script is neither a skill nor `/retro`, so whether it may read the
trace has to be decided.

## Decision drivers

- A landing nobody iterated on is the gap the retro found; the check has to sit
  where the merge happens.
- The operator delegates rulings and wants no stops, so an exception must be
  one flag, not a conversation.
- An unconfigured trace is a working state (ADR-0008 clause 2) and must not
  stop a landing.
- No skill gains a read of the trace (ADR-0008 clause 7, held by
  `tests/trace-skills.test.sh`).

## Considered options

1. **Refuse by default, override with a named reason that is recorded** *(chosen)*
2. **Land by default and record `data.iterated=no`** — rejected: a record the
   retro reads a week later did not stop #625 and #626; the refusal is the check.
3. **Read the iteration from the forge** — rejected: `/pr-iterate` leaves no
   forge mark of its own per iteration, and adding one changes a shared-layer
   skill for a kit-only check.
4. **Have `pr.iterate` carry the head sha and match it exactly** — rejected for
   now: it changes the shared-layer skill and the trace's shape (a release);
   the date comparison below needs neither.

## Decision outcome

1. **The landing script is an operator-run reader.** It runs by the operator's
   hand (shared invariant §7), so its read of the trace is the operator's read,
   the same standing clause 7 gives a diagnosis. It reads `show` only, for
   `pr.iterate` on the PR it lands; no skill gains a read.
2. **An iteration is at the head** when a `pr.iterate` on `pr:#<N>`, any
   outcome, is stamped at or after the head commit's committed date as the
   forge reports it — both ISO 8601 UTC, compared as strings. `/pr-iterate`
   emits after its own push, so its event follows the commit it pushed.
3. **With none, the script refuses**: exit 2, nothing merged, nothing recorded,
   stderr naming the head commit, `/pr-iterate`, and the override. A head the
   forge does not date is no iteration at it.
4. **The override is `--no-iteration '<reason>'`.** The landing goes ahead and
   `merge.land` records `data.iterated=no` and the reason as
   `data.no_iteration`. With an iteration at head, `data.iterated=yes`, and an
   unused override's reason is not recorded.
5. **Unconfigured, the check is skipped** and stderr says so: there is nothing
   to read, and nothing will be recorded either.

## Consequences

- **Good**: a landing the loop never looked at needs a reason someone typed,
  and the retro can count those reasons.
- **Bad / trade-off**: the trace becomes load-bearing for one operator command
  — a configured trace that lost its events refuses every landing until the
  override is used.
- **Honest limitation**: a commit's date is when it was committed, not pushed;
  an iteration between a commit and its later push counts as at its head.
  Option 4 closes that if it ever matters.

## More information

- Built by #630. `tests/land.test.sh` section 9 drives the refusal, the
  override and the unconfigured skip against a fixture trace.
- `/merge-train` records `merge.land` in the landing script's shape under #634.

## Amendment 2026-10-10 — a review verdict at the head (#673)

On 2026-10-09 PR #665's review degraded under a vendor's credit exhaustion and
posted with no `review.verdict`; the script checked for an iteration at its
head and not for a review, and landed it (retro `retro-20261009T112925Z`).
Decided by the implementer session for #673 on the operator's standing
delegation; the merge of its pull request is the operator's yes.

1. **Clause 1 reads one more kind.** The script reads `show` for
   `review.verdict` on the PR it lands, beside `pr.iterate`; still no skill
   gains a read.
2. **A review is at the head** when a `review.verdict` on `pr:#<N>`, **any
   axis and any outcome**, is stamped at or after the head commit's committed
   date — clause 2's comparison. `/pr-iterate` runs `/review-pr` each
   iteration, so a converged loop's last review follows the head. A `blocked`
   verdict counts: what the review found is the operator's read on the PR, and
   whether the checks are green is the gate's.
3. **With none, the script refuses** as clause 3 says, and one refusal names
   every check that failed — iteration, review or both — so one run teaches
   both overrides.
4. **The override is `--no-review '<reason>'`**, shaped like
   `--no-iteration`: `merge.land` records `data.reviewed=no` and the reason as
   `data.no_review`; with a verdict at head, `data.reviewed=yes`, and an
   unused reason is not recorded.
5. **A prose-only PR** — a diary stamp, a housekeeping row — that nobody
   iterated or reviewed is a documented path, not an exception: it lands on
   both overrides, each naming why (`--no-iteration 'prose-only: diary stamp'
   --no-review 'prose-only: diary stamp'`), and the retro can count them.
6. **Unconfigured**, both checks are skipped and stderr says so (clause 5).

`tests/land.test.sh` section 14 drives each branch; the train's `merge.land`
names neither `reviewed` nor `no_review`, the script's alone like the
iteration keys (section 10).
