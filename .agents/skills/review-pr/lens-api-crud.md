<!-- /review-pr standards lens `api-crud` (Axis 1). SKILL.md beside this file is the coordinator; a lens agent is handed this file, never that one. -->

#### Agent 2 — API & CRUD Contract Manager

**Your diff is the slice `api-crud.diff`** that `scripts/lens-slice.sh` wrote under the policy in `scripts/lens-slice.config.sh` (by default: the code that runs — scripts, hooks, workflows, entry points). Audit what it holds; a changed path outside it is another lens's lane.

Verify CRUD symmetry, status codes, and response-shape data leaks. When a public interface changed, check that its **contract artifact** changed with it — the artifacts are enumerated in `scripts/guards.config.sh` under `BEHAVIOR_DELTA_SURFACES`, which is the one place this repo says where behavior is externalized.
