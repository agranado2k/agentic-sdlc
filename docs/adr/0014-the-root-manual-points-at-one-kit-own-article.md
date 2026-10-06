# ADR-0014: The root manual's read-on-demand elaboration moves to one kit-own article it points at

- **Status**: Accepted
- **Date**: 2026-10-06
- **Deciders**: the implementer session for #489, on the operator's (Arthur Granado) standing delegation of rulings
- **Supersedes / amends**: amends ADR-0004 clauses 1 and 4 — the root is no longer the kit's *only* article of its own, and the tiers section no longer stays whole in it; the 350-line budget (clause 2) and its check stand unchanged
- **Superseded by**: —

## Context and problem statement

The housekeeping pass of 2026-10-02 measured the root manual at exactly
350 lines — the budget ADR-0004 records, up 16 from the 334-line baseline it
was set against. The manual tells every landing to add a quick-reference row
for each skill, script and gate the repo gains, so the next landing was going
to turn the self-host suite red. ADR-0004 clause 3 already names the two
ways out: split into a kit-own article, or supersede the record with a new
budget.

The same budget was also asserted twice — the self-host suite reads it from
ADR-0004, and the root-guard suite carried a literal copy — so the number
was known in two places, one of which would rot the day the record changed.

## Decision drivers

- Shared invariant §11: the root is re-read on every request; elaboration
  read on demand belongs in an article it points at.
- ADR-0004 clause 3 makes growth past the budget a decision, never a silent
  line, and a raised budget is the one answer that buys nothing back.
- Every hard rule and the command map stay in the root — the manual's own
  shape claim.
- One home per rule: a moved paragraph is deleted from the root, not copied.

## Considered options

1. **Move the tier practice to one kit-own article** *(chosen)* — the
   candidate ADR-0004 itself named. The root keeps the four tier names, the
   no-model rule, hard rule 10 and the reviewer spawn command; the table,
   the shipped-empty mapping and its kit twin, the wrapper's explanation,
   the policy and the domain axis move.
2. **Supersede ADR-0004 with a larger budget** — rejected: it pays more on
   every request to avoid one move the record already anticipated.
3. **Trim prose in place** — not rejected, not enough: tightening buys a few
   lines, and the next wave of rows spends them.

## Decision outcome

Chosen: **one kit-own article, pointed at from the root**.

1. The kit's on-demand elaboration lives in **`docs/capability-tiers.md`**,
   a kit-own file: `bootstrap.sh`'s kit-own list strips it from a consumer's
   tree, as it strips this record, and nothing the kit ships names it. It
   sits under `docs/`, not `constitution/`, so the manual's claim that the
   kit has no `local-*` article stays true and the article-layer rules that
   hold the shipped articles do not apply to it.
2. The root manual names the article in its article-layer section and in
   the section the text left. A later move of read-on-demand elaboration
   goes to the same article, or to a sibling named the same way and in the
   same list — never to a file the root does not point at.
3. What stays in the root: every hard rule, the command map, the four tier
   names, the rule that no shipped file names a model, and the one command
   a session types before spawning a reviewer.
4. The 350-line budget stands, read from ADR-0004 by
   `tests/self-host.test.sh` alone. No other suite re-measures the root;
   the self-host suite fails if one does.

## Consequences

- **Good**: the root drops from 350 to under 300 lines, with room for the
  next quick-reference rows; the budget is one number in one record checked
  by one suite.
- **Bad / trade-off**: a session that spawns now reads one more file, and
  ADR-0004's "fourth home" cost is paid: one more kit-own file for bootstrap
  to strip.
- **Neutral**: the policy paragraph's duplication with the kit-only config's
  header (ADR-0004 option 3) moves with it, still a housekeeping finding.

## More information

- Implemented in: #489.
- Related: ADR-0004 (the budget, amended here); ADR-0003 (the kit's own
  mapping, which the moved text explains); shared invariant §11.
