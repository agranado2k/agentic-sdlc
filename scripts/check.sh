#!/bin/sh
# The docs gate — agentic-sdlc walking skeleton (K0).
#
# Shared invariant §8: "a rule written in a document that nothing checks decays
# into a lie, and stale standing instructions are worse than absent ones." This
# script is the smallest honest enforcement of that for a freshly bootstrapped
# project. It checks three things, and claims nothing beyond them:
#
#   1. placeholder-unstamped — no double-brace mark (an upper-case name wrapped
#      in doubled curly braces) survived bootstrap. A file still carrying one
#      was never personalized, and every agent session loads that hole. This
#      comment describes the mark rather than showing it, because the gate scans
#      its own source too — a gate exempt from itself is not a gate.
#   2. shared-layer-missing  — every file the `VERSION` manifest lists as
#      shared layer still exists. The shared layer is the thing the kit
#      versions; if it can vanish silently, the version marker is decoration.
#   3. path-missing          — every repo path the root CLAUDE.md references in
#      a code span exists on disk. This is the seed of the full
#      claude-md-refs validator, which K1 (#3) ports in whole (with slash-command
#      resolution, the article layer, reachability, and the portability
#      deny-list). Deliberately NOT claimed here.
#
# POSIX sh, no dependencies beyond git and the standard toolchain — the kit's
# core is language-agnostic (PRD #1), so the gate a fresh project inherits must
# not require a runtime it hasn't chosen yet.
#
# Exit: 0 clean, 1 violations found, 2 could not run.

set -u

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root=$(pwd)
cd "$repo_root" || {
	echo "check.sh: cannot enter repo root '$repo_root'" >&2
	exit 2
}

vfile=$(mktemp) || exit 2
trap 'rm -f "$vfile"' EXIT INT TERM HUP

# report <rule> <file> <message> <hint>
report() {
	printf '  [%s] %s\n    x %s\n      -> %s\n\n' "$1" "$2" "$3" "$4" >>"$vfile"
}

# The reviewed surface. `git ls-files -co --exclude-standard` is tracked files
# PLUS untracked-but-not-ignored ones, which is exactly right for a project that
# has just been bootstrapped and has not committed yet, while still respecting
# .gitignore so build output never reaches the gate.
list_files() {
	if git rev-parse --git-dir >/dev/null 2>&1; then
		git ls-files -co --exclude-standard
	else
		find . -type f ! -path './.git/*' | sed 's|^\./||'
	fi
}

# ---------------------------------------------------------------------------
# 1. No unstamped placeholders
# ---------------------------------------------------------------------------
# The pattern is assembled from variables so this script does not itself contain
# the literal mark. Otherwise the gate would have to exempt its own source, and
# a gate with a blind spot over itself is not a gate.
ob='{'
cb='}'
placeholder_re="${ob}${ob}[A-Z][A-Z0-9_]*${cb}${cb}"

list_files | while IFS= read -r f; do
	[ -f "$f" ] || continue
	# `*.template` files are SUPPOSED to carry placeholders — they are the
	# unstamped source bootstrap reads. Everything else is stamped output.
	case "$f" in
	*.template) continue ;;
	esac
	grep -n -I "$placeholder_re" "$f" 2>/dev/null | while IFS= read -r hit; do
		report "placeholder-unstamped" "$f:${hit%%:*}" \
			"still contains an unstamped placeholder" \
			"Run bootstrap, or replace the mark by hand. An agent loading this file loads the hole."
	done
done

# ---------------------------------------------------------------------------
# 2. The shared layer named in VERSION is intact
# ---------------------------------------------------------------------------
if [ ! -f VERSION ]; then
	report "shared-layer-missing" "VERSION" \
		"the shared-layer manifest does not exist" \
		"Restore VERSION from the kit — without it nothing records which files are shared layer, or at which version."
else
	shared_version=$(sed -n 's/^shared-layer:[[:space:]]*//p' VERSION | head -1)
	[ -n "$shared_version" ] || report "shared-layer-missing" "VERSION" \
		"has no 'shared-layer: <version>' line" \
		"The manifest must state the version it pins, or the update recipe has no anchor to diff from."

	awk '
		/^files:/           { inlist = 1; next }
		!inlist             { next }
		/^[ \t]*#/          { next }
		/^[ \t]*$/          { next }
		/^[ \t]+[^ \t]/     { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print; next }
		                    { inlist = 0 }
	' VERSION | while IFS= read -r shared; do
		[ -e "$shared" ] && continue
		report "shared-layer-missing" "$shared" \
			"is listed in VERSION as shared layer but does not exist" \
			"Restore it from the kit at the pinned version. Shared-layer files are copied verbatim, not edited or deleted locally."
	done
fi

# ---------------------------------------------------------------------------
# 3. Every repo path the root manual references exists
# ---------------------------------------------------------------------------
# Path roots: the trees a manual is allowed to point into. A backticked token
# whose first segment is one of these, and which contains a `/`, is a repo path
# and must resolve. Anything else (prose, bare filenames, globs) is left alone.
path_roots='constitution scripts docs tests adapters templates .githooks .github .claude'

if [ -f CLAUDE.md ]; then
	# Strip fenced blocks (their ``` markers would be read as span delimiters),
	# pull out every `code span`, then split spans into words so a span like
	# `sh scripts/check.sh` still yields the path.
	awk '/^[ \t]*(```|~~~)/ { fence = !fence; next } !fence { print }' CLAUDE.md |
		grep -o '`[^`]*`' |
		tr -d '`' |
		tr ' \t' '\n\n' |
		sort -u |
		while IFS= read -r token; do
			case "$token" in
			*/*) ;;
			*) continue ;; # no separator: not a path
			esac
			root=${token%%/*}
			is_root=0
			for r in $path_roots; do
				[ "$root" = "$r" ] && is_root=1 && break
			done
			[ "$is_root" = 1 ] || continue
			# Trailing punctuation from prose, and trailing slash on dirs.
			clean=$(printf '%s' "$token" | sed 's/[.,;:)]*$//')
			if [ -e "$clean" ] || [ -e "${clean%/}" ]; then
				continue
			fi
			report "path-missing" "CLAUDE.md" \
				"references \`$token\` but that path does not exist" \
				"Create it or remove the reference — the manual must describe reality, not intent."
		done
else
	report "path-missing" "CLAUDE.md" \
		"the root agent manual does not exist" \
		"Run bootstrap.sh to stamp constitution/CLAUDE.md.template into CLAUDE.md."
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
if [ ! -s "$vfile" ]; then
	echo "OK  docs gate: all checks passed (shared-layer ${shared_version:-unknown})"
	exit 0
fi

echo "FAIL  docs gate: violations found" >&2
echo "" >&2
cat "$vfile" >&2
count=$(grep -c '^  \[' "$vfile")
echo "$count violation(s). Fix them, or see .githooks/pre-push for the logged bypass." >&2
exit 1
