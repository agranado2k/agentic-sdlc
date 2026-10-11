#!/bin/sh
# budget.lib.sh — THE worker Budget. One implementation, sourced by its callers.
#
# A task ceiling and a memory ceiling for a command's WHOLE process tree,
# derived from this host now and applied down the strongest rung it offers:
# a transient scope under the user service manager, else rlimits, else a loud
# no-op. The kit's ADR-0006 is the decision; this file is its mechanism, moved
# out of scripts/agent-dispatch.sh so a caller reaches it through four
# functions instead of the dispatcher's internals (#742, #747).
#
#   _budget_here=<this directory>          # on its own line, BEFORE sourcing
#   . scripts/budget.lib.sh
#
#   budget_derive [--tasks <n>] [--memory <MiB>] [--off] >record
#       prints the Budget as a key=value record, one per line: mode (derived,
#       inherited, disabled), tasks, memory_mib, tasks_from, memory_from,
#       rung (scope, scope-tasks, rlimit, none — none unless derived), and the
#       policy it was derived under: tasks_floor, tasks_ceiling,
#       memory_floor_mib, memory_ceiling_mib, and nproc_flag (the ulimit
#       option this sh sets the process count with, or empty).
#   budget_run <record-file> <verdict-file> [--unit <name>] -- <cmd…>
#       runs the command under the record's rung and returns ITS status. A
#       derived record opens the rung; an inherited or disabled one runs the
#       command bare. A scope that refuses at its pre-flight falls to the
#       rlimit rung, loudly, and the command runs once.
#   budget_verdict <verdict-file> [--timed-out]
#       prints `tasks` or `memory` — the ceiling the run hit — or nothing.
#       Returns 1 with the reason on stderr when the verdict cannot be read.
#       While the run's scope still lives and its wrapper has written
#       nothing, the scope's counters are recorded from outside first.
#       --timed-out is a watchdog's call, made before it signals a run that
#       outlived its time: that record carries 124, a timeout's status, as
#       the run's; without it the status is `-`, none seen.
#   budget_inherited_bounds [<record-file>]
#       prints the enclosing cgroup's limits — cgroup, tasks (<n> or max),
#       memory_mib (<n> or max) — when that cgroup already bounds the caller:
#       its pids.max is the tightest on the path, or (given a record) its
#       pids.max or memory.max sits below the record's ceilings. Returns 1,
#       printing nothing, when it does not.
#
# NO FUNCTION EXITS ITS CALLER, AND NONE SETS A VARIABLE ITS CALLER READS:
# each runs in a subshell of its own (the `( … )` body), so a policy value
# that cannot be a budget is `return 2` with the reason on stderr, and the
# names below stay private. A caller that wants a field reads the record.
#
# INPUTS, unchanged from the kit's ADR-0006: the AGENT_BUDGET_* policy in the tier
# policy file (scripts/agents.config.sh, read through scripts/agents.lib.sh
# beside this file; empty there is the defaults below), the outer dispatch's
# AGENT_DISPATCH_BUDGET_TASKS / AGENT_DISPATCH_BUDGET_MEMORY_MIB, and the
# host's /proc and /sys. AGENT_DISPATCH_HOST_ROOT is TEST-ONLY: prefixed to
# those host paths so a suite can hand the derivation a fake host.
# BUDGET_WHO names the caller in every line this file says (`x <who>:`,
# `!  <who>:`); empty is `budget`.
#
# THE VERDICT FILE is `<pids.events max> <memory.events oom_kill> <status>`,
# written from inside the scope after the command exits — `-` for a counter
# that could not be read, never 0 — or from outside it by budget_verdict, the
# status then 124 under --timed-out and `-` otherwise. Three files beside it carry the rest:
# <verdict-file>.started (written inside the scope before the command runs),
# .rung (the rung the command ran under) and .unit (the scope's name).
#
# Shared layer (see VERSION): copied verbatim into a consumer.

BUDGET_DEFAULT_TASKS_PERCENT=25
BUDGET_DEFAULT_TASKS_FLOOR=256
BUDGET_DEFAULT_TASKS_CEILING=4096
BUDGET_DEFAULT_MEMORY_PERCENT=50
BUDGET_DEFAULT_MEMORY_FLOOR_MIB=512
BUDGET_DEFAULT_MEMORY_CEILING_MIB=8192
# Where this library lives, for the tier resolver beside it — taken at source
# time, as scripts/agents.lib.sh takes its _agents_here.
_budget_lib_dir=${_budget_here:-}

_budget_who() { printf '%s' "${BUDGET_WHO:-budget}"; }

# _budget_die <message> — the refusal. Every caller of it runs inside one of
# the public functions' subshells, so this `exit` is that function's
# `return 2`, never the caller's shell going away.
_budget_die() {
	echo "x $(_budget_who): $1" >&2
	exit 2
}

# _budget_whole_number <what> <value> — a whole number from 1: 0 is not a
# ceiling, and a leading zero is octal to $(( )) in every sh — 025 would
# derive 21%. The one validator for the flags, the policy and the inherited
# pair.
_budget_whole_number() {
	case "$2" in
	'' | *[!0123456789]*) _budget_die "$1 takes a whole number, got '$2'" ;;
	0) _budget_die "$1 takes a whole number from 1, and 0 is not one. Leave it out for the default." ;;
	0*) _budget_die "$1 takes a whole number with no leading zero, got '$2'" ;;
	esac
}

# _budget_policy_numbers NAME=default ... — the policy values in ONE sourcing
# of the tier policy file, each the default when unset or empty and refused
# when not a whole number. Prints them space-separated, in argument order.
# The policy file is sourced in a subshell of its own: nothing it defines
# reaches the derivation. The assignments sit on their own lines because
# bash and zsh drop a prefix assignment on `.`.
_budget_policy_numbers() {
	(
		[ -n "$_budget_lib_dir" ] && [ -f "$_budget_lib_dir/agents.lib.sh" ] ||
			_budget_die "cannot find agents.lib.sh — a sourcing caller sets _budget_here to this library's directory first"
		AGENTS_CONFIG=${AGENTS_CONFIG:-}
		export AGENTS_CONFIG
		_agents_here="$_budget_lib_dir"
		. "$_budget_lib_dir/agents.lib.sh"
		agents_load_config >/dev/null 2>&1 || true
		for _bpn in "$@"; do
			_bpn_name=${_bpn%%=*} _bpn_default=${_bpn#*=}
			eval "_bpn_v=\"\${$_bpn_name:-}\""
			[ -n "$_bpn_v" ] || _bpn_v=$_bpn_default
			_budget_whole_number "$_bpn_name in your agents config" "$_bpn_v"
			printf '%s ' "$_bpn_v"
		done
	)
}

# _budget_percent_below_100 <suffix> <value> — a percentage is 1–99
# (the kit's ADR-0006 clause 3): the budget sits BELOW the ceiling the
# session shares.
_budget_percent_below_100() {
	[ "$2" -lt 100 ] ||
		_budget_die "AGENT_BUDGET_$1 must be below 100 — the budget sits below the ceiling the session shares (the kit's ADR-0006), got $2"
}

# _budget_floor_at_most_ceiling <floor suffix> <floor> <ceiling suffix> <ceiling>
# — a floor above its ceiling leaves the clamp with no answer.
_budget_floor_at_most_ceiling() {
	[ "$2" -le "$4" ] ||
		_budget_die "AGENT_BUDGET_$1 $2 is above AGENT_BUDGET_$3 $4 — a floor sits at or below its ceiling"
}

# _budget_session_tasks — the task ceiling this session runs under: the
# smallest numeric pids.max on the path from this process's own cgroup up to
# the root. On a systemd host that is the user slice's TasksMax — 33% of
# threads-max by default, and the ceiling the incident behind
# the kit's ADR-0006 filled. Prints "<ceiling> <cgroup>"; fails when no cgroup on the
# path sets one, which is also what a host without cgroup v2 (no `0::` line)
# looks like.
_budget_session_tasks() {
	_bst_host=${AGENT_DISPATCH_HOST_ROOT:-}
	_bst_path=$(sed -n 's/^0:://p' "$_bst_host/proc/self/cgroup" 2>/dev/null)
	[ -n "$_bst_path" ] || return 1
	_bst_best="" _bst_where=""
	while :; do
		_bst_v=$(cat "$_bst_host/sys/fs/cgroup$_bst_path/pids.max" 2>/dev/null)
		case "$_bst_v" in
		'' | *[!0123456789]*) ;;
		*)
			if [ -z "$_bst_best" ] || [ "$_bst_v" -lt "$_bst_best" ]; then
				_bst_best=$_bst_v _bst_where=$_bst_path
			fi
			;;
		esac
		case "$_bst_path" in
		'' | /) break ;;
		esac
		_bst_path=${_bst_path%/*}
	done
	[ -n "$_bst_best" ] || return 1
	# The basename of the root is empty; a container with a private cgroup
	# namespace and a pids limit on it is exactly where the line matters.
	_bst_name=${_bst_where##*/}
	[ -n "$_bst_name" ] || _bst_name=/
	printf '%s %s\n' "$_bst_best" "$_bst_name"
}

# _budget_mem_available_mib — MemAvailable now, in MiB. What the host could
# give at this moment, not what it has installed.
_budget_mem_available_mib() {
	_bma_kb=$(awk '/^MemAvailable:/ { print $2; exit }' "${AGENT_DISPATCH_HOST_ROOT:-}/proc/meminfo" 2>/dev/null)
	case "$_bma_kb" in
	'' | *[!0123456789]*) return 1 ;;
	esac
	printf '%s\n' $((_bma_kb / 1024))
}

# _budget_clamp <derived> <floor> <ceiling> — sets _bc_value and _bc_note.
# Below the floor is raised AND said: the operator hears that this host is
# smaller than the percentage assumes. Above the ceiling is held in silence,
# because more headroom buys a worker nothing.
_budget_clamp() {
	_bc_value=$1 _bc_note=""
	if [ "$1" -lt "$2" ]; then
		_bc_value=$2 _bc_note="$1 is below the floor $2 — raised to the floor"
	elif [ "$1" -gt "$3" ]; then
		_bc_value=$3 _bc_note="$1 is above the ceiling $3 — held to the ceiling"
	fi
}

# _budget_nproc_limit — the per-user process limit (RLIMIT_NPROC) this
# session runs under: the number `ulimit -u` prints, read from
# /proc/self/limits so it comes through the same host seam as the cgroup
# ceiling and a suite can choose it. Prints the soft limit — a number, or
# "unlimited"; fails when the file has no such line.
_budget_nproc_limit() {
	_bnl=$(awk '/^Max processes/ { print $3; exit }' "${AGENT_DISPATCH_HOST_ROOT:-}/proc/self/limits" 2>/dev/null)
	[ -n "$_bnl" ] || return 1
	printf '%s\n' "$_bnl"
}

# _budget_nproc_flag — the ulimit option that sets the per-user process limit
# under THIS sh, for the rlimit rung: -u for bash, zsh and ksh; -p for dash,
# which spells the same limit differently (it has no -u, and bash's -p is the
# pipe size, which cannot be set — so the order below is safe both ways).
# Probed by setting the limit to itself in a subshell; a shell with neither
# prints nothing, and that is the ladder's third rung.
_budget_nproc_flag() {
	for _bnf in -u -p; do
		if (ulimit "$_bnf" "$(ulimit "$_bnf" 2>/dev/null)") >/dev/null 2>&1; then
			printf '%s' "$_bnf"
			return 0
		fi
	done
	return 1
}

# _budget_rung <nproc flag> — the highest rung of the kit's ADR-0006 ladder
# this host offers, probed rather than configured: a policy file cannot know
# what host it is on. `scope` needs systemd-run, a user manager that answers,
# AND the pids and memory controllers delegated to it — read from
# cgroup.controllers on this process's own cgroup, because a manager that
# answers is reachable, not necessarily able to bound: without `memory`,
# -p MemoryMax= is accepted and applies nothing. `scope-tasks` is pids
# delegated and memory not — the scope still carries the task bound, which
# is the incident's. `rlimit` needs a shell whose ulimit can set the process
# count; `none` is neither.
_budget_rung() {
	if command -v systemd-run >/dev/null 2>&1 && systemctl --user show --property=Version >/dev/null 2>&1; then
		_br_own=$(sed -n 's/^0:://p' "${AGENT_DISPATCH_HOST_ROOT:-}/proc/self/cgroup" 2>/dev/null)
		_br_ctl=" $(cat "${AGENT_DISPATCH_HOST_ROOT:-}/sys/fs/cgroup$_br_own/cgroup.controllers" 2>/dev/null) "
		# Two separate word tests: one pattern for both would need the space
		# between them twice, and a single space cannot be consumed twice.
		_br_pids=0 _br_memory=0
		case "$_br_ctl" in *" pids "*) _br_pids=1 ;; esac
		case "$_br_ctl" in *" memory "*) _br_memory=1 ;; esac
		if [ "$_br_pids" = 1 ] && [ "$_br_memory" = 1 ]; then
			echo scope
			return 0
		elif [ "$_br_pids" = 1 ]; then
			echo scope-tasks
			return 0
		fi
	fi
	if [ -n "$1" ]; then
		echo rlimit
	else
		echo none
	fi
}

# _budget_field <record-file> <key> — one field of a record, or nothing.
# Builtins only: the verdict side runs where a fork may be refused.
_budget_field() {
	while IFS= read -r _bf_line; do
		case "$_bf_line" in
		"$2="*)
			printf '%s' "${_bf_line#*=}"
			return 0
			;;
		esac
	done <"$1"
}

# The Budget's three modes: disabled by flag, inherited from an outer
# dispatch, or derived here. An inner dispatch derives nothing
# (the kit's ADR-0006 clause 7): a scope opened inside a scope is a sibling, not a
# child, and would escape the outer's ceiling — so the outer's numbers arrive
# by environment and are taken as given.
#
# Where a host fact is missing — the per-user limit is unlimited or
# unreadable, /proc/meminfo has no MemAvailable — there is nothing to take a
# percentage of, and the policy CEILING stands in on both sides (clause 2):
# the most the policy lets one worker have, so the worker is bounded by the
# policy rather than by nothing. Never the floor, which answers a host KNOWN
# to be small.
budget_derive() (
	_bd_tasks_flag="" _bd_memory_flag="" _bd_off=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--tasks)
			[ $# -ge 2 ] || _budget_die "--tasks needs a number of tasks"
			_budget_whole_number --tasks "$2"
			_bd_tasks_flag=$2
			shift 2
			;;
		--memory)
			[ $# -ge 2 ] || _budget_die "--memory needs a number of MiB"
			_budget_whole_number --memory "$2"
			_bd_memory_flag=$2
			shift 2
			;;
		--off)
			_bd_off=1
			shift
			;;
		*) _budget_die "budget_derive takes --tasks <n>, --memory <MiB> and --off, got '$1'" ;;
		esac
	done
	[ "$_bd_off" = 1 ] && [ -n "$_bd_tasks_flag$_bd_memory_flag" ] &&
		_budget_die "--off and a --tasks or --memory override contradict each other"
	_bd_nproc_flag=$(_budget_nproc_flag) || _bd_nproc_flag=""
	# One sourcing for the six; the status is checked here, where it can be.
	_bd_all=$(_budget_policy_numbers \
		"AGENT_BUDGET_TASKS_PERCENT=$BUDGET_DEFAULT_TASKS_PERCENT" \
		"AGENT_BUDGET_TASKS_FLOOR=$BUDGET_DEFAULT_TASKS_FLOOR" \
		"AGENT_BUDGET_TASKS_CEILING=$BUDGET_DEFAULT_TASKS_CEILING" \
		"AGENT_BUDGET_MEMORY_PERCENT=$BUDGET_DEFAULT_MEMORY_PERCENT" \
		"AGENT_BUDGET_MEMORY_FLOOR_MIB=$BUDGET_DEFAULT_MEMORY_FLOOR_MIB" \
		"AGENT_BUDGET_MEMORY_CEILING_MIB=$BUDGET_DEFAULT_MEMORY_CEILING_MIB") || exit 2
	_bd_tasks_percent=${_bd_all%% *} _bd_all=${_bd_all#* }
	_bd_tasks_floor=${_bd_all%% *} _bd_all=${_bd_all#* }
	_bd_tasks_ceiling=${_bd_all%% *} _bd_all=${_bd_all#* }
	_bd_memory_percent=${_bd_all%% *} _bd_all=${_bd_all#* }
	_bd_memory_floor=${_bd_all%% *} _bd_all=${_bd_all#* }
	_bd_memory_ceiling=${_bd_all%% *}
	_budget_percent_below_100 TASKS_PERCENT "$_bd_tasks_percent"
	_budget_percent_below_100 MEMORY_PERCENT "$_bd_memory_percent"
	_budget_floor_at_most_ceiling TASKS_FLOOR "$_bd_tasks_floor" TASKS_CEILING "$_bd_tasks_ceiling"
	_budget_floor_at_most_ceiling MEMORY_FLOOR_MIB "$_bd_memory_floor" MEMORY_CEILING_MIB "$_bd_memory_ceiling"
	_bd_mode="" _bd_tasks="" _bd_tasks_from="" _bd_memory="" _bd_memory_from="" _bd_rung=none
	# Inherited is checked before disabled: an inner dispatch is already inside
	# the outer scope's cgroup, and --off on it cannot leave (clause 7).
	if [ -n "${AGENT_DISPATCH_BUDGET_TASKS:-}" ]; then
		_bd_mode=inherited
		_bd_tasks=$AGENT_DISPATCH_BUDGET_TASKS
		_bd_memory=${AGENT_DISPATCH_BUDGET_MEMORY_MIB:-}
		# Taken from the outer dispatch, but not on trust: an outer dispatch
		# exports both or neither, each a whole number.
		_budget_whole_number "AGENT_DISPATCH_BUDGET_TASKS, inherited from the outer dispatch," "$_bd_tasks"
		[ -n "$_bd_memory" ] ||
			_budget_die "AGENT_DISPATCH_BUDGET_TASKS is set and AGENT_DISPATCH_BUDGET_MEMORY_MIB is not — an outer dispatch exports both or neither"
		_budget_whole_number "AGENT_DISPATCH_BUDGET_MEMORY_MIB, inherited from the outer dispatch," "$_bd_memory"
	elif [ "$_bd_off" = 1 ]; then
		_bd_mode=disabled
	else
		_bd_mode=derived
		if [ -n "$_bd_tasks_flag" ]; then
			# An override is named by the dispatcher's flag, the one an
			# operator types; the dry run prints this field as it stands.
			_bd_tasks=$_bd_tasks_flag _bd_tasks_from="--budget-tasks"
			[ "$_bd_tasks" -lt "$_bd_tasks_floor" ] &&
				_bd_tasks_from="$_bd_tasks_from; below the floor $_bd_tasks_floor, honoured as given"
		elif _bt=$(_budget_session_tasks); then
			_bt_base=${_bt%% *} _bt_where=${_bt#* }
			_budget_clamp $((_bt_base * _bd_tasks_percent / 100)) "$_bd_tasks_floor" "$_bd_tasks_ceiling"
			_bd_tasks=$_bc_value
			_bd_tasks_from="$_bd_tasks_percent% of $_bt_base, the pids.max of cgroup $_bt_where${_bc_note:+: $_bc_note}"
		else
			_bt_base=$(_budget_nproc_limit) || _bt_base=""
			case "$_bt_base" in
			'' | *[!0123456789]*)
				_bd_tasks=$_bd_tasks_ceiling
				_bd_tasks_from="the policy ceiling — no cgroup on this session sets a task ceiling and the per-user process limit is ${_bt_base:-unreadable}"
				;;
			*)
				_budget_clamp $((_bt_base * _bd_tasks_percent / 100)) "$_bd_tasks_floor" "$_bd_tasks_ceiling"
				_bd_tasks=$_bc_value
				_bd_tasks_from="$_bd_tasks_percent% of $_bt_base, the per-user process limit (RLIMIT_NPROC — no cgroup on this session sets a task ceiling)${_bc_note:+: $_bc_note}"
				;;
			esac
		fi
		if [ -n "$_bd_memory_flag" ]; then
			_bd_memory=$_bd_memory_flag _bd_memory_from="--budget-memory"
			[ "$_bd_memory" -lt "$_bd_memory_floor" ] &&
				_bd_memory_from="$_bd_memory_from; below the floor $_bd_memory_floor, honoured as given"
		elif _bm_base=$(_budget_mem_available_mib); then
			_budget_clamp $((_bm_base * _bd_memory_percent / 100)) "$_bd_memory_floor" "$_bd_memory_ceiling"
			_bd_memory=$_bc_value
			_bd_memory_from="$_bd_memory_percent% of $_bm_base MiB MemAvailable${_bc_note:+: $_bc_note}"
		else
			_bd_memory=$_bd_memory_ceiling
			_bd_memory_from="the policy ceiling — /proc/meminfo has no MemAvailable to derive from"
		fi
		_bd_rung=$(_budget_rung "$_bd_nproc_flag")
	fi
	printf 'mode=%s\n' "$_bd_mode"
	printf 'tasks=%s\n' "$_bd_tasks"
	printf 'memory_mib=%s\n' "$_bd_memory"
	printf 'tasks_from=%s\n' "$_bd_tasks_from"
	printf 'memory_from=%s\n' "$_bd_memory_from"
	printf 'rung=%s\n' "$_bd_rung"
	printf 'tasks_floor=%s\n' "$_bd_tasks_floor"
	printf 'tasks_ceiling=%s\n' "$_bd_tasks_ceiling"
	printf 'memory_floor_mib=%s\n' "$_bd_memory_floor"
	printf 'memory_ceiling_mib=%s\n' "$_bd_memory_ceiling"
	printf 'nproc_flag=%s\n' "$_bd_nproc_flag"
)

# _budget_counters_text — the text of _cg_counters <cgroup path>, which sets
# _pm (pids.events max) and _ok (memory.events oom_kill), each `-` when its
# file could not be read. Printed as TEXT because it runs in another shell:
# the wrapper inside the scope, and budget_verdict reading from outside it.
# Builtins only, because inside the scope at the task ceiling a fork of its
# own — an awk, a sed — would itself be rejected. "Could not read" and "no
# ceiling hit" must not look alike (driver 4), hence `-`, never 0.
_budget_counters_text() {
	cat <<'CNT'
_cg_counters() {
	_pm=- _ok=-
	[ -n "$1" ] || return 0
	{ while read -r _k _v _rest; do case "$_k" in max) _pm=$_v ;; esac; done; } 2>/dev/null <"/sys/fs/cgroup$1/pids.events" || _pm=-
	{ while read -r _k _v _rest; do case "$_k" in oom_kill) _ok=$_v ;; esac; done; } 2>/dev/null <"/sys/fs/cgroup$1/memory.events" || _ok=-
}
CNT
}

# _budget_props <rung> <tasks> <memory MiB> — the properties a scope carries
# on that rung; the pre-flight and the real spawn open a scope with the same.
#
# OOMPolicy=continue and MemorySwapMax=0 REFINE clause 5's bare
# `-p MemoryMax=<MiB>M` (the kit's ADR-0006 records why): without
# OOMPolicy=continue the host tore the whole scope down on the first OOM and
# the wrapper never ran to read the counter clause 6 needs; without
# MemorySwapMax=0 the runaway filled swap for seconds and could trip
# systemd-oomd's pressure kill of the scope before MemoryMax bit. With both,
# the kernel OOM-kills the worker inside the cgroup, the wrapper survives,
# and the memory ceiling is observable at once.
_budget_props() {
	if [ "$1" = scope ]; then
		printf '%s' "-p TasksMax=$2 -p MemoryMax=${3}M -p MemorySwapMax=0 -p OOMPolicy=continue"
	else
		printf '%s' "-p TasksMax=$2 -p OOMPolicy=continue"
	fi
}

# _budget_quote <arg…> — the arguments as one string a shell `eval` reads
# back as the same words: each single-quoted, its own quotes escaped.
_budget_quote() {
	_bq=""
	for _bq_a; do
		_bq="$_bq '$(printf '%s\n' "$_bq_a" | sed "s/'/'\\\\''/g")'"
	done
	printf '%s' "${_bq# }"
}

# The wrapper the scope runs. Its three arguments are the started marker,
# the verdict file and the command as one string — positional parameters,
# which are not inherited, so none of the three reaches the command's
# environment. It writes the marker before the command runs, so a wrapper
# that never started (the scope torn down before its first line) is told from
# a command that merely exited non-zero; after the command it reads its own
# cgroup's counters with builtins and writes the verdict before the scope
# empties.
_budget_wrapper_text() {
	_budget_counters_text
	cat <<'WRAP'
_own=""
while IFS= read -r _l; do case "$_l" in 0::*) _own=${_l#0::} ;; esac; done </proc/self/cgroup 2>/dev/null
: >"$1"
eval "$3"
_st=$?
_cg_counters "$_own"
printf '%s %s %s\n' "$_pm" "$_ok" "$_st" >"$2"
exit "$_st"
WRAP
}

# budget_run — see the header. The scope rung is decided BEFORE the spawn:
# systemd-run can refuse after the probe passed — the bus gone between probe
# and spawn, a manager that will not create scopes (the kit's ADR-0006
# clause 5). So an empty scope with the real properties is opened and closed
# first, in milliseconds; a refusal there falls to the weaker rung, loudly,
# with systemd-run's own message. After the real spawn nothing is retried:
# the started marker is a file, and a file the command's tree can remove must
# never be what runs the command a second time.
budget_run() (
	[ $# -ge 2 ] || _budget_die "budget_run takes <record-file> <verdict-file> [--unit <name>] -- <cmd…>"
	_brun_record=$1 _brun_verdict=$2 _brun_unit=""
	shift 2
	[ -f "$_brun_record" ] || _budget_die "budget_run: no record at $_brun_record"
	while [ $# -gt 0 ]; do
		case "$1" in
		--unit)
			[ $# -ge 2 ] || _budget_die "budget_run: --unit needs a name"
			_brun_unit=$2
			shift 2
			;;
		--)
			shift
			break
			;;
		*) _budget_die "budget_run: expected -- before the command, got '$1'" ;;
		esac
	done
	[ $# -ge 1 ] || _budget_die "budget_run: no command after --"
	_brun_mode=$(_budget_field "$_brun_record" mode)
	_brun_tasks=$(_budget_field "$_brun_record" tasks)
	_brun_memory=$(_budget_field "$_brun_record" memory_mib)
	_brun_rung=$(_budget_field "$_brun_record" rung)
	# Only a DERIVED budget opens a rung: an inherited one is already inside
	# the outer scope's cgroup, and a disabled one runs bare on purpose.
	[ "$_brun_mode" = derived ] || _brun_rung=none
	rm -f "$_brun_verdict" "$_brun_verdict.started" "$_brun_verdict.unit"
	case "$_brun_rung" in
	scope | scope-tasks)
		_brun_props=$(_budget_props "$_brun_rung" "$_brun_tasks" "$_brun_memory")
		# eval, as the spawn does: zsh does not split an unquoted expansion.
		if ! _brun_err=$(eval "systemd-run --user --scope $_brun_props --quiet true" 2>&1 >/dev/null); then
			echo "!  $(_budget_who): the transient scope cannot open — systemd-run refused after the probe passed:" >&2
			echo "   ${_brun_err:-(no message)}" >&2
			echo "   Running the worker under the weaker rlimit rung instead." >&2
			if _budget_nproc_flag >/dev/null; then _brun_rung=rlimit; else _brun_rung=none; fi
		fi
		;;
	esac
	printf '%s\n' "$_brun_rung" >"$_brun_verdict.rung"
	case "$_brun_rung" in
	scope | scope-tasks)
		[ -n "$_brun_unit" ] && printf '%s\n' "$_brun_unit" >"$_brun_verdict.unit"
		_brun_cmd=$(_budget_quote "$@")
		_brun_wrap=$(_budget_wrapper_text)
		if [ -n "$_brun_unit" ]; then
			eval "systemd-run --user --scope --unit=\"\$_brun_unit\" $_brun_props --quiet sh -c \"\$_brun_wrap\" budget-run \"\$_brun_verdict.started\" \"\$_brun_verdict\" \"\$_brun_cmd\""
		else
			eval "systemd-run --user --scope $_brun_props --quiet sh -c \"\$_brun_wrap\" budget-run \"\$_brun_verdict.started\" \"\$_brun_verdict\" \"\$_brun_cmd\""
		fi
		;;
	rlimit)
		# ulimit in this subshell, before the command: the process count under
		# the flag this sh spells it with, the data segment in KiB. Weaker, per
		# the kit's ADR-0006: RLIMIT_NPROC counts the uid, and RLIMIT_DATA is
		# per process. A refused ulimit is heard, and the command still runs.
		# `exec`, so the limits die with the command and no process carrying
		# the caller's name holds them.
		_brun_nf=$(_budget_nproc_flag) || _brun_nf=-u
		ulimit "$_brun_nf" "$_brun_tasks" ||
			echo "!  $(_budget_who): ulimit refused the task ceiling $_brun_tasks — the rlimit rung applies no task bound" >&2
		ulimit -d $((_brun_memory * 1024)) ||
			echo "!  $(_budget_who): ulimit -d refused the memory ceiling $_brun_memory MiB — the rlimit rung applies no memory bound" >&2
		exec "$@"
		;;
	*)
		"$@"
		;;
	esac
)

# budget_verdict — see the header. On a scope rung the verdict is the cgroup
# counters the wrapper wrote: a task ceiling hit (pids.events max > 0) or, on
# the full scope rung, a memory ceiling hit (memory.events oom_kill > 0). On
# the rlimit and no-op rungs there is no counter, and nothing is printed
# (the kit's ADR-0006 clause 6). A verdict that cannot be read is its own outcome
# — never a silent zero (driver 4): the marker missing (the wrapper never
# ran), the verdict file missing or malformed (a pressure kill takes every
# process in the cgroup, wrapper included), or a counter marked unreadable.
budget_verdict() (
	_bv_timed_out=0
	case "$#:${2:-}" in
	1:) ;;
	2:--timed-out) _bv_timed_out=1 ;;
	*) _budget_die "budget_verdict takes <verdict-file> [--timed-out]" ;;
	esac
	_bv=$1 _bv_rung=""
	[ -f "$_bv.rung" ] && read -r _bv_rung <"$_bv.rung"
	case "$_bv_rung" in
	scope | scope-tasks) ;;
	*) return 0 ;;
	esac
	# From outside the scope, while it lives. For a watchdog about to signal:
	# once the scope empties, its cgroup and the counters are gone, and a
	# ceiling hit before the watchdog fired is the earlier event. And for a
	# run whose wrapper died while something of its tree still holds the
	# scope open: the counters outlived the wrapper, so they are read rather
	# than reported missing.
	if [ ! -f "$_bv" ] && [ -f "$_bv.unit" ]; then
		read -r _bv_unit <"$_bv.unit"
		_bv_cg=$(systemctl --user show -p ControlGroup --value "$_bv_unit" 2>/dev/null)
		if [ -n "$_bv_cg" ]; then
			eval "$(_budget_counters_text)"
			_cg_counters "$_bv_cg"
			if [ "$_bv_timed_out" = 1 ]; then _bv_status=124; else _bv_status=-; fi
			printf '%s %s %s\n' "$_pm" "$_ok" "$_bv_status" >"$_bv"
		fi
	fi
	if [ ! -f "$_bv.started" ]; then
		echo "!  $(_budget_who): the scope's started marker is missing after the spawn — the scope was torn
   down before the worker started, or this dispatch's scratch was removed under it." >&2
		return 1
	fi
	if [ ! -f "$_bv" ]; then
		echo "!  $(_budget_who): the scope's verdict file is missing — the wrapper did not survive to write it
   (the scope was torn down, or a pressure kill took the wrapper with the worker)." >&2
		return 1
	fi
	_v_pids="" _v_oom="" _v_rest=""
	read -r _v_pids _v_oom _v_rest <"$_bv" 2>/dev/null || true
	case "$_v_pids" in
	-)
		echo "!  $(_budget_who): the pids.events counter could not be read inside the scope." >&2
		return 1
		;;
	'' | *[!0123456789]*)
		echo "!  $(_budget_who): the scope's verdict file is malformed ('$_v_pids $_v_oom $_v_rest')." >&2
		return 1
		;;
	esac
	case "$_v_oom" in
	-)
		if [ "$_bv_rung" = scope ]; then
			echo "!  $(_budget_who): the memory.events counter could not be read inside the scope." >&2
			return 1
		fi
		;;
	'' | *[!0123456789]*)
		echo "!  $(_budget_who): the scope's verdict file is malformed ('$_v_pids $_v_oom $_v_rest')." >&2
		return 1
		;;
	esac
	if [ "$_v_pids" -gt 0 ]; then
		echo tasks
	elif [ "$_bv_rung" = scope ] && [ "$_v_oom" -gt 0 ]; then
		echo memory
	fi
	return 0
)

# budget_inherited_bounds — see the header. A transient scope opened from a
# cgroup that already bounds the caller would be a SIBLING under the user
# manager, outside that cgroup and above its ceilings (the kit's ADR-0006
# clause 7). The root is every scope's ancestor — a container with a
# pids.max on its root bounds a child scope too — so it never counts.
budget_inherited_bounds() (
	_bib_host=${AGENT_DISPATCH_HOST_ROOT:-}
	_bib_tasks="" _bib_memory=""
	if [ $# -ge 1 ]; then
		[ -f "$1" ] || _budget_die "budget_inherited_bounds: no record at $1"
		_bib_tasks=$(_budget_field "$1" tasks)
		_bib_memory=$(_budget_field "$1" memory_mib)
	fi
	_bib_own=$(sed -n 's/^0:://p' "$_bib_host/proc/self/cgroup" 2>/dev/null)
	case "$_bib_own" in '' | /) return 1 ;; esac
	_bib_pids=$(cat "$_bib_host/sys/fs/cgroup$_bib_own/pids.max" 2>/dev/null)
	_bib_mem=$(cat "$_bib_host/sys/fs/cgroup$_bib_own/memory.max" 2>/dev/null)
	_bib_bounds=0
	case "$_bib_pids" in
	'' | *[!0123456789]*) _bib_pids=max ;;
	*)
		_bib_tightest=$(_budget_session_tasks) && [ "${_bib_tightest#* }" = "${_bib_own##*/}" ] && _bib_bounds=1
		case "$_bib_tasks" in
		'' | *[!0123456789]*) ;;
		*) [ "$_bib_pids" -lt "$_bib_tasks" ] && _bib_bounds=1 ;;
		esac
		;;
	esac
	case "$_bib_mem" in
	'' | *[!0123456789]*) _bib_mem=max ;;
	*)
		_bib_mem=$((_bib_mem / 1048576))
		case "$_bib_memory" in
		'' | *[!0123456789]*) ;;
		*) [ "$_bib_mem" -lt "$_bib_memory" ] && _bib_bounds=1 ;;
		esac
		;;
	esac
	[ "$_bib_bounds" = 1 ] || return 1
	printf 'cgroup=%s\n' "${_bib_own##*/}"
	printf 'tasks=%s\n' "$_bib_pids"
	printf 'memory_mib=%s\n' "$_bib_mem"
)
