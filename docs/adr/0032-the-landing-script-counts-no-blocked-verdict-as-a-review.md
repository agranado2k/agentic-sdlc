# ADR-0032: The landing script counts no blocked verdict as a review

- **Status**: Accepted
- **Date**: 2026-10-22
- **Deciders**: the implementer session for #816, on the operator's standing delegation of rulings; the merge of its pull request is the operator's yes
- **Supersedes / amends**: ADR-0019's amendment of 2026-10-10 (#673), clause 2 — the "any axis and any outcome" a review at the head was counted on
- **Superseded by**: —

## Context and problem statement

ADR-0019's #673 amendment made the landing script (`scripts/land.kit.sh`)
refuse a PR with no `review.verdict` at its head commit, and counted any
verdict there — any axis, any outcome. A `blocked` verdict counted on purpose:
what the review found was the operator's read on the PR.

#808 (v0.82.0) gave `/review-pr` a branch for a review in which no lens ran
and no single-reviewer pass returned: it records
`review.verdict outcome=blocked data.axis=1 data.lenses=0 reason='no lens ran'`,
and its Axis-2 verdict beside it as usual. Nothing audited the diff, yet the
landing script reads two verdicts at the head and lands the PR — the very
degraded review #673 was written to stop. Found by #808's own review (its
M-1), deferred there as outside that ticket, and filed as #816.

## Decision drivers

- A review that audited nothing must not satisfy a check whose purpose is
  that something audited the head.
- A single-reviewer pass is a real review: it records `data.lenses=0` too,
  with `data.agent=single-reviewer`, and must keep counting.
- The check reads the trace's envelope and fixed data keys, never a free-text
  `reason`.
- An exception stays one flag, `--no-review '<reason>'`, as ADR-0019 decided.

## Considered options

1. **Count an Axis-1 verdict on any outcome but `blocked`** *(chosen)*
2. **Exclude only the no-lens shape** — `blocked` with `data.lenses=0` and
   the reason `no lens ran` — rejected: it recognises the case by a free-text
   reason, and a single-reviewer pass that blocks carries the same
   `data.lenses=0`, so the data keys alone cannot tell them apart.
3. **Keep counting any verdict and record `data.reviewed=blocked`** —
   rejected: a record the retro reads a week later is ADR-0019's rejected
   option 2 again; the refusal is the check.

## Decision outcome

1. **A review is at the head** when a `review.verdict` on `pr:#<N>` carrying
   `data.axis=1`, on **any outcome but `blocked`**, is stamped at or after the
   head commit's committed date — ADR-0019 clause 2's comparison. This
   replaces the #673 amendment's "any axis and any outcome".
2. **An Axis-2 verdict alone is no review at the head.** The no-lens review
   records one beside its blocked Axis 1, so counting it would land exactly
   that review; and Axis 2 is the behavior confirm-list, not the standards
   audit.
3. **A blocked verdict beside a later pass at the same head counts** — the
   pass is the review. A head whose only Axis-1 verdicts are `blocked` is
   refused like a head with none: exit 2, nothing merged, nothing recorded,
   and the refusal says the verdict it found was blocked.
4. **The override is unchanged**: `--no-review '<reason>'` lands it, and
   `merge.land` records `data.reviewed=no` with the reason as
   `data.no_review`. A blocked review an operator chooses to land over is a
   landing with no review the check can stand on, and the reason says why.
5. Unconfigured, nothing is checked (ADR-0019 clause 5).

## Consequences

- **Good**: a review that ran no lens can no longer land a PR by its mere
  presence in the trace.
- **Bad / trade-off**: a review whose lenses ran and found blocking findings
  now refuses too, where ADR-0019 let it land as the operator's read. Landing
  over such findings takes `--no-review` and a typed reason, which the retro
  can count.
- **Honest limitation**: `data.reviewed=no` does not tell a landing over a
  blocked review from one over no review; the `data.no_review` reason is
  where that difference is written.

## More information

- Built by #816. `tests/land.test.sh` section 14 drives the blocked verdict,
  the no-lens shape with its Axis-2 verdict, an Axis-2 verdict alone, a
  single-reviewer pass at `data.lenses=0`, a blocked verdict beside a pass,
  and the override.
- The script still reads `show` for the same four kinds ADR-0019 names;
  section 15 is unchanged.
