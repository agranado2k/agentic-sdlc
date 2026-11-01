# ADR-0041: In a factory project, a configuration value the factory defines is read from its manifest, at the base too

- **Status**: Accepted
- **Date**: 2026-11-01
- **Deciders**: the operator, 2026-10-31, on the D-08 factory operator's widened option (a) (PRD-12 §8, process/R226 and process/R227), and on the adoption date's one home (PR #948, PRD-14 §8: only a factory project has approved tests); the shape below by the implementer session for #959 under the operator's delegation of rulings, the no-kit-home answer by the coordinating session's ruling on it; the merge of its pull request is the operator's yes
- **Supersedes / amends**: amends ADR-0039 clause 2 (the judging set gains `.factory/project.yaml`) and clause 3 (a fourth question, `value`)
- **Superseded by**: —

## Context and problem statement

A repository that plans in the software factory holds `.factory/project.yaml`,
the factory's project manifest, at its git top level. Some configuration the
kit reads is also defined there. The first is the acceptance-test adoption
date (PRD-14): the factory's `acceptance_tests_since` decides which tickets
owe approved tests, and the kit's acceptance guard reads the same date. Two
homes for one value drift, and a judge reading the wrong one either holds a
ticket the factory let into build or lets through one it held.

The operator ruled the value has one home in a factory project, the factory's
key, and the kit's own policy file is read for it only where the repository is
not a factory project (R226) — for a value the kit itself defines there. The
adoption date is not one: only a factory project has approved tests, so a
repository with no manifest has no adoption date and owes nothing (PRD-14 §8,
2026-10-31). Where a judge reads such a value at a base ref,
the manifest is read at that ref through the policy reader and fails closed as
it does (R227), so a pull request cannot move its own adoption date.

Inventory at this record: the kit reads no other value the factory defines.
The factory's `test_tier_since` has no kit reader, and `agents.default` names
an agent harness, which no kit policy file holds. The adoption date is the
first and only value, and its acceptance guard is not built yet.

## Decision drivers

- **One home per value**, chosen by the repository's shape, never by which
  file a caller happened to open.
- **No pull request moves its own judge** (ADR-0039): the manifest is read at
  the base, and a branch cannot change which home is read.
- **A lost value is not permission**: a manifest the base lacks, or a value
  out of shape, fails closed and never falls back to the kit's policy file.
- **The next value costs one line**, not a second reader.

## Considered options

1. **One `value` question in the policy reader, over a registry of values in
   the reader itself** *(chosen)*.
2. **Each judge reads the manifest itself** — rejected: every judge would
   re-implement the base read, the factory-project test and the fail-closed
   shape, the duplication ADR-0039 exists to prevent.
3. **The registry in a consumer-owned policy file** (the risk policy) —
   rejected: R226 is a kit rule, not a preference; a consumer dropping an
   entry would send a factory-defined value back to the kit's file.
4. **A kit-side home for the adoption date** (a guards-policy variable read
   outside a factory project) — rejected: the operator ruled the date lives
   only in the manifest (PRD-14 §8), and outside a factory project nothing is
   owed, so a kit variable would be a setting no judge reads.

## Decision outcome

Chosen: **`sh scripts/policy.sh value <name> [--base <ref>]`**.

1. **The manifest is a judging file.** `.factory/project.yaml` joins ADR-0039's
   fixed judging set by its whole path, so `read` copies it at a base and
   `touched` reports a pull request that adds, edits or deletes it. No other
   file under `.factory/` is in the set.
2. **A factory project**, for a read at a base, is one whose base commit or
   HEAD commit holds the manifest — either, so a branch that deletes it is
   still read from the base's manifest, and one that adds it fails closed
   (`fail-closed missing .factory/project.yaml`) instead of reading the kit's
   file. With no base, it is the git top level's working tree holding it. A
   `.factory/` folder without the manifest is not one.
3. **The read.** In a factory project the value is the manifest's top-level key
   (`<key>: <value>`, the value bare or quoted, a trailing comment allowed).
   With `--base` it is read from git's objects at the base through the
   reader's `fetch`, so `no-base`, `missing`, `unreadable` and `invalid` mean
   what ADR-0039 says. With no base it reads the working tree — for a local
   session; a judge always passes `--base`.
4. **The answer** in a factory project is one line, `<name> <value>` or
   `<name> unset` (the key absent, or written with no value), exit 0. Outside
   one it is nothing on stdout and exit 0: the value has no home there, no
   kit file stands in, and a caller's environment is never read. A value out
   of shape — for a date, anything but one real `YYYY-MM-DD` — or a key
   written twice is `fail-closed invalid .factory/project.yaml`, exit 3. An
   unknown name is exit 2.
5. **The registry.** `factory_value` in `scripts/policy.sh` lists each value:
   its name and the manifest key. Today one: `acceptance-tests-since`,
   manifest `acceptance_tests_since`.
6. **The rule for the next value.** When the kit comes to read a value the
   factory also defines, it gains a registry line in the same change, and
   every judge reads it through `value --base`, treating any exit other than
   0 as its strictest path. Only a value the kit itself defines for a
   repository that is no factory project gains a kit-side home, read there
   alone and never in a factory project. No judge reads the manifest
   directly.

## Consequences

- **Good**: PRD-14's acceptance guard reads its date through one call that
  already decides whether the repository is a factory project, reads the
  date at the base and fails closed; the date has one home.
- **Bad / trade-off**: a repository adopting the factory fails closed on any
  registered value until the manifest lands on its base; the adoption pull
  request takes the strictest path for that judge. The working-tree read is a
  second mode of a reader that was base-only, kept to `value`.
- **Neutral**: `scripts/policy.sh` is shared layer, so this moves a release.

## Confirmation

`tests/factory-config.test.sh` holds the read in fixture factory projects whose
guards policy sets a date of its own that is never read, at the working tree
and at the base, the same fixture without the manifest (nothing printed), and
every fail-closed case;
`tests/policy.test.sh` holds the manifest in the judging set.
