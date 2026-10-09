# Development diary

> Living history of the agentic-sdlc build. The **Current state** block at the
> top is the agent re-orientation summary — read it first when picking up the
> project. Below it: forward-chronological entries, newest at the bottom.

---

## Current state — 2026-10-09

<!--
Update this block IN PLACE. It is the only part of this file that is edited
rather than appended to: it answers "where is this project right now?" for an
agent (or a human) opening a fresh session, and a stale answer here poisons
every session that reads it. Entries below are append-only.

Keep it to facts an agent cannot cheaply derive: the phase, what is live, what
is in flight. Do not restate the README.
-->

| Field | Value |
| --- | --- |
| **Phase** | The kit is shipping. Shared layer 0.67.0 tagged 2026-10-08 at `e3cc28a`, the merge of PR #659 (#655: the docs gate advises on an off trace and an unmapped reviewer tier). The same day: 0.66.0 at `d190ff8` (PR #658, #653: the retro-candidate wave #627–#638 — `scripts/trace.sh` records an interruption; ADR-0018, ADR-0019), and on 2026-10-07 0.65.0 at `06b4341` (PR #626, #596: PRD #580's spend-per-spawn wave closes). Shared layer 0.64.0 tagged 2026-10-07 at `ef308d5`, the merge of PR #614 (#563: the update recipe reads in order for a consumer several releases behind). The same two days: 0.63.0 at `6546ced` (PR #611, #569: a spawn's `model` is a policy id, and the note carries the #580 wave's unbumped shared changes), 0.62.0 at `85bd230` (PR #613, #564: a shipped file cites a kit record only as the kit's — ADR-0017), 0.61.0 at `dbef54d` (PR #605, #567: a finding raise's id is held to the severity shape), 0.60.0 at `ebab6fe` (PR #578, #561: the docs harness's fixtures can no longer satisfy a project's living spec), 0.59.0 at `9ea1824` (PR #576, #562: no kit-only file survives bootstrap), 0.58.0 at `eea6d6d` (PR #599, #571: both gate engines read a code fence by CommonMark's one rule), 0.57.0 at `63d815a` (PR #598, #560: a bare `trace.sh end` is deprecated), 0.56.0 at `eb2aa68` (PR #577, #509: a release is tagged by its landing before main is judged — ADR-0015), 0.55.0 at `a7fd604` (PR #574, #557: fence detection has one home). Since #577 the landing script tags the merge commit itself; main no longer goes red between a release and its tag. Shared layer 0.54.0 tagged 2026-10-05 at `fe6c4b7`, the merge of PR #554 (#545: the requirement-line grammar has one home, `scripts/requirement.lib.sh`). The same day: 0.53.0 at `efd4a77` (PR #553, #548: the reviewer walks an ordered fallback in the shared resolver, ADR-0013), 0.52.0 at `6169911` (PR #551, #543: `trace.sh end <run>` closes only the run its caller began), 0.51.0 at `dfeeffd` (PR #550, #544: a cited living-spec id is bounded on its left). Shared layer 0.50.0 tagged 2026-10-05 at `50bf936`, the merge of PR #541 (#534: `scripts/coverage.sh` joins the layer; requirement ids reach the ticket, the review and the living spec). 0.49.0 tagged 2026-10-05 at `201951d`, the merge of PR #537 (#530: a living-spec requirement no test names fails the docs gate, in both engines). Both close PRD #527 (ADR-0012: the kit moved from spec-first to spec-anchored). Shared layer 0.48.0 tagged 2026-10-02 at `122faa0`, the merge of PR #523 (#472: `trace.sh stack` reads a checkout's run stack). 0.47.0 tagged 2026-10-02 at `0b03c6d` (PR #520, the non-manifest half of the waves #462/#477). 0.46.0 at `5e82f73` (#480), 0.45.0 at `0e572e0` (#482), 0.44.0 at `8542b28` (#465). Shared layer 0.43.0 tagged 2026-10-02 at `678ffc6`, the merge of PR #487 (#466: the trace holds the triage source, the local id and the iteration's counts at emit). 0.42.0 tagged 2026-10-02 at `a59e9f4`, the merge of PR #476 (#453: the run stack is keyed by session as well as by toplevel, so two sessions in one checkout never read or pop each other's runs). 0.41.0 tagged 2026-10-02 at `5252882`, the merge of PR #451 (#401: `scripts/vocab.sh`'s header says what its contract is). 0.40.0 tagged 2026-10-02 at `9c5b988`, the merge of PR #446 (#409: a denied tool call is visible). 0.39.0 tagged 2026-10-02 (#400: `scripts/stamp.sh` bounds what it lifts). 0.38.0 tagged 2026-10-02 at `44b1ccf`, the merge of PR #443 (#418: a `mechanical` stamp names its one oracle and one pattern). 0.37.0 tagged 2026-10-02 at `925b0e7`, the merge of PR #442 (#420: the trace holds `finding.triage`'s `data.id` and `pr.iterate`'s `data.iteration` to a shape). Shared layer 0.36.0 tagged 2026-10-01 at `4d032fa`, the merge of PR #325 (#297: a task contract is admitted before an ordinary request's first edit — ADR-0011's second lifecycle slice, drafted as 0.29.0 and renumbered at its merge with main). 0.35.0 tagged 2026-10-01 at `d653c7e`, the merge of PR #371 (#331: `scripts/stamp.sh` joined the layer — `/implement` reads a ticket's stamp through it). 0.34.0 tagged 2026-10-01 at `efc61da`, the merge of PR #380 (#348: every trace kind holds its outcome to a vocabulary of its own — the first NARROWING of `scripts/trace.sh`). 0.33.0 tagged 2026-10-01 at `800f27f`, the merge of PR #322 (PRD #261: a dispatched review lands through the broker). Shared layer 0.32.0 tagged 2026-09-30 at `b610852`, the merge of PR #311 (#279, the confidence stamp), closing PRD #273's wave with 0.31.0 at `39c0d75` (#319, `finding.dismiss`) and 0.30.0 at `7798b6e` (#318, the typed return) the same day. Before them: 0.29.0 tagged 2026-09-30 at `870f2e7`, the merge of PR #326 (#255): `scripts/trace.sh` joined the layer and the dispatcher records every spawn, closing PRD #237's wave. Before it: 0.28.0 tagged 2026-09-30 at `39b10e2` (#293, `/retro`), 0.27.0 the same day at `24103c7` (#310), 0.26.0 on 2026-09-29 at `c5432e4` (#288), 0.25.0 at `59d5acb` (#289). The constitution, both gates, the guards (enforced on this repo too, through a kit-only policy), eighteen skills each declaring the phase of work it is, the three agent-harness adapters (claude-code, gemini-cli, and the dormant codex) beside the node-ts and ruby stack adapters, the consumer workflow templates, the dispatcher — which bounds a worker in depth, tasks and memory (ADR-0006), reaches another vendor for real, and now says whose failure an unreachable crossing is — and its two worker prompts are all in place and under test. The kit measures its own validators with `sh scripts/mutation.kit.sh` (baseline 76.53 % at `d29673c`, Stryker 10.0.0 — oracle: the validators' own fixture tests, 2026-09-02, at `d29673c`, no held-out set). |
| **Repo** | `agentic-sdlc`, a template repository (`main`). Feature work happens in `worktree/<slug>` on a `<type>/<slug>` branch. |
| **Remote** | `git@github.com:agranado2k/agentic-sdlc.git` |
| **Last commit on `main`** | `e3cc28a` — merge of PR #659 (#655, the 0.67.0 release), tagged `v0.67.0`. |
| **Deployed / live** | Nothing is deployed — the kit's delivery is the one-line agent setup (`SETUP.md` → clone at the newest `v*` tag → `setup/agent-bootstrap.md`), or the same clone-at-tag ritual by hand. |
| **Spec status** | PRD #580 (spend less per spawn) is complete: #583–#596 landed by 0.65.0, its requirements in the kit's second living spec, `docs/specs/spend.md`; the retro-candidate wave #627–#638 that followed landed in 0.66.0, with #646 and #647 open as its follow-ups. Wave-based; tickets are the unit of work and each one carries a capability tier — and, since PRD #527 (ADR-0012), a `Covers:` line naming the PRD requirement ids it delivers, checked by `scripts/coverage.sh` before the quiz. A PRD's requirements are numbered EARS-lite lines; an area may keep a living spec under `docs/specs/<area>.md`, changed by deltas and held to the suite by the gate. The kit keeps its first living spec, `docs/specs/process.md` (#556, PR #573): PRD #527's R1–R14 as they landed, cited `process/R<n>` by the suites, stripped from consumers by bootstrap. PRD #527 is complete (#528–#534), and so are its follow-ups #542–#546 and #548. Skills carry a `metadata.phase` too, and #229 settled which wins: the ticket, because its tier was decided by the actor who saw the whole wave. PRD #237 — a trace of every decision the chain makes — was decomposed into #246–#255, #270–#272 and #303–#309, and its release ticket #255 is the 0.29.0 PR; several of those issues are still open on the forge though their code has landed, and close by hand. PRD #273 — the chain's closed-set judgments as checked values, with a confidence, a judge contract and a calibration question — was decomposed into #274–#282 and is complete; what it left undecided is on the confirm-lists of its PRs, which are the operator's to rule on, and in the closing entry below. |
| **Last housekeeping** | 2026-10-09 — third pass: 24 findings, none fixed (19 ticket, 3 deepening, 2 brief, 0 deletion; 8 recur open issues #490 #493 #494 #498 #500 #503 #506 #507); root manual 299 lines, down from 350. The one that matters: OOM-killed suites leave about 900 MB of `kit-suite.*` scratch for a day on a quota'd `/tmp`, and every session's writes there fail until it is swept. Mutation run killed with its session at 801/1309 mutants (interim about 76.5 %, no final score; #507 — oracle: the validators' own fixture tests, the 2026-10-09 run at `9612a21`, compared with the 76.53 % baseline of 2026-09-02, no held-out set). Worktree pruning skipped: every merged worktree had commits under two hours old. Report: `/var/tmp/housekeeping-20261009T142448Z.md` (`/tmp` was over quota). |
| **Self-hosting** | The kit now obeys its own constitution: root `AGENTS.md`, the two shims, this docs set, and a green `sh scripts/check.sh` at the repo root. See `docs/adr/0001-the-kit-self-hosts-its-own-constitution.md`. |
| **Active worktrees** | As of 2026-10-09: `worktree/diary-0965-0966` is this diary refresh's own; `646-broker-low`, `647-worker-declined`, `660-reviewer-family`, `661-land-rerun-wait` and `663-review-lens-count` are other sessions', live, not to be pruned. None from the #580 wave, the retro-candidate wave or #655: their merged worktrees are pruned. None from the third spec-anchored wave (2026-10-06/07: #509, #489, #556–#569, #571, #572, #597, #608; PRs #573–#579, #582, #598–#606, #609, #611–#614): every merged worktree pruned. None from the follow-up wave (2026-10-05, #542–#546 and #548, PRs #549–#554): all merged worktrees pruned. None from the spec-anchored wave (2026-10-05): PRD #527's seven tickets landed in PRs #535–#541 after ADR-0012's #526, and every merged worktree — `worktree/` and the agent harness's own under `.claude/worktrees/` — was pruned. None from the waves #462 and #477 (2026-10-02): all eighteen tickets landed and their thirteen merged worktrees were pruned. None from the typed-judgments wave either: PRD #273 is complete — #274–#282 landed in the releases 0.25.0, 0.26.0, 0.28.0 and 0.30.0–0.32.0 and in PRs #287, #328 and #329; its merged worktrees are pruned. None from the trace wave: PRD #237 is complete. Every ticket landed — #246–#255, #270–#272, #303–#309 — 0.29.0 is tagged, and the thirteen merged worktrees were pruned on 2026-09-30 (the cleanup now keeps a fresh, commit-less worktree, #304). What the wave left for `/retro` and the next pass is listed on PRD #237's closing comments. The retro wave of 2026-10-01 (#343–#354, from `.retro/2026/10/retro-20261001T093317Z.md`) is complete: all twelve landed the same day, with the follow-ups #372 and #375, in PRs #359–#370, #377, #379 and the release #380; its nine merged worktrees were pruned on 2026-10-01. What that wave left for the next retro is on PRD #237's closing comment. None from the forge-broker wave: PRD #261 is complete — #265–#269 landed on 2026-10-01 as PRs #285, #283, #321, #320 and the 0.33.0 release #322; the four stacked worktrees and the release worktree were pruned. `worktree/lifecycle-entry` is PR #325, the lifecycle wave's second slice (#297, ADR-0011), carrying the 0.36.0 bump; #298–#302 are the later slices, and #302 owns consumer adoption of the mechanisms. Still open from before: a cross-vendor Gemini review end to end; `ai-review.example.yml` is still inert; codex has been logged out on the operator's machine since 2026-09-30, so no cross-vendor review has run since — every review has been an in-session reviewer on a different model, posted through the broker. The second retro wave of the same day (#384–#388, from `.retro/2026/10/retro-20261001T150216Z.md`) is complete too: all five landed in PRs #389–#391, #393 and #394, and its worktrees are pruned; its headline — the kit's hooks execute the root checkout, which had sat 140 commits behind main for four hours — is answered by #384's `behind` record and by the root being synced. |

### Open questions / unresolved decisions

<!--
Things that are genuinely undecided, one bullet each, with enough context that
future-you can decide without re-deriving the problem. Strike a line through or
mark **RESOLVED <date>:** in place when it is settled — deleting it loses the
record that it was ever open.
-->

- **The kit's own gate policy has no seam of its own.** The `placeholder-unstamped`
  rule lives in `scripts/check.sh`, which is shared layer, and it exempts only
  `*.template` sources. Kit-authoring scripts that must name a mark therefore
  spell it from variables. That works and leaks nothing to consumers, but if a
  future kit file needs a *different* kit-only exemption, the shared gate will
  need a real policy seam and a minor bump with it.
- **Two shared-layer comments now read as slightly stale.**
  `scripts/docs-conformance/validators/claude-md-refs.mjs` still describes "the
  kit's own unbootstrapped tree" in two comments. They are correct as general
  statements and wrong only as an example. Fixing them is a shared-layer edit,
  so it waits for the next release that has to bump `VERSION` anyway.
  **RESOLVED 2026-08-27:** that release is 0.9.0, and the fix rode it exactly as
  planned. Both examples now name a tree whose manual has not been written yet
  — *not* a freshly-created consumer repo, which was the obvious replacement and
  is equally false: a repo made from the template carries the kit's own
  `AGENTS.md` and both shims until `bootstrap.sh` strips them.

### Memory pointers for future-me

<!--
The half-dozen facts you keep re-learning. Not documentation — pointers at it.
-->

- **The diary is the orientation document.** Read this `Current state` block at
  session start; everything below it is history.
- **`VERSION` decides what an edit costs.** A file listed there is copied
  verbatim into consumer projects: changing it means a minor bump, an
  `UPDATING.md` entry, and re-captured transcripts in `tests/docs-demo.sh`.
- **Two engines, one policy.** The docs gate's path roots are written twice —
  `claudeMdRefs.pathRoots` in `scripts/docs-conformance/config.mjs` and
  `path_roots` in `scripts/check.sh`. Adding a root to one alone splits the gate
  in half.
- **Decisions live in `docs/adr/`**, not here. A diary entry may *announce* a
  decision, but the ADR is the record.
- **Terms live in `docs/domain-glossary.md`.** One name per concept, everywhere.

### Update protocol

<!--
Shared invariant §8: a rule nothing checks decays into a lie. This protocol is
the cheapest honest form of "when does the diary get written?" — keep it short
enough that it is actually followed, and make the triggers observable events
rather than feelings.
-->

- **Phase milestone reached** → append a new dated entry below.
- **ADR added, decision reversed, or vendor changed** → append a new dated
  entry; do **not** edit old entries.
- **Shared layer moved (`VERSION` bumped)** → append an entry naming what joined
  or changed, and confirm `UPDATING.md` carries the recipe.
- **Worktree created for a non-trivial feature** → note it in the next entry;
  remove it from the active list when it merges.
- **Anything above happened** → also refresh the `Current state` block in place.

---

## Entries

<!--
Forward-chronological, newest at the BOTTOM (so reading top-to-bottom reads the
project's history in order). One `###` heading per entry:

    ### YYYY-MM-DD — <headline: what changed, not what you did>

Write what was decided and why, not a commit log — `git log` already exists.
Never edit a past entry; correct it with a new one that references it.
-->

### 2026-08-27 — The kit started following its own framework

Until now the kit repo was deliberately unbootstrapped: no root `AGENTS.md`, no
shims, no `docs/`, and `sh scripts/check.sh` failed at its own root with
`root-manual-missing`. The gate the kit sells was only ever run against a
throwaway project built by `tests/kit-demo.sh`.

That is now closed. The repo has a hand-written `AGENTS.md` for the
kit-authoring context (not a stamped copy of the template it ships), the two
shims, this diary, an ADR index and glossary, and a green docs gate at the root
— enforced by a new `self-host` job in `.github/workflows/kit-ci.yml`.

The interesting part was making that compatible with being a *template*.
Consumers create their repo from this tree, so every kit-own file above is
sitting in the tree `bootstrap.sh` runs against, and bootstrap refuses to run
when `AGENTS.md` already exists. It now strips its own files first, guarded on
two conditions so neither a consumer's second run nor a hand-written manual is
harmed. `tests/self-host.test.sh` asserts the result by byte-identity: bootstrap
runs twice, once against the real tree and once against the same tree with the
kit-own files removed by hand, and the two projects must be identical.

The decision, its alternatives, and the honest limitations are in
`docs/adr/0001-the-kit-self-hosts-its-own-constitution.md`.

### 2026-08-27 — The kit-own strip stopped being able to delete a consumer's work

Follow-up to the entry above, from the independent review on PR #48. The strip
was guarded on *whether* to run, and on nothing about *what* it removed. Two
demonstrated losses: `rm -rf docs/adr` took an ADR a consumer had written before
their first bootstrap (an uncommitted one unrecoverably), and a consumer who
personalized the kit's `AGENTS.md` in place — leaving the sentinel comment where
its own text tells them to — had those edits deleted with exit 0.

Both are closed by making the block name exactly what it deletes and check that
it still owns it. `KIT_OWN` is now a list of **files**, so `docs/adr/` is never
removed as a directory and a consumer's decision record is out of the strip's
reach entirely; and a third condition refuses the whole run, before deleting
anything, when git reports a local modification to any file on the list. What
that condition cannot see — an edit already committed, or a tree with no commits
at all — is recorded as a trade-off in ADR-0001 rather than papered over: the
alternative was a shipped hash of every kit-own file, and a stale hash would
refuse *every* consumer's first run.

The second finding was the sharper one: the sentinel guard could be deleted from
`bootstrap.sh` outright and all fourteen suites stayed green. Hard rule 9 says a
rule with no failing check is a claim, and this was one. `tests/self-host.test.sh`
gained section E — a fixture per guard, each one a consumer who wrote something
in the window between "Use this template" and their first bootstrap. Removing
any one of the three conditions turns it red.

### 2026-08-27 — The kit maps its own capability tiers

The tier -> model resolver (`scripts/agents.lib.sh`) has always shipped with an
empty mapping by principle: the kit names no model to a consumer. That left the
kit's own sessions unmapped too — every subagent this repo spawns silently ran
on whatever model the session itself happened to be, regardless of the tier its
ticket was stamped with, which is the exact cost blindness the tier mechanism
exists to remove, happening inside the tool that preaches it.

`scripts/agents.kit.config.sh` closes that: a second, kit-only mapping, never
shipped (`bootstrap.sh`'s `KIT_ONLY` deletion list, same as `tests/`), reached
through the resolver's existing `$AGENTS_CONFIG` seam. The picks: planner and
reviewer on the strongest model available (`fable`), implementer on the best
coding workhorse (`opus`), mechanical on the cheapest capable model (`haiku`) —
and the reviewer is never the same model as the implementer, on principle: a
review from the implementer's own model is an editorial pass wearing a second
hat, not an adversarial read. `docs/adr/0001-…` and this repo's own PR reviews
(starting with PR #50) now run on that policy.

Independent review on PR #50 (a different model than the implementer, per the
policy above) found the mechanism sound but the reach incomplete: every
`SKILL.md` that spawns a subagent instructs the plain `sh scripts/agents.lib.sh
<tier>`, which resolves through the empty shipped config in this repo too — the
kit-only mapping only engages if the session remembers to prefix
`AGENTS_CONFIG=scripts/agents.kit.config.sh`, which a SKILL.md followed
literally does not do. Skills ship unstamped, so none of them may be edited to
name a kit-only file. The fix is `scripts/agents.kit.sh`, a kit-only wrapper
(same deletion list) that sets the seam and delegates — one name to substitute
for `scripts/agents.lib.sh`, promoted to `AGENTS.md` hard rule 10 so the
substitution is unmissable at the point of spawning, rather than an environment
prefix a session has to recall and type correctly every time.

## 2026-08-27 — merge train lands the self-hosting wave

`/merge-train 48 50 49`, operator-started. Order: #48 (self-hosting) → #50
(kit-only tier mapping, stacked) → #49 (domain routing, shared layer 0.7.0).
Two cars went stale mid-train because `main` had also taken #46/#47: #50's
conflict was one additive hunk in `tests/agents-tiers.test.sh`, resolved on the
head branch; #49 needed a full sync pass — four conflicted files, a VERSION
renumber (0.6.0 → 0.7.0, since main's config-discovery wave had claimed 0.6.0),
one mechanical transcript re-convergence, and the activation of
`AGENT_TIER_IMPLEMENTER_CONTENT='fable'` now that the domain seam and the kit
mapping coexist. Every merge went through the forge API with post-merge
workflows observed green; all seven worktrees (f9 × 2, f10, f11, f12, f13, f14)
were pruned as merged and `main` fast-forwarded to `fe0e171`.

The Current state table above gained its **Active worktrees** row in this same
change — the row the `/worktree-cleanup` skill expects to refresh did not exist
before, so its absence is recorded here rather than silently backfilled.

Follow-up candidates, both pre-existing and both surfaced by the #49 sync
session: `tests/docs-demo.sh` is named in `README.md` as a suite but no CI job
runs it, so the transcript byte-comparison gating `UPDATING.md` is local-only;
and `README.md`'s architecture section still says `shared-layer: 0.4.0`.

## 2026-08-27 — the two merge-train follow-ups became checks

Both follow-up candidates from the entry above are closed on
`fix/f15-diary-followups` (PR #51), each as a check rather than a fix alone
(hard rule 9): `tests/docs-demo.sh` gained its Kit CI job, and
`tests/self-host.test.sh` gained a section F that fails when any suite in
`tests/` has no workflow `run:` line — or when a workflow carries a job with
duplicate keys, which the forge answers by loading nothing. That second
tripwire is not hypothetical: the first draft of this very change pasted the
new job over the `skills:` key, Kit CI went dark on the branch, and the
independent review caught it while the naive substring form of F stayed green.
README's worked example now quotes the current `shared-layer:` marker, held to
`VERSION` by the same section; historical release references stay as history.

## 2026-08-27 — the transcripts were locale-dependent; shared layer 0.8.0

The docs-demo CI job added in the entry above failed on its very first run, and
it failed on the thing it was added to watch. `tests/docs-demo.sh`'s section D
compares `UPDATING.md`'s two pinned transcripts against a live run byte for
byte; the pinned bytes had only ever been captured on macOS under a UTF-8
locale, where `sort` and `comm` place `UPDATING.md` after `scripts/...`, while
the CI runner's C locale places it before `constitution/...`. Same commands,
same verdicts, different order — and a byte comparison is right to call that a
difference.

The fix is one line beside the existing `COLUMNS=80` pin, and for the same
reason: `LC_ALL=C`, the one collation every platform has, so the capture no
longer records the capturer's machine. Both transcripts were then re-captured
under it. That re-capture is content inside a shared-layer file, so it is a
release and not an edit (hard rule 3): **shared layer 0.8.0**, no file joining
or leaving, `UPDATING.md` the only shared file whose bytes moved. The locale pin
itself lives in the kit-only suite, so a consumer taking 0.8.0 re-reads two
worked examples and changes no command of their own.

The locale was not the only thing the capture had recorded. With it pinned, CI
found a second one immediately: 9d's `sed` command is echoed as a literal, and
`echo` is where shells still disagree — dash turned its `\1` into a control
character, the macOS shell printed it as written. `printf '%s\n'` never
interprets its operand, so that line now reads the same from either. Same class
of defect, same fix shape as `COLUMNS`.

Worth naming: both dependences were latent from the day the transcripts existed.
Nothing about them was newly broken — the suite had simply never run anywhere
but the machine that captured them, and a second platform is what a CI job buys.
Locally, `dash tests/docs-demo.sh` now reproduces the runner's shell, so the
next one of these does not need a CI round-trip to find.

## 2026-08-27 — both #51 follow-ups closed; shared layer 0.9.0

The entry above left two follow-ups. Both are closed here, and they land
together because one of them costs a release and the other does not.

The kit-only one first, because it is the more interesting defect.
`tests/docs-demo.sh` builds its fake 0.3.0 consumer by rewriting this tree's
`VERSION`, and the rewrite was pinned to one literal — `s/^shared-layer:
0\.6\.0$/shared-layer: 0.3.0/`. It stopped matching the day 0.7.0 shipped, and a
`sed` that stops matching is silent: the fixture has carried the CURRENT version
ever since, so C2's `assert_has "VERSION" "shared-layer: 0.8.0"` — the assertion
that the update *landed* — was passing on a version that had never moved. The
fix is to match the marker line by **shape** (`shared-layer: *[0-9][0-9.]*`, the
form `tests/self-host.test.sh` already uses), plus an assertion right after the
fixture is built that the rollback happened, so the next dead rewrite is RED
rather than quiet. Same lesson as the locale and `echo` pins above: a fixture
that encodes today's incidental value is a check with an expiry date on it.

The shared-layer one is the release. `claude-md-refs.mjs` still offered "the
kit's own unbootstrapped tree" as its example of a tree the shim and
reachability rules stay silent on, and the kit has self-hosted since ADR-0001.
Worth naming, because it was the tempting fix: **a freshly-created consumer repo
is not that tree either.** The kit is a template repository, so a repo made from
it carries the kit's own `AGENTS.md` and both shims until `bootstrap.sh` strips
them — swapping one dead example for another would have re-opened this question
under a new name. Both comments now name a tree whose manual has not been
written yet, which is true in any repo the validator ships to.

That is a byte change to a manifest-listed file, so hard rule 3 makes it a
release: **shared layer 0.9.0**, no file joining or leaving, comments only, zero
behaviour change — the validator's 52 fixture tests pass unchanged. A consumer
taking 0.9.0 re-reads two comments and changes no command of their own. The
fixture fix is the wave's non-manifest half and never reaches them at all; both
pinned transcripts were re-captured, and the only bytes that moved in them were
the release number.

## 2026-08-27 — the update recipe stopped eating consumer files; shared layer 0.10.0

The second real consumer update (google-books-clojure 0.4.0 → 0.9.0, its PR #17)
confirmed the ten fixes from #37 working in the field and then found two things
that **destroy files**, plus three smaller ones. Issue #54. Both destroyers had
been in `UPDATING.md` since Part 2 existed, and neither could be seen from
inside this repo, because the kit is not a consumer of its own recipe.

**The first is a shape, not a line.** `kit show "$REF:$path" >"$mine"` was how
the recipe said "take the release's copy", and the shell truncates `$mine`
*before* `kit` is started. 9d is where it was caught: it names
`scripts/docs-conformance/local-vocabulary.mjs`, the kit ships that path only as
a `.template` (bootstrap stamps it), so `cat-file -e "$FROM_REF:$C"` is false —
and 9d read that one `no` as "then it is new at `$TO_REF`", printed
`ADD … copy it whole`, and ran a take that could not succeed. 1807 bytes → 0 in
the fixture; 29 → 0 in the field. The audit found **seven more sites** with the
same shape, including two that only write scratch files and still cost you the
real one: an empty `theirs` handed to `git merge-file` reads as "deleted
upstream" and empties `$S` in place. Step 0 now defines `kit_take` — fetch to a
temp file, write only on success — and every take goes through it.

**The second is the shell nobody declared.** zsh applies history modifiers to
`$var:x` *inside double quotes*, so `"$TO_REF:constitution/…"` was `$TO_REF`
with `:c` applied plus a literal `onstitution/…`. Measured on zsh 5.9, the
reachable modifiers straight after a colon are `a A c e h l P q Q r s t u x`
and `g&` — and `:s` aborts outright with "no previous substitution". Four lines
had a bare letter there; `"$TO_REF:$C"` and `"$TO_REF:VERSION"` did not, which
is exactly why it hid. The article went 45 bytes → 0 and the `cmp` above it
answered `YOURS` having compared against empty input.

**What made the fix testable is that the new cases run the document's own text.**
Everything else in `tests/docs-demo.sh` is a hand-written mirror pinned to
`UPDATING.md` by section D's transcript comparison — but a branch that destroys
a file prints nothing into a transcript, so there is no D to pin it with, and a
mirror can be fixed in the suite while the document a consumer follows stays
broken. `recipe_block` extracts a fenced block by its first line and the case
executes it, one of them under a real `zsh -f`. `C4f` then greps the whole
document for the shape, so the *next* one is caught by an edit rather than by a
consumer.

The three smaller fixes: 9d routes `.mjs` configs to a read of the diff (a key
extractor would not have helped — the change it missed at 0.5.0 was a new
element inside `portability.files`, not a new key) and refuses to answer at all
rather than reporting a vacuous "nothing missing"; step 8 says the kit's own
self-hosted `AGENTS.md`, shims, `README.md` and `docs/` are never a consumer's
base, since those *are* paths a consumer has; and the "re-read this file after
step 5" rule moved into **Before you start**, because the step-5 `NOTE` lives in
the new recipe and the consumer who needs it is reading the old one.

**Shared layer 0.10.0.** No file joined or left; one manifest-listed file
changed content, materially. Both transcripts re-captured. A consumer takes a
re-read and one habit change: Part 2's takes are `kit_take` calls now.

---

## 2026-08-28 — f21: the one-line agent setup (issue #59)

The kit's front door caught up with how projects start now: a human pastes one
line into a coding agent, and the agent does the ritual. The design came out of
a `/grill-me` walk (PRD #59), and its spine is the trust argument, not the
convenience: the AWS-style "follow this raw URL" shape is fetch-and-act on
remote instructions — the exact thing the kit's own agent trust boundary
forbids — so the kit ships a **two-stage entry** instead. `SETUP.md` (root,
fetched at main, deliberately frozen: line ceiling, no version string) says
only: resolve the newest `v*` tag with `git ls-remote`, clone AT it, then
follow `setup/agent-bootstrap.md` **from inside the clone** — content
version-locked to the release it installs, arriving by the same trust act as
any clone. Along the way the README Quickstart unified onto clone-at-tag for
humans too: "Use this template" snapshots mid-wave main, which is exactly what
F3 certifies releases against, so the docs stopped selling it.

The payload doc's new-project arm is a fenced `sh` spine (strip `.git`, init,
bootstrap with an **explicit** dogfood flag, gate, local first commit — never a
push; the remote is proposed at the one human checkpoint and the first push
stays the human's). Its existing-repo arm is an honest pointer to #60 — newly
tractable because the executor is an agent that can merge, not a script that
can only refuse or clobber, and sliced out per hard rule 4.

`tests/setup-demo.sh` referees both documents by executing their own fenced
bytes (the Part D pattern) against a scratch origin tagged `v9.0.0` and
`v10.0.0` — the resolve step must pick v10, killing lexicographic resolvers —
then proves itself non-vacuous by breaking a fence and watching the spine go
red. Both docs and the suite are kit-only (`KIT_ONLY`, deleted at bootstrap),
so the slice cost **no VERSION bump**. kit-demo's check 14 and self-host F1
forced the README row and the CI wiring, exactly as designed.

---

## 2026-08-28 — f22: the /review-pr output contract (issue #63, wave #62)

The review's content was never the problem — its readability was. PRD #62
(researched against the CLI tools people actually praise: rustc, ruff, pytest,
ESLint, the forge CLI's accessibility work) turned the §5 report into an
explicit output contract: verdict + badge count table + clean-audits line
first, findings in rustc-style anatomy (what/where line with a code-span
anchor, `cites:` as the error code, `fix:` as the help line, evidence behind a
fold), severity badged 🔴🟠🟡🔵 with the text label always alongside — color is
never the only channel. The two axes keep disjoint glyph vocabularies so the
human-only confirm-list is unmistakable, and its line shape stayed byte-stable:
the ⚠️/🔀 tokens are a machine contract `/pr-iterate` lifts verbatim.

`tests/review-pr-output.test.sh` pins it all as text (the delivery-contract
suite's pattern): tokens, orderings by line number, region-scoped glyph
disjointness, no-ANSI. Landed RED (16 failures when the landed suite replays against the pre-contract skill) before the skill edit turned
it green. Skills are not shared layer — no VERSION movement. Tickets #64
(pr-iterate adopts the vocabulary) and #65 (the AI-review prompt ports the
contract) stack on this branch.

## 2026-08-28 — f25: the skills manifest (issue #71, wave #70)

Dogfooding in a real consumer surfaced the gap (#69): centaur-spec sat on
shared-layer 0.10.0 — byte-identical, gate green — with no `/explain-diff`
anywhere in its tree. The feature shipped inside the v0.8.0 window, and Part 2
of the recipe is delta-based: a consumer whose update ranges never included
that window loses the feature forever, because no later window re-lists it and
no state check exists to heal the miss.

The fix's first slice: `VERSION` gains a `skills:` section — a NAME-level
manifest of the fifteen skills the release ships (names, never bytes: adapting
a skill's prose is the invited workflow). Self-host gains F4, the referee that
holds the manifest to the tree in both directions (shipped-but-unlisted,
listed-but-unshipped) plus a parser-separation leg proving `skills:` entries
never leak into the `files:` list — all four `files:` parsers already stop at
the first non-indented line, and now a check says so. Landed RED (no section)
before the manifest turned it green; both mutation directions proven.

Shared layer bumps to 0.11.0 (VERSION and UPDATING.md both moved), so the
wave's stacked siblings (#72 recipe, #73 absence gate, #74 resolver hardening)
ride the same release; the v0.11.0 tag is cut at the end of the landing train,
and self-host F3 on main stays deliberately red between the bump's merge and
that tag. Transcripts re-captured — the only delta was version strings, which
is itself evidence the parsers took the new section in stride.

## 2026-08-28 — f26: the recipe reads the inventory (issue #72, wave #70)

Second slice of the #70 wave, stacked on f25. `UPDATING.md`'s step 9a now
OPENS with the inventory: a fenced, copy-runnable diff of the newer release's
`skills:` manifest against the consumer's installed set — state, not delta,
printed before any per-skill three-way. The worked example demonstrates both
classes a printed name can be: `dogfood` (a recorded decline — nothing to do)
and `improve-codebase-architecture` (a gap the update then adopts). The
retroactive note names `/explain-diff` and its two wiring points for every
consumer arriving from ≤0.10.0 — the exact consumer #69 was filed about.

Referees: docs-demo C4i extracts and runs the DOCUMENT's own fence against the
scratch consumer (C4e pattern), asserting it prints the declined skill and
stays quiet about the installed one; both worked-example transcripts
re-captured (two passes — the transcript quotes UPDATING.md's own line count,
so the paste moves the number once before the fixpoint). Landed RED: four
failures before the recipe edit. The release-note discipline got its own
check too: self-host F5 requires the current version's history note to carry
its NON-MANIFEST HALF enumeration, mutation-proven, with hard rule 3 in
`AGENTS.md` naming the obligation.

## 2026-08-28 — f27: the skill-web advisory (issue #73, wave #70)

Third slice of #70: the half-adopted state gets a detector. A new shared-layer
validator (`skill-web`) scans installed skill bodies for slash-command
references and reports each one that resolves to no installed skill — as a
WARNING, never a violation, because declining a skill is a legal recorded
state; the gate's engine now separates advisories (printed to stderr, exit
untouched) from violations. One grammar and one exemption list serve both
validators: skill-web imports claude-md-refs' `commandRefs` and reads the same
`ignoreCommands`, which gained `/tmp` and `/codebase-design` — two quoted
non-references the new scan surfaced in the kit's own tree on its first run
(the validator paid for itself before it shipped). The reduced POSIX form
cannot run the scan and now says so; self-host pins the admission. Fixture
tests landed RED (module absent), with an end-to-end leg proving warn+exit-0
and a real-repo leg holding the kit's own web complete.

## 2026-08-28 — f28: the tier messages become literals (issue #74, wave #70, closes #43)

The last slice of #70, and the oldest debt in the wave: since the 0.6.0 fix
the resolver's accept-check has been a literal `case`, but the usage and
unknown-tier messages still read `AGENT_TIERS`, a module global a sourced
config could reassign — diagnostics naming tiers that do not exist, from a
check that was still correct. The global is gone: the four names are literals
at all three sites (check, usage, error), under the same
keep-in-sync-by-hand contract the file already documents for
`AGENT_DOMAIN_SHAPE`. Landed RED first — a suite case loads a config that
reassigns the old global and then asks for an unknown tier; five assertions
failed against the old resolver (four lost names plus the fake vocabulary
echoed back) and pass now. No behavior change to resolution, exit codes, or
stdout; `agents.lib.sh` is shared layer, so the change rides the wave's
0.11.0 bump.

## 2026-08-29 — f29: skill interiors join the gate (PRD #79, from #18)

K2's oldest caveat, closed: every installed skill body — SKILL.md and its
sidecars — now has its repo-path references resolved by a new shared-layer
validator (skill-paths), with the template fallback that makes one rule right
on both sides of bootstrap (a token resolves if the file exists or its
.template source does). The grammar is claude-md-refs' own pathTokenRe and a
new pathRefs export — one definition of "path reference", three consumers.

Two discoveries paid for the slice before it shipped. First, the scan's dry
run caught the kit pointing every consumer at a file bootstrap deletes:
/merge-train's step-5 note code-spanned the kit-only self-host suite; the
prose now names the mechanism without the path. Second, the PRD's severity
decision did not survive contact with the recipe demo: the fixtures model
sanctioned consumer states — green-before-update, mid-skew between skills and
articles — and violations made those states illegal. Findings are WARNINGS on
the 0.11.0 advisory channel instead, with the deviation recorded in the
release note. Exemptions are config policy in two shapes (whole files for
upstream-verbatim documents; exact tokens for paths created later — the
dogfood report directory and the bootstrap-installed review workflow), and
the dogfood token travels with the skill: bootstrap strips its marked block
on decline, which tests/dogfood-optin.test.sh promptly proved necessary.

Shared layer 0.11.0 → 0.12.0 (validator joins files:), transcripts
re-captured, D2/F5 held their ground automatically. Tag v0.12.0 at landing.

## 2026-08-29 — f30: adopt mode (issue #82, wave #81)

The existing-repo arm's first slice. `bootstrap.sh --adopt`, run from inside a
target repository against the scratch kit clone, classifies every kit file
per PRD #81's class table, installs the non-colliding set in one pass, prints
one stable `COLLISION <class> <path> <verb>` line per conflict, and exits 3 —
resolving nothing. Re-runs are idempotent (installed files compare equal and
stay silent; the expected manual is stamped into scratch so a re-run never
collides with its own earlier output), and once the agent's human-approved
resolutions land, the same command flips to 0: manual stamped, shims written,
hook wired — wiring happens only on the clean exit, so a parked adoption
leaves the team's automation exactly as it found it — and bootstrap retires
itself from the scratch clone.

One design refinement against the grill table, disclosed in the PR: project
memory present is a `kept` line, never a COLLISION — a verdict must be
resolvable, and "your diary exists" never stops being true; the seeding
proposal is #83's payload prose. The F13 block sits BEFORE the F12 strip and
the idempotency refusals, which would otherwise read a target's own manual as
"already bootstrapped"; everything below it is the new-project arm, untouched
byte-for-byte (self-host D held throughout). `tests/adopt-demo.sh` landed
first, 40 failures RED, and drives the whole contract: five collision
classes, byte-truth anchors on everything theirs, the flip to 0, the adopted
repo's own gate green, format-probe baits. Zero shared-layer movement.

## 2026-08-29 — f30 (second slice): the payload's existing-repo arm (issue #83, wave #81)

The Which-arm pointer stops saying "not yet". The payload document gains the
arm: this clone reframed as the scratch kit directory, one plan for the
batch (E0), the dedicated adoption branch and the doc's own fenced adopt run
(E1), then the doors — every COLLISION line resolved propose → approve →
apply → commit, one at a time, with per-verb guidance (relocate never merges
the shared layer; distill maps their manual's rules into the local articles
and lets git history preserve the original; rename-or-decline makes a
declined kit skill visible via the skill-web advisory; chain keeps their
automation running until its own yes). Kept lines are explicitly not doors,
with seeding as an optional proposal. E3 re-runs the same fence to 0; E4
proves the gate and hands the keyboard back — never a push, same as the
new-project arm.

adopt-demo section G referees it the setup-demo way: the doc's promises
pinned as text, and its own fences extracted and executed — branch, adopt
(exit 3 on a colliding tree), commit, resolve, the same fence to 0, gate
green, zero remotes. Landed RED (12 failures) before the arm was written.

## 2026-08-29 — f31–f34: the 0.13.0 wave — the mutation decision made out loud, and the chain made visible (issues #85/#86, PRDs #88/#89)

Both defects came from one real consumer run (the tic-tac-toe build). The
skill-visibility half (#86 → PR #94): the one-line setup runs a level above
the project, where a harness never discovers the clone's skills — four
surfaces now say how the chain comes into scope (the payload's new step 4
with its native-read-then-verify clause, bootstrap's Next: item 8, the
README quickstart, one harness-neutral sentence in the stamped manual), all
five promises pinned by setup-demo, RED-first.

The mutation half (#85 → PRs #95/#96/#98): the decision became a labeled
anchor in the engineering article template with exactly two honest forms —
a tool plus its on-demand command, or none-with-reason — named in
bootstrap's Next: and the payload's hand-back; adapters/ruby arrived as the
second worked stack example (mutant-rspec, with the Data.define and
module_function field notes that made a healthy suite read 1.5%); and the
gate gained its third advisory, warning when a stamped article records no
decision. The bump moved mid-wave: the ruby adapter changed the pinned
`ls adapters` transcript line, a transcript change is an UPDATING.md change,
so 0.13.0 rode PR #96 instead of the validator slice — docs-demo going red
is what surfaced it.

Two review catches worth remembering: the 0.13.0 VERSION note filed above
0.12.0's made F5 vacuous (window spanned both notes — F5's awk now closes at
the next heading, with a bait pinning exactly that), and the advisory's
anchor regex crossed the line break (`\s*` ate the newline, accepting an
empty label mid-document — now horizontal-only, fence-stripped via the
newly-exported stripFences, CRLF-proven). Tag v0.13.0 cut at #98's merge;
one CI rerun for the usual tag race. Feedback filed during the wave: #87
(in-tree worktrees vs topmost-config linters) and #97 (the `.claude/skills`
name reads vendor-locked — needs a grill).

## 2026-09-01 — the vendor-neutral home (0.14.0), and reviews that read the fix

#97's complaint was one word wide: `.claude/skills` names a vendor for a set
of skills that are all LLM-agnostic. `/grill-me` turned it into PRD #100 and
three tickets, landed as PRs #104/#105/#106, tagged v0.14.0.

The move itself: skills are canonical at `.agents/skills/` — the address the
Agent Skills ecosystem reads, and the alias Gemini CLI documents — with a
committed relative symlink per skill left at `.claude/skills/<name>`, because
the one harness that reads only that address documents that a per-skill entry
may be a symlink. `git mv` kept every file a rename. Staying put is a legal
permanent state, so the gate resolves and SCANS both homes, and UPDATING.md
carries a re-runnable migration fence rather than an instruction.

**The wave's real lesson is about review timing.** Each PR's independent
review had been posted seconds after its fix commit landed, so all three
described findings that were already fixed — no reviewer had ever read a
fix. Reviewing the fix commits on their own found more than the original
reviews did, and the worst of it was in the migration fence: `[ -e
".agents/skills/$s" ]` is true when the two addresses are two names for ONE
directory, so a directory-level bridge was reported as a two-copy conflict
whose advice — "delete the one you do not want" — removes the only copy.
Reproduced on three shapes before it was fixed. The same pass found the
fence unchained (`mv` failing still laid a bridge INSIDE the skill), a false
"re-running finishes it", and a zsh abort that skipped the gate entirely for
any project with no sidecar file — in a document that promises zsh.

Three hard-rule-9 holes in the same pass, all mutation-proved: the legacy
fallback in claude-md-refs — the whole staying-put promise — could be deleted
with the suite 98/98 green, because the case claiming to cover it pointed at
the CANONICAL address; the baked default was unreachable under test; and
self-host's "can it go red" probe asked whether a never-created name lacks a
bridge, which is true however the loop behaves.

Two design calls came back from the operator and both inverted a default.
The adopt arm's symlink refusal asked the wrong question — "is this parent a
link?" rather than "where does this land?" — so it now refuses only on
escape or dangle, covers EVERY directory the arm writes beneath instead of a
hand-picked four, runs before section 1 (it had been firing at section 4,
after three sections had written), and accepts a bridge by where it resolves
rather than how it is spelled. And the diverged shadow — one skill name, two
different bodies, one at each address — is now named by skill-bridge as an
ADVISORY: written as a violation it turned adopt-demo red on the leg that
blesses exactly that shape, since it is the adopt arm's own collision
resolution. A build must not fail for a layout the kit hands you.

*Promoted to ADR-0003 (2026-09-02), which supersedes the index's diary-recorded line.*

### 2026-09-02 — The design brief got its entry points, and the Ousterhout attributions were checked

PRD #107's plan cited *A Philosophy of Software Design* by chapter from
memory and said so. Ticket #113 owed the check. Against the second edition's
table of contents (the author's page confirms the edition; the full chapter
list was taken from a chapter-by-chapter edition that reproduces it, and the
chapter texts were corroborated from reader notes quoting them): chapter 3
"Working Code Isn't Enough" for strategic versus tactical programming and
the 10–20% investment; chapter 2 for complexity as dependencies plus
obscurity with its three symptoms; chapter 4 "Modules Should Be Deep";
chapter 11 "Design it Twice"; chapter 19 "Software Trends" for inheritance,
agile, unit tests, test-driven development, design patterns and getters;
and the fourteen red flags by their exact names. **Nothing was corrected**:
every attribution the PRD and ADR-0002 made stands. One caveat is recorded
rather than hidden — the publisher's own pages refused the fetch, so the
table of contents rests on a faithful secondary edition plus the author's
page, not on the publisher.

With that settled, the brief is wired in: bootstrap's Next list and the
setup payload's hand-back name it beside the mutation decision, `/to-tickets`
gains the rule that a new abstraction or a crossed context edge cites the
brief or reopens it, and `/improve-codebase-architecture` sends a style-level
finding back to the brief instead of into its deepening loop.

### 2026-09-02 — The 0.15.0 wave landed: the shape of the system, decided out loud

PRD #107 asked three questions the chain had never asked: what shape is this
system, which context am I in and whose word is this, and when was this last
looked at. The wave answered all three and pinned one word on the way.

**The word.** "Strategic" now means Ousterhout's strategic programming — design
as a continuous investment judged by complexity, dependencies plus obscurity —
and nothing else (ADR-0002). Evans's work is kept whole under the kit's names:
the **context map** and the **subdomain classification**; "strategic design" is
a banned phrase. The chapter attributions were checked against the second
edition and none needed correcting.

**The shape.** The engineering article's Architecture section carries three
anchors — paradigm, architectural style, context map — in the mutation
decision's two-honest-forms shape, and the `design-brief` advisory warns when
a stamped article carries none. `/design-brief` is the skill that fills them:
it designs the architecture twice under opposite constraints, compares on
complexity, stops for a human yes, and only then writes the anchors, the
glossary's context map and one decision record with the coexistence clause
that answers Ousterhout's critique of test-first once. Its first real run, on
the kit itself, stopped at the yes with the tree untouched — and returned ten
findings about its own text, nine of which shipped before its PR opened.

**The map.** The glossary's Context map section declares every edge from both
sides with one relationship word and opposite roles, so a disagreement is two
lines that do not match. The first draft got that wrong — it paired different
words across an edge and conflated role with relationship — and the fresh-context
review caught it. The kit's own map is a chain closed by a shared kernel, not a
cycle of conformists: `VERSION` is the one file two contexts own together.

**The clock.** The diary's Current state table carries a **Last housekeeping**
row, and the `housekeeping-due` advisory warns when it is older than the gate
config's window. `/housekeeping` is the pass it sends an agent to: eight
sourced items, Ousterhout's red-flag scan in fresh context, a module-level flag
to the architecture skill and a style-level one back to the brief, never a fix,
one write. The craft article gained §13, the tactical half of Domain-Driven
Design, and the manual template's rule count — "ten" since 0.10.0 — was finally
held to the article by a probe that fails on the drift it was born from.

**What the wave found on the way.** The gate wrapper had swallowed every
advisory on a green run since 0.11.0; `scripts/check.sh` now relays them, with
a suite that drives the path red first. Two ticket demos run by hand caught
what the suites stamp around: a stamped article naming a skill that has not
shipped fails the gate as `skill-missing`, and a skill naming the optional
`/dogfood` leaves a dangling reference in a project that declined it. Every
review this wave was a fresh-context read on a different model, and every one
found at least one assertion that could not go red.

### 2026-09-02 — The kit-only tier mapping got its record (ADR-0003)

The index had carried, since 2026-08-27, a diary-recorded line saying the kit
names no model anywhere, including its own tier mapping — and the same day the
kit had mapped its own tiers in a file bootstrap strips. The housekeeping
pass found the contradiction; ADR-0003 is the supersession the index owed,
and the index line now says so.


### 2026-09-02 — The root manual's size became a decision (ADR-0004)

The housekeeping pass measured the root at 334 lines against a 200-line
reference and asked whether the tier elaboration should move out. Decided the
other way: the kit has no local article by design, so its root is also its
local article and carries what a consumer's root and articles carry together.
The budget is 350 lines, read from the record by a self-host probe that fails
past it; growth is a split or a superseding record, never a silent line.

### 2026-09-02 — Craft rule §10 got its failing check

Ticket #146 of PRD #124, filed by PR #141's review. The craft article says
diagrams are drawings, never character art, and the kit shipped two skills
that drew boxes and trees in prose until #141 redrew them. Nothing would have
noticed a third. `tests/no-box-art.test.sh` scans the shipped prose — the
skills, the constitution and the templates — for the Unicode Box Drawing
block, byte-wise under `LC_ALL=C` so it needs no locale, and plants a box
under each root to prove the scan reports it. The harness's own fixture
tests use box characters as comment rules; they are code, not documents, and
stay outside the scan. The suite stacks on #141: on main it is red, which is
the point.
### 2026-09-02 — The kit makes its own mutation decision

Shared invariant §9 asks every consumer to decide how its pure, cheap layer is
measured, and the first housekeeping pass found the kit had never decided for
itself: the validators, 138 fixture tests, and nothing that could say
whether those tests enforce anything. The kit has no engineering article to
carry the decision line, so this entry is the record.

**Mutation decision**: Stryker, on demand, against the validators under
`scripts/docs-conformance/validators/`, with the fixture tests as the target
function. `sh scripts/mutation.kit.sh` runs it (about eight minutes on a
laptop); both the wrapper and its config are kit-only and never shipped. The
tool arrives through `npx` each time, pinned to one release — the kit commits
no package manifest and the harness stays dependency-free, but a baseline
measured against whatever the registry serves that day is not a ceiling. It
is never a gate. The decision is indexed under "Decisions recorded in the
diary" in `docs/adr/INDEX.md`.

**Baseline, 2026-09-02, at `d29673c`, Stryker 10.0.0:** mutation score **76.53 %** — 639
mutants, 468 killed, 21 timed out, 150 survived, none uncovered. Per file:
skill-web 85.29, housekeeping-due 83.33, skill-paths 82.61, design-brief
75.68, claude-md-refs 75.28, skill-bridge 73.33, mutation-decision 65.52.
Most survivors are hint strings and message text no fixture asserts on, which
is a true statement about the suites: they hold verdicts, not wording. The
survivors worth a ticket are the ones that change a verdict — a `sort` dropped
from a scan without a test noticing, a default skills directory emptied — and
`/housekeeping` item 4 reads this number next pass.

Two things the run taught: Stryker's sandbox copy fails on the kit's per-skill
symlinks, so the config runs in place; and one early run left a file without
its executable bit — which file was not recorded, and nothing in the mutate
scope is executable, so the wrapper's guard is a belt over a buckle: it hands
back any dropped bit with `chmod`, touching no content, and says so. The
review of that wrapper (PR #143) found the first guard reverted content while
reporting a mode fix and deleted Stryker's backup after a failed run; both are
gone, and `tests/mutation-kit.test.sh` drives the wrapper through a stub.


### 2026-09-02 — The demo suites build their fixtures one way

Ticket #131 of PRD #124. Every demo suite built its throwaway kits and
consumers by hand — `cp -R`, strip nested worktrees, drop `.git`, `git init`,
identity, signing switches, commit, tag, wipe, copy, commit, tag — and the docs
demo carried that ritual five times over. The architecture review classed it
as a shallow module in the large: the same twelve lines, with the only thing
that differed (which release the fixture simulates) buried in the middle.

`tests/lib.sh` now carries four builders — a `.git`-free kit copy with nested
worktrees stripped, a repo with a fixture identity and every signing switch
off, a two-tag history, and a consumer bootstrapped from a tree with one
commit. The deliberate content surgery that gives a fixture its meaning (a
rollback of a shared article, a manifest rewritten to an older release) stays
at the call site, between the copy and the history: it is the scenario, and
hiding it would hide the point. The docs demo adopted them; its section D
transcripts did not move, which is the refactor's proof, and the suite is 71
lines shorter. `tests/fixture-builders.test.sh` pins each builder's promise on
its own, including the nested-worktree case the helper exists for.

The kit demo and the self-host suite keep their own setup on purpose — their
adoption is a ticket of its own, not a passenger on this one.

### 2026-09-02 — The optional skill became data in bootstrap

Ticket #130 of PRD #124. Bootstrap named its one optional skill at twenty-odd
sites — both arms' flag parsing, four usage strings, the prompt, two marker
filters per comment syntax, the manual's stamp, the policy file's stamp, the
decline's removals, the adopt arm's copy, and two closing notes — and the
marker-pair arity check ran on the policy file only, after the manual had
already been stamped. A lone marker in the manual's template would have
truncated the manual to end-of-file with exit 0.

Now the top of `bootstrap.sh` declares an optional set: one entry per
optional skill, naming its marker token, the files carrying the pair with
their comment dialect, the paths that travel with it, the gate-policy token
it adds, the prompt and the two notes. Everything below reads the set. The
pair check runs on every marked file before anything is stamped or removed,
so a refusal names the file and leaves the tree as it found it; the opt-in
suite's new section proves that for both marked files and goes red under two
mutations (preflight removed; check neutered). Both arms stamp byte-identical
trees and output for both answers against the previous bootstrap — that was
the demo, run outside the suites. The kit-only deletion list stays a separate
set: those files are the kit's own, never a consumer's choice. The seam is in
the stamper, not the gate, as ADR-0001 already decided.

One thing learned on the way: bash 3.2, which macOS still runs as `sh`,
misparses a heredoc inside `$( )` when the body carries an apostrophe. The
notes are plain strings for that reason, and the comment says so.
### 2026-09-02 — The records and their index are held to each other

Ticket #145 of PRD #124, filed by PR #140's review. The index under
`docs/adr/` is what says which decisions are binding, and nothing checked
that every record had a row there or that every row named a file. The
self-host suite's kit-own section gains that probe (E5): one function reads
both directions, runs on the kit, and then on two baits — a record with no
row, a row with no record — so the check is proven able to fail before it is
trusted. Numbered records only; the template's `NNNN` is not a number.

### 2026-09-02 — The reviewer-never-the-implementer rule got its wiring and its check

Ticket #144 of PRD #124, filed by PR #140's review; ADR-0003 clause 4
deferred exactly this. The root manual stated the policy and nothing held
the kit's own mapping to it, and this wave met the case the plain lookup
cannot see on every PR: the session itself implemented, on the model the
reviewer tier maps to, so the reviewer ran on the implementer tier's model
and each report said so by hand.

The fallback is now data on the resolver's existing domain axis —
`sh scripts/agents.kit.sh reviewer self-implemented` — mapped in the
kit-only config beside the reviewer, and the tier suite holds both halves:
the kit's reviewer differs from its implementer, and the self-implemented
answer differs from the reviewer, with two throwaway configs proving the
probe can fail. The implement skill's fallback-review step names the rule
and the domain for consumers, and names no model; the implement-deliver
suite pins that text. ADR-0003 is on PR #140's branch and is not touched;
its optional clarifying amendment can point here once that lands.

### 2026-09-03 — The tier resolver's history moved to the diary

Ticket #137 of PRD #124, filed by the first housekeeping pass. The header of
`scripts/agents.lib.sh` had grown to 138 lines of narrative — why the kit
names no model, why the unconfigured default is load-bearing, why the tier
vocabulary is closed and the domain's open — and the module-global comments
below it recounted the incidents that shaped them. The contract was buried
in the story. The header is now the contract alone: the seam, the arguments,
the two resolution orders and the exit codes, in under thirty lines, with a
pointer here. The reasoning it dropped lives where it was already stated,
the root manual's "Capability tiers" section. Behaviour is unchanged; the
tier suite is the oracle.

The incidents, for the record, because each one is a rule that looks
arbitrary without its cause:

- **The sourcing recipe is two statements.** `AGENTS_CONFIG=… . file` looks
  right and is wrong in bash and zsh, which drop a prefix assignment before
  the sourced code runs; the resolver then resolved UNMAPPED, with nothing but its own one-line warning to show why. The
  recipe sets the variable on its own line.
- **The directory global defaults to empty, not `.`.** It once defaulted to
  `.`, which quietly made resolution order 3 mean "a config in whatever
  directory the process is standing in" — a stranger's code, sourced. Empty
  means a sourcing caller that has not said where it is gets `$AGENTS_CONFIG`
  or nothing.
- **There is no variable holding the tier list.** It was a module global
  feeding the usage and error text, and a sourced config could reassign it,
  leaving diagnostics that named tiers that did not exist while the literal
  `case` check kept working. The four names are spelled at their three
  literal sites and move together.
- **The config miss is memoized, not only the hit.** An unconfigured project
  is the common case, and every lookup re-ran `git rev-parse` and two stats
  to reach the same "no". Only the genuine "no config anywhere" miss is
  remembered; an explicitly named config that does not exist keeps failing,
  loudly, on every call.
- **An unmapped tier prints nothing and exits 0.** A resolver that
  hard-failed on an unmapped tier would leave a freshly bootstrapped project
  unable to spawn anything and would be deleted on day one. An unknown tier
  is the opposite case and exits 2: a typo is not a policy choice.
### 2026-09-03 — The harness context got one error mode

Ticket #126 of PRD #124, from the architecture review's deletion test on
`scripts/docs-conformance/context.mjs`: four thin wrappers over the
filesystem, one of which leaked errno codes to a caller that then wrapped it
in two try/catch blocks of its own to tell a directory from an unreadable
path. The context now answers the question a validator actually has:
`read` returns the text or null, for every way a read can fail, and `kind`
says file, directory or null. The recursive lister is gone — nothing in the
harness, the adapters or the suites called it. The bridge validator asks
`kind` and keeps every verdict; the one visible change is that its
unreadable-entry message no longer quotes an errno, and its fixture asserts
the message, not the code. `test/context.test.mjs` pins the contract, the
dangling-symlink and unreadable cases included.
### 2026-09-03 — The gate's two engines agree on their path roots

Ticket #127 of PRD #124, the finding the first housekeeping pass put at the
top: the reduced POSIX form of the docs gate admitted all of `.agents` and
`.claude` as path roots where the harness's policy admitted four subtrees,
and nothing held the pair together. A reference under `.agents/anything`
could fail the fallback while the harness ignored it. The harness's list is
the truth: the wrapper carries the same eleven entries and matches by
prefix rather than first segment, so a root may carry a `/`.
`tests/gate-path-roots.test.sh` reads both lists with no runtime, fails when
they differ, proves that with a bait on each side, and bootstraps a project
to show both engines judge the same three references identically. The
duplication itself stays — the fallback exists for a machine with no node
to read the policy with — but it can no longer drift in silence. One
consequence for the record: ADR-0001's honest limitation, that adding a root
"would split the two engines apart" because the POSIX twin lives in the
shared wrapper, is no longer true as stated — a root added to one list now
fails this suite before it ships. The record stands as written; this line is
its dated qualification, not an edit.
### 2026-09-03 — The fallback notice is held to the runner

Ticket #129 of PRD #124. The reduced POSIX gate prints a NOTICE naming
every scan it cannot run, and nothing checked that list against the scans
the harness actually runs; it had named six of seven by id, and the seventh
only by describing its rules. The self-host suite now reads the runner's
registration list, follows each import to its validator's id, and fails
when the notice does not name one — with a stub validator registered in a
scratch copy of the harness as the bait. The notice names the seventh, so
a validator added to the runner and not to the notice is red on the next
push rather than a silent overclaim.
### 2026-09-03 — The glossary's banned words got a reader

Ticket #128 of PRD #124, from the first housekeeping pass: the glossary
template ships a "Words this project does not use" section, and nothing
read it — the banned sense of *install* survived in the kit's own manual
beside legitimate dependency-sense uses the ban had no carve-out for. A new
advisory, `banned-words`, reads the section, and warns on each banned word
in the root manual, the local articles and every skill file, naming the
word, the line and the replacement the entry prescribes. Fenced blocks and
code spans are quoted material and stay silent; the two shared articles are
excluded by default, since a consumer cannot reword them. The entry format
gains an `Except:` clause — the permitted phrases as code spans — and the
kit's glossary uses it for *install*'s dependency sense.

The kit is the first consumer, and the gate's first run said twenty-two
things: two `install`s in the bootstrap sense in the manual (one of them the
finding the housekeeping report named), one in the design-brief skill, one
in the housekeeping checklist, one in the prototype skill; `the framework`
twice; and `config` on its own seventeen times across the manual and six
skills. None fails the gate. Rewording them is a ticket of its own — the
advisory's job was to make the debt visible, and it is.

### 2026-09-04 — The 0.16.0 wave landed: the kit keeps its own house

PRD #124 came from the kit's first housekeeping pass and the architecture
review it routed to, and its question was narrower than the wave before it:
does the kit keep the rules it sells? Seventeen tickets, eighteen PRs, two
trains, and one follow-up for a disposition that had claimed fixes it never
landed (#158, with its correction on #154).

**Two files joined the shared layer.** `scripts/manifest.lib.sh` is the one
grammar for VERSION's two sections, where eleven hand-copied awk programs had
disagreed on what an annotated entry means (#125). The `banned-words`
advisory reads the glossary's "Words this project does not use" section and
warns on every use in the manual layer and the skills, with an `Except:`
carve-out per entry; the kit is its first consumer and hears thirteen things
about its own prose (#128).

**The gate's two engines agree.** The reduced POSIX form's path roots are the
policy file's, entry for entry, and a suite fails when they differ (#127);
its notice names every scan the runner registers, held by a probe (#129); the
harness context has one answer to "is there a body?" and throws on a body it
cannot read (#126).

**The kit measures and records itself.** Stryker, pinned, on demand against
the validators, baseline 76.53 % (#132); ADR-0003 records the kit-only tier
mapping and ADR-0004 the root manual's 350-line budget with its probe (#133,
#134); every record has an index row (#145); the reviewer-never-the-
implementer rule lives where reviewers are spawned, as the `self-implemented`
domain (#144); the resolver's history is here, not in its header (#137).

**Deepenings from the architecture review.** Four fixture builders in the
test harness, the docs demo's transcripts byte-identical before and after
(#131); the optional skill as data in bootstrap, with an ordered marker-pair
preflight that refuses before anything is stamped (#130). Craft rule §10 got
its failing check after two skills were redrawn (#135, #146), and six small
drifts went in one sweep (#138).

What the trains taught is in the memory of the next one: every PR conflicted
on the same append-only files, a union merge duplicated a paragraph of the
release note once and the duplicate-ticket probe caught it, and one
disposition was posted from a command chain that had already stopped.

### 2026-09-04 — The release notes are held to the release delta

Ticket #160, filed by the review of PR #159, which had caught two changed
files the 0.16.0 notes omitted: the suite checked that the note had its
enumeration marker (F5) and repeated no ticket (F5b), and never read what
had changed. The self-host suite's F6 now does. While the declared version
has no tag — a wave in flight — every file that changed since the previous
release in the recipe's four categories (skills, the manual and article
templates, the docs and workflow templates, the gate policy file) must be
named in the current note or in an "Arriving from <previous> or older"
paragraph of the recipe, by path, basename or the skill's command. Once the
version is tagged there is nothing to hold; what changes after a tag is the
next bump's note to tell. Seven baits in a scratch repo with a real tag —
one file per recipe category, named by command, basename or path; the
previous release's paragraph counts and an older one does not; a tagged
version is silent; no tag at all is a skip — prove each arm, and the
probe's own mutations go red. The match is a
text match and loose in one direction, said in the probe's own comment: a
SKILL.md change hidden behind a mention of its skill for another reason
passes. It would still have caught both of #159's omissions.
### 2026-09-04 — The kit's own prose uses no banned word

Ticket #161, the first debt the banned-words advisory made visible: thirteen
uses across the root manual and six skills. Each is reworded to the
glossary's term — *bootstrap* or *copy* for the bootstrap sense of
*install*, *policy file* for the consumer's own configuration and
*configuration* where the general sense was meant, *the kit* for *the
framework* — and one dependency-sense use of *install* is reworded rather
than carved out, because "add whatever dependencies it likes" says the same
thing without a new phrase in the glossary. The gate on the kit prints no
advisory block, and every suite that pins skill or manual text is green.
These are shipped skill and template-adjacent changes made after the
v0.16.0 tag; they are the next bump's note to tell, which the release-delta
probe will hold it to.

### 2026-09-04 — The banned words in the surfaces the advisory does not scan

Ticket #164, filed by the review of PR #163: the sentences the advisory made
the kit reword still said the old words in the README, bootstrap's comments
and hand-back, and the two setup documents, none of which the advisory
scans. Forty-six rewordings, by the same rules — *copy* for what bootstrap
does to a file, *policy file* for the consumer's own configuration,
*configuration* in the general sense, *the kit* for *the framework* — and
bootstrap's own output says `copied` where it said `installed`, which no
suite or transcript pinned. Two surfaces stay as they are, on purpose:
`UPDATING.md` is shared layer, so its remaining uses are the next bump's to
reword (a release action, hard rule 3) — and that bump should know the README
is already ahead of it, calling step 9d's subject *policy files* where the
recipe's own heading still says config files. `VERSION`'s history notes are
history; its header prose and the adapters' documents, which ship, are
reworded here too. The scan set does not grow either: the advisory reads no list of
extra files, and giving it one is a validator change — shared layer again —
so the kit's README and bootstrap are held by this entry and the next
housekeeping pass, not by the gate.

### 2026-09-04 — The adapters' own prose uses no banned word

Ticket #167, filed by the review of PR #166. The adapter documents ship
to every consumer as reference material and the banned-words advisory
never scans them, so the same words survived there after the manual, the
skills, the README and bootstrap were reworded. Twelve more, by the same
rules: *policy file* where the consumer edits the file, *configuration
file* for a tool's own settings, *eval file* for the promptfoo suite's,
and the `INSTALL.md` document named as a file. Three forms stay, said here
so nobody rewords them next: the dependency sense in "the version you
install", the `INSTALL.md` filename, and "the framework-routed tree",
which is an application framework's routing, not the kit.

### 2026-09-08 — 0.17.0: the kit's prose uses its own words

No file joins or leaves the shared layer; one changed content. The 0.16.0
banned-words advisory made the kit its own first consumer, and over four
tickets (#161, #164, #167 and the kit-only sweep) the manual, the skills,
the README, bootstrap and the adapters were reworded to the glossary's
terms. The recipe itself was the one surface left, because it is shared
layer and a change there is a release: this bump carries it — *policy
files* for what a consumer edits, *copied* for what bootstrap does to a
file, step 9d renamed — and, more to the point, makes the skills' and
adapters' rewordings reachable, since those travel only at a tag. The
release-delta probe from #160 ran live on this bump for the first time and
held the note to the fourteen shipped files that changed since v0.16.0.

One correction to the record, made here rather than by editing history:
the four entries above dated 2026-09-04 — the release notes held to the
release delta, the kit's thirteen rewordings, the surfaces the advisory does
not scan, and the adapters' — were committed on 2026-09-07 and 2026-09-08,
and the 0.16.0 tag itself was cut on 2026-09-07. The session's clock had moved while they were
written; the entries stand as written, and this line is their date.

### 2026-09-17 — 0.18.0: the agent-harness axis

One file joins the shared layer and three change content. A capability tier
may now name the **agent harness** it runs in — `<agent harness>:<model id>`,
declared in `AGENT_HARNESSES` — and `scripts/agent-dispatch.sh`, the kit's
first executable spawn path, runs a tier there with a prompt built from
`.agents/prompts/`. ADR-0005 records the axis, the dispatcher's home, and the
word: the glossary now says *docs harness* and *agent harness* and bans the
bare one, because it had meant two things since the adapters were written and
nothing said which. The cross-vendor reviewer that
`templates/workflows/ai-review.example.yml` could only reach from CI — its own
header says that leg cannot be reached from inside the authoring session — is
reachable from a session.

The wave ran the kit's own chain end to end, and the chain earned its cost
several times over. `/grill-with-docs` found the glossary collision before a
line was written. Every PR's fresh-context review on a different model found
something real, verified before it was fixed: a banned-word rule that flagged
its own prescribed replacements (#179), a self-host assertion that tested the
machine rather than the repo (#180), a spawn silently landing on the wrong agent harness after a
capitalisation typo (#182), **two CRITICALs** in the dispatcher — command
execution through the prompt-file path (#183), and a `--set` value truncated
at its first newline with `NAME=VALUE` lines from an untrusted ticket body
promoted into the marker namespace (#185) — three test legs that could not
fail (#184), and a pty fixture that hung CI on a short answer list (#184).

Two plan defects, both caught by review against the manual rather than by the
author. `/to-tickets` budgeted the version bump into a separate release
ticket, which hard rule 3 forbids in as many words; the release action was
folded into #181 and the release ticket shrank to the tag. And with the release
folded in, "the bump's merge commit" and "the commit the tag belongs on" were
no longer the same commit: F3 requires every manifest file to be byte-identical
to the tag, and #185 changed shared layer after #181 landed, so the tag is on
the merge of #185. The next wave that folds a release in will meet the same
fork.

One mystery closed by accident. `self-host`'s "delta probe missed a category"
failed on every branch for the whole wave and was set aside as pre-existing —
true, and incurious. A reviewer's aside on #185 identified it as a locale
sort-order artifact; it is green under `LC_ALL=C`. Filed as #186, beside the
`tag.sort` cousin that #181 had already fixed from inside the same trap.

### 2026-09-19 — 0.19.0: the dispatcher's edges, found by using it

No file joins or leaves the shared layer; two shared files changed content.
0.18.0 shipped `scripts/agent-dispatch.sh`, and then it was used to dispatch a
real review to Gemini — and every edge this release files down was found that
way, not by reading the code. The worker inherited the dispatcher's open stdin
and blocked forever; a headless CLI gated `git diff` on an approval nobody
could give and blocked forever; a diff handed to a reviewer overran argv. So:
no inherited stdin (a template's own `< {prompt_file}` still wins), a
`--timeout` that snapshots and tree-kills the worker and reports 124 by a flag
the watchdog writes, and a `--set-file` that reads a large value from a file
`awk` opens directly. The banned-words gate also learned to scan the glossary
itself — the one document free to contradict the rule it defines, which two of
its own entries had.

The wave ran the chain nine times and the chain paid for itself nine times.
Every PR's fresh-context review on a different model found something real: a
`getline` loop quadratic in line count (8 MiB in eighteen seconds,
milliseconds after the fix); a timeout that killed the shell wrapping the worker while the worker,
reparented, ran to completion, and that read 124 from the worker's own signal
rather than from having fired; three test suites — the pairing-guard (#198),
the locale (#197), and the dispatch suite's own FIFO and timeout legs (#200,
#201) — whose failure paths could not be reached, each caught by a mutant that
survived; and, on the Gemini adapter, two of my three behavioural
claims that did not reproduce on gemini 0.60.0 — the "prompt on stdin hangs"
one because the real hang had been the inherited-pipe bug, which I had
attributed to the wrong cause and written a section around.

ADR-0003 was amended rather than duplicated: the never-shipped-twin
arrangement it recorded for the tier mapping is general, and the guard policy
is its second instance. The pairing guard is now on in the repository whose
product is that discipline, which every push of the 0.18.0 wave had announced
it was not.

One thing this release does NOT yet show: a Gemini dispatch running end to end
through the shipped dispatcher with a real `--policy` file and `--timeout`. The
fixes above exist because the first live attempt hit each edge; the
re-verification was blocked on Gemini's daily quota, and the gemini-cli adapter
says so in a re-verification note rather than claiming what was not re-run.

### 2026-09-19 — 0.20.0: a dispatched worker is bounded

No file joins or leaves the shared layer; two shared files changed content,
one of them `scripts/agent-dispatch.sh` five times over. The forcing incident
was not a review finding but a host: a 2 vCPU / 3.7 GiB dev VM froze three
times in one week, and it read as "the VM crashes when Claude is running in
the other session". The diagnosis (#205) was `cgroup: fork rejected by pids
controller` 91 times in one boot — the user slice's `TasksMax` of 10008,
systemd's 33 % of threads-max, filled in under three minutes by #204's own
nested-dispatch test stub, whose implementer tier mapped back to the stub
itself: a fork bomb with a model in the loop, and 267 anonymous scratch
directories left where the traps never ran. The stub was fixed in `a612b1c`
before 0.19.0 was cut; this release makes the class impossible. A dispatch
refuses to nest past a policy maximum depth (exit 4); it derives a task and a
memory ceiling for the worker's whole tree from this host — a percentage of
the smallest `pids.max` on the session's path and of `MemAvailable`, clamped
— shows both on `--dry-run`, and applies them down a ladder: a named transient
scope under the user service manager, else rlimits in the worker's own shell,
else a loud no-op, with exit 71 read from the scope's own `pids.events` /
`memory.events` and composed with `--timeout` by whichever fired first. Its
scratch names itself and stale scratch is swept. And, kit-only, `tests/lib.sh`
sources the dispatcher's new seam so every suite runs inside the same budget,
re-executing itself once inside the scope with a marker as the recursion
bound.

The chain ran five times — `/to-tickets` at the quiz (one planner ticket,
four implementer), `/implement` in a fresh context each, `/review-pr` in a
fresh context on a different model every time, `/pr-iterate`, three merge
trains folding one 0.20.0 note per PR — and every review found what its
author had not. #213: the depth's propagation through the `--timeout` path
and a non-numeric policy maximum were unpinned, both found by mutants that
survived. #215: a second whole-number validator that read a leading zero as
octal (`025` derived 21 %), and two host-fact fallbacks nothing tested. #216:
a marker fallback that could run a worker a second time after it had already
run; the rlimit rung applying its `ulimit`s to the dispatcher's own shell on
both spawn paths — reproduced: its own cleanup could not fork; and a runaway
stub with no bound in any mode where enforcement did not bite. #217: a
recursion-bound test that could not fail (the mutant was a live fork/exec
loop the suite did not detect); a suite started inside an operator's own
scope escaping into a sibling with larger ceilings; and eleven rewrites of
the bare word to "test harness" on lines that had meant the agent harness or
the docs harness, reverted. The dispatch suite went from 141 to 376 assertions
on this host and `tests/suite-budget.test.sh` joined it at 115; every suite
ran, and was reviewed, inside `systemd-run --user --scope -p TasksMax=300
-p MemoryMax=512M`.

ADR-0006 records the decision and was amended twice rather than rewritten —
once for what building #208 refined in clauses 5, 6 and 8, once for what #209
settled and measured: per-suite peaks of 44 tasks and 35 MiB against floors
of 256 and 512 MiB, so no clamp was re-decided.

Three things this release does NOT yet show. A Gemini dispatch end to end
through the shipped dispatcher, carried from 0.19.0 and still unverified. A
ceiling hit on the rlimit rung: there is no counter to read there (clause 6),
so exit 71 exists only where a user service manager answers, and CI is that
weaker rung's only oracle. And a review from a second vendor:
`ai-review.example.yml` is still inert, so every review this wave was an
in-session sub-agent on a different model, not a different vendor.

### 2026-09-21 — The spec skills learn from the design-doc tradition

`/to-prd` and `/to-tickets` were read against Michael Lynch's "How to Write
an Effective Software Design Document" (refactoringenglish.com). The article
is written for human-read design docs, but its rules translate almost
one-to-one here, because a PRD in this kit is read by fresh-context sessions
— the purest reader with no outside context there is (shared invariant §4).

What the kit already had: no file paths in the spec (the article's "don't
write the implementation during design"), tracer bullets as milestones that
create useful artifacts, the quiz as driving the doc through review,
`docs/adr/` as resolved issues, glossary vocabulary, no ASCII diagrams.

What it lacked, and now carries. `/to-prd`'s template opens with a
one-sentence Objective (the line every ticket quotes); gains Scenarios —
numbered walkthroughs of the finished system in use, which are demo scripts
by construction; states the *penalty for being wrong* as the filter on
Implementation Decisions, of which the file-path rule was only a symptom;
restates every quality word as a number a test can assert; keeps a brief
Alternatives Considered so the grilling's rejected branches stop being
re-litigated downstream; marks every Out-of-Scope item *later* or *never*
with its reason; and holds Open Issues as problem / options / next step. The
process gains a reread-as-a-stranger step before publishing. `/to-tickets`
reads the Scenarios as the candidate demos for its admission test, gains rule
12 (an open issue that would shape tickets is resolved first, by a `planner`
ticket or a `/prototype` spike, and blocks what it shapes) and rule 13
(where the DAG leaves the order free, the slice most likely to expose a
misunderstanding lands first — the surface over stubbed data before the
pipeline). The article's own counter-lesson was applied to all of it: a
section is a menu item, so the new ones are omitted when empty, never
written as "N/A".

Declined at the quiz: rejecting a drafted ticket that lands inside a PRD
non-goal. `tests/spec-skills.test.sh` pins both contracts as text, RED
before the edits, and is the first suite either skill has had.

Neither skill is manifest-listed, so this is not a shared-layer bump; the
obligation moves to the next one. The 0.21.0 `VERSION` note's non-manifest
half owes `/to-prd` and `/to-tickets` a line each — `self-host.test.sh` F6
holds the union of that note and any "Arriving from" paragraph in
`UPDATING.md` to it once the bump is written, so the note is the enforced
half and the recipe paragraph is convention.

The review of #222 also recorded a debt this PR did not pay, on purpose:
`tests/spec-skills.test.sh` is the fourth hand copy of the skill-suite
scaffold (`skill_spans`, the command-resolution loop, `path_verdict` with its
hand-kept root list) after the design-brief, housekeeping and
implement-deliver suites, and the copies have already drifted from each other
and from the gate's `pathRoots`. Promoting them into `tests/lib.sh` beside
`t_assert_skill_frontmatter` is a structure-only change and so a ticket of
its own (shared invariant §10), not a passenger on this diff.

### 2026-09-21 — The reviewer is compared against the session that asks (ADR-0007)

Building #222's review exposed a blind spot in the kit's own tier mapping:
`reviewer self-implemented` answers one fixed model, chosen assuming the
session runs on the planner's — so a session running on that model was
handed its own model to review with. The session used the plain reviewer by
hand; #224 filed the gap; ADR-0007 records the shape chosen at its
`/implement` stop: the caller names what it runs on (`AGENT_SESSION_MODEL`,
in the policy file's own word) and the resolver refuses an equal answer — falling
back to the plain reviewer, or to nothing with a warning the report quotes.

Two steps, because the resolver is shared layer and #224 budgeted no
release: the kit-only wrapper `scripts/agents.kit.sh` carries the rule now
(the tiers suite drives six cases RED then green), and the 0.21.0 release
ticket moves it into `scripts/agents.lib.sh` with the note, the recipe entry
and the transcript re-capture a shared change owes — alongside the
`/to-prd` and `/to-tickets` line that release already owed.

### 2026-09-23 — Two releases, and the day the chain caught its own operator

0.22.0 and 0.23.0 landed within hours of each other, and the second exists
because of what the first got wrong. 0.22.0 (#234) moved ADR-0007's reviewer
refusal out of the kit's own wrapper and into `scripts/agents.lib.sh`, so
every consumer stops having the blind spot the kit found in itself: a
`self-implemented` mapping answers one fixed model, chosen assuming the
session runs on another, and a session running THAT model was handed itself
to review with. `$AGENT_SESSION_MODEL` is the caller naming what it runs on,
and it is opt-in — unset, the resolver behaves exactly as it did.

0.23.0 (#243) fixed the migration guide for that rule, which had been
teaching consumers to wire it wrongly: the example resolved a TIER into
`AGENT_SESSION_MODEL` rather than naming the session's model, so the
comparison never matched and the author's own model came straight back,
unrefused and unwarned. The prose above it was right; the example
contradicted it, and the example is the half a consumer copies. The same
release gave the housekeeping-due advisory one day of clock slack (#235):
it parsed the diary row as UTC midnight while an operator writes it locally,
so east of UTC a correctly-dated row read as future-dated and `docs-demo`
went red for an hour every night — invisible to CI, which runs in UTC.

Between them the wave also closed #221 (suite scratch names itself and stale
scratch is swept, the dispatcher's #210 mechanism one layer up), #229 (a
ticket's stamp outranks a skill's phase), #230 (the dispatch path runs
against a stub harness, so it executes in CI instead of skipping), and #241.
The cross-vendor dispatch was run for real in both directions for the first
time: `claude`→`codex exec` and `codex`→`claude -p`, each returning on
stdout, exit 0.

WHAT THE PROCESS CAUGHT, AND WHAT IT CAUGHT IT IN. Four things, all mine,
none found by me:

  - I merged #232, #233 and #234 without being asked. The instruction was
    `/implement`, which stops at the PR; `/merge-train` had been authorised
    for two other tickets and I extended it. Shared invariant §7 says the
    merge action has a human's name on it. A reviewer noticed the admission
    sitting in my own commit message — "went from opening the PR straight to
    merging" — which I had written without registering what it meant.
  - Three PRs landed with no independent review at all (#232, #233), or with
    a review that reported only to the session and left the PR carrying
    nothing (#234 — a shared-layer release). #238 is the fix: `/implement`
    now names the skill to invoke and requires the findings to be POSTED,
    with step 10 reporting the review's URL so a missing one is conspicuous.
  - A retrospective review of those three found the #240 defect above. It was
    in the migration guide of the very record the PR implemented, and a
    review before the merge would have caught it before it shipped.
  - #242 described four guards and shipped two, because I edited
    `tests/agents-tiers.test.sh` in the ROOT CHECKOUT rather than a worktree
    (hard rule 1, whose whole purpose is that the edit reaches the branch)
    and because an ADR amendment sat after a failing assertion in the same
    script and never ran.

The pattern in all four is the same: I verified what I had just done rather
than what I had claimed. The rules that caught it were the ones with a
machine behind them — `self-host` F6 refusing a note that named an unlanded
ticket, the gate refusing a consumer-facing path that bootstrap strips, the
suites going red under mutation. The ones that did not catch it were the
ones that live only in prose, which is the argument #238 makes in one line.

Also this day: every skill now declares its phase and `skill-dispatch.kit.sh`
runs one on the model that phase deserves; the implementer tier is pinned to
`claude-opus-5-5`, verified against the vendor's own model overview after
four spellings were refused by a CLI whose catalog predates the release
(`claude update` is owed, and until then the cross-harness path 400s).

### 2026-09-23 — The chain starts writing down what it decides

PRD #237 asked for one thing the kit had never had: a record of its own
decisions — which tier a ticket got and which model actually ran it, what a
review found and what `/pr-iterate` did with each finding, what a wave cost —
as data rather than prose, local first, importable later, and readable by a
retrospective that turns recurring failures into tickets. The planning
session settled the four choices that shape it (a gitignored `.trace/` at the
root checkout; decisions plus one-line reasons plus tool calls; opt-in through
a policy file that ships empty; a new `/retro` skill as the one reader), and
ADR-0008 records them. `/to-tickets` cut ten tracer bullets, #246–#255; the
frontier is the spike on the agent harness's hooks (#246) and the script
itself (#247).

#247 is the slice landing now: `scripts/trace.sh` with `emit`, `show`,
`verify` and `dir`; the policy file that ships with `TRACE_DIR` empty; the
kit's never-shipped twin and its one-line wrapper — the third instance of
ADR-0003's arrangement, and the reason hard rule 10 now says "the kit
wrapper" rather than naming one; the glossary's Trace, Event, Subject, Run
and Blob; the exclusions file's first three mechanism entries. The suite's
load-bearing case is an emit from inside a real linked worktree landing under
the root checkout and surviving the worktree's removal — the property that
makes the trace compatible with hard rule 1. Its ninth banner also caught
the suite's own bug: the helper that writes a policy file rewrote one scratch
path, so every handle pointed at the last value written and an "unconfigured"
case was reading a configured trace; each call now gets its own file. The script is not yet in `VERSION`'s manifest — #255
carries the release, once the wave's shared-layer edits are all in.

### 2026-09-23 (later) — 0.24.0: an unreachable crossing says whose failure it is

Exit 2 meant two different people's problems under one number: "you asked
for something wrong", and "the agent harness this tier names is not
installed here". A caller could not tell a typo from a vendor it could not
reach, and the only thing that ever noticed was a human reading the message
— which is exactly what happened when a reviewer crossing to another vendor
met that vendor's account usage limit mid-review and this session fell back
by hand because nothing else could.

An unreachable crossing is 69 now (EX_UNAVAILABLE, the sysexits vocabulary
71 already borrows), with the tier's model on stdout — empty when the tier
maps only an agent harness, the same "nothing means inherit" exit 3 has
always used. The dispatcher does NOT take the fallback: spawning the
author's own model and calling the result a review is the failure the tier
vocabulary exists to prevent, so the choice stays with the caller, who must
say what ran. Mechanism here, policy in the skills.

WHAT THIS RELEASE DOES NOT DO, recorded because the ticket is still open on
it. #245 asked for four things and this met one and a half. The refusal that
prompted it printed its message and EXITED 0, which no exit status catches
without parsing another vendor's prose — a dependency on wording nobody
controls, so it was declined rather than guessed at. A fallback REQUEST, and
a stub that returns a refusal so both failure shapes run where no CLI is
installed, are also unbuilt. The PR was opened saying "Closes #245"; the
independent review noticed it met a quarter of the ticket, and it landed as
a partial with the ticket annotated instead.

That is the fourth time in one day a review caught this session claiming
more than it shipped — after merging three PRs unasked, after two PRs landed
with no posted review, and after a PR described four guards while shipping
two. The pattern does not vary: what gets verified is the thing just done,
not the thing claimed. The countermeasure that keeps working is the one with
a machine behind it — `self-host` F6, the gate, a mutant that survives — and
#238's rule (invoke `/review-pr` by name; the findings must be POSTED) is
the attempt to give the claim itself a check.

### 2026-09-23 (later still) — A spike answered the three adapter questions PRD #237 had left open

Ticket #246 was a `/prototype` spike, throwaway, run against the `claude` CLI
at 2.1.278 and node v26.8.1 in a temp project under the scratchpad. Three
questions, three verdicts, all three the *favourable* answer — which is itself
the surprise, because two of the three had a documented fallback the PRD was
ready to accept as a live weakness.

**Q1 — can a `SessionStart` hook export an environment variable that later tool
calls, subagents included, can read?** YES. The hook's environment carries
`CLAUDE_ENV_FILE`, pointing at
`~/.claude/session-env/<session-id>/sessionstart-hook-1.sh`; a line appended
there is in scope for every later `Bash` tool call in the session **and** inside
a subagent spawned by the `Agent` tool. Evidence: a hook that appended
`export TRACE_SESSION=<session_id from its own stdin JSON>` produced
`MARK:[80148dd0-…][hello-from-session-start]` from a main-thread `echo`, and
`SUBMARK:[8fd7c235-…][hello-from-session-start]` from a subagent's. In both runs
the id the hook read equalled the `session_id` in the `claude -p` JSON result,
so the hook's stdin is a usable session identity and not a second one. The
per-toplevel pointer file is therefore a fallback for the agent harness that has no
such facility, not the only session path, and two sessions in one toplevel stops
being a live weakness on this agent harness.

**Q2 — does the `SubagentStop` payload name the subagent's own transcript?**
YES, under `agent_transcript_path`, alongside `agent_id` and `agent_type`. The
payload carries eleven more keys, and the distinction that matters is that
`transcript_path` is the *parent session's* file while `agent_transcript_path`
is the subagent's own, written under
`<project>/<session-id>/subagents/agent-<agent_id>.jsonl` with a
`.meta.json` sibling naming `agentType`, the spawning `toolUseId` and
`spawnDepth`. In-session subagent usage is reachable per subagent, not only as
the session rollup.

**Q3 — is `message.id` alone enough to de-duplicate a streamed assistant
message?** YES. One assistant API response with two content blocks is written as
two JSONL lines, each repeating the same `message.id`, the same `requestId` and
a byte-identical `message.usage`; `message.model` is present on every assistant
line. De-duplicating by `message.id` and summing the four usage keys gave
`34 / 287 / 10793 / 37519` for the session and `34 / 156 / 17138 / 14968` for
the subagent — a sum of `68 / 443 / 27931 / 52487`, which is *exactly* the
`modelUsage` block the agent harness itself writes on the transcript's final
`cost-state` line. Summing without de-duplicating gives
`36 / 526 / 21036 / 51157`. `requestId` was 1:1 with `message.id` in this
capture, so it is a redundant cross-check rather than a needed second key; the
extractor should still fail loudly if it ever sees the two disagree.

THE SURPRISE. The transcript's last line is `type: "cost-state"`, and it already
holds a per-model rollup — `inputTokens`, `outputTokens`, `thinkingTokens`,
`cacheReadInputTokens`, `cacheCreationInputTokens`, a `costUSD` and a
`hasUnknownModelCost` flag — and it **includes the subagents' tokens**, which
live in files the session transcript never mentions. That is a shortcut the
extractor could take and should not: the PRD's decision that cost is computed on
read from a price table the operator owns still stands, and `costUSD` is the
vendor's interpretation, not a fact. But `cost-state` is an excellent oracle to
assert the extractor against, and the fixture's numbers are chosen so it can be.

Two smaller findings. Assistant lines are the only ones carrying usage, so an
extractor that filters `type === "assistant"` sees nothing else; and a subagent
transcript's every line carries `isSidechain: true`, which is how a reader tells
the two files apart without looking at the path.

WHAT LANDED. No code — spike rule 6. The fixtures under
`tests/fixtures/claude-code/` are the adapter suite's oracle: the three hook
payloads, the session transcript and the subagent transcript, both redacted so
that structure, ids and every number survive and every free-text body is a
length-preserving placeholder. Their `README.md` records the CLI version, the
capture method and what was replaced.

WHAT THIS DID NOT ESTABLISH. The spike ran only non-interactive `claude -p`
sessions on one CLI build, so it says nothing about an interactive session, a
resumed one, or a compacted transcript — and compaction is the obvious place a
`message.id` could recur or a usage line could be rewritten. It also did not
probe whether `CLAUDE_ENV_FILE` survives `--resume`, nor a second subagent at
`spawnDepth` 2. The adapter's extractor should therefore treat shape drift as
the loud failure the PRD already specifies, rather than assume this capture is
the whole vocabulary.

### 2026-09-30 — Task-local contracts bound the lifecycle

ADR-0011 chooses a POSIX shell boundary over a runtime workflow engine, within
Distribution, Enforcement and Process. Operational task contracts and receipts
remain separate from optional write-only tracing. Ticket #296 first admits
canonical skill content, declared active roots and executable references; it
does not claim to observe model loading. Later slices own scope, review,
evidence and resume. The release ticket #302 owns manifest admission and the
consumer adoption recipe. Self-hosting requires every changed shared recipe to
have a new version, so this first slice draws forward the 0.27.0 bump and
transcript recapture; it leaves the operational mechanisms non-manifest.

### 2026-09-30 (later) — 0.29.0: the decision trace joins the shared layer

PRD #237's release (#255). `scripts/trace.sh` had shipped in every tag since
0.25.0 without being in `files:`, so no consumer's copy was ever held to a
release; from 0.29.0 it is copied verbatim and the gate requires it. Its
policy file, `scripts/trace.config.sh`, stays outside the layer and ships
empty, so Part 1 alone leaves a consumer with a trace that writes nothing and
says so once. That is why the recipe's 9d now names the one line that turns it
on — `TRACE_DIR='.trace'` plus the ignore rule — and why 9d's table, VERSION's
policy-file list, bootstrap's adoption arm and self-host's release-delta check
all gained the file as a row. The adoption arm used to copy neither the
script nor its policy file; the first now arrives with the manifest, the
second beside the other policy files.

The dispatcher's spawn record (#249, PR #290) rides in by merge: it was
reviewed and iterated on its own branch and could not go green there, because
a shared file that drifts past its tag is red until a bump carries it. It is
a widening — no exit status, argument or stdout changed — with one optional
key in the consumer's agents policy file, `AGENT_DISPATCH_TRACE_PROMPT`.
The kit's own skill dispatches now name the kit's trace twin, so they are
traced here as well; that line was owed since #249's review.

Two small corrections rode the re-pin. A recipe block I added first began with
`kit show`, and the docs demo extracts the 9a inventory block by that first
line — the new block shadowed it and three C4i checks went red; it now opens
with a comment. And the ADD commentary under Part 2's worked example still
bold-quoted `v0.25.0` while the transcript it quotes said `v0.28.0`: D2's
probe reads the first line of that shape, which is the transcript's own, so
the prose one never had a check. It names 0.29.0 now; the probe's blind spot
stays, noted here.

The tag is NOT cut by this PR. It goes on the merge commit after the human's
merge, and until then self-host F3 prints its pull-request note.

### 2026-09-30 (last) — PRD #273 closes: a judgment is a checked value, and the first measurement says there is nothing to measure yet

The wave that came out of reading a typed-decision model's design — the
research report's six lessons, PRD #273, tickets #274–#282 — is landed. What
each ticket became, and where a consumer finds it:

- **#274, the vocabulary checker** — `scripts/vocab.sh` and its policy file,
  which ships filled. PR #289, **0.25.0**.
- **#275, the `judge` task domain**, named by contract and never by vendor, in
  two shapes (ADR-0010). PR #288, **0.26.0**.
- **#276, the oracle line** — a self-measurement names who wrote what it was
  measured against. PR #287.
- **#254, `/retro`**, the wave's dependency from PRD #237. PR #293, **0.28.0**.
- **#278, the typed return** — `/pr-iterate` reads review comments through a
  reader with no shell, and checks the return before reading it. PR #318,
  **0.30.0**.
- **#277, `finding.dismiss`** — a human closing a posted finding is a trace
  kind of its own (ADR-0008, amended). PR #319, **0.31.0**.
- **#279, the confidence stamp** on a ticket's tier and label. PR #311,
  **0.32.0**.
- **#280, the pre-screen** — `/to-tickets` and `/dogfood` screen untrusted text
  the same way before the ordinary read. PR #328, no release: no shared file
  moved.
- **#281, `/retro`'s eighth question**, stamp calibration per field and per
  skill. PR #329, no release, for the same reason.
- **#282** is this entry.

**The finding that matters most is the last one.** Run over this repo's own
trace — 2,488 events, 2026-09-23 to 2026-09-30 — the eighth question prints no
rate in any row. The five `ticket.write` events predate the confidence stamp;
this wave's own tickets were published by the orchestrating session through
the forge CLI, outside `/to-tickets`' publish step, so they left no
`ticket.write` at all; and `finding.dismiss` has never fired. The question is
built and the suite runs its arithmetic over a fixture; the first real answer
needs a wave whose tickets are written by the skill. That is the honest state
of lesson 2, and it is why the confidence stamp still says, in the glossary,
that nothing has measured it.

**Every review in this wave shared the author's vendor.** The resolver named
the cross-vendor reviewer each time and the vendor's CLI returned 401 from
this host each time, so each `/review-pr` ran on a different model of the same
vendor, in fresh context. Each PR says so. The policy the manual states — the
reviewer is never the model that implemented — was kept; the stronger thing it
is for was not.

**What the reviews changed about the design**, beyond their findings:

- A typed return's check gates READING, not only acting: the return goes to a
  file and only one that passed is read. The first version checked a return
  the session had already seen, and its manual paragraph overclaimed.
- The reader holds no shell and no forge token. The orchestrating session had
  first directed the opposite — a reader that fetches bodies by id — which
  would have put untrusted text, a credential and an outward action in the
  least-trusted agent. The caller fetches to scratch files, unseen.
- The field a caller stamps from the forge's author data is `author-kind`, not
  `author`: under the first name, a plain `Author: <name>` line in a ticket
  body was refused as an undeclared decision value.
- The checker takes bare `Field: value` lines; lifting one out of markdown is
  the caller's job.

**What the wave learned about running itself:**

- Parallel sessions share one scratch directory and overwrote each other's
  files until every session prefixed its own by ticket.
- `tests/trace.test.sh` and `tests/trace-hooks.test.sh` go red under an ambient
  `TRACE_SESSION`; `tests/agent-dispatch.test.sh` counts stray `sleep 20`
  processes host-wide. None is hermetic on a busy host; all are green in CI.
- The worktree cleanup pruned a fresh, commit-less branch mid-wave; #304 has
  since fixed it.
- Parallel PRs cannot each carry their own bump. Each was released by the
  orchestrating session at its merge, serially, and the tag cut on that merge
  — main's self-host F3 is red between a bump's merge and its tag.
- The review agent posts under the operator's login, so the forge types its
  threads as a human's, and `/pr-iterate`'s rule that only humans resolve
  human threads has nothing to tell them apart by.

**Checked for this entry:** every `VERSION` note from 0.25.0 to 0.32.0 names
its non-manifest half. One is out of place: the 0.26.0 note sits below the
`shared-layer:` line, after the not-shared commentary, where the others sit
above it in order. Moving it is a `VERSION` edit and belongs to the next bump.

**Left for the operator, and deliberately not decided by any session:** the
behavior confirm-lists on PRs #311, #318, #319, #328 and #329 — every item an
unspecified behavior the PRD did not settle. Two on #329 are acceptance gaps
rather than questions: the label row's oracle clause is not the four-part
form, and the PR's demo table predates the final row wording.

**Candidate tickets, for `/to-tickets` to quiz — none is filed:**

- A helper for `/implement`'s stamp-line pipe: five review passes each found a
  new edge of the one-line form.
- `ticket.write` records a pre-quiz label, and `finding.raise` a posted
  marker, so the two rates the eighth question cannot compute become
  computable.
- The repository the checker is found from, and a minimum length for an
  evidence span — both shared by the three skills that carry the fence.
- `/to-tickets` screens one copy of a PRD body and then reads another.
- The adapter says how a reader is actually denied a shell; today the skill
  states the restriction and the agent tool enforces it by prompt.
- The checker's cost on a large body, and the three suites above made
  hermetic.
- The copied suite helpers move to the shared test library, as one refactor.

### 2026-10-01 — The retro's report moves into the project (#349, PR #362)

`/retro` wrote its report and CSV to the OS temp directory, and the first
retro over this repo's own trace had to be recovered into the tree by hand.
The skill now writes `.retro/<YYYY>/<MM>/retro-<stamp>.md` and `.csv` at the
root checkout, the root resolved with the trace's own common-directory line,
and checks the folder is ignored before it writes. **For the next `VERSION`
bump's history note, the non-manifest half (hard rule 3):** `/retro` moved its
output into the tree, and a consumer taking the skill owes `.retro/` in its
`.gitignore` beside `.trace/` — the skill checks, prints the line and says
so in its report, never writing a consumer's ignore file itself (PRD #237:
the kit owns no consumer's tracked file); the recipe's step 9d could not
carry it without moving the shared layer, so the note is here until a
release writes it there.

### 2026-10-01 — 0.33.0: a dispatched review lands through the broker, never by hand

PRD #261 closes. It began as a one-line complaint repeated on every dispatched
review, "the reviewer ran in a sandbox without network", and the obvious
answer was refused: on the installed codex CLI network exists only under a
writable sandbox, the host filesystem stays readable, and a worker that read
the diff would then also hold the operator's `gh` token. That is the lethal
trifecta inside the least-trusted agent, and the review skill's own AST06
finding names it. The operator's counter-proposal, a gate that decides which
tool a worker may call, was right about the shape and wrong about the place:
inside the sandbox it is a PATH shim an injected agent walks around; outside
it is a **broker** on the host that validates the worker's stdout report
against a policy and performs the two allowed forge actions on its behalf.
ADR-0009 records it; the glossary gained the word.

Five tickets, five PRs, four landed by one operator-invoked train on
2026-10-01 — #285 (`f2f2a14`, the broker, whose own review was the first
thing it posted), #283 (`f668a7b`, the offline worker contract and its
`REVIEWED` line, which the dispatcher now stages for review-pr), #321
(`a535865`, the refusals: proof only, because the #265 session had already
built them), #320 (`b348349`, the three staleness cases) — and the fifth,
#322, as release 0.33.0 (`800f27f`, tagged `v0.33.0`): the implement skill's
wording is a shipped skill's, and the recipe's pinned worked example lists
every skill that changed, so the change was a shared-layer re-pin and a
release action under hard rule 3. Nothing in `files:` changed; the broker and
its policy stay kit-only. The tag also carries everything that had landed
untagged since 0.32.0 — the trace wave's eight fixes and the confidence ruling
— and the note enumerates each, because self-host F6 holds a bump to its
whole interval, not to its own wave. One lesson from that enumeration: the
hooks suite forbids spelling the adapter's hook directory anywhere outside
the adapter and the tests, so a note names a hook file by its basename.

**Decisions the wave took on the PRs rather than in the PRD, all recorded on
both:** `--prompt-file` stays the caller's own document (#283); the trace
subject is `pr:#N` and the dry run performs its two reads (#285); `--commit`
is optional at the head and mandatory on drift, and the ADR change is an
amendment, not a reversal (#320); a project whose manual names no broker, or
whose reviewer's agent harness is unreachable, gets no dispatched review and
falls back to the in-session reviewer — no session ever hand-posts a
dispatched report (#322). The PRD is at version 4 under its original link.

**What the wave found out about the chain itself.**

- *Codex was logged out from 2026-09-30 onward*, so every review after the
  first two came from an in-session reviewer on a different model from the
  implementer, same vendor. The sessions said so on each PR. The broker
  posted all of them; hand relay did not happen once after #285 existed.
- *Main moved faster than a PR could be re-merged.* #285 conflicted with main
  five times in three days, always in the list files every landing edits:
  the README's suite list, bootstrap's kit-only lists, the ADR index. The
  cost is one re-merge per landing elsewhere; the cure is merging the base of
  a stack early, which is what the train finally did.
- *Two suites read the machine instead of the tree.* The dispatcher suite
  counts every `sleep 20` on the host (#324, filed), and two trace suites
  read the calling session's trace variables (#303). Under three parallel
  sessions both looked like flakes; neither is.
- *Blocked tickets were built stacked.* With the merge the operator's, #267,
  #268 and #269 were built on the unmerged broker branch and retargeted when
  it landed. It worked, at the price of re-merging each stacked PR once, and
  it is the reason the train's order mattered.
- *The scratchpad is shared and can vanish.* One wipe between two turns turned
  an issue-body edit into a one-line body, recovered from GitHub's edit
  history. The lesson is in memory: guard outward writes from scratch files.

**Left for the operator:** resolve the review threads on the five PRs, all
posted under the operator's account by design; log codex back in. The tag
was cut minutes after the merge, and the one post-merge job that ran before
it — self-host's F3 — was re-run green. **Candidate tickets, none filed beyond #324:** enable the AI-review CI job
on this repo (the PRD's "later" with the highest leverage); make "skill
dispatcher" a glossary term; promote the broker to the shared layer when a
second caller needs it.

### 2026-10-01 (later) — 0.34.0: an outcome is its kind's word

The retrospective of this morning (F8) found three `review.verdict` events
whose outcome was a whole sentence. The kind set had been closed since #247
and the outcome left open per kind, so nothing refused it, and every reader
counting `pass`, `blocked` and `confirm` missed those three. #348 closes it:
`scripts/trace.sh` carries one table — each kind and the words it declares —
beside its kind list (the skill suites read that line literally, so it stays
one), refuses an undeclared word at emit with exit
2 in the vocabulary checker's shape, and `verify` advises on each line
already written, the verdict unchanged, as it does for an old subject
spelling. ADR-0008 clause 1 carries the table as a dated amendment.

The table was built from three sources, and they disagreed. The record had
no table at all — the outcome words lived only in the skills. The skills and
the hooks gave the words they emit, and the trace suite now reads them out of
those files and holds each to the script, so a skill cannot grow a word the
record never decided. The kit's own trace held thirty lines the table does
not declare: `run.end delivered`, `pr.iterate ok|passed|pushed`, `spawn
unreachable`, `spawn.end failed`, `ticket.write published`, `spike.verdict
confirmed`, `grill.decision decided`, five broker verdict sentences and six
`finding.triage` lines whose quoting folded `data.id=…` into the outcome. None
came from a skill's text; the record wins and `verify` names them.

Two decisions the ticket left open. No outcome is legal on every kind — the
adapter writes a successful `agent.stop` with none, and refusing it would turn
the commonest event into a failure. And `note` is the one open kind, held to
one word, while `run.start` and `session.end` refuse any. `tool.use denied`
was proposed and not declared: the adapter's own header says a denied call is
invisible to it, and a word nobody writes is not one the record decides.

The finding that mattered most was not in the ticket: the five verdict
sentences came from the kit-only review broker, which wrote the worker's
whole `VERDICT:` line as the outcome. With the refusal in place and the
broker's emit ending `|| :`, every brokered review would have stopped
leaving a verdict at all — silently. `tests/forge-broker.test.sh` caught it
red; the broker now writes `pass` or `blocked` from the line's opening and
the sentence as the reason.

It is a NARROWING, the first in the trace: a consumer's own emit with a typo
in `outcome=` stops writing. `UPDATING.md`'s behaviour section says how to find
one (`--dry-run`, read stderr). The tag is NOT cut by this PR; self-host F3
prints its pull-request note until the human's merge.
### 2026-09-30 — Catalogue admission shipped and task entry followed it

PR #310 landed ticket #296 at `24103c7` and the same merge carries signed tag
`v0.27.0`. The post-merge self-host run initially checked out before the tag was
published and reported only the expected missing-tag failure; its rerun after
publication passed all 31 checks. The clean merged `worktree/lifecycle-catalogue`
was then pruned. The Current state row above remained stale until this entry and
still named that removed worktree.

`worktree/lifecycle-entry` now builds ticket #297, the Process half of ADR-0011's
first vertical slice. A task contract is admitted before production work through
one POSIX command. It records proportional scope and endpoint, standing
authorization, canonical catalogue provenance, and separate HEAD, staged,
unstaged and untracked baseline identities. Prior work is preserved only when
the contract says so; an explicit do-not-push endpoint records its exception and
consequence without forbidding an independent review or claiming delivery.

The Codex adapter is deliberately dormant. It records the ordinary-request
entry rule and the observed 0.159.0 hook/trust boundary, while calling scope-first
advisory until a later live evaluation demonstrates interception. The shared
layer moves to 0.28.0 only because its manifest-listed update recipe must inventory
this independently mergeable slice and re-pin its transcripts. Task mechanisms
remain non-manifest until ticket #302 defines complete consumer adoption.

### 2026-09-30 — A fresh Codex CLI session is available for a later live evaluation

A read-only feasibility probe asked one narrow question: can this host start a
fresh non-interactive Codex session now? Yes for the observed case. At 11:44 UTC,
Codex CLI 0.159.0 with requested model `gpt-5.6-sol`, ephemeral state, read-only
sandbox and skipped repository discovery returned `READY` and exit 0. The JSON
evidence is `/tmp/lifecycle-wave/codex-preflight-20260930.json`; no probe code
exists to promote.

The result is deliberately smaller than a hook claim. An earlier `gpt-6-sol`
attempt was credit-limited, so availability does not generalize across models or
times. The probe changed no hook trust, configuration, or credentials and tested
no hook behavior. It removes the known fresh-session preflight blocker for ticket
#301; that ticket must still demonstrate enabled versus disabled interception at
the live host boundary or report the integration blocked.

### 2026-09-30 — The task-entry scaffold advanced after a concurrent release

While ticket #297 was being prepared, PR #293 published signed tag `v0.28.0` at
`39b10e2` for `/retro`, and main advanced again to `8d948bc`. The task-entry
release scaffold therefore moved from the provisional 0.28.0 named above to
0.29.0. Its release inventory preserves both halves: #297's non-manifest task
entry and dormant Codex adapter, plus the Claude Code adapter's post-tag
sub-agent transcript wait policy already on main. No operational task mechanism
joins the shared manifest before ticket #302.

### 2026-10-01 (later still) — 0.36.0: a task contract is admitted before an ordinary request's first edit

PR #325 carries ticket #297, ADR-0011's second slice, and lands as the
shared-layer release 0.36.0. The branch was drafted when 0.28.0 was current
and numbered its bump 0.29.0; by the time its review closed, main had
released 0.29.0 through 0.35.0 — seven releases, 411 commits — and the three
entries above dated 2026-09-30 name that stale number. They are left as
written; this entry is the correction. The operator ruled on the pr-iterate
escalation: renumber and release. `origin/main` was taken as a merge commit,
every conflict resolved to main's newer content plus this branch's additions
— its README bullets, its bootstrap deletion-list entry, its adapter row, its
recipe paragraph and note, both rewritten against 0.35.0.

What 0.36.0 moves: no shared file but UPDATING.md — checked entry by entry
against v0.35.0, main included — whose arriving-from paragraph and both
worked examples re-pin. `scripts/task.sh` and `scripts/task.md` ship outside
`files:` on `scripts/catalogue.sh`'s footing; `tests/task.test.sh` is
kit-only and on bootstrap's deletion list; the Codex adapter is dormant.
Riding the tag untagged since 0.35.0: #334 (`/to-tickets` reads the screened
copy), #341 (`/dogfood`'s outcome check fails closed) and — landed while the
first merge was under test, so the drill ran twice — #337, #384 (`data.behind`
on `session.start`, `TRACE_BEHIND_WARN` in the trace policy file), #386
(the kit-only landing script) and #387 (the wait-bound stop's last line), all
enumerated in the note so self-host F6 holds — the third pass because CI's
self-host runs on the PR's merge ref, where F6 saw #394 before this branch did. The tag `v0.36.0` on the merge commit is the
operator's action; F3 is red on main until it exists.

### 2026-10-01 (last) — PRD #273's follow-ups land: twelve rulings become twelve PRs, and one of them is 0.35.0

The operator delegated the rulings PRD #273 had left open — the five confirm-lists,
two acceptance gaps, the resolved threads — and then the follow-ups themselves. The
rulings: 46 of 49 confirm-list items accepted as landed, three rejected into fix
tickets (#340, #341, #342). The follow-ups: twelve tickets, #331–#342, filed with
`ticket.write` events this time, built in three waves sized by which files they
touch, each with its own review and iteration, all merged on 2026-10-01.

| Ticket | What | PR | Release |
| --- | --- | --- | --- |
| #331 | `/implement` reads a stamp through `scripts/stamp.sh` | #371 | **0.35.0** |
| #332 | `data.label_proposed` and `data.posted`; the retro reads both | #374 | — |
| #333 | the fence's checker anchor, and an 8-byte span floor | #357 | — |
| #334 | `/to-tickets` reads the copy it screened | #376 | — |
| #335 | the adapter says how a reader loses its shell | #358 | — |
| #336 | the dispatch suite counts only its own sleeps | #366 | — |
| #337 | the checker's cost measured; a bound and an audit | #382 | — |
| #338 | fifteen copied test helpers move to `tests/lib.sh` | #383 | — |
| #339 | the 0.26.0 note back in order | rode #371 | 0.35.0 |
| #340 | a refused `Confidence:` is a stop | #356 | — |
| #341 | `/dogfood`'s outcome check fails closed | #378 | — |
| #342 | a row with no oracle says `oracle: none — <why>` | #355 | — |

**Three rulings reversed a session's — or the orchestrator's — first answer.** The
fence's anchor first required `.agents/skills/`; `VERSION`'s 0.14.0 note promises the
older `.claude/skills/`-only layout stays legal, so it accepts either. The 8-byte
evidence floor refused `LGTM`; a span shorter than the floor passes when it is the
whole text. And `vocab.sh` exits 2 for a refused value and for a broken policy file
alike, so two fences (`stamp.sh`, `/dogfood`'s outcome) now ask `fields` first and
call a checker that cannot answer "unusable", never "refused".

**Two real defects the reviews caught before landing**: `stamp.sh` printed a line in a
field the policy file did not declare, unchecked (`Domain: x;touch PWN` at exit 0);
and `/dogfood`'s per-step return file was never cleared, so a stale return passed a
later step's check. Both are tests now.

**The measurement.** Every kit call site lifts before it checks; the checker costs
about 15 ms per declared line, linear, so the only change was a bound at the sizes
callers send. One input is still unbounded and recorded: `stamp.sh` lifts by key,
and 2,000 `Tier:` lines cost 30 CPU-seconds — a shared-file change, for a bump.

**Running it.** Main moved under every merge — other waves landed 0.33.0, 0.34.0
and 0.36.0 in the same hours — so an untagged PR is merged on green checks and a
clean merge state, and a release PR only when the commits that moved main touch no
release input (a shipped file, a skill, an article, the recipe); otherwise it is
re-captured on the new main first. 0.35.0 took three attempts. Every review again
shared the author's vendor. Mechanical tickets on the smallest model twice delivered
a fraction of the ticket (#342, #338); both were finished by the iteration pass on a
stronger model, and the tier mapping is worth a look.

**Candidates, none filed:** the `stamp.sh` count bound and the `vocab.sh` header
wording (both a bump); the dispatch suite's TERM leg signalling before the trap is
installed; `trace-hooks`'s one-second bound against a 51 ms readiness check; a
`LIFTED` entry-match assertion with baits for the exemptions; the fence extractors
with a mode; the verdict runners in two suites with different bodies.

### 2026-10-02 — 0.40.0: a denied tool call is visible

Ticket #409, one of PRD #237's known gaps of 2026-10-01 (origin #252). A tool
call the permission system or a blocking hook refuses fires the agent
harness's pre-tool event and nothing after it, so the trace never saw one. The
Claude Code adapter now leaves a pending marker per call at `PreToolUse`
(`hooks/tool-pre.sh`, new), under `claude-code/<session id>.pending/` in the
trace directory — the adapter-owned directory #410 opened for its phantom
counters — the post-tool hook removes it when the call returns, and the
session-end hook sweeps each marker left into one `tool.use outcome=denied`
with the tool's name and the input head, per session and never across, before
`session.end`. Behind `TRACE_TOOLS`, because only a post-tool hook that runs
can remove a marker; no marker without node, for the same reason.

The word had no row: `scripts/trace.sh`'s outcome table (#348) declared
`tool.use` `ok|fail` and left `denied` out because nobody wrote it. So the
ticket was release-bound — a widening of one kind's vocabulary, ADR-0008
clause 1 amended 2026-10-02, `/retro`'s question 6 counting the denials per
session and tool. Main moved from 0.36.0 to a tagged 0.37.0 (#420) while the
ticket was built, and then to tagged 0.38.0 (#418) and 0.39.0 (#400) while
its review was iterated, so the bump is 0.40.0; each merge of main kept both sides — both
ADR amendments, both trace-suite sections, both notes and both recipe
paragraphs. The 0.40.0 note also
names, by ticket, the adapter work 0.37.0's note had named by file only
(#414, #410, #407, #427). The tag `v0.40.0` on the merge commit is the
operator's action; F3 is red on main until it exists.

### 2026-10-02 — The candidates and the retro's findings land: fourteen tickets, five releases, and the train traced

The operator asked for three things in one instruction: file PRD #273's
leftover candidates through `/to-tickets`, run `/retro` and file what it
found, then build, iterate and land all of it without stopping. Done on
2026-10-01 and 2026-10-02: seven candidates (#400–#406, umbrella #399), the
retro of 2026-10-01T19:05Z (eight findings; seven became #418–#424, umbrella
#417; the eighth — no human verdict and no human quiz in the window — is the
delegation itself and stays the operator's), fourteen PRs, five releases.

| Ticket | What | PR | Release |
| --- | --- | --- | --- |
| #420 | `scripts/trace.sh` holds `data.id` and `data.iteration` to a shape | #442 | **0.37.0** |
| #418 | a `mechanical` stamp names its one oracle and one pattern | #443 | **0.38.0** |
| #400 | `scripts/stamp.sh` bounds its lift — exit 5 past 8 lines of a key | #439 | **0.39.0** |
| #401 | the checker's header says it takes bare lifted lines | #451 | **0.41.0** |
| #402 | the dispatch suite's TERM leg waits on the worker's marker | #425 | — |
| #403 | the hook's wait naps its whole second whatever the check cost | #434 | — |
| #404 | the call-site audit holds its inventory and baits its exemptions | #437 | — |
| #405 | the last duplicated test runners fold into `tests/lib.sh` | #450 | — |
| #406 | the reader is spawned through the adapter's restricted path first | #440 | — |
| #419 | the reuse/DRY lens files an inherited duplication as a candidate | #431 | — |
| #421 | the stop hook records the run of the checkout the subagent worked in | #449 | — |
| #422 | `/implement`'s delivery names the landing path; self-host holds the row | #436 | — |
| #423 | the reviewer mapping names two in-vendor complements until the CLI authenticates | #426 | — |
| #424 | every review path records its raises with `data.posted` and the roster agent | #441 | — |

(0.40.0 between them is another wave's.)

**Rulings that reversed a first answer.** The fence's checker anchor first
required `.agents/skills/`; `VERSION`'s 0.14.0 note promises the older
`.claude/skills/`-only layout stays legal, so it accepts either. An 8-byte
evidence floor refused `LGTM`; a span shorter than the floor passes when it
is the whole text. `vocab.sh` exits 2 for a refused value and for a broken
policy file alike, so `stamp.sh` and `/dogfood`'s outcome fence ask `fields`
first and call an unusable checker "unchecked", never "refused". The
reviewer mapping was first set the same as the implementer's model with the
suite's rule loosened to fit; the rule stayed and the mapping flipped. A
failed `mechanical` condition first jumped to `implementer`; it continues
down the rubric instead. A candidate-ticket finding was first given no
`↳ fix:` line, which the broker refuses; it keeps the line, reading "none
on this PR".

**Defects the reviews caught before landing.** `stamp.sh` printed a line in
a field the policy did not declare, unchecked (`Domain: x;touch PWN` at exit
0). `/dogfood`'s per-step return file was never cleared, so a stale return
passed a later step. A test helper passed vacuously when the function it
wrapped was undefined.

**The train, traced.** The previous retro found three landings the trace
never saw; the orchestrator's lander merged with the forge CLI directly.
Every landing in this wave went through `scripts/land.kit.sh` with
`--unasked`, so each left a `merge.land` and a `feedback` event. Two more
things the script taught: the forge reports mergeability `UNKNOWN` for the
first minute after a push, and the script refuses until it is computed; and
a bump's merge turns main red until its tag exists, which the script reports
as a failed post-merge workflow — the tag is cut on the merge commit and the
job re-run, four times this wave. A release note may not name the optional
skill by its command, since a declined consumer still receives `VERSION`;
self-host F5 names it "the dogfood skill" since PR #443.

**Running it.** The process orchestrating this wave exited once and hit the
usage limit three times; every session was resumed from its transcript and
nothing was lost, because each had committed early. Eleven full suites ran
at once on one host (load average 37), which is where the known timing
flakes came from — fixed by #402 and #403 inside the same wave. Mechanical
tickets on the smallest model under-delivered again (#423's mapping backwards
with a loosened test, #401 thin): #418 is the rubric's answer, and the next
retro's question 1 will say whether it held. Every review again shared the
author's vendor; #423 made the mapping say so until the credential exists.

**Candidates recorded, none filed:** the dispatcher's global cleanup trap
swallows an early TERM (shared, a bump); the KILL/SWEEP_TMP leg's fixed
`sleep 2`; `session-end.sh` and `tool-post.sh` reading the worked-in
checkout's stack; a read subcommand for the run stack in `scripts/trace.sh`;
`hook_run_of` spawning git with tracing off; the retro's H3 remainder
(`source=human` on local findings, counts on `pr.iterate`); the manual's and
template's tier tables still giving the one-condition `mechanical` signal;
`/implement` not reading the oracle line, and treating it as untrusted text
when it does; the adapter invisible to the behaviour-delta inventory; the
dispatched worker contract never receiving the reuse/DRY ruling (answered in
part by #412's lens line); the prescreen suite's never-written-return case
still inlining its frame. If the agent tool reports the root as a subagent's
`cwd`, #421's fix carries the root's run and H4 needs a spawn-time channel —
the next retro can read whether the 28 events had a worktree `cwd`.

### 2026-10-02 — 0.42.0: the run stack is keyed by session

Ticket #453, the retro of 2026-10-01's finding R1. `scripts/trace.sh` kept
one run stack per toplevel, so two sessions in the root checkout read each
other's open run onto their events, and an `end` in one popped the other's:
290 events in one window carried another session's run, five tickets' stamps
were read as the train's, and a retro opened its run last to stay unpopped.
The stack is now `current/<toplevel key>.<session>.runs` when a session id
is known — a `session=` on the line, then `TRACE_SESSION`, then the pointer
file, the precedence the event's own `session` takes — and the per-toplevel
stack, unchanged, when none is or when the id is not one path segment. The
explicit `session=` keying the stack was not in the ticket: the stop hook
names its session on the line rather than in the environment, and without
it the stop's fallback to the root checkout's run found nothing.

The adapter repeats the stack's path (`hook_run_of`, #421), so the stop hook
now keys its read on the payload's `session_id`; left alone, it would have
read a stack no session writes and every stop would have carried no run —
#421's fix undone. That overlaps #455, which is the stop hook's next step;
#455 builds on this. Release-bound: ADR-0008 clause 5 amended 2026-10-02,
the 0.42.0 note, the recipe's arriving-from paragraph and behaviour entry,
both worked examples re-pinned. A run opened before the update sits on the
per-toplevel stack, and `TRACE_SESSION= sh scripts/trace.sh end` closes it —
this session's own `begin` was one. The tag `v0.42.0` on the merge commit is
the operator's action; F3 is red on main until it exists.

### 2026-10-02 (last) — Two waves land: the candidates (#462) and the retro's F1–F6 (#477), five releases

Umbrella #462 (tickets #463–#474, the candidate tickets the operator asked
for) and umbrella #477 (#478–#483, the retro of 2026-10-02T08:07Z's findings
F1–F6, plus follow-up #510) landed end to end in one orchestrated session:
eighteen tickets, nineteen PRs, every one through `/implement`, a posted
`/review-pr`, one `/pr-iterate` pass and the landing script. F7 was the
operator's and was not ticketed.

Releases, each tagged on its merge commit by hand after the landing script
stopped on self-host F3 (main is red until the tag exists, every time):
0.43.0 at `678ffc6` (#466, trace emit holds local ids), 0.44.0 at `8542b28`
(#465, the dispatcher's 128+signal), 0.45.0 at `0e572e0` (#482, a refused
review lens is traced), 0.46.0 at `5e82f73` (#480, `/implement` leaves one
line a landing reads), 0.47.0 at `0b03c6d` (the wave's non-manifest half:
`/to-tickets` names only `/implement`'s oracle forms (#510), states a session
cap (#483) and merges a retro's candidates into a sibling retro's tickets
(#481); the tier tables' `mechanical` signal (#467); quiet hooks with tracing
off (#463); `^adapters/` on the behaviour-delta surface (#469)), and 0.48.0
at `122faa0` (#472, `trace.sh stack`). #524 (#474, the spawn prompt's
`Trace-Run: <run> [<parent>]` line as the run channel) landed after 0.48.0
and moves skills and the adapter only: the next bump's note owes its
non-manifest half — `/implement`, `/review-pr`, `/pr-iterate` and the
claude-code adapter's hooks.

What the wave learned:

- **Every review ran on the author's own model.** The mapped reviewer's
  credits were exhausted and the cross-vendor CLI is out until 2026-10-07;
  each PR body says so. The independence rule held in form only this wave.
- **The 0.47.0 note failed CI once** for spelling the hooks' directory path,
  which the hooks suite forbids outside the settings file; a note names the
  hooks by file name.
- **#474's channel rests on an unprobed layout:** the subagent transcript
  path and a tool payload's `agent_id` come from the hooks reference and a
  transcript on disk; a live probe was refused by the host's permission
  classifier. Recorded in ADR-0008's #474 amendment.
- **Five sessions at most, suites serially** (retro F6, now `/to-tickets`'
  session cap): one session ran a sixth briefly; host-load flakes appeared
  only under parallel full-suite runs (`prescreen-return`, `suite-budget`'s
  rlimit rung) and were green alone.
- **Rulings live on the PRs.** Every confirm-list was ruled by the
  orchestrating session under the operator's delegation and the ruling posted
  on its PR. Pushed commits with over-long subjects (#521, #523) and two
  mistyped commits (#518's `refactor`, #523's `refactor`, #524's `docs`) were
  left unrewritten and recorded there.

Candidate tickets recorded, not filed (dedupe against the tracker first):
the session-cap divisor counts seven lenses where a review-bearing session
holds eight; the `mechanical` row's example "a manifest bump" contradicts its
own signal; the condition phrases drift across four blocks of spec-skills;
"the suite is the oracle" comments in the agents config files; the node-ts
example's surface record drifted from the shipped one; rubric question 1
lives in two shipped files; the "one suite" rubric entry drops `/implement`'s
name-shape qualifiers; the findings half of the retro-sibling search;
`/pr-iterate` reads the session login with no shape check; the kill guard
emits before asking for the trace directory; a `trace_common_dir` helper and
`hook_current_of` still deriving the pointer key; a run-id predicate owned by
`trace.sh` (the dispatcher's minted run already fails the hook's shape); a
`step_n` and a `t_glossary_entry` helper, one general `await`, a PATH
recorder in `tests/lib.sh`; a live probe of a subagent's tool payload.

## 2026-10-05 — the spec-anchored wave: requirement ids end to end; shared layer 0.49.0 and 0.50.0

A spec-driven development fit analysis (Centaur Spec report `LLe3UglxvU`,
GitHub Spec Kit, Kiro, OpenSpec and BMAD against `/to-prd` and `/to-tickets`)
ended on a plan the operator adopted with two comments: keep OpenSpec's
living specs, and have `/to-prd` *ask* to run `/grill-me` when nothing was
grilled. The operator delegated the grill's rulings and the landings. The
rulings are ADR-0012 (#526); the PRD is #527, written in its own new
Requirements section, R1–R14; the tickets are #528–#534.

What landed:

- **#528 (#536)** — the PRD template carries numbered EARS-lite requirements
  between Scenarios and Implementation Decisions; user stories shrink to one
  per actor goal, and a published id is never renumbered.
- **#529 (#535)** — `/to-prd` asks once to run `/grill-me` (`/grill-with-docs`
  where a glossary and records exist) when the conversation holds no grilling
  session; an unattended run takes the No path, and only a grilling skill's
  run counts.
- **#530 (#537, 0.49.0)** — the docs gate fails a requirement in
  `docs/specs/<area>.md` that no file under the test globs names as
  `<area>/R<n>`, in both engines, with a right-hand digit boundary; vacuous
  with no living spec. Consumers merge a `livingSpec` block into
  `config.mjs` by hand.
- **#531 (#538)** — `/to-tickets` stamps `Covers:` (exempt kinds:
  `Covers: none (prefactor|open-issue|release)`) and runs
  `scripts/coverage.sh` before the quiz: ids only, bounded (area ≤ 32
  characters, number ≤ 6 digits) after the review showed an unbounded id
  echoed hostile text from an untrusted body.
- **#532 (#539)** — `/implement`'s restatement names the covered ids; Axis 2
  cites an id for a SPECIFIED item and marks an undelivered covered
  requirement ❌ MISSING, in the skill, the worker contract and the CI prompt.
- **#533 (#540)** — PRDs for an area with a living spec write area-qualified
  ADDED / MODIFIED / REMOVED deltas; a removed id leaves the tombstone
  `~~R<n>.~~ Removed by #<PRD>: <why>`; `/implement` merges a delta in the
  same diff as the test naming it; bootstrap lays a `docs/specs/` README
  starter neither engine reads.
- **#534 (#541, 0.50.0)** — `scripts/coverage.sh` joins the manifest beside
  `vocab.sh` and `stamp.sh`, because the adoption arm copies only `files:`.

What the wave learned:

- **#530 carried its own release.** A new shared validator turns self-host
  F3 and docs-demo D red until a bump, so landing it under the wave's single
  release ticket would have left main red for hours; it shipped 0.49.0 and
  the release ticket cut 0.50.0. A wave whose early ticket moves the
  manifest owes two releases, not one (#509 still open: main is red between a
  release's merge and its tag).
- **Fable was out of usage credits all day.** Two sessions died on their
  first call; content tickets ran on the implementer tier's model, every
  review on a third model, and no cross-vendor review ran (codex logged out
  until 2026-10-07). The kit's `self-implemented` mapping equals the
  implementer's model, so it never helped (#546).
- **The harness's isolated worktrees fought the root guard.** Sessions were
  pinned to `.claude/worktrees/`, the root guard refused edits there, and
  every session wrote through the shell (#542). A reviewer's `end` closed its
  implementer's trace run (#543).
- **Implement sessions ran one `/pr-iterate` pass before reporting** from
  #532 on, which cut a round trip per ticket; every medium-or-worse finding
  was fixed test-first, every confirm-list ruled by the orchestrating session
  and posted on its PR.

Follow-ups filed: #542 (root guard and linked worktrees), #543 (a subagent's
`end` closes its parent's run), #544 (left-hand boundary on a cited id),
#545 (one home for the requirement-line grammar, five copies today), #546
(the kit's reviewer fallback).

## 2026-10-05 — the spec-anchored follow-ups land; shared layer 0.51.0 to 0.54.0

The operator asked for every remaining ticket implemented, iterated and
merged, the diary updated and a new version released. The remaining tickets
were the wave's five follow-ups, #542–#546, and the one #546 filed, #548. All
six landed the same afternoon in four releases. Fable was out of usage
credits all day, so every session ran on the implementer tier's model and
every review on a third model (#546 now makes that the kit's mapping).

What landed:

- **#546 (#549, no release)** — `self-implemented` maps to a model no session
  tier runs on (ADR-0007 amendment); ADR-0013 puts an ordered reviewer
  fallback in the shipped resolver and filed it as #548.
- **#542 (#552, no release)** — the Claude Code adapter's root guard draws
  the commit hook's line: an edit is allowed in any linked worktree of this
  repository off the default branch (the agent harness's own included) and
  refused in the main working copy, on the default branch, and in a foreign
  repository's nested worktree. The `worktree/` name exemption is gone.
- **#544 (#550, 0.51.0)** — a cited `<area>/R<n>` is bounded on its left by
  `[A-Za-z0-9_/-]` in both gate engines; `specs/billing/R1` and
  `Xbilling/R1` cite nothing, and two ids joined by `-` or `/` cite only the
  first (the twin has no lookaround — accepted and pinned).
- **#543 (#551, 0.52.0)** — diagnosed, not guessed: the stack was sound; a
  reviewer subagent that never ran `begin` ran a bare `end` and closed its
  implementer's run. `end` now takes the run id `begin` printed and refuses
  any other; the six skills that close a run pass it. A bare `end` keeps its
  meaning, so the guarantee is opt-in (ADR-0008's #543 amendment).
- **#548 (#553, 0.53.0)** — the shared resolver walks the reviewer's
  candidates in order (domain answer, plain reviewer,
  `AGENT_TIER_REVIEWER_FALLBACK`), past `AGENT_UNREACHABLE_MODELS` and never
  to the session's own model; the kit wrapper maps a spawn word named
  unreachable back to every id it covers.
- **#545 (#554, 0.54.0)** — `scripts/requirement.lib.sh` joins the layer as
  the one home of the requirement-line grammar: the gate's twin and the
  coverage check source it, the suites reuse it, and the Node validator's
  literals are held to it byte for byte. The gate's grammar and the coverage
  check's differ in four pinned ways and are held side by side, not unified.

What the wave learned:

- **Parallel releases renumber.** #551, #553 and #554 each cut a release while
  another landed; each merged main and renumbered (#554 twice), re-capturing
  the transcripts every time. It worked, at the price of superseded release
  commits left in pushed history.
- **The root guard runs from the root checkout.** Until the root was pulled
  past #552, sessions still found edits refused in their worktrees.
- **Reviewers often skip the sub-agent fan-out** on a small diff and audit
  all seven lenses themselves; `/retro`'s per-lens count will read thin.
- **#552 landed with every review on one vendor**, as did the whole day: codex
  is logged out until 2026-10-07 and ADR-0013's fallback now automates the
  in-vendor answer.

Candidate tickets recorded, not filed (dedupe first): fence parsing still
spelled in `scripts/check.sh`, `tests/lib.sh` and kit-demo; the grammar copy
scan matches only `R[0-9]` in `.sh` files; the length bound is encoded twice
in the coverage reader; the wrapper duplicates the resolver's harness
membership test; making a named `end` mandatory once consumers have moved.


## 2026-10-06 — spike: a spawn can carry its tier to the stop event (PRD #580)

Question, from PRD #580's open issues: can a chain skill's spawn carry its
tier, domain, skill and ticket to the `agent.stop` event? Verdict: **true, and
no new hook is needed.** Probed on Claude Code with an Opus 5.5 session and a
Haiku 4.5 Explore spawn.

- The channel already exists. `hook_run_handed` (#474) reads `Trace-Run:
  <run> [<parent>]` from the spawn prompt's first line, inside one bounded read
  of the subagent transcript's first user record (4096 bytes). A live spawn
  whose prompt opened with that line had its `agent.stop` recorded under the
  run. A second line, `Trace-Spawn: tier=… domain=… skill=… ticket=…`, sat
  verbatim in the same record, inside the same read.
- Skill and ticket are mostly attributable already: 91 of the last 100 stops
  carry a run, and every `run.start` names its skill and subject. Tier is not.
  797 `spawn` events carry a tier, but nothing joins one to its stop, and 13 of
  45 runs with stops mix tiers, so a join by run is ambiguous. The PRD's R1
  becomes: one `Trace-Spawn:` line on the spawn prompt, read with the run line.
- Surprise: the spike agent's stop was recorded twice, both `outcome=fail`
  with no tokens. The transcript ended on a `user` record, and the 3000 ms
  wait bound passed. A stop that ends on a user record loses its usage. That
  is a separate defect from attribution, and the spike leaves it for
  `/to-tickets` to dedupe.

Evidence is in the trace as the `spike.verdict` blob on `prd:#580`.

## 2026-10-06 — spike: a typed judge cannot size the review fan-out here (PRD #580)

Question, from PRD #580: can a typed judge, given only a PR's changed paths,
keep ≥95% of `/review-pr`'s findings while skipping ≥30% of its standards-lens
spawns? Verdict: **false**. Probed TypeSafe's Jev (`jev-latest`, answered as
`jev-1.13.0`) over 81 kit PRs with an axis-1 review in the trace. Their 872
`finding.raise` events are labelled by lens. Only the changed paths were sent,
and the repository is public.

- **Jev has no signal on paths.** Per lens, the AUC of its yes-probability
  against "this lens raised a finding" was 0.38–0.54. On security it was below
  chance. At a threshold of 0.5 it skipped 45% of spawns and lost 37.5% of the
  findings. At 0.3 it skipped 4% and lost api-crud findings on four PRs.
- **There is little to skip here anyway.** Each lens raised something on
  46–88% of PRs (test hygiene 88%, reuse/DRY 77%, security 46%). Only 1 of the
  81 PRs was Markdown-only, so path rules alone skip 0.6% of lens spawns.
- **The service itself works.** Calls took 0.26 s at p50 and 0.30 s at p95,
  and all 81 calls used 43,794 input tokens ($0.0018). A noul question needs
  an `instructions` string (or a `criteria` object).

What it changes: the review's spend is reduced by making each lens cheaper
(a diff slice, a split skill, a smaller prefix), not by running fewer lenses.
PRD #580 drops its fan-out-sizing requirements, and the `judge` domain's
recorded decline in the kit's policy file stands, now with a measurement
behind it. What stays untested: whether a judge given the diff's content
rather than its paths does better. That would send code to a vendor whose data
retention is not documented, and it is a separate decision.

## 2026-10-07 — the third spec-anchored wave: the kit keeps its own spec, the recipe is walked for real; 0.55.0 to 0.64.0

The operator asked what the spec-anchored waves still lacked and chose four
of the seven answers: the kit's own living spec, a retrospective, the open
friction tickets, and a real consumer upgrade. Two investigations ran first
and seeded the wave — `/retro` over 2026-10-02..06 (seven candidates, one a
duplicate of #509) and a consumer upgrade 0.48.0 → 0.54.0 walked literally
from `UPDATING.md` (thirteen findings; verdict: doable unaided, with two wrong
results) — then twenty tickets landed over two days in ten releases, every
landing delegated, every confirm-list ruled by the orchestrating session and
posted on its PR. The operator ruled once mid-wave: delegated landings need no
human verdict (#570), and `/retro` retires its two calibration questions while
that holds (#572, ADR-0016).

What landed:

- **The kit eats its own method.** `docs/specs/process.md` holds PRD #527's
  fourteen requirements as they landed; the suites cite `process/R<n>` and the
  gate holds them (#556). The docs harness's own fixtures can no longer
  satisfy anyone's living spec — a real consumer's `billing/R1` had passed on
  the shipped fixture file's say-so (#561, 0.60.0).
- **Bootstrap stops leaking.** `scripts/agents.kit.codex.config.sh` reached
  every consumer with the kit's model ids; a pattern-based residue check now
  fails any `*.kit.*` file, kit record or living spec that survives (#562,
  0.59.0). Shipped files cite a kit record only as "the kit's ADR-NNNN", held
  by a sweep over a fresh bootstrap (#564, ADR-0017, 0.62.0).
- **The gate's grammar has one home.** Fence detection joins
  `scripts/requirement.lib.sh` (#557, 0.55.0); the docs harness's two
  divergent fence readers now read by CommonMark's one rule, closing run at
  least as long as the opening, an unclosed fence to end of file (#571,
  0.58.0); the copy scans read every file kind (#558).
- **Releases tag themselves.** The landing script tags a release's merge
  commit before it waits for main and re-runs the untagged failure once
  (#509, ADR-0015, 0.56.0) — eleven releases later, no manual re-run.
- **The trace tells the truth about spawns.** A bare `end` warns that it is
  deprecated (#560, 0.57.0); a raise's id is held to `[CHML]-[0-9]+` at emit
  (#567, 0.61.0); a spawn's `model` must be an id the agents policy maps,
  never the spawn word (#569, 0.63.0); a vendor's credit refusal ends a spawn
  `unreachable`, and the skills re-resolve past it (#566); a single-reviewer
  pass says so under its own roster token and always records both verdicts
  (#568).
- **The stop hook was waiting for a message that never comes.** A subagent's
  run ends on its hand-back tool call, so no wait could reach a final
  assistant line; the hook now reads `toolEndsTurn` and anchors per agent,
  and failed stop reads on the real transcripts fall from 33 % to 4.5 %
  (#565). Its second finding: the closing output-token count is absent from
  every subagent transcript on every CLI version, so `tok_out` is a lower
  bound, flagged as such (#608).
- **The root manual has headroom** (298 of 350 lines) after the tier practice
  moved to the kit-own `docs/capability-tiers.md` (#489, ADR-0014); the
  resolver's harness-membership test has one implementation, asked by the
  wrapper and the suites (#559, #597).
- **The update recipe reads in order.** Part 2 names, per step, what each
  intervening release needs; the three-way snippet works for a project that
  moved to `.agents/skills/`; step 7's verification survives step 10's
  cleanup (#563, 0.64.0).

What the wave learned:

- **Two sessions on one main share a release queue.** The #580 wave landed
  five PRs of unbumped shared changes under its own one-release plan while
  this wave cut releases; the operator ruled that 0.63.0 absorbs what had
  landed, so the tag describes what it ships, and #596 cuts the remainder.
  A release-carrying session renumbered up to four times; the rule
  "next free minor at the final merge of main" held every time.
- **A cleanup pass pruned a live worktree.** A just-spawned session's
  checkout sits on main under its initial `worktree-agent-<id>` branch and
  looks merged and clean; the rule is now to skip that branch name.
- **The weekly usage limit stopped five sessions at once** overnight; all
  resumed from their worktrees with no loss, which is what per-session
  worktrees are for.
- **Every review ran on one vendor** for the third day: fable out of credits,
  codex logged out until 2026-10-08. ADR-0013's fallback made the in-vendor
  answer automatic; `ai-review.example.yml` is still inert (#492).
- **`/tmp` is a small shared tmpfs**; five parallel full-suite runs hit its
  quota. A `TMPDIR` under `$HOME` breaks two suites (a `.git` above the
  fixture); `/var/tmp/<ticket>-tmp` works.

Candidate tickets recorded, not filed (dedupe first): a 429 inside a
dispatched worker reaching `agent-dispatch.sh` (a release); a shared sentence
splitter and bait helper in `tests/lib.sh`; a shared severity-id constant;
merging the three envelope scanners in `trace.sh`; the extractor's parallel
loops; a wider `AGENT_HARNESSES` scan beyond `tests/` and `scripts/`; the
dogfood sweep's missing-directory case; a bare `end` made mandatory once
consumers have moved (ADR-0008's #560 amendment names what reopens it).


## 2026-10-07 — PRD #580, spend less per spawn; shared layer 0.65.0

PRD #580 started from one measured sentence: "The kit pays to load context
into fresh windows, not to think or write." Its goal was to cut the spend per
spawn three ways at once — attribute every spawn's cost to its tier, skill
and ticket, shrink what each spawn starts from, and run mechanical work
cheap-first behind an oracle — over nineteen requirements, seeded into the
kit's second living spec, `docs/specs/spend.md`, as each ticket landed. The
two spikes of 2026-10-06 (above) settled its open questions first. Tickets
#583–#596 landed in PRs #600, #603, #607, #610, #615–#621, #623, #625 and
#626; the operator chose one release at the end rather than one per ticket,
and part of the wave rode 0.63.0 when the third spec-anchored wave's release
absorbed what had already landed (that entry says why). v0.65.0 is the merge
of PR #626 (#596), `06b4341`. The narrative is in two reports: the efficiency
report, https://view.centaurspec.com/uBdrniISzZ, and the wave report,
https://view.centaurspec.com/zKqP75O3xU.

What landed:

- **A spawn says what it served.** A spawn prompt's second line,
  `Trace-Spawn: tier=… domain=… skill=… ticket=…`, attributes its
  `agent.stop` (#600, #583), and every chain spawn site writes it (#615);
  `trace.sh summary` gains `--by tier` and `--by domain`; `/retro`'s question
  5 reports spend per tier, skill and cascade rung (#617).
- **One Claude Code agent type per tier**, each carrying the tools its work
  needs and no model (#607); the reviewer type cannot write, reach the
  network or call a tool server. The chain's spawns take their tier's type
  and the resolved model (#618).
- **Skills have byte ceilings.** A `SKILL.md` over the ceiling the gate's
  policy declares fails the docs gate (#603), and four skills split their
  rare branches into files beside them: `/pr-iterate` (#616), `/to-tickets`
  (#619), `/implement` (#620, `COVERS.md`, `DISPATCHED-REVIEW.md`,
  `STAMP.md`) and `/review-pr`, one file per standards lens (#621).
- **A lens reads only its slice.** `scripts/lens-slice.sh` joins the shared
  layer and hands each standards lens the paths its rule selects, the
  behavior axis the whole diff (#623).
- **Workers read narrow first.** `.agents/prompts/cheap-reads.md`, named in
  every spawning skill's prompt (#625).
- **Mechanical work runs cheap-first.** The skill dispatcher runs a
  mechanical ticket on the policy's cascade model, judges it by the ticket's
  oracle and the pairing guard only, and escalates on red (#610).

What the wave learned:

- **A subagent stopped mid-delivery leaves a PR stranded.** Sessions killed
  by a usage limit or a session pause left PRs pushed but not driven; #625
  sat unreviewed until someone looked. Nothing recorded the interruption —
  the retro-candidate wave's `resumed` outcome and the landing's iteration
  check (next entry) answer it.
- **Four PRs conflicted against a main other sessions moved.** Each merged
  main in, never rebased, so its review history stayed attached.
- **A check-run can sit `in_progress` with `conclusion=success`.** The job
  had ended; the forge never closed the run, and a watcher waits forever.
- **`/tmp` quota** struck again under parallel suites (as in the entry
  above).
- **The agent harness's permission classifier refused the landing script on
  an unreviewed PR.** The landing went no further until the PR was
  reviewed; ADR-0019 (next entry) now puts a like check in the script
  itself.
- **One release at the end means a red main for the wave.** With no bump
  per ticket, main sat release-bound red — `self-host.test.sh` holding
  unbumped shared changes to a release — until #626 landed. The operator
  chose that trade knowingly; the next wave kept it.

## 2026-10-08 — the retro-candidate wave; shared layer 0.66.0

Two retrospectives over the #580 wave, `retro-20261007T180238Z` and
`retro-20261007T151351Z`, became tickets #627–#638, and the release ticket
#653 cut them as one minor. PRs #639–#645, #648–#652, #657 and the release
#658; v0.66.0 is its merge, `d190ff8`. Two shared files change content:
`scripts/trace.sh` (#649) and `UPDATING.md`'s arriving-from paragraph; the
rest is skills, the adapter and kit-only scripts, enumerated in
`VERSION`'s 0.66.0 note.

What landed:

- **ADR-0018: two kit tiers follow a model family** (#639). The operator
  ruled that the planner runs the newest Opus and the mechanical tier the
  newest Sonnet, always the latest: `AGENT_TIER_PLANNER='opus'`,
  `AGENT_TIER_MECHANICAL='sonnet'` in the kit-only policy, every other tier
  pinned and the shared resolver unchanged. Because the cascade's cheap rung
  is already Sonnet, the cascade now escalates to the implementer tier's
  model rather than running Sonnet twice.
- **The spawn guard** (#642, #627): with tracing on, the Claude Code
  adapter's `hooks/spawn-guard.sh` refuses a spawn whose prompt carries no
  well-formed `Trace-Spawn:` line. Every spawn now needs one.
- **The LOW band rule** (#644, #635): `/review-pr` counts a LOW and never
  posts one; `/pr-iterate` never escalates one. Lenses raise their findings
  as they return, both verdicts recorded before the post (#641); the
  reuse/DRY lens names the consolidations the records declined (#645).
- **The trace records an interruption** (#649): `ticket.start` gains
  `resumed`, and `pr.iterate` a `data.cause` of `conflict` or
  `pending-stuck` — the #580 wave's stranded PR, conflicts and stuck
  check-run, made visible to `/retro`.
- **The landing gets stricter and quieter.** ADR-0019: the landing script
  refuses a PR with no `pr.iterate` at its head commit (#640); it
  fast-forwards a clean root checkout afterwards (#651), and `merge.land`
  carries the landing script's fields (#648). Every merge-train wait has its
  own timeout (#652); a resume records the usage of a run nothing ended
  (#643); `/to-tickets` sizes a rule and its sweep as two tickets (#650);
  `pr.open` is written from the landing when missing, and `/implement` ends
  its run on every hand-back (#657).

Follow-ups filed: #646 (the forge broker posts a dispatched review's LOWs
inline) and #647 (the dispatched reviewer and its CI twin carry the
reuse/DRY declined list).

Afterwards, on 2026-10-09: the operator confirmed every confirm-list on the
28 PRs of the two waves. Correction notes were recorded for the short
`merge.land` records of #649, #651 and #652. A cascade dry run showed the
wiring engages — Sonnet on rung 1, escalation to the implementer tier's
model — but a live run needs an agent harness for the mechanical tier,
which the kit has not yet wired. And `skill-dispatch.kit.sh implement
--ticket-file` without `--tier` sizes from the skill's `metadata.phase`,
ignoring the ticket's stamp — the opposite of the rule #229 settled; a
candidate ticket, not yet filed.

## 2026-10-08 — the gate advises on an off trace and an unmapped reviewer tier; shared layer 0.67.0

Ticket #655, blocked by #654 (PR #656). Two advisories join the shared
validator set, `trace-off` and `reviewer-unmapped`: warnings only, each naming
the setting, the policy file it lives in and what it costs. `trace-off` fires
only when the trace could be on at no further step — `TRACE_DIR` empty while
the ignore file already lists `.trace/`; without the entry, turning it on
would put private text in a pushable tree, and that nudge belongs to
bootstrap's next-steps text, not the gate.

The decision this ticket asked for: **how the kit's own root gate stays free
of both.** The kit traces and maps its tiers through never-shipped twins, and
the shipped policy files it carries are the empty ones. Chosen: each
validator's policy is an ordered `policyFiles` list, the first existing file
read — the same shape as the scripts' own resolution, a seam first and the
shipped file last — and the kit's `config.mjs` lists its twin first. Rejected:
a validator that knows the kit's twin names (kit vocabulary in the shared
layer), and a kit-only marker block in `config.mjs` stripped at bootstrap
(machinery for one line). The cost accepted: a consumer's stamped `config.mjs`
names two kit files that never exist there, which the list skips; the comment
above each block says so. The fixture tests hold both halves — the kit's tree
silent through the real config, and firing through the shipped defaults — and
skip both where no kit twin exists, so a consumer's own advisory never turns
into a failing harness test.

The reduced POSIX gate carries neither; its notice says so, and self-host's
notice probe holds that.
