#!/bin/sh
# The walking skeleton's acceptance test — and its demo.
#
# K0's claim is one sentence: "a project created from this template, bootstrapped,
# passes its own gate — and the gate is not vacuous." A claim that nothing runs
# is a claim nobody should believe, so this script runs the whole path end to
# end against a throwaway copy of the kit:
#
#   1. RED    before bootstrap — the gate fails on an unpersonalized tree
#   2. GREEN  bootstrap stamps, wires, self-deletes; the gate passes
#   3.        a second bootstrap is refused (idempotency)
#   4. GREEN  a real `git push` to a real remote passes through the real hook
#   5. RED    an unstamped placeholder fails the gate AND blocks the push
#   6. RED    a missing shared-layer file fails the gate
#   7. GREEN  restored tree passes again
#   8.        the documented bypass lets a red tree through, loudly
#
# This is the kit's whole test tier for now. K1-K5 each bring their own.
#
# Usage: sh tests/skeleton-demo.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
SCRATCH=$(mktemp -d) || exit 2
PROJ="$SCRATCH/demo-project"
REMOTE="$SCRATCH/demo-remote.git"

trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP

failures=0

banner() { printf '\n=== %s ===\n' "$*"; }
pass() { printf '  ok    %s\n' "$*"; }
fail() {
	printf '  FAIL  %s\n' "$*"
	failures=$((failures + 1))
}

# assert_status <expected> <label> -- <command...>
assert_status() {
	expected=$1
	label=$2
	shift 3
	out=$("$@" 2>&1)
	actual=$?
	if [ "$actual" = "$expected" ]; then
		pass "$label (exit $actual)"
	else
		fail "$label — expected exit $expected, got $actual"
		printf '%s\n' "$out" | sed 's/^/        | /'
	fi
	LAST_OUT=$out
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

assert_file() { [ -e "$1" ] && pass "$1 exists" || fail "$1 is missing"; }
assert_no_file() { [ -e "$1" ] && fail "$1 still exists" || pass "$1 is gone"; }

# ---------------------------------------------------------------------------
banner "Setup — simulate 'Use this template'"
# ---------------------------------------------------------------------------
mkdir -p "$PROJ"
cp -R "$KIT/." "$PROJ/"
rm -rf "$PROJ/.git"
cd "$PROJ" || exit 2

git init -q -b main
git config user.name "Skeleton Demo"
git config user.email "demo@example.invalid"
git config commit.gpgsign false
git add -A
git init -q --bare "$REMOTE"
git remote add origin "$REMOTE"
pass "fresh repo at \$SCRATCH/demo-project with a bare origin"

# ---------------------------------------------------------------------------
banner "1. RED — the gate fails BEFORE bootstrap"
# ---------------------------------------------------------------------------
# If it passed here, it would be passing on a tree with no agent manual at all,
# and the green in step 2 would mean nothing.
assert_status 1 "check.sh rejects an unbootstrapped tree" -- sh scripts/check.sh
assert_out_has "the root agent manual does not exist"

# ---------------------------------------------------------------------------
banner "2. GREEN — bootstrap, then the gate"
# ---------------------------------------------------------------------------
assert_status 0 "bootstrap.sh runs" -- sh bootstrap.sh "Demo Project" "A throwaway project proving the skeleton walks."
printf '%s\n' "$LAST_OUT" | sed 's/^/      > /'

assert_file "CLAUDE.md"
assert_no_file "constitution/CLAUDE.md.template"
assert_no_file "bootstrap.sh"
assert_no_file "tests/skeleton-demo.sh"
assert_file "constitution/shared-invariants.md"

grep -q "Demo Project" CLAUDE.md && pass "CLAUDE.md carries the project name" ||
	fail "CLAUDE.md was not stamped with the project name"
[ "$(git config core.hooksPath)" = ".githooks" ] && pass "core.hooksPath is .githooks" ||
	fail "core.hooksPath is '$(git config core.hooksPath)', expected .githooks"

# Deliberately NOT `git add`-ed first: a just-bootstrapped project has committed
# nothing, and the gate must see the new CLAUDE.md anyway.
assert_status 0 "check.sh passes on the bootstrapped project" -- sh scripts/check.sh
assert_out_has "shared-layer 0.1.0"

# ---------------------------------------------------------------------------
banner "3. Idempotency — bootstrap refuses a second run"
# ---------------------------------------------------------------------------
cp "$KIT/bootstrap.sh" bootstrap.sh
assert_status 1 "second bootstrap is refused" -- sh bootstrap.sh "Other Name"
assert_out_has "already exists"
rm -f bootstrap.sh

# ---------------------------------------------------------------------------
banner "4. GREEN — a real push through the real pre-push hook"
# ---------------------------------------------------------------------------
git add -A
git commit -q -m "chore: bootstrap from agentic-sdlc"
assert_status 0 "git push succeeds (hook ran the gate and it passed)" -- git push -q origin main
assert_status 0 "the pre-push hook is executable" -- test -x .githooks/pre-push

# ---------------------------------------------------------------------------
banner "5. RED — an unstamped placeholder fails the gate and blocks the push"
# ---------------------------------------------------------------------------
cp CLAUDE.md "$SCRATCH/CLAUDE.md.good"
printf '\nOwner: {{PROJECT_OWNER}}\n' >>CLAUDE.md
assert_status 1 "check.sh rejects the surviving placeholder" -- sh scripts/check.sh
assert_out_has "placeholder-unstamped"

git add -A
git commit -q -m "docs: add an owner line (with an unstamped placeholder)"
assert_status 1 "git push is BLOCKED by the hook" -- git push origin main
assert_out_has "pre-push: docs gate failed"

# ---------------------------------------------------------------------------
banner "6. RED — a deleted shared-layer file fails the gate"
# ---------------------------------------------------------------------------
cp "$SCRATCH/CLAUDE.md.good" CLAUDE.md
cp constitution/shared-invariants.md "$SCRATCH/shared-invariants.good"
rm -f constitution/shared-invariants.md
assert_status 1 "check.sh rejects the missing shared-layer file" -- sh scripts/check.sh
assert_out_has "shared-layer-missing"
assert_out_has "path-missing"

# ---------------------------------------------------------------------------
banner "7. GREEN — restored tree passes again"
# ---------------------------------------------------------------------------
cp "$SCRATCH/shared-invariants.good" constitution/shared-invariants.md
assert_status 0 "check.sh passes once the tree is whole" -- sh scripts/check.sh

# ---------------------------------------------------------------------------
banner "8. The bypass is real, and loud"
# ---------------------------------------------------------------------------
printf '\nOwner: {{PROJECT_OWNER}}\n' >>CLAUDE.md
git add -A
git commit -q --allow-empty -m "docs: reintroduce the bad line to test the bypass"
out=$(PUSH_WITHOUT_DOCS=1 git push origin main 2>&1)
status=$?
if [ "$status" = 0 ]; then
	pass "PUSH_WITHOUT_DOCS=1 lets the push through (exit 0)"
else
	fail "bypass did not work — exit $status"
	printf '%s\n' "$out" | sed 's/^/        | /'
fi
LAST_OUT=$out
assert_out_has "BYPASSED"

# ---------------------------------------------------------------------------
banner "Result"
# ---------------------------------------------------------------------------
if [ "$failures" = 0 ]; then
	echo "  ALL GREEN — the skeleton walks."
	exit 0
fi
echo "  $failures assertion(s) failed."
exit 1
