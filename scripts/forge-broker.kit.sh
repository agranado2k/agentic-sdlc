#!/bin/sh
# forge-broker.kit.sh — land a dispatched reviewer's report on the pull request.
# Kit-authoring only, never shipped (bootstrap.sh's KIT_ONLY list deletes it,
# with scripts/forge-broker.kit.config.sh and tests/forge-broker.test.sh).
#
#   sh scripts/forge-broker.kit.sh <PR> <report|-> [--dry-run] [--commit <sha>]
#                                  [--model <id>] [--harness <name>]
#
# WHY THIS EXISTS. When /implement reaches its review step with no review
# workflow wired, this repo dispatches the reviewer tier to another vendor's
# agent harness (scripts/agent-dispatch.sh). That worker runs in the harness's
# default sandbox — a read-only tree and NO NETWORK — which is the right
# place for an agent whose input is a diff the root manual classifies as
# untrusted content: with network it would hold private data, untrusted
# content and an external action at once, the lethal trifecta, with the
# operator's own forge token in reach. So the worker never posts. It prints
# its findings on stdout in the machine contract .agents/prompts/review-worker.md
# defines, the coordinating session captures that to a file, and THIS script —
# on the host, where the credentials and the network already are — validates
# the report and performs the only two forge operations the policy allows.
# ADR-0009 is the record; PRD #261 the design.
#
# THE BROKER, NOT A GATE AND NOT A GUARD. A gate checks the tree, a guard
# checks a diff; the broker ACTS on a forge on a worker's behalf, under a
# policy, and refuses everything the policy does not name. Nothing in the
# report can choose the operation, the target PR or the review event: the PR
# is the operator's first argument, the operations are the policy file's
# list, and the event is the policy file's constant — COMMENT, always
# explicit, because a blank event leaves the forge's review PENDING and
# visible to nobody, and APPROVE would let a worker's word satisfy branch
# protection.
#
# WHAT IT DOES, IN ORDER — validation before action, and nothing posted
# unless everything validated:
#   1. Refuse to run without the forge CLI (`gh`) on PATH — exit 69.
#   2. Parse the report against the contract: a `REVIEWED: <full sha>` first
#      line, a `VERDICT:` line, both axis headings, the four severity headings
#      in order with an empty one STATING its absence, findings in the
#      `**ID** \`path:line\` — text` / `↳ fix:` shape with an ID whose letter
#      matches its section, and a confirm-list whose items open with their
#      tag. A report that fails ANY of this posts nothing — exit 65 — and a
#      `REVIEWED` that contradicts `--commit` is the same failure. What the
#      worker did not say, the broker does not write: absence is published
#      only where the report stated it.
#   3. Ask the forge for the PR head. In this release the reviewed commit
#      must BE the head; anything else is exit 75 with a one-line reason,
#      and the finer staleness cases (commits added after the review, a
#      rewritten branch) are a later ticket's.
#   4. Ask the forge for the PR diff and check every finding's `path:line`
#      against its right-hand side. A finding whose location is not in the
#      diff is DROPPED from the inline comments and named on stderr — the
#      forge refuses a review that cites a line outside the diff, and one
#      fabricated location must not sink the rest. Its severity section then
#      says how many it withheld — never "none found.".
#   5. Look for the marker an earlier run of this same report left on the PR
#      (an HTML comment carrying the report's content hash). A review or
#      comment already carrying it is not posted again; its URL is printed
#      instead. A retried session lands the review once — and a lookup the
#      forge REFUSES is exit 69, never a silent "not there".
#   6. Perform the two operations: one review with `event` COMMENT and the
#      findings as inline comments, one top-level comment with the behavior
#      confirm-list. Print the two URLs on stdout, one per line, then one
#      `dropped …` line when anything was withheld.
#   7. Emit one `review.verdict` trace event, subject `pr:#<N>`, the verdict
#      as outcome, the model and agent harness when the caller passed them.
#      Never load-bearing (ADR-0008 clause 4).
#
# --dry-run performs the READS (head, diff) and prints both payloads exactly
# as they would be sent, and makes no mutating call and no trace emit.
#
# STREAMS AND EXIT STATUSES. stdout is the answer: URLs, one per line, then
# the dropped summary; under --dry-run, the two JSON payloads. Every reason is
# on stderr, prefixed `forge-broker:`. Exit 0 posted, or already posted; 2 a
# usage error; 65 (EX_DATAERR) a report that fails the contract; 69
# (EX_UNAVAILABLE) no forge CLI, or a forge call that failed; 75 (EX_TEMPFAIL)
# the reviewed commit is not the head, re-run the review; 78 (EX_CONFIG) a
# policy file that is missing, or does not allow an operation this script
# performs.
#
# POSIX sh, `git` and `gh` only — no jq, no node: the JSON payload is built
# here, with one escaper walked character by character (the finding text is
# untrusted and carries quotes, backslashes and whatever else the worker
# wrote), and `gh api --input -` carries it as a body. `gh`'s own `--jq` is
# used to read single fields back; it is part of `gh`, not a dependency.
#
# tests/forge-broker.test.sh drives this file against a stub `gh` that records
# argv and stdin and answers with canned output.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)

EX_USAGE=2
EX_DATAERR=65
EX_UNAVAILABLE=69
EX_TEMPFAIL=75
EX_CONFIG=78

usage() {
	cat >&2 <<'EOF'
usage: sh scripts/forge-broker.kit.sh <PR> <report|-> [--dry-run] [--commit <sha>] [--model <id>] [--harness <name>]
  <PR>       the pull request number the review lands on — the operator's, never the report's
  <report>   the dispatched reviewer's stdout, captured to a file; - reads standard input
  --dry-run  read the PR, print both payloads as they would be sent, post nothing
  --commit   the sha the session recorded before dispatching; must equal the report's REVIEWED line
  --model, --harness   recorded on the trace event, nothing else
exit: 0 posted (or already posted) · 2 usage · 65 report fails the contract · 69 no forge CLI · 75 reviewed commit is not the head · 78 policy
EOF
	exit "$EX_USAGE"
}

note() { echo "forge-broker: $1" >&2; }
die() {
	_d_status=$1
	shift
	note "$*"
	exit "$_d_status"
}

# --- arguments ---------------------------------------------------------------
PR=
REPORT=
DRY=0
COMMIT=
MODEL=
HARNESS=
while [ $# -gt 0 ]; do
	case $1 in
	--dry-run) DRY=1 ;;
	--commit)
		[ $# -ge 2 ] || usage
		COMMIT=$2
		shift
		;;
	--model)
		[ $# -ge 2 ] || usage
		MODEL=$2
		shift
		;;
	--harness)
		[ $# -ge 2 ] || usage
		HARNESS=$2
		shift
		;;
	-h | --help) usage ;;
	-) [ -n "$PR" ] && [ -z "$REPORT" ] || usage; REPORT=- ;;
	-*) note "unknown option '$1'"; usage ;;
	*)
		if [ -z "$PR" ]; then
			PR=$1
		elif [ -z "$REPORT" ]; then
			REPORT=$1
		else
			usage
		fi
		;;
	esac
	shift
done
[ -n "$PR" ] && [ -n "$REPORT" ] || usage
case $PR in '' | *[!0-9]*) note "'$PR' is not a pull request number"; usage ;; esac
if [ "$REPORT" != - ]; then
	[ -f "$REPORT" ] || { note "report '$REPORT' does not exist or is not a file"; usage; }
	[ -r "$REPORT" ] || { note "report '$REPORT' is not readable"; usage; }
fi
if [ -n "$COMMIT" ]; then
	case $COMMIT in *[!0-9a-fA-F]* | '' | ? | ?? | ??? | ???? | ????? | ??????) die "$EX_USAGE" "--commit '$COMMIT' is not a hex sha of at least seven characters" ;; esac
	COMMIT=$(printf '%s' "$COMMIT" | tr 'A-F' 'a-f')
fi

# --- the policy: an allow-list, as data ----------------------------------------
# Anchored on where THIS FILE lives unless named explicitly: a policy file is
# sourced, which is to say executed, and standing in a foreign clone must never
# run its code as you (the reason scripts/agents.lib.sh gives).
POLICY=${BROKER_CONFIG:-$ROOT/scripts/forge-broker.kit.config.sh}
[ -f "$POLICY" ] || die "$EX_CONFIG" "policy file '$POLICY' does not exist"
BROKER_OPERATIONS=
BROKER_OP_REVIEW_ENDPOINT=
BROKER_OP_REVIEW_EVENT=
BROKER_OP_COMMENT_ENDPOINT=
# shellcheck disable=SC1090
. "$POLICY"
allowed() {
	for _al_op in $BROKER_OPERATIONS; do
		[ "$_al_op" = "$1" ] && return 0
	done
	return 1
}
for op in review comment; do
	allowed "$op" || die "$EX_CONFIG" "the policy '$POLICY' does not allow the '$op' operation, and this broker performs it — nothing posted. BROKER_OPERATIONS is '$BROKER_OPERATIONS'."
done
[ -n "$BROKER_OP_REVIEW_ENDPOINT" ] || die "$EX_CONFIG" "the policy allows 'review' but names no BROKER_OP_REVIEW_ENDPOINT"
[ -n "$BROKER_OP_COMMENT_ENDPOINT" ] || die "$EX_CONFIG" "the policy allows 'comment' but names no BROKER_OP_COMMENT_ENDPOINT"
# The one value this script will not take on trust even from its own policy:
# any event but COMMENT lets a worker's report approve or block a PR.
[ "$BROKER_OP_REVIEW_EVENT" = COMMENT ] || die "$EX_CONFIG" "BROKER_OP_REVIEW_EVENT is '$BROKER_OP_REVIEW_EVENT'; the broker posts reviews with event COMMENT only — a review must never approve or block a PR on a worker's word (ADR-0009)"
REVIEW_EP="repos/{owner}/{repo}/$(printf '%s' "$BROKER_OP_REVIEW_ENDPOINT" | sed "s/{pr}/$PR/g")"
COMMENT_EP="repos/{owner}/{repo}/$(printf '%s' "$BROKER_OP_COMMENT_ENDPOINT" | sed "s/{pr}/$PR/g")"

# --- the forge CLI -------------------------------------------------------------
command -v gh >/dev/null 2>&1 || die "$EX_UNAVAILABLE" "the forge CLI 'gh' is not on PATH — the broker has no other way to reach the forge"

# --- scratch ----------------------------------------------------------------------
TMP=$(mktemp -d "${TMPDIR:-/tmp}/forge-broker.XXXXXX") || die 1 "cannot create a scratch directory"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
mkdir -p "$TMP/findings"

if [ "$REPORT" = - ]; then
	cat >"$TMP/report.md"
else
	cp "$REPORT" "$TMP/report.md"
fi
[ -s "$TMP/report.md" ] || die "$EX_DATAERR" "the report is empty — nothing to validate, nothing posted"

# --- 2. the contract ----------------------------------------------------------------
# One awk pass, bytes not characters (the tags are emoji and the dash is
# multi-byte; C collation keeps every byte a byte). It writes what it found
# into scratch — one file per fact, one pair of files per finding — and every
# violation to $TMP/error. The shell reads the verdict of that pass, never the
# report again.
LC_ALL=C awk -v out="$TMP" '
BEGIN {
	order[1] = "CRITICAL"; order[2] = "HIGH"; order[3] = "MEDIUM"; order[4] = "LOW"
	initial["CRITICAL"] = "C"; initial["HIGH"] = "H"; initial["MEDIUM"] = "M"; initial["LOW"] = "L"
	want = 1; sev = ""; n = 0; infinding = 0; verdict = 0; axis1 = 0; axis2 = 0; tagged = 0
}
function err(msg) { print msg >> (out "/error") }
NR == 1 {
	if ($0 ~ /^REVIEWED:[ \t]*[0-9a-fA-F]+[ \t]*$/) {
		s = $0; sub(/^REVIEWED:[ \t]*/, "", s); sub(/[ \t]*$/, "", s)
		if (length(s) != 40) err("the REVIEWED line carries " length(s) " hex characters, not a full 40-character sha: " $0)
		else print tolower(s) > (out "/reviewed")
	} else err("the first line is not REVIEWED: <sha> — it reads: " substr($0, 1, 80))
	next
}
/^VERDICT:/ && !verdict {
	verdict = 1
	print $0 > (out "/verdict")
	next
}
# The two axis headings are part of the contract, and the second one closes
# Axis 1: findings stop being recognised there, tags start.
/^##[ \t]+Axis[ \t]*1/ { axis1 = 1; infinding = 0; next }
/^##[ \t]+Axis[ \t]*2/ { axis2 = 1; sev = "done"; infinding = 0; next }
/^#### (CRITICAL|HIGH|MEDIUM|LOW)[ \t]*$/ {
	h = $2
	infinding = 0
	if (want > 4) { err("a fifth severity heading: " $0); next }
	if (h != order[want]) { err("severity heading out of order: found #### " h " where #### " order[want] " was expected"); next }
	want++
	sev = h
	seen[h] = 1
	next
}
# An empty severity section STATES its absence; the broker never infers it.
sev != "" && sev != "done" && !infinding && /^[^A-Za-z0-9]*[Nn]one found/ { absent[sev] = 1; next }
sev != "" && sev != "done" && /^([-*][ \t]+)?\*\*[CHML]-[0-9]+\*\*/ {
	n++
	line = $0
	sub(/^[-*][ \t]+/, "", line)
	id = line; sub(/^\*\*/, "", id); sub(/\*\*.*$/, "", id)
	path = ""; lno = ""
	rest = line; sub(/^\*\*[^*]*\*\*[ \t]*/, "", rest)
	if (match(rest, /^`[^`]+`/)) {
		loc = substr(rest, 2, RLENGTH - 2)
		k = 0
		for (i = length(loc); i > 0; i--) if (substr(loc, i, 1) == ":") { k = i; break }
		if (k > 1 && k < length(loc)) {
			path = substr(loc, 1, k - 1); lno = substr(loc, k + 1)
			if (lno !~ /^[0-9]+$/ || lno + 0 == 0) { path = ""; lno = "" }
		}
	}
	fid[n] = id
	cnt[sev]++
	if (substr(id, 1, 1) != initial[sev]) err("finding " id " sits under #### " sev " — IDs are C-1, H-1, M-1, L-1 …, numbered from 1 within their own severity")
	if (path == "") err("finding " id " carries no readable `path:line` — the shape is **<ID>** `<file>:<line>` — <text>, and a location the broker cannot read is a finding it cannot anchor")
	printf "%s\t%s\t%s\t%s\n", id, sev, path, lno > (out "/findings/" n ".meta")
	print line > (out "/findings/" n ".body")
	infinding = n
	next
}
infinding && /^[ \t]*$/ { infinding = 0; next }
infinding {
	if ($0 ~ /^[^A-Za-z0-9]*fix:[ \t]*[^ \t]/) hasfix[infinding] = 1
	print $0 >> (out "/findings/" infinding ".body"); next
}
(sev == "LOW" || sev == "done") && /^([-*][ \t]+)?[^A-Za-z0-9#`*]*(UNSPECIFIED|MISSING|MIXED COMMIT|SPECIFIED)([ \t]|$)/ {
	line = $0
	sub(/^[-*][ \t]+/, "", line)
	tagged++
	print line >> (out "/behavior")
	next
}
END {
	if (!verdict) err("no VERDICT: line")
	if (want <= 4) err("the severity heading #### " order[want] " is missing — all four appear, in order, always")
	if (!axis1) err("no `## Axis 1` heading — the standards axis opens with it")
	if (!axis2) err("no `## Axis 2` heading — the behavior confirm-list opens with it, and the broker never writes a confirm-list the worker did not")
	for (i = 1; i <= 4; i++) {
		s = order[i]
		if (seen[s] && !cnt[s] && !absent[s]) err("the #### " s " section holds no finding and does not state absence — an empty heading carries the line `— none found.`, so that absence is stated and never inferred")
	}
	for (i = 1; i <= n; i++) if (!hasfix[i]) err("finding " fid[i] " carries no `↳ fix:` line — a finding without the concrete change is half a finding")
	if (axis2 && !tagged) err("the `## Axis 2` section holds no item opening with its tag (⚠️ UNSPECIFIED, ❌ MISSING, 🔀 MIXED COMMIT, ✅ SPECIFIED) — a confirm-list the broker cannot read is not one it may publish as empty")
	print n > (out "/count")
}
' "$TMP/report.md"

if [ -s "$TMP/error" ]; then
	note "the report fails the worker contract; nothing posted:"
	sed 's/^/forge-broker:   /' "$TMP/error" >&2
	exit "$EX_DATAERR"
fi
REVIEWED=$(cat "$TMP/reviewed")
VERDICT_LINE=$(head -n 1 "$TMP/verdict")
VERDICT=$(printf '%s' "$VERDICT_LINE" | sed 's/^VERDICT:[ 	]*//')
COUNT=$(cat "$TMP/count")

# --commit may be abbreviated; the report's REVIEWED sha is full, so agreement
# is a prefix match.
if [ -n "$COMMIT" ]; then
	case $REVIEWED in
	"$COMMIT"*) ;;
	*) die "$EX_DATAERR" "the report says REVIEWED: $REVIEWED but the session recorded --commit $COMMIT; the two must agree — nothing posted" ;;
	esac
fi

# --- 3. the head ----------------------------------------------------------------------
HEAD=$(gh pr view "$PR" --json headRefOid --jq .headRefOid 2>"$TMP/gh.err") || {
	sed 's/^/forge-broker:   /' "$TMP/gh.err" >&2
	die "$EX_UNAVAILABLE" "the forge did not answer for PR #$PR"
}
HEAD=$(printf '%s' "$HEAD" | tr -d ' \r\n' | tr 'A-F' 'a-f')
[ -n "$HEAD" ] || die "$EX_UNAVAILABLE" "the forge returned no head sha for PR #$PR"
[ "$REVIEWED" = "$HEAD" ] || die "$EX_TEMPFAIL" "reviewed commit $REVIEWED is not the head of PR #$PR (head is $HEAD); re-run the review against the current head — nothing posted"

# --- 4. locations against the diff -------------------------------------------------------
gh pr diff "$PR" >"$TMP/pr.diff" 2>"$TMP/gh.err" || {
	sed 's/^/forge-broker:   /' "$TMP/gh.err" >&2
	die "$EX_UNAVAILABLE" "the forge did not return the diff of PR #$PR"
}
# The right-hand side of every hunk, as `path<TAB>start<TAB>end`; a finding's
# line must sit inside one of its file's ranges.
#
# THE PATH IS THE WHOLE REST OF THE LINE, NOT ITS SECOND FIELD. A name with
# spaces is truncated by `$2`, and git QUOTES a name that is not plain ASCII
# (core.quotePath) in C style, octal escapes and all. Either way a valid
# finding on that file would be dropped as "not in the diff" and its severity
# section published as "none found" — absence inferred from a parse bug. So:
# take the rest of the line, unquote it when it is quoted, then strip `b/`,
# and keep the ranges TAB-separated so a space in a path stays inside it.
LC_ALL=C awk '
	function unquote(s,   r, i, n, c, o, v, k) {
		s = substr(s, 2, length(s) - 2)
		r = ""; n = length(s)
		for (i = 1; i <= n; i++) {
			c = substr(s, i, 1)
			if (c != "\\") { r = r c; continue }
			i++; c = substr(s, i, 1)
			if (c == "n") r = r "\n"
			else if (c == "t") r = r "\t"
			else if (c == "r") r = r "\r"
			else if (c == "a") r = r sprintf("%c", 7)
			else if (c == "b") r = r sprintf("%c", 8)
			else if (c == "f") r = r sprintf("%c", 12)
			else if (c == "v") r = r sprintf("%c", 11)
			else if (c >= "0" && c <= "7") {
				o = c
				while (length(o) < 3 && substr(s, i + 1, 1) >= "0" && substr(s, i + 1, 1) <= "7") { i++; o = o substr(s, i, 1) }
				v = 0
				for (k = 1; k <= length(o); k++) v = v * 8 + (substr(o, k, 1) + 0)
				r = r sprintf("%c", v)
			}
			else r = r c
		}
		return r
	}
	/^\+\+\+ / {
		p = substr($0, 5)
		sub(/\r$/, "", p)
		if (substr(p, 1, 1) == "\"") p = unquote(p)
		if (p == "/dev/null") { p = ""; next }
		sub(/^b\//, "", p)
		next
	}
	/^@@ / && p != "" {
		m = $3; sub(/^\+/, "", m)
		split(m, a, ",")
		s = a[1] + 0
		c = (a[2] == "" ? 1 : a[2] + 0)
		if (c > 0) printf "%s\t%s\t%s\n", p, s, s + c - 1
	}
' "$TMP/pr.diff" >"$TMP/hunks"
in_diff() { LC_ALL=C awk -F'\t' -v p="$1" -v l="$2" '$1 == p && $2 + 0 <= l + 0 && l + 0 <= $3 + 0 { f = 1 } END { exit !f }' "$TMP/hunks"; }

# --- the payloads --------------------------------------------------------------------------
# json_str — standard input as the inside of a JSON string, on one line:
# backslash, quote, tab and CR escaped, lines joined with \n, every other
# control character removed first (tr, whose octal ranges are POSIX).
json_str() {
	tr -d '\001-\010\013\014\016-\037' | LC_ALL=C awk '
		NR > 1 { printf "\\n" }
		{
			n = length($0)
			for (i = 1; i <= n; i++) {
				c = substr($0, i, 1)
				if (c == "\\") printf "\\\\"
				else if (c == "\"") printf "\\\""
				else if (c == "\t") printf "\\t"
				else if (c == "\r") printf "\\r"
				else printf "%s", c
			}
		}
	'
}

HASH=$( (unset GIT_DIR GIT_WORK_TREE && git hash-object "$TMP/report.md") 2>/dev/null) || die 1 "git hash-object failed — git is required"
MARKER="<!-- forge-broker: $HASH -->"

# The review body: the marker, the verdict, and the four headings, each
# stating absence or listing the findings that are inline below it. The
# finding text itself lives on the inline comment, once.
DROPPED=
NDROPPED=0
: >"$TMP/comments.json"
for sev in CRITICAL HIGH MEDIUM LOW; do
	printf '\n#### %s\n' "$sev" >>"$TMP/body.md"
	any=0
	secdrop=0
	i=1
	while [ "$i" -le "$COUNT" ]; do
		IFS='	' read -r f_id f_sev f_path f_line <"$TMP/findings/$i.meta"
		if [ "$f_sev" = "$sev" ]; then
			if ! in_diff "$f_path" "$f_line"; then
				note "dropped $f_id: $f_path:$f_line is not in the diff of PR #$PR — the forge would refuse the whole review for it"
				DROPPED="${DROPPED:+$DROPPED, }$f_id ($f_path:$f_line not in diff)"
				NDROPPED=$((NDROPPED + 1))
				secdrop=$((secdrop + 1))
			else
				any=1
				printf '**%s** `%s:%s` — inline below.\n' "$f_id" "$f_path" "$f_line" >>"$TMP/body.md"
				[ -s "$TMP/comments.json" ] && printf ',' >>"$TMP/comments.json"
				printf '{"path":"%s","line":%s,"side":"RIGHT","body":"%s"}' \
					"$(printf '%s' "$f_path" | json_str)" "$f_line" "$(json_str <"$TMP/findings/$i.body")" >>"$TMP/comments.json"
			fi
		fi
		i=$((i + 1))
	done
	# Absence is only ever REPORTED absence. A section whose findings were all
	# withheld says so — "none found." there would be the broker putting a
	# claim the worker never made under its own review.
	if [ "$any" != 1 ]; then
		if [ "$secdrop" = 0 ]; then
			printf -- '— none found.\n' >>"$TMP/body.md"
		else
			printf -- '— %s finding(s) withheld: their locations are not in this PR diff; see the broker log.\n' "$secdrop" >>"$TMP/body.md"
		fi
	fi
done
{
	printf '%s\n' "$MARKER"
	printf '%s\n\n' "$VERDICT_LINE"
	printf '## Axis 1 — Standards\n'
	cat "$TMP/body.md"
	printf '\n---\n_Standards axis of a review by a dispatched reviewer that ran offline and read-only; landed by the forge broker (`scripts/forge-broker.kit.sh`) at %s' "$REVIEWED"
	[ -n "$MODEL" ] && printf ', model `%s`' "$MODEL"
	[ -n "$HARNESS" ] && printf ' on `%s`' "$HARNESS"
	printf '. Event: COMMENT, by policy — this review never approves or blocks._\n'
} >"$TMP/review.md"
printf '{"commit_id":"%s","event":"%s","body":"%s","comments":[%s]}\n' \
	"$REVIEWED" "$BROKER_OP_REVIEW_EVENT" "$(json_str <"$TMP/review.md")" "$(cat "$TMP/comments.json")" >"$TMP/review.json"

{
	printf '%s\n' "$MARKER"
	printf '## Axis 2 — Behavior (for a human)\n\n'
	cat "$TMP/behavior"
	printf '\n---\n_Behavior axis of the same dispatched review; a confirm-list for a human, never resolved by an agent (shared invariant §5)._\n'
} >"$TMP/comment.md"
printf '{"body":"%s"}\n' "$(json_str <"$TMP/comment.md")" >"$TMP/comment.json"

if [ "$DRY" = 1 ]; then
	printf 'POST %s\n' "$REVIEW_EP"
	cat "$TMP/review.json"
	printf 'POST %s\n' "$COMMENT_EP"
	cat "$TMP/comment.json"
	[ "$NDROPPED" = 0 ] || printf 'dropped %s finding(s): %s\n' "$NDROPPED" "$DROPPED"
	note "dry run — nothing posted, nothing traced"
	exit 0
fi

# --- 5. already landed? -----------------------------------------------------------------------
# `url<TAB>body` per review or comment; the marker is the first line of every
# body this script writes, so it follows the tab directly.
#
# A LISTING THAT FAILED IS NOT AN EMPTY LISTING. The marker is the whole of
# clause 8's recovery guarantee: a lookup that 502s, or that a stale token
# refuses, must never read as "the marker is not there", or the retry posts
# the review a second time. So the forge's own status is kept — the `grep`
# runs on a file, never in the pipeline whose status the shell would read —
# and a refusal on EITHER lookup is exit 69 before either write.
existing() {
	gh api "$1" --paginate --jq '.[] | "\(.html_url)\t\(.body)"' >"$TMP/listing" 2>"$TMP/gh.err" || return 1
	grep -F "	$MARKER" "$TMP/listing" | head -n 1 | cut -f1
}
REVIEW_URL=$(existing "$REVIEW_EP") || {
	sed 's/^/forge-broker:   /' "$TMP/gh.err" >&2
	die "$EX_UNAVAILABLE" "the forge did not list the reviews of PR #$PR, so an absent marker cannot be told from an unread one — nothing posted; re-run when the forge answers"
}
COMMENT_URL=$(existing "$COMMENT_EP") || {
	sed 's/^/forge-broker:   /' "$TMP/gh.err" >&2
	die "$EX_UNAVAILABLE" "the forge did not list the comments of PR #$PR, so an absent marker cannot be told from an unread one — nothing posted; re-run when the forge answers"
}

# --- 6. the two operations ---------------------------------------------------------------------
if [ -n "$REVIEW_URL" ]; then
	note "the review for this report already landed: $REVIEW_URL"
else
	REVIEW_URL=$(gh api --method POST "$REVIEW_EP" --input - --jq .html_url <"$TMP/review.json" 2>"$TMP/gh.err") || {
		sed 's/^/forge-broker:   /' "$TMP/gh.err" >&2
		die "$EX_UNAVAILABLE" "the forge refused the review on PR #$PR; the behavior comment was not attempted"
	}
fi
if [ -n "$COMMENT_URL" ]; then
	note "the behavior comment for this report already landed: $COMMENT_URL"
else
	COMMENT_URL=$(gh api --method POST "$COMMENT_EP" --input - --jq .html_url <"$TMP/comment.json" 2>"$TMP/gh.err") || {
		sed 's/^/forge-broker:   /' "$TMP/gh.err" >&2
		die "$EX_UNAVAILABLE" "the forge refused the behavior comment on PR #$PR; the review is at $REVIEW_URL"
	}
fi
printf '%s\n%s\n' "$REVIEW_URL" "$COMMENT_URL"
[ "$NDROPPED" = 0 ] || printf 'dropped %s finding(s): %s\n' "$NDROPPED" "$DROPPED"

# --- 7. the trace ------------------------------------------------------------------------------
# Never load-bearing: the review landed whatever the trace says (ADR-0008
# clause 4). Kit-only script, so the kit's own policy is the default seam.
set -- kind=review.verdict "subject=pr:#$PR" "outcome=$VERDICT" "data.review=$REVIEW_URL" "data.comment=$COMMENT_URL" "data.reviewed=$REVIEWED" "data.dropped=$NDROPPED"
[ -z "$MODEL" ] || set -- "$@" "model=$MODEL"
[ -z "$HARNESS" ] || set -- "$@" "harness=$HARNESS"
TRACE_CONFIG="${TRACE_CONFIG:-$ROOT/scripts/trace.kit.config.sh}" sh "$ROOT/scripts/trace.sh" emit "$@" || :
exit 0
