#!/bin/sh
# tests/failure-signature.test.sh — the failure signature and the stop it
# drives, through two seams.
#
#   1. THE HELPER. `sh scripts/failure-signature.sh sign <name> [<log>|-]`
#      prints one failure signature: the check's or test's name, a tab, and
#      the first error line of its log with the digits that are only run ids
#      or timestamps written as `<id>` and `<time>`. `streak <state-file>`
#      reads this run's signatures on stdin and prints each one's count of
#      consecutive runs, keeping the counts in the state file. Every case
#      drives the script's arguments, streams and exit status — never its
#      internals.
#   2. THE SKILLS. /pr-iterate stops after three identical failures
#      (process/R18), restarts the count on a different one (process/R19);
#      /implement stops after three identical full-suite failures
#      (process/R20); either stop is traced with data.stop=repeated-failure
#      and the name, never the log text (process/R21). The sentences are
#      asserted where an agent reads them.
#
# Usage: sh tests/failure-signature.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
SIG="$KIT/scripts/failure-signature.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

TAB=$(printf '\t')

# log <file> <lines…> — a fixture log, one argument per line.
log() {
	_l_f=$1
	shift
	printf '%s\n' "$@" >"$_l_f"
}

banner "sign: two logs that differ only in a run id are one signature"

# A GitHub Actions --log-failed excerpt: job, step, the runner's timestamp,
# then the output. Run 1 and run 2 differ in the timestamps, the run id in a
# URL and a trace run id — and in nothing a fix could change.
log "$SCRATCH/run1" \
	"test (ubuntu)${TAB}Run suite${TAB}2026-10-21T10:41:40.1234567Z ok    the stamp is read" \
	"test (ubuntu)${TAB}Run suite${TAB}2026-10-21T10:41:41.0000001Z   FAIL  tests/trace.sh: line 212: expected 3, got 2 (run 18234567890, trace 20261021T104216Z-1274158-99412a4e)" \
	"test (ubuntu)${TAB}Run suite${TAB}2026-10-21T10:41:42.5Z   FAIL  a later failure"
log "$SCRATCH/run2" \
	"test (ubuntu)${TAB}Run suite${TAB}2026-10-22T08:02:13.7654321Z ok    the stamp is read" \
	"test (ubuntu)${TAB}Run suite${TAB}2026-10-22T08:02:14.9999999Z   FAIL  tests/trace.sh: line 212: expected 3, got 2 (run 18299999991, trace 20261022T080214Z-2290011-0c7d31f2)" \
	"test (ubuntu)${TAB}Run suite${TAB}2026-10-22T08:02:15.1Z   FAIL  a later failure"

t_exec sh "$SIG" sign 'test (ubuntu)' "$SCRATCH/run1"
expect_status 0 "a readable log signs, exit 0"
one=$T_OUT
t_exec sh "$SIG" sign 'test (ubuntu)' "$SCRATCH/run2"
two=$T_OUT
[ -n "$one" ] && [ "$one" = "$two" ] &&
	pass "two logs that differ only in run ids and timestamps give equal signatures" ||
	fail "run ids leaked into the signature: '$one' vs '$two'"
expect_out_has "test (ubuntu)${TAB}" "the signature opens with the name and a tab"
expect_out_has "line 212: expected 3, got 2" "the first error line's own digits are kept"
expect_out_lacks "a later failure" "only the FIRST error line is read"
expect_out_lacks "the stamp is read" "a line before the first error is not it"
expect_out_lacks "18299999991" "a run id is not in the signature"
expect_out_lacks "08:02" "a timestamp is not in the signature"
expect_out_lacks "0c7d31f2" "a trace run id's hex tail is not in the signature"
[ "$(printf '%s\n' "$one" | wc -l | tr -d ' ')" = 1 ] &&
	pass "a signature is one line" || fail "a signature spans lines: '$one'"

banner "sign: each normalisation rule, and its edge, exactly"

# sign_line <line> <expected tail> <label> — the line as the whole log, read
# from stdin; the signature must be `j`, a tab, and exactly the tail.
sign_line() {
	t_exec sh -c "printf '%s\\n' \"\$1\" | sh '$SIG' sign j" sign_line "$1"
	expect_resolved "j${TAB}$2" "$3"
}
sign_line 'error on 2026-10-21 in job' 'error on <time> in job' "a bare date is <time>"
sign_line 'error at 10:41:40 now' 'error at <time> now' "a bare time is <time>"
sign_line 'error at 10:41:40.123 now' 'error at <time> now' "a time with a fraction is one <time>"
sign_line 'error at 2026-10-21 10:41:40 now' 'error at <time> now' "a date and a time apart by a space are one <time>"
sign_line 'error stamp 20261021T104216Z end' 'error stamp <time> end' "a bare compact stamp is <time>"
sign_line 'error pid 12345 kept' 'error pid 12345 kept' "5 digits are kept: below the run-id length"
sign_line 'error pid 123456 gone' 'error pid <id> gone' "6 digits are <id>"
sign_line 'error sha abc123 kept' 'error sha abc123 kept' "6 hex characters are kept: below the hex-id length"
sign_line 'error sha abc1234 gone' 'error sha <id> gone' "7 hex characters with a digit and a letter are <id>"
sign_line 'error word deadbeef kept' 'error word deadbeef kept' "a hex-letter word with no digit is kept"

banner "sign: two logs that differ in the error are two signatures"

log "$SCRATCH/run3" \
	"test (ubuntu)${TAB}Run suite${TAB}2026-10-22T08:02:14.9999999Z   FAIL  tests/trace.sh: line 212: expected 4, got 2"
t_exec sh "$SIG" sign 'test (ubuntu)' "$SCRATCH/run3"
[ "$T_OUT" != "$one" ] &&
	pass "a different expected value is a different signature" ||
	fail "an error that changed signed the same: '$T_OUT'"
t_exec sh "$SIG" sign 'test (macos)' "$SCRATCH/run1"
[ "$T_OUT" != "$one" ] &&
	pass "the same line under another check's name is a different signature" ||
	fail "the name is not part of the signature: '$T_OUT'"

banner "sign: the first error line, its fallback, and stdin"

log "$SCRATCH/plain" "" "  building the fixture" "Error: cannot open fixture.json" "error: second"
t_exec sh "$SIG" sign 'tests/stamp.test.sh' "$SCRATCH/plain"
expect_resolved "tests/stamp.test.sh${TAB}Error: cannot open fixture.json" "an 'Error:' line is an error line, case aside"
log "$SCRATCH/noerr" "" "   " "  the runner was killed  " "after this"
t_exec sh "$SIG" sign 'job' "$SCRATCH/noerr"
expect_resolved "job${TAB}the runner was killed" "no error line: the first non-blank line, trimmed"
t_exec sh -c "printf 'not ok 3 - refuses a long line\r\n' | sh '$SIG' sign 'tap'"
expect_resolved "tap${TAB}not ok 3 - refuses a long line" "the log is read from stdin with no file, a CR dropped"
# Each match term alone, behind a non-blank line the fallback would take:
# the term, not the fallback, picked the line.
log "$SCRATCH/expected" "building" "want 3 but expected 2"
t_exec sh "$SIG" sign 'job' "$SCRATCH/expected"
expect_resolved "job${TAB}want 3 but expected 2" "'expected' alone marks the error line"
log "$SCRATCH/assert" "building" "Assert x == y"
t_exec sh "$SIG" sign 'job' "$SCRATCH/assert"
expect_resolved "job${TAB}Assert x == y" "'assert' alone marks the error line, case aside"
log "$SCRATCH/notok" "1..3" "not ok 2 - the stamp"
t_exec sh "$SIG" sign 'job' "$SCRATCH/notok"
expect_resolved "job${TAB}not ok 2 - the stamp" "'not ok' alone marks the error line"
t_exec sh -c "printf 'assertion failed: x == y\n' | sh '$SIG' sign 'tap' -"
expect_resolved "tap${TAB}assertion failed: x == y" "'-' reads stdin too"
# awk reads a bare operand shaped `name=value` as an assignment, not a file:
# a relative log path holding `=` must still be read as the log (#818).
mkdir -p "$SCRATCH/eq"
log "$SCRATCH/eq/plain.txt" "building" "error: the fixture is missing"
cp "$SCRATCH/eq/plain.txt" "$SCRATCH/eq/a=b.txt"
t_exec sh -c "cd '$SCRATCH/eq' && sh '$SIG' sign job plain.txt"
plain_sig=$T_OUT
t_exec sh -c "cd '$SCRATCH/eq' && sh '$SIG' sign job a=b.txt"
expect_resolved "$plain_sig" "a relative log path holding '=' is read as a file: the same signature as a plain path"
expect_resolved "job${TAB}error: the fixture is missing" "the '=' path's signature is the log's error line, not the empty log's"
: >"$SCRATCH/empty"
t_exec sh "$SIG" sign 'job' "$SCRATCH/empty"
expect_resolved "job${TAB}" "an empty log signs as the name alone"
long=$(awk 'BEGIN { for (i = 0; i < 400; i++) printf "x"; printf "\n" }')
log "$SCRATCH/long" "error: $long"
t_exec sh "$SIG" sign 'job' "$SCRATCH/long"
# `job`, a tab, then exactly 240 bytes of the line: the cut, not a bound.
[ "${#T_OUT}" -eq 244 ] && pass "a long error line is cut to exactly its first 240 bytes" ||
	fail "a long error line was not cut: ${#T_OUT} bytes"

banner "sign: caller errors are exit 2, nothing on stdout"

expect_exit 2 "no name" -- sh "$SIG" sign
expect_out_is "" "no name: stdout empty"
expect_exit 2 "an empty name" -- sh "$SIG" sign '' "$SCRATCH/plain"
expect_exit 2 "a name with a tab" -- sh "$SIG" sign "a${TAB}b" "$SCRATCH/plain"
expect_exit 2 "an unreadable log" -- sh "$SIG" sign 'job' "$SCRATCH/absent"
expect_err_has "absent" "the unreadable log is named"

# A name is the forge's text: a backslash in it is two characters, never an
# escape. awk's -v would turn a literal `\t` into a tab and `\n` into a
# newline, past the refusal above, and split the signature it opens.
t_exec sh "$SIG" sign 'a\tb' "$SCRATCH/plain"
expect_resolved "a\\tb${TAB}Error: cannot open fixture.json" "a literal backslash-t in a name stays two characters, one tab in the signature"
t_exec sh "$SIG" sign 'a\nb' "$SCRATCH/plain"
expect_resolved "a\\nb${TAB}Error: cannot open fixture.json" "a literal backslash-n in a name stays two characters, one line"
expect_exit 2 "an unknown verb" -- sh "$SIG" sing 'job'
expect_exit 2 "no verb" -- sh "$SIG"

banner "streak: three identical failures count to 3, a different one restarts"

state="$SCRATCH/state/streak"
mkdir -p "$SCRATCH/state"
a="test (ubuntu)${TAB}FAIL  tests/trace.sh: line 212: expected 3, got 2"
b="test (ubuntu)${TAB}FAIL  tests/trace.sh: line 212: expected 4, got 2"
c="lint${TAB}error: trailing space"

streak() { t_exec sh -c "printf '%s' \"\$1\" | sh '$SIG' streak '$state'" streak "$1"; }

streak "$a
"
expect_resolved "1${TAB}$a" "iteration 1: a new signature counts 1"
streak "$a
"
expect_resolved "2${TAB}$a" "iteration 2: the same signature counts 2"
streak "$a
"
expect_resolved "3${TAB}$a" "iteration 3: the same signature again counts 3 — the stop"
streak "$b
"
expect_resolved "1${TAB}$b" "a different error line under the same check restarts at 1 (UC1 2a)"
streak "$b
$c
"
expect_resolved "2${TAB}$b
1${TAB}$c" "each signature counts alone, in input order; a second check is its own count (UC1 3a)"
streak ""
expect_resolved "" "a run with no failure prints nothing"
streak "$b
"
expect_resolved "1${TAB}$b" "a run with no failure in between restarts the count — consecutive means consecutive"
streak "$b
$b
"
expect_resolved "2${TAB}$b" "a signature repeated within one run counts once"

# The state file's path is the caller's: a backslash in it is a character,
# so the counts are written to that file and no other.
bstate="$SCRATCH/state/pr\\t820.streak"
t_exec sh -c "printf '%s\n' \"\$1\" | sh '$SIG' streak \"\$2\"" streak "$a" "$bstate"
t_exec sh -c "printf '%s\n' \"\$1\" | sh '$SIG' streak \"\$2\"" streak "$a" "$bstate"
expect_resolved "2${TAB}$a" "a backslash in the state file's path is kept: the second run counts 2"

# A relative state file path holding `=` is read as the file, never as an
# awk assignment that would forget the count (#818).
t_exec sh -c "cd '$SCRATCH/state' && printf '%s\n' \"\$1\" | sh '$SIG' streak pr=820.streak" streak "$a"
t_exec sh -c "cd '$SCRATCH/state' && printf '%s\n' \"\$1\" | sh '$SIG' streak pr=820.streak" streak "$a"
expect_resolved "2${TAB}$a" "a relative state file path holding '=' is read as a file: the second run counts 2"

banner "streak: caller errors are exit 2"

expect_exit 2 "no state file" -- sh "$SIG" streak
t_exec sh -c "printf 'x\tline\n' | sh '$SIG' streak '$SCRATCH/no-such-dir/state'"
expect_status 2 "a state file in a missing directory is refused"
expect_out_is "" "a refused streak prints nothing"

banner "/pr-iterate's own fence counts across iterations (process/R18, R19)"

# The fence REPEATED-FAILURE.md tells /pr-iterate to run, lifted and run as
# written in a throwaway checkout: three iterations whose one red signs the
# same reach 3; a release-bound red beside it is never counted; an iteration
# with no red forgets the count.
fence=$(t_fence "$KIT/.agents/skills/pr-iterate/REPEATED-FAILURE.md" holds 'failure-signature.sh streak')
if [ -z "$fence" ]; then
	fail "process/R18: pr-iterate/REPEATED-FAILURE.md has no fence running the counter"
else
	repo="$SCRATCH/repo"
	mkdir -p "$repo/scripts"
	git init -q "$repo"
	cp "$SIG" "$repo/scripts/"
	printf '%s\n' "$fence" | sed 's/<N>/820/g' >"$SCRATCH/fence.sh"
	# iteration <log for check 1> [<log for check 2>] — one iteration's
	# scratch, two named reds at most, then the fence; its output in T_OUT.
	iteration() {
		scratch="$SCRATCH/it"
		rm -rf "$scratch"
		mkdir -p "$scratch/checks"
		: >"$scratch/checks/list"
		if [ $# -ge 1 ]; then printf 'test (ubuntu)\n' >>"$scratch/checks/list" && printf '%s\n' "$1" >"$scratch/checks/1"; fi
		if [ $# -ge 2 ]; then printf 'docs-demo\n' >>"$scratch/checks/list" && printf '%s\n' "$2" >"$scratch/checks/2"; fi
		t_exec env scratch="$scratch" sh -c 'cd "$1" && . "$2"' fence "$repo" "$SCRATCH/fence.sh"
	}
	rb='FAIL release-bound: the pinned transcript waits on v0.80.0'
	iteration 'FAIL line 212: expected 3, got 2 (run 18234567890)' "$rb"
	expect_resolved "1${TAB}test (ubuntu)${TAB}FAIL line 212: expected 3, got 2 (run <id>)" "iteration 1: count 1, the release-bound red not counted"
	iteration 'FAIL line 212: expected 3, got 2 (run 18299999991)' "$rb"
	expect_out_has "2${TAB}test (ubuntu)" "iteration 2: the same failure under a new run id counts 2"
	iteration 'FAIL line 212: expected 3, got 2 (run 18300000007)'
	expect_out_has "3${TAB}test (ubuntu)" "iteration 3: count 3 — the stop"
	iteration 'FAIL line 212: expected 4, got 2 (run 18300000099)'
	expect_out_has "1${TAB}test (ubuntu)" "a different error line restarts at 1"
	iteration
	expect_resolved "" "an iteration with no red prints nothing"
	iteration 'FAIL line 212: expected 4, got 2 (run 18300000100)'
	expect_out_has "1${TAB}test (ubuntu)" "a green iteration in between restarted the count"
	[ -f "$repo/.git/pr-iterate-820.streak" ] && pass "the count lives in the checkout's git directory" ||
		fail "no state file under the checkout's git directory"
fi

banner "the skills say the stop (process/R18 to R21)"

pri_skill=$(cat "$KIT/.agents/skills/pr-iterate/SKILL.md")
pri=$(cat "$KIT/.agents/skills/pr-iterate/REPEATED-FAILURE.md" 2>/dev/null)
imp_skill=$(cat "$KIT/.agents/skills/implement/SKILL.md")
imp=$(cat "$KIT/.agents/skills/implement/REPEATED-FAILURE.md" 2>/dev/null)

t_text_has "$pri_skill" "[\`REPEATED-FAILURE.md\`](REPEATED-FAILURE.md)" "process/R18: /pr-iterate step 3 points at the stop" "/pr-iterate SKILL.md"
t_text_has "$pri" "sh scripts/failure-signature.sh sign" "process/R18: /pr-iterate signs each failing check's own log" "pr-iterate/REPEATED-FAILURE.md"
t_text_has "$pri" "sh scripts/failure-signature.sh streak" "process/R18: /pr-iterate counts the signatures across iterations" "pr-iterate/REPEATED-FAILURE.md"
t_text_has "$pri" "On 3 consecutive iterations, push no further fix" "process/R18: the third identical failure stops the fixes" "pr-iterate/REPEATED-FAILURE.md"
t_text_has "$pri" "escalate naming the check, the count and the quoted error line" "process/R18: the escalation's three parts" "pr-iterate/REPEATED-FAILURE.md"
t_text_has "$pri" "repeated identical failure: <the check by name>, <count> iterations" "process/R18: the escalation line's spelling" "pr-iterate/REPEATED-FAILURE.md"
t_text_has "$pri" "A signature that differs from the previous iteration's restarts its count" "process/R19: a different signature restarts the count" "pr-iterate/REPEATED-FAILURE.md"
t_text_has "$pri" "The 5-iteration cap stays" "process/R18: the cap stays the backstop" "pr-iterate/REPEATED-FAILURE.md"
t_text_has "$imp_skill" "[\`REPEATED-FAILURE.md\`](REPEATED-FAILURE.md)" "process/R20: /implement step 4 points at the stop" "/implement SKILL.md"
t_text_has "$imp" "fails with the same signature 3 consecutive times, stop editing" "process/R20: the third identical suite failure stops the edits" "implement/REPEATED-FAILURE.md"
t_text_has "$imp" "report the test, the assertion and each attempt, without pushing" "process/R20: the report's parts, and no push" "implement/REPEATED-FAILURE.md"
t_text_has "$imp" "sh scripts/failure-signature.sh streak" "process/R20: /implement counts with the same helper" "implement/REPEATED-FAILURE.md"
t_text_has "$pri" "kind=pr.iterate subject=pr:#<N> outcome=stopped data.iteration=<i> data.stop=repeated-failure data.check=" "process/R21: /pr-iterate traces the stop on its own kind" "pr-iterate/REPEATED-FAILURE.md"
t_text_has "$imp" "kind=note subject=ticket:#<N> outcome=stopped data.stop=repeated-failure data.test=" "process/R21: /implement traces the stop as a note" "implement/REPEATED-FAILURE.md"
for f in pri imp; do
	eval "body=\$$f"
	t_text_has "$body" "never the log text" "process/R21: the trace line carries the name, never the log ($f)" "$f REPEATED-FAILURE.md"
done

# That each stop line is one the trace accepts is tests/trace-skills.test.sh's:
# it runs every trace line of every skill file, the siblings included.

t_done "the failure signature"
