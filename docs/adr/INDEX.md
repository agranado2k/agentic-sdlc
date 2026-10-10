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
| [0007](0007-a-review-never-resolves-to-the-sessions-own-model.md) | A reviewer resolves against the session that asks, and never to its own model | Accepted 2026-09-21 — amends ADR-0003; amended 2026-10-05 (#546): a `self-implemented` mapping names a model no session tier runs on, so the refusal is the net and not the route — that amendment superseded for the kit's own policy by ADR-0020 (2026-10-09): the refusal is the route again, through the kit wrapper's family bridge |
| [0008](0008-decisions-are-traced-to-a-local-append-only-record.md) | The chain's decisions are traced to a local, append-only record the chain never reads | Superseded by 0024 |
| [0009](0009-a-dispatched-worker-acts-on-the-forge-only-through-the-broker.md) | A dispatched worker never holds network or credentials, and acts on the forge only through the broker | Accepted 2026-09-28 — builds on ADR-0005's non-goal 12 (the dispatcher does not enforce what a worker may do); the broker is where that enforcement lives; amended 2026-09-30 (#268): a review behind the head is posted anchored to the commit it reviewed, one whose commit left the PR is exit 75; amended 2026-10-01 (PR #320): on drift `--commit` is mandatory, its absence exit 65; amended 2026-10-01 (#375): the trace records one `finding.raise` per posted finding and a `review.verdict` per axis; amended 2026-10-01 (#424): each raise carries `data.posted=yes`; amended 2026-10-09 (#646): a LOW is counted in the review body, never posted inline, and raised `data.posted=no` |
| [0010](0010-a-typed-judge-is-a-task-domain-named-by-its-contract.md) | A typed judge is a task domain named by its contract, in two shapes | Accepted 2026-09-28 — stands under ADR-0003's closed tier vocabulary |
| [0011](0011-task-local-contracts-bound-the-lifecycle.md) | Task-local contracts bound the lifecycle | Accepted 2026-09-30 |
| [0012](0012-requirements-are-numbered-traced-and-anchored-in-living-specs.md) | Requirements are numbered, traced to tickets and tests, and anchored in living specs | Accepted 2026-10-05 — builds on ADR-0008: nothing here reads the trace |
| [0013](0013-a-reviewers-next-answer-is-an-ordered-fallback-in-the-shared-resolver.md) | A reviewer's next answer is an ordered fallback in the shared resolver, past what the caller names unreachable | Accepted 2026-10-05 — builds on ADR-0007; built by #548 |
| [0014](0014-the-root-manual-points-at-one-kit-own-article.md) | The root manual's read-on-demand elaboration moves to one kit-own article it points at | Accepted 2026-10-06 — amends ADR-0004 clauses 1 and 4; built by #489 |
| [0015](0015-a-release-is-tagged-by-its-landing-before-main-is-judged.md) | A release is tagged by its landing, before main is judged | Accepted 2026-10-06 — gives hard rule 3's landed release its mechanism; built by #509 |
| [0016](0016-the-kit-accepts-train-only-verdicts-while-it-delegates-landing.md) | The kit accepts train-only verdicts while it delegates landing | Accepted 2026-10-06 — the operator's ruling on #570; reads alongside ADR-0008's amendment of 2026-10-01 (#385); `/retro` questions 7 and 8 retire on it per window, built by #572 |
| [0017](0017-a-shipped-file-cites-a-kit-record-only-as-the-kits.md) | A shipped file cites a kit record only as the kit's | Accepted 2026-10-07 — #564; held by `t_kit_record_cites` in self-host over a fresh bootstrap |
| [0018](0018-two-kit-tiers-follow-a-model-family.md) | Two kit tiers follow a model family, not a pinned id | Accepted 2026-10-08 — the operator's decision; the planner is `opus` and the mechanical tier `sonnet` in the kit's own policy, amends ADR-0003 for those two tiers; a cascade rung equal to the mechanical mapping escalates to the implementer's model; held by `tests/agents-tiers.test.sh` and `tests/skill-cascade.test.sh`; clause 1 superseded for the reviewer and clause 4 widened by ADR-0020 (2026-10-09) |
| [0019](0019-the-landing-script-refuses-a-pr-with-no-iteration-at-its-head.md) | The landing script refuses a PR with no iteration at its head | Accepted 2026-10-08 — #630; names the landing script an operator-run reader beside ADR-0008 clause 7; held by `tests/land.test.sh` section 9 — amended 2026-10-10 (#673): a `review.verdict` at the head is checked the same way, overridden by `--no-review '<reason>'`; a prose-only PR lands on both overrides; held by section 14 |
| [0020](0020-the-kits-reviewer-follows-the-sonnet-family.md) | The kit's reviewer tier follows the Sonnet family | Accepted 2026-10-09 — the operator's ruling of 2026-10-08 (#660); the reviewer is `sonnet`, `self-implemented` unmapped, the fallback `opus claude-fable-5-1`; the kit wrapper's bridge reads whole families; held by `tests/agents-tiers.test.sh`; clause 5's Codex non-goal superseded by ADR-0022 (2026-10-10); amended 2026-10-10 (#724): the fallback is empty in both kit policies — reviews run on the Sonnet family only, and a Sonnet session's review is spawned by a session off that family |
| [0021](0021-a-record-past-five-amendments-is-consolidated-into-a-successor.md) | A record past five in-place amendments is consolidated into a successor, starting with ADR-0008 | Accepted 2026-10-10 — #679; ADR-0008 takes no further in-place amendment and is consolidated into a successor that keeps its clause numbers (build: #692); the cap binds every record; amended 2026-10-10 (#692): ADR-0008's ceiling leaves the frozen line once ADR-0024 supersedes it |
| [0022](0022-the-codex-sessions-reviewer-follows-the-sonnet-family.md) | The Codex session's reviewer follows the Sonnet family too | Accepted 2026-10-10 — #691, on the operator's direction of 2026-10-09; supersedes ADR-0020 clause 5's Codex non-goal; `claude-code:sonnet`, fallback `claude-code:opus claude-code:claude-fable-5-1`, `self-implemented` unmapped; held by `tests/agents-tiers.test.sh`; amended 2026-10-10 (#724) by ADR-0020's amendment: the fallback is empty |
| [0023](0023-the-worktree-cleanup-keeps-a-checkout-a-live-session-holds.md) | The worktree cleanup keeps a checkout a live session holds | Accepted 2026-10-10 — #680; amends ADR-0008 clause 5 as a new record (ADR-0021 clause 4): `stack <dir> --all` prints every open run in a checkout, and the cleanup keeps a merged worktree with an open run or a process in it, naming which |
| [0024](0024-decisions-are-traced-to-a-local-append-only-record-as-amended.md) | The chain's decisions are traced to a local, append-only record the chain never reads — ADR-0008 consolidated | Accepted 2026-10-10 — #692; supersedes ADR-0008 under ADR-0021, its clause numbers kept, every amendment folded in present tense, ADR-0023 clause 1 in clause 5 and the operator-run readers of ADR-0019 and ADR-0023 in clause 7; held by `tests/trace.test.sh` section 18 |

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
- **Five in-place amendments at most** (ADR-0021). A record whose header
  already names five takes no sixth: its next change is a consolidating
  successor that keeps its clause numbers, and the old record's status becomes
  `Superseded by NNNN`.
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
