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
  `scripts/agents.config.sh`, `scripts/trace.config.sh`. Mechanism is shared;
  policy is local.
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
- **Docs harness** — `scripts/docs-conformance/`, the Node implementation of the
  docs gate's reference checks. Dependency-free ESM. When node is absent,
  `scripts/check.sh` runs a **reduced POSIX fallback** and prints a notice
  naming what it can no longer see.
  - _Avoid_: "the validator" for the whole tree — a *validator* is one module
    under `scripts/docs-conformance/validators/`; and the bare "harness", which
    since the agent-harness axis means two things here — see "Words this
    project does not use".
- **Rule id** — the kebab-case name a violation reports under:
  `placeholder-unstamped`, `root-manual-missing`, `shared-layer-missing`,
  `path-missing`, `skill-missing`, `article-unreferenced`, `shim-invalid`,
  `portability-leak`. Suites assert on these strings, so they are API.
- **Article** — an on-demand layer of the constitution under `constitution/`,
  loaded when relevant and binding while loaded. Every article must be reachable
  from the root manual (`article-unreferenced`), because an article nothing
  points at binds nobody and rots unseen.
- **Advisory** — a gate finding on the warning channel: printed to stderr by
  the docs harness and relayed by `scripts/check.sh` on a green run, never failing
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
  variable name `AGENT_TIER_<TIER>_<DOMAIN>`. A situation domain's answer is
  also compared against the **session's own model** when the caller names it
  (`AGENT_SESSION_MODEL`, in the policy file's own word): a reviewer answer equal
  to it is refused, falling back to the plain tier or to nothing with a
  warning — the reviewer is a relation between two models, and only the caller
  holds the second. Ref: ADR-0007.
  - _Avoid_: "category", "type of work" — and never a second tier. A `Domain:`
    on every ticket is the same non-decision as one tier on every ticket.
- **Phase** — the kind of work a SKILL is, declared in its own frontmatter
  (`metadata.phase`) and shipped with it: `planner`, `implementer`, `tester`,
  `mechanical`, `reviewer`. Where a tier sizes one ticket, a phase sizes the
  skill, so a session can resolve the model a command deserves without a
  ticket in hand. `tester` is the one that is not a tier — it is implementer
  work whose medium is a test, carried as the `tests` domain, because the
  tier vocabulary is closed.
  Where a ticket and a skill both answer, the **ticket wins**: its tier was
  decided by the actor with a view of the whole wave, and the phase is what
  sizes a command nobody wrote a ticket for. Ref: #229.
  - _Avoid_: "step" (the chain's order is not the work's kind), and "tier"
    for this — a tier is stamped on a ticket, a phase is declared by a skill.
- **Agent harness** — the agent CLI a tier's model runs *in*: the program that
  holds the session, loads `AGENTS.md`, and owns the tool calls. The resolver's
  optional *third* axis: declared in `AGENT_HARNESSES` and written as the
  prefix of a tier's value (`<agent harness>:<model id>`), which is the design
  ADR-0005 records and #173 builds — until that lands, the name is settled here
  and the mechanism does not exist yet. Where the tier is how
  big the work is and the task domain is what it is made of, the agent harness
  is *whose* session runs it — the axis that makes a reviewer from a different
  vendor reachable without CI. An unprefixed value means the caller's own agent
  harness, which is what every tier meant before the axis existed.
  - _Avoid_: the bare "harness" — see "Words this project does not use";
    "provider" (that is the vendor behind the model, not the program running
    it); and "runner".
- **Budget** — the two ceilings a dispatched worker's whole process tree runs
  inside: a task ceiling and a memory ceiling, decided at dispatch time as a
  percentage of the host — the task ceiling the operator's own session runs
  under, and the memory available right now — clamped to a policy floor and
  ceiling. Percentages and clamps are policy-file variables in
  `scripts/agents.config.sh`; derivation, the enforcement ladder and the exit
  status (71) are `scripts/agent-dispatch.sh`'s, and `--dry-run` shows the
  budget before a token is spent. A nested dispatch inherits the outer's and
  never opens a fresh one. Every suite runs inside one too, applied by the
  shared test harness through the dispatcher's own derivation; `AGENT_SUITE_BUDGET=off`
  is the off switch. Ref: ADR-0006, and its #209 amendment.
- **Trace** — the append-only record of the chain's decisions: one event per
  line, per-day files under a trace directory the policy file names, written
  by `scripts/trace.sh` and read only after the fact — by the operator, a
  diagnosis or a retrospective, never by a chain skill (shared invariant §4).
  Unconfigured is a working state: with no directory named, an emit is a
  silent no-op. The kit traces itself through a never-shipped twin of the
  policy file. Ref: ADR-0008, PRD #237.
  - _Avoid_: "log" (a trace is structured and joinable, a log is lines);
    "telemetry" (nothing leaves the machine); "memory" (ADR-0005's non-goal
    stands — the chain never reads it back).
- **Event** — one line of the trace: a schema version, a UTC timestamp, an
  id, a **kind** from a closed vocabulary (unknown is a usage error, like an
  unknown tier), the resolver's words where they apply, an outcome, a
  one-line reason, raw token counts, and an open `data` map of strings.
  Fields sit in a fixed order and absent optionals are omitted; nothing ever
  rewrites one — a correction is a new event.
  - _Avoid_: "entry", "record" — both are used for the decision records.
- **Subject** — what an event is about, written `<type>:<reference>`:
  `prd:#12`, `ticket:#34`, `pr:#56`, `branch:feat/x`, `session:<id>`,
  `run:<id>`, `worktree:<slug>`. The type set is open; the shape is not, so a
  PRD, a ticket, a PR and a session all join on one column, and `show`
  matches one exactly — `ticket:#3` never finds `ticket:#34`. An event may
  name secondary subjects under `related`.
  - _Avoid_: "target", "ref" alone.
- **Run** — one invocation of a skill, with an id the trace hands out at
  `begin` and closes at `end`; every event emitted in between carries it, a
  nested skill carries the outer as `parent`, and a dispatched worker gets
  its own with the dispatching run as parent. Arrives with #248; the name is
  settled here.
  - _Avoid_: "session" for this — a session is the agent harness's, and holds
    many runs.
- **Blob** — a payload too large or too shaped for one event line — a prompt,
  a tool result, spike evidence — stored once under the trace directory by
  content hash and referenced from the event. Arrives with #248.
  - _Avoid_: "attachment".
  - _Avoid_: "quota" — a quota is a share allotted for a period; a budget
    here is a ceiling on one tree, derived fresh per dispatch. "Limit" and
    "cap" stay ordinary words for the host facts a budget is derived *from*
    (the slice's `TasksMax`, the per-user process limit); only the derived
    pair is the budget.
- **Dispatch scratch** — the directory `scripts/agent-dispatch.sh` stages a
  worker's prompt in: `agent-dispatch.XXXXXX` under `$TMPDIR` (else `/tmp`),
  removed by the dispatcher's own trap — and, when a dispatch dies before
  reaching it, by a later dispatch's sweep. Recognisable by name alone, which
  is what the sweep and `/housekeeping` item 5 act on. Ref: ADR-0005 (the
  dispatcher's home); #210.
  - _Avoid_: "temp dir", "the tmp directory" — the name is the point; a
    directory that is only a temp dir cannot be told from anyone else's.
- **Sweep age** — how old dispatch scratch must be before the next dispatch
  removes it on entry: `AGENT_DISPATCH_SWEEP_DAYS` in the policy file, whole
  days, kit default one. It exceeds any `--timeout` a dispatch runs under, and
  the dispatcher refuses a `--timeout` that reaches it, so scratch past the
  sweep age was never a dispatch still running *under `--timeout`*. An untimed
  dispatch has no such bound: one that outlives the sweep age has its scratch
  removed under it by the next dispatch, which is survivable — the worker took
  its prompt at exec, and the trap's removal of a directory already gone is a
  no-op. On the scope rung the wrapper's verdict, written there after the
  worker exits, is then lost: the dispatch says so and passes the worker's own
  status through; it never runs the worker again. Ref: #210, #208.
  - _Avoid_: "TTL", "expiry" — the scratch does not expire; it is evidence of
    a dispatch that died, kept long enough to be sure of that.
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
  test harness and is not a suite. "The suite" (singular, unqualified) means all of
  them. A suite runs inside the budget from the line that sources the test harness.
- **Diagram language** — mermaid, in a fenced block, wherever a shipped
  markdown document needs a picture; the forge renders it, and craft rule §10
  forbids the alternative. Each block carries an accessible title and
  description. HTML reports draw inline SVG instead. Ref: the architecture
  skill's presenting contract.
  - _Avoid_: "ASCII diagram", "box drawing" — the thing §10 bans.
- **Scenario** — in a PRD, a numbered walkthrough of the finished system in use:
  actor, action, what they see, with concrete names. `/to-prd` writes one per
  major story; `/to-tickets` reads them as the first list of tracer bullets.
  - _Avoid_: the Gherkin sense — a feature file's `Scenario:` is executable
    spec, held by the guards; say "feature file" for that.
- **Open issue** — a PRD question the conversation left unresolved, written as
  problem / options / next step. One whose answer would shape tickets is the
  **open-issue gate**: `/to-tickets` writes its resolution as the first ticket
  and every ticket it shapes is blocked by it. Resolved, it moves into the
  PRD's decisions or a decision record.
  - _Avoid_: "TBD", "TODO" — an open issue has a next step, a TODO has none.
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
  what it does to an individual file. Except: **the dependency sense** —
  `dependency install`, `npm install`, `unpinned installs`, `install error`,
  `installed extension`.
- **config** — ambiguous on its own between a **policy file** (the consumer's
  to edit) and shared-layer mechanism. Use **policy file** or **shared-layer
  mechanism**, or qualify it. The unabbreviated **configuration**, in its
  general sense — a system's settings, an interface's required
  configuration — is not this entry's concern and is not banned. Except:
  **a qualified use** — `per-clone config`, `gate config`,
  `test-runner config`, `config schema`, `your config`, `config-as-data`.
- **harness** on its own — ambiguous between the **docs harness**
  (scripts/docs-conformance/, the gate's Node engine) and the **agent harness**
  (the agent CLI a tier's model runs in). Say which.
  The ORDINARY SENSE — a rig you build to exercise code, as the diagnose skill
  builds one to reproduce a bug — is not this entry's concern and is not
  banned, but the check cannot read that sentence: it carves out only the code
  spans in the Except clause below, so the phrases carrying that sense are
  listed there with the rest. A new phrasing needs a new span, which is the
  honest cost of banning a word the language also uses.
  Variable names spelled AGENT_HARNESS_SOMETHING need no carve-out: underscore
  is a word character, so the check never finds a bare word inside one. Do not
  add them to the clause below as documentation — every span there is a carve-out
  phrase, and a span holding a single underscore blanks underscores everywhere,
  which splits those very names apart and reports the fragment.
  Except: **a qualified use** — `docs harness`, `agent harness`,
  `agent-harness`, `test harness`, `throwaway harness`, `bisection harness`,
  `timing harness`.
- **the framework** as a file set — ambiguous between the **kit** (the repo) and
  the **shared layer** (the copied files). Say which.
- **strategic design** — ambiguous between Evans's name for context mapping
  and Ousterhout's "strategic" (design as continuous investment), which is
  the sense the kit's design brief reserves the word for. Use **context map**
  and **subdomain classification**.
