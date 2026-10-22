---
id: T-15
type: ticket
title: Restricted reader returns unreadable on posted review and confirm-list comments
parent: agentic-sdlc
class: toil
stage: proposed
created: 2026-10-22
updated: 2026-10-22
deps: []
priority: 3
---

# T-15 · Restricted reader returns unreadable on posted review and confirm-list comments

GitHub issue: #836

Finding (retro F5, Q3): the restricted reader still returns "unreadable" on review and confirm-list comments. Those comments then escalate to the operator, who had delegated the rulings.

Retro: retro-20261022T135553Z

## Evidence

- pr:#810 (human comment 4336226519) and pr:#811 (human comment 6315127856), both 2026-10-21.
- #773 closed this class on 2026-10-14T20:57. This evidence comes after that fix, so the fix did not hold.

## Behaviour

Find why a posted lens review comment, or a posted behaviour confirm-list, yields a return that fails the typed-return check. Likely causes are a span across a glyph, non-ASCII text, or a count mismatch. Fix the reader's prompt rules or the check so such comments return a readable return.

## Acceptance

- The typed-return suite gains fixtures: a posted lens review comment, and a posted behaviour confirm-list, each in the shape the kit itself posts.
- Each fixture is RED before the fix, and each asserts the return passes the vocab.sh shape check after it.

Tier: implementer
Confidence: medium
Class: toil
Label: ready-for-agent
