#!/bin/sh
# tests/fixture-builders.test.sh — the harness's fixture builders as a SEAM.
#
# Every demo suite builds throwaway kits and consumers; tests/lib.sh now builds
# them one way. This suite pins what each builder promises — a .git-free kit
# copy with nested worktrees stripped, a repo with a fixture identity and every
# signing switch off, a two-tag history whose tags resolve to the two trees,
# and a consumer bootstrapped from a tree with one commit — and proves each can
# go red. The demo suites are the builders' oracle in the large: section D of
# tests/docs-demo.sh compares transcripts byte for byte.
#
# Usage: sh tests/fixture-builders.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init
KIT="$ROOT"

# ---------------------------------------------------------------------------
banner "1. t_kit_tree — a .git-free copy, nested worktrees stripped"
# ---------------------------------------------------------------------------
TREE="$SCRATCH/tree"
t_kit_tree "$KIT" "$TREE"
[ -f "$TREE/bootstrap.sh" ] && [ -f "$TREE/VERSION" ] && pass "the copy carries the kit's files" || fail "the copy is missing kit files"
[ ! -e "$TREE/.git" ] && pass "the copy has no .git" || fail "the copy carries a .git"
# A small repo with a worktree checked out INSIDE it — the kit's own
# convention — proves the copy drops it. The source is passed as a physical
# path because git reports worktrees that way and the helper matches on the
# prefix, exactly as the suites pass the kit's own root.
FAKEKIT="$(cd "$SCRATCH" && pwd -P)/fakekit"
mkdir -p "$FAKEKIT"; printf 'root\n' >"$FAKEKIT/README.md"
t_git_identity "$FAKEKIT" t t@example.invalid
git -C "$FAKEKIT" add -A >/dev/null; git -C "$FAKEKIT" commit -q -m "root"
git -C "$FAKEKIT" worktree add -q "$FAKEKIT/worktree/nested" -b nested >/dev/null 2>&1
[ -f "$FAKEKIT/worktree/nested/README.md" ] || fail "the fixture's nested worktree was not created"
TREE2="$SCRATCH/tree2"
t_kit_tree "$FAKEKIT" "$TREE2"
[ -f "$TREE2/README.md" ] && [ ! -e "$TREE2/worktree/nested" ] && pass "a nested worktree is stripped from the copy" || fail "the nested worktree rode into the copy"

# ---------------------------------------------------------------------------
banner "2. t_git_identity — a repo that commits and tags anywhere"
# ---------------------------------------------------------------------------
R="$SCRATCH/ident"; mkdir -p "$R"
t_git_identity "$R" "Fixture Name" "fixture@example.invalid"
[ "$(git -C "$R" config user.name)" = "Fixture Name" ] && pass "identity set" || fail "identity not set"
[ "$(git -C "$R" config commit.gpgsign)" = "false" ] && [ "$(git -C "$R" config tag.gpgSign)" = "false" ] &&
	pass "commit and tag signing are off" || fail "a signing switch is still on"
[ "$(git -C "$R" symbolic-ref --short HEAD)" = "main" ] && pass "the branch is main" || fail "the branch is not main"

# ---------------------------------------------------------------------------
banner "3. t_kit_history — two trees, two tags, each resolving to its tree"
# ---------------------------------------------------------------------------
OLD="$SCRATCH/old"; NEW="$SCRATCH/new"; mkdir -p "$OLD" "$NEW"
printf 'shared-layer: 0.1.0\n' >"$OLD/VERSION"; printf 'old\n' >"$OLD/only-old.txt"
printf 'shared-layer: 0.2.0\n' >"$NEW/VERSION"; printf 'new\n' >"$NEW/only-new.txt"
HIST="$SCRATCH/hist"
t_kit_history "$HIST" "$OLD" v0.1.0 "$NEW" v0.2.0
[ "$(git -C "$HIST" show v0.1.0:VERSION)" = "shared-layer: 0.1.0" ] && pass "v0.1.0 resolves to the old tree" || fail "v0.1.0 does not hold the old tree"
[ "$(git -C "$HIST" show v0.2.0:VERSION)" = "shared-layer: 0.2.0" ] && pass "v0.2.0 resolves to the new tree" || fail "v0.2.0 does not hold the new tree"
git -C "$HIST" cat-file -e v0.2.0:only-old.txt 2>/dev/null &&
	fail "the old tree's file survived into the new release — the replacement is not wholesale" ||
	pass "the new release does not carry the old tree's files"
[ "$(git -C "$HIST" rev-list --count HEAD)" = 2 ] && pass "exactly two commits" || fail "history has $(git -C "$HIST" rev-list --count HEAD) commits, not 2"

# ---------------------------------------------------------------------------
banner "4. t_consumer_from — bootstrapped from a tree, one commit"
# ---------------------------------------------------------------------------
CONS="$SCRATCH/consumer"
here=$(pwd)
t_consumer_from "$TREE" "$CONS" "Fixture Consumer" "consumer@example.invalid" --no-dogfood "Fixture Consumer" "A throwaway."
cd "$here" || exit 2
[ -f "$CONS/AGENTS.md" ] && grep -q "Fixture Consumer" "$CONS/AGENTS.md" && pass "bootstrap ran and stamped the manual" || fail "bootstrap did not stamp the manual"
[ ! -e "$CONS/bootstrap.sh" ] && pass "bootstrap deleted itself" || fail "bootstrap.sh survived"
[ "$(git -C "$CONS" rev-list --count HEAD)" = 1 ] && pass "one commit" || fail "the consumer has $(git -C "$CONS" rev-list --count HEAD) commits"
[ "$(git -C "$CONS" log -1 --format=%s)" = "chore: bootstrap from agentic-sdlc" ] && pass "the commit subject is the bootstrap's" || fail "unexpected commit subject"

t_done "fixture builders"
