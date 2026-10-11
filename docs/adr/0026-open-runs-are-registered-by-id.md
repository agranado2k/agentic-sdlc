# ADR-0026: Open runs are registered by id

- **Status**: Accepted
- **Date**: 2026-10-11
- **Deciders**: the operator, in the `/grill-with-docs` session for PRD #742 (2026-10-11); the implementer session for #745 under the operator's delegation of rulings; the merge of its pull request is the operator's yes
- **Supersedes / amends**: amends ADR-0024 clause 5 — `begin` and `end` gain a second thing they write, the registry, and `begin` a `--detached` form; recorded as a new record so ADR-0024 takes a one-line link rather than a sixth paragraph in its longest clause (ADR-0021)
- **Superseded by**: —

## Context and problem statement

A run lives on a run stack, keyed by checkout and session (ADR-0024 clause
5), and nowhere else while it is open. A dispatched worker's run and a
cascade's never touch a stack: the dispatcher mints an id by its own recipe
and hands it on in `TRACE_RUN`, so while the worker runs its run exists only
in an environment variable. The operator watching a wave cannot ask what is
running, and a run a crashed worker left open is found only after the fact,
by `/retro` pairing `run.start` with `run.end` in the log. Nor is there one
minter: the dispatcher's own recipe was the one that went wrong (#743).

`stack <dir> --all` (ADR-0023) answers for one checkout's stacks, and cannot
see a run that was never pushed.

## Decision drivers

- **Parallel writers never contend over one file** (craft §11): fifty
  workers may register at once.
- **The event log stays the durable record**; whatever answers "what is open
  now" is a view, never a second source of truth.
- **The trace is the only minter of a run id.**
- **Stale is reported, never guessed away**: a process check is evidence,
  not a verdict.
- **Unconfigured is a working state.**

## Considered options

1. **One file per open run, keyed by run id, under the trace directory,
   landed by rename** *(chosen)*.
2. **One registry file, appended and rewritten.** Rejected: every writer
   contends over it, and removal is a rewrite a parallel append can lose.
3. **Derive open runs from the event log** (`run.start` with no `run.end`).
   Rejected as the live answer: it reads every day's file to answer a "now"
   question, and a run whose `run.end` was never written reads as open for
   ever. It stays `/retro`'s question.
4. **Push detached runs onto a stack of their own.** Rejected: a stack is
   per checkout and session, and a detached run's owner may end it from
   anywhere; a stack would also make two concurrent begins lose a push.

## Decision outcome

Chosen: **option 1.**

1. **The open-run registry is `runs/<run id>` under the trace directory**,
   one file per run begun and not ended, each `<field>=<value>` lines in a
   fixed order: `run`, `parent`, `session`, `checkout`, `opened` (`stack` or
   `detached`), `pid`, `host`, `started` (a UTC second). An entry is staged
   under the trace directory's `tmp/` and landed by one rename, so a reader
   sees a whole entry or none and concurrent registrations each land.
   A run id is held to the shape `id --check` holds before any path is built
   from it.
2. **Writers.** `begin` registers its run, opened `stack`, after its
   `run.start` and before its push. **`begin --detached <skill>`** mints a run
   through the same minter `id` uses, writes its `run.start` with the run
   current at the call as its parent, registers it opened `detached`, prints
   the id, and changes no run stack. Unconfigured, it prints a well-formed id
   and writes nothing. `end` removes the entry of the run it closes, after
   its `run.end`; `end <run>` naming a detached run closes it from any
   checkout or session — its `run.end` carries the parent its entry named —
   and a run with no entry and not on the stack is refused as before. A run
   handed to a subagent on a `Trace-Run:` line is the spawner's own and
   already registered. An entry that will not go is said on stderr and the
   exit stays 0: the run is closed, and its `run.end` says so.
3. **Readers.** `runs` prints one line per entry, `<run> <opened> <state>
   <started> <parent|->`, oldest first; `runs <id>` prints that entry's
   fields, then `state=<state>`. An id with no entry — a value no run id has
   the shape of included — is exit 1 and nothing printed. An entry or a
   registry that cannot be read is exit 2. Unconfigured, `runs` prints
   nothing and exits 0. Neither writes.
4. **State.** An entry reads `live` while its process runs on this host,
   `stale` once that process is gone from this host, and `unknown` for an
   entry from another host or with no process id. The process is the one
   that called the script — for a dispatcher's `run=$(… begin --detached …)`,
   the dispatcher. **Only `end` removes an entry**; a stale one stays until
   its run is ended.
5. **Clause 7 stands.** `runs` is a reader for the operator and for
   operator-run tools; no chain skill calls it.

## Consequences

- **Good**: every open run, a dispatched worker's and a cascade's included,
  is queryable by id while it runs, and one left open is visible as stale.
- **Good**: one minter — the dispatcher and the cascade can move onto
  `begin --detached` (#746) and drop their recipes.
- **Bad / trade-off**: `scripts/trace.sh` is shared layer, so the registry
  ships in a release (0.71.0).
- **Bad / trade-off**: a run left open by a crashed process keeps its entry
  until somebody ends it; nothing sweeps.
- **Honest limitation**: a caller whose shell is itself short-lived — an
  agent harness's one-command shell — registers a process that is gone when
  the command returns, so a session's stack run reads `stale` while it is
  open. Stale is evidence for a reader to weigh, not a verdict; what reopens
  this is a reader shown to need a live answer for such a run, and then the
  caller names its long-lived process.
- **Honest limitation**: a process this user may not signal reads as gone;
  the trace directory's writers are this user.

## More information

- Built for #745, from PRD #742 (R7–R14), grilled with `/grill-with-docs`
  on 2026-10-11; the glossary's **Open-run registry**, **detached run** and
  **stale** came from that session.
- Held by `tests/trace.test.sh` section 36.
- Later, recorded in PRD #742's out-of-scope list: the worktree cleanup and
  `/retro`'s orphan check reading the registry in place of `stack --all`
  (reopen when one misses a detached run), and sweeping stale entries
  (reopen when they are seen to accumulate).
- Related: ADR-0024 clauses 5 and 7, ADR-0023, ADR-0021, craft §11.
