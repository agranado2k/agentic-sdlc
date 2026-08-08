# agentic-sdlc

A language-agnostic, agent-first SDLC framework — extracted from a production
project where it was built, reviewed, and exercised by the very chain it defines.

Spec → tracer-bullet tickets → test-first implementation → two-axis review
(standards findings to agents, behavior findings to humans) → human merge gate.
Constitution-layered agent instructions, CI-verified process docs, guards that
block what prose used to merely request.

**Use it as a GitHub template**, run one bootstrap script, and your new repo has
an agent operating manual, the portable rulebook underneath it, and a gate that
fails when the two stop describing reality.

## Quickstart

```sh
# 1. Create your repo from this template ("Use this template" on GitHub, or:)
gh repo create my-project --template agranado2k/agentic-sdlc --private --clone
cd my-project

# 2. Bootstrap. Runs once, then deletes itself. Commits nothing.
sh bootstrap.sh "My Project" "One line about what it does."

# 3. Check the gate is green, then make the first commit yours.
sh scripts/check.sh
git add -A && git commit -m "chore: bootstrap from agentic-sdlc"

# 4. Turn the TDD pairing guard on. It ships INACTIVE — see "The guards".
$EDITOR scripts/guards.config.sh   # set GUARD_SOURCE_RE
```

`bootstrap.sh` stamps `constitution/CLAUDE.md.template` into a root `CLAUDE.md`,
wires the pre-push gate with native `git config core.hooksPath .githooks` (no
hook manager, no dependency), prints your next steps, and removes itself. It
refuses to run a second time rather than overwriting a manual you have since
edited.

## What you get

| Path | What it is |
| --- | --- |
| `constitution/shared-invariants.md` | The portable rulebook — eleven invariants that hold regardless of stack, domain, or vendor. **Shared layer:** copied verbatim, not edited locally. |
| `constitution/CLAUDE.md.template` | The root agent manual, carrying double-brace placeholder marks that bootstrap stamps. Becomes `CLAUDE.md`; then it is yours. |
| `scripts/check.sh` | The docs gate. POSIX sh, no runtime dependency. |
| `scripts/guards.config.sh` | **Yours.** The one place the guards learn your repo's shape — source globs, test globs, contract artifacts. |
| `scripts/tdd-pairing-guard.sh` | The TDD pairing rule: source changes must carry test changes. One implementation, called by the hook and by CI. |
| `scripts/tdd-pairing-guard-ci.sh` | The CI caller of that rule — merge-base range, `tdd-exempt` label hatch. |
| `scripts/behavior-delta.sh` | Inventories the branch's deltas in your contract artifacts, plus a per-commit `refactor:`-that-is-not check. |
| `.githooks/pre-push` | Runs the docs gate and the pairing guard before every push, each with its own loud, logged bypass. |
| `templates/workflows/` | CI workflow templates, copied into `.github/workflows/` by bootstrap. |
| `VERSION` | The shared-layer manifest: which files are shared, at which version. |
| `tests/` | The kit's own acceptance tests (removed from your project by bootstrap). |

## The shared layer, and why it has a version

Most of what bootstrap leaves behind is **yours** the moment it lands — your
`CLAUDE.md`, your local rules, your docs. A small part is not: the files listed
under `files:` in `VERSION` are the **shared layer**, copied verbatim from the
kit and deliberately not edited downstream. They carry no product name, no
command, and no vendor, which is exactly what makes them copyable at all.

`VERSION` pins which release of that layer you took (`shared-layer: 0.1.0`). When
the kit moves, you diff the kit's shared layer against yours and apply what
changed — a manual, reviewable update rather than a dependency bump. That recipe
is written and demonstrated in K4 (#6); today `VERSION` is the anchor it will
diff from, and the gate fails if a shared-layer file goes missing.

A local exception to a shared invariant does not get edited into the shared file.
It goes in a local article, and the shared copy stays byte-identical.

## The gate

Shared invariant §8: a process rule must be executable or CI-verified, because a
rule nothing checks decays into a lie — and a stale standing instruction is worse
than an absent one, since every agent session loads it.

`scripts/check.sh` is the smallest honest version of that. It fails when:

- an unstamped placeholder survived bootstrap (the manual was never personalized);
- a shared-layer file named in `VERSION` is gone;
- the root `CLAUDE.md` references a repo path that does not exist.

It claims nothing more. It runs on `git push` via `.githooks/pre-push`, with
`PUSH_WITHOUT_DOCS=1` as a documented, warning-printing escape hatch.

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

## CI templates, and why they are not workflows here

`templates/workflows/` holds the CI half of each gate. `bootstrap.sh` copies
them into `.github/workflows/` of your project and removes the templates
directory. They are not live in this repo because **a template repository must
not run its consumers' CI against its own tree** — the kit has a
`CLAUDE.md.template` rather than a `CLAUDE.md`, and no configured source globs,
so both consumer gates are designed to be inert or red here.

Commit linting ships as `commitlint.yml.example` — inert, because GitHub Actions
reads `.yml`. It is the one gate whose reference implementation needs node, and
the kit does not decide that your project uses node. Rename it when you are
ready; the header explains what to do if you are not on node.

The kit's own CI is `.github/workflows/kit-guards.yml`, which runs the guard
test tiers and the end-to-end demo against this tree.

## Status — honest version

This is the **walking skeleton (K0)** plus the **guards (K3)**: thin, but
end-to-end and actually exercised. `sh tests/skeleton-demo.sh` builds a throwaway
project from this tree, bootstraps it, and proves the gate green — then proves it
red on an unstamped placeholder and on a deleted shared-layer file, including a
real `git push` that the hook actually blocks. `sh tests/guards-demo.sh` does the
same for the guards: bootstrap, an unconfigured push that warns and passes,
globs configured, a source-only push the hook really blocks (origin does not
move), and the paired push that lands.

Not here yet, each with its own ticket:

| | Ticket | Brings |
| --- | --- | --- |
| K1 | [#3](https://github.com/agranado2k/agentic-sdlc/issues/3) | The full docs-conformance harness + `claude-md-refs` validator (slash-command resolution, article reachability, the portability deny-list), `local-engineering` / `local-workflow` templates |
| K2 | [#4](https://github.com/agranado2k/agentic-sdlc/issues/4) | Twelve de-productized skills — grill-me, to-prd, to-tickets, implement, tdd, review-pr, pr-iterate, diagnose, and the rest |
| K4 | [#6](https://github.com/agranado2k/agentic-sdlc/issues/6) | Docs skeletons (diary, ADR dir + MADR template, glossary, PR template) and `UPDATING.md` — the shared-layer update recipe |
| K5 | [#7](https://github.com/agranado2k/agentic-sdlc/issues/7) | `adapters/node-ts/` — one worked reference wiring (vitest, Stryker differential, eval tier) |
| K6 | [#8](https://github.com/agranado2k/agentic-sdlc/issues/8) | Dogfood: a throwaway project end-to-end, and the verbatim claim proved by diff |

The PRD is [#1](https://github.com/agranado2k/agentic-sdlc/issues/1). The kit is
built ticket-by-ticket by its own `/to-tickets` → `/implement` chain.

## Working on the kit itself

`scripts/check.sh` is written for a *bootstrapped* project, so running it against
this repo fails on purpose: the kit has a `CLAUDE.md.template`, not a `CLAUDE.md`.
The kit's own gates are its tests, which run the consumer gates inside real
throwaway consumers. Do not wire `core.hooksPath` in this repo.

```sh
sh tests/skeleton-demo.sh            # K0: bootstrap + docs gate, end to end
sh tests/guards-demo.sh              # K3: the guards, end to end
sh tests/tdd-pairing-guard.test.sh   # the pairing rule
sh tests/tdd-pairing-guard-ci.test.sh
sh tests/behavior-delta.test.sh
```
