# The eight questions — each in full

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
before the quiz), `ticket.start` (the tier the implementing session read,
and its `outcome`), `finding.raise` (`data.severity`), `pr.iterate`
(`data.iteration`, `outcome`), and the token fields of every event inside
the ticket's runs.*

- Group tickets by `tier`. Per tier: PRs opened, critical and high findings
  raised per PR, iterations to the first `pr.iterate outcome=green`, and the
  cost of the ticket's runs (`summary --by skill` gives the whole; the pivot
  gives it per ticket).
- A tier whose PRs average more criticals or more iterations than the tier
  above it is mis-rubriced: the work needed more judgement than the stamp
  bought. `mechanical` iterating like `implementer` is the classic case.
- A `ticket.start` with `outcome` `disputed` — the implementer demonstrated
  the stamp wrong — or `defaulted` — the ticket carried no tier at all — is
  counted per tier, before any PR opens: `disputed` is a finding about the
  rubric, `defaulted` one about the stamping in `/to-tickets`.
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
sub-agent that raised it), `finding.triage` (`data.source`, `data.id`,
`outcome`, `reason`).*

- Join raise to triage on `data.id` within one PR, and only the triages with
  `data.source=local` and a standards id (`C-`, `H-`, `M-` or `L-N`): a
  check, a bot comment and a human comment are triaged too, under ids no
  review raised, and a confirm-list item has no raise by design — `/review-pr`
  records that axis as a verdict count. The ids restart with every review, so on
  a PR reviewed more than once pair each triage with the latest raise of its
  id before it, by `ts`. Per `data.agent`: findings raised, accepted,
  `rejected`, escalated, answered.
- A rejection carries a **policy citation** when its `reason` names a
  decision record, an article, or a rule of this repo — the triage said "we
  decided otherwise", not "this is wrong". Count those separately from
  rejections for being mistaken.
- An agent whose findings are rejected with a citation more often than they
  are accepted, over at least three PRs, is asking for something the repo
  has decided against: its prompt is the finding. An agent whose findings
  are accepted every time and are all `low` is a different finding — signal
  that costs a spawn and changes little.
- A finding raised by nobody — a `finding.triage` with `data.source=local`
  and a standards id, and no `finding.raise` of that id before it on that
  PR — is chain health (question 6), noted here and counted there.

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
- A priced read — `summary`, `export --csv` — that prints the stale-table
  advisory on stderr is a finding too: every cost in the window was priced
  from a table nobody re-checked inside its own window. Put the table's
  `Last checked` date beside every cost figure in the report.
- A session whose usage dwarfs its outcome — no `pr.open`, or a PR that took
  more iterations than the wave's median at more cost than its median — is a
  ticket-sizing finding: the ticket was too big for one context window, or
  the tier under it was wrong (question 1).
- Cost per skill against what the skill produced: a review that costs more
  than the implementation it reviewed is worth naming, not necessarily worth
  changing.

Route: `/to-tickets` — a price-table row or re-check, a domain mapping in
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
  reached and a fallback the session then chose — a window where the
  crossing never worked is a finding about the mapping, not about the
  session. `outcome=in-session` on a `spawn` is not a fallback marker: every
  spawn a skill runs itself carries it. A
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

## 8. Stamp calibration

*Reads: `ticket.write` — the published `tier`, `data.tier_proposed` (the
tier before the quiz), `data.confidence` (the tier's, as drafted) and
`data.label_confidence` (the label's, under its own key); `finding.raise`
(`data.severity`, `data.where`); `finding.dismiss` (`data.where`,
`data.thread`) — a human closing a posted finding with no commit answering
it; and `run.start`, for the `skill` of the run each of them was emitted in.*

A stamp is a judgement; this question asks what happened to it. It is
answered per decision field and per skill, never one number for the chain:
one row per field (`tier`, `label`, `severity`), per skill that stamped it,
per value the stamp carried — so an easy field's score cannot hide a hard
field's, and a row says whose stamp it was. The skill is read from three
places in order, and the first that answers names the row: the event's own
`skill`; else the `skill` of the `run.start` its `run` points at — a finding
is raised inside a review's run and carries no skill of its own; else, for a
kind exactly one chain skill emits, that skill — a `ticket.write` is
`/to-tickets`'s and a `finding.raise` is `/review-pr`'s — and the row says so,
`(by kind)` after the skill's name: the ticket-writing skill opens no run and
its emit names no skill, so without this step every tier and label row would
be nobody's. An event none of the three names goes on a row named
`unattributed`.

- **A row is never named by trace text.** Three values name a row — a
  confidence, a severity, a skill — and each is held to what the project
  declares before it is printed: a confidence and a severity to the words
  `sh scripts/vocab.sh fields` prints for that field, a skill to a directory
  under `.agents/skills/`. A value outside them is counted on one row per
  field named `undeclared`, which prints the count and never the value:
  `skill` and `data.*` carry whatever a session typed, forge text included,
  and a row's name is read by the human as the report's own word.
- **The tier, per confidence.** Take one `ticket.write` per subject, the
  latest by `ts`, and group by `data.confidence` — `low`, `medium`, `high`.
  A ticket was overridden at the quiz when its `tier` differs from its
  `data.tier_proposed`. Per group: how many were overridden, of how many
  carry both keys. A `ticket.write` with no `data.confidence` was written
  before the stamp existed: it goes in a row named `unstamped`, and one with
  no `data.tier_proposed` has no override to read — count it on its row and
  leave it out of the denominator. A confidence that is none of the three
  words goes on the `undeclared` row below.
- **The label, in a row of its own.** `ticket.write` records the label's
  confidence (`data.label_confidence`) and the label as published, but no
  label from before the quiz, so the label's override rate is not computable
  from the trace today. The row prints the stamps per confidence and those
  words in place of a rate. It is a candidate ticket — the emit that would
  have to record the drafted label — never a guess: no rate is inferred
  from the tier's.
- **The severity, per band.** Group the `finding.raise` events by
  `data.severity`. A raise was dismissed when a `finding.dismiss` sits on its
  subject with its `data.where`; where a pull request was reviewed more than
  once, pair the dismissal with the latest raise at that `data.where` before
  it, by `ts`. One dismissal is a (`data.thread`, `data.where`) pair, counted
  once per subject: a thread resolved and its review dismissed can both
  emit, and so can two iterations that saw the same thread. Two findings
  raised on one line join to one dismissal — count both as dismissed, and say
  on the row how many shared one. A dismissal that joins no raise — a third
  party's review, a path the emitter would not type — is counted beside the
  table, in no band.
- **The dismissal rate's denominator overcounts.** It is every raise on the
  subject, and a `finding.raise` records a finding the review raised, with no
  marker that it was posted on the forge: a finding nobody posted could not
  have been dismissed and is still in the denominator, as is a finding raised
  again by a second review. The report says so under the severity rows,
  every time: the rate is a lower bound on the share of posted findings a
  human dismissed, not a measurement of it.
- **Every row carries the oracle clause** — who wrote the oracle this number
  was measured against, when, against which version, and what it was compared
  to (`docs/domain-glossary.md`, Oracle): `— oracle: <who>, <when>,
  <version>, <comparator>`. For a tier row the oracle is the human at the
  quiz, over the window, against the tier rubric in `/to-tickets` as it stood
  when the window closed — its version or its commit — the published tier
  compared with the proposed one; for a severity row it is the human who closed the thread, the
  dismissals compared with the raises on the same pull request. Both end
  `no held-out set`: the operator who confirmed the stamps is the operator
  reading the table, and the row must not read as anything else.
- **A row with too few events says so.** Fewer than five events in a row's
  denominator is a count, not a rate: print the counts and `too few to rate`
  instead of a rate. A window with raises and no `finding.dismiss` at all is
  the same case, not a band nobody dismissed: the severity rows print their
  raises and `no dismissal recorded in the window`, and whether the emitter
  ran is question 6's to ask. A window where every row reads one of those
  ways reports the table as it stands and carries the question to the next
  retro.

The rows read like this — the field, the skill, the stamp's value, the
counts, the rate or the words that replace it, the clause:

```
tier · to-tickets (by kind) · low       5 of 7 overridden   71 %   — oracle: the human at the quiz, <window>, <version>, published tier against proposed; no held-out set
tier · to-tickets (by kind) · medium    1 of 3 overridden   too few to rate   — oracle: the human at the quiz, <window>, <version>, published tier against proposed; no held-out set
label · to-tickets (by kind) · medium   9 stamped           override rate not computable from the trace today   — oracle: none — the trace holds no label from before the quiz
severity · review-pr · low              2 of 11 dismissed   18 %   — oracle: the human who closed the thread, <window>, <version>, dismissals against raises on the same pull request; no held-out set
```

What counts as a finding, among rows that carry a rate: `high` stamps
overridden as often as `low` ones, or more — the confidence orders nothing,
and the quiz sorted by it is sorted by noise; a `low` row overridden more
often than not — read the `reason` of the overridden stamps for the rubric
question they share, which is the line the ticket would change; a severity
dismissed more often than it stood — the band is drawn where humans do not
act on it. The label's row is a finding until the trace can answer it.

Route: `/to-tickets` — the confidence rule or a rubric line there, a severity
band's definition in `/review-pr`, or the `ticket.write` emit that records no
drafted label.
