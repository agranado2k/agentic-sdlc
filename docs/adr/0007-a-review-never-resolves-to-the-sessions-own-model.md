# ADR-0007: A reviewer resolves against the session that asks, and never to its own model

- **Status**: Accepted
- **Date**: 2026-09-21
- **Deciders**: Arthur Granado (operator), at the `/implement` stop for #224
- **Supersedes / amends**: amends ADR-0003 in one respect — the kit's mapping is no longer the whole answer for the reviewer tier; the caller's model is the third input
- **Superseded by**: ADR-0020 for the kit's own policy, in one respect — the 2026-10-05 amendment (#546); the rest binds (amended 2026-09-23: what is compared is the MODEL half only, not the harness prefix as this record's More-information line first said; the substitution is of the whole mapping, so a fallback that crosses agent harnesses carries its own, which is why harness mode refuses on the same comparison rather than skipping it. Amended 2026-09-22: the shared-resolver step was written as 0.21.0's; 0.21.0 shipped without it, so the step is #226's whenever that lands — the decision is unchanged, only its schedule. Amended 2026-10-05, #546: a `self-implemented` mapping names a model no session tier runs on, so the refusal is the net and not the route — see the end of this record; the ordered fallback past it is ADR-0013's)

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
  record does not touch).

### Amendment, 2026-10-05 — the `self-implemented` answer is a model no session runs on (#546)

Narrows how a policy file fills the domain this record polices; the refusal,
its input and its fallback are unchanged, so the record is amended in place.
Decided by the planner session for #546, on the operator's standing
delegation of rulings.

**What happened.** The kit's mapping gave `self-implemented` the
implementer's model, chosen when the reviewer and the content domain shared
one model and the implementer had another. On 2026-10-05 every session of the
spec-anchored wave ran on the implementer's model, so the domain answered
each one its own model. The refusal caught that only for a session that set
`AGENT_SESSION_MODEL` in the policy file's pinned id — the spawn word a
session knows itself by matches nothing under the exact comparison above —
and then fell back to the plain reviewer, whose model was out of usage
credits all day. With no next answer, every session overrode the reviewer by
hand with a third model, and two failed outright on the first spawn before
doing so.

**The rule.** A policy that maps `self-implemented` maps it to a model **no
session tier of that policy runs on** — not the planner's, the
implementer's, the mechanical tier's, nor any implementer domain's. A
session's model is one of those; one fixed answer can differ from all of
them only by being none of them; and only then is the answer right for a
session that never says what it runs on, or says it in a word the policy
does not use — the two cases the refusal cannot see. The refusal stays, as
the net for a session that does run on that model.

**The kit's answer**, in `scripts/agents.kit.config.sh`: `claude-sonnet-5-5`
until the cross-vendor reviewer authenticates again, when the other vendor's
model — disjoint from every local session by construction — returns.
`tests/agents-tiers.test.sh` pins the rule against the kit's mapping, not the
id: the answer is no session tier's model, both session models get it with
no refusal, and a session named by its spawn word still gets a model other
than its own.

**Rejected.**

- *Keep the implementer's model and rely on the refusal* — what failed: the
  refusal needs an input nothing sets, in a spelling a session does not
  naturally use, and its only fallback is the plain reviewer, so one
  outage leaves no answer.
- *Map it to the mechanical tier's model* (`claude-opus-5`) — a session
  tier, so a mechanical session would be refused into the plain reviewer
  again; and its in-session spawn word is `opus`, which the harness resolves
  to the implementer's model, so the "different" reviewer would run on the
  author's.
- *Map it to the content model and the plain reviewer to a third* — moves
  the outage onto the plain path without removing it, and undersizes the
  plain reviewer, which no session-model collision forces.
- *Make the mapping relative to the session* (this record's option 2) —
  still rejected for the reason it was: a matrix per session model, and it
  needs the same input the refusal lacks.

**Cost.** The answer is a mid-tier model where a content session used to
get the implementer's; a weaker read, chosen over a stronger one that did
not run. A further answer when this one is refused or unreachable is not a
mapping question: ADR-0013 places it in the shared resolver.
