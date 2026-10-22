---
id: T-10
type: ticket
title: A fresh bootstrap copies the kit's own .factory/ into the consumer
parent: agentic-sdlc
class: toil
stage: done
created: 2026-10-21
updated: 2026-10-21
approved_by: "agranado"
approved_at: 2026-10-21
deps: []
priority: 3
links:
  pr: "#813"
review:
  outcome: approved
  commit: "d2b9351"
  by: "review-pr (sonnet) on #813"
  at: 2026-10-21
qa:
  outcome: pass
  by: "merge-train (#813 landed, suite green)"
  at: 2026-10-21
---

# T-10 · A fresh bootstrap copies the kit's own .factory/ into the consumer

GitHub issue: #812

## Behaviour

Raised 2026-10-20, from the self-host suite on PR #795.

This repository now commits its own `.factory/`: the software factory's discovery and PRDs about the kit. `bootstrap.sh`'s `KIT_OWN` strip list names the kit's own files one by one and does not name `.factory/`. So a fresh bootstrap copies this repository's factory items into the consumer's tree. The self-host suite showed it: it read `.factory/items/PRD-03/prd.md` inside a fresh bootstrap.

Candidates: strip `.factory/` in bootstrap, as a directory rule beside `KIT_OWN`, which names only files on purpose. Or name each item file in `KIT_OWN`, which then needs an edit per new item. Either way, add a test that a fresh bootstrap holds no `.factory/`.

## Acceptance

- A fresh bootstrap of the kit holds no `.factory/`: the self-host suite's kit-residue check flags any file of the kit's `.factory/` found in the stamped tree.
- A consumer's own `.factory/` (a manifest whose `id:` is not the kit's) survives bootstrap untouched.
- The harness-helpers suite drives the residue check RED on a leaked factory item.
- Built test-first, as PR #813.

Tier: implementer
Confidence: high
Label: none
