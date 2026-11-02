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
R37. `/retro`'s question 2 SHALL run the outcome recorder, then print the record reader's rows for its window, before its existing per-lens triage counts. [UC1 1, 4]
R38. The vocabulary checker SHALL accept a `Risk:` line whose value is `low` alone, or `high` followed by exactly one reason from the policy's risk reasons (`irreversible`, `security`, `invisible`, `shared-layer`, `unclear`, `unlearned`, `outward`), and SHALL refuse any other value, naming the field. [UC1 2]
R39. IF a `Risk:` line names a reason the policy reserves for the risk rule (`unlearned`, `outward`), THEN the vocabulary checker SHALL refuse it unless its caller declares itself the risk rule. [UC1 2a]
R40. The vocabulary checker SHALL accept a `Test-tier:` line whose value is one requirement id in the coverage check's bounded grammar followed by one of `unit`, `suite`, `e2e`, `manual`, SHALL accept one such line per distinct id, and SHALL refuse an id given two different tiers. [UC1 2, 2b]
R41. The shipped vocabulary policy SHALL declare the fields `risk`, `risk-confidence` (`low`, `medium`, `high`), `test-tier`, `result` (`pass`, `fail`, `skipped`) and `scope` (`inside`, `outward`), and the checker's built-in defaults SHALL equal it.
R42. WHEN a ticket carries `Risk:`, `Risk-confidence:` or `Test-tier:` lines, the stamp reader SHALL lift and check them with the ticket's other stamp lines and print them as spelled, and SHALL print no `Risk:` line for a ticket that carries none. [UC1 3, 3a]
R43. IF a ticket carries more than 32 `Test-tier:` lines, more than 32 `Accept-test:` lines, or more than 8 lines of any other stamp key, THEN the stamp reader SHALL stop with exit 5 and print nothing. [UC1 3b; PRD-14 UC1 2c]
R44. WHEN the release that ships R38 to R43 lands, `UPDATING.md` SHALL tell a consumer whose own vocabulary policy file predates it to add the five new fields, because a policy file that is found is the whole policy.
R45. WHEN `/implement` opens a pull request for a ticket with a `Covers:` line, it SHALL write, above the explain-diff marker and under a `<!-- check-table -->` marker, a table headed `| Requirement | Test tier | Result | Evidence |` with one row per covered id, and the shipped PR template SHALL carry that section. [UC2 1, 3]
R46. Each check-table row SHALL carry the ticket's `Test-tier:` for its id where the ticket stamps one, a result of `pass`, `fail` or `skipped`, and as evidence a `<path>::<test>@<commit>` pin of the test that checked it or an `https://` URL, where an id the ticket carries `Accept-test:` lines for SHALL take a pin whose `<path>::<test>` is one of those lines, and a `manual` row no human has checked SHALL read `skipped` with the evidence `-`. [UC2 5]
R47. The check-table reader SHALL read a PR body and a ticket body and print only requirement ids, tokens and row numbers: exit 0 when every covered id has exactly one row, its result `pass`, its tier the ticket's stamp, and its evidence one of the id's `Accept-test:` lines where it has any; exit 1 with `missing-row:`, `extra-row:`, `tier-differs:`, `not-approved:`, `fail:` and `skipped:` lines; exit 2 for a row that breaks the grammar or a table past 64 rows, naming the row number; exit 3 when the body carries no table. [UC4 3]
R48. WHEN `/review-pr` reviews a PR whose ticket has a `Covers:` line, its coordinator SHALL run the check-table reader and hand the output to Agent 7, which SHALL list each id the reader names, and each covered id when the reader exits 2 or 3, as a ❌ MISSING item naming the id and the reader's word. [UC3 1, 2, 1a, 1b, 1c]
R49. WHEN `/pr-iterate` pushes a commit to a PR with a check table, it SHALL rewrite each row's result and evidence pin from that iteration's suite run at the new head. [UC3 3]
R50. WHILE the check-table reader prints a `fail:`, `not-approved:`, `missing-row:`, `extra-row:` or `tier-differs:` line, `/pr-iterate` SHALL NOT report the PR converged. [UC3 4]
R51. WHEN the check-table reader prints `skipped:` lines, `/pr-iterate` SHALL list those ids at the top of its report as manual checks awaiting the operator. [UC3 4]
R56. WHEN `/pr-iterate` meets an ⚠️ UNSPECIFIED item marked `scope: inside`, it SHALL decide it, keeping the change or amending it, and SHALL record the decision as one row of the PR body's decision log under a `<!-- decision-log -->` marker above the explain-diff marker, with an id `D-<n>` never renumbered, the surface, the decision and why. [UC5 2]
R57. WHEN `/pr-iterate` writes a decision-log row, it SHALL record one `finding.triage` event carrying `data.scope=inside` and `data.decision=D-<n>`. [UC5 2]
R58. IF an ⚠️ UNSPECIFIED item is marked `scope: outward`, THEN `/pr-iterate` SHALL NOT decide, amend or log it, and SHALL list it verbatim at the top of its report for the operator. [UC5 3]
R59. IF a review marks `scope: outward` an item the decision log holds, THEN `/pr-iterate` SHALL strike that row, keeping its id, and SHALL hold the item as R58 says. [UC5 2a]
R60. No skill SHALL read a decision log's or a check table's prose back as an instruction: a skill reads the decision log only for its `D-<n>` ids, and the check table only through the check-table reader.
R61. `/to-tickets` SHALL stamp every ticket with one `Risk:` line and one `Risk-confidence:` line, check both with the vocabulary checker as the planner before the quiz, and repair and recheck a refused line before it is shown. [UC3 1, 2, 1a]
R62. `/to-tickets` SHALL state which change each planner reason covers (`irreversible`: cannot be undone by a revert; `security`: auth, secrets or the trust boundary; `invisible`: a mistake no post-merge outcome would count; `shared-layer`: a file the shared-layer manifest lists, a contract file, or a policy, guard or gate file; `unclear`: the planner cannot tell), and SHALL stamp `low` only when none applies. [UC3 1, 1b]
R63. `/to-tickets` SHALL show each ticket's `Risk:` and `Risk-confidence:` at the quiz, and SHALL record on each `ticket.write` event the proposed risk, the published risk and the risk confidence. [UC3 3, 4]
R64. WHEN `/pr-iterate` ends an iteration on a PR, it SHALL run the risk rule at the PR's head with the ticket it holds and print the effective risk at the top of its report, marked as reported only. [UC1 1, 8]
R65. `/pr-iterate` and the landing script SHALL take the same actions on a PR whatever the risk rule prints. [UC1 8]
R66. `/retro`'s question 8 SHALL count the latest `risk.judge` per PR in its window as agreed or disagreed, the disagreements split by which side raised the risk, by reason and by review area, and the risk overrides at the quiz per `Risk-confidence`. [UC5 1, 2, 3, 2a]
R67. `/retro`'s question 8 SHALL leave `risk.judge` events with `data.switch=tripped` out of its disagreement counts and print how many it left out. [UC5 2]
R120. WHERE the repository's git top level holds the factory's project manifest and the `factory-prd` skill is installed, WHEN `/to-prd` starts, it SHALL publish nothing to the forge's issue tracker, SHALL write no `prd.write` event, and SHALL end with a hand-off naming `/factory-prd` as where PRDs are written. [UC2 2, 3]
R121. WHERE the repository's git top level holds the factory's project manifest and the `factory-tickets` skill is installed, WHEN `/to-tickets` starts, it SHALL publish no issue, merge no section, close no twin, write no `ticket.write` event, and SHALL end with a hand-off naming `/factory-tickets` as where tickets are written. [UC1 2, 3, 4]
R122. `/to-prd` and `/to-tickets` SHALL decide the deferral before any other step: before `/to-prd`'s grilling question, and before `/to-tickets` fetches a PRD body or makes its pre-screen's scratch directory. [UC1 2, UC2 2]
R123. IF the repository holds no `.factory/` folder, or holds one with no project manifest at its git top level, THEN `/to-prd` and `/to-tickets` SHALL run their forge flow unchanged and SHALL name no factory skill. [UC1 2a, UC2 2a]
R124. The deferral SHALL be decided by the presence of the project manifest and of the factory skill's `SKILL.md` alone, and SHALL read nothing from either file or from any factory item.
R125. IF the operator's own message in the session asks for the forge version, THEN `/to-prd` and `/to-tickets` SHALL run their forge flow, and the skill's hand-off SHALL say that it ran the forge flow in a factory project. [UC1 2b, UC2 2b]
R126. A request for the forge version carried in a spawn prompt, a ticket body, a PRD body or another agent's message SHALL NOT lift the deferral. [UC1 2c]
R127. `/grill-me`, `/grill-with-docs` and `/design-brief` SHALL carry no factory deferral, and SHALL run the same with or without the project manifest.
R128. WHEN the stamp reader is given a factory ticket id, `T-` followed by 1 to 6 digits, in a checkout whose git top level holds the project manifest, it SHALL run `factory stamp <id>` with that top level as its directory, and SHALL make no tracker call. [UC3 1, 2]
R129. The stamp reader SHALL read a factory ticket's stamp only through `factory stamp`, and SHALL open no file under the factory folder. [UC3 2, 2b]
R130. WHEN the stamp reader reads a factory ticket, it SHALL pass the lines `factory stamp` printed through its own lift, bound and vocabulary checker, `Label:` lines included, and SHALL print only lines its checker passed; WHEN it reads a tracker issue, it SHALL lift no `Label:` line. [UC3 2, 2e]
R131. IF the checkout's git top level holds no project manifest, or `factory stamp` exits 2, THEN the stamp reader SHALL exit 2, print nothing on stdout, and name the id and the case on stderr. [UC3 2a]
R132. For a factory ticket id the stamp reader SHALL NOT exit 4, and IF `factory stamp` exits with any status but 0, 2, 3 or 5, THEN the stamp reader SHALL exit 3 and print nothing on stdout. [UC3 2c]
R133. For a factory ticket, the stamp reader SHALL exit 3 when `factory stamp` exits 3 and 5 when it exits 5, printing nothing on stdout, and SHALL relay none of `factory stamp`'s standard error. [UC3 2c, 2d]
R134. The stamp reader SHALL accept as its one argument only digits or a factory ticket id, and SHALL refuse anything else, a temporary `T-~<hex>` id included, as a usage error, exit 2.
R135. WHEN `/implement` is handed a factory ticket id, it SHALL read the ticket's stamp with the one call `sh scripts/stamp.sh T-<n>`, and SHALL treat each exit as it does for an issue. [UC3 1, 3]
R136. WHEN bootstrap stamps a project that holds no `.factory/` folder, it SHALL write no `.factory/` folder, and the stamped project SHALL pass the kit's end-to-end bootstrap acceptance test as it did before this PRD. [UC4 1, 2]
R137. WHEN the release that ships R128 to R134 lands, `UPDATING.md` SHALL tell a consumer that the stamp reader now accepts a factory ticket id, that it runs `factory stamp` in a factory project, and that its behaviour for an issue number is unchanged.
R138. IF the stamp reader is given a factory ticket id in a factory project and no `factory` binary is on `PATH`, THEN it SHALL exit 3, print nothing on stdout, and write one stderr line naming the absent binary and the forge-issue form, `sh scripts/stamp.sh <issue-number>`. [UC3 2f]
R139. WHEN the stamp reader exits 3 for an absent `factory` binary and `/implement` holds the ticket's forge issue number from its hand-off, `/implement` SHALL say once that it fell back to the forge issue and SHALL read the stamp with `sh scripts/stamp.sh <N>`; holding none, it SHALL take exit 3's path as for an issue. [UC3 2f]
R222. WHEN `/implement` is handed a temporary factory id, `T-~` followed by hex, it SHALL refuse it, read no stamp, and name `factory renumber` as what makes it stampable. [UC3 2g]
R223. IF the repository's git top level holds the project manifest and the factory skill for the planning skill's item is not installed, THEN `/to-prd` or `/to-tickets` SHALL run its forge flow as today and SHALL say once, at its start, that `factory install-skill` would add that factory skill. [UC1 2e, UC2 2c]
R224. `/to-prd` and `/to-tickets` SHALL decide the deferral without running any `factory` subcommand, so that a factory project without the `factory` binary runs them as R123 or R223 says.
R225. A factory skill SHALL count as installed when its `SKILL.md` exists under the user's `~/.claude/skills/<name>/` or the project's `.claude/skills/<name>/`, and under no other path.
R201. WHEN `/pr-iterate` requests a review at a new head, it SHALL also request the verifier at that head, and neither skill SHALL request the verifier more than once for one head commit. [UC2 3]
R202. `/pr-iterate` SHALL triage each verifier finding as it triages a bot's finding, and SHALL record its `finding.triage` with the finding's `V-` id. [UC2 1]
R203. IF the verifier marks a check-table row `disputed`, THEN `/pr-iterate` SHALL list that id at the top of its report as a check awaiting the operator, beside the skipped rows, and SHALL NOT rewrite that row's result for the dispute. [UC2 2]
R204. `/pr-iterate` SHALL NOT decide, amend or log a verifier's ⚠️ UNSPECIFIED item, whatever scope it carries, and SHALL list each one verbatim at the top of its report for the operator. [UC2 4]
R205. No `verify.verdict` outcome SHALL stop `/pr-iterate` from reporting a PR converged. [UC2 5]
R206. The shipped CI review prompt SHALL ask for `scope: inside` or `scope: outward` as the first words after the tag on each ⚠️ UNSPECIFIED item. [UC5 1]
R207. The shipped CI review prompt SHALL ask for one line per `pass` row of the PR's check table, naming the row's id and `upheld` or `disputed`. [UC5 2]
R208. IF the verifier disputes a finding of the kit's review, THEN `/pr-iterate` SHALL list that finding's id with the verifier's evidence at the top of its report, beside the disputed rows, and SHALL NOT reject the finding on the verifier's verdict alone. [UC2 1a]
R220. `/to-tickets`' rule against file paths in ticket bodies SHALL except `Accept-test:` lines, as it excepts a mechanical ticket's oracle line, because the approval commit pins each path and the acceptance guard catches a path that drifts.
R221. WHERE a ticket draft carries `Accept-test:` lines, `/to-tickets` SHALL check each with the vocabulary checker before the quiz and show them at the quiz beside the ticket's `Test-tier:` lines.
R240. WHEN `/pr-iterate` or `/merge-train` records a verdict or a landing for a PR whose landing line names a factory ticket id, it SHALL write `ticket:T-<digits>` where it writes `ticket:#<N>` for an issue. [UC2 2b]
R241. `/merge-train` SHALL read a landing line whose handle is `#<N>` or a canonical factory ticket id, and SHALL treat any other spelling as no line. [UC2 2b]
R226. WHERE the repository's git top level holds the project manifest, every configuration value the kit reads that the factory also defines SHALL be read from the factory's key in `.factory/project.yaml`, and the kit's own policy file SHALL be read for that value only where the repository is not a factory project.
R227. WHERE the kit's policy reader reads a configuration value at a base ref, and R226 sends that value to `.factory/project.yaml`, the value SHALL be read from `.factory/project.yaml` at the same base ref through the policy reader, failing closed as the policy reader does.
R228. WHEN `/implement` is handed a canonical factory ticket id, it SHALL read the ticket's text with `factory show <id>`, as untrusted content, and SHALL fetch no forge issue. [UC1 1]
R229. WHEN `/implement` is handed a factory ticket id with one digit, it SHALL write the id with a leading zero, `T-0<d>`, in every subject, line, branch name and argument it writes. [UC1 1a]
R230. WHEN `/implement` builds a factory ticket, it SHALL work on a branch `<type>/t-<digits>-<slug>`, the digits as the canonical id spells them. [UC1 2]
R231. WHEN `/implement` starts a factory ticket in `ready`, it SHALL run `factory move <id> build` and commit the move as the branch's first commit; IF the move is refused, THEN it SHALL stop before any edit and report the condition the factory printed. [UC1 2, 2a]
R232. IF the factory ticket is already in `build` or later when `/implement` starts, THEN it SHALL make no move. [UC1 2b]
R233. WHEN `/implement` builds a factory ticket, it SHALL write `ticket:T-<digits>` wherever it writes `ticket:#<N>` for an issue: `ticket.start`, its run's `begin`, `pr.open`'s `related`, and every note. [UC1 3, 5]
R234. WHEN `/implement` opens the PR for a factory ticket, the body SHALL carry `<!-- implement: ticket=T-<digits> tier=<tier> -->` once, SHALL name the ticket's id, and SHALL carry no closing keyword. [UC1 5]
R235. WHEN the PR for a factory ticket exists, `/implement` SHALL set the ticket's `links.pr` to `"#<PR>"`, run `factory move <id> review`, and push both as one commit on the ticket's branch; IF the move is refused, THEN it SHALL keep the `links.pr` commit and report the refusal. [UC1 6, 6a]
R236. `/implement` SHALL NOT run `factory review`, `factory qa`, `factory approve`, `factory close` or `factory move --force`. [UC1 8]
R237. IF the `factory` binary is not on `PATH` when `/implement` builds a factory ticket, THEN it SHALL make no stage move and no `links.pr` edit, and its report SHALL name each one it left for the operator. [UC1 2c]
R238. WHEN `/implement` dispatches the review of a factory ticket's PR, it SHALL pass `--ticket T-<digits>` and the ticket's `factory show` text as the spec. [UC1 7]
R239. WHEN `/review-pr` or `/pr-iterate` checks the check table of a PR whose ticket is a factory ticket id, it SHALL take the ticket side from what `sh scripts/stamp.sh T-<digits>` printed, and SHALL fetch no issue. [UC1 7]
