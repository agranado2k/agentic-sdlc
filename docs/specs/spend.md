# Spend

The kit's living spec for the **spend** area: what an agent spawn costs and
how the kit keeps it small — the context each spawn starts from, the reads it
makes, and the trace that attributes it. ADR-0012 is the contract; the file's
format is the starter a consumer gets, `templates/docs/specs/README.md`.

Seeded by #585 from PRD #580's Requirements, keeping its numbers; each
requirement joins this file with the ticket that delivers it. Outside this
file a requirement is cited as `spend/R<n>`, and the docs gate fails one that
no suite under `tests/` names. The kit's own: bootstrap strips it, so no
consumer inherits a spec whose tests it does not have.

R1. WHEN a chain skill spawns a subagent, the trace SHALL record the spawn's stop with the tier, the domain (or none), the skill and the ticket (or none) the spawn served.
R8. The docs gate SHALL fail when a SKILL.md exceeds the byte ceiling the gate's policy declares for it, naming the file, its size and the ceiling.
