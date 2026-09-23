# ADR-0008: The chain's decisions are traced to a local, append-only record the chain never reads

- **Status**: Accepted
- **Date**: 2026-09-22
- **Deciders**: Arthur Granado (operator), at the planning session for PRD #237
- **Supersedes / amends**: — (leaves ADR-0005's "not a memory or a context store" non-goal intact, and is bound by it)
- **Superseded by**: —

## Context and problem statement

The chain decides something at every step and records almost none of it.
`/to-tickets` stamps a tier, `/implement` reads it, the resolver maps it to a
model, and nothing writes down which model actually ran — the resolver's own
unmapped-tier warning names that blindness. `/review-pr`'s seven sub-agents
resolve no tier at all. The two best-specified records the chain produces,
`/pr-iterate`'s iteration report (applied, rejected with a reason, escalated,
per finding) and `/merge-train`'s output, are printed to the operator and
discarded. Tokens and cost are never measured: ADR-0004's honest limitation
says the root manual's budget "is not derived from a token budget", and no
token has ever been counted here.

So the operator cannot answer what a wave cost, which model reviewed a PR,
why a bot's suggestion was rejected, or whether the `mechanical` tier keeps
producing PRs that need three iterations. None of it can become training
data, and none of it can feed a retrospective, because none of it exists as
data. The memory of decisions is prose at three levels — these records, the
diary, and issue and PR bodies — all human-parsed and joinable only by a
`Part of #N` line and a branch name.

## Decision drivers

- **The chain must not read its own history.** Shared invariant §4: a
  reviewer that has seen the author's narrative reviews the narrative. Any
  record of decisions has to be an artifact read after the fact, and a rule
  with a failing check has to say so.
- **The kit names no vendor, no model and no price**, anywhere it ships
  (ADR-0003). A cost is a reading of a token count against a table that rots
  on the vendor's schedule; an event is a fact.
- **Unconfigured is a working state.** The guards and the tiers both mean
  "inactive" when their policy file is empty; a consumer who never heard of
  a trace must get exactly what they have today — and the kit does not own
  a consumer's ignore file.
- **Private data stays local.** Findings, reasons, prompts and token counts in
  plain text are the root manual's trust-boundary material. Nothing the kit
  ships may push them anywhere.
- **Feature work happens in worktrees that get pruned.** A record kept inside
  a worktree dies with it.
- **Mechanism is shared; policy is local** (`VERSION`'s split). The writer,
  the reader and the vocabulary are one implementation every consumer gets
  verbatim; where the trace lives, whether tool calls are captured, and what
  a token costs are the consumer's lines to fill.

## Considered options

1. **A local, append-only JSONL trace under the root checkout, gated by a
   policy file that ships empty, read only after the fact** *(chosen)* — one
   shared script writes and reads it; skills and the dispatcher emit at their
   decision points; an agent-harness adapter records sessions, subagents and
   tool calls; a retrospective skill is the sanctioned reader.
2. **Commit the trace under `docs/`** — rejected: every session becomes a
   reviewed diff and the repository grows without bound; a gitignored
   directory is just as importable and invisible to the gate.
3. **The agent harness's own telemetry export** — rejected as the mechanism,
   kept as a later export route: it is one vendor's, it names that vendor in
   every line, and it knows nothing of tickets, tiers, findings or verdicts,
   which are the decisions this record is about.
4. **On by default, with an opt-out** — rejected: it writes private data into
   every consumer's tree unasked, the kit does not own their ignore file, and
   "is tracing on?" would have a hidden answer where `dir` printing nothing
   is an unambiguous one.
5. **Cost computed at emit time** — rejected: a price is an interpretation; a
   price edit would silently re-price nothing, or everything, depending on
   when it was made. Tokens and the model are written; cost is computed on
   read, and an export says which table priced it.

## Decision outcome

Chosen: **option 1**.

1. **One event per line.** `scripts/trace.sh` appends one JSON object per
   decision to a per-day file under the trace directory. Fields sit in a
   fixed order and absent optionals are omitted; `kind` is a closed
   vocabulary and an unknown one is a usage error, like an unknown tier;
   `data.*` keys are open and carry strings, like task domains. A subject is
   `<type>:<reference>` so a PRD, a ticket, a PR, a branch, a session and a
   run join on one column, and `show` matches one exactly.
2. **Unconfigured is a working state.** `scripts/trace.config.sh` is a policy
   file and ships with `TRACE_DIR` empty; an empty value makes every emit exit
   0 having written nothing, after one note on stderr that `TRACE_QUIET=1`
   silences. A policy file named explicitly and missing is a usage error. The
   kit's own answer is `scripts/trace.kit.config.sh`, reached through
   `scripts/trace.kit.sh`, both never shipped — the arrangement ADR-0003's
   amendment states as general, so the twin needs no record of its own; this
   record is about the trace.
3. **The directory is the root checkout's.** A relative `TRACE_DIR` resolves
   through git's common directory, so an emit from inside a linked worktree
   lands beside the root's `.git` and pruning the worktree loses nothing; an
   absolute value is taken as given; the environment beats the file for one
   process. The kit's own trace is gitignored.
4. **Emit is never load-bearing.** Every call site tolerates failure. A trace
   error is loud on stderr, and where possible in the trace, never in an exit
   status a skill, a hook or a dispatch acts on.
5. **Appends are one short write** (craft §11). An event is one `printf` to
   an append-mode descriptor; a cap on the line and a content-addressed blob
   directory for larger payloads arrive with #248. Nothing ever rewrites an
   event file; a correction is a new event.
6. **Cost is computed on read, never on write.** Events carry raw token
   counts and the model; a price table in the policy file prices them at
   summary and export time, and an export stamps when and from which table
   it was priced. The kit ships no price.
7. **The chain never reads the trace.** No chain skill calls `show`,
   `summary` or `export`; a text suite holds every one of them to it. The
   readers are the operator, `/diagnose`, and a retrospective skill whose
   findings enter the line at `/to-tickets` — a recurring failure becomes a
   rule with a failing check, never a preloaded lessons file (shared
   invariant §11).
8. **The agent harness is the adapter's business.** Session, subagent and
   tool-call capture, and the transcript usage extractor, live under the
   Claude Code adapter, dormant for consumers; only a kit-only settings file
   wires them here. Tool-call capture sits behind its own policy switch,
   because it is the largest source of lines and the least decision-bearing.
9. **Explicit non-goal**: the trace is not a memory and not a context store.
   ADR-0005's non-goal stands; nothing here moves a transcript or feeds a
   later session what an earlier one decided. It is not telemetry either:
   nothing leaves the machine unless the operator exports it.
10. **Explicit non-goal**: this record does not choose a database, a
    dashboard or an export sink. The per-day JSONL is the first store and the
    interface a later importer reads; the exclusions file records what the
    kit does not ship.

## Consequences

- **Good**: the tier decision, the model actually used, every review finding
  and its triage, every iteration and landing, and every diagnosis verdict
  become data with a stable join key. A wave can be priced; a ticket's trail
  can be read from one command; a retrospective has something to read.
- **Good**: a consumer who never opens the policy file is exactly where they
  were, and one who adds one line gets the whole mechanism.
- **Bad / trade-off**: every chain skill gains emit lines it has to carry, and
  they ship to consumers as prose — a text suite polices the shape, but not
  whether a session actually emits. A skill that skips its emits produces a
  trace with holes, and the retrospective sees the holes as facts.
- **Bad / trade-off**: the trace script is shared layer, so its first
  landing and every later change to it is a release action (root manual,
  hard rule 3) with a transcript re-capture; the wave's release ticket
  carries that.
- **Neutral**: `.trace/` joins `worktree/` as the second thing the kit
  keeps out of its own version control, for the same reason — it is local
  by design.
- **Honest limitation**: the trace is only as honest as the emitter. A
  reason field is what the session wrote, not what it thought; the full
  chain of thought stays in the agent harness's transcript, pointed at, not
  copied. Single-write appends are a de facto property of short writes to a
  local filesystem, demonstrated by a suite, not a POSIX guarantee, and out
  of scope on a network filesystem. No rotation exists yet; a housekeeping
  measurement of the directory's size is the follow-up.

## More information

- Design: PRD #237; the wave's tickets #246–#255. Implemented first in #247
  (this record, the script's `emit`, `show`, `verify` and `dir`, the policy
  file, the kit twin, the ignore rule and the glossary terms).
- Related: ADR-0003 (policy files ship empty; the kit's twin), ADR-0005 (the
  dispatcher, and the non-goal this record keeps), ADR-0004 (the line budget
  that was never a token budget), shared invariant §4 (fresh context) and
  §11 (the context budget), craft rule §11 (never truncate).
