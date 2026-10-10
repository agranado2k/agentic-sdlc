# ADR-0021: A record past five in-place amendments is consolidated into a successor, starting with ADR-0008

- **Status**: Accepted
- **Date**: 2026-10-10
- **Deciders**: a planner session for #679, under the operator's delegation of rulings (2026-10-10); the merge of its pull request is the operator's yes
- **Supersedes / amends**: — (refines the index's amendment convention: what "may be recorded in place" is bounded by; ADR-0008 stays binding until its successor lands)
- **Superseded by**: — (amended 2026-10-10 for #692: ADR-0024 supersedes ADR-0008, which section H then skips, so ADR-0008's ceiling leaves the frozen line of clause 5 and the line names ADR-0009's alone)

## Context and problem statement

ADR-0008, the trace record, is 886 lines. Its header's "Superseded by" field
holds about two dozen dated amendments as one paragraph of some 6,000
characters. Its index row is the longest line in `docs/adr/INDEX.md`. About
720 of its lines are the Decision outcome, where every amendment is an
italic block after the clause it amends. Its More information section adds
one bullet per amending ticket. The housekeeping pass of 2026-10-09
(`housekeeping-20261009T142448Z`, finding 7) flagged it. "One decision per
record" and "a reversal is a new record" both strain: the record has turned
into the trace's changelog.

The cost falls on later sessions, not on whoever writes the next amendment.
Hard rule 5 makes every session that changes the trace script, its hooks or
its policy read this record first. The current rule is buried in narrative
about how each amendment came to be, so a reader pays for the history to
find the rule. Each new amendment makes that worse, and the trace is the
fastest-moving decision the kit has. No other record comes close. ADR-0009
is next with seven amendments named in its header (its index row lists
five) in 347 lines, and the other eighteen records hold at most three
each.

Citations raise the stakes. About sixty-six files name ADR-0008, many of
them shipped skills (as "the kit's ADR-0008", per ADR-0017), and about
ninety-three of those citations name a clause by number, `ADR-0008 clause N`.
Clauses 1, 4, 5, 6 and 7 carry most of them. Editing a shipped file is a
release action (hard rule 3), so any option that needs every citation
re-pointed before it can land is a release.

## Decision drivers

- **The read cost per later session.** The record is read before every trace
  change. What that reader needs is the current rule.
- **Citations keep resolving.** `ADR-0008 clause N` has to lead to the right
  rule with no edit to a shipped file.
- **The index conventions.** One decision per record. A reversal is a new
  record, never an edit. An amendment in place may only narrow or clarify.
  The index alone has to answer "what is currently binding?".
- **No history is lost.** The amendments' reasons stay readable, just off the
  path a reader takes to find the rule.
- **The fix stays fixed.** Whatever the kit does to ADR-0008 has to apply
  again to the next record that grows the same way, ADR-0009 included.

## Considered options

1. **A consolidating successor, with the in-place amendment allowance capped
   at five** *(chosen)*. A new record restates the trace decision as it
   binds today: the amendments are folded into the clauses and the
   narrative stays in ADR-0008. ADR-0008's status becomes `Superseded by`
   the successor. The cap is what triggers the next consolidation.
2. **A cap alone: ADR-0008 takes no more amendments, and later trace changes
   become new records that amend it.** Rejected. This stops new growth but
   leaves the 886 lines a reader pays for, and every later change adds one
   more record to read alongside it. The rule ends up spread over ADR-0008
   plus N small records, and a reader has to merge them by hand. That costs
   more per session than the current record, and the cost keeps rising.
3. **A successor with no cap.** Rejected. It pays down this debt once and
   lets the successor grow back the same way. The trace keeps moving, and
   without a stopping rule the next housekeeping pass files this ticket
   again.
4. **Rewrite ADR-0008 in place with the amendments folded in.** Rejected.
   The convention forbids editing an accepted record beyond a narrowing
   amendment, and in-place rewrites are exactly how a record's history gets
   lost.
5. **A successor that renumbers its clauses as the material now falls.**
   Rejected. About ninety-three `ADR-0008 clause N` citations would point at
   the wrong rule, and fixing the shipped ones would be a release.

## Decision outcome

Chosen: **option 1.**

1. **ADR-0008 is consolidated into a successor record.** The successor states
   the trace decision as it binds today: one record, its amendments folded
   into the clause text as present-tense rules, and no dated amendment blocks.
   Its Context and Considered options are ADR-0008's, shortened. Its More
   information names ADR-0008 as the place each amendment's reason is kept.
   It reverses nothing. A rule that reads differently in the successor than
   in ADR-0008 as amended is a defect in the successor.
2. **The successor keeps ADR-0008's clause numbers.** Clause *N* of the
   successor is clause *N* of ADR-0008, so every `ADR-0008 clause N` citation
   still names the right rule. A rule that no longer fits its clause stays
   there and points to where its detail lives. It does not move to a new
   number.
3. **Citations are not re-pointed when the successor lands.** ADR-0008's
   status becomes `Superseded by <successor>`, and its index row says that
   and nothing else. A citation therefore resolves in one hop: open ADR-0008,
   read the status, go to the same clause in the successor. A citation is
   re-pointed when its file is edited for a reason of its own. A shipped
   file's citation is re-pointed only in a release that already touches that
   file. Kit-only files (suites, the kit's own docs and scripts) may be
   re-pointed in the successor's own change.
4. **ADR-0008 takes no further in-place amendment from today.** A trace
   change decided before the successor lands is recorded as a new record that
   amends ADR-0008, and the successor folds it in when it lands.
5. **The in-place amendment allowance is capped at five per record.** A record
   whose header already names five in-place amendments takes no sixth.
   The next change to its decision is a consolidating successor, written
   under clauses 1 to 3 as they apply to that record. The cap counts the dated
   amendment notes in the record's header, from its title to its first
   section, whichever field holds them. A note counts when it starts with
   `amend` and is followed by its date. It applies to every record in
   `docs/adr/` from today and to each successor in turn. A successor starts
   at zero. A record past the cap today is held at the count it has:
   ADR-0008 at twenty-four, ADR-0009 at seven. Neither takes another. The
   suite reads these ceilings from this line: `frozen: 0009:7` (ADR-0008's
   left it when ADR-0024 superseded it, #692).
   `tests/self-host.test.sh` section H counts every live record's header and
   fails on one past its ceiling. A superseded record is skipped. A probe it
   baits proves the count can fail.
6. **Explicit non-goals.** This record does not write the successor: that
   build is #692, at the implementer tier. It changes no shipped
   file. It does not change the consumers' index template
   (`templates/docs/adr/INDEX.md.template`). Carrying the cap into it would be
   a shared-layer change, and that is a separate decision. It does not
   consolidate ADR-0009 now. Its header already names seven amendments, so
   its next change is its consolidating successor (clause 5), not an eighth
   amendment.

## Consequences

- **Good**: the record a trace change has to read first becomes the current
  rule, roughly a third of ADR-0008's length, with no history to read past.
  ADR-0008 stays in place for the reasons behind each rule.
- **Good**: every clause citation in the kit and in shipped skills still
  resolves, and nothing ships to make that true.
- **Good**: the cap is a measured ceiling (shared invariant §9), held by a
  suite rather than claimed (hard rule 9). It is counted from a record's
  header and turns "this record is too long" into a
  trigger rather than a housekeeping judgment.
- **Bad / trade-off**: a citation to ADR-0008 costs one extra hop until it is
  re-pointed, and some may never be. Two records carry the same clause
  numbers, so a reader who skips the status line reads the history, not the
  rule.
- **Bad / trade-off**: the successor is a large prose change that no suite
  can fully check. A folded clause that quietly drops an amendment's rule is
  a regression only a reader will catch. The follow-up ticket's review owns
  that comparison.
- **Bad / trade-off**: the suites that read ADR-0008's text (for instance
  `tests/trace-skills.test.sh` section 8, which matches clause 7's dated
  amendment) must move to the successor in its change, or keep reading
  ADR-0008 deliberately.
- **Neutral**: ADR-0009 is already past the cap. Whoever changes it next
  writes its successor, which makes that change bigger than it would
  otherwise be.
- **Honest limitation**: the cap counts amendments, not lines. A record can
  stay under five amendments and still grow long, as ADR-0006 has at 405
  lines with none. Length without amendments is a different problem, and
  this record leaves it to housekeeping.

## More information

- Decided for #679, from `housekeeping-20261009T142448Z`, finding 7.
- The successor's build is #692 (Tier: implementer).
- Measured at decision time: ADR-0008 is 886 lines, with about two dozen
  dated amendments in its header and an outcome section of about 720 lines.
  About 66 files cite ADR-0008, with about 93 `clause N` citations.
- Related: ADR-0008 (the record consolidated), ADR-0017 (a shipped file cites
  a kit record as the kit's), ADR-0004 and shared invariant §11 (the context
  budget this protects), the index's Conventions.
