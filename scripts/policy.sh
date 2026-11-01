#!/bin/sh
# policy.sh — the POLICY READER: a judging file as the base branch has it,
# never as the pull request left it, and failing closed when it cannot say.
#
#   sh scripts/policy.sh read <path> --base <ref>
#   sh scripts/policy.sh touched <base> <head>
#   sh scripts/policy.sh thresholds --base <ref>
#
# A guard, gate or review reader that judges a pull request reads its policy
# through this script, so no pull request can loosen the rule that judges it.
#
# read        writes the base's version of one JUDGING FILE to a copy under the
#             repository's git directory — policy/<base commit>/<path>, so a
#             module's relative import of its sibling resolves — prints the
#             copy's absolute path, and exits 0. A file whose name ends `.sh`
#             must pass `sh -n` there.
# touched     prints, sorted, one per line, each judging-set path the diff from
#             merge-base(<base>, <head>) to <head> adds, modifies, deletes, or
#             renames from or to; exit 1 when it printed one, 0 when none.
# thresholds  prints `miss-rate-below <n>` then `precision-floor <n>`, read from
#             the risk policy (scripts/risk.config.sh) at the base; exit 0.
#
# THE JUDGING SET, matched by whole repository-relative path: every file
# directly under scripts/ whose name ends `.config.sh`; the docs gate's
# scripts/docs-conformance/config.mjs and local-vocabulary.mjs; every file
# directly under .githooks/ and .github/workflows/; the risk policy; and each
# path the risk policy's RISK_JUDGING_EXTRA names AT THE BASE. A file of the
# same name anywhere else is not in it.
#
# FAIL CLOSED. Any answer it cannot give is ONE line on stdout,
#   fail-closed <reason> <path>
# and exit 3, the reason one of: no-base (the ref names no commit here),
# missing (absent at the base), unreadable (not a regular file there, or git
# cannot produce it), invalid (a `.sh` file fails `sh -n`, or a threshold or an
# extra path is out of shape). The line carries nothing read from any file.
# When the risk policy fails closed during `touched`, the paths the rest of the
# set selects print first, then its line, and the exit is 3. `touched` with
# no merge base between the two refs (unrelated histories, a shallow clone)
# answers `fail-closed no-base scripts/risk.config.sh`, and a diff git cannot
# produce `fail-closed unreadable scripts/risk.config.sh`. When `read` is
# asked for a path outside the fixed set and the risk policy fails closed, its
# line answers: the reader cannot say the path is not judged.
#
# Exit: 0 the answer; 1 `touched` found judging files; 2 a caller error, or a
# path outside the judging set — nothing on stdout, nothing written; 3 failed
# closed.
#
# IT READS GIT'S OBJECTS ONLY: no checkout, no fetch, no read of the working
# tree — an unfetched ref is no-base, and the working tree's copy of a file is
# never a fallback. A shell judging file is evaluated only in a child process,
# so nothing it sets, defines or changes reaches this script or its caller.
#
# Shared layer (see VERSION): copied verbatim, not edited downstream. Your
# thresholds and extra judging paths go in scripts/risk.config.sh.

set -uf

RISK_POLICY=scripts/risk.config.sh

die() {
	echo "policy: $*" >&2
	exit 2
}

usage="usage: sh scripts/policy.sh read <path> --base <ref> | touched <base> <head> | thresholds --base <ref>"

git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"

# plain_path <path> — 0 for a repository-relative path with no empty, `.` or
# `..` segment, and no leading or trailing `/`.
plain_path() {
	case $1 in
	'' | /* | */ | *//* | . | .. | ./* | ../* | */. | */.. | */./* | */../*) return 1 ;;
	esac
	return 0
}

# _directly_under <dir/> <path> — 0 when <path> is one entry directly in <dir/>.
_directly_under() {
	case $2 in
	"$1"*)
		case ${2#"$1"} in '' | */*) return 1 ;; esac
		return 0
		;;
	esac
	return 1
}

# in_fixed <path> — 0 when the path is in the judging set by place and suffix.
in_fixed() {
	plain_path "$1" || return 1
	case $1 in
	"$RISK_POLICY" | scripts/docs-conformance/config.mjs | scripts/docs-conformance/local-vocabulary.mjs) return 0 ;;
	*.config.sh) _directly_under scripts/ "$1" && return 0 ;;
	esac
	_directly_under .githooks/ "$1" && return 0
	_directly_under .github/workflows/ "$1" && return 0
	return 1
}

# base_commit <ref> — the commit a ref names here, or status 1.
base_commit() {
	case $1 in '' | -*) return 1 ;; esac
	git rev-parse --verify --quiet "$1^{commit}" 2>/dev/null
}

store=
# copy_root — the absolute directory copies live under, made once.
copy_root() {
	[ -n "$store" ] && return 0
	_cr_gd=$(git rev-parse --git-common-dir) || die "no git directory"
	store=$(cd "$_cr_gd" && pwd)/policy
	mkdir -p "$store" || die "cannot create $store"
}

tmp=
trap '[ -n "$tmp" ] && rm -f "$tmp"' EXIT
trap 'exit 130' INT TERM HUP

# fetch <commit> <path> — write the base's copy; set COPY to its path, or
# REASON to the fail-closed reason. Status 0 on a copy.
fetch() {
	COPY= REASON=
	_f_entry=$(git --literal-pathspecs ls-tree --full-tree -z "$1" -- "$2" 2>/dev/null | tr '\0' '\n' | head -n 1)
	if [ -z "$_f_entry" ]; then
		if git cat-file -e "$1^{tree}" 2>/dev/null; then REASON=missing; else REASON=unreadable; fi
		return 1
	fi
	_f_meta=${_f_entry%%"	"*}
	_f_name=${_f_entry#*"	"}
	[ "$_f_name" = "$2" ] || {
		REASON=missing
		return 1
	}
	_f_mode=${_f_meta%% *}
	_f_obj=${_f_meta##* }
	case $_f_mode in
	100644 | 100755) ;;
	*)
		REASON=unreadable
		return 1
		;;
	esac
	copy_root
	tmp=$(mktemp "$store/.tmp.XXXXXX") || die "cannot write under $store"
	if ! git cat-file blob "$_f_obj" >"$tmp" 2>/dev/null; then
		rm -f "$tmp"
		tmp=
		REASON=unreadable
		return 1
	fi
	case $2 in
	*.sh)
		if ! sh -n "$tmp" >/dev/null 2>&1; then
			rm -f "$tmp"
			tmp=
			REASON=invalid
			return 1
		fi
		;;
	esac
	_f_dest=$store/$1/$2
	mkdir -p "$(dirname "$_f_dest")" && mv -f "$tmp" "$_f_dest" || die "cannot write $_f_dest"
	tmp=
	COPY=$_f_dest
	return 0
}

# risk_eval <commit> — read the risk policy at the commit, in a child process.
# Sets RISK_REASON (empty on success), MISS_RATE, FLOOR and EXTRA (one judging
# path per line). Every source of extra judging paths is read here, at the base.
risk_eval() {
	RISK_REASON= MISS_RATE= FLOOR= EXTRA=
	if ! fetch "$1" "$RISK_POLICY"; then
		RISK_REASON=$REASON
		return 1
	fi
	# The child sources the base's copy and prints only what it validated —
	# two whole percents (or `x`) then the extra paths — through `command`,
	# so a function the policy defines cannot speak for it.
	_re_out=$(sh -c '
		. "$1" >/dev/null 2>&1 </dev/null
		set -f
		for v in "${RISK_MISS_RATE_BELOW-}" "${RISK_PRECISION_FLOOR-}"; do
			case $v in
			[0-9] | [1-9][0-9] | 100) command printf "%s\n" "$v" ;;
			*) command printf "x\n" ;;
			esac
		done
		for p in ${RISK_JUDGING_EXTRA-}; do command printf "%s\n" "$p"; done
		command printf "end\n"
	' _ "$COPY" 2>/dev/null) || _re_out=
	MISS_RATE=$(printf '%s\n' "$_re_out" | sed -n 1p)
	FLOOR=$(printf '%s\n' "$_re_out" | sed -n 2p)
	_re_last=$(printf '%s\n' "$_re_out" | sed -n '$p')
	for _re_n in "$MISS_RATE" "$FLOOR"; do
		case $_re_n in
		[0-9] | [1-9][0-9] | 100) ;;
		*)
			RISK_REASON=invalid
			return 1
			;;
		esac
	done
	[ "$_re_last" = end ] || {
		RISK_REASON=invalid
		return 1
	}
	EXTRA=$(printf '%s\n' "$_re_out" | sed -e '1,2d' -e '$d')
	_re_ifs=$IFS
	IFS='
'
	for _re_p in $EXTRA; do
		plain_path "$_re_p" || {
			IFS=$_re_ifs
			RISK_REASON=invalid
			return 1
		}
	done
	IFS=$_re_ifs
	return 0
}

# in_extra <path> — 0 when the path is on the extra list risk_eval read.
in_extra() { [ -n "$EXTRA" ] && printf '%s\n' "$EXTRA" | grep -qxF -- "$1"; }

cmd=${1:-}
case $cmd in
read)
	[ $# -eq 4 ] && [ "$3" = --base ] || die "$usage"
	path=$2
	ref=$4
	plain_path "$path" || die "not a judging file: a plain repository-relative path is required"
	commit=$(base_commit "$ref") || {
		printf 'fail-closed no-base %s\n' "$path"
		exit 3
	}
	if ! in_fixed "$path"; then
		if ! risk_eval "$commit"; then
			printf 'fail-closed %s %s\n' "$RISK_REASON" "$RISK_POLICY"
			exit 3
		fi
		in_extra "$path" || die "not a judging file: $path"
	fi
	fetch "$commit" "$path" || {
		printf 'fail-closed %s %s\n' "$REASON" "$path"
		exit 3
	}
	printf '%s\n' "$COPY"
	exit 0
	;;
thresholds)
	[ $# -eq 3 ] && [ "$2" = --base ] || die "$usage"
	commit=$(base_commit "$3") || {
		printf 'fail-closed no-base %s\n' "$RISK_POLICY"
		exit 3
	}
	risk_eval "$commit" || {
		printf 'fail-closed %s %s\n' "$RISK_REASON" "$RISK_POLICY"
		exit 3
	}
	printf 'miss-rate-below %s\nprecision-floor %s\n' "$MISS_RATE" "$FLOOR"
	exit 0
	;;
touched)
	[ $# -eq 3 ] || die "$usage"
	head=$(base_commit "$3") || die "the head ref names no commit: $3"
	commit=$(base_commit "$2") || {
		printf 'fail-closed no-base %s\n' "$RISK_POLICY"
		exit 3
	}
	# No merge base (unrelated histories, a shallow clone) is a base the
	# reader cannot reach from the head: closed, never a caller error.
	mb=$(git merge-base "$commit" "$head" 2>/dev/null) || {
		printf 'fail-closed no-base %s\n' "$RISK_POLICY"
		exit 3
	}
	risk_eval "$commit" || EXTRA=
	git diff --quiet --no-renames "$mb" "$head" >/dev/null 2>&1
	[ $? -le 1 ] || {
		printf 'fail-closed unreadable %s\n' "$RISK_POLICY"
		exit 3
	}
	changed=$(git diff --name-only -z --no-renames "$mb" "$head" | tr '\0' '\n')
	hits=$(
		IFS='
'
		for p in $changed; do
			if in_fixed "$p" || in_extra "$p"; then printf '%s\n' "$p"; fi
		done | LC_ALL=C sort -u
	)
	[ -n "$hits" ] && printf '%s\n' "$hits"
	if [ -n "$RISK_REASON" ]; then
		printf 'fail-closed %s %s\n' "$RISK_REASON" "$RISK_POLICY"
		exit 3
	fi
	[ -n "$hits" ] && exit 1
	exit 0
	;;
*)
	die "$usage"
	;;
esac
