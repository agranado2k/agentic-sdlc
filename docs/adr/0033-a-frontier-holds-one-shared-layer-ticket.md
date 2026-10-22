# ADR-0033: A frontier holds one shared-layer ticket

- **Status**: Accepted
- **Date**: 2026-10-22
- **Deciders**: the implementer session for #833, on the operator's standing delegation of rulings; the merge of its pull request is the operator's yes
- **Supersedes / amends**: — (a `/to-tickets` rule beside hard rule 3 and ADR-0025, on the ticket side of the same release)
- **Superseded by**: —

## Context and problem statement

Hard rule 3 makes every change to a file `VERSION` lists a release: the
`shared-layer:` line is bumped and `UPDATING.md` gains an entry. ADR-0025
makes the landing script refuse a move with no bump, with no override.

Retro `retro-20261022T135553Z` found what that costs when a decomposition puts
several such tickets on one frontier. They run in parallel, each bumps the same
line from the same base, and the first to land turns every other one into a
conflict. The trace held 8 `pr.iterate data.cause=conflict` iterations on 7
PRs (#805 #806 #807×2 #808 #810 #811 #825), release-bound red on #808 and #821,
and 8 releases (v0.79.0 to v0.86.0) in 2 days. The parallel frontier's lead
times were 5 to 9 h, against under 1.5 h for the serial tail.

Ticket #833 asked `/to-tickets` to pick one of two forms and record it: at most
one shared-layer ticket per frontier, or the frontier's bumps deferred to one
release ticket at its tail.

## Decision drivers

- The base branch stays green between landings: no ticket may land a
  shared-layer move that leaves the release-bound checks red.
- The rule works with ADR-0025 as it stands, not by reversing it.
- The rule lives where the frontier is made: in the decomposition's edges,
  read by `/implement` and the hand-off with no new mechanism.

## Considered options

1. **At most one shared-layer ticket per frontier; a second is chained with a
   `Blocked by:` edge** *(chosen)*. Each release is cut from a base that
   already carries the one before it.
2. **Defer the bumps to one release ticket at the frontier's tail**: rejected.
   Every ticket before the tail moves a listed file with no bump. ADR-0025's
   landing script refuses each of them, with no override; and if one landed
   by another path, main would be red on the release-bound checks until the
   tail landed, the incident ADR-0025 exists to prevent. Taking this form
   would mean reversing ADR-0025 for a saving of a few version numbers.
3. **No rule; leave the conflicts to `/pr-iterate`**: rejected. That is the
   measured state the retro reported.

## Decision outcome

Chosen: **option 1**.

1. **The rule.** `/to-tickets` rule 16, "One shared-layer ticket per
   frontier": a frontier holds at most one ticket that moves a file `VERSION`
   lists, or `VERSION` itself.
2. **The chain.** Where two such tickets would share a frontier, the later one
   carries a `Blocked by:` edge on the earlier, in the order the feedback-first
   rule chose.
3. **The hand-off.** Step 5's sequencing honours the rule: a shared-layer
   ticket on the frontier is not named to start while another release's pull
   request is open, another wave's included. It waits, as a ticket past the
   session cap does.
4. **Held by** `tests/spec-skills.test.sh`, banner "The release frontier".
5. **Explicit non-goal**: this does not change how a release is cut, tagged
   or landed (hard rule 3, ADR-0015, ADR-0025), and it does not serialise
   tickets that move no listed file.

## Consequences

- **Good**: a decomposition no longer races releases against each other; each
  shared-layer ticket bumps from a base that already holds the last release.
- **Bad / trade-off**: shared-layer tickets of one wave now run one at a time,
  so a wave with many of them is slower end to end than its frontier suggests.
  The retro's lead times say the serial tail was the faster one anyway.
- **Honest limitation**: the rule is text a planner obeys at decomposition
  time. A ticket whose shared-layer move nobody foresaw is not caught by it;
  the landing script's ADR-0025 refusal is still the check at the merge. The
  next `/retro`'s before-and-after section judges the rule by
  `kind=pr.iterate data.cause=conflict`.

## More information

- Implemented in: #833
- Related: hard rule 3, ADR-0025, ADR-0029 (the session cap the hand-off
  holds), retro `retro-20261022T135553Z`
