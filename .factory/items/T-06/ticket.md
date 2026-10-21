---
id: T-06
type: ticket
title: "The docs gate checks declared tools: a skill's allowed-tools, an agent type's tools line, and spawns that only narrow"
parent: PRD-04
stage: ready
created: 2026-10-21
updated: 2026-10-21
deps: []
priority: 2
---

# T-06 · The docs gate checks declared tools: a skill's allowed-tools, an agent type's tools line, and spawns that only narrow

GitHub issue: #800

## Behaviour

Part of PRD-04, slice 1. Objective: a spawned subagent can only ever narrow what its spawner may do.

Three gate rules, policy as data in the gate's config: a `SKILL.md` with no `allowed-tools` in its frontmatter fails; an agent type under the adapter with no `tools:` line fails (it would inherit every tool); a skill that names a spawn type whose `tools:` holds a tool absent from the skill's `allowed-tools` fails, naming the skill, the type and the tools outside. A spawn type is a type token named in a spawn sentence, matched against the adapter's type names (MVP). The POSIX fallback twin moves with the config list. Because no kit skill declares `allowed-tools` yet, the kit's own gate runs the first rule as an advisory until the sweep ticket turns it to failing; the gate stays green on main.

Shared layer: a new validator joins the manifest, so this ticket carries the minor bump, its update-recipe entry and the re-captured pinned transcripts, and lands tagged (hard rule 3, ADR-0025).

## Acceptance

- A fixture tree per rule under the gate's tests, each failing and passing.
- PRD-04 UC2 and UC2 2a reproduce on fixtures with the messages the PRD gives.
- The living process spec gains process/R30 to R32.

Covers: process/R30, process/R31, process/R32
Tier: implementer
Confidence: high
Label: none
