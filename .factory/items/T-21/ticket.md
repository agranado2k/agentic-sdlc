---
id: T-21
type: ticket
title: The Bash guard refuses a pgrep -f wait loop
parent: agentic-sdlc
class: toil
stage: review
created: 2026-10-23
updated: 2026-10-25
deps: []
priority: 3
links:
  pr: "#853"
approved_by: "agranado"
approved_at: 2026-10-25
---

# T-21 · The Bash guard refuses a pgrep -f wait loop

GitHub issue: #849

Finding (retro R4, Q6 and Q3): a wait loop such as `until ! pgrep -f "<command>"` matches its own command line, so it never exits. It then holds a worktree as "live", and the cleanup keeps that worktree.

Retro: retro-20261023T103804Z

## Evidence

- The window's tool calls include 10 `until ! pgrep -f` loops.
- One loop, waiting on `gh pr checks 841 --watch`, never exited and held a worktree on 2026-10-22. The same thing happened on 2026-10-21.
- Each time the stuck loop was found and killed by hand at wrap-up.

## Behaviour

- The agent harness's Bash pre-tool guard refuses an `until` or `while` loop that polls `pgrep -f`.
- Its refusal message names the bounded alternatives: a foreground `timeout <n>` around the command being waited on, or the harness's own notification when a background command ends.
- A loop with an explicit `timeout` bound is let through.

## Acceptance

- The guard's suite refuses the `pgrep -f` loop form, red first.
- The same suite lets a `timeout`-bounded wait through.

## Demo

The guard refuses `until ! pgrep -f "x"; do sleep 5; done` with the message.

Tier: implementer
Confidence: medium
Label: none
Class: toil
