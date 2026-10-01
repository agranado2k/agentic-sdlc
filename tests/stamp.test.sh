#!/bin/sh
# tests/stamp.test.sh — the stamp reader as a SEAM.
#
# `sh scripts/stamp.sh <issue-number>` is how /implement reads a ticket's
# `Tier:`, `Confidence:` and `Domain:` lines out of an untrusted ticket body.
# It replaces a one-line pipe in the skill's prose whose status was the
# checker's alone, so a ticket with no stamp lines and a fetch that failed
# both looked like nothing at all, and under `pipefail` a stampless ticket
# exited 1, a status the skill never defined (PR #311's last open HIGH; #331).
#
# The contract, one outcome per status, and this suite drives each red first:
#   0  the checked stamp lines on stdout, and only those;
#   2  a refused value: NOTHING on stdout, the reason on stderr, and the
#      refused line never printed anywhere — it is the ticket's text;
#   3  no stamp lines: an old ticket, not a refusal — stdout empty;
#   4  the fetch failed, after one retry — never read as a missing line.
#
# The tracker's CLI is a STUB `gh` on PATH, so every body here is a fixture
# and nothing touches the network. What is asserted is the verdict through
# the script's public surface — its argument, its exit status, its two
# streams — never its internals.
#
# Usage: sh tests/stamp.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
STAMP="$KIT/scripts/stamp.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

# The stub tracker CLI. It records every argument vector it was called with,
# fails as many times as $SCRATCH/fails-left says (printing an error, as the
# real CLI does), and otherwise prints the fixture body.
mkdir -p "$SCRATCH/bin"
cat >"$SCRATCH/bin/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_DIR/calls"
left=$(cat "$STUB_DIR/fails-left" 2>/dev/null || echo 0)
if [ "$left" -gt 0 ]; then
	echo $((left - 1)) >"$STUB_DIR/fails-left"
	echo "HTTP 502: Bad gateway (https://api.github.com/graphql)" >&2
	exit 1
fi
cat "$STUB_DIR/body"
STUB
chmod +x "$SCRATCH/bin/gh"
STUB_DIR=$SCRATCH
export STUB_DIR
PATH="$SCRATCH/bin:$PATH"
export PATH

# body <printf format> [<fails before success>] — the next fetch's fixture.
body() {
	# shellcheck disable=SC2059  # the format IS the fixture
	printf "$1" >"$SCRATCH/body"
	echo "${2:-0}" >"$SCRATCH/fails-left"
	: >"$SCRATCH/calls"
}
calls() { wc -l <"$SCRATCH/calls" | tr -d ' '; }

# stamp <args…> — the script, run as the skill runs it, from a scratch cwd so
# a payload that ran would leave its file where this suite looks for it.
stamp() {
	cd "$SCRATCH" || exit 2
	t_run_split sh "$STAMP" "$@"
	cd "$KIT" || exit 2
}

# no_pwn <label> — the payload never ran.
no_pwn() {
	[ -e "$SCRATCH/PWN" ] && { fail "$1: the payload RAN while the stamp was read"; rm -f "$SCRATCH/PWN"; } ||
		pass "$1: the payload never ran"
}

# ---------------------------------------------------------------------------
banner "Exit 0 — the checked stamp lines, and only those, on stdout"
# ---------------------------------------------------------------------------
body 'Some prose.\nTier: implementer\nConfidence: low\nDomain: content\nMore prose.\n'
stamp 331
s_assert_resolved "$(printf 'Tier: implementer\nConfidence: low\nDomain: content')" \
	"a legal stamp: exit 0, its three lines and nothing else of the body"
grep -qx 'issue view 331 --json body --jq .body' "$SCRATCH/calls" &&
	pass "the body is fetched with the tracker's CLI: gh issue view 331 --json body --jq .body" ||
	fail "the stub was not called as 'gh issue view 331 --json body --jq .body': $(cat "$SCRATCH/calls")"

body 'Tier: implementer\r\nConfidence: high\r\n'
stamp 331
s_assert_resolved "$(printf 'Tier: implementer\nConfidence: high')" \
	"a CRLF body: exit 0, and the lines come back without their carriage returns"

body 'Tier: implementer\nDomain: code\n'
stamp 331
s_assert_resolved "$(printf 'Tier: implementer\nDomain: code')" \
	"no Confidence: line — exit 0: not a stop, the ticket predates the stamp"

body 'Prose.\n- Tier: planner\n**Tier:** planner\n> Tier: planner\nTier: mechanical\n'
stamp 331
s_assert_resolved "Tier: mechanical" \
	"markdown-wrapped lines are not decision lines: only the bare one is lifted"

body 'see the Domain: code;touch PWN\nTier: implementer\n'
stamp 331
s_assert_resolved "Tier: implementer" "a key in mid-line prose is not lifted"
no_pwn "mid-line key"

# A no-break or zero-width space dressing a key: renders like a stamp, is not
# one. Run under a UTF-8 locale on purpose — the script pins its own, so a
# [[:space:]] that takes a no-break space under the caller's locale must not
# decide what is lifted.
body 'Tier: implementer\nDomain\302\240: code;touch PWN\n\342\200\213Domain: code;touch PWN\n'
cd "$SCRATCH" || exit 2
t_run_split env LC_ALL=en_US.UTF-8 sh "$STAMP" 331
cd "$KIT" || exit 2
s_assert_resolved "Tier: implementer" \
	"a key dressed in a no-break or zero-width space is never lifted, whatever the caller's locale"
no_pwn "dressed key"

# Anchored on its own location, never the caller's cwd: a foreign clone's
# checker and policy are not run from where you stand.
body 'Tier: reviewer\n'
mkdir -p "$SCRATCH/foreign/scripts"
git -C "$SCRATCH/foreign" init -q
printf '#!/bin/sh\ntouch "%s/PWN"\nexit 0\n' "$SCRATCH" >"$SCRATCH/foreign/scripts/vocab.sh"
cd "$SCRATCH/foreign" || exit 2
t_run_split sh "$STAMP" 331
cd "$KIT" || exit 2
s_assert_resolved "Tier: reviewer" "run from a foreign clone, it uses its own checker"
no_pwn "foreign checker"

# ---------------------------------------------------------------------------
banner "Exit 2 — a refused value: nothing on stdout, the line never printed"
# ---------------------------------------------------------------------------
# refused <label> <field> <payload> — status 2, empty stdout, the field named
# on stderr, and the payload absent from BOTH streams.
refused() {
	s_assert_status 2 "$1: refused, exit 2"
	[ -z "$S_OUT" ] && pass "$1: nothing on stdout" || fail "$1: stdout should be empty, got '$S_OUT'"
	case $S_ERR in
	*"x stamp: "*"$2"*) pass "$1: stderr names the refused field, $2" ;;
	*) fail "$1: stderr does not name the refused field $2: '$S_ERR'" ;;
	esac
	case "$S_OUT$S_ERR" in
	*"$3"*) fail "$1: the refused text '$3' was printed — it is the ticket's, untrusted" ;;
	*) pass "$1: the refused text is printed on neither stream" ;;
	esac
	no_pwn "$1"
}

body "Tier: implementer'; touch PWN; echo '\nConfidence: high\n"
stamp 331
refused "a quote in the tier" tier "touch PWN"

body 'Tier: implementer\302\240\n'
stamp 331
refused "a no-break space inside the tier's value" tier "$(printf '\302\240')"

body 'Tier: implementer\n domain: x;touch PWN\n'
stamp 331
refused "a lower-case, indented domain carrying a payload" domain "touch PWN"

body 'Tier: implementer\nConfidence: sure\n'
stamp 331
refused "Confidence: sure — a refused confidence is a stop" confidence "sure"

body 'Prose.\nConfidence: certainly\n'
stamp 331
refused "a refused confidence with no Tier: line — still a stop" confidence "certainly"

body 'Tier: implementer\nTier: planner\n'
stamp 331
s_assert_status 2 "two tiers, two answers: refused, exit 2"
[ -z "$S_OUT" ] && pass "two tiers: nothing on stdout" || fail "two tiers: stdout should be empty, got '$S_OUT'"
s_assert_err_has "x stamp:"

# The argument is a number, or nothing is fetched at all.
for arg in '' '331; touch PWN' '-1' '#331'; do
	body 'Tier: implementer\n'
	if [ -z "$arg" ]; then stamp; else stamp "$arg"; fi
	s_assert_status 2 "issue number '$arg': a usage error, exit 2"
	[ "$(calls)" = 0 ] && pass "issue number '$arg': the tracker was never called" ||
		fail "issue number '$arg': the tracker was called $(calls) time(s)"
	no_pwn "issue number '$arg'"
done

# ---------------------------------------------------------------------------
banner "Exit 3 — no stamp lines: an old ticket, not a refusal"
# ---------------------------------------------------------------------------
body 'A ticket written before the stamp existed.\n\n## Behavior\nIt does a thing.\n'
stamp 331
s_assert_status 3 "a body with no stamp lines: exit 3"
[ -z "$S_OUT" ] && pass "no stamp lines: nothing on stdout" || fail "no stamp lines: stdout should be empty, got '$S_OUT'"

body 'Prose.\n- Tier: planner\n**Confidence:** high\n'
stamp 331
s_assert_status 3 "a body whose only stamps are markdown-wrapped: exit 3, nothing lifted"

body ''
stamp 331
s_assert_status 3 "an empty body: exit 3"

# A checker that cannot run is not a refusal (PRD #273: the call sites
# tolerate a checker error), and nothing unchecked is ever printed: the
# script fails CLOSED into "no stamp read", and says why on stderr.
mkdir -p "$SCRATCH/bare/scripts"
cp "$STAMP" "$SCRATCH/bare/scripts/stamp.sh"
body 'Tier: planner\n'
cd "$SCRATCH" || exit 2
t_run_split sh "$SCRATCH/bare/scripts/stamp.sh" 331
cd "$KIT" || exit 2
s_assert_status 3 "the checker is gone: exit 3, the missing-line defaults — not a refusal"
[ -z "$S_OUT" ] && pass "the checker is gone: nothing unchecked on stdout" ||
	fail "the checker is gone: an unchecked line was printed: '$S_OUT'"
s_assert_err_has "vocab.sh"

# ---------------------------------------------------------------------------
banner "Exit 4 — the fetch failed: never read as a missing line"
# ---------------------------------------------------------------------------
body 'Tier: implementer\n' 1
stamp 331
s_assert_resolved "Tier: implementer" "one failed fetch, then a good one: retried once, exit 0"
[ "$(calls)" = 2 ] && pass "…the tracker was called exactly twice" || fail "…the tracker was called $(calls) time(s), not 2"

body 'Tier: implementer\n' 2
stamp 331
s_assert_status 4 "two failed fetches: exit 4, a stop — not 3, not 0"
[ -z "$S_OUT" ] && pass "a failed fetch: nothing on stdout" || fail "a failed fetch: stdout should be empty, got '$S_OUT'"
[ "$(calls)" = 2 ] && pass "…one retry, never a loop" || fail "…the tracker was called $(calls) time(s), not 2"
s_assert_err_has "x stamp:"

t_done "the stamp reader"
