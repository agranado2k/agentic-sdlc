#!/bin/sh
# tests/spec-skills.test.sh — the /to-prd and /to-tickets contracts, checked as TEXT.
#
# The two skills are documents an agent obeys, and what makes them a pipeline
# rather than two prompts is machine-checkable: the PRD template's sections,
# in the order a fresh session reads them; the phrases that carry each rule
# the design-doc lessons added (a one-sentence objective, scenarios as demo
# scripts, the penalty-for-being-wrong filter, later/never on every non-goal,
# open issues with a next step, the stranger reread before publishing); the
# hand-off from the PRD's scenarios to the tickets' admission test; the
# open-issue gate and the feedback-first ordering on the ticket side; and, as
# every skill suite holds, spec-only frontmatter, every command and path
# resolving, and the roster knowing both skills.
#
# NOT simulable here, and deliberately not faked: a real PRD needs a real
# conversation and a real tracker; a real decomposition needs a human at the
# quiz. What IS asserted is the text that drives both.
#
# Usage: sh tests/spec-skills.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"

PRD=".agents/skills/to-prd/SKILL.md"
TIX=".agents/skills/to-tickets/SKILL.md"
PRD_ABS="$ROOT/$PRD"
TIX_ABS="$ROOT/$TIX"

cd "$ROOT" || exit 2

# Code spans outside fenced blocks, one token per line — the same reading the
# other skill suites use.
skill_spans() {
	for f in "$PRD_ABS" "$TIX_ABS"; do
		awk '/^[ \t]*(```|~~~)/ { fence = !fence; next } !fence { print }' "$f"
	done | grep -o '`[^`]*`' | tr -d '`' | tr ' \t' '\n\n'
}

# line_of <file> <fixed string> — first matching line number, empty if none.
line_of() { grep -n -F -- "$2" "$1" | head -1 | cut -d: -f1; }

# ---------------------------------------------------------------------------
banner "0. The files under test"
# ---------------------------------------------------------------------------
for s in to-prd to-tickets; do
	[ -f ".agents/skills/$s/SKILL.md" ] && pass ".agents/skills/$s/SKILL.md exists" || {
		fail ".agents/skills/$s/SKILL.md is missing — nothing else in this suite means anything"
		t_done "/to-prd and /to-tickets contracts"
	}
	if [ -L ".claude/skills/$s" ] && [ -f ".claude/skills/$s/SKILL.md" ]; then
		pass "the harness bridge symlink for /$s resolves to the canonical skill"
	else
		fail "no resolving symlink at .claude/skills/$s — the harness that reads only that address is blind to it"
	fi
done

# ---------------------------------------------------------------------------
banner "1. Frontmatter and roster: the open standard's fields, and the three surfaces"
# ---------------------------------------------------------------------------
t_assert_skill_frontmatter "$(dirname "$PRD_ABS")"
t_assert_skill_frontmatter "$(dirname "$TIX_ABS")"
t_assert_skill_in_roster "to-prd"
t_assert_skill_in_roster "to-tickets"

# ---------------------------------------------------------------------------
banner "2. The PRD template's sections, in the order a fresh session reads them"
# ---------------------------------------------------------------------------
# The objective is first because it is the line every ticket quotes; open
# issues sit after out-of-scope because a reader decides what the feature is
# before learning what is still undecided about it.
want="Objective
Problem Statement
Solution
User Stories
Scenarios
Implementation Decisions
Testing Decisions
Alternatives Considered
Out of Scope
Open Issues
Further Notes"
got=$(awk '/^<prd-template>/ { on = 1; next } /^<\/prd-template>/ { on = 0 } on && /^## / { sub(/^## /, ""); print }' "$PRD_ABS")
if [ "$got" = "$want" ]; then
	pass "the PRD template carries the eleven sections in order"
else
	fail "the PRD template's sections are not the eleven expected, in order — got: $(printf '%s' "$got" | tr '\n' '|')"
fi

# ---------------------------------------------------------------------------
banner "3. Each PRD rule is carried by the phrase that names it"
# ---------------------------------------------------------------------------
# Anchored on the rules' own tokens, not on common English a rewrite would
# keep by accident.
assert_file_has "$PRD" "one sentence"
assert_file_has "$PRD" "penalty for being wrong"
assert_file_has "$PRD" "a number a test can assert"
assert_file_has "$PRD" "*later*"
assert_file_has "$PRD" "*never*"
assert_file_has "$PRD" "next step"
assert_file_has "$PRD" "few brief lines"
assert_file_has "$PRD" "omitted when empty"
# The scenarios section is the hand-off: it must say who reads it.
scen_line=$(line_of "$PRD_ABS" "## Scenarios")
scen_end=$(awk -v s="${scen_line:-0}" 'NR > s && /^## / { print NR; exit }' "$PRD_ABS")
if [ -n "$scen_line" ] && sed -n "${scen_line},${scen_end:-\$}p" "$PRD_ABS" | grep -q '/to-tickets'; then
	pass "the Scenarios section names /to-tickets as its reader"
else
	fail "the Scenarios section does not say /to-tickets reads it — the hand-off is not written down"
fi
# Open issues name their two resolution routes.
oi_line=$(line_of "$PRD_ABS" "## Open Issues")
oi_end=$(awk -v s="${oi_line:-0}" 'NR > s && /^## / { print NR; exit }' "$PRD_ABS")
if [ -n "$oi_line" ] && sed -n "${oi_line},${oi_end:-\$}p" "$PRD_ABS" | grep -q '/prototype' &&
	sed -n "${oi_line},${oi_end:-\$}p" "$PRD_ABS" | grep -q 'planner'; then
	pass "an open issue's next step can be a /prototype spike or a planner ticket"
else
	fail "the Open Issues section does not name /prototype and planner as next steps"
fi
# The stranger reread cites the invariant it serves and precedes publishing.
assert_file_has "$PRD" "shared invariant §4"
reread_line=$(line_of "$PRD_ABS" "shared invariant §4")
publish_line=$(grep -n '^[0-9]\. .*[Pp]ublish' "$PRD_ABS" | head -1 | cut -d: -f1)
if [ -n "$reread_line" ] && [ -n "$publish_line" ] && [ "$reread_line" -lt "$publish_line" ]; then
	pass "the reread (line $reread_line) precedes the publish step (line $publish_line)"
else
	fail "the reread does not precede the publish step — reread='$reread_line' publish='$publish_line'"
fi

# ---------------------------------------------------------------------------
banner "4. The ticket side: scenarios feed the demo test, open issues gate, order for feedback"
# ---------------------------------------------------------------------------
# Rules stay contiguously numbered — a rule inserted by hand has broken this
# before in another skill's history.
nums=$(awk '/^## Rules for every ticket/ { on = 1; next } on && /^## / { on = 0 } on && /^[0-9]+\. \*\*/ { sub(/\..*/, ""); print }' "$TIX_ABS")
n=$(printf '%s\n' "$nums" | grep -c .)
expect=$(seq 1 "$n" | tr '\n' ' ')
if [ "$n" -ge 13 ] && [ "$(printf '%s\n' "$nums" | tr '\n' ' ')" = "$expect" ]; then
	pass "the $n ticket rules are numbered 1..$n without a gap"
else
	fail "the ticket rules are not contiguous 1..N with N >= 13 — got: $(printf '%s' "$nums" | tr '\n' ' ')"
fi
# The open-issue gate: one rule names the input, both routes and the edge.
gate=$(grep -i 'open issue' "$TIX_ABS" | grep -F 'planner' | grep -F '/prototype' | grep -F 'Blocked by:')
[ -n "$gate" ] &&
	pass "one rule turns a constraining open issue into a planner ticket or a /prototype spike that blocks the tickets it shapes" ||
	fail "no single rule names open issue + planner + /prototype + Blocked by: — the open-issue gate is missing or split"
# Feedback-first ordering.
assert_file_has "$TIX" "**Feedback-first ordering.**"
assert_file_has "$TIX" "stubbed"
# Procedure step 1 starts from the PRD's scenarios; the quiz includes the order.
step1=$(awk '/^## Procedure/ { on = 1; next } on && /^1\. / { print; exit }' "$TIX_ABS")
printf '%s\n' "$step1" | grep -q 'Scenarios' &&
	pass "procedure step 1 reads the PRD's Scenarios as the candidate demos" ||
	fail "procedure step 1 does not name the PRD's Scenarios"
quiz=$(awk '/^## Procedure/ { on = 1; next } on && /^3\. / { print; exit }' "$TIX_ABS")
printf '%s\n' "$quiz" | grep -qi 'order' &&
	pass "the quiz asks the user to challenge the order" ||
	fail "the quiz never mentions the order the decomposer chose"
# docs-demo.sh's three-way merge anchors on this heading; hold it here too.
assert_file_has "$TIX" "## The tier rubric"
# Anti-pattern for the gate.
assert_file_has "$TIX" "across an open issue"

# ---------------------------------------------------------------------------
banner "5. Every slash command both skills name resolves to a skill on disk"
# ---------------------------------------------------------------------------
resolved=0
for cmd in $(skill_spans | grep '^[([{"]*/[a-z]' | grep -o '/[a-z][a-z0-9-]*' | sort -u); do
	t_is_ignored_command "$cmd" && continue
	if [ -f ".agents/skills/${cmd#/}/SKILL.md" ]; then
		resolved=$((resolved + 1))
	else
		fail "a spec skill names $cmd but .agents/skills/${cmd#/}/SKILL.md does not exist"
	fi
done
[ "$resolved" -ge 5 ] &&
	pass "all $resolved slash commands in the two skills resolve" ||
	fail "only $resolved commands resolved — the pair should name at least /grill-me, /to-tickets, /implement, /prototype and /design-brief"

# ---------------------------------------------------------------------------
banner "6. Every repo path both skills name is real, templated, or installed"
# ---------------------------------------------------------------------------
path_verdict() {
	p=$1
	[ -e "$ROOT/$p" ] && { echo "exists in this tree"; return 0; }
	[ -e "$ROOT/$p.template" ] && { echo "shipped as $p.template"; return 0; }
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
		fail "a spec skill names $tok, which is a dead reference in every consumer project"
	fi
done
[ "$checked" -ge 3 ] && pass "$checked repo paths checked" ||
	fail "only $checked repo paths found — the pair should name the glossary, the decision records and the tier policy file"

# No model identifier anywhere: the tier resolves it, and a PRD outlives the id.
if grep -Eiq 'claude-[a-z]+-[0-9]|gpt-[0-9]|gemini-[0-9]|\b(opus|sonnet|haiku) [0-9]' "$PRD_ABS" "$TIX_ABS"; then
	fail "a spec skill names a model identifier — the tier resolves the model"
else
	pass "no model identifier in either skill"
fi

t_done "/to-prd and /to-tickets contracts"
