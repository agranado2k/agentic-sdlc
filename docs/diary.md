# Development diary

> Living history of the agentic-sdlc build. The **Current state** block at the
> top is the agent re-orientation summary — read it first when picking up the
> project. Below it: forward-chronological entries, newest at the bottom.

---

## Current state — 2026-09-02

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
| **Phase** | The kit is shipping. Shared layer 0.15.0, tagged at the merge that closed PRD #107; the constitution, both gates, the guards, seventeen skills, the adapters and the consumer workflow templates are all in place and under test. |
| **Repo** | `agentic-sdlc`, a template repository (`main`). Feature work happens in `worktree/<slug>` on a `<type>/<slug>` branch. |
| **Remote** | `git@github.com:agranado2k/agentic-sdlc.git` |
| **Deployed / live** | Nothing is deployed — the kit's delivery is the one-line agent setup (`SETUP.md` → clone at the newest `v*` tag → `setup/agent-bootstrap.md`), or the same clone-at-tag ritual by hand. |
| **Spec status** | Wave-based; tickets are the unit of work and each one carries a capability tier. |
| **Last housekeeping** | 2026-09-02 — first pass: 17 findings, none fixed (root manual baseline 334 lines); the one that matters: the docs gate's two engines disagree on their path roots (`scripts/check.sh` admits all of `.agents`/`.claude`, `config.mjs` only four subtrees) and nothing holds the pair together. Report: `housekeeping-20260902T134521Z.md` in the OS temp directory. |
| **Self-hosting** | The kit now obeys its own constitution: root `AGENTS.md`, the two shims, this docs set, and a green `sh scripts/check.sh` at the repo root. See `docs/adr/0001-the-kit-self-hosts-its-own-constitution.md`. |
| **Active worktrees** | None. The 0.15.0 wave (PRD #107) landed as PRs #116, #118, #119, #117, #120, #121, #122 and #123, and tagged v0.15.0 (2026-09-02): the design brief, its three anchors and advisory, the glossary's context map, craft rule §13, the housekeeping clock and its pass, and "strategic" pinned to Ousterhout (ADR-0002). Open: #87 (worktree vs topmost-config linters), #99 (Agent Plugins spike, parked), #97 (closable — owes its reporter a note on why `.agents/skills` won over `.llm/skills`). |

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

### 2026-09-02 — The kit makes its own mutation decision

Shared invariant §9 asks every consumer to decide how its pure, cheap layer is
measured, and the first housekeeping pass found the kit had never decided for
itself: seven validators, 138 fixture tests, and nothing that could say
whether those tests enforce anything. The kit has no engineering article to
carry the decision line, so this entry is the record.

**Decision**: Stryker, on demand, against the validators under
`scripts/docs-conformance/validators/`, with the fixture tests as the target
function. `sh scripts/mutation.kit.sh` runs it (about eight minutes on a
laptop); both the wrapper and its config are kit-only and never shipped. The
tool arrives through `npx` each time — the kit commits no package manifest and
the harness stays dependency-free. It is never a gate.

**Baseline, 2026-09-02, at `d29673c`:** mutation score **76.53 %** — 639
mutants, 468 killed, 21 timed out, 150 survived, none uncovered. Per file:
skill-web 85.29, housekeeping-due 83.33, skill-paths 82.61, design-brief
75.68, claude-md-refs 75.28, skill-bridge 73.33, mutation-decision 65.52.
Most survivors are hint strings and message text no fixture asserts on, which
is a true statement about the suites: they hold verdicts, not wording. The
survivors worth a ticket are the ones that change a verdict — a `sort` dropped
from a scan without a test noticing, a default skills directory emptied — and
`/housekeeping` item 4 reads this number next pass.

Two things the run taught: Stryker's sandbox copy fails on the kit's per-skill
symlinks, so the config runs in place; and an in-place run restored one file's
content but dropped its executable bit, which the wrapper now checks for and
restores, loudly.

