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
t_text_has "$handoff" "concurrent-subagent limit" "the cap is derived from the host's concurrent-subagent limit"
t_text_has "$handoff" "/review-pr" "the divisor is the review every such session ends at"
# The formula is held on its own sentence: across the whole step, the
# rationale sentence's "concurrent-subagent limit" would satisfy the first
# anchor for a formula that divides something else by seven.
formula=$(printf '%s\n' "$handoff" | grep -o 'The cap is [^.]*\.')
[ -n "$formula" ] && pass "the hand-off states the cap in a sentence of its own" || fail "the hand-off has no 'The cap is …' sentence"
in_order "$formula" "the cap is the limit divided by the seven lenses, rounded down, never below one — in one sentence" \
	"concurrent-subagent limit" "divided by seven" "rounded down" "never below one"
t_text_has "$handoff" "as the project states it" "the limit is the project's stated value, read where it is written"
t_text_has "$handoff" "never a number this skill names" "no host's number is baked into a skill that ships to every host"
in_order "$handoff" "a project that states no limit is told so, and runs one session at a time" \
	"states no limit" "say so" "one session at a time"
in_order "$handoff" "a frontier larger than the cap is sequenced, the rest waiting on sessions that end" \
	"larger than the cap" "sequence" "as sessions end"
case ${handoff#5. } in
*[0-9]*) fail "the hand-off carries a digit — the limit is the project's value, and the divisor is spelled 'seven'" ;;
*) pass "the hand-off carries no digit: no limit is baked in" ;;
esac
t_text_has "$quiz" "the session cap beside the frontier" "the quiz shows the cap where the human reads the frontier"
# The place the hand-off reads the limit from exists: the consumer's workflow
# article carries a line for it, a mark the project fills in — or answers
# "unstated", the reading that runs one session at a time.
wf_cap=$(grep -F 'concurrent-subagent limit' "$ROOT/constitution/local-workflow.md.template" | head -n 1)
t_text_has "$wf_cap" "$(t_mark CONCURRENT_SUBAGENT_LIMIT)" "the workflow template states the host's concurrent-subagent limit as a mark the project fills"
t_text_has "$wf_cap" "unstated" "the workflow template names 'unstated' as the answer when the limit is not known"
t_text_has "$handoff" "constitution/local-workflow.md" "the hand-off reads the limit from the workflow article that carries its line"

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
