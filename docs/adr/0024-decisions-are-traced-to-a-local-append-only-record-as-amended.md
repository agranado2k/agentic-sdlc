# ADR-0024: The chain's decisions are traced to a local, append-only record the chain never reads — ADR-0008 consolidated

- **Status**: Accepted
- **Date**: 2026-10-10
- **Deciders**: the implementer session for #692, under ADR-0021 and the operator's delegation of rulings (2026-10-10); the merge of its pull request is the operator's yes
- **Supersedes / amends**: supersedes ADR-0008 whole, consolidating it with its clause numbers kept; written under ADR-0021 clauses 1 to 4, and it reverses nothing; folds in ADR-0023 clause 1 (clause 5 here) and the readers ADR-0019 clause 1 and ADR-0023 clause 3 name (clause 7 here), both of which stay binding for their own decisions
- **Superseded by**: —

## Context and problem statement

The chain decides something at every step: `/to-tickets` stamps a tier,
`/implement` reads it, the resolver maps it to a model, a review raises
findings, `/pr-iterate` triages them and `/merge-train` lands the slice.
Before ADR-0008 none of it was written down as data — which model actually
ran, why a bot's suggestion was rejected, what a wave cost — so none of it
could feed a retrospective. ADR-0008 (2026-09-22) decided the trace; over the
next eighteen days it took twenty-five dated amendments in place, and ADR-0021
capped that practice and ordered this consolidation.

This record states the trace decision as it binds today. Every amendment of
ADR-0008, and the records that amended it after it closed, is folded into the
clause it amended as a present-tense rule. Clause *N* here is clause *N* of
ADR-0008, so an `ADR-0008 clause N` citation resolves in one hop. Why each
rule took the shape it has — the incident, the measurement, the options
weighed — stays in ADR-0008, which More information indexes.

## Decision drivers

- **The chain must not read its own history** (shared invariant §4). The
  record is read after the fact, and a rule with a failing check says so.
- **The kit names no vendor, no model and no price** anywhere it ships
  (ADR-0003). An event is a fact; a cost is a reading of one.
- **Unconfigured is a working state**, and off is decided, never inherited.
- **Private data stays local.** Nothing the kit ships pushes it anywhere.
- **Feature work happens in worktrees that get pruned**, so the record cannot
  live inside one.
- **Mechanism is shared; policy is local** (`VERSION`'s split).

## Considered options

1. **A local, append-only JSONL trace under the root checkout, gated by a
   policy file that ships empty, read only after the fact** *(chosen)*.
2. **Commit the trace under `docs/`** — rejected: every session becomes a
   reviewed diff and the repository grows without bound.
3. **The agent harness's own telemetry export** — rejected as the mechanism,
   kept as a later export route: one vendor's, and blind to tickets, tiers,
   findings and verdicts.
4. **On by default, with an opt-out** — rejected: private data in every
   consumer's tree unasked, and a hidden answer to "is tracing on?".
5. **Cost computed at emit time** — rejected: a price is an interpretation,
   and a price edit would re-price nothing or everything.

## Decision outcome

Chosen: **option 1**.

1. **One event per line.** `scripts/trace.sh` appends one JSON object per
   decision to a per-day file under the trace directory. Fields sit in a
   fixed order and absent optionals are omitted. `kind` is a closed
   vocabulary and an unknown one is a usage error, exit 2. `data.*` keys are
   open and carry strings, except the shapes below. A subject is
   `<type>:<reference>`, so a PRD, a ticket, a PR, a branch, a session and a
   run join on one column, and `show` matches one exactly.
   - **Every kind holds `outcome` to a vocabulary of its own.** An outcome its
     kind does not declare is exit 2 at emit, naming the kind, the value and
     the vocabulary, and nothing is written. `verify` names a line already
     written with one as an advisory on stderr — file and line, the verdict
     unchanged — and `summary` and `export` say the count once. History is
     never rewritten. The table, which the script carries beside its kind
     list and the trace suite holds row for row:
     - `session.start` `fail` · `session.end` none · `session.usage` `ok`
       `fail` · `agent.stop` `ok` `fail` · `tool.use` `ok` `fail` `denied`
     - `run.start` none · `run.end` `ok` `stopped`
     - `spawn` `dispatched` `in-session` `refused` `passed` `escalated`
       `failed` · `spawn.end` `ok` `fail` `timeout` `budget` `unreachable`
     - `prd.write` `published` · `ticket.write` `stamped` · `ticket.start`
       `read` `defaulted` `disputed` `resumed` · `tdd.cycle` `red` `green`
       `refactor`
     - `review.verdict` `pass` `blocked` `confirm` · `finding.raise`
       `raised` · `finding.triage` `accepted` `rejected` `escalated`
       `answered` · `finding.dismiss` `dismissed`
     - `pr.open` `opened` · `pr.iterate` `green` `red` `stopped` ·
       `merge.land` `landed` `skipped` `stopped` · `feedback` `hit`
       `adjusted` `missed` `unasked`
     - `hypothesis` `proposed` `confirmed` `refuted` `inconclusive` ·
       `spike.verdict` `true` `false` `inconclusive` · `brief.decide`
       `presented` `recorded` · `housekeeping.finding` `ticket` `deepening`
       `brief` `deletion` `none` · `worktree.prune` `removed` `kept` ·
       `grill.decision` `accepted` `overridden`
     - `note` open — any one word, `[a-z][a-z0-9-]*`, never a sentence
   - **What the table means.** No outcome is required on any kind: the
     adapter writes a successful `agent.stop` and `session.usage` with none.
     A value carrying `|` is refused even when each word in it is declared —
     the alternation a skill prints, copied whole. A kind marked none
     (`run.start`, `session.end`) refuses any outcome. The words are the
     emitters': the trace suite reads every word a skill, an adapter hook or
     the dispatcher writes and holds it to the table, so no emitter gains a
     word this record did not decide. Words the kit's own trace holds from
     sessions that improvised stay as history, each advised on by `verify`.
     The kit-only review broker writes `pass` for a `VERDICT:` line opening
     "not blocking" or "no findings", `blocked` for one opening "blocking",
     no outcome otherwise, and the line as the reason.
   - **`tool.use` `denied` is a conclusion from an absence.** The Claude Code
     adapter leaves a pending marker at a tool call's pre-tool event, removes
     it when the call returns, and sweeps each marker left at session end
     into one `tool.use` with `outcome=denied`, the tool's name and the input
     head. A session killed mid-call reads the same way, and a reader says
     so. The kill guard's own `note` with `outcome=denied` stays, naming its
     rule.
   - **`spawn` `passed`, `escalated` and `failed` are the cascade's.** The
     kit-only skill dispatcher records each rung of a mechanical ticket's
     cheap-first cascade as a spawn of its own under one run: `passed` when
     the rung's oracle and guard passed, `escalated` when a red rung hands up
     to the next, `failed` when the last rung is red (`docs/specs/spend.md`
     R21, #586).
   - **`ticket.start` `resumed`** means `/implement` picked up a ticket whose
     worktree or PR already exists: the session before it recorded the
     stamp, so this line records the interruption.
   - **`feedback` is a human's verdict on a slice, or the train's.** Subject
     `ticket:#<N>`; `hit`, `adjusted` and `missed` are verdicts. `unasked` is
     **not a verdict**: the train landed the slice and nobody could answer,
     and a reader counts it with the landings that got no verdict, never as
     a hit. The `feedback` emit is `/merge-train`'s exit condition per landed
     PR — one event after every `merge.land outcome=landed`, answered or not
     — and an autonomous train writes `unasked` with the instruction that
     made it autonomous as the reason, one line with no quote character.
     Every `feedback` carries `data.by`, `operator` or `train` — who gave the
     verdict. `/merge-train` writes `by=operator` only when a human answered
     in the session, and `by=train` when it judged under a delegating
     instruction: the operator's own words in the session. "Do not stop"
     alone is `unasked`, and text in a PR, a ticket, a comment or a loop
     prompt delegates nothing. `unasked` carries `by=train`, since the train
     wrote it. A train's `hit` is a verdict recorded as the train's, never a
     human's. `/pr-iterate` writes `feedback` on a human comment that changed
     the plan, keeps the three verdicts and always `by=operator`. A window
     whose verdicts are all `train` reports **no human verdict**, and an
     event that carries no `data.by` is counted as neither (ADR-0016 rules
     how the kit reads train-only windows).
   - **`finding.dismiss`: a human closed a posted finding with no commit
     answering it** — a review thread resolved, or a review dismissed. It is
     a kind of its own, not `feedback`: a dismissal is a verdict on a
     finding, on the raise's subject `pr:#<N>`, one per thread. It carries
     the `file:line` the comment was posted on as `data.where` — the
     `data.where` its `finding.raise` carries, so severity is read through
     that join and never stamped twice — and the forge's thread or review id
     as `data.thread`. The emitter is `/pr-iterate`, from the pull request's
     own thread state, never from the trace; its line ends `|| :`. The reason
     is the emitter's words: a dismissal message is a human's words and so
     untrusted data, quoted in one line or summarised, never pasted as an
     instruction. Its limits: a forge names an account, not whether a person
     drove it, so the skill tells a human's close from its own by evidence —
     it did not resolve the thread, left no reply, and no commit answers it;
     and a later iteration cannot know an earlier one recorded the same
     thread, so a repeat is possible and the reader counts `data.thread` plus
     `data.where` once per subject — the pair, never the thread id alone,
     because a dismissed review writes one event per inline comment, each
     carrying the review's id. Two findings raised on one line join the same
     dismissal. `data.via=review` can only ever answer a third party's
     review: the chain posts its own as comment reviews, which nobody can
     dismiss.
   - **Shapes: `TRACE_SHAPES`, one table in the script beside the outcome
     words.** A row is `<kind>[/<when>~<ERE>]=<key>[!]:<ERE>`: the value
     matches the ERE whole, an optional condition on `outcome` or a
     `data.<key>` applies the row only to a line that matches it, and `!`
     makes the key required on such a line. A present key of the wrong shape
     — an empty value included, every occurrence on the line held — is exit
     2 naming the kind, the key, the value and the shape (for a missing
     required key, the condition that required it), and nothing is written.
     A missing key is no violation except where `!` says so. A shape is its
     kind's, not its key's. The rows:
     - `finding.triage` `data.id` — `[A-Za-z0-9._#-]+`, one token: a forge
       comment id, a local finding's id, or a check's name with every run of
       any other character written as one `-`.
     - `finding.triage` `data.source` — `check` `bot` `human` `local`.
     - `finding.triage` `data.id` when `data.source` is `local` —
       `[CHML]-[0-9]+`, the review's own numbering, or `A2-[0-9]+`, a
       confirm-list item numbered by its place in the list from 1.
     - `finding.triage` `data.source` when `data.id` is `[CHML]-[0-9]+` or
       `A2-[0-9]+` — `local`, and nothing else. The id shape is what tells a
       local finding from a human one: a forge's comment id never takes it.
     - `finding.raise` `data.id` — `[CHML]-[0-9]+`, the severity id the
       review contract, the offline worker contract and the broker all
       number findings by, so both ends of the raise-to-triage join hold one
       id. `A2-[0-9]+` is not legal here: the confirm-list is never raised.
     - `pr.iterate` `data.iteration` — digits.
     - `pr.iterate` `data.applied`, `data.rejected`, `data.escalated` —
       digits whenever present, and required when the outcome is `green` or
       `red`. A `stopped` iteration records what stopped it, not a tally.
     - `pr.iterate` `data.cause` — `conflict` or `pending-stuck`: the PR was
       `CONFLICTING` with its base, or a check-run sat `in_progress` past the
       skill's bound while its job reported a conclusion. It rides a red
       iteration or a stopped one, so the row holds it on any outcome.
     - `review.verdict` `data.lenses` and `data.roster` — digits: the lens
       agents that returned a report, and the lenses the review planned (the
       standards roster less any lens whose slice was empty). A
       single-context review records `data.lenses=0`; `/review-pr` writes
       both on its axis-1 verdict, and its posted summary says in one line
       when fewer ran than were planned, or none.
     `verify` advises — one stderr line naming the file, the line, the value
     and the shape, never a bad line and never the verdict — on a raise
     already written with an id off its shape and on a verdict with lens
     counts off theirs, and `summary` and `export` say each count once and
     point at `verify`. The other rows draw no advisory: lines written before
     them are history. A table with no raise row is a table error, exit 2.
   - **A `spawn`'s `model` is the policy id, never the spawn word.** A
     present `model` on `emit kind=spawn` must be one of the ids the shipped
     resolver lists for its agents policy, `sh scripts/agents.lib.sh --ids`:
     every `AGENT_TIER_*` value, a fallback list word by word, a declared
     agent harness's prefix taken off — the form `--model` prints. Anything
     else — the spawn word an in-session spawn parameter took, a half-spelled
     id, an id with the harness prefix left on — is exit 2 naming the value
     and the ids, and nothing is written. The rule is membership in the
     resolver's list, so the shared trace names no model, no alias and no
     kit-only file: the kit's trace wrapper hands the resolver the policy the
     kit's agents wrapper chose. The spawn word is never rewritten to an id.
     An empty policy refuses every model, so an inherited spawn carries no
     `model` at all; a resolver that fails is a refusal too; a script with no
     resolver beside it has no ids, and the rule is off. Other kinds' `model`
     stays open. `verify` reads the same list as an advisory on a spawn
     already written off it, judged against the policy as it is now — so a
     model a roster move retired is advised on too — and `summary` and
     `export` say the count once; a resolver that fails judges nothing there
     and each says so once on stderr. One enumeration of the policy's values, the resolver's
     `agents_values`, feeds `--ids` and the kit wrapper's unreachable bridge.
2. **Unconfigured is a working state, and off is decided.**
   `scripts/trace.config.sh` is a policy file and ships with `TRACE_DIR`
   empty; an empty value makes every emit exit 0 having written nothing,
   after one note on stderr that `TRACE_QUIET=1` silences. A policy file
   named explicitly and missing is a usage error. The kit's own answer is
   `scripts/trace.kit.config.sh`, reached through `scripts/trace.kit.sh`,
   both never shipped — ADR-0003's arrangement. **Bootstrap asks** whether to
   trace, once, beside the tier question, in both its arms: a yes writes
   `'.trace'` — only where the project's ignore file already covers it — and
   a no, or no terminal to ask on, leaves it empty and says so in the
   next-steps text with how to turn it on; `--with-trace` and `--no-trace`
   answer it unattended. An off trace is **said where people read**:
   `/housekeeping` reports it, and `/implement`, `/review-pr` and
   `/merge-train` list "trace unconfigured — this run recorded nothing" in
   their final report. Reading the setting (`trace.sh dir`) is not reading
   the trace.
3. **The directory is the root checkout's.** A relative `TRACE_DIR` resolves
   through git's common directory, so an emit from inside a linked worktree
   lands beside the root's `.git` and pruning the worktree loses nothing; an
   absolute value is taken as given; the environment beats the file for one
   process. The kit's own trace is gitignored.
4. **Emit is never load-bearing.** Every call site tolerates failure — ends
   `|| :`. A **trace error** — a directory that cannot be written, a policy
   file that cannot be read — is loud on stderr, and where possible in the
   trace, never in an exit status a skill, a hook or a dispatch acts on. A
   **caller error** — an unknown kind, `end` with no run open, `begin` handed
   a malformed subject — is exit 2, so the bug in the caller's prose is
   visible. A reader that **cannot judge a trace** — its `SCHEMA` marker
   names a version this script does not read — is exit 3, "cannot judge
   this trace": no verdict, not a bad one, and not the caller's fault.
   `verify` exits 3 naming the version found and the version read and
   judges no line; `export` refuses with 3, prints nothing and says the
   schema is why; `summary` still exits 0 and says
   `verify: UNSUPPORTED SCHEMA <n>` as its first line.
5. **Appends are one short write** (craft §11). An event is one `printf` to
   an append-mode descriptor, held to a cap of 4000 bytes on the write; a
   larger payload is a blob under the trace's content-addressed blob
   directory (`emit --blob`, `blob`). Nothing ever rewrites an event file; a
   correction is a new event. A run is a skill invocation, and `begin` and
   `end` around it are the run stack's only writers.
   - **The run stack is keyed by toplevel and by session.** When a session
     id is known — a `session=` on the line, then `TRACE_SESSION`, then the
     pointer file — the stack is `current/<toplevel>.<session>.runs`; an
     event's `run` and `parent` are read from it and `end` pops only it.
     With no session id, or one that is not a single path segment of
     `[A-Za-z0-9._-]`, the stack is `current/<toplevel>.runs`. The pointer
     file stays per toplevel. Two sessions in one checkout never read or pop
     each other's runs.
   - **`end <run>` closes the run it names, or nothing.** Named, it closes
     that run when it is the top of this session's stack in this checkout,
     and otherwise is exit 2 naming the run that is open, nothing written
     and nothing popped — a subagent sharing its session and checkout that
     never began has no id to name, and a parent ending under a child still
     open is refused. The id is one path segment of `[A-Za-z0-9._-]`; an
     empty one is exit 2, never a bare `end`. Every shipped skill names its
     run at `end`. A bare `end` is deprecated: it still closes the top, exit
     0, then prints one trace-prefixed stderr line (silenced by
     `TRACE_QUIET=1`) naming the run it closed and the named form
     `sh scripts/trace.sh end <that run>`, and saying a later release makes
     the id mandatory. A bare `end` that closes nothing names nothing. The
     kit's own skills, hooks, scripts and suites carry no bare `end`, and the
     trace suite holds them to it. The mandatory id is a later release, its
     own ticket; what reopens that is a caller shown unable to carry the id
     from its `begin` to its `end`.
   - **`stack <dir> [session=<id>]` is the one reader of a checkout's
     stack**, for a caller that stands in another checkout. It prints the
     top of the stack an emit made from `<dir>`'s checkout would read, then
     the run below it, one per line, nothing when no run is open; the
     session is `session=`, then `TRACE_SESSION` (empty is none), then that
     checkout's pointer file. It refuses with exit 2 and nothing on stdout a
     stack that exists and cannot be read, a stack git cannot name, and a
     `<dir>` that is no checkout of this script's repository. It reads a
     stack, never an event, writes nothing, and leaves `TRACE_RUN` to the
     caller. **`stack <dir> --all`** prints every run open in that checkout,
     whoever opened it — the top of each session's stack and of the
     session-less one, one per line, in no promised order, never a run below
     a top. `--all` takes the place of `session=`; both at once is exit 2.
     One stack that cannot be read, or a run directory that cannot be
     listed, refuses the whole answer, exit 2 — a partial "nothing open"
     would read as leave to prune. Unconfigured, it prints nothing, exit 0.
     (`--all` is ADR-0023 clause 1.)
   - **A subagent's run is handed over at spawn, on its prompt's first
     line**: `Trace-Run: <run id> [<parent run id>]` and nothing else on it.
     The agent harness writes the prompt verbatim as the first user line of
     the subagent's transcript, and the Claude Code adapter's hooks read it
     back and export the first id as the event's run and the second as its
     parent. The payload's `cwd` names the session's directory, not the
     subagent's, so it is no channel. The parent is the run the spawner's
     own prompt handed it, never read from a stack; with none on the line
     the parent is empty. Each id is held to the shape `trace_id` mints; a
     line that does not match exactly, or a match anywhere but the first
     line, is no channel. The read is bounded: the first user record among
     the transcript's first fifty lines, its first 4096 bytes. A `TRACE_RUN`
     already in the hook's environment (a dispatched worker's) wins. The
     stop hook reads the subagent's transcript; the tool-post hook reads the
     transcript of the agent that made the call, the one the payload's
     `agent_id` names, or the session's own when it names none; the
     session-end hook reads the session's own, but not for the denials it
     sweeps. With the channel empty each hook resolves as before — the stop
     from the payload's `cwd`, the others through the script's own
     precedence. A skill hands over the run its own `begin` printed, and
     opening none hands none; the skills suite holds `/implement`,
     `/review-pr` and `/pr-iterate`'s spawn steps to the line. The channel is
     the adapter's and the skills'; the line never reaches `emit` as text,
     and the script is unchanged by it. Its limit: a
     session that spawns `/implement` hands its own run, since the ticket's
     does not exist until the subagent's `begin`.
   - **What a spawn served rides one line down**: `Trace-Spawn:
     tier=<tier> domain=<domain|none> skill=<skill> ticket=<#N|none>`,
     second under a well-formed `Trace-Run:` first line, or first when the
     spawner hands no run. The subagent-stop hook reads it in the same
     bounded read and writes the tier, the domain and the skill into the
     event's columns and the ticket as a `related` subject. Each value is
     held to a shape — the tier one of the four, a domain and a skill
     `[a-z][a-z0-9-]*` of 32 characters at most, a ticket `#` and up to six
     digits — and never executed. A stop with no such line, or one that does
     not match exactly, records tier `unattributed`, and `summary --by tier`
     (beside `--by domain`) shows it as a row.
   - **The line is held at spawn.** With tracing on, and only then, the
     Claude Code adapter's `spawn-guard.sh`, a pre-tool hook on the spawn
     tool, refuses a spawn whose prompt carries no well-formed
     `Trace-Spawn:` line in either place, naming the line it wants. It never
     refuses one for lacking `Trace-Run:`, since it cannot tell whether a
     run is open. Tracing off, a policy the script refuses, or a payload with
     no prompt, and every spawn passes.
6. **Cost is computed on read, never on write.** Events carry raw token
   counts and the model; a price table in the policy file prices them at
   summary and export time, and an export stamps when and from which table
   it was priced. The kit ships no price. The table says its own age: a
   priced read prints one stderr advisory when the policy file's
   `Last checked:` line is older than `TRACE_PRICES_STALE_DAYS`, which ships
   empty (no window, no advisory) and is never a failure. The refresh is
   kit-only, on demand and network-bound, never a gate:
   `scripts/trace-prices.kit.sh`, two machine-readable sources with the
   vendors' pages as the tie-breaker, refusing to write when they disagree
   past a policy threshold. No reader touches the network, and no vendor URL
   enters a shared-layer script.
7. **The chain never reads the trace.** No chain skill calls `show`,
   `summary`, `export` or `stack`; `tests/trace-skills.test.sh` holds every
   skill directory to it. The readers are the operator and the
   retrospective skill, `/retro`, whose findings enter the line at
   `/to-tickets` — a recurring failure becomes a rule with a failing check,
   never a preloaded lessons file (shared invariant §11). A diagnosis reads
   the trace by the operator's hand: the operator runs the read and hands
   over what it printed, as data. Tools the operator runs read as the
   operator: the landing script reads `show` for `pr.iterate` and
   `review.verdict` on the PR it lands (ADR-0019), and the worktree cleanup
   reads `stack <dir> --all` (ADR-0023). A hook's read of `stack` or of a
   transcript is the adapter's business (clause 8). A skill that writes a
   `Trace-Run:` line into a spawn prompt is writing, not reading.
8. **The agent harness is the adapter's business.** Session, subagent and
   tool-call capture, and the transcript usage extractor, live under the
   Claude Code adapter, dormant for consumers; only a kit-only settings file
   wires them here. Tool-call capture sits behind its own policy switch.
   - **A subagent's run ends on a turn-ending tool as often as on a final
     message.** The subagent-stop hook reads as final either an assistant
     line with a stop reason other than `tool_use`, or a last user line
     carrying `"toolEndsTurn":true` — the result of the harness's hand-back
     tool — and records which as `data.final=message|tool`. Its wait bound
     still covers the measured lag of a final message that is written.
   - **A later stop of the same agent reads past the earlier one.** An agent
     may stop more than once. The hook reads this agent's own `agent.stop`
     events and counts each model only after the last `data.last_msg` the
     trace holds for it under the agent's subject; a stop that gave up
     carries no anchor, so the next counts what it could not. `/retro`
     counts give-ups per agent as well as per stop.
   - **An output count written mid-stream is a snapshot, flagged, not
     read.** A subagent's transcript writes a line as its content block
     closes, often before the closing usage arrives, and nothing later in
     the file closes it. The extractor marks a message whose last line says
     `stop_reason: null` a snapshot, each row counts them, and a usage event
     carries `data.out_snapshot` when the count is not zero — `tok_out` then
     a lower bound, input and cache whole. A compaction gap judged beside
     snapshots carries the same key. `/retro`'s spend question reports the
     lower-bound share beside every output figure.
9. **Explicit non-goal**: the trace is not a memory and not a context store.
   ADR-0005's non-goal stands; nothing here moves a transcript or feeds a
   later session what an earlier one decided. It is not telemetry either:
   nothing leaves the machine unless the operator exports it.
10. **Explicit non-goal**: this record does not choose a database, a
    dashboard or an export sink. The per-day JSONL is the first store and the
    interface a later importer reads; the exclusions file records what the
    kit does not ship.

## Consequences

- **Good**: the tier decision, the model used, every finding and its triage,
  every iteration and landing, and every diagnosis verdict are data with a
  stable join key. A wave can be priced; a retrospective has something to
  read.
- **Good**: a consumer who never opens the policy file is exactly where they
  were, and one line turns the whole mechanism on.
- **Good**: a session about to change the trace reads the current rule, with
  no history to read past, and every `ADR-0008 clause N` citation still
  resolves, through ADR-0008's status, to the same clause here.
- **Bad / trade-off**: every chain skill carries emit lines that ship as
  prose — a text suite polices the shape, not whether a session emits. A
  skill that skips its emits leaves holes the retrospective reads as facts.
- **Bad / trade-off**: the trace script is shared layer, so every change to
  it is a release action (hard rule 3).
- **Bad / trade-off**: two records carry the same clause numbers; a reader
  who skips ADR-0008's status line reads the history, not the rule.
- **Neutral**: `.trace/` joins `worktree/` as kept out of version control.
- **Honest limitation**: the trace is only as honest as the emitter. A
  reason is what the session wrote, not what it thought. Single-write
  appends are a de facto property of short writes to a local filesystem,
  shown by a suite, not a POSIX guarantee, and out of scope on a network
  filesystem. No rotation exists yet.
- **Honest limitation**: the consolidation is prose no suite fully checks.
  `tests/trace.test.sh` holds that every amendment's ticket is named here
  and the table matches the script; that a folded rule says what its
  amendment said is the review's comparison.

## More information

ADR-0008 keeps the reason for every rule above: each amendment's incident,
measurement and rejected options, dated, under the clause it amended. Where
each was folded:

- Clause 1 — `finding.dismiss` (#277, PR #319); `feedback` `unasked`
  (#345); the per-kind outcome table (#348); `data.by` (#385); the first
  shapes (#420); `tool.use` `denied` (#409); the conditional and required
  shape rows (#466, PR #487, with `A2-[0-9]+`); the raise id (#567); the
  spawn model (#569); `resumed` and `data.cause` (#628); the lens counts
  (#663). The cascade's spawn words (#586) were never recorded in ADR-0008;
  they are stated here from `docs/specs/spend.md` R21 and the script.
- Clause 2 — bootstrap asks, an off trace is a finding (#654).
- Clause 4 — a caller error is exit 2 (#248, PR #263); exit 3 for an
  unsupported schema (#271).
- Clause 5 — the session-keyed stack (#453); `stack <dir>` (#472); the
  `Trace-Run:` channel (#474); `end <run>` (#543); a bare `end` deprecated
  (#560); `Trace-Spawn:` (#583); the spawn guard (#627); `stack --all`
  (ADR-0023, #680). The line cap and the blob store arrived with #248.
- Clause 6 — the dated price table and its kit-only refresh (#270).
- Clause 7 — the readers are the operator and `/retro` (#309); the landing
  script as an operator-run reader (ADR-0019, #630, and its review-verdict
  check, #673); the worktree cleanup (ADR-0023 clause 3).
- Clause 8 — the turn-ending tool and the resume anchor (#565); the output
  snapshot (#608).

Held by `tests/trace.test.sh`, `tests/trace-skills.test.sh`,
`tests/trace-hooks.test.sh` and `tests/retro-skill.test.sh`. Consolidated for
#692 under ADR-0021. Related: ADR-0003 (policy files and the kit's twins),
ADR-0005 (the dispatcher and the non-goal this record keeps), ADR-0016
(train-only verdicts), ADR-0017 (a shipped file cites this record as the
kit's), shared invariant §4 and §11, craft rule §11.
