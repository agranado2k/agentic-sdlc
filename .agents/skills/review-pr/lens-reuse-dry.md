<!-- /review-pr standards lens `reuse-dry` (Axis 1). SKILL.md beside this file is the coordinator; a lens agent is handed this file, never that one. -->

#### Agent 5 — Reuse & DRY Auditor

**Your diff is the slice `reuse-dry.diff`** that `scripts/lens-slice.sh` wrote under the policy in `scripts/lens-slice.config.sh` (by default: everything but generated fixtures and transcripts). Audit what it holds; a changed path outside it is another lens's lane.

Often the highest-yield lens: **new code must reuse what already exists before it reinvents it.** Using the reuse catalog from step 1, for every new function, type, constant, query, or block of logic in the diff, ask: *does an equivalent already exist in the codebase, and should this have called it instead?*

Flag, with the exact existing export/`file:line` that should have been reused:

- **Reimplemented helpers** — a new local function that duplicates a shared utility or value object that is already exported. Cite the existing one.
- **Copy-paste blocks** — the same logic (validation, mapping, error shaping, authorization checks, pagination handling) pasted across two or more changed files, or pasted from an existing file the diff clearly mirrors. Recommend extracting once and calling it from both sites.
- **Parallel constant/enum definitions** — a value, label map, or option list redefined locally when a canonical source already exists (e.g. deriving UI options from a domain enum rather than hand-listing them). Cite the canonical source.
- **Duplicated wire/DTO shapes or mappers** — a storage↔domain or domain↔wire mapping rewritten instead of routed through the existing mapper.
- **Divergent-behavior duplication** (highest severity) — two copies that are *supposed* to behave identically but have already drifted (one validates, the other doesn't; one degrades a legacy record, the other throws). This is a latent bug, not just a style issue — bump it up a severity band.

Distinguish **genuine duplication worth removing** from **incidental similarity** (two short blocks that look alike but are coupled to different concerns and would be wrongly fused by a shared abstraction). Do NOT recommend a premature shared abstraction for a single occurrence — that contradicts Agent 4. The bar is: an existing reusable thing is right there, OR the same non-trivial logic appears in ≥2 places in this diff. When in doubt about whether extraction is worth it, state the trade-off rather than asserting.

**Then ask which case the duplication is, because the two leave the report differently.** A duplication **the diff ADDS** — a new copy of something that already exists, or the same logic pasted twice within this diff — is the author's, and a finding at the severity the buckets give it. A duplication the diff merely **touches or extends** — copies that pre-date the branch, which the diff edits in place, mirrors into one more call site, or leaves beside a helper it added — is not the author's to consolidate: moving those copies into a shared file is a behaviour-preserving refactor, and shared invariant §10 lands one on its own ticket, never as a passenger on a feature diff. Report that case as a **candidate ticket** — a LOW whose what/where line opens `candidate ticket:`, whose `↳ cites:` line names shared invariant §10, and whose `↳ fix:` line reads `none on this PR — candidate ticket (shared invariant §10)`, so the PR is asked for nothing. The report's shape does not change: a candidate ticket is a LOW with the §5 anatomy, not a new section, badge or status, so `/pr-iterate` reads it as a LOW it may defer and the trace counts it as this lens's raise — and the one exception is the divergent-behavior copy above, which is a latent bug whichever branch introduced it and stays a finding.

**What the decision records decline.** Each raise below was rejected in triage with the record beside it as the reason, so do not raise it, on any diff: the list is drawn from the trace's rejected `finding.triage` events against this lens, never invented, and a rule joins it only beside the record its rejection cited. A record that names the kit is the kit's own; a project that never adopted it judges that case by the bar above.

- **Consolidating copies the diff did not write** into one shared helper on this PR — declined by shared invariant §10: the inherited case above is the one way such copies leave the report.
- **A shared file for a second copy of a short helper**, where the extraction would add a library the change otherwise does not need — declined by `constitution/shared-code-craft.md` §1, the smallest diff that delivers the behavior.
- **A consolidation whose shared home is a shared-layer file**, or that ties a kit-only list to one — declined by the kit's root manual, hard rule 3: a shared-layer edit is a release action, never a passenger on a ticket.
- **The kit wrapper's spawn-word bridge, read as a copy of the resolver's agent-harness split** — declined by the kit's ADR-0013 clause 2, which puts the spawn-word bridge in the wrapper on purpose.
- **A restated bound that is the observable contract**, such as the coverage grammar's id bounds a suite holds beside `scripts/coverage.sh` — declined by the kit's living spec requirement process/R7, which makes those bounds the contract.
