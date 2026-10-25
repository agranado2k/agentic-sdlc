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
#   6. Cross-skill agreement (#64): /pr-iterate reports the review with the
#      same badge+label vocabulary, the ⚠️/🔀 tokens it lifts verbatim are
#      byte-identical across the two documents, and its human-only block
#      stays badge-free.
#   7. The decision lines are the policy file's (ticket #280): every severity
#      band the report prints and every status Agent 7 tags a line with is a
#      token scripts/vocab.config.sh declares — READ from that file through
#      the checker's own `fields` subcommand, never a hand-kept copy — so a
#      band or a status the skill prints and the file does not declare goes
#      red. Proved by bait: planted in a copy of the skill, withdrawn from a
#      copy of the policy file.
#   8. The dispatched worker's contract (#266): .agents/prompts/review-worker.md
#      opens by telling the worker it is offline, forbids a fetch and a forge
#      call, and makes `REVIEWED: <full sha>` the report's first line — the
#      sha pinned before the diff is read against it.
#   9. The reuse/DRY lens's two cases (#419): a duplication the diff ADDS is a
#      finding; one it merely touches or extends is a LOW candidate ticket
#      citing shared invariant §10, with a fix line that asks this PR for
#      nothing — in one sentence of Agent 5's prompt, the exception kept, the
#      report's shape and the roster unchanged. Proved by two baits.
#  10. The dispatched worker carries that ruling (#471): the added case, the
#      inherited case and the ruling are sentences of the worker's contract
#      word for word as Agent 5's prompt says them, read from the skill; the
#      exception keeps its direction; the anatomy declares the `↳ cites:`
#      line and defines the what/where line the ruling names — each proved by
#      a mutant that cuts exactly the text it holds. Its twin, the CI review
#      prompt, carries the same ruling in the same words, and both define the
#      buckets the added case is graded by in the skill's own sentence.
#      Both also carry the lens's declined list (#647), lead-in and every
#      bullet word for word from the lens (the twin, a consumer template, all
#      but the one citing a numbered ADR); a bullet dropped from either is red.
#  11. Every planned lens is accounted for (#482, retro F6): a lens the host
#      refused to start records its spawn with `outcome=refused` and no
#      `spawn.end` — nothing started, so nothing ends; a lens that started
#      ends in exactly one `spawn.end`, `unreachable` when its vendor refused
#      it (a usage limit, #566) and `fail` with its cause when it returned no
#      report — all recorded before the verdict; and
#      the summary carries a `Lenses not run:` line naming both kinds and
#      whether this session audited the lens in its own context instead, so a
#      review that ran six lenses never reads as one that ran seven. Every
#      rule proved by its own bait.
#  14. Each standards lens reads only its own instructions (#589): Agents 1–6
#      live in lens-<roster-token>.md beside SKILL.md, each under its own
#      heading; the coordinator names every file, holds no lens body, keeps
#      Agent 7, and hands a lens agent its own file, never the skill.
#  15. A posted review is never raise-less or verdict-less (#629): on path
#      (a) a lens's raises are recorded beside its spawn.end the moment it
#      returns, and a review run replayed up to the first post holds its
#      spawn.end and review.verdict for axis 1 and axis 2.
#  16. A LOW is counted, never posted by an agent (#635): the rule sits beside
#      the bands with its evidence, path (a) and the relay raise a LOW
#      data.posted=no and post none, and /pr-iterate applies a mechanical LOW
#      or declines it citing the band — never escalates one.
#  18. The lenses resolve against the AUTHOR's model (#730): §3's one resolve
#      names the session model as the author's — read from the spawn prompt's
#      `Author-Model:` line, never the orchestrator's own — and /implement's
#      step 9(b) writes that line. Run as written against a throwaway policy,
#      with an orchestrator on the reviewer's own model: a diff authored on
#      another model resolves the reviewer with no warning, one authored on the
#      reviewer's model warns. The pre-#730 span is the bait: it warns falsely.
#  20. A review in which no lens ran is a block (process/R15–R17): a diff
#      whose every lens slice is empty takes the single-reviewer pass over
#      the whole diff, with no verdict before it returns; a review in which no
#      lens and no pass returned records review.verdict outcome=blocked
#      data.lenses=0, reason 'no lens ran', and says so on its Verdict line;
#      /pr-iterate never converges on it and escalates it at the top. Each
#      rule proved by a bait, and the all-empty case shown on a real slicer
#      run over a new top-level directory.
#  21. A blocked review's report has one order (#820): each NO-LENS.md
#      carries one report skeleton, in its skill's own output format. The
#      review's: the summary heading, then the BLOCKED Verdict line, the
#      confirm-list's ⚠️ items below the rule. /pr-iterate's: the ⚠️ block
#      first, as its Output format and hard rule 4 put it, then the
#      escalation line, then the /review-pr: status line carrying the same
#      Verdict text — which both skeletons and the broker spell alike.
#  23. Two rejected findings never raised again (#846): §4, which every
#      standards lens reads, says a version bump is owed only by a path on
#      VERSION's files: list and a skill, listed by name, owes none
#      (ADR-0025); and §3 names a refused or failed lens under `Lenses not
#      run:` without the coordinator auditing its slice (ADR-0035 clause 2),
#      its summary marks a lens "run in this context instead" only for a
#      context with no subagent tool, and the dispatched worker's contract
#      carries the same bump rule.
#  24. Every ⚠️ UNSPECIFIED item carries a scope (#873, process/R53–R55):
#      Agent 7 writes `scope: inside` or `scope: outward`, the vocabulary's
#      two words, as the first words of the item's arrow line, defined in the
#      skill's two sentences; a missing or unknown scope reads as outward; the
#      Axis-2 verdict records data.outward beside data.unspecified. The
#      dispatched worker writes the scope right after the tag, in the same
#      words. Each rule proved by a bait.
#  25. The review lists a check table's gaps and the loop keeps the table
#      (#871, process/R48 process/R49 process/R50 process/R51): /review-pr's coordinator runs the check-table
#      reader on the two fetched bodies and hands Agent 7 its output as a
#      file; Agent 7 — and the dispatched worker, in the same words — lists
#      each id it names as ❌ MISSING with the reader's word, every covered id
#      on its exit 2 or 3. /pr-iterate rewrites the rows at the new head after
#      a push, never converges while a blocking word is printed, and lists
#      the skipped ids at the top of its report. UC3 walked on the real reader
#      and the skill's own rewrite. Each rule proved by a bait.
#
# Usage: sh tests/review-pr-output.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

SKILL=".claude/skills/review-pr/SKILL.md"
SKILL_ABS="$ROOT/$SKILL"

cd "$ROOT" || exit 2


# region <start-re> <end-re> — the lines from the first match of start to the
# first match of end (exclusive of nothing; sed range). Used to hold the two
# axes' sections to DISJOINT glyph vocabularies.
region() { sed -n "/$1/,/$2/p" "${3:-$SKILL_ABS}"; }

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
rs=$(t_line_of "$SKILL_ABS" "### Review Summary")
v=$(t_line_of "$SKILL_ABS" "**Verdict:**")
c=$(t_line_of "$SKILL_ABS" "Clean audits:")
th=$(t_line_of "$SKILL_ABS" "| | Severity | Count |")
tf=$(t_line_of "$SKILL_ABS" "**Then the findings**")
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

a5=$(t_line_of "$SKILL_ABS" "### 5. Severity-Based")
a5b=$(t_line_of "$SKILL_ABS" "### 5b. Behavior Confirm-List")
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
q=$(t_line_of "$SKILL_ABS" "Which severity categories or specific items should I post")
r=$(t_line_of "$SKILL_ABS" "Restate the verdict")
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

# ---------------------------------------------------------------------------
banner "6. Cross-skill agreement — /pr-iterate speaks the same vocabulary (#64)"
# ---------------------------------------------------------------------------
# Two documents, one vocabulary: /pr-iterate's status block reports the local
# review with the same badges, and the human-only tokens it lifts verbatim
# (hard rule 4) are byte-identical to the ones the review template emits. A
# mismatch here is two skills describing one report differently — the drift
# this suite exists to stop.
ITER=".claude/skills/pr-iterate/SKILL.md"
[ -f "$ROOT/$ITER" ] && pass "$ITER exists" ||
	fail "$ITER is missing — the cross-skill half of the contract has no counterpart"

for pair in "🔴 CRITICAL" "🟠 HIGH" "🟡 MEDIUM" "🔵 LOW"; do
	assert_file_has "$ITER" "$pair"
done
for tok in "⚠️ UNSPECIFIED" "🔀 MIXED COMMIT"; do
	assert_file_has "$ITER" "$tok"
	assert_file_has "$SKILL" "$tok"
done
# The badges never leak into the human-only lane: /pr-iterate's ⚠️-first
# report section stays badge-free, exactly as §5b stays badge-free here.
# The endpoint is verified first: if the `Status:` line is renamed, the sed
# range runs to EOF and the badge scan would fire with the WRONG diagnosis —
# still red, but a misleading signpost (review of PR #67, L-2).
iter_confirm=$(sed -n '/⚠️ For you/,/^Status:/p' "$ROOT/$ITER")
iter_confirm_end=$(printf '%s\n' "$iter_confirm" | tail -1)
case "$iter_confirm" in
"") fail "/pr-iterate's output format lost its '⚠️ For you' block — hard rule 4's surface moved" ;;
*)
	if [ "$iter_confirm_end" != "Status:" ]; then
		fail "/pr-iterate's human-only block no longer ends at 'Status:' — the extraction's endpoint moved; fix the range before trusting the badge scan"
	else
		case "$iter_confirm" in
		*🔴* | *🟠* | *🟡* | *🔵*) fail "/pr-iterate's human-only block carries a severity badge — the axes' vocabularies must stay disjoint everywhere" ;;
		*) pass "/pr-iterate's human-only block stays badge-free, and its extraction endpoint holds" ;;
		esac
	fi
	;;
esac

# ---------------------------------------------------------------------------
banner "7. The decision lines are the policy file's — read through the checker"
# ---------------------------------------------------------------------------
# The report's severity is a band on three kinds of line — a count-table row,
# a section heading, and the badge+label pair wherever else it is spelled.
# Agent 7's status is the TAG on a confirm-list line: in the §5b template and
# in the agent's own classification prose. 🧬 MUTATION is on the list and is
# deliberately no token: the skill says it measures the list, and the policy
# file says the same, so it is set aside by name and by nothing looser.
POLICY="$ROOT/scripts/vocab.config.sh"
BADGES='🔴|🟠|🟡|🔵|🟣|🟤|🟢|⚫|⚪'
GLYPHS='✅|⚠️|❌|🔀|🧬'


# printed_severities <skill> — every band the skill prints, folded to a token.
printed_severities() {
	{
		sed -n 's/^| [^|]* | \([A-Z][A-Z -]*[A-Z]\) | X |$/\1/p' "$1"
		grep -o -E "($BADGES) \**[A-Z][A-Z-]+" "$1" | sed -e 's/^[^ ]* //' -e 's/^\**//'
	} | tr 'A-Z ' 'a-z-' | sort -u
}

# printed_statuses <skill> — every tag on a confirm-list line, folded.
printed_statuses() {
	{
		sed -n "/^### 5b\\. /,/^### 6\\. /p" "$1" | sed -n 's/^[^ A-Za-z<`#|>-][^ ]* \([A-Z][A-Z ]*[A-Z]\)  *[<a-z].*/\1/p'
		grep -o -E "($GLYPHS) \*\*[A-Z][A-Z ]*[A-Z]" "$1" | sed 's/^[^ ]* \*\*//'
	} | grep -v -x 'MUTATION' | tr 'A-Z ' 'a-z-' | sort -u
}

# undeclared <field> <printed tokens> <policy file> — the printed tokens the
# policy file does not declare, space-joined.
undeclared() {
	_ud=$(t_field_tokens "$1" "$3")
	for _ud_tok in $2; do
		case " $_ud " in *" $_ud_tok "*) ;; *) printf '%s ' "$_ud_tok" ;; esac
	done | sed 's/ $//'
}

# held <label> <field> <printed tokens> <policy file> — green when every
# printed token is declared and at least one was printed.
held() {
	_h_bad=$(undeclared "$2" "$3" "$4")
	if [ -n "$3" ] && [ -z "$_h_bad" ]; then pass "$1"; else
		fail "$1 — ${_h_bad:-nothing was extracted} is printed by the skill and not declared as a $2 in the policy file"
	fi
}
# baited <label> <field> <printed tokens> <policy file> <the token that must
# be caught> — green when exactly that token is reported undeclared.
baited() {
	_b_bad=$(undeclared "$2" "$3" "$4")
	if [ "$_b_bad" = "$5" ]; then pass "$1"; else
		fail "$1 — expected '$5' reported undeclared, got '${_b_bad:-nothing}'"
	fi
}

sev=$(printed_severities "$SKILL_ABS" | tr '\n' ' ' | sed 's/ $//')
sta=$(printed_statuses "$SKILL_ABS" | tr '\n' ' ' | sed 's/ $//')
[ -n "$(t_field_tokens severity "$POLICY")" ] && [ -n "$(t_field_tokens status "$POLICY")" ] &&
	pass "the policy file declares severity and status, read through 'fields'" ||
	fail "'sh scripts/vocab.sh fields' printed no severity or no status vocabulary"
# …and the reader knows the (open) mark (review of PR #328): `fields` marks an
# open vocabulary `<field> (open):`, and a reader that does not know the mark
# reads nothing for an opened field. The reader is t_field_tokens in
# tests/lib.sh, the one copy every suite uses; this case holds it on THIS
# suite's field and the policy-file argument, so it guards the shared reader,
# not a local copy — keep it.
sed "s/^VOCAB_OPEN='\(.*\)'/VOCAB_OPEN='\1 severity'/" "$POLICY" >"$SCRATCH/opened.config.sh"
[ -n "$(t_field_tokens severity "$POLICY")" ] && [ "$(t_field_tokens severity "$SCRATCH/opened.config.sh")" = "$(t_field_tokens severity "$POLICY")" ] &&
	pass "a vocabulary a consumer opens is still read: the reader knows the (open) mark" ||
	fail "with severity opened in the policy file the reader read '$(t_field_tokens severity "$SCRATCH/opened.config.sh")', not '$(t_field_tokens severity "$POLICY")'"
held "every severity band the report prints is a token the policy file declares: $sev" severity "$sev" "$POLICY"
held "every status Agent 7 tags a line with is a token the policy file declares: $sta" status "$sta" "$POLICY"
# …and nothing declared goes unprinted: the two lists are one vocabulary.
[ "$(printf '%s\n' $sev | sort | tr '\n' ' ')" = "$(printf '%s\n' $(t_field_tokens severity "$POLICY") | sort | tr '\n' ' ')" ] &&
	pass "…and every declared severity is a band the report prints" ||
	fail "the report prints '$sev', the policy file declares '$(t_field_tokens severity "$POLICY")'"
[ "$(printf '%s\n' $sta | sort | tr '\n' ' ')" = "$(printf '%s\n' $(t_field_tokens status "$POLICY") | sort | tr '\n' ' ')" ] &&
	pass "…and every declared status is a tag Agent 7 prints" ||
	fail "Agent 7 tags '$sta', the policy file declares '$(t_field_tokens status "$POLICY")'"

# The one copy-and-edit helper the per-rule bait wrappers below call (#860).
# bait_copy <source> <copy> <sed script> — edit a copy, green only when the
# edit changed it, so a bait whose anchor moved cannot pass by planting nothing.
# bait_gap <checker> <rule name> <sed script> — the same on the skill, then
# green when the checker run on the copy names the rule. The baits that stage
# companions or edit one of several files (#635, #796, #820, bt_bait) keep
# that staging and call bait_copy for the edit. lens_bait, which edits a copy
# of the lens directory, and the inline single baits keep their own edit: the
# PR #864 ruling left them outside this refactor.
bait_copy() {
	sed "$3" "$1" >"$2" && ! cmp -s "$2" "$1"
}
bait_gap() {
	bait_copy "$SKILL_ABS" "$SCRATCH/bait-gap.md" "$3" && "$1" "$SCRATCH/bait-gap.md" | grep -qxF -- "$2"
}
# Every bait's "planted nothing" guard lives in bait_copy alone, so hold it here:
# an edit that changes nothing must fail, or every bait could go green unplanted.
# Silent when it holds — #860 keeps the passing count — and a FAIL when it breaks.
! bait_copy "$SKILL_ABS" "$SCRATCH/bait-noop.md" 's/^\(.*\)$/\1/' ||
	fail "bait_copy passed an edit that changed nothing"

# The bait. Each plants ONE line in a copy of the skill — where a session
# would print it from — and the same holder must name exactly that token.
bait_skill() { awk -v at="$1" -v add="$2" '{ print } index($0, at) == 1 { print add }' "$SKILL_ABS" >"$SCRATCH/bait.md"; }
bait_skill '| 🔵 | LOW | X |' '| 🟣 | BLOCKER | X |'
baited "bait: a band added to the count table goes red" severity "$(printed_severities "$SCRATCH/bait.md")" "$POLICY" blocker
bait_skill '#### 🟠 HIGH' '#### 🟤 MEDIUM-HIGH'
baited "bait: a band added as a section heading goes red" severity "$(printed_severities "$SCRATCH/bait.md")" "$POLICY" medium-high
bait_skill '❌ MISSING ' '🟢 DEFERRED     <spec line the diff postpones>'
baited "bait: a status added to the confirm-list template goes red" status "$(printed_statuses "$SCRATCH/bait.md")" "$POLICY" deferred
bait_skill '- ⚠️ **UNSPECIFIED' '- ✅ **MOSTLY SPECIFIED** — the spec nearly asked for it.'
baited "bait: a status added to Agent 7's classification goes red" status "$(printed_statuses "$SCRATCH/bait.md")" "$POLICY" mostly-specified
cmp -s "$SCRATCH/bait.md" "$SKILL_ABS" && fail "the last bait planted nothing — its anchor line moved" || pass "the baits planted their lines"
# The other half: the skill unchanged, the token withdrawn from the FILE — so
# the list being read is the policy file's and not one this suite carries.
sed "s/^VOCAB_SEVERITY=.*/VOCAB_SEVERITY='critical high medium'/" "$POLICY" >"$SCRATCH/no-low.config.sh"
baited "bait: a band withdrawn from the policy file goes red" severity "$sev" "$SCRATCH/no-low.config.sh" low
sed "s/^VOCAB_STATUS=.*/VOCAB_STATUS='mixed-commit unspecified specified'/" "$POLICY" >"$SCRATCH/no-missing.config.sh"
baited "bait: a status withdrawn from the policy file goes red" status "$sta" "$SCRATCH/no-missing.config.sh" missing
# The mutation line is set aside by name, and the skill still says why.
assert_file_has "$SKILL" "It is **not** a classification" "the mutation line is a measurement, so it is no status"

# ---------------------------------------------------------------------------
banner "8. The dispatched worker's contract: offline, and says what it reviewed (#266)"
# ---------------------------------------------------------------------------
# .agents/prompts/review-worker.md is the review the kit dispatches to another
# agent harness — the same two axes, returned on stdout instead of posted.
# That worker runs in its harness's default sandbox, read-only and with no
# network, and must stay that way (PRD #261): with network it would hold a
# writable tree, the operator's forge token and an untrusted diff at once. So
# the contract has to say two things the skill above never needed to: that
# the worker is OFFLINE, up front, so it spends its budget on the diff rather
# than on discovering the sandbox; and WHICH COMMIT it reviewed, so the session
# that posts the findings can tell a head that moved from a commit it missed.
# Same honest boundary as the rest of this suite — the contract is a document,
# so its external behaviour is its text.
WORKER=".agents/prompts/review-worker.md"
WORKER_ABS="$ROOT/$WORKER"
[ -f "$WORKER_ABS" ] && pass "$WORKER exists" || {
	fail "$WORKER is missing — the dispatched review has no contract"
	t_done "/review-pr output contract"
}
wline() { grep -nF -- "$1" "$WORKER_ABS" | head -1 | cut -d: -f1; }

# The body the worker actually reads: the editor header stripped exactly the
# way scripts/agent-dispatch.sh strips it (a `<!--` first line through the
# first line that IS `-->`). "Opens by" means the first line of THAT, not the
# first line of the file.
body_of() {
	awk 'NR == 1 && $0 == "<!--" { inhdr = 1; next }
	     inhdr { if ($0 == "-->") inhdr = 0; next }
	     { print }' "$1"
}
body=$(body_of "$WORKER_ABS")
first=$(printf '%s\n' "$body" | grep -m1 .)
case "$first" in
*"no network"*) pass "the contract's first line to the worker says it has no network" ;;
*) fail "the contract does not OPEN by saying the worker is offline; its first line is: '$first'" ;;
esac
assert_file_has "$WORKER" "no credentials" "a worker that believes it holds a token will try to use it"
# The PROHIBITION, in words a model acts on: not a fetch, not a forge call.
# Read unwrapped — the contract is 80-column prose and a sentence may break
# between the verb and its object; the worker reads sentences, not lines.
unwrapped=$(printf '%s\n' "$body" | tr '\n' ' ')
printf '%s\n' "$unwrapped" | grep -qiE 'do not (attempt|try|run)[^.]*fetch' &&
	pass "$WORKER tells the worker not to attempt a fetch" ||
	fail "$WORKER never forbids a fetch — the worker will try one and burn its budget on the sandbox"
printf '%s\n' "$unwrapped" | grep -qiE 'do not (attempt|try|run)[^.]*forge' &&
	pass "$WORKER tells the worker not to attempt a forge call" ||
	fail "$WORKER never forbids a forge call"
assert_file_has "$WORKER" "stdout" "stdout is the only channel out, and the contract must say so"

# The machine contract: REVIEWED first, VERDICT second, and the sha comes from
# the local branch — no fetch needed to produce it.
assert_file_has "$WORKER" "REVIEWED: <full sha>"
r=$(wline "REVIEWED: <full sha>")
v=$(wline "VERDICT:")
if [ -n "$r" ] && [ -n "$v" ] && [ "$r" -lt "$v" ]; then
	pass "REVIEWED (line $r) is specified ahead of VERDICT (line $v) — the first line of the report names the commit"
else
	fail "REVIEWED must precede VERDICT in the contract — REVIEWED='$r' VERDICT='$v'"
fi
assert_file_has "$WORKER" "git rev-parse" "the sha is produced offline, from the branch the worker diffed"

# The sha is PINNED FIRST, and the diff is read against it. A worker that
# diffs a mutable branch ref and resolves that ref separately can report a
# commit it never reviewed: the coordinating session holds the same checkout
# and can commit while the worker reads. The ORDER is the guarantee the
# REVIEWED header makes, so the order is what this asserts.
rp=$(wline 'git rev-parse %%BRANCH%%')
gd=$(wline 'git diff %%BASE%%')
if [ -n "$rp" ] && [ -n "$gd" ] && [ "$rp" -lt "$gd" ]; then
	pass "the contract pins the sha (line $rp) before it reads the diff (line $gd)"
else
	fail "the contract must resolve and retain the sha of %%BRANCH%% BEFORE the diff — rev-parse='$rp' diff='$gd'"
fi
if printf '%s\n' "$unwrapped" | grep -qF 'git diff %%BASE%%...%%BRANCH%%'; then
	fail "the diff endpoint is still the mutable branch ref — diff against the pinned sha instead"
else
	pass "the diff endpoint is the pinned sha, not the mutable branch ref"
fi

# The header stays honest about why the file exists: it is what a session
# stages in place of telling the worker to run /review-pr, and the reason is
# the sandbox. A header that still described only the CI/branch split would
# send the next editor to the wrong mental model.
header=$(sed -n '1,/^-->$/p' "$WORKER_ABS")
case "$header" in
*"/review-pr"*) pass "the editor header names /review-pr as the skill this contract stands in for" ;;
*) fail "the editor header never mentions /review-pr — it no longer says why this file is dispatched" ;;
esac
case "$header" in
*offline* | *"no network"*) pass "…and says the worker is offline, which is the reason" ;;
*) fail "…and does not say the worker is offline, which is the whole reason for the swap" ;;
esac

# Shared invariant §7 stays in the worker's own words (tests/agent-dispatch
# holds the same line; repeated here because this suite owns the contract).
assert_file_has "$WORKER" "do not push"


# Each finding names the lens that raised it (#412): one `↳ lens:` line in
# the finding anatomy, its token lifted from /review-pr §3's Axis-1 roster and
# spelled exactly as the skill spells it, so the broker's raise reads one row
# per lens instead of `unattributed`. The tokens are read from the skill, not
# typed here: a rename on either side is red.
assert_file_has "$WORKER" "↳ lens:" "a finding with no lens line is an unattributed raise"
n_tok=0
for tok in $(sed -n 's/^- `\([a-z-]*\)` — Agent [1-6],.*/\1/p' "$ROOT/$SKILL"); do
	n_tok=$((n_tok + 1))
	assert_file_has "$WORKER" "\`$tok\`" "the contract spells the roster token the skill does"
done
[ "$n_tok" = 6 ] && pass "six Axis-1 roster tokens were read from the skill" ||
	fail "expected six Axis-1 roster tokens in $SKILL, read $n_tok"

# ---------------------------------------------------------------------------
banner "9. The reuse/DRY lens tells added duplication from inherited duplication (#419)"
# ---------------------------------------------------------------------------
# Retro H2 (2026-10-01): Agent 5's findings were accepted once and rejected
# four times with a citation over three PRs — each time it asked a feature PR
# to move copies that pre-date the branch into a shared file. That move is a
# behaviour-preserving refactor, and shared invariant §10 lands one on its own
# ticket, never as a passenger on a feature diff. So the prompt names two
# cases, and the suite holds it to both: a duplication the diff ADDS is a
# finding at its severity; a duplication the diff merely touches or extends is
# a CANDIDATE TICKET — named as such, LOW, §10 cited, and a fix line that
# asks this PR for nothing. It is a fix LINE and not an absent one because the
# broker refuses a whole report over one finding without it
# (scripts/forge-broker.kit.sh; tests/forge-broker.test.sh section 21 runs the
# line this suite pins through it).
# Scoped to Agent 5's own section: the other lenses' prompts stay as they
# were, and a rule written into §5's shared anatomy would bind all six.
# Agent 5's prompt is its own lens file since #589: its section runs from its
# heading to the file's end, and every reader below reads that file.
LENS5="$ROOT/.agents/skills/review-pr/lens-reuse-dry.md"
a5=$(t_line_of "$LENS5" "#### Agent 5 ")
a6=$(($(wc -l <"$LENS5") + 1))
if [ -n "$a5" ]; then
	pass "Agent 5's section is extractable (lines $a5-$a6)"
else
	fail "Agent 5's section is not extractable — a5='$a5' a6='$a6'"
fi
# agent5_of <a copy of the skill> — the body between the two headings; the
# headings themselves are §3's, not Agent 5's. sentences_of <a copy> — that
# body unwrapped and split one sentence per line: the prompt is 80-column
# prose and a sentence may break between the case and its ruling, and the
# reviewer reads sentences, not lines. The one pair of readers for the skill
# and for the baits below, so a bait runs the assertion and never a retyped
# copy of it. sentences — the splitter itself, on stdin: lines joined, spaces
# squeezed, one sentence per line with its edges trimmed, so a skill paragraph
# and a contract wrapped at 80 columns split alike (section 10 compares them).
agent5_of() { sed -n "$((${a5:-0} + 1)),$((${a6:-1} - 1))p" "$1"; }
sentences() { tr '\n' ' ' | tr -s ' ' | tr '.' '\n' | sed 's/^ //; s/ $//'; }
sentences_of() { agent5_of "$1" | sentences; }
agent5=$(agent5_of "$LENS5")
agent5_flat=$(printf '%s\n' "$agent5" | tr '\n' ' ')
a5_has() {
	if printf '%s\n' "$agent5_flat" | grep -qF -- "$1"; then
		pass "Agent 5's prompt says '$1'${2:+ ($2)}"
	else
		fail "Agent 5's prompt never says '$1'${2:+ — $2}"
	fi
}
# The two cases, each by name.
a5_has "the diff ADDS" "the first case: a new copy is the author's, and a finding"
a5_has "pre-date the branch" "the second case: copies the diff inherited are not the author's to consolidate"
# ruling_of <a copy of the skill> — the ONE sentence of Agent 5's section that
# names the candidate ticket, puts it at LOW and cites §10; empty when no
# sentence carries all three.
ruling_of() { sentences_of "$1" | grep -F "candidate ticket" | grep -F "LOW" | grep -F "§10"; }
# The fix line a candidate ticket carries, as the prompt spells it: the PR is
# asked for nothing, and the line says so in words the broker accepts.
# spells_fix <a ruling sentence> — exit 0 when the sentence spells that line.
CT_FIX='none on this PR — candidate ticket (shared invariant §10)'
spells_fix() { printf '%s\n' "$1" | grep -qF -- "\`↳ fix:\` line reads \`$CT_FIX\`"; }
# The ruling on the second case: named, LOW, §10 cited, the fix line spelled —
# all in ONE sentence, so the four cannot be met by a word each, scattered
# across the section. (A later sentence that re-asks for the move is a
# reviewer's catch, not this check's: it holds the ruling, not the whole prose.)
ruling=$(ruling_of "$LENS5")
[ -n "$ruling" ] &&
	pass "one sentence rules the inherited case: a candidate ticket, LOW, citing invariant §10" ||
	fail "no single sentence of Agent 5's prompt names the inherited duplication a candidate ticket AND puts it at LOW AND cites invariant §10"
spells_fix "$ruling" &&
	pass "…and that sentence spells the fix line — \`$CT_FIX\` — which asks this PR for nothing" ||
	fail "…and that sentence does not spell the candidate ticket's fix line \`↳ fix: $CT_FIX\` — the reviewer will still ask for the move, or omit the line and the broker will refuse the report"
# The citation reaches the report: a candidate ticket cites §10 on its
# `↳ cites:` line, where /pr-iterate reads the reason for a LOW it may skip.
a5_has "↳ cites:" "the citation is on the finding's own line, not only in the prompt's reasoning"
# The one exception stays, and is held in one sentence with its verdict: a
# divergent-behavior copy is a latent bug whichever branch introduced it, so
# the candidate-ticket ruling never defers it.
exception=$(sentences_of "$LENS5" | grep -F "divergent-behavior" | grep -F "stays a finding")
[ -n "$exception" ] &&
	pass "the exception is pinned: a divergent-behavior copy stays a finding whichever branch introduced it" ||
	fail "no sentence of Agent 5's prompt keeps the divergent-behavior copy a finding — the candidate-ticket ruling would defer a latent bug"
# The report's shape is unchanged — the candidate ticket is a LOW with the §5
# anatomy, not a new section at any heading depth. (The count table is held
# by sections 1 and 7 already.)
printf '%s\n' "$agent5" | grep -qE '^#{1,6} ' &&
	fail "Agent 5's section grew a heading — the report's shape is §5's and does not change here" ||
	pass "Agent 5's section adds no heading: the report's shape is unchanged"
# The roster: seven lenses, the unattributed token and — since #568 — the
# single-reviewer token (section 13).
roster=$(region '^\*\*The sub-agent roster\.\*\*' '^#### Agents 1–6 ' | grep -c '^- `')
[ "$roster" = 9 ] &&
	pass "the roster names seven lenses, the unattributed token and the single-reviewer token" ||
	fail "the roster names $roster tokens, not 9 — seven lenses, unattributed and single-reviewer"
# Bait 1: the ruling withdrawn from a copy of the skill — ruling_of must be
# what catches it, so it is known to read the prompt and not a word that
# happens to be elsewhere in the file.
sed "$((a5 + 1)),$((a6 - 1))s/candidate ticket/follow-up/g" "$LENS5" >"$SCRATCH/bait5.md"
b5=$(ruling_of "$SCRATCH/bait5.md")
[ -z "$b5" ] && ! cmp -s "$SCRATCH/bait5.md" "$LENS5" &&
	pass "bait: the ruling renamed away from 'candidate ticket' goes red" ||
	fail "bait: with 'candidate ticket' withdrawn from Agent 5's section the ruling still reads '$b5'"
# Bait 2: the fix line replaced by a request for the move, in the same
# sentence — the ruling still reads, and the fix assertion is what goes red.
# This is the check that carries retro H2: a lens that names the ticket and
# still asks for the consolidation.
sed "$((a5 + 1)),$((a6 - 1))s/none on this PR[^\`]*/extract the copies into one helper and call it from both sites/" "$LENS5" >"$SCRATCH/bait5-fix.md"
b5f=$(ruling_of "$SCRATCH/bait5-fix.md")
if [ -n "$b5f" ] && ! cmp -s "$SCRATCH/bait5-fix.md" "$LENS5" && ! spells_fix "$b5f"; then
	pass "bait: the fix line swapped for a request to move the copies goes red at the fix assertion"
else
	fail "bait: with the fix line swapped for a request to move the copies, the fix assertion still passes (ruling: '$b5f')"
fi

# The declined list (#633). Retro 2026-10-07: Agent 5 was rejected 6 of 9
# times in the wave, each rejection citing a decision record, so the lens
# names each rule a record declines, with that record, and stops raising it.
# The list was drawn from the trace's rejected finding.triage events joined
# to their reuse-dry raises — never invented — so each record below is one a
# rejection cited. declined_of <a copy of the lens> — the bullets under the
# list's lead-in, up to the first blank line after them.
DECLINED_LEAD='**What the decision records decline.**'
declined_of() {
	awk -v lead="$DECLINED_LEAD" 'index($0, lead) { on = 1; next } on && n && /^$/ { exit } on && /^- / { n++; print }' "$1"
}
declined=$(declined_of "$LENS5")
[ -n "$declined" ] &&
	pass "Agent 5's prompt lists the rules the decision records decline" ||
	fail "Agent 5's prompt has no '$DECLINED_LEAD' list — the lens keeps raising what the records declined"
# Every bullet names its record on a 'declined by' clause: a rule with no
# record is an invented one.
# Judged only when the list exists: an absent list is the assertion above's
# one failure, not a second one here.
if [ -n "$declined" ]; then
	unrecorded=$(printf '%s\n' "$declined" | grep -v -F 'declined by ' || :)
	[ -z "$unrecorded" ] &&
		pass "every declined rule names the record that declines it" ||
		fail "a declined rule names no record: $unrecorded"
fi
# The records the rejected triages cited, each named on a bullet.
for rec in 'shared invariant §10' '`constitution/shared-code-craft.md` §1' "the kit's root manual, hard rule 3" "the kit's ADR-0013 clause 2" "the kit's living spec requirement process/R7"; do
	t_text_has "$declined" "declined by $rec" "a rejected reuse-dry raise cited it" "the declined list"
done
# Bait: one bullet's record cut from a copy of the lens goes red.
sed "/^- .*declined by the kit's ADR-0013/s/ — declined by .*//" "$LENS5" >"$SCRATCH/bait5-declined.md"
bd=$(declined_of "$SCRATCH/bait5-declined.md" | grep -v -F 'declined by ' || :)
[ -n "$bd" ] && ! cmp -s "$SCRATCH/bait5-declined.md" "$LENS5" &&
	pass "bait: a declined rule with its record cut goes red" ||
	fail "bait: with ADR-0013's record cut from its bullet, the list still reads as recorded"

# ---------------------------------------------------------------------------
banner "10. The dispatched worker and its CI twin carry the reuse/DRY ruling in the skill's words (#471)"
# ---------------------------------------------------------------------------
# Section 9's ruling reached the in-session lens only: a dispatched worker
# still filed an inherited duplication as a finding against the PR, because
# its contract (section 8's file) never heard of the two cases. So the
# contract carries them — the added case, the inherited case and the ruling,
# as the SAME sentences Agent 5's prompt says, read from the skill here and
# never retyped, so a reword on either side is red. Compared sentence by
# sentence over prose unwrapped and spaces squeezed: the contract is
# 80-column prose and the skill is not, and both models read sentences.
w_sentences=$(printf '%s\n' "$body" | sentences)
a5_sentences=$(sentences_of "$LENS5")
# The CI review prompt is the worker's twin — "same two axes, same standard",
# its header says — so it rules duplication in the same words, or the two
# reviewers of one diff disagree on whose duplication it is. Both are held
# below, each to the skill. And "the buckets" the added case grades by are
# defined in each: the skill's own sentence giving the four their meanings.
TWIN="templates/workflows/ai-review-prompt.md"
buckets=$(sentences <"$SKILL_ABS" | grep -F 'The severity buckets keep their meanings' | head -n 1)
# skill_sentence <needle> — the first sentence of Agent 5's prompt holding the
# needle; empty when none does. carries <sentences> <sentence> — the sentence
# is a whole sentence of the given text.
skill_sentence() { printf '%s\n' "$a5_sentences" | grep -F -- "$1" | head -n 1; }
carries() { [ -n "$2" ] && printf '%s\n' "$1" | grep -qxF -- "$2"; }
[ -n "$buckets" ] ||
	fail "the skill no longer says which meanings the severity buckets keep — nothing to define 'the buckets' by"
t_sentences=$(body_of "$ROOT/$TWIN" | sentences)
# sentences_for <file> — that file's sentences, split once above.
sentences_for() { case $1 in "$TWIN") printf '%s\n' "$t_sentences" ;; *) printf '%s\n' "$w_sentences" ;; esac; }
for f in "$WORKER" "$TWIN"; do
	f_sentences=$(sentences_for "$f")
	for needle in '**Then ask which case' '**the diff ADDS**' '**touches or extends**' '**candidate ticket**'; do
		want=$(skill_sentence "$needle")
		[ -n "$want" ] ||
			fail "Agent 5's prompt no longer holds a sentence with '$needle' — nothing to hold $f to"
		carries "$f_sentences" "$want" &&
			pass "$f says Agent 5's '$needle' sentence word for word" ||
			fail "$f does not say Agent 5's '$needle' sentence word for word — it rules duplication differently from the lens"
	done
	carries "$f_sentences" "$buckets" &&
		pass "$f defines the buckets in the skill's sentence: which meanings the four severities keep" ||
		fail "$f grades the added case by 'the buckets' and never says what they mean — carry the skill's sentence: $buckets"
done
# The exception, held by its direction and not by two words in one sentence:
# the sentence naming the divergent-behavior copy ends in the skill's own
# verdict — read from the skill — and carries no negation, so an exception
# reversed ("no longer stays a finding", "there is no exception") is red.
verdict=$(skill_sentence 'divergent-behavior' | sed -n 's/.*, which \(is a latent bug.*stays a finding\)$/\1/p')
[ -n "$verdict" ] ||
	fail "Agent 5's prompt no longer ends its divergent-behavior sentence in a verdict that keeps the copy a finding — nothing to hold the worker to"
# keeps_exception <sentences> — exit 0 when one sentence naming the
# divergent-behavior copy ends in that verdict and negates nothing before
# naming it (the verdict after it is the skill's own words, held above).
keeps_exception() {
	printf '%s\n' "$1" | grep -F 'divergent-behavior' | while IFS= read -r e; do
		case $e in *"$verdict") ;; *) continue ;; esac
		printf '%s\n' "${e%%divergent-behavior*}" | grep -qiE "(^|[^a-z])(not|never|no|nothing|none)([^a-z]|\$)|n't" || echo kept
	done | grep -q kept
}
for f in "$WORKER" "$TWIN"; do
	[ -n "$verdict" ] && keeps_exception "$(sentences_for "$f")" &&
		pass "$f keeps the exception: a divergent-behavior copy $verdict" ||
		fail "$f never keeps a divergent-behavior copy a finding in the skill's verdict — the ruling would defer a latent bug"
done
for flip in 's/and stays a finding/and no longer stays a finding/' 's/The one exception is a/There is no exception for a/' 's/The one exception is a/Nothing is excepted for a/'; do
	keeps_exception "$(printf '%s\n' "$w_sentences" | sed "$flip")" &&
		fail "bait: the exception reversed ($flip) still reads as kept" ||
		pass "bait: the exception reversed ($flip) goes red"
done
# says_once <file> <text> <why> — the text is said in the file (prose
# unwrapped, spaces squeezed), and said exactly once: cut once, it is gone. A
# text said twice — once by the paragraph that needs it — would survive the
# cut, so the assertion reads the one line it claims to hold (each was also
# run red against the real file with that line deleted, #485).
unwrap() { tr '\n' ' ' <"$1" | tr -s ' '; }
says_once() {
	t_text_has "$(unwrap "$1")" "$2" "$3" "$1"
	unwrap "$1" | awk -v n="$2" '{ i = index($0, n); if (i) $0 = substr($0, 1, i - 1) substr($0, i + length(n)) } 1' >"$SCRATCH/says_once.cut"
	grep -qF -- "$2" "$SCRATCH/says_once.cut" &&
		fail "$1 says '$2' more than once — cut once, it is still said, so another line satisfies the assertion" ||
		pass "…and says it exactly once: cut once from $1, it is gone"
}
# The ruling names a `↳ cites:` line and a what/where line: the worker's
# anatomy declares the one and defines the other, each on its own line.
says_once "$WORKER" "↳ cites: <the decision record, audit item or craft rule — only when there is one>" \
	"the ruling cites §10 on a line the worker's anatomy declares"
says_once "$WORKER" "The first line is the finding's what/where line." \
	"the ruling's what/where line is a term the worker's anatomy defines"
says_once "$TWIN" 'one line readable in isolation — the finding'"'"'s what/where line' \
	"the ruling's what/where line is a term the CI prompt's anatomy defines"
says_once "$TWIN" 'a "↳ cites:" line naming the decision record, audit item or craft rule' \
	"the ruling cites §10 on a line the CI prompt's anatomy declares"
# Bait: the worker's fix line reworded — the exact comparison is what goes red.
bait_w=$(printf '%s\n' "$w_sentences" | sed 's/none on this PR/extract the copies on this PR/')
carries "$bait_w" "$(skill_sentence '**candidate ticket**')" &&
	fail "bait: the worker's fix line reworded still reads as the skill's ruling" ||
	pass "bait: the worker's fix line reworded goes red"
# The declined list rides along (#647). Section 9's list (#633) reached the
# in-session lens only, so a dispatched or CI reviewer kept raising the rules
# the records declined. Both carry its lead-in and every bullet word for word,
# read from the lens here and never retyped — compared over prose unwrapped
# and spaces squeezed, since the two files wrap at 80 columns and the lens
# does not. One bullet is the worker's alone: the CI twin is a template a
# consumer receives, and tests/ai-review-template.test.sh refuses it a
# numbered `ADR-0` citation — true of one repo only — so the bullet citing
# the kit's ADR-0013 is not the twin's to carry, and every other one is.
# TWIN_EXEMPT — the one bullet the twin need not carry, named by its title.
# A title the lens no longer holds is a stale exemption, and goes red.
TWIN_EXEMPT='- **The kit wrapper'"'"'s spawn-word bridge, read as a copy of the resolver'"'"'s agent-harness split**'
t_text_has "$declined" "$TWIN_EXEMPT" "the twin's one exempt bullet, still in the lens — else the exemption names nothing" "the declined list"
# declined_said_in <file> [<bullets>] — the lens's lead-in paragraph and
# bullets (the lens's own unless given) the file does not say, one per line;
# empty when it says them all.
declined_lead=$(grep -F -- "$DECLINED_LEAD" "$LENS5" | head -n 1)
declined_said_in() {
	_ds_text=$(unwrap "$1")
	printf '%s\n%s\n' "$declined_lead" "${2-$declined}" | while IFS= read -r _ds_line; do
		[ -n "$_ds_line" ] || continue
		case $1 in *"$TWIN") case $_ds_line in "$TWIN_EXEMPT"*) continue ;; esac ;; esac
		printf '%s\n' "$_ds_text" | grep -qF -- "$_ds_line" || printf '%s\n' "$_ds_line"
	done
}
[ -n "$declined_lead" ] && [ -n "$declined" ] ||
	fail "the lens's declined list is gone — nothing to hold the worker and its CI twin to"
for f in "$WORKER" "$TWIN"; do
	unsaid=$(declined_said_in "$f")
	[ -n "$declined" ] && [ -z "$unsaid" ] &&
		pass "$f carries the lens's declined list, lead-in and every bullet it may, word for word" ||
		fail "$f does not say, word for word, what the lens's declined list says — its reviewer keeps raising: $unsaid"
	# Bait: one bullet dropped from a copy of the file goes red.
	awk 'index($0, "- **A consolidation whose shared home") { skip = 1; next } skip && /^  / { next } { skip = 0; print }' "$f" >"$SCRATCH/bait647.md"
	! cmp -s "$SCRATCH/bait647.md" "$f" && [ -n "$(declined_said_in "$SCRATCH/bait647.md")" ] &&
		pass "bait: a declined bullet dropped from $f goes red" ||
		fail "bait: with a declined bullet dropped from $f, the list still reads as carried — or the bait planted nothing"
	# Bait: the lead-in reworded in a copy of the file goes red too.
	sed 's/Each raise below was rejected/Each raise below was disputed/' "$f" >"$SCRATCH/bait647-lead.md"
	! cmp -s "$SCRATCH/bait647-lead.md" "$f" && [ -n "$(declined_said_in "$SCRATCH/bait647-lead.md")" ] &&
		pass "bait: the declined list's lead-in reworded in $f goes red" ||
		fail "bait: with the lead-in reworded in $f, the list still reads as carried — or the bait planted nothing"
done
# Bait (#675): a second bullet citing a decision record, absent from the
# twin, goes red — the twin's exemption is one bullet, not every record cited.
bait675='- **A bait rule nobody declined** — declined by the kit'"'"'s ADR-0099, which no twin carries.'
[ "$(declined_said_in "$TWIN" "$declined
$bait675")" = "$bait675" ] &&
	pass "bait: a second ADR-citing bullet missing from $TWIN goes red" ||
	fail "bait: a second ADR-citing bullet missing from $TWIN still reads as carried — the exemption is a pattern, not the one bullet"


# ---------------------------------------------------------------------------
banner "11. Every planned lens is accounted for, and a missing lens is named (#482)"
# ---------------------------------------------------------------------------
# lens_rules_missing <skill file> — the rules of #482 the file does not hold,
# space-joined. The spawn rules are read inside §3 only (its heading to the
# first agent's), the report line inside the summary template only, so a
# phrase that wanders elsewhere does not count. A lens the host refused to
# start records `spawn outcome=refused` and no `spawn.end` — nothing started,
# so nothing ends; a lens that started ends in exactly one `spawn.end`.
lens_rules_missing() {
	_lr_s3=$(region '^### 3\. ' '^#### Agents 1–6 ' "$1")
	# One sentence per line: split at a full stop followed by a space, so
	# `spawn.end` and `§5` stay whole (awk, not sed: a `\n` in a sed
	# replacement is GNU's alone).
	_lr_sen=$(printf '%s\n' "$_lr_s3" | tr '\n' ' ' | awk '{ gsub(/\. /, ".\n"); print }')
	_lr_end=$(printf '%s\n' "$_lr_s3" | grep -o '`sh scripts/trace\.sh emit kind=spawn\.end[^`]*`' || true)
	_lr_out=''
	[ "$(printf '%s\n' "$_lr_end" | grep -c .)" = 1 ] || _lr_out="$_lr_out one-spawn.end-emit-in-§3"
	printf '%s\n' "$_lr_end" | grep -qF 'outcome=ok|unreachable|fail' || _lr_out="$_lr_out outcome=ok|unreachable|fail"
	printf '%s\n' "$_lr_end" | grep -qF 'data.agent=<roster-token>' || _lr_out="$_lr_out spawn.end-data.agent"
	printf '%s\n' "$_lr_sen" | grep -F 'Every lens this review planned' | grep -qF 'before the verdict' ||
		_lr_out="$_lr_out every-lens-before-the-verdict"
	printf '%s\n' "$_lr_sen" | grep -F 'outcome=refused' | grep -F 'no `spawn.end`' | grep -qF 'concurrent' ||
		_lr_out="$_lr_out refused-lens:outcome=refused-and-no-spawn.end"
	# One sentence binds each outcome to its cause: `ok` to a returned report,
	# `unreachable` to a vendor's refusal (#566), `fail` to no report.
	printf '%s\n' "$_lr_sen" | grep -F 'started' | grep -F 'ends in exactly one `spawn.end`' |
		grep -F '`ok` when it returned its report' | grep -F '`unreachable` when its vendor refused it' |
		grep -F '`fail` when it ended with' |
		grep -qF 'no report' || _lr_out="$_lr_out started-lens:one-spawn.end-ok-and-fail-with-cause"
	# #566: the refusal is named by the text a spawn returns, `fail` keeps
	# every other cause, and an unreachable lens is re-resolved past the model
	# it was spawned on — never a name read out of the error.
	printf '%s\n' "$_lr_sen" | grep -F '`unreachable` when its vendor refused it' | grep -F 'out of usage credits' |
		grep -F 'rate_limit' | grep -qF '429' || _lr_out="$_lr_out unreachable-bound-to-the-refusal-text"
	printf '%s\n' "$_lr_sen" | grep -F '`fail` when it ended with' | grep -qF 'any other cause' ||
		_lr_out="$_lr_out fail-kept-for-any-other-cause"
	printf '%s\n' "$_lr_sen" | grep -F 'AGENT_UNREACHABLE_MODELS="$model"' | grep -F 'sh scripts/agents.lib.sh reviewer' |
		grep -qF 're-resolve' || _lr_out="$_lr_out re-resolve-past-the-model-it-spawned-on"
	printf '%s\n' "$_lr_sen" | grep -F 'in this context instead' | grep -qF 'its record stands' ||
		_lr_out="$_lr_out audited-here:record-stands"
	# ADR-0035 clause 2 (review of #844, M-2): a spent walk names the lens
	# under `Lenses not run:`, and only a context with no subagent tool
	# audits in place — no sentence of §3 sends a spent walk to this context.
	printf '%s\n' "$_lr_sen" | grep -F 'the walk is spent' | grep -qF '`Lenses not run:`' ||
		_lr_out="$_lr_out spent-walk:named-under-lenses-not-run"
	printf '%s\n' "$_lr_sen" | grep -F 'the walk is spent' | grep -qF 'in this context instead' &&
		_lr_out="$_lr_out spent-walk:audited-here"
	printf '%s\n' "$_lr_sen" | grep -F 'in this context instead' | grep -F 'its record stands' |
		grep -qF 'no subagent tool' || _lr_out="$_lr_out audited-here:only-with-no-subagent-tool"
	_lr_line=$(region '^### Review Summary$' '^| | Severity | Count |$' "$1" | grep '^Lenses not run: ')
	for _lr_p in 'refused' 'ended in fail' 'in this context instead'; do
		printf '%s\n' "$_lr_line" | grep -qF -- "$_lr_p" || _lr_out="$_lr_out summary-line:'$_lr_p'"
	done
	grep -qF 'line is never a clean audit' "$1" || _lr_out="$_lr_out never-a-clean-audit"
	# The roster says where every `data.agent` is written; `spawn.end` writes
	# one too, so the roster's list of places names it (review of #512).
	grep '^\*\*The sub-agent roster\.\*\*' "$1" | grep -qF 'on the spawn and its `spawn.end` above' ||
		_lr_out="$_lr_out roster-names-spawn.end"
	printf '%s' "$_lr_out" | sed 's/^ //'
}
miss=$(lens_rules_missing "$SKILL_ABS")
[ -z "$miss" ] && pass "/review-pr records a refused lens as refused with no spawn.end, ends a started one in one spawn.end with each outcome bound to its cause, before the verdict, and names a lens not run in its summary" ||
	fail "/review-pr's lens accounting is missing: $miss — a review whose lenses never ran reads as one that ran (retro F6)"
# The line sits between Clean audits and the count table.
c=$(t_line_of "$SKILL_ABS" "Clean audits:")
ln=$(t_line_of "$SKILL_ABS" "Lenses not run: ")
th=$(t_line_of "$SKILL_ABS" "| | Severity | Count |")
[ -n "$ln" ] && [ "$c" -lt "$ln" ] && [ "$ln" -lt "$th" ] &&
	pass "the summary's 'Lenses not run:' line sits between Clean audits ($c) and the count table ($th)" ||
	fail "'Lenses not run:' is not between Clean audits ($c) and the count table ($th) — got '$ln'"
# Baits: one per rule the reader holds, so no rule survives its own deletion.
for b in \
	's/\(kind=spawn\.end[^`]*\)outcome=ok|unreachable|fail/\1outcome=ok|fail/' \
	's/\(kind=spawn\.end[^`]*\) data\.agent=<roster-token>/\1/' \
	's/\(`sh scripts\/trace\.sh emit kind=spawn\.end[^`]*`\)/\1 and \1/' \
	's/outcome=refused/outcome=fail/g' \
	's/no `spawn\.end`/a `spawn.end`/g' \
	's/ends in exactly one `spawn\.end`/ends in a `spawn.end`/g' \
	's/`fail` when it ended/`ok` when it ended/' \
	's/`unreachable` when its vendor/`fail` when its vendor/' \
	's/`ok` when it returned its report/`fail` when it returned its report/' \
	's/vendor refused it/vendor paused it/g' \
	's/out of usage credits/out of credit/' \
	's/rate_limit/throttle/g' \
	's/HTTP 429/HTTP 4xx/g' \
	's/any other cause/one cause/g' \
	's/AGENT_UNREACHABLE_MODELS="$model"/AGENT_UNREACHABLE_MODELS="<the model>"/g' \
	's/re-resolve/resolve/g' \
	's/no report/a short report/g' \
	's/before the verdict/after the verdict/g' \
	's/its record stands/its record is replaced/' \
	's/^Lenses not run: .*$//' \
	'/^Lenses not run: /s/refused/stopped/g' \
	'/^Lenses not run: /s/ended in fail/ended badly/' \
	'/^Lenses not run: /s/in this context instead/elsewhere/' \
	's/line is never a clean audit/line is a clean audit/' \
	's/on the spawn and its `spawn\.end` above/on the spawn above/'; do
	sed "$b" "$SKILL_ABS" >"$SCRATCH/bait482.md"
	if ! cmp -s "$SCRATCH/bait482.md" "$SKILL_ABS" && [ -n "$(lens_rules_missing "$SCRATCH/bait482.md")" ]; then
		pass "bait: '$b' goes red"
	else
		fail "bait: '$b' was not caught — or planted nothing"
	fi
done

# ---------------------------------------------------------------------------
banner "12. Axis 2 cites requirement ids where the spec carries them (process/R9)"
# ---------------------------------------------------------------------------
# #532, ADR-0012 clause 6. Agent 7 cited "a PRD acceptance criterion" the PRD
# template never had, so a SPECIFIED citation was free text, and a requirement
# a ticket promised on its `Covers:` line could go undelivered with nothing on
# the confirm-list to say so. Where the spec carries ids, a ✅ cites the id and
# every covered id the diff leaves undone is a ❌ MISSING naming it; with no ids,
# both read as before. Two sentences in Agent 7's procedure rule it, and the
# offline worker and its CI twin say them word for word — the same two axes,
# the same standard — so the three reviewers of one diff cite alike. The tags
# are the existing ones, so the line shape the broker reads does not move
# (tests/forge-broker.test.sh section 22 lands such a report).
R9_IDS='**Where the spec carries requirement ids** — `R<n>` lines in a PRD'"'"'s Requirements section, `<area>/R<n>` for a living spec'"'"'s, and a ticket'"'"'s `Covers:` line naming the ones it delivers — a ✅ SPECIFIED item cites the id of the requirement it delivers, and every id on the ticket'"'"'s `Covers:` line that the diff does not deliver is a ❌ MISSING item naming that id, so a covered requirement left undone reaches the human on the confirm-list rather than passing in silence'
R9_NONE='**With no requirement ids in the spec**, both read as they always have: a ✅ SPECIFIED item cites the PRD, ticket or decision-record line it answers, and a ❌ MISSING item names the spec line the diff does not deliver'
a7_sentences=$(region '^#### Agent 7 ' '^### 4\. ' | sentences)
[ -n "$a7_sentences" ] && pass "Agent 7's procedure is extractable" ||
	fail "Agent 7's region is empty — its heading or §4's moved and this section lost them"
for want in "$R9_IDS" "$R9_NONE"; do
	carries "$a7_sentences" "$want" &&
		pass "process/R9: Agent 7 says it, word for word: ${want%%,*}" ||
		fail "process/R9: Agent 7's procedure does not say, word for word: $want"
done
for f in "$WORKER" "$TWIN"; do
	f_sentences=$(sentences_for "$f")
	for want in "$R9_IDS" "$R9_NONE"; do
		carries "$f_sentences" "$want" &&
			pass "process/R9: $f says Agent 7's sentence word for word: ${want%%,*}" ||
			fail "process/R9: $f does not say Agent 7's requirement-id sentence word for word — its reviewer would cite differently: $want"
	done
done
# The worker's items are one line each, and the broker lifts that line and
# drops any other — so the dispatched form puts the id on the item's own line,
# where §5b's two-line ✅ would lose it.
t_text_has "$(unwrap "$WORKER")" "The id goes on the item's own line, right after its tag: the session that lands this report keeps the tagged line and drops any line beneath it" "process/R9: a dispatched item's id survives the broker's one-line lift" "$WORKER"
# The template the report prints carries the id in the citation slot of a ✅
# and in the body of a ❌ — after the tag, so the tag still opens the line.
t_text_has "$axis2" "→ <the requirement id it delivers, where the spec carries ids; else the PRD/ticket/decision-record citation>" "process/R9: the ✅ template's citation is the id where there is one" "the §5b template"
t_text_has "$axis2" "❌ MISSING      <the requirement id the ticket covers, where the spec carries ids; else the spec line the diff does not deliver>" "process/R9: the ❌ template names the covered id where there is one" "the §5b template"
# Baits: each weakening of the ruling, in the skill, goes red.
for b in \
	's/a ✅ SPECIFIED item cites the id/a ✅ SPECIFIED item may cite the id/' \
	's/is a ❌ MISSING item naming that id/is left off the list/' \
	's/reaches the human on the confirm-list/is noted for the author/' \
	's/both read as they always have/both cite a requirement id anyway/'; do
	carries "$(printf '%s\n' "$a7_sentences" | sed "$b")" "$R9_IDS" &&
		carries "$(printf '%s\n' "$a7_sentences" | sed "$b")" "$R9_NONE" &&
		fail "bait: '$b' still reads as the ruling" ||
		pass "bait: '$b' goes red"
done

# ---------------------------------------------------------------------------
banner "13. A single-reviewer review says so, and records both verdicts (#568)"
# ---------------------------------------------------------------------------
# Retro 20261006T080718Z (questions 2 and 6): 7 of 33 reviews ran ONE reviewer
# that audited every lens itself, yet filed its raises under lens tokens no
# lens agent produced — /retro's count per lens read the reviewer's own
# sorting as a lens's signal — and two reviews recorded no review.verdict at
# all. The ruling: the seven sub-agents are the protocol, and one context
# auditing the lenses itself — the single-reviewer pass — is allowed only
# when no lens agent can run, and only when recorded: its own roster token on
# every raise a lens agent did not produce, the same token on both verdict
# lines, and both verdicts on every review, before the run's end.
# single_rules_missing <skill file> — the rules the file has lost, one name
# per line. Each rule is held where it is read: the roster row in the roster,
# the protocol in §3, the raise in §6's record step, the relay in its own
# section, the verdicts beside §5b's emit and the end in §7.
single_rules_missing() {
	_sr_rows=$(t_roster_rows "$1")
	printf '%s\n' "$_sr_rows" | grep -qF -- '- `single-reviewer` — ' || printf '%s\n' 'roster row'
	printf '%s\n' "$_sr_rows" | grep -F -- '- `single-reviewer` — ' | grep -qF "a spawn's token only as [\`LENS-RETURN.md\`](LENS-RETURN.md) says" || printf '%s\n' 'row: a spawn only per LENS-RETURN'
	_sr_s3=$(region '^### 3\. ' '^#### Agents 1–6 ' "$1" | tr '\n' ' ' | tr -s ' ')
	for _sr_r in \
		'protocol|**The seven sub-agents are the protocol; one context auditing every lens itself is the single-reviewer pass, allowed only when no lens agent can run and only when recorded.**' \
		'never to save spawns|never a choice made to save spawns: a context that can spawn the seven spawns them' \
		'summary names the lenses|Its summary'"'"'s `Lenses not run:` line names every lens it audited, each marked "run in this context instead"' \
		'raises under the token|Every finding it raises carries `data.agent=single-reviewer`, never the token of a lens no lens agent ran' \
		'verdicts carry the token|both of its verdict lines (§5, §5b) carry `data.agent=single-reviewer`'; do
		case "$_sr_s3" in *"${_sr_r#*|}"*) ;; *) printf '%s\n' "${_sr_r%%|*}" ;; esac
	done
	_sr_rec=$(region '^#### Approval Process' '^#### Relaying a review' "$1" | tr '\n' ' ' | tr -s ' ')
	case "$_sr_rec" in *'On a single-reviewer pass (§3) the token is `single-reviewer` for every finding no lens agent produced'*) ;; *) printf '%s\n' 'raise step: the token' ;; esac
	_sr_rel=$(region '^#### Relaying a review' '^### 7\. ' "$1" | tr '\n' ' ' | tr -s ' ')
	case "$_sr_rel" in *'`single-reviewer` for every finding of a report that says one reviewer audited the lenses itself, whatever lens it names'*) ;; *) printf '%s\n' 'relay: the token' ;; esac
	_sr_5b=$(region '^### 5b\. ' '^### 6\. ' "$1" | tr '\n' ' ' | tr -s ' ')
	case "$_sr_5b" in *'**Both verdicts are recorded on every review — seven agents, a single-reviewer pass, a relay — before anything is posted and before the run'"'"'s `end` (§7).**'*) ;; *) printf '%s\n' 'both verdicts always' ;; esac
	case "$_sr_5b" in *'A verdict is never skipped because the report had no findings: `pass` is a verdict.'*) ;; *) printf '%s\n' 'pass is a verdict' ;; esac
	_sr_cl=$(region '^### 7\. ' '^ZZZ' "$1" | tr '\n' ' ' | tr -s ' ')
	case "$_sr_cl" in *'the run closes after the raises and both verdicts, never before them'*) ;; *) printf '%s\n' 'end after both verdicts' ;; esac
}
miss=$(single_rules_missing "$SKILL_ABS" | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "/review-pr allows a single-reviewer pass only when no lens agent can run, files its raises and verdicts under its own token, and records both verdicts on every review before the end" ||
	fail "/review-pr's single-reviewer rules are missing: $miss — a one-reviewer review files raises under lenses nobody ran (retro 20261006T080718Z)"
# The token is a token on the roster — the holder in tests/trace-skills.test.sh
# reads every data.agent against it — and it is not a lens: it has no Agent
# number, so the lens count other skills read (/to-tickets' session cap)
# stays the seven agents.
t_roster_rows "$SKILL_ABS" | grep -F -- '- `single-reviewer` — ' | grep -q 'Agent [0-9]' &&
	fail "the single-reviewer row names an agent number — it is not a lens, and the lens count would grow" ||
	pass "the single-reviewer row names no agent number: it is not a lens"
# Baits: each rule deleted from a copy is named.
for b in \
	'roster row|/^- `single-reviewer` — /d' \
	'row: a spawn only per LENS-RETURN|/^- `single-reviewer` — /s/ only as / /' \
	'protocol|s/allowed only when no lens agent can run and only when recorded/allowed whenever it is quicker/' \
	'never to save spawns|s/never a choice made to save spawns/also a way to save spawns/' \
	'summary names the lenses|s/line names every lens it audited/line may name a lens/' \
	'raises under the token|s/never the token of a lens no lens agent ran/or the token of the lens it fits/' \
	'verdicts carry the token|s/both of its verdict lines (§5, §5b) carry/its verdict lines may carry/' \
	'raise step: the token|s/the token is `single-reviewer` for every finding no lens agent produced/the token is the lens it fits/' \
	'relay: the token|s/whatever lens it names/unless it names a lens/' \
	'both verdicts always|s/Both verdicts are recorded on every review/A verdict is recorded on most reviews/' \
	'pass is a verdict|s/`pass` is a verdict\./no findings need no verdict./' \
	'end after both verdicts|s/closes after the raises and both verdicts/closes after the raises/'; do
	bait_gap single_rules_missing "${b%%|*}" "${b#*|}" && pass "bait: /review-pr without '${b%%|*}' goes red" ||
		fail "bait: /review-pr without '${b%%|*}' was not caught — or the bait planted nothing"
done

# ---------------------------------------------------------------------------
banner "14. Each standards lens reads only its own instructions (#589)"
# ---------------------------------------------------------------------------
# PRD #580's baseline: 6.5% of all spawn tool output went to lens agents
# re-reading the whole 44KB skill. So SKILL.md is the coordinator, and each
# Axis-1 lens's instructions live in a file of their own beside it, named by
# its roster token — `lens-<token>.md` — which is the one file that lens's
# agent is handed. Agent 7 (Axis 2) stays in SKILL.md: the behavior axis is
# unchanged. lens_gaps <a skill directory> — what the split has lost, one line
# per gap; nothing printed when every lens has its file, its heading and its
# name in the coordinator, and the coordinator carries no lens body.
lens_gaps() {
	_lg_rows=$(t_roster_rows "$1/SKILL.md" | grep -E '^- `[a-z-]+` — Agent [1-6], ')
	[ "$(printf '%s\n' "$_lg_rows" | grep -c .)" = 6 ] || printf '%s\n' 'six Axis-1 roster rows'
	printf '%s\n' "$_lg_rows" | while IFS= read -r _lg_row; do
		_lg_tok=$(printf '%s\n' "$_lg_row" | sed 's/^- `\([^`]*\)`.*/\1/')
		_lg_n=$(printf '%s\n' "$_lg_row" | sed 's/^.* — Agent \([1-6]\), .*/\1/')
		_lg_title=$(printf '%s\n' "$_lg_row" | sed 's/^.* — Agent [1-6], //')
		_lg_f="$1/lens-$_lg_tok.md"
		[ -f "$_lg_f" ] || { printf 'lens-%s.md: no file\n' "$_lg_tok"; continue; }
		grep -qxF -- "#### Agent $_lg_n — $_lg_title" "$_lg_f" || printf 'lens-%s.md: no Agent %s heading\n' "$_lg_tok" "$_lg_n"
		grep -qF -- "lens-$_lg_tok.md" "$1/SKILL.md" || printf 'SKILL.md: lens-%s.md not named\n' "$_lg_tok"
	done
	grep -qE '^#### Agent [1-6] ' "$1/SKILL.md" && printf '%s\n' 'SKILL.md: a lens body is still in the coordinator'
	grep -qE '^#### Agent 7 — ' "$1/SKILL.md" || printf '%s\n' 'SKILL.md: Agent 7 left the coordinator'
	_lg_flat=$(tr '\n' ' ' <"$1/SKILL.md" | tr -s ' ')
	printf '%s\n' "$_lg_flat" | grep -qF "A lens agent reads its own file and this skill's §4 and §5, never the rest of it" ||
		printf '%s\n' 'SKILL.md: no rule that a lens agent reads only its own file'
	for _lg_w in 'for Agent 5, step 1'"'"'s reuse catalog' 'for Agent 6, the mutation delta' '§5 (the severity buckets and the finding anatomy)'; do
		printf '%s\n' "$_lg_flat" | grep -qF -- "$_lg_w" || printf 'SKILL.md: the lens hand-off lost "%s"\n' "$_lg_w"
	done
	for _lg_f in "$1"/lens-*.md; do
		[ -f "$_lg_f" ] || continue
		_lg_tok=$(basename "$_lg_f" .md)
		printf '%s\n' "$_lg_rows" | grep -qF -- "- \`${_lg_tok#lens-}\` — " || printf '%s: no roster row\n' "$_lg_tok"
	done
	:
}
LENS_DIR=$(dirname "$SKILL_ABS")
gaps=$(lens_gaps "$LENS_DIR")
[ -z "$gaps" ] && pass "six lens files, each named by its roster token and carrying its own heading; the coordinator names each, holds no lens body, keeps Agent 7, and hands a lens only its own file" ||
	fail "the lens split has gaps: $(printf '%s' "$gaps" | tr '\n' ';')"
# Baits: a copy of the skill with one lens file gone, and one with a lens body
# put back into the coordinator — lens_gaps must name each.
mkdir -p "$SCRATCH/lens-bait"
cp "$LENS_DIR"/*.md "$SCRATCH/lens-bait/"
rm -f "$SCRATCH/lens-bait/lens-simplicity.md"
lens_gaps "$SCRATCH/lens-bait" | grep -qF 'lens-simplicity.md: no file' &&
	pass "bait: a lens file removed is named" || fail "bait: a lens file removed was not caught"
cp "$LENS_DIR/lens-simplicity.md" "$SCRATCH/lens-bait/"
cat "$SCRATCH/lens-bait/lens-simplicity.md" >>"$SCRATCH/lens-bait/SKILL.md"
lens_gaps "$SCRATCH/lens-bait" | grep -qF 'a lens body is still in the coordinator' &&
	pass "bait: a lens body back in the coordinator is named" || fail "bait: a lens body back in the coordinator was not caught"

# One bait per remaining rule (#621 review M-3): each mutant of a fresh copy
# must be named by the gap it plants.
lens_bait() {
	rm -rf "$SCRATCH/lens-bait" && mkdir -p "$SCRATCH/lens-bait" && cp "$LENS_DIR"/*.md "$SCRATCH/lens-bait/" &&
		sed -i "$2" "$SCRATCH/lens-bait/$1" &&
		lens_gaps "$SCRATCH/lens-bait" | grep -qF -- "$3"
}
for b in \
	'lens-pattern.md|s/^#### Agent 3 — .*/#### Agent 3 — Something Else/|lens-pattern.md: no Agent 3 heading' \
	'SKILL.md|s/lens-api-crud\.md/lens-api.md/g|SKILL.md: lens-api-crud.md not named' \
	'SKILL.md|s/^#### Agent 7 — /#### Axis 2 — /|Agent 7 left the coordinator' \
	'SKILL.md|s/never the rest of it/and whatever else it likes/|no rule that a lens agent reads only its own file' \
	'SKILL.md|s/for Agent 6, the mutation delta/for Agent 6, nothing/|lost "for Agent 6, the mutation delta"' \
	'SKILL.md|/^- `pattern` — /d|six Axis-1 roster rows'; do
	f=${b%%|*}; r=${b#*|}; e=${r%%|*}; w=${r#*|}
	lens_bait "$f" "$e" "$w" && pass "bait: '$w' is named" || fail "bait: '$w' was not caught"
done
rm -rf "$SCRATCH/lens-bait" && mkdir -p "$SCRATCH/lens-bait" && cp "$LENS_DIR"/*.md "$SCRATCH/lens-bait/" &&
	cp "$LENS_DIR/lens-pattern.md" "$SCRATCH/lens-bait/lens-orphan.md"
lens_gaps "$SCRATCH/lens-bait" | grep -qF 'lens-orphan: no roster row' &&
	pass "bait: a lens file with no roster row is named" || fail "bait: an orphan lens file was not caught"


# ---------------------------------------------------------------------------
banner "15. A posted review is never raise-less or verdict-less (#629)"
# ---------------------------------------------------------------------------
# #603, #617 and #626 posted reviews whose trace held no finding.raise and no
# review.verdict: the emits were left to the end of the review and written
# from memory, and a whole review's worth was lost at once. The ruling: on
# path (a) — the spawn prompt answered the post question before any lens ran
# — a lens's raises are recorded beside its spawn.end the moment it returns,
# and both verdicts are recorded before anything is posted.
# emit_points_missing <skill file> — each rule the file has lost, one per line.
emit_points_missing() {
	_ep_s3=$(region '^### 3\. ' '^#### Agents 1–6 ' "$1" | tr '\n' ' ' | tr -s ' ')
	for _ep_r in \
		"raise at lens return|**On §6's path (a) a lens's raises are recorded beside its \`spawn.end\`, the moment it returns**" \
		'ids in arrival order|the coordinator numbers it in arrival order' \
		"audited here raises at its end|raises that lens's findings the moment its audit ends" \
		'b and c raise at 6|Paths (b) and (c) learn their answer after the report, and raise at §6'; do
		case "$_ep_s3" in *"${_ep_r#*|}"*) ;; *) printf '%s\n' "${_ep_r%%|*}" ;; esac
	done
	_ep_ap=$(region '^#### Approval Process' '^#### Relaying a review' "$1" | tr '\n' ' ' | tr -s ' ')
	case "$_ep_ap" in *'records every raise as its lens returned (§3)'*) ;; *) printf '%s\n' 'path a points at the lens return' ;; esac
	case "$_ep_ap" in *'whose relay (below) posts it and records no second raise'*) ;; *) printf '%s\n' 'unreachable forge: no second raise' ;; esac
	_ep_5=$(region '^### 5\. ' '^### 5b\. ' "$1" | tr '\n' ' ' | tr -s ' ')
	case "$_ep_5" in *"Record the axis's verdict once, before anything is posted"*) ;; *) printf '%s\n' 'axis 1 verdict before the post' ;; esac
	_ep_5b=$(region '^### 5b\. ' '^### 6\. ' "$1" | tr '\n' ' ' | tr -s ' ')
	case "$_ep_5b" in *'before anything is posted and before the run'*) ;; *) printf '%s\n' 'both verdicts before the post' ;; esac
	_ep_rl=$(region '^#### Relaying a review' '^### 7\. ' "$1" | tr '\n' ' ' | tr -s ' ')
	case "$_ep_rl" in *'record, verdict, post'*) ;; *) printf '%s\n' 'relay order' ;; esac
	_ep_v=$(t_line_of "$1" '**Then the two verdicts')
	_ep_p=$(t_line_of "$1" '**Then post**')
	[ -n "$_ep_v" ] && [ -n "$_ep_p" ] && [ "$_ep_v" -lt "$_ep_p" ] || printf '%s\n' 'relay verdicts above its post'
}
miss=$(emit_points_missing "$SKILL_ABS" | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "/review-pr records a lens's raises at its return on path (a), and both verdicts before anything is posted" ||
	fail "/review-pr's emit points are missing: $miss — a posted review reads raise-less in the trace (#629)"
for b in \
	"raise at lens return|s/a lens's raises are recorded beside its \`spawn.end\`, the moment it returns/a lens's raises wait for the end/" \
	'ids in arrival order|s/numbers it in arrival order/picks/' \
	"audited here raises at its end|s/the moment its audit ends/at the end/" \
	'b and c raise at 6|s/and raise at §6/and raise whenever/' \
	'path a points at the lens return|s/records every raise as its lens returned (§3)/records every raise/' \
	'unreachable forge: no second raise|s/posts it and records no second raise/records them again/' \
	"axis 1 verdict before the post|s/verdict once, before anything is posted/verdict once/" \
	'both verdicts before the post|s/before anything is posted and before the run/before the run/' \
	'relay order|s/record, verdict, post/record, post, verdict/' \
	'relay verdicts above its post|s/\*\*Then the two verdicts/**Last, the two verdicts/'; do
	bait_gap emit_points_missing "${b%%|*}" "${b#*|}" && pass "bait: /review-pr without '${b%%|*}' goes red" ||
		fail "bait: /review-pr without '${b%%|*}' was not caught — or the bait planted nothing"
done
# The acceptance, run: replay every documented trace line above §6 — the
# protocol up to the first post — in document order, under one review run.
# The run holds a spawn.end and a review.verdict for axis 1 and for axis 2:
# a verdict whose emit moved below the post is red here.
replay_before_post() { # <skill file> <trace dir> — exit 0 when every span ran
	_rp_cut=$(t_line_of "$1" '### 6. ')
	head -n "$((_rp_cut - 1))" "$1" >"$SCRATCH/pre-post.md"
	# §3 hands path (a)'s raise to §6 step 3's line: the replay types it there.
	region '^### 3\. ' '^#### Agents 1–6 ' "$1" | grep -qF "§6 step 3's line" &&
		t_trace_lines "$1" | grep -F 'kind=finding.raise' | grep -vF 'data.via=relay' >>"$SCRATCH/pre-post.md"
	printf '`sh scripts/trace.sh end <the run id your begin printed> outcome=ok || :`\n' >>"$SCRATCH/pre-post.md"
	_rp_bad=0
	while IFS= read -r _rp_span; do
		[ -n "$_rp_span" ] || continue
		_rp_cmd=$(t_trace_runnable "$_rp_span")
		( cd "$ROOT" && TRACE_DIR="$2" TRACE_QUIET=1 sh -c "$_rp_cmd" >/dev/null 2>&1 ) || _rp_bad=1
	done <<SPANS
$(t_trace_spans "$SCRATCH/pre-post.md")
SPANS
	return "$_rp_bad"
}
AGENTS_CONFIG="$SCRATCH/agents.x.sh"
export AGENTS_CONFIG
printf "AGENT_TIER_REVIEWER='x'\n" >"$AGENTS_CONFIG"
holds_before_post() { # <trace dir> — names each record the replayed run lacks
	_hb=$(cat "$1"/events/*.jsonl 2>/dev/null)
	printf '%s\n' "$_hb" | grep -qF '"kind":"spawn.end"' || printf '%s\n' 'spawn.end'
	printf '%s\n' "$_hb" | grep -qF '"kind":"finding.raise"' || printf '%s\n' 'finding.raise'
	for _hb_a in 1 2; do
		printf '%s\n' "$_hb" | grep -F '"kind":"review.verdict"' | grep -qE "\"axis\":\"?$_hb_a\"?[,}]" || printf '%s\n' "verdict axis $_hb_a"
	done
}
rm -rf "$SCRATCH/run.629"
replay_before_post "$SKILL_ABS" "$SCRATCH/run.629" && pass "every documented trace line above §6 runs" ||
	fail "a documented trace line above §6 does not run"
miss=$(holds_before_post "$SCRATCH/run.629" | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "a review run replayed up to the first post holds its spawn.end, a lens's finding.raise and review.verdict for axis 1 and axis 2" ||
	fail "a review run replayed up to the first post lacks: $miss — a posted review reads verdict-less (#629)"
# Bait: the axis-2 verdict's emit moved below the post — the replay is red.
awk '/kind=review\.verdict[^`]*data\.axis=2/ && !done { held = $0; done = 1; sub(/`sh scripts\/trace\.sh emit kind=review\.verdict[^`]*`/, "", $0) } /^#### Relaying a review/ && held { print held } { print }' "$SKILL_ABS" >"$SCRATCH/bait629-late.md"
rm -rf "$SCRATCH/run.629b"
replay_before_post "$SCRATCH/bait629-late.md" "$SCRATCH/run.629b" || :
holds_before_post "$SCRATCH/run.629b" | grep -qxF 'verdict axis 2' &&
	pass "bait: an axis-2 verdict recorded after the post is red" ||
	fail "bait: an axis-2 verdict moved below the post was not caught"
# Bait: §3 without the lens-return raise — the replay holds no raise before the post.
sed "s/§6 step 3's line/the line in §6/" "$SKILL_ABS" >"$SCRATCH/bait629-noraise.md"
rm -rf "$SCRATCH/run.629c"
replay_before_post "$SCRATCH/bait629-noraise.md" "$SCRATCH/run.629c" || :
holds_before_post "$SCRATCH/run.629c" | grep -qxF 'finding.raise' &&
	pass "bait: a raise left for the end of the review is red" ||
	fail "bait: a review that raises nothing before the post was not caught"

# ---------------------------------------------------------------------------
banner "16. A LOW is counted, never posted by an agent (#635)"
# ---------------------------------------------------------------------------
# Retro F3 (2026-10-07): 114 of 171 raises were LOW, all posted, and the loop
# declined 52 of them as lows. The ruling: a lens still raises a LOW (about
# four in ten triaged LOWs were applied), the report and the trace count it,
# and no agent path posts it; /pr-iterate applies a mechanical one or declines
# it citing the band, and never hands one to the operator. Section 17 (#732)
# narrows the raise itself to a LOW that passes the band's test.
ITER_ABS="$ROOT/$ITER"
# low_band_missing <review-pr file> <pr-iterate file> — each rule lost, one per line.
low_band_missing() {
	_lb_r=$(tr '\n' ' ' <"$1" | tr -s ' ')
	_lb_i=$(tr '\n' ' ' <"$2" | tr -s ' ')
	for _lb in \
		'band rule|**A LOW is counted, never posted by an agent path of this skill**' \
		'band says why not stop at medium|why not a lens that stops at MEDIUM' \
		'path a: a LOW is posted=no|and `no` for every LOW (§5)' \
		'relay: a LOW is posted=no|`no` for a LOW, which no relay posts (§5)' \
		'relay posts no LOW|never a LOW (§5)'; do
		case "$_lb_r" in *"${_lb#*|}"*) ;; *) printf '%s\n' "${_lb%%|*}" ;; esac
	done
	_lb_b=$(t_line_of "$1" '**A LOW is counted, never posted by an agent path of this skill**')
	_lb_h=$(t_line_of "$1" 'LOW is minor simplifications and style')
	[ -n "$_lb_b" ] && [ "$_lb_b" = "$_lb_h" ] || printf '%s\n' 'band rule beside the bands'
	for _lb in \
		'iterate: a LOW row|| A LOW | Apply it only when it is clear and mechanical, inside this diff' \
		'iterate: decline cites the band|decline it, citing `/review-pr` §5' \
		'iterate: never escalate a LOW|never escalated' \
		'iterate: the LOW row wins|for a LOW this row wins over the two above it and over hard rule 7'; do
		case "$_lb_i" in *"${_lb#*|}"*) ;; *) printf '%s\n' "${_lb%%|*}" ;; esac
	done
}
miss=$(low_band_missing "$SKILL_ABS" "$ITER_ABS" | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "a LOW is counted, never posted: the rule beside the bands, path (a), the relay and /pr-iterate's triage" ||
	fail "the LOW band rule is missing: $miss (#635)"
bait635() { # <rule name> <file: r|i> <sed script>
	_bf=$SKILL_ABS; [ "$2" = i ] && _bf=$ITER_ABS
	bait_copy "$_bf" "$SCRATCH/bait635.md" "$3" || return 1
	if [ "$2" = i ]; then low_band_missing "$SKILL_ABS" "$SCRATCH/bait635.md"; else low_band_missing "$SCRATCH/bait635.md" "$ITER_ABS"; fi | grep -qxF -- "$1"
}
for b in \
	'band rule|r|s/A LOW is counted, never posted by an agent path of this skill/A LOW is posted/' \
	'band says why not stop at medium|r|s/why not a lens that stops at MEDIUM/why/' \
	'path a: a LOW is posted=no|r|s/and `no` for every LOW (§5)//' \
	'relay: a LOW is posted=no|r|s/`no` for a LOW, which no relay posts (§5)/likewise/' \
	'relay posts no LOW|r|s/never a LOW (§5)/every finding/' \
	'band rule beside the bands|r|s/ \*\*A LOW is counted, never posted by an agent path of this skill\*\*/\n\n**A LOW is counted, never posted by an agent path of this skill**/' \
	'iterate: a LOW row|i|s/| A LOW | Apply it only/| A LOW | Apply it/' \
	'iterate: decline cites the band|i|s/decline it, citing `\/review-pr` §5/decline it/' \
	'iterate: never escalate a LOW|i|s/never escalated/escalated when unsure/' \
	'iterate: the LOW row wins|i|s/for a LOW this row wins over the two above it and over hard rule 7/when no row above matches/'; do
	_bn=${b%%|*}; _rest=${b#*|}
	bait635 "$_bn" "${_rest%%|*}" "${_rest#*|}" && pass "bait: without '$_bn' goes red" ||
		fail "bait: without '$_bn' was not caught — or the bait planted nothing"
done

# ---------------------------------------------------------------------------
banner "17. A lens raises a LOW only when it passes the band rule's own test (#732)"
# ---------------------------------------------------------------------------
# Retro 2026-10-10: of 150 LOWs triaged, 109 were declined, 104 citing §5's
# band rule — the lenses raised, and the orchestrator triaged, LOWs the policy
# already declines. So the band's test (a clear, mechanical fix inside the
# diff) is applied where a finding is made: §5 states it once, and every
# standards lens file, the dispatched worker's contract and its CI twin carry
# that sentence word for word — read from the skill here, never retyped, so a
# reword on either side is red. A candidate ticket asks the PR for nothing, so
# the sentence itself exempts it.
band_test=$(sentences <"$SKILL_ABS" | grep -F "the test of \`/review-pr\` §5's band rule" | head -n 1)
[ -n "$band_test" ] && pass "§5 states the band rule's own test for a LOW: $band_test" ||
	fail "§5 no longer states the band rule's test for a LOW — nothing to hold the lenses to (#732)"
# band_test_missing <skill dir> <worker> <twin> — each prompt that does not
# carry the band test as a whole sentence, one per line.
band_test_missing() {
	for _bt_f in "$1"/lens-*.md "$2" "$3"; do
		[ -n "$band_test" ] && sentences <"$_bt_f" | grep -qxF -- "$band_test" || basename "$_bt_f"
	done
}
miss=$(band_test_missing "$LENS_DIR" "$WORKER_ABS" "$ROOT/$TWIN" | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "all six lens files, the worker contract and its CI twin carry the band test word for word" ||
	fail "these prompts do not carry §5's band test word for word: $miss (#732)"
# A bait per lens, and one each for the worker and its twin: a fresh copy with
# that prompt's sentence dropped, or reworded, must be named.
bt_bait() { # <file name> <sed script>
	rm -rf "$SCRATCH/bt-bait" && mkdir -p "$SCRATCH/bt-bait" &&
		cp "$LENS_DIR"/*.md "$WORKER_ABS" "$ROOT/$TWIN" "$SCRATCH/bt-bait/" &&
		cp "$SCRATCH/bt-bait/$1" "$SCRATCH/bt-bait/$1.orig" && bait_copy "$SCRATCH/bt-bait/$1.orig" "$SCRATCH/bt-bait/$1" "$2" &&
		band_test_missing "$SCRATCH/bt-bait" "$SCRATCH/bt-bait/review-worker.md" "$SCRATCH/bt-bait/ai-review-prompt.md" | grep -qxF -- "$1"
}
for _bt_l in "$LENS_DIR"/lens-*.md; do
	_bt_n=$(basename "$_bt_l")
	bt_bait "$_bt_n" "/band rule, a clear and mechanical fix/d" &&
		pass "bait: $_bt_n without the band test is named" || fail "bait: $_bt_n without the band test was not caught — or the bait planted nothing"
done
for b in \
	'lens-simplicity.md|s/a clear and mechanical fix inside this diff/a fix/' \
	'review-worker.md|s/clear and mechanical fix/fix/' \
	'ai-review-prompt.md|s/a clear and mechanical fix/a fix/'; do
	bt_bait "${b%%|*}" "${b#*|}" && pass "bait: ${b%%|*} with the band test reworded is named" ||
		fail "bait: ${b%%|*} with the band test reworded was not caught — or the bait planted nothing"
done
rm -rf "$SCRATCH/bt-bait"

# ---------------------------------------------------------------------------
banner "18. The lenses resolve against the author's model, not the orchestrator's (#730)"
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # the span is matched as text, never expanded here
resolve_span=$(grep -o '`model=$(AGENT_SESSION_MODEL=[^`]*`' "$SKILL_ABS" | head -n 1 | tr -d '`')
case $resolve_span in
*"'<author>'"*"sh scripts/agents.lib.sh reviewer)") pass "§3 resolves the reviewer tier with the author named as the session: $resolve_span" ;;
*) fail "§3's one resolve no longer names the author as the session model — got '$resolve_span' (#730)" ;;
esac
assert_file_has "$SKILL" "\`Author-Model:\` line"
assert_file_has ".agents/skills/implement/SKILL.md" "\`Author-Model: <"
# lens_resolve <span> <author> — the span run as an agent runs it, from the
# root, by an orchestrator that exported its OWN model (the reviewer's) as the
# session, against a policy where the reviewer and the author differ.
AUTHOR_POLICY="$SCRATCH/730-agents.config.sh"
t_write_config "$AUTHOR_POLICY" "AGENT_TIER_REVIEWER='stand-in-reviewer'
AGENT_TIER_IMPLEMENTER='stand-in-implementer'"
lens_resolve() {
	_lr_cmd=$(printf '%s' "$1" | sed "s/<author>/$2/")
	t_exec env AGENTS_TIER_QUIET= AGENTS_CONFIG="$AUTHOR_POLICY" \
		AGENT_SESSION_MODEL=stand-in-reviewer sh -c "$_lr_cmd; printf '%s' \"\$model\""
}
lens_resolve "$resolve_span" stand-in-implementer
if [ "$T_STATUS" = 0 ] && [ "$T_OUT" = stand-in-reviewer ] && [ -z "$T_ERR" ]; then
	pass "a diff authored on another model: the lenses resolve to the reviewer, no warning"
else
	fail "a diff authored on another model: expected 'stand-in-reviewer' and no warning, got status $T_STATUS, '$T_OUT', stderr '$T_ERR'"
fi
lens_resolve "$resolve_span" stand-in-reviewer
case $T_ERR in
*"share the author's model"*) [ -z "$T_OUT" ] && pass "a diff authored on the reviewer's own model: nothing resolves, and it warns" ||
	fail "a diff authored on the reviewer's own model resolved '$T_OUT' — the author's model reviewing itself" ;;
*) fail "a diff authored on the reviewer's own model did not warn — stderr '$T_ERR'" ;;
esac
# No Author-Model line names nobody: the empty session turns the self-check
# off rather than falling back to the orchestrator's own model.
lens_resolve "$resolve_span" ''
if [ "$T_STATUS" = 0 ] && [ "$T_OUT" = stand-in-reviewer ] && [ -z "$T_ERR" ]; then
	pass "no author named: the lenses resolve to the reviewer, no warning"
else
	fail "no author named: expected 'stand-in-reviewer' and no warning, got status $T_STATUS, '$T_OUT', stderr '$T_ERR'"
fi
# The bait: the span before #730, the session left to the orchestrator.
# shellcheck disable=SC2016
lens_resolve 'model=$(sh scripts/agents.lib.sh reviewer)' stand-in-implementer
case $T_ERR in
*"share the author's model"*) pass "bait: the orchestrator's own model as the session warns falsely on another author's diff" ;;
*) fail "bait: the pre-#730 span did not warn — the leg above cannot fail" ;;
esac
rm -f "$AUTHOR_POLICY"

# ---------------------------------------------------------------------------
banner "19. A lens runs the band rule's acceptance test on a LOW before raising it (#774)"
# ---------------------------------------------------------------------------
# Retro 2026-10-14: after #732 landed, 13 of 18 LOWs the lenses raised on
# #757, #761 and #764 were still declined under the band. Section 17's
# sentence named the test — "a clear and mechanical fix inside this diff" —
# and left a lens to judge "clear" itself; every LOW a lens can write a fix
# for looked clear to it. Triage declined them as a design call, a behavior
# change owing a test, a documented choice, a line owed by another ticket.
# So the sentence now carries the test itself, as the questions triage asks,
# and this leg pins each question's wording into §5 and into every lens
# prompt, so a prompt that drops or softens one is named.
band_questions='fix|its `↳ fix:` line spells out the whole edit, with no choice between designs left to whoever applies it
diff|that edit touches only lines this diff added or changed
behavior|it leaves behavior as it is, owing no new test and undoing no choice a comment, record or other ticket already made
drop|a LOW that fails any one of them is dropped, not raised'
# band_questions_missing <file>… — "<file>: <question>" for each question the
# file's band-test sentence does not carry, one per line.
band_questions_missing() {
	for _bq_f in "$@"; do
		_bq_s=$(sentences <"$_bq_f" | grep -F "the test of \`/review-pr\` §5's band rule" | head -n 1)
		printf '%s\n' "$band_questions" | while IFS= read -r _bq; do
			case "$_bq_s" in *"${_bq#*|}"*) ;; *) printf '%s: %s\n' "$(basename "$_bq_f")" "${_bq%%|*}" ;; esac
		done
	done
}
miss=$(band_questions_missing "$SKILL_ABS" | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "§5's band test asks the acceptance questions: the whole edit, inside the diff, no behavior, drop on any no" ||
	fail "§5's band test lacks its acceptance questions: $miss (#774)"
miss=$(band_questions_missing "$LENS_DIR"/lens-*.md "$WORKER_ABS" "$ROOT/$TWIN" | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "all six lens files, the worker contract and its CI twin ask the acceptance questions before a LOW" ||
	fail "these prompts raise a LOW without the band rule's acceptance test: $miss (#774)"
# A bait per lens: a copy with one question softened must be named, the
# lens and the question both.
for _bq_l in "$LENS_DIR"/lens-*.md; do
	_bq_n=$(basename "$_bq_l")
	sed 's/owing no new test and //' "$_bq_l" >"$SCRATCH/$_bq_n"
	! cmp -s "$SCRATCH/$_bq_n" "$_bq_l" && band_questions_missing "$SCRATCH/$_bq_n" | grep -qxF "$_bq_n: behavior" &&
		pass "bait: $_bq_n without the behavior question is named" ||
		fail "bait: $_bq_n without the behavior question was not caught — or the bait planted nothing"
	rm -f "$SCRATCH/$_bq_n"
done
for b in \
	'fix|s/, with no choice between designs left to whoever applies it//' \
	'diff|s/touches only lines this diff added or changed/touches this diff/' \
	'drop|s/is dropped, not raised/is raised as a LOW/'; do
	sed "${b#*|}" "$SKILL_ABS" >"$SCRATCH/774-skill.md"
	! cmp -s "$SCRATCH/774-skill.md" "$SKILL_ABS" && band_questions_missing "$SCRATCH/774-skill.md" | grep -qxF "774-skill.md: ${b%%|*}" &&
		pass "bait: §5 without the '${b%%|*}' question is named" ||
		fail "bait: §5 without the '${b%%|*}' question was not caught — or the bait planted nothing"
done
rm -f "$SCRATCH/774-skill.md"

# ---------------------------------------------------------------------------
banner "20. A review in which no lens ran is a block, and /pr-iterate does not converge on it (process/R15, process/R16, process/R17)"
# ---------------------------------------------------------------------------
# An empty slice is "not counted as a clean audit" — for one lens. Nothing
# said what a review in which NO lens ran records: a diff whose every slice is
# empty, or whose every spawn failed, could still record an Axis-1 `pass`
# nobody audited. The rule is held where it is read: a pointer in /review-pr
# §3's slice paragraph and beside §5's verdict emit, the branch itself in
# NO-LENS.md beside the skill, and /pr-iterate's stop condition pointing at its
# own NO-LENS.md, which recognises the review's Verdict line byte for byte.
# (The slice paragraph sits under §3's "Agents 1–6" heading.)
# nolens_missing <skills dir> — the rules the tree under <skills dir> has
# lost, one name per line.
nolens_missing() {
	_nl_r3=$(region '^### 3\. ' '^#### Agents 1–6 ' "$1/review-pr/SKILL.md" | tr '\n' ' ' | tr -s ' ')
	_nl_rs=$(region '^#### Agents 1–6 ' '^#### Agent 7 ' "$1/review-pr/SKILL.md" | tr '\n' ' ' | tr -s ' ')
	_nl_r5=$(region '^### 5\. ' '^### 5b\. ' "$1/review-pr/SKILL.md" | tr '\n' ' ' | tr -s ' ')
	_nl_rn=$(tr '\n' ' ' <"$1/review-pr/NO-LENS.md" 2>/dev/null | tr -s ' ')
	_nl_i6=$(region '^### 6 — Stop conditions' '^## Output format' "$1/pr-iterate/SKILL.md" | tr '\n' ' ' | tr -s ' ')
	_nl_in=$(tr '\n' ' ' <"$1/pr-iterate/NO-LENS.md" 2>/dev/null | tr -s ' ')
	# The trigger is step 6's to state; the branch says it once, not twice.
	_nl_n1="count=$(grep -o 'with the reason `no lens ran`' "$1/pr-iterate/NO-LENS.md" 2>/dev/null | grep -c '');"
	for _nl_r in \
		'R15: §3 points at the branch|rs|When every count is 0, open [`NO-LENS.md`](NO-LENS.md) beside this file: that diff still gets a review.' \
		'R15: §3 allows the pass on an all-empty diff|r3|the host offers it no subagent tool, refused the spawns, or every lens slice was empty ([`NO-LENS.md`](NO-LENS.md))' \
		'R15: the pass is one §3 allows|rn|no lens agent can run when there is no slice to hand one' \
		'R17: the trigger is stated once|n1|count=1;' \
		'R15: the pass runs over the whole diff|rn|**A diff whose every lens slice is empty still gets a review: run the single-reviewer pass over the whole diff, `behavior.diff`, and record no Axis-1 verdict before that pass returns.**' \
		'R16: §5 points at the branch|r5|A review in which no lens ran records `blocked`, never `pass`: [`NO-LENS.md`](NO-LENS.md).' \
		'R16: no lens and no pass is a block|rn|**When no Axis-1 lens returned a report and no single-reviewer pass returned, the review records `blocked` and says that no lens ran.**' \
		'R16: the verdict line recorded|rn|sh scripts/trace.sh emit kind=review.verdict subject=pr:#<N> outcome=blocked data.axis=1 data.lenses=0 data.roster=<count> reason='"'"'no lens ran'"'"' || :' \
		'R16: the Verdict line says so|rn|**Verdict:** BLOCKED — no lens ran; this is not a review' \
		'R16: some lenses ran is unchanged|rn|A review in which some lenses ran is unchanged' \
		'R17: step 6 points at the branch|i6|- The review recorded Axis 1 `blocked` with the reason `no lens ran` → 🟡 escalate, never ✅ converged: open [`NO-LENS.md`](NO-LENS.md) beside this file' \
		'R17: not converged|in|**A review whose Axis-1 verdict is `blocked` with the reason `no lens ran` is no verdict for step 6'"'"'s converged condition: the PR is not converged, whatever its checks and threads say.**' \
		'R17: escalated at the top|in|Escalate it at the top of the report, directly below the ⚠️ block:' \
		'R17: recognised by the review'"'"'s own Verdict line|in|Its report'"'"'s Verdict line reads `BLOCKED — no lens ran; this is not a review`'; do
		_nl_name=${_nl_r%%|*}
		_nl_rest=${_nl_r#*|}
		_nl_where=${_nl_rest%%|*}
		_nl_want=${_nl_rest#*|}
		case $_nl_where in
		r3) _nl_text=$_nl_r3 ;;
		rs) _nl_text=$_nl_rs ;;
		n1) _nl_text=$_nl_n1 ;;
		r5) _nl_text=$_nl_r5 ;;
		rn) _nl_text=$_nl_rn ;;
		i6) _nl_text=$_nl_i6 ;;
		in) _nl_text=$_nl_in ;;
		esac
		case "$_nl_text" in *"$_nl_want"*) ;; *) printf '%s\n' "$_nl_name" ;; esac
	done
}
SKILLS_DIR="$ROOT/.agents/skills"
miss=$(nolens_missing "$SKILLS_DIR" | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "process/R15, process/R16, process/R17: an all-empty diff takes the single-reviewer pass, a review in which no lens ran records blocked and says so, and /pr-iterate escalates it, never converged" ||
	fail "the no-lens rules are missing: $miss — an empty review would stand in for a review"
# Baits: each rule cut from a copy of the four files is named.
mkdir -p "$SCRATCH/796/review-pr" "$SCRATCH/796/pr-iterate"
bait796() { # <rule name> <file under the skills dir> <sed script>
	for _b_f in review-pr/SKILL.md review-pr/NO-LENS.md pr-iterate/SKILL.md pr-iterate/NO-LENS.md; do
		cp "$SKILLS_DIR/$_b_f" "$SCRATCH/796/$_b_f" 2>/dev/null || : >"$SCRATCH/796/$_b_f"
	done
	bait_copy "$SKILLS_DIR/$2" "$SCRATCH/796/$2" "$3" && nolens_missing "$SCRATCH/796" | grep -qxF -- "$1"
}
for b in \
	'R15: §3 points at the branch|review-pr/SKILL.md|s/When every count is 0, open/When a count is 0, skip/' \
	'R15: §3 allows the pass on an all-empty diff|review-pr/SKILL.md|s/, or every lens slice was empty//' \
	'R15: the pass is one §3 allows|review-pr/NO-LENS.md|s/no lens agent can run when there is no slice to hand one/it runs even when the host could spawn the lens agents/' \
	'R17: the trigger is stated once|pr-iterate/NO-LENS.md|s#^Opened from `/pr-iterate` step 6#& when the review recorded Axis 1 `blocked` with the reason `no lens ran`#' \
	'R15: the pass runs over the whole diff|review-pr/NO-LENS.md|s/record no Axis-1 verdict before that pass returns/record the verdict at once/' \
	'R16: §5 points at the branch|review-pr/SKILL.md|s/records `blocked`, never `pass`/records `pass`/' \
	'R16: no lens and no pass is a block|review-pr/NO-LENS.md|s/the review records `blocked` and says that no lens ran/the review records `pass`/' \
	'R16: the verdict line recorded|review-pr/NO-LENS.md|s/outcome=blocked data.axis=1 data.lenses=0/outcome=pass data.axis=1 data.lenses=0/' \
	'R16: the Verdict line says so|review-pr/NO-LENS.md|s/BLOCKED — no lens ran; this is not a review/no findings/g' \
	'R16: some lenses ran is unchanged|review-pr/NO-LENS.md|s/some lenses ran is unchanged/one lens ran is blocked too/' \
	'R17: step 6 points at the branch|pr-iterate/SKILL.md|s/→ 🟡 escalate, never ✅ converged/→ ✅ converged/' \
	'R17: not converged|pr-iterate/NO-LENS.md|s/the PR is not converged/the PR may converge/' \
	'R17: escalated at the top|pr-iterate/NO-LENS.md|s/at the top of the report, directly below the ⚠️ block/at the end of the report/' \
	"R17: recognised by the review's own Verdict line|pr-iterate/NO-LENS.md|s/this is not a review/no review/g"; do
	_b_rest=${b#*|}
	bait796 "${b%%|*}" "${_b_rest%%|*}" "${_b_rest#*|}" && pass "bait: without '${b%%|*}' goes red" ||
		fail "bait: without '${b%%|*}' was not caught — or the bait planted nothing"
done
rm -rf "$SCRATCH/796"

# The fixture review: a diff no lens rule selects reaches §3's trigger. The
# slicer is run as the review runs it, on a real throwaway repository: every
# lens prints a count of 0 and behavior.diff still carries the change, so the
# branch NO-LENS.md opens on — the single-reviewer pass over behavior.diff —
# is the path this review takes. Two policies: a consumer's whose every rule
# is anchored to a directory the diff does not touch, over a new top-level
# directory; and the kit's shipped one, over a change only fixtures carry.
# nolens_counts <slicer stdout> — "all-empty" when every lens counts 0 and
# behavior counts at least 1; otherwise the counts as read.
nolens_counts() {
	printf '%s\n' "$1" | awk '
		$1 == "behavior" { b = $2; next }
		NF >= 2 { n++; if ($2 != 0) hit = 1 }
		END { if (n == 6 && !hit && b > 0) print "all-empty"; else print "lenses=" n " nonzero=" hit+0 " behavior=" b+0 }'
}
t_repo
t_write "$REPO" scripts/tool.sh 'echo one
'
t_write "$REPO" tests/tool.test.sh 'sh scripts/tool.sh
'
t_commit "$REPO" "chore: base" >/dev/null
git -C "$REPO" checkout -q -b feat/new-tool
t_write "$REPO" setup/new-tool/run.sh 'echo new
'
t_commit "$REPO" "feat: a new top-level directory" >/dev/null
cat >"$SCRATCH/796-policy.sh" <<'POLICY'
LENS_SLICE_RULES='security     ^scripts/
api-crud     ^scripts/
test-hygiene ^tests/
pattern      ^(scripts|tests)/
simplicity   ^(scripts|tests)/
reuse-dry    ^(scripts|tests)/'
POLICY
t_exec sh -c 'cd "$1" && LENS_SLICE_CONFIG="$2" sh "$3" main "$4"' _ "$REPO" "$SCRATCH/796-policy.sh" "$ROOT/scripts/lens-slice.sh" "$SCRATCH/796-out1"
got=$(nolens_counts "$T_OUT")
[ "$T_STATUS" = 0 ] && [ "$got" = all-empty ] && grep -qF 'b/setup/new-tool/run.sh' "$SCRATCH/796-out1/behavior.diff" &&
	pass "process/R15: a new top-level directory no rule selects slices to six empty lenses and a whole behavior.diff — the single-reviewer path" ||
	fail "process/R15: the new-top-level-directory fixture did not reach the single-reviewer path: exit $T_STATUS, $got"
FIXTURE_REPO=$REPO
t_repo
t_write "$REPO" scripts/tool.sh 'echo one
'
t_commit "$REPO" "chore: base" >/dev/null
git -C "$REPO" checkout -q -b test/fixtures-only
t_write "$REPO" setup/new-tool/fixtures/case.jsonl '{"a":1}
'
t_commit "$REPO" "test: fixtures only" >/dev/null
t_exec sh -c 'cd "$1" && sh "$2" main "$3"' _ "$REPO" "$ROOT/scripts/lens-slice.sh" "$SCRATCH/796-out2"
got=$(nolens_counts "$T_OUT")
[ "$T_STATUS" = 0 ] && [ "$got" = all-empty ] &&
	pass "process/R15: under the kit's shipped policy, a fixtures-only diff slices to six empty lenses — the single-reviewer path" ||
	fail "process/R15: the shipped-policy fixtures-only diff did not reach the single-reviewer path: exit $T_STATUS, $got"
# The bait: a diff one lens does select is not the all-empty case.
REPO=$FIXTURE_REPO
t_write "$REPO" scripts/tool.sh 'echo two
'
t_commit "$REPO" "feat: a lens's lane" >/dev/null
t_exec sh -c 'cd "$1" && LENS_SLICE_CONFIG="$2" sh "$3" main "$4"' _ "$REPO" "$SCRATCH/796-policy.sh" "$ROOT/scripts/lens-slice.sh" "$SCRATCH/796-out3"
[ "$(nolens_counts "$T_OUT")" != all-empty ] && pass "bait: a diff a lens selects is not read as all-empty" ||
	fail "bait: a diff a lens selects was read as all-empty — the fixture check cannot fail"
rm -rf "$SCRATCH/796-out1" "$SCRATCH/796-out2" "$SCRATCH/796-out3" "$SCRATCH/796-policy.sh"

# ---------------------------------------------------------------------------
banner "21. A blocked review's report has one order, in both sidecars, and they agree (#820)"
# ---------------------------------------------------------------------------
# The no-lens branch said where its lines go in words, and one of those words
# contradicted /pr-iterate's own Output format: "above the ⚠️ block, as its
# first line" against "the ⚠️ items come first, above everything else". Each
# sidecar now carries one skeleton of its report, and the order is read off
# the skeleton's lines, never off prose.
# nl_fence [<file>] — the first triple-backtick block in <file>, or in stdin
# with no file, fences dropped.
nl_fence() { awk '/^```/ { if (in_f) exit; in_f = 1; next } in_f' "${1:--}" 2>/dev/null; }
# nl_line <text> <needle> — the line number of the first line of <text>
# carrying <needle>, 0 when none does.
nl_line() { _nl_n=$(printf '%s\n' "$1" | grep -nF -- "$2" | head -n 1 | cut -d: -f1); echo "${_nl_n:-0}"; }
NL_VERDICT='BLOCKED — no lens ran; this is not a review'
NL_ESCALATION='🟡 Escalated: no lens ran — the review audited nothing on this head'
# order_missing <skills dir> <broker script> — the order rules broken, one
# name per line.
order_missing() {
	_o_rn=$(nl_fence "$1/review-pr/NO-LENS.md")
	_o_in=$(nl_fence "$1/pr-iterate/NO-LENS.md")
	_o_fmt=$(region '^## Output format' '^## ' "$1/pr-iterate/SKILL.md" | nl_fence)
	# The review's skeleton: heading, then the Verdict line as the next line
	# that says anything, then the rule and Axis 2's header, then ⚠️.
	_o_h=$(nl_line "$_o_rn" '### Review Summary')
	_o_v=$(nl_line "$_o_rn" "**Verdict:** $NL_VERDICT")
	_o_next=$(printf '%s\n' "$_o_rn" | awk -v h="$_o_h" 'NR > h && NF { print NR; exit }')
	_o_b=$(nl_line "$_o_rn" '### Behavior changes in this PR — confirm before merge')
	_o_w=$(nl_line "$_o_rn" '⚠️ UNSPECIFIED')
	[ "$_o_h" -gt 0 ] && [ "$_o_v" -gt 0 ] && [ "$_o_v" = "${_o_next:-0}" ] || echo 'review: the Verdict line opens the summary'
	[ "$_o_v" -gt 0 ] && [ "$_o_b" -gt "$_o_v" ] && [ "$_o_w" -gt "$_o_b" ] || echo 'review: the ⚠️ items stay below the rule'
	# /pr-iterate's skeleton: its format's own title and ⚠️ lines first, then
	# the escalation, then the status line, then the stop.
	_o_t=$(nl_line "$_o_in" 'PR #<N> — "<title>" — iteration <i>')
	_o_wi=$(nl_line "$_o_in" '⚠️ For you (behavior confirm-list, human-only):')
	_o_e=$(nl_line "$_o_in" "$NL_ESCALATION")
	_o_s=$(nl_line "$_o_in" "/review-pr:    $NL_VERDICT")
	_o_x=$(nl_line "$_o_in" 'Next: stop — escalation')
	[ "$_o_t" = 1 ] && [ "$_o_wi" -gt 1 ] && [ "$(nl_line "$_o_fmt" '⚠️ For you (behavior confirm-list, human-only):')" -gt 0 ] &&
		[ "$(printf '%s\n' "$_o_in" | sed -n "2,$((_o_wi - 1))p" | grep -c .)" = 0 ] || echo 'iterate: the ⚠️ block comes first, as the Output format says'
	[ "$_o_wi" -gt 0 ] && [ "$_o_e" -gt "$_o_wi" ] || echo 'iterate: the escalation follows the ⚠️ block'
	[ "$_o_e" -gt 0 ] && [ "$_o_s" -gt "$_o_e" ] && [ "$_o_x" -gt "$_o_s" ] || echo 'iterate: the BLOCKED status line, then the stop'
	# Said once: the escalation line stands once in the skeleton, and no
	# word in the sidecar puts it above the ⚠️ block.
	[ "$(printf '%s\n' "$_o_in" | grep -cF -- "$NL_ESCALATION")" = 1 ] &&
		! grep -qF 'above the ⚠️ block' "$1/pr-iterate/NO-LENS.md" || echo 'iterate: the order is said once'
	# The two agree: one Verdict text, the broker's too.
	grep -qF "NO_LENS_VERDICT='$NL_VERDICT'" "$2" || echo 'agree: the broker spells the Verdict alike'
}
miss=$(order_missing "$SKILLS_DIR" "$ROOT/scripts/forge-broker.kit.sh" | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "#820: a blocked review's report has one order — the review's Verdict line opens its summary, /pr-iterate's ⚠️ block precedes its escalation and its BLOCKED status line, one Verdict text throughout" ||
	fail "#820: a blocked review's report order is broken: $miss"
mkdir -p "$SCRATCH/820/review-pr" "$SCRATCH/820/pr-iterate"
bait820() { # <rule name> <file under the skills dir, or broker> <sed script>
	for _b_f in review-pr/NO-LENS.md pr-iterate/NO-LENS.md pr-iterate/SKILL.md; do
		cp "$SKILLS_DIR/$_b_f" "$SCRATCH/820/$_b_f" 2>/dev/null || : >"$SCRATCH/820/$_b_f"
	done
	cp "$ROOT/scripts/forge-broker.kit.sh" "$SCRATCH/820/broker.sh"
	if [ "$2" = broker ]; then _b_src="$ROOT/scripts/forge-broker.kit.sh" _b_dst="$SCRATCH/820/broker.sh"
	else _b_src="$SKILLS_DIR/$2" _b_dst="$SCRATCH/820/$2"; fi
	bait_copy "$_b_src" "$_b_dst" "$3" && order_missing "$SCRATCH/820" "$SCRATCH/820/broker.sh" | grep -qxF -- "$1"
}
for b in \
	'review: the Verdict line opens the summary|review-pr/NO-LENS.md|/^### Review Summary$/a\
Clean audits: none' \
	'review: the ⚠️ items stay below the rule|review-pr/NO-LENS.md|/^### Behavior changes in this PR/i\
⚠️ UNSPECIFIED  <surface>: above the rule' \
	'iterate: the ⚠️ block comes first, as the Output format says|pr-iterate/NO-LENS.md|/^PR #<N>/a\
🟡 Escalated: first' \
	'iterate: the ⚠️ block comes first, as the Output format says|pr-iterate/SKILL.md|s/⚠️ For you (behavior confirm-list, human-only):/For you:/' \
	'iterate: the escalation follows the ⚠️ block|pr-iterate/NO-LENS.md|/^⚠️ For you/,$d' \
	'iterate: the BLOCKED status line, then the stop|pr-iterate/NO-LENS.md|/\/review-pr:    BLOCKED/d' \
	'iterate: the order is said once|pr-iterate/NO-LENS.md|$a\
Escalate it above the ⚠️ block.' \
	'agree: the broker spells the Verdict alike|broker|s/this is not a review/not a review/'; do
	_b_rest=${b#*|}
	bait820 "${b%%|*}" "${_b_rest%%|*}" "${_b_rest#*|}" && pass "bait: without '${b%%|*}' goes red" ||
		fail "bait: without '${b%%|*}' was not caught — or the bait planted nothing"
done
rm -rf "$SCRATCH/820"

# ---------------------------------------------------------------------------
banner "22. A lens returns raise lines; its parent records them (#834)"
# ---------------------------------------------------------------------------
# 66 of 177 reviewer-tier stops ran on wider agent types, because a lens that
# records its own raises needs a shell. The ruling: a lens returns its raises
# in a declared shape — one `Raise: <id> <file:line>` line per finding, then
# `Raises: <count>` — and the coordinator that spawned it records them with
# LENS-RETURN.md's own fenced `lens_raise`, which is lifted and RUN here
# against the real trace script: ADR-0034's required keys hold, ids number in
# arrival order across lenses, a LOW is never posted, and a return off the
# shape is refused whole with nothing recorded.
LR="$ROOT/.agents/skills/review-pr/LENS-RETURN.md"
if [ -f "$LR" ]; then pass "LENS-RETURN.md sits beside the skill"; else fail "LENS-RETURN.md is missing beside /review-pr"; fi
t_lift_shape "$LR" '^Raise: ' "$SCRATCH/834-shape"
[ "$(cat "$SCRATCH/834-shape" 2>/dev/null)" = 'Raise: <its id, [CHML]-[0-9]+> <file:line>
Raises: <count>' ] && pass "the return shape is a fence: one raise line per finding, then the count" ||
	fail "LENS-RETURN.md declares no 'Raise: … / Raises: …' fence: $(cat "$SCRATCH/834-shape" 2>/dev/null)"
t_fence "$LR" holds 'lens_raise()' >"$SCRATCH/834-fn.sh"
[ -s "$SCRATCH/834-fn.sh" ] && pass "the parent-side emit is a fenced lens_raise()" || fail "LENS-RETURN.md has no fenced lens_raise()"
t_text_has "$(region '^### 3\. ' '^#### Agents 1–6 ' "$SKILL_ABS" | tr '\n' ' ')" '[`LENS-RETURN.md`](LENS-RETURN.md)' "§3 sends the coordinator to the lens return" "§3"
TD834="$SCRATCH/834-trace"
lr() { # <return file> <agent> <posted> — the fence, run from the kit root
	( cd "$ROOT" && . "$SCRATCH/834-fn.sh" && TRACE_DIR="$TD834" TRACE_QUIET=1 lens_raise 12 "$2" "$3" "$1" "$SCRATCH/834-tally" )
}
# A planted command (review of #844, M-3): were any line of a return run, the
# touch would leave its file behind, so the absence below can fail.
rm -f "$SCRATCH/834-planted"
printf '%s\n' '### Review' '**H-1** `a.sh:3` — x' 'Raise: H-1 scripts/a.sh:3' 'Raise: L-1 scripts/b.sh:9' \
	"Raise: H-2 bad\$(touch\${IFS}$SCRATCH/834-planted)path:1" 'Raises: 3' >"$SCRATCH/834-sec"
printf '%s\n' 'Raise: H-1 scripts/c.sh:4' 'Raises: 1' >"$SCRATCH/834-pat"
printf '%s\n' 'all clean' 'Raises: 0' >"$SCRATCH/834-clean"
rm -rf "$TD834" "$SCRATCH/834-tally"
map=$(lr "$SCRATCH/834-sec" security yes; lr "$SCRATCH/834-pat" pattern yes; lr "$SCRATCH/834-clean" simplicity yes)
[ "$map" = 'H-1 H-1
L-1 L-1
H-2 H-2
H-1 H-3' ] && pass "lens_raise prints each lens id beside its review id, numbered in arrival order across lenses" ||
	fail "lens_raise's renumbering: $map"
raises=$(cat "$TD834"/events/*.jsonl 2>/dev/null | grep -F '"kind":"finding.raise"')
[ "$(printf '%s\n' "$raises" | grep -c .)" = 4 ] && pass "one finding.raise per raise line, none for a clean return" ||
	fail "the raises recorded: $raises"
printf '%s\n' "$raises" | grep -F '"id":"H-3"' | grep -F '"severity":"high"' | grep -F '"agent":"pattern"' | grep -F '"where":"scripts/c.sh:4"' | grep -qF '"posted":"yes"' &&
	pass "a raise carries its review id, its severity from the letter, its lens, its place and the post answer" ||
	fail "the pattern lens's raise: $raises"
printf '%s\n' "$raises" | grep -F '"id":"L-1"' | grep -F '"severity":"low"' | grep -qF '"posted":"no"' &&
	pass "a LOW is recorded as not posted, whatever the path's answer" || fail "the LOW's raise: $raises"
printf '%s\n' "$raises" | grep -F '"id":"H-2"' | grep -qF '"where":"unsafe-path"' &&
	pass "a place off the plain set is recorded as unsafe-path, never typed" || fail "the unsafe place: $raises"
grep -qF '$(touch${IFS}' "$SCRATCH/834-sec" && [ ! -e "$SCRATCH/834-planted" ] &&
	pass "and nothing in a return was executed: the planted touch left no file" || fail "a return's text was executed, or no command was planted"
rm -f "$SCRATCH/834-planted"
for bad834 in \
	'no count|Raise: H-1 a.sh:1' \
	'count disagrees|Raise: H-1 a.sh:1\nRaises: 2' \
	'off-shape id|Raise: X-1 a.sh:1\nRaises: 1' \
	'trailing prose|Raise: H-1 a.sh:1\nRaises: 1\nthanks' \
	'stray raise in prose|Raise: H-1 a.sh:1\nprose\nRaise: H-2 a.sh:2\nRaises: 1' \
	'markdown-wrapped|- Raise: H-1 a.sh:1\nRaises: 1'; do
	printf '%b\n' "${bad834#*|}" >"$SCRATCH/834-bad"
	rm -rf "$TD834"
	_lr_err=$(lr "$SCRATCH/834-bad" security yes 2>&1 >/dev/null); _lr_rc=$?
	[ "$_lr_rc" = 2 ] && [ -z "$(cat "$TD834"/events/*.jsonl 2>/dev/null)" ] && case $_lr_err in *'a.sh'*) false ;; *) : ;; esac &&
		pass "a return with ${bad834%%|*} is refused whole: exit 2, nothing recorded, nothing of it printed" ||
		fail "a return with ${bad834%%|*}: exit $_lr_rc, stderr '$_lr_err', trace $(cat "$TD834"/events/*.jsonl 2>/dev/null)"
done
# The coordinator is never reviewer-tier on a wider type: /implement and
# /pr-iterate stamp the /review-pr spawn planner, and the lens prompt is told
# to return the fence.
LRF=$(tr '\n' ' ' <"$LR" | tr -s ' ')
t_text_has "$LRF" 'quote the fence above in its spawn prompt' "each lens prompt carries the shape" "LENS-RETURN.md"
t_text_has "$LRF" 'never through a shell heredoc' "the return reaches a file without a shell parsing it" "LENS-RETURN.md"
t_text_has "$LRF" 'one `reviewer`-type spawn' "the single-reviewer pass is a reviewer-type spawn where types are offered" "LENS-RETURN.md"
t_text_has "$(tr '\n' ' ' <"$ROOT/.agents/skills/implement/SKILL.md")" "this spawn is the review's coordinator and judges nothing: resolve it, stamp its \`Trace-Spawn:\` line and record its spawn \`planner\`" "/implement stamps its /review-pr coordinator planner where types are offered" "/implement"
grep -qF 'Trace-Spawn: tier=planner domain=none skill=pr-iterate' "$ROOT/.agents/skills/pr-iterate/SKILL.md" &&
	pass "/pr-iterate stamps its /review-pr spawn planner" || fail "/pr-iterate still stamps its /review-pr spawn reviewer"
grep -qF 'Trace-Spawn: tier=reviewer domain=none skill=pr-iterate' "$ROOT/.agents/skills/pr-iterate/SKILL.md" &&
	fail "/pr-iterate keeps a tier=reviewer stamp on a skill-running spawn" || pass "/pr-iterate has no tier=reviewer coordinator stamp"

# ---------------------------------------------------------------------------
banner "23. A lens is told the bump rule; a failed lens is never audited here (#846)"
# ---------------------------------------------------------------------------
# Lenses kept raising "a skill edit owes a version bump", rejected every time
# under ADR-0025, and §3 still let the coordinator audit a refused or failed
# lens itself, against ADR-0035 clause 2. Both sentences are read where the
# lens and the coordinator read them; each is proved by a bait.
# adr_rules_missing <skill file> — the rules the file has lost, one per line.
adr_rules_missing() {
	_ar_s4=$(region '^### 4\. ' '^### 5\. ' "$1" | tr '\n' ' ' | tr -s ' ')
	case "$_ar_s4" in *"**A version bump is owed only by a path on \`VERSION\`'s \`files:\` list**: a skill sits on its \`skills:\` list by name and owes none (the kit's ADR-0025)"*) ;; *) printf '%s\n' 'bump rule in §4' ;; esac
	_ar_s3=$(region '^### 3\. ' '^#### Agents 1–6 ' "$1" | tr '\n' ' ' | tr -s ' ')
	case "$_ar_s3" in *'A lens refused or failed is named under `Lenses not run:`, and the coordinator never audits its slice in its place'*) ;; *) printf '%s\n' 'failed lens not audited here' ;; esac
	case "$_ar_s3" in *'one lens audited here after its agent was refused or failed'*) printf '%s\n' 'no audit of a failed lens' ;; esac
	grep -qF 'marked "run in this context instead" by a context with no subagent tool>' "$1" ||
		printf '%s\n' 'summary mark needs no subagent tool'
}
# The dispatched worker reads no SKILL.md: it is told the same bump rule itself.
worker_bump_missing() { # <worker file>
	tr '\n' ' ' <"$1" | tr -s ' ' | grep -qF "A version bump is owed only by a path on \`VERSION\`'s \`files:\` list: a skill sits on its \`skills:\` list by name and owes none (the kit's ADR-0025)." ||
		printf '%s\n' 'worker bump rule'
}
[ -z "$(worker_bump_missing "$WORKER_ABS")" ] && pass "the dispatched worker is told a skill owes no bump (ADR-0025)" ||
	fail "$WORKER does not tell the worker a skill owes no bump — it raises what every triage rejects (#846)"
sed "s/a skill sits on its \`skills:\` list by name and owes$/a skill owes one, and/" "$WORKER_ABS" >"$SCRATCH/bait846w.md"
! cmp -s "$SCRATCH/bait846w.md" "$WORKER_ABS" && [ -n "$(worker_bump_missing "$SCRATCH/bait846w.md")" ] &&
	pass "bait: a worker contract without the bump rule goes red" ||
	fail "bait: a worker contract without the bump rule was not caught — or the bait planted nothing"
rm -f "$SCRATCH/bait846w.md"
miss=$(adr_rules_missing "$SKILL_ABS" | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "§4 tells every lens a skill owes no bump (ADR-0025), and §3 never audits a refused or failed lens in its place (ADR-0035)" ||
	fail "/review-pr's ADR-0025/ADR-0035 rules are missing: $miss — lenses raise findings every triage rejects (#846)"
for b in \
	'bump rule in §4|s/a skill sits on its `skills:` list by name and owes none/a skill owes one too/' \
	'failed lens not audited here|s/never audits its slice in its place/audits its slice/' \
	'no audit of a failed lens|s/^\(\*\*The seven sub-agents.*\)$/\1 The same holds for one lens audited here after its agent was refused or failed./' \
	'summary mark needs no subagent tool|s/by a context with no subagent tool>/when this session audited it itself>/'; do
	bait_gap adr_rules_missing "${b%%|*}" "${b#*|}" && pass "bait: /review-pr without '${b%%|*}' goes red" ||
		fail "bait: /review-pr without '${b%%|*}' was not caught — or the bait planted nothing"
done

# ---------------------------------------------------------------------------
banner "24. Every ⚠️ item carries a scope, and a missing one is outward (#873)"
# ---------------------------------------------------------------------------
# process/R53–R55, ADR-0038: Agent 7 writes `scope: inside` or `scope:
# outward` as the first words of an UNSPECIFIED item's arrow line, the two
# words the vocabulary's `scope` field declares and the two definitions
# that draw the line between them; every reader takes a missing or unknown
# scope as outward; the Axis-2 verdict counts the outward items beside the
# unspecified ones. The dispatched worker, whose tagged line is the only one
# its broker keeps, writes the scope right after the tag, in the same words.
SCOPE_WORDS=$(sh scripts/vocab.sh fields | sed -n 's/^scope: //p')
[ "$SCOPE_WORDS" = 'inside outward' ] && pass "the vocabulary's scope field holds inside and outward" ||
	fail "the vocabulary's scope field is '$SCOPE_WORDS', not 'inside outward' — the confirm-list's two words are undeclared"
# scope_rules_missing <file> — the scope rules a skill or contract has lost.
scope_rules_missing() {
	_sc=$(tr '\n' ' ' <"$1" | tr -s ' ')
	case "$_sc" in *"\`scope: inside\` when its effect stays inside the change — a name, a structure, internal error wording, a test's shape"*) ;; *) printf '%s\n' 'inside defined' ;; esac
	case "$_sc" in *"\`scope: outward\` when a user, a consumer or another skill sees or relies on it — an output format, a flag, an exit code, a rule an agent obeys"*) ;; *) printf '%s\n' 'outward defined' ;; esac
	case "$_sc" in *"an item with no scope, or a word the vocabulary's \`scope\` field does not hold, as \`outward\`"*) ;; *) printf '%s\n' 'outward default' ;; esac
	case "$_sc" in *'Classify, never resolve'*) ;; *) printf '%s\n' 'never resolves' ;; esac
}
# skill_scope_missing <skill file> — the rules above, the arrow line's first
# words in §5b's shape, and the verdict's outward count.
skill_scope_missing() {
	scope_rules_missing "$1"
	region '^### 5b\. ' '^Rules: ' "$1" | grep -A1 '^⚠️ UNSPECIFIED ' | grep -qE '^ +→ scope: <inside\|outward> ' ||
		printf '%s\n' 'arrow line opens with scope'
	grep -qF 'data.unspecified=<count> data.outward=<count>' "$1" || printf '%s\n' 'verdict counts outward'
}
worker_scope_missing() {
	scope_rules_missing "$1"
	grep -qF '⚠️ UNSPECIFIED  scope: <inside|outward> — <observable change nobody asked for>' "$1" ||
		printf '%s\n' 'tagged line opens with scope'
}
miss=$(skill_scope_missing "$SKILL_ABS" | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "process/R53–R55: Agent 7 scopes every ⚠️ item on its arrow line, a missing scope is outward, and the verdict counts data.outward" ||
	fail "process/R53–R55: /review-pr's scope rules are missing: $miss"
miss=$(worker_scope_missing "$WORKER_ABS" | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "process/R53–R54: the dispatched worker scopes every ⚠️ item right after its tag, in the skill's words" ||
	fail "process/R53–R54: $WORKER's scope rules are missing: $miss"
for b in \
	'inside defined|s/internal error wording, a test.s shape/internal error wording/' \
	'outward defined|s/an exit code, a rule an agent obeys/an exit code/' \
	'outward default|s/as `outward`\*\*/as `inside`**/' \
	'never resolves|s/Classify, never resolve/Classify, and resolve where you can/' \
	'arrow line opens with scope|s/^\( *→ \)scope: <inside|outward> — no spec reference found/\1no spec reference found/' \
	'verdict counts outward|s/ data.outward=<count>//'; do
	bait_gap skill_scope_missing "${b%%|*}" "${b#*|}" && pass "bait: /review-pr without '${b%%|*}' goes red" ||
		fail "bait: /review-pr without '${b%%|*}' was not caught — or the bait planted nothing"
done
bait_copy "$WORKER_ABS" "$SCRATCH/bait873w.md" 's/UNSPECIFIED  scope: <inside|outward> — /UNSPECIFIED  /' &&
	worker_scope_missing "$SCRATCH/bait873w.md" | grep -qxF 'tagged line opens with scope' &&
	pass "bait: a worker contract whose ⚠️ line carries no scope goes red" ||
	fail "bait: a worker contract whose ⚠️ line carries no scope was not caught — or the bait planted nothing"
rm -f "$SCRATCH/bait873w.md"

# ---------------------------------------------------------------------------
banner "25. The review lists a check table's gaps, the loop keeps the table (#871)"
# ---------------------------------------------------------------------------
# process/R48 process/R49 process/R50 process/R51, ADR-0037 clause 9: no covered id is left without a passing
# row in silence. The review reads the table through scripts/check-table.sh
# and no other way; Agent 7 turns each line it prints into a ❌ MISSING item;
# /pr-iterate rewrites the rows after a push and reads them back the same way.
RCT_ABS="$ROOT/.agents/skills/review-pr/CHECK-TABLE.md"
ICT_ABS="$ROOT/.agents/skills/pr-iterate/CHECK-TABLE.md"
for f in "$RCT_ABS" "$ICT_ABS"; do
	[ -f "$f" ] && pass "${f#"$ROOT"/} exists" || fail "${f#"$ROOT"/} is missing"
done
# The listing rule, one sentence, held word for word in Agent 7's section and
# in the dispatched worker's contract (whitespace collapsed, as in both).
CT_RULE=$(printf '%s' "list each \`<word>: <id>\` line it holds as \`❌ MISSING      <id> — <word>\`, and on its \`exit: 2\` or \`exit: 3\` every id on the ticket's \`Covers:\` line, the word \`refused\` or \`missing-row\`; an id it lists is listed once, with the reader's word." | tr -s ' ')
CT_ONLY='No step reads the check table except through the reader'
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
# review_ct_missing <review-pr SKILL.md> <its CHECK-TABLE.md> — rules lost.
review_ct_missing() {
	_a7=$(region '^#### Agent 7' '^\*\*Commit separation' "$1" | tr '\n' ' ' | tr -s ' ')
	has "$_a7" "4. The check-table reader's output, where the ticket carries a \`Covers:\` line — [\`CHECK-TABLE.md\`](CHECK-TABLE.md)" || printf '%s\n' 'agent 7 input'
	has "$_a7" "$CT_RULE" || printf '%s\n' 'agent 7 rule'
	_rc=$(unwrap "$2")
	has "$_rc" 'gh pr view <N> --json body -q .body >"$d/pr-body"' && has "$_rc" 'gh issue view <T> --json body -q .body >"$d/ticket-body"' || printf '%s\n' 'fetched bodies'
	has "$_rc" 'sh scripts/check-table.sh "$d/pr-body" "$d/ticket-body" >"$d/check-table" 2>/dev/null; echo "exit: $?" >>"$d/check-table"' || printf '%s\n' 'coordinator runs reader'
	has "$_rc" "hand \`\$d/check-table\` to Agent 7 as a file, beside \`scripts/behavior-delta.sh\`'s output" || printf '%s\n' 'handed as a file'
	has "$_rc" "$CT_ONLY" || printf '%s\n' 'only through the reader'
	has "$_rc" "appends \`\$d/check-table\`, under a \`Check-table reader:\` line, to the spec file" || printf '%s\n' 'dispatched appends'
	for _w in missing-row extra-row tier-differs fail skipped; do
		has "$_rc" "\`$_w\`" || printf '%s\n' "word $_w"
	done
}
worker_ct_missing() {
	_wc=$(unwrap "$1")
	has "$_wc" "$CT_RULE" || printf '%s\n' 'worker rule'
	has "$_wc" "ends with a \`Check-table reader:\` block" || printf '%s\n' 'worker block'
}
# iter_ct_missing <pr-iterate SKILL.md> <its CHECK-TABLE.md> — rules lost.
iter_ct_missing() {
	_s4=$(region '^### 4 — Act' '^### 5 — ' "$1" | tr '\n' ' ' | tr -s ' ')
	has "$_s4" "rewrite its rows at the new head — [\`CHECK-TABLE.md\`](CHECK-TABLE.md)" || printf '%s\n' 'rewrite at push'
	region '^### 6 — ' '^## Output format' "$1" |
		grep -qF -- "- The check-table reader prints \`fail:\`, \`missing-row:\`, \`extra-row:\` or \`tier-differs:\` → never ✅ converged" ||
		printf '%s\n' 'not converged'
	awk '/^⚠️ For you/ { f = NR } /^Manual checks awaiting you: / { m = NR } /^Status:$/ { s = NR }
		END { exit !(f && m && s && f < m && m < s) }' "$1" || printf '%s\n' 'manual checks at top'
	_ic=$(unwrap "$2")
	has "$_ic" "While the reader prints a \`fail:\`, \`missing-row:\`, \`extra-row:\` or \`tier-differs:\` line, the PR is not converged" || printf '%s\n' 'four blocking words'
	has "$_ic" "\`skipped:\` ids are manual checks awaiting the operator, listed at the top of the report" || printf '%s\n' 'skipped is manual'
	has "$_ic" "the result from this iteration's full-suite run at the new head, the pin \`<path>::<test>@<the new head's sha>\`" || printf '%s\n' 'rewrite from suite run'
	has "$_ic" "$CT_ONLY" || printf '%s\n' 'only through the reader'
}
miss=$(review_ct_missing "$SKILL_ABS" "$RCT_ABS" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "process/R48: the coordinator runs the reader on the two fetched bodies, hands Agent 7 its output as a file, and Agent 7 lists each id as ❌ MISSING with the reader's word" ||
	fail "process/R48: /review-pr's check-table rules are missing: $miss"
miss=$(worker_ct_missing "$WORKER_ABS" | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "process/R48: the dispatched worker lists the reader's ids as ❌ MISSING in Agent 7's words" ||
	fail "process/R48: $WORKER's check-table rules are missing: $miss"
miss=$(iter_ct_missing "$ITER_ABS" "$ICT_ABS" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "process/R49 process/R50 process/R51: /pr-iterate rewrites the rows at the new head, never converges on a blocking word, and lists the skipped ids at the top" ||
	fail "process/R49 process/R50 process/R51: /pr-iterate's check-table rules are missing: $miss"
# ct_bait <checker> <rule> <file to edit: 1|2> <sed> <file 1> <file 2>
ct_bait() {
	if [ "$3" = 1 ]; then
		bait_copy "$5" "$SCRATCH/ct-bait.md" "$4" && "$1" "$SCRATCH/ct-bait.md" "$6"
	else
		bait_copy "$6" "$SCRATCH/ct-bait.md" "$4" && "$1" "$5" "$SCRATCH/ct-bait.md"
	fi 2>/dev/null | grep -qxF -- "$2"
}
for b in \
	'agent 7 input|1|s/^4\. The check-table reader.s output.*$/4. Nothing else./' \
	'agent 7 rule|1|s/and on its `exit: 2` or `exit: 3` every id/and on its `exit: 2` every id/' \
	'fetched bodies|2|s/gh issue view <T>/gh issue view <N>/' \
	'coordinator runs reader|2|s/; echo "exit: \$?" >>"\$d\/check-table"//' \
	'handed as a file|2|s/to Agent 7 as a file/to Agent 7 in its prompt/' \
	'only through the reader|2|s/No step reads the check table except through the reader/Read the check table/' \
	'dispatched appends|2|s/under a `Check-table reader:` line/under the spec/' \
	'word missing-row|2|s/`missing-row`/`missing`/g' \
	'word extra-row|2|s/`extra-row`/`extra`/g' \
	'word tier-differs|2|s/`tier-differs`/`tier`/g' \
	'word fail|2|s/`fail`/`failed`/g' \
	'word skipped|2|s/`skipped`/`skip`/g'; do
	r=${b%%|*}; rest=${b#*|}
	ct_bait review_ct_missing "$r" "${rest%%|*}" "${rest#*|}" "$SKILL_ABS" "$RCT_ABS" && pass "bait: /review-pr without '$r' goes red" ||
		fail "bait: /review-pr without '$r' was not caught — or the bait planted nothing"
done
bait_copy "$WORKER_ABS" "$SCRATCH/ct-bait-w.md" 's/the word `refused` or `missing-row`/the word `missing-row`/' &&
	worker_ct_missing "$SCRATCH/ct-bait-w.md" | grep -qxF 'worker rule' &&
	pass "bait: a worker contract that drops exit 2's word goes red" ||
	fail "bait: a worker contract that drops exit 2's word was not caught — or the bait planted nothing"
for b in \
	'rewrite at push|1|s/rewrite its rows at the new head/rewrite its rows/' \
	'not converged|1|s/ or `tier-differs:` → never ✅ converged/ → never ✅ converged/' \
	'manual checks at top|1|/^Manual checks awaiting you: /d' \
	'four blocking words|2|s/`extra-row:` or `tier-differs:` line, the PR/`extra-row:`, `tier-differs:` or `skipped:` line, the PR/' \
	'skipped is manual|2|s/listed at the top of the report/listed under Next/' \
	'rewrite from suite run|2|s/at the new head, the pin/at the base, the pin/' \
	'only through the reader|2|s/No step reads the check table except through the reader/Read the check table/'; do
	r=${b%%|*}; rest=${b#*|}
	ct_bait iter_ct_missing "$r" "${rest%%|*}" "${rest#*|}" "$ITER_ABS" "$ICT_ABS" && pass "bait: /pr-iterate without '$r' goes red" ||
		fail "bait: /pr-iterate without '$r' was not caught — or the bait planted nothing"
done
bait_copy "$WORKER_ABS" "$SCRATCH/ct-bait-w.md" 's/ends with a `Check-table reader:` block/ends with the reader output/' &&
	worker_ct_missing "$SCRATCH/ct-bait-w.md" | grep -qxF 'worker block' &&
	pass "bait: a worker contract that names no Check-table reader: block goes red" ||
	fail "bait: a worker contract that names no Check-table reader: block was not caught — or the bait planted nothing"
rm -f "$SCRATCH/ct-bait.md" "$SCRATCH/ct-bait-w.md"

# Every word the reader prints on exit 1 is one the review lists: one fixture
# that draws all five out of the real reader.
CT_HEAD='| Requirement | Test tier | Result | Evidence |'
CT_SEP='| --- | --- | --- | --- |'
ct_body() {
	{
		printf '## What\n\n<!-- check-table -->\n%s\n%s\n' "$CT_HEAD" "$CT_SEP"
		for r; do printf '%s\n' "$r"; done
		printf '\nprose\n\n<!-- explain-diff-appendix -->\n\nnarrative\n'
	} >"$SCRATCH/ct-pr"
}
printf 'Covers: process/R1, process/R2, process/R3, process/R4\nTest-tier: process/R2 unit\nTest-tier: process/R4 manual\n' >"$SCRATCH/ct-ticket"
ct_body '| process/R2 | suite | pass | tests/a.test.sh::process/R2@3f9c2e1 |' \
	'| process/R3 | unit | fail | tests/a.test.sh::process/R3@3f9c2e1 |' \
	'| process/R3 | unit | pass | tests/a.test.sh::process/R3@3f9c2e1 |' \
	'| process/R4 | manual | skipped | - |'
words=$(sh scripts/check-table.sh "$SCRATCH/ct-pr" "$SCRATCH/ct-ticket" 2>/dev/null | sed 's/:.*//' | sort -u | tr '\n' ' ')
[ "$words" = 'extra-row fail missing-row skipped tier-differs ' ] &&
	pass "process/R48: the reader's exit-1 words are the five the review lists" ||
	fail "process/R48: the reader printed the words '$words', not the five the review lists"

# UC3, walked: a fail and a skipped id give two ❌ MISSING items; /pr-iterate's
# own rewrite, run as written at a new head, leaves only the skipped id.
printf 'Covers: process/R46, process/R47\nTest-tier: process/R46 suite\nTest-tier: process/R47 manual\n' >"$SCRATCH/ct-ticket"
ct_body '| process/R46 | suite | fail | tests/a.test.sh::process/R46@3f9c2e1 |' '| process/R47 | manual | skipped | - |'
out=$(sh scripts/check-table.sh "$SCRATCH/ct-pr" "$SCRATCH/ct-ticket" 2>/dev/null)
items=$(printf '%s\n' "$out" | sed -n 's/^\([a-z-]*\): \(.*\)$/❌ MISSING      \2 — \1/p')
[ "$items" = "❌ MISSING      process/R46 — fail
❌ MISSING      process/R47 — skipped" ] &&
	pass "process/R48 (UC3 1–2): fail: and skipped: give two ❌ MISSING items, each naming its id and the reader's word" ||
	fail "process/R48 (UC3 1–2): the reader's lines gave the items '$items'"
# The rewrite, lifted from the pr-iterate branch's fenced block and run as the
# skill wrote it, the forge stubbed: `gh pr view` prints the fixture body (or
# fails, when FETCH=fail), `gh pr edit` copies the body file it is handed to
# $scratch/edited — the body the PR would carry.
NEW=0123456789abcdef0123456789abcdef01234567
# uc3_rewrite <rewrite-block source> <rows> [fail] — run the block on ct-pr;
# exit 0 when it edited the body (even to nothing), the edited body in $SCRATCH/uc3/edited.
uc3_rewrite() {
	rm -rf "$SCRATCH/uc3" && mkdir -p "$SCRATCH/uc3" || return 2
	printf '%s' "$2" >"$SCRATCH/uc3/rows"
	{
		printf '%s\n' 'gh() { case "$2" in view) [ "${FETCH:-}" = fail ] && return 1; cat "$CT_PR" ;; edit) cp "$5" "$scratch/edited" ;; esac; }'
		awk '/^```sh$/ { f = 1; b = ""; next } f && /^```$/ { f = 0; if (b ~ /awk /) print b; next } f { b = b $0 "\n" }' "$1"
	} >"$SCRATCH/uc3/rewrite.sh"
	(cd "$SCRATCH/uc3" && CT_PR="$SCRATCH/ct-pr" FETCH="${3:-}" PR=950 scratch="$SCRATCH/uc3" sh ./rewrite.sh) >/dev/null 2>&1
	[ -f "$SCRATCH/uc3/edited" ]
}
ROWS=$(printf 'process/R46 pass tests/a.test.sh::process/R46@%s\nprocess/R47 pass tests/a.test.sh::process/R47@%s\n' "$NEW" "$NEW")
if uc3_rewrite "$ICT_ABS" "$ROWS"; then
	t_exec sh scripts/check-table.sh "$SCRATCH/uc3/edited" "$SCRATCH/ct-ticket"
	[ "$T_STATUS" = 1 ] && [ "$T_OUT" = 'skipped: process/R47' ] &&
		pass "process/R49 process/R50 process/R51 (UC3 3–4): after the rewrite only skipped: process/R47 remains — a manual check, the row left as the operator's" ||
		fail "process/R49 process/R50 process/R51 (UC3 3–4): after the rewrite the reader exited $T_STATUS printing '$T_OUT'"
	grep -qF "| process/R46 | suite | pass | tests/a.test.sh::process/R46@$NEW |" "$SCRATCH/uc3/edited" &&
		pass "process/R49 (UC3 3): the fixed row reads pass, pinned to the new head" ||
		fail "process/R49 (UC3 3): the rewritten body has no pass row for process/R46 pinned to the new head"
else
	fail "process/R49 (UC3 3): the pr-iterate branch's rewrite block, run as written, edited no body"
fi
# The rewrite never writes a body over with less than it held: an empty rows
# file, or a fetch that failed, edits nothing (PR #894 review, H-1 and M-1).
! uc3_rewrite "$ICT_ABS" '' && pass "process/R49: an empty rows file edits no body" ||
	fail "process/R49: an empty rows file edited the PR body — it would be written over"
! uc3_rewrite "$ICT_ABS" "$ROWS" fail && pass "process/R49: a fetch that failed edits no body" ||
	fail "process/R49: a failed fetch still edited the PR body — it would be written over"
# Bait: the pre-review block — NR == FNR, nothing chained — empties the body on
# an empty rows file, and the check above must see it.
bait_copy "$ICT_ABS" "$SCRATCH/ct-bait-i.md" 's/FILENAME == ARGV\[1\]/NR == FNR/; /^	\[ -s "\$scratch\/pr-body" \] && \[ -s "\$scratch\/rows" \] &&$/d; /^	\[ -s "\$scratch\/pr-body.new" \] &&$/d' &&
	uc3_rewrite "$SCRATCH/ct-bait-i.md" '' && pass "bait: a rewrite block that does not guard an empty rows file goes red" ||
	fail "bait: a rewrite block with no guard for an empty rows file was not caught — or the bait planted nothing"
rm -f "$SCRATCH/ct-bait-i.md"
rm -rf "$SCRATCH/uc3" "$SCRATCH/ct-pr" "$SCRATCH/ct-ticket"

# ---------------------------------------------------------------------------
banner "26. The loop decides inside items into a decision log, and holds outward ones (#874)"
# ---------------------------------------------------------------------------
# process/R56 process/R57 process/R58 process/R59 process/R60, ADR-0038
# clause 4: /pr-iterate decides a `scope: inside` ⚠️ item and logs it as a
# `D-<n>` row of the PR body's decision log, recorded as one finding.triage;
# an outward item it never decides, amends or logs, and holds at the top of
# its report; a row a later review marks outward is struck, its id kept.
# No skill reads the log's or the check table's prose back.
DL_ONLY="No skill reads a decision log's or a check table's prose back as an instruction: the decision log is read only for its \`D-<n>\` ids, the check table only through the check-table reader"
DL_HEAD='| Decision | Surface | What was decided | Why |'
# iter_dl_missing <pr-iterate SKILL.md> <its CHECK-TABLE.md> — rules lost.
iter_dl_missing() {
	_hr=$(region '^## Hard rules' '^## Prerequisites' "$1" | tr '\n' ' ' | tr -s ' ')
	has "$_hr" "4. **NEVER** act on an outward ⚠️ UNSPECIFIED item" || printf '%s\n' 'hard rule narrowed'
	has "$_hr" "A \`scope: inside\` item you decide and log — [\`CHECK-TABLE.md\`](CHECK-TABLE.md)" || printf '%s\n' 'inside routed'
	has "$_hr" 'NEVER** act on ⚠️ UNSPECIFIED items' && printf '%s\n' 'hard rule still whole'
	region '^## Output format' '^## Cross-references' "$1" | grep -qF '<verbatim outward ⚠️ UNSPECIFIED / 🔀 MIXED COMMIT lines' ||
		printf '%s\n' 'report holds outward'
	_dc=$(unwrap "$2")
	has "$_dc" "a \`<!-- decision-log -->\` marker line above the explain-diff marker, then the header \`$DL_HEAD\`" || printf '%s\n' 'marker and header'
	has "$_dc" "\`D-<n>\`, numbered from 1 and never renumbered" || printf '%s\n' 'never renumbered'
	has "$_dc" 'The log is created by the first row written' || printf '%s\n' 'created by first row'
	printf '%s\n' "$_dc" | grep -qF "kind=finding.triage subject=pr:#<N> outcome=answered|accepted data.source=local data.id='A2-<k>' data.scope=inside data.decision='<D-n>'" ||
		printf '%s\n' 'triage fields'
	has "$_dc" 'neither decide, amend nor log it' || printf '%s\n' 'outward not decided'
	has "$_dc" 'List it verbatim at the top of the report' || printf '%s\n' 'outward at top'
	has "$_dc" 'strike its row, keeping its id, and hold the item' || printf '%s\n' 'strike keeps id'
	has "$_dc" "$DL_ONLY" || printf '%s\n' 'no read-back'
}
# review_dl_missing <review-pr SKILL.md> — the no-read-back line and the
# two blocks Agent 7 skips when it reads the PR description.
review_dl_missing() {
	_rv=$(unwrap "$1")
	has "$_rv" "$DL_ONLY" || printf '%s\n' 'no read-back'
	has "$_rv" "skip its \`<!-- check-table -->\` and \`<!-- decision-log -->\` blocks" || printf '%s\n' 'agent 7 skips blocks'
}
miss=$(iter_dl_missing "$ITER_ABS" "$ICT_ABS" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "process/R56–R60: /pr-iterate decides and logs inside items as never-renumbered D-<n> rows, records each as one triage, holds outward ones at the top, strikes a re-scoped row keeping its id, and reads the log back for ids only" ||
	fail "process/R56–R60: /pr-iterate's decision-log rules are missing: $miss"
miss=$(review_dl_missing "$SKILL_ABS" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
[ -z "$miss" ] && pass "process/R60: /review-pr reads neither block's prose back, and Agent 7 skips both" ||
	fail "process/R60: /review-pr's no-read-back rules are missing: $miss"
for b in \
	'hard rule narrowed|1|s/act on an outward ⚠️ UNSPECIFIED item/act on an ⚠️ UNSPECIFIED item/' \
	'inside routed|1|s/A `scope: inside` item you decide and log/A `scope: inside` item is the operator.s too/' \
	'report holds outward|1|s/<verbatim outward ⚠️ UNSPECIFIED/<verbatim ⚠️ UNSPECIFIED/' \
	'marker and header|2|s/| What was decided | Why |/| Decision | Why |/' \
	'never renumbered|2|s/numbered from 1 and never renumbered/numbered from 1/' \
	'created by first row|2|s/The log is created by the first row written/The log is created at the start/' \
	'triage fields|2|s/ data.scope=inside data.decision=/ data.decision=/' \
	'outward not decided|2|s/neither decide, amend nor log it/decide it as you would an inside one/' \
	'outward at top|2|s/List it verbatim at the top of the report/List it under Next/' \
	'strike keeps id|2|s/strike its row, keeping its id,/delete its row/' \
	'no read-back|2|s/the decision log is read only for its `D-<n>` ids/the decision log is read whole/'; do
	r=${b%%|*}; rest=${b#*|}
	ct_bait iter_dl_missing "$r" "${rest%%|*}" "${rest#*|}" "$ITER_ABS" "$ICT_ABS" && pass "bait: /pr-iterate without '$r' goes red" ||
		fail "bait: /pr-iterate without '$r' was not caught — or the bait planted nothing"
done
for b in \
	'no read-back|s/the check table only through the check-table reader/the check table as written/' \
	'agent 7 skips blocks|s/skip its `<!-- check-table -->` and `<!-- decision-log -->` blocks/read its tables too/'; do
	bait_gap review_dl_missing "${b%%|*}" "${b#*|}" && pass "bait: /review-pr without '${b%%|*}' goes red" ||
		fail "bait: /review-pr without '${b%%|*}' was not caught — or the bait planted nothing"
done
rm -f "$SCRATCH/ct-bait.md"
# The shipped PR template carries the Decision log section, and the kit's own
# copy is the same file: the heading the log is written under, and no marker
# line — the log is created by the first row written.
for tpl in templates/docs/PULL_REQUEST_TEMPLATE.md .github/PULL_REQUEST_TEMPLATE.md; do
	assert_file_has "$tpl" "## Decision log" "process/R56: $tpl carries the Decision log section"
	grep -qx '<!-- decision-log -->' "$tpl" && fail "process/R56: $tpl carries the marker line — an empty log the first row did not create" ||
		pass "process/R56: $tpl carries no marker line until a row is written"
done
assert_file_has docs/domain-glossary.md "- **Decision log** —" "the glossary defines Decision log"

# UC5, walked on the branch's own script, lifted from the pr-iterate branch's
# fenced block and run as written: the rename marked inside becomes row D-1 on
# the template's body, the log created under its heading and above the
# explain-diff marker, the check table still read whole; the triage line,
# run as written, records one event naming D-1; a second row is D-2; a later
# outward mark on the rename's surface strikes D-1, its id kept, and the next
# row is still D-3.
DLD="$SCRATCH/dl" && rm -rf "$DLD" && mkdir -p "$DLD"
awk '/^```sh$/ { f = 1; b = ""; next } f && /^```$/ { f = 0; if (b ~ /dl_write\(\) \{/) print b; next } f { b = b $0 "\n" }' "$ICT_ABS" >"$DLD/fns.sh"
{ cat templates/docs/PULL_REQUEST_TEMPLATE.md; printf '\n<!-- explain-diff-appendix -->\n\nnarrative\n'; } >"$DLD/body"
printf 'scripts/stamp.sh\nkept: the helper lift is now lift_lines\nthe new name says what it lifts\n' >"$DLD/row1"
printf 'tests/a.test.sh\namended: the fixture is one file\none file reads in one place\n' >"$DLD/row2"
printf 'scripts/stamp.sh\n' >"$DLD/surface"
if [ -s "$DLD/fns.sh" ] && . "$DLD/fns.sh"; then
	id=$(dl_next "$DLD/body")
	dl_write "$DLD/body" "$DLD/row1" >"$DLD/body1"
	[ "$id" = D-1 ] && grep -qxF '| D-1 | scripts/stamp.sh | kept: the helper lift is now lift_lines | the new name says what it lifts |' "$DLD/body1" &&
		pass "process/R56 (UC5 2): the rename marked inside ends as row D-1, surface, decision and why" ||
		fail "process/R56 (UC5 2): the first row was '$id', or its row is not in the body"
	awk -v h="$DL_HEAD" '/^## Decision log$/ { d = NR } /^<!-- decision-log -->$/ { m = NR } $0 == h { hd = NR }
		/^<!-- explain-diff-appendix -->$/ { x = NR } END { exit !(d && d < m && hd == m + 1 && m < x) }' "$DLD/body1" &&
		pass "process/R56: the first row created the log — marker, then header — under the Decision log heading, above the explain-diff marker" ||
		fail "process/R56: the log was not created under its heading, marker then header, above the explain-diff marker"
	printf 'Covers: none (prefactor)\n' >"$DLD/ticket"
	t_exec sh scripts/check-table.sh "$DLD/body1" "$DLD/ticket"
	[ "$T_STATUS" = 0 ] && pass "process/R56: the check table still reads through its reader beside the log" ||
		fail "process/R56: with the log written the check-table reader exited $T_STATUS printing '$T_OUT'"
	tl=$(unwrap "$ICT_ABS" | grep -o "sh scripts/trace.sh emit kind=finding.triage subject=pr:#<N> outcome=answered|accepted[^|]*|| :" | head -1 |
		sed -e 's/pr:#<N>/pr:#960/' -e 's/answered|accepted/answered/' -e 's/A2-<k>/A2-1/' -e "s/'<D-n>'/D-1/" -e "s/reason='[^']*'/reason='kept'/")
	TR="$DLD/trace" && mkdir -p "$TR"
	if [ -n "$tl" ] && (TRACE_DIR="$TR" TRACE_QUIET=1 sh -c "$tl") >/dev/null 2>&1; then
		n=$(find "$TR" -name "*.jsonl" -exec cat {} + 2>/dev/null | grep '"kind":"finding.triage"' | grep -c '"decision":"D-1"')
		s=$(find "$TR" -name "*.jsonl" -exec cat {} + 2>/dev/null | grep '"decision":"D-1"' | grep -c '"scope":"inside"')
		[ "$n" = 1 ] && [ "$s" = 1 ] && pass "process/R57 (UC5 2): the triage line, run as written, records one finding.triage naming D-1, scope inside" ||
			fail "process/R57 (UC5 2): the triage line recorded $n events naming D-1 ($s with scope inside)"
	else
		fail "process/R57: the pr-iterate branch's triage line did not run as written: '$tl'"
	fi
	dl_write "$DLD/body1" "$DLD/row2" >"$DLD/body2"
	[ "$(dl_next "$DLD/body1")" = D-2 ] && grep -qF '| D-2 | tests/a.test.sh |' "$DLD/body2" && [ "$(grep -c '^<!-- decision-log -->$' "$DLD/body2")" = 1 ] &&
		pass "process/R56: the second row joins the same log as D-2" ||
		fail "process/R56: the second row did not join the log as D-2"
	dl_ids_for "$DLD/body2" "$DLD/surface" >"$DLD/ids"
	[ "$(cat "$DLD/ids")" = D-1 ] && pass "process/R59 (UC5 2a): the outward item's surface finds D-1, and the reader prints its id only" ||
		fail "process/R59 (UC5 2a): the surface found '$(cat "$DLD/ids")', not D-1"
	dl_strike "$DLD/body2" "$DLD/ids" >"$DLD/body3"
	grep -qxF '| D-1 | ~~scripts/stamp.sh~~ | ~~kept: the helper lift is now lift_lines~~ | ~~the new name says what it lifts~~ |' "$DLD/body3" &&
		grep -qF '| D-2 | tests/a.test.sh |' "$DLD/body3" &&
		pass "process/R59 (UC5 2a): D-1 is struck, its id kept, and D-2 is untouched" ||
		fail "process/R59 (UC5 2a): the strike did not keep D-1's id or touched D-2"
	[ "$(dl_next "$DLD/body3")" = D-3 ] && [ -z "$(dl_ids_for "$DLD/body3" "$DLD/surface")" ] &&
		pass "process/R56 process/R59: a struck row keeps its number — the next row is D-3 — and is found no second time" ||
		fail "process/R56 process/R59: after the strike the next id was '$(dl_next "$DLD/body3")'"
	printf 'a|b.sh\nkept: x\ny\n' >"$DLD/row3"; printf 'a|b.sh\n' >"$DLD/surface3"
	dl_write "$DLD/body3" "$DLD/row3" >"$DLD/body4"
	[ "$(dl_ids_for "$DLD/body4" "$DLD/surface3")" = D-3 ] && pass "process/R59: a surface holding '|' finds the row dl_write wrote for it" ||
		fail "process/R59: a surface holding '|' did not find its own row — the strike would silently not happen"
	printf 'two\nlines\n' >"$DLD/short"
	! dl_write "$DLD/body1" "$DLD/short" >"$DLD/body-short" 2>/dev/null && pass "process/R56: a row with a cell missing writes nothing" ||
		fail "process/R56: a row with a cell missing was written"
else
	fail "process/R56: the pr-iterate branch holds no runnable dl_write block"
fi
rm -rf "$DLD"

t_done "/review-pr output contract"
