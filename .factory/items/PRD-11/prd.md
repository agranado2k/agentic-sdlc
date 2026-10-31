---
id: PRD-11
type: prd
title: "The closed loop: retro to ticket to lane to a before-and-after check"
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

# PRD-11 · The closed loop: retro to ticket to lane to a before-and-after check

## 1. Objective

Close the kit's learning loop. Every fix `/retro` proposes, and every operator ruling that
recurs, becomes a ticket that carries the measure it will be judged by. That ticket goes through
the low-risk lane like any other ticket. It counts as working only when a before-and-after check
of three repeats a side shows a drop larger than the pooled standard deviation.

**Problem.** `/retro` already reads the trace and turns what recurs into candidate tickets. A
candidate that edits a lens or a skill carries a `Targets:` query, and `/retro`'s before-and-after
section compares that query's rate per landed PR in a window before the landing and in an equal
window after (process/R25–R28). Three gaps keep this from being the loop the operator asked for
(D-02, the operator's second idea, 2026-10-23: "the kit learns with the mistakes so it can
automatically fix that, and learns the project's guidelines and the human's preferences"):
- **The check reads noise as a result.** One before-rate and one after-rate are compared, so a
  wave that happened to be quiet reads as a fix that worked, and a noisy one reads as a fix that
  failed. D-02 asked for the check to be *eval-gated: three repeats, pooled SD*.
- **Only lens and skill edits are judged.** A candidate that adds a check or changes a policy
  value carries no measure, so nothing ever says whether it worked.
- **Preferences are not data.** When the operator rules on an outward ⚠️ UNSPECIFIED item
  (ADR-0038), the ruling is a comment on the PR, nowhere in the trace. So no retro can see that
  the operator kept the same kind of change five times running, and nothing can propose making
  that the default.

K1–K5 built everything this loop rides on. K1 (PRD-06, ADR-0036) gives post-merge outcomes and
review areas. K4 (PRD-07, ADR-0037, ADR-0038) gives the decision log and the inside/outward
scope. K2 (PRD-08) gives the base-branch risk policy. K3 (PRD-09) gives the risk rule. K5
(PRD-10) gives the lane.

**Solution.**
- **A loop ticket** is any ticket that carries a `Targets:` line, whatever wrote it: a retro
  candidate, the software factory's planner, or one of D-08's efficiency proposals.
  `/retro`'s before-and-after section already judges every such ticket. This PRD makes the
  judgement eval-gated.
- **Two summed measures beside the count.** Per landed ticket, `/retro` measures the tokens
  priced per model under the run the ticket's `/implement` opened, and the agent wall-clock
  of that run, from its `run.start` to its `run.end` at the open, reviewed PR. The section prints the median of each over the
  wave next to the loop tickets' counts, each on its own, never as one combined score. This is
  how a D-08 efficiency proposal measured in tokens or time is read.
- **The eval gate.** Each side of the landing is split into three equal **repeats**. The query's
  rate per landed PR is measured in each repeat, and the **pooled SD** of the six rates is
  computed. The row reads `drop` only when the before-mean minus the after-mean is greater than
  the pooled SD. It reads `no drop` when the after-mean is not below the before-mean, which is a
  finding, as today. Anything between reads `within noise`, which is reported and is not a
  finding. A `drop` records one note that closes the loop for that ticket.
  It is a post-landing noise check, not D-08's pre-landing eval gate, which is *later* (§6, §8).
- **Every candidate that edits something carries its measure.** `Edits:` widens from `lens` and
  `skill` to `check` and `policy`. Each such candidate carries `Runs:` and `Targets:`, checked by
  the vocabulary checker, or it stays an observation. The candidate block is the retro → ticket
  handoff contract D-02 agreed with D-08.
- **Retro tickets ride the lane.** They are stamped and judged like any ticket. A lens edit is
  always held for the operator, because it changes the instrument the earned record is measured
  with.
- **Rulings become data.** Each outward item on the confirm-list carries a closed **surface**
  token: `output-format`, `flag`, `exit-code`, `agent-rule` or `other`. A **ruling recorder**
  records the operator's `keep` or `change` against the item. An item the operator ruled `keep`
  at the head no longer makes the PR `high outward`.
- **Recurring rulings become proposed defaults.** Take a review area and a surface. When the
  operator's last 5 rulings for that pair, on 5 landed PRs, all read `keep`, `/retro` proposes a
  **ruling default**: a policy value. Its `Targets:` query is the operator's rulings of that
  surface, so the loop judges its own proposal. The operator confirms the proposal once, by
  landing the policy change, which the lane always holds for them. From then on, an outward item
  of that surface, on a PR whose review areas all carry the default, is ruled `keep` by policy
  and recorded as such.

**The test of done.** The fixture repository has the lane open. Loop ticket #950 is stamped
`Targets: kind=finding.triage data.source=check data.id=Kit-CI-self-host` and landed through the
lane. Before the landing, its six repeats read `0.50 0.40 0.60`, and after it `0.10 0.20 0.00`.
`/retro` then prints `ticket:#950 … mean 0.50 → 0.10, pooled SD 0.10 — drop; landed: lane` and
records one closed note. A second `/retro` records none. Then five operator `keep` rulings of
surface `exit-code` are recorded on five landed PRs touching review area `security`. The next
`/retro` files one candidate, `Edits: policy risk`, with `Targets: kind=ruling data.by=operator
data.surface=exit-code`. Once `security:exit-code` is in the risk policy's ruling defaults, a PR
touching only `security` paths with one outward `exit-code` item gets a `ruling outcome=keep
data.by=default`. The risk rule prints `effective: low`, and the lane lands the PR.

## 2. Users and scenarios

**U1 — the operator**, who rules on outward items, confirms a proposed default by landing it,
and reads which fixes held up. **U2 — `/retro`**, the one skill that reads the trace. It
judges loop tickets and proposes defaults. **U3 — the planner** (`/to-tickets`, or the
factory's planning in a repository with `.factory/`), which turns candidates into tickets.
**U4 — `/pr-iterate` and the ruling recorder**, which record rulings and apply defaults. **U5
— the risk rule and the lane** (PRD-09, PRD-10), which read the rulings.

Stories:

1. As the operator, I want a fix the kit made to itself judged against noise, so that a quiet
   week never passes for a working fix and a loud one never condemns a good fix.
2. As the operator, I want every retro fix that edits something, a check or a policy value as
   much as a lens, to carry the measure it will be judged by, fixed when it is proposed.
3. As the operator, I want a retro ticket to land through the lane when it is low risk, and a
   lens edit always to wait for me, so that the loop runs on its own without letting the judge
   rewrite itself.
4. As the operator, I want my rulings on outward items recorded as data, so that the kit can
   see what I keep deciding the same way.
5. As the operator, I want a ruling I have made five times in a row proposed as a default I
   confirm once, so that I stop being asked a question I have already answered.
6. As D-08's factory, I want the retro → ticket handoff to be a checked format, so that my
   planning can read a retro's candidates without reading prose.

**UC1 — A retro fix rides the lane and is judged against noise.** Actor: the operator and the
chain, in the kit. Goal: a recurring failure becomes a check that lands without the operator
and is shown to work.
1. `/retro`'s question 3 finds the self-host check failing for one cause on 6 PRs. It writes a
   candidate block: `Finding:`, `Edits: check self-host`, `Runs:` with the run ids behind the
   evidence, and `Targets: kind=finding.triage data.source=check data.id=Kit-CI-self-host`.
2. The vocabulary checker accepts the block's `Edits:`, `Runs:` and `Targets:` lines, so the
   candidate is filed.
3. `/to-tickets` runs over the report, at its quiz or under the operator's delegating
   instruction. It publishes ticket #950 carrying `Retro: retro-<stamp>`, the `Targets:` line,
   and a `Risk:` stamp of `low` (PRD-09).
4. `/implement` adds the suite assertion. `/pr-iterate` takes PR #951 to green. The risk rule
   prints `effective: low`, and the lane lands it with `merge.land data.via=lane` (PRD-10).
5. A later `/retro`, whose window reaches the landing plus its window length, splits each side
   of the landing into three repeats and prints
   `ticket:#950 Kit-CI-self-host: 0.50 0.40 0.60 → 0.10 0.20 0.00 per PR; mean 0.50 → 0.10,
   pooled SD 0.10 — drop; landed: lane`.
6. It records one `note outcome=closed` naming ticket #950. The section's count line reads
   `loop tickets: drop 1, within noise 0, no drop 0, inconclusive 0, pending 0; via lane 1`.

Extensions:
- 1a. The candidate carries `Edits:` but no `Targets:` or no `Runs:`, or the checker refuses a
  line. It moves to the report's observations and is not filed.
- 1b. The candidate edits a lens (`Edits: lens pattern`). Its PR touches the review skill's
  files, so the lane holds it with `lane: held path`. The operator lands it, and its row reads
  `landed: operator`.
- 5a. The repeats read `0.50 0.10 0.90 → 0.30 0.00 0.60`: mean 0.50 → 0.30, pooled SD 0.35. The
  row reads `within noise`. It is not a finding and records no note. A later retro may judge
  the ticket again.
- 5b. The after-mean is not below the before-mean. The row reads `no drop`, and it is a finding
  naming the ticket, routed to reopen or revert it, as today.
- 5c. A repeat holds fewer than 3 landed PRs. The row reads `inconclusive — fewer than 3 landed
  PRs in a repeat`.
- 5d. The after window is still open. The row reads `pending`, as today.
- 6a. A later retro reads `drop` again. The ticket already has its closed note, so nothing is
  recorded.

**UC2 — The operator rules on an outward item.** Actor: the operator, on PR #960. The PR's
confirm-list holds `⚠️ UNSPECIFIED  trace.sh: exits 3 on an unknown schema` with the arrow line
`→ scope: outward surface: exit-code — …` as item `A2-4`. Goal: the ruling is data, and a
`keep` stops the item holding the PR.
1. The review records its Axis-2 verdict with `data.outward=1` and
   `data.outward_items=A2-4:exit-code`.
2. `/pr-iterate` lists A2-4 verbatim at the top of its report. Beside it are the two ruling
   commands, one for `keep` and one for `change`. It runs neither.
3. The operator runs the `keep` command. The ruling recorder finds A2-4 among the latest Axis-2
   verdict's outward items and reads its surface there. It records `ruling outcome=keep
   subject=pr:#960 data.item=A2-4 data.surface=exit-code data.by=operator`, with the head commit
   the verdict was made at.
4. On the next iteration the risk rule counts one outward item and one item ruled `keep` at that
   head, so it no longer says `outward`. With every area earned, it prints `effective: low`, and
   the lane may land the PR.

Extensions:
- 3a. The item is not among that verdict's outward items (`A2-9`), or the PR has no Axis-2
  verdict. The recorder exits 2 and records nothing.
- 3b. An agent session runs the command, under the operator's standing delegation. The agent-
  harness marker is set, so the recorder records `data.by=session`. The risk rule does not count
  it, and the PR stays `high outward`.
- 3c. The operator runs `change`. The ruling is recorded, and the PR stays `high outward`. The
  change itself is made as it is today, on the operator's word.
- 4a. A new commit moves the head, and the review runs again. Rulings name the old head, so they
  no longer count, and the outward items are listed again.

**UC3 — `/retro` proposes a default from recurring rulings.** Actor: `/retro`. The trace holds
seven operator rulings of surface `exit-code`. The latest five are on five distinct landed PRs
that touch review area `security`, and all five read `keep`. Goal: a proposed default the
operator confirms once.
1. The recurring-rulings section reads every `ruling` event. It maps each PR to its review areas
   through its landing, as the record reader does (ADR-0036).
2. For the pair `security` and `exit-code`, the latest five operator rulings are all `keep`. It
   writes a candidate block: `Finding:`, `Edits: policy risk`, `Runs:`, and `Targets:
   kind=ruling data.by=operator data.surface=exit-code`. The finding names the proposed entry
   `security:exit-code`.
3. The tracker search finds no ticket for it, so the candidate is filed. The section prints
   `rulings: operator 7, session 12, default 0`.

Extensions:
- 2a. Fewer than five operator rulings exist for the pair, or the five are mixed. No proposal.
- 2b. The risk policy at the base branch already holds `security:exit-code`, or the surface is
  `other`. No proposal.
- 2c. The latest five all read `change`. The candidate is `Edits: skill implement` instead. It
  proposes that an unspecified change of that surface in that area is asked before it is
  built, with `Targets: kind=ruling data.by=operator data.surface=exit-code outcome=change`.
- 3a. The tracker holds an earlier proposal for the same pair, closed as not planned (the
  operator declined it). No proposal is made, and the report names that ticket.
- 3b. The tracker holds an open ticket for the pair. The finding folds into it, as `/retro` and
  `/to-tickets` already do.

**UC4 — A ruling default applies on a later PR.** Actor: `/pr-iterate`, on PR #975, which
touches only `scripts/` (review area `security`). The operator has landed `security:exit-code`
in the risk policy's ruling defaults. The lane held that policy PR with `path`, so the operator
landed it themselves. Goal: the item is ruled by the operator's standing decision, and the PR
is not held for it.
1. The review records `data.outward_items=A2-2:exit-code`.
2. `/pr-iterate` runs the ruling recorder with `--defaults`. The recorder reads the ruling
   defaults at the base branch and finds the PR's review areas, `security` only. The pair is
   listed for every one of them, so it records `ruling outcome=keep data.by=default` for A2-2.
3. The risk rule counts A2-2 as ruled and prints `effective: low`. `/pr-iterate`'s report lists
   A2-2 at the top as ruled by default `security:exit-code`.
4. The lane lands the PR, and the operator reads the report afterwards.
5. A later `/retro` judges the default's ticket by its `Targets:` query: operator rulings of
   `exit-code` per landed PR fall, and the row reads `drop`.

Extensions:
- 2a. The PR also touches `tests/` (review area `test-hygiene`), and the defaults hold no
  `test-hygiene:exit-code`. No default is recorded, and the PR stays `high outward`.
- 2b. The risk policy fails closed at the base. No default is recorded, and the fail-closed line
  goes to standard error.
- 2c. The item's surface is `other`. No default ever applies.
- 3a. At the same head, the operator rules A2-2 `change`. The operator's latest ruling wins over
  the default, and the PR is `high outward` again.

**UC5 — A D-08 efficiency proposal enters as a loop ticket.** Actor: the planner, with one of
D-08's efficiency proposals. Goal: the proposal is judged like any retro fix.
1. The planner writes the ticket with a `Targets:` line that counts the events the proposal
   should reduce. It writes no `Retro:` line, because no retro wrote it.
2. The ticket lands through the lane or through the operator.
3. `/retro`'s before-and-after section judges it as in UC1 5–6, since it judges every landed
   ticket with a `Targets:` line.
4. Beside the rows, the section prints the wave's two summed measures: the median tokens priced
   per model, and the median agent wall-clock of `/implement`'s run, from its `run.start` to its
   `run.end` at the open, reviewed PR, over the wave's landed tickets. The time the PR then waits
   for a human is not in it. A proposal that aims at tokens or time is read there, next to its
   count.

Extensions:
- 1a. The proposal's measure is tokens or cost per PR, which a count query cannot express. Its
  `Targets:` line counts the events it should reduce (spawns, re-reviews, iterations), and its
  effect on the sums is read on the summed-measures line of step 4 (§8).
- 4a. A landed ticket has no `/implement` run, or its run has no `run.end`. It is left out of both
  medians, and the line counts how many were left out. A ticket whose tokens hold an unpriced
  model is left out of the token median the same way.

## 3. Model

- **Loop ticket**: a ticket whose stamp carries a `Targets:` line. Its source does not matter.
  `/retro`'s before-and-after section judges it once its after window closes.
- **Repeat**: one third of a side of the landing. With `W` the retro's window length and `T`
  the landing, the before repeats are `[T−W, T−2W/3)`, `[T−2W/3, T−W/3)` and `[T−W/3, T)`, and
  the after repeats are `(T, T+W/3]`, `(T+W/3, T+2W/3]` and `(T+2W/3, T+W]`. A repeat's rate is
  the query's matches in it divided by the landed PRs in it. A stopped run's events are left
  out, as today.
- **Pooled SD**: `sqrt((s_b² + s_a²) / 2)`, where `s_b` and `s_a` are the sample standard
  deviations (divisor 2) of the three before-rates and the three after-rates.
- **Verdict** of a judged row, from the before-mean `B`, the after-mean `A` and the pooled SD
  `S`, compared unrounded: `drop` when `B − A > S`; `no drop` when `A ≥ B`; `within noise`
  otherwise. Rates, means and `S` print to two decimals.
- **Summed measures**: per landed ticket, its **priced tokens**, the cost, priced per model as
  the trace's summary prices it, of the token-bearing events of the run the ticket's
  `/implement` opened and the runs beneath it; and its **agent wall-clock**, from that run's
  `run.start` to its `run.end`, where the run ends at the open, reviewed PR, so no human wait
  after it counts. Reported per wave as two medians, never combined.
- **Loop closed**: a ticket with a `drop` row. It gets one `note outcome=closed`, and later
  retros record nothing more for it.
- **Candidate block**: the retro → ticket handoff contract, a blank-line-separated block in the
  report's findings list. It holds `Finding:`, and, when it edits something, `Edits: <lens|skill|check|policy>
  <name>`, `Runs: <run id> …` and `Targets: <query>`, all checked by the vocabulary checker.
- **Surface**: the closed token an outward item carries after its scope: `output-format`,
  `flag`, `exit-code`, `agent-rule` (decision Q6's list) or `other`. Missing or unknown reads
  `other`.
- **Ruling**: one `ruling` event. Its subject is the PR. Its outcome is `keep` or `change`. Its
  data holds the item id (`A2-<n>`), its surface, the head the verdict was made at, and `by`:
  `operator`, `session` or `default`.
- **Ruling recorder**: the command that records a ruling. Given an item, it takes the surface and
  head from the latest Axis-2 `review.verdict`. Given `--defaults`, it applies the ruling
  defaults. It takes `by` from the environment, never from its caller.
- **Ruling default**: an entry `<review area>:<surface>` in the risk policy's ruling-defaults
  list, shipped empty. It applies to an outward item of that surface on a PR whose every
  review area carries an entry for that surface.
- **Ruled** (for the risk rule): an outward item whose latest ruling at the judged head, by
  `operator`, or by `default` with no later operator ruling, is `keep`.
- **Recurring ruling**: for one review area and one surface other than `other`, the latest 5
  operator rulings on 5 distinct landed PRs touching that area, all with the same outcome.

## 4. Rules

Ids start at runtime/R140 and process/R140, after the blocks the parallel D-02 drafts took. They
are re-based at approval if they collide (§8, Further notes).

Area: runtime

Deltas against `docs/specs/runtime.md`.

### ADDED

runtime/R140. The trace SHALL accept the kind `ruling` with the outcomes `keep` and `change`, subject `pr:#<N>`, carrying `data.item` of the form `A2-<n>`, `data.surface` from the vocabulary's `surface` field, `data.head` of 40 hex digits and `data.by` one of `operator`, `session` and `default`, and SHALL refuse any other outcome or shape, exit 2, writing nothing. [UC2 3]
runtime/R141. The trace SHALL refuse, exit 2, an Axis-2 `review.verdict` whose `data.outward_items` is not a comma-separated list of `A2-<n>:<surface>` entries, or whose entry count differs from its `data.outward`. [UC2 1]
runtime/R142. WHEN the broker records an Axis-2 verdict, it SHALL carry `data.outward_items`, one entry per outward item in confirm-list order, reading each item's surface only as a vocabulary token and as `other` where it is missing or not in the vocabulary. [UC2 1]
runtime/R143. WHEN the ruling recorder runs with a PR, an item id and `keep` or `change`, it SHALL record one `ruling` event with that item's surface as the latest Axis-2 `review.verdict` on the PR lists it, and the head commit that verdict was made at. [UC2 3]
runtime/R144. IF the PR has no Axis-2 verdict, or the item is not among the latest one's outward items, THEN the ruling recorder SHALL exit 2, recording nothing. [UC2 3a]
runtime/R145. The ruling recorder SHALL set `data.by` to `session` when the environment carries an agent-harness marker and to `operator` otherwise, and SHALL exit 2, recording nothing, when its caller supplies a `by`. [UC2 3b]
runtime/R146. The ruling recorder SHALL record nothing when the trace already holds a ruling for the same PR, item, head, `by` and outcome.
runtime/R147. The ruling recorder SHALL print and record only item ids, surface tokens, review area names, PR numbers, commit shas and the words of runtime/R140, and no text from a PR, a comment, a commit message or a ticket.
runtime/R148. IF the trace is unconfigured, THEN the ruling recorder SHALL record nothing, print nothing on standard output, say so on standard error and exit 0.
runtime/R149. The adapter's root guard SHALL refuse an agent's tool call that runs the ruling recorder while unsetting or overriding an agent-harness marker. [UC2 3b]
runtime/R150. The risk policy SHALL ship with an empty ruling-defaults list whose entries take the form `<review area>:<surface>`. [UC4]
runtime/R151. WHEN the ruling recorder runs with `--defaults` and a PR, it SHALL record one `ruling outcome=keep data.by=default` for each outward item at the latest Axis-2 verdict whose surface the ruling defaults pair with every review area the PR's diff from its merge base touches, and none for an item of surface `other`. [UC4 2, 2a, 2c]
runtime/R152. The ruling recorder SHALL read the ruling defaults only through the base-branch policy contract, and SHALL record no default and print the fail-closed line on standard error when that read fails closed. [UC4 2b]
runtime/R153. The ruling recorder SHALL apply no ruling-defaults entry whose area is not a review area of the lens-slice policy or whose surface is not in the vocabulary or is `other`, and SHALL name each such entry on standard error. [UC4 2c]

### MODIFIED

runtime/R59 (added by PRD-09). WHEN the Axis-2 `review.verdict` at the PR's head commit carries more outward items than there are items ruled `keep` at that head (by `operator`, or by `default` with no later `operator` ruling of that item at that head), the rule's risk SHALL be `high outward`; a `session` ruling SHALL never count as ruled. [UC2 4, 3b, 3c, 4a, UC4 3, 3a]

Area: process

Deltas against `docs/specs/process.md`.

### ADDED

process/R140. WHEN a before-and-after row reads `drop`, `/retro` SHALL record one `note outcome=closed` naming the ticket in `related`, and SHALL record none for a ticket the trace already holds one for. [UC1 6, 6a]
process/R141. Each before-and-after row SHALL end with `landed: lane` when the ticket's `merge.land` carries `data.via=lane`, and `landed: operator` otherwise. [UC1 5, 1b]
process/R142. The before-and-after section SHALL end with one line counting its rows by verdict (`drop`, `within noise`, `no drop`, `inconclusive`, `pending`) and the judged tickets that landed through the lane. [UC1 6]
process/R143. The vocabulary checker SHALL accept an `Edits:` line whose value is one of `lens`, `skill`, `check` and `policy` followed by one name token, and a `Runs:` line of one or more run ids in the shape the trace mints, and SHALL refuse any other value, naming the field. [UC1 2]
process/R144. `/retro` SHALL check each candidate block's `Edits:`, `Runs:` and `Targets:` lines with the vocabulary checker before it files the candidate, and SHALL move a block with a refused line to the report's observations. [UC1 2, 1a]
process/R145. `/to-tickets` SHALL carry a retro candidate's `Targets:` line onto its ticket as a stamp line, beside its `Retro:` line, and SHALL NOT publish a ticket from a candidate with an `Edits:` line and no `Targets:` line. [UC1 3]
process/R146. The kit's lane policy SHALL hold every path under the review skill's directory, so that a lens edit lands only through the operator. [UC1 1b]
process/R147. `/review-pr`'s Agent 7 SHALL write, on each ⚠️ UNSPECIFIED item marked `scope: outward`, `surface: <token>` right after the scope, from the vocabulary's `surface` field (`output-format`, `flag`, `exit-code`, `agent-rule`, `other`). [UC2]
process/R148. Every reader of the confirm-list SHALL read an outward item with no surface, or a word the `surface` field does not hold, as `other`. [UC4 2c]
process/R149. WHEN `/review-pr` records its Axis-2 verdict, it SHALL carry `data.outward_items` as runtime/R141 shapes it. [UC2 1]
process/R150. WHEN `/pr-iterate` lists an outward item that is not ruled `keep` at the head, it SHALL print beside it the ruling recorder's command for `keep` and for `change`, filled with the PR and the item id, and SHALL run neither. [UC2 2]
process/R151. WHEN `/pr-iterate`'s review records an Axis-2 verdict at a new head, `/pr-iterate` SHALL run the ruling recorder with `--defaults` before it runs the risk rule. [UC4 2]
process/R152. `/pr-iterate` SHALL list each outward item ruled `keep` by default at the top of its report, with the ruling-defaults entries that ruled it. [UC4 3]
process/R153. WHEN the latest 5 operator rulings of one surface other than `other`, on 5 distinct landed PRs touching one review area, all read `keep`, `/retro` SHALL file one candidate with `Edits: policy risk`, the rulings' run ids in `Runs:`, `Targets: kind=ruling data.by=operator data.surface=<surface>`, and the entry `<area>:<surface>` named in its finding. [UC3 1, 2]
process/R154. WHEN those 5 rulings all read `change`, `/retro` SHALL file one candidate with `Edits: skill implement`, proposing that an unspecified change of that surface in that area is asked before it is built, with `Targets: kind=ruling data.by=operator data.surface=<surface> outcome=change`. [UC3 2c]
process/R155. `/retro` SHALL propose no ruling default for a pair with fewer than 5 operator rulings, with mixed outcomes among its latest 5, of surface `other`, or already in the risk policy's ruling defaults at the base branch. [UC3 2a, 2b]
process/R156. IF the tracker holds a proposal for the same pair closed as not planned, THEN `/retro` SHALL NOT propose it again, and SHALL name that ticket in its report. [UC3 3a]
process/R157. `/retro` SHALL count only `operator` rulings toward process/R153 and R154, and SHALL print the window's rulings counted by `by`. [UC3 3]
process/R158. For each ticket landed in its window, `/retro` SHALL measure its priced tokens, the cost the trace's summary prices, per model, for the token-bearing events of the run the ticket's `/implement` opened and the runs beneath it, and its agent wall-clock, from that run's `run.start` to its `run.end`, the run ending at the open, reviewed PR, and SHALL NOT run the wall-clock to the ticket's `merge.land`. [UC5 4]
process/R159. The before-and-after section SHALL print one line holding the median priced tokens and the median agent wall-clock over the window's landed tickets, beside its rows' counts, each measure on its own and never folded with the other or with a count into one score, and SHALL leave out of a median, and count on that line, a ticket with no `/implement` run, a run with no `run.end`, or, for the token median, an unpriced model. [UC5 4, 4a]
process/R160. `/retro` SHALL report no operator wait (approve, review or QA) as a measure of a loop ticket or of a wave: those waits are the factory's gate-time metrics and measure the operator, not the change. [UC5 4]

### MODIFIED

process/R25. WHEN a landed ticket carries a `Targets:` line, `/retro` SHALL split the window before its landing, and an equal window after, into three equal consecutive repeats each, and SHALL report the query's count per landed PR in each of the six repeats, each side's mean, and the pooled SD, the square root of the mean of the two sides' sample variances. [UC1 5]
process/R26. IF the two windows of R25 differ in tier → model mapping or in kit version, or a repeat holds fewer than 3 landed PRs, THEN `/retro` SHALL report the comparison as inconclusive with its reason, and SHALL leave failed runs out of every count. [UC1 5c]
process/R27. `/retro` SHALL read a row as `drop` when its before-mean minus its after-mean is greater than the pooled SD, `no drop` when its after-mean is not below its before-mean, and `within noise` otherwise, and SHALL file a finding naming the ticket for a `no drop` row only. [UC1 5, 5a, 5b]
process/R28. A candidate `/retro` proposes with an `Edits:` line, whether it edits a lens, a skill, a check or a policy, SHALL cite the trace events behind it by run id in `Runs:` and carry its `Targets:` line, and SHALL NOT be filed without them. [UC1 1, 1a]

## 5. Slices (vertical, demoable, in order)

Every slice waits for PRD-10's slice 2 (the lane), PRD-09's risk rule and PRD-08's base-branch
reader. A slice that changes the trace's kind table, the vocabulary policy or the risk policy
moves a `VERSION`-listed file, so it is a shared-layer release, one per frontier (ADR-0033).

**Slice 1 — the eval-gated before-and-after check.** The tracer bullet: an existing loop ticket
judged against noise, end to end, from the trace a retro already reads.
- *Covers:* process/R25, process/R26, process/R27 (modified), process/R140, process/R141, process/R142, process/R158, process/R159, process/R160.
- *Also:* the decision record for this PRD (§8), and glossary entries for loop ticket, repeat,
  pooled SD, loop closed, priced tokens and agent wall-clock.
- *Accept:* the retro suite's fixture trace prints UC1's row with `0.50 0.40 0.60 → 0.10 0.20
  0.00`, `pooled SD 0.10`, `drop` and `landed: lane`, and records one closed note, and a second
  run records none. A fixture with `0.50 0.10 0.90 → 0.30 0.00 0.60` prints `pooled SD 0.35 —
  within noise` with no finding. A fixture with equal means prints `no drop` and a finding. A
  repeat holding 2 landed PRs prints `inconclusive — fewer than 3 landed PRs in a repeat`. The
  count line matches the fixtures. A fixture wave of three landed tickets with known token
  events and `/implement` run start and end times, each landed later, prints the median priced tokens and the median agent
  wall-clock as two separate values. The wall-clock median ignores the time from a run's end to its
  landing. A ticket with no `/implement` run, and one whose tokens hold an unpriced model, are left out of the median they cannot enter and counted on the line.
  No line prints an operator wait or a combined score.

**Slice 2 — every edit carries its measure, and lens edits wait for the operator.**
- *Covers:* process/R28 (modified), process/R143, process/R144, process/R145, process/R146.
- *Blocked by:* slice 1.
- *Accept:* the vocabulary suite accepts `Edits: check self-host` and `Runs: <a minted run id>`,
  and refuses `Edits: prose x` and a malformed run id. A retro fixture report with a `check`
  candidate missing `Targets:` lists it under observations. The `/to-tickets` suite publishes a
  candidate's ticket with its `Targets:` and `Retro:` lines, and refuses one without
  `Targets:`. The landing script's suite holds a fixture PR touching the review skill with
  `lane: held path`.

**Slice 3 — rulings recorded, and a `keep` ruling lifts `outward` (shared-layer release).**
- *Covers:* runtime/R140, runtime/R141, runtime/R142, runtime/R143, runtime/R144, runtime/R145, runtime/R146, runtime/R147, runtime/R148, runtime/R149, runtime/R59 (modified), process/R147, process/R148, process/R149, process/R150.
- *Blocked by:* slice 1.
- *Accept:* in a fixture repository, UC2's flow records one `ruling` with `data.by=operator`,
  and the risk rule then prints no `outward`. The same command with an agent-harness marker set
  records `by=session`, and the rule still prints `high outward`. A ruling naming an older head
  does not count. `A2-9` exits 2. A second identical run records nothing. A caller-supplied `by`
  exits 2. The trace suite refuses a verdict whose item count differs from `data.outward`. The
  root guard's suite refuses an agent call that overrides the marker. A skill-text suite holds
  Agent 7's `surface:` words and `/pr-iterate`'s two printed commands.

**Slice 4 — ruling defaults applied (shared-layer release).**
- *Covers:* runtime/R150, runtime/R151, runtime/R152, runtime/R153, process/R151, process/R152.
- *Blocked by:* slice 3.
- *Accept:* with `security:exit-code` in a fixture base-branch risk policy, UC4's PR gets one
  `by=default` keep, the rule prints `effective: low`, and the report lists the entry. Adding a
  `tests/` path records no default. A missing risk policy records none and prints the
  fail-closed line. An entry `security:other` or `nosuch:flag` is named on standard error and
  not applied. An operator `change` at the same head makes the rule print `high outward` again.

**Slice 5 — `/retro` proposes defaults from recurring rulings.**
- *Covers:* process/R153, process/R154, process/R155, process/R156, process/R157.
- *Blocked by:* slice 4.
- *Accept:* the retro suite's fixture trace with UC3's seven rulings files one `Edits: policy
  risk` candidate naming `security:exit-code`, with the `Targets:` line of process/R153 and
  passing the vocabulary checker. Four rulings, a mixed five, `other`, or a pair already in the
  defaults files nothing. Five `change` rulings file an `Edits: skill implement` candidate. A
  stubbed tracker holding a closed-as-not-planned proposal files nothing and names it.
  `session` and `default` rulings are counted in the printed line and never toward a proposal.

## 6. Non-goals (this PRD)

- **D-08's eval gate: a pre-landing eval of a skill or lens change.** *Later*, as its own PRD
  (operator, 2026-10-31). It runs before the change lands, solves a fixed task set at least 3
  times with the change and at least 3 times without it, and accepts the change only when the
  gap exceeds the pooled SD (D-08 research.md lines 45–47, 421–423 and 666–667; proposals.md
  lines 153 and 226–228). It needs an eval harness the kit does not have. What reopens it: a
  PRD of its own, written once the low-risk lane has a record; until then process/R146 keeps
  every lens edit with the operator. This PRD's check is not that gate (§8).
- **Publishing a retro's candidates without the `/to-tickets` quiz.** *Not here*. The quiz stays
  the checkpoint between a retro's reading and the tracker. The operator can already delegate it
  by instruction, and "automatic" here means no new human step after it (§8).
- **`/retro` reverting or reopening a ticket itself on `no drop`.** *Never*: `/retro` never fixes
  (ADR-0024 clause 7). The finding goes to `/to-tickets`.
- **A `no drop` counted as a mistake.** *Never* without the operator: decision Q2's list of
  three is closed.
- **Learning from the words of a ruling or a comment.** *Never* (trust boundary). A ruling is an
  item id, a surface token and `keep` or `change`.
- **Defaults that raise risk, or that turn an outward item into an inside one at review.**
  *Later*. A default only records a `keep` ruling. Agent 7's scope words are unchanged.
- **Counting the session's delegated rulings toward a default or toward risk.** *Later*, if ever
  (§8). They share the judge's model family (D-02, "who labels lens findings").
- **A default for surface `other`.** *Never*: it names no kind of change.
- **Summed measures (tokens, cost) in the `Targets:` grammar.** *Not here*: the two summed
  measures are reported beside the counts, per wave (process/R158–R160), and `Targets:` stays a
  count query (§8).
- **One score combining tokens, wall-clock and counts.** *Never* (§8).
- **The operator's waits as a measure of a change.** *Never* here: they are the factory's
  gate-time metrics (`factory stats`) and measure the operator (§8).
- **Area × tier as the change kind; a learned model of risk.** *Later* (operator, 2026-10-23).

## 7. Technical constraints and testing

- POSIX `sh`, `git` and `awk`, like the trace and `/retro`'s pipelines. The repeat arithmetic,
  including the square root, runs in `awk`. Comparisons use unrounded values, and printing uses
  two decimals.
- **Trust boundary.** The ruling recorder acts on the trace and reads no prose. It takes the
  surface from the trace's own `review.verdict`, holds the item id to `A2-[0-9]+` and the outcome
  to two words, and takes `by` from the environment. The broker reads a surface from the review
  report only as a vocabulary token. `/retro` and `/to-tickets` read a candidate block only
  through the vocabulary checker. Ticket bodies, PR bodies and comments are never read into a
  command.
- **`by` is a tripwire, not a proof.** An agent's tool call that clears the agent-harness marker
  is refused by the root guard (runtime/R149), but a process outside the adapter could still
  claim `operator`. That is the same limit the pre-commit hook states, and it is accepted here
  because a false `operator` ruling only lifts `outward` on one PR whose areas are already
  earned.
- **Readers.** The ruling recorder, run by `/pr-iterate`, reads the trace and the base-branch
  risk policy. That is a chain-run reader, so it needs the amendment of ADR-0024 clause 7 that
  §8 records, as PRD-10 needed for the lane.
- **Tests.** The retro suites drive fixture traces with timed landings and query matches, and
  assert on printed rows, findings and notes. The ruling recorder's suite uses a fixture trace,
  a fixture base-branch risk policy, and the environment with and without a marker. The risk
  rule's suite gains the ruled-item cases. New trace kinds and fields join the trace suite's
  row-for-row table check (ADR-0024 clause 1).
- **Numbers:** 3 repeats a side; at least 3 landed PRs per repeat; `drop` only beyond 1 pooled
  SD; 5 operator rulings on 5 distinct landed PRs for a proposal; one closed note per ticket; a
  second run of the recorder or of `/retro` writes 0 lines.

## 8. Decisions recorded for this PRD

**From D-02** (decisions.md, proposals.md, 2026-10-23): the operator's second idea, and Option
3's stage ⑥. The loop's shape in four steps: the retro proposes; the proposal becomes a ticket;
the fix is a check, a policy value or a skill line carrying a `Targets:` query; the
before-and-after section proves it worked or reopens it. "Automatic" means the cycle runs
through the same lane as any ticket. A preference is learned when an operator ruling recurs: the
retro proposes a default, and the operator's ruling on that proposal is the label (S-12). Also
Q1, Q2, Q5, Q6 and Q7 (K6 fifth, after K5), and the work split with D-08 ("its efficiency
proposals enter as tickets under K6").

**Already fixed, not reopened:** ADR-0024 clause 7 (`/retro` never fixes; the chain does not
read the trace except where a record allows it), ADR-0036, ADR-0037, ADR-0038, process/R25–R28
as they stand until modified here, PRD-09's risk rule and PRD-10's lane, hold list and lane
policy.

**Settled after approval** (T-59): **how D-08's efficiency proposals are measured** (the
session under the operator's delegation, 2026-10-31, on D-08's recommendation). A summed
measure exists beside the findings-per-proposal count, as two metrics per landed ticket: the
tokens priced per model, from the kit's own trace (the session hooks' token records, as the
trace's summary reads them), grouped by the run the ticket's `/implement` opened; and the agent
wall-clock of that run, from its `run.start` to its `run.end`, the run ending at the open,
reviewed PR, and never to `merge.land`, so the human's time after the PR opens is left out
(the session under the operator's delegation, 2026-10-31, on review of T-59). The operator's waits (approve,
review and QA) are excluded: they are the factory's gate-time metrics (`factory stats`) and
measure the operator, not the proposal. `/retro` reports the median of each per wave next to
the counts, and never a single combined score. `Targets:` stays a count query, so a proposal
still enters as a loop ticket through a count proxy (UC5 1a). This closes §9's question and
adds process/R158–R160 to slice 1.

**Settled after approval** (the rest of §9's questions, closed 2026-10-31):

- **T-60's check is a post-landing noise check, not D-08's eval gate** (operator, 2026-10-31).
  "Eval-gated, three repeats, pooled SD" is defined nowhere in D-02; D-08 defines it as a
  pre-landing eval of a skill or lens change, solved at least 3 times with the change and at
  least 3 times without it, accepted only when the gap exceeds the pooled SD (D-08 research.md
  lines 45–47 and 421–423; proposals.md line 153). This PRD's three sub-windows a side read the
  trace after the landing and gate nothing: they say whether a landed fix moved its count beyond
  noise. T-60 (#923) is kept as written. D-08's eval gate is §6's *later* item, a PRD of its own;
  meanwhile process/R146 keeps every lens edit with the operator.
- **Preference learning counts operator rulings only, and stays idle while the operator
  delegates** (the session under the operator's delegation, 2026-10-31, on D-02's record and
  the D-08 session's recommendation). D-02 decisions.md, "who labels lens findings", excludes the
  session's rulings because they share the judge's model family; runtime/R145 and process/R157
  already count only `operator`. The operator can rule any item at any time with the commands
  `/pr-iterate` prints (process/R150). Counting a session ruling after a clean fix window would
  label the PR's outcome, not the operator's preference.
- **`within noise` stays report-only** (the session under the operator's delegation,
  2026-10-31). Nothing argues for acting before real rows exist; revisit at the first `/retro`
  after slice 1.
- **The numbers stay fixed in the skill** (the session under the operator's delegation,
  2026-10-31). Revisit if the first real rows are mostly `inconclusive`. The factory defines no
  such key, so K7's manifest rule does not apply.
- **A ruling counts only at the head it names** (the session under the operator's delegation,
  2026-10-31). Carrying a ruling forward would let a later diff inherit a `keep` it never got;
  re-rulings are counted in the first waves after slice 3 before anything changes.

**Derived while writing** (the session, under the operator's standing delegation of rulings;
the maintainer confirms them at approval):

- **"Three repeats, pooled SD" is read as three sub-windows a side.** D-02's text uses the phrase
  once (brief.md, K6) and defines it nowhere. This repository holds no eval harness that could
  replay a task three times, so the reading that uses the trace `/retro` already reads is: three
  equal repeats a side, and a drop that has to beat one pooled SD. With n = 3 this is a coarse
  gate. It is chosen because it is cheap, it can be checked against a fixture, and it stops the
  commonest false result, a single quiet window. The other reading was settled after approval:
  it is D-08's pre-landing eval gate, deferred (see "Settled after approval" and §6).
- **`within noise` is reported, not a finding.** A fix that did no measurable harm is not
  reopened on noise. Its loop simply stays open, with no closed note.
- **A loop ticket is keyed on its `Targets:` line, not on where it came from.** This is how
  D-08's efficiency proposals enter under K6: as tickets with a `Targets:` line, written by the
  factory's planning or by `/to-tickets`, and judged by the same section. No new path is needed.
- **The candidate block is the retro → ticket contract** (D-02's boundary condition 3), held by
  the vocabulary checker so that the factory reads fields, not prose.
- **Lens edits always wait for the operator.** A lens is the instrument the earned record is
  measured with, so a lane that lets the judge rewrite itself would make the record
  self-certifying. This is a kit lane-policy value, not a new hold token.
- **Rulings come from a recorder, with `by` taken from the environment.** The agent posts to the
  forge under the operator's login, so a comment's author cannot tell the two apart. The
  agent-harness marker the pre-commit hook already uses can.
- **Only `operator` and `default` rulings lift `outward`.** A `keep` from the operator answers
  Q6's question for that item. A default is the operator's answer given in advance, confirmed by
  landing a policy file that the lane always holds for them. A delegated session's ruling would
  let the chain lower its own risk, which Q6 forbids.
- **A ruling counts only at the head it names.** It is the conservative choice. Carrying rulings
  across heads was settled after approval (per head; see "Settled after approval").
- **A default is per review area, and it must cover every area the PR touches.** This follows
  Q4: the riskiest area judges.
- **Five rulings in a row.** This is a quarter of Q3's 20-landing window. Mixed outcomes reset
  it, and a declined proposal is never re-proposed (the operator's ruling on the proposal is the
  label).
- **One new decision record** (slice 1). It defines the loop ticket and the eval gate. It adds
  the `surface` field, the `Edits:` and `Runs:` contract fields, and the `ruling` kind. It
  amends ADR-0024 clause 7 and ADR-0036's caller list for the ruling recorder as a chain-run
  reader, and ADR-0037's ticket contract for the candidate block. It is written as a new record,
  because those records are at or near their amendment cap.

**Alternatives considered:**

- **A significance test (Welch's t, a p-value).** With three repeats a side, it would almost
  never pass. One pooled SD is the plainer bar, and it is the one D-02 named.
- **Reading rulings from `Ruling:` lines in the operator's PR comments.** This was rejected. The
  comment is untrusted forge text, and its author login is shared with the agent.
- **Defaults as one global list per surface.** This was rejected because it ignores Q4's areas.
- **Auto-publishing loop candidates under a standing authorisation.** Rejected for this PRD (§6).

**Further notes.** Requirement ids start at runtime/R140 and process/R140. PRD-06 to PRD-10 and
PRD-13 took runtime/R31–R69, R80–R103 and R200+, process/R37–R68, R80–R85 and R120+, and
policy/R1–R33. These ids are re-based at approval if they collide. The MODIFIED runtime/R59
follows PRD-09's final id.

## 9. Unresolved questions

None. Every question was settled after approval (§8, 2026-10-31).

## 10. Dogfood plan

Five tickets in slice order. Slices 3 and 4 are releases in frontiers of their own. After slice
1, the next `/retro` re-judges every loop ticket already landed (the kit has lens and skill
edits with `Targets:` lines since process/R25), so the first rows show how many of them were
noise. After slice 3, the operator rules outward items with the printed commands, and the
first `/retro` after five such rulings for one pair shows the proposal. When the operator lands
the first default, the loop judges itself: the default's own ticket is a loop ticket, and its
row says whether the operator was asked less.
