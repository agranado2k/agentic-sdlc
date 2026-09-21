---
name: to-prd
description: Turn the current conversation context into a PRD and publish it to the project issue tracker. Use when user wants to create a PRD from the current context.
---

This skill takes the current conversation context and codebase understanding and produces a PRD. Do NOT interview the user — just synthesize what you already know. (If the requirements are not settled yet, that is `/grill-me` or `/grill-with-docs`, not this.)

## Before you start

- **The tracker.** Publish to whatever issue tracker the project uses; the root `AGENTS.md` or `constitution/local-workflow.md` names it. If neither does, ask once and then record the answer there rather than in this file.
- **The autonomy label.** Shared invariant §6: every ticket carries an explicit autonomy label, and ambiguity resolves to human-in-the-loop. This kit's mechanism is a single `ready-for-agent` label — its presence means an agent may take the work solo, its absence means a human stays in the loop. There is no literal `HITL` label; absence *is* the signal.

## Process

1. Explore the repo to understand the current state of the codebase, if you haven't already. Use `docs/domain-glossary.md` vocabulary throughout the PRD, and respect the decision records in `docs/adr/` that cover the area you're touching.

2. Sketch out the seams at which you're going to test the feature. Existing seams should be preferred to new ones. Use the highest seam possible. If new seams are needed, propose them at the highest point you can.

Check with the user that these seams match their expectations.

3. Write the PRD using the template below, then **reread it as a stranger.** The PRD is read by sessions that hold none of this conversation (shared invariant §4). Whatever you would tell a teammate before they read it belongs in the Objective and the Problem Statement, not in your head; if a section only makes sense with the chat open, it is not finished.

4. Publish it to the project issue tracker with the `ready-for-agent` label if the work is mechanical with a checkable definition of done — no additional triage needed.

<prd-template>

## Objective

The objective is one sentence, in plain language and the glossary's vocabulary, that any stakeholder understands: what this changes and for whom. It is the line every ticket quotes for context and the handle the diary uses, so it is the first line of the PRD, before the problem is explained.

## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A LONG, numbered list of user stories. Each user story should be in the format of:

1. As an <actor>, I want a <feature>, so that <benefit>

<user-story-example>
1. As a mobile bank customer, I want to see balance on my accounts, so that I can make better informed decisions about my spending
</user-story-example>

This list of user stories should be extremely extensive and cover all aspects of the feature.

## Scenarios

Where a story is abstract, a numbered walkthrough of the finished system in use — actor, action, what they see — step by step, with concrete names rather than placeholders. One per major story.

<scenario-example>
1. Bob creates a custom report in his dashboard.
2. Bob opens the menu and clicks "Share > as URL".
3. Bob emails the URL to his teammate, Charlie.
4. Charlie clicks the link and sees an exact copy of Bob's report, read-only.
</scenario-example>

Each scenario is a demo script: `/to-tickets` reads them as the candidate tracer bullets, so a scenario that cannot be walked through is a story the PRD has not finished thinking about.

## Implementation Decisions

Record a decision here when the **penalty for being wrong** is high — an interface, a storage shape, a seam, a module boundary: anything expensive to reverse once sessions have built on it. A decision that is cheap to change later belongs to the implementing session, not the PRD; pinning it here writes the implementation during design. The file-path rule below is one consequence of this.

A list of implementation decisions that were made. This can include:

- The modules that will be built/modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.

Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it within the relevant decision and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

## Testing Decisions

A list of testing decisions that were made. Include:

- A description of what makes a good test (only test external behavior, not implementation details)
- Which modules will be tested
- Prior art for the tests (i.e. similar types of tests in the codebase)
- Every quality word in this PRD — fast, small, robust, responsive — restated as a number a test can assert, or dropped

## Alternatives Considered

A few brief lines per strong alternative the grilling rejected, and why it lost. Only the ones a later session would plausibly propose again — not every idea, which is overkill. A decision that outlives this feature goes to `docs/adr/` and is linked from here, not repeated.

## Out of Scope

One line per item, each with its reason, and each marked *later* (deferred — say what would reopen it) or *never* (rejected). A bare list makes a fresh session guess which is which.

## Open Issues

Anything the grilling left unresolved, each as three lines: the problem, the options seen, and the immediate next step — a `/prototype` spike, a question to a named person, or a `planner` ticket. When one is resolved, move it out of here and into Implementation Decisions (or a decision record); the tracker keeps the history. An open issue whose answer would shape tickets blocks `/to-tickets` — see that skill's rule.

## Further Notes

Any further notes about the feature.

</prd-template>

Scenarios, Alternatives Considered and Open Issues are **omitted when empty** — never written as "none" or "N/A". A section is a menu item, not a form field.

## What happens next

A PRD that spans more than one context window goes through `/to-tickets` before any code is written (shared invariant §1). One that fits a single window can go straight to `/implement`.

---

*Adapted from `engineering/to-prd` in [mattpocock/skills](https://github.com/mattpocock/skills) — MIT, see `.agents/skills/LICENSE-mattpocock-skills.md`. Upstream expects a separate setup skill to have supplied the tracker and label vocabulary; here that vocabulary is the kit's own autonomy-label mechanism. The Objective, Scenarios, Alternatives Considered and Open Issues sections, the penalty-for-being-wrong filter and the stranger reread follow Michael Lynch's [How to Write an Effective Software Design Document](https://refactoringenglish.com/excerpts/write-an-effective-design-doc).*
