# ADR-0025: The landing script refuses a shared-layer move with no version bump

- **Status**: Accepted
- **Date**: 2026-10-11
- **Deciders**: the implementer session for #728, on the operator's standing delegation of rulings; the merge of its pull request is the operator's yes
- **Supersedes / amends**: — (a refusal beside ADR-0019's, on another ground; gives hard rule 3's "changing one is a release action" a check at the merge)
- **Superseded by**: —

## Context and problem statement

On 2026-10-10 PR #693 moved shared-layer files — the docs gate's POSIX twin,
its runner, and a new validator joining the manifest — with no `VERSION`
bump, and landed. The checks that catch a missing bump (`self-host.test.sh`'s
release-bound legs) went red on #693 itself, but the landing script did not
refuse it, and main's CI stayed red from 13:53Z until another session's
release landed around 18:05Z. Every PR in between was red only on checks
bound to the release (retro `retro-20261010T194521Z`).

Hard rule 3 makes a shared-layer change a release. A gate that is only red on
the PR can be landed past by hand. The refusal has to sit at the merge.

## Decision drivers

- The refusal sits where the merge happens, like ADR-0019's.
- What the script compares is what the merge lands: the PR's own diff, from
  its merge base. Comparing against the base branch's tip would read a
  release that landed on main since as this PR's bump.
- A file joining or leaving the manifest is a shared-layer change too.
- When the check cannot read the PR's diff it does not let the PR through.

## Considered options

1. **Refuse in the landing script on the PR's diff, read with git, with no
   override** *(chosen)*.
2. **An override, `--no-bump '<reason>'`**: rejected. Hard rule 3 has no
   exception that skips a bump. A move with no bump leaves main red on the
   release-bound legs until a release lands. So an override only lets the red
   onto main, and that is the incident this record exists to prevent.
3. **Read the diff from the forge (`gh pr diff`)**: rejected. The forge gives
   the changed paths but not the `files:` list at either end. The script
   would still need git for `VERSION`, and two sources for one question can
   disagree.
4. **Leave it to the release-bound CI checks**: rejected. They were red on
   #693 and it landed anyway. A required check would also hold every PR
   behind an untagged release, which is a different question.

## Decision outcome

1. **What counts as moved.** The script fetches the base branch and
   `refs/pull/<N>/head`. It takes the merge base of `origin/<base>` and the
   head commit the forge names. A path is moved when
   `git diff --name-only --no-renames <merge base> <head>` lists it. A rename
   counts as both of its paths.
2. **The manifest is read at both ends.** The listed paths are the union of
   `VERSION`'s `files:` list at the merge base and at the head, read through
   `scripts/manifest.lib.sh`. So a file that joins the manifest or leaves it
   counts as listed.
3. **A bump** is a `shared-layer:` line at the head that is a version (the
   same shape step 2b tags) and differs from the merge base's.
4. **The refusal.** If a moved path is listed and there is no bump, the
   script exits 2. Nothing is merged and nothing is recorded. stderr names
   each moved listed path, both shared-layer values, and hard rule 3, and
   says what a release owes. The check is the same under `--train`, under
   `--no-iteration` and `--no-review`, and with the trace unconfigured: it
   reads git, not the trace.
5. **An unread diff refuses.** The script refuses the same way, naming what
   failed, when any of these fails: the forge names no head commit, the
   fetch fails, there is no merge base, the diff fails, or `VERSION` cannot
   be read at either end.
6. **Where it runs.** The check comes after ADR-0019's checks (step 1b) and
   before the `pr.open` write (step 1d). So a PR that fails both checks is
   named for the iteration and review first.

## Consequences

- **Good**: a shared-layer change with no bump cannot reach main through the
  landing script or the train.
- **Bad / trade-off**: every landing now needs to fetch the PR's head ref.
  With no network, or on a forge with no `refs/pull/*`, every landing is
  refused. Both are this kit's own setup, on GitHub.
- **Honest limitation**: a bare `gh pr merge` still bypasses the check, as it
  bypasses ADR-0019's. Hard rule 7 and `/merge-train` are what route merges
  through the script.

## More information

- Built by #728. `tests/land.test.sh` section 16 covers each case against a
  stub forge and a stub git: refused, bumped, nothing listed moved, joining,
  leaving, a non-version line, the overrides, `--train`, unread diffs, and
  the trace unconfigured.
