# ADR-0008: The chain's decisions are traced to a local, append-only record the chain never reads

- **Status**: Accepted
- **Date**: 2026-09-22
- **Deciders**: Arthur Granado (operator), at the planning session for PRD #237
- **Supersedes / amends**: — (leaves ADR-0005's "not a memory or a context store" non-goal intact, and is bound by it)
- **Superseded by**: — (amended 2026-09-28: clause 4 governs an emit; a caller error in `begin` or `end` — a pop with nothing to pop, a malformed argument — is exit 2 like an unknown kind, and the call site still tolerates it. Decided at the `/pr-iterate` stop for #248, PR #263. Amended again 2026-09-28: a reader that cannot judge a trace — an unknown `SCHEMA` version — is exit 3, a third family beside the verdict and the caller error; see clause 4. Decided for #271. Amended 2026-09-30: clause 1's closed kind vocabulary gains `finding.dismiss`, a human closing a posted finding with no commit answering it, emitted by `/pr-iterate` on the subject of the `finding.raise` it answers — not carried on `feedback`. Decided at planner ticket #277, which resolves PRD #273's first open issue; the merge of its pull request is the operator's yes)

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
   *Amended 2026-09-30:* the vocabulary gains one kind, **`finding.dismiss`**
   — a human closed a posted finding with no commit answering it: a review
   thread resolved, or a review dismissed. The trace already held the
   session's own triage (`finding.triage`) and nothing of what a human did
   with the comments `/review-pr` posts, so the question "per severity, how
   often was a posted finding dismissed?" had a raise and no outcome to join
   it to. What was decided, and where it lands:
   - **A new kind, not `feedback`.** `feedback` is a human's verdict on a
     *slice* — subject `ticket:#<N>`, outcome `hit|adjusted|missed`, one per
     landing or re-cut. A dismissal is a human's verdict on a *finding* —
     subject `pr:#<N>`, one per thread. Carried on `feedback` it would sit on
     a subject the raise is not on, widen a three-word outcome with a fourth
     that means something else, and make every reader of `feedback` tell the
     two apart by a `data` key; and its emitter at landing, `/merge-train`,
     fetches no review thread. A closed vocabulary is where a distinction
     like that belongs, and widening it is this record's to decide — hence
     an amendment and not a line in a skill.
   - **The join is the subject and `data.where`.** The event sits on the
     raise's subject and carries the `file:line` the comment was posted on,
     which is the `data.where` its `finding.raise` carries; severity is read
     through that join and never stamped a second time. It cannot be the
     finding's id: a posted comment does not show one, by `/review-pr`'s own
     rule. `data.thread` carries the forge's id for the thread or review.
   - **The emitter is `/pr-iterate`, from what it fetched from the forge.**
     Clause 7 stands untouched: the skill learns of the dismissal from the
     pull request's own thread state, never from the trace. Clause 4 stands:
     the line ends `|| :`.
   - **The reason is the emitter's words** — what the snapshot showed. A
     dismissal message is a human's words and so untrusted data (root
     manual, agent trust boundary): quoted in one line, or summarised where
     it cannot be quoted safely, never pasted as an instruction.
   - **Honest limitations.** A forge names an account, not whether a person
     or an agent drove it; where the two share one, the skill tells a human's
     close from its own by evidence — it did not resolve the thread, left no
     reply on it, and no commit answers it. And because no iteration reads
     the trace, a later iteration cannot know an earlier one recorded the
     same thread: a repeat is possible, and the reader counts
     `data.thread` plus `data.where` once per subject — the pair, never
     the thread id alone, because a dismissed review writes one event per
     inline comment it carried and every one carries the review's id. Two
     findings raised on one line join to the same dismissal; the reader
     reports that as it finds it. And `data.via=review` can only ever
     answer a third party's review: this chain posts its own as comment
     reviews, which the forge lets nobody dismiss, so an event on that path
     has no `/review-pr` raise to join.
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
   *Amended 2026-09-28:* this clause is about a trace error — a directory
   that cannot be written, a policy file that cannot be read. A **caller
   error** is a different thing: `end` with no run open, or `begin` handed a
   malformed subject, is a bug in the skill's prose, and it reports as exit 2
   the way an unknown kind always has, so the bug is visible. Every call site
   still ends in `|| :`, so no skill's outcome changes either way; what
   changes is that the operator can see it.
   *Amended 2026-09-28 (#271):* a **third** state joins those two, and it is a
   reader's rather than an emitter's — a trace whose `SCHEMA` marker names a
   version this script does not read. It is neither: the command was well
   formed and the directory was readable, so nothing failed; the reader simply
   **cannot judge these lines**. By meaning it joins the family the docs gate
   spells as its own 2 — "could not run" (`scripts/check.sh`: 0 clean, 1
   violations, 2 could not run) — because the answer is *no verdict*, not *a
   bad verdict*. It may not borrow that family's NUMBER here, because 2 in
   this script is the caller's own error, and the two ask opposite things of
   whoever reads them: a caller told 2 fixes its command, where a caller told
   this must update the shared layer and touch nothing about the call. So the
   contract widens by one code rather than overloading one, and it is **exit
   3, "cannot judge this trace"**: `verify` exits 3, names the version it
   found and the version it reads, and judges no line; `export` refuses with
   3, prints nothing, and says on stderr that the schema — not a bad line — is
   why; `summary` still exits 0, because a glance is not an import, and says
   `verify: UNSUPPORTED SCHEMA <n>` as its own first line where a damaged
   trace gets a bad-line count. Numbering above 2 for "did not happen, and not
   because of you" is a practice `scripts/agent-dispatch.sh` already keeps (3,
   4, 69 beside its 2); the number's meaning there is its own. Escalated by
   #263's review (M-3), decided for #271.
5. **Appends are one short write** (craft §11). An event is one `printf` to
   an append-mode descriptor; a cap on the line and a content-addressed blob
   directory for larger payloads arrive with #248. Nothing ever rewrites an
   event file; a correction is a new event.
6. **Cost is computed on read, never on write.** Events carry raw token
   counts and the model; a price table in the policy file prices them at
   summary and export time, and an export stamps when and from which table
   it was priced. The kit ships no price.
   *Amended 2026-09-28 (#270):* the cost of pricing on read is a table with a
   date on it, and a dated claim rots quietly. So the table says its own age —
   a priced read prints one advisory on stderr when the policy file's
   `Last checked:` line is older than `TRACE_PRICES_STALE_DAYS`, which ships
   empty (no window, no advisory) and is never a failure — and the refresh
   that answers it is **kit-only**, on demand and network-bound, never a
   gate: `scripts/trace-prices.kit.sh`, two machine-readable sources with the
   vendors' pages as the human tie-breaker, refusing to write when the two
   disagree past a policy threshold. This is not the rejected "fetch prices at
   query time": no reader ever touches the network, and no vendor URL enters a
   shared-layer script.
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
- Amended for ticket #277 (PR #319): the `finding.dismiss` kind, its emit
  in `/pr-iterate`, and the suites that hold both.
- Related: ADR-0003 (policy files ship empty; the kit's twin), ADR-0005 (the
  dispatcher, and the non-goal this record keeps), ADR-0004 (the line budget
  that was never a token budget), shared invariant §4 (fresh context) and
  §11 (the context budget), craft rule §11 (never truncate).
