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
sed "s/^VOCAB_OPEN=.*/VOCAB_OPEN='domain severity'/" "$POLICY" >"$SCRATCH/opened.config.sh"
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
	printf '%s\n' "$_sr_rows" | grep -F -- '- `single-reviewer` — ' | grep -qF 'never a spawn' || printf '%s\n' 'row: never a spawn'
	_sr_s3=$(region '^### 3\. ' '^#### Agents 1–6 ' "$1" | tr '\n' ' ' | tr -s ' ')
	for _sr_r in \
		'protocol|**The seven sub-agents are the protocol; one context auditing every lens itself is the single-reviewer pass, allowed only when no lens agent can run and only when recorded.**' \
		'never to save spawns|never a choice made to save spawns: a context that can spawn the seven spawns them' \
		'summary names the lenses|Its summary'"'"'s `Lenses not run:` line names every lens it audited, each marked "run in this context instead"' \
		'raises under the token|Every finding it raises carries `data.agent=single-reviewer`, never the token of a lens no lens agent ran' \
		'verdicts carry the token|both of its verdict lines (§5, §5b) carry `data.agent=single-reviewer`' \
		'one lens audited here|that lens'"'"'s findings are `single-reviewer`'"'"'s'; do
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
bait568() { # <rule name> <sed script>
	sed "$2" "$SKILL_ABS" >"$SCRATCH/bait568.md"
	! cmp -s "$SCRATCH/bait568.md" "$SKILL_ABS" && single_rules_missing "$SCRATCH/bait568.md" | grep -qxF -- "$1"
}
for b in \
	'roster row|/^- `single-reviewer` — /d' \
	'row: never a spawn|/^- `single-reviewer` — /s/never a spawn/a spawn/' \
	'protocol|s/allowed only when no lens agent can run and only when recorded/allowed whenever it is quicker/' \
	'never to save spawns|s/never a choice made to save spawns/also a way to save spawns/' \
	'summary names the lenses|s/line names every lens it audited/line may name a lens/' \
	'raises under the token|s/never the token of a lens no lens agent ran/or the token of the lens it fits/' \
	'verdicts carry the token|s/both of its verdict lines (§5, §5b) carry/its verdict lines may carry/' \
	"one lens audited here|s/that lens's findings are \`single-reviewer\`'s/that lens keeps its token/" \
	'raise step: the token|s/the token is `single-reviewer` for every finding no lens agent produced/the token is the lens it fits/' \
	'relay: the token|s/whatever lens it names/unless it names a lens/' \
	'both verdicts always|s/Both verdicts are recorded on every review/A verdict is recorded on most reviews/' \
	'pass is a verdict|s/`pass` is a verdict\./no findings need no verdict./' \
	'end after both verdicts|s/closes after the raises and both verdicts/closes after the raises/'; do
	bait568 "${b%%|*}" "${b#*|}" && pass "bait: /review-pr without '${b%%|*}' goes red" ||
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
bait629() { # <rule name> <sed script>
	sed "$2" "$SKILL_ABS" >"$SCRATCH/bait629.md"
	! cmp -s "$SCRATCH/bait629.md" "$SKILL_ABS" && emit_points_missing "$SCRATCH/bait629.md" | grep -qxF -- "$1"
}
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
	bait629 "${b%%|*}" "${b#*|}" && pass "bait: /review-pr without '${b%%|*}' goes red" ||
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
# it citing the band, and never hands one to the operator.
ITER_ABS="$ROOT/$ITER"
# low_band_missing <review-pr file> <pr-iterate file> — each rule lost, one per line.
low_band_missing() {
	_lb_r=$(tr '\n' ' ' <"$1" | tr -s ' ')
	_lb_i=$(tr '\n' ' ' <"$2" | tr -s ' ')
	for _lb in \
		'band rule|**A LOW is counted, never posted by an agent path of this skill**' \
		'band evidence|114 of 171 raises were LOW' \
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
	sed "$3" "$_bf" >"$SCRATCH/bait635.md"
	! cmp -s "$SCRATCH/bait635.md" "$_bf" || return 1
	if [ "$2" = i ]; then low_band_missing "$SKILL_ABS" "$SCRATCH/bait635.md"; else low_band_missing "$SCRATCH/bait635.md" "$ITER_ABS"; fi | grep -qxF -- "$1"
}
for b in \
	'band rule|r|s/A LOW is counted, never posted by an agent path of this skill/A LOW is posted/' \
	'band evidence|r|s/114 of 171 raises were LOW/many raises were LOW/' \
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

t_done "/review-pr output contract"
