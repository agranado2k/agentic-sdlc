---
id: T-09
type: ticket
title: Release the D-01 wave
parent: PRD-05
stage: done
created: 2026-10-21
updated: 2026-10-22
deps: [T-01, T-02, T-03, T-04, T-05, T-06, T-07, T-08]
priority: 3
links:
  pr: "#830"
review:
  outcome: approved
  commit: "c4f4ec3"
  by: "review-pr (sonnet) on #830"
  at: 2026-10-22
qa:
  outcome: pass
  by: "merge-train (#830 landed, suite green)"
  at: 2026-10-22
---

# T-09 · Release the D-01 wave

GitHub issue: #804

## Behaviour

Part of D-01 (PRD-01 to PRD-05). Objective: consumers can reach the wave through the update recipe.

After every other D-01 ticket has landed, bump the shared-layer minor with a history note that enumerates the wave's non-manifest half (the skill changes to `/review-pr`, `/pr-iterate`, `/implement`, `/retro`, `/to-prd`, `/to-tickets` and every skill's `allowed-tools`, plus any wiring), record the update-recipe entry, re-capture the pinned transcripts, and land with the merge commit tagged. Release notes are written from the tag's content. The bumps the shared-layer tickets carried stay as they are; this one covers what landed after the last of them.

## Acceptance

- The self-host suite is green, including its history-note and tag legs, on the tagged merge commit.

Covers: none (release)
Tier: implementer
Confidence: medium
Label: none
