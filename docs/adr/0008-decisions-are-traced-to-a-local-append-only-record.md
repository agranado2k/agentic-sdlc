# ADR-0008: The chain's decisions are traced to a local, append-only record the chain never reads

- **Status**: Accepted
- **Date**: 2026-09-22
- **Deciders**: Arthur Granado (operator), at the planning session for PRD #237
- **Supersedes / amends**: — (leaves ADR-0005's "not a memory or a context store" non-goal intact, and is bound by it)
- **Superseded by**: — (amended 2026-09-28: clause 4 governs an emit; a caller error in `begin` or `end` — a pop with nothing to pop, a malformed argument — is exit 2 like an unknown kind, and the call site still tolerates it. Decided at the `/pr-iterate` stop for #248, PR #263. Amended again 2026-09-28: a reader that cannot judge a trace — an unknown `SCHEMA` version — is exit 3, a third family beside the verdict and the caller error; see clause 4. Decided for #271. Amended 2026-09-30: clause 7's readers are the operator and the retrospective skill, and a diagnosis reads the trace by the operator's hand; see clause 7. Decided for #309. Amended 2026-09-30: clause 1's closed kind vocabulary gains `finding.dismiss`, a human closing a posted finding with no commit answering it, emitted by `/pr-iterate` on the subject of the `finding.raise` it answers — not carried on `feedback`. Decided at planner ticket #277, which resolves PRD #273's first open issue; the merge of its pull request is the operator's yes. Amended 2026-10-01: `feedback`'s outcome vocabulary gains `unasked` — the train nobody could answer — and the emit is `/merge-train`'s exit condition per landed PR; see clause 1. Decided for #345, from the retrospective of 2026-10-01, finding F2. Amended 2026-10-01: every kind holds `outcome` to a vocabulary of its own, refused at emit and advised on by `verify`; see clause 1. Decided for #348, from the same retrospective, finding F8. Amended 2026-10-01: `feedback` carries `data.by=operator|train` — who gave the verdict, a human in the session or a train under a delegating instruction; see clause 1. Decided for #385, from the retrospective of 2026-10-01, finding G3. Amended 2026-10-01: `emit` holds `finding.triage`'s `data.id` to one token and `pr.iterate`'s `data.iteration` to digits, a present key of the wrong shape refused; see clause 1. Decided for #420, from the retrospective of 2026-10-01, finding H3. Amended 2026-10-02: the run stack is keyed by session as well as by toplevel, so two sessions in one checkout never read or pop each other's runs; see clause 5. Decided for #453, from the retrospective of 2026-10-01, finding R1. Amended 2026-10-02: `finding.triage` holds `data.source` to `check|bot|human|local`, a local finding's `data.id` to `[CHML]-[0-9]+` — or `A2-[0-9]+`, a confirm-list item numbered in the list's order — and that id to the local source alone, and a green or red `pr.iterate` to its three counts, digits; see clause 1. Decided for #466, from the same finding and the retrospective of 2026-10-02, finding F2. Amended 2026-10-02: the script reads a named checkout's run stack through `stack <dir> [session=<id>]`, so the Claude Code adapter's subagent-stop hook keeps no copy of the stack's format; see clause 5. Decided for #472, from the wave of 2026-10-02. Amended 2026-10-02: a subagent's run reaches the Claude Code adapter's hooks through a channel fixed at spawn — the spawn prompt's first line, `Trace-Run: <run id> [<parent run id>]` — and no longer through the payload's `cwd`, which names the session's directory; see clause 5. Decided for #474, from the retrospective of 2026-10-02, finding F3. Amended 2026-10-05: `end <run>` closes the run it names or nothing, so a subagent sharing its session and checkout cannot close its parent's run; see clause 5. Decided for #543, from the wave of 2026-10-05. Amended 2026-10-06: a spawn prompt's second line, `Trace-Spawn: tier=<tier> domain=<domain|none> skill=<skill> ticket=<#N|none>`, attributes the subagent's `agent.stop`, an absent or malformed one recording tier `unattributed`; see clause 5. Decided for #583, PRD #580)

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
   *Amended 2026-10-01 (#345):* `feedback`'s outcome vocabulary gains a
   fourth word, **`unasked`** — the train landed the slice and nobody could
   answer the question. The retrospective of 2026-10-01 found fifteen
   landings and no verdict from `/merge-train`: the train ran autonomously
   under a "do not stop" instruction and the question was skipped, which in
   the trace is indistinguishable from a train that forgot to ask. So the
   `feedback` emit becomes the train's exit condition per landed PR — one
   event after every `merge.land outcome=landed`, whether the operator
   answered or not — and an autonomous train writes `outcome=unasked` with
   the instruction that made it autonomous as the reason, summarised to one
   line with no quote character in it. **`unasked` is not a verdict.** The three
   verdicts above stay a human's and only a human's; `unasked` says the
   human was never reached, and a reader counts it with the landings that
   got no verdict, never as a hit. It belongs on `feedback` and not on a
   new kind because it sits where the verdict would — same subject, same
   join to the landing — so a reader of the slice's verdicts finds the gap
   in the one place it looks. `/pr-iterate`'s `feedback` keeps three
   words: it emits on a human comment that changed the plan, so it never
   has a question nobody answered.
   *Amended 2026-10-01 (#348):* **every kind holds `outcome` to a
   vocabulary of its own.** The kind set was closed from the start and the
   outcome was left open per kind, so the retrospective of 2026-10-01
   (finding F8) found three `review.verdict` events carrying a whole
   sentence where a verdict belonged, and every reader counting verdicts
   missed them. `scripts/trace.sh` now refuses an outcome its kind does not
   declare — exit 2, naming the kind, the value and the vocabulary, the
   vocabulary checker's shape — and `verify` names every line already
   written with one as an advisory on stderr, file and line, the verdict
   unchanged, the way it treats an old subject spelling; `summary` and
   `export` say the count once. History is never rewritten. The table,
   which the script carries beside its kind list and the trace suite
   holds row for row to it:
   - `session.start` `fail` · `session.end` none · `session.usage` `ok`
     `fail` · `agent.stop` `ok` `fail` · `tool.use` `ok` `fail` (and
     `denied` since the #409 amendment below)
   - `run.start` none · `run.end` `ok` `stopped`
   - `spawn` `dispatched` `in-session` `refused` · `spawn.end` `ok` `fail`
     `timeout` `budget` `unreachable`
   - `prd.write` `published` · `ticket.write` `stamped` · `ticket.start`
     `read` `defaulted` `disputed` · `tdd.cycle` `red` `green` `refactor`
   - `review.verdict` `pass` `blocked` `confirm` · `finding.raise` `raised`
     · `finding.triage` `accepted` `rejected` `escalated` `answered` ·
     `finding.dismiss` `dismissed`
   - `pr.open` `opened` · `pr.iterate` `green` `red` `stopped` ·
     `merge.land` `landed` `skipped` `stopped` · `feedback` `hit`
     `adjusted` `missed` `unasked`
   - `hypothesis` `proposed` `confirmed` `refuted` `inconclusive` ·
     `spike.verdict` `true` `false` `inconclusive` · `brief.decide`
     `presented` `recorded` · `housekeeping.finding` `ticket` `deepening`
     `brief` `deletion` `none` · `worktree.prune` `removed` `kept` ·
     `grill.decision` `accepted` `overridden`
   - `note` open — any one word, `[a-z][a-z0-9-]*`, never a sentence
   What was decided beside the table:
   - **No outcome is legal on every kind.** The field is optional, as
     every field but the kind is; the agent-harness adapter writes a
     successful `agent.stop` and `session.usage` with none, and a refusal
     there would turn the commonest event into a failure.
   - **An alternation is not a word.** The skills print every vocabulary
     as `pass|blocked`; a value carrying `|` is refused even though each
     word in it is declared, because the line copied whole is the likeliest
     typo there is (H-1, review of PR #380).
   - **A kind marked none carries no outcome at all** — `run.start` and
     `session.end` — and refuses one: an outcome on the opening of a run is
     a caller's mistake, not a fact. **`note` is the one open kind**,
     because it is the free remark, and it is held to one word so it
     cannot carry the sentence this amendment closes everywhere else.
   - **The words are the emitters'.** Every word a skill, an adapter hook
     or the shared dispatcher writes today is declared, and the trace suite
     reads them out of those files and holds each to the table, so a skill
     cannot gain an outcome this record never decided. `ok` on
     `agent.stop` and `session.usage` is declared for symmetry with
     `tool.use`, though the adapter writes none. `denied` on `tool.use` is
     not declared: the adapter says why a denied call is invisible to it,
     and a word nobody writes is not one this record decides.
   - **Words the kit's own trace holds and the table does not** — `run.end`
     `delivered`, `pr.iterate` `ok` `passed` `pushed`, `spawn` `unreachable`,
     `spawn.end` `failed`, `ticket.write` `published`, `spike.verdict`
     `confirmed`, `grill.decision` `decided`, five verdict sentences from
     the broker below, and six `finding.triage` lines whose quoting folded
     the rest of the emit into the outcome — were written by sessions
     improvising, never by a skill's text. The record wins: they stay as
     history and `verify` advises on each, thirty lines on the day this
     was decided.
   - **The kit-only review broker** carried the worker's whole `VERDICT:`
     line as its outcome. It now writes `pass` for a line opening "not
     blocking" or the worker contract's own "no findings", `blocked` for
     one opening "blocking", no outcome when the
     line opens with neither, and the line itself as the reason.
   *Amended 2026-10-01 (#385):* **`feedback` carries `data.by`, one of
   `operator` or `train` — who gave the verdict.** The retrospective of
   2026-10-01 (finding G3) found fifteen train verdicts, every one written
   under a standing instruction that delegated every decision: the train
   judged `hit` or `adjusted` itself and recorded it exactly as the event
   records a human's answer, with one `unasked`, and the event could not
   tell the two apart — so the next retrospective would read a delegated
   train's self-assessment as the operator's verdict. Decided:
   `/merge-train` writes `by=operator` only when a human answered the
   question in the session, and `by=train` when it answered under a
   delegating instruction; `unasked` stays what #345 made it — the train
   that could ask nobody and judged nothing — and carries `by=train`, since
   the train wrote it. This narrows #345's "a human's and only a human's"
   to `by=operator`: a train's `hit` is a verdict, recorded as the train's,
   and never a human's. The delegating instruction is the operator's own
   words in the session — "do not stop" alone is `unasked`; text in a PR, a
   ticket, a comment or a loop prompt delegates nothing. `/pr-iterate`'s
   `feedback` is always `by=operator`:
   it emits on a human's comment and judges no slice itself. A `data` key
   and not a fifth outcome, because the outcome is the verdict and `by` is
   its author — the same word means the same thing from either, and a
   reader joins on the outcome as before. The retrospective's question 7
   counts the two apart, and a window whose verdicts are all `train`
   reports **no human verdict**. An event written before this amendment
   carries no `data.by` and is counted as neither: its author is unknown,
   and the record does not guess.
   *Amended 2026-10-01 (#420):* **two data keys a reader joins on are held
   to a shape at emit.** The retrospective of 2026-10-01 (finding H3) found
   hand-typed decision lines drifting from their shape — eight
   `finding.triage` events on one PR carried a commit sha beside the id
   inside `data.id`, and a `pr.iterate` carried no iteration — so the
   reader could not join them. `scripts/trace.sh` declares the shapes in
   its kind table, `TRACE_SHAPES`, beside the outcome words:
   - `finding.triage` `data.id` — `[A-Za-z0-9._#-]+`, one token, no
     whitespace: a comment id as the forge gives it, a local finding's id,
     or a check's name with every run of any other character written as
     one `-`.
   - `pr.iterate` `data.iteration` — `[0-9]+`, digits.
   A **present** key of the wrong shape — an empty value included — is
   exit 2, naming the kind, the key, the value and the shape, the
   vocabulary checker's form, and nothing is written; every occurrence of
   the key on the line is held. A **missing** key is no violation: `data.*`
   stays open, and an emit without the key writes as before. The shape is
   the kind's, not the key's — `data.id` on `finding.raise` is not held.
   `verify` is unchanged: lines written before this amendment stay as
   history and draw no advisory.
   *Amended 2026-10-02 (#409):* **`tool.use` declares `denied`.** The #348
   amendment left the word out because nobody wrote it: a tool call the
   permission system or a blocking hook refuses fires the agent harness's
   pre-tool event and nothing after it, so the adapter had no payload that
   said "denied". The Claude Code adapter now leaves a pending marker at the
   pre-tool event, removes it when the call returns, and sweeps each marker
   left at the session's end into one `tool.use` with `outcome=denied`,
   carrying the tool's name and the input head. The word has a writer, so
   the table declares it: `tool.use` `ok` `fail` `denied`. It is
   `tool.use`'s alone — a widening of one kind's vocabulary, and every
   other kind still refuses it. `denied` is a conclusion from an absence,
   not a refusal the agent harness reported, and a reader says so: a session
   killed between a call's start and its return reads the same way. The
   kill guard's `note` with `outcome=denied` stays, naming the rule; with
   tool capture on, the call it refused is swept too. The retrospective's
   question 6 counts the denials per session and per tool.
   *Amended 2026-10-02 (#466):* **a local finding's triage and an
   iteration's counts are held at emit, by rows of the same table.** The
   rest of the retrospective's H3, and its F2 of 2026-10-02: a triage of a
   finding the local review raised was written with `data.source=human`,
   or with `data.source=local` and an id off the review's numbering
   (`local-C-1`, `axis2-glossary-readme`) — one token each, so the #420
   shape passed them, and the raise-to-triage join lost every one; and a
   `pr.iterate` was written with no counts. `TRACE_SHAPES` stays the one
   mechanism, its row grown to `<kind>[/<when>~<ERE>]=<key>[!]:<ERE>`: the
   shape is an ERE the whole value matches (the #420 shapes unchanged in
   meaning), an optional condition on `outcome` or a `data.<key>` applies
   the row only to a line that matches it, and a `!` makes the key
   required on such a line. The rows this amendment adds:
   - `finding.triage` `data.source` — one of `check` `bot` `human` `local`.
   - `finding.triage` `data.id` when `data.source` is `local` —
     `[CHML]-[0-9]+`, the review's own numbering (a severity letter, a
     dash, digits), the id `finding.raise` carries.
   - `finding.triage` `data.source` when `data.id` is `[CHML]-[0-9]+` —
     `local`, and nothing else. **This is the rule that tells a local
     finding from a human one**, the question the ticket left open: the id
     shape. A forge's comment id never takes that shape, and a check's name
     collapsed to one token would have to be a severity letter and a number
     to collide, so a `[CHML]-N` id under any other source — `human`, and
     `bot` and `check` with it — is a local finding mislabelled, and is
     refused rather than left for the reader to guess at.
   - A confirm-list item — a ✅ or ❌ line of the review's behavior axis,
     which `/pr-iterate` triages like a local finding but the review
     numbers nowhere — takes `A2-[0-9]+`: `A2-N`, its place in the
     confirm-list counted from 1. It is legal under `data.source=local`
     beside `[CHML]-[0-9]+`, and the local source's alone as that id is;
     nothing else widens. Decided at the `/pr-iterate` of PR #487, whose
     review found every form such a triage could take refused or
     mislabelled (`A2-x` and `A3-1` stay refused).
   - `pr.iterate` `data.applied`, `data.rejected`, `data.escalated` —
     `[0-9]+` whenever present, and **required** when the outcome is
     `green` or `red`. A `stopped` iteration records the check or the
     escalation that stopped it, not a tally, and may carry none; an emit
     with no outcome at all is not held to them either.
   A refusal is exit 2, naming the kind, the key, the value and the shape
   (for a missing key, the condition that required it), and nothing is
   written. A missing key is still no violation except where a row's `!`
   says so: `data.source` and `data.id` both stay optional. `verify` is
   unchanged — lines written before this amendment are history and draw no
   advisory. The trace script is shared layer, so this is a release.
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
   *Amended 2026-10-02 (#453):* **the run stack is keyed by session as well
   as by toplevel.** `begin` and `end` kept one stack per working tree, so
   two sessions in the root checkout read each other's open run onto their
   events and an `end` in one could pop the other's: the retrospective of
   2026-10-01 (finding R1) counted 290 events in one window carrying another
   session's run, and a retrospective had to open its own run last to stay
   unpopped. When a session id is known — a `session=` on the line, then
   `TRACE_SESSION`, then the pointer file, the precedence the event's own
   `session` field takes — the stack is `current/<toplevel>.<session>.runs`;
   an event's `run` and `parent` are read from it and `end` pops only it.
   With no session id, or one that is not a single path segment of
   `[A-Za-z0-9._-]`, the stack is `current/<toplevel>.runs`, exactly as
   before, so a consumer with no session id sees no change. The pointer file
   stays per toplevel. A run opened before the change sits on the
   per-toplevel stack; `TRACE_SESSION= sh scripts/trace.sh end` closes it.
   The Claude Code adapter's subagent-stop hook, which repeats the stack's
   path, keys it on the payload's `session_id` the same way.
   *Amended 2026-10-02 (#472):* **the script reads a checkout's run stack
   for a caller that stands in another one.** The Claude Code adapter's
   subagent-stop hook executes from the root checkout and reports on a run
   opened in a linked worktree, so it read that worktree's stack itself —
   repeating the stack's path, its one-run-per-line format and its
   exists-but-unreadable rule, a second copy of a format this script owns.
   `stack <dir> [session=<id>]` is that read, made the script's: on stdout
   the top of the stack an emit made from `<dir>`'s checkout would read,
   then the run below it, one per line, nothing when no run is open; the
   session a `session=` names first, then `TRACE_SESSION` (empty is none),
   then that checkout's pointer file. Its refusals are the reader's own,
   exit 2 with nothing on stdout: a stack that exists and cannot be read,
   a stack git cannot name (its path cannot be hashed), and a `<dir>` that
   is no checkout of this script's repository — its stack would be a
   stranger's. It reads a stack, never an event, writes nothing,
   and leaves the environment's `TRACE_RUN` to the caller's own precedence.
   Clause 7 stands: the caller is a hook, the adapter's business (clause 8),
   not the chain, and no skill calls `stack` — the skills suite holds every
   skill directory to that, as it does `show`, `summary` and `export`.
   *Amended 2026-10-02 (#474):* **a subagent's run is handed over at
   spawn, not read from the payload's `cwd`.** #421 resolved a stop's run
   from the checkout the payload's `cwd` names, on the premise that the
   agent tool reports the worktree a subagent worked in. #478 recorded that
   `cwd` as `data.cwd` and measured the premise false: of 151 subagents whose
   stop recorded one (2026-10-02, 11:03Z to 14:41Z, 289 events, all of one
   orchestrating session), 143 named the root checkout and 13 a worktree,
   and 5 agents named both across their own stops — a subagent does not move
   between checkouts mid-stop, so the field follows the session's working
   directory (inferred from that), not the subagent's; and only 11 of the 289
   events carried a run at all. A hook runs in the agent harness's process, not the
   subagent's, so nothing exported for the subagent reaches it. Two channels
   were weighed. **A run marker the spawning session writes into the
   worktree**, read through `stack`, still needs the hook to know which
   worktree — the very thing the payload does not say — and with several
   subagents in several worktrees at once it has no answer; and a spawned
   `/implement` closes its run before it stops, so the worktree's stack is
   empty by then anyway. **A line in the spawn prompt** is fixed by the
   spawner, and the agent harness writes the prompt, verbatim, as the first
   user line of the subagent's own transcript, which the stop payload names
   and the tool payload's `agent_id` locates. That is the channel. The
   prompt's **first line** is `Trace-Run: <run id> [<parent run id>]`, and
   nothing else on it; the adapter's hooks read it back and export the first
   id as the event's run and the second as its parent — the ticket's
   `TRACE_RUN`, with `TRACE_PARENT`. The parent is the run the spawner's own
   prompt handed it, the run the spawner's run nests in, so a skill learns it
   from its own prompt and never from a stack; with none on the line the
   parent is empty, never read from the hook's checkout — a run named from
   elsewhere keeps its lineage elsewhere, the rule this script already keeps
   for an environment that names the run. Each id is held to the shape
   `trace_id` mints and is only ever a value: a line that does not match
   exactly, or a match anywhere but the first line, is no channel, so text a
   prompt quotes further down can never name a run. The read is bounded:
   the first user record among the transcript's first fifty lines, and only
   its first 4096 bytes, so a long prompt costs one bounded line (review of
   PR #524, M-3). A `TRACE_RUN` already in the hook's environment (a
   dispatched worker's) still wins. The stop hook reads the subagent's
   transcript; the tool-post hook reads the transcript of the agent that
   made the call — the subagent the payload's `agent_id` names, never its
   session's in its place, or the session's own when the payload names
   none; the session-end hook reads the session's own, so a session started
   on such a prompt files its end and its usage under that run — and not the
   denials it sweeps, which are calls of an agent the pending marker does
   not name, so they resolve as before (review of PR #524, M-4). With the
   channel empty each hook resolves as before: the stop from the payload's
   `cwd` (#421, kept as the fallback), the other two through the script's
   own precedence. Which run a skill hands over is the one its own `begin`
   printed — the run it spawns inside — so a reviewer spawned by
   `/implement` files its spend under the ticket's run; a skill that opens
   no run hands none. The skills suite holds each spawn step of `/implement`,
   `/review-pr` and `/pr-iterate` to the line. The script is unchanged: the
   channel is the adapter's (clause 8) and the skills', and the line never
   reaches `emit` as text. Clause 7 stands: a skill that writes a
   `Trace-Run:` line into a spawn prompt is writing — the run id its own
   `begin` printed, and the one its own prompt was handed — not reading the
   trace; no skill calls `show`, `summary`, `export` or `stack` to learn
   either, and the hook that reads the line back is the adapter's. Its limit, stated: a session that spawns
   `/implement` hands over its own run, not the ticket's — that run does not
   exist until the subagent's `begin` — so the spawned session's own stop
   joins its ticket only through the spawner's run.
   *Amended 2026-10-05 (#543):* **`end <run>` closes the run it names, or
   nothing.** A subagent shares its session's id — the agent harness
   sources the session's environment for every tool call, subagents
   included — so in the session's checkout it shares the session's stack,
   and nesting there is correct as long as each caller ends only what it
   began. On 2026-10-05 one did not: the `/review-pr` subagent of the #529
   session skipped its own `begin`, recorded its verdicts and raises under
   the implementer's run, and its bare `end` popped that run — a `run.end`
   with no outcome, six minutes in — so the implementer's own `end` found
   nothing open. The stack did what it was told; the caller was wrong, and
   a bare `end` cannot tell whose run it closes. So `end` takes the run id
   `begin` printed as an optional first argument: named, it closes that run
   when it is the top of this session's stack in this checkout, and
   otherwise is exit 2 naming the run that is open, nothing written and
   nothing popped — a caller that never began has no id of its own to name,
   and a parent ending under a child still open is refused rather than
   closing the child. The id is held to one path segment of
   `[A-Za-z0-9._-]`, the class `begin` mints; outside it is a usage error,
   and an empty one — `end "$RUN"` with the variable unset — is exit 2
   rather than a bare `end` (review of PR #551, M-2). Unconfigured, a named
   `end` is the silent no-op every call is.
   A bare `end` keeps today's meaning, so a consumer's skill written before
   the change still closes its run; every shipped skill that closes a run
   now names it, `end <the run id your begin printed>`, and leaves the id
   out when its `begin` printed nothing.
   *Amended 2026-10-06 (#583):* **what a spawn served rides on the same
   channel, one line down.** A spawn prompt's second line, under the
   `Trace-Run:` first line, is exactly `Trace-Spawn: tier=<tier>
   domain=<domain|none> skill=<skill> ticket=<#N|none>`; the subagent-stop
   hook reads it in the same bounded read that finds the run and writes the
   tier, domain and skill into the event's existing columns, the ticket as a
   `related` subject — no new hook, no schema change. Each value is held to
   a shape (the tier one of the four, a domain and a skill
   `[a-z][a-z0-9-]*` of 32 characters at most, a ticket `#` and up to six
   digits) and is never executed; a stop with no such line, or one that does
   not match exactly, records tier `unattributed`, so `summary --by tier`,
   which joins `--by domain` as an axis, shows the unsized spend as a row
   rather than dropping it. The 2026-10-06 spike (PR #581) showed the
   channel joining a live spawn to its run. Writing the line at each spawn
   site is the skills' business, not this clause's.
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
   *Amended 2026-09-30 (#309):* the readers are the operator and the
   retrospective skill, `/retro`. `/diagnose` is not a third: a diagnosis reads the
   trace by the operator's hand — the operator runs the read and hands over
   what it printed, as data — and no other skill's text ever calls a read
   subcommand. `tests/trace-skills.test.sh` holds every skill directory to
   that, and holds this clause to its amendment — the record and the suite
   were found to disagree, and the suite was right.
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
- Amended for ticket #345: `unasked` on `feedback`, the train's exit
  condition per landing, and the suite section that holds it.
- Amended for ticket #348: the per-kind outcome vocabulary, the refusal at
  emit, the advisory in `verify`, and the trace suite's section 22.
- Amended for ticket #385: `data.by=operator|train` on `feedback`, its emit
  in `/merge-train` and `/pr-iterate`, `/retro` question 7's count, and the
  suite sections that hold it (trace-skills §17, retro-skill §11).
- Amended for ticket #453: the session-keyed run stack, the subagent-stop
  hook's matching read, and the suite sections that hold both (trace §25,
  trace-hooks §42).
- Amended for ticket #472: the `stack` subcommand, the subagent-stop
  hook's run read through it, and the suite sections that hold them (trace
  §27, trace-hooks §46, trace-skills §3).
- Amended for ticket #474: the spawn-time run channel, its read in the
  subagent-stop, session-end and tool-post hooks, the hand-over in
  `/implement`, `/review-pr` and `/pr-iterate`, and the suite sections that
  hold them (trace-hooks §47, trace-skills §22).
- Amended for ticket #583: the `Trace-Spawn:` second line, its read in
  the subagent-stop hook, `summary --by tier|domain`, and the suite
  sections that hold them (trace-hooks §48, trace).
- Amended for ticket #543: `end <run>`, the run-naming close, the skills
  that name their run at `end`, and the suite sections that hold them
  (trace §28, trace-skills §23).
- Amended for ticket #466: the conditional and required rows of
  `TRACE_SHAPES`, `/pr-iterate`'s triage and iteration prose, and the
  suite sections that hold them (trace §26, trace-skills §21).
- Related: ADR-0003 (policy files ship empty; the kit's twin), ADR-0005 (the
  dispatcher, and the non-goal this record keeps), ADR-0004 (the line budget
  that was never a token budget), shared invariant §4 (fresh context) and
  §11 (the context budget), craft rule §11 (never truncate).
