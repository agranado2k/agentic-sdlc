#!/bin/sh
# acceptance-guard.sh — the ACCEPTANCE GUARD: a factory ticket's approved
# acceptance test files held from the approval to the ticket's done, judged
# from the base, failing closed.
#
#   sh scripts/acceptance-guard.sh check <base> <head>
#   sh scripts/acceptance-guard.sh tests <ticket> --base <ref>
#   sh scripts/acceptance-guard.sh held --base <ref>
#
# A FACTORY PROJECT is a repository whose git top level holds the software
# factory's project manifest, .factory/project.yaml; nothing above the top
# level counts. Only one has approved tests: anywhere else every command
# prints nothing and exits 0.
#
# A FACTORY TICKET is .factory/items/<id>/ticket.md, its id the directory's
# name (letters, digits, `.`, `_`, `-`). From its front matter — the block
# between the first two `---` lines — the guard reads `stage`, `created`, and
# the APPROVAL RECORD: `commit`, `by` and `at` nested under a top-level
# `tests:`, which the factory writes when the operator approves the ticket's
# tests. The APPROVAL COMMIT is its `commit`: a commit whose tree holds every
# file the ticket's `Accept-test:` lines name, at the approved content; it
# need not be on the base branch. From the body it reads only the `Covers:`,
# `Test-tier:` and `Accept-test:` stamp lines, each checked by the vocabulary
# checker beside this file (the requirement grammar for `Covers:`). A HELD
# TICKET carries an approval record and is not at stage `done`.
#
# WHERE IT READS. `check` reads the tickets and the manifest at POLICY_BASE
# when it names a ref, and from the working tree when it is unset; `tests`
# and `held` read them at --base. A read at a ref goes through the policy
# reader beside this file (scripts/policy.sh), never the working tree, and
# reads the guards policy there too, so a missing one fails closed. File
# content is compared from git's objects alone: nothing is checked out,
# fetched or written in the working tree.
#
# check   prints, sorted, one `changed: <ticket> <requirement-id> <path>`
#         line per `Accept-test:` path of a held ticket whose content at
#         <head> differs from its content at the approval commit — a path
#         absent at <head> is changed when <base> holds it (the pull request
#         deleted it); one absent at both was never brought in, and is not —
#         and exits 1 when it printed one, 0
#         when none. Every held ticket is scanned, not one PR's.
# tests   for a ticket with an approval record, `approved <commit>` then its
#         `Accept-test:` lines as spelled, exit 0. Without one:
#           no-tests <ticket> no-adoption-date        exit 0 (the manifest's
#                                                     acceptance_tests_since
#                                                     absent or empty)
#           no-tests <ticket> created-before-adoption exit 0 (`created`, a
#                                                     date, before it)
#           no-tests <ticket> no-automated-id         exit 0 (no covered id
#                                                     stamped other than
#                                                     `manual`, or no Covers:)
#           owed <ticket>                             exit 4
#         A `created` missing or not a date never exempts.
# held    one `<ticket> <path>` line per file a held ticket's `Accept-test:`
#         lines name, sorted, exit 0.
#
# FAIL CLOSED: one `fail-closed <reason> <path>` line on stdout and exit 3 —
# the policy reader's own line when it fails closed on the guards policy, the
# manifest or a ticket file; `fail-closed invalid <ticket file>` for an
# approval record the guard cannot hold (a commit this clone does not hold, a
# missing `commit`, `by` or `at`, a record not written field by field, an
# `Accept-test:` line the checker refuses, an approved path absent at the
# approval commit) and, for `tests`, a stamp the checker refuses;
# `fail-closed missing <helper>` when a script this guard reads through is
# not beside it. Nothing read from a ticket is ever printed except ticket ids,
# requirement ids, approval commits, and `Accept-test:` lines the checker
# accepted.
#
# Exit: 0 pass or an answer; 1 `check` found a changed held file; 2 a caller
# error, nothing on stdout; 3 failed closed; 4 `tests` found the ticket owed.
#
# Shared layer (see VERSION): copied verbatim, not edited downstream.

set -u
LC_ALL=C
export LC_ALL

_ag_here=$(cd "$(dirname "$0")" && pwd -P)
READER=$_ag_here/policy.sh
VOCAB=$_ag_here/vocab.sh
GRAMMAR=$_ag_here/requirement.lib.sh
MANIFEST=.factory/project.yaml
TAB=$(printf '\t')

usage="usage: sh scripts/acceptance-guard.sh check <base> <head> | tests <ticket> --base <ref> | held --base <ref>"

die() {
	echo "acceptance-guard: $*" >&2
	exit 2
}

closed() {
	printf 'fail-closed %s %s\n' "$1" "$2"
	exit 3
}

commit_of() {
	case $1 in '' | -*) return 1 ;; esac
	git rev-parse --verify --quiet "$1^{commit}" 2>/dev/null
}

ticket_id_ok() {
	case $1 in '' | . | .. | *[!A-Za-z0-9._-]*) return 1 ;; esac
	return 0
}

git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"

cmd=${1:-}
ref= head= want=
case $cmd in
check)
	[ $# -eq 3 ] || die "$usage"
	basec=$(commit_of "$2") || die "the base ref names no commit: $2"
	head=$(commit_of "$3") || die "the head ref names no commit: $3"
	ref=${POLICY_BASE:-}
	;;
tests)
	[ $# -eq 4 ] && [ "$3" = --base ] || die "$usage"
	ticket_id_ok "$2" || die "not a ticket id: letters, digits, '.', '_' and '-' only"
	want=$2
	ref=$4
	;;
held)
	[ $# -eq 3 ] && [ "$2" = --base ] || die "$usage"
	ref=$3
	;;
*) die "$usage" ;;
esac

top=$(git rev-parse --show-toplevel 2>/dev/null) || die "no working tree"
cd "$top" || die "cannot enter $top"
for _h in "$READER" "$VOCAB" "$GRAMMAR"; do
	[ -f "$_h" ] || closed missing "scripts/${_h##*/}"
done

# --- the factory project and its adoption date ------------------------------
# The policy reader answers both: nothing printed outside a factory project,
# its fail-closed line for a manifest it cannot read or a date out of shape.
rc=0
if [ -n "$ref" ]; then
	commit_of "$ref" >/dev/null || closed no-base "$MANIFEST"
	since=$(sh "$READER" value acceptance-tests-since --base "$ref" 2>/dev/null) || rc=$?
else
	since=$(sh "$READER" value acceptance-tests-since 2>/dev/null) || rc=$?
fi
case $rc in
0) ;;
3)
	case $since in fail-closed\ *) printf '%s\n' "$since" | head -n 1 && exit 3 ;; esac
	closed unreadable "$MANIFEST"
	;;
*) closed unreadable "$MANIFEST" ;;
esac
[ -n "$since" ] || exit 0
since=${since#acceptance-tests-since }
[ "$since" = unset ] && since=

# --- the guards policy, at the base -----------------------------------------
if [ -n "$ref" ]; then
	rc=0
	out=$(sh "$READER" read scripts/guards.config.sh --base "$ref" 2>/dev/null) || rc=$?
	[ "$rc" = 0 ] || {
		case $out in fail-closed\ *) printf '%s\n' "$out" | head -n 1 && exit 3 ;; esac
		closed unreadable scripts/guards.config.sh
	}
fi

# --- the tickets ------------------------------------------------------------
# list_tickets — one repository-relative ticket file path per line.
list_tickets() {
	if [ -n "$ref" ]; then
		git ls-tree -r -z --name-only "$(commit_of "$ref")" -- .factory/items 2>/dev/null | tr '\0' '\n' |
			grep -E '^\.factory/items/[^/]+/ticket\.md$'
	else
		for _lt in .factory/items/*/ticket.md; do
			[ -f "$_lt" ] && printf '%s\n' "$_lt"
		done
	fi
	return 0
}

# open_ticket <path> — set FILE to a readable copy of the ticket, read at the
# base through the policy reader, or the working tree's file.
open_ticket() {
	if [ -n "$ref" ]; then
		_ot_rc=0
		FILE=$(sh "$READER" read "$1" --base "$ref" 2>/dev/null) || _ot_rc=$?
		[ "$_ot_rc" = 0 ] && [ -f "$FILE" ] && return 0
		case $FILE in fail-closed\ *) printf '%s\n' "$FILE" | head -n 1 && exit 3 ;; esac
		closed unreadable "$1"
	fi
	[ -f "$1" ] || closed missing "$1"
	FILE=$1
}

# parse <file> — read the ticket's front matter and stamp lines into STAGE,
# CREATED, REC (none|yes|bad), R_COMMIT, R_BY, R_AT and LINES (the lifted
# Covers:, Test-tier: and Accept-test: lines, one per line).
parse() {
	_pa=$(awk '
		function scalar(v) {
			sub(/^[ \t]+/, "", v)
			if (v ~ /^"/) return match(v, /^"[^"]*"/) ? substr(v, 2, RLENGTH - 2) : ""
			if (v ~ /^\047/) return match(v, /^\047[^\047]*\047/) ? substr(v, 2, RLENGTH - 2) : ""
			sub(/(^|[ \t])#.*$/, "", v); sub(/[ \t]+$/, "", v)
			return v
		}
		function nested(k,   v) { v = $0; sub("^[ \t]+" k "[ \t]*:", "", v); return scalar(v) }
		{ sub(/\r$/, "") }
		NR == 1 && /^---[ \t]*$/ { st = 1; next }
		NR == 1 { st = 2 }
		st == 1 && /^---[ \t]*$/ { st = 2; next }
		st == 1 && /^[^ \t#]/ {
			top = $0; sub(/[ \t]*:.*$/, "", top)
			v = $0; sub(/^[^:]*:/, "", v); v = scalar(v)
			if (top == "tests") { nt++; if (v != "") bad = 1 }
			else if (top == "stage") stage = v
			else if (top == "created") created = v
			next
		}
		st == 1 && top == "tests" && /^[ \t]+[^ \t#]/ {
			kids = 1
			if ($0 ~ /^[ \t]+commit[ \t]*:/) { nc++; commit = nested("commit") }
			else if ($0 ~ /^[ \t]+by[ \t]*:/) { nb++; by = nested("by") }
			else if ($0 ~ /^[ \t]+at[ \t]*:/) { na++; at = nested("at") }
			next
		}
		st == 2 {
			k = tolower($0)
			if (k ~ /^[ \t]*(covers|test(-|[ \t_]+)tier|accept(-|[ \t_]+)test)[ \t]*:/) lines = lines "\n" $0
		}
		END {
			rec = "none"
			if (nt > 1 || nc > 1 || nb > 1 || na > 1) rec = "bad"
			else if (bad) rec = "bad"
			else if (nt && kids) rec = "yes"
			printf "%s\n%s\n%s\n%s\n%s\n%s%s\n", stage, created, rec, commit, by, at, lines
		}' "$1") || closed unreadable "$2"
	STAGE=$(printf '%s\n' "$_pa" | sed -n 1p)
	CREATED=$(printf '%s\n' "$_pa" | sed -n 2p)
	REC=$(printf '%s\n' "$_pa" | sed -n 3p)
	R_COMMIT=$(printf '%s\n' "$_pa" | sed -n 4p)
	R_BY=$(printf '%s\n' "$_pa" | sed -n 5p)
	R_AT=$(printf '%s\n' "$_pa" | sed -n 6p)
	LINES=$(printf '%s\n' "$_pa" | sed '1,6d')
}

# key_lines <key> — the lifted lines whose key folds to <key>.
key_lines() {
	printf '%s\n' "$LINES" | awk -v want="$1" '
		{ k = $0; sub(/:.*/, "", k); sub(/^[ \t]+/, "", k); sub(/[ \t]+$/, "", k)
		  gsub(/[ \t_]+/, "-", k); if (tolower(k) == want) print }'
}

# value_of <line> — a stamp line's value, trimmed.
value_of() { printf '%s\n' "${1#*:}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# vocab_ok <lines> — 0 when the checker accepts every line; a checker that
# cannot run fails closed.
vocab_ok() {
	[ -n "$1" ] || return 0
	_vo=0
	printf '%s\n' "$1" | sh "$VOCAB" >/dev/null 2>&1 || _vo=$?
	case $_vo in
	0) return 0 ;;
	2) return 1 ;;
	*) closed unreadable scripts/vocab.sh ;;
	esac
}

# approved <ticket path> — hold the approval record to its shape: set ACCEPT
# (the checked Accept-test: lines) and PAIRS (`<id><TAB><path>` per line), or
# fail closed naming the ticket file.
approved() {
	[ "$REC" = yes ] || closed invalid "$1"
	[ -n "$R_BY" ] && [ -n "$R_AT" ] || closed invalid "$1"
	printf '%s\n' "$R_COMMIT" | grep -qE '^[0-9a-f]{4,64}$' || closed invalid "$1"
	commit_of "$R_COMMIT" >/dev/null || closed invalid "$1"
	ACCEPT=$(key_lines accept-test)
	vocab_ok "$ACCEPT" || closed invalid "$1"
	PAIRS=
	[ -n "$ACCEPT" ] || return 0
	PAIRS=$(printf '%s\n' "$ACCEPT" | while IFS= read -r _ap_l; do
		_ap_v=$(value_of "$_ap_l")
		_ap_id=${_ap_v%% *}
		_ap_pin=${_ap_v#* }
		printf '%s\t%s\n' "$_ap_id" "${_ap_pin%%::*}"
	done | sort -u)
	_ap_ifs=$IFS
	IFS='
'
	for _ap_p in $PAIRS; do
		[ "$(git cat-file -t "$R_COMMIT:${_ap_p#*"$TAB"}" 2>/dev/null)" = blob ] || {
			IFS=$_ap_ifs
			closed invalid "$1"
		}
	done
	IFS=$_ap_ifs
}

# date_ok <text> — 0 for a real YYYY-MM-DD calendar date.
date_ok() {
	printf '%s\n' "$1" | awk '
		NR > 1 || !/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { bad = 1; next }
		{
			y = substr($0, 1, 4) + 0; m = substr($0, 6, 2) + 0; d = substr($0, 9, 2) + 0
			split("31 28 31 30 31 30 31 31 30 31 30 31", dm, " ")
			if (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) dm[2] = 29
			if (m < 1 || m > 12 || d < 1 || d > dm[m]) bad = 1
		}
		END { exit bad }'
}

# --- tests ------------------------------------------------------------------
if [ "$cmd" = tests ]; then
	path=.factory/items/$want/ticket.md
	open_ticket "$path"
	parse "$FILE" "$path"
	if [ "$REC" != none ]; then
		approved "$path"
		printf 'approved %s\n' "$R_COMMIT"
		[ -z "$ACCEPT" ] || printf '%s\n' "$ACCEPT"
		exit 0
	fi
	if [ -z "$since" ]; then
		printf 'no-tests %s no-adoption-date\n' "$want"
		exit 0
	fi
	if date_ok "$CREATED" && [ "$(printf '%s\n%s\n' "$CREATED" "$since" | sort | head -n 1)" != "$since" ]; then
		printf 'no-tests %s created-before-adoption\n' "$want"
		exit 0
	fi
	# Owed only for a covered id stamped with a tier other than manual.
	covers=$(key_lines covers)
	tiers=$(key_lines test-tier)
	vocab_ok "$tiers" || closed invalid "$path"
	ids=
	if [ -n "$covers" ]; then
		# shellcheck disable=SC1090
		. "$GRAMMAR"
		command -v req_covers_ids >/dev/null 2>&1 || closed invalid "$GRAMMAR"
		[ "$(printf '%s\n' "$covers" | while IFS= read -r l; do value_of "$l"; done | sort -u | wc -l)" -eq 1 ] ||
			closed invalid "$path"
		ids=$(req_covers_ids "$(value_of "$(printf '%s\n' "$covers" | head -n 1)")") || closed invalid "$path"
	fi
	auto=$(printf '%s\n' "$tiers" | while IFS= read -r l; do
		[ -n "$l" ] || continue
		v=$(value_of "$l")
		[ "${v#* }" = manual ] || printf '%s\n' "${v%% *}"
	done)
	for id in $ids; do
		if printf '%s\n' "$auto" | grep -qxF -- "$id"; then
			printf 'owed %s\n' "$want"
			exit 4
		fi
	done
	printf 'no-tests %s no-automated-id\n' "$want"
	exit 0
fi

# --- check and held: every held ticket --------------------------------------
out=$(
	list_tickets | while IFS= read -r path; do
		id=${path#.factory/items/}
		id=${id%/ticket.md}
		ticket_id_ok "$id" || {
			echo "acceptance-guard: a factory item folder whose name is not a ticket id — not read" >&2
			continue
		}
		open_ticket "$path"
		parse "$FILE" "$path"
		[ "$REC" = none ] && continue
		[ "$STAGE" = done ] && continue
		approved "$path"
		[ -n "$PAIRS" ] || continue
		printf '%s\n' "$PAIRS" | while IFS="$TAB" read -r rid file; do
			if [ "$cmd" = held ]; then
				printf '%s %s\n' "$id" "$file"
				continue
			fi
			want_obj=$(git rev-parse --verify --quiet "$R_COMMIT:$file" 2>/dev/null)
			have_obj=$(git rev-parse --verify --quiet "$head:$file" 2>/dev/null) || {
				# Absent at the head is changed only when the base held the
				# file: the PR deleted it. One absent at both was never
				# brought in — the approved tests live off the base branch
				# until the ticket's build lands them.
				git cat-file -e "$basec:$file" 2>/dev/null || continue
				have_obj=
			}
			[ "$want_obj" = "$have_obj" ] || printf 'changed: %s %s %s\n' "$id" "$rid" "$file"
		done
	done
)
# A fail-closed line from inside the loop ends the answer: it alone is printed.
fc=$(printf '%s\n' "$out" | grep '^fail-closed ' | head -n 1)
if [ -n "$fc" ]; then
	printf '%s\n' "$fc"
	exit 3
fi
out=$(printf '%s\n' "$out" | sed '/^$/d' | sort -u)
[ -n "$out" ] && printf '%s\n' "$out"
[ "$cmd" = check ] && [ -n "$out" ] && exit 1
exit 0
