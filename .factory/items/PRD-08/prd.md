---
id: PRD-08
type: prd
title: Policy files judged by the base branch, failing closed
parent: D-02
stage: review
created: 2026-10-28
updated: 2026-10-28
stages:
  - {stage: draft, at: 2026-10-28T12:26Z}
  - {stage: review, at: 2026-10-28T12:50Z}
---


# PRD-08 · Policy files judged by the base branch, failing closed

## 1. Objective

Make every guard, gate and review reader that judges a pull request read its policy files as
they stand on the base branch, not as the pull request left them, and treat a policy file that is
missing or unreadable there as a failed judgment, never as a pass. Hold D-02's Q3 thresholds
(the miss-rate ceiling and the precision floor) in one new policy file, read the same way.

**Problem.** The kit's judgments are policy as data: the TDD pairing guard reads which paths are
source from the guards policy, the docs gate reads what it enforces from its gate config, the
review slices a diff among its lenses by the lens-slice policy, and the check-table reader and
stamp reader hold words to the vocabulary policy. Today every one of them reads that data from
the tree it runs in, and on a pull request that tree is the PR's own. So a PR can loosen the rule
that judges it: drop its source directory from the guards policy and land code with no test, add
an exemption to the gate config, or narrow the security lens's paths so the lens never sees its
diff. The shipped pairing workflow says so in its own header ("a PR that edits them is checked by
its edits") and leaves it to human review. D-02's later stages remove that human from low-risk
PRs (K5), and they need numbers to decide what is low risk (Q3). Those numbers cannot sit in a
file the PR being judged may edit. D-02's research adopted the answer from S-14: a PR that edits
a policy file is judged by the base branch's version, failing closed to a human (research.md,
recommendation 2; decisions.md, Q3).

**Solution, from the user's side.**
- A new **policy reader** answers three questions, each at a base ref: give me this policy
  file as the base has it (`read`), which judging files does this diff touch (`touched`), and
  what are the risk thresholds (`thresholds`). Each answer is either the data or one
  `fail-closed <reason> <path>` line with its own exit code, never a fallback to the working tree.
- A new **risk policy** ships filled with Q3's numbers: an area's reviews must miss fewer than
  5% of its mistakes, and at least 80% of its lens findings must hold up.
- One environment variable, `POLICY_BASE`, tells every judge which ref to read its policy at. The
  shipped CI workflows set it to the pull request's base commit, and `/review-pr` sets it to the
  base it reviews against. Where it is unset (a local push, a hand-run gate) every judge reads the
  working tree, as today.
- On a fail-closed answer each judge takes its strictest path: the guard and the gate fail the
  check, the slicer hands every lens the whole diff, and the check-table reader refuses, so the
  review lists every covered requirement as missing.

K2 acts on nothing itself. It gives K3's risk rule (PRD-09) and K5's lane (PRD-10) a policy they
can trust and one way to read it: K3 turns a fail-closed answer into high risk, and a touched
judging file into high risk too (§8).

**The test of done.** In a fixture repository whose `main` holds the shipped risk policy and a
guards policy naming `src/` as source, a branch lowers the precision floor to 50, removes `src/`
from the source pattern, and adds `src/a.sh` with no test. Then:
- `sh scripts/policy.sh thresholds --base main` prints `precision-floor 80`;
- `sh scripts/policy.sh touched main HEAD` prints both policy files and exits 1;
- the pairing guard run with `POLICY_BASE=main` fails on `src/a.sh`;
- after `main` loses its risk policy, `thresholds` prints `fail-closed missing scripts/risk.config.sh`
  and exits 3.

## 2. Users and scenarios

**U1 — the operator**, who tightens a threshold or a guard and wants that to bind the next PR at
once, and no PR to loosen it for itself. **U2 — an implementing session or a CI job**, which runs
a guard or the gate on a PR. **U3 — `/review-pr`**, which slices the diff and reads the check
table. **U4 — the risk rule (K3) and the lane (K5)**, which will read thresholds and touched
judging files through this PRD's interface.

Stories:

1. As the operator, I want a PR's guards, gate and review to use the policy on the base branch,
   so that no PR can loosen the rule that judges it.
2. As the operator, I want a policy file that is missing or broken on the base branch to fail the
   judgment, so that a lost file never reads as permission.
3. As the operator, I want Q3's thresholds in a policy file I can tighten without a kit release,
   and the tightening to apply from the moment it lands.
4. As the author of K3 and K5, I want one reader with fixed output shapes and exit codes, so that
   the risk rule and the lane neither re-implement the base read nor guess what a failure looks
   like.
5. As a consumer who runs the hooks locally, I want a local push to keep reading my working tree,
   so that I can try a policy change before I open the PR.

**UC1 — The operator tightens the precision floor.** Actor: the operator, on a branch
`chore/floor-90` off `main`. Goal: the floor binds every PR judged after it lands, and none
before.
1. The operator changes `precision-floor` from 80 to 90 in the risk policy, commits and opens
   PR #910.
2. `sh scripts/policy.sh touched origin/main HEAD` prints `scripts/risk.config.sh` and exits 1.
   (K3 will read that line as high risk, so #910 waits for the operator.)
3. While #910 is open, PR #911 is judged. `sh scripts/policy.sh read scripts/risk.config.sh
   --base origin/main` prints the path of a copy of `main`'s file, outside the working tree.
4. `sh scripts/policy.sh thresholds --base origin/main` prints `miss-rate-below 5` and
   `precision-floor 80`: #910's 90 does not apply yet.
5. #910 lands. The same command, after a fetch, prints `precision-floor 90`.

Extensions:
- 2a. The branch deletes the risk policy. `touched` prints its path all the same: a deleted
  judging file is touched.
- 3a. `main` holds no risk policy (a consumer deleted it). `read` prints `fail-closed missing
  scripts/risk.config.sh` on standard output, exits 3 and writes no copy. The working tree's
  copy, present on the branch, is not read.
- 3b. `main`'s risk policy has a shell syntax error. `read` prints `fail-closed invalid
  scripts/risk.config.sh` and exits 3.
- 3c. `origin/main` is not fetched in this clone. `read` prints `fail-closed no-base
  scripts/risk.config.sh` and exits 3.
- 3d. The caller asks for `read docs/notes.md`, which is not a judging file. The reader exits 2,
  prints nothing on standard output, and writes no copy.
- 4a. `main`'s risk policy sets `precision-floor=eighty`, or leaves it empty, or sets 120.
  `thresholds` prints `fail-closed invalid scripts/risk.config.sh`, no threshold line, and exits 3.

**UC2 — A PR loosens the guard that judges it.** Actor: an implementing session, and the CI job
that runs the pairing guard on its PR #912. Goal: the guard judges #912 by `main`'s source
pattern.
1. #912 edits the guards policy so `GUARD_SOURCE_RE` no longer matches `src/`, and adds
   `src/parse.sh` with no test change.
2. The shipped pairing workflow runs the guard with `POLICY_BASE` set to the PR's base commit.
   The guard reads the guards policy through the policy reader at that commit, where `src/`
   is still source.
3. The guard fails: `src/parse.sh` changed with no test.

Extensions:
- 2a. `main` has no guards policy. The guard prints `fail-closed missing scripts/guards.config.sh`
  and exits non-zero. It does not take the unconfigured path that warns and passes.
- 2b. `main`'s guards policy is present and sets no source pattern (a consumer who has not
  configured the guard). The guard warns once and passes, exactly as today.
- 2c. The session pushes #912 from its worktree. The pre-push hook runs with no `POLICY_BASE`,
  reads the working tree's guards policy, and passes. CI, not the local hook, is the judge.

**UC3 — A PR edits the docs gate's config to pass its own violation.** Actor: the docs gate in
CI on PR #913, which adds a document carrying a stale term and, in the same diff, an exemption
for it in the gate config. Goal: the gate judges #913 by `main`'s config.
1. The docs gate workflow runs the gate with `POLICY_BASE` set to the base commit.
2. The gate loads its config module, and the local-vocabulary module beside it, from the reader's
   copies at that commit. `main`'s config has no exemption.
3. The gate fails on the stale term.

Extensions:
- 2a. `main` has no gate config. The gate prints `fail-closed missing
  scripts/docs-conformance/config.mjs`, runs no validator, and exits 1.
- 2b. `main` has no local-vocabulary module, which is optional today. The gate reads an empty
  local vocabulary, as it does today when the module is absent: that is the stricter reading.
- 2c. node is absent. The gate's reduced POSIX form reads the two values it reads from the
  config, from the reader's copy at that commit.

**UC4 — The review slices a diff by `main`'s lens rules.** Actor: `/review-pr`, reviewing PR
#914 against `origin/main`. #914 edits the lens-slice policy so the security lens excludes
`scripts/`, and changes `scripts/land.kit.sh`. Goal: the security lens sees the change.
1. `/review-pr` runs the slicer, the behavior-delta lister and the check-table reader with
   `POLICY_BASE=origin/main`.
2. The slicer reads the lens-slice policy at `origin/main`, where `scripts/` is in the security
   lens's paths, and writes `scripts/land.kit.sh`'s hunks into the security slice.
3. The behavior-delta lister reads `BEHAVIOR_DELTA_SURFACES` from the guards policy at
   `origin/main`, and the check-table reader reads its words from the vocabulary policy there.

Extensions:
- 2a. `origin/main` has no lens-slice policy. The slicer writes the whole diff into every lens's
  slice, prints `fail-closed missing scripts/lens-slice.config.sh`, and exits 3. `/review-pr`
  runs every standards lens on its whole slice and prints the fail-closed line in its report's
  summary.
- 3a. The guards policy fails closed at `origin/main`. The behavior-delta lister prints the
  fail-closed line, then lists every path the diff changes as a candidate.
- 3b. The vocabulary policy fails closed at `origin/main`. The check-table reader prints the
  fail-closed line and exits 2, so the review lists every id on the ticket's `Covers:` line as
  ❌ MISSING, as it already does for a refused table.

## 3. Model

- **Base branch's version**: a file's content at the commit a ref names, read from git's objects.
  For a PR it is the base branch's tip as the judge sees it: in CI the pull request event's base
  commit, in a review the ref the review diffs against. The merge base is not used (§8).
- **Judging file**: a file whose content decides how a change is judged. The **judging set** is,
  by whole repository-relative path: every file directly under `scripts/` whose name ends
  `.config.sh` (every policy file the kit ships and its kit-only twins); the docs gate's config
  module and its local-vocabulary module; every file directly under `.githooks/` and
  `.github/workflows/` (where the guards and the gate are wired); the risk policy; and every path
  the risk policy's extra list names at the base. A file with the same name in another directory
  is not in the set (S-14: only exact names are trusted).
- **Policy reader**: the one program that reads a judging file at a base ref. It has three
  questions: `read <path> --base <ref>`, `touched <base> <head>` and `thresholds --base <ref>`.
- **Fail closed**: the reader's answer when it cannot give the base branch's version. It is one
  line on standard output, `fail-closed <reason> <path>`, and exit 3. The reasons are a closed
  set: `no-base` (the ref names no commit here), `missing` (the path is absent at the ref),
  `unreadable` (not a regular file, or git cannot produce its content), and `invalid` (a shell
  file fails the syntax check, or a threshold is out of shape). The line carries no text read
  from any file. Each judge maps the answer to its strictest path:

  | Judge | Strictest path on fail closed |
  |---|---|
  | TDD pairing guard (CI) | fails the check |
  | docs gate (CI) | exits 1, runs no validator |
  | lens slicer (review) | every lens gets the whole diff; exit 3 |
  | behavior-delta lister (review) | every changed path is a candidate |
  | check-table reader (review) | refuses (exit 2): every covered id is ❌ MISSING |
  | risk rule (K3, later) | high risk (§8) |

- **`POLICY_BASE`**: the ref every judge reads its policy at. Set, each judge reads through the
  policy reader at that ref and never from the working tree. Unset, each judge reads the working
  tree, as today. An override that names a policy file explicitly (`GUARDS_CONFIG`,
  `VOCAB_CONFIG`, `LENS_SLICE_CONFIG`) is read at `POLICY_BASE` when it names a judging file, and
  as given when it names a path outside the set (a test fixture).
- **Risk policy**: a new policy file, shipped filled (ADR-0003's 2026-09-28 amendment: a policy
  the kit can fill ships filled, no twin). It holds:
  - `miss-rate-below`: a whole percent, 0 to 100. Shipped 5, Q3's "fewer than 1 in 20". An area
    meets it when its miss rate, in percent, is strictly below it. Over a full 20-landing window
    that means no missed mistake, so one escaped mistake drops the area at once, as Q3 says.
  - `precision-floor`: a whole percent, 0 to 100. Shipped 80, Q3's "at least 80%". An area meets
    it when its lens precision, in percent, is at or above it.
  - an extra list, shipped empty: more repository-relative paths to treat as judging files.
  Comparing the earned record (PRD-06) with these numbers is K3's work, not this PRD's.

**Inventory: the kit's policy files and what K2 does with each.**

| Policy file | Read by | Judges a PR? | K2 |
|---|---|---|---|
| guards policy (and the kit's guards twin) | pairing guard (pre-push, CI); behavior-delta lister (review) | yes | read at `POLICY_BASE`, slices 2 and 4 |
| docs gate config and local vocabulary | docs gate (full and POSIX form) | yes | read at `POLICY_BASE`, slice 3 |
| lens-slice policy | lens slicer (review); its `--areas` form (record reader) | yes, in review | slicer read at `POLICY_BASE`, slice 4; `--areas` unchanged |
| vocabulary policy | vocabulary checker, stamp reader, check-table reader | yes, the check table in review | read at `POLICY_BASE`, slice 4 |
| risk policy (new) | policy reader's `thresholds` | yes, from K3 | read at a base always, slice 1 |
| agents policy (and the kit's two twins) | tier resolver: which model reviews | indirectly | touched only; base read *later* (§6) |
| trace policy (and the kit's twin) | trace; its fix window feeds the earned record | indirectly | touched only; *later* (§6) |
| broker policy (kit-only) | the review broker's allow-list | no; operator-side | touched only |

Every row is in the judging set, so `touched` reports a PR that edits any of them.

## 4. Rules

Area: policy

No living spec exists for this area. The first ticket that covers one of these lines creates
`docs/specs/policy.md`, keeping these numbers.

policy/R1. WHEN asked to `read` a judging file at a base ref, the policy reader SHALL write the file's content at that ref to a copy outside the working tree, at its repository-relative path under one directory per base commit, print the copy's absolute path, and exit 0. [UC1 3]
policy/R2. WHEN given a base ref, the policy reader SHALL read no file from the working tree, on success or on failure. [UC1 3a]
policy/R3. IF the path asked for is not in the judging set, THEN the policy reader SHALL exit 2, print nothing on standard output, and write no copy. [UC1 3d]
policy/R4. IF the base ref names no commit in the repository, THEN the policy reader SHALL print `fail-closed no-base <path>` and exit 3. [UC1 3c]
policy/R5. IF the path is absent at the base ref, THEN the policy reader SHALL print `fail-closed missing <path>` and exit 3, writing no copy. [UC1 3a]
policy/R6. IF the entry at the base ref is not a regular file, or git cannot produce its content, THEN the policy reader SHALL print `fail-closed unreadable <path>` and exit 3.
policy/R7. IF a judging file whose name ends `.sh` fails `sh -n` at the base ref, THEN the policy reader SHALL print `fail-closed invalid <path>` and exit 3. [UC1 3b]
policy/R8. A fail-closed line SHALL hold exactly three space-separated fields, `fail-closed`, one of `no-base` `missing` `unreadable` `invalid`, and the repository-relative path, and nothing read from any file.
policy/R9. The judging set SHALL hold exactly the files directly under `scripts/` whose names end `.config.sh`, the docs gate's config and local-vocabulary modules, the files directly under `.githooks/` and `.github/workflows/`, the risk policy, and each path the risk policy's extra list names at the base ref, each matched by its whole repository-relative path. [UC1 3d]
policy/R10. WHEN asked for `touched <base> <head>`, the policy reader SHALL print, one per line and sorted, each judging-set path that the diff from the two refs' merge base to the head adds, modifies, deletes, or renames from or to, and SHALL exit 1 when it printed one and 0 when it printed none. [UC1 2, 2a]
policy/R11. IF the risk policy fails closed at the base while `touched` runs, THEN the policy reader SHALL print the touched paths the rest of the judging set selects, then the fail-closed line, and exit 3.
policy/R12. WHEN asked for `thresholds --base <ref>`, the policy reader SHALL print exactly two lines, `miss-rate-below <n>` then `precision-floor <n>`, from the risk policy at that ref, and exit 0. [UC1 4, 5]
policy/R13. IF a threshold in the risk policy at the ref is unset, empty, or not a whole number from 0 to 100, THEN the policy reader SHALL print `fail-closed invalid <risk policy path>`, print no threshold line, and exit 3. [UC1 4a]
policy/R14. The policy reader SHALL evaluate a shell judging file only in a child process, so that no variable, function or directory change the file makes reaches the reader's caller.
policy/R15. The risk policy SHALL ship with `miss-rate-below` 5, `precision-floor` 80 and an empty extra list.
policy/R16. WHERE `POLICY_BASE` is unset, the pairing guard, the behavior-delta lister, the docs gate, the lens slicer and the vocabulary checker SHALL read their policy files from the working tree as they do today. [UC2 2c]
policy/R17. WHERE `POLICY_BASE` names a ref, a policy override that names a judging file SHALL be read at that ref through the policy reader, and one that names a path outside the judging set SHALL be read as given.
policy/R18. WHERE `POLICY_BASE` names a ref, the TDD pairing guard SHALL read the guards policy through the policy reader at that ref. [UC2 2, 3]
policy/R19. IF `POLICY_BASE` names a ref and the policy reader fails closed on the guards policy, THEN the pairing guard SHALL print the fail-closed line and exit non-zero, and SHALL NOT warn and pass. [UC2 2a]
policy/R20. WHERE the guards policy at `POLICY_BASE` is present and sets no source pattern, the pairing guard SHALL warn once and pass. [UC2 2b]
policy/R21. The shipped TDD pairing workflow SHALL set `POLICY_BASE` to the pull request's base commit. [UC2 2]
policy/R22. WHERE `POLICY_BASE` names a ref, the docs gate SHALL load its config module and local-vocabulary module from the policy reader's copies at that ref, in its full form, and SHALL read its two config values from the copy at that ref in its reduced POSIX form. [UC3 2, 2c]
policy/R23. IF `POLICY_BASE` names a ref and the policy reader fails closed on the docs gate's config module, THEN the docs gate SHALL print the fail-closed line, run no validator, and exit 1. [UC3 2a]
policy/R24. IF the local-vocabulary module is missing at `POLICY_BASE`, THEN the docs gate SHALL read an empty local vocabulary. [UC3 2b]
policy/R25. The shipped docs gate workflow, and each job of the kit's own CI that runs the docs gate on a pull request, SHALL set `POLICY_BASE` to the pull request's base commit, with that commit fetched. [UC3 1]
policy/R26. WHERE `POLICY_BASE` names a ref, the lens slicer SHALL read the lens-slice policy through the policy reader at that ref. [UC4 2]
policy/R27. IF `POLICY_BASE` names a ref and the policy reader fails closed on the lens-slice policy, THEN the lens slicer SHALL write the whole diff into every lens's slice, print the fail-closed line, and exit 3. [UC4 2a]
policy/R28. WHERE `POLICY_BASE` names a ref, the behavior-delta lister SHALL read the guards policy through the policy reader at that ref. [UC4 3]
policy/R29. IF `POLICY_BASE` names a ref and the policy reader fails closed on the guards policy, THEN the behavior-delta lister SHALL print the fail-closed line first and list every path the diff changes as a candidate. [UC4 3a]
policy/R30. WHERE `POLICY_BASE` names a ref, the vocabulary checker SHALL read the vocabulary policy through the policy reader at that ref. [UC4 3]
policy/R31. IF `POLICY_BASE` names a ref and the policy reader fails closed on the vocabulary policy, THEN the check-table reader SHALL print the fail-closed line and exit 2. [UC4 3b]
policy/R32. `/review-pr` SHALL run the lens slicer, the behavior-delta lister and the check-table reader with `POLICY_BASE` set to the base ref it reviews against. [UC4 1]
policy/R33. WHEN the lens slicer exits 3, `/review-pr` SHALL run every standards lens on its whole-diff slice and print the fail-closed line in its report's summary. [UC4 2a]

## 5. Slices (vertical, demoable, in order)

Every slice moves a `VERSION`-listed file (a new script, or a guard, gate or skill that already
ships), so each is a shared-layer release. ADR-0033 chains them one per frontier, in this order.

**Slice 1 — the policy reader and the risk policy.** The tracer bullet: one policy file, read at
the base, failing closed, end to end.
- *Covers:* policy/R1, policy/R2, policy/R3, policy/R4, policy/R5, policy/R6, policy/R7, policy/R8, policy/R9, policy/R10, policy/R11, policy/R12, policy/R13, policy/R14, policy/R15.
- *Also:* the decision record (§8); the glossary entries base branch's version, judging file,
  policy reader, fail closed, risk policy; the risk policy in `VERSION`'s list of policy files
  and in bootstrap's copy; an AGENTS.md quick-reference row.
- *Accept:* in a fixture repository, a branch that lowers `precision-floor` to 50 still gets
  `precision-floor 80` from `thresholds --base main`, and `touched main HEAD` prints the risk
  policy and exits 1. Deleting the file on `main` gives `fail-closed missing …`, exit 3, with the
  branch's copy present in the working tree. A syntax error gives `invalid`, an unfetched ref
  `no-base`, `precision-floor=eighty` `invalid`, and `read docs/notes.md` exit 2. A copy of the
  file at `other/scripts/risk.config.sh` is not in the judging set. A file that sets a variable
  leaves the caller's environment unchanged.

**Slice 2 — the pairing guard judged by the base.**
- *Covers:* policy/R16, policy/R17, policy/R18, policy/R19, policy/R20, policy/R21.
- *Accept:* UC2's fixture fails the guard under `POLICY_BASE=main` and passes it with
  `POLICY_BASE` unset. A `main` with no guards policy fails with the fail-closed line; a `main`
  whose guards policy sets no source pattern warns and passes. The kit's guards twin, named by
  override, is read at the base. The workflow template's suite asserts the variable is set from
  the PR's base commit.

**Slice 3 — the docs gate judged by the base.**
- *Covers:* policy/R22, policy/R23, policy/R24, policy/R25.
- *Accept:* UC3's fixture fails the gate under `POLICY_BASE=main` in both forms (node present,
  node absent). A `main` with no gate config exits 1 with the fail-closed line and no validator
  output. A `main` with no local-vocabulary module gives the same result as today. The kit's own
  self-host run on a PR sets the variable, and `scripts/check.sh` on the kit is green.

**Slice 4 — the review judged by the base.**
- *Covers:* policy/R26, policy/R27, policy/R28, policy/R29, policy/R30, policy/R31, policy/R32, policy/R33.
- *Accept:* UC4's fixture puts `scripts/land.kit.sh`'s hunks in the security slice under
  `POLICY_BASE=main`. A `main` with no lens-slice policy gives every lens the whole diff and exit
  3; with no guards policy, every changed path is a behavior candidate; with no vocabulary
  policy, the check-table reader exits 2. The review skill's suite asserts `/review-pr` sets the
  variable for all three readers and prints the fail-closed line in its summary.

## 6. Non-goals (this PRD)

- **Comparing an area's earned record with the thresholds, and labelling a PR low or high.**
  *Later*, K3 (PRD-09). K2 prints the numbers and the touched files; it never says `low` or
  `high`.
- **The kill switch.** *Later*, K3. If K3 keeps it in the risk policy, it is read at the base
  through this reader like the thresholds, and a PR cannot untrip it for itself.
- **Reading the PR's scripts (the mechanism) from the base branch.** *Never* in K2. CI runs the
  PR's own guard and gate scripts. A PR that edits them moves a `VERSION`-listed file, which the
  landing script already refuses without a release (ADR-0025) and which the planner stamps
  `Risk: high shared-layer`. Reopen if a mechanism change is found loosening a judgment between
  release and review.
- **Reading the agents policy at the base for the reviewer's resolution.** *Later*. A PR that
  edits it is in the judging set, so `touched` reports it and K3 holds it high. Reopen if K5's
  lane ever lands a PR whose review was resolved from a policy the PR changed.
- **Reading the trace policy's fix window at the base.** *Later*. The earned record is computed by
  the operator and `/retro` from the root checkout, which is on the base branch. Reopen when K3
  computes the record inside a PR's worktree.
- **Changing the local hooks.** *Never*: a local push reads the working tree (story 5), and CI is
  the judge (UC2 2c).
- **Failing closed in the agent harness's own hooks.** *Later*: the root guard fails open on
  purpose, and whether a sub-agent's hook should fail closed is D-02 research §5 question 3,
  still open. K2's fail-closed rule is about a judge's policy file, not a hook's parse failure.
- **The record reader's `--areas` form reading the lens-slice policy at a base.** *Later*, with
  the fix window above: it runs from the root checkout.
- **Moving the earned record's 20-landing window into the risk policy.** Open (§9).

## 7. Technical constraints

- POSIX `sh` and `git` only, like the guards. The docs gate's full form stays plain ESM with no
  package manager; it loads the copies by path.
- The reader reads the base branch's version from git's objects alone. It never checks out, never
  switches branch, never writes inside the working tree, and never fetches: an unfetched ref is
  `no-base`. Copies live under the repository's git directory, one directory per base commit, at
  their repository-relative paths, so a config module's relative import of its sibling resolves.
- A policy file is code (the kit's 0.6.0 trust wave: "a config is sourced, i.e. CODE"). Sourcing
  the base's copy is safe because the base branch is the trusted tree. No judge sources the PR's
  copy while `POLICY_BASE` is set.
- The shipped workflows must hold the base commit's objects: the pairing workflow already checks
  out full history, and the docs gate workflow gains whatever fetch puts the base commit in reach
  (policy/R25).
- A base policy may name a validator or path that the PR's tree no longer has. The judge then fails
  as it would on a broken policy. That is a closed failure, and a PR that removes what a policy
  names touches a judging file or a `VERSION`-listed file anyway.
- **Tests** drive each judge from outside, in throwaway git repositories with a `main` and a
  branch, asserting exit codes and the exact fail-closed line. Prior art: the pairing guard's CI
  suite (simulated event payload, throwaway repositories), the lens-slice suite, the check-table
  suite, and the docs harness's fixture trees. Every fail-closed reason has a fixture that
  produces it.
- **Numbers, not quality words:** thresholds are whole percents 0–100; a fail-closed line has
  exactly three fields; `touched` exits 1 on any hit. The reader's speed is not promised; slice 1
  measures one `read` on the kit and records it in the diary.

## 8. Decisions recorded for this PRD

**From D-02** (decisions.md, 2026-10-23, the operator): Q1 (a policy, guard or gate file is high
risk because its mistake is not countable), Q3 (the two thresholds, in a policy file judged by
main's version and failing closed when missing), Q7 (K2 before anything reads a threshold), and
research recommendation 2 (adopt S-14).

**Derived while writing** (the session, under the operator's standing delegation of rulings; the
maintainer confirms them at approval):

- **One reader, three questions, one failure shape.** Every judge reads a judging file through
  the policy reader; none re-implements the base read. A fail-closed answer is exit 3 and one
  `fail-closed <reason> <path>` line on standard output, with four reasons. K3 and K5 build on
  this shape, so it is fixed here.
- **One variable says where to read.** `POLICY_BASE` names the ref. Set, nothing falls back to the
  working tree. Unset, every judge behaves as it does today. The alternative, each judge taking
  its own base argument, would leave a consumer's own judges to rediscover the rule.
- **The base branch's tip, not the merge base.** Q3 says the operator tightens a threshold
  without a kit change; reading the tip makes a tightening bind every open PR from the moment it
  lands. The merge base would let an old branch keep the looser rule it started under.
- **The judging set is fixed by place and suffix, plus an extra list read at the base.** Exact
  directories and the existing naming convention cover every policy file the kit ships, its
  kit-only twins and a consumer's own, with no list a PR could shorten. The extra list only adds,
  and it is read at the base, so a PR cannot remove its own file from the set.
- **A missing local vocabulary reads as empty.** It is optional today, and empty is the stricter
  reading, so absence is already closed.
- **CI and the review are the judges; local hooks are not.** A local push keeps the working tree
  (story 5). The landing script and the train run from the root checkout on the base branch, so
  they read the base's policy already.
- **What K3 does with K2's answers** (a constraint handed to PRD-09, which writes the
  requirement): a fail-closed answer on the risk policy makes the PR `high unlearned`, since the
  rule cannot show the area learned; a PR that `touched` reports makes it `high shared-layer`,
  the reason the `Risk:` contract already gives policy, guard and gate files. Neither needs a new
  reason token, so the contract with the factory (D-08) does not move.
- **The thresholds are whole percents.** POSIX `sh` compares integers natively. "Fewer than 1 in
  20" is `miss-rate-below 5`, and "at least 80%" is `precision-floor 80`.

**Decision records:**
- **Needed at slice 1:** one record, "a judge reads its policy from the base branch, failing
  closed": the judging set, `POLICY_BASE`, the fail-closed shape and reasons, and the strictest
  path per judge. It narrows the stance in the shipped pairing workflow's header ("a PR that
  edits them is checked by its edits") for policy data; for mechanism that stance stands.
- **Cited:** ADR-0003 and its 2026-09-28 amendment (the risk policy ships filled, no twin),
  ADR-0025 (a mechanism change is a release), ADR-0033 (one shared-layer ticket per frontier),
  ADR-0036 (the earned record the thresholds will be compared with), ADR-0037 (the `Risk:`
  contract and its reasons), and ADR-0017 (a shipped file cites a kit record only as the kit's).

**Alternatives considered:**

- **Run the PR's workflows from the base (`pull_request_target`).** This reads every file at the
  base, mechanism included, but it is GitHub-only and runs with a write token next to untrusted
  code. The kit's core is forge-neutral `sh` and `git`.
- **A closed list of policy files written in the reader.** The kit's twins and a consumer's own
  policy files would need a reader change each time. The place-and-suffix rule covers them.
- **Fail closed by falling back to the shipped defaults.** A default is a value the operator did
  not choose; Q3 says missing means fail closed, not a quiet default.

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

- **Is the earned record's 20-landing window one of Q3's "numbers"?**
  - Options: keep it fixed at 20 in the record reader (ADR-0036 as built), with the risk policy
    holding the two thresholds; or move it into the risk policy, with a MODIFIED runtime/R44 so
    the record reader reads it.
  - Next step: question to agranado at K3's grill, where the comparison is designed. MVP default:
    fixed at 20; K2 holds two thresholds.
- **Should `touched` also report `VERSION`-listed files?**
  - Options: K2 reports judging files only, and K3 reads `VERSION`'s list through the landing
    script's existing read (ADR-0025); or `touched` reports both, so K3 has one query.
  - Next step: question to agranado at K3's grill. MVP default: judging files only.

## 10. Dogfood plan

Four tickets in slice order, chained one per frontier (ADR-0033). After slice 1 lands, the kit's
own `/retro` can print `thresholds --base origin/main` beside the earned record, ready for K3.
After slice 2 and 3, the kit's own CI judges each PR by `main`'s policy, and the first PR that
edits a policy file is the live demo: `touched` reports it, and its guards and gate run on
`main`'s rules. After slice 4, `/review-pr` on the kit slices by `main`'s lens rules.
