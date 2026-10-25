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
R29. Every `SKILL.md` the kit ships SHALL declare `allowed-tools` in its frontmatter.
R30. The docs gate SHALL fail a `SKILL.md` with no `allowed-tools`.
R31. The docs gate SHALL fail an agent type under the adapter with no `tools:` line.
R32. WHERE a skill names a spawn type, the docs gate SHALL fail it when that type's `tools:` holds a tool absent from the skill's `allowed-tools`.
R33. `/to-prd`'s template SHALL write each scenario as a use case: `UC<n>`, a name, an actor, a goal, a numbered main flow, and extensions numbered from the step they branch from (`2a`).
R34. `/to-prd` SHALL end each requirement a step checks with the steps it checks in brackets, as in `[UC1 3a]`, and MAY leave the brackets off a requirement no step reaches.
R35. `/to-tickets` SHALL read each use case's main flow as a candidate tracer bullet.
R36. A PRD written before this change SHALL keep its walkthrough scenarios, and no check SHALL refuse them.
R37. `/retro`'s question 2 SHALL print the record reader's rows before its existing per-lens triage counts. [UC1 4]
R38. The vocabulary checker SHALL accept a `Risk:` line whose value is `low` alone, or `high` followed by exactly one reason from the policy's risk reasons (`irreversible`, `security`, `invisible`, `shared-layer`, `unclear`, `unlearned`, `outward`), and SHALL refuse any other value, naming the field. [UC1 2]
R39. IF a `Risk:` line names a reason the policy reserves for the risk rule (`unlearned`, `outward`), THEN the vocabulary checker SHALL refuse it unless its caller declares itself the risk rule. [UC1 2a]
R40. The vocabulary checker SHALL accept a `Test-tier:` line whose value is one requirement id in the coverage check's bounded grammar followed by one of `unit`, `suite`, `e2e`, `manual`, SHALL accept one such line per distinct id, and SHALL refuse an id given two different tiers. [UC1 2, 2b]
R41. The shipped vocabulary policy SHALL declare the fields `risk`, `risk-confidence` (`low`, `medium`, `high`), `test-tier`, `result` (`pass`, `fail`, `skipped`) and `scope` (`inside`, `outward`), and the checker's built-in defaults SHALL equal it.
R42. WHEN a ticket carries `Risk:`, `Risk-confidence:` or `Test-tier:` lines, the stamp reader SHALL lift and check them with the ticket's other stamp lines and print them as spelled, and SHALL print no `Risk:` line for a ticket that carries none. [UC1 3, 3a]
R43. IF a ticket carries more than 32 `Test-tier:` lines, or more than 8 lines of any other stamp key, THEN the stamp reader SHALL stop with exit 5 and print nothing. [UC1 3b]
R44. WHEN the release that ships R38 to R43 lands, `UPDATING.md` SHALL tell a consumer whose own vocabulary policy file predates it to add the five new fields, because a policy file that is found is the whole policy.
R45. WHEN `/implement` opens a pull request for a ticket with a `Covers:` line, it SHALL write, above the explain-diff marker and under a `<!-- check-table -->` marker, a table headed `| Requirement | Test tier | Result | Evidence |` with one row per covered id, and the shipped PR template SHALL carry that section. [UC2 1, 3]
R46. Each check-table row SHALL carry the ticket's `Test-tier:` for its id where the ticket stamps one, a result of `pass`, `fail` or `skipped`, and as evidence a `<path>::<test>@<commit>` pin of the test that checked it or an `https://` URL, and a `manual` row no human has checked SHALL read `skipped` with the evidence `-`. [UC2 1, 2]
R47. The check-table reader SHALL read a PR body and a ticket body and print only requirement ids, tokens and row numbers: exit 0 when every covered id has exactly one row, its result `pass` and its tier the ticket's stamp; exit 1 with `missing-row:`, `extra-row:`, `tier-differs:`, `fail:` and `skipped:` lines; exit 2 for a row that breaks the grammar or a table past 64 rows, naming the row number; exit 3 when the body carries no table. [UC3 1, 1a, 1b, 1c]
R48. WHEN `/review-pr` reviews a PR whose ticket has a `Covers:` line, its coordinator SHALL run the check-table reader and hand the output to Agent 7, which SHALL list each id the reader names, and each covered id when the reader exits 2 or 3, as a ❌ MISSING item naming the id and the reader's word. [UC3 1, 2, 1a, 1b, 1c]
R49. WHEN `/pr-iterate` pushes a commit to a PR with a check table, it SHALL rewrite each row's result and evidence pin from that iteration's suite run at the new head. [UC3 3]
R50. WHILE the check-table reader prints a `fail:`, `missing-row:`, `extra-row:` or `tier-differs:` line, `/pr-iterate` SHALL NOT report the PR converged. [UC3 4]
R51. WHEN the check-table reader prints `skipped:` lines, `/pr-iterate` SHALL list those ids at the top of its report as manual checks awaiting the operator. [UC3 4]
