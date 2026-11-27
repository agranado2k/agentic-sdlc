# D-05 · Research: improving the SDLC agent harness

Date: 2026-11-27. Phase 1 (survey, S-25 to S-55) and phase 2 (the operator's sources S-1 to S-14,
with S-1's guides S-15 to S-24), plus a re-read of D-02's 45 sources for the harness, all read
through restricted readers. Every claim cites a source id: a bare `S-n` is this discovery's
`sources.yaml`, `D-02/S-n` is D-02's. **[inference]** marks this session's own reasoning. Quotes
passed through a summarising fetch tool: they are near-verbatim, and a record that cites one checks
it against the page first. Where a reader saw only part of a page, `sources.yaml` says so.

## 1. Summary

**The question.** What should change in the kit's agent harness (skills, hooks and guards, the
dispatcher, the trace) so agents deliver more reliably and at lower cost, and which practices from
other harnesses and verification tools are worth adopting?

**The answer so far:**

- **The harness measurably changes results, though less than the model.** Harness-Bench ran 10
  models through 7 harnesses on the same tasks: the spread was 5.0 to 9.5 points for nine models
  and 39.2 for one, and no harness was best on every model (S-35). SWE-agent's interface alone
  moved the same model from 11.0% to 18.0% on SWE-bench Lite (S-32). Each Harness-Bench cell ran
  once, so run-to-run variance is unmeasured (S-35).
- **Accuracy without cost and repeat trials is not progress.** Simple baselines matched
  state-of-the-art coding agents at a fraction of the cost (S-53); an agent that passes once often
  fails on repeat, which pass^k exposes (S-33); a fixed three-step pipeline matched agents at $0.70
  an issue (S-52).
- **Agents game the checks that judge them.** When the tests are impossible to pass honestly,
  frontier models pass them anyway, by editing or special-casing them, up to 76% of the time on
  one suite; read-only or hidden tests and an explicit "flag for a human" exit cut that sharply
  (S-55). Any evidence gate the kit adds needs the same protection **[inference]**.
- **The verification layer is the lever, and it must be evaluated like any other system.** The
  Claude Code team grades its reviewers against reverts and rejected changes, replays incident PRs
  and measures recall per stage (S-14); sashiko ships a replay benchmark (S-7). The kit records
  outcomes (K1) but has no replay **[inference]**.
- **Cheap, diff-scoped evidence beats more reviewers.** S-14: "One reviewer, multiple rounds".
  Mutation testing runs on diffs at Google scale only once it samples few mutants on changed,
  covered lines (S-26); LLM-written mutants and tests were 73% accepted at Meta (S-28); an agent
  writing property tests found real bugs at about $10 a valid bug (S-29).
- **Gates fail open by default, and the field rolls policy out in stages.** Claude Code and Cursor
  hooks fail open unless set to block (S-38, D-02/S-32); Kubernetes runs a policy as warn and audit
  before enforce (S-36); S-14 adds off, observe and enforce for a commit gate.
- **Recovery is a solved problem elsewhere.** Idempotency keys (S-41), one retry layer with a
  budget and a propagated deadline (S-42), checkpoints replayed from an event history (S-43), and
  for agents, a progress file plus git commits as recovery points (S-44).
- **Context is the cost line.** Context is a finite attention budget (S-46); accuracy falls as input
  grows even on simple tasks (S-47); a cached prefix costs a tenth of uncached input, but only while
  it stays byte-identical (S-50, S-48).

**Recommendations** (each argued in §4):

1. **Adopt** a review replay: past landed PRs with a known outcome (K1's reverts and fixes),
   restored to the reviewed commit, a one-sentence answer key, merged-and-stable PRs as the
   control, recall per stage, repeat trials reported as pass^k (S-14, S-7, S-33, S-53).
2. **Adapt** diff-scoped evidence gates: mutation and CRAP scores on the changed code as review
   evidence, property and differential tiers in the test ladder, with tests the implementing agent
   cannot edit (S-2, S-4, S-26, S-28, S-29, S-55, S-14).
3. **Adopt** gate rollout modes, off, observe and enforce, with the two-block escape and a
   per-commit verification stamp; settle D-02's fail-open question per guard through them
   (S-14, S-36, S-38).
4. **Adapt** harness reliability and cost: reconcile-before-retry with an idempotency key, one
   retry layer, a skill content hash on each spawn, a count of missing usage, per-run budgets, a
   Stop-hook completion gate, a stable cached prefix (S-15, S-41, S-42, S-44, S-19, S-38, S-50).
5. **Later:** formal proof as an optional top rung for consumers (S-8 to S-13); decision models
   for fixed-choice gates (D-02/S-8); provenance-tracking control planes such as CaMeL (S-40); the
   topology record D-02 recommended and no PRD took.

## 2. Landscape (phase 1)

### The sub-questions

Agreed with the operator before the search (operator, 2026-11-27):

1. **Evidence gates:** what evidence pipelines require before a change counts as done, and what each costs.
2. **Evaluating the harness:** how a harness or a review agent is measured, and how much the harness, not the model, moves the result.
3. **Guard and gate design:** fail-open or fail-closed, how a new gate is rolled out, hooks and policy layers.
4. **Run reliability:** recovering a crashed or timed-out run without repeating side effects, versioned definitions, budgets and stopping.
5. **Cost inside the harness:** what context loads each session, caching, compaction, tool design, token accounting.
6. **Dissent:** where harness engineering hurts.

31 sources were searched for across canon, practice, new work and dissent (S-25 to S-55); 29 were
read, 2 were not (§6).

### Schools of practice

| School | Idea | Fits | Costs | Who | Sources |
|---|---|---|---|---|---|
| **A · Thin loop** | A minimal loop and a bash tool; trust the model, delete scaffolding as models improve | Frontier models on well-tested repos | No guarantees; nothing stops an agent gaming its checks | mini-swe-agent; Sketch | S-54, D-02/S-15, D-02/S-12, S-51 (unread) |
| **B · Interface and context engineering** | Shape what the model sees and can do: tool design, capped search, linted edits, just-in-time context, a stable cached prefix, compaction | Every harness; the measured gains are here | Ongoing tuning per model; effects vary by model | SWE-agent, Anthropic, Manus, OpenAI Codex | S-32, S-46, S-47, S-48, S-49, S-50, D-02/S-45 |
| **C · Deterministic control plane** | Hooks, policies and gates outside the model decide what runs; failure behaviour and rollout are explicit | Irreversible or security-relevant actions | Fail-open defaults; CaMeL paid 77% vs 84% task success and about 2.8x tokens | Claude Code, Cursor, Kubernetes, CaMeL | S-38, S-36, S-37, S-39, S-40, S-16, D-02/S-32, D-02/S-33 |
| **D · Evidence-gated verification** | A change is done when executable evidence says so: tests as the oracle, mutation, property and differential tests, proofs at the top | Code with a test suite; costs climb with each rung | Mutation compute; false positives; tests the agent can edit get gamed | Google, Meta, Anthropic, unclebob | S-25, S-26, S-28, S-29, S-30, S-31, S-55 |
| **E · Durable execution** | A run survives a crash: checkpoints, idempotency keys, retry budgets, progress files, recovery points | Long runs, side effects on outside systems | Storage and replay latency; idempotency must be designed per action | Stripe, Google SRE, Temporal, LangGraph, Anthropic | S-41, S-42, S-43, S-44, S-45 |

Across all five sits **measurement**: execution-graded benchmarks (S-31, S-34), pass^k (S-33),
paired harness runs (S-35) and cost-aware comparison (S-53). It is how the schools are judged
rather than a way to build a harness, so it is the frame of §4, not a sixth school.

### Emerging work (last 18 months)

- **Harness evaluation across models** (S-35, May 2026): one run per cell, so a first map, not a
  settled ranking.
- **Test gaming measured** (S-55, Oct 2025): impossible tasks turn the pass rate into a cheating
  rate; LLM monitors caught 42–65% of it on SWE-bench.
- **LLMs writing the verification:** mutants and the tests that kill them (S-28, Jan 2025); property
  tests by an agent (S-29, Oct 2025), though only about a quarter of LLM-written property tests are
  valid and sound (S-30).
- **Fail-closed hooks as a setting:** Claude Code's `onFailure: "block"` (S-38, v2.1.295 or later).
- **Provenance-tracking control planes** (S-40, 2025): research grade, with a utility and token cost.
- **Formal proof at scale** (S-8, Oct 2026): real, but hundreds of millions of tokens a proof.
- **Gate rollout and incident replay inside an agent team** (S-14, Nov 2026; S-7).

### Where the kit sits [inference]

- **C, strongly:** guards and hooks around tools, base-branch policy (ADR-0039), the spawn guard,
  the risk rule and kill switch.
- **D, partly:** tests first, acceptance tests approved with the ticket and held (ADR-0046), the
  check table; mutation only on demand.
- **B, partly:** a budgeted root manual, skills disclosed on demand, read-only reviewer fan-out.
- **E, thinly:** the open-run registry and duplicate-refusing trace events; no idempotency key or
  retry budget.
- **A, rejected** for writes, by design.
- **Measurement:** outcomes and verdicts recorded, no replay and no repeat trials.

## 3. The operator's sources (phase 2)

### S-1 and its guides · openworker harness (andrewyng) — schools C and E

A Rust engine with TypeScript and Rust SDKs that an app embeds: the engine owns the loop,
approvals and durable sessions; the app owns UI, credentials, models and tools (S-1). Its guides
(S-15 to S-24) carry the mechanisms that bear on the kit:

- **Recovery without side-effect replay** — "If an action's outcome is unknown, inspect its status
  before retrying it" (S-15); on limits, panics or timeouts "the turn stops without replaying the
  action, and cancellation is not rollback" (S-23).
- **Immutable agent identity** — changing instructions, tools or approval mode needs a new agent
  name; sessions pin the tool bundle, policies and executable bytes (S-15, S-23).
- **Fail-closed by boundary** — a required check that is unavailable parks the session until it is
  restored and explicitly resumed; detectors that time out never become allows; observer hooks
  cannot veto (S-16). Incomplete streamed tool calls cannot authorise execution (S-20).
- **Isolation** — the loop and the tools can run in separate sandboxes; the sandbox gets a
  placeholder credential and the real one stays with the trusted provider (S-17).
- **Least exposure** — the bundle's tool list is the selection; missing or duplicate tools fail
  with no fallback (S-18, S-23).
- **Telemetry honesty** — "Missing usage is unknown, not zero"; drops and write failures are
  counted; "Traces are best effort, not a billing ledger" (S-19, S-20).
- **Per-turn limits** — model calls and output tokens per turn (S-15).
- No measured results anywhere in S-1 or its guides. It agrees with school E and goes further than
  the survey on fail-closed behaviour (school C); it leaves out evaluation entirely.

### S-2 to S-4 · unclebob's crapper, mutator and agnesse — school D

Three tools with one design: run on the diff, answer by exit code, write machine-readable results.

| Tool | What it does | Agent-facing shape |
|---|---|---|
| crapper (S-2) | CRAP = CC² × (1 − coverage)³ + CC per function; 30+ is "complex and under-tested" | `--threshold 30` exits 2; `--changed` scores only git additions and edits |
| mutator (S-4) | Mutation score = killed / (killed + survived) | exits 3 when a mutant survives; `--changed`; differential re-runs after a snapshot |
| agnesse (S-3) | A FitNesse-derived acceptance-test wiki: Markdown tables are fixtures, results are JSON | exits with the failing-page count; an MCP server (`list_pages`, `run`, `get_results`); `--rerun-failures` |

crapper implements Savoia's formula (S-25), whose author warns it "should not be abused or misused
as a proxy for code quality". mutator's diff scoping is the move that made mutation testing viable
at Google (S-26). crapper and mutator cover Clojure, Java, Go, TypeScript/JavaScript, Rust, Python
and Swift; none covers POSIX sh, most of the kit's own code. No measured results. **[inference]**
For the kit's own code the reachable target is the Node docs harness; for consumers, the tools fit
an optional gate. The kit's only mutation run today is `scripts/mutation.kit.sh` (Stryker, on
demand, never a gate), and README credits swarm-forge for "mutation testing as review *evidence*".
What they leave out: who may edit the tests the score depends on (S-55).

### S-5 · Bailador, "Uncle Bob's agent pipeline" (Medium)

**Unread:** HTTP 403. No workaround was used. The operator may paste it as a note, as for S-14.

### S-6 · Prime Intellect — measurement, school D

An RL and evals organisation (65 repos). `verifiers` builds one environment that serves both RL
training and evaluation; `prime-envs` smoke-tests each changed environment in CI, and counts a
zero CLI exit as a pass only when the saved episode also succeeded; `prime-agent` runs autonomously
within turn, token and time budgets with user-defined gates, warning that a passed gate only checks
what it verifies. No measured results in the READMEs read.

### S-7 · sashiko — measurement

A Linux Foundation agentic code-review system for the kernel and other systems projects. Parallel
specialist stages (goal, implementation, execution flow, resources, locking, security), then a
verification stage and a per-finding check. `sashiko benchmark` replays historical bugs: an
isolated database per run, a judge matching findings to ground-truth descriptions, suites of 9, 99
and 999 Linux entries plus 53 versioned LKML entries. Reported: 75.8% of Linux bugs detected
(v0.9.3), 58.5% on GCC (v0.7.0), false positives under 20% by manual sample. It applies the
benchmark pattern (S-31) to review rather than repair; it does not report repeat trials (S-33).

### S-8 · Anthropic, "LLMs are making formal software verification feasible at a much larger scale" (with Theorem, 2026-10-22) — school D, top rung

The spec is derived mechanically from an existing fuzz entry point ("no crash for inputs under
64 MB"); Claude writes the Rocq proof; "the Rocq kernel checks it against the specification", so no
human reads the proof. A failed proof sends Claude to patch the code, regenerate the spec and
reprove; behaviour-changing patches were penalised and audited for reward hacking. Results: 239
entry points in 123 OSS-Fuzz libraries proven crash-free, hundreds of bugs found, about 180 million
lines of Rocq, a typical proof about 600,000 lines. Opus 5.5 proves half of 36 small tasks with
about 40% fewer tokens than Opus 5; agents sharing a proof workspace used 17% fewer tokens. Limits:
the trusted base (kernel, RISC-V and Linux semantics, compiler, hardware); single-threaded static
musl binaries only; proofs "can take hundreds of millions of tokens". The appendix PDF was fetched
but its text was not extractable.

### S-9 · Lean — school D

One language for program and specification, a minimal trusted kernel, native compilation,
automation tactics (`grind`, `bv_decide`). The transferable pattern is AWS Cedar's (Lean use-case
page): an executable Lean model about a tenth the size of the Rust code, differential tests on
millions of random inputs against it, and "No new Cedar version is released unless its model,
proofs, and differential tests are current." No cost figures.

### S-10 to S-13 · the formal-verification companies — school D

- **&Truth (S-10):** a stated mission, "reads code in any language and mathematically proves it
  safe, secure, and correct"; no mechanism, no libraries.
- **Harmonic (S-11):** Aristotle takes a property in plain English, returns proved, refuted or open
  with the assumptions behind each verdict, and can run on every commit; vendor-reported case
  studies (Heartbleed code refuted, the fix proved). The IMO2025 repo holds Lean statements and
  proofs for problems 1 to 5.
- **Theorem (S-12):** proofs a customer's CI can recheck. `oss-verify-proofs` has 695 of 20,659
  statements proved; `rocq-linux-process-semantics` checks one new file in about a second against a
  model whose full build takes about 45 CPU-minutes.
- **Axiom (S-13):** mathematics. AXLE is a client for a hosted Lean verification API; the Stacks
  formalisation keeps AI-written proofs (`StacksFrontier`) apart from human-reviewed ones
  (`StacksCore`).

The operator's table needs corrections before it is cited: see the erratum in
`notes/formal-verification-companies.md`.

### S-14 · Osmani, "How the Claude Code team thinks about verification" (claude.dev, 2026-11-16) — schools C and D, measurement

The operator's copy matches the published article on all eleven checkpoints read. The practices,
against the kit **[inference for the kit column]**:

| S-14 practice | The kit today |
|---|---|
| Review rules read from the base branch, never the PR | ADR-0039, `scripts/policy.sh` |
| Still failing after 3 rounds → a human | the third identical failure stops (`REPEATED-FAILURE.md`) |
| Reviewers graded by reverts and rejections | K1's outcome recorder, the earned record |
| A review is valid for one commit only | verdicts are recorded per head |
| Cheap checks before the PR | `/implement` runs the suite before pushing |
| **A new gate starts in observe mode; two blocks, then let through; every commit stamped with how it was verified, "none" included** | **No** |
| **A 39-item reliability checklist, each item with a diff-readable trigger and the incidents behind it; 3 to 10 match per diff** | Lens slicing by path; no incident-backed trigger list |
| **Misses become rules only when seen in two PRs, visible in a diff, surviving three disproving agents, then human approval; three bug finders replayed on incident PRs** | `/retro` → `/to-tickets`, unranked, no replay |
| **One reviewer tuned over rounds, not a second one stacked** | PRD-13 stacks a cross-provider verifier |
| **Recall measured separately for raw findings, after verification, and final** | `finding.verify` recorded; no per-stage recall |
| **Flaky tests: no skip, sleep or retry; delete with a written reason** | No rule |

It recommends three test types for agents: end-to-end, property and differential. Its observe mode
matches Kubernetes' audit and warn modes (S-36); its flaky-test rule answers the gaming S-55
measures.

### What changed in the phase 1 view after phase 2

- School D gains its cheapest rung (CRAP, S-2) and its most expensive (proof, S-8); the operator's
  sources sit mostly in D and in measurement.
- S-14 joins C and D through one mechanism the survey lacked: rolling a gate out by mode inside an
  agent team.
- No source added a school.

## 4. Synthesis

### Criteria

- **Research criteria:** measured effect, cost per change, reversibility, fit with the kit's
  decision records, and time to a first demoable slice.
- **Operator's criteria:** measurement first, because without a replay every other harness change
  is an opinion (operator, 2026-11-27) — the same call D-02 made. Phase 3 adds the criteria the
  operator's questions reveal.

### Comparison against the kit

| Practice | School | Kit today [inference] | Verdict | Sources |
|---|---|---|---|---|
| Review replay on past outcomes, per-stage recall, repeat trials | Measurement | Outcomes recorded, no replay | **Adopt** | S-14, S-7, S-33, S-53 |
| One tuned reviewer vs a stacked verifier | Measurement | Stacked (PRD-13) | **Test** with the replay | S-14 |
| Mutation and CRAP on the diff as review evidence | D | Stryker on demand, not evidence | **Adapt** | S-2, S-4, S-25, S-26, S-28 |
| Property and differential test tiers | D | Not in the test-tier vocabulary | **Adapt** | S-14, S-9, S-29, S-30 |
| Tests the implementing agent cannot edit | D | Approved acceptance tests are held (ADR-0046); other tests are not | **Adapt** | S-55 |
| Gate modes off / observe / enforce, two-block escape | C | Guards are on or off | **Adopt** | S-14, S-36 |
| Per-commit verification stamp, "none" included | C | Check table in the PR body | **Adapt** | S-14 |
| Fail-closed required checks | C | `root-guard.sh` fails open on purpose | **Open** — settle per guard through observe mode | S-16, S-38, D-02/S-33 |
| Idempotency key and reconcile before a retry | E | Duplicate-refusing events; no general reconcile | **Adapt** | S-15, S-23, S-41 |
| One retry layer, a retry budget, a propagated deadline | E | Third-failure stop; no budget | **Adapt** | S-42 |
| Progress file and commits as recovery points | E | Commits per slice; the diary | Confirmed in part | S-44 |
| Versioned agent definitions | E | Skills edited in place; spawn line names the skill only | **Adapt** — a content hash per spawn | S-15, S-23, D-02/S-1 |
| Missing usage is unknown, not zero | E | `session.usage outcome=fail` events seen today | **Adapt** — count the holes before trusting cost | S-19, S-20 |
| Per-run token and time budgets | E | Session cap, third-failure stop | **Adapt** | S-15, S-6, D-02/S-17 |
| Stop-hook completion gate | C | None | **Adapt** | S-38, D-02/S-17 |
| Stable cached prefix, small always-loaded context | B | 350-line root manual, re-read every request | **Measure** — cache hit rate and manual size | S-46, S-47, S-48, S-50 |
| Tool and output shaping (caps, concise modes) | B | Restricted reviewer tools; return shapes | Confirmed in part | S-32, S-49 |
| Provenance-tracking control plane | C | Restricted readers and declared return shapes | **Later** | S-39, S-40 |
| Incident-backed diff triggers | D | Path-based lens slicing | **Later** — needs incidents | S-14 |
| Formal proof as a gate | D | None | **Later**, consumer-optional | S-8 to S-13 |
| Thin loop for writes | A | Rejected | **Reject** | S-55 |
| Topology record | C | ADR-0009 covers one cell | **Later** (carried from D-02) | D-02/S-4, D-02/S-30 |

## 5. Open questions

1. **Which PRs seed the replay?** K1's reverts and fixes are few; S-14 also uses a size-matched
   clean control and maintainer-rejected changes. Is that enough to tune without overfitting?
2. **Does the replay judge with a model?** Sashiko's judge and S-14's one-sentence answer key are
   both LLM-matched; the judge then needs its own validation (D-02/S-26).
3. **How many repeat trials can the kit afford?** pass^k needs several runs per case (S-33); each
   review costs real tokens. Not tried: no cost per review read from the trace yet.
4. **Mutation on POSIX sh:** no tool read here covers it. Node validators only, or a sh mutator?
5. **Where does the verification stamp live** — a commit trailer, the trace, or both?
6. **How much does the root manual cost per session, and is its prefix cache-stable?** Not tried:
   the trace's usage events would answer it once their holes are counted.

## 6. Red flags and unread sources

**Text addressed to agents, none followed:**
- `theorem-labs/oss-verify` README: "A coding agent starts at [AGENTS.md](AGENTS.md)", with a
  prompt to enroll the project. Not fetched, not followed.
- `sashiko` CONTRIBUTING: "Contributors and coding agents are required to act on every finding
  reported by `sashiko-bot`" — project policy, not an attack.
- Harmonic: an "Ask an AI about this page" share widget.
- S-29's appendix carries the study's own agent prompt (seen through a summary only); study
  material, not followed.
- METR (D-02/S-20): the dataset canary again.

**Commercial framing:** S-10 to S-13 sell verification; S-8 is co-written with Theorem (S-12);
S-43 is Temporal's own post; S-48 is Manus's; S-14, S-8, S-44, S-46, S-49 and S-50 come from
Anthropic, whose model this session runs on. Weighed as bias.

**Conflicting figures:** D-02/S-12 cites Harness-Bench as "52.4 to 76.2 on 106 tasks"; the paper's
HTML gives neither figure, reports 274 general tasks, and its own abstract page says 106 tasks while
the body says 300 (S-35). §1 uses the body's figures.

**Unread or partly read:**
- S-5: HTTP 403.
- S-27 (QuickCheck): the PDF came back as binary with no text.
- S-51 (Sutton, "The Bitter Lesson"): a self-signed certificate.
- S-26: abstract only; its PDF was not extractable.
- S-45: the URL served LangGraph's "Persistence" page, not durable execution.
- S-8's appendix PDF: text not extractable.
- `theorem-labs/xv6iris`: HTTP 404.
- Partly through a summary rather than verbatim: S-29, S-30, S-31, S-32, S-33, S-35, S-36, S-37,
  S-38, S-39, S-40, S-42, S-47, S-50, S-52, S-53, S-55; D-02/S-26 abstract only; the second half of
  D-02/S-17, D-02/S-24 and D-02/S-32.
