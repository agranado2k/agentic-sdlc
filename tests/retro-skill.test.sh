#!/bin/sh
# tests/retro-skill.test.sh — the /retro contract, checked as TEXT.
#
# /retro is the one sanctioned reader of the trace besides the operator and a
# diagnosis (ADR-0008 clause 7; PRD #237, ticket #254). It is a document an
# agent obeys, so — the same honest boundary as tests/housekeeping-skill.test.sh
# — the external behavior IS the text, and this suite pins the tokens a session
# following it must run and the rules it must keep:
#
#   1. The EIGHT fixed questions, named and numbered: tier calibration, review
#      signal per sub-agent, recurring failures, diagnosis calibration, spend,
#      chain health, aim calibration (the seventh, added at the PRD
#      re-evaluation of 2026-09-28, reads the `feedback` events) and stamp
#      calibration (the eighth, PRD #273, ticket #281): per decision field and
#      per skill, never one number for the chain; the oracle clause on every
#      row; and three limits the question states instead of papering over —
#      the dismissal denominator overcounts where a raise carries no posted
#      marker (#332), the label's override rate is
#      computable only from stamps that carry `data.label_proposed` (ticket
#      #354), and a row with too few events prints no rate.
#   2. It reads through the plain `sh scripts/trace.sh show|summary|export`
#      name — never the kit's never-shipped wrapper — and verifies first.
#   3. The report and its CSV land IN THE PROJECT, at the root checkout:
#      .retro/<YYYY>/<MM>/retro-<YYYYMMDDTHHMMSSZ>.md and .csv, the root found
#      through git's common directory the way scripts/trace.sh finds it for a
#      relative TRACE_DIR — so a retro run from a linked worktree lands at the
#      root and survives the worktree's pruning (ticket #349; before it the
#      report went to the OS temp directory and was lost with it). The folder
#      is gitignored beside .trace/, and the one-line derivation the skill
#      quotes is RUN here from a scratch worktree (section 9).
#   4. Findings are routed to /to-tickets as candidates; it never fixes, never
#      edits a skill, never pushes or merges. A recurring failure becomes a
#      rule with a failing check, never a preloaded lessons file (shared
#      invariant §11).
#   5. It opens and closes a run — begin / end — and the end carries
#      data.findings=<count>; every trace call ends in `|| :`; every kind it
#      emits is one the script knows; every documented span RUNS against a
#      scratch trace (placeholders filled) and what it wrote verifies.
#   6. The default window is since its own last run.end.
#   7. It is planner work, its frontmatter is specification-clean, every
#      command and path it names resolves, and no model id appears.
#   8. The roster knows it: VERSION's skills manifest, both manuals, README,
#      the provenance file, /housekeeping's checklist (a retro ran inside the
#      window), the trace-skills suite's named exclusion, bootstrap's KIT_ONLY
#      list and a kit CI job for this suite. Every surface that counts the
#      questions counts eight.
#   9. It learns from its own runs (ticket #461, section 13): the window is
#      the last CLOSED retro, a retro open beside it is named and never
#      closed, sibling reports in the same window are named, questions 5 and
#      6 read the compaction gap, the phantom stops and the wait-bound keys,
#      and a finding is searched for in the tracker before it is recorded.
#  10. Questions 7 and 8 retire, per window, while a binding decision record
#      says the project accepts train-only verdicts (#572, section 15): the
#      spans that count each question's operator verdicts RUN over two
#      fixture windows, and the kit's own record is found by the span.
#
# NOT HELD here, on purpose: question 8's "what counts as a finding"
# criteria and the rubric version its tier oracle names. Both are on the
# behavior confirm-list of PR #329, the human's to confirm; a pin would
# decide them first.
#
# NOT simulable here: the pass itself, which reads a real trace and writes a
# report. The ticket's demo — a retro over this repo's own trace — is run by
# hand and quoted in the delivering PR. What IS run here (section 2c) is
# question 8's arithmetic over a FIXTURE trace in scratch: the kit's own
# trace holds too few calibration pairs to print a rate, and a rule whose
# numbers were never computed once is a claim.
#
# Every case was driven RED first (hard rule 9): the suite was written against
# a tree with no .agents/skills/retro/.
#
# Usage: sh tests/retro-skill.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

SKILL=".agents/skills/retro/SKILL.md"
SKILL_ABS="$ROOT/$SKILL"
SIDECAR=".agents/skills/retro/QUESTIONS.md"
SIDECAR_ABS="$ROOT/$SIDECAR"
TRACE="scripts/trace.sh"

cd "$ROOT" || exit 2

# The span tokeniser and the placeholder filler are tests/lib.sh's
# (t_trace_lines, t_trace_spans, t_trace_runnable), shared with
# tests/trace-skills.test.sh (M-4, review of PR #293).

# window_section — SKILL.md's "The window" section: the window span is the
# first trace span in it (ticket #461).
window_section() { awk '/^## The window/ { on = 1; next } /^## / { on = 0 } on' "$SKILL_ABS"; }

# flat — stdin as one line, runs of spaces squeezed: a rule that wraps across
# two lines is still the rule, and a needle is matched against the sentence.
flat() { tr '\n' ' ' | tr -s ' '; }

# no_seven <file, relative to the root> — no surface still counts seven
# questions, in either spelling, and not across a line break either: a
# line-based grep passes "seven\nquestions" (review of PR #329, L-4).
no_seven() {
	flat <"$ROOT/$1" | grep -qE 'seven (fixed )?questions' &&
		fail "$1 still counts seven questions" || pass "$1 nowhere counts seven questions"
}

# ---------------------------------------------------------------------------
banner "0. The files under test"
# ---------------------------------------------------------------------------
[ -f "$SKILL_ABS" ] && pass "$SKILL exists" || {
	fail "$SKILL is missing — nothing else in this suite means anything"
	t_done "/retro contract"
}
[ -f "$SIDECAR_ABS" ] && pass "$SIDECAR exists — the questions in full live beside the order" ||
	fail "$SIDECAR is missing"
if [ -L "$ROOT/.claude/skills/retro" ] && [ -f "$ROOT/.claude/skills/retro/SKILL.md" ]; then
	pass "the harness bridge symlink resolves to the canonical skill"
else
	fail "no resolving symlink at .claude/skills/retro"
fi

# ---------------------------------------------------------------------------
banner "1. Frontmatter: the open standard's fields; the pass is planner work"
# ---------------------------------------------------------------------------
t_assert_skill_frontmatter "$(dirname "$SKILL_ABS")"
phase=$(awk 'NR == 1 && /^---/ { fm = 1; next } fm && /^---/ { exit } fm && /^metadata:/ { m = 1; next } m && /^[A-Za-z]/ { m = 0 } m && /^[ \t]+phase:/ { sub(/^[ \t]+phase:[ \t]*/, ""); print; exit }' "$SKILL_ABS")
[ "$phase" = planner ] && pass "metadata.phase is planner — its findings constrain the tickets that follow" ||
	fail "metadata.phase is '$phase', not planner"

# ---------------------------------------------------------------------------
banner "2. The eight fixed questions, named and numbered, in both files"
# ---------------------------------------------------------------------------
# Only the questions section counts in SKILL.md — the procedure below it
# numbers its steps too.
questions() { awk '/^## The eight questions/ { on = 1; next } /^## / { on = 0 } on' "$SKILL_ABS"; }
items=$(questions | grep -c '^[0-9][0-9]*\. \*\*')
[ "$items" = 8 ] && pass "the questions section has eight numbered items" || fail "the questions section has $items numbered items, not eight"
for q in 'Tier calibration' 'Review signal' 'Recurring failures' 'Diagnosis calibration' 'Spend' 'Chain health' 'Aim calibration' 'Stamp calibration'; do
	questions | grep -q "\*\*$q" && pass "SKILL.md names the question '$q'" || fail "SKILL.md does not name the question '$q'"
	grep -q "^## [1-8]\. $q" "$SIDECAR_ABS" && pass "QUESTIONS.md carries '$q' as a numbered section" ||
		fail "QUESTIONS.md has no numbered section for '$q'"
done
sidecar_sections=$(grep -c '^## [1-9]\. ' "$SIDECAR_ABS")
[ "$sidecar_sections" = 8 ] && pass "QUESTIONS.md has exactly eight numbered sections" || fail "QUESTIONS.md has $sidecar_sections numbered sections, not eight"
grep -q '^# The eight questions' "$SIDECAR_ABS" && pass "QUESTIONS.md's title counts eight" || fail "QUESTIONS.md's title does not say eight questions"
# Each question reads named kinds and fields of the trace. The sidecar is the
# half the pass executes, so the kinds are held there.
assert_file_has "$SIDECAR" "ticket.write" "tier calibration reads the tier stamped at write time"
assert_file_has "$SIDECAR" "tier_proposed" "…and the quiz override the stamp records"
assert_file_has "$SIDECAR" "pr.iterate" "tier calibration counts iterations per tier"
assert_file_has "$SIDECAR" "finding.raise" "review signal reads the findings raised"
assert_file_has "$SIDECAR" "finding.triage" "…and how each was triaged"
assert_file_has "$SIDECAR" "data.agent" "review signal is PER SUB-AGENT"
assert_file_has "$SIDECAR" "rejected" "review signal counts the rejections"
assert_file_has "$SIDECAR" "policy citation" "…that cite a policy — a decision record or an article"
# Review ids restart with every review, and only a LOCAL triage has a raise
# at all (second review of PR #293): a join on the bare id conflates two
# reviews of one PR, and an orphan rule over every source turns each check,
# bot and human triage into a false chain-health finding.
assert_file_has "$SIDECAR" "\`data.source=local\`" "review signal joins only the triages that have a raise — the local ones"
assert_file_has "$SIDECAR" "latest raise" "…and pairs each with the latest raise of its id, since ids restart per review"
# …and only an Axis-1 id has a raise: /review-pr records its second axis as
# a verdict count, so a local triage of a confirm-list item is no orphan.
assert_file_has "$SIDECAR" "has no raise by design" "a confirm-list triage is not read as a finding raised by nobody"
assert_file_has "$SIDECAR" "about the stamping" "a defaulted start is /to-tickets not stamping, not the rubric misjudging"
grep -qE 'exit 3' "$SKILL_ABS" && awk '/^## Routing/ { on = 1; next } /^## / { on = 0 } on' "$SKILL_ABS" | grep -q 'operator' &&
	pass "the routing section names its one exception — exit 3 goes to the operator" ||
	fail "step 1 routes exit 3 to the operator while Routing says everything goes to /to-tickets"
assert_file_has "$SIDECAR" "hypothesis" "diagnosis calibration reads the hypotheses"
assert_file_has "$SIDECAR" "data.rank" "…at the rank each held"
assert_file_has "$SIDECAR" "confirmed" "…against the one confirmed"
assert_file_has "$SIDECAR" "session.usage" "spend reads the per-model token sums"
assert_file_has "$SIDECAR" "unpriced" "spend names the model the price table does not"
# A priced read says on stderr when the price table is past its window
# (ADR-0008 clause 6); a retro that drops stderr quotes stale costs bare.
assert_file_has "$SIDECAR" "Last checked" "spend reads the stale-table advisory and dates every cost figure"
grep -qE 'never[^.]*TRACE_QUIET=1' "$SKILL_ABS" && pass "the reads keep stderr — the switch that silences the advisory is named as NEVER used" ||
	fail "SKILL.md does not forbid TRACE_QUIET=1 on its reads — the stale-table advisory would be silenced"
assert_file_has "$SIDECAR" "spawn.end" "chain health reads how spawns ended"
for o in fail timeout budget unreachable; do
	assert_file_has "$SIDECAR" "\`$o\`" "chain health names the spawn outcome '$o'"
done
# H-1 (review of PR #293): a window with no spawn.end at all is ONE finding
# about the emitter, never one per spawn — or every spawn is a finding.
assert_file_has "$SIDECAR" "no \`spawn.end\` at all" "an absent kind is one finding about the emitter, not one per spawn"
# `outcome=in-session` is what EVERY spawn a skill runs itself carries — it
# marks no fallback (second review of PR #293, M-3).
assert_file_lacks "$SIDECAR" "\`spawn outcome=in-session\` beside it" "in-session is not read as the trace of a fallback"
assert_file_has "$SIDECAR" "not a fallback marker" "…and the sidecar says so, since the word invites the misreading"
# A stamp the implementer disputed, or found missing, is the most direct
# tier-calibration signal the chain emits (L-2).
for o in disputed defaulted; do
	assert_file_has "$SIDECAR" "\`$o\`" "tier calibration counts the ticket.start outcome '$o'"
done
assert_file_has "$SIDECAR" "merge.land" "chain health finds PRs with no landing"
assert_file_has "$SIDECAR" "\`feedback\`" "aim calibration reads the feedback events"
for v in hit adjusted missed; do
	assert_file_has "$SIDECAR" "\`$v\`" "aim calibration names the verdict '$v'"
done
assert_file_has "$SIDECAR" "re-cut" "aim calibration asks how many landed slices were followed by a re-cut"

# ---------------------------------------------------------------------------
banner "2b. The eighth question: stamp calibration (PRD #273, ticket #281)"
# ---------------------------------------------------------------------------
# Held to the eighth SECTION of the sidecar, flattened to one line: a token
# that question 1 or 2 happens to carry proves nothing about question 8, and
# a rule that wraps across two lines is still the rule. And held to its PROSE:
# the fenced example rows and the `Reads:` line repeat the rules' own words
# (`— oracle: `, `no held-out set`, `too few`, `run.start`), so a needle they
# satisfy survives the rule's deletion (review of PR #329, H-5). The rows are
# read apart, as rows.
sec8() { awk '/^## 8\. / { on = 1; next } /^## / { on = 0 } on' "${1:-$SIDECAR_ABS}"; } # [<sidecar file>]
fenced() { awk '/^```/ { fence = !fence; next } fence'; } # stdin's fenced lines, the example rows
unfenced() { awk '/^```/ { fence = !fence; next } !fence'; } # stdin's lines outside a fence, the prose
stamp=$(sec8 | awk '/^```/ { fence = !fence; next } !fence' | awk '/^\*Reads: / { reads = 1 } !reads; reads && /\*$/ { reads = 0 }' | flat)
reads8=$(sec8 | awk '/^\*Reads: / { reads = 1 } reads; reads && /\*$/ { reads = 0 }' | flat)
rows8=$(sec8 | fenced)
[ -n "$stamp" ] && [ -n "$reads8" ] && [ "$(printf '%s\n' "$rows8" | grep -c .)" -ge 3 ] &&
	pass "question 8 has rule prose, a Reads line and example rows — each read apart" ||
	fail "question 8 could not be split into its prose, its Reads line and its example rows"
reads_has() { # <needle> <message>
	case "$reads8" in
	*"$1"*) pass "$2" ;;
	*) fail "$2 — question 8's Reads line does not name: $1" ;;
	esac
}
stamp_has() { # <needle> <message>
	case "$stamp" in
	*"$1"*) pass "$2" ;;
	*) fail "$2 — question 8 does not say: $1" ;;
	esac
}
# What it reads: the tier's stamp and its outcome on ONE event, the finding's
# severity through the join ADR-0008's amendment of 2026-09-30 fixed.
reads_has '`ticket.write`' "stamp calibration reads the ticket as it was published"
reads_has '`data.confidence`' "…the confidence the tier was stamped with"
reads_has '`data.tier_proposed`' "…and the tier before the quiz, against the published one"
reads_has '`finding.raise`' "…the finding as raised, for its severity"
reads_has '`finding.dismiss`' "…and the human's dismissal of it"
stamp_has '`data.where`' "the dismissal joins its raise on the subject and data.where"
# The rule the PRD's story 14 asks for: an easy field must not hide a hard one.
stamp_has 'per decision field and per skill' "the question is answered per decision field and per skill"
stamp_has 'never one number for the chain' "…never as one number for the chain"
stamp_has 'per value the stamp carried' "…one row per field, per skill, per value the stamp carried"
# The tier's rows (H-3, review of PR #329): which event is read, what an
# override is, and who is left out of the denominator are the arithmetic —
# each survived a hand mutation before it was pinned here.
stamp_has 'Take one `ticket.write` per subject, the latest by `ts`' "one ticket.write per subject, the latest by ts"
stamp_has 'group by `data.confidence`' "…grouped by the confidence the tier was stamped with"
stamp_has 'when its `tier` differs from its `data.tier_proposed`' "an override is a published tier that differs from the proposed one"
stamp_has 'of how many carry both keys' "the denominator is the tickets that carry both keys"
stamp_has 'a row named `unstamped`' "a ticket.write from before the stamp existed goes on a row named unstamped"
stamp_has 'leave it out of the denominator' "a ticket with no proposed tier is counted on its row and left out of the denominator"
stamp_has 'goes on the `undeclared` row' "a confidence outside the three words goes on the undeclared row"
# The skill is the RUN's: a finding.raise carries its run and no skill of its
# own (the kit's own trace, read for this ticket's demo), so a reader that
# pivots on the event's skill column files every severity row under nothing.
stamp_has '`run.start`' "the skill that stamped is read from the run's run.start where the event names none"
stamp_has '`unattributed`' "…and an event nothing attributes is a row that says so"
# H-1 (review of PR #329): /to-tickets opens no run and its ticket.write names
# no skill, so the two sources above file EVERY tier and label row under
# `unattributed`. The reader's third source is the kind itself, for a kind
# exactly one chain skill emits — a fact tests/trace-skills.test.sh holds, not
# this prose — and a row attributed that way says so.
stamp_has 'for a kind exactly one chain skill emits, that skill' "a kind one skill emits names that skill where the event and its run name none"
stamp_has 'a `ticket.write` is `/to-tickets`'"'"'s' "…a ticket.write is the ticket-writing skill's"
stamp_has 'a `finding.raise` is `/review-pr`'"'"'s' "…a finding.raise the reviewing skill's"
stamp_has '`(by kind)`' "…and the row says it was attributed by kind"
case "$stamp" in
*"event's own \`skill\`"*'`run.start`'*'exactly one chain skill emits'*'`unattributed`'*)
	pass "the four sources are read in one order: the event, its run, its kind, then unattributed" ;;
*) fail "question 8 does not give the attribution order: the event's own skill, its run's run.start, its kind, then unattributed" ;;
esac
# The example rows agree with the rule: a tier or label row is /to-tickets'
# by kind, a severity row /review-pr's through its run.
bad_rows=$(printf '%s\n' "$rows8" | grep -E '^(tier|label) ' | grep -vF ' · to-tickets (by kind) · ' || true)
[ -z "$bad_rows" ] && printf '%s\n' "$rows8" | grep -qE '^tier ' && printf '%s\n' "$rows8" | grep -qE '^label ' &&
	pass "every example tier and label row names to-tickets, attributed by kind" ||
	fail "an example tier or label row does not read '· to-tickets (by kind) ·' — the example contradicts the attribution rule"
printf '%s\n' "$rows8" | grep -E '^severity ' | grep -qF ' · review-pr · ' &&
	pass "the example severity row names review-pr, read from its run" ||
	fail "the example severity row does not read '· review-pr ·'"
# M-1 (review of PR #329): three trace values name a row — a confidence, a
# severity, a skill — and trace data can carry forge text. Each is held to
# what the project declares before it is printed; anything else is ONE row
# per field that prints a count and never the value. One word for it, too:
# the confidence's `other` was the same rule under a second name.
stamp_has 'A row is never named by trace text' "a row is never named by trace text"
stamp_has '`sh scripts/vocab.sh fields`' "a confidence and a severity are held to the declared vocabulary, read from the checker"
stamp_has 'a directory under `.agents/skills/`' "a skill is held to the skills the project holds"
stamp_has 'prints the count and never the value' "…which prints the count and never the value"
case "$stamp" in
*'under `other`'*) fail "question 8 still files an undeclared confidence under 'other' — one rule, one row name: undeclared" ;;
*) pass "no second name for the undeclared row" ;;
esac
# The reader's dependency is real: the checker declares both fields, and the
# example rows' own names pass the rule they sit under.
declared=$(sh "$ROOT/scripts/vocab.sh" fields 2>/dev/null)
for f in confidence severity; do
	printf '%s\n' "$declared" | grep -q "^$f: ." && pass "sh scripts/vocab.sh fields declares $f" ||
		fail "sh scripts/vocab.sh fields prints no '$f:' line — question 8 holds its row names to it"
done
row_bad=
while IFS= read -r row; do
	[ -n "$row" ] || continue
	field=$(printf '%s\n' "$row" | awk -F ' · ' '{ print $1 }')
	skill=$(printf '%s\n' "$row" | awk -F ' · ' '{ sub(/ \(by kind\)$/, "", $2); print $2 }')
	value=$(printf '%s\n' "$row" | awk -F ' · ' '{ split($3, w, " "); print w[1] }')
	case $field in severity) vocab=severity ;; *) vocab=confidence ;; esac
	[ -d "$ROOT/.agents/skills/$skill" ] || row_bad="$row_bad [skill '$skill']"
	printf '%s\n' "$declared" | sed -n "s/^$vocab: //p" | tr ' ' '\n' | grep -qx -- "$value" || row_bad="$row_bad [$vocab '$value']"
done <<EOF
$rows8
EOF
[ -z "$row_bad" ] && pass "every example row is named by a declared value and a skill the kit holds" ||
	fail "an example row is named by something the rule would file under undeclared:$row_bad"

# The oracle clause (#276) is on EVERY row this question prints, in the form
# the housekeeping checklist gave it.
stamp_has 'Every row carries the oracle clause' "every row carries the oracle clause"
# M-3 (review of PR #329): the clause has ONE wording, the housekeeping
# checklist's, and the glossary's Oracle entry names the same four parts.
# Question 8 paraphrased it ("who wrote the oracle this number was measured
# against"), which is a second form of a rule the kit states once. The
# needle is read out of the checklist, so the two cannot drift apart.
oracle_form='who wrote the test fixtures, when, against which version, and what it was compared to: `— oracle: <who>, <when>, <version>, <comparator>`'
case "$(flat <"$ROOT/.agents/skills/housekeeping/CHECKLIST.md")" in
*"$oracle_form"*) pass "/housekeeping's checklist states the oracle clause's form" ;;
*) fail "/housekeeping's checklist no longer states the oracle clause in the words this suite holds question 8 to — move both together" ;;
esac
stamp_has "$oracle_form" "…in the checklist's own words, not a paraphrase of them"
# …and the checklist admits the glossary's second form (#332, after PR #355):
# a row that measured nothing names no oracle and says why, and is not a
# finding for that. Question 8 says the same of its own rows.
none_form='`— oracle: none — <why>`'
case "$(flat <"$ROOT/.agents/skills/housekeeping/CHECKLIST.md")" in
*"$none_form"*'with neither is a finding'*) pass "/housekeeping's checklist admits the none form, and a row with neither form is the finding" ;;
*) fail "/housekeeping's checklist still gives the four-part clause as the only form — a row in the glossary's $none_form form reads as a finding" ;;
esac
stamp_has "or, on a row that measured nothing, the glossary's other form, $none_form" "question 8's rule admits the none form beside the four-part clause"
oracle_entry=$(awk '/^- \*\*Oracle\*\*/ { on = 1 } on && /^- \*\*/ && !/^- \*\*Oracle\*\*/ { exit } on && /^## / { exit } on' "$ROOT/docs/domain-glossary.md" | flat)
case "$oracle_entry" in
*'who wrote the test fixtures, when'*) pass "the glossary's Oracle entry opens on the same parts" ;;
*) fail "the glossary's Oracle entry no longer says 'who wrote the test fixtures, when'" ;;
esac
# A calibration row has no fixtures: a human's verdict graded the stamp. The
# glossary carries that sense, and question 8 says who stands in the clause.
case "$oracle_entry" in
*"graded by a human's verdict"*) pass "…and carries the sense a calibration row uses: graded by a human's verdict" ;;
*) fail "the glossary's Oracle entry defines only fixtures — a calibration row's oracle, a human's verdict, has no sense there" ;;
esac
stamp_has 'A calibration row has no fixtures' "question 8 says what stands in for the fixtures' author: the human whose verdict graded the stamp"
stamp_has 'the severity bands in `/review-pr` as they stood when the window closed' "a severity row's version is named: the bands as they stood when the window closed"
stamp_has 'the human at the quiz' "the tier rows' oracle is named: the human at the quiz"
stamp_has 'no held-out set' "…and the comparator is named as what it is — no held-out set"
# A row that measured nothing names no oracle and says why: oracle: none — <why>
# (ticket #342). The glossary carries that form, and the example rows hold to it.
case "$oracle_entry" in
*'oracle: none — '*) pass "the glossary's Oracle entry mentions the form: oracle: none — <why>" ;;
*) fail "the glossary's Oracle entry does not mention: oracle: none — <why>" ;;
esac
# The none form does not repeal the entry's rule — the checklist's words, "a
# comparator is always named, never implied" — it is the rule kept where
# there is nothing to name: the row says it has no comparator, instead of
# implying one. Both sentences are held, so neither can be edited into
# contradicting the other.
comparator_rule='a comparator is always named, never implied'
case "$(flat <"$ROOT/.agents/skills/housekeeping/CHECKLIST.md")" in
*"$comparator_rule"*) pass "/housekeeping's checklist states the comparator rule" ;;
*) fail "/housekeeping's checklist no longer states the comparator rule in the words this suite holds the glossary to — move both together" ;;
esac
case "$oracle_entry" in
*"$comparator_rule"*) pass "…and the glossary's Oracle entry still states it in the checklist's words: $comparator_rule" ;;
*) fail "the glossary's Oracle entry no longer states the rule the checklist states: $comparator_rule" ;;
esac
case "$oracle_entry" in
*'no comparator to name'*) pass "…and the none form is that rule kept: a row that measured nothing has no comparator to name, and says so" ;;
*) fail "the glossary's Oracle entry does not say the none form has 'no comparator to name' — read beside the rule, a row naming none would imply one" ;;
esac
# A label row that measured nothing carries the none form (ticket #342): a
# row whose stamps all predate `data.label_proposed` (ticket #354, the label
# half of #332) has no override to read, so no who, when or version to name,
# and a four-part clause there would name an oracle that does not exist. The
# holder reads any sidecar, so the baits below can prove it goes red (hard
# rule 9) without touching the real one.
label_row_of() { # <sidecar file> — question 8's not-computable label example row, or nothing
	sec8 "$1" | fenced | grep -E '^label · .*not computable from the trace today' | head -1
}
label_row_none_form() { # <sidecar file> — exit 0 only when the label row reads `— oracle: none — <why>`
	label_row_of "$1" | grep -qE -- '— oracle: none — [^ ]'
}
# …and the converse, now that a label row can measure: a label row with
# counts was graded by the human at the quiz, so it names that oracle and
# never the none form.
rated_label=$(printf '%s\n' "$rows8" | grep -E '^label · .* [0-9]+ of [0-9]+ overridden ' || true)
[ -n "$rated_label" ] && ! printf '%s\n' "$rated_label" | grep -qF -- '— oracle: none' &&
	printf '%s\n' "$rated_label" | grep -qF -- '— oracle: the human at the quiz, ' &&
	pass "a label row with counts names the human at the quiz as its oracle, never the none form" ||
	fail "question 8 has no label row with counts naming '— oracle: the human at the quiz, …' (or one carries the none form)"
stamp_has 'For a label row: the human at the quiz' "a label row's oracle is named: the human at the quiz"
stamp_has 'carries the none form of the clause' "a label row that measured nothing is said to carry the none form"
label_row=$(label_row_of "$SIDECAR_ABS")
if [ -n "$label_row" ]; then
	label_row_none_form "$SIDECAR_ABS" && pass "the label row carries oracle: none — <why> form" ||
		fail "the label row does not carry oracle: none — <why>; found: $label_row"
else
	fail "no label row found in question 8 examples"
fi
# The bait: three copies of the sidecar whose label row names an oracle it
# does not have, names none and gives no why, or carries no clause at all.
# The holder must refuse every one — and each bait must have planted its
# line: a copy whose label row is missing or unchanged proves nothing.
bait_label_row() { # <sed substitution on the label row> — exit 0 only when the copy's row is there and changed
	sed "/^label · /$1" "$SIDECAR_ABS" >"$SCRATCH/bait-sidecar.md" || return 1
	bait_row=$(label_row_of "$SCRATCH/bait-sidecar.md")
	[ -n "$bait_row" ] && [ "$bait_row" != "$label_row" ]
}
bait_label_row 's/— oracle: none — .*$/— oracle: the human at the quiz, <window>, <version>, published label against proposed; no held-out set/' &&
	! label_row_none_form "$SCRATCH/bait-sidecar.md" &&
	pass "bait: a label row that names a four-part oracle it does not have goes red" ||
	fail "bait: a label row carrying a four-part clause passed as the none form (the holder reads the clause's presence, not its form) — or the bait planted nothing"
bait_label_row 's/— oracle: none — .*$/— oracle: none/' &&
	! label_row_none_form "$SCRATCH/bait-sidecar.md" &&
	pass "bait: a label row that says none and gives no why goes red" ||
	fail "bait: a label row reading '— oracle: none' with no <why> passed (the why is the half that keeps the row honest) — or the bait planted nothing"
bait_label_row 's/ *— oracle: none — .*$//' &&
	! label_row_none_form "$SCRATCH/bait-sidecar.md" &&
	pass "bait: a label row with no oracle clause at all goes red" ||
	fail "bait: a label row with no oracle clause passed the none-form holder — or the bait planted nothing"
# Honesty point 1 (#332): a raise now says whether it was posted, and the
# denominator counts only the posted; a raise recorded before the key existed
# carries no marker, stays in, and its row OVERCOUNTS what a human could have
# dismissed. The row says which form it used.
# Each of these rules has a test that fails without it (review of PR #374,
# H-2): posted_rules_missing reads any sidecar and names every rule it has
# lost, one per line, and one bait per rule proves it red — in the parent
# shell, where a fail counts.
posted_rules_missing() { # <sidecar file>
	_pr_stamp=$(sec8 "$1" | unfenced | flat)
	for _r in \
		'posted denominator|counts only the raises carrying `data.posted=yes`' \
		'unposted out|A raise with `data.posted=no` is in no denominator and in no pairing' \
		'unposted counted beside|count it beside its row, `<n> not posted`' \
		'unmarked overcounts|A raise that carries no `data.posted` was recorded before the key existed, and the denominator **overcounts**' \
		'row names its form|Each severity row says which form it used — `posted only`, or `overcounts`' \
		'lower bound|the rate is a lower bound on the share of posted findings'; do
		case "$_pr_stamp" in *"${_r#*|}"*) ;; *) printf '%s\n' "${_r%%|*}" ;; esac
	done
	# …and every severity example row carries the form it used.
	_pr_bare=$(sec8 "$1" | fenced | grep -E '^severity · ' | grep -vE '   (posted only|overcounts)   ' || true)
	_pr_any=$(sec8 "$1" | fenced | grep -cE '^severity · ')
	[ -z "$_pr_bare" ] && [ "$_pr_any" -gt 0 ] || printf '%s\n' 'example row names its form'
}
missing=$(posted_rules_missing "$SIDECAR_ABS" | tr '\n' ',' | sed 's/,$//')
[ -z "$missing" ] && pass "the posted marker's rules are all stated: the denominator, the unposted counted beside, the overcount, the form each row names, and the example rows carry it" ||
	fail "question 8 has lost posted-marker rules: $missing"
for b in \
	'posted denominator|s/counts only the raises carrying `data.posted=yes`/counts the raises/' \
	'unposted out|s/is in no denominator and in no pairing/is counted/' \
	'unposted counted beside|s/`<n> not posted`/nowhere/' \
	'unmarked overcounts|s/the denominator \*\*overcounts\*\*/the denominator is exact/' \
	'row names its form|s/says which form it used — `posted only`, or/may name a form, or/' \
	'lower bound|s/the rate is a lower bound on the share/the rate is the share/' \
	'example row names its form|/^severity · /s/   posted only   /   /'; do
	sed "${b#*|}" "$SIDECAR_ABS" >"$SCRATCH/bait-sidecar.md"
	! cmp -s "$SCRATCH/bait-sidecar.md" "$SIDECAR_ABS" && posted_rules_missing "$SCRATCH/bait-sidecar.md" | grep -qxF -- "${b%%|*}" &&
		pass "bait: question 8 without '${b%%|*}' goes red" ||
		fail "bait: question 8 without '${b%%|*}' was not caught — or the bait planted nothing"
done
# …and a dismissal is one (data.thread, data.where) pair per subject — a
# resolved thread and its dismissed review can both emit.
stamp_has '(`data.thread`, `data.where`) pair' "a dismissal is identified by the (data.thread, data.where) pair"
stamp_has 'pair, counted once per subject' "…and counted once per subject"
# H-2 (review of PR #329): the join had two rules that disagreed on a PR
# reviewed twice — "the latest raise at that data.where" picks one raise,
# "two findings on one line both count" picks two. ONE rule now: the latest
# raise there before the dismissal, and its same-review siblings on the line.
stamp_has 'One pairing rule' "the severity join states one pairing rule"
stamp_has 'pairs with the latest raise on its subject at its `data.where` before it, by `ts`' "a dismissal pairs with the latest raise at its data.where before it"
stamp_has 'from the same review — the same `run`' "…and with that raise's same-review siblings on the line, told apart by run"
stamp_has "An earlier review's raise at that line is not paired; it stays in the denominator" "an earlier review's raise at the line is not paired, and stays in the denominator"
stamp_has 'say on the row how many shared' "raises that shared one dismissal are said on the row"
# M-2: a resolved thread carries the thread's id and a dismissed review the
# review's, so the pair does NOT fold them into one — the raise does.
stamp_has 'A raise is dismissed once, however many dismissals pair with it' "a raise is dismissed once, however many dismissals pair with it"
stamp_has 'counted beside the table, in no band' "a dismissal that pairs with no raise is counted beside the table"
case "$stamp" in
*'join to one dismissal'*) fail "question 8 still carries the second pairing rule ('… join to one dismissal') beside the first" ;;
*) pass "no second pairing rule beside the first" ;;
esac
# Honesty point 2: ticket.write now records the pre-quiz label, so the label's
# override rate can be computed when enough stamps carry both keys. The row
# shows override counts when there are enough, or "too few to rate" otherwise.
stamp_has '`data.label_proposed`' "the pre-quiz label is read, under its own key"
stamp_has '`data.label` differs from its `data.label_proposed`' "the override is defined as label change at quiz"
stamp_has 'count it on its row and leave it out of the denominator' "stamps without the key stay in history but out of rate calculation"
stamp_has 'a row of its own' "…the label row is a row of its own"
# H-3 (review of PR #368): the label's own rules each have a needle. A row
# whose stamps all predate the key says so in words, not as 0 of 0…
stamp_has 'A label row none of whose stamps carries `data.label_proposed`' "a label row whose stamps all predate the key is named"
stamp_has 'prints its stamp count and `not computable from the trace today` in place of a rate' "…and prints its count and 'not computable from the trace today', never a rate"
# …and the threshold is the one every row has, per row — per confidence
# group — never a count over the window (M-1).
stamp_has 'Each label row is held to the five-event threshold below, per row' "the label's threshold is per row, the same as every other row's"
case "$stamp" in
*'If fewer than five stamps carry it'*) fail "question 8 still states a per-window threshold for the label beside the per-row one" ;;
*) pass "no per-window threshold for the label beside the per-row one" ;;
esac
# Honesty point 3: a thin row prints its counts and the words, not a rate.
# The bullet's HEADING says "too few" too, so the needle is the rule: the
# threshold, and what is printed in the rate's place.
stamp_has "Fewer than five events in a row's denominator is a count, not a rate" "a row with fewer than five events in its denominator is a count, not a rate"
stamp_has 'print the counts and `too few to rate` instead of a rate' "…it prints the counts and 'too few to rate' instead of a rate"
# A window with raises and no finding.dismiss at all is not a band nobody
# dismissed: 0 of 7 printed as a rate reads as a measurement of an emitter
# that may never have run (the kit's own trace, the day the kind landed).
stamp_has 'no dismissal recorded in the window' "a window with no finding.dismiss at all prints no dismissal rate"
# L-6: question 8's override is question 1's, re-cut — one home for the
# definition, and the second question says whose it is.
stamp_has 'the quiz override question 1 counts' "the tier override is question 1's, cut here by confidence — one home per rule"
# L-7: some raises can never be reached by a dismissal, and they are in the
# denominator too — named, beside the two the brief already names.
stamp_has 'a raise no dismissal can reach' "a raise no dismissal can reach is named as part of the overcount"
stamp_has 'a subject that is not a pull request' "…a raise on a subject that is not a pull request"
# The finding's line goes into a quoted `reason=` on the candidate note, and
# what it summarises is trace text: never pasted in, so never able to close
# the quotes.
stamp_has 'summarised, never quoted' "a finding's line is the retro's own words — trace text is summarised, never quoted"
# A sentence that said only what every retro does anyway is gone.
case "$stamp" in
*'carries the question to the next retro'*) fail "question 8 still says a thin window 'carries the question to the next retro' — every retro asks all eight" ;;
*) pass "no sentence restating that the next retro asks the question again" ;;
esac
# Second local review of PR #329, H-2 and M-5: raises that share a dismissal
# are ALL counted dismissed though one closed thread may have answered one of
# them, so on such a row the numerator overcounts too and "a lower bound" is
# false; and a pair emitted twice is read at its earliest ts, or a raise
# landing between the two emits changes what it pairs with.
stamp_has 'A row where raises shared a dismissal is not even that' "a row where raises shared a dismissal is said not to be a lower bound"
stamp_has 'read at its earliest `ts`' "a pair emitted more than once is read at its earliest ts"
# Second local review, M-3, M-4, L-2: the undeclared row's SHAPE is stated
# (the word stands in the value's place — the grain stays field, skill,
# value), the confidence groups are the declared words and not a hard-coded
# three, and "per value" says which value each field's stamp carries.
stamp_has 'its confidence for a tier or a label, its band for a severity' "per value: the confidence for a tier or a label, the band for a severity"
stamp_has "carries \`undeclared\` in that value's place" "an undeclared value's row carries the word in that value's place"
stamp_has 'none of the declared words' "the confidence groups are the declared words, not a hard-coded three"
case "$stamp" in
*'`undeclared` row below'*) fail "the tier bullet points at the undeclared row 'below' — the rule is the bullet above it" ;;
*) pass "the tier bullet points at the undeclared rule where it is" ;;
esac
stamp_has 'Route: `/to-tickets`' "its findings leave through /to-tickets like the other seven"
# M-2 (review of PR #368): every rated label row that is a finding routes to
# the label rule and the confidence rule, by number — not only one that
# mirrors a tier finding.
stamp_has 'any label row with a rate that is a finding to rules 4 and 14' "a rated label finding routes to /to-tickets rules 4 and 14"
for f in "$SKILL_ABS" "$ROOT/.agents/skills/retro/QUESTIONS.md"; do
	case "$(flat <"$f")" in
	*'mirrors a tier-override'* | *'mirrors a tier override'*) fail "${f#"$ROOT"/} still routes only a label finding that mirrors a tier finding" ;;
	*) pass "${f#"$ROOT"/} routes a label finding whether or not it mirrors a tier finding" ;;
	esac
done
# The order file, the description and the procedure count with it.
# Held to the EIGHTH ITEM, not the section: a phrase another item carries
# proves nothing about this one (L-3).
item8=$(questions | awk '/^8\. \*\*/ { on = 1 } /^[0-79]\. \*\*/ { on = 0 } on' | flat)
item8_has() { # <needle> <message>
	case "$item8" in
	*"$1"*) pass "$2" ;;
	*) fail "$2 — SKILL.md's eighth item does not say: $1" ;;
	esac
}
item8_has 'per decision field and per skill, never one number for the chain' "SKILL.md's eighth item holds the per-field, per-skill rule"
# …and no stronger than QUESTIONS.md (review of PR #374): a raise with no
# posted marker is still counted, so the item says the dismissal rate counts
# only the posted where the raise says, never "a finding posted" outright.
item8_has 'counting only the posted where the raise says whether it was' "…and the dismissal rate counts only the posted where the raise says, no stronger than question 8"
case "$item8" in
*'how often a finding posted at'*) fail "SKILL.md's eighth item says 'a finding posted' outright — raises with no posted marker are counted too" ;;
*) pass "…and never says 'a finding posted' outright" ;;
esac
item8_has 'Every row carries the oracle clause' "…and the oracle clause on every row"
item8_has 'too few events says so instead of a rate' "…and the thin row that prints no rate"
item8_has 'computable once its stamps carry `data.label_proposed`' "…and the label's override rate, computable once its stamps carry the pre-quiz label"
case "$item8" in
*'which the trace cannot answer today'*) fail "SKILL.md's eighth item still says the trace cannot answer the label's override rate" ;;
*) pass "…and no longer says the trace cannot answer it" ;;
esac
desc=$(sed -n 's/^description: //p' "$SKILL_ABS")
case "$desc" in
*'eight fixed questions'*'stamp calibration'*) pass "the frontmatter description counts eight and names stamp calibration" ;;
*) fail "the frontmatter description does not say 'eight fixed questions' with stamp calibration among them" ;;
esac
assert_file_has "$SKILL" "pivot eight times" "the procedure pivots once per question"
assert_file_has "$SKILL" "data.question=<1..8>" "a candidate note can name the eighth question"
route8=$(awk '/^## Routing/ { on = 1; next } /^## / { on = 0 } on' "$SKILL_ABS" | awk '/^- / { on = 0 } /^- A \*\*stamp\*\*/ { on = 1 } on' | flat)
[ -n "$route8" ] && pass "routing has an entry for a stamp" || fail "the Routing section has no entry for a stamp"
# …and the entry says where each of the three findings goes — the heading
# alone survives the deletion of all three.
for needle in 'rubric line in `/to-tickets`' "that band's definition in \`/review-pr\`" 'a label row with a rate that is a finding → `/to-tickets` rules 4 and 14'; do
	case "$route8" in
	*"$needle"*) pass "the stamp's routing entry names: $needle" ;;
	*) fail "the stamp's routing entry does not name: $needle" ;;
	esac
done
for f in "$SKILL" "$SIDECAR"; do
	no_seven "$f"
done

# ---------------------------------------------------------------------------
banner "2c. A worked example over a FIXTURE trace: question 8's arithmetic prints a rate"
# ---------------------------------------------------------------------------
# The kit's own trace holds too few calibration pairs for any row to carry a
# rate yet, so the demo over it shows thresholds and no arithmetic. This is
# the arithmetic, over a FIXTURE — a scratch trace written by the trace
# script's own `emit`, never the repo's trace, invented numbers and labelled
# as such. It follows question 8's rules for the tier, label and severity rows:
# what it proves is that the rules are computable from what `export` prints,
# and that the attribution, the latest-write rule, the threshold, the undeclared
# row and the one pairing rule give the numbers the prose says they give. It is a
# SECOND implementation of rules the prose states — it cannot go red when the
# prose changes, only when the script or the vocabulary does; the needles in
# 2b hold the prose, and the example rows are held to this arithmetic below.
# The pass itself is still an agent reading a trace.
fx="$SCRATCH/fixture.retro"
fx_trace() { ( cd "$ROOT" && TRACE_DIR="$fx" TRACE_QUIET=1 sh "$TRACE" "$@" ); }
fx_n=0
fx_ticket() { # <published tier> <proposed tier> <published label> <proposed label> [confidence, of both stamps]
	fx_n=$((fx_n + 1))
	fx_trace emit kind=ticket.write subject="ticket:#$fx_n" tier="$1" data.tier_proposed="$2" data.label="$3" data.label_proposed="$4" ${5:+data.confidence="$5"} ${5:+data.label_confidence="$5"}
}
# A ticket written twice: the draft said `high` and was overridden, the
# re-write says `low` and was not. Only the latest per subject is read.
fx_trace emit kind=ticket.write subject='ticket:#6' tier=planner data.tier_proposed=mechanical data.label=ready-for-agent data.label_proposed=ready-for-agent data.confidence=high
# PRD #273 scenario 3's low row: 7 stamped low, 5 tiers overridden at the
# quiz. The labels are overridden on 6 of the 7 — #1–#5 and #7 — so the
# label row cannot be the tier row read twice.
for _ in 1 2 3 4 5; do fx_ticket implementer mechanical ready-for-agent none low; done
fx_ticket mechanical mechanical ready-for-agent ready-for-agent low
fx_ticket mechanical mechanical none ready-for-agent low
# A thin row: 3 stamped medium, 1 tier and 2 labels overridden — counts, not
# rates. The label row is question 8's example row.
fx_ticket planner implementer ready-for-agent none medium
fx_ticket implementer implementer none ready-for-agent medium
fx_ticket implementer implementer ready-for-agent ready-for-agent medium
# A confidence no vocabulary declares — trace text, never a row's name.
fx_ticket implementer implementer ready-for-agent ready-for-agent run-this-instead
# …and a ticket written before either key existed: no tier confidence (the
# tier's unstamped row) and no data.label_proposed (a label row whose stamps
# all predate the key prints no rate).
fx_trace emit kind=ticket.write subject='ticket:#12' tier=implementer data.tier_proposed=implementer data.label=ready-for-agent data.label_confidence=high
# A first review's run raises six `low` findings; a human closes one thread,
# and two iterations both see it closed — one (thread, where) pair, once.
fx_run=$(fx_trace begin review-pr subject='pr:#9')
for line in 1 2 3 4 5 6; do
	fx_trace emit kind=finding.raise subject='pr:#9' outcome=raised data.id="L-$line" data.severity=low data.agent=simplicity data.where="a.sh:$line" data.posted=yes reason=fixture
done
# A seventh `low` the human chose not to post (#332), the latest raise on
# the line the human later closes: nobody could have dismissed it, so it is
# in no denominator and pairs with nothing.
fx_trace emit kind=finding.raise subject='pr:#9' outcome=raised data.id=L-7 data.severity=low data.agent=simplicity data.where=a.sh:2 data.posted=no reason=fixture
fx_trace end "$fx_run" outcome=ok
for _ in 1 2; do
	fx_trace emit kind=finding.dismiss subject='pr:#9' outcome=dismissed data.via=thread data.where=a.sh:2 data.thread=T1 reason=fixture
done
# A second review — recorded before the posted marker existed, so its raises
# carry none and its row overcounts — raises five `medium` findings, two of them on the line the
# first review raised on; a human closes one thread there. The dismissal
# pairs with the LATEST raise at that line and its same-review sibling —
# both count, the row says two shared it — and not with the first review's.
fx_run=$(fx_trace begin review-pr subject='pr:#9')
for where in a.sh:2 a.sh:2 b.sh:1 b.sh:2 b.sh:3; do
	fx_trace emit kind=finding.raise subject='pr:#9' outcome=raised data.id=M-1 data.severity=medium data.agent=simplicity data.where="$where" reason=fixture
done
fx_trace end "$fx_run" outcome=ok
fx_trace emit kind=finding.dismiss subject='pr:#9' outcome=dismissed data.via=thread data.where=a.sh:2 data.thread=T2 reason=fixture
# …and a dismissal at a line nobody raised on is counted beside the table.
fx_trace emit kind=finding.dismiss subject='pr:#9' outcome=dismissed data.via=review data.where=z.sh:1 data.thread=R1 reason=fixture
fx_rows=$(fx_trace export | awk -v conf=" $(sh "$ROOT/scripts/vocab.sh" fields | sed -n 's/^confidence: //p') " \
	-v sev=" $(sh "$ROOT/scripts/vocab.sh" fields | sed -n 's/^severity: //p') " '
	function get(key,   m) { return match($0, "\"" key "\":\"[^\"]*\"") ? substr($0, RSTART + length(key) + 4, RLENGTH - length(key) - 5) : "" }
	# The three sources, in order: the event, its run, its kind.
	function who(kind,   s) {
		if ((s = get("skill")) != "") return s
		if ((s = get("run")) != "" && s in runskill) return runskill[s]
		if (kind == "ticket.write") return "to-tickets (by kind)"
		if (kind == "finding.raise") return "review-pr (by kind)"
		return "unattributed"
	}
	# A confidence names its row only when declared: none is unstamped, any other undeclared.
	function bucket(c) { return c == "" ? "unstamped" : (index(conf, " " c " ") == 0 ? "undeclared" : c) }
	function rate(hit, of) { return of < 5 ? "too few to rate" : sprintf("%.0f %%", 100 * hit / of) }
	{ kind = get("kind") }
	kind == "run.start" { runskill[get("run")] = get("skill") }
	# One ticket.write per subject, the latest: export is in ts order, so a
	# later line for a subject replaces the earlier one.
	kind == "ticket.write" {
		c = get("confidence"); p = get("tier_proposed"); t = get("subject")
		c = bucket(c)
		trow[t] = "tier · " who(kind) " · " c
		tover[t] = (p == "") ? -1 : (get("tier") != p)
		# The label, in a row of its own: its confidence under its own key,
		# overridden where the published label is not the proposed one.
		c = get("label_confidence"); p = get("label_proposed")
		c = bucket(c)
		lrow[t] = "label · " who(kind) " · " c
		lover[t] = (p == "") ? -1 : (get("label") != p)
	}
	kind == "finding.raise" {
		v = get("severity"); if (index(sev, " " v " ") == 0) v = "undeclared"
		k = "severity · " who(kind) " · " v; seen[k] = 1
		# Not posted: in no denominator and in no pairing. No marker: an
		# older raise, counted, and its row overcounts.
		if (get("posted") == "no") { notposted[k]++; next }
		if (get("posted") == "") unmarked[k] = 1
		n++; rrow[n] = k; rat[n] = get("subject") " " get("where"); rrun[n] = get("run")
		of[k]++
	}
	# The one pairing rule: the latest raise at the line before the dismissal,
	# and its siblings there from the same run. A pair seen again is skipped —
	# the earliest is the one read.
	kind == "finding.dismiss" {
		pair = get("subject") " " get("thread") " " get("where")
		if (pair in once) next
		once[pair] = 1
		w = get("subject") " " get("where"); last = 0
		for (i = n; i >= 1; i--) if (rat[i] == w) { last = i; break }
		if (!last) { beside++; next }
		paired = 0
		for (i = 1; i <= n; i++) if (rat[i] == w && (i == last || (rrun[i] != "" && rrun[i] == rrun[last]))) {
			paired++
			if (!gone[i]) { gone[i] = 1; hit[rrow[i]]++ }
		}
		if (paired > 1) shared[rrow[last]] += paired
	}
	END {
		for (t in trow) { k = trow[t]; seen[k] = 1; if (tover[t] >= 0) { of[k]++; hit[k] += tover[t] } }
		for (t in lrow) { k = lrow[t]; seen[k] = 1; stamped[k]++; if (lover[t] >= 0) { of[k]++; hit[k] += lover[t] } }
		# A label row none of whose stamps carries the pre-quiz label: its count
		# and the words, never 0 of 0.
		for (k in seen) {
			if (k ~ /^label/ && !of[k]) { printf "%s   %d stamped   not computable from the trace today\n", k, stamped[k]; continue }
			line = sprintf("%s   %d of %d %s   %s", k, hit[k], of[k], (k ~ /^(tier|label)/ ? "overridden" : "dismissed"), rate(hit[k], of[k]))
			if (k in shared) line = line "   " shared[k] " shared a dismissal"
			# A severity row says which form it used, and counts its unposted raises beside it.
			if (k ~ /^severity/) {
				line = line "   " (k in unmarked ? "overcounts" : "posted only")
				if (notposted[k]) line = line "   " notposted[k] " not posted"
			}
			print line
		}
		printf "beside the table: %d dismissal(s) that pair with no raise\n", beside
	}' | sort)
printf '    fixture trace, not the repo'"'"'s — %s events written by `emit` under a scratch TRACE_DIR:\n' "$(fx_trace export | grep -c .)"
printf '%s\n' "$fx_rows" | sed 's/^/      | /'
fx_row() { # <row, exact> <message>
	printf '%s\n' "$fx_rows" | grep -qxF -- "$1" && pass "$2" || fail "$2 — the fixture's table has no row: $1"
}
fx_row 'tier · to-tickets (by kind) · low   5 of 7 overridden   71 %' "a row with seven events prints a rate: 5 of 7 overridden, 71 % — attributed by kind, /to-tickets having opened no run"
fx_row 'tier · to-tickets (by kind) · medium   1 of 3 overridden   too few to rate' "a row with three events prints its counts and no rate"
fx_row 'tier · to-tickets (by kind) · undeclared   0 of 1 overridden   too few to rate' "a confidence no vocabulary declares is counted on the undeclared row"
printf '%s\n' "$fx_rows" | grep -qF 'run-this-instead' && fail "the undeclared confidence's own text reached a row's name" ||
	pass "…and its text names no row"
fx_row 'tier · to-tickets (by kind) · unstamped   0 of 1 overridden   too few to rate' "a ticket.write with no confidence goes on the unstamped row"
# The label rows (H-2, review of PR #368): grouped by data.label_confidence,
# overridden where data.label differs from data.label_proposed — overrides
# the fixture places apart from the tier's, so a row read off the tier keys
# cannot pass for one read off the label keys.
fx_row 'label · to-tickets (by kind) · low   6 of 7 overridden   86 %' "a label row with seven events prints a rate: 6 of 7 overridden, 86 % — read off the label keys, not the tier's 5 of 7"
fx_row 'label · to-tickets (by kind) · medium   2 of 3 overridden   too few to rate' "a label row with three events prints its counts and no rate"
fx_row 'label · to-tickets (by kind) · undeclared   0 of 1 overridden   too few to rate' "a label confidence no vocabulary declares is counted on the undeclared label row"
fx_row 'label · to-tickets (by kind) · high   1 stamped   not computable from the trace today' "a label row whose stamps all predate data.label_proposed prints its count and not computable, never 0 of 0"
fx_row 'severity · review-pr · low   1 of 6 dismissed   17 %   posted only   1 not posted' "six posted raises, one dismissed twice over: 1 of 6, 17 % — the pair counted once, the skill read from the run's run.start, and the raise nobody posted is in no denominator and no pairing"
fx_row 'severity · review-pr · medium   2 of 5 dismissed   40 %   2 shared a dismissal   overcounts' "a second review's two raises on one line share one dismissal: both count, the row says so, the first review's raise there is not paired again — and raises with no posted marker say the row overcounts"
fx_row 'beside the table: 1 dismissal(s) that pair with no raise' "a dismissal that pairs with no raise is counted beside the table, in no band"
printf '%s\n' "$fx_rows" | grep -qE '^tier .*· high |^label .*· unstamped ' && fail "the fixture's table has a tier high row or a label unstamped row — an earlier ticket.write of a re-written subject was read" ||
	pass "a subject written twice is read once, at its latest write"
# The prose's own example rows are arithmetic too (second local review, M-1):
# a rate is the rounded share of its counts, a row under five events carries
# no rate, every row carries the clause — and the row the fixture computes
# for scenario 3 is the row the example shows.
ex_bad=
while IFS= read -r row; do
	[ -n "$row" ] || continue
	case $row in *'— oracle: '*) ;; *) ex_bad="$ex_bad [no oracle clause: ${row%% *}]" ;; esac
	counts=$(printf '%s\n' "$row" | sed -n 's/.* \([0-9][0-9]*\) of \([0-9][0-9]*\) [od][a-z]* .*/\1 \2/p')
	[ -n "$counts" ] || continue
	hit=${counts% *}
	of=${counts#* }
	if [ "$of" -lt 5 ]; then
		case $row in *'too few to rate'*) ;; *) ex_bad="$ex_bad [$hit of $of carries a rate]" ;; esac
	else
		want=$(awk -v h="$hit" -v o="$of" 'BEGIN { printf "%.0f %%", 100 * h / o }')
		case $row in *"   $want   "*) ;; *) ex_bad="$ex_bad [$hit of $of is $want]" ;; esac
	fi
done <<EOF
$rows8
EOF
[ -z "$ex_bad" ] && pass "every example row's rate is the rounded share of its counts, thin rows carry none, and each carries the oracle clause" ||
	fail "an example row in question 8 does not follow the question's own rules:$ex_bad"
printf '%s\n' "$rows8" | grep -qF 'tier · to-tickets (by kind) · low       5 of 7 overridden   71 %' &&
	pass "the example's scenario-3 row is the row the fixture computes" ||
	fail "the example's low row is no longer '5 of 7 overridden   71 %' — the fixture computes that row; move both together"
for lr in 'label · to-tickets (by kind) · medium   2 of 3 overridden   too few to rate' \
	'label · to-tickets (by kind) · high   1 stamped   not computable from the trace today'; do
	printf '%s\n' "$rows8" | tr -s ' ' | grep -qF "$(printf '%s' "$lr" | tr -s ' ')" &&
		printf '%s\n' "$fx_rows" | grep -qxF -- "$lr" &&
		pass "the example's label row is the row the fixture computes: $lr" ||
		fail "the example's label row is no longer the fixture's '$lr' — move both together"
done
( cd "$ROOT" && TRACE_DIR="$fx" TRACE_QUIET=1 sh "$TRACE" verify >/dev/null 2>&1 ) && pass "and the fixture trace verifies" ||
	fail "the fixture trace does not verify"

# ---------------------------------------------------------------------------
banner "3. It reads by the plain script name, verifies first, and never names the kit wrapper"
# ---------------------------------------------------------------------------
for sub in show summary export verify; do
	if grep -qE "sh scripts/trace\\.sh +$sub\\b" "$SKILL_ABS" "$SIDECAR_ABS"; then
		pass "/retro runs sh $TRACE $sub"
	else
		fail "/retro never runs sh $TRACE $sub — the reader the ticket names"
	fi
done
for f in "$SKILL" "$SIDECAR"; do
	assert_file_lacks "$f" "trace.kit.sh" "the wrapper is kit-only and deleted by bootstrap; a consumer following it runs nothing"
done
grep -qE 'summary +--by' "$SKILL_ABS" "$SIDECAR_ABS" && pass "summary is asked by an axis (--by)" || fail "no 'summary --by' in the sidecar"
grep -qE 'export +--csv' "$SKILL_ABS" "$SIDECAR_ABS" && pass "export is asked as CSV, the shape a pivot reads" || fail "no 'export --csv' in the sidecar"
grep -qE 'show +run:' "$SKILL_ABS" "$SIDECAR_ABS" >/dev/null && pass "a run is read by its own id (show run:<id>)" ||
	fail "show run:<id> is never used — story 25 gave a run an id for this"
# In the PROCEDURE, verify comes before any read: a damaged trace is finding
# zero. (The window section above it reads too — to find the last run — and
# that read is not the pass; the procedure is.)
# verify has two ways to say no, and they ask opposite things (ADR-0008
# clause 4 as amended): exit 1 is a damaged line, exit 3 a schema this reader
# cannot judge — no line to name, and nothing to read until the script is
# updated. A damaged line is permanent: nothing edits an event file (clause 5).
assert_file_has "$SKILL" "Exit 3" "a trace this reader cannot judge is its own case, not a damaged line"
assert_file_has "$SKILL" "UNSUPPORTED SCHEMA" "…recognised by the line summary prints for it"
assert_file_has "$SKILL" "not a first retro" "…and an empty window after it is never read as a first retro"
assert_file_has "$SKILL" "a correction is a new event" "a damaged line is not 'fixed' — the window moves past it"
assert_file_lacks "$SKILL" "until it is fixed" "nothing rewrites an event file, so nothing waits for a fix"
# The previous retro's candidates sit BEFORE its run end, outside the default
# window by construction — so the recurrence check needs its own read (M-4).
grep -qE 'show +run:<id> +--kind +note' "$SKILL_ABS" && pass "the previous retro's candidates are read by its run id — the window alone never reaches them" ||
	fail "no 'show run:<id> --kind note' — the 'repeats a previous retro' route has nothing to compare against"
procedure() { awk '/^## Procedure/ { on = 1; next } /^## / { on = 0 } on' "$SKILL_ABS"; }
v_step=$(procedure | grep -nE "sh scripts/trace\\.sh +verify" | head -1 | cut -d: -f1)
r_step=$(procedure | grep -nE "sh scripts/trace\\.sh +(show|summary|export)" | head -1 | cut -d: -f1)
b_step=$(procedure | grep -nE "sh scripts/trace\\.sh +begin" | head -1 | cut -d: -f1)
[ -n "$v_step" ] && [ -n "$b_step" ] && [ "$v_step" -lt "$b_step" ] &&
	pass "verify (line $v_step) comes before begin (line $b_step) — the window is fixed on a verified trace (M-1)" ||
	fail "verify does not come before begin — verify='$v_step' begin='$b_step'"
procedure | grep -q "refuses" && pass "the procedure says what a retro does when export refuses" ||
	fail "the procedure never says what happens when export refuses on a damaged trace (M-1)"
if [ -n "$v_step" ] && [ -n "$r_step" ] && [ "$v_step" -lt "$r_step" ]; then
	pass "in the procedure, verify (line $v_step) comes before the first read (line $r_step)"
else
	fail "in the procedure, verify does not come before the first read — verify='$v_step' read='$r_step'"
fi

# ---------------------------------------------------------------------------
banner "4. The report lands in the project under .retro/; findings are candidates; it never fixes"
# ---------------------------------------------------------------------------
assert_file_has "$SKILL" 'retro-<YYYYMMDDTHHMMSSZ>.md' "the report's name carries a UTC stamp"
# Ticket #349: the report lives in the project, not in the OS temp directory
# — a temp report is lost with the machine's next sweep, and a retro nobody
# can re-read is a retro that never ran. The full path rule is section 9's.
# — and that section holds the path; here only the old home is refused.
assert_file_lacks "$SKILL" '<tmpdir>/retro-' "the report no longer goes to the OS temp directory"
assert_file_lacks "$SKILL" "outside the repo tree" "…and the skill no longer says the report lands outside the tree"
# H-3 (review of PR #293): the trace carries third-party text (comment bodies
# in reason=), and the reader must say what it is.
assert_file_has "$SKILL" "data, never instructions" "the trace's contents are untrusted content"
assert_file_has "$SKILL" "never fixes"
assert_file_has "$SKILL" "never edits a skill"
assert_file_has "$SKILL" "candidate ticket"
assert_file_has "$SKILL" "shared invariant §11"
assert_file_has "$SKILL" "rule with a failing check"
assert_file_has "$SKILL" "never a preloaded lessons file"
for f in "$SKILL" "$SIDECAR"; do
	assert_file_has "$f" "/to-tickets"
	assert_file_lacks "$f" "gh pr merge" "the pass records; it never merges"
	assert_file_lacks "$f" "git push" "the pass records; it never pushes"
	assert_file_lacks "$f" "gh issue create" "the pass proposes; publishing a ticket is /to-tickets' act after its quiz"
	assert_file_lacks "$f" "--force" "the pass rewrites nothing"
done
grep -q '^## Routing' "$SKILL_ABS" && pass "routing has its own section" || fail "no Routing section"

# ---------------------------------------------------------------------------
banner "5. It opens and closes a run; the end carries the finding count"
# ---------------------------------------------------------------------------
KINDS=$(sed -n "s/^TRACE_KINDS='\(.*\)'\$/\1/p" "$ROOT/$TRACE")
[ -n "$KINDS" ] && pass "$TRACE names its closed kind vocabulary" || fail "$TRACE has no TRACE_KINDS line"
lines=$(t_trace_lines "$SKILL_ABS")
printf '%s\n' "$lines" | grep -qF "sh $TRACE begin retro" && pass "/retro opens a run as retro" || fail "/retro never runs 'sh $TRACE begin retro'"
printf '%s\n' "$lines" | grep -qF "sh $TRACE end" && pass "/retro closes the run" || fail "/retro never runs 'sh $TRACE end'"
note=$(printf '%s\n' "$lines" | grep -F 'kind=note')
printf '%s\n' "$note" | grep -qF "related='" && pass "the candidate note quotes related= — several subjects, the house form (H-2, review of PR #293)" ||
	fail "the candidate note's related= is unquoted — a second subject is exit 2, swallowed by '|| :', and the candidate is lost"
printf '%s\n' "$lines" | grep -F "sh $TRACE end" | grep -qF 'data.findings=' &&
	pass "the end carries data.findings= — the count PRD #237 scenario 8 asks for" ||
	fail "the end does not carry data.findings="
for k in $(printf '%s\n' "$lines" | grep -oE 'kind=[a-z][a-z.]*' | sed 's/^kind=//' | sort -u); do
	case " $KINDS " in
	*" $k "*) pass "/retro emits $k, which $TRACE knows" ;;
	*) fail "/retro emits kind=$k, which $TRACE does not know — the vocabulary is closed" ;;
	esac
done
bare=$(grep -nE "sh scripts/trace\\.sh +(emit|begin|end)" "$SKILL_ABS" "$SIDECAR_ABS" | grep -vF '|| :' || true)
[ -z "$bare" ] && pass "every emit, begin and end tolerates failure ('|| :')" ||
	{ fail "a trace call has no '|| :' — ADR-0008 clause 4:"; printf '%s\n' "$bare" | sed 's/^/        | /'; }
open=$(grep -n '`sh scripts/trace\.sh' "$SKILL_ABS" "$SIDECAR_ABS" | grep -vE '`sh scripts/trace\.sh[^`]*`' || true)
[ -z "$open" ] && pass "every trace span closes on the line it opens" ||
	{ fail "a trace span runs past its line:"; printf '%s\n' "$open" | sed 's/^/        | /'; }

# Every documented span RUNS, placeholders made literal by t_trace_runnable.
# Reads run against the same scratch trace the emits write to, in file
# order, so a read that comes first sees an empty trace and must still exit
# 0 — which is what the first retro over a fresh trace meets.
dir="$SCRATCH/run.retro"
n=0; bad=0
for f in "$SKILL_ABS" "$SIDECAR_ABS"; do
	while IFS= read -r span; do
		[ -n "$span" ] || continue
		n=$((n + 1))
		cmd=$(t_trace_runnable "$span")
		err=$( cd "$ROOT" && TRACE_DIR="$dir" TRACE_QUIET=1 sh -c "$cmd" 2>&1 >/dev/null ); st=$?
		if [ "$st" != 0 ]; then
			bad=$((bad + 1))
			fail "a documented line does not run (exit $st): $span"
			printf '        | as run: %s\n        | %s\n' "$cmd" "$err"
		fi
	done <<EOF
$(t_trace_spans "$f")
EOF
done
[ "$bad" = 0 ] && pass "all $n documented trace lines run" || true
[ "$n" -ge 8 ] && pass "$n spans documented — the reads and the writes" || fail "only $n trace spans documented"
if [ -d "$dir" ]; then
	( cd "$ROOT" && TRACE_DIR="$dir" TRACE_QUIET=1 sh "$TRACE" verify >/dev/null 2>&1 ) &&
		pass "and what they wrote verifies" || fail "the lines ran but the trace they wrote does not verify"
	# The begin/end pair really opened and closed a run named retro, and the
	# end carried the count: the two facts the next retro's window reads.
	grep '"kind":"run.start"' "$dir"/events/*.jsonl | grep -q '"skill":"retro"' &&
		pass "the scratch trace holds a run.start for skill retro" || fail "no run.start with skill=retro in the scratch trace"
	grep '"kind":"run.end"' "$dir"/events/*.jsonl | grep -q '"findings":"' &&
		pass "…and a run.end carrying data.findings" || fail "no run.end carrying data.findings in the scratch trace"
	# L-2 (review of PR #293): the window span is a pipeline ending in tail,
	# which exits 0 on empty input, so its exit status proves nothing. Run it
	# again now that a retro run is seeded and hold its OUTPUT to that run.
	# The window span is the first in the window section (ticket #461): it
	# prints the closed retro's run.end, whose ts is the window's since.
	wspan=$(window_section | grep -o '`sh scripts/trace\.sh[^`]*`' | tr -d '`' | head -1)
	wout=$( cd "$ROOT" && TRACE_DIR="$dir" TRACE_QUIET=1 sh -c "$(t_trace_runnable "$wspan")" 2>/dev/null )
	printf '%s\n' "$wout" | grep -qF '"kind":"run.end"' &&
		pass "the window span's output is the seeded retro's run.end — the pipeline selects, not just exits 0" ||
		fail "the window span printed no run.end over a trace that holds a closed retro: $wspan"
fi

# ---------------------------------------------------------------------------
banner "6. The default window is since its own last run end"
# ---------------------------------------------------------------------------
assert_file_has "$SKILL" "since its own last" "the default window is the skill's own clock"
assert_file_has "$SKILL" "run.end" "…read from its last run.end"
assert_file_has "$SKILL" "--since" "…and --since overrides it"
assert_file_has "$SKILL" "first retro" "a first retro has no last run: the whole trace, and the report says so"

# ---------------------------------------------------------------------------
banner "7. Every command and path resolves; no model id"
# ---------------------------------------------------------------------------
t_assert_skill_commands 3 "the skill should name at least /to-tickets, /housekeeping and /diagnose" "$SKILL_ABS" "$SIDECAR_ABS"
t_assert_skill_paths 2 "the skill should name the trace script and the glossary" "$SKILL_ABS" "$SIDECAR_ABS"
t_assert_no_model_id "$SKILL_ABS" "$SIDECAR_ABS"

# ---------------------------------------------------------------------------
banner "8. The roster knows the skill, and the kit holds it to its suites"
# ---------------------------------------------------------------------------
t_assert_skill_in_roster "retro"
grep -q '`/retro`' "$ROOT/AGENTS.md" && pass "the kit's own manual names /retro" || fail "AGENTS.md never names /retro — the gate would report an orphan"
grep -q '`/retro`' "$ROOT/README.md" && pass "README names /retro" || fail "README never names /retro"
grep -q 'tests/retro-skill.test.sh' "$ROOT/README.md" && pass "README names this suite" || fail "README does not name tests/retro-skill.test.sh"
# Every surface that counts the questions counts eight (ticket #281): the two
# manuals say it twice each — the chain paragraph and the quick-reference row
# — and the glossary, README and the provenance file once.
count_eight() { # <file> <at least> <needle>
	n=$(flat <"$ROOT/$1" | grep -oF "$3" | grep -c .)
	[ "$n" -ge "$2" ] && pass "$1 says '$3' $n time(s), at least the $2 expected" || fail "$1 says '$3' $n time(s), expected at least $2"
	no_seven "$1"
}
count_eight AGENTS.md 2 'eight fixed questions'
count_eight constitution/AGENTS.md.template 2 'eight fixed questions'
count_eight docs/domain-glossary.md 1 'eight fixed questions'
count_eight README.md 1 'the eight fixed questions'
count_eight .agents/skills/LICENSE-mattpocock-skills.md 1 'eight questions'
for f in constitution/AGENTS.md.template docs/domain-glossary.md; do
	flat <"$ROOT/$f" | grep -qF 'stamp calibration' && pass "$f names stamp calibration among the questions" ||
		fail "$f lists the questions without stamp calibration"
done
grep -q '/retro' "$ROOT/.agents/skills/housekeeping/CHECKLIST.md" &&
	pass "/housekeeping's checklist asks whether a retro ran inside its window (story 12)" ||
	fail "/housekeeping's checklist never names /retro — the loop has no clock"
grep -q 'retro' "$ROOT/tests/trace-skills.test.sh" &&
	pass "tests/trace-skills.test.sh names retro as the one skill allowed to read" ||
	fail "tests/trace-skills.test.sh does not name retro — its read ban is either broken or unexcepted"
grep -F 'KIT_ONLY=' "$ROOT/bootstrap.sh" | grep -q 'tests/retro-skill.test.sh' &&
	pass "bootstrap's KIT_ONLY list names this suite" || fail "tests/retro-skill.test.sh is not on bootstrap's KIT_ONLY list — it would ship to consumers"
grep -q 'sh tests/retro-skill.test.sh' "$ROOT/.github/workflows/kit-ci.yml" &&
	pass "kit CI runs this suite" || fail "no kit CI job runs tests/retro-skill.test.sh"

# ---------------------------------------------------------------------------
banner "9. The report lives in the project under .retro/ at the root checkout (ticket #349)"
# ---------------------------------------------------------------------------
# 9a. The path rule, in the procedure's two writing steps — the export (step
# 4, the first thing written, so the folder is resolved and made THERE: review
# of PR #362, M1) and the report (step 5, beside it): .retro/<YYYY>/<MM>/ at
# the ROOT CHECKOUT, the root found through git's common directory — the
# derivation scripts/trace.sh and the cleanup script share — so a retro run
# from a worktree lands at the root and the worktree's pruning loses nothing.
export_step=$(procedure | awk '/^4\. \*\*/ { on = 1 } /^[0-35-9]\. \*\*/ { on = 0 } on' | flat)
write_step=$(procedure | awk '/^5\. \*\*/ { on = 1 } /^[0-46-9]\. \*\*/ { on = 0 } on' | flat)
step_has() { # <step text> <step name> <needle> <message>
	case "$1" in
	*"$3"*) pass "$4" ;;
	*) fail "$4 — the procedure's $2 step does not say: $3" ;;
	esac
}
export_has() { step_has "$export_step" export "$@"; }
write_has() { step_has "$write_step" write "$@"; }
export_has 'git rev-parse --path-format=absolute --git-common-dir' "the export step resolves the root through git's common directory — the one-line derivation, before anything is written"
export_has 'mkdir -p "$root/.retro/<YYYY>/<MM>"' "…and makes the folder there"
export_has 'root checkout' "…at the root checkout"
export_has 'scripts/trace.sh' "…named as the same derivation the trace script uses for a relative TRACE_DIR"
export_has 'as `.csv`' "…and saves the export there as .csv"
export_has 'prints nothing' "…and says what to do when the derivation prints nothing: outside a repository there is no trace to read (L5)"
write_has '.retro/<YYYY>/<MM>/retro-<YYYYMMDDTHHMMSSZ>.md' "the write step names the report's path under .retro/<YYYY>/<MM>/"
write_has 'beside the export' "…beside the export step 4 saved"
write_has 'linked worktree' "…so a retro run from a linked worktree lands at the root"
write_has "worktree's pruning" "…and survives the worktree's pruning"
write_has 'check-ignore -q .retro/' "the write step checks the folder is ignored before it writes (H1)"
# Not ignored: the pass TELLS, it never writes a consumer's ignore file — the
# kit owns no consumer's tracked file and nothing it ships edits one at
# runtime (PRD #237, alternatives considered). The line to add is printed,
# the report's first line says so, and the pass carries on.
write_has 'does not touch the project' "…and when it is not, the pass does not touch the project's ignore file"
write_has 'the one line to add' "…it prints the one line to add"
write_has 'beside `.trace/`' "…`.retro/` beside the trace's own"
write_has "report's first line" "…and says so in the report's first line"
case "$write_step" in
*'add `.retro/` to the project'* | *'adds the line'* | *'add it yourself'*) fail "the write step still has the pass write a consumer's ignore file — it tells, it never edits" ;;
*) pass "the write step never has the pass edit a consumer's ignore file" ;;
esac
write_has 'a project that takes this skill' "…which is also the consumer's note, since the recipe cannot carry it without moving the shared layer"
# The derivation is quoted as ONE code span, so a session copies one line and
# a suite can run it. Extracted from the export step by its distinctive token
# (L1) — never from the whole file, never by position.
derive=$(printf '%s' "$export_step" | grep -o '`[^`]*git-common-dir[^`]*`' | head -1 | tr -d '`')
[ -n "$derive" ] && pass "the derivation is one code span in the export step: $derive" || fail "no code span in the export step carries git-common-dir"
# The parity the skill claims is held to the two scripts it is claimed with
# (L2): the same flag pair in scripts/trace.sh and the cleanup script, so a
# change to either goes red here and the sentence is re-read.
for f in scripts/trace.sh scripts/worktree-cleanup.sh; do
	grep -qF -- 'rev-parse --path-format=absolute --git-common-dir' "$ROOT/$f" &&
		pass "$f still resolves the root with the same flag pair the skill quotes" ||
		fail "$f no longer uses 'rev-parse --path-format=absolute --git-common-dir' — the skill's parity claim is stale"
done
# 9b. The derivation RUNS, from a linked worktree of a scratch repo, and
# prints that repo's root — not the worktree. A rule whose one line was
# never executed is a claim (hard rule 9).
t_repo
git -C "$REPO" worktree add -q "$REPO/worktree/wt" -b feat/wt 2>/dev/null
got=$( cd "$REPO/worktree/wt" && sh -c "$derive; printf '%s' \"\$root\"" 2>/dev/null )
want=$(cd "$REPO" && pwd -P)
[ -n "$got" ] && [ "$(cd "$got" 2>/dev/null && pwd -P)" = "$want" ] &&
	pass "run from a linked worktree, the derivation prints the root checkout" ||
	fail "run from a linked worktree, the derivation printed '$got', not the root '$want'"
got=$( cd "$REPO" && sh -c "$derive; printf '%s' \"\$root\"" 2>/dev/null )
[ -n "$got" ] && [ "$(cd "$got" 2>/dev/null && pwd -P)" = "$want" ] &&
	pass "run from the root checkout, the derivation prints the root checkout" ||
	fail "run from the root checkout, the derivation printed '$got', not '$want'"
# 9c. The folder is out of version control, beside the trace's — a report
# carries trace text (reasons, comment bodies, costs) and is local by design,
# and a gitignored folder is invisible to the docs gate's placeholder scan.
grep -qx '\.retro/' "$ROOT/.gitignore" && pass ".gitignore keeps .retro/ out of version control" || fail ".gitignore does not list .retro/"
# 9d. Every surface that said where the report lands now says the folder:
# the kit's manual and its stamped template (the quick-reference row), the
# README's suite paragraph, the glossary's Retro entry — which also names the
# folder as the kit's own word — and /housekeeping's checklist, whose check
# is unchanged (a report dated inside the window) but looks in the new place.
# Scoped to the unit that describes the retro (M3): other skills write their
# reports outside the tree on purpose, and a row about one of them is not
# this suite's to fail. The manuals' unit is the quick-reference row (one
# line); the README's is this suite's own bullet; the glossary's is the two
# Retro entries; the checklist's is the retrospective bullet.
retro_text() { # <file> — the unit about the retro, flattened
	case "$1" in
	*CHECKLIST.md) awk '/^- \*\*The retrospective/ { on = 1; print; next } /^- / { on = 0 } on' "$ROOT/$1" ;;
	README.md) awk '/^- `sh tests\/retro-skill\.test\.sh`/ { on = 1; print; next } /^- / { on = 0 } on' "$ROOT/$1" ;;
	*glossary.md) awk '/^- \*\*Retro( folder)?\*\*/ { on = 1; print; next } /^- \*\*/ { on = 0 } on' "$ROOT/$1" ;;
	*) grep -F '`/retro`' "$ROOT/$1" ;;
	esac | flat
}
for f in AGENTS.md constitution/AGENTS.md.template README.md docs/domain-glossary.md .agents/skills/housekeeping/CHECKLIST.md; do
	t=$(retro_text "$f")
	[ -n "$t" ] || { fail "$f has no line about the retro"; continue; }
	printf '%s' "$t" | grep -qF '.retro/' && pass "$f names .retro/ where it describes the retro" || fail "$f's retro line does not name .retro/"
	printf '%s' "$t" | grep -qiE 'outside the (repo )?tree|under the temp' &&
		fail "$f still sends the retro report outside the tree" || pass "$f no longer sends the retro report outside the tree"
done
# The glossary's own word for the folder — an entry, held to its text (M2).
entry=$(awk '/^- \*\*Retro folder\*\*/ { on = 1; print; next } /^- \*\*/ { on = 0 } on' "$ROOT/docs/domain-glossary.md" | flat)
[ -n "$entry" ] && pass "the glossary has a Retro folder entry" || fail "the glossary has no '**Retro folder**' entry"
entry_has() { case "$entry" in *"$1"*) pass "$2" ;; *) fail "$2 — the Retro folder entry does not say: $1" ;; esac; }
entry_has '.retro/<YYYY>/<MM>/' "…naming the path"
entry_has 'root checkout' "…at the root checkout"
entry_has 'common directory' "…resolved through git's common directory"
entry_has '`.trace/`' "…gitignored beside the trace"


# ---------------------------------------------------------------------------
banner "10. Question 7 counts an unasked verdict with the landings that got none (ticket #372)"
# ---------------------------------------------------------------------------
# /merge-train records `feedback outcome=unasked` when an autonomous train
# could not ask the verdict (PR #361). Read as one more outcome beside
# hit|adjusted|missed, an unasked landing passes for an answered one and the
# retro goes blind to the gap. Held to the seventh SECTION's prose, flattened:
# the `Reads:` paragraph lists the outcomes too, so a needle it satisfies
# would survive the rule's deletion; the Route paragraph, wrapped lines and
# all, is held apart (review of PR #377, M-1).
sec7() { awk '/^## 7\. / { on = 1; next } /^## / { on = 0 } on' "$SIDECAR_ABS"; }
sec7_prose=$(sec7 | awk '/^\*Reads:/ { r = 1 } /^Route:/ { x = 1 } (r || x) && /^$/ { r = x = 0; next } !r && !x' | flat)
sec7_route=$(sec7 | awk '/^Route:/ { on = 1 } on && /^$/ { exit } on' | flat)
q7_has() { case "$sec7_prose" in *"$1"*) pass "$2" ;; *) fail "$2 — question 7's prose does not say: $1" ;; esac; }
q7_has '`unasked`' "question 7 names the unasked outcome"
q7_has 'is not a verdict' "…says an unasked landing is not a verdict"
q7_has 'with the landings that got no verdict' "…and counts it with the landings that got no verdict"
q7_has '`<n> unasked, <m> without a feedback event`' "…naming each apart on the row: n unasked, m without a feedback event"
case "$sec7_route" in
*'`unasked`'*'`/merge-train`'*) pass "question 7's route sends the unasked verdicts to /merge-train with the missing ones" ;;
*) fail "question 7's Route line does not send the unasked verdicts to /merge-train" ;;
esac
# `unasked` is the train's word alone (tests/trace-skills.test.sh holds
# /pr-iterate to hit|adjusted|missed): the Reads paragraph, which names both
# emitters, says so rather than listing it as theirs (review of PR #377, L-1).
sec7_reads=$(sec7 | awk '/^\*Reads:/ { r = 1 } r && /^$/ { exit } r' | flat)
case "$sec7_reads" in
*'`unasked` (the train'"'"'s alone)'*) pass "the Reads paragraph says unasked is /merge-train's alone" ;;
*) fail "the Reads paragraph lists unasked without saying it is /merge-train's alone" ;;
esac
# The order's one-line summary in SKILL.md carries the same distinction.
q7_line=$(awk '/^7\. \*\*Aim calibration\*\*/ { on = 1; print; next } /^[0-9]+\. / { on = 0 } on' "$SKILL_ABS" | flat)
case "$q7_line" in
*'`unasked`'*) pass "SKILL.md's question 7 counts an unasked verdict as no verdict" ;;
*) fail "SKILL.md's question 7 does not name the unasked verdict" ;;
esac


# ---------------------------------------------------------------------------
banner "11. Question 7 counts a delegated train's verdict apart from the operator's (ticket #385)"
# ---------------------------------------------------------------------------
# Retro G3: fifteen train verdicts, all written under a standing instruction
# that delegated every decision, and question 7 read them as the human's.
# `feedback` now carries data.by=operator|train (ADR-0008, amended
# 2026-10-01, #385); the question counts the two apart and a window whose
# verdicts are all `train` is reported as no human verdict. Held the way
# section 10 holds unasked: the seventh section's prose, Reads and Route
# apart, flattened — section 10's own $sec7_prose, $sec7_route, $sec7_reads
# and $q7_line (review of PR #393, M-7).
q7_has '`data.by`' "question 7 reads data.by"
q7_has '`operator`' "…names the operator's verdict"
q7_has '`train`' "…and the train's"
q7_has 'never the human'"'"'s verdict' "…says a train's verdict is never the human's"
q7_has '`<n> operator, <m> train`' "…counts the two apart on the row: n operator, m train"
q7_has 'no human verdict' "…and reports a window whose verdicts are all train as no human verdict"
q7_has 'no `data.by`' "…and says what a feedback written before the key counts as"
q7_has '`<p> unattributed`' "…: p unattributed (L-3 of the same review)"
q7_has 'never as the operator'"'"'s' "…never as the operator's"
# The first bullet, which counts re-cuts and misses, counts the operator's
# verdicts and not a train's self-assessment (L-1 of the same review).
q7_has 'counting `operator` verdicts' "the per-slice bullet counts operator verdicts toward re-cuts and misses, not a train's"
case "$sec7_reads" in
*'`data.by`'*'`operator`'*'`train`'*) pass "the Reads paragraph lists data.by with its two words" ;;
*) fail "the Reads paragraph does not list \`data.by\` as \`operator\` or \`train\`" ;;
esac
case "$sec7_route" in
*'`train`'*) pass "question 7's route says where a window of train verdicts goes" ;;
*) fail "question 7's Route line does not route the train's verdicts" ;;
esac
case "$q7_line" in
*'`train`'*'no human verdict'*) pass "SKILL.md's question 7 counts a train's verdict apart and names the window with no human verdict" ;;
*) fail "SKILL.md's question 7 does not count a \`train\` verdict apart from the operator's as no human verdict" ;;
esac

# ---------------------------------------------------------------------------
banner "12. Question 6 counts the denied tool calls (ticket #409)"
# ---------------------------------------------------------------------------
# A tool call the operator or a blocking hook refused is now a `tool.use` with
# `outcome=denied`, swept at session end from the pre-tool hook's marker (the
# Claude Code adapter, #409). Question 6 reads them: per session and per tool,
# a denial that recurs is a skill asking for what its agent may not do. Held
# to the sixth section's prose, its Reads paragraph and SKILL.md's line, the
# way section 10 holds question 7.
sec6() { awk '/^## 6\. / { on = 1; next } /^## / { on = 0 } on' "$SIDECAR_ABS"; }
sec6_prose=$(sec6 | awk '/^\*Reads:/ { r = 1 } /^Route:/ { x = 1 } (r || x) && /^$/ { r = x = 0; next } !r && !x' | flat)
sec6_reads=$(sec6 | awk '/^\*Reads:/ { r = 1 } r && /^$/ { exit } r' | flat)
case "$sec6_reads" in
*'`tool.use`'*'`denied`'*) pass "question 6's Reads paragraph lists tool.use with outcome denied" ;;
*) fail "question 6's Reads paragraph does not list \`tool.use\` (\`denied\`)" ;;
esac
case "$sec6_prose" in
*'**Denied tool calls**'*'`data.tool`'*) pass "question 6 counts the denied tool calls per data.tool" ;;
*) fail "question 6 has no **Denied tool calls** bullet counting per \`data.tool\`" ;;
esac
case "$sec6_prose" in
*'recurs'*) pass "…and names a recurring denial as the finding" ;;
*) fail "question 6 does not say which denial is a finding" ;;
esac
q6_line=$(awk '/^6\. \*\*Chain health\*\*/ { on = 1; print; next } /^[0-9]+\. / { on = 0 } on' "$SKILL_ABS" | flat)
case "$q6_line" in
*'denied'*) pass "SKILL.md's question 6 names the denied tool calls" ;;
*) fail "SKILL.md's question 6 does not name the denied tool calls" ;;
esac

# ---------------------------------------------------------------------------
banner "13. The retro learns from its own runs: a closed window, an open sibling, the new keys, the tracker (ticket #461)"
# ---------------------------------------------------------------------------
# Three retros of 2026-10-01 ran at once. The window span's `tail -1` named
# a run.start, and the latest one was a sibling's still open, so a retro read
# from a run that had not ended; two retros over one window filed six
# duplicate tickets between them. Each lesson is held here.
#
# 13a. The window is the last CLOSED retro. A scratch trace holds retro A,
# begun and ended, then retro B, begun and never ended: the window span must
# print A's run.end and nothing of B.
lw="$SCRATCH/learn.retro"
lw_trace() { ( cd "$ROOT" && TRACE_DIR="$lw" TRACE_QUIET=1 sh "$TRACE" "$@" ); }
run_a=$(lw_trace begin retro); lw_trace end "$run_a" outcome=ok data.findings=1 >/dev/null
run_b=$(lw_trace begin retro)
wspan=$(window_section | grep -o '`sh scripts/trace\.sh[^`]*`' | tr -d '`' | head -1)
wout=$( cd "$ROOT" && TRACE_DIR="$lw" TRACE_QUIET=1 sh -c "$(t_trace_runnable "$wspan")" 2>/dev/null )
case "$wout" in
*'"kind":"run.end"'*"$run_a"*) pass "the window span prints the closed retro's run.end" ;;
*) fail "the window span does not print the closed retro's run.end: $wspan" ;;
esac
case "$wout" in
*"$run_b"*) fail "the window span names the open retro $run_b — a run that has not ended is no window" ;;
*) pass "…and never the retro still open" ;;
esac
[ "$(printf '%s\n' "$wout" | grep -c .)" = 1 ] && pass "…as one line" || fail "the window span printed $(printf '%s\n' "$wout" | grep -c .) lines, not one"

# 13b. A retro open beside this one is named in the report's first line and
# left open. The procedure carries the span that lists them; over the same
# scratch trace it prints B and not A.
proc() { awk '/^## Procedure/ { on = 1; next } /^## / { on = 0 } on' "$SKILL_ABS"; }
ospan=$(proc | grep -o '`sh scripts/trace\.sh export[^`]*`' | tr -d '`' | grep -F '"kind":"run.end"' | head -1)
if [ -n "$ospan" ]; then
	oout=$( cd "$ROOT" && TRACE_DIR="$lw" TRACE_QUIET=1 sh -c "$(t_trace_runnable "$ospan")" 2>/dev/null )
	case "$oout" in *"$run_b"*) pass "the open-run span lists the retro still open" ;; *) fail "the open-run span does not list the open retro: $ospan" ;; esac
	case "$oout" in *"$run_a"*) fail "the open-run span lists the closed retro $run_a" ;; *) pass "…and not the closed one" ;; esac
else
	fail "the procedure carries no span listing the retro runs still open"
fi
# Each needle is held to its own numbered step, not the whole procedure: step
# 5 also says "report's first line", and a needle it satisfies would survive
# step 2's rule being deleted (L-1, review of PR #475).
step() { proc | awk -v n="$1" '$0 ~ "^" n "\\. \\*\\*" { on = 1; print; next } /^[0-9]+\. \*\*/ { on = 0 } on' | flat; }
step_has() { case "$(step "$1")" in *"$2"*) pass "$3" ;; *) fail "$3 — step $1 does not say: $2" ;; esac; }
step_has 2 'another retro is open' "step 2 names the case of another retro open"
step_has 2 'report'"'"'s first line' "…says so in the report's first line"
step_has 2 'never closes it' "…and never closes the other run"
step_has 2 'below yours' "…and says where a sibling in this working tree sits: below this pass's run (L-5)"

# 13c. Question 5 reads the compaction gap and the phantom stops; question 6
# the wait-bound keys of a failed agent.stop. Each key is held to the
# sixth/fifth section's Reads paragraph and to the adapter that writes it,
# so a misspelled key is red here before it is a question nobody can answer.
reads_of() { awk -v n="$1" '$0 ~ "^## " n "\\. " { on = 1; next } /^## / { on = 0 } on' "$SIDECAR_ABS" | awk '/^\*Reads:/ { r = 1 } r && /^$/ { exit } r' | flat; }
sec5_reads=$(reads_of 5)
sec6_reads=$(reads_of 6)
for k in 'data.via=rollup' 'data.phantoms'; do
	case "$sec5_reads" in *"\`$k\`"*) pass "question 5's Reads paragraph names $k" ;; *) fail "question 5's Reads paragraph does not name \`$k\`" ;; esac
	grep -qF "\`$k" "$ROOT/adapters/claude-code/README.md" && pass "…a key the adapter documents writing" || fail "$k is no key adapters/claude-code/README.md documents"
done
for k in 'data.last_kind' 'data.last_age_ms'; do
	case "$sec6_reads" in *"\`$k\`"*) pass "question 6's Reads paragraph names $k" ;; *) fail "question 6's Reads paragraph does not name \`$k\`" ;; esac
	grep -qF "\`$k\`" "$ROOT/adapters/claude-code/README.md" && pass "…a key the adapter documents writing" || fail "$k is no key adapters/claude-code/README.md documents"
done
case "$sec6_reads" in *'`agent.stop`'*) pass "question 6 reads agent.stop" ;; *) fail "question 6's Reads paragraph does not name \`agent.stop\`" ;; esac
sec5_prose=$(awk '/^## 5\. / { on = 1; next } /^## / { on = 0 } on' "$SIDECAR_ABS" | flat)
case "$sec5_prose" in *'**Phantom stops**'*) pass "question 5 has a phantom-stops bullet" ;; *) fail "question 5 has no **Phantom stops** bullet" ;; esac
case "$sec5_prose" in *'**The compaction gap**'*) pass "question 5 has a compaction-gap bullet" ;; *) fail "question 5 has no **The compaction gap** bullet" ;; esac
case "$sec6_prose" in *'**Stops read too early**'*) pass "question 6 has a bullet for the stops the wait bound passed" ;; *) fail "question 6 has no **Stops read too early** bullet" ;; esac
# #565 (review of PR #606, M-2): a give-up leaves no anchor, so the agent's
# next stop counts what it could not — a give-up's tokens are lost only when
# no later stop of that agent was priced. The bullet counts per agent as well
# as per stop, and reads data.final, the key the adapter writes on a priced stop.
case "$sec6_reads" in *'`data.final`'*) pass "question 6's Reads paragraph names data.final" ;; *) fail "question 6's Reads paragraph does not name \`data.final\`" ;; esac
grep -qF '`data.final`' "$ROOT/adapters/claude-code/README.md" && pass "…a key the adapter documents writing" || fail "data.final is no key adapters/claude-code/README.md documents"
case "$sec6_prose" in *'its tokens are in no event'*) fail "question 6 still says a give-up's tokens are in no event — a later stop of the agent counts them (#565)" ;; *) pass "question 6 no longer says a give-up's tokens are in no event" ;; esac
case "$sec6_prose" in *'per agent as well as per stop'*) pass "question 6 counts the give-ups per agent as well as per stop" ;; *) fail "question 6 does not count the give-ups per agent as well as per stop" ;; esac
# Questions 7 and 8 already read data.by (#385) and data.label_proposed
# (#354): sections 11 and 2b hold them; one needle each here keeps the
# ticket's list whole in one place.
assert_file_has "$SIDECAR" '`data.by`' "question 7 reads data.by"
assert_file_has "$SIDECAR" '`data.label_proposed`' "question 8 reads data.label_proposed"

# 13d. The report's first line names the sibling reports written in the same
# window, so /to-tickets deduplicates two retros' findings.
step_has 5 'sibling report' "the report step names the sibling reports"
step_has 5 'same window' "…the ones written in the same window"
# The rule RUNS (M-2, review of PR #475): step 5's listing over a scratch
# .retro/ holding a report from before the window, one inside it and this
# pass's own prints only the one inside it.
lspan=$(step 5 | grep -o '`ls "$root"/.retro/[^`]*`' | tr -d '`' | head -1)
if [ -n "$lspan" ]; then
	sr="$SCRATCH/sibling.root"; mkdir -p "$sr/.retro/2026/09" "$sr/.retro/2026/10"
	: >"$sr/.retro/2026/09/retro-20260930T120000Z.md"
	: >"$sr/.retro/2026/10/retro-20261001T080000Z.md"
	: >"$sr/.retro/2026/10/retro-20261001T120000Z.md"
	: >"$sr/.retro/2026/10/retro-20261002T090000Z.md"
	lcmd=$(printf '%s\n' "$lspan" | sed -e 's/<the window start as YYYYMMDDTHHMMSSZ>/20261001T100000Z/' -e 's/<the file name of this report>/retro-20261002T090000Z.md/')
	lout=$(root="$sr" sh -c "$lcmd" 2>&1)
	case "$lout" in *retro-20261001T120000Z.md*) pass "step 5's listing prints the report inside the window" ;; *) fail "step 5's listing missed the sibling inside the window: $lcmd → $lout" ;; esac
	case "$lout" in *retro-20260930T*|*retro-20261001T080000Z*) fail "step 5's listing prints a report from before the window: $lout" ;; *) pass "…and none from before it, the previous retro's own included" ;; esac
	case "$lout" in *retro-20261002T090000Z.md*) fail "step 5's listing prints this pass's own report" ;; *) pass "…and not this pass's own" ;; esac
else
	fail "step 5 carries no runnable listing of the sibling reports (\`ls \"\$root\"/.retro/…\`)"
fi

# 13e. Before a finding is recorded, the tracker is searched for it since the
# window start; a match is named in the findings table and the note's
# related, and a finding with a landed ticket is reported closed.
step_has 6 'gh issue list --state all --search' "the routing step searches the tracker, open and closed"
step_has 6 'created:>=<YYYY-MM-DD>' "…since the window start"
step_has 6 'findings table' "…names a match in the findings table"
step_has 6 'reported closed' "…reports a finding with a landed ticket closed"
step_has 6 'not as a candidate' "…not as a candidate"
# The fix-not-holding exception needs the landing's date, so the search asks
# for it (M-1, L-2, review of PR #475).
step_has 6 'closedAt' "the search returns each match's closing date"
step_has 6 'postdates the landing' "…which a finding's evidence is compared with: a fix that did not hold is a candidate again"
# Step 8 and the never-fix paragraph say every CANDIDATE leaves for
# /to-tickets — a finding reported closed is not one (L-4).
step_has 8 'Every candidate is a ticket' "step 8 routes the candidates, not every finding"
assert_file_has "$SKILL" 'reported closed is named and routed nowhere' "…and says what happens to a finding reported closed"
note_span=$(proc | grep -o '`sh scripts/trace\.sh emit kind=note[^`]*`' | head -1)
case "$note_span" in *'outcome=candidate|closed'*) pass "the note records closed beside candidate" ;; *) fail "the note's outcome is not candidate|closed: $note_span" ;; esac

# ---------------------------------------------------------------------------
banner "14. Question 6 reads a refused spawn as refused, not as a worker nobody waited for (#482)"
# ---------------------------------------------------------------------------
# /review-pr records a lens the host refused to start as `spawn
# outcome=refused` with no `spawn.end` — nothing started, so nothing ends
# (ruling on PR #512). Question 6's no-end rule would count each one as a
# worker nobody waited for, and the refusal itself nowhere. So the Reads
# paragraph lists the spawn's refused outcome, and the no-end sentence
# exempts it and counts it on its own.
case "$sec6_reads" in
*'`spawn` (`outcome` `refused`)'*) pass "question 6's Reads paragraph lists spawn with outcome refused" ;;
*) fail "question 6's Reads paragraph does not list \`spawn\` (\`outcome\` \`refused\`)" ;;
esac
noend=$(printf '%s\n' "$sec6_prose" | awk '{ gsub(/\. /, ".\n"); print }' | grep -F 'nobody waited for')
case "$noend" in
*'`outcome=refused`'*'never started'*) pass "question 6's no-end rule exempts a refused spawn, which never started" ;;
*) fail "question 6 counts a refused spawn as a worker nobody waited for: $noend" ;;
esac
case "$sec6_prose" in
*'**Refused spawns**'*) pass "question 6 counts refused spawns as their own row" ;;
*) fail "question 6 has no **Refused spawns** bullet" ;;
esac

# ---------------------------------------------------------------------------
banner "15. Questions 7 and 8 retire while the project accepts train-only verdicts (#572)"
# ---------------------------------------------------------------------------
# The operator ruled on #570 that train-only landing verdicts are fine, after
# four windows running had re-raised "no human verdict" as a finding nobody
# could act on. So a project that records, in a binding decision record, that
# it accepts train-only verdicts gets questions 7 and 8 answered with one
# retired line — no finding, no note — whenever the window holds no operator
# verdict, and the calibration resumes by itself the first window holding one.
# The skill ships unstamped: the line says "the project", and the kit records
# its own answer as a decision record of its own.
#
# 15a. Each question carries the span that counts its operator verdicts, and
# the span RUNS: over a window of train and unasked verdicts only — no
# dismissal, no quiz override — both print 0, the retired case; over a window
# holding an operator verdict, a dismissal and an override, each prints the
# count, the calibration case.
sec_of() { awk -v n="$1" '$0 ~ "^## " n "\\. " { on = 1; next } /^## / { on = 0 } on' "$SIDECAR_ABS"; }
vspan() { sec_of "$1" | grep -o '`sh scripts/trace\.sh export[^`]*`' | tr -d '`' | head -1; }
v7=$(vspan 7)
v8=$(vspan 8)
[ -n "$v7" ] && pass "question 7 carries a span that counts its operator verdicts" || fail "question 7 carries no \`sh scripts/trace.sh export …\` span counting operator verdicts"
[ -n "$v8" ] && pass "question 8 carries a span that counts its operator verdicts" || fail "question 8 carries no \`sh scripts/trace.sh export …\` span counting operator verdicts"
vcount() { # <trace dir> <span>
	( cd "$ROOT" && TRACE_DIR="$1" TRACE_QUIET=1 sh -c "$(t_trace_runnable "$2")" 2>/dev/null )
}
tw="$SCRATCH/train-only.retro"
tw_trace() { ( cd "$ROOT" && TRACE_DIR="$tw" TRACE_QUIET=1 sh "$TRACE" "$@" ); }
# Before the window (H-1, review of PR #601): an operator verdict, a human
# dismissal and a quiz override, all on a day before the window's start — the
# day file renamed to one the --since day excludes. A span that dropped its
# --since would count them.
tw_trace emit kind=feedback subject='ticket:#9' related='pr:#19' outcome=missed data.by=operator reason=fixture
tw_trace emit kind=finding.dismiss subject='pr:#19' outcome=dismissed data.via=thread data.where=b.sh:1 data.thread=T9 reason=fixture
tw_trace emit kind=ticket.write subject='ticket:#9' tier=planner data.tier_proposed=implementer data.confidence=low
for f in "$tw"/events/*.jsonl; do mv "$f" "$tw/events/2025-12-31.jsonl"; done
# A ticket written before the proposed keys existed is no override (H-2): the
# span's guards read a missing key as nothing to compare.
tw_trace emit kind=ticket.write subject='ticket:#5' tier=implementer data.label=ready-for-agent data.confidence=high data.label_confidence=high
tw_trace emit kind=feedback subject='ticket:#1' related='pr:#11' outcome=hit data.by=train reason=fixture
tw_trace emit kind=feedback subject='ticket:#2' related='pr:#12' outcome=unasked data.by=train reason=fixture
tw_trace emit kind=ticket.write subject='ticket:#3' tier=implementer data.tier_proposed=implementer data.label=ready-for-agent data.label_proposed=ready-for-agent data.confidence=high data.label_confidence=high
tw_trace emit kind=finding.raise subject='pr:#11' outcome=raised data.id=L-1 data.severity=low data.agent=simplicity data.where=a.sh:1 data.posted=yes reason=fixture
if [ -n "$v7" ]; then
	[ "$(vcount "$tw" "$v7")" = 0 ] && pass "…question 7's span prints 0 over a window of train and unasked verdicts — the retired case" ||
		fail "question 7's span printed '$(vcount "$tw" "$v7")' over a window with no operator verdict, not 0: $v7"
fi
if [ -n "$v8" ]; then
	[ "$(vcount "$tw" "$v8")" = 0 ] && pass "…question 8's span prints 0 over a window with no dismissal and no override — the retired case" ||
		fail "question 8's span printed '$(vcount "$tw" "$v8")' over a window with no dismissal and no override, not 0: $v8"
fi
ho="$SCRATCH/operator.retro"
ho_trace() { ( cd "$ROOT" && TRACE_DIR="$ho" TRACE_QUIET=1 sh "$TRACE" "$@" ); }
ho_trace emit kind=feedback subject='ticket:#1' related='pr:#11' outcome=hit data.by=train reason=fixture
ho_trace emit kind=feedback subject='ticket:#2' related='pr:#12' outcome=adjusted data.by=operator reason=fixture
# A ticket overridden on its draft and confirmed on its re-write: only the
# latest write per subject counts, so it is no override.
ho_trace emit kind=ticket.write subject='ticket:#3' tier=planner data.tier_proposed=implementer data.label=ready-for-agent data.label_proposed=ready-for-agent data.confidence=low data.label_confidence=low
ho_trace emit kind=ticket.write subject='ticket:#3' tier=planner data.tier_proposed=planner data.label=ready-for-agent data.label_proposed=ready-for-agent data.confidence=low data.label_confidence=low
# One label override at the quiz, and one human dismissal.
ho_trace emit kind=ticket.write subject='ticket:#4' tier=implementer data.tier_proposed=implementer data.label=none data.label_proposed=ready-for-agent data.confidence=high data.label_confidence=high
ho_trace emit kind=finding.raise subject='pr:#11' outcome=raised data.id=L-1 data.severity=low data.agent=simplicity data.where=a.sh:1 data.posted=yes reason=fixture
ho_trace emit kind=finding.dismiss subject='pr:#11' outcome=dismissed data.via=thread data.where=a.sh:1 data.thread=T1 reason=fixture
if [ -n "$v7" ]; then
	[ "$(vcount "$ho" "$v7")" = 1 ] && pass "…question 7's span counts the one operator verdict and not the train's — the calibration resumes" ||
		fail "question 7's span printed '$(vcount "$ho" "$v7")' over a window with one operator verdict, not 1: $v7"
fi
if [ -n "$v8" ]; then
	[ "$(vcount "$ho" "$v8")" = 2 ] && pass "…question 8's span counts the dismissal and the latest write's override, not the draft's — the calibration resumes" ||
		fail "question 8's span printed '$(vcount "$ho" "$v8")' over a window with one dismissal and one override, not 2: $v8"
fi

# 15b. The prose of each section: the retired line, its two conditions, that
# it is no finding, that it resumes by itself, and that a project with no such
# record raises the finding as before.
q_has() { case "$prose" in *"$1"*) pass "$2" ;; *) fail "$2 — question $n does not say: $1" ;; esac; }
for n in 7 8; do
	prose=$(sec_of "$n" | flat)
	q_has '`retired: no operator verdict in the window, and the project accepts train-only verdicts (<the record>)`' "question $n carries the retired line, in the project's terms"
	q_has 'binding decision record' "…held to a binding decision record"
	q_has 'is no finding' "…says the retired line is no finding"
	q_has 'records no note' "…and records no note for it"
	q_has 'resumes by itself' "…resumes by itself the first window holding an operator verdict"
	q_has 'A project with no such record has the absence raised as before' "…and a project with no such record has the absence raised as before"
done
# H-3 (review of PR #601): the retired line swallows no missing emit.
n=7 prose=$(sec_of 7 | flat)
q_has 'is still counted on the row' "question 7 still counts a landing with no feedback event on its row"
q_has 'question 6'"'"'s to raise' "…as a missing emit, question 6's to raise"
case "$sec7_route" in
*'retired'*) pass "question 7's route says a retired answer goes nowhere" ;;
*) fail "question 7's Route line does not say where a retired answer goes" ;;
esac

# 15c. SKILL.md's order says it too, and the record is found by a span that
# runs: in this repo it lists the kit's own record, accepted, citing #570.
q8_line=$(awk '/^8\. \*\*Stamp calibration\*\*/ { on = 1; print; next } /^[0-9]+\. |^## / { on = 0 } on' "$SKILL_ABS" | flat)
for line in "$q7_line" "$q8_line"; do
	case "$line" in
	*'train-only verdicts'*'retired'* | *'retired'*'train-only verdicts'*) pass "SKILL.md's question names the retired answer under train-only verdicts: ${line%%—*}" ;;
	*) fail "SKILL.md's question does not say it retires while the project accepts train-only verdicts: ${line%%—*}" ;;
	esac
done
# The record span (M-1, review of PR #601) lists a record only when it says
# the project accepts train-only verdicts AND its status is Accepted — never
# the index, a proposed record or a superseded one. Run over a fixture
# decision directory first, then over this repo.
rspan=$(sec_of 7 | grep -o '`for f in docs/adr/[^`]*`' | tr -d '`' | head -1)
if [ -n "$rspan" ]; then
	ra="$SCRATCH/records"
	mkdir -p "$ra/docs/adr"
	printf '# ADR-0001: The project accepts train-only verdicts\n\n- **Status**: Accepted\n' >"$ra/docs/adr/0001-yes.md"
	printf '# ADR-0002: The project accepts train-only verdicts\n\n- **Status**: Proposed\n' >"$ra/docs/adr/0002-proposed.md"
	printf '# ADR-0003: The project accepts train-only verdicts\n\n- **Status**: Superseded by 0004\n' >"$ra/docs/adr/0003-superseded.md"
	printf '# ADR-0004: Something else\n\n- **Status**: Accepted\n' >"$ra/docs/adr/0004-other.md"
	printf '| [0001](0001-yes.md) | The project accepts train-only verdicts | Accepted |\n' >"$ra/docs/adr/INDEX.md"
	fx_rec=$( cd "$ra" && sh -c "$rspan" 2>/dev/null )
	[ "$fx_rec" = docs/adr/0001-yes.md ] && pass "the record span lists only the accepted record that accepts train-only verdicts — not the index, a proposed or a superseded one" ||
		fail "over a fixture decision directory the record span listed '$fx_rec', not docs/adr/0001-yes.md: $rspan"
	rec=$( cd "$ROOT" && sh -c "$rspan" 2>/dev/null )
	[ "$(printf '%s\n' "$rec" | grep -c .)" = 1 ] && pass "the record span lists exactly one record in this repo: $rec" ||
		fail "the record span lists '$rec' in this repo, not one record: $rspan"
	[ -n "$rec" ] && grep -qF '#570' "$ROOT/$rec" && pass "…citing the operator's ruling, #570" || fail "the kit's train-only record does not cite #570"
	[ -n "$rec" ] && grep -qF "($(basename "$rec"))" "$ROOT/docs/adr/INDEX.md" && pass "…and indexed" || fail "docs/adr/INDEX.md has no row for $rec"
else
	fail "question 7 carries no \`for f in docs/adr/…\` span that finds an accepted record"
fi

t_done "/retro contract"
