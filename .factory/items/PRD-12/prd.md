---
id: PRD-12
type: prd
title: The kit's planning skills defer to the factory where it exists
parent: D-02
stage: approved
created: 2026-10-28
updated: 2026-10-29
stages:
  - {stage: draft, at: 2026-10-28T12:26Z}
  - {stage: review, at: 2026-10-28T12:50Z}
  - {stage: approved, at: 2026-10-29T12:08Z}
approved_by: "agranado"
approved_at: 2026-10-29T12:08Z
---


# PRD-12 · The kit's planning skills defer to the factory where it exists

## 1. Objective

In a repository that plans in the software factory, have the kit's `/to-prd` and `/to-tickets`
hand planning to the factory instead of publishing to the forge's issue tracker, and have the
kit's stamp reader read a factory ticket's stamp, so that the factory owns idea → ticket, the
kit's chain builds the ticket it is handed, and a repository with no factory keeps today's
chain unchanged.

**Problem.** D-02 and the software factory's D-08 agreed a boundary on 2026-10-23, and the
operator accepted it: the factory owns idea → ticket (its item model, its gates, its planning
skills), and the kit owns ticket → landed change (`/implement`, `/review-pr`, `/pr-iterate`,
`/merge-train`, `/worktree-cleanup`, `/retro`, plus the trace, the invariants and the ticket
contract). Nothing in the kit knows about that boundary yet. In a repository with a factory
project, `/to-prd` and `/to-tickets` still publish PRDs and tickets as forge issues, so the same
plan can exist twice, once as factory items and once as issues, and the two drift. And the
kit's stamp reader fetches a ticket's stamp only by issue number. A factory ticket is a file in
the repository with an id like `T-07`, and the reader cannot read it. So `/implement` cannot
read the tier, label, risk and coverage of the ticket the factory hands it, except by keeping a
mirrored forge issue. The kit's skill dispatcher already works around this with a stand-in
tracker that feeds a file to the reader.

**Solution.** This is D-02's K7. It sits outside the Q7 order and depends on the factory's
IN-01 (§9). Two changes. First, the **stamp reader** accepts a **factory ticket id** besides an
issue number. It reads that ticket's file from the checkout's factory folder, lifts stamp lines
from its body only (never from its frontmatter), checks them with the same vocabulary checker
and bound, and keeps its exit codes. `/implement` reads a factory ticket's stamp through it,
with one call, as it does an issue's. Second, the two **planning skills**, `/to-prd` and
`/to-tickets`, **defer** in a **factory project**. Their first step finds the factory's project
manifest, and if it is there, they publish nothing to the forge, write no trace event, and end
with a hand-off naming the factory as where PRDs and tickets are written. Only the operator's
own message can override that. `/grill-me`, `/grill-with-docs` and `/design-brief` do not defer:
they publish no PRD or ticket. A repository with no factory manifest, which is every consumer
bootstrap makes today, sees no change.

**The test of done.** In a fixture repository with a factory manifest and a ticket item `T-07`
stamped `Tier: mechanical`, `Label: ready-for-agent` and `Risk: low`, and with `class: toil` in
its frontmatter, `sh scripts/stamp.sh T-07` prints those three lines and no `Class:` line, makes
no tracker call, and exits 0. In the same repository, a `/to-tickets` run ends at the hand-off,
with no `gh issue create` and no `ticket.write` event. With the manifest removed, the same run
publishes as it does today.

## 2. Users and scenarios

**U1 — the operator** of a repository that plans in the factory, who wants each plan to exist
once, as factory items. **U2 — `/implement`**, the kit's session that builds one ticket and
reads its stamp first. **U3 — a consumer with no factory**, who gets the generic chain (operator,
2026-10-23, "a consumer with no factory gets the generic chain").

Stories:

1. As the operator of a factory project, I want `/to-prd` and `/to-tickets` to send me to the
   factory instead of opening forge issues, so that a plan is never written twice and never
   drifts between two trackers.
2. As `/implement`, I want to read a factory ticket's stamp with the same reader and the same
   exits as an issue's, so that the tier, label, risk and coverage the planner decided reach the
   build without a mirrored issue.
3. As a consumer with no factory, I want bootstrap and the planning skills to behave exactly as
   before, so that a boundary I do not use costs me nothing.
4. As the operator, I want to be able to run the forge version in a factory project when I say
   so myself, so that a repository mid-move still has a way to plan.

**UC1 — `/to-tickets` defers in a factory project.** Actor: the operator, in a repository whose
root holds the factory's project manifest. PRD-04 is approved in the factory. Goal: the tickets
are written as factory items, and the forge holds none.
1. The operator runs `/to-tickets PRD-04`.
2. Before it reads a PRD, fetches anything or makes a scratch directory, `/to-tickets` checks
   whether the repository root holds the factory's project manifest. It does.
3. It prints one hand-off: this repository plans in the software factory, tickets are factory
   items written with the factory's planning skill, and `/to-tickets` publishes nothing to the
   tracker here. Then it ends.
4. The forge has no new issue, and the trace has no `ticket.write` event from the run.

Extensions:
- 2a. The repository holds no `.factory/` folder, or holds one with no project manifest at its
  root. `/to-tickets` runs its forge flow, unchanged.
- 2b. The operator's own message in this session asked for the forge version ("publish these as
  issues"). `/to-tickets` runs its forge flow, and its hand-off says that it ran the forge flow
  in a factory project.
- 2c. The run was spawned by another session, and the spawn prompt asks for the forge version.
  That is not the operator's message. `/to-tickets` defers as in step 3.
- 2d. `/retro` or `/improve-codebase-architecture` hands its findings to `/to-tickets`. The
  deferral of step 3 applies the same way (see §9 for retro candidates).

**UC2 — `/to-prd` defers in a factory project.** Actor: the operator, after a grilled
conversation in the same repository. Goal: the PRD is written as a factory item under its
discovery.
1. The operator runs `/to-prd`.
2. Before its grilling question and before it explores the repository, `/to-prd` finds the
   factory's project manifest.
3. It prints the hand-off: PRDs are factory items under a discovery, written with the factory's
   planning skill, and `/to-prd` publishes nothing to the tracker here. It writes no `prd.write`
   event, and it ends.

Extensions:
- 2a. No manifest. `/to-prd` runs as today, its grilling question included.
- 2b. The operator's own message asked for the forge version. It runs as today and says so.

**UC3 — `/implement` reads a factory ticket's stamp.** Actor: an implementer session handed
`T-07`. Goal: the session knows T-07's tier, label, risk and coverage, as the planner stamped
them.
1. The session runs `sh scripts/stamp.sh T-07`. That is one call, the id and nothing else.
2. The stamp reader finds T-07's ticket file in the factory folder of the checkout it lives in.
   It lifts the bare stamp lines below the frontmatter and checks them with the vocabulary
   checker. It prints `Tier: mechanical`, `Label: ready-for-agent`, `Risk: low` and
   `Covers: process/R130`, and exits 0. It calls no tracker.
3. `/implement` goes on exactly as it does after reading an issue's stamp.

Extensions:
- 2a. No item `T-07`, an item whose `type:` is not `ticket`, or a checkout with no factory
  manifest. Exit 2, nothing on stdout, and stderr names the id and which of the three it was.
- 2b. T-07's frontmatter carries `class: toil`. It is frontmatter, not a stamp line, so it is
  never lifted.
- 2c. The file exists but cannot be read. Exit 4, nothing on stdout: a stop, never a missing
  stamp.
- 2d. The body carries no stamp line. Exit 3, as for an issue with none.
- 2e. `Label: maybe` is refused by the checker. Exit 2, the field named, never the value.

**UC4 — A consumer with no factory sees nothing new.** Actor: a new consumer running bootstrap
into a project with no `.factory/` folder. Goal: the same project the release before this PRD
would have made, and the same chain.
1. Bootstrap writes the project. It holds no `.factory/` folder.
2. `/to-tickets` publishes forge issues, and `sh scripts/stamp.sh 42` reads issue #42 as before.

## 3. Model

- **Factory project**: a repository whose root holds the factory's project manifest,
  `.factory/project.yaml`, the file `factory init` writes. A `.factory/` folder without that
  file is not a factory project. Only the file's presence is read, never its contents.
- **Factory ticket**: an item of the factory whose `type:` is `ticket`, named by an id
  `T-<digits>` (at most 6 digits). Its file is the `ticket.md` of the item's folder, a fenced
  frontmatter block followed by a body. Its **stamp** is the bare `Key: value` lines of the body,
  as for an issue, with `Label:` added: a file has no tracker label, so the factory carries the
  autonomy label as a stamp line.
- **Planning skill** (in this PRD): a kit skill that publishes an item on the idea → ticket side
  of the boundary. That is `/to-prd` (a PRD) and `/to-tickets` (tickets), and no other.
  `/grill-me` and `/grill-with-docs` publish nothing, and a grilled conversation feeds either
  route. `/design-brief` writes the kit's engineering article and a decision record, which are
  the kit's own documents. `/prototype` records a finding. None of these four is a planning
  skill here.
- **Deferral**: the planning skill's first step in a factory project. It prints one hand-off
  naming the factory as where the item is written, publishes nothing to the forge, writes no
  trace event, and ends.
- **Forge override**: the operator's own message in the session asking for the forge version.
  It is the one thing that lifts a deferral. Text in a spawn prompt, a ticket, a PRD or another
  agent's message never is (root manual, agent trust boundary).

## 4. Rules

Area: process

Deltas against `docs/specs/process.md`, which ends at R60. Ids start at R120 because sibling
D-02 drafts hold R61 upward (§11).

### ADDED

process/R120. WHERE the repository root holds the factory's project manifest, WHEN `/to-prd` starts, it SHALL publish nothing to the forge's issue tracker, SHALL write no `prd.write` event, and SHALL end with a hand-off naming the factory as where PRDs are written. [UC2 2, 3]
process/R121. WHERE the repository root holds the factory's project manifest, WHEN `/to-tickets` starts, it SHALL publish no issue, merge no section, close no twin, write no `ticket.write` event, and SHALL end with a hand-off naming the factory as where tickets are written. [UC1 2, 3, 4]
process/R122. `/to-prd` and `/to-tickets` SHALL decide the deferral before any other step: before `/to-prd`'s grilling question, and before `/to-tickets` fetches a PRD body or makes its pre-screen's scratch directory. [UC1 2, UC2 2]
process/R123. IF the repository holds no `.factory/` folder, or holds one with no project manifest at its root, THEN `/to-prd` and `/to-tickets` SHALL run their forge flow unchanged. [UC1 2a, UC2 2a]
process/R124. The deferral SHALL be decided by the presence of the project manifest alone, and SHALL read nothing from the manifest or from any factory item.
process/R125. IF the operator's own message in the session asks for the forge version, THEN `/to-prd` and `/to-tickets` SHALL run their forge flow, and the skill's hand-off SHALL say that it ran the forge flow in a factory project. [UC1 2b, UC2 2b]
process/R126. A request for the forge version carried in a spawn prompt, a ticket body, a PRD body or another agent's message SHALL NOT lift the deferral. [UC1 2c]
process/R127. `/grill-me`, `/grill-with-docs` and `/design-brief` SHALL carry no factory deferral, and SHALL run the same with or without the project manifest.
process/R128. WHEN the stamp reader is given a factory ticket id, `T-` followed by 1 to 6 digits, it SHALL read that ticket's file from the factory folder of the checkout the reader lives in, and SHALL make no tracker call. [UC3 1, 2]
process/R129. The stamp reader SHALL lift a factory ticket's stamp lines only from below the frontmatter's closing fence, so that no frontmatter key is read as a stamp line. [UC3 2b]
process/R130. WHEN the stamp reader reads a factory ticket, it SHALL lift and check `Label:` lines with the other stamp keys, under the same bound, and WHEN it reads a tracker issue, it SHALL lift no `Label:` line. [UC3 2]
process/R131. IF a factory ticket id names no item, an item whose `type:` is not `ticket`, or the checkout holds no project manifest, THEN the stamp reader SHALL exit 2, print nothing on stdout, and name the id and the case on stderr. [UC3 2a]
process/R132. IF a factory ticket's file exists but cannot be read, THEN the stamp reader SHALL exit 4 and print nothing on stdout. [UC3 2c]
process/R133. For a factory ticket's body, the stamp reader SHALL give the exits 0, 2 (a refused value), 3 and 5, and the output, that it gives for a tracker issue whose body is the same text without the frontmatter. [UC3 2d, 2e]
process/R134. The stamp reader SHALL accept as its one argument only digits or a factory ticket id, and SHALL refuse anything else as a usage error, exit 2.
process/R135. WHEN `/implement` is handed a factory ticket id, it SHALL read the ticket's stamp with the one call `sh scripts/stamp.sh T-<n>`, and SHALL treat each exit as it does for an issue. [UC3 1, 3]
process/R136. WHEN bootstrap stamps a project that holds no `.factory/` folder, it SHALL write no `.factory/` folder, and the stamped project SHALL pass the kit's end-to-end bootstrap acceptance test as it did before this PRD. [UC4 1, 2]
process/R137. WHEN the release that ships R128 to R134 lands, `UPDATING.md` SHALL tell a consumer that the stamp reader now accepts a factory ticket id, and that its behaviour for an issue number is unchanged.

## 5. Slices (vertical, demoable, in order)

Slice 1 moves `scripts/stamp.sh`, which `VERSION` lists, so it is a shared-layer release.
Slices 2 and 3 move skills only, which belong to the release's non-manifest half: the next
release's `VERSION` history note lists them. Slice 1 waits on §9's first question (the
open-issue gate of `/to-tickets` rule 12). Slices 2 and 3 wait on its second.

**Slice 1 — the stamp reader reads a factory ticket, and `/implement` uses it (shared-layer
release).** The receiving end first: the kit can build a factory ticket before anything sends
planning there.
- *Covers:* process/R128, process/R129, process/R130, process/R131, process/R132,
  process/R133, process/R134, process/R135, process/R137.
- *Also:* the glossary gains factory project and factory ticket. The release bumps `VERSION`'s
  minor, writes `UPDATING.md`'s entry, re-captures the transcripts `tests/docs-demo.sh` quotes,
  and lands only once its merge commit carries the `v<version>` tag (the kit's ADR-0015,
  ADR-0025).
- *Accept:* `tests/stamp.test.sh`, with a fixture factory folder and a stand-in tracker that
  fails if it is called, prints UC3's four lines for `T-07`, and no `Class:` line for its
  frontmatter's `class: toil`. It exits 2 on each case of 2a, 4 on an unreadable file, 3 on a
  body with no stamp, 5 on 9 `Label:` lines, and 2 on `T-1234567` and on `t-07`. The same body
  given as an issue prints the same lines except `Label:`. A skill-text suite holds
  `/implement`'s one-call line for a factory ticket id.

**Slice 2 — `/to-tickets` defers in a factory project.**
- *Covers:* process/R121, process/R122, process/R123, process/R124, process/R125,
  process/R126, process/R127, process/R136.
- *Blocked by:* slice 1.
- *Also:* one decision record: where a factory project exists, the kit's planning skills defer
  to it, and only the operator's own message overrides that. The glossary gains deferral.
- *Accept:* `tests/spec-skills.test.sh` holds `/to-tickets`' deferral as its first step, before
  the pre-screen, with the hand-off's words, the override's "operator's own message", and the
  absence of any publish or trace call on that path. It also holds that `/grill-me`,
  `/grill-with-docs` and `/design-brief` name no deferral. `tests/kit-demo.sh` passes
  unchanged, and its stamped project holds no `.factory/` folder.

**Slice 3 — `/to-prd` defers in a factory project.**
- *Covers:* process/R120, process/R122, process/R123, process/R125, process/R126.
- *Blocked by:* slice 2.
- *Accept:* `tests/spec-skills.test.sh` holds `/to-prd`'s deferral ahead of its grilling
  question, its hand-off, and no `prd.write` on that path.

## 6. Non-goals (this PRD)

- **The kit writing factory items** (running `factory new` from `/to-prd` or `/to-tickets`):
  *never*. A factory PRD needs a discovery parent, and the item model is the factory's. New
  planning features land only in the factory (operator, 2026-10-23).
- **The factory's own planning skills**: *never here*. They are D-08's.
- **The stamp reader calling `factory stamp`**: *never*. The kit's core is `sh` and `git` only,
  and runs before a project has chosen any tool.
- **A trace event for a deferral**: *later*. A new outcome on `prd.write` or `ticket.write` is a
  change to the trace's kind table, and ADR-0024 is at its amendment cap. Reopen when `/retro`'s
  chain-health question needs to count deferrals.
- **The rest of the chain naming a factory ticket** (the trace subject, the PR's implement line,
  the landing script's `--ticket`): *later*. See §9.
- **Retiring the skill dispatcher's stand-in tracker** for `--ticket-file`: *later*. That is a
  kit-only cleanup once slice 1 is tagged, and it is the dispatcher's own ticket.
- **Bootstrap copying a `.factory/` folder into a consumer**: *never here*. That is this repo's
  inbox item IN-01, which is unrelated to the factory's IN-01.
- **Deferral in `/grill-me`, `/grill-with-docs`, `/design-brief`, `/prototype`**: *never*, as
  long as they publish no PRD or ticket (§3).

## 7. Technical constraints and testing

- POSIX `sh` and `git` only in the stamp reader, as today. It finds the factory folder from the
  repository root the script lives in, never the caller's working directory, as it already does
  for the vocabulary checker.
- **Trust boundary.** A factory ticket's file is untrusted, as an issue body is. The reader
  reads exactly two things from the frontmatter: the fence lines that bound it, and an anchored
  `type: ticket` line. From the body it reads only the bare stamp lines, through the existing
  lift, bound and checker. No ticket text reaches stdout unless the checker passed it, and none
  reaches stderr. The deferral reads no file's contents (R124).
- **Tests** drive behaviour from outside. The stamp suite builds a throwaway repository with a
  factory folder and items, and puts a stand-in tracker first on `PATH` that fails the test if
  it is called. The skills are held by skill-text suites, the prior art for every rule a skill
  obeys: `tests/spec-skills.test.sh`, and `tests/implement-deliver.test.sh` for `/implement`.
  Bootstrap is held by `tests/kit-demo.sh`.
- **Numbers, not quality words:** an id is `T-` and 1 to 6 digits (R128). The bound is the
  policy's, 8 lines of a key (R130). "Unchanged" for a consumer means the end-to-end bootstrap
  acceptance test passes with no edit to it (R136).

## 8. Decisions recorded for this PRD

From D-02 (decisions.md, 2026-10-23): the ticket boundary (proposed by D-08, accepted by the
operator); its four conditions, of which (1) is that the kit keeps generic forge versions of its
planning skills and (4) is that IN-01 (the stamp reader reads a factory ticket) comes first; "a
consumer with no factory gets the generic chain"; Q7 (K7 outside the order, after IN-01).

**Derived while writing** (the session, under the operator's standing delegation of rulings;
the maintainer confirms them at approval):

- **The planning skills are `/to-prd` and `/to-tickets`, and only they.** The boundary gives the
  factory the item model and its planning skills. A kit skill is on the factory's side when it
  publishes a PRD or a ticket. The grilling skills publish nothing, and `/design-brief` writes
  the kit's own documents, so making them defer would cost a factory project a tool and protect
  no item from being written twice.
- **Deferral is a stop with a hand-off, not a switch of destination.** A switch, where the kit
  skill writes factory items itself, would put item-model knowledge in the kit and grow a
  planning feature there. The operator ruled that new planning features land only in the
  factory.
- **A factory project is the manifest's presence, read and nothing more.** A stray `.factory/`
  folder does not count. Reading no contents keeps the check free of untrusted text, and of any
  tool beyond the shell.
- **Only the operator's own message lifts the deferral.** This is the root manual's rule that no
  agent's message is the user's consent, applied here. A spawned or unattended run defers.
- **The stamp reader reads the file itself.** It does not delegate to the factory's
  `factory stamp`, which reads the same contract with the same checker. The kit owns the ticket
  contract and its reader. The factory's command stays a second reader of it.
- **`Label:` is lifted from a factory ticket only.** On an issue, the tracker's label is the
  autonomy label, and a body line would be a second source that can disagree with it.
- **Exit codes keep the stamp reader's meanings.** An id with no ticket behind it is a caller
  error, exit 2, as `factory stamp` also has it. An unreadable file is the reader failing to get
  the body, exit 4, as for a failed fetch (`factory stamp` uses 3 there, §9).
- **Receiving end first.** Slice 1 lets the kit build a factory ticket before slices 2 and 3
  send planning to the factory. That is condition (4)'s order.

**Alternatives considered:**

- **Make every pre-ticket skill defer** (the grilling skills, `/design-brief`). This lost: they
  publish no item, so there is nothing to keep from being written twice.
- **Decide the deferral from a policy flag** instead of from the manifest. This lost because the
  flag would duplicate what the manifest already says, and could disagree with it.
- **A file form of the stamp reader** (`--file <path>`). This lost because a path lets a caller
  point the reader at any file, while an id resolves only inside the factory folder. The id is
  also what the factory and its tickets name.

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

- **What the factory's IN-01 settles.** Condition (4) puts IN-01 first, and its state cannot be
  known from this repository. What this PRD needs from it: a stable ticket file layout (one
  folder per item, a `ticket.md` that opens with a `---` fenced frontmatter carrying `type:
  ticket`), the id shape `T-<digits>`, and the stamp key set, `Label:` included, recorded as part
  of the ticket contract. The installed `factory` 0.1.0 already has `factory stamp <T-id>`, with
  the stamp reader's exits except 4, so IN-01 may already have shipped.
  - Options: IN-01 is shipped as `factory stamp`, and slice 1 starts. Or IN-01 changes the
    layout or the key set, and slice 1 waits for it.
  - Next step: a question to agranado, relayed to the D-08 session, before `/to-tickets` runs on
    this PRD. Slice 1 is blocked on the answer.
- **The factory ships no PRD- or ticket-writing skill yet.** `factory install-skill` writes only
  `factory` and `factory-discover`. Deferring `/to-tickets` now would leave a factory project
  with no skill that stamps tickets and runs the quiz.
  - Options: defer anyway, and name `factory-discover` and the `factory` skill in the hand-off;
    hold slices 2 and 3 until D-08's planning skills exist; or name whatever skill the factory's
    guide lists at run time.
  - Next step: a question to the D-08 session. Slices 2 and 3 are blocked on it. MVP default:
    hold them.
- **The chain beyond the stamp names a ticket by issue number.** The trace subject
  `ticket:#<N>`, the PR's `<!-- implement: ticket=#<N> -->` line, the landing script's
  `--ticket` and a PR's closing reference all expect `#<N>`.
  - Options: accept `T-<n>` in each of them, as a follow-up PRD; or keep a mirrored forge issue
    per factory ticket, as this repository does today.
  - Next step: a `planner` ticket after slice 1 lands. MVP default: the mirrored issue.
- **This repository is itself a factory project.** Once slice 2 lands, `/to-tickets` defers here,
  while the kit's chain still lands by issue number (previous question).
  - Options: the operator's override on each run; a kit-only opt-out; or answer the previous
    question first.
  - Next step: a question to agranado at approval. MVP default: the operator's override.
- **Retro candidates in a factory project** (condition (3), the retro → to-tickets handoff
  format as a contract). A retro's candidates have no PRD. The factory has `factory inbox add`
  and toil tickets.
  - Options: `/to-tickets` defers as for a PRD; or the hand-off names `factory inbox add` for
    each candidate.
  - Next step: settle it with the handoff contract in the D-08 session. MVP default: defer as
    for a PRD.

## 10. Dogfood plan

Three tickets in slice order. Slice 1's tag lets the factory's tickets in this repository be
built by their `T-<n>` id rather than by a mirrored issue, once the chain's naming question (§9)
is answered. Slices 2 and 3 are first run here under the operator's override (§9). The first
factory ticket built through `sh scripts/stamp.sh T-<n>` is the measure.

## 11. Further notes

Requirement ids start at process/R120 so that they do not collide with the sibling D-02 drafts
(PRD-08 to PRD-13 hold process/R61 upward and runtime/R52 upward). They are re-based at
approval if they collide with whatever has landed by then.
