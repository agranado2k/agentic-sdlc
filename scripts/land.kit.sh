#!/bin/sh
# land.kit.sh — land ONE green PR by hand, and record it the way the train does.
# Kit-authoring only, never shipped (bootstrap.sh's KIT_ONLY list deletes it,
# with tests/land.test.sh).
#
#   sh scripts/land.kit.sh <PR#> [--ticket <N|T-NN>] [--unasked '<reason>'] [--no-iteration '<reason>'] [--no-review '<reason>'] [--train]
#   sh scripts/land.kit.sh <PR#> --lane [--ticket <N|T-NN>]
#
# WHY THIS EXISTS. /merge-train records every landing it makes — a merge.land
# with the merge sha, then the operator's verdict as a feedback event — and
# /retro reads the pair. A PR merged by hand outside a train recorded neither:
# three retros running found a quarter to a third of the landings missing from
# the trace (retro G2, #386). This is the train's step 4 for one PR, so the
# merge keeps a human's name — the operator runs it, no agent does (shared
# invariant §7) — and the trace keeps the record.
#
# WHAT IT DOES, in order:
#   1. Reads the PR and REFUSES, exit 2 with nothing merged and nothing
#      emitted, unless it is open, not a draft, mergeable, CLEAN against its
#      base, carries no human "changes requested", and every check is green.
#      A PR behind its base is refused too: the train's update-branch step
#      is the train's to take.
#   1b. REFUSES the same way a PR with no /pr-iterate iteration at its head
#      commit: no pr.iterate event on pr:#<N> in the trace stamped at or
#      after the head commit's committed date (#630, ADR-0019). The operator
#      overrides it with --no-iteration '<reason>', and merge.land records
#      data.iterated=no with the reason as data.no_iteration; with one at
#      head, data.iterated=yes. The same for the review (#673): no Axis-1
#      review.verdict on pr:#<N>, any outcome but blocked (#816, ADR-0032),
#      at or after the head commit's date refuses it, unless --no-review
#      '<reason>' names why — data.reviewed=no with data.no_review, or
#      data.reviewed=yes. One refusal names every check that failed. A
#      prose-only PR nobody iterated or reviewed — a diary stamp — lands on
#      both overrides, each with its reason. The verifier is read beside
#      them and never checked: merge.land carries data.verified, the
#      outcome of the latest verify.verdict on pr:#<N> at or after the head
#      commit's date, or none; no outcome of it refuses, waits or merges
#      (runtime/R214, R215, ADR-0044). Unconfigured, the trace holds
#      nothing to read and records nothing: both checks are skipped, and
#      stderr says so.
#   1c. REFUSES the same way a PR that moves a file VERSION's files: list
#      names — at its merge base or its head — with no new version on the
#      shared-layer line (#728, ADR-0025): a shared-layer change is a release
#      (hard rule 3). The diff is the PR's own, read with git from its merge
#      base; one that cannot be read refuses too. No override.
#   1d. Writes pr.open on pr:#<N> (data.via=land, related to the ticket and
#      the head branch) when the trace holds none for it: a PR opened outside
#      /implement still joins its ticket for /retro (#638).
#   1e. Marks merge.land data.ticket_start=no when the trace holds no
#      ticket.start on the landed ticket (#775): /retro then tells a ticket
#      nobody started from one the trace lost. Never a refusal.
#   2. Merges with the merge-commit method (`gh pr merge <N> --merge`) — the
#      one /merge-train's hard rule 3 reads from the local workflow article
#      (in this repo, the root AGENTS.md). A merge the forge rejects
#      records merge.land `stopped` and exits 1; no verdict is asked.
#   2b. When the merge moves VERSION's shared-layer line it is a release:
#      tags the merge commit v<version> (`git tag -a`, the operator's own
#      signing config) and pushes the tag BEFORE waiting — a release is not
#      landed until that tag exists (hard rule 3), and the kit's CI holds
#      main red until it does (ADR-0015, #509). A tag origin already holds
#      on the merge commit is kept; one naming any other commit is never
#      moved, and the release is reported not landed.
#   3. Waits for the base branch's workflows on the merge commit, each one
#      watched to its end. For a tagged release, each run that failed —
#      started on the merge push, before the tag could exist — is re-run
#      once (`gh run rerun <id> --failed`) and only its second result is
#      judged. A re-run refused because the run is already running is no
#      verdict: that run is watched to its end and judged (#661); any other
#      refusal is a failure. An untagged merge's red is never re-run.
#      A job whose record stays "in progress" after it ended is re-run once,
#      by its job id, and named on stderr; the same job stuck again is a stop,
#      judged as a red check is (#850). Records it cannot read leave for the
#      forge's watch, bounded by the wait: a watch that outlives it stops
#      the wait, data.workflows=unknown, exit 1.
#   4. Emits merge.land (`landed`, the sha, the method, the wait, the
#      workflows' result) on pr:#<N>, related to the ticket — and whether
#      /implement opened the PR (data.implement=yes|no, with
#      data.implement_tier when yes — a key of its own, never the event's
#      top-level tier), read from the one line /implement writes in the PR
#      body (#480).
#   5. Asks the verdict question when stdin is a terminal and emits feedback
#      `hit|adjusted|missed`; with no terminal, or --unasked, it emits
#      `unasked` with the reason — never a verdict nobody gave.
#   6. Fast-forwards the root checkout — the main worktree of this repo, or
#      LAND_ROOT_CHECKOUT — to origin's base when it is on that branch, with
#      no tracked change uncommitted, and not diverged, and says so on stderr; a dirty, off-base, detached
#      or diverged root is left untouched and named (#636). No event, no
#      exit status: the landing is what the record is about.
#   With --train, /merge-train is the caller (#662): it ran its own ordering
#   and update-branch steps and lands each PR here, so a train meets the same
#   gate and writes merge.land through the same emitter. merge.land is marked
#   data.via=train, and step 5 is skipped: the train asks the verdict after
#   the merge and records who answered (data.by), which this run cannot.
#   --train with --unasked is a usage error — the train records the verdict.
#   With --lane, /pr-iterate is the caller and no operator is at it: the
#   LOW-RISK LANE (ADR-0047, PRD-10). Every refusal above is made first, with
#   the same exit and effect (runtime/R80); --lane with --no-iteration,
#   --no-review, --unasked or --train is a usage error, exit 2, nothing merged
#   or recorded (runtime/R81). Then the lane's own checks, between steps 1c and
#   1d, the first that applies HOLDING the PR: `closed` when the lane policy
#   (scripts/lane.kit.config.sh, read at origin's base through the policy
#   reader, scripts/policy.sh) names no operator or cannot be read
#   (runtime/R83); then the risk rule (scripts/risk.sh) at the PR's head with
#   the PR and its ticket, of whose lines only `effective:` and `switch:` are
#   read: `switch` when it prints `switch: tripped`, `risk` on any effective
#   risk but `low` — a missing line too (runtime/R88). Between `closed` and
#   `switch`, in runtime/R82's order: `drift` when this checkout's landing
#   script or risk rule differs from the base's (runtime/R84); `path` when the
#   PR's diff touches a file VERSION's files: list names at either end, a
#   judging file the policy reader names, or a path the lane policy's
#   LANE_HOLD_PATTERNS select (runtime/R85); `base-red` when the latest run of
#   any workflow on the base's head commit is not a success (runtime/R86);
#   `check-table` when scripts/check-table.sh, given the PR's body and the
#   ticket's, exits anything but 0, or there is no ticket body (runtime/R87);
#   `verifier <reason>` when the latest verify.verdict at the head is not a
#   pass — `disputed`, `blocked`, `unavailable` or `none` (runtime/R104). A
#   hold prints `lane: held <token>`, merges nothing, exits 4 and records one
#   merge.land `skipped` with data.via=lane, data.hold, data.head and the
#   verifier's data.reason — none when the trace holds that PR, head and token
#   already (runtime/R91). Past every check the
#   merge pins the head the rule judged (`--match-head-commit`), so a head that
#   moved is the forge's refusal, exit 1 as today (runtime/R89); merge.land
#   carries data.via=lane and data.decisions, the decision-log ids in the PR
#   body, the feedback is `unasked` with data.by=lane, and the last line is
#   `lane: landed` (runtime/R90). What the lane prints and records is closed
#   tokens, numbers, shas and digits only: no title, branch or reason text, and
#   the forge's own chatter goes nowhere (runtime/R102).
#   A failed post-merge workflow still records both events — the PR did land —
#   and then exits 1: escalate, as the train's hard rule 6 says. So does a
#   merge commit the forge never names (data.workflows=unknown, no sha), and
#   one no run appeared for within the wait while the base branch's workflows
#   declare a push trigger, or could not be read (data.workflows=unknown,
#   #688: exit 1, never 2, so a train stops; `none` is only a base whose
#   workflows declare no push trigger), and
#   so does a release whose tag is not on origin: merged, not landed. A
#   release's merge.land carries data.release, data.tagged and data.reruns.
#
# THE TICKET is the PR's first closing reference, or --ticket — an issue
# number, or a canonical factory ticket id (T-07) — or, with neither, the
# factory ticket id its /implement landing line names (PRD-15, runtime/R243).
# An issue's events take ticket:#<N>, a factory ticket's ticket:T-<digits>.
# With no ticket at all, the feedback sits on the PR itself. A factory
# ticket's own close is the factory's: this script runs no `factory`
# subcommand and writes nothing under .factory/ (runtime/R245).
#
# THE TRACE's emits are never load-bearing (ADR-0008 clause 4): unconfigured,
# the merge and stdout are exactly what a traced run does. Its one read is
# step 1b's, and that read IS load-bearing when the trace is configured: no
# pr.iterate or no review.verdict at the head refuses the landing
# (ADR-0019). Kit-only, so the kit's own policy is the default seam —
# scripts/trace.sh read through scripts/trace.kit.config.sh, what
# scripts/trace.kit.sh runs; a caller's TRACE_CONFIG still wins (the broker's
# arrangement).
#
# exit: 0 landed · 1 merge rejected, a post-merge workflow failed, no merge commit named, or a release left untagged · 2 usage, or the PR refused · 4 the lane held it · 69 no forge CLI
#
# tests/land.test.sh drives this file against a stub `gh` on PATH, and a stub
# `git` that answers the release questions and passes everything else through.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)

# How long step 3 looks for the merge commit's runs to appear: the forge
# registers them a moment after the merge. The suite sets the wait to 0.
POLL_TRIES=${LAND_POLL_TRIES:-12}
POLL_SECONDS=${LAND_POLL_SECONDS:-10}

usage() {
	cat >&2 <<'EOF'
usage: sh scripts/land.kit.sh <PR#> [--ticket <N|T-NN>] [--unasked '<reason>'] [--no-iteration '<reason>'] [--no-review '<reason>'] [--train]
       sh scripts/land.kit.sh <PR#> --lane [--ticket <N|T-NN>]
  <PR#>       the pull request to land — green, mergeable, clean against its base
  --ticket    the ticket the PR implemented, when the PR closes none: an issue number or a factory ticket id (T-07)
  --unasked   record the verdict as unasked, with this reason (the operator is not at the prompt)
  --no-iteration  land with no /pr-iterate iteration at the head commit, for this reason (recorded)
  --no-review     land with no /review-pr verdict at the head commit, for this reason (recorded)
  --train     /merge-train is landing it: merge.land says via=train, and the verdict is left to the train
  --lane      the low-risk lane, /pr-iterate's: land it only when the lane is open and its risk low, else hold it; takes none of the flags above but --ticket
exit: 0 landed · 1 merge rejected, a post-merge workflow failed, no merge commit named, or a release left untagged · 2 usage, or the PR refused · 4 the lane held it · 69 no forge CLI
EOF
	exit 2
}
note() { echo "land: $1" >&2; }
# factory_id <handle> — 0 when <handle> is a canonical factory ticket id: T-,
# then 2 to 6 digits, a leading zero only in the two-digit form — the one
# spelling the trace takes as ticket:T-<digits> (the kit's ADR-0040).
factory_id() {
	case $1 in
	T-[0-9][0-9]) return 0 ;;
	T-0* | T-*[!0-9]* | T-???????*) return 1 ;;
	T-??*) return 0 ;;
	esac
	return 1
}
refuse() {
	note "refusing PR #$PR: $1 — nothing merged, nothing recorded"
	exit 2
}

PR=
TICKET=
UNASKED=
NO_ITERATION=
NO_REVIEW=
VIA=land
LANE=
TRAIN=
while [ $# -gt 0 ]; do
	case $1 in
	--ticket)
		[ $# -ge 2 ] || usage
		TICKET=$2
		shift
		;;
	--unasked)
		[ $# -ge 2 ] && [ -n "$2" ] || usage
		UNASKED=$2
		shift
		;;
	--no-iteration | --no-review)
		# One printable line: the trace refuses a control character, and a
		# reason it refused after the merge would leave the landing unrecorded.
		[ $# -ge 2 ] && [ -n "$2" ] || usage
		case $2 in *[![:print:]]*) note "$1 takes a one-line reason"; usage ;; esac
		if [ "$1" = --no-review ]; then NO_REVIEW=$2; else NO_ITERATION=$2; fi
		shift
		;;
	--train) TRAIN=1 VIA=train ;;
	--lane) LANE=1 ;;
	-h | --help) usage ;;
	-*) note "unknown option '$1'"; usage ;;
	*) [ -z "$PR" ] || usage; PR=$1 ;;
	esac
	shift
done
case $PR in '' | *[!0-9]*) [ -z "$PR" ] || note "'$PR' is not a pull request number"; usage ;; esac
[ "$VIA" = land ] || [ -z "$UNASKED" ] || { note "--train leaves the verdict to the train; drop --unasked"; usage; }
# The lane takes no override: each one is an operator's call, and no operator
# is at a lane run (runtime/R81).
if [ -n "$LANE" ]; then
	[ -z "$NO_ITERATION$NO_REVIEW$UNASKED$TRAIN" ] || { note "--lane takes no --no-iteration, --no-review, --unasked or --train"; usage; }
	VIA=lane
fi
case $TICKET in *[!0-9]*) factory_id "$TICKET" || { note "--ticket '$TICKET' is neither a ticket number nor a factory ticket id (T-07)"; usage; } ;; esac
command -v gh >/dev/null 2>&1 || { note "no forge CLI (gh) on PATH"; exit 69; }
# Descriptor 3 carries the forge's own chatter — a merge naming the PR's title,
# a watch naming its jobs: stderr for the operator, nowhere in the lane, whose
# caller reads only what runtime/R102 allows.
if [ -n "$LANE" ]; then exec 3>/dev/null; else exec 3>&2; fi

# trace loud|quiet <field>=<value> … — `quiet` silences the unconfigured
# note, so an unconfigured run says it once. The switch rides the external
# command, never a prefix on this function (forge-broker.kit.sh says why).
TRACE_POLICY=${TRACE_CONFIG:-$ROOT/scripts/trace.kit.config.sh}
trace() {
	_tr_quiet=
	[ "$1" = quiet ] && _tr_quiet=1
	shift
	TRACE_QUIET="${_tr_quiet:-${TRACE_QUIET:-}}" TRACE_CONFIG="$TRACE_POLICY" \
		sh "$ROOT/scripts/trace.sh" emit "$@" </dev/null || :
}
# trace_read <subcommand> … — a read through the same policy, quiet.
trace_read() {
	TRACE_QUIET=1 TRACE_CONFIG="$TRACE_POLICY" \
		sh "$ROOT/scripts/trace.sh" "$@" </dev/null 2>/dev/null
}

# --- 1. the gate: green and mergeable, or nothing happens ---------------------
# One `name=value` line per field, every value folded onto one line, and each
# read back by its name (#684): reordering the query, or a forge answering the
# fields in another order, never shifts one field into another.
STATE=$(gh pr view "$PR" --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,baseRefName,closingIssuesReferences,headRefName,title \
	--jq '{state, isDraft, mergeable, mergeStateStatus, reviewDecision: (.reviewDecision // ""), baseRefName,
		ticket: ((.closingIssuesReferences // []) | map(.number|tostring) | first // ""), headRefName: (.headRefName // ""), title}
		| to_entries[] | "\(.key)=\(.value | tostring | gsub("[\r\n]"; " "))"') ||
	refuse "the forge did not answer for it"
# named <answer> <name> — the value of the one line named <name>, or nothing.
named() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -n 1; }
field() { named "$STATE" "$1"; }
[ "$(field state)" = OPEN ] || refuse "it is $(field state), not open"
[ "$(field isDraft)" = false ] || refuse "it is a draft"
[ "$(field reviewDecision)" != CHANGES_REQUESTED ] || refuse "a human review requests changes"
[ "$(field mergeable)" = MERGEABLE ] || refuse "it is not mergeable ($(field mergeable)) — send it to /pr-iterate"
case $(field mergeStateStatus) in
CLEAN | HAS_HOOKS) ;;
BEHIND) refuse "it is behind its base — a train updates it through the forge first" ;;
*) refuse "its merge state is $(field mergeStateStatus), not clean" ;;
esac
gh pr checks "$PR" >/dev/null 2>&1
case $? in
0) ;;
8) refuse "its checks are still pending — not green yet" ;;
*) refuse "its checks are not green" ;;
esac

# --- 1b. an iteration and a review at the head commit (#630, #673, ADR-0019) ---
# /pr-iterate records one pr.iterate per iteration, after its own push, and
# /review-pr one review.verdict per axis — and /pr-iterate runs a review each
# iteration — so a loop or a review that saw the head commit is stamped at or
# after that commit's date. Each such stamp on pr:#<N> is compared with the
# head's date, both ISO 8601 in UTC, as strings. An iteration counts on any
# outcome: whether the checks are green is the gate above's question. A
# review counts as an Axis-1 verdict on any outcome but blocked (#816,
# ADR-0032): a review in which no lens ran records exactly that, and what a
# blocked verdict found is no audit a landing can stand on. An Axis-2 verdict
# alone is no standards review. A head the forge does not date is neither
# at it.
ITERATED=
REVIEWED=
REVIEWED_BLOCKED=
VERIFIED=
VERIFIED_DISPUTED=
# at_head <kind> [<key>] — print "<outcome> <value>" for each <kind> event on
# pr:#<PR> stamped at or after $HEAD_AT, the value its data map's <key> (axis
# unless named); exit 1 when there is none. The subject, stamp and outcome are
# read from the envelope only — up to the data map, as `show` prints it — so a
# data key never reads as one of them; the value from the data map.
at_head() {
	trace_read show "pr:#$PR" --kind "$1" |
		awk -v s="\"subject\":\"pr:#$PR\"" -v h="$HEAD_AT" -v k="${2:-axis}" '
			{ e = $0; m = ""; d = index(e, ",\"data\":{"); if (d) { m = substr(e, d); e = substr(e, 1, d - 1) } }
			index(e, s) && match(e, /"ts":"[^"]*"/) && substr(e, RSTART + 6, RLENGTH - 7) >= h {
				o = match(e, /"outcome":"[^"]*"/) ? substr(e, RSTART + 11, RLENGTH - 12) : "-"
				a = match(m, "\"" k "\":\"[^\"]*\"") ? substr(m, RSTART + length(k) + 4, RLENGTH - length(k) - 5) : "-"
				print o, a; f = 1
			}
			END { exit !f }'
}
# The head commit and its date: the trace checks here and the shared-layer
# check below (#728) read the same one.
HEAD=$(gh pr view "$PR" --json headRefOid,commits --jq '.headRefOid as $h
	| {oid: $h, committedDate: ((.commits // []) | map(select(.oid == $h)) | last | .committedDate // "")}
	| to_entries[] | "\(.key)=\(.value | tostring | gsub("[\r\n]"; " "))"' 2>/dev/null) || HEAD=
HEAD_OID=$(named "$HEAD" oid)
HEAD_AT=$(named "$HEAD" committedDate)
case $HEAD_OID in '' | *[!0-9a-f]*) HEAD_OID='<unnamed>' ;; esac
if [ -z "$(trace_read dir)" ]; then
	note "the trace is unconfigured — whether /pr-iterate ran and /review-pr recorded a verdict at the head of PR #$PR is not checked"
else
	ITERATED=no
	REVIEWED=no
	VERIFIED=none
	case $HEAD_AT in
	[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z)
		! at_head pr.iterate >/dev/null || ITERATED=yes
		_verdicts=$(at_head review.verdict) || _verdicts=
		! printf '%s\n' "$_verdicts" | awk '$2 == "1" && $1 != "blocked" { f = 1 } END { exit !f }' || REVIEWED=yes
		! printf '%s\n' "$_verdicts" | grep -qx 'blocked 1' || REVIEWED_BLOCKED=yes
		# What the verifier said at the head: the latest verify.verdict's
		# outcome, read and recorded, never checked (runtime/R214, R215).
		# Its disputed pins ride along, for the lane's verifier hold alone
		# (runtime/R104).
		_vline=$(at_head verify.verdict disputed | tail -n 1)
		VERIFIED=${_vline%% *}
		VERIFIED_DISPUTED=${_vline#* }
		case $VERIFIED in pass | blocked | unavailable) ;; *) VERIFIED=none ;; esac
		;;
	*) HEAD_AT='<undated>' ;;
	esac
	# One refusal names every check that failed, so an operator learns both
	# overrides from one run.
	_missing=
	_no_verdict='no /review-pr Axis-1 verdict'
	[ -z "$REVIEWED_BLOCKED" ] || _no_verdict='only a blocked /review-pr Axis-1 verdict, which is no review'
	[ "$ITERATED" = yes ] || [ -n "$NO_ITERATION" ] ||
		_missing="no /pr-iterate iteration — run /pr-iterate $PR, or land it with --no-iteration '<reason>'"
	[ "$REVIEWED" = yes ] || [ -n "$NO_REVIEW" ] ||
		_missing="${_missing:+$_missing; }$_no_verdict — run /review-pr on it, or land it with --no-review '<reason>'"
	[ -z "$_missing" ] || refuse "at its head commit $HEAD_OID ($HEAD_AT) the trace records $_missing"
	[ "$ITERATED" = yes ] || note "no /pr-iterate iteration at the head commit $HEAD_OID — landing on --no-iteration, recorded"
	[ "$REVIEWED" = yes ] || note "no /review-pr verdict at the head commit $HEAD_OID — landing on --no-review, recorded"
fi

BASE=$(field baseRefName)

# --- 1c. the shared layer moves only with a version bump (#728, ADR-0025) ------
# A PR that moves a file VERSION's files: list names is a release (hard rule
# 3): it lands only with VERSION's shared-layer line moved to a new version.
# The diff is the PR's own, from its merge base with the base branch to its
# head, as the forge's diff is; the list is read at both ends, so a file
# joining or leaving the manifest counts. A diff that cannot be read refuses:
# this check cannot vouch for what it did not see. No override.
. "$ROOT/scripts/manifest.lib.sh"
# layer_version <VERSION text> — the shared-layer value, only when it is a
# version: anything else is no release and is never typed into a tag.
layer_version() {
	printf '%s\n' "$1" | sed -n 's/^shared-layer: *\([0-9]\{1,6\}\.[0-9]\{1,6\}\.[0-9]\{1,6\}\) *$/\1/p' | head -1
}
# bumped <VERSION before> <VERSION after> — print the new version and exit 0
# when the shared-layer line moved to a version; a line that moved to no
# version, or did not move, is no bump. Step 2b's release is the same question.
bumped() {
	_bp_v=$(layer_version "$2")
	[ -n "$_bp_v" ] && [ "$_bp_v" != "$(layer_version "$1")" ] && printf '%s\n' "$_bp_v"
}
_sl_unread="its diff could not be read to check the shared layer"
[ "$HEAD_OID" != '<unnamed>' ] || refuse "the forge did not name its head commit, so $_sl_unread"
git -C "$ROOT" fetch -q origin "$BASE" "refs/pull/$PR/head" >/dev/null 2>&1 ||
	refuse "fetching origin $BASE and the PR's head failed, so $_sl_unread"
_sl_mb=$(git -C "$ROOT" merge-base "refs/remotes/origin/$BASE" "$HEAD_OID" 2>/dev/null) && [ -n "$_sl_mb" ] ||
	refuse "its head $HEAD_OID has no merge base with origin/$BASE here, so $_sl_unread"
# quotePath off: a listed path git would print quoted must still match.
_sl_moved=$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false git -C "$ROOT" diff --name-only --no-renames "$_sl_mb" "$HEAD_OID" 2>/dev/null) ||
	refuse "git could not diff $_sl_mb..$HEAD_OID, so $_sl_unread"
_sl_before=$(git -C "$ROOT" show "$_sl_mb:VERSION" 2>/dev/null) && _sl_after=$(git -C "$ROOT" show "$HEAD_OID:VERSION" 2>/dev/null) ||
	refuse "VERSION could not be read at its merge base and head, so $_sl_unread"
_sl_listed=$({ printf '%s\n' "$_sl_before" | manifest_section files; printf '%s\n' "$_sl_after" | manifest_section files; } | sort -u)
[ -n "$_sl_listed" ] || refuse "VERSION's files: list reads empty at its merge base and head, so $_sl_unread"
# The moved paths the manifest names, at either end, one per line.
_sl_hit=$(printf '%s\n' "$_sl_moved" | while IFS= read -r _sl_p; do
	[ -n "$_sl_p" ] && printf '%s\n' "$_sl_listed" | grep -qxF -- "$_sl_p" && printf '%s\n' "$_sl_p"
done)
if [ -n "$_sl_hit" ] && ! bumped "$_sl_before" "$_sl_after" >/dev/null; then
	_sl_was=$(layer_version "$_sl_before") _sl_now=$(layer_version "$_sl_after")
	refuse "it moves the shared layer — $(printf '%s\n' "$_sl_hit" | tr '\n' ' ')— with no new version on VERSION's shared-layer line (${_sl_was:-no version} at its merge base, ${_sl_now:-no version} at its head); a shared-layer change is a release (AGENTS.md hard rule 3): bump the minor in VERSION, record it in UPDATING.md, re-capture the pinned transcripts"
fi

# --- 1c. the landing line ---------------------------------------------------------
# Whether /implement opened the PR, read from the line it writes in the body
# (#480). The body is untrusted text: it is matched against one fixed shape,
# never evaluated and never spliced into an event — what reaches the trace is
# a handle the shape allows, `#` and 1 to 9 digits or a canonical factory
# ticket id, and a tier the vocabulary checker passes. Anything else, the body
# unreadable included, is recorded as absent; the record never blocks a
# landing. Read before the merge, since a line naming a factory ticket names
# the ticket of a PR that closes none (runtime/R243).
IMPLEMENT=no
IMPL_TIER=
implement_line() {
	gh pr view "$PR" --json body --jq '.body // ""' 2>/dev/null | tr -d '\r' |
		awk 'index($0, "<!-- implement:") == 1 { n++; line = $0 } END { if (n == 1) print line }' |
		sed -n 's/^<!-- implement: ticket=\([#T][-0-9]\{1,10\}\) tier=\([a-z][a-z0-9-]\{0,31\}\) -->$/\1 \2/p'
}
# legal_tier <token> — the vocabulary checker's verdict on one token the
# shape above already bounded: one argument, one line, never the body.
legal_tier() { sh "$ROOT/scripts/vocab.sh" "Tier: $1" >/dev/null 2>&1; }
# legal_handle <handle> — `#` and 1 to 9 digits, or a canonical factory id.
legal_handle() {
	case $1 in
	'#'*) case ${1#\#} in '' | *[!0-9]* | ??????????*) return 1 ;; esac ;;
	*) factory_id "$1" ;;
	esac
}
# Exactly one line opening with the marker, and it of the one shape: a second
# one, or a malformed one, leaves nothing to read.
IMPL=$(implement_line)
_il_ticket=
if [ -n "$IMPL" ]; then
	_il_ticket=${IMPL%% *}
	_il_tier=${IMPL#* }
	legal_handle "$_il_ticket" && legal_tier "$_il_tier" || _il_ticket=
fi

[ -n "$TICKET" ] || TICKET=$(field ticket)
# A PR that closes no issue and was given no --ticket takes the factory
# ticket its line names; an issue number on the line names none (#480).
[ -n "$TICKET" ] || ! factory_id "$_il_ticket" || TICKET=$_il_ticket
# TREF is the ticket as a subject spells it after `ticket:`.
case $TICKET in '' | T-*) TREF=$TICKET ;; *) TREF="#$TICKET" ;; esac
if [ -n "$_il_ticket" ] && { [ -z "$TICKET" ] || [ "$_il_ticket" = "$TREF" ]; }; then
	IMPLEMENT=yes
	IMPL_TIER=$_il_tier
fi
TITLE=$(field title)
if [ -n "$TICKET" ]; then
	FB_SUBJECT="ticket:$TREF"
	set -- "related=ticket:$TREF"
else
	FB_SUBJECT="pr:#$PR"
	set --
fi
[ -z "$ITERATED" ] || set -- "$@" "data.iterated=$ITERATED"
[ "$ITERATED" != no ] || set -- "$@" "data.no_iteration=$NO_ITERATION"
[ -z "$REVIEWED" ] || set -- "$@" "data.reviewed=$REVIEWED"
[ "$REVIEWED" != no ] || set -- "$@" "data.no_review=$NO_REVIEW"
[ -z "$VERIFIED" ] || set -- "$@" "data.verified=$VERIFIED"

# --- 1L. the low-risk lane: hold, or go on to the merge (ADR-0047) -------------
# Only with --lane, and only once every refusal above has passed (runtime/R80).
# Each check below holds on the first that applies, in ADR-0047 clause 4's
# order; PRD-10's later slices add theirs between `closed` and `switch`. What
# leaves this block is closed tokens, the PR and ticket numbers and the head
# commit — never a line the policy, the risk rule or the forge wrote.
DECISIONS=
if [ -n "$LANE" ]; then
	# hold <token> [<reason>] — print it, record it once per PR, head and
	# token, exit 4. A reason, the verifier's, follows the token on the line
	# and rides the event as data.reason (runtime/R104).
	hold() {
		if ! trace_read show "pr:#$PR" --kind merge.land | grep -F "\"subject\":\"pr:#$PR\"" |
			grep -F '"outcome":"skipped"' | grep -F '"via":"lane"' | grep -F "\"hold\":\"$1\"" |
			grep -qF "\"head\":\"$HEAD_OID\""; then
			trace quiet kind=merge.land "subject=pr:#$PR" ${TICKET:+"related=ticket:$TREF"} outcome=skipped \
				data.via=lane "data.hold=$1" ${2:+"data.reason=$2"} "data.head=$HEAD_OID"
		fi
		printf 'lane: held %s\n' "$1${2:+ $2}"
		exit 4
	}
	_lane_base="refs/remotes/origin/$BASE"
	# closed: the lane policy at the base names a forge login, or the lane is
	# closed (runtime/R83). The kit's twin is read, as this script reads the
	# kit's trace policy; the base's copy is evaluated in a child process that
	# starts with the name unset, so neither the environment nor the PR's tree
	# stands in for it.
	_lane_op=
	_lane_copy=$(cd "$ROOT" && sh scripts/policy.sh read scripts/lane.kit.config.sh --base "$_lane_base" 2>/dev/null) &&
		[ -f "$_lane_copy" ] &&
		_lane_op=$(sh -c 'unset LANE_OPERATOR; . "$1" >/dev/null 2>&1 </dev/null; command printf "%s\n" "${LANE_OPERATOR-}"' _ "$_lane_copy" 2>/dev/null)
	case $_lane_op in
	'' | -* | *- | *--* | *[!A-Za-z0-9-]*) hold closed ;;
	esac
	# A forge login is 1 to 39 letters, digits and single inner hyphens.
	[ "${#_lane_op}" -le 39 ] || hold closed
	# drift: the landing script and the risk rule this run obeys are the
	# base's, byte for byte, so no PR lands under the code it changes; a copy
	# the base cannot give is drift too (runtime/R84).
	for _lane_f in land.kit.sh risk.sh; do
		_lane_b=$(git -C "$ROOT" show "$_lane_base:scripts/$_lane_f" 2>/dev/null) &&
			[ "$_lane_b" = "$(cat "$ROOT/scripts/$_lane_f" 2>/dev/null)" ] || hold drift
	done
	# path: step 1c's diff, from the merge base to the head, touching a file
	# the manifest names at either end, a judging file the policy reader
	# names (its failing closed included), or a path one of the lane policy's
	# hold patterns selects — whatever the risk (runtime/R85). A pattern is
	# letters, digits, `.`, `_`, `/`, `-` and `*`, which crosses a `/`; one out
	# of that shape holds every PR, and none is ever expanded as a filename.
	[ -z "$_sl_hit" ] || hold path
	(cd "$ROOT" && sh scripts/policy.sh touched "$_lane_base" "$HEAD_OID" </dev/null >/dev/null 2>&1) || hold path
	_lane_pat=$(sh -c 'unset LANE_HOLD_PATTERNS; . "$1" >/dev/null 2>&1 </dev/null; command printf "%s\n" "${LANE_HOLD_PATTERNS-}"' _ "$_lane_copy" 2>/dev/null | tr '\n\t' '  ')
	case $_lane_pat in *[!A-Za-z0-9._/*\ -]*) hold path ;; esac
	set -f
	for _lane_p in $_lane_pat; do
		printf '%s\n' "$_sl_moved" | while IFS= read -r _lane_m; do
			case $_lane_m in $_lane_p) exit 1 ;; esac
		done || hold path
	done
	set +f
	# base-red: the latest run of each workflow on the base branch's head
	# commit, and every one of them a success — a run not yet finished, or a
	# forge that cannot say, included (runtime/R86).
	_lane_tip=$(git -C "$ROOT" rev-parse --verify --quiet "$_lane_base" 2>/dev/null) || hold base-red
	case $_lane_tip in '' | *[!0-9a-f]*) hold base-red ;; esac
	_lane_runs=$(gh run list --branch "$BASE" --commit "$_lane_tip" --limit 200 --json workflowName,status,conclusion,createdAt \
		--jq 'group_by(.workflowName)[] | max_by(.createdAt) | if .status == "completed" then .conclusion else .status end' \
		</dev/null 2>/dev/null) || hold base-red
	! printf '%s\n' "$_lane_runs" | grep -v '^success$' | grep -q . || hold base-red
	# check-table: the check-table reader on the PR's body and the ticket's —
	# an issue's from the tracker, a factory ticket's its file at the base —
	# exits 0, or the PR holds; no ticket, or an empty body, is no body
	# (runtime/R87). Only the reader's exit is read.
	_lane_ok=
	_lane_tmp=$(mktemp -d "${TMPDIR:-/tmp}/land-lane.XXXXXX") || hold check-table
	if [ -n "$TICKET" ] && gh pr view "$PR" --json body --jq '.body // ""' </dev/null >"$_lane_tmp/pr" 2>/dev/null; then
		case $TICKET in
		T-*) git -C "$ROOT" show "$_lane_base:.factory/items/$TICKET/ticket.md" >"$_lane_tmp/ticket" 2>/dev/null && _lane_ok=1 ;;
		*) gh issue view "$TICKET" --json body --jq '.body // ""' </dev/null >"$_lane_tmp/ticket" 2>/dev/null && _lane_ok=1 ;;
		esac
		[ -z "$_lane_ok" ] || grep -q '[^[:space:]]' "$_lane_tmp/ticket" || _lane_ok=
		[ -z "$_lane_ok" ] || sh "$ROOT/scripts/check-table.sh" "$_lane_tmp/pr" "$_lane_tmp/ticket" </dev/null >/dev/null 2>&1 || _lane_ok=
	fi
	rm -rf "$_lane_tmp"
	[ -n "$_lane_ok" ] || hold check-table
	# verifier: the latest verify.verdict at the head, as merge.land reads it
	# above, is a pass — the one verifier outcome the landing script acts on
	# (runtime/R104, R215). The hold names why: a blocked verdict with a
	# disputed pin, any other blocked, unavailable, or none at all.
	case $VERIFIED in
	pass) ;;
	blocked)
		case $VERIFIED_DISPUTED in '' | 0 | *[!0-9]*) hold verifier blocked ;; *) hold verifier disputed ;; esac
		;;
	unavailable) hold verifier unavailable ;;
	*) hold verifier none ;;
	esac
	# switch, risk: the risk rule at the head, with the PR and its ticket, read
	# for two lines only (runtime/R88). Anything but `switch: on` and
	# `effective: low` holds — a rule that printed neither included.
	_lane_rule=$(cd "$ROOT" && TRACE_CONFIG="$TRACE_POLICY" sh scripts/risk.sh "$_lane_base" "$HEAD_OID" --pr "$PR" \
		${TICKET:+--ticket "$TICKET"} </dev/null 2>/dev/null) || _lane_rule=
	_lane_sw=$(printf '%s\n' "$_lane_rule" | sed -n 's/^switch: //p' | head -n 1)
	_lane_eff=$(printf '%s\n' "$_lane_rule" | sed -n 's/^effective: //p' | head -n 1)
	[ "$_lane_sw" != tripped ] || hold switch
	[ "$_lane_sw" = on ] && [ "$_lane_eff" = low ] || hold risk
	# The decision-log ids in the PR body, struck rows counted and a fenced log
	# no log (the kit's ADR-0038): a count, never a cell.
	. "$ROOT/scripts/requirement.lib.sh"
	DECISIONS=$(gh pr view "$PR" --json body --jq '.body // ""' 2>/dev/null | tr -d '\r' | fence_strip |
		awk -F'|' '/^<!-- decision-log -->$/ { t = 1; next } t && !/^\|/ { t = 0 }
			t { id = $2; gsub(/[ ~]/, "", id); if (id ~ /^D-[0-9]+$/) n++ } END { print n + 0 }')
	case $DECISIONS in '' | *[!0-9]*) DECISIONS=0 ;; esac
	set -- "$@" "data.decisions=$DECISIONS"
fi

# --- 1d. a PR the trace never saw opened (#638) --------------------------------
# A PR opened outside /implement left no pr.open, and /retro joins a ticket to
# its PR through that event's related field. When the trace holds none on
# pr:#<N>, the landing writes it, marked data.via=land. The head branch is
# forge text: only a ref of a bounded shape reaches the trace, else nothing.
# Unconfigured, there is nothing to read and nothing written.
if [ -n "$(trace_read dir)" ] &&
	! trace_read show "pr:#$PR" --kind pr.open | grep -qF "\"subject\":\"pr:#$PR\""; then
	_po_rel=
	[ -z "$TICKET" ] || _po_rel="ticket:$TREF"
	_po_branch=$(field headRefName | sed -n '/^[A-Za-z0-9][A-Za-z0-9._\/-]\{0,99\}$/p')
	# The lane records no forge text (runtime/R102): no branch, no title.
	[ -z "$LANE" ] || _po_branch=
	[ -z "$_po_branch" ] || _po_rel="${_po_rel:+$_po_rel }branch:$_po_branch"
	# The landing's own arguments sit in "$@" for step 2: the optional field
	# is spelled as an argument only when it is there, never by `set --`.
	_po_why="reason=$TITLE"
	[ -z "$LANE" ] || _po_why=
	trace quiet kind=pr.open "subject=pr:#$PR" ${_po_rel:+"related=$_po_rel"} outcome=opened data.via=land ${_po_why:+"$_po_why"}
fi

# --- 1e. a ticket the trace never saw started (#775) ---------------------------
# /implement records ticket.start when it reads the stamp; a PR whose ticket has
# none reaches /retro looking like a trace that lost it. When the trace holds no
# ticket.start on ticket:#<N>, merge.land says data.ticket_start=no; with one, or
# with no ticket known, it says nothing. Unconfigured, nothing is read.
if [ -n "$TICKET" ] && [ -n "$(trace_read dir)" ] &&
	! trace_read show "ticket:$TREF" --kind ticket.start | grep -qF "\"subject\":\"ticket:$TREF\""; then
	set -- "$@" data.ticket_start=no
fi

# --- 2. the merge -------------------------------------------------------------
# The lane merges the head the risk rule judged, and no other: a head that
# moved since is the forge's refusal (runtime/R89).
_pin=
[ -z "$LANE" ] || _pin=$HEAD_OID
_stop_why="reason=the forge rejected the merge"
[ -z "$LANE" ] || _stop_why=
if ! gh pr merge "$PR" --merge ${_pin:+--match-head-commit "$_pin"} >&3 2>&3; then
	note "the forge rejected the merge of PR #$PR — re-read its state; nothing else was done"
	trace loud kind=merge.land "subject=pr:#$PR" "$@" outcome=stopped data.method=merge "data.via=$VIA" \
		${_stop_why:+"$_stop_why"}
	exit 1
fi
# The forge can name the merge commit a moment after the merge: asked again,
# within the same wait as step 3.
SHA=
i=0
while [ "$i" -lt "$POLL_TRIES" ]; do
	SHA=$(gh pr view "$PR" --json mergeCommit --jq '.mergeCommit.oid // ""' 2>/dev/null) && [ -n "$SHA" ] && break
	SHA=
	i=$((i + 1))
	[ "$POLL_SECONDS" -gt 0 ] && sleep "$POLL_SECONDS"
done

# --- 2b. a release lands tagged (#509, ADR-0015) ------------------------------
# A merge that moves VERSION's shared-layer line is a release, and a release is
# not landed until its merge commit carries v<version> (hard rule 3). The CI
# that holds that line (self-host F3) starts on the merge push, before any tag
# could exist — so the tag is cut here, before the wait, and step 3 re-runs
# once what failed without it. An existing tag is never moved.
RELEASE=
TAGGED=
if [ -n "$SHA" ]; then
	if git -C "$ROOT" fetch -q origin "$BASE" >/dev/null 2>&1 &&
		_ver_after=$(git -C "$ROOT" show "$SHA:VERSION" 2>/dev/null) &&
		_ver_before=$(git -C "$ROOT" show "$SHA^1:VERSION" 2>/dev/null); then
		if _v=$(bumped "$_ver_before" "$_ver_after"); then
			RELEASE=v$_v
		elif [ -z "$(layer_version "$_ver_after")" ] && printf '%s\n' "$_ver_after" | grep -q '^shared-layer:'; then
			note "VERSION's shared-layer line at $SHA is not a version — nothing tagged"
		fi
	else
		note "could not read VERSION at $SHA and its parent — if the merge bumped the shared layer, tag it by hand: git tag -a v<version> $SHA && git push origin v<version>"
	fi
fi
if [ -n "$RELEASE" ]; then
	# The commit the forge's tag already names, peeled when it is annotated.
	_held=$(git -C "$ROOT" ls-remote --tags origin "refs/tags/$RELEASE" "refs/tags/$RELEASE^{}" 2>/dev/null |
		awk '$2 ~ /\^\{\}$/ { p = $1 } $2 !~ /\^\{\}$/ && q == "" { q = $1 } END { print (p != "" ? p : q) }')
	if [ "$_held" = "$SHA" ]; then
		TAGGED=yes
		note "$RELEASE already names $SHA on origin — nothing to cut"
	elif [ -n "$_held" ]; then
		TAGGED=no
		note "$RELEASE already names $_held on origin, not the merge commit $SHA — a tag is never moved; this release is not landed"
	elif ! git -C "$ROOT" tag -a "$RELEASE" -m "$RELEASE — $TITLE" "$SHA" >&2; then
		TAGGED=no
		note "the tag $RELEASE could not be cut — cut it by hand: git tag -a $RELEASE $SHA && git push origin $RELEASE"
	elif ! git -C "$ROOT" push origin "refs/tags/$RELEASE" >&2; then
		TAGGED=no
		note "the tag $RELEASE was cut here (git tag -a $RELEASE $SHA) but origin refused it — push it by hand: git push origin $RELEASE"
	else
		TAGGED=yes
		note "tagged the merge commit $SHA $RELEASE and pushed it"
	fi
fi

# push_workflows <commit> — the workflow files under .github/workflows/, as
# the merge commit holds them, that declare a push trigger: one name per
# line. Exit 1 when the commit, or one of its workflow files, is not here to
# read; a commit with no workflow directory declares none. A trigger is
# `push` in the top-level `on:` value (`on: push`, `on: [push, …]`) or a
# `push` key under it. Its branch filters are not read: a push trigger that
# excludes the base reads as expected, and a wrong `unknown` stops a train
# where a wrong `none` would call an unverified merge verified.
push_workflows() {
	git -C "$ROOT" cat-file -e "$1^{commit}" 2>/dev/null || return 1
	_pw_names=$(git -C "$ROOT" ls-tree --name-only "$1:.github/workflows" 2>/dev/null) || return 0
	printf '%s\n' "$_pw_names" | while IFS= read -r _pw_f; do
		case $_pw_f in *.yml | *.yaml) ;; *) continue ;; esac
		_pw_text=$(git -C "$ROOT" show "$1:.github/workflows/$_pw_f" 2>/dev/null) || exit 1
		if printf '%s\n' "$_pw_text" | awk '
			{ sub(/^#.*/, ""); sub(/[ \t]#.*/, "") }
			/^[^ \t]/ { on = 0 }
			/^["\047]?on["\047]?[ \t]*:/ {
				v = $0; sub(/^[^:]*:/, "", v)
				if (v ~ /(^|[^A-Za-z0-9_-])push([^A-Za-z0-9_-]|$)/) f = 1
				on = 1; next
			}
			on && /^[ \t]+(-[ \t]+)?["\047]?push["\047]?[ \t]*(:|$)/ { f = 1 }
			END { exit !f }'; then
			printf '%s\n' "$_pw_f"
		fi
	done
}

# watch_run <run id> — wait for one run's end, then judge it with the forge's
# own watch: exit 0 green, 1 red or stopped. A run can end with one job
# record still "in progress" — the job finished (its conclusion is set) or
# its run completed, yet the record never closed — and a watch on it never
# returns (pr:#842 waited 3,308 s; pr:#831, #850). So the wait reads the job
# records itself: each job stuck so is re-run once, by its job id, and named
# on stderr; the same job stuck again — or still stuck LAND_POLL_TRIES reads
# after its re-run — is a stop, judged as a red check is. Records it cannot
# read, or a stuck line naming no job id, leave for the forge's watch, the
# wait before #850 — bounded by bounded_watch, since a stuck job is what a
# watch never returns on: exit 2 when it outlives the wait.
# shellcheck disable=SC2016 # $s is jq's variable, not the shell's
STALL_JQ='.status, (.status as $s | .jobs[] | select(.status != "completed" and ($s == "completed" or (.conclusion // "") != "")) | "\(.databaseId) \(.name)")'
watch_run() {
	_wr_ids=" " _wr_names= _wr_tries=0
	while :; do
		# Records the forge cannot answer for: the bounded watch.
		_wr_seen=$(gh run view "$1" --json status,jobs --jq "$STALL_JQ" 2>/dev/null) || {
			bounded_watch "$1"
			return
		}
		_wr_stuck=$(printf '%s\n' "$_wr_seen" | sed -n 2p)
		if [ -n "$_wr_stuck" ]; then
			_wr_job=${_wr_stuck%% *} _wr_name=${_wr_stuck#* }
			case $_wr_job in '' | *[!0-9]*) # not a job id: the bounded watch
				bounded_watch "$1"
				return
				;;
			esac
			case $_wr_ids in
			*" $_wr_job "*)
				# The re-run was asked; the forge has not replaced the record yet.
				_wr_tries=$((_wr_tries + 1))
				if [ "$_wr_tries" -ge "$POLL_TRIES" ]; then
					note "run $1's job '$_wr_name' is still stuck in progress after its re-run — stopped, judged a failure"
					return 1
				fi
				;;
			*)
				if printf '%s\n' "$_wr_names" | grep -qxF -- "$_wr_name"; then
					note "run $1's job '$_wr_name' is stuck again in progress after its one re-run — stopped, judged a failure"
					return 1
				fi
				note "run $1's job '$_wr_name' (job $_wr_job) is stuck in progress after it ended — re-running that job, once"
				gh run rerun --job "$_wr_job" >&3 2>&3 || {
					note "the forge refused to re-run job '$_wr_name' of run $1 — judged a failure"
					return 1
				}
				_wr_ids="$_wr_ids$_wr_job " _wr_names="$_wr_names$_wr_name
" _wr_tries=0
				;;
			esac
		elif [ "$(printf '%s\n' "$_wr_seen" | sed -n 1p)" = completed ]; then
			break
		fi
		[ "$POLL_SECONDS" -gt 0 ] && sleep "$POLL_SECONDS"
	done
	# Completed with no job stuck: the watch returns at once with the verdict.
	gh run watch "$1" --exit-status >&3 2>&3
}

# bounded_watch <run id> — the forge's watch, given the wait's bound: checked
# LAND_POLL_TRIES times, LAND_POLL_SECONDS apart (one second at least, so a
# zero-second suite still gives it time). Exit 0 green, 1 red; 2 when the
# watch outlived the wait — it is stopped, named on stderr, and the caller
# records the workflows unknown, as an exhausted wait does (#850).
bounded_watch() {
	_bw_dir=$(mktemp -d "${TMPDIR:-/tmp}/land-watch.XXXXXX") || return 2
	(
		gh run watch "$1" --exit-status >&3 2>&3 &
		echo $! >"$_bw_dir/pid"
		wait $!
		echo $? >"$_bw_dir/rc"
	) &
	_bw_sub=$! _bw_n=0
	_bw_nap=$POLL_SECONDS
	[ "$_bw_nap" -gt 0 ] || _bw_nap=1
	while [ ! -s "$_bw_dir/rc" ]; do
		if [ "$_bw_n" -ge "$POLL_TRIES" ]; then
			kill "$(cat "$_bw_dir/pid" 2>/dev/null)" 2>/dev/null
			wait "$_bw_sub" 2>/dev/null
			rm -rf "$_bw_dir"
			note "run $1's watch did not end within the wait ($POLL_TRIES checks, ${_bw_nap}s apart) — stopped; its workflows are unknown"
			return 2
		fi
		_bw_n=$((_bw_n + 1))
		sleep "$_bw_nap"
	done
	wait "$_bw_sub"
	_bw_rc=$(cat "$_bw_dir/rc")
	rm -rf "$_bw_dir"
	[ "$_bw_rc" = 0 ]
}

# --- 3. the base branch's workflows on the merge commit -----------------------
# Listed until nothing new appears: a workflow the forge registers a beat
# after the first is watched too. With no sha there is nothing to list.
START=$(date +%s)
WORKFLOWS=success
WATCHED=
FAILED=
STALLED=
if [ -z "$SHA" ]; then
	WORKFLOWS=unknown
	note "the forge never reported the merge commit of PR #$PR — it merged; its workflows were not watched"
else
	i=0
	while [ "$i" -lt "$POLL_TRIES" ]; do
		NEW=
		for id in $(gh run list --branch "$BASE" --commit "$SHA" --json databaseId --jq '.[].databaseId' 2>/dev/null); do
			case " $WATCHED " in *" $id "*) ;; *) NEW="$NEW $id" ;; esac
		done
		if [ -n "$NEW" ]; then
			for id in $NEW; do
				watch_run "$id"
				case $? in
				0) ;;
				2)
					STALLED=$id
					break
					;;
				*) WORKFLOWS=failure FAILED="$FAILED $id" ;;
				esac
			done
			WATCHED="$WATCHED$NEW"
			[ -z "$STALLED" ] || break
		elif [ -n "$WATCHED" ]; then
			break
		else
			i=$((i + 1))
		fi
		[ "$POLL_SECONDS" -gt 0 ] && sleep "$POLL_SECONDS"
	done
	# No run is a verdict only when none was due (#688): the forge can skip
	# a push run, and a merge no CI ran must not read as a verified one.
	if [ -z "$WATCHED" ]; then
		if ! EXPECTED=$(push_workflows "$SHA"); then
			WORKFLOWS=unknown
			note "no workflow ran on $BASE at $SHA within the wait, and its workflows could not be read here — the merge is unverified"
		elif [ -n "$EXPECTED" ]; then
			WORKFLOWS=unknown
			note "no workflow ran on $BASE at $SHA within the wait, though these declare a push trigger: $(printf '%s\n' "$EXPECTED" | tr '\n' ' ')— the merge is unverified"
		else
			WORKFLOWS=none
			note "no workflow ran on $BASE at $SHA within the wait, and none of its workflows declares a push trigger — nothing to watch"
		fi
	fi
	# A watch that outlived the wait stops it: what it watched is unknown,
	# unless a run already failed (#850).
	[ -z "$STALLED" ] || [ "$WORKFLOWS" = failure ] || WORKFLOWS=unknown
fi
# A tagged release re-runs, once, each run that failed — its failed jobs only:
# a run on the merge push may have started before the tag existed, and its
# second attempt alone is judged. With no tag on origin a re-run would fail
# the same way, so nothing is re-run, and an untagged merge is never re-run.
# A re-run the forge refuses because the run is already running is no verdict:
# that run is watched to its end and its end is judged (#661). Any other
# refusal is a failure. data.reruns counts the re-runs the forge started.
RERUNS=0
# rerun_judged <run id> — watch a re-run and fold its end into WORKFLOWS;
# exit 1 only when the watch outlived the wait, which stops the re-runs.
rerun_judged() {
	watch_run "$1"
	case $? in
	0) ;;
	2)
		STALLED=$1
		[ "$WORKFLOWS" = failure ] || WORKFLOWS=unknown
		return 1
		;;
	*) WORKFLOWS=failure ;;
	esac
}
if [ "$TAGGED" = yes ] && [ -n "$FAILED" ] && [ -z "$STALLED" ]; then
	note "re-running, once, what failed before $RELEASE was on origin:$FAILED"
	WORKFLOWS=success
	for id in $FAILED; do
		# The forge's answer reaches stderr as before, and is kept to be read.
		_said=$(gh run rerun "$id" --failed 2>&1)
		_rc=$?
		[ -z "$_said" ] || printf '%s\n' "$_said" >&3
		if [ "$_rc" -ne 0 ]; then
			case $_said in
			*"already running"*)
				note "run $id is already running — the re-run was refused; waiting for that run's end instead"
				rerun_judged "$id" || break
				;;
			*)
				note "the forge refused to re-run run $id — judged a failure"
				WORKFLOWS=failure
				;;
			esac
			continue
		fi
		RERUNS=$((RERUNS + 1))
		# The new attempt leaves `completed` a beat after the re-run is asked.
		i=0
		while [ "$i" -lt "$POLL_TRIES" ] &&
			[ "$(gh run view "$id" --json status --jq .status 2>/dev/null)" = completed ]; do
			i=$((i + 1))
			[ "$POLL_SECONDS" -gt 0 ] && sleep "$POLL_SECONDS"
		done
		rerun_judged "$id" || break
	done
fi
WAITED=$(($(date +%s) - START))

# --- 4. the landing ---------------------------------------------------------------
# Whether /implement opened the PR is read in step 1c's landing line, above.
_land_why="reason=$TITLE"
[ -z "$LANE" ] || _land_why=
set -- "subject=pr:#$PR" "$@" outcome=landed data.method=merge "data.waited=$WAITED" "data.workflows=$WORKFLOWS" "data.via=$VIA" \
	${_land_why:+"$_land_why"} "data.implement=$IMPLEMENT"
[ -z "$IMPL_TIER" ] || set -- "$@" "data.implement_tier=$IMPL_TIER"
[ -z "$SHA" ] || set -- "$@" "data.merge_sha=$SHA"
[ -z "$RELEASE" ] || set -- "$@" "data.release=$RELEASE" "data.tagged=$TAGGED" "data.reruns=$RERUNS"
trace loud kind=merge.land "$@"

# --- 5. the verdict ---------------------------------------------------------------
# Under --train the verdict is the train's: it asks after the merge and says
# who answered, so this run writes no feedback a second one would join.
if [ "$VIA" = train ]; then
	VERDICT="left to the train"
elif [ -n "$LANE" ]; then
	# Nobody was asked, and the lane says it was the one landing it.
	VERDICT=unasked
	set -- "subject=$FB_SUBJECT" outcome=unasked data.by=lane
	[ -z "$TICKET" ] || set -- "$@" "related=pr:#$PR"
	trace quiet kind=feedback "$@"
else
	VERDICT=unasked
	WHY=$UNASKED
	if [ -z "$UNASKED" ]; then
		if [ -t 0 ]; then
			WHY="the operator left the prompt without a verdict"
			while :; do
				printf 'Did the slice hit its target? hit | adjusted | missed: ' >&2
				read -r ans || break
				case $ans in
				hit | adjusted | missed)
					printf 'One line: what it taught, or what gets re-cut: ' >&2
					read -r WHY || WHY=
					VERDICT=$ans
					break
					;;
				esac
				note "answer hit, adjusted or missed"
			done
		else
			WHY="no terminal at the prompt, so nobody was asked"
		fi
	fi
	# On the ticket, related to the PR — the join to merge.land; on the PR alone
	# when no ticket is known. A verdict given with no line carries no reason.
	set -- "subject=$FB_SUBJECT" "outcome=$VERDICT"
	[ -z "$TICKET" ] || set -- "$@" "related=pr:#$PR"
	[ -z "$WHY" ] || set -- "$@" "reason=$WHY"
	trace quiet kind=feedback "$@"
fi

# --- 6. the root checkout follows the landing (#636) ---------------------------
# The hooks run from the root checkout, so a landed hook fix reaches no session
# until the root moves. It is fast-forwarded to origin's base only when it is
# a checkout, on the base branch, with no tracked change uncommitted and
# nothing of its own that origin lacks; any other root is left exactly as it
# was, and named. Tracked changes only, as scripts/worktree-cleanup.sh judges
# the same root: an untracked file is safe, since `merge --ff-only` refuses
# rather than overwrite one. Never a reset, a stash or a merge commit: the
# one write is `merge --ff-only`. It changes no exit status and no event.
RC=${LAND_ROOT_CHECKOUT:-$(git -C "$ROOT" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')}
leave_root() { note "left the root checkout $RC alone: $1 — fast-forward it by hand when it is clean and on $BASE"; }
# Read before the ladder, never inside it: empty is a detached HEAD, or no
# checkout at all, which the first rung below names first.
_rc_branch=$(git -C "$RC" symbolic-ref -q --short HEAD 2>/dev/null) || _rc_branch=
if [ -z "$RC" ] || ! _rc_top=$(git -C "$RC" rev-parse --show-toplevel 2>/dev/null) ||
	[ "$_rc_top" != "$(cd "$RC" 2>/dev/null && pwd -P)" ]; then
	note "the root checkout ${RC:-<none found>} is not a checkout — no root fast-forwarded"
elif [ -z "$_rc_branch" ]; then
	leave_root "its HEAD is detached, not on $BASE"
elif [ "$_rc_branch" != "$BASE" ]; then
	leave_root "it is on $_rc_branch, not $BASE"
elif ! git -C "$RC" diff --quiet 2>/dev/null || ! git -C "$RC" diff --cached --quiet 2>/dev/null; then
	leave_root "it has uncommitted changes"
elif ! git -C "$RC" fetch -q origin "$BASE" >/dev/null 2>&1; then
	leave_root "fetching origin $BASE there failed"
elif ! _rc_to=$(git -C "$RC" rev-parse -q --verify "refs/remotes/origin/$BASE^{commit}" 2>/dev/null); then
	leave_root "it has no origin/$BASE to follow"
elif [ "$(git -C "$RC" rev-parse HEAD 2>/dev/null)" = "$_rc_to" ]; then
	note "the root checkout $RC is already at origin/$BASE ($_rc_to)"
elif ! git -C "$RC" merge-base --is-ancestor HEAD "$_rc_to" 2>/dev/null; then
	leave_root "its $BASE has diverged from origin/$BASE (it holds commits origin lacks)"
elif ! git -C "$RC" merge --ff-only -q "$_rc_to" >&2; then
	leave_root "the fast-forward to origin/$BASE failed"
else
	note "fast-forwarded the root checkout $RC to origin/$BASE ($_rc_to)"
fi

TAGNOTE=
case $TAGGED in
yes) TAGNOTE=" · tagged $RELEASE" ;;
no) TAGNOTE=" · $RELEASE NOT tagged" ;;
esac
printf 'landed #%s %s (merge) · workflows %s · waited %ss%s\n' "$PR" "${SHA:-<merge commit unknown>}" "$WORKFLOWS" "$WAITED" "$TAGNOTE"
printf 'feedback: %s\n' "$VERDICT"
[ -z "$LANE" ] || echo 'lane: landed'
case $WORKFLOWS in
failure)
	note "a post-merge workflow failed on $BASE at $SHA — escalate with the run log; land nothing else"
	exit 1
	;;
unknown)
	if [ -z "$SHA" ]; then
		note "find the merge commit of PR #$PR and watch $BASE's workflows on it by hand"
	else
		note "no CI verified $SHA on $BASE — run its workflows on it (or find why the forge made no run) before landing anything else"
	fi
	exit 1
	;;
esac
# An untagged release is not landed (hard rule 3), whatever main says.
if [ "$TAGGED" = no ]; then
	note "$RELEASE merged but is not on origin as a tag naming $SHA — the release is not landed until it is; land nothing else"
	exit 1
fi
exit 0
