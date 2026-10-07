#!/bin/sh
# lens-slice.sh — the slice of a branch's diff each /review-pr standards lens
# reads, and the whole diff the behavior axis reads.
#
# Usage:  sh scripts/lens-slice.sh <base-ref> <out-dir>
#
# Writes, under <out-dir> (created if absent):
#   <lens>.diff     for each standards lens of /review-pr's roster —
#                   security api-crud pattern simplicity reuse-dry test-hygiene —
#                   the diff restricted to the changed paths its rule selects;
#   behavior.diff   the whole diff, always: the behavior axis judges what the
#                   change does, and no path rule may hide part of that from it.
# and prints one line per file written: `<name> <changed-file count> <path>`.
# A count of 0 is an empty slice: nothing in that lens's lane changed.
#
# The diff is merge-base(<base-ref>, HEAD)..HEAD, the branch's own commits —
# the scope /review-pr's step 0 locks.
#
# WHICH PATHS A LENS SEES is policy, not code: LENS_SLICE_RULES in
# scripts/lens-slice.config.sh (or the file $LENS_SLICE_CONFIG names), one
# `<lens> <include-ERE> [<exclude-ERE>]` record per line, whitespace-separated
# (an ERE needing a space spells it `[ ]`), matched by awk against each changed
# path: a path the include matches and the exclude does not is in the slice. A
# lens with no record gets the whole diff — a lens is never starved by an
# omission — and with no rules at all the slicer says so on stderr and every
# lens gets the whole diff. A record naming a lens not on the roster is
# refused (exit 2) rather than ignored: a typo would otherwise widen a slice
# in silence.
#
# Exit: 0 sliced; 2 caller error (arguments, base, policy) — nothing written.
#
# Shared layer (see VERSION): copied verbatim, not edited downstream. Your
# policy goes in scripts/lens-slice.config.sh.

set -eu

ROSTER='security api-crud pattern simplicity reuse-dry test-hygiene'

die() {
	echo "lens-slice: $*" >&2
	exit 2
}

[ $# -eq 2 ] || die "usage: sh scripts/lens-slice.sh <base-ref> <out-dir>"
base_ref=$1
out=$2

here=$(dirname "$0")
if [ -n "${LENS_SLICE_CONFIG:-}" ]; then
	[ -f "$LENS_SLICE_CONFIG" ] || die "LENS_SLICE_CONFIG=$LENS_SLICE_CONFIG does not exist"
	# A bare name would be searched on PATH by `.`: anchor it to the cwd.
	case $LENS_SLICE_CONFIG in
	*/*) . "$LENS_SLICE_CONFIG" ;;
	*) . "./$LENS_SLICE_CONFIG" ;;
	esac
elif [ -f "$here/lens-slice.config.sh" ]; then
	. "$here/lens-slice.config.sh"
fi
rules=${LENS_SLICE_RULES:-}

# Refuse a record for a lens off the roster, or one with more than three
# fields, before anything is written.
if [ -n "$rules" ]; then
	bad=$(printf '%s\n' "$rules" | awk -v roster=" $ROSTER " '
		NF && index(roster, " " $1 " ") == 0 { print $1 }')
	[ -z "$bad" ] || die "LENS_SLICE_RULES names a lens not on the roster ($ROSTER): $(printf '%s' "$bad" | tr '\n' ' ')"
	long=$(printf '%s\n' "$rules" | awk 'NF > 3 { print $1 }')
	[ -z "$long" ] || die "LENS_SLICE_RULES has a record of more than three fields (lens include exclude): $(printf '%s' "$long" | tr '\n' ' ')"
else
	echo "lens-slice: no rules in LENS_SLICE_RULES — every lens gets the whole diff" >&2
fi

base=$(git merge-base "$base_ref" HEAD 2>/dev/null) || die "cannot resolve merge-base($base_ref, HEAD)"
# -z: unquoted names. Without it git quotes a non-ASCII or special name, and
# the quoted form matches no pathspec, dropping the file from every slice.
changed=$(git diff --name-only -z "$base" HEAD | tr '\0' '\n')

mkdir -p "$out" || die "cannot create $out"

# write <name> <newline-separated paths> — the diff over exactly those paths.
write() {
	_w_name=$1
	_w_paths=$2
	_w_file="$out/$_w_name.diff"
	if [ -z "$_w_paths" ]; then
		: >"$_w_file"
		_w_n=0
	else
		# One literal pathspec per path: no glob or magic in a file name widens it.
		set --
		_w_ifs=$IFS
		IFS='
'
		set -f # the split must not glob a name like `a[1].md` against the cwd
		for _w_p in $_w_paths; do set -- "$@" ":(literal)$_w_p"; done
		set +f
		IFS=$_w_ifs
		_w_n=$#
		git -c core.quotePath=false diff "$base" HEAD -- "$@" >"$_w_file"
	fi
	printf '%s %s %s\n' "$_w_name" "$_w_n" "$_w_file"
}

for lens in $ROSTER; do
	record=$(printf '%s\n' "$rules" | awk -v l="$lens" '$1 == l { print; exit }')
	if [ -z "$record" ]; then
		write "$lens" "$changed"
		continue
	fi
	inc=$(printf '%s\n' "$record" | awk '{ print $2 }')
	exc=$(printf '%s\n' "$record" | awk '{ print $3 }')
	# Through ENVIRON, not -v: awk -v processes escapes, turning `\.` into `.`.
	sel=$(printf '%s\n' "$changed" | LS_INC=$inc LS_EXC=$exc awk '
		NF && $0 ~ ENVIRON["LS_INC"] && (ENVIRON["LS_EXC"] == "" || $0 !~ ENVIRON["LS_EXC"])')
	write "$lens" "$sel"
done
write behavior "$changed"
