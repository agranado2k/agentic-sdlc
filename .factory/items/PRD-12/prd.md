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
IN-01, which has shipped as `factory stamp` (§8, 2026-10-31). Two changes. First, the **stamp
reader** accepts a **factory ticket id** besides an issue number. It never parses a factory
ticket's file: in a factory project it runs the factory's own reader, `factory stamp <T-id>`,
passes what that prints through the kit's own lift, bound and vocabulary checker again, and
keeps the exits the two readers share. Where the `factory` binary is absent it says so and
sends the caller back to the ticket's forge issue. `/implement` reads a factory ticket's stamp
through it, with one call, as it does an issue's. Second, the two **planning skills**, `/to-prd`
and `/to-tickets`, **defer by name** to the factory's own planning skill, `factory-prd` or
`factory-tickets`, in a **factory project** where that skill is installed. Their first step
looks for the factory's project manifest and for the factory skill's `SKILL.md`. With both
there, they publish nothing to the forge, write no trace event, and end with a hand-off naming
the factory skill. With the manifest there and the skill missing, they run as today and say
once that `factory install-skill` would add the factory one. Only the operator's own message
can override a deferral. `/grill-me`, `/grill-with-docs` and `/design-brief` do not defer: they
publish no PRD or ticket. A repository with no factory manifest, which is every consumer
bootstrap makes today, sees no change.

**The test of done.** In a fixture repository with a factory manifest, a stand-in `factory`
first on `PATH` that prints `Tier: mechanical`, `Label: ready-for-agent` and `Risk: low` for
`factory stamp T-07`, and a stand-in tracker that fails if it is called,
`sh scripts/stamp.sh T-07` prints those three lines, makes no tracker call, and exits 0. With
the stand-in `factory` removed from `PATH`, the same call exits 3 and names the absent binary.
In the same repository, with a `factory-tickets` skill installed, a `/to-tickets` run ends at
the hand-off naming it, with no `gh issue create` and no `ticket.write` event. With the skill
removed it publishes as today and names `factory install-skill` once; with the manifest
removed it publishes as today and names nothing.

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
git top level holds the factory's project manifest, with the factory's `factory-tickets` skill
installed. PRD-04 is approved in the factory. Goal: the tickets are written as factory items,
and the forge holds none.
1. The operator runs `/to-tickets PRD-04`.
2. Before it reads a PRD, fetches anything or makes a scratch directory, `/to-tickets` checks
   whether the git top level holds the factory's project manifest, and whether the
   `factory-tickets` skill's `SKILL.md` exists. Both do.
3. It prints one hand-off: this repository plans in the software factory, tickets are written
   with `/factory-tickets`, and `/to-tickets` publishes nothing to the tracker here. Then it
   ends.
4. The forge has no new issue, and the trace has no `ticket.write` event from the run.

Extensions:
- 2a. The repository holds no `.factory/` folder, or holds one with no project manifest at its
  git top level. `/to-tickets` runs its forge flow, unchanged, and names no factory skill.
- 2b. The operator's own message in this session asked for the forge version ("publish these as
  issues"). `/to-tickets` runs its forge flow, and its hand-off says that it ran the forge flow
  in a factory project.
- 2c. The run was spawned by another session, and the spawn prompt asks for the forge version.
  That is not the operator's message. `/to-tickets` defers as in step 3.
- 2d. `/retro` or `/improve-codebase-architecture` hands its findings to `/to-tickets`. The
  deferral of step 3 applies the same way (see §9 for retro candidates).
- 2e. The manifest is there and the `factory-tickets` skill is not installed. `/to-tickets`
  runs its forge flow as today, and says once, at its start, that this is a factory project
  and that `factory install-skill` would add the factory's `factory-tickets` skill.

**UC2 — `/to-prd` defers in a factory project.** Actor: the operator, after a grilled
conversation in the same repository. Goal: the PRD is written as a factory item under its
discovery.
1. The operator runs `/to-prd`.
2. Before its grilling question and before it explores the repository, `/to-prd` finds the
   factory's project manifest and the `factory-prd` skill's `SKILL.md`.
3. It prints the hand-off: PRDs are factory items under a discovery, written with
   `/factory-prd`, and `/to-prd` publishes nothing to the tracker here. It writes no
   `prd.write` event, and it ends.

Extensions:
- 2a. No manifest. `/to-prd` runs as today, its grilling question included, and names no
  factory skill.
- 2b. The operator's own message asked for the forge version. It runs as today and says so.
- 2c. The manifest is there and the `factory-prd` skill is not installed. `/to-prd` runs as
  today, and says once, at its start, that `factory install-skill` would add the factory's
  `factory-prd` skill.

**UC3 — `/implement` reads a factory ticket's stamp.** Actor: an implementer session handed
`T-07`. Goal: the session knows T-07's tier, label, risk and coverage, as the planner stamped
them.
1. The session runs `sh scripts/stamp.sh T-07`. That is one call, the id and nothing else.
2. The stamp reader finds that the git top level of the checkout it lives in holds the
   factory's project manifest, and runs `factory stamp T-07` there. It reads no ticket file
   itself. It passes the lines `factory stamp` printed through its own lift, bound and
   vocabulary checker. It prints `Tier: mechanical`, `Label: ready-for-agent`, `Risk: low` and
   `Covers: process/R130`, and exits 0. It calls no tracker.
3. `/implement` goes on exactly as it does after reading an issue's stamp.

Extensions:
- 2a. The checkout is no factory project, or `factory stamp` exits 2 (no such ticket, or a
  refused value). Exit 2, nothing on stdout, and stderr names the id and the case.
- 2b. T-07 carries a `Class:` line or a frontmatter `class:` key. `factory stamp` reads
  neither, so neither is printed.
- 2c. `factory stamp` exits 3 (no stamp line, or no checker). Exit 3, as for an issue with
  none. There is no exit 4: nothing is fetched.
- 2d. `factory stamp` exits 5 (too many lines of a key). Exit 5.
- 2e. A line `factory stamp` printed is refused by the kit's own checker. Exit 2, the field
  named, never the value.
- 2f. The `factory` binary is not on `PATH`. Exit 3, nothing on stdout, and one stderr line
  names the absent binary and the forge-issue path. `/implement`, holding the ticket's forge
  issue number from its hand-off, says once that it fell back and reads
  `sh scripts/stamp.sh <N>`. Holding none, it takes exit 3's path as for an issue.
- 2g. The session is handed a temporary id, `T-~` and hex, before `factory renumber`.
  `/implement` refuses it and reads no stamp: the id is not stampable.

**UC4 — A consumer with no factory sees nothing new.** Actor: a new consumer running bootstrap
into a project with no `.factory/` folder. Goal: the same project the release before this PRD
would have made, and the same chain.
1. Bootstrap writes the project. It holds no `.factory/` folder.
2. `/to-tickets` publishes forge issues, and `sh scripts/stamp.sh 42` reads issue #42 as before.

## 3. Model

- **Factory project**: a repository whose git top level holds the factory's project manifest,
  `.factory/project.yaml`, the file `factory init` writes (agreed with D-08, 2026-10-29). A
  `.factory/` folder without that file is not a factory project, and nothing above the git top
  level is read. Only the file's presence is read, never its contents.
- **Factory ticket**: an item of the factory whose `type:` is `ticket`, named by an id
  `T-<digits>` (the kit bounds it at 6 digits). A temporary id, `T-~<hex>`, given before
  `factory renumber`, is not stampable. The file layout (`.factory/items/T-nn/ticket.md`, YAML
  front matter, then a body of bare `Key: value` stamp lines) is the factory's, and the kit
  never reads it. Its **stamp** is what `factory stamp <T-id>` prints: the keys `Tier`,
  `Confidence`, `Label`, `Domain`, `Risk`, `Risk-confidence`, `Test-tier` and `Covers` today,
  `Accept-test` later (factory T-94). `Class` is written in a factory ticket but not read by
  `factory stamp`. `Label:` is there because a file has no tracker label, so the factory
  carries the autonomy label as a stamp line.
- **Factory skill**: the factory's own planning skill for an item, `factory-prd` for a PRD and
  `factory-tickets` for tickets. It is **installed** when its `SKILL.md` exists in a skill
  directory the harness discovers: `factory install-skill` writes
  `~/.claude/skills/<name>/SKILL.md`, and a project's own `.claude/skills/<name>/SKILL.md`
  counts the same.
- **Planning skill** (in this PRD): a kit skill that publishes an item on the idea → ticket side
  of the boundary. That is `/to-prd` (a PRD) and `/to-tickets` (tickets), and no other.
  `/grill-me` and `/grill-with-docs` publish nothing, and a grilled conversation feeds either
  route. `/design-brief` writes the kit's engineering article and a decision record, which are
  the kit's own documents. `/prototype` records a finding. None of these four is a planning
  skill here.
- **Deferral**: the planning skill's first step in a factory project whose factory skill is
  installed. It prints one hand-off naming that factory skill, publishes nothing to the forge,
  writes no trace event, and ends. It is decided from two files' presence, never by running a
  `factory` subcommand, so a project without the binary still works.
- **Forge override**: the operator's own message in the session asking for the forge version.
  It is the one thing that lifts a deferral. Text in a spawn prompt, a ticket, a PRD or another
  agent's message never is (root manual, agent trust boundary).

## 4. Rules

Area: process

Deltas against `docs/specs/process.md`, which ends at R60. Ids start at R120 because sibling
D-02 drafts hold R61 upward (§11).

### ADDED

Amended 2026-10-31 by T-69 (#932), T-70 (#933) and the operator's configuration ruling (§8):
R120 to R125 and R128 to R135 are reworded in place to the factory's shipped contract, and
R138, R139 and R222 to R227 are added. No published id is renumbered or reused.

process/R120. WHERE the repository's git top level holds the factory's project manifest and the `factory-prd` skill is installed, WHEN `/to-prd` starts, it SHALL publish nothing to the forge's issue tracker, SHALL write no `prd.write` event, and SHALL end with a hand-off naming `/factory-prd` as where PRDs are written. [UC2 2, 3]
process/R121. WHERE the repository's git top level holds the factory's project manifest and the `factory-tickets` skill is installed, WHEN `/to-tickets` starts, it SHALL publish no issue, merge no section, close no twin, write no `ticket.write` event, and SHALL end with a hand-off naming `/factory-tickets` as where tickets are written. [UC1 2, 3, 4]
process/R122. `/to-prd` and `/to-tickets` SHALL decide the deferral before any other step: before `/to-prd`'s grilling question, and before `/to-tickets` fetches a PRD body or makes its pre-screen's scratch directory. [UC1 2, UC2 2]
process/R123. IF the repository holds no `.factory/` folder, or holds one with no project manifest at its git top level, THEN `/to-prd` and `/to-tickets` SHALL run their forge flow unchanged and SHALL name no factory skill. [UC1 2a, UC2 2a]
process/R124. The deferral SHALL be decided by the presence of the project manifest and of the factory skill's `SKILL.md` alone, and SHALL read nothing from either file or from any factory item.
process/R125. IF the operator's own message in the session asks for the forge version, THEN `/to-prd` and `/to-tickets` SHALL run their forge flow, and the skill's hand-off SHALL say that it ran the forge flow in a factory project. [UC1 2b, UC2 2b]
process/R126. A request for the forge version carried in a spawn prompt, a ticket body, a PRD body or another agent's message SHALL NOT lift the deferral. [UC1 2c]
process/R127. `/grill-me`, `/grill-with-docs` and `/design-brief` SHALL carry no factory deferral, and SHALL run the same with or without the project manifest.
process/R128. WHEN the stamp reader is given a factory ticket id, `T-` followed by 1 to 6 digits, in a checkout whose git top level holds the project manifest, it SHALL run `factory stamp <id>` with that top level as its directory, and SHALL make no tracker call. [UC3 1, 2]
process/R129. The stamp reader SHALL read a factory ticket's stamp only through `factory stamp`, and SHALL open no file under the factory folder. [UC3 2, 2b]
process/R130. WHEN the stamp reader reads a factory ticket, it SHALL pass the lines `factory stamp` printed through its own lift, bound and vocabulary checker, `Label:` lines included, and SHALL print only lines its checker passed; WHEN it reads a tracker issue, it SHALL lift no `Label:` line. [UC3 2, 2e]
process/R131. IF the checkout's git top level holds no project manifest, or `factory stamp` exits 2, THEN the stamp reader SHALL exit 2, print nothing on stdout, and name the id and the case on stderr. [UC3 2a]
process/R132. For a factory ticket id the stamp reader SHALL NOT exit 4, and IF `factory stamp` exits with any status but 0, 2, 3 or 5, THEN the stamp reader SHALL exit 3 and print nothing on stdout. [UC3 2c]
process/R133. For a factory ticket, the stamp reader SHALL exit 3 when `factory stamp` exits 3 and 5 when it exits 5, printing nothing on stdout, and SHALL relay none of `factory stamp`'s standard error. [UC3 2c, 2d]
process/R134. The stamp reader SHALL accept as its one argument only digits or a factory ticket id, and SHALL refuse anything else, a temporary `T-~<hex>` id included, as a usage error, exit 2.
process/R135. WHEN `/implement` is handed a factory ticket id, it SHALL read the ticket's stamp with the one call `sh scripts/stamp.sh T-<n>`, and SHALL treat each exit as it does for an issue. [UC3 1, 3]
process/R136. WHEN bootstrap stamps a project that holds no `.factory/` folder, it SHALL write no `.factory/` folder, and the stamped project SHALL pass the kit's end-to-end bootstrap acceptance test as it did before this PRD. [UC4 1, 2]
process/R137. WHEN the release that ships R128 to R134 lands, `UPDATING.md` SHALL tell a consumer that the stamp reader now accepts a factory ticket id, that it runs `factory stamp` in a factory project, and that its behaviour for an issue number is unchanged.
process/R138. IF the stamp reader is given a factory ticket id in a factory project and no `factory` binary is on `PATH`, THEN it SHALL exit 3, print nothing on stdout, and write one stderr line naming the absent binary and the forge-issue form, `sh scripts/stamp.sh <issue-number>`. [UC3 2f]
process/R139. WHEN the stamp reader exits 3 for an absent `factory` binary and `/implement` holds the ticket's forge issue number from its hand-off, `/implement` SHALL say once that it fell back to the forge issue and SHALL read the stamp with `sh scripts/stamp.sh <N>`; holding none, it SHALL take exit 3's path as for an issue. [UC3 2f]
process/R222. WHEN `/implement` is handed a temporary factory id, `T-~` followed by hex, it SHALL refuse it, read no stamp, and name `factory renumber` as what makes it stampable. [UC3 2g]
process/R223. IF the repository's git top level holds the project manifest and the factory skill for the planning skill's item is not installed, THEN `/to-prd` or `/to-tickets` SHALL run its forge flow as today and SHALL say once, at its start, that `factory install-skill` would add that factory skill. [UC1 2e, UC2 2c]
process/R224. `/to-prd` and `/to-tickets` SHALL decide the deferral without running any `factory` subcommand, so that a factory project without the `factory` binary runs them as R123 or R223 says.
process/R225. A factory skill SHALL count as installed when its `SKILL.md` exists under the user's `~/.claude/skills/<name>/` or the project's `.claude/skills/<name>/`, and under no other path.
process/R226. WHERE the repository's git top level holds the project manifest, every configuration value the kit reads that the factory also defines SHALL be read from the factory's key in `.factory/project.yaml`, and the kit's own policy file SHALL be read for that value only where the repository is not a factory project.
process/R227. WHERE the kit's policy reader reads a configuration value at a base ref, and R226 sends that value to `.factory/project.yaml`, the value SHALL be read from `.factory/project.yaml` at the same base ref through the policy reader, failing closed as the policy reader does.

## 5. Slices (vertical, demoable, in order)

Slice 1 moves `scripts/stamp.sh`, which `VERSION` lists, so it is a shared-layer release.
Slices 2 and 3 move skills only, which belong to the release's non-manifest half: the next
release's `VERSION` history note lists them. §9's first two questions are settled (§8,
2026-10-31), so no slice waits on the factory: slice 1 needs only `factory stamp`, which has
shipped, and slices 2 and 3 need no factory skill to exist, because a missing one is R223's
path. Slice 4 waits on PRD-08's policy reader.

**Slice 1 — the stamp reader runs `factory stamp` for a factory ticket, and `/implement` uses
it (shared-layer release).** The receiving end first: the kit can build a factory ticket before
anything sends planning there.
- *Covers:* process/R128, process/R129, process/R130, process/R131, process/R132,
  process/R133, process/R134, process/R135, process/R137, process/R138, process/R139,
  process/R222.
- *Also:* the glossary gains factory project and factory ticket. The release bumps `VERSION`'s
  minor, writes `UPDATING.md`'s entry, re-captures the transcripts `tests/docs-demo.sh` quotes,
  and lands only once its merge commit carries the `v<version>` tag (the kit's ADR-0015,
  ADR-0025).
- *Accept:* `tests/stamp.test.sh`, with a fixture factory project, a stand-in `factory` first
  on `PATH` that records its arguments and answers by exit, and a stand-in tracker that fails
  if it is called, prints UC3's four lines for `T-07` and exits 0, the stand-in run as
  `factory stamp T-07` from the fixture's git top level. It exits 2 when the stand-in exits 2
  and when the checkout has no manifest, 3 when the stand-in exits 3 and when it exits 7, 5
  when it exits 5, never 4, and 2 when the stand-in prints `Label: maybe`, naming the field and
  never the value; the stand-in's stderr never reaches the reader's. With no `factory` on
  `PATH` it exits 3 and its one stderr line names the absent binary and the forge-issue form.
  It exits 2 as a usage error on `T-1234567`, `t-07` and `T-~a1b2`, without running the
  stand-in. The same lines given as an issue body print the same except `Label:`. A skill-text
  suite holds `/implement`'s one-call line for a factory ticket id, its once-said fall-back to
  the forge issue on an absent binary, and its refusal of a temporary id naming
  `factory renumber`.

**Slice 2 — `/to-tickets` defers by name in a factory project.**
- *Covers:* process/R121, process/R122, process/R123, process/R124, process/R125,
  process/R126, process/R127, process/R136, process/R223, process/R224, process/R225.
- *Blocked by:* slice 1.
- *Also:* one decision record: where a factory project exists and its factory skill is
  installed, the kit's planning skills defer to that skill by name, and only the operator's own
  message overrides that; with the skill missing they run as today and name
  `factory install-skill` once. The glossary gains deferral and factory skill.
- *Accept:* `tests/spec-skills.test.sh` holds `/to-tickets`' deferral as its first step,
  before the pre-screen: its two presence checks (the manifest at the git top level, and
  `factory-tickets/SKILL.md` under the two skill roots of R225), the hand-off naming
  `/factory-tickets`, the once-said `factory install-skill` line for a missing skill, the
  override's "operator's own message", no `factory` subcommand anywhere on the path, and no
  publish or trace call on the deferring path. It also holds that `/grill-me`,
  `/grill-with-docs` and `/design-brief` name no deferral. `tests/kit-demo.sh` passes
  unchanged, and its stamped project holds no `.factory/` folder.

**Slice 3 — `/to-prd` defers by name in a factory project.**
- *Covers:* process/R120, process/R122, process/R123, process/R125, process/R126,
  process/R223, process/R224.
- *Blocked by:* slice 2.
- *Accept:* `tests/spec-skills.test.sh` holds `/to-prd`'s deferral ahead of its grilling
  question, its two presence checks, its hand-off naming `/factory-prd`, its once-said
  `factory install-skill` line for a missing skill, and no `prd.write` and no `factory`
  subcommand on that path.

**Slice 4 — in a factory project, a value the factory defines is read from its manifest.**
- *Covers:* process/R226, process/R227.
- *Blocked by:* PRD-08's policy reader (T-41), which must carry `.factory/project.yaml` in its
  judging set before R227 can read it at a base.
- *Accept:* a suite over the kit's configuration reads holds that, in a fixture factory
  project whose manifest and kit policy file disagree on a value both define, the kit reads the
  manifest's, at the working tree with no base and at the base ref with one; that the same
  fixture without the manifest reads the kit's policy file; and that a malformed manifest value
  at the base fails closed. PRD-14's adoption date is the first value held this way.

## 6. Non-goals (this PRD)

- **The kit writing factory items** (running `factory new` from `/to-prd` or `/to-tickets`):
  *never*. A factory PRD needs a discovery parent, and the item model is the factory's. New
  planning features land only in the factory (operator, 2026-10-23).
- **The factory's own planning skills**: *never here*. They are D-08's (`factory-prd`,
  `factory-tickets`, factory T-93 and T-96).
- **The stamp reader parsing a factory ticket's file**: *never*. The layout is the factory's,
  and `factory stamp` is its one reader (§8, 2026-10-31). This reverses the earlier non-goal
  "the stamp reader calling `factory stamp`".
- **Probing for the factory with a `factory` subcommand** in a planning skill: *never* (R224).
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
- **Reading `Accept-test:` through `factory stamp`**: *later*, once factory T-94 ships it after
  the kit's `Accept-test:` release (PRD-14). The kit's checker passes it on then with no change
  here.

## 7. Technical constraints and testing

- POSIX `sh` and `git` in the stamp reader, as today; the `factory` binary is run only for a
  factory ticket id in a factory project, and its absence is R138's exit, never a crash. The
  reader finds the git top level from the repository the script lives in, never the caller's
  working directory, as it already does for the vocabulary checker, and runs `factory stamp`
  there (`factory stamp -C <top level> <id>`).
- **Trust boundary.** A factory ticket's file is untrusted, as an issue body is, and the kit
  opens none (R129). What `factory stamp` prints on stdout is treated as an untrusted body:
  the reader's own lift, bound and checker run over it, so no ticket text reaches stdout unless
  the kit's checker passed it. Its stderr is discarded, and the reader names each case itself
  from the exit status, so none reaches the reader's stderr. `factory stamp` runs the
  project's own `scripts/vocab.sh`, as the kit's reader does. The deferral reads no file's
  contents and runs no `factory` subcommand (R124, R224).
- **Tests** drive behaviour from outside. The stamp suite builds a throwaway repository with a
  factory manifest, puts a stand-in `factory` first on `PATH` that answers by exit and records
  its arguments, and a stand-in tracker that fails the test if it is called. The skills are
  held by skill-text suites, the prior art for every rule a skill obeys:
  `tests/spec-skills.test.sh`, and `tests/implement-deliver.test.sh` for `/implement`.
  Bootstrap is held by `tests/kit-demo.sh`.
- **Numbers, not quality words:** an id is `T-` and 1 to 6 digits (R128). The bound is the
  policy's, 8 lines of a key (R130). The exits for a factory ticket are 0, 2, 3 and 5 (R132,
  R133). "Unchanged" for a consumer means the end-to-end bootstrap acceptance test passes with
  no edit to it (R136).

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
- **~~The stamp reader reads the file itself.~~** Superseded 2026-10-31 by the T-69 answer
  below: the kit does not parse factory ticket files, and runs `factory stamp`.
- **`Label:` is lifted from a factory ticket only.** On an issue, the tracker's label is the
  autonomy label, and a body line would be a second source that can disagree with it.
- **~~Exit codes keep the stamp reader's meanings.~~** Superseded 2026-10-31 by the T-69
  answer below: a factory ticket's exits are `factory stamp`'s, 0, 2, 3 and 5, and there is no
  4, because nothing is fetched.
- **Receiving end first.** Slice 1 lets the kit build a factory ticket before slices 2 and 3
  send planning to the factory. That is condition (4)'s order.

**Settled 2026-10-31** (§9's first two questions, closing T-69 #932 and T-70 #933):

- **T-69 · IN-01 has shipped as `factory stamp`, and the kit runs it** (a ruling: the
  factory's contract as shipped, relayed by the D-08 factory session on 2026-10-31). The kit
  does not parse factory ticket files. In a factory project it runs
  `factory stamp <T-id> [--json]` (schema `schemas/stamp.schema.json` in the factory repo),
  whose exits are the stamp reader's: 0 checked lines, 2 refused or no such ticket, 3 no stamp
  or no checker, 5 too many lines; no 4, because nothing is fetched. Layout, for reference
  only: `.factory/items/T-nn/ticket.md`, YAML front matter, then a body of bare `Key: value`
  stamp lines. Id shape `T-[0-9]+`; a temporary `T-~<hex>` id (before `factory renumber`) is
  not stampable, and `/implement` refuses it (R222). Keys read today: Tier, Confidence, Label,
  Domain, Risk, Risk-confidence, Test-tier, Covers; Accept-test later (factory T-94, after the
  kit's Accept-test release); `Class` is written but not read by `factory stamp`; undeclared
  fields are dropped and named in `undeclared`. A factory project is one whose git top level
  holds `.factory/project.yaml` (agreed 2026-10-29; nothing above the git top level is read).
  This changed §1, UC3, §3, R128 to R135, R137, slice 1's acceptance, §6 and §7.
- **T-69 · Where the `factory` binary is absent, the stamp reader sends the caller to the
  forge issue, and says so once** (the session's ruling, under the operator's delegation, on
  D-08's stress that "a project without the binary must still work"). Given a factory ticket
  id in a factory project with no `factory` on `PATH`, the reader exits 3 (factory stamp's
  "no checker" meaning) with one stderr line naming the absent binary and
  `sh scripts/stamp.sh <issue-number>` (R138). `/implement`, holding the ticket's forge issue
  number from its hand-off, says once that it fell back and reads the issue's stamp (R139);
  holding none, it takes exit 3's path, whose missing-line defaults fail safe (a missing
  `Risk:` reads as `high unclear`). Exit 3 rather than 2, because the ticket may well exist and
  the caller did nothing wrong; rather than a kit-side parse of the file, because that would
  bring back the second reader the T-69 answer removed.
- **T-70 · The planning skills do not wait for the factory's skills; they defer by name when
  the skill is installed** (the session's ruling under the operator's delegation, 2026-10-31,
  on D-08's recommendation, following factory PRD-16's coexistence rule). The factory's skills
  are `factory-prd` and `factory-tickets`, which `factory install-skill` writes to
  `~/.claude/skills/<name>/SKILL.md` (not landed yet: factory T-93 and T-96). `/to-prd` and
  `/to-tickets` defer by name when the project is a factory project and that factory skill's
  `SKILL.md` exists (R120, R121, R225). In a factory project with the skill missing they run
  the generic skill as today and say once that `factory install-skill` would add the factory
  one (R223). They never probe with a `factory` subcommand: a skill directory is what the
  harness discovers, and a project without the binary still works (R224). Hand-off words, for
  the skill-text suites: deferring, "This repository plans in the software factory: write
  tickets with `/factory-tickets` (PRDs with `/factory-prd`). `/to-tickets` (`/to-prd`)
  publishes nothing to the tracker here."; skill missing, "This is a factory project, and the
  factory's `factory-tickets` (`factory-prd`) skill is not installed: running the generic
  skill. `factory install-skill` would add the factory one."
- **R225's project root is the session's reading, confirmed** (derived under delegation,
  confirmed by the coordinator's ruling of 2026-10-31): the ruling
  names `~/.claude/skills/`, where `factory install-skill` writes; a project's own
  `.claude/skills/<name>/SKILL.md` is also a directory the harness discovers, so it counts the
  same. No other path does.
- **In a factory project, configuration the factory defines is read from the factory's
  manifest** (the operator's own yes, 2026-10-31, on the D-08 factory operator's widened
  option (a)). Every configuration value the kit reads that the factory also defines is read
  from the factory's key in `.factory/project.yaml`, and the kit's own policy file is read only
  where the project is not a factory project (R226). The factory's operator ruled this for
  every configuration check, not only `acceptance_tests_since`; PRD-14's adoption date is its
  first instance. Wherever the kit's policy reader (PRD-08, K2) reads such a key at the base,
  the read happens at the base too (R227), so PRD-08's reader (T-41) must carry
  `.factory/project.yaml` in its judging set and honour the rule. Slice 4 delivers it, as
  T-86 (#959).

**Alternatives considered:**

- **Make every pre-ticket skill defer** (the grilling skills, `/design-brief`). This lost: they
  publish no item, so there is nothing to keep from being written twice.
- **Decide the deferral from a policy flag** instead of from the manifest. This lost because the
  flag would duplicate what the manifest already says, and could disagree with it.
- **The kit parsing the factory ticket's file itself** (this PRD's first draft). This lost on
  2026-10-31: two readers of one layout drift, and the factory owns the layout.
- **A file form of the stamp reader** (`--file <path>`). This lost because a path lets a caller
  point the reader at any file, while an id resolves only inside the factory folder. The id is
  also what the factory and its tickets name.

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

- **~~What the factory's IN-01 settles.~~** Settled 2026-10-31 (T-69, #932): IN-01 shipped as
  `factory stamp`, and the kit runs it rather than parsing the file. See §8.
- **~~The factory ships no PRD- or ticket-writing skill yet.~~** Settled 2026-10-31 (T-70,
  #933): the planning skills do not wait; they defer by name to `factory-prd` or
  `factory-tickets` where that skill is installed, and name `factory install-skill` once where
  it is not. See §8.
- **The chain beyond the stamp names a ticket by issue number.** The trace subject
  `ticket:#<N>`, the PR's `<!-- implement: ticket=#<N> -->` line, the landing script's
  `--ticket` and a PR's closing reference all expect `#<N>`.
  - Options: accept `T-<n>` in each of them, as a follow-up PRD; or keep a mirrored forge issue
    per factory ticket, as this repository does today.
  - Next step: a `planner` ticket after slice 1 lands. MVP default: the mirrored issue.
- **This repository is itself a factory project.** Once slice 2 lands and `factory-tickets` is
  installed here, `/to-tickets` defers here, while the kit's chain still lands by issue number (previous question).
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

Four build tickets in slice order, slice 4's being T-86 (#959). Slice 1's tag lets the factory's tickets in this repository be
built by their `T-<n>` id rather than by a mirrored issue, once the chain's naming question (§9)
is answered. Slices 2 and 3 are first run here under the operator's override (§9). The first
factory ticket built through `sh scripts/stamp.sh T-<n>` is the measure.

## 11. Further notes

Requirement ids start at process/R120 so that they do not collide with the sibling D-02 drafts
(PRD-08 to PRD-13 hold process/R61 upward and runtime/R52 upward). They are re-based at
approval if they collide with whatever has landed by then. The 2026-10-31 amendment added
R138 and R139, then R222 to R227, because PRD-11 holds process/R140 to R160, PRD-13 holds
R200 to R208 and PRD-14 holds R220 and R221. The next free id, for T-74's trace-subject
requirements, is R228.
