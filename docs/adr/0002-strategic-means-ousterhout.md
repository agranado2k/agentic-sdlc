# ADR-0002: "Strategic" means Ousterhout's strategic programming; Evans's work is the context map

- **Status**: Accepted
- **Date**: 2026-09-02
- **Deciders**: Arthur Granado (operator), at the PRD #107 grilling
- **Supersedes / amends**: amends ADR-0001 §4 in one respect — the kit ships four records under `docs/adr/` now, not three, and bootstrap's kit-own list strips this one too
- **Superseded by**: —

## Context and problem statement

The 0.15.0 wave makes architecture a recorded decision: a design brief, three
anchors in the engineering article, a context map in the glossary, and a
housekeeping pass that re-questions the shape as the project evolves. Three
sources the wave drew on use the word *strategic* for three different things,
and the kit's glossary rule is one name per concept:

- John Ousterhout (*A Philosophy of Software Design*, ch. 3) — **strategic
  programming** versus tactical programming: working code is not enough, and
  design is a continuous investment judged by the complexity it removes.
- Eric Evans (*Domain-Driven Design*) — **strategic design**: subdomains,
  bounded contexts and the relationships between them, as opposed to the
  tactical patterns inside one model (aggregates, value objects, repositories).
- The *Domain-Driven Agents* article the wave adapted — strategic work is the
  human deciding what changes and why; tactical work is the agent carrying it
  into files.

The kit already cites Ousterhout for deep modules and "design it twice", and
already keeps the language half of Evans (the glossary is titled "Ubiquitous
Language" and groups terms by bounded context). Before this wave the word
*strategic* appeared nowhere in the kit, so it could be pinned cleanly, once.

## Decision drivers

- One name per concept, in code and in conversation (the glossary's rule).
- The concept the kit most needs a word for is the *investment* stance — the
  reason a design brief and a periodic re-question exist at all.
- Evans's ideas must survive intact; only their label is at stake.
- The human/agent split already has names in the kit (the planner tier, the
  autonomy label) and needs no third.

## Considered options

1. **Ousterhout's sense, only** *(chosen)* — "strategic" is the investment
   stance; Evans's work is named *context map* and *subdomain classification*;
   "strategic design" is a banned phrase in the glossary.
2. **Evans's sense** — rejected: it would leave the investment stance, which
   the design brief and the housekeeping scan embody, without a word, and
   would collide with the kit's existing Ousterhout vocabulary.
3. **The article's human/agent sense** — rejected: the kit already names that
   split (tier, label), and a third name for it is the drift the glossary
   forbids.
4. **Avoid the word entirely** — rejected: the design brief's whole framing is
   that the shape is an investment decided deliberately, and "strategic" is
   the accepted word for that stance in the source the kit already cites.

## Decision outcome

Chosen: **Ousterhout's sense, only**.

1. In the kit's prose, skills and glossary, *strategic* means design as a
   continuous investment, judged by complexity — dependencies plus obscurity.
   The design brief is one strategic act; the housekeeping pass's red-flag scan
   is its periodic re-question.
2. Evans's strategic patterns are kept under the kit's names: the **context
   map** (contexts and their edges, declared from both sides) and the
   **subdomain classification** (core, supporting, generic). The phrase
   "strategic design" is banned in the glossary, with those two as the
   replacements.
3. The tactical half of Evans — aggregates owning their invariants, value
   objects over primitives, the ubiquitous language in code — lives in the
   shared code-craft article as one portable rule, without the word.
4. The human/agent split is not called strategic/tactical; it stays the
   planner tier and the autonomy label.
5. **Explicit non-goal**: this record does not choose an architecture for the
   kit or for any consumer. It fixes a word so the brief that does can be
   read.

## Consequences

- **Good**: a reader of any skill, article or glossary entry meets one meaning
  of the word, and the design brief's framing reads as what it is — an
  investment decision, not a diagram.
- **Bad / trade-off**: a reader arriving from the DDD literature must learn
  that the kit says "context map" where their books say "strategic design".
  The glossary's banned-words entry is where they learn it.
- **Neutral**: the coldtake article's split survives in substance (humans
  decide, agents carry) under the kit's existing names.
- **Honest limitation**: nothing enforces the word mechanically outside the
  glossary's banned list; a skill that reintroduces "strategic design" would
  be caught by a reader, not a gate.

## More information

- Implemented in: PRD #107; the design brief skill (ticket #112), the context
  map (ticket #109), the craft rule (ticket #110).
- Related: ADR-0001 (the kit follows its own framework); the glossary's
  **Context map** and **Subdomain classification** entries.
