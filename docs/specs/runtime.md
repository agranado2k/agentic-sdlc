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
(#877).

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
R39. The recorder SHALL map a landed commit to its PR only through a `merge.land` event's `data.merge_sha`, and SHALL read from commit messages and factory items nothing but the Conventional Commit type token, a 40-hex sha, `qa.outcome` and `links.pr`, each held to its shape, so that a PR number written in prose produces no outcome. [UC2 1a]
R40. A landing whose Conventional Commit type is neither `fix` nor `revert` SHALL produce no outcome. [UC2 1b]
R41. The recorder SHALL write no outcome the trace already holds for the same PR, outcome and evidence (`data.by_sha`, or `data.ticket` for `qa-failed`), so that a second run over the same history writes nothing. [UC1 5]
R42. IF a blamed line resolves to a landing that no `merge.land` with a merge sha names, THEN the recorder SHALL write no outcome for that line and SHALL print the count of such lines on standard error. [UC1 2b]
R43. IF the trace is unconfigured, THEN the recorder and the record reader SHALL write nothing, print nothing on standard output, and exit 0. [UC1 2c]
R44. WHEN the record reader runs, it SHALL print one row per review area of the lens-slice policy, holding the area's landed PRs counted (its most recent 20, or fewer, said as `<n> of 20`), how many of them landed inside the fix window, and how many carry a mistake. [UC1 4, UC4 1, 2, 1a]
R45. The record reader SHALL count a landed PR toward every review area that one of the paths its merge commit changed against its first parent belongs to. [UC1 4]
R46. The record reader SHALL count a mistake as missed unless a finding raised on that PR, not upheld at triage, names a file in the outcome's `data.files`, and SHALL always count a `qa-failed` mistake as missed. [UC4 3, 3a]
R47. The record reader SHALL print, per review area, the PRs with a missed mistake and the miss rate over the PRs counted. [UC4 3]
R48. The record reader SHALL count a finding toward every review area its `data.where` path belongs to, as held up when its triage is `accepted` or a mistake against its PR names its file, as not held up when it was rejected at triage or dismissed by a human with no such mistake, and as unlabelled otherwise. [UC4 4]
R49. The record reader SHALL print, per review area, the findings held up, not held up and unlabelled, the precision (held up over labelled), and the count of labels from triage, from a human dismissal and from a post-merge outcome. [UC4 4]
R50. IF a ratio's denominator is zero, THEN the record reader SHALL print `n/a` for it. [UC4 4a]
R51. The record reader SHALL compare no number to a threshold, SHALL print no risk word, and SHALL write nothing to the trace or to any file. [UC4 5]
