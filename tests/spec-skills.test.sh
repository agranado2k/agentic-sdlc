#!/bin/sh
# tests/spec-skills.test.sh — the /to-prd and /to-tickets contracts, checked as TEXT.
#
# The two skills are documents an agent obeys, and what makes them a pipeline
# rather than two prompts is machine-checkable: the PRD template's sections,
# in the order a fresh session reads them; the phrases that carry each rule
# the design-doc lessons added (a one-sentence objective, scenarios as demo
# scripts, numbered EARS-lite requirements and goal-sized stories — each
# assertion naming the PRD #527 requirement it holds — the
# penalty-for-being-wrong filter, later/never on every non-goal,
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
# The retro branch lives beside SKILL.md (#592): one entry point, the rare
# branch in a file it names by relative path.
RETRO_CAND_ABS="$ROOT/.agents/skills/to-tickets/RETRO-CANDIDATES.md"

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
banner "1b. /to-prd asks once before writing an ungrilled PRD (ADR-0012 clause 5, process/R3 process/R4)"
# ---------------------------------------------------------------------------
# The question lives in "Before you start", so it is asked before any step of
# the process runs — and it is one question, not an interview: beyond it the
# skill still synthesizes. The check reads the conversation only; a skill that
# read the trace to decide would break ADR-0008.
grill=$(section_of "$PRD_ABS" "Before you start" | awk '/^- \*\*An ungrilled conversation\.\*\*/ { on = 1; print; next } on && /^- \*\*/ { exit } on')
[ -n "$grill" ] && pass "\"Before you start\" carries the ungrilled-conversation bullet" ||
	fail "\"Before you start\" has no '- **An ungrilled conversation.**' bullet — process/R3's question has no home"
w="the grilling bullet"
t_text_has "$grill" "holds no grilling session" "process/R3: the trigger — what the conversation lacks" "$w"
t_text_has "$grill" "one question" "process/R3: one question, not an interview" "$w"
t_text_has "$grill" "run \`/grill-me\` first?" "process/R3: the question itself" "$w"
t_text_has "$grill" "\`/grill-with-docs\` instead" "process/R3: the substitution" "$w"
t_text_has "$grill" "glossary" "process/R3: the substitution's condition names the glossary" "$w"
t_text_has "$grill" "decision records" "process/R3: … and the decision records" "$w"
t_text_has "$grill" "**Yes**" "process/R3: the accept path" "$w"
t_text_has "$grill" "hand back" "process/R3: yes returns to this skill's synthesis" "$w"
t_text_has "$grill" "**No**" "process/R4: the decline path" "$w"
t_text_has "$grill" "under Open Issues" "process/R4: the decline path lists its guesses where a later session reads them" "$w"
t_text_has "$grill" "would otherwise have guessed" "process/R4: what goes there — the guesses, not a summary" "$w"
t_text_has "$grill" "nobody to answer" "process/R4: a spawned or unattended run, with nobody to answer, takes the decline path" "$w"
t_text_has "$grill" "counts as grilled" "process/R3: only a grilling skill's run counts — a hand-run interview does not" "$w"
t_text_has "$grill" "reads the conversation only" "process/R3: the check's one input" "$w"
t_text_has "$grill" "never the trace" "process/R3: the input it never reads" "$w"
t_text_has "$grill" "ADR-0008" "process/R3: why — no skill reads the trace" "$w"
t_text_has "$grill" "still never interviews" "ADR-0012 clause 11: no clarify loop beyond the one question" "$w"
# The intro's no-interview rule names its one exception, or the two contradict.
intro=$(awk '/^---$/ { n++; next } n == 2 && /^## / { exit } n == 2' "$PRD_ABS")
t_text_has "$intro" "Do NOT interview the user" "the intro keeps its rule" "the intro"
t_text_has "$intro" "one question" "… and names the one question as its exception" "the intro"
# Asked before the process runs: the bullet precedes step 1.
q_line=$(t_line_of "$PRD_ABS" "**An ungrilled conversation.**")
s1_line=$(grep -n '^1\. ' "$PRD_ABS" | head -1 | cut -d: -f1)
[ -n "$q_line" ] && [ -n "$s1_line" ] && [ "$q_line" -lt "$s1_line" ] &&
	pass "the question (line $q_line) is asked before process step 1 (line $s1_line)" ||
	fail "the question does not precede process step 1 — question='$q_line' step1='$s1_line'"
# Never a trace read in the skill: no reader verb of the trace script appears.
for verb in show summary export; do
	grep -qE "trace(\.kit)?\.sh $verb" "$PRD_ABS" &&
		fail "/to-prd names 'trace.sh $verb' — a skill that reads the trace breaks ADR-0008" ||
		pass "/to-prd never reads the trace with '$verb'"
done

# ---------------------------------------------------------------------------
banner "2. The PRD template's sections, in the order a fresh session reads them"
# ---------------------------------------------------------------------------
# The objective is first because it is the line every ticket opens with; open
# issues sit after out-of-scope because a reader decides what the feature is
# before learning what is still undecided about it. Requirements sit between
# the scenarios that walk the system and the decisions that shape its build
# (process/R1, ADR-0012 clause 1).
want="Objective
Problem Statement
Solution
User Stories
Scenarios
Requirements
Implementation Decisions
Testing Decisions
Alternatives Considered
Out of Scope
Open Issues
Further Notes"
got=$(awk '/^<prd-template>/ { on = 1; next } /^<\/prd-template>/ { on = 0 } on && /^## / { sub(/^## /, ""); print }' "$PRD_ABS")
if [ "$got" = "$want" ]; then
	pass "the PRD template carries the twelve sections in order, Requirements between Scenarios and Implementation Decisions (process/R1)"
else
	fail "the PRD template's sections are not the twelve expected, in order (process/R1) — got: $(printf '%s' "$got" | tr '\n' '|')"
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

# The user stories are the why, not the exhaustive list: the requirements are
# that list now (process/R2, ADR-0012 clause 2).
stories=$(section_of "$PRD_ABS" "User Stories")
t_text_has "$stories" "one story per distinct actor goal" "process/R2: the stories' size rule, one per goal rather than a long list"
t_text_has "$stories" "the *why*" "process/R2: what a story is kept for"
t_text_has "$stories" "every requirement serves at least one" "process/R2: the back-reference that keeps stories and requirements joined"
t_text_has "$stories" "are one story" "process/R2: two stories with the same actor and goal merge"
t_text_has "$stories" "a requirement nobody asked for" "process/R2: a requirement serving no story is flagged"
for gone in "LONG" "extremely extensive" "cover all aspects"; do
	printf '%s\n' "$stories" | grep -qF -- "$gone" &&
		fail "process/R2: the User Stories guidance still says '$gone' — the exhaustive list is the requirements' job now" ||
		pass "process/R2: the User Stories guidance no longer says '$gone'"
done

# Each requirement is one observable behavior in EARS-lite, with an id
# numbered from 1 within the PRD (process/R1, ADR-0012 clause 1).
req=$(section_of "$PRD_ABS" "Requirements")
t_text_has "$req" "one observable behavior" "process/R1: a requirement line holds one behavior"
t_text_has "$req" "a test can fail" "process/R1: observable means a test can fail it"
t_text_has "$req" "EARS-lite" "process/R1: the notation is named"
for form in "The <system> SHALL" "WHEN <trigger>, the <system> SHALL" "WHILE <state>," "IF <condition>, THEN" "WHERE <feature>,"; do
	t_text_has "$req" "$form" "process/R1: one of the five EARS-lite forms"
done
t_text_has "$req" '`R<n>`' "process/R1: the id's shape"
t_text_has "$req" "numbered from 1 within the PRD" "process/R1: where the numbering starts and what it is scoped to"
t_text_has "$req" "exhaustive list" "process/R1: the requirements, not the stories, are the exhaustive list"
t_text_has "$req" "is not renumbered" "process/R1: a published id is never renumbered — tickets and tests cite it"
t_text_has "$req" "bundles two behaviors is two requirements" "process/R1: one behavior per line, the bundling rule"
t_text_has "$req" "a number, or dropped" "process/R1: a line no test could fail falls under the quality-word rule"
for n in 1 2 3; do
	printf '%s\n' "$req" | sed -n '/<requirement-example>/,/<\/requirement-example>/p' | grep -Eq "^R$n\. .* SHALL " &&
		pass "process/R1: the example's R$n is an EARS-lite SHALL line" ||
		fail "process/R1: the requirement example has no 'R$n. … SHALL' line — the example drifted from its own forms"
done
printf '%s\n' "$req" | sed -n '/<requirement-example>/,/<\/requirement-example>/p' | grep -Eq '^R1\. ' &&
	pass "process/R1: the requirement example opens at R1, as its rule demands" ||
	fail "process/R1: the requirement example carries no line opening 'R1. ' — the example contradicts its numbering rule"

# Where a living spec exists for the PRD's area, the requirements are deltas
# against it (process/R10, ADR-0012 clause 8): three headings, each with its
# rule; the area-qualified spelling that lets the PRD, the Covers: line and the
# test cite one string; the next free id counted over tombstones too, so an id
# is never reused; and the plain form, with its area named, for an area that
# has no living spec yet.
t_text_has "$req" "**Where a living spec exists for the area" "process/R10: the delta form has its condition"
t_text_has "$req" '`docs/specs/<area>.md`' "process/R10: the living spec is named by its path"
for h in ADDED MODIFIED REMOVED; do
	t_text_has "$req" "\`### $h\`" "process/R10: the $h heading is named"
done
t_text_has "$req" "spelled with its area-qualified id, \`<area>/R<n>.\`" "process/R10: a delta line carries the area-qualified id"
t_text_has "$req" "all cite the same string" "process/R10: one spelling from PRD to Covers: to test"
t_text_has "$req" "under the next free id" "process/R10: ADDED takes the next free id"
t_text_has "$req" "its requirement lines and its tombstones both" "process/R10: the next free id counts the tombstones — ids are never reused"
t_text_has "$req" "its whole new text restated under the id it already has" "process/R10: MODIFIED restates the whole text under the same id"
t_text_has "$req" "the id, and why it goes" "process/R10: REMOVED names the id and why"
t_text_has "$req" "A REMOVED line is still a requirement line" "process/R10: a removal is covered by a ticket like any other requirement"
t_text_has "$req" "**Where no living spec exists for the area**" "process/R10: the plain form has its condition"
t_text_has "$req" "write plain \`R<n>.\` lines" "process/R10: with no living spec, plain ids"
t_text_has "$req" '`Area: <area>`' "process/R10: a plain PRD names its area, so the first ticket knows which file to create"
t_text_has "$req" "the first ticket that covers one creates \`docs/specs/<area>.md\`" "process/R10: who creates the living spec"
t_text_has "$req" "keeping the PRD's numbers" "process/R10: the created file keeps the PRD's ids, so citations stay true"

# The delta example: one area-qualified line under each heading, and the
# coverage check reads the example as three requirements — the template and
# the script that consumes its output agree on the grammar.
delta_ex=$(printf '%s\n' "$req" | sed -n '/<requirement-delta-example>/,/<\/requirement-delta-example>/p')
[ -n "$delta_ex" ] && pass "process/R10: the Requirements section carries a delta example" ||
	fail "process/R10: no <requirement-delta-example> in the Requirements section"
for h in ADDED MODIFIED REMOVED; do
	printf '%s\n' "$delta_ex" | awk -v h="### $h" '$0 == h { getline; print; exit }' | grep -Eq "^$REQ_AREA_ERE/$REQ_PRD_ID_ERE[.] " &&
		pass "process/R10: the example's ### $h is followed by an area-qualified requirement line" ||
		fail "process/R10: the example's ### $h is not followed by a '<area>/R<n>. ' line"
done
ex_dir=$(mktemp -d "${TMPDIR:-/tmp}/spec-skills-delta.XXXXXX")
printf '%s\n' "$delta_ex" >"$ex_dir/prd"
printf 'Covers: none (prefactor)\n' >"$ex_dir/1"
ex_out=$(sh scripts/coverage.sh "$ex_dir/prd" "$ex_dir/1" 2>/dev/null)
rm -rf "$ex_dir"
[ "$(printf '%s\n' "$ex_out" | grep -Ec "^uncovered: $REQ_AREA_ERE/$REQ_PRD_ID_ERE\$")" -eq 3 ] &&
	pass "process/R10: the coverage check reads the delta example as three area-qualified requirements" ||
	fail "process/R10: the coverage check read the delta example as '$ex_out' — the template and the check disagree"

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
# The mechanical rubric's two conditions (ticket #418, retro H1): over two
# windows 4 of 7 PRs from `mechanical` tickets were blocked at their first
# review and rebuilt on a stronger model, 0 of 8 `implementer` PRs were. The
# first rubric line — "checkable definition of done" — admitted refactors
# across many suites, which the suite could verify but the smallest model
# could not produce. So the `mechanical` answer now needs both conditions: the
# ticket names the ONE command whose exit is its oracle, and the change is one
# file or one pattern applied uniformly across many. The conditions gate that
# answer and nothing else (PR #443 review): a ticket that fails one is no hit,
# so the rubric goes on to questions 2, 3 and 4 — a failed condition never
# jumps past the planner and reviewer questions straight to `implementer`.
# The oracle has a home in the ticket — the first line of its Acceptance
# section — which the publish step names. Rule 14 says what a doubt on either
# condition does to the confidence, and the glossary's entry says the same in
# one sentence, so a reader who meets the tier there first meets them too.
rubric=$(section_of "$TIX_ABS" "The tier rubric")
rline1=$(printf '%s\n' "$rubric" | awk '/^1\. / { print; exit }')
[ -n "$rline1" ] && pass "the tier rubric still opens with a numbered first question" ||
	fail "the tier rubric has no numbered first line — the mechanical question is gone"
t_text_has "$rline1" "only when both conditions hold" "the two conditions are both required, not either"
t_text_has "$rline1" "names the one command whose exit is its oracle" "condition one: the oracle is one command, named in the ticket"
t_text_has "$rline1" "first line of its Acceptance section" "condition one says where in the ticket the oracle is written"
t_text_has "$rline1" "one file or one pattern applied uniformly across many" "condition two: the change is one file, or one pattern everywhere"
t_text_has "$rline1" "many files for different reasons" "the refactor the suite verifies but the smallest model cannot produce is named"
t_text_has "$rline1" '"unless"' "a definition of done with an exception in it is not checkable without judgement"
t_text_has "$rline1" '⇒ `mechanical`' "the first line still answers mechanical — the conditions narrow the tier, they do not remove it"
in_order "$rline1" "a failed condition is no hit: the rubric goes on to question 2, after the answer and the conditions" \
	'⇒ `mechanical`' "only when both conditions hold" "many files for different reasons" '"unless"' "no hit" "goes on to question 2"
case $rline1 in
*'`implementer`'* | *'`planner`'* | *'`reviewer`'*) fail "rubric line 1 names a tier other than mechanical — a failed condition must go on to questions 2 to 4, not be sent to one tier" ;;
*) pass "rubric line 1 names no tier but mechanical — a failed condition is sized by questions 2 to 4" ;;
esac
t_text_has "$rubric" "first hit wins" "the rubric still reads first hit wins — a failed condition is simply not a hit"
# A sweep is two tickets (#631, retro-20261007T151351Z): 4 of 22 implementer
# tickets cost over three times the median, each one a rule applied to every
# site of a shape at once. The rubric's sizing guidance splits it.
t_text_has "$rubric" "adds a rule and applies it to every site of a shape is two tickets" "#631: a rule plus its sweep is sized as two tickets"
t_text_has "$rubric" "the rule with its check first, the sweep second" "#631: the order — the rule and its check land before the sweep"
# The oracle forms the rubric names are the ones /implement runs (ticket #510,
# from PR #484's review). Since #468 /implement matches a mechanical ticket's
# oracle line against a closed allow-list in its step 1 and holds anything
# else to the full suite, so a rubric that still offered "one validator" or
# "a diff that must come out empty" stamped tickets whose oracle the reader
# refuses. The list is read from /implement, never a hand copy: each step-1
# entry's name ("the docs gate", "one suite", "the full suite") and its first
# command, where a `sh -c` named by reference is step 4's loop as step 4 spells
# it. The rubric's list — the span between "whose exit is its oracle — " and
# " — as the first line" — holds exactly those entries, `; `-separated outside
# backticks, and each one WHOLE: "<name>, <command>" and not a byte more, so a
# trailing "or make test" is a disagreement, not a passenger.
IMPL_ABS="$ROOT/.agents/skills/implement/SKILL.md"
# The closed list moved, verbatim, to the branch step 1 opens (#593).
IMPL_COVERS_ABS="$ROOT/.agents/skills/implement/COVERS.md"
impl_forms=$(sed -n 's/.*one entry of this closed list of verification commands: \*\*\([^*]*\)\*\*.*/\1/p' "$IMPL_COVERS_ABS")
impl_loop=$(awk '/^4\. / { print; exit }' "$IMPL_ABS" | sed -n "s/.*\(\`sh -c '[^\`]*'\`\).*/\1/p")
if [ -z "$impl_forms" ]; then
	fail "/implement's step 1 branch (COVERS.md) lost 'one entry of this closed list of verification commands: **…**' — the allow-list the rubric is held to; the rubric's oracle list cannot be compared"
elif [ -z "$impl_loop" ]; then
	fail "/implement's step 4 no longer spells the full suite as a \`sh -c '…'\` loop — the full-suite entry the rubric is held to; the rubric's oracle list cannot be compared"
else
	pass "/implement still carries its closed list of oracle forms and step 4's full-suite loop"
fi
# oracle_forms_agree <text> <where> — <text>'s oracle list against the one
# /implement runs, built once as the exact span it must be: each entry
# "<name>, <command>", "; "-joined, "; or " before the last. The comparison
# alone waits on the allow-list (which failed once, above, by its own name
# when missing); the prose assertions after it run either way.
oracle_forms_agree() {
	t_text_has "$1" "outside that list is not \`mechanical\`" "$2 says a ticket whose only honest oracle is outside the list is not mechanical"
	t_text_has "$1" "where the suite is not a \`tests/\` directory of shell scripts, only the docs gate is among them" "$2 says, in one clause, that a project whose suite is not tests/*.sh has only the docs gate"
	t_text_has "$1" "as the first line of its Acceptance section; and the change" "$2 joins its two conditions with the skill's semicolon"
	case $1 in
	*"a diff that must come out empty"* | *"one validator"*) fail "$2 still offers an oracle /implement never matches (a diff, a validator)" ;;
	*) pass "$2 offers no oracle /implement never matches" ;;
	esac
	[ -n "$impl_forms" ] && [ -n "$impl_loop" ] || return 0
	span=$(printf '%s\n' "$1" | sed -n 's/.*whose exit is its oracle — \(.*\) — as the first line of its Acceptance section.*/\1/p')
	want=$(IMPL_FORMS=$impl_forms IMPL_LOOP=$impl_loop awk 'BEGIN {
		s = ENVIRON["IMPL_FORMS"]; n = 0; cur = ""; code = 0
		# split /implement'"'"'s list on "; " outside backticks
		for (i = 1; i <= length(s); i++) {
			c = substr(s, i, 1)
			if (c == "`") code = !code
			if (!code && substr(s, i, 2) == "; ") { E[++n] = cur; cur = ""; i++; continue }
			cur = cur c
		}
		E[++n] = cur
		for (i = 1; i <= n; i++) {
			lab = E[i]; sub(/, .*/, "", lab)
			cmd = ""; if (match(E[i], /`[^`]*`/)) cmd = substr(E[i], RSTART, RLENGTH)
			if (cmd == "`sh -c`") cmd = ENVIRON["IMPL_LOOP"]
			out = out (i == 1 ? "" : (i == n ? "; or " : "; ")) lab ", " cmd
		}
		print out
	}')
	[ -n "$span" ] && [ "$span" = "$want" ] &&
		pass "$2 names exactly the oracle forms /implement runs, each whole" ||
		fail "$2's oracle list is \"$span\", not exactly /implement's \"$want\""
}
oracle_forms_agree "$rline1" "rubric question 1"
t_text_has "$publish" 'the oracle: `<command>`' "the publish step writes a mechanical ticket's oracle as a body line"
in_order "$publish" "the oracle line opens the Acceptance section of a mechanical ticket" \
	'`mechanical`' "Acceptance section" 'the oracle: `<command>`'
t_text_has "$publish" "the one command rubric question 1 names" "the publish step's oracle line points back at the rubric question that asks for it"
draft=$(awk '/^## Procedure/ { on = 1; next } on && /^2\. / { print; exit }' "$TIX_ABS")
t_text_has "$draft" 'the oracle: `<command>`' "step 2 drafts a mechanical ticket's oracle line, so the quiz sees it before the human confirms the tier"
rule8=$(printf '%s\n' "$rules" | grep -F '**No file paths')
t_text_has "$rule8" "oracle line" "rule 8 makes the one exception for a mechanical ticket's oracle line, which names a command and may name its path"
t_text_has "$conf" "A \`mechanical\` stamp with either of the rubric's two conditions in doubt is \`low\`." "rule 14: a doubt on either mechanical condition is a low confidence, never a quiet high"
tier_entry=$(awk '/^- \*\*Tier\*\*/ { on = 1; print; next } on && (/^- \*\*/ || /^  - /) { exit } on { print }' "$ROOT/docs/domain-glossary.md" | tr '\n' ' ' | tr -s ' ')
[ -n "$tier_entry" ] && pass "the glossary carries a **Tier** entry" || fail "docs/domain-glossary.md has no **Tier** entry"
t_text_has "$tier_entry" "one command whose exit is its oracle" "the glossary's tier entry carries condition one"
t_text_has "$tier_entry" "one file or one pattern applied uniformly across many" "the glossary's tier entry carries condition two, with its across-many"
t_text_has "$tier_entry" "many files for different reasons" "the glossary's tier entry names the many-files refactor that fails it"
t_text_has "$tier_entry" '"unless"' "the glossary's tier entry names the definition of done with an exception in it"
t_text_has "$tier_entry" "the rubric's later questions size it" "the glossary's tier entry says a failure is sized by the rest of the rubric, not sent to one tier"
tier_mech=${tier_entry#*A \`mechanical\` stamp}
case $tier_mech in
*'`implementer`'* | *'`planner`'* | *'`reviewer`'*) fail "the glossary's mechanical sentence names a fallback tier — a failure is sized by the rubric's later questions" ;;
*) pass "the glossary's mechanical sentence names no fallback tier" ;;
esac
wf_rubric=$(awk '/^1\. \*\*Is the definition of done checkable/ { on = 1 } on && /^2\. / { exit } on { print }' "$ROOT/constitution/local-workflow.md.template" | tr '\n' ' ' | tr -s ' ')
[ -n "$wf_rubric" ] && pass "the workflow template still carries rubric line 1" || fail "constitution/local-workflow.md.template lost its rubric line 1"
t_text_has "$wf_rubric" "only when both conditions hold" "the workflow template's rubric line 1 requires both mechanical conditions"
t_text_has "$wf_rubric" "one command whose exit is its oracle" "the workflow template's condition one: one oracle command"
t_text_has "$wf_rubric" "first line of its Acceptance section" "the workflow template says where the oracle is written"
t_text_has "$wf_rubric" "one file or one pattern applied uniformly across many" "the workflow template's condition two: one file or one pattern across many"
t_text_has "$wf_rubric" "many files for different reasons" "the workflow template names the many-files refactor that fails it"
t_text_has "$wf_rubric" '"unless"' "the workflow template names the definition of done with an exception in it"
in_order "$wf_rubric" "the workflow template sends a failed condition on to question 2, after the conditions" \
	'⇒ `mechanical`' "only when both conditions hold" "no hit" "question 2"
case $wf_rubric in
*'`implementer`'* | *'`planner`'* | *'`reviewer`'*) fail "the workflow template's rubric line 1 names a tier other than mechanical" ;;
*) pass "the workflow template's rubric line 1 names no tier but mechanical" ;;
esac
oracle_forms_agree "$wf_rubric" "the workflow template's rubric line 1"
# The two tier tables (ticket #467): the kit's (in its kit-own tiers article
# since ADR-0014) and the consumer manual
# template each give a `mechanical` row a signal cell, and #418 left both
# giving the one-condition signal ("the suite is the oracle"). Each cell quotes
# rubric line 1's two conditions in the phrases asserted on it above, and joins
# them as the rubric does — "only when both": a cell reworded to "when either
# holds" still carries both phrases, and is red here on the join.
# mech_signal <manual> — the signal cell of <manual>'s `mechanical` tier row.
mech_signal() { awk -F'|' '/^\| `mechanical` \|/ { print $4; exit }' "$ROOT/$1"; }
for manual in docs/capability-tiers.md constitution/AGENTS.md.template; do
	cell=$(mech_signal "$manual")
	[ -n "$cell" ] && pass "$manual has a \`mechanical\` row with a signal cell" ||
		fail "$manual has no \`mechanical\` row with a signal cell in its tier table"
	t_text_has "$cell" "names the one command whose exit is its oracle" "$manual's mechanical signal carries condition one, in rubric line 1's words" "$manual's mechanical signal"
	t_text_has "$cell" "one file or one pattern applied uniformly across many" "$manual's mechanical signal carries condition two, in rubric line 1's words" "$manual's mechanical signal"
	t_text_has "$cell" "only when both" "$manual's mechanical signal requires both conditions, not either" "$manual's mechanical signal"
	case $cell in
	*"the suite is the oracle"*) fail "$manual's mechanical signal still gives the one-condition signal (\"the suite is the oracle\")" ;;
	*) pass "$manual's mechanical signal no longer gives the one-condition signal" ;;
	esac
done
assert_file_has "$TIX" "across an open issue" "the anti-pattern names the gate it points at"
# The session cap (ticket #483, retro F6): every review-bearing /implement
# session ends at a /review-pr that spawns seven lenses, so two such sessions
# at once ran past the host's concurrent-subagent limit — on #439 and #440
# lenses were refused at it and 13 Agent calls failed. The hand-off says how
# many of the frontier may run at once: the host's limit over the seven,
# rounded down, never below one; the limit is a value the project states,
# never a number the skill bakes in, and a project that states none gets one
# session at a time. A frontier larger than the cap is sequenced, and the quiz
# shows the cap beside the frontier.
handoff=$(awk '/^## Procedure/ { on = 1; next } on && /^5\. / { print; exit }' "$TIX_ABS")
t_text_has "$handoff" "**session cap**" "the hand-off names the session cap under its own bold name"
t_text_has "$handoff" "/review-pr" "the divisor is the review every such session ends at"
# Rule 3 is where an agent first reads that the frontier runs in parallel;
# unqualified, it promises what the hand-off's cap withholds (#514, M-2).
t_text_has "$(rule_n 3)" "up to the session cap the hand-off states (step 5)" "rule 3's parallel frontier is bounded by the session cap"
# The divisor is /review-pr's roster, read from that skill and never a hand
# copy: a lens added or dropped there must move every place this cap spells
# its count, or the formula goes stale under a green suite (#514, L-1).
# A lens is a roster row naming its Agent number: `unattributed` and
# `single-reviewer` are tokens, not spawns (#568).
lenses=$(t_roster_rows "$ROOT/.agents/skills/review-pr/SKILL.md" | grep -c ' — Agent [0-9]')
case $lenses in
5) lens_word=five ;; 6) lens_word=six ;; 7) lens_word=seven ;; 8) lens_word=eight ;; 9) lens_word=nine ;;
*) lens_word="" ;;
esac
[ -n "$lens_word" ] && pass "/review-pr's roster holds $lens_word lenses" ||
	fail "/review-pr's roster holds $lenses lenses — extend the number words in this check"
t_text_has "$handoff" "spawns $lens_word subagents" "the hand-off's lens count is /review-pr's roster"
# The formula is held on its own sentence: across the whole step, the
# rationale sentence's "concurrent-subagent limit" would satisfy the first
# anchor for a formula that divides something else by seven.
formula=$(printf '%s\n' "$handoff" | grep -o 'The cap is [^.]*\.')
in_order "$formula" "the cap is the limit divided by the roster's lenses, rounded down, never below one — in one 'The cap is …' sentence" \
	"concurrent-subagent limit" "divided by $lens_word" "rounded down" "never below one"
t_text_has "$formula" "rounded down and never below one." "the floor ends the formula sentence — nothing qualifies it after"
t_text_has "$handoff" "as the project states it" "the limit is the project's stated value, read where it is written"
t_text_has "$handoff" "never a number this skill names" "no host's number is baked into a skill that ships to every host"
in_order "$handoff" "a project that states no limit is told so" "states no limit" "say so"
t_text_has "$handoff" "name one session at a time as the safe reading" "with no limit stated, one session at a time is the reading named"
t_text_has "$handoff" "is not opened at once: sequence it" "a frontier larger than the cap is sequenced, not opened at once"
in_order "$handoff" "the tickets up to the cap start now, the rest as sessions end" \
	"larger than the cap" "up to the cap" "as sessions end"
# No limit is baked in, held on the session-cap sentences alone — the rest of
# the step may cite a rule by number — and in words as well as digits: the
# only numbers those sentences may spell are one and the roster's count
# (#514, L-3).
cap_text=$(printf '%s\n' "$handoff" | sed -n 's/.*\(how many of that frontier.*as sessions end\.\).*/\1/p')
if [ -z "$cap_text" ]; then
	fail "the hand-off's session-cap sentences ('how many of that frontier' … 'as sessions end.') were not found"
else
	case $cap_text in
	*[0-9]*) fail "the session-cap sentences carry a digit — the limit is the project's value, and the divisor is a word" ;;
	*) pass "the session-cap sentences carry no digit: no limit is baked in" ;;
	esac
	words=$(printf '%s\n' two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen \
		sixteen seventeen eighteen nineteen twenty thirty forty fifty sixty hundred | grep -vx "$lens_word" | paste -sd'|' -)
	if printf '%s\n' "$cap_text" | grep -Eiqw "$words"; then
		fail "the session-cap sentences spell a number other than one and $lens_word — a limit baked in as a word"
	else
		pass "the session-cap sentences spell no number but one and $lens_word"
	fi
fi
in_order "$quiz" "the quiz shows the cap beside the DAG, before the human is asked to challenge it" \
	"the DAG" "the session cap beside the frontier" "ask the user to challenge"
# The place the hand-off reads the limit from exists: the consumer's workflow
# article carries a line for it, a mark the project fills in — or answers
# "unstated", the reading that runs one session at a time.
wf_cap=$(grep -F 'concurrent-subagent limit' "$ROOT/constitution/local-workflow.md.template" | head -n 1)
t_text_has "$wf_cap" "$(t_mark CONCURRENT_SUBAGENT_LIMIT)" "the workflow template states the host's concurrent-subagent limit as a mark the project fills"
t_text_has "$wf_cap" "unstated" "the workflow template names 'unstated' as the answer when the limit is not known"
t_text_has "$handoff" "constitution/local-workflow.md" "the hand-off reads the limit from the workflow article that carries its line"
# The glossary names the concept the hand-off introduces (#483).
cap_entry=$(awk '/^- \*\*Session cap\*\*/ { on = 1; print; next } on && (/^- \*\*/ || /^#/ || /^$/) { exit } on { print }' "$ROOT/docs/domain-glossary.md" | tr '\n' ' ' | tr -s ' ')
[ -n "$cap_entry" ] && pass "the glossary carries a **Session cap** entry" || fail "docs/domain-glossary.md has no **Session cap** entry"
t_text_has "$cap_entry" "concurrent-subagent limit" "the glossary's session-cap entry derives it from the concurrent-subagent limit"
t_text_has "$cap_entry" "/to-tickets" "the glossary's session-cap entry names the skill that states it"
t_text_has "$cap_entry" "the $lens_word lenses" "the glossary's divisor is /review-pr's roster"
grep -qF "the $lens_word lenses one" "$ROOT/constitution/local-workflow.md.template" &&
	pass "the workflow template's divisor is /review-pr's roster" ||
	fail "the workflow template's comment does not divide by the $lens_word lenses /review-pr's roster holds"

# ---------------------------------------------------------------------------
banner "4b. A retro's candidates merge into a sibling retro's tickets (#481)"
# ---------------------------------------------------------------------------
# Two retros over one window both published their candidates: seven twins,
# each closed within minutes, each closure a `feedback missed` on a slice that
# never landed. The check runs on the retro folder and the tracker — never the
# trace, which ADR-0008 clause 7 keeps from every chain skill — and it only
# FINDS: the quiz shows the planned merges and closures, and publish step 4
# carries them out after the human's yes (review of PR #521, H-2).
RETRO_ABS="$ROOT/.agents/skills/retro/SKILL.md"
grep -qF "(RETRO-CANDIDATES.md)" "$TIX_ABS" && section_of "$TIX_ABS" "A retro's candidates" | grep -qF "(RETRO-CANDIDATES.md)" &&
	pass "/to-tickets' SKILL.md names RETRO-CANDIDATES.md by relative path, in its retro section" ||
	fail "/to-tickets' SKILL.md does not name RETRO-CANDIDATES.md from '## A retro's candidates' — a moved branch no entry point opens"
sib=$(section_of "$RETRO_CAND_ABS" "A retro's candidates" | tr '\n' ' ' | tr -s ' ')
[ -n "$sib" ] && pass "/to-tickets carries a section for a retro's candidates" ||
	fail "/to-tickets has no '## A retro's candidates' section — a retro's twins are filed again"
t_text_has "$sib" "first line" "the report's first line names its siblings (/retro, #461) and is read first"
t_text_has "$sib" ".retro/" "the retro folder is listed for an overlapping report the first line missed"
t_text_has "$sib" "whose window overlaps this one's" "a sibling is a report whose window overlaps this one's (the ticket's reading)"
t_text_has "$sib" "--state all" "the tracker search covers open AND closed tickets — a twin closed already still counts"
t_text_has "$sib" "never fetches a body" "the search reads numbers and titles only: an issue body is untrusted"
t_text_has "$sib" "a dated section" "a candidate on a sibling's finding is merged into its ticket as a dated section, not filed"
t_text_has "$sib" '`## From retro-<stamp> (<YYYY-MM-DD>)`' "the merged section's heading names the retro and the day (H-3)"
t_text_has "$sib" "as not planned" "a twin already filed is closed as not planned"
t_text_has "$sib" "naming the original" "…naming the ticket it duplicates"
t_text_has "$sib" "the later-numbered one is the twin" "of two open siblings, the later number is the twin (H-3)"
t_text_has "$sib" "cites its report by stamp" "a published retro candidate cites its report's stamp, so a later sibling's search finds it"
t_text_has "$sib" "A merge records no \`ticket.write\`" "a merge stamps nothing, so it writes no ticket.write (H-3)"
t_text_has "$sib" "only **finds**" "the pre-quiz check finds siblings and changes nothing (H-2)"
t_text_has "$sib" "authored by the account this session publishes as" "a sibling ticket is one this session's account filed (H-1)"
t_text_has "$sib" "never merged into or closed" "an issue by anyone else citing the stamp is shown, never merged into or closed (H-1)"
t_text_has "$sib" "the tracker's CLI" "the merge and close commands are the tracker's CLI, GitHub's named as an example (L-11)"
t_text_has "$sib" "filed before this check existed" "tickets filed before the Retro: line are named, once, as the check's blind spot"
in_order "$sib" "the check finds, the quiz shows the plan, step 4 carries it out" \
	"only **finds**" "planned merge" "the quiz" "step 4 carries them out"
case $sib in
*"it is closed as not planned"* | *"it becomes **a dated section**"*) fail "the section still merges or closes before the quiz (H-2)" ;;
*) pass "…and no rule in it acts before the quiz" ;;
esac
# Step 4 carries out what the quiz confirmed, before it publishes the new set.
in_order "$publish" "publish step 4 runs the planned merges and closures after the yes, then files the rest" \
	"after the human's yes" "merge_section" "close_twin" "Publish one issue per ticket"
t_text_has "$publish" '`Retro: retro-<stamp>`' "a retro's candidate is published carrying its report's stamp (H-3)"
t_text_has "$publish" "related=retro:" "a retro's candidate records the report, not a PRD, on its ticket.write (L-10)"
t_text_has "$step1" "A retro has no PRD" "step 1 says what stands in for the PRD when the input is a retro report (L-10)"
# The procedure sends a retro's draft through the check before step 3's quiz.
draft=$(awk '/^## Procedure/ { on = 1; next } on && /^2\. / { print; exit }' "$TIX_ABS")
t_text_has "$draft" "A retro's candidates" "the draft step routes a retro report through the sibling check, by the section's name"
# A twin is no landed slice: its closure records no verdict, and the same
# sentence stands wherever a `feedback` event is written or could be.
twin_rule="A ticket closed as a duplicate records no \`feedback\`: feedback is a verdict on a landed slice, and a twin is none."
for f in "$RETRO_CAND_ABS" "$ROOT/.agents/skills/merge-train/SKILL.md" "$ROOT/.agents/skills/pr-iterate/SKILL.md"; do
	tr '\n' ' ' <"$f" | tr -s ' ' | grep -qF -- "$twin_rule" &&
		pass "$(basename "$(dirname "$f")") says a duplicate closure records no feedback" ||
		fail "$(basename "$(dirname "$f")") never says '$twin_rule'"
done
# One window start, one form: /retro writes it on the report's first line, and
# /to-tickets reads it back from there (M-4).
for f in "$RETRO_ABS" "$RETRO_CAND_ABS"; do
	grep -qF -- '`window-start <YYYYMMDDTHHMMSSZ>`' "$f" &&
		pass "$(basename "$(dirname "$f")") names the first line's window-start form" ||
		fail "$(basename "$(dirname "$f")") never names '\`window-start <YYYYMMDDTHHMMSSZ>\`' — the start has no one form"
done

# The section's fence runs: the sibling listing over a scratch retro folder,
# and the tracker calls against a stand-in CLI that records what it was asked.
t_init
fence=$(t_fence "$RETRO_CAND_ABS" holds 'retro_siblings()')
if [ -z "$fence" ]; then
	fail "no sh fence defines retro_siblings() — the listing is prose nobody can run"
else
	printf '%s\n' "$fence" >"$SCRATCH/fence.sh"
	# One listing rule (M-3): /to-tickets' listing is /retro step 5's, the same
	# glob and the same awk program, character for character.
	r_awk=$(grep -o "awk -F/ -v since=[^']*'[^']*'" "$RETRO_ABS" | head -1 | sed "s/^[^']*//")
	t_awk=$(printf '%s\n' "$fence" | grep -o "awk -F/ -v since=[^']*'[^']*'" | head -1 | sed "s/^[^']*//")
	[ -n "$r_awk" ] && [ "$r_awk" = "$t_awk" ] &&
		pass "the sibling listing's awk program is /retro step 5's, verbatim" ||
		fail "the two listings differ: /retro $r_awk, /to-tickets $t_awk"
	glob='/.retro/*/*/retro-*.md 2>/dev/null'
	grep -qF -- "$glob" "$RETRO_ABS" && printf '%s\n' "$fence" | grep -qF -- "$glob" &&
		pass "…and so is the glob it lists" || fail "the two listings do not share the glob '$glob'"

	# window_start reads the first line's named form, and nothing else (M-4).
	printf 'window-start 20261001T150216Z — siblings: none\nbody\n' >"$SCRATCH/report.md"
	got=$( (. "$SCRATCH/fence.sh" && window_start "$SCRATCH/report.md"))
	[ "$got" = 20261001T150216Z ] && pass "window_start reads the start the report's first line opens with" ||
		fail "window_start read '$got' from a first line opening 'window-start 20261001T150216Z'"
	printf 'the window: since 2026-10-01\nwindow-start 20261001T150216Z\n' >"$SCRATCH/report2.md"
	got=$( (. "$SCRATCH/fence.sh" && window_start "$SCRATCH/report2.md")); rc=$?
	[ "$rc" != 0 ] && [ -z "$got" ] && pass "…and a report whose first line does not open with it has no start (a stop)" ||
		fail "window_start read '$got' (exit $rc) from a report whose first line names no start"

	for bad in 'window-start 2026T1Z' 'window-start 1T12345678901234Z' 'window-start 20261001T150216Zab'; do
		printf '%s\n' "$bad" >"$SCRATCH/report3.md"
		got=$( (. "$SCRATCH/fence.sh" && window_start "$SCRATCH/report3.md")); rc=$?
		[ "$rc" != 0 ] && [ -z "$got" ] && pass "…nor a first line '$bad', not a stamp's shape" ||
			fail "window_start read '$got' (exit $rc) from a first line '$bad'"
	done
	mkdir -p "$SCRATCH/root/.retro/2026/09" "$SCRATCH/root/.retro/2026/10" "$SCRATCH/bin"
	for n in 2026/09/retro-20260930T120000Z 2026/10/retro-20261001T150216Z 2026/10/retro-20261001T190528Z \
		2026/10/retro-20261001T191425Z 2026/10/retro-20261002T080718Z 2026/10/retro-2026x \
		2026/10/retro-20261001T200000Z-copy; do
		: >"$SCRATCH/root/.retro/$n.md"
	done
	got=$( (. "$SCRATCH/fence.sh" && retro_siblings "$SCRATCH/root" 20261001T191527Z retro-20261002T080718Z.md) | tr '\n' ' ')
	[ "$got" = "" ] && pass "a window no other report falls in has no sibling" ||
		fail "retro_siblings listed '$got' for a window only this report falls in"
	got=$( (. "$SCRATCH/fence.sh" && retro_siblings "$SCRATCH/root" 20261001T150216Z retro-20261001T191425Z.md) | tr '\n' ' ')
	[ "$got" = "retro-20261001T150216Z retro-20261001T190528Z retro-20261002T080718Z " ] &&
		pass "the siblings are the reports stamped at or after the start — the one stamped AT it included (M-5) — not itself, nor a malformed name" ||
		fail "retro_siblings listed '$got' — wanted 'retro-20261001T150216Z retro-20261001T190528Z retro-20261002T080718Z '"
	# The export beside a report is a csv of the same stamp: no report, no sibling.
	mkdir -p "$SCRATCH/csv/.retro/2026/10"
	: >"$SCRATCH/csv/.retro/2026/10/retro-20261001T195000Z.csv"
	got=$( (. "$SCRATCH/fence.sh" && retro_siblings "$SCRATCH/csv" 20261001T150216Z retro-20261002T080718Z.md) | tr '\n' ' ')
	[ "$got" = "" ] && pass "a retro's csv export in the window, alone in the folder, is no sibling" ||
		fail "retro_siblings listed '$got' from a folder holding only a csv export"

	# The stamp check holds the whole value (M-1), anchored at both ends.
	(. "$SCRATCH/fence.sh" && stamp_ok retro-20261001T190528Z) && pass "stamp_ok takes a report stamp" ||
		fail "stamp_ok refused a report stamp"
	nl='
'
	for bad in "retro-20261001T190528Z${nl}\" in:title OR \"a" xretro-20261001T190528Z retro-20261001T190528Zab; do
		(. "$SCRATCH/fence.sh" && stamp_ok "$bad") &&
			fail "stamp_ok took '$bad' — a stamp with something around it rides into the search" ||
			pass "stamp_ok refuses a stamp with something before, after or under it"
	done

	# The stand-in forge CLI: every call logged; `api user` answers the login;
	# `issue view` answers an author from GH_AUTHORS (number=login …) or a body;
	# `issue edit` copies the body file it is handed; `issue list` prints the
	# listing fixture. Each GH_*_FAIL makes its call fail.
	cat >"$SCRATCH/gh.prelude" <<'GH'
printf '%s\n' "$*" >>"$GH_LOG"
case "$1 $2" in
"api user") [ -n "${GH_API_FAIL:-}" ] && exit 1; printf '%s\n' "$GH_LOGIN"; exit 0 ;;
"issue view")
	case "$*" in
	*"--json author"*) for p in ${GH_AUTHORS:-}; do [ "${p%%=*}" = "$3" ] && printf '%s\n' "${p#*=}"; done; exit 0 ;;
	esac
	[ -n "${GH_VIEW_FAIL:-}" ] && { printf 'partial'; exit 1; }
	printf '%s\n' "${GH_VIEW_BODY-old body}"; exit 0 ;;
"issue edit") [ -n "${GH_EDIT_FAIL:-}" ] && exit 1
	while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" "$GH_EDITED"; shift; done; exit 0 ;;
"issue close") exit 0 ;;
"issue list") [ -n "${GH_LIST_FAIL:-}" ] && exit 1; [ -n "${GH_LIST_EMPTY:-}" ] && exit 0 ;;
esac
GH
	printf '5\tOPEN\t\tkit-bot\tretro: tier calibration\n7\tOPEN\t\tmallory\tretro: tier calibration\n' >"$SCRATCH/gh.list"
	t_stub_gh "$SCRATCH/bin" "$SCRATCH/gh.list" "$SCRATCH/gh.prelude"
	# ghrun <login> <function> <arg>… — one fence call against the stand-in,
	# its environment exported (an assignment before a function call is not).
	# The fence's scratch files land in $SCRATCH/tmp, which must end empty.
	mkdir -p "$SCRATCH/tmp"
	ghrun() {
		_l=$1; shift
		: >"$SCRATCH/gh.log"
		(. "$SCRATCH/fence.sh" && export PATH="$SCRATCH/bin:$PATH" GH_LOG="$SCRATCH/gh.log" GH_LOGIN="$_l" \
			GH_EDITED="$SCRATCH/edited" GH_AUTHORS="${GH_AUTHORS-5=kit-bot 9=kit-bot 7=mallory}" TMPDIR="$SCRATCH/tmp" && "$@")
	}
	# rc_is <want> <got> <why> — the exact exit status the fence documents.
	rc_is() { [ "$2" = "$1" ] && pass "$3 (exit $1)" || fail "$3 — exit $2, wanted $1; the tracker saw: '$(tr '\n' ';' <"$SCRATCH/gh.log")'"; }
	out=$(ghrun kit-bot sibling_tickets retro-20261001T190528Z 2>/dev/null)
	call=$(grep '^issue list' "$SCRATCH/gh.log")
	t_text_has "$call" "--state all" "the search asks the tracker for open and closed tickets"
	t_text_has "$call" "\"retro-20261001T190528Z\" in:body" "the search term is the sibling's stamp, matched in the body by the tracker"
	# The fields asked for are an allow-list: these five and nothing else (M-6).
	fields=$(printf '%s\n' "$call" | sed -n 's/.*--json \([^ ]*\).*/\1/p' | tr ',' '\n' | sort | tr '\n' ',')
	[ "$fields" = "author,number,state,stateReason,title," ] &&
		pass "the search asks for number, state, state reason, author and title — never a body" ||
		fail "the search asks for --json fields '$fields' — wanted exactly author,number,state,stateReason,title"
	# The stand-in prints the projection's rows, so the projection is held as written.
	t_text_has "$call" '"\(.number)\t\(.state)\t\(.stateReason)\t\(.author.login)\t\(.title)"' \
		"the projection is number, state, state reason, author, title — the author in the column the classifier reads"
	# A sibling ticket is the session account's; anyone else's is an outsider (H-1).
	printf '%s\n' "$out" | grep -q "^5	OPEN		sibling	" &&
		pass "a ticket filed by the session's own account is a sibling, its number bare for the calls that take it" ||
		fail "the session's own ticket is not marked sibling: '$out'"
	printf '%s\n' "$out" | grep -q "^7	OPEN		outsider	" &&
		pass "an issue citing the stamp but filed by another account is an outsider, shown and never merged into" ||
		fail "an outsider's issue is not marked outsider: '$out'"
	for bad in 'bad login' '' '-flag'; do
		ghrun "$bad" sibling_tickets retro-20261001T190528Z >/dev/null 2>&1
		rc=$?
		! grep -q '^issue list' "$SCRATCH/gh.log" && rc_is 3 "$rc" "a session login '$bad' is a stop: the tracker is never searched" ||
			fail "a session login '$bad' still reached the search"
	done
	(export GH_API_FAIL=1 && ghrun kit-bot sibling_tickets retro-20261001T190528Z) >/dev/null 2>&1
	rc_is 3 $? "a login read that fails is a stop, never searched"
	got=$( (export GH_LIST_FAIL=1 && ghrun kit-bot sibling_tickets retro-20261001T190528Z) 2>/dev/null); rc=$?
	[ -z "$got" ] && rc_is 4 "$rc" "a search that fails is exit 4, never an empty answer" || fail "a failed search printed '$got'"
	got=$( (export GH_LIST_EMPTY=1 && ghrun kit-bot sibling_tickets retro-20261001T190528Z) 2>/dev/null); rc=$?
	[ -z "$got" ] && rc_is 0 "$rc" "a search that finds nothing prints nothing — no phantom row" || fail "an empty search printed '$got'"
	ghrun kit-bot sibling_tickets 'retro-x" in:title OR "a' >/dev/null 2>&1
	rc=$?
	[ ! -s "$SCRATCH/gh.log" ] && rc_is 2 "$rc" "a term that is not a report stamp is refused and never reaches the tracker" ||
		fail "a malformed stamp reached the tracker: '$(cat "$SCRATCH/gh.log")'"

	# The merge appends the dated section to the body it read, and a failed or
	# empty read is a stop, never an edit (M-2) — as is a target another
	# account filed, whichever list named it.
	printf '## From retro-20261002T080718Z (2026-10-02)\nthe evidence\n' >"$SCRATCH/section"
	rm -f "$SCRATCH/edited"
	ghrun kit-bot merge_section 5 "$SCRATCH/section" >/dev/null 2>&1
	rc_is 0 $? "merge_section succeeds on the session's own ticket"
	grep -q '^old body' "$SCRATCH/edited" 2>/dev/null && grep -q '^## From retro-20261002T080718Z' "$SCRATCH/edited" &&
		pass "merge_section edits the ticket to its body plus the dated section" ||
		fail "merge_section did not hand the edit the old body and the section"
	for mode in fail empty edit outsider number; do
		rm -f "$SCRATCH/edited"
		case $mode in
		fail) want=1; (export GH_VIEW_FAIL=1 && ghrun kit-bot merge_section 5 "$SCRATCH/section") >/dev/null 2>&1 ;;
		empty) want=1; (export GH_VIEW_BODY='' && ghrun kit-bot merge_section 5 "$SCRATCH/section") >/dev/null 2>&1 ;;
		edit) want=1; (export GH_EDIT_FAIL=1 && ghrun kit-bot merge_section 5 "$SCRATCH/section") >/dev/null 2>&1 ;;
		outsider) want=5; ghrun kit-bot merge_section 7 "$SCRATCH/section" >/dev/null 2>&1 ;;
		number) want=2; ghrun kit-bot merge_section 5x "$SCRATCH/section" >/dev/null 2>&1 ;;
		esac
		rc=$?
		rc_is "$want" "$rc" "merge_section stops on a $mode case"
		[ "$mode" = edit ] || ! grep -q '^issue edit' "$SCRATCH/gh.log" ||
			fail "merge_section's $mode case still edited the ticket"
	done
	[ -z "$(ls -A "$SCRATCH/tmp")" ] && pass "merge_section leaves no scratch file behind, whichever way it ends" ||
		fail "merge_section left '$(ls -A "$SCRATCH/tmp" | tr '\n' ' ')' behind"

	# The twin is the later number, closed as not planned naming the original (H-3).
	ghrun kit-bot close_twin 9 5 >/dev/null 2>&1
	rc_is 0 $? "close_twin closes a twin of the session's own"
	t_text_has "$(cat "$SCRATCH/gh.log")" 'issue close 9 --reason not planned --comment Duplicate of #5' \
		"close_twin closes the later number as not planned, naming the original"
	for args in '5 9' '5 5' '9x 5'; do
		# shellcheck disable=SC2086 # the pair splits on purpose
		ghrun kit-bot close_twin $args >/dev/null 2>&1
		rc=$?
		! grep -q '^issue close' "$SCRATCH/gh.log" && rc_is 2 "$rc" "close_twin refuses '$args' — the twin must be the later number" ||
			fail "close_twin '$args' reached the close"
	done
	ghrun kit-bot close_twin 9 7 >/dev/null 2>&1
	rc=$?
	! grep -q '^issue close' "$SCRATCH/gh.log" && rc_is 5 "$rc" "close_twin refuses an original another account filed" ||
		fail "close_twin closed a ticket as a duplicate of an outsider's"
fi

# ---------------------------------------------------------------------------
banner "4c. Covers: on every ticket, and the coverage check before the quiz (ADR-0012 clauses 3 and 4, process/R5 process/R6)"
# ---------------------------------------------------------------------------
# A ticket names the requirement ids it delivers; the three exempt kinds say
# which they are, on a line the coverage check can tell from a gap. The check
# itself is a script (tests/coverage.test.sh holds its verdicts); what is
# held here is that the skill stamps the line, runs the script by its plain
# name before the human sees the draft, shows both lists, and publishes the
# line the quiz confirmed.
covers=$(printf '%s\n' "$rules" | grep -F '**Covers')
[ -n "$covers" ] && pass "process/R5: a ticket rule titled Covers exists" || fail "process/R5: no ticket rule titled Covers — the stamp has no rule"
w="the Covers rule"
t_text_has "$covers" '`Covers: <id>, <id>`' "process/R5: the line's shape, spelled once" "$w"
t_text_has "$covers" '`<area>/R<n>`' "process/R5: an area-qualified id is a legal entry" "$w"
t_text_has "$covers" '`Covers: none (prefactor)`' "process/R5: the prefactor exemption, spelled as the check reads it" "$w"
t_text_has "$covers" '`Covers: none (open-issue)`' "process/R5: the open-issue exemption" "$w"
t_text_has "$covers" '`Covers: none (release)`' "process/R5: the release exemption" "$w"
t_text_has "$covers" "orphan" "process/R5: a ticket that covers nothing unexempt is named for what it is" "$w"
t_text_has "$covers" "no requirement lines" "process/R5: a PRD written before requirements gets no Covers: lines" "$w"
draft=$(awk '/^## Procedure/ { on = 1; next } on && /^2\. / { print; exit }' "$TIX_ABS")
t_text_has "$draft" "a \`Covers:\` line (rule" "process/R5: the draft step stamps the line, citing its rule" "step 2"
t_text_has "$draft" "named by its draft number" "process/R6: each drafted ticket goes to a file the check can label" "step 2"
t_text_has "$quiz" 'sh scripts/coverage.sh "$scratch/body" "$draft"/' "process/R6: the check runs on the screened copy and the drafts, by the plain script name" "the quiz step"
t_text_has "$quiz" "reads ids only" "process/R7: the check reads ids only — why its output may enter the session" "the quiz step"
t_text_has "$quiz" '`uncovered: <id>`' "process/R6: the uncovered list, as the script prints it" "the quiz step"
t_text_has "$quiz" '`orphan: <n>`' "process/R6: the orphan list, as the script prints it" "the quiz step"
t_text_has "$quiz" "shows both lists" "process/R6: the quiz shows both lists" "the quiz step"
t_text_has "$quiz" "runs again" "process/R6: the check runs again after a Covers: line changes" "the quiz step"
t_text_has "$quiz" "Exit 3" "process/R6: a PRD with no requirement lines is its own answer, not a pass" "the quiz step"
t_text_has "$quiz" "A retro's candidates have no PRD and so no requirements" "process/R5: a retro's candidates, which have no PRD, are outside the check and the line" "the quiz step"
in_order "$quiz" "process/R6: the coverage check runs before the draft is presented" \
	"sh scripts/coverage.sh" "shows both lists" "present the draft"
t_text_has "$publish" "a \`Covers:\` line" "process/R5: the published body carries the Covers: line" "the publish step"
handoff=$(awk '/^## Procedure/ { on = 1; next } on && /^5\. / { print; exit }' "$TIX_ABS")
t_text_has "$handoff" 'rm -rf "${draft:?}"' "the draft files go when the decomposition ends" "step 5"

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
