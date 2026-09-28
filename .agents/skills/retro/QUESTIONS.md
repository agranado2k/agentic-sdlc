# The seven questions — each in full

`/retro` answers these in order, over one window, from one CSV export. For
every question: what to read, how to join it, what counts as a finding, where
the finding goes. A finding's entry in the report carries the question
number, the evidence (subjects and counts), and the route.

The joins are on the subject strings the trace already carries: a ticket is
`ticket:#N`, a PR `pr:#N`, a run `run:<id>`; a PR joins its ticket through
the `related` field of its `pr.open`, and every event inside a skill
invocation carries that invocation's `run`. `sh scripts/trace.sh show pr:#<N>`
prints one PR's whole trail when the pivot needs a second look.

## 1. Tier calibration

*Reads: `ticket.write` (the `tier`, and `data.tier_proposed` — the tier
before the quiz), `ticket.start` (the tier the implementing session read),
`finding.raise` (`data.severity`), `pr.iterate` (`data.iteration`,
`outcome`), and the token fields of every event inside the ticket's runs.*

- Group tickets by `tier`. Per tier: PRs opened, critical and high findings
  raised per PR, iterations to the first `pr.iterate outcome=green`, and the
  cost of the ticket's runs (`summary --by skill` gives the whole; the pivot
  gives it per ticket).
- A tier whose PRs average more criticals or more iterations than the tier
  above it is mis-rubriced: the work needed more judgement than the stamp
  bought. `mechanical` iterating like `implementer` is the classic case.
- A ticket whose `tier` differs from its `data.tier_proposed` is a quiz
  override. Compare its iterations and criticals with its proposed tier's
  average: an override that paid for itself is the rubric lagging the human;
  one that did not is the human lagging the rubric. Both are findings about
  the rubric's wording.

Route: `/to-tickets` — a change to the tier rubric's questions, or to the
tier → model mapping in `scripts/agents.config.sh` when the tier is right and
the model under it is what iterates.

## 2. Review signal

*Reads: `finding.raise` (`data.id`, `data.severity`, `data.agent` — the
sub-agent that raised it), `finding.triage` (`data.id`, `outcome`, `reason`).*

- Join raise to triage on `data.id` within one PR. Per `data.agent`: findings
  raised, accepted, `rejected`, escalated, answered.
- A rejection carries a **policy citation** when its `reason` names a
  decision record, an article, or a rule of this repo — the triage said "we
  decided otherwise", not "this is wrong". Count those separately from
  rejections for being mistaken.
- An agent whose findings are rejected with a citation more often than they
  are accepted, over at least three PRs, is asking for something the repo
  has decided against: its prompt is the finding. An agent whose findings
  are accepted every time and are all `low` is a different finding — signal
  that costs a spawn and changes little.
- A finding raised by nobody — a `finding.triage` with no matching
  `finding.raise` — is chain health (question 6), noted here and counted
  there.

Route: `/to-tickets` — a prompt change for one agent in `/review-pr`, with
the citation the rejections kept making.

## 3. Recurring failures

*Reads: `pr.iterate outcome=red` (`reason` names the failing check),
`finding.triage` (`data.source` — `check`, `bot`, `human`, `local` — and
`data.id`), `tdd.cycle outcome=red` (`reason`, `data.test`).*

- Group the red iteration reasons by the check they name; group triages by
  `data.source` and `data.id`. A check that failed on two or more PRs, or a
  triage class that recurs across PRs, is a recurring failure.
- The finding is the recurrence, not the failure: one PR failing the docs
  gate on a dead path is Tuesday; three PRs failing it on the same rule is a
  rule nobody can see coming.
- The route is always **a rule with a failing check**: a docs-gate validator
  with a fixture that fails without it, a guard, a suite assertion — whatever
  makes the next PR fail locally before it fails in review. It is never a
  preloaded lessons file, never a line in the manual asking agents to
  remember, never a note in a skill's anti-patterns: prose is read by every
  request and enforced by none (shared invariant §11).

Route: `/to-tickets` — one ticket per recurrence, naming the check to add
and the fixture that proves it can fail.

## 4. Diagnosis calibration

*Reads: `hypothesis` — `outcome=proposed` with `data.rank`, then
`confirmed`, `refuted` or `inconclusive` with the `data.rank` it held — per
diagnosis `run`.*

- Per diagnosis run: the rank of the hypothesis that was `confirmed`. Over
  the window: how many diagnoses, how often rank 1 was the one, the mean
  rank of the confirmed hypothesis, and how many runs closed with none
  confirmed.
- A first-ranked hypothesis confirmed in fewer than half the diagnoses says
  the ranking step is not paying for its probes; a mean rank near the number
  of hypotheses says the ordering is arbitrary. Both are findings about how
  `/diagnose` ranks, not about any one bug.
- Fewer than three diagnoses in the window is a denominator, not a finding:
  report the numbers and carry the question to the next retro.

Route: `/to-tickets` — a change to the hypothesis step in `/diagnose`.

## 5. Spend

*Reads: `session.usage` (four token counts per model per session),
`agent.stop` and `spawn.end` (a sub-agent's or a worker's tokens), and the
`cost_usd` column the export computes from the price table at read time.*

- `sh scripts/trace.sh summary --by model --since <YYYY-MM-DD>` for the models and their cost; `--by skill` and `--by session` for where it went. The pivot gives cost per ticket: every token-bearing event inside a run whose skill opened on that ticket.
- A cost cell reading `unpriced` is a model the price table does not name.
  That is a finding about the policy file, and until it is fixed every total
  that includes the model reads `unpriced` too — say so in the report rather
  than quoting a partial sum.
- A session whose usage dwarfs its outcome — no `pr.open`, or a PR that took
  more iterations than the wave's median at more cost than its median — is a
  ticket-sizing finding: the ticket was too big for one context window, or
  the tier under it was wrong (question 1).
- Cost per skill against what the skill produced: a review that costs more
  than the implementation it reviewed is worth naming, not necessarily worth
  changing.

Route: `/to-tickets` — a price-table row, a domain mapping in
`scripts/agents.config.sh`, or a sizing finding for the wave's next
decomposition.

## 6. Chain health

*Reads: `ticket.write`, `ticket.start`, `pr.open`, `merge.land`, `spawn`,
`spawn.end` (`outcome` — `ok`, `fail`, `timeout`, `budget`, `unreachable`),
`run.start`, `run.end`.*

- **Tickets with no PR**: a `ticket.write` with no later `ticket.start`, or a
  `ticket.start` with no `pr.open`, inside the window and older than the
  wave's median ticket.
- **PRs with no landing**: a `pr.open` with no `merge.land` — and a PR the
  forge shows merged with no `merge.land` at all, which is `/merge-train`
  not emitting, a different finding from a PR still open.
- **Spawns that ended badly**: a `spawn.end` with `outcome` `fail`, `timeout`
  or `budget`; an `unreachable` one, which is a vendor that could not be
  reached and a fallback the session then chose — the trace shows the choice
  (`spawn outcome=in-session` beside it), and a window where the crossing
  never worked is a finding about the mapping, not about the session. A
  `spawn` with no `spawn.end` is a worker nobody waited for — but a window
  with no `spawn.end` at all, against spawns that plainly ended, is **one**
  finding about the emitter (the dispatcher or the skill that spawned), never
  one per spawn. The same rule holds for any kind: an absent kind is one
  hole, not a finding per event that should have had it.
- **Runs never closed**: a `run.start` with no `run.end` — a session that
  stopped without saying how, or a skill whose end line nobody ran.
- **Missing emits**: a skill that ran — its PR exists, its worktree was
  pruned — with no events of its own. The chain's contract is one emit per
  decision point; a hole is a fact the retro reads as one.

Route: `/to-tickets` — the skill whose emit is missing or whose end is never
reached, the dispatcher whose workers end badly, or the mapping whose vendor
is never reachable.

## 7. Aim calibration

*Reads: `feedback` — subject `ticket:#N`, `related` its `pr:#N`, `outcome`
one of `hit`, `adjusted`, `missed`, `reason` the operator's words — emitted
by `/merge-train` at landing and by `/pr-iterate` when a human comment
changes the plan; joined to `ticket.write` for the tier and to the `skill`
of the runs that built it.*

- Per landed slice in the window: its verdict, if one was given. `hit` is
  the plan holding; `adjusted` is a re-cut of what came after; `missed` is
  the slice itself being wrong. Count how many landed slices were followed
  by a re-cut (`adjusted` or `missed`), and name the tier and the skill that
  produced each miss.
- Misses clustered on one tier are question 1's finding seen from the other
  side — the stamp bought less judgement than the slice needed. Misses
  clustered early in a wave are the ordering: the slice that would have
  exposed the misunderstanding was not sequenced first (feedback-first
  ordering, `/to-tickets` rule 13).
- Landed slices with no `feedback` at all are their own finding: the verdict
  is not being asked, and without it the next slice is chosen from the plan
  alone. A wave with landings and no verdicts reports the count and routes
  it to `/merge-train`, where the question is asked.

Route: `/to-tickets` — the ordering rule or the tier rubric, with the misses
as evidence; the missing verdicts to `/merge-train`.
