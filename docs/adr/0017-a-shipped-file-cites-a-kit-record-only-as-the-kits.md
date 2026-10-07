# ADR-0017: A shipped file cites a kit record only as the kit's

- **Status**: Accepted
- **Date**: 2026-10-07
- **Deciders**: the implementing session for #564, under the operator's delegation of rulings
- **Supersedes / amends**: —
- **Superseded by**: —

## Context and problem statement

Bootstrap strips the kit's decision records from every project it stamps,
and `t_kit_residue` proves none survives. The files it ships — skills,
shared scripts, the adapter, the policy files, the hook — cited those
records all the same: about a hundred bare `ADR-0008`, `ADR-0012`, `ADR-0006`
and the like, across 38 files. A real consumer upgrade (2026-10-06, #564) found
them pointing at nothing. Worse than nothing: a project numbers its own
records from 0001, so by its eighth decision a bare `ADR-0008` in a shipped
skill points at the project's own 0008, which decides something else. One
recipe paragraph even told the consumer "your copy of ADR-0008", a copy no
consumer has.

## Decision drivers

- A shipped line is obeyed by an agent in a repo that is not the kit's; a
  cite it cannot resolve, or resolves wrongly, is a defect, not a typo.
- The cites carry real information — why a script refuses, where a rule was
  decided — and the records are public in the kit's repository; deleting the
  cites throws away provenance a curious consumer can still follow.
- The rule must hold itself: a rule with no failing check is a claim.

## Considered options

1. **A shipped file names a kit record only as `the kit's ADR-NNNN`, held by a
   suite over a fresh bootstrap** *(chosen)*
2. **Replace every cite with something the consumer has** — a glossary term,
   a shared invariant. Rejected as the general rule: most cites name a
   decision no consumer-side document carries (the worker budget, the trace's
   clauses), so the replacement would be a paraphrase that loses the pointer.
3. **A URL per cite.** Rejected: a hundred links into a repository whose
   layout can move, each one rotting on its own.
   One place says where the kit's records live instead: the ADR index
   template a consumer reads.
4. **A docs-gate rule in both engines.** Rejected: the gate runs in consumer
   projects too, where a bare `ADR-0008` is the project's own record and
   correct. Only the kit knows which files it ships, so the check is a kit
   suite.

## Decision outcome

Chosen: **every file a fresh bootstrap leaves names a kit decision record as
`the kit's ADR-NNNN`, on one line, or not at all.**

1. The spelling is the qualifier, so the reader knows to look in the kit's
   repository (`docs/adr/` there), never in the project's own index.
2. `VERSION` is exempt: it is the kit's own release ledger, every line the kit
   speaking of itself, and its history notes are not rewritten.
3. `tests/lib.sh`'s `t_kit_record_cites` is the check: `tests/self-host.test.sh`
   runs it over a fresh bootstrap and over the optional dogfood skill, and
   `tests/harness-helpers.test.sh` drives it red per case.
4. The project's ADR index template says what `the kit's ADR-NNNN` means.

## Consequences

- **Good**: a consumer reading a shipped skill can tell the kit's records from
  its own, and the next bare cite fails the kit's suite before it ships.
- **Bad**: the cites read longer, and a possessive (`ADR-0007's warning`)
  needs rewording to stay readable.
- **Neutral**: issue and PRD numbers in shipped comments (`PRD #237`) are the
  kit's tracker's too; they are not records and stay out of this rule's reach.

## More information

- Ticket #564; the sweep's sibling, `t_kit_residue`, is #562's.
