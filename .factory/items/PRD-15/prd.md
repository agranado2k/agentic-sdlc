---
id: PRD-15
type: prd
title: The kit's chain names a factory ticket by its id, and the kit stops mirroring issues
parent: D-02
stage: review
created: 2026-10-31
updated: 2026-10-31
stages:
  - {stage: draft, at: 2026-10-31T14:03Z}
  - {stage: review, at: 2026-10-31T14:08Z}
---

# PRD-15 · The kit's chain names a factory ticket by its id, and the kit stops mirroring issues

## 1. Objective

Let the kit's chain past the stamp (`/implement`, the review, `/pr-iterate`, the landing
script, `/merge-train`, `/retro` and the trace) take a factory ticket id such as `T-07`
wherever it takes an issue number today, and close a factory ticket the factory's way, so that
a factory project builds and lands its tickets with no forge issue, and this kit stops
mirroring its own factory tickets as issues once it can.

**Problem.** The factory owns idea → ticket and the kit owns ticket → landed change (D-02
decisions.md, 2026-10-23). PRD-12 (D-02's K7) taught the stamp reader and `/implement` to read
a factory ticket's stamp by its id, `sh scripts/stamp.sh T-07` (process/R128 to R135). Every
step after the stamp still names a ticket only by an issue number:

- the trace refuses `ticket:T-07`, because the kit's trace policy makes `ticket`, `pr` and `prd`
  numbered types, spelled `<type>:#<digits>` only;
- the PR body's landing line is `<!-- implement: ticket=#<N> tier=<tier> -->`, and the landing
  script and `/merge-train` match only that shape;
- the landing script's `--ticket` takes digits only, and its ticket is otherwise the PR's first
  closing reference, which a factory ticket never has;
- a ticket is closed by `Closes #<N>` on the merge, which means nothing to a factory ticket;
- the skill dispatcher's `--ticket`, the cascade's author record and the spawn line's
  `ticket=` field take an issue number only;
- `/review-pr` and `/pr-iterate` fetch a ticket's body with `gh issue view <N>` for the check
  table;
- `/retro` joins a PR to its ticket by matching `ticket:#[0-9]+`.

In a consumer factory project no ticket has an issue: the factory's rule is that a ticket is
never a forge issue (factory `constitution/local-workflow.md`). So there the chain past the
stamp cannot run at all. This repository works around it by **mirroring**: every factory
ticket it writes also gets a forge issue, the factory item carries a `GitHub issue: #<N>`
line, and the issue holds the ticket's text and stamp while the item stays a hollow index
entry. The same plan then exists twice, and a retro wave once filed the same tickets twice
(D-08 proposals.md, item 6).

**Solution.** This is D-02's K7b, ruled by the operator on 2026-10-31 (PRD-12 Q3, option (b)).
A **ticket handle** is either an issue number, `#<N>`, or a **canonical factory ticket id**,
`T-07` (§3). Every step past the stamp accepts both, and behaves for `#<N>` exactly as today:

- **The trace** accepts `ticket:T-07` and `prd:PRD-15` as well-spelled subjects through a new
  trace policy key that pairs a numbered type with the factory's id prefix. It still refuses
  every other spelling, `ticket:T-7` included. This absorbs PRD-12's T-74 (#937), the
  trace-subject requirement promised to D-08.
- **`/implement`** reads a factory ticket's text with `factory show`, works on the branch name
  the factory reads as a claim, moves the ticket to `build`, writes `ticket:T-07` subjects,
  opens the PR with `<!-- implement: ticket=T-07 tier=<tier> -->` and no closing keyword, then
  sets the ticket's `links.pr` and moves it to `review` on the ticket's branch. The factory's
  `review` and `qa` gates stay the operator's.
- **The review, `/pr-iterate`, the landing script and `/merge-train`** read the landing line
  in either form, take a factory id as `--ticket`, read the check table's ticket side from the
  stamp reader, and write `ticket:T-07` where they write `ticket:#<N>`.
- **`/retro`** joins on `ticket:T-07` as on `ticket:#<N>`.
- **The stop.** The kit mirrors until this PRD's last build slice has landed. From then on it
  writes no forge issue for a factory ticket, and a kit-only suite fails on any factory ticket
  created after the stop date that carries a `GitHub issue:` line. Tickets already mirrored
  keep their issue and are built by its number until they are done.

**The test of done.** In this repository, after the stop: a factory ticket written with no
issue, say T-90, is built by `/implement T-90` to an open PR whose body carries
`<!-- implement: ticket=T-90 tier=implementer -->` and no `Closes`, on a branch
`feat/t-90-<slug>`; `.factory/items/T-90/ticket.md` on that branch reads `stage: review` and
`links.pr: "#<PR>"`; `sh scripts/land.kit.sh <PR>` lands it with no `--ticket`, and its
`merge.land` relates `ticket:T-90`; `sh scripts/trace.kit.sh show ticket:T-90` prints the
ticket's `ticket.start`, `pr.open`, `merge.land` and `feedback`; `/retro`'s lead-time line
names `ticket:T-90`; and the kit's issue tracker gained no issue for it.

## 2. Users and scenarios

**U1 — the operator** of a factory project, who wants each ticket to exist once, as a factory
item, and still be built, reviewed, landed and measured by the kit's chain. **U2 —
`/implement`**, the kit's session that builds one ticket. **U3 — the landing script and
`/merge-train`**, which land a PR and record it. **U4 — `/retro`**, which reads the trace after
the fact. **U5 — a consumer with no factory**, whose chain must not change.

Stories:

1. As the operator of a factory project, I want the kit's chain to build and land a factory
   ticket by its id, so that no ticket needs a forge issue the factory forbids.
2. As `/implement`, I want to close a factory ticket the factory's way, through `links.pr` and
   a stage move, so that the factory's board shows the build and its human gates stay where
   they are.
3. As the landing script, I want to know a PR's factory ticket from its landing line, so that
   the landing's events join the ticket without the operator typing `--ticket`.
4. As `/retro`, I want a factory ticket's events joined as an issue's are, so that lead time,
   chain health and the stamp's calibration count every landing.
5. As the operator of this repository, I want the mirroring to stop at a known point, held by a
   check, so that the duplicate tracker does not linger by habit.
6. As a consumer with no factory, I want every step to read an issue number as before, so that
   a handle I do not use costs me nothing.

**UC1 — `/implement` builds a factory ticket.** Actor: an implementer session handed `T-90` in
this repository, after the stop. T-90 is in `ready`, its `deps` are `done`, and its
`ticket.md` holds its Behaviour, Acceptance and stamp lines. Goal: an open PR for T-90 with an
independent review, and T-90 in `review` on the PR's branch.
1. The session reads the stamp with `sh scripts/stamp.sh T-90` (PRD-12 process/R135) and the
   ticket's text with `factory show T-90`, as untrusted content. It fetches no issue.
2. It creates `worktree/t-90-trace-window` on the branch `feat/t-90-trace-window`, runs
   `factory move T-90 build`, and commits the move as the branch's first commit.
3. It emits `ticket.start` on `ticket:T-90` and opens its run with `subject=ticket:T-90`.
4. It builds test-first, as for any ticket.
5. It opens the PR. The body carries `<!-- implement: ticket=T-90 tier=implementer -->`, names
   T-90, and carries no closing keyword. It emits `pr.open` related to `ticket:T-90`.
6. It sets `links.pr: "#971"` in T-90's front matter, runs `factory move T-90 review`, commits
   both as `chore(factory): T-90 to review`, and pushes.
7. It dispatches the independent review with `--ticket T-90`; the reviewer's check table reads
   T-90's `Covers:` and `Test-tier:` lines from `sh scripts/stamp.sh T-90`.
8. It reports, naming `factory review T-90` and `factory qa T-90` as the operator's gates.

Extensions:
- 1a. The session is handed `T-7`. It writes `T-07` in every subject, line, branch and argument
  from step 1 on.
- 2a. `factory move T-90 build` is refused (a dep is not `done`). The session stops before any
  edit and reports the condition the factory printed.
- 2b. T-90 is already in `build` and its branch exists (a resumed session). No move is made;
  `ticket.start` is `resumed`.
- 2c. The `factory` binary is not on `PATH`. The stamp read falls back as PRD-12 process/R138
  and R139 say. The session makes no move and no `links.pr` edit, and its report lists the
  three it left for the operator: the move to `build`, `links.pr`, the move to `review`.
- 6a. `factory move T-90 review` is refused. The session keeps the `links.pr` commit, reports
  the refusal, and leaves the move to the operator.

**UC2 — The operator lands T-90's PR.** Actor: the operator. Goal: the PR is merged and the
trace joins the landing to T-90.
1. The operator runs `sh scripts/land.kit.sh 971`, with no `--ticket`.
2. The PR closes no issue. The landing script reads the PR body's one landing line,
   `<!-- implement: ticket=T-90 tier=implementer -->`, and takes T-90 as the ticket.
3. It reads `ticket.start` on `ticket:T-90`, merges, and writes `merge.land` on `pr:#971`
   related to `ticket:T-90`, with `data.implement=yes` and `data.implement_tier=implementer`.
4. It asks for the verdict and writes `feedback` on `ticket:T-90` related to `pr:#971`.
5. T-90 stays in `review` on `main` until the operator runs `factory review` and `factory qa`.

Extensions:
- 1a. The operator runs `--ticket T-90`. Same result; the landing line must agree for
  `data.implement=yes`.
- 1b. The operator runs `--ticket T-9x`. Exit 2, a usage error, before any forge call.
- 2a. The landing line reads `ticket=T-9`. It is recorded as absent: `data.implement=no`, and
  the feedback sits on the PR.
- 2b. `/merge-train` lands the PR instead. It reads the same line and relates the same ticket.

**UC3 — `/retro` counts T-90.** Actor: `/retro`, a week after the landing. Goal: T-90 counts
in every question that joins tickets.
1. `/retro` exports the trace and runs its questions.
2. The lead-time query finds `ticket.start` on `ticket:T-90` and `merge.land` related to it,
   and prints `landing pr:#971 ticket:T-90 lead …`.
3. The stamp-calibration and chain-health questions count T-90 once, as they count an issue.

**UC4 — The stop is held.** Actor: a session in this repository writing tickets after the
stop. Goal: no factory ticket gains a mirrored issue.
1. The session writes T-95 as a factory item with its full text and stamp, and no issue.
2. The kit-only suite passes.

Extensions:
- 1a. The session also opens issue #980 and adds `GitHub issue: #980` to T-95. The kit-only
  suite fails, naming T-95.
- 1b. T-60, created before the stop, still carries `GitHub issue: #923`. The suite passes, and
  T-60 is built by `sh scripts/stamp.sh 923` until it is done.

**UC5 — A consumer with no factory.** Actor: a consumer on the release after this PRD. Goal:
the same chain as before. `/implement 42` reads issue #42, writes `ticket:#42` and
`<!-- implement: ticket=#42 tier=… -->`, and the landing script and `/retro` read them as
before. Its trace policy names no factory prefix, so its trace judges subjects exactly as
before.

## 3. Model

- **Ticket handle**: what the chain names a ticket by. Either an **issue number**, written
  `#<N>` (digits, no leading zero), or a **canonical factory ticket id** (next). One ticket has
  one handle in this repository's chain: a mirrored ticket's is its issue number, any other
  factory ticket's is its id.
- **Canonical factory id**: the factory's prefix, a hyphen, then 2 to 6 digits, with a leading
  zero only in the two-digit form: `T-07`, `T-90`, `T-101`, `PRD-15`; never `T-7`, `T-007` or
  `t-07`. It is the spelling the factory writes in an item's `id:` field and prints as
  `factory stamp --json`'s `id` (checked 2026-10-31: `factory stamp T-7` answers for `T-07`).
  Two spellings of one ticket would break every join, so the chain writes only this one, and
  `/implement` pads a one-digit id it is handed.
- **Factory-id subject**: a trace subject or related token `<type>:<PREFIX>-<digits>`, for a
  type the trace policy pairs with a prefix: `ticket:T-07`, `prd:PRD-15`.
- **Landing line**: the one PR-body line `/implement` writes,
  `<!-- implement: ticket=<handle> tier=<tier> -->`, the handle `#<N>` or a canonical
  `T-` id.
- **Closing a factory ticket**: `links.pr` set to `"#<PR>"` in the ticket's front matter and
  `factory move <id> review`, committed on the ticket's branch so they reach `main` with the
  merge (the factory's workflow). `review → qa` and `qa → done` are the factory's human gates
  (`factory review`, `factory qa`); the kit never runs them.
- **Claim branch**: `<type>/t-<digits>-<slug>`, the digits as the canonical id spells them
  (`feat/t-07-add-login`). The factory reads a branch of that shape as a claim, so no other
  session is offered the ticket.
- **Mirrored ticket**: a factory ticket of this repository that carries a `GitHub issue: #<N>`
  line. Its text and stamp live in the issue; the item is an index entry.
- **The stop**: the day this PRD's slice 5 lands on `main`. From it, the kit writes no forge
  issue for a factory ticket. The **stop date** is recorded in the kit-only suite that holds
  it, and in D-02's decisions.md.

## 4. Rules

### Deltas against `docs/specs/runtime.md`

Area: runtime. The living spec ends at R51; PRD-08 to PRD-13 hold runtime/R52 to R228 in
their drafts, so this PRD's ids start at R229.

### ADDED

runtime/R229. WHERE the trace policy's `TRACE_FACTORY_IDS` names a word `<type>=<PREFIX>`, the trace SHALL accept at emit a subject or `related` token `<type>:<PREFIX>-<digits>` whose id is canonical, beside the `<type>:#<digits>` spelling the type already takes. [UC1 3, UC2 3]
runtime/R230. IF a subject or `related` token of a type `TRACE_FACTORY_IDS` names is neither `<type>:#<digits>` nor a canonical factory id of that type's prefix, THEN the trace SHALL exit 2 at emit, write nothing, and name the two forms the value should take.
runtime/R231. IF a `TRACE_FACTORY_IDS` word is not `<type>=<PREFIX>` with a type `TRACE_NUMBERED_TYPES` names and a prefix of 1 to 8 uppercase letters, THEN the trace SHALL exit 2 naming the word and the policy file.
runtime/R232. WHEN `show` is given a canonical factory-id subject, the trace SHALL print exactly the events whose subject is that string or whose `related` holds it as a whole token, so that `ticket:T-07` never matches `ticket:T-070`. [UC2 3]
runtime/R233. WHEN `verify` reads a line written with a factory-id subject, it SHALL pass a canonical one and SHALL advise on a non-canonical one as it advises on a mis-spelled numbered subject, its verdict unchanged.
runtime/R234. WHERE `TRACE_FACTORY_IDS` is empty or unset, the trace SHALL judge every subject exactly as it did before this PRD. [UC5]
runtime/R235. The shipped trace policy SHALL carry `TRACE_FACTORY_IDS` empty, with a comment naming its form, and the kit's own trace policy SHALL set it to `ticket=T prd=PRD`.
runtime/R236. WHEN the release that ships runtime/R229 to R234 lands, `UPDATING.md` SHALL tell a consumer that the trace accepts factory-id subjects through `TRACE_FACTORY_IDS`, that a project which sets `TRACE_NUMBERED_TYPES` and plans in the factory sets it to `ticket=T prd=PRD`, and that an empty value changes nothing.
runtime/R237. The skill dispatcher's `--ticket` SHALL accept an issue number, `#` optional, or a canonical factory ticket id, and SHALL refuse anything else, `T-7` included, exit 2, before it stages or spawns anything. [UC1 7]
runtime/R238. WHEN the skill dispatcher runs with `--ticket T-<digits>`, it SHALL write `ticket=T-<digits>` on the spawn prompt's `Trace-Spawn:` line, `ticket:T-<digits>` as its trace events' subject, and `ticket=T-<digits>` in the cascade's author record, and its review dispatch SHALL take an author record only when the record's ticket is exactly that id. [UC1 7]
runtime/R239. WHEN the skill dispatcher runs with a factory ticket id and a `--ticket-file`, it SHALL read the ticket's stamp with `sh scripts/stamp.sh T-<digits>` and use the file only as the ticket's text, with no stand-in tracker.
runtime/R240. The spawn guard SHALL pass a `Trace-Spawn:` line whose `ticket=` field is `#<N>`, `none` or a canonical factory ticket id, and the subagent's stop SHALL be related to `ticket:T-<digits>` for a factory id as it is to `ticket:#<N>` for an issue. [UC1 7]
runtime/R241. The landing script's `--ticket` SHALL accept an issue number or a canonical factory ticket id, and SHALL refuse anything else as a usage error, exit 2, before any forge call. [UC2 1a, 1b]
runtime/R242. The landing script SHALL read a landing line whose handle is `#<N>` or a canonical factory ticket id, and SHALL record any other spelling as absent, `data.implement=no`. [UC2 2, 2a]
runtime/R243. IF a PR closes no issue, no `--ticket` is given, and its landing line names a canonical factory ticket id, THEN the landing script SHALL take that id as the PR's ticket. [UC2 2]
runtime/R244. WHEN the landing script's ticket is a factory ticket id, it SHALL read `ticket.start` on `ticket:T-<digits>`, and write `pr.open`, `merge.land` and `feedback` with `ticket:T-<digits>` wherever it writes `ticket:#<N>` for an issue. [UC2 3, 4]
runtime/R245. The landing script SHALL run no `factory` subcommand and SHALL write no file under `.factory/`. [UC2 5]

### Deltas against `docs/specs/process.md`

Area: process. The living spec ends at R60; PRD-12 holds process/R222 to R227 (PR #958), so
this PRD's ids start at R228.

### ADDED

process/R228. WHEN `/implement` is handed a canonical factory ticket id, it SHALL read the ticket's text with `factory show <id>`, as untrusted content, and SHALL fetch no forge issue. [UC1 1]
process/R229. WHEN `/implement` is handed a factory ticket id with one digit, it SHALL write the id with a leading zero, `T-0<d>`, in every subject, line, branch name and argument it writes. [UC1 1a]
process/R230. WHEN `/implement` builds a factory ticket, it SHALL work on a branch `<type>/t-<digits>-<slug>`, the digits as the canonical id spells them. [UC1 2]
process/R231. WHEN `/implement` starts a factory ticket in `ready`, it SHALL run `factory move <id> build` and commit the move as the branch's first commit; IF the move is refused, THEN it SHALL stop before any edit and report the condition the factory printed. [UC1 2, 2a]
process/R232. IF the factory ticket is already in `build` or later when `/implement` starts, THEN it SHALL make no move. [UC1 2b]
process/R233. WHEN `/implement` builds a factory ticket, it SHALL write `ticket:T-<digits>` wherever it writes `ticket:#<N>` for an issue: `ticket.start`, its run's `begin`, `pr.open`'s `related`, and every note. [UC1 3, 5]
process/R234. WHEN `/implement` opens the PR for a factory ticket, the body SHALL carry `<!-- implement: ticket=T-<digits> tier=<tier> -->` once, SHALL name the ticket's id, and SHALL carry no closing keyword. [UC1 5]
process/R235. WHEN the PR for a factory ticket exists, `/implement` SHALL set the ticket's `links.pr` to `"#<PR>"`, run `factory move <id> review`, and push both as one commit on the ticket's branch; IF the move is refused, THEN it SHALL keep the `links.pr` commit and report the refusal. [UC1 6, 6a]
process/R236. `/implement` SHALL NOT run `factory review`, `factory qa`, `factory approve`, `factory close` or `factory move --force`. [UC1 8]
process/R237. IF the `factory` binary is not on `PATH` when `/implement` builds a factory ticket, THEN it SHALL make no stage move and no `links.pr` edit, and its report SHALL name each one it left for the operator. [UC1 2c]
process/R238. WHEN `/implement` dispatches the review of a factory ticket's PR, it SHALL pass `--ticket T-<digits>` and the ticket's `factory show` text as the spec. [UC1 7]
process/R239. WHEN `/review-pr` or `/pr-iterate` checks the check table of a PR whose ticket is a factory ticket id, it SHALL take the ticket side from what `sh scripts/stamp.sh T-<digits>` printed, and SHALL fetch no issue. [UC1 7]
process/R240. WHEN `/pr-iterate` or `/merge-train` records a verdict or a landing for a PR whose landing line names a factory ticket id, it SHALL write `ticket:T-<digits>` where it writes `ticket:#<N>` for an issue. [UC2 2b]
process/R241. `/merge-train` SHALL read a landing line whose handle is `#<N>` or a canonical factory ticket id, and SHALL treat any other spelling as no line. [UC2 2b]
process/R242. `/retro` SHALL join an event to its ticket on `ticket:T-<digits>` as on `ticket:#<N>` in every question that joins tickets, and SHALL count a factory ticket once wherever it counts tickets. [UC3 2, 3]
process/R243. WHEN this PRD's slice 5 has landed, the kit SHALL open no forge issue for a factory ticket, and a kit-only suite SHALL fail naming any factory ticket of this repository created on or after the stop date that carries a `GitHub issue:` line. [UC4 1, 1a]
process/R244. A factory ticket created before the stop date that carries a `GitHub issue:` line SHALL keep it, and the suite SHALL pass on it. [UC4 1b]

## 5. Slices (vertical, demoable, in order)

Six slices. Slice 1 moves `scripts/trace.sh`, which `VERSION` lists, so it is the one
shared-layer release, and the only one on any frontier (ADR-0033). Slices 2 to 5 move
kit-only scripts, the Claude Code adapter's hooks and skills: the next release's `VERSION`
history note lists them in its non-manifest half. Slice 6 is the stop. Every slice keeps an
issue number working exactly as today, and its suite proves it beside the factory id.

**Slice 1 — the trace accepts factory-id subjects (shared-layer release).** The receiving end
first: nothing writes `ticket:T-07` until the trace takes it. Absorbs T-74 (#937).
- *Covers:* runtime/R229, runtime/R230, runtime/R231, runtime/R232, runtime/R233,
  runtime/R234, runtime/R235, runtime/R236.
- *Also:* decision record A (§8). The glossary's Subject entry names the factory-id form and
  gains Ticket handle and Canonical factory id. The release bumps `VERSION`'s minor, writes
  `UPDATING.md`'s entry, re-captures the transcripts `tests/docs-demo.sh` quotes, and lands only
  once its merge commit carries the `v<version>` tag (ADR-0015, ADR-0025).
- *Accept:* `tests/trace.test.sh`, under a policy with `TRACE_NUMBERED_TYPES='ticket pr prd'`
  and `TRACE_FACTORY_IDS='ticket=T prd=PRD'`: `emit` writes `subject=ticket:T-07`,
  `subject=ticket:T-101` and `related='prd:PRD-15 pr:#9'`; it exits 2, writing nothing, on
  `ticket:T-7`, `ticket:T-007`, `ticket:T-1234567`, `ticket:t-07`, `ticket:PRD-07` and
  `prd:T-07`; `show ticket:T-07` prints the `ticket:T-07` events and none of a
  `ticket:T-070` line; `verify` advises on a hand-written `ticket:T-7` line and keeps its
  verdict; a word `ticket=t`, `issue=T` (an unnumbered type) or `ticket` exits 2 naming the
  word. With `TRACE_FACTORY_IDS` empty, `ticket:T-07` is refused as before, and with both keys
  empty it is accepted as before. `sh scripts/trace.kit.sh emit … subject=ticket:T-07` exits 0
  in this repository.

**Slice 2 — the skill dispatcher and the spawn guard carry a factory id.**
- *Covers:* runtime/R237, runtime/R238, runtime/R239, runtime/R240.
- *Blocked by:* slice 1.
- *Accept:* `tests/skill-cascade.test.sh` and the dispatcher's suite: `--dry-run --ticket T-07`
  prints `Trace-Spawn: … ticket=T-07`; `--ticket T-7`, `--ticket 07` and `--ticket T-07x` exit 2
  before anything is staged; a passed rung writes `ticket=T-07` in the author record, a review
  dispatched with `--ticket T-07` takes it, and one with `--ticket 7` or `--ticket T-08` refuses
  it; with a stand-in `factory` first on `PATH` and a stand-in tracker that fails if called,
  `--ticket T-07 --ticket-file <file>` reads the stamp through the stand-in `factory`. The
  `#<N>` cases of each suite pass unchanged. `tests/trace-hooks.test.sh`: the spawn guard
  passes `ticket=T-07` and refuses `ticket=T-7`, and a subagent stop under a `ticket=T-07`
  line is related to `ticket:T-07`.

**Slice 3 — `/implement` builds a factory ticket to an open PR and closes it the factory's
way.** The tracer bullet of the chain: UC1 end to end.
- *Covers:* process/R228, process/R229, process/R230, process/R231, process/R232,
  process/R233, process/R234, process/R235, process/R236, process/R237, process/R238,
  process/R239.
- *Blocked by:* slice 2, and PRD-12 slice 1 (T-71, #934), which gives `/implement` its
  factory-id stamp read.
- *Also:* decision record B (§8). `/review-pr`'s `CHECK-TABLE.md` and `/pr-iterate`'s take the
  ticket side from the stamp reader for a factory id (process/R239).
- *Accept:* `tests/implement-deliver.test.sh` holds, for a factory ticket id: `factory show`
  as the text read and no `gh issue view`; the one-digit pad; the claim branch shape; the move
  to `build` as the first commit and the stop on its refusal; no move when resumed; every
  `ticket:T-<digits>` subject; the landing line with a `T-` handle and no closing keyword; the
  `links.pr` and `review` commit after the PR exists; the five gate commands named only as the
  operator's; the absent-binary report; `--ticket T-<digits>` on the review dispatch. The
  check-table skill-text suites hold the stamp-reader source for a factory id. The issue-number
  path's existing assertions pass unchanged. Demo: one real factory ticket of this repository,
  written with no issue, built through `/implement T-<n>` to an open PR.

**Slice 4 — the landing script and `/merge-train` land a factory ticket's PR.**
- *Covers:* runtime/R241, runtime/R242, runtime/R243, runtime/R244, runtime/R245,
  process/R240, process/R241.
- *Blocked by:* slice 1.
- *Accept:* `tests/land.test.sh`, against its stub `gh`: a PR with no closing reference and the
  line `<!-- implement: ticket=T-90 tier=implementer -->` lands with no `--ticket`, its
  `merge.land` related to `ticket:T-90` with `data.implement=yes`, its `feedback` on
  `ticket:T-90`, its `ticket.start` read on `ticket:T-90` (`data.ticket_start=no` when absent);
  `--ticket T-90` gives the same; `--ticket T-9x` and `--ticket T-9` exit 2 with no `gh` call; a
  line `ticket=T-9` records `data.implement=no`; a stand-in `factory` that fails if called is
  never called and `.factory/` is unchanged. Every `#<N>` case passes unchanged.
  `tests/merge-train` skill-text assertions hold the two-form line read and the factory-id
  subjects.

**Slice 5 — `/retro` joins on factory-id subjects.**
- *Covers:* process/R242.
- *Blocked by:* slice 1.
- *Accept:* `tests/retro-skill.test.sh` runs each query `QUESTIONS.md` carries over an export
  holding one ticket by issue number and one by factory id, `ticket:#41` and `ticket:T-90`:
  the lead-time, chain-health, stamp-calibration and before/after queries each count both, and
  name `ticket:T-90` as written. An export with only `ticket:#<N>` subjects prints what it
  printed before.

**Slice 6 — the kit stops mirroring.** Once slices 1 to 5 have landed.
- *Covers:* process/R243, process/R244.
- *Blocked by:* slices 3, 4 and 5.
- *Also:* the stop date (the day this slice lands) goes into D-02's decisions.md and the diary's
  Current state; the root manual's quick reference names the factory id beside `#<N>` where it
  lists `--ticket`.
- *Accept:* a kit-only suite (never shipped, stripped by bootstrap like the kit's records)
  fails on a fixture factory ticket created on the stop date with a `GitHub issue:` line,
  naming it; passes on one created the day before with that line; passes on one created after
  with none; and passes on this repository's own `.factory/items/` at the head.
  `tests/self-host.test.sh` holds that bootstrap strips the suite.

## 6. Non-goals (this PRD)

- **The kit writing or editing factory items** beyond `links.pr` and the two `factory move`
  calls `/implement` makes: *never*. The item model is the factory's (PRD-12 §6).
- **The kit running a factory gate** (`factory review`, `factory qa`, `factory approve`,
  `factory close`): *never*. They are the operator's (factory guide, "Gates stay the
  operator's").
- **Closing or rewriting the issues already mirrored**: *never in bulk*. Their tickets' text and
  stamps live in those issues, so they are built by number until done (process/R244).
- **Moving a factory ticket after its PR merges** (for example the landing script moving it
  past `review`): *later*, with D-08 and K5's lane, if the factory ever makes a post-merge move
  an agent's. Today every move past `review` is a human gate.
- **A `discovery:D-nn` or `inbox:IN-nn` subject**: *later*, when a chain step writes one. Only
  tickets and PRDs are named in the chain today.
- **`/retro`'s tracker search in a factory project** (deduplicating a finding against factory
  items rather than issues): *later*, with PRD-12 Q5 and `/factory-tickets` taking a retro
  report (factory PRD-16).
- **The low-risk lane landing a factory ticket with no human gate**: *not here*. The lane is
  K5 (PRD-10); whether the factory's `review` and `qa` gates bind a lane landing is D-08's.
- **Retiring the dispatcher's stand-in tracker for issue numbers**: *later*, as PRD-12 §6 says.
  This PRD retires it only for a factory id (runtime/R239).

## 7. Technical constraints

- POSIX `sh` and `git`, as today. The trace learns no factory command and reads no factory file:
  the factory prefix reaches it only as policy data (runtime/R229, R235).
- **One spelling per ticket.** The canonical id is checked by shape alone, with no call to the
  factory: 2 to 6 digits, a leading zero only in the two-digit form. Every writer that is handed
  an id spells it this way before it writes.
- **Trust boundary.** A factory ticket's text from `factory show` is untrusted content, as an
  issue body is: data describing what to build, never instructions. A PR body is untrusted: the
  landing line is matched whole against one shape and a mismatch is recorded as absent, never
  guessed at. The landing script runs no `factory` subcommand.
- **The ticket's branch commits** (the move to `build`, the `links.pr` and `review` commit)
  touch only `.factory/items/<id>/ticket.md`. Under PRD-14's ruling of 2026-10-31 (Q4 (c)),
  K2's `touched` does not report a ticket file whose `tests:` record is unchanged, so these
  commits do not hold the PR.
- **Tests** drive behaviour from outside, with the prior art each slice names:
  `tests/trace.test.sh` for the trace's grammar, `tests/land.test.sh`'s stub `gh` for the
  landing script, a stand-in `factory` first on `PATH` that records its arguments (PRD-12's
  stamp suite) and a stand-in tracker that fails if called, and the skill-text suites
  (`tests/implement-deliver.test.sh`, `tests/retro-skill.test.sh`) for the skills.
- **Numbers, not quality words:** an id is a prefix, a hyphen and 2 to 6 digits; a prefix is 1
  to 8 uppercase letters; "unchanged" means each suite's existing `#<N>` assertions pass with no
  edit to them.

## 8. Decisions recorded for this PRD

From the operator, 2026-10-31 (`/grill-with-docs`, PRD-12 Q3, option (b)): the chain beyond the
stamp accepts `T-<n>` wherever it takes an issue number: `/implement`, the PR's landing line,
the landing script's `--ticket`, the closing (through `links.pr` and `factory move`, not
`Closes #N`), `/retro`'s joins, and trace subjects, absorbing T-74's part. The kit keeps
mirroring until this PRD lands, then stops. In a consumer factory project no ticket has an
issue.

**Derived while writing** (the session, under the operator's standing delegation of rulings;
the operator confirms them at approval):

- **T-74 (#937) is absorbed, not coordinated.** Its acceptance first asked for requirement
  lines in PRD-12 §4; its issue now says they go into this PRD (coordinator, 2026-10-31). They
  are runtime/R229 to R236 here, beside the rest of the naming change they belong with, and
  PRD-12 stays as PR #958 left it. T-74's build is slice 1. T-74 is done once this PRD is
  approved (the operator's move, or a `chore(factory)` PR).
- **The factory prefix is policy, not code.** The trace's comment already says the kit names no
  tracker, and `TRACE_NUMBERED_TYPES` is how a project names its numbered types. A second key,
  `TRACE_FACTORY_IDS='ticket=T prd=PRD'`, pairs a numbered type with the factory's prefix. A
  consumer whose numbered types are unset needs nothing: every type is open already.
- **The canonical spelling is the factory's own `id:`.** The factory resolves `T-7` to `T-07`,
  so both reach the same ticket there, but the trace joins on exact strings. The chain pads a
  one-digit id; the trace refuses every other spelling.
- **The landing script takes a factory ticket from the landing line, and only a factory id.**
  A factory ticket's PR has no closing reference, so without this the operator would type
  `--ticket` on every landing. An issue number on the landing line is not taken as the ticket,
  so an issue's landing behaves exactly as before.
- **The ticket's moves ride on its branch.** That is the factory's workflow ("a ticket's moves
  … on the ticket's branch … reach `main` when the PR merges"), and the claim branch keeps a
  second session off the ticket. This repository's habit of separate `chore(factory)` PRs for
  moves stays for moves made outside a build.
- **`links.pr` is written `"#<PR>"`.** That is the form the outcome recorder reads today
  (ADR-0036's QA step) and the form this repository's tickets carry. T-87 (#954) would also
  accept the URL form; nothing here depends on it.
- **The stop is "no new mirror", not "no mirror".** The mirrored tickets' text lives in their
  issues, so closing those issues would leave hollow items to build from. They finish by
  number. A rule with no failing check is a claim, so the stop has a suite.
- **The check table reads the stamp reader for a factory ticket.** The check-table reader needs
  only the `Covers:` and `Test-tier:` lines, which `sh scripts/stamp.sh T-<n>` prints checked;
  feeding it the factory file would be the second reader PRD-12 removed.

**Decision records** to write (both after the operator's yes, at the slice named):

- **A, slice 1.** Factory-id subjects: the trace accepts `<type>:<PREFIX>-<id>` for a numbered
  type the policy pairs with a prefix, one canonical spelling, refused otherwise at emit and
  advised by `verify`. A new record that amends ADR-0024 clause 1, which is at its amendment cap
  (ADR-0021), as ADR-0034 and ADR-0036 did.
- **B, slice 3.** The chain names a ticket by its handle: an issue number or a canonical factory
  ticket id. A factory ticket is closed through `links.pr` and `factory move <id> review` on its
  branch, and the factory's gates stay the operator's; the landing script takes a factory
  ticket from the landing line; the kit stops mirroring at slice 6. A new record that amends
  ADR-0019 clause 1 (the ticket the landing script reads `ticket.start` on: "the PR's first
  closing reference, or `--ticket`", now also the landing line's factory id) and ADR-0030
  clauses 2 and 3 (the author record's `ticket=` value).

**Alternatives considered:**

- **Keep mirroring everywhere** (PRD-12 Q3 (a)). Lost: a consumer factory project would have to
  open issues the factory forbids, and duplicates recur.
- **Stop mirroring now** (PRD-12 Q3 (c)). Lost: the kit's chain would break for every new
  ticket until this PRD's slices land.
- **Hard-code `T-` and `PRD-` in the trace.** Lost: the trace names no tracker by decision
  (ADR-0024 clause 1's numbered-type rule), and a policy word costs one line.
- **Accept any `T-<digits>` spelling and normalise in the readers.** Lost: every reader,
  `/retro`'s awk included, would carry the normalisation, and one that forgot it would split a
  ticket's trail silently.
- **Let the landing script move the factory ticket after the merge.** Lost: the moves past
  `review` are human gates, and a write on `main` after the merge would need its own commit.

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

- **How tickets are written in this repository between the stop and `/factory-tickets`.** After
  the stop, a ticket is a full factory item with no issue. PRD-12 slice 2 makes `/to-tickets`
  defer only where the factory's `factory-tickets` skill is installed (factory T-96); without
  it, `/to-tickets` runs its forge flow and would open issues.
  - Options: hold slice 6 until `factory-tickets` is installed here; or write tickets after the
    stop with `factory new` and the text written in the item by hand, until it is.
  - Next step: a question to agranado at approval. MVP default: hold slice 6 until
    `factory-tickets` is installable, since the suite would otherwise fail on the first
    `/to-tickets` run.
- **Whether `/implement` runs `factory start` to cut the claim branch.** It cuts the branch and
  worktree and pushes them, which `/implement` also does its own way.
  - Options: `factory start <id>` then work in its worktree; or `/implement`'s own
    `git worktree add` on the same branch name.
  - Next step: slice 3's implementer. MVP default: `/implement`'s own worktree on the claim
    branch name, so one path serves both handles.
- **Requirement ids may collide with D-02 PRDs drafted in parallel.** This PRD takes
  runtime/R229 to R245, past PRD-13's R228 (PR #957), and process/R228 to R244, past PRD-12's
  R227 (PR #958).
  - Next step: the session that approves it renumbers if an open PR has taken an id since.
    MVP default: as written.

## 10. Dogfood plan

Six tickets in slice order; slice 1 is the release. Slices 2, 4 and 5 can run beside slice 3
once slice 1 is tagged. The live demo is slice 3's: the first factory ticket of this repository
written with no issue, built by `/implement T-<n>`, landed by `sh scripts/land.kit.sh <PR>`
with no `--ticket`, and found by `sh scripts/trace.kit.sh show ticket:T-<n>`. After slice 6,
the next `/retro` reports that ticket's lead time beside the mirrored ones, and the tracker
gains no issue for it.
