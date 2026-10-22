---
id: T-13
type: ticket
title: Reviewer lenses run on the reviewer agent type; the parent emits their raises
parent: agentic-sdlc
class: toil
stage: proposed
created: 2026-10-22
updated: 2026-10-22
deps: [T-11]
priority: 3
---

# T-13 · Reviewer lenses run on the reviewer agent type; the parent emits their raises

GitHub issue: #834

Finding (retro F3, Q6 and Q5): reviewer-tier work runs on wider agent types, because the `reviewer` type cannot emit trace events.

Retro: retro-20261022T135553Z

## Evidence

66 of 177 reviewer-tier stops (37 %) ran on other agent types: planner 48, implementer 10, general-purpose 7, claude 1. Those types hold Edit, Write, Bash and Agent, which undoes the offline reviewer contract. Their first-call median prompt was 25,958 tokens (planner) and 39,330 (general-purpose), against 17,697 on the reviewer type. That mix raised the window's overall median by 53 %.

Runs: 20261014T152844Z-1377177-493fac3c 20261014T153426Z-1944329-92405beb 20261021T115721Z-2704608-e6fbf03b 20261021T181424Z-2293020-80433348

## Behaviour

- /review-pr: a lens returns its raise lines in a declared shape, and the parent session emits them. A lens then needs no shell and runs on the `reviewer` type (Read, Grep, Glob).
- The spawn guard refuses a `tier=reviewer` spawn on any agent type but `reviewer`.

## Acceptance

- A spawn-guard suite leg drives the refusal RED, then green.
- A review-pr contract leg pins the lens return shape and the parent-side emit.
- Shared-layer release where the moved files are VERSION-listed.

Blocked by: #832 (T-11)

Tier: planner
Confidence: medium
Class: toil
Targets: kind=agent.stop tier=reviewer data.agent_type=planner
Label: none
