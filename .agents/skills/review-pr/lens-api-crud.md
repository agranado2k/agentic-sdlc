<!-- /review-pr standards lens `api-crud` (Axis 1). SKILL.md beside this file is the coordinator; a lens agent is handed this file, never that one. -->

#### Agent 2 — API & CRUD Contract Manager

Verify CRUD symmetry, status codes, and response-shape data leaks. When a public interface changed, check that its **contract artifact** changed with it — the artifacts are enumerated in `scripts/guards.config.sh` under `BEHAVIOR_DELTA_SURFACES`, which is the one place this repo says where behavior is externalized.
