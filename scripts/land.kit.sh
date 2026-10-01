#!/bin/sh
# land.kit.sh — land ONE green PR by hand, and record it the way the train does.
# Kit-authoring only, never shipped (bootstrap.sh's KIT_ONLY list deletes it,
# with tests/land.test.sh).
#
#   sh scripts/land.kit.sh <PR#> [--ticket <N>] [--unasked '<reason>']
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
#   2. Merges with the merge-commit method (`gh pr merge <N> --merge`) — the
#      one constitution/local-workflow.md mandates. A merge the forge rejects
#      records merge.land `stopped` and exits 1; no verdict is asked.
#   3. Waits for the base branch's workflows on the merge commit, each one
#      watched to its end.
#   4. Emits merge.land (`landed`, the sha, the method, the wait, the
#      workflows' result) on pr:#<N>, related to the ticket.
#   5. Asks the verdict question when stdin is a terminal and emits feedback
#      `hit|adjusted|missed`; with no terminal, or --unasked, it emits
#      `unasked` with the reason — never a verdict nobody gave.
#   A failed post-merge workflow still records both events — the PR did land —
#   and then exits 1: escalate, as the train's hard rule 6 says.
#
# THE TICKET is the PR's first closing reference, or --ticket. With neither,
# the feedback sits on the PR itself.
#
# THE TRACE is never load-bearing (ADR-0008 clause 4): unconfigured, the merge
# and stdout are exactly what a traced run does. Kit-only, so the kit's own
# policy is the default seam — scripts/trace.sh read through
# scripts/trace.kit.config.sh, what scripts/trace.kit.sh runs; a caller's
# TRACE_CONFIG still wins (the broker's arrangement).
#
# exit: 0 landed · 1 merge rejected, or a post-merge workflow failed · 2 usage, or the PR refused · 69 no forge CLI
#
# tests/land.test.sh drives this file against a stub `gh` on PATH.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)

# How long step 3 looks for the merge commit's runs to appear: the forge
# registers them a moment after the merge. The suite sets the wait to 0.
POLL_TRIES=${LAND_POLL_TRIES:-12}
POLL_SECONDS=${LAND_POLL_SECONDS:-10}

usage() {
	cat >&2 <<'EOF'
usage: sh scripts/land.kit.sh <PR#> [--ticket <N>] [--unasked '<reason>']
  <PR#>       the pull request to land — green, mergeable, clean against its base
  --ticket    the ticket the PR implemented, when the PR closes none
  --unasked   record the verdict as unasked, with this reason (the operator is not at the prompt)
exit: 0 landed · 1 merge rejected, or a post-merge workflow failed · 2 usage, or the PR refused · 69 no forge CLI
EOF
	exit 2
}
note() { echo "land: $1" >&2; }
refuse() {
	note "refusing PR #$PR: $1 — nothing merged, nothing recorded"
	exit 2
}

PR=
TICKET=
UNASKED=
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
	-h | --help) usage ;;
	-*) note "unknown option '$1'"; usage ;;
	*) [ -z "$PR" ] || usage; PR=$1 ;;
	esac
	shift
done
case $PR in '' | *[!0-9]*) [ -z "$PR" ] || note "'$PR' is not a pull request number"; usage ;; esac
case $TICKET in *[!0-9]*) note "--ticket '$TICKET' is not a ticket number"; usage ;; esac
command -v gh >/dev/null 2>&1 || { note "no forge CLI (gh) on PATH"; exit 69; }

# trace loud|quiet <field>=<value> … — `quiet` silences the unconfigured
# note, so an unconfigured run says it once. The switch rides the external
# command, never a prefix on this function (forge-broker.kit.sh says why).
trace() {
	_tr_quiet=
	[ "$1" = quiet ] && _tr_quiet=1
	shift
	TRACE_QUIET="${_tr_quiet:-${TRACE_QUIET:-}}" TRACE_CONFIG="${TRACE_CONFIG:-$ROOT/scripts/trace.kit.config.sh}" \
		sh "$ROOT/scripts/trace.sh" emit "$@" </dev/null || :
}

# --- 1. the gate: green and mergeable, or nothing happens ---------------------
# One value per line: a title is the only free text, and it comes last.
STATE=$(gh pr view "$PR" --json state,isDraft,mergeable,mergeStateStatus,reviewDecision,baseRefName,closingIssuesReferences,title \
	--jq '.state, (.isDraft|tostring), .mergeable, .mergeStateStatus, (.reviewDecision // ""), .baseRefName, ((.closingIssuesReferences // []) | map(.number|tostring) | first // ""), .title') ||
	refuse "the forge did not answer for it"
field() { printf '%s\n' "$STATE" | sed -n "${1}p"; }
[ "$(field 1)" = OPEN ] || refuse "it is $(field 1), not open"
[ "$(field 2)" = false ] || refuse "it is a draft"
[ "$(field 5)" != CHANGES_REQUESTED ] || refuse "a human review requests changes"
[ "$(field 3)" = MERGEABLE ] || refuse "it is not mergeable ($(field 3)) — send it to /pr-iterate"
case $(field 4) in
CLEAN | HAS_HOOKS) ;;
BEHIND) refuse "it is behind its base — a train updates it through the forge first" ;;
*) refuse "its merge state is $(field 4), not clean" ;;
esac
gh pr checks "$PR" >/dev/null 2>&1
case $? in
0) ;;
8) refuse "its checks are still pending — not green yet" ;;
*) refuse "its checks are not green" ;;
esac
BASE=$(field 6)
[ -n "$TICKET" ] || TICKET=$(field 7)
TITLE=$(field 8)
if [ -n "$TICKET" ]; then
	FB_SUBJECT="ticket:#$TICKET"
	set -- "related=ticket:#$TICKET"
else
	FB_SUBJECT="pr:#$PR"
	set --
fi

# --- 2. the merge -------------------------------------------------------------
if ! gh pr merge "$PR" --merge >&2; then
	note "the forge rejected the merge of PR #$PR — re-read its state; nothing else was done"
	trace loud kind=merge.land "subject=pr:#$PR" "$@" outcome=stopped data.method=merge data.via=land \
		"reason=the forge rejected the merge"
	exit 1
fi
SHA=$(gh pr view "$PR" --json mergeCommit --jq .mergeCommit.oid)

# --- 3. the base branch's workflows on the merge commit -----------------------
START=$(date +%s)
RUNS=
i=0
while [ "$i" -lt "$POLL_TRIES" ]; do
	RUNS=$(gh run list --branch "$BASE" --commit "$SHA" --json databaseId --jq '.[].databaseId' 2>/dev/null)
	[ -n "$RUNS" ] && break
	i=$((i + 1))
	[ "$POLL_SECONDS" -gt 0 ] && sleep "$POLL_SECONDS"
done
WORKFLOWS=success
if [ -z "$RUNS" ]; then
	WORKFLOWS=none
	note "no workflow ran on $BASE at $SHA within the wait — nothing to watch"
fi
for id in $RUNS; do
	gh run watch "$id" --exit-status >&2 || WORKFLOWS=failure
done
WAITED=$(($(date +%s) - START))

# --- 4. the landing ---------------------------------------------------------------
trace loud kind=merge.land "subject=pr:#$PR" "$@" outcome=landed "data.merge_sha=$SHA" data.method=merge \
	"data.waited=$WAITED" "data.workflows=$WORKFLOWS" data.via=land "reason=$TITLE"

# --- 5. the verdict ---------------------------------------------------------------
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

printf 'landed #%s %s (merge) · workflows %s · waited %ss\n' "$PR" "$SHA" "$WORKFLOWS" "$WAITED"
printf 'feedback: %s\n' "$VERDICT"
if [ "$WORKFLOWS" = failure ]; then
	note "a post-merge workflow failed on $BASE at $SHA — escalate with the run log; land nothing else"
	exit 1
fi
exit 0
