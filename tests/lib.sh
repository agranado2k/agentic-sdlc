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
