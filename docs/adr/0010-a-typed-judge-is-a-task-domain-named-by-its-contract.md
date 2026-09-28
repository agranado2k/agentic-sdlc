# ADR-0010: A typed judge is a task domain named by its contract, in two shapes

- **Status**: Accepted
- **Date**: 2026-09-28
- **Deciders**: Arthur Granado (operator), at PRD #273's synthesis and the quiz that stamped #275; recorded by the `/implement` session for #275
- **Supersedes / amends**: — (stands under ADR-0003: the tier vocabulary stays closed and the kit's own mapping stays kit-only; the judge is the task-domain axis's answer, not a fifth word on the tier axis). Numbered 0010 because 0009 was already taken by the broker record on an open branch (PR #285) when this one was written; numbers are never reused, so neither yields
- **Superseded by**: —

## Context and problem statement

A judgment in the chain — which tier a ticket gets, whether a review comment
is applied or escalated, whether a dogfood step passed — climbs a cost ladder
with two rungs today: a deterministic script where one is possible
(`behavior-delta.sh`, the guards, the gate), otherwise the session's own
model, at the session's price and latency. September 2026 produced a third
rung between them. Models now answer a typed question over a block of state
with a probability per option in tens of milliseconds — the research report
this record rests on (https://view.centaurspec.com/oNa-l6LtDR, revision 5)
counts at least eight open implementations of one contract in eleven days,
several Apache-2.0 and runnable on a laptop, and two leaderboards ranking
them. The kit has no name for that rung: a consumer who wants a cheap judge
for comment triage has nowhere to map one, and the resolver's closed tier
vocabulary (ADR-0003) means a new tier is a manual change, a resolver change
and a release.

The field also split the contract in two while the report was being written.
Most of the entrants **decide**: a readout of probabilities over supplied
options. One — a contrastive ranker — **ranks** supplied candidates by
similarity instead, and its authors measured the difference where it bites.
Used as a verifier of long-horizon agent trajectories ("is this run on
track?"), the ranker with light fine-tuning set the state of the art on two
agent benchmarks (Terminal-Bench 2.1 at 87.6 %, DeepSWE at 81.6 %) while the
decider it was compared against scored **below chance** on the same tasks
(report, section 5, "CLM-8B — a ranker, an action cache, and the verifier
result"; section 7, "A decider as a verifier"). "Which of these options" and
"is this trajectory good" are different judgments, and a model sold for the
first does worse than a coin at the second.

Two rules of this kit constrain the answer before any option is weighed. The
kit names no model anywhere it ships, and its own mapping names one only to
itself (ADR-0003). And shared invariant §5 requires a standards finding to be
verifiable from the diff — so the review verdict needs the whole change and a
reason, which a probability with no rationale cannot supply.

## Decision drivers

- The tier vocabulary is closed (ADR-0003) and a tier is a size of work; a
  typed judge is a medium — what the work is made of — which is what the
  task-domain axis exists to name.
- The kit names no model. A week-old model on an unproven price is the
  fastest-rotting identifier there is, and the seam must work with the
  mapping empty.
- An unmapped domain is a working state that falls back to the tier in
  silence. A project that has not decided must be exactly where it is today.
- The negative has a measurement behind it (section 5), not an assumption.
  Naming the shape at the seam is cheaper than discovering the mismatch in a
  retrospective.
- Shared invariant §5: the review verdict is verifiable from the diff, with a
  reason. Nothing in the typed rung can produce that.

## Considered options

1. **A task domain, `judge`, on the `mechanical` tier, specified by contract
   in two shapes, unmapped by default, declined by the kit's own mapping**
   *(chosen)* — the clauses below.
2. **A fifth tier, `judge`** — rejected: the tier vocabulary is closed by
   ADR-0003 and a tier is a size of work, not a medium; widening it is a
   manual change, a resolver change and a release, for a word that answers
   the wrong question.
3. **One shape only — decide** — rejected: the field ships two contracts,
   and the measurement above is precisely a decider handed a verification.
   A seam that cannot say which shape it answers will be handed the wrong
   one.
4. **Map the domain to a named model in the kit's own policy file** —
   rejected: the kit's own sessions have no judge backend to run, the field
   is weeks old, and the kit-only file is exactly where such a name would
   rot. Declining in a comment records the decision; the resolver's silence
   would not.
5. **Name no seam; let each consumer invent a domain token** — rejected: the
   skills that would spawn a judge must name one token, the way `/implement`
   already names `reviewer self-implemented`, and a token nobody wrote is one
   every consumer spells differently.

## Decision outcome

Chosen: **a task domain, by contract, in two shapes — decide and
rank-or-verify — mapped by nobody the kit ships to**.

1. **`judge` is a task domain on the `mechanical` tier.** It is resolved as
   `mechanical judge` and read from `AGENT_TIER_MECHANICAL_JUDGE`. It is not
   a tier: ADR-0003's four names stand, and the resolver is unchanged — an
   unmapped domain already falls back to its tier in silence, which is the
   whole mechanism this record needs.
2. **It is specified by its contract, never by a vendor**: state and typed
   questions in, typed answers with per-option probabilities out. Any backend
   that answers that contract fits the seam; the report's entrants are
   possible mappings, and the kit names none of them.
3. **It has two shapes, and a mapping answers one.** *Decide*: among supplied
   options — the chain's triage questions (`/pr-iterate`'s per-comment
   triage, `/to-tickets`' label pre-screen, `/dogfood`'s pass / fail / paper
   cut). *Rank-or-verify*: over supplied candidates. A consumer who maps the
   domain says which shape the backend answers, beside the mapping.
4. **A decider is never handed a verification.** The measurement in the
   context above is the reason: on the one published comparison, the decider
   scored below chance at "is this trajectory good" while a ranker set the
   state of the art. That figure is the ranker's authors' own, on their
   benchmarks (report, section 5 — the comparator is named, as lesson L6
   asks); it is one measurement, and it is the only one there is.
5. **No typed judge takes the review verdict** — neither shape. The verdict
   is the whole diff, with reasons a human can verify from it (shared
   invariant §5); a probability with no rationale is not that, and a typed
   judge's window does not hold a diff. The typed rung belongs at triage and
   routing, never at the verdict.
6. **It ships unmapped, and the kit's own mapping declines it explicitly.**
   `scripts/agents.config.sh` assigns nothing, as always. The kit-only twins
   (`scripts/agents.kit.config.sh` and its codex counterpart, never shipped)
   carry a comment that names `AGENT_TIER_MECHANICAL_JUDGE`, says the kit
   names no model, and never assigns it — because a decline is a decision
   and an absent line is not.
7. **Explicit non-goal**: this record chooses no backend and no price, does
   not fix the shape of a typed return (PRD #273's vocabulary and
   return-shape tickets own that), and does not decide which skill spawns a
   judge first. It names the seam; the mapping is the consumer's.

## Consequences

- **Good**: a consumer with no API budget can map an open-weight judge on
  their own machine to the chain's triage questions without the kit naming
  one; the shape is said at the seam, so a verification is not handed to a
  decider by accident; the kit's refusal to name a model is a recorded
  decision rather than an omission.
- **Bad / trade-off**: a seam with nothing behind it in the kit — every
  session here resolves `mechanical judge` to the mechanical tier's model and
  pays that price, until a judge earns a mapping. Two shapes mean a caller
  has to know which it needs, and that knowledge lives in prose.
- **Neutral**: a consumer sees one more paragraph in the manual and one more
  variable name they may set. The resolver, the wrapper and the shipped
  policy file are byte-identical to before.
- **Honest limitation**: the resolver cannot tell a decider from a ranker. A
  consumer who maps a decider and hands it a verification gets a silent bad
  answer; clause 4 is a rule whose only check is the tiers suite holding this
  record and the manual to the words, not a script refusing the call. And the
  measurement behind it is one paper's own numbers on its own benchmarks.

## More information

- Implemented in: #275 (PRD #273), which adds the `mechanical judge` cases
  to `tests/agents-tiers.test.sh`, the declining comment to the kit-only
  policy files, and the paragraphs in the root manual, the manual template
  and the glossary's **Task domain** entry.
- The research: https://view.centaurspec.com/oNa-l6LtDR — section 5 "The
  field, eleven days in" (the contrastive ranker's verifier result; "L4's
  contract now has two shapes"), section 6 lesson L4 (the cost ladder as a
  domain, never a fifth tier), section 7 "A decider as a verifier".
- Related: ADR-0003 (the closed tier vocabulary and the kit-only mapping),
  ADR-0007 (the `self-implemented` domain — the other token the kit names on
  the open axis), shared invariant §5, the root manual's "Capability tiers".
