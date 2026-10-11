#!/bin/sh
# tests/budget-lib.test.sh — the worker Budget, through its four functions.
#
# scripts/budget.lib.sh is the kit's ADR-0006 mechanism, moved out of the
# dispatcher (#747): budget_derive prints a record, budget_run runs a command
# under it, budget_verdict reads what the run left, budget_inherited_bounds
# says whether the enclosing cgroup already bounds the caller. Every leg here
# goes through those four on a FAKE host (AGENT_DISPATCH_HOST_ROOT) with stub
# systemd-run / systemctl binaries on PATH, so the numbers are this suite's
# and no leg opens a real scope. No leg names a private function.
#
# Usage: sh tests/budget-lib.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
LIBDIR="$KIT/scripts"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

# Every leg runs the library in a fresh sh, with no policy and no outer
# dispatch inherited from whoever ran this suite.
unset AGENT_DISPATCH_BUDGET_TASKS AGENT_DISPATCH_BUDGET_MEMORY_MIB BUDGET_WHO
CFG="$SCRATCH/empty.config.sh"
: >"$CFG"
AGENTS_CONFIG=$CFG
export AGENTS_CONFIG

# lib <function> [args…] — source the library the way a caller does and call
# one function, with stdout and stderr kept apart (S_OUT, S_ERR, S_STATUS).
lib() {
	t_run_split sh -c '_budget_here="$1"; . "$1/budget.lib.sh"; shift; "$@"' lib "$LIBDIR" "$@"
}
# field <key> — one line of the record in S_OUT.
field() { printf '%s\n' "$S_OUT" | sed -n "s/^$1=//p"; }
# s_field <key> <expected> <label>
s_field() {
	_sf=$(field "$1")
	[ "$_sf" = "$2" ] && pass "$3" || { fail "$3 — $1 is '$_sf', expected '$2'"; _s_dump; }
}

HOST="$SCRATCH/host"
t_fake_host "$HOST" 10008 2141820
export AGENT_DISPATCH_HOST_ROOT="$HOST"
OWN="$SLICE/session-1.scope"
NOSD="$SCRATCH/sd-no"
t_no_user_manager "$NOSD"
# A user manager that answers, and a systemd-run that LOGS its arguments
# and runs what follows --quiet, writing the marker and the verdict the way
# the scope's wrapper would — FAKE_VERDICT, when set, is what the counters
# read. Its last three arguments are the marker, the verdict and the command.
SDYES="$SCRATCH/sd-yes"
mkdir -p "$SDYES"
printf '#!/bin/sh\nexit 0\n' >"$SDYES/systemctl"
cat >"$SDYES/systemd-run" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$SCRATCH/sd-args"
for _a; do _started=\$_verdict; _verdict=\$_cmd; _cmd=\$_a; done
[ "\$_cmd" = true ] && exit 0
: >"\$_started"
eval "\$_cmd"
_st=\$?
[ -n "\${FAKE_VERDICT+x}" ] && printf '%s\n' "\$FAKE_VERDICT" >"\$_verdict"
exit "\$_st"
EOF
chmod +x "$SDYES/systemctl" "$SDYES/systemd-run"
SDREFUSE="$SCRATCH/sd-refuse"
mkdir -p "$SDREFUSE"
cp "$SDYES/systemctl" "$SDREFUSE/systemctl"
printf '#!/bin/sh\necho "refused by fixture" >&2\nexit 1\n' >"$SDREFUSE/systemd-run"
chmod +x "$SDREFUSE/systemd-run"
PATH_NOSD="$NOSD:$PATH"

# ---------------------------------------------------------------------------
banner "1. budget_derive prints the record and sets nothing"
# ---------------------------------------------------------------------------
PATH=$PATH_NOSD lib budget_derive
s_assert_status 0 "budget_derive derives against the fake host"
s_field mode derived "mode is derived"
s_field tasks 2502 "tasks is 25% of the slice's pids.max, 10008"
s_field memory_mib 1045 "memory is 50% of 2091 MiB MemAvailable"
s_field tasks_from "25% of 10008, the pids.max of cgroup user-1000.slice" "tasks_from names the cgroup it read"
s_field memory_from "50% of 2091 MiB MemAvailable" "memory_from names the fact it read"
s_field rung rlimit "with no user manager the rung is rlimit"
s_field tasks_floor 256 "the policy's task floor is in the record"
s_field memory_ceiling_mib 8192 "…and its memory ceiling"
case "$(field nproc_flag)" in -u | -p) pass "nproc_flag is the ulimit option this sh spells" ;; *) fail "nproc_flag is '$(field nproc_flag)'" ;; esac
[ -z "$S_ERR" ] && pass "…and says nothing on stderr" || { fail "budget_derive spoke on stderr"; _s_dump; }

# The floor raises and says so; the ceiling holds.
echo 400 >"$SLICE/pids.max"
PATH=$PATH_NOSD lib budget_derive
s_field tasks 256 "25% of 400 is 100, below the floor — the floor stands"
s_field tasks_from "25% of 400, the pids.max of cgroup user-1000.slice: 100 is below the floor 256 — raised to the floor" "…and tasks_from says why"
echo 100000 >"$SLICE/pids.max"
PATH=$PATH_NOSD lib budget_derive
s_field tasks 4096 "25% of 100000 is above the ceiling — the ceiling stands"
echo 10008 >"$SLICE/pids.max"

# The overrides, the off switch and the inherited pair.
PATH=$PATH_NOSD lib budget_derive --tasks 100 --memory 300
s_field tasks 100 "--tasks replaces the derived task ceiling"
s_field tasks_from "--budget-tasks; below the floor 256, honoured as given" "…named as the dispatcher's override, below the floor"
s_field memory_mib 300 "--memory replaces the derived memory ceiling"
PATH=$PATH_NOSD lib budget_derive --off
s_field mode disabled "--off is the disabled mode"
s_field rung none "…with no rung"
t_run_split env AGENT_DISPATCH_BUDGET_TASKS=777 AGENT_DISPATCH_BUDGET_MEMORY_MIB=888 \
	sh -c '_budget_here="$1"; . "$1/budget.lib.sh"; budget_derive --off' lib "$LIBDIR"
s_field mode inherited "an outer dispatch's pair is inherited, and --off cannot leave it"
s_field tasks 777 "…its task ceiling"
s_field memory_mib 888 "…and its memory ceiling"

# The rung is probed: a manager that answers with both controllers delegated
# is the scope rung; pids alone is scope-tasks.
PATH="$SDYES:$PATH" lib budget_derive
s_field rung scope "a user manager with pids and memory delegated is the scope rung"
echo 'cpu pids' >"$OWN/cgroup.controllers"
PATH="$SDYES:$PATH" lib budget_derive
s_field rung scope-tasks "pids without memory is the scope-tasks rung"
echo 'cpu memory pids' >"$OWN/cgroup.controllers"

# Nothing leaks: the variables the sourcing shell holds are the same before
# and after the call.
t_run_split sh -c '_budget_here="$1"; . "$1/budget.lib.sh"
names() { set | sed -n "s/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p" | sort; }
before="" after=""; before=$(names); budget_derive >/dev/null; after=$(names)
[ "$before" = "$after" ] && echo same || { echo differ; printf "%s\n" "$before" >"$2/747-before"; printf "%s\n" "$after" >"$2/747-after"; diff "$2/747-before" "$2/747-after"; }' lib "$LIBDIR" "$SCRATCH"
s_assert_out_is same "budget_derive sets no variable in the shell that called it"

# ---------------------------------------------------------------------------
banner "2. A policy that cannot be a budget is refused, and the caller lives"
# ---------------------------------------------------------------------------
bad() { printf '%s\n' "$1" >"$SCRATCH/bad.config.sh"; AGENTS_CONFIG="$SCRATCH/bad.config.sh" PATH=$PATH_NOSD lib budget_derive; }
bad 'AGENT_BUDGET_TASKS_PERCENT=100'
s_assert_status 2 "a percentage of 100 is refused, exit 2"
s_assert_err_has "below 100"
bad 'AGENT_BUDGET_TASKS_PERCENT=99'
s_assert_status 0 "…and 99 is the last one accepted"
bad 'AGENT_BUDGET_MEMORY_PERCENT=0'
s_assert_status 2 "a percentage of 0 is refused"
s_assert_err_has "AGENT_BUDGET_MEMORY_PERCENT"
bad 'AGENT_BUDGET_TASKS_PERCENT=025'
s_assert_status 2 "a leading zero is refused — arithmetic would read it as octal"
bad "AGENT_BUDGET_TASKS_FLOOR='lots'"
s_assert_status 2 "a value that is not a whole number is refused, not defaulted"
bad 'AGENT_BUDGET_TASKS_FLOOR=5000'
s_assert_status 2 "a floor above its ceiling is refused"
s_assert_err_has "AGENT_BUDGET_TASKS_CEILING"
[ -z "$S_OUT" ] && pass "…and a refused derivation prints no record" || fail "a refused derivation printed '$S_OUT'"
# The refusal returns; it never exits the shell that called it.
printf 'AGENT_BUDGET_TASKS_PERCENT=100\n' >"$SCRATCH/bad.config.sh"
t_run_split env AGENTS_CONFIG="$SCRATCH/bad.config.sh" PATH="$PATH_NOSD" \
	sh -c '_budget_here="$1"; . "$1/budget.lib.sh"; budget_derive >/dev/null; echo "still here, status $?"' lib "$LIBDIR"
s_assert_out_is "still here, status 2" "a refused policy returns 2 to a caller that keeps running"
s_assert_err_has "x budget: AGENT_BUDGET_TASKS_PERCENT"
t_run_split env AGENTS_CONFIG="$SCRATCH/bad.config.sh" BUDGET_WHO=dispatch PATH="$PATH_NOSD" \
	sh -c '_budget_here="$1"; . "$1/budget.lib.sh"; budget_derive' lib "$LIBDIR"
s_assert_err_has "x dispatch: AGENT_BUDGET_TASKS_PERCENT"
t_run_split env AGENT_DISPATCH_BUDGET_TASKS=777 PATH="$PATH_NOSD" \
	sh -c '_budget_here="$1"; . "$1/budget.lib.sh"; budget_derive' lib "$LIBDIR"
s_assert_status 2 "an inherited task ceiling with no memory beside it is refused"
s_assert_err_has "AGENT_DISPATCH_BUDGET_MEMORY_MIB"
PATH=$PATH_NOSD lib budget_derive --tasks 010
s_assert_status 2 "--tasks with a leading zero is refused the same way"

# ---------------------------------------------------------------------------
banner "3. budget_run runs the command under the record's rung"
# ---------------------------------------------------------------------------
REC="$SCRATCH/record"
V="$SCRATCH/verdict"
LIMITS='echo "NPROC=$(ulimit -u 2>/dev/null || ulimit -p 2>/dev/null) DATA=$(ulimit -d)"; exit 7'
# The rlimit rung: ulimit in the command's shell, the status passed back.
PATH=$PATH_NOSD lib budget_derive --tasks 5000 --memory 128
printf '%s\n' "$S_OUT" >"$REC"
PATH=$PATH_NOSD lib budget_run "$REC" "$V" -- sh -c "$LIMITS"
s_assert_status 7 "budget_run returns the command's own status"
s_assert_out_has "NPROC=5000" "…the task ceiling applied as the process-count rlimit"
s_assert_out_has "DATA=131072" "…and the memory ceiling as ulimit -d (128 MiB in KiB)"
lib budget_verdict "$V"
s_assert_status 0 "on the rlimit rung the verdict reads cleanly"
s_assert_out_is "" "…and names no ceiling — a hit there is not observable"

# The scope rung: the properties reach systemd-run, the unit is named, and
# the command runs inside the wrapper.
PATH="$SDYES:$PATH" lib budget_derive --tasks 300 --memory 600
printf '%s\n' "$S_OUT" >"$REC"
rm -f "$SCRATCH/sd-args"
t_run_split env PATH="$SDYES:$PATH" FAKE_VERDICT='0 0 0' \
	sh -c '_budget_here="$1"; . "$1/budget.lib.sh"; shift; budget_run "$@"' lib "$LIBDIR" "$REC" "$V" --unit budget-lib-test -- sh -c 'echo "ran: $1"; exit 3' x "it's quoted"
s_assert_status 3 "on the scope rung budget_run returns the command's status"
s_assert_out_has "ran: it's quoted" "…the command and its arguments arrive intact"
case "$(cat "$SCRATCH/sd-args")" in
*"-p TasksMax=300 -p MemoryMax=600M -p MemorySwapMax=0 -p OOMPolicy=continue --quiet true"*) pass "…a pre-flight opens an empty scope with the real properties first" ;;
*) fail "no pre-flight with the scope's properties: $(cat "$SCRATCH/sd-args")" ;;
esac
case "$(cat "$SCRATCH/sd-args")" in
*"--unit=budget-lib-test -p TasksMax=300 -p MemoryMax=600M"*) pass "…and the scope is named as asked" ;;
*) fail "the scope was not named budget-lib-test: $(cat "$SCRATCH/sd-args")" ;;
esac
lib budget_verdict "$V"
s_assert_out_is "" "counters at zero are no ceiling hit"

# A pre-flight refusal falls to rlimits, out loud, and the command runs once.
t_run_split env PATH="$SDREFUSE:$PATH" BUDGET_WHO=dispatch \
	sh -c '_budget_here="$1"; . "$1/budget.lib.sh"; shift; budget_run "$@"' lib "$LIBDIR" "$REC" "$V" -- sh -c "$LIMITS"
s_assert_status 7 "a scope refused at the pre-flight still runs the command"
s_assert_err_has "refused by fixture"
s_assert_err_has "!  dispatch: the transient scope cannot open"
s_assert_out_has "NPROC=300" "…under the rlimit rung's task ceiling"
[ "$(printf '%s\n' "$S_OUT" | grep -c '^NPROC=')" = 1 ] && pass "…exactly once" || fail "the command ran $(printf '%s\n' "$S_OUT" | grep -c '^NPROC=') times"

# An inherited or disabled record opens nothing: systemd-run is never called.
printf 'mode=inherited\ntasks=500\nmemory_mib=500\nrung=none\n' >"$SCRATCH/inherited"
rm -f "$SCRATCH/sd-args"
PATH="$SDYES:$PATH" lib budget_run "$SCRATCH/inherited" "$V" -- sh -c "$LIMITS"
s_assert_status 7 "an inherited record runs the command bare"
[ -f "$SCRATCH/sd-args" ] && fail "an inherited record opened a scope" || pass "…and opens no scope"
s_assert_out_lacks "NPROC=500" "…and applies no rlimit of its own"

# ---------------------------------------------------------------------------
banner "4. budget_verdict reads the run's counters"
# ---------------------------------------------------------------------------
# verdict <rung> <file content|-absent> [started] — a verdict file by hand,
# as budget_run's wrapper leaves it.
verdict() {
	rm -f "$V" "$V.started" "$V.unit"
	printf '%s\n' "$1" >"$V.rung"
	[ "$2" = -absent ] || printf '%s\n' "$2" >"$V"
	[ "${3:-started}" = started ] && : >"$V.started"
	PATH=$PATH_NOSD lib budget_verdict "$V"
}
verdict scope '3 0 0'
s_assert_out_is tasks "pids.events max above 0 is the task ceiling"
verdict scope '0 5 0'
s_assert_out_is memory "memory.events oom_kill above 0 on the scope rung is the memory ceiling"
verdict scope-tasks '0 5 0'
s_assert_out_is "" "on scope-tasks an oom_kill is not this rung's flag"
verdict scope-tasks '3 0 0'
s_assert_out_is tasks "…while a task ceiling hit there still is"
verdict scope '0 0 0' none
s_assert_status 1 "a missing started marker is unreadable, status 1"
s_assert_err_has "started marker is missing"
verdict scope -absent
s_assert_status 1 "a missing verdict file is unreadable"
s_assert_err_has "verdict file is missing"
verdict scope 'garbage'
s_assert_status 1 "a malformed verdict is unreadable"
s_assert_err_has "malformed"
verdict scope '- - 0'
s_assert_status 1 "a counter marked unreadable is its own outcome, never a zero"
s_assert_err_has "could not be read"
verdict scope-tasks '0 - 0'
s_assert_status 0 "on scope-tasks an unreadable memory counter is not this rung's concern"
verdict none -absent
s_assert_status 0 "with no rung there is nothing to read, and nothing is wrong"
s_assert_out_is "" "…and nothing is printed"

# From outside the scope, while it lives. The stub manager names the unit's
# cgroup by a path that climbs out of /sys/fs/cgroup into this suite's
# scratch, so the counters read are a fixture's: a task ceiling already hit.
# Only a caller whose watchdog is about to signal asks for that read, with
# --timed-out, and the verdict it leaves carries the status a timeout has.
SDCG="$SCRATCH/sd-cg"
mkdir -p "$SDCG" "$SCRATCH/cg"
printf '#!/bin/sh\necho "/../../..%s"\n' "$SCRATCH/cg" >"$SDCG/systemctl"
chmod +x "$SDCG/systemctl"
printf 'max 3\n' >"$SCRATCH/cg/pids.events"
printf 'low 0\noom_kill 0\n' >"$SCRATCH/cg/memory.events"
# outside [--timed-out] — budget_verdict on a run whose wrapper wrote nothing.
outside() {
	rm -f "$V"
	echo budget-lib-test >"$V.unit"
	echo scope >"$V.rung"
	: >"$V.started"
	t_run_split env PATH="$SDCG:$PATH" sh -c '_budget_here="$1"; . "$1/budget.lib.sh"; shift; budget_verdict "$@"' lib "$LIBDIR" "$V" "$@"
}
if [ -d /sys/fs/cgroup ]; then
	outside --timed-out
	s_assert_status 0 "--timed-out reads a live scope's counters from outside"
	s_assert_out_is tasks "…and a ceiling already hit on them is the verdict"
	[ "$(cat "$V" 2>/dev/null)" = "3 0 124" ] && pass "…recorded with the status a timeout has, 124" || fail "the verdict written from outside is '$(cat "$V" 2>/dev/null)', expected '3 0 124'"
	outside
	s_assert_status 1 "without --timed-out a missing verdict file is unreadable"
	s_assert_err_has "verdict file is missing"
	[ -f "$V" ] && fail "a verdict was written from outside without --timed-out" || pass "…and nothing is read from outside the scope"
else
	skip "no /sys/fs/cgroup here — the outside read is not judged"
fi
PATH=$PATH_NOSD lib budget_verdict "$V" --sideways
s_assert_status 2 "an argument budget_verdict does not know is refused"

# ---------------------------------------------------------------------------
banner "5. budget_inherited_bounds names a cgroup that already bounds the caller"
# ---------------------------------------------------------------------------
PATH=$PATH_NOSD lib budget_inherited_bounds
s_assert_status 1 "the session scope with no ceiling of its own bounds nothing"
s_assert_out_is "" "…and nothing is printed"
echo 100 >"$OWN/pids.max"
PATH=$PATH_NOSD lib budget_inherited_bounds
s_assert_status 0 "a pids.max that is the tightest on the path bounds the caller"
s_field cgroup session-1.scope "…naming the cgroup"
s_field tasks 100 "…its task ceiling"
s_field memory_mib max "…and a memory ceiling it does not set as max"
echo 20000 >"$OWN/pids.max"
echo 1073741824 >"$OWN/memory.max"
printf 'mode=derived\ntasks=2502\nmemory_mib=2000\n' >"$SCRATCH/derived"
PATH=$PATH_NOSD lib budget_inherited_bounds "$SCRATCH/derived"
s_assert_status 0 "a memory.max below the record's memory ceiling bounds the caller"
s_field memory_mib 1024 "…in MiB"
PATH=$PATH_NOSD lib budget_inherited_bounds
s_assert_status 1 "…while without a record only the tightest-on-path test applies"
echo max >"$OWN/pids.max"
rm -f "$OWN/memory.max"
printf '0::/\n' >"$HOST/proc/self/cgroup"
PATH=$PATH_NOSD lib budget_inherited_bounds "$SCRATCH/derived"
s_assert_status 1 "the root cgroup never counts — it is every scope's ancestor"

t_done "budget-lib"
