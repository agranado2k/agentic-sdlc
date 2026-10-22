# ADR-0034: A review event carries its join keys — a raise its id and severity, a verdict its outcome and axis

- **Status**: Accepted
- **Date**: 2026-10-22
- **Deciders**: the implementer session for #832, under the operator's delegation of rulings; the merge of its pull request is the operator's yes
- **Supersedes / amends**: amends ADR-0024 clause 1 — "no outcome is required on any kind" and "a missing key is no violation except where `!` says so" gain two kinds' exceptions, and the review broker's "no outcome otherwise" becomes a refusal before anything is posted; recorded as a new record because ADR-0024 already names five in-place amendments and takes no sixth (ADR-0021 clause 5)
- **Superseded by**: —

## Context and problem statement

The retrospective of 2026-10-22 (finding F1, questions 3 and 6) read review
events that no reader could join. Three `finding.raise` events had no
`data.severity`: pr:#788 M-1, whose reason said LOW under an M id, and
pr:#821 L-0, a reviewer's probe with "x" as its reason. One raise on pr:#826
had no `data.id`, and its `data.severity` was `LOW` in upper case. Two
`review.verdict` events, on pr:#806 and pr:#810, had no `data.axis`. One on
pr:#811, written through the review broker, had no `outcome`: the worker's
verdict line opened "no blocking findings", which the broker's three
openings did not match, so it wrote the verdict with none.

Each was legal at emit. ADR-0024 clause 1 holds a *present* key to its shape
and requires one only where a conditional row says so, and it requires no
outcome on any kind. A raise without its id joins no triage. A raise without
a declared severity falls out of every per-severity count `/retro` makes. A
verdict without its axis or its outcome is no verdict the landing script
(ADR-0032) or `/retro` can count.

## Decision drivers

- A rule with no failing check is a claim (shared invariant §8). The skills
  already write all four keys, so the gap is the check, not the instruction.
- History is never rewritten. Lines already written stay, and a reader is
  told about them.
- The severity words are the vocabulary checker's (`scripts/vocab.sh`), so a
  project that renames them is held to its own words, never to a copy.

## Considered options

1. **Require the four keys at emit, advise on history** — chosen.
2. **Leave emit open and only advise in `verify`.** Rejected: the bad lines
   keep arriving, and an advisory nobody reads after the fact repairs nothing.
3. **Make every shape row's key required.** Rejected: `finding.triage`'s
   `data.id` and `data.source` are optional by decision (ADR-0024 clause 1),
   and a check's triage carries no id. The rule belongs to the two kinds the
   evidence names.

## Decision outcome

Chosen: **option 1.**

1. **`scripts/trace.sh` carries a required-key table, `TRACE_REQUIRED`,**
   beside the shapes. Each entry is `<kind>=outcome` or `<kind>=data.<key>`:
   every line of that kind carries the field, non-empty, whatever its
   outcome. The table today is `finding.raise` `data.id` and `data.severity`,
   and `review.verdict` `outcome` and `data.axis`. An emit missing one is
   exit 2, naming the kind and the field, and nothing is written. A dry run
   is held the same way.
2. **The values stay where ADR-0024 clause 1 puts them.** A raise's `data.id`
   is the `[CHML]-[0-9]+` shape row. A verdict's outcome is the kind's own
   words. A new shape row holds `review.verdict` `data.axis` to `1` or `2`.
3. **A raise's `data.severity` is a severity word the vocabulary checker
   declares,** asked of `scripts/vocab.sh` beside the script as
   `Severity: <value>`. Every occurrence on the line is held. The refusal is
   exit 2 and quotes the checker's own words. With no checker beside the
   script, no word is judged, but the key is still required.
4. **`verify` advises on history.** A raise or a verdict already written
   without a required key, or a raise whose severity is off the checker's
   words, draws one stderr line naming the file, the line and what is
   missing or off. It is never a bad line and never the verdict. `summary`
   and `export` say the count once and point at `verify`.
5. **The review broker's verdict always carries an outcome.** A `VERDICT:`
   line opening "not blocking", "no blocking" or "no findings" is `pass`.
   One opening "blocking" is `blocked`, and the no-lens line stays
   `blocked`. A line that opens with none of these fails the worker contract,
   and nothing is posted, so no verdict is traced without its word. This
   replaces ADR-0024 clause 1's "no outcome otherwise".

## Consequences

- Good: every raise joins its triage and is counted by its severity, and
  every verdict says which axis it is and what it found. The six events the
  retrospective found are advised on by `verify` each time it lists.
- Bad: a session that improvises a raise without a severity now loses the
  event. The line ends `|| :`, so the session goes on, and the refusal on
  stderr names what is missing.
- Bad: a worker whose verdict line opens with other words, such as
  "Approve", is refused by the broker and has to be dispatched again.
  The worker contract names the openings, so this is a contract breach, not
  a new rule.
- Neutral: a raise emit now runs the vocabulary checker once per severity,
  one short process.

## More information

- Ticket #832; retrospective `retro-20261022T135553Z`, finding F1.
- Held by `tests/trace.test.sh` section 41 (the refusals, the checker's
  words read through `VOCAB_CONFIG`, the lone-script case, and the `verify`,
  `summary` and `export` advisories) and by `tests/forge-broker.test.sh`
  (every verdict the broker traces carries an outcome, and an unreadable
  opening is refused before anything is posted).
