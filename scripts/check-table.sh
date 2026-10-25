#!/bin/sh
# check-table.sh — the check-table reader: does every requirement a ticket
# covers have one passing row, at the tier the ticket stamped, in its PR's
# check table?
#
#   sh scripts/check-table.sh <pr-body-file> <ticket-body-file>
#
# WHAT IT ANSWERS. /implement writes a CHECK TABLE into the body of every PR
# it opens for a ticket with a `Covers:` line (the kit's ADR-0037 clause 9):
# per covered requirement, the test tier that checked it, the result and the
# evidence. This reader holds that table to the ticket. It runs no tracker or
# forge command: the caller fetches both bodies into files and names them.
#
# WHAT IT READS. Of the TICKET body, its one bare `Covers:` line (none, or
# `none (<reason>)`, covers nothing; two, or a value that is not a list of
# bounded ids, is refused) and its bare `Test-tier: <id> <tier>` lines, held
# by scripts/vocab.sh to the vocabulary policy — one tier per id — and to the
# policy's published bound. Of the PR body, the part ABOVE the
# `<!-- explain-diff-appendix -->` marker line (below it is the author's
# narrative), outside every fence: the one `<!-- check-table -->` marker line,
# then, on the next lines, the exact header
#   | Requirement | Test tier | Result | Evidence |
# a separator row of four cells, and the rows, up to the first line that does
# not open with `|`, at most 64. A row is four cells:
#   Requirement  a bounded requirement id (scripts/requirement.lib.sh);
#   Test tier    a token of the policy's `test-tier` field;
#   Result       a token of the policy's `result` field;
#   Evidence     `<path>::<test>@<sha>` — path and test in the plain set
#                (letters, digits, `.`, `/`, `_`, `-`), the sha 7 to 40 hex
#                digits; or an `https://` URL in the plain set plus `:`, `#`,
#                `?`, `=`, `&` and `%`, at most 200 characters; or `-`, only
#                on a `skipped` row.
#
# WHAT IT PRINTS — requirement ids, tokens and row numbers, and nothing else.
# No cell's text and no line of either body reaches stdout or stderr, so it is
# safe to run on untrusted bodies without reading their prose into a session.
#
# EXIT STATUS, one outcome each:
#   0  every covered id has exactly one row, its result `pass` and its tier
#      the ticket's stamp (any tier, for an id the ticket stamps none for):
#      NOTHING printed;
#   1  a gap, one `<word>: <id>` line each: per covered id in the `Covers:`
#      order, `missing-row:` (no row), `tier-differs:` (its row's tier is not
#      the stamp), `fail:` or `skipped:` (its row's result), and `extra-row:`
#      (a second row for it); then `extra-row:` per id the ticket does not
#      cover, in the table's order, each once;
#   2  a row that breaks the grammar or a table past 64 rows — stderr names
#      the row number (`row <n>`, counted from the first row under the
#      separator), or the header or the separator row; a body with two
#      check-table markers; a ticket whose `Covers:` or `Test-tier:` lines are
#      refused; a usage error or an unreadable file. NOTHING on stdout;
#   3  the PR body carries no check table: stderr says so, stdout empty.
#
# THE GRAMMAR is not spelled here twice: the id, the Covers: value and the
# fence are scripts/requirement.lib.sh's, the tokens and the bound are
# scripts/vocab.sh's (its `fields`), both read from beside this script, and
# without either the reader refuses (exit 2) rather than read nothing.
#
# Shared layer, beside scripts/coverage.sh: /implement writes the table, and
# the review and iteration skills read it through this script and no other way.
set -u
LC_ALL=C
export LC_ALL

ct_say() { printf 'x check-table: %s\n' "$*" >&2; }

usage() {
	ct_say "usage: sh scripts/check-table.sh <pr-body-file> <ticket-body-file>"
	exit 2
}

here=$(dirname "$0")
grammar="$here/requirement.lib.sh"
vocab="$here/vocab.sh"
[ -r "$grammar" ] || {
	ct_say "scripts/requirement.lib.sh, the requirement grammar, is missing beside this script — restore it from the kit"
	exit 2
}
# shellcheck disable=SC1090
. "$grammar"
for fn in req_covers_ids fence_strip; do
	command -v "$fn" >/dev/null 2>&1 || {
		ct_say "scripts/requirement.lib.sh defines no $fn — restore it from the kit"
		exit 2
	}
done
[ -r "$vocab" ] || {
	ct_say "scripts/vocab.sh, the vocabulary checker, is missing beside this script — restore it from the kit"
	exit 2
}

[ $# -eq 2 ] || usage
pr=$1
tk=$2
for f in "$pr" "$tk"; do
	[ -f "$f" ] && [ -r "$f" ] || {
		ct_say "a body is not a readable file — fetch the PR body and the ticket body into files first"
		exit 2
	}
done

# --- the vocabulary ---------------------------------------------------------
fields=$(sh "$vocab" fields 2>/dev/null) || {
	ct_say "scripts/vocab.sh could not print its fields — the vocabulary policy is broken"
	exit 2
}
tiers=$(printf '%s\n' "$fields" | sed -n 's/^test-tier (keyed): //p')
results=$(printf '%s\n' "$fields" | sed -n 's/^result: //p')
[ -n "$tiers" ] && [ -n "$results" ] || {
	ct_say "the vocabulary policy declares no test-tier or no result field — add them (UPDATING.md, 0.91.0)"
	exit 2
}
bound=$(printf '%s\n' "$fields" | sed -n 's/^bound test-tier: //p')
[ -n "$bound" ] || bound=$(printf '%s\n' "$fields" | sed -n 's/^bound: //p')
[ -n "$bound" ] || bound=8

# --- the ticket -------------------------------------------------------------
tbody=$(tr -d '\r' <"$tk")
lines=$(printf '%s\n' "$tbody" | grep '^Covers:')
n=$(printf '%s' "$lines" | grep -c '')
covered=''
case $n in
0) ;;
1)
	value=$(printf '%s\n' "$lines" | sed 's/^Covers:[[:space:]]*//; s/[[:space:]]*$//')
	covered=$(req_covers_ids "$value") || {
		ct_say "the ticket's Covers: line is neither a list of requirement ids nor none (prefactor|open-issue|release)"
		exit 2
	}
	;;
*)
	ct_say "the ticket carries $n Covers: lines — a ticket carries one"
	exit 2
	;;
esac

stamps=$(printf '%s\n' "$tbody" | grep '^Test-tier:')
if [ -n "$stamps" ]; then
	n=$(printf '%s\n' "$stamps" | grep -c '')
	[ "$n" -le "$bound" ] || {
		ct_say "the ticket carries $n Test-tier: lines — the policy's bound is $bound"
		exit 2
	}
	printf '%s\n' "$stamps" | sh "$vocab" check >/dev/null 2>&1 || {
		ct_say "the ticket's Test-tier: lines are refused by scripts/vocab.sh — run it on them to see why"
		exit 2
	}
	stamps=$(printf '%s\n' "$stamps" | awk '{ print $2, $3 }')
fi

# --- the table --------------------------------------------------------------
# Outside every fence, above the appendix marker.
above=$(tr -d '\r' <"$pr" | fence_strip | awk '/^[ \t]*<!-- explain-diff-appendix -->[ \t]*$/ { exit } { print }')
marker='^[ \t]*<!-- check-table -->[ \t]*$'
m=$(printf '%s\n' "$above" | grep -c "$marker")
[ "$m" -gt 0 ] || {
	ct_say "the PR body carries no check table (no <!-- check-table --> marker line above the explain-diff marker)"
	exit 3
}
[ "$m" -eq 1 ] || {
	ct_say "the PR body carries $m check-table markers — a body carries one table"
	exit 2
}

# The parse: `ok <id> <tier> <result>` per row, or one `bad <what>` line.
rows=$(printf '%s\n' "$above" | awk -v marker="$marker" -v tiers=" $tiers " -v results=" $results " \
	-v amax="$REQ_ID_AREA_MAX" -v nmax="$REQ_ID_NUM_MAX" '
	function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
	function idok(s,    a, num) {
		if (s !~ /^([a-z][a-z0-9-]*\/)?R[1-9][0-9]*$/) return 0
		a = s; if (!sub(/\/.*/, "", a)) a = ""
		num = s; sub(/^.*R/, "", num)
		return length(a) <= amax && length(num) <= nmax
	}
	function evok(s, result,    sha) {
		if (s == "-") return result == "skipped"
		if (s ~ pin) { sha = s; sub(/^.*@/, "", sha); return length(sha) >= 7 && length(sha) <= 40 }
		return s ~ url && length(s) <= 200
	}
	BEGIN {
		pin = "^[A-Za-z0-9._/-]+::[A-Za-z0-9._/-]+@[0-9a-fA-F]+$"
		url = "^https://[A-Za-z0-9._/:#?=&%-]+$"
		head = "| Requirement | Test tier | Result | Evidence |"
	}
	state == 0 { if ($0 ~ marker) state = 1; next }
	state == 1 { if (trim($0) != head) { print "bad the header row"; exit } state = 2; next }
	state == 2 {
		if (trim($0) !~ /^\|([ \t]*:?-+:?[ \t]*\|){4}$/) { print "bad the separator row"; exit }
		state = 3; next
	}
	state == 3 {
		if (substr($0, 1, 1) != "|") exit
		r++
		if (r > 64) { print "bad row " r " (a table holds at most 64 rows)"; exit }
		line = trim($0)
		if (line !~ /\|$/) { print "bad row " r; exit }
		line = substr(line, 2, length(line) - 2)
		if (split(line, c, "|") != 4) { print "bad row " r; exit }
		id = trim(c[1]); tier = trim(c[2]); res = trim(c[3]); ev = trim(c[4])
		if (!idok(id) || index(tiers, " " tier " ") == 0 || tier == "" ||
			index(results, " " res " ") == 0 || res == "" || !evok(ev, res)) {
			print "bad row " r; exit
		}
		print "ok", id, tier, res
	}
	END { if (state == 1) print "bad the header row"; else if (state == 2) print "bad the separator row" }
')
case $rows in
bad* | *"
bad"*)
	what=$(printf '%s\n' "$rows" | sed -n 's/^bad //p' | head -n 1)
	ct_say "$what breaks the check table's grammar (the kit's ADR-0037 clause 9)"
	exit 2
	;;
esac

# --- the verdict ------------------------------------------------------------
gap=0
say() { printf '%s: %s\n' "$1" "$2"; gap=1; }
for id in $covered; do
	mine=$(printf '%s\n' "$rows" | awk -v id="$id" '$1 == "ok" && $2 == id')
	k=$(printf '%s' "$mine" | grep -c '')
	[ "$k" -gt 0 ] || { say missing-row "$id"; continue; }
	set -- $(printf '%s\n' "$mine" | head -n 1)
	want=$(printf '%s\n' "$stamps" | awk -v id="$id" '$1 == id { print $2; exit }')
	[ -z "$want" ] || [ "$want" = "$3" ] || say tier-differs "$id"
	case $4 in
	fail) say fail "$id" ;;
	skipped) say skipped "$id" ;;
	esac
	[ "$k" -eq 1 ] || say extra-row "$id"
done
for id in $(printf '%s\n' "$rows" | awk '$1 == "ok" && !seen[$2]++ { print $2 }'); do
	printf '%s\n' "$covered" | grep -Fqx -- "$id" || say extra-row "$id"
done
exit "$gap"
