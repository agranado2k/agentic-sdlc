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

R17. WHERE the policy declares a cascade model for the `mechanical` tier, the skill dispatcher SHALL run a mechanical ticket on that model first and run the ticket's named oracle and the pairing guard on the result.
R18. WHEN the first rung's oracle or pairing guard is red, the dispatcher SHALL discard that rung's working changes and run the ticket again on the tier's mapped model.
R19. The dispatcher SHALL decide escalation from the oracle's and the guard's exit codes only, never from the worker's own report.
R20. IF a mechanical ticket names no oracle command, THEN the dispatcher SHALL refuse the cascade and run the ticket on the tier's mapped model, saying why.
R21. The trace SHALL record each cascade rung as its own spawn under one run, with `outcome` `passed` or `escalated`.
R24. No file the kit ships SHALL name a model identifier, including the agent types and the cascade's configuration (ADR-0003). The docs gate's existing check SHALL cover the new files.
