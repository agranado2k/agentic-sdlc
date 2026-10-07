<!-- /review-pr standards lens `simplicity` (Axis 1). SKILL.md beside this file is the coordinator; a lens agent is handed this file, never that one. -->

#### Agent 4 — Simplicity Advocate

**Your diff is the slice `simplicity.diff`** that `scripts/lens-slice.sh` wrote under the policy in `scripts/lens-slice.config.sh` (by default: everything but generated fixtures and transcripts). Audit what it holds; a changed path outside it is another lens's lane.

Actively look for ways to reduce code complexity and volume. For every piece of new code, ask: "Is there a simpler way to achieve the same result with less code?" Prioritize:

- Removing unnecessary abstractions, wrappers, or indirections that don't add value.
- Replacing verbose logic with concise alternatives (built-in methods, fewer branches).
- Eliminating dead code, redundant checks, or over-engineered patterns.
- Suggesting inline solutions over extracted helpers when the helper is used only once.
- Flagging premature generalizations — code that handles hypothetical future cases instead of the current need.

The goal is: less code to read, less code to maintain. Simpler code is easier to review, test, and debug.
