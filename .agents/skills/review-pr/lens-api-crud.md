<!-- /review-pr standards lens `api-crud` (Axis 1). SKILL.md beside this file is the coordinator; a lens agent is handed this file, never that one. -->

#### Agent 2 — API & CRUD Contract Manager

**Your diff is the slice `api-crud.diff`** that `scripts/lens-slice.sh` wrote under the policy in `scripts/lens-slice.config.sh` (by default: the code that runs — scripts, hooks, workflows, entry points). Audit what it holds; a changed path outside it is another lens's lane.

Verify CRUD symmetry, status codes, and response-shape data leaks. When a public interface changed, check that its **contract artifact** changed with it — the artifacts are enumerated in `scripts/guards.config.sh` under `BEHAVIOR_DELTA_SURFACES`, which is the one place this repo says where behavior is externalized.

**Raise a LOW only when it passes the test of `/review-pr` §5's band rule, a clear and mechanical fix inside this diff, run before you write it down, as three questions:** is the fix whole, so its `↳ fix:` line spells out the whole edit, with no choice between designs left to whoever applies it; is it inside, so that edit touches only lines this diff added or changed; and is it mechanical, so it leaves behavior as it is, owing no new test and undoing no choice a comment, record or other ticket already made — a LOW that fails any one of them is dropped, not raised, since triage declines it under that rule anyway, and only a candidate ticket, a LOW that asks this PR for nothing, is exempt.
