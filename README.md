# agentic-sdlc

A language-agnostic, agent-first SDLC framework — extracted from a production
project where it was built, reviewed, and exercised by the very chain it defines.

Spec → tracer-bullet tickets → test-first implementation → two-axis review
(standards findings to agents, behavior findings to humans) → human merge gate.
Constitution-layered agent instructions, CI-verified process docs, guards that
block what prose used to merely request.

**Paste one line into a coding agent** (or run the same ritual by hand), and
your new repo has an agent operating manual, the portable rulebook underneath
it, and a gate that fails when the two stop describing reality.

## Quickstart

**With a coding agent** — paste this line and answer its plan:

> Set up the agentic-sdlc kit by following
> <https://raw.githubusercontent.com/agranado2k/agentic-sdlc/main/SETUP.md>

`SETUP.md` is a deliberately frozen entry point: the agent resolves the newest
release tag, clones the kit **at that tag**, and follows
`setup/agent-bootstrap.md` from inside the clone — one checkpoint (project
name, description, the optional `/dogfood` skill, the remote), then bootstrap,
the gate, and a local first commit. It never pushes; the first push is yours.

When the agent finishes, start your next session **in the project directory**:
a harness's slash commands are discovered from the directory a session starts
in, and the setup itself ran one level above it — so the kit's chain
(`/grill-me`, `/tdd`, …) only appears to a session started (or moved — in
Claude Code ≥ 2.1.246, `/cd <dir>`) inside the project.

**By hand** — the same ritual, manually:

```sh
# 1. Clone at the newest release tag — a certified release, never mid-wave main.
KIT_URL=https://github.com/agranado2k/agentic-sdlc.git
KIT_TAG=$(git ls-remote --tags --refs "$KIT_URL" 'refs/tags/v*' |
	sed 's|.*refs/tags/||' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' |
	sort -t . -k 1.2,1n -k 2,2n -k 3,3n | tail -n 1)
git clone --branch "$KIT_TAG" "$KIT_URL" my-project && cd my-project
rm -rf .git && git init -b main

# 2. Bootstrap. Runs once, then deletes itself. Commits nothing.
#    It asks one question — whether to include the optional /dogfood skill.
#    Answer it up front with --with-dogfood / --no-dogfood if you prefer;
#    with no terminal to ask on, it skips.
sh bootstrap.sh "My Project" "One line about what it does."

# 3. Check the gate is green, then make the first commit yours.
sh scripts/check.sh
git add -A && git commit -m "chore: bootstrap from agentic-sdlc $KIT_TAG"

# 4. Turn the TDD pairing guard on. It ships INACTIVE — see "The guards".
$EDITOR scripts/guards.config.sh   # set GUARD_SOURCE_RE
```

("Use this template" on GitHub still exists, but it snapshots the default
branch — you would get whatever main holds that day, not a release. The
clone-at-tag ritual above is the supported way in, for humans and agents both.)

`bootstrap.sh` stamps `constitution/AGENTS.md.template` into a root `AGENTS.md`,
writes the two one-line shims (`CLAUDE.md`, `GEMINI.md`) that point at it, stamps
the documentation set out of `templates/docs/`, wires the pre-push gate
with native `git config core.hooksPath .githooks` (no hook manager, no
dependency), prints your next steps, and removes itself. It refuses to run a
second time rather than overwriting a manual you have since edited.

## What you get

| Path | What it is |
| --- | --- |
| `constitution/shared-invariants.md` | The portable rulebook — eleven invariants that hold regardless of stack, domain, or vendor. **Shared layer:** copied verbatim, not edited locally. |
| `constitution/shared-code-craft.md` | The portable rules for the code an agent writes — from the smallest sufficient diff to diagrams drawn as SVG in HTML reports, never ASCII, to invariants kept inside the object that owns them. **Shared layer** too. |
| `constitution/AGENTS.md.template` | The root agent manual: hard rules, agent trust boundary, article-layer pointers, quick-reference map. Carries double-brace marks that bootstrap stamps. Becomes `AGENTS.md`; then it is yours. |
| `LICENSE` | MIT. The skills adapted from mattpocock/skills carry their upstream notice separately, in `.agents/skills/LICENSE-mattpocock-skills.md`. |
| `constitution/local-engineering.md.template` | The stack article — style, architecture, test tiers, "what this repo is NOT". Marks and inline guidance; you fill it in and drop the suffix. |
| `constitution/local-workflow.md.template` | The process article — commits, merges, the docs-trigger matrix, review, decision records, the log. Same deal. |
| `constitution/local-product.md.template` | The product article — the surfaces a user actually touches, and the personas that touch them. Ships **only if you take the optional `/dogfood` skill**, which is the one thing that reads it. |
| `.agents/skills/` | The skills — the lifecycle made runnable, at the vendor-neutral home (`.claude/skills/` holds one committed symlink per skill for the harness that reads only that address). All but `/dogfood` always; it is **opt-in at bootstrap**. Copied as-is, never stamped: they must read correctly in any project. **Yours** on arrival. |
| `scripts/check.sh` | The docs gate. POSIX sh; delegates the reference checks to the harness when node is available (see below). |
| `scripts/docs-conformance/` | The real validator: layered manuals, slash-command resolution, article reachability, portability deny-list, and the advisories — warnings that never fail the gate, relayed by `scripts/check.sh` on a green run; `docs/domain-glossary.md` keeps the roster (a skill referencing one you lack, a dead path inside a skill body, a materialized bridge symlink, an engineering article with no mutation decision or no design brief, a diary whose housekeeping date has gone stale — version skew is a sanctioned mid-update state). Dependency-free ESM, with its own fixture tests. |
| `scripts/docs-conformance/config.mjs` | Everything the gate enforces, as data. **Yours** — the engine is shared, the rules are not. |
| `scripts/guards.config.sh` | **Yours.** The one place the guards learn your repo's shape — source globs, test globs, contract artifacts. |
| `scripts/agents.lib.sh` | The capability-tier resolver: `sh scripts/agents.lib.sh implementer` prints the model that tier maps to. Shared layer; holds the four tier names and no model. |
| `scripts/agents.config.sh` | **Yours.** Tier → model id, for your provider. Ships empty on purpose — the kit names no model, because model ids rot faster than anything else it could carry. |
| `scripts/tdd-pairing-guard.sh` | The TDD pairing rule: source changes must carry test changes. One implementation, called by the hook and by CI. |
| `scripts/tdd-pairing-guard-ci.sh` | The CI caller of that rule — merge-base range, `tdd-exempt` label hatch. |
| `scripts/behavior-delta.sh` | Inventories the branch's deltas in your contract artifacts, plus a per-commit `refactor:`-that-is-not check. |
| `scripts/worktree-cleanup.sh` | Prunes merged worktrees and fast-forwards the root checkout. Driven by the `/worktree-cleanup` skill. **Yours** — not shared layer. |
| `.githooks/pre-push` | Runs the docs gate and the pairing guard before every push, each with its own loud, logged bypass. |
| `.githooks/pre-commit` | Refuses an agent's commit from the main working copy or on the default branch (hard rule 1, "Worktree, always"); a human with no agent-harness marker set commits as before. One loud bypass, documented in the hook. |
| `templates/workflows/` | CI workflow templates, copied into `.github/workflows/` by bootstrap. Two ship live (the docs gate, the TDD pairing gate); two ship as `.example` — commit linting, and the AI review below. |
| `templates/workflows/ai-review.example.yml` | The cross-provider review workflow: two advisory reviewers from two vendors, one identical prompt, firing on PR open. This is what `/implement` requests when it delivers. **Inert on arrival** — rename it once a provider secret exists. |
| `templates/docs/` | The documentation skeletons. Stamped into `README.md`, `docs/diary.md`, `docs/domain-glossary.md`, `docs/adr/INDEX.md`, `docs/adr/NNNN-template.md` and `.github/PULL_REQUEST_TEMPLATE.md`, then removed. |
| `adapters/` | Worked reference wirings, one directory per stack — **copy only if your stack matches**. Not shared layer, not stamped, not copied in: it arrives in your project intact and dormant. See below. |
| `UPDATING.md` | The shared-layer update recipe — how to diff your copy against a newer kit release and adopt it. **Shared layer.** |
| `EXCLUSIONS.md` | What the kit deliberately does **not** ship, and why — one entry per considered-and-rejected skill or mechanism, plus the standing rule that keeps it current. Kit-repo meta: removed by bootstrap, not shared layer. |
| `tests/docs-demo.sh` | K4's acceptance test — the personalized docs set, and the update recipe run end to end (removed by bootstrap). |
| `VERSION` | The shared-layer manifest: which files are shared, at which version. |
| `SETUP.md` + `setup/agent-bootstrap.md` | The one-line agent setup: the frozen entry doc the pasted line fetches, and the tag-pinned procedure it hands off to. Kit-only — both removed by bootstrap. |
| `tests/` | The kit's own acceptance tests and CI (removed from your project by bootstrap). |

### One manual, three entry points

The rules live in **`AGENTS.md`** — the filename the agent-tool ecosystem has
converged on, and the one this kit treats as canonical. Beside it bootstrap
writes two **shims**, `CLAUDE.md` and `GEMINI.md`, each holding one import line:

```markdown
<!-- Shim: the agent manual is AGENTS.md. Edit that file, not this one. -->
@AGENTS.md
```

That is the whole file, and the docs gate keeps it that way: `shim-invalid`
fires if a shim grows a second instruction, imports something else, or goes
missing. The rule exists because of the failure it prevents — the moment a
tool-specific file *can* hold a rule, somebody adds one there, and the repo has
two manuals whose difference nobody can see. A shim with no room for content
cannot become a rival manual.

The list is policy, not a constant: `claudeMdRefs.shims` in
`scripts/docs-conformance/config.mjs` names the entry points, and a project that
does not want one deletes it from that list rather than from the validator. The
check is evaluated only where the manual exists, so the kit's own tree — which
ships an `AGENTS.md.template` and no stamped files — stays silent.

**The honest limit.** This buys you the *rules* in every agent tool, not the
*commands*. The skills live at `.agents/skills/` in the open Agent Skills
format; a tool that does not read that directory gets the practice as prose from
the manual and the articles, with no `/`-command to invoke it. Each `SKILL.md` is
plain markdown, so pointing another tool at one by path works today — but porting
them to a second command format is explicitly out of scope here.

### The documentation set

Bootstrap leaves a project with the four documents an agent-run project needs on
day one, personalized with your project name and the bootstrap date:

- **`docs/diary.md`** — the development diary. A **Current state** block that is
  edited in place (the re-orientation summary an agent reads first), open
  questions, memory pointers, an explicit update protocol, and append-only dated
  entries below.
- **`docs/adr/INDEX.md`** + **`docs/adr/NNNN-template.md`** — MADR decision
  records. The index says what is currently binding; the template is copied per
  decision and stays in your repo.
- **`docs/domain-glossary.md`** — the ubiquitous language, plus the half people
  forget: the words the project deliberately does *not* use.
- **`.github/PULL_REQUEST_TEMPLATE.md`** — the PR checklist, with a separate
  section for the behavior findings a human must confirm (shared invariant §5).

All four are **yours** the moment they land. They are stamped from templates, not
copied verbatim, and nothing updates them afterwards.

### The skills

`.agents/skills/` holds eighteen skills — the chain at the top of this README, made
runnable:

`/grill-me` → `/to-prd` → `/to-tickets` → `/implement` (driving `/tdd`, ending at
an open PR that carries a review) → `/review-pr` → `/pr-iterate` →
`/merge-train` → `/worktree-cleanup`, plus `/grill-with-docs`, `/prototype`,
`/diagnose`, `/explain-diff`, `/improve-codebase-architecture`,
`/design-brief`, `/housekeeping` and `/retro` off to the side.

**All but `/dogfood` are unconditional; it alone is opt-in.** Every other
skill works on the day the repo is created, because it operates on specs,
tickets, diffs and branches — things a one-hour-old project already has.
`/dogfood` operates on a *running product*: it walks the personas you declare
through the surface you declare (a browser for a web app, the binary for a CLI,
a client for an API or a tool server) before a human does, and hands the friction
and breakage it hits to `/to-tickets` as candidate tickets. **It never fixes what
it finds** — a repair by the session that found the problem destroys the only
independent reading anyone had of it, and smuggles a behavior change into a
verification pass (shared invariant §10).

So bootstrap asks, once: *Include the /dogfood skill? Needs a runnable
user-facing surface.* `--with-dogfood` and `--no-dogfood` answer it
non-interactively, and with no terminal to ask on it skips — the two mistakes
are not symmetric, since a project that skipped it can copy the skill back in a
minute, while one that took it carries a command it cannot run. Declining
removes three things together: the skill directory, the
`constitution/local-product.md.template` article that exists only to feed it,
and the manual's rows about it. Nothing is left commented out, and
`sh tests/dogfood-optin.test.sh` proves it by planting the removed reference
back and watching the gate report `skill-missing`.

They are **copied as-is, never stamped**. That is a stronger constraint than the
templates are under: a template may carry a mark because something fills it in,
while a skill has to read correctly in a project nobody personalized. So where a
skill needs a project specific, it points at the artifact this kit already
establishes — `constitution/local-engineering.md` for the test tiers,
`scripts/guards.config.sh` for what counts as source and which artifacts are
contracts, `docs/adr/` for the binding decisions, `docs/domain-glossary.md` for
the names.

Three consequences worth stating plainly:

- **`/implement` delivers to the PR boundary and stops there.** The session does
  not end at a local commit: it pushes, opens the PR (body carrying the
  restatement it opened with, plus the demo evidence), and requests one
  independent review — preferring a **forge review workflow**, because CI holds
  the secrets and can therefore reach a reviewer from a different vendor than
  the session that wrote the code, and falling back to a fresh-context
  `/review-pr` subagent on a different model tier when no workflow is wired.
  What it never does is land it: shared invariant §7 puts a human's name on the
  merge, and driving the PR to green afterwards is `/pr-iterate`'s loop.
- **The root manual's quick-reference is the index, and the gate enforces it.**
  Every `/command` in `AGENTS.md` must resolve to a skill directory (`.agents/skills/<name>/SKILL.md`, reachable through its `.claude/skills` symlink too).
  Delete a skill you do not run and the gate makes you delete its row.
- **`/review-pr` keeps both axes** (shared invariant §5). Axis 1's six standards
  sub-agents feed a severity report an agent may act on; Axis 2's seventh
  sub-agent runs in a fresh context and emits a confirm-list only a human may
  resolve. The mutation-delta step it can cite is **conditional** — mutation
  testing is stack-specific, so the skill says to check `adapters/` and to skip
  the block, loudly, when nothing is wired.

**What is *not* here is recorded too.** `EXCLUSIONS.md` names every skill or
mechanism that was considered and left out, with the reason attached — and the
standing rule that an exclusion is written down in the same pull request that
makes it. It exists because a skill once went missing for two releases and
nothing in the repo could say whether that was a decision or a slip; an absence
looks the same either way until somebody writes the reason down. It is
kit-repo meta and bootstrap removes it, so your project starts that record
empty rather than inheriting this one.

Six of the skills are adapted from [mattpocock/skills](https://github.com/mattpocock/skills)
under MIT; `.agents/skills/LICENSE-mattpocock-skills.md` records which, what
changed, and reproduces the licence, and each adapted skill carries the same note
at its own foot so provenance survives being read out of context. That file also
records the eleven that have **no** upstream — counting `/review-pr`, whose
second axis has none, and `/dogfood`, checked against the upstream repository
rather than assumed — and the one with a
different upstream: `/explain-diff`, adapted from Geoffrey Litt's
publicly shared skill.

## The shared layer, and why it has a version

Most of what bootstrap leaves behind is **yours** the moment it lands — your
`AGENTS.md`, your local rules, your docs. A small part is not: the files listed
under `files:` in `VERSION` are the **shared layer**, copied verbatim from the
kit and deliberately not edited downstream. They carry no product name, no
command, and no vendor, which is exactly what makes them copyable at all.

`VERSION` pins which release of that layer you took (`shared-layer: 0.45.0`). When
the kit moves, you diff the kit's shared layer against yours and apply what
changed — a manual, reviewable update rather than a dependency bump. That recipe
is `UPDATING.md`, **Part 1**: read both manifests, read the upstream delta,
measure your own drift, apply, then **verify the verbatim claim byte-for-byte**
before bumping the marker.

`UPDATING.md` **Part 2** covers everything the manifest does not, because that is
where most of a release's actual features live: skills, the manual and its local
articles, the workflow templates, the policy files, the adapters. Those are not a
copy — you were invited to edit them — so "byte-identical to the release" is the
wrong question there, and each category gets its own: a three-way review for
skills, missing *sections* for the manual, **never overwrite, diff the key sets**
for policy files, whole directories for adapters. Part 1 alone is an inert
half-update: 0.4.0's tier resolver is shared layer, while the policy file it reads and
the skills that call it are not. Both halves are demonstrated end to end by
`sh tests/docs-demo.sh`, whose two transcripts are the worked examples inside
`UPDATING.md` itself.

The gate fails if a shared-layer file goes missing, so the manifest cannot
silently stop describing reality.

A local exception to a shared invariant does not get edited into the shared file.
It goes in a local article, and the shared copy stays byte-identical.

## The gate

Shared invariant §8: a process rule must be executable or CI-verified, because a
rule nothing checks decays into a lie — and a stale standing instruction is worse
than an absent one, since every agent session loads it.

`scripts/check.sh` is that gate. It runs on `git push` via `.githooks/pre-push`,
with `PUSH_WITHOUT_DOCS=1` as a documented, warning-printing escape hatch.

**Three checks always run, in POSIX sh** — they are cheap and exact in a shell:

- an unstamped placeholder survived bootstrap (the manual was never personalized);
- a shared-layer file named in `VERSION` is gone;
- the root `AGENTS.md` does not exist at all.

**The reference checks are delegated**, because they are real parsing work:

| | Engine | Covers |
| --- | --- | --- |
| node on `PATH` | `scripts/docs-conformance/` | every layer of the manual (root, articles, nested package manuals); slash commands must resolve to a skill; repo paths must exist; every article must be reachable from the root; the shared article must stay free of product, vendor, path and command names |
| no node | POSIX fallback inside `scripts/check.sh` | repo paths in code spans of the root manual and the articles — and it prints a NOTICE naming everything it is *not* checking |

That split is the whole language-agnostic claim, kept honest: a project that has
not chosen a toolchain still inherits a working gate on day one, and is told
plainly what it is missing rather than being allowed to believe in coverage it
does not have. `DOCS_CHECK_NO_NODE=1` forces the fallback, which is how the demo
proves both engines — including a portability leak the fallback provably misses.

The harness carries its own fixture tests (`scripts/docs-conformance/test/`),
because a gate whose failure path is untested is a claim, not a check.

Note that the gate scans its own source too, and that files named `*.template`
are exempt because carrying unstamped marks is their job. Everything else is
stamped output and is held to it.

## The guards

The docs gate answers "do the documents still describe reality". The guards
answer two different questions, and they follow the same shape: **a script owns
the rule, a caller resolves the range.** That is what lets one rule run in a
hook, in CI, and in a test without three copies of it drifting apart.

**The TDD pairing guard** (`scripts/tdd-pairing-guard.sh`) fails a range that
touches source files and no test file. `.githooks/pre-push` calls it per pushed
ref; `scripts/tdd-pairing-guard-ci.sh` calls it over a pull request's merge-base
range. The two escape hatches differ on purpose: locally it is
`PUSH_WITHOUT_TESTS=1`, an env var in one person's shell history; in CI it is
the `tdd-exempt` label, an override visible to whoever reviews the PR. So a
local bypass only *defers* the failure.

**`scripts/behavior-delta.sh`** lists — never judges — the branch's changes to
your contract artifacts: the places where behavior is externalized and therefore
machine-visible. It also checks something no branch-level view can see: a commit
whose Conventional Commit type claims structure-only work (`refactor:`,
`style:`) while its own diff edits a contract artifact.

### They start INACTIVE, and that is the design

`scripts/guards.config.sh` is the one place the guards read policy from — and it
ships with **no source globs set**. Until you set `GUARD_SOURCE_RE`, the pairing
guard prints one warning per push and blocks nothing.

That default is deliberate, not an oversight. Bootstrap runs on an empty
project; it cannot know where your source will live, and a guess stamped into a
script becomes a rule nobody chose. A guard that blocked every push in a repo
nobody had configured yet would be deleted on day one — and a deleted guard
checks nothing. So the kit ships the mechanism and asks you for the policy.

Mechanism is shared layer (copied verbatim, listed in `VERSION`); policy is
yours (`scripts/guards.config.sh` is deliberately *not* shared). That split is
what lets a kit update diff cleanly against your copy.

## Capability tiers — the kit names no model

The planner decides what each ticket is *worth* running, on cost/benefit, using
four names the whole chain speaks: `planner`, `implementer`, `mechanical`,
`reviewer`. `/to-tickets` stamps a tier on every ticket and shows the mix at its
quiz; `/implement` reads its ticket's tier when it spawns.

The kit ships the vocabulary (in the manual) and the resolver
(`scripts/agents.lib.sh`, shared layer) and **never a model identifier**. Those
rot on a vendor's schedule and differ per provider, so the mapping is yours, in
`scripts/agents.config.sh`, which ships empty:

```sh
sh scripts/agents.lib.sh mechanical   # prints your mapped id — or nothing
```

Unmapped is a working state, the same way an unconfigured guard is: the resolver
warns once, prints nothing, and the spawn inherits the session's own model —
exactly today's behaviour. Where that value goes in a spawn call is the one
harness-specific detail, and it lives in `adapters/claude-code/README.md`.

## The adapters, and why they are dormant

The core is stack-free on purpose — that is what makes it copyable — and that
leaves one question unanswered on day one: *what do those settings actually look
like for my stack?* `adapters/` answers it by example, and only by example.

`adapters/node-ts/` is the worked wiring for a pnpm/TypeScript workspace with
Vitest: a filled-in `guards.config.sh` (real source and test globs, six contract
surfaces beyond the kit's two), a differential Stryker mutation diagnostic with
its report formatter and label-triggered workflow, and a promptfoo eval tier for
agent-facing prompt surfaces. Every value in it is a real value from the project
this framework was extracted from, with the reasoning left in.

**`bootstrap.sh` does not touch this tree.** It copies nothing out of it, stamps
nothing in it, and deletes nothing from it — so it arrives in your project
byte-identical and inert. Neither alternative was better: copying an adapter in
would be a stack guess stamped into a file the docs gate then enforces, and
deleting one would move the only worked example out of reach at exactly the
moment it becomes useful (the day you turn a guard on, weeks after bootstrap).
Nothing in `adapters/` is on an execution path: no workflow lives there, no
guard resolves its policy file from there, and no gate reads it. If no adapter
matches your stack, `rm -rf adapters` is the encouraged answer — a Node wiring
sitting in a Go repo is a stale standing instruction waiting to mislead the next
agent session.

`sh tests/adapters-demo.sh` states all of that as checks rather than prose: the
shell and module files parse, the policy-file examples really set what the guards
read, and a bootstrapped consumer still holds the tree byte-for-byte with
nothing copied in. What it *cannot* check — no Stryker run, no promptfoo run, no
workflow GitHub has ever parsed — is listed in `adapters/node-ts/INSTALL.md`.

## CI templates, and why they are not workflows here

`templates/workflows/` holds the CI half of each gate. `bootstrap.sh` copies
them into `.github/workflows/` of your project and removes the templates
directory. They are not live in this repo because **a template repository must
not run its consumers' CI against its own tree** — the kit has a
`AGENTS.md.template` rather than an `AGENTS.md`, and no configured source globs,
so both consumer gates are designed to be inert or red here.

Commit linting ships as `commitlint.yml.example` — inert, because GitHub Actions
reads `.yml`. It is the one gate whose reference implementation needs node, and
the kit does not decide that your project uses node. Rename it when you are
ready; the header explains what to do if you are not on node.

### Cross-provider AI review

`ai-review.example.yml` ships inert the same way, and is the mechanism
`/implement` reaches for when it delivers a PR. It holds **two** advisory
reviewers — one Anthropic, one Google — because the reason to run a review in CI
rather than inside the authoring session is structural: **CI holds the secrets,
so it can call a reviewer from a different vendor than the model that wrote the
code**, and a reviewer sharing the author's model family shares the author's
blind spots.

The shape, and what a third provider would change:

- **One file, two filled variants.** The cross-provider leg *is* the feature, so
  a single-provider example would ship the plumbing and drop the point. Both
  jobs are live YAML, not commented-out alternatives, and neither vendor is the
  default — the kit picks no model and no vendor anywhere else either.
- **Three marked choice points per job** — `PROVIDER CHOICE 1/3` the invocation,
  `2/3` the secret name, `3/3` the prompt. Adding a reviewer means copying a job
  and changing those three things.
- **The two prompts are byte-identical**, and `tests/ai-review-template.test.sh`
  asserts it. Asking two vendors different questions and then comparing their
  answers measures the prompts, not the models.
- **The prompt references your manual instead of restating it** — `AGENTS.md`,
  the `constitution/` articles, your decision records. The one rule it spells
  out is the two-axis split (shared invariant §5), because that describes the
  shape of the review's own output: standards findings an agent may act on, and
  a behavior confirm-list the bot is told not to answer or resolve.
- **Advisory, never gating.** Every review step is `continue-on-error`, the runs
  are concurrency-cancelled per PR, and the header says plainly not to put these
  jobs in your required status checks — the moment a bot's opinion can block a
  merge, a vendor outage is an outage in your ability to ship.

Renaming it with only one provider secret configured is a working state: each
job checks for its own key and skips itself with a `::notice::` when it is
absent, so the file is never red by default.

The kit's own CI is `.github/workflows/kit-guards.yml`, which runs the guard
test tiers and the end-to-end demo against this tree.

## Status — honest version

The **constitution layer (K1)**, the **skills (K2)**, the **guards (K3)**, the
**documentation set + update recipe (K4)**, the **Node/TS reference adapter
(K5)** and the **tool-agnostic manual (K7)** are in on top of the walking
skeleton (K0).

- `sh tests/kit-demo.sh` builds a throwaway project from this tree, bootstraps
  it, and proves the gate green — then red once per failure mode it claims: an
  unstamped placeholder, a deleted shared-layer file, a stale path, a dead
  slash command, the project's own name leaking into the shared article, and an
  article the root never points at. Includes a real `git push` the hook blocks,
  the POSIX fallback run, and a focused pass over the skills: every `/command`
  in the bootstrapped manual resolves to a `SKILL.md`, every shipped skill is
  reachable from the manual, no skill carries an unstamped mark — and then the
  same gate goes red when a skill is deleted out from under its row. It also
  proves the three entry points: `AGENTS.md` plus two shims that really are
  shims, then red when a shim grows content, red when a shim is deleted, and
  red when `AGENTS.md` itself is renamed away.
- `sh tests/guards-demo.sh` does the same for the guards: an unconfigured push
  that warns and passes, globs configured, a source-only push the hook really
  blocks (origin does not move), and the paired push that lands.
- `sh tests/docs-demo.sh` proves the bootstrapped docs set is personalized (and
  that the gate catches an unstamped mark inside `docs/`), then runs **both
  halves** of the `UPDATING.md` recipe. Part 1 — the shared layer — on a fake
  0.1.0 consumer updating to 0.45.0, including a local edit to a shared file,
  moving it out, and the byte-for-byte verbatim check afterwards. Part 2 —
  everything else — on a consumer bootstrapped at 0.3.0: it first holds that
  consumer to the *inert half-update* Part 1 alone produces (the capability-tier
  resolver arrives; its policy file, its callers and the wave's two new skills do
  not), then runs Part 2's steps and proves each of them lands — a new skill
  byte-identical, a changed skill taken, a locally-edited skill three-way merged
  rather than clobbered, `scripts/agents.config.sh` as an ADD, the review
  workflow together with the prompt file it reads. The hand edits are held
  non-optional by the gate, in both directions, including adopting and then
  declining the optional `/dogfood` skill after bootstrap. Both transcripts are
  the worked examples inside `UPDATING.md`.
- `sh tests/adapters-demo.sh` covers K5: the adapter files parse, the policy-file
  examples really configure the guards, and a bootstrapped consumer keeps
  `adapters/` byte-identical with nothing copied or activated from it.

- `sh tests/ai-review-template.test.sh` covers the cross-provider review
  template: every workflow template really parses as YAML (on python3 or ruby —
  it skips loudly rather than pretending when neither is there), the advisory
  invariants are in the file rather than only in its header, no merge or approve
  verb is reachable, the two provider prompts are byte-identical, the extraction
  source's own vocabulary did not come along, and a real bootstrap leaves the
  file copied, byte-identical, and still an `.example` with no live twin.

- `sh tests/exclusions.test.sh` keeps `EXCLUSIONS.md` honest: every command it
  says the kit does not ship really has no skill directory, every entry carries
  a reason and not just a name, `/ce-dogfood` stays recorded as optional rather
  than excluded — and the staleness check itself is proved by running it against
  a fixture that names a skill which *does* ship. It also checks the record's
  own wiring: bootstrap deletes it, and `VERSION` does not list it.

- `sh tests/dogfood-optin.test.sh` covers the one skill that is optional.
  Bootstrap is run three ways against three throwaway copies of the kit — with
  the skill, without it, and with neither flag nor a terminal to ask on — and
  each result is held to the gate. The load-bearing leg is the declined one:
  nothing in that tree may mention the command, and the proof is not the grep
  but the validator, which must report `skill-missing` the moment the removed
  row is planted back. A typo'd flag is checked too, because
  `--with-dogfod` silently becoming the project name is a mistake you find a
  week later in the stamped manual. (`sh tests/kit-demo.sh` bootstraps
  `--with-dogfood`: it asserts the maximal set, so its "every command resolves,
  no skill is orphaned" pass covers the optional skill as well.)

- `sh tests/worktree-cleanup.test.sh` covers the one new script that deletes
  things: merged-and-clean is pruned, merged-but-dirty and unmerged are kept,
  `--dry-run` changes nothing, and a typo'd flag exits 2 rather than running.

- `sh tests/setup-demo.sh` referees the one-line agent setup (`SETUP.md` +
  `setup/agent-bootstrap.md`) by executing the documents' **own fenced
  blocks** against a scratch origin tagged twice: the resolve step must pick
  `v10.0.0` over `v9.0.0` (a lexicographic sort dies there), the spine must
  end at a bootstrapped, gate-green project whose first commit is local and
  whose remote list is empty — never a push — and `SETUP.md` must stay frozen:
  under its line ceiling, naming no version, carrying the trust-posture and
  plan-first sentences. Then the referee proves itself non-vacuous: one broken
  fence, and the spine goes red.

- `sh tests/adopt-demo.sh` referees the existing-repo adoption arm: a fixture
  repo carrying one deliberate collision per class (their manual, their
  memory, a name-colliding skill, their hook, a file at a shared-layer path)
  is driven through `bootstrap.sh --adopt` — the safe set is copied in, five
  stable `COLLISION` lines print, the run exits 3 resolving nothing, re-runs
  are idempotent, and once every collision is resolved the same command flips
  to 0, wires the hook, and leaves the adopted repo's own gate green with the
  team's memory byte-identical throughout.

- `sh tests/review-pr-output.test.sh` pins the `/review-pr` output contract as
  text, the way the delivery-contract suite pins `/implement`: the summary-first
  order (verdict, badge count table, clean-audits line before any finding), the
  four badge+label pairs, the finding anatomy (`fix:` line, evidence fold,
  INITIAL-N ids), the disjoint glyph vocabularies of the two axes, the
  confirm-list's verbatim-liftable line shape and 🔀→⚠️→✅ order, the
  one-top-level-comment and inline-only posting rules, and the absence of any
  ANSI escape — the report is markdown for two hosts, not a terminal program.
  The report's severity lines and Agent 7's status lines are held to the
  policy file (ticket #280): the suite reads the `severity` and `status`
  vocabularies through `sh scripts/vocab.sh fields`, never from a list of its
  own, and a band or a status planted in a copy of the skill — or withdrawn
  from a copy of the policy file — goes red.

- `sh tests/manifest.test.sh` pins the manifest grammar once — first word is
  the name, annotation is legal, comments and blanks skipped, a list ends at
  the first unindented line — and holds the recipe's two self-contained copies
  equal to it, so the recipe cannot drift from the gate.

- `sh tests/docs-gate-advisory.test.sh` proves the gate's warning channel is
  audible where the operator actually looks: an advisory the harness reports
  on a green tree is relayed by `scripts/check.sh` — the entry point the hook
  and CI run — and a tree with nothing to advise prints no advisory block.

- `sh tests/trace.test.sh` proves the decision trace (ADR-0008): an
  unconfigured emit is a silent no-op, a configured one appends one JSON line
  in a fixed field order, the escaper and the closed kind vocabulary refuse
  what they should, `show` matches a subject exactly, `verify` names a bad line
  by file and line, and an emit from inside a linked worktree lands under the
  root checkout and survives the worktree's removal. Then a run has an
  identity: `begin` hands one out and `end` closes it, a nested `begin`
  records its parent, the environment outranks the run stack, only `begin` and
  `end` rewrite that stack and both by rename, fifty parallel emits all land
  and all verify while the stack stays untouched, an event whose write would
  exceed 4000 bytes is refused with the refusal pointing at `--blob`, a payload
  is stored once under git's own hash of the bytes that were stored — by
  `blob` too, which prints that name and byte count, writes no event and
  leaves the stored file owner-only — and `verify` refuses a schema it does
  not know.
- `sh tests/forge-broker.test.sh` proves the broker (ADR-0009) lands a
  dispatched reviewer's report on the PR without the worker ever holding
  network or credentials: against a stub forge CLI that records argv and
  stdin, a valid report makes exactly two mutating calls — one review whose
  payload carries `event` COMMENT explicitly, one top-level behavior comment
  — and prints both URLs; `--dry-run` prints both payloads and posts nothing;
  a report with no `REVIEWED` or `VERDICT` line, or a heading missing, posts
  nothing and exits 65; a reviewed commit the PR no longer holds exits 75,
  while one behind the head posts anchored to itself, checked against the
  base...reviewed diff, with a drift line — and only with a matching
  `--commit`, which is optional at the head and mandatory on drift, its
  absence exit 65; no `gh` on PATH exits 69; a policy
  that omits an operation exits 78; a finding whose `path:line` is not in the
  diff is dropped and named; a retried run finds its marker and skips; the
  word APPROVE in a finding never reaches the event; and the trace's `show`
  reads back one `finding.raise` per posted finding and a `review.verdict`
  per axis, none of them carrying a line of the report, while an
  unconfigured trace leaves the posting unchanged.
- `sh tests/land.test.sh` proves a PR landed by hand records what the train
  records (#386): against a stub forge CLI, a PR that is red, pending, a
  draft, conflicting, behind its base or under a human's changes requested
  is refused with exit 2, no merge call and no event; a green one is merged
  with the merge-commit method, main's workflows on the merge commit are
  watched, and the trace holds one `merge.land` then one `feedback` —
  `unasked` with its reason when no terminal is at the prompt, the
  operator's verdict when one is; an unconfigured trace leaves the merge and
  stdout unchanged.
- `sh tests/catalogue.test.sh` checks runtime catalogue admission: source and
  active content identities, exact case, explicit executable references, stale
  copies, and reproduction after bootstrap. See `scripts/catalogue.md`.
- `sh tests/task.test.sh` checks task entry before production work: missing
  scope and unacknowledged baselines are refused; clean and preserved dirty
  baselines record separate branch, HEAD, index, worktree, untracked-content and
  catalogue identities; small changes, waves, reports and read-only requests
  take proportional endpoints; an explicit local endpoint keeps its exception
  and consequence without inventing remote delivery. See `scripts/task.md`.
- `sh tests/vocab.test.sh` proves the vocabulary checker (PRD #273): every
  shipped vocabulary accepts its own tokens; a misspelling, an invented token,
  an empty value and a token outside the shape are each exit 2 with the field
  named; a whole ticket body on stdin checks clean when its prose is not a
  decision; a cross-field rule refuses the forbidden pair and accepts the
  others; a rule set no combination can satisfy is reported as a policy
  contradiction, distinct from a bad value; the policy file is held at load
  to the shape and to the neutral-name rule; a named and missing policy file
  is exit 2, and discovery never reads the repo the caller stands in; the
  tier is read and never widened — the resolver still refuses a fifth token.
- `sh tests/vocab-policy.test.sh` holds the shipped `scripts/vocab.config.sh`
  to the skills that spell the same words — the severity buckets and
  confirm-list tags of `/review-pr`, the triage verbs and thread kinds of
  `/pr-iterate`, the tier and confidence stamps of `/to-tickets` and the
  resolver's literal — order included, and to the checker's own defaults, so a
  token added on one side and not the other goes red.
- `sh tests/typed-return.test.sh` holds `/pr-iterate`'s delegated untrusted
  read to its declared return shape (PRD #273): three bare lines — the
  command-shaped flag, the triage action, one evidence line quoting the
  comment read — whose options are the policy file's tokens, with the author
  kind stamped by the caller from the forge's own data; the check before the
  read, through the plain script name; free text as a finding. It lifts the
  check the skill prints out of the skill and runs it: the good return passes,
  and a sentence outside the shape, an undeclared value, the inconsistent pair
  and a markdown-wrapped line are each refused — as is every return when the
  checker is missing, since the check fails closed. The evidence line is held
  too — one quoted span of at most 200 bytes of printable ASCII, verbatim from
  a single line of its comment by a fixed-string match against the scratch
  file the caller fetched unseen — and a count of returns that is not the
  count of comments refuses them all. Only a return that passed is printed;
  a refused one is named by comment and position. The snapshot itself is held
  to metadata only: no command in it selects a body. It also holds the
  trust-boundary paragraph in the kit's manual and the template.
- `sh tests/stamp.test.sh` holds `scripts/stamp.sh`, the one way `/implement`
  reads its ticket's `Tier:`, `Confidence:` and `Domain:` lines (#331): the
  issue number in, the body fetched through a stub tracker CLI, the bare
  lines lifted and checked. Five statuses, each driven red first — 0 with the
  checked lines and nothing else on stdout; 2 for a refused value, nothing on
  stdout and the field named, never the text; 3 for a ticket with no stamp
  lines, a checker that is gone or cannot run (its policy missing or
  malformed), or a line of a field the policy does not declare with no tier
  left — never a refusal and never an unchecked line; 4 for a fetch that
  failed on its one retry; 5 for more than 8 lines of one key, a stop with
  nothing checked and stderr naming the key and the count, never a line, in
  bounded CPU time; and a signal exits, never a verdict. The bodies
  are hostile: a quote that closes its own argument, a no-break, em or
  zero-width space in a value or a key — the em space under a caller's
  C.UTF-8, so the script's own locale pin is what decides it — a NUL,
  markdown-wrapped lines, and a foreign clone's checker under the caller's
  cwd.
- `sh tests/prescreen-return.test.sh` holds the other two untrusted reads to
  the same form (ticket #280), where the return is smaller. `/to-tickets`
  over a PRD issue body and `/dogfood` over product output it can capture
  to a file unseen each pre-screen the text before the session reads it
  (text a browser tool has already shown the session is outside the
  pre-screen, and the skill says so): the caller writes it to a scratch
  file unseen, a reader with no shell, no forge CLI and no network returns
  two bare lines — `Command-shaped:` from the policy file's tokens and one
  evidence span — and the check each skill prints is lifted out and run: the
  shape, then the checker under its plain name, found from the repository
  root and refusing when it is missing; the span capped, printable and
  verbatim in the scratch file; a refused return named and never printed.
  The fence that shows the pre-screen end to end is run as well, against a
  stub forge command, a stub step and a stub reader — a failed fetch is a
  stop, an empty output reaches no reader, a return an earlier step left is
  never read for a later one, the scratch home is gone afterwards — and the
  two skills' copies of the check are compared line for line. A
  typed return is a classification, so the pre-screen replaces neither read —
  `yes` is the stop each skill already described, `no` is followed by the
  ordinary read, as data — and neither skill may claim more than the check
  does. `/dogfood`'s row outcome is held as a decision line too: the command
  the skill prints is run, and an outcome the policy file does not declare is
  exit 2.

- `sh tests/trace-prices.test.sh` proves the price table says when it is stale
  and refreshes on demand (ticket #270). Because cost is computed on read
  (ADR-0008 clause 6), the table is a dated claim that rots quietly — so
  `summary` and `export --csv` read its `Last checked:` line and print one
  advisory on stderr past `TRACE_PRICES_STALE_DAYS`: never on stdout, never an
  exit status, silent when the window is empty or no date is written, silenced
  by `TRACE_QUIET=1`. Then the kit-only refresh script
  (`scripts/trace-prices.kit.sh`) against fixture payloads under
  `tests/fixtures/prices/` — no network in the suite at all: `--check` reports
  drift as exit 1 and a source failure as exit 2, two sources disagreeing past
  the threshold refuse the write and print both, and a write rewrites exactly
  the five values, the date and the two source-revision lines, leaves every
  other byte of the policy file alone, and commits nothing.

- `sh tests/trace-hooks.test.sh` covers the other end of that trace — the
  Claude Code adapter's session hooks, against the checked-in payload and
  redacted transcript fixtures. The session-start hook writes the pointer file
  the shared script reads a session id back from, proved by a *later* emit
  carrying that session rather than by looking for a file, and appends the
  export to the env file the agent harness hands it. The session-end hook sums
  tokens per model with a streamed response counted once, and the numbers are
  held to the agent harness's own rollup line as an oracle: the session's usage
  plus the subagent's equals it exactly. Then both failure shapes — a renamed
  usage key and a PATH with no node — make the extractor exit 2 and the hook
  record one event with `outcome=fail` naming the cause, and every hook exits 0
  and says nothing on either stream throughout. Then tool capture, which is a
  switch of its own: with `TRACE_TOOLS` empty in the shipped policy file the
  post-tool hook writes nothing at all, and with it set one tool call becomes
  one `tool.use` event whose two blob names are git's own hash of the payload's
  input and result, stored by the shared script's `blob` with no store code
  left in the adapter — a 20 KB input still leaves the line inside the 4000-byte
  cap, a failed call reads `outcome=fail` with the agent harness's error as its
  result, a tool result that quotes another `session_id` does not re-file the
  event, and a `tool_use_id` the trace could never match is one `fail` event
  rather than a silent drop. Finally the kit-only `.claude/settings.json` parses
  and names only hook scripts that exist.
- `sh tests/root-guard.test.sh` holds the manual's first hard rule at both
  places it can be held. The Claude Code adapter's pre-tool hook, fed fixture
  payloads against a throwaway repository with a linked worktree, refuses a
  Write, Edit, MultiEdit or notebook edit at the root with exit 2 and the rule
  on stderr, and lets the same write through under `worktree/`, outside the
  repository and under `.trace/` or `.retro/`; for Bash it refuses a redirect,
  `sed -i`, `tee`, `cp`, `mv`, `git checkout` or `git restore` onto a tracked
  root file (following `cd` and `git -C`, past heredoc bodies, continuation
  lines and `env`/`sudo`/`VAR=` prefixes), `mv` of a directory of tracked
  files, `git checkout` or `git restore` of a directory or `.`, the discards
  `git stash`, `git reset --hard` and `git clean -f`, and `git commit
  --no-verify`, `git -c core.hooksPath=…` or a `core.hooksPath` change made at
  the root, and passes `sh tests/x.sh` and `git commit -uno`. Then `.githooks/pre-commit` refuses a commit from
  the main working copy or on the default branch when any agent-harness marker
  is set, each marker alone, without printing its bypass; lets the same commit
  through for a human with none; passes an agent's commit from a linked
  worktree on a feature branch and a repository's first commit; and lets
  `COMMIT_WITHOUT_WORKTREE=1` through loudly. Every refusal was first watched
  passing a guard that knew no rule.
- `sh tests/trace-skills.test.sh` holds every chain skill to the trace's
  contract as text (ADR-0008, tickets #250 and #309): each of the fourteen
  emits at its decision points by the plain `sh scripts/trace.sh …` name,
  never the kit's never-shipped wrapper; every emit, begin and end ends in `|| :`, so a trace
  error changes no skill's outcome; every kind a skill emits is one the script
  knows; `/review-pr` resolves the reviewer tier once, before its sub-agents,
  and records a spawn per agent with that model, and every `data.agent` it
  writes — spawn, raise, or a relayed review's raise — is a token from its
  own closed sub-agent roster; `/merge-train` and
  `/pr-iterate` record the human's `feedback` verdict on a landed slice; and
  no skill, chain or not, ever calls `show`, `summary` or `export`.
- `sh tests/no-box-art.test.sh` is craft rule §10 as a failing check: no
  box-drawing character anywhere in the shipped prose — the skills, the
  constitution and the templates — with a planted box under each root proving
  the scan reports it, and ordinary dashes, arrows and accents left alone. The
  harness's fixture tests, which use box characters as comment rules, are
  code and out of scope.
- `sh tests/mutation-kit.test.sh` drives the kit's own mutation wrapper,
  `scripts/mutation.kit.sh`, through a stub Stryker: the pinned `--dry-run`
  command, usage errors and a non-kit tree refused with exit 2, the exit code
  propagated, a dropped executable bit handed back without touching content,
  and Stryker's backup kept after a failed run.
- `sh tests/harness-helpers.test.sh` drives the folded assertion helpers in
  `tests/lib.sh` — `t_text_has`, `t_fence`, `t_check_run` and `t_verdict_is` —
  through each branch, the failing ones included: a refusal assertion with no
  `verdict` function, no lifted check or no project to run in fails loudly
  instead of passing vacuously.
- `sh tests/fixture-builders.test.sh` pins the four fixture builders in
  `tests/lib.sh` that every demo suite makes its throwaway kits and consumers
  with: a `.git`-free kit copy with nested worktrees stripped, a repo with a
  fixture identity and every signing switch off, a two-tag history whose tags
  resolve to their trees, and a consumer bootstrapped from a tree with one
  commit. The demo suites are the builders' oracle in the large — the docs
  demo's pinned transcripts did not move when it adopted them.

- `sh tests/suite-budget.test.sh` proves every suite runs inside the worker
  budget (ADR-0006, #209) that `tests/lib.sh` applies the moment a suite
  sources it: sourcing `scripts/agent-dispatch.sh` defines its derivation and
  runs nothing, a stub suite run through the test harness against a fake host
  comes back inside a budget of that host's numbers, a fork loop and a
  greedy allocation come back as failures naming the ceiling with exit 71
  while the calling shell still forks, the rlimit rung refuses forks inside
  the suite's own shell, the off switch runs a stub bare and says so, the
  marker bounds the recursion, and a scope that refuses to open falls to
  rlimits out loud.

- `sh tests/gate-path-roots.test.sh` holds the docs gate's two engines to one
  set of path roots: the reduced POSIX form's list must equal the policy
  file's `claudeMdRefs.pathRoots` entry for entry, two baits prove the
  comparison can fail, and a bootstrapped project proves both engines judge
  the same reference the same way — including one under a subtree only the
  fallback used to admit.

- `sh tests/design-brief-skill.test.sh` pins the `/design-brief` contract as
  text: the three anchors it writes, design-it-twice compared on complexity,
  the human stop before every write, the decision record, the two entry
  points, spec-only frontmatter, and every path and command it names
  resolving.

- `sh tests/housekeeping-skill.test.sh` pins the `/housekeeping` contract as
  text: eight checklist items each with a named source, the red flags and
  their two routes, the never-fix rule, the one permitted write, planner-tier
  work, spec-only frontmatter, and every path and command resolving.

- `sh tests/retro-skill.test.sh` pins the `/retro` contract as text: the eight
  fixed questions named and numbered in both files, the trace kinds each one
  reads, the eighth's per-field and per-skill rule with its oracle clause and
  the three limits it states — its arithmetic run once over a fixture trace in
  scratch, so a row that prints a rate is a computed number and not a claim —
  the plain `sh scripts/trace.sh show|summary|export` name with
  `verify` first, the report and its CSV under `.retro/<YYYY>/<MM>/` at the
  root checkout (the one-line common-directory derivation the skill quotes
  is run from a scratch worktree, and `.gitignore` holds the folder),
  findings routed to `/to-tickets` and never fixed (a recurring failure
  becomes a rule with a failing check, never a lessons file — shared
  invariant §11), the run it
  opens and closes with `data.findings`, every documented trace line run
  against a scratch trace, the default window since its own last run end,
  planner-tier work, and every roster surface — including `/housekeeping`'s
  "a retro ran inside the window" line and the trace-skills suite's named
  exclusion for the one skill allowed to read.

- `sh tests/spec-skills.test.sh` pins the `/to-prd` and `/to-tickets` contracts
  as text: the PRD template's eleven sections in reading order, the phrase
  that carries each rule (one-sentence objective, scenarios as demo scripts,
  the penalty-for-being-wrong filter, later/never on every non-goal, open
  issues with a next step, the stranger reread before publishing), the
  hand-off from scenarios to the admission test, the open-issue gate and
  feedback-first ordering on the ticket side, spec-only frontmatter, and
  every path and command resolving.

- `sh tests/skill-phase.test.sh` pins the phase every skill declares in its
  frontmatter — the closed vocabulary (planner, implementer, tester,
  mechanical, reviewer), that every shipped skill carries one and every phase
  is used by something, and that `scripts/skill-dispatch.kit.sh` turns a skill
  name into the tier its phase means and dispatches there.

- `sh tests/self-host.test.sh` covers the claim that the kit keeps its own
  rules. The kit's manual layer exists and its shims really are shims, the docs
  gate is green at the kit root on both engines — and then the half that could
  break every consumer: bootstrap runs twice, once against this tree as it is
  and once against the same tree with the kit's own files removed by hand, and
  the two stamped projects must be byte-identical. A spot-check only finds the
  leaks somebody thought of.

The kit's own CI runs the harness fixture tests, the portability validator
against `constitution/shared-invariants.md`, the docs gate at this repo's own
root, the guard test suites, and the demos on every PR (`kit-ci.yml` +
`kit-guards.yml`).

Not here yet, each with its own ticket:

| | Ticket | Brings |
| --- | --- | --- |
| K6 | [#8](https://github.com/agranado2k/agentic-sdlc/issues/8) | Dogfood: a throwaway project end-to-end, and the verbatim claim proved by diff |

The PRD is [#1](https://github.com/agranado2k/agentic-sdlc/issues/1). The kit is
built ticket-by-ticket by its own `/to-tickets` → `/implement` chain.

## Licence

MIT (`LICENSE`) — and additionally, for the six skills adapted from
[mattpocock/skills](https://github.com/mattpocock/skills), the upstream MIT
notice reproduced in `.agents/skills/LICENSE-mattpocock-skills.md`.

## Working on the kit itself

**The kit follows its own framework.** This repo is bootstrapped: it has its own
root `AGENTS.md` — hand-written for the kit-authoring context, not a stamped copy
of the template it ships — the two shims beside it, a `docs/` set, and a GREEN
`sh scripts/check.sh` at its own root, enforced by the `self-host` job in
`kit-ci.yml`. See `docs/adr/0001-the-kit-self-hosts-its-own-constitution.md` for
why, and for how `bootstrap.sh` keeps a consumer's first run working anyway: it
strips the kit's own files before stamping yours, so what you receive is exactly
what you received before the kit had any.

Wire the hook in your clone, once — hooks path is per-clone config and cannot be
committed:

```sh
git config core.hooksPath .githooks
```

Then the gates and the suites. CI runs all of them:

```sh
sh scripts/check.sh                                    # the docs gate, on THIS repo
node --test scripts/docs-conformance/test/*.test.mjs   # the validators' fixture tests
node scripts/docs-conformance/index.mjs .              # portability of THIS repo's shared layer
sh tests/self-host.test.sh                             # the kit keeps its own rules, and still stamps clean
sh tests/kit-demo.sh                                   # K0+K1: bootstrap + docs gate, end to end
sh tests/guards-demo.sh                                # K3: the guards, end to end
sh tests/docs-demo.sh                                  # K4: the docs set + the UPDATING.md recipe
sh tests/adapters-demo.sh                              # K5: the adapters tree, and that it stays dormant
sh tests/tdd-pairing-guard.test.sh                     # the pairing rule
sh tests/tdd-pairing-guard-ci.test.sh
sh tests/behavior-delta.test.sh
sh tests/worktree-cleanup.test.sh                      # the pruning rule
sh tests/exclusions.test.sh                            # EXCLUSIONS.md has not gone stale
sh tests/agents-tiers.test.sh                          # the capability-tier resolver
sh tests/agent-harness.test.sh                         # the agent-harness axis of that resolver
sh tests/agent-dispatch.test.sh                        # running a tier on another agent harness
sh tests/agent-roster.test.sh                          # bootstrap's agent-roster prompt
sh tests/implement-deliver.test.sh                     # /implement's Deliver phase
sh tests/ai-review-template.test.sh                    # the cross-provider review template
sh tests/dogfood-optin.test.sh                         # the one optional skill, both answers
sh tests/setup-demo.sh                                 # the one-line agent setup, from its own bytes
sh tests/review-pr-output.test.sh                      # the /review-pr output contract
sh tests/adopt-demo.sh                                 # the existing-repo adoption arm
sh tests/docs-gate-advisory.test.sh                    # the warning channel is audible through the gate
sh tests/trace.test.sh                                 # the decision trace: emit, show, verify, and the worktree property
sh tests/forge-broker.test.sh                          # the broker lands a dispatched review on the PR, through a stub forge CLI
sh tests/land.test.sh                                  # one PR landed by hand records merge.land and feedback, through a stub forge CLI
sh tests/task.test.sh                                  # task scope, baseline identity, proportional endpoint
sh tests/vocab.test.sh                                 # the vocabulary checker refuses what no vocabulary declares
sh tests/vocab-policy.test.sh                          # the shipped vocabularies match the skills that spell them
sh tests/typed-return.test.sh                          # /pr-iterate refuses an untrusted-read return that is not the declared shape
sh tests/stamp.test.sh                                 # /implement reads its ticket's stamp through one script with four exit statuses
sh tests/prescreen-return.test.sh                      # /to-tickets and /dogfood pre-screen their untrusted text as a checked typed return
sh tests/trace-hooks.test.sh                           # the Claude Code adapter's session hooks and usage extractor
sh tests/root-guard.test.sh                            # the root checkout refuses an agent's edit and an agent's commit
sh tests/trace-prices.test.sh                          # the price table's staleness advisory and its kit-only refresh
sh tests/trace-skills.test.sh                          # every chain skill emits at its decision points, and none reads the trace
sh tests/fixture-builders.test.sh                      # the test harness's fixture builders
sh tests/harness-helpers.test.sh                       # the test harness's folded assertion helpers
sh tests/design-brief-skill.test.sh                    # the /design-brief contract
sh tests/housekeeping-skill.test.sh                    # the /housekeeping contract
sh tests/retro-skill.test.sh                           # the /retro contract
sh tests/spec-skills.test.sh                           # the /to-prd and /to-tickets contracts
sh tests/skill-phase.test.sh                           # every skill declares its phase of work
sh tests/manifest.test.sh                              # the manifest grammar, once
sh tests/no-box-art.test.sh                            # craft §10: no character art in the shipped prose
sh tests/gate-path-roots.test.sh                       # the gate's two engines agree on their path roots
sh tests/mutation-kit.test.sh                          # the kit's own mutation wrapper, through a stub
sh tests/suite-budget.test.sh                          # every suite runs inside the worker budget
```

`bootstrap.sh` is edited by several kit tickets at once. Each one's changes live
between a `K<n> BEGIN` / `K<n> END` banner — keep yours inside one, and do not
interleave with another ticket's block.

`bootstrap.sh` also contains the one thing in the kit that deletes files at the
*start* of a run: the `F12` block, which removes the kit's own manual, shims and
documentation files before the "already bootstrapped" check would trip on them.
It names **exact files, never a directory**, and is guarded on three conditions:
the template is still present, the root manual carries the `agentic-sdlc:kit-own`
sentinel, **and** git reports no local modification to anything on the list. So a
consumer's second run, a hand-written manual, a decision they recorded in
`docs/adr/` and a manual they personalized in place are all left alone — the
last of those with a refusal that names the file. Do not delete that sentinel
comment from `AGENTS.md`, and add any new kit-own file to the list beside it —
`tests/self-host.test.sh` section E is what holds both.

`UPDATING.md` quotes two transcripts produced by `tests/docs-demo.sh`. If you
change the recipe or the shared layer, re-run the demo and re-paste them — and
the demo will tell you when you have to: its last section compares both `console`
blocks in `UPDATING.md` byte for byte against the run it just did, and fails on a
stale one. A worked example nobody re-runs is exactly the stale standing
instruction shared invariant §8 is about, so this one is re-run on every pass.
Re-paste; never hand-edit a transcript to match.

## References — where the ideas come from

This framework is a synthesis, not an invention. These are the sources it
draws on, so humans and agents alike can trace any practice here back to its
origin.

### Methodology

- **Matt Pocock — [AI Hero](https://www.aihero.dev)**. The core chain
  (grill → PRD → tickets → implement → review) and much of its vocabulary:
  - [Tracer bullets](https://www.aihero.dev/tracer-bullets) — tickets as
    demoable vertical slices sized to one context window, and the standing
    rule against building horizontal layers in isolation.
  - [A complete guide to AGENTS.md](https://www.aihero.dev/a-complete-guide-to-agents-md)
    — the instruction budget and progressive disclosure behind the root manual.
  - The skill write-ups:
    [to-tickets](https://www.aihero.dev/skills-to-tickets),
    [implement](https://www.aihero.dev/skills-implement),
    [code-review](https://www.aihero.dev/skills-code-review).
  - [mattpocock/skills](https://github.com/mattpocock/skills) (MIT) — six of
    the skills are adapted from it; the upstream notice and the
    per-skill provenance table live in
    `.agents/skills/LICENSE-mattpocock-skills.md`.
  - The talk ["A Workflow for AI Coding"](https://www.youtube.com/watch?v=-QFHIoCo-Ko)
    (AI Engineer 2026), with third-party walkthroughs by
    [Sean Weldon](https://www.sean-weldon.com/blog/2026-04-27-workflow-for-ai-coding-matt-pocock)
    and [explainx](https://explainx.ai/blog/matt-pocock-ai-coding-real-engineers-workshop-2026).
- **Robert C. Martin — [swarm-forge](https://github.com/unclebob/swarm-forge)**
  — the layered constitution shape (one root manual → shared articles → local
  articles) and mutation testing as review *evidence* rather than reviewer
  taste.
- **Kieran Klaassen** — the dogfood verification harness idea behind the
  opt-in `/dogfood` skill: synthetic personas exercising the product's real
  user-facing surface before a human does. Credited by name in the
  predecessor project's history; no public link was recorded there.
- **John Ousterhout — *A Philosophy of Software Design*** (2nd ed., 2021) —
  the source of the kit's word **strategic**: chapter 3, "Working Code Isn't
  Enough", sets strategic programming against tactical programming and asks
  for a continuous design investment; chapter 2 defines complexity as dependencies
  plus obscurity, with change amplification, cognitive load and unknown
  unknowns as its symptoms; chapter 4's deep modules and chapter 11's "design
  it twice" are the working vocabulary of `/improve-codebase-architecture`
  and `/design-brief`; chapter 19's software-trends critiques (inheritance,
  test-driven development, design patterns over-applied) are what the brief
  answers; and the book's fourteen red flags are what `/housekeeping`
  scans for. Chapter numbers verified against the second edition's table of
  contents (ADR-0002).
- **Geoffrey Litt — ["Understanding is the new
  bottleneck"](https://www.geoffreylitt.com/2026/07/02/understanding-is-the-new-bottleneck)**
  — the case that as agents write more of the code, human understanding, not
  verification, becomes the constraint. `/explain-diff` is adapted from the
  [skill he published](https://gist.github.com/geoffreylitt/a29df1b5f9865506e8952488eac3d524)
  alongside it; the cognitive-debt framing it fights comes from
  [Margaret-Anne Storey](https://margaretstorey.com/blog/2026/02/09/cognitive-debt/),
  and [Simon Willison's interactive-explanations
  pattern](https://simonwillison.net/guides/agentic-engineering-patterns/interactive-explanations/)
  is the same idea taken further — explanations you can *play with*, not just
  read.

### Standards

- [AGENTS.md](https://agents.md) — the cross-tool manual format. The kit's
  `CLAUDE.md` / `GEMINI.md` are one-line import shims pointing at it.
- [Conventional Commits](https://www.conventionalcommits.org) — the commit
  convention the guards, hooks and skills assume.
- [MADR](https://adr.github.io/madr/) — the decision-record format
  `/grill-with-docs` writes.

The kit was first built and exercised inside a working product
repository and extracted here afterwards; `EXCLUSIONS.md` records what
deliberately stayed behind, and why.
