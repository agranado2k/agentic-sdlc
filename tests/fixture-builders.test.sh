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
# convention — proves the copy drops it. The source is deliberately the
# LOGICAL scratch path: on macOS that is a symlink into /private, git reports
# the worktree by its physical path, and the builder must resolve the
# difference itself rather than leave it to every caller.
FAKEKIT="$SCRATCH/fakekit"
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
[ "$(git -C "$R" config user.name)" = "Fixture Name" ] && [ "$(git -C "$R" config user.email)" = "fixture@example.invalid" ] &&
	pass "identity set" || fail "identity not set"
[ "$(git -C "$R" config commit.gpgsign)" = "false" ] && [ "$(git -C "$R" config tag.gpgSign)" = "false" ] &&
	[ "$(git -C "$R" config tag.forceSignAnnotated)" = "false" ] &&
	pass "commit, tag and annotated-tag signing are off" || fail "a signing switch is still on"
[ "$(git -C "$R" config core.hooksPath)" = ".git/no-such-hooks" ] && pass "the machine's hooks are out of reach" || fail "hooks path not neutralised"
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
[ "$(git -C "$HIST" log --format=%s v0.1.0 -1)" = "release 0.1.0" ] && [ "$(git -C "$HIST" log --format=%s v0.2.0 -1)" = "release 0.2.0" ] &&
	pass "each release commit is titled after its tag, without the v" || fail "release commit subjects are not derived from the tags"

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
# A source that still carries a .git (a kit clone, say) must not leak its
# history into the consumer: the copy drops it before the identity is set.
SRCREPO="$SCRATCH/srcrepo"; mkdir -p "$SRCREPO"; cp -R "$TREE/." "$SRCREPO/"
t_git_identity "$SRCREPO" t t@example.invalid
git -C "$SRCREPO" add -A >/dev/null; git -C "$SRCREPO" commit -q -m "first"; git -C "$SRCREPO" commit -q --allow-empty -m "second"
CONS2="$SCRATCH/consumer-from-repo"
t_consumer_from "$SRCREPO" "$CONS2" "Fixture Consumer" "consumer@example.invalid" --no-dogfood "Fixture Consumer" "A throwaway."
cd "$here" || exit 2
[ "$(git -C "$CONS2" rev-list --count HEAD)" = 1 ] && pass "a .git-bearing source leaves exactly one commit in the consumer" || fail "the source's history leaked into the consumer ($(git -C "$CONS2" rev-list --count HEAD) commits)"

# ---------------------------------------------------------------------------
banner "5. The budget's host fixtures — a fake host, no user manager, the uid's tasks"
# ---------------------------------------------------------------------------
# The dispatch suite and the suite-budget suite derive a budget against the
# same fake host and fall to the rlimit rung the same way; each builder is
# held to the files the dispatcher's derivation reads.
FH="$SCRATCH/fake-host"
t_fake_host "$FH" 10008 2141820
[ "$HOST" = "$FH" ] && [ "$SLICE" = "$FH/sys/fs/cgroup/user.slice/user-1000.slice" ] && pass "t_fake_host sets HOST and SLICE" || fail "t_fake_host set HOST='$HOST' SLICE='$SLICE'"
[ "$(cat "$FH/proc/self/cgroup")" = "0::/user.slice/user-1000.slice/session-1.scope" ] && pass "the process sits in the session scope under the user slice" || fail "unexpected cgroup line: $(cat "$FH/proc/self/cgroup")"
[ "$(cat "$SLICE/pids.max")" = 10008 ] && pass "the slice carries the task ceiling given" || fail "slice pids.max is $(cat "$SLICE/pids.max")"
[ "$(cat "$SLICE/session-1.scope/pids.max")" = max ] && [ "$(cat "$FH/sys/fs/cgroup/user.slice/pids.max")" = max ] && pass "the scope and user.slice carry none" || fail "the scope or user.slice carries a ceiling"
[ "$(cat "$SLICE/session-1.scope/cgroup.controllers")" = "cpu memory pids" ] && pass "both controllers are delegated to the process's own cgroup" || fail "cgroup.controllers is '$(cat "$SLICE/session-1.scope/cgroup.controllers")'"
grep -q '^MemAvailable:    2141820 kB$' "$FH/proc/meminfo" && pass "/proc/meminfo carries the MemAvailable given" || fail "meminfo lacks the MemAvailable given"
NUM="$SCRATCH/no-user-manager"
t_no_user_manager "$NUM"
if PATH="$NUM:$PATH" systemctl --user show --property=Version >/dev/null 2>&1; then
	fail "t_no_user_manager's systemctl answered — the ladder would not fall to rlimits"
else
	pass "t_no_user_manager's systemctl fails, so the ladder falls to rlimits"
fi
case "$(t_uid_tasks)" in
'' | *[!0123456789]*) fail "t_uid_tasks printed '$(t_uid_tasks)', not a whole number" ;;
*) pass "t_uid_tasks prints a whole number ($(t_uid_tasks))" ;;
esac

# ---------------------------------------------------------------------------
banner "Sourcing the lib pins collation — the environment does not decide an order"
# ---------------------------------------------------------------------------
# The probe runs in a subshell whose LC_ALL is a UTF-8 locale — the one that
# ignores a leading `.` and sorts `adapters/` before `.agents/` — then sources
# the lib and sorts. If the lib's pin is gone, the UTF-8 order comes back and
# this goes red. Skipped, and says so, where the locale is not installed.
if locale -a 2>/dev/null | grep -qi '^en_US\.utf-\?8$'; then
	# The lib path goes in as $0, not $1: tests/lib.sh derives its repo root
	# from $0, and `sh -c` with a placeholder there would point it nowhere.
	probe=$(LC_ALL=en_US.UTF-8 sh -c '. "$0"; printf ".agents/x\nadapters/y\n" | sort | head -n 1' "$KIT/tests/lib.sh" 2>/dev/null)
	[ "$probe" = ".agents/x" ] &&
		pass "after sourcing tests/lib.sh, .agents/ sorts before adapters/ even from a UTF-8 shell" ||
		fail "the collation pin is not effective: sorted '$probe' first under en_US.UTF-8"
else
	skip "en_US.UTF-8 is not installed — the collation pin is NOT held on this machine"
fi

# ---------------------------------------------------------------------------
banner "The split-stream helpers can go red"
# ---------------------------------------------------------------------------
# Three suites lean on t_run_split and the s_assert_* family for every claim
# they make. The suites only ever drive them green, so a helper that always
# passed would pass every suite. Each is held to printing FAIL on a mismatch —
# in a subshell, so the failures counted here are this section's own.
t_run_split sh -c 'echo out; echo err >&2; exit 3'
[ "$S_OUT" = "out" ] && [ "$S_ERR" = "err" ] && [ "$S_STATUS" = 3 ] &&
	pass "t_run_split keeps stdout, stderr and status apart" ||
	fail "t_run_split mixed its streams: out='$S_OUT' err='$S_ERR' status=$S_STATUS"
red() { (failures=0; "$@" >/dev/null 2>&1; [ "$failures" = 1 ]); }
red s_assert_resolved "not-out" x   && pass "s_assert_resolved fails on a wrong answer"      || fail "s_assert_resolved passed a wrong answer"
red s_assert_out_is "not-out" x     && pass "s_assert_out_is fails on a wrong answer"        || fail "s_assert_out_is passed a wrong answer"
red s_assert_status 0 x             && pass "s_assert_status fails on a wrong status"        || fail "s_assert_status passed a wrong status"
red s_assert_out_has "absent" x     && pass "s_assert_out_has fails on a missing needle"     || fail "s_assert_out_has passed a missing needle"
red s_assert_out_lacks "out" x      && pass "s_assert_out_lacks fails on a present needle"   || fail "s_assert_out_lacks passed a present needle"
red s_assert_err_has "absent"       && pass "s_assert_err_has fails on a missing needle"     || fail "s_assert_err_has passed a missing needle"
red s_assert_err_lacks "err"        && pass "s_assert_err_lacks fails on a present needle"   || fail "s_assert_err_lacks passed a present needle"

# ---------------------------------------------------------------------------
banner "Suite scratch names itself, and stale scratch is swept (#221)"
# ---------------------------------------------------------------------------
# A suite killed at its budget (#209) dies before its trap, by design, so its
# scratch survives it — and `mktemp -d` with no template names that survivor
# `tmp.XXXXXX`, which nobody can distinguish from anyone else's. The 0.20.0
# wave left 83 of them on one host in a day. The dispatcher already solved
# this one layer down (#210): a named prefix, and a sweep of what is older
# than a run could plausibly be. This is the same answer for the harness.
[ -n "${T_SCRATCH_PREFIX:-}" ] && pass "the harness names its scratch prefix ($T_SCRATCH_PREFIX)" ||
	fail "tests/lib.sh defines no T_SCRATCH_PREFIX — scratch left by a killed suite is anonymous"
case "$SCRATCH" in
*/"$T_SCRATCH_PREFIX"*) pass "this suite's own scratch carries it: $(basename "$SCRATCH")" ;;
*) fail "this suite's scratch is '$(basename "$SCRATCH")', which the prefix cannot find" ;;
esac

# The acceptance case, run for real: kill a suite with a signal it cannot trap
# and look at what is left by NAME alone.
KILLME="$SCRATCH/killme.sh"
cat >"$KILLME" <<KILL_EOF
#!/bin/sh
T_ROOT="$T_ROOT"
export T_ROOT
. "$T_ROOT/tests/lib.sh"
t_init
echo "\$SCRATCH" > "$SCRATCH/victim-path"
kill -9 \$\$
KILL_EOF
chmod +x "$KILLME"
TMPDIR="$SCRATCH/tmproot" && mkdir -p "$TMPDIR"
TMPDIR="$TMPDIR" sh "$KILLME" >/dev/null 2>&1
VICTIM=$(cat "$SCRATCH/victim-path" 2>/dev/null)
if [ -n "$VICTIM" ] && [ -d "$VICTIM" ]; then
	case "$(basename "$VICTIM")" in
	"$T_SCRATCH_PREFIX"*) pass "a suite killed with SIGKILL leaves scratch identifiable by name alone" ;;
	*) fail "the killed suite left '$(basename "$VICTIM")' — anonymous, exactly the state #221 is about" ;;
	esac
else
	fail "the killed suite left nothing to identify (victim='$VICTIM')"
fi

# The sweep: old scratch goes and says so, fresh scratch stays, and anything
# without the prefix is never touched — the dispatcher's three rules.
SWEEPROOT="$SCRATCH/sweeproot"
mkdir -p "$SWEEPROOT"
OLDDIR="$SWEEPROOT/${T_SCRATCH_PREFIX}oldone"
FRESHDIR="$SWEEPROOT/${T_SCRATCH_PREFIX}freshone"
STRANGER="$SWEEPROOT/tmp.somebodyelse"
mkdir -p "$OLDDIR" "$FRESHDIR" "$STRANGER"
touch -d '30 days ago' "$OLDDIR" 2>/dev/null || touch -t "$(date -d '30 days ago' +%Y%m%d%H%M 2>/dev/null || echo 202001010000)" "$OLDDIR"
_sweep_err=$(mktemp "$SCRATCH/sweep-err.XXXXXX")
( TMPDIR="$SWEEPROOT"; export TMPDIR; t_sweep_scratch 2>"$_sweep_err" )
_sweep_msg=$(cat "$_sweep_err")
[ -d "$OLDDIR" ] && fail "the sweep left scratch older than the sweep age" || pass "the sweep removes scratch older than the sweep age"
[ -d "$FRESHDIR" ] && pass "…and leaves fresh scratch alone — a suite may still be running in it" ||
	fail "the sweep removed fresh scratch, which could be a running suite's"
[ -d "$STRANGER" ] && pass "…and never touches a directory without the prefix" ||
	fail "the sweep removed 'tmp.somebodyelse' — it is not ours to remove"
case "$_sweep_msg" in
*swept*) pass "…and says on stderr what it removed" ;;
*) fail "the sweep removed scratch silently: '$_sweep_msg'" ;;
esac

# One variable, one default, documented where a reader of the harness meets it.
[ -n "${T_SCRATCH_SWEEP_DAYS:-}" ] && pass "the sweep age is one variable ($T_SCRATCH_SWEEP_DAYS day(s))" ||
	fail "no T_SCRATCH_SWEEP_DAYS — the age is buried in the sweep"
grep -q 'T_SCRATCH_SWEEP_DAYS' "$T_ROOT/tests/lib.sh" &&
	grep -q "$T_SCRATCH_PREFIX" "$T_ROOT/tests/lib.sh" &&
	pass "the harness header names both" || fail "the harness does not document its own scratch"

# EVERY suite goes through the harness or carries the prefix: one anonymous
# `mktemp -d` is one more directory nobody can safely remove.
_anon=''
for f in "$T_ROOT"/tests/*.sh; do
	b=$(basename "$f")
	[ "$b" = lib.sh ] && continue
	# A bare `mktemp -d` with no template, outside a comment.
	# `\$(mktemp` is text being WRITTEN into a script for another shell — the
	# recipe's own working directory, quoted verbatim in UPDATING.md — not
	# scratch this suite creates. The escape is the discriminator.
	grep -n 'mktemp -d' "$f" | grep -v '^[0-9]*:[[:space:]]*#' | grep -v '\\\$(mktemp' |
		grep -qE 'mktemp -d\)|mktemp -d[[:space:]]*$|mktemp -d[[:space:]]*\|\|' &&
		_anon="$_anon $b"
done
[ -z "$_anon" ] && pass "no suite makes anonymous scratch" ||
	fail "these suites still call a bare 'mktemp -d':$_anon"

t_done "fixture builders"
