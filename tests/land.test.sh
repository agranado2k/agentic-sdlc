#!/bin/sh
# tests/land.test.sh — one PR landed by hand records what the train records.
#
# The suite drives scripts/land.kit.sh through its command line and observes
# only what it does to the outside: what it asked the forge CLI to do, what it
# printed, its exit status, and what reached the trace. The forge CLI is a
# STUB `gh` first on PATH that logs its argv and answers each subcommand from
# the environment — tests/forge-broker.test.sh's pattern, for its reason: a
# real forge would make the suite depend on an account, a network and a live
# PR, none of which are properties of the script.
#
# THE CASE THAT MATTERS MOST IS THE REFUSAL. A PR that is not green and
# mergeable is refused with exit 2 BEFORE anything happens: no merge call and
# no event, because a landing the trace records that the forge never made is
# worse than the silence this script exists to end (retro G2).
#
# THE CASE THAT MATTERS SECOND IS THE PAIR. A landed PR leaves exactly one
# merge.land and exactly one feedback — `unasked` with its reason when nobody
# is at a terminal to answer — the join /retro reads per landing.
#
# Usage: sh tests/land.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
LAND="$KIT/scripts/land.kit.sh"
TRACE="$KIT/scripts/trace.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

# --- the stub forge CLI ------------------------------------------------------
# The PR's state is one value per line, in the order the script asks for it:
# state, isDraft, mergeable, mergeStateStatus, reviewDecision, base branch,
# closing ticket, title. STUB_* variables set the forge's answers.
STUBDIR="$SCRATCH/bin"
mkdir -p "$STUBDIR"
cat >"$STUBDIR/gh" <<'EOF'
#!/bin/sh
printf 'ARGV: %s\n' "$*" >>"$STUB_LOG"
# The forge's state for one run: knob assignments land() wrote for it.
[ -s "$STUB_KNOBS" ] && . "$STUB_KNOBS"
case " $* " in
*" pr view "*"mergeCommit"*) printf '%s\n' "${STUB_SHA-abcdef0123456789abcdef0123456789abcdef01}" ;;
*" pr view "*)
	[ "${STUB_VIEW_RC:-0}" = 0 ] || { echo 'gh: HTTP 502 Bad Gateway' >&2; exit "$STUB_VIEW_RC"; }
	printf '%s\n' "${STUB_PRSTATE:-OPEN}" "${STUB_DRAFT:-false}" "${STUB_MERGEABLE:-MERGEABLE}" \
		"${STUB_MSS:-CLEAN}" "${STUB_REVIEW-APPROVED}" main "${STUB_TICKET-77}" "${STUB_TITLE:-feat(x): a slice}"
	;;
*" pr checks "*) exit "${STUB_CHECKS_RC:-0}" ;;
*" pr merge "*) exit "${STUB_MERGE_RC:-0}" ;;
*" run list "*)
	# A run the forge registers late shows from the second listing on.
	printf '%s\n' ${STUB_RUNS-901}
	[ "$(grep -c '^ARGV: run list' "$STUB_LOG")" -lt 2 ] || printf '%s\n' ${STUB_RUNS_LATE:-}
	;;
*" run watch "*) exit "${STUB_WATCH_RC:-0}" ;;
esac
EOF
chmod +x "$STUBDIR/gh"
PATH="$STUBDIR:$PATH"
STUB_LOG="$SCRATCH/gh.log"
STUB_KNOBS="$SCRATCH/gh.knobs"
STUB_SHA=abcdef0123456789abcdef0123456789abcdef01
export PATH STUB_LOG STUB_KNOBS

TRACE_DIR="$SCRATCH/trace"
export TRACE_DIR
# The kit twin is the script's own default; the suite still names it, so a
# reader of the trace below reads the same policy the script wrote through.
show() { env TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh" sh "$TRACE" show "$@" 2>/dev/null; }

# land [STUB_<KNOB>=<value> …] <args> — the script with no terminal on
# stdin, streams kept apart, the stub's log reset so every count is about one
# run. The leading knobs set the forge's state for this run only: they are
# written to a file the stub reads, never put in front of a function call,
# whose assignments POSIX may let outlive it (forge-broker.kit.sh says why).
# Short waits: LAND_POLL_SECONDS=0.
land() {
	: >"$STUB_LOG"
	: >"$STUB_KNOBS"
	while [ $# -gt 0 ]; do
		case $1 in
		STUB_*=*) printf "%s='%s'\n" "${1%%=*}" "${1#*=}" >>"$STUB_KNOBS" ;;
		*) break ;;
		esac
		shift
	done
	t_run_split env LAND_POLL_SECONDS=0 sh "$LAND" "$@" </dev/null
	: >"$STUB_KNOBS"
}
merges() { grep -c '^ARGV: pr merge' "$STUB_LOG"; }
events() { show "pr:#$1" | grep -c "\"kind\":\"$2\"" | tr -d ' '; }

# ---------------------------------------------------------------------------
banner "1. A PR that is not green and mergeable is refused: exit 2, nothing merged, nothing emitted"
# ---------------------------------------------------------------------------
# refused <knob> <pr> <label>
refused() {
	_r_pr=$2
	_r_label=$3
	land "$1" "$_r_pr"
	s_assert_status 2 "$_r_label: refused with exit 2"
	[ "$(merges)" = 0 ] && pass "$_r_label: no merge call reached the forge" ||
		fail "$_r_label: the forge was asked to merge a PR the script should have refused"
	[ "$(show "pr:#$_r_pr" | grep -c '"kind"' | tr -d ' ')" = 0 ] && pass "$_r_label: nothing reached the trace" ||
		fail "$_r_label: an event was emitted for a refused PR"
}
refused STUB_CHECKS_RC=1 101 "a red check"
refused STUB_MERGEABLE=CONFLICTING 102 "a conflicting PR"
refused STUB_DRAFT=true 103 "a draft"
refused STUB_REVIEW=CHANGES_REQUESTED 104 "a human's changes requested"
refused STUB_MSS=BEHIND 105 "a PR behind its base"
refused STUB_PRSTATE=MERGED 106 "a PR already merged"
refused STUB_CHECKS_RC=8 107 "pending checks"
land STUB_CHECKS_RC=1 109
printf '%s\n' "$S_ERR" | grep -qi 'checks' && pass "a red refusal names the checks" ||
	fail "a red refusal does not say the checks are what refused it: $S_ERR"
refused STUB_VIEW_RC=1 110 "a forge that does not answer for the PR"
land abc
s_assert_status 2 "a PR that is not a number is a usage error"
land
s_assert_status 2 "no PR at all is a usage error"

# ---------------------------------------------------------------------------
banner "2. A green PR lands: one merge.land, one feedback"
# ---------------------------------------------------------------------------
land 123
s_assert_status 0 "a green PR lands with exit 0"
grep -q '^ARGV: pr merge 123 --merge' "$STUB_LOG" && pass "merged with the merge-commit method (gh pr merge 123 --merge)" ||
	fail "the merge call was not 'gh pr merge 123 --merge': $(grep 'pr merge' "$STUB_LOG")"
[ "$(merges)" = 1 ] && pass "exactly one merge call" || fail "$(merges) merge calls"
grep -q "^ARGV: run list.*$STUB_SHA" "$STUB_LOG" && pass "it looks for main's workflows on the merge commit" ||
	fail "it never listed the workflow runs on the merge commit"
grep -q '^ARGV: run watch 901' "$STUB_LOG" && pass "and waits for each one" || fail "it never watched run 901"
s_assert_out_has "$STUB_SHA" "stdout names the merge sha"
[ "$(events 123 merge.land)" = 1 ] && pass "one merge.land for pr:#123" || fail "$(events 123 merge.land) merge.land events for pr:#123"
[ "$(events 123 feedback)" = 1 ] && pass "one feedback for pr:#123" || fail "$(events 123 feedback) feedback events for pr:#123"
ml=$(show 'pr:#123' --kind merge.land)
for tok in '"outcome":"landed"' "\"merge_sha\":\"$STUB_SHA\"" '"method":"merge"' '"related":"ticket:#77"' '"reason":"feat(x): a slice"'; do
	printf '%s\n' "$ml" | grep -qF -- "$tok" && pass "merge.land carries $tok" || fail "merge.land lacks $tok: $ml"
done
fb=$(show 'pr:#123' --kind feedback)
for tok in '"subject":"ticket:#77"' '"related":"pr:#123"' '"outcome":"unasked"'; do
	printf '%s\n' "$fb" | grep -qF -- "$tok" && pass "feedback carries $tok" || fail "feedback lacks $tok: $fb"
done
printf '%s\n' "$fb" | grep -qi '"reason":"[^"]*terminal' && pass "with no terminal, the unasked reason says so" ||
	fail "the unasked reason does not name the missing terminal: $fb"
# merge.land before feedback, the order a reader joins them in.
order=$(show 'pr:#123' | grep -oE '"kind":"(merge.land|feedback)"' | tr '\n' ' ')
[ "$order" = '"kind":"merge.land" "kind":"feedback" ' ] && pass "merge.land is written before feedback" ||
	fail "the events are out of order: $order"

land 124 --unasked 'operator said land and do not stop'
s_assert_status 0 "--unasked lands too"
fb=$(show 'pr:#124' --kind feedback)
printf '%s\n' "$fb" | grep -qF '"outcome":"unasked"' && printf '%s\n' "$fb" | grep -qF '"reason":"operator said land and do not stop"' &&
	pass "--unasked records unasked with the reason given" || fail "--unasked did not record its reason: $fb"

land STUB_TICKET= 125 --ticket 88
fb=$(show 'pr:#125' --kind feedback)
printf '%s\n' "$fb" | grep -qF '"subject":"ticket:#88"' && pass "--ticket names the ticket when the PR closes none" ||
	fail "--ticket did not set the feedback subject: $fb"
land STUB_TICKET= 126
fb=$(show 'pr:#126' --kind feedback)
printf '%s\n' "$fb" | grep -qF '"subject":"pr:#126"' && pass "with no ticket known, feedback sits on the PR itself" ||
	fail "with no ticket, feedback is not on pr:#126: $fb"

# ---------------------------------------------------------------------------
banner "3. The verdict question, asked at a terminal"
# ---------------------------------------------------------------------------
# script(1) gives the run a terminal; where it is missing the case is skipped,
# loudly, rather than faked.
if command -v script >/dev/null 2>&1 && script -qec true /dev/null </dev/null >/dev/null 2>&1; then
	: >"$STUB_LOG"
	printf 'adjusted\nthe next slice is re-cut smaller\n' |
		script -qec "env LAND_POLL_SECONDS=0 sh '$LAND' 130" /dev/null >"$SCRATCH/tty.out" 2>&1
	fb=$(show 'pr:#130' --kind feedback)
	printf '%s\n' "$fb" | grep -qF '"outcome":"adjusted"' && pass "an answer at the terminal is the verdict (adjusted)" ||
		{ fail "the terminal answer did not become the verdict: $fb"; sed 's/^/        | /' "$SCRATCH/tty.out"; }
	printf '%s\n' "$fb" | grep -qF '"reason":"the next slice is re-cut smaller"' && pass "and its one line is the reason" ||
		fail "the terminal's reason line was not recorded: $fb"
	grep -qi 'hit' "$SCRATCH/tty.out" && grep -qi 'adjusted' "$SCRATCH/tty.out" && grep -qi 'missed' "$SCRATCH/tty.out" &&
		pass "the question offers hit, adjusted and missed" || fail "the question does not offer the three verdicts"
	: >"$STUB_LOG"
	printf 'maybe\nhit\nas planned\n' |
		script -qec "env LAND_POLL_SECONDS=0 sh '$LAND' 131" /dev/null >"$SCRATCH/tty.out" 2>&1
	show 'pr:#131' --kind feedback | grep -qF '"outcome":"hit"' && pass "a word outside the three is asked again, not recorded" ||
		fail "an answer outside hit|adjusted|missed was not re-asked: $(show 'pr:#131' --kind feedback)"
else
	echo "  skip  no script(1) here — the terminal path is not exercised by this run" >&2
fi

# ---------------------------------------------------------------------------
banner "4. The trace unconfigured leaves the merge unchanged"
# ---------------------------------------------------------------------------
land 123
traced_out=$S_OUT
: >"$STUB_LOG"
t_run_split env TRACE_DIR= TRACE_CONFIG="$KIT/scripts/trace.config.sh" LAND_POLL_SECONDS=0 sh "$LAND" 140 </dev/null
s_assert_status 0 "unconfigured, a green PR still lands with exit 0"
[ "$(merges)" = 1 ] && pass "unconfigured, the merge call is the same one call" || fail "unconfigured: $(merges) merge calls"
[ "$(printf '%s\n' "$S_OUT" | sed 's/#140/#N/g')" = "$(printf '%s\n' "$traced_out" | sed 's/#123/#N/g')" ] &&
	pass "and stdout is what a traced run prints" || fail "unconfigured stdout differs: '$S_OUT' vs '$traced_out'"
[ "$(show 'pr:#140' | grep -c '"kind"' | tr -d ' ')" = 0 ] && pass "and nothing reached the trace" ||
	fail "an unconfigured run wrote to the trace"

# ---------------------------------------------------------------------------
banner "5. The forge's answers after the decision"
# ---------------------------------------------------------------------------
land STUB_MERGE_RC=1 150
[ "$S_STATUS" != 0 ] && pass "a merge the forge rejects is not exit 0 (got $S_STATUS)" || fail "a rejected merge exited 0"
show 'pr:#150' --kind merge.land | grep -qF '"outcome":"stopped"' && pass "and records merge.land stopped" ||
	fail "a rejected merge did not record merge.land stopped: $(show 'pr:#150')"
[ "$(events 150 feedback)" = 0 ] && pass "and asks no verdict of a PR that did not land" || fail "a rejected merge recorded feedback"
land STUB_WATCH_RC=1 151
[ "$S_STATUS" = 1 ] && pass "a failed post-merge workflow is exit 1 — escalate, as the train's hard rule 6 says" ||
	fail "a failed post-merge workflow exited $S_STATUS"
show 'pr:#151' --kind merge.land | grep -qF '"workflows":"failure"' && pass "the landing still records, with data.workflows=failure" ||
	fail "a failed post-merge workflow was not recorded on merge.land: $(show 'pr:#151')"
[ "$(events 151 feedback)" = 1 ] && pass "and the landing still gets its feedback" || fail "no feedback after a failed workflow"
printf '%s\n' "$S_ERR" | grep -qi 'escalate' && pass "stderr says to escalate" || fail "stderr does not say escalate: $S_ERR"

land STUB_RUNS= 152
s_assert_status 0 "no workflow on the merge commit: still a landing, exit 0"
[ "$(grep -c '^ARGV: run list' "$STUB_LOG")" = 12 ] && pass "it looked LAND_POLL_TRIES times (12) before giving up" ||
	fail "it listed the runs $(grep -c '^ARGV: run list' "$STUB_LOG") times, not 12"
show 'pr:#152' --kind merge.land | grep -qF '"workflows":"none"' && pass "and records data.workflows=none" ||
	fail "no run found was not recorded as workflows=none: $(show 'pr:#152')"
land STUB_RUNS_LATE=902 153
grep -q '^ARGV: run watch 902' "$STUB_LOG" && pass "a workflow the forge registers late is watched too" ||
	fail "the late run 902 was never watched"
[ "$(grep -c '^ARGV: run watch 901' "$STUB_LOG")" = 1 ] && pass "and the first is watched once" ||
	fail "run 901 was watched $(grep -c '^ARGV: run watch 901' "$STUB_LOG") times"
land STUB_SHA= 154
s_assert_status 1 "a merge commit the forge never reports is exit 1"
grep -q '^ARGV: run list' "$STUB_LOG" && fail "it listed runs for an empty merge commit" ||
	pass "and no runs are listed for an empty commit"
ml=$(show 'pr:#154' --kind merge.land)
printf '%s\n' "$ml" | grep -qF '"outcome":"landed"' && printf '%s\n' "$ml" | grep -qF '"workflows":"unknown"' &&
	pass "the landing still records, landed with data.workflows=unknown" || fail "an unknown sha was not recorded as such: $ml"
printf '%s\n' "$ml" | grep -qF '"merge_sha"' && fail "an empty merge_sha was recorded: $ml" || pass "and no empty merge_sha"
printf '%s\n' "$S_ERR" | grep -qi 'merge commit' && pass "stderr says the merge commit is unknown" || fail "stderr: $S_ERR"

# ---------------------------------------------------------------------------
banner "6. Kit-only: on bootstrap's deletion list, named by the root manual"
# ---------------------------------------------------------------------------
kit_only=$(sed -n 's/^KIT_ONLY="\(.*\)"$/\1/p' "$KIT/bootstrap.sh")
for f in scripts/land.kit.sh tests/land.test.sh; do
	case " $kit_only " in
	*" $f "*) pass "$f is on bootstrap.sh's KIT_ONLY list" ;;
	*) fail "$f is not on bootstrap.sh's KIT_ONLY list — it would ship to a consumer" ;;
	esac
done
grep -F '/merge-train' "$KIT/AGENTS.md" | grep -qF 'scripts/land.kit.sh' &&
	pass "the root manual's /merge-train row names scripts/land.kit.sh as the one-PR form" ||
	fail "the root manual's /merge-train row does not name scripts/land.kit.sh"

t_done "land one PR by hand"
