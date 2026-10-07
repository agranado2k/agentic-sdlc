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
a5=$(t_line_of "$SKILL_ABS" "#### Agent 5 ")
a6=$(t_line_of "$SKILL_ABS" "#### Agent 6 ")
if [ -n "$a5" ] && [ -n "$a6" ] && [ "$a5" -lt "$a6" ]; then
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
agent5=$(agent5_of "$SKILL_ABS")
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
ruling=$(ruling_of "$SKILL_ABS")
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
exception=$(sentences_of "$SKILL_ABS" | grep -F "divergent-behavior" | grep -F "stays a finding")
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
roster=$(region '^\*\*The sub-agent roster\.\*\*' '^#### Agent 1 ' | grep -c '^- `')
[ "$roster" = 9 ] &&
	pass "the roster names seven lenses, the unattributed token and the single-reviewer token" ||
	fail "the roster names $roster tokens, not 9 — seven lenses, unattributed and single-reviewer"
# Bait 1: the ruling withdrawn from a copy of the skill — ruling_of must be
# what catches it, so it is known to read the prompt and not a word that
# happens to be elsewhere in the file.
sed "$((a5 + 1)),$((a6 - 1))s/candidate ticket/follow-up/g" "$SKILL_ABS" >"$SCRATCH/bait5.md"
b5=$(ruling_of "$SCRATCH/bait5.md")
[ -z "$b5" ] && ! cmp -s "$SCRATCH/bait5.md" "$SKILL_ABS" &&
	pass "bait: the ruling renamed away from 'candidate ticket' goes red" ||
	fail "bait: with 'candidate ticket' withdrawn from Agent 5's section the ruling still reads '$b5'"
# Bait 2: the fix line replaced by a request for the move, in the same
# sentence — the ruling still reads, and the fix assertion is what goes red.
# This is the check that carries retro H2: a lens that names the ticket and
# still asks for the consolidation.
sed "$((a5 + 1)),$((a6 - 1))s/none on this PR[^\`]*/extract the copies into one helper and call it from both sites/" "$SKILL_ABS" >"$SCRATCH/bait5-fix.md"
b5f=$(ruling_of "$SCRATCH/bait5-fix.md")
if [ -n "$b5f" ] && ! cmp -s "$SCRATCH/bait5-fix.md" "$SKILL_ABS" && ! spells_fix "$b5f"; then
	pass "bait: the fix line swapped for a request to move the copies goes red at the fix assertion"
else
	fail "bait: with the fix line swapped for a request to move the copies, the fix assertion still passes (ruling: '$b5f')"
fi

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
a5_sentences=$(sentences_of "$SKILL_ABS")
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
	_lr_s3=$(region '^### 3\. ' '^#### Agent 1 ' "$1")
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
	_sr_s3=$(region '^### 3\. ' '^#### Agent 1 ' "$1" | tr '\n' ' ' | tr -s ' ')
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
	case "$_sr_5b" in *'**Both verdicts are recorded on every review — seven agents, a single-reviewer pass, a relay — before the run'"'"'s `end` (§7).**'*) ;; *) printf '%s\n' 'both verdicts always' ;; esac
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

t_done "/review-pr output contract"
