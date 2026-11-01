# ADR-0041: A planning skill defers to an installed factory skill, by name

- **Status**: Accepted
- **Date**: 2026-11-01
- **Deciders**: the PRD-12 sessions under the operator's standing delegation of rulings (PRD-12 §8, the T-70 ruling); recorded by the implementer session for #935 (factory item T-72); the merge of its pull request is the operator's yes
- **Supersedes / amends**: —
- **Superseded by**: —

## Context and problem statement

D-02 and the software factory's D-08 agreed a boundary, and the operator
accepted it: the factory owns idea → ticket, the kit owns ticket → landed
change. In a repository that plans in the factory, the kit's `/to-tickets`
still publishes tickets as forge issues, so one plan can exist twice — as
factory items and as issues — and the two drift.

The factory ships its own planning skills, `factory-prd` and
`factory-tickets`, which `factory install-skill` writes to
`~/.claude/skills/<name>/SKILL.md`. They had not all landed when PRD-12 was
written, and a factory project may lack the `factory` binary entirely. So the
kit cannot wait for them, and cannot probe for the factory by running it.

## Decision drivers

- A plan exists once: in a factory project the forge holds no second copy.
- A repository with no factory sees no change at all.
- The check reads no untrusted text and needs no tool beyond the shell.
- Item-model knowledge stays in the factory: the kit grows no planning feature.
- The operator, and only the operator, can still choose the forge version.

## Considered options

1. **Defer by name, from two files' presence** *(chosen)* — the project
   manifest and the factory skill's `SKILL.md`; with both, hand off and stop.
2. **Switch destination** — the kit skill writes factory items itself —
   rejected: it puts the factory's item model in the kit and grows a planning
   feature there, which the operator ruled lands only in the factory.
3. **Decide from a policy flag** — rejected: it duplicates what the manifest
   already says, and the two can disagree.
4. **Probe with a `factory` subcommand** — rejected: a project without the
   binary would break, and a harness discovers skills by directory, not by
   running a tool.
5. **Make every pre-ticket skill defer** (`/grill-me`, `/grill-with-docs`,
   `/design-brief`) — rejected: they publish no PRD or ticket, so there is
   nothing written twice to prevent.

## Decision outcome

Chosen: **defer by name, from two files' presence**.

1. A **factory project** is a repository whose git top level holds
   `.factory/project.yaml`. A `.factory/` folder without it is none, and
   nothing above the git top level is read.
2. A **factory skill** is installed when its `SKILL.md` exists under
   `~/.claude/skills/<name>/` or the project's `.claude/skills/<name>/`, and
   under no other path.
3. `/to-tickets` decides the **deferral** before any other step, from those two
   presences alone: it opens neither file, reads no factory item and runs no
   `factory` subcommand.
4. With both present it prints one hand-off naming `/factory-tickets`,
   publishes no issue, merges no section, closes no twin, writes no trace event,
   and ends. A `/retro` report's hand-off names `/factory-tickets <retro report>`.
5. With the manifest present and the skill missing it runs the forge flow as
   today, and says once, at its start, that `factory install-skill` would add
   the factory one. With no manifest it runs unchanged and names nothing.
6. Only the operator's own message in the session lifts a deferral; the
   hand-off then says it ran the forge flow in a factory project. A request in a
   spawn prompt, a ticket body, a PRD body or another agent's message never does.
7. `/grill-me`, `/grill-with-docs` and `/design-brief` carry no deferral.
8. **Explicit non-goal**: a trace event for a deferral (the trace's kind table
   is ADR-0024's, at its amendment cap), and the kit writing factory items.

## Consequences

- **Good**: in a factory project the forge holds no duplicate plan; a consumer
  with no factory runs exactly as before; the check is two `test -f` calls.
- **Bad / trade-off**: a deferral leaves no trace line, so `/retro` cannot count
  deferrals until a later record adds an outcome for it.
- **Neutral**: this repository is a factory project and defers like any other,
  with the operator's per-run override for exceptions.
- **Honest limitation**: the check trusts presence. A `SKILL.md` placed under a
  skill root by hand counts as installed whatever it holds, and a harness that
  discovers skills elsewhere is not seen.

## More information

- Implemented in: #935 (factory item T-72), PRD-12 slice 2; `/to-prd` follows in slice 3.
- Held by: `tests/spec-skills.test.sh` (the factory-project section, which runs
  `FACTORY.md`'s own fenced check against fixture repositories) and
  `tests/self-host.test.sh` (process/R136).
- Related: PRD-12 §3 and §8; `docs/specs/process.md` process/R121 to R127, R136,
  R223 to R225.
