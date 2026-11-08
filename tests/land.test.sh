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
	_bf=${STUB_BODY_FILE:-${STUB_DEFAULT_BODY:-}}
	[ -z "$_bf" ] || cat "$_bf"
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
*" issue view "*)
	# The ticket's body, for the lane's check-table hold (runtime/R87): a
	# file the case wrote, or the section's default, or nothing.
	[ "${STUB_ISSUE_RC:-0}" = 0 ] || { echo 'gh: HTTP 502 Bad Gateway' >&2; exit "$STUB_ISSUE_RC"; }
	_if=${STUB_ISSUE_FILE-${STUB_DEFAULT_ISSUE:-}}
	[ -z "$_if" ] || cat "$_if"
	;;
*" run list "*"workflowName"*)
	# The base branch's head's runs, for the lane's base-red hold
	# (runtime/R86): under STUB_RUNS_JSON the script's own --jq program runs
	# over a canned answer; else one word per workflow, STUB_BASE_RUNS.
	[ "${STUB_BASE_RUNS_RC:-0}" = 0 ] || { echo 'gh: HTTP 502 Bad Gateway' >&2; exit "$STUB_BASE_RUNS_RC"; }
	if [ -n "${STUB_RUNS_JSON:-}" ]; then
		STUB_PR_JSON=$STUB_RUNS_JSON
		jq_answer "$@"
	fi
	printf '%s\n' ${STUB_BASE_RUNS-success success}
	;;
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
*" run view "*"jobs"*)
	# The wait's job records (#850): the run's status, then one "<id> <name>"
	# line per job stuck in progress. STUB_STALL is the stuck job before any
	# job was re-run, STUB_STALL_AFTER the one after; under STUB_RUN_JSON the
	# script's own --jq program runs over a canned forge answer instead
	# (STUB_RUN_JSON_AFTER once a job was re-run). STUB_JOBS_RC, set, is a
	# forge that cannot answer for the records: that exit, nothing printed.
	[ -z "${STUB_JOBS_RC:-}" ] || exit "$STUB_JOBS_RC"
	if grep -q '^ARGV: run rerun --job' "$STUB_LOG"; then
		_json=${STUB_RUN_JSON_AFTER:-${STUB_RUN_JSON:-}} _stall=${STUB_STALL_AFTER:-}
	else
		_json=${STUB_RUN_JSON:-} _stall=${STUB_STALL:-}
	fi
	if [ -n "$_json" ]; then
		STUB_PR_JSON=$_json
		jq_answer "$@"
	fi
	echo completed
	[ -z "$_stall" ] || printf '%s\n' "$_stall"
	;;
*" run view "*)
	# A re-run's new attempt shows `completed` (the old attempt) for the first
	# STUB_COMPLETED_VIEWS asks for its status alone, then queued.
	if [ "$(grep -c '^ARGV: run view [0-9]* --json status --jq' "$STUB_LOG")" -le "${STUB_COMPLETED_VIEWS:-0}" ]; then
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
# The base branch's head the lane's base-red hold asks for, only once
# section 24 names the base's tree; every other rev-parse is the real git's.
rev-parse) case "$*:${STUB_BASE_TREE:-}" in *refs/remotes/origin/main*:?*) printf 'ARGV: git %s\n' "$*" >>"$STUB_LOG" ;; *) exec "$REAL_GIT" ${_c:+-C "$_c"} "$@" ;; esac ;;
# The PR's own diff (#728): its merge base and the paths it moves are the
# stub's; the root checkout's `diff --quiet` and `merge-base --is-ancestor`
# still reach the real git.
diff) case " $* " in *' --name-only '*) printf 'ARGV: git %s\n' "$*" >>"$STUB_LOG" ;; *) exec "$REAL_GIT" ${_c:+-C "$_c"} "$@" ;; esac ;;
merge-base) case " $* " in *' --is-ancestor '*) exec "$REAL_GIT" ${_c:+-C "$_c"} "$@" ;; *) printf 'ARGV: git %s\n' "$*" >>"$STUB_LOG" ;; esac ;;
*) if [ -n "$_c" ]; then exec "$REAL_GIT" -C "$_c" "$@"; else exec "$REAL_GIT" "$@"; fi ;;
esac
# pr_version <shared-layer value> <extra entry>… — a VERSION as the PR's
# merge base or head holds it: the version line, then the files: list.
pr_version() {
	printf '# a note\nshared-layer: %s\n\nfiles:\n' "$1"
	shift
	[ -z "${STUB_PR_NO_LIST:-}" ] || { printf 'skills:\n  grill-me\n'; return; }
	for _e in scripts/shared.sh UPDATING.md "$@"; do printf '  %s  annotated\n' "$_e"; done
	printf 'skills:\n  grill-me\n'
}
_mb=ba5eba5eba5eba5eba5eba5eba5eba5eba5eba5e
_ho=${STUB_HEAD_OID-1234567890123456789012345678901234567890}
case $1 in
fetch)
	case " $* " in *' refs/pull/'*) exit "${STUB_PR_FETCH_RC:-0}" ;; esac
	exit "${STUB_FETCH_RC:-0}"
	;;
merge-base) [ "${STUB_MB_RC:-0}" = 0 ] || exit "$STUB_MB_RC"; printf '%s\n' "$_mb" ;;
diff) [ "${STUB_PR_DIFF_RC:-0}" = 0 ] || exit "$STUB_PR_DIFF_RC"; for _f in ${STUB_PR_FILES:-}; do printf '%s\n' "$_f"; done ;;
show)
	case $2 in
	"$_mb:VERSION") [ "${STUB_PR_BASE_SHOW_RC:-0}" = 0 ] || exit "$STUB_PR_BASE_SHOW_RC"; pr_version 0.1.0 ${STUB_MANIFEST_BASE_EXTRA:-} ;;
	"$_ho:VERSION")
		[ "${STUB_PR_HEAD_SHOW_RC:-0}" = 0 ] || exit "$STUB_PR_HEAD_SHOW_RC"
		pr_version "${STUB_PR_VER_HEAD:-0.1.0}" ${STUB_MANIFEST_HEAD_EXTRA:-}
		;;
	*'^1:VERSION') printf '# a note\nshared-layer: %s\n' "${STUB_VER_BEFORE:-0.1.0}" ;;
	*':VERSION') printf '# a note\nshared-layer: %s\n' "${STUB_VER_AFTER:-0.1.0}" ;;
	*':.github/workflows/'?*) cat "${STUB_WORKFLOWS:-/nonexistent}/${2##*/}" 2>/dev/null || exit 128 ;;
	# The lane's reads at the base (runtime/R84, R87), only once section 24
	# names the base's tree: the landing script and the risk rule as the
	# running copy has them unless STUB_DRIFT names one (`gone`: unreadable),
	# and a factory ticket's file.
	"refs/remotes/origin/main:scripts/"*)
		[ -n "${STUB_BASE_TREE:-}" ] || exit 128
		_bf=${2#*:scripts/}
		case ${STUB_DRIFT:-} in
		"$_bf") echo '# drifted' ;;
		gone) exit 128 ;;
		*) cat "$STUB_BASE_TREE/scripts/$_bf" 2>/dev/null || exit 128 ;;
		esac
		;;
	"refs/remotes/origin/main:.factory/items/"*/ticket.md)
		[ -n "${STUB_FACTORY_TICKET:-}" ] || exit 128
		cat "$STUB_FACTORY_TICKET"
		;;
	*) exit 128 ;;
	esac
	;;
rev-parse) printf '%s\n' "${STUB_BASE_OID:-b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0}" ;;
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
	t_exec env LAND_POLL_SECONDS=0 sh "$LAND" "$@" </dev/null
	: >"$STUB_KNOBS"
}
merges() { grep -c '^ARGV: pr merge' "$STUB_LOG"; }
events() { show "pr:#$1" | grep -c "\"kind\":\"$2\"" | tr -d ' '; }

# ---------------------------------------------------------------------------
banner "1. A PR that is not green and mergeable is refused: exit 2, nothing merged, nothing emitted"
# ---------------------------------------------------------------------------
# not_landed <pr> <label> — the last run refused: exit 2, no merge call.
not_landed() {
	expect_status 2 "$2: refused with exit 2"
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
printf '%s\n' "$T_ERR" | grep -qi 'checks' && pass "a red refusal names the checks" ||
	fail "a red refusal does not say the checks are what refused it: $T_ERR"
refused STUB_VIEW_RC=1 110 "a forge that does not answer for the PR"
land abc
expect_status 2 "a PR that is not a number is a usage error"
land
expect_status 2 "no PR at all is a usage error"

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
expect_status 0 "a green PR lands with exit 0"
grep -q '^ARGV: pr merge 123 --merge' "$STUB_LOG" && pass "merged with the merge-commit method (gh pr merge 123 --merge)" ||
	fail "the merge call was not 'gh pr merge 123 --merge': $(grep 'pr merge' "$STUB_LOG")"
[ "$(merges)" = 1 ] && pass "exactly one merge call" || fail "$(merges) merge calls"
grep -q "^ARGV: run list.*$STUB_SHA" "$STUB_LOG" && pass "it looks for main's workflows on the merge commit" ||
	fail "it never listed the workflow runs on the merge commit"
grep -q '^ARGV: run watch 901' "$STUB_LOG" && pass "and waits for each one" || fail "it never watched run 901"
expect_out_has "$STUB_SHA" "stdout names the merge sha"
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
expect_status 0 "--unasked lands too"
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
expect_status 0 "a forge answering the fields in another order lands the PR"
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
printf '%s\n' "$T_ERR" | grep -qF 'it is a draft' && pass "a draft answered bottom-up is refused as a draft" ||
	fail "a draft answered bottom-up was refused for another reason: $T_ERR"
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
	expect_status 0 "the script's own --jq programs, run by jq, land the PR"
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
traced_out=$T_OUT
: >"$STUB_LOG"
# The second run's workflow takes seconds the first one's did not: the waited
# figure is the clock's, so it differs, and the comparison is not about it.
t_exec env TRACE_DIR= TRACE_CONFIG="$KIT/scripts/trace.config.sh" LAND_POLL_SECONDS=0 STUB_WATCH_SLEEP=2 sh "$LAND" 140 </dev/null
expect_status 0 "unconfigured, a green PR still lands with exit 0"
[ "$(merges)" = 1 ] && pass "unconfigured, the merge call is the same one call" || fail "unconfigured: $(merges) merge calls"
# norm <PR> — stdout with the PR number and the waited seconds masked.
norm() { sed "s/#$1/#N/g; s/waited [0-9]*s/waited Ns/"; }
[ "$(printf '%s\n' "$T_OUT" | norm 140)" = "$(printf '%s\n' "$traced_out" | norm 123)" ] &&
	pass "and stdout is what a traced run prints" || fail "unconfigured stdout differs: '$T_OUT' vs '$traced_out'"
[ "$(show 'pr:#140' | grep -c '"kind"' | tr -d ' ')" = 0 ] && pass "and nothing reached the trace" ||
	fail "an unconfigured run wrote to the trace"

# ---------------------------------------------------------------------------
banner "5. The forge's answers after the decision"
# ---------------------------------------------------------------------------
land STUB_MERGE_RC=1 150
[ "$T_STATUS" != 0 ] && pass "a merge the forge rejects is not exit 0 (got $T_STATUS)" || fail "a rejected merge exited 0"
show 'pr:#150' --kind merge.land | grep -qF '"outcome":"stopped"' && pass "and records merge.land stopped" ||
	fail "a rejected merge did not record merge.land stopped: $(show 'pr:#150')"
[ "$(events 150 feedback)" = 0 ] && pass "and asks no verdict of a PR that did not land" || fail "a rejected merge recorded feedback"
land STUB_WATCH_RC=1 151
[ "$T_STATUS" = 1 ] && pass "a failed post-merge workflow is exit 1 — escalate, as the train's hard rule 6 says" ||
	fail "a failed post-merge workflow exited $T_STATUS"
show 'pr:#151' --kind merge.land | grep -qF '"workflows":"failure"' && pass "the landing still records, with data.workflows=failure" ||
	fail "a failed post-merge workflow was not recorded on merge.land: $(show 'pr:#151')"
[ "$(events 151 feedback)" = 1 ] && pass "and the landing still gets its feedback" || fail "no feedback after a failed workflow"
printf '%s\n' "$T_ERR" | grep -qi 'escalate' && pass "stderr says to escalate" || fail "stderr does not say escalate: $T_ERR"
grep -q '^ARGV: run rerun' "$STUB_LOG" && fail "a merge that bumps nothing had a failed run re-run" ||
	pass "a merge that bumps nothing re-runs no failed workflow — its red is the verdict"
grep -qE '^ARGV: git (tag|push)' "$STUB_LOG" && fail "a merge that bumps nothing was tagged: $(grep '^ARGV: git' "$STUB_LOG")" ||
	pass "and is not tagged"

land STUB_RUNS= 152
expect_status 0 "no workflow on the merge commit: still a landing, exit 0"
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
expect_status 1 "a merge commit the forge never reports is exit 1"
grep -q '^ARGV: run list' "$STUB_LOG" && fail "it listed runs for an empty merge commit" ||
	pass "and no runs are listed for an empty commit"
ml=$(show 'pr:#154' --kind merge.land)
printf '%s\n' "$ml" | grep -qF '"outcome":"landed"' && printf '%s\n' "$ml" | grep -qF '"workflows":"unknown"' &&
	pass "the landing still records, landed with data.workflows=unknown" || fail "an unknown sha was not recorded as such: $ml"
printf '%s\n' "$ml" | grep -qF '"merge_sha"' && fail "an empty merge_sha was recorded: $ml" || pass "and no empty merge_sha"
printf '%s\n' "$T_ERR" | grep -qi 'merge commit' && pass "stderr says the merge commit is unknown" || fail "stderr: $T_ERR"

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
expect_status 1 "no run for a merge whose workflows declare a push trigger is exit 1 — not 2, so a train stops"
ml=$(show 'pr:#155' --kind merge.land)
printf '%s\n' "$ml" | grep -qF '"outcome":"landed"' && printf '%s\n' "$ml" | grep -qF '"workflows":"unknown"' &&
	pass "and records landed with data.workflows=unknown, not none" || fail "an unverified merge was not recorded unknown: $ml"
expect_err_has "unverified" "stderr says the merge is unverified"
expect_err_has "ci.yml" "stderr names a block-form push workflow it expected"
expect_err_has "release.yaml" "stderr names a flow-form push workflow it expected"
printf '%s\n' "$T_ERR" | grep -qF 'lint.yml' && fail "a pull_request-only workflow was named as expected on push: $T_ERR" ||
	pass "and does not name a workflow with no push trigger"
expect_out_has "workflows unknown" "stdout's landing line says workflows unknown"
[ "$(events 155 feedback)" = 1 ] && pass "and the landing still gets its feedback" || fail "no feedback after an unverified merge"

land STUB_RUNS= "STUB_WORKFLOWS=$SCRATCH/wf-nopush" 156
expect_status 0 "no run for a merge whose workflows declare no push trigger: still exit 0"
show 'pr:#156' --kind merge.land | grep -qF '"workflows":"none"' && pass "and records data.workflows=none" ||
	fail "a tree with no push trigger was not recorded workflows=none: $(show 'pr:#156')"

land STUB_RUNS= STUB_CATFILE_RC=128 "STUB_WORKFLOWS=$SCRATCH/wf-nopush" 157
expect_status 1 "no run, and a merge commit whose workflows cannot be read here: exit 1"
show 'pr:#157' --kind merge.land | grep -qF '"workflows":"unknown"' && pass "and records data.workflows=unknown" ||
	fail "an unreadable workflow tree was recorded as known: $(show 'pr:#157')"
expect_err_has "could not be read" "stderr says the merge's workflows could not be read — the merge is unverified"
# A workflow file the tree lists but git cannot read is no answer either: a
# directory named like one stands in for it, beside a file with no push.
mkdir -p "$SCRATCH/wf-unread/broken.yml"
cp "$SCRATCH/wf-nopush/manual.yml" "$SCRATCH/wf-unread/"
land STUB_RUNS= "STUB_WORKFLOWS=$SCRATCH/wf-unread" 159
expect_status 1 "no run, and a workflow file that cannot be read: exit 1, never none"
show 'pr:#159' --kind merge.land | grep -qF '"workflows":"unknown"' && pass "and records data.workflows=unknown" ||
	fail "an unreadable workflow file was read as no push trigger: $(show 'pr:#159')"
expect_err_has "could not be read" "stderr says the workflows could not be read"

land STUB_RUNS= "STUB_WORKFLOWS=$SCRATCH/wf-push" 158 --train
expect_status 1 "the train's landing of an unverified merge is exit 1 — the train stops on it"
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
	expect_status 0 "$_lw_label: the PR lands, exit 0"
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
# Section 2's landing, read back without its exit status: T_STATUS is the
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
expect_status 0 "a release whose first run failed untagged, green on its re-run, lands with exit 0"
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
expect_out_has "tagged v0.2.0" "stdout says the release was tagged"
expect_err_lacks "land nothing else" "and stderr raises no failure"

# shellcheck disable=SC2086
land $REL 191
expect_status 0 "a release green on its first runs lands with exit 0"
grep -q '^ARGV: run rerun' "$STUB_LOG" && fail "a green release was re-run" || pass "and nothing is re-run"
grep -qE "^ARGV: git push origin (refs/tags/)?v0\.2\.0$" "$STUB_LOG" && pass "and it is still tagged" || fail "a green release was not tagged"

# shellcheck disable=SC2086
land $REL STUB_WATCH_RC=1 STUB_WATCH_RC_AFTER=1 192
expect_status 1 "a release still red after its one re-run is exit 1"
[ "$(grep -c '^ARGV: run rerun' "$STUB_LOG")" = 1 ] && pass "re-run once, never twice" ||
	fail "re-run $(grep -c '^ARGV: run rerun' "$STUB_LOG") times"
show 'pr:#192' --kind merge.land | grep -qF '"workflows":"failure"' && pass "and recorded with data.workflows=failure" ||
	fail "a release red after its re-run was not recorded as failure: $(show 'pr:#192' --kind merge.land)"
expect_err_has "land nothing else" "stderr says to land nothing else"

# shellcheck disable=SC2086
land $REL STUB_PUSH_RC=1 STUB_WATCH_RC=1 193
expect_status 1 "a release whose tag the forge refused is exit 1"
grep -q '^ARGV: run rerun' "$STUB_LOG" && fail "a run was re-run with no tag on the forge" ||
	pass "and nothing is re-run — a re-run with no tag fails the same way"
expect_err_has "git tag -a v0.2.0 $STUB_SHA" "stderr names the tag command to run by hand"
show 'pr:#193' --kind merge.land | grep -qF '"tagged":"no"' && pass "and merge.land records tagged=no" ||
	fail "a refused tag was not recorded: $(show 'pr:#193' --kind merge.land)"

# shellcheck disable=SC2086
land $REL STUB_PUSH_RC=1 194
expect_status 1 "an untagged release is exit 1 even with main green — it is not landed (hard rule 3)"

# shellcheck disable=SC2086
land $REL "STUB_REMOTE_TAG=$STUB_SHA" STUB_WATCH_RC=1 195
expect_status 0 "a release already tagged at its merge commit lands with exit 0"
grep -qE '^ARGV: git (tag|push)' "$STUB_LOG" && fail "an existing tag was cut again" || pass "and the tag is not cut again"
[ "$(grep -c '^ARGV: run rerun' "$STUB_LOG")" = 1 ] && pass "but a run that failed is still re-run once" || fail "the failed run was not re-run"

# shellcheck disable=SC2086
land $REL STUB_REMOTE_TAG=1111111111111111111111111111111111111111 196
expect_status 1 "a release whose tag already names another commit is exit 1"
grep -qE '^ARGV: git (tag|push)' "$STUB_LOG" && fail "a tag naming another commit was moved or re-cut" ||
	pass "and the tag is never moved"
expect_err_has "1111111111111111111111111111111111111111" "stderr names the commit the tag already holds"
expect_err_lacks "2222222222222222222222222222222222222222" "and reads the commit an annotated tag peels to, never its tag object"

# A lightweight tag lists the commit alone, with no peeled line (M-2 of the
# review of PR #577).
# shellcheck disable=SC2086
land $REL "STUB_REMOTE_TAG=$STUB_SHA" STUB_REMOTE_TAG_KIND=lightweight 199
expect_status 0 "a lightweight tag already on the merge commit is the release's tag: exit 0"
grep -qE '^ARGV: git (tag|push)' "$STUB_LOG" && fail "a lightweight tag on the merge commit was cut again" ||
	pass "and is not cut again"
# shellcheck disable=SC2086
land $REL STUB_REMOTE_TAG=1111111111111111111111111111111111111111 STUB_REMOTE_TAG_KIND=lightweight 200
expect_status 1 "a lightweight tag naming another commit is exit 1"
grep -qE '^ARGV: git (tag|push)' "$STUB_LOG" && fail "a lightweight tag naming another commit was moved" ||
	pass "and is never moved"

# The re-run waits for its new attempt to leave `completed` before watching
# it: a watch on the old attempt would report the old failure (M-1).
# shellcheck disable=SC2086
land $REL STUB_WATCH_RC=1 STUB_COMPLETED_VIEWS=2 201
expect_status 0 "a re-run whose new attempt shows completed twice first still lands green"
[ "$(grep -c '^ARGV: run view 901 --json status --jq' "$STUB_LOG")" = 3 ] &&
	pass "it asked the run's status until it left completed (three asks)" ||
	fail "it asked the run's status $(grep -c '^ARGV: run view 901 --json status --jq' "$STUB_LOG") times, not 3"
_last_view=$(grep -n '^ARGV: run view 901 --json status --jq' "$STUB_LOG" | tail -1 | cut -d: -f1)
_second_watch=$(grep -n '^ARGV: run watch 901' "$STUB_LOG" | sed -n 2p | cut -d: -f1)
[ -n "$_second_watch" ] && [ "$_second_watch" -gt "$_last_view" ] &&
	pass "and watched the re-run only after it left completed (line $_last_view < $_second_watch)" ||
	fail "the re-run was watched before its status left completed: view $_last_view, watch ${_second_watch:-none}"

# A re-run the forge refuses is a failure, not a pass (M-3).
# shellcheck disable=SC2086
land $REL STUB_WATCH_RC=1 STUB_RERUN_RC=1 202
expect_status 1 "a re-run the forge refuses is exit 1"
show 'pr:#202' --kind merge.land | grep -qF '"workflows":"failure"' && pass "and recorded with data.workflows=failure" ||
	fail "a refused re-run was not recorded as failure: $(show 'pr:#202' --kind merge.land)"
[ "$(grep -c '^ARGV: run watch 901' "$STUB_LOG")" = 1 ] && pass "and a refused re-run is not watched" ||
	fail "a refused re-run was watched $(grep -c '^ARGV: run watch 901' "$STUB_LOG") times"
expect_err_has "run cannot be rerun" "and stderr carries the forge's refusal"

# A re-run refused because the run is still going is no verdict: the landing
# waits for that run and judges its end (#661 — #659's release was recorded
# failure while main's run on it ended success).
BUSY="STUB_RERUN_RC=1"
BUSY_ERR="STUB_RERUN_ERR=run 901 cannot be rerun; This workflow is already running"
iterated 230 231 232
# shellcheck disable=SC2086
land $REL STUB_WATCH_RC=1 $BUSY "$BUSY_ERR" STUB_WATCH_RC_AFTER=0 230
expect_status 0 "a re-run refused as already running, whose run then ends green, lands with exit 0"
show 'pr:#230' --kind merge.land | grep -qF '"workflows":"success"' && pass "and is recorded with data.workflows=success" ||
	fail "a still-running run that ended green was not recorded success: $(show 'pr:#230' --kind merge.land)"
show 'pr:#230' --kind merge.land | grep -qF '"reruns":"0"' && pass "and data.reruns=0 — the forge started no re-run" ||
	fail "a refused re-run was counted as one: $(show 'pr:#230' --kind merge.land)"
[ "$(grep -c '^ARGV: run watch 901' "$STUB_LOG")" = 2 ] && pass "it watched the running run to its end" ||
	fail "run 901 was watched $(grep -c '^ARGV: run watch 901' "$STUB_LOG") times, not twice"
expect_err_has "already running" "stderr says the run was still going"
expect_err_lacks "land nothing else" "and raises no failure"

# shellcheck disable=SC2086
land $REL STUB_WATCH_RC=1 $BUSY "$BUSY_ERR" STUB_WATCH_RC_AFTER=1 231
expect_status 1 "a re-run refused as already running, whose run then ends red, is exit 1"
show 'pr:#231' --kind merge.land | grep -qF '"workflows":"failure"' && pass "and is recorded with data.workflows=failure" ||
	fail "a still-running run that ended red was not recorded failure: $(show 'pr:#231' --kind merge.land)"
expect_err_has "land nothing else" "stderr says to land nothing else"

# shellcheck disable=SC2086
land $REL STUB_WATCH_RC=1 $BUSY "STUB_RERUN_ERR=HTTP 403: Resource not accessible by integration" 232
expect_status 1 "a re-run refused for any other reason is still exit 1"
show 'pr:#232' --kind merge.land | grep -qF '"workflows":"failure"' && pass "and recorded with data.workflows=failure" ||
	fail "a re-run refused for another reason was not recorded failure: $(show 'pr:#232' --kind merge.land)"
show 'pr:#232' --kind merge.land | grep -qF '"reruns":"0"' && pass "and data.reruns=0 — a refused re-run is never counted" ||
	fail "a re-run refused for another reason was counted as one: $(show 'pr:#232' --kind merge.land)"
[ "$(grep -c '^ARGV: run watch 901' "$STUB_LOG")" = 1 ] && pass "and its run is not watched again" ||
	fail "a run refused for another reason was watched $(grep -c '^ARGV: run watch 901' "$STUB_LOG") times"
expect_err_has "Resource not accessible" "and stderr names the refusal"

land STUB_FETCH_RC=1 STUB_WATCH_RC=1 197
expect_status 1 "with the merge commit unreadable, the landing is judged as before (a red run is exit 1)"
grep -qE '^ARGV: git (tag|push)' "$STUB_LOG" && fail "an unreadable merge was tagged" || pass "and nothing is tagged"
expect_err_has "VERSION" "stderr says it could not read whether the merge bumped VERSION"

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
	expect_err_has "pr-iterate" "$_ni_label: stderr sends it to /pr-iterate"
	expect_err_has "--no-iteration" "$_ni_label: and names the override"
}
land 300
no_iter "no pr.iterate event at all" 300
expect_err_has "1234567890123456789012345678901234567890" "stderr names the head commit"

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
expect_status 2 "--no-iteration with a reason that is not one line is a usage error, before any merge"
[ "$(merges)" = 0 ] && pass "and nothing reached the forge" || fail "a multi-line reason was merged on: $(merges) merge calls"

land STUB_HEAD_OID='not-a-sha' 310
no_iter "a head the forge names in no sha shape" 310
expect_err_has "<unnamed>" "stderr marks the head commit unnamed, never echoing the forge's text"
land STUB_HEAD_DATE= 310
expect_err_has "<undated>" "stderr marks an undated head as such"

land 308 --no-iteration ''
expect_status 2 "--no-iteration with an empty reason is a usage error"
land 308 --no-iteration
expect_status 2 "--no-iteration with no reason is a usage error"

# Unconfigured, nothing can be read and nothing is recorded: the check is
# skipped, said on stderr, and the merge goes on (ADR-0008 clause 2).
: >"$STUB_LOG"
t_exec env TRACE_DIR= TRACE_CONFIG="$KIT/scripts/trace.config.sh" LAND_POLL_SECONDS=0 sh "$LAND" 309 </dev/null
expect_status 0 "unconfigured, a PR with no recorded iteration still lands"
expect_err_has "not checked" "and stderr says the iteration was not checked"

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
LAND_ONLY='iterated no_iteration reviewed no_review ticket_start verified'
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
	t_exec env LAND_ROOT_CHECKOUT="$_lr_root" LAND_POLL_SECONDS=0 "$@" sh "$LAND" "$_lr_pr" </dev/null
}
iterated 211 212 213 214 215

R="$SCRATCH/root-clean"
mkroot "$R" || fail "could not build the clean root checkout"
want=$("$REAL_GIT" -C "$R" rev-parse origin/main)
landed_with_root "$R" 205
expect_status 0 "a landing with a clean root checkout exits 0"
[ "$(head_of "$R")" = "$want" ] && pass "the clean root checkout on main is fast-forwarded to origin/main" ||
	fail "the clean root checkout was not fast-forwarded: HEAD $(head_of "$R"), origin/main $want"
# One fetch for the release question, one in the root checkout before it moves.
[ "$(grep -c '^ARGV: git fetch -q origin main$' "$STUB_LOG")" = 2 ] && pass "it fetches the base again for the root checkout" ||
	fail "it did not fetch the base for the root checkout: $(grep 'git' "$STUB_LOG")"
expect_err_has "fast-forwarded the root checkout $R" "stderr says the root was fast-forwarded, and where"

R="$SCRATCH/root-dirty"
mkroot "$R" || fail "could not build the dirty root checkout"
was=$(head_of "$R")
echo edit >"$R/f"
landed_with_root "$R" 206
expect_status 0 "a dirty root checkout does not fail the landing"
[ "$(head_of "$R")" = "$was" ] && [ "$(cat "$R/f")" = edit ] && pass "a dirty root checkout is left alone, its edit intact" ||
	fail "a dirty root checkout was touched: HEAD $(head_of "$R"), f '$(cat "$R/f")'"
expect_err_has "left the root checkout $R alone" "stderr names the dirty root it left"
expect_err_has "uncommitted" "and says why: uncommitted changes"

R="$SCRATCH/root-branch"
mkroot "$R" || fail "could not build the off-main root checkout"
git -C "$R" checkout -q -b feat/elsewhere
was=$(head_of "$R")
landed_with_root "$R" 207
expect_status 0 "a root checkout off main does not fail the landing"
[ "$(head_of "$R")" = "$was" ] && [ "$("$REAL_GIT" -C "$R" rev-parse main)" = "$was" ] &&
	pass "a root checkout off main is left alone, main not moved" || fail "a root checkout off main was touched"
expect_err_has "left the root checkout $R alone" "stderr names the off-main root it left"
expect_err_has "feat/elsewhere" "and says which branch it is on"

R="$SCRATCH/root-diverged"
mkroot "$R" || fail "could not build the diverged root checkout"
t_write "$R" g three && t_commit "$R" local >/dev/null
was=$(head_of "$R")
landed_with_root "$R" 208
expect_status 0 "a diverged root checkout does not fail the landing"
[ "$(head_of "$R")" = "$was" ] && pass "a diverged root checkout is left alone" || fail "a diverged root checkout was moved"
expect_err_has "left the root checkout $R alone" "stderr names the diverged root it left"
expect_err_has "diverged" "and says it has diverged"

landed_with_root "$SCRATCH/no-root" 209
expect_status 0 "a root path that is no checkout does not fail the landing"
expect_err_has "is not a checkout" "and stderr says so"

R="$SCRATCH/root-untracked"
mkroot "$R" || fail "could not build the root checkout with an untracked file"
t_write "$R" scratch.txt note
landed_with_root "$R" 211
[ "$(head_of "$R")" = "$("$REAL_GIT" -C "$R" rev-parse origin/main)" ] && [ -f "$R/scratch.txt" ] &&
	pass "an untracked file alone does not hold the root back: fast-forwarded, the file kept (worktree-cleanup's rule)" ||
	fail "a root with only an untracked file was not fast-forwarded: $T_ERR"

R="$SCRATCH/root-detached"
mkroot "$R" || fail "could not build the detached root checkout"
git -C "$R" checkout -q --detach
was=$(head_of "$R")
landed_with_root "$R" 203
[ "$(head_of "$R")" = "$was" ] && pass "a detached root checkout is left alone" || fail "a detached root checkout was moved"
expect_err_has "detached" "and stderr says its HEAD is detached"

R="$SCRATCH/root-current"
mkroot "$R" || fail "could not build the up-to-date root checkout"
git -C "$R" merge -q --ff-only origin/main
landed_with_root "$R" 204
expect_err_has "already at origin/main" "a root already at origin/main is said to be so"

R="$SCRATCH/root-nofetch"
mkroot "$R" || fail "could not build the root checkout whose fetch fails"
was=$(head_of "$R")
landed_with_root "$R" 210 STUB_FETCH_RC=1
expect_status 0 "a fetch that fails in the root does not fail the landing"
[ "$(head_of "$R")" = "$was" ] && pass "a root whose fetch failed is left alone" || fail "a root whose fetch failed was moved"
expect_err_has "fetching origin main there failed" "and stderr says the fetch failed"

R="$SCRATCH/root-noorigin"
mkroot "$R" || fail "could not build the root checkout with no origin/main"
git -C "$R" update-ref -d refs/remotes/origin/main
was=$(head_of "$R")
landed_with_root "$R" 212
[ "$(head_of "$R")" = "$was" ] && pass "a root with no origin/main is left alone" || fail "a root with no origin/main was moved"
expect_err_has "no origin/main to follow" "and stderr says there is nothing to follow"

# The default: the main worktree of the repo the script runs from — here a
# scratch repo whose linked worktree holds a copy of the kit's scripts.
R="$SCRATCH/root-default"
W="$SCRATCH/root-default-wt"
mkroot "$R" || fail "could not build the default root checkout"
git -C "$R" worktree add -q "$W" -b side 2>/dev/null && cp -R "$KIT/scripts" "$W/" ||
	fail "could not build the linked worktree the default case runs from"
: >"$STUB_LOG"
t_exec env LAND_ROOT_CHECKOUT= LAND_POLL_SECONDS=0 sh "$W/scripts/land.kit.sh" 213 </dev/null
expect_status 0 "with no LAND_ROOT_CHECKOUT, the landing still exits 0"
[ "$(head_of "$R")" = "$("$REAL_GIT" -C "$R" rev-parse origin/main)" ] &&
	pass "with no LAND_ROOT_CHECKOUT, the main worktree of the script's repo is the root fast-forwarded" ||
	fail "the default root was not the main worktree: $T_ERR"

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
expect_status 0 "a PR with no pr.open lands"
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
expect_status 2 "the train's landing of a PR with a red required check is refused: exit 2, the train's skip"
[ "$(merges)" = 0 ] && pass "and the PR is skipped, not merged — no merge call reached the forge" ||
	fail "the train's landing merged a PR with a red required check"
[ "$(show 'pr:#500' --kind merge.land | grep -c .)" = 0 ] && pass "and no merge.land is recorded for the skipped PR" ||
	fail "a refused train landing recorded a merge.land: $(show 'pr:#500' --kind merge.land)"
expect_err_has "checks" "and stderr names the checks as what refused it"

land 501 --train
expect_status 0 "a green PR the train lands through the script exits 0"
[ "$(merges)" = 1 ] && pass "merged once" || fail "$(merges) merge calls for the train's green PR"
ml=$(show 'pr:#501' --kind merge.land)
for tok in '"outcome":"landed"' '"via":"train"' "\"merge_sha\":\"$STUB_SHA\"" '"iterated":"yes"'; do
	printf '%s\n' "$ml" | grep -qF -- "$tok" && pass "the train's merge.land carries $tok" || fail "the train's merge.land lacks $tok: $ml"
done
[ "$(events 501 feedback)" = 0 ] && pass "--train writes no feedback: the verdict is the train's to record" ||
	fail "--train wrote $(events 501 feedback) feedback event(s) — the train's own would make a second"
expect_out_has "feedback: left to the train" "stdout says the verdict is left to the train"

land 502 --train --unasked 'nobody here'
expect_status 2 "--train with --unasked is a usage error: the train records the verdict"
[ "$(merges)" = 0 ] && pass "and nothing is merged" || fail "a usage error still merged"
expect_err_has "drop --unasked" "and stderr names --unasked as what made it one"

# The manual's row is where the train reads how to run the script.
grep -F '| Land a batch of green PRs' "$KIT/AGENTS.md" | grep -qF -- '--train' &&
	pass "the root manual's landing row names --train" ||
	fail "the root manual's landing row does not name --train — the train cannot tell how to run the script"

# ---------------------------------------------------------------------------
banner "14. No review.verdict at the head commit: refused, or landed on a named reason and recorded (#673)"
# ---------------------------------------------------------------------------
# On 2026-10-09 #665's review degraded and posted with no review.verdict; the
# landing checked for an iteration at the head and not for a review, and
# landed it. The same check as section 9's, for the review: an Axis-1
# review.verdict on the PR, any outcome but blocked (#816), stamped at or
# after its head commit's date — else exit 2, nothing merged, nothing recorded, unless --no-review
# names why, and then merge.land says the landing had none. Every PR here is
# #600 up, so no seed above reaches it.
# no_rev <label> <pr> — refused on the review check, the trace untouched.
no_rev() {
	_nr_label=$1
	not_landed "$2" "$_nr_label"
	[ "$(events "$2" merge.land)" = 0 ] && [ "$(events "$2" feedback)" = 0 ] &&
		pass "$_nr_label: no landing reached the trace" || fail "$_nr_label: a landing was recorded: $(show "pr:#$2")"
	expect_err_has "review-pr" "$_nr_label: stderr sends it to /review-pr"
	expect_err_has "--no-review" "$_nr_label: and names the override"
}
seed pr.iterate green 600
land 600
no_rev "an iteration at head and no review.verdict at all" 600
expect_err_has "1234567890123456789012345678901234567890" "stderr names the head commit"

land 601
no_rev "neither an iteration nor a verdict" 601
expect_err_has "pr-iterate" "and the one refusal names the missing iteration as well"
expect_err_has "--no-iteration" "and both overrides"

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

# A blocked Axis-1 verdict is not a review the landing counts (#816,
# ADR-0032): since #808 a review in which no lens ran records exactly that,
# and nothing audited the diff. Nor is an Axis-2 verdict alone — the no-lens
# review records one beside its blocked Axis 1.
seed review.verdict blocked 605
seed pr.iterate red 605
land 605
no_rev "a blocked Axis-1 verdict alone at the head" 605
expect_err_has "blocked" "stderr names the blocked verdict"

seed pr.iterate green 606
seed review.verdict confirm 606
land 606
no_rev "an Axis-2 verdict alone at the head" 606

# verdict <pr> <outcome> <data…> — a review.verdict in the exact shape a
# /review-pr branch records it.
verdict() {
	_vd_pr=$1
	_vd_outcome=$2
	shift 2
	env TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh" TRACE_QUIET=1 sh "$TRACE" emit kind=review.verdict \
		"subject=pr:#$_vd_pr" "outcome=$_vd_outcome" "$@" </dev/null >/dev/null 2>&1 ||
		fail "could not seed a review.verdict on pr:#$_vd_pr"
}
# The no-lens review exactly as NO-LENS.md records it, Axis 2 beside it.
seed pr.iterate green 613
verdict 613 blocked data.axis=1 data.lenses=0 data.roster=6 'reason=no lens ran'
verdict 613 confirm data.axis=2 data.unspecified=1 data.mixed=0 data.missing=0 reason=seeded
land 613
no_rev "a no-lens review (blocked, data.lenses=0) with its Axis-2 verdict" 613
expect_err_has "blocked" "stderr names the blocked verdict"

seed pr.iterate green 614
verdict 614 pass data.axis=1 data.agent=single-reviewer data.lenses=0 data.roster=0 reason=seeded
land 614
landed_with 614 "a single-reviewer pass at data.lenses=0" '"reviewed":"yes"' '"iterated":"yes"'
show 'pr:#614' --kind merge.land | grep -qF '"no_review"' && fail "a reviewed landing carries a no_review reason" ||
	pass "and carries no no_review reason"

seed pr.iterate green 615
verdict 615 blocked data.axis=1 data.lenses=0 data.roster=6 'reason=no lens ran'
verdict 615 pass data.axis=1 data.lenses=6 data.roster=6 reason=seeded
land 615
landed_with 615 "a blocked verdict and a pass at the same head" '"reviewed":"yes"'

seed pr.iterate green 616
verdict 616 blocked data.axis=1 data.lenses=0 data.roster=6 'reason=no lens ran'
land 616 --no-review 'no lens ran; read by hand'
landed_with 616 "a blocked verdict alone, with --no-review" '"reviewed":"no"' '"no_review":"no lens ran; read by hand"'

# runtime/R213 (PRD-13, ADR-0044): the verifier is advisory, never the review.
# A verify.verdict outcome=pass at the head, in the shape the broker records
# it — even beside an Axis-1-looking data key — counts as no review: refused,
# exit 2, nothing recorded.
seed pr.iterate green 617
env TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh" TRACE_QUIET=1 sh "$TRACE" emit kind=verify.verdict \
	'subject=pr:#617' outcome=pass data.via=broker "data.reviewed=$STUB_SHA" data.provider=anthropic \
	data.rung=same-provider data.disputed=0 data.axis=1 reason=seeded </dev/null >/dev/null 2>&1 ||
	fail "runtime/R213: could not seed a verify.verdict on pr:#617"
[ "$(events 617 verify.verdict)" = 1 ] && pass "runtime/R213: the seeded verify.verdict pass is in the trace" ||
	fail "runtime/R213: no verify.verdict seeded on pr:#617 — the refusal below would prove nothing"
land 617
no_rev "runtime/R213: a verify.verdict pass alone at the head" 617

# …and the other way round: a blocked verifier beside the kit's Axis-1 pass is
# not refused for review — the verifier decides nothing at the landing.
seed pr.iterate green 618
verdict 618 pass data.axis=1 data.lenses=6 data.roster=6 reason=seeded
env TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh" TRACE_QUIET=1 sh "$TRACE" emit kind=verify.verdict \
	'subject=pr:#618' outcome=blocked data.via=broker "data.reviewed=$STUB_SHA" data.provider=anthropic \
	data.rung=same-provider data.disputed=0 reason=seeded </dev/null >/dev/null 2>&1 ||
	fail "runtime/R213: could not seed a verify.verdict on pr:#618"
land 618
landed_with 618 "runtime/R213: a blocked verify.verdict beside an Axis-1 pass" '"reviewed":"yes"'

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
expect_status 2 "--no-review with an empty reason is a usage error"
land 611 --no-review
expect_status 2 "--no-review with no reason is a usage error"
land 611 "--no-review" "two
lines"
expect_status 2 "--no-review with a reason that is not one line is a usage error"
[ "$(merges)" = 0 ] && pass "and nothing reached the forge" || fail "a multi-line reason was merged on: $(merges) merge calls"

# Unconfigured, the review is not checked either, and stderr says so.
: >"$STUB_LOG"
t_exec env TRACE_DIR= TRACE_CONFIG="$KIT/scripts/trace.config.sh" LAND_POLL_SECONDS=0 sh "$LAND" 612 </dev/null
expect_status 0 "unconfigured, a PR with no recorded verdict still lands"
expect_err_has "review" "and stderr says the review verdict was not checked"

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
# land_read_kinds <script> — one line per read: its kind; `?<line>` for a
# read whose kind is neither a literal nor a wrapper's "$1", or a wrapper
# called with a kind it cannot spell; `!<subcommand> <line>` for a trace read
# through any subcommand but `show` and `dir`. A backslash-continued line is
# read with the next, and a function's name is dropped at its closing brace,
# so a top-level "$1" read follows no wrapper.
land_read_kinds() {
	awk '
		pend != "" { $0 = pend $0; pend = "" }
		/\\$/ { sub(/\\$/, ""); pend = $0 " "; next }
		/^[ \t]*#/ { next }
		{ n++; L[n] = $0; at[n] = NR }
		/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { fn = $0; sub(/\(\).*/, "", fn) }
		/^}/ { fn = "" }
		/trace_read[ \t]+[a-z]/ {
			c = $0; sub(/.*trace_read[ \t]+/, "", c); sub(/[^a-z].*/, "", c)
			if (c != "show" && c != "dir") print "!" c " " NR
		}
		/show[^|]*--kind/ {
			k = $0; sub(/.*--kind[ =]*/, "", k); sub(/[ \t|;)].*/, "", k)
			if (k == "\"$1\"" || k == "$1") { if (fn != "") W[fn] = 1; else print "?" NR }
			else if (k ~ /^[a-z][a-z._]*$/) print k
			else print "?" NR
		}
		END {
			for (f in W) for (i = 1; i <= n; i++) {
				s = L[i]
				if (s ~ ("^" f "\\(\\)")) continue
				while (match(s, "(^|[^A-Za-z0-9_])" f "[ \t]+")) {
					s = substr(s, RSTART + RLENGTH); k = s; sub(/[ \t|;)&].*/, "", k)
					if (k ~ /^[a-z][a-z._]*$/) print k; else print "?" at[i]
				}
			}
		}' "$1" | sort -u
}
# land_reads_unnamed <script> <record> — every read <record> does not name,
# one per line; nothing when each is named. A script with no read found is
# named too: a check that read nothing has checked nothing.
land_reads_unnamed() {
	_lr_kinds=$(land_read_kinds "$1" | tr ' ' '_')
	[ -n "$_lr_kinds" ] || { echo "no show --kind read found in $1"; return; }
	_lr_text=$(sed -n '/^## Decision outcome/,$p' "${2:-/dev/null}" 2>/dev/null)
	for _lr_k in $_lr_kinds; do
		case $_lr_k in
		'?'*) echo "an unreadable kind at line ${_lr_k#?}" ;;
		'!'*) _lr_c=${_lr_k#!} && echo "a ${_lr_c%%_*} read at line ${_lr_c#*_}, beyond show" ;;
		*) case $_lr_text in *"\`$_lr_k\`"*) ;; *) echo "$_lr_k" ;; esac ;;
		esac
	done
}
_lr_read=$(land_read_kinds "$LAND" | tr '\n' ' ')
[ "$_lr_read" = "merge.land pr.iterate pr.open review.verdict ticket.start verify.verdict " ] &&
	pass "the script's reads are the six kinds: $_lr_read" ||
	fail "the script's reads read as '$_lr_read', not merge.land, pr.iterate, pr.open, review.verdict, ticket.start and verify.verdict"
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
# lr_bait <name> <expected substring> <what it proves> <line>… — the check on
# a copy of the script with <line>s appended names <expected substring>.
lr_bait() {
	_lb_n=$1 _lb_x=$2 _lb_w=$3
	shift 3
	{ cat "$LAND"; printf '%s\n' "$@"; } >"$LR_BAIT/$_lb_n.sh"
	case $(land_reads_unnamed "$LR_BAIT/$_lb_n.sh" "$ADR19") in
	*"$_lb_x"*) pass "bait: $_lb_w" ;;
	*) fail "bait: not caught — $_lb_w: $(land_reads_unnamed "$LR_BAIT/$_lb_n.sh" "$ADR19")" ;;
	esac
}
lr_bait continued feedback "a read split by a backslash across lines is read whole, and named" \
	'trace_read show "pr:#$PR" \' '	--kind feedback >/dev/null'
lr_bait toplevel 'unreadable kind' 'a top-level "$1" read after a function follows no wrapper, and is named unreadable' \
	'trace_read show "pr:#$PR" --kind "$1"'
lr_bait wrapper-var 'unreadable kind' 'a wrapper called with a kind it cannot spell is named unreadable' \
	'seen() {' '	trace_read show "pr:#$PR" --kind "$1"' '}' 'seen "$K"'
lr_bait summary 'a summary read' 'a trace read through a subcommand beyond show is named' \
	'trace_read summary --by kind >/dev/null'
grep -vF 'pr.open' "${ADR19:-/dev/null}" >"$LR_BAIT/record.md"
[ "$(land_reads_unnamed "$LAND" "$LR_BAIT/record.md")" = pr.open ] &&
	pass "bait: with pr.open cut from the record, the check names it" ||
	fail "bait: a record that does not name pr.open passed: $(land_reads_unnamed "$LAND" "$LR_BAIT/record.md")"
printf '%s\n' 'echo no reads here' >"$LR_BAIT/none.sh"
case $(land_reads_unnamed "$LR_BAIT/none.sh" "$ADR19") in
*'no show --kind read'*) pass "bait: a script with no read found fails, having read nothing" ;;
*) fail "bait: a script with no read passed the check" ;;
esac

banner "16. A PR that moves the shared layer with no version bump is refused (#728)"
# PR #693 moved manifest-listed files with no VERSION bump and landed, and
# main stayed red until another session cut a release. The landing reads the
# PR's diff against its merge base and VERSION's files: list at both ends;
# a moved listed path with the shared-layer line unchanged refuses it — exit
# 2, nothing merged, nothing recorded, the moved files and hard rule 3 named.
# No override: a shared-layer change is a release, never an exception.
# no_bump <pr> <label> — refused on the shared-layer check.
no_bump() {
	not_landed "$1" "$2"
	[ "$(events "$1" merge.land)" = 0 ] && [ "$(events "$1" feedback)" = 0 ] && [ "$(events "$1" pr.open)" = 0 ] &&
		pass "$2: no landing reached the trace" || fail "$2: a landing was recorded: $(show "pr:#$1")"
	expect_err_has "hard rule 3" "$2: stderr names the hard rule"
}
iterated 700 701 702 703 704 705 707 708 709 710 714 715 716
land STUB_PR_FILES='scripts/shared.sh docs/notes.md' 700
no_bump 700 "a manifest-listed file moved, the version unchanged"
expect_err_has "scripts/shared.sh" "stderr names the moved manifest-listed file"
printf '%s\n' "$T_ERR" | grep -qF 'docs/notes.md' && fail "the refusal names a file outside the manifest: $T_ERR" ||
	pass "and names no file outside the manifest"
expect_err_has "0.1.0" "and the shared-layer version it still reads"
grep -qE '^ARGV: git diff --name-only .*ba5eba5e' "$STUB_LOG" && pass "the diff it read is the PR's, from its merge base" ||
	fail "the diff was not read from the merge base: $(grep '^ARGV: git' "$STUB_LOG")"

land STUB_PR_FILES='scripts/shared.sh docs/notes.md VERSION UPDATING.md' STUB_PR_VER_HEAD=0.2.0 701
expect_status 0 "the same diff with a shared-layer bump lands"
[ "$(events 701 merge.land)" = 1 ] && pass "and records its merge.land" || fail "a bumped PR left $(events 701 merge.land) merge.land"

land STUB_PR_FILES='docs/notes.md README.md tests/x.test.sh' 702
expect_status 0 "a diff that moves no manifest-listed file lands"

land STUB_PR_FILES='VERSION scripts/joins.sh' STUB_MANIFEST_HEAD_EXTRA=scripts/joins.sh 703
no_bump 703 "a file joining the manifest with no bump"
expect_err_has "scripts/joins.sh" "the joining file is named"

land STUB_PR_FILES='VERSION scripts/leaves.sh' STUB_MANIFEST_BASE_EXTRA=scripts/leaves.sh 704
no_bump 704 "a file leaving the manifest with no bump"
expect_err_has "scripts/leaves.sh" "the leaving file is named"

land STUB_PR_FILES='scripts/shared.sh' STUB_PR_VER_HEAD=banana 705
no_bump 705 "a shared-layer line moved to no version"

land STUB_PR_FILES='scripts/shared.sh' 713 --no-iteration 'aside' --no-review 'aside'
no_bump 713 "the trace overrides do not reach the shared-layer check"

land STUB_PR_FILES='scripts/shared.sh' 707 --train
no_bump 707 "a train's landing"

land STUB_PR_FETCH_RC=1 708
not_landed 708 "a PR whose head could not be fetched"
expect_err_has "could not be read" "stderr says the diff could not be read"
land STUB_MB_RC=1 709
not_landed 709 "a PR with no merge base"
expect_err_has "no merge base" "stderr names the missing merge base"
expect_err_has "could not be read" "and says the diff could not be read"
land STUB_PR_HEAD_SHOW_RC=128 STUB_PR_FILES='docs/notes.md' 710
not_landed 710 "a PR whose head VERSION could not be read"
expect_err_has "VERSION could not be read" "stderr names the unread VERSION"
land STUB_PR_BASE_SHOW_RC=128 STUB_PR_FILES='docs/notes.md' 714
not_landed 714 "a PR whose merge base VERSION could not be read"
expect_err_has "VERSION could not be read" "stderr names the unread VERSION at the merge base"
land STUB_PR_NO_LIST=1 STUB_PR_FILES='scripts/shared.sh' 716
not_landed 716 "a PR whose VERSION lists no files at either end"
expect_err_has "reads empty" "stderr says the list read empty"
land STUB_PR_DIFF_RC=128 715
not_landed 715 "a PR whose diff git could not compute"
expect_err_has "could not diff" "stderr names the failed diff"

t_exec env TRACE_DIR= TRACE_CONFIG="$KIT/scripts/trace.config.sh" LAND_POLL_SECONDS=0 sh "$LAND" 711 </dev/null
expect_status 0 "unconfigured, a PR moving nothing listed still lands"
: >"$STUB_LOG"
printf '%s\n' "STUB_PR_FILES='scripts/shared.sh'" >"$STUB_KNOBS"
t_exec env TRACE_DIR= TRACE_CONFIG="$KIT/scripts/trace.config.sh" LAND_POLL_SECONDS=0 sh "$LAND" 712 </dev/null
: >"$STUB_KNOBS"
not_landed 712 "unconfigured, an unbumped shared-layer move"
expect_err_has "hard rule 3" "unconfigured, the refusal is the shared-layer one"


# ---------------------------------------------------------------------------
banner "17. The landing script is the kit's one merge.land emitter and one forge merge (#729)"
# ---------------------------------------------------------------------------
# On 2026-10-10 a session landed 17 PRs through a train helper of its own:
# it merged past this script's gate and wrote merge.land itself, after #662
# had made the script the train's per-PR step. A rule the prose states and no
# check holds routes around as easily as that, so this section scans the
# kit's tracked files for a merge.land emitter (a `kind=merge.land` emit, or
# the event spelled as JSON, its quotes escaped or not) and a forge merge call (`gh pr merge`, the REST
# merge endpoint, the GraphQL mutation), and fails on any outside the landing
# script and /merge-train's no-script path — one emit line and one merge line,
# for a consumer with no landing script. The suites (which stub and forbid
# these calls) and the history records (which narrate them) are not scanned:
# neither runs, and neither instructs an agent.
LAND_EMIT_RE='kind=merge\.land|\\?"kind\\?" *: *\\?"merge\.land|gh pr merge|pulls/[^ /]*/merge([^-a-z_]|$)|mergePullRequest'
# landing_emitters <root> — every hit in <root>'s tracked files, `<path>:<line>:<text>`.
landing_emitters() {
	git -C "$1" grep -nE "$LAND_EMIT_RE" -- . ':!tests' ':!docs/adr' ':!docs/diary.md'
}
# landing_strays <root> — the hits nothing allows: the landing script's are
# allowed whole; the train skill's first emit line and first merge line are
# its no-script path, and a second of either is a stray.
landing_strays() {
	landing_emitters "$1" | awk -F: '
		$1 == "scripts/land.kit.sh" { next }
		$1 == ".agents/skills/merge-train/SKILL.md" && /kind=merge\.land/ && !e++ { next }
		$1 == ".agents/skills/merge-train/SKILL.md" && /gh pr merge/ && !m++ { next }
		{ print }'
}

hits=$(landing_emitters "$KIT")
printf '%s\n' "$hits" | grep -q '^scripts/land\.kit\.sh:[0-9]*:.*kind=merge\.land' &&
	printf '%s\n' "$hits" | grep -q '^scripts/land\.kit\.sh:[0-9]*:.*gh pr merge' &&
	pass "the scan finds the landing script's own emitter and merge — it is not blind" ||
	fail "the scan does not find the landing script's emitter and merge: $hits"
strays=$(landing_strays "$KIT")
[ -z "$strays" ] && pass "no kit file but the landing script and the train's no-script path emits merge.land or merges" ||
	fail "merge.land emitters or forge merges outside the landing script: $strays"

# The bait: a scratch repo shaped like the kit, the allowed lines in place,
# then one stray at a time — each must be named, and the allowed shape not.
BAIT="$SCRATCH/emitters"
mkdir -p "$BAIT/scripts" "$BAIT/.agents/skills/merge-train" "$BAIT/tests"
git -C "$BAIT" init -q
printf '%s\n' 'gh pr merge "$PR" --merge' 'trace loud kind=merge.land "$@"' >"$BAIT/scripts/land.kit.sh"
printf '%s\n' 'gh pr merge "$PR" --merge' '`sh scripts/trace.sh emit kind=merge.land subject=pr:#<N>`' \
	'gh api -X PUT "repos/{owner}/{repo}/pulls/$PR/update-branch"' >"$BAIT/.agents/skills/merge-train/SKILL.md"
printf '%s\n' 'gh pr merge 1 --merge' 'kind=merge.land' >"$BAIT/tests/x.test.sh"
git -C "$BAIT" add -A
[ -z "$(landing_strays "$BAIT")" ] && pass "bait: the allowed shape, an update-branch call and a suite's stub are no strays" ||
	fail "bait: the allowed shape was flagged: $(landing_strays "$BAIT")"
# bait <path> <line> <label> — the line planted at <path> is named a stray.
bait() {
	mkdir -p "$(dirname "$BAIT/$1")"
	cp "$BAIT/$1" "$SCRATCH/emitters.held" 2>/dev/null || : >"$SCRATCH/emitters.held"
	printf '%s\n' "$2" >>"$BAIT/$1"
	git -C "$BAIT" add -A
	landing_strays "$BAIT" | grep -q "^$1:" && pass "bait: $3 is named" || fail "bait: $3 went unnamed"
	cp "$SCRATCH/emitters.held" "$BAIT/$1"
	[ -s "$BAIT/$1" ] || rm -f "$BAIT/$1"
	git -C "$BAIT" add -A
}
bait scripts/train-helper.sh 'gh pr merge "$n" --merge --admin' "a session's helper calling gh pr merge"
bait scripts/train-helper.sh "sh scripts/trace.sh emit kind=merge.land subject=pr:#\$n data.via=train-helper" "a helper emitting merge.land"
bait scripts/train-helper.sh 'gh api -X PUT "repos/o/r/pulls/$n/merge"' "a helper calling the REST merge endpoint"
bait scripts/train-helper.sh 'gh api graphql -f query="mutation { mergePullRequest(input: {}) { clientMutationId } }"' "a helper calling the GraphQL merge"
bait scripts/train-helper.sh 'printf "{\"kind\":\"merge.land\"}" >>"$trace"' "a helper writing merge.land as escaped JSON"
bait scripts/emit.mjs 'appendFileSync(trace, JSON.stringify({"kind":"merge.land"}))' "a script writing merge.land as plain JSON"
bait scripts/emit.mjs '{ "kind": "merge.land", "subject": "pr:#1" }' "a JSON line with spaces around its colon"
bait .agents/skills/merge-train/SKILL.md 'sh scripts/trace.sh emit kind=merge.land data.via=train-helper' "a second emit line in the train skill"
bait .agents/skills/merge-train/SKILL.md 'gh pr merge "$PR" --admin' "a second merge line in the train skill"
bait .agents/skills/review-pr/SKILL.md 'gh pr merge <N> --auto' "a merge in another skill"
[ -z "$(landing_strays "$BAIT")" ] && pass "bait: each stray removed, the shape is clean again" ||
	fail "bait: a stray outlived its removal: $(landing_strays "$BAIT")"

# The train skill says it in one line, and says how a release-bound red lands.
MT="$KIT/.agents/skills/merge-train/SKILL.md"
assert_file_has "$MT" "a merge outside the landing script is not a landing"
assert_file_has "$MT" "lands only after the release is cut"

# ---------------------------------------------------------------------------
banner "18. A landing whose ticket the trace never saw started says so (#775)"
# ---------------------------------------------------------------------------
# Two /implement runs opened PRs with no ticket.start (#730, #732), and /retro's
# chain-health question could not tell a ticket nobody started from one the
# trace lost. The landing reads ticket.start on the ticket it closes and, when
# the trace holds none, its merge.land carries data.ticket_start=no; with one,
# or with no ticket known, nothing extra.
# started <ticket> — a ticket.start on ticket:#<ticket>, as /implement writes it.
started() {
	env TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh" TRACE_QUIET=1 sh "$TRACE" emit kind=ticket.start \
		"subject=ticket:#$1" tier=implementer outcome=read reason=seeded </dev/null >/dev/null 2>&1 ||
		fail "could not seed a ticket.start on ticket:#$1"
}
# landing_of <pr> — the PR's landed merge.land, one line.
landing_of() { show "pr:#$1" --kind merge.land | grep -F '"outcome":"landed"'; }
iterated 720 721 722 723 724
land STUB_TICKET=190 720
expect_status 0 "a PR whose ticket was never started lands"
landing_of 720 | grep -qF '"ticket_start":"no"' && pass "its merge.land records ticket_start=no" ||
	fail "a never-started ticket's merge.land lacks ticket_start=no: $(landing_of 720)"

started 191
land STUB_TICKET=191 721
expect_status 0 "a PR whose ticket was started lands"
[ -n "$(landing_of 721)" ] && ! landing_of 721 | grep -qF '"ticket_start"' &&
	pass "a started ticket's merge.land records nothing extra" ||
	fail "a started ticket's merge.land carries ticket_start, or none was written: $(landing_of 721)"

# A ticket.start on #1920 is not one on #192: the subject is matched whole.
started 1920
land STUB_TICKET=192 722
landing_of 722 | grep -qF '"ticket_start":"no"' && pass "a ticket.start on a longer number does not count as #192's" ||
	fail "#1920's ticket.start was read as #192's: $(landing_of 722)"

started 193
land STUB_TICKET= 723 --ticket 193
[ -n "$(landing_of 723)" ] && ! landing_of 723 | grep -qF '"ticket_start"' &&
	pass "--ticket names the ticket read, as the closing reference does" ||
	fail "a started ticket named by --ticket was recorded unstarted: $(landing_of 723)"

land STUB_TICKET= 724
[ -n "$(landing_of 724)" ] && ! landing_of 724 | grep -qF '"ticket_start"' &&
	pass "with no ticket known, nothing is read and nothing extra recorded" ||
	fail "a landing with no ticket recorded ticket_start: $(landing_of 724)"

# ---------------------------------------------------------------------------
banner "19. A job stuck in progress after its run completed is re-run once, then a stop (#850)"
# ---------------------------------------------------------------------------
# pr:#842 waited 3,308 s, and pr:#831 hung the same way: the run had ended,
# one job record stayed in progress, and a watch on it never returns. While
# it waits the landing reads the run's job records; a stuck job is re-run
# once, by its job id, and named on stderr; the same job stuck again is a
# stop, recorded as a failed workflow like any red check.
iterated 850 851 852 853 854
land STUB_STALL='71 kit-ci / build' 850
expect_status 0 "a run with one job stuck in progress lands after one re-run"
[ "$(grep -c '^ARGV: run rerun --job 71$' "$STUB_LOG")" = 1 ] && pass "the stuck job is re-run once, by its id (gh run rerun --job 71)" ||
	fail "the stuck job was not re-run exactly once: $(grep 'run rerun' "$STUB_LOG")"
[ "$(grep -c '^ARGV: run rerun' "$STUB_LOG")" = 1 ] && pass "and nothing else is re-run" ||
	fail "more than the stuck job was re-run: $(grep 'run rerun' "$STUB_LOG")"
_rerun=$(line_of '^ARGV: run rerun --job')
_watch=$(line_of '^ARGV: run watch 901')
[ "$_rerun" -gt 0 ] && [ "$_watch" -gt "$_rerun" ] && pass "and the run is watched only after the re-run (line $_rerun < $_watch)" ||
	fail "the run was watched before the stuck job's re-run: rerun $_rerun, watch $_watch"
expect_err_has "kit-ci / build" "stderr names the stuck job"
expect_err_has "re-running" "and says it re-ran it"
landing_of 850 | grep -qF '"workflows":"success"' && pass "merge.land records the workflows success" ||
	fail "a landing cleared by one re-run was not recorded success: $(landing_of 850)"

land STUB_STALL='71 kit-ci / build' STUB_STALL_AFTER='72 kit-ci / build' 851
expect_status 1 "the same job stuck again after its re-run is a stop: exit 1"
[ "$(grep -c '^ARGV: run rerun' "$STUB_LOG")" = 1 ] && pass "it is never re-run a second time" ||
	fail "the stuck job was re-run $(grep -c '^ARGV: run rerun' "$STUB_LOG") times"
expect_err_has "stuck again" "stderr says the job stalled a second time"
landing_of 851 | grep -qF '"workflows":"failure"' && pass "and merge.land records the workflows failure" ||
	fail "a second stall was not recorded failure: $(landing_of 851)"

land STUB_STALL='71 kit-ci / build' STUB_STALL_AFTER='71 kit-ci / build' 852
expect_status 1 "a re-run that never leaves the stuck record is a stop: exit 1"
[ "$(grep -c '^ARGV: run rerun' "$STUB_LOG")" = 1 ] && pass "and it is re-run once only" ||
	fail "a re-run that never took was re-run $(grep -c '^ARGV: run rerun' "$STUB_LOG") times"
# One read finds the stall, then LAND_POLL_TRIES (12) reads after its re-run.
[ "$(grep -c '^ARGV: run view 901 --json status,jobs' "$STUB_LOG")" -le 13 ] && pass "within the wait's bound (LAND_POLL_TRIES reads after the re-run, 13 in all)" ||
	fail "it read the job records $(grep -c '^ARGV: run view 901 --json status,jobs' "$STUB_LOG") times, past 13"
expect_err_has "still stuck" "stderr says the job is still stuck after its re-run"

land STUB_STALL='71 kit-ci / build' STUB_RERUN_RC=1 853
expect_status 1 "a stuck job the forge refuses to re-run is exit 1"
landing_of 853 | grep -qF '"workflows":"failure"' && pass "and recorded with data.workflows=failure" ||
	fail "a refused job re-run was not recorded failure: $(landing_of 853)"

# Records the forge cannot answer for, and a stuck line that names no job id,
# leave the stall check: the run is watched as before #850, nothing re-run.
iterated 855 856 857
land STUB_JOBS_RC=1 855
expect_status 0 "job records the forge cannot read fall back to the watch, and the run lands"
grep -q '^ARGV: run watch 901' "$STUB_LOG" && pass "the run is watched" || fail "with unreadable job records, run 901 was never watched"
grep -q '^ARGV: run rerun' "$STUB_LOG" && fail "with unreadable job records, something was re-run: $(grep 'run rerun' "$STUB_LOG")" ||
	pass "and nothing is re-run"
landing_of 855 | grep -qF '"workflows":"success"' && pass "and merge.land records the workflows success" ||
	fail "a watched green run behind unreadable records was not recorded success: $(landing_of 855)"

land STUB_STALL='not-an-id kit-ci / build' 856
expect_status 0 "a stuck line whose first word is no job id falls back to the watch, and the run lands"
grep -q '^ARGV: run rerun' "$STUB_LOG" && fail "a stuck line with no job id was re-run: $(grep 'run rerun' "$STUB_LOG")" ||
	pass "and no job is re-run on it"
grep -q '^ARGV: run watch 901' "$STUB_LOG" && pass "the run is watched instead" || fail "with no job id, run 901 was never watched"

# That fallback watch is bounded by the wait: a watch that does not end within
# LAND_POLL_TRIES reads, LAND_POLL_SECONDS apart (one second at least), is
# stopped and the workflows recorded unknown, as an exhausted wait is.
: >"$STUB_LOG"
printf "STUB_JOBS_RC='1'\nSTUB_WATCH_SLEEP='6'\n" >"$STUB_KNOBS"
_t0=$(date +%s)
t_exec env LAND_POLL_SECONDS=0 LAND_POLL_TRIES=2 sh "$LAND" 857 </dev/null
_took=$(($(date +%s) - _t0))
: >"$STUB_KNOBS"
expect_status 1 "a fallback watch that outlives the wait is a stop: exit 1"
landing_of 857 | grep -qF '"workflows":"unknown"' && pass "and merge.land records the workflows unknown" ||
	fail "a fallback watch that outlived the wait was not recorded unknown: $(landing_of 857)"
expect_err_has "did not end within the wait" "stderr says the watch outlived the wait"
[ "$_took" -lt 6 ] && pass "and the landing did not wait for the watch's end (${_took}s)" ||
	fail "the landing waited ${_took}s, the watch's whole length"

# The record as the forge wrote it for #831: the run still in progress, the
# job's conclusion success, its status never closed. The script's own --jq
# program, run by jq, has to call that job stuck.
if command -v jq >/dev/null 2>&1; then
	cat >"$SCRATCH/run854.json" <<'JSON'
{"status": "in_progress", "jobs": [
 {"databaseId": 81, "name": "docs gate", "status": "completed", "conclusion": "success"},
 {"databaseId": 82, "name": "suite (land)", "status": "in_progress", "conclusion": "success"}]}
JSON
	cat >"$SCRATCH/run854-after.json" <<'JSON'
{"status": "completed", "jobs": [
 {"databaseId": 81, "name": "docs gate", "status": "completed", "conclusion": "success"},
 {"databaseId": 83, "name": "suite (land)", "status": "completed", "conclusion": "success"}]}
JSON
	land STUB_RUN_JSON="$SCRATCH/run854.json" STUB_RUN_JSON_AFTER="$SCRATCH/run854-after.json" 854
	expect_status 0 "through jq, a job ended but never closed is re-run and the run lands"
	[ "$(grep -c '^ARGV: run rerun --job 82$' "$STUB_LOG")" = 1 ] && pass "through jq, the one stuck job is re-run (82)" ||
		fail "through jq, the stuck job was not re-run once: $(grep 'run rerun' "$STUB_LOG")"
	expect_err_has "suite (land)" "through jq, stderr names it"
else
	skip "no jq on PATH — the script's own job-record program is not run by this suite here"
fi

# ---------------------------------------------------------------------------
banner "20. A factory ticket's PR lands by its id (PRD-15 slice 4, runtime/R241 to R245)"
# ---------------------------------------------------------------------------
# A factory ticket has no forge issue, so its PR closes none: the landing line
# names it, `<!-- implement: ticket=T-90 tier=implementer -->`, or --ticket
# does. Its events take `ticket:T-90` wherever an issue's take `ticket:#<N>`
# (the trace's TRACE_FACTORY_IDS, ADR-0040). The landing runs no `factory`
# subcommand and writes nothing under .factory/: a stand-in `factory` that
# fails if called sits first on PATH, and the landings run from a scratch
# project whose .factory/ tree is compared before and after.
cat >"$STUBDIR/factory" <<'FEOF'
#!/bin/sh
printf 'factory %s\n' "$*" >>"$FACTORY_LOG"
exit 1
FEOF
chmod +x "$STUBDIR/factory"
FACTORY_LOG="$SCRATCH/factory.log"
: >"$FACTORY_LOG"
export FACTORY_LOG
FPROJ="$SCRATCH/factory-project"
mkdir -p "$FPROJ/.factory/items/T-90"
printf -- '---\nid: T-90\nstage: review\n---\n' >"$FPROJ/.factory/items/T-90/ticket.md"
# tree_sum <dir> — one checksum line per file under <dir>, sorted: two equal
# sums are an unchanged tree.
tree_sum() { (cd "$1" && find . -type f -exec cksum {} + | sort); }
_fp_before=$(tree_sum "$FPROJ/.factory")
_fk_before=$(tree_sum "$KIT/.factory")
cd "$FPROJ" || fail "could not enter the scratch factory project"
# started_id <id> — a ticket.start on ticket:<id>, as /implement writes it.
started_id() {
	env TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh" TRACE_QUIET=1 sh "$TRACE" emit kind=ticket.start \
		"subject=ticket:$1" tier=implementer outcome=read reason=seeded </dev/null >/dev/null 2>&1 ||
		fail "could not seed a ticket.start on ticket:$1"
}
# lands_on <PR> <id> <label> — the PR landed, and its events joined ticket:<id>.
lands_on() {
	expect_status 0 "$3: lands, exit 0"
	landing_of "$1" | grep -qF "\"related\":\"ticket:$2\"" && pass "$3: merge.land is related to ticket:$2" ||
		fail "$3: merge.land is not related to ticket:$2: $(landing_of "$1")"
	landing_of "$1" | grep -qF '"implement":"yes"' && pass "$3: merge.land records implement=yes" ||
		fail "$3: merge.land lacks implement=yes: $(landing_of "$1")"
	show "ticket:$2" --kind feedback | grep -qF "\"subject\":\"ticket:$2\"" && pass "$3: its feedback is on ticket:$2" ||
		fail "$3: no feedback on ticket:$2: $(show "ticket:$2")"
	show "pr:#$1" --kind pr.open | grep -qF "ticket:$2" && pass "$3: its pr.open is related to ticket:$2" ||
		fail "$3: its pr.open is not related to ticket:$2: $(show "pr:#$1" --kind pr.open)"
}
iterated 960 961 962 963 964 965 966 967 968
f=$(body factory90 "<!-- implement: ticket=T-90 tier=implementer -->")
land STUB_TICKET= "STUB_BODY_FILE=$f" 960
lands_on 960 T-90 "runtime/R243, runtime/R244: a PR closing no issue, its line naming T-90, no --ticket"
landing_of 960 | grep -qF '"ticket_start":"no"' && pass "with no ticket.start on ticket:T-90, merge.land records ticket_start=no" ||
	fail "an unstarted factory ticket's merge.land lacks ticket_start=no: $(landing_of 960)"

started_id T-91
f=$(body factory91 "<!-- implement: ticket=T-91 tier=implementer -->")
land STUB_TICKET= "STUB_BODY_FILE=$f" 961 --ticket T-91
lands_on 961 T-91 "runtime/R241, runtime/R244: --ticket T-91"
[ -n "$(landing_of 961)" ] && ! landing_of 961 | grep -qF '"ticket_start"' &&
	pass "--ticket T-91: the ticket.start on ticket:T-91 is read" ||
	fail "--ticket T-91: a started factory ticket was recorded unstarted: $(landing_of 961)"

# A ticket.start on T-920 is not one on T-92: the subject is matched whole.
started_id T-920
f=$(body factory92 "<!-- implement: ticket=T-92 tier=implementer -->")
land STUB_TICKET= "STUB_BODY_FILE=$f" 962
lands_on 962 T-92 "a line naming T-92"
landing_of 962 | grep -qF '"ticket_start":"no"' && pass "a ticket.start on T-920 does not count as T-92's" ||
	fail "T-920's ticket.start was read as T-92's: $(landing_of 962)"

# Any other spelling is no line: recorded absent, and never the PR's ticket.
_fx_pr=962
for _fx_line in "ticket=T-9" "ticket=T-007" "ticket=t-07" "ticket=T-1234567" "ticket=T-9x" "ticket=PRD-15"; do
	_fx_pr=$((_fx_pr + 1))
	f=$(body "factorybad.$_fx_pr" "<!-- implement: $_fx_line tier=implementer -->")
	land STUB_TICKET= "STUB_BODY_FILE=$f" "$_fx_pr"
	landed_with "$_fx_pr" "runtime/R242: a line spelled $_fx_line" '"implement":"no"'
	landing_of "$_fx_pr" | grep -qF '"related":"ticket:' && fail "a line spelled $_fx_line named the PR's ticket: $(landing_of "$_fx_pr")" ||
		pass "a line spelled $_fx_line names no ticket"
done
[ "$_fx_pr" -le 968 ] || fail "section 20 ran past the PRs it seeded"

# A PR that closes an issue keeps the issue as its ticket: a factory id on its
# line is another ticket's, and the line is recorded absent.
iterated 970
f=$(body factorycloses "<!-- implement: ticket=T-90 tier=implementer -->")
land "STUB_BODY_FILE=$f" 970
landed_with 970 "a PR closing #77 whose line names T-90" '"implement":"no"' '"related":"ticket:#77"'

# --ticket takes an issue number or a canonical factory id, nothing else, and
# refuses before any forge call.
for _fx_t in T-9x T-9 T-007 t-07 T-1234567 PRD-15 '#77' T-; do
	land 971 --ticket "$_fx_t"
	expect_status 2 "runtime/R241: --ticket $_fx_t is a usage error"
	[ -s "$STUB_LOG" ] && fail "--ticket $_fx_t reached the forge: $(cat "$STUB_LOG")" ||
		pass "--ticket $_fx_t: no forge call"
done

cd "$KIT" || fail "could not return to the kit"
[ -s "$FACTORY_LOG" ] && fail "the landing ran the factory: $(cat "$FACTORY_LOG")" ||
	pass "runtime/R245: the landing ran no factory subcommand"
[ "$(tree_sum "$FPROJ/.factory")" = "$_fp_before" ] && pass "runtime/R245: the project's .factory/ is unchanged" ||
	fail "the landing changed the project's .factory/"
[ "$(tree_sum "$KIT/.factory")" = "$_fk_before" ] && pass "the kit's .factory/ is unchanged" ||
	fail "the landing changed the kit's .factory/"

# /merge-train reads the two-form line and writes the factory id's subjects
# (process/R240, R241), and /pr-iterate's verdict takes the same handle.
MT="$KIT/.agents/skills/merge-train/SKILL.md"
PI="$KIT/.agents/skills/pr-iterate/SKILL.md"
# The train's filter, run as the skill spells it, prints the handle for each
# canonical spelling and nothing for any other (process/R241).
mt_filter=$(grep -o "sed -n -e 's/^<!-- implement: .*/p'" "$MT" | head -n 1)
[ -n "$mt_filter" ] && pass "process/R241: /merge-train spells its landing-line filter" ||
	fail "process/R241: /merge-train's landing-line filter is not the three-expression sed"
for _mf in '#77 #77' 'T-07 T-07' 'T-90 T-90' 'T-123456 T-123456' 'T-9 ' 'T-007 ' 'T-1234567 ' 't-07 ' '#-1 ' 'PRD-15 '; do
	_mf_in=${_mf%% *} _mf_want=${_mf#* }
	_mf_got=$(printf '<!-- implement: ticket=%s tier=planner -->\n' "$_mf_in" | eval "$mt_filter" | cut -d' ' -f1)
	[ "$_mf_got" = "$_mf_want" ] && pass "process/R241: /merge-train's filter reads ticket=$_mf_in as '${_mf_want}'" ||
		fail "process/R241: /merge-train's filter read ticket=$_mf_in as '$_mf_got', not '$_mf_want'"
done
mt_flat=$(tr '\n' ' ' <"$MT" | tr -s ' ')
t_text_has "$mt_flat" 'related=ticket:<ticket>' "/merge-train's merge.land relates ticket:<ticket>, the handle as the line names it"
t_text_has "$mt_flat" 'subject=ticket:<ticket>' "process/R240: /merge-train's feedback is on ticket:<ticket>"
t_text_has "$mt_flat" 'any other spelling is no line' "process/R241: /merge-train treats any other spelling as no line"
t_text_has "$mt_flat" '`T-07`, never `T-7`' "/merge-train names the canonical factory id"
printf '%s\n' "$mt_flat" | grep -qF 'ticket:#<ticket>' && fail "/merge-train still writes ticket:#<ticket>" ||
	pass "/merge-train writes no ticket:#<ticket>"
pi_flat=$(tr '\n' ' ' <"$PI" | tr -s ' ')
t_text_has "$pi_flat" 'subject=ticket:<ticket>' "process/R240: /pr-iterate's feedback is on ticket:<ticket>"
printf '%s\n' "$pi_flat" | grep -qF 'ticket:#<ticket>' && fail "/pr-iterate still writes ticket:#<ticket>" ||
	pass "/pr-iterate writes no ticket:#<ticket>"


# ---------------------------------------------------------------------------
banner "21. The landing takes the same action whatever the risk rule said (process/R65, PRD-09 slice 1)"
# ---------------------------------------------------------------------------
# The risk rule is report-only: a PR it called high lands exactly as one it
# called low, and the landing script reads nothing of it.
iterated 980 981
# judged <PR> <outcome> <effective> — a risk.judge at the stub's head.
judged() {
	env TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh" TRACE_QUIET=1 sh "$TRACE" emit kind=risk.judge "subject=pr:#$1" \
		"outcome=$2" "data.head=$STUB_SHA" data.planner=low "data.rule=$3" "data.effective=$3" data.switch=on reason=seeded </dev/null >/dev/null 2>&1 ||
		fail "could not seed a risk.judge on pr:#$1"
}
judged 980 disagreed 'high unlearned'
judged 981 agreed low
land 980
_rk_high=$(merges)
landed_with 980 "process/R65: a PR the risk rule called high unlearned" '"outcome":"landed"'
land 981
landed_with 981 "process/R65: a PR the risk rule called low" '"outcome":"landed"'
[ "$_rk_high" = "$(merges)" ] && pass "process/R65: both made the same merge call" || fail "process/R65: the high PR made $_rk_high merge calls, the low one $(merges)"
# Its lane mode is the one exception PRD-10 writes into process/R65 (section
# 24): the rule is named in the lane's block and nowhere else, comments aside.
sed -e '/^# --- 1L\./,/^# --- 1d\./d' -e '/^[[:space:]]*#/d' "$LAND" | grep -qE 'risk\.sh|risk\.judge' &&
	fail "process/R65: the landing script reads the risk rule outside its lane mode" ||
	pass "process/R65: outside its lane mode, the landing script names neither the rule nor its event"
grep -q '^# --- 1L\.' "$LAND" && sed -n '/^# --- 1L\./,/^# --- 1d\./p' "$LAND" | grep -q 'scripts/risk\.sh' &&
	pass "process/R65: the lane's block is where the rule is run — the cut above is not blind" ||
	fail "process/R65: no lane block running scripts/risk.sh between 1L and 1d — the cut above reads nothing"

banner "22. merge.land records what the verifier said at the head, and nothing waits on it (runtime/R214, R215, PRD-13 slice 4)"
# ---------------------------------------------------------------------------
# The landing records data.verified — the latest verify.verdict on the PR
# stamped at or after the head commit's date, or none — and no outcome of it
# changes whether the script refuses, waits or merges (runtime/R215).
# vverdict <PR> <outcome> [<disputed>] — a verifier's verdict, now, in the
# broker's shape, with <disputed> disputed pins (0 unless given).
vverdict() {
	_vv_data=
	[ "$2" = unavailable ] || _vv_data="data.reviewed=$STUB_SHA data.provider=anthropic data.rung=cross-provider data.disputed=${3:-0}"
	# shellcheck disable=SC2086 # the verdict's keys split into words on purpose
	env TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh" TRACE_QUIET=1 sh "$TRACE" emit kind=verify.verdict \
		"subject=pr:#$1" "outcome=$2" data.via=broker $_vv_data reason=seeded </dev/null >/dev/null 2>&1 ||
		fail "could not seed a verify.verdict $2 on pr:#$1"
}
iterated 990 991 992 993
vverdict 990 blocked
land 990
landed_with 990 "runtime/R214: a blocked verify.verdict at the head beside the kit's Axis-1 pass" '"verified":"blocked"' '"reviewed":"yes"'
[ "$(merges)" = 1 ] && pass "runtime/R215: a blocked verifier still merges, one merge call" || fail "runtime/R215: a blocked verifier made $(merges) merge calls"
vverdict 991 pass
vverdict 991 unavailable
land 991
landed_with 991 "runtime/R214: the LATEST verdict at the head is the one recorded" '"verified":"unavailable"'
land 992
landed_with 992 "runtime/R214: no verify.verdict at all" '"verified":"none"'
# A verdict stamped before the head commit's date is not at the head.
vverdict 993 blocked
land STUB_HEAD_DATE=2999-01-01T00:00:00Z 993 --no-iteration 'a later head' --no-review 'a later head'
landed_with 993 "runtime/R214: a verify.verdict stamped before the head's date" '"verified":"none"'
# A blocked verifier never refuses, and a pass never stands in for the review.
seed pr.iterate green 994
vverdict 994 pass
land 994
not_landed 994 "runtime/R215: a verifier pass with no Axis-1 review is refused as before"
vverdict 995 blocked
seed pr.iterate green 995
seed review.verdict pass 995
land STUB_MERGE_RC=1 995
show 'pr:#995' --kind merge.land | grep -qF '"verified":"blocked"' && pass "runtime/R214: a stopped merge.land carries data.verified too" ||
	fail "runtime/R214: the stopped merge.land lacks verified=blocked: $(show 'pr:#995' --kind merge.land)"

banner "23. The low-risk lane's decision is recorded, and shared invariant §7 names its one exception (PRD-10 slice 1, #913)"
# The lane is the landing script's own mode, so its record is held here. §7
# ships verbatim, so its exception is worded portably: it names no lane, no
# script and no record, only the conditions a project's own decision must meet.
_s7=$(sed -n '/^## 7\./,/^## 8\./p' "$KIT/constitution/shared-invariants.md")
for _s7_w in 'judged low risk' 'measured post-merge outcomes' 'standing authorization' 'names that human' \
	'stop at once' 'escaped mistakes return to that human' 'recorded decision' 'as it reads above'; do
	printf '%s\n' "$_s7" | tr '\n' ' ' | grep -qF "$_s7_w" && pass "§7's exception says: $_s7_w" || fail "§7 lacks the exception's words: $_s7_w"
done
printf '%s\n' "$_s7" | grep -qiwE 'lane|landing script|ADR|pr-iterate|trace' &&
	fail "§7 names kit vocabulary: $(printf '%s\n' "$_s7" | grep -iwE 'lane|landing script|ADR|pr-iterate|trace')" ||
	pass "§7's exception names none of the kit's vocabulary"
_lane_adr=$(grep -l '^- \*\*Supersedes / amends\*\*: supersedes shared invariant §7 for the low-risk lane only' "$KIT"/docs/adr/[0-9]*.md 2>/dev/null | head -1)
if [ -n "$_lane_adr" ]; then
	pass "a record supersedes shared invariant §7 for the low-risk lane only"
	for _la_w in 'amends ADR-0024 clause 7' 'ADR-0036' '§5 keeps its text' 'standing authorization' 'lane policy' 'closed' \
		'closed until the lane policy names an operator' 'a hold is exit 4 and an event; a refusal stays exit 2 and silent' \
		'held by path, whatever the risk' 'only a failed QA gets a revert pull request' 'a red base branch holds the lane'; do
		tr '\n' ' ' <"$_lane_adr" | sed 's/  */ /g' | grep -qiF "$_la_w" && pass "…and it says: $_la_w" || fail "the lane record lacks: $_la_w"
	done
	_la_row=$(grep -F "($(basename "$_lane_adr"))" "$KIT/docs/adr/INDEX.md")
	printf '%s\n' "$_la_row" | grep -qF 'supersedes shared invariant §7 for the low-risk lane only' &&
		printf '%s\n' "$_la_row" | grep -qF 'amends ADR-0024 clause 7' && printf '%s\n' "$_la_row" | grep -qF 'ADR-0036' &&
		pass "…and its index row names what it supersedes and amends" || fail "the index row for $(basename "$_lane_adr") does not name §7, ADR-0024 clause 7 and ADR-0036: $_la_row"
else
	fail "no record supersedes shared invariant §7 for the low-risk lane only"
fi
for _la_g in 'Low-risk lane' 'Lane policy' 'Hold' 'Escape' 'Notice'; do
	grep -q "^- \*\*$_la_g\*\* —" "$KIT/docs/domain-glossary.md" && pass "the glossary defines $_la_g" || fail "the glossary has no $_la_g entry"
done

# ---------------------------------------------------------------------------
banner "24. The low-risk lane lands a low-risk PR, and holds a closed lane, a tripped switch and a high risk (PRD-10 slice 2, #914)"
# ---------------------------------------------------------------------------
# With --lane the script makes every refusal above, then the lane's own
# checks (ADR-0047): the lane policy read at the base through the policy
# reader, and the risk rule run at the PR's head. Both need a real repository
# the stub git cannot give, so this section runs a COPY of the kit's scripts
# whose risk rule and policy reader are stubs: each logs its argv beside the
# forge's and answers from the knobs. The script under test is the kit's own,
# copied as it is; no environment switch reaches it, so nothing here is a
# seam a lane run in production could be pointed at.
LANEKIT="$SCRATCH/lanekit"
mkdir -p "$LANEKIT/scripts"
cp "$KIT"/scripts/*.sh "$LANEKIT/scripts/"
LANE_FIX="$SCRATCH/lane-policies"
mkdir -p "$LANE_FIX"
printf "LANE_OPERATOR='octocat'\nLANE_HOLD_PATTERNS='scripts/land.kit.sh .githooks/* adapters/claude-code/*'\n" >"$LANE_FIX/open"
printf "LANE_OPERATOR=''\n" >"$LANE_FIX/none"
printf "LANE_OPERATOR='octo cat; BAIT-POLICY'\n" >"$LANE_FIX/bad"
printf "LANE_OPERATOR='octocat'\nLANE_HOLD_PATTERNS='docs/*.md;BAIT-POLICY'\n" >"$LANE_FIX/badpat"
printf "LANE_OPERATOR='octocat'\n" >"$LANE_FIX/nopat"
export LANE_FIX
# The policy reader: STUB_LANE names the base's lane policy — open, none,
# bad — or `fail`, the reader failing closed (exit 3, its one line).
cat >"$LANEKIT/scripts/policy.sh" <<'EOF'
#!/bin/sh
printf 'ARGV: policy %s\n' "$*" >>"$STUB_LOG"
[ -s "$STUB_KNOBS" ] && . "$STUB_KNOBS"
# `touched` answers STUB_TOUCHED: 1 a judging file in the diff, 3 failed closed.
[ "$1" != touched ] || { [ "${STUB_TOUCHED:-0}" = 0 ] || echo scripts/BAIT.config.sh; exit "${STUB_TOUCHED:-0}"; }
[ "${STUB_LANE:-open}" != fail ] || { echo "fail-closed missing $2"; exit 3; }
printf '%s\n' "$LANE_FIX/${STUB_LANE:-open}"
EOF
# The risk rule: its lines, the effective and the switch from the knobs; the
# rule's own line says low whatever the effective says, and a bait line
# carries text no lane line may repeat — the lane reads two lines only.
cat >"$LANEKIT/scripts/risk.sh" <<'EOF'
#!/bin/sh
printf 'ARGV: risk %s\n' "$*" >>"$STUB_LOG"
[ -s "$STUB_KNOBS" ] && . "$STUB_KNOBS"
printf 'effective: %s\nplanner: low\nrule: low\narea: security earned\nswitch: %s\nBAIT-RISK: effective: low\n' \
	"${STUB_EFFECTIVE-low}" "${STUB_SWITCH:-on}"
EOF
_land_kit=$LAND
LAND="$LANEKIT/scripts/land.kit.sh"
LANE_HEAD=1234567890123456789012345678901234567890
# The base branch's tree as the lane reads it (runtime/R84): the running copy
# itself, so no drift unless a case says so. The ticket's body and the PR's
# carry one covered requirement and its one passing row, so the check table
# passes unless a case gives other bodies (runtime/R87).
STUB_BASE_TREE=$LANEKIT
LANE_TICKET="$SCRATCH/lane-ticket.md"
printf '%s\n' 'BAIT-TICKET: Covers: none' 'Covers: runtime/R1' 'Test-tier: runtime/R1 suite' >"$LANE_TICKET"
# lane_table <requirement> <tier> <result> <evidence> — one check-table row.
lane_table() {
	printf '<!-- check-table -->\n| Requirement | Test tier | Result | Evidence |\n| --- | --- | --- | --- |\n'
	printf '| %s | %s | %s | %s |\n' "$@"
}
STUB_DEFAULT_ISSUE=$LANE_TICKET
STUB_DEFAULT_BODY=$(body lane-default "$(lane_table runtime/R1 suite pass 'tests/x.sh::a test@abcdef1')")
export STUB_BASE_TREE STUB_DEFAULT_ISSUE STUB_DEFAULT_BODY

# lane_lines_closed <label> — every stdout line of the last run is of a shape
# the lane may print: closed tokens, numbers, shas and digits (runtime/R102).
lane_lines_closed() {
	_llc_bad=$(printf '%s\n' "$T_OUT" | grep -vE '^(lane: (landed|held (closed|drift|path|base-red|check-table|verifier (disputed|blocked|unavailable|none)|switch|risk))|landed #[0-9]+ [0-9a-f]{40} \(merge\) · workflows [a-z]+ · waited [0-9]+s|feedback: unasked)$' | grep .)
	[ -z "$_llc_bad" ] && pass "runtime/R102: $1: every line the lane printed is a closed token, a number or a sha" ||
		fail "runtime/R102: $1: the lane printed a line outside its closed set: $_llc_bad"
}
# no_bait <label> <subject>… — no event on the subjects carries text from the
# PR's title, body or branch, the ticket, the lane policy or the risk rule's
# other lines (runtime/R102).
no_bait() {
	_nb_label=$1
	shift
	for _nb_s in "$@"; do
		show "$_nb_s" | grep -q 'BAIT' && fail "runtime/R102: $_nb_label: an event on $_nb_s carries forge or file text: $(show "$_nb_s" | grep BAIT)" ||
			pass "runtime/R102: $_nb_label: no event on $_nb_s carries text from a title, body, branch or policy"
	done
}
iterated 9101 9102 9103 9104 9105 9106 9107 9108 9109 9120 9121 9122 9123 9124
# A verifier's pass at each head, so no PR here holds with `verifier` unless a
# case says so (runtime/R104).
for _lv in 9101 9102 9103 9104 9105 9106 9107 9108 9109 9120 9121 9122 9123 9124; do vverdict "$_lv" pass; done

# --- UC1: a low-risk PR lands through the lane --------------------------------
_lb=$(body lane301 '<!-- implement: ticket=#77 tier=implementer -->
BAIT-BODY: effective: low
## Decision log

<!-- decision-log -->
| Decision | Surface | What was decided | Why |
| --- | --- | --- | --- |
| D-1 | scripts/x.sh | kept BAIT-BODY | one line |
| ~~D-2~~ | ~~docs/y.md~~ | ~~struck~~ | ~~held~~ |
| D-3 | scripts/z.sh | amended | one line |

<!-- check-table -->
| Requirement | Test tier | Result | Evidence |
| --- | --- | --- | --- |
| runtime/R1 | suite | pass | tests/x.sh::a test@abcdef1 |

```
<!-- decision-log -->
| D-9 | fenced | not a log | quoted |
```')
land STUB_BODY_FILE="$_lb" STUB_TITLE='feat(x): BAIT-TITLE' STUB_BRANCH=feat/BAIT-BRANCH 9101 --lane
expect_status 0 "runtime/R90: UC1's low-risk PR lands through the lane, exit 0"
expect_out_has 'lane: landed' "runtime/R90: the lane prints lane: landed"
printf '%s\n' "$T_OUT" | tail -n 1 | grep -qx 'lane: landed' && pass "runtime/R90: lane: landed is the run's last line" ||
	fail "runtime/R90: the last line is not lane: landed: $T_OUT"
grep -qx "ARGV: policy read scripts/lane.kit.config.sh --base refs/remotes/origin/main" "$STUB_LOG" &&
	pass "runtime/R83: the lane reads the kit's lane policy at the base, through the policy reader" ||
	fail "runtime/R83: the lane policy was not read at origin's base through the policy reader: $(grep 'ARGV: policy' "$STUB_LOG")"
grep -qx "ARGV: risk refs/remotes/origin/main $LANE_HEAD --pr 9101 --ticket 77" "$STUB_LOG" &&
	pass "runtime/R88: the risk rule ran at the PR's head commit, with the PR and its ticket" ||
	fail "runtime/R88: the risk rule was not run at the head with the PR and ticket: $(grep 'ARGV: risk' "$STUB_LOG")"
grep -qx "ARGV: pr merge 9101 --merge --match-head-commit $LANE_HEAD" "$STUB_LOG" &&
	pass "runtime/R89: the lane merges the exact head the risk rule judged" ||
	fail "runtime/R89: the merge did not pin the judged head: $(grep 'pr merge' "$STUB_LOG")"
[ "$(line_of 'ARGV: risk')" -lt "$(line_of 'ARGV: pr merge')" ] && [ "$(line_of 'ARGV: policy')" -lt "$(line_of 'ARGV: risk')" ] &&
	pass "runtime/R88: the lane policy, then the risk rule, both before the merge" ||
	fail "runtime/R88: the lane's reads are out of order: $(cat "$STUB_LOG")"
landed_with 9101 "runtime/R90: the lane's landing" '"outcome":"landed"' '"via":"lane"' '"decisions":"3"' "\"merge_sha\":\"$STUB_SHA\""
_lf=$(show 'ticket:#77' --kind feedback | grep -F '"related":"pr:#9101"')
printf '%s\n' "$_lf" | grep -qF '"outcome":"unasked"' && printf '%s\n' "$_lf" | grep -qF '"by":"lane"' &&
	pass "runtime/R90: feedback outcome=unasked data.by=lane, joined to the PR" ||
	fail "runtime/R90: no unasked feedback by the lane on the ticket: $_lf"
lane_lines_closed "a lane landing"
no_bait "a lane landing" 'pr:#9101' 'ticket:#77'

# --- holds: closed, switch, risk ----------------------------------------------
# lane_held <PR> <token> <label> [<reason>] — the last run held: exit 4, one
# line, no merge call, and exactly one merge.land skipped by the lane with the
# token and the head commit — the PR's only event but the ones seeded at its
# head. A reason follows the token on the line (the verifier's, runtime/R104).
lane_held() {
	_lh_line="lane: held $2${4:+ $4}"
	expect_status 4 "runtime/R91: $3: held, exit 4"
	[ "$T_OUT" = "$_lh_line" ] && pass "runtime/R91: $3: it prints $_lh_line, and nothing else" ||
		fail "runtime/R91: $3: stdout is not '$_lh_line': $T_OUT"
	[ "$(merges)" = 0 ] && pass "runtime/R91: $3: no merge call" || fail "runtime/R91: $3: the forge was asked to merge a held PR"
	_lh=$(show "pr:#$1" --kind merge.land)
	[ "$(printf '%s\n' "$_lh" | grep -c .)" = 1 ] && printf '%s\n' "$_lh" | grep -qF '"outcome":"skipped"' &&
		printf '%s\n' "$_lh" | grep -qF '"via":"lane"' && printf '%s\n' "$_lh" | grep -qF "\"hold\":\"$2\"" &&
		printf '%s\n' "$_lh" | grep -qF "\"head\":\"$LANE_HEAD\"" &&
		pass "runtime/R91: $3: one merge.land outcome=skipped data.via=lane, with the token and the head commit" ||
		fail "runtime/R91: $3: the hold's merge.land is not the one expected: $_lh"
	[ "$(events "$1" feedback)" = 0 ] &&
		[ "$(show "pr:#$1" | grep -vE '"kind":"(pr\.iterate|review\.verdict|verify\.verdict)"' | grep -c '"kind"' | tr -d ' ')" = 1 ] &&
		pass "runtime/R91: $3: the hold is the run's one event" ||
		fail "runtime/R91: $3: a held run recorded more than its hold: $(show "pr:#$1")"
	lane_lines_closed "$3"
	no_bait "$3" "pr:#$1"
}
land STUB_LANE=none STUB_TITLE='BAIT-TITLE' 9102 --lane
lane_held 9102 closed "runtime/R83: a lane policy that names no operator"
grep -q '^ARGV: risk' "$STUB_LOG" && fail "runtime/R83: a closed lane still ran the risk rule" ||
	pass "runtime/R83: a closed lane holds before the risk rule runs"
land STUB_LANE=fail 9103 --lane
lane_held 9103 closed "runtime/R83: a lane policy the base-branch policy contract cannot read"
land STUB_LANE=bad 9107 --lane
lane_held 9107 closed "runtime/R83: a lane policy whose operator is no forge login"
land STUB_SWITCH=tripped STUB_EFFECTIVE='high unlearned' 9104 --lane
lane_held 9104 switch "runtime/R88: a tripped kill switch"
land STUB_EFFECTIVE='high unlearned' 9105 --lane
lane_held 9105 risk "runtime/R88: a high effective risk, the rule's own line low"
land STUB_EFFECTIVE='high unclear' STUB_SWITCH=bogus 9108 --lane
lane_held 9108 risk "runtime/R88: a switch line neither on nor tripped, with a high risk"
land STUB_EFFECTIVE= 9109 --lane
lane_held 9109 risk "runtime/R88: a risk rule that printed no effective risk"

# --- holds: drift, path, base-red, check-table, verifier (PRD-10 slice 3, #915) ---
# Between `closed` and `switch`, in runtime/R82's order, each the same shape:
# `lane: held <token>`, exit 4, one merge.land skipped by the lane.
iterated 9130 9131 9132 9133 9134 9135 9136 9137 9138 9139 9140 9141 9142 9143 9144 9145 9146 9147 9148 9149 9150 9151 9152 9153 9154 9155 9156 9157 9158 9159 9160
for _lv in 9130 9131 9132 9133 9134 9135 9136 9137 9138 9139 9140 9141 9142 9143 9144 9145 9146 9147 9148 9149 9150 9151 9152 9153 9154 9155 9156 9157 9158 9160; do vverdict "$_lv" pass; done

# drift: the running copy's landing script or risk rule is not the base's.
land STUB_DRIFT=land.kit.sh 9130 --lane
lane_held 9130 drift "runtime/R84: a landing script that differs from the base branch's"
grep -qx 'ARGV: git show refs/remotes/origin/main:scripts/land.kit.sh' "$STUB_LOG" &&
	pass "runtime/R84: the lane reads the base's landing script at origin's base" ||
	fail "runtime/R84: the base's landing script was not read: $(grep 'git show' "$STUB_LOG")"
grep -q '^ARGV: risk' "$STUB_LOG" && fail "runtime/R82: a drift hold still ran the risk rule" ||
	pass "runtime/R82: a drift hold comes before the risk rule"
land STUB_DRIFT=risk.sh 9131 --lane
lane_held 9131 drift "runtime/R84: a risk rule that differs from the base branch's"
land STUB_DRIFT=gone 9132 --lane
lane_held 9132 drift "runtime/R84: a base branch whose copy cannot be read"

# path: the manifest at either end, a judging policy file, a hold pattern.
land STUB_PR_FILES=UPDATING.md STUB_PR_VER_HEAD=0.2.0 9133 --lane
lane_held 9133 path "runtime/R85: a diff touching a file VERSION's files: list names (a bumped release)"
land STUB_PR_FILES=docs/gone.md STUB_MANIFEST_BASE_EXTRA=docs/gone.md STUB_PR_VER_HEAD=0.2.0 9134 --lane
lane_held 9134 path "runtime/R85: a file the manifest names only at the merge base"
land STUB_TOUCHED=1 STUB_PR_FILES=scripts/x.config.sh 9135 --lane
lane_held 9135 path "runtime/R85: a diff touching a policy file read under the base-branch policy contract"
grep -qx "ARGV: policy touched refs/remotes/origin/main $LANE_HEAD" "$STUB_LOG" &&
	pass "runtime/R85: the judging files are asked of the policy reader, from the base to the head" ||
	fail "runtime/R85: the policy reader was not asked which judging files moved: $(grep 'ARGV: policy' "$STUB_LOG")"
land STUB_TOUCHED=3 9136 --lane
lane_held 9136 path "runtime/R85: a policy reader that fails closed on the diff"
land STUB_PR_FILES=.githooks/pre-push 9137 --lane
lane_held 9137 path "runtime/R85: a diff touching a path the lane policy's hold patterns select"
land STUB_PR_FILES='docs/a.md adapters/claude-code/hooks/root-guard.sh' 9138 --lane
lane_held 9138 path "runtime/R85: a hold pattern whose * crosses a directory"
land STUB_LANE=badpat STUB_PR_FILES=docs/a.md 9139 --lane
lane_held 9139 path "runtime/R85: a hold pattern out of shape holds every PR"
# A pattern is never a filename glob: a * the shell expanded against the
# working directory would read as no pattern at all.
_lp_here=$(pwd)
mkdir -p "$SCRATCH/globdir/adapters/claude-code" && : >"$SCRATCH/globdir/adapters/claude-code/x"
cd "$SCRATCH/globdir" && land STUB_PR_FILES=adapters/claude-code/hooks/root-guard.sh 9140 --lane
cd "$_lp_here"
lane_held 9140 path "runtime/R85: a hold pattern matched as a pattern, run from a directory it would glob"

# base-red: the latest run of any workflow on the base's head.
land STUB_BASE_RUNS='success failure' 9141 --lane
lane_held 9141 base-red "runtime/R86: a base branch whose latest workflow run failed"
grep -q "^ARGV: run list .*--commit b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0" "$STUB_LOG" &&
	pass "runtime/R86: the runs asked for are the base branch's head's" ||
	fail "runtime/R86: the run listing did not name the base's head: $(grep 'run list' "$STUB_LOG")"
land STUB_BASE_RUNS_RC=1 9142 --lane
lane_held 9142 base-red "runtime/R86: a forge that cannot list the base's runs"
_rj="$SCRATCH/lane-runs.json"
printf '%s\n' '[{"workflowName":"CI","status":"completed","conclusion":"failure","createdAt":"2026-01-01T00:00:00Z"},' \
	'{"workflowName":"CI","status":"completed","conclusion":"success","createdAt":"2026-01-02T00:00:00Z"},' \
	'{"workflowName":"Guards","status":"in_progress","conclusion":"","createdAt":"2026-01-02T00:00:00Z"}]' >"$_rj"
land STUB_RUNS_JSON="$_rj" 9143 --lane
lane_held 9143 base-red "runtime/R86: a workflow whose latest run has not finished"
printf '%s\n' '[{"workflowName":"CI","status":"completed","conclusion":"failure","createdAt":"2026-01-01T00:00:00Z"},' \
	'{"workflowName":"CI","status":"completed","conclusion":"success","createdAt":"2026-01-02T00:00:00Z"},' \
	'{"workflowName":"Guards","status":"completed","conclusion":"success","createdAt":"2026-01-01T00:00:00Z"}]' >"$_rj"
land STUB_RUNS_JSON="$_rj" 9144 --lane
expect_status 0 "runtime/R86: a workflow re-run green on the base's head: its latest run is what counts, and it lands"

# check-table: the reader, given the PR's body and the ticket's.
land STUB_BODY_FILE="$(body lane-skip "$(lane_table runtime/R1 suite skipped -)")" 9145 --lane
lane_held 9145 check-table "runtime/R87: a check table with a skipped row"
_lt2="$SCRATCH/lane-ticket2.md"
printf '%s\n' 'Covers: runtime/R1, runtime/R2' 'Test-tier: runtime/R1 suite' 'Test-tier: runtime/R2 suite' >"$_lt2"
land STUB_ISSUE_FILE="$_lt2" 9146 --lane
lane_held 9146 check-table "runtime/R87: a check table missing a covered requirement's row"
land STUB_TICKET= 9147 --lane
lane_held 9147 check-table "runtime/R87: no ticket, so no ticket body"
land STUB_ISSUE_RC=1 9148 --lane
lane_held 9148 check-table "runtime/R87: a ticket body the forge cannot give"
land STUB_ISSUE_FILE= 9149 --lane
lane_held 9149 check-table "runtime/R87: an empty ticket body"
land STUB_TICKET= STUB_FACTORY_TICKET="$LANE_TICKET" 9150 --lane --ticket T-07
expect_status 0 "runtime/R87: a factory ticket's body, read at the base, passes the table and lands"
grep -qx 'ARGV: git show refs/remotes/origin/main:.factory/items/T-07/ticket.md' "$STUB_LOG" &&
	pass "runtime/R87: a factory ticket's body is its file at origin's base" ||
	fail "runtime/R87: the factory ticket's file was not read at the base: $(grep 'git show' "$STUB_LOG")"

# verifier: the latest verify.verdict at the head, its reason named.
vverdict 9151 blocked 1
land 9151 --lane
lane_held 9151 verifier "runtime/R104: a blocked verdict with a disputed check-table row" disputed
vverdict 9152 blocked
land 9152 --lane
lane_held 9152 verifier "runtime/R104: a blocked verdict with no disputed row" blocked
vverdict 9153 unavailable
land 9153 --lane
lane_held 9153 verifier "runtime/R104: no verifier could be reached" unavailable
land 9159 --lane
lane_held 9159 verifier "runtime/R104: no verdict at all" none
for _vr in 9151:disputed 9152:blocked 9153:unavailable 9159:none; do
	show "pr:#${_vr%%:*}" --kind merge.land | grep -qF "\"reason\":\"${_vr#*:}\"" &&
		pass "runtime/R104: the ${_vr#*:} hold records its reason in data.reason" ||
		fail "runtime/R104: the ${_vr#*:} hold's event lacks data.reason: $(show "pr:#${_vr%%:*}" --kind merge.land)"
done
grep -q '^ARGV: risk' "$STUB_LOG" && fail "runtime/R82: a verifier hold still ran the risk rule" ||
	pass "runtime/R82: the verifier hold comes before the risk rule"

# The order: the earlier token wins where two apply.
land STUB_LANE=none STUB_DRIFT=land.kit.sh 9154 --lane
lane_held 9154 closed "runtime/R82: closed before drift"
land STUB_DRIFT=risk.sh STUB_PR_FILES=.githooks/pre-push 9155 --lane
lane_held 9155 drift "runtime/R82: drift before path"
land STUB_PR_FILES=.githooks/pre-push STUB_BASE_RUNS=failure 9156 --lane
lane_held 9156 path "runtime/R82: path before base-red"
land STUB_BASE_RUNS=failure STUB_ISSUE_FILE= 9157 --lane
lane_held 9157 base-red "runtime/R82: base-red before check-table"
land STUB_ISSUE_FILE= STUB_SWITCH=tripped STUB_EFFECTIVE='high unlearned' 9158 --lane
lane_held 9158 check-table "runtime/R82: check-table before switch"

# None applies: a PR touching nothing held, on a green base, with a passing
# table, a pass at the head and a low risk, lands (UC1).
land STUB_PR_FILES='docs/a.md scripts/feature.sh' STUB_LANE=nopat 9160 --lane
expect_status 0 "runtime/R82: a PR no hold applies to still lands through the lane"
lane_lines_closed "a lane landing past every hold"

# --- a second hold at the same head writes nothing ------------------------------
land STUB_SWITCH=tripped 9104 --lane
expect_status 4 "runtime/R91: the same hold again: exit 4"
[ "$(events 9104 merge.land)" = 1 ] && pass "runtime/R91: a second hold at the same head and token records nothing" ||
	fail "runtime/R91: a second hold at the same head recorded again: $(events 9104 merge.land) merge.land events"
land STUB_SWITCH=tripped STUB_HEAD_OID=feedface0123456789feedface0123456789feed 9104 --lane
expect_status 4 "runtime/R91: the same hold at a new head: exit 4"
[ "$(events 9104 merge.land)" = 2 ] && pass "runtime/R91: a hold at a new head is recorded once more" ||
	fail "runtime/R91: a hold at a new head: $(events 9104 merge.land) merge.land events, want 2"

# --- a merge the forge refuses -----------------------------------------------------
land STUB_MERGE_RC=1 9106 --lane
expect_status 1 "runtime/R89: a head the forge will not merge (it moved): exit 1, as today"
expect_out_lacks 'lane: landed' "runtime/R89: a refused merge prints no lane: landed"
show 'pr:#9106' --kind merge.land | grep -F '"outcome":"stopped"' | grep -qF '"via":"lane"' &&
	pass "runtime/R89: the refused merge records merge.land stopped, by the lane" ||
	fail "runtime/R89: no stopped merge.land by the lane: $(show 'pr:#9106' --kind merge.land)"
no_bait "a refused lane merge" 'pr:#9106'

# --- the override flags --------------------------------------------------------------
for _lo in "--no-iteration why" "--no-review why" "--unasked why" "--train"; do
	# shellcheck disable=SC2086 # the flag and its reason, split on purpose
	land 9120 --lane $_lo
	expect_status 2 "runtime/R81: --lane with ${_lo%% *}: exit 2"
	[ "$(merges)" = 0 ] && [ "$(show 'pr:#9120' | grep -c '"kind":"merge\.land\|"kind":"feedback\|"kind":"pr\.open' | tr -d ' ')" = 0 ] &&
		pass "runtime/R81: --lane with ${_lo%% *}: nothing merged, nothing recorded" ||
		fail "runtime/R81: --lane with ${_lo%% *} merged or recorded: $(show 'pr:#9120')"
	# shellcheck disable=SC2086
	land 9120 $_lo --lane
	expect_status 2 "runtime/R81: ${_lo%% *} before --lane: exit 2"
done

# --- every refusal still refuses ----------------------------------------------------
# lane_refused <knob> <PR> <label> — section 1's refusal, under --lane: exit 2,
# nothing merged, nothing recorded, and the lane never consulted.
lane_refused() {
	land "$1" "$2" --lane
	expect_status 2 "runtime/R80: $3, under --lane: refused with exit 2"
	[ "$(merges)" = 0 ] && ! grep -qE '^ARGV: (policy|risk)' "$STUB_LOG" &&
		pass "runtime/R80: $3, under --lane: no merge call, and the lane's checks never ran" ||
		fail "runtime/R80: $3, under --lane: merged, or the lane ran: $(cat "$STUB_LOG")"
	[ "$(show "pr:#$2" | grep -c '"kind":"merge\.land\|"kind":"feedback\|"kind":"pr\.open' | tr -d ' ')" = 0 ] &&
		pass "runtime/R80: $3, under --lane: nothing reached the trace" ||
		fail "runtime/R80: $3, under --lane: an event was recorded: $(show "pr:#$2")"
	expect_out_lacks 'lane:' "runtime/R80: $3, under --lane: no lane line"
}
lane_refused STUB_CHECKS_RC=1 9121 "a red check"
lane_refused STUB_MERGEABLE=CONFLICTING 9121 "a conflicting PR"
lane_refused STUB_DRAFT=true 9121 "a draft"
lane_refused STUB_REVIEW=CHANGES_REQUESTED 9121 "a human's changes requested"
lane_refused STUB_MSS=BEHIND 9121 "a PR behind its base"
lane_refused STUB_PRSTATE=MERGED 9121 "a PR already merged"
lane_refused STUB_CHECKS_RC=8 9121 "pending checks"
lane_refused STUB_VIEW_RC=1 9121 "a forge that does not answer for the PR"
lane_refused STUB_HEAD_RC=1 9122 "a head the forge does not name"
lane_refused STUB_PR_FILES=UPDATING.md 9123 "a shared-layer move with no version bump"
lane_refused STUB_PR_FETCH_RC=1 9123 "a PR head that cannot be fetched"
lane_refused STUB_PRSTATE=OPEN 9125 "no /pr-iterate iteration and no review at the head"
seed pr.iterate stopped 9126
lane_refused STUB_PRSTATE=OPEN 9126 "no review at the head"
LAND=$_land_kit

# --- the lane policy: shipped empty, a kit twin, both judging files --------------
# Both are named `<name>.config.sh` directly under scripts/, the policy
# reader's judging set (ADR-0039): read at the base, never the PR's tree.
for _lp in lane.config.sh lane.kit.config.sh; do
	_lp_op=$(sh -c 'unset LANE_OPERATOR; . "$1" >/dev/null 2>&1 </dev/null; printf "%s" "${LANE_OPERATOR-unset}"' _ "$KIT/scripts/$_lp")
	[ -z "$_lp_op" ] && pass "runtime/R83: scripts/$_lp names no operator, so its lane is closed" ||
		fail "runtime/R83: scripts/$_lp names an operator ('$_lp_op') — the lane opens only on the operator's own landing"
done
grep -q '^KIT_ONLY=.* scripts/lane\.kit\.config\.sh[ "]' "$KIT/bootstrap.sh" &&
	pass "runtime/R83: bootstrap strips the kit's lane twin, so a consumer gets only the empty lane policy" ||
	fail "runtime/R83: scripts/lane.kit.config.sh is not on bootstrap's KIT_ONLY list"
grep -q 'policy\.sh read scripts/lane\.kit\.config\.sh --base' "$KIT/scripts/land.kit.sh" &&
	pass "runtime/R83: the landing script reads the kit's twin, at a base, through the policy reader" ||
	fail "runtime/R83: the landing script does not read scripts/lane.kit.config.sh through the policy reader at a base"


# ---------------------------------------------------------------------------
banner "25. /pr-iterate's lane step runs the landing command on a green, low-risk head (PRD-10 slice 2, #916)"
# ---------------------------------------------------------------------------
# The lane is reachable end to end only through /pr-iterate: its step 6 runs
# the command the lane policy names, with --lane, once the iteration recorded
# green and the risk rule printed `effective: low` at that head.
PI="$KIT/.agents/skills/pr-iterate/SKILL.md"
PL="$KIT/.agents/skills/pr-iterate/LANE.md"
PIR="$KIT/.agents/skills/pr-iterate/RISK.md"
[ -f "$PL" ] && pass "process/R80: /pr-iterate carries the lane step's branch file" || fail "process/R80: no .agents/skills/pr-iterate/LANE.md"
pl_flat=$(tr '\n' ' ' <"$PL" 2>/dev/null | tr -s ' ')
pi_flat=$(tr '\n' ' ' <"$PI" | tr -s ' ')
t_text_has "$pi_flat" 'A `green` iteration opens [`LANE.md`](LANE.md) before the run closes' "process/R80: step 6 opens the lane step after the green record, before the run ends"
_pl_green=$(t_line_of "$PI" 'kind=pr.iterate subject=pr:#<N> outcome=green|red|stopped data.iteration=<i> data.applied')
_pl_open=$(t_line_of "$PI" 'A `green` iteration opens [`LANE.md`](LANE.md)')
[ -n "$_pl_green" ] && [ -n "$_pl_open" ] && [ "$_pl_open" -ge "$_pl_green" ] &&
	pass "process/R80: the lane step comes after the iteration's record" || fail "process/R80: the lane step (line $_pl_open) precedes the iteration's record (line $_pl_green)"
# R80: its three conditions, the invocation, and the three answers it reports.
t_text_has "$pl_flat" 'this iteration recorded `pr.iterate outcome=green`' "process/R80: condition one, the iteration recorded green"
t_text_has "$pl_flat" 'the risk rule exited 0 at this head and its first line is `effective: low`' "process/R80: condition two, effective low at that head"
t_text_has "$pl_flat" 'the lane policy names a landing command' "process/R80: condition three, a landing command named"
t_text_has "$pl_flat" 'lane_out=$($lane_cmd <N> --lane --ticket <T> 2>&1); lane_rc=$?' "process/R80: the command runs with --lane, the PR and its ticket, its status kept"
for _pl_ans in '`lane: landed`' '`lane: held <token>`' 'Lane: refused, exit <lane_rc>'; do
	t_text_has "$pl_flat" "$_pl_ans" "process/R80: the step reports what the command printed"
done
# R81: no command, nothing run, today's report.
t_text_has "$pl_flat" 'An empty command — every consumer'"'"'s, as shipped — runs nothing, and the report is today'"'"'s' "process/R81: no landing command named runs none"
# R82: the landing's report lists the decision-log ids, for after the fact.
t_text_has "$pl_flat" 'Lane: Landed by the lane — decision log to read after the fact: <lane_ids, or none>' "process/R82: a lane landing's report lists the PR's decision-log ids"
t_text_has "$pi_flat" 'Lane: <LANE.md'"'"'s line; omitted when the step ran nothing>' "process/R82: the report format carries the lane line"
# R85: never the train, one landing per iteration.
t_text_has "$pl_flat" 'The step never starts `/merge-train`, and runs one landing per iteration, for this PR alone' "process/R85: never the train, one landing per run"
for _pl_f in "$PI" "$PL"; do
	grep -qE 'gh pr merge|merge-train <|/merge-train [0-9<]' "$_pl_f" &&
		fail "process/R85: $(basename "$_pl_f") merges or starts a train itself" || pass "process/R85: $(basename "$_pl_f") merges nothing and starts no train"
done
# Hard rule 2 gains the lane exception, citing its record.
grep -n '^2\. \*\*NEVER\*\* merge the PR' "$PI" | grep -qF 'ADR-0047' && grep '^2\. \*\*NEVER\*\* merge the PR' "$PI" | grep -qF '[`LANE.md`](LANE.md)' &&
	pass "process/R80: hard rule 2 names the lane exception and its decision record" || fail "process/R80: hard rule 2 carries no lane exception citing ADR-0047"

# The step's own fence, run: the command read at the base, the decision-log ids.
_pl_fence=$(t_fence "$PL" holds 'lane_command()')
[ -n "$_pl_fence" ] && pass "LANE.md's fence defines lane_command and lane_dl_ids" || fail "LANE.md has no fence defining lane_command()"
t_repo
PLR=$REPO
# The fence runs on the real git: this suite's stub git answers the landing's questions.
PL_PATH=${PATH#"$STUBDIR:"}
mkdir -p "$PLR/scripts"
cp "$KIT/scripts/policy.sh" "$KIT/scripts/requirement.lib.sh" "$PLR/scripts/"
# pl_cmd <LANE_LAND_COMMAND line, or nothing> [<policy path>] — the command the
# fence reads from that policy committed on main, as /pr-iterate reads it.
pl_cmd() {
	t_write "$PLR" "${2:-scripts/lane.config.sh}" "LANE_OPERATOR=''
$1
"
	t_commit "$PLR" "chore: lane policy" >/dev/null
	(PATH=$PL_PATH && cd "$PLR" && eval "$_pl_fence" && lane_command main ${2:+"$2"})
}
[ "$(pl_cmd "LANE_LAND_COMMAND=''")" = '' ] && pass "process/R81: an empty landing command reads as none" || fail "process/R81: an empty command read as '$(pl_cmd "LANE_LAND_COMMAND=''")'"
[ "$(pl_cmd '')" = '' ] && pass "process/R81: a policy with no landing-command key reads as none" || fail "process/R81: a missing key read as a command"
[ "$(pl_cmd "LANE_LAND_COMMAND='sh scripts/land.kit.sh'")" = 'sh scripts/land.kit.sh' ] && pass "process/R80: a plain command reads back word for word" || fail "process/R80: a plain command read as '$(pl_cmd "LANE_LAND_COMMAND='sh scripts/land.kit.sh'")'"
for _pl_bad in "LANE_LAND_COMMAND='sh land.sh; BAIT'" "LANE_LAND_COMMAND='sh \$(BAIT)'" "LANE_LAND_COMMAND='sh  land.sh'" "LANE_LAND_COMMAND='sh land.sh
BAIT'"; do
	[ "$(pl_cmd "$_pl_bad")" = '' ] && pass "process/R81: a command out of the plain-word shape reads as none" || fail "process/R81: '$_pl_bad' read as '$(pl_cmd "$_pl_bad")'"
done
[ "$(PATH=$PL_PATH && cd "$PLR" && eval "$_pl_fence" && lane_command no-such-base)" = '' ] && pass "process/R81: a policy the reader cannot read at the base reads as none" || fail "process/R81: an unreadable base read as a command"
[ "$(pl_cmd "LANE_LAND_COMMAND='sh scripts/land.kit.sh'" scripts/lane.kit.config.sh)" = 'sh scripts/land.kit.sh' ] && pass "process/R80: the twin the root manual names is read in its place" || fail "process/R80: lane_command reads no named twin"
_pl_body="intro
<!-- decision-log -->
| Decision | Surface | What was decided | Why |
| --- | --- | --- | --- |
| D-1 | a | kept | x |
| ~~D-2~~ | ~~b~~ | ~~struck~~ | ~~y~~ |
| D-3 | c | amended | z |

\`\`\`text
<!-- decision-log -->
| D-9 | quoted | in a fence | no |
\`\`\`
<!-- explain-diff-appendix -->"
_pl_ids=$(PATH=$PL_PATH && cd "$PLR" && eval "$_pl_fence" && printf '%s\n' "$_pl_body" | lane_dl_ids)
[ "$_pl_ids" = 'D-1 D-3' ] && pass "process/R82: the ids read are every unstruck row's, a fenced log left out" || fail "process/R82: lane_dl_ids read '$_pl_ids'"
_pl_none=$(PATH=$PL_PATH && cd "$PLR" && eval "$_pl_fence" && printf 'no log here\n' | lane_dl_ids)
[ "$_pl_none" = '' ] && pass "process/R82: a body with no log reads no id" || fail "process/R82: a log-less body read '$_pl_none'"

# The policy: shipped with no landing command, the kit's naming the landing script.
_pl_shipped=$(sh -c 'unset LANE_LAND_COMMAND; . "$1" >/dev/null 2>&1 </dev/null; printf "%s" "${LANE_LAND_COMMAND-unset}"' _ "$KIT/scripts/lane.config.sh")
[ -z "$_pl_shipped" ] && pass "process/R81: the shipped lane policy carries the key and names no landing command" || fail "process/R81: scripts/lane.config.sh's LANE_LAND_COMMAND is '$_pl_shipped'"
_pl_kit=$(sh -c 'unset LANE_LAND_COMMAND; . "$1" >/dev/null 2>&1 </dev/null; printf "%s" "${LANE_LAND_COMMAND-unset}"' _ "$KIT/scripts/lane.kit.config.sh")
[ "$_pl_kit" = 'sh scripts/land.kit.sh' ] && pass "process/R80: the kit's lane policy names the landing script" || fail "process/R80: scripts/lane.kit.config.sh's LANE_LAND_COMMAND is '$_pl_kit'"
grep -q '^# LANE_LAND_COMMAND .*--lane' "$KIT/scripts/lane.kit.config.sh" && pass "process/R80: the kit's policy says /pr-iterate runs it with --lane" || fail "process/R80: the kit's policy never says the command runs with --lane"
sed -n '/^10\. \*\*In THIS repo/,/^## /p' "$KIT/AGENTS.md" | grep -qF 'scripts/lane.kit.config.sh' &&
	pass "process/R80: hard rule 10 sends /pr-iterate's lane step to the kit's twin" || fail "process/R80: hard rule 10 never names scripts/lane.kit.config.sh"

t_done "land one PR by hand"
