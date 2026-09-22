# ADR-0007: A reviewer resolves against the session that asks, and never to its own model

- **Status**: Accepted
- **Date**: 2026-09-21
- **Deciders**: Arthur Granado (operator), at the `/implement` stop for #224
- **Supersedes / amends**: amends ADR-0003 in one respect — the kit's mapping is no longer the whole answer for the reviewer tier; the caller's model is the third input
- **Superseded by**: — (amended 2026-09-22: the shared-resolver step was written as 0.21.0's; 0.21.0 shipped without it, so the step is #226's whenever that lands — the decision is unchanged, only its schedule)

## Context and problem statement

ADR-0003 gave the kit its own tier-to-model mapping, and #144 gave that
mapping a `self-implemented` domain on the reviewer tier: the situation where
the session itself wrote the diff, on the model the reviewer tier maps to, so
the reviewer needs a second answer. The mapping answers it with one fixed
model — chosen on the assumption that a session runs on the planner's model,
so "self-implemented" means "not that one".

PR #222 was built by a session running on the model that fixed answer names.
`sh scripts/agents.kit.sh reviewer self-implemented` therefore resolved to the
implementer's own model: the review would have been an editorial pass wearing
a second hat, which is the exact outcome the domain exists to prevent. The
session noticed and used the plain reviewer tier by hand; nothing in the
resolver, the wrapper or the config would have. The policy in the root manual
— "the reviewer is never the same model that implemented" — had a mechanism
that held for one session model and silently failed for the other.

## Decision drivers

- The reviewer rule is a **relation between two models** (the reviewer's and
  the implementer's), and the implementer's is the session's — a fact only
  the caller has. A policy file that answers without it can only ever be right by
  assumption.
- The kit names no model anywhere it ships (ADR-0003), and its own mapping is
  small on purpose. A matrix of "the alternative for each model a session can
  run on" grows a line per model and repeats the assumption once per row.
- An unmapped tier is a working state today: the resolver warns once, prints
  nothing, and the spawn inherits the session. A refusal should have the same
  shape, so a caller that already handles "nothing" handles this too.
- `scripts/agents.lib.sh` is shared layer. Changing it is a release action
  (root manual, hard rule 3) with a transcript re-capture this host cannot
  run; #224 did not budget a release, and 0.21.0 already owes a note.

## Considered options

1. **The resolver refuses when equal.** The caller names its model in
   `AGENT_SESSION_MODEL`; when the reviewer answer equals it, warn once and
   fall back to the plain reviewer tier; when that too equals it, warn that
   the review will share the author's model and print nothing. Policy file
   unchanged.
2. **The mapping is relative to the caller.** The policy file names the
   alternative per session model
   (`AGENT_TIER_REVIEWER_SELF_IMPLEMENTED_FROM_<MODEL>`); the resolver picks
   the row by `AGENT_SESSION_MODEL`. Explicit, but a matrix that must be kept
   for every model a session might run on.
3. **Leave it to the session.** Document the gotcha and trust the report to
   say which tier reviewed. Cheapest, and exactly the state that failed.

## Decision outcome

**Option 1**, in two steps that keep hard rule 3 intact:

- **Now, in the kit-only wrapper.** `scripts/agents.kit.sh` — never shipped —
  implements the refusal for the reviewer tier when `AGENT_SESSION_MODEL` is
  set, and is the `exec` it always was otherwise. The tiers suite drives the
  equal, fallback-also-equal, unequal, non-reviewer, quiet and exit-code cases.
- **In a later release, in the shared resolver.** The same rule moves into
  `scripts/agents.lib.sh`, where every consumer's `self-implemented` mapping
  has the same blind spot; the release ticket carries it, with the `VERSION`
  note, the `UPDATING.md` entry and the transcript re-capture that a
  shared-layer change owes. Until then the wrapper is the kit's own fix and a
  consumer's resolver behaves as it did.

The value compared is the **word the policy file uses**, not a vendor's full
identifier: `AGENT_SESSION_MODEL=opus` matches `AGENT_TIER_…='opus'`. The
session says what it runs on in the policy file's own vocabulary; that is the one
fact it holds that the policy file does not.

## Consequences

- A session on any model gets a reviewer that differs, or a warning it can
  quote — never a silent same-model review. The `/implement` report's "which
  tier reviewed" line has a mechanism behind it.
- A caller that never sets `AGENT_SESSION_MODEL` is exactly where it was. The
  variable is a courtesy the session pays, not a requirement; a session that
  does not know its model cannot be refused, and the warning path is the
  fallback the resolver already had.
- The glossary's **task domain** entry gains the third input; the root manual's
  "Capability tiers" section says what a kit session sets before it spawns a
  reviewer.
- Two definitions of one rule exist until 0.21.0 lands — the wrapper's and,
  then, the resolver's. The release ticket retires the wrapper's copy in the
  same change that ships the resolver's.

## More information

- Filed as #224 after PR #222's review; the workaround the session used is
  the fallback this record makes automatic.
- ADR-0003 (the mapping), ADR-0005 (the agent-harness axis — a third axis this
  record does not touch: the harness prefix on a value is compared as part of
  the word).
