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
#      judged. An untagged merge's red is never re-run.
#   4. Emits merge.land (`landed`, the sha, the method, the wait, the
#      workflows' result) on pr:#<N>, related to the ticket — and whether
#      /implement opened the PR (data.implement=yes|no, with
#      data.implement_tier when yes — a key of its own, never the event's
#      top-level tier), read from the one line /implement writes in the PR
#      body (#480).
#   5. Asks the verdict question when stdin is a terminal and emits feedback
#      `hit|adjusted|missed`; with no terminal, or --unasked, it emits
#      `unasked` with the reason — never a verdict nobody gave.
#   A failed post-merge workflow still records both events — the PR did land —
#   and then exits 1: escalate, as the train's hard rule 6 says. So does a
#   merge commit the forge never names (data.workflows=unknown, no sha), and
#   so does a release whose tag is not on origin: merged, not landed. A
#   release's merge.land carries data.release, data.tagged and data.reruns.
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
# exit: 0 landed · 1 merge rejected, a post-merge workflow failed, no merge commit named, or a release left untagged · 2 usage, or the PR refused · 69 no forge CLI
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
usage: sh scripts/land.kit.sh <PR#> [--ticket <N>] [--unasked '<reason>']
  <PR#>       the pull request to land — green, mergeable, clean against its base
  --ticket    the ticket the PR implemented, when the PR closes none
  --unasked   record the verdict as unasked, with this reason (the operator is not at the prompt)
exit: 0 landed · 1 merge rejected, a post-merge workflow failed, no merge commit named, or a release left untagged · 2 usage, or the PR refused · 69 no forge CLI
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
# layer_version <VERSION text> — the shared-layer value, only when it is a
# version: anything else is no release and is never typed into a tag.
layer_version() {
	printf '%s\n' "$1" | sed -n 's/^shared-layer: *\([0-9]\{1,6\}\.[0-9]\{1,6\}\.[0-9]\{1,6\}\) *$/\1/p' | head -1
}
if [ -n "$SHA" ]; then
	if git -C "$ROOT" fetch -q origin "$BASE" >/dev/null 2>&1 &&
		_ver_after=$(git -C "$ROOT" show "$SHA:VERSION" 2>/dev/null) &&
		_ver_before=$(git -C "$ROOT" show "$SHA^1:VERSION" 2>/dev/null); then
		_v=$(layer_version "$_ver_after")
		if [ -n "$_v" ] && [ "$_v" != "$(layer_version "$_ver_before")" ]; then
			RELEASE=v$_v
		elif [ -z "$_v" ] && printf '%s\n' "$_ver_after" | grep -q '^shared-layer:'; then
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

# --- 3. the base branch's workflows on the merge commit -----------------------
# Listed until nothing new appears: a workflow the forge registers a beat
# after the first is watched too. With no sha there is nothing to list.
START=$(date +%s)
WORKFLOWS=success
WATCHED=
FAILED=
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
				gh run watch "$id" --exit-status >&2 || { WORKFLOWS=failure; FAILED="$FAILED $id"; }
			done
			WATCHED="$WATCHED$NEW"
		elif [ -n "$WATCHED" ]; then
			break
		else
			i=$((i + 1))
		fi
		[ "$POLL_SECONDS" -gt 0 ] && sleep "$POLL_SECONDS"
	done
	if [ -z "$WATCHED" ]; then
		WORKFLOWS=none
		note "no workflow ran on $BASE at $SHA within the wait — nothing to watch"
	fi
fi
# A tagged release re-runs, once, each run that failed — its failed jobs only:
# a run on the merge push may have started before the tag existed, and its
# second attempt alone is judged. With no tag on origin a re-run would fail
# the same way, so nothing is re-run, and an untagged merge is never re-run.
RERUNS=0
if [ "$TAGGED" = yes ] && [ -n "$FAILED" ]; then
	note "re-running, once, what failed before $RELEASE was on origin:$FAILED"
	WORKFLOWS=success
	for id in $FAILED; do
		RERUNS=$((RERUNS + 1))
		gh run rerun "$id" --failed >&2 || { WORKFLOWS=failure; continue; }
		# The new attempt leaves `completed` a beat after the re-run is asked.
		i=0
		while [ "$i" -lt "$POLL_TRIES" ] &&
			[ "$(gh run view "$id" --json status --jq .status 2>/dev/null)" = completed ]; do
			i=$((i + 1))
			[ "$POLL_SECONDS" -gt 0 ] && sleep "$POLL_SECONDS"
		done
		gh run watch "$id" --exit-status >&2 || WORKFLOWS=failure
	done
fi
WAITED=$(($(date +%s) - START))

# --- 4. the landing ---------------------------------------------------------------
# Whether /implement opened the PR, read from the line it writes in the body
# (#480). The body is untrusted text: it is matched against one fixed shape,
# never evaluated and never spliced into an event — what reaches the trace is
# a digit string the shape allows and a tier the vocabulary checker passes.
# Anything else, the body unreadable included, is recorded as absent; the
# record never blocks a landing.
IMPLEMENT=no
IMPL_TIER=
implement_line() {
	gh pr view "$PR" --json body --jq '.body // ""' 2>/dev/null | tr -d '\r' |
		awk 'index($0, "<!-- implement:") == 1 { n++; line = $0 } END { if (n == 1) print line }' |
		sed -n 's/^<!-- implement: ticket=#\([0-9]\{1,9\}\) tier=\([a-z][a-z0-9-]\{0,31\}\) -->$/\1 \2/p'
}
# legal_tier <token> — the vocabulary checker's verdict on one token the
# shape above already bounded: one argument, one line, never the body.
legal_tier() { sh "$ROOT/scripts/vocab.sh" "Tier: $1" >/dev/null 2>&1; }
# Exactly one line opening with the marker, and it of the one shape: a second
# one, or a malformed one, leaves nothing to read.
IMPL=$(implement_line)
if [ -n "$IMPL" ]; then
	_il_ticket=${IMPL%% *}
	_il_tier=${IMPL#* }
	if { [ -z "$TICKET" ] || [ "$_il_ticket" = "$TICKET" ]; } &&
		legal_tier "$_il_tier"; then
		IMPLEMENT=yes
		IMPL_TIER=$_il_tier
	fi
fi
set -- "subject=pr:#$PR" "$@" outcome=landed data.method=merge "data.waited=$WAITED" "data.workflows=$WORKFLOWS" data.via=land "reason=$TITLE" \
	"data.implement=$IMPLEMENT"
[ -z "$IMPL_TIER" ] || set -- "$@" "data.implement_tier=$IMPL_TIER"
[ -z "$SHA" ] || set -- "$@" "data.merge_sha=$SHA"
[ -z "$RELEASE" ] || set -- "$@" "data.release=$RELEASE" "data.tagged=$TAGGED" "data.reruns=$RERUNS"
trace loud kind=merge.land "$@"

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

TAGNOTE=
case $TAGGED in
yes) TAGNOTE=" · tagged $RELEASE" ;;
no) TAGNOTE=" · $RELEASE NOT tagged" ;;
esac
printf 'landed #%s %s (merge) · workflows %s · waited %ss%s\n' "$PR" "${SHA:-<merge commit unknown>}" "$WORKFLOWS" "$WAITED" "$TAGNOTE"
printf 'feedback: %s\n' "$VERDICT"
case $WORKFLOWS in
failure)
	note "a post-merge workflow failed on $BASE at $SHA — escalate with the run log; land nothing else"
	exit 1
	;;
unknown)
	note "find the merge commit of PR #$PR and watch $BASE's workflows on it by hand"
	exit 1
	;;
esac
# An untagged release is not landed (hard rule 3), whatever main says.
if [ "$TAGGED" = no ]; then
	note "$RELEASE merged but is not on origin as a tag naming $SHA — the release is not landed until it is; land nothing else"
	exit 1
fi
exit 0
