# ADR-0004: The kit's root manual is also its local article, budgeted at 350 lines

- **Status**: Accepted
- **Date**: 2026-09-02
- **Deciders**: Arthur Granado (operator), via PRD #124's quiz
- **Supersedes / amends**: amends ADR-0001 §4 in one respect — the records directory holds one more kit-own record, which bootstrap's kit-own list strips
- **Superseded by**: —

## Context and problem statement

The root manual is loaded into every session and re-read on every request;
shared invariant §11 calls its size a budget every request pays. The kit's
root measures 334 lines against the 200-line reference point Osmani names for
an agent file, and the question was whether the capability-tier elaboration
(67 lines) and the kit-only wiring should move to an on-demand article.

The kit is not an ordinary consumer. A consumer's standing instructions are
a root and two or three local articles — engineering, workflow, and product
when the optional skill is installed — that the root points at. The kit ships those articles as templates and has none of
its own — the root manual says so, and the "What this repo is" section is
named as the kit's equivalent. So the kit's root carries what a consumer
splits across three files: orientation, the hard rules, the tier practice
that a consumer's workflow article would hold, and the command map. Measured
against a consumer's root alone it is long; measured against a consumer's
root plus its two articles it is short.

The 67-line tiers section is the one candidate for an article. It exists
because the kit is the only repo where a skill's literal spawn command is
wrong (hard rule 10), and the explanation of why cannot live in the skills,
which ship unstamped.

## Decision drivers

- One home per rule (shared invariant §11): a kit-only article would be a
  fourth home for standing instructions, and a kit-own file for bootstrap to
  strip.
- The manual's own claim, "the kit has no `local-*` article of its own", is
  load-bearing for the templates-stamped and article-reachability rules.
- A budget with no failing check is a claim (hard rule 9).
- The reference point of 200 lines is for a file whose elaboration lives
  elsewhere; the kit's does not.

## Considered options

1. **Keep one root, record the budget, hold it with a check** *(chosen)* —
   the root stays the kit's only local article; its size is capped at 350
   lines by a self-host probe; growth past that is a decision, not a drift.
2. **A kit-only article for the tier practice** — rejected: a new kit-own
   file, a new deletion-list entry, a fourth home for rules, and the loss of
   the manual's "no local article" claim, to move 67 lines that every kit
   session needs anyway (hard rule 10 is the most-tripped rule in the repo).
3. **Trim the tiers section in place** — not rejected, but not this
   decision: tightening prose is ordinary editing under the budget, and the
   section's policy paragraph is duplicated in the kit-only config's header,
   which is a one-home finding for the next pass.

## Decision outcome

Chosen: **one root, a recorded budget, a check**.

1. The kit's root manual is its only local article. It carries what a
   consumer's root and two local articles carry together.
2. Its budget is **350 lines**. The self-host suite fails when the root
   exceeds it, with its own bait.
3. Growth past the budget is a decision: split into a kit-only article and
   supersede this record, or raise the budget here with the reason. Never a
   silent line.
4. The tiers section stays in the root. Its duplication with the kit-only
   config's header is a housekeeping finding, not part of this decision.
5. **Explicit non-goal**: this record says nothing about a consumer's root.
   The template is 281 lines and the consumer's elaboration lives in the
   articles it points at; a consumer's budget is theirs.

## Consequences

- **Good**: the root's size is a rule with a check, and the manual's shape
  claims stay true.
- **Bad / trade-off**: every kit session pays 334 lines on every request,
  about a third more than the reference point; the tiers section is the
  price of hard rule 10.
- **Neutral**: the check is a line count, the bluntest possible instrument;
  it catches growth, not bloat.
- **Honest limitation**: 350 is a number chosen to fit today's root with
  room for one more hard rule. It is not derived from a token budget, and
  a model with a smaller context would want a smaller number.

## More information

- Implemented in: ticket #134 of PRD #124; the housekeeping report of
  2026-09-02, item 1.1.
- Related: shared invariant §11; ADR-0001 (the kit follows its own
  framework); Addy Osmani, "Audit your Agent files" (the 200-line reference).
