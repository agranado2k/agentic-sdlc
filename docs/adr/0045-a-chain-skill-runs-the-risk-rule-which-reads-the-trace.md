# ADR-0045: A chain skill runs the risk rule, the one route by which it sees anything derived from the trace

- **Status**: Accepted
- **Date**: 2026-11-01
- **Deciders**: the planner session for #905 (PRD-09 slice 1), under the operator's delegation of rulings; the rule is PRD-09 §8's, approved by the operator on 2026-10-29 and settled in the D-02 grill of 2026-10-31; the merge of this record's pull request is the operator's yes
- **Supersedes / amends**: amends ADR-0024 clause 1, which gains the kind `risk.judge`, and clauses 7 and 9, for one named reader; recorded as a new record because ADR-0024 takes no further in-place amendment (ADR-0021 clause 5), as ADR-0036 did
- **Superseded by**: —

## Context and problem statement

D-02 plans a lane that lets a low-risk pull request land without the
operator, and defines low risk by what the kit has learned rather than by
path: a review area is earned when its record shows a full window of
landings, few missed mistakes and lens findings that hold up (decision Q3),
and a change in an area that has not earned it is high risk. ADR-0036 gave
the trace that record, and an operator-run reader that prints it. ADR-0039
gave the two thresholds a home read from the base branch. ADR-0037 fixed the
`Risk:` stamp and reserved two reasons, `unlearned` and `outward`, for a
writer that did not exist yet.

Nothing joined them. Before the lane lets any verdict decide a landing, the
operator needs to see, on every pull request, what the rule would have said,
and how often it disagreed with the planner's stamp. The place that holds a
pull request's head and its review is `/pr-iterate`, a chain skill. ADR-0024
clause 7 says the chain never reads the trace, and clause 9 that the trace is
not a memory. A skill that prints a verdict computed from the trace breaks
both as written.

## Decision drivers

1. A pull request's risk is visible on the pull request's own loop, without
   an operator's act, so that the later lane has a reported history to be
   judged by.
2. No prose derived from the trace reaches a session: the trust boundary and
   clause 9's reason (a later session is fed nothing an earlier one decided)
   both hold.
3. Every unknown fails closed, toward high.
4. One reader writes the reserved reasons, and records what it said.

## Considered options

1. **The rule as an operator-run tool only**, like the record reader. Clause
   7 stays whole, but no pull request shows its risk without the operator's
   act, and the lane needs a chain-side verdict. Rejected.
2. **The rule writes a `Risk:` line into the ticket or the pull request
   body.** A line the planner never wrote must not look as if it did
   (ADR-0037 option 4), and a body is untrusted on its next read. Rejected.
3. **Supersede clauses 7 and 9.** Wider than the need: every other skill
   keeps its reason not to read the trace. Rejected.
4. **Amend clauses 7 and 9 for one named reader, the risk rule**, which
   hands a chain skill closed tokens only. Chosen.

## Decision outcome

Chosen option 4.

1. **The risk rule is `scripts/risk.sh`, shared layer.** Given a base, a
   head, `--pr <N>` and the ticket (`--ticket <N>` or `T-<n>`,
   `--ticket-file <path>`), it prints, in this order and nothing else,
   `effective:`, `planner:`, `rule:`, one `area: <review area>
   earned|unlearned` line per review area the diff touches (`none` for a path
   in no area), and `switch: on|tripped`, and exits 0 whatever it says; 2 is
   a caller error. Each risk value is checked by the vocabulary checker as
   `--writer risk-rule`, and a refusal prints nothing.
2. **The planner's risk** is the ticket's `Risk:` line as the stamp reader
   lifts it, and `high unclear` with no ticket, no line, or any stamp-reader
   exit but 0 (ADR-0037 clause 3). A ticket body file reaches the stamp
   reader through a stand-in tracker, as the skill dispatcher reads one.
3. **Earned is read over settled landings.** An area is earned when the
   record reader's settled form, `trace.sh record --settled`, shows 20
   landings that landed before the fix window began, a miss rate below the
   risk policy's `miss-rate-below`, a precision at or above its
   `precision-floor`, and no missed mistake on a landing of the area still
   inside the fix window. Precision `n/a` is unlearned. The settled form
   prints digits and area names only, and refuses a trace whose `SCHEMA` it
   cannot judge, exit 3.
4. **Failing closed.** Thresholds the policy reader cannot give (any exit but
   0), an unconfigured trace, an unjudgeable `SCHEMA`, or a record reader
   that fails make every area unlearned; the cause goes to standard error and
   the exit stays 0. An unconfigured or unjudgeable trace records nothing.
5. **The verdict.** Any unlearned area makes the rule's risk `high
   unlearned`, else `low`. The effective risk is the higher of the planner's
   and the rule's; on high it carries the rule's reason when the rule says
   high, the planner's otherwise. A disagreement is two different levels.
6. **The event.** The rule records one `risk.judge`, outcome `agreed` or
   `disagreed`, subject `pr:#<N>`, the ticket in `related`, and in data the
   head (`data.head`, a commit sha), `data.planner`, `data.rule`,
   `data.effective`, `data.unlearned` and `data.switch` (`on` or
   `tripped`). It records nothing when the trace already holds one for the
   same PR and head with the same risks and switch. ADR-0024 clause 1's kind
   table gains the row `risk.judge` = `agreed` | `disagreed`, its outcome
   required.
7. **Clause 7, amended:** the risk rule is the one route by which a chain
   skill sees anything derived from the trace. `/pr-iterate` runs it at the
   end of each iteration and puts its effective line at the top of its report,
   marked reported only. What crosses is closed tokens, review area names,
   `none`, switch words, digits and commit shas — never text from a ticket,
   a pull request body, a commit message or a transcript. No chain skill
   calls `show`, `summary`, `export` or `record` itself; the rule does, as a
   script. Clause 7 stays binding for everything else.
8. **Clause 9, amended:** the rule's event is what was said, not a cache:
   the verdict and the earned record are computed on each run (ADR-0036
   clause 4), and nothing reads the event back but the rule's own
   same-verdict check and `/retro`. Clause 9 stays binding for everything
   else.
9. **Report-only.** Nothing in the chain acts on the verdict: `/pr-iterate`
   and the landing script take the same actions whatever it prints. The lane
   that acts on it is a later record's (D-02's K5), and that record, not this
   one, touches shared invariant §7.
10. **Not in this slice, and named so a reader does not assume them.** The
    Axis-2 `outward` count and the `high unclear` of an unreviewed head
    (PRD-09 slice 2), and the kill switch's trip (slice 3) — until then the
    switch reads `on`. The review areas are read from the lens-slice policy
    as the record reader reads them, from the tree the rule runs in; a pull
    request that edits that policy is a judging-file change the policy
    reader's `touched` names, and the later lane holds it by path.

### Consequences

- Good: every pull request's loop shows its risk and the areas that made it
  high, and `/retro` gets one event per PR and head to count disagreements
  from.
- Good: the reserved reasons have their one writer, and every unknown reads
  high.
- Bad: a chain skill now depends on the trace being configured to say
  anything but `high`; an unconfigured consumer sees every pull request read
  `high unlearned`, which is the honest answer and also a noisy one.
- Bad: no area earns until about 30 days after its 20th landing, because
  only settled landings count. That costs nothing while the lane is closed.

## Confirmation

`tests/risk.test.sh` builds a fixture repository and trace and holds every
clause above: UC1's lines and its `disagreed` event, the second run that
writes nothing, the planner's `high unclear` cases, the settled window and
the in-window miss, precision `n/a` and below the floor, `area: none
unlearned`, the failing-closed paths, the checker's refusal, caller errors,
`/pr-iterate`'s step and its reported-only words, and the landing script
reading nothing of the rule. `tests/trace.test.sh` holds the kind's row and
its refusals; `tests/land.test.sh` lands a pull request the rule calls high.
