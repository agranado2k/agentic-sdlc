# Acceptance

The kit's living spec for the **acceptance** area: the acceptance tests a
ticket names before its build — the `Accept-test:` line that pins each one,
read and checked out of the ticket's stamp — and, as later slices land, the
guard that holds an approved test from its approval to the ticket's done.
ADR-0037 is the contract for the line; the file's format is the starter a
consumer gets, `templates/docs/specs/README.md`.

Seeded by #969 from PRD-14's Rules (factory item, D-02), keeping its numbers;
each requirement joins this file with the ticket that delivers it. Outside
this file a requirement is cited as `acceptance/R<n>`, and the docs gate
fails one that no suite under `tests/` names. The kit's own: bootstrap strips
it, so no consumer inherits a spec whose tests it does not have.

R1. The vocabulary checker SHALL accept an `Accept-test:` line whose value is one requirement id in the coverage check's bounded grammar, one space, and a test pin `<path>::<test-name>`. [UC1 2]
R2. IF a test pin is longer than 200 bytes, holds a byte outside printable ASCII or a `|`, has an empty path, a path holding a space, a path starting with `/` or holding a `..` segment, or an empty test name, THEN the vocabulary checker SHALL refuse it, naming the field `accept-test`. [UC1 2a, 2d, 2e]
R3. The vocabulary checker SHALL accept several `Accept-test:` lines for one id, and SHALL read two identical lines as one answer.
R4. The shipped vocabulary policy SHALL declare the field `accept-test` as a keyed field whose value is held to the test-pin grammar the checker owns, with a published line bound of 32, and the checker's built-in defaults SHALL equal it.
R5. WHEN a ticket carries `Accept-test:` lines, the stamp reader SHALL lift and check them with the ticket's other stamp lines and print them as spelled. [UC1 2]
R6. IF a ticket's `Accept-test:` line names an id that is not on its `Covers:` line, THEN the stamp reader SHALL exit 2 naming the field `accept-test`. [UC1 2b]
R7. WHEN the release that ships acceptance/R1 to R6 lands, `UPDATING.md` SHALL tell a consumer whose own vocabulary policy file predates it to add the `accept-test` field and its bound.
R8. WHEN asked to `check <base> <head>`, the acceptance guard SHALL print, sorted, one `changed: <ticket> <requirement-id> <path>` line for each `Accept-test:` path of a held ticket whose content at the head differs from its content at the ticket's approval commit, and SHALL exit 1 when it printed one and 0 when it printed none. [UC3 2, 3]
R9. The acceptance guard SHALL hold only tickets whose front matter at the base carries an approval record and whose stage is not `done`. [UC3 2a, 2b]
R10. A held path that is absent at the head SHALL count as changed WHERE the base holds it; a held path absent at both the base and the head SHALL NOT count as changed. [UC3 3a]
R11. WHERE `POLICY_BASE` names a ref, the acceptance guard SHALL read the guards policy, the factory project manifest and every factory ticket through the policy reader at that ref, and SHALL read neither from the working tree. [UC3 1, 2, 2c]
R12. WHERE `POLICY_BASE` is unset, the acceptance guard SHALL read the guards policy, the factory project manifest and the factory tickets from the working tree.
R13. IF a held ticket's approval commit names no commit in the repository, its approval record lacks `commit`, `by` or `at`, one of its `Accept-test:` lines is refused by the checker, or an approved path is absent at the approval commit, THEN the acceptance guard SHALL print `fail-closed invalid <ticket path>` and exit 3. [UC3 2d; UC2 1c]
R14. IF the policy reader fails closed on the guards policy, the factory project manifest or a factory ticket, THEN the acceptance guard SHALL print that fail-closed line and exit 3, and SHALL NOT pass. [UC3 2e]
R15. WHERE the repository is not a factory project, the acceptance guard SHALL print nothing on standard output and exit 0 for `check`. [UC3 2f]
R16. The acceptance guard SHALL print nothing read from a factory ticket except ticket ids, requirement ids, approval commits, and `Accept-test:` lines the checker accepted.
R17. WHEN asked for `tests <ticket> --base <ref>` on a ticket with an approval record, the acceptance guard SHALL print `approved <commit>` and then the ticket's `Accept-test:` lines as spelled, and exit 0. [UC2 1]
R18. IF a ticket without an approval record was created before the adoption date the factory project manifest names at the base, THEN `tests` SHALL print `no-tests <ticket> created-before-adoption` and exit 0. [UC2 1b]
R19. IF a ticket without an approval record covers no id whose `Test-tier:` is other than `manual`, THEN `tests` SHALL print `no-tests <ticket> no-automated-id` and exit 0.
R20. IF a ticket is owed (not exempt, no approval record, at least one covered id with a `Test-tier:` other than `manual`), THEN `tests` SHALL print `owed <ticket>` and exit 4. [UC2 1a]
R21. IF the factory project manifest at the base names no adoption date, the key absent or written with no value, THEN `tests` SHALL print `no-tests <ticket> no-adoption-date` and exit 0 for a ticket without an approval record, and `check` SHALL still hold every ticket that has one.
R22. IF the factory project manifest's `acceptance_tests_since` at the base is not a valid `YYYY-MM-DD` date, THEN the acceptance guard SHALL print `fail-closed invalid .factory/project.yaml` and exit 3.
R23. The shipped TDD pairing workflow, and the kit's own guards workflow, SHALL run the acceptance guard's `check` on every pull request from its base commit to its head, with `POLICY_BASE` set to the base commit, and fail on a non-zero exit. [UC3 1]
R35. IF a ticket's front matter `created` is missing or not a date, THEN the adoption date SHALL NOT exempt it.
R36. The shipped TDD pairing workflow, and the kit's own guards workflow, SHALL run the acceptance guard's script as it is at the base commit, read from git's objects, and never the copy in the pull request's head. [UC3 1]
R37. WHEN asked for `held --base <ref>`, the acceptance guard SHALL print one line `<ticket> <path>` per file a held ticket's `Accept-test:` lines name, and exit 0.
