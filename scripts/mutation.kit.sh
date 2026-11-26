#!/bin/sh
# scripts/mutation.kit.sh — the KIT'S OWN mutation measurement. Not shipped.
#
# Shared invariant §9: green is a claim, not a measurement. The kit asks every
# consumer to decide how its pure, cheap layer is measured and to say so in
# the engineering article. The kit has no such article, so this file and the
# diary entry that records the baseline are its decision: the validators
# under scripts/docs-conformance/validators/ are measured with Stryker, on
# demand, never as a gate, against the fixture tests that are their target
# function.
#
# Kit-only: bootstrap.sh's KIT_ONLY list deletes this file and its config at
# stamp time, the same way it deletes tests/. A consumer's measurement is the
# consumer's decision; adapters/node-ts/ holds a worked wiring to copy.
#
# The tool arrives through npx on demand, PINNED to one version below. The
# kit commits no package manifest and takes no dependency — the harness stays
# dependency-free ESM — but a baseline measured against whatever the registry
# serves that day is not a ceiling (§9), and an unpinned fetch executes
# whatever "latest" means with the operator's privileges. Bump the pin and
# re-measure together. The config is JSON rather than the .mjs the adapter's
# example uses because a second executable module in the kit's tree would
# need its own exemption from the gate's policy; JSON carries no reasoning,
# so the reasoning lives here.
#
# Where it runs. Stryker's sandbox copy fails on the kit's per-skill symlinks,
# so the config runs it in place (`inPlace`): it backs up the files it
# mutates to .stryker-tmp, mutates them in the tree and restores them at the
# end. An interrupted run skips that restore, and a second signal while
# Stryker shuts down skips it too ("Forced exit. Received signal again") —
# npx forwards SIGINT/SIGTERM to Stryker, so one Ctrl-C arrives twice. So the
# wrapper never lets Stryker near the caller's tree: it adds a detached
# worktree of HEAD under TMPDIR, runs there, and removes it after a
# successful run. Uncommitted edits are therefore not measured. A failed,
# interrupted or paused run keeps the worktree for inspection and prints the
# one command that removes it; the caller's tree is clean whatever happened.
# The config's `disableTypeChecks: false` keeps Stryker from rewriting every
# .mjs under lib/src/test with a `// @ts-nocheck` line — the kit type-checks
# nothing, and that preprocessor was what touched 43 files outside the
# mutate scope on a two-file run (2026-11-24) and dropped an executable bit.
#
# A host that sleeps voids the run. Stryker times a mutant on the wall clock
# (60 s plus 1.5 x the suite's time), and on macOS node's clock keeps counting
# while the host sleeps: every sleep longer than that times out each mutant in
# flight, one per concurrent runner, and Stryker counts a timeout as killed.
# The 2026-11-21 run went into clamshell sleep 6 minutes in and was asleep
# 97 % of its 35.6 hours; its 547 timeouts against 133 sleeps of a minute or
# more is about 4 a sleep, its concurrency (#507). So the wrapper keeps a
# heartbeat, and a gap of PAUSE_SECONDS or more between two beats stops the
# run with exit 3: its score would count the pause as kills. Keep the lid
# open, on power, or prefix `caffeinate -i` against idle sleep on macOS.
#
# Keep the config's commandRunner in step with kit-ci.yml's harness job: JSON
# cannot source anything, so the suite line is spelled twice.
#
# Usage: sh scripts/mutation.kit.sh            # about 90 minutes on a laptop
#                                               (1,651 mutants at 2521ada8;
#                                               extrapolated from 57 mutants
#                                               in 181 s, 2026-11-24); runs
#                                               in a throwaway worktree of
#                                               HEAD, network required
#        sh scripts/mutation.kit.sh --dry-run  # print what would run
#
# Exit: Stryker's own; 2 on a usage error or when this is not the kit; 3 when
# the host paused the run; 128 + n when signal n interrupted it.

set -u

[ $# -le 1 ] || {
	echo "mutation.kit.sh: too many arguments (expected --dry-run or nothing)" >&2
	exit 2
}
case "${1:-}" in
--dry-run | "") ;;
*)
	echo "mutation.kit.sh: unknown argument '$1' (expected --dry-run)" >&2
	exit 2
	;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
	echo "mutation.kit.sh: not inside a git repository" >&2
	exit 2
}
cd "$root" || exit 2
[ -f VERSION ] && [ -d scripts/docs-conformance/validators ] || {
	echo "mutation.kit.sh: $root is not the kit — no VERSION, or no validators to mutate" >&2
	exit 2
}

CONFIG=scripts/mutation.kit.config.json
STRYKER_VERSION=10.0.0
CMD="npx --yes -p @stryker-mutator/core@$STRYKER_VERSION stryker run $CONFIG"

if [ "${1:-}" = "--dry-run" ]; then
	echo "$CMD"
	exit 0
fi

PAUSE_SECONDS=30

# Every process below the given one, parents first, so a parent killed first
# cannot start a replacement child.
descendants() {
	ps -A -o pid= -o ppid= | awk -v root="$1" '
		{ kids[$2] = kids[$2] " " $1 }
		END { q = root; while (q != "") { n = split(q, a, " "); q = "";
			for (i = 1; i <= n; i++) { if (a[i] != root) print a[i]; q = q kids[a[i]] } } }'
}

tmp=${TMPDIR:-/tmp}
base=$(mktemp -d "${tmp%/}/kit-mutation.XXXXXX") || exit 2
work="$base/run"
git worktree add --detach -q "$work" HEAD || { rm -rf "$base"; exit 2; }
recover="git -C '$root' worktree remove --force '$work' && rm -rf '$base'"
keep() {
	echo "mutation.kit.sh: $1; the run's worktree is kept at $work" >&2
	echo "mutation.kit.sh: remove it with: $recover" >&2
}
echo "mutation.kit.sh: measuring HEAD $(git rev-parse --short HEAD) in $work (uncommitted edits are not measured)" >&2

(cd "$work" && exec $CMD) </dev/null &
pid=$!
stop() {
	for p in $pid $(descendants "$pid"); do kill -KILL "$p" 2>/dev/null; done
	wait "$pid" 2>/dev/null
}
trap 'stop; keep "interrupted"; exit 130' INT
trap 'stop; keep "interrupted"; exit 143' TERM
trap 'stop; keep "interrupted"; exit 129' HUP

last=$(date +%s)
while kill -0 "$pid" 2>/dev/null; do
	sleep 1 &
	wait $!
	now=$(date +%s)
	if [ $((now - last)) -ge "$PAUSE_SECONDS" ]; then
		stop
		keep "the host paused this run for $((now - last)) s (asleep, or stopped); every mutant in flight timed out and counts as killed, so its score is void"
		exit 3
	fi
	last=$now
done
wait "$pid"
status=$?
trap - INT TERM HUP

if [ "$status" -eq 0 ]; then
	git worktree remove --force "$work" && rm -rf "$base"
else
	keep "Stryker exited $status"
fi
exit "$status"
