# ADR-0031: A subagent in its parent's checkout runs detached

- **Status**: Accepted
- **Date**: 2026-10-14
- **Deciders**: the implementer session for #782, under the operator's delegation of rulings; the merge of its pull request is the operator's yes
- **Supersedes / amends**: applies ADR-0026 clause 2 (`begin --detached`) to `/pr-iterate`'s re-reviewer; changes no script
- **Superseded by**: —

## Context and problem statement

A run stack is keyed by checkout and session (ADR-0024 clause 5), so a
subagent working in its parent's checkout shares its parent's stack. On
PR #781, `/pr-iterate`'s re-reviewer began its review-pr run there, as #769
prescribes, and could not end it by id: its parent's run sat above it, and
`end <run>` closes only the top of the stack (#543). A stack is last in,
first out. A parent and a subagent it does not wait on are not, and while
the child's run is on top every line the parent writes carries the child's
run.

## Decision drivers

- **The parent's stack stays intact.** A child's begin and end move none
  of the parent's runs, and none of the parent's lines take the child's run.
- **The child ends its own run by id, whatever is on the stack.**
- **No release for a rule the trace already keeps.**

## Considered options

1. **The child begins detached** *(chosen)*: `begin --detached` puts its
   run on no stack and in the registry, every other trace line of the
   review carries it by `TRACE_RUN=<id>`, and `end <id>` closes it from
   anywhere, with the parent its entry names.
2. **Let `end <run>` take a run out of the middle of a stack.** Rejected:
   it changes `scripts/trace.sh`, a shared-layer release, and leaves the
   shared stack in place, so the parent's lines still carry the child's run
   while it is on top.
3. **The re-reviewer works in a checkout of its own.** Rejected: a second
   worktree per re-review costs a checkout and its cleanup for what is a
   read, and the spawn would have to say where to work, which a skill
   cannot hold to anything.

## Decision outcome

Chosen: **option 1.**

1. `/pr-iterate`'s spawn prompt for the re-reviewer says, in those words,
   to begin `sh scripts/trace.sh begin --detached review-pr
   subject=pr:#<N> || :` in place of `/review-pr`'s own `begin`, never as
   well as it, to put `TRACE_RUN=<the run id that begin printed>` before
   every other trace line of the review, and to end it by that id. A
   reviewer that ran both would leave a stack run above its parent's, and
   the parent's `end` would be refused as on #781.
2. This record changes nothing for a re-review the parent runs itself,
   with no subagent. That review follows `/review-pr`'s own `begin` on the
   stack. It is the session's own nested run, so the stack stays last in,
   first out.

## Consequences

- **Good**: the child's run closes by id under any stack, and its
  `run.end` names the parent run it was begun under.
- **Good**: no change to `scripts/trace.sh`, so no release.
- **Bad / trade-off**: a run begun from an agent harness's one-command
  shell reads `stale` in `runs` while it is open (ADR-0026's honest
  limitation). Stale stays evidence, not a verdict.
- **Bad / trade-off**: a line the child writes without the `TRACE_RUN`
  prefix carries the stack's top, the parent's run.
- **Honest limitation**: `/pr-iterate` step 2's reviewer still runs
  `/review-pr`'s own `begin` on the shared stack; it is spawned and waited
  on, so the stack stays last in, first out for it.

## More information

- Built for #782, from the retro of 2026-10-14 (PR #781).
- Held by `tests/trace.test.sh` section 39 and
  `tests/trace-skills.test.sh` section 31.
- Related: ADR-0026, ADR-0024 clause 5, #543, #769, #770.
