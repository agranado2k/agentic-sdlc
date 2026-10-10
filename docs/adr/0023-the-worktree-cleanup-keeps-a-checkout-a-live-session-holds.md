# ADR-0023: The worktree cleanup keeps a checkout a live session holds

- **Status**: Accepted
- **Date**: 2026-10-10
- **Deciders**: the implementer session for #680, under the operator's delegation of rulings (2026-10-10); the merge of its pull request is the operator's yes
- **Supersedes / amends**: amends ADR-0008 clause 5 (its #472 amendment: `stack <dir>` gains a `--all` form) and names a second caller of `stack` beside clause 7 — recorded as a new record because ADR-0021 clause 4 closes ADR-0008 to in-place amendment; the successor (#692) folds it in
- **Superseded by**: —

## Context and problem statement

`scripts/worktree-cleanup.sh` removes a worktree under `worktree/` and its
branch when the branch is merged into the base and the worktree is clean. A
session still working in that worktree right after its pull request lands
looks exactly like that: merged, and clean once it has committed. A cleanup run
by the operator or by another session at that moment removes the worktree out
from under the live one. The operator's workaround lived only in memory —
"skip `worktree-agent-*` branches" — and the housekeeping pass of 2026-10-09
(`housekeeping-20261009T142448Z`, finding 9) filed it as #680.

The evidence a session is live already exists in two places. A skill that is
running holds an open run on the run stack of the checkout it began in. A
process working in the checkout has its current directory inside it. The
cleanup reads neither.

The run stack is not the cleanup's to read directly. Since #453 each session
keeps its own stack per checkout, and since #472 `scripts/trace.sh stack <dir>`
is the one reader of a stack, so no caller repeats its path or format. But
`stack <dir>` answers for one session — the one its caller names or carries
in `TRACE_SESSION`, else the checkout's pointer file. The cleanup stands in the
root checkout and knows no session but its own, and the live session's stack
is keyed by an id it never sees.

## Decision drivers

- **A miss is data loss, an extra keep costs one more run.** Every doubt keeps.
- **The stack's format stays the trace script's** (ADR-0008 clause 5, #472).
- **The cleanup ships to consumers and must work with tracing off.**
- **The chain never reads the trace** (ADR-0008 clause 7).

## Considered options

1. **`stack <dir> --all` in the trace script, read by the cleanup, plus a
   process check** *(chosen)*.
2. **The cleanup globs the stack files itself.** Rejected: a second copy of
   the stack's path and format, exactly what #472 removed from the adapter.
3. **`stack <dir>` with the cleanup's own session.** Rejected: it reads the
   cleanup's own runs, never the live session's.
4. **A process check alone.** Rejected as the only evidence: an agent
   harness's tool calls are short-lived processes, so a session between calls
   has none standing in the worktree.
5. **Skip by branch-name pattern** (the operator's workaround). Rejected: a
   convention of one harness, not evidence, and it keeps a finished worktree
   forever.

## Decision outcome

Chosen: **option 1.**

1. **`sh scripts/trace.sh stack <dir> --all`** prints every run open in the
   checkout `<dir>` is in, whoever opened it: the top of each session's stack
   there and of the session-less one, one run per line, in no promised order,
   never a run below a top. `--all` takes the place of `session=`; both at
   once is a usage error, exit 2. Its refusals are `stack <dir>`'s, with one
   addition: one stack that exists and cannot be read refuses the whole
   answer, exit 2, nothing on stdout — a partial "nothing open" would read as
   leave to prune. Unconfigured, it prints nothing and exits 0. It reads
   stacks, never an event, and writes nothing.
2. **The cleanup keeps a merged, clean worktree that a live session holds**,
   and names why: `live: open run <run id>` when `stack <wt> --all` printed a
   run, `live: process <pid> works in it` when a process's current directory
   is inside it (read from `/proc` where it exists; elsewhere that leg is
   silent). It asks only for a worktree it would otherwise remove. A trace
   that refuses to answer keeps the worktree too, naming the exit. An open run
   a crashed session left behind keeps its worktree until the run is closed —
   the run id in the reason is what the operator closes.
3. **Clause 7 stands.** The cleanup script is an operator-run tool, as the
   adapter's hooks are the adapter's business; `/worktree-cleanup`'s skill
   text calls no read subcommand, and `tests/trace-skills.test.sh` still holds
   every skill directory to that.
4. **The policy the cleanup's trace reads is the trace's own seam.** The
   cleanup runs `scripts/trace.sh` from the root checkout, so it reads that
   checkout's `scripts/trace.config.sh`, or `TRACE_CONFIG` when set. The kit's
   own policy is the kit-only twin, so in the kit the cleanup is run with
   `TRACE_CONFIG=scripts/trace.kit.config.sh` (the root manual's hard rule 10).

## Consequences

- **Good**: a just-landed worktree a session still holds survives a cleanup,
  by evidence, and the summary says which run or process kept it.
- **Good**: the stack's format still has one reader.
- **Bad / trade-off**: `scripts/trace.sh` is shared layer, so `--all` ships in
  a release (#687's wave), and a consumer who takes the new cleanup without
  the new trace script gets a usage refusal from `stack`, which keeps every
  merged worktree, named, until the trace script is taken too.
- **Bad / trade-off**: a run left open by a crashed session holds its worktree
  until somebody closes the run.
- **Honest limitation**: the process leg reads `/proc`; on a system without it
  only the trace leg answers, and with tracing off nothing does — the cleanup
  is then exactly as it was before.

## More information

- Built for #680, from `housekeeping-20261009T142448Z`, finding 9.
- Held by `tests/trace.test.sh` section 34 and `tests/worktree-cleanup.test.sh`.
- Related: ADR-0008 clauses 5 and 7, ADR-0021 clause 4, the #453 and #472
  amendments of ADR-0008.
