# ADR-0043: The chain names a ticket by its handle, and closes a factory ticket the factory's way

- **Status**: Accepted
- **Date**: 2026-11-01
- **Deciders**: the implementer session for #965, under the operator's delegation of rulings, from PRD-15 §8's decision record B; the merge of its pull request is the operator's yes
- **Supersedes / amends**: amends ADR-0019 clause 1 (the ticket the landing script reads `ticket.start` on: "the PR's first closing reference, or `--ticket`", now also the landing line's factory id) and ADR-0030 clauses 2 and 3 (the author record's `ticket=` value, now `#N`, `none` or a canonical factory id); a new record because both are records of their own, and ADR-0019 already carries four amendments
- **Superseded by**: —

## Context and problem statement

The factory owns idea → ticket and the kit owns ticket → landed change. A
factory project opens no forge issue for a ticket, so a chain that names a
ticket only as `#<N>` cannot build, land or measure one there; this
repository works around that by mirroring each factory ticket as an issue,
and the same plan then exists twice. The operator ruled (2026-10-31, PRD-12
Q3 option (b)) that the chain past the stamp takes a factory ticket id
wherever it takes an issue number. ADR-0040 opened the trace to it; this
record says how the rest of the chain names and closes such a ticket.

## Decision drivers

- One spelling per ticket: the trace joins on exact strings.
- The factory's gates (`review`, `qa`) are human gates, and the item model is
  the factory's: the kit writes no more of it than closing needs.
- A consumer with no factory sees nothing change.

## Considered options

1. **A ticket handle, `#<N>` or a canonical factory id; a factory ticket closed through `links.pr` and `factory move <id> review` on its branch** *(chosen)*.
2. **Keep mirroring every factory ticket as an issue** — rejected: a consumer factory project would have to open issues the factory forbids, and duplicates recur.
3. **Let the landing script move the factory ticket after the merge** — rejected: every move past `review` is a human gate, and a write on the default branch after the merge needs a commit of its own.

## Decision outcome

Chosen: **option 1**.

1. **A ticket handle** is an issue number, `#<N>`, or a canonical factory
   ticket id, `T-<digits>` as ADR-0040 clause 3 spells it. One ticket has one
   handle: a mirrored ticket's is its issue number, any other factory ticket's
   is its id. A writer handed a one-digit id pads it, `T-07`.
2. **`/implement` builds a factory ticket by its id** (`STAMP.md`'s factory
   section, process/R228 to R238): its text from `factory show`, untrusted;
   no forge issue fetched; the claim branch `<type>/t-<digits>-<slug>` in its
   own worktree (not `factory start`); `factory move <id> build` as the
   branch's first commit, a refusal a stop; `ticket:T-<digits>` subjects; the
   landing line `<!-- implement: ticket=T-<digits> tier=<tier> -->` and no
   closing keyword.
3. **A factory ticket is closed the factory's way**: `links.pr: "#<PR>"` and
   `factory move <id> review`, one commit on the ticket's branch, reaching the
   default branch with the merge. A refused move keeps the `links.pr` commit
   and is reported. `factory review`, `factory qa`, `factory approve`,
   `factory close` and a forced move stay the operator's; no session runs them.
4. **The check table's ticket side** for a factory id is what
   `sh scripts/stamp.sh T-<digits>` printed (process/R239), never the item file.
5. **ADR-0019 clause 1, amended**: the landing script's ticket is the PR's
   first closing reference, or `--ticket`, or — a PR closing no issue — the
   landing line's factory id; only a factory id is taken from the line.
6. **ADR-0030 clauses 2 and 3, amended**: the author record's `ticket=` is
   `#N`, `none`, or the canonical factory id the cascade ran with, and the
   review dispatch takes it only when it is exactly the dispatch's.
7. **The stop**: the kit mirrors until PRD-15's last build slice lands, then
   writes no forge issue for a factory ticket, held by a kit-only suite
   (PRD-15 slice 6). Tickets already mirrored finish by number.

## Consequences

- **Good**: a factory ticket can be built, landed and measured with no issue,
  and its board shows the build without a session touching a human gate.
- **Bad / trade-off**: `/implement` now writes two factory fields (the stage
  through `factory move`, and `links.pr` by hand); nothing else of the item.
- **Neutral**: an issue's path is unchanged, word for word.
- **Honest limitation**: the slice's live demo — a factory ticket written
  with no issue, built by `/implement T-<n>` — waits for the stop; until then
  the skill text and a fixture show it.

## More information

- Implemented in: #965 (factory T-96, PRD-15 slice 3); clause 6 by #964
  (T-90), clause 5 by T-99, clause 7 by PRD-15 slice 6.
- Requirements: `docs/specs/process.md` R228 to R239.
- Related: ADR-0040, ADR-0019, ADR-0030, ADR-0021.
