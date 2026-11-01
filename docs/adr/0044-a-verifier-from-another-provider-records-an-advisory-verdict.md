# ADR-0044: A verifier from another provider reviews each PR head and records an advisory verdict of its own kind

- **Status**: Accepted
- **Date**: 2026-11-01
- **Deciders**: the implementer session for #939 (PRD-13 slice 1, T-76), under the operator's delegation of rulings; PRD-13 was approved by the operator, its walk settled on 2026-10-31 (#957), and the merge of this record's pull request is the operator's yes
- **Supersedes / amends**: amends ADR-0024 clause 1, which gains the kinds `verify.verdict` and `finding.verify` and a `V-` id on a raise and a triage; recorded as a new record because ADR-0024 is at its amendment cap (ADR-0021 clause 5), as ADR-0034, ADR-0036 and ADR-0040 were
- **Superseded by**: —

## Context and problem statement

Every review this kit runs on its own diffs comes from one vendor's models.
ADR-0027 already moves a review off the author's family, but a family of the
same provider shares more of the author's training than a model of another
provider does. Nothing in the trace says what a second provider would have
caught that the kit's review missed, or whether the findings the kit's review
raised were real. D-08's C5 asks exactly that: a critic whose object is the
reviewer's findings.

PRD-13 adds a **verifier**: a reviewer from another provider, run on each PR
head beside `/review-pr`, with the review worker's contract, that also judges
the check table's `pass` rows and each finding the kit's review raised. This
record fixes what the verifier is, where its model comes from, what it may
decide, and the trace's contract with it. The resolver, the dispatcher, the
broker and the readers that carry it out are PRD-13's later slices.

## Decision drivers

- No existing reader may count the verifier's verdict as the kit's review by
  accident. The landing script counts any Axis-1 `review.verdict` that is not
  blocked (ADR-0032).
- The lenses' earned record (ADR-0036) must measure the kit's own review
  alone.
- A missing verifier must be visible to `/retro`, not silent.
- A new kind is a clause 1 change, and ADR-0024 is at its amendment cap.

## Considered options

1. **A new kind, `verify.verdict`, and a second, `finding.verify`** *(chosen)*
   — every reader that exists today ignores both, so the change fails closed.
2. **`review.verdict` with a role key** — rejected: the landing script and
   every reader that counts a review would count the verifier's verdict unless
   each learned to skip the key. One forgotten reader fails open.
3. **The verifier's finding verdicts as `finding.triage`** — rejected: a
   triage labels a finding, and the earned record counts labels. The verifier
   would then decide whether the kit's finding held up, which makes it a judge
   of the review it is meant only to advise on.

## Decision outcome

Chosen: **option 1**.

1. **The verifier** is a reviewer-tier spawn in the `cross-provider` domain.
   It reviews one PR head on both axes with the review worker's contract (one
   contract per task kind, never one per provider, so comparing two vendors
   measures the models and not the prompts), judges each `pass` row of the
   PR's check table, and returns a verdict on each finding the kit's review
   raised at that head.
2. **Its model is resolved by a walk, failing closed.** First a model whose
   declared **provider** differs from the author's; else a model of the
   author's provider and another family (ADR-0027's test, over the reviewer
   tier's ordered walk, ADR-0013); else none. A provider is declared per
   agent harness in the agents policy, and a model's provider is its agent
   harness's. An author whose provider is not declared gets no verifier. No
   verifier resolved, or a spawn that still fails after one re-resolve, is
   recorded as `unavailable`, never skipped.
3. **It is advisory.** Its verdict is never the review a landing requires:
   ADR-0032 does not move, and the kit's own Axis-1 `review.verdict` is still
   that review. It decides nothing — no finding is rejected and no PR held on
   its word — with one exception owned elsewhere: PRD-10's low-risk lane
   lands a PR only on the verifier's `pass` at its head (operator,
   2026-10-31).
4. **The trace kind `verify.verdict`** records it, on `pr:#<N>`. Its outcomes
   are `pass`, `blocked` and `unavailable`; the outcome is required, and any
   other is refused, exit 2, writing nothing. A `pass` or `blocked` carries
   `data.reviewed`, the head commit it reviewed (40 hex digits), and
   `data.provider`, its model's provider (a token: a lowercase letter, then
   lowercase letters, digits, `.`, `_` or `-`); missing or malformed, the line
   is refused the same way. An `unavailable` needs neither. `blocked` means a
   CRITICAL or HIGH finding or a disputed row, `pass` otherwise.
5. **The verifier's findings carry a `V-` id**: `V-` before a lens finding id
   (`V-H-1`), on `finding.raise` and on `finding.triage`. Triage pairs with a
   finding by id within a PR, so an unprefixed `H-1` from the verifier and
   `H-1` from a lens would be one finding. A verifier's finding is triaged
   as a bot's (`data.source=bot`), so a local triage still takes a lens id
   only. Every id the trace refused before it still refuses. A `V-` raise counts toward no review area of the earned
   record; the verifier's own row is a later slice's.
6. **The trace kind `finding.verify`** records the verifier's verdict on one
   finding the kit's review raised. Its outcomes are `confirmed` and
   `disputed`, required; it carries the lens finding's `data.id` (never a
   `V-` id: the verifier does not judge its own findings) and `data.where`,
   the evidence's `<path>:<line>` at the head. Anything else is refused,
   exit 2, writing nothing. **It is never a `finding.triage`** (D-08's C5,
   PRD-13 §8): no reader of triage counts it, so it labels no finding, and
   post-merge outcomes and triage stay the only labels. A disputed finding
   never makes the verdict `blocked`.

## Consequences

- Good: every reader that exists today ignores the verifier, so landing the
  kinds before their writers changes no count.
- Good: an `unavailable` verdict makes a missing verifier a fact `/retro` can
  count.
- Bad: two more kinds in the closed vocabulary, and a consumer whose own
  readers count `finding.raise` by id must expect `V-` ids once a verifier
  runs.
- Neutral: on the walk's second rung the verifier can be the same model as
  the kit's review of that diff; PRD-13 records the rung so `/retro` can tell.

## More information

- PRD-13 (`.factory/items/PRD-13/prd.md`), slice 1; ticket #939 (T-76); the
  requirements are `docs/specs/runtime.md` R200, R201, R202 and R221.
- Cited: ADR-0009 (the worker is offline, the broker acts), ADR-0013, ADR-0020
  and ADR-0027 (the walk and the family rule), ADR-0032 (the landing's review
  check), ADR-0036 (the earned record).
- Held by `tests/trace.test.sh` section 22 (the kind table, row for row) and
  section 44 (the outcomes, the required keys, the `V-` ids, and a `V-` raise
  counted toward no review area).
