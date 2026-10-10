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
# The PR's state is one `name=value` line per field — state, isDraft,
# mergeable, mergeStateStatus, reviewDecision, baseRefName, ticket,
# headRefName, title — and the head commit's is oid and committedDate. The
# script reads each field by its name, never by its line (#684), so
# STUB_ORDER=reversed answers the same fields bottom-up. STUB_* variables set
# the forge's answers.
STUBDIR="$SCRATCH/bin"
mkdir -p "$STUBDIR"
cat >"$STUBDIR/gh" <<'EOF'
#!/bin/sh
printf 'ARGV: %s\n' "$*" >>"$STUB_LOG"
# The forge's state for one run: knob assignments land() wrote for it.
[ -s "$STUB_KNOBS" ] && . "$STUB_KNOBS"
# order — the answer's lines as asked, or bottom-up under STUB_ORDER=reversed.
order() { if [ "${STUB_ORDER:-}" = reversed ]; then sed -n '1!G;h;$p'; else cat; fi; }
# jq_answer — under STUB_PR_JSON, run the script's OWN --jq program over a
# canned forge answer with jq, as gh would: the key names the script reads are
# then held to the keys its query emits (#684). Exits the stub when it answered.
jq_answer() {
	[ -n "${STUB_PR_JSON:-}" ] || return 0
	prog= prev=
	for a; do [ "$prev" = --jq ] && prog=$a; prev=$a; done
	jq -r "$prog" "$STUB_PR_JSON"
	exit
}
case " $* " in
*" pr view "*"mergeCommit"*) printf '%s\n' "${STUB_SHA-abcdef0123456789abcdef0123456789abcdef01}" ;;
*" pr view "*"headRefOid"*)
	# The head commit, and the date it was committed: the iteration check
	# reads the trace for a pr.iterate at or after it (#630).
	[ "${STUB_HEAD_RC:-0}" = 0 ] || { echo 'gh: HTTP 502 Bad Gateway' >&2; exit "$STUB_HEAD_RC"; }
	jq_answer "$@"
	printf 'oid=%s\ncommittedDate=%s\n' "${STUB_HEAD_OID-1234567890123456789012345678901234567890}" "${STUB_HEAD_DATE-2000-01-01T00:00:00Z}" | order
	;;
*" pr view "*"body"*)
	# The PR body is a file the case wrote — free text, quotes and all, so it
	# never passes through the knob file's quoting.
	[ "${STUB_BODY_RC:-0}" = 0 ] || { echo 'gh: HTTP 502 Bad Gateway' >&2; exit "$STUB_BODY_RC"; }
	[ -z "${STUB_BODY_FILE:-}" ] || cat "$STUB_BODY_FILE"
	;;
*" pr view "*)
	[ "${STUB_VIEW_RC:-0}" = 0 ] || { echo 'gh: HTTP 502 Bad Gateway' >&2; exit "$STUB_VIEW_RC"; }
	jq_answer "$@"
	printf '%s\n' "state=${STUB_PRSTATE:-OPEN}" "isDraft=${STUB_DRAFT:-false}" "mergeable=${STUB_MERGEABLE:-MERGEABLE}" \
		"mergeStateStatus=${STUB_MSS:-CLEAN}" "reviewDecision=${STUB_REVIEW-APPROVED}" baseRefName=main "ticket=${STUB_TICKET-77}" \
		"headRefName=${STUB_BRANCH-feat/x}" "title=${STUB_TITLE:-feat(x): a slice}" | order
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
*" run rerun "*)
	# A refused re-run says why on stderr, as the forge's CLI does.
	[ "${STUB_RERUN_RC:-0}" = 0 ] || { printf '%s\n' "${STUB_RERUN_ERR:-run cannot be rerun}" >&2; exit "$STUB_RERUN_RC"; }
	;;
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
fetch | show | ls-remote | tag | push | cat-file | ls-tree) printf 'ARGV: git %s\n' "$*" >>"$STUB_LOG" ;;
*) if [ -n "$_c" ]; then exec "$REAL_GIT" -C "$_c" "$@"; else exec "$REAL_GIT" "$@"; fi ;;
esac
case $1 in
fetch) exit "${STUB_FETCH_RC:-0}" ;;
show)
	case $2 in
	*'^1:VERSION') printf '# a note\nshared-layer: %s\n' "${STUB_VER_BEFORE:-0.1.0}" ;;
	*':VERSION') printf '# a note\nshared-layer: %s\n' "${STUB_VER_AFTER:-0.1.0}" ;;
	*':.github/workflows/'?*) cat "${STUB_WORKFLOWS:-/nonexistent}/${2##*/}" 2>/dev/null || exit 128 ;;
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
# The merge commit is held here unless STUB_CATFILE_RC says not; its
# workflow directory is STUB_WORKFLOWS, a scratch tree, and absent without it.
cat-file) exit "${STUB_CATFILE_RC:-0}" ;;
ls-tree) [ -d "${STUB_WORKFLOWS:-/nonexistent}" ] || exit 128; ls "$STUB_WORKFLOWS" ;;
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
# The root checkout the landing fast-forwards (#636) is the script's own repo's
# main worktree unless LAND_ROOT_CHECKOUT names another: every run here names
# a scratch path that is no checkout, so no case ever moves this repo's root.
# Section 11 points it at scratch checkouts of its own.
LAND_ROOT_CHECKOUT="$SCRATCH/no-root"
export LAND_ROOT_CHECKOUT

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

# seed <kind> <outcome> <PR>… — record one <kind> event on each PR, now: the
# stub's head commit is dated 2000 unless a case says otherwise, so each event
# sits at its head.
seed() {
	_sd_kind=$1
	_sd_outcome=$2
	shift 2
	# The keys each kind's shape asks for; one word each, split on purpose.
	case $_sd_kind in
	pr.iterate) _sd_data='data.iteration=1 data.applied=0 data.rejected=0 data.escalated=0' ;;
	*)
		# `confirm` is Axis 2's word alone, so its verdict is Axis 2's.
		_sd_data='data.axis=1'
		[ "$_sd_outcome" != confirm ] || _sd_data='data.axis=2'
		;;
	esac
	for _sd_pr in "$@"; do
		# shellcheck disable=SC2086
		env TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh" TRACE_QUIET=1 sh "$TRACE" emit "kind=$_sd_kind" \
			"subject=pr:#$_sd_pr" "outcome=$_sd_outcome" $_sd_data reason=seeded </dev/null >/dev/null 2>&1 ||
			fail "could not seed a $_sd_kind event on pr:#$_sd_pr"
	done
}
# reviewed <PR>… — a /review-pr verdict at each PR's head (#673).
reviewed() { seed review.verdict pass "$@"; }
# iterated <PR>… — a PR the loop drove to its head: a /pr-iterate iteration
# (#630) and the verdict of the review it ran (#673). Section 1's PRs are
# refused before the trace is read, and #140 is section 4's unconfigured run,
# whose trace must stay empty.
iterated() {
	seed pr.iterate stopped "$@"
	reviewed "$@"
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

# The forge's answer read by field name, never by line (#684): the same fields
# answered bottom-up land the same PR, every value where it belongs — and a
# draft answered bottom-up is still a draft.
land STUB_ORDER=reversed STUB_TICKET=91 STUB_BRANCH=feat/reordered STUB_TITLE='feat(y): reordered' 127
s_assert_status 0 "a forge answering the fields in another order lands the PR"
ml=$(show 'pr:#127' --kind merge.land)
for tok in '"related":"ticket:#91"' '"reason":"feat(y): reordered"' '"iterated":"yes"' '"reviewed":"yes"'; do
	printf '%s\n' "$ml" | grep -qF -- "$tok" && pass "reordered, merge.land still carries $tok" || fail "reordered, merge.land lacks $tok: $ml"
done
po=$(show 'pr:#127' --kind pr.open)
printf '%s\n' "$po" | grep -qF '"related":"ticket:#91 branch:feat/reordered"' && pass "reordered, pr.open names the head branch and the ticket" ||
	fail "reordered, pr.open lost its ticket or branch: $po"
grep -q '^ARGV: run list --branch main ' "$STUB_LOG" && pass "reordered, the base branch is still main" ||
	fail "reordered, the base branch was misread: $(grep 'run list' "$STUB_LOG")"
land STUB_ORDER=reversed STUB_DRAFT=true 108
not_landed 108 "a draft answered bottom-up"
printf '%s\n' "$S_ERR" | grep -qF 'it is a draft' && pass "a draft answered bottom-up is refused as a draft" ||
	fail "a draft answered bottom-up was refused for another reason: $S_ERR"
# The query's own keys, not only the stub's (#684, review M-1): where jq is on
# PATH, the stub runs the script's --jq programs over a forge answer whose keys
# sit in another order than the query names them. A field the script reads by
# a name its query does not emit leaves that value empty, and this case fails.
if command -v jq >/dev/null 2>&1; then
	cat >"$SCRATCH/pr128.json" <<'JSON'
{"title": "feat(z): through jq", "commits": [{"oid": "1234567890123456789012345678901234567890", "committedDate": "2000-01-01T00:00:00Z"}],
 "headRefName": "feat/through-jq", "closingIssuesReferences": [{"number": 93}], "baseRefName": "main", "reviewDecision": null,
 "mergeStateStatus": "CLEAN", "mergeable": "MERGEABLE", "isDraft": false, "state": "OPEN",
 "headRefOid": "1234567890123456789012345678901234567890"}
JSON
	land STUB_PR_JSON="$SCRATCH/pr128.json" 128
	s_assert_status 0 "the script's own --jq programs, run by jq, land the PR"
	ml=$(show 'pr:#128' --kind merge.land)
	for tok in '"related":"ticket:#93"' '"reason":"feat(z): through jq"' '"iterated":"yes"' '"reviewed":"yes"'; do
		printf '%s\n' "$ml" | grep -qF -- "$tok" && pass "through jq, merge.land carries $tok" || fail "through jq, merge.land lacks $tok: $ml"
	done
	po=$(show 'pr:#128' --kind pr.open)
	printf '%s\n' "$po" | grep -qF '"related":"ticket:#93 branch:feat/through-jq"' && pass "through jq, pr.open names the head branch" ||
		fail "through jq, pr.open lost its ticket or branch: $po"
else
	skip "no jq on PATH — the script's own --jq programs are not run by this suite here"
fi

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

# No run for a merge whose base branch's workflows declare a push trigger is
# no verdict (#688): on 2026-10-09 the forge made no push run for the merge of
# #670, and the landing recorded workflows=none and reported it done. The
# workflows are read as the merge commit holds them; `none` stays the answer
# only for a tree none of whose workflows declares a push trigger.
mkdir -p "$SCRATCH/wf-push" "$SCRATCH/wf-nopush"
printf 'name: ci\non:\n  push:\n    branches: [main]\n  pull_request:\njobs: {}\n' >"$SCRATCH/wf-push/ci.yml"
printf 'name: release\n"on": [push, workflow_dispatch]\njobs: {}\n' >"$SCRATCH/wf-push/release.yaml"
printf 'name: lint\non: [pull_request]\njobs:\n  push:\n    runs-on: x\n' >"$SCRATCH/wf-push/lint.yml"
printf 'name: pr\n# on a push nothing runs here\non:\n  pull_request:\n    types: [opened] # push\njobs:\n  push:\n    runs-on: x\n' >"$SCRATCH/wf-nopush/pr.yml"
printf 'name: manual\non: workflow_dispatch\njobs: {}\n' >"$SCRATCH/wf-nopush/manual.yml"
printf 'push: not a workflow\n' >"$SCRATCH/wf-nopush/README.md"

land STUB_RUNS= "STUB_WORKFLOWS=$SCRATCH/wf-push" 155
s_assert_status 1 "no run for a merge whose workflows declare a push trigger is exit 1 — not 2, so a train stops"
ml=$(show 'pr:#155' --kind merge.land)
printf '%s\n' "$ml" | grep -qF '"outcome":"landed"' && printf '%s\n' "$ml" | grep -qF '"workflows":"unknown"' &&
	pass "and records landed with data.workflows=unknown, not none" || fail "an unverified merge was not recorded unknown: $ml"
s_assert_err_has "unverified" "stderr says the merge is unverified"
s_assert_err_has "ci.yml" "stderr names a block-form push workflow it expected"
s_assert_err_has "release.yaml" "stderr names a flow-form push workflow it expected"
printf '%s\n' "$S_ERR" | grep -qF 'lint.yml' && fail "a pull_request-only workflow was named as expected on push: $S_ERR" ||
	pass "and does not name a workflow with no push trigger"
s_assert_out_has "workflows unknown" "stdout's landing line says workflows unknown"
[ "$(events 155 feedback)" = 1 ] && pass "and the landing still gets its feedback" || fail "no feedback after an unverified merge"

land STUB_RUNS= "STUB_WORKFLOWS=$SCRATCH/wf-nopush" 156
s_assert_status 0 "no run for a merge whose workflows declare no push trigger: still exit 0"
show 'pr:#156' --kind merge.land | grep -qF '"workflows":"none"' && pass "and records data.workflows=none" ||
	fail "a tree with no push trigger was not recorded workflows=none: $(show 'pr:#156')"

land STUB_RUNS= STUB_CATFILE_RC=128 "STUB_WORKFLOWS=$SCRATCH/wf-nopush" 157
s_assert_status 1 "no run, and a merge commit whose workflows cannot be read here: exit 1"
show 'pr:#157' --kind merge.land | grep -qF '"workflows":"unknown"' && pass "and records data.workflows=unknown" ||
	fail "an unreadable workflow tree was recorded as known: $(show 'pr:#157')"
s_assert_err_has "could not be read" "stderr says the merge's workflows could not be read — the merge is unverified"
# A workflow file the tree lists but git cannot read is no answer either: a
# directory named like one stands in for it, beside a file with no push.
mkdir -p "$SCRATCH/wf-unread/broken.yml"
cp "$SCRATCH/wf-nopush/manual.yml" "$SCRATCH/wf-unread/"
land STUB_RUNS= "STUB_WORKFLOWS=$SCRATCH/wf-unread" 159
s_assert_status 1 "no run, and a workflow file that cannot be read: exit 1, never none"
show 'pr:#159' --kind merge.land | grep -qF '"workflows":"unknown"' && pass "and records data.workflows=unknown" ||
	fail "an unreadable workflow file was read as no push trigger: $(show 'pr:#159')"
s_assert_err_has "could not be read" "stderr says the workflows could not be read"

land STUB_RUNS= "STUB_WORKFLOWS=$SCRATCH/wf-push" 158 --train
s_assert_status 1 "the train's landing of an unverified merge is exit 1 — the train stops on it"
show 'pr:#158' --kind merge.land | grep -qF '"workflows":"unknown"' && pass "and records data.workflows=unknown, via the train" ||
	fail "the train's unverified merge was not recorded unknown: $(show 'pr:#158')"

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
s_assert_err_has "run cannot be rerun" "and stderr carries the forge's refusal"

# A re-run refused because the run is still going is no verdict: the landing
# waits for that run and judges its end (#661 — #659's release was recorded
# failure while main's run on it ended success).
BUSY="STUB_RERUN_RC=1"
BUSY_ERR="STUB_RERUN_ERR=run 901 cannot be rerun; This workflow is already running"
iterated 230 231 232
# shellcheck disable=SC2086
land $REL STUB_WATCH_RC=1 $BUSY "$BUSY_ERR" STUB_WATCH_RC_AFTER=0 230
s_assert_status 0 "a re-run refused as already running, whose run then ends green, lands with exit 0"
show 'pr:#230' --kind merge.land | grep -qF '"workflows":"success"' && pass "and is recorded with data.workflows=success" ||
	fail "a still-running run that ended green was not recorded success: $(show 'pr:#230' --kind merge.land)"
show 'pr:#230' --kind merge.land | grep -qF '"reruns":"0"' && pass "and data.reruns=0 — the forge started no re-run" ||
	fail "a refused re-run was counted as one: $(show 'pr:#230' --kind merge.land)"
[ "$(grep -c '^ARGV: run watch 901' "$STUB_LOG")" = 2 ] && pass "it watched the running run to its end" ||
	fail "run 901 was watched $(grep -c '^ARGV: run watch 901' "$STUB_LOG") times, not twice"
s_assert_err_has "already running" "stderr says the run was still going"
s_assert_err_lacks "land nothing else" "and raises no failure"

# shellcheck disable=SC2086
land $REL STUB_WATCH_RC=1 $BUSY "$BUSY_ERR" STUB_WATCH_RC_AFTER=1 231
s_assert_status 1 "a re-run refused as already running, whose run then ends red, is exit 1"
show 'pr:#231' --kind merge.land | grep -qF '"workflows":"failure"' && pass "and is recorded with data.workflows=failure" ||
	fail "a still-running run that ended red was not recorded failure: $(show 'pr:#231' --kind merge.land)"
s_assert_err_has "land nothing else" "stderr says to land nothing else"

# shellcheck disable=SC2086
land $REL STUB_WATCH_RC=1 $BUSY "STUB_RERUN_ERR=HTTP 403: Resource not accessible by integration" 232
s_assert_status 1 "a re-run refused for any other reason is still exit 1"
show 'pr:#232' --kind merge.land | grep -qF '"workflows":"failure"' && pass "and recorded with data.workflows=failure" ||
	fail "a re-run refused for another reason was not recorded failure: $(show 'pr:#232' --kind merge.land)"
show 'pr:#232' --kind merge.land | grep -qF '"reruns":"0"' && pass "and data.reruns=0 — a refused re-run is never counted" ||
	fail "a re-run refused for another reason was counted as one: $(show 'pr:#232' --kind merge.land)"
[ "$(grep -c '^ARGV: run watch 901' "$STUB_LOG")" = 1 ] && pass "and its run is not watched again" ||
	fail "a run refused for another reason was watched $(grep -c '^ARGV: run watch 901' "$STUB_LOG") times"
s_assert_err_has "Resource not accessible" "and stderr names the refusal"

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
# landing reads the trace (ADR-0019) for a pr.iterate on the PR stamped at or
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

reviewed 305 307
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

land 308 "--no-iteration" "two
lines"
s_assert_status 2 "--no-iteration with a reason that is not one line is a usage error, before any merge"
[ "$(merges)" = 0 ] && pass "and nothing reached the forge" || fail "a multi-line reason was merged on: $(merges) merge calls"

land STUB_HEAD_OID='not-a-sha' 310
no_iter "a head the forge names in no sha shape" 310
s_assert_err_has "<unnamed>" "stderr marks the head commit unnamed, never echoing the forge's text"
land STUB_HEAD_DATE= 310
s_assert_err_has "<undated>" "stderr marks an undated head as such"

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

# ---------------------------------------------------------------------------
banner "10. /merge-train's merge.land takes the landing script's fields (#634)"
# ---------------------------------------------------------------------------
# Two emitters write merge.land: this script and /merge-train's step 4. A
# reader joins them as one kind, so they write one field set. The script's set
# is every data key its landed merge.land events above carry — a release, a
# tier and an override among them — and the train's is the data keys its emit
# line names, compared whole. Four keys are the script's alone: data.iterated,
# data.no_iteration, data.reviewed and data.no_review answer a trace read
# (ADR-0019) that no chain skill makes (ADR-0008 clause 7), so the train names
# none of them.
LAND_ONLY='iterated no_iteration reviewed no_review'
land_keys=$(env TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh" sh "$TRACE" export 2>/dev/null |
	grep -F '"kind":"merge.land"' | grep -F '"outcome":"landed"' |
	sed 's/.*"data":{//' | grep -oE '(^|,)"[a-z_]+":' | tr -d ',":' | sort -u)
for _k in $LAND_ONLY; do land_keys=$(printf '%s\n' "$land_keys" | grep -vx "$_k"); done
# train_keys <skill file> — the data keys /merge-train's merge.land line names.
train_keys() { grep -F 'kind=merge.land' "$1" | grep -oE 'data\.[a-z_]+=' | sed 's/^data\.//; s/=$//' | sort -u; }
[ "$(printf '%s\n' "$land_keys" | grep -c .)" -ge 10 ] && pass "the landings above yield the script's field set ($(echo $land_keys))" ||
	fail "the landings above yield too few fields to compare: $(echo $land_keys)"
if [ "$(train_keys "$MT")" = "$land_keys" ]; then
	pass "/merge-train's merge.land names the landing script's fields, no more and no fewer"
else
	fail "/merge-train's merge.land fields differ from the landing script's — train: $(echo $(train_keys "$MT")); script: $(echo $land_keys)"
fi
# The probe can go red: the train's line with one field dropped.
sed '/kind=merge.land/s/ data\.waited=[^ ]*//' "$MT" >"$SCRATCH/mt.short"
[ "$(train_keys "$SCRATCH/mt.short")" = "$land_keys" ] && fail "the field probe passed a train line with data.waited dropped — the check is vacuous" ||
	pass "the field probe rejects a train line with a field dropped"

# ---------------------------------------------------------------------------
banner "11. After the landing, a clean root checkout on main is fast-forwarded; any other is left and named (#636)"
# ---------------------------------------------------------------------------
# mkroot <dir> — a checkout on main at c1, its origin/main one commit ahead
# at c2, as a fetch would leave it (the stub's fetch fetches nothing).
mkroot() {
	mkdir -p "$1" && t_git_identity "$1" t t@t &&
		t_write "$1" f one && t_commit "$1" c1 >/dev/null &&
		t_write "$1" f two && t_commit "$1" c2 >/dev/null &&
		git -C "$1" update-ref refs/remotes/origin/main HEAD &&
		git -C "$1" reset -q --hard HEAD^
}
head_of() { "$REAL_GIT" -C "$1" rev-parse HEAD; }
# landed_with_root <dir> <pr> [STUB_<KNOB>=<value> …] — land <pr> with the
# root checkout at <dir>, the knobs in the environment of that one run.
landed_with_root() {
	_lr_root=$1
	_lr_pr=$2
	shift 2
	: >"$STUB_LOG"
	t_run_split env LAND_ROOT_CHECKOUT="$_lr_root" LAND_POLL_SECONDS=0 "$@" sh "$LAND" "$_lr_pr" </dev/null
}
iterated 211 212 213 214 215

R="$SCRATCH/root-clean"
mkroot "$R" || fail "could not build the clean root checkout"
want=$("$REAL_GIT" -C "$R" rev-parse origin/main)
landed_with_root "$R" 205
s_assert_status 0 "a landing with a clean root checkout exits 0"
[ "$(head_of "$R")" = "$want" ] && pass "the clean root checkout on main is fast-forwarded to origin/main" ||
	fail "the clean root checkout was not fast-forwarded: HEAD $(head_of "$R"), origin/main $want"
# One fetch for the release question, one in the root checkout before it moves.
[ "$(grep -c '^ARGV: git fetch -q origin main$' "$STUB_LOG")" = 2 ] && pass "it fetches the base again for the root checkout" ||
	fail "it did not fetch the base for the root checkout: $(grep 'git' "$STUB_LOG")"
s_assert_err_has "fast-forwarded the root checkout $R" "stderr says the root was fast-forwarded, and where"

R="$SCRATCH/root-dirty"
mkroot "$R" || fail "could not build the dirty root checkout"
was=$(head_of "$R")
echo edit >"$R/f"
landed_with_root "$R" 206
s_assert_status 0 "a dirty root checkout does not fail the landing"
[ "$(head_of "$R")" = "$was" ] && [ "$(cat "$R/f")" = edit ] && pass "a dirty root checkout is left alone, its edit intact" ||
	fail "a dirty root checkout was touched: HEAD $(head_of "$R"), f '$(cat "$R/f")'"
s_assert_err_has "left the root checkout $R alone" "stderr names the dirty root it left"
s_assert_err_has "uncommitted" "and says why: uncommitted changes"

R="$SCRATCH/root-branch"
mkroot "$R" || fail "could not build the off-main root checkout"
git -C "$R" checkout -q -b feat/elsewhere
was=$(head_of "$R")
landed_with_root "$R" 207
s_assert_status 0 "a root checkout off main does not fail the landing"
[ "$(head_of "$R")" = "$was" ] && [ "$("$REAL_GIT" -C "$R" rev-parse main)" = "$was" ] &&
	pass "a root checkout off main is left alone, main not moved" || fail "a root checkout off main was touched"
s_assert_err_has "left the root checkout $R alone" "stderr names the off-main root it left"
s_assert_err_has "feat/elsewhere" "and says which branch it is on"

R="$SCRATCH/root-diverged"
mkroot "$R" || fail "could not build the diverged root checkout"
t_write "$R" g three && t_commit "$R" local >/dev/null
was=$(head_of "$R")
landed_with_root "$R" 208
s_assert_status 0 "a diverged root checkout does not fail the landing"
[ "$(head_of "$R")" = "$was" ] && pass "a diverged root checkout is left alone" || fail "a diverged root checkout was moved"
s_assert_err_has "left the root checkout $R alone" "stderr names the diverged root it left"
s_assert_err_has "diverged" "and says it has diverged"

landed_with_root "$SCRATCH/no-root" 209
s_assert_status 0 "a root path that is no checkout does not fail the landing"
s_assert_err_has "is not a checkout" "and stderr says so"

R="$SCRATCH/root-untracked"
mkroot "$R" || fail "could not build the root checkout with an untracked file"
t_write "$R" scratch.txt note
landed_with_root "$R" 211
[ "$(head_of "$R")" = "$("$REAL_GIT" -C "$R" rev-parse origin/main)" ] && [ -f "$R/scratch.txt" ] &&
	pass "an untracked file alone does not hold the root back: fast-forwarded, the file kept (worktree-cleanup's rule)" ||
	fail "a root with only an untracked file was not fast-forwarded: $S_ERR"

R="$SCRATCH/root-detached"
mkroot "$R" || fail "could not build the detached root checkout"
git -C "$R" checkout -q --detach
was=$(head_of "$R")
landed_with_root "$R" 203
[ "$(head_of "$R")" = "$was" ] && pass "a detached root checkout is left alone" || fail "a detached root checkout was moved"
s_assert_err_has "detached" "and stderr says its HEAD is detached"

R="$SCRATCH/root-current"
mkroot "$R" || fail "could not build the up-to-date root checkout"
git -C "$R" merge -q --ff-only origin/main
landed_with_root "$R" 204
s_assert_err_has "already at origin/main" "a root already at origin/main is said to be so"

R="$SCRATCH/root-nofetch"
mkroot "$R" || fail "could not build the root checkout whose fetch fails"
was=$(head_of "$R")
landed_with_root "$R" 210 STUB_FETCH_RC=1
s_assert_status 0 "a fetch that fails in the root does not fail the landing"
[ "$(head_of "$R")" = "$was" ] && pass "a root whose fetch failed is left alone" || fail "a root whose fetch failed was moved"
s_assert_err_has "fetching origin main there failed" "and stderr says the fetch failed"

R="$SCRATCH/root-noorigin"
mkroot "$R" || fail "could not build the root checkout with no origin/main"
git -C "$R" update-ref -d refs/remotes/origin/main
was=$(head_of "$R")
landed_with_root "$R" 212
[ "$(head_of "$R")" = "$was" ] && pass "a root with no origin/main is left alone" || fail "a root with no origin/main was moved"
s_assert_err_has "no origin/main to follow" "and stderr says there is nothing to follow"

# The default: the main worktree of the repo the script runs from — here a
# scratch repo whose linked worktree holds a copy of the kit's scripts.
R="$SCRATCH/root-default"
W="$SCRATCH/root-default-wt"
mkroot "$R" || fail "could not build the default root checkout"
git -C "$R" worktree add -q "$W" -b side 2>/dev/null && cp -R "$KIT/scripts" "$W/" ||
	fail "could not build the linked worktree the default case runs from"
: >"$STUB_LOG"
t_run_split env LAND_ROOT_CHECKOUT= LAND_POLL_SECONDS=0 sh "$W/scripts/land.kit.sh" 213 </dev/null
s_assert_status 0 "with no LAND_ROOT_CHECKOUT, the landing still exits 0"
[ "$(head_of "$R")" = "$("$REAL_GIT" -C "$R" rev-parse origin/main)" ] &&
	pass "with no LAND_ROOT_CHECKOUT, the main worktree of the script's repo is the root fast-forwarded" ||
	fail "the default root was not the main worktree: $S_ERR"

# ---------------------------------------------------------------------------
banner "12. A PR the trace never saw opened gets its pr.open from the landing (#638)"
# ---------------------------------------------------------------------------
# A PR opened outside /implement left no pr.open, so /retro's join from ticket
# to PR had nothing to read for it. The landing writes one when the trace holds
# none on pr:#<N> — before merge.land, related to the ticket and the branch,
# marked data.via=land — and never a second when one is there.
opens() { show "pr:#$1" --kind pr.open; }
iterated 400 401 402 403
land 400
s_assert_status 0 "a PR with no pr.open lands"
[ "$(events 400 pr.open)" = 1 ] && pass "the landing wrote one pr.open for pr:#400" ||
	fail "$(events 400 pr.open) pr.open events for pr:#400"
po=$(opens 400)
for tok in '"outcome":"opened"' '"related":"ticket:#77 branch:feat/x"' '"via":"land"' '"reason":"feat(x): a slice"'; do
	printf '%s\n' "$po" | grep -qF -- "$tok" && pass "the fallback pr.open carries $tok" || fail "the fallback pr.open lacks $tok: $po"
done
order=$(show 'pr:#400' | grep -oE '"kind":"(pr.open|merge.land)"' | tr '\n' ' ')
[ "$order" = '"kind":"pr.open" "kind":"merge.land" ' ] && pass "pr.open is written before merge.land" ||
	fail "the events are out of order: $order"

env TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh" TRACE_QUIET=1 sh "$TRACE" emit kind=pr.open subject=pr:#401 \
	related='ticket:#77 branch:feat/y' outcome=opened reason=seeded </dev/null >/dev/null 2>&1 ||
	fail "could not seed a pr.open event on pr:#401"
land 401
[ "$(events 401 pr.open)" = 1 ] && pass "a PR /implement opened keeps its one pr.open — none added" ||
	fail "$(events 401 pr.open) pr.open events for pr:#401"
opens 401 | grep -qF '"via":"land"' && fail "the landing wrote over a PR that had its pr.open" ||
	pass "and the one there is the session's, not the landing's"

land STUB_BRANCH='feat/x; rm -rf' STUB_TICKET= 402
po=$(opens 402)
printf '%s\n' "$po" | grep -qF '"related"' && fail "a branch of no ref shape, with no ticket, still reached related: $po" ||
	pass "a branch of no ref shape is left out, never copied into the trace"
[ "$(events 402 pr.open)" = 1 ] && pass "and the pr.open is written without it" || fail "$(events 402 pr.open) pr.open events for pr:#402"

land STUB_TICKET= 403
opens 403 | grep -qF '"related":"branch:feat/x"' && pass "with no ticket known, related names the branch alone" ||
	fail "with no ticket, the pr.open's related is not the branch alone: $(opens 403)"

# #404 is seeded with no pr.iterate, so the iteration check refuses it.
land 404
[ "$(events 404 pr.open)" = 0 ] && pass "a refused PR gets no pr.open either" || fail "a refused PR was recorded opened"

reviewed 405
land STUB_MERGE_RC=1 405 --no-iteration 'forge rejects it'
[ "$(events 405 pr.open)" = 1 ] && pass "a merge the forge rejects still records the PR opened" ||
	fail "$(events 405 pr.open) pr.open events for the rejected pr:#405"

# ---------------------------------------------------------------------------
banner "13. The train lands through this script: --train (#662)"
# ---------------------------------------------------------------------------
# On 2026-10-08 a train landed four PRs with their release check red: it wrote
# its own merge.land and so never met this script's gate. Where the root
# manual names the landing script, /merge-train runs it per PR with --train
# after its own ordering and update-branch steps. The gate is the same one —
# a red required check is exit 2, nothing merged, nothing recorded, so the
# train skips the PR — and the record is this script's, marked
# data.via=train. The verdict stays the train's: it asks after the merge and
# says who answered (data.by), which no landing run can, so --train writes
# no feedback of its own.
iterated 500 501 502
land STUB_CHECKS_RC=1 500 --train
s_assert_status 2 "the train's landing of a PR with a red required check is refused: exit 2, the train's skip"
[ "$(merges)" = 0 ] && pass "and the PR is skipped, not merged — no merge call reached the forge" ||
	fail "the train's landing merged a PR with a red required check"
[ "$(show 'pr:#500' --kind merge.land | grep -c .)" = 0 ] && pass "and no merge.land is recorded for the skipped PR" ||
	fail "a refused train landing recorded a merge.land: $(show 'pr:#500' --kind merge.land)"
s_assert_err_has "checks" "and stderr names the checks as what refused it"

land 501 --train
s_assert_status 0 "a green PR the train lands through the script exits 0"
[ "$(merges)" = 1 ] && pass "merged once" || fail "$(merges) merge calls for the train's green PR"
ml=$(show 'pr:#501' --kind merge.land)
for tok in '"outcome":"landed"' '"via":"train"' "\"merge_sha\":\"$STUB_SHA\"" '"iterated":"yes"'; do
	printf '%s\n' "$ml" | grep -qF -- "$tok" && pass "the train's merge.land carries $tok" || fail "the train's merge.land lacks $tok: $ml"
done
[ "$(events 501 feedback)" = 0 ] && pass "--train writes no feedback: the verdict is the train's to record" ||
	fail "--train wrote $(events 501 feedback) feedback event(s) — the train's own would make a second"
s_assert_out_has "feedback: left to the train" "stdout says the verdict is left to the train"

land 502 --train --unasked 'nobody here'
s_assert_status 2 "--train with --unasked is a usage error: the train records the verdict"
[ "$(merges)" = 0 ] && pass "and nothing is merged" || fail "a usage error still merged"
s_assert_err_has "drop --unasked" "and stderr names --unasked as what made it one"

# The manual's row is where the train reads how to run the script.
grep -F '| Land a batch of green PRs' "$KIT/AGENTS.md" | grep -qF -- '--train' &&
	pass "the root manual's landing row names --train" ||
	fail "the root manual's landing row does not name --train — the train cannot tell how to run the script"

# ---------------------------------------------------------------------------
banner "14. No review.verdict at the head commit: refused, or landed on a named reason and recorded (#673)"
# ---------------------------------------------------------------------------
# On 2026-10-09 #665's review degraded and posted with no review.verdict; the
# landing checked for an iteration at the head and not for a review, and
# landed it. The same check as section 9's, for the review: a review.verdict
# on the PR, any axis and any outcome, stamped at or after its head commit's
# date — else exit 2, nothing merged, nothing recorded, unless --no-review
# names why, and then merge.land says the landing had none. Every PR here is
# #600 up, so no seed above reaches it.
# no_rev <label> <pr> — refused on the review check, the trace untouched.
no_rev() {
	_nr_label=$1
	not_landed "$2" "$_nr_label"
	[ "$(events "$2" merge.land)" = 0 ] && [ "$(events "$2" feedback)" = 0 ] &&
		pass "$_nr_label: no landing reached the trace" || fail "$_nr_label: a landing was recorded: $(show "pr:#$2")"
	s_assert_err_has "review-pr" "$_nr_label: stderr sends it to /review-pr"
	s_assert_err_has "--no-review" "$_nr_label: and names the override"
}
seed pr.iterate green 600
land 600
no_rev "an iteration at head and no review.verdict at all" 600
s_assert_err_has "1234567890123456789012345678901234567890" "stderr names the head commit"

land 601
no_rev "neither an iteration nor a verdict" 601
s_assert_err_has "pr-iterate" "and the one refusal names the missing iteration as well"
s_assert_err_has "--no-iteration" "and both overrides"

reviewed 602
land STUB_HEAD_DATE=2999-01-01T00:00:00Z 602 --no-iteration 'iteration aside'
no_rev "a review.verdict older than the head commit" 602

reviewed 6030
seed pr.iterate green 603
land 603
no_rev "a review.verdict on another PR only (#6030)" 603

seed pr.iterate green 604
land STUB_HEAD_RC=1 604 --no-iteration 'iteration aside'
no_rev "a forge that does not date the head commit" 604

seed review.verdict blocked 605
seed pr.iterate red 605
land 605
landed_with 605 "a blocked verdict at the head — any outcome counts; the gate judges the checks" '"reviewed":"yes"'

seed pr.iterate green 606
seed review.verdict confirm 606
land 606
landed_with 606 "an Axis-2 verdict at the head" '"reviewed":"yes"' '"iterated":"yes"'
show 'pr:#606' --kind merge.land | grep -qF '"no_review"' && fail "a reviewed landing carries a no_review reason" ||
	pass "and carries no no_review reason"

seed pr.iterate green 607
land 607 --no-review 'the review degraded; read by hand'
landed_with 607 "no review.verdict, with --no-review" '"reviewed":"no"' '"no_review":"the review degraded; read by hand"' '"iterated":"yes"'
[ "$(merges)" = 1 ] && pass "--no-review: one merge call" || fail "--no-review: $(merges) merge calls"

iterated 608
land 608 --no-review 'not needed'
landed_with 608 "a verdict at head and --no-review both" '"reviewed":"yes"'
show 'pr:#608' --kind merge.land | grep -qF '"no_review"' && fail "an unused --no-review reason was recorded" ||
	pass "and the unused override's reason is not recorded"

# The documented path for a prose-only PR — a diary stamp nobody iterated or
# reviewed: both overrides, each naming why, and both recorded.
land 609 --no-iteration 'prose-only: diary stamp' --no-review 'prose-only: diary stamp'
landed_with 609 "a prose-only PR on both overrides" '"iterated":"no"' '"reviewed":"no"' '"no_review":"prose-only: diary stamp"'

seed pr.iterate green 610
land STUB_MERGE_RC=1 610 --no-review 'forge rejects it'
show 'pr:#610' --kind merge.land | grep -qF '"reviewed":"no"' && pass "a rejected merge's merge.land stopped says it had no review too" ||
	fail "the stopped merge.land lacks reviewed=no: $(show 'pr:#610' --kind merge.land)"

land 611 --no-review ''
s_assert_status 2 "--no-review with an empty reason is a usage error"
land 611 --no-review
s_assert_status 2 "--no-review with no reason is a usage error"
land 611 "--no-review" "two
lines"
s_assert_status 2 "--no-review with a reason that is not one line is a usage error"
[ "$(merges)" = 0 ] && pass "and nothing reached the forge" || fail "a multi-line reason was merged on: $(merges) merge calls"

# Unconfigured, the review is not checked either, and stderr says so.
: >"$STUB_LOG"
t_run_split env TRACE_DIR= TRACE_CONFIG="$KIT/scripts/trace.config.sh" LAND_POLL_SECONDS=0 sh "$LAND" 612 </dev/null
s_assert_status 0 "unconfigured, a PR with no recorded verdict still lands"
s_assert_err_has "review" "and stderr says the review verdict was not checked"

# The manual's row is where the operator reads the override.
grep -F '| Land a batch of green PRs' "$KIT/AGENTS.md" | grep -qF -- "--no-review" &&
	pass "the root manual's landing row names --no-review" ||
	fail "the root manual's landing row does not name --no-review"

banner "15. Every kind the script reads from the trace is named by ADR-0019 (#723)"
# The script is an operator-run reader of the trace (ADR-0019 clause 1), and
# the record is where each read it makes is decided. A `show --kind` read the
# record does not name is an undecided read, so this section reads every kind
# the script asks `show` for and fails on one the record's Decision outcome
# and amendments do not name in backticks. A read through a wrapper — a
# function passing its "$1" as the kind — is followed to the wrapper's calls;
# a kind the reader cannot spell out is named as unreadable, never skipped.
ADR19=$(ls "$KIT"/docs/adr/0019-*.md 2>/dev/null | head -1)
# land_read_kinds <script> — one line per read: its kind, or `?<line>` for a
# read whose kind is neither a literal nor a wrapper's "$1".
land_read_kinds() {
	awk '
		/^[ \t]*#/ { next }
		/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { fn = $0; sub(/\(\).*/, "", fn) }
		/show[^|]*--kind/ {
			k = $0; sub(/.*--kind[ =]*/, "", k); sub(/[ \t|;)].*/, "", k)
			if (k == "\"$1\"" || k == "$1") { if (fn != "") print "@" fn }
			else if (k ~ /^[a-z][a-z._]*$/) print k
			else print "?" NR
		}' "$1" | while IFS= read -r _lk; do
		case $_lk in
		@*) sed -e '/^[ \t]*#/d' "$1" | grep -o "${_lk#@} [a-z][a-z._]*" | sed 's/^[^ ]* //' ;;
		*) printf '%s\n' "$_lk" ;;
		esac
	done | sort -u
}
# land_reads_unnamed <script> <record> — every read <record> does not name,
# one per line; nothing when each is named. A script with no read found is
# named too: a check that read nothing has checked nothing.
land_reads_unnamed() {
	_lr_kinds=$(land_read_kinds "$1")
	[ -n "$_lr_kinds" ] || { echo "no show --kind read found in $1"; return; }
	_lr_text=$(sed -n '/^## Decision outcome/,$p' "${2:-/dev/null}" 2>/dev/null)
	for _lr_k in $_lr_kinds; do
		case $_lr_k in
		'?'*) echo "an unreadable kind at line ${_lr_k#?}" ;;
		*) case $_lr_text in *"\`$_lr_k\`"*) ;; *) echo "$_lr_k" ;; esac ;;
		esac
	done
}
_lr_read=$(land_read_kinds "$LAND" | tr '\n' ' ')
[ "$_lr_read" = "pr.iterate pr.open review.verdict " ] &&
	pass "the script's reads are the three kinds: $_lr_read" ||
	fail "the script's reads read as '$_lr_read', not pr.iterate, pr.open and review.verdict"
_lr_miss=$(land_reads_unnamed "$LAND" "$ADR19")
[ -z "$_lr_miss" ] && pass "ADR-0019 names every kind the landing script reads" ||
	fail "ADR-0019 does not name the landing script's read of: $(echo $_lr_miss)"
LR_BAIT="$SCRATCH/land.reads-bait"
mkdir -p "$LR_BAIT"
{ cat "$LAND"; printf '%s\n' 'trace_read show "pr:#$PR" --kind feedback >/dev/null'; } >"$LR_BAIT/literal.sh"
[ "$(land_reads_unnamed "$LR_BAIT/literal.sh" "$ADR19")" = feedback ] &&
	pass "bait: a new show --kind read the record does not name turns the check red, naming it" ||
	fail "bait: an unnamed literal read was not named: $(land_reads_unnamed "$LR_BAIT/literal.sh" "$ADR19")"
{ cat "$LAND"; printf '%s\n' 'seen() {' '	trace_read show "pr:#$PR" --kind "$1"' '}' 'seen spawn.end'; } >"$LR_BAIT/wrapper.sh"
[ "$(land_reads_unnamed "$LR_BAIT/wrapper.sh" "$ADR19")" = spawn.end ] &&
	pass "bait: a read through a new wrapper is followed to its call, and named" ||
	fail "bait: a wrapped unnamed read was not named: $(land_reads_unnamed "$LR_BAIT/wrapper.sh" "$ADR19")"
{ cat "$LAND"; printf '%s\n' 'trace_read show "pr:#$PR" --kind "$K"'; } >"$LR_BAIT/variable.sh"
case $(land_reads_unnamed "$LR_BAIT/variable.sh" "$ADR19") in
*unreadable*) pass "bait: a kind the check cannot spell out is named unreadable, never skipped" ;;
*) fail "bait: a read of a variable kind passed unread" ;;
esac
grep -vF 'pr.open' "${ADR19:-/dev/null}" >"$LR_BAIT/record.md"
[ "$(land_reads_unnamed "$LAND" "$LR_BAIT/record.md")" = pr.open ] &&
	pass "bait: with pr.open cut from the record, the check names it" ||
	fail "bait: a record that does not name pr.open passed: $(land_reads_unnamed "$LAND" "$LR_BAIT/record.md")"
printf '%s\n' 'echo no reads here' >"$LR_BAIT/none.sh"
case $(land_reads_unnamed "$LR_BAIT/none.sh" "$ADR19") in
*'no show --kind read'*) pass "bait: a script with no read found fails, having read nothing" ;;
*) fail "bait: a script with no read passed the check" ;;
esac

t_done "land one PR by hand"
