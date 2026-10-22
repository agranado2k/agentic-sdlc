---
id: T-07
type: ticket
title: Every skill declares its powers in allowed-tools
parent: PRD-04
stage: done
created: 2026-10-21
updated: 2026-10-22
deps: [T-06]
priority: 3
links:
  pr: "#821"
review:
  outcome: approved
  commit: "a45ddf0"
  by: "review-pr (sonnet) on #821"
  at: 2026-10-22
qa:
  outcome: pass
  by: "merge-train (#821 landed, suite green)"
  at: 2026-10-22
---

# T-07 · Every skill declares its powers in allowed-tools

GitHub issue: #803

## Behaviour

Part of PRD-04, slice 2. Objective: an operator can judge a skill from its frontmatter.

Every `SKILL.md` the kit ships declares `allowed-tools`: the tools its own session uses, read from its steps (a skill that spawns nothing omits `Agent`). Each spawn type a skill names must fit within its list. Then the kit's gate runs the missing-`allowed-tools` rule as failing, not advisory. That completes process/R30, which T-06 shipped as an advisory. In Claude Code `allowed-tools` pre-approves the tools it names, so each list is the smallest the skill's steps need.

## Acceptance

- The oracle: `sh scripts/check.sh` passes on the kit with all three rules failing, not advisory.
- The living process spec gains process/R29.

Covers: process/R29, process/R30
Tier: implementer
Confidence: medium
Label: none
