# ADR-0001: The kit self-hosts its own constitution

- **Status**: Accepted
- **Date**: 2026-08-27
- **Deciders**: Arthur Granado
- **Supersedes / amends**: —
- **Superseded by**: —

## Context and problem statement

agentic-sdlc ships a constitution — a root `AGENTS.md`, two tool shims, a
documentation set, a docs gate, guards, and a set of skills — and stamps it into
a consumer project with `bootstrap.sh`. Until this decision, the kit repo itself
had none of it. There was no root `AGENTS.md`, no `CLAUDE.md` / `GEMINI.md`, no
`docs/` at all, and `sh scripts/check.sh` **failed** at the kit's own root with
`root-manual-missing` plus a handful of `placeholder-unstamped` findings in
`bootstrap.sh` and `tests/*.sh`. The gate was only ever run green against a
throwaway project built by `tests/kit-demo.sh`.

That is a credibility problem before it is a technical one. Shared invariant §8
is "a rule written in a document that nothing checks decays into a lie", and the
kit was asking every consumer to keep a gate green in a repo where the authors
did not. It is also a feedback problem: agents authoring the kit worked with no
standing instructions of their own, so every session re-derived the worktree
convention, the shared-layer discipline, and the test suite from scratch.

The reason it had stayed that way is real, though, and it is what makes this a
decision rather than a chore. **The kit is a template repository.** Consumers
create their repo *from this tree*, so anything the kit adds at its own root
arrives in every consumer's tree — and `bootstrap.sh` refuses to run when
`AGENTS.md` already exists ("this repo looks bootstrapped already"). A kit-own
root manual, added naively, would break every consumer's first command.

A second constraint bounded the solution: two of the failing gate findings are
in files that legitimately contain double-brace marks (`bootstrap.sh`, which
stamps them, and the demo suites, which plant them to prove the gate catches
them). The rule that flags them lives in `scripts/check.sh`, which `VERSION`
lists as **shared layer** — copied verbatim into consumers, and not editable
without a minor bump, an `UPDATING.md` entry, and re-captured transcripts.

## Decision drivers

- **A consumer's first bootstrap must keep working, byte for byte.** No
  observable change to what a stamped project receives.
- **No kit-only policy may leak into consumer projects.** Whatever exempts the
  kit's own files must not arrive in somebody else's repo as a hole in their
  gate.
- **No shared-layer edit.** It was explicitly out of scope for this change, and
  its true cost (bump + recipe + transcripts) is much larger than the change
  itself.
- **The gate must keep no blind spot over its own tooling.** An exemption broad
  enough to cover `tests/*.sh` is broad enough to hide a real leak.
- **Smallest design that works.** This is infrastructure; a new mechanism has to
  earn its permanent maintenance cost.

## Considered options

### For the kit-own files vs. bootstrap

1. **Strip the kit-own files in `bootstrap.sh` before the idempotency check,
   guarded by a sentinel** *(chosen)* — bootstrap already has a `KIT_ONLY` list
   it deletes at the end; this is the same idea moved to the front, where it has
   to be, because the idempotency check would otherwise trip on the kit's own
   manual.
2. **Ship the kit's manual under another name** (e.g. `KIT-AGENTS.md`) —
   rejected: the gate's `root-manual-missing` rule is hard-coded to the
   configured root manual, so the kit would still be red at its own root. It
   would be self-*documenting*, not self-*hosting*.
3. **Relax bootstrap's idempotency check to a warning** — rejected: that check
   is the only thing standing between a second run and a week of somebody's
   local rules being silently overwritten.

### For the `placeholder-unstamped` findings

1. **Spell the mark from variables in the kit-authoring files** *(chosen)* — a
   `mark` helper in `bootstrap.sh`, `tests/lib.sh` and `tests/kit-demo.sh`, and
   one reworded comment. `scripts/check.sh` already does exactly this for its
   own source, and says why in a comment: *"the pattern is assembled from
   variables so this script does not itself contain the literal mark. Otherwise
   the gate would have to exempt its own source, and a gate with a blind spot
   over itself is not a gate."* The kit-authoring scripts are in the same
   position, so they get the same answer.
2. **A kit-only gate-policy file, or an env var / CLI flag read by the gate** —
   rejected on inspection: the `placeholder-unstamped` rule is implemented
   entirely in `scripts/check.sh`'s POSIX section, which reads no config at all.
   Every variant of this option (an exclusion list, `DOCS_CHECK_*` env var, an
   extra argument, a stamped `config.mjs`) requires editing a shared-layer file,
   which was the one thing ruled out. `scripts/docs-conformance/config.mjs`
   cannot help either: the node harness never sees this rule.
3. **Rename the offending files so the `*.template` exemption covers them** —
   rejected: `tests/kit-demo.sh.template` is not a runnable suite, and the
   exemption exists for unstamped sources, not for scripts.

## Decision outcome

Chosen: **the kit repo is bootstrapped like any consumer, and `bootstrap.sh`
removes the kit's own files before it stamps a consumer's.**

1. The kit root carries a **hand-written** `AGENTS.md` describing the
   kit-authoring context — not a stamped copy of
   `constitution/AGENTS.md.template`. The two are different documents for
   different readers and are expected to diverge.
2. `CLAUDE.md` and `GEMINI.md` sit beside it in exactly the shape
   `bootstrap.sh` writes: one HTML comment, one `@AGENTS.md` import.
3. The kit carries `docs/diary.md`, `docs/adr/` (this record, its index, and the
   MADR skeleton), `docs/domain-glossary.md`, and
   `.github/PULL_REQUEST_TEMPLATE.md`.
4. `bootstrap.sh` removes `AGENTS.md`, the shims, `docs/diary.md`,
   `docs/domain-glossary.md`, `docs/adr/` and `.github/PULL_REQUEST_TEMPLATE.md`
   **before** the "already bootstrapped" check, under **two** conditions, both
   required:
   - `constitution/AGENTS.md.template` still exists (this tree has not been
     stamped), **and**
   - the root manual carries the sentinel string `agentic-sdlc:kit-own`.

   The sentinel is what preserves today's safety for the one case that would
   otherwise regress: a repo created from the template whose owner hand-wrote an
   `AGENTS.md` before running bootstrap. Their file has no sentinel, nothing is
   removed, and they get the same refusal they get today.
5. Kit-authoring files that must **name** a double-brace mark spell it from
   variables (`ob` / `cb` and a `mark` helper) rather than carrying a literal
   one. No exemption is added to the gate, and no kit-only policy file exists.
6. `.github/workflows/kit-ci.yml` gains a `self-host` job running
   `sh scripts/check.sh` at the kit root, so the green is enforced rather than
   claimed.
7. `tests/self-host.test.sh` is the suite. Its load-bearing assertion is
   **byte-identity**: bootstrap runs twice, once against the real tree and once
   against the same tree with the kit-own files removed by hand, and the two
   resulting projects must be identical file for file.
8. **Explicit non-goal**: this does not give the kit a general seam for
   kit-only gate policy. It removes the need for one today; it does not build
   one for tomorrow.

## Consequences

- **Good**: the kit keeps the rule it sells. `sh scripts/check.sh` is green at
  the kit root and enforced in CI, and every agent session in this repo now
  loads standing instructions written for it instead of re-deriving them.
- **Good**: no shared-layer file changed, so `VERSION` stays at 0.5.0, no
  `UPDATING.md` entry is owed, and no pinned transcript had to be re-captured.
- **Bad / trade-off**: `bootstrap.sh` now deletes files at the *start* of its
  run. That is the highest-consequence line in the script, and it is guarded by
  a string match. The guard is double (template present **and** sentinel
  present), and the byte-identity suite covers the outcome, but a future editor
  who deletes the sentinel comment from `AGENTS.md` breaks consumer bootstrap in
  a way that only `tests/self-host.test.sh` will catch.
- **Bad / trade-off**: the mark-spelling convention makes three kit-authoring
  files slightly less direct to read. `s|$(mark PROJECT_NAME)|…|g` is a step
  removed from `s|{{…}}|…|g`. This is the same cost `scripts/check.sh` already
  pays, and it is paid at the exact places that would otherwise need a gate
  exemption.
- **Neutral**: the kit's `AGENTS.md` and the template it ships must now be kept
  in step *conceptually* (tiers, hard rules, the chain) without being kept in
  step *literally*. They are different documents; nothing diffs them, and
  nothing should.
- **Honest limitation**: the `templates/` tree is not one of the gate's
  `pathRoots`, so code-span references to `templates/docs/` and
  `templates/workflows/` in the kit's manual are **not** existence-checked.
  Adding the root would split the two engines apart, because the POSIX twin of
  that list lives in shared-layer `scripts/check.sh`. Those two references can
  therefore go stale silently.
- **Honest limitation**: two comments in shared-layer
  `scripts/docs-conformance/validators/claude-md-refs.mjs` still cite "the kit's
  own unbootstrapped tree" as their example. The rules they describe are
  unchanged and still correct; only the example is now wrong. Fixing them is a
  shared-layer edit and waits for the next release that bumps `VERSION` anyway.
  It is recorded in `docs/diary.md` so it is not rediscovered as a surprise.

## More information

- Implemented in: ticket f12, branch `feat/f12-self-host`.
- Related: `VERSION` (what "shared layer" means and what changing one costs),
  `UPDATING.md` (the recipe), `scripts/check.sh` (the `placeholder-unstamped`
  rule and the comment this decision follows), `tests/self-host.test.sh`.
