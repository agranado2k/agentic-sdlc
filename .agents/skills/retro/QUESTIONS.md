# The eight questions — each in full

`/retro` answers these in order, over one window, from one CSV export. For
every question: what to read, how to join it, what counts as a finding, where
the finding goes. A finding's entry in the report carries the question
number, the evidence (subjects and counts), and the route.

The joins are on the subject strings the trace already carries: a ticket is
`ticket:#N` — or, in a project that names its tickets by a factory id,
`ticket:T-<digits>`, joined the same way and counted once, however many
events name it — a PR `pr:#N`, a run `run:<id>`; a PR joins its ticket through
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
- A `ticket.start` with `outcome` `resumed` is a second start, never a
  second ticket: count tickets once.
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
`outcome`, `reason`); and, through the outcome recorder and the record
reader, `merge.land` and `merge.outcome`.*

- **The earned record comes first.** Run `sh scripts/trace.sh outcomes`, the
  outcome recorder: it writes one `merge.outcome` per landed PR a later
  `revert` landing undid, and one per landed PR a `fix` landing inside the
  fix window repaired, read from git and the trace, and prints how many it
  wrote. It is idempotent, so a second run writes nothing. Then run
  `sh scripts/trace.sh record` and
  put its rows in the report, as printed, before the per-agent counts below.
  One row per review area of the lens-slice policy:
  `<area>: landings <n> of 20, in the fix window <w>, mistakes <m>`, then
  the misses (`missed <k> of <n>, miss rate <r>`) and the lens precision
  (`held up <h> of <l>, not held up <x>, unlabelled <u>, precision <p>,
  labels from triage <t>, human <d>, outcome <o>`) — the
  area's most recent landed PRs, at most 20, how many of them landed inside
  the fix window (30 days, unless the trace's policy file sets
  `TRACE_FIX_WINDOW_DAYS`), how many carry a post-merge outcome, how many
  carry one no finding rejected at triage named a file of, and how the
  findings raised on them held up. Where a verifier reviews beside the kit's
  own review, each area's row is followed by one verifier row per rung,
  `<area> verifier cross-provider:` and `<area> verifier same-provider:` —
  its findings by the same labels, its precision, the mistakes it caught,
  the landings it blocked where the kit's review passed, and the kit
  findings it confirmed and disputed, each by label; put those rows in the
  report as printed too, so the rungs can be compared. The area's own row is
  the kit's review alone. A ratio over nothing reads `n/a`. The record
  is each area's last 20 landings as of now, not cut to the window. Reverts,
  fixes inside the fix window and, where the repository holds a `.factory/`
  folder, failed factory QA are recorded; a ticket id the recorder names on
  stderr is a failed QA it could not join to a landed PR — report it beside
  the rows. The record compares nothing to a threshold, and neither does this
  question: the rows are reported, never a finding on their own.
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

*Reads: `session.usage` (four token counts per model per session, and
`data.via=rollup` on the gap a compaction left — or, with `outcome=fail`,
on a rollup that was refused), `session.end` (`data.phantoms`, the
session's phantom stops), `agent.stop` and `spawn.end` (a sub-agent's or a
worker's tokens; a stop's `tier`, `domain` and `skill` say which spawn it served,
`unattributed` when none was handed, and its `data.ticket` the ticket when
no run was), `spawn` (a cascade rung's verdict, `data.rung`), `data.out_snapshot` on any of those token-bearing events
(how many of its messages carry a streamed output snapshot), `data.partial`
on a stop priced past a half-written last transcript line, and the
`cost_usd` column the export computes from the price table at read time.*

- `sh scripts/trace.sh summary --by model --since <YYYY-MM-DD>` for the models and their cost; `--by skill` and `--by session` for where it went. The pivot gives cost per ticket: every token-bearing event inside a run whose skill opened on that ticket. An `agent.stop` no such run ties to a ticket — its spawn handed no run, so it is filed under none or under whatever run its checkout held — takes `data.ticket` as its fallback join: the ticket its spawn's `Trace-Spawn:` line named, recorded only on a stop no run was handed to.
- **Per tier, per skill and per cascade rung** — one span over the priced
  export prints the answer, a row per line, `<axis> <key> <spawns> <cost>`:
  `sh scripts/trace.sh export --csv --since <YYYY-MM-DD> | awk 'function csv(s, f,   n, q, c, t) { n = 0; q = 0; t = ""; while (s != "") { c = substr(s, 1, 1); s = substr(s, 2); if (q && c == "\"" && substr(s, 1, 1) == "\"") { t = t c; s = substr(s, 2) } else if (c == "\"") q = !q; else if (c == "," && !q) { f[++n] = t; t = "" } else t = t c } f[++n] = t } function add(r, x) { n[r]++; if (x == "unpriced") u[r]++; else s[r] += x } NR == 1 { csv($0, h); for (i in h) k[h[i]] = i; next } { split("", f); csv($0, f); e = f[k["kind"]]; run = f[k["run"]]; g = match(f[k["data"]], /"rung":"[0-9]+/) ? substr(f[k["data"]], RSTART + 8, RLENGTH - 8) : "" } e == "spawn" && f[k["tier"]] != "" && run != "" { rt[run] = f[k["tier"]]; rs[run] = f[k["skill"]] } e == "spawn" && g != "" && f[k["outcome"]] ~ /^(passed|escalated|failed)$/ { add("verdict rung-" g ":" f[k["outcome"]], 0) } (e == "agent.stop" || e == "spawn.end") && f[k["cost_usd"]] != "" { m++; c[m] = f[k["cost_usd"]]; ti[m] = f[k["tier"]]; sk[m] = f[k["skill"]]; ru[m] = e == "spawn.end" ? run : ""; rg[m] = g; pa[m] = f[k["data"]] ~ /"partial":"yes"/ } END { for (i = 1; i in c; i++) { x = c[i]; t = ti[i] != "" ? ti[i] : rt[ru[i]] != "" ? rt[ru[i]] : "unattributed"; y = sk[i] != "" ? sk[i] : rs[ru[i]] != "" ? rs[ru[i]] : "unattributed"; add("tier " t, x); add("skill " y, x); if (rg[i] != "") add("rung " rg[i], x); if (pa[i]) add("partial stops", x); add("bucket " (x == "unpriced" ? "unpriced" : x + 0 >= 10 ? "10-up" : x + 0 >= 1 ? "1-10" : x + 0 >= 0.1 ? "0.10-1" : "under-0.10"), x); add("total all", x) } for (r in n) printf "%s %d %s\n", r, n[r], r ~ /^verdict/ ? "-" : u[r] ? "unpriced" : sprintf("%.4f", s[r]) }' | sort`.
  A spawn is a token-bearing `agent.stop` or `spawn.end`; a `spawn.end` with
  no tier of its own takes the tier and skill of the `spawn` in its run — the
  cascade's verdicts carry them. A stop with no tier, or with tier
  `unattributed`, is the **unattributed** row, its own row and never dropped:
  its share of the total is how much spend no tier can answer for. `rung <n>`
  sums each cascade rung's spawns, and `verdict rung-<n>:<outcome>` counts
  its `passed`, `escalated` and `failed` — a cheap rung that escalates often
  costs more than the mapped rung alone. `bucket` sorts every spawn by
  **order of magnitude** — under $0.10, $0.10 to $1, $1 to $10, $10 up —
  so the tail that carries the spend shows. The span prints sums, not
  shares: the report divides each bucket's sum by the `total all` row's.
  `partial stops` counts and sums the stops carrying `data.partial` — each
  priced from the complete lines before a last line the agent harness was
  still writing, so its tokens are short by that line. The report names
  their count beside the unpriced ones; no row means none in the window.
- **The first-call prompt** — what a spawn's first call sent, the size of
  the context it starts from:
  `sh scripts/trace.sh export --since <YYYY-MM-DD> | awk -F'"transcript":"' '/"kind":"agent\.stop"/ && NF - 1 { split($2, a, "\""); print a[1] }' | while read -r t; do test -f "$t" && awk 'function n(k) { return match($0, "\"" k "\":[0-9]+") ? substr($0, RSTART + length(k) + 3, RLENGTH - length(k) - 3) + 0 : 0 } /"usage"/ { print n("input_tokens") + n("cache_creation_input_tokens") + n("cache_read_input_tokens"); exit }' "$t"; done | sort -n | awk '{ v[NR] = $1 } END { print NR ? v[int((NR + 1) / 2)] : "none" }'`
  prints the median over the window's stops whose transcript is still on
  disk (`none` when none is). Set it beside the baseline the project's
  spend PRD recorded, when it recorded one.
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
- **The compaction gap**: a `session.usage` with `data.via=rollup` holds the
  tokens a compaction spent and no message carries — part of the session's
  sum, never a second count of it. Report per session how much of the spend
  came that way. One with `outcome=fail` is a rollup the hook refused: that
  session's figure is an undercount by an unknown amount, and the report
  says so beside it instead of quoting the sum as whole.
- **Output read from a snapshot**: an event carrying `data.out_snapshot`
  counted that many messages whose transcript line was written before the
  response closed, so their output count is the streamed snapshot and
  nothing later in the file holds the closing one. Its `tok_out` — and the
  output cost priced from it — is a **lower bound**, short by an unknown
  amount; input and cache counts are whole. Most sub-agent tool turns end
  this way, so report the share of `agent.stop` output that is a lower
  bound beside every output figure, and never compare such a figure as
  exact against one that is not. On a compaction gap (`data.via=rollup`)
  the key means the reverse: the rollup counts those messages' closing
  output, so the gap's `tok_out` holds their remainder beside the
  compaction's own — the session's sum stays whole, its split does not.
- **Phantom stops**: sum `data.phantoms` over a session's `session.end`
  events (a resumed session ends more than once). `0` is a count taken; a
  `session.end` with no `data.phantoms` is a count not taken, never zero. A
  window whose phantoms rise against the last retro's is a finding about
  the agent harness's stop events: a ticket against the adapter that
  counts them.

Route: `/to-tickets` — a price-table row or re-check, a domain mapping in
`scripts/agents.config.sh`, or a sizing finding for the wave's next
decomposition.

## 6. Chain health

*Reads: `ticket.write`, `ticket.start` (and `outcome` `resumed`), `pr.iterate` (`data.cause`), `pr.open`, `merge.land`
(and, the lane's, `outcome` with `data.via=lane` and `data.hold`), `lane.escape` (`outcome`), `spawn`,
`spawn` (`outcome` `refused`), `spawn.end` (`outcome` — `ok`, `fail`, `timeout`, `budget`, `unreachable`),
`agent.stop` with `outcome` `fail` (`data.last_kind`, `data.last_age_ms`) and a priced one (`data.final`),
`run.start`, `run.end`, and `tool.use` with `outcome` `denied` (`data.tool`,
`data.input_head`).*

- **Tickets with no PR**: a `ticket.write` with no later `ticket.start`, or a
  `ticket.start` (a `resumed` one never counted alone) with no `pr.open`, inside the window and older than the
  wave's median ticket.
- **PRs with no landing**: a `pr.open` with no `merge.land` — and a PR the
  forge shows merged with no `merge.land` at all, which is `/merge-train`
  not emitting, a different finding from a PR still open.
- **The low-risk lane**: what the lane carried and why it held the rest.
  A pull request counts once, by its latest lane event in the window: landed
  when a `merge.land` with `outcome=landed` and `data.via=lane` names it,
  held otherwise, by its latest hold's `data.hold` token — a hold the
  operator then landed is still the lane's hold. The tokens print by count,
  a tie in the order the lane checks them, and a token the lane does not
  declare prints `undeclared`, never its text. Escapes count each escaped
  pull request's latest `lane.escape` by outcome — `revert`, `fix`,
  `notified`:
  `sh scripts/trace.sh export --since <YYYY-MM-DD> | awk 'function v(k) { return match($0, "\"" k "\":\"[^\"]*\"") ? substr($0, RSTART + length(k) + 4, RLENGTH - length(k) - 5) : "" } /"kind":"merge\.land"/ && /"via":"lane"/ { p = v("subject"); o = v("outcome"); if (o == "landed") ld[p] = 1; else if (o == "skipped") hd[p] = v("hold") } /"kind":"lane\.escape"/ { es[v("subject")] = v("outcome") } END { n = split("closed drift escape path base-red check-table verifier switch risk undeclared", tk, " "); for (p in ld) l++; for (p in hd) { if (p in ld) continue; h++; for (i = 1; n > i; i++) if (tk[i] == hd[p]) break; c[tk[i]]++ } s = ""; for (m = 1; n >= m; m++) { b = 0; for (i = 1; n >= i; i++) if (c[tk[i]] > c[tk[b]]) b = i; if (!b) break; s = s (s == "" ? " (" : ", ") tk[b] " " c[tk[b]]; delete c[tk[b]] } s = s (s == "" ? "" : ")"); for (p in es) { e++; ec[es[p]]++ } x = ""; split("revert fix notified", eo, " "); for (i = 1; 3 >= i; i++) if (ec[eo[i]]) x = x (x == "" ? " (" : ", ") eo[i] " " ec[eo[i]]; x = x (x == "" ? "" : ")"); print "lane: landed " l + 0 ", held " h + 0 s ", escapes " e + 0 x }'`
  prints, for a wave of fourteen:

  ```
  lane: landed 8, held 6 (risk 4, path 1, check-table 1), escapes 0
  ```

  A hold token that dominates the line is where the lane stops carrying
  work — `risk` the review areas' earned records, `path` the hold list,
  `check-table` the tickets — and an escape is a lane landing that turned
  out wrong: one beside a low landed count is the lane's own finding.
- **Spawns that ended badly**: a `spawn.end` with `outcome` `fail`, `timeout`
  or `budget`; an `unreachable` one, which is a vendor that could not be
  reached and a fallback the session then chose — a window where the
  crossing never worked is a finding about the mapping, not about the
  session. `outcome=in-session` on a `spawn` is not a fallback marker: every
  spawn a skill runs itself carries it. A
  `spawn` with no `spawn.end` is a worker nobody waited for, unless it
  carries `outcome=refused`: that one never started, so nothing ends — but a window
  with no `spawn.end` at all, against spawns that plainly ended, is **one**
  finding about the emitter (the dispatcher or the skill that spawned), never
  one per spawn. The same rule holds for any kind: an absent kind is one
  hole, not a finding per event that should have had it.
- **Refused spawns**: a `spawn` with `outcome=refused` and no `spawn.end` —
  a worker the host or the dispatcher would not start, such as a review lens
  refused at the host's concurrent-subagent limit. Counted per skill; one
  that recurs is a skill planning more workers than the host will run.
- **Stops read too early**: an `agent.stop` with `outcome=fail` is a
  sub-agent whose transcript had not ended when the hook's wait bound
  passed. A give-up leaves no anchor, so a later stop of the same agent
  (its subject) counts what it could not: its tokens are lost only when no
  later stop of that agent was priced. Count them per agent as well as per
  stop — an agent whose last stop is priced lost nothing, and a run
  the agent harness prompted again after its end gives up once on the way.
  A priced stop's `data.final` says how the run ended: `message`, or `tool` — a
  turn-ending tool such as the hand-back. `data.last_kind` is the type of
  the file's last line and `data.last_age_ms` that line's age when the
  bound passed: a young line is an agent still writing — the bound is too
  short, a policy-file value — and an old one an agent whose run ended in
  a shape the hook does not read as final. Count them per shape.
- **Interruptions**: a `ticket.start` with `outcome=resumed` — a session
  died or was replaced before its ticket reached a PR, usage limits the
  commonest cause — and a red or stopped `pr.iterate` whose `data.cause` is `conflict`
  (the PR fell behind a moving main) or `pending-stuck` (a check-run sat
  `in_progress` after its job had ended). Count each per ticket and per
  cause: one that recurs is a wave sized past its sessions, or a main
  moving faster than its PRs land.
- **Runs never closed**: a `run.start` with no `run.end` — a session that
  stopped without saying how, or a skill whose end line nobody ran.
- **Denied tool calls**: each `tool.use` with `outcome=denied` — a call that
  fired its pre-tool hook and never returned, swept at the session's end —
  counted per session and per `data.tool`, with the input head of each. A
  denial that recurs — the same tool, the same command shape, across
  sessions — is a skill asking its agent for what the permission policy or a
  guard will not give it: one finding per shape, never one per call. A
  window with tool capture off holds none, and that is no finding.
- **Missing emits**: a skill that ran — its PR exists, its worktree was
  pruned — with no events of its own. The chain's contract is one emit per
  decision point; a hole is a fact the retro reads as one.

Route: `/to-tickets` — the skill whose emit is missing or whose end is never
reached, the dispatcher whose workers end badly, or the mapping whose vendor
is never reachable.

## 7. Aim calibration

*Reads: `feedback` — subject `ticket:#N` or `ticket:T-<digits>`, `related` its `pr:#N`, `outcome`
one of `hit`, `adjusted`, `missed` or `unasked` (the train's and the lane's alone),
`data.by` one of `operator`, `train` or `lane` (who gave the verdict: a human in
the session, the train under a delegating instruction, or the low-risk lane
landing with no act of the operator's), `reason` the
answerer's words — emitted by `/merge-train` at landing and by
`/pr-iterate` when a human comment changes the plan; joined to
`ticket.write` for the tier and to the `skill` of the runs that built it.*

- Per landed slice in the window: its verdict, if one was given, counting
  `operator` verdicts; `train` ones are reported apart (below). `hit` is
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
- A `feedback` whose outcome is `unasked` is not a verdict: `/merge-train`
  records it when a train ran autonomously and nobody was at the prompt to
  answer. Count it with the landings that got no verdict, never as a
  verdict given, and name the two apart on the row — `<n> unasked, <m>
  without a feedback event` — since the first is a question the train
  could not ask and the second one it never recorded asking.
- Count the verdicts by `data.by`. `operator` is a human's answer; `train`
  is the train judging the slice itself under a delegating instruction —
  never the human's verdict; `lane` is the low-risk lane's landing, always
  `unasked`, and never the human's verdict either. Report the three apart on
  the row — `<n> operator, <m> train, <l> lane` — and a window whose verdicts
  are all `train` or `lane` as **no human verdict**, read with the landings
  that got none. A `feedback` with no `data.by` was written before the key
  existed: count it as `<p> unattributed`, never as the operator's:
  `sh scripts/trace.sh export --since <YYYY-MM-DD> | awk '/"kind":"feedback"/ { b = match($0, /"by":"[^"]*"/) ? substr($0, RSTART + 6, RLENGTH - 7) : ""; if (b == "operator" || b == "train" || b == "lane") c[b]++; else u++ } END { print "feedback by: " c["operator"] + 0 " operator, " c["train"] + 0 " train, " c["lane"] + 0 " lane, " u + 0 " unattributed" }'`
  — any other `data.by` counts as unattributed too.
- **Retired while the project accepts train-only verdicts.** A project
  that delegates its landings may decide that a train's verdict is enough,
  and records so in a binding decision record: one whose text says it
  accepts train-only verdicts and whose status is Accepted —
  `for f in docs/adr/[0-9]*.md; do grep -qi 'accepts train-only verdicts' "$f" && grep -q '^- \*\*Status\*\*: Accepted' "$f" && echo "$f"; done`
  lists it, never the index, a proposed record or a superseded one. Count the window's operator
  verdicts: `sh scripts/trace.sh export --since <YYYY-MM-DD> | awk '/"kind":"feedback"/ && /"by":"operator"/ { n++ } END { print n + 0 }'`,
  skipping, as everywhere, the events before the window's start. With
  that record binding and that count 0, the question answers
  `retired: no operator verdict in the window, and the project accepts train-only verdicts (<the record>)`
  — the record named by its file — in place of the no-human-verdict
  finding and the misses: the row's counts still print, but the retired
  line is no finding, counts toward no total and records no note. It
  resumes by itself: the first window holding one operator verdict
  calibrates as above, the record notwithstanding. A project with no such
  record has the absence raised as before. A landing with no `feedback`
  event at all is still counted on the row — a missing emit, which is
  question 6's to raise, not this one's.

Route: `/to-tickets` — the ordering rule or the tier rubric, with the misses
as evidence; the missing verdicts and the `unasked` ones to `/merge-train`;
a window of `train` verdicts to the operator who delegated them — no skill
asks the question on their behalf; a retired answer routes nowhere.

## 8. Stamp calibration

*Reads: `ticket.write` — the published `tier`, `data.tier_proposed` (the
tier before the quiz), `data.confidence` (the tier's, as drafted), the
published `data.label`, `data.label_proposed` (the label before the quiz)
and `data.label_confidence` (the label's, under its own key), and the
risk's three — `data.risk` as published, `data.risk_proposed` and
`data.risk_confidence`; `risk.judge` (`outcome`, `data.planner`,
`data.rule`, `data.unlearned`, `data.switch`) — the risk rule against the
planner, one per pull request and head;
`finding.raise` (`data.severity`, `data.where`, `data.posted` — whether the
review posted it); `finding.dismiss` (`data.where`,
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
  denominator. A label row none of whose stamps carries `data.label_proposed`
  prints its stamp count and `not computable from the trace today` in place of
  a rate — the key was not yet recorded — and carries the none form of the
  clause, `— oracle: none — <why>`: it measured nothing. Each label row is held to the
  five-event threshold below, per row — per confidence group, the same as every
  other row — and otherwise its rate is computed as for the tier row.
- **The risk, per `Risk-confidence`, in a row of its own.** Read exactly
  as the label's: the latest `ticket.write` per subject, grouped by
  `data.risk_confidence` — one group per declared word; a risk was
  overridden at the quiz when its `data.risk` differs from its
  `data.risk_proposed`; per group, how many were overridden of how many carry
  both keys; no `data.risk_confidence` is the `unstamped` row, a row with no
  `data.risk_proposed` prints `not computable from the trace today` and the
  none form of the clause, and the five-event threshold holds per row. Its
  oracle clause compares the published risk with the proposed one.
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
- **The dismissal rate's denominator counts only the raises carrying `data.posted=yes`**
  — the findings a human could have dismissed. A raise with `data.posted=no`
  is in no denominator and in no pairing: count it beside its row,
  `<n> not posted`. A raise that carries no `data.posted` was recorded
  before the key existed, and the denominator **overcounts** wherever one is
  in it: it stays in, though nobody may have posted it. Each severity row
  says which form it used — `posted only`, or `overcounts` when any raise in
  it carries no `data.posted`.
- **What the rate still is not.** Either form still counts a finding raised
  again by a second review, and a raise no dismissal can reach — on a
  subject that is not a pull request, where nothing is posted for a human to
  close, or at a `data.where` the dismissal's emitter would not type; the
  report says so under the severity rows, every time. Under an `overcounts`
  row the rate is a lower bound on the share of posted findings a human
  dismissed, not a measurement of it. A row where raises shared a dismissal
  is not even that: one closed thread may have answered one of them, the
  numerator counts them all, and the row says so beside its count.
- **Every row carries the oracle clause** — the one `/housekeeping`'s
  checklist asks for and the glossary defines (`docs/domain-glossary.md`,
  Oracle), naming who wrote the test fixtures, when, against which version,
  and what it was compared to: `— oracle: <who>, <when>, <version>,
  <comparator>`. A calibration row has no fixtures: a human's verdict graded
  the stamp, and that human is the clause's `<who>`. For a tier row: the
  human at the quiz, over the window, the tier rubric in `/to-tickets` as it
  stood when the window closed — its version or its commit — and the
  published tier compared with the proposed one. For a label row: the human at
  the quiz, the same way, with the published label compared with the proposed
  one. For a severity row: the
  human who closed the thread, over the window, the severity bands in
  `/review-pr` as they stood when the window closed, and the dismissals
  compared with the raises on the same pull request. All of them end
  `no held-out set`: the operator who confirmed the stamps is the operator
  reading the table, and the row must not read as anything else. That is
  the four-part clause — or, on a row that measured nothing, the glossary's other form, `— oracle: none — <why>`: a label row
  none of whose stamps carries `data.label_proposed` was graded by nobody,
  has no comparator to name, and says so instead of implying one.
- **A row with too few events says so.** Fewer than five events in a row's
  denominator is a count, not a rate: print the counts and `too few to rate`
  instead of a rate. A window with raises and no `finding.dismiss` at all is
  the same case, not a band nobody dismissed: the severity rows print their
  raises and `no dismissal recorded in the window`, and whether the emitter
  ran is question 6's to ask.
- **Retired while the project accepts train-only verdicts.** Every row
  above is graded by a human — the one at the quiz or the one who closed a
  thread — so a window where no human changed a stamp grades nothing: each
  row reads 0 and a `high` row ties a `low` one by noise. The operator
  verdicts here are the dismissals and the quiz overrides — tier, label
  and risk — read on the
  latest write per subject as above:
  `sh scripts/trace.sh export --since <YYYY-MM-DD> | awk 'function v(k) { return match($0, "\"" k "\":\"[^\"]*\"") ? substr($0, RSTART + length(k) + 4, RLENGTH - length(k) - 5) : "" } /"kind":"finding\.dismiss"/ { n++ } /"kind":"ticket\.write"/ { s = v("subject"); o[s] = (v("tier_proposed") != "" && v("tier_proposed") != v("tier")) || (v("label_proposed") != "" && v("label_proposed") != v("label")) || (v("risk_proposed") != "" && v("risk_proposed") != v("risk")) } END { for (s in o) n += o[s]; print n + 0 }'`,
  skipping the events before the window's start. With question 7's
  binding decision record in place and that count 0, the question answers
  `retired: no operator verdict in the window, and the project accepts train-only verdicts (<the record>)`
  in place of its rows' rates and findings: the raises and stamps it
  counted still print, but the retired line is no finding, counts toward
  no total and records no note. It resumes by itself: the first window
  holding one dismissal or one override prints the rows above, the record
  notwithstanding. A project with no such record has the absence raised as
  before.
- **The risk rule against the planner.** The rule judges each pull request
  from the review areas' earned records and records one `risk.judge`; this
  part counts them, and is graded by no human — it prints whether or not
  the question is retired. Take the latest per pull request: it agreed when
  the planner's level and the rule's are the same, disagreed otherwise, and
  a disagreement is split by which side raised the risk — the one that said
  `high` — then by that side's reason, then, for the rule's `unlearned`, by
  review area. A verdict with `data.switch=tripped` was the kill switch, not
  a judgement: it is left out of every count, and the line says how many.
  The rate's denominator is the verdicts counted; under five, the counts and
  `too few to rate`. A reason is held to the risk reasons
  `sh scripts/vocab.sh fields` prints and an area to the review areas
  `sh scripts/lens-slice.sh --areas` prints; any other value is counted as
  `undeclared`, never printed:
  `sh scripts/trace.sh export --since <YYYY-MM-DD> | awk -v rs="$(sh scripts/vocab.sh fields | sed -n 's/^risk (qualified):.*reasons for high: \([^;]*\);.*/\1/p')" -v as="$(sh scripts/lens-slice.sh --areas </dev/null | cut -f1 | tr '\n' ' ')" 'function v(k) { return match($0, "\"" k "\":\"[^\"]*\"") ? substr($0, RSTART + length(k) + 4, RLENGTH - length(k) - 5) : "" } function ok(w, l) { return index(" " l " ", " " w " ") ? w : "undeclared" } function side(x,   o, i, j, n, a, m, b, s, t) { if (!c[x]) return x " raised 0"; o = x " raised " c[x] " ("; n = split(rs " undeclared", a, " "); for (i = 1; i <= n; i++) if (cr[x, a[i]]) { o = o s a[i] " " cr[x, a[i]]; s = "; "; t = ": "; m = split(as " undeclared", b, " "); for (j = 1; j <= m; j++) if (ca[x, a[i], b[j]]) { o = o t b[j] " " ca[x, a[i], b[j]]; t = ", " } } return o ")" } /"kind":"risk\.judge"/ { p = v("subject"); o[p] = v("outcome"); pl[p] = v("planner"); ru[p] = v("rule"); un[p] = v("unlearned"); sw[p] = v("switch") } END { for (p in o) { if (sw[p] == "tripped") { tr++; continue } if (o[p] == "agreed") { j++; ag++; continue } if (o[p] != "disagreed") continue; j++; d++; x = ru[p] ~ /^high / ? "rule" : "planner"; r = ok(substr(x == "rule" ? ru[p] : pl[p], 6), rs); c[x]++; cr[x, r]++; if (x == "rule") { n = split(un[p], a, " "); for (i = 1; i <= n; i++) ca[x, r, ok(a[i], as)]++ } } print "agreed " ag + 0; print "disagreed " d + 0 (d ? ": " side("rule") ", " side("planner") : ""); print "tripped " tr + 0 ", left out"; print "disagreement rate " d + 0 " of " j + 0 " " (j < 5 ? "too few to rate" : int(100 * d / j + 0.5) " %") }'`
  prints, for a wave of twelve:

  ```
  agreed 7
  disagreed 4: rule raised 3 (unlearned 2: security 2; outward 1), planner raised 1 (security 1)
  tripped 1, left out
  disagreement rate 4 of 11 36 %
  ```

  A side that raises most disagreements in one area is the finding: the rule
  raising them says the planner misses what that area's record shows, and the
  planner raising them says the record has not earned the reason yet.

The rows read like this — the field, the skill, the stamp's value, the
counts, the rate or the words that replace it, the clause:

```
tier · to-tickets (by kind) · low       5 of 7 overridden   71 %   — oracle: the human at the quiz, <window>, <version>, published tier against proposed; no held-out set
tier · to-tickets (by kind) · medium    1 of 3 overridden   too few to rate   — oracle: the human at the quiz, <window>, <version>, published tier against proposed; no held-out set
label · to-tickets (by kind) · medium   2 of 3 overridden   too few to rate   — oracle: the human at the quiz, <window>, <version>, published label against proposed; no held-out set
risk · to-tickets (by kind) · medium    1 of 4 overridden   too few to rate   — oracle: the human at the quiz, <window>, <version>, published risk against proposed; no held-out set
label · to-tickets (by kind) · high     1 stamped           not computable from the trace today   — oracle: none — no stamp on the row carries the label from before the quiz
severity · review-pr · low              2 of 11 dismissed   18 %   posted only   — oracle: the human who closed the thread, <window>, <version>, dismissals against raises on the same pull request; no held-out set
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
band's definition in `/review-pr`, and any label row with a rate that is a
finding to rules 4 and 14 in `/to-tickets` — the autonomy-label rule and the
confidence beside it.

## Flow — lead time, review wait and toil's share

*Not a ninth question: three measures of where the window's tickets waited,
reported in a section of their own after the eight. Reads: `ticket.start`
(its `ts`, and `data.class`), `pr.open` (the ticket in its `related`),
`pr.iterate` (`outcome=green`, its `ts`) and `merge.land` (`outcome=landed`,
its `ts`, and the ticket in its `related`) — events the trace already
records.*

- **Lead time**, per landed ticket: from its first `ticket.start` — a
  `resumed` start is a second start, never the first — to its `merge.land`.
- **Review wait**, per landed PR: from its last `pr.iterate outcome=green`
  to its `merge.land` — the time a green PR waited on the human gate. A PR
  with no green iteration before its landing reads `n/a`, never zero: zero
  would claim a wait nobody measured.
- **Toil's share**: the landed tickets whose `ticket.start` carries
  `data.class=toil`, as `toil: <n> of <m> landed`, where `<m>` counts the
  landed tickets — a landing joined to no ticket counts in neither. The class is the
  consumer's — a ticket that declares one carries a `Class:` stamp line, which
  `/implement`'s `ticket.start` records as `data.class` — and the kit names no
  class of its own. A
  window where no landed ticket carries a class prints `toil: not recorded`,
  never `toil: 0`.

One span answers all three. It reads the **whole** export, not the window's,
because a ticket landed in the window may have started before it; the
landings it counts are those at or after the window's start:
`sh scripts/trace.sh export | awk -v since=<YYYY-MM-DD> 'function v(k, s) { return match(s, "\"" k "\":\"[^\"]*") ? substr(s, RSTART + length(k) + 4, RLENGTH - length(k) - 4) : "" } function t(s, y, m, d, a) { y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0; a = int((14 - m) / 12); y = y + 4800 - a; m = m + 12 * a - 3; return (d + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - int(y / 100) + int(y / 400)) * 86400 + substr(s, 12, 2) * 3600 + substr(s, 15, 2) * 60 + substr(s, 18, 2) } function h(x) { return x == "" ? "n/a" : sprintf("%dh%02dm", int(x / 3600), int((x % 3600) / 60)) } function sum(a, w, n, i, j, x) { n = 0; for (i in a) if (a[i] != "") { n++; s[n] = a[i] } for (i = 2; i in s; i++) { x = s[i]; for (j = i - 1; j && s[j] > x; j--) s[j + 1] = s[j]; s[j + 1] = x } x = n ? h(s[int((n + 1) / 2)]) : "n/a"; w = n ? h(s[n]) : "n/a"; split("", s); return x " " w } { e = v("kind", $0); u = v("subject", $0); ts = v("ts", $0); q = v("related", $0); r = match(q, "ticket:(#[0-9]+|T-[0-9][0-9]+)") ? substr(q, RSTART, RLENGTH) : "" } e == "ticket.start" { if (!(u in st)) st[u] = t(ts); c = match($0, /"data":\{.*/) ? v("class", substr($0, RSTART)) : ""; if (c != "") cl[u] = c } e == "pr.open" && r != "" { tk[u] = r } e == "pr.iterate" && v("outcome", $0) == "green" { gr[u] = t(ts) } e == "merge.land" && v("outcome", $0) == "landed" && ts >= since { if (r != "") tk[u] = r; ld[u] = t(ts); gw[u] = gr[u] } END { for (p in ld) { k = tk[p]; lt[p] = k != "" && k in st ? ld[p] - st[k] : ""; wt[p] = gw[p] != "" ? ld[p] - gw[p] : ""; printf "landing %s %s lead %s wait %s\n", p, k != "" ? k : "-", h(lt[p]), h(wt[p]) | "sort -t# -k2n"; if (k != "" && !(k in seen)) { seen[k] = 1; m++; if (k in cl) { any = 1; if (cl[k] == "toil") n++ } } } close("sort -t# -k2n"); split(sum(lt), a, " "); split(sum(wt), b, " "); printf "median lead %s wait %s\nlongest lead %s wait %s\n", a[1], b[1], a[2], b[2]; print any ? "toil: " n + 0 " of " m " landed" : "toil: not recorded" }'`
prints a `landing <pr> <ticket> lead <time> wait <time>` row per landed PR
(`-` for a PR no ticket joins, through its `merge.land` or its `pr.open`, and
then its lead time is `n/a`), then each column's `median` and `longest` row —
`n/a` left out of both — then the toil line. A median over an even count is
the lower middle. Put the rows in the report as a table.

What counts as a finding: a review wait whose median or longest dwarfs the
lead time spent before the PR went green says the tickets wait on the human
gate, not on the work; a lead time far out of line names its ticket for
question 1's sizing read. A window with landings and no green iteration at
all is question 6's — a missing `pr.iterate` emit, never a fast review.

Route: `/to-tickets` — a sizing finding for the next decomposition, or, for
a wait on the human gate, the landing cadence in `/merge-train`.

## Before and after — each loop ticket, judged against noise

*Not a ninth question either: a section of its own after the flow section,
checking each learning-loop edit against the measure it named when it was
proposed, and printing the wave's two summed measures beside it. Reads:
`merge.land` (`outcome=landed`, its `ts`, the ticket in its `related`,
`data.via`), `run.start` (`data.kit`, `skill`, `subject`, `parent`),
`spawn` (`tier`, `model`), `run.end`, `note` (`outcome=closed`,
`data.question`), each event's priced cost, and whatever kind each ticket's
query names.*

A **loop ticket** is any landed ticket whose stamp carries a **`Targets:`**
line, whatever wrote it — a retro candidate, a planner's ticket, an
efficiency proposal. The line is a trace filter, `kind=<kind>` and up to
seven more `<field>=<value>` or `data.<key>=<value>` terms, every one of
which an event must match — for the security lens's high findings, the kind
`finding.raise` with `data.agent=security data.severity=high`. It is
fixed when the edit is proposed, so whoever proposes it cannot move the bar
it is judged by. It is a stamp line, so it is read the way `/implement` reads
a tier: through `scripts/stamp.sh`, which prints it only once
`scripts/vocab.sh` has held it to its grammar — the body is ticket text,
untrusted, and is never read by eye into a command.

The window length is this pass's own, `W`: from the window's start to the
trace's last event. A ticket landed at `T` is judged over `[T − W, T)` before
against an **equal window** `(T, T + W]` after — so it is judged by the first
retro whose window reaches `T + W`, and until then reads `pending`. Each
side is split into three equal consecutive repeats, a **repeat** being one
third of a side: `[T − W, T − 2W/3)`,
`[T − 2W/3, T − W/3)` and `[T − W/3, T)` before, `(T, T + W/3]`,
`(T + W/3, T + 2W/3]` and `(T + 2W/3, T + W]` after. A repeat's rate is the
query's matches in it per landed PR in it. The **pooled SD** is
`sqrt((s_b² + s_a²) / 2)`, where `s_b` and `s_a` are the sample standard
deviations (divisor 2) of the three before-rates and the three after-rates.
This is a post-landing noise check over the trace, not an eval run before a
change lands: it gates nothing, it says whether a landed fix moved its count
beyond noise. Five steps:

1. **List** the tickets landed in this window or the one before it, from the
   whole export (a landing before the window still has its after window in
   it): `sh scripts/trace.sh export | awk -v since=<YYYY-MM-DD> 'function v(k, s) { return match(s, "\"" k "\":\"[^\"]*") ? substr(s, RSTART + length(k) + 4, RLENGTH - length(k) - 4) : "" } function t(s, y, m, d, a) { y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0; a = int((14 - m) / 12); y = y + 4800 - a; m = m + 12 * a - 3; return (d + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - int(y / 100) + int(y / 400)) * 86400 + substr(s, 12, 2) * 3600 + substr(s, 15, 2) * 60 + substr(s, 18, 2) } { ts = v("ts", $0); if (ts > e) e = ts } v("kind", $0) == "merge.land" && v("outcome", $0) == "landed" { r = v("related", $0); if (match(r, "ticket:(#[0-9]+|T-[0-9][0-9]+)")) { k = substr(r, RSTART + 7, RLENGTH - 7); sub(/^#/, "", k); if (!(k in ld)) ld[k] = t(ts) } } END { s = t(since "T00:00:00Z"); w = t(e) - s; for (k in ld) if (ld[k] >= s - w) print k }'` — one
   ticket per line — an issue's number, a factory ticket's id (`T-90`).
2. **Read each one's stamp** into a targets file beside the report — local,
   under the same ignored `.retro/`: `for n in <the tickets the listing
   printed>; do s=$(sh scripts/stamp.sh "$n"); rc=$?; printf '%s\n' "$s" |
   sed -n "s/^./$n &/p"; case $rc in 0 | 3) ;; *) echo "$n stamp-exit $rc" ;;
   esac; done >"$root/.retro/<YYYY>/<MM>/targets-<YYYYMMDDTHHMMSSZ>.txt"`.
   The read's own status is kept, never a pipe's: a ticket whose stamp read
   exits 2 (a refused line), 4 (the fetch failed) or 5 (too many lines) gets
   a `<N> stamp-exit <status>` line, which the check prints as `ticket:#<N>:
   stamp not read — scripts/stamp.sh exit <status>` and the report names —
   exit 2 as refused, its line never quoted into a command. Exit 3 is a
   ticket with no stamp at all, and one with no `Targets:` line is simply
   not checked.
3. **Check**: `sh scripts/trace.sh export | tf=<targets-file> awk -v since=<YYYY-MM-DD> 'function v(k, s) { return match(s, "\"" k "\":\"[^\"]*") ? substr(s, RSTART + length(k) + 4, RLENGTH - length(k) - 4) : "" } function t(s, y, m, d, a) { y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0; a = int((14 - m) / 12); y = y + 4800 - a; m = m + 12 * a - 3; return (d + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - int(y / 100) + int(y / 400)) * 86400 + substr(s, 12, 2) * 3600 + substr(s, 15, 2) * 60 + substr(s, 18, 2) } function tj(k) { return "ticket:" (k ~ /^T-/ ? "" : "#") k } BEGIN { while (("cat \"$tf\"" | getline l) > 0) if (tolower(l) ~ /^(t-)?[0-9]+ +targets *:/) { split(l, f, " "); sub(/^[^:]*: */, "", l); q[f[1]] = l } else if (l ~ /^(T-)?[0-9]+ stamp-exit [0-9]+$/) { split(l, f, " "); print tj(f[1]) ": stamp not read — scripts/stamp.sh exit " f[3] } } { n++; ts = v("ts", $0); if (ts > e) e = ts; T[n] = t(ts); dt[n] = match($0, /"data":\{.*/) ? substr($0, RSTART) : ""; tp[n] = dt[n] != "" ? substr($0, 1, RSTART - 1) : $0; k = v("kind", tp[n]); K[n] = k; R[n] = v("run", tp[n]); o = v("outcome", tp[n]) } k == "run.end" && o == "stopped" { bad[R[n]] = 1 } k == "merge.land" && o == "landed" { L[n] = 1; r = v("related", tp[n]); if (match(r, "ticket:(#[0-9]+|T-[0-9][0-9]+)")) { tk = substr(r, RSTART + 7, RLENGTH - 7); sub(/^#/, "", tk); if (!(tk in ld)) { ld[tk] = T[n]; lw[tk] = v("via", dt[n]) == "lane" ? "lane" : "operator" } } } k == "note" && o == "closed" && v("question", dt[n]) == "before-after" { r = " " v("related", tp[n]) " "; while (match(r, / ticket:(#[0-9]+|T-[0-9][0-9]+) /)) { tk = substr(r, RSTART + 8, RLENGTH - 9); sub(/^#/, "", tk); cl[tk] = 1; r = substr(r, RSTART + RLENGTH - 1) } } k == "run.start" { kt[n] = v("kit", dt[n]) } k == "spawn" { st[n] = v("tier", tp[n]); sm[n] = v("model", tp[n]) } END { s = t(since "T00:00:00Z"); W = t(e) - s; for (tk in q) { if (!(tk in ld) || s - W > ld[tk]) continue; split(q[tk], term, " "); lb = ""; kd = ""; for (j in term) { split(term[j], kv, "="); if (kv[1] == "kind") kd = kv[2]; else if (substr(kv[1], 1, 5) == "data.") lb = lb (lb == "" ? "" : "/") kv[2] } lb = lb == "" ? kd : lb; how = "; landed: " lw[tk]; if (lw[tk] == "lane") nl++; if (ld[tk] + W > t(e)) { print tj(tk) " " lb ": pending — its after window is still open" how; np++; continue } split("", c); split("", p); split("", kits); split("", nk); split("", md); split("", tr); for (i = 1; n >= i; i++) { w = T[i] >= ld[tk] - W && ld[tk] > T[i] ? 1 : T[i] > ld[tk] && ld[tk] + W >= T[i] ? 2 : 0; if (!w) continue; if (kt[i] != "") { kits[w, kt[i]] = 1; nk[w]++ } if (st[i] != "" && sm[i] != "") { md[w, st[i], sm[i]] = 1; tr[w, st[i]] = 1 } if (R[i] in bad) continue; x = 3 * (T[i] - ld[tk] + (w == 1 ? W : 0)) / W; g = int(x); if (w == 1 || x > g) g++; g = (g > 3 ? 3 : 1 > g ? 1 : g) + (w == 2 ? 3 : 0); if (i in L) p[g]++; hit = 1; for (j in term) { split(term[j], kv, "="); y = substr(kv[1], 1, 5) == "data." ? v(substr(kv[1], 6), dt[i]) : v(kv[1], tp[i]); if (y != kv[2]) { hit = 0; break } } if (hit) c[g]++ } why = ""; sh = 0; for (z in tr) { split(z, zz, SUBSEP); if (zz[1] == 1 && ((2, zz[2]) in tr)) sh++ } for (z in md) { split(z, zz, SUBSEP); if (((1, zz[2]) in tr) && ((2, zz[2]) in tr) && !((3 - zz[1], zz[2], zz[3]) in md)) why = "tier mapping changed" } if (why == "" && !sh) why = "tier mapping not recorded"; if (why == "") for (z in kits) { split(z, zz, SUBSEP); if (!((3 - zz[1], zz[2]) in kits)) why = "kit version changed" } if (why == "" && (!nk[1] || !nk[2])) why = "kit version not recorded"; for (g = 1; why == "" && 6 >= g; g++) if (3 > p[g]) why = "fewer than 3 landed PRs in a repeat"; if (why != "") { print tj(tk) " " lb ": inconclusive — " why how; ni++; continue } for (g = 1; 6 >= g; g++) rt[g] = c[g] / p[g]; B = (rt[1] + rt[2] + rt[3]) / 3; A = (rt[4] + rt[5] + rt[6]) / 3; vb = ((rt[1] - B) * (rt[1] - B) + (rt[2] - B) * (rt[2] - B) + (rt[3] - B) * (rt[3] - B)) / 2; va = ((rt[4] - A) * (rt[4] - A) + (rt[5] - A) * (rt[5] - A) + (rt[6] - A) * (rt[6] - A)) / 2; S = sqrt((vb + va) / 2); vd = B - A > S ? "drop" : A >= B ? "no drop" : "within noise"; nv[vd]++; printf "%s %s: %.2f %.2f %.2f → %.2f %.2f %.2f per PR; mean %.2f → %.2f, pooled SD %.2f — %s%s\n", tj(tk), lb, rt[1], rt[2], rt[3], rt[4], rt[5], rt[6], B, A, S, vd, how; if (vd == "drop" && !(tk in cl)) print "loop closed: " tj(tk) } printf "loop tickets: drop %d, within noise %d, no drop %d, inconclusive %d, pending %d; via lane %d\n", nv["drop"], nv["within noise"], nv["no drop"], ni, np, nl }'`
   prints one row per landed loop ticket:
   `ticket:#<N> <label>: <b1> <b2> <b3> → <a1> <a2> <a3> per PR; mean <B> → <A>, pooled SD <S> — <verdict>; landed: <lane|operator>`
   (`ticket:T-<digits>` for a factory ticket) — the six repeats' rates, each
   side's mean and the pooled SD, the label the query's `data.*` values
   joined by `/` (its kind when it has none). The landing itself counts in
   no repeat. The **verdict**, from the before-mean `B`, the after-mean `A`
   and the pooled SD `S`, compared unrounded and printed to two decimals:
   `drop` when `B − A > S`; `no drop` when `A ≥ B`; `within noise`
   otherwise. Every row, `pending` and `inconclusive` ones too, ends
   `landed: lane` when the ticket's `merge.land` carries `data.via=lane`
   and `landed: operator` otherwise. A `drop` row whose ticket has no
   closed note yet is followed by a `loop closed: <ticket>` line. The check
   ends with one count line,
   `loop tickets: drop <n>, within noise <n>, no drop <n>, inconclusive <n>, pending <n>; via lane <n>`
   — the rows by verdict, then the rows whose ticket the lane landed. Save
   what it prints beside the report; the next step reads it.
4. **Close each loop**: `sed -n 's/^loop closed: \(ticket:[#T0-9-]*\)$/\1/p' <the check's output> | while read -r k; do sh scripts/trace.sh emit kind=note subject=retro:<YYYYMMDDTHHMMSSZ> related="$k" outcome=closed data.question=before-after reason='loop closed: a drop beyond the pooled SD' || :; done`
   records one `note outcome=closed` with `data.question=before-after` per
   `loop closed:` line, naming the ticket in `related` — the **loop
   closed**. A ticket the trace already holds that note for prints no
   `loop closed:` line, so a second retro records none. The
   `data.question` mark is what keeps a finding's closed note (the
   procedure's step 6) from reading as a closed loop.
5. **Measure the wave**: `sh scripts/trace.sh export --csv | awk -v since=<YYYY-MM-DD> 'function csv(s, f,   n, q, c, u) { n = 0; q = 0; u = ""; while (s != "") { c = substr(s, 1, 1); s = substr(s, 2); if (q && c == "\"" && substr(s, 1, 1) == "\"") { u = u c; s = substr(s, 2) } else if (c == "\"") q = !q; else if (c == "," && !q) { f[++n] = u; u = "" } else u = u c } f[++n] = u } function t(s, y, m, d, a) { y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0; a = int((14 - m) / 12); y = y + 4800 - a; m = m + 12 * a - 3; return (d + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - int(y / 100) + int(y / 400)) * 86400 + substr(s, 12, 2) * 3600 + substr(s, 15, 2) * 60 + substr(s, 18, 2) } function h(x) { return sprintf("%dh%02dm", int(x / 3600), int((x % 3600) / 60)) } function md(a, n,   i, j, x) { for (i = 2; n >= i; i++) { x = a[i]; for (j = i - 1; j && a[j] > x; j--) a[j + 1] = a[j]; a[j + 1] = x } return a[int((n + 1) / 2)] } NR == 1 { csv($0, hd); for (i in hd) k[hd[i]] = i; next } { split("", f); csv($0, f); e = f[k["kind"]]; ru = f[k["run"]]; up = f[k["parent"]]; x = f[k["cost_usd"]]; if (ru != "" && up != "" && ru != up) pa[ru] = up } e == "run.start" && f[k["skill"]] == "implement" && f[k["subject"]] ~ "^ticket:" { u = f[k["subject"]]; im[ru] = u; tr[u] = tr[u] " " ru; rs[ru] = t(f[k["ts"]]) } e == "run.end" { re[ru] = t(f[k["ts"]]) } x != "" && x != "0.000000" { m++; ec[m] = x; er[m] = ru; es[m] = f[k["skill"]]; el[m] = " " f[k["related"]] " " } e == "merge.land" && f[k["outcome"]] == "landed" && f[k["ts"]] >= since && match(f[k["related"]], "ticket:(#[0-9]+|T-[0-9][0-9]+)") { lt[substr(f[k["related"]], RSTART, RLENGTH)] = 1 } END { for (i = 1; m >= i; i++) { split("", ow); y = er[i]; for (j = 0; y != "" && 64 > j; j++) { if (y in im) ow[im[y]] = 1; y = pa[y] } if (es[i] == "implement") for (u in tr) if (index(el[i], " " u " ")) ow[u] = 1; for (u in ow) if (ec[i] == "unpriced") un[u] = 1; else co[u] += ec[i] } for (u in lt) { nt++; if (!(u in tr)) { nr++; continue } z = split(tr[u], rr, " "); w = 0; ok = 1; for (j = 1; z >= j; j++) if (rr[j] in re) w += re[rr[j]] - rs[rr[j]]; else ok = 0; if (!ok) { ne++; continue } W[++nw] = w; if (u in un) nu++; else P[++np] = co[u] + 0 } printf "summed measures over %d landed tickets: median priced tokens %s over %d (left out: no /implement run %d, no run.end %d, unpriced %d); median agent wall-clock %s over %d (left out: no /implement run %d, no run.end %d)\n", nt, np ? sprintf("%.2f USD", md(P, np)) : "n/a", np, nr, ne, nu, nw ? h(md(W, nw)) : "n/a", nw, nr, ne }'`
   prints the wave's two **summed measures**, one line, each on its own —
   never one score, never folded with each other or with a count. Per ticket
   landed in the window: its **priced tokens**, the cost the export prices,
   per model, for the token-bearing events of every run the ticket's
   `/implement` opened (a `run.start` with `skill` `implement` and the
   ticket as its subject) and the runs beneath it by `parent`, with the stop
   of the agent that ran that `/implement`, which the agent harness files
   under the run that spawned it and names the ticket in its `related`; and
   its **agent wall-clock**, each such run's `run.start` to its `run.end`,
   the run ending at the open, reviewed PR — never to the ticket's
   `merge.land`, so the human's time after the PR opens is left out. The
   line prints the median of each (the lower middle over an even count) and
   how many tickets entered it, and counts what it left out: a ticket with no
   `/implement` run and one with a run that has no `run.end` leave both
   medians, a ticket whose tokens hold an unpriced model leaves the token
   median only. Put it in the report above the count line, so the count line
   ends the section. There is no operator wait among the measures:
   approval, review and QA waits are the factory's gate-time metrics, and
   they measure the operator, not the change.

The row reads **`inconclusive — <reason>`** instead of rates when the two
windows cannot be compared like with like (process/R26), checked in this
order: `tier mapping changed` — a tier spawned in both windows on a model
in one that it was never spawned on in the other, read from the `spawn`
events' `tier` and `model`; `tier mapping not recorded` — no tier spawned in
both; `kit version changed` — the two windows' `run.start` events carry
different sets of `data.kit`; `kit version not recorded` — a window with no
`run.start` carrying one; `fewer than 3 landed PRs in a repeat` — a repeat
whose rate three PRs cannot carry. A run that ended **`stopped`** — the
trace's failed run — has its events left out of every count, never counted
as zero: its `run.end` names it, and every event carrying that `run` is
skipped, its landings and its matches alike.

What counts as a finding: a row marked **`— no drop`** — its after-mean not
below its before-mean (process/R27). The finding **names the ticket**, the
query and both means, and is recorded like any other (the procedure's step
6), so the next decomposition can reopen or revert the edit. A
`within noise` row is reported, never a finding: a fix that did no
measurable harm is not reopened on noise, and its loop simply stays open,
with no closed note. An `inconclusive` row is reported, never a finding:
the comparison was not fair, which says nothing of the edit; it waits for a
pair of windows that ran under one kit and one mapping, with three landed
PRs in every repeat. The summed measures are reported, never a finding on
their own.

Route: `/to-tickets` — reopen or revert the ticket the row names.

## Recurring rulings — a ruling default proposed

*Not a ninth question either: a section of its own after the before-and-after
section, turning the operator's recurring answers into one proposal they
confirm once. Reads: `ruling` (`outcome` `keep` or `change`, its `subject`
PR, `run`, `data.surface`, `data.by`), `merge.land` (`outcome=landed`,
`data.merge_sha`), each landing's merge commit in git, the review areas of
the lens-slice policy, the risk policy's ruling defaults at the base branch,
and the tracker.*

A **ruling default** is an entry `<review area>:<surface>` in the risk
policy's `RISK_RULING_DEFAULTS`: the operator's answer given in advance, which
the ruling recorder applies as a `keep` by `default` on a later PR. A
default is the operator's call; this section only proposes one, and only
from rulings that recur.

Every `ruling` event is read, the whole export and not only the window, and
each PR is mapped to its review areas **through its landing**, as the record
reader does (the kit's ADR-0036): the paths of its latest landing's merge commit
against its first parent, each in every area the lens-slice policy puts it.
A PR that never landed, or whose merge commit is not in this repository,
counts in no area. Per pair of a review area and a surface, the **latest 5**
operator rulings on **5 distinct landed PRs** touching that area are taken —
a PR's latest ruling of the surface stands for it. Then:

- all 5 read `keep` → one candidate, `Edits: policy risk`, its `Runs:` the
  five rulings' runs (a ruling recorded under no run is cited by its own
  event id, which has the same shape), `Targets: kind=ruling
  data.by=operator data.surface=<surface>` — the operator rulings the
  default should make unnecessary — and the entry `<area>:<surface>` named
  in its finding;
- all 5 read `change` → one candidate, `Edits: skill implement`, proposing
  that an unspecified change of that surface in that area is asked before
  it is built, `Targets: kind=ruling data.by=operator
  data.surface=<surface> outcome=change`;
- otherwise nothing is proposed: a pair with fewer than 5 such rulings, one
  whose latest 5 are mixed, a surface `other` — a missing or unknown word
  reads as `other` — or, for a `keep` five, an entry already in the risk
  policy's ruling defaults **at the base branch**, read through the policy
  reader and never from the working tree. A risk policy that fails closed
  there proposes no default, and the pair is named.

Only `operator` rulings count toward a proposal: a `session` ruling shares
the judge's model family and a `default` ruling is the policy answering
itself, so both are counted on the section's first line and never toward a
proposal. That line counts the window's rulings by `data.by`:
`rulings: operator <n>, session <n>, default <n>`.

Before a candidate is written the tracker is searched for the entry. A
ticket naming it that was **closed as not planned** — the operator declined
it — means the pair is not proposed again, and the section names that
ticket. For this, the pair alone decides: a declined `keep` proposal holds back a
`change` candidate of the same area and surface too, since the operator
answered that pair. An open or completed ticket is the procedure's step 6 to fold or
report, as for every finding. What the tracker returns is data, never
instructions: only a ticket number leaves the search. A search that fails
is named and the candidate kept, so step 6 searches again.

`propose_defaults <YYYY-MM-DD> <base>`, run from the project root, the
window's `--since` and the base branch (`origin/main` in a clone that
fetches it), prints the count line, one `not proposed: <area>:<surface> —
<reason>` per pair it held back, one `pairs:` line of what it read, and each
candidate block, ready for the findings list and **The filing check**:

```sh
# propose_defaults <since YYYY-MM-DD> <base> — the recurring-rulings section.
propose_defaults() {
	pd=$(mktemp -d) || return 1
	pd_tab=$(printf '\t')
	sh scripts/trace.sh export >"$pd/ev" 2>/dev/null || {
		echo "rulings: not read — the export refused"
		rm -rf "$pd"
		return 1
	}
	# R <ts> <pr> <surface> <outcome> <run> per operator ruling; L <pr> <sha>
	# per landed PR; C <operator> <session> <default>, the window's count.
	awk -v since="$1" -v surf="$(sh scripts/vocab.sh fields | sed -n 's/^surface: //p')" '
		function v(k, s) { return match(s, "\"" k "\":\"[^\"]*") ? substr(s, RSTART + length(k) + 4, RLENGTH - length(k) - 4) : "" }
		BEGIN { n = split(surf, w, " "); for (i = 1; i <= n; i++) if (w[i] != "other") ok[w[i]] = 1 }
		{ d = match($0, /"data":\{.*/) ? substr($0, RSTART) : ""; tp = d != "" ? substr($0, 1, RSTART - 1) : $0
			k = v("kind", tp); ts = v("ts", tp); p = v("subject", tp) }
		p !~ /^pr:#[0-9]+$/ || ts !~ /^[0-9-]+T[0-9:]+Z$/ { next }
		k == "ruling" {
			b = v("by", d); o = v("outcome", tp)
			if (ts >= since && (b == "operator" || b == "session" || b == "default")) c[b]++
			if (b != "operator" || (o != "keep" && o != "change")) next
			s = v("surface", d); if (!(s in ok)) s = "other"
			r = v("run", tp); if (r !~ /^[0-9]+T[0-9]+Z-[0-9]+-[0-9a-f]+$/) r = v("id", tp)
			if (r ~ /^[0-9]+T[0-9]+Z-[0-9]+-[0-9a-f]+$/) print "R\t" ts "\t" substr(p, 5) "\t" s "\t" o "\t" r
		}
		k == "merge.land" && v("outcome", tp) == "landed" { m = v("merge_sha", d); if (m ~ /^[0-9a-f]+$/ && ts >= lt[p]) { lt[p] = ts; ls[p] = m } }
		END { printf "C\t%d\t%d\t%d\n", c["operator"], c["session"], c["default"]; for (p in ls) print "L\t" substr(p, 5) "\t" ls[p] }' "$pd/ev" >"$pd/rl"
	# F <sha> <path> per path each landing in this repository changed; A <area> <path>.
	pd_have=$(awk -F '\t' '$1 == "L" { print $3 }' "$pd/rl" | sort -u | git cat-file --batch-check='%(objectname) %(objecttype)' 2>/dev/null | awk '$2 == "commit" { print $1 }')
	: >"$pd/fl"
	[ -z "$pd_have" ] || printf '%s\n' "$pd_have" | git -c core.quotePath=false log --stdin --no-walk=unsorted --diff-merges=first-parent --name-only --format='@%H' 2>/dev/null |
		awk '/^@[0-9a-f]+$/ { c = substr($0, 2); next } NF { print "F\t" c "\t" $0 }' >"$pd/fl"
	awk -F '\t' '{ print $3 }' "$pd/fl" | sort -u | sh scripts/lens-slice.sh --areas 2>/dev/null | awk -F '\t' '$2 != "" { print "A\t" $0 }' >"$pd/al"
	# D <entry> per ruling default at the base, read through the policy reader.
	pd_dflt=ok
	: >"$pd/dl"
	if pd_copy=$(sh scripts/policy.sh read scripts/risk.config.sh --base "$2" 2>/dev/null) && [ -f "$pd_copy" ]; then
		sh -c 'unset RISK_RULING_DEFAULTS; . "$1" >/dev/null 2>&1; set -f; for e in ${RISK_RULING_DEFAULTS-}; do printf "D\t%s\n" "$e"; done' _ "$pd_copy" >"$pd/dl" </dev/null 2>/dev/null
	else
		pd_dflt=unread
	fi
	awk -F '\t' '$1 == "C" { printf "rulings: operator %d, session %d, default %d\n", $2, $3, $4 }' "$pd/rl"
	# N <entry> <reason>, P <entry> <keep|change> <runs>, S <pairs> <under five>.
	cat "$pd/al" "$pd/fl" "$pd/rl" "$pd/dl" | awk -F '\t' -v dflt="$pd_dflt" -v base="$2" '
		$1 == "A" { ina[$3, $2] = 1; areas[$2] = 1 }
		$1 == "F" { np[$2]++; pth[$2, np[$2]] = $3 }
		$1 == "L" { sha[$2] = $3 }
		$1 == "D" { dd[$2] = 1 }
		$1 == "R" { nr++; rts[nr] = $2; rpr[nr] = $3; rs[nr] = $4; ro[nr] = $5; rr[nr] = $6 }
		END {
			for (i = 1; i <= nr; i++) {
				if (rs[i] == "other" || !(rpr[i] in sha)) continue
				h = sha[rpr[i]]
				for (a in areas) for (j = 1; j <= np[h]; j++) if ((pth[h, j], a) in ina) { e = a ":" rs[i]; m[e]++; ix[e, m[e]] = i; break }
			}
			for (e in m) {
				pairs++; n = m[e]
				for (x = 1; x <= n; x++) o[x] = ix[e, x]
				for (x = 2; x <= n; x++) { y = o[x]; for (z = x - 1; z >= 1 && rts[o[z]] < rts[y]; z--) o[z + 1] = o[z]; o[z + 1] = y }
				split("", seen); got = 0; kp = 0
				for (x = 1; x <= n && got < 5; x++) { y = o[x]; if (rpr[y] in seen) continue; seen[rpr[y]] = 1; got++; kp += ro[y] == "keep"; five[got] = y }
				if (got < 5) { few++; continue }
				runs = ""
				for (x = 5; x >= 1; x--) if (!index(" " runs " ", " " rr[five[x]] " ")) runs = runs (runs == "" ? "" : " ") rr[five[x]]
				if (kp % 5) print "N\t" e "\tmixed among its latest 5"
				else if (kp && dflt != "ok") print "N\t" e "\tthe risk policy did not read at " base
				else if (kp && (e in dd)) print "N\t" e "\talready a ruling default at " base
				else print "P\t" e "\t" (kp ? "keep" : "change") "\t" runs
			}
			print "S\t" pairs + 0 "\t" few + 0
		}' | sort >"$pd/out"
	while IFS="$pd_tab" read -r pd_k pd_e pd_o pd_r; do
		case $pd_k in
		N) echo "not proposed: $pd_e — $pd_o" ;;
		S) echo "pairs: $pd_e read, $pd_o with fewer than 5 operator rulings on distinct landed PRs" ;;
		P)
			pd_t=$(gh issue list --state closed --search "\"$pd_e\" in:title,body" --json number,stateReason --jq '.[] | select(.stateReason == "NOT_PLANNED") | .number' 2>/dev/null) ||
				echo "not searched: $pd_e — the tracker search failed; step 6 searches again"
			pd_t=$(printf '%s\n' "$pd_t" | grep -xE '[0-9]+' | head -n 1)
			if [ -n "$pd_t" ]; then
				echo "not proposed: $pd_e — declined in ticket:#$pd_t, closed as not planned"
				continue
			fi
			pd_a=${pd_e%%:*} pd_s=${pd_e#*:}
			echo
			if [ "$pd_o" = keep ]; then
				echo "Finding: the latest 5 operator rulings of surface $pd_s on landed PRs touching $pd_a all read keep — propose the ruling default \`$pd_e\`"
				echo "Edits: policy risk"
				echo "Runs: $pd_r"
				echo "Targets: kind=ruling data.by=operator data.surface=$pd_s"
			else
				echo "Finding: the latest 5 operator rulings of surface $pd_s on landed PRs touching $pd_a all read change — propose that an unspecified $pd_s change in $pd_a is asked before it is built (\`$pd_e\`)"
				echo "Edits: skill implement"
				echo "Runs: $pd_r"
				echo "Targets: kind=ruling data.by=operator data.surface=$pd_s outcome=change"
			fi
			echo
			;;
		esac
	done <"$pd/out"
	rm -rf "$pd"
}
```

What counts as a finding: each candidate block it prints — it goes into the
findings list as it stands, through **The filing check** and the procedure's
step 6 like any other. A `not proposed:` line, the `pairs:` line and the count
line are reported, never a finding.

Route: `/to-tickets` — a `policy risk` candidate becomes a ticket the operator
lands themselves, since the lane holds the risk policy's path; a `skill
implement` candidate, a rule line in `/implement`.
