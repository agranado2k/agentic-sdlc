# ADR-0030: A cascade diff's reviewer is resolved from the author its verdict recorded

- **Status**: Accepted
- **Date**: 2026-10-14
- **Deciders**: the planner session for #778, under the operator's delegation of rulings; the merge of its pull request is the operator's yes
- **Supersedes / amends**: amends ADR-0027 clause 4 ("name the author, not the session") and closes the limitation its Consequences record ("no script can see who wrote a diff"), for a diff the cascade built; a new record because ADR-0027 is a record of its own and a partial replacement of a clause is not an in-place edit (`docs/adr/INDEX.md`, conventions)
- **Superseded by**: —

## Context and problem statement

ADR-0027 gives a diff the Sonnet family wrote an Opus reviewer, but only when
the session names the diff's author in `AGENT_SESSION_MODEL` when it looks up
the reviewer. That record called it a limitation: nothing checks the name. The
retro of 2026-10-14 (`retro-20261014T104726Z`) found the way it fails. The
trace's rung spawn records the author (`sonnet`), but #762's rung commits
carry a co-author trailer naming the session's family. Git misnames the
author, and a session that trusts git asks for a review on the author's own
family, which ADR-0007 exists to prevent.

#777 put every rung verdict through one helper in the skill dispatcher
(`_cascade_verdict` in `scripts/skill-dispatch.kit.sh`) and made the open-PR
step wait for a verdict. So the dispatcher always knows which rung's work
passed and what model that rung ran on. The review dispatch for the ticket is
also the dispatcher's (`skill-dispatch.kit.sh review-pr --tier reviewer …`).

## Decision drivers

- ADR-0007 and ADR-0027, read per author: a diff is never reviewed by its author's family.
- A fact a script holds is not left to a session to restate.
- ADR-0024 clause 7: the chain never reads the trace. The review dispatch runs in a session, so it cannot read the author out of the trace.
- No shared-layer change. The dispatcher is kit-only, and no shipped skill moves.

## Considered options

1. **The verdict records the author in the trace and in the worktree's git dir; the review dispatch reads the git-dir record and refuses a cascade-built ticket with none** *(chosen)*.
2. **The review dispatch reads the author out of the trace.** Rejected. It would make a session-run script a reader of the trace, against ADR-0024 clause 7.
3. **Strip or rewrite the rung commits' co-author trailer.** Rejected. A trailer is the agent harness's, and a correct trailer still leaves a session to read it and say it. The fact would stay one the session restates.
4. **Fall back to the session's model when no author is recorded.** Rejected by the ticket. For a cascade-built ticket the session's model is the wrong answer, so no default stands in for the record.

## Decision outcome

Chosen: **option 1.**

1. **The verdict records the author.** `_cascade_verdict` writes the rung's model as `data.author` on every verdict, `passed`, `escalated` and `failed`, beside the model and the two exit codes.
2. **A passed verdict also leaves the author for the review.** It writes `skill-cascade-author` in the worktree's git dir, never its working tree (which the guard judges): `model=<the rung's model>` and `ticket=<#N, or none when the cascade ran with no --ticket>`. Only a passed rung's work is the diff under review, so only a passed verdict writes the record. A cascade started again in the worktree removes it first, so a record never outlives the cascade that wrote it.
3. **The review dispatch resolves from it.** For `review-pr`, the dispatcher reads the record from `--worktree`, or from the checkout it runs in. A record whose ticket is exactly the dispatch's — `#N` for `--ticket N`, `none` for a dispatch with no `--ticket` — sets `AGENT_SESSION_MODEL` to the recorded author, whatever the session named, and stderr says so. The dry run names the reviewer that author resolves. A record for any other ticket is no author: a stale record in a reused worktree never answers an unrelated review.
4. **A cascade-built ticket with no author is refused.** A `--ticket-file` whose stamp is `mechanical`, whose Acceptance opens with an oracle line on the closed list, under a policy that declares `AGENT_CASCADE_MECHANICAL`, is cascade-built. With no record for its ticket, the review dispatch exits 2, names what is missing and names `--rung-done`, the call that records the verdict and its author. It never falls back to the session's model.
5. **Every other review is unchanged.** A ticket the cascade did not build, or a dispatch with no `--ticket-file` and no record, resolves against the session as ADR-0027 says.
6. **The answers under the kit's Claude Code policy**: a Sonnet rung's diff gets `opus` whatever the session names, through the shared resolver's exact refusal of `sonnet` and ADR-0027's fallback.

## Consequences

- **Good**: a cascade-built PR's reviewer no longer depends on a session naming its author correctly. The co-author trailer can say anything.
- **Good**: a review dispatched before the rung was judged is refused, the same gap #777 closed for the open-PR step.
- **Bad / trade-off**: the refusal needs the ticket body as `--ticket-file`. A review dispatched with no `--ticket-file` and no record is not known to be cascade-built, and resolves against the session as before. The root manual's dispatch row names `--ticket-file` for that reason.
- **Bad / trade-off**: a cascade whose cheap rung's agent harness is unreachable falls through to a plain dispatch (exit 69) with no verdict, so it records no author, and its review is refused. The kit's cascade model names no agent harness, so the kit never takes that path. A consumer-shaped policy that does is a ticket for when one exists.
- **Bad / trade-off**: a cascade that failed hands the ticket back to a human. A fix made on that ticket is not a rung's work, so it records no author, and its review is refused until the ticket is re-stamped off `mechanical` by `/to-tickets`.
- **Honest limitation**: the author is the model the rung was resolved to, as the shared resolver printed it. The review dispatch compares through the same resolver, exactly, so a rung recorded as a pinned id is refused only that id, not its family. The kit's cascade model is the family word `sonnet`, so the kit's answer is `opus`.

## More information

- Implemented in: the PR for #778 (`feat/778-reviewer-from-rung-author`). Held by `tests/skill-cascade.test.sh` section 9: the passed verdict's `data.author`; a Sonnet rung's diff gets `opus` with the session naming `opus`, `sonnet`, a Fable id or nothing; the dry run; a record for another ticket (with or without `--ticket` on the review), no record, an unjudged rung, a cascade with no passed verdict and a restarted cascade are each refused; a ticket the cascade did not build resolves against the session; an escalated cascade whose rung 2 passes records rung 2's model, and its review resolves against that author; a ticketless cascade's record answers a ticketless review. Each case was shown failing before the record and the read existed.
- Related: ADR-0007 (the refusal), ADR-0018 (the cascade rung), ADR-0024 clause 7 (the chain never reads the trace), ADR-0027 (a Sonnet author's diff is reviewed by Opus).
