# ADR-0006: A dispatched worker runs inside a budget derived from the host at dispatch time

- **Status**: Accepted
- **Date**: 2026-09-19
- **Deciders**: Arthur Granado
- **Supersedes / amends**: amends ADR-0005 in one respect — its clause 12 says the dispatcher does not enforce what a worker may *do*; it still does not, and it now bounds what a worker may *consume*
- **Superseded by**: —

## Context and problem statement

`scripts/agent-dispatch.sh` bounds a worker in time (`--timeout`, since
0.19.0) and in nothing else. A worker is a whole process tree — an agent CLI
under a shell, and everything it spawns — and every task in that tree counts
against the ceiling the operator's own login session runs under. On a 2 vCPU /
3.7 GiB host the dispatch suite, driving a stub that re-dispatched itself,
filled that ceiling in under three minutes; the kernel logged `cgroup: fork
rejected by pids controller` 91 times in one boot, each run preceded by the
suite. Past the ceiling nothing of the operator's can fork: the shell dies, the
agent harness aborts, the SSH session drops. It reads as the machine crashing
(#205).

The ceiling in question is the user slice's `TasksMax` — 10008 on that host,
which is systemd's default of 33% of `kernel.threads-max` (30329), not a number
anyone chose. The operator shares it with every worker they dispatch. The
recursion that triggered the incident was fixed on its own (#204) and a depth
limit is its own ticket (#206), but neither bounds a single worker that fans
out: a build that spawns a thousand processes, or an agent CLI that runs the
suite that runs the dispatcher. A time bound does not help either — the slice
filled well inside any timeout a review would tolerate.

What cannot be built until this is settled: the enforcement (#208) and the
suite running under it (#209) both need one definition of the bound, where its
numbers come from, how it is inherited by a nested dispatch, and what a worker
that hits it looks like to the caller.

## Decision drivers

1. **The operator's session survives a runaway worker.** The bound sits below
   the ceiling the session shares, by a margin, on every host.
2. **The kit names no host.** One file runs on a 2 vCPU VM, a 64-core
   workstation and a CI container; a number in the kit is wrong everywhere but
   one.
3. **Unset is a working state** (the resolver's contract, ADR-0005 driver 4): a
   project that never heard of a budget gets a sane one, and can see it before
   it spends a token.
4. **Loud degradation.** A bound the host cannot apply is announced, never
   silently dropped.
5. **Policy is the consumer's, mechanism is the kit's** (`VERSION`'s split):
   fractions and clamps are policy-file data; derivation, the ladder and the
   verdict are shared layer.
6. **A verdict the caller can read.** The timeout's 124 set the shape — a
   distinct status, decided by a flag the dispatcher writes from what it
   observed, never inferred from the worker's own status.

## Considered options

1. **A budget derived from the host at dispatch time** — a percentage of the
   task ceiling the session runs under and of the memory available now, each
   clamped, enforced through the strongest mechanism the host offers *(chosen)*.
2. **A fixed cap in the kit** (`TasksMax=300`, say) — rejected on driver 2: it
   is the number that was right for the incident's host, too small for a
   workstation's build and too large for a container whose whole slice is
   512; and it is a standing number with a timer on it, the way a model id is.
3. **Lower the user slice's own `TasksMax`** — rejected on driver 1: the slice
   *is* the operator's session, so lowering it lowers the operator too and
   bounds no worker separately — a runaway still fills whatever the slice has,
   and the shell still dies, only sooner. It also takes root for the slice
   drop-in, which the kit cannot ask for.
4. **The timeout alone** — rejected: the slice filled in under three minutes,
   and a timeout short enough to catch that is shorter than any review.
5. **The depth limit alone (#206)** — rejected as a substitute, kept as a
   complement: it bounds recursion, not one worker's fan-out.
6. **rlimits as the only mechanism** — rejected as the first rung, kept as the
   second: `RLIMIT_NPROC` counts the uid's processes rather than the tree's,
   every rlimit is per process and inherited rather than per tree, and an
   address-space limit is meaningless for an agent CLI that reserves gigabytes
   it never touches. A cgroup bounds a tree; an rlimit bounds a process.

## Decision outcome

Chosen: **a host-derived budget — policy-file percentages and clamps, applied
down a ladder, inherited by a nested dispatch, with its own exit status.**

1. **A budget** is two ceilings on a dispatched worker's whole process tree: a
   **task ceiling** (the number of tasks — threads and processes — the tree
   may hold at once) and a **memory ceiling** (in MiB). It is decided once, at
   dispatch time, and is a property of the dispatch — never of the tier, the
   task domain, the agent harness or the model.

2. **Derivation.** Each ceiling is a percentage of a host fact, clamped:
   - The task ceiling is `AGENT_BUDGET_TASKS_PERCENT` of **the task ceiling
     the operator's own session runs under**. With cgroup v2 that is the
     smallest numeric `pids.max` on the path from the dispatcher's own cgroup
     (the `0::` line of `/proc/self/cgroup`) up to the root — on a systemd
     host, the user slice's `TasksMax`. Where no cgroup on that path sets one,
     it is the per-user process limit (`ulimit -u`, or `-p` under dash).
     Where that is `unlimited` too, the policy ceiling stands in. The
     dispatch reports which.
   - The memory ceiling is `AGENT_BUDGET_MEMORY_PERCENT` of **`MemAvailable`**
     in `/proc/meminfo`, read at dispatch time — what the host could give right
     now, not what it has installed.
   - **Floor.** A derived value below `AGENT_BUDGET_TASKS_FLOOR` /
     `AGENT_BUDGET_MEMORY_FLOOR_MIB` is raised to the floor and the dispatch
     says so on stderr: below it a worker cannot do useful work, and a host
     that small leaves the operator less margin than the percentage promised.
     The operator hears that, and decides.
   - **Ceiling.** A derived value above `AGENT_BUDGET_TASKS_CEILING` /
     `AGENT_BUDGET_MEMORY_CEILING_MIB` is held to the ceiling, in silence: more
     headroom buys a worker nothing, and a big host is no reason to let one
     worker take a quarter of it.
   - **Never a fixed number in the kit.** The kit ships percentages and clamps;
     the host supplies the base.

3. **Kit defaults**, applied whenever a policy variable is unset or empty:
   tasks **25%**, floor **256**, ceiling **4096**; memory **50%**, floor
   **512 MiB**, ceiling **8192 MiB**. On the incident's host that is 2502
   tasks of 10008 and about 1 GiB of the 2 GiB available — when a worker runs
   away the operator keeps three quarters of the slice and half the memory.
   The defaults live in the dispatcher, so a policy file from an older release
   still gets them; the policy file documents them beside its six empty
   variables, in the shape every other variable there has. The kit's own
   never-shipped twin (`scripts/agents.kit.config.sh`, ADR-0003) sets none of
   them: the defaults are the kit's answer for itself, and #209 may tighten
   them for the suite.

4. **Where policy lives.** The six variables above, in `scripts/agents.config.sh`
   — the consumer's policy file, never overwritten by an update. Per dispatch,
   `--budget-tasks <n>` and `--budget-memory <MiB>` replace the derived value
   (an explicit number is honoured as given; one below the floor is warned,
   not raised), and `--no-budget` runs that one dispatch with no budget at all
   — **loudly**: on stderr and on the dry-run's budget line. `--no-budget`
   with either override is a usage error. Disabling is the only way to run a
   worker unbounded on a host that can bound one.

5. **The enforcement ladder**, top rung first. #208 implements it; a dispatch
   takes the highest rung its host offers, probed at dispatch time and never
   configured, because a policy file cannot know which host it is on:
   1. **A transient scope under the user's service manager**, where
      `systemd-run` is on PATH and `systemctl --user` reaches the manager:
      `systemd-run --user --scope -p TasksMax=<tasks> -p MemoryMax=<MiB>M`.
      The budget is then a cgroup shared by everything the worker spawns, and
      a fork or an allocation past it fails **inside the worker's boundary**
      while the operator's session keeps forking. This is the rung the
      incident's host offers, and the rung the suites are run under by hand
      until #209.
   2. **rlimits in the worker's shell** where there is no user manager:
      `ulimit -u <tasks>` for tasks (`-p` under dash, which spells
      `RLIMIT_NPROC` that way and has no `-u`; the dispatcher probes which
      spelling its `sh` has, since neither is POSIX) and `ulimit -d <KiB>`
      (`RLIMIT_DATA`) for memory. Weaker, and the dispatch says so:
      `RLIMIT_NPROC` counts every process of the uid, so the worker stops
      forking when the *uid* reaches the number, not the tree; a per-process
      data limit bounds each process and never their sum. Memory on this rung
      is best-effort.
   3. **A loud no-op** where the shell cannot set an rlimit either: the budget
      is derived, announced on stderr as not applied, and the worker runs as
      before. Never silent.

6. **The verdict.** A worker that exceeds its budget makes the dispatcher exit
   **71** — `EX_OSERR` in `sysexits.h`, whose gloss is "system error (e.g.,
   can't fork)", which is what the worker saw — distinct from 0, 2, 3, 124 and
   the signal statuses. As with 124, the verdict is a **flag the dispatcher
   writes from what it observed**, never an inference from the worker's own
   status: on the scope rung a wrapper inside the scope reads its cgroup's
   `pids.events` (`max` greater than 0) and `memory.events` (`oom_kill`
   greater than 0) after the worker exits and before the scope empties, and
   stderr names which ceiling was hit. On the rlimit rung there is no counter
   to read; #208 decides how much can be observed there, and a hit it cannot
   observe passes the worker's own status through — the weaker rung was
   already announced. A worker that both runs past `--timeout` and exceeds
   its budget exits with whichever fired first, and its tree is gone either
   way.

7. **Nesting.** A dispatch inside a dispatched worker runs **inside the
   outer's budget and never opens a fresh one**. The outer dispatcher exports
   the budget it applied into the worker's environment as
   `AGENT_DISPATCH_BUDGET_TASKS` and `AGENT_DISPATCH_BUDGET_MEMORY_MIB`; an
   inner dispatcher that finds them set derives nothing, opens no scope, sets
   no rlimit, and says on its dry-run that it inherited. A scope opened inside
   a scope would be a *sibling* under the user manager, outside the outer's
   cgroup — the escape this clause forbids. So a chain of nested workers
   shares one ceiling however deep #206 lets it go; the depth is #206's own
   variable, carried the same way, and the two are independent facts about a
   dispatch. An outer dispatch that ran with `--no-budget` exports nothing,
   and an inner one then derives its own.

8. **Visible before it is enforced.** `--dry-run` prints both ceilings, the
   host fact and percentage each came from, the clamp if one applied, the rung
   the host would offer, and — until #208 lands — that nothing is applied.
   What is shown is what will be enforced, computed by the same code.

9. **Explicit non-goal**: CPU time and I/O are not budgeted. Tasks were the
   incident; memory is the sibling that kills a host the same way; nothing
   else has.

10. **Explicit non-goal**: a budget is not a reservation. Two dispatches from
    one session each derive against the same host and are not made to fit
    together; the percentage is the margin, and a session that dispatches in
    parallel divides it itself.

## Consequences

- **Good**: the operator's session survives a runaway worker on any host with
  a user service manager, by construction rather than by luck, and the number
  that does it is visible before a token is spent.
- **Good**: #208 and #209 build from one definition — the variables, the
  flags, the ladder, the status, the environment names — with no decision
  left to make at implementation time.
- **Bad / trade-off**: six more policy variables and three more flags on a
  script whose usage line was already long. The price of a number that is
  never fixed.
- **Bad / trade-off**: on the rlimit rung the memory ceiling is best-effort
  and the task ceiling counts the uid rather than the tree. A host without a
  user manager gets a weaker promise, and the dry-run has to say so every
  time.
- **Neutral**: `--dry-run` grows four lines. A project that never dispatches
  to another agent harness sees nothing.
- **Honest limitation**: `MemAvailable` is a moment. A budget derived at
  dispatch time is not re-derived while the worker runs, so a host whose free
  memory halves afterwards still lets the worker use what was derived.
- **Honest limitation**: a transient scope bounds what the user manager can
  see. A worker that escapes its cgroup — a setuid helper, a daemon it hands
  to the system manager — is outside the budget.

## More information

- Implemented in: #207 (this record, the glossary term, the dry-run), #208
  (enforcement), #209 (the suite under the budget) — all part of #205, which
  carries the incident.
- Related: ADR-0005 (the dispatcher's home and its exit statuses);
  `scripts/agent-dispatch.sh`'s `--timeout` note (the 124 precedent clause 6
  copies); `sysexits.h` (`EX_OSERR` is 71); systemd's `DefaultTasksMax=`
  (33% of `kernel.threads-max`).
