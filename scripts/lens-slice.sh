#!/bin/sh
# lens-slice.sh — the slice of a branch's diff each /review-pr standards lens
# reads, and the whole diff the behavior axis reads.
#
# Usage:  sh scripts/lens-slice.sh <base-ref> <out-dir>
#         sh scripts/lens-slice.sh --areas    < paths, one per line
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
# --areas classifies instead of slicing: it reads paths on stdin, one per
# line, and prints first one `<lens><TAB>` line per lens in roster order, then
# one `<lens><TAB><path>` line per path each lens's rule selects — the review
# areas a path belongs to (the trace's record reader counts a landing toward
# each, #875). Same policy, same refusals, nothing written; it reads no git.
#
# POLICY_BASE (the kit's ADR-0039): set to a ref, the slice form reads the
# lens-slice policy as that ref has it, through scripts/policy.sh, so a pull
# request cannot narrow the lens that reads it — the policy file of the
# slicer's own repository, or a LENS_SLICE_CONFIG naming a judging file there;
# an override outside the judging set is read as given. A policy the base
# cannot give FAILS CLOSED: every lens gets the whole diff, the reader's
# `fail-closed <reason> <path>` line is printed after the slices, and the exit
# is 3. Unset, the working tree's policy is read. --areas never reads a base.
#
# Exit: 0 sliced; 2 caller error (arguments, base, policy) — nothing written;
# 3 failed closed — every lens's slice is the whole diff.
#
# Shared layer (see VERSION): copied verbatim, not edited downstream. Your
# policy goes in scripts/lens-slice.config.sh.

set -eu

ROSTER='security api-crud pattern simplicity reuse-dry test-hygiene'

die() {
	echo "lens-slice: $*" >&2
	exit 2
}

usage="usage: sh scripts/lens-slice.sh <base-ref> <out-dir> | --areas"
mode=slice
case ${1:-} in
--areas)
	[ $# -eq 1 ] || die "$usage"
	mode=areas
	;;
*)
	[ $# -eq 2 ] || die "$usage"
	base_ref=$1
	out=$2
	;;
esac

here=$(dirname "$0")
# load_given — the policy as the working tree has it, or as an override names it.
load_given() {
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
}

# load_at_base — the policy as POLICY_BASE has it (policy_at_base in
# guards.lib.sh beside this script). Sets `failed` to the reader's
# fail-closed line, or to `-` when the base could not be read and the reader
# gave none (its account is on stderr), and leaves the rules empty.
failed=
load_at_base() {
	[ -f "$here/guards.lib.sh" ] || {
		echo "lens-slice: POLICY_BASE is set but guards.lib.sh, the base read, is missing beside the slicer." >&2
		failed=-
		return
	}
	# shellcheck source=./guards.lib.sh
	. "$here/guards.lib.sh"
	_lb_top=$(git rev-parse --show-toplevel 2>/dev/null) && _lb_top=$(cd "$_lb_top" && pwd -P) ||
		die "POLICY_BASE is set but this is not a git working tree"
	if [ -z "${LENS_SLICE_CONFIG:-}" ]; then
		# The cwd repository's base is this slicer's policy only when the
		# slicer is that repository's own; crossing is LENS_SLICE_CONFIG's job.
		_lb_own=$( (unset GIT_DIR GIT_WORK_TREE && git -C "$here" rev-parse --show-toplevel) 2>/dev/null) &&
			_lb_own=$(cd "$_lb_own" && pwd -P) || _lb_own=
		if [ "$_lb_top" != "$_lb_own" ]; then
			echo "lens-slice: refusing to read $_lb_top's lens-slice policy at $POLICY_BASE — it is not the slicer's own repository (${_lb_own:-unknown}). Set LENS_SLICE_CONFIG to cross repositories on purpose." >&2
			failed=-
			return
		fi
	fi
	_lb_rc=0
	policy_at_base "$here" "$_lb_top" "${LENS_SLICE_CONFIG:-}" scripts/lens-slice.config.sh || _lb_rc=$?
	case $_lb_rc in
	0) LENS_SLICE_RULES=$(policy_value "$POLICY_COPY" LENS_SLICE_RULES) ;;
	1) load_given ;;
	*) failed=${POLICY_FAIL:--} ;;
	esac
}

if [ "$mode" = slice ] && [ -n "${POLICY_BASE:-}" ]; then
	load_at_base
else
	load_given
fi
if [ -n "$failed" ]; then
	# Failed closed: no rule is trusted, so no lens is narrowed — the
	# strictest slice is the whole diff, for every lens.
	LENS_SLICE_RULES=
	echo "lens-slice: the lens-slice policy at POLICY_BASE=$POLICY_BASE cannot be read — failing closed, every lens gets the whole diff" >&2
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
elif [ -z "$failed" ]; then
	echo "lens-slice: no rules in LENS_SLICE_RULES — every lens gets the whole diff" >&2
fi

# lens_paths <lens> — the paths on stdin the lens's rule selects; every path when
# the lens has no record.
lens_paths() {
	_s_record=$(printf '%s\n' "$rules" | awk -v l="$1" '$1 == l { print; exit }')
	if [ -z "$_s_record" ]; then
		awk NF
		return
	fi
	_s_inc=$(printf '%s\n' "$_s_record" | awk '{ print $2 }')
	_s_exc=$(printf '%s\n' "$_s_record" | awk '{ print $3 }')
	# Through ENVIRON, not -v: awk -v processes escapes, turning `\.` into `.`.
	LS_INC=$_s_inc LS_EXC=$_s_exc awk '
		NF && $0 ~ ENVIRON["LS_INC"] && (ENVIRON["LS_EXC"] == "" || $0 !~ ENVIRON["LS_EXC"])'
}

if [ "$mode" = areas ]; then
	paths=$(cat)
	for lens in $ROSTER; do printf '%s\t\n' "$lens"; done
	for lens in $ROSTER; do
		printf '%s\n' "$paths" | lens_paths "$lens" | awk -v l="$lens" '{ print l "\t" $0 }'
	done
	exit 0
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
	write "$lens" "$(printf '%s\n' "$changed" | lens_paths "$lens")"
done
write behavior "$changed"

if [ -n "$failed" ]; then
	[ "$failed" = - ] || printf '%s\n' "$failed"
	exit 3
fi
