# Development diary

> Living history of the agentic-sdlc build. The **Current state** block at the
> top is the agent re-orientation summary — read it first when picking up the
> project. Below it: forward-chronological entries, newest at the bottom.

---

## Current state — 2026-08-27

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
| **Phase** | The kit is shipping. Shared layer 0.5.0; the constitution, both gates, the guards, the skills, the adapters and the consumer workflow templates are all in place and under test. |
| **Repo** | `agentic-sdlc`, a template repository (`main`). Feature work happens in `worktree/<slug>` on a `<type>/<slug>` branch. |
| **Remote** | `git@github.com:agranado2k/agentic-sdlc.git` |
| **Deployed / live** | Nothing is deployed — the kit's delivery is "Use this template" plus `sh bootstrap.sh`. |
| **Spec status** | Wave-based; tickets are the unit of work and each one carries a capability tier. |
| **Self-hosting** | The kit now obeys its own constitution: root `AGENTS.md`, the two shims, this docs set, and a green `sh scripts/check.sh` at the repo root. See `docs/adr/0001-the-kit-self-hosts-its-own-constitution.md`. |

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
