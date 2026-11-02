# Policy

The kit's living spec for the **policy** area: how a judge reads the policy
files that decide how a pull request is judged — as the base branch has them,
failing closed — and the risk policy that holds the thresholds. ADR-0039 is
the contract; the file's format is the starter a consumer gets,
`templates/docs/specs/README.md`.

Seeded by #904 from PRD-08's Rules (factory item, D-02), keeping its numbers;
each requirement joins this file with the ticket that delivers it. Outside
this file a requirement is cited as `policy/R<n>`, and the docs gate fails one
that no suite under `tests/` names. The kit's own: bootstrap strips it, so no
consumer inherits a spec whose tests it does not have.

R1. WHEN asked to `read` a judging file at a base ref, the policy reader SHALL write the file's content at that ref to a copy outside the working tree, at its repository-relative path under one directory per base commit, print the copy's absolute path, and exit 0.
R2. WHEN given a base ref, the policy reader SHALL read no file from the working tree, on success or on failure.
R3. IF the path asked for is not in the judging set, THEN the policy reader SHALL exit 2, print nothing on standard output, and write no copy.
R4. IF the base ref names no commit in the repository, THEN the policy reader SHALL print `fail-closed no-base <path>` and exit 3.
R5. IF the path is absent at the base ref, THEN the policy reader SHALL print `fail-closed missing <path>` and exit 3, writing no copy.
R6. IF the entry at the base ref is not a regular file, or git cannot produce its content, THEN the policy reader SHALL print `fail-closed unreadable <path>` and exit 3.
R7. IF a judging file whose name ends `.sh` fails `sh -n` at the base ref, THEN the policy reader SHALL print `fail-closed invalid <path>` and exit 3.
R8. A fail-closed line SHALL hold exactly three space-separated fields, `fail-closed`, one of `no-base` `missing` `unreadable` `invalid`, and the repository-relative path, and nothing read from any file.
R9. The judging set SHALL hold exactly the files directly under `scripts/` whose names end `.config.sh`, the docs gate's config and local-vocabulary modules, the files directly under `.githooks/` and `.github/workflows/`, every file named `ticket.md` directly under a directory directly under `.factory/items/`, the factory project manifest `.factory/project.yaml`, the risk policy, and each path the risk policy's extra list names at the base ref, each matched by its whole repository-relative path; `touched` reports a factory ticket file only as policy/R10 says. [UC3 2, 2c]
R10. WHEN asked for `touched <base> <head>`, the policy reader SHALL print, one per line and sorted, each judging-set path that the diff from the two refs' merge base to the head adds, modifies, deletes, or renames from or to, except a factory ticket file, which it SHALL print only when the front matter `tests:` approval record differs between the merge base and the head (added, removed or changed), and SHALL exit 1 when it printed one and 0 when it printed none. [UC3 2]
R11. IF the risk policy fails closed at the base while `touched` runs, THEN the policy reader SHALL print the touched paths the rest of the judging set selects, then the fail-closed line, and exit 3.
R12. WHEN asked for `thresholds --base <ref>`, the policy reader SHALL print exactly two lines, `miss-rate-below <n>` then `precision-floor <n>`, from the risk policy at that ref, and exit 0.
R13. IF a threshold in the risk policy at the ref is unset, empty, or not a whole number from 0 to 100, THEN the policy reader SHALL print `fail-closed invalid <risk policy path>`, print no threshold line, and exit 3.
R14. The policy reader SHALL evaluate a shell judging file only in a child process, so that no variable, function or directory change the file makes reaches the reader's caller.
R15. The risk policy SHALL ship with `miss-rate-below` 5, `precision-floor` 80 and an empty extra list.
R16. WHERE `POLICY_BASE` is unset, the pairing guard, the behavior-delta lister, the docs gate, the lens slicer and the vocabulary checker SHALL read their policy files from the working tree as they do today.
R17. WHERE `POLICY_BASE` names a ref, a policy override that names a judging file SHALL be read at that ref through the policy reader, and one that names a path outside the judging set SHALL be read as given.
R18. WHERE `POLICY_BASE` names a ref, the TDD pairing guard SHALL read the guards policy through the policy reader at that ref.
R19. IF `POLICY_BASE` names a ref and the policy reader fails closed on the guards policy, THEN the pairing guard SHALL print the fail-closed line and exit non-zero, and SHALL NOT warn and pass.
R20. WHERE the guards policy at `POLICY_BASE` is present and sets no source pattern, the pairing guard SHALL warn once and pass.
R21. The shipped TDD pairing workflow SHALL set `POLICY_BASE` to the pull request's base commit.
