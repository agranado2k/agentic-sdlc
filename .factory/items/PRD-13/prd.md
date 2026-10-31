---
id: PRD-13
type: prd
title: A cross-provider verifier reviews each PR beside the kit's own review
parent: D-02
stage: approved
created: 2026-10-28
updated: 2026-10-29
stages:
  - {stage: draft, at: 2026-10-28T12:26Z}
  - {stage: review, at: 2026-10-28T12:50Z}
  - {stage: approved, at: 2026-10-29T12:08Z}
approved_by: "agranado"
approved_at: 2026-10-29T12:08Z
---

# PRD-13 · A cross-provider verifier reviews each PR beside the kit's own review

## 1. Objective

Have a **verifier**, a reviewer whose model comes from a different provider than the model
that wrote the diff, review each pull request head beside the kit's own `/review-pr`. It also
judges whether each passing row of the PR's check table is backed by a test that really checks
the requirement, and whether each finding the kit's review raised is real, with its evidence. Its
verdicts are recorded in the trace and counted against post-merge outcomes,
so the operator can see what a second model family catches that the kit's review misses. In
this PRD it only reports: it never blocks, never counts as the review a landing requires, and
never decides anything.

**Problem.** Every reviewer the kit runs on its own PRs is from one provider. ADR-0027 makes
sure a diff is never reviewed by its author's model family, but all of those families come from
the same vendor. D-02's reading found that a judge carries the flaws of what it judges (D-02
research S-26), and that cross-model review is the practice that answers this (S-10, school C).
The kit has two half-built routes and neither one closes the gap:
- **The CI route.** The two-vendor review workflow ships inert as an example for consumers. The
  kit itself does not run it, it records nothing in the trace, and its prompt writes no scope
  words yet (ADR-0038, Neutral).
- **The dispatched route.** The skill dispatcher and the broker (ADR-0009) can run an offline
  reviewer on another agent harness, but no rule picks a model from another provider, and the
  kit policy's cross-vendor reviewer ids are commented out until that CLI logs in.

PRD-07 also left one claim with nobody to check it: a check-table row says `pass` and pins a
test, but nothing asks whether that test checks the requirement it is pinned to (PRD-07 §6,
"later, K8").

**Solution, from the user's side.**
- After `/implement` asks for the kit's review, it asks for the verifier on the same head. The
  kit's resolver picks a verifier model whose declared provider differs from the author's. When
  no such model is reachable, the PR records that no verifier ran.
- The verifier works offline and is given files only. It writes the review worker's report,
  plus one line per passing check-table row, `upheld` or `disputed`, and one line per finding
  the kit's review raised at that head, `confirmed` or `disputed`, with its evidence.
- The broker posts the report as a separately marked review and comment, and records a
  `verify.verdict`. `/pr-iterate` triages the verifier's findings like any bot's, and lists its
  disputed rows and its behavior items for the operator.
- The landing script still requires the kit's own Axis-1 verdict (ADR-0032). It records the
  verifier's outcome on `merge.land` and never acts on it.
- `/retro`'s earned record gains a verifier row per review area: its precision, the mistakes it
  caught, and the landings where it said `blocked` while the kit's review said `pass`.

The test of done:
- On a fixture PR written by a Sonnet author, the resolver picks the other provider's
  candidate. The broker posts a review under the verifier's marker and records `verify.verdict
  outcome=blocked data.disputed=1` for a report that disputes one row. The landing script
  refuses that PR when it has no kit Axis-1 verdict, and lands it with `data.verified=blocked`
  once it has one.
- With no candidate from another provider declared, the same run records `verify.verdict
  outcome=unavailable` and posts nothing.
- On a fixture PR whose kit review raised `H-1` and `M-2`, a report confirming `H-1` and
  disputing `M-2`, each with a span found at its cited line, records one `finding.verify` per
  finding. The same report with a span not found at its cited line exits 65 and records nothing.
- On a fixture trace where a reverted PR's file was named only by a `V-H-1` finding, the record
  reader counts the mistake as missed by the kit's review and caught by the verifier.

## 2. Users and scenarios

**U1 — the operator**, who reads the PR before merging and reads `/retro`'s record. **U2 — the
kit's chain skills**: `/implement`, `/pr-iterate`, `/retro`. **U3 — the kit's machinery**: the
tier resolver, the skill dispatcher, the broker, the trace and the landing script. **U4 — a
consumer** who enables the shipped CI review workflow.

Stories:

1. As the operator, I want each PR reviewed by a model from another provider as well, so that
   a blind spot shared by every model of one vendor has a chance of being seen.
2. As the operator, I want each `pass` row of the check table judged by that model, so that a
   row pinned to a test that does not check its requirement is shown to me.
3. As the operator, I want the verifier's record kept apart from the kit review's, so that I
   can see what it adds before anyone lets it decide anything.
4. As the landing script, I want the verifier's verdict never to count as the review, so that
   no PR lands on an advisory reviewer's word alone.
5. As a consumer, I want the CI review prompt to write the same scope words and pin judgements
   as the kit's verifier, so that the two routes produce the same shape.

**UC1 — Verify a PR head.** Actor: the session that ran `/implement` on ticket #970 and opened
PR #971. The author is `sonnet`. Goal: a verifier's report on the PR and its verdict recorded.
1. After requesting the kit's review, the session asks the kit's resolver for the reviewer tier
   in the `cross-provider` domain, naming `sonnet` as the author. The policy declares the
   session's own agent harness under one provider, and the `codex` harness under another. The
   resolver prints the first candidate from the other provider.
2. The skill dispatcher stages, as files, the verifier contract, the diff of the head commit
   against its base and the ticket body. For each `pass` row of the PR's check table, it also
   stages the requirement's line from the living spec and the pinned test file at the pinned
   commit. It stages the findings the kit's review raised at that head, `H-1` and `M-2`, as
   data. The worker runs with no network and no forge credential.
3. The worker prints its report, with one finding verdict line each for `H-1` (`confirmed`) and
   `M-2` (`disputed`), each citing a place at the head and quoting a span from it. The broker
   validates it, then posts one review (event COMMENT, findings inline) and one comment, both
   under the verifier's markers. The comment shows each finding verdict with its evidence.
4. The broker records `verify.verdict outcome=pass`, with `data.reviewed`, `data.provider` and
   `data.disputed=0`, on `pr:#971`, and raises each finding as `finding.raise` with a `V-` id
   and `data.agent=verifier`. It records one `finding.verify` per finding verdict line:
   `outcome=confirmed data.id=H-1` and `outcome=disputed data.id=M-2`.

Extensions:
- 0a. The kit's review has recorded no Axis-1 verdict at the head yet. The dispatcher records
  `verify.verdict outcome=unavailable` with that reason, and nothing is posted.
- 1a. The policy declares no candidate from a provider other than the author's, or declares no
  provider for the author. The resolver prints nothing and warns. The dispatcher records
  `verify.verdict outcome=unavailable` with the reason, and nothing is posted.
- 2a. The spawn fails on its first call. The session re-resolves once with that model named
  unreachable. When nothing remains, the dispatcher records `outcome=unavailable` as in 1a.
- 3a. The report disputes `process/R46`. The broker records `outcome=blocked
  data.disputed=1`. A CRITICAL or HIGH finding gives `blocked` the same way.
- 3b. The report has no pin line for one `pass` row, or uses a word other than `upheld` or
  `disputed`. The broker exits 65, posts nothing and records nothing.
- 3c. The report has no verdict line for `M-2`, names a finding that was not staged, uses a word
  other than `confirmed` or `disputed`, or quotes a span that is not on its cited line at the
  head. The broker exits 65, posts nothing and records nothing.
- 3d. The kit's review raised no finding at the head. An empty findings file is staged and the
  report carries no finding verdict line.

**UC2 — Iterate with the verifier's findings.** Actor: `/pr-iterate` on PR #971, after UC1 3a,
with one verifier finding `V-H-1`. Goal: verifier findings triaged and disputed rows shown,
with the verifier deciding nothing.
1. `/pr-iterate` triages `V-H-1` as it triages a bot's finding. It accepts and fixes it, and
   records `finding.triage` with `data.id=V-H-1`.
2. It lists `process/R46` at the top of its report, beside any skipped rows, as a check
   awaiting the operator. It leaves the row's result as it was.
3. It pushes the fix and requests the kit's review and the verifier at the new head, once each.
4. The verifier's report holds one ⚠️ UNSPECIFIED item marked `scope: inside`. `/pr-iterate`
   neither decides it nor logs it. It lists the item verbatim at the top of its report.
5. The kit's review passes at the new head and the verifier still says `blocked`.
   `/pr-iterate` reports the PR converged, with the disputed row and the verifier's item listed.

Extensions:
- 1a. The verifier disputed the kit's finding `M-2`. `/pr-iterate` lists `M-2` with the
  verifier's evidence at the top of its report, beside the disputed rows. It does not reject
  `M-2` on the verifier's word: it triages `M-2` as it would with no verifier on the PR.

**UC3 — Land a PR the verifier blocked.** Actor: the operator, running the landing script on
PR #971. Goal: a landing that the verifier's verdict neither allows nor stops.
1. The head carries the kit's Axis-1 `review.verdict outcome=pass` and a `verify.verdict
   outcome=blocked`. The script lands the PR and records `merge.land` with
   `data.verified=blocked`.

Extensions:
- 1a. The head carries a `verify.verdict outcome=pass` and no kit Axis-1 verdict. The script
  refuses with exit 2, as it refuses a head with no review (ADR-0032).
- 1b. The PR has no `verify.verdict` at or after its head commit. The script lands it with
  `data.verified=none`.

**UC4 — Read what the verifier adds.** Actor: `/retro`, running the record reader. Goal: the
verifier's record per review area, apart from the lenses'.
1. PR #971 was later reverted, and the revert removed lines in a file that only `V-H-1` named.
   The reader counts the mistake as missed by the kit's review and caught by the verifier.
2. In the area's verifier row, the reader prints held up, not held up and unlabelled findings,
   the precision, the catches, and one landing that was `blocked` by the verifier and `pass` by
   the kit's Axis-1.
3. The same row prints the kit findings the verifier confirmed and the ones it disputed, each
   split into held up, not held up and unlabelled. The lenses' own counts are what they would
   be with no `finding.verify` in the trace.

Extensions:
- 2a. No PR in the area's window carries a verifier finding. The verifier's ratios print `n/a`
  (runtime/R50).

**UC5 — A consumer's CI review writes the same shape.** Actor: the shipped CI review workflow,
renamed and given one provider secret by a consumer. Goal: its review carries the scope words
and the pin judgements.
1. Its ⚠️ UNSPECIFIED items carry `scope: inside` or `scope: outward` as the first words after
   the tag.
2. For each `pass` row of the PR's check table, it writes one line naming the id and `upheld`
   or `disputed`.

## 3. Model

- **Verifier**: a reviewer-tier spawn in the `cross-provider` domain. Its model's provider
  differs from the provider of the model that wrote the diff. It reviews one PR head on both
  axes, with the review worker's contract, and judges each `pass` check-table row. It is
  advisory: its verdict is never the review a landing requires, and it decides nothing.
- **Provider**: the vendor behind a model, as the glossary's agent-harness entry already uses
  the word. The kit policy declares one provider per agent harness, and one for the session's
  own. A model's provider is its harness's provider. Comparing families (ADR-0027) is a
  different and finer test, and this PRD does not change it.
- **Pin judgement**: `upheld` when the pinned test, read at its pinned commit, exercises the
  behavior the requirement line states. Otherwise `disputed`. It is given only on `pass` rows.
- **`verify.verdict`**: a new trace kind. Its outcomes are `pass`, `blocked` and `unavailable`.
  It is a separate kind so that no reader of `review.verdict` (the landing script, `/retro`, the
  record reader) counts it as the kit's review by accident.
- **Finding verdict**: the verifier's judgement of one finding the kit's review raised at the
  head: `confirmed` when the finding is real, `disputed` when it is not. It always carries its
  evidence: a `<path>:<line>` at the head commit and a span quoted from that line. It is recorded
  as the trace kind `finding.verify`, which no reader of `finding.triage` counts as a triage, so
  it never labels the finding: post-merge outcomes and triage still do. This is how the verifier
  meets D-08's C5 (§8): its object is the reviewer's findings.
- **Verifier finding**: a `finding.raise` whose id is `V-` before a lens-style id (`V-H-1`), with
  `data.agent=verifier`. The prefix keeps its id apart from the kit's lens finding ids on the
  same PR, so triage events are matched to the right finding.

## 4. Rules

Areas: runtime and process.

### Runtime

Deltas against `docs/specs/runtime.md`, which ends at R51.

#### ADDED

runtime/R200. The trace SHALL accept the kind `verify.verdict` with the outcomes `pass`, `blocked` and `unavailable`, and SHALL refuse any other outcome on it, exit 2, writing nothing. [UC1 4, 1a]
runtime/R201. The trace SHALL refuse, exit 2, a `verify.verdict` of outcome `pass` or `blocked` that carries no `data.reviewed` of 40 hex digits or no `data.provider` token. [UC1 4]
runtime/R202. The trace SHALL accept a `finding.raise` or `finding.triage` id of the form `V-` followed by a lens finding id, and SHALL refuse every other id it refuses today. [UC1 4, UC2 1]
runtime/R203. WHEN the kit's tier resolver is asked for the reviewer tier in the `cross-provider` domain with the diff's author named, it SHALL print the first of the policy's verifier candidates, in policy order, whose declared provider differs from the author's and which the caller has not named unreachable. [UC1 1]
runtime/R204. The resolver SHALL take an unprefixed model's provider from the provider the policy declares for the session's own agent harness, and a `<harness>:<model>` value's provider from the one declared for that harness. [UC1 1]
runtime/R205. IF the author's provider is not declared, or no candidate with a declared provider other than the author's remains, THEN the resolver SHALL print nothing on standard output, warn naming the reason, and exit 0. [UC1 1a]
runtime/R206. WHEN the skill dispatcher runs the verifier on a pull request's head, it SHALL stage the verifier contract, the head commit's diff against its base, and the ticket body as files, and SHALL give the worker no network and no forge credential. [UC1 2]
runtime/R207. WHEN the dispatcher runs the verifier on a PR whose body carries a check table, it SHALL also stage, for each `pass` row, the line of the head's living spec that carries the row's id, and the pinned test file as it stood at the pinned commit. [UC1 2]
runtime/R208. IF the resolver prints no verifier, or the verifier's spawn still fails after one re-resolve with the failed model named unreachable, THEN the dispatcher SHALL record one `verify.verdict outcome=unavailable` on the PR with the reason, and nothing SHALL be posted. [UC1 1a, 2a]
runtime/R209. The broker SHALL validate a verifier's report against the review worker's contract, and SHALL post it as one review (event COMMENT, findings inline) and one comment, each under a marker distinct from the kit review's markers. [UC1 3]
runtime/R210. The broker's check for an earlier post SHALL read a verifier's markers and the kit review's markers apart, so a post of one never stops a post of the other. [UC1 3]
runtime/R211. WHEN the broker posts a verifier's report, it SHALL record one `verify.verdict` on `pr:#<N>` carrying `data.reviewed`, `data.provider` and `data.disputed`, with outcome `blocked` when the report holds a CRITICAL or HIGH finding or a disputed row and `pass` otherwise, and SHALL raise each finding as `finding.raise` with its `V-` id and `data.agent=verifier`. [UC1 4, 3a]
runtime/R212. IF a verifier's report lacks one pin line for each `pass` row the check-table reader returns, or a pin line carries a word other than `upheld` or `disputed`, THEN the broker SHALL exit 65, posting nothing and recording nothing. [UC1 3b]
runtime/R213. The landing script SHALL count no `verify.verdict` as the review at the head that its review check requires. [UC3 1a]
runtime/R214. WHEN the landing script records `merge.land`, it SHALL carry `data.verified`: the outcome of the latest `verify.verdict` on the PR stamped at or after the head commit's committed date, or `none` when there is none. [UC3 1, 1b]
runtime/R215. No `verify.verdict` outcome SHALL change whether the landing script refuses, waits or merges. [UC3 1]
runtime/R216. The record reader SHALL print, per review area, the verifier's findings held up, not held up and unlabelled, its precision, the mistakes it caught, and the count of landings whose `merge.land` carries `data.verified=blocked` while an Axis-1 `review.verdict` at the same head has outcome `pass`. [UC4 1, 2, 2a]
runtime/R217. WHEN the dispatcher runs the verifier on a pull request's head, it SHALL also stage, as one data file, each finding the kit's own review raised on that PR at that head (any `data.agent` but `verifier`), with its id, severity, place and text, and SHALL stage an empty file when that review raised none. [UC1 2, 3d]
runtime/R218. IF the kit's own Axis-1 `review.verdict` is not yet recorded at the head when the verifier is requested, THEN the dispatcher SHALL record one `verify.verdict outcome=unavailable` on the PR naming that reason, and nothing SHALL be posted. [UC1 0a]
runtime/R219. The verifier contract SHALL ask for one finding verdict line per staged finding, carrying the finding's id, `confirmed` or `disputed`, and evidence: a `<path>:<line>` at the head commit and a span quoted from that line. [UC1 3]
runtime/R220. IF a verifier's report lacks a finding verdict line for a staged finding, names an id that was not staged, carries a word the vocabulary's `finding-verdict` field does not hold, or quotes a span the broker does not find on the cited line of the cited file at the head commit, THEN the broker SHALL exit 65, posting nothing and recording nothing. [UC1 3c]
runtime/R221. The trace SHALL accept the kind `finding.verify` with the outcomes `confirmed` and `disputed`, carrying a lens finding `data.id` and a `data.where` place, and SHALL refuse, exit 2, writing nothing, any other outcome, a `V-` id, or a missing `data.id` or `data.where`. [UC1 4]
runtime/R222. WHEN the broker posts a verifier's report, it SHALL record one `finding.verify` on `pr:#<N>` per finding verdict line, with `data.agent=verifier` and the evidence place as `data.where`, SHALL show each verdict with its evidence in the posted comment, and SHALL set the `verify.verdict` outcome by runtime/R211 alone, unmoved by any finding verdict. [UC1 3, 4]
runtime/R223. The record reader SHALL print, in each area's verifier row, the kit findings the verifier confirmed and those it disputed, each split into held up, not held up and unlabelled, and SHALL count no `finding.verify` toward a lens's counts or a finding's label. [UC4 3]

#### MODIFIED

runtime/R46. The record reader SHALL count a mistake as missed unless a finding raised on that PR by the kit's own review (any `data.agent` but `verifier`), not upheld at triage, names a file in the outcome's `data.files`, and SHALL always count a `qa-failed` mistake as missed. [UC4 1]
runtime/R48. The record reader SHALL count a finding of the kit's own review (any `data.agent` but `verifier`) toward every review area its `data.where` path belongs to, as held up when its triage is `accepted` or a mistake against its PR names its file, as not held up when it was rejected at triage or dismissed by a human with no such mistake, and as unlabelled otherwise; it SHALL count a verifier finding by the same labels in the area's verifier row only. [UC4 1, 2]

### Process

Deltas against `docs/specs/process.md`, which ends at R60.

#### ADDED

process/R200. WHERE the tier resolver prints a model for the reviewer tier in the `cross-provider` domain, WHEN `/implement` has requested the independent review, it SHALL request the verifier on the same head commit. [UC1 1]
process/R201. WHEN `/pr-iterate` requests a review at a new head, it SHALL also request the verifier at that head, and neither skill SHALL request the verifier more than once for one head commit. [UC2 3]
process/R202. `/pr-iterate` SHALL triage each verifier finding as it triages a bot's finding, and SHALL record its `finding.triage` with the finding's `V-` id. [UC2 1]
process/R203. IF the verifier marks a check-table row `disputed`, THEN `/pr-iterate` SHALL list that id at the top of its report as a check awaiting the operator, beside the skipped rows, and SHALL NOT rewrite that row's result for the dispute. [UC2 2]
process/R204. `/pr-iterate` SHALL NOT decide, amend or log a verifier's ⚠️ UNSPECIFIED item, whatever scope it carries, and SHALL list each one verbatim at the top of its report for the operator. [UC2 4]
process/R205. No `verify.verdict` outcome SHALL stop `/pr-iterate` from reporting a PR converged. [UC2 5]
process/R206. The shipped CI review prompt SHALL ask for `scope: inside` or `scope: outward` as the first words after the tag on each ⚠️ UNSPECIFIED item. [UC5 1]
process/R207. The shipped CI review prompt SHALL ask for one line per `pass` row of the PR's check table, naming the row's id and `upheld` or `disputed`. [UC5 2]
process/R208. IF the verifier disputes a finding of the kit's review, THEN `/pr-iterate` SHALL list that finding's id with the verifier's evidence at the top of its report, beside the disputed rows, and SHALL NOT reject the finding on the verifier's verdict alone. [UC2 1a]

## 5. Slices (vertical, demoable, in order)

Slice 1 is the tracer bullet. Slices 2, 3 and 5 can then run as one frontier. Slices 1 and 4
each move the shared layer, because the trace script is listed in `VERSION`. So each is a
release ticket in its own frontier, and slice 4 is `Blocked by:` slice 1 (`/to-tickets` rule 16,
the kit's ADR-0033).

**Slice 1 — one verifier review, posted and recorded (shared-layer release).**
- *Covers:* runtime/R200, R201, R202, R203, R204, R205, R206, R208, R209, R210, R211, R213, R221; process/R200.
- *Also:* the decision record for the verifier (needed, §8). The glossary gains Verifier and
  Provider. The kit's agents policy declares one provider per agent harness and the verifier
  candidates. The verifier contract is a new kit prompt beside the review worker's, adding only
  the verifier's role. The release bumps `VERSION`'s minor, writes `UPDATING.md`'s entry,
  re-captures the transcripts `tests/docs-demo.sh` quotes, and is landed only once its merge
  commit carries the `v<version>` tag (ADR-0015, ADR-0025).
- *Accept:* the trace suite refuses an unknown `verify.verdict` outcome, a `pass` with no
  `data.reviewed`, and a `W-H-1` finding id, and accepts `V-H-1`. It accepts `finding.verify`
  `confirmed` and `disputed` on `H-1`, and refuses another outcome, a `V-H-1` id and a missing
  `data.where`. The tier suite resolves a
  Sonnet author to the other provider's candidate, an author on that other provider to the
  session harness's candidate, and prints nothing for an undeclared author. The broker suite
  posts a fixture verifier report under its own markers beside an already posted kit review,
  and records `pass`, then `blocked` for a report with a HIGH finding. A landing-script fixture
  with only a `verify.verdict outcome=pass` is refused with exit 2.

**Slice 2 — the check table's passing rows and the review's findings judged.**
- *Covers:* runtime/R207, R212, R217, R218, R219, R220, R222.
- *Blocked by:* slice 1.
- *Also:* the vocabulary policy gains the field `finding-verdict` with `confirmed` and
  `disputed` (a policy file, no release). The verifier contract asks for the finding verdict
  lines. Slice 1 adds the trace kind `finding.verify` (runtime/R221) in its release, so this
  slice moves no shared-layer file.
- *Accept:* the dispatcher suite stages the spec line and the pinned test file for each `pass`
  row of a fixture PR body, and stages none for `fail` or `skipped` rows. It stages the kit
  review's findings at the head, an empty file when there are none, and records `unavailable`
  when no kit Axis-1 verdict is at the head. The broker suite records `blocked data.disputed=1`
  for a report disputing one row, and exits 65 with nothing posted for a report missing a pin
  line or using the word `agreed`. It records one `finding.verify` per finding verdict line with
  the outcome unchanged by them, and exits 65 with nothing recorded for a missing finding line,
  an unstaged id, the word `agreed`, and a span not on its cited line.

**Slice 3 — `/pr-iterate` with a verifier on the PR.**
- *Covers:* process/R201, R202, R203, R204, R205, R208.
- *Blocked by:* slice 1.
- *Accept:* a skill-text suite holds the once-per-head request, the bot-style triage with the
  `V-` id, the disputed-row and verifier-item lists at the top of the report, the unchanged
  converged rule, the item that is never decided or logged, and the disputed kit finding listed
  with its evidence and never rejected on the verifier's word alone.

**Slice 4 — what the verifier adds, measured (shared-layer release).**
- *Covers:* runtime/R46 (modified), R48 (modified), R214, R215, R216, R223.
- *Blocked by:* slice 1.
- *Also:* the second release: bump, `UPDATING.md`, re-captures, tag. Its `VERSION` history note
  lists the skill and template movements landed since slice 1.
- *Accept:* on UC4's fixture trace, the record reader counts the reverted PR as missed by the
  kit's review and caught by the verifier. It prints the verifier row's counts and one
  blocked-versus-pass landing, and a lens precision equal to the one it printed before the
  verifier findings were added. With `finding.verify` events added, it prints the confirmed and
  disputed kit findings split by label, and every lens count is unchanged. A landing-script fixture records `data.verified=blocked`, and
  `data.verified=none` when no verdict is at the head.

**Slice 5 — the CI review prompt writes the same shape.**
- *Covers:* process/R206, R207.
- *Blocked by:* nothing.
- *Accept:* `tests/ai-review-template.test.sh` holds the scope words, where they are written,
  and the pin-line instruction, and still holds that every provider job reads the one prompt
  file.

## 6. Non-goals (this PRD)

- **A verifier verdict that blocks a landing or holds the low-risk lane.** *Later*, K5. Whether
  the lane requires `verify.verdict outcome=pass` is open (§9). Until then the verdict is
  advisory, as the CI review workflow's jobs are.
- **The verifier deciding inside items or writing the decision log.** *Never*. Only
  `/pr-iterate`'s session decides an inside item (ADR-0038 clause 4), and only from the kit's
  own Agent 7 classification.
- **A dispatched verifier in a consumer project.** *Later*, together with promoting the
  dispatcher and the broker (#226). A consumer's cross-provider leg stays the CI workflow.
- **Recording a CI review's verdict in the trace.** *Later*. CI holds no trace, and reading a
  bot's comment into the trace would mean a new reader of untrusted text. Reopen when a consumer
  asks to measure its CI reviewers.
- **Running the pinned test again.** *Later*. The verifier works offline and judges what the
  test checks. CI already runs the suite. Reopen if `/retro` finds an `upheld` row whose test
  did not pass at its pin.
- **The verifier as a co-signer before an auto-merge** (D-08's stage 3). *Later*. Here no
  `verify.verdict` or finding verdict changes a landing (runtime/R215). Reopen when K5 lets a
  PR land without the operator's merge action, or when slice 4's record shows the verifier's
  confirmed and disputed verdicts agreeing with post-merge labels well enough to trust as a
  gate.
- **The verifier as a critic of the plan or the tests, on two providers** (D-08's stage 2).
  *Later*. Here it judges a PR head, its pass rows and the review's findings, and never a PRD,
  a ticket or a test before the diff. Reopen when a D-02 or D-08 PRD puts a cross-provider
  check before `/implement`, for example on approved acceptance tests (K9).
- **Running the verifier only on high-risk PRs to save spend.** *Later*, as a K6 efficiency
  ticket, once K3 says which PRs are high risk.
- **Changing ADR-0027's family walk for the kit's own review.** *Never* here. The verifier is a
  second reviewer, not a replacement for the first.

## 7. Technical constraints

- POSIX `sh`, kit policy as data, and skill text with its suites only.
- The provider rule lives in the kit's resolver wrapper, as ADR-0020 put the family rule there,
  so the shared resolver does not move. The trace is the one shared-layer script that moves.
- The worker is offline with no credential (ADR-0009). The broker's allow-list is unchanged,
  because a verifier needs only the two operations it already allows: a COMMENT review and one
  comment.
- The verifier's report is untrusted output. Only the broker reads it, and only through the
  contract's validation. The session reads the verifier's posts as it reads any bot's.
- At most one verifier run per head commit. A report covers at most the 64 rows the check
  table may hold (process/R47).

## 8. Decisions recorded for this PRD

**From D-02** (decisions.md, 2026-10-23):
- The work split with D-08: D-08's cross-provider verifier (C5) becomes its own kit PRD, K8,
  after K4.
- Labels come from post-merge outcomes, not from rulings that share the judge's model family
  (S-26). This is why the verifier is measured by the record (slice 4) before it decides
  anything.
- Q7's order of value: measurement first. So the verifier reports only.
- PRD-07 §6 deferred re-checking the evidence pins to K8.

**From D-08** (relayed by the D-08 factory session, 2026-10-31; settles §9's first question
and T-75):
- **C5's wording** (D-08's operator, 2026-10-23), in substance: a model from a different family
  or provider checks the reviewer's findings. Its object is the reviewer's findings: are they
  real, and what did the review miss?
- This PRD's MVP default judged the check table's `pass` rows. That overlaps C5 but is not the
  same thing. D-08 also used C5 as a co-signer before any auto-merge (its stage 3) and as plan
  or test critics on two providers (its stage 2). Those gating uses are *later* (§6).
- **Ruling** (this session, under the operator's delegation, 2026-10-31, on D-08's
  recommendation): keep the MVP, a different provider beside `/review-pr` on each PR head,
  report-only and recorded in the trace, and add one thing so that it meets C5. The verifier
  also takes `/review-pr`'s raised findings, as data, and returns a finding verdict per finding,
  `confirmed` or `disputed`, with its evidence (runtime/R217 to R223, process/R208). "What did
  the review miss" was already covered by the verifier's own `V-` findings on both axes.
  - A per-finding verdict is the conservative superset. Whether a pass-rows-only MVP would have
    been enough is left for D-08's operator to comment on later.
  - Finding verdicts are their own trace kind, `finding.verify`, never a `finding.triage`, so
    the verifier never labels a kit finding and the lenses' earned record stays the kit's
    review alone (as for `V-` findings).
  - A disputed kit finding does not make the verdict `blocked`, and `/pr-iterate` never rejects
    a finding on the verifier's word alone. The verifier stays advisory.
  - Evidence is a place at the head and a span quoted from it, which the broker checks against
    the head commit (the trust boundary's verified span): a dispute with no checkable evidence
    is refused.
  - The verifier runs after the kit's review is recorded at the head, because it judges that
    review's findings; when none is recorded it records `unavailable`.

**Derived while writing** (the session, under the operator's standing delegation of rulings;
the maintainer confirms them at approval):
- **Cross-provider means a different declared provider, not a different family.** Family
  differences within one vendor are already ADR-0027's rule. The provider is declared per agent
  harness in policy, and an undeclared author fails closed: no verifier is chosen.
- **A new trace kind, not `review.verdict` with a role key.** The landing script counts any
  Axis-1 `review.verdict` that is not blocked. A role key would count as a review unless every
  reader learned to skip it. A new kind fails closed for every reader that already exists.
- **The verifier never satisfies ADR-0032, and ADR-0032 does not move.** The kit's own Axis-1
  verdict is still the one review a landing requires. `merge.land` only records the verifier's
  outcome.
- **Verifier finding ids carry a `V-` prefix.** Triage is matched to a finding by id within a
  PR. Unprefixed, `H-1` from the verifier and `H-1` from a lens would be one finding to the
  record reader.
- **The verifier's findings never count toward the lenses' precision or catches**, so the
  earned record that K3 reads measures the kit's own review alone. The verifier gets its own
  row.
- **Both axes, with the review worker's contract.** One contract per task kind, never one per
  provider, so that comparing two vendors measures the models and not the prompts. The
  verifier contract adds only the pin lines.
- **Verdict words:** `blocked` for a CRITICAL or HIGH finding or a disputed row, `pass`
  otherwise, and `unavailable` when nothing ran. Recording `unavailable` makes a missing
  verifier visible to `/retro` instead of silent.

**Decision records:**
- **Needed at slice 1:** one record for the verifier. It covers the provider rule and its fail
  closed default, the advisory status, the `verify.verdict` kind with its outcomes and required
  keys, the `V-` id prefix, and the verdict never counting as the review. Adding a kind amends
  ADR-0024 clause 1. ADR-0024 is at its amendment cap (ADR-0021), so this is a new record, as
  ADR-0036 was. It takes the next free number when written.
- **Cited:** ADR-0009 (the worker is offline, the broker acts), ADR-0013 (the unreachable
  re-resolve), ADR-0020 and ADR-0027 (the family rule in the kit wrapper), ADR-0030 (a cascade
  diff's author), ADR-0032 (the landing's review check), ADR-0036 (the earned record), ADR-0037
  (the check table), ADR-0038 (scope words, and its note on the CI prompt), ADR-0033, ADR-0015
  and ADR-0025 (release tickets).

**Alternatives considered:**
- **The verifier's Axis-1 verdict counts as the review.** Rejected. One advisory model's word
  would be enough to land, and K3 would read a record mixing two reviewers.
- **The CI workflow as the kit's own verifier route.** Rejected for the kit. CI records no
  trace, so the verifier could not be measured, and measuring it is the point.
- **Judging the pins only, without a review.** Rejected. It leaves out the diff-level blind
  spots that motivate cross-provider review (S-10, S-26), and it would need a second contract.

## 9. Unresolved questions (MVP defaults; raise with `factory inbox add` if hit)

- ~~**D-08's own definition of C5 is not in this repository.**~~ **Settled** 2026-10-31 (§8,
  "From D-08"; T-75): keep the MVP and add a finding verdict per finding of the kit's review.
  The gating uses are *later* (§6).
- **Whether the low-risk lane requires a verifier `pass`.** A disputed row or a `blocked`
  verdict could hold a low-risk PR for the operator.
  - Options: never; only a disputed row holds; any `blocked` holds.
  - Next step: K5's grill, with slice 4's record in hand. MVP default: never (this PRD).
- **Requirement ids may collide with D-02's PRDs drafted in parallel.** This PRD numbers from
  runtime/R200 and process/R200, the next free ids in the living specs. Other K-PRDs written at
  the same time may take the same ids.
  - Options: renumber at approval in approval order; give each PRD a reserved block.
  - Next step: the session that approves the D-02 PRDs renumbers before any of them is
    published to a ticket. MVP default: renumber at approval.
- **The kit has no reachable cross-provider model today.** The kit policy's other-vendor ids are
  commented out until that CLI logs in. Until then every verifier run records `unavailable`.
  - Options: log the CLI in before slice 1 lands; land slices 1 to 4 and let `unavailable`
    count; declare a further provider.
  - Next step: an operator action, to be confirmed at slice 1's ticket. MVP default: land, and
    count `unavailable`.

## 10. Dogfood plan

Five tickets in slice order: slice 1 alone, then slices 2, 3 and 5 as one frontier, then slice
4 in its own frontier. Once slice 1 lands, every kit PR opened by `/implement` asks for the
verifier. The first `/retro` after slice 4 prints the verifier row of each review area, and
the counts of `unavailable`, `blocked` and `pass` there are what K5's grill reads when it
decides the lane question in §9.
