#!/bin/sh
# lens-slice.config.sh — which changed paths each /review-pr standards lens
# reads. Read by scripts/lens-slice.sh, which /review-pr's coordinator runs once
# per review; the slicer holds the mechanism, this file the policy.
#
# THIS FILE IS YOURS. It is not part of the shared layer (see VERSION), it is
# not overwritten by a kit update, and editing it is the intended workflow. Like
# scripts/vocab.config.sh it ships FILLED: the rules below fit a project laid
# out as the kit is — executable code under scripts/, hooks under .githooks/,
# CI under .github/workflows/, suites under tests/, generated fixtures and
# captured transcripts under a fixtures/ directory. Retune them to your layout;
# the skill does not change.
#
# One `<lens> <include-ERE> [<exclude-ERE>]` record per line, whitespace-
# separated (an ERE needing a space spells it `[ ]`), each matched by awk
# against a changed path: in the slice when the include matches and the
# exclude does not. `.` includes every path; no exclude drops none. A lens with no record reads the whole diff, and so does every lens
# when this variable is empty. The lens names are /review-pr's roster tokens —
# security api-crud pattern simplicity reuse-dry test-hygiene — and a record
# for any other name is refused. The behavior axis is not configurable here:
# it always reads the whole diff.
#
# Defaults (#590): security and api-crud read code that runs — scripts, hooks,
# workflows, the bootstrap entry point and adapters; test-hygiene reads the
# suites; pattern, simplicity and reuse-dry read everything but generated
# fixtures and transcripts, which no author wrote by hand.

LENS_SLICE_RULES='security     ^(scripts/|\.githooks/|\.github/workflows/|adapters/|bootstrap\.sh$)  (^|/)fixtures/
api-crud     ^(scripts/|\.githooks/|\.github/workflows/|adapters/|bootstrap\.sh$)  (^|/)fixtures/
test-hygiene ^tests/  (^|/)fixtures/
pattern      .  (^|/)fixtures/|\.jsonl$
simplicity   .  (^|/)fixtures/|\.jsonl$
reuse-dry    .  (^|/)fixtures/|\.jsonl$'
