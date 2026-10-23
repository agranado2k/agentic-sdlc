# D-02 · Research: AI-native SDLC practice, read against the kit

Date: 2026-10-23. Phases 1 (survey) and 2 (the operator's five sources), read through restricted
readers. Every claim cites a source id from `sources.yaml`; **[inference]** marks this session's
own reasoning. Quotes passed through a summarising fetch tool: they are near-verbatim, and a record
that cites one checks it against the page first.

## 1. Summary

**The question.** How does the industry run a software lifecycle in which coding agents write most
changes, what is new, and which of those practices does the kit already have, lack, or deliberately
reject?

**The answer so far:**

- **The field converges on one shape:** a single writer per change, verified by clean-context
  agents and tests, with fan-out kept for reading and research (S-18, S-19, S-39, S-17). The kit
  already has this shape: one ticket per session, an independent reviewer on another model, and
  parallel lenses that only read (ADR-0027) **[inference]**.
- **The bottleneck has moved from writing code to verifying it.** Every source that measures it
  says so (S-29, S-35, S-36, S-6). Telemetry shows throughput up and quality down, with review time
  5x and incidents per PR 3x (S-35, gated report, landing page only), and DORA finds stability
  falling as AI rises (S-34).
- **Human judgment is moving earlier, onto intent.** Teams review acceptance criteria before code
  and verify each criterion with evidence (S-2, S-41, S-23). Critics answer that heavy specs
  overload review and give false control (S-22). The kit sits between the two: `/grill-me` and
  `/to-prd` review intent before code, and the behavior confirm-list is read after it
  **[inference]**.
- **Automated judges must be validated like classifiers.** That means precision and recall against
  human labels, a floor chosen from the consequences, and a check on calibration (S-3, S-24, S-27).
  Judges inherit the flaws of what they judge (S-26), and all six automated systems tested missed
  failures that "looked correct" (S-7). The kit's review lenses are judges, and their precision has
  never been measured **[inference]**. This session's retro found one lens false positive recurring
  on five PRs (retro 20261023T103804Z, R1).
- **Recurring review findings should become machine-enforced rules.** S-2 calls them invariants;
  S-42 and S-1 make the same move. The kit already holds this principle ("a rule with no failing
  check is a claim", `/retro` → `/to-tickets`) **[inference]**. What it lacks is the mining step that
  ranks findings by frequency (S-2).
- **The harness is now a policy plane, and policy must fail safely.** Hooks are layered from
  enterprise down to user and support `failClosed` (S-32). A fail-open policy hook let `git push`
  and `rm -rf` through (S-33). Mods can approve a tool call past settings hooks unless the settings
  are managed (S-9).
- **Where an agent runs is a security decision.** VMs are the gold standard and worktrees isolate
  only git state (S-4, S-11). Sandboxing cut permission prompts by 84% (S-30).
- **Measurement is unreliable.** METR's RCT design broke once every developer used AI (S-20, S-21,
  S-43), and the claimed gains come from vendors (S-40, S-2).

**Recommendations** (each one is argued in §4):

1. **Adapt** S-3's judge validation to the review lenses. Measure each lens's precision against
   the triage outcomes the trace already holds, and give each lens a floor (S-3, S-24, S-27). First
   settle open question 1: who labels.
2. **Adopt** S-14's base-branch rule for the kit's policy files. A PR that edits a guard, lens or
   vocabulary policy is judged by main's version, and fails closed to a human (S-14).
3. **Adapt** S-2's per-criterion verdict. The behavior confirm-list gains one line per `Covers:`
   requirement, each with its demo evidence (S-2, S-41, S-6).
4. **Adapt** stability into `/retro`'s flow section, alongside the throughput it already measures:
   reverts, and fixes landed after a merge (S-34, S-35).
5. **Adapt** a topology record: one decision record stating where each agent's model, loop and
   tools run, which isolation applies, and where credentials sit (S-4, S-11, S-28, S-30).
6. **Reject** for now:
   - per-turn supervisors (noise and cost; S-5, S-13);
   - mods as the kit's guard mechanism (one vendor's harness, unsandboxed; S-9);
   - ship-and-revert in place of a human merge (shared invariant §7; S-6, S-14).

## 2. Landscape (phase 1)

### Schools of practice

| School | Idea | Fits | Costs | Who | Sources |
|---|---|---|---|---|---|
| **A · Spec-driven pipeline** | A human-approved spec, then a plan and tasks; agents implement; humans review artifacts at each gate | Greenfield and bounded features | Markdown review load, false control, specs drift | GitHub spec-kit, Kiro, Tessl; Anthropic's interview-to-SPEC step | S-22, S-23, S-17, S-26 |
| **B · Harness engineering** | Engineers build the agent's environment (knowledge base, linters, structural tests, hooks, skills, cleanup agents), and every struggle becomes a repo rule | Agent-first codebases with low entropy | Ongoing maintenance, hooks that fail open, bloated instruction files | OpenAI Codex team (via S-42, S-44), Anthropic, Cursor | S-17, S-31, S-32, S-33, S-42, S-1 |
| **C · Single writer, independent verifiers** | One agent writes; clean-context reviewers, tests, stop hooks and behavior evidence verify; humans read the evidence | The consensus default for writes | Reviewers over-report; review time still rises; behavior evidence costs VM time | Cognition (Devin Review), Anthropic writer/reviewer, Google conditional LGTM | S-17, S-36, S-39, S-40, S-41 |
| **D · Orchestrator fan-out** | A lead splits the work across isolated parallel workers, then synthesizes | Research, broad reads, independent tickets | About 15x chat tokens; review throughput caps landing; writers' implicit decisions conflict | Anthropic research and `/batch`, Devin managing Devins | S-17, S-18, S-19, S-29, S-39 |
| **E · Eval-driven improvement** | Read traces, build a failure taxonomy, use binary judges calibrated against an expert; capability evals graduate into regression evals; fixes go back into rules | Any pipeline with LLM decision points | Expert labeling time; judges inherit model flaws; criteria drift | Husain's clients, Anthropic, EvalGen | S-24, S-25, S-26, S-27, S-3, S-7 |

The operator's sources add a sixth school, which the survey did not name:

| School | Idea | Fits | Costs | Who | Sources |
|---|---|---|---|---|---|
| **F · Attention interface** | The harness turns to face the human: user-programmable middleware decides when to interrupt, what to show and what to ask | One operator's synchronous session | Noise (99 of 111 turns), tokens, unsandboxed extensions, vendor lock-in | Claude Code mods, ModSmith | S-5, S-9, S-12, S-13 |

**Where the kit sits [inference]:** it is a deliberate blend of schools A, B, C and E.
- **A:** `/grill-me` → `/to-prd` → `/to-tickets`.
- **B:** skills, the docs gate, guards, and `/retro` → rules.
- **C:** `/implement` plus an independent `/review-pr` on another model (ADR-0027).
- **E, in part:** `/retro` reads the trace with fixed questions, but no judge is validated against labels.
- **D, constrained:** parallel tickets are capped at 3, each in its own worktree. Its first failure mode, conflicting implicit decisions (S-18), is what the VERSION collisions were. `/to-tickets` rule 16 (ADR-0033) answered them.

### Emerging work (last 18 months)

- **Agent Skills as an open standard** (S-31, 2025-12). It is shipping across harnesses, but no
  study measures how well skills work.
- **Hooks as a layered policy plane with fail-closed options** (S-32). It is early: fail-open
  defaults were fixed only in 2026 (S-33).
- **Sandboxing in place of approval prompts** (S-30, one internal metric) and in-process mods
  (S-9, early access).
- **Behavior-evidence verification**, where agents return a test plan with screenshots and video
  (S-41). These are vendor products with self-reported numbers.
- **The narrowed multi-agent consensus:** single-threaded writes, map-reduce reads (S-39, 2026-04).
- **Population-scale studies of agent PRs** (S-37, S-38). Agent PRs are rejected for reasons human
  PRs are not, distrust among them, and 67.9% of rejections carry no explicit feedback.
- **Decision models**, cheap calibrated classifiers for fixed-choice gates (S-3, S-8).
- **The measurement crisis:** RCTs no longer work, so the evidence now comes from telemetry and
  surveys, which are correlational (S-21, S-34, S-35).

## 3. The operator's sources (phase 2)

### S-1 · Tenex, "Building an AI-Native SDLC" — school B (with A)
- **Claims:**
  - Context as code: one versioned record beside the code, split into truth, intent and history.
  - A "fence rule": the tool rewrites only machine-owned fenced blocks.
  - Status is derived from the record, never reported: "No field for health exists."
  - "Done" is gated on linked evidence (a PR, tests or a sign-off).
  - Skills are versioned and tested like software (more than 50 of them).
  - Each project improves the system that runs the next one.
- **Evidence:** a description of the firm's own repository, with no outcome data. It is a
  consultancy (S-1).
- **Agrees with:**
  - the kit's diary, ADRs and trace (truth, intent, history);
  - tracer-bullet checkpoints;
  - skills with suites;
  - `/retro` → rules [inference].
- **Adds:**
  - views derived for three audiences;
  - plan-then-apply for tracker writes, refusing an ambiguous match;
  - a planning-readiness measure ("where the plan runs out");
  - a startup context packet injected by hooks.
- **Leaves out:** review, merge authority, model choice and measured outcomes.

### S-2 · Tessl / Aviator, "We stopped reviewing code and started verifying intent" — school A/C
- **Claims:**
  - Review intent before generation.
  - Each acceptance criterion becomes a contract with a deterministic verdict and attached evidence,
    so the reviewer reads about five verdicts instead of a 500-line diff.
  - Mine the last 1,000 review comments and take the top 20 repeats as the first machine-enforced
    invariants.
  - Name an owner for each rule.
  - A five-step model: Argue, Capture, Codify, Debate, Own.
- **Evidence:** one number (4x PR volume). The adoption timeline is asserted, not measured, and the
  author's company sells review tooling.
- **Its one-hop reference S-6** adds: path-based escalation (auth, schema, dependencies);
  parallel candidate implementations ranked by verification; and "ask it to write a script that
  verifies".
- **Agrees with:**
  - `/grill-me` and `/to-prd` before code;
  - the confirm-list kept for the human;
  - hard rule 9 [inference].
- **Adds:**
  - a per-criterion verdict with evidence (the kit's confirm-list is a list for a human to read,
    not a verdict per criterion);
  - a frequency-ranked mining pipeline from review findings to rules;
  - named rule owners.
- **Rejected part:** S-6's ship-and-revert in place of an approval gate conflicts with shared
  invariant §7.
- **Leaves out:** design-level problems that invariants miss, retiring a rule, and the cost of
  false positives.

### S-3 · Husain & Saha, "How To Use Decision Models for Evals" — school E
- **Claims:**
  - A judge is a classifier.
  - Choose a precision and recall floor from the consequences (80/80 for alerting), tune each
    threshold by stratified 5-fold cross-validation before comparing, and plot F1 against cost on a
    Pareto frontier.
  - Check calibration (reliability bins, Platt scaling, Brier score).
  - Build one judge per failure mode. Start with a large model and test smaller ones against it.
  - Hold out a test set before optimising prompts, because wrong labels steer the search.
- **Evidence:** 98 traces from one product, with published data files. The authors call it a
  method demonstration, not a ranking.
- **One-hop references:**
  - S-7: automated error analysis reached 74–87% recall, and every system missed failures that
    "looked correct" against the product goal.
  - S-8: decision models match LLMs on routing and safety at 5–6x lower cost, but trail them on
    reasoning.
- **Agrees with:**
  - the kit's binary, vocabulary-checked verdict lines;
  - tier → model as data with a cheap-first cascade ("start large, test smaller against it")
    [inference].
- **Adds:**
  - per-lens precision and recall against human labels, with a floor per lens (recall for
    security, precision for nits);
  - calibration of severity;
  - a held-out set before tuning a skill prompt.
- **Supports:** S-7 backs the kit's split, standards to agents and behavior to a human: the
  "looks right, wrong goal" class is what automated judges miss [inference].
- **Leaves out:** judging diffs (it judges traces of a product), and confidence intervals.

### S-4 · Zeyliger, "The Topology of an LLM Agent Loop With Tool Use" — school B (systems side)
- **Claims:**
  - An agent is a model, a loop and tools, and where each runs decides privacy, cost, capability
    and blast radius.
  - VMs are the gold standard for running tools. The ladder runs microVM → gVisor → WASM →
    read-only SQL (S-11).
  - Map where credentials live.
  - Keep durable history in a real store.
  - Narrow bespoke loops (alerts, deploy supervisor) beat one general loop.
- **Evidence:** descriptive, with nothing measured. The author sells VMs.
- **One-hop reference S-10:** cross-model adversarial review, agent-supervised deploys that can
  halt, and a merge queue under 3 minutes.
- **Agrees with:**
  - the trifecta model and delegated untrusted reads (S-28);
  - model mapping as data;
  - review by a different model (ADR-0027);
  - the append-only trace [inference].
- **Adds:**
  - an explicit topology record (ADR-0009 covers one cell: a reviewer with no network);
  - isolation matched to the job (worktrees isolate git state, not execution);
  - a post-merge supervisor [inference].
- **Leaves out:** multi-agent coordination, review and merge.

### S-5 · McAteer, "Claude Mods: Flipping the Harness Inside Out" — school F
- **Claims:**
  - Mods are in-process middleware that let the harness face the human.
  - A side agent caught about 45 files of uncommitted work that a discard would have lost.
  - A next-steps supervisor fired on 99 of 111 turns, at about 5–6k tokens per check.
  - Mods are not sandboxed.
  - The best case is a harness that proposes its own improvements from real use.
- **Evidence:** one practitioner's experience. Cost figures come from the author's README
  estimates (S-13).
- **One-hop references:**
  - S-9: a mod's approval can pass a tool call that settings hooks would hold, unless the settings
    are managed.
  - S-14: a PR that edits a policy file is judged by the base branch's version, failing closed;
    only exact basenames are trusted.
  - S-12: the "attention policy" every harness will ship, learned from corrections.
- **Agrees with:**
  - the confirm-list and the autonomy label as a declared attention policy;
  - `/retro` reading the trace for repeated friction, though the kit routes fixes to tickets,
    never to self-modification [inference].
- **Adds:**
  - S-14's base-branch rule;
  - a measured interruption rate as a budget beside spend;
  - pricing an automation before adopting it;
  - a trust review for harness extensions alongside `scripts/catalogue.sh`.
- **Risk to the kit:** in a consumer that installs mods without managed settings, the kit's
  PreToolUse guards can be overridden by a mod's approval (S-9) [inference].
- **Leaves out:** teams, review and merge.

**What changed in the phase-1 view:**
- S-5 adds school F.
- S-3 and S-7 move school E from "a practice for product teams" to "a direct test for the kit's own
  review lenses".
- S-2 and S-6 sharpen school A's open dispute (S-22) into a concrete proposal: verdicts per
  criterion.

## 4. Synthesis

### Criteria (research)
Complexity added; reversibility; cost per wave; fit with the binding decision records (shared
invariant §7, ADR-0008 the trace read only by `/retro`, ADR-0009, ADR-0025, ADR-0027); and the time
until a first slice can be demonstrated.

### Operator's criteria
- **Accuracy, with the human pulled in only for high risk** (operator, 2026-10-23). An option scores
  on how precise its automated verdicts are, and on how rarely it asks the human for anything that
  is not high risk. [inference] This reads S-3's precision floor and S-6's path-based escalation as
  one criterion: a judge accurate enough to be trusted on low risk, and a risk rule that decides
  when the human is asked.
- **Order of value: measurement first, then guard safety, then policy safety** (operator,
  2026-10-23).
- **Labels come from post-merge outcomes** (operator, 2026-10-23), not from the session's own
  rulings. [inference] So a lens finding is judged against what happened after landing (a revert, a
  fix that touched the flagged line), which the trace does not yet record (§5 Q6).

### Comparison against the kit

| Practice | School | Kit today [inference] | Verdict | Reason |
|---|---|---|---|---|
| Single writer, independent verifier on another model | C | Has it (ADR-0027) | Confirmed | S-18, S-39, S-10 |
| Parallel workers only on independent tickets | D | Cap 3, rule 16 (ADR-0033) | Confirmed | S-18, S-19 |
| Intent reviewed before code | A | `/grill-me`, `/to-prd`, `Covers:` | Confirmed | S-2, S-23 |
| Per-criterion verdict with evidence | A/C | The confirm-list is read by a human; demo evidence sits in the PR body | **Adapt** | S-2, S-41, S-6. The kit's `Covers:` ids make each criterion addressable. |
| Lens precision against labels, floor per lens | E | Retro Q2 counts rejections; no floor, no labels | **Adapt** | S-3, S-24, S-27, S-26; the retro's R1 false positive recurred on 5 PRs |
| Review findings mined into rules by frequency | B/E | `/retro` → `/to-tickets`, unranked | **Adapt** | S-2, S-42, S-25 |
| Policy files judged by the base branch | — | CI runs the PR's own tree (`kit-guards.yml` checks out the PR) | **Adopt** | S-14; a PR could loosen the rule that judges it |
| Fail-closed policy hooks | B | `root-guard.sh` fails open on purpose (its header: a guard that blocks on a parse failure "would brick the session") | **Open** | S-33 against the kit's recorded trade-off; see §5 Q3 |
| Stability beside throughput | — | Flow section: lead time, review wait, toil | **Adapt** | S-34, S-35 |
| Topology and isolation record | B | ADR-0009 covers one cell; worktrees only | **Adapt** | S-4, S-11, S-28, S-30 |
| Path-based escalation (auth, schema, deps) | A/C | Autonomy label at write time; `BEHAVIOR_DELTA_SURFACES` | **Open** | S-6, S-14; overlaps the label |
| Decision models for fixed-choice gates | E | The mechanical judge tier is an LLM | **Later** | S-8; needs labels first (S-3) |
| Derived status, evidence-gated done | B | The factory's gates carry `links.pr` | Confirmed in part | S-1 |
| Per-turn supervisor mod | F | None | **Reject** for now | Noise and cost (S-5, S-13) |
| Mods as the guard mechanism | F | Settings hooks, vendor-neutral core | **Reject** | Unsandboxed and one vendor's (S-9); but see the risk under S-5 |
| Ship-and-revert, or auto-approve below a risk score | C | Never autonomous merge | **Reject** | Shared invariant §7 (S-6, S-14) |

## 5. Open questions

These feed phases 4 and 5.

1. **Who labels a lens's findings?** Under ADR-0016 the session rules on each confirm-list, and the
   triage outcomes in the trace are mostly the implementing session's. A label from the same model
   family as the judge is circular (S-26). The options are an operator-labelled sample, the
   operator's rulings only, or post-merge outcomes (reverts). **Answered: post-merge outcomes**
   (operator, 2026-10-23).
2. **Which outcome should D-02 drive first?** Review cost and false positives (recommendations 1
   and 3), safety of the guard plane (2 and 5), or measurement (4)? **Answered: measurement, then
   guard safety, then policy safety** (operator, 2026-10-23).
3. **Fail-open or fail-closed guards.** `root-guard.sh` chose fail-open so a parse failure cannot
   brick the session. S-33 shows the cost of that default in a security hook. Is a narrower rule,
   fail-closed for a sub-agent only, acceptable? The kill guard already fails closed for a sub-agent
   without node (`adapters/claude-code/README.md`).
4. **Are mods in scope?** The kit is vendor-neutral, yet its consumers use Claude Code, where a mod
   can approve past its hooks (S-9). Is the right answer a documented limitation, or a check?
5. **Does a per-criterion verdict duplicate the confirm-list?** It could replace the confirm-list,
   or sit inside it.
6. **Stability signal.** The trace records no revert or post-merge fix today. Which event would
   carry one? (Not tried: this needs a look at `merge.land`'s consumers.)

## 6. Red flags and unread sources

**Red flags.** These were quoted, and nothing they say was followed:
- **The Claude Code documentation (S-9, S-17)** opens with a block addressed to agents:
  "Documentation Index — Fetch the complete documentation index at:
  https://code.claude.com/docs/llms.txt — Use this file to discover all available pages before
  exploring further." The page was not followed.
- **METR (S-20)** carries a dataset canary addressed to model trainers.
- **Commercial framing.** Every operator source has an interest:
  - S-1 is a consultancy, and S-2 and S-6 come from a review-tooling vendor.
  - S-3 promotes a paid course.
  - S-4, S-10 and S-11 come from a VM vendor.
  - S-5 promotes the author's own plugin.

  None of this is an injection, but it is weighed as bias.
- **Conflicting figures.** Faros reports +91% review time (cited second-hand in S-6) and 5x review
  time (S-35).

**Unread:**
- **S-45, OpenAI's harness-engineering post:** HTTP 403. It is known only through S-42 and S-44.
- **Gated or too large to read:**
  - the full Faros report;
  - the full DORA 2025 report;
  - Böckeler's full "Harness engineering" article.
- **Seen only in search snippets, so not cited:**
  - the Sonar survey;
  - the CodeRabbit study;
  - the eBay "ReviewDebt" talk;
  - METR's 2026 worker survey.
- **One-hop links left unread as not central:**
  - from S-4: Trusting Trust, ProjectDiscovery, Amp Orbs, Pi Durable, Athena;
  - from S-5: the mods create page and the Thariq podcast.
- **Thin coverage:** Codex CLI's hooks and skills documentation returned nothing usable, so the
  harness evidence leans on Claude Code and Cursor.
