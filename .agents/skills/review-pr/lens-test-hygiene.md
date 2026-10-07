<!-- /review-pr standards lens `test-hygiene` (Axis 1). SKILL.md beside this file is the coordinator; a lens agent is handed this file, never that one. -->

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

Mutation testing is stack-specific, so the kit's core does not ship it: check `adapters/` for a wiring that provides a **mutation delta** (its output handed to you as a file when you hold no shell) — a mutation run scoped to the source files *this branch* changed, reporting the score plus every surviving mutant with `file:line` and the mutator. A surviving mutant is production behavior that was deleted or inverted with **no test failing** (shared invariant §9: green is a claim, not a measurement). **If no such adapter is wired, skip this block entirely and say so in one line — do not invent a substitute metric, and do not treat its absence as a clean bill of health.**

When a mutation delta IS available, use its output like this:

- **A survivor is a finding; an unbacked "this test looks weak" is not.** Report each as `[file:line] <Mutator> survives — <what the mutant changed>, no test failed`. **HIGH** when the mutant sits in code this branch added or changed (the branch shipped behavior nothing checks); **MEDIUM** when it is pre-existing (real, but not this PR's regression).
- **Assertion weakening is the failure mode this exists to catch.** An *edited existing* assertion in the diff plus a new survivor in the code that assertion covers is the signature of a test made to ask for less so it would pass. Name it as that, explicitly, and cite both the assertion hunk and the mutant.
- **Never report the score itself as a finding.** This is a diagnostic, not a gate, and the score drifts run to run. Report mutants, which are reproducible; small score movements are noise.
- **"The mutant is equivalent" is a legitimate resolution** — some mutants provably cannot be killed. If the author has already argued equivalence for a mutant, that closes it; do not re-raise it.
- **Its silence is not coverage.** A mutation run covers only the tree the adapter scopes it to, so points 1–8 still apply across every other tree in the diff.
