#!/bin/sh
# tests/suite-budget.test.sh — every suite runs inside the worker budget.
#
# ADR-0006 gives a dispatched worker a budget: a task ceiling and a memory
# ceiling on its whole process tree, derived from the host. #209 puts every
# suite under the same one, applied by tests/lib.sh the moment a suite sources
# it — so the incident that started the wave (a runaway suite filling the
# login session's task ceiling, #205) fails as a red suite instead of a frozen
# host. This suite is the test harness's oracle for that, through two seams:
#
#   1. THE BUDGET LIBRARY. tests/lib.sh takes the derivation, the ladder and
#      the verdict from scripts/budget.lib.sh's four functions — the ones the
#      dispatcher calls — so a suite and a worker cannot disagree about a
#      number, and no file outside the library names a private helper of it.
#   2. THE TEST HARNESS SEAM. A STUB SUITE — a script that sources tests/lib.sh the
#      way every suite does — is run as `sh stub.sh`, against a fake host the
#      dispatcher already knows how to read (AGENT_DISPATCH_HOST_ROOT), so the
#      budget is small and the numbers are this suite's. A green stub runs
#      once inside the budget and says so; a runaway stub stops at the
#      ceiling and comes back as a FAILURE naming it, exit 71, with the
#      calling shell still forking; the off switch runs a stub bare and loud;
#      the marker bounds the recursion; a bad switch value is refused.
#
# The runaways are SELF-BOUNDED in time, as tests/agent-dispatch.test.sh's
# are: where enforcement does not bite they end on their own and say so, and
# that line is what the leg fails on. Every stub suite here runs in a scope
# that is a SIBLING of this suite's own (a scope from inside a scope is not a
# child), so nothing here leans on an outer budget as a backstop.
#
# Usage: sh tests/suite-budget.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)

# This suite is the test harness's oracle, so it cannot lean on the test
# harness's own recursion bound to be one: a test harness that lost that
# bound would re-execute this file until the host refused to fork, and no
# assertion below would ever run. Its own count, carried above the source
# line where both runs pass: the outer run is 1, the inner 2, a third is the
# bound gone.
SUITE_BUDGET_TEST_DEPTH=$((${SUITE_BUDGET_TEST_DEPTH:-0} + 1))
export SUITE_BUDGET_TEST_DEPTH
[ "$SUITE_BUDGET_TEST_DEPTH" -le 2 ] || { echo "  FAIL  $0 started a ${SUITE_BUDGET_TEST_DEPTH}rd time — the test harness re-executes without its marker; its recursion bound is gone" >&2; exit 99; }

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

# ---------------------------------------------------------------------------
banner "1. The test harness reaches the Budget through the library's interface"
# ---------------------------------------------------------------------------
# tests/lib.sh confines a suite through scripts/budget.lib.sh — budget_derive,
# budget_run, budget_verdict and budget_inherited_bounds — the same four the
# dispatcher calls, so a suite and a worker cannot disagree about a number
# (#742, #748). The numbers come from the library on the same fake host the
# dispatch suite uses: 25% of the slice's 10008 tasks, 50% of 2091 MiB.
t_fake_host "$SCRATCH/host" 10008 2141820
# derive — source the library the way a caller does, against the fake host,
# and print its record.
derive() { t_exec env AGENT_DISPATCH_HOST_ROOT="$HOST" "$@" sh -c '_budget_here="$1"
. "$1/budget.lib.sh"
budget_derive' probe "$KIT/scripts"; }
derive
expect_status 0 "budget_derive derives against the fake host"
expect_out_has "tasks=2502" "…the task ceiling the dispatch suite's dry run shows: 25% of 10008"
expect_out_has "memory_mib=1045" "…and the memory ceiling: 50% of 2091 MiB"
# The policy file is read through the same reader: a ceiling in it clamps.
CFG_SMALL="$SCRATCH/small.config.sh"
printf "AGENT_BUDGET_TASKS_CEILING='300'\nAGENT_BUDGET_MEMORY_CEILING_MIB='600'\n" >"$CFG_SMALL"
derive AGENTS_CONFIG="$CFG_SMALL"
expect_out_has "tasks=300" "the policy file's task clamp applies through the library"
expect_out_has "memory_mib=600" "…and its memory clamp"
# The inherited case: an outer budget in the environment is taken as given.
derive AGENT_DISPATCH_BUDGET_TASKS=777 AGENT_DISPATCH_BUDGET_MEMORY_MIB=888
expect_out_has "mode=inherited" "an outer dispatch's budget is inherited through the library"
expect_out_has "tasks=777" "…its task ceiling as given"
# And a policy value that cannot be a budget is refused where the caller can
# hear it: status 2, never a default, and the caller's shell goes on.
printf "AGENT_BUDGET_TASKS_PERCENT='lots'\n" >"$CFG_SMALL"
t_exec env AGENT_DISPATCH_HOST_ROOT="$HOST" AGENTS_CONFIG="$CFG_SMALL" sh -c '_budget_here="$1"
. "$1/budget.lib.sh"
budget_derive
echo "caller status $?"' probe "$KIT/scripts"
expect_out_has "caller status 2" "a policy value that is not a whole number is refused with status 2 — and the caller goes on"
expect_err_has "AGENT_BUDGET_TASKS_PERCENT"

# R21: no file outside the library names a function private to it. The
# private names are read from the library itself — every function it defines
# whose name starts with an underscore, the counters reader it ships as text
# among them — so a private helper added or renamed there is held here with
# no edit to this suite. The dated records are exempt: VERSION's history,
# UPDATING.md, the diary and the decision records quote what a file said
# when it was written, and rewriting a record to drop a name would falsify
# it. Every other tracked file, code and prose alike, is held.
# private_names_outside <root> — prints `<file>: <name>` for each hit under a
# git tree at <root>; nothing when clean.
private_names_outside() {
	_pno_names=$(sed -n 's/^\(_[A-Za-z0-9_]*\)() *[({].*/\1/p' "$1/scripts/budget.lib.sh" | sort -u)
	[ -n "$_pno_names" ] || { echo "no private names read from $1/scripts/budget.lib.sh"; return 0; }
	for _pno_n in $_pno_names; do
		git -C "$1" grep -lw -e "$_pno_n" -- . ':!scripts/budget.lib.sh' ':!VERSION' ':!UPDATING.md' ':!docs/diary.md' ':!docs/adr' 2>/dev/null |
			sed "s|\$|: $_pno_n|"
	done
}
HITS=$(private_names_outside "$KIT")
[ -z "$HITS" ] && pass "no file outside scripts/budget.lib.sh names a function private to it" ||
	fail "files outside scripts/budget.lib.sh name its private functions: $(printf '%s' "$HITS" | tr '\n' ';')"
# …and the check can fail: a scratch tree whose one caller names a private
# helper is caught, by file and by name — the helper read from the library,
# so this suite names none of its own. A record that quotes one is not.
PNO="$SCRATCH/pno"
mkdir -p "$PNO/scripts"
cp "$KIT/scripts/budget.lib.sh" "$PNO/scripts/budget.lib.sh"
PLANT=$(sed -n 's/^\(_[A-Za-z0-9_]*\)() *[({].*/\1/p' "$PNO/scripts/budget.lib.sh" | head -n 1)
printf '#!/bin/sh\n%s\n' "$PLANT" >"$PNO/caller.sh"
printf 'quotes %s as it once was\n' "$PLANT" >"$PNO/VERSION"
git -C "$PNO" init -q && git -C "$PNO" add -A
HITS=$(private_names_outside "$PNO")
if [ -n "$PLANT" ] && [ "$HITS" = "caller.sh: $PLANT" ]; then
	pass "…and a caller that names one is caught — the record that quotes one is not"
else
	fail "the private-name check on a planted caller printed '$HITS', expected 'caller.sh: $PLANT'"
fi

# The dispatcher no longer supports being sourced, so it no longer asks what
# name it runs under: a copy executed under another name, with the two
# libraries beside it, is the dispatcher it was.
RENAMED="$SCRATCH/renamed"; mkdir -p "$RENAMED"
cp "$KIT/scripts/agent-dispatch.sh" "$RENAMED/dispatch"
cp "$KIT/scripts/agents.lib.sh" "$KIT/scripts/budget.lib.sh" "$RENAMED/"
t_exec env AGENTS_CONFIG="$KIT/scripts/agents.kit.config.sh" sh "$KIT/scripts/agent-dispatch.sh" implementer --prompt 'x' --dry-run
ORIG_STATUS=$T_STATUS ORIG_OUT=$T_OUT
t_exec env AGENTS_CONFIG="$KIT/scripts/agents.kit.config.sh" sh "$RENAMED/dispatch" implementer --prompt 'x' --dry-run
expect_status "$ORIG_STATUS" "a copy of the dispatcher executed under another name answers as the dispatcher does"
[ -n "$ORIG_OUT" ] && [ "$T_OUT" = "$ORIG_OUT" ] && pass "…with the same output, word for word" ||
	fail "the renamed copy printed '$T_OUT', the dispatcher '$ORIG_OUT'"
expect_err_lacks "a name other than agent-dispatch.sh"

# ---------------------------------------------------------------------------
banner "2. A suite that sources tests/lib.sh runs inside the budget, once"
# ---------------------------------------------------------------------------
# The test harness seam. tests/lib.sh derives the kit root from the SUITE's $0, so
# a stub suite lives under a scratch root whose scripts/ is the kit's own:
# one symlink, and the stub sources the real tests/lib.sh the way every suite
# does. Every stub is run with the marker UNSET — this suite itself runs
# inside the budget, and a stub that inherited its marker would never
# re-execute — and with no dispatched worker's budget and no operator's
# policy file in the environment.
STUBROOT="$SCRATCH/kit"
mkdir -p "$STUBROOT/tests"
ln -s "$KIT/scripts" "$STUBROOT/scripts"
COUNT="$SCRATCH/starts"
# green — a suite that passes, and reports what it runs under: the marker,
# the process and data limits its shell has, and that it can still fork.
# The start line is written BEFORE the test harness is sourced, so the file
# counts every run of the file: the bare one and the one inside — and a
# third start ends the stub with a status of its own, so a test harness
# that re-executes without its marker is a failed leg here, not a fork loop.
GREEN="$STUBROOT/tests/green.sh"
cat >"$GREEN" <<EOF
#!/bin/sh
echo start >>"$COUNT"
[ "\$(wc -l <"$COUNT")" -le 2 ] || { echo "green: started a 3rd time — the test harness re-executes without its marker" >&2; exit 99; }
. "$KIT/tests/lib.sh"
echo "budget: \${AGENT_SUITE_BUDGET:-<unset>}"
echo "agents config: \${AGENTS_CONFIG:-<unset>}"
echo "trace: \$(env | grep '^TRACE_' | sort | tr '\n' ' ')<end>"
echo "nproc: \$(ulimit -u 2>/dev/null || ulimit -p)"
echo "data: \$(ulimit -d)"
sh -c 'exit 0' && echo "forks: yes"
exit "\${STUB_EXIT:-0}"
EOF
# unsetting <cmd…> — run it with the marker, a dispatched worker's budget
# and the operator's policy file UNSET, never exported-empty. `env NAME=`
# leaves NAME exported, so the test harness's own `export` of the marker
# would then carry nothing this suite could miss — an inner run would see
# the marker whether or not the test harness exported it, and the "exactly
# twice" legs could not fail. A subshell's `unset` is POSIX; `env -u` is not.
unsetting() { sh -c 'unset AGENT_SUITE_BUDGET AGENT_DISPATCH_BUDGET_TASKS AGENT_DISPATCH_BUDGET_MEMORY_MIB AGENTS_CONFIG; exec "$@"' unsetting "$@"; }
# stub_on <host root> <env…> <suite> [args] — run a stub suite as a suite is
# run, `sh <path>`, with those unset, that fake host in place and the start
# count fresh; stub is the same on the fake host above.
stub_on() { rm -f "$COUNT"; _so_host=$1; shift; t_exec unsetting env AGENT_DISPATCH_HOST_ROOT="$_so_host" "$@"; }
stub() { stub_on "$HOST" "$@"; }
starts() { [ -f "$COUNT" ] && wc -l <"$COUNT" | tr -d ' ' || echo 0; }

# The fake host is small: 25% of 400 tasks is below the floor, so the floor
# stands and the test harness says so; 50% of 2091 MiB is 1045 MiB.
echo 400 >"$SLICE/pids.max"
stub sh "$GREEN"
expect_status 0 "a green suite run through the test harness passes"
expect_out_has "budget: applied: tasks 256, memory 1045 MiB, rung " "…and runs inside the budget derived from the (fake) host, with the marker naming it"
expect_out_has "forks: yes" "…and can fork inside it"
expect_out_has "agents config: <unset>" "…with the environment it was started with — the kit's policy file stayed with the derivation"
expect_err_has "below the floor"
expect_err_lacks "already inside"
[ "$(starts)" = 2 ] && pass "the suite's file ran exactly twice — once bare, once inside the budget" ||
	fail "the suite's file ran $(starts) time(s) — expected 2 (the marker is the recursion bound)"
RUNG=$(printf '%s\n' "$T_OUT" | sed -n 's/^budget: applied: .*, rung //p')
case "$RUNG" in
scope | scope-tasks | rlimit | none) pass "the marker names the rung: $RUNG" ;;
*) fail "the marker names no rung this suite knows: '$RUNG'" ;;
esac
# The test harness needs the Budget library and nothing of the dispatcher's:
# a stub root whose scripts/ is the kit's own less scripts/agent-dispatch.sh
# runs its suite inside the same budget, with the same marker.
NODISP="$SCRATCH/kit-nodispatch"
mkdir -p "$NODISP/tests" "$NODISP/scripts"
for f in "$KIT"/scripts/*; do [ "${f##*/}" = agent-dispatch.sh ] || ln -s "$f" "$NODISP/scripts/${f##*/}"; done
cp "$GREEN" "$NODISP/tests/green.sh"
stub sh "$NODISP/tests/green.sh"
expect_status 0 "a suite whose kit root carries no dispatcher still runs through the test harness"
expect_out_has "budget: applied: tasks 256, memory 1045 MiB, rung " "…inside the budget the library derived, the marker unchanged"
[ "$(starts)" = 2 ] && pass "…and its file ran exactly twice" || fail "the dispatcher-less stub ran $(starts) time(s) — expected 2"
# And the library is the one file it cannot run without: a stub root whose
# scripts/ lacks scripts/budget.lib.sh is refused out loud, naming the file,
# exit 2 — the dispatcher's own answer — never a shell's bare `.` error.
NOLIB="$SCRATCH/kit-nolib"
mkdir -p "$NOLIB/tests" "$NOLIB/scripts"
for f in "$KIT"/scripts/*; do [ "${f##*/}" = budget.lib.sh ] || ln -s "$f" "$NOLIB/scripts/${f##*/}"; done
cp "$GREEN" "$NOLIB/tests/green.sh"
stub sh "$NOLIB/tests/green.sh"
expect_status 2 "a suite whose kit root carries no Budget library is refused, exit 2"
expect_err_has "tests/lib.sh: cannot find budget.lib.sh in $NOLIB/scripts"
expect_out_lacks "budget:" "…and the suite body never ran"
# A suite's own status passes through the test harness untouched.
stub STUB_EXIT=5 sh "$GREEN"
expect_status 5 "a suite's own exit status passes through"
# …and an AGENTS_CONFIG the operator exported reaches it as exported, never
# replaced by the kit's.
stub AGENTS_CONFIG=/operator/own.sh sh "$GREEN"
expect_out_has "agents config: /operator/own.sh" "an AGENTS_CONFIG the operator exported reaches the suite as it was"
# The trace's identity and policy are the exception: a session's hooks export
# them, and a suite must start from none whatever the calling shell said —
# in the run inside the budget too, not only in the bare one (#303).
stub TRACE_SESSION=s TRACE_RUN=r TRACE_PARENT=p TRACE_DIR=/nowhere TRACE_CONFIG=/nowhere.sh TRACE_QUIET=1 sh "$GREEN"
expect_out_has "trace: <end>" "the trace variables a calling shell exported do not reach the suite inside the budget"
[ "$(starts)" = 2 ] && pass "…and that was the re-executed run, not a bare one" || fail "the scrubbed stub ran $(starts) time(s) — expected 2"

# The off switch: the suite runs bare, once, and the test harness says so.
stub AGENT_SUITE_BUDGET=off STUB_EXIT=3 sh "$GREEN"
expect_status 3 "AGENT_SUITE_BUDGET=off runs the suite bare — its own status, as before"
expect_out_has "budget: off" "…with no marker set"
expect_err_has "AGENT_SUITE_BUDGET=off"
[ "$(starts)" = 1 ] && pass "…and the file ran once — nothing was re-executed" || fail "the file ran $(starts) time(s) with the budget off"

# A value that is neither is refused before the suite runs: a typo must not
# read as "inside".
stub AGENT_SUITE_BUDGET=on sh "$GREEN"
expect_status 2 "an unknown AGENT_SUITE_BUDGET value is refused, exit 2"
expect_err_has "AGENT_SUITE_BUDGET"
expect_out_lacks "budget:" "…and the suite body never ran"

# Inside a dispatched worker the suite is already inside that worker's
# budget (ADR-0006 clause 7): the test harness opens none of its own, says so,
# and the suite runs once.
stub AGENT_DISPATCH_BUDGET_TASKS=777 AGENT_DISPATCH_BUDGET_MEMORY_MIB=888 sh "$GREEN"
expect_status 0 "inside a dispatched worker's budget the suite runs"
expect_out_has "budget: <unset>" "…bare — no scope of its own"
expect_err_has "dispatched worker"
[ "$(starts)" = 1 ] && pass "…and once" || fail "the file ran $(starts) time(s) inside a worker's budget"

# The second recursion bound, for a run that lost the marker anyway (an
# `env -i`, a wrapper that scrubs its environment): on the scope rung the
# inner run's own cgroup is the suite-<name>-<pid>.scope the test harness
# opened, and a test harness that finds itself there without the marker
# refuses to derive — exit 2, before a second sibling scope opens — rather
# than opening one per re-execution until the host refuses to fork. The
# fake host's own cgroup becomes a suite scope for this leg; the stub runs once.
printf '0::/user.slice/user-1000.slice/user@1000.service/app.slice/suite-green-4242.scope\n' >"$HOST/proc/self/cgroup"
stub sh "$GREEN"
expect_status 2 "a run that lost its marker inside a suite scope is refused, exit 2 — the second recursion bound"
expect_err_has "suite-green-4242.scope"
expect_err_has "AGENT_SUITE_BUDGET"
expect_out_lacks "budget:" "…and the suite body never ran"
[ "$(starts)" = 1 ] && pass "…and the file ran once — no sibling scope was opened" || fail "the file ran $(starts) time(s) from inside a suite scope without its marker"
printf '0::/user.slice/user-1000.slice/session-1.scope\n' >"$HOST/proc/self/cgroup"

# A suite started inside a cgroup that already bounds it — an operator's own
# `systemd-run --user --scope -p TasksMax=100 -p MemoryMax=64M`, the
# containment ADR-0006 clause 5 describes for the time before #209 — must
# not escape it: a scope opened from there is a SIBLING under the user
# manager, with the derived ceilings (larger, usually) and not the
# operator's. When the tightest pids.max on the path is the own cgroup's,
# or the derived ceilings exceed the own cgroup's pids.max / memory.max, the
# suite runs in place under that cgroup and says so — never "this host is
# small". Three shapes, then the one that is not this: a container's root.
OWN="$HOST/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/run-u99.scope"
mkdir -p "$OWN"
printf '0::/user.slice/user-1000.slice/user@1000.service/app.slice/run-u99.scope\n' >"$HOST/proc/self/cgroup"
echo 100 >"$OWN/pids.max"
echo 67108864 >"$OWN/memory.max"
stub sh "$GREEN"
expect_status 0 "inside an operator's scope whose pids.max is the tightest on the path, the suite runs"
expect_out_has "budget: applied: tasks 100, memory 64 MiB, rung inherited" "…in place, the marker naming that cgroup's ceilings"
expect_err_has "already inside a bounded cgroup (run-u99.scope"
expect_err_lacks "this host is small"
expect_out_has "forks: yes" "…and it can fork"
[ "$(starts)" = 2 ] && pass "…and the file ran twice — once bare, once in place with the marker" || fail "the file ran $(starts) time(s) inside an operator's scope"
# The floor above the operator's cap: the slice is the tightest at 100, so
# the derived ceiling is the floor, 256 — above the own cgroup's 200.
echo 200 >"$OWN/pids.max"
rm -f "$OWN/memory.max"
echo 100 >"$SLICE/pids.max"
stub sh "$GREEN"
expect_out_has "budget: applied: tasks 200, memory max, rung inherited" "a derived task ceiling above the own cgroup's pids.max runs in place too, under the cgroup's"
expect_err_has "already inside a bounded cgroup (run-u99.scope"
echo 400 >"$SLICE/pids.max"
# Memory alone: no task ceiling on the own cgroup, and a memory.max the
# derived 1045 MiB would exceed.
echo max >"$OWN/pids.max"
echo 67108864 >"$OWN/memory.max"
stub sh "$GREEN"
expect_out_has "budget: applied: tasks max, memory 64 MiB, rung inherited" "a derived memory ceiling above the own cgroup's memory.max runs in place, under the cgroup's"
expect_err_has "already inside a bounded cgroup (run-u99.scope"
rm -rf "$HOST/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service"
# A container's root is every scope's ancestor — a scope opened there is a
# child, bounded by the root's pids.max on top of its own — so the tightest
# ceiling being the own cgroup's is NOT the operator's-scope case there.
printf '0::/\n' >"$HOST/proc/self/cgroup"
echo 2048 >"$HOST/sys/fs/cgroup/pids.max"
echo 'cpu memory pids' >"$HOST/sys/fs/cgroup/cgroup.controllers"
stub sh "$GREEN"
expect_out_has "budget: applied: tasks 512, memory 1045 MiB, rung " "at a container's root the suite takes the derived budget — 25% of the root's 2048"
expect_out_lacks "rung inherited" "…in a scope of its own, which is the root's child"
expect_err_lacks "already inside"
rm -f "$HOST/sys/fs/cgroup/pids.max" "$HOST/sys/fs/cgroup/cgroup.controllers"
printf '0::/user.slice/user-1000.slice/session-1.scope\n' >"$HOST/proc/self/cgroup"

# Every suite in tests/ sources the test harness, so none has to remember any of
# this — including the three that keep their own scratch and trap.
for suite in "$KIT"/tests/*.sh; do
	rel="tests/${suite##*/}"
	[ "$rel" = tests/lib.sh ] && continue
	grep -q '^\. ".*/lib\.sh"$' "$suite" && pass "$rel sources tests/lib.sh" ||
		fail "$rel does not source tests/lib.sh — it runs outside the budget"
done

# ---------------------------------------------------------------------------
banner "3. A runaway suite stops at its ceiling and comes back as a FAILURE"
# ---------------------------------------------------------------------------
# The incident, as a red suite. On the scope rung the test harness reads the
# scope's counters after the suite exits and names the ceiling; these legs
# need that rung, which the green stub's marker reported above, and say they
# were skipped where it is absent. The rlimit legs after them run everywhere.
# forker — a suite whose loop forks 400 sleeps at once; bounded in time (two
# seconds) so where enforcement does not bite it ends on its own.
FORKER="$STUBROOT/tests/forker.sh"
cat >"$FORKER" <<EOF
#!/bin/sh
. "$KIT/tests/lib.sh"
echo "forker begins"
i=0
while [ \$i -lt 400 ]; do
	sleep 2 &
	i=\$((i + 1))
done
echo "forker finished its loop"
exit 0
EOF
# greedy — a suite that allocates past the memory floor: 29 doublings is a
# 512 MiB string whose last step holds 768 MiB, against a 512 MiB ceiling.
# Where enforcement does not bite it finishes and SAYS so, and that line is
# what the leg fails on.
GREEDY="$STUBROOT/tests/greedy.sh"
cat >"$GREEDY" <<EOF
#!/bin/sh
. "$KIT/tests/lib.sh"
echo "greedy begins"
awk 'BEGIN { s = "x"; for (i = 0; i < 29; i++) s = s s; print "greedy allocated it all" }'
echo "greedy went on after the allocation"
exit 0
EOF
if [ "$RUNG" = scope ]; then
	stub sh "$FORKER"
	expect_status 71 "a fork loop stops at the task ceiling and the suite exits 71"
	expect_out_has "FAIL" "…the test harness reports it as a FAILURE of that suite"
	expect_out_has "hit its TASK ceiling (256 tasks)" "…naming the ceiling it hit"
	expect_out_has "forker begins" "…after the suite's own output"
	if sh -c 'exit 0'; then
		pass "a command in the calling shell right after the runaway still forks"
	else
		fail "the calling shell could not fork after the runaway — the budget did not contain it"
	fi
	# 50% of 800 MiB is below the memory floor; the floor, 512 MiB, stands.
	printf 'MemTotal:        3902724 kB\nMemFree:          200000 kB\nMemAvailable:     819200 kB\n' >"$HOST/proc/meminfo"
	stub sh "$GREEDY"
	expect_status 71 "a greedy allocation stops at the memory ceiling and the suite exits 71"
	expect_out_has "hit its MEMORY ceiling (512 MiB)" "…naming the ceiling it hit"
	expect_out_lacks "greedy allocated it all" "…the greedy process was OOM-killed before it finished"
	printf 'MemTotal:        3902724 kB\nMemFree:          200000 kB\nMemAvailable:    2141820 kB\n' >"$HOST/proc/meminfo"
else
	printf '  --    the scope rung is not offered here (rung: %s) — the scope legs are skipped; CI runs them where it can\n' "$RUNG"
fi

# ---------------------------------------------------------------------------
banner "4. The rlimit rung — the weaker promise, applied in the suite's own shell"
# ---------------------------------------------------------------------------
# A systemctl that fails stands in for a host with no user service manager
# (the dispatch suite's NOSD), so the ladder falls to rlimits everywhere this
# runs — including CI, whose sh is dash and spells the process limit -p. The
# fake host for these legs sets no cgroup ceiling, so the base is the per-user
# process limit: RLIMIT_NPROC counts every task of the uid, so the ceiling is
# the uid's task count plus a margin (at least the floor), and the loop's own
# forks are what cross it.
NOSD="$SCRATCH/sd-no"; t_no_user_manager "$NOSD"
HOST_RL="$SCRATCH/host-rl"
mkdir -p "$HOST_RL/proc/self" "$HOST_RL/sys/fs/cgroup"
printf '0::/\n' >"$HOST_RL/proc/self/cgroup"
UID_TASKS=$(t_uid_tasks)
RL_TASKS=$((UID_TASKS + 80))
[ "$RL_TASKS" -lt 300 ] && RL_TASKS=300
printf 'Max processes             %s                   %s                   processes\n' $((RL_TASKS * 4)) $((RL_TASKS * 4)) >"$HOST_RL/proc/self/limits"
printf 'MemTotal:        3902724 kB\nMemFree:          200000 kB\nMemAvailable:    2141820 kB\n' >"$HOST_RL/proc/meminfo"
# Both controllers delegated, so that with a manager that answers this host
# still offers the scope rung — section 5 wants a scope that then refuses.
echo 'cpu memory pids' >"$HOST_RL/sys/fs/cgroup/cgroup.controllers"
rlstub() { stub_on "$HOST_RL" PATH="$NOSD:$PATH" "$@"; }
rlstub sh "$GREEN"
expect_status 0 "a green suite runs under the rlimit rung"
expect_out_has "rung rlimit" "…and its marker names the rung"
expect_out_has "nproc: $RL_TASKS" "…the task ceiling is the suite shell's process limit (25% of the fake per-user limit)"
expect_out_has "data: $((1045 * 1024))" "…and the memory ceiling its data limit, in KiB"
expect_out_has "forks: yes" "…and it can still fork"
expect_err_has "weaker"
expect_err_has "never a FAIL line naming the ceiling"
[ "$(starts)" = 2 ] && pass "…and the file ran twice — once bare, once inside" || fail "the file ran $(starts) time(s) under the rlimit rung"
# A fork loop under that ceiling is refused inside the suite's own shell. A
# hit is not observable on this rung (ADR-0006 clause 6): the status is the
# shell's own verdict on its refused forks — never 71 — the shell's own
# error is what says so, the note above has said that is how it shows, and
# the calling shell still forks.
rlstub sh "$FORKER"
case "$T_STATUS" in
71 | 124) fail "a fork loop on the rlimit rung should pass the suite's own status through, got $T_STATUS"; printf "%s\n" "$T_OUT" | sed "s/^/        > /"; printf "%s\n" "$T_ERR" | sed "s/^/        | /" ;;
0) fail "a fork loop on the rlimit rung ran whole — the limit did not land in the suite's shell"; printf "%s\n" "$T_OUT" | sed "s/^/        > /"; printf "%s\n" "$T_ERR" | sed "s/^/        | /" ;;
*) pass "a fork loop on the rlimit rung passes the suite's own status through ($T_STATUS) — not 71" ;;
esac
expect_err_has "fork"
expect_out_has "forker begins" "…the suite ran, its forks refused inside its own shell"
if sh -c 'exit 0'; then
	pass "a command in the calling shell right after the runaway still forks"
else
	fail "the calling shell could not fork after the rlimit-rung runaway"
fi

# ---------------------------------------------------------------------------
banner "5. The scope that will not open, and the verdict that cannot be read"
# ---------------------------------------------------------------------------
# Both need a host whose probe offers the scope rung; where it does not, the
# legs say so. A systemd-run that refuses falls to rlimits before the run,
# loudly, with its own message; one that exits 0 without running the wrapper
# leaves no verdict, which is said and the run's status passed through —
# never a silent green. The rlimit-sized host, because the refusal lands the
# suite on rlimits and a floor-sized ceiling would refuse its every fork on a
# uid that already runs that many tasks — which is the rung's weakness, not
# the leg's point.
if [ "$RUNG" = scope ]; then
	SDREFUSE="$SCRATCH/sd-refuse"; mkdir -p "$SDREFUSE"
	printf '#!/bin/sh\necho "Failed to start transient scope unit: Access denied" >&2\nexit 1\n' >"$SDREFUSE/systemd-run"; chmod +x "$SDREFUSE/systemd-run"
	stub_on "$HOST_RL" PATH="$SDREFUSE:$PATH" sh "$GREEN"
	expect_status 0 "a scope that refuses to open still runs the suite"
	expect_out_has "rung rlimit" "…under the rlimit rung"
	expect_err_has "Access denied"
	expect_err_has "cannot open"
	SDFAKE="$SCRATCH/sd-fake"; mkdir -p "$SDFAKE"
	printf '#!/bin/sh\nexit 0\n' >"$SDFAKE/systemd-run"; chmod +x "$SDFAKE/systemd-run"
	stub_on "$HOST_RL" PATH="$SDFAKE:$PATH" sh "$GREEN"
	expect_status 0 "a scope whose wrapper never wrote a verdict passes the run's status through"
	expect_err_has "started marker is missing" "…the library's own reason: the wrapper never started"
	expect_err_has "The budget verdict cannot be read; the run's own status (0) passes through." "…and the run's status passed through, said as the dispatcher says it"
else
	printf '  --    the scope rung is not offered here (rung: %s) — the scope legs are skipped\n' "$RUNG"
fi

t_done "suite budget"
