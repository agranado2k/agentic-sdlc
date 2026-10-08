# ADR-0018: Two kit tiers follow a model family, not a pinned id

- **Status**: Accepted
- **Date**: 2026-10-08
- **Deciders**: the operator (Arthur Granado)
- **Supersedes / amends**: amends ADR-0003 in one respect — the kit's own policy pins ids for every tier *except* the two named here; and the cascade's escalation target decided with #586
- **Superseded by**: —

## Context and problem statement

`scripts/agents.kit.config.sh`, the kit's own tier policy, has pinned full model
ids since the 2026-08-27 check: "an alias silently follows the roster … Pinning
means the move is a commit someone made on purpose." That rule has a cost the
operator no longer wants to pay on two tiers. Each time a family ships a new
model, the planner and the mechanical tier keep running the old one until
someone remembers to re-pin. On 2026-10-08 the planner was `claude-fable-5-1`
and the mechanical tier `claude-opus-5`, an Opus a generation behind the
implementer's.

The operator's decision is that the planner runs the newest Opus and the
mechanical tier the newest Sonnet, whichever models those are at the time.
Every other tier stays pinned.

Several things depend on a mapped value being a pinned id, and the change
reaches each of them. The resolver's `--ids` is the list a spawn trace's model
must belong to. `--alias` folds an id to a spawn word. ADR-0007 and ADR-0013
compare models by exact match when choosing a reviewer. The mechanical cascade
(#586) escalates from its cheap rung to "the tier's mapped model", and that
cheap rung is Sonnet 5.5, so with the mechanical tier also on Sonnet the
escalation would run Sonnet a second time.

## Decision drivers

- The operator wants these two tiers on the newest model without a commit each time a family moves.
- A recorded policy should still say what each tier runs. A family word does that: it records "the newest Opus" as the decision, where an id records one model.
- The tier must reach both consumption paths, the in-session spawn parameter and `claude --model`, with no resolver change to the shared layer unless one is needed.
- A session must never be handed its own model as reviewer (ADR-0007). This holds even when the session names itself by a family word.

## Considered options

1. **Map the two tiers to the bare family word, `opus` and `sonnet`** *(chosen)*. Both paths take that word as it is.
2. **Keep pinning and add a family→latest-id step to the resolver.** Rejected. The resolver is shared layer and holds no vendor knowledge by decision, so it would need a roster it cannot keep current offline. It is also unnecessary: `claude --help` (checked 2026-10-08) documents `--model` as taking "an alias for the latest model (e.g. 'fable', 'opus', or 'sonnet') or a model's full name".
3. **Keep pinning everything and re-pin on each release of a family.** Rejected because this is the cost the operator is removing.

For the cascade:

- **(a) Escalate to the implementer tier's model when the cascade's rung equals the mechanical mapping** *(chosen)*.
- **(b) Turn the cascade off for the kit.** Rejected. A cheap first draw that an oracle judges is still worth having, and with (a) the escalation lands on a stronger model rather than a repeat of the same one.

## Decision outcome

Chosen: **the bare family word for the planner (`opus`) and the mechanical tier (`sonnet`); every other tier stays pinned.**

1. In `scripts/agents.kit.config.sh`, `AGENT_TIER_PLANNER='opus'` and `AGENT_TIER_MECHANICAL='sonnet'`. They mean the newest model in that family. The implementer, the reviewer, the reviewer's `self-implemented` domain, the reviewer fallback list and the `content` and `tests` domains all stay pinned ids. A reviewer value is never a family word. `tests/agents-tiers.test.sh` pins both halves of this clause.
2. **Both paths take the word unchanged.** The in-session spawn parameter accepts `opus` and `sonnet`, and `--alias` folds a word with no dashes to itself. `claude --model` accepts the same aliases. **The shared resolver, `scripts/agents.lib.sh`, does not change.**
3. **`--ids` lists `opus` and `sonnet`**, because they are the values these two tiers map. A planner or mechanical spawn is therefore traced under the family word. That word is the record of the decision; the model it resolved to that day is not recorded.
4. **The exact-match comparison guards the reviewer tier only.** In ADR-0007 and ADR-0013 the shared resolver compares `AGENT_SESSION_MODEL` and `AGENT_UNREACHABLE_MODELS` by exact string against reviewer candidates, and it never refuses a planner or mechanical answer. A session on a family-following tier names itself by the policy's word, which is `sonnet` for a mechanical session. The reviewer candidates are pinned ids, and `claude-sonnet-5-5` is today the same model as `sonnet`. So the kit wrapper `scripts/agents.kit.sh`, which already owns the id-to-word fold (ADR-0013 clause 2), treats a **mapped** family word as covering every pinned id that folds to it:
   - Named as the session, the first such id becomes the session model and any further ones are treated as unreachable.
   - Named unreachable, the word covers all of those ids.
   - A word the policy does not map is still compared exactly and refuses nothing.

   As a result, a `sonnet` session that asks for `reviewer self-implemented` gets `claude-fable-5-1`, not `claude-sonnet-5-5`. The change is kit-only; consumers have no family-following tier to bridge.
5. **The cascade escalates to the implementer's model when its rung is the mechanical mapping.** `AGENT_CASCADE_MECHANICAL` is set to `sonnet`, the same word as the tier. When the skill dispatcher sees that the cascade model and harness equal the mechanical tier's, it runs rung 2 on the implementer tier's model, with the ticket's domain carried through and both halves staged. It says so on stderr, and the rung's trace record carries that model. While the cascade's value names no agent harness, the dispatcher still refuses the cascade, as before.
6. **Explicit non-goal**: this decides nothing for consumers. The shipped `scripts/agents.config.sh` stays empty, and a consumer who maps a family word gets the resolver's exact comparison with no bridge.

## Consequences

- **Good**: when Opus or Sonnet moves, the planner and the mechanical tier move the same day, with no commit and no re-pin. The mechanical tier also gets cheaper: it moves from an Opus to a Sonnet.
- **Good**: a mechanical ticket now escalates from Sonnet to the implementer's Opus. Before this change it went from Sonnet 5.5 to the older Opus 5.
- **Bad / trade-off**: a model change on these two tiers has no diff and no decision. The roster moving underneath the policy is exactly what the pinning rule existed to prevent, and here it is accepted on purpose. A new model that regresses on planning or mechanical work arrives unannounced, and `/retro` is where that will show up.
- **Bad / trade-off**: the trace loses its id-versus-word guard for `opus`. Since `opus` is now a mapped value, an implementer spawn that is mis-recorded under the spawn word `opus`, instead of `claude-opus-5-5`, is accepted, and it reads as a planner spawn. Spend per model also splits Opus across two rows. Token-bearing events come from transcripts, which record the real id, so cost is unaffected.
- **Neutral**: the cross-harness `--model` path receives a word rather than an id. Under an old CLI an alias resolves to whatever that CLI calls latest, not to a refusal (see the policy file's note on CLI versions).
- **Honest limitation**: the bridge in clause 4 folds by the id shape this policy uses (`vendor-family-version`) and lives only in the kit wrapper. A session that calls `scripts/agents.lib.sh` directly, against hard rule 10, gets the exact comparison and can be handed `claude-sonnet-5-5` while it runs on `sonnet`. Also, once a `sonnet` session has refused its family, its only reviewer is `claude-fable-5-1`. When Fable is unreachable, the walk is spent, the spawn inherits the session's model, and the resolver says so.

## More information

- Implemented in: the PR that adds this record (`chore/0018-family-tiers`)
- Related: ADR-0003 (the kit maps its own tiers), ADR-0007 and ADR-0013 (the reviewer refusal and its walk), #586 (the cascade), #569 (`--ids`)
