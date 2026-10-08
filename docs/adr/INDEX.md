# Architecture Decision Records

Each ADR captures **one** architectural decision for agentic-sdlc, in
[MADR format](https://adr.github.io/madr/). The record is the contract; the
development chronology lives in `docs/diary.md`.

Copy `NNNN-template.md` to start a new one.

## Index

<!--
One row per ADR, in numeric order. The Status column carries the *live* status
plus the date it reached it, and any supersession/amendment note — so this table
alone answers "what is currently binding?" without opening 40 files.
-->

| # | Title | Status |
|---|---|---|
| [0001](0001-the-kit-self-hosts-its-own-constitution.md) | The kit self-hosts its own constitution | Accepted 2026-08-27 |
| [0002](0002-strategic-means-ousterhout.md) | "Strategic" means Ousterhout's strategic programming; Evans's work is the context map | Accepted 2026-09-02 |
| [0003](0003-the-kit-maps-its-own-tiers.md) | The kit carries its own tier-to-model mapping, and never ships it | Accepted 2026-09-02 — supersedes the diary-recorded decision of 2026-08-27 below; amended 2026-09-17 to state the arrangement as general, with the guard policy as its second instance; amended 2026-09-28: a policy file the kit can fill ships filled, with no twin — the vocabulary checker's |
| [0004](0004-the-root-manual-is-the-kits-local-article.md) | The kit's root manual is also its local article, budgeted at 350 lines | Accepted 2026-09-02 — clauses 1 and 4 amended by ADR-0014 (2026-10-06): the tier practice lives in one kit-own article the root points at; the budget stands |
| [0005](0005-the-agent-harness-axis.md) | A capability tier may name the agent harness it runs on, and the kit ships the dispatcher | Accepted 2026-09-09 — amends ADR-0003 |
| [0006](0006-the-worker-budget-is-derived-from-the-host.md) | A dispatched worker runs inside a budget derived from the host at dispatch time | Accepted 2026-09-19 — amends ADR-0005; amended 2026-09-19 with what building #208 refined in clauses 5, 6 and 8, and again with what #209 settled for the suite |
| [0007](0007-a-review-never-resolves-to-the-sessions-own-model.md) | A reviewer resolves against the session that asks, and never to its own model | Accepted 2026-09-21 — amends ADR-0003; amended 2026-10-05 (#546): a `self-implemented` mapping names a model no session tier runs on, so the refusal is the net and not the route |
| [0008](0008-decisions-are-traced-to-a-local-append-only-record.md) | The chain's decisions are traced to a local, append-only record the chain never reads | Accepted 2026-09-22 — bound by ADR-0005's non-goal; the policy-file twin is ADR-0003's third instance — amended 2026-09-28 (#263, PR #263): a caller error in `begin` or `end` is exit 2, a trace error never is; amended 2026-09-28 (#271, PR #292): exit 3 is "cannot judge this trace", an unsupported schema; amended 2026-09-30 (#309, PR #315): clause 7's readers are the operator and the retrospective skill — a diagnosis reads the trace by the operator's hand, and no other skill calls a read subcommand; amended 2026-09-30 (#277, PR #319): the closed kind vocabulary gains `finding.dismiss`, a human closing a posted finding; amended 2026-10-01 (#345): `feedback`'s outcome gains `unasked` — the train nobody could answer, not a verdict — and the emit is `/merge-train`'s exit condition per landed PR; amended 2026-10-01 (#348): every kind holds `outcome` to a vocabulary of its own — an undeclared word is exit 2 at emit and an advisory in `verify`; amended 2026-10-01 (#385): `feedback` carries `data.by=operator\|train` — a human's verdict in the session, or a delegated train's own, counted apart; a window of `train` verdicts is no human verdict; amended 2026-10-02 (#409): `tool.use` declares `denied` — a call that fired its pre-tool hook and never returned, swept at session end by the Claude Code adapter; amended 2026-10-02 (#453): the run stack is keyed by session as well as by toplevel — two sessions in one checkout never read or pop each other's runs; a caller with no session id keeps the per-toplevel stack; amended 2026-10-02 (#466, PR #487): `finding.triage` holds `data.source` to `check\|bot\|human\|local`, a local finding's id to `[CHML]-[0-9]+` — or `A2-[0-9]+`, a confirm-list item numbered in the list's order — and that id to the local source alone, and a green or red `pr.iterate` to its three counts, digits; amended 2026-10-02 (#472): `stack <dir> [session=<id>]` prints a named checkout's open run and the run below it, refusing an unreadable stack or another repository's checkout with exit 2 — the Claude Code adapter's subagent-stop hook reads its run through it and keeps no copy of the stack's format; amended 2026-10-02 (#474): a subagent's run reaches the adapter's hooks on its spawn prompt's first line, `Trace-Run: <run id> [<parent run id>]`, read back from its transcript — the payload's `cwd` is the session's, not the subagent's (#478); amended 2026-10-05 (#543): `end <run>` closes the run it names or nothing — exit 2 naming the run that is open, nothing written — so a subagent sharing its session and checkout that never began cannot close its parent's run; a bare `end` keeps its meaning, and every shipped skill names its run at `end`; amended 2026-10-06 (#560): a bare `end` is deprecated — it still closes the top, then prints one stderr line naming the run it closed and the named form — on the way to a mandatory run id in a later release; amended 2026-10-07 (#567): `finding.raise` holds a present `data.id` to the review's severity id, `[CHML]-[0-9]+` — exit 2 at emit, an advisory in `verify` for a raise written before; amended 2026-10-07 (#569): a `spawn`'s present `model` is an id the shipped resolver lists for its agents policy (`agents.lib.sh --ids`), never the in-session spawn word — exit 2 at emit, an advisory in `verify` for a spawn written before; amended 2026-10-08 (#627): with tracing on, the Claude Code adapter refuses a spawn whose prompt carries no well-formed `Trace-Spawn:` line, which may also open a prompt that hands no run; amended 2026-10-08 (#628): `ticket.start` declares `resumed` and `pr.iterate` holds a present `data.cause` to `conflict\|pending-stuck` — a resumed ticket, a conflict with the base and a stuck check-run leave an event; amended 2026-10-08 (#654): the policy file still ships empty, but bootstrap asks and an off trace is a finding in the chain's reports |
| [0009](0009-a-dispatched-worker-acts-on-the-forge-only-through-the-broker.md) | A dispatched worker never holds network or credentials, and acts on the forge only through the broker | Accepted 2026-09-28 — builds on ADR-0005's non-goal 12 (the dispatcher does not enforce what a worker may do); the broker is where that enforcement lives; amended 2026-09-30 (#268): a review behind the head is posted anchored to the commit it reviewed, one whose commit left the PR is exit 75; amended 2026-10-01 (PR #320): on drift `--commit` is mandatory, its absence exit 65; amended 2026-10-01 (#375): the trace records one `finding.raise` per posted finding and a `review.verdict` per axis; amended 2026-10-01 (#424): each raise carries `data.posted=yes` |
| [0010](0010-a-typed-judge-is-a-task-domain-named-by-its-contract.md) | A typed judge is a task domain named by its contract, in two shapes | Accepted 2026-09-28 — stands under ADR-0003's closed tier vocabulary |
| [0011](0011-task-local-contracts-bound-the-lifecycle.md) | Task-local contracts bound the lifecycle | Accepted 2026-09-30 |
| [0012](0012-requirements-are-numbered-traced-and-anchored-in-living-specs.md) | Requirements are numbered, traced to tickets and tests, and anchored in living specs | Accepted 2026-10-05 — builds on ADR-0008: nothing here reads the trace |
| [0013](0013-a-reviewers-next-answer-is-an-ordered-fallback-in-the-shared-resolver.md) | A reviewer's next answer is an ordered fallback in the shared resolver, past what the caller names unreachable | Accepted 2026-10-05 — builds on ADR-0007; built by #548 |
| [0014](0014-the-root-manual-points-at-one-kit-own-article.md) | The root manual's read-on-demand elaboration moves to one kit-own article it points at | Accepted 2026-10-06 — amends ADR-0004 clauses 1 and 4; built by #489 |
| [0015](0015-a-release-is-tagged-by-its-landing-before-main-is-judged.md) | A release is tagged by its landing, before main is judged | Accepted 2026-10-06 — gives hard rule 3's landed release its mechanism; built by #509 |
| [0016](0016-the-kit-accepts-train-only-verdicts-while-it-delegates-landing.md) | The kit accepts train-only verdicts while it delegates landing | Accepted 2026-10-06 — the operator's ruling on #570; reads alongside ADR-0008's amendment of 2026-10-01 (#385); `/retro` questions 7 and 8 retire on it per window, built by #572 |
| [0017](0017-a-shipped-file-cites-a-kit-record-only-as-the-kits.md) | A shipped file cites a kit record only as the kit's | Accepted 2026-10-07 — #564; held by `t_kit_record_cites` in self-host over a fresh bootstrap |
| [0018](0018-two-kit-tiers-follow-a-model-family.md) | Two kit tiers follow a model family, not a pinned id | Accepted 2026-10-08 — the operator's decision; the planner is `opus` and the mechanical tier `sonnet` in the kit's own policy, amends ADR-0003 for those two tiers; a cascade rung equal to the mechanical mapping escalates to the implementer's model; held by `tests/agents-tiers.test.sh` and `tests/skill-cascade.test.sh` |
| [0019](0019-the-landing-script-refuses-a-pr-with-no-iteration-at-its-head.md) | The landing script refuses a PR with no iteration at its head | Accepted 2026-10-08 — #630; names the landing script an operator-run reader beside ADR-0008 clause 7; held by `tests/land.test.sh` section 9 |

## Conventions

- **File name**: `NNNN-short-kebab-title.md`, zero-padded to four digits.
  Numbers are never reused, even for a rejected ADR.
- **Status values**: `Proposed` · `Accepted` · `Rejected` · `Deprecated` ·
  `Superseded by NNNN`.
- **The "Decision outcome" section is the contract.** Implementation detail and
  historical context go in `More information` at the bottom, kept short.
- **When a decision is reversed or revised, do NOT edit the old ADR.** Write a
  new one and set the old one's status to `Superseded by NNNN`. An amendment
  that only *narrows or clarifies* the same decision may be recorded in place,
  dated and labelled as an amendment — but a reversal never is.
- **Write the ADR when the decision is made**, not when the code lands. An ADR
  written after the fact documents a rationalization, not a decision.
- **One decision per record.** If the title needs an "and", it is two ADRs.

## Decisions recorded in the diary, not as ADRs

<!--
Some material decisions do not warrant a standalone record but are still binding
policy. List them here with a date, so "it is not in docs/adr/" never means "it
was never decided". If one grows consequential enough, promote it to an ADR and
leave a back-reference in the diary entry.
-->

- **2026-09-02 — the kit's own mutation decision.** Stryker, pinned to one
  release, on demand against the docs-gate validators with their fixture
  tests as the target function, never as a gate; `scripts/mutation.kit.sh` is
  the command and the diary entry "The kit makes its own mutation decision"
  carries the baseline. Kit-only, never shipped.
- **2026-08-27 — the kit's `scripts/agents.config.sh` stays unmapped.** The kit
  names no model anywhere, including in its own copy of the tier mapping. Every
  tier here inherits the session's model and the resolver warns once, which is
  the state a consumer starts in too. **Superseded by ADR-0003** (2026-09-02):
  the shipped config stays empty, but the kit carries a kit-only mapping of its
  own, reached through the resolver's config seam and never shipped.
