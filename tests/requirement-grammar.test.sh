#!/bin/sh
# tests/requirement-grammar.test.sh — the requirement-line grammar, once.
#
# What counts as a requirement line, an id, an area and a cited name was
# spelled in six places — the living-spec validator, its POSIX twin in the
# gate, the coverage check, and patterns in three suites — and the
# left-boundary fix (#544) had to land in each (#545). scripts/requirement.lib.sh
# is now the one home on the shell side: the gate's twin, the coverage check
# and the suites source it, and the docs harness's fixture tests hold the
# validator's patterns equal to it (living-spec.test.mjs).
#
# This suite pins the grammar's behavior through the module's surface, pins
# the TWO grammars it holds as two — the living spec's and the PRD's differ,
# and a refactor is not the place to unify them — and proves no copy of an id
# pattern survives outside the home. The home also holds the fence rule
# (#557), which the gate's reduced path check, tests/lib.sh and the kit demo
# read through fence_strip; this suite pins it and proves no copy of the
# fence pattern survives either.
#
# Usage: sh tests/requirement-grammar.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

MODULE="scripts/requirement.lib.sh"

# ---------------------------------------------------------------------------
banner "0. The module exists, is sourceable, and is shared layer"
# ---------------------------------------------------------------------------
[ -f "$ROOT/$MODULE" ] && pass "$MODULE exists" || {
	fail "$MODULE is missing — nothing else in this suite means anything"
	t_done "requirement grammar"
}
# shellcheck disable=SC1090
. "$ROOT/$MODULE"
for fn in req_spec_lines req_spec_ids req_prd_ids fence_strip; do
	command -v "$fn" >/dev/null 2>&1 && pass "sourcing defines $fn" ||
		fail "sourcing $MODULE does not define $fn"
done
for v in REQ_AREA_ERE REQ_FENCE_ERE REQ_LINE_ERE REQ_CITED_NAME_ERE REQ_CITED_TOKEN_ERE \
	REQ_PRD_ID_ERE REQ_PRD_LINE_ERE REQ_BOUNDED_ID_ERE REQ_ID_AREA_MAX REQ_ID_NUM_MAX; do
	eval "val=\${$v:-}"
	[ -n "$val" ] && pass "sourcing sets $v" || fail "sourcing $MODULE leaves $v empty"
done
manifest_section files <"$ROOT/VERSION" | grep -qx "$MODULE" && pass "$MODULE is manifest-listed (shared layer)" ||
	fail "$MODULE is not in VERSION's files: — a consumer's gate would source a file it does not have"

# ---------------------------------------------------------------------------
banner "1. The living spec's grammar (the docs gate's rule, both engines)"
# ---------------------------------------------------------------------------
# A requirement line opens `R<n>.` at the first column, followed by a blank,
# a tab, a carriage return or the line's end; fenced lines are examples, and
# an id is read once. The tab and CR rows are here because they are the two
# characters that reach awk only through -v — a dialect that read them as
# letters would lose those lines.
TAB=$(printf '\t')
CR=$(printf '\r')
SPEC="$SCRATCH/spec.md"
{
	printf '# Billing\n'
	printf 'R1. The invoice SHALL carry the legal name.\n'
	printf 'R2.%sTab-separated.\n' "$TAB"
	printf 'R3.%s\n' "$CR"
	printf 'R4.\n'
	printf 'R0. Numbered from zero, which the living spec admits.\n'
	printf '```\nR5. inside a fence\n```\n'
	printf '~~~\nR6. inside a tilde fence\n~~~\n'
	printf ' R7. indented\n'
	printf 'R8a. not an id\n'
	printf 'R9.x glued\n'
	printf '~~R10.~~ Removed by #1: a tombstone\n'
	printf 'billing/R11. area-qualified, which a living spec line is not\n'
	printf 'R1. again\n'
} >"$SPEC"
got=$(req_spec_ids "$SPEC" | tr '\n' ' ')
[ "$got" = "R1 R2 R3 R4 R0 " ] && pass "req_spec_ids reads R1 R2 R3 R4 R0 — fences, indents, glued and tombstoned lines skipped, each id once" ||
	fail "req_spec_ids read '$got', expected 'R1 R2 R3 R4 R0 '"
lines=$(req_spec_lines "$SPEC" | grep -c '')
[ "$lines" = 6 ] && pass "req_spec_lines prints every requirement line, the repeat included (6)" ||
	fail "req_spec_lines printed $lines lines, expected 6"
got=$(printf 'R1. from stdin\n' | req_spec_lines)
[ "$got" = "R1. from stdin" ] && pass "req_spec_lines reads stdin when given no file" ||
	fail "req_spec_lines on stdin printed '$got'"

for a in billing a a1 sub-billing x-9; do
	printf '%s\n' "$a" | LC_ALL=C grep -Eqx "$REQ_AREA_ERE" && pass "area: '$a' is an area" || fail "area: '$a' was refused"
done
for a in Billing 1billing -billing billing_x 'bill ing' ''; do
	printf '%s\n' "$a" | LC_ALL=C grep -Eqx "$REQ_AREA_ERE" && fail "area: '$a' was accepted" || pass "area: '$a' is no area"
done

# The cited name, with both boundaries: the token ERE swallows one offending
# character on either side and the name ERE, anchored, drops the match.
CITED='(billing/R1) Xbilling/R2 9billing/R3 -billing/R4 sub/billing/R5 billing/R6abc billing/R7_x billing/R8.5 billing/R9. billing/R10-x billing/R11-billing/R12'
got=$(printf '%s\n' "$CITED" | LC_ALL=C grep -o -E "$REQ_CITED_TOKEN_ERE" | LC_ALL=C grep -x -E "$REQ_CITED_NAME_ERE" | tr '\n' ' ')
[ "$got" = "billing/R1 billing/R9 billing/R10 billing/R11 " ] &&
	pass "cited names: only billing/R1, R9, R10 and R11 survive both boundaries" ||
	fail "cited names read '$got', expected 'billing/R1 billing/R9 billing/R10 billing/R11 '"

# ---------------------------------------------------------------------------
banner "1b. Fence detection — one rule, for every reader of a markdown line"
# ---------------------------------------------------------------------------
# A line whose first non-blank characters are ``` or ~~~ toggles a fence, and
# every line from one such line to the next is quoted material: the living
# spec's reader skips it, and so do the code-span readers — the gate's reduced
# path check, the suites' skill spans and the kit demo's manual commands
# (#557). fence_strip is that rule as a reader. It TOGGLES on either marker,
# so a ``` line inside a ~~~ block closes it: pinned as the behavior the
# readers had, not endorsed — unifying it with the docs harness's paired
# reading is a behavior change, its own ticket.
DOC="$SCRATCH/fenced.md"
{
	printf 'before `a`\n'
	printf '```sh\nin backtick fence\n```\n'
	printf 'between\n'
	printf '  ~~~\nin indented tilde fence\n  ~~~\n'
	printf '%s```\nin tab-indented fence\n```\n' "$TAB"
	printf '~~~md\n'
	printf '```\n'
	printf 'after a backtick line inside a tilde block\n'
	printf '```\n'
	printf '~~~\n'
	printf 'x```not a fence\n'
	printf 'after\n'
} >"$DOC"
got=$(fence_strip "$DOC" | tr '\n' '|')
[ "$got" = 'before `a`|between|after a backtick line inside a tilde block|x```not a fence|after|' ] &&
	pass "fence_strip keeps the lines outside every fence, toggling on either marker at any indent" ||
	fail "fence_strip printed '$got'"
got=$(printf '```\nhidden\n```\nshown\n' | fence_strip)
[ "$got" = "shown" ] && pass "fence_strip reads stdin when given no file" || fail "fence_strip on stdin printed '$got'"
printf '```\nunclosed\n' >"$SCRATCH/open.md"
printf 'next file\n' >"$SCRATCH/next.md"
got=$(fence_strip "$SCRATCH/open.md"; fence_strip "$SCRATCH/next.md")
[ "$got" = "next file" ] && pass "an unclosed fence hides the rest of its file and no more — one call per file" ||
	fail "an unclosed fence leaked across calls: '$got'"

# ---------------------------------------------------------------------------
banner "2. The PRD's grammar (the coverage check), bounded"
# ---------------------------------------------------------------------------
PRD="$SCRATCH/prd.md"
A32=abcdefghijklmnopqrstuvwxyzabcdef
A33=${A32}g
{
	printf 'R1. A plain requirement.\n'
	printf 'billing/R2. An area-qualified one.\n'
	printf 'R3.\n'
	printf 'R4.%s\n' "$CR"
	printf 'R5.%sTab is no separator here.\n' "$TAB"
	printf 'R0. Not numbered from one.\n'
	printf '%s/R6. at the area bound\n' "$A32"
	printf '%s/R7. past the area bound\n' "$A33"
	printf 'R123456. at the number bound\n'
	printf 'R1234567. past the number bound\n'
	printf ' R8. indented\n'
	printf 'R1. again\n'
} >"$PRD"
got=$(req_prd_ids "$PRD" | tr '\n' ' ')
want="R1 billing/R2 R3 R4 $A32/R6 R123456 "
[ "$got" = "$want" ] && pass "req_prd_ids reads the bounded ids, the CR-ended line included, each once" ||
	fail "req_prd_ids read '$got', expected '$want'"
for id in R1 R999999 billing/R1 "$A32/R1"; do
	printf '%s\n' "$id" | grep -Eqx "$REQ_BOUNDED_ID_ERE" && pass "bounded id: '$id' is an id" || fail "bounded id: '$id' was refused"
done
for id in R0 R01 R1234567 "$A33/R1" Billing/R1 billing/ "R1 "; do
	printf '%s\n' "$id" | grep -Eqx "$REQ_BOUNDED_ID_ERE" && fail "bounded id: '$id' was accepted" || pass "bounded id: '$id' is no id"
done
[ "$REQ_ID_AREA_MAX" = 32 ] && [ "$REQ_ID_NUM_MAX" = 6 ] && pass "the bounds are 32 area characters and 6 digits" ||
	fail "the bounds moved: area $REQ_ID_AREA_MAX, number $REQ_ID_NUM_MAX"

# ---------------------------------------------------------------------------
banner "3. Two grammars, held as two — the difference is recorded, not unified"
# ---------------------------------------------------------------------------
# The living spec admits R0, a tab and an unbounded id, and no area prefix;
# the PRD admits an area prefix and is bounded. #545 was a refactor, so it
# kept both; a change that merges them changes behavior and is its own ticket.
one() { printf '%s\n' "$1" >"$SCRATCH/one"; }
one 'R0. zero'
[ -n "$(req_spec_ids "$SCRATCH/one")" ] && [ -z "$(req_prd_ids "$SCRATCH/one")" ] &&
	pass "R0. is a living-spec line and no PRD line" || fail "R0. is read alike by both grammars"
one "R1.${TAB}tab"
[ -n "$(req_spec_ids "$SCRATCH/one")" ] && [ -z "$(req_prd_ids "$SCRATCH/one")" ] &&
	pass "a tab after R1. ends a living-spec id and no PRD id" || fail "a tab after R1. is read alike by both grammars"
one 'billing/R1. qualified'
[ -z "$(req_spec_ids "$SCRATCH/one")" ] && [ -n "$(req_prd_ids "$SCRATCH/one")" ] &&
	pass "billing/R1. is a PRD line and no living-spec line" || fail "billing/R1. is read alike by both grammars"
one 'R1234567. long'
[ -n "$(req_spec_ids "$SCRATCH/one")" ] && [ -z "$(req_prd_ids "$SCRATCH/one")" ] &&
	pass "a seven-digit id is a living-spec line and past the PRD's bound" || fail "a seven-digit id is read alike by both grammars"

# ---------------------------------------------------------------------------
banner "4. One home — the readers source it, and no copy survives"
# ---------------------------------------------------------------------------
grep -q 'requirement\.lib\.sh' "$ROOT/scripts/check.sh" && pass "scripts/check.sh sources the home" ||
	fail "scripts/check.sh does not source $MODULE"
grep -q 'requirement\.lib\.sh' "$ROOT/scripts/coverage.sh" && pass "scripts/coverage.sh sources the home" ||
	fail "scripts/coverage.sh does not source $MODULE"
# An id pattern — `R[0-9]` or `R[1-9]` — on a line that is not a comment, in
# any shell script of the kit but the home and this suite, is a copy.
copies() { # <file>... — prints file:line of every id pattern outside a comment
	for f; do
		awk -v f="$f" '/^[ \t]*#/ { next } index($0, "R[0-9]") || index($0, "R[1-9]") { print f ":" FNR }' "$f"
	done
}
stray=$(cd "$ROOT" && for f in scripts/*.sh scripts/*/*.sh tests/*.sh bootstrap.sh .githooks/*; do
	[ -f "$f" ] || continue
	case "$f" in "$MODULE" | tests/requirement-grammar.test.sh) continue ;; esac
	copies "$f"
done)
[ -z "$stray" ] && pass "no shell script outside the home spells an id pattern" ||
	fail "an id pattern is spelled outside $MODULE: $(printf '%s' "$stray" | tr '\n' ' ')"
# …and the scan can go red: a gate with an inline requirement-line pattern is caught.
{ cat "$ROOT/scripts/check.sh"; printf '%s\n' "ids=\$(awk '!fence && /^R[0-9]+[.]/' \"\$spec\")"; } >"$SCRATCH/check.copy"
[ -n "$(copies "$SCRATCH/check.copy")" ] && pass "the scan flags a gate that spells the requirement line inline" ||
	fail "the scan passed a gate with an inline id pattern — the check is vacuous"
# Fence detection is one rule in every reader (#557): the gate's reduced path
# check, tests/lib.sh's skill spans and the kit demo's manual commands call
# fence_strip, and a fence pattern — the ``` and ~~~ alternation — on a line
# that is not a comment, in any shell script of the kit but the home and this
# suite, is a copy.
for f in scripts/check.sh tests/lib.sh tests/kit-demo.sh; do
	grep -q 'fence_strip' "$ROOT/$f" && pass "$f reads fence_strip" || fail "$f does not read fence_strip from $MODULE"
done
fence_copies() { # <file>... — prints file:line of every fence pattern outside a comment
	for f; do
		awk -v f="$f" '/^[ \t]*#/ { next } index($0, "```|~~~") { print f ":" FNR }' "$f"
	done
}
stray=$(cd "$ROOT" && for f in scripts/*.sh scripts/*/*.sh tests/*.sh bootstrap.sh .githooks/*; do
	[ -f "$f" ] || continue
	case "$f" in "$MODULE" | tests/requirement-grammar.test.sh) continue ;; esac
	fence_copies "$f"
done)
[ -z "$stray" ] && pass "no shell script outside the home spells a fence pattern" ||
	fail "a fence pattern is spelled outside $MODULE: $(printf '%s' "$stray" | tr '\n' ' ')"
# …and the scan can go red: a harness that strips fences inline is caught.
{ cat "$ROOT/tests/lib.sh"; printf '%s\n' 'awk '\''/^[ \t]*(```|~~~)/ { fence = !fence; next } !fence { print }'\'' "$f"'; } >"$SCRATCH/lib.copy"
[ -n "$(fence_copies "$SCRATCH/lib.copy")" ] && pass "the scan flags a harness that spells the fence rule inline" ||
	fail "the scan passed a harness with an inline fence pattern — the check is vacuous"

# ---------------------------------------------------------------------------
banner "5. The readers fail CLOSED without the home"
# ---------------------------------------------------------------------------
# The gate's twin (the reduced engine) and the coverage check both need the
# grammar; a consumer whose copy is missing or empty gets a refusal, never a
# zero-requirement pass.
PROJ="$SCRATCH/proj"
t_consumer_from "$ROOT" "$PROJ" "Grammar Fixture" "grammar@example.invalid" --no-dogfood "Grammar Fixture" "A project with a living spec."
cd "$ROOT" || exit 2
git -C "$PROJ" config core.hooksPath .git/no-such-hooks
(cd "$PROJ" && rm -f "$MODULE" && DOCS_CHECK_NO_NODE=1 sh scripts/check.sh >"$SCRATCH/nogrammar.out" 2>&1; echo $? >"$SCRATCH/nogrammar.rc")
[ "$(cat "$SCRATCH/nogrammar.rc")" = 1 ] && grep -q "shared-layer-missing.*requirement" "$SCRATCH/nogrammar.out" &&
	pass "a missing grammar is a red reduced gate (shared-layer-missing), not a silent pass" ||
	{ fail "with the grammar missing the reduced gate exited $(cat "$SCRATCH/nogrammar.rc")"; sed 's/^/        | /' "$SCRATCH/nogrammar.out" | head -8; }
(cd "$PROJ" && printf '#!/bin/sh\n' >"$MODULE" && DOCS_CHECK_NO_NODE=1 sh scripts/check.sh >"$SCRATCH/emptygrammar.out" 2>&1; echo $? >"$SCRATCH/emptygrammar.rc")
[ "$(cat "$SCRATCH/emptygrammar.rc")" = 2 ] && grep -q "req_spec_ids" "$SCRATCH/emptygrammar.out" &&
	pass "a grammar that defines nothing stops the reduced gate with exit 2, naming the function" ||
	{ fail "with an empty grammar the reduced gate exited $(cat "$SCRATCH/emptygrammar.rc") — expected 2"; sed 's/^/        | /' "$SCRATCH/emptygrammar.out" | head -8; }
(cd "$PROJ" && printf '#!/bin/sh\nreq_spec_ids() { :; }\n' >"$MODULE" && DOCS_CHECK_NO_NODE=1 sh scripts/check.sh >"$SCRATCH/nofence.out" 2>&1; echo $? >"$SCRATCH/nofence.rc")
[ "$(cat "$SCRATCH/nofence.rc")" = 2 ] && grep -q "fence_strip" "$SCRATCH/nofence.out" &&
	pass "a grammar without the fence rule stops the reduced gate with exit 2, naming fence_strip" ||
	{ fail "with no fence_strip the reduced gate exited $(cat "$SCRATCH/nofence.rc") — expected 2"; sed 's/^/        | /' "$SCRATCH/nofence.out" | head -8; }
printf 'R1. one\n' >"$SCRATCH/cov.prd"
printf 'Covers: R1\n' >"$SCRATCH/1"
rm -f "$PROJ/$MODULE"
t_run_split sh "$PROJ/scripts/coverage.sh" "$SCRATCH/cov.prd" "$SCRATCH/1"
[ "$S_STATUS" = 2 ] && [ -z "$S_OUT" ] && printf '%s' "$S_ERR" | grep -q 'requirement\.lib\.sh' &&
	pass "the coverage check without its grammar refuses (exit 2), says why, prints nothing" ||
	fail "the coverage check without its grammar: exit $S_STATUS, stdout '$S_OUT', stderr '$S_ERR'"

t_done "requirement grammar"
