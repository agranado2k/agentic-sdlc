#!/bin/sh
# stamp.sh — read a ticket's stamp lines, checked, out of an untrusted body.
#
#   sh scripts/stamp.sh <issue-number>
#
# WHAT IT ANSWERS. Which `Tier:`, `Confidence:` and `Domain:` lines a ticket
# carries, and whether the vocabulary checker accepts them. /implement reads
# its ticket's stamp through this script and nothing else: the ticket body is
# untrusted, and a value typed into a quoted shell argument closes the quote
# and runs whatever follows it — so the body never passes through a command an
# agent types, and the only ticket text that leaves this script is lines the
# checker has passed. It replaces a one-line pipe whose status was the
# checker's alone, so a ticket with no stamp and a fetch that failed both
# looked like nothing at all (#331).
#
# EXIT STATUS, one outcome each; stdout carries the stamp and nothing else:
#   0  the checked stamp lines on stdout, as the ticket spells them;
#   2  a refused value, or a usage error: NOTHING on stdout, the reason on
#      stderr naming the field — never the refused text, which is the
#      ticket's, untrusted; read the line in the ticket, quote it only in a
#      report;
#   3  no stamp read: the body carries no stamp lines (a ticket written
#      before the stamp existed — not a refusal), or the checker is gone from
#      this project, which fails CLOSED here: nothing unchecked is printed,
#      and stderr says which of the two it was;
#   4  the fetch failed, twice — one retry, never a loop. Never read it as a
#      missing line: it is a stop.
#
# WHAT IS A STAMP LINE: a BARE `Key: value` line whose key is tier,
# confidence or domain in any case, indented or not — the way the checker
# reads a key, so a line the checker would read is never one this filter
# missed. A markdown-wrapped line (`- Tier: …`, `**Tier:** …`) is not one, to
# the filter as to the checker. The locale is pinned to C here, so
# [[:space:]] is ASCII space whatever the caller runs in: a key dressed in a
# no-break or zero-width space is never lifted.
#
# THE TRACKER is GitHub's CLI: `gh issue view <N> --json body --jq .body`.
# THE CHECKER is scripts/vocab.sh, found from the repository root THIS FILE
# lives in — never the caller's cwd, for the reason scripts/vocab.sh gives: a
# foreign clone's scripts are not run as you.
#
# Shared layer (see VERSION): this file is copied verbatim.
set -u
LC_ALL=C
export LC_ALL

_stamp_here=$(cd "$(dirname "$0")" && pwd -P)

stamp_say() { printf 'x stamp: %s\n' "$*" >&2; }

usage() {
	stamp_say "usage: sh scripts/stamp.sh <issue-number> — the number alone, digits only"
	exit 2
}

[ $# = 1 ] || usage
case $1 in
'' | *[!0123456789]*) usage ;;
esac
issue=$1

_stamp_root=$( (unset GIT_DIR GIT_WORK_TREE && git -C "$_stamp_here" rev-parse --show-toplevel) 2>/dev/null) ||
	_stamp_root=$(dirname "$_stamp_here")
vocab="$_stamp_root/scripts/vocab.sh"

# --- fetch, once more on failure -------------------------------------------
_stamp_tmp=$(mktemp -d "${TMPDIR:-/tmp}/stamp.XXXXXX") || {
	stamp_say "no scratch directory — nothing read"
	exit 4
}
trap 'rm -rf "$_stamp_tmp"' EXIT INT TERM HUP

stamp_fetch() { gh issue view "$issue" --json body --jq .body >"$_stamp_tmp/body"; }
if ! stamp_fetch && ! stamp_fetch; then
	stamp_say "fetching issue #$issue failed twice (the tracker's error is above) — a stop, never a missing line"
	exit 4
fi

# --- lift ------------------------------------------------------------------
tr -d '\r' <"$_stamp_tmp/body" |
	grep -iE '^[[:space:]]*(tier|confidence|domain)[[:space:]]*:' >"$_stamp_tmp/lines"
if [ ! -s "$_stamp_tmp/lines" ]; then
	stamp_say "issue #$issue carries no Tier:, Confidence: or Domain: line — no stamp read, not a refusal"
	exit 3
fi

if [ ! -f "$vocab" ]; then
	stamp_say "the checker $vocab is gone from this project — no stamp read, nothing unchecked printed"
	exit 3
fi

# --- check -----------------------------------------------------------------
if sh "$vocab" <"$_stamp_tmp/lines" 2>/dev/null; then
	cat "$_stamp_tmp/lines"
	exit 0
fi

# Refused. Name the field of each line the checker refuses on its own — the
# key is one of three words this filter matched, so it is safe to print; the
# value is not — and say so when only the lines together are refused.
_named=0
while IFS= read -r line; do
	key=$(printf '%s\n' "$line" | sed 's/^[[:space:]]*\([A-Za-z]*\).*/\1/' | tr 'A-Z' 'a-z')
	printf '%s\n' "$line" | sh "$vocab" 2>/dev/null && continue
	stamp_say "issue #$issue: the $key line is refused — its value is not in the $key vocabulary ($(sh "$vocab" fields 2>/dev/null | sed -n "s/^$key[^:]*: //p")); the value is not printed: it is the ticket's text"
	_named=1
done <"$_stamp_tmp/lines"
[ "$_named" = 1 ] ||
	stamp_say "issue #$issue: the stamp lines are refused together — a field given two values, or a rule across fields; read them in the ticket"
exit 2
