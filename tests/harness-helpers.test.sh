#!/bin/sh
# tests/harness-helpers.test.sh — the folded assertion helpers as a SEAM.
#
# Ticket #405 folded three helper pairs into tests/lib.sh: t_text_has, t_fence
# and the verdict runner (t_check_run under t_verdict_is). The suites that call
# them are their oracle in the large, but a suite only ever drives the branch
# it needs — so a branch nobody drives is a claim (review of PR #450, M-5).
# This suite drives each helper in a subshell and reads what it printed: a
# helper that should fail must print FAIL, and one that should pass must not.
# The vacuous-pass cases are the point (M-1): a refusal assertion with no
# verdict, no check or no project to run in must fail loudly, never pass.
#
# Usage: sh tests/harness-helpers.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

# printed <command...> — what a helper printed, run in a subshell so its pass
# or fail never counts here; this suite counts only its own verdict on it.
printed() { ("$@") 2>&1; }
# says <label> <want ok|FAIL> <command...> — the helper printed exactly one
# assertion line, and it was <want>.
says() {
	_label=$1 _want=$2
	shift 2
	_out=$(printed "$@")
	_n=$(printf '%s\n' "$_out" | grep -cE '^  (ok  |FAIL)  ')
	if [ "$_n" -eq 1 ] && printf '%s\n' "$_out" | grep -q "^  $_want "; then
		pass "$_label"
	else
		fail "$_label — wanted one '$_want' line, the helper printed: $(printf '%s' "$_out" | tr '\n' '|')"
	fi
}

# ---------------------------------------------------------------------------
banner "1. t_text_has — one line per token, the block named on a fail"
# ---------------------------------------------------------------------------
says "a token in the text passes" ok t_text_has "alpha beta" "beta" "why"
says "a token not in the text fails" FAIL t_text_has "alpha beta" "gamma" "why"
says "the token is a fixed string, never a pattern" FAIL t_text_has "alpha beta" "a.pha" "why"
out=$(printed t_text_has "alpha" "gamma" "why" "the block")
case $out in
*"FAIL  the block never says 'gamma' — why") pass "<whose> names the block in the fail line" ;;
*) fail "<whose> is not in the fail line: $out" ;;
esac
out=$(printed t_text_has "alpha" "gamma" "why")
case $out in
*"FAIL  never says 'gamma' — why") pass "with no <whose>, the fail line opens on 'never says'" ;;
*) fail "the fail line without <whose> is: $out" ;;
esac

# ---------------------------------------------------------------------------
banner "2. t_fence — the two modes, and nothing else"
# ---------------------------------------------------------------------------
DOC="$SCRATCH/doc.md"
cat >"$DOC" <<'EOF'
```sh
first() { :; }
```

```bash
step two
```

```sh
step three
second() { :; }
```
EOF
[ "$(t_fence "$DOC" holds "second()")" = "step three
second() { :; }" ] && pass "holds: the first sh fence holding the needle, verbatim" ||
	fail "holds lifted: $(t_fence "$DOC" holds "second()" | tr '\n' '|')"
[ "$(t_fence "$DOC" opens '^step t')" = "step three
second() { :; }" ] && pass "opens: the first sh fence whose first line matches" ||
	fail "opens lifted: $(t_fence "$DOC" opens '^step t' | tr '\n' '|')"
[ "$(t_fence "$DOC" opens '^step two' bash)" = "step two" ] &&
	pass "the language picks the fence's opening" || fail "the bash fence was not lifted"
[ -z "$(t_fence "$DOC" opens 'second')" ] &&
	pass "opens matches the first line only — a later line never picks the fence" ||
	fail "opens picked a fence by a line other than its first"
[ -z "$(t_fence "$DOC" holds "no such needle")" ] &&
	pass "no fence holds the needle: nothing printed, for the caller to assert on" ||
	fail "a needle no fence holds lifted text"
out=$(t_fence "$DOC" hold "second()" 2>"$SCRATCH/fence.err")
st=$?
[ "$st" -ne 0 ] && [ -z "$out" ] && grep -q 'holds|opens' "$SCRATCH/fence.err" &&
	pass "an unknown mode is refused, naming the two it takes" ||
	fail "an unknown mode: status $st, printed '$out', said '$(cat "$SCRATCH/fence.err")'"

# ---------------------------------------------------------------------------
banner "3. t_check_run — the frame a lifted check runs in"
# ---------------------------------------------------------------------------
PROJECT="$SCRATCH/project"
mkdir -p "$PROJECT/sub"
CHECK="$SCRATCH/check.sh"
cat >"$CHECK" <<'EOF'
where() { pwd; printf 'config=%s\n' "${VOCAB_CONFIG:-unset}"; echo to-stderr >&2; return "${1:-0}"; }
EOF
VOCAB_CONFIG=/leaked t_check_run "$CHECK" where 0
[ "$(head -1 "$SCRATCH/verdict.out")" = "$(cd "$PROJECT" && pwd)" ] &&
	pass "the check runs from \$PROJECT" || fail "the check ran from $(head -1 "$SCRATCH/verdict.out")"
grep -qx 'config=unset' "$SCRATCH/verdict.out" &&
	pass "VOCAB_CONFIG is unset unless POLICY_FOR names a policy file" || fail "a caller's VOCAB_CONFIG leaked into the check"
grep -qx 'to-stderr' "$SCRATCH/verdict.err" && pass "stderr lands in verdict.err" || fail "stderr was not captured"
WHERE=sub POLICY_FOR=/the/policy t_check_run "$CHECK" where 3
st=$?
[ "$st" -eq 3 ] && pass "the status is the function's" || fail "the status was $st, not the function's 3"
[ "$(head -1 "$SCRATCH/verdict.out")" = "$(cd "$PROJECT/sub" && pwd)" ] &&
	pass "\$WHERE moves the check below \$PROJECT" || fail "WHERE was not honoured"
grep -qx 'config=/the/policy' "$SCRATCH/verdict.out" &&
	pass "POLICY_FOR is exported as VOCAB_CONFIG" || fail "POLICY_FOR did not reach the check"

# ---------------------------------------------------------------------------
banner "4. t_verdict_is — the verdict asserted, never a vacuous pass"
# ---------------------------------------------------------------------------
cat >"$CHECK" <<'EOF'
answer() { [ "$1" = yes ]; }
EOF
verdict() { t_check_run "$CHECK" answer "$1"; }
says "accepted, and the check accepts: a pass" ok t_verdict_is accepted "l" yes
says "accepted, but the check refuses: a fail" FAIL t_verdict_is accepted "l" no
says "refused, and the check refuses: a pass" ok t_verdict_is refused "l" no
says "refused, but the check accepts: a fail" FAIL t_verdict_is refused "l" yes
out=$(T_VERDICT_PREFIX="skill — " printed t_verdict_is accepted "l" yes)
case $out in *"ok    skill — l") pass "T_VERDICT_PREFIX goes before the label" ;; *) fail "the prefixed label: $out" ;; esac
on_refusal() { pass "the callback got: $1"; }
out=$(T_VERDICT_PREFIX="skill — " T_VERDICT_REFUSED=on_refusal printed t_verdict_is refused "l" no)
case $out in *"ok    the callback got: skill — l") pass "T_VERDICT_REFUSED is handed the full label, and its line is the pass" ;; *) fail "the refusal callback: $out" ;; esac

# The vacuous cases (M-1): each would read as a refusal — a missing function
# is status 127, a missing directory a failed cd — and pass every `refused`.
# Each case runs in a subshell (printed), so what it unsets stays there.
no_verdict() { unset -f verdict; t_verdict_is "$1" "l" no; }
no_check() { CHECK=$2; t_verdict_is "$1" "l" yes; }
no_project() { PROJECT=$2; t_verdict_is "$1" "l" no; }
printf 'stale stream from an earlier call\n' >"$SCRATCH/verdict.out"
says "no verdict function: a refusal assertion fails" FAIL no_verdict refused
out=$(printed no_verdict accepted)
case $out in
*"stale stream"*) fail "no verdict function: the fail line quotes an earlier call's streams: $out" ;;
*FAIL*"verdict"*) pass "no verdict function: the fail line says so, and quotes no earlier call" ;;
*) fail "no verdict function, accepted: $out" ;;
esac
says "no lifted check (empty): a refusal assertion fails" FAIL no_check refused ""
says "no lifted check (missing): a refusal assertion fails" FAIL no_check refused "$SCRATCH/no-such-check"
out=$(printed no_check accepted "$SCRATCH/no-such-check")
case $out in
*"stale stream"*) fail "no lifted check: the fail line quotes an earlier call's streams: $out" ;;
*FAIL*"check"*) pass "no lifted check: the fail line says so, and quotes no earlier call" ;;
*) fail "no lifted check, accepted: $out" ;;
esac
says "no project to run in: a refusal assertion fails" FAIL no_project refused ""
says "a project that is not a directory: a refusal assertion fails" FAIL no_project refused "$SCRATCH/no-such-project"
says "…and an accepted assertion fails too" FAIL no_project accepted "$SCRATCH/no-such-project"

t_done "harness helpers"
