## What & why

<!--
What this PR does and the intent behind it. Link the issue, PRD, and any ADR it
implements or amends.

One vertical slice per PR (shared invariant §2). If you cannot answer "what can
I demo when this lands?", the slice is wrong.
-->

## Check table

<!--
One row per requirement the ticket's `Covers:` line lists: the test tier
that checked it, the result (`pass`, `fail` or `skipped`) and the evidence
(`<path>::<test>@<commit>`, an `https://` URL, or `-` on a `skipped` row).
A `manual` row no human has checked reads `skipped` with `-`. Keep the
marker line and the header exactly as they are; `sh scripts/check-table.sh`
reads the table through them. A ticket that covers no requirement leaves
the table with no rows.
-->

<!-- check-table -->
| Requirement | Test tier | Result | Evidence |
| --- | --- | --- | --- |

## Decision log

<!--
One row per open point the iteration loop decided itself because its effect
stays inside the change: a review's UNSPECIFIED item marked `scope: inside`.
The loop creates the log with its first row, a decision-log marker comment
line and the header `| Decision | Surface | What was decided | Why |`, under
this heading. A row's id, `D-<n>`, is numbered from 1 and never renumbered;
a row a later review marked outward is struck, its id kept, and the item is
held for you. Outward items are never logged here. Read the log before
merging; no skill reads its prose back.
-->

## Checklist

- [ ] **One slice** — this PR does one thing; refactoring and behavior change are
      not mixed in a single commit (shared invariant §10)
- [ ] **Tests first** — every behavior change is paired with a test that fails
      without it (shared invariant §3); the suite is green
- [ ] **Docs match reality** — diary / ADR / glossary updated where this changed
      what they claim; the docs gate (`sh scripts/check.sh`) is green
- [ ] **Decisions recorded** — any architectural choice made here has an ADR in
      `docs/adr/` and a row in its `INDEX.md`
- [ ] **Conventional Commits**, commits curated before review

## Behavior findings for a human

<!--
Shared invariant §5: standards findings and behavior findings are never merged.
This section is the human confirm-list — the questions a diff alone cannot
answer. Be specific; "please review carefully" is not an item.

  - Did the semantics of X change for existing callers?
  - Is trade-off Y acceptable?
  - Is the new default the right one?

Write "none" if there genuinely are none, rather than deleting the heading.
-->

## Notes for review

<!--
Where to start reading, what is deliberately out of scope, known follow-ups, and
anything that looks wrong but is not.
-->

---

<!--
Shared invariant §7: autonomy never includes merge. An agent may take this PR to
one click away from landing and stops there — the merge is a human action with a
human's name on it.
-->
