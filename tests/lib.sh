#!/bin/sh
# tests/lib.sh — the kit's tiny test harness. Sourced, never executed. Every
# suite runs INSIDE THE WORKER BUDGET from the moment it sources this file —
# "the budget" below says how, and how to turn it off.
#
# The kit's core is POSIX sh and git, so its tests are too: no runner, no
# package.json, no install. `sh tests/<name>.test.sh` is the whole invocation.
#
# The guards under test read git history and produce a verdict about it, so
# every fixture here is a REAL throwaway repository with real commits and a real
# `git diff`. Faking the history would fake the test.
#
# Fixtures are hermetic: their own identity, no signing, and hooksPath pointed
# at nothing — otherwise a developer's global GPG requirement or hook manager
# would fail these tests for reasons that have nothing to do with the guards.

failures=0
LAST_OUT=""
LAST_STATUS=0

# Collation is the developer's, and the suites are full of `sort`s whose output
# is compared against strings written in one order. Under en_US.UTF-8 a
# leading `.` is ignored, so `adapters/` sorts before `.agents/`; under C it
# does not. self-host's delta probe failed on exactly that for the whole of a
# release wave and was set aside as pre-existing each time.
#
# Pinned HERE, at source time, not in t_init: seven suites never call t_init,
# and a pin that a suite has to opt into is the coupling this is removing.
# Three suites carry their own assertion helpers (adapters-demo, setup-demo,
# kit-demo) and source this file for the pin and the budget below alone. The
# same posture t_git_identity takes for signing and hooks paths — a
# developer's environment does not decide what a test asserts — and
# tests/fixture-builders.test.sh holds this one the way it holds those. A
# suite that means to test a locale sets LC_ALL on the command itself, as
# agents-tiers does, and a prefix still wins over an export.
LC_ALL=C
export LC_ALL

# The repo root, derived once from the suite that sourced this harness; every
# helper below anchors on it rather than on the working directory. Overridable
# because a fixture that lives in scratch — a throwaway suite written to prove
# what a KILLED suite leaves behind (#221) — sits outside tests/, so deriving
# from its $0 would point the harness at the scratch directory instead of the
# repo. A suite under tests/ never sets it and never notices.
T_ROOT=${T_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}

# --- the budget --------------------------------------------------------------
# EVERY SUITE RUNS INSIDE THE BUDGET A DISPATCHED WORKER GETS (ADR-0006, #209):
# a task ceiling and a memory ceiling on its whole process tree, derived from
# this host by the dispatcher's own code — this file sources
# scripts/agent-dispatch.sh for the derivation, the rung and the scope
# properties, so a suite and a worker cannot disagree about a number — and
# applied down the same ladder: a transient scope under the user service
# manager, else rlimits in the suite's own shell (weaker, and said so on
# stderr), else a loud no-op. Found live: a runaway suite filled the login
# session's task ceiling and froze the host three times (#205). Inside the
# scope a runaway fails at its ceiling instead, and after the suite exits a
# wrapper reads the scope's pids.events / memory.events (builtins only: at the
# task ceiling a fork of its own would be refused) and turns a hit into
#
#   FAIL  <suite> hit its TASK ceiling (N tasks) …   exit 71 (EX_OSERR)
#
# whatever the suite itself printed — a suite that hit a ceiling did not run
# whole — while the calling shell forks on. On the rlimit rung a hit is not
# observable (the ADR says why): it shows as the shell's own fork or
# allocation error and the suite's own status, never as a FAIL line, and
# the rung's note says so before the suite runs.
#
# HOW A SUITE GETS THERE WITHOUT A RUNNER. The first time this file is sourced
# it derives the budget and runs `sh "$0" "$@"` — the suite again, from its
# first line — inside it, with AGENT_SUITE_BUDGET set to what was applied; the
# second sourcing sees that and carries on into the suite. That marker is the
# recursion bound (#206's lesson): a run that lost it would derive again and
# open a second scope — a SIBLING under the user manager, never a child — so
# nothing here leans on an outer scope as a backstop, and no suite should.
# A second bound survives a lost marker on the scope rung: the inner run's
# own cgroup is the suite-<name>-<pid>.scope this file opened, and a run
# that finds itself there without the marker is refused, exit 2, rather
# than opening a sibling per re-execution until the host refuses to fork.
# The lines above a suite's source line run in both runs, so keep them free
# of side effects; the outer run's own EXIT trap still fires when it exits
# with the inner run's status.
#
# AGENT_SUITE_BUDGET is the one switch:
#   unset (or empty)   derive and apply — the default
#   off                the suite runs bare, as before #209; said on stderr
#   applied: …         set by this file for the inner run; never set it yourself
# Anything else is refused, exit 2: a typo must not read as "inside". Inside a
# dispatched worker (AGENT_DISPATCH_BUDGET_TASKS set) the suite is already
# inside that worker's budget and opens none of its own (ADR-0006 clause 7).
# The same when the cgroup this shell already sits in bounds the suite — an
# operator's own `systemd-run --user --scope -p TasksMax=…`, whose pids.max
# is the tightest on the path or whose pids.max / memory.max the derived
# ceilings would exceed: a scope opened from there is a sibling outside it,
# so the suite runs in place under that cgroup's ceilings, marker `rung
# inherited`, and the note names the cgroup.
# The policy the budget is derived under is the kit's own,
# scripts/agents.kit.config.sh, never the environment's $AGENTS_CONFIG — the
# defaults today, and the place to tighten the suite's budget if a clamp is
# ever reached in ordinary running. AGENT_DISPATCH_HOST_ROOT reaches the
# derivation as it reaches the dispatcher: tests/suite-budget.test.sh hands
# stub suites a small fake host through it.

# _sb_note <line> — one stderr line; every line the test harness says about the
# budget is prefixed `tests/lib.sh:` so it reads as the test harness's, not the
# suite's.
_sb_note() { echo "$1" >&2; }

# _sb_own_bounds — does the cgroup this shell sits in already bound the
# suite? True when its pids.max is the tightest on the path (an operator's
# scope, not the session slice), or its pids.max or memory.max sits below
# the derived ceiling: a transient scope opened from here would be a SIBLING
# under the user manager, outside that cgroup and above its ceilings
# (ADR-0006 clause 7). The root is every scope's ancestor — a container
# with a pids.max on its root bounds a child scope too — so it never
# counts. Sets _sb_own_name and _sb_own_limits ("tasks <n|max>, memory
# <MiB|max>"). Called after _budget_derive, in its shell.
_sb_own_bounds() {
	_sb_own_name="" _sb_own_limits=""
	_ob_own=$(sed -n 's/^0:://p' "$_host/proc/self/cgroup" 2>/dev/null)
	case "$_ob_own" in '' | /) return 1 ;; esac
	_ob_pids=$(cat "$_host/sys/fs/cgroup$_ob_own/pids.max" 2>/dev/null)
	_ob_mem=$(cat "$_host/sys/fs/cgroup$_ob_own/memory.max" 2>/dev/null)
	_ob_bounds=0
	case "$_ob_pids" in
	'' | *[!0123456789]*) _ob_pids=max ;;
	*)
		_ob_tightest=$(_budget_session_tasks) && [ "${_ob_tightest#* }" = "${_ob_own##*/}" ] && _ob_bounds=1
		[ "$_ob_pids" -lt "$BUDGET_TASKS" ] && _ob_bounds=1
		;;
	esac
	case "$_ob_mem" in
	'' | *[!0123456789]*) _ob_mem=max ;;
	*)
		_ob_mem=$((_ob_mem / 1048576))
		[ "$_ob_mem" -lt "$BUDGET_MEMORY" ] && _ob_bounds=1
		_ob_mem="$_ob_mem MiB"
		;;
	esac
	[ "$_ob_bounds" = 1 ] || return 1
	_sb_own_name=${_ob_own##*/}
	_sb_own_limits="tasks $_ob_pids, memory $_ob_mem"
}

# t_suite_under_budget <suite> [args…] — run the suite inside the budget
# _budget_derive left in BUDGET_TASKS / BUDGET_MEMORY / BUDGET_RUNG, down the
# rung the host offers. Called in the subshell that sourced the dispatcher —
# its `die` and its names stay there — and exits with the suite's
# status, or 71 on a ceiling hit.
t_suite_under_budget() {
	case "$BUDGET_TASKS_FROM$BUDGET_MEMORY_FROM" in
	*"below the floor"*)
		_sb_note "!  tests/lib.sh: this host is small — a derived budget was raised to the floor (tasks $BUDGET_TASKS: $BUDGET_TASKS_FROM; memory $BUDGET_MEMORY MiB: $BUDGET_MEMORY_FROM)"
		;;
	esac
	_sb_rung=$BUDGET_RUNG
	case "$_sb_rung" in
	scope | scope-tasks)
		# Decided before the run, as the dispatcher decides it: an empty scope
		# with the real properties opens and closes first, and a refusal there
		# falls to the weaker rung out loud, with systemd-run's own message.
		_budget_scope_props "$_sb_rung"
		# shellcheck disable=SC2086  # the properties are a word list on purpose
		if ! _sb_err=$(systemd-run --user --scope $SCOPE_PROPS --quiet true 2>&1 >/dev/null); then
			_sb_note "!  tests/lib.sh: the transient scope cannot open — systemd-run refused after the probe passed: ${_sb_err:-(no message)}"
			if [ -n "$NPROC_FLAG" ]; then _sb_rung=rlimit; else _sb_rung=none; fi
			_sb_note "   Running the suite under the $_sb_rung rung instead."
		fi
		;;
	esac
	[ "$_sb_rung" = scope-tasks ] &&
		_sb_note "i  tests/lib.sh: the memory controller is not delegated to the user manager on this host — the memory ceiling ($BUDGET_MEMORY MiB) is announced and not applied; the task ceiling ($BUDGET_TASKS) is"
	AGENT_SUITE_BUDGET="applied: tasks $BUDGET_TASKS, memory $BUDGET_MEMORY MiB, rung $_sb_rung"
	export AGENT_SUITE_BUDGET
	case "$_sb_rung" in
	scope | scope-tasks)
		# The wrapper inside the scope runs the suite, then reads its own
		# cgroup's counters and writes them to a file this side reads: the
		# verdict is that flag, never the suite's own status. The scope is named
		# after the suite so a stray one can be listed.
		_sb_verdict=$(mktemp) || exit 2
		trap 'rm -f "$_sb_verdict"' EXIT
		_sb_unit="suite-$(printf '%s' "${1##*/}" | sed 's/\.sh$//; s/[^A-Za-z0-9-]/-/g')-$$"
		_sb_wrap=$(
			_budget_counters_text
			cat <<'WRAP'
_own=""
while IFS= read -r _l; do case "$_l" in 0::*) _own=${_l#0::} ;; esac; done </proc/self/cgroup 2>/dev/null
_verdict=$1
shift
sh "$@"
_st=$?
_cg_counters "$_own"
printf '%s %s %s\n' "$_pm" "$_ok" "$_st" >"$_verdict"
exit "$_st"
WRAP
		)
		# shellcheck disable=SC2086  # the properties are a word list on purpose
		systemd-run --user --scope --unit="$_sb_unit" $SCOPE_PROPS --quiet sh -c "$_sb_wrap" suite-under-budget "$_sb_verdict" "$@"
		_sb_st=$?
		_sb_pm="" _sb_ok="" _sb_rest=""
		[ -f "$_sb_verdict" ] && read -r _sb_pm _sb_ok _sb_rest <"$_sb_verdict" 2>/dev/null
		# An unreadable verdict is its own outcome, said aloud, with the run's
		# status passed through — never a silent zero (ADR-0006, driver 4).
		case "$_sb_pm" in
		'') _sb_note "!  tests/lib.sh: the scope's verdict is missing — the wrapper did not survive to write it (a pressure kill takes every process in the cgroup). The budget verdict cannot be read; the run's own status ($_sb_st) passes through."; exit "$_sb_st" ;;
		-) _sb_note "!  tests/lib.sh: pids.events could not be read inside the scope. The budget verdict cannot be read; the run's own status ($_sb_st) passes through."; exit "$_sb_st" ;;
		*[!0123456789]*) _sb_note "!  tests/lib.sh: the scope's verdict is malformed ('$_sb_pm $_sb_ok $_sb_rest'). The run's own status ($_sb_st) passes through."; exit "$_sb_st" ;;
		esac
		if [ "$_sb_pm" -gt 0 ]; then
			printf '  FAIL  %s hit its TASK ceiling (%s tasks): a fork in its process tree was refused %s time(s) — whatever it printed above, it did not run whole. Exit 71 (EX_OSERR).\n' "$1" "$BUDGET_TASKS" "$_sb_pm"
			exit 71
		fi
		if [ "$_sb_rung" = scope ]; then
			case "$_sb_ok" in
			'' | -) _sb_note "!  tests/lib.sh: memory.events could not be read inside the scope. The memory verdict cannot be read; the run's own status ($_sb_st) passes through."; exit "$_sb_st" ;;
			*[!0123456789]*) _sb_note "!  tests/lib.sh: the scope's verdict is malformed ('$_sb_pm $_sb_ok $_sb_rest'). The run's own status ($_sb_st) passes through."; exit "$_sb_st" ;;
			esac
			if [ "$_sb_ok" -gt 0 ]; then
				printf '  FAIL  %s hit its MEMORY ceiling (%s MiB): a process in its tree was OOM-killed inside its cgroup %s time(s) — whatever it printed above, it did not run whole. Exit 71 (EX_OSERR).\n' "$1" "$BUDGET_MEMORY" "$_sb_ok"
				exit 71
			fi
		fi
		exit "$_sb_st"
		;;
	rlimit)
		# ulimit in the suite's own shell, before the suite: the process count
		# under the flag this sh spells it with (-u; -p on dash), the data
		# segment in KiB. Weaker, per the ADR: RLIMIT_NPROC counts the uid, and
		# RLIMIT_DATA is per process. A refused ulimit is heard, and the suite
		# still runs.
		_sb_note "i  tests/lib.sh: budget tasks $BUDGET_TASKS, memory $BUDGET_MEMORY MiB — applied by rlimits (ulimit $NPROC_FLAG, ulimit -d), the weaker rung: no user service manager answered, or it has no pids controller delegated; per process, and the task count is the user's, not the tree's. A ceiling hit on this rung shows as the shell's own error — a refused fork, a failed allocation — and the suite's own status, never a FAIL line naming the ceiling (ADR-0006 clause 6)."
		exec sh -c 'ulimit "$1" "$2" || echo "!  tests/lib.sh: ulimit $1 refused the task ceiling $2 — the rlimit rung applies no task bound" >&2
ulimit -d $(($3 * 1024)) || echo "!  tests/lib.sh: ulimit -d refused the memory ceiling $3 MiB — the rlimit rung applies no memory bound" >&2
shift 3
exec sh "$@"' suite-under-budget "$NPROC_FLAG" "$BUDGET_TASKS" "$BUDGET_MEMORY" "$@"
		;;
	*)
		_sb_note "!  tests/lib.sh: no user service manager and no rlimit on this host — the budget (tasks $BUDGET_TASKS, memory $BUDGET_MEMORY MiB) is announced and not applied. The suite runs unbounded, as before."
		exec sh "$@"
		;;
	esac
}

case "${AGENT_SUITE_BUDGET:-}" in
"applied: "*) ;;
off)
	_sb_note "!  tests/lib.sh: AGENT_SUITE_BUDGET=off — $0 runs with NO budget. A runaway suite then takes the session's whole task ceiling and memory with it."
	;;
'')
	if [ -n "${AGENT_DISPATCH_BUDGET_TASKS:-}" ]; then
		_sb_note "i  tests/lib.sh: inside a dispatched worker's budget (tasks $AGENT_DISPATCH_BUDGET_TASKS, memory ${AGENT_DISPATCH_BUDGET_MEMORY_MIB:-?} MiB) — $0 runs there and opens none of its own"
	else
		(
			_dispatch_here="$T_ROOT/scripts"
			# The kit's policy file, for the derivation only: the dispatcher's
			# policy reader takes the shell variable, and the suite must then see
			# the environment it was started with — a suite that resolves tiers
			# would otherwise resolve them through the kit's own mapping.
			_sb_cfg_was=${AGENTS_CONFIG-}
			_sb_cfg_set=${AGENTS_CONFIG+set}
			AGENTS_CONFIG="$T_ROOT/scripts/agents.kit.config.sh"
			# shellcheck disable=SC1091
			. "$T_ROOT/scripts/agent-dispatch.sh"
			# The second recursion bound, read through the dispatcher's host
			# seam so a stub suite on a fake host is judged by that host's
			# cgroup, not by the scope the suite driving it runs in.
			_sb_own=$(sed -n 's/^0:://p' "$_host/proc/self/cgroup" 2>/dev/null)
			case "$_sb_own" in
			*/suite-*.scope)
				_sb_note "x  tests/lib.sh: $0 is already inside a suite scope (${_sb_own##*/}) and AGENT_SUITE_BUDGET is not set — the marker was lost on the way in (an env -i, a wrapper that scrubs its environment?), and deriving again would open a sibling scope per run. Refused. Run the suite from outside that scope, or with AGENT_SUITE_BUDGET=off."
				exit 2
				;;
			esac
			_budget_derive
			if [ -n "$_sb_cfg_set" ]; then AGENTS_CONFIG=$_sb_cfg_was; else unset AGENTS_CONFIG; fi
			if _sb_own_bounds; then
				_sb_note "i  tests/lib.sh: already inside a bounded cgroup ($_sb_own_name: $_sb_own_limits) — a transient scope opened from here would be a sibling outside it, above its ceilings (ADR-0006 clause 7). $0 runs in place, under that cgroup's ceilings; a hit there is that cgroup's refusal, not a FAIL line from this file."
				AGENT_SUITE_BUDGET="applied: $_sb_own_limits, rung inherited"
				export AGENT_SUITE_BUDGET
				exec sh "$0" "$@"
			fi
			t_suite_under_budget "$0" "$@"
		)
		exit $?
	fi
	;;
*)
	_sb_note "x  tests/lib.sh: AGENT_SUITE_BUDGET takes 'off' or nothing, got '$AGENT_SUITE_BUDGET' — unset it to run under the budget, or set it to off to run bare"
	exit 2
	;;
esac

# --- the split-stream runner -------------------------------------------------
# The resolver's and the dispatcher's whole contract is "the answer on stdout,
# diagnostics on stderr", and a runner that merged the two could not tell a
# warning from a model id. Three suites each carried their own copy of this
# and its assertions, and the copies had drifted; agent-dispatch's
# `assert_out_lacks` even shadowed the LAST_OUT one above under the same name
# with different semantics. One copy, prefixed so it shadows nothing.
#
# t_run_split <cmd...> — run it with stdout and stderr kept apart.
# Sets S_OUT, S_ERR and S_STATUS. Needs SCRATCH (t_init).
t_run_split() {
	_rs_err=$(mktemp "$SCRATCH/err.XXXXXX") || exit 2
	S_OUT=$("$@" 2>"$_rs_err")
	S_STATUS=$?
	S_ERR=$(cat "$_rs_err")
	rm -f "$_rs_err"
}

_s_dump() {
	printf '%s\n' "$S_OUT" | sed 's/^/        > /'
	printf '%s\n' "$S_ERR" | sed 's/^/        | /'
}

# s_assert_resolved <expected stdout> <label> — status 0 AND exactly that answer.
s_assert_resolved() {
	if [ "$S_STATUS" = 0 ] && [ "$S_OUT" = "$1" ]; then
		pass "$2"
	else
		fail "$2 — expected '$1', got status $S_STATUS, stdout '$S_OUT'"
		printf '%s\n' "$S_ERR" | sed 's/^/        | /'
	fi
}

# s_assert_out_is <expected> <label> — exactly that stdout, whatever the status.
s_assert_out_is() {
	[ "$S_OUT" = "$1" ] && pass "$2" || fail "$2 — expected exactly '$1', got '$S_OUT'"
}

# s_assert_status <n> <label>
s_assert_status() {
	if [ "$S_STATUS" = "$1" ]; then
		pass "$2"
	else
		fail "$2 — expected status $1, got $S_STATUS"
		_s_dump
	fi
}

# s_assert_out_has <needle> <label>
s_assert_out_has() {
	case "$S_OUT" in
	*"$1"*) pass "$2" ;;
	*)
		fail "$2 — stdout lacks '$1'"
		printf '%s\n' "$S_OUT" | sed 's/^/        > /'
		;;
	esac
}

# s_assert_out_lacks <needle> <label>
s_assert_out_lacks() {
	case "$S_OUT" in
	*"$1"*)
		fail "$2 — stdout should NOT contain '$1'"
		printf '%s\n' "$S_OUT" | sed 's/^/        > /'
		;;
	*) pass "$2" ;;
	esac
}

# s_assert_err_has <needle> / s_assert_err_lacks <needle> — the label is the
# needle; diagnostics are what these assert on.
s_assert_err_has() {
	case "$S_ERR" in
	*"$1"*) pass "stderr mentions '$1'" ;;
	*)
		fail "stderr does not mention '$1'"
		printf '%s\n' "$S_ERR" | sed 's/^/        | /'
		;;
	esac
}
s_assert_err_lacks() {
	case "$S_ERR" in
	*"$1"*)
		fail "stderr should NOT mention '$1'"
		printf '%s\n' "$S_ERR" | sed 's/^/        | /'
		;;
	*) pass "stderr does not mention '$1'" ;;
	esac
}

# t_mark <NAME> — the double-brace placeholder mark, e.g. `t_mark PROJECT_OWNER`.
#
# Assembled from variables so no suite contains a LITERAL mark. The kit repo is
# itself bootstrapped now (docs/adr/0001-the-kit-self-hosts-its-own-constitution.md),
# so `scripts/check.sh`'s placeholder rule runs over these scripts too — and
# that rule exempts only `*.template` sources, deliberately, because a gate with
# a hole shaped like its own tooling is not a gate. check.sh spells its own
# pattern the same way, for the same reason. Suites that must PLANT a mark to
# prove the gate catches it therefore spell it rather than write it.
#
# There are three copies of this helper, and at least one of them must stay a
# copy: `mark` in `bootstrap.sh` ships into a consumer tree that has no `tests/`
# to source from, so it cannot be deduplicated into this file at any price.
# `mark` in `tests/kit-demo.sh` is the third; that suite carries its own
# assertion helpers and sources this file for the pin and the budget alone. If
# you are here to remove duplication, remove that one — never bootstrap's.
_t_ob='{'
_t_cb='}'
t_mark() { printf '%s%s%s%s%s' "$_t_ob" "$_t_ob" "$1" "$_t_cb" "$_t_cb"; }

# SUITE SCRATCH NAMES ITSELF (#221), and stale scratch is swept.
#
# A suite that hits its budget ceiling (#209) is killed before its trap runs,
# by design — so its scratch outlives it. `mktemp -d` with no template names
# that survivor `tmp.XXXXXX`, indistinguishable from every other program's,
# and the 0.20.0 wave left 83 of them on one host in a single day: nobody
# could tell which were safe to remove, so none were.
#
# scripts/agent-dispatch.sh solved exactly this one layer down (#210) and
# this is the same answer, in the same shape: a PREFIX, so what a killed run
# leaves is identifiable by name alone, and a SWEEP of what is older than a
# run could plausibly still be. The three rules of that sweep are the
# dispatcher's, and they are what make it safe on a shared /tmp: only
# directories carrying the prefix, only those older than the age, and nothing
# followed through a symlink.
#
# T_SCRATCH_SWEEP_DAYS is the age, in whole days. The default is deliberately
# generous — a suite is minutes, not days, so a day-old directory is certainly
# abandoned — and an operator who runs suites that legitimately outlive it can
# raise it in their environment.
T_SCRATCH_PREFIX=${T_SCRATCH_PREFIX:-kit-suite.}
T_SCRATCH_SWEEP_DAYS=${T_SCRATCH_SWEEP_DAYS:-1}

# t_sweep_scratch — remove suite scratch under $TMPDIR older than the sweep
# age, and say how much went. Never touches a name without the prefix.
t_sweep_scratch() {
	_ts_root=${TMPDIR:-/tmp}
	[ -d "$_ts_root" ] || return 0
	# POSIX find only, and the predicates carry the safety rather than sitting
	# beside it: `dir/.` with `! -name . -prune` is depth one; `-mtime +n` is
	# true once the whole days elapsed exceed n, so "at least N days" is
	# +(N-1); the walk is PHYSICAL (no -L, no -H) so a planted
	# `kit-suite.x -> ~` is a link and `-type d` never hands it to rm; and a
	# sibling owned by someone else fails at rm on a sticky /tmp, so -print
	# follows only a removal that worked and the count is of what actually
	# went.
	_ts_swept=$(find "$_ts_root/." ! -name . -prune -type d -name "${T_SCRATCH_PREFIX}*" \
		-mtime "+$((T_SCRATCH_SWEEP_DAYS - 1))" -exec rm -rf {} \; -print 2>/dev/null | wc -l | tr -d ' ')
	[ "${_ts_swept:-0}" -gt 0 ] &&
		echo "i  tests/lib.sh: swept $_ts_swept stale suite scratch under $_ts_root — at least $T_SCRATCH_SWEEP_DAYS day(s) old, left by suites that never reached their trap" >&2
	return 0
}

t_init() {
	t_sweep_scratch
	SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/${T_SCRATCH_PREFIX}XXXXXX") || exit 2
	trap 't_cleanup' EXIT INT TERM HUP
}

t_cleanup() { [ -n "${SCRATCH:-}" ] && rm -rf "$SCRATCH"; }

banner() { printf '\n=== %s ===\n' "$*"; }
pass() { printf '  ok    %s\n' "$*"; }
fail() {
	printf '  FAIL  %s\n' "$*"
	failures=$((failures + 1))
}

# t_repo — a fresh repo on `main` with one empty root commit.
#
# Sets the global REPO rather than echoing the path: a fixture builder that has
# to run inside `$(...)` runs in a SUBSHELL, so any sha or path it recorded on
# the way is lost to the caller. Setting globals keeps the builders composable.
t_repo() {
	REPO=$(mktemp -d "$SCRATCH/repo.XXXXXX") || exit 2
	git -C "$REPO" init -q -b main
	git -C "$REPO" config user.name "Guard Fixture"
	git -C "$REPO" config user.email "fixture@example.invalid"
	git -C "$REPO" config commit.gpgsign false
	git -C "$REPO" config core.hooksPath .git/no-such-hooks
	git -C "$REPO" commit -q --allow-empty -m "chore: root"
}

# t_write <repo> <relative-path> <contents>
t_write() {
	mkdir -p "$(dirname "$1/$2")"
	printf '%s' "$3" >"$1/$2"
}

# t_commit <repo> <subject> — stages everything and commits. Echoes the sha.
t_commit() {
	git -C "$1" add -A
	git -C "$1" commit -q --allow-empty -m "$2"
	git -C "$1" rev-parse HEAD
}

t_short() { git -C "$1" rev-parse --short "${2:-HEAD}"; }

# t_run <command...> — runs it, capturing combined output in LAST_OUT and the
# exit status in LAST_STATUS. Never fails the script itself.
t_run() {
	LAST_OUT=$("$@" 2>&1)
	LAST_STATUS=$?
	return 0
}

# assert_status <expected> <label> -- <command...>
assert_status() {
	_expected=$1
	_label=$2
	shift 3
	t_run "$@"
	if [ "$LAST_STATUS" = "$_expected" ]; then
		pass "$_label (exit $LAST_STATUS)"
	else
		fail "$_label — expected exit $_expected, got $LAST_STATUS"
		printf '%s\n' "$LAST_OUT" | sed 's/^/        | /'
	fi
}

assert_out_has() {
	case "$LAST_OUT" in
	*"$1"*) pass "output mentions '$1'" ;;
	*)
		fail "output does not mention '$1'"
		printf '%s\n' "$LAST_OUT" | sed 's/^/        | /'
		;;
	esac
}

assert_out_lacks() {
	case "$LAST_OUT" in
	*"$1"*)
		fail "output should NOT mention '$1'"
		printf '%s\n' "$LAST_OUT" | sed 's/^/        | /'
		;;
	*) pass "output does not mention '$1'" ;;
	esac
}

# assert_file_has <file> <literal> [<why>]
# assert_file_lacks <file> <literal> [<why>]
#
# Several suites in this kit assert about DOCUMENTS rather than about exit
# codes — a skill, a workflow template, a prompt. The assertion is always the
# same shape: does this file contain this literal string. `grep -F` and not a
# pattern, because the literals are real content (`--auto`, `AXIS 1 —
# STANDARDS`, `types: [opened, …]`) and regex metacharacters in them would
# silently change what is being checked.
#
# The optional third argument is the REASON the rule exists, not a replacement
# label: it is appended to both the pass and the fail line, so the output says
# why a check matters at the moment it fires — which is the only moment anyone
# reads it. A failing `lacks` also prints the offending lines with numbers,
# because "it is in there somewhere" is not an actionable failure.
assert_file_has() {
	if grep -qF -- "$2" "$1"; then
		pass "$1 says '$2'${3:+ ($3)}"
	else
		fail "$1 never says '$2'${3:+ — $3}"
	fi
}

assert_file_lacks() {
	if grep -qF -- "$2" "$1"; then
		fail "$1 contains '$2'${3:+ — $3}"
		grep -nF -- "$2" "$1" | sed 's/^/        | /'
	else
		pass "no '$2' in $1${3:+ ($3)}"
	fi
}

t_done() {
	printf '\n'
	if [ "$failures" = 0 ]; then
		printf '  ALL GREEN — %s\n' "${1:-suite}"
		exit 0
	fi
	printf '  %s assertion(s) failed — %s\n' "$failures" "${1:-suite}"
	exit 1
}

# ---------------------------------------------------------------------------
# Fixture builders — the throwaway repos every demo makes, built one way.
#
# The deliberate CONTENT SURGERY that gives a fixture its meaning (a rollback
# of a shared article, a manifest rewritten to an older release, a wave's
# additions removed) stays at the call site, between the copy and the history:
# it is the fixture's whole point, and hiding it would hide the scenario.
# These hide only what is the same every time — the copy, the identity, the
# signing switches, the tag pair.
# ---------------------------------------------------------------------------

# t_kit_tree <kit> <dest> — a .git-free copy of the kit's working tree at
# <dest>, nested worktrees stripped. The source is resolved to its physical
# path first: git reports worktrees that way, and the strip matches on the
# prefix, so a symlinked source (macOS's /var → /private/var, say) would
# otherwise keep every nested worktree in silence.
t_kit_tree() {
	_kt_src=$(cd "$1" && pwd -P) || exit 2
	mkdir -p "$2"
	cp -R "$_kt_src/." "$2/"
	strip_nested_worktrees "$_kt_src" "$2"
	rm -rf "$2/.git"
}

# t_git_identity <dir> <name> <email> — init a repo on main with a fixture
# identity, every signing switch off, and the machine's hooks out of reach,
# so a fixture commits and tags on any machine — the same neutralisation
# t_repo gives the small fixtures.
t_git_identity() {
	git -C "$1" init -q -b main
	git -C "$1" config user.name "$2"
	git -C "$1" config user.email "$3"
	git -C "$1" config commit.gpgsign false
	git -C "$1" config tag.gpgSign false
	git -C "$1" config tag.forceSignAnnotated false
	git -C "$1" config core.hooksPath .git/no-such-hooks
	# `tag.sort` is the same class of trap as the signing switches above, and it
	# bites somewhere worse: a developer with `-version:refname` set globally
	# sees `git tag --list` order the fixture's tags differently from CI, so
	# docs-demo reports UPDATING.md's pinned transcript STALE, and the honest
	# repair — re-paste what the run produced — pins the document to that one
	# machine and turns CI red for everybody else. Pinned to git's default so
	# the transcript means the same thing everywhere.
	git -C "$1" config tag.sort refname
}

# t_kit_history <hist> <old tree> <old tag> <new tree> <new tag> — one repo
# holding two releases as real tags: the old tree committed and tagged, then
# replaced wholesale by the new tree, committed and tagged. Passes or fails on
# both tags existing.
t_kit_history() {
	mkdir -p "$1"
	cp -R "$2/." "$1/"
	t_git_identity "$1" "Kit Release" "kit@example.invalid"
	git -C "$1" add -A >/dev/null
	git -C "$1" commit -q -m "release ${3#v}"
	git -C "$1" tag "$3"
	find "$1" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
	cp -R "$4/." "$1/"
	git -C "$1" add -A >/dev/null
	git -C "$1" commit -q -m "release ${5#v}"
	git -C "$1" tag "$5"
	if git -C "$1" rev-parse -q --verify "$3" >/dev/null && git -C "$1" rev-parse -q --verify "$5" >/dev/null; then
		pass "kit history built with tags $3 and $5"
	else
		fail "kit history tags were not created ($3, $5)"
	fi
}

# t_consumer_from <tree> <dest> <name> <email> [bootstrap args...] — a
# consumer bootstrapped from a kit tree: copy, identity, bootstrap with the
# given arguments, one commit. Leaves the shell in <dest>.
t_consumer_from() {
	_cf_tree=$1; _cf_dest=$2; _cf_name=$3; _cf_email=$4
	shift 4
	mkdir -p "$_cf_dest"
	cp -R "$_cf_tree/." "$_cf_dest/"
	rm -rf "$_cf_dest/.git"
	t_git_identity "$_cf_dest" "$_cf_name" "$_cf_email"
	cd "$_cf_dest" || exit 2
	sh bootstrap.sh "$@" >/dev/null 2>&1
	git add -A >/dev/null
	git commit -q -m "chore: bootstrap from agentic-sdlc"
}

# strip_nested_worktrees <src_repo> <dest_tree> — drop any git worktree that
# lives INSIDE the source repo from a tree that was just `cp -R`'d out of it.
#
# Why this exists: the kit's own convention is to develop in worktrees checked
# out under the repo, and `cp -R` takes them along. A fixture built that way is
# testing whatever a sibling branch happens to have in it — /dogfood's suite
# went red on main because an unrelated branch's checkout mentioned the command
# the suite asserts is absent. "Use this template" never hands anyone a nested
# worktree, so neither should a fixture that simulates it.
strip_nested_worktrees() {
	_swt_src=$1
	_swt_dest=$2
	git -C "$_swt_src" worktree list --porcelain 2>/dev/null |
		sed -n 's/^worktree //p' |
		while IFS= read -r _swt_path; do
			case "$_swt_path" in
			"$_swt_src") ;;
			"$_swt_src"/*) rm -rf "$_swt_dest/${_swt_path#"$_swt_src"/}" ;;
			esac
		done
}

# t_fake_host <dir> <slice pids.max> <MemAvailable kB> — the host the
# dispatcher's derivation reads through AGENT_DISPATCH_HOST_ROOT, so a suite
# asserts the arithmetic against numbers it chose: this process in
# /user.slice/user-1000.slice/session-1.scope with both controllers
# delegated, the slice carrying the task ceiling, user.slice and the scope
# carrying none, and a /proc/meminfo with that MemAvailable. Sets HOST and
# SLICE. A leg that wants another shape edits the files after — the shape is
# the fixture's point and stays at the call site, as the section header says.
t_fake_host() {
	HOST=$1
	SLICE="$HOST/sys/fs/cgroup/user.slice/user-1000.slice"
	mkdir -p "$HOST/proc/self" "$SLICE/session-1.scope"
	printf '0::/user.slice/user-1000.slice/session-1.scope\n' >"$HOST/proc/self/cgroup"
	echo max >"$HOST/sys/fs/cgroup/user.slice/pids.max"
	echo "$2" >"$SLICE/pids.max"
	echo max >"$SLICE/session-1.scope/pids.max"
	echo 'cpu memory pids' >"$SLICE/session-1.scope/cgroup.controllers"
	printf 'MemTotal:        3902724 kB\nMemFree:          200000 kB\nMemAvailable:    %s kB\n' "$3" >"$HOST/proc/meminfo"
}

# t_no_user_manager <dir> — a systemctl that fails, to put first on PATH:
# stands in for a host with no user service manager, so the budget's ladder
# falls to rlimits wherever the suite runs.
t_no_user_manager() {
	mkdir -p "$1"
	printf '#!/bin/sh\nexit 1\n' >"$1/systemctl"
	chmod +x "$1/systemctl"
}

# t_uid_tasks — how many tasks this uid runs now. RLIMIT_NPROC counts the
# uid, not the tree, so a rlimit-rung leg sets its ceiling above this number
# and lets its own forks be what cross it. `ps -o nlwp=` is procps, not
# POSIX (the same footing as setsid): where ps has no nlwp column this
# prints 0 and the leg's margin is its whole ceiling.
t_uid_tasks() { ps -u "$(id -u)" -o nlwp= 2>/dev/null | awk '{ s += $1 } END { print s + 0 }'; }

# The manifest grammar, shared with the gate and bootstrap. Sourced here so
# every suite reads VERSION one way — and asserted, so a module that loads
# and defines nothing cannot turn manifest-driven loops into no-ops.
# shellcheck disable=SC1091
. "$T_ROOT/scripts/manifest.lib.sh"
command -v manifest_section >/dev/null 2>&1 || { echo "tests/lib.sh: scripts/manifest.lib.sh did not define manifest_section" >&2; exit 2; }

# t_assert_skill_in_roster <name> — the three roster surfaces every shipped
# skill must appear on: VERSION's skills: manifest, the consumer manual
# template's quick-reference table, and the provenance file.
t_assert_skill_in_roster() {
	_sr_root="$T_ROOT"
	manifest_section skills <"$_sr_root/VERSION" | grep -qx -- "$1" &&
		pass "VERSION's skills manifest names $1" ||
		fail "VERSION's skills manifest does not name $1 — no consumer will ever be told it exists"
	grep -q "\`/$1\`" "$_sr_root/constitution/AGENTS.md.template" &&
		pass "the consumer manual template names /$1" ||
		fail "the consumer manual template never names /$1 — a stamped project cannot find it"
	grep -q -- "$1" "$_sr_root/.agents/skills/LICENSE-mattpocock-skills.md" &&
		pass "the provenance file accounts for $1" ||
		fail "the provenance file does not account for $1"
}

# t_ignored_commands — the slash commands the gate's policy file exempts from
# skill resolution (`claudeMdRefs.ignoreCommands` in config.mjs), one per line.
# Read from the file rather than mirrored: three hand-kept copies of that list
# had already drifted by the time this helper existed.
t_ignored_commands() {
	sed -n '/ignoreCommands: \[/,/\]/p' "$T_ROOT/scripts/docs-conformance/config.mjs" |
		grep -o '"/[a-z][a-z0-9-]*"' | tr -d '"'
}

# t_is_ignored_command <cmd> — true when the policy file exempts it.
t_is_ignored_command() { t_ignored_commands | grep -qx -- "$1"; }

# The skill-suite scaffold (#223): four suites had each carried a hand copy of
# the tokeniser, the command and path resolution and the model-id ban, and the
# copies had drifted — one verdict weaker than the rest, one root list missing
# a root, every root list a hand mirror of the gate's pathRoots. Held once,
# here, the same way the roster block above and the ignored commands are.

# t_skill_label <file>... — the skill name(s) a message should blame: one
# directory name per file, deduplicated, joined by "/". A pair of skills
# tested together must not report the first one's name for the second one's
# dead reference.
t_skill_label() {
	for _sl_f; do basename "$(dirname "$_sl_f")"; done | sort -u | tr '\n' '/' | sed 's|/$||'
}

# t_skill_spans <file>... — code spans outside fenced blocks, one token per
# line: the same reading tests/kit-demo.sh gives the manual, applied to a
# skill and its sidecars. A missing file is skipped, not an error, so a suite
# can list an optional sidecar.
t_skill_spans() {
	for _ss_f; do
		[ -f "$_ss_f" ] || continue
		awk '/^[ \t]*(```|~~~)/ { fence = !fence; next } !fence { print }' "$_ss_f"
	done | grep -o '`[^`]*`' | tr -d '`' | tr ' \t' '\n\n'
}

# t_skill_path_roots — the gate's pathRoots, one per line, read from the
# policy file rather than mirrored.
t_skill_path_roots() {
	sed -n '/pathRoots: \[/,/\]/p' "$T_ROOT/scripts/docs-conformance/config.mjs" |
		grep -o '"[^"]*"' | tr -d '"'
}

# t_assert_skill_commands <min> <why> <file>... — every slash command the
# files' code spans name resolves to a skill on disk (minus the gate's
# exemptions), and at least <min> do; <why> completes the fail line when fewer
# resolve ("the skill should name at least …").
t_assert_skill_commands() {
	_sc_min=$1; _sc_why=$2; shift 2
	_sc_n=0
	for _sc_cmd in $(t_skill_spans "$@" | grep '^[([{"]*/[a-z]' | grep -o '/[a-z][a-z0-9-]*' | sort -u); do
		t_is_ignored_command "$_sc_cmd" && continue
		if [ -f "$T_ROOT/.agents/skills/${_sc_cmd#/}/SKILL.md" ]; then
			_sc_n=$((_sc_n + 1))
		else
			fail "$(t_skill_label "$@") names $_sc_cmd but .agents/skills/${_sc_cmd#/}/SKILL.md does not exist"
		fi
	done
	[ "$_sc_n" -ge "$_sc_min" ] &&
		pass "all $_sc_n slash commands in $(t_skill_label "$@") resolve" ||
		fail "only $_sc_n commands resolved — $_sc_why"
}

# t_skill_path_verdict <path> <file>... — why a repo path a skill names is not
# a dead reference: it exists in this tree, ships as a template, is a
# workflow bootstrap copies from templates/workflows/, is created by bootstrap
# (a line that creates or copies it — the KIT_ONLY deletion list and comments
# prove the opposite), or the skill names it conditionally
# ("when … exist"). Prints the verdict; returns 1 with nothing when none holds.
t_skill_path_verdict() {
	_pv_p=$1; shift
	[ -e "$T_ROOT/$_pv_p" ] && { echo "exists in this tree"; return 0; }
	[ -e "$T_ROOT/$_pv_p.template" ] && { echo "shipped as $_pv_p.template"; return 0; }
	# bootstrap copies templates/workflows/* into .github/workflows/ by a loop
	# that never names the file, so the copy source is the verdict.
	case "$_pv_p" in .github/workflows/*)
		[ -e "$T_ROOT/templates/workflows/$(basename "$_pv_p")" ] &&
			{ echo "copied from templates/workflows/ by bootstrap.sh"; return 0; } ;;
	esac
	grep -F -- "$_pv_p" "$T_ROOT/bootstrap.sh" | grep -v '^[[:space:]]*#' | grep -v '^KIT_ONLY=' |
		grep -Eq '(cp|mkdir|ln|stamp|printf|>|install)' &&
		{ echo "installed by bootstrap.sh"; return 0; }
	grep -F -- "$_pv_p" "$@" 2>/dev/null | grep -qi 'when .*exist' && { echo "named conditionally"; return 0; }
	return 1
}

# t_assert_skill_paths <min> <why> <file>... — every repo path under one of
# the gate's roots that the files' code spans name has a verdict, and at least
# <min> were checked; <why> completes the fail line when fewer were.
t_assert_skill_paths() {
	_sp_min=$1; _sp_why=$2; shift 2
	_sp_roots=$(t_skill_path_roots)
	_sp_n=0
	for _sp_tok in $(t_skill_spans "$@" | sed 's/[),.;:]*$//' | grep -v '[<>*$]' | grep '/' | sort -u); do
		_sp_hit=0
		for _sp_root in $_sp_roots; do
			case "$_sp_tok" in "$_sp_root"/*) _sp_hit=1; break ;; esac
		done
		[ "$_sp_hit" = 1 ] || continue
		_sp_n=$((_sp_n + 1))
		if _sp_why_ok=$(t_skill_path_verdict "$_sp_tok" "$@"); then
			pass "$_sp_tok — $_sp_why_ok"
		else
			fail "$_sp_tok is named by $(t_skill_label "$@") but resolves to nothing, in this tree or a bootstrapped one"
		fi
	done
	[ "$_sp_n" -ge "$_sp_min" ] && pass "$_sp_n repo paths checked" ||
		fail "only $_sp_n repo paths found — $_sp_why"
}

# t_assert_no_model_id <file>... — no model identifier anywhere: the tier
# resolves the model, and a skill or a ticket outlives the id.
t_assert_no_model_id() {
	if grep -Eiq 'claude-[a-z]+-[0-9]|gpt-[0-9]|gemini-[0-9]|\b(opus|sonnet|haiku) [0-9]' "$@"; then
		fail "$(t_skill_label "$@") names a model identifier — the tier resolves the model, a ticket outlives the id"
	else
		pass "no model identifier in $(t_skill_label "$@")"
	fi
}

# t_assert_skill_frontmatter <skill dir> — the Agent Skills specification's
# frontmatter rules, held once for every skill suite: keys limited to the
# fields the specification defines (any case — an unexpected key is a finding
# whatever its case), name equal to the directory, description under 1024
# characters read to the next key, the body under 500 lines, supporting files
# one level deep.
t_assert_skill_frontmatter() {
	_sf_dir=$1
	_sf_file="$_sf_dir/SKILL.md"
	_sf_keys=$(awk 'NR == 1 { next } /^---/ { exit } /^[A-Za-z0-9_-]+:/ { sub(/:.*/, ""); print tolower($0) }' "$_sf_file")
	for _sf_k in $_sf_keys; do
		case "$_sf_k" in
		name | description | license | compatibility | metadata | allowed-tools) ;;
		*) fail "$_sf_file: frontmatter key '$_sf_k' is not one the Agent Skills specification defines — the kit ships vendor-neutral skills" ;;
		esac
	done
	printf '%s\n' "$_sf_keys" | grep -qx name && pass "$_sf_file carries name" || fail "$_sf_file lacks name"
	printf '%s\n' "$_sf_keys" | grep -qx description && pass "$_sf_file carries description" || fail "$_sf_file lacks description"
	_sf_name=$(awk 'NR == 1 { next } /^---/ { exit } /^name:/ { sub(/^name: */, ""); print; exit }' "$_sf_file")
	[ "$_sf_name" = "$(basename "$_sf_dir")" ] && pass "frontmatter name equals the directory name" ||
		fail "frontmatter name '$_sf_name' is not the directory name"
	_sf_desc=$(awk 'NR == 1 { next } /^---/ { exit } /^[A-Za-z0-9_-]+:/ { indesc = ($0 ~ /^description:/); if (indesc) { sub(/^description: */, ""); n += length($0) } ; next } indesc { n += length($0) + 1 } END { print n + 0 }' "$_sf_file")
	[ "${_sf_desc:-0}" -le 1024 ] && pass "description is $_sf_desc chars, within the specification's 1024" ||
		fail "description is $_sf_desc chars — the specification caps it at 1024"
	_sf_lines=$(wc -l <"$_sf_file" | tr -d ' ')
	[ "$_sf_lines" -le 500 ] && pass "SKILL.md is $_sf_lines lines, under the 500 the specification recommends" ||
		fail "SKILL.md is $_sf_lines lines — over the 500 the specification recommends; move reference material to a sidecar"
	_sf_deep=$(find "$_sf_dir" -mindepth 2 -type f | head -1)
	[ -z "$_sf_deep" ] && pass "supporting files are one level deep" || fail "a supporting file is nested deeper than one level: $_sf_deep"
}

