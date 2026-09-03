#!/bin/sh
# tests/design-brief-skill.test.sh — the /design-brief contract, checked as TEXT.
#
# The skill is a document an agent obeys, so what makes it internally
# consistent is machine-checkable: it names the three anchors the engineering
# article stamps, the design-it-twice discipline and the complexity criterion
# it compares on, the human stop that precedes every write, the decision
# record it produces, and its two entry points; every slash command it names
# resolves to a skill on disk and every repo path it names is real, templated,
# or installed by bootstrap; its frontmatter uses only the fields the Agent
# Skills specification defines; and the harness bridge symlink resolves.
#
# NOT simulable here, and deliberately not faked: a real design brief needs a
# real brief and a human saying yes. The ticket's demo — invoke it on the kit,
# see two candidates, say no, see nothing on disk change — is run by hand and
# quoted in the delivering PR. What IS asserted is the text that drives it.
#
# Usage: sh tests/design-brief-skill.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"

SKILL=".agents/skills/design-brief/SKILL.md"
SKILL_ABS="$ROOT/$SKILL"
SIDECAR=".agents/skills/design-brief/BRIEF-FORMAT.md"

cd "$ROOT" || exit 2

# Code spans outside fenced blocks, one token per line — the same reading the
# other skill suites use.
skill_spans() {
	for f in "$SKILL_ABS" "$ROOT/$SIDECAR"; do
		[ -f "$f" ] || continue
		awk '/^[ \t]*(```|~~~)/ { fence = !fence; next } !fence { print }' "$f"
	done | grep -o '`[^`]*`' | tr -d '`' | tr ' \t' '\n\n'
}

# ---------------------------------------------------------------------------
banner "0. The files under test"
# ---------------------------------------------------------------------------
[ -f "$SKILL_ABS" ] && pass "$SKILL exists" || {
	fail "$SKILL is missing — nothing else in this suite means anything"
	t_done "/design-brief contract"
}
[ -f "$ROOT/$SIDECAR" ] && pass "$SIDECAR exists — the shapes the brief writes live beside the procedure" ||
	fail "$SIDECAR is missing — the skill has nowhere to keep the shapes it writes"
if [ -L "$ROOT/.claude/skills/design-brief" ] && [ -f "$ROOT/.claude/skills/design-brief/SKILL.md" ]; then
	pass "the harness bridge symlink resolves to the canonical skill"
else
	fail "no resolving symlink at .claude/skills/design-brief — the harness that reads only that address is blind to it"
fi

# ---------------------------------------------------------------------------
banner "1. Frontmatter: the open standard's fields, nothing harness-specific"
# ---------------------------------------------------------------------------
t_assert_skill_frontmatter "$(dirname "$SKILL_ABS")"

# ---------------------------------------------------------------------------
banner "2. It records the three anchors the engineering article stamps"
# ---------------------------------------------------------------------------
# The labels come from the template that stamps them, never typed a third
# time: the skill and its sidecar must agree with the document the advisory
# reads.
TEMPLATE="constitution/local-engineering.md.template"
anchors=$(sed -n '/^## Architecture/,/^## /p' "$ROOT/$TEMPLATE" | grep -o '^\*\*[A-Za-z ]*\*\*:' )
n_anchors=$(printf '%s\n' "$anchors" | grep -c .)
[ "$n_anchors" = 3 ] && pass "the template's Architecture section stamps three anchors" ||
	fail "the template's Architecture section stamps $n_anchors anchors, not three — this suite's premise moved"
printf '%s\n' "$anchors" | while IFS= read -r anchor; do
	assert_file_has "$SKILL" "$anchor"
	assert_file_has "$SIDECAR" "$anchor"
done
assert_file_has "$SKILL" "none — "
assert_file_has "$SIDECAR" "none — "
# The sidecar's edge shape is the glossary template's: same relationship word
# on both sides, roles opposite.
assert_file_has "$SIDECAR" "— upstream;"
assert_file_has "$SIDECAR" "— downstream;"
assert_file_has "$SIDECAR" "same relationship word on both lines"

# ---------------------------------------------------------------------------
banner "3. Design it twice, compared on complexity — and a recommendation, not a menu"
# ---------------------------------------------------------------------------
# Anchored on the claims' own tokens, not on common English words a rewrite
# would keep by accident.
assert_file_has "$SKILL" "### 3. Design it twice"
assert_file_has "$SKILL" "*minimise dependencies*"
assert_file_has "$SKILL" "*minimise obscurity*"
assert_file_has "$SKILL" "dependencies plus obscurity"
assert_file_has "$SKILL" "The named risk is"
assert_file_has "$SKILL" "over-application"
assert_file_has "$SKILL" "**core** ("
assert_file_has "$SKILL" "**supporting** ("
assert_file_has "$SKILL" "**generic** ("
assert_file_has "$SKILL" "from both sides"
assert_file_has "$SKILL" "A menu is not a"

# ---------------------------------------------------------------------------
banner "4. The human stop precedes every write"
# ---------------------------------------------------------------------------
assert_file_has "$SKILL" "before writing anything"
assert_file_has "$SKILL" "nothing in the repo tree"
# The stop must come BEFORE the recording step in the procedure's order.
stop_line=$(grep -n "before writing anything" "$SKILL_ABS" | head -1 | cut -d: -f1)
record_line=$(grep -n "^### .*Record" "$SKILL_ABS" | head -1 | cut -d: -f1)
if [ -n "$stop_line" ] && [ -n "$record_line" ] && [ "$stop_line" -lt "$record_line" ]; then
	pass "the stop (line $stop_line) precedes the Record step (line $record_line)"
else
	fail "the stop does not precede the Record step — stop='$stop_line' record='$record_line'"
fi

# ---------------------------------------------------------------------------
banner "5. The decision record, the coexistence clause, and the two entry points"
# ---------------------------------------------------------------------------
assert_file_has "$SKILL" "**One decision record**"
assert_file_has "$SKILL" "**coexistence clause**"
assert_file_has "$SIDECAR" "test-driven development drives every"
assert_file_has "$SKILL" "## Entry points"
assert_file_has "$SKILL" "**Bootstrap hand-back.**"
assert_file_has "$SKILL" "housekeeping"
assert_file_has "$SKILL" "/improve-codebase-architecture"
assert_file_has "$SKILL" "**The context map** in the glossary"
# No model identifier anywhere the skill or its sidecar: the tier resolves it.
if grep -Eiq 'claude-[a-z]+-[0-9]|gpt-[0-9]|gemini-[0-9]|\b(opus|sonnet|haiku) [0-9]' "$SKILL_ABS" "$ROOT/$SIDECAR"; then
	fail "the skill names a model identifier — the tier resolves the model, a ticket outlives the id"
else
	pass "no model identifier in the skill or its sidecar"
fi
# Strategic means Ousterhout here, and the skill says so where a reader meets
# the word first.
assert_file_has "$SKILL" "Ousterhout"
assert_file_has "$SKILL" "context map"

# ---------------------------------------------------------------------------
banner "6. It never lands anything"
# ---------------------------------------------------------------------------
assert_file_lacks "$SKILL" "gh pr merge" "the brief records; it never merges"
assert_file_lacks "$SKILL" "git push" "the brief records; delivery is /implement's"

# ---------------------------------------------------------------------------
banner "7. Every slash command the skill names resolves to a skill on disk"
# ---------------------------------------------------------------------------
# The exemptions are read from the gate's policy file (tests/lib.sh), never
# mirrored: a mirror had already drifted once in this skill's own history.
resolved=0
for cmd in $(skill_spans | grep '^[([{"]*/[a-z]' | grep -o '/[a-z][a-z0-9-]*' | sort -u); do
	t_is_ignored_command "$cmd" && continue
	if [ -f ".agents/skills/${cmd#/}/SKILL.md" ]; then
		resolved=$((resolved + 1))
	else
		fail "$SKILL names $cmd but .agents/skills/${cmd#/}/SKILL.md does not exist"
	fi
done
[ "$resolved" -ge 2 ] &&
	pass "all $resolved slash commands in the skill resolve" ||
	fail "only $resolved commands resolved — the skill should name at least /to-tickets and /improve-codebase-architecture"

# ---------------------------------------------------------------------------
banner "8. Every repo path the skill names is real, templated, or installed"
# ---------------------------------------------------------------------------
path_verdict() {
	p=$1
	[ -e "$ROOT/$p" ] && { echo "exists in this tree"; return 0; }
	[ -e "$ROOT/$p.template" ] && { echo "shipped as $p.template"; return 0; }
	# Only a line that creates or copies the path counts. A comment or the
	# KIT_ONLY deletion list mentioning it proves the opposite of installed.
	grep -F -- "$p" "$ROOT/bootstrap.sh" | grep -v '^[[:space:]]*#' | grep -v '^KIT_ONLY=' |
		grep -Eq '(cp|mkdir|ln|stamp|printf|>|install)' &&
		{ echo "installed by bootstrap.sh"; return 0; }
	return 1
}
checked=0
for tok in $(skill_spans | sed 's/[),.;:]*$//' | grep -v '[<>*$]' | grep '/' | sort -u); do
	case "$tok" in
	constitution/* | scripts/* | docs/* | tests/* | adapters/* | templates/* | .githooks/* | .github/* | .agents/* | .claude/*) ;;
	*) continue ;;
	esac
	checked=$((checked + 1))
	if why=$(path_verdict "$tok"); then
		pass "$tok — $why"
	else
		fail "$SKILL names $tok, which is a dead reference in every consumer project"
	fi
done
[ "$checked" -ge 3 ] && pass "$checked repo paths checked" ||
	fail "only $checked repo paths found — the skill should name the article, the glossary and the decision records"

# ---------------------------------------------------------------------------
banner "9. The roster knows the skill"
# ---------------------------------------------------------------------------
t_assert_skill_in_roster "design-brief"

# ---------------------------------------------------------------------------
banner "10. The entry points are wired, not just named"
# ---------------------------------------------------------------------------
# The skill says where it is invoked from; each of those places must actually
# say so, or the brief is a command nobody is ever sent to.
# The bootstrap Next list and the setup hand-back are asserted where they are
# rendered — tests/kit-demo.sh and tests/setup-demo.sh — not repeated here.
grep -q '/design-brief' "$ROOT/.agents/skills/to-tickets/SKILL.md" &&
	pass "/to-tickets carries the rule that a new abstraction or a crossed edge cites the brief" ||
	fail "/to-tickets never names /design-brief — the planner's re-question rule is missing (ticket #113)"
grep -q '/design-brief' "$ROOT/.agents/skills/improve-codebase-architecture/SKILL.md" &&
	pass "/improve-codebase-architecture names the re-entry into the brief" ||
	fail "/improve-codebase-architecture never names /design-brief (ticket #113)"
grep -q 'strategic programming' "$ROOT/README.md" &&
	pass "README's further reading pins the word to Ousterhout's strategic programming" ||
	fail "README's Ousterhout entry does not name strategic programming (ticket #113)"

t_done "/design-brief contract"
