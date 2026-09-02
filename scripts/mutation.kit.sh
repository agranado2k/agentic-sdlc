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
# In-place mode (the config's `inPlace`) exists because Stryker's sandbox copy
# fails on the kit's per-skill symlinks. In place, Stryker backs the files it
# mutates up to .stryker-tmp, mutates them in the tree, and restores them at
# the end. Two consequences:
#   - until that restore has happened the backup is the only copy of the
#     originals, so this wrapper never deletes .stryker-tmp: Stryker removes
#     it after a successful run, and after a failed one the wrapper names it
#     as the recovery copy instead;
#   - a restore rewrites content, not mode. One early run was seen to leave a
#     file without its executable bit (which file was not recorded, and
#     nothing in the mutate scope is executable today — so the guard is a
#     belt over a buckle): any `100755 => 100644` drift left after the run
#     gets its bit back with chmod, which touches no content, and is reported.
#
# Keep the config's commandRunner in step with kit-ci.yml's harness job: JSON
# cannot source anything, so the suite line is spelled twice.
#
# Usage: sh scripts/mutation.kit.sh            # ~8 minutes on a laptop; runs
#                                               IN PLACE — clean validators
#                                               tree, network required
#        sh scripts/mutation.kit.sh --dry-run  # print what would run
#
# Exit: Stryker's own; 2 on a usage error or when this is not the kit.

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

$CMD
status=$?

# Give back any executable bit the in-place restore dropped, loudly, and
# never touch content. --raw -z: one NUL-terminated meta record then one path
# record per entry, so a path with a space survives.
git diff --raw -z -- . 2>/dev/null | tr '\0' '\n' |
	awk 'NR % 2 == 1 { meta = $0; next } meta ~ /^:100755 100644 / { print }' |
	while IFS= read -r f; do
		chmod +x "$f" && echo "mutation.kit.sh: restored the executable bit on $f (the in-place run dropped it)" >&2
	done

# Content is never touched: a validator that still differs from the index
# after the run is a restore that did not happen, and the operator needs to
# see it, not have it silently reverted.
if ! git diff --quiet -- scripts/docs-conformance 2>/dev/null; then
	echo "mutation.kit.sh: scripts/docs-conformance differs from the index after the run — a restore may have failed; inspect before committing" >&2
fi

if [ "$status" -ne 0 ] && [ -d .stryker-tmp ]; then
	echo "mutation.kit.sh: Stryker exited $status; .stryker-tmp is its backup of the originals — check the tree before removing it" >&2
fi

exit "$status"
