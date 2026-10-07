# Capability tiers — the kit's practice

The kit's one on-demand article: elaboration the root manual `AGENTS.md` points
at instead of carrying, because every line there is re-read on every request
(shared invariant §11) and this text is needed only when a ticket is sized or an
agent is spawned. ADR-0014 records the move. It is **kit-own**: `bootstrap.sh`
strips it from a consumer's tree the way it strips the kit's decision records,
and nothing the kit ships may point at it.

What stays in the root, and is not repeated here: hard rule 10 (run the kit
wrapper where a SKILL.md names the plain resolver), the four tier names, and the
one command you type before spawning a reviewer — the root's "Capability tiers"
section is that command's home.

## The four tiers

Work in this repo is sized to one of **four tiers**, a cost/benefit decision
made when the ticket is written — not when the agent is spawned, and never by
the agent about itself. A **skill** also declares the phase of work it is
(`metadata.phase`), and where both exist the ticket wins: the phase is what
sizes a command nobody wrote a ticket for.

| Tier | The work | The signal |
| --- | --- | --- |
| `planner` | Decomposing a wave, designing a gate, triaging an ambiguous failure | Reads broadly, writes little; a wrong answer costs a whole wave downstream |
| `implementer` | Building one kit ticket test-first — a script, a validator rule, an article | The default for real work here |
| `mechanical` | Renames across the templates and skills, a manifest bump, a transcript re-capture | A checkable definition of done, only when both hold: the ticket names the one command whose exit is its oracle, and the change is one file or one pattern applied uniformly across many |
| `reviewer` | Adversarial reading of a finished diff in fresh context | Undersize it and review becomes a rubber stamp |

`/to-tickets` stamps a tier on every ticket and shows it at the quiz for
override; `/implement` reads it when it spawns.

**The mechanical tier can run cheap-first.** Where the policy declares
`AGENT_CASCADE_MECHANICAL`, the skill dispatcher runs a mechanical ticket on
that model first, then the ticket's oracle and the pairing guard in its
worktree; red on either exit code, it resets the worktree to the ticket's base
and runs the ticket again on the tier's mapped model. The worker's own report
never decides. A ticket with no closed-list oracle is refused the cascade, and
so is a cascade model the dispatcher cannot cross to — an oracle cannot judge
work the dispatcher never ran. The kit's own value names no agent harness
today, so its cascade is declared but refused until one is wired (#586).

## The mapping is data, and the kit carries its own

**The root manual names no model, and neither does any other file the kit
ships.** Model identifiers rot on a vendor's schedule, so the tier → model
mapping is data in `scripts/agents.config.sh` and the resolver is
`scripts/agents.lib.sh` (`sh scripts/agents.lib.sh implementer` prints the id).
An unmapped tier is a working state: the resolver warns once, prints nothing,
and the spawn inherits the session's model — `adapters/claude-code/README.md`
is one worked example.

`scripts/agents.config.sh` ships EMPTY to every consumer, by principle. But
this repo is itself a consumer of the mechanism it ships: an unmapped resolver
would let the kit's own agents inherit the session model whatever tier their
ticket was stamped — so the kit carries a second, kit-only mapping,
`scripts/agents.kit.config.sh`, never shipped (it is on `bootstrap.sh`'s
kit-authoring deletion list, the same as `tests/`; ADR-0003).

Every SKILL.md that spawns a subagent says, verbatim, `sh scripts/agents.lib.sh
<tier>` — correct for a consumer, and it has to stay that way: skills ship
unstamped, so none may name a kit-only file (the root manual's "The chain").
Typed literally in THIS repo, that command reads the empty shipped policy file
and prints nothing. **Hard rule 10** is the fix, every time a skill says to
spawn. The wrapper sets the resolver's existing `$AGENTS_CONFIG` seam and
delegates —

```sh
AGENTS_CONFIG=scripts/agents.kit.config.sh sh scripts/agents.lib.sh <tier>
```

— one name to substitute, not an environment prefix to type right every time.

## The policy behind the mapping

Plan on the strongest model available; execute spawned per tier, and per
**domain** where the medium changes the answer; the reviewer is never the model
that implemented — a review from the implementer's own model is an editorial
pass wearing a second hat, not an adversarial read (ADR-0007).

## The domain axis

The domain is the resolver's optional second argument: `sh
scripts/agents.kit.sh implementer content` prefers
`AGENT_TIER_IMPLEMENTER_CONTENT`, falling back to `AGENT_TIER_IMPLEMENTER`.
The two vocabularies are opposite: the four tier names are **closed** (an
unknown one is exit 2), while domains are **open local policy**, so an unmapped
one falls back to the tier in silence. This repo maps `content`, for the prose
that is most of the kit's product — `implementer` work by tier, not code by
medium — and `self-implemented` on the reviewer tier, for a diff the session
wrote on the reviewer's model, a situation, not a medium, chosen at spawn time.
`code` is unmapped: the plain tier is its answer. `/to-tickets` stamps an
optional `Domain:` line when the medium would change the model, and `/implement`
passes it as the second argument; a situation domain is never stamped on a
ticket.

One more the kit names and maps for nobody — **`judge`** on `mechanical`, by
contract not by vendor: state and typed questions in, typed answers with
per-option probabilities out, in two shapes — **decide** and
**rank-or-verify**. A decider is never handed a verification, nor any judge the
review verdict (§5, ADR-0010).
