#!/bin/sh
# tests/check-table.test.sh — the check-table reader as a SEAM (process/R46 process/R47).
#
# `sh scripts/check-table.sh <pr-body-file> <ticket-body-file>` reads the
# check table /implement writes into a PR body (the kit's ADR-0037 clause 9)
# against the ticket's `Covers:` and `Test-tier:` lines, and answers one
# question: does every covered requirement have exactly one row, passing, at
# the tier the ticket stamped? Both bodies are untrusted, so the reader prints
# requirement ids, tokens and row numbers ONLY — never a cell's text, never a
# line of either body. Every fixture below carries the canary string, and the
# last section greps both streams of every run for it.
#
# The contract, one outcome per status, and this suite drives each red first:
#   0  every covered id has exactly one row, its result `pass` and its tier
#      the ticket's stamp: NOTHING printed;
#   1  `missing-row:`, `extra-row:`, `tier-differs:`, `fail:` and `skipped:`
#      lines, one id each;
#   2  a row that breaks the grammar or a table past 64 rows, naming the row
#      number on stderr, stdout empty; a usage error or an unreadable file;
#   3  the body carries no table.
#
# What is asserted is the verdict through the script's public surface — its
# arguments, its exit status, its two streams — never its internals.
#
# Usage: sh tests/check-table.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
READER="$KIT/scripts/check-table.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

CANARY='CANARY-q7Zx'
HEAD='| Requirement | Test tier | Result | Evidence |'
SEP='| --- | --- | --- | --- |'
PIN="tests/check-table.test.sh::process/R45@3f9c2e1"

# ticket <printf format> — the ticket body; body <rows…> — a PR body whose
# check table holds the rows given, one argument a row, framed by prose that
# carries the canary; run — the reader on the two.
ticket() { printf "$1" >"$SCRATCH/ticket"; }
body() {
	{
		printf '## What & why\n\n%s prose above the table.\n\n<!-- check-table -->\n%s\n%s\n' "$CANARY" "$HEAD" "$SEP"
		for r; do printf '%s\n' "$r"; done
		printf '\n%s prose below the table.\n\n<!-- explain-diff-appendix -->\n\n%s appendix\n' "$CANARY" "$CANARY"
	} >"$SCRATCH/pr"
}
ALL_OUT=''
run() {
	t_exec sh "$READER" "$SCRATCH/pr" "$SCRATCH/ticket"
	ALL_OUT="$ALL_OUT$T_OUT
$T_ERR
"
}

STD_TICKET="Build the $CANARY thing.\n\nCovers: process/R45, process/R46, process/R47\nTest-tier: process/R45 unit\nTest-tier: process/R46 suite\nTest-tier: process/R47 manual\nTier: implementer\n"
ROW45="| process/R45 | unit | pass | $PIN |"
ROW46="| process/R46 | suite | pass | tests/check-table.test.sh::process/R46@3f9c2e1aa |"
ROW47="| process/R47 | manual | pass | https://github.com/o/r/pull/9#issuecomment-1 |"

# ---------------------------------------------------------------------------
banner "0. The script under test"
# ---------------------------------------------------------------------------
[ -f "$READER" ] && pass "scripts/check-table.sh exists" || {
	fail "scripts/check-table.sh is missing — nothing else in this suite means anything"
	t_done "the check-table reader"
}

# ---------------------------------------------------------------------------
banner "1. Every covered id, one passing row at its stamped tier: exit 0, nothing printed (process/R47)"
# ---------------------------------------------------------------------------
ticket "$STD_TICKET"
body "$ROW45" "$ROW46" "$ROW47"
run
expect_resolved "" "process/R47: a complete, passing table at the stamped tiers — exit 0, stdout empty"
[ -z "$T_ERR" ] && pass "process/R47: and nothing on stderr" || fail "process/R47: stderr should be empty — got '$T_ERR'"

# Rows in any order; cells padded freely; a CRLF body reads the same.
body "|process/R47|manual|pass|https://github.com/o/r/pull/9|" "$ROW46" "|  process/R45  |  unit  |  pass  |  $PIN  |"
run
expect_resolved "" "process/R46: rows in any order and cells padded or not still read"
body "$ROW45" "$ROW46" "$ROW47"
sed 's/$/\r/' "$SCRATCH/pr" >"$SCRATCH/pr.crlf" && mv "$SCRATCH/pr.crlf" "$SCRATCH/pr"
run
expect_resolved "" "process/R47: a CRLF body reads the same as an LF one"

# An id the ticket stamps no tier for takes whatever tier its row names.
ticket "Covers: process/R45, process/R46\nTest-tier: process/R45 unit\n"
body "$ROW45" "| process/R46 | e2e | pass | $PIN |"
run
expect_resolved "" "process/R46: an id with no Test-tier: stamp passes at any tier"

# ---------------------------------------------------------------------------
banner "2. A gap is named, one word and one id a line: exit 1 (process/R47)"
# ---------------------------------------------------------------------------
ticket "$STD_TICKET"
body "$ROW45" "$ROW47"
run
expect_status 1 "process/R47: a covered id with no row exits 1"
expect_out_is "missing-row: process/R46" "process/R47: missing-row: names the id, and nothing else"

body "$ROW45" "$ROW46" "$ROW47" "| process/R48 | unit | pass | $PIN |"
run
expect_status 1 "process/R47: a row for an id the ticket does not cover exits 1"
expect_out_is "extra-row: process/R48" "process/R47: extra-row: names the uncovered id"

body "$ROW45" "$ROW46" "$ROW47" "$ROW45"
run
expect_status 1 "process/R47: two rows for one covered id exit 1 — exactly one row per id"
expect_out_is "extra-row: process/R45" "process/R47: the repeated id is an extra-row:"

body "| process/R45 | suite | pass | $PIN |" "$ROW46" "$ROW47"
run
expect_status 1 "process/R47: a row whose tier is not the ticket's stamp exits 1"
expect_out_is "tier-differs: process/R45" "process/R47: tier-differs: names the id, never either tier"

body "$ROW45" "| process/R46 | suite | fail | $PIN |" "$ROW47"
run
expect_status 1 "process/R47: a failing row exits 1"
expect_out_is "fail: process/R46" "process/R47: fail: names the id"

body "$ROW45" "$ROW46" "| process/R47 | manual | skipped | - |"
run
expect_status 1 "process/R47: a skipped row exits 1 — a manual check awaits the operator"
expect_out_is "skipped: process/R47" "process/R47: skipped: names the id"

# A repeated covered id is judged by its first row, and named extra besides.
body "$ROW45" "| process/R46 | suite | fail | $PIN |" "$ROW47" "$ROW46"
run
expect_status 1 "process/R47: a failing first row with a second row for the same id exits 1"
expect_out_is "fail: process/R46
extra-row: process/R46" "process/R47: … the first row's fail:, then extra-row: for the repeat"

# All five at once: covered ids in the ticket's order, then the extra rows in
# the table's order.
body "| process/R47 | manual | skipped | - |" "| process/R9 | unit | pass | $PIN |" "| process/R45 | e2e | fail | $PIN |"
run
expect_status 1 "process/R47: every word at once exits 1"
expect_out_is "tier-differs: process/R45
fail: process/R45
missing-row: process/R46
skipped: process/R47
extra-row: process/R9" "process/R47: covered ids in the Covers: order, then extra rows in table order"

# A table with no rows owes every covered id.
body
run
expect_status 1 "process/R47: a table with a header and no rows exits 1"
expect_out_is "missing-row: process/R45
missing-row: process/R46
missing-row: process/R47" "process/R47: … and names every covered id missing"

# ---------------------------------------------------------------------------
banner "3. The row grammar: a broken row is exit 2, naming the row (process/R46 process/R47)"
# ---------------------------------------------------------------------------
ticket "$STD_TICKET"
bad_row() {
	body "$ROW45" "$ROW46" "$1"
	run
	expect_status 2 "process/R46: $2 — exit 2"
	expect_out_is "" "process/R46: … nothing on stdout"
	expect_err_has "row 3" "process/R46: … stderr names row 3"
}
bad_row "| process/R47 | manual | pass |" "a row of three cells"
bad_row "| process/R47 | manual | pass | $PIN | extra |" "a row of five cells"
bad_row "| R47 is $CANARY | manual | pass | $PIN |" "a Requirement cell that is no id"
bad_row "| process/R1234567 | manual | pass | $PIN |" "an id past six digits"
bad_row "| process/R47 | integration | pass | $PIN |" "a Test tier no vocabulary holds"
bad_row "| process/R47 | manual | passed | $PIN |" "a Result no vocabulary holds"
bad_row "| process/R47 | manual | pass | - |" "the evidence '-' on a pass row"
bad_row "| process/R47 | manual | fail | - |" "the evidence '-' on a fail row"
bad_row "| process/R47 | manual | pass | tests/x.sh::t@3f9c2e |" "a pin with a six-hex sha"
bad_row "| process/R47 | manual | pass | tests/x.sh::t@3f9c2e1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa |" "a pin with a 41-hex sha"
bad_row "| process/R47 | manual | pass | tests/x.sh::t@3f9c2g1 |" "a pin whose sha is not hex"
bad_row "| process/R47 | manual | pass | tests/x y.sh::t@3f9c2e1 |" "a pin whose path leaves the plain set"
bad_row "| process/R47 | manual | pass | tests/x.sh::\$(id)@3f9c2e1 |" "a pin whose test name leaves the plain set"
bad_row "| process/R47 | manual | pass | ::t@3f9c2e1 |" "a pin with no path"
bad_row "| process/R47 | manual | pass | tests/x.sh@3f9c2e1 |" "a pin with no test"
bad_row "| process/R47 | manual | pass | http://example.com/x |" "an http:// URL"
bad_row "| process/R47 | manual | pass | https:// |" "an https:// URL with nothing after it"
bad_row "| process/R47 | manual | pass | https://example.com/a b |" "a URL with a space"
bad_row "| process/R47 | manual | pass | https://example.com/<b> |" "a URL outside the plain set"
bad_row "| process/R47 | manual | pass | $CANARY |" "evidence that is none of the three shapes"
long=$(printf 'https://example.com/%0181d' 0)
bad_row "| process/R47 | manual | pass | $long |" "a URL of 201 characters"
ok=$(printf 'https://example.com/%0180d' 0)
body "$ROW45" "$ROW46" "| process/R47 | manual | pass | $ok |"
run
expect_resolved "" "process/R46: a URL of exactly 200 characters is evidence"
body "$ROW45" "$ROW46" "| process/R47 | manual | pass | https://example.com/a-b_c.d/e:f#g?h=i&j=%20 |"
run
expect_resolved "" "process/R46: a URL using every character of its plain set is evidence"
body "$ROW45" "$ROW46" "| process/R47 | manual | pass | tests/a-b_c.sh::Some.test_name-1@0123456789abcdef0123456789abcdef01234567 |"
run
expect_resolved "" "process/R46: a pin with a 40-hex sha and the whole plain set is evidence"
body "$ROW45" "$ROW46" "| process/R47 | manual | skipped | $PIN |"
run
expect_status 1 "process/R46: a skipped row may still carry a pin"
expect_out_is "skipped: process/R47" "process/R46: … and reads as skipped"

# The header and the separator are held too.
{
	printf '<!-- check-table -->\n| Requirement | Tier | Result | Evidence |\n%s\n%s\n' "$SEP" "$ROW45"
} >"$SCRATCH/pr"
run
expect_status 2 "process/R46: a header that is not the exact header is exit 2"
expect_err_has "header" "process/R46: … stderr names the header"
{
	printf '<!-- check-table -->\n%s\n| Requirement |\n%s\n' "$HEAD" "$ROW45"
} >"$SCRATCH/pr"
run
expect_status 2 "process/R46: a separator row of the wrong width is exit 2"
expect_err_has "separator" "process/R46: … stderr names the separator"

# Two tables are two answers.
{
	printf '<!-- check-table -->\n%s\n%s\n%s\n\n<!-- check-table -->\n%s\n%s\n%s\n' "$HEAD" "$SEP" "$ROW45" "$HEAD" "$SEP" "$ROW46"
} >"$SCRATCH/pr"
run
expect_status 2 "process/R47: a body with two check-table markers is exit 2"

# ---------------------------------------------------------------------------
banner "4. The 64-row bound: row 65 is exit 2 (process/R47)"
# ---------------------------------------------------------------------------
covers=$(awk 'BEGIN { for (i = 1; i <= 64; i++) printf "%sprocess/R%d", (i > 1 ? ", " : ""), i }')
ticket "Covers: $covers\n"
rows64=$(awk -v pin="$PIN" 'BEGIN { for (i = 1; i <= 64; i++) printf "| process/R%d | unit | pass | %s |\n", i, pin }')
body "$rows64"
run
expect_resolved "" "process/R47: a table of exactly 64 rows is read"
body "$rows64" "| process/R65 | unit | pass | $PIN |"
run
expect_status 2 "process/R47: a table of 65 rows is exit 2"
expect_out_is "" "process/R47: … nothing on stdout"
expect_err_has "row 65" "process/R47: … stderr names row 65"

# ---------------------------------------------------------------------------
banner "5. No table: exit 3 (process/R47)"
# ---------------------------------------------------------------------------
ticket "$STD_TICKET"
printf '## What & why\n\n%s no table here.\n\n%s\n%s\n%s\n' "$CANARY" "$HEAD" "$SEP" "$ROW45" >"$SCRATCH/pr"
run
expect_status 3 "process/R47: a body with no check-table marker is exit 3, even with a bare table in it"
expect_out_is "" "process/R47: … nothing on stdout"
# A table quoted under the appendix marker is the author's narrative, not the
# check table: /implement writes the table above the marker.
printf '## What & why\n\n<!-- explain-diff-appendix -->\n\n<!-- check-table -->\n%s\n%s\n%s\n' "$HEAD" "$SEP" "$ROW45" >"$SCRATCH/pr"
run
expect_status 3 "process/R45: a table below the explain-diff marker is no check table — exit 3"
# A table inside a fence is quoted material.
printf '## What & why\n\n```\n<!-- check-table -->\n%s\n%s\n%s\n```\n' "$HEAD" "$SEP" "$ROW45" >"$SCRATCH/pr"
run
expect_status 3 "process/R47: a table inside a fence is quoted material — exit 3"
# A marker inside a longer line is no marker.
printf 'see <!-- check-table --> below\n%s\n%s\n%s\n' "$HEAD" "$SEP" "$ROW45" >"$SCRATCH/pr"
run
expect_status 3 "process/R47: the marker counts only on a line of its own"

# ---------------------------------------------------------------------------
banner "6. The ticket body: Covers: and Test-tier: read through the grammar (process/R47)"
# ---------------------------------------------------------------------------
body "$ROW45"
ticket "Covers: process/R45\nTest-tier: process/R45 unit\nTest-tier: process/R45 suite\n"
run
expect_status 2 "process/R47: a ticket stamping one id two tiers is exit 2"
expect_out_is "" "process/R47: … nothing on stdout"
ticket "Covers: process/R45\nTest-tier: process/R45 integration\n"
run
expect_status 2 "process/R47: a ticket Test-tier: no vocabulary holds is exit 2"
ticket "Covers: process/R45 and $CANARY\n"
run
expect_status 2 "process/R47: a malformed Covers: line is exit 2"
ticket "Covers: process/R45\nCovers: process/R46\n"
run
expect_status 2 "process/R47: a ticket with two Covers: lines is exit 2"
ticket "Covers: none (release)\n"
run
expect_status 1 "process/R47: an exempt ticket covers nothing, so every row is extra"
expect_out_is "extra-row: process/R45" "process/R47: … extra-row: names it"
ticket "No covers line at all.\n"
run
expect_status 1 "process/R47: a ticket with no Covers: line covers nothing either"
# A wrapped or indented Test-tier: line is prose, never a stamp.
ticket "Covers: process/R45\n- Test-tier: process/R45 suite\n"
run
expect_resolved "" "process/R47: a bulleted Test-tier: line is prose, not a stamp"

# ---------------------------------------------------------------------------
banner "7. Usage and unreadable input: exit 2, nothing on stdout"
# ---------------------------------------------------------------------------
t_exec sh "$READER"
expect_status 2 "no arguments is a usage error"
t_exec sh "$READER" "$SCRATCH/pr"
expect_status 2 "a PR body and no ticket body is a usage error"
t_exec sh "$READER" "$SCRATCH/absent" "$SCRATCH/ticket"
expect_status 2 "an unreadable PR body is exit 2"
expect_out_is "" "… nothing on stdout"
mkdir -p "$SCRATCH/dir"
t_exec sh "$READER" "$SCRATCH/pr" "$SCRATCH/dir"
expect_status 2 "a directory in place of the ticket body is exit 2"
# Without the requirement grammar beside it, the reader refuses rather than
# read nothing.
mkdir -p "$SCRATCH/lone"
cp "$READER" "$SCRATCH/lone/check-table.sh"
t_exec sh "$SCRATCH/lone/check-table.sh" "$SCRATCH/pr" "$SCRATCH/ticket"
expect_status 2 "process/R47: with no scripts/requirement.lib.sh beside it, the reader refuses (exit 2)"

# ---------------------------------------------------------------------------
banner "8. No line of either body reaches either stream (process/R47)"
# ---------------------------------------------------------------------------
case $ALL_OUT in
*"$CANARY"*) fail "process/R47: the canary reached an output stream — a body line leaked" ;;
*) pass "process/R47: across every run above, the canary never reached stdout or stderr" ;;
esac
# Every stdout line of every run is one word and one bounded id, the id
# shape read from the grammar's one home.
. "$KIT/scripts/requirement.lib.sh"
printf '%s\n' "$ALL_OUT" | grep -E '^(missing-row|extra-row|tier-differs|fail|skipped): ' |
	grep -Evx "(missing-row|extra-row|tier-differs|fail|skipped): $REQ_BOUNDED_ID_ERE" >"$SCRATCH/odd"
[ ! -s "$SCRATCH/odd" ] && pass "process/R47: every verdict line is a word and a requirement id, nothing else" ||
	fail "process/R47: a verdict line carried more than a word and an id: $(head -1 "$SCRATCH/odd")"

t_done "the check-table reader"
