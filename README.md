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
| `.githooks/pre-push` | Runs the gate before every push, with a loud, logged bypass. |
| `VERSION` | The shared-layer manifest: which files are shared, at which version. |
| `tests/skeleton-demo.sh` | The kit's own acceptance test (removed from your project by bootstrap). |

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

## Status — honest version

This is the **walking skeleton (K0)**: thin, but end-to-end and actually
exercised. `sh tests/skeleton-demo.sh` builds a throwaway project from this tree,
bootstraps it, and proves the gate green — then proves it red on an unstamped
placeholder and on a deleted shared-layer file, including a real `git push` that
the hook actually blocks.

Not here yet, each with its own ticket:

| | Ticket | Brings |
| --- | --- | --- |
| K1 | [#3](https://github.com/agranado2k/agentic-sdlc/issues/3) | The full docs-conformance harness + `claude-md-refs` validator (slash-command resolution, article reachability, the portability deny-list), `local-engineering` / `local-workflow` templates |
| K2 | [#4](https://github.com/agranado2k/agentic-sdlc/issues/4) | Twelve de-productized skills — grill-me, to-prd, to-tickets, implement, tdd, review-pr, pr-iterate, diagnose, and the rest |
| K3 | [#5](https://github.com/agranado2k/agentic-sdlc/issues/5) | TDD pairing guard + CI twin, behavior-delta, workflow templates |
| K4 | [#6](https://github.com/agranado2k/agentic-sdlc/issues/6) | Docs skeletons (diary, ADR dir + MADR template, glossary, PR template) and `UPDATING.md` — the shared-layer update recipe |
| K5 | [#7](https://github.com/agranado2k/agentic-sdlc/issues/7) | `adapters/node-ts/` — one worked reference wiring (vitest, Stryker differential, eval tier) |
| K6 | [#8](https://github.com/agranado2k/agentic-sdlc/issues/8) | Dogfood: a throwaway project end-to-end, and the verbatim claim proved by diff |

The PRD is [#1](https://github.com/agranado2k/agentic-sdlc/issues/1). The kit is
built ticket-by-ticket by its own `/to-tickets` → `/implement` chain.

## Working on the kit itself

`scripts/check.sh` is written for a *bootstrapped* project, so running it against
this repo fails on purpose: the kit has a `CLAUDE.md.template`, not a `CLAUDE.md`.
The kit's own gate is `sh tests/skeleton-demo.sh`, which runs the consumer gate
inside a real throwaway consumer. Do not wire `core.hooksPath` in this repo.
