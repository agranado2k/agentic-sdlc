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
# The copy is what git would hand over (#690): tracked files with their working
# changes, plus untracked files nobody ignored — the work in progress a suite
# run is checking — and never an ignored directory, a tracked file deleted in
# the working tree, or anything else the checkout merely happens to hold.
printf '.trace/\nworktree/\n' >"$FAKEKIT/.gitignore"
printf 'gone\n' >"$FAKEKIT/deleted.txt"
git -C "$FAKEKIT" add -A >/dev/null; git -C "$FAKEKIT" commit -q -m "ignore and delete"
rm "$FAKEKIT/deleted.txt"
mkdir -p "$FAKEKIT/.trace/blobs"; printf 'trace\n' >"$FAKEKIT/.trace/blobs/big"
printf 'edited\n' >"$FAKEKIT/README.md"
printf 'fresh\n' >"$FAKEKIT/fresh.txt"
ln -s no-such-target "$FAKEKIT/dangling"
TREE3="$SCRATCH/tree3"
t_kit_tree "$FAKEKIT" "$TREE3" 2>"$SCRATCH/tree3.err"
[ ! -e "$TREE3/.trace" ] && pass "an ignored directory stays out of the copy" || fail "the ignored .trace/ rode into the copy"
[ "$(cat "$TREE3/README.md" 2>/dev/null)" = edited ] && pass "a tracked file arrives with its working change" || fail "the tracked file's working change is missing"
[ -f "$TREE3/fresh.txt" ] && pass "an untracked, unignored file arrives" || fail "an untracked, unignored file was left out"
[ ! -e "$TREE3/deleted.txt" ] && [ ! -s "$SCRATCH/tree3.err" ] &&
	pass "a tracked file deleted in the working tree is skipped in silence" ||
	fail "the deleted file arrived or the copy complained: $(cat "$SCRATCH/tree3.err")"
[ -L "$TREE3/dangling" ] && pass "a symlink whose target is missing arrives as a link" || fail "the dangling symlink was dropped from the copy"
# A source git cannot list is refused, never copied as an empty fixture that
# every assertion downstream would then misread.
NOTGIT="$SCRATCH/notgit"; mkdir -p "$NOTGIT"; printf 'x\n' >"$NOTGIT/file"
(t_kit_tree "$NOTGIT" "$SCRATCH/tree4") 2>/dev/null
[ $? -eq 2 ] && pass "a source git cannot list is refused with exit 2" || fail "a source git cannot list was copied as if it were a kit"

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

# The trace's identity and policy variables are scrubbed the same way, and for
# the same reason: a kit session's hooks export TRACE_SESSION to every tool
# call, so a suite run inside one inherited it and the trace suite's emits
# carried a session its assertions did not expect — red for the operator,
# green in CI (#303). The probe exports every one of them, sources the lib,
# and lists what survived between two sentinels — so a source that failed
# prints nothing and goes red, rather than reading as "nothing survived".
probe=$(TRACE_SESSION=s TRACE_RUN=r TRACE_PARENT=p TRACE_DIR=/nowhere TRACE_CONFIG=/nowhere.sh TRACE_QUIET=1 \
	sh -c '. "$0"; printf "sourced["; env | grep "^TRACE_" | sort | tr "\n" " "; printf "]"' "$KIT/tests/lib.sh" 2>/dev/null)
[ "$probe" = "sourced[]" ] &&
	pass "after sourcing tests/lib.sh, no TRACE_ identity or policy variable the caller exported survives" ||
	fail "the trace scrub is not effective: the sourced suite still sees $probe"

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
[ "$T_SCRATCH_PREFIX" = 'kit-suite.' ] &&
	pass "the harness names its scratch prefix, and it is the literal the checklist tells an operator to look for" ||
	fail "the prefix is '$T_SCRATCH_PREFIX', not the 'kit-suite.' every document names"
case "$SCRATCH" in
*/"$T_SCRATCH_PREFIX"*) pass "this suite's own scratch carries it: $(basename "$SCRATCH")" ;;
*) fail "this suite's scratch is '$(basename "$SCRATCH")', which the prefix cannot find" ;;
esac
# The prefix is the `-name` of a `find … -exec rm -rf` on a shared directory,
# so it is a CONSTANT and not a seam: an override would put that removal
# behind an environment variable, where `*` matches everything in $TMPDIR.
grep -q "^T_SCRATCH_PREFIX='kit-suite\.'$" "$T_ROOT/tests/lib.sh" &&
	pass "…and it is assigned as a constant, not read from the environment" ||
	fail "T_SCRATCH_PREFIX is overridable — an environment variable now decides what rm -rf matches"

# The acceptance case, run for real: kill a suite with a signal it cannot trap
# and look at what is left by NAME alone. $0 is set to a path under tests/ so
# the harness derives its own root exactly as it does for a real suite — no
# widened seam, and nothing written into the tree.
KILL_BODY='. "$(dirname "$0")/lib.sh"; t_init; echo "$SCRATCH" > "$VICTIM_OUT"; kill -9 $$'
mkdir -p "$SCRATCH/tmproot"
VICTIM_OUT="$SCRATCH/victim-path" TMPDIR="$SCRATCH/tmproot" \
	sh -c "$KILL_BODY" "$T_ROOT/tests/killme" >/dev/null 2>&1
VICTIM=$(cat "$SCRATCH/victim-path" 2>/dev/null)
if [ -n "$VICTIM" ] && [ -d "$VICTIM" ]; then
	case "$(basename "$VICTIM")" in
	"$T_SCRATCH_PREFIX"*) pass "a suite killed with SIGKILL leaves scratch identifiable by name alone" ;;
	*) fail "the killed suite left '$(basename "$VICTIM")' — anonymous, exactly the state #221 is about" ;;
	esac
else
	fail "the killed suite left nothing to identify (victim='$VICTIM')"
fi

# THE SWEEP, and the three predicates that make it safe on a shared /tmp. The
# fixtures are the dispatcher's (tests/agent-dispatch.test.sh), because this is
# its mechanism one layer up and a weaker set here would be a weaker claim.
SWEEPROOT="$SCRATCH/sweeproot"
mkdir -p "$SWEEPROOT"
OLDDIR="$SWEEPROOT/${T_SCRATCH_PREFIX}oldone"
FRESHDIR="$SWEEPROOT/${T_SCRATCH_PREFIX}freshone"
STRANGER="$SWEEPROOT/tmp.somebodyelse"
NESTED="$OLDDIR/nested/deeper"
PLAINFILE="$SWEEPROOT/${T_SCRATCH_PREFIX}notadirectory"
LINKTARGET="$SCRATCH/link-target"
EVILLINK="$SWEEPROOT/${T_SCRATCH_PREFIX}evil"
mkdir -p "$FRESHDIR" "$STRANGER" "$NESTED" "$LINKTARGET"
: >"$LINKTARGET/precious"
: >"$PLAINFILE"
ln -s "$LINKTARGET" "$EVILLINK"
# Older than the age, by an hour rather than a month: a 30-day fixture would
# pass a sweep whose threshold had drifted to a week.
_old_stamp=$(date -d '25 hours ago' +%Y%m%d%H%M 2>/dev/null || echo 202001010000)
touch -t "$_old_stamp" "$OLDDIR" 2>/dev/null || touch -t 202001010000 "$OLDDIR"
# The plain file and the symlink are aged TOO. Left fresh, the age predicate
# would exclude them on its own and `-type d` could be deleted without any
# assertion noticing — the mutant that proved it.
touch -t "$_old_stamp" "$PLAINFILE" 2>/dev/null || touch -t 202001010000 "$PLAINFILE"
touch -h -t "$_old_stamp" "$EVILLINK" 2>/dev/null || touch -h -t 202001010000 "$EVILLINK" 2>/dev/null || :
# And the symlink's TARGET is aged as well. Left fresh, a sweep that followed
# links (`find -L`) would resolve the link to a fresh directory and skip it on
# age alone — the physical walk would be deletable without a failing check.
touch -t "$_old_stamp" "$LINKTARGET" 2>/dev/null || touch -t 202001010000 "$LINKTARGET"
# Driven through t_init, not by calling the sweep directly: acceptance line 2
# is that a LATER SUITE removes it, and the wiring is half of that claim.
_sweep_err="$SCRATCH/sweep-err"
( TMPDIR="$SWEEPROOT" HOME="$HOME" sh -c '. "$(dirname "$0")/lib.sh"; t_init' \
	"$T_ROOT/tests/sweeper" ) 2>"$_sweep_err" >/dev/null
_sweep_msg=$(cat "$_sweep_err")
[ -d "$OLDDIR" ] && fail "a later suite left scratch older than the sweep age" ||
	pass "a later suite's t_init removes scratch older than the sweep age"
[ -d "$FRESHDIR" ] && pass "…and leaves fresh scratch alone — a suite may still be running in it" ||
	fail "the sweep removed fresh scratch, which could be a running suite's"
[ -d "$STRANGER" ] && pass "…and never touches a directory without the prefix" ||
	fail "the sweep removed 'tmp.somebodyelse' — it is not ours to remove"
[ -f "$PLAINFILE" ] && pass "…nor a plain FILE carrying the prefix — -type d is what keeps it a directory sweep" ||
	fail "the sweep removed a plain file: -type d is missing or ineffective"
[ -L "$EVILLINK" ] && pass "…nor a symlink carrying the prefix — the walk is physical" ||
	fail "the sweep removed a symlink — it followed or matched one, which -type d must prevent"
[ -f "$LINKTARGET/precious" ] && pass "…and what such a symlink POINTS AT survives, which is the whole point" ||
	fail "the sweep followed a planted symlink and removed its target"
case "$_sweep_msg" in
*swept*) pass "…and says on stderr what it removed" ;;
*) fail "the sweep removed scratch silently: '$_sweep_msg'" ;;
esac

# A DEAD OWNER IS SWEPT NOW, A LIVE ONE NEVER (#676). Two OOM-killed suites
# left ~900 MB of scratch that the day-long age kept, and the quota'd /tmp
# refused every session's writes until it was swept by hand. Scratch names
# its owning process, so the next suite to start tells dead from live.
OWNROOT="$SCRATCH/ownroot"
mkdir -p "$OWNROOT"
# The real thing first: a suite killed with SIGKILL, minutes old at most.
VICTIM_OUT="$SCRATCH/victim2-path" TMPDIR="$OWNROOT" \
	sh -c "$KILL_BODY" "$T_ROOT/tests/killme" >/dev/null 2>&1
VICTIM2=$(cat "$SCRATCH/victim2-path" 2>/dev/null)
[ -n "$VICTIM2" ] && [ -d "$VICTIM2" ] ||
	fail "the second killed suite left no scratch to sweep (victim='$VICTIM2')"
# A live owner, by name — this suite's own process — and aged past the sweep
# age, so the age rule alone would take it.
_own_tok=$(t_scratch_owner) || fail "t_scratch_owner printed no owner token"
LIVEDIR="$OWNROOT/${T_SCRATCH_PREFIX}${_own_tok}.livexx"
mkdir -p "$LIVEDIR"
touch -t "$_old_stamp" "$LIVEDIR" 2>/dev/null || touch -t 202001010000 "$LIVEDIR"
# A fresh directory with no recorded owner: the age rule still holds it.
UNOWNED="$OWNROOT/${T_SCRATCH_PREFIX}legacy"
mkdir -p "$UNOWNED"
# A dead owner in ANOTHER pid namespace is not ours to judge — kill -0 there
# answers about some other process.
sh -c 'exit 0' &
_dead=$!
wait "$_dead"
FOREIGN="$OWNROOT/${T_SCRATCH_PREFIX}${_dead}-1.foreign"
mkdir -p "$FOREIGN"
# A token that only LOOKS like an owner — a pid with a letter in it — names no
# process, so it is left to the age rule; a probe on it would answer "dead".
MALFORMED="$OWNROOT/${T_SCRATCH_PREFIX}1x-${_own_tok#*-}.malformed"
mkdir -p "$MALFORMED"
_own_err="$SCRATCH/own-err"
( TMPDIR="$OWNROOT" sh -c '. "$(dirname "$0")/lib.sh"; t_init' \
	"$T_ROOT/tests/sweeper" ) 2>"$_own_err" >/dev/null ||
	fail "the sweeping suite itself failed — the cases below would mislead: $(cat "$_own_err")"
[ -n "$VICTIM2" ] && [ ! -d "$VICTIM2" ] &&
	pass "a killed suite's fresh scratch is removed at the next start — its owner is gone" ||
	fail "a killed suite's scratch survived the next start (owner dead, age irrelevant): '$VICTIM2'"
[ -d "$LIVEDIR" ] && pass "…and a LIVE owner's scratch is kept, however old" ||
	fail "the sweep removed scratch whose owner process is still running"
[ -d "$UNOWNED" ] && pass "…and fresh scratch with no recorded owner is left to the age rule" ||
	fail "the sweep removed fresh scratch whose owner it could not name"
[ -d "$FOREIGN" ] && pass "…and an owner recorded in another pid namespace is left to the age rule" ||
	fail "the sweep judged a process in another pid namespace dead by this one's kill -0"
# A dead owner's scratch the sweeping user does not own is not judged dead:
# signal 0 on another user's pid fails as if it were gone. The sweep is run
# under an `id` that answers another uid, so this directory is "not ours".
NOTMINE="$OWNROOT/${T_SCRATCH_PREFIX}${_dead}-${_own_tok#*-}.notmine"
mkdir -p "$NOTMINE" "$SCRATCH/fakeid"
printf '#!/bin/sh\necho 99999\n' >"$SCRATCH/fakeid/id"
chmod +x "$SCRATCH/fakeid/id"
( PATH="$SCRATCH/fakeid:$PATH" TMPDIR="$OWNROOT" sh -c '. "$(dirname "$0")/lib.sh"; t_init' \
	"$T_ROOT/tests/sweeper" ) >/dev/null 2>&1
[ -d "$NOTMINE" ] && pass "…and a dead owner's scratch under another uid is left to the age rule" ||
	fail "the sweep removed scratch it does not own on a signal-0 failure that may only mean another user's process"
[ -d "$MALFORMED" ] && pass "…and a malformed owner token is left to the age rule, never probed" ||
	fail "the sweep removed fresh scratch whose owner token is not a pid"
case "$(cat "$_own_err")" in
*'owner process is gone'*) pass "…and says on stderr what it removed, and why" ;;
*) fail "the owner sweep was silent: '$(cat "$_own_err")'" ;;
esac

# One variable, one default, validated before it reaches arithmetic, and
# documented where a reader of the harness meets it.
[ "$T_SCRATCH_SWEEP_DAYS" = 1 ] && pass "the sweep age is one variable with a kit default of 1 day" ||
	fail "T_SCRATCH_SWEEP_DAYS is '$T_SCRATCH_SWEEP_DAYS', not the documented default"
for _bad in 0 08 'a[$(echo INJECTED)]'; do
	_got=$(T_SCRATCH_SWEEP_DAYS="$_bad" sh -c '. "$(dirname "$0")/lib.sh" >/dev/null 2>&1; printf "%s" "$T_SCRATCH_SWEEP_DAYS"' "$T_ROOT/tests/ageprobe" 2>/dev/null)
	[ "$_got" = 1 ] && pass "T_SCRATCH_SWEEP_DAYS='$_bad' is refused and falls back to 1" ||
		fail "T_SCRATCH_SWEEP_DAYS='$_bad' became '$_got' — it reaches \$(( )) unvalidated"
done
grep -q 'T_SCRATCH_SWEEP_DAYS' "$T_ROOT/tests/lib.sh" &&
	grep -q "$T_SCRATCH_PREFIX" "$T_ROOT/tests/lib.sh" &&
	pass "the harness header names both" || fail "the harness does not document its own scratch"

# Every suite that makes the prefixed scratch makes it through t_scratch, so
# it is named for its owner and sweeps at start (#676): a suite that spells
# the template by hand makes owner-less scratch the age rule keeps for a day.
# The pattern is split so this suite's own line never matches it.
_hand_pat='T_SCRATCH_PREFIX''}XXXXXX'
_handmade=''
for f in "$T_ROOT"/tests/*.sh; do
	case ${f##*/} in lib.sh) continue ;; esac
	grep -qF "$_hand_pat" "$f" && _handmade="$_handmade ${f##*/}"
done
[ -z "$_handmade" ] && pass "every suite makes its prefixed scratch through t_scratch, named for its owner" ||
	fail "these build kit-suite scratch by hand, with no owner in its name:$_handmade"

# EVERY suite goes through the harness or carries the prefix. DEFAULT-DENY:
# enumerating the anonymous spellings let `mktemp --directory` and `mktemp -dq`
# through, so what is required is a template rooted in a variable — anything
# else is anonymous by some spelling.
_anon=''
for f in "$T_ROOT"/tests/*.sh; do
	b=$(basename "$f")
	[ "$b" = lib.sh ] && continue
	# Only a CALL counts — `$(mktemp …)`. Prose that merely names the command,
	# including this suite's own fail message, is not a call.
	while IFS= read -r _line; do
		case "$_line" in
		'') continue ;;
		*'\$(mktemp'*) continue ;;
		*'"$'*) continue ;;
		*) _anon="$_anon $b:${_line%%:*}" ;;
		esac
	done <<EOF
$(grep -n '\$(mktemp' "$f" | grep -v '^[0-9]*:[[:space:]]*#')
EOF
done
[ -z "$_anon" ] && pass "every mktemp under tests/ carries a template rooted in a variable" ||
	fail "these call mktemp with no variable-rooted template:$_anon"

t_done "fixture builders"
