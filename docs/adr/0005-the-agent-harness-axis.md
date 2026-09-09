# ADR-0005: A capability tier may name the agent harness it runs on, and the kit ships the dispatcher

- **Status**: Accepted
- **Date**: 2026-09-09
- **Deciders**: agranado2k
- **Supersedes / amends**: amends ADR-0003 in one respect — a tier's mapped value may name an agent harness as well as a model
- **Superseded by**: —

## Context and problem statement

The kit has held since `/implement` was written that **the reviewer is never the
model that implemented**: a review from the author's own model is an editorial
pass wearing a second hat. `templates/workflows/ai-review.example.yml` goes
further and asks two *vendors* the same question, because a reviewer sharing the
author's model family shares the author's blind spots.

That workflow also records why it lives in CI, in its own header:

> CI holds the secrets, so a workflow can call a reviewer from a DIFFERENT
> VENDOR than the one running the session that wrote the code. **That
> cross-provider leg is unreachable from inside the authoring harness.**

So a second vendor was reachable only after a pull request existed, and only if
the project had wired that workflow and its secrets. Inside a session — where
the work happens, and where `/implement` would like an implementer on one model
and a reviewer on another — every tier resolved to a bare model id and was
spawned in whatever agent harness the session happened to be running.

The forcing case is one `implement/SKILL.md` already documents and works around:
when the session itself wrote the diff, the reviewer tier may resolve to the
model already running, so the kit added a `self-implemented` task domain to
force a different one. That workaround is a symptom. The tier vocabulary was
carrying a distinction — *whose session* runs the work — that it had no axis for.

A second problem surfaced while settling the first. `docs/domain-glossary.md`
defines **Harness** as `scripts/docs-conformance/`, the docs gate's Node engine,
and `scripts/check.sh` prints `engine: harness` on every green run. Meanwhile
`adapters/README.md` and `adapters/claude-code/README.md` already use "harness"
for the agent CLI, in five places, unglossed. The word was already overloaded;
this feature would have made the agent-CLI sense load-bearing in the shared
layer's public interface.

## Decision drivers

1. **A consumer already in the field must be unaffected.** `scripts/agents.lib.sh`
   is shared layer, copied verbatim into every project bootstrapped from any
   release. Most map bare model ids and will never declare an agent harness.
2. **The kit names no model, and no vendor's command line.** ADR-0003's reasoning
   holds: identifiers rot on a vendor's schedule, and so do invocations.
3. **The split must be decidable, not guessed.** A colon is legal inside a model
   identifier.
4. **"Unset is a working state"** is the resolver's central contract and the
   reason the tier mechanism was adopted at all. A new axis may not carve an
   exception into it.
5. **One name per concept** (glossary rule). An agent given two names for one
   thing invents a distinction between them.
6. **Shared invariant §7 is untouched.** A human's name stays on the merge.

## Considered options

### The axis

1. **A third axis on the tier value — `<agent harness>:<model id>`** *(chosen)*.
2. **A parallel variable, `AGENT_TIER_<TIER>_HARNESS`** — rejected: that name is
   already the task-domain axis's fold of a domain called `harness`. The two axes
   would collide in one namespace and the resolver could not tell a project that
   mapped an agent harness from one that mapped a medium.
3. **Leave it in CI and widen the workflow** — rejected against driver 1's spirit:
   it works, but it puts every cross-vendor step behind a pull request and a
   secret store, which is the latency `/implement` was trying to remove. It stays
   the recommended path for projects that want no local dispatch.
4. **Move the session between agent harnesses** (a portable transcript) —
   rejected: tool-call encodings differ per vendor and reasoning blocks are
   provider-signed, so the transfer is lossy by construction. It is also
   unnecessary: a dispatched worker is given *fresh* context by design, which
   shared invariant §4 already requires of a reviewer.

### The word

5. **Qualify both senses, ban the bare word** *(chosen)* — `docs harness` and
   `agent harness`, with the bare "harness" added to "Words this project does not
   use". This is the pattern the glossary already uses for `config`, for the same
   reason, with the same `Except:` shape for sanctioned qualified uses.
6. **A new word for the agent CLI** (`runner`) — rejected: it fights
   `adapters/claude-code/README.md`, which is titled "wiring capability tiers into
   one agent harness", and "harness" is the industry-wide term for the thing.
7. **A new word for the docs gate** — rejected on blast radius at the time, then
   partly adopted: the gate's own output line moves to `engine: docs harness`,
   because banning a bare word while the gate's success line uses it is the
   inconsistency this kit exists to prevent.

### The empty model

8. **Resolve, and warn once** *(chosen)* — an agent harness named with no model
   runs on that CLI's own default.
9. **Refuse it** — rejected against driver 4: it makes an error of the one case
   the rest of the resolver treats as normal.
10. **Resolve silently** — rejected: the operator is then spending at another
    vendor on a model nobody chose, with no signal anywhere.

## Decision outcome

Chosen: **a third axis on the tier value, a shipped dispatcher, and both senses of
"harness" qualified**.

1. A project MAY declare `AGENT_HARNESSES` in `scripts/agents.config.sh` and
   prefix any tier or task-domain value with a declared token:
   `<agent harness>:<model id>`.
2. A value with **no declared prefix keeps its old meaning exactly** — this
   tier's model, on the caller's own agent harness. A project that declares none
   is unaffected by any clause here.
3. The prefix is an agent harness **only if it was declared**. An undeclared
   prefix leaves the value whole, so a model id that merely contains a colon
   survives.
4. `scripts/agents.lib.sh` gains `--model` (the default, and the pre-existing
   contract) and `--harness`. **Stdout still carries one answer and nothing
   else**; every diagnostic stays on stderr.
5. A caller that asks for a model with no flag, on a tier that names an agent
   harness, still receives the model and is warned once on stderr that an agent
   harness was dropped. Silence there would be a wrong-harness spawn nobody
   could see.
6. **An agent harness named with no model resolves**, runs on that CLI's own
   default, and warns once. The command template omits the model option entirely
   rather than passing an empty one — `adapters/claude-code/README.md` already
   states that rule ("Do not pass an empty string as the model parameter…
   Branch on emptiness"); this makes it declarative, via a second policy
   variable `AGENT_HARNESS_<H>_MODEL_FLAG` substituted into `{model_flag}`.
7. `scripts/agent-dispatch.sh` **joins the shared layer**. It is mechanism —
   resolve, substitute markers, whitelist the model id, exec — and the kit's
   mechanism/policy split (stated in `VERSION`) puts mechanism in the layer so a
   fix reaches everyone. The only vendor-specific part is the command template,
   which is policy and already local.
8. The dispatcher exits **3, not an error**, when a tier names no agent harness,
   printing the model id for the caller to spawn in-harness as before.
9. The model id is whitelisted to letters, digits and `. _ - : /` before it is
   interpolated into the eval'd command template. Anything else is refused, not
   escaped.
10. **The glossary is canonical for the word.** `Docs harness` and `Agent
    harness` are the two terms; bare "harness" is banned with an `Except:` for
    `test harness` and the `AGENT_HARNESS_*` variable names. The gate's own
    output becomes `engine: docs harness`.
11. **Explicit non-goal**: this does not move a session, a transcript, or any
    conversational state between agent harnesses. A worker gets fresh context and
    a constructed prompt. Nothing here is a memory or a context store.
12. **Explicit non-goal**: the dispatcher does not enforce what a worker may do.
    Push and merge stay forbidden by shared invariant §7 and by the flags in the
    project's own command template — not by this script.

## Consequences

- **Good**: the cross-vendor reviewer is reachable from inside a session, before
  a pull request exists and without a secret store.
  `AGENT_TIER_REVIEWER_SELF_IMPLEMENTED` becomes redundant once a project maps
  agent harnesses, because the coordinating session knows what it is running.
- **Good**: the CI workflow's three "PROVIDER CHOICE" points — invocation,
  credential, prompt — become the same three points locally, so a project wires
  one idea twice rather than two ideas once each.
- **Bad / trade-off**: this is the kit's **first executable spawn path**, and it
  ships to every consumer whether or not they want one. It is inert until an
  agent harness is declared, but it is there, and the operator pays for the
  tokens it spends. `--dry-run` exists so that cost is inspectable first.
- **Bad / trade-off**: a headless worker needs approval flags to be useful, and
  those flags are a security posture. The kit refuses to choose one, so a project
  that wires this carelessly gets a broadly-permissioned agent. The refusal is
  deliberate; the risk is real.
- **Bad / trade-off**: the terminology decision costs a rename across eleven
  prose sites, the gate's own output string, a suite that asserts it and two
  `UPDATING.md` transcripts — churn on the one document a consumer follows
  step-by-step during an update.
- **Neutral**: the resolver grows a third axis. Its contract — one answer on
  stdout, diagnostics on stderr, unset is a working state — is unchanged in every
  particular.
- **Honest limitation**: the dispatcher can verify that the rules were
  *delivered* to another agent harness, never that they were *obeyed*. A probe on
  2026-09-09 confirmed one foreign agent harness reads this repo's `AGENTS.md`
  whole and answers correctly from it — the four tier names with the kit's own
  `scripts/agents.kit.sh` wrapper, hard rule 7 on the merge gate, shared invariant
  §4 on reviewer isolation, and a refusal to name a model identifier because
  `scripts/agents.config.sh` ships empty. That is strong evidence and it is not a
  guarantee. A project adopting this should read its first worker outputs
  adversarially.

## More information

- Grilled against the glossary and the records on 2026-09-09; the terminology
  collision it found is clause 10.
- Related: ADR-0003 (the kit maps its own tiers, and never ships the mapping),
  `templates/workflows/ai-review.example.yml`, `adapters/claude-code/README.md`,
  shared invariants §4 (fresh context for a reviewer) and §7 (the human merge gate)
