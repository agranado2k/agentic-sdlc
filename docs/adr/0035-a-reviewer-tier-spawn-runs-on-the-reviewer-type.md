# ADR-0035: A reviewer-tier spawn runs on the reviewer type, and its parent records what it returns

- **Status**: Accepted
- **Date**: 2026-10-22
- **Deciders**: the planner session for #834, under the operator's delegation of rulings; the merge of its pull request is the operator's yes
- **Supersedes / amends**: replaces #588's ruling, recorded only in the adapter README, that the review coordinator runs on the `planner` agent type while stamped `tier=reviewer`
- **Superseded by**: —

## Context and problem statement

The retrospective of 2026-10-22 (finding F3, questions 5 and 6) counted 66
of 177 reviewer-tier stops on agent types wider than `reviewer`: planner 48,
implementer 10, general-purpose 7, claude 1. Those types hold Bash, Edit,
Write and Agent, which undo the offline reviewer contract (ADR-0009), and
their first-call prompts ran 26 to 39 thousand tokens against 18 thousand on
the reviewer type. Two causes. The review coordinator was stamped
`tier=reviewer` on the `planner` type by #588's ruling, because it runs a
skill, spawns and posts. And a judging context that had to record its own
raises needed a shell, so sessions spawned lenses and re-reviewers on wider
types and recorded their verdicts by hand.

## Decision drivers

- A rule with no failing check is a claim (shared invariant §8): the
  reviewer type was a convention nothing held.
- A judging context should hold only what judging needs: Read, Grep, Glob.
- ADR-0034's required keys must hold on every raise, whoever records it.

## Considered options

1. **Lenses return raise lines; the parent records them; the coordinator is
   planner work; the spawn guard refuses a reviewer-tier spawn on another
   type** — chosen.
2. **Run the coordinator inside the requesting session, no spawn.** Rejected:
   the author's session would assemble its own review's verdict, and a 40 KB
   skill plus seven reports would land in an already long context.
3. **Keep the coordinator stamped `reviewer` on the planner type, and exempt
   it in the guard.** Rejected: the guard cannot tell a coordinator from a
   lens by its line, and the exemption is the 48 stops the retrospective
   counted.

## Decision outcome

Chosen: **option 1.**

1. **A lens returns a declared shape.** After its §5 report, one
   `Raise: <id> <file:line>` line per finding, its id numbered in its own
   report and its letter the severity, then `Raises: <count>` as the last
   line. `/review-pr`'s `LENS-RETURN.md` holds the fence and the parent-side
   emit, `lens_raise`, which refuses a return off the shape whole — exit 2,
   nothing recorded, nothing of it printed — and otherwise renumbers in
   arrival order, records one `finding.raise` per line with its id, severity,
   lens, place and post answer (a LOW never posted, a place off the plain set
   `unsafe-path`), and prints the renumbering.
2. **Every judging context is a `reviewer`-type spawn where tier types are
   offered**: the six lenses, Agent 7, and the single-reviewer pass, which
   becomes one spawn auditing every lens. The coordinator audits no lens in
   its own context; a lens whose reviewer walk is spent is named under
   `Lenses not run:`. Only a context with no subagent tool audits in place.
3. **The coordinator is planner work.** `/implement` 9(b), where types are
   offered, resolves, stamps and records it `planner` on the `planner` type;
   `/pr-iterate` stamps its `/review-pr` spawn `tier=planner`. Its lenses are
   still resolved against the author's model (ADR-0020, ADR-0027), so the
   review's independence lives where the judging is.
4. **The spawn guard refuses a `tier=reviewer` spawn on any agent type but
   `reviewer`**, read off the payload's `subagent_type`, the absent key
   included, only where the project wires `.claude/agents/reviewer.md`. The
   refusal is exit 2 and one `note` with `data.agent_type`.

## Consequences

- Good: a reviewer-tier stop on a wider type becomes a refused spawn, and
  the retro's `kind=agent.stop tier=reviewer data.agent_type=planner` count
  should fall to the dispatcher's offline worker and nothing else.
- Good: no session records a review by hand; the raise lines are checked
  before anything is recorded.
- Bad: the coordinator now runs on the planner tier's model, which in the
  kit's policy costs more per token than the reviewer's. It judges nothing,
  so a later record may size it lower.
- Bad: a lens whose return is off the shape loses its findings for that
  review; it is named under `Lenses not run:` and the review is short.
- Neutral: a consumer with no tier types wired, or no spawn guard, sees no
  change.

## More information

- Ticket #834; retrospective `retro-20261022T135553Z`, finding F3.
- Held by `tests/trace-hooks.test.sh` section 51 (the refusal on each wider
  type and the default, the payload key over the prompt's text, the record,
  and the unwired copy) and `tests/review-pr-output.test.sh` section 22 (the
  fence, `lens_raise` run against the real trace script, the refusals, and
  the planner stamps in `/implement` and `/pr-iterate`).
