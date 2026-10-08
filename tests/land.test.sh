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
*" pr view "*"headRefOid"*)
	# The head commit, and the date it was committed: the iteration check
	# reads the trace for a pr.iterate at or after it (#630).
	[ "${STUB_HEAD_RC:-0}" = 0 ] || { echo 'gh: HTTP 502 Bad Gateway' >&2; exit "$STUB_HEAD_RC"; }
	printf '%s\n' "${STUB_HEAD_OID-1234567890123456789012345678901234567890}" "${STUB_HEAD_DATE-2000-01-01T00:00:00Z}"
	;;
*" pr view "*"body"*)
	# The PR body is a file the case wrote — free text, quotes and all, so it
	# never passes through the knob file's quoting.
	[ "${STUB_BODY_RC:-0}" = 0 ] || { echo 'gh: HTTP 502 Bad Gateway' >&2; exit "$STUB_BODY_RC"; }
	[ -z "${STUB_BODY_FILE:-}" ] || cat "$STUB_BODY_FILE"
	;;
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
*" run watch "*)
	# A workflow that takes wall-clock time: the waited figure moves with it.
	[ -z "${STUB_WATCH_SLEEP:-}" ] || sleep "$STUB_WATCH_SLEEP"
	# A run re-run after the tag answers with its second attempt's result.
	grep -q '^ARGV: run rerun' "$STUB_LOG" && exit "${STUB_WATCH_RC_AFTER:-0}"
	exit "${STUB_WATCH_RC:-0}"
	;;
*" run rerun "*) exit "${STUB_RERUN_RC:-0}" ;;
*" run view "*)
	# A re-run's new attempt shows `completed` (the old attempt) for the first
	# STUB_COMPLETED_VIEWS asks, then queued.
	if [ "$(grep -c '^ARGV: run view' "$STUB_LOG")" -le "${STUB_COMPLETED_VIEWS:-0}" ]; then
		echo completed
	else
		echo queued
	fi
	;;
esac
EOF
chmod +x "$STUBDIR/gh"
# The stub git answers the landing's release questions and passes everything
# else to the real one: whether the merge bumped VERSION's shared-layer line
# (the merge commit against its first parent), whether the tag already exists
# on the forge, and the tag and its push — each logged beside the forge's
# calls, so one log holds the order. With no knobs the merge bumps nothing.
REAL_GIT=$(command -v git)
export REAL_GIT
cat >"$STUBDIR/git" <<'EOF'
#!/bin/sh
[ -s "$STUB_KNOBS" ] && . "$STUB_KNOBS"
_c=
[ "${1:-}" = -C ] && { _c=$2; shift 2; }
case ${1:-} in
fetch | show | ls-remote | tag | push) printf 'ARGV: git %s\n' "$*" >>"$STUB_LOG" ;;
*) if [ -n "$_c" ]; then exec "$REAL_GIT" -C "$_c" "$@"; else exec "$REAL_GIT" "$@"; fi ;;
esac
case $1 in
fetch) exit "${STUB_FETCH_RC:-0}" ;;
show)
	case $2 in
	*'^1:VERSION') printf '# a note\nshared-layer: %s\n' "${STUB_VER_BEFORE:-0.1.0}" ;;
	*':VERSION') printf '# a note\nshared-layer: %s\n' "${STUB_VER_AFTER:-0.1.0}" ;;
	*) exit 128 ;;
	esac
	;;
ls-remote)
	# An annotated tag lists its tag object, then the commit it peels to; a
	# lightweight one lists the commit alone.
	[ -n "${STUB_REMOTE_TAG:-}" ] || exit 0
	if [ "${STUB_REMOTE_TAG_KIND:-annotated}" = annotated ]; then
		printf '%s\trefs/tags/v%s\n' 2222222222222222222222222222222222222222 "${STUB_VER_AFTER:-0.1.0}"
		printf '%s\trefs/tags/v%s^{}\n' "$STUB_REMOTE_TAG" "${STUB_VER_AFTER:-0.1.0}"
	else
		printf '%s\trefs/tags/v%s\n' "$STUB_REMOTE_TAG" "${STUB_VER_AFTER:-0.1.0}"
	fi
	;;
tag) exit "${STUB_TAG_RC:-0}" ;;
push) exit "${STUB_PUSH_RC:-0}" ;;
esac
EOF
chmod +x "$STUBDIR/git"
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
# not_landed <pr> <label> — the last run refused: exit 2, no merge call.
not_landed() {
	s_assert_status 2 "$2: refused with exit 2"
	[ "$(merges)" = 0 ] && pass "$2: no merge call reached the forge" ||
		fail "$2: the forge was asked to merge a PR the script should have refused"
}
# refused <knob> <pr> <label>
refused() {
	_r_pr=$2
	_r_label=$3
	land "$1" "$_r_pr"
	not_landed "$_r_pr" "$_r_label"
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

# iterated <PR>… — record a /pr-iterate iteration on each PR, now: the stub's
# head commit is dated 2000 unless a case says otherwise, so each event sits
# at its head. Section 1's PRs are refused before the trace is read, and #140
# is section 4's unconfigured run, whose trace must stay empty.
iterated() {
	for _it_pr in "$@"; do
		env TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh" TRACE_QUIET=1 sh "$TRACE" emit kind=pr.iterate \
			"subject=pr:#$_it_pr" outcome=stopped data.iteration=1 reason=seeded </dev/null >/dev/null 2>&1 ||
			fail "could not seed a pr.iterate event on pr:#$_it_pr"
	done
}
_seed=120
while [ "$_seed" -le 210 ]; do
	[ "$_seed" = 140 ] || iterated "$_seed"
	_seed=$((_seed + 1))
done

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
# The second run's workflow takes seconds the first one's did not: the waited
# figure is the clock's, so it differs, and the comparison is not about it.
t_run_split env TRACE_DIR= TRACE_CONFIG="$KIT/scripts/trace.config.sh" LAND_POLL_SECONDS=0 STUB_WATCH_SLEEP=2 sh "$LAND" 140 </dev/null
s_assert_status 0 "unconfigured, a green PR still lands with exit 0"
[ "$(merges)" = 1 ] && pass "unconfigured, the merge call is the same one call" || fail "unconfigured: $(merges) merge calls"
# norm <PR> — stdout with the PR number and the waited seconds masked.
norm() { sed "s/#$1/#N/g; s/waited [0-9]*s/waited Ns/"; }
[ "$(printf '%s\n' "$S_OUT" | norm 140)" = "$(printf '%s\n' "$traced_out" | norm 123)" ] &&
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
grep -q '^ARGV: run rerun' "$STUB_LOG" && fail "a merge that bumps nothing had a failed run re-run" ||
	pass "a merge that bumps nothing re-runs no failed workflow — its red is the verdict"
grep -qE '^ARGV: git (tag|push)' "$STUB_LOG" && fail "a merge that bumps nothing was tagged: $(grep '^ARGV: git' "$STUB_LOG")" ||
	pass "and is not tagged"

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
banner "6. The landing records whether /implement opened the PR, read from its body (#480)"
# ---------------------------------------------------------------------------
# /implement writes one line into the PR body it opens — the ticket and the
# tier it read through the stamp checker. The landing reads that line from the
# forge, never from the trace (ADR-0008 clause 7), and records it on
# merge.land as data.implement=yes|no and data.implement_tier. The body is untrusted:
# only a line of the one fixed shape, whose tier the vocabulary checker
# passes, counts; anything else is recorded as absent — and never blocks the
# landing.
# body <name> <text> — write a PR body for one case; prints its path.
body() { printf '%s\n' "$2" >"$SCRATCH/body.$1"; printf '%s' "$SCRATCH/body.$1"; }
# landed_with <PR> <label> <token>… — the PR landed, exit 0, and its
# merge.land carries every token.
landed_with() {
	_lw_pr=$1
	_lw_label=$2
	shift 2
	s_assert_status 0 "$_lw_label: the PR lands, exit 0"
	_lw_ml=$(show "pr:#$_lw_pr" --kind merge.land)
	for _lw_tok in "$@"; do
		printf '%s\n' "$_lw_ml" | grep -qF -- "$_lw_tok" && pass "$_lw_label: merge.land carries $_lw_tok" ||
			fail "$_lw_label: merge.land lacks $_lw_tok: $_lw_ml"
	done
}
# no_tier <PR> <label> — merge.land carries no tier at all, under either key.
no_tier() {
	show "pr:#$1" --kind merge.land | grep -qE '"(implement_)?tier"' && fail "$2: a tier was recorded: $(show "pr:#$1" --kind merge.land)" ||
		pass "$2: no tier is recorded"
}
# The line is lifted from /implement's own step 8, placeholders filled, so the
# skill that writes it and the script that reads it are held to one shape.
LINE=$(grep -oE '<!-- implement: [^`]*-->' "$KIT/.agents/skills/implement/SKILL.md" | head -1 |
	sed 's/<N>/77/; s/<tier>/mechanical/')
[ "$LINE" = '<!-- implement: ticket=#77 tier=mechanical -->' ] && pass "the line, lifted from /implement's step 8: $LINE" ||
	fail "/implement's step 8 does not spell the line this suite expects: '$LINE'"
f=$(body yes "## What & why

Closes #77.

$LINE

<!-- explain-diff-appendix -->")
land "STUB_BODY_FILE=$f" 160
landed_with 160 "the line in the body" '"implement":"yes"' '"implement_tier":"mechanical"'
# The stub answers any body request, so the argv is what holds the field:
# the body, and an empty string for a body the forge leaves null.
grep -qF 'ARGV: pr view 160 --json body --jq .body // ""' "$STUB_LOG" && pass "the body is read from the forge, --jq '.body // \"\"'" ||
	fail "the PR body was never asked of the forge as --json body --jq '.body // \"\"': $(grep '^ARGV: pr view 160' "$STUB_LOG")"

land 161
landed_with 161 "no line in the body" '"implement":"no"'
no_tier 161 "no line in the body"
# Section 2's landing, read back without its exit status: S_STATUS is the
# last run's, #161's, and a pass line here must report on #123 alone.
show 'pr:#123' --kind merge.land | grep -qF '"implement":"no"' &&
	pass "an empty body (section 2's landing): merge.land carries \"implement\":\"no\"" ||
	fail "an empty body (section 2's landing): merge.land lacks \"implement\":\"no\": $(show 'pr:#123' --kind merge.land)"

f="$SCRATCH/body.crlf"
printf 'Closes #77.\r\n%s\r\n' "$LINE" >"$f"
land "STUB_BODY_FILE=$f" 162
landed_with 162 "a body with CRLF line ends" '"implement":"yes"' '"implement_tier":"mechanical"'

f=$(body offvocab "<!-- implement: ticket=#77 tier=implementor -->")
land "STUB_BODY_FILE=$f" 163
landed_with 163 "a tier off the vocabulary" '"implement":"no"'
no_tier 163 "a tier off the vocabulary"

# Hostile lines: each is recorded as absent, and none of it runs. Each lands
# a PR of its own, #170 up, so each is read back on its own event.
_h_pr=169
for hostile in \
	"<!-- implement: ticket=#77 tier=\$(touch $SCRATCH/pwned) -->" \
	"<!-- implement: ticket=#77 tier=\`touch $SCRATCH/pwned\` -->" \
	"<!-- implement: ticket=#77 tier=planner -->; touch $SCRATCH/pwned" \
	"<!-- implement: ticket=#77 tier=planner' data.implement=yes reason='x -->" \
	"<!-- implement: ticket=#77 tier=planner tier=reviewer -->" \
	"  <!-- implement: ticket=#77 tier=planner -->" \
	"<!-- implement: ticket=77 tier=planner -->"; do
	_h_pr=$((_h_pr + 1))
	f=$(body "hostile.$_h_pr" "$hostile")
	land "STUB_BODY_FILE=$f" "$_h_pr"
	landed_with "$_h_pr" "a malformed line ($hostile)" '"implement":"no"'
	no_tier "$_h_pr" "a malformed line ($hostile)"
done
[ -e "$SCRATCH/pwned" ] && fail "a hostile PR body ran a command" || pass "no hostile body ran anything"

f=$(body two "$LINE
<!-- implement: ticket=#77 tier=planner -->")
land "STUB_BODY_FILE=$f" 165
landed_with 165 "two lines in one body" '"implement":"no"'
no_tier 165 "two lines in one body"

# Prose that quotes the marker mid-line is not a second line: only a line
# opening with it counts, so the good line beside it is still read.
f=$(body quoted "$LINE
The landing reads \`<!-- implement: ticket=#1 tier=planner -->\` from the body.")
land "STUB_BODY_FILE=$f" 169
landed_with 169 "a good line beside prose quoting the marker" '"implement":"yes"' '"implement_tier":"mechanical"'

f=$(body other "<!-- implement: ticket=#999 tier=planner -->")
land "STUB_BODY_FILE=$f" 166
landed_with 166 "a line naming another ticket" '"implement":"no"'
no_tier 166 "a line naming another ticket"

f=$(body noticket "<!-- implement: ticket=#999 tier=planner -->")
land STUB_TICKET= "STUB_BODY_FILE=$f" 167
landed_with 167 "with no ticket known, the line's own" '"implement":"yes"' '"implement_tier":"planner"'

# The ticket's bound, with no ticket known so no mismatch hides it: an empty
# number or a tenth digit is not the shape, and the line is absent.
f=$(body noticket.empty "<!-- implement: ticket=# tier=planner -->")
land STUB_TICKET= "STUB_BODY_FILE=$f" 177
landed_with 177 "an empty ticket number, no ticket known" '"implement":"no"'
no_tier 177 "an empty ticket number, no ticket known"
f=$(body noticket.long "<!-- implement: ticket=#1234567890 tier=planner -->")
land STUB_TICKET= "STUB_BODY_FILE=$f" 178
landed_with 178 "a ten-digit ticket number, no ticket known" '"implement":"no"'
no_tier 178 "a ten-digit ticket number, no ticket known"

# The body the forge fails on is one that would otherwise count — #160's, a
# good line naming the landing's own ticket — so only the failed read can
# leave it absent.
land STUB_BODY_RC=1 "STUB_BODY_FILE=$SCRATCH/body.yes" 168
landed_with 168 "a good body the forge does not answer for" '"implement":"no"'
no_tier 168 "a good body the forge does not answer for"

# ---------------------------------------------------------------------------
banner "7. Kit-only: on bootstrap's deletion list, named by the root manual"
# ---------------------------------------------------------------------------
kit_only=$(sed -n 's/^KIT_ONLY="\(.*\)"$/\1/p' "$KIT/bootstrap.sh")
for f in scripts/land.kit.sh tests/land.test.sh; do
	case " $kit_only " in
	*" $f "*) pass "$f is on bootstrap.sh's KIT_ONLY list" ;;
	*) fail "$f is not on bootstrap.sh's KIT_ONLY list — it would ship to a consumer" ;;
	esac
done
# The /merge-train row's naming of the script is held by tests/self-host.test.sh
# F7 alone — by path, by the name "landing script", with baits (#422).

# ---------------------------------------------------------------------------
banner "8. A release's merge lands tagged, and main is judged after the tag (#509, ADR-0015)"
# ---------------------------------------------------------------------------
# A merge that moves VERSION's shared-layer line is a release, and the kit's
# own CI holds main red until its tag exists (self-host F3) — a run that
# started on the merge push, before any tag could. So the landing tags the
# merge commit itself, right after the merge and before it waits; re-runs,
# once, every run that failed; and only then judges main. The log holds the
# forge's calls and the tag's in one order, which is what proves it.
REL="STUB_VER_BEFORE=0.1.0 STUB_VER_AFTER=0.2.0"
# line_of <pattern> — the first log line matching, by number; 0 for none.
line_of() { grep -n -m1 -- "$1" "$STUB_LOG" | cut -d: -f1 | grep . || echo 0; }

# shellcheck disable=SC2086 # REL is two knob words, split on purpose
land $REL STUB_WATCH_RC=1 STUB_WATCH_RC_AFTER=0 190
s_assert_status 0 "a release whose first run failed untagged, green on its re-run, lands with exit 0"
grep -qF "ARGV: git tag -a v0.2.0" "$STUB_LOG" && grep -F "ARGV: git tag -a v0.2.0" "$STUB_LOG" | grep -qF "$STUB_SHA" &&
	pass "it tags the merge commit v0.2.0 (git tag -a v0.2.0 … $STUB_SHA)" ||
	fail "the merge commit was not tagged v0.2.0: $(grep '^ARGV: git' "$STUB_LOG")"
grep -qE "^ARGV: git push origin (refs/tags/)?v0\.2\.0$" "$STUB_LOG" && pass "and pushes the tag to origin" ||
	fail "the tag was never pushed: $(grep '^ARGV: git' "$STUB_LOG")"
_merge=$(line_of '^ARGV: pr merge')
_push=$(line_of '^ARGV: git push')
_watch=$(line_of '^ARGV: run watch')
[ "$_merge" -gt 0 ] && [ "$_push" -gt "$_merge" ] && [ "$_watch" -gt "$_push" ] &&
	pass "the order is merge, tag pushed, then the wait (lines $_merge < $_push < $_watch)" ||
	fail "the order is not merge < tag push < watch: merge $_merge, push $_push, watch $_watch"
[ "$(grep -c '^ARGV: run rerun 901 --failed' "$STUB_LOG")" = 1 ] && pass "the failed run is re-run once, its failed jobs only (gh run rerun 901 --failed)" ||
	fail "the failed run was not re-run exactly once with --failed: $(grep 'run rerun' "$STUB_LOG")"
[ "$(line_of '^ARGV: run rerun')" -gt "$_push" ] && pass "and the re-run comes after the tag is pushed" ||
	fail "the re-run came before the tag was pushed"
[ "$(grep -c '^ARGV: run watch 901' "$STUB_LOG")" = 2 ] && pass "and the re-run is watched to its end" ||
	fail "run 901 was watched $(grep -c '^ARGV: run watch 901' "$STUB_LOG") times, not twice"
ml=$(show 'pr:#190' --kind merge.land)
for tok in '"workflows":"success"' '"release":"v0.2.0"' '"tagged":"yes"' '"reruns":"1"'; do
	printf '%s\n' "$ml" | grep -qF -- "$tok" && pass "merge.land carries $tok" || fail "merge.land lacks $tok: $ml"
done
s_assert_out_has "tagged v0.2.0" "stdout says the release was tagged"
s_assert_err_lacks "land nothing else" "and stderr raises no failure"

# shellcheck disable=SC2086
land $REL 191
s_assert_status 0 "a release green on its first runs lands with exit 0"
grep -q '^ARGV: run rerun' "$STUB_LOG" && fail "a green release was re-run" || pass "and nothing is re-run"
grep -qE "^ARGV: git push origin (refs/tags/)?v0\.2\.0$" "$STUB_LOG" && pass "and it is still tagged" || fail "a green release was not tagged"

# shellcheck disable=SC2086
land $REL STUB_WATCH_RC=1 STUB_WATCH_RC_AFTER=1 192
s_assert_status 1 "a release still red after its one re-run is exit 1"
[ "$(grep -c '^ARGV: run rerun' "$STUB_LOG")" = 1 ] && pass "re-run once, never twice" ||
	fail "re-run $(grep -c '^ARGV: run rerun' "$STUB_LOG") times"
show 'pr:#192' --kind merge.land | grep -qF '"workflows":"failure"' && pass "and recorded with data.workflows=failure" ||
	fail "a release red after its re-run was not recorded as failure: $(show 'pr:#192' --kind merge.land)"
s_assert_err_has "land nothing else" "stderr says to land nothing else"

# shellcheck disable=SC2086
land $REL STUB_PUSH_RC=1 STUB_WATCH_RC=1 193
s_assert_status 1 "a release whose tag the forge refused is exit 1"
grep -q '^ARGV: run rerun' "$STUB_LOG" && fail "a run was re-run with no tag on the forge" ||
	pass "and nothing is re-run — a re-run with no tag fails the same way"
s_assert_err_has "git tag -a v0.2.0 $STUB_SHA" "stderr names the tag command to run by hand"
show 'pr:#193' --kind merge.land | grep -qF '"tagged":"no"' && pass "and merge.land records tagged=no" ||
	fail "a refused tag was not recorded: $(show 'pr:#193' --kind merge.land)"

# shellcheck disable=SC2086
land $REL STUB_PUSH_RC=1 194
s_assert_status 1 "an untagged release is exit 1 even with main green — it is not landed (hard rule 3)"

# shellcheck disable=SC2086
land $REL "STUB_REMOTE_TAG=$STUB_SHA" STUB_WATCH_RC=1 195
s_assert_status 0 "a release already tagged at its merge commit lands with exit 0"
grep -qE '^ARGV: git (tag|push)' "$STUB_LOG" && fail "an existing tag was cut again" || pass "and the tag is not cut again"
[ "$(grep -c '^ARGV: run rerun' "$STUB_LOG")" = 1 ] && pass "but a run that failed is still re-run once" || fail "the failed run was not re-run"

# shellcheck disable=SC2086
land $REL STUB_REMOTE_TAG=1111111111111111111111111111111111111111 196
s_assert_status 1 "a release whose tag already names another commit is exit 1"
grep -qE '^ARGV: git (tag|push)' "$STUB_LOG" && fail "a tag naming another commit was moved or re-cut" ||
	pass "and the tag is never moved"
s_assert_err_has "1111111111111111111111111111111111111111" "stderr names the commit the tag already holds"
s_assert_err_lacks "2222222222222222222222222222222222222222" "and reads the commit an annotated tag peels to, never its tag object"

# A lightweight tag lists the commit alone, with no peeled line (M-2 of the
# review of PR #577).
# shellcheck disable=SC2086
land $REL "STUB_REMOTE_TAG=$STUB_SHA" STUB_REMOTE_TAG_KIND=lightweight 199
s_assert_status 0 "a lightweight tag already on the merge commit is the release's tag: exit 0"
grep -qE '^ARGV: git (tag|push)' "$STUB_LOG" && fail "a lightweight tag on the merge commit was cut again" ||
	pass "and is not cut again"
# shellcheck disable=SC2086
land $REL STUB_REMOTE_TAG=1111111111111111111111111111111111111111 STUB_REMOTE_TAG_KIND=lightweight 200
s_assert_status 1 "a lightweight tag naming another commit is exit 1"
grep -qE '^ARGV: git (tag|push)' "$STUB_LOG" && fail "a lightweight tag naming another commit was moved" ||
	pass "and is never moved"

# The re-run waits for its new attempt to leave `completed` before watching
# it: a watch on the old attempt would report the old failure (M-1).
# shellcheck disable=SC2086
land $REL STUB_WATCH_RC=1 STUB_COMPLETED_VIEWS=2 201
s_assert_status 0 "a re-run whose new attempt shows completed twice first still lands green"
[ "$(grep -c '^ARGV: run view 901' "$STUB_LOG")" = 3 ] &&
	pass "it asked the run's status until it left completed (three asks)" ||
	fail "it asked the run's status $(grep -c '^ARGV: run view 901' "$STUB_LOG") times, not 3"
_last_view=$(grep -n '^ARGV: run view' "$STUB_LOG" | tail -1 | cut -d: -f1)
_second_watch=$(grep -n '^ARGV: run watch 901' "$STUB_LOG" | sed -n 2p | cut -d: -f1)
[ -n "$_second_watch" ] && [ "$_second_watch" -gt "$_last_view" ] &&
	pass "and watched the re-run only after it left completed (line $_last_view < $_second_watch)" ||
	fail "the re-run was watched before its status left completed: view $_last_view, watch ${_second_watch:-none}"

# A re-run the forge refuses is a failure, not a pass (M-3).
# shellcheck disable=SC2086
land $REL STUB_WATCH_RC=1 STUB_RERUN_RC=1 202
s_assert_status 1 "a re-run the forge refuses is exit 1"
show 'pr:#202' --kind merge.land | grep -qF '"workflows":"failure"' && pass "and recorded with data.workflows=failure" ||
	fail "a refused re-run was not recorded as failure: $(show 'pr:#202' --kind merge.land)"
[ "$(grep -c '^ARGV: run watch 901' "$STUB_LOG")" = 1 ] && pass "and a refused re-run is not watched" ||
	fail "a refused re-run was watched $(grep -c '^ARGV: run watch 901' "$STUB_LOG") times"

land STUB_FETCH_RC=1 STUB_WATCH_RC=1 197
s_assert_status 1 "with the merge commit unreadable, the landing is judged as before (a red run is exit 1)"
grep -qE '^ARGV: git (tag|push)' "$STUB_LOG" && fail "an unreadable merge was tagged" || pass "and nothing is tagged"
s_assert_err_has "VERSION" "stderr says it could not read whether the merge bumped VERSION"

land STUB_VER_BEFORE=0.1.0 'STUB_VER_AFTER=0.2.0; touch pwned' 198
grep -qE '^ARGV: git (tag|push)' "$STUB_LOG" && fail "a malformed version line was tagged" ||
	pass "a shared-layer value that is not a version is never tagged"

# /merge-train agrees (ADR-0015 clause 7): its step 4 tags a release between
# the merge and the wait, and judges main after one re-run of what failed.
MT="$KIT/.agents/skills/merge-train/SKILL.md"
# mt_order <file> — exit 0 when the merge, the tag and the watch appear in
# that order in the file; the tag's line is the one the skill spells.
mt_order() {
	awk '
		/gh pr merge "\$PR" --merge/ && !m { m = NR }
		/git tag -a v<version> <merge sha>/ && !t { t = NR }
		/gh run watch/ && !w { w = NR }
		END { exit !(m && t && w && m < t && t < w) }
	' "$1"
}
mt_order "$MT" && pass "/merge-train's step 4 tags a release between the merge and the wait" ||
	fail "/merge-train's step 4 does not cut the release tag between 'gh pr merge' and 'gh run watch'"
grep -qF 'gh run rerun <id> --failed' "$MT" && tr '\n' ' ' <"$MT" | grep -qiE 'rerun <id> --failed[^.]*once|once[^.]*rerun <id> --failed' &&
	pass "/merge-train re-runs a tagged release's failed runs once (gh run rerun <id> --failed)" ||
	fail "/merge-train does not say a tagged release's failed runs are re-run once with gh run rerun <id> --failed"
# The probe can go red: the same skill with the tag moved after the wait.
awk '/git tag -a v<version> <merge sha>/ { held = $0; next } { print } END { print held }' "$MT" >"$SCRATCH/mt.late"
mt_order "$SCRATCH/mt.late" && fail "the order probe passed a skill that tags after the wait — the check is vacuous" ||
	pass "the order probe rejects a skill that tags after the wait"

# ---------------------------------------------------------------------------
banner "9. No pr.iterate at the head commit: refused, or landed on a named reason and recorded (#630)"
# ---------------------------------------------------------------------------
# #625 and #626 landed with no /pr-iterate iteration at their head commit. The
# landing reads the trace (ADR-0018) for a pr.iterate on the PR stamped at or
# after its head commit's date; with none it refuses — exit 2, nothing merged,
# nothing recorded — unless --no-iteration names why, and then merge.land says
# the landing had none. Every PR here is #300 up, so no seed above reaches it.
# no_iter <label> <pr> — refused on the iteration check: the seeded
# pr.iterate stays, so the trace is held to no merge.land and no feedback.
no_iter() {
	_ni_label=$1
	not_landed "$2" "$_ni_label"
	[ "$(events "$2" merge.land)" = 0 ] && [ "$(events "$2" feedback)" = 0 ] &&
		pass "$_ni_label: no landing reached the trace" || fail "$_ni_label: a landing was recorded: $(show "pr:#$2")"
	s_assert_err_has "pr-iterate" "$_ni_label: stderr sends it to /pr-iterate"
	s_assert_err_has "--no-iteration" "$_ni_label: and names the override"
}
land 300
no_iter "no pr.iterate event at all" 300
s_assert_err_has "1234567890123456789012345678901234567890" "stderr names the head commit"

iterated 301
land STUB_HEAD_DATE=2999-01-01T00:00:00Z 301
no_iter "a pr.iterate older than the head commit" 301

iterated 3020
land 302
no_iter "a pr.iterate on another PR only (#3020)" 302

iterated 303
land STUB_HEAD_RC=1 303
no_iter "a forge that does not name the head commit" 303
land STUB_HEAD_DATE=yesterday 303
no_iter "a head date of no known shape" 303

iterated 304
land 304
landed_with 304 "a pr.iterate at the head commit" '"iterated":"yes"'
show 'pr:#304' --kind merge.land | grep -qF '"no_iteration"' && fail "an iterated landing carries a no_iteration reason" ||
	pass "and carries no no_iteration reason"

land 305 --no-iteration 'hotfix: the operator ran the checks by hand'
landed_with 305 "no pr.iterate, with --no-iteration" '"iterated":"no"' '"no_iteration":"hotfix: the operator ran the checks by hand"'
[ "$(merges)" = 1 ] && pass "--no-iteration: one merge call" || fail "--no-iteration: $(merges) merge calls"

iterated 306
land 306 --no-iteration 'not needed'
landed_with 306 "an iteration at head and --no-iteration both" '"iterated":"yes"'
show 'pr:#306' --kind merge.land | grep -qF '"no_iteration"' && fail "an unused override reason was recorded" ||
	pass "and the unused override's reason is not recorded"

land STUB_MERGE_RC=1 307 --no-iteration 'forge rejects it'
show 'pr:#307' --kind merge.land | grep -qF '"iterated":"no"' && pass "a rejected merge's merge.land stopped says it had no iteration too" ||
	fail "the stopped merge.land lacks iterated=no: $(show 'pr:#307' --kind merge.land)"

land 308 --no-iteration ''
s_assert_status 2 "--no-iteration with an empty reason is a usage error"
land 308 --no-iteration
s_assert_status 2 "--no-iteration with no reason is a usage error"

# Unconfigured, nothing can be read and nothing is recorded: the check is
# skipped, said on stderr, and the merge goes on (ADR-0008 clause 2).
: >"$STUB_LOG"
t_run_split env TRACE_DIR= TRACE_CONFIG="$KIT/scripts/trace.config.sh" LAND_POLL_SECONDS=0 sh "$LAND" 309 </dev/null
s_assert_status 0 "unconfigured, a PR with no recorded iteration still lands"
s_assert_err_has "not checked" "and stderr says the iteration was not checked"

t_done "land one PR by hand"
