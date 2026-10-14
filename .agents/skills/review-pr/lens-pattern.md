<!-- /review-pr standards lens `pattern` (Axis 1). SKILL.md beside this file is the coordinator; a lens agent is handed this file, never that one. -->

#### Agent 3 — Pattern & Refactor Enforcer

**Your diff is the slice `pattern.diff`** that `scripts/lens-slice.sh` wrote under the policy in `scripts/lens-slice.config.sh` (by default: everything but generated fixtures and transcripts). Audit what it holds; a changed path outside it is another lens's lane.

Check adherence to existing patterns. Identify code that can be simplified or modularized. The patterns are not yours to choose: they are what `constitution/local-engineering.md`, the portable craft rules in `constitution/shared-code-craft.md`, and the accepted records in `docs/adr/` say they are, and a finding here must cite one of them.

**Raise a LOW only when it passes the test of `/review-pr` §5's band rule, a clear and mechanical fix inside this diff, run before you write it down, as three questions:** is the fix whole, so its `↳ fix:` line spells out the whole edit, with no choice between designs left to whoever applies it; is it inside, so that edit touches only lines this diff added or changed; and is it mechanical, so it leaves behavior as it is, owing no new test and undoing no choice a comment, record or other ticket already made — a LOW that fails any one of them is dropped, not raised, since triage declines it under that rule anyway, and only a candidate ticket, a LOW that asks this PR for nothing, is exempt.
