---
id: PRD-10
type: prd
title: "The low-risk lane: a low-risk PR lands without the operator"
parent: D-02
stage: approved
created: 2026-10-28
updated: 2026-10-29
stages:
  - {stage: draft, at: 2026-10-28T12:26Z}
  - {stage: review, at: 2026-10-28T12:50Z}
  - {stage: approved, at: 2026-10-29T12:08Z}
approved_by: "agranado"
approved_at: 2026-10-29T12:08Z
---

# PRD-10 · The low-risk lane: a low-risk PR lands without the operator

## 1. Objective

Let a pull request whose effective risk is `low` land with no act of the operator's, through the
**low-risk lane**: the landing script, run by `/pr-iterate` once the PR is green, re-judges the
PR's risk at its head, keeps every refusal it makes today, and merges only when the lane is open,
the risk is low and nothing on the lane's own hold list applies. When a lane landing later turns
out to be a mistake, the lane sends the operator one notice, opens a revert PR where nothing has
undone the mistake yet, and holds that PR for them. One decision record supersedes shared
invariant §7 for this lane only, in a shared-layer release.

**Problem.** Every PR the chain builds stops one click short of the merge (shared invariant §7,
`/pr-iterate` hard rule "you never merge"), whatever its risk. The operator already lands most
PRs on a standing instruction to the session (the kit's ADR-0016 accepts the train's verdicts for
that), so the stop is a formality on most PRs and no protection on the rest: nothing checks that
the review the operator trusts has earned it. D-02 measured that trust first. K1 (PRD-06,
ADR-0036) records post-merge outcomes and prints each review area's earned record. K4 (PRD-07,
ADR-0037, ADR-0038) puts a check table and a decision log on every PR and marks each unspecified
item inside or outward. K2 (PRD-08) reads policy from the base branch and fails closed. K3
(PRD-09) judges each PR's effective risk and reports it, and gives the operator a kill switch.
Nothing acts on that verdict yet. D-02's outcome is that a low-risk ticket reaches a landed
change with no human step, and the operator is involved only when something high risk happens.

**Solution.**
- The lane is **closed** until the operator opens it, by landing a base-branch policy value that
  names them (their forge login). That value is the standing authorisation: a policy that carries
  their name, in place of a merge click per PR.
- When `/pr-iterate` records a PR `green` and the risk rule has just printed `effective: low`, it
  runs the landing command the lane policy names. The kit's policy names the landing script in
  lane mode; a consumer's ships empty, so its chain stops where it stops today.
- In lane mode the landing script makes every refusal it makes today, takes none of its override
  flags, then **holds** the PR (exit 4, recorded) unless the lane is open, the risk rule run at
  the head says `effective: low`, the check table passes, the verifier (PRD-13) said `pass` at
  the head, the diff touches nothing on the hold list, the base branch's own workflows are
  green, and the PR is not an escape's revert. Then it
  merges that head and records the landing as the lane's.
- Before it judges, each lane run records new post-merge outcomes. A mistake against a lane
  landing (an **escape**) gets one notice to the operator. Where nothing has undone it yet (a
  failed factory QA), the lane opens a revert PR, or files a fix ticket when the revert conflicts.
  The area's demotion needs no act: the escape is a missed mistake in its earned record, so the
  risk rule calls the area unlearned (PRD-09) and the lane holds every PR touching it, the revert
  included.
- A tripped kill switch makes every PR high (PRD-09), so it stops the lane at once. An agent
  cannot delete the trip marker: the adapter's root guard refuses it.

**The test of done.** In a fixture repository with the lane opened for `operator-login`, every
review area earned and a ticket stamped `Risk: low`, a green PR with a passing check table makes
`/pr-iterate`'s lane step print `lane: landed`, and the trace holds `merge.land outcome=landed
data.via=lane`. A second PR stamped `Risk: high security` prints `lane: held risk` and stays
open. A factory QA failure recorded against the first PR makes the next lane run print `lane:
escape pr:#<N> revert pr:#<M>`, open one revert PR, file one notice, and hold the revert PR with
`lane: held risk`. Creating the trip marker makes the next lane run print `lane: held switch`.

## 2. Users and scenarios

**U1 — the operator**, who opens and closes the lane, trips the kill switch, reads the decision
log after a lane landing, and receives an escape's notice. **U2 — `/pr-iterate`**, which runs the
lane step. **U3 — the landing script in lane mode**, which judges, holds or merges, and handles
escapes. **U4 — `/retro`**, which counts what the lane landed and held. **U5 — K6's closed loop**,
which will send retro tickets through this lane.

Stories:

1. As the operator, I want a low-risk PR to land with no act of mine, so that I am needed only
   for the high-risk ones.
2. As the operator, I want the lane closed until I name myself in base-branch policy, so that
   nobody, an agent included, can open it in a PR it then lands.
3. As the operator, I want the lane to keep every check the landing makes today, so that a lane
   landing is never weaker than one I would have run.
4. As the operator, I want a PR that edits the shared layer, a policy, a guard or the lane itself
   held for me whatever its risk says, so that no lane landing can widen the lane.
5. As the operator, I want one notice per escaped mistake, naming the mistake, the PR and its
   review area, and a revert PR waiting for me where nothing undid it, so that I act on it once.
6. As the operator, I want the kill switch to stop the lane at once, and no agent able to reset
   it, so that I can halt it the moment I stop trusting it.
7. As `/retro`, I want each lane landing and hold recorded with a closed reason, so that D-02's
   H2 (fewer than half of PRs need the operator, with no rise in escaped mistakes) can be read.

**UC1 — A low-risk PR lands through the lane.** Actor: `/pr-iterate`, on PR #930 for ticket
#925, stamped `Risk: low`. The lane policy on the base branch names `operator-login`. Goal: the
PR lands with no operator act.
1. `/pr-iterate` ends an iteration with every check green and a review verdict at the head, and
   records `pr.iterate outcome=green`.
2. The risk rule, run at that head with ticket #925, prints `effective: low` and `switch: on`.
3. The lane policy names a landing command, so `/pr-iterate` runs it with `--lane`, the PR and
   the ticket.
4. The landing script reads the PR and makes every refusal it makes today: open, not a draft, no
   human review requesting changes, mergeable, not behind, checks green, a `pr.iterate` and an
   unblocked Axis-1 `review.verdict` at the head, no shared-layer move without a bump. None
   applies.
5. It runs the lane's own checks in order: the lane is open; its landing script and the risk rule
   in this checkout match the base branch's; it records new outcomes, finds no escape to handle,
   and the PR is not an escape's revert; the diff touches no hold-list path; the base branch's
   latest workflow runs are green; the check-table reader, given the PR body and the ticket body,
   exits 0; the latest verifier verdict at the head is `pass` (PRD-13); the risk rule, run again
   at the head, prints `effective: low`.
6. It merges that head, waits for the base branch's workflows as today, records `merge.land
   outcome=landed data.via=lane` with the count of decision-log rows, and `feedback
   outcome=unasked data.by=lane`. It prints `lane: landed` and exits 0.
7. `/pr-iterate` reports `Landed by the lane` with the PR's decision-log ids, for the operator to
   read after the fact.

Extensions:
- 2a. The rule prints `effective: high <reason>`. `/pr-iterate` runs no landing command and
  reports the PR as waiting for the operator, as today.
- 3a. The lane policy names no landing command (every consumer, as shipped). The step does
  nothing, and the report is today's.
- 4a. Any of today's refusals applies. The script refuses as today (exit 2, nothing merged,
  nothing recorded), and `/pr-iterate` reports the refusal.
- 5a. The lane policy names nobody, or cannot be read under K2's contract. `lane: held closed`,
  exit 4.
- 5b. The checkout's landing script or risk rule differs from the base branch's. `lane: held
  drift`, exit 4: a PR must not land under the code it changes.
- 5c. The check-table reader exits anything but 0 (a missing or extra row, a `fail` or `skipped`
  row, a broken row, no table, or no ticket body). `lane: held check-table`, exit 4.
- 5d. The rule prints `effective: high <reason>`: `lane: held risk`, or `lane: held switch` when
  it printed `switch: tripped`. Exit 4.
- 5e. The PR's head moved after the rule judged it. The forge refuses the merge of a head other
  than the judged one; exit 1 as a rejected merge is today.
- 5f. The verifier's latest verdict at the head is not `pass`: `blocked` with a disputed
  check-table row, `blocked` otherwise, `unavailable` (no verifier model could be reached), or
  no verdict at all. `lane: held verifier <reason>`, the reason `disputed`, `blocked`,
  `unavailable` or `none`. Exit 4.
- 6a. A base-branch workflow fails after the lane's merge. Exit 1 as today, and the operator gets
  one notice naming the landing and the failed run. Every later lane run holds with `lane: held
  base-red` until the base branch's latest runs are green again.
- 6b. Every hold (5a–5d, 5f, and UC2, UC3 2) records `merge.land outcome=skipped data.via=lane` with
  the hold token, once per PR, head and token.

**UC2 — A PR on the hold list waits for the operator.** Actor: `/pr-iterate`, on PR #934, which
edits the lens-slice policy file for a ticket stamped `Risk: low` (a planner who missed
`shared-layer`). Every area is earned, so the rule prints `effective: low`. Goal: the PR waits
whatever its risk says.
1. The landing script reaches the hold-list check. The diff touches a policy file K2 reads from
   the base branch.
2. It prints `lane: held path`, records the hold, and exits 4. The PR stays open.

Extensions:
- 1a. The diff touches a file `VERSION`'s `files:` list names at either end, or a path the lane
  policy's hold patterns select (the kit's: the landing script, the risk rule, the hooks, the
  adapter, the CI workflows). Same hold.

**UC3 — A lane landing turns out to be a mistake.** Actor: the landing script, in a lane run for
PR #940. PR #930 landed through the lane last week; since then factory ticket T-71, which #930
built, failed its QA gate. Goal: the operator learns of it once, the mistake is undone in a PR
they hold, and the area stops landing through the lane.
1. Before judging #940, the script runs the outcome recorder, which records `merge.outcome
   outcome=qa-failed subject=pr:#930`.
2. The script finds that #930 landed with `data.via=lane` and has no `lane.escape` event. It is
   an escape.
3. It opens a revert of #930's merge commit on a new branch from the base branch, and a PR for
   it whose body names the mistake, PR #930 and its review areas.
4. It sends the operator one notice naming the outcome, PR #930, its review areas and the revert
   PR.
5. It records `lane.escape outcome=revert subject=pr:#930` with the revert PR in `related`, and
   prints `lane: escape pr:#930 revert pr:#941`.
6. It goes on judging #940. #930's areas now carry a missed mistake, so the risk rule calls them
   unlearned. #940 touches one of them: `lane: held risk`. A PR in an area #930 did not touch
   still lands.
7. The revert PR #941 reaches `/pr-iterate` like any PR and is held: it is an escape's revert
   (`lane: held escape`), and its areas are unlearned.

Extensions:
- 1a. The outcome is `reverted` (a revert already landed) or `fixed` (a fix already landed). The
  mistake is already undone, so the script opens nothing, sends the notice, records
  `lane.escape outcome=notified`, and prints `lane: escape pr:#930 notified`.
- 3a. The revert does not apply cleanly. The script opens no PR, files one fix ticket through the
  tracker naming the PR, the outcome and the areas, stamped `Risk: high unclear`, sends the
  notice naming that ticket, and records `lane.escape outcome=fix`.
- 3b. Opening the revert PR or filing the ticket fails. The script records nothing for the
  escape, says why on standard error, holds the PR it was judging with `lane: held escape`, and
  exits 4; the next run tries again.
- 5a. A later lane run finds the same escape. It has a `lane.escape` event, so nothing is opened,
  sent or recorded again.
- 7a. The operator runs the landing script with `--escapes` and no PR. It records outcomes and
  handles every escape as above, lands nothing, and exits 0.

**UC4 — The operator opens, closes and stops the lane.** Actor: the operator. Goal: the lane is
open only while they say so, and stops at once when they say stop.
1. After reading `/retro`'s risk reports, the operator lands a policy change naming their login
   as the lane's operator. That PR touches a policy file, so they land it themselves.
2. From the next run, low-risk PRs land through the lane.
3. A lane landing surprises them. They create the trip marker in the clone's git directory.
4. Every lane run in that clone holds with `lane: held switch`.
5. An agent session runs a command that removes the marker. The adapter's root guard refuses it.
6. To stop the lane everywhere, the operator lands the policy change that empties the name (or
   trips the base-branch switch). Every run in every clone and in CI reads the base branch.

**UC5 — `/retro` reads the lane.** Actor: the operator, running `/retro` over a wave of 14 PRs.
Goal: see how much the lane carried and why it held the rest.
1. Question 6 (chain health) prints `lane: landed 8, held 6 (risk 4, path 1, check-table 1),
   escapes 0`.
2. Question 7 counts the lane's `feedback by=lane` apart from the operator's, as it counts the
   train's.

## 3. Model

- **The low-risk lane**: the landing script run with `--lane`, by `/pr-iterate`, with no operator
  act. It lands a PR or holds it. Nothing else lands without the operator.
- **Lane policy**: base-branch policy read under K2's contract. It names the lane's operator (a
  forge login), the landing command `/pr-iterate` runs, and the hold patterns. It is a policy
  file of its own, not the risk policy (which ships filled): shipped empty, so a consumer's lane
  is closed and its `/pr-iterate` runs nothing, with a kit-only twin that holds the kit's values,
  as the agents policy has. Both names end `.config.sh` under `scripts/`, so both are in K2's
  judging set.
- **Open**: the lane policy names an operator and can be read. Anything else is **closed**.
  Opening and closing are changes to that policy, which only the operator lands, since a lane run
  holds any PR that touches it.
- **Hold list**: every file `VERSION`'s `files:` list names at the PR's merge base or head; every
  policy file K2 reads from the base branch; and every path the lane policy's hold patterns
  select. These are Q1's changes "whose mistake would never show up as a countable outcome", held
  by path whatever the planner stamped.
- **Hold**: a refusal of the lane's own, after today's refusals have passed. Exit 4, one line
  `lane: held <token>`, one `merge.land outcome=skipped data.via=lane` event. The tokens, in the
  order they are checked: `closed`, `drift`, `escape`, `path`, `base-red`, `check-table`,
  `verifier`, `switch`, `risk`. The `verifier` hold names its reason after the token.
- **Escape**: a `merge.outcome` against a PR whose `merge.land` says `data.via=lane`. An escape is
  handled once: notified, and reverted or ticketed where nothing has undone it. Its area's
  demotion is the risk rule's, read from the earned record (PRD-09), not a state the lane keeps.
- **Notice**: one message to the lane's operator per escape, and one per failed post-merge
  workflow after a lane landing, naming only closed tokens, PR and ticket numbers, review area
  names and a run id.
- **Standing authorisation**: the operator's name in the lane policy. It replaces the per-PR
  merge act for the lane only, and is what the decision record superseding §7 rests on.

## 4. Rules

Ids start at runtime/R80 and process/R80, leaving a gap after PRD-09 (runtime/R52–R69,
process/R61–R67). PRD-08 took a new area (policy/R1 to R33), so none collides (§8).

Area: runtime

Deltas against `docs/specs/runtime.md`.

### ADDED

runtime/R80. WHEN the landing script runs with `--lane`, it SHALL make every refusal it makes without `--lane`, with the same exit code and the same effect. [UC1 4, 4a]
runtime/R81. IF `--lane` is given with `--no-iteration`, `--no-review`, `--unasked` or `--train`, THEN the landing script SHALL exit 2, merging and recording nothing. [UC1 4]
runtime/R82. WHEN every refusal has passed in lane mode, the landing script SHALL check, in this order, `closed`, `drift`, `escape`, `path`, `base-red`, `check-table`, `verifier`, `switch` and `risk`, and on the first that applies SHALL print `lane: held <token>`, merge nothing and exit 4. [UC1 5]
runtime/R83. The lane SHALL read as closed, holding with `closed`, when the lane policy names no operator or cannot be read under the base-branch policy contract. [UC1 5a, UC4 6]
runtime/R84. IF the landing script or the risk rule in the running checkout differs from its version on the base branch, THEN a lane run SHALL hold with `drift`. [UC1 5b]
runtime/R85. IF the PR's diff from its merge base touches a file `VERSION`'s `files:` list names at either end, a policy file read under the base-branch policy contract, or a path the lane policy's hold patterns select, THEN a lane run SHALL hold with `path`. [UC2 1, 2, 1a]
runtime/R86. IF the latest run of any workflow on the base branch's head did not succeed, THEN a lane run SHALL hold with `base-red`. [UC1 6a]
runtime/R87. IF the check-table reader, given the PR body and the ticket body, exits anything but 0, or no ticket body is given, THEN a lane run SHALL hold with `check-table`. [UC1 5c]
runtime/R88. A lane run SHALL run the risk rule at the PR's head commit with the PR and its ticket, SHALL read only its `effective:` and `switch:` lines, and SHALL hold with `switch` when it prints `switch: tripped` and with `risk` when it prints any effective risk but `low`. [UC1 5, 5d, UC4 4]
runtime/R89. WHEN a lane run passes every check, the landing script SHALL merge the head commit the risk rule judged, and SHALL let the forge refuse a merge whose head has moved. [UC1 6, 5e]
runtime/R90. WHEN the lane lands a PR, the landing script SHALL record `merge.land outcome=landed data.via=lane` with the count of decision-log ids in the PR body, and `feedback outcome=unasked data.by=lane`, and SHALL print `lane: landed`. [UC1 6]
runtime/R91. WHEN a lane run holds a PR, the landing script SHALL record one `merge.land outcome=skipped data.via=lane` with the hold token and the head commit, and SHALL record nothing when the trace already holds one for the same PR, head and token. [UC1 6b]
runtime/R92. Before it judges a PR, a lane run SHALL run the outcome recorder, and SHALL handle every escape that has no `lane.escape` event. [UC3 1, 2, 5a]
runtime/R93. The trace SHALL accept the kind `lane.escape` with the outcomes `revert`, `fix` and `notified`, subject the escaped PR, and SHALL refuse any other outcome on it, exit 2, writing nothing. [UC3 5]
runtime/R94. WHEN an escape's outcome is `qa-failed`, the landing script SHALL open one PR reverting the escaped PR's merge commit on a new branch from the base branch, and record `lane.escape outcome=revert` with that PR in `related`. [UC3 3, 5]
runtime/R95. IF the revert does not apply cleanly, THEN the landing script SHALL open no PR, SHALL file one fix ticket stamped `Risk: high unclear` naming the escaped PR, the outcome and its review areas, and SHALL record `lane.escape outcome=fix` with that ticket in `related`. [UC3 3a]
runtime/R96. WHEN an escape's outcome is `reverted` or `fixed`, the landing script SHALL open no PR and file no ticket, and SHALL record `lane.escape outcome=notified`. [UC3 1a]
runtime/R97. WHEN the landing script records a `lane.escape`, it SHALL send the lane's operator one notice naming the outcome, the escaped PR, its review areas and the revert PR or fix ticket when there is one. [UC3 4]
runtime/R98. IF opening the revert, filing the ticket or sending the notice fails, THEN the landing script SHALL record no `lane.escape` for that escape, name the cause on standard error, and hold the PR it was judging with `escape`. [UC3 3b]
runtime/R99. A lane run SHALL hold with `escape` a PR that a `lane.escape` event names in `related`, or whose ticket one names. [UC3 7]
runtime/R100. WHEN a base-branch workflow fails after a lane landing, the landing script SHALL exit 1 as it does today and send the lane's operator one notice naming the landed PR and the failed run. [UC1 6a]
runtime/R101. WHEN the landing script runs with `--escapes` and no PR, it SHALL record outcomes and handle every unhandled escape as a lane run does, merge nothing, and exit 0. [UC3 7a]
runtime/R102. The landing script's lane output, its lane events and its notices SHALL carry only closed tokens, review area names, PR and ticket numbers, commit shas, run ids and digits, and no text from a ticket body, a PR body, a commit message or a log.
runtime/R103. The adapter's root guard SHALL refuse an agent's tool call that deletes, moves or overwrites the kill switch's trip marker. [UC4 5]
runtime/R104. IF the latest `verify.verdict` on the PR, read as runtime/R214 (PRD-13) reads it for `merge.land`, is not `pass`, THEN a lane run SHALL hold with `verifier`, print `lane: held verifier <reason>` with the reason `disputed` for a `blocked` verdict whose `data.disputed` is 1 or more, `blocked` for any other `blocked`, `unavailable` for `unavailable`, and `none` when there is no such verdict, and SHALL record the reason in the hold event's `data.reason`. [UC1 5f]

Area: process

Deltas against `docs/specs/process.md`.

### ADDED

process/R80. WHEN `/pr-iterate` records `green` on a PR, the risk rule has printed `effective: low` at that head, and the lane policy names a landing command, `/pr-iterate` SHALL run that command with `--lane`, the PR and its ticket, and report `lane: landed`, the hold token or the refusal it printed. [UC1 3, 7, 2a, 3a, 4a]
process/R81. IF the lane policy names no landing command, THEN `/pr-iterate` SHALL run none and report as it does today. [UC1 3a]
process/R82. WHEN the lane lands a PR, `/pr-iterate`'s report SHALL list the PR's decision-log ids for the operator to read after the landing. [UC1 7]
process/R83. `/retro`'s question 6 SHALL count, in its window, the lane's landings, its holds by token and its escapes by outcome. [UC5 1]
process/R84. `/retro`'s question 7 SHALL count a `feedback` with `data.by=lane` apart from the operator's, as it counts the train's. [UC5 2]
process/R85. `/merge-train` SHALL NOT be started by the lane, and the lane SHALL land one PR per run. [UC1 3]

### MODIFIED

process/R65 (added by PRD-09). `/pr-iterate` and the landing script SHALL take the same actions on a PR whatever the risk rule prints, except the lane step of process/R80 and the lane mode of runtime/R80–R102. [UC1 2a]

Area: runtime

runtime/R215 (added by PRD-13). No `verify.verdict` outcome SHALL change whether the landing script refuses, waits or merges, except the lane's `verifier` hold of runtime/R104. [UC1 5f]

## 5. Slices (vertical, demoable, in order)

Slice 1 moves `constitution/shared-invariants.md`, a file `VERSION` lists, so it is a release
ticket in its own frontier (ADR-0033). Slices 2 to 5 move the kit-only landing script, the
adapter and skills; slice 3 adds a trace kind, which moves `scripts/trace.sh`, so it is a release
too. All wait for PRD-09's slice 3 (the kill switch) and PRD-08's base-branch reader.

**Slice 1 — the record and the invariant (shared-layer release).**
- *Covers:* none; it carries the decision record every later slice cites.
- *Also:* a new decision record superseding shared invariant §7 for the lane only, amending the
  kit's ADR-0024 clause 7 and ADR-0036 for the landing script's lane mode as a reader run by a
  chain skill, and stating how the lane keeps §5 (§8). §7's text gains the exception in portable
  words. The glossary gains low-risk lane, lane policy, hold, escape and notice. Bump,
  `UPDATING.md` (a consumer takes the new text; its lane stays closed), re-captures, tag.
- *Accept:* the docs gate's portability check passes on the new §7; the self-host suite still
  passes over a fresh bootstrap; the record's index row names what it supersedes and amends.

**Slice 2 — the lane lands a low-risk PR, and holds the rest.** The tracer bullet.
- *Covers:* runtime/R80, R81, R82, R83, R84, R85, R86, R87, R88, R89, R90, R91, R102, R104,
  process/R80, R81, R82, R85, process/R65 (modified), runtime/R215 (modified).
- *Blocked by:* slice 1, and PRD-13's slice 1 for the `verify.verdict` kind.
- *Accept:* the landing script's suite lands UC1's fixture PR through a stubbed forge and records
  `data.via=lane`; holds a closed lane, a drifted script, a hold-list path, a red base branch, a
  `skipped` check-table row, a verifier verdict other than `pass` (each of the four reasons), a
  tripped switch and a `high` effective risk, each with its token,
  exit 4 and one event; a second held run at the same head writes nothing; every override flag
  with `--lane` exits 2; every refusal the suite already holds still refuses under `--lane`. A
  skill-text suite holds `/pr-iterate`'s lane step, its no-command branch and its report line.

**Slice 3 — escapes (shared-layer release).**
- *Covers:* runtime/R92, R93, R94, R95, R96, R97, R98, R99, R101.
- *Blocked by:* slice 2.
- *Accept:* a fixture `qa-failed` outcome against a lane landing opens one revert PR, one notice
  and one `lane.escape outcome=revert`; a conflicting revert files one fix ticket instead; a
  `fixed` outcome only notifies; a second run opens and sends nothing; a failing forge call
  records nothing and holds with `escape`; the revert PR is held with `escape`; `--escapes` lands
  nothing. The trace suite's row-for-row table holds the new kind.

**Slice 4 — the kill switch cannot be reset by an agent, and the post-merge notice.**
- *Covers:* runtime/R100, R103.
- *Blocked by:* slice 2.
- *Accept:* the root guard's suite refuses an agent's `rm`, `mv` and write on the trip marker and
  allows the operator's; a fixture workflow failing after a lane landing sends one notice and the
  next lane run holds with `base-red`.

**Slice 5 — `/retro` reads the lane.**
- *Covers:* process/R83, R84.
- *Blocked by:* slice 2.
- *Accept:* the retro suite's fixture trace prints UC5's counts and keeps `by=lane` apart.

## 6. Non-goals (this PRD)

- **A lane for consumers.** *Later*. The lane's mechanism is the kit-only landing script; a
  consumer gets the amended §7 and a `/pr-iterate` step that does nothing until its lane policy
  names a landing command (§9).
- **The risk rule's verdict, the thresholds and the kill switch themselves.** PRD-09 and PRD-08.
  This PRD reads the rule's `effective:` and `switch:` lines and nothing else of it.
- **Re-earning a demoted area.** *Never* a lane act: an area earns low risk back only through its
  record (ADR-0036, PRD-09), as more landings push the escape out of its window.
- **A lane-wide stop on an escape.** *Never* (decision Q5, option (c) lost). The kill switch stays
  the operator's manual stop.
- **The lane updating a stale branch, or ordering a batch.** *Never* here: a behind PR is refused
  as today, and batches are `/merge-train`'s, which only the operator starts.
- **A schedule that sweeps escapes with no PR to judge.** *Later*. `--escapes` exists for the
  operator or a `/loop` to run; nothing starts it on its own.
- **A session landing a PR on the operator's in-session instruction.** Unchanged. That landing is
  the operator's act through the landing script without `--lane`, as today.
- **Implementing the fix an escape's ticket asks for.** *Never* by the lane. The ticket goes
  through `/implement` like any other, and its PR is held (R99).
- **Change kind as area × tier; a learned model of risk.** *Later* (operator, 2026-10-23).

## 7. Technical constraints and testing

- POSIX `sh` and `git`, plus the forge CLI the landing script already uses. The landing script
  stays kit-only; the root guard is the Claude Code adapter's.
- **Trust boundary.** The lane acts (merges, opens PRs, files tickets, sends notices), so it reads
  no prose: the risk rule's two lines, the check-table reader's exit code, decision-log ids only
  (process/R60), trace events through the trace's readers, and the forge's state fields. A notice
  and a revert PR body are built from closed tokens and numbers only (R102).
- **The lane runs the base branch's code.** R84 holds a run whose landing script or risk rule
  differs from the base branch's, so a PR cannot land under a lane it edited; R85 holds a PR that
  edits them.
- **Failing closed everywhere**: an unreadable lane policy, a missing ticket, no check table, an
  unreadable trace (the rule calls the PR high), a red base branch, no verifier `pass` at the
  head, a failed escape action. Each holds; none lands.
- **A revert** is made in a throwaway worktree under the git directory, from the base branch,
  with `git revert -m 1` of the escaped merge commit, pushed to a new branch; the worktree is
  removed after. Its PR body opens with the escape's tokens.
- **Tests** drive the landing script against a stubbed forge, as its suite already does, with a
  fixture trace (landings, outcomes, verdicts, `pr.iterate`), a fixture base-branch lane policy
  and the risk rule's real output. Every new hold token and the `lane.escape` outcomes join the
  suites' row-for-row checks (ADR-0024 clause 1).
- **Numbers**: one PR per lane run; one hold event per PR, head and token; one notice and one
  `lane.escape` per escape; a second run writes 0 lines. The thresholds are K2's values.

## 8. Decisions recorded for this PRD

**From D-02** (decisions.md, 2026-10-23): Q1 (high risk is not yet learned or not learnable; the
policy, guard and gate files and the shared layer are never learnable), Q2 (a mistake is a
revert, a later fix within 30 days, or a failed factory QA), Q3 (one escaped mistake demotes at
once), Q5 (an escape demotes its area, opens a revert or fix PR held for the operator, and sends
one notice; other areas keep their lane; the kill switch stays the manual stop), Q6 (outward items
make the PR high, inside items are decided and logged), Q7 (K5 fourth, after K3 and K4), the
`Risk:` contract settled with D-08, and Option 3 (a lane that stays closed until the operator
opens it, on a standing authorisation that carries their name, behind one record superseding §7
for the lane only).

**Already fixed, not reopened:** ADR-0019 and ADR-0032 (the landing script's iteration and review
checks), ADR-0025 (the shared-layer bump, no override), ADR-0015 (the release tag), ADR-0016
(train-only verdicts while landing is delegated), ADR-0036, ADR-0037, ADR-0038, and PRD-09's
risk rule, effective risk and kill switch.

**Derived while writing** (the session, under the operator's standing delegation of rulings; the
maintainer confirms them at approval):

- **One new record supersedes §7 for the lane only, and §7's text names the exception.** The
  invariant ships verbatim, so its new sentence is portable: a change judged low risk from
  measured post-merge outcomes may land with no per-change human act, under a standing
  authorisation that names the human, which a human can stop at once, and whose escaped mistakes
  return to that human. A consumer whose project records no such decision keeps §7 as it reads
  today.
- **The same record amends ADR-0024 clause 7 and ADR-0036's caller list** (both at or near their
  amendment cap, so as a new record): the landing script in lane mode, run by `/pr-iterate`, is a
  trace reader and runs the outcome recorder, handing back only the tokens of R102.
- **§5 keeps its text.** The lane lands only when no outward item is open (the rule's `outward`),
  and inside items are decided and logged as ADR-0038 already allows. What changes is when the
  operator reads the log: after the landing. The record says so, and `/pr-iterate` lists the ids.
- **The lane is the landing script with `--lane`, run by `/pr-iterate`.** PRD-09 named the
  landing script the reader that acts. One landing path keeps every refusal by construction
  (R80); a second script would copy them and drift.
- **The lane is closed until the operator names themselves in base-branch policy.** Option 3's
  lane switch and its standing authorisation are one value. Separate from the kill switch: the
  name opens, the switch stops, and either alone keeps PRs off the lane.
- **The lane holds the hold list by path, whatever the risk.** PRD-09 leaves `shared-layer` to
  the planner. The lane is where an unlearnable change would land unread, so it holds Q1's
  never-learnable files itself. It writes no `Risk:` reason, so the contract the factory reads is
  unchanged.
- **Q5 read against Q2: only a failed QA gets a revert PR.** A `reverted` outcome means a revert
  already landed, and a `fixed` outcome a fix; reverting the original then would undo the fix. So
  those two notify only. The demotion and the notice happen for all three.
- **"A fix PR where the revert conflicts" becomes a fix ticket.** A fix needs an implementation
  session; the lane cannot write one. The ticket goes through `/implement`, and its PR is held.
- **A red base branch holds the lane and notifies.** Not one of Q2's mistakes, but an agent
  landing onto a red base branch compounds it; holding is the closed failure.
- **A hold is exit 4 and an event; a refusal stays exit 2 and silent.** Today's refusals are
  "not ready", and the operator path keeps their meaning (R80). A hold is the lane's judgement,
  and D-02's H2 needs it counted.
- **The trip marker is guarded by the root guard.** PRD-09 left this to K5. A marker an agent can
  delete is no stop once the lane acts.

**Settled after approval** (the 2026-10-31 grill of D-02's open questions; the first five were
§9's):

- **The lane requires the verifier's `pass`** (operator, 2026-10-31, overriding PRD-13's
  "never"). A lane run holds a PR with `verifier` unless the latest verifier verdict at its head
  is `pass`: a disputed check-table row, a `blocked` verdict, or `unavailable` (no verifier model
  reached) holds it for the operator, and so does no verdict at all. The hold names its reason
  (`disputed`, `blocked`, `unavailable`, `none`), added as runtime/R104, with runtime/R82's
  order MODIFIED in place and PRD-13's runtime/R215 MODIFIED here for the one exception. The
  verifier and the walk that resolves its model (another provider first, else the same provider
  in a different family from the diff's author) are PRD-13's. The hold sits after
  `check-table` and before `switch`, so a PR the review and the table already hold reads its own
  reason first. T-52 (#915) carries it, blocked by PRD-13's first ticket. This matches the D-08
  operator's "the reviewer and a verifier from another provider both pass a PR" and the D-08
  session's recommendation, with the operator's same-provider rung added.
- **The lane policy is a file of its own, shipped empty, with a kit twin** (the session under
  the operator's delegation, 2026-10-31). The risk policy ships filled with no twin (PRD-08 §3,
  ADR-0003's 2026-09-28 amendment), and the lane policy ships empty, so one file cannot hold
  both. Its `scripts/*.config.sh` name puts it in K2's judging set (policy/R9), so R83 and R85
  hold with no extra list entry, and "cannot be read" is K2's fail-closed line, exit 3. The
  factory defines no lane key, so no manifest key overrides it. §3 and T-51 (#914) say so.
- **PRD-09's questions left to K5 are settled** (the session under the operator's delegation,
  2026-10-31). The token: this PRD's own `switch` hold. The fix window: only settled landings
  count toward an area's 20 (PRD-09 runtime/R55, operator, 2026-10-31).
- **The notice is one forge issue assigned to the lane policy's operator login** (the session
  under the operator's delegation, 2026-10-31). The landing script already holds the forge
  credentials and calls (runtime/R94, R95), an issue lasts, and R102 bounds its text. The D-08
  session's recommendation, a trace event plus the factory's post-merge QA queue, is not taken:
  that queue is not built, exists only in a factory project, and lists landings for batch QA
  rather than flagging an escape, which D-02 Q5 says the operator is notified of.
- **The lane stays kit-only** (the session under the operator's delegation, 2026-10-31). The
  landing script is kit-only; promoting a forge-neutral landing command is K6's grill, with the
  kit's lane record in hand.
- **Requirement ids stand** (the session under the operator's delegation, 2026-10-31). PRD-09
  was approved with process/R65 unchanged, so this PRD's MODIFIED process/R65 names it
  correctly, and runtime/R80 to R104 and process/R80 to R85 collide with nothing.

**Alternatives considered:**

- **The lane as `/merge-train` started by an agent.** The train's first hard rule is that only the
  operator starts it, and it is a batch tool. Rejected; the lane lands one PR per run (process/R85).
- **The lane trusting the effective risk `/pr-iterate` printed.** The head can move and the
  checkout can differ. Rejected; the landing script runs the rule itself at the head it merges.
- **A lane-wide stop on any escape** (Q5 option (c)). Rejected by the operator.
- **The lane writing `Risk: high shared-layer` for a hold-list path.** It would put a planner
  reason in a writer the contract does not name. Rejected for the path hold.

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

None open. The five questions this section held were settled after approval, and the
operator's 2026-10-31 verifier ruling added one hold (§8).

## 10. Dogfood plan

Five tickets in slice order. After slice 2 lands, the operator opens the kit's lane by landing
their login in the policy, and every `/pr-iterate` run on a low-risk kit PR lands it or prints
its hold. After slice 3, the operator walks UC3 once in the landing script's fixture repository
to see the revert PR, the notice and the area's holds before the first real escape can happen. Each wave's `/retro` after slice 5 reads D-02's H2 directly: the share of PRs held for the
operator, and the escapes beside it.
