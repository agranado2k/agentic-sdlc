# D-02 · Proposals (phase 4)

Criteria (research.md §4):
- the research's own: complexity, reversibility, cost per wave, fit with the binding decision
  records, and time to a first demonstrable slice;
- the operator's: **accuracy, with the human in the loop only for high risk**, and the order
  **measurement → guard safety → policy safety**.

## The operator's idea, in their words (2026-10-23)

> I vision a sdlc that will get a well written ticket that will have everything the agent needs to
> implement, specs, gaps, what should be the final result. And from there it should /implement ,
> /review-pr (fixing anything that doesn't match to the ticket spects, gaps, but also make decisions
> on some ambigous part and let the human knows what have been decided) and finally /merge-train
> the PR, unless something high risk can be flagged.

**Which schools it matches [inference]:**
- **A (spec-driven):** the ticket is the contract.
- **C (single writer, independent verifiers):** the review fixes against that contract.
- **S-6 and S-14's risk-gated escalation:** the human sees only high risk.

S-14 is the nearest precedent: it auto-approves below a configured risk score and always sends a
PR that edits policy to a human. S-40's autofix-until-green is the nearest precedent for a review
that fixes as well as reports. No source in the research lands a PR with no human act at all, so
that part has no precedent.

**Where it meets a binding rule.** Landing with no human act contradicts shared invariant §7 ("the
merge action is a human decision with a human's name on it") and hard rule 7. ADR-0016 already
lets the session rule and run the train *after the operator starts it*; this goes one step further.
The idea needs a new decision record that supersedes §7 for low-risk changes. The rule cannot be
edited in place (hard rule 5).

## The operator's second idea, in their words (2026-10-23)

> Also, I'd like that the kit learns with the mistakes so it can automatically fix that ( /retro )
> and learn the projects guidelines and the humnans preferences

**Which schools it matches [inference]:**
- **B (harness engineering):** each agent struggle becomes a repo rule (S-42), and lessons compound
  into checks and skills (S-1).
- **E (eval-driven improvement):** error analysis over traces into a failure taxonomy (S-25, S-7).
- **S-2:** mine recurring review comments into enforced invariants.
- **F (attention interface):** a harness that proposes its own improvements from real use (S-5,
  S-13). The attention policy is learned from the human's corrections (S-12).

**What the kit has today.** `/retro` already reads the trace and turns what recurs into candidate
tickets. This session ran that loop twice, and the second run caught a false finding on five PRs.

**What is missing:**
- **"Automatically":** the loop stops at a human publishing the tickets and starting the work.
- **"Human preferences":** the operator's rulings and overrides are not collected as data a retro
  learns from.

**Where it meets binding rules:**
- `/retro` never fixes, so the reading stays independent of the repair (ADR-0008 clause 7).
- What it learns must become a **rule with a failing check, never a lessons file** or memory (shared
  invariant §11; ADR-0005's and ADR-0008's "not a memory" non-goal).

Neither rule blocks the idea. Together they set its shape [inference]:
1. The retro proposes.
2. The proposal becomes a ticket.
3. The ticket's fix is a check, a policy value or a skill line, carrying a `Targets:` query.
4. The before-and-after section proves the fix worked, or reopens it.

"Automatic" means that whole cycle runs through the same lane as any other ticket. A preference is
learned when an operator ruling recurs: the retro proposes making it the default, as a policy value
or a skill line, and the operator's ruling on that proposal is the label (S-12).

**How each option takes it.**
- **Option 1** runs retro tickets through the autopilot like any ticket.
- **Option 2** adds the labels. Operator rulings and overrides are recorded as their own events,
  beside post-merge outcomes, so a preference can be counted.
- **Option 3** adds a stage ⑥, the closed loop. Retro candidates whose fix is low-risk flow through
  the low-risk lane, and a candidate that edits a lens or a skill must carry its `Targets:` line,
  which retro already requires. Recurring operator rulings become proposed defaults that the
  operator confirms once.

---

## Option 1 · Ticket as contract, autopilot below a risk line (the operator's)

**Objective.** A ticket complete enough to build from goes to landing with no human act, unless a
risk rule flags it.

**Users and the main scenario.** The operator writes or approves the ticket, then reads a short
decision log afterwards. The chain runs the rest:
1. `/implement` builds from the ticket.
2. `/review-pr` checks every acceptance criterion and fixes what misses it.
3. Where the ticket is ambiguous, the review decides, and records each decision on the PR.
4. A risk rule decides whether the PR waits for the human or the train lands it.

**What it changes:**
- A **ticket completeness gate**: specs, the gaps closed, and the final result as acceptance
  criteria, with `Covers:` ids.
- A **review that fixes**. Today `/pr-iterate` fixes and `/review-pr` only reports.
- A **decision log** on each PR.
- A **risk rule**: risky paths, the ticket's tier, an unspecified confirm-list item, and a change to a
  policy file.
- An **auto-started train**.
- A **new decision record** superseding §7 for the low-risk lane.

**Rough slices:**
1. The completeness gate on a ticket.
2. The decision log.
3. The risk rule, reporting only.
4. The review fixes against the ticket.
5. The auto-landing lane, behind the new decision record.

**Cost and risk.** Highest. It removes the last human act on a low-risk PR before anyone has
measured how accurate the automated verdicts are. That is the failure S-26 and S-7 warn of: judges
miss what "looks correct" but misses the goal.

**What it rules out.** The per-PR human click.

**Evidence.** S-2, S-6, S-14, S-40, S-41; against: S-7, S-26, S-35.

## Option 2 · Measure first: record what happened after landing (the smallest thing)

**Objective.** Every lens finding and every landed PR gets an outcome that a later retro can
score: precision per lens, from post-merge outcomes.

**Users and the main scenario.** The operator reads `/retro` and sees, for each lens, how often
its findings matched a later revert or fix. A lens below its floor is a candidate for a prompt
change.

**What it changes.**
- The trace records two outcomes: a **revert** of a landed merge, and a **post-merge fix** that
  touches a line a lens flagged (or a line the diff changed).
- `/retro` gains precision per lens against those outcomes, with a floor stated per lens in
  policy.

**Rough slices:**
1. Record a revert or post-merge fix event at landing time, from the merge diff.
2. Join it to the findings.
3. Per-lens precision and the floor in `/retro`.

**Cost and risk.** Low: a few hooks and a retro section. Nothing changes who lands what.

**What it rules out.** Nothing. It only defers autonomy until the numbers exist.

**Evidence.** S-3, S-24, S-27, S-26, S-34; the operator's answers on labels and order.

## Option 3 · Earned autonomy: the risk-gated lane, unlocked by the measurements (middle)

**Objective.** The operator's vision, reached in steps. Each step is unlocked only when the
measurements say the automated verdicts are accurate enough.

**Users and the main scenario.**
1. Option 2's numbers run first.
2. Then a **risk rule** (path-based escalation as in S-6, base-branch policy as in S-14) labels each
   PR low or high, and reports only.
3. The review **decides ambiguities and logs them** on the PR, and the human reads the log.
4. Once the lenses that a low-risk PR depends on hold their precision floor over N landed outcomes,
   the operator turns on the low-risk lane. The train is then started on the operator's standing
   authorisation, a policy that carries their name, instead of a per-PR command.

**What it changes.**
- Everything in Option 2.
- A risk rule kept as policy and judged by main's version.
- A decision log on each PR.
- A lane switch that stays off until the floors hold.
- One decision record that supersedes §7 for that lane only.

**Rough slices:**
1. Option 2, with operator rulings and overrides recorded as events.
2. The base-branch policy rule (guard safety, the operator's second priority).
3. The risk rule, reporting only.
4. The decision log.
5. The lane switch and its decision record.
6. The closed loop: low-risk retro candidates ride the lane; recurring rulings become proposed
   defaults.

**Cost and risk.** Medium. Every step is reversible, and autonomy arrives only with evidence. It
serves the operator's criterion directly: it is accurate first, and the human is reserved for high
risk.

**What it rules out.** Autonomy before measurement.

**Evidence.** S-3, S-6, S-14, S-24, S-26, S-30, S-36.

---

## Comparison

| Criterion | Option 1 · Autopilot | Option 2 · Measure first | Option 3 · Earned autonomy |
|---|---|---|---|
| Accuracy (operator) | Assumed, not measured | Measured | Measured, and autonomy gated on it |
| Human only for high risk (operator) | Yes, from day one | No change | Yes, once floors hold |
| Measurement → guard → policy order (operator) | Policy first | Measurement only | In that order |
| Complexity | High | Low | Medium, staged |
| Reversibility | Low: unsupervised landings ship | Full | High: the lane is a switch |
| Fit with the decision records | Supersedes §7 at once | Fits | Supersedes §7 for one lane, with evidence |
| Time to a first slice | Long | Short | Short (its first slice is Option 2) |
| Learns from mistakes and preferences (operator) | Retro tickets ride the autopilot; no preference data | Collects the labels: outcomes and rulings | Closed loop ⑥: retro → ticket → lane → before-and-after check; recurring rulings become proposed defaults |

**Recommendation: Option 3.** It reaches the operator's vision, but in the operator's own order:
measure, make the guards safe, then change policy. Its first slice is Option 2, so nothing is lost
by starting there. Option 1 lands unmeasured verdicts with no human act, which is the one move the
evidence argues against (S-7, S-26, S-35).

**Choice: Option 3, earned autonomy** (operator, 2026-10-23). Option 1 lost because it lands
unmeasured verdicts with no human act. Option 2 lives on as Option 3's first stage, not as the
whole answer.

**High risk, in the operator's words:** "The agent can't learn with the mistakes." [inference] The
operator defines risk by learnability, not by path: a change is high risk where the kit has no
measured record of its own accuracy on that kind of change (no outcome signal, no precision floor
met) or where a mistake would not show up as an outcome it can learn from. Phase 5 makes that
definition concrete.

**Later, not now:** "some kind of system-one or small language model that will helps it learn by
itself" (operator). This matches the decision models of S-3 and S-8, and the trace already holds
the labels such a model would train or calibrate on. It is recorded as a future PRD, after
stages ① to ⑥.
