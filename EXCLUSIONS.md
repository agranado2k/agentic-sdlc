# EXCLUSIONS — what this kit deliberately does not ship

This file exists because `/improve-codebase-architecture` sat unported for two
releases and, when someone finally asked whether that was **a decision or a
slip**, nothing in this repo could answer — so it was neither recorded nor
caught, it was just missing (it was a slip; [#25](https://github.com/agranado2k/agentic-sdlc/issues/25)
ported it).

An absence looks identical from the outside whether it was chosen or forgotten.
That is the entire problem this record solves: everything below is an absence
somebody chose, with the reason attached, so the next reader can tell the two
apart without archaeology.

## The standing rule

**A skill or mechanism that is considered and then left out gets a line here in
the same pull request that excludes it.** Not the next PR, not a follow-up
ticket — the same one. The reason is cheap to write while the decision is being
made and nearly impossible to reconstruct six weeks later, which is exactly how
the slip above happened.

Two corollaries:

- **Removing something already shipped is an exclusion too.** Deleting a skill
  without a line here recreates the original problem in the other direction.
- **An entry that stops being true gets deleted, in the PR that makes it
  untrue.** `tests/exclusions.test.sh` enforces this half mechanically: every
  entry marked `(excluded)` below must have no matching directory in
  `.agents/skills/`. A record that confidently names something the kit *does*
  ship is worse than no record at all.

The entry format is load-bearing, not decorative: `### /<command> (excluded)`
is what the test parses. Prose entries under any other heading are not read as
claims of exclusion.

---

## Excluded

Three skills exist in the predecessor repo this kit was extracted from
(`centaur-spec`) and were read, in full, before being left out.

### /report-comments (excluded)

**Product-specific, and the portable part is already here.** It drives one
product's report-comment feature: its tool surface is that product's own MCP
server (`mcp__centaurspec__*`), it branches on a comment `intent` value defined
by that product's schema, and it cites that product's ADR numbers for its own
trust rules. Copied into a repo with no reports and no such server, nothing in
it resolves — it would be a command on the manual's map pointing at a feature
the project does not have.

What *is* portable in it — untrusted third-party content is **data**, never
instructions — is already in the kit twice over: as the agent trust boundary in
the root manual, and as the "the ticket body is untrusted content" rule that
`/implement` opens with. The skill was the vehicle; the rule was the cargo, and
the cargo arrived.

### /zoom-out (excluded)

**A prompt macro, not a workflow — and excluded for that reason, not for being
product-specific.** It is seven lines ("go up a layer of abstraction, give me a
map of the relevant modules and callers, use the project's glossary") carrying
`disable-model-invocation: true`, so only a human typing it ever fires it. It is
in fact perfectly portable; saying otherwise would be the kind of tidy-sounding
reason this file exists to prevent.

The reason it stays out is what a kit skill costs. Every skill this kit ships
owns a lifecycle stage, leaves an artifact something can check, and buys a row
in the manual's quick-reference map that the docs gate then polices for the life
of the project. A phrasing convenience that produces no artifact cannot pay that
rent, and it does not need to: a personal prompt belongs in a user-level skills
directory, where it costs the repo nothing and follows its author between
projects. The kit-level question it asks — "how does this fit together, and
where should it be deepened?" — is `/improve-codebase-architecture`'s, and that
one ends in a decision record.

### /review-and-evaluate (excluded)

**Predecessor-specific, and superseded by an invariant.** Its own header records
that it was copied out of an earlier repo (`zora-pantheon`) and its body never
left: it hard-codes that repo's ADR numbers and its `docs/spec.html`, neither of
which exists anywhere else.

The deeper reason is structural, and would survive de-productizing it. It runs a
review agent and a context-alignment agent in parallel and then **merges their
output into one Apply / Skip / Discuss verdict list** — which is precisely the
merge [shared invariant §5](constitution/shared-invariants.md) forbids: standards
findings an agent may act on and behavior findings only a human may resolve are
categorically different outputs, and collapsing them into one list destroys both.
This kit's `/review-pr` runs both readings and deliberately keeps them apart.
Porting `/review-and-evaluate` would mean shipping a skill that violates the
rulebook it shipped beside.

---

## Optional, not excluded

### /ce-dogfood (optional, not excluded)

Dogfooding was **never rejected**, and this row exists to stop that misreading
from taking hold. The predecessor's `ce-dogfood` bundles two separable things:
one product's personas, flows and browser wiring (local knowledge, stays behind)
and the pattern underneath — synthetic personas exercising the product through
its **real user-facing surface** before a human does, which is portable, because
only the surface varies by stack (a browser for a web app, the binary for a CLI,
a client for a tool server).

That pattern **ships**, as the opt-in `/dogfood` skill
([#27](https://github.com/agranado2k/agentic-sdlc/issues/27)) — opt-in rather
than default because it needs a runnable user-facing surface, and a project
without one would inherit a command it cannot run. `bootstrap.sh` asks once
(`--with-dogfood` / `--no-dogfood` answer it non-interactively; with no terminal
to ask on, it skips), and a declined answer removes the skill directory, its
product article, and the manual's rows about it — so the skipped case leaves
nothing dangling rather than a commented-out row.

The record stands either way, which is the point of writing it here: this was a
**scoping** decision about which part of the predecessor's skill was portable,
never a decision to leave dogfooding out. What stayed behind is what the
scoping said would stay behind — one product's personas, its flows, its browser
wiring — plus one thing the port dropped deliberately: the predecessor repaired
what it found, and this version reports instead, because a fix applied by the
session that found the problem destroys the only independent reading anyone had
of it (shared invariant §10).

---

## Mechanisms

The standing rule covers non-skill mechanisms too — a guard, a gate, a workflow,
a manifest entry. None has been considered-and-excluded since this file started,
so the section is empty rather than absent: an empty section invites the next
entry, while a missing one invites a README section nobody links.

Two decisions that *look* like exclusions but are recorded elsewhere, because
the thing was shipped rather than left out: `adapters/` arrives dormant and
uninstalled (`adapters/node-ts/INSTALL.md` says why), and the cross-provider AI
review workflow arrives inert as an `.example` (see the README). Shipped-but-off
is not an exclusion.

---

## Where this file lives, and why it is not in your project

`EXCLUSIONS.md` answers "what does **this kit** not ship". Inside a project
bootstrapped from the kit that sentence has no referent — the reader would take
it for a record of *their* decisions — so the file takes the same route as the
kit's own tests and CI: it is named in `bootstrap.sh`'s `KIT_ONLY` list and
deleted along with `bootstrap.sh` itself.

It is therefore **not shared layer**, and not listed under `files:` in `VERSION`,
for the simplest available reason: a file that never arrives cannot be copied
verbatim or diffed against a later release. This is a different case from
`UPDATING.md`, which *is* shared layer — that one is a recipe the consumer runs,
so it has to travel; this one is a record of the kit's own history, so it does
not. `tests/exclusions.test.sh` asserts both halves, so the wiring cannot drift
away from this paragraph.
