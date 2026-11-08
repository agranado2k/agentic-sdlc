# ADR-0048: A loop ticket is judged against noise after it lands, beside the wave's two summed measures

- **Status**: Accepted
- **Date**: 2026-11-08
- **Deciders**: the planner session for #923 (PRD-11 slice 1), under the operator's delegation of rulings (ADR-0016); the decisions are PRD-11 §8's, approved by the operator, with T-59's measure settled on 2026-10-31 (#922); the merge of this record's pull request is the operator's yes
- **Supersedes / amends**: amends ADR-0024 clause 7 and ADR-0036 clause 5 (their caller lists) for the ruling recorder as a chain-run reader, and ADR-0037's ticket contract for the candidate block; recorded as a new record because ADR-0024 takes no further in-place amendment (ADR-0021 clause 5), as ADR-0036, ADR-0045 and ADR-0047 did
- **Superseded by**: —

## Context and problem statement

`/retro`'s before-and-after section (process/R25 to R28) judged an edit
that carries a `Targets:` query by one rate per landed PR before its landing
and one after. One quiet wave read as a fix that worked and one loud wave as
a fix that failed: the check read noise as a result. D-02 asked for the
check to be "eval-gated: three repeats, pooled SD", and PRD-11 makes that
the loop's judge. The same PRD needs contracts its later slices build on —
the confirm-list's surface token, the retro candidate's fields, the
`ruling` kind and a recorder that reads the trace from a chain skill — and
D-08's efficiency proposals need a measure in tokens and time, which T-59
settled. This record states all of it once, so the later tickets (PRD-11
slices 2 to 5) read one decision rather than five.

## Decision drivers

1. A fix counts as working only when its count moved beyond what the trace's
   own week-to-week variation explains.
2. The judge reads the trace `/retro` already reads; nothing new is
   recorded to make it work, and nothing gates a landing on it.
3. A cost and a time are read beside the counts, never folded into them,
   and never measure the operator.
4. The contracts later slices build are fixed before they are built, so a
   slice cannot quietly widen the chain's reads.

## Considered options

1. **Keep one rate a side.** Rejected: driver 1.
2. **A significance test (Welch's t, a p-value).** With three repeats a side
   it almost never passes. Rejected (PRD-11 §8).
3. **D-08's pre-landing eval gate** — a fixed task set solved at least three
   times with the change and three without it. Needs an eval harness the kit
   does not have; deferred as its own PRD (PRD-11 §6).
4. **Three equal sub-windows a side and a drop beyond one pooled SD, read
   after the landing.** Chosen.

## Decision outcome

Chosen option 4.

1. **A loop ticket** is any landed ticket whose stamp carries a `Targets:`
   line, whatever wrote it: a retro candidate, the factory's planner,
   `/to-tickets`, or one of D-08's efficiency proposals, which enter through
   a count proxy because `Targets:` stays a count query. `/retro`'s
   before-and-after section judges every loop ticket once its after window
   closes.
2. **The eval gate is a post-landing noise check, not D-08's eval gate.**
   With `W` the retro's window length and `T` the landing, each side is
   split into three equal consecutive **repeats**, `[T − W, T − 2W/3)`,
   `[T − 2W/3, T − W/3)`, `[T − W/3, T)` before and `(T, T + W/3]`,
   `(T + W/3, T + 2W/3]`, `(T + 2W/3, T + W]` after. A repeat's rate is the
   query's matches in it per landed PR in it. The **pooled SD** is
   `sqrt((s_b² + s_a²) / 2)`, each `s` the sample standard deviation
   (divisor 2) of one side's three rates. All of it runs in `awk`, compares
   unrounded and prints to two decimals. It gates nothing: it says whether
   a landed fix moved its count beyond noise.
3. **Three verdicts.** From the before-mean `B`, the after-mean `A` and the
   pooled SD `S`: `drop` when `B − A > S`; `no drop` when `A ≥ B`, a finding
   naming the ticket, as before; `within noise` otherwise, reported and
   never a finding — a fix that did no measurable harm is not reopened on
   noise, and its loop stays open. A row is `inconclusive` with its reason
   when the windows differ in tier mapping or kit version or a repeat holds
   fewer than 3 landed PRs (that reason replaces "no landed PR in a
   window"), and `pending` while its after window is open. A run that ended
   `stopped` has its events — landings and matches alike — left out of
   every count. The numbers (3 repeats, 3 PRs a repeat, 1 pooled SD) stay
   fixed in the skill.
4. **The loop closed.** A `drop` row records one `note outcome=closed`,
   subject the retro, the ticket in `related`, marked
   `data.question=before-after` — the mark keeps a finding's closed note
   (`/retro`'s step 6) from reading as a closed loop. The check prints a
   `loop closed:` line only for a ticket with no such note, so a second
   retro records none.
5. **Each row says how the ticket landed**: `landed: lane` when its
   `merge.land` carries `data.via=lane`, `landed: operator` otherwise —
   `pending` and `inconclusive` rows too. The section ends with one count
   line, `loop tickets: drop <n>, within noise <n>, no drop <n>,
   inconclusive <n>, pending <n>; via lane <n>`, where `via lane` counts the
   rows, of any verdict, whose ticket the lane landed.
6. **Two summed measures, per wave, never one score.** Per ticket landed in
   the window: its **priced tokens**, the cost the trace's priced export
   gives, per model, for the token-bearing events of every run the ticket's
   `/implement` opened (a `run.start` with skill `implement` and the ticket
   as subject) and the runs beneath it by `parent`; and its **agent
   wall-clock**, each such run's `run.start` to its `run.end`, the run
   ending at the open, reviewed PR, never at the ticket's `merge.land`. Two
   readings this session made, recorded so the next ticket does not remake
   them: a ticket with several `/implement` runs (a resumed one) sums them;
   and the stop of the agent that ran `/implement` — which the agent harness
   files under the run that spawned it, or under none, naming the ticket in
   `related` — counts toward that ticket, because it is where most of an
   implementer's tokens are recorded. The line prints the median of each
   (the lower middle over an even count) and how many entered it; a ticket
   with no `/implement` run, or a run with no `run.end`, leaves both
   medians, and one whose tokens hold an unpriced model leaves the token
   median only, each counted on the line. No operator wait — approval,
   review or QA — is a measure: those are the factory's gate-time metrics
   and measure the operator, not the change.
7. **Contracts the later slices build**, decided here and built there:
   - a vocabulary field `surface` — `output-format`, `flag`, `exit-code`,
     `agent-rule`, `other` — that Agent 7 writes after an outward item's
     scope, read as `other` when missing or unknown (slice 3);
   - two vocabulary fields for the candidate block: `Edits:` — `lens`,
     `skill`, `check` or `policy`, then one name token — and `Runs:` — one
     or more run ids in the shape the trace mints (slice 2);
   - the trace kind `ruling`, outcomes `keep` and `change`, subject
     `pr:#<N>`, carrying `data.item` (`A2-<n>`), `data.surface`, `data.head`
     (40 hex digits) and `data.by` (`operator`, `session`, `default`), every
     other shape refused (slice 3, a shared-layer release).
8. **ADR-0024 clause 7 and ADR-0036 clause 5, amended:** the ruling
   recorder, run by `/pr-iterate`, a chain skill, is a trace reader. It reads
   the latest Axis-2 `review.verdict` on the PR and the PR's `ruling`
   events, and prints and records only item ids, surface tokens, review
   area names, PR numbers, commit shas and the `ruling` kind's words — never
   text from a PR, a comment, a commit message or a ticket. No chain skill
   calls `show`, `summary`, `export`, `record` or `outcomes` itself. Both
   clauses stay binding for everything else; this amendment takes effect
   when slice 3 lands the recorder.
9. **ADR-0037's ticket contract, amended for the candidate block:** the
   retro → ticket handoff is a blank-line-separated block of bare lines in
   the retro report's findings list — `Finding:` and, when the candidate
   edits something, `Edits:`, `Runs:` and `Targets:` — each held by the
   vocabulary checker. `/to-tickets` carries a candidate's `Targets:` onto
   its ticket as a stamp line beside its `Retro:` line, and publishes no
   ticket from a candidate with an `Edits:` line and no `Targets:` line
   (slice 2).
10. **Not in this record's slice**, so a reader does not assume them built:
    the `Edits:` and `Runs:` checks and the lens edits held for the operator
    (slice 2), the surface, the `ruling` kind and its recorder (slice 3), the
    ruling defaults (slice 4), and the proposals from recurring rulings
    (slice 5).

### Consequences

- Good: a quiet wave no longer passes for a working fix, and a loud one no
  longer condemns a good one; a closed loop is a fact in the trace.
- Good: an efficiency proposal reads its tokens and its time beside its
  count, without a weighting nobody chose.
- Bad: three repeats of at least three landed PRs each needs nine landings a
  side, so a small project's rows read `inconclusive` for a long time; the
  numbers are revisited if the first real rows mostly do.
- Bad: with n = 3 a side the gate is coarse; it stops the commonest false
  result, a single quiet window, and no more.
- Bad: the token measure rests on how the agent harness files a spawned
  agent's stop; a harness that files it elsewhere moves the measure.

## Confirmation

`tests/retro-skill.test.sh` section 22 runs the check, the close and the
measures spans over fixture traces — the drop row of `0.50 0.40 0.60 →
0.10 0.20 0.00`, the within-noise row, the equal means, the thin repeat, a
stopped run, one closed note and none on a second run, the two medians with
the left-out tickets counted — and holds this record's words, its index row
and the glossary's six terms. Each later slice's suite holds its clauses as
it builds them.
