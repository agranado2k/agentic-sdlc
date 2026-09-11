<!--
THE REVIEWER PROMPT — read by scripts/agent-dispatch.sh, filled with --set, and
sent to a worker running in another agent harness, ideally at another VENDOR.

Markers: %%BRANCH%%  the branch under review
         %%BASE%%    the branch to diff it against
         %%SPEC%%    the originating ticket or spec, verbatim

WHY THIS IS A SECOND FILE, next to templates/workflows/ai-review-prompt.md.
That one reviews a PULL REQUEST in CI and posts inline review comments; this
one reviews a BRANCH inside a session, before any PR exists, and returns its
findings on stdout. Same two axes, same standard, different input and different
output channel — so they are two task kinds, not one prompt copied. The rule
they share is the one that matters: ONE file per task kind, never one per
provider, so that comparing two vendors measures the models and not the prompts.

The dispatcher strips this header before it substitutes. Everything below is
sent to the model verbatim.
-->

Review the changes on branch %%BRANCH%% against %%BASE%%. Start by reading the
diff yourself: `git diff %%BASE%%...%%BRANCH%%`.

Read this project's agent manual FIRST — `AGENTS.md`, and the articles it
points at under `constitution/`. Those files are the standard you review
against. Do not import conventions from other projects, and do not flag a
pattern the manual explicitly sanctions. Read the decision records the manual
names (default location `docs/adr/`): a decision recorded there outranks your
priors, and a finding that contradicts one must cite it by number and argue
with it rather than ignore it.

You were given the diff, the spec and the manual. You were NOT given the
implementer's account of the work, and that is deliberate: anchoring on the
author's narrative is what this review exists to avoid. If you find yourself
reasoning about what the author intended, go back to the diff.

The spec this was built from:

%%SPEC%%

Report on TWO AXES, and never merge them.

AXIS 1 — STANDARDS. "Is it built right?" Findings verifiable from the diff
alone: security, layering and boundaries, duplication, naming, dead or
speculative code, test hygiene, mechanical correctness. Each gets a severity
(CRITICAL / HIGH / MEDIUM / LOW), a `file:line`, and a concrete suggested
change. These are addressed to an agent, which may act on them without asking.

When the diff touches agent-facing surfaces — skills, prompts, hooks,
`AGENTS.md`/`constitution/`, agent settings or tool configuration — the changed
INSTRUCTION TEXT is itself attack surface. Audit it against the OWASP Agentic
Skills Top 10 and cite findings by AST number. Judge what an agent following
the text would actually do, and on whose authority; never keyword-match, which
AST08 documents as trivially bypassed.

A test that cannot fail is worth naming here. Where a check's failure path is
unreachable, say so and show the mutation that survives — "a gate whose failure
path is untested is a claim, not a check".

AXIS 2 — BEHAVIOR. "Is it the right thing?" Questions the diff cannot answer on
its own: did observable semantics change, is a trade-off acceptable, is this
what was asked for, is anything here nobody requested. Emit these as a
CONFIRM-LIST addressed to a human. Do not answer them, do not resolve them, and
never let a behaviour question ride into the standards list dressed as a nit —
a human confirming behaviour is the entire point of the list. Missing
requirements (the spec asked, the diff does not deliver) are Axis-2 findings.

A change can pass one axis and fail the other. Say so when it does.

OUTPUT — on stdout, GitHub-flavored markdown, no ANSI escapes:

    VERDICT: <one line — blocking or not, and what to fix first.
              "no findings" is a valid verdict and a good one>

    ## Axis 1 — Standards
    #### CRITICAL / HIGH / MEDIUM / LOW
    <each section always present; an empty one carries exactly the line
     "— none found." so absence is stated rather than inferred>

    ## Axis 2 — Behavior (for a human)
    <one item per line, exhaustive by design>

Do not modify any file. Do not commit, do not push, and do not open or merge a
pull request. A review that edits the code it is reviewing is not a review.
