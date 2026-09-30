# Runtime catalogue admission

From a repository, using POSIX sh:

```sh
sh scripts/catalogue.sh check .
sh scripts/catalogue.sh check . path/to/caller.catalogue
```

The default declaration is `scripts/catalogue.config`, relative to the supplied
repository. A caller declaration replaces it completely. Declare every root
active in the session; the command cannot discover which roots a model loaded.
Canonical source is `.agents/skills`. Each immediate skill directory must have
an exact-case `SKILL.md`; all files, including sidecars, belong to its identity.
Source directory symlinks are refused to prevent recursive catalogue cycles.

Declarations are data, never sourced as shell. Blank lines and lines beginning
with `#` are ignored. The first record is `catalogue|1`; following records are:

| Record | Meaning |
| --- | --- |
| `active|ROOT|identical` | A complete linked or byte-identical copy of canonical source |
| `reference|executable|PATH` | Required local file; checked, hashed, never executed |
| `reference|optional|PATH` | Local file checked and hashed when present |
| `reference|example|TEXT` | Illustrative reference, not an executable dependency |
| `reference|external|TEXT` | External reference, never fetched |

At least one active root is required. Relative roots and local references resolve
from the repository; absolute roots permit caller-managed installations. Local
paths use ASCII letters, digits, slash, dot, underscore and hyphen. Empty, dot,
parent and repeated-slash components are refused. Record fields cannot contain
pipes or newlines. Explicit classification avoids treating every prose example
as a command; maintainers must keep executable declarations complete when skills
change. This command verifies declarations, not the completeness of prose analysis.

Every active root must contain exactly the canonical files and directories, with
exact names and matching bytes, including hidden files. Missing, stale, extra and
wrong-case entries fail admission. `identical` includes symlinks and physical
copies. Other transformation modes fail closed. A future transformation mode
must include a versioned reproducible verifier before it can be admitted.

Success exits 0 and prints deterministic pipe records: the declaration path and
git blob hash, each canonical `source` file and hash, each `root` and its canonical
origin/mode, each `active` file and hash, and reference results. The final record
is `admitted|1`. Git hashes are raw bytes (`hash-object --no-filters`), including
uncommitted edits. Compare the complete output for repeat admission of the same
repository/declaration; paths are part of origin identity. No timestamps, trace
history or model identifiers are consulted. Failure exits 2 with an actionable
stderr diagnostic and no admission output. The command does not lock sources:
after edits, admit again. Filesystem admission does not prove model-visible loading.

Fresh bootstrap retains the command and declaration and removes the optional
skill from both source and linked roots when declined. Existing consumers adopt
the mechanism with the wave's release recipe; it is not yet manifest-listed in
this intermediate slice. Scope, review, delivery and resume remain later slices.
