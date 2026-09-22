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

# line_of <file> <fixed string> — first matching line number, empty if none.
line_of() { grep -n -F -- "$2" "$1" | head -1 | cut -d: -f1; }

# section_of <file> <## heading> — the section's lines, from its heading up to
# (not including) the next `## ` heading; the same slice the design-brief
# suite takes of the engineering article.
section_of() { sed -n "/^## $2\$/,/^## /p" "$1" | sed '1!{/^## /d;}'; }

# has_in <text> <fixed string> <why> — one pass/fail per token, so a failure
# names the token that went missing rather than the whole block.
has_in() {
	printf '%s\n' "$1" | grep -q -F -- "$2" &&
		pass "'$2' — $3" ||
		fail "never says '$2' — $3"
}

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
# The objective is first because it is the line every ticket opens with; open
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
# The PRD process is numbered without a gap too — a step inserted by hand is
# how the reread could end up after the publish it is meant to precede.
pnums=$(awk '/^## Process/ { on = 1; next } on && /^<prd-template>/ { on = 0 } on && /^[0-9]+\. / { sub(/\..*/, ""); print }' "$PRD_ABS")
pn=$(printf '%s\n' "$pnums" | grep -c .)
[ "$pn" -ge 4 ] && [ "$(printf '%s\n' "$pnums" | tr '\n' ' ')" = "$(awk -v n="$pn" 'BEGIN { for (i = 1; i <= n; i++) printf "%d ", i }')" ] &&
	pass "the $pn process steps are numbered 1..$pn without a gap" ||
	fail "the process steps are not contiguous 1..N with N >= 4 — got: $(printf '%s' "$pnums" | tr '\n' ' ')"

# ---------------------------------------------------------------------------
banner "3. Each PRD rule is carried by its own words, inside its own section"
# ---------------------------------------------------------------------------
# Anchored on the rules' own tokens, not on common English a rewrite would
# keep by accident — and scoped to the section, so a rule cannot drift into
# Further Notes and still count.
obj=$(section_of "$PRD_ABS" "Objective")
has_in "$obj" "one sentence" "the objective has a length, and it is one sentence"
has_in "$obj" "line every ticket opens with" "the promise /to-tickets' publish step keeps"
has_in "$obj" "first line of the PRD" "it is read before the problem is explained"

scen=$(section_of "$PRD_ABS" "Scenarios")
has_in "$scen" "walkthrough" "a scenario is the finished system in use, step by step"
has_in "$scen" "concrete names" "no placeholders — a walkthrough with <actor> in it is a story, not a scenario"
has_in "$scen" "One per major story" "coverage, not a sample"
has_in "$scen" "/to-tickets" "the hand-off: who reads the scenarios"
has_in "$scen" "not finished thinking about" "a scenario that cannot be walked is the PRD's own finding"
printf '%s\n' "$scen" | sed -n '/<scenario-example>/,/<\/scenario-example>/p' | grep -q '<[a-z]*>' &&
	fail "the scenario example carries a <placeholder> — the rule it illustrates forbids exactly that" ||
	pass "the scenario example uses concrete names, as its rule demands"

impl=$(section_of "$PRD_ABS" "Implementation Decisions")
has_in "$impl" "penalty for being wrong" "the filter on what a PRD pins"
has_in "$impl" "belongs to the implementing session" "the reversible is left to the session that builds it"
has_in "$impl" "one consequence of this" "the file-path rule is derived from the filter, not a peer of it"

has_in "$(section_of "$PRD_ABS" "Testing Decisions")" "a number a test can assert" "every quality word becomes measurable, or goes"

alt=$(section_of "$PRD_ABS" "Alternatives Considered")
has_in "$alt" "few brief lines" "the article's length rule — exhaustive rejected-idea logs are overkill"
has_in "$alt" "plausibly propose again" "the filter on which alternatives are worth recording"
has_in "$alt" "docs/adr/" "a durable decision is linked from its record, never repeated"
has_in "$alt" "after a human yes" "the PRD references a record; it never writes one on its own authority"

oos=$(section_of "$PRD_ABS" "Out of Scope")
has_in "$oos" "with its reason" "a non-goal carries its why"
has_in "$oos" "*later*" "deferred is marked, and italic so it scans"
has_in "$oos" "*never*" "rejected is marked, and italic so it scans"
has_in "$oos" "say what would reopen it" "a deferral names its trigger"

oi=$(section_of "$PRD_ABS" "Open Issues")
has_in "$oi" "three lines" "problem / options / next step — the shape, not a free-text note"
has_in "$oi" "next step" "an open issue is actionable or it is a TODO"
has_in "$oi" "/prototype" "one route: a spike"
has_in "$oi" "planner" "one route: a planner ticket"
has_in "$oi" "no label" "the third route: a question a human answers, unlabelled by rule 4"
has_in "$oi" "move it out" "a resolved issue leaves the section; the tracker keeps the history"
has_in "$oi" "open-issue gate" "the back-reference to /to-tickets' rule, by name not by number"

# The menu rule, and the stranger reread before publishing.
assert_file_has "$PRD" "omitted when empty" "an empty section is omitted, never written as N/A"
assert_file_has "$PRD" "reread it as a stranger" "the reread is the rule; its citation is not a substitute for it"
assert_file_has "$PRD" "shared invariant §4" "the reread cites the fresh-context invariant it serves"
assert_file_has "$PRD" "only makes sense with the chat open" "the reread gives the reader a test, not a mood"
reread_line=$(line_of "$PRD_ABS" "reread it as a stranger")
publish_line=$(grep -n '^[0-9]\. .*[Pp]ublish' "$PRD_ABS" | head -1 | cut -d: -f1)
if [ -n "$reread_line" ] && [ -n "$publish_line" ] && [ "$reread_line" -lt "$publish_line" ]; then
	pass "the reread (line $reread_line) precedes the publish step (line $publish_line)"
else
	fail "the reread does not precede the publish step — reread='$reread_line' publish='$publish_line'"
fi

# ---------------------------------------------------------------------------
banner "4. The ticket side: scenarios feed the demo test, open issues gate, order for feedback"
# ---------------------------------------------------------------------------
# Rules stay contiguously numbered, and every numbered rule opens with a bold
# title — a rule inserted by hand has broken both before in another skill's
# history.
rules=$(awk '/^## Rules for every ticket/ { on = 1; next } on && /^## / { on = 0 } on && /^[0-9]+\. / { print }' "$TIX_ABS")
nums=$(printf '%s\n' "$rules" | sed 's/\..*//')
n=$(printf '%s\n' "$nums" | grep -c .)
expect=$(awk -v n="$n" 'BEGIN { for (i = 1; i <= n; i++) printf "%d ", i }')
if [ "$n" -ge 13 ] && [ "$(printf '%s\n' "$nums" | tr '\n' ' ')" = "$expect" ]; then
	pass "the $n ticket rules are numbered 1..$n without a gap"
else
	fail "the ticket rules are not contiguous 1..N with N >= 13 — got: $(printf '%s' "$nums" | tr '\n' ' ')"
fi
untitled=$(printf '%s\n' "$rules" | grep -vc '^[0-9]*\. \*\*')
[ "$untitled" = 0 ] && pass "every ticket rule opens with a bold title" ||
	fail "$untitled ticket rule(s) carry no bold title — a rule a reader cannot cite by name"
rule_n() { printf '%s\n' "$rules" | awk -v k="$1" -F. '$1 == k { print; exit }'; }

rule1=$(rule_n 1)
has_in "$rule1" "Scenarios are the first list of demos" "the admission test starts from the PRD's scenarios"
has_in "$rule1" "two exceptions" "prefactoring and the open-issue ticket are the only non-demoable tickets"
has_in "$rule1" "rule 12" "the second exception is named where the first is"

gate=$(printf '%s\n' "$rules" | grep -i 'open issue' | grep -F 'Blocked by:' | head -1)
[ -n "$gate" ] && pass "one rule names the open issue and the Blocked by: edge together — the gate is one rule" ||
	fail "no single rule names open issue + Blocked by: — the open-issue gate is missing or split"
has_in "$gate" "planner" "one route: a planner ticket"
has_in "$gate" "/prototype" "one route: a spike"
has_in "$gate" "no label" "the question route: unlabelled, so a human answers it"
has_in "$gate" "definition of done is the answer recorded" "what the gate ticket demos — the answer, written down"
has_in "$gate" "touches no ticket is left where it is" "an open issue that shapes nothing is not a blocker"

order=$(printf '%s\n' "$rules" | grep -F '**Feedback-first ordering.**')
[ -n "$order" ] && pass "the ordering rule exists under its own title" || fail "no rule titled Feedback-first ordering"
has_in "$order" "sequence first" "the direction of the rule — first, not last"
has_in "$order" "most likely to expose a misunderstanding" "the criterion the order is chosen by"
has_in "$order" "thinnest end-to-end slice" "a vertical slice, never the surface as a layer"
has_in "$order" "stubbed" "stubbed data is allowed on the way to feedback"

step1=$(awk '/^## Procedure/ { on = 1; next } on && /^1\. / { print; exit }' "$TIX_ABS")
has_in "$step1" "Scenarios are the candidate demos" "step 1 reads the PRD's scenarios as the first draft"
has_in "$step1" "rule 12" "step 1 also lists the open issues the gate turns into tickets"
quiz=$(awk '/^## Procedure/ { on = 1; next } on && /^3\. / { print; exit }' "$TIX_ABS")
has_in "$quiz" "the order you chose" "the decomposer's own ordering choice is put up for challenge"
publish=$(awk '/^## Procedure/ { on = 1; next } on && /^4\. / { print; exit }' "$TIX_ABS")
has_in "$publish" "PRD's Objective" "a published ticket opens with the line /to-prd says every ticket carries"
# docs-demo.sh's three-way merge anchors on this heading; hold it here too.
assert_file_has "$TIX" "## The tier rubric" "the heading the update recipe's worked example merges around"
assert_file_has "$TIX" "across an open issue" "the anti-pattern names the gate it points at"

# ---------------------------------------------------------------------------
banner "5. Every slash command both skills name resolves to a skill on disk"
# ---------------------------------------------------------------------------
t_assert_skill_commands 5 "the pair should name at least /grill-me, /to-tickets, /implement, /prototype and /design-brief" "$PRD_ABS" "$TIX_ABS"

# ---------------------------------------------------------------------------
banner "6. Every repo path both skills name is real, templated, or installed"
# ---------------------------------------------------------------------------
t_assert_skill_paths 3 "the pair should name the glossary, the decision records and the tier policy file" "$PRD_ABS" "$TIX_ABS"

# No model identifier anywhere: the tier resolves it, and a PRD outlives the id.
t_assert_no_model_id "$PRD_ABS" "$TIX_ABS"

t_done "/to-prd and /to-tickets contracts"
