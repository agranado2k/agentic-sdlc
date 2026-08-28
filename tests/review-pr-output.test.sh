#!/bin/sh
# The /review-pr OUTPUT CONTRACT (#63), checked as TEXT — the same honest
# boundary as tests/implement-deliver.test.sh: the skill is a document, so the
# external behavior IS the text. This suite pins the tokens an agent following
# the document must emit; it never simulates a review (a mocked review proves
# only that the mock ran).
#
# What it holds (PRD #62):
#   1. Summary first — a verdict line, a severity count table with a badge
#      column, and a clean-audits roll-up, specified BEFORE any finding detail.
#   2. Severity has a markdown-native color: 🔴 CRITICAL / 🟠 HIGH / 🟡 MEDIUM /
#      🔵 LOW, badge always redundant to the text label (never the only channel).
#   3. Finding anatomy — a mandatory what/where line (bold ID + code-span
#      anchor), an optional citation line, an optional fix line, evidence
#      folded into a details element.
#   4. The axes stay visually disjoint: no confirm-list glyph inside the §5
#      region, no circle badge inside the §5b region.
#   5. Machine invariants survive the redesign: C/H/M/L buckets and INITIAL-N
#      ids, the confirm-list's glyph-first line shape and 🔀→⚠️→✅ order, one
#      top-level comment for Axis 2, inline-only for Axis 1, no ANSI anywhere,
#      the tone rules that keep the report format out of PR threads.
#
# Usage: sh tests/review-pr-output.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

SKILL=".claude/skills/review-pr/SKILL.md"
SKILL_ABS="$ROOT/$SKILL"

cd "$ROOT" || exit 2

line_of() { grep -nF -- "$1" "$SKILL_ABS" | head -1 | cut -d: -f1; }

# region <start-re> <end-re> — the lines from the first match of start to the
# first match of end (exclusive of nothing; sed range). Used to hold the two
# axes' sections to DISJOINT glyph vocabularies.
region() { sed -n "/$1/,/$2/p" "$SKILL_ABS"; }

# ---------------------------------------------------------------------------
banner "0. The file under test"
# ---------------------------------------------------------------------------
[ -f "$SKILL_ABS" ] && pass "$SKILL exists" || {
	fail "$SKILL is missing — nothing else in this suite means anything"
	t_done "/review-pr output contract"
}

# ---------------------------------------------------------------------------
banner "1. Summary first: verdict, badge count table, clean-audits roll-up"
# ---------------------------------------------------------------------------
assert_file_has "$SKILL" "**Verdict:**"
assert_file_has "$SKILL" "Clean audits:"
assert_file_has "$SKILL" "| | Severity | Count |"

# Anchored INSIDE the summary template, not on a prose mention: verdict, then
# clean-audits, then the count table, all between the template's own header and
# the findings paragraph. (The first shape anchored on prose and one mutant —
# verdict moved out of the fence — survived; found by the review of PR #66.)
rs=$(line_of "### Review Summary")
v=$(line_of "**Verdict:**")
c=$(line_of "Clean audits:")
th=$(line_of "| | Severity | Count |")
tf=$(line_of "**Then the findings**")
if [ -n "$rs" ] && [ -n "$v" ] && [ -n "$c" ] && [ -n "$th" ] && [ -n "$tf" ] &&
	[ "$rs" -lt "$v" ] && [ "$v" -lt "$c" ] && [ "$c" -lt "$th" ] && [ "$th" -lt "$tf" ]; then
	pass "summary template order holds: header ($rs) < verdict ($v) < clean audits ($c) < count table ($th) < findings ($tf)"
else
	fail "summary-first broke — header='$rs' verdict='$v' clean-audits='$c' table='$th' findings='$tf'"
fi

# All four sections always appear; an empty one states its emptiness (operator
# amendment to PRD #62 at the PR #66 confirm-list: sections are kept, absence
# is stated, the count table's zeros remain the numeric record).
assert_file_has "$SKILL" "all four severity sections, always"
assert_file_has "$SKILL" "— none found."

# ---------------------------------------------------------------------------
banner "2. Severity badges — color as REDUNDANT encoding, all four buckets"
# ---------------------------------------------------------------------------
for pair in "🔴 CRITICAL" "🟠 HIGH" "🟡 MEDIUM" "🔵 LOW"; do
	assert_file_has "$SKILL" "$pair"
done
# The principle itself must survive in prose, or the next edit drops the label
# and encodes severity in color alone.
assert_file_has "$SKILL" "never the only channel"

# ---------------------------------------------------------------------------
banner "3. Finding anatomy: what/where line, citation, fix line, evidence fold"
# ---------------------------------------------------------------------------
assert_file_has "$SKILL" "↳ fix:"
assert_file_has "$SKILL" "↳ cites:"
assert_file_has "$SKILL" "<details>"
assert_file_has "$SKILL" "file:line"
# The ID scheme is a machine invariant — /pr-iterate cites findings across
# iterations and commit messages by these ids.
assert_file_has "$SKILL" "INITIAL-N"
assert_file_has "$SKILL" "Numbering resets per category"
assert_file_has "$SKILL" "**H-1**"

# ---------------------------------------------------------------------------
banner "4. The axes' glyph vocabularies are disjoint on the page"
# ---------------------------------------------------------------------------
axis1=$(region '^### 5\. ' '^### 5b\.')
axis2=$(region '^### 5b\.' '^### 6\.')
[ -n "$axis1" ] && pass "the §5 region is extractable" ||
	fail "the §5 region is empty — the section headers moved and this suite lost them"
[ -n "$axis2" ] && pass "the §5b region is extractable" ||
	fail "the §5b region is empty — the section headers moved and this suite lost them"

for glyph in "✅" "⚠️" "❌" "🔀" "🧬"; do
	case "$axis1" in
	*"$glyph"*) fail "the §5 (Axis 1) region contains $glyph — confirm-list glyphs are Axis 2's alone" ;;
	*) pass "the §5 region does not borrow $glyph" ;;
	esac
done
for badge in "🔴" "🟠" "🟡" "🔵"; do
	case "$axis2" in
	*"$badge"*) fail "the §5b (Axis 2) region contains $badge — severity badges are Axis 1's alone" ;;
	*) pass "the §5b region does not borrow $badge" ;;
	esac
done

# ---------------------------------------------------------------------------
banner "5. Machine invariants survive the redesign"
# ---------------------------------------------------------------------------
# The confirm-list's inner shape is what /pr-iterate hard rule 4 lifts verbatim.
assert_file_has "$SKILL" "🔀 MIXED COMMIT"
assert_file_has "$SKILL" "⚠️ UNSPECIFIED"
assert_file_has "$SKILL" "✅ SPECIFIED"
assert_file_has "$SKILL" "❌ MISSING"
assert_file_has "$SKILL" "🧬 MUTATION"

# Scoped to the §5b region: the same tokens legitimately appear in Agent 7's
# procedure prose, and the ORDER rule is about the template the report emits.
printf '%s\n' "$axis2" >"$SCRATCH/axis2.region"
rline() { grep -nF -- "$1" "$SCRATCH/axis2.region" | head -1 | cut -d: -f1; }
x=$(rline "🔀 MIXED COMMIT")
w=$(rline "⚠️ UNSPECIFIED")
s=$(rline "✅ SPECIFIED")
if [ -n "$x" ] && [ -n "$w" ] && [ -n "$s" ] && [ "$x" -lt "$w" ] && [ "$w" -lt "$s" ]; then
	pass "the confirm-list template keeps its order: 🔀 ($x) before ⚠️ ($w) before ✅ ($s)"
else
	fail "the confirm-list template order broke — 🔀='$x' ⚠️='$w' ✅='$s'"
fi

a5=$(line_of "### 5. Severity-Based")
a5b=$(line_of "### 5b. Behavior Confirm-List")
if [ -n "$a5" ] && [ -n "$a5b" ] && [ "$a5" -lt "$a5b" ]; then
	pass "Axis 1's report (line $a5) is specified before Axis 2's confirm-list (line $a5b)"
else
	fail "axis section order broke — §5='$a5' §5b='$a5b'"
fi

assert_file_has "$SKILL" "exactly ONE top-level PR comment"
assert_file_has "$SKILL" "NEVER create a general/summary PR comment for Axis-1"
# The tone rules are the wall between the report format and PR threads.
assert_file_has "$SKILL" "Do NOT prefix comments with labels"

# The closing restates the verdict so the question is answerable without
# scrolling back up (PRD #62, solution point 6).
assert_file_has "$SKILL" "Restate the verdict"
q=$(line_of "Which severity categories or specific items should I post")
r=$(line_of "Restate the verdict")
# -le, not -lt: the closing may put both on one line, restatement first.
if [ -n "$q" ] && [ -n "$r" ] && [ "$r" -le "$q" ]; then
	pass "the closing restates the verdict (line $r) ahead of the question (line $q)"
else
	fail "the closing question is not preceded by the verdict — restate='$r' question='$q'"
fi

# No ANSI, ever: the output is GFM rendered by two hosts, not a terminal
# program. One escape byte anywhere in the skill is a contract violation.
if grep -q "$(printf '\033')" "$SKILL_ABS"; then
	fail "the skill contains a raw ANSI escape byte — the output contract is markdown-only"
else
	pass "no ANSI escape byte anywhere in the skill"
fi

t_done "/review-pr output contract"
