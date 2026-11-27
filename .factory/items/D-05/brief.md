---
id: D-05
type: discovery
title: Improve the SDLC agent harness
parent: agentic-sdlc
stage: exploring
created: 2026-11-16
updated: 2026-11-16
stages:
  - {stage: exploring, at: 2026-11-16T10:31Z}
---

## Problem

The kit's agent harness is what runs its SDLC chain end to end: the skills, the hooks and guards around an agent's tools, the dispatcher that spawns sessions and reviewers, and the trace they write. The question: what should change in that harness so agents deliver more reliably and at lower cost, and which practices from other agent harnesses are worth adopting?

## Outcome

A change to the kit's harness — a skill, a guard, a lens, the dispatcher — is accepted on measured evidence. A review replay restores past landed PRs whose outcome is known (reverted, fixed, or merged and stable) to the reviewed commit, runs the review chain on them, and scores recall per stage (raw findings, after verification, final) and precision against the stable control, before and after the change. Every commit carries a stamp of how it was verified, "none" included, so unverified work can be counted.

## Scope

In:
- **The review replay** on K1's outcomes, with per-stage recall; its first use settles one tuned reviewer against the stacked cross-provider verifier (S-14, S-7).
- **Diff-scoped evidence gates:** mutation and CRAP scores on the changed code as evidence `/review-pr` reads, and property and differential tiers in the test ladder (S-2, S-4, S-9, S-14).
- **Gate rollout modes:** off, observe and enforce, a two-block escape, and the per-commit verification stamp; D-02's fail-open question settled per guard through observe mode (S-14, S-16).
- **Harness reliability and cost:** reconcile an unknown side effect before a retry, a skill content hash on each spawn, a count of missing usage before cost is trusted, per-run token and time budgets, a Stop-hook completion gate (S-15, S-19, S-23, D-02/S-17).

Out: which model runs which tier (D-04); the review process itself beyond measuring it (D-03); per-turn supervisor mods (rejected in D-02).

Later: formal proof (Lean, Rocq) as an optional top rung for a consumer (S-8 to S-13); decision models for fixed-choice gates (D-02/S-8); incident-backed diff triggers once incidents exist (S-14); the topology record D-02 recommended and no PRD took.
