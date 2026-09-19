#!/bin/sh
# tests/suite-budget.test.sh — every suite runs inside the worker budget.
#
# ADR-0006 gives a dispatched worker a budget: a task ceiling and a memory
# ceiling on its whole process tree, derived from the host. #209 puts every
# suite under the same one, applied by tests/lib.sh the moment a suite sources
# it — so the incident that started the wave (a runaway suite filling the
# login session's task ceiling, #205) fails as a red suite instead of a frozen
# host. This suite is the harness's oracle for that, through two seams:
#
#   1. THE DISPATCHER'S SOURCING SEAM. tests/lib.sh takes the derivation from
#      scripts/agent-dispatch.sh by sourcing it, so a suite and a worker cannot
#      disagree about a number. Sourced, the dispatcher defines and runs
#      nothing; _budget_derive then answers what --dry-run shows.
#   2. THE HARNESS SEAM. A STUB SUITE — a script that sources tests/lib.sh the
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
DISPATCH="$KIT/scripts/agent-dispatch.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

# ---------------------------------------------------------------------------
banner "1. Sourcing the dispatcher defines the derivation and runs nothing"
# ---------------------------------------------------------------------------
# The seam tests/lib.sh uses. Sourced with _dispatch_here set (the same shape
# as scripts/agents.lib.sh's _agents_here), the dispatcher must define its
# _budget_* functions and return before it parses arguments, sweeps scratch or
# resolves a tier — with the suite's own arguments untouched, and nothing on
# either stream. A dispatcher that ran when sourced would print its usage and
# exit 2 here.
t_run_split sh -c '_dispatch_here="$1"; . "$2"; command -v _budget_derive >/dev/null && echo "defined: _budget_derive"; command -v _budget_scope_props >/dev/null && echo "defined: _budget_scope_props"; command -v _budget_counters_text >/dev/null && echo "defined: _budget_counters_text"; shift 2; echo "args: $*"' probe "$KIT/scripts" "$DISPATCH" a b
s_assert_status 0 "sourcing the dispatcher with _dispatch_here set exits 0 — it ran no dispatch"
s_assert_out_has "defined: _budget_derive" "…and defines _budget_derive"
s_assert_out_has "defined: _budget_scope_props" "…and _budget_scope_props"
s_assert_out_has "defined: _budget_counters_text" "…and _budget_counters_text"
s_assert_out_has "args: a b" "…and leaves the sourcing shell's arguments alone"
s_assert_out_lacks "usage:" "…without printing the usage"
s_assert_err_lacks "dispatch:"

# Sourced WITHOUT _dispatch_here there is nowhere to find agents.lib.sh, and
# the dispatcher says so rather than guessing from the sourcing script's $0.
t_run_split sh -c '. "$1"; echo "still here"' probe "$DISPATCH"
s_assert_status 2 "sourcing without _dispatch_here is refused, exit 2"
s_assert_err_has "_dispatch_here"
s_assert_out_lacks "still here" "…and the sourcing shell does not go on"

# _budget_derive answers what the dry run shows, from the same fake host the
# dispatch suite uses: 25% of the slice's 10008 tasks, 50% of 2091 MiB.
HOST="$SCRATCH/host"
SLICE="$HOST/sys/fs/cgroup/user.slice/user-1000.slice"
mkdir -p "$HOST/proc/self" "$SLICE/session-1.scope"
printf '0::/user.slice/user-1000.slice/session-1.scope\n' >"$HOST/proc/self/cgroup"
echo max >"$HOST/sys/fs/cgroup/user.slice/pids.max"
echo 10008 >"$SLICE/pids.max"
echo max >"$SLICE/session-1.scope/pids.max"
echo 'cpu memory pids' >"$SLICE/session-1.scope/cgroup.controllers"
printf 'MemTotal:        3902724 kB\nMemFree:          200000 kB\nMemAvailable:    2141820 kB\n' >"$HOST/proc/meminfo"
# derive — source the seam against the fake host and print what it derived.
derive() { t_run_split env AGENT_DISPATCH_HOST_ROOT="$HOST" "$@" sh -c '_dispatch_here="$1"; . "$2"; _budget_derive; _budget_scope_props "$BUDGET_RUNG"; printf "mode=%s tasks=%s memory=%s rung=%s\nprops=%s\n" "$BUDGET_MODE" "$BUDGET_TASKS" "$BUDGET_MEMORY" "$BUDGET_RUNG" "$SCOPE_PROPS"' probe "$KIT/scripts" "$DISPATCH"; }
derive
s_assert_status 0 "_budget_derive derives against the fake host"
s_assert_out_has "mode=derived tasks=2502 memory=1045" "…the same numbers the dispatch suite's dry run shows: 25% of 10008, 50% of 2091 MiB"
s_assert_out_has "TasksMax=2502" "…and the scope properties carry the task ceiling"
s_assert_out_has "OOMPolicy=continue" "…and the OOM policy the ADR amendment records"
# The policy file is read through the same reader: a ceiling in it clamps.
CFG_SMALL="$SCRATCH/small.config.sh"
printf "AGENT_BUDGET_TASKS_CEILING='300'\nAGENT_BUDGET_MEMORY_CEILING_MIB='600'\n" >"$CFG_SMALL"
derive AGENTS_CONFIG="$CFG_SMALL"
s_assert_out_has "tasks=300 memory=600" "the policy file's clamps apply through the seam"
# The inherited case is the dispatcher's own: an outer budget in the
# environment is taken as given and derives nothing.
derive AGENT_DISPATCH_BUDGET_TASKS=777 AGENT_DISPATCH_BUDGET_MEMORY_MIB=888
s_assert_out_has "mode=inherited tasks=777 memory=888" "an outer dispatch's budget is inherited through the seam"
# And a policy value that cannot be a budget is refused where the sourcing
# shell can hear it: exit 2, never a default.
printf "AGENT_BUDGET_TASKS_PERCENT='lots'\n" >"$CFG_SMALL"
derive AGENTS_CONFIG="$CFG_SMALL"
s_assert_status 2 "a policy value that is not a whole number is refused through the seam"
s_assert_err_has "AGENT_BUDGET_TASKS_PERCENT"

t_done "suite budget"
