---
id: T-24
type: ticket
title: A stop priced past a half-written transcript line records data.partial
parent: agentic-sdlc
class: toil
stage: done
created: 2026-10-23
updated: 2026-10-25
deps: []
priority: 3
links:
  pr: "#868"
approved_by: "agranado"
approved_at: 2026-10-25
review:
  outcome: approved
  commit: "6acaad1"
  by: "review-pr on #868"
  at: 2026-10-25
qa:
  outcome: pass
  by: "land.kit.sh (#868 landed, main workflows green)"
  at: 2026-10-25
---

# T-24 · A stop priced past a half-written transcript line records data.partial

GitHub issue: #862

Toil from the 2026-10-23 wave: since #848, a subagent stop whose transcript ends in a half-written line is still priced, from the lines before it. The stop's event does not say a line was skipped, so /retro cannot tell a fully priced stop from one priced short, nor count how often it happens.

When the usage reader skips an unterminated last line, the stop's trace event records `data.partial=yes`; a fully read transcript records no such key. /retro's spend question counts partial stops in its window and names them beside the unpriced ones.

The usage reader is a shared-layer file, so this is a release: VERSION bump, UPDATING.md entry, the docs-demo transcripts re-captured, and the tag on the merge commit (ADR-0025).

## Acceptance
- The hook suite: a transcript with a half-written last line yields a stop event with `data.partial=yes`; a whole transcript yields none.
- The retro suite holds the spend question's count of partial stops.
- The release is complete: the bump, the UPDATING entry, re-captured demos.

Class: toil
Tier: implementer
Confidence: high
