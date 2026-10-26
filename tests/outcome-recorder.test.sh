#!/bin/sh
# tests/outcome-recorder.test.sh — self-tests for the outcome recorder,
# `sh scripts/trace.sh outcomes` (PRD-06 slices 2, 4 and 5 of K1, #876,
# #878, #879; the kit's ADR-0036).
#
# The recorder reads git and the trace, and writes one `merge.outcome
# outcome=reverted` against each landed PR whose lines a later `revert`
# landing removed, and one `outcome=fixed` against each whose lines a `fix`
# landing removed or rewrote inside the fix window, as git blame at that
# landing's first parent attributes them — and, from a fixture `.factory/`,
# one `outcome=qa-failed` against the PR a ticket whose QA failed links. Its whole job is reading git, so the fixture is a REAL throwaway
# repository with scripted landings — squash-style commits on main and
# merge commits whose PR title sits below the "Merge pull request" line —
# and a fixture trace holding their `merge.land` events.
#
# Usage: sh tests/outcome-recorder.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
TRACE="$KIT/scripts/trace.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# policy <trace dir> — a trace policy file naming that directory.
policy() {
	_po=$(mktemp "$SCRATCH/policy.XXXXXX") || exit 2
	printf "TRACE_DIR='%s'\n" "$1" >"$_po"
	printf '%s\n' "$_po"
}
# land_ev <trace> <subject> <merge sha> — one raw `merge.land` line.
land_ev() {
	mkdir -p "$1/events"
	_le_n=$((${_le_n:-0} + 1))
	printf '{"v":1,"ts":"%s","id":"%s-%d-0000abcd","kind":"merge.land","subject":"%s","outcome":"landed","reason":"fixture","data":{"merge_sha":"%s"}}\n' \
		"$NOW" "$(printf '%s' "$NOW" | tr -d ':-')" "$_le_n" "$2" "$3" >>"$1/events/${NOW%%T*}.jsonl"
}
# put <path> <lines…> — write the file, one argument per line.
put() {
	_pu=$1
	shift
	mkdir -p "$(dirname "$R/$_pu")"
	printf '%s\n' "$@" >"$R/$_pu"
}
# land <message> [<body>] — commit the tree on the current branch; prints the sha.
land() {
	git -C "$R" add -A
	if [ $# -gt 1 ]; then git -C "$R" commit -q -m "$1" -m "$2"; else git -C "$R" commit -q -m "$1"; fi
	git -C "$R" rev-parse HEAD
}
# merge_pr <branch> <number> <title> — a GitHub-style merge commit: the PR
# title is the message's third line, under "Merge pull request".
merge_pr() {
	git -C "$R" checkout -q main
	git -C "$R" merge -q --no-ff "$1" -m "Merge pull request #$2 from fixture/$1" -m "$3"
	git -C "$R" rev-parse HEAD
}
outcomes_in() { cat "$1"/events/*.jsonl | grep '"kind":"merge.outcome"'; }
count_in() { cat "$1"/events/*.jsonl | wc -l | tr -d ' '; }
record_cmd() { t_exec sh -c 'cd "$1" && env TRACE_CONFIG="$2" LENS_SLICE_CONFIG="$3" sh "$4" "$5"' _ "$R" "$ON" "$POL" "$TRACE" "$1"; }

banner "1. A revert landing's removed lines are blamed to the PR that brought them (runtime/R32, R39, R40, R42)"

t_repo
R=$REPO
T="$SCRATCH/trace"
put seed/s.sh s1 s2
SEED=$(land 'chore: seed, before the trace')
put src/a.sh a1 a2 a3
S1=$(land 'feat: one')
git -C "$R" checkout -q -b two
put tests/t.sh t1 t2
B2=$(land 'test: two')
S2=$(merge_pr two 2 'feat: two')
put lib/x.sh x1 x2
S6=$(land 'feat: six')
put docs/n.md n1
S99=$(land 'feat: ninety-nine')
put docs/d.md d1 d2
S9=$(land 'feat: nine')
rm "$R/docs/d.md"
S10=$(land 'feat: drop d, a pure deletion')
put docs/d.md d1 d2
S11=$(land 'revert: put d back' "This reverts commit $S10.")
# Removes a2 (from #1) and s1 (from the seed no merge.land names), names #99
# in prose and #6's sha in its body: neither is read, since it removed lines.
put src/a.sh a1 a3
put seed/s.sh s2
S3=$(land 'revert: undo one, as #99 asked' "This reverts commit $S6.")
git -C "$R" checkout -q -b four
put tests/t.sh t2
land 'chore: drop t1' >/dev/null
S4=$(merge_pr four 4 'revert(tests)!: undo two')
put lib/x.sh x2
S7=$(land 'refactor: tidy six')
put lib/x.sh
S8=$(land 'feat: rework six, reverting #6')
# Three pure-addition reverts whose sha must not resolve to a PR: one that
# names no commit, one off the first-parent history, one no merge.land names.
put docs/e.md e1
S12=$(land 'revert: bad sha' 'This reverts commit 0123456789abcdef0123456789abcdef01234567.')
put docs/e.md e1 e2
S13=$(land 'revert: off the first parent' "This reverts commit $B2.")
put docs/e.md e1 e2 e3
S14=$(land 'revert: unnamed' "This reverts commit $SEED.")
for _p in "1 $S1" "2 $S2" "3 $S3" "4 $S4" "6 $S6" "7 $S7" "8 $S8" "9 $S9" "10 $S10" "11 $S11" "12 $S12" "13 $S13" "14 $S14" "99 $S99" "20 $B2"; do
	land_ev "$T" "pr:#${_p%% *}" "${_p#* }"
done
ON=$(policy "$T")
POL="$SCRATCH/lens-slice-policy.sh"
printf '%s\n' "LENS_SLICE_RULES='security ^src/" 'api-crud ^api/' 'test-hygiene ^tests/' 'pattern ^docs/' 'simplicity ^lib/' "reuse-dry ^none/'" >"$POL"

_before=$(count_in "$T")
record_cmd outcomes
[ "$T_STATUS" = 0 ] && pass "outcomes exits 0" || fail "outcomes exited $T_STATUS: $T_ERR"
OUT1=$(outcomes_in "$T")
[ "$(printf '%s\n' "$OUT1" | grep -c .)" = 3 ] && pass "three outcomes are written, no more" ||
	fail "expected three merge.outcome lines, got: $OUT1"
[ "$(count_in "$T")" = $((_before + 3)) ] && pass "and nothing else is written to the trace" || fail "the trace grew by $(($(count_in "$T") - _before)), not 3"

# has_outcome <pr> <related> <by sha> <files> — one written line, exactly.
has_outcome() {
	printf '%s\n' "$OUT1" | grep -F "\"subject\":\"pr:#$1\"" | grep -F '"outcome":"reverted"' | grep -F "\"related\":\"pr:#$2\"" |
		grep -F "\"by_sha\":\"$3\"" | grep -qF "\"files\":\"$4\""
}
has_outcome 1 3 "$S3" src/a.sh && pass "runtime/R32: a squash-style revert gives reverted on #1, related #3, its merge sha in data.by_sha, src/a.sh in data.files" ||
	fail "runtime/R32: no reverted outcome on #1 by #3 ($S3) naming src/a.sh: $OUT1"
has_outcome 2 4 "$S4" tests/t.sh && pass "runtime/R32: a merge-commit revert, typed on the PR title's line, blames a branch commit to #2's landing" ||
	fail "runtime/R32: no reverted outcome on #2 by #4 ($S4) naming tests/t.sh: $OUT1"
printf '%s\n' "$OUT1" | grep -qF '"subject":"pr:#99"' && fail "runtime/R39: a PR named in prose (#99) got an outcome" ||
	pass "runtime/R39: a commit message naming #99 in prose gives nothing for #99"
printf '%s\n' "$OUT1" | grep -qF '"subject":"pr:#6"' && fail "runtime/R39, R40: #6 got an outcome from a sha in a line-removing revert's body or a feat/refactor landing" ||
	pass "runtime/R39, runtime/R40: a feat or refactor landing removing #6's lines gives nothing, and a line-removing revert's sha is not read"
printf '%s\n' "$OUT1" | grep -qF '"subject":"pr:#9"' && fail "runtime/R40: a feat landing that removed #9's lines gave #9 an outcome" ||
	pass "runtime/R40: a feat: pure deletion of #9's file gives #9 nothing"
printf '%s\n' "$OUT1" | grep -qiE 'asked|undo|tidy|put d back' && fail "a merge.outcome carries text from a commit message: $OUT1" ||
	pass "no merge.outcome field carries text from a commit message"
case $T_ERR in *'1 line'*'no merge.land'*) pass "runtime/R42: the seed's blamed line gets no outcome, and its count is said on stderr" ;;
*) fail "runtime/R42: stderr did not count one unattributed line: $T_ERR" ;; esac

banner "2. A pure-deletion revert is resolved by the sha in its message, and only a landed first-parent one (runtime/R33)"

has_outcome 10 11 "$S11" docs/d.md && pass "runtime/R33: the revert that removes no line names #10's merge sha, and #10 is reverted" ||
	fail "runtime/R33: no reverted outcome on #10 by #11 ($S11): $OUT1"
printf '%s\n' "$OUT1" | grep -qE '"related":"pr:#1[234]"|"subject":"pr:#20"' &&
	fail "runtime/R33: a sha that does not resolve, is off the first parent, or no merge.land names, gave an outcome" ||
	pass "runtime/R33: a sha that does not resolve, one off the first-parent history and one no merge.land names give nothing"

banner "3. A second run writes 0 lines (runtime/R41)"

_mid=$(count_in "$T")
record_cmd outcomes
[ "$T_STATUS" = 0 ] && [ "$(count_in "$T")" = "$_mid" ] && pass "runtime/R41: a second run over the same history writes 0 lines" ||
	fail "runtime/R41: the second run exited $T_STATUS and the trace went $_mid -> $(count_in "$T")"
case $T_OUT in *'0 written'*) pass "and says so: 0 written" ;; *) fail "the second run did not say 0 written: $T_OUT" ;; esac
( cd "$R" && env TRACE_CONFIG="$ON" sh "$TRACE" verify >/dev/null 2>&1 ) && pass "the trace the recorder wrote verifies" ||
	fail "trace verify refuses the trace the recorder wrote"

banner "4. /retro's question 2, end to end: the recorder, then the record reader (process/R37, runtime/R43)"

record_cmd record
REC1=$T_OUT
printf '%s\n' "$REC1" | grep -qF 'security: landings 2 of 20, in the fix window 2, mistakes 1,' &&
	printf '%s\n' "$REC1" | grep -qF 'simplicity: landings 3 of 20, in the fix window 3, mistakes 0,' &&
	pass "process/R37: after one run the reverted PR's review area reads mistakes 1, an untouched one 0" ||
	fail "process/R37: record printed: $(printf '%s' "$REC1" | tr '\n' ';')"
_mid=$(count_in "$T")
record_cmd outcomes
record_cmd record
[ "$T_OUT" = "$REC1" ] && [ "$(count_in "$T")" = "$_mid" ] && pass "process/R37: a second /retro adds nothing and prints the same record" ||
	fail "process/R37: the second pass changed the trace ($_mid -> $(count_in "$T")) or the record"

# A path holding a space: git ends its `--- a/<path>` header with a tab,
# which must not reach blame as part of the name (review of PR #895).
R_MAIN=$R
t_repo
R=$REPO
T2="$SCRATCH/trace-space"
put 'src/a b.sh' s1 s2
SP1=$(land 'feat: a spaced path')
put 'src/a b.sh' s2
SP2=$(land 'revert: drop s1')
land_ev "$T2" 'pr:#31' "$SP1"
land_ev "$T2" 'pr:#32' "$SP2"
t_exec sh -c 'cd "$1" && env TRACE_CONFIG="$2" sh "$3" outcomes' _ "$R" "$(policy "$T2")" "$TRACE"
outcomes_in "$T2" | grep -F '"subject":"pr:#31"' | grep -qF '"files":"src/a b.sh"' &&
	pass "runtime/R32: a revert of lines in a path holding a space is blamed to the PR that wrote them" ||
	fail "runtime/R32: no outcome for a spaced path: $T_OUT | $T_ERR"
R=$R_MAIN

banner "5. A fix landing counts against a PR only inside the fix window (runtime/R34, R35, R36)"

# A throwaway history dated by GIT_COMMITTER_DATE: #41 lands on day 0, #42 on
# day 29, #44 on day 35, and #43 — a merge commit typed `fix` on its PR
# title's line, naming #44 in prose — on day 41, rewriting one line of #41
# (41 days before it) and one of #42 (12 days before it).
# at <day> <cmd…> — run the command with both git dates on that day.
at() {
	_at_d=$(printf '2026-01-%02dT12:00:00Z' $(($1 + 1)))
	[ "$1" -lt 31 ] || _at_d=$(printf '2026-02-%02dT12:00:00Z' $(($1 - 30)))
	shift
	GIT_COMMITTER_DATE=$_at_d GIT_AUTHOR_DATE=$_at_d "$@"
}
R_MAIN=$R
t_repo
R=$REPO
TF="$SCRATCH/trace-fix"
put src/f.sh f1 f2
F41=$(at 0 land 'feat: forty-one')
put src/g.sh g1 g2
F42=$(at 29 land 'feat: forty-two')
put docs/h.md h1 h2
F44=$(at 35 land 'feat: forty-four')
git -C "$R" checkout -q -b fortythree
put src/f.sh f1-fixed f2
put src/g.sh g1-fixed g2
at 41 land 'chore: repair' >/dev/null
F43=$(at 41 merge_pr fortythree 43 'fix(src): repair the bug from #44')
for _p in "41 $F41" "42 $F42" "43 $F43" "44 $F44"; do
	land_ev "$TF" "pr:#${_p%% *}" "${_p#* }"
done
FON=$(policy "$TF")
# fix_run <policy> — the recorder over the fix history, under that policy.
fix_run() { t_exec sh -c 'cd "$1" && env TRACE_CONFIG="$2" sh "$3" outcomes' _ "$R" "$1" "$TRACE"; }

fix_run "$FON"
FOUT=$(outcomes_in "$TF")
printf '%s\n' "$FOUT" | grep -F '"subject":"pr:#42"' | grep -F '"outcome":"fixed"' | grep -F '"related":"pr:#43"' |
	grep -F "\"by_sha\":\"$F43\"" | grep -F '"files":"src/g.sh"' | grep -qF '"days":"12"' &&
	pass "runtime/R34: a fix 12 days after #42 gives fixed on #42, related #43, its merge sha, src/g.sh and data.days 12" ||
	fail "runtime/R34: no fixed outcome on #42 by #43 with data.days 12: $FOUT | $T_ERR"
[ "$(printf '%s\n' "$FOUT" | grep -c .)" = 1 ] && pass "runtime/R35: #41, landed 41 days before the fix, gets nothing — one outcome only" ||
	fail "runtime/R35: expected one merge.outcome, got: $FOUT"
printf '%s\n' "$FOUT" | grep -qF '"subject":"pr:#44"' && fail "runtime/R39: the fix's title names #44 in prose and #44 got an outcome" ||
	pass "runtime/R39: a fix whose message names #44 in prose gives #44 nothing"
_mid=$(count_in "$TF")
fix_run "$FON"
[ "$T_STATUS" = 0 ] && [ "$(count_in "$TF")" = "$_mid" ] && pass "runtime/R41: a second run over the fix writes 0 lines" ||
	fail "runtime/R41: the second run exited $T_STATUS and the trace went $_mid -> $(count_in "$TF")"

# window <value> — a fresh trace holding the four landings, its policy
# setting TRACE_FIX_WINDOW_DAYS to the value; runs the recorder over it.
window() {
	TW=$(mktemp -d "$SCRATCH/trace-window.XXXXXX")
	mkdir -p "$TW/events"
	grep -h '"kind":"merge.land"' "$TF"/events/*.jsonl >"$TW/events/${NOW%%T*}.jsonl"
	_wp=$(policy "$TW")
	printf "TRACE_FIX_WINDOW_DAYS='%s'\n" "$1" >>"$_wp"
	fix_run "$_wp"
	WOUT=$(cat "$TW"/events/*.jsonl | grep '"kind":"merge.outcome"')
}
window 7
[ "$T_STATUS" = 0 ] && [ -z "$WOUT" ] && pass "runtime/R36: a 7-day fix window in the policy file: the 12-day fix gives nothing" ||
	fail "runtime/R36: under a 7-day window the recorder exited $T_STATUS and wrote: $WOUT"
window 13
printf '%s\n' "$WOUT" | grep -F '"subject":"pr:#42"' | grep -qF '"days":"12"' && [ -z "$T_ERR" ] &&
	pass "runtime/R36: a 13-day fix window holds the 12-day fix, silently" ||
	fail "runtime/R36: under a 13-day window: $WOUT | $T_ERR"
window 12
[ "$T_STATUS" = 0 ] && [ -z "$WOUT" ] && pass "runtime/R35: a 12-day fix window does not hold a fix 12 days later — the window's edge is outside it" ||
	fail "runtime/R35: under a 12-day window the 12-day fix was recorded, or the recorder exited $T_STATUS: $WOUT"
for _bad in 'two weeks' 7.5 -7 0; do
	window "$_bad"
	if printf '%s\n' "$WOUT" | grep -F '"subject":"pr:#42"' | grep -qF '"days":"12"'; then
		case $T_ERR in *TRACE_FIX_WINDOW_DAYS*"$_bad"*30*) pass "runtime/R36: TRACE_FIX_WINDOW_DAYS='$_bad' is not used — the 30-day window holds, and stderr says so" ;;
		*) fail "runtime/R36: TRACE_FIX_WINDOW_DAYS='$_bad' gave no note on stderr: $T_ERR" ;; esac
	else
		fail "runtime/R36: TRACE_FIX_WINDOW_DAYS='$_bad' was used, or the 30-day window did not hold: $WOUT | $T_ERR"
	fi
done
_wp=$(policy "$TW")
printf "TRACE_FIX_WINDOW_DAYS='thirty'\n" >>"$_wp"
t_exec sh -c 'cd "$1" && env TRACE_CONFIG="$2" LENS_SLICE_CONFIG="$3" sh "$4" record' _ "$R" "$_wp" "$POL" "$TRACE"
case $T_ERR in *TRACE_FIX_WINDOW_DAYS*thirty*30*) pass "runtime/R36: the record reader reads the same window, and says so for a value it cannot use" ;;
*) fail "runtime/R36: record gave no note for TRACE_FIX_WINDOW_DAYS='thirty': $T_ERR" ;; esac
TE=$(mktemp -d "$SCRATCH/trace-env.XXXXXX")
mkdir -p "$TE/events"
grep -h '"kind":"merge.land"' "$TF"/events/*.jsonl >"$TE/events/${NOW%%T*}.jsonl"
t_exec sh -c 'cd "$1" && env TRACE_FIX_WINDOW_DAYS=7 TRACE_CONFIG="$2" sh "$3" outcomes' _ "$R" "$(policy "$TE")" "$TRACE"
cat "$TE"/events/*.jsonl | grep -F '"subject":"pr:#42"' | grep -qF '"days":"12"' &&
	pass "runtime/R36: a 7-day TRACE_FIX_WINDOW_DAYS in the environment is not the policy file's — the 12-day fix is still recorded" ||
	fail "runtime/R36: an environment window was read as the policy's: $T_ERR"
grep -qx "TRACE_FIX_WINDOW_DAYS=''" "$KIT/scripts/trace.config.sh" &&
	pass "runtime/R36: the shipped trace policy file names TRACE_FIX_WINDOW_DAYS, empty — the 30-day window" ||
	fail "runtime/R36: scripts/trace.config.sh does not ship TRACE_FIX_WINDOW_DAYS=''"

# A fix whose merge commit is dated before the landing it rewrites — a
# skewed clock, a rebased history — is not inside the window: #51 lands on
# day 20 and #52, typed `fix`, is dated day 10.
t_repo
R=$REPO
TS="$SCRATCH/trace-skew"
put src/s.sh s1 s2
S51=$(at 20 land 'feat: fifty-one')
git -C "$R" checkout -q -b fiftytwo
put src/s.sh s1-fixed s2
at 10 land 'chore: repair' >/dev/null
S52=$(at 10 merge_pr fiftytwo 52 'fix: repair fifty-one')
land_ev "$TS" pr:#51 "$S51"
land_ev "$TS" pr:#52 "$S52"
fix_run "$(policy "$TS")"
[ "$T_STATUS" = 0 ] && [ -z "$(outcomes_in "$TS")" ] && pass "runtime/R34: a fix dated before the landing it rewrites gives that landing nothing" ||
	fail "runtime/R34: a fix dated 10 days before #51 recorded: $(outcomes_in "$TS") | $T_ERR"
R=$R_MAIN

banner "6. A failed factory QA is a qa-failed outcome on the PR its ticket links (runtime/R37, R38, R39, R41, R46)"

# A fresh history: #890 brings src/q.sh, #891 tests/q.sh. Before any
# .factory/ exists the recorder takes no step for it and says nothing.
t_repo
R=$REPO
TQ="$SCRATCH/trace-qa"
put src/q.sh q1 q2
S890=$(land 'feat: eight-ninety')
put tests/q.sh u1
S891=$(land 'test: eight-ninety-one')
land_ev "$TQ" pr:#890 "$S890"
land_ev "$TQ" pr:#891 "$S891"
QON=$(policy "$TQ")
qa_run() { t_exec sh -c 'cd "$1" && env TRACE_CONFIG="$2" LENS_SLICE_CONFIG="$3" sh "$4" "$5"' _ "$R" "$QON" "$POL" "$TRACE" "$1"; }
_q0=$(count_in "$TQ")
qa_run outcomes
[ "$T_STATUS" = 0 ] && [ -z "$T_ERR" ] && [ "$(count_in "$TQ")" = "$_q0" ] && pass "runtime/R37: a repository with no .factory/ gives nothing and prints nothing on stderr" ||
	fail "runtime/R37: with no .factory/ the recorder exited $T_STATUS, wrote $(($(count_in "$TQ") - _q0)) line(s), said: $T_ERR"

# ticket <id> <frontmatter lines…> — a factory ticket under .factory/items/<id>/;
# its body names #891 in prose and in a field-shaped line, neither read.
ticket() {
	_ti=$1
	shift
	mkdir -p "$R/.factory/items/$_ti"
	{
		printf '%s\n' --- "id: $_ti" 'type: ticket' "$@" 'notes:' '  pr: "#891"' ---
		printf '%s\n' '' "# $_ti" '' 'Broke in staging on #891, see links:' 'pr: "#891"' 'qa:' '  outcome: fail'
	} >"$R/.factory/items/$_ti/ticket.md"
}
ticket T-31 'links:' '  pr: "#890"' 'qa:' '  outcome: fail' '  by: "operator"'
ticket T-32 'links:' '  pr: "890a"' 'qa:' '  outcome: fail'
ticket T-33 'qa:' '  outcome: fail' 'links:' "  pr: '#999'"
ticket T-34 'links:' '  pr: "#891"' 'qa:' '  outcome: pass'
ticket T-35 'links:' '  pr: #891' 'qa:' '  outcome: fail'
mkdir -p "$R/.factory/items/PRD-09"
printf '%s\n' --- 'id: PRD-09' 'links:' '  pr: "#891"' 'qa:' '  outcome: fail' --- >"$R/.factory/items/PRD-09/prd.md"
qa_run outcomes
QOUT=$(outcomes_in "$TQ")
[ "$T_STATUS" = 0 ] && [ "$(printf '%s\n' "$QOUT" | grep -c .)" = 1 ] &&
	printf '%s\n' "$QOUT" | grep -F '"subject":"pr:#890"' | grep -F '"outcome":"qa-failed"' | grep -qF '"ticket":"T-31"' &&
	pass "runtime/R37: T-31's qa.outcome fail and links.pr #890 give one merge.outcome outcome=qa-failed on #890, data.ticket T-31" ||
	fail "runtime/R37: expected one qa-failed on #890 for T-31, got (exit $T_STATUS): $QOUT | $T_ERR"
printf '%s\n' "$QOUT" | grep -qF '"subject":"pr:#891"' && fail "runtime/R39: #891, named only in prose, another field, a passed ticket or a prd, got an outcome" ||
	pass "runtime/R39: a body, another field, a passed QA and a non-ticket item naming #891 give #891 nothing"
case $T_OUT in *'1 written'*) pass "and says so: 1 written" ;; *) fail "the recorder did not say 1 written: $T_OUT" ;; esac
for _id in T-32 T-33 T-35; do
	case $T_ERR in *"$_id"*) pass "runtime/R38: $_id's links.pr (malformed, or naming a PR with no merge.land) is named on stderr" ;;
	*) fail "runtime/R38: stderr does not name $_id: $T_ERR" ;; esac
done
case $T_ERR in *T-31* | *T-34*) fail "runtime/R38: stderr names a ticket that was recorded or passed: $T_ERR" ;;
*) pass "runtime/R38: stderr names neither the recorded ticket nor the passed one" ;; esac
printf '%s\n' "$QOUT" | grep -qiE 'operator|staging' && fail "a qa-failed line carries text from a factory ticket: $QOUT" ||
	pass "no qa-failed field carries text from a factory ticket"

_q1=$(count_in "$TQ")
qa_run outcomes
[ "$T_STATUS" = 0 ] && [ "$(count_in "$TQ")" = "$_q1" ] && pass "runtime/R41: a second run writes 0 lines — the PR and data.ticket are its key" ||
	fail "runtime/R41: the second run exited $T_STATUS and the trace went $_q1 -> $(count_in "$TQ")"
( cd "$R" && env TRACE_CONFIG="$QON" sh "$TRACE" verify >/dev/null 2>&1 ) && pass "the trace holding the qa-failed line verifies" ||
	fail "trace verify refuses the qa-failed line the recorder wrote"
qa_run record
printf '%s\n' "$T_OUT" | grep -qF 'security: landings 1 of 20, in the fix window 1, mistakes 1, missed 1 of 1,' &&
	printf '%s\n' "$T_OUT" | grep -qF 'test-hygiene: landings 1 of 20, in the fix window 1, mistakes 0, missed 0 of 1,' &&
	pass "runtime/R46: the record reader counts #890's area with one missed mistake, #891's with none" ||
	fail "runtime/R46: record printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
R=$R_MAIN

OFF=$(mktemp "$SCRATCH/off.XXXXXX")
printf "TRACE_DIR=''\n" >"$OFF"
t_exec sh -c 'cd "$1" && env TRACE_CONFIG="$2" sh "$3" outcomes' _ "$R" "$OFF" "$TRACE"
[ "$T_STATUS" = 0 ] && [ -z "$T_OUT" ] && [ -z "$(git -C "$R" status --porcelain)" ] &&
	pass "runtime/R43: an unconfigured recorder writes nothing, prints nothing on stdout, and exits 0" ||
	fail "runtime/R43: unconfigured, outcomes exited $T_STATUS, printed '$T_OUT'"
expect_exit 2 "outcomes takes no argument" -- env TRACE_CONFIG="$ON" sh "$TRACE" outcomes --since 2026-01-01

t_done "outcome recorder"
