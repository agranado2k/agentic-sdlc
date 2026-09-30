#!/bin/sh
# tests/retro-skill.test.sh — the /retro contract, checked as TEXT.
#
# /retro is the one sanctioned reader of the trace besides the operator and a
# diagnosis (ADR-0008 clause 7; PRD #237, ticket #254). It is a document an
# agent obeys, so — the same honest boundary as tests/housekeeping-skill.test.sh
# — the external behavior IS the text, and this suite pins the tokens a session
# following it must run and the rules it must keep:
#
#   1. The SEVEN fixed questions, named and numbered: tier calibration, review
#      signal per sub-agent, recurring failures, diagnosis calibration, spend,
#      chain health, aim calibration (the seventh, added at the PRD
#      re-evaluation of 2026-09-28, reads the `feedback` events).
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
#      list and a kit CI job for this suite.
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
banner "2. The seven fixed questions, named and numbered, in both files"
# ---------------------------------------------------------------------------
# Only the questions section counts in SKILL.md — the procedure below it
# numbers its steps too.
questions() { awk '/^## The seven questions/ { on = 1; next } /^## / { on = 0 } on' "$SKILL_ABS"; }
items=$(questions | grep -c '^[1-7]\. \*\*')
[ "$items" = 7 ] && pass "the questions section has seven numbered items" || fail "the questions section has $items numbered items, not seven"
for q in 'Tier calibration' 'Review signal' 'Recurring failures' 'Diagnosis calibration' 'Spend' 'Chain health' 'Aim calibration'; do
	questions | grep -q "\*\*$q" && pass "SKILL.md names the question '$q'" || fail "SKILL.md does not name the question '$q'"
	grep -q "^## [1-7]\. $q" "$SIDECAR_ABS" && pass "QUESTIONS.md carries '$q' as a numbered section" ||
		fail "QUESTIONS.md has no numbered section for '$q'"
done
sidecar_sections=$(grep -c '^## [1-7]\. ' "$SIDECAR_ABS")
[ "$sidecar_sections" = 7 ] && pass "QUESTIONS.md has exactly seven numbered sections" || fail "QUESTIONS.md has $sidecar_sections numbered sections, not seven"
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
assert_file_has "$SIDECAR" "hypothesis" "diagnosis calibration reads the hypotheses"
assert_file_has "$SIDECAR" "data.rank" "…at the rank each held"
assert_file_has "$SIDECAR" "confirmed" "…against the one confirmed"
assert_file_has "$SIDECAR" "session.usage" "spend reads the per-model token sums"
assert_file_has "$SIDECAR" "unpriced" "spend names the model the price table does not"
assert_file_has "$SIDECAR" "spawn.end" "chain health reads how spawns ended"
for o in fail timeout budget unreachable; do
	assert_file_has "$SIDECAR" "\`$o\`" "chain health names the spawn outcome '$o'"
done
# H-1 (review of PR #293): a window with no spawn.end at all is ONE finding
# about the emitter, never one per spawn — or every spawn is a finding.
assert_file_has "$SIDECAR" "no \`spawn.end\` at all" "an absent kind is one finding about the emitter, not one per spawn"
assert_file_has "$SIDECAR" "merge.land" "chain health finds PRs with no landing"
assert_file_has "$SIDECAR" "\`feedback\`" "aim calibration reads the feedback events"
for v in hit adjusted missed; do
	assert_file_has "$SIDECAR" "\`$v\`" "aim calibration names the verdict '$v'"
done
assert_file_has "$SIDECAR" "re-cut" "aim calibration asks how many landed slices were followed by a re-cut"

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
