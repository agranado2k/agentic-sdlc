---
id: D-02
type: discovery
title: Outside reading on AI-native SDLC practice
parent: agentic-sdlc
stage: shaped
created: 2026-10-22
updated: 2026-10-23
---

## Problem

The kit's chain stops for a human at every merge (shared invariant §7) and on every unspecified behavior item, whatever the change's risk. The operator already delegates those rulings to the session by standing instruction, so the stop is a formality on most PRs and no protection on the rest: nothing measures whether the review the operator is trusting catches mistakes. The trace records what the chain did but not what happened after a merge, so the kit cannot learn which of its reviews to trust, and its retro → ticket loop has no check that a fix worked. Five outside writings read in this discovery (research.md) converge on the same answer: autonomy earned from measured outcomes, not granted by path or by default.

## Target user

The operator of a kit-driven repository who writes, or has the factory write, well-specified tickets and wants the chain to carry each one to a landed change, involving them only when something high risk happens (operator, 2026-10-23). Second, a consumer with no factory: they get the same chain through the generic planning skills, kept in step with the ticket contract.

## Outcome

A ticket with its spec, gaps and intended result goes through /implement, /review-pr and /merge-train with no human step when its change is low risk, and stops for the operator only when it is high risk. Risk is earned: a repo area becomes low risk when its last 20 landed PRs show fewer than 1 in 20 escaped mistakes and at least 80% of lens findings upheld, and drops back on one escaped mistake. Every decision the agent takes on the ticket's open points is in the PR's decision log. Retro findings return as tickets whose effect is checked before and after.

## Scope

In: the kit side of the ticket → landed change boundary agreed with D-08 — post-merge outcomes in the trace, per-area review precision and miss rate, policy files judged by the base branch, the risk rule and kill switch, the PR decision log and check table, the low-risk lane with the ADR that supersedes §7 for it, the closed retro loop, and the planning skills deferring to the factory where `.factory/` exists.

Out: the factory's item model, gates, views and planning skills (D-08); editing the kit directly from a source; a learned model of risk.

Later: change kind as area × tier; a system-one or small model that helps the kit learn by itself; a record of the agent topology a wave ran with.

## Hypotheses

- H1: within ten waves of PRD-K1 landing, at least one repo area earns low risk under the Q3 thresholds. If none does, the thresholds or the area split are wrong, not the lens.
- H2: once the lane is open, the share of PRs that need the operator falls below half, with no rise in the escaped-mistake rate measured by Q2's definition.
- H3: lens precision measured from post-merge outcomes ranks the lenses differently from the operator's rulings alone; if it does not, rulings were already a sufficient label.

## PRDs

In order (decisions.md Q7). Each is one /to-tickets run.

1. **K1 · Post-merge outcomes in the trace.** Record reverts, later fixes touching a PR's lines within 30 days, failed factory QA and the operator's rulings as outcome events against the PR; compute per-area miss rate and lens precision over the last 20 landings (Q2–Q4). Order 1, in parallel with K4. Depends on nothing.
2. **K4 · Decision log and check table in the PR.** /review-pr records each decision it took on an unspecified internal item, and the `<!-- check-table -->` table of requirement, test tier, result and evidence (contract agreed with D-08). Order 1, in parallel with K1. Depends on nothing.
3. **K2 · Policy files judged by the base branch, failing closed.** A guard, gate or threshold reads its policy from the base branch's version; a missing or unreadable file means high risk. Holds the Q3 thresholds. Order 2. Depends on nothing; sequenced before anything reads a threshold.
4. **K3 · The risk rule, report-only, and the kill switch.** The planner stamps `Risk: low` or `Risk: high <reason>` at /to-tickets (`irreversible`, `security`, `invisible`, `shared-layer`, `unclear`; missing reads `high unclear`); the rule adds `unlearned` (Q3) and `outward` (Q6), and the higher of the two risks holds. Planner–rule disagreements are trace events /retro counts. Reported, not acted on; a kill switch the operator trips. Order 3. Depends on K1, K2.
5. **K5 · The low-risk lane.** A low-risk PR lands without the operator; an ADR supersedes shared invariant §7 for that lane only (a shared-layer release). An escaped mistake demotes its area, opens a revert or fix PR held for the operator, and notifies them (Q5). Order 4. Depends on K3, K4.
6. **K6 · The closed loop.** Retro → ticket → lane → before/after check, eval-gated (three repeats, pooled SD); recurring operator rulings become proposed policy defaults. Order 5. Depends on K5.
7. **K7 · Planning skills defer to the factory.** The kit's generic planning skills defer to the factory's where `.factory/` exists, and `scripts/stamp.sh` reads a factory ticket. Outside the order. Depends on IN-01 (factory).

Raised to D-08 (not edited here): the factory's PRDs A–D depend on K1, K3, K4 and K5; the `Risk:` contract settled with D-08 (decisions.md, 2026-10-23).
