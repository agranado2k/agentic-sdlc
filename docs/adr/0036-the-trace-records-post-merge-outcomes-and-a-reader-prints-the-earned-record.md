# ADR-0036: The trace records a landed PR's post-merge outcomes, and an operator-run reader prints each review area's earned record

- **Status**: Accepted
- **Date**: 2026-10-25
- **Deciders**: the implementer session for #875 (PRD-06 slice 1), under the operator's delegation of rulings; PRD-06 was approved by the operator on 2026-10-25, and the merge of this record's pull request is the operator's yes
- **Supersedes / amends**: amends ADR-0024 clause 1, which gains the kind `merge.outcome`, and clause 7, which gains two operator-run readers; recorded as a new record because ADR-0024 already names five in-place amendments and takes no sixth (ADR-0021 clause 5), as ADR-0034 did
- **Superseded by**: —

## Context and problem statement

The trace records what the chain decided up to `merge.land` and nothing
after it. No event says that a landed PR was reverted, that a fix two weeks
later rewrote its lines, or that its factory ticket failed QA. So nobody can
say which review lenses catch real mistakes in which part of the repository.
`/retro`'s question 2 counts how the implementing session triaged each
finding, but that label comes from the reviewer's own model family, and it
never looks past the merge.

PRD-06 (D-02's earned-autonomy plan, K1) measures this and does nothing
else: a kind that records each mistake against the PR it happened to, a
recorder that writes those events from git and the trace, and a reader that
prints each review area's record. No chain skill reads either, and no number
is compared to a threshold. That is K2 and K3, which must write the record
that supersedes clauses 7 and 9 of ADR-0024 when a chain skill comes to act
on the record. This record does not.

## Decision drivers

- A new kind is a clause 1 change, and ADR-0024 is at its amendment cap.
- Clause 7 says the chain never reads the trace. Both new readers are run by
  the operator and by `/retro`, the one sanctioned reader, so they stay
  within clause 7's existing shape.
- Commit messages, PR titles and ticket bodies are untrusted. A field the
  trace holds must come from git or the trace, never from their prose.
- The record is computed on read, like cost (clause 6), so a change to its
  definition re-reads all history and no stored copy goes stale.

## Considered options

1. **One new record amending clauses 1 and 7** — chosen.
2. **Consolidate ADR-0024 into a successor now.** Rejected: a consolidation
   is its own change, and nothing in K1 reverses a clause.
3. **Record outcomes from `/merge-train` at landing time.** Rejected for K1:
   a chain skill would read the trace to find the PR a revert undid, and a
   by-hand landing would be missed. PRD-06 §6 keeps it as the later route.

## Decision outcome

Chosen: **option 1.**

1. **Clause 1 gains the kind `merge.outcome`, a post-merge outcome.** Its
   outcome words are `reverted`, `fixed` and `qa-failed`. Any other word is
   exit 2 with nothing written, and the outcome is required
   (`TRACE_REQUIRED`): a `merge.outcome` that names no outcome is nothing a
   reader can count. Its fields:
   - `subject` is `pr:#<N>`, the landed PR the outcome happened to.
   - `related` names the evidence PR where there is one: the reverting or
     the fixing landing.
   - `data.by_sha` is the evidence landing's merge commit, 40 hex digits.
   - `data.files` lists the files of the PR's lines that the evidence
     touched, as git's own diff names them.
   - `data.days` is the days from the PR's landing to the evidence's,
     digits.
   - `data.ticket` is the factory ticket a `qa-failed` outcome comes from.
   - **The evidence key** a re-run is checked against is `data.by_sha` for
     `reverted` and `fixed`, and `data.ticket` for `qa-failed`. Each is
     required on its outcomes (`TRACE_SHAPES` rows with `!`), so no outcome
     is written that a second run could not recognise.
   No field holds text from a commit message, a PR, an issue or a ticket
   body: only shas, PR and ticket ids, paths from git's diff, digits and
   outcome words. The trace suite holds the row with the others, row for
   row.
2. **A mistake is a landed PR with at least one post-merge outcome.** A
   revert has no time window. A fix counts inside the **fix window**, 30
   days after the PR landed. A failed factory QA counts whenever it is
   read. The recorder, which writes these, is PRD-06's later slices; until
   it lands, the only `merge.outcome` is a hand emit.
3. **A review area is one record of the lens-slice policy**, named by its
   lens token. A path belongs to every area whose include pattern matches it
   and whose exclude does not, and a lens with no record takes every path,
   as it reads the whole diff. The slicer says which areas a path belongs
   to (`sh scripts/lens-slice.sh --areas`), so the policy has one parser.
   The word is "review area", never bare "area", which the glossary gives
   to a living spec.
4. **The earned record is computed on read and stored nowhere.** The record
   reader is `sh scripts/trace.sh record`. It prints one row per review
   area: the area's most recent landings, at most 20 (`landings <n> of
   20`), how many of them landed inside the fix window, and how many carry a
   mistake. A landing is a `merge.land outcome=landed` with a
   `data.merge_sha`, the latest per PR. It counts toward every review area
   that one of the paths its merge commit changed against its first parent
   belongs to, read from git in the checkout the reader runs in. A landing
   whose commit that repository does not hold counts nowhere, and the
   reader says how many on stderr. Unconfigured, it prints nothing on
   stdout, writes nothing and exits 0. It compares nothing to a threshold,
   prints no risk word, and writes nothing to the trace or to any file. The
   misses, precision and their label sources join the row in PRD-06's
   slice 4.
5. **Clause 7 names two operator-run readers.** The outcome recorder reads
   `merge.land` to map a commit to its PR, and its own past outcomes to stay
   idempotent. The record reader reads `merge.land` and `merge.outcome`. The
   operator and `/retro` run them, and no other skill calls either:
   `tests/trace-skills.test.sh` holds every skill but the reader to no
   `record` call, as it does for `show`, `summary` and `export`. `/retro`'s
   question 2 prints the record's rows before its per-lens triage counts.

## Consequences

- Good: a landed PR's fate can be data. The first `/retro` after this
  release prints the kit's real per-area landing counts, which is the
  evidence PRD-06's open question on overlapping lens-slice rules waits
  for.
- Good: K3 builds its risk rule on a record whose definition is fixed here,
  with no risk words in it.
- Bad: until the recorder lands, every row shows zero mistakes, so a reader
  can take the record for a clean history. `/retro` says the recorder is
  not yet there.
- Bad: the reader runs one `git log` over every landing on each call. It is
  measured over the kit's own trace and the duration is recorded in the
  diary as the baseline. No speed is promised here.
- Neutral: `pattern`, `simplicity` and `reuse-dry` select the same paths
  today, and so do `security` and `api-crud`, so several rows can match.
  One row per rule is the MVP default, and the question goes to K3's grill.

## More information

- PRD-06 (`.factory/items/PRD-06/prd.md`), slice 1; ticket #875; the
  requirements are `docs/specs/runtime.md` R31 and R43 to R45, and
  `docs/specs/process.md` R37.
- Held by `tests/trace.test.sh` section 22 (the kind table, row for row) and
  section 42 (the outcome words, the evidence keys, and the record over a
  fixture repository: one row per area, first-parent paths, the 20-landing
  window, the fix window, the unconfigured case), `tests/lens-slice.test.sh`
  (`--areas`), `tests/trace-skills.test.sh` section 3 (no skill but `/retro`
  calls `record`) and `tests/retro-skill.test.sh` (question 2 prints the
  record before the per-lens counts).
