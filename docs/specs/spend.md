# Spend

The kit's living spec for the **spend** area: what an agent spawn costs and
how the kit keeps it small — the context each spawn starts from, the reads it
makes, and the trace that attributes it. ADR-0012 is the contract; the file's
format is the starter a consumer gets, `templates/docs/specs/README.md`.

Seeded from PRD #580's Requirements, keeping its numbers; each
requirement joins this file with the ticket that delivers it. Outside this
file a requirement is cited as `spend/R<n>`, and the docs gate fails one that
no suite under `tests/` names. The kit's own: bootstrap strips it, so no
consumer inherits a spec whose tests it does not have.

R4. The Claude Code adapter SHALL provide one agent type per capability tier, each declaring the tools that tier's work needs and no model.
R5. The reviewer agent type SHALL carry no tool that writes files, reaches the network or calls an MCP server.
R24. No file the kit ships SHALL name a model identifier, including the agent types and the cascade's configuration (ADR-0003). The docs gate's existing check SHALL cover the new files.
