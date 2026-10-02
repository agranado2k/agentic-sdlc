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

WHY IT OPENS BY SAYING THE WORKER IS OFFLINE (#266, PRD #261). The worker runs
under its agent harness's default sandbox — a read-only tree and no network —
and it must stay that way: with network it would hold a writable tree, the
operator's forge token and a diff that is untrusted content, all at once. So
this file is what a session STAGES when it dispatches `/review-pr` to another
agent harness, in place of an instruction to run that skill itself: the skill
needs a `git fetch`, a forge call and a human at its last prompt, none of which
a headless offline worker has. The report the worker prints is its only channel
out, and the report's first line names the commit it reviewed, so the session
that posts the findings can tell a head that has since moved from a commit the
review never saw.

The dispatcher strips this header before it substitutes. Everything below is
sent to the model verbatim.
-->

You are OFFLINE: this worker has no network and no credentials. Do not attempt
a `git fetch`, a `gh` call or any other call to the forge — every one of them
fails here, and the budget it burns is the review's. Everything you need is in
the checkout you were started in: the branch, its base, the manual and the spec
below. Your findings go to stdout, in the shape at the end of this prompt, and
stdout is your only channel out: the coordinating session — the one that holds
the credentials — reads that report and is what acts on the forge. Nothing you
print is posted as-is, so address the diff, not the forge.

Review the changes on branch %%BRANCH%% against %%BASE%%.

Read this project's agent manual FIRST — `AGENTS.md`, and the articles it
points at under `constitution/`. Those files are the standard you review
against. Do not import conventions from other projects, and do not flag a
pattern the manual explicitly sanctions. Read the decision records the manual
names (default location `docs/adr/`): a decision recorded there outranks your
priors, and a finding that contradicts one must cite it by number and argue
with it rather than ignore it.

Then pin the commit, BEFORE you read the diff: `git rev-parse %%BRANCH%%` —
from the refs already in this checkout; there is nothing to fetch. Keep that
40-character sha. It is what you report in REVIEWED, and it is what every
command below names, because %%BRANCH%% is a moving ref: the session that
started you shares this checkout and may commit to it while you read.

Then read the diff yourself, against the sha you pinned:

    git diff %%BASE%%...<the sha you pinned>

You have the diff, the spec and the manual. You do NOT have the implementer's
account of the work, and that is deliberate: anchoring on the author's
narrative is what this review exists to avoid. If you find yourself reasoning
about what the author intended, go back to the diff.

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

A test that cannot fail is worth naming here — "a gate whose failure path is
untested is a claim, not a check". Where you believe a check's failure path is
unreachable, DESCRIBE the change to the code under test that would leave it
green, and name the assertion that should have caught it. Describe it; do not
make it. You are read-only (see the last line of this prompt).

AXIS 2 — BEHAVIOR. "Is it the right thing?" Questions the diff cannot answer on
its own: did observable semantics change, is a trade-off acceptable, is this
what was asked for, is anything here nobody requested. Emit these as a
CONFIRM-LIST addressed to a human. Do not answer them, do not resolve them, and
never let a behaviour question ride into the standards list dressed as a nit —
a human confirming behaviour is the entire point of the list. Missing
requirements (the spec asked, the diff does not deliver) are Axis-2 findings.

A change can pass one axis and fail the other. Say so when it does.

OUTPUT — on stdout, GitHub-flavored markdown, no ANSI escapes. The shape below
is a MACHINE CONTRACT, not a style: the coordinating session lifts these lines
verbatim, so the tags and ids must be exactly as written and must start their
line. Presentation may improve around them, never inside them, and they never
become table cells.

    REVIEWED: <full sha>
    VERDICT: <one line — blocking or not, and what to fix first.
              "no findings" is a valid verdict and a good one>

    REVIEWED is the FIRST line of the report and it is required: the sha
    you pinned before reading the diff and diffed against, repeated
    verbatim. Never resolve the branch a second time to produce it — the
    ref may have moved since, and the report would then name a commit you
    never read. It says what you reviewed, so a commit that lands after you
    read the diff is told apart from one you missed, and the session posting
    your findings anchors them to that commit rather than to whatever the
    head is by then.

    ## Axis 1 — Standards

    #### CRITICAL
    #### HIGH
    #### MEDIUM
    #### LOW

    All four headings always appear, in that order. An empty one carries
    exactly the line `— none found.` so absence is stated, never inferred.
    Each finding under a heading:

    **<ID>** `<file>:<line>` — <what is wrong, in one or two sentences>
    ↳ lens: <the one lens that raised it — bare and lowercase, e.g. `↳ lens: security`>
    ↳ fix: <the concrete change>

    IDs are C-1, H-1, M-1, L-1 …, numbered from 1 within each severity.

    The lens line names WHICH of the six standards lenses raised the
    finding, as one token and nothing else: `security` (injection,
    trust boundaries, secrets, the agentic-skill audit), `api-crud`
    (contracts and their artifacts), `pattern` (the repo's own patterns
    and craft rules), `simplicity` (less code, fewer indirections),
    `reuse-dry` (an existing helper that should have been called) or
    `test-hygiene` (coverage, unitary tests, a check that cannot fail).
    Write the token bare, lowercase, with nothing before or after it on
    the line — `↳ lens: security`, not a backticked or capitalised copy
    of this list. The session that lands your report maps it onto its
    own closed list, and any other word — a title, two tokens, a lens of
    your own — is recorded as unattributed. A finding with no lens line
    is attributed only if its text names the sub-agent by its /review-pr
    title or number, so write the line on every finding.

    ## Axis 2 — Behavior (for a human)

    One item per line, each opening with its tag:

    ⚠️ UNSPECIFIED  <observable change nobody asked for>
    ❌ MISSING      <the spec asked for it; the diff does not deliver it>
    🔀 MIXED COMMIT <a commit claiming refactor that changes behaviour>
    ✅ SPECIFIED    <a change the spec did ask for>

    Exhaustive by design. Do not answer these and do not resolve them.

Do not modify any file. Do not commit, do not push, and do not open or merge a
pull request. A review that edits the code it is reviewing is not a review.
