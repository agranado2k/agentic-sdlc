# Runtime

The kit's living spec for the **runtime** area: what the kit's machinery does
while work runs — the trace's run identity and its open-run registry, the
worker Budget a dispatched worker and a suite both run under, and the test
harness's one assertion family. ADR-0012 is the contract; the file's format
is the starter a consumer gets, `templates/docs/specs/README.md`.

Seeded by #765 from PRD #742's Requirements, keeping its numbers, each line
restated as what #743–#752 landed. Two lines carry a ruling made on the
wave's PRs: R13 reads a stack run's state from its run stack and a detached
run's from its process (ADR-0026 clause 4), and R26 reads "define an
assertion function" as defining a function that carries an assertion name
of the test harness's. R25 is restated after R27's contract, which retired
the merged family it also named. Outside this file a requirement is cited as
`runtime/R<n>`, and the docs gate fails one that no suite under `tests/`
names. The kit's own: bootstrap strips it, so no consumer inherits a spec
whose tests it does not have.

R31 and R43 to R45 joined from PRD-06 slice 1 (#875, ADR-0036), keeping the
PRD's numbers. R32, R33 and R39 to R42 joined with the outcome recorder
(#876), which restated R43 to name the recorder beside the record reader, as
the PRD writes it. R46 to R51 joined with the misses and lens precision
(#877). R37 and R38 joined with the failed factory QA
(#879). R229 to R236 joined from PRD-15 slice 1 (#963, ADR-0040), keeping
the PRD's numbers past PRD-08 to PRD-13's drafts. R241 to R245 joined from
PRD-15 slice 4 (#966), the landing script's factory ticket. R52 to R58,
R61 to R64, R68 and R69 joined from PRD-09 slice 1 (#905, ADR-0045), the
risk rule, keeping the PRD's numbers; R59 and R60 joined with its second
slice (#906), the review at the head; R65 to R67 with its third (#907),
the kill switch.
The verifier's dispatch and its broker joined as R206, R208 to R211 and
R227, from PRD-13 slice 1 (#941, ADR-0044).
R80, R81, R83, R88 to R91 and R102 joined from PRD-10 slice 2 (#914,
ADR-0047), keeping the PRD's numbers: the landing script's lane mode.
R82, R84 to R87 and R104 joined from PRD-10 slice 3 (#915), keeping the
PRD's numbers: the lane's remaining holds. R82 leaves out `escape` until the
slice that adds that hold restates it, as the PRD writes it; the slice
restated R215 to name R104 as its one exception, as PRD-10 writes it.
R103 joined from PRD-10 slice 4 (#919), keeping the PRD's number: the root
guard keeps the trip marker from an agent.
R149 joined from PRD-11's T-66 (#929), keeping the PRD's number: the root
guard keeps the ruling recorder's `by` from an agent.
R150 to R153 joined from PRD-11 slice 4 (#930), keeping the PRD's numbers:
the ruling defaults, read at the base and applied by the ruling recorder.
R95, R96 and R101 joined from PRD-10's escape cases (#918), keeping the
PRD's numbers: an escape already undone only notifies, a conflicting revert
files a fix ticket, and `--escapes` sweeps with no PR.
R100 joined from PRD-10 slice 4's notice (#920), keeping the PRD's number:
a base-branch workflow failing after a lane landing sends one notice.
The earned record's verifier rows joined as R214 to R216, R223 and R228,
from PRD-13 slice 4 (#945), which restated R46 and R48 to count the kit's
own review apart from the verifier.

R1. WHEN the dispatcher dispatches a worker, the worker's run id SHALL have the shape the trace mints.
R2. WHEN the skill dispatcher runs inside a dispatched worker, the staged prompt SHALL open with a `Trace-Run:` line naming the worker's run and a `Trace-Spawn:` line.
R3. WHEN `trace.sh current` runs, the trace SHALL print `<run> [<parent>]`, the run and parent an emit from the same process would stamp, the environment taking precedence over this session's stack in this checkout.
R4. IF no run is open, `TRACE_RUN` is set to the empty string, or the trace is unconfigured, THEN `trace.sh current` SHALL print nothing and exit 0.
R5. WHEN `trace.sh id` runs, the trace SHALL print a fresh run id and write nothing.
R6. WHEN `trace.sh id --check <id>` runs, the trace SHALL exit 0 for every id `begin`, `begin --detached` and `id` print, and 1 for any other string.
R7. WHEN `begin` opens a run, the trace SHALL add an open-run registry entry for it naming its parent, session, checkout, how it was opened (`stack`), process id, host and start time.
R8. WHEN `begin --detached` runs, the trace SHALL mint a run id, add a registry entry for it opened `detached`, print the id, and change no run stack.
R9. IF the trace is unconfigured, THEN `begin --detached` SHALL print a well-formed run id and write nothing.
R10. WHEN `end <run>` closes a run, the trace SHALL remove that run's registry entry.
R11. WHEN `trace.sh runs` runs, the trace SHALL print one line per registry entry; WHEN `trace.sh runs <id>` runs, it SHALL print that entry's fields.
R12. IF `trace.sh runs <id>` names no entry, THEN the trace SHALL exit 1 and print nothing.
R13. IF a registry entry's run is gone — a stack run's id on no run stack of its session, a detached run's process no longer running on this host — THEN `trace.sh runs` SHALL report it as `stale` and SHALL NOT remove it.
R14. WHEN two processes register runs concurrently, the registry SHALL hold both entries.
R15. The dispatcher, the skill dispatcher (its cascade included) and the Claude Code adapter's hooks SHALL obtain the current run, new run ids and run-id checks only through the trace's `current`, `begin --detached` and `id --check`; no other file SHALL parse an event's JSON for its run or hold a copy of the run-id shape.
R16. The Budget library SHALL provide `budget_derive`, which prints a `key=value` record (`mode`, `tasks`, `memory_mib`, `tasks_from`, `memory_from`, `rung`) and sets no variable its caller reads.
R17. IF the Budget policy is invalid, THEN `budget_derive` SHALL return 2 with a message on standard error and SHALL NOT exit its caller's shell.
R18. WHEN `budget_run <record> <verdict-file> -- <cmd>` runs, the library SHALL run the command under the record's rung and return the command's exit status; `budget_verdict <verdict-file>` SHALL print the ceiling hit (`tasks` or `memory`) or nothing.
R19. The dispatcher's printed budget lines, its exit statuses 71 and 124, and the test harness's suite budget marker SHALL be byte-identical to their form before the extraction.
R20. The test harness SHALL confine a suite through the Budget library's `budget_run`, and SHALL hold no enforcement ladder of its own.
R21. No file outside the Budget library SHALL name a function private to it.
R22. WHEN `t_exec <cmd>` runs, the test harness SHALL capture the command's standard output, standard error and exit status separately into `T_OUT`, `T_ERR` and `T_STATUS`.
R23. WHEN any `expect_*` assertion does not hold, the test harness SHALL print a FAIL line, count one failure, and dump standard output lines prefixed `>` and standard error lines prefixed `|`.
R24. WHEN `expect_said` or `expect_unsaid` runs, the test harness SHALL match the needle against either stream.
R25. Every `expect_*` assertion SHALL be driven red by a suite.
R26. No file under `tests/` other than the test harness SHALL define a function that carries the name of one of the test harness's assertions.
R27. No file under `tests/` SHALL define or call `t_run`, `t_run_split`, the `assert_status` / `assert_out_*` family, the `s_assert_*` family, `LAST_OUT` or `S_OUT`, and a suite SHALL fail when one does.
R28. WHEN `trace.sh begin` opens a run, its `run.start` SHALL carry `data.kit`, read from `VERSION`.
R29. WHEN the harness exposes the session's model or its own name, `run.start` SHALL carry `model` and `harness`, and SHALL leave out a value the harness does not expose, never guessing it.
R30. WHEN a spawn is recorded, its `spawn` event SHALL carry `data.tools`, the tool list of the agent type it spawned as.
R31. The trace SHALL accept the kind `merge.outcome` with the outcomes `reverted`, `fixed` and `qa-failed`, and SHALL refuse any other outcome on it, exit 2, writing nothing. [UC1 3]
R32. WHEN the outcome recorder runs, it SHALL write one `merge.outcome outcome=reverted` against each landed PR that introduced a line a later landing of Conventional Commit type `revert` removed, as git blame at that landing's first parent attributes the line, with the reverting PR in `related` and its merge commit in `data.by_sha`. [UC1 2, 3]
R33. IF a `revert` landing removes no line, THEN the recorder SHALL take the reverted commit only from a 40-hex sha in the landing's merge commit message that lies on the base branch's first-parent history and that a `merge.land` names, and SHALL write nothing when none does. [UC1 2a]
R34. WHEN the outcome recorder runs, it SHALL write one `merge.outcome outcome=fixed` against each landed PR that introduced a line a landing of type `fix` removed or rewrote within the fix window after the PR landed, with `data.days` the days between the two landings. [UC2 1, 2]
R35. IF a `fix` landing touches a line of a PR that landed before the fix window, THEN the recorder SHALL write no outcome against that PR. [UC2 3]
R36. The fix window SHALL be 30 days unless the trace's policy file sets another whole number of days.
R37. WHERE the repository holds a `.factory/` folder, WHEN the recorder runs, it SHALL write one `merge.outcome outcome=qa-failed` against the PR a ticket's `links.pr` names when that ticket's `qa.outcome` is `fail`, with the ticket's id in `data.ticket`. [UC3 1, 2]
R38. IF a factory ticket's `links.pr` is not `#<digits>`, or names a PR with no `merge.land`, THEN the recorder SHALL write nothing for that ticket and print its id on standard error. [UC3 2a]
R39. The recorder SHALL map a landed commit to its PR only through a `merge.land` event's `data.merge_sha`, and SHALL read from commit messages and factory items nothing but the Conventional Commit type token, a 40-hex sha, `qa.outcome` and `links.pr`, each held to its shape, so that a PR number written in prose produces no outcome. [UC2 1a]
R40. A landing whose Conventional Commit type is neither `fix` nor `revert` SHALL produce no outcome. [UC2 1b]
R41. The recorder SHALL write no outcome the trace already holds for the same PR, outcome and evidence (`data.by_sha`, or `data.ticket` for `qa-failed`), so that a second run over the same history writes nothing. [UC1 5]
R42. IF a blamed line resolves to a landing that no `merge.land` with a merge sha names, THEN the recorder SHALL write no outcome for that line and SHALL print the count of such lines on standard error. [UC1 2b]
R43. IF the trace is unconfigured, THEN the recorder and the record reader SHALL write nothing, print nothing on standard output, and exit 0. [UC1 2c]
R44. WHEN the record reader runs, it SHALL print one row per review area of the lens-slice policy, holding the area's landed PRs counted (its most recent 20, or fewer, said as `<n> of 20`), how many of them landed inside the fix window, and how many carry a mistake. [UC1 4, UC4 1, 2, 1a]
R45. The record reader SHALL count a landed PR toward every review area that one of the paths its merge commit changed against its first parent belongs to. [UC1 4]
R46. The record reader SHALL count a mistake as missed unless a finding raised on that PR by the kit's own review (any `data.agent` but `verifier`), not upheld at triage, names a file in the outcome's `data.files`, and SHALL always count a `qa-failed` mistake as missed. [UC4 1]
R47. The record reader SHALL print, per review area, the PRs with a missed mistake and the miss rate over the PRs counted. [UC4 3]
R48. The record reader SHALL count a finding of the kit's own review (any `data.agent` but `verifier`) toward every review area its `data.where` path belongs to, as held up when its triage is `accepted` or a mistake against its PR names its file, as not held up when it was rejected at triage or dismissed by a human with no such mistake, and as unlabelled otherwise; it SHALL count a verifier finding by the same labels in the area's verifier row only. [UC4 1, 2]
R49. The record reader SHALL print, per review area, the findings held up, not held up and unlabelled, the precision (held up over labelled), and the count of labels from triage, from a human dismissal and from a post-merge outcome. [UC4 4]
R50. IF a ratio's denominator is zero, THEN the record reader SHALL print `n/a` for it. [UC4 4a]
R51. The record reader SHALL compare no number to a threshold, SHALL print no risk word, and SHALL write nothing to the trace or to any file. [UC4 5]
R52. The trace SHALL accept the kind `risk.judge` with the outcomes `agreed` and `disagreed`, and SHALL refuse any other outcome on it, exit 2, writing nothing. [UC1 7]
R53. WHEN the risk rule runs with a base, a head and a PR number, it SHALL print on standard output, in this order and nothing else, `effective: <risk>`, `planner: <risk>`, `rule: <risk>`, one `area: <review area> earned|unlearned` line per review area the diff touches, and `switch: on|tripped`, and exit 0. [UC1 6]
R54. The risk rule SHALL read the planner's risk only from a ticket's `Risk:` line, lifted by the stamp reader from a ticket number or a ticket body file, and SHALL read it as `high unclear` when no ticket is given, the ticket carries no `Risk:` line, or the stamp reader refuses it. [UC1 2, 1a, 2a]
R55. The risk rule SHALL judge a review area earned only when its earned record, read over the area's most recent settled landings (those that landed before the fix window began), shows the full window of 20 settled landings, a missed-mistake rate below the policy's limit, and a precision at or above the policy's floor, and no landing of the area inside the fix window carries a missed mistake; it SHALL judge the area unlearned when its precision is `n/a`. [UC1 4]
R56. IF any review area the diff touches is unlearned, or a changed path belongs to no review area, THEN the rule's risk SHALL be `high unlearned` unless `outward` applies, and a path in no area SHALL print as `area: none unlearned`. [UC1 4, 3a]
R57. IF the thresholds cannot be read under the base-branch policy contract, THEN the risk rule SHALL judge every review area unlearned. [UC1 4a]
R58. IF the trace is unconfigured or holds a `SCHEMA` the reader cannot judge, THEN the risk rule SHALL judge every review area unlearned, name the cause on standard error, print its lines, record nothing, and exit 0. [UC1 4b]
R59. WHEN the Axis-2 `review.verdict` at the PR's head commit carries more outward items than there are items ruled `keep` at that head (by `operator`, or by `default` with no later `operator` ruling of that item at that head), the rule's risk SHALL be `high outward`; a `session` ruling SHALL never count as ruled. [UC2 4, 3b, 3c, 4a, UC4 3, 3a]
R60. IF the trace holds no Axis-2 `review.verdict` at the PR's head commit, THEN the rule's risk SHALL be `high unclear` unless `outward` or `unlearned` applies. [UC2 1a, 2a]
R61. The effective risk SHALL be `high` when either the planner's or the rule's risk is `high`, carrying the rule's reason when the rule's risk is high and the planner's otherwise, and `low` only when both are `low`. [UC1 6, 7b]
R62. The risk rule SHALL check every `Risk` value it prints with the vocabulary checker, declaring itself the risk rule, and SHALL print nothing and exit 2 if the checker refuses one.
R63. WHEN the risk rule judges a PR, it SHALL record one `risk.judge` event with subject `pr:#<N>`, the ticket in `related` when there is one, outcome `disagreed` when the planner's level differs from the rule's and `agreed` otherwise, and in `data` the head commit, the planner's, rule's and effective risks, the unlearned areas and the switch state. [UC1 7, 7b]
R64. IF the trace already holds a `risk.judge` for the same PR and head commit with the same risks and switch state, THEN the risk rule SHALL record nothing. [UC1 7a]
R65. WHILE the kill switch is tripped, the risk rule SHALL replace a rule's risk of `low` with `high unlearned`, print `switch: tripped`, and record `data.switch=tripped`. [UC4 2]
R66. The kill switch SHALL read tripped when the base branch's policy sets it so, when that value cannot be read, or when the trip marker exists in the clone's git directory, and on otherwise. [UC4 1, 3, 1a, 2b]
R67. The risk rule SHALL read the thresholds and the switch value only through the base-branch policy contract, never from the environment or the PR's own tree. [UC4 2a]
R68. The risk rule SHALL exit 0 whatever risk it prints, and SHALL write nothing but its `risk.judge` event. [UC1 8]
R69. The risk rule SHALL print and record only risk tokens, review area names from the lens-slice policy, `none`, the switch words, digits and commit shas, and no text from a ticket body, a PR body or a commit message.
R80. WHEN the landing script runs with `--lane`, it SHALL make every refusal it makes without `--lane`, with the same exit code and the same effect. [UC1 4, 4a]
R81. IF `--lane` is given with `--no-iteration`, `--no-review`, `--unasked` or `--train`, THEN the landing script SHALL exit 2, merging and recording nothing. [UC1 4]
R82. WHEN every refusal has passed in lane mode, the landing script SHALL check, in this order, `closed`, `drift`, `escape`, `path`, `base-red`, `check-table`, `verifier`, `switch` and `risk`, and on the first that applies SHALL print `lane: held <token>`, merge nothing and exit 4. [UC1 5]
R83. The lane SHALL read as closed, holding with `closed`, when the lane policy names no operator or cannot be read under the base-branch policy contract. [UC1 5a, UC4 6]
R84. IF the landing script or the risk rule in the running checkout differs from its version on the base branch, THEN a lane run SHALL hold with `drift`. [UC1 5b]
R85. IF the PR's diff from its merge base touches a file `VERSION`'s `files:` list names at either end, a policy file read under the base-branch policy contract, or a path the lane policy's hold patterns select, THEN a lane run SHALL hold with `path`. [UC2 1, 2, 1a]
R86. IF the latest run of any workflow on the base branch's head did not succeed, THEN a lane run SHALL hold with `base-red`. [UC1 6a]
R87. IF the check-table reader, given the PR body and the ticket body, exits anything but 0, or no ticket body is given, THEN a lane run SHALL hold with `check-table`. [UC1 5c]
R88. A lane run SHALL run the risk rule at the PR's head commit with the PR and its ticket, SHALL read only its `effective:` and `switch:` lines, and SHALL hold with `switch` when it prints `switch: tripped` and with `risk` when it prints any effective risk but `low`. [UC1 5, 5d, UC4 4]
R89. WHEN a lane run passes every check, the landing script SHALL merge the head commit the risk rule judged, and SHALL let the forge refuse a merge whose head has moved. [UC1 6, 5e]
R90. WHEN the lane lands a PR, the landing script SHALL record `merge.land outcome=landed data.via=lane` with the count of decision-log ids in the PR body, and `feedback outcome=unasked data.by=lane`, and SHALL print `lane: landed`. [UC1 6]
R91. WHEN a lane run holds a PR, the landing script SHALL record one `merge.land outcome=skipped data.via=lane` with the hold token and the head commit, and SHALL record nothing when the trace already holds one for the same PR, head and token. [UC1 6b]
R92. Before it judges a PR, a lane run SHALL run the outcome recorder, and SHALL handle every escape that has no `lane.escape` event. [UC3 1, 2, 5a]
R93. The trace SHALL accept the kind `lane.escape` with the outcomes `revert`, `fix` and `notified`, subject the escaped PR, and SHALL refuse any other outcome on it, exit 2, writing nothing. [UC3 5]
R94. WHEN an escape's outcome is `qa-failed`, the landing script SHALL open one PR reverting the escaped PR's merge commit on a new branch from the base branch, and record `lane.escape outcome=revert` with that PR in `related`. [UC3 3, 5]
R95. IF the revert does not apply cleanly, THEN the landing script SHALL open no PR, SHALL file one fix ticket stamped `Risk: high unclear` naming the escaped PR, the outcome and its review areas, and SHALL record `lane.escape outcome=fix` with that ticket in `related`. [UC3 3a]
R96. WHEN an escape's outcome is `reverted` or `fixed`, the landing script SHALL open no PR and file no ticket, and SHALL record `lane.escape outcome=notified`. [UC3 1a]
R97. WHEN the landing script records a `lane.escape`, it SHALL send the lane's operator one notice naming the outcome, the escaped PR, its review areas and the revert PR or fix ticket when there is one. [UC3 4]
R98. IF opening the revert, filing the ticket or sending the notice fails, THEN the landing script SHALL record no `lane.escape` for that escape, name the cause on standard error, and hold the PR it was judging with `escape`. [UC3 3b]
R99. A lane run SHALL hold with `escape` a PR that a `lane.escape` event names in `related`, or whose ticket one names. [UC3 7]
R100. WHEN a base-branch workflow fails after a lane landing, the landing script SHALL exit 1 as it does today and send the lane's operator one notice naming the landed PR and the failed run. [UC1 6a]
R101. WHEN the landing script runs with `--escapes` and no PR, it SHALL record outcomes and handle every unhandled escape as a lane run does, merge nothing, and exit 0. [UC3 7a]
R102. The landing script's lane output, its lane events and its notices SHALL carry only closed tokens, review area names, PR and ticket numbers, commit shas, run ids and digits, and no text from a ticket body, a PR body, a commit message or a log.
R103. The adapter's root guard SHALL refuse an agent's tool call that deletes, moves or overwrites the kill switch's trip marker. [UC4 5]
R104. IF the latest `verify.verdict` on the PR, read as runtime/R214 reads it for `merge.land`, is not `pass`, THEN a lane run SHALL hold with `verifier`, print `lane: held verifier <reason>` with the reason `disputed` for a `blocked` verdict whose `data.disputed` is 1 or more, `blocked` for any other `blocked`, `unavailable` for `unavailable`, and `none` when there is no such verdict, and SHALL record the reason in the hold event's `data.reason`. [UC1 5f]
R140. The trace SHALL accept the kind `ruling` with the outcomes `keep` and `change`, subject `pr:#<N>`, carrying `data.item` of the form `A2-<n>`, `data.surface` from the vocabulary's `surface` field, `data.head` of 40 hex digits and `data.by` one of `operator`, `session` and `default`, and SHALL refuse any other outcome or shape, exit 2, writing nothing. [UC2 3]
R141. The trace SHALL refuse, exit 2, an Axis-2 `review.verdict` whose `data.outward_items` is not a comma-separated list of `A2-<n>:<surface>` entries, or whose entry count differs from its `data.outward`. [UC2 1]
R142. WHEN the broker records an Axis-2 verdict, it SHALL carry `data.outward_items`, one entry per outward item in confirm-list order, reading each item's surface only as a vocabulary token and as `other` where it is missing or not in the vocabulary. [UC2 1]
R143. WHEN the ruling recorder runs with a PR, an item id and `keep` or `change`, it SHALL record one `ruling` event with that item's surface as the latest Axis-2 `review.verdict` on the PR lists it, and the head commit that verdict was made at. [UC2 3]
R144. IF the PR has no Axis-2 verdict, or the item is not among the latest one's outward items, THEN the ruling recorder SHALL exit 2, recording nothing. [UC2 3a]
R145. The ruling recorder SHALL set `data.by` to `session` when the environment carries an agent-harness marker and to `operator` otherwise, and SHALL exit 2, recording nothing, when its caller supplies a `by`. [UC2 3b]
R146. The ruling recorder SHALL record nothing when the trace already holds a ruling for the same PR, item, head, `by` and outcome.
R147. The ruling recorder SHALL print and record only item ids, surface tokens, review area names, PR numbers, commit shas and the words of runtime/R140, and no text from a PR, a comment, a commit message or a ticket.
R148. IF the trace is unconfigured, THEN the ruling recorder SHALL record nothing, print nothing on standard output, say so on standard error and exit 0.
R149. The adapter's root guard SHALL refuse an agent's tool call that runs the ruling recorder while unsetting or overriding an agent-harness marker. [UC2 3b]
R150. The risk policy SHALL ship with an empty ruling-defaults list whose entries take the form `<review area>:<surface>`. [UC4]
R151. WHEN the ruling recorder runs with `--defaults` and a PR, it SHALL record one `ruling outcome=keep data.by=default` for each outward item at the latest Axis-2 verdict whose surface the ruling defaults pair with every review area the PR's diff from its merge base touches, and none for an item of surface `other`. [UC4 2, 2a, 2c]
R152. The ruling recorder SHALL read the ruling defaults only through the base-branch policy contract, and SHALL record no default and print the fail-closed line on standard error when that read fails closed. [UC4 2b]
R153. The ruling recorder SHALL apply no ruling-defaults entry whose area is not a review area of the lens-slice policy or whose surface is not in the vocabulary or is `other`, and SHALL name each such entry on standard error. [UC4 2c]
R200. The trace SHALL accept the kind `verify.verdict` with the outcomes `pass`, `blocked` and `unavailable`, and SHALL refuse any other outcome on it, exit 2, writing nothing. [UC1 4, 1a]
R201. The trace SHALL refuse, exit 2, a `verify.verdict` of outcome `pass` or `blocked` that carries no `data.reviewed` of 40 hex digits or no `data.provider` token. [UC1 4]
R202. The trace SHALL accept a `finding.raise` or `finding.triage` id of the form `V-` followed by a lens finding id, and SHALL refuse every other id it refuses today. [UC1 4, UC2 1]
R206. WHEN the skill dispatcher runs the verifier on a pull request's head, it SHALL stage the verifier contract, the head commit's diff against its base, and the ticket body as files, and SHALL give the worker no network and no forge credential. [UC1 2]
R207. WHEN the dispatcher runs the verifier on a PR whose body carries a check table, it SHALL also stage, for each `pass` row, the line of the head's living spec that carries the row's id, and the pinned test file as it stood at the pinned commit. [UC1 2]
R208. IF the resolver prints no verifier, or the verifier's spawn still fails after one re-resolve with the failed model named unreachable, THEN the dispatcher SHALL record one `verify.verdict outcome=unavailable` on the PR with the reason, and nothing SHALL be posted. [UC1 1a, 2a]
R209. The broker SHALL validate a verifier's report against the review worker's contract, and SHALL post it as one review (event COMMENT, findings inline) and one comment, each under a marker distinct from the kit review's markers. [UC1 3]
R210. The broker's check for an earlier post SHALL read a verifier's markers and the kit review's markers apart, so a post of one never stops a post of the other. [UC1 3]
R211. WHEN the broker posts a verifier's report, it SHALL record one `verify.verdict` on `pr:#<N>` carrying `data.reviewed`, `data.provider` and `data.disputed`, with outcome `blocked` when the report holds a CRITICAL or HIGH finding or a disputed row and `pass` otherwise, and SHALL raise each finding as `finding.raise` with its `V-` id and `data.agent=verifier`. [UC1 4, 3a]
R212. IF a verifier's report lacks one pin line for each `pass` row the check-table reader returns, or a pin line carries a word other than `upheld` or `disputed`, THEN the broker SHALL exit 65, posting nothing and recording nothing. [UC1 3b]
R214. WHEN the landing script records `merge.land`, it SHALL carry `data.verified`: the outcome of the latest `verify.verdict` on the PR stamped at or after the head commit's committed date, or `none` when there is none. [UC3 1, 1b]
R215. No `verify.verdict` outcome SHALL change whether the landing script refuses, waits or merges, except the lane's `verifier` hold of runtime/R104. [UC3 1]
R216. The record reader SHALL print, per review area, the verifier's findings held up, not held up and unlabelled, its precision, the mistakes it caught, and the count of landings whose `merge.land` carries `data.verified=blocked` while an Axis-1 `review.verdict` at the same head has outcome `pass`. [UC4 1, 2, 2a]
R217. WHEN the dispatcher runs the verifier on a pull request's head, it SHALL also stage, as one data file, each finding the kit's own review raised on that PR at that head (any `data.agent` but `verifier`), with its id, severity, place and text, and SHALL stage an empty file when that review raised none. [UC1 2, 3d]
R218. IF the kit's own Axis-1 `review.verdict` is not yet recorded at the head when the verifier is requested, THEN the dispatcher SHALL record one `verify.verdict outcome=unavailable` on the PR naming that reason, and nothing SHALL be posted. [UC1 0a]
R219. The verifier contract SHALL ask for one finding verdict line per staged finding, carrying the finding's id, `confirmed` or `disputed`, and evidence: a `<path>:<line>` at the head commit and a span quoted from that line. [UC1 3]
R220. IF a verifier's report lacks a finding verdict line for a staged finding, names an id that was not staged, carries a word the vocabulary's `finding-verdict` field does not hold, or quotes a span the broker does not find on the cited line of the cited file at the head commit, THEN the broker SHALL exit 65, posting nothing and recording nothing. [UC1 3c]
R221. The trace SHALL accept the kind `finding.verify` with the outcomes `confirmed` and `disputed`, carrying a lens finding `data.id` and a `data.where` place, and SHALL refuse, exit 2, writing nothing, any other outcome, a `V-` id, or a missing `data.id` or `data.where`. [UC1 4]
R222. WHEN the broker posts a verifier's report, it SHALL record one `finding.verify` on `pr:#<N>` per finding verdict line, with `data.agent=verifier` and the evidence place as `data.where`, SHALL show each verdict with its evidence in the posted comment, and SHALL set the `verify.verdict` outcome by runtime/R211 alone, unmoved by any finding verdict. [UC1 3, 4]
R223. The record reader SHALL print, in each area's verifier row, the kit findings the verifier confirmed and those it disputed, each split into held up, not held up and unlabelled, and SHALL count no `finding.verify` toward a lens's counts or a finding's label. [UC4 3]
R227. WHEN the broker records a `verify.verdict` of outcome `pass` or `blocked`, it SHALL carry `data.rung` as the rung the resolver named for that run, and SHALL exit 65, posting nothing and recording nothing, when the dispatcher passed no rung or a word other than `cross-provider` or `same-provider`. [UC1 4, 1b]
R228. The record reader SHALL print each area's verifier row once per rung, from the `verify.verdict` events' `data.rung`, and SHALL count a verifier finding or finding verdict in the row of the rung its PR's verdict at that head names. [UC4 4]
R229. WHERE the trace policy's `TRACE_FACTORY_IDS` names a word `<type>=<PREFIX>`, the trace SHALL accept at emit a subject or `related` token `<type>:<PREFIX>-<digits>` whose id is canonical, beside the `<type>:#<digits>` spelling the type already takes. [UC1 3, UC2 3]
R230. IF a subject or `related` token of a type `TRACE_FACTORY_IDS` names is neither `<type>:#<digits>` nor a canonical factory id of that type's prefix, THEN the trace SHALL exit 2 at emit, write nothing, and name the two forms the value should take.
R231. IF a `TRACE_FACTORY_IDS` word is not `<type>=<PREFIX>` with a type `TRACE_NUMBERED_TYPES` names and a prefix of 1 to 8 uppercase letters, THEN the trace SHALL exit 2 naming the word and the policy file.
R232. WHEN `show` is given a canonical factory-id subject, the trace SHALL print exactly the events whose subject is that string or whose `related` holds it as a whole token, so that `ticket:T-07` never matches `ticket:T-070`. [UC2 3]
R233. WHEN `verify` reads a line written with a factory-id subject, it SHALL pass a canonical one and SHALL advise on a non-canonical one as it advises on a mis-spelled numbered subject, its verdict unchanged.
R234. WHERE `TRACE_FACTORY_IDS` is empty or unset, the trace SHALL judge every subject exactly as it did before this PRD. [UC5]
R235. The shipped trace policy SHALL carry `TRACE_FACTORY_IDS` empty, with a comment naming its form, and the kit's own trace policy SHALL set it to `ticket=T prd=PRD`.
R236. WHEN the release that ships runtime/R229 to R234 lands, `UPDATING.md` SHALL tell a consumer that the trace accepts factory-id subjects through `TRACE_FACTORY_IDS`, that a project which sets `TRACE_NUMBERED_TYPES` and plans in the factory sets it to `ticket=T prd=PRD`, and that an empty value changes nothing.
R241. The landing script's `--ticket` SHALL accept an issue number or a canonical factory ticket id, and SHALL refuse anything else as a usage error, exit 2, before any forge call. [UC2 1a, 1b]
R242. The landing script SHALL read a landing line whose handle is `#<N>` or a canonical factory ticket id, and SHALL record any other spelling as absent, `data.implement=no`. [UC2 2, 2a]
R243. IF a PR closes no issue, no `--ticket` is given, and its landing line names a canonical factory ticket id, THEN the landing script SHALL take that id as the PR's ticket. [UC2 2]
R244. WHEN the landing script's ticket is a factory ticket id, it SHALL read `ticket.start` on `ticket:T-<digits>`, and write `pr.open`, `merge.land` and `feedback` with `ticket:T-<digits>` wherever it writes `ticket:#<N>` for an issue. [UC2 3, 4]
R245. The landing script SHALL run no `factory` subcommand and SHALL write no file under `.factory/`. [UC2 5]
