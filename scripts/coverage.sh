#!/bin/sh
# coverage.sh — the coverage check: which requirements no ticket covers, and
# which tickets cover nothing.
#
#   sh scripts/coverage.sh <prd-body-file> <ticket-file>...
#
# WHAT IT ANSWERS. /to-tickets runs it before its quiz (ADR-0012 clause 4) on
# the PRD body — the pre-screen's scratch copy — and on each drafted ticket's
# body, one file per ticket, the file named by the ticket's label (its draft
# number). It names every requirement no ticket's `Covers:` line lists, and
# every ticket that lists none without declaring itself exempt; the quiz shows
# both lists.
#
# WHAT IT READS — ids, and nothing else. Of the PRD body, the REQUIREMENT
# LINES only: a line that opens, at its first column, with a requirement id
# and a full stop — `R<n>.` or `<area>/R<n>.`, the area `[a-z][a-z0-9-]*`,
# n from 1 — followed by a space or the line's end. An id is BOUNDED: the
# area at most 32 characters, the number at most 6 digits. A would-be id past
# either bound is not an id — its line is not a requirement line, and a
# `Covers:` line holding one is malformed (exit 2) — so no id can carry prose
# to an output stream. Of a ticket, its one
# bare `Covers:` line only, which is either a comma-separated list of those
# ids or an exemption, `Covers: none (prefactor)`, `none (open-issue)` or
# `none (release)`. An id anywhere else — prose, a heading, a bullet, an
# indented line, a ticket's own copy of a requirement line, a wrapped
# `**Covers:**` — is never read. Ids compare as written: `R10` does not cover
# `process/R10`.
#
# WHAT IT PRINTS — ids and labels, and nothing else. A requirement id it
# prints matched the bounded id shape; a label it prints is a file name the caller
# chose and held to `[A-Za-z0-9._-]`. No line of either file ever reaches
# stdout or stderr, so the check is safe to run on an untrusted body without
# reading its prose into the session (PRD #527 R7).
#
# EXIT STATUS, one outcome each:
#   0  every requirement covered and every ticket covering or exempt:
#      NOTHING printed;
#   1  a gap: `uncovered: <id>` per requirement no ticket covers, in the PRD's
#      order, then `orphan: <label>` per non-exempt ticket that covers
#      nothing, in argument order;
#   2  a usage error, an unreadable file, a label outside the label shape, or
#      a `Covers:` line that is neither an id list nor an exemption, or a
#      ticket with two: NOTHING on stdout, stderr naming the label, never the
#      line — every ticket is checked before any gap is printed;
#   3  the PRD body carries no requirement lines (a PRD written before them):
#      nothing to check, stderr says so, stdout empty.
#
# Shipped to every consumer beside scripts/vocab.sh: /to-tickets ships
# unstamped and calls it by this name.
set -u
LC_ALL=C
export LC_ALL

cov_say() { printf 'x coverage: %s\n' "$*" >&2; }

usage() {
	cov_say "usage: sh scripts/coverage.sh <prd-body-file> <ticket-file>... — one file per drafted ticket, named by its label"
	exit 2
}

# The id shape, one ERE: an optional area of at most AREA_MAX characters,
# then R and a number from 1 of at most NUM_MAX digits.
AREA_MAX=32
NUM_MAX=6
ID="([a-z][a-z0-9-]{0,$((AREA_MAX - 1))}/)?R[1-9][0-9]{0,$((NUM_MAX - 1))}"

[ $# -ge 2 ] || usage
prd=$1
shift
[ -f "$prd" ] && [ -r "$prd" ] || {
	cov_say "the PRD body is not a readable file"
	exit 2
}

# The requirement ids, in the PRD's order, each once. The bounds are checked
# by length, not by an interval in the pattern: not every awk reads one.
reqs=$(awk -v id="^([a-z][a-z0-9-]*/)?R[1-9][0-9]*\\\\." -v amax="$AREA_MAX" -v nmax="$NUM_MAX" '
	{ sub(/\r$/, "") }
	$0 ~ id "$" || $0 ~ id " " {
		r = $0; sub(/\..*/, "", r)
		a = r; if (!sub(/\/.*/, "", a)) a = ""
		n = r; sub(/^.*R/, "", n)
		if (length(a) > amax || length(n) > nmax) next
		if (!seen[r]++) print r
	}
' "$prd") || {
	cov_say "the PRD body could not be read"
	exit 2
}
[ -n "$reqs" ] || {
	cov_say "the PRD body carries no requirement lines — nothing to check"
	exit 3
}

# Every ticket is checked before any gap is printed: a refusal leaves stdout
# empty.
covered=''
orphans=''
for t; do
	label=${t##*/}
	case $label in
	'' | *[!A-Za-z0-9._-]*)
		cov_say "a ticket file's name is not a label ([A-Za-z0-9._-]) — name each file by its draft number"
		exit 2
		;;
	esac
	[ -f "$t" ] && [ -r "$t" ] || {
		cov_say "ticket $label: not a readable file"
		exit 2
	}
	lines=$(tr -d '\r' <"$t" | grep '^Covers:')
	n=$(printf '%s' "$lines" | grep -c '')
	case $n in
	0)
		orphans="$orphans$label
"
		continue
		;;
	1) ;;
	*)
		cov_say "ticket $label: $n Covers: lines — a ticket carries one"
		exit 2
		;;
	esac
	value=$(printf '%s\n' "$lines" | sed 's/^Covers:[[:space:]]*//; s/[[:space:]]*$//')
	if printf '%s\n' "$value" | grep -Eqx 'none \((prefactor|open-issue|release)\)'; then
		continue
	fi
	printf '%s\n' "$value" | grep -Eqx "$ID( *, *$ID)*" || {
		cov_say "ticket $label: its Covers: line is neither a list of requirement ids nor none (prefactor|open-issue|release)"
		exit 2
	}
	covered="$covered$(printf '%s\n' "$value" | tr ',' '\n' | tr -d ' ')
"
done

gap=0
for r in $reqs; do
	printf '%s' "$covered" | grep -Fqx -- "$r" && continue
	printf 'uncovered: %s\n' "$r"
	gap=1
done
for o in $orphans; do
	printf 'orphan: %s\n' "$o"
	gap=1
done
exit "$gap"
