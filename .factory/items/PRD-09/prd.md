---
id: PRD-09
type: prd
title: The risk rule, report-only, and its kill switch
parent: D-02
stage: review
created: 2026-10-28
updated: 2026-10-28
stages:
  - {stage: draft, at: 2026-10-28T12:26Z}
  - {stage: review, at: 2026-10-28T12:50Z}
---

# PRD-09 · The risk rule, report-only, and its kill switch

## 1. Objective

Have the planner stamp each ticket `Risk: low` or `Risk: high <reason>`, have a **risk rule** judge
each pull request's risk from its review areas' earned records and its unspecified outward items,
report the higher of the two on every `/pr-iterate` run without acting on it, record every
planner–rule disagreement for `/retro`, and give the operator a kill switch that stops the rule
from calling any PR low.

**Problem.** D-02 plans to let a low-risk PR land without the operator (K5), and to define low
risk by what the kit has learned, not by path (decision Q1): a change is high risk when its review
areas have not earned their record (Q3), or when its mistake would never show up as a countable
outcome. Three pieces exist and nothing joins them. K1 (PRD-06, ADR-0036) prints each review
area's earned record but compares no number to a threshold. K4 (PRD-07, ADR-0037, ADR-0038) fixed
the `Risk:` and `Risk-confidence:` stamps and the reserved reasons `unlearned` and `outward`, and
counts each review's outward items in `review.verdict data.outward`, but no skill stamps `Risk:`
and nothing writes the reserved reasons. K2 (PRD-08) puts the Q3 thresholds in a policy file read
from the base branch. Before K5 lets any verdict decide a landing, the operator needs to see,
over real PRs, what the rule would have said and how often it disagreed with the planner. And
once the lane exists, the operator needs one act that stops it from calling anything low.

**Solution.**
- `/to-tickets` stamps `Risk:` and `Risk-confidence:` on every ticket, checked by the vocabulary
  checker, and shows them at the quiz for the operator to override.
- A new shared-layer script, the risk rule, takes a PR's base and head, its number and its
  ticket. It reads the planner's stamp, the earned record of every review area the diff touches,
  the Q3 thresholds and the kill switch, and the Axis-2 verdict at the PR's head. It prints the
  **effective risk**, the higher of the planner's risk and its own, as closed tokens only, and
  records one `risk.judge` trace event.
- `/pr-iterate` runs the rule each iteration and puts the effective risk at the top of its
  report, marked as reported only. Nothing in the chain acts on it: K5 does that.
- `/retro`'s stamp-calibration question counts the disagreements.
- The kill switch is two things, either of which trips it: a value in the base branch's policy,
  and a marker file outside version control that anyone may create in the clone. While it is
  tripped, the rule calls no PR low.

**The test of done.** In a fixture repository whose trace gives `security` a missed mistake, a PR
that touches `scripts/` for a ticket stamped `Risk: low` makes the rule print `effective: high
unlearned`, `planner: low` and `rule: high unlearned`, and record `risk.judge outcome=disagreed`.
A second run at the same head writes nothing. `/pr-iterate`'s report opens with the effective
line and takes the same actions it takes for a low PR. Creating the trip marker makes a PR whose
areas are all earned print `rule: high unlearned` and `switch: tripped`.

## 2. Users and scenarios

**U1 — the operator**, who reads each PR's effective risk before trusting a landing, trips the
switch, and later (K5) lets low-risk PRs land without a merge click. **U2 — the planner**:
`/to-tickets`, or the software factory stamping a ticket the kit builds. **U3 — `/pr-iterate`**,
which runs the rule. **U4 — `/retro`**, which counts what the rule and the planner disagreed on.
**U5 — K5's lane**, which will read the effective risk this PRD defines.

Stories:

1. As the operator, I want each PR's effective risk shown on every `/pr-iterate` run, with the
   review areas that made it high, so that I can see what the lane would do before it exists.
2. As the operator, I want the rule's high to win over a planner's low, and the planner's high to
   win over the rule's low, so that neither side can lower a risk the other raised.
3. As the operator, I want each disagreement between the planner and the rule recorded, so that
   `/retro` can tell me whether the planner's stamps or the record is the weaker signal.
4. As the operator, I want one act that stops the rule from calling any PR low, and that no PR can
   undo, so that I can halt the lane at once when I stop trusting it.
5. As the planner, I want to stamp the risk I see in the spec, and have the quiz show it, so that
   a change the record cannot judge (a shared-layer file, a secret) is high from the start.
6. As the author of K5, I want the effective risk in a fixed, checked form, so that the lane reads
   the verdict and never recomputes it.

**UC1 — The rule reports a PR's risk.** Actor: `/pr-iterate`, on PR #910 for ticket #905. The
ticket is stamped `Risk: low`, `Risk-confidence: medium`. The PR changes `scripts/foo.sh` and
`tests/foo.test.sh`. Goal: the PR's effective risk, reported and recorded.
1. `/pr-iterate` finishes the iteration's fixes and runs the rule with the base branch, the PR's
   head, `--pr 910` and the ticket body it already holds.
2. The rule reads the ticket's `Risk:` line through the stamp reader: `low`.
3. It asks the lens-slice policy which review areas the two paths belong to: `security`,
   `api-crud`, `pattern`, `simplicity`, `reuse-dry` and `test-hygiene`.
4. It reads those six areas' earned records and the Q3 thresholds. Five show `landings 20 of 20`,
   `missed 0 of 20` and precision of 0.80 or more, so they are earned. `security` shows `missed 1
   of 20`, so it is unlearned.
5. It reads the Axis-2 `review.verdict` at the PR's head: `data.outward=0`.
6. It prints `effective: high unlearned`, `planner: low`, `rule: high unlearned`, six `area:`
   lines (`area: security unlearned` and five `earned`) and `switch: on`. It exits 0.
7. It records `risk.judge outcome=disagreed subject=pr:#910 related=ticket:#905` with the head
   commit, both risks, the effective risk, the unlearned areas and the switch state.
8. `/pr-iterate` puts `Risk: high unlearned (reported only)` at the top of its report, and does
   everything else as it would for a low PR.

Extensions:
- 1a. No ticket is known for the PR. The planner's risk reads `high unclear`, and `planner:`
  says so.
- 2a. The ticket carries no `Risk:` line, or the stamp reader refuses it. The planner's risk reads
  `high unclear` (ADR-0037 clause 3). Nothing is written into the ticket.
- 3a. A changed path belongs to no review area. The rule's risk is `high unlearned`, and the path
  counts as one unlearned area named `none`.
- 4a. The thresholds cannot be read (K2's failing-closed contract). Every area is unlearned.
- 4b. The trace is unconfigured, or holds a `SCHEMA` the reader cannot judge. Every area is
  unlearned, the rule says why on standard error, prints its lines, records nothing, and exits 0.
- 7a. `/pr-iterate` runs again at the same head and nothing has changed. The rule prints the same
  lines and records nothing.
- 7b. The ticket was stamped `Risk: high security` and every area is earned. The rule says `low`,
  the effective risk is `high security`, and the event is `disagreed`: the planner raised it.

**UC2 — An outward item makes the PR high.** Actor: `/pr-iterate`, on PR #912. Its last review
marked a new exit code `scope: outward`, so the Axis-2 verdict at the head carries
`data.outward=1`. Every area is earned and the ticket says `Risk: low`. Goal: the PR reads high
because something outside it relies on an unspecified change (Q6).
1. The rule reads `data.outward=1` from the Axis-2 verdict at the head.
2. It prints `rule: high outward` and `effective: high outward`, and records `disagreed`.

Extensions:
- 1a. The trace holds no Axis-2 verdict at this head: the review has not run, or ran on an older
  commit. The rule cannot tell whether an outward item exists, so its risk is `high unclear`,
  unless another reason already makes it high.
- 2a. Areas are unlearned too. `outward` is the reason printed (the order is `outward`,
  `unlearned`, `unclear`), and the unlearned areas still get their `area:` lines.

**UC3 — The planner stamps risk, and the operator overrides it.** Actor: `/to-tickets`, drafting
four tickets from a PRD. Goal: each ticket carries a checked risk stamp the operator has seen.
1. For each ticket it writes a `Risk:` line and a `Risk-confidence:` line. A ticket that moves a
   file the shared-layer manifest lists gets `Risk: high shared-layer`. One that only renames a
   test helper gets `Risk: low`.
2. Before the quiz it checks every line with the vocabulary checker as the planner.
3. The quiz shows each ticket's risk and its confidence beside its tier. The operator changes
   ticket 3 from `low` to `high irreversible`.
4. Each `ticket.write` event records the proposed risk, the published risk and the confidence.

Extensions:
- 1a. The draft writes `Risk: high unlearned`. The checker refuses it (a reserved reason), and the
  draft is repaired and checked again, never shown refused.
- 1b. The planner cannot tell. It stamps `Risk: high unclear`.

**UC4 — The operator trips the kill switch, and resets it.** Actor: the operator, after a landed
PR in an earned area turned out wrong. Goal: from now on, no PR reads low until they say so.
1. The operator creates the trip marker in the clone's git directory, outside version control.
2. The next rule run on any PR prints `switch: tripped`, and `rule: high unlearned` where the rule
   would have said low. Its event carries `data.switch=tripped`.
3. Days later the operator deletes the marker. The next run prints `switch: on` again.

Extensions:
- 1a. The operator wants the switch tripped in every clone and in CI. They set the switch value in
  the policy file and land that change on the base branch. Every run reads the base branch's
  value, so it holds wherever the rule runs.
- 2a. A PR edits the policy file in its own tree to reset the switch. The rule reads the base
  branch's value, never the PR's tree, so the PR still reads tripped.
- 2b. The switch value cannot be read. It reads tripped.

**UC5 — `/retro` counts the disagreements.** Actor: the operator, running `/retro` for a wave of
12 PRs. Goal: know whether the planner or the record raised risk more often, and where.
1. Question 8 reads the `risk.judge` events in the window, the latest per PR.
2. It prints `agreed 7`, `disagreed 4: rule raised 3 (unlearned 2: security 2; outward 1),
   planner raised 1 (security 1)`, and `tripped 1, left out`.
3. It prints the risk overrides at the quiz per `Risk-confidence`, as it does for tiers.

Extensions:
- 2a. The window holds fewer events than question 8's existing minimum. The row says so instead
  of a rate.

## 3. Model

- **Planner's risk**: the ticket's `Risk:` stamp, read through the stamp reader. A missing line, a
  refused one, or no ticket at all reads `high unclear` (ADR-0037 clause 3).
- **Earned** (a review area, decision Q3): the area's earned record (ADR-0036) shows a full window
  of landings, a missed-mistake rate below the policy's limit, and a precision at or above the
  policy's floor. As D-02 set them: 20 landings, fewer than 1 in 20 missed, precision at least
  0.80. Precision `n/a` is not earned. Any other area is **unlearned**. One escaped mistake in the
  window makes it unlearned at once, because it counts as missed.
- **Rule's risk**: `high outward` when the Axis-2 verdict at the PR's head counted one or more
  outward items (Q6, ADR-0038); else `high unlearned` when any review area the diff touches is
  unlearned, or a changed path belongs to none; else `high unclear` when the trace holds no Axis-2
  verdict at the head; else `low`. While the kill switch is tripped, a rule's `low` becomes `high
  unlearned`.
- **Effective risk**: the higher of the two, `high` above `low`. When the rule says high, its
  reason is printed; otherwise the planner's is. A **disagreement** is a planner level that
  differs from the rule level. Two highs with different reasons agree.
- **Kill switch**: tripped when the base branch's policy says so, when that value cannot be read,
  or when the trip marker exists in the clone's git directory. It is reset only by the operator,
  through the base branch or by deleting the marker.
- **Report-only**: the rule's verdict is printed and recorded, and changes no exit code and no
  action of any skill or script. K5 is the first reader that acts on it.

## 4. Rules

Area: runtime

Deltas against `docs/specs/runtime.md`, which ends at R51. PRD-08 is written in parallel and may
take ids too; whichever is approved second renumbers (§9).

### ADDED

runtime/R52. The trace SHALL accept the kind `risk.judge` with the outcomes `agreed` and `disagreed`, and SHALL refuse any other outcome on it, exit 2, writing nothing. [UC1 7]
runtime/R53. WHEN the risk rule runs with a base, a head and a PR number, it SHALL print on standard output, in this order and nothing else, `effective: <risk>`, `planner: <risk>`, `rule: <risk>`, one `area: <review area> earned|unlearned` line per review area the diff touches, and `switch: on|tripped`, and exit 0. [UC1 6]
runtime/R54. The risk rule SHALL read the planner's risk only from a ticket's `Risk:` line, lifted by the stamp reader from a ticket number or a ticket body file, and SHALL read it as `high unclear` when no ticket is given, the ticket carries no `Risk:` line, or the stamp reader refuses it. [UC1 2, 1a, 2a]
runtime/R55. The risk rule SHALL judge a review area earned only when its earned record shows the policy's full window of landings, a missed-mistake rate below the policy's limit, and a precision at or above the policy's floor, and SHALL judge it unlearned when its precision is `n/a`. [UC1 4]
runtime/R56. IF any review area the diff touches is unlearned, or a changed path belongs to no review area, THEN the rule's risk SHALL be `high unlearned` unless `outward` applies, and a path in no area SHALL print as `area: none unlearned`. [UC1 4, 3a]
runtime/R57. IF the thresholds cannot be read under the base-branch policy contract, THEN the risk rule SHALL judge every review area unlearned. [UC1 4a]
runtime/R58. IF the trace is unconfigured or holds a `SCHEMA` the reader cannot judge, THEN the risk rule SHALL judge every review area unlearned, name the cause on standard error, print its lines, record nothing, and exit 0. [UC1 4b]
runtime/R59. WHEN the Axis-2 `review.verdict` at the PR's head commit carries `data.outward` of 1 or more, the rule's risk SHALL be `high outward`. [UC2 1, 2]
runtime/R60. IF the trace holds no Axis-2 `review.verdict` at the PR's head commit, THEN the rule's risk SHALL be `high unclear` unless `outward` or `unlearned` applies. [UC2 1a, 2a]
runtime/R61. The effective risk SHALL be `high` when either the planner's or the rule's risk is `high`, carrying the rule's reason when the rule's risk is high and the planner's otherwise, and `low` only when both are `low`. [UC1 6, 7b]
runtime/R62. The risk rule SHALL check every `Risk` value it prints with the vocabulary checker, declaring itself the risk rule, and SHALL print nothing and exit 2 if the checker refuses one.
runtime/R63. WHEN the risk rule judges a PR, it SHALL record one `risk.judge` event with subject `pr:#<N>`, the ticket in `related` when there is one, outcome `disagreed` when the planner's level differs from the rule's and `agreed` otherwise, and in `data` the head commit, the planner's, rule's and effective risks, the unlearned areas and the switch state. [UC1 7, 7b]
runtime/R64. IF the trace already holds a `risk.judge` for the same PR and head commit with the same risks and switch state, THEN the risk rule SHALL record nothing. [UC1 7a]
runtime/R65. WHILE the kill switch is tripped, the risk rule SHALL replace a rule's risk of `low` with `high unlearned`, print `switch: tripped`, and record `data.switch=tripped`. [UC4 2]
runtime/R66. The kill switch SHALL read tripped when the base branch's policy sets it so, when that value cannot be read, or when the trip marker exists in the clone's git directory, and on otherwise. [UC4 1, 3, 1a, 2b]
runtime/R67. The risk rule SHALL read the thresholds and the switch value only through the base-branch policy contract, never from the environment or the PR's own tree. [UC4 2a]
runtime/R68. The risk rule SHALL exit 0 whatever risk it prints, and SHALL write nothing but its `risk.judge` event. [UC1 8]
runtime/R69. The risk rule SHALL print and record only risk tokens, review area names from the lens-slice policy, `none`, the switch words, digits and commit shas, and no text from a ticket body, a PR body or a commit message.

Area: process

Deltas against `docs/specs/process.md`, which ends at R60.

### ADDED

process/R61. `/to-tickets` SHALL stamp every ticket with one `Risk:` line and one `Risk-confidence:` line, check both with the vocabulary checker as the planner before the quiz, and repair and recheck a refused line before it is shown. [UC3 1, 2, 1a]
process/R62. `/to-tickets` SHALL state which change each planner reason covers (`irreversible`: cannot be undone by a revert; `security`: auth, secrets or the trust boundary; `invisible`: a mistake no post-merge outcome would count; `shared-layer`: a file the shared-layer manifest lists, a contract file, or a policy, guard or gate file; `unclear`: the planner cannot tell), and SHALL stamp `low` only when none applies. [UC3 1, 1b]
process/R63. `/to-tickets` SHALL show each ticket's `Risk:` and `Risk-confidence:` at the quiz, and SHALL record on each `ticket.write` event the proposed risk, the published risk and the risk confidence. [UC3 3, 4]
process/R64. WHEN `/pr-iterate` ends an iteration on a PR, it SHALL run the risk rule at the PR's head with the ticket it holds and print the effective risk at the top of its report, marked as reported only. [UC1 1, 8]
process/R65. `/pr-iterate` and the landing script SHALL take the same actions on a PR whatever the risk rule prints. [UC1 8]
process/R66. `/retro`'s question 8 SHALL count the latest `risk.judge` per PR in its window as agreed or disagreed, the disagreements split by which side raised the risk, by reason and by review area, and the risk overrides at the quiz per `Risk-confidence`. [UC5 1, 2, 3, 2a]
process/R67. `/retro`'s question 8 SHALL leave `risk.judge` events with `data.switch=tripped` out of its disagreement counts and print how many it left out. [UC5 2]

## 5. Slices (vertical, demoable, in order)

Slices 1 to 3 move the risk rule or the trace's kind table, both shared layer, so each is a
release ticket in its own frontier (ADR-0033), chained in this order. Slices 4 and 5 move skills
only and can run beside slice 2 once slice 1 lands. Slice 1 waits for the K2 slice that gives a
reader of base-branch policy.

**Slice 1 — the rule judges unlearned areas, reported by `/pr-iterate` (shared-layer release).**
The tracer bullet: one reason, end to end.
- *Covers:* runtime/R52, R53, R54, R55, R56, R57, R58, R61, R62, R63, R64, R68, R69, process/R64,
  process/R65.
- *Also:* the decision record that lets a chain skill run the rule (§8). The glossary gains risk
  rule, effective risk, earned and unlearned. Bump, `UPDATING.md`, re-captures, tag. Until slice 2
  lands, the rule reads no review verdict.
- *Accept:* a fixture repository and trace print UC1's lines and its `disagreed` event; a second
  run writes nothing; no ticket and a ticket with no `Risk:` line both print `planner: high
  unclear`; a path in no area prints `area: none unlearned`; unreadable thresholds and an
  unconfigured trace make every area unlearned and still exit 0. A skill-text suite holds
  `/pr-iterate`'s step and its reported-only words, and the landing script's suite lands a fixture
  PR the rule calls high.

**Slice 2 — outward and unreviewed heads (shared-layer release).**
- *Covers:* runtime/R59, R60.
- *Blocked by:* slice 1.
- *Accept:* a fixture verdict with `data.outward=1` prints `rule: high outward`; no verdict at the
  head prints `high unclear`; both with unlearned areas print the order `outward`, `unlearned`.

**Slice 3 — the kill switch (shared-layer release).**
- *Covers:* runtime/R65, R66, R67.
- *Blocked by:* slice 2.
- *Also:* the glossary gains kill switch; the decision record names the trip marker.
- *Accept:* the marker trips an all-earned fixture to `rule: high unlearned` and `switch:
  tripped`, and deleting it resets it; a tripped base-branch value with an untripped PR tree reads
  tripped; an unreadable value reads tripped; the environment cannot reset it.

**Slice 4 — the planner stamps risk.**
- *Covers:* process/R61, R62, R63.
- *Blocked by:* slice 1.
- *Accept:* `tests/spec-skills.test.sh` holds the stamp step, the reasons' meanings, the checker
  call before the quiz, the quiz line and the `ticket.write` fields.

**Slice 5 — `/retro` counts the disagreements.**
- *Covers:* process/R66, R67.
- *Blocked by:* slice 1.
- *Accept:* the retro suite's fixture trace prints UC5's counts, leaves the tripped event out and
  says how many.

## 6. Non-goals (this PRD)

- **Acting on the effective risk**: holding a PR, landing one without the operator, demoting an
  area and opening a revert. *Later*, K5. Its record supersedes shared invariant §7 for the lane.
- **The thresholds' home, names and base-branch reading.** K2 (PRD-08). This PRD only reads them
  through K2's contract.
- **The rule detecting `shared-layer` or `security` from paths.** *Later*. The D-08 contract gives
  the rule `unlearned` and `outward` only. Reopen if `/retro` shows planner stamps missing a
  shared-layer change (§9).
- **A reason token of its own for a tripped switch.** *Later*, see §9. Adding one changes the
  ticket contract the factory reads (ADR-0037).
- **Writing the effective risk into the PR body.** *Later*, K5, when the lane needs it where the
  forge shows it.
- **Stopping an agent from deleting the trip marker.** *Later*, K5: in report-only, a deleted
  marker lowers no landing. The adapter's root guard is the likely home.
- **The rule reading a factory ticket by its id.** *Later*, K7 after IN-01. Until then a factory
  ticket reaches the rule as a ticket body file.
- **Storing the verdict or the earned record.** *Never*. Both are computed on each run (ADR-0036
  clause 4); the event records what was said, not a cache to read back.
- **Area × tier as the change kind; a learned model of risk.** *Later* (operator, 2026-10-23).

## 7. Technical constraints and testing

- POSIX `sh` and `git` only. The rule is a shared-layer script beside the vocabulary checker and
  the stamp reader, and ships to consumers: `/to-tickets` and `/pr-iterate` ship, and a consumer
  with no factory gets the same chain (D-02, 2026-10-23).
- **Trust boundary.** Ticket and PR bodies are untrusted. The planner's risk reaches the rule only
  through the stamp reader and the vocabulary checker. The rule reads the trace through its own
  readers, never a transcript. What reaches `/pr-iterate` is closed tokens, area names and digits
  (R69), so a session is handed no prose derived from the trace.
- **Failing closed everywhere**: no ticket, no stamp, no thresholds, no trace, no verdict at the
  head, an unreadable switch, a path in no area. Each makes the PR high, never low.
- **Tests** build a throwaway git repository with scripted landings and a fixture trace holding
  `merge.land`, `merge.outcome`, findings and `review.verdict` events, as PRD-06's suites do, plus
  a fixture base-branch policy file. Every new outcome word joins the trace suite's row-for-row
  table check (ADR-0024 clause 1).
- **Numbers**: the thresholds are K2's policy values (as set, 20 landings, fewer than 1 in 20
  missed, precision 0.80); idempotence is "a second run at the same head writes 0 lines" (R64).
  The rule's running time is measured in slice 1 over the kit's own trace and recorded in the
  diary as a baseline. It is not promised here.

## 8. Decisions recorded for this PRD

**From D-02** (decisions.md, 2026-10-23): Q1 (high risk is not yet learned, or cannot be learned
from), Q3 (earned on misses and noise, thresholds as policy), Q4 (a change kind is a review area;
a diff is judged by its riskiest area), Q6 (an outward item makes the PR high), Q7 (K3 third,
after K1 and K2), the `Risk:` contract settled with D-08 and its two amendments (the rule alone
writes `unlearned` and `outward`; the higher of the two risks holds; each disagreement is an event
`/retro` counts), and Q5's line that the kill switch stays the operator's manual stop.

**Already fixed, not reopened:** ADR-0037 (the `Risk:` grammar, the reserved reasons written
only with the risk-rule writer flag, a missing line read as `high unclear` and never written in),
ADR-0038 (scope, outward by default, `data.outward`), ADR-0036 (the earned record's definition).
The factory's PRD-15 relies on ADR-0037 as it stands.

**Derived while writing** (the session, under the operator's standing delegation of rulings; the
maintainer confirms them at approval):

- **A chain skill may run the rule, which reads the trace: a new record amends ADR-0024 clauses 7
  and 9.** Clause 7 says the chain never reads the trace, and clause 9 that it is not a memory.
  `/pr-iterate` running the rule breaks both as written. ADR-0024 is at its amendment cap
  (ADR-0021), so slice 1 writes one new record, as ADR-0036 did: the risk rule is the one route by
  which a chain skill sees anything derived from the trace; it hands over only closed tokens,
  area names and digits; and the session gets no transcript or prose. PRD-06 §8 said K3 must
  supersede these clauses; amending them for one named reader is the narrower reading, and the
  clauses stay binding for everything else.
- **The rule runs in `/pr-iterate`, once per iteration.** That is where the review's outward
  count and the fixed head both exist. The landing script, an operator tool, prints nothing new
  here: K5 makes it the reader that acts.
- **The rule records its own event**, as the review broker records the verdict it posts, so the
  skill does not assemble trace fields. One event per PR and head, so `/retro` reads the latest
  per PR.
- **Reason order: `outward`, then `unlearned`, then `unclear`.** Only one reason fits on a `Risk:`
  line (ADR-0037 clause 1). `outward` names this PR's own unresolved item, and the operator can
  act on it; `unlearned` is the area's standing state; `unclear` is the absence of a review.
- **On high from both sides, the rule's reason prints.** Its reasons are measured; the planner's is
  kept in `planner:` and in the event.
- **No verdict at the head reads `high unclear`, not `low`.** The rule cannot rule out an outward
  item it has not seen. The rule may write `unclear` because its writer flag admits every reason.
- **A path in no review area is unlearned.** The lens-slice policy can leave a path unselected by
  every rule; no record covers it, so nothing earned it.
- **Overlapping lens-slice rules need no merge for the rule** (PRD-06 §9). A path in several
  areas with identical patterns has identical records and so identical verdicts; the duplicate
  `area:` lines cost nothing. PRD-06's open question stays open for the record's display only.
- **The kill switch is two switches, either of which trips.** The base-branch policy value reaches
  every clone and CI, and its reset needs a merge, which is the operator's. The marker outside
  version control is the one-act stop on this machine, and no PR can delete it. Tripping is open
  to anyone, because it only makes PRs high; resetting is the operator's.
- **A tripped switch prints `high unlearned`** and says `switch: tripped`, rather than a new
  reason token, because the ticket contract's reason list is fixed (ADR-0037) and the factory reads
  it. The event's `data.switch` keeps tripped verdicts apart for `/retro` (R67).
- **The rule's interface**: a base and a head as git refs, `--pr <N>`, and `--ticket <N>` or
  `--ticket-file <path>`, mirroring the skill dispatcher's ticket arguments. Exit 0 for any
  verdict, 2 for a caller error. Expensive to reverse once K5 and the factory call it.

**Alternatives considered:**

- **The rule as an operator-run tool only, like the record reader.** It keeps ADR-0024 intact, but
  the effective risk would never appear on a PR without the operator's act, and K5's lane needs a
  chain-side verdict. Rejected.
- **The rule writes its verdict as a `Risk:` line into the ticket or PR body.** A line the planner
  never wrote must not look as if it did (ADR-0037 option 4), and a body is untrusted on the next
  read. Rejected; the event and the printed lines are the record.
- **A kill switch in the environment.** Any process, an agent included, could set or clear it,
  and it would not reach CI. Rejected.

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

- **What this PRD needs from K2 (PRD-08), written in parallel.**
  - Problem: the rule reads the Q3 thresholds and the switch value "through the base-branch policy
    contract", and K2 defines that contract. Four things are needed from it: which policy file
    holds the thresholds and the switch; their names; whether the record's window of 20 (fixed in
    the record reader, runtime/R44) becomes a policy value the reader also reads; and the exact
    form of "fails closed" a reader sees (an exit code, or a value).
  - Options seen: K2 names them all; or K3's slice 1 adds the switch and K2 holds only the
    thresholds.
  - Next step: read PRD-08 once it is written and align R55, R57, R66 and R67 to its words before
    either PRD is approved. MVP default: the thresholds and the switch in the same base-branch
    policy file, the window staying the record reader's 20.
- **Requirement ids may clash with PRD-08.**
  - Problem: both PRDs add requirements to the living specs at the same time.
  - Options seen: PRD-08 takes runtime ids and this PRD renumbers; or the second approved
    renumbers.
  - Next step: the maintainer checks both at approval. MVP default: whichever is approved second
    renumbers.
- **Do landings still inside the fix window count toward an area's 20?**
  - Problem: today every review area shows 20 of 20 landings, all inside the 30-day fix window,
    `missed 0` and precision from 0.89 to 0.95, all from triage labels. Under Q3 as written, all
    six areas are earned on day one, before any landing has finished the window in which a fix
    would count it as a mistake.
  - Options seen: count them, as Q3 is written; require a policy number of settled landings
    outside the window; require a share of labels from outcomes or humans, not triage (PRD-06 §8
    left that share to K3).
  - Next step: question to agranado before K5's grill, with slice 1's first real report in hand.
    MVP default: count them, since a report changes no landing. It must be settled before K5.
- **Should the rule also raise `shared-layer` from paths?**
  - Problem: Q1 lists policy, guard and gate files and the shared layer as never learnable, but the
    D-08 contract gives that call to the planner alone. A planner who misses it leaves a low
    stamp that the record may well call earned.
  - Options seen: planner only, as agreed; the rule also raises from the shared-layer manifest and
    the K2 policy file list, which needs the factory told, since the rule would write a planner
    reason.
  - Next step: raise with the D-08 session and the operator at K5's grill. MVP default: planner
    only; `/retro`'s disagreement counts show whether planners miss it.
- **A dedicated reason for a tripped switch.**
  - Problem: a tripped switch prints `high unlearned`, which reads as a fact about the areas.
  - Options seen: keep `unlearned` with `switch: tripped` beside it; add a reserved reason such as
    `halted` to the contract, a shared-layer change the factory must take.
  - Next step: decide at K5's grill, where the lane reads it. MVP default: `unlearned`.

## 10. Dogfood plan

Five tickets in slice order. After slice 1 lands, every `/pr-iterate` run on the kit's own PRs
prints an effective risk, and each wave's `/retro` after slice 5 shows how often the planner and
the record disagreed. With K1's backfill, the first report already judges every review area, so
the first wave is where D-02's H1 is first read from the rule rather than the raw record. The
operator trips the switch once on purpose after slice 3, to see every PR read high, and resets
it. K5 opens the lane only after these reports.
