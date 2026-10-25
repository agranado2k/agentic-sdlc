# ADR-0037: The ticket contract carries Risk:, Risk-confidence: and Test-tier:, and a PR carries a check table

- **Status**: Accepted
- **Date**: 2026-10-25
- **Deciders**: the planner session for #869, under the operator's delegation of rulings (ADR-0016); the contract itself was settled with the software factory's D-08 session on 2026-10-23 (PRD-07 §8); the merge of its pull request is the operator's yes
- **Supersedes / amends**: —
- **Superseded by**: —

## Context and problem statement

PRD-07 (factory item D-02) gives a ticket two new stamps and a pull request
one new block. A ticket says how risky its change is (`Risk:`) and which tier
of test checks each requirement it covers (`Test-tier:`). The PR the chain
opens then shows, per covered requirement, the tier that checked it, the
result and the evidence (the **check table**). Today a PR says "tests pass",
and nothing ties that claim to the requirement ids on the ticket's `Covers:`
line (ADR-0012).

The software factory, a planner outside the kit, stamps tickets the kit's
chain builds. Its PRD 3 starts on the tag of the release that fixes these
words. Until a kit record fixes them, the D-02 and D-08 sessions treat them
as drafts. Each one is expensive to reverse once a second planner stamps
against it. So this record fixes the grammars, who may write which reason,
how a missing `Risk:` line is read, and the check table's shape. The check
table itself is written in a later slice.

## Decision drivers

- One reading for every reader. A ticket body is untrusted (the root
  manual's trust boundary), so every value is checked by
  `scripts/vocab.sh` before it reaches a command. The stamp reader prints
  only lines the checker passed.
- The checker's two load rules hold for every new token: the shape
  `[a-z][a-z0-9-]*`, and no token carries its answer in its spelling.
- Words a later rule writes must not be writable now. The risk rule (K3) is
  the one writer of the reasons that record what it learned.
- Keep the release thin. Every other K4 ticket and the factory's next PRD
  wait on this tag.

## Considered options

1. **New kinds of field in the checker, held as policy data** *(chosen)*.
   `Risk:` is a qualified field and `Test-tier:` a keyed field, declared in
   `scripts/vocab.config.sh` the way the query field is.
2. **One closed token per combination** (`high-security`, `R41-suite`):
   rejected. The tier and the id would be fused into one word, a requirement
   id is no token at all, and every new reason would multiply the list.
3. **A second `Confidence:` line for the risk**: rejected. A body's one
   `Confidence:` line is the tier's (`/to-tickets` rule 14), and the checker
   refuses a field given two values.
4. **The stamp reader writes `Risk: high unclear` when the line is
   missing**: rejected. A line the planner never wrote must not look as if it
   did, and no reader acts on risk until K3.

## Decision outcome

Chosen: **new kinds of field in the checker, held as policy data**.

1. **`Risk:` is one line, a qualified field.** Its value is a level token
   and, for the levels the policy marks, exactly one reason token. As
   shipped: `low` stands alone, and `high` takes one of `irreversible`,
   `security`, `invisible`, `shared-layer`, `unclear`, `unlearned`,
   `outward`. `Risk: high`, `Risk: low security` and two reasons are
   refused, each naming the field `risk`. The policy names the levels
   (`VOCAB_RISK`), the levels that take a reason (`VOCAB_RISK_QUALIFIED`),
   the reasons (`VOCAB_RISK_REASONS`) and the reserved ones
   (`VOCAB_RISK_RESERVED`).
2. **The reserved reasons have one writer.** `unlearned` and `outward` are
   the risk rule's alone. The checker refuses them unless its caller
   declares itself the risk rule with `--writer risk-rule`. The default
   writer is `planner`. The writer is a command-line flag and never the
   environment, so no caller inherits it. The stamp reader never passes it,
   so a ticket, a stamp or a factory line can never name a reserved reason.
3. **A missing `Risk:` line is read as `high unclear` by every reader that
   acts on risk.** It is never written in: the stamp reader prints no `Risk:`
   line for a ticket that carries none.
4. **`Risk-confidence:` is its own closed field**, `low` `medium` `high`,
   spelled exactly `risk-confidence`. The body's one `Confidence:` line stays
   the tier's.
5. **`Test-tier:` is a keyed field.** Its value is a requirement id, then one
   of `unit` `suite` `e2e` `manual`. The id is held to the requirement
   library's bounded grammar (`scripts/requirement.lib.sh`, beside the
   checker): `R<n>` or `<area>/R<n>`, the area at most 32 characters, n from
   1 and at most 6 digits. The checker holds only the tokens and never the
   id's meaning. The line repeats once per id. The same id with two tiers is
   refused, and the same id with the same tier is one answer. Whether each
   `Covers:` id has exactly one `Test-tier:` line is the coverage check's
   question, not the checker's.
6. **Two tokens a PR carries are vocabulary fields too**: `result` (`pass`,
   `fail`, `skipped`), a check-table row's, and `scope` (`inside`,
   `outward`), an unspecified item's. The scope rule is a later record's.
7. **The line bounds are published policy**, never hard-coded: at most 8
   lines of any one stamp key (`VOCAB_BOUND`), and 32 `Test-tier:` lines
   (`VOCAB_BOUNDS='test-tier=32'`). `sh scripts/vocab.sh fields` prints them
   as `bound:` lines, the stamp reader enforces them with exit 5, and a
   planner outside the kit reads them from the same file. A policy that
   publishes none leaves the stamp reader at its own 8 for every key.
8. **The stamp reader lifts `Covers:` with the contract's lines**, and holds
   it to the coverage check's grammar itself: a comma-separated list of
   bounded ids, or `none (prefactor)`, `none (open-issue)` or `none
   (release)`. Without the requirement library it fails closed (exit 3).
9. **The check table's shape**, written into the PR body by `/implement`
   alone, above the `<!-- explain-diff-appendix -->` marker:
   - a `<!-- check-table -->` marker line first, then the exact header
     `| Requirement | Test tier | Result | Evidence |` and a separator row;
   - rows run to the first line that does not open with `|`, one row per
     covered id, at most **64 rows**;
   - `Requirement` holds a bounded id, `Test tier` a test-tier token (the
     ticket's stamp for that id where it carries one), `Result` a result
     token;
   - `Evidence` is one of three things: `<path>::<test>@<sha>`, the path and
     the test name in the plain set (letters, digits, `.`, `/`, `_`, `-`)
     and the sha 7 to 40 hex digits; an `https://` URL in the plain set plus
     `:`, `#`, `?`, `=`, `&` and `%`, at most 200 characters; or `-`, only on
     a `skipped` row. A `manual` row no human has checked reads `skipped`
     with the evidence `-`.
10. **Explicit non-goals**: acting on risk (the risk rule, holding a PR, the
    low-risk lane — K3, K5); `/to-tickets` stamping `Risk:` or
    `Test-tier:`; the check-table reader and its exit codes (a later slice,
    a release of its own); reading the policy from the base branch (K2).

## Consequences

- **Good**: the factory and the kit stamp the same words, checked at one
  seam. A reserved reason cannot be forged by a ticket. The bound a
  ticket is held to is read, not guessed.
- **Bad / trade-off**: a consumer whose own `scripts/vocab.config.sh`
  predates this release holds none of the five new fields, because a policy
  file that is found is the whole policy. Its stamp reader drops the new
  lines as undeclared until the consumer adds them (`UPDATING.md` says so).
- **Neutral**: `fields` gains `(qualified)`, `(keyed)` and `bound` lines.
  Readers that read one field's line by its prefix are unaffected.
- **Honest limitation**: the writer flag is a declaration, not an identity.
  Any caller that types `--writer risk-rule` is believed. What holds the
  line is that no shipped reader of a ticket passes it, and
  `tests/stamp.test.sh` shows the stamp reader cannot be made to.

## More information

- Implemented in: #869 (PRD-07 slice 1, process/R38 to R44).
- Held by `tests/vocab.test.sh` (the Risk: and Test-tier: sections),
  `tests/vocab-policy.test.sh` section 13 and `tests/stamp.test.sh` (the
  process/R42 and R43 sections).
- Related: ADR-0012 (ids and `Covers:`), ADR-0015 and ADR-0025 (a release is
  bumped and tagged), ADR-0033 (one shared-layer ticket per frontier),
  ADR-0016 (the session's delegated rulings).
