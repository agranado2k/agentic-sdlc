# ADR-0029: A frontier's session cap is held to the vendor's usage window

- **Status**: Accepted
- **Date**: 2026-10-14
- **Deciders**: the planner session for #776, under the operator's delegation of rulings; the merge of its pull request is the operator's yes
- **Supersedes / amends**: refines the session cap `/to-tickets` states at its hand-off (#483, #510), which no record held until now; builds on ADR-0003 (policy as data, the shipped file empty and the kit's own value in its twin)
- **Superseded by**: —

## Context and problem statement

`/to-tickets` states a frontier's **session cap** at its hand-off. It is the
host's concurrent-subagent limit divided by the seven lenses one `/review-pr`
spawns, rounded down and never below one. That bound keeps lenses from being
refused at the host's slot limit. It says nothing about the vendor's **usage
window**: the metered allowance a session draws on, which, once spent, stops
every session drawing on it at the same moment.

In PRD #742's wave that happened five times. Nineteen runs ended stopped,
twenty spawns never ended, and six tickets had to be resumed (retro
`retro-20261014T104726Z`). On 2026-10-14 another stop killed three sessions
at once. The subagent cap had allowed every one of those sessions. The
operator's working rule since then is at most three parallel sessions, with
one reviewer per re-review.

The ticket asks for the window as a policy value, read by the frontier rule
and never written into the skill.

## Decision drivers

- **Policy is data, not prose.** A vendor's window and a plan's size are the
  operator's facts. They differ per vendor and per plan, and they move on the
  vendor's schedule. A skill ships unchanged to every project, so it cannot
  carry the number (ADR-0003, and the hand-off's own "never a number this
  skill names").
- **Unset is a working state.** A project that has not stated a window keeps
  today's cap exactly.
- **A rule with no failing check is a claim** (shared invariant §8). The cap
  should be computed by something a suite can run, not only described.
- **One reading of the policy.** Skills never read a value out of a policy
  file by hand; the resolver that already knows where the policy is answers.

## Considered options

1. **A window value in the agents policy, applied by a resolver form
   `--session-cap <n>` that prints the lower of `<n>` and the window**
   *(chosen)*.
2. **A second line in the workflow article beside the subagent limit.**
   Rejected: the article is prose a session reads by eye, and the ticket asks
   for a policy file. It would also leave the "lower of the two" as prose with
   no command a suite can run.
3. **A new policy file for session sizing.** Rejected: one more file for one
   value, and a second place that would need its own kit twin and its own
   resolution order. The agents policy already maps tiers onto one vendor's
   models, and the window is that vendor's.
4. **Have the resolver compute the whole cap from the subagent limit.**
   Rejected: the divisor is `/review-pr`'s roster, which the suite reads from
   that skill. A copy of seven inside the resolver would drift from the
   roster without a red test.

## Decision outcome

Chosen: **option 1.**

1. **`AGENT_WINDOW_SESSIONS`** in the agents policy names the most
   review-bearing sessions (an `/implement` that ends at a `/review-pr`) one
   usage window carries. `scripts/agents.config.sh` ships it **empty**. The
   kit's own twins, `scripts/agents.kit.config.sh` and
   `scripts/agents.kit.codex.config.sh`, carry **3**, the operator's working
   rule.
2. **`sh scripts/agents.lib.sh --session-cap <n>`**, where `<n>` is the cap
   the subagent limit gave, prints the lower of `<n>` and the window. When the
   policy states no window, or no policy exists, it prints `<n>`. It reads no
   model value, and `--ids` does not list the window.
3. **Both numbers must be whole numbers of at least one.** Anything else, in
   the argument or in the policy, is exit 2 with nothing printed and the
   variable named. A misspelt window read as no window would be no bound, in
   silence. A named policy that is missing is exit 2, as it is for a tier.
4. **`/to-tickets`' hand-off runs it.** The cap from the subagent limit is
   computed as before. That cap is then held to the window through the
   command, and the hand-off says which bound held. A refusal is a policy to
   repair, said at the quiz, and until it is repaired the safe reading is one
   session at a time.
5. **In this repository the command is the kit wrapper's**
   (`sh scripts/agents.kit.sh --session-cap <n>`, hard rule 10), which passes
   the form through to the policy it picked.

## Consequences

- **Good**: a frontier opened by `/to-tickets` here runs at most three
  review-bearing sessions, whatever the host's slot limit allows.
- **Good**: the rule is executable. `tests/agents-tiers.test.sh` drives the
  resolver form, and `tests/spec-skills.test.sh` runs the command as the
  hand-off writes it and shows it caps at the window when the window is the
  lower.
- **Bad / trade-off**: `scripts/agents.lib.sh` is shared layer, so the form
  ships in a release (0.77.0), with an `UPDATING.md` entry.
- **Honest limitation**: one value per policy, not one per vendor. A project
  whose tiers draw on two vendors' windows states the tighter one. The
  per-harness policies the kit keeps (Claude Code and Codex) each carry
  their own value.
- **Honest limitation**: the window bounds how many sessions start together,
  not how much each one spends. A single long session can still spend a
  window alone. The number is the operator's measured rule, and `/retro`'s
  stopped-run counts are where it is revisited.

## More information

- Built for #776, from the retro of 2026-10-14 (`retro-20261014T104726Z`).
- Held by `tests/agents-tiers.test.sh` ("--session-cap: the frontier's cap
  held to the usage window") and `tests/spec-skills.test.sh` (the hand-off's
  usage-window leg).
