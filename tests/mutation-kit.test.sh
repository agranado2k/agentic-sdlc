#!/bin/sh
# tests/mutation-kit.test.sh — the kit's own mutation wrapper as a SEAM.
#
# scripts/mutation.kit.sh has observable behaviours that need no Stryker
# to check: it refuses to run anywhere but the kit, it prints its pinned
# command on --dry-run, it refuses a usage error before touching anything,
# and it runs Stryker in a throwaway worktree of HEAD, so the caller's tree is
# never mutated: a successful run removes that worktree, a failed, interrupted
# or host-paused run keeps it and prints the one command that removes it. A
# stub `npx` on PATH stands in for the real run, and a stub `date` for a host
# that slept.
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
expect_exit 0 "--dry-run exits 0 at the root" -- sh scripts/mutation.kit.sh --dry-run
expect_said "npx --yes -p @stryker-mutator/core@"
expect_said "stryker run scripts/mutation.kit.config.json"
case "$T_OUT" in
*"@stryker-mutator/core@"[0-9]*.[0-9]*.[0-9]*" "*) pass "the tool version is pinned to one release" ;;
*) fail "the tool is not pinned to a release: $T_OUT" ;;
esac
expect_exit 0 "--dry-run exits 0 from a subdirectory — the root is resolved, not required" -- \
	sh -c "cd '$ROOT/scripts' && sh mutation.kit.sh --dry-run"

# ---------------------------------------------------------------------------
banner "2. A usage error exits 2 before anything runs"
# ---------------------------------------------------------------------------
expect_exit 2 "a typo'd flag is refused" -- sh scripts/mutation.kit.sh --dryrun
expect_said "unknown argument"
expect_exit 2 "a stray extra argument is refused" -- sh scripts/mutation.kit.sh --dry-run extra
expect_said "too many arguments"

# ---------------------------------------------------------------------------
banner "3. Outside the kit it exits 2 and says which check failed"
# ---------------------------------------------------------------------------
NOTKIT="$SCRATCH/notkit"
mkdir -p "$NOTKIT" && git -C "$NOTKIT" init -q -b main
expect_exit 2 "a git repo that is not the kit is refused" -- \
	sh -c "cd '$NOTKIT' && sh '$ROOT/scripts/mutation.kit.sh' --dry-run"
expect_said "is not the kit"

# ---------------------------------------------------------------------------
banner "4. The run happens in a throwaway worktree, never in the caller's tree"
# ---------------------------------------------------------------------------
# A throwaway copy of the kit with one commit, so the tree has a HEAD to
# measure and a status to stay clean.
KIT="$SCRATCH/kit"
mkdir -p "$KIT" && cp -R "$ROOT/." "$KIT/"
strip_nested_worktrees "$ROOT" "$KIT"
rm -rf "$KIT/.git"
git -C "$KIT" init -q -b main
git -C "$KIT" config user.name t && git -C "$KIT" config user.email t@example.invalid
git -C "$KIT" config commit.gpgsign false && git -C "$KIT" config core.hooksPath .git/no-such-hooks
git -C "$KIT" add -A >/dev/null && git -C "$KIT" commit -q -m "kit copy"
clean() { [ -z "$(git -C "$KIT" status --porcelain)" ]; }
# The throwaway worktrees the wrapper made and did not remove.
leftovers() { git -C "$KIT" worktree list --porcelain | grep -c '^worktree ' | awk '{ print $1 - 1 }'; }

STUB="$SCRATCH/stub"; mkdir -p "$STUB"
RUNTMP="$SCRATCH/tmp"; mkdir -p "$RUNTMP"
run_wrapper() { sh -c "cd '$KIT' && TMPDIR='$RUNTMP' PATH='$STUB':\$PATH sh scripts/mutation.kit.sh"; }

# A successful run: says where it ran, mutates a validator there, exits 0.
cat >"$STUB/npx" <<'STUB'
#!/bin/sh
echo "STUB npx: $* in $(pwd)"
echo "// MUTANT" >>scripts/docs-conformance/validators/skill-web.mjs
exit 0
STUB
chmod +x "$STUB/npx"
expect_exit 0 "a clean run exits 0" -- run_wrapper
expect_said "STUB npx: --yes -p @stryker-mutator/core@"
case "$T_OUT" in
*"STUB npx:"*" in $KIT") fail "Stryker ran in the caller's tree" ;;
*"STUB npx:"*" in "*"/tmp/kit-mutation."*"/run") pass "Stryker ran in a throwaway worktree under TMPDIR" ;;
*) fail "Stryker's working directory is not under TMPDIR: $T_OUT" ;;
esac
expect_said "measuring HEAD $(git -C "$KIT" rev-parse --short HEAD)"
clean && pass "the caller's tree is untouched by a run" || fail "the run left changes in the caller's tree"
[ "$(leftovers)" = 0 ] && pass "a successful run removes its worktree" || fail "a successful run left its worktree behind"

# A failed run: exit code propagated, the worktree kept, the command to
# remove it printed — and that command works.
printf '#!/bin/sh\necho "STUB npx: $* in $(pwd)"\nexit 7\n' >"$STUB/npx"
expect_exit 7 "Stryker's exit code propagates" -- run_wrapper
clean && pass "a failed run leaves the caller's tree clean" || fail "a failed run left changes in the caller's tree"
[ "$(leftovers)" = 1 ] && pass "a failed run keeps its worktree for inspection" || fail "a failed run removed its worktree"
recover=$(printf '%s\n%s\n' "$T_OUT" "$T_ERR" | sed -n 's/^mutation.kit.sh: remove it with: //p' | tail -1)
[ -n "$recover" ] && pass "a failed run prints the recovery command" || fail "no recovery command printed"
sh -c "$recover" && [ "$(leftovers)" = 0 ] && pass "the printed recovery command removes the worktree" ||
	fail "the printed recovery command did not remove the worktree: $recover"

# ---------------------------------------------------------------------------
banner "5. An interrupted run: the run stops, the tree is clean, recovery is printed"
# ---------------------------------------------------------------------------
# One interrupt per trapped signal, each with its own exit code. perl resets
# the signal to its default before the exec: a background job of a
# non-interactive shell starts with SIGINT ignored, and a shell cannot trap a
# signal ignored on entry.
for pair in TERM:143 INT:130 HUP:129; do
	sig=${pair%%:*} want=${pair#*:}
	cat >"$STUB/npx" <<STUB
#!/bin/sh
echo \$\$ >'$SCRATCH/stryker.pid'
echo "// MUTANT" >>scripts/docs-conformance/validators/skill-web.mjs
exec sleep 300
STUB
	rm -f "$SCRATCH/stryker.pid"
	(cd "$KIT" && TMPDIR="$RUNTMP" PATH="$STUB:$PATH" exec perl -e '$SIG{INT} = $SIG{HUP} = $SIG{TERM} = "DEFAULT"; exec @ARGV' sh scripts/mutation.kit.sh) >"$SCRATCH/int.out" 2>&1 &
	wrapper=$!
	n=0; while [ ! -s "$SCRATCH/stryker.pid" ] && [ $n -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
	kill -"$sig" "$wrapper"
	wait "$wrapper"; st=$?
	[ "$st" = "$want" ] && pass "SIG$sig: the run exits $want (128 + the signal)" || fail "SIG$sig: the run exited $st, not $want"
	kill -0 "$(cat "$SCRATCH/stryker.pid")" 2>/dev/null && fail "SIG$sig: the Stryker process outlived the interrupt" || pass "SIG$sig: the interrupt stops the Stryker process"
	grep -q "interrupted" "$SCRATCH/int.out" && pass "SIG$sig: the run says it was interrupted" || fail "SIG$sig: no interruption message: $(cat "$SCRATCH/int.out")"
	clean && pass "SIG$sig: the caller's tree is clean" || fail "SIG$sig: changes left in the caller's tree"
	recover=$(sed -n 's/^mutation.kit.sh: remove it with: //p' "$SCRATCH/int.out" | tail -1)
	[ -n "$recover" ] && sh -c "$recover" && [ "$(leftovers)" = 0 ] &&
		pass "SIG$sig: the printed recovery command cleans up" ||
		fail "SIG$sig: recovery failed: $(cat "$SCRATCH/int.out")"
done

# ---------------------------------------------------------------------------
banner "5b. A worktree that cannot be added leaves no temporary directory behind"
# ---------------------------------------------------------------------------
REALGIT=$(command -v git)
cat >"$STUB/git" <<STUB
#!/bin/sh
[ "\$1" = worktree ] && [ "\$2" = add ] && { echo "stub git: worktree add refused" >&2; exit 128; }
exec '$REALGIT' "\$@"
STUB
chmod +x "$STUB/git"
expect_exit 2 "a failed worktree add exits 2" -- run_wrapper
[ -z "$(ls "$RUNTMP")" ] && pass "no kit-mutation directory is left under TMPDIR" ||
	fail "the wrapper left $(ls "$RUNTMP") under TMPDIR"
rm -f "$STUB/git"

# ---------------------------------------------------------------------------
banner "6. A run the host paused (slept) is stopped: its timeouts are the pause's"
# ---------------------------------------------------------------------------
# A stub date whose clock jumps 1000 s per call stands in for a host that
# slept between two heartbeats; the stub Stryker would run for minutes.
printf '#!/bin/sh\necho "STUB npx: $* in $(pwd)"\nexec sleep 300\n' >"$STUB/npx"
cat >"$STUB/date" <<STUB
#!/bin/sh
f='$SCRATCH/clock'; n=\$(cat "\$f" 2>/dev/null || echo 0); n=\$((n + 1000)); echo "\$n" >"\$f"; echo "\$n"
STUB
chmod +x "$STUB/date"
expect_exit 3 "a paused run exits 3" -- run_wrapper
expect_said "paused this run for"
expect_said "score is void"
clean && pass "a paused run leaves the caller's tree clean" || fail "a paused run left changes"
recover=$(printf '%s\n%s\n' "$T_OUT" "$T_ERR" | sed -n 's/^mutation.kit.sh: remove it with: //p' | tail -1)
[ -n "$recover" ] && sh -c "$recover" && [ "$(leftovers)" = 0 ] &&
	pass "the printed recovery command cleans up after a pause" || fail "recovery after a pause failed"
rm -f "$STUB/date"

t_done "the kit's mutation wrapper"
