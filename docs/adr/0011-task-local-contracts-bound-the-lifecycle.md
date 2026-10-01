# ADR-0011: Task-local contracts bound the lifecycle

- **Status**: Accepted
- **Date**: 2026-09-30
- **Deciders**: Arthur Granado (operator), at the lifecycle PRD wave approval
- **Supersedes / amends**: none; preserves ADR-0008's write-only tracing boundary
- **Superseded by**: —

## Context and problem statement

Skills describe phases, but an ordinary request has no mechanically checked
boundary between an installed catalogue, authorized scope, review and delivery.
A file inventory cannot prove which instructions a model loaded. The lifecycle
needs explicit evidence without turning optional tracing into operational state.

## Decision drivers

- Keep the core portable before a consumer chooses a runtime: POSIX sh and git.
- Keep the existing Distribution, Enforcement and Process contexts.
- Bound work by explicit scope and current evidence, with honest partial outcomes.
- Preserve the existing dispatcher and independent review boundary.

## Considered options

1. **Minimal-dependency procedural boundary**: shell commands validate an
   explicit task-local contract and content-bound receipts. Small public seams;
   no install, daemon or additional broker. Chosen.
2. **Readable-flow runtime**: express transitions in a typed runtime or workflow
   engine, with a store and adapters. Easier structured parsing and inspection,
   but introduces runtime installation, persistence and migration concerns before
   a consumer has a toolchain. Rejected for this wave.

## Decision outcome

1. Distribution owns catalogue admission: canonical `.agents/skills` bytes,
   explicitly declared active roots and references. Admission reports origin and
   git content identities, checks exact path case and refuses stale copies. It
   is filesystem evidence, never a claim of model-visible loading.
2. Active roots are supplied by the repository or caller. The initial supported
   representation is linked or byte-identical content. A transformation must
   eventually name a versioned reproducible verifier; unsupported transformation
   modes fail closed now. We do not claim transformed installations are supported.
3. References are explicitly classified as executable, optional, example or
   external. Only executable references are mandatory local dependencies;
   optional references are checked when present. Prose examples are not parsed
   as commands. The declaration is a reviewed contract, not a complete inference
   from arbitrary prose. Skill phase metadata remains in the skills themselves.
4. Process will own a task-local scope contract and resumable outcome;
   Enforcement will own validation and content-bound evidence receipts. Subsequent
   slices bind review capability, delivery evidence and resume to that contract.
   No new bounded context, generic workflow engine or dispatch broker is created.
5. Operational records are separate from the optional trace. Lifecycle decisions
   never read trace history. Existing dispatcher capability remains its boundary;
   a requested review and a completed review remain distinct facts.
6. Delivery must eventually distinguish completion, partial and blocked outcomes;
   this catalogue slice implements none of those later state transitions. The
   wave's release ticket adds shared mechanisms to the manifest and documents
   adoption for existing consumers. A fresh bootstrap retains the catalogue
   mechanism now while stripping this kit-only record and its tests.

## Consequences

- No additional runtime dependency or background service.
- Plain records require explicit grammar and failure tests at each public seam.
- A caller can omit an active root or reference; admission cannot discover what
  a model sees or certify an undeclared installation. Runtime evaluation remains
  a separate wave deliverable.
- Concurrent source edits require re-admission; this is a read-time check, not a
  filesystem lock or a security boundary against a malicious local writer.

## More information

Ticket #296 is catalogue admission. Tickets #297–#302 add scope, review
capability, evidence, resume, evaluation and release respectively.
