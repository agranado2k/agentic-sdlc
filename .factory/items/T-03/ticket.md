---
id: T-03
type: ticket
title: "Runs record their context: kit version, model, harness and a spawn's tools"
parent: PRD-03
stage: done
created: 2026-10-21
updated: 2026-10-21
deps: []
priority: 2
---

# T-03 · Runs record their context: kit version, model, harness and a spawn's tools

GitHub issue: #798

## Behaviour

Part of PRD-03, slice 1. Objective: a comparison across time compares like with like.

When the trace's `begin` opens a run, its `run.start` carries `data.kit`, the shared-layer version as the manifest writes it. Where the harness exposes the session's model or its own name, `run.start` carries `model` and `harness`; a value the harness does not expose is left out, never guessed. A recorded `spawn` carries `data.tools`, the tool list of the agent type it spawned as. MVP for the model under Claude Code: the adapter's session hook passes it where the hook payload carries it. No field holds untrusted text; the trace stays append-only.

Shared layer: the trace script is in the manifest, so this ticket carries the minor bump, its update-recipe entry and the re-captured pinned transcripts, and lands tagged (hard rule 3, the kit's ADR-0025).

## Acceptance

- A trace suite asserts `run.start` carries `data.kit`; carries `model` when the harness variable is set and none when it is not; and `spawn` carries `data.tools`.
- The living runtime spec gains runtime/R28 to R30.

Covers: runtime/R28, runtime/R29, runtime/R30
Tier: implementer
Confidence: low
Label: none
