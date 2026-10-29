---
id: PRD-14
type: prd
title: Acceptance tests approved with the ticket, held by a guard and built from first
parent: D-02
stage: review
created: 2026-10-29
updated: 2026-10-29
stages:
  - {stage: draft, at: 2026-10-29T16:33Z}
  - {stage: review, at: 2026-10-29T16:42Z}
---

# PRD-14 · Acceptance tests approved with the ticket, held by a guard and built from first

## 1. Objective

Let a ticket name the acceptance tests that define its done, have a human approve those tests
before the build starts, and hold them: the build starts from them red, never edits them, ends
when they are green, and a guard fails any pull request that changes an approved test file.

**Problem.** Today the session that builds a ticket also writes the tests that judge it. The
ticket's `Covers:` line names requirement ids (the kit's ADR-0012), and the check table shows
which tier of test checked each one (ADR-0037). But the tests in the evidence column are the
implementer's own, written in the same diff as the code. A build that misread a requirement
writes a test that agrees with the misreading, and the check table then shows a `pass` that
proves nothing. Nothing stops a build from weakening a test it cannot pass, either. The
pairing guard checks that a source change comes with a test change, not that the test is the
one the human meant. D-02's later stages remove the human from low-risk PRs (K5), which makes
this worse: the only remaining human act on such a PR would be approving its tests, and today
there is no such act.

The software factory (its D-08) has designed that act as its stage 2, "acceptance tests
approved with the ticket" (factory PRD-17). It writes the tests first, and `factory approve
T-nn --tests <commit>` records who approved them, at which commit. Its PRD-17 waits on this
PRD for the kit's half: a stamp line naming the tests, a guard that holds them, and a chain
that builds from them.

**Solution, from the user's side.**
- A ticket carries one `Accept-test: <requirement-id> <path>::<test-name>` line per acceptance
  test, beside its `Test-tier:` lines. The stamp reader checks them like any stamp line. The
  vocabulary ships in a tagged release, and factory PRD-17 starts on that tag.
- A new **acceptance guard** reads every factory ticket on the base branch. For each one with
  an **approval record** and not yet done, it fails the PR when a file one of its `Accept-test:`
  lines names differs from its content at the approval commit. It reads its policy and the
  tickets through K2's policy reader (PRD-08), so a PR cannot move its own approval.
- `/implement` builds in **tests-first mode**. It brings in the approved tests unchanged,
  confirms they are red against the base's code, never edits them, and is done when they are
  green. A ticket created on or after the project's **adoption date** with no approved tests is
  not built; the session reports the tests as owed.
- `/review-pr` runs the guard on the diff, and Agent 7 lists an approved test that changed as
  ❌ MISSING. The check table's row for a requirement with approved tests cites one of them as
  its evidence, and the check-table reader holds the row to that.

Acceptance tests are on by default, and there is no key that turns them off (D-08's operator,
2026-10-29). The one exemption is a ticket created before the adoption date.

**The test of done.** In a fixture repository with a `.factory/` folder, ticket T-90 covers
`report/R3`, carries `Accept-test: report/R3 tests/report.test.sh::totals by area`, and its
front matter records `tests: {commit: 4b1c9e0, by: agranado, at: 2026-11-02}` at stage
`build`. Then:
- `sh scripts/stamp.sh` on T-90's issue prints the `Accept-test:` line, and on a copy whose
  path holds a space exits 2 naming `accept-test`;
- the acceptance guard, run from `main` to a branch that edits `tests/report.test.sh`, prints
  `changed: T-90 report/R3 tests/report.test.sh` and exits 1, and run on a branch that leaves
  the file as it was at `4b1c9e0` exits 0;
- the same branch that also rewrites T-90's `tests.commit` to its own head still fails: the
  guard read `main`'s ticket;
- a ticket T-91 created after the adoption date with no approval makes the reader print
  `owed T-91` and exit 4, and `/implement` on T-91 stops before its first commit.

## 2. Users and scenarios

**U1 — the operator**, who approves a ticket's acceptance tests and wants that approval to
bind the build. **U2 — the software factory**, which writes the tests, stamps the
`Accept-test:` lines and records the approval. **U3 — `/implement`**, which builds the ticket.
**U4 — `/review-pr` and the CI job that runs the guards**, which judge the PR.

Stories:

1. As the operator, I want the tests I approved to be the ones that decide the ticket is done,
   so that a build cannot pass by agreeing with its own misreading.
2. As the operator, I want any PR that changes an approved test file to fail, so that a test I
   approved is changed only when I approve it again.
3. As the software factory, I want the `Accept-test:` grammar fixed in a tagged kit release, so
   that my PRD-17 stamps lines the kit's chain reads and checks.
4. As `/implement`, I want one reader that tells me a ticket's approved tests, or that they are
   owed, or that the ticket is exempt, so that I neither build a ticket whose tests nobody
   approved nor re-implement the exemption rule.
5. As the reviewer, I want the diff read against the approved tests and the check table to cite
   them, so that a `pass` row means the approved test passed.

**UC1 — Read a ticket's acceptance tests.** Actor: `/implement`, starting issue #990, which the
factory planned as T-90. Goal: the ticket's stamp, checked.
1. Issue #990 carries `Covers: report/R3, report/R4`, `Test-tier: report/R3 suite`,
   `Test-tier: report/R4 manual`, `Accept-test: report/R3 tests/report.test.sh::totals by area`
   and `Accept-test: report/R3 tests/report.test.sh::empty window prints zero`.
2. `sh scripts/stamp.sh 990` hands the lines to the vocabulary checker, which accepts them, and
   prints them as spelled with the other stamp lines.

Extensions:
- 2a. A line reads `Accept-test: report/R3 tests/report test.sh::totals`. The checker refuses
  the space in the path, and the stamp reader exits 2 naming the field `accept-test`.
- 2b. A line names `report/R9`, which is not on the `Covers:` line. The stamp reader exits 2
  naming `accept-test`.
- 2c. The ticket carries 40 `Accept-test:` lines. The stamp reader exits 5 and prints nothing.
- 2d. A line names `../secrets/key::x` or `/etc/passwd::x`. The checker refuses the path.
- 2e. A line is 260 bytes long. The checker refuses it.

**UC2 — Build from the approved red tests.** Actor: `/implement` on T-90. The factory approved
its tests at commit `4b1c9e0`, which holds `tests/report.test.sh` with both tests and is not on
`main`. Goal: a PR whose approved tests pass, unchanged.
1. `/implement` asks the acceptance reader for T-90's tests at `origin/main`. It prints
   `approved 4b1c9e0` and the two `Accept-test:` lines.
2. In its new worktree off `origin/main`, `/implement` brings `tests/report.test.sh` in at its
   content at `4b1c9e0` and commits it alone, unchanged, as the build's first commit.
3. It runs both approved tests at that commit. Both fail: the code they test is not written.
4. It drives `/tdd` through the seams. Its own extra tests go in other files.
   `tests/report.test.sh` is never edited.
5. Both approved tests pass, and so does the full suite. `/implement` opens the PR. The check
   table's `report/R3` row reads `suite | pass |
   tests/report.test.sh::totals by area@9d2f0a1`, and `report/R4` reads `manual | skipped | -`.

Extensions:
- 1a. T-91 was created on 2026-11-05, after the adoption date, covers a `suite` id, and has no
  approval record. The reader prints `owed T-91` and exits 4. `/implement` stops before its
  first commit and reports that T-91's acceptance tests are owed.
- 1b. T-12 was created before the adoption date and has no approval record. The reader prints
  `no-tests T-12 created-before-adoption` and exits 0. `/implement` builds as it does today.
- 1c. T-90's `tests.commit` names a commit this clone does not hold. The reader prints
  `fail-closed invalid .factory/items/T-90/ticket.md` and exits 3. `/implement` stops and
  reports the line.
- 1d. The repository has no `.factory/` folder. `/implement` does not ask the reader and builds
  as it does today.
- 3a. `empty window prints zero` already passes at the first commit. `/implement` stops and
  reports the test as green before the build: it does not test the change.
- 4a. Making `totals by area` pass would need its expected total changed. `/implement` stops,
  leaves the file unchanged, and reports the test and the change it would need, for the
  operator to approve again.

**UC3 — A PR changes an approved test.** Actor: the CI job that runs the guards on PR #995 for
T-90, whose build weakened an assertion in `tests/report.test.sh`. Goal: the PR fails.
1. The shipped pairing workflow runs the acceptance guard from the PR's base commit to its head,
   with `POLICY_BASE` set to the base commit.
2. The guard lists the factory tickets at the base and reads each through the policy reader.
   T-90 is at stage `build` with an approval record at `4b1c9e0`.
3. `tests/report.test.sh` at the head differs from its content at `4b1c9e0`. The guard prints
   `changed: T-90 report/R3 tests/report.test.sh` and exits 1, and the check fails.

Extensions:
- 2a. T-89 has `Accept-test:` lines and no approval record. The guard does not hold it.
- 2b. T-88 is at stage `done`. The guard does not hold it, so a later ticket may change its
  tests.
- 2c. #995 also rewrites T-90's `tests.commit` to its own head. The guard read `main`'s ticket,
  so `4b1c9e0` still holds and the PR still fails. K2's `touched` reports the ticket file.
- 2d. T-90's approval record names no commit here, or lacks its `by` field. The guard prints
  `fail-closed invalid .factory/items/T-90/ticket.md` and exits 3.
- 2e. The guards policy is missing at the base. The guard prints K2's
  `fail-closed missing scripts/guards.config.sh` and exits 3.
- 2f. The repository has no `.factory/` folder. The guard prints nothing and exits 0.
- 3a. #995 deletes or renames `tests/report.test.sh`. The guard reports it as changed.
- 3b. The operator agrees the assertion was wrong and runs `factory approve T-90 --tests
  <new commit>`, and that lands on `main`. The next run holds the new content, and #995 passes
  once it carries it.

**UC4 — The review reads the diff against the approved tests.** Actor: `/review-pr` on #995.
Goal: a changed approved test, or a row citing an unapproved test, reaches the operator.
1. The coordinator runs the acceptance guard from the review's base to the head, with
   `POLICY_BASE` set to that base, and the check-table reader on the PR body and ticket body.
2. Agent 7 receives both outputs. It lists `❌ MISSING report/R3 — approved test changed`.
3. The check-table reader prints `not-approved: report/R3` when the `report/R3` row's evidence
   names a test that is not one of `report/R3`'s `Accept-test:` lines. Agent 7 lists it as
   ❌ MISSING too.

Extensions:
- 1a. The guard exits 3. Agent 7 lists every id on the ticket's `Accept-test:` lines as ❌
  MISSING, and the report's summary prints the fail-closed line.

## 3. Model

- **Acceptance test**: a test named on a ticket, before the build, as part of the definition of
  done of one requirement the ticket covers. A requirement may have several.
- **`Accept-test:` line**: a stamp line, `Accept-test: <requirement-id> <test pin>`. It is a
  **keyed field** of the vocabulary, like `Test-tier:`: the id is held to the requirement
  library's bounded grammar and must be on the ticket's `Covers:` line. Unlike `Test-tier:`, an
  id may repeat, once per test.
- **Test pin**: `<path>::<test-name>`, held to a grammar the checker owns, not to tokens: at most
  200 bytes, printable ASCII, no `|`. The path is relative, non-empty, holds no space, no `::`,
  and no `..` segment. The test name is non-empty and may hold spaces. The pin splits at its
  first `::`.
- **Approval record**: the `tests` block of a factory ticket's front matter, `{commit, by, at}`,
  written by `factory approve T-nn --tests <commit>` (factory side). The **approval commit** is
  its `commit`: a commit whose tree holds every file the ticket's `Accept-test:` lines name, at
  the approved content. It need not be on the base branch.
- **Held ticket**: a factory ticket, read at the base, that carries an approval record and whose
  `stage` is not `done`. Its approved test files are held from the approval until it is done.
- **Acceptance guard**: the new guard and reader. It answers two questions, each at a base:
  `check <base> <head>` (which held files a diff changed) and `tests <ticket> --base <ref>`
  (what a ticket's approved tests are, or that they are owed). It reads the guards policy and
  each factory ticket through the policy reader (PRD-08), and fails closed in K2's shape.
- **Adoption date**: a date in the guards policy, `YYYY-MM-DD`. A ticket whose front matter
  `created` is before it is exempt. Unset, no ticket is exempt. This is the one exemption;
  there is no per-ticket opt-out.
- **Owed**: a ticket that is not exempt, has no approval record, and covers at least one id whose
  `Test-tier:` is not `manual`. A ticket whose ids are all `manual`, or that has no `Covers:`
  line, owes nothing, since there is no automated test to approve.
- **Tests-first mode**: how `/implement` builds a ticket with approved tests. It brings them in
  unchanged as the first commit, confirms each is red there, never edits them, and is done when
  they pass.

**What each part reads.**

| Reader | Reads | From | Through |
|---|---|---|---|
| stamp reader | `Accept-test:` lines | the tracker issue | vocabulary checker |
| acceptance guard, `check` | approval records, stages, `Accept-test:` lines; the held files | factory tickets at the base; the files at the approval commit and the head | policy reader; git objects |
| acceptance guard, `tests` | the above, plus `created`, `Test-tier:` lines and the adoption date | factory ticket and guards policy at the base | policy reader |
| check-table reader | `Accept-test:` lines | the ticket body the caller fetched | its own parse, ids and pins only |

## 4. Rules

Area: acceptance

No living spec exists for this area. The first ticket that covers one of these lines creates
`docs/specs/acceptance.md`, keeping these numbers. Deltas against `process` and `policy` follow.

acceptance/R1. The vocabulary checker SHALL accept an `Accept-test:` line whose value is one requirement id in the coverage check's bounded grammar, one space, and a test pin `<path>::<test-name>`. [UC1 2]
acceptance/R2. IF a test pin is longer than 200 bytes, holds a byte outside printable ASCII or a `|`, has an empty path, a path holding a space, a path starting with `/` or holding a `..` segment, or an empty test name, THEN the vocabulary checker SHALL refuse it, naming the field `accept-test`. [UC1 2a, 2d, 2e]
acceptance/R3. The vocabulary checker SHALL accept several `Accept-test:` lines for one id, and SHALL read two identical lines as one answer.
acceptance/R4. The shipped vocabulary policy SHALL declare the field `accept-test` as a keyed field whose value is held to the test-pin grammar the checker owns, with a published line bound of 32, and the checker's built-in defaults SHALL equal it.
acceptance/R5. WHEN a ticket carries `Accept-test:` lines, the stamp reader SHALL lift and check them with the ticket's other stamp lines and print them as spelled. [UC1 2]
acceptance/R6. IF a ticket's `Accept-test:` line names an id that is not on its `Covers:` line, THEN the stamp reader SHALL exit 2 naming the field `accept-test`. [UC1 2b]
acceptance/R7. WHEN the release that ships acceptance/R1 to R6 lands, `UPDATING.md` SHALL tell a consumer whose own vocabulary policy file predates it to add the `accept-test` field and its bound.
acceptance/R8. WHEN asked to `check <base> <head>`, the acceptance guard SHALL print, sorted, one `changed: <ticket> <requirement-id> <path>` line for each `Accept-test:` path of a held ticket whose content at the head differs from its content at the ticket's approval commit, and SHALL exit 1 when it printed one and 0 when it printed none. [UC3 2, 3]
acceptance/R9. The acceptance guard SHALL hold only tickets whose front matter at the base carries an approval record and whose stage is not `done`. [UC3 2a, 2b]
acceptance/R10. A held path that is absent at the head SHALL count as changed. [UC3 3a]
acceptance/R11. WHERE `POLICY_BASE` names a ref, the acceptance guard SHALL read the guards policy and every factory ticket through the policy reader at that ref, and SHALL read neither from the working tree. [UC3 1, 2, 2c]
acceptance/R12. WHERE `POLICY_BASE` is unset, the acceptance guard SHALL read the guards policy and the factory tickets from the working tree.
acceptance/R13. IF a held ticket's approval commit names no commit in the repository, its approval record lacks `commit`, `by` or `at`, one of its `Accept-test:` lines is refused by the checker, or an approved path is absent at the approval commit, THEN the acceptance guard SHALL print `fail-closed invalid <ticket path>` and exit 3. [UC3 2d; UC2 1c]
acceptance/R14. IF the policy reader fails closed on the guards policy or on a factory ticket, THEN the acceptance guard SHALL print that fail-closed line and exit 3, and SHALL NOT pass. [UC3 2e]
acceptance/R15. WHERE the repository has no `.factory/` folder, the acceptance guard SHALL print nothing on standard output and exit 0 for `check`. [UC3 2f]
acceptance/R16. The acceptance guard SHALL print nothing read from a factory ticket except ticket ids, requirement ids, approval commits, and `Accept-test:` lines the checker accepted.
acceptance/R17. WHEN asked for `tests <ticket> --base <ref>` on a ticket with an approval record, the acceptance guard SHALL print `approved <commit>` and then the ticket's `Accept-test:` lines as spelled, and exit 0. [UC2 1]
acceptance/R18. IF a ticket without an approval record was created before the adoption date the guards policy names at the base, THEN `tests` SHALL print `no-tests <ticket> created-before-adoption` and exit 0. [UC2 1b]
acceptance/R19. IF a ticket without an approval record covers no id whose `Test-tier:` is other than `manual`, THEN `tests` SHALL print `no-tests <ticket> no-automated-id` and exit 0.
acceptance/R20. IF a ticket is owed (not exempt, no approval record, at least one covered id with a `Test-tier:` other than `manual`), THEN `tests` SHALL print `owed <ticket>` and exit 4. [UC2 1a]
acceptance/R21. WHERE the guards policy names no adoption date, no ticket SHALL be exempt, and a ticket whose `created` is missing or not a date SHALL NOT be exempt.
acceptance/R22. IF the guards policy's adoption date is set and is not a valid `YYYY-MM-DD` date, THEN the acceptance guard SHALL print `fail-closed invalid <guards policy path>` and exit 3.
acceptance/R23. The shipped TDD pairing workflow, and the kit's own guards workflow, SHALL run the acceptance guard's `check` on every pull request from its base commit to its head, with `POLICY_BASE` set to the base commit, and fail on a non-zero exit. [UC3 1]
acceptance/R24. WHERE the repository holds a `.factory/` folder, `/implement` SHALL ask the acceptance guard for the ticket's tests at the base before its first edit. [UC2 1, 1d]
acceptance/R25. IF the acceptance guard prints `owed`, THEN `/implement` SHALL stop before its first commit and report that the ticket's acceptance tests are owed. [UC2 1a]
acceptance/R26. IF the acceptance guard exits 3 for `tests`, THEN `/implement` SHALL stop before its first commit and report the fail-closed line. [UC2 1c]
acceptance/R27. WHEN the acceptance guard prints approved tests, `/implement` SHALL bring each approved file into its worktree at its content at the approval commit and commit those files alone, unchanged, as the build's first commit. [UC2 2]
acceptance/R28. WHEN the first commit holds the approved tests, `/implement` SHALL run each one before writing other code, and IF any passes there, THEN SHALL stop and report it as green before the build. [UC2 3, 3a]
acceptance/R29. WHILE building a ticket with approved tests, `/implement` SHALL NOT edit, move or delete an approved test file. [UC2 4]
acceptance/R30. IF an approved test cannot pass without a change to it, THEN `/implement` SHALL stop, leave the file unchanged, and report the test and the change it would need for the operator to approve again. [UC2 4a]
acceptance/R31. `/implement` SHALL NOT open the pull request of a ticket with approved tests until every approved test passes at the head and the full suite passes. [UC2 5]
acceptance/R32. WHEN `/review-pr` reviews a pull request in a repository with a `.factory/` folder, its coordinator SHALL run the acceptance guard's `check` from the review's base to the head with `POLICY_BASE` set to that base, and hand the output to Agent 7. [UC4 1]
acceptance/R33. Agent 7 SHALL list each `changed:` line as a ❌ MISSING item naming the requirement id and `approved test changed`. [UC4 2]
acceptance/R34. IF the acceptance guard exits 3 during a review, THEN Agent 7 SHALL list every id on the ticket's `Accept-test:` lines as ❌ MISSING, and the report's summary SHALL print the fail-closed line. [UC4 1a]

### Deltas against `docs/specs/process.md`

PRD-07 delivered process/R38 to R60. The in-flight D-02 PRDs take ids up to process/R207
(PRD-13), so this PRD's ADDED lines start at process/R220.

#### MODIFIED

process/R43. IF a ticket carries more than 32 `Test-tier:` lines, more than 32 `Accept-test:` lines, or more than 8 lines of any other stamp key, THEN the stamp reader SHALL stop with exit 5 and print nothing. [UC1 2c]
process/R46. Each check-table row SHALL carry the ticket's `Test-tier:` for its id where the ticket stamps one, a result of `pass`, `fail` or `skipped`, and as evidence a `<path>::<test>@<commit>` pin of the test that checked it or an `https://` URL, where an id the ticket carries `Accept-test:` lines for SHALL take a pin whose `<path>::<test>` is one of those lines, and a `manual` row no human has checked SHALL read `skipped` with the evidence `-`. [UC2 5]
process/R47. The check-table reader SHALL read a PR body and a ticket body and print only requirement ids, tokens and row numbers: exit 0 when every covered id has exactly one row, its result `pass`, its tier the ticket's stamp, and its evidence one of the id's `Accept-test:` lines where it has any; exit 1 with `missing-row:`, `extra-row:`, `tier-differs:`, `not-approved:`, `fail:` and `skipped:` lines; exit 2 for a row that breaks the grammar or a table past 64 rows, naming the row number; exit 3 when the body carries no table. [UC4 3]

#### ADDED

process/R220. `/to-tickets`' rule against file paths in ticket bodies SHALL except `Accept-test:` lines, as it excepts a mechanical ticket's oracle line, because the approval commit pins each path and the acceptance guard catches a path that drifts.
process/R221. WHERE a ticket draft carries `Accept-test:` lines, `/to-tickets` SHALL check each with the vocabulary checker before the quiz and show them at the quiz beside the ticket's `Test-tier:` lines.

### Delta against `docs/specs/policy.md`

#### MODIFIED

policy/R9. The judging set SHALL hold exactly the files directly under `scripts/` whose names end `.config.sh`, the docs gate's config and local-vocabulary modules, the files directly under `.githooks/` and `.github/workflows/`, every file named `ticket.md` directly under a directory directly under `.factory/items/`, the risk policy, and each path the risk policy's extra list names at the base ref, each matched by its whole repository-relative path. [UC3 2, 2c]

## 5. Slices (vertical, demoable, in order)

Slices 1, 2 and 4 each move a `VERSION`-listed file, so each is a shared-layer release, and
ADR-0033 chains them one per frontier: 1, then 2, then 4. Slice 3 moves only skill text and can
share slice 4's frontier. Slice 1 needs only K4 (PRD-07, landed); slices 2 to 4 need K2's
policy reader and `POLICY_BASE` in the pairing workflow (PRD-08 slices 1 and 2).

**Slice 1 — the `Accept-test:` vocabulary, read from a ticket (shared-layer release).** The
release factory PRD-17 starts on.
- *Covers:* acceptance/R1, acceptance/R2, acceptance/R3, acceptance/R4, acceptance/R5, acceptance/R6, acceptance/R7, process/R43, process/R220, process/R221.
- *Also:* ADR-0037 amended in place with the `Accept-test:` grammar (§8). The glossary gains
  acceptance test, `Accept-test:` line and test pin. The release moves the vocabulary checker
  and the stamp reader, both in `VERSION`, so the ticket bumps the minor, writes `UPDATING.md`,
  re-captures the transcripts `tests/docs-demo.sh` quotes, and lands only once its merge commit
  carries its tag. The history note names `/to-tickets`' rule 8 change as the non-manifest
  half.
- *Accept:* the vocabulary suites accept UC1's lines and refuse each extension's pin (space,
  `..`, leading `/`, `|`, 201 bytes, empty name). Two identical lines read as one. The policy
  suite holds the shipped file equal to the defaults. The stamp suite, with a stubbed tracker,
  prints UC1's lines, exits 2 on an id off the `Covers:` line, and exits 5 on 33 `Accept-test:`
  lines. A skill-text suite holds `/to-tickets`' exception and its check before the quiz.

**Slice 2 — the acceptance guard (shared-layer release).** The tracer bullet of the hold: one
approved file, judged at the base, failing closed.
- *Covers:* acceptance/R8, acceptance/R9, acceptance/R10, acceptance/R11, acceptance/R12, acceptance/R13, acceptance/R14, acceptance/R15, acceptance/R16, acceptance/R17, acceptance/R18, acceptance/R19, acceptance/R20, acceptance/R21, acceptance/R22, acceptance/R23, policy/R9.
- *Blocked by:* slice 1, and PRD-08 slices 1 and 2.
- *Also:* the new decision record (§8). The glossary gains approval record, approval commit,
  held ticket, acceptance guard, adoption date and owed. The guards policy gains the adoption
  date, commented out in the shipped file and set in the kit's twin to the day this slice
  lands. The new guard joins `VERSION`'s files and bootstrap's copy, and AGENTS.md gains a
  quick-reference row.
- *Accept:* in throwaway repositories with a `main`, a branch and a `.factory/` folder, UC3's
  fixture fails with the `changed:` line and passes with the file left at its approval content,
  including when the approval commit is not on `main`. A rewrite of the branch's own
  `tests.commit` still fails. A deleted file is changed; a `done` or unapproved ticket is not
  held; an unknown approval commit gives `invalid`; a missing guards policy at `main` gives
  K2's line; no `.factory/` exits 0. `tests` gives `approved`, `owed`, both `no-tests` reasons,
  and `invalid` for a bad adoption date. The workflow template's suite asserts the guard runs
  with `POLICY_BASE` set.

**Slice 3 — tests-first mode in `/implement`.**
- *Covers:* acceptance/R24, acceptance/R25, acceptance/R26, acceptance/R27, acceptance/R28, acceptance/R29, acceptance/R30, acceptance/R31.
- *Blocked by:* slice 2.
- *Also:* the glossary gains tests-first mode.
- *Accept:* `/implement`'s skill-text suite holds each step: the reader asked before the first
  edit where `.factory/` exists, the stop on `owed` and on exit 3, the first commit of the
  approved files alone, the red check and its stop, the never-edit rule and its stop, and the
  done rule. A fixture run of the steps' commands on UC2's repository shows the first commit's
  files byte-equal to the approval commit's.

**Slice 4 — the review and the check table read the approved tests (shared-layer release).**
- *Covers:* acceptance/R32, acceptance/R33, acceptance/R34, process/R46, process/R47.
- *Blocked by:* slice 2 (and slice 1, through it).
- *Also:* the check-table reader is in `VERSION`, so this is the third release: bump,
  `UPDATING.md`, re-captures, tag. The offline review worker's contract and the review broker
  learn the `approved test changed` item.
- *Accept:* the check-table suite drives `not-approved:` from a row citing a test off the id's
  `Accept-test:` lines, passes a row citing one, and admits a pin whose test name holds spaces.
  `tests/review-pr-output.test.sh` holds Agent 7's item for a `changed:` line and the fail-closed
  listing. A skill-text suite holds `/review-pr`'s coordinator step and `/implement`'s
  check-table citation.

## 6. Non-goals (this PRD)

- **`factory approve --tests`, the refused ready → build move, and `factory tests T-nn`.**
  *Never* here: factory PRD-17. The kit reads the approval record the factory writes, as the
  outcome recorder reads `qa.outcome` and `links.pr`.
- **A per-ticket or per-project opt-out key.** *Never*: D-08's operator ruled it out
  (2026-10-29). The adoption date is the only exemption.
- **Writing the acceptance tests, or an approval record, in a repository with no `.factory/`
  folder.** *Later*, open (§9, first question). Reopen when a consumer without the factory asks
  for acceptance tests.
- **Checking that a named test still exists in its file, or still asserts what it did.**
  *Later*. The guard is file-level: any byte change fails. Reopen if the file-level hold blocks
  too much honest work, which `/retro` would see as re-approvals.
- **Holding an approved test after its ticket is done.** *Never* in K9: once done, the file is
  ordinary code, judged by the pairing guard and the review.
- **Making the low-risk lane (K5) require approved tests.** *Later*, K5's grill. K9 gives it the
  approval record to read.
- **Rewriting tickets created before the adoption date.** *Never*: they are exempt.
- **A new trace kind for the guard or tests-first mode.** *Later*. The guard reads no trace
  (ADR-0024 clause 7), and `/retro` can count re-approvals from the factory's records. Reopen if
  `/retro` needs the owed stops as events.

## 7. Technical constraints

- POSIX `sh` and `git` only, like the guards. The guard reads file content at a commit from
  git's objects alone; it never checks out, switches branch, writes in the working tree, or
  fetches. An approval commit the clone does not hold is `invalid`.
- It reads factory front matter as the outcome recorder does: the block between the first two
  `---` lines, only the named keys (`stage`, `created`, and `commit`, `by`, `at` nested under a
  top-level `tests:`), each a scalar held to its shape. The body is read only for stamp lines,
  each checked by the vocabulary checker.
- Ticket bodies on the tracker are untrusted (root `AGENTS.md`). Every `Accept-test:` line
  reaches a skill through the stamp reader or the guard, never as raw body text. A test pin is
  not a token: the checker holds it to a grammar, as it holds a trace filter.
- The shipped CI workflows must hold the approval commits' objects. The pairing workflow already
  checks out full history; an approval commit off `main` is reachable from the PR's head once
  `/implement` built from it, and absent otherwise, which fails closed.
- A ticket's id in `changed:`, `owed` and `no-tests` lines is the factory ticket directory's
  name, held to the outcome recorder's `data.ticket` shape.
- **Tests** drive the guard from outside, in throwaway git repositories with a `main`, a branch
  and a `.factory/` folder, asserting exit codes and exact lines. Prior art: the pairing guard's
  CI suite, the outcome recorder's factory fixtures in the trace suite, PRD-08's policy reader
  suite, and the stamp and check-table suites. Every fail-closed cause has a fixture.
- **Numbers, not quality words:** a test pin is at most 200 bytes; a ticket carries at most 32
  `Accept-test:` lines; `check` exits 1 on any changed held path. The guard's speed is not
  promised; slice 2 measures one `check` on the kit, whose `.factory/` holds some 90 tickets,
  and records it in the diary.

## 8. Decisions recorded for this PRD

**From D-02** (decisions.md, 2026-10-29): K9 added at D-08's request and kept in D-02 by the
operator; its four parts; `/to-tickets` rule 8's second exception; no opt-out key, only the
adoption date (D-08's operator). From the brief: depends on K2 and K4, ordered after K4 beside
K3.

**From D-08** (factory PRD-17, as relayed): the approval record is the factory ticket's front
matter `tests: {commit, by, at}`, written by `factory approve T-nn --tests <commit>`; the
factory refuses ready → build until approval; `factory tests T-nn` exits 1 when an approved
test file changed.

**Derived while writing** (the session, under the operator's standing delegation of rulings; the
maintainer confirms them at approval):

- **The hold is file-level, compared with the approval commit, not the base.** The approval
  commit is the only content a human approved. Comparing with it lets the approved tests live
  off `main` until the build brings them in, keeps `main`'s suite green, and catches a change
  made on `main` after the approval as well as one in the PR.
- **The guard reads the tickets at the base, through K2's reader.** A PR that rewrites its own
  approval record is judged by the base's. To read them there, factory ticket files join K2's
  judging set (MODIFIED policy/R9), so K2's `touched` also reports a PR that edits one.
- **The guard scans every held ticket, not the PR's ticket.** It needs no PR → ticket mapping,
  and it also stops a PR for one ticket from changing another ticket's approved tests.
- **The hold ends at `done`.** After that the file is ordinary code. A change before then needs
  a new approval, which is the operator's act.
- **Tests-first mode never edits an approved file at all.** The build's own extra tests go in
  other files, so the file-level hold and the build agree.
- **One reader with two questions and K2's failure shape.** `tests` prints `approved <commit>`
  and the lines (exit 0), `no-tests <ticket> <reason>` (exit 0), `owed <ticket>` (exit 4), or a
  fail-closed line (exit 3). `/implement` and later K5 read these shapes, so they are fixed here.
- **The adoption date lives in the guards policy**, read at the base. It is a judging file
  already, so a PR cannot move its own ticket before the date. Unset means no exemption, which
  is "on by default"; a malformed date fails closed.
- **A ticket with only `manual` ids, or no `Covers:` line, owes nothing.** `Accept-test:` is
  keyed by a covered id, and a manual id has no automated test to approve.
- **The test pin's extra limits** (relative path, no `..`, no `|`) are the session's, beyond the
  brief's "printable ASCII, no spaces in the path, at most 200 bytes": the guard opens the path,
  and the check table holds the pin in a cell.

**Decision records:**
- **Needed at slice 1:** an in-place amendment of ADR-0037, which fixes the ticket contract and
  has no amendment yet (ADR-0021's cap is five): the `Accept-test:` key, the test-pin grammar,
  its bound, and the rule 8 exception.
- **Needed at slice 2:** one new record, "approved acceptance tests are held from approval to
  done": the approval record as the factory writes it, the file-level comparison with the
  approval commit, the held set, the base read through K2's reader with factory tickets in the
  judging set, the adoption date as the only exemption, the owed rule, and tests-first mode's
  never-edit rule. It takes the next free number when written. ADR-0038 is the highest today,
  and PRD-08, PRD-09, PRD-10, PRD-11 and PRD-13 each name one unnumbered new record, so it is
  likely ADR-0044 or later.
- **Cited:** ADR-0012 (ids, `Covers:`, a test names its requirement), ADR-0015 and ADR-0025 (a
  release is bumped and tagged), ADR-0024 clause 7 (the guard reads no trace), ADR-0033 (one
  shared-layer ticket per frontier), ADR-0037 (the ticket contract and the check table),
  ADR-0038 (Agent 7's confirm-list), and ADR-0017 (a shipped file cites a kit record only as the
  kit's).

**Alternatives considered:**

- **Compare with the base instead of the approval commit.** Simpler, but it would need the red
  tests on `main` before the build, turning `main`'s suite red, and it would miss a change
  landed on `main` after the approval.
- **Hold the named test, not the file.** Closer to the intent, but needs a per-language parser
  of test files. The kit's core is `sh` and `git`.
- **Read the approval record from the PR's own tree.** The PR could then approve itself.

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

Two would change a ticket's shape and go first, as open-issue tickets:

- **How a repository with no `.factory/` folder gets approved acceptance tests.** *Shapes
  tickets.*
  - Options: K9 binds only where a factory writes approval records (this PRD); or the kit's
    `/to-tickets` writes the red tests and the kit records its own approval (a front matter it
    does not have, or a tracker label), adding at least two slices.
  - Next step: question to agranado before `/to-tickets` runs on this PRD. MVP default: binds
    only with a `.factory/` folder; without one, `/implement` and the guard behave as today.
- **Where approved tests live before the build.** *Shapes tickets* (slice 3, and factory
  PRD-17's commit).
  - Options: off `main`, at an approval commit `/implement` brings them in from (this PRD); or
    landed on `main` behind a pending marker the suite skips, which needs a pending mechanism
    per test runner.
  - Next step: ask the D-08 session, through the operator, before slice 2. MVP default: off
    `main`.

The rest keep the shapes above:

- **How `/implement` finds the factory ticket for the issue it builds.**
  - Options: the reader takes `#<N>` and picks the one factory ticket whose body holds the line
    `GitHub issue: #<N>`; the dispatcher passes the factory id; or K7's factory-ticket read.
  - Next step: settle in slice 3's grill with K7's state in hand. MVP default: the `#<N>`
    lookup; no match reads as `no-tests #<N> no-factory-ticket`, since only factory tickets have
    an approval to read.
- **How one approved test is run.**
  - Options: a run command in the guards policy taking a path and a test name; or the project's
    own test command on the whole file.
  - Next step: slice 3's implementer. MVP default: the policy's command where set, else the
    file, so red and green are judged per file.
- **Several approved tests for one id against one check-table row.**
  - Options: the row cites one, and `pass` asserts all passed (this PRD); or one row per test.
  - Next step: K8's grill, where the evidence is re-checked. MVP default: one row per id.
- **Whether K2's `touched` should report factory ticket files.** It now does (policy/R9), so
  under K3 every PR that edits a factory ticket is high risk.
  - Options: keep it; or let `read` serve factory tickets while `touched` skips them.
  - Next step: question to agranado at K3's grill. MVP default: keep it, since approval is the
    operator's act anyway.
- **Where the factory reads the adoption date.**
  - Options: the kit's guards policy (this PRD); or the factory's project manifest, which the
    kit would then read.
  - Next step: ask the D-08 session before slice 2. MVP default: the guards policy, written by
    the kit and only read by the factory, as the contract split says.
- **Requirement ids may collide with D-02's PRDs drafted in parallel.** This PRD takes
  process/R220 and R221, past PRD-13's R207, and modifies process/R43, R46, R47 and policy/R9,
  which no other open PRD modifies today.
  - Next step: the session that approves the D-02 PRDs renumbers before any is published to a
    ticket. MVP default: as written.

## 10. Dogfood plan

Four tickets in slice order, three of them releases chained one per frontier (ADR-0033). After
slice 1's tag, the factory starts PRD-17 and stamps `Accept-test:` lines on the kit's own
tickets. After slice 2, the kit's own CI holds every approved test, and its guards twin's
adoption date exempts the tickets planned before it. The first kit ticket planned after that
date is the live demo: the factory approves its tests, `/implement` (slice 3) brings them in
red and builds to green, and a deliberate edit to one on a scratch branch fails the guard.
After slice 4, `/review-pr` on the kit lists that edit as ❌ MISSING, and the check table cites
the approved test. `/retro` can then compare that wave's `fail` rows and re-approvals with the
wave before.
