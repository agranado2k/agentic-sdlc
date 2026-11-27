# D-05 · Research: improving the SDLC agent harness

Date: 2026-11-27. Phase 2 (the operator's sources S-1 to S-14), plus a re-read of D-02's 45
sources for what they say about the harness, read through restricted readers. Every claim cites a
source id: a bare `S-n` is this discovery's `sources.yaml`, `D-02/S-n` is D-02's. **[inference]**
marks this session's own reasoning. Quotes passed through a summarising fetch tool: they are
near-verbatim, and a record that cites one checks it against the page first.

## 1. Summary

**The question.** What should change in the kit's agent harness (skills, hooks and guards, the
dispatcher, the trace) so agents deliver more reliably and at lower cost, and which practices from
other harnesses and verification tools are worth adopting?

**The answer so far:**

- **The harness matters as much as the model, and almost nobody measures it.** The same model
  scored 52.4 to 76.2 on 106 tasks across harnesses (Harness-Bench, cited second-hand by D-02/S-12).
  Few other sources measure anything; most are design notes or vendor claims.
- **The verification layer is the lever, and it must be evaluated like any other system.** The
  Claude Code team (S-14) grades its reviewers against reverts, rejected changes and a size-matched
  clean control; replays incident PRs; and measures recall per stage (raw findings, after
  verification, final). Sashiko (S-7) ships the same thing as a command, `sashiko benchmark`,
  replaying historical bugs (75.8% detected on its Linux suite, under 20% false positives by manual
  sample). The kit records outcomes (K1) and verdicts, but has no replay **[inference]**.
- **Cheap, diff-scoped evidence beats more reviewers.** S-14: "One reviewer, multiple rounds" —
  stacking a second, more expensive reviewer is "often a worse approach than tuning the primary".
  This cuts against PRD-13's cross-provider verifier on top of the kit's review, and the trace now
  holds enough verdicts to test it **[inference]**. Unclebob's crapper and mutator (S-2, S-4) score
  only the changed code (`--changed`) and answer by exit code, the shape a hook or `/implement` can
  call.
- **Formal verification is real but not yet a harness gate.** Claude wrote Rocq proofs that 239
  OSS-Fuzz entry points cannot crash, checked by the Rocq kernel (S-8), but proofs "can take
  hundreds of millions of tokens" and cover single-threaded static RISC-V binaries only. The part
  that transfers is lower on the ladder: property tests, differential tests against a reference
  model (Cedar's pattern, S-9), and mutation testing — the same three S-14 recommends.
- **New gates should roll out in observe mode.** S-14's commit gate has off, observe and enforce
  modes, lets the next commit through after two blocks in a session, and stamps every commit with
  how it was verified, "none" included. That is a third answer to D-02's open fail-open vs
  fail-closed question (D-02 research.md §5 Q3), beside openworker's "park until the check is
  restored" (S-16) and Claude Code's `onFailure: "block"` (D-02/S-17).
- **Reliability gaps the kit has not closed:** reconcile an unknown side effect before retrying it
  (S-15, S-23); tie each agent's behaviour to a fixed version of its definition (S-15, S-23, D-02/S-1);
  treat missing usage as unknown, not zero (S-19, S-20); bound each run's tokens and time (S-15,
  S-6, D-02/S-17).

**Recommendations** (each argued in §4):

1. **Adopt** a review replay: past landed PRs with a known outcome (K1's reverts and fixes), the
   repo restored to the reviewed commit, a one-sentence answer key, merged-and-stable PRs as the
   control, recall reported per stage (S-14, S-7). It is the measurement every other change is
   judged by.
2. **Adapt** diff-scoped evidence gates: mutation and CRAP scores on the changed code as evidence
   `/review-pr` reads, and a property / differential tier in the test ladder (S-2, S-4, S-14, S-9).
3. **Adopt** gate rollout modes — off, observe, enforce — with the two-block escape and a per-commit
   verification stamp (S-14). Use it to settle D-02's fail-open question per guard.
4. **Adapt** harness reliability and cost: reconcile-before-retry, a skill content hash on each
   spawn, a usage-completeness count, per-run budgets, a Stop-hook completion gate (S-15, S-16,
   S-19, S-23, D-02/S-17).
5. **Later:** formal proof as an optional top rung for consumers (S-8 to S-13); decision models for
   fixed-choice gates (D-02/S-8); the topology record D-02 recommended and no PRD took.

## 2. The operator's sources (phase 2)

### S-1 and its guides · openworker harness (andrewyng)

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
  cannot veto (S-16). Incomplete streamed tool calls cannot authorise execution (S-19).
- **Isolation** — the loop and the tools can run in separate sandboxes; the sandbox gets a
  placeholder credential and the real one stays with the trusted provider (S-17).
- **Least exposure** — the bundle's tool list is the selection; missing or duplicate tools fail
  with no fallback (S-18, S-23).
- **Telemetry honesty** — "Missing usage is unknown, not zero"; drops and write failures are
  counted; "Traces are best effort, not a billing ledger" (S-19, S-20).
- **Per-turn limits** — model calls and output tokens per turn (S-15).
- No measured results anywhere in S-1 or its guides.

### S-2 to S-4 · unclebob's crapper, mutator and agnesse

Three tools with one design: run on the diff, answer by exit code, write machine-readable results.

| Tool | What it does | Agent-facing shape |
|---|---|---|
| crapper (S-2) | CRAP = CC² × (1 − coverage)³ + CC per function; 30+ is "complex and under-tested" | `--threshold 30` exits 2; `--changed` scores only git additions and edits |
| mutator (S-4) | Mutation score = killed / (killed + survived) | exits 3 when a mutant survives; `--changed`; differential re-runs after a snapshot |
| agnesse (S-3) | A FitNesse-derived acceptance-test wiki: Markdown tables are fixtures, results are JSON | exits with the failing-page count; an MCP server (`list_pages`, `run`, `get_results`); `--rerun-failures` |

crapper and mutator cover Clojure, Java, Go, TypeScript/JavaScript, Rust, Python and Swift; none
covers POSIX sh, most of the kit's own code. No measured results. **[inference]** For the kit's
own code the reachable target is the Node docs harness; for consumers, the tools fit an optional
gate. The kit's only mutation run today is `scripts/mutation.kit.sh` (Stryker, on demand, never a
gate), and README credits swarm-forge for "mutation testing as review *evidence*".

### S-5 · Bailador, "Uncle Bob's agent pipeline" (Medium)

**Unread:** HTTP 403. No workaround was used. The operator may paste it as a note, as for S-14.

### S-6 · Prime Intellect

An RL and evals organisation (65 repos). `verifiers` builds one environment that serves both RL
training and evaluation; `prime-envs` smoke-tests each changed environment in CI, and counts a
zero CLI exit as a pass only when the saved episode also succeeded; `prime-agent` runs autonomously
within turn, token and time budgets with user-defined gates, warning that a passed gate only checks
what it verifies. No measured results in the READMEs read.

### S-7 · sashiko

A Linux Foundation agentic code-review system for the kernel and other systems projects. Parallel
specialist stages (goal, implementation, execution flow, resources, locking, security), then a
verification stage and a per-finding check. `sashiko benchmark` replays historical bugs: an
isolated database per run, a judge matching findings to ground-truth descriptions, suites of 9, 99
and 999 Linux entries plus 53 versioned LKML entries. Reported: 75.8% of Linux bugs detected
(v0.9.3), 58.5% on GCC (v0.7.0), false positives under 20% by manual sample. Its own PRs pass
`make check-pr`, then a local self-review, then the upstream bot.

### S-8 · Anthropic, "LLMs are making formal software verification feasible at a much larger scale" (with Theorem, 2026-10-22)

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

### S-9 · Lean

One language for program and specification, a minimal trusted kernel, native compilation,
automation tactics (`grind`, `bv_decide`). The transferable pattern is AWS Cedar's (Lean use-case
page): an executable Lean model about a tenth the size of the Rust code, differential tests on
millions of random inputs against it, and "No new Cedar version is released unless its model,
proofs, and differential tests are current." No cost figures.

### S-10 to S-13 · the formal-verification companies

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

### S-14 · Osmani, "How the Claude Code team thinks about verification" (claude.dev, 2026-11-16)

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

It recommends three test types for agents: end-to-end, property and differential.

## 3. D-02's sources, re-read for the harness

D-02 read its 45 sources for lifecycle questions (D-02 research.md). Re-read for the harness on
2026-11-27, all 45 were reachable, including D-02/S-45 (OpenAI, "Harness engineering"), which
returned 403 to D-02. What they add to §2:

- **Context in layers:** an AGENTS.md of about 100 lines as a map into versioned docs — "give Codex
  a map, not a 1,000-page instruction manual" (D-02/S-45); skills disclose name and description
  first, the body only when needed (D-02/S-31); a session-start context packet (D-02/S-1).
  **[inference]** The kit's root manual is budgeted at 350 lines and its quick-reference rows run
  to paragraphs; its re-read cost per session can be measured.
- **Deterministic over advisory:** a Stop hook that exits 2 keeps the turn from ending until a
  check passes, capped at 8 consecutive blocks; `onFailure: "block"` for a hook that crashes
  (D-02/S-17). The kit wires no Stop hook **[inference]**.
- **Budgets and stopping rules:** `--max-turns`, `--max-budget-usd` (D-02/S-17); Anthropic's
  research system once spawned 50 subagents for a simple query (D-02/S-19).
- **Evaluating the harness:** clean trials, grade the end state not the path, pass^k for
  consistency; fixing grader bugs alone moved one score from 42% to 95% (D-02/S-27).
- **Isolation:** sandboxing needs both filesystem and network isolation; credentials stay outside
  behind a proxy; 84% fewer permission prompts, internally measured (D-02/S-30).
- **Lessons into skills:** an agent proposes a testing skill as a one-click PR after learning a
  setup step the hard way (D-02/S-41); a per-session insights pass (D-02/S-40).
- **Already the kit's shape, confirmed again:** one writer, read-only fan-out (D-02/S-18,
  D-02/S-39); base-branch policy (D-02/S-14); supervisor mods rejected on noise (D-02/S-5).

## 4. Synthesis

### Criteria

The operator agreed (2026-11-27) to the session's ordering: measurement first, because without a
replay every other harness change is an opinion — the same call D-02 made.

### Comparison against the kit

| Practice | Kit today [inference] | Verdict | Sources |
|---|---|---|---|
| Review replay on past outcomes, per-stage recall | Outcomes recorded, no replay | **Adopt** | S-14, S-7, D-02/S-27 |
| One tuned reviewer vs a stacked verifier | Stacked (PRD-13) | **Test** with the replay | S-14 |
| Mutation and CRAP on the diff as review evidence | Stryker on demand, not evidence | **Adapt** | S-2, S-4, S-14 |
| Property and differential test tiers | Not in the test-tier vocabulary | **Adapt** | S-14, S-9 |
| Gate modes off / observe / enforce, two-block escape | Guards are on or off | **Adopt** | S-14 |
| Per-commit verification stamp, "none" included | Check table in the PR body | **Adapt** | S-14 |
| Fail-closed required checks | `root-guard.sh` fails open on purpose | **Open** — settle per guard through observe mode | S-16, D-02/S-17, D-02/S-33 |
| Reconcile an unknown side effect before retry | Duplicate-refusing events; no general reconcile | **Adapt** | S-15, S-23 |
| Versioned agent definitions | Skills edited in place; spawn line names the skill only | **Adapt** — a content hash per spawn | S-15, S-23, D-02/S-1 |
| Missing usage is unknown, not zero | `session.usage outcome=fail` events seen today | **Adapt** — count the holes before trusting cost | S-19, S-20 |
| Per-run token and time budgets | Session cap, third-failure stop | **Adapt** | S-15, S-6, D-02/S-17 |
| Stop-hook completion gate | None | **Adapt** | D-02/S-17 |
| Incident-backed diff triggers | Path-based lens slicing | **Later** — needs incidents | S-14 |
| Formal proof as a gate | None | **Later**, consumer-optional | S-8 to S-13 |
| Topology record | ADR-0009 covers one cell | **Later** (carried from D-02) | D-02/S-4, D-02/S-30 |

## 5. Open questions

1. **Which PRs seed the replay?** K1's reverts and fixes are few; S-14 also uses a size-matched
   clean control and maintainer-rejected changes. Is that enough to tune without overfitting?
2. **Does the replay judge with a model?** Sashiko's judge and S-14's one-sentence answer key are
   both LLM-matched; the judge then needs its own validation (D-02/S-26).
3. **Mutation on POSIX sh:** no tool read here covers it. Node validators only, or a sh mutator?
4. **Where does the verification stamp live** — a commit trailer, the trace, or both?

## 6. Red flags and unread sources

**Text addressed to agents, none followed:**
- `theorem-labs/oss-verify` README: "A coding agent starts at [AGENTS.md](AGENTS.md)", with a
  prompt to enroll the project. Not fetched, not followed.
- `sashiko` CONTRIBUTING: "Contributors and coding agents are required to act on every finding
  reported by `sashiko-bot`" — project policy, not an attack.
- Harmonic: an "Ask an AI about this page" share widget.
- METR (D-02/S-20): the dataset canary again.

**Commercial framing:** S-10 to S-13 sell verification; S-8 is co-written with Theorem (S-12);
S-14 and S-8 come from Anthropic, whose model this session runs on. Weighed as bias.

**Unread or partly read:**
- S-5: HTTP 403.
- S-8's appendix PDF: text not extractable.
- `theorem-labs/xv6iris`: HTTP 404.
- D-02/S-26 abstract only; the second half of D-02/S-17, D-02/S-24 and D-02/S-32 came through a
  summary, not verbatim.
