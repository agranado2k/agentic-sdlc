# ADR-0013: A reviewer's next answer is an ordered fallback in the shared resolver, past what the caller names unreachable

- **Status**: Accepted
- **Date**: 2026-10-05
- **Deciders**: the planner session for #546, on the operator's (Arthur Granado) standing delegation of rulings
- **Supersedes / amends**: — (builds on ADR-0007: its refusal gains a next answer; ADR-0003's mapping stays the policy that names every answer)
- **Superseded by**: —

## Context and problem statement

ADR-0007 gives the reviewer tier exactly one fallback: when the answer it
resolves is the session's own model, the plain reviewer tier. Past that the
resolver prints nothing, and the spawn inherits the session — the
editorial pass the rule exists to prevent, reported rather than prevented.

On 2026-10-05 that one fallback was the only route, and it was unreachable.
The kit's plain reviewer model was out of usage credits all day — every spawn
on it failed with HTTP 429 on its first call — and the cross-vendor reviewer
had been logged out since 2026-10-01. Every session of the wave reviewed on a
third model chosen by hand; two failed a first spawn before choosing it. The
same hole is in every consumer: one reviewer model per policy, and one
vendor's rate limit or expired login away from no review at all.

Two questions, then: is the next answer a mapping matter (the kit's file
alone) or a resolver matter (every project's); and how does the resolver,
which runs offline before the spawn, learn that an answer is unreachable?

## Decision drivers

- **The reviewer rule never answers the session's own model** (ADR-0007),
  however many answers are tried.
- **One definition of a rule.** ADR-0007 ran a kit-wrapper copy and a
  resolver copy until 0.22.0 retired the wrapper's; a second kit-only
  mechanism reopens that.
- **The hole is not the kit's alone.** A consumer's reviewer fails the same
  way, and the kit sells the rule.
- **The resolver is offline POSIX sh.** It runs before the spawn, holds no
  credentials and makes no network call; reachability is learned only when a
  spawn's first call fails.
- **Old callers keep working.** A policy file or caller written before this
  must resolve exactly as it does today.

## Considered options

1. **An ordered fallback list in the shared resolver, reviewer tier only;
   the caller names what it found unreachable** *(chosen)*.
2. **The kit's mapping only** — a fallback variable read by the kit's
   wrapper, `scripts/agents.kit.sh` — rejected: it recreates the two
   definitions 0.22.0 retired, leaves every consumer's hole open, and turns a
   wrapper pinned as a thin `exec` into a second resolver.
3. **No mechanism: re-pin the mapping per outage**, as #423 did for the
   cross-vendor reviewer — rejected as the standing answer: a day-long
   outage then costs a commit, a re-pinned suite and a revert, and the
   sessions in flight before the commit still fall through. It stays the
   interim until option 1 is built.
4. **The resolver probes reachability** — rejected: a probe spends a call,
   needs credentials the resolver must not hold, and still cannot see a rate
   limit that arrives on the next call.
5. **Several ids in the tier's own value** (`AGENT_TIER_REVIEWER='a b'`) —
   rejected: every caller that reads one id, the harness split and the
   `--alias` bridge among them, would read a list; a separate variable leaves
   every existing value meaning what it means.
6. **Fall back to the session's model with a warning** — rejected: that is
   the outcome the rule exists to prevent; it remains only as today's
   reported last resort when every answer is spent.

## Decision outcome

Chosen: **option 1**. The resolver change is a shared-layer release built by
its own ticket (#548); this record decides its contract.

1. **A policy may name an ordered fallback for the reviewer tier** in a new
   variable, `AGENT_TIER_REVIEWER_FALLBACK`: space-separated values, each in
   the shape a tier value already takes (a model, or `<harness>:<model>`).
   Unset or empty, the resolver behaves exactly as it does today.
2. **The caller names what it found unreachable** in
   `AGENT_UNREACHABLE_MODELS`, space-separated, in the policy file's own
   words — the same contract as `AGENT_SESSION_MODEL`: a fact only the
   caller holds, compared exactly, on the model half only. A session that
   saw a spawn fail on its first call (rate limit, authentication, an
   unknown model) re-resolves with that model named.
3. **The walk, reviewer tier only:** the domain answer, then the plain
   reviewer, then each fallback in order; the first candidate that is
   neither the session's model nor named unreachable is the answer, with a
   warning that names what was skipped and why. A spent list prints nothing
   with the warning ADR-0007 already gives — never the session's model.
4. **Other tiers are untouched.** An unreachable planner, implementer or
   mechanical model leaves the spawn inheriting the session, a working state
   that breaks no rule; only the reviewer has a model it must never be.
5. **The kit's mapping fills the list** once the resolver reads it; until
   then the kit's interim is ADR-0007's 2026-10-05 amendment (a
   `self-implemented` model no session runs on) plus option 3's re-pin.
6. **Explicit non-goal:** the resolver never learns reachability by itself,
   never retries, and never records the outage — remembering it across
   sessions is the trace's and the operator's, not the resolver's.

## Consequences

- **Good**: one outage no longer ends in a hand-picked reviewer; the next
  answer is policy, recorded and pinned, and the same in every project.
- **Good**: the rule holds under every path — no candidate equal to the
  session is ever printed.
- **Bad / trade-off**: a shared-layer release (VERSION, UPDATING.md, the
  transcript re-capture), and one more caller-held variable, which nothing
  sets automatically — as nothing sets `AGENT_SESSION_MODEL`.
- **Bad / trade-off**: the session must notice a failed spawn and re-resolve;
  a session that does not is where it was today.
- **Honest limitation**: the fallback cannot make the review cross-vendor
  when every other vendor is down; it only keeps it off the author's model.

## More information

- Decided in #546; built by #548. Evidence: the 2026-10-05 spec-anchored
  wave (PRD #527), every review spawned on the plain reviewer failing with
  HTTP 429, and the cross-vendor reviewer logged out until 2026-10-07.
- Related: ADR-0003 (the mapping), ADR-0005 (`<harness>:<model>` values),
  ADR-0007 and its 2026-10-05 amendment.
