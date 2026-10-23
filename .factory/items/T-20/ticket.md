---
id: T-20
type: ticket
title: The landing script re-runs a stuck in-progress job once
parent: agentic-sdlc
class: toil
stage: proposed
created: 2026-10-23
updated: 2026-10-23
deps: []
priority: 3
---

# T-20 · The landing script re-runs a stuck in-progress job once

GitHub issue: #850

Finding (retro R5, Q6): the landing script's wait on a PR's checks hangs when a run has completed but one of its job records stays "in progress".

Retro: retro-20261023T103804Z

## Evidence

- pr:#842 waited 3,308 seconds before landing.
- pr:#831 (2026-10-22) hung the same way. `gh run cancel` reported the run completed. Re-running the one stuck job cleared both.

## Behaviour

- While waiting, the landing script spots a completed run that still holds a job "in progress".
- It re-runs that job once and says so in its output.
- A second stall on the same job is a stop, as any red check is.

## Acceptance

- The landing suite, with a stubbed forge, re-runs the stuck job exactly once and names it, red first.
- The same suite stops on a second stall.

## Demo

The stubbed run lands after one re-run, and the output line names the job.

Tier: implementer
Confidence: medium
Class: toil
