#!/bin/sh
# tests/lib.sh — the kit's tiny test harness. Sourced, never executed.
#
# The kit's core is POSIX sh and git, so its tests are too: no runner, no
# package.json, no install. `sh tests/<name>.test.sh` is the whole invocation.
#
# The guards under test read git history and produce a verdict about it, so
# every fixture here is a REAL throwaway repository with real commits and a real
# `git diff`. Faking the history would fake the test.
#
# Fixtures are hermetic: their own identity, no signing, and hooksPath pointed
# at nothing — otherwise a developer's global GPG requirement or hook manager
# would fail these tests for reasons that have nothing to do with the guards.

failures=0
LAST_OUT=""
LAST_STATUS=0

# t_mark <NAME> — the double-brace placeholder mark, e.g. `t_mark PROJECT_OWNER`.
#
# Assembled from variables so no suite contains a LITERAL mark. The kit repo is
# itself bootstrapped now (docs/adr/0001-the-kit-self-hosts-its-own-constitution.md),
# so `scripts/check.sh`'s placeholder rule runs over these scripts too — and
# that rule exempts only `*.template` sources, deliberately, because a gate with
# a hole shaped like its own tooling is not a gate. check.sh spells its own
# pattern the same way, for the same reason. Suites that must PLANT a mark to
# prove the gate catches it therefore spell it rather than write it.
#
# There are three copies of this helper, and at least one of them must stay a
# copy: `mark` in `bootstrap.sh` ships into a consumer tree that has no `tests/`
# to source from, so it cannot be deduplicated into this file at any price.
# `mark` in `tests/kit-demo.sh` is the third; that suite carries its own harness
# and sources nothing at all. If you are here to remove duplication, remove that
# one — never bootstrap's.
_t_ob='{'
_t_cb='}'
t_mark() { printf '%s%s%s%s%s' "$_t_ob" "$_t_ob" "$1" "$_t_cb" "$_t_cb"; }

t_init() {
	SCRATCH=$(mktemp -d) || exit 2
	trap 't_cleanup' EXIT INT TERM HUP
}

t_cleanup() { [ -n "${SCRATCH:-}" ] && rm -rf "$SCRATCH"; }

banner() { printf '\n=== %s ===\n' "$*"; }
pass() { printf '  ok    %s\n' "$*"; }
fail() {
	printf '  FAIL  %s\n' "$*"
	failures=$((failures + 1))
}

# t_repo — a fresh repo on `main` with one empty root commit.
#
# Sets the global REPO rather than echoing the path: a fixture builder that has
# to run inside `$(...)` runs in a SUBSHELL, so any sha or path it recorded on
# the way is lost to the caller. Setting globals keeps the builders composable.
t_repo() {
	REPO=$(mktemp -d "$SCRATCH/repo.XXXXXX") || exit 2
	git -C "$REPO" init -q -b main
	git -C "$REPO" config user.name "Guard Fixture"
	git -C "$REPO" config user.email "fixture@example.invalid"
	git -C "$REPO" config commit.gpgsign false
	git -C "$REPO" config core.hooksPath .git/no-such-hooks
	git -C "$REPO" commit -q --allow-empty -m "chore: root"
}

# t_write <repo> <relative-path> <contents>
t_write() {
	mkdir -p "$(dirname "$1/$2")"
	printf '%s' "$3" >"$1/$2"
}

# t_commit <repo> <subject> — stages everything and commits. Echoes the sha.
t_commit() {
	git -C "$1" add -A
	git -C "$1" commit -q --allow-empty -m "$2"
	git -C "$1" rev-parse HEAD
}

t_short() { git -C "$1" rev-parse --short "${2:-HEAD}"; }

# t_run <command...> — runs it, capturing combined output in LAST_OUT and the
# exit status in LAST_STATUS. Never fails the script itself.
t_run() {
	LAST_OUT=$("$@" 2>&1)
	LAST_STATUS=$?
	return 0
}

# assert_status <expected> <label> -- <command...>
assert_status() {
	_expected=$1
	_label=$2
	shift 3
	t_run "$@"
	if [ "$LAST_STATUS" = "$_expected" ]; then
		pass "$_label (exit $LAST_STATUS)"
	else
		fail "$_label — expected exit $_expected, got $LAST_STATUS"
		printf '%s\n' "$LAST_OUT" | sed 's/^/        | /'
	fi
}

assert_out_has() {
	case "$LAST_OUT" in
	*"$1"*) pass "output mentions '$1'" ;;
	*)
		fail "output does not mention '$1'"
		printf '%s\n' "$LAST_OUT" | sed 's/^/        | /'
		;;
	esac
}

assert_out_lacks() {
	case "$LAST_OUT" in
	*"$1"*)
		fail "output should NOT mention '$1'"
		printf '%s\n' "$LAST_OUT" | sed 's/^/        | /'
		;;
	*) pass "output does not mention '$1'" ;;
	esac
}

# assert_file_has <file> <literal> [<why>]
# assert_file_lacks <file> <literal> [<why>]
#
# Several suites in this kit assert about DOCUMENTS rather than about exit
# codes — a skill, a workflow template, a prompt. The assertion is always the
# same shape: does this file contain this literal string. `grep -F` and not a
# pattern, because the literals are real content (`--auto`, `AXIS 1 —
# STANDARDS`, `types: [opened, …]`) and regex metacharacters in them would
# silently change what is being checked.
#
# The optional third argument is the REASON the rule exists, not a replacement
# label: it is appended to both the pass and the fail line, so the output says
# why a check matters at the moment it fires — which is the only moment anyone
# reads it. A failing `lacks` also prints the offending lines with numbers,
# because "it is in there somewhere" is not an actionable failure.
assert_file_has() {
	if grep -qF -- "$2" "$1"; then
		pass "$1 says '$2'${3:+ ($3)}"
	else
		fail "$1 never says '$2'${3:+ — $3}"
	fi
}

assert_file_lacks() {
	if grep -qF -- "$2" "$1"; then
		fail "$1 contains '$2'${3:+ — $3}"
		grep -nF -- "$2" "$1" | sed 's/^/        | /'
	else
		pass "no '$2' in $1${3:+ ($3)}"
	fi
}

t_done() {
	printf '\n'
	if [ "$failures" = 0 ]; then
		printf '  ALL GREEN — %s\n' "${1:-suite}"
		exit 0
	fi
	printf '  %s assertion(s) failed — %s\n' "$failures" "${1:-suite}"
	exit 1
}

# ---------------------------------------------------------------------------
# Fixture builders — the throwaway repos every demo makes, built one way.
#
# The deliberate CONTENT SURGERY that gives a fixture its meaning (a rollback
# of a shared article, a manifest rewritten to an older release, a wave's
# additions removed) stays at the call site, between the copy and the history:
# it is the fixture's whole point, and hiding it would hide the scenario.
# These hide only what is the same every time — the copy, the identity, the
# signing switches, the tag pair.
# ---------------------------------------------------------------------------

# t_kit_tree <kit> <dest> — a .git-free copy of the kit's working tree at
# <dest>, nested worktrees stripped. The source is resolved to its physical
# path first: git reports worktrees that way, and the strip matches on the
# prefix, so a symlinked source (macOS's /var → /private/var, say) would
# otherwise keep every nested worktree in silence.
t_kit_tree() {
	_kt_src=$(cd "$1" && pwd -P) || exit 2
	mkdir -p "$2"
	cp -R "$_kt_src/." "$2/"
	strip_nested_worktrees "$_kt_src" "$2"
	rm -rf "$2/.git"
}

# t_git_identity <dir> <name> <email> — init a repo on main with a fixture
# identity, every signing switch off, and the machine's hooks out of reach,
# so a fixture commits and tags on any machine — the same neutralisation
# t_repo gives the small fixtures.
t_git_identity() {
	git -C "$1" init -q -b main
	git -C "$1" config user.name "$2"
	git -C "$1" config user.email "$3"
	git -C "$1" config commit.gpgsign false
	git -C "$1" config tag.gpgSign false
	git -C "$1" config tag.forceSignAnnotated false
	git -C "$1" config core.hooksPath .git/no-such-hooks
}

# t_kit_history <hist> <old tree> <old tag> <new tree> <new tag> — one repo
# holding two releases as real tags: the old tree committed and tagged, then
# replaced wholesale by the new tree, committed and tagged. Passes or fails on
# both tags existing.
t_kit_history() {
	mkdir -p "$1"
	cp -R "$2/." "$1/"
	t_git_identity "$1" "Kit Release" "kit@example.invalid"
	git -C "$1" add -A >/dev/null
	git -C "$1" commit -q -m "release ${3#v}"
	git -C "$1" tag "$3"
	find "$1" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
	cp -R "$4/." "$1/"
	git -C "$1" add -A >/dev/null
	git -C "$1" commit -q -m "release ${5#v}"
	git -C "$1" tag "$5"
	if git -C "$1" rev-parse -q --verify "$3" >/dev/null && git -C "$1" rev-parse -q --verify "$5" >/dev/null; then
		pass "kit history built with tags $3 and $5"
	else
		fail "kit history tags were not created ($3, $5)"
	fi
}

# t_consumer_from <tree> <dest> <name> <email> [bootstrap args...] — a
# consumer bootstrapped from a kit tree: copy, identity, bootstrap with the
# given arguments, one commit. Leaves the shell in <dest>.
t_consumer_from() {
	_cf_tree=$1; _cf_dest=$2; _cf_name=$3; _cf_email=$4
	shift 4
	mkdir -p "$_cf_dest"
	cp -R "$_cf_tree/." "$_cf_dest/"
	rm -rf "$_cf_dest/.git"
	t_git_identity "$_cf_dest" "$_cf_name" "$_cf_email"
	cd "$_cf_dest" || exit 2
	sh bootstrap.sh "$@" >/dev/null 2>&1
	git add -A >/dev/null
	git commit -q -m "chore: bootstrap from agentic-sdlc"
}

# strip_nested_worktrees <src_repo> <dest_tree> — drop any git worktree that
# lives INSIDE the source repo from a tree that was just `cp -R`'d out of it.
#
# Why this exists: the kit's own convention is to develop in worktrees checked
# out under the repo, and `cp -R` takes them along. A fixture built that way is
# testing whatever a sibling branch happens to have in it — /dogfood's suite
# went red on main because an unrelated branch's checkout mentioned the command
# the suite asserts is absent. "Use this template" never hands anyone a nested
# worktree, so neither should a fixture that simulates it.
strip_nested_worktrees() {
	_swt_src=$1
	_swt_dest=$2
	git -C "$_swt_src" worktree list --porcelain 2>/dev/null |
		sed -n 's/^worktree //p' |
		while IFS= read -r _swt_path; do
			case "$_swt_path" in
			"$_swt_src") ;;
			"$_swt_src"/*) rm -rf "$_swt_dest/${_swt_path#"$_swt_src"/}" ;;
			esac
		done
}

# t_ignored_commands — the slash commands the gate's policy file exempts from
# skill resolution (`claudeMdRefs.ignoreCommands` in config.mjs), one per line.
# Read from the file rather than mirrored: three hand-kept copies of that list
# had already drifted by the time this helper existed.
t_ignored_commands() {
	sed -n '/ignoreCommands: \[/,/\]/p' "${ROOT:-$(pwd)}/scripts/docs-conformance/config.mjs" |
		grep -o '"/[a-z][a-z0-9-]*"' | tr -d '"'
}

# t_is_ignored_command <cmd> — true when the policy file exempts it.
t_is_ignored_command() { t_ignored_commands | grep -qx -- "$1"; }

# t_assert_skill_frontmatter <skill dir> — the Agent Skills specification's
# frontmatter rules, held once for every skill suite: keys limited to the
# fields the specification defines (any case — an unexpected key is a finding
# whatever its case), name equal to the directory, description under 1024
# characters read to the next key, the body under 500 lines, supporting files
# one level deep.
t_assert_skill_frontmatter() {
	_sf_dir=$1
	_sf_file="$_sf_dir/SKILL.md"
	_sf_keys=$(awk 'NR == 1 { next } /^---/ { exit } /^[A-Za-z0-9_-]+:/ { sub(/:.*/, ""); print tolower($0) }' "$_sf_file")
	for _sf_k in $_sf_keys; do
		case "$_sf_k" in
		name | description | license | compatibility | metadata | allowed-tools) ;;
		*) fail "$_sf_file: frontmatter key '$_sf_k' is not one the Agent Skills specification defines — the kit ships vendor-neutral skills" ;;
		esac
	done
	printf '%s\n' "$_sf_keys" | grep -qx name && pass "$_sf_file carries name" || fail "$_sf_file lacks name"
	printf '%s\n' "$_sf_keys" | grep -qx description && pass "$_sf_file carries description" || fail "$_sf_file lacks description"
	_sf_name=$(awk 'NR == 1 { next } /^---/ { exit } /^name:/ { sub(/^name: */, ""); print; exit }' "$_sf_file")
	[ "$_sf_name" = "$(basename "$_sf_dir")" ] && pass "frontmatter name equals the directory name" ||
		fail "frontmatter name '$_sf_name' is not the directory name"
	_sf_desc=$(awk 'NR == 1 { next } /^---/ { exit } /^[A-Za-z0-9_-]+:/ { indesc = ($0 ~ /^description:/); if (indesc) { sub(/^description: */, ""); n += length($0) } ; next } indesc { n += length($0) + 1 } END { print n + 0 }' "$_sf_file")
	[ "${_sf_desc:-0}" -le 1024 ] && pass "description is $_sf_desc chars, within the specification's 1024" ||
		fail "description is $_sf_desc chars — the specification caps it at 1024"
	_sf_lines=$(wc -l <"$_sf_file" | tr -d ' ')
	[ "$_sf_lines" -le 500 ] && pass "SKILL.md is $_sf_lines lines, under the 500 the specification recommends" ||
		fail "SKILL.md is $_sf_lines lines — over the 500 the specification recommends; move reference material to a sidecar"
	_sf_deep=$(find "$_sf_dir" -mindepth 2 -type f | head -1)
	[ -z "$_sf_deep" ] && pass "supporting files are one level deep" || fail "a supporting file is nested deeper than one level: $_sf_deep"
}

