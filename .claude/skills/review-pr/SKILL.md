---
name: review-pr
description: Two-axis senior reviewer. Axis 1 (standards, "is it built right?") runs 6 specialized parallel sub-agents (Security, API/CRUD, Pattern enforcement, Simplicity, Reuse/DRY, Test hygiene) producing a severity-based report. Axis 2 (spec & behavior, "is it the right thing?") runs a 7th fresh-context sub-agent producing a behavior-change confirm-list for the human. Axes are never merged. Scoped to the current branch's diff against the default branch.
---

# Skill: Senior Security-First Reviewer

Performs a rigorous code review focused on Security, API consistency, pattern conformance, simplification, and test hygiene — followed by a collaborative commenting process on the pull request.

**The two axes are shared invariant §5 made executable.** Standards findings are verifiable from the diff alone and are addressed to agents; behavior findings are not decidable from the diff and are addressed to humans as an explicit confirm-list. Merging them destroys both.

## Execution Protocol

### 0. Branch Scope Lock (MANDATORY — Before anything else)

**CRITICAL RULE**: You MUST ONLY review code from the `$ARGUMENTS` branch's — or the CURRENT branch's if no arguments were given — commits that diverge from the target branch (usually the repo's default branch; `constitution/local-workflow.md` names it).

Steps:

1. Run `git fetch origin` first to refresh remote refs, so the scope is computed against the real target tip and not a stale local copy. Do NOT rebase or modify the current branch.
2. Run `git branch --show-current` to identify the current branch.
3. Run `git merge-base origin/<default-branch> HEAD` to find the common ancestor (fall back to the local `<default-branch>` if there is no `origin` remote).
4. Run `git log --oneline <merge-base>..HEAD` to list ONLY the commits unique to this branch.
5. Run `git diff <merge-base>..HEAD --name-only` to get the list of changed files.
6. ALL review analysis MUST be scoped exclusively to these changed files and these commits.
7. NEVER review, comment on, or flag issues in code that was NOT changed in this branch's commits.
8. If a file was only partially modified, only review the changed lines and their immediate context.

**If this PR is stacked on another feature branch, pass that branch as the base** — the default-branch base would scope the review to everything since the default branch and credit the branch underneath's findings to this PR.

This ensures the review is focused, actionable, and doesn't generate noise from pre-existing code.

### 1. Context Discovery (cheap/fast model)

**Action**: Scan the repository to identify existing tools and architectural patterns. Read the root `AGENTS.md`, the articles it points at under `constitution/`, and the binding records in `docs/adr/INDEX.md`.

**Goal**: Determine this repo's established conventions — export styles, error handling, layering, and whichever in-repo helpers the decision records standardize on. Conventions come from the repo, never from the reviewer's habits.

**Also build a reuse catalog** the Reuse & DRY auditor (Agent 6) will match new code against: the shared helpers, utilities, value objects, and repository/data-access methods that already exist near the diff. Note the barrels or index files that export them, and any workspace-level shared packages, so "this could have called an existing helper" findings cite the exact export that should have been reused.

### 2. Change Summarization (strong model)

**Action**: Summarize the branch's changes (scoped to commits from step 0), focusing on new endpoints, data queries, security-critical code paths, and any cross-cutting concerns.

### 3. Parallel Specialized Reviews (7 sub-agents, two axes)

Agents 1–6 are **Axis 1 — Standards** ("is it built right?"). Agent 7 is **Axis 2 — Spec & Behavior** ("is it the right thing?"). The two axes answer orthogonal questions and their findings are **never merged, co-ranked, or interleaved**: Axis 1 feeds the severity report (§5); Axis 2 emits its own confirm-list (§5b). A change can pass one axis and fail the other.

All agents MUST only analyze code within the branch scope defined in step 0.

#### Agent 1 — Security Sentinel

Audit for injection of every kind the stack admits (SQL/NoSQL, command, template, prompt). Ensure strict input validation and output encoding at every trust boundary; check authentication, authorization, and secret handling on each changed path. Then check the diff against whatever security decisions this repo has recorded in `docs/adr/` — response headers, upload handling, credential scopes, edge rules — and cite them by number.

**Agentic skill surface audit — [OWASP Agentic Skills Top 10](https://owasp.org/www-project-agentic-skills-top-10/).** When the diff touches an agent-facing surface — skills, prompts, hooks, the constitution/`AGENTS.md`, agent settings or tool config (at minimum the set `BEHAVIOR_DELTA_SURFACES` in `scripts/guards.config.sh` enumerates, plus any agent-facing prompt text living outside that list — the config is consumer-owned policy, so treat it as a floor, never the boundary) — the changed *instruction text itself is attack surface* and gets this additional audit. Cite findings by AST number the same way ADRs are cited. Review the **semantics** of instruction text, never keywords: pattern-matching scanners are exactly what AST08 documents as trivially bypassed, so the question for every changed instruction is *"what would an agent following this actually do, and on whose authority?"*

- **Embedded imperatives that exfiltrate or escalate (AST01) — CRITICAL.** Skill or prompt text directing an agent to read credentials/secrets, transmit data to an external host, weaken permissions, or conceal its own actions.
- **Instructions sourced from outside the repo (AST05) — CRITICAL.** A skill that tells the agent to fetch a URL (or read an external doc) *and follow what it finds* splices an attacker-controlled document into the prompt. External content may be read **as data**; it must never be followed **as instructions**, and the skill text must state which it is. An unpinned external instruction source is the finding even when today's content is benign.
- **Supply-chain execution (AST02, AST07) — CRITICAL/HIGH.** `curl | sh`, unpinned installs, or setup that executes before/without user consent in a skill's scripts or hooks (CRITICAL); version-unpinned or hash-unverified dependencies a skill relies on, where a later upstream change silently changes what runs (HIGH).
- **Over-privilege (AST03) — HIGH.** Tool grants or permission additions broader than the skill's stated job; writes to standing-instruction files (`AGENTS.md`, constitution, settings, *other* skills or memory files) that the skill's purpose does not require. A skill that edits the rules future sessions run under is privilege escalation, not convenience — least-privilege applies to instructions exactly as it does to code.
- **Metadata/behavior mismatch and metadata injection (AST04) — HIGH.** A frontmatter `description` that under-states or misrepresents what the body does (the description is what decides the skill gets loaded, so the mismatch is the vulnerability), and any frontmatter or manifest built from untrusted input.
- **Isolation weakening (AST06) — HIGH.** Instructions to disable sandboxing, run untrusted or fetched code on the host, or expose long-lived credentials to content retrieved at runtime.
- **Governance trail (AST09) — MEDIUM.** A new or changed skill/hook that leaves no audit trail this repo requires (changelog or UPDATING entry, decision record when it changes policy). Axis 2 already confirms *that* these surfaces changed; this check is about whether the change is inventoried.
- **Cross-platform porting (AST10) — MEDIUM.** A skill ported from another agent platform whose permission or safety metadata was dropped in translation — flag only what the diff shows was lost.

**Shell-hazard audit — when the diff touches shell code or operator-facing command snippets.** Two shapes with reproduced data-loss incidents in this framework's own history; judge each changed command by what it does on FAILURE, not success, and cite `constitution/shared-code-craft.md` §11–§12 by number the way ADRs and AST numbers are cited:

- **Truncate-before-failure (§11) — HIGH.** A `>` aimed at a file the repo or operator cannot lose, fed by a command that can fail — the redirect empties the target before the producer runs. Scratch-then-move is the fix; flag the bare form even when today's producer "cannot fail", because the next edit changes the producer, not the redirect.
- **Interpreter drift (§12) — HIGH.** A snippet with no declared shell, or an unbraced expansion followed by text an interactive shell can reinterpret (`"$REF:x"` forms). The finding is the unpinned form itself, never whether the author's own shell happens to bite today — the operator's shell is not the author's.

#### Agent 2 — API & CRUD Contract Manager

Verify CRUD symmetry, status codes, and response-shape data leaks. When a public interface changed, check that its **contract artifact** changed with it — the artifacts are enumerated in `scripts/guards.config.sh` under `BEHAVIOR_DELTA_SURFACES`, which is the one place this repo says where behavior is externalized.

#### Agent 3 — Pattern & Refactor Enforcer

Check adherence to existing patterns. Identify code that can be simplified or modularized. The patterns are not yours to choose: they are what `constitution/local-engineering.md`, the portable craft rules in `constitution/shared-code-craft.md`, and the accepted records in `docs/adr/` say they are, and a finding here must cite one of them.

#### Agent 4 — Simplicity Advocate

Actively look for ways to reduce code complexity and volume. For every piece of new code, ask: "Is there a simpler way to achieve the same result with less code?" Prioritize:

- Removing unnecessary abstractions, wrappers, or indirections that don't add value.
- Replacing verbose logic with concise alternatives (built-in methods, fewer branches).
- Eliminating dead code, redundant checks, or over-engineered patterns.
- Suggesting inline solutions over extracted helpers when the helper is used only once.
- Flagging premature generalizations — code that handles hypothetical future cases instead of the current need.

The goal is: less code to read, less code to maintain. Simpler code is easier to review, test, and debug.

#### Agent 5 — Reuse & DRY Auditor

Often the highest-yield lens: **new code must reuse what already exists before it reinvents it.** Using the reuse catalog from step 1, for every new function, type, constant, query, or block of logic in the diff, ask: *does an equivalent already exist in the codebase, and should this have called it instead?*

Flag, with the exact existing export/`file:line` that should have been reused:

- **Reimplemented helpers** — a new local function that duplicates a shared utility or value object that is already exported. Cite the existing one.
- **Copy-paste blocks** — the same logic (validation, mapping, error shaping, authorization checks, pagination handling) pasted across two or more changed files, or pasted from an existing file the diff clearly mirrors. Recommend extracting once and calling it from both sites.
- **Parallel constant/enum definitions** — a value, label map, or option list redefined locally when a canonical source already exists (e.g. deriving UI options from a domain enum rather than hand-listing them). Cite the canonical source.
- **Duplicated wire/DTO shapes or mappers** — a storage↔domain or domain↔wire mapping rewritten instead of routed through the existing mapper.
- **Divergent-behavior duplication** (highest severity) — two copies that are *supposed* to behave identically but have already drifted (one validates, the other doesn't; one degrades a legacy record, the other throws). This is a latent bug, not just a style issue — bump it up a severity band.

Distinguish **genuine duplication worth removing** from **incidental similarity** (two short blocks that look alike but are coupled to different concerns and would be wrongly fused by a shared abstraction). Do NOT recommend a premature shared abstraction for a single occurrence — that contradicts Agent 4. The bar is: an existing reusable thing is right there, OR the same non-trivial logic appears in ≥2 places in this diff. When in doubt about whether extraction is worth it, state the trade-off rather than asserting.

#### Agent 6 — Test Hygiene Inspector

When the PR includes test files, this agent MUST:

1. Identify which package or workspace the test belongs to.
2. Locate that workspace's test-runner config and check for global setup/bootstrap entries.
3. Read those global setup files to understand what mocks, stubs, or configurations are already provided globally.
4. Flag as **duplicated code** any mock or setup in the test file that is already handled by the global setup.
5. Verify that EVERY new function, method, or module introduced in this branch has corresponding tests. Flag missing coverage.
6. Check that each test case is truly **unitary** — testing exactly ONE behavior or scenario. Flag tests that:
   - Assert multiple unrelated behaviors in a single test block.
   - Combine happy-path and error-path assertions in one test.
   - Have vague descriptions that don't clearly state the single thing being tested.
7. Flag **redundant tests** — tests that verify the same behavior in different ways without adding value. Each test must justify its existence by covering a unique scenario.
8. Ensure test descriptions state the expected behavior and the condition, not the implementation.

Common examples of duplication to flag:

- Re-mocking modules that are already mocked in global setup.
- Redefining environment variables that are set globally.
- Re-stubbing globals already stubbed in setup files.
- Duplicating per-test hooks that mirror global setup behavior.

**If this repo has a mutation adapter, cite surviving mutants rather than taste.** Points 5–7 ask you to judge whether a test is *load-bearing*, and an opinion on that ("this assertion looks weak") is cheap for an author to argue with. Where a machine answer exists, use it instead.

Mutation testing is stack-specific, so the kit's core does not ship it: check `adapters/` for a wiring that provides a **mutation delta** — a mutation run scoped to the source files *this branch* changed, reporting the score plus every surviving mutant with `file:line` and the mutator. A surviving mutant is production behavior that was deleted or inverted with **no test failing** (shared invariant §9: green is a claim, not a measurement). **If no such adapter is wired, skip this block entirely and say so in one line — do not invent a substitute metric, and do not treat its absence as a clean bill of health.**

When a mutation delta IS available, use its output like this:

- **A survivor is a finding; an unbacked "this test looks weak" is not.** Report each as `[file:line] <Mutator> survives — <what the mutant changed>, no test failed`. **HIGH** when the mutant sits in code this branch added or changed (the branch shipped behavior nothing checks); **MEDIUM** when it is pre-existing (real, but not this PR's regression).
- **Assertion weakening is the failure mode this exists to catch.** An *edited existing* assertion in the diff plus a new survivor in the code that assertion covers is the signature of a test made to ask for less so it would pass. Name it as that, explicitly, and cite both the assertion hunk and the mutant.
- **Never report the score itself as a finding.** This is a diagnostic, not a gate, and the score drifts run to run. Report mutants, which are reproducible; small score movements are noise.
- **"The mutant is equivalent" is a legitimate resolution** — some mutants provably cannot be killed. If the author has already argued equivalence for a mutant, that closes it; do not re-raise it.
- **Its silence is not coverage.** A mutation run covers only the tree the adapter scopes it to, so points 1–8 still apply across every other tree in the diff.

#### Agent 7 — Spec & Behavior Reviewer (Axis 2 — fresh context)

The one agent whose job is the question the other six never ask: **did anything change that nobody asked for?**

**Context isolation (non-negotiable, shared invariant §4):** this sub-agent runs with a fresh context and receives ONLY:

1. The diff (`merge-base...HEAD`) scoped to the **contract artifacts** below.
2. The originating spec: the PRD/ticket issue body (from the branch name, PR description, or `Part of #N` references) and any decision records the diff touches. **When reading a PR description, stop at the marker line `<!-- explain-diff-appendix -->` where present**: `/implement` appends the author's `/explain-diff` narrative below it, and the implementer's narrative is exactly what this agent's context isolation exists to exclude. A body without the marker is read whole — an ordinary `---` rule is formatting, never a boundary.
3. The output of `scripts/behavior-delta.sh` (the deterministic candidate list), and the mutation delta from `adapters/` if one is wired.

It must **NOT** receive the other six agents' findings, the implementation conversation, or this skill's earlier summarization — anchoring on the implementer's narrative is exactly what it exists to avoid.

**The contract artifacts.** Behavior lives in them, so behavior changes are machine-visible in them. **This repo's list is data, not prose: it is `BEHAVIOR_DELTA_SURFACES` in `scripts/guards.config.sh`, and `scripts/behavior-delta.sh` inventories exactly that set.** Read the config rather than assuming the table below; it is a starting shape, not the authority.

| Behavior surface | Typical artifact | Red flag |
|---|---|---|
| Observable behavior | the existing test suite | an **edited** existing assertion is by definition a behavior change (new tests are additions; edits are the signal) |
| API surface | the API contract document (OpenAPI/GraphQL/protobuf) | any delta: fields, params, status codes |
| Error semantics | the shared error model | changed error types / status mappings |
| Domain events | the event catalogue + emit sites | payload/name changes |
| Persistence | migrations + the schema document | column meaning, defaults, constraints |
| Configuration | the environment/config schema | new/changed defaults, removed vars |
| Security posture | the header/auth policy | any delta |
| Agent-facing surface | prompts, tool descriptions, packaged skills | any prompt-surface delta |
| Process & agent surfaces | `.claude/skills/`, `constitution/`, root and nested `AGENTS.md`, `.githooks/`, `scripts/` | skills, hooks, gates and standing instructions change how every future session behaves — same confirm treatment; an edited constitution rule with no spec reference is an unapproved policy change, not a docs tidy-up |

**Procedure:** run `scripts/behavior-delta.sh` for the grounded candidate list, read each candidate's diff hunk, then classify every behavior delta against the originating spec:

- ✅ **SPECIFIED** — the spec asked for it. Cite the exact line: PRD acceptance criterion, ticket body, or decision-record number.
- ⚠️ **UNSPECIFIED — confirm** — no spec reference found. This is the finding class the human must see; do not soften it, do not resolve it yourself.

Missing requirements (spec asked, diff doesn't deliver) are also Axis-2 findings, tagged ❌ **MISSING**.

**Commit separation** (shared invariant §10 — refactoring and behavior never share a commit) is the one Axis-2 finding class that is *about the history rather than the diff*, so it is classified per commit, not per surface. `scripts/behavior-delta.sh` emits it as its own **Commit separation** section: commits whose Conventional Commit type claims structure-only work (`refactor`, `style`) while that commit's own diff touches a contract artifact. Each listed commit is a confirm-list item tagged 🔀 **MIXED COMMIT**. The script has already established the fact — do not re-derive it and do not resolve it yourself; report the commit, the artifacts it touches, and let the human choose between splitting the commit and relabelling it. An empty section is the normal result and needs no mention.

**The mutation delta, if this repo has one**, closes the list with the one thing the other tags cannot state: whether the behavior above is actually *enforced* (shared invariant §9). Emit it as exactly **one** 🧬 **MUTATION** line — including the skip, because "no mutated source changed" is itself information the human wants confirmed. It is **not** a classification and takes no ✅/⚠️: it is a measurement of the list, so it goes last, after the tagged items it qualifies. Never assign it a severity, never let a score decide anything, and do not restate the individual mutants here — Agent 6 owns those as Axis-1 findings (a surviving mutant is a *standards* problem: the tests are not load-bearing). Axis 2's use of the number is narrower and specific: a ⚠️ UNSPECIFIED behavior change in a file that also carries survivors is unrequested behavior that nothing is checking, and the human should see those two facts on the same screen. **If no mutation adapter is wired, omit the 🧬 line entirely** rather than printing a hollow one.

### 4. High-Signal Filtering

**Constraint**: Ignore nitpicks. Focus on vulnerabilities, broken contracts, major pattern deviations, code duplication / missed reuse of existing helpers, duplicated test setup, missing tests, redundant tests, and simplification opportunities that meaningfully reduce code volume or complexity.

**Justified vs. unjustified deviations**: before reporting any deviation from an existing pattern, decide whether it is *intentional and better* or *accidental*. A deviation that is an improvement over the pattern it mirrors — stronger typing, better error handling, a decision record that explicitly sanctions it — is **not a finding**; drop it or, at most, note it as a deliberate improvement. Only surface deviations that are accidental, that break consistency without benefit, or that contradict a binding record. When you cite one, include its number so the reasoning is auditable. This keeps the report free of noise where the author already made a considered call.

(High-signal filtering applies to **Axis 1 findings only** — Axis 2's confirm-list is exhaustive by design: every behavior delta appears, tagged, because "small note nobody flagged" is precisely how unrequested behavior changes slip through.)

### 5. Severity-Based Summary Report (MANDATORY — Axis 1)

After all agents complete, you MUST present the **Axis 1 (standards)** findings as one report following the output contract below. The report is GitHub-flavored markdown and nothing else — the same bytes render in the terminal and as PR-comment text, so: no ANSI escapes ever, no raw HTML beyond the `<details>`/`<summary>` fold, tables kept to two or three columns so a phone does not scroll them.

**Summary first.** The reader decides "is this blocked, and what do I fix first?" in the first screenful, before any finding detail:

```
### Review Summary

**Verdict:** <one line — blocking or not, and what to fix first; "no findings" is a valid verdict>
Clean audits: <the lenses that found nothing, comma-separated — one line, never sections of nothing>

| | Severity | Count |
|---|----------|-------|
| 🔴 | CRITICAL | X |
| 🟠 | HIGH | X |
| 🟡 | MEDIUM | X |
| 🔵 | LOW | X |
```

The badge is **redundant** encoding: the text label always accompanies it, because color is never the only channel a reader has. The count table is the exhaustive record — all four buckets always appear, zeros included. The severity buckets keep their meanings: CRITICAL is vulnerabilities, data leaks, broken functionality, divergent duplicate logic already drifted into a latent bug; HIGH is missing tests, broken contracts, major pattern violations, a reimplemented helper duplicating an existing export; MEDIUM is redundant tests, unnecessary complexity, copy-paste blocks worth extracting once; LOW is minor simplifications and style.

**Then the findings**, one section per **non-empty** severity (empty sections are omitted — the table already said zero), headed by badge + label: `#### 🔴 CRITICAL`, `#### 🟠 HIGH`, `#### 🟡 MEDIUM`, `#### 🔵 LOW`. Each finding uses this anatomy:

```
#### 🟠 HIGH

**H-1** `path/to/file:42` — one line: what is wrong, readable in isolation
↳ cites: <the decision record, audit item, or craft rule that makes this a finding>
↳ fix: <the change the review wants, one line>
<details><summary>evidence</summary>

the longer proof — a mutation transcript, a failing command, an excerpt

</details>

**H-2** `path/to/other:7` — next finding, same anatomy
```

Anatomy rules:

- The what/where line is **mandatory**: bold ID, a code-span `file:line` anchor (clickable in both mediums), one line that makes sense in isolation.
- `↳ cites:` and `↳ fix:` appear only when the review actually has them — never padded with filler.
- Evidence longer than a couple of lines goes behind the fold: thoroughness must not cost the reader scroll distance.
- Items are numbered INITIAL-N (C = Critical, H = High, M = Medium, L = Low). Numbering resets per category, and the IDs are how findings stay citable across iterations and commit messages.
- Axis 1 owns the four circle badges. It never borrows the confirm-list's glyph set, and never lends its badges to §5b — the two axes must be tell-apart-at-a-glance.

### 5b. Behavior Confirm-List (MANDATORY — Axis 2, never merged with §5)

Immediately after the severity report — **separated by a horizontal rule and under its own header**, so the axes are unmistakable on the page — present Agent 7's output verbatim in this shape, 🔀 items first, then ⚠️. The list's inner shape is a machine contract, not a style: glyph + TAG at the start of the line, one item per line, so the human-only items can be lifted verbatim by whatever reads this report next. Presentation may improve *around* these lines, never *inside* them — and in particular they never become table cells, which would break the lifting.

```
### Behavior changes in this PR — confirm before merge

🔀 MIXED COMMIT <short-sha> <commit subject>
                → claims refactor/style but touches <artifacts>. Split or relabel?

⚠️ UNSPECIFIED  <surface>: <what changed, one line>
                → no spec reference found. Desired?

✅ SPECIFIED    <surface>: <what changed, one line>
                → <PRD/ticket/decision-record citation>; <artifact updated>

❌ MISSING      <spec line the diff does not deliver>

🧬 MUTATION     <score> over <N> changed source file(s) — <M> surviving mutant(s)
                → the branch's behavior, as enforced by its tests
```

The 🧬 line when a mutation adapter is wired but the branch touched none of the source it covers — still printed, never omitted:

```
🧬 MUTATION     no covered source changed — mutation run skipped
```

When no mutation adapter is wired at all, the 🧬 line does not appear; say so once, plainly, under the list.

Rules: never assign severities to these items, never mix them into the C/H/M/L lists, never omit a ✅ (the human should see the whole behavioral footprint, not just the suspects). 🔀 items come first — they are the cheapest to act on and the reason the rest of the list is hard to read. 🧬 comes last and appears at most once: it measures the list rather than joining it, and it is the only line that is never a question for the human. If Agent 7 found no behavior deltas, say exactly that — an empty confirm-list is a meaningful result.

After presenting the summary, you MUST ask:

> "Which categories or specific items do you want me to post as comments on the PR? (e.g., 'all H', 'C-1 and H-3', 'all')"

### 6. Pull-Request Interaction & Feedback

#### Comment Placement

- **ALWAYS post inline comments on the exact line where the issue is**, as a single review with a `comments` array (on GitHub: `gh api repos/{owner}/{repo}/pulls/{number}/reviews`). (Axis 1 findings only.)
- **The Axis-2 confirm-list posts as exactly ONE top-level PR comment** (never inline, never split): the human confirms an inventory, they don't chase threads. Edit that same comment if the diff changes.
- **NEVER create a general/summary PR comment for Axis-1 findings.** Each standards finding must be an inline review comment attached to the specific line in the diff — a top-level summary of them makes each problem harder to locate. The Axis-2 confirm-list is the **single sanctioned exception**: it is an inventory by design, and it must be top-level (previous bullet).
- Use the line number in the file at HEAD, on the right-hand side of the diff.
- For new files, the file line number equals the diff line number.
- For modified files, use the line number in the new version of the file.
- All selected findings MUST be posted in a **single API call**, so they appear as a cohesive review rather than scattered individual comments.

#### Language

- **ALL review comments MUST be written in English.** Regardless of the language used in the terminal conversation with the user, every comment posted to the pull request must be in English.

#### Tone of Voice

- Write in **first person** as a colleague doing a review (e.g., "I noticed that…", "From what I can see…", "Maybe we could…").
- Professional, friendly, and collaborative. Never accusatory or robotic.
- **Do NOT prefix comments with labels like "H1:", "Finding 1:", "MEDIUM:", etc.** Just write naturally as a human reviewer would.
- Keep comments short and direct. Use bullet points for clarity when needed.

#### Approval Process

1. Present the severity-based summary report (step 5) in the terminal.
2. **Mandatory Step**: Ask the user which items to post on the PR.
3. Only after user confirmation, post ALL selected findings as **inline review comments** in a single API call. Never post a summary comment — only inline comments per finding.

This skill never merges (shared invariant §7). It reviews, reports, and stops.

### 7. Finalization

**Closing**: Restate the verdict in one line — the reader answers the question below without scrolling back up — and then you MUST end the response with: "Review complete. Which severity categories or specific items should I post as PR comments?"
