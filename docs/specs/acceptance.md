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
