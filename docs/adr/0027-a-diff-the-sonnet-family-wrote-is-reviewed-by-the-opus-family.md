# ADR-0027: A diff the Sonnet family wrote is reviewed by the Opus family

- **Status**: Accepted
- **Date**: 2026-10-13
- **Deciders**: the operator (Arthur Granado), option (a) on #763, recorded on that issue on 2026-10-13; built by the planner session for #763
- **Supersedes / amends**: amends ADR-0020 as amended on 2026-10-10 (#724), for the Claude Code session's policy only: the reviewer's fallback is `opus` again, for an author on the Sonnet family and no other. A partial reversal of that amendment, so a new record and not a second in-place amendment (`docs/adr/INDEX.md`, conventions)
- **Superseded by**: —

## Context and problem statement

The cheap-first cascade's first rung is the Sonnet family
(`AGENT_CASCADE_MECHANICAL='sonnet'`, ADR-0018). Since ADR-0020's amendment of
2026-10-10 the reviewer tier is the Sonnet family with no fallback, and a
review never resolves to its author's family (ADR-0007, through the kit
wrapper's bridge). So `AGENT_SESSION_MODEL=sonnet sh scripts/agents.kit.sh
reviewer` printed nothing for every diff the cheap rung wrote, which are the
diffs the cascade exists to produce. Landing PR #762 (#752) found it: the
landing script needed `--no-review`, so every cascade-built PR landed
unreviewed by construction.

The amendment had expected that "a session off the Sonnet family spawns" a
Sonnet author's review on `sonnet`. That review shares the author's family,
which is the editorial pass ADR-0007 exists to prevent. Read per author and not
per session, the amendment left a Sonnet-written diff with no reviewer it
allowed.

## Decision drivers

- ADR-0007, read per author: a diff is never reviewed by its author's family.
- The operator's ruling of 2026-10-08, as narrowed on 2026-10-10: reviews run on Sonnet. That holds for every author it can hold for.
- ADR-0013: a reviewer has a next answer while a candidate remains, and a spent walk prints nothing, never the author's own model.
- No shared-layer change. The shared resolver and every shipped skill stay as they are.

## Considered options

1. **(a) The reviewer's fallback is `opus`, served only to an author on the Sonnet family** *(chosen)*.
2. **(b) Move the cascade's cheap rung off the reviewer's family.** Rejected by the operator. It changes the cost ladder ADR-0018 set to fix a review problem.
3. **(c) Declare a cascade-built diff exempt from review when the full-suite oracle passed.** Rejected by the operator. The oracle proves the ticket's command exits 0. It does not read the diff.
4. **A fallback of `opus` with no fence.** Rejected. The shared resolver walks to the fallback whenever the candidates before it are skipped, as the session's own or as unreachable alike. So a Fable author, an unnamed one, or any author off the Sonnet family whose Sonnet was unreachable would get an Opus review. That goes against "every other diff keeps the Sonnet-only reviewer". An Opus author was already safe, because the bridge refuses it its own family.

## Decision outcome

Chosen: **option 1.**

1. In `scripts/agents.kit.config.sh`, `AGENT_TIER_REVIEWER_FALLBACK='opus'`, the bare family word and nothing past it. `AGENT_TIER_REVIEWER` stays `sonnet`, and `self-implemented` stays unmapped.
2. **The fence.** A kit-only policy variable, `AGENT_KIT_REVIEWER_FALLBACK_SERVES`, is read by `scripts/agents.kit.sh` and by no shared resolver. When it is `own-family` (the kit's Claude Code policy sets this), the fallback answers only an author whose family holds a candidate before the fallback (the domain answer or the plain reviewer). For any other author, if those candidates are all named unreachable, the wrapper prints nothing in every form (bare, `--model`, `--alias`, `--harness`), warns, and exits 0. When it is empty or `any`, the walk is ADR-0013's as before. Any other value is refused with exit 2, because a misspelt fence would otherwise be no fence and give no sign.
3. **The answers**, through `sh scripts/agents.kit.sh reviewer [self-implemented]`:
   - A Sonnet author (`sonnet`, or any `claude-sonnet-*` id) gets `opus`. With `opus` named unreachable it gets nothing.
   - An Opus author gets `sonnet`. With Sonnet unreachable it gets nothing, because `opus` is its own family.
   - A Fable, other or unnamed author gets `sonnet`. With Sonnet unreachable it gets nothing, refused by the fence.
4. **Name the author, not the session.** The session asks with `AGENT_SESSION_MODEL` set to the diff's author: the cascade rung's model when a rung wrote it, never the Opus session that spawned the rung. `/review-pr` §3 already resolves its lenses against the author. A cascade-built PR therefore gets an Opus review and lands with no `--no-review`.
5. **Nothing printed still means spawn no review here** (ADR-0020's amendment): the review waits for its reviewer, and the report quotes the warning.
6. **Explicit non-goals**: the Codex session's policy (`scripts/agents.kit.codex.config.sh`) keeps an empty fallback, because no Codex session is on the Sonnet family. Consumers, the shared resolver and every shipped skill are unchanged.

## Consequences

- **Good**: every diff has a reviewer that is not its author's family. The cascade's output is reviewed again, and `--no-review` is back to being a named exception.
- **Good**: Sonnet stays the reviewer for every author off its family, outage or not, which is what the 2026-10-10 ruling was for.
- **Bad / trade-off**: an Opus review of a cheap rung's diff costs more than the rung did. That is the price of a review that differs from its author. `/retro`'s spend question is where it will show.
- **Bad / trade-off**: one more kit-only variable, and the fence lives in the wrapper. A session that calls `scripts/agents.lib.sh` directly, against hard rule 10, walks to `opus` for any author whose Sonnet is unreachable. This is the same limitation ADR-0020 records for the bridge.
- **Honest limitation**: the rule depends on the caller naming the author. A session that names itself (Opus) for a rung's diff gets `sonnet`, a review on the author's family. The root manual and `docs/capability-tiers.md` say to name the author, but no script can see who wrote a diff.

## More information

- Implemented in: the PR for #763 (`feat/763-opus-reviews-sonnet`). Held by `tests/agents-tiers.test.sh`: the author cases, the fence in each form, the misspelt-value refusal, and the full family walk through the wrapper. Every answer for a Sonnet author folds to `opus`, and every answer for any other author folds to `sonnet`. Each case was shown failing before the policy and the fence existed.
- Related: ADR-0007 (the refusal), ADR-0013 (the walk), ADR-0018 (the cascade rung and family-following tiers), ADR-0020 and its amendment (the reviewer follows the Sonnet family), ADR-0022 (the Codex session's policy).
