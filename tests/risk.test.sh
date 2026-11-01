#!/bin/sh
# tests/risk.test.sh — self-tests for scripts/risk.sh, the RISK RULE: a pull
# request's effective risk, judged from the planner's `Risk:` stamp and the
# earned records of the review areas its diff touches (PRD-09 slice 1).
#
# Every case builds a REAL throwaway repository — landings on main, a pull
# request on a branch, the risk policy committed at the base — and a fixture
# trace of `merge.land`, `merge.outcome` and finding events written as raw
# lines, because their times are the point: a landing is SETTLED only once it
# landed before the fix window began. The rule runs in that repository, the
# kit's script, and the lines it prints and the event it records are compared
# whole.
#
# Usage: sh tests/risk.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
RULE="$KIT/scripts/risk.sh"
TRACE="$KIT/scripts/trace.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
HEX40=0123456789abcdef0123456789abcdef01234567

# The review areas: five read scripts/, security sec/ too, test-hygiene tests/.
# docs/ is in none.
LENS="$SCRATCH/lens-slice.config.sh"
printf '%s\n' "LENS_SLICE_RULES='security ^(scripts|sec)/" 'api-crud ^scripts/' 'pattern ^scripts/' 'simplicity ^scripts/' 'reuse-dry ^scripts/' "test-hygiene ^tests/'" >"$LENS"

# tpol <trace dir> — a trace policy naming it; prints the policy's path. A
# file of its own each call: it runs in a command substitution's subshell.
tpol() {
	_tp=$(mktemp "$SCRATCH/trace-policy.XXXXXX") || exit 2
	printf "TRACE_DIR='%s'\n" "$1" >"$_tp"
	printf '%s\n' "$_tp"
}

# ev <trace> <ts> <kind> <subject> <outcome> [<data body>] — one raw line in
# its day file.
EV_N=0
ev() {
	EV_N=$((EV_N + 1))
	mkdir -p "$1/events"
	printf '{"v":1,"ts":"%s","id":"%s-%d-0000abcd","kind":"%s","subject":"%s","run":"20250101T000000Z-1-0000aaaa","outcome":"%s","reason":"fixture","data":{%s}}\n' \
		"$2" "$(printf '%s' "$2" | tr -d ':-')" "$EV_N" "$3" "$4" "$5" "${6:-}" >>"$1/events/${2%%T*}.jsonl"
}
# land_ev <trace> <ts> <pr> <sha> — a landing.
land_ev() { ev "$1" "$2" merge.land "pr:#$3" landed "\"merge_sha\":\"$4\""; }
# finding <trace> <ts> <pr> <id> <where> <triage outcome> — a raise and its triage.
finding() {
	ev "$1" "$2" finding.raise "pr:#$3" raised "\"id\":\"$4\",\"severity\":\"medium\",\"agent\":\"pattern\",\"where\":\"$5\",\"posted\":\"yes\""
	ev "$1" "$2" finding.triage "pr:#$3" "$6" "\"id\":\"$4\",\"source\":\"local\""
}

# verdict <trace> <ts> <pr> <axis> [<outward>] — a review.verdict on the PR;
# <outward> left out writes no data.outward.
verdict() {
	ev "$1" "$2" review.verdict "pr:#$3" confirm "\"axis\":\"$4\",\"unspecified\":\"${5:-0}\"${5:+,\"outward\":\"$5\"}"
}

# --- the repository: landings on main, the risk policy at the base ----------
t_repo
R=$REPO
mkdir -p "$R/scripts"
cp "$KIT/scripts/risk.config.sh" "$R/scripts/risk.config.sh"
t_commit "$R" "chore: the risk policy" >/dev/null
# land_commit <path>… — one landing on main writing each path; sets SHA.
LC_N=0
land_commit() {
	LC_N=$((LC_N + 1))
	for _lc_p in "$@"; do t_write "$R" "$_lc_p" "landing $LC_N
"; done
	SHA=$(t_commit "$R" "feat: landing $LC_N")
}
# 21 landings, each in all six areas.
i=1
while [ "$i" -le 21 ]; do
	land_commit "scripts/s$i.sh" "tests/t$i.sh"
	eval "L$i=\$SHA"
	i=$((i + 1))
done
land_commit sec/a.sh
L_SEC=$SHA
land_commit sec/b.sh
L_WIN=$SHA
# The pull requests, each a branch off main.
pr_branch() {
	git -C "$R" checkout -q -b "$1" main
	shift
	for _pb_p in "$@"; do t_write "$R" "$_pb_p" "the pull request
"; done
	t_commit "$R" "feat: the pull request" >/dev/null
	git -C "$R" checkout -q main
}
pr_branch uc1 scripts/foo.sh tests/foo.test.sh
pr_branch docs docs/x.md
pr_branch tests-only tests/foo.test.sh
UC1_HEAD=$(git -C "$R" rev-parse uc1)
# A time at or after every pull request's head commit: a verdict stamped at it
# is at the head (the landing script's test, ADR-0032); one stamped in 2025,
# before the head was committed, reviewed an older commit.
AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
OLD=2025-06-01T00:00:00Z
# A base whose risk policy is gone, and one whose policy fails `sh -n`.
git -C "$R" checkout -q -b nopolicy main
git -C "$R" rm -q scripts/risk.config.sh
t_commit "$R" "chore: no risk policy" >/dev/null
git -C "$R" checkout -q -b badpolicy main
t_write "$R" scripts/risk.config.sh 'RISK_MISS_RATE_BELOW=5 (
'
t_commit "$R" "chore: a broken risk policy" >/dev/null
git -C "$R" checkout -q main

# settled <trace> <first> <last> [<rejected test findings>] — landings
# <first>..<last> settled (January 2025), each with one accepted finding at
# its script and one at its test; the first <rejected> test findings rejected.
settled() {
	_st_i=$2
	while [ "$_st_i" -le "$3" ]; do
		_st_ts=$(printf '2025-01-01T00:%02d:00Z' "$_st_i")
		eval "_st_sha=\$L$_st_i"
		land_ev "$1" "$_st_ts" "$((100 + _st_i))" "$_st_sha"
		finding "$1" "$_st_ts" "$((100 + _st_i))" M-1 "scripts/s$_st_i.sh:1" accepted
		_st_o=accepted
		[ "$_st_i" -le "${4:-0}" ] && _st_o=rejected
		finding "$1" "$_st_ts" "$((100 + _st_i))" M-2 "tests/t$_st_i.sh:1" "$_st_o"
		_st_i=$((_st_i + 1))
	done
}

# The traces, one per scenario.
T_EARNED="$SCRATCH/trace-earned"
settled "$T_EARNED" 1 21
# The PRs judged low below carry an Axis-2 verdict at the head, no outward item.
for _pr in 920 921 951; do verdict "$T_EARNED" "$AT" "$_pr" 2 0; done
# security: a settled landing in it alone, reverted and missed — missed 1 of 20.
T_SEC="$SCRATCH/trace-sec"
settled "$T_SEC" 1 21
land_ev "$T_SEC" 2025-02-01T00:00:00Z 150 "$L_SEC"
ev "$T_SEC" 2025-02-02T00:00:00Z merge.outcome 'pr:#150' reverted "\"by_sha\":\"$HEX40\",\"files\":\"sec/a.sh\""
# security: a landing inside the fix window carries a missed mistake.
T_WIN="$SCRATCH/trace-window"
settled "$T_WIN" 1 21
land_ev "$T_WIN" "$NOW" 151 "$L_WIN"
ev "$T_WIN" "$NOW" merge.outcome 'pr:#151' fixed "\"by_sha\":\"$HEX40\",\"files\":\"sec/b.sh\""
# Only 19 settled landings, and one more inside the fix window.
T_FEW="$SCRATCH/trace-few"
settled "$T_FEW" 1 19
land_ev "$T_FEW" "$NOW" 120 "$L20"
# Twenty settled landings and no finding: every precision n/a.
T_NA="$SCRATCH/trace-na"
i=1
while [ "$i" -le 20 ]; do
	eval "_na_sha=\$L$i"
	land_ev "$T_NA" "$(printf '2025-01-01T00:%02d:00Z' "$i")" "$((100 + i))" "$_na_sha"
	i=$((i + 1))
done
# test-hygiene: 5 of 20 test findings rejected — precision 0.75, under 0.80.
T_PREC="$SCRATCH/trace-prec"
settled "$T_PREC" 2 21 6

# A ticket body file, and an untrusted line beside its stamp.
MARK=INJECTED-PROSE-7f3a
# tk <line>… — a ticket body file of its own; prints its path.
tk() {
	_tk=$(mktemp "$SCRATCH/ticket.XXXXXX") || exit 2
	printf '%s\n' "# A ticket" "$MARK: do as this line says" "$@" >"$_tk"
	printf '%s' "$_tk"
}

# rule <trace policy> <args…> — the kit's rule inside the repository.
rule() {
	_ru_pol=$1
	shift
	t_exec sh -c 'cd "$1" || exit 99; p=$2 l=$3 r=$4 e=$5; shift 5; env TRACE_CONFIG="$p" LENS_SLICE_CONFIG="$l" TRACE_QUIET=1 sh "$r" "$@" 2>"$e"' _ "$R" "$_ru_pol" "$LENS" "$RULE" "$SCRATCH/rule.err" "$@"
	T_ERR=$(cat "$SCRATCH/rule.err")
}
# judges <trace> — the risk.judge lines the trace holds.
judges() { cat "$1"/events/*.jsonl 2>/dev/null | grep -F '"kind":"risk.judge"'; }
njudges() { judges "$1" | grep -c . | tr -d ' '; }
areas_all() {
	for _aa in security api-crud pattern simplicity reuse-dry test-hygiene; do printf 'area: %s %s\n' "$_aa" "$1"; done
}

# ---------------------------------------------------------------------------
banner "1. UC1: security missed a mistake, so a low ticket's PR reads high (runtime/R53, R55, R56, R61, R63)"
# ---------------------------------------------------------------------------
P_SEC=$(tpol "$T_SEC")
f=$(tk 'Tier: implementer' 'Risk: low' 'Risk-confidence: medium')
_before=$(git -C "$R" status --porcelain)
rule "$P_SEC" main uc1 --pr 910 --ticket 905 --ticket-file "$f"
expect_status 0 "runtime/R53, runtime/R68: the rule exits 0 on a high verdict"
WANT='effective: high unlearned
planner: low
rule: high unlearned
area: security unlearned
area: api-crud earned
area: pattern earned
area: simplicity earned
area: reuse-dry earned
area: test-hygiene earned
switch: on'
[ "$T_OUT" = "$WANT" ] && pass "runtime/R53, runtime/R55, runtime/R56, runtime/R61: UC1's lines, in order and nothing else — security's missed 1 of 20 is unlearned, the five areas at 20 settled landings, no miss and precision 1.00 are earned" ||
	fail "runtime/R53: the rule printed: $(printf '%s' "$T_OUT" | tr '\n' ';') (stderr: $T_ERR)"
J=$(judges "$T_SEC")
[ "$(njudges "$T_SEC")" = 1 ] && pass "runtime/R63: one risk.judge recorded" || fail "runtime/R63: $(njudges "$T_SEC") risk.judge lines recorded"
for tok in '"outcome":"disagreed"' '"subject":"pr:#910"' '"related":"ticket:#905"' "\"head\":\"$UC1_HEAD\"" '"planner":"low"' '"rule":"high unlearned"' '"effective":"high unlearned"' '"unlearned":"security"' '"switch":"on"'; do
	case $J in *"$tok"*) pass "runtime/R63: the event carries $tok" ;; *) fail "runtime/R63: the event lacks $tok: $J" ;; esac
done
[ "$(git -C "$R" status --porcelain)" = "$_before" ] && pass "runtime/R68: the rule writes nothing in the repository" || fail "runtime/R68: the rule changed the repository: $(git -C "$R" status --porcelain)"
case "$T_OUT$T_ERR$J" in *"$MARK"*) fail "runtime/R69: text from the ticket body reached the output or the trace" ;; *) pass "runtime/R69: no text from the ticket body reaches stdout, stderr or the event" ;; esac
# R69: every printed line is closed tokens, area names, switch words.
_bad=$(printf '%s\n' "$T_OUT" | grep -vE '^(effective|planner|rule): (low|high (irreversible|security|invisible|shared-layer|unclear|unlearned|outward))$|^area: (security|api-crud|pattern|simplicity|reuse-dry|test-hygiene|none) (earned|unlearned)$|^switch: (on|tripped)$')
[ -z "$_bad" ] && pass "runtime/R69: every line printed is a closed token, an area name or a switch word" || fail "runtime/R69: lines outside the closed set: $_bad"

# runtime/R64: the same head again records nothing.
rule "$P_SEC" main uc1 --pr 910 --ticket 905 --ticket-file "$f"
expect_status 0 "runtime/R64: a second run exits 0"
[ "$T_OUT" = "$WANT" ] && pass "runtime/R64: and prints the same lines" || fail "runtime/R64: the second run printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
[ "$(njudges "$T_SEC")" = 1 ] && pass "runtime/R64: a second run at the same head writes 0 lines" || fail "runtime/R64: the second run recorded again ($(njudges "$T_SEC") lines)"
# A different PR at the same head is a judgment of its own.
rule "$P_SEC" main uc1 --pr 911 --ticket-file "$f"
[ "$(njudges "$T_SEC")" = 2 ] && pass "runtime/R64: another PR at the same head records its own" || fail "runtime/R64: PR #911 recorded $(njudges "$T_SEC") total"
judges "$T_SEC" | grep -F '"pr:#911"' | grep -qF '"related"' && fail "runtime/R63: a judgment with no ticket number still named one in related" ||
	pass "runtime/R63: with no ticket number, related is left out"

# ---------------------------------------------------------------------------
banner "2. Every area earned: the planner's risk stands (runtime/R55, R61, R63)"
# ---------------------------------------------------------------------------
P_EARNED=$(tpol "$T_EARNED")
rule "$P_EARNED" main uc1 --pr 920 --ticket-file "$f"
expect_status 0 "all earned, a low ticket: exit 0"
WANT_LOW="effective: low
planner: low
rule: low
$(areas_all earned)
switch: on"
[ "$T_OUT" = "$WANT_LOW" ] && pass "runtime/R55, runtime/R61: 21 settled landings count as the most recent 20; low and low is low" ||
	fail "all earned printed: $(printf '%s' "$T_OUT" | tr '\n' ';') (stderr: $T_ERR)"
judges "$T_EARNED" | grep -F '"pr:#920"' | grep -qF '"outcome":"agreed"' && pass "runtime/R63: low and low is agreed" || fail "runtime/R63: $(judges "$T_EARNED")"
judges "$T_EARNED" | grep -F '"pr:#920"' | grep -qF '"unlearned"' && fail "runtime/R63: an all-earned verdict names unlearned areas" || pass "runtime/R63: an all-earned verdict names no unlearned area"

# UC1 7b: the planner raised it.
f2=$(tk 'Risk: high security')
rule "$P_EARNED" main uc1 --pr 921 --ticket-file "$f2"
printf '%s\n' "$T_OUT" | head -3 | tr '\n' ';' | grep -qx 'effective: high security;planner: high security;rule: low;' &&
	pass "runtime/R61: the planner's high over the rule's low is the planner's reason" ||
	fail "runtime/R61: 7b printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
judges "$T_EARNED" | grep -F '"pr:#921"' | grep -qF '"outcome":"disagreed"' && pass "runtime/R63: a planner's high against a rule's low is disagreed" || fail "runtime/R63: 7b recorded: $(judges "$T_EARNED" | grep -F '"pr:#921"')"
# Two highs with different reasons agree; the rule's reason prints.
rule "$P_SEC" main uc1 --pr 922 --ticket-file "$f2"
printf '%s\n' "$T_OUT" | head -3 | tr '\n' ';' | grep -qx 'effective: high unlearned;planner: high security;rule: high unlearned;' &&
	pass "runtime/R61: on high from both sides the rule's reason prints" ||
	fail "runtime/R61: two highs printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
judges "$T_SEC" | grep -F '"pr:#922"' | grep -qF '"outcome":"agreed"' && pass "runtime/R63: two highs with different reasons agree" || fail "runtime/R63: two highs recorded: $(judges "$T_SEC" | grep -F '"pr:#922"')"

# ---------------------------------------------------------------------------
banner "3. The planner's risk, read only through the stamp reader (runtime/R54)"
# ---------------------------------------------------------------------------
planner_line() { printf '%s\n' "$T_OUT" | sed -n 's/^planner: //p'; }
rule "$P_EARNED" main uc1 --pr 930
[ "$(planner_line)" = 'high unclear' ] && pass "runtime/R54: no ticket reads high unclear" || fail "runtime/R54: no ticket read '$(planner_line)'"
[ "$(printf '%s\n' "$T_OUT" | head -1)" = 'effective: high unclear' ] && pass "runtime/R61: and the effective risk is the planner's high unclear" || fail "runtime/R61: no ticket's effective line: $(printf '%s\n' "$T_OUT" | head -1)"
f3=$(tk 'Tier: implementer')
rule "$P_EARNED" main uc1 --pr 931 --ticket-file "$f3"
[ "$(planner_line)" = 'high unclear' ] && pass "runtime/R54: a ticket with no Risk: line reads high unclear" || fail "runtime/R54: no Risk: line read '$(planner_line)'"
grep -q '^Risk' "$f3" && fail "runtime/R54: the rule wrote into the ticket" || pass "runtime/R54: and nothing is written into the ticket"
for bad in 'Risk: high unlearned' 'Risk: medium' 'Risk: high because I say so'; do
	f4=$(tk "$bad")
	rule "$P_EARNED" main uc1 --pr 932 --ticket-file "$f4"
	[ "$T_STATUS" = 0 ] && [ "$(planner_line)" = 'high unclear' ] && pass "runtime/R54: a refused stamp ('$bad') reads high unclear, exit 0" ||
		fail "runtime/R54: '$bad' exited $T_STATUS, planner '$(planner_line)'"
done
# A ticket number, read through the stamp reader's tracker.
STUB="$SCRATCH/stub"
t_stub_gh "$STUB" "$(tk 'Tier: implementer' 'Risk: high irreversible')"
t_exec sh -c 'cd "$1" && shift && PATH="$1:$PATH" env TRACE_CONFIG="$2" LENS_SLICE_CONFIG="$3" TRACE_QUIET=1 sh "$4" main uc1 --pr 933 --ticket 905' _ "$R" "$STUB" "$P_EARNED" "$LENS" "$RULE"
[ "$(planner_line)" = 'high irreversible' ] && pass "runtime/R54: --ticket <N> reads the issue's Risk: line through the stamp reader" || fail "runtime/R54: --ticket 905 read '$(planner_line)': $T_ERR"
judges "$T_EARNED" | grep -F '"pr:#933"' | grep -qF '"related":"ticket:#905"' && pass "runtime/R63: and names ticket:#905 in related" || fail "runtime/R63: #933 recorded $(judges "$T_EARNED" | grep -F '"pr:#933"')"

# ---------------------------------------------------------------------------
banner "4. Earned is settled landings meeting both thresholds, and nothing missed in the window (runtime/R55)"
# ---------------------------------------------------------------------------
area_of() { printf '%s\n' "$T_OUT" | sed -n "s/^area: $1 //p"; }
rule "$(tpol "$T_WIN")" main uc1 --pr 940 --ticket-file "$f"
[ "$(area_of security)" = unlearned ] && [ "$(area_of pattern)" = earned ] &&
	pass "runtime/R55: a missed mistake on a landing inside the fix window makes its area unlearned at once" ||
	fail "runtime/R55: the window case printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
rule "$(tpol "$T_FEW")" main uc1 --pr 941 --ticket-file "$f"
[ "$T_OUT" = "effective: high unlearned
planner: low
rule: high unlearned
$(areas_all unlearned)
switch: on" ] && pass "runtime/R55: 19 settled landings and one inside the fix window are not a full window — every area unlearned" ||
	fail "runtime/R55: 19 settled printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
rule "$(tpol "$T_NA")" main uc1 --pr 942 --ticket-file "$f"
[ "$(printf '%s\n' "$T_OUT" | grep -c '^area: .* unlearned$')" = 6 ] && pass "runtime/R55: precision n/a is unlearned" || fail "runtime/R55: precision n/a printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
rule "$(tpol "$T_PREC")" main uc1 --pr 943 --ticket-file "$f"
[ "$(area_of test-hygiene)" = unlearned ] && [ "$(area_of security)" = earned ] &&
	pass "runtime/R55: a precision of 0.75, under the 0.80 floor, is unlearned" ||
	fail "runtime/R55: the precision case printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
t_exec sh -c 'cd "$1" && env TRACE_CONFIG="$2" LENS_SLICE_CONFIG="$3" TRACE_QUIET=1 sh "$4" record --settled' _ "$R" "$P_SEC" "$LENS" "$TRACE"
printf '%s\n' "$T_OUT" | grep -qx 'security landings 20 missed 1 held 19 judged 19 window-missed 0' &&
	printf '%s\n' "$T_OUT" | grep -qx 'test-hygiene landings 20 missed 0 held 20 judged 20 window-missed 0' &&
	pass "runtime/R55: the record reader's settled form counts each area's most recent 20 settled landings, in digits" ||
	fail "runtime/R55: record --settled printed: $(printf '%s' "$T_OUT" | tr '\n' ';') $T_ERR"

# ---------------------------------------------------------------------------
banner "5. A path in no review area is unlearned (runtime/R56)"
# ---------------------------------------------------------------------------
rule "$P_EARNED" main docs --pr 950 --ticket-file "$f"
[ "$T_OUT" = 'effective: high unlearned
planner: low
rule: high unlearned
area: none unlearned
switch: on' ] && pass "runtime/R56: a path in no area prints area: none unlearned, and the rule's risk is high unlearned" ||
	fail "runtime/R56: the docs PR printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
judges "$T_EARNED" | grep -F '"pr:#950"' | grep -qF '"unlearned":"none"' && pass "runtime/R63: the event names the area none" || fail "runtime/R63: #950 recorded $(judges "$T_EARNED" | grep -F '"pr:#950"')"
rule "$P_EARNED" main tests-only --pr 951 --ticket-file "$f"
[ "$T_OUT" = 'effective: low
planner: low
rule: low
area: test-hygiene earned
switch: on' ] && pass "runtime/R53: one area line per area the diff touches, and no other" ||
	fail "runtime/R53: the tests-only PR printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"

# ---------------------------------------------------------------------------
banner "6. Failing closed: thresholds, trace and schema (runtime/R57, R58)"
# ---------------------------------------------------------------------------
for base in nopolicy badpolicy; do
	rule "$P_EARNED" "$base" uc1 --pr 960 --ticket-file "$f"
	[ "$T_STATUS" = 0 ] && [ "$(printf '%s\n' "$T_OUT" | grep -c '^area: .* unlearned$')" = 6 ] && [ "$(printf '%s\n' "$T_OUT" | sed -n 3p)" = 'rule: high unlearned' ] &&
		pass "runtime/R57: thresholds the base cannot give ($base) make every area unlearned, exit 0" ||
		fail "runtime/R57: base $base exited $T_STATUS and printed: $(printf '%s' "$T_OUT" | tr '\n' ';') $T_ERR"
done
# Any policy-reader exit but 0 is the strictest path: a reader that fails.
OFF="$SCRATCH/trace-off.sh"
printf "TRACE_DIR=''\n" >"$OFF"
rule "$OFF" main uc1 --pr 961 --ticket-file "$f"
[ "$T_STATUS" = 0 ] && [ "$(printf '%s\n' "$T_OUT" | grep -c '^area: .* unlearned$')" = 6 ] && [ "$(printf '%s\n' "$T_OUT" | tail -1)" = 'switch: on' ] &&
	pass "runtime/R58: an unconfigured trace makes every area unlearned, prints its lines, exit 0" ||
	fail "runtime/R58: unconfigured exited $T_STATUS and printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
case $T_ERR in *unconfigured*) pass "runtime/R58: and names the cause on stderr" ;; *) fail "runtime/R58: stderr did not name the unconfigured trace: $T_ERR" ;; esac
T_SCHEMA="$SCRATCH/trace-schema"
settled "$T_SCHEMA" 1 21
printf '99\n' >"$T_SCHEMA/SCHEMA"
_sc_before=$(cat "$T_SCHEMA"/events/*.jsonl | wc -l)
rule "$(tpol "$T_SCHEMA")" main uc1 --pr 962 --ticket-file "$f"
[ "$T_STATUS" = 0 ] && [ "$(printf '%s\n' "$T_OUT" | grep -c '^area: .* unlearned$')" = 6 ] &&
	pass "runtime/R58: a SCHEMA the reader cannot judge makes every area unlearned, exit 0" ||
	fail "runtime/R58: SCHEMA 99 exited $T_STATUS and printed: $(printf '%s' "$T_OUT" | tr '\n' ';') $T_ERR"
case $T_ERR in *SCHEMA*) pass "runtime/R58: and names the schema on stderr" ;; *) fail "runtime/R58: stderr did not name the schema: $T_ERR" ;; esac
[ "$(cat "$T_SCHEMA"/events/*.jsonl | wc -l)" = "$_sc_before" ] && pass "runtime/R58: and records nothing into a trace it cannot judge" || fail "runtime/R58: the rule wrote into an unjudgeable trace"

# ---------------------------------------------------------------------------
banner "7. Every Risk value printed is checked; a refusal prints nothing (runtime/R62)"
# ---------------------------------------------------------------------------
# A vocabulary policy whose risk reasons leave out `unlearned`: the rule's
# own `high unlearned` is refused.
VP="$SCRATCH/vocab.config.sh"
sed "s/^VOCAB_RISK_REASONS=.*/VOCAB_RISK_REASONS='irreversible security invisible shared-layer unclear outward'/; s/^VOCAB_RISK_RESERVED=.*/VOCAB_RISK_RESERVED='outward'/" "$KIT/scripts/vocab.config.sh" >"$VP"
_vp_before=$(njudges "$T_SEC")
t_exec sh -c 'cd "$1" && env VOCAB_CONFIG="$2" TRACE_CONFIG="$3" LENS_SLICE_CONFIG="$4" TRACE_QUIET=1 sh "$5" main uc1 --pr 970 --ticket-file "$6"' _ "$R" "$VP" "$P_SEC" "$LENS" "$RULE" "$f"
[ "$T_STATUS" = 2 ] && [ -z "$T_OUT" ] && pass "runtime/R62: a value the checker refuses prints nothing, exit 2" || fail "runtime/R62: a refused value exited $T_STATUS and printed: $T_OUT"
[ "$(njudges "$T_SEC")" = "$_vp_before" ] && pass "runtime/R62: and records nothing" || fail "runtime/R62: a refused verdict was recorded"
grep -qF -- '--writer risk-rule' "$RULE" && pass "runtime/R62: the rule declares itself the risk rule to the checker" || fail "runtime/R62: the rule never declares --writer risk-rule"

# ---------------------------------------------------------------------------
banner "8. Caller errors are exit 2, nothing printed or recorded (runtime/R68)"
# ---------------------------------------------------------------------------
_ce_before=$(njudges "$T_EARNED")
for args in 'main uc1' 'main uc1 --pr' 'main uc1 --pr abc' 'nosuch uc1 --pr 980' 'main nosuch --pr 980' 'main uc1 --pr 980 --ticket-file /no/such/file' 'main uc1 --pr 980 --ticket 9x' 'main uc1 --pr 980 --bogus'; do
	# shellcheck disable=SC2086 # the arguments split on purpose
	rule "$P_EARNED" $args
	[ "$T_STATUS" = 2 ] && [ -z "$T_OUT" ] && pass "a caller error ($args) is exit 2, nothing on stdout" || fail "'$args' exited $T_STATUS and printed: $T_OUT"
done
[ "$(njudges "$T_EARNED")" = "$_ce_before" ] && pass "and no caller error records a judgment" || fail "a caller error recorded a judgment"

# ---------------------------------------------------------------------------
banner "9. /pr-iterate runs the rule and reports it only (process/R64, process/R65)"
# ---------------------------------------------------------------------------
PI="$KIT/.agents/skills/pr-iterate/SKILL.md"
PIR="$KIT/.agents/skills/pr-iterate/RISK.md"
grep -qF '[`RISK.md`](RISK.md)' "$PI" && pass "process/R64: /pr-iterate's step 6 opens the risk rule's branch file" || fail "process/R64: /pr-iterate never links RISK.md"
pi_flat=$(cat "$PIR" | tr '\n' ' ' | tr -s ' ')
t_text_has "$pi_flat" 'sh scripts/risk.sh <base> <head> --pr <N>' "process/R64: /pr-iterate runs the risk rule at the PR's head"
t_text_has "$pi_flat" '--ticket-file' "process/R64: with the ticket it holds"
t_text_has "$pi_flat" '--ticket-file "$scratch/ticket-body"; rc=$?' "process/R64: the step keeps the rule's exit status, so a rule that judged nothing is told from a verdict"
printf '%s\n' "$pi_flat" | grep -qF 'ticket-body" || :' && fail "process/R64: the step discards the rule's exit status" || pass "process/R64: the step never discards the rule's exit status"
t_text_has "$pi_flat" 'Risk: <the effective line> (reported only)' "process/R64: the report opens with the effective risk, marked reported only"
_pi_title=$(t_line_of "$PI" 'PR #<N> — "<title>" — iteration <i>')
_pi_risk=$(grep -n '^Risk: <the effective line> (reported only)' "$PI" | head -1 | cut -d: -f1)
_pi_warn=$(t_line_of "$PI" '⚠️ For you (behavior confirm-list, human-only):')
[ -n "$_pi_risk" ] && [ "$_pi_risk" -eq $((_pi_title + 1)) ] && [ "$_pi_warn" -gt "$_pi_risk" ] &&
	pass "process/R64: the risk line is the report's first line under its title" || fail "process/R64: the risk line is not at the top of the report (title $_pi_title, risk $_pi_risk, confirm-list $_pi_warn)"
t_text_has "$pi_flat" 'takes the same actions whatever the rule prints' "process/R65: /pr-iterate acts the same whatever the rule prints"
LAND="$KIT/scripts/land.kit.sh"
grep -qE 'risk\.sh|risk\.judge' "$LAND" && fail "process/R65: the landing script reads the risk rule" || pass "process/R65: the landing script reads nothing of the risk rule"

# ---------------------------------------------------------------------------
banner "10. The decision and the vocabulary are recorded (PRD-09 §8)"
# ---------------------------------------------------------------------------
_adr=$(grep -l 'risk rule' "$KIT"/docs/adr/[0-9]*.md 2>/dev/null | xargs grep -l 'amends ADR-0024 clause' 2>/dev/null | xargs grep -l 'risk.judge' 2>/dev/null | head -1)
[ -n "$_adr" ] && grep -qF 'clause 7' "$_adr" && grep -qF 'clause 9' "$_adr" &&
	pass "a decision record amends ADR-0024 clauses 7 and 9 for the risk rule" || fail "no record amends ADR-0024 clauses 7 and 9 for the risk rule"
for term in 'Risk rule' 'Effective risk' 'Earned' 'Unlearned'; do
	grep -qF -- "- **$term**" "$KIT/docs/domain-glossary.md" && pass "the glossary defines $term" || fail "the glossary has no entry for $term"
done

# ---------------------------------------------------------------------------
banner "11. An outward item or an unreviewed head raises the rule's risk (runtime/R59, R60)"
# ---------------------------------------------------------------------------
# UC2: the Axis-2 verdict at the head counted one outward item; every area
# earned and the ticket says low.
verdict "$T_EARNED" "$AT" 1100 1
verdict "$T_EARNED" "$AT" 1100 2 1
rule "$P_EARNED" main uc1 --pr 1100 --ticket-file "$f"
expect_status 0 "runtime/R59: an outward verdict exits 0"
[ "$T_OUT" = "effective: high outward
planner: low
rule: high outward
$(areas_all earned)
switch: on" ] && pass "runtime/R59: an Axis-2 verdict at the head with data.outward=1 over all-earned areas prints rule: high outward and effective: high outward" ||
	fail "runtime/R59: UC2 printed: $(printf '%s' "$T_OUT" | tr '\n' ';') (stderr: $T_ERR)"
J=$(judges "$T_EARNED" | grep -F '"pr:#1100"')
for tok in '"outcome":"disagreed"' '"rule":"high outward"' '"effective":"high outward"' '"planner":"low"' "\"head\":\"$UC1_HEAD\"" '"switch":"on"'; do
	case $J in *"$tok"*) pass "runtime/R59, runtime/R63: the outward judgment carries $tok" ;; *) fail "runtime/R59: the outward judgment lacks $tok: $J" ;; esac
done
case $J in *'"unlearned"'*) fail "runtime/R63: an all-earned outward judgment names unlearned areas" ;; *) pass "runtime/R63: an all-earned outward judgment names no unlearned area" ;; esac
# Two or more outward items are outward too.
verdict "$T_EARNED" "$AT" 1101 2 3
rule "$P_EARNED" main uc1 --pr 1101 --ticket-file "$f"
[ "$(printf '%s\n' "$T_OUT" | sed -n 3p)" = 'rule: high outward' ] && pass "runtime/R59: data.outward of 3 is outward" || fail "runtime/R59: outward=3 printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"

# UC2 1a: no Axis-2 verdict at the head.
rule_line() { printf '%s\n' "$T_OUT" | sed -n 3p; }
nolow() {
	[ "$T_OUT" = "effective: high unclear
planner: low
rule: high unclear
$(areas_all earned)
switch: on" ]
}
rule "$P_EARNED" main uc1 --pr 1102 --ticket-file "$f"
nolow && pass "runtime/R60: no Axis-2 verdict for the PR over all-earned areas prints rule: high unclear" ||
	fail "runtime/R60: no verdict printed: $(printf '%s' "$T_OUT" | tr '\n' ';') (stderr: $T_ERR)"
judges "$T_EARNED" | grep -F '"pr:#1102"' | grep -F '"outcome":"disagreed"' | grep -qF '"rule":"high unclear"' &&
	pass "runtime/R60, runtime/R63: and records the rule's high unclear against the planner's low, disagreed" || fail "runtime/R60: #1102 recorded $(judges "$T_EARNED" | grep -F '"pr:#1102"')"
verdict "$T_EARNED" "$OLD" 1103 2 0
rule "$P_EARNED" main uc1 --pr 1103 --ticket-file "$f"
nolow && pass "runtime/R60: an Axis-2 verdict only at an older commit is no verdict at the head — high unclear" ||
	fail "runtime/R60: an older verdict printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
verdict "$T_EARNED" "$OLD" 1104 2 1
rule "$P_EARNED" main uc1 --pr 1104 --ticket-file "$f"
nolow && pass "runtime/R59, runtime/R60: an outward item counted at an older commit is not the head's — high unclear" ||
	fail "runtime/R60: an older outward verdict printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
verdict "$T_EARNED" "$AT" 1105 1
rule "$P_EARNED" main uc1 --pr 1105 --ticket-file "$f"
nolow && pass "runtime/R60: an Axis-1 verdict alone at the head is no Axis-2 verdict — high unclear" ||
	fail "runtime/R60: an Axis-1 verdict printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
verdict "$T_EARNED" "$AT" 1106 2
rule "$P_EARNED" main uc1 --pr 1106 --ticket-file "$f"
nolow && pass "runtime/R60: an Axis-2 verdict that counts no outward items cannot rule one out — high unclear" ||
	fail "runtime/R60: a verdict with no data.outward printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
verdict "$T_EARNED" "$AT" 1107 2 0
rule "$P_EARNED" main uc1 --pr 1199 --ticket-file "$f"
nolow && pass "runtime/R60: another PR's verdict is not this PR's — high unclear" ||
	fail "runtime/R60: another PR's verdict printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
# The latest Axis-2 verdict at the head is the one read.
verdict "$T_EARNED" "$AT" 1108 2 1
verdict "$T_EARNED" "$AT" 1108 2 0
rule "$P_EARNED" main uc1 --pr 1108 --ticket-file "$f"
[ "$(rule_line)" = 'rule: low' ] && pass "runtime/R59: the latest Axis-2 verdict at the head is the one read" || fail "runtime/R59: the latest verdict read $(rule_line)"

# UC2 2a: the order is outward, then unlearned, then unclear.
P_SEC=$(tpol "$T_SEC")
verdict "$T_SEC" "$AT" 1110 2 1
rule "$P_SEC" main uc1 --pr 1110 --ticket-file "$f"
[ "$T_OUT" = 'effective: high outward
planner: low
rule: high outward
area: security unlearned
area: api-crud earned
area: pattern earned
area: simplicity earned
area: reuse-dry earned
area: test-hygiene earned
switch: on' ] && pass "runtime/R59: outward over an unlearned area prints high outward and still the unlearned area: line" ||
	fail "runtime/R59: outward with unlearned printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
judges "$T_SEC" | grep -F '"pr:#1110"' | grep -F '"rule":"high outward"' | grep -qF '"unlearned":"security"' &&
	pass "runtime/R63: and the event still names the unlearned area" || fail "runtime/R63: #1110 recorded $(judges "$T_SEC" | grep -F '"pr:#1110"')"
rule "$P_SEC" main uc1 --pr 1111 --ticket-file "$f"
[ "$(rule_line)" = 'rule: high unlearned' ] && [ "$(printf '%s\n' "$T_OUT" | head -1)" = 'effective: high unlearned' ] &&
	pass "runtime/R60: no verdict with unlearned areas prints high unlearned" || fail "runtime/R60: no verdict with unlearned printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
# The same PR and head re-judged after its review raised it records again.
rule "$P_EARNED" main uc1 --pr 1112 --ticket-file "$f"
verdict "$T_EARNED" "$AT" 1112 2 1
rule "$P_EARNED" main uc1 --pr 1112 --ticket-file "$f"
[ "$(judges "$T_EARNED" | grep -cF '"pr:#1112"')" = 2 ] && pass "runtime/R64: a review that changes the rule's risk at the same head is a judgment of its own" ||
	fail "runtime/R64: #1112 recorded $(judges "$T_EARNED" | grep -cF '"pr:#1112"') judgments"

# ---------------------------------------------------------------------------
banner "12. The kill switch: the trip marker, the base's value, never the tree or the environment (runtime/R65, R66, R67)"
# ---------------------------------------------------------------------------
# The bases: one that trips the switch, one that leaves it unset, one that
# sets it out of shape. A pull request off the tripping base resets the switch
# in its own tree; one off main trips it in its tree.
# on_base <branch> <from> <sed expression> — a base whose risk policy the
# expression rewrote.
on_base() {
	git -C "$R" checkout -q -b "$1" "$2"
	sed "$3" "$R/scripts/risk.config.sh" >"$R/scripts/risk.config.sh.new" && mv "$R/scripts/risk.config.sh.new" "$R/scripts/risk.config.sh"
	t_commit "$R" "chore: the kill switch, $1" >/dev/null
	git -C "$R" checkout -q main
}
grep -qx 'RISK_KILL_SWITCH=on' "$R/scripts/risk.config.sh" && pass "runtime/R66: the shipped risk policy sets the kill switch on" || fail "runtime/R66: the shipped risk policy carries no RISK_KILL_SWITCH=on line"
on_base tripbase main 's/^RISK_KILL_SWITCH=.*/RISK_KILL_SWITCH=tripped/'
on_base unsetswitch main '/^RISK_KILL_SWITCH=/d'
on_base badswitch main 's/^RISK_KILL_SWITCH=.*/RISK_KILL_SWITCH=maybe/'
git -C "$R" checkout -q -b untrip tripbase
sed 's/^RISK_KILL_SWITCH=.*/RISK_KILL_SWITCH=on/' "$R/scripts/risk.config.sh" >"$R/scripts/risk.config.sh.new" && mv "$R/scripts/risk.config.sh.new" "$R/scripts/risk.config.sh"
t_write "$R" scripts/foo.sh "the pull request
"
t_commit "$R" "feat: a pull request that resets the switch in its tree" >/dev/null
git -C "$R" checkout -q -b treetrip main
sed 's/^RISK_KILL_SWITCH=.*/RISK_KILL_SWITCH=tripped/' "$R/scripts/risk.config.sh" >"$R/scripts/risk.config.sh.new" && mv "$R/scripts/risk.config.sh.new" "$R/scripts/risk.config.sh"
t_write "$R" scripts/foo.sh "the pull request
"
t_commit "$R" "feat: a pull request that trips the switch in its tree" >/dev/null
git -C "$R" checkout -q main
UNTRIP_HEAD=$(git -C "$R" rev-parse untrip)
TREETRIP_HEAD=$(git -C "$R" rev-parse treetrip)
WANT_FIVE_LOW="effective: low
planner: low
rule: low
area: security earned
area: api-crud earned
area: pattern earned
area: simplicity earned
area: reuse-dry earned
switch: on"
WANT_FIVE_TRIP="effective: high unlearned
planner: low
rule: high unlearned
area: security earned
area: api-crud earned
area: pattern earned
area: simplicity earned
area: reuse-dry earned
switch: tripped"
WANT_TRIP="effective: high unlearned
planner: low
rule: high unlearned
$(areas_all earned)
switch: tripped"

# UC4 1-3: the operator creates the trip marker in the clone's git directory.
MARKER="$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)/risk-switch-tripped"
# A time at or after the new heads' commits: their verdicts are at the head.
AT2=$(date -u +%Y-%m-%dT%H:%M:%SZ)
for _pr in 1200 1201 1202 1203 1204 1205 1206 1207; do verdict "$T_EARNED" "$AT2" "$_pr" 2 0; done
: >"$MARKER"
rule "$P_EARNED" main uc1 --pr 1200 --ticket-file "$f"
expect_status 0 "runtime/R68: a tripped switch still exits 0"
[ "$T_OUT" = "$WANT_TRIP" ] && pass "runtime/R65, runtime/R66: the trip marker turns an all-earned rule: low into rule: high unlearned and switch: tripped" ||
	fail "runtime/R65: the marker printed: $(printf '%s' "$T_OUT" | tr '\n' ';') (stderr: $T_ERR)"
J=$(judges "$T_EARNED" | grep -F '"pr:#1200"')
for tok in '"switch":"tripped"' '"rule":"high unlearned"' '"effective":"high unlearned"' '"outcome":"disagreed"'; do
	printf '%s\n' "$J" | grep -qF "$tok" && pass "runtime/R65: the tripped event carries $tok" || fail "runtime/R65: #1200 recorded $J, missing $tok"
done
printf '%s\n' "$J" | grep -qF '"unlearned"' && fail "runtime/R65: a tripped switch named earned areas unlearned in the event" || pass "runtime/R65: the event names no area unlearned that earned its record"
git -C "$R" status --porcelain | grep -q . && fail "the trip marker shows in version control" || pass "runtime/R66: the trip marker is outside version control"
# The worktree of a clone reads the same marker.
git -C "$R" worktree add -q "$SCRATCH/wt-switch" uc1 2>/dev/null
t_exec sh -c 'cd "$1" || exit 99; env TRACE_CONFIG="$2" LENS_SLICE_CONFIG="$3" TRACE_QUIET=1 sh "$4" main uc1 --pr 1201 --ticket-file "$5" 2>/dev/null' _ "$SCRATCH/wt-switch" "$P_EARNED" "$LENS" "$RULE" "$f"
[ "$(printf '%s\n' "$T_OUT" | tail -1)" = 'switch: tripped' ] && pass "runtime/R66: a worktree of the clone reads the clone's trip marker" ||
	fail "runtime/R66: a worktree printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
git -C "$R" worktree remove --force "$SCRATCH/wt-switch" 2>/dev/null
# Deleting the marker resets it.
rm -f "$MARKER"
rule "$P_EARNED" main uc1 --pr 1200 --ticket-file "$f"
[ "$T_OUT" = "$WANT_LOW" ] && pass "runtime/R66: deleting the trip marker brings back rule: low and switch: on" ||
	fail "runtime/R66: after the marker printed: $(printf '%s' "$T_OUT" | tr '\n' ';') (stderr: $T_ERR)"
judges "$T_EARNED" | grep -F '"pr:#1200"' | grep -qF '"switch":"on"' && pass "runtime/R64: the reset is a judgment of its own, data.switch=on" || fail "runtime/R64: #1200 recorded $(judges "$T_EARNED" | grep -F '"pr:#1200"')"
# A rule already high keeps its own reason under a tripped switch.
: >"$MARKER"
verdict "$T_EARNED" "$AT2" 1202 2 1
rule "$P_EARNED" main uc1 --pr 1202 --ticket-file "$f"
[ "$(rule_line)" = 'rule: high outward' ] && [ "$(printf '%s\n' "$T_OUT" | tail -1)" = 'switch: tripped' ] &&
	pass "runtime/R65: a tripped switch replaces only a low; high outward stands" || fail "runtime/R65: outward under the marker printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
rm -f "$MARKER"

# UC4 1a, 2a: the base's value trips it; the pull request's tree does not reset it.
rule "$P_EARNED" tripbase untrip --pr 1203 --ticket-file "$f"
[ "$T_OUT" = "$WANT_FIVE_TRIP" ] && pass "runtime/R66, runtime/R67: a tripped base with the switch reset in the PR's tree reads tripped" ||
	fail "runtime/R67: tripbase..untrip printed: $(printf '%s' "$T_OUT" | tr '\n' ';') (stderr: $T_ERR)"
judges "$T_EARNED" | grep -F '"pr:#1203"' | grep -F "\"head\":\"$UNTRIP_HEAD\"" | grep -qF '"switch":"tripped"' && pass "runtime/R65: and records data.switch=tripped" || fail "runtime/R65: #1203 recorded $(judges "$T_EARNED" | grep -F '"pr:#1203"')"
rule "$P_EARNED" main treetrip --pr 1204 --ticket-file "$f"
[ "$T_OUT" = "$WANT_FIVE_LOW" ] && pass "runtime/R67: a switch tripped only in the PR's tree is not read — the base's on stands" ||
	fail "runtime/R67: main..treetrip printed: $(printf '%s' "$T_OUT" | tr '\n' ';') (stderr: $T_ERR)"
: "$TREETRIP_HEAD"

# UC4 2b: a value that cannot be read at the base reads tripped.
for base in unsetswitch badswitch nopolicy badpolicy; do
	rule "$P_EARNED" "$base" uc1 --pr 1205 --ticket-file "$f"
	[ "$T_STATUS" = 0 ] && [ "$(printf '%s\n' "$T_OUT" | tail -1)" = 'switch: tripped' ] && [ "$(rule_line)" = 'rule: high unlearned' ] &&
		pass "runtime/R66: a switch value the base cannot give ($base) reads tripped, exit 0" ||
		fail "runtime/R66: base $base exited $T_STATUS and printed: $(printf '%s' "$T_OUT" | tr '\n' ';') $T_ERR"
done
rule "$P_EARNED" unsetswitch uc1 --pr 1205 --ticket-file "$f"
printf '%s\n' "$T_ERR" | grep -q 'kill switch' && pass "runtime/R66: the cause is said on stderr" || fail "runtime/R66: no cause on stderr: $T_ERR"

# R67: no environment variable resets the switch or moves a threshold.
export RISK_KILL_SWITCH=on
rule "$P_EARNED" tripbase untrip --pr 1206 --ticket-file "$f"
[ "$(printf '%s\n' "$T_OUT" | tail -1)" = 'switch: tripped' ] && pass "runtime/R67: an exported RISK_KILL_SWITCH=on does not reset a tripped base" ||
	fail "runtime/R67: RISK_KILL_SWITCH=on printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
rule "$P_EARNED" unsetswitch uc1 --pr 1206 --ticket-file "$f"
[ "$(printf '%s\n' "$T_OUT" | tail -1)" = 'switch: tripped' ] && pass "runtime/R67: an exported RISK_KILL_SWITCH=on does not stand in for a base that lacks it" ||
	fail "runtime/R67: unset base with the env printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
unset RISK_KILL_SWITCH
export RISK_MISS_RATE_BELOW=100 RISK_PRECISION_FLOOR=0
rule "$P_SEC" main uc1 --pr 1207 --ticket-file "$f"
printf '%s\n' "$T_OUT" | grep -qx 'area: security unlearned' && pass "runtime/R67: exported thresholds do not move the ones the rule reads" ||
	fail "runtime/R67: exported thresholds printed: $(printf '%s' "$T_OUT" | tr '\n' ';')"
unset RISK_MISS_RATE_BELOW RISK_PRECISION_FLOOR

# The decision and the vocabulary.
grep -qF -- '- **Kill switch**' "$KIT/docs/domain-glossary.md" && pass "the glossary defines Kill switch" || fail "the glossary has no entry for Kill switch"
[ -n "$_adr" ] && grep -qF 'risk-switch-tripped' "$_adr" && grep -qF 'RISK_KILL_SWITCH' "$_adr" && pass "the risk rule's decision record names the trip marker and the switch's home" ||
	fail "the risk rule's decision record names neither the trip marker nor RISK_KILL_SWITCH"

t_done "the risk rule"
