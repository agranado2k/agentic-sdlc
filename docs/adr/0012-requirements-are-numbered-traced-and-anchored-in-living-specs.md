# ADR-0012: Requirements are numbered, traced to tickets and tests, and anchored in living specs

- **Status**: Accepted
- **Date**: 2026-10-05
- **Deciders**: Arthur Granado (operator), who delegated the rulings below to the orchestrating session after reviewing the spec-driven development fit analysis
- **Supersedes / amends**: — (builds on ADR-0008: nothing here reads the trace)
- **Superseded by**: —

## Context and problem statement

The chain is spec-first: a PRD is written, decomposed and closed when its wave
lands. Nothing numbered connects what a PRD asks for to the tickets that build
it, the tests that hold it, or the review that judges the diff. `/review-pr`'s
Axis 2 is told to cite "a PRD acceptance criterion" for every SPECIFIED item,
yet the PRD template has no such section, so the citation is free text or
nothing. A requirement no ticket covers is invisible until someone notices it
missing.

The spec-driven development tools surveyed on 2026-10-05 (GitHub Spec Kit,
AWS Kiro, OpenSpec, BMAD) converge on numbered, testable requirements, a
coverage analysis between requirements and tasks, and — in OpenSpec — a living
spec per area that each change edits by ADDED / MODIFIED / REMOVED deltas. The
critics' measured failure modes are markdown bloat, double review and drift
between spec and code. The operator chose to adopt the traceability spine and
to move the kit one step up the scale, from spec-first to spec-anchored.

## Decision drivers

1. Every rule has a failing check (shared invariant §8) — a requirement that
   no test names is a claim.
2. The context budget (§11): the PRD must not grow a second exhaustive list.
3. Tracer bullets (§2): nothing here adds a horizontal planning layer.
4. Portability: skills ship unstamped and the gate's core stays POSIX sh plus
   the optional Node harness.
5. ADR-0008: no skill reads the trace to decide anything.

## Considered options

1. **Numbered requirements, a coverage check, and living specs edited by
   deltas** *(chosen)* — the spec-anchored step, with the suite as the check
   that keeps the living spec honest.
2. **Numbered requirements and a coverage check only** (spec-first with
   traceability) — rejected by the operator: every PRD re-describes the
   existing behavior it changes, and ids die with the PRD, so a test cannot
   name a requirement that outlives its wave.
3. **Spec Kit's full artifact set** (plan, research, data-model, contracts,
   tasks files) — rejected on driver 2: it is the bloat critics measured.
4. **Spec-as-source** (code regenerated from the spec) — rejected: the suite is
   the specification (§3), and generation brings non-determinism into the
   build.

## Decision outcome

Chosen: **numbered requirements, a coverage check, and living specs edited by
deltas**.

1. **A PRD carries a Requirements section**, between Scenarios and
   Implementation Decisions. Each line is one observable behavior a test can
   fail, written in EARS-lite: `The <system> SHALL …`, `WHEN <trigger>, the
   <system> SHALL …`, `WHILE <state>, …`, `IF <condition>, THEN …`, `WHERE
   <feature>, …`. Each carries an id `R<n>`, numbered from 1 within the PRD.
2. **The requirements are the exhaustive list; the user stories are not.** The
   template drops its "extremely extensive" demand: one story per distinct
   actor goal, kept as the *why*, and every requirement serves at least one.
3. **A ticket names what it covers** on a `Covers:` line of requirement ids. A
   prefactor, an open-issue ticket or a release ticket may carry none.
4. **A coverage check runs before the quiz** in `/to-tickets`: a script, not
   prose, that names every requirement no ticket covers and every ticket that
   covers nothing without being one of the exempt kinds. It reads ids only —
   the requirement lines and `Covers:` lines — so it runs on the screened copy
   of an untrusted PRD body without reading prose into the session.
5. **`/to-prd` asks before writing an ungrilled PRD.** When the conversation
   holds no grilling session it asks one question — run `/grill-me` first
   (`/grill-with-docs` where a glossary and decision records exist)? Yes runs
   it and hands back; no writes the PRD with what would have been guessed under
   Open Issues. The check reads the conversation only (driver 5).
6. **Downstream skills cite ids.** `/implement`'s restatement names the ids its
   ticket covers; Axis 2 of `/review-pr` cites a requirement id for a SPECIFIED
   item when the spec carries ids, and lists a covered requirement the diff does
   not deliver as a confirm item. Without ids, both behave as before.
7. **A living spec is one file per area under `docs/specs/<area>.md`**, the
   area a lowercase token `[a-z][a-z0-9-]*` the PRD names (a context in the
   glossary's map is the default unit). It holds the area's current
   requirements, each with an id `R<n>` stable for the file's life; outside the
   file a requirement is cited as `<area>/R<n>`. Ids are never reused.
8. **Where a living spec exists for the area, a PRD states its requirements as
   deltas** under `### ADDED`, `### MODIFIED` and `### REMOVED`. An ADDED line
   takes the next free id in the area; a MODIFIED line restates the whole new
   text under the existing id; a REMOVED line names the id and why. A PRD for an
   area with no living spec writes plain `R<n>` lines, and the first ticket that
   covers one creates the file.
9. **Deltas merge in the PR that delivers them**, never in a wave-end sweep:
   the implementing session edits the living spec for the ids its ticket covers
   in the same diff as the test that names them, so spec and test land together
   or not at all.
10. **The gate holds the living spec to the suite**: every requirement in
    `docs/specs/*.md` is named, as `<area>/R<n>`, by at least one file the
    project's test globs match. With no living spec the check is vacuous. Both
    engines of the docs gate carry it, per the rule that their lists move
    together.
11. **Explicit non-goals**: no plan, research, data-model or contracts files;
    no spec-as-source; no unchanged-behavior section in the PRD (a living spec
    makes everything outside a delta unchanged by construction — *later*, if
    PRDs for areas with no living spec keep needing it); no clarify loop inside
    `/to-prd` beyond the one question.

## Consequences

- **Good**: a requirement is traceable from PRD to ticket to test to review;
  drift between the living spec and the suite fails the gate; a PRD that
  changes an existing area states only the delta.
- **Bad / trade-off**: one more artifact kind to keep, and a test must name the
  requirement it holds, which is new discipline for every suite. The gate
  check is new shared-layer mechanism, so the wave is a release.
- **Neutral**: the trace is untouched; tickets keep every existing stamp.
- **Honest limitation**: the gate proves a test *names* a requirement, not that
  the test *checks* it — a test can cite `<area>/R3` and assert nothing about
  it. Axis 2 and the human reading the confirm-list remain the check on that.
  The coverage check proves every requirement has a ticket, not that the ticket
  delivers it.

## More information

- Analysis: the spec-driven development fit report of 2026-10-05 (Centaur Spec
  `LLe3UglxvU`), with the operator's comments and the plan it ends on.
- Prior art: Spec Kit's `FR-001` requirements and `/analyze`; Kiro's EARS
  requirements; OpenSpec's `specs/` and change deltas.
- Implemented in: the PRD and tickets that cite this record.
