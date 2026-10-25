---
id: PRD-06
type: prd
title: Post-merge outcomes in the trace, and each area's earned record
parent: D-02
stage: approved
created: 2026-10-23
updated: 2026-10-25
approved_by: "agranado"
approved_at: 2026-10-25
---

# PRD-06 · Post-merge outcomes in the trace, and each area's earned record

## 1. Objective

Record in the trace what happened to each landed PR after its merge (reverted, fixed within 30
days, or failed its factory QA), and report for each review area how often its reviews missed a
mistake and how many of its lens findings held up, so the kit can measure which reviews to trust.

**Problem.** The chain stops for the operator at every merge (shared invariant §7), but the
operator already delegates those rulings to the session (ADR-0016), so on most PRs the stop is a
formality. On the rest it protects nothing that anyone can see: the trace records what the chain
decided up to `merge.land` and nothing after it. No event says that a PR was reverted, that a
fix two weeks later rewrote its lines, or that its ticket failed QA. So nobody can say which
review lenses catch real mistakes and which only make noise, in which part of the repository.
`/retro`'s question 2 counts how the implementing session triaged each finding, but that label
comes from the same model family as the reviewer (D-02 research S-26), and it never looks past
the merge.

**Solution.** This is the first PRD of D-02's earned-autonomy plan (K1; decisions Q2–Q4, Q7).
A new trace kind, `merge.outcome`, records each **mistake** against the PR it happened to. An
**outcome recorder**, which reads git and the trace, writes those events. It is idempotent, so
its first run backfills every landing the trace already holds a merge sha for (224 at the time
of writing), and the 20-landing window is full from day one. A **record reader** computes each
review area's **earned record** on read: its last 20 landings, the mistakes among them, the
ones the review missed, and its lens findings' precision. `/retro` runs both and prints the
record. K1 measures and reports, and nothing more. No threshold is compared, no PR is labelled
low or high risk, and no chain skill reads the record: that is K2 (thresholds as base-branch
policy), K3 (the risk rule) and K5 (the lane).

**The test of done.** In a fixture repository, a PR is landed, a `revert:` landing removes its
lines, and `/retro` is run. The trace then holds `merge.outcome outcome=reverted subject=pr:#<N>`,
a second `/retro` adds nothing, and the record prints that PR's areas with one mistake each. On
the kit itself, the first `/retro` after slice 1 prints a record for every review area of the
lens-slice policy.

## 2. Users and scenarios

**U1 — the operator**, reading `/retro` and deciding later (through K2/K3) where to trust the
review. **U2 — `/retro`**, the one skill that reads the trace (ADR-0024 clause 7). **U3 — a
later risk rule (K3)**, which will read the record this PRD defines.

Stories:

1. As the operator, I want every revert, every later fix and every failed QA recorded against the
   PR it undid, so that a landed PR's fate is data rather than memory.
2. As the operator, I want each review area's miss rate and lens precision over its last 20
   landings, so that I can see which areas' reviews have earned trust before any lane opens.
3. As the operator, I want the precision label to come from what happened after the merge, not
   only from the implementing session's triage, so that a reviewer is not judged by its own
   family (D-02 decision 2026-10-23, "who labels lens findings").
4. As the author of K3, I want the record to have a fixed, recorded definition and no risk
   words in it, so that the risk rule can be built on it without redefining it.

**UC1 — A revert is counted against its PR.** Actor: the operator, after PR #866 (touching
`scripts/` and `tests/`) landed and PR #870, titled `revert: …`, landed three days later. Goal:
the trace says #866 was reverted, and the record counts it.
1. The operator runs `/retro` for the week.
2. `/retro`'s question 2 runs the outcome recorder. It finds #870's merge commit through the
   `merge.land` event that names it, reads the Conventional Commit type `revert`, and blames the
   lines #870 removed at #870's first parent. The lines resolve to commits that #866's landing
   brought in, and #866's merge commit is the `data.merge_sha` of #866's `merge.land`.
3. It writes `merge.outcome outcome=reverted subject=pr:#866 related=pr:#870` with
   `data.by_sha` = #870's merge commit and `data.files` = the files whose lines it removed.
4. `/retro` prints the earned record: one row per review area. The `security` and
   `test-hygiene` rows show `mistakes 1`, because #866 touched paths in both.
5. The next day the operator runs `/retro` again. The recorder finds the same evidence already
   recorded and writes nothing.

Extensions:
- 2a. #866 only deleted lines, so #870 removes none. The recorder takes the reverted commit from
  #870's merge commit message only as a 40-hex sha, checks with git that it lies on the base
  branch's first-parent history and that `merge.land` names it, and records the revert. A message
  with no such sha, or one that does not resolve, records nothing.
- 2b. Some blamed lines come from a landing older than the trace's first `merge.land` with a merge
  sha. No outcome is written for them, and the recorder prints how many lines it could not
  attribute on standard error.
- 2c. The trace is unconfigured. The recorder writes nothing and exits 0.

**UC2 — A later fix is counted, inside the fix window only.** Actor: the operator. PR #880,
titled `fix(trace): …`, landed 12 days after #866 and rewrote two lines #866 introduced. It also
rewrote one line from #801, which landed 41 days earlier. Goal: #866 carries a fix outcome and
#801 does not.
1. The recorder reads #880's type, `fix`, and blames the lines #880 removed or rewrote, at its
   first parent.
2. Two lines resolve to #866, landed 12 days before #880. It writes `merge.outcome outcome=fixed
   subject=pr:#866 related=pr:#880`, with `data.days=12`.
3. One line resolves to #801, landed 41 days before. That is past the 30-day fix window, so
   nothing is written for #801.

Extensions:
- 1a. #880's title names #866 in prose (`fixes the bug from #866`). That prose is never read.
  The blame alone decides which PR the fix is against.
- 1b. A landing typed `feat`, `refactor` or anything but `fix` or `revert` touches #866's lines.
  It is not a fix, and no outcome is written.

**UC3 — A failed factory QA is counted.** Actor: the operator, in a repository with a `.factory/`
folder. Ticket T-31 has `links.pr: "#890"`, and the operator ran `factory qa T-31 --outcome fail`.
Goal: #890 carries a QA outcome.
1. The recorder reads each factory ticket's `qa.outcome` and `links.pr` fields, and no other
   field and no body text.
2. T-31 reads `fail` and `#890`. It writes `merge.outcome outcome=qa-failed subject=pr:#890` with
   `data.ticket=T-31`.

Extensions:
- 1a. The repository has no `.factory/` folder. This step is skipped, silently.
- 2a. `links.pr` does not have the shape `#<digits>`, or names a PR with no `merge.land`. Nothing
  is written, and the ticket's id is printed on standard error.

**UC4 — Read an area's earned record.** Actor: the operator, reading `/retro`'s question 2.
Goal: know, for `test-hygiene`, how often the review missed a mistake and how often its
findings held up.
1. The record reader takes the 20 most recent landed PRs whose diff touches a path the
   `test-hygiene` rule of the lens-slice policy selects.
2. Of those 20, 6 landed less than 30 days ago and are still inside the fix window. 1 carries a
   mistake (#866, reverted).
3. #866's review raised `H-1` on `tests/trace.test.sh:120`, and the session rejected it. #870
   removed lines from `tests/trace.test.sh`, so the review is counted as having caught the
   mistake: the miss belongs to the triage, not the review. The row shows `missed 0 of 20`.
4. Over the same 20 PRs, findings whose `data.where` path the rule selects: 14 accepted, 3
   rejected, 1 dismissed by a human, and 2 escalated, which are unlabelled. `H-1` is rejected
   but vindicated by #866's revert, so it counts as held up. The row shows `held up 15 of 18`,
   `precision 0.83`, and the labels' sources: `triage 17, human 1, outcome 1`.
5. The row carries no `low` or `high` and no threshold.

Extensions:
- 1a. Fewer than 20 landings touched the area. The row counts the ones there are, and says so
  (`landings 7 of 20`).
- 3a. The mistake is `qa-failed`, so no file is implicated. It counts as missed.
- 4a. No finding in the area is labelled. Precision prints `n/a`, never `0` or `1`.

## 3. Model

- **Post-merge outcome**: one `merge.outcome` event, subject `pr:#<N>`, the PR it happened to.
  Its outcomes are `reverted`, `fixed` and `qa-failed`. `related` names the evidence PR where
  there is one. `data.by_sha` is the evidence landing's merge commit, `data.files` the files it
  touched in the PR's lines, `data.days` the days from the PR's landing to the evidence's, and
  `data.ticket` the factory ticket for `qa-failed`.
- **Mistake** (decision Q2): a landed PR with at least one post-merge outcome. That is, (1) a later
  `revert` landing removed lines it introduced, or reverted it by sha; (2) a `fix` landing within
  30 days removed or rewrote lines it introduced, as git blame at the fix's first parent says;
  or (3) its factory ticket's QA gate reads `fail`. A revert has no time window. A fix has 30
  days.
- **Review area** (decision Q4): one record of the lens-slice policy, named by its lens token. A
  path belongs to every area whose include pattern matches it and whose exclude does not. The
  word is "review area", never bare "area", which the glossary already gives to a living spec.
- **Earned record**: per review area, computed on read and stored nowhere. It holds the area's
  last 20 landed PRs (`merge.land outcome=landed` with a merge sha), how many are still inside
  the fix window, how many carry a mistake, how many carry a **missed** mistake, the **miss
  rate** (PRs with a missed mistake over the PRs counted), and lens **precision** with its
  label sources.
- **Missed** (by the review): a mistake is caught when a finding raised on that PR, and not
  upheld at triage, names a file in the outcome's `data.files`. Any other mistake is missed, and
  a `qa-failed` one always is.
- **Held up** (a lens finding): its triage is `accepted`, or a mistake against its PR names its
  `data.where` file. **Did not hold up**: rejected at triage, or dismissed by a human
  (`finding.dismiss`), with no mistake that vindicates it. Every other finding (escalated,
  answered, never triaged) is unlabelled and left out of the ratio.

## 4. Rules

Area: runtime

Deltas against `docs/specs/runtime.md`, which ends at R30.

### ADDED

runtime/R31. The trace SHALL accept the kind `merge.outcome` with the outcomes `reverted`, `fixed` and `qa-failed`, and SHALL refuse any other outcome on it, exit 2, writing nothing. [UC1 3]
runtime/R32. WHEN the outcome recorder runs, it SHALL write one `merge.outcome outcome=reverted` against each landed PR that introduced a line a later landing of Conventional Commit type `revert` removed, as git blame at that landing's first parent attributes the line, with the reverting PR in `related` and its merge commit in `data.by_sha`. [UC1 2, 3]
runtime/R33. IF a `revert` landing removes no line, THEN the recorder SHALL take the reverted commit only from a 40-hex sha in the landing's merge commit message that lies on the base branch's first-parent history and that a `merge.land` names, and SHALL write nothing when none does. [UC1 2a]
runtime/R34. WHEN the outcome recorder runs, it SHALL write one `merge.outcome outcome=fixed` against each landed PR that introduced a line a landing of type `fix` removed or rewrote within the fix window after the PR landed, with `data.days` the days between the two landings. [UC2 1, 2]
runtime/R35. IF a `fix` landing touches a line of a PR that landed before the fix window, THEN the recorder SHALL write no outcome against that PR. [UC2 3]
runtime/R36. The fix window SHALL be 30 days unless the trace's policy file sets another whole number of days.
runtime/R37. WHERE the repository holds a `.factory/` folder, WHEN the recorder runs, it SHALL write one `merge.outcome outcome=qa-failed` against the PR a ticket's `links.pr` names when that ticket's `qa.outcome` is `fail`, with the ticket's id in `data.ticket`. [UC3 1, 2]
runtime/R38. IF a factory ticket's `links.pr` is not `#<digits>`, or names a PR with no `merge.land`, THEN the recorder SHALL write nothing for that ticket and print its id on standard error. [UC3 2a]
runtime/R39. The recorder SHALL map a landed commit to its PR only through a `merge.land` event's `data.merge_sha`, and SHALL read from commit messages and factory items nothing but the Conventional Commit type token, a 40-hex sha, `qa.outcome` and `links.pr`, each held to its shape, so that a PR number written in prose produces no outcome. [UC2 1a]
runtime/R40. A landing whose Conventional Commit type is neither `fix` nor `revert` SHALL produce no outcome. [UC2 1b]
runtime/R41. The recorder SHALL write no outcome the trace already holds for the same PR, outcome and evidence (`data.by_sha`, or `data.ticket` for `qa-failed`), so that a second run over the same history writes nothing. [UC1 5]
runtime/R42. IF a blamed line resolves to a landing that no `merge.land` with a merge sha names, THEN the recorder SHALL write no outcome for that line and SHALL print the count of such lines on standard error. [UC1 2b]
runtime/R43. IF the trace is unconfigured, THEN the recorder and the record reader SHALL write nothing, print nothing on standard output, and exit 0. [UC1 2c]
runtime/R44. WHEN the record reader runs, it SHALL print one row per review area of the lens-slice policy, holding the area's landed PRs counted (its most recent 20, or fewer, said as `<n> of 20`), how many of them landed inside the fix window, and how many carry a mistake. [UC1 4, UC4 1, 2, 1a]
runtime/R45. The record reader SHALL count a landed PR toward every review area that one of the paths its merge commit changed against its first parent belongs to. [UC1 4]
runtime/R46. The record reader SHALL count a mistake as missed unless a finding raised on that PR, not upheld at triage, names a file in the outcome's `data.files`, and SHALL always count a `qa-failed` mistake as missed. [UC4 3, 3a]
runtime/R47. The record reader SHALL print, per review area, the PRs with a missed mistake and the miss rate over the PRs counted. [UC4 3]
runtime/R48. The record reader SHALL count a finding toward every review area its `data.where` path belongs to, as held up when its triage is `accepted` or a mistake against its PR names its file, as not held up when it was rejected at triage or dismissed by a human with no such mistake, and as unlabelled otherwise. [UC4 4]
runtime/R49. The record reader SHALL print, per review area, the findings held up, not held up and unlabelled, the precision (held up over labelled), and the count of labels from triage, from a human dismissal and from a post-merge outcome. [UC4 4]
runtime/R50. IF a ratio's denominator is zero, THEN the record reader SHALL print `n/a` for it. [UC4 4a]
runtime/R51. The record reader SHALL compare no number to a threshold, SHALL print no risk word, and SHALL write nothing to the trace or to any file. [UC4 5]

Area: process

Deltas against `docs/specs/process.md`, which ends at R36.

### ADDED

process/R37. `/retro`'s question 2 SHALL run the outcome recorder, then print the record reader's rows for its window, before its existing per-lens triage counts. [UC1 1, 4]

## 5. Slices (vertical, demoable, in order)

Each slice that changes the trace's kind table moves a `VERSION`-listed file, so it is a
shared-layer release. ADR-0033 chains them one per frontier, and the order below is that chain.

**Slice 1 — reverts recorded, and the record shown by `/retro`.** The tracer bullet: one
outcome, end to end.
- *Covers:* runtime/R31, runtime/R32, runtime/R33, runtime/R39, runtime/R40, runtime/R41, runtime/R42, runtime/R43, runtime/R44, runtime/R45, process/R37.
- *Also:* the decision record that amends ADR-0024 (§8), and the glossary entries: post-merge
  outcome, mistake, review area, earned record.
- *Accept:* in a fixture repository with a fixture trace, a `revert:` landing gives one
  `reverted` event, and a second run gives none. A pure-deletion revert is found by its sha. A
  commit message naming `#99` in prose gives nothing for #99. The record prints one row per
  lens-slice rule, with `mistakes 1` on the areas the reverted PR touched. A `/retro` suite
  asserts that question 2 runs both. The full run over the kit's own trace is measured and its
  duration recorded in the diary as the baseline.

**Slice 2 — later fixes inside the fix window.**
- *Covers:* runtime/R34, runtime/R35, runtime/R36.
- *Accept:* fixture landings at 12 and 41 days give `fixed` for the first only. A policy value
  of 7 days drops the 12-day one.

**Slice 3 — failed factory QA.**
- *Covers:* runtime/R37, runtime/R38.
- *Accept:* a fixture `.factory/` with a `qa.outcome: fail` ticket gives `qa-failed` on its PR.
  A malformed `links.pr` gives nothing and the ticket id on standard error. No `.factory/` gives
  nothing, silently.

**Slice 4 — misses and precision.**
- *Covers:* runtime/R46, runtime/R47, runtime/R48, runtime/R49, runtime/R50, runtime/R51.
- *Accept:* UC4's fixture prints `missed 0 of 20`, `held up 15 of 18`, `precision 0.83` and
  `triage 17, human 1, outcome 1`. An area with no labelled finding prints `n/a`. No row holds
  `low` or `high`.

## 6. Non-goals (this PRD)

- **The risk rule, the thresholds (1 in 20, 80%), the lane, the kill switch** — *later*: K2 holds
  the thresholds in base-branch policy, K3 compares the record against them, and K5 opens the
  lane. K1 prints numbers only (runtime/R51).
- **Area × tier as the change kind** — *later* (operator, 2026-10-23): reopen when per-area
  counts are deep enough to split.
- **A learned or small model of risk** — *later* (operator, 2026-10-23): after stages ① to ⑥.
- **`/merge-train` recording outcomes at landing time** — *later*: it is a chain skill, and to
  read `merge.land` it would read the trace (ADR-0024 clause 7). Reopen when K3 needs a record
  fresher than the last `/retro`.
- **Reading a ticket's or PR's prose for "fixes #N"** — *never* as prose (trust boundary). If a
  fix that blame cannot attribute shows up, a structured stamp field is the *later* route.
- **Line-level vindication of a rejected finding** — *later*: K1 matches on the file. Reopen if
  `/retro` shows file-level vindication crediting lenses that did not point at the broken line.
- **The operator's `feedback outcome=missed` counted as a mistake** — *later*: Q2's list of three
  is the operator's and is closed. The verdicts stay in `/retro`'s existing counts. Reopen on
  the operator's word.
- **Storing the earned record** — *never*: it is computed on read, like cost (ADR-0024 clause 6),
  so a definition change re-reads all history and no stored copy goes stale.
- **A review-area policy file of its own** — *later*: Q4 chose the lens-slice rules. Reopen if
  retuning those rules for review cost starts moving areas' records (see §9).

## 7. Technical constraints and testing

- POSIX `sh` and `git` only, like the rest of the trace. The trace stays append-only, and no
  `merge.outcome` field holds text from a commit message, a PR, an issue or a ticket body: only
  shas, PR and ticket ids, file paths taken from git's own diff, digits and outcome words.
- **Trust boundary.** Commit messages, PR titles and factory ticket bodies are untrusted. The
  recorder reads exactly four things from them, each by an anchored pattern and held to its
  shape: the Conventional Commit type token (`^(fix|revert)(\([^)]*\))?!?:`), a 40-hex sha
  verified by git, `qa.outcome` (`pass|fail`) and `links.pr` (`#[0-9]+`). Everything else in
  them is never read. Joins go through the trace's own `merge.land` and git's own blame.
- **Tests** drive behaviour from outside. Each suite builds a throwaway git repository with
  scripted landings (merge commits with first parents, `revert:` and `fix:` subjects, dates set
  with `GIT_COMMITTER_DATE`), a fixture trace holding their `merge.land` events, and, for slice
  3, a fixture `.factory/`. It then asserts on the events written and the rows printed. Prior
  art: the trace suite's fixture traces, the landing script's suite with its fixture
  repositories, and the retro suites that hold a skill's text to its contract. Every new
  outcome word joins the trace suite's row-for-row table check (ADR-0024 clause 1).
- **Numbers, not quality words:** the fix window is 30 days (R36), the record's window is 20
  landings (R44), idempotence is "a second run writes 0 lines" (R41). The recorder's speed is
  measured in slice 1 over the kit's own history and recorded as a baseline. It is not promised
  here.

## 8. Decisions recorded for this PRD

From D-02 (decisions.md, 2026-10-23, the operator): Q2 (what a mistake is), Q3 (the numbers the
record is built for), Q4 (a change kind is a review area, from the lens-slice rules), Q7 (K1
first, in parallel with K4), and the earlier "labels come from post-merge outcomes".

**Derived while writing** (the session, under the operator's standing delegation of rulings;
the maintainer confirms them at approval):

- **K1 stays inside ADR-0024; K3 owns the supersession.** ADR-0024 clause 7 says the chain never
  reads the trace, and only the operator, `/retro` and named operator-run tools do. K1 adds two
  readers, the recorder (it reads `merge.land` to map shas to PRs, and its own past outcomes to
  stay idempotent) and the record reader. Both are run only by `/retro` and by the operator, so
  they are within clause 7's existing shape, and no chain skill reads either. A new kind is a
  clause 1 change, and ADR-0024 is at its five-amendment cap (ADR-0021). So slice 1 writes **one
  new decision record** that amends ADR-0024 clauses 1 and 7 as a new record, as ADR-0034 did:
  the `merge.outcome` kind with its outcome words and shapes, and the two readers named in
  clause 7. It takes the next free ADR number when written. The step that lets a chain skill act
  on the record, K3's risk rule, contradicts clause 7 and clause 9 ("not a memory"). K3 must
  write the record that supersedes them. K1 does not.
- **Fix-ness comes from the Conventional Commit type, and the PR from blame.** Q2's "a later
  `fix:` commit or ticket naming the PR" is read as: the fixing landing is typed `fix`, and the
  PR it fixes is the one git blame attributes the removed or rewritten lines to. Prose naming a
  PR is never read (trust boundary). A fix that lands under another type is not counted (§6).
- **A revert has no time window; a fix has 30 days.** Q2 bounds only the fix.
- **Counting: a PR counts toward every review area it touches.** Q4's "judged by its riskiest
  area" is a judgement, and it belongs to K3. For the record, a PR and its mistakes count in
  each area its diff touches, and a finding in each area of its own `data.where` path.
- **Missed versus caught is decided at file level, conservatively.** A mistake is caught only
  when a finding on that PR named a file the mistake touched and triage overrode it. So the miss
  belongs to the triage, not the review. A `qa-failed` mistake touches no file and always
  counts as missed. Under doubt the record leans toward "missed", because everything starts high
  risk (Q1).
- **Precision counts the session's triage, and says how much of it there is.** Waiting for human
  dismissals and post-merge vindications alone would leave most areas with no label for months.
  The record instead counts triage labels too, prints each label's source (triage, human,
  outcome), and lets an outcome override triage: a rejected finding later vindicated holds up.
  K3 decides what share of non-triage labels it requires.
- **The record is computed on read, never stored**, so a definition change re-reads all history.
- **Backfill is the clock.** The recorder's first run covers every landing the trace holds with a
  merge sha (since 2026-09-29, 224 at the time of writing), so Q7's 20-landing window is full at
  once. Landings still inside the fix window are counted and flagged, never held back.

**Alternatives considered:**

- **Emit outcomes from `/merge-train` at each landing.** It is fresher, but a chain skill would
  read the trace (clause 7), and a by-hand landing would be missed. It is the *later* route of §6.
- **Detect a revert only by its `This reverts commit` line.** This is message text, and the
  message is untrusted. Blame on the removed lines needs no message, so the sha is the fallback
  for a pure-deletion PR only (runtime/R33).
- **Label precision from the operator's rulings only.** These are too rare under ADR-0016's
  delegation to fill a 20-landing window. The record counts them as the `human` label source
  instead.

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

- **The lens-slice rules overlap, so several review areas may carry identical records.** Today
  `pattern`, `simplicity` and `reuse-dry` select the same paths, and so do `security` and
  `api-crud`. The record may show three distinct areas under six names.
  - Options: keep one row per rule (Q4 as decided); merge rules with identical patterns into one
    row named by all their lenses; or give review areas a policy of their own (§6, *later*).
  - Next step: question to agranado at K3's grill, with slice 1's first real record in hand. It
    does not shape K1's tickets. MVP default: one row per rule.

## 10. Dogfood plan

Four tickets in slice order, chained one per frontier (ADR-0033). The kit runs the recorder on
its own trace after slice 1 lands. The first `/retro` after that prints the kit's earned
record, backfilled from 2026-09-29, and that `/retro` is where D-02's hypothesis H1 (some review
area earns its numbers within ten waves) starts counting. The software factory's PRDs A–D read
this record once K3 exists. Until then, its `factory qa` verdicts feed slice 3's outcomes.
