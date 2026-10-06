# Process

The kit's living spec for the **process** area: the chain's skills and the
checks that hold them — what `/to-prd`, `/to-tickets`, `/implement`,
`/review-pr`, the coverage check and the docs gate's living-spec rule do
today. ADR-0012 is the contract; the file's format is the starter a consumer
gets, `templates/docs/specs/README.md`.

Seeded by #556 from PRD #527's Requirements, keeping its numbers, each line
restated as what landed. Outside this file a requirement is cited as
`process/R<n>`, and the docs gate fails one that no suite under `tests/`
names. The kit's own: bootstrap strips it, so no consumer inherits a spec
whose tests it does not have.

R1. The `/to-prd` template SHALL carry a Requirements section between Scenarios and Implementation Decisions, each line one observable behavior a test can fail, in EARS-lite, with an id `R<n>` numbered from 1 within the PRD and never renumbered once published.
R2. The `/to-prd` template SHALL ask for one user story per distinct actor goal, kept as the *why* that every requirement serves, and SHALL NOT ask for an exhaustive story list.
R3. WHEN `/to-prd` runs in a conversation that holds no `/grill-me` or `/grill-with-docs` run, it SHALL ask one question, whether to run `/grill-me` first, naming `/grill-with-docs` instead where a glossary and decision records exist, and SHALL decide this from the conversation only, never the trace.
R4. IF the human declines the grilling, or the run has nobody to answer because it was spawned or is unattended, THEN `/to-prd` SHALL write the PRD without asking and list under Open Issues each point it would otherwise have guessed.
R5. WHERE the PRD carries requirement lines, `/to-tickets` SHALL stamp each ticket with one bare `Covers:` line of the ids it delivers, `R<n>` or `<area>/R<n>`, except a prefactor, an open-issue or a release ticket, which SHALL say so as `Covers: none (prefactor)`, `Covers: none (open-issue)` or `Covers: none (release)`, and the coverage check SHALL refuse any other `Covers:` line, naming the ticket and never the line.
R6. WHEN `/to-tickets` reaches the quiz, it SHALL run the coverage check, `scripts/coverage.sh`, on the screened PRD body and the drafted tickets, which SHALL name every requirement no ticket covers as `uncovered: <id>` and every non-exempt ticket that covers nothing as `orphan: <label>`, and the quiz SHALL show both lists.
R7. The coverage check SHALL read only the PRD's requirement lines and each ticket's bare `Covers:` line, with every id bounded to an area of at most 32 characters and a number of at most 6 digits, and SHALL print only ids and ticket labels, never a line of either file.
R8. WHEN a ticket carries a well-formed `Covers:` line, `/implement`'s restatement SHALL name those ids and its first red tests SHALL be those requirements, and a malformed line SHALL be reported as malformed with no id read from it.
R9. WHERE the spec carries requirement ids, Axis 2 of `/review-pr` SHALL cite the id on a SPECIFIED item's own line and SHALL list each id on the ticket's `Covers:` line that the diff does not deliver as a MISSING item on the confirm-list.
R10. WHERE a living spec exists for the PRD's area, `/to-prd` SHALL write the requirements as `### ADDED`, `### MODIFIED` and `### REMOVED` deltas against it, each line spelled with its area-qualified id `<area>/R<n>.`, and the coverage check SHALL read every delta line as a requirement.
R11. WHEN a ticket covers a requirement of an area, `/implement` SHALL apply it to `docs/specs/<area>.md` in the same diff as the test that names `<area>/R<n>`, a REMOVED requirement leaving the tombstone `~~R<n>.~~ Removed by #<PRD>: <why>` so its id is never reused, and the first ticket covering a plain `R<n>` of a PRD whose `Area:` line holds a bounded area token SHALL create that file, keeping the PRD's numbers.
R12. IF a requirement in `docs/specs/*.md` is named, as `<area>/R<n>`, by no file the docs gate's `livingSpec.testGlobs` match, THEN the docs gate SHALL fail in both its engines, naming the file and the id.
R13. WHILE no living spec exists, no `docs/specs/` directory or no file in it with a requirement line, the gate's living-spec check SHALL pass.
R14. Bootstrap SHALL give a consumer the coverage check, the gate's living-spec check in both engines and the `docs/specs/README.md` starter, and SHALL give it no living spec of the kit's.
