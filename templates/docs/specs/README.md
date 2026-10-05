# Living specs

This directory holds the project's **living specs**: one file per area,
`docs/specs/<area>.md`, stating what that area does today. A PRD is written,
built and closed; a living spec outlives it, so a test can name a requirement
that is still true long after the wave that introduced it.

There is no living spec here yet. This README is the only file bootstrap
put in the directory, and it holds no requirement: it is not an area file.

## The file

- **The name is the area**: one lowercase token, `[a-z][a-z0-9-]*` —
  `docs/specs/billing.md` is the `billing` area. A bounded context in the
  glossary's context map is the default unit.
- **A requirement is a line that opens with its id**, `R<n>.` at the first
  column, then one observable behavior a test can fail, in EARS-lite
  (`The <system> SHALL …`, `WHEN …`, `WHILE …`, `IF … THEN …`, `WHERE …`).
  Any other line — a heading, prose, an indented line, a fenced example — is
  not a requirement.
- **Outside the file, a requirement is cited as `<area>/R<n>`** — in a
  ticket's `Covers:` line, in a PRD's delta, and in the test that holds it.
- **An id is stable for the file's life and never reused.**

```md
# Billing

R1. The invoice SHALL carry the customer's legal name.
R2. WHEN a payment fails, the system SHALL retry once.
~~R3.~~ Removed by #41: the paper statement is no longer sent.
```

## How it changes: deltas, merged by the PR that delivers them

A PRD for an area that has a living spec does not restate the area. Its
Requirements section holds deltas, each line spelled with the area-qualified
id, so the PRD, the ticket and the test cite one string:

```md
### ADDED
billing/R4. WHEN an invoice is reissued, the invoice SHALL show the original's number.

### MODIFIED
billing/R2. WHEN a payment fails, the system SHALL retry twice, an hour apart.

### REMOVED
billing/R1. Removed: the legal name moved to the customer record.
```

- `### ADDED` takes the next free id: one past the highest number the file
  has used, its requirement lines and its tombstones both.
- `### MODIFIED` restates the whole new text under the existing id.
- `### REMOVED` names the id and why it goes.

The session that implements a ticket applies the deltas for the ids its
ticket covers to this file **in the same diff as the test that names
`<area>/R<n>`**, so the living spec and its tests land together or not at
all. A removed requirement leaves a **tombstone** in place of its line:

```md
~~R<n>.~~ Removed by #<PRD>: <why>
```

Struck through, it does not open with `R<n>.`, so it is no requirement and
no test has to name it; kept, it stops the id from being reused.

A PRD for an area with no living spec writes plain `R<n>.` lines and names
its area on an `Area: <area>` line; the first ticket that covers one creates
`docs/specs/<area>.md`, keeping the PRD's numbers.

## The gate

The docs gate (`scripts/check.sh`, in both its engines) fails when a
requirement in `docs/specs/*.md` is named, as `<area>/R<n>`, by no file the
test globs match — `livingSpec.testGlobs` in
`scripts/docs-conformance/config.mjs`. A test names a requirement in its own
name or in a comment beside it. With no living spec the check passes, and it
passes on this README, which holds none.

A name is not an assertion: a test can cite `billing/R2` and check nothing
about it. The review of the diff, and the human who reads it, remain the
check on that.
