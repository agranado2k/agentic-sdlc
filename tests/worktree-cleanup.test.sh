#!/bin/sh
# tests/worktree-cleanup.test.sh — the pruning rule, against real repositories.
#
# The script decides, per worktree, between "remove this and its branch" and
# "keep it and say why". Both outcomes are destructive to get wrong in opposite
# directions, so every fixture here is a REAL repo with a REAL bare remote and
# REAL linked worktrees: faking the git state would fake the test.
#
# Usage: sh tests/worktree-cleanup.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/scripts/worktree-cleanup.sh"

. "$ROOT/tests/lib.sh"

t_init

# --- fixture builders --------------------------------------------------------

# wt_fixture — a repo on `main`, pushed to a bare origin with a HEAD symref, and
# `worktree/` gitignored (the layout the root manual's first hard rule asks for).
wt_fixture() {
	t_repo
	REMOTE="$SCRATCH/remote.$$.$(basename "$REPO").git"
	git init -q --bare -b main "$REMOTE"
	git -C "$REPO" remote add origin "$REMOTE"
	printf 'worktree/\n' >"$REPO/.gitignore"
	git -C "$REPO" add -A
	git -C "$REPO" commit -q -m "chore: ignore the worktree tree"
	git -C "$REPO" push -q -u origin main
	git -C "$REPO" remote set-head origin main >/dev/null
}

# wt_branch <slug> — a linked worktree at worktree/<slug> on feat/<slug>, with
# one commit on it. Branched from origin/main rather than the root checkout's
# HEAD, so that several fixtures can land in sequence without colliding — the
# root checkout is deliberately left stale, which is the situation the script
# exists to fix.
wt_branch() {
	git -C "$REPO" worktree add -q "worktree/$1" -b "feat/$1" origin/main
	printf '%s\n' "$1" >"$REPO/worktree/$1/$1.txt"
	git -C "$REPO/worktree/$1" add -A
	git -C "$REPO/worktree/$1" commit -q -m "feat: $1"
}

# wt_land <slug> — simulate the pull request landing: push the branch's tip onto
# origin/main, so it becomes an ancestor of the base ref.
wt_land() {
	git -C "$REPO" push -q origin "feat/$1:main"
	git -C "$REPO" fetch -q origin
}

# wt_run [args…] — run the script with the fixture repo as cwd.
wt_run() {
	t_run env WC_REPO="$REPO" WC_SCRIPT="$SCRIPT" \
		sh -c 'cd "$WC_REPO" && sh "$WC_SCRIPT" "$@"' -- "$@"
}

wt_has_worktree() { git -C "$REPO" worktree list | grep -q "worktree/$1"; }
wt_has_branch() { git -C "$REPO" branch --list "feat/$1" | grep -q .; }

# ---------------------------------------------------------------------------
banner "A merged, clean worktree is pruned; everything else is kept"
# ---------------------------------------------------------------------------
wt_fixture
wt_branch landed
wt_land landed
wt_branch wip # committed, never landed
wt_branch messy
wt_land messy                                          # landed…
printf 'scratch\n' >"$REPO/worktree/messy/scratch.txt" # …but has uncommitted work

wt_run
[ "$LAST_STATUS" = 0 ] && pass "the script exits 0 (exit 0)" ||
	fail "the script exited $LAST_STATUS"

wt_has_worktree landed && fail "the merged worktree was not removed" ||
	pass "the merged, clean worktree is gone"
wt_has_branch landed && fail "the merged branch survived" ||
	pass "its local branch is gone too"

wt_has_worktree wip && pass "the unmerged worktree is kept" ||
	fail "an unmerged worktree was removed — that is data loss"
assert_out_has "not merged into"
# A branch with commits of its own is never fresh, however the fresh test reads
# the reflog: its tip has moved since the branch was created.
assert_out_lacks "(feat/wip) — fresh"

# `messy` IS merged — it is kept only because of the untracked file in it, which
# is the case worth pinning: "merged" alone must never be sufficient.
wt_has_worktree messy && pass "a merged worktree with uncommitted work is kept" ||
	fail "a worktree with uncommitted changes was removed — that is data loss"
assert_out_has "uncommitted changes"

# The remote branch goes too, for the case a forge did not delete it on merge.
git -C "$REPO" ls-remote --exit-code --heads origin "feat/landed" >/dev/null 2>&1 &&
	fail "the merged remote branch survived" ||
	pass "the merged remote branch is deleted"

# ---------------------------------------------------------------------------
banner "A fresh worktree — no commits of its own — is kept, not pruned"
# ---------------------------------------------------------------------------
# The regression this guards: a branch created a minute ago has no commits, so
# it is trivially an ancestor of the base ref and read as "merged". A cleanup
# run while a session was starting removed that session's worktree and branch.
# Nothing can have been merged from a branch that has nothing, so it is kept —
# whether the base still sits where it was branched from, or has moved on since.
# Its neighbours pin that the rule narrows nothing else: a landed branch and a
# squash-merged one (recorded as merged by a stub forge CLI) are still pruned.

# wt_fresh <slug> — a linked worktree on feat/<slug>, branched from origin/main
# and given no commits: the state a session is in the moment it opens.
wt_fresh() { git -C "$REPO" worktree add -q "worktree/$1" -b "feat/$1" origin/main; }

# A forge CLI stub that records exactly one pull request as merged: the head
# `feat/squashed`. Every other lookup answers empty, as the real CLI does for a
# branch with no merged pull request.
STUB_BIN="$SCRATCH/stub-forge-bin"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/gh" <<'STUB'
#!/bin/sh
case " $* " in
*" --head feat/squashed "*) echo 42 ;;
esac
exit 0
STUB
chmod +x "$STUB_BIN/gh"

fresh_fixture() {
	wt_fixture
	wt_fresh stale # branched from the base BEFORE anything below landed
	wt_branch landed
	wt_land landed
	# The squash merge: the branch's change lands on main as a NEW commit, so
	# the branch is never an ancestor of the base — only the forge knows.
	wt_branch squashed
	git -C "$REPO" worktree add -q "$SCRATCH/squash.$$" --detach origin/main
	printf 'squashed\n' >"$SCRATCH/squash.$$/squashed.txt"
	git -C "$SCRATCH/squash.$$" add -A
	git -C "$SCRATCH/squash.$$" commit -q -m "feat: squashed (#42)"
	git -C "$SCRATCH/squash.$$" push -q origin HEAD:main
	git -C "$REPO" worktree remove "$SCRATCH/squash.$$"
	git -C "$REPO" fetch -q origin
	wt_fresh fresh # branched from the base's current tip
}

for mode in --dry-run real; do
	fresh_fixture
	if [ "$mode" = real ]; then
		PATH="$STUB_BIN:$PATH" wt_run
	else
		PATH="$STUB_BIN:$PATH" wt_run --dry-run
	fi
	[ "$LAST_STATUS" = 0 ] && pass "$mode: the script exits 0 (exit 0)" ||
		fail "$mode: the script exited $LAST_STATUS"
	assert_out_has "worktree/fresh (feat/fresh) — fresh"
	assert_out_has "worktree/stale (feat/stale) — fresh"
	assert_out_has "no commits of its own"
	assert_out_lacks "Removing merged worktree $REPO/worktree/fresh"
	assert_out_lacks "Removing merged worktree $REPO/worktree/stale"
	assert_out_has "Removing merged worktree $REPO/worktree/landed"
	assert_out_has "Removing merged worktree $REPO/worktree/squashed"
	assert_out_has "removed (2):"
	assert_out_has "kept (2):"
	wt_has_worktree fresh && wt_has_branch fresh &&
		pass "$mode: the fresh worktree and its branch are kept" ||
		fail "$mode: a fresh worktree was pruned — that is a starting session's worktree lost"
	wt_has_worktree stale && wt_has_branch stale &&
		pass "$mode: a fresh worktree on a base that moved on is kept" ||
		fail "$mode: a fresh worktree on an older base tip was pruned"
done
wt_has_worktree landed && fail "the landed worktree survived the real run" ||
	pass "the landed worktree is still pruned"
wt_has_worktree squashed && fail "the squash-merged worktree survived the real run" ||
	pass "the squash-merged worktree the forge records as merged is still pruned"

# ---------------------------------------------------------------------------
banner "--dry-run changes nothing"
# ---------------------------------------------------------------------------
wt_fixture
wt_branch landed
wt_land landed

wt_run --dry-run
assert_out_has "[dry-run]"
assert_out_has "nothing was changed"
wt_has_worktree landed && pass "the worktree is still there after --dry-run" ||
	fail "--dry-run removed a worktree"
wt_has_branch landed && pass "the branch is still there after --dry-run" ||
	fail "--dry-run deleted a branch"
[ "$(git -C "$REPO" rev-parse HEAD)" = "$(git -C "$REPO" rev-parse main)" ] &&
	pass "the base branch did not move under --dry-run" ||
	fail "--dry-run fast-forwarded the root checkout"

# ---------------------------------------------------------------------------
banner "The root checkout fast-forwards, and only then runs the post-sync hook"
# ---------------------------------------------------------------------------
wt_fixture
before=$(git -C "$REPO" rev-parse HEAD)
wt_branch landed
wt_land landed

WORKTREE_CLEANUP_POST_SYNC='echo POST_SYNC_MARKER'
export WORKTREE_CLEANUP_POST_SYNC
wt_run
assert_out_has "Fast-forwarding main"
assert_out_has "POST_SYNC_MARKER"
[ "$(git -C "$REPO" rev-parse HEAD)" != "$before" ] &&
	pass "the root checkout moved to the landed commit" ||
	fail "the root checkout did not fast-forward"

# Second run: nothing landed since, so nothing moves and the hook must NOT fire.
# A post-sync command that runs on every invocation is how a reinstall ends up
# in someone's hot loop.
wt_run
assert_out_has "already up to date"
assert_out_lacks "POST_SYNC_MARKER"
unset WORKTREE_CLEANUP_POST_SYNC

# Without the hook set, the script says what it is NOT doing rather than
# guessing a package manager.
wt_fixture
wt_branch landed2
wt_land landed2
wt_run
assert_out_has "reinstall dependencies if your project needs it"

# ---------------------------------------------------------------------------
banner "Uncommitted work in the root checkout stops the fast-forward"
# ---------------------------------------------------------------------------
wt_fixture
wt_branch landed
wt_land landed
printf 'edited\n' >>"$REPO/.gitignore" # a TRACKED file, modified

wt_run
assert_out_has "uncommitted changes — skipping fast-forward"
[ "$(git -C "$REPO" rev-parse HEAD)" = "$(git -C "$REPO" rev-parse main)" ] &&
	pass "HEAD is untouched while the root is dirty" ||
	fail "the script fast-forwarded over uncommitted work"

# ---------------------------------------------------------------------------
banner "Untracked worktree/ does NOT read as a dirty root"
# ---------------------------------------------------------------------------
# The regression this guards: `git status --porcelain` reports the untracked
# `worktree/` tree, so a project that forgot to gitignore it would silently
# never fast-forward — a no-op that looks exactly like success.
wt_fixture
git -C "$REPO" rm -q --cached .gitignore
rm -f "$REPO/.gitignore"
git -C "$REPO" commit -q -m "chore: stop ignoring the worktree tree"
git -C "$REPO" push -q origin main
wt_branch landed
wt_land landed

wt_run
assert_out_has "Fast-forwarding main"

# ---------------------------------------------------------------------------
banner "Scope: only worktrees under worktree/ are candidates"
# ---------------------------------------------------------------------------
wt_fixture
git -C "$REPO" worktree add -q "$SCRATCH/elsewhere.$$" -b feat/elsewhere
git -C "$REPO" push -q origin "feat/elsewhere:main"
git -C "$REPO" fetch -q origin

wt_run
assert_out_has "outside worktree/, skipped"
git -C "$REPO" worktree list | grep -q "elsewhere" &&
	pass "a merged worktree outside worktree/ is left alone" ||
	fail "the script removed a worktree outside its scope"

# ---------------------------------------------------------------------------
banner "WORKTREE_CLEANUP_BASE overrides the merge target"
# ---------------------------------------------------------------------------
# The default is origin's HEAD branch. A repo whose integration branch is not
# that one must be able to say so without editing the script.
wt_fixture
git -C "$REPO" push -q origin main:release
git -C "$REPO" fetch -q origin
wt_branch landed
git -C "$REPO" push -q origin "feat/landed:release" # landed on release, NOT main
git -C "$REPO" fetch -q origin

wt_run # default base: origin/main — not merged there
assert_out_has "not merged into origin/main"
wt_has_worktree landed && pass "kept when measured against the default base" ||
	fail "removed a branch that never landed on the default base"

WORKTREE_CLEANUP_BASE=origin/release
export WORKTREE_CLEANUP_BASE
wt_run
wt_has_worktree landed && fail "the override did not take effect" ||
	pass "removed once the base is the branch it actually landed on"
unset WORKTREE_CLEANUP_BASE

# ---------------------------------------------------------------------------
banner "An unknown argument is an error, not a silent full run"
# ---------------------------------------------------------------------------
wt_fixture
wt_branch landed
wt_land landed

wt_run --dryrun # a plausible typo for --dry-run
[ "$LAST_STATUS" = 2 ] && pass "a bad argument exits 2 (exit 2)" ||
	fail "a bad argument exited $LAST_STATUS — a typo'd --dry-run must not delete anything"
assert_out_has "unknown argument"
wt_has_worktree landed && pass "nothing was removed on the bad invocation" ||
	fail "the script acted despite the bad argument"

t_done "worktree-cleanup.sh"
