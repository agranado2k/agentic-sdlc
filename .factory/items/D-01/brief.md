---
id: D-01
type: discovery
title: Proposals from the software factory
parent: agentic-sdlc
stage: exploring
created: 2026-10-20
updated: 2026-10-20
---

## Problem

The software factory (`agranado2k/software-factory-suite`) runs this kit's chain on every
ticket. Its D-03 discovery ("Improving the factory") compared the chain with 13 outside sources
and grilled the results (Q1 to Q20, 2026-10-17 and 2026-10-18). Its Q18 decided that
improvements to the kit's skills and scripts go upstream, here, and are not edited into the
consumer's copies, which would drift. This discovery holds those proposals as PRDs.

## Outcome

Each proposal is a PRD here, a delta against this kit's living specs (`process`, `runtime`,
`spend`), ready for `/to-tickets` once the kit's maintainer approves it. The factory then takes
each one through `UPDATING.md` when a release ships it.

## Scope

In:
- the four proposals of the factory's D-03 Q19, in its order;
- the `/retro` measures of Q12, Q17 and Q20 that the kit does not report yet;
- the use-case scenarios of Q13 in `/to-prd`.

Out:
- anything only the factory's own layer or binary needs (its toil lane is its PRD-08);
- the two `/housekeeping` audits of Q19 (rows 5, 24 and 37 of its research), left to the next
  housekeeping pass.

## Children

- PRD-01 A review in which no lens ran is a block (Q19, proposal 1)
- PRD-02 Stop after repeated identical failures (Q19, proposal 2)
- PRD-03 Runs record their context, and `/retro` measures flow and checks learning-loop edits
  (Q19 proposal 3, Q12, Q17, Q20)
- PRD-04 Skills declare their powers, and a subagent's only narrow (Q19, proposal 4)
- PRD-05 PRD scenarios as use cases (Q13)
