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
#   4  the fetch failed, after one retry — never read as a missing line;
#   5  too many stamp lines — more than 8 of one key: a stop, stdout empty.
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
# The checker's policy is the kit's own unless a case below names one: a
# VOCAB_CONFIG in the caller's environment would decide every verdict here.
unset VOCAB_CONFIG

# The stub tracker CLI. It records every argument vector it was called with,
# fails as many times as $SCRATCH/fails-left says (printing an error, as the
# real CLI does), and otherwise prints the fixture body — t_stub_gh's frame
# (tests/lib.sh), with this prelude.
cat >"$SCRATCH/gh.prelude" <<'STUB'
printf '%s\n' "$*" >>"$STUB_DIR/calls"
# A signal mid-fetch, delivered to the script — the stub's parent — while it
# waits on the tracker.
[ -e "$STUB_DIR/signal" ] && kill -"$(cat "$STUB_DIR/signal")" "$PPID"
left=$(cat "$STUB_DIR/fails-left" 2>/dev/null || echo 0)
if [ "$left" -gt 0 ]; then
	echo $((left - 1)) >"$STUB_DIR/fails-left"
	echo "HTTP 502: Bad gateway (https://api.github.com/graphql)" >&2
	exit 1
fi
STUB
t_stub_gh "$SCRATCH/bin" "$SCRATCH/body" "$SCRATCH/gh.prelude"
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
	t_exec sh "$STAMP" "$@"
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
expect_resolved "$(printf 'Tier: implementer\nConfidence: low\nDomain: content')" \
	"a legal stamp: exit 0, its three lines and nothing else of the body"
grep -qx 'issue view 331 --json body --jq .body' "$SCRATCH/calls" &&
	pass "the body is fetched with the tracker's CLI: gh issue view 331 --json body --jq .body" ||
	fail "the stub was not called as 'gh issue view 331 --json body --jq .body': $(cat "$SCRATCH/calls")"

# A Targets: line (process/R25, #802) is a stamp line: lifted beside the
# other three, checked against its grammar, printed only once it passed.
body 'Tier: implementer\nTargets: kind=finding.raise data.agent=security data.severity=high\n'
stamp 802
expect_resolved "$(printf 'Tier: implementer\nTargets: kind=finding.raise data.agent=security data.severity=high')" \
	"a Targets: line is lifted and checked like any stamp line"
body "Tier: implementer\nTargets: kind=finding.raise data.agent=x';touch PWN;'\n"
stamp 802
expect_status 2 "a Targets: line outside its grammar is refused, nothing printed"
expect_err_has "the targets line is refused"
no_pwn "refused Targets: line"

# A Class: line (#819) is a stamp line too: /implement records it as
# ticket.start's data.class, so it leaves only once the checker passed it.
body 'Tier: implementer\nClass: toil\n'
stamp 819
expect_resolved "$(printf 'Tier: implementer\nClass: toil')" \
	"a Class: line is lifted and checked like any stamp line"
body "Tier: implementer\nClass: toil';touch PWN;'\n"
stamp 819
expect_status 2 "a Class: line outside its vocabulary is refused, nothing printed"
expect_err_has "the class line is refused"
no_pwn "refused Class: line"
# …and it is bounded like the others: nine Class: lines are exit 5, the key
# named, nothing checked.
body "$(awk 'BEGIN { print "Tier: implementer"; for (i = 0; i < 9; i++) print "Class: toil" }')\n"
stamp 819
expect_status 5 "nine Class: lines are past the bound: exit 5, a stop"
expect_err_has "9 class lines"

body 'Tier: implementer\r\nConfidence: high\r\n'
stamp 331
expect_resolved "$(printf 'Tier: implementer\nConfidence: high')" \
	"a CRLF body: exit 0, and the lines come back without their carriage returns"

body 'Tier: implementer\nDomain: code\n'
stamp 331
expect_resolved "$(printf 'Tier: implementer\nDomain: code')" \
	"no Confidence: line — exit 0: not a stop, the ticket predates the stamp"

body 'Prose.\n- Tier: planner\n**Tier:** planner\n> Tier: planner\nTier: mechanical\n'
stamp 331
expect_resolved "Tier: mechanical" \
	"markdown-wrapped lines are not decision lines: only the bare one is lifted"

body 'see the Domain: code;touch PWN\nTier: implementer\n'
stamp 331
expect_resolved "Tier: implementer" "a key in mid-line prose is not lifted"
no_pwn "mid-line key"

# A no-break or zero-width space dressing a key: renders like a stamp, is not
# one. Run under a UTF-8 locale on purpose — the script pins its own, so a
# [[:space:]] that takes a no-break space under the caller's locale must not
# decide what is lifted.
body 'Tier: implementer\nDomain\302\240: code;touch PWN\n\342\200\213Domain: code;touch PWN\n'
cd "$SCRATCH" || exit 2
t_exec env LC_ALL=en_US.UTF-8 sh "$STAMP" 331
cd "$KIT" || exit 2
expect_resolved "Tier: implementer" \
	"a key dressed in a no-break or zero-width space is never lifted, whatever the caller's locale"
no_pwn "dressed key"
# …and a body the locale DECIDES, so the pin itself is held: glibc's UTF-8
# [[:space:]] takes an em space (U+2003), its C one does not. Pinned, a key
# dressed in one is never lifted — exit 0, the Tier: line alone; unpinned, it
# is lifted and refused — exit 2. The no-break space above cannot tell the
# two apart: glibc counts it as space in neither locale.
printf '\342\200\203' | LC_ALL=C.UTF-8 grep -q '^[[:space:]]$' &&
	pass "this host's C.UTF-8 counts an em space as [[:space:]] — the body below is one the locale decides" ||
	fail "this host's C.UTF-8 does not count an em space as [[:space:]] — the locale pin goes untested here"
body 'Tier: implementer\nDomain\342\200\203: x;touch PWN\n'
cd "$SCRATCH" || exit 2
t_exec env LC_ALL=C.UTF-8 sh "$STAMP" 331
cd "$KIT" || exit 2
expect_resolved "Tier: implementer" \
	"a key dressed in an em space, under a caller's C.UTF-8: never lifted — the script's own C locale decides"
no_pwn "em-space key"

# A NUL anywhere in the body makes GNU grep read it as binary and lift
# nothing — a stamped ticket read as an old one. A NUL is a line break to the
# script: the stamp beside one is read, and a NUL inside a value splits it,
# so the value is refused — never glued back together into a legal word.
body 'Prose with a NUL \000 in it.\nTier: mechanical\n'
stamp 331
expect_resolved "Tier: mechanical" "a NUL elsewhere in the body: the stamp is still read, exit 0"
body 'Tier: impl\000ementer\n'
stamp 331
expect_status 2 "a NUL inside the tier's value: the value is split and refused, exit 2"

# Anchored on its own location, never the caller's cwd: a foreign clone's
# checker and policy are not run from where you stand.
body 'Tier: reviewer\n'
mkdir -p "$SCRATCH/foreign/scripts"
git -C "$SCRATCH/foreign" init -q
printf '#!/bin/sh\ntouch "%s/PWN"\nexit 0\n' "$SCRATCH" >"$SCRATCH/foreign/scripts/vocab.sh"
cd "$SCRATCH/foreign" || exit 2
t_exec sh "$STAMP" 331
cd "$KIT" || exit 2
expect_resolved "Tier: reviewer" "run from a foreign clone, it uses its own checker"
no_pwn "foreign checker"

# ---------------------------------------------------------------------------
banner "Exit 2 — a refused value: nothing on stdout, the line never printed"
# ---------------------------------------------------------------------------
# refused <label> <field> <payload> — status 2, empty stdout, the field named
# on stderr, and the payload absent from BOTH streams.
refused() {
	expect_status 2 "$1: refused, exit 2"
	[ -z "$T_OUT" ] && pass "$1: nothing on stdout" || fail "$1: stdout should be empty, got '$T_OUT'"
	case $T_ERR in
	*"x stamp: "*"$2"*) pass "$1: stderr names the refused field, $2" ;;
	*) fail "$1: stderr does not name the refused field $2: '$T_ERR'" ;;
	esac
	case "$T_OUT$T_ERR" in
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
expect_status 2 "two tiers, two answers: refused, exit 2"
[ -z "$T_OUT" ] && pass "two tiers: nothing on stdout" || fail "two tiers: stdout should be empty, got '$T_OUT'"
# Each line passes alone, so no field is named: the stderr line says the
# lines are refused together, and quotes neither value.
expect_err_has "the stamp lines are refused together"
expect_err_lacks "the tier line is refused"
expect_err_lacks "implementer"
expect_err_lacks "planner"

# The refusal names the refused field's OWN vocabulary: a declared field whose
# name merely starts with the key is another field, never listed under it.
cat >"$SCRATCH/tiernote.config.sh" <<'EOF2'
VOCAB_FIELDS='tier tier-note'
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_TIER_NOTE='alpha'
EOF2
body 'Tier: bogus\n'
cd "$SCRATCH" || exit 2
t_exec env VOCAB_CONFIG="$SCRATCH/tiernote.config.sh" sh "$STAMP" 331
cd "$KIT" || exit 2
expect_status 2 "a refused tier beside a field named tier-note: exit 2"
expect_err_has "the tier vocabulary (planner implementer mechanical reviewer)"
expect_err_lacks "alpha"

# The argument is a number, or nothing is fetched at all.
# usage_refused <label> — exit 2, the usage line on stderr, nothing fetched.
usage_refused() {
	expect_status 2 "$1: a usage error, exit 2"
	expect_err_has "usage: sh scripts/stamp.sh <issue-number>"
	[ "$(calls)" = 0 ] && pass "$1: the tracker was never called" ||
		fail "$1: the tracker was called $(calls) time(s)"
	no_pwn "$1"
}
for arg in '' '331; touch PWN' '-1' '#331' '33a1'; do
	body 'Tier: implementer\n'
	stamp "$arg"
	usage_refused "issue number '$arg'"
done
body 'Tier: implementer\n'
stamp
usage_refused "no argument at all"
body 'Tier: implementer\n'
stamp 331 332
usage_refused "two issue numbers"

# ---------------------------------------------------------------------------
banner "Exit 3 — no stamp lines: an old ticket, not a refusal"
# ---------------------------------------------------------------------------
body 'A ticket written before the stamp existed.\n\n## Behavior\nIt does a thing.\n'
stamp 331
expect_status 3 "a body with no stamp lines: exit 3"
[ -z "$T_OUT" ] && pass "no stamp lines: nothing on stdout" || fail "no stamp lines: stdout should be empty, got '$T_OUT'"

body 'Prose.\n- Tier: planner\n**Confidence:** high\n'
stamp 331
expect_status 3 "a body whose only stamps are markdown-wrapped: exit 3, nothing lifted"

body ''
stamp 331
expect_status 3 "an empty body: exit 3"

# A checker that cannot run is not a refusal (PRD #273: the call sites
# tolerate a checker error), and nothing unchecked is ever printed: the
# script fails CLOSED into "no stamp read", and says why on stderr.
mkdir -p "$SCRATCH/bare/scripts"
cp "$STAMP" "$SCRATCH/bare/scripts/stamp.sh"
body 'Tier: planner\n'
cd "$SCRATCH" || exit 2
t_exec sh "$SCRATCH/bare/scripts/stamp.sh" 331
cd "$KIT" || exit 2
expect_status 3 "the checker is gone: exit 3, the missing-line defaults — not a refusal"
[ -z "$T_OUT" ] && pass "the checker is gone: nothing unchecked on stdout" ||
	fail "the checker is gone: an unchecked line was printed: '$T_OUT'"
expect_err_has "vocab.sh"
# …asked before anything is lifted: a body with no stamp lines, under a
# checker that is gone, says the checker is gone — not that the ticket is old.
body 'A ticket written before the stamp existed.\n'
cd "$SCRATCH" || exit 2
t_exec sh "$SCRATCH/bare/scripts/stamp.sh" 331
cd "$KIT" || exit 2
expect_status 3 "the checker is gone, no stamp lines either: exit 3"
expect_err_has "is gone from this project"

# stamp_under <policy file> — the script, with VOCAB_CONFIG naming the policy.
stamp_under() {
	cd "$SCRATCH" || exit 2
	t_exec env VOCAB_CONFIG="$1" sh "$STAMP" 331
	cd "$KIT" || exit 2
}
# unusable <label> <payload> — exit 3, nothing on stdout, stderr says the
# checker could not run and never calls it a refusal, the payload nowhere.
unusable() {
	expect_status 3 "$1: the checker cannot run — exit 3, not a refusal"
	[ -z "$T_OUT" ] && pass "$1: nothing on stdout" || fail "$1: stdout should be empty, got '$T_OUT'"
	expect_err_has "cannot run"
	expect_err_lacks "refused"
	case "$T_OUT$T_ERR" in
	*"$2"*) fail "$1: the ticket's text '$2' was printed" ;;
	*) pass "$1: the ticket's text is printed on neither stream" ;;
	esac
}

# A checker that is present but cannot answer is the same case as one that is
# gone: its exit 2 on a policy error is not a refusal of the ticket. The script
# asks it `fields` first, and a non-zero there is "checker unusable".
body 'Tier: implementer\nConfidence: high\nDomain: x;touch PWN\n'
stamp_under /nonexistent
unusable "VOCAB_CONFIG names a file that does not exist" "touch PWN"
printf 'VOCAB_FIELDS=(\n' >"$SCRATCH/broken.config.sh"
stamp_under "$SCRATCH/broken.config.sh"
unusable "a policy file that does not parse" "touch PWN"
# One that answers `fields` and dies on the check itself: only a 2 from the
# check of the lines is a refusal, any other failure is the checker's.
cat >"$SCRATCH/dies.config.sh" <<'EOF'
VOCAB_FIELDS='tier confidence domain'
VOCAB_OPEN='domain'
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_CONFIDENCE='low medium high'
VOCAB_DOMAIN='code'
case ${1:-check} in fields) ;; *) exit 5 ;; esac
EOF
body 'Tier: implementer\nConfidence: high\n'
stamp_under "$SCRATCH/dies.config.sh"
expect_status 3 "a checker that answers fields and dies on the check (exit 5): exit 3, not a refusal"
[ -z "$T_OUT" ] && pass "…nothing on stdout" || fail "…stdout should be empty, got '$T_OUT'"
expect_err_lacks "refused"
no_pwn "an unusable checker"

# ---------------------------------------------------------------------------
banner "An undeclared field: never checked, so never printed"
# ---------------------------------------------------------------------------
# The checker ignores a line whose field its policy does not declare — so a
# project whose policy drops `domain` would pass `Domain: x;touch PWN` at exit
# 0, and the script would print it as a checked stamp line. The script asks
# the checker which fields it declares before lifting, and a lifted line of
# an undeclared field is named on stderr, never printed: exit 0 only when the
# Tier: line was checked and printed, else 3.
cat >"$SCRATCH/nodomain.config.sh" <<'EOF'
VOCAB_FIELDS='tier confidence'
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_CONFIDENCE='low medium high'
EOF
body 'Tier: implementer\nDomain: x;touch PWN\n'
stamp_under "$SCRATCH/nodomain.config.sh"
expect_resolved "Tier: implementer" \
	"the reviewer's reproduction — Domain: x;touch PWN under a policy with no domain: exit 0, the Tier: line alone"
expect_err_has "the domain line names a field this project's policy does not declare"
case "$T_OUT$T_ERR" in
*"touch PWN"*) fail "the undeclared line was printed: '$T_OUT$T_ERR'" ;;
*) pass "the undeclared line is printed on neither stream" ;;
esac
no_pwn "undeclared domain"

body 'Confidence: high\nDomain: x;touch PWN\n'
stamp_under "$SCRATCH/nodomain.config.sh"
expect_status 3 "an undeclared line dropped and no Tier: line checked: exit 3"
[ -z "$T_OUT" ] && pass "…nothing on stdout" || fail "…stdout should be empty, got '$T_OUT'"

cat >"$SCRATCH/notier.config.sh" <<'EOF'
VOCAB_FIELDS='confidence domain'
VOCAB_OPEN='domain'
VOCAB_CONFIDENCE='low medium high'
VOCAB_DOMAIN='code'
EOF
body 'Tier: x;touch PWN\nConfidence: high\nDomain: code\n'
stamp_under "$SCRATCH/notier.config.sh"
expect_status 3 "a policy that declares no tier: the Tier: line is never checked, so exit 3"
[ -z "$T_OUT" ] && pass "…nothing on stdout, not even the lines that were checked" ||
	fail "…stdout should be empty, got '$T_OUT'"
expect_err_has "the tier line names a field this project's policy does not declare"
expect_err_lacks "touch PWN"

# ---------------------------------------------------------------------------
banner "Exit 5 — too many stamp lines: the lift is bounded, per key"
# ---------------------------------------------------------------------------
# The lift reads by KEY, and the checker's work is linear in the lines it is
# handed: a body carrying 2,000 `Tier:` lines cost about 30 CPU-seconds and
# came back at exit 0 with all 2,000 printed (PR #382). The script lifts at
# most 8 lines of any one key — enough that a field written twice with two
# values still reaches the checker and is refused — and a body with more is a
# stop of its own: exit 5, nothing printed, stderr naming the key and the
# count, never the lines.
#
# stamp_cpu_ms — the CPU milliseconds of one run of the script on the current
# fixture, read by tests/lib.sh's t_cpu_ms (CPU time, never the wall clock, so
# a loaded host cannot redden it), or "unmeasured".
# Called in $(...), so its cd stays there; the run's status was asserted on
# the run before it, and this one is measured only.
stamp_cpu_ms() { cd "$SCRATCH" && t_cpu_ms sh "$STAMP" 331; }
STAMP_BOUND_MS=1500 # one run on 2,000 Tier: lines: bounded ~180, unbounded ~28,000
body "$(awk 'BEGIN { for (i = 0; i < 2000; i++) printf "Tier: implementer\\n" }')"
stamp 331
expect_status 5 "2,000 Tier: lines: exit 5, too many stamp lines — not a refusal, not a stamp"
[ -z "$T_OUT" ] && pass "2,000 Tier: lines: nothing on stdout" ||
	fail "2,000 Tier: lines: stdout should be empty, got $(printf '%s' "$T_OUT" | grep -c '') line(s)"
expect_err_has "too many stamp lines"
expect_err_has "2000 tier lines"
expect_err_lacks "implementer"
expect_err_lacks "refused"
cpu_ms=$(stamp_cpu_ms)
case $cpu_ms in
*[!0-9]* | "") fail "2,000 Tier: lines — the shell's \`times\` gave no children's CPU time to read ('$cpu_ms')" ;;
*)
	[ "$cpu_ms" -le "$STAMP_BOUND_MS" ] && pass "2,000 Tier: lines cost ${cpu_ms}ms of CPU — within ${STAMP_BOUND_MS}ms" ||
		fail "2,000 Tier: lines cost ${cpu_ms}ms of CPU — over the ${STAMP_BOUND_MS}ms budget"
	;;
esac

# The bound is per key, whatever its case: nine lines of one key spelled
# three ways are nine lines of that key.
body 'Tier: implementer\ntier: implementer\nTIER: implementer\nTier: implementer\nTier: implementer\nTier: implementer\nTier: implementer\nTier: implementer\n  Tier: implementer\n'
stamp 331
expect_status 5 "nine Tier: lines in three cases: exit 5"
expect_err_has "9 tier lines"
[ -z "$T_OUT" ] && pass "nine Tier: lines: nothing on stdout" || fail "nine Tier: lines: stdout should be empty, got '$T_OUT'"

# Eight of one key is within the bound, and reaches the checker: eight equal
# lines pass, and eight carrying two values are refused together, exit 2.
body 'Tier: implementer\nTier: implementer\nTier: implementer\nTier: implementer\nTier: implementer\nTier: implementer\nTier: implementer\nTier: implementer\nConfidence: high\nDomain: code\n'
stamp 331
expect_status 0 "eight Tier: lines, one value: within the bound, checked, exit 0"
body 'Tier: implementer\nTier: implementer\nTier: implementer\nTier: implementer\nTier: implementer\nTier: implementer\nTier: implementer\nTier: planner\n'
stamp 331
expect_status 2 "eight Tier: lines, two values: within the bound, so the checker refuses them, exit 2"
expect_err_has "the stamp lines are refused together"

# Eight of each of the three keys is twenty-four lines, and within the bound:
# it is per key, never a total.
body "$(awk 'BEGIN { for (i = 0; i < 8; i++) printf "Tier: implementer\\nConfidence: high\\nDomain: code\\n" }')"
stamp 331
expect_status 0 "eight lines of each key: the bound is per key, never a total — exit 0"

# Two keys past the bound: both named, each with its count, in one line —
# in key order, so the message is the same whatever order awk counted in.
body "$(awk 'BEGIN { for (i = 0; i < 9; i++) printf "Tier: implementer\\nConfidence: high\\n" }')"
stamp 331
expect_status 5 "nine Tier: and nine Confidence: lines: exit 5"
expect_err_has "9 confidence lines, 9 tier lines"

# The bound counts what is LIFTED, before the policy is asked which fields it
# declares: nine lines of a field this project does not declare are still
# nine lines the script read, and still exit 5 — never dropped one by one.
body "$(awk 'BEGIN { printf "Tier: implementer\\n"; for (i = 0; i < 9; i++) printf "Domain: x;touch PWN\\n" }')"
stamp_under "$SCRATCH/nodomain.config.sh"
expect_status 5 "nine lines of an undeclared Domain: they count toward the bound, exit 5"
expect_err_has "9 domain lines"
[ -z "$T_OUT" ] && pass "…nothing on stdout, not even the Tier: line" || fail "…stdout should be empty, got '$T_OUT'"
expect_err_lacks "touch PWN"
no_pwn "nine undeclared lines"

# Exit 5 comes before the check: nine Tier: lines that the checker WOULD
# refuse are a stop of the bound, never a refusal — nothing reaches it.
body "$(awk 'BEGIN { for (i = 0; i < 9; i++) printf "Tier: x;touch PWN\\n" }')"
stamp 331
expect_status 5 "nine illegal Tier: lines: exit 5 wins over the refusal (2)"
expect_err_lacks "refused"
expect_err_lacks "touch PWN"
no_pwn "nine illegal lines"

# ---------------------------------------------------------------------------
banner "The ticket contract's stamp lines: Risk:, Risk-confidence:, Test-tier:, Covers: (process/R42)"
# ---------------------------------------------------------------------------
# UC1: a ticket carrying the contract's seven lines — the stamp reader lifts
# and checks them with the ticket's other stamp lines and prints them as the
# ticket spells them (the kit's ADR-0037).
UC1='Prose.\nTier: implementer\nConfidence: medium\nCovers: process/R41, process/R42\nRisk: high shared-layer\nRisk-confidence: medium\nTest-tier: process/R41 suite\nTest-tier: process/R42 unit\nMore prose.\n'
body "$UC1"
stamp 900
expect_resolved "$(printf 'Tier: implementer\nConfidence: medium\nCovers: process/R41, process/R42\nRisk: high shared-layer\nRisk-confidence: medium\nTest-tier: process/R41 suite\nTest-tier: process/R42 unit')" \
	"process/R42: the UC1 ticket — all seven stamp lines, as spelled, and nothing else"

# UC1 3a: no Risk: line — none printed, none invented. The `high unclear`
# reading belongs to the reader that acts on risk, never to this one.
body 'Tier: implementer\nTest-tier: process/R41 suite\n'
stamp 900
expect_resolved "$(printf 'Tier: implementer\nTest-tier: process/R41 suite')" \
	"process/R42: a ticket with no Risk: line prints none"
expect_out_lacks "Risk" "process/R42: …and invents no Risk: line"
expect_out_lacks "unclear" "process/R42: …and no high unclear"

# UC1 2a: a reason only the risk rule writes. The stamp reader is never the
# risk rule, so the checker refuses it: exit 2, the field named, the line not.
body 'Tier: implementer\nRisk: high outward\n'
stamp 900
refused "process/R42: Risk: high outward" risk "high outward"
body 'Tier: implementer\nRisk: high unlearned\n'
stamp 900
refused "process/R42: Risk: high unlearned" risk "high unlearned"
body 'Tier: implementer\nRisk: high\n'
stamp 900
expect_status 2 "process/R42: Risk: high with no reason is refused, exit 2"
expect_err_has "the risk line is refused"
body "Tier: implementer\nRisk: low';touch PWN;'\n"
stamp 900
refused "process/R42: a payload on the Risk: line" risk "touch PWN"
# The writer is a flag the stamp reader never passes — and no environment
# variable stands in for it.
body 'Tier: implementer\nRisk: high outward\n'
cd "$SCRATCH" || exit 2
t_exec env VOCAB_WRITER=risk-rule sh "$STAMP" 900
cd "$KIT" || exit 2
expect_status 2 "process/R42: no environment makes the stamp reader the risk rule"

# UC1 2b: one id given two tiers — each line passes alone, so the lines are
# refused together, neither value quoted.
body 'Tier: implementer\nTest-tier: process/R41 suite\nTest-tier: process/R41 unit\n'
stamp 900
expect_status 2 "process/R42: one id given two tiers is refused, exit 2"
expect_err_has "the stamp lines are refused together"
[ -z "$T_OUT" ] && pass "process/R42: …nothing on stdout" || fail "process/R42: …stdout should be empty, got '$T_OUT'"
body "Tier: implementer\nTest-tier: x;touch\$(id) suite\n"
stamp 900
refused "process/R42: a Test-tier: id outside the grammar" test-tier "touch"

# The keys fold the way the checker folds them: case, and a space or an
# underscore for the hyphen. A line the checker would read is never one the
# lift missed.
body 'Tier: implementer\nrisk confidence: low\nTEST_TIER: process/R1 e2e\n'
stamp 900
expect_resolved "$(printf 'Tier: implementer\nrisk confidence: low\nTEST_TIER: process/R1 e2e')" \
	"process/R42: 'risk confidence:' and 'TEST_TIER:' are lifted as the checker reads them"
body 'Tier: implementer\nrisk confidence: certain\n'
stamp 900
refused "process/R42: a folded risk-confidence key, refused" risk-confidence "certain"

# Covers: is lifted and held to the coverage check's grammar — bounded ids,
# comma-separated, or one of the three exemptions — and printed as spelled.
for cov in 'none (prefactor)' 'none (open-issue)' 'none (release)' 'R1' 'process/R38,process/R39'; do
	body "Tier: implementer\nCovers: $cov\n"
	stamp 900
	expect_resolved "$(printf 'Tier: implementer\nCovers: %s' "$cov")" "process/R42: 'Covers: $cov' is lifted and printed"
done
body "Tier: implementer\nCovers: process/R41; touch PWN\n"
stamp 900
refused "process/R42: a Covers: line that is no id list" covers "touch PWN"
body 'Tier: implementer\nCovers: none (later)\n'
stamp 900
refused "process/R42: a Covers: exemption outside the three" covers "later"
body 'Tier: implementer\nCovers: process/R41\nCovers: process/R42\n'
stamp 900
expect_status 2 "process/R42: two Covers: lines with two values are refused together, exit 2"
expect_err_has "the stamp lines are refused together"
# Without the requirement grammar beside it the reader cannot read a Covers:
# line, and fails closed: exit 3, nothing printed.
mkdir -p "$SCRATCH/nogrammar/scripts"
cp "$STAMP" "$KIT/scripts/vocab.sh" "$KIT/scripts/vocab.config.sh" "$SCRATCH/nogrammar/scripts/"
body 'Tier: implementer\nCovers: process/R41\n'
cd "$SCRATCH" || exit 2
t_exec sh "$SCRATCH/nogrammar/scripts/stamp.sh" 900
cd "$KIT" || exit 2
expect_status 3 "process/R42: no requirement grammar beside the reader — a Covers: line cannot be read, exit 3"
[ -z "$T_OUT" ] && pass "process/R42: …nothing on stdout" || fail "process/R42: …stdout should be empty, got '$T_OUT'"

# A consumer whose policy predates the contract declares none of its fields:
# the new lines are dropped as undeclared, the Tier: line still read.
body 'Tier: implementer\nRisk: high security\nTest-tier: process/R41 suite\n'
stamp_under "$SCRATCH/nodomain.config.sh"
expect_resolved "Tier: implementer" "process/R42: under a policy that predates the contract, the new lines are not printed"
expect_err_has "the risk line names a field this project's policy does not declare"
expect_err_has "the test-tier line names a field this project's policy does not declare"

# ---------------------------------------------------------------------------
banner "The bound is the policy's: 32 Test-tier: lines, 8 of every other key (process/R43)"
# ---------------------------------------------------------------------------
tiers() { awk -v n="$1" 'BEGIN { print "Tier: implementer"; for (i = 1; i <= n; i++) printf "Test-tier: process/R%d suite\n", i }'; }
body "$(tiers 32)\n"
stamp 900
expect_status 0 "process/R43: 32 Test-tier: lines are within the bound — checked, exit 0"
[ "$(printf '%s\n' "$T_OUT" | grep -c '^Test-tier:')" = 32 ] && pass "process/R43: …all 32 printed" ||
	fail "process/R43: …printed $(printf '%s\n' "$T_OUT" | grep -c '^Test-tier:') of 32"
body "$(tiers 33)\n"
stamp 900
expect_status 5 "process/R43: 33 Test-tier: lines are past the bound: exit 5"
body "$(tiers 40)\n"
stamp 900
expect_status 5 "process/R43: 40 Test-tier: lines (UC1 3b): exit 5, a stop"
[ -z "$T_OUT" ] && pass "process/R43: …nothing on stdout" || fail "process/R43: …stdout should be empty"
expect_err_has "40 test-tier lines"
expect_err_lacks "process/R"
for key in Risk Risk-confidence Covers; do
	body "$(awk -v k="$key" 'BEGIN { print "Tier: implementer"; for (i = 0; i < 9; i++) print k ": low" }')\n"
	stamp 900
	expect_status 5 "process/R43: nine $key: lines are past the bound of 8: exit 5"
	[ -z "$T_OUT" ] && pass "process/R43: …nothing on stdout" || fail "process/R43: …stdout should be empty"
done
expect_err_has "9 covers lines"
# The bound is read from the policy, not spelled here: a policy that lowers
# it is obeyed, and one that declares none keeps the reader's own 8.
cat >"$SCRATCH/bound2.config.sh" <<'EOF'
VOCAB_FIELDS='tier test-tier'
VOCAB_KEYED='test-tier'
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_TEST_TIER='unit suite e2e manual'
VOCAB_BOUND=2
VOCAB_BOUNDS='test-tier=3'
EOF
body "$(tiers 3)\n"
stamp_under "$SCRATCH/bound2.config.sh"
expect_status 0 "process/R43: a policy bounding test-tier at 3: three lines pass"
body "$(tiers 4)\n"
stamp_under "$SCRATCH/bound2.config.sh"
expect_status 5 "process/R43: …and four are past it — the bound is the policy's"
body 'Tier: implementer\nTier: implementer\nTier: implementer\n'
stamp_under "$SCRATCH/bound2.config.sh"
expect_status 5 "process/R43: …and its every-key bound of 2 holds the Tier: lines"
cat >"$SCRATCH/nobound.config.sh" <<'EOF'
VOCAB_FIELDS='tier test-tier'
VOCAB_KEYED='test-tier'
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_TEST_TIER='unit suite e2e manual'
EOF
body "$(tiers 9)\n"
stamp_under "$SCRATCH/nobound.config.sh"
expect_status 5 "process/R43: a policy that publishes no bound: the reader's own 8 holds, even for Test-tier:"

# ---------------------------------------------------------------------------
banner "Exit 4 — the fetch failed: never read as a missing line"
# ---------------------------------------------------------------------------
body 'Tier: implementer\n' 1
stamp 331
expect_resolved "Tier: implementer" "one failed fetch, then a good one: retried once, exit 0"
[ "$(calls)" = 2 ] && pass "…the tracker was called exactly twice" || fail "…the tracker was called $(calls) time(s), not 2"

body 'Tier: implementer\n' 2
stamp 331
expect_status 4 "two failed fetches: exit 4, a stop — not 3, not 0"
[ -z "$T_OUT" ] && pass "a failed fetch: nothing on stdout" || fail "a failed fetch: stdout should be empty, got '$T_OUT'"
[ "$(calls)" = 2 ] && pass "…one retry, never a loop" || fail "…the tracker was called $(calls) time(s), not 2"
expect_err_has "x stamp:"

# ---------------------------------------------------------------------------
banner "A signal ends the script: never read on with its scratch gone"
# ---------------------------------------------------------------------------
# A trap that only removes the scratch directory returns, and the script
# carries on reading files that are gone — so an interrupt ended as exit 3
# (the defaults) or 4, not as an interrupt. The scratch directory is gone
# either way.
mkdir -p "$SCRATCH/tmpd"
for sig in TERM:143 INT:130 HUP:129; do
	body 'Tier: implementer\n'
	echo "${sig%%:*}" >"$SCRATCH/signal"
	cd "$SCRATCH" || exit 2
	t_exec env TMPDIR="$SCRATCH/tmpd" sh "$STAMP" 331
	cd "$KIT" || exit 2
	rm -f "$SCRATCH/signal"
	expect_status "${sig#*:}" "SIG${sig%%:*} mid-fetch: the script exits ${sig#*:}, not on to a verdict"
	[ -z "$T_OUT" ] && pass "SIG${sig%%:*}: nothing on stdout" || fail "SIG${sig%%:*}: stdout should be empty, got '$T_OUT'"
	[ -z "$(ls -A "$SCRATCH/tmpd")" ] && pass "SIG${sig%%:*}: the scratch directory is removed" ||
		fail "SIG${sig%%:*}: left behind: $(ls -A "$SCRATCH/tmpd")"
done

t_done "the stamp reader"
