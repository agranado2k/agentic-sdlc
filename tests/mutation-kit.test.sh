#!/bin/sh
# tests/mutation-kit.test.sh — the kit's own mutation wrapper as a SEAM.
#
# scripts/mutation.kit.sh has four observable behaviours that need no Stryker
# to check: it refuses to run anywhere but the kit, it prints its pinned
# command on --dry-run, it refuses a usage error before touching anything,
# and after a run it hands back any executable bit the in-place restore
# dropped, keeps Stryker's backup when the run failed, and propagates the exit
# code. A stub `npx` on PATH stands in for the eight-minute run.
#
# Usage: sh tests/mutation-kit.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
cd "$ROOT" || exit 2
t_init

# ---------------------------------------------------------------------------
banner "1. --dry-run prints the pinned command and exits 0, from anywhere in the kit"
# ---------------------------------------------------------------------------
assert_status 0 "--dry-run exits 0 at the root" -- sh scripts/mutation.kit.sh --dry-run
assert_out_has "npx --yes -p @stryker-mutator/core@"
assert_out_has "stryker run scripts/mutation.kit.config.json"
case "$LAST_OUT" in
*"@stryker-mutator/core@"[0-9]*.[0-9]*.[0-9]*" "*) pass "the tool version is pinned to one release" ;;
*) fail "the tool is not pinned to a release: $LAST_OUT" ;;
esac
assert_status 0 "--dry-run exits 0 from a subdirectory — the root is resolved, not required" -- \
	sh -c "cd '$ROOT/scripts' && sh mutation.kit.sh --dry-run"

# ---------------------------------------------------------------------------
banner "2. A usage error exits 2 before anything runs"
# ---------------------------------------------------------------------------
assert_status 2 "a typo'd flag is refused" -- sh scripts/mutation.kit.sh --dryrun
assert_out_has "unknown argument"
assert_status 2 "a stray extra argument is refused" -- sh scripts/mutation.kit.sh --dry-run extra
assert_out_has "too many arguments"

# ---------------------------------------------------------------------------
banner "3. Outside the kit it exits 2 and says which check failed"
# ---------------------------------------------------------------------------
NOTKIT="$SCRATCH/notkit"
mkdir -p "$NOTKIT" && git -C "$NOTKIT" init -q -b main
assert_status 2 "a git repo that is not the kit is refused" -- \
	sh -c "cd '$NOTKIT' && sh '$ROOT/scripts/mutation.kit.sh' --dry-run"
assert_out_has "is not the kit"

# ---------------------------------------------------------------------------
banner "4. The run, with a stub Stryker: exit code, dropped bit, backup"
# ---------------------------------------------------------------------------
# A throwaway copy of the kit with one commit, so the tree has recorded modes
# to drift from.
KIT="$SCRATCH/kit"
mkdir -p "$KIT" && cp -R "$ROOT/." "$KIT/"
strip_nested_worktrees "$ROOT" "$KIT"
rm -rf "$KIT/.git"
git -C "$KIT" init -q -b main
git -C "$KIT" config user.name t && git -C "$KIT" config user.email t@example.invalid
git -C "$KIT" config commit.gpgsign false && git -C "$KIT" config core.hooksPath .git/no-such-hooks
git -C "$KIT" add -A >/dev/null && git -C "$KIT" commit -q -m "kit copy"
[ -x "$KIT/scripts/check.sh" ] || fail "fixture: scripts/check.sh is not executable in the copy"

STUB="$SCRATCH/stub"; mkdir -p "$STUB"
# The failing run: drops an executable bit AND changes content on the same
# file (so a fix that reverts the file instead of restoring the bit is caught
# — the first guard did exactly that), leaves a mutant behind in a validator,
# leaves the backup, exits 7.
cat >"$STUB/npx" <<'STUB'
#!/bin/sh
echo "STUB npx: $*"
chmod -x scripts/check.sh
echo "# LEFTOVER EDIT" >>scripts/check.sh
echo "// LEFTOVER MUTANT" >>scripts/docs-conformance/validators/skill-web.mjs
mkdir -p .stryker-tmp && echo backup >.stryker-tmp/marker
exit 7
STUB
chmod +x "$STUB/npx"
assert_status 7 "Stryker's exit code propagates" -- \
	sh -c "cd '$KIT' && PATH='$STUB':\$PATH sh scripts/mutation.kit.sh"
assert_out_has "STUB npx: --yes -p @stryker-mutator/core@"
assert_out_has "restored the executable bit on scripts/check.sh"
[ -x "$KIT/scripts/check.sh" ] && pass "the dropped bit is back" || fail "scripts/check.sh is still not executable"
git -C "$KIT" diff -- scripts/check.sh | grep -q '^old mode' && fail "the mode line is still in the diff" || pass "no mode drift left in the diff"
grep -q "LEFTOVER EDIT" "$KIT/scripts/check.sh" && pass "the bit came back without reverting the file's content" || fail "the wrapper reverted scripts/check.sh instead of restoring its bit"
[ -f "$KIT/.stryker-tmp/marker" ] && pass "the backup survives a failed run" || fail "the backup was deleted after a failed run"
grep -q "LEFTOVER MUTANT" "$KIT/scripts/docs-conformance/validators/skill-web.mjs" &&
	pass "a leftover mutant is left for the operator, never reverted" || fail "the wrapper reverted content"
assert_out_has "differs from the index after the run"
assert_out_has ".stryker-tmp is its backup"

# The clean run: nothing drifts, nothing is said, exit 0.
rm -rf "$KIT/.stryker-tmp"
git -C "$KIT" checkout -q -- scripts/docs-conformance
printf '#!/bin/sh\necho "STUB npx: $*"\nexit 0\n' >"$STUB/npx"
assert_status 0 "a clean run exits 0" -- \
	sh -c "cd '$KIT' && PATH='$STUB':\$PATH sh scripts/mutation.kit.sh"
assert_out_lacks "restored the executable bit"
assert_out_lacks ".stryker-tmp"
assert_out_lacks "differs from the index"

t_done "the kit's mutation wrapper"
