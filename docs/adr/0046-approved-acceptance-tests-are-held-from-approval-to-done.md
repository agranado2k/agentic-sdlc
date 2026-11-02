# ADR-0046: Approved acceptance tests are held from approval to done, judged from the base

- **Status**: Accepted
- **Date**: 2026-11-02
- **Deciders**: the implementer session for #970 (PRD-14 slice 2, factory T-94), under the operator's delegation of rulings; the rule is PRD-14 §8's, approved by the operator and settled in the D-02 grill of 2026-10-31; the merge of this record's pull request is the operator's yes
- **Supersedes / amends**: narrows ADR-0039's "the PR's own scripts run" for this one guard: CI runs the acceptance guard from the base's objects
- **Superseded by**: —

## Context and problem statement

PRD-14 lets the operator approve a ticket's acceptance tests before the
build, so the tests that decide the ticket is done are ones a human read,
not ones the build wrote to agree with its own reading. The software factory
writes the approval (its PRD-17): a `tests:` record in the factory ticket's
front matter, `{commit, by, at}`. ADR-0037 fixed the `Accept-test:` line that
names each test. Nothing yet stops a pull request from changing an approved
test file, and a check that reads the approval or its own script from the
pull request's tree could be rewritten by the pull request it judges.

## Decision drivers

- A pull request must not be able to approve itself or loosen its judge.
- The kit's core is `sh` and `git`; no per-language test parser.
- `main`'s suite stays green: the red approved tests live off `main` until the
  build brings them in.
- Fail closed: a record the guard cannot hold is a failure, never a pass.

## Considered options

1. Compare the held files with the base, not the approval commit.
2. Hold the named test inside the file, not the file.
3. Read the approval record from the pull request's own tree.
4. Hold each approved file at its approval commit's content, reading every
   factory ticket at the base through the policy reader, and run the guard's
   script from the base's objects.

## Decision outcome

Chosen option 4 (PRD-14 §8; options 1 to 3 are its alternatives considered).

1. **The guard is `scripts/acceptance-guard.sh`, shared layer**, with three
   questions, each at a base: `check <base> <head>` prints, sorted, one
   `changed: <ticket> <id> <path>` per held file whose content at the head
   differs from its content at the approval commit, a file the base holds and
   the head lacks counting as changed, exit 1 on any; a file absent at both
   was never brought in and is not changed, so an unrelated pull request
   passes while the approved tests still live off `main` (clause 2); `tests <ticket> --base <ref>` prints
   `approved <commit>` and the `Accept-test:` lines (exit 0),
   `no-tests <ticket> <reason>` (exit 0), or `owed <ticket>` (exit 4);
   `held --base <ref>` lists `<ticket> <path>` per held file. These shapes
   are fixed here: `/implement` and later the low-risk lane read them.
2. **The hold is file-level, compared with the approval commit.** The
   approval commit is the only content a human approved; it need not be on
   `main`, and a change landed on `main` after the approval is caught too.
3. **The held set** is every factory ticket that, read at the base, carries
   an approval record and is not at stage `done`. Every held ticket is
   scanned, so no pull request-to-ticket mapping is needed and a pull request
   for one ticket cannot change another's approved tests. At `done` the file
   becomes ordinary code.
4. **Read at the base, through the policy reader.** With `POLICY_BASE` set,
   the guards policy, the factory project manifest and every factory ticket
   are read at that ref through `scripts/policy.sh`, never the working tree;
   factory ticket files join its judging set, and its `touched` reports one
   only when the `tests:` approval record changes (the factory moves a
   ticket's stage on every build branch). Unset, `check` reads the working
   tree, for a local run.
5. **Only a factory project has approved tests**: one whose git top level
   holds `.factory/project.yaml`. Anywhere else the guard prints nothing and
   exits 0; nothing above the top level is read.
6. **The adoption date is the only exemption**, the manifest's
   `acceptance_tests_since`: a ticket created before it owes nothing. Unset,
   nothing is owed and approvals are still held; out of shape, the guard
   fails closed. A `created` missing or not a date never exempts. A ticket
   owes approved tests when it has no approval record and covers an id
   stamped with a `Test-tier:` other than `manual`; a ticket with no
   `Covers:` line, or only `manual` ids, or a covered id with no `Test-tier:`
   line at all, owes nothing — the requirement's text, read literally.
7. **Fail closed in K2's shape.** One `fail-closed <reason> <path>` line and
   exit 3: the policy reader's own line for the guards policy, the manifest
   or a ticket file; `invalid <ticket file>` for an approval commit this
   clone does not hold, a missing `commit`, `by` or `at`, a record not
   written field by field, an `Accept-test:` line the checker refuses, or an
   approved path absent at the approval commit. Nothing read from a ticket is
   printed but ticket ids, requirement ids, approval commits and checked
   `Accept-test:` lines.
8. **The judge cannot be edited by the pull request it judges.** The shipped
   pairing workflow and the kit's guards workflow run one identical step: it
   extracts `scripts/` from the base commit's objects and runs that copy of
   the guard with `POLICY_BASE` set to the base. A release that changes the
   guard is judged by the old one. A base with no guard yet holds nothing and
   the step passes with a notice — the one state before adoption.
9. **Tests-first mode never edits an approved file.** The build's own extra
   tests go in other files, so the file-level hold and the build agree
   (`/implement`, PRD-14 slice 3).

### Consequences

- Good: a pull request that changes an approved test cannot pass the
  required check, whoever holds the token, once the ruleset requires it.
- Good: the approved tests stay off `main` until the build, so `main` stays
  green.
- Bad: any byte change to a held file fails, including an honest one; the
  operator approves again (`factory approve --tests`).
- Bad: the guard reads every factory ticket through the policy reader, one
  process each: about 3 seconds for the kit's 99 tickets (diary, 2026-11-02).

## Confirmation

`tests/acceptance-guard.test.sh` builds throwaway factory projects with a
`main`, a branch and an approval commit off `main`, and holds every clause:
the `changed:` line and its pass, a branch rewriting its own record, a
deleted file, a `done` and an unapproved ticket, each fail-closed cause, no
factory project in three shapes, the `tests` answers and the adoption date's
three states, `held`, and the CI step extracted from both workflows run
against a pull request that edits the guard to always pass.
`tests/policy.test.sh` holds the judging set's ticket files and `touched`'s
approval-record rule.
