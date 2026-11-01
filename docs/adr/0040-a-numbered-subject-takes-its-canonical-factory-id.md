# ADR-0040: A numbered subject takes its canonical factory id, paired by policy

- **Status**: Accepted
- **Date**: 2026-11-01
- **Deciders**: the implementer session for #963, under the operator's delegation of rulings, from PRD-15 §8's decision record A; the merge of its pull request is the operator's yes
- **Supersedes / amends**: amends ADR-0024 clause 1 — a numbered type's one spelling, `<type>:#<digits>`, gains a second where the policy pairs the type with a factory prefix; recorded as a new record because ADR-0024 is at its amendment cap (ADR-0021 clause 5), as ADR-0034 and ADR-0036 were
- **Superseded by**: —

## Context and problem statement

The kit plans in the factory (`.factory/`), and so may a consumer. A factory
ticket is named by its id, `T-07`, and a factory project opens no forge issue
for it. Today this repository mirrors each factory ticket as an issue so the
chain past the stamp has a number to write; PRD-15 ends that mirroring, and
the operator ruled (2026-10-31, PRD-12 Q3 option (b)) that the chain takes
`T-<n>` wherever it takes an issue number.

The trace is the receiving end. Under the kit's own policy,
`TRACE_NUMBERED_TYPES='ticket pr prd'` holds a ticket to one spelling,
`ticket:#<digits>` (#305), so `ticket:T-07` is refused at emit and nothing
later in the chain can write it. T-74 (#937) asked for the same opening and
is absorbed here.

## Decision drivers

- One spelling per ticket: a join key with synonyms is not one (#305). Two
  spellings of one factory ticket, `T-7` and `T-07`, would break every join.
- The kit names no tracker: the factory's prefix reaches the trace as policy
  data, never as code, and the trace runs no factory command.
- A consumer that sets nothing sees nothing change.

## Considered options

1. **A second policy key, `TRACE_FACTORY_IDS`, pairing a numbered type with a prefix** *(chosen)* — `ticket=T prd=PRD`; the shape is checked alone.
2. **Open the `ticket` type in the kit's own policy** — rejected: drops #305's one spelling for issue numbers too, and `show` on one spelling would miss the others again.
3. **Hard-code the factory's `T-` and `PRD-` prefixes in the trace** — rejected: names a tracker in shared-layer code, and a consumer's factory may use another prefix.

## Decision outcome

Chosen: **option 1**.

1. The trace policy carries `TRACE_FACTORY_IDS`, words `<type>=<PREFIX>`.
   It ships empty with a comment naming its form; the kit's own trace policy
   sets `ticket=T prd=PRD`. Only the policy file sets it; an environment value
   is ignored, as `TRACE_NUMBERED_TYPES`'s is.
2. A word whose type `TRACE_NUMBERED_TYPES` does not name, whose prefix is not
   1 to 8 uppercase letters, or that has no `=`, is exit 2 naming the word and
   the policy file.
3. Where a type is paired, `emit` accepts a subject or `related` token
   `<type>:<PREFIX>-<digits>` whose id is **canonical** — 2 to 6 digits, a
   leading zero only in the two-digit form (`T-07`, `T-101`; never `T-7`,
   `T-007`) — beside `<type>:#<digits>`, and refuses every other spelling of
   that type, exit 2, writing nothing and naming both forms.
4. `show` takes a canonical factory-id subject and matches it as a whole token,
   so `ticket:T-07` never finds `ticket:T-070`. `verify` passes a canonical
   factory-id line and advises on a non-canonical one, naming both forms, its
   verdict unchanged.
5. With the key empty or unset every subject is judged exactly as before.
6. **Explicit non-goal**: which writer pads a one-digit id, how `/implement`,
   the landing script and the dispatcher take a factory id, and when the kit
   stops mirroring are PRD-15's later slices and decision record B.

## Consequences

- **Good**: a factory ticket with no issue can be traced and joined by one
  spelling, and the receiving end lands before any writer.
- **Bad / trade-off**: a numbered type now has two spellings, one per handle;
  one ticket still has one handle (a mirrored ticket's is its issue number), but
  nothing in the trace enforces that a ticket is never written both ways.
- **Neutral**: the shape check is by pattern alone; a well-shaped id for a
  ticket that does not exist is accepted, as `ticket:#99999` is.
- **Honest limitation**: lines written by hand before the rule are advised on,
  never rewritten.

## More information

- Implemented in: #963 (factory T-97, PRD-15 slice 1; absorbs #937, T-74).
- Requirements: `docs/specs/runtime.md` R229 to R236.
- Related: ADR-0024 clause 1, ADR-0021 clause 5, ADR-0034, ADR-0036; #305.
