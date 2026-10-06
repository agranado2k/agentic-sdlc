# ADR-0014: A release is tagged by its landing, before main is judged

- **Status**: Accepted
- **Date**: 2026-10-06
- **Deciders**: the planner session for #509, on the operator's (Arthur Granado) standing delegation of rulings
- **Supersedes / amends**: — (gives hard rule 3's definition of a landed release, in the root `AGENTS.md`, its mechanism; nothing in that definition changes)
- **Superseded by**: —

## Context and problem statement

Hard rule 3 says a release is not landed until the bump's merge commit
carries its `v<version>` tag, and `tests/self-host.test.sh` F3 holds that
line: on a push to main, a declared shared-layer version with no tag is red.
The tag can only go on the merge commit once the merge exists — and main's
post-merge Kit CI starts on that same merge push. So every release turned
main red: found on 0.33.0, 0.36.0 and 0.42.0 (2026-10-01 to 2026-10-02,
issue #509), then five releases in a row on 2026-10-05, 0.49.0 to 0.54.0,
each landed by `sh scripts/land.kit.sh <PR>`. Each time the landing script
waited for main's workflows, saw F3 fail, printed "a post-merge workflow
failed on main — land nothing else", recorded the failure, and exited 1; the
operator then tagged the merge commit by hand (`git tag -a v<ver> <merge
sha>`, pushed), re-ran the failed run (`gh run rerun <id> --failed`), and
main went green. Five out of five: a false red the procedure itself made,
and a manual step every release.

The trace learned the wrong thing too: `merge.land` said
`data.workflows=failure` for landings that were, minutes later, sound — and
`/merge-train`'s hard rule 6 would have stopped a train dead on the same red.

## Decision drivers

- **Hard rule 3 stays exactly as strong.** The tag is on the merge commit,
  and an untagged bump is red on main — a release no consumer can reach.
- **No false red, no manual step.** A release landed through the sanctioned
  path leaves main green unaided, or says precisely why not.
- **The record is true.** `merge.land` reports the verdict of a run that
  could pass, and whether the release was tagged.
- **No new CI machinery.** The fix lives in the landing, which already holds
  the operator's name and credentials, not in a scheduled job or a weaker
  check.

## Considered options

1. **The landing tags a release merge itself, before it waits, and re-runs
   once what failed untagged** *(chosen)* — the operator's by-hand repair,
   moved into the landing script and `/merge-train`, in the order that makes
   it unnecessary.
2. **F3 says "tag pending" on the bump's own merge push, and a scheduled or
   tag-push run holds the line** — rejected: it weakens the forcing function
   the check exists for (main green with no tag), moves the red to a later
   run nobody is watching, and needs a new scheduled workflow to replace
   what the push run did.
3. **Tag the PR head before the merge, move the tag to the merge commit
   after** — rejected: a tag that moves is a release that changes under a
   consumer who fetched it in between; a merge-commit merge never makes the
   head the merge commit, so the move is always needed; and it is two
   forge writes for what the chosen option does in one.

## Decision outcome

Chosen: **the landing tags a release merge before it waits**.

1. **A release is a merge that moves `VERSION`'s `shared-layer:` line**,
   read from the merge commit against its first parent. Only a value of
   version shape is a release; anything else is never typed into a tag.
2. **The landing tags the merge commit `v<version>` right after the merge
   and before it waits for main's workflows** — an annotated tag cut with the
   operator's own git config (signing included), pushed to origin. The tag
   still lands on the merge commit, as hard rule 3 requires; only its timing
   moved, from after the wait to before it.
3. **A tag origin already holds is never moved.** One naming the merge
   commit is kept as the tag; one naming any other commit leaves the release
   not landed, reported with the commit it names.
4. **After the tag is on origin, each run that failed is re-run once — its
   failed jobs only — and only that second result is judged.** A run on the
   merge push may have started before the tag existed; its second attempt
   cannot. Once, never twice: a release still red after its re-run is a real
   failure, and stops the landing as any other.
5. **An untagged merge's red is never re-run.** With no tag on origin a
   re-run fails the same way, and a non-release merge's red is its verdict.
6. **A release whose tag is not on origin is merged, not landed**: the
   landing script exits 1, names the command to finish it by hand, and
   records `data.tagged=no`. A release's `merge.land` carries
   `data.release`, `data.tagged` and `data.reruns`.
7. **`/merge-train` agrees**: a train landing a release tags it at the
   merge, before its post-merge wait, and judges main after the one re-run.
   The landing script (`scripts/land.kit.sh`) is the mechanism; the train's
   step 4 says the same in prose, and its hard rule 6 reads the judged
   result.
8. **Explicit non-goal**: this does not change F3, nor what counts as a
   release, nor who may land one. The landing still carries a human's name
   (shared invariant §7) — the tag rides on the merge the operator chose to
   make, never on an agent's initiative.

## Consequences

- **Good**: a release landed through the landing script leaves main green
  with no manual step; the trace's `merge.land` stops recording a failure
  the procedure manufactured; F3 keeps its full strength.
- **Bad / trade-off**: the landing script now holds a git write — a tag
  and its push — beside its forge calls, and needs a checkout with origin's
  base branch fetchable. A run with no push right to tags reports the
  release not landed instead of finishing it.
- **Neutral**: the re-run makes a release's landing take one CI cycle
  longer when the first run raced the tag.
- **Honest limitation**: the re-run is blind to *why* a run failed. A
  release that also broke something real is re-run once before the landing
  says so — one wasted cycle, never a masked failure, because the second
  result is judged. A run that started after the tag and still failed is
  re-run too, for the same single cycle.

## More information

- Implemented in: #509 — `scripts/land.kit.sh` step 2b and step 3,
  `tests/land.test.sh` section 8, `.agents/skills/merge-train/SKILL.md`
  step 4 and step 5.
- Related: hard rule 3 in the root `AGENTS.md`; `tests/self-host.test.sh`
  F3; ADR-0008 (the trace the landing writes to).
