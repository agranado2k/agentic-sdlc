---
id: PRD-05
type: prd
title: PRD scenarios as use cases
parent: D-01
stage: approved
created: 2026-10-20
updated: 2026-10-21
approved_by: "agranado"
approved_at: 2026-10-21
---

# PRD-05 · PRD scenarios as use cases

## 1. Objective

Have `/to-prd` write a PRD's scenarios as system use cases (an actor, a goal, numbered main-flow
steps and numbered extensions), and have each requirement cite the steps it checks. The flows
are then complete, and each requirement can be traced to the step that needs it.

Today the Scenarios section is "a numbered walkthrough, actor, action, what they see". It has no
goal and no place for the branches: the refusal, the missing input, the second path. So
requirements for the unwanted cases (`IF … THEN`) often serve no written scenario, and nothing
links a requirement back to a flow. The software factory has written its PRDs this way since its
PRD-05, and its D-03 Q13 decided that the template change belongs upstream (Q18).

The test of done: `/to-prd`'s template shows a `UC1` with an actor, a goal, a main flow and a
`2a` extension, and an EARS line ending `[UC1 2a]`. `/to-tickets` reads each use case's main
flow as a candidate tracer bullet.

## 2. Users and scenarios

**U1 — the author of a PRD**, running `/to-prd`. **U2 — `/to-tickets`**, cutting the PRD.

Stories:

1. As an author, I want a shape that asks for the branches of each flow, so that the unwanted
   cases are written before anyone builds them.
2. As `/to-tickets`, I want each requirement to name its steps, so that a slice's tickets cover
   the steps of a flow together.

**UC1 — Write a PRD in use cases.** Actor: an author running `/to-prd` on a grilled plan for
saved views.
1. The template's Scenarios section asks for `UC<n> — <name>. Actor: … Goal: …`, numbered steps,
   and `Extensions:` numbered from their step.
2. The author writes `UC1 — Share a saved view`, four steps, and `3a. The link has expired`.
3. Each requirement ends with the steps it checks: `R3. IF the link has expired, THEN … [UC1
   3a]`.

Extensions:
- 3a. A requirement no step reaches, such as a schema rule, carries no brackets. That is
  allowed, and the coverage check is unchanged.

**UC2 — Cut tickets from use cases.** Actor: `/to-tickets` on that PRD.
1. It reads each use case's main flow as a candidate tracer bullet, as it reads a scenario
   today.
2. It sorts each extension's requirements onto the slice that builds the extension's step, or a
   later one.

## 3. Model

Scenarios become use cases. The rest of the template is unchanged: User Stories stay the *why*,
and Requirements stay EARS-lite, with an optional `[UC<n> <step>…]` suffix.

## 4. Rules

Area: process

Deltas against `docs/specs/process.md`, numbered after PRD-04's process/R29 to R32.

### ADDED

process/R33. `/to-prd`'s template SHALL write each scenario as a use case: `UC<n>`, a name, an actor, a goal, a numbered main flow, and extensions numbered from the step they branch from (`2a`). [UC1 1, 2]
process/R34. `/to-prd` SHALL end each requirement a step checks with the steps it checks in brackets, as in `[UC1 3a]`, and MAY leave the brackets off a requirement no step reaches. [UC1 3, 3a]
process/R35. `/to-tickets` SHALL read each use case's main flow as a candidate tracer bullet. [UC2 1]
process/R36. A PRD written before this change SHALL keep its walkthrough scenarios, and no check SHALL refuse them.

## 5. Slices (vertical, demoable, in order)

**Slice 1 — the template and its reader.**
- *Covers:* process/R33, R34, R35, R36.
- *Accept:*
  - Suites assert the template's use-case shape and the bracket form in `/to-prd`, and the
    reading rule in `/to-tickets`.

## 6. Non-goals (this PRD)

- **Rewriting existing PRDs** — *never*: they stay as written (R36).
- **A gate that every requirement cites a step** — *later*: reopen if `/retro` finds
  requirements nobody's flow needed.

## 7. Technical constraints

Skill text, the template, and suites only.

## 8. Decisions recorded for this PRD

- The software factory's D-03 Q13, overridden from leaving the template alone, and Q18.

## 10. Dogfood plan

One ticket. The software factory's own PRD template (its `factory new prd` skeleton) is that
repository's change, not this one.
