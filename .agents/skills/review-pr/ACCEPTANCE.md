# The approved tests, read for Agent 7

Opened from `/review-pr` §3, Agent 7's inputs, in a factory project. `SKILL.md` stays the entry point; this file is the branch, and a `§` points into `SKILL.md`.

A **factory project** is a repository whose top level holds the software factory's project manifest, `.factory/project.yaml`. There the operator approves a ticket's acceptance tests before the build — its `Accept-test:` lines — and a build that changes an approved test file has moved the definition of done it was handed. The **acceptance guard**, `scripts/acceptance-guard.sh`, says which: from the base to the head it prints one `changed: <ticket> <id> <path>` line per approved test file a held ticket names whose content differs from its approval, and nothing read from a ticket but ids, commits and checked `Accept-test:` lines. Outside a factory project, or with no `scripts/acceptance-guard.sh`, Agent 7 gets no guard file and nothing below applies.

**Run it, before Agent 7 spawns**, in the directory `d` outside the tree the check table uses, the base the one §0 locked and judged at that base, so the branch under review cannot rewrite the tickets and the policy it is held to:

```sh
POLICY_BASE=<base> sh scripts/acceptance-guard.sh check <base> HEAD >"$d/acceptance" 2>/dev/null; echo "exit: $?" >>"$d/acceptance"
```

Then hand `$d/acceptance` to Agent 7 as a file, beside `scripts/behavior-delta.sh`'s output. It holds the guard's stdout and a last `exit: <n>` line: exit 0 is no approved test changed, nothing to list; exit 1 the `changed:` lines; exit 3 the guard failed closed, its one `fail-closed <reason> <path>` line above — it could not tell what the base approved, so nothing it holds counts as checked; exit 2 is a call you got wrong: fix it and run it again, never hand Agent 7 a caller error. Agent 7 lists them as its rule says; the coordinator lists none and judges none.

**Agent 7's rule.** Where you hold the acceptance guard's output, list each `changed: <ticket> <id> <path>` line it holds as `❌ MISSING      <id> — approved test changed`, and on its `exit: 3` every id on the ticket's `Accept-test:` lines as `❌ MISSING      <id> — acceptance guard failed closed`; an id it lists is listed once. The ticket's `Accept-test:` lines are its stamp's, as `sh scripts/stamp.sh T-<digits>` prints them. A changed approved test is never a ✅ SPECIFIED item, whatever the diff's reason for it: only the operator re-approves a test (`factory approve`), never a review.

**The fail-closed line reaches the summary.** On exit 3 the summary carries `Acceptance guard: <its fail-closed line>` under its **Verdict:** line (§5), the line as the guard printed it — a reason and a path, never a ticket's prose — so a review the guard could not judge never reads as one it judged clean.

**A dispatched review.** An offline worker has no repository history to judge from, so the session dispatching `/review-pr` runs the line above itself, in the checkout it dispatches from, before the dispatch, and appends `$d/acceptance`, under an `Acceptance guard:` line, to the spec file it hands the worker — beside the `Check-table reader:` block, before it. The worker's contract lists that block in Agent 7's words, and quotes the fail-closed line in its `VERDICT:` line.
