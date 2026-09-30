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
#      the dismissal denominator overcounts, the label's override rate is not
#      computable from the trace today, and a row with too few events prints
#      no rate.
#   2. It reads through the plain `sh scripts/trace.sh show|summary|export`
#      name — never the kit's never-shipped wrapper — and verifies first.
#   3. The report lands OUTSIDE the tree: <tmpdir>/retro-<YYYYMMDDTHHMMSSZ>.md.
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
#
# NOT simulable here: the pass itself, which reads a real trace and writes a
# report. The ticket's demo — a retro over this repo's own trace — is run by
# hand and quoted in the delivering PR.
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

# flat — stdin as one line, runs of spaces squeezed: a rule that wraps across
# two lines is still the rule, and a needle is matched against the sentence.
flat() { tr '\n' ' ' | tr -s ' '; }

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
items=$(questions | grep -c '^[1-8]\. \*\*')
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
sec8() { awk '/^## 8\. / { on = 1; next } /^## / { on = 0 } on' "$SIDECAR_ABS"; }
stamp=$(sec8 | awk '/^```/ { fence = !fence; next } !fence' | awk '/^\*Reads: / { reads = 1 } !reads; reads && /\*$/ { reads = 0 }' | flat)
reads8=$(sec8 | awk '/^\*Reads: / { reads = 1 } reads; reads && /\*$/ { reads = 0 }' | flat)
rows8=$(sec8 | awk '/^```/ { fence = !fence; next } fence')
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
# The skill is the RUN's: a finding.raise carries its run and no skill of its
# own (the kit's own trace, read for this ticket's demo), so a reader that
# pivots on the event's skill column files every severity row under nothing.
stamp_has '`run.start`' "the skill that stamped is read from the run's run.start where the event names none"
stamp_has '`unattributed`' "…and an event with neither is a row that says so"
# The oracle clause (#276) is on EVERY row this question prints, in the form
# the housekeeping checklist gave it.
stamp_has 'Every row carries the oracle clause' "every row carries the oracle clause"
stamp_has '— oracle: ' "…in the '— oracle:' form the diary's rows use"
stamp_has 'the human at the quiz' "the tier rows' oracle is named: the human at the quiz"
stamp_has 'no held-out set' "…and the comparator is named as what it is — no held-out set"
# Honesty point 1: finding.raise has no posted marker, so the denominator is
# raises on the subject and it OVERCOUNTS what a human could have dismissed.
stamp_has 'overcounts' "the dismissal denominator is said to overcount"
stamp_has 'no marker that it was posted' "…and why: a raise carries no marker that it was posted"
# …and a dismissal is one (data.thread, data.where) pair per subject — a
# resolved thread and its dismissed review can both emit.
stamp_has '(`data.thread`, `data.where`) pair' "a dismissal is identified by the (data.thread, data.where) pair"
stamp_has 'counted once' "…and counted once per subject"
# Honesty point 2: ticket.write records no pre-quiz label, so the label's
# override rate is a row that says so — a candidate ticket, never a guess.
stamp_has '`data.label_confidence`' "the label's confidence is read, under its own key"
stamp_has 'not computable from the trace today' "the label's override rate is said to be not computable today"
stamp_has 'a row of its own' "…in a row of its own"
stamp_has 'never a guess' "…as a candidate ticket, never a guess"
# Honesty point 3: a thin row prints its counts and the words, not a rate.
stamp_has 'too few' "a row with too few events says so"
stamp_has 'instead of a rate' "…instead of printing a rate"
# A window with raises and no finding.dismiss at all is not a band nobody
# dismissed: 0 of 7 printed as a rate reads as a measurement of an emitter
# that may never have run (the kit's own trace, the day the kind landed).
stamp_has 'no dismissal recorded in the window' "a window with no finding.dismiss at all prints no dismissal rate"
stamp_has 'Route: `/to-tickets`' "its findings leave through /to-tickets like the other seven"
# The order file, the description and the procedure count with it.
questions | flat | grep -q 'per decision field and per skill, never one number for the chain' &&
	pass "SKILL.md's eighth item holds the per-field, per-skill rule" ||
	fail "SKILL.md's eighth item does not say 'per decision field and per skill, never one number for the chain'"
questions | flat | grep -q 'oracle clause' && pass "…and the oracle clause on every row" ||
	fail "SKILL.md's eighth item does not name the oracle clause"
desc=$(sed -n 's/^description: //p' "$SKILL_ABS")
case "$desc" in
*'eight fixed questions'*'stamp calibration'*) pass "the frontmatter description counts eight and names stamp calibration" ;;
*) fail "the frontmatter description does not say 'eight fixed questions' with stamp calibration among them" ;;
esac
assert_file_has "$SKILL" "pivot eight times" "the procedure pivots once per question"
assert_file_has "$SKILL" "data.question=<1..8>" "a candidate note can name the eighth question"
awk '/^## Routing/ { on = 1; next } /^## / { on = 0 } on' "$SKILL_ABS" | grep -q '\*\*stamp\*\*' &&
	pass "routing says what a stamp-calibration ticket would change" || fail "the Routing section has no entry for a stamp"
for f in "$SKILL" "$SIDECAR"; do
	assert_file_lacks "$f" "seven questions" "no file of the skill still counts seven"
	assert_file_lacks "$f" "seven fixed" "…in either spelling"
done

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
banner "4. The report lands outside the tree; findings are candidates; it never fixes"
# ---------------------------------------------------------------------------
assert_file_has "$SKILL" 'retro-<YYYYMMDDTHHMMSSZ>.md' "the report's name carries a UTC stamp"
assert_file_has "$SKILL" '<tmpdir>/retro-' "…under the OS temp directory"
assert_file_has "$SKILL" 'TMPDIR' "…resolved from \$TMPDIR"
assert_file_has "$SKILL" "outside the repo tree"
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
	wspan=$(t_trace_spans "$SKILL_ABS" | grep -F '"kind":"run.start"' | head -1)
	wout=$( cd "$ROOT" && TRACE_DIR="$dir" TRACE_QUIET=1 sh -c "$(t_trace_runnable "$wspan")" 2>/dev/null )
	printf '%s\n' "$wout" | grep -F '"kind":"run.start"' | grep -qF '"skill":"retro"' &&
		pass "the window span's output is the seeded retro run.start — the pipeline selects, not just exits 0" ||
		fail "the window span printed no retro run.start over a trace that holds one: $wspan"
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
count_eight() { # <file> <expected> <needle>
	n=$(flat <"$ROOT/$1" | grep -oF "$3" | grep -c .)
	[ "$n" -ge "$2" ] && pass "$1 says '$3' ($n of $2)" || fail "$1 says '$3' $n time(s), expected $2"
	flat <"$ROOT/$1" | grep -qE 'seven (fixed )?questions' &&
		fail "$1 still counts seven questions" || pass "$1 nowhere counts seven questions"
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

t_done "/retro contract"
