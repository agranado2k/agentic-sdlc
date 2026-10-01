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
#   0  the checked stamp lines on stdout, as the ticket spells them. A line
#      whose field the policy does not declare is one the checker would
#      ignore, so it is never printed: stderr names its field, and with one
#      dropped the exit is 0 only when the Tier: line was checked and printed;
#   2  a refused value, or a usage error: NOTHING on stdout, the reason on
#      stderr naming the field — never the refused text, which is the
#      ticket's, untrusted; read the line in the ticket, quote it only in a
#      report;
#   3  no stamp read, NOTHING on stdout, and stderr says which case: the
#      body carries no stamp lines (a ticket written before the stamp
#      existed — not a refusal); the checker is gone from this project, or
#      cannot run (its `fields` fails — a policy file missing or malformed —
#      or its check exits with anything but 0 or 2), which fails CLOSED;
#      or a stamp line names a field the policy does not declare, and no
#      Tier: line was left to check. Only a 2 from the check of the lines
#      themselves is a refusal;
#   4  the fetch failed, twice — one retry, never a loop. Never read it as a
#      missing line: it is a stop. (A signal exits 128 + its number, nothing
#      printed — never a verdict.)
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
# The EXIT trap cleans up; a signal EXITS, so the script never reads on with
# its scratch directory gone (a handler that only cleaned up would return).
trap 'rm -rf "$_stamp_tmp"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

stamp_fetch() { gh issue view "$issue" --json body --jq .body >"$_stamp_tmp/body"; }
if ! stamp_fetch && ! stamp_fetch; then
	stamp_say "fetching issue #$issue failed twice (the tracker's error is above) — a stop, never a missing line"
	exit 4
fi

# --- the checker: present, runnable, and what it declares --------------------
# Asked BEFORE anything is lifted. A checker that cannot answer `fields` —
# gone, or a policy file missing or malformed — cannot check either, and its
# exit 2 there is not a refusal of the ticket: exit 3, nothing printed.
if [ ! -f "$vocab" ]; then
	stamp_say "the checker $vocab is gone from this project — no stamp read, nothing unchecked printed"
	exit 3
fi
if ! sh "$vocab" fields >"$_stamp_tmp/fields" 2>/dev/null; then
	stamp_say "the checker $vocab cannot run here (its policy file missing or malformed?) — no stamp read, nothing unchecked printed"
	exit 3
fi
# stamp_declared <key> — does the policy declare the field?
stamp_declared() { grep -qE "^$1( \\(open\\))?: " "$_stamp_tmp/fields"; }
# stamp_key <line> — the line's key, lower-cased: one of the three words the
# filter matched, so it is safe to print; the value is not.
stamp_key() { printf '%s\n' "$1" | sed 's/^[[:space:]]*\([A-Za-z]*\).*/\1/' | tr 'A-Z' 'a-z'; }

# --- lift ------------------------------------------------------------------
tr -d '\r' <"$_stamp_tmp/body" |
	grep -iE '^[[:space:]]*(tier|confidence|domain)[[:space:]]*:' >"$_stamp_tmp/lifted"
if [ ! -s "$_stamp_tmp/lifted" ]; then
	stamp_say "issue #$issue carries no Tier:, Confidence: or Domain: line — no stamp read, not a refusal"
	exit 3
fi

# A line whose field the policy does not declare is one the checker would
# ignore — so it is never checked, and never printed.
_dropped=0
: >"$_stamp_tmp/lines"
while IFS= read -r line; do
	key=$(stamp_key "$line")
	if stamp_declared "$key"; then
		printf '%s\n' "$line" >>"$_stamp_tmp/lines"
	else
		stamp_say "issue #$issue: the $key line names a field this project's policy does not declare — not checked, not printed"
		_dropped=1
	fi
done <"$_stamp_tmp/lifted"

# --- check -----------------------------------------------------------------
_rc=0
[ -s "$_stamp_tmp/lines" ] && { sh "$vocab" <"$_stamp_tmp/lines" 2>/dev/null || _rc=$?; }
case $_rc in
0)
	if [ "$_dropped" = 1 ] && ! grep -qiE '^[[:space:]]*tier[[:space:]]*:' "$_stamp_tmp/lines"; then
		stamp_say "issue #$issue: no Tier: line was checked — no stamp read"
		exit 3
	fi
	cat "$_stamp_tmp/lines"
	exit 0
	;;
2) ;;
*)
	stamp_say "the checker $vocab cannot run the check (exit $_rc) — no stamp read, nothing unchecked printed"
	exit 3
	;;
esac

# Refused. Name the field of each line the checker refuses on its own, and
# say so when only the lines together are refused.
_named=0
while IFS= read -r line; do
	key=$(stamp_key "$line")
	printf '%s\n' "$line" | sh "$vocab" 2>/dev/null && continue
	stamp_say "issue #$issue: the $key line is refused — its value is not in the $key vocabulary ($(sed -n "s/^$key[^:]*: //p" "$_stamp_tmp/fields")); the value is not printed: it is the ticket's text"
	_named=1
done <"$_stamp_tmp/lines"
[ "$_named" = 1 ] ||
	stamp_say "issue #$issue: the stamp lines are refused together — a field given two values, or a rule across fields; read them in the ticket"
exit 2
