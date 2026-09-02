# ADR-0003: The kit carries its own tier-to-model mapping, and never ships it

- **Status**: Accepted
- **Date**: 2026-09-02
- **Deciders**: Arthur Granado (operator); recorded by the first housekeeping pass, item 3
- **Supersedes / amends**: supersedes the index's diary-recorded decision of 2026-08-27, "the kit's `scripts/agents.config.sh` stays unmapped — the kit names no model anywhere, including in its own copy of the tier mapping" (the practice dates from that day; this record is the supersession the index owed); amends ADR-0001 §4 in one respect — five records under `docs/adr/` now, not four, and bootstrap's kit-own list strips this one too
- **Superseded by**: —

## Context and problem statement

The kit ships a capability-tier resolver and an empty mapping, by principle:
model identifiers rot on a vendor's schedule, and a kit that shipped one would
ship a standing instruction with a timer on it. On 2026-08-27 the index
recorded, as a diary-level decision, that this extended to the kit's own copy:
the kit names no model anywhere.

The same day the kit started following its own framework, and the cost of
that decision showed up inside it: every subagent this repo spawns — a
reviewer in fresh context, a planner's exploration, a mechanical fan-out —
inherited the session's model regardless of the tier its ticket was stamped
with. That is the exact blindness the tier mechanism exists to remove,
happening in the tool that preaches it. A kit-only mapping was added that day,
the diary recorded it, and the root manual gained hard rule 10 — but the index
line was never marked superseded. The first housekeeping pass (2026-09-02) found a binding index
line contradicted by a file with five model identifiers in it and no record
of the reversal.

## Decision drivers

- The shipped principle must hold: no consumer receives a model name from the
  kit.
- The kit's own sessions must run tiers as their tickets stamp them, or the
  kit does not practise what it ships.
- A reversal is a new record, never an edit to the old one (the index's own
  convention).
- Model identifiers rot; whatever carries them must say so and be re-checked.

## Considered options

1. **A kit-only mapping, never shipped** *(chosen)* — the shape clauses 2
   and 3 below record.
2. **Keep the kit unmapped** — rejected: every kit session's subagents run on
   the session's model, and the reviewer tier in particular becomes an
   editorial pass on the implementer's own model.
3. **Map the shipped config** — rejected: it violates the shipped principle;
   a consumer would inherit rotting identifiers and a vendor.
4. **Map through environment only, no file** — rejected: an environment
   prefix typed by hand on every spawn is the drift the wrapper exists to
   remove.

## Decision outcome

Chosen: **a kit-only mapping, never shipped**.

1. `scripts/agents.config.sh` ships empty and stays empty. Nothing the kit
   ships names a model.
2. `scripts/agents.kit.config.sh` maps the four tiers and the `content`
   domain for this repository only. It is on bootstrap's kit-only deletion
   list and never reaches a consumer. Its identifiers rot on the vendor's
   schedule; its header carries the last-checked date.
3. `scripts/agents.kit.sh` is the wrapper that sets the resolver's config
   seam and delegates. In this repository a skill's literal
   `sh scripts/agents.lib.sh <tier>` is replaced by it every time — root
   manual hard rule 10 — because skills ship unstamped and may not name a
   kit-only file.
4. The policy behind the mapping, as the root manual already states it:
   plan on the strongest model available; execute per tier and per domain;
   the reviewer is never the same model that implemented. How that rule
   holds when the session itself implemented is wired and checked by its
   own ticket, not decided here.
5. **Explicit non-goal**: this record does not choose models. The identifiers
   are data in the kit-only file and rot on their own schedule.

## Consequences

- **Good**: the kit's own tickets run on the tiers they were stamped with,
  and its reviews are adversarial by construction rather than by hope.
- **Bad / trade-off**: two config files with one shape, and a hard rule that
  exists only to say the shipped command is wrong here. Both are the price of
  keeping the shipped file empty.
- **Neutral**: a consumer sees nothing of this; their resolver, config and
  skills are unchanged.
- **Honest limitation**: nothing owns the re-check of the mapping's
  identifiers — no gate, no checklist item; the header's last-checked date is
  a note, not a rule. A rotten identifier fails at spawn time, which is later
  than a reader would like.

## More information

- Implemented in: the diary entry of 2026-08-27 ("The kit maps its own
  capability tiers"), PR #50's review, root manual hard rule 10; recorded by
  ticket #133 of PRD #124.
- Related: ADR-0001 (the kit follows its own framework); the root manual's
  "Capability tiers" section.
