# Domain glossary — Ubiquitous Language

The registry of canonical terms for agentic-sdlc. Use these spellings and
meanings consistently across **code** (script names, variable names, rule ids),
commit messages, PR titles, ADRs, the diary, and conversations with agents.

One name per concept. An agent given two names for one thing will invent a
distinction between them.

**Adding a term** — introduce it in the same change that first uses it in code.
Say what it *is*, not what it does, and cross-reference the ADR or spec section
that defines its behavior.

**Changing a term** — rename across the whole repo in a single change, and
update this file in the same commit. Do **not** leave aliases: the point of a
ubiquitous language is that there is exactly one name per concept.

**Retiring a term** — keep the entry, mark it _(superseded by `NewName`)_, and
say what replaced it. A deleted entry loses the fact that the old name ever
meant something, which is exactly what a reader of old code needs.

> **Source of truth.** This file is canonical for domain *language*. Where other
> documents disagree on a name, this one wins and they are synced to it. They
> still win on architecture — this carve-out is for naming only.

---

<!--
Grouped by the seam each term belongs to. Entry shape:

  - **Term** — what it is, in one or two sentences. Where it lives. Ref: <ADR>.
    - _Avoid_: <the near-synonym people reach for, and why it is wrong>
-->

## Distribution — what the kit hands over

- **Kit** — this repository, and the thing being built. A template repo, not a
  package: it is consumed by "Use this template" plus one run of
  `bootstrap.sh`, never by a dependency manager.
  - _Avoid_: "the library", "the package" — nothing here is installed or
    versioned into a lockfile.
- **Consumer** — a project created from the kit. The reader of everything under
  `constitution/` and `templates/`, and the only party `UPDATING.md` addresses.
  - _Avoid_: "the user" — ambiguous between the consumer project's authors and
    the end users of whatever they build.
- **Stamp** — to produce a real file from a `*.template` source by substituting
  its double-brace marks, then delete the source. `bootstrap.sh` stamps
  `constitution/AGENTS.md.template` into `AGENTS.md`. A *copied* file, by
  contrast, is placed byte-for-byte with no substitution.
  - _Avoid_: "generate", "render" — both suggest the source stays around and can
    be re-run, and a stamp is one-shot.
- **Manifest** — `VERSION`'s two lists, `files:` (the shared layer) and
  `skills:` (the roster), in one format: an indented entry whose name is its
  first word, the rest annotation. Read by one grammar,
  `scripts/manifest.lib.sh`, which the gate, bootstrap and the suites source;
  the update recipe keeps its own copy by contract and a suite holds the two
  equal.
  - _Avoid_: "the file list" — the manifest is two lists, and the parser is
    the thing that decides what an entry is.
- **Shared layer** — the files listed under `files:` in `VERSION`, copied
  verbatim into a consumer and not edited there. Changing one is a release
  action: minor bump, an `UPDATING.md` entry, and re-captured transcripts.
  Ref: `VERSION`.
  - _Avoid_: "the core", "the framework files" — neither says the thing that
    matters, which is *copied verbatim and therefore diffable*.
- **Policy file** — a file the kit ships whose whole purpose is to be edited by
  the consumer, deliberately kept OUT of the shared layer:
  `scripts/docs-conformance/config.mjs`, `scripts/guards.config.sh`,
  `scripts/agents.config.sh`. Mechanism is shared; policy is local.
  - _Avoid_: "config" alone — it hides the load-bearing half, which is that this
    file is *not* copied verbatim and may diverge freely.
- **Shim** — a tool-specific entry point (`CLAUDE.md`, `GEMINI.md`) holding
  nothing but `@AGENTS.md` and at most one HTML comment. The `shim-invalid` rule
  enforces the shape, because a tool-specific file that *can* hold a rule
  eventually does, and the repo then has two manuals nobody diffs.
  - _Avoid_: "alias", "symlink" — they are real files with real content, just
    provably no rules.
- **Kit-own file** — a file that exists at the kit root because the kit follows
  its own framework, and that `bootstrap.sh` removes before stamping a
  consumer's equivalent: the root `AGENTS.md`, the shims, and the kit's own
  documentation files. Enumerated by exact path in `KIT_OWN`, and recognised as
  a set by the sentinel `agentic-sdlc:kit-own` in the manual. A file at one of
  those paths that the consumer has locally modified is not kit-own any more,
  and bootstrap refuses rather than deleting it. Ref: ADR-0001.
  - _Avoid_: "kit-only" — that is the *other* list in `bootstrap.sh`
    (`KIT_ONLY`: the tests and CI, removed at the END of the run). The two are
    different sets removed at different times for different reasons.

## Enforcement — what keeps the documents honest

- **Gate** — a check that must pass before a push lands, run by
  `.githooks/pre-push` and re-run in CI. The kit has two: the **docs gate**
  (`scripts/check.sh`) and the **TDD pairing guard**
  (`scripts/tdd-pairing-guard.sh`). Every gate has a loud, logged bypass.
  - _Avoid_: "linter" — a gate checks that documents and reality still describe
    each other, not that code is formatted.
- **Guard** — a rule about a *diff* rather than about the tree: the pairing
  guard, the behavior-delta guard. Guards read git history and produce a
  verdict about a range.
- **Harness** — `scripts/docs-conformance/`, the Node implementation of the docs
  gate's reference checks. Dependency-free ESM. When node is absent,
  `scripts/check.sh` runs a **reduced POSIX fallback** and prints a notice
  naming what it can no longer see.
  - _Avoid_: "the validator" for the whole tree — a *validator* is one module
    under `scripts/docs-conformance/validators/`.
- **Rule id** — the kebab-case name a violation reports under:
  `placeholder-unstamped`, `root-manual-missing`, `shared-layer-missing`,
  `path-missing`, `skill-missing`, `article-unreferenced`, `shim-invalid`,
  `portability-leak`. Suites assert on these strings, so they are API.
- **Article** — an on-demand layer of the constitution under `constitution/`,
  loaded when relevant and binding while loaded. Every article must be reachable
  from the root manual (`article-unreferenced`), because an article nothing
  points at binds nobody and rots unseen.
- **Advisory** — a gate finding on the warning channel: printed to stderr by
  the harness and relayed by `scripts/check.sh` on a green run, never failing
  the push. The decision-anchor advisories name a promotion path in their
  validator's header comment. The kit has six (`skill-web`, `skill-paths`,
  `skill-bridge`, `mutation-decision`, `design-brief`, `housekeeping-due` —
  the count moves with
  `scripts/docs-conformance/runner.mjs`). An advisory is the posture for a
  rule about consumer-owned prose, where version skew is a sanctioned state.
  - _Avoid_: "soft failure" — an advisory does not fail; "lint warning" — it
    reports a missing decision, not a style slip.
- **Anchor** — a labeled decision line in a stamped article, `**Label**:`
  followed by the decision, with exactly two honest forms: the decision, or an
  explicit `none — <reason>`. The template stamps the label with a mark after
  it; an advisory referees the filled article. The kit has four: the mutation
  decision, and the design brief's paradigm, architectural style and context
  map.
  - _Avoid_: "placeholder" — a placeholder is the unstamped mark the gate
    rejects; an anchor is the line that survives stamping.
- **Portability** — the property the shared articles must keep: copyable
  verbatim into a repo that shares none of this one's vocabulary. Enforced as a
  deny-list (`portability-leak`) over product names, hostnames, vendors,
  tool invocations, slash commands and repo paths.

## Process — how work moves

- **Tier** — the capability size stamped on a ticket when it is *written*:
  `planner`, `implementer`, `mechanical`, `reviewer`. Resolved to a model at
  spawn time by `scripts/agents.lib.sh` from the mapping in
  `scripts/agents.config.sh`. The kit names no model anywhere.
  - _Avoid_: "model", "agent size" — the tier is a decision about the *work*,
    deliberately made before anyone knows which model will run it.
- **Task domain** — the resolver's optional *second* axis: what the work is made
  **of**, where the tier is how big it is. `content`, `code`, `html-report`. A
  ticket carries one only when the medium would change which model you would
  pick. The axis also admits a token that names a **situation** rather than a
  medium, chosen at spawn time and never stamped on a ticket: `self-implemented`
  on the reviewer tier is the worked example — the session wrote the diff on
  the model the reviewer tier maps to, so the reviewer needs a second answer.
  Unlike the four tier names its vocabulary is **open and local**, so an
  unmapped domain falls back to the plain tier silently; what is not open is its
  **shape** (`[a-z][a-z0-9-]*`), because the token is interpolated into the
  variable name `AGENT_TIER_<TIER>_<DOMAIN>`.
  - _Avoid_: "category", "type of work" — and never a second tier. A `Domain:`
    on every ticket is the same non-decision as one tier on every ticket.
- **Tracer bullet** — a ticket that is a thin end-to-end slice: something
  demoable, not a horizontal layer. In this repo a tracer bullet is typically a
  rule, the check that enforces it, and the suite that drives that check red
  before green. Ref: shared invariant §2.
  - _Avoid_: "MVP", "spike" — a spike is `/prototype` output and is thrown away;
    a tracer bullet is kept and built on.
- **Worktree** — a checkout under `worktree/<slug>` on branch `<type>/<slug>`,
  where all in-progress work happens. The root checkout is never edited
  directly. `worktree/` is untracked, and fixtures strip nested worktrees before
  copying the tree, because "Use this template" never hands anyone one.
  - _Avoid_: "branch" as a synonym — the branch is the ref, the worktree is the
    directory, and this repo cares about both separately.
- **Suite** — one executable script under `tests/`. `tests/lib.sh` is the shared
  harness and is not a suite. "The suite" (singular, unqualified) means all of
  them.
- **Diagram language** — mermaid, in a fenced block, wherever a shipped
  markdown document needs a picture; the forge renders it, and craft rule §10
  forbids the alternative. Each block carries an accessible title and
  description. HTML reports draw inline SVG instead. Ref: the architecture
  skill's presenting contract.
  - _Avoid_: "ASCII diagram", "box drawing" — the thing §10 bans.
- **Demo** — a suite whose output is meant to be *read*: `tests/kit-demo.sh`,
  `tests/docs-demo.sh`. They build a throwaway project and walk it through every
  failure mode the kit claims to catch, red and green.
- **Strategic** — Ousterhout's sense, only: design as a continuous investment,
  judged by the complexity it removes (dependencies plus obscurity). The
  design brief is one strategic act; `/housekeeping`'s red-flag scan is
  its periodic re-question. Ref: ADR-0002.
  - _Avoid_: "strategic design" (Evans's phrase — say context map);
    "strategic vs tactical" for the human/agent split (that is the tier and
    the autonomy label).
- **Design brief** — the recorded output of one `/design-brief` run: the
  three anchors in the engineering article, the glossary's context map, and
  one decision record. Made after a human yes, never before. Ref: ADR-0002.
  - _Avoid_: "architecture doc" — a brief is three anchors and a record, not
    a document that grows.
- **Context map** — the glossary section where every edge between contexts is
  declared from both sides, one relationship per edge named identically on
  both lines. Two declarations of one edge that disagree are the finding.
  Ref: PRD #107; the section below is the kit's own.
  - _Avoid_: "strategic design" — banned below; "context diagram" — a picture
    of the map is not the map.
- **Subdomain classification** — the design brief's split of a system's
  subdomains into core (where the product wins), supporting (needed, not
  differentiating) and generic (buy or copy). It decides where the design
  investment goes, and the brief's decision record carries it. Ref: PRD #107.
  - _Avoid_: "strategic design" — same reason.

---

## Context map

The kit's three sections are its contexts, and the edges between them are
declared here from both sides, in the shape the consumer template teaches.
The map is a chain with a shared kernel closing it, not a cycle of
conformists: `VERSION` is the one file two contexts own together.

### Distribution

- **Distribution → Enforcement**: conformist — upstream; the shared layer's
  manifest and the rule ids are read by the gate exactly as spelled here.
- **Distribution → Process**: shared kernel — co-owner; `VERSION` is the
  kernel — the manifest half is Distribution's, the history note is
  Process's, and only a release action changes either.

### Enforcement

- **Enforcement → Distribution**: conformist — downstream; the gate reads the
  manifest and the rule ids as given and never defines a shared file.
- **Enforcement → Process**: conformist — upstream; the verdicts (green, red,
  advisory) are the words the chain moves on, and a push lands only on green.

### Process

- **Process → Enforcement**: conformist — downstream; the chain never
  redefines what green means.
- **Process → Distribution**: shared kernel — co-owner; the release action
  (bump, note, tag) writes the kernel's note half and ships the manifest
  half unchanged.

---

## Words this project does not use

<!--
The other half of a ubiquitous language, and the half that is usually missing:
the terms that are ambiguous here and are therefore banned. Each line names the
banned word and the word to use instead.
-->

- **install** — ambiguous here (nothing is installed; the kit is copied and
  stamped). Use **bootstrap** for the one-shot run, or **stamp** / **copy** for
  what it does to an individual file.
- **config** on its own — ambiguous between a **policy file** (the consumer's to
  edit) and shared-layer mechanism. Say which.
- **the framework** as a file set — ambiguous between the **kit** (the repo) and
  the **shared layer** (the copied files). Say which.
- **strategic design** — ambiguous between Evans's name for context mapping
  and Ousterhout's "strategic" (design as continuous investment), which is
  the sense the kit's design brief reserves the word for. Use **context map**
  and **subdomain classification**.
