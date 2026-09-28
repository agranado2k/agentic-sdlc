# ADR-0009: A dispatched worker never holds network or credentials, and acts on the forge only through the broker

- **Status**: Accepted
- **Date**: 2026-09-28
- **Deciders**: Arthur Granado (operator), at the planning session for PRD #261
- **Supersedes / amends**: — (builds on ADR-0005's clause 12, the dispatcher's explicit non-goal of not enforcing what a worker may do: this record is where that enforcement lives, beside the dispatcher and not in it)
- **Superseded by**: —

## Context and problem statement

When `/implement` reaches its review step with no review workflow wired, this
repo dispatches the reviewer tier to another vendor's agent harness through
`scripts/agent-dispatch.sh`. That harness runs the worker under its default
sandbox: a read-only tree and no network. The worker was told to run
`/review-pr`, a skill that needs a `git fetch`, a forge API call and a human at
its final prompt. It had none of the three, so every dispatched review came
back with the same line — "the reviewer ran in a sandbox without network" —
and the operator relayed both axes to the pull request by hand: the standards
findings as a review with inline comments, the behavior confirm-list as one
comment. Three PRs landed in September 2026 (#257, #259, #262) with a review
that reached only the session and left the PR carrying nothing; #238 fixed the
skill's prose, not the mechanism.

The obvious fix, giving the worker network, is worse than the friction. On the
installed harness, network is a configuration key that exists only under a
writable sandbox, and the host filesystem stays readable — so a worker with
network would also hold a writable tree and the operator's own forge token. Its
input is the diff and the PR text, which the root manual's "Agent trust
boundary" classifies as untrusted content. Network therefore completes the
lethal trifecta inside the least-trusted agent in the chain: it could push,
post an approval under the operator's name, and satisfy branch protection on
its own word. `/review-pr` itself flags that arrangement as a HIGH finding
(AST06, isolation weakening). A scoped token does not rescue it, because
posting a review needs the same scope that allows approving.

So the pressure is two-sided: the relay is safe but manual and was skipped
three times running; network is automatic but hands the operator's forge
identity to an agent reading attacker-controllable text.

## Decision drivers

- **The lethal trifecta is the line.** A worker that reads untrusted content
  may hold private data OR an external action, never both. The diff is
  untrusted content; a forge token is an external action.
- **The dispatcher stays neutral.** ADR-0005 clause 12: the dispatcher does not
  enforce what a worker may do, and it is shared layer — changing it is a
  release action (hard rule 3) this wave did not budget.
- **The review must land where the human reads it.** `/implement` step 9: "a
  review that reported only to you is not a review". Whatever mechanism wins
  has to end with findings on the PR, not in a session transcript.
- **Policy as data, with a suite.** The guards, the tiers and the trace all
  keep their mechanism in a script and their decisions in a policy file the
  suite drives. A new privilege boundary should have the same shape, so that
  widening it is a visible edit to a list.
- **Kit-only until earned.** The kit ships no forge-specific mechanism today;
  a second caller (an implementer worker opening a PR) earns a promotion, and
  promotion is a release.

## Considered options

1. **The worker stays offline; a host-side broker validates its stdout report
   and performs the two allowed forge operations** *(chosen)* — the worker
   prints the machine contract `.agents/prompts/review-worker.md` defines, the
   session captures it to a file, and `scripts/forge-broker.kit.sh` — on the
   host, where the credentials and network already are — checks it against
   the contract and the diff, refuses everything its policy file does not
   name, posts one review with event COMMENT and one behavior comment, and
   records the verdict in the trace.
2. **Network inside the sandbox** — rejected: on the installed harness it
   requires a writable sandbox, the host filesystem stays readable, and the
   worker would hold the operator's token while reading untrusted content.
   The kit's own review skill flags this as HIGH (AST06).
3. **A `gh` shim on the worker's PATH** — rejected: it gates only a cooperative
   agent. An injected one calls the binary by absolute path or uses `curl`
   with the readable token, and the sandbox has no per-host allowlist to stop
   it.
4. **A scoped fine-grained token for the worker** — rejected: posting a review
   needs the same scope that allows approving, so only a separate bot account
   closes the hole, and that is per-machine secret management the kit cannot
   ship or test.
5. **The CI review workflow instead of dispatch** — not an alternative but the
   complement: it is the sanctioned reviewer *with* network, in a disposable
   VM with a job-scoped token. Enabling it on this repo is a separate ticket.

## Decision outcome

Chosen: **option 1**.

1. **A dispatched worker never holds network or credentials.** No sandbox,
   approval or network flag is added to any command template in the kit's
   policy files. The worker's only channel to the forge is the report it
   prints on stdout.
2. **The broker is the one thing that acts on the forge on a worker's
   behalf.** `scripts/forge-broker.kit.sh`, host-side, kit-only, never
   shipped (on `bootstrap.sh`'s `KIT_ONLY` list), standing beside the
   shared-layer dispatcher and changing none of it. The glossary defines
   **Broker** under Process, distinct from a gate (a check on the tree) and a
   guard (a check on a diff): a broker acts.
3. **The allow-list is policy as data.** `scripts/forge-broker.kit.config.sh`
   names the operations the broker may perform. This release names two: a
   pull request review with event COMMENT carrying inline comments, and one
   top-level PR comment. An operation not on the list does not exist to the
   broker (exit 78 when asked). The event is a constant of the policy, and the
   broker accepts only COMMENT there: a blank event leaves the review PENDING
   and invisible, and APPROVE or REQUEST_CHANGES would let a worker's word
   satisfy branch protection. Widening the event is a new record, not an edit.
4. **Nothing in the report can choose the operation, the target PR or the
   event.** The PR number is the operator's first argument; a number in the
   report's text is text.
5. **Validation before action, and nothing posted unless everything
   validated.** The report must match the machine contract — a `REVIEWED:
   <full sha>` first line, a `VERDICT:` line, the four severity headings in
   order, findings in the ID / location / fix shape, behavior items opening
   with their tag — or the broker posts nothing and exits 65 (EX_DATAERR); a
   `REVIEWED` line that contradicts the session's `--commit` is the same
   failure. Each finding's `path:line` must sit in the diff's right-hand
   side; a finding that does not is dropped from the inline comments and
   named on stderr, and stdout says how many were withheld.
6. **The reviewed commit is part of the contract.** In this release it must
   equal the PR head; anything else is exit 75 (EX_TEMPFAIL) with a one-line
   reason and nothing posted. The two finer cases — commits added after the
   review (post anchored to the reviewed commit, with a drift note) and a
   rewritten branch (refuse) — are a later ticket's, and their exit statuses
   are already reserved here: 0 with a note, and 75.
7. **Exit statuses are distinct and from the sysexits vocabulary the
   dispatcher already uses**: 0 posted or already posted; 2 usage; 65 the
   report fails the contract; 69 (EX_UNAVAILABLE) no forge CLI on PATH, or a
   forge call that failed; 75 the reviewed commit is not the head; 78
   (EX_CONFIG) the policy is missing or does not allow an operation the broker
   performs.
8. **Idempotence by marker.** Every body the broker writes opens with an HTML
   comment carrying the report's git content hash. Before posting, the broker
   lists the PR's reviews and comments and skips whichever already carries the
   marker, printing the existing URL — so a retried session lands the review
   once, and a crash between the two operations is recovered by re-running.
9. **The output contract**: stdout carries the review URL and the comment URL,
   one per line, then one `dropped …` line when anything was withheld; under
   `--dry-run` it carries both payloads exactly as they would be sent, after
   the reads and before any write. stderr carries every reason, prefixed
   `forge-broker:`.
10. **The trace is written, not read.** One `review.verdict` event, subject
    `pr:#<N>`, the verdict line as outcome, the model and agent harness when
    the caller passes them. Never load-bearing (ADR-0008 clause 4).
11. **Explicit non-goal**: this record does not decide whether the kit ships a
    broker. It is kit-only; promotion to the shared layer is reopened when a
    second caller needs it, and is a release action then.
12. **Explicit non-goal**: this record does not enable the CI review workflow
    on the kit's own PRs. `ai-review.example.yml` stays inert until its own
    ticket; that reviewer runs with network by design, in a disposable VM with
    a job-scoped token, and is the complement of this decision rather than a
    contradiction of it.

## Consequences

- **Good**: a dispatched review lands on the PR without the operator relaying
  it, and the worker that produced it never had a token or a route to the
  forge — an injected diff can at most shape the text of a COMMENT review.
- **Good**: the privilege boundary is a list in a policy file with a suite
  behind it (`tests/forge-broker.test.sh` drives every refusal red), so the
  next operation the kit grants a worker is a visible edit, reviewed as one.
- **Bad / trade-off**: the review is posted by the operator's own `gh`
  identity, so on the PR it reads as the operator's review. The body's footer
  says who actually reviewed and that the event is COMMENT by policy; a
  separate bot identity would be more honest and is exactly the per-machine
  secret management option 4 rejected.
- **Bad / trade-off**: the broker is one more kit-only script with its own
  policy twin — the fourth instance of ADR-0003's arrangement — and each one
  is a file a session has to know exists. The manual's quick-reference row
  and the glossary entry are the cost of that.
- **Neutral**: the dispatcher, the worker prompt's machine contract and the
  `/implement` skill are unchanged by this record. The prompt's opening
  statement that the worker is offline (#266) and the skill naming the broker
  as the way a dispatched review lands (#269) are their own tickets.
- **Honest limitation**: the broker validates shape and location, not truth.
  A worker that was steered into writing a false finding at a real diff line
  gets that finding posted, as a COMMENT, under the operator's name. The
  human reading the PR is still the last check — which is what shared
  invariant §5 says the behavior axis is for, and why the broker never
  resolves it.
- **Honest limitation**: the broker trusts its own policy file. A policy
  edited to widen `BROKER_OPERATIONS` is honoured, and only the suite and the
  reviewer of that diff stand in the way — the same standing every policy
  file in this kit has.

## More information

- Implemented in: #265 (this record, the broker, its policy and suite);
  designed in PRD #261; #266 adds the `REVIEWED` line and the offline
  statement to the worker contract; #269 makes `/implement` name the broker.
- Related: ADR-0005 (the agent harness axis; clause 12 is the non-goal this
  record picks up), ADR-0007 (a review never resolves to the session's own
  model), ADR-0008 (the trace the verdict is written to), the root manual's
  "Agent trust boundary", `/review-pr`'s AST06 finding.
- The sandbox facts above were checked against the installed codex CLI on
  2026-09-23 and should be re-checked when that CLI moves.
