# Glossary format

The project's ubiquitous language lives in `docs/domain-glossary.md` (the root
`AGENTS.md` names the real path — trust it over this file if they disagree).
That file carries its own writing rules in its header; this sidecar is the short
version, for use mid-grilling.

## Entry shape

```md
## <Context name>

- **<Term>** — <what it IS, in one or two sentences>. <Kind: Aggregate root /
  Entity / Value Object / read type / port / adapter>. Ref: <ADR-NNNN or spec section>.
  - _Avoid_: <the near-synonym people reach for> (<why it is wrong here>).
```

And the half that is usually missing:

```md
## Words this project does not use

- **<banned word>** — ambiguous here (<why>). Use **<term>** or **<term>**.
```

## Rules

- **Be opinionated.** When multiple words exist for the same concept, pick the
  best one and list the others under `_Avoid_`. One name per concept: an agent
  given two names for one thing will invent a distinction between them.
- **Keep definitions tight.** One or two sentences max. Define what it IS, not
  what it does. When an entry needs a page of explanation, that page is a
  decision record and the entry points at it.
- **Only include terms specific to this project's domain.** General programming
  concepts (timeouts, error types, utility patterns) don't belong even if the
  project uses them constantly. Before adding a term, ask: is this a concept
  unique to this domain, or a general programming concept? Only the former
  belongs.
- **Group terms under subheadings** when natural clusters emerge — usually one
  `##` per bounded context, module, or subsystem. If all terms belong to one
  cohesive area, a flat list is fine.
- **Retire, don't delete.** Mark a superseded term _(superseded by `NewName`)_
  and say what replaced it. A deleted entry loses the fact that the old name
  ever meant something — exactly what a reader of old code needs.
- **Rename in one change.** Changing a term means renaming it across the whole
  codebase and updating the glossary in the same commit. No aliases.

## Multiple contexts, and the context map

When the repo has several bounded contexts, give each one a `##` section in the
single glossary (or its own file, with `docs/domain-glossary.md` as the index —
prefer the single file until it stops being readable in one session-start scan;
two glossaries that both define the same term are the drift this whole document
exists to prevent).

The edges between contexts live in the glossary's **Context map** section, and
the rule that makes it worth maintaining mid-grilling: **every edge is declared
from both sides.** The upstream says what it publishes; the downstream says what
it takes and how. Two declarations of one edge that do not match are the
disagreement itself, surfaced before it is a bug — and an edge declared from one
side only is half a decision, visible because the other context's block does not
mention it. One line per edge, under the context that is speaking, naming one of
Evans's relationships (upstream / downstream, conformist, anti-corruption layer,
published language, shared kernel, separate ways):

```md
## Context map

### Ordering

- **Ordering → Fulfillment** — upstream: published language. Publishes `OrderPlaced`.

### Fulfillment

- **Fulfillment → Ordering** — downstream: anti-corruption layer. Consumes
  `OrderPlaced`, translated into `PickRequest` at the edge; nothing of Ordering's
  model leaks past it.
```

When a grilling answer names a new context, adds an edge, or changes a
relationship, update both sides in the same breath. The glossary template's
header comment carries the one-line gloss of each relationship; the section is
first written by the design brief and kept current here. The phrase "strategic
design" is banned in the glossary's last section: say **context map**.

---

*Replaces the upstream `CONTEXT-FORMAT.md` from
[mattpocock/skills](https://github.com/mattpocock/skills) — MIT, see
`.agents/skills/LICENSE-mattpocock-skills.md`. Upstream puts the language in a
root `CONTEXT.md` with a `CONTEXT-MAP.md` for multi-context repos; this kit
already ships a glossary document, so the skill writes into that one instead of
creating a second home for the same rule.*
