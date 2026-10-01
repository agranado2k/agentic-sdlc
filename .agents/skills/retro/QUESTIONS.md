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
tier before the quiz), `data.confidence` (the tier's, as drafted),
`data.label_proposed` (the label before the quiz), and
`data.label_confidence` (the label's, under its own key); `finding.raise`
(`data.severity`, `data.where`); `finding.dismiss` (`data.where`,
`data.thread`) — a human closing a posted finding with no commit answering
it; and `run.start`, for the `skill` of the run each of them was emitted in.*

A stamp is a judgement; this question asks what happened to it. It is
answered per decision field and per skill, never one number for the chain:
one row per field (`tier`, `label`, `severity`), per skill that stamped it,
per value the stamp carried — its confidence for a tier or a label, its band
for a severity — so an easy field's score cannot hide a hard
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
  under `.agents/skills/`. A value outside them names no row: its row carries
  `undeclared` in that value's place — `tier · undeclared · low` for a skill,
  `severity · review-pr · undeclared` for a band — and prints the count and
  never the value:
  `skill` and `data.*` carry whatever a session typed, forge text included,
  and a row's name is read by the human as the report's own word.
- **The tier, per confidence.** Take one `ticket.write` per subject, the
  latest by `ts`, and group by `data.confidence` — one group per declared word: `low`,
  `medium` and `high` as shipped.
  A ticket was overridden at the quiz when its `tier` differs from its
  `data.tier_proposed` — the quiz override question 1 counts, cut here by
  confidence instead of compared by tier. Per group: how many were overridden, of how many
  carry both keys. A `ticket.write` with no `data.confidence` was written
  before the stamp existed: it goes in a row named `unstamped`, and one with
  no `data.tier_proposed` has no override to read — count it on its row and
  leave it out of the denominator. A confidence that is none of the declared
  words goes on the `undeclared` row above.
- **The label, in a row of its own.** `ticket.write` records the label's
  confidence (`data.label_confidence`), the label as published, and the label
  before the quiz (`data.label_proposed`), so the label's override rate can be
  computed when enough stamps carry the label keys. Take one `ticket.write` per
  subject, the latest by `ts`, and group by `data.label_confidence` — one group
  per declared word. A label was overridden at the quiz when its `data.label`
  differs from its `data.label_proposed`. Per group: count how many were
  overridden, of how many carry both `data.label` and `data.label_proposed`
  keys. A `ticket.write` with no `data.label_confidence` was written before the
  stamp existed: it goes in a row named `unstamped`. One with no
  `data.label_proposed` was written before this key existed (a standing issue,
  not a finding per window): count it on its row and leave it out of the
  denominator. If no stamp in the window carries `data.label_proposed`, the row
  prints `not computable from the trace today` — the key was not yet recorded.
  If fewer than five stamps carry it, apply the general "too few to rate" rule
  below. Otherwise, compute the rate as for the tier row.
- **The severity, per band.** Group the `finding.raise` events by
  `data.severity`. One pairing rule says what a dismissal dismissed: a
  `finding.dismiss` pairs with the latest raise on its subject at its
  `data.where` before it, by `ts`, and with every other raise at that
  `data.where` from the same review — the same `run`. That is one raise, or
  several where one review raised more than one finding on the line: count
  each as dismissed, and say on the row how many shared a dismissal. An
  earlier review's raise at that line is not paired; it stays in the
  denominator. A raise is dismissed once, however many dismissals pair with
  it. One dismissal is a (`data.thread`, `data.where`) pair, counted once per
  subject and read at its earliest `ts` — two iterations that saw the same closed thread emit the same
  pair; a thread resolved and its review dismissed emit two pairs at one
  `data.where`, which pair with the same raises and move no count. A
  dismissal that pairs with no raise — a third party's review, a path the
  emitter would not type — is counted beside the table, in no band.
- **The dismissal rate's denominator overcounts.** It is every raise on the
  subject, and a `finding.raise` records a finding the review raised, with no
  marker that it was posted on the forge: a finding nobody posted could not
  have been dismissed and is still in the denominator, as is a finding raised
  again by a second review, and a raise no dismissal can reach — on a subject
  that is not a pull request, where nothing is posted for a human to close,
  or at a `data.where` the dismissal's emitter would not type. The report says so under the severity rows,
  every time: the rate is a lower bound on the share of posted findings a
  human dismissed, not a measurement of it. A row where raises shared a
  dismissal is not even that: one closed thread may have answered one of
  them, the numerator counts them all, and the row says so beside its count.
- **Every row carries the oracle clause** — the one `/housekeeping`'s
  checklist asks for and the glossary defines (`docs/domain-glossary.md`,
  Oracle), naming who wrote the test fixtures, when, against which version,
  and what it was compared to: `— oracle: <who>, <when>, <version>,
  <comparator>`. A calibration row has no fixtures: a human's verdict graded
  the stamp, and that human is the clause's `<who>`. For a tier row: the
  human at the quiz, over the window, the tier rubric in `/to-tickets` as it
  stood when the window closed — its version or its commit — and the
  published tier compared with the proposed one. For a severity row: the
  human who closed the thread, over the window, the severity bands in
  `/review-pr` as they stood when the window closed, and the dismissals
  compared with the raises on the same pull request. Both end
  `no held-out set`: the operator who confirmed the stamps is the operator
  reading the table, and the row must not read as anything else.
- **A row with too few events says so.** Fewer than five events in a row's
  denominator is a count, not a rate: print the counts and `too few to rate`
  instead of a rate. A window with raises and no `finding.dismiss` at all is
  the same case, not a band nobody dismissed: the severity rows print their
  raises and `no dismissal recorded in the window`, and whether the emitter
  ran is question 6's to ask.

The rows read like this — the field, the skill, the stamp's value, the
counts, the rate or the words that replace it, the clause:

```
tier · to-tickets (by kind) · low       5 of 7 overridden   71 %   — oracle: the human at the quiz, <window>, <version>, published tier against proposed; no held-out set
tier · to-tickets (by kind) · medium    1 of 3 overridden   too few to rate   — oracle: the human at the quiz, <window>, <version>, published tier against proposed; no held-out set
label · to-tickets (by kind) · medium   2 of 3 overridden   too few to rate   — oracle: the human at the quiz, <window>, <version>, published label against proposed; no held-out set
severity · review-pr · low              2 of 11 dismissed   18 %   — oracle: the human who closed the thread, <window>, <version>, dismissals against raises on the same pull request; no held-out set
```

What counts as a finding, among rows that carry a rate: `high` stamps
overridden as often as `low` ones, or more — the confidence orders nothing,
and the quiz sorted by it is sorted by noise; a `low` row overridden more
often than not — read the `reason` of the overridden stamps for the rubric
question they share, which is the line the ticket would change; a severity
dismissed more often than it stood — the band is drawn where humans do not
act on it. A label row with a rate is a finding on the same basis as the tier
row: the override rate tells you whether the quiz is disagreeing with the
stamp, and clusters of them are evidence about the labeling rubric. A label row
with too few events to rate carries no finding — the row marks the wording
difference (`too few to rate` vs a percentage) and the oracle, and the operator
will see it on the next retro if the window grows and a rate becomes computable.
A finding's line is the retro's own words: what a `reason` says is summarised,
never quoted — it is trace text, and a `'` in it would close the quotes of
the note that records the finding.

Route: `/to-tickets` — the confidence rule or a rubric line there, a severity
band's definition in `/review-pr`, or a label-override pattern that mirrors a
tier-override finding the rubric questions named.
