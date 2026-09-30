#!/bin/sh
# Admit declared runtime skill roots against canonical source bytes.
set -eu
LC_ALL=C
export LC_ALL

die() { printf 'catalogue: %s\n' "$*" >&2; exit 2; }
hash() { git hash-object --no-filters -- "$1" || die "cannot hash $1"; }

valid_path() {
	case "$1" in
	''|*[!a-zA-Z0-9_./-]*|*/|*//*|.|..|./*|../*|*/./*|*/../*|*/.|*/..)
		die "unsupported path: $1" ;;
	esac
}

# Compare each component with directory entries, not a case-folding stat.
exact_path() (
	valid_path "$1"
	rest=$1
	base=.
	case "$rest" in /*) base=; rest=${rest#/} ;; esac
	while [ -n "$rest" ]; do
		component=${rest%%/*}
		found=no
		for candidate in "$base"/* "$base"/.[!.]* "$base"/..?*; do
			[ "${candidate##*/}" = "$component" ] || continue
			if [ -e "$candidate" ] || [ -L "$candidate" ]; then found=yes; break; fi
		done
		[ "$found" = yes ] || die "missing or wrong-case path: $1"
		base=$base/$component
		case "$rest" in */*) rest=${rest#*/} ;; *) rest= ;; esac
	done
)

# Subshells keep recursive walk state private in POSIX sh.
walk() (
	exact_path "$1"
	[ -d "$1" ] || die "not a catalogue directory: $1"
	if [ "$2" = source ] && [ -L "$1" ]; then
		die "canonical directory must not be linked: $1"
	fi
	if [ -n "${3:-}" ]; then
		[ -d "$3" ] || die "catalogue type mismatch: $1 (source: $3)"
	fi
	for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
		[ -e "$entry" ] || [ -L "$entry" ] || continue
		valid_path "$entry"
		other=
		if [ -n "${3:-}" ]; then
			other=$3/${entry##*/}
			exact_path "$other"
		fi
		if [ -d "$entry" ]; then
			if [ "$2" = source ] && [ -L "$entry" ]; then
				die "canonical directory must not be linked: $entry"
			fi
			walk "$entry" "$2" "$other"
		elif [ -f "$entry" ]; then
			identity=$(hash "$entry")
			if [ -n "$other" ]; then
				[ -f "$other" ] || die "not a regular catalogue file: $other"
				[ "$identity" = "$(hash "$other")" ] || die "stale copy: $entry (source: $other)"
			fi
			printf '%s|%s|%s\n' "$2" "$entry" "$identity"
		else
			die "not a regular catalogue file: $entry"
		fi
	done
	if [ -n "${3:-}" ]; then
		for expected in "$3"/* "$3"/.[!.]* "$3"/..?*; do
			[ -e "$expected" ] || [ -L "$expected" ] || continue
			exact_path "$1/${expected##*/}"
		done
	fi
)

[ "$#" -ge 2 ] && [ "$#" -le 3 ] && [ "$1" = check ] ||
	die 'usage: sh scripts/catalogue.sh check REPOSITORY [DECLARATION]'
cd "$2" || die "cannot open repository: $2"
declaration=${3:-scripts/catalogue.config}
exact_path "$declaration"
[ -f "$declaration" ] || die "missing declaration: $declaration"
skills=0
for skill in .agents/skills/* .agents/skills/.[!.]* .agents/skills/..?*; do
	[ -d "$skill" ] || continue
	exact_path "$skill/SKILL.md"
	[ -f "$skill/SKILL.md" ] || die "not a regular skill: $skill/SKILL.md"
	skills=$((skills + 1))
done
[ "$skills" -gt 0 ] || die 'empty canonical catalogue: .agents/skills'
scratch=$(mktemp -d "${TMPDIR:-/tmp}/catalogue.XXXXXX") || exit 2
trap 'rm -rf "$scratch"' EXIT HUP INT TERM

{
	declaration_hash=$(hash "$declaration")
	printf 'declaration|%s|%s\n' "$declaration" "$declaration_hash"
	walk .agents/skills source
	version=
	roots=
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in ''|'#'*) continue ;; esac
		IFS='|' read -r kind path mode extra <<EOF
$line
EOF
		if [ -z "$version" ]; then
			[ "$line" = 'catalogue|1' ] || die 'first record must be catalogue|1'
			version=1
			continue
		fi
		[ "$line" = "$kind|$path|$mode" ] && [ -n "$path" ] && [ -n "$mode" ] ||
			die "malformed declaration: $line"
		case "$kind" in
		active)
			[ "$mode" = identical ] || die "unsupported transformation: $mode"
			case "|$roots|" in *"|$path|"*) die "duplicate active root: $path" ;; esac
			printf 'root|%s|.agents/skills|identical\n' "$path"
			walk "$path" active .agents/skills
			roots=$roots$path'|'
			;;
		reference)
			case "$path" in
			executable|optional)
				valid_path "$mode"
				if [ "$path" = optional ] && [ ! -e "$mode" ] && [ ! -L "$mode" ]; then
					printf 'reference|optional|%s|absent\n' "$mode"
					continue
				fi
				exact_path "$mode"
				[ -f "$mode" ] || die "not a regular dependency: $mode"
				identity=$(hash "$mode")
				printf 'reference|%s|%s|%s\n' "$path" "$mode" "$identity"
				;;
			example|external) printf 'reference|%s|%s|not-checked\n' "$path" "$mode" ;;
			*) die "unknown reference class: $path" ;;
			esac
			;;
		*) die "unknown declaration: $kind" ;;
		esac
	done <"$declaration"
	[ -n "$version" ] || die 'missing catalogue version'
	[ -n "$roots" ] || die 'no active roots declared'
	printf 'admitted|1\n'
} >"$scratch/result"
cat "$scratch/result"
