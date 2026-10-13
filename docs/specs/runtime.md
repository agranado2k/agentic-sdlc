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
