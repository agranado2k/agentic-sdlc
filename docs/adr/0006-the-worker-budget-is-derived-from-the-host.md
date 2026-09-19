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
     it is the per-user process limit — `RLIMIT_NPROC`, the number `ulimit -u`
     prints, read from `/proc/self/limits` so it comes through the same seam
     as the cgroup ceiling. The dispatch reports which.
   - The memory ceiling is `AGENT_BUDGET_MEMORY_PERCENT` of **`MemAvailable`**
     in `/proc/meminfo`, read at dispatch time — what the host could give right
     now, not what it has installed.
   - **No host fact.** Where the base cannot be read — no `0::` cgroup sets a
     ceiling and `/proc/self/limits` has no `Max processes` line, or
     `/proc/meminfo` has no `MemAvailable` — or the per-user limit is
     `unlimited`, there is nothing to take a percentage of, and **the policy
     ceiling stands in** for that ceiling, on both sides. The ceiling is the
     most the policy lets one worker have, so the worker is bounded by the
     policy rather than by nothing. The floor is not used here: it answers a
     host *known* to be small, and an unknown host is not known to be small —
     a worker held to 512 MiB on a workstation because `/proc/meminfo` had no
     `MemAvailable` would be a false economy. The dry run names the fact that
     was missing; nothing is said on stderr, since no clamp was applied.
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
   **What sizes the clamps.** 256 tasks: an agent CLI is a few dozen
   threads, the shell and the tools under it a few dozen more, and a build or
   a test run beneath that a hundred or two in flight — below 256 a worker
   fails forks in its own test run rather than in a runaway. 4096: sixteen
   floors, a fan-out no single worker has a legitimate reason for; one that
   wants more *is* the incident. 512 MiB: an agent CLI's resident set is a
   few hundred MiB before it opens a file — below it a worker is killed on
   start rather than on a runaway. 8192 MiB: the whole of a small host —
   above it the worker, not the host, is what should be smaller. These are
   first sizings from the incident's host, and #209 re-measures them against
   the suite: a clamp the suite reaches in ordinary running is a clamp to
   re-decide, in a record that supersedes this clause on that point.
   **The permitted range.** Each variable is a positive whole number with no
   leading zero (shell arithmetic reads `025` as octal). A percentage is
   **1 to 99**: the budget sits below the ceiling the session shares (driver
   1), and 100 or more would put it at or above in silence. A floor is at
   most its ceiling. Anything else — `lots`, `0`, `025`, `150`, a floor above
   its ceiling — is refused at dispatch with exit 2, never defaulted or
   clamped: a policy value that cannot be a budget is a mistake to report.
   The two flags are held to the same validator.

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
      `systemd-run` is on PATH, `systemctl --user` reaches the manager, **and
      the manager has the `pids` and `memory` controllers delegated** — read
      from `cgroup.controllers` on the dispatcher's own cgroup, one more file
      on the path the derivation already walks. A manager that answers is
      reachable, not necessarily able to bound: under one without `memory`,
      `-p MemoryMax=` is accepted and applies nothing, which is the silent
      degradation driver 4 forbids. The rung is then
      `systemd-run --user --scope -p TasksMax=<tasks> -p MemoryMax=<MiB>M`.
      The budget is a cgroup shared by everything the worker spawns, and
      a fork or an allocation past it fails **inside the worker's boundary**
      while the operator's session keeps forking. With `pids` delegated and
      `memory` not, the scope is still the rung — the tree-wide task bound is
      what the incident needed — carrying `TasksMax` alone, and the memory
      ceiling on that host is announced and not applied (rung 3 for that one
      ceiling; not `ulimit -d`, which is a different promise rather than a
      weaker form of this one). With `pids` not delegated, or
      `cgroup.controllers` unreadable, a scope bounds nothing that matters
      and the ladder falls to rung 2. This is the rung the incident's host
      offers (`cpu memory pids`), and the rung the suites are run under by
      hand until #209.
      **When the rung refuses at execution** — `systemd-run` exits non-zero
      after the probe passed: the bus gone between probe and spawn, a
      unit-name collision, a manager that will not create scopes — #208
      falls to rung 2 and says so on stderr with `systemd-run`'s own message,
      rather than refusing the dispatch: the worker still runs, under the
      weaker promise, and the operator hears which. The wrapper inside the
      scope (clause 6) writes a started-marker before it runs the worker,
      and that marker is how #208 tells a scope that never opened from a
      worker that exited non-zero on its own. The dry run cannot show this
      case: it probes, and never opens a scope.
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
   can't fork)", which is what the worker saw — distinct from 0, 2, 3, 124,
   the status #206's depth refusal takes, and the signal statuses. As with 124, the verdict is a **flag the dispatcher
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
   `AGENT_DISPATCH_BUDGET_TASKS` and `AGENT_DISPATCH_BUDGET_MEMORY_MIB` —
   both or neither; an inner dispatcher that finds them set derives nothing,
   opens no scope, sets no rlimit, and says on its dry-run that it inherited.
   The pair is held to the same validator as the flags and the policy file,
   and one without the other is refused: the inner dispatch hands the numbers
   to the mechanism, so it takes them as given but not on trust. A scope opened inside
   a scope would be a *sibling* under the user manager, outside the outer's
   cgroup — the escape this clause forbids. So a chain of nested workers
   shares one ceiling however deep #206 lets it go; the depth is #206's own
   variable, carried the same way, and the two are independent facts about a
   dispatch. **An inherited budget wins over `--no-budget`**: the inner
   dispatch is already inside the outer scope's cgroup and no flag on it can
   leave, so the flag is not an escape — the dispatch takes the inherited
   numbers and says on its budget line and on stderr that `--no-budget`
   cannot escape them. Disabling, like deriving, belongs to the outermost
   dispatch. An outer dispatch that ran with `--no-budget` exports nothing,
   and an inner one then derives its own.

8. **Visible before it is enforced.** `--dry-run` prints both ceilings, the
   host fact and percentage each came from, the clamp if one applied, the rung
   the host would offer, and — until #208 lands — that nothing is applied.
   What is shown is what will be enforced, computed by the same code. Until
   #208, the two stderr notes clauses 2 and 4 attach to the dispatch — the
   floor raised, the budget disabled — are said under `--dry-run` only: a
   real dispatch applies nothing and says nothing about a budget it does not
   apply, and the suite holds it to that silence. #208 lifts both to every
   dispatch in the change that applies the budget.

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

### Amendment, 2026-09-19 — what building #208 refined in clauses 5, 6 and 8

#208 implemented the ladder as recorded, and building it against a real host
refined four things the clauses above left open or got wrong. The clauses
stand as written; this block is what binds where they differ.

- **Clause 5, rung 1 — the scope command carries two more properties.** The
  rung is `systemd-run --user --scope --unit=agent-dispatch-<suffix> -p
  TasksMax=<tasks> -p MemoryMax=<MiB>M -p MemorySwapMax=0 -p
  OOMPolicy=continue`. Without `OOMPolicy=continue` the host tore the whole
  scope down on the first out-of-memory event, and the wrapper (clause 6)
  never ran to read the counter the verdict needs; `continue` leaves the
  kernel to OOM-kill the offending task *inside* the cgroup, so the wrapper
  survives to read `memory.events`. Without `MemorySwapMax=0` the runaway
  filled swap for seconds first, which both delayed the bound and let
  `systemd-oomd`'s pressure kill of the scope pre-empt it; with swap denied,
  the ceiling bites at `MemoryMax` and is observable at once. A memory budget
  swap can evade is not a budget. The `pids`-only rung carries `TasksMax` and
  `OOMPolicy=continue`. The scope is **named** after the dispatch's scratch
  (`agent-dispatch-<mktemp suffix>`), so the dispatcher can reach the whole
  cgroup after the spawn: on `--timeout` it KILLs the unit after the tree
  walk's TERM/KILL pass, which is what makes "the tree is gone either way"
  hold for a child the worker double-forked out of the walk's reach, and a
  stray `agent-dispatch-*` scope has a name `/housekeeping` can list.
- **Clause 5, "when the rung refuses at execution" — decided before the
  spawn, never by a re-run.** The dispatcher opens and closes an empty scope
  with the real properties first, in milliseconds; a refusal there falls to
  rung 2 loudly with `systemd-run`'s own message. After the real spawn a
  missing started-marker is *reported* — the scope torn down before the
  worker started, or the scratch removed under an untimed dispatch older
  than the sweep age — and the run's own status passes through. The marker
  is a file a worker's tree or a sweep can remove; it never runs the worker a
  second time.
- **Clause 6 — nothing is observed on the rlimit rung, and an unreadable
  verdict is loud.** A `RLIMIT_NPROC` hit is uid-wide and a `RLIMIT_DATA` hit
  is a `malloc` the worker sees and the dispatcher does not, so on rung 2 a
  hit passes the worker's own status through; the weaker rung was already
  announced. On the scope rungs "could not read the counters" is never the
  same as "no ceiling hit": the wrapper writes `-` for a counter it could not
  read, and a missing marker, a missing or malformed verdict file (the
  wrapper killed with the worker — `systemd-oomd` takes every process in the
  pressured cgroup, and `OOMPolicy=continue` exempts nothing) or an
  unreadable counter is said on stderr with the run's own status passed
  through, never a silent zero. **Whichever fired first** is decided from
  the counters: the watchdog reads the scope's `pids.events` /
  `memory.events` from outside before it signals — once the scope empties
  they are gone — and a ceiling hit already on them exits 71, not 124.
- **Clause 8 — visible, and now enforced.** `--dry-run`'s `enforced:` line
  says, per rung, that the budget *is* applied: both ceilings exit 71 on the
  scope rung, the task ceiling alone on the `pids`-only rung, best-effort on
  rlimits, announced only where there is no mechanism. The floor note, the
  off switch and the no-mechanism note of rung 3 are said on **every**
  dispatch, so an operator piping stdout still hears them; a within-budget
  dispatch that trips no clamp stays silent on stderr, the way the timeout is
  silent until it fires.

### Amendment, 2026-09-19 — what building #209 settled for the suite

#209 put every suite under the budget as clause 3 anticipated. Five things
were left to it and are decided here; the clauses stand as written.

- **One derivation, reached by sourcing.** The kit's test harness
  (`tests/lib.sh`) takes the budget from `scripts/agent-dispatch.sh` itself:
  the dispatcher detects being sourced (the resolver's own test —
  `ZSH_EVAL_CONTEXT`, then `$0`), defines its budget prefix and returns
  before the dispatch proper. A copy of the arithmetic in the test harness, or a
  third shared file both would source, were the alternatives; the seam adds
  nothing to the manifest and cannot drift from what a worker gets.
- **A suite is inside a budget the way a nested dispatch is (clause 7).**
  The test harness re-executes the suite inside the budget with
  `AGENT_SUITE_BUDGET=applied: …` in its environment, and the second sourcing
  carries on. That marker is the recursion bound. Inside a dispatched worker
  (`AGENT_DISPATCH_BUDGET_TASKS` set) the test harness opens nothing: a scope from
  inside a scope is a sibling, and a suite's scope is never a backstop for
  the dispatches it runs — the dispatch suite's runaways are bounded by their
  own dispatch, exactly as clause 7 says. The outer boundary is not only a
  dispatch: a suite started inside a cgroup that already bounds it — an
  operator's own `systemd-run --user --scope`, whose `pids.max` is the
  tightest on the path or whose `pids.max` / `memory.max` the derived
  ceilings would exceed — runs in place under that cgroup's ceilings and
  says which, because the sibling the ladder would open escapes the
  operator's cap with larger numbers and blames the host for being small.
  The root cgroup is every scope's ancestor and never counts as that
  boundary. A run that lost the marker inside a suite's own scope is
  refused outright: the scope's name is the second recursion bound.
- **The policy is the kit's own.** The suite derives under
  `scripts/agents.kit.config.sh` (ADR-0003's never-shipped twin), never the
  environment's `$AGENTS_CONFIG`: a developer's environment does not decide
  the ceiling a test runs under. The file sets none of the six variables —
  the defaults stand for the suite too — and is where a tighter suite budget
  would go.
- **The clamps were re-measured against the suite and stand.** On the
  incident's host (2 vCPU / 3.7 GiB, `TasksMax` 10008) the derived budget is
  2502 tasks and about 1 GiB. Each suite run once in a scope of its own,
  `pids.peak` / `memory.peak` read before the scope emptied: the largest
  task peak is 44 (the dispatch suite; its runaways run in sibling scopes
  of their own, as a worker's do) and the largest memory peak 35 MiB (the
  adoption demo) — without node, which the four docs-gate suites add on
  CI and which was not measured: node was absent on the measuring host.
  Nothing measured reaches the floors, let alone the ceilings; nothing in
  clause 3 is re-decided.
- **Off is loud, and disabling is the outermost run's.** `AGENT_SUITE_BUDGET=off`
  runs a suite as before #209 and says so on stderr; any other value is
  refused, so a typo cannot read as "inside".
