# The check table (step 8)

Opened from `/implement` step 8 when the ticket carries a `Covers:` line that lists requirement ids. `SKILL.md` stays the entry point; this file is the branch. A step's number still points into `SKILL.md`.

**Write the check table into the PR body, above the `<!-- explain-diff-appendix -->` marker** — in the PR template's Check table section, which is where it sits. The table shows, for each requirement the ticket covers, which tier of test checked it, the result and the evidence, so the human who merges reads proof per requirement and not "tests pass". The Axis-2 reviewer reads the body down to the appendix marker, so the table is placed above it and never below it.

Its shape is fixed, byte for byte, because a reader holds it:

1. a `<!-- check-table -->` marker on a line of its own;
2. the exact header on the next line, `| Requirement | Test tier | Result | Evidence |`;
3. a separator row on the line after, `| --- | --- | --- | --- |`;
4. **one row per covered id**, in the order the `Covers:` line lists them, at most 64 rows; the first line after the last row does not open with `|`.

Each row's four cells:

- **Requirement** — the id as the `Covers:` line `scripts/stamp.sh` printed lists it. A row is never written for an id the line does not list.
- **Test tier** — the ticket's `Test-tier:` line for that id, as `scripts/stamp.sh` printed it, where the ticket stamps one; where it stamps none, the tier of the test that checked it: `unit`, `suite`, `e2e` or `manual`.
- **Result** — `pass`, `fail` or `skipped`, read from the full-suite run of step 4 at the commit you push.
- **Evidence** — a `<path>::<test>@<commit>` pin of the test that checked it: the test file's path, the test's name, and the commit the suite ran at, 7 to 40 hex digits (a suite whose assertions name the requirement id takes the id as the test's name, `tests/<suite>.sh::<area>/R<n>@<commit>`); or an `https://` URL of at most 200 characters, such as the CI run that checked it. Path and test name use only letters, digits, `.`, `/`, `_` and `-`; a URL adds `:`, `#`, `?`, `=`, `&` and `%`.

**A `manual` row no human has checked reads `skipped` with the evidence `-`.** The operator checks it; you never mark it `pass` for them. `-` belongs on a `skipped` row and nowhere else.

**Check the table before you push the body**: save the body you will open the PR with, and the ticket body, to files under your worktree's git directory, and run `sh scripts/check-table.sh <body file> <ticket body file>`. It reads both as data and prints only requirement ids, tokens and row numbers. Exit 0 is a complete, passing table. Exit 1 names a `missing-row:`, `extra-row:`, `tier-differs:`, `fail:` or `skipped:` id: fix the table, or the code, until only the `skipped:` lines of `manual` rows remain, and name those in your report as checks awaiting the operator. Exit 2 names the row that breaks the grammar: rewrite that row. Exit 3 means the reader found no table above the appendix marker.

A `Covers:` line that is malformed, or spelled `none (<reason>)`, owes no table: leave the template's section with no rows. A ticket covering more than 64 ids is too big for one session: stop and split it via `/to-tickets` (`SKILL.md`'s token-burn boundary).
