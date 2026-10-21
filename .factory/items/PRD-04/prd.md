---
id: PRD-04
type: prd
title: Skills declare their powers, and a subagent's only narrow
parent: D-01
stage: approved
created: 2026-10-20
updated: 2026-10-21
approved_by: "agranado"
approved_at: 2026-10-21
---

# PRD-04 · Skills declare their powers, and a subagent's only narrow

## 1. Objective

Have every skill declare in its frontmatter the tools it needs, and have the docs gate check
two things: that every agent type the kit ships names its tools, and that a skill spawns only
types whose tools are within its own. A spawned subagent can then only ever narrow what its
spawner may do.

Today none of the 18 `SKILL.md` files declares `allowed-tools`. Tool limits live only on the
agent types under `.claude/agents/` (reviewer: Read, Grep, Glob; mechanical adds Bash, Edit,
Write, Skill; planner and implementer add Agent). The adapter's README says "a type with no
`tools:` line inherits every tool", and nothing checks that a type keeps its line. A reader of a
skill cannot tell what the skill may do without reading every step. This is the software
factory's D-03 Q19 proposal 4 (its research, rows 10 and 11).

The test of done:
- `sh scripts/check.sh` fails a `SKILL.md` with no `allowed-tools`.
- It fails an agent type with no `tools:` line.
- It fails a skill that names a spawn type whose tools are outside the skill's own.

## 2. Users and scenarios

**U1 — a consumer's operator**, deciding whether to trust a skill. **U2 — the kit's
maintainer**, editing a skill.

Stories:

1. As an operator, I want each skill to state the powers it uses, so that I can judge it from
   its frontmatter.
2. As the maintainer, I want the gate to catch a spawn that would widen powers, so that no edit
   quietly gives a subagent more than its spawner has.

**UC1 — A skill states its powers.** Actor: the operator, reading `/explain-diff`.
1. Its frontmatter reads, for example, `allowed-tools: Read, Grep, Glob, Bash, Write` (illustrative, not
   checked against the skill).
2. The operator sees it spawns nothing, since `Agent` is absent, and allows it.

**UC2 — The gate catches a widening.** Actor: the maintainer, editing `/review-pr`.
1. They change a lens spawn's type from `reviewer` to `implementer`.
2. `sh scripts/check.sh` fails: `review-pr spawns implementer, whose tools (Edit, Write, Agent)
   are outside its allowed-tools`.

Extensions:
- 2a. They delete `tools:` from `.claude/agents/reviewer.md`. The gate fails: `reviewer has no
  tools line, so it inherits every tool`.

## 3. Model

- `allowed-tools` in a `SKILL.md`'s frontmatter, in the Agent Skills format: the tools the
  skill's own session uses. In Claude Code it pre-approves them. It is a declaration and an
  input to the gate, not a sandbox.
- A **spawn type** is an agent type a skill names in a spawn instruction. The narrowing rule:
  that type's `tools:` ⊆ the skill's `allowed-tools`.

## 4. Rules

Area: process

Deltas against `docs/specs/process.md`, numbered after PRD-03's process/R22 to R28.

### ADDED

process/R29. Every `SKILL.md` the kit ships SHALL declare `allowed-tools` in its frontmatter. [UC1 1]
process/R30. The docs gate SHALL fail a `SKILL.md` with no `allowed-tools`.
process/R31. The docs gate SHALL fail an agent type under the adapter with no `tools:` line. [UC2 2a]
process/R32. WHERE a skill names a spawn type, the docs gate SHALL fail it when that type's `tools:` holds a tool absent from the skill's `allowed-tools`. [UC2 2]

## 5. Slices (vertical, demoable, in order)

**Slice 1 — the gate rules, with fixtures.**
- *Covers:* process/R30, R31, R32.
- *Accept:* a fixture tree per rule under the gate's tests, failing and passing.

**Slice 2 — every skill declares its powers.**
- *Covers:* process/R29.
- *Accept:* `sh scripts/check.sh` passes on the kit with R30 to R32 on.

## 6. Non-goals (this PRD)

- **Enforcing tools at run time** — *never* in the kit: that is the harness's job, through agent
  types and permission settings.
- **Per-step tool limits inside a skill** — *later*: reopen if a skill's steps need different
  powers.

## 7. Technical constraints

The gate's validators (`scripts/docs-conformance/`), with policy as data in `config.mjs`. A
consumer's own skills are held to the rule too, since they go through the same gate.

## 8. Decisions recorded for this PRD

- The software factory's D-03 Q19, proposal 4.
- **Derived while writing:** R32 checks only spawn types a skill names. A spawn that inherits
  the session's type is already within the skill's powers.

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

- **How the gate finds a skill's spawn types.** MVP: a type token named in a spawn sentence (for
  example "the `planner` agent type"), matched against the adapter's type names.

## 10. Dogfood plan

Two tickets: the rule first, then the sweep (rule with its check first, then the sweep blocked
by it).
