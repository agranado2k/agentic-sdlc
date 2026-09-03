# Architecture Decision Records

Each ADR captures **one** architectural decision for agentic-sdlc, in
[MADR format](https://adr.github.io/madr/). The record is the contract; the
development chronology lives in `docs/diary.md`.

Copy `NNNN-template.md` to start a new one.

## Index

<!--
One row per ADR, in numeric order. The Status column carries the *live* status
plus the date it reached it, and any supersession/amendment note — so this table
alone answers "what is currently binding?" without opening 40 files.
-->

| # | Title | Status |
|---|---|---|
| [0001](0001-the-kit-self-hosts-its-own-constitution.md) | The kit self-hosts its own constitution | Accepted 2026-08-27 |
| [0002](0002-strategic-means-ousterhout.md) | "Strategic" means Ousterhout's strategic programming; Evans's work is the context map | Accepted 2026-09-02 |
| [0003](0003-the-kit-maps-its-own-tiers.md) | The kit carries its own tier-to-model mapping, and never ships it | Accepted 2026-09-02 — supersedes the diary-recorded decision of 2026-08-27 below |
| [0004](0004-the-root-manual-is-the-kits-local-article.md) | The kit's root manual is also its local article, budgeted at 350 lines | Accepted 2026-09-02 |

## Conventions

- **File name**: `NNNN-short-kebab-title.md`, zero-padded to four digits.
  Numbers are never reused, even for a rejected ADR.
- **Status values**: `Proposed` · `Accepted` · `Rejected` · `Deprecated` ·
  `Superseded by NNNN`.
- **The "Decision outcome" section is the contract.** Implementation detail and
  historical context go in `More information` at the bottom, kept short.
- **When a decision is reversed or revised, do NOT edit the old ADR.** Write a
  new one and set the old one's status to `Superseded by NNNN`. An amendment
  that only *narrows or clarifies* the same decision may be recorded in place,
  dated and labelled as an amendment — but a reversal never is.
- **Write the ADR when the decision is made**, not when the code lands. An ADR
  written after the fact documents a rationalization, not a decision.
- **One decision per record.** If the title needs an "and", it is two ADRs.

## Decisions recorded in the diary, not as ADRs

<!--
Some material decisions do not warrant a standalone record but are still binding
policy. List them here with a date, so "it is not in docs/adr/" never means "it
was never decided". If one grows consequential enough, promote it to an ADR and
leave a back-reference in the diary entry.
-->

- **2026-08-27 — the kit's `scripts/agents.config.sh` stays unmapped.** The kit
  names no model anywhere, including in its own copy of the tier mapping. Every
  tier here inherits the session's model and the resolver warns once, which is
  the state a consumer starts in too. **Superseded by ADR-0003** (2026-09-02):
  the shipped config stays empty, but the kit carries a kit-only mapping of its
  own, reached through the resolver's config seam and never shipped.
