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
# open-issue gate, the feedback-first ordering and the confidence stamp (its
# three tokens, its wording, the pre-quiz check, the low-first sort) on the
# ticket side; and, as
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

# section_of <file> <## heading> — the section's lines, from its heading up to
# (not including) the next `## ` heading; the same slice the design-brief
# suite takes of the engineering article.
section_of() { sed -n "/^## $2\$/,/^## /p" "$1" | sed '1!{/^## /d;}'; }

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
t_text_has "$obj" "one sentence" "the objective has a length, and it is one sentence"
t_text_has "$obj" "line every ticket opens with" "the promise /to-tickets' publish step keeps"
t_text_has "$obj" "first line of the PRD" "it is read before the problem is explained"

scen=$(section_of "$PRD_ABS" "Scenarios")
t_text_has "$scen" "walkthrough" "a scenario is the finished system in use, step by step"
t_text_has "$scen" "concrete names" "no placeholders — a walkthrough with <actor> in it is a story, not a scenario"
t_text_has "$scen" "One per major story" "coverage, not a sample"
t_text_has "$scen" "/to-tickets" "the hand-off: who reads the scenarios"
t_text_has "$scen" "not finished thinking about" "a scenario that cannot be walked is the PRD's own finding"
printf '%s\n' "$scen" | sed -n '/<scenario-example>/,/<\/scenario-example>/p' | grep -q '<[a-z]*>' &&
	fail "the scenario example carries a <placeholder> — the rule it illustrates forbids exactly that" ||
	pass "the scenario example uses concrete names, as its rule demands"

impl=$(section_of "$PRD_ABS" "Implementation Decisions")
t_text_has "$impl" "penalty for being wrong" "the filter on what a PRD pins"
t_text_has "$impl" "belongs to the implementing session" "the reversible is left to the session that builds it"
t_text_has "$impl" "one consequence of this" "the file-path rule is derived from the filter, not a peer of it"

t_text_has "$(section_of "$PRD_ABS" "Testing Decisions")" "a number a test can assert" "every quality word becomes measurable, or goes"

alt=$(section_of "$PRD_ABS" "Alternatives Considered")
t_text_has "$alt" "few brief lines" "the article's length rule — exhaustive rejected-idea logs are overkill"
t_text_has "$alt" "plausibly propose again" "the filter on which alternatives are worth recording"
t_text_has "$alt" "docs/adr/" "a durable decision is linked from its record, never repeated"
t_text_has "$alt" "after a human yes" "the PRD references a record; it never writes one on its own authority"

oos=$(section_of "$PRD_ABS" "Out of Scope")
t_text_has "$oos" "with its reason" "a non-goal carries its why"
t_text_has "$oos" "*later*" "deferred is marked, and italic so it scans"
t_text_has "$oos" "*never*" "rejected is marked, and italic so it scans"
t_text_has "$oos" "say what would reopen it" "a deferral names its trigger"

oi=$(section_of "$PRD_ABS" "Open Issues")
t_text_has "$oi" "three lines" "problem / options / next step — the shape, not a free-text note"
t_text_has "$oi" "next step" "an open issue is actionable or it is a TODO"
t_text_has "$oi" "/prototype" "one route: a spike"
t_text_has "$oi" "planner" "one route: a planner ticket"
t_text_has "$oi" "no label" "the third route: a question a human answers, unlabelled by rule 4"
t_text_has "$oi" "move it out" "a resolved issue leaves the section; the tracker keeps the history"
t_text_has "$oi" "open-issue gate" "the back-reference to /to-tickets' rule, by name not by number"

# The menu rule, and the stranger reread before publishing.
assert_file_has "$PRD" "omitted when empty" "an empty section is omitted, never written as N/A"
assert_file_has "$PRD" "reread it as a stranger" "the reread is the rule; its citation is not a substitute for it"
assert_file_has "$PRD" "shared invariant §4" "the reread cites the fresh-context invariant it serves"
assert_file_has "$PRD" "only makes sense with the chat open" "the reread gives the reader a test, not a mood"
reread_line=$(t_line_of "$PRD_ABS" "reread it as a stranger")
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
t_text_has "$rule1" "Scenarios are the first list of demos" "the admission test starts from the PRD's scenarios"
t_text_has "$rule1" "two exceptions" "prefactoring and the open-issue ticket are the only non-demoable tickets"
t_text_has "$rule1" "rule 12" "the second exception is named where the first is"

gate=$(printf '%s\n' "$rules" | grep -i 'open issue' | grep -F 'Blocked by:' | head -1)
[ -n "$gate" ] && pass "one rule names the open issue and the Blocked by: edge together — the gate is one rule" ||
	fail "no single rule names open issue + Blocked by: — the open-issue gate is missing or split"
t_text_has "$gate" "planner" "one route: a planner ticket"
t_text_has "$gate" "/prototype" "one route: a spike"
t_text_has "$gate" "no label" "the question route: unlabelled, so a human answers it"
t_text_has "$gate" "definition of done is the answer recorded" "what the gate ticket demos — the answer, written down"
t_text_has "$gate" "touches no ticket is left where it is" "an open issue that shapes nothing is not a blocker"

order=$(printf '%s\n' "$rules" | grep -F '**Feedback-first ordering.**')
[ -n "$order" ] && pass "the ordering rule exists under its own title" || fail "no rule titled Feedback-first ordering"
t_text_has "$order" "sequence first" "the direction of the rule — first, not last"
t_text_has "$order" "most likely to expose a misunderstanding" "the criterion the order is chosen by"
t_text_has "$order" "thinnest end-to-end slice" "a vertical slice, never the surface as a layer"
t_text_has "$order" "stubbed" "stubbed data is allowed on the way to feedback"

step1=$(awk '/^## Procedure/ { on = 1; next } on && /^1\. / { print; exit }' "$TIX_ABS")
t_text_has "$step1" "Scenarios are the candidate demos" "step 1 reads the PRD's scenarios as the first draft"
t_text_has "$step1" "rule 12" "step 1 also lists the open issues the gate turns into tickets"
quiz=$(awk '/^## Procedure/ { on = 1; next } on && /^3\. / { print; exit }' "$TIX_ABS")
t_text_has "$quiz" "the order you chose" "the decomposer's own ordering choice is put up for challenge"
publish=$(awk '/^## Procedure/ { on = 1; next } on && /^4\. / { print; exit }' "$TIX_ABS")
t_text_has "$publish" "PRD's Objective" "a published ticket opens with the line /to-prd says every ticket carries"
# The confidence stamp (PRD #273): three tokens beside every tier and label
# stamp, described in the PRD's own words; the checker runs on every stamp
# BEFORE the human sees the list; the quiz is sorted low first; and the sort
# is all it does — a confidence that could skip the quiz, or move a label,
# would be an autonomy decision nobody has measured the right to make.
conf=$(printf '%s\n' "$rules" | grep -F '**Confidence')
[ -n "$conf" ] && pass "the confidence rule exists under its own title" || fail "no rule titled Confidence"
t_text_has "$conf" '`Confidence: <low|medium|high>`' "the stamp, spelled once with its three tokens in the vocabulary's order"
# The stamping clauses themselves, not the words: the rule's own title says
# "tier" and "label", so a bare-word probe stays green with the sentence gone.
t_text_has "$conf" 'Each `Tier:` stamp (rule 9)' "it is stamped beside the tier"
t_text_has "$conf" "each autonomy-label decision (rule 4" "and beside the autonomy label — the label or its absence"
t_text_has "$conf" "how sure the stamp looked, never how likely it is right" "the PRD's wording — a confidence is not a probability"
t_text_has "$conf" "sorts the quiz and never skips it" "the one job a confidence has"
t_text_has "$conf" "No autonomy decision reads it" "rule 4 decides the label alone"

# in_order <text> <why> <needle>… — every needle is present, each after the
# one before it.
in_order() {
	_io_text=$1 _io_why=$2 _io_at=0
	shift 2
	for _io_n; do
		_io_i=$(printf '%s\n' "$_io_text" | awk -v n="$_io_n" -v from="$_io_at" '{ i = index(substr($0, from + 1), n); print (i ? i + from : 0); exit }')
		if [ "$_io_i" = 0 ]; then
			fail "$_io_why — '$_io_n' is missing, or comes before what should precede it"
			return
		fi
		_io_at=$_io_i
	done
	pass "$_io_why"
}
t_text_has "$quiz" "sh scripts/vocab.sh 'Tier: <tier>' 'Confidence: <token>'" "the checker is handed the tier stamp with its confidence — the plain script, skills ship unstamped"
t_text_has "$quiz" "sh scripts/vocab.sh 'Label: <ready-for-agent|none>' 'Confidence: <token>'" "and the label stamp with its own"
# "Every stamp" includes the task domain where one was stamped (PR #311): an
# open vocabulary, so the checker holds it to the token shape — which is what
# refuses a model name with a dot in it, or a capitalised word.
t_text_has "$quiz" "'Domain: <token>'" "a stamped domain goes to the checker with the tier it rides on"
in_order "$quiz" "the domain is checked before the list is presented, like the other stamps" \
	"sh scripts/vocab.sh 'Tier: <tier>'" "'Domain: <token>'" "fix what it refuses" "present the draft"
t_text_has "$quiz" "fix what it refuses" "a refused stamp is repaired before the human sees the list"
t_text_has "$quiz" "is not a refusal — say so at the quiz and carry on" "a checker that cannot run is tolerated and said; it never skips the quiz"
t_text_has "$quiz" "low-confidence first" "the sort: the human's attention lands where the draft was unsure"
in_order "$quiz" "the check comes before the list is presented, and the list is sorted" \
	"sh scripts/vocab.sh" "fix what it refuses" "present the draft" "low-confidence first"
t_text_has "$publish" '`Confidence: <token>`' "a published body carries the tier's confidence"
in_order "$publish" "the body's decision lines run Tier, Confidence, Domain" \
	'`Tier: <tier>`' '`Confidence: <token>`' '`Domain: <token>`'
in_order "$publish" "ticket.write carries the confidence beside the pre-quiz tier, on one event" \
	"kind=ticket.write" "data.tier_proposed=" "data.confidence="
# The label's confidence is a second stamp and gets a second key (PR #311):
# PRD #273 scenario 3 reports calibration per field, so a label's confidence
# filed under the tier's key — or not recorded at all — is a row /retro cannot
# print. It sits beside the label it qualifies, as the tier's sits beside the
# pre-quiz tier. The pre-quiz label (ticket #354) sits between them, so /retro
# can read the label's override as it reads the tier's.
in_order "$publish" "ticket.write carries the label, the pre-quiz label, then the label's confidence under its own key" \
	"kind=ticket.write" "data.confidence=" "data.label=" "data.label_proposed=" "data.label_confidence="
t_text_has "$publish" "never folded into \`data.confidence\`" "the two keys are told apart in words"
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
