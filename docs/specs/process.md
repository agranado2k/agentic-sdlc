# Process

The kit's living spec for the **process** area: the chain's skills and the
checks that hold them — what `/to-prd`, `/to-tickets`, `/implement`,
`/review-pr`, `/pr-iterate`, the coverage check and the docs gate's living-spec rule do
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
R15. WHERE every lens slice is empty, `/review-pr` SHALL run the single-reviewer pass over the whole diff, and SHALL NOT record a verdict before that pass returns.
R16. IF no Axis-1 lens returned a report and no single-reviewer pass returned, THEN `/review-pr` SHALL record `review.verdict outcome=blocked data.lenses=0` with the reason `no lens ran`, and its Verdict line SHALL say that no lens ran.
R17. WHEN `/pr-iterate`'s review records a verdict blocked because no lens ran, `/pr-iterate` SHALL NOT report the PR as converged, and SHALL escalate it at the top of its report.
R18. WHEN `/pr-iterate` sees a failure with the same signature on 3 consecutive iterations, it SHALL push no further fix, and SHALL escalate naming the check, the count and the quoted error line.
R19. WHEN a failure's signature differs from the previous iteration's, `/pr-iterate` SHALL restart that count.
R20. WHEN `/implement`'s full-suite run fails with the same signature 3 consecutive times, it SHALL stop editing and report the test, the assertion and each attempt, without pushing.
R21. WHEN either skill stops under R18 or R20, it SHALL record the stop in the trace with `data.stop=repeated-failure` and the signature's check or test name, never the log text.
R22. `/retro` SHALL report, per landed ticket in the window, the lead time from its first `ticket.start` to its `merge.land`, with the window's median and longest.
R23. `/retro` SHALL report, per landed PR, the review wait from its last `pr.iterate outcome=green` to its `merge.land`, and SHALL report `n/a` for a PR with no green iteration.
R24. `/retro` SHALL report toil's share of landed tickets from `ticket.start`'s `data.class=toil`, and `not recorded` when no ticket in the window carries a class.
R25. WHEN a landed ticket carries a `Targets:` line, `/retro` SHALL report that query's count per landed PR in the window before its landing and in an equal window after.
R26. IF the two windows of R25 differ in tier → model mapping or in kit version, THEN `/retro` SHALL report the comparison as inconclusive, and SHALL leave failed runs out of both counts.
R27. IF R25's after-rate is not below its before-rate, THEN `/retro` SHALL file a finding naming the ticket.
R28. A lens or skill edit that `/retro` proposes SHALL cite the trace events behind it by run id and carry its `Targets:` line, and SHALL NOT be filed without them.
R30. The docs gate SHALL fail a `SKILL.md` with no `allowed-tools`.
R31. The docs gate SHALL fail an agent type under the adapter with no `tools:` line.
R32. WHERE a skill names a spawn type, the docs gate SHALL fail it when that type's `tools:` holds a tool absent from the skill's `allowed-tools`.
R33. `/to-prd`'s template SHALL write each scenario as a use case: `UC<n>`, a name, an actor, a goal, a numbered main flow, and extensions numbered from the step they branch from (`2a`).
R34. `/to-prd` SHALL end each requirement a step checks with the steps it checks in brackets, as in `[UC1 3a]`, and MAY leave the brackets off a requirement no step reaches.
R35. `/to-tickets` SHALL read each use case's main flow as a candidate tracer bullet.
R36. A PRD written before this change SHALL keep its walkthrough scenarios, and no check SHALL refuse them.
