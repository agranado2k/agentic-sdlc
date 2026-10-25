---
id: PRD-07
type: prd
title: The PR's decision log and check table, and the ticket contract's vocabularies
parent: D-02
stage: approved
created: 2026-10-23
updated: 2026-10-25
approved_by: "agranado"
approved_at: 2026-10-25
---

# PRD-07 · The PR's decision log and check table, and the ticket contract's vocabularies

## 1. Objective

Have every pull request the chain opens carry two records the operator reads before merging: a
**check table** that shows, for each requirement the ticket covers, which tier of test checked
it, the result and the evidence; and a **decision log** of each open point the agent decided
itself because its effect stays inside the change. Also fix the ticket contract's two new
vocabularies, `Risk:` and `Test-tier:`, in the kit's vocabulary checker and stamp reader, in a
tagged release the software factory can stamp against.

**Problem.** Today a PR says "tests pass" and nothing ties that claim to the requirement ids on
the ticket's `Covers:` line (the kit's ADR-0012). And every ⚠️ UNSPECIFIED item on `/review-pr`'s
confirm-list (§5b) is human-only (`/pr-iterate` hard rule 4), whether it is a renamed helper or a
new exit code. In this repository the operator already delegates those rulings to the session by
standing instruction, and the session posts each ruling as a PR comment. So the stop is a
formality on most items, the rulings are scattered across comments, and nothing tells the
operator which rulings touched what other people rely on. The operator's vision (D-02
proposals.md, idea 1) is a review that fixes what misses the ticket, decides the ambiguous parts,
and tells the human what it decided.

The factory (its D-08) also waits on this PRD. The D-02 and D-08 sessions agreed a `Risk:` line,
a `Test-tier:` line and a check-table shape. These are drafts until a kit decision record fixes
them, and the factory's PRD 3 starts on the tag of the release that ships them.

**Solution, from the user's side.**
- A ticket may carry `Risk:` and one `Test-tier:` line per covered id. The stamp reader checks
  them like `Tier:`.
- `/implement` opens each PR with a check table. `/review-pr` reads it, through a reader that
  prints only ids and tokens, and lists every covered id with no passing row as ❌ MISSING.
- The review marks each ⚠️ UNSPECIFIED item `scope: inside` or `scope: outward`. `/pr-iterate`
  decides the inside items and logs each in the PR body. The outward items stay the operator's,
  as every ⚠️ item is today.

This PRD only records what happens. Acting on risk is later work: holding a PR, the low-risk
lane, and the rule that writes `unlearned` and `outward` (K3, K5).

The test of done:
- `sh scripts/stamp.sh <N>` on a ticket carrying `Risk: high shared-layer` and `Test-tier:
  process/R38 suite` prints both lines, and on `Risk: high outward` exits 2.
- A PR built from a ticket covering three ids opens with three check-table rows. The next review
  lists a `fail` row as ❌ MISSING.
- A PR whose review marks a rename `scope: inside` and a new exit code `scope: outward` ends its
  `/pr-iterate` run with the rename logged as `D-1`, and the exit code at the top of the report
  for the operator.

## 2. Users and scenarios

**U1 — the operator**, who reads the PR before merging it. **U2 — the software factory**, a
planner outside the kit that stamps tickets the kit's chain builds. **U3 — the chain's skills**:
`/to-tickets`, `/implement`, `/review-pr`, `/pr-iterate`.

Stories:

1. As the operator, I want the agent to decide the open points whose effect stays inside the
   change and to tell me what it decided, so that I am asked only about what others rely on.
2. As the operator, I want each PR to show, per covered requirement, which tier of test checked
   it and with what result, so that I read evidence, not "tests pass".
3. As the software factory, I want the `Risk:` and `Test-tier:` vocabularies fixed in a tagged
   kit release, so that my tickets stamp words the kit's chain reads and checks.
4. As `/implement`, I want the stamp reader to check `Risk:` and `Test-tier:`, so that an
   untrusted ticket body never hands me an unchecked value.
5. As a later reader (the risk rule, `/retro`), I want the outward count and each logged decision
   recorded as tokens in the trace, so that I can count them without reading PR prose.

**UC1 — Read a stamped ticket.** Actor: `/implement`, starting ticket #900. Goal: the ticket's
stamp, checked.
1. Ticket #900 carries `Tier: implementer`, `Confidence: medium`, `Covers: process/R41,
   process/R42`, `Risk: high shared-layer`, `Risk-confidence: medium`, `Test-tier: process/R41
   suite` and `Test-tier: process/R42 unit`.
2. `sh scripts/stamp.sh 900` hands the lines to the vocabulary checker, which accepts them.
3. The stamp reader prints the seven lines, and `/implement`'s restatement names the risk and
   both test tiers.

Extensions:
- 2a. The ticket says `Risk: high outward`, a reason only the risk rule writes. The checker
  refuses it, and the stamp reader exits 2 naming the field `risk`, never the line.
- 2b. The ticket says `Test-tier: process/R41 suite` and `Test-tier: process/R41 unit`. The
  checker refuses the id given two tiers.
- 3a. The ticket carries no `Risk:` line. The reader prints none and invents none. A later
  reader takes the absence as `high unclear`.
- 3b. The ticket carries 40 `Test-tier:` lines. The reader stops with exit 5 and prints nothing.

**UC2 — Open a PR with its check table.** Actor: `/implement` on ticket #901, which covers
`process/R45`, `process/R46` and `process/R47` and stamps `process/R47` as `manual`. Goal: a PR
whose body shows the evidence per requirement.
1. The full suite passes. `/implement` writes the PR body from the template, with a table under
   `<!-- check-table -->`: `process/R45 | unit | pass | tests/check-table.test.sh::process/R45@3f9c2e1`,
   and a `suite` row for `process/R46`.
2. It writes the `process/R47` row as `manual | skipped | -`, since no human has checked it yet.
3. The table sits above the `<!-- explain-diff-appendix -->` marker, so the Axis-2 reviewer reads
   it.

**UC3 — Review and iterate against the check table.** Actor: `/review-pr`, then `/pr-iterate`,
on PR #950 for ticket #901. Goal: no covered id is left without a passing row in silence.
1. The review's coordinator runs the check-table reader on the PR body and the ticket body. It
   prints `fail: process/R46` and `skipped: process/R47`.
2. Agent 7 receives that output beside `scripts/behavior-delta.sh`'s. It lists `❌ MISSING
   process/R46 — fail` and `❌ MISSING process/R47 — skipped`.
3. `/pr-iterate` fixes the failing test and pushes. It rewrites the `process/R46` row as `pass`,
   pinned to the new head.
4. The reader now prints only `skipped: process/R47`. `/pr-iterate` reports the PR converged,
   with `process/R47` at the top as a manual check awaiting the operator.

Extensions:
- 1a. Row 3 breaks the grammar. The reader exits 2 naming row 3, and every covered id reads as
  missing.
- 1b. The body carries no table. The reader exits 3, and every covered id is ❌ MISSING
  `missing-row`.
- 1c. A row's tier differs from the ticket's `Test-tier:` stamp. The reader prints
  `tier-differs: <id>`, and Agent 7 lists it as ❌ MISSING.

**UC4 — Stamp test tiers.** Actor: `/to-tickets`, drafting from a PRD with requirement lines.
Goal: every covered id carries the tier the planner chose.
1. For each ticket, it writes one `Test-tier:` line per id on its `Covers:` line.
2. Before the quiz, it checks every `Test-tier:` line with the vocabulary checker.
3. The quiz shows each ticket's test tiers beside its `Covers:` line.

Extensions:
- 2a. The checker refuses a line. The draft is repaired and checked again, never shown refused.

**UC5 — Decide an unspecified item, or hold it.** Actor: `/pr-iterate` on PR #960. Its review
lists two ⚠️ UNSPECIFIED items: a helper renamed from `lift` to `lift_lines`, and a new exit code
4 on a shipped script. Goal: each item ends decided and logged, or held for the operator.
1. Agent 7 marks the rename `scope: inside` and the exit code `scope: outward`.
2. `/pr-iterate` keeps the rename. It writes row `D-1` in the decision log under `<!--
   decision-log -->`, giving the surface, the decision and why, and records one `finding.triage`
   event naming `D-1`.
3. It lists the exit-code item verbatim at the top of its report for the operator, and neither
   decides, amends nor logs it.
4. Before merging, the operator reads the decision log and the held item.

Extensions:
- 1a. Agent 7 gives an item no scope, or a word the vocabulary does not hold. The item reads as
  `outward`.
- 2a. A later review marks outward the item `D-1` decided. `/pr-iterate` strikes row `D-1`,
  keeping its id, and holds the item as step 3 says.

## 3. Model

- **The ticket contract** gains three stamp keys:
  - `Risk:` takes a level and, for `high`, one reason.
  - `Risk-confidence:` is the risk stamp's confidence. The body's one `Confidence:` line stays
    the tier's (`/to-tickets` rule 14).
  - `Test-tier:` takes a requirement id and a test tier.

  The vocabulary checker also learns two tokens a PR carries: a check-table row's **result** and
  an ⚠️ item's **scope**.
- **The check table** is a block in the PR body: a marker, a fixed header, one row per covered
  id. Its machine-read cells are ids and tokens, plus one evidence pin held to a grammar.
- **The decision log** is a block in the PR body: a marker, and one row per decided inside item
  with a stable id `D-<n>`. Its prose is for the operator. No skill reads it back, and the trace
  carries each decision as a `finding.triage` event.
- **Scope** is a word Agent 7 adds to each ⚠️ UNSPECIFIED item: `inside` or `outward`. A missing
  or unknown scope reads as `outward`, which fails closed to the operator.

## 4. Rules

Area: process

Deltas against `docs/specs/process.md`, which ends at R36; PRD-06 takes process/R37, so these start at R38.

### ADDED

process/R38. The vocabulary checker SHALL accept a `Risk:` line whose value is `low` alone, or `high` followed by exactly one reason from the policy's risk reasons (`irreversible`, `security`, `invisible`, `shared-layer`, `unclear`, `unlearned`, `outward`), and SHALL refuse any other value, naming the field. [UC1 2]
process/R39. IF a `Risk:` line names a reason the policy reserves for the risk rule (`unlearned`, `outward`), THEN the vocabulary checker SHALL refuse it unless its caller declares itself the risk rule. [UC1 2a]
process/R40. The vocabulary checker SHALL accept a `Test-tier:` line whose value is one requirement id in the coverage check's bounded grammar followed by one of `unit`, `suite`, `e2e`, `manual`, SHALL accept one such line per distinct id, and SHALL refuse an id given two different tiers. [UC1 2, 2b]
process/R41. The shipped vocabulary policy SHALL declare the fields `risk`, `risk-confidence` (`low`, `medium`, `high`), `test-tier`, `result` (`pass`, `fail`, `skipped`) and `scope` (`inside`, `outward`), and the checker's built-in defaults SHALL equal it.
process/R42. WHEN a ticket carries `Risk:`, `Risk-confidence:` or `Test-tier:` lines, the stamp reader SHALL lift and check them with the ticket's other stamp lines and print them as spelled, and SHALL print no `Risk:` line for a ticket that carries none. [UC1 3, 3a]
process/R43. IF a ticket carries more than 32 `Test-tier:` lines, or more than 8 lines of any other stamp key, THEN the stamp reader SHALL stop with exit 5 and print nothing. [UC1 3b]
process/R44. WHEN the release that ships R38 to R43 lands, `UPDATING.md` SHALL tell a consumer whose own vocabulary policy file predates it to add the five new fields, because a policy file that is found is the whole policy.
process/R45. WHEN `/implement` opens a pull request for a ticket with a `Covers:` line, it SHALL write, above the explain-diff marker and under a `<!-- check-table -->` marker, a table headed `| Requirement | Test tier | Result | Evidence |` with one row per covered id, and the shipped PR template SHALL carry that section. [UC2 1, 3]
process/R46. Each check-table row SHALL carry the ticket's `Test-tier:` for its id where the ticket stamps one, a result of `pass`, `fail` or `skipped`, and as evidence a `<path>::<test>@<commit>` pin of the test that checked it or an `https://` URL, and a `manual` row no human has checked SHALL read `skipped` with the evidence `-`. [UC2 1, 2]
process/R47. The check-table reader SHALL read a PR body and a ticket body and print only requirement ids, tokens and row numbers: exit 0 when every covered id has exactly one row, its result `pass` and its tier the ticket's stamp; exit 1 with `missing-row:`, `extra-row:`, `tier-differs:`, `fail:` and `skipped:` lines; exit 2 for a row that breaks the grammar or a table past 64 rows, naming the row number; exit 3 when the body carries no table. [UC3 1, 1a, 1b, 1c]
process/R48. WHEN `/review-pr` reviews a PR whose ticket has a `Covers:` line, its coordinator SHALL run the check-table reader and hand the output to Agent 7, which SHALL list each id the reader names, and each covered id when the reader exits 2 or 3, as a ❌ MISSING item naming the id and the reader's word. [UC3 1, 2, 1a, 1b, 1c]
process/R49. WHEN `/pr-iterate` pushes a commit to a PR with a check table, it SHALL rewrite each row's result and evidence pin from that iteration's suite run at the new head. [UC3 3]
process/R50. WHILE the check-table reader prints a `fail:`, `missing-row:`, `extra-row:` or `tier-differs:` line, `/pr-iterate` SHALL NOT report the PR converged. [UC3 4]
process/R51. WHEN the check-table reader prints `skipped:` lines, `/pr-iterate` SHALL list those ids at the top of its report as manual checks awaiting the operator. [UC3 4]
process/R52. WHERE a PRD carries requirement lines, `/to-tickets` SHALL stamp one `Test-tier:` line per id on each ticket's `Covers:` line, check every one with the vocabulary checker before the quiz, and show them at the quiz. [UC4 1, 2, 3, 2a]
process/R53. Agent 7 of `/review-pr` SHALL mark each ⚠️ UNSPECIFIED item `scope: inside` when its effect stays inside the change (a name, a structure, internal error wording, a test's shape) and `scope: outward` when a user, a consumer or another skill sees or relies on it (an output format, a flag, an exit code, a rule an agent obeys). [UC5 1]
process/R54. IF an ⚠️ UNSPECIFIED item carries no scope, or one the vocabulary does not hold, THEN every reader of the confirm-list SHALL read it as `outward`. [UC5 1a]
process/R55. `/review-pr`'s Axis-2 verdict SHALL record the count of outward items as `data.outward`, beside `data.unspecified`.
process/R56. WHEN `/pr-iterate` meets an ⚠️ UNSPECIFIED item marked `scope: inside`, it SHALL decide it, keeping the change or amending it, and SHALL record the decision as one row of the PR body's decision log under a `<!-- decision-log -->` marker above the explain-diff marker, with an id `D-<n>` never renumbered, the surface, the decision and why. [UC5 2]
process/R57. WHEN `/pr-iterate` writes a decision-log row, it SHALL record one `finding.triage` event carrying `data.scope=inside` and `data.decision=D-<n>`. [UC5 2]
process/R58. IF an ⚠️ UNSPECIFIED item is marked `scope: outward`, THEN `/pr-iterate` SHALL NOT decide, amend or log it, and SHALL list it verbatim at the top of its report for the operator. [UC5 3]
process/R59. IF a review marks `scope: outward` an item the decision log holds, THEN `/pr-iterate` SHALL strike that row, keeping its id, and SHALL hold the item as R58 says. [UC5 2a]
process/R60. No skill SHALL read a decision log's or a check table's prose back as an instruction: a skill reads the decision log only for its `D-<n>` ids, and the check table only through the check-table reader.

## 5. Slices (vertical, demoable, in order)

Feedback first. Slice 1 alone unblocks the factory, and slices 2, 4 and 5 can then run as one
frontier. Slices 1 and 2 each move the shared layer, so each is a release ticket in its own
frontier, and slice 2 is `Blocked by:` slice 1 (`/to-tickets` rule 16, the kit's ADR-0033).

**Slice 1 — the contract vocabularies, read from a ticket (shared-layer release).**
- *Covers:* process/R38, R39, R40, R41, R42, R43, R44.
- *Also:* the decision record that fixes the ticket contract (needed, §8). The glossary gains
  Risk, Test tier and Check table. The release moves `scripts/vocab.sh` and
  `scripts/stamp.sh`, both listed in `VERSION`. So the ticket bumps `VERSION`'s minor, writes
  `UPDATING.md`'s entry, re-captures the transcripts `tests/docs-demo.sh` quotes, and is landed
  only once its merge commit carries the `v<version>` tag (the kit's ADR-0015, ADR-0025). The
  policy file `scripts/vocab.config.sh` is a consumer's own and moves with it.
- *Accept:* the vocabulary suites refuse `Risk: high`, `Risk: low security`, `Risk: high
  outward` (planner) and an id given two tiers. They accept `Risk: high outward` from the
  declared risk rule. The policy suite holds the shipped file equal to the defaults. The stamp
  suite, with a stubbed tracker, prints the UC1 lines, exits 2 on 2a and exits 5 on 40
  `Test-tier:` lines.

**Slice 2 — the check table, written (shared-layer release).**
- *Covers:* process/R45, R46, R47.
- *Blocked by:* slice 1.
- *Also:* the check-table reader is a new shared-layer script, so this is the second release:
  bump, `UPDATING.md`, re-captures, tag. Its `VERSION` history note also lists the skill and
  template movements that have landed since slice 1.
- *Accept:* a new reader suite, built like `tests/coverage.test.sh`, drives each exit code from
  fixture bodies, and shows that no line of either body reaches stdout. A skill-text suite holds
  `/implement`'s check-table step and the template section.

**Slice 3 — the check table, read and kept.**
- *Covers:* process/R48, R49, R50, R51.
- *Blocked by:* slice 2.
- *Accept:* `tests/review-pr-output.test.sh` holds Agent 7's MISSING items for each reader word,
  and the offline review worker's contract carries the same. A skill-text suite holds
  `/pr-iterate`'s rewrite step, its not-converged rule and its manual-check list.

**Slice 4 — test tiers stamped at `/to-tickets`.**
- *Covers:* process/R52.
- *Blocked by:* slice 1.
- *Accept:* `tests/spec-skills.test.sh` holds the stamp step, its checker call before the quiz,
  and its place at the quiz.

**Slice 5 — scope on every unspecified item.**
- *Covers:* process/R53, R54, R55.
- *Blocked by:* slice 1.
- *Also:* the decision record for the scope rule (needed, §8). The glossary gains Scope. The
  offline review worker's contract and the review broker count outward items.
- *Accept:* the review-output suite holds the scope words on the ⚠️ line and the outward default.
  `tests/forge-broker.test.sh` records `data.outward` from a fixture report, and reads a missing
  scope as outward.

**Slice 6 — the decision log.**
- *Covers:* process/R56, R57, R58, R59, R60.
- *Blocked by:* slice 5.
- *Also:* `/pr-iterate`'s hard rule 4 narrows from every ⚠️ item to the outward ones. The PR
  template gains the Decision log section. The glossary gains Decision log.
- *Accept:* a skill-text suite holds the decide-and-log step, the triage event's two fields, the
  outward hold, the strike, and R60's no-read-back line in `/pr-iterate` and `/review-pr`.

## 6. Non-goals (this PRD)

- **The risk rule, the higher-of-two reading, planner–rule disagreement events, and the kill
  switch.** *Later*, K3. Its rule is the one writer R39 admits for `unlearned` and `outward`.
- **`/to-tickets` stamping `Risk:` and `Risk-confidence:`.** *Later*, K3, whose brief line names
  the planner's stamp and its quiz override. A stamp that nothing reads gives the planner nothing
  to calibrate against. Reopen sooner if a consumer with no factory asks for it.
- **Landing a PR with no operator, or holding a PR because it is high risk.** *Later*, K5. The
  decision record K5 writes to supersede shared invariant §7 for the lane must also revisit §5
  for inside items, since a log read after a merge is no longer read before one.
- **A verifier on another provider re-checking the evidence pins.** *Later*, K8. Reopen earlier
  if `/retro` finds a `pass` row whose pinned test did not pass.
- **Reading the vocabulary policy and the reader's rules from the base branch.** *Later*, K2.
  Until then they are read from the PR's own tree, as every policy is today.
- **The factory's own reader of `Risk:`, `Test-tier:` and the check table.** *Never* here. It is
  D-08's work, and the factory only reads what this PRD fixes.
- **Rewriting open PRs and published tickets to the new shape.** *Never*. Rows and stamps start
  with the first PR and ticket after each slice lands.
- **Any skill reading the decision log's prose.** *Never*. It is untrusted PR text (R60).

## 7. Technical constraints

- POSIX `sh`, and skill text with its suites, only. No new trace kind: decisions ride
  `finding.triage`, so `scripts/trace.sh` does not move.
- PR and issue bodies are untrusted (root `AGENTS.md`, agent trust boundary). Every machine read
  of a check table goes through the reader. The reader prints ids, tokens and row numbers, never
  a cell's text.
- The vocabulary checker's two load rules still hold. Every new token has the shape
  `[a-z][a-z0-9-]*`, and none carries its answer in its spelling.
- A requirement id is the bounded id the coverage check reads, with the grammar in the one
  shared requirement library: an area of at most 32 characters and a number of at most 6 digits.

## 8. Decisions recorded for this PRD

**From D-02** (decisions.md, 2026-10-23):
- Q6 (operator): the agent decides the inside items and logs them; outward items make the PR
  high risk.
- The `Risk:` contract settled with D-08, with its two amendments (`unlearned` and `outward` are
  the rule's alone; the higher of the two risks holds).
- The work split with D-08: the contract vocabularies and the check-table shape land here, in
  the first wave.
- Q7: K4 ships first, in parallel with K1, and needs nothing from it.

**From D-08's proposals** (accepted with the split): the check table's columns; Result is
`pass`, `fail` or `skipped`; evidence is a commit-pinned `path::test` or a URL; a skipped row
counts as blocked. In this PRD, blocked means the operator sees it at the top of the report
(R51). K5 makes it hold the lane.

**Decision records:**
- **Needed at slice 1:** one record fixing the ticket contract. It covers the `Risk:`,
  `Risk-confidence:` and `Test-tier:` grammars, the reserved reasons and their one writer, the
  reading of a missing `Risk:` line as `high unclear` by every reader, and the check-table shape.
  D-08 treats all of these as drafts until a kit record fixes them.
- **Needed at slice 5:** one record of the scope rule: Q6's inside/outward line, the outward
  default, and who decides an inside item.
- **Cited:** ADR-0012 (ids and `Covers:`), ADR-0015 and ADR-0025 (a release is bumped and
  tagged), ADR-0033 (one shared-layer ticket per frontier), ADR-0009 (the broker), ADR-0024 (the
  trace is written by skills and read only by `/retro`), ADR-0016 (the session's delegated
  rulings), and ADR-0017 (a shipped skill cites a kit record only as the kit's).

**Implementation decisions** (each one expensive to reverse once the factory stamps against it):
- **`Risk:` is one line, a qualified field.** It holds a level token, then, for the levels the
  policy marks, exactly one reason token. The policy names the levels, the levels that take a
  reason, the reasons, and the reasons reserved for the risk rule. The checker learns this as a
  new kind of field, held as data like the query field.
- **The writer is declared by the caller.** The default is the planner, so a stamp, a ticket and
  a factory line can never name a reserved reason. A declared risk-rule writer may. K3 uses that
  mode, so the checker does not move again for it.
- **`Risk-confidence:` is its own key**, because a ticket body's one `Confidence:` line is the
  tier's (`/to-tickets` rule 14). Two `Confidence:` values would be refused as two answers. The
  D-08 session must be told, since its "beside `Tier:` with a `Confidence:`" did not settle the
  key (§9).
- **`Test-tier:` is a keyed field.** Its key is a bounded requirement id and its value a token.
  It may repeat once per key. The same key with two values is refused, and the same key with
  the same value is one answer.
- **A missing `Risk:` line is read as `high unclear` by the reader that acts on risk**, never
  written in by the stamp reader. That reader does not exist until K3, and a line the planner
  never wrote must not look as if it did.
- **The check table's grammar:**
  - The marker line comes first, then the exact header and a separator row.
  - Rows run to the first line that does not open with `|`.
  - A `Requirement` cell holds a bounded id, `Test tier` a test-tier token, and `Result` a
    result token.
  - `Evidence` is one of three things:
    - `<path>::<test>@<sha>`: a path and a test name in the plain set (letters, digits, `.`, `/`,
      `_`, `-`) and a sha of 7 to 40 hex digits;
    - an `https://` URL in the plain set plus `:`, `#`, `?`, `=`, `&` and `%`, at most 200
      characters;
    - `-`, only on a `skipped` row.
  - The table may hold at most 64 rows.
- **The check-table reader is a new shared-layer script beside the coverage check.** It reads
  two files the caller fetched, a PR body and a ticket body, and shares the coverage check's id
  grammar. It runs no tracker and no forge command. Agent 7, a reviewer with read-only tools,
  receives its output as a file, as it receives `scripts/behavior-delta.sh`'s.
- **Scope is written on the ⚠️ item's arrow line**, as its first words `scope: inside` or `scope:
  outward`. The confirm-list's machine contract stays the same: one item per line, tag first.
  The review broker and the offline review worker's contract learn the same words.
- **Only `/pr-iterate`'s session decides an inside item.** Agent 7 classifies and never resolves
  (`/review-pr` §5b, unchanged), so the independent reviewer is not the author of what it judges.
  `/implement` logs nothing, so the author never classifies its own choices.
- **The decision log's grammar.** The marker comes first, then the header `| Decision |
  Surface | What was decided | Why |`. A row's first cell is `D-<n>`, numbered from 1 and never
  renumbered, and a struck row keeps its id. The log is created by the first row written.
- **Shared invariant §5 is not amended; K4 narrows how it is applied.** An inside item is still
  a behavior finding addressed to the human: it sits in its own log in the PR body, never among
  the Axis-1 standards findings, and the human reads it before merging, since §7 still holds in
  K4. It is not "dressed as a standards nit". So `constitution/shared-invariants.md`, a
  shared-layer file, does not move. If the operator reads Q6 as an amendment, that edit is its
  own shared-layer release ticket in a later frontier.

- **Settled with the D-08 session, 2026-10-23** (formerly §9's three open questions):
  - `Risk-confidence: <low|medium|high>` is its own key, and its vocabulary field is spelled
    exactly `risk-confidence`, so `factory stamp` maps nothing. `Confidence:` stays the tier's.
  - `Test-tier:` allows 32 lines per ticket, every other stamp key 8. The bound is published in
    the vocabulary policy, not hard-coded, so the factory reads it from there.
  - On a two-token line, the vocabulary checker holds only the vocabulary tokens: the tier on
    `Test-tier: <covers-id> <tier>`, the level and its reason on `Risk: high <reason>`. The
    covers id is the coverage check's, which also checks that each `Covers:` id has exactly one
    `Test-tier:` line and that each `Test-tier:` id is on the `Covers:` line.
  - The factory does not seed the check table. The PR body is the kit's, and `/implement` alone
    writes it. Its rows come from the ticket's `Test-tier:` lines: Requirement and Test tier
    are filled from the stamp, and Result and Evidence by the implementer. One writer per
    artifact. The factory operator confirmed this (relayed by D-08, 2026-10-23).

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

None open. The three this PRD was written with were settled with D-08 and moved to §8.

## 10. Dogfood plan

Six tickets, in slice order.
- The kit's own PRs carry check tables from slice 2's landing, and decision logs from slice 6's.
- The first wave after slice 6 is the measure. The operator should find each inside ruling in a
  `D-<n>` row rather than in a PR comment. `/retro` can count decisions per PR from
  `finding.triage data.scope=inside`, and outward items from `review.verdict data.outward`.
- The software factory starts its PRD 3 (`Risk:` and `Test-tier:` stamps) on slice 1's tag.
