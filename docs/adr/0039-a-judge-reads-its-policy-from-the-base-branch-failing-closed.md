# ADR-0039: A judge reads its policy from the base branch, failing closed

- **Status**: Accepted
- **Date**: 2026-11-01
- **Deciders**: the planner session for #904, under the operator's delegation of rulings; the rule itself was the operator's in the software factory's D-02 session (decisions Q1 and Q3, research recommendation 2, adopting S-14) and PRD-08 §8; the merge of its pull request is the operator's yes
- **Supersedes / amends**: — (narrows, for policy data only, the stance in the shipped pairing workflow's header, `templates/workflows/tdd-pairing.yml`: "a PR that edits them is checked by its edits")
- **Superseded by**: —

## Context and problem statement

The kit's judgments are policy as data. The TDD pairing guard reads which
paths are source from the guards policy, the docs gate reads what it
enforces from its config module, `/review-pr` slices a diff among its
lenses by the lens-slice policy, and the check-table reader holds its words
to the vocabulary policy. Every one of them reads that data from the tree it
runs in, and on a pull request that tree is the pull request's own. So a
pull request can loosen the rule that judges it: drop its source directory
from the guards policy and land code with no test, add an exemption to the
gate's config, or narrow the security lens's paths so the lens never sees
its diff. The shipped pairing workflow says so in its header and leaves it
to human review.

D-02's later stages take the human out of low-risk pull requests, and they
need two numbers to decide what is low risk (Q3: a miss rate below 5%, a
precision floor of 80%). Those numbers cannot sit in a file the pull request
being judged may edit. PRD-08 is the work; this record fixes the shape every
later slice and the risk rule build on.

## Decision drivers

- **No pull request loosens its own judge.** The data a judgment reads must
  come from a tree the pull request cannot have changed.
- **A lost policy is not permission.** A file that is missing or broken where
  the judge looks must fail the judgment, never read as "unconfigured, pass".
- **One reader, one failure shape.** The risk rule and the lane (PRD-09,
  PRD-10) read its answers mechanically; each judge must not re-implement the
  base read or guess what a failure looks like.
- **Forge-neutral, `sh` and `git` only**, like the guards it serves.

## Considered options

1. **One policy reader that reads a judging file at a base ref from git's
   objects, failing closed in one shape** *(chosen)*.
2. **Run the pull request's workflows from the base (`pull_request_target`)**
   — rejected: GitHub-only, and it runs a write token next to untrusted code.
3. **A closed list of policy files written into the reader** — rejected: every
   kit-only twin and every consumer's own policy file would need a reader
   change, and a list is something a pull request could shorten.
4. **Fail closed by falling back to the shipped defaults** — rejected: a
   default is a value the operator did not choose, and Q3 says missing means
   fail closed.

## Decision outcome

Chosen: **one policy reader, `scripts/policy.sh`, shared layer**.

1. **The base branch's version.** A judge reads a judging file as it stands
   at the commit a base ref names, from git's objects alone: no checkout, no
   fetch, no read of the working tree. The ref is the base branch's tip — in
   CI the pull request event's base commit, in a review the ref it diffs
   against — never the merge base, so a tightening binds every open pull
   request from the moment it lands.
2. **The judging set**, matched by whole repository-relative path: every file
   directly under `scripts/` whose name ends `.config.sh`; the docs gate's
   `scripts/docs-conformance/config.mjs` and `local-vocabulary.mjs`; every file
   directly under `.githooks/` and `.github/workflows/`; the risk policy; and
   each path the risk policy's extra list names **at the base**. Fixed by place
   and suffix, so no list exists for a pull request to shorten; the extra list
   only adds, and is read at the base. A file of the same name anywhere else
   is not in the set.
3. **Three questions.** `read <path> --base <ref>` writes a copy of the
   base's file under the repository's git directory, at
   `policy/<base commit>/<path>` so a module's relative import of its sibling
   resolves, and prints its absolute path. `touched <base> <head>` prints,
   sorted, each judging-set path the diff from the merge base to the head
   adds, modifies, deletes, or renames from or to, and exits 1 on any.
   `thresholds --base <ref>` prints `miss-rate-below <n>` then
   `precision-floor <n>`. A path outside the set is exit 2, nothing printed,
   nothing written.
4. **Fail closed, one shape.** An answer the reader cannot give is one line
   on standard output, `fail-closed <reason> <path>`, and exit 3. The reasons
   are a closed set: `no-base` (the ref names no commit here), `missing`
   (absent at the base), `unreadable` (not a regular file there, or git cannot
   produce it), `invalid` (a `.sh` judging file fails `sh -n`, or a threshold
   or an extra path is out of shape). The line carries nothing read from any
   file. When the risk policy fails closed during `touched`, the paths the
   rest of the set selects print first, then its line, exit 3; when `touched`
   finds no merge base between its refs (unrelated histories, a shallow
   clone) it answers `fail-closed no-base` and the risk policy's path, and a
   diff git cannot produce `fail-closed unreadable` and that path, never a
   caller error; when `read` is
   asked for a path outside the fixed set and the risk policy fails closed,
   that line answers, since the reader cannot say the path is not judged.
5. **A policy file is code, evaluated only in a child process.** The base's
   copy is trusted because the base is the trusted tree; no judge sources the
   pull request's copy while it reads at a base, and nothing the file sets,
   defines or changes reaches the reader or its caller.
6. **The risk policy**, `scripts/risk.config.sh`: `RISK_MISS_RATE_BELOW` (a
   whole percent, met when an area's miss rate is strictly below it; ships 5),
   `RISK_PRECISION_FLOOR` (a whole percent, met at or above it; ships 80) and
   `RISK_JUDGING_EXTRA` (extra judging paths; ships empty). It ships filled
   with no twin, under ADR-0003's 2026-09-28 amendment. Comparing the earned
   record (ADR-0036) with these numbers is the risk rule's work, not the
   reader's.
7. **`POLICY_BASE` says where to read.** One environment variable names the
   ref every judge reads its policy at. Set, a judge reads through the reader
   at that ref and never falls back to the working tree; an override naming a
   policy file explicitly is read at that ref when it names a judging file,
   and as given when it names a path outside the set. Unset — a local push, a
   hand-run gate — every judge reads the working tree, as before. The shipped
   CI workflows set it to the pull request's base commit, and `/review-pr` to
   the base it reviews against. CI and the review are the judges; the local
   hooks are not.
8. **The strictest path per judge** on a fail-closed answer:

   | Judge | Strictest path |
   |---|---|
   | TDD pairing guard (CI) | fails the check |
   | docs gate (CI) | exits 1, runs no validator |
   | lens slicer (review) | every lens gets the whole diff; exit 3 |
   | behavior-delta lister (review) | every changed path is a candidate |
   | check-table reader (review) | refuses (exit 2): every covered id is missing |
   | risk rule (later) | high risk |

9. **Policy data, not mechanism.** CI still runs the pull request's own guard
   and gate scripts. A pull request that edits them moves a `VERSION`-listed
   file, which the landing script refuses without a release (ADR-0025). The
   pairing workflow's "checked by its edits" stance stands for mechanism and
   is narrowed by this record for policy data.

## Consequences

- **Good**: once the judges are wired (PRD-08 slices 2 to 4), no pull request
  can loosen the guard, the gate or the review that judges it, and a lost
  policy file stops a judgment instead of passing it. The risk rule gets its
  two numbers from a file no pull request can edit for itself.
- **Bad / trade-off**: a consumer who wants to try a policy change must push
  it to the base before CI honours it; a local push still reads the working
  tree, which is the escape. Copies accumulate under the git directory, one
  directory per base commit read; they are small and safe to delete.
- **Neutral**: slice 1 ships the reader and the risk policy with no judge
  reading through it yet; `POLICY_BASE` is read by nothing until slice 2.
- **Honest limitation**: the reader trusts the base. A policy that landed
  loose is read loose; the base is only as good as the review that put it
  there. A path with whitespace cannot be named on the extra list.

## More information

- Implemented in: #904 (PRD-08 slice 1, policy/R1 to policy/R15), held by
  `tests/policy.test.sh`. Slices 2 to 4 wire the pairing guard, the docs gate
  and the review.
- Living spec: `docs/specs/policy.md`.
- Cited: ADR-0003 and its 2026-09-28 amendment, ADR-0017, ADR-0025, ADR-0033,
  ADR-0036, ADR-0037.
