#!/bin/sh
# scripts/mutation.kit.sh — the KIT'S OWN mutation measurement. Not shipped.
#
# Shared invariant §9: green is a claim, not a measurement. The kit asks every
# consumer to decide how its pure, cheap layer is measured and to say so in
# the engineering article. The kit has no such article, so this file and the
# diary entry that records the baseline are its decision: the seven
# validators under scripts/docs-conformance/validators/ are measured with
# Stryker, on demand, never as a gate, against the fixture tests that are
# their target function.
#
# Kit-only: bootstrap.sh's KIT_ONLY list deletes this file and its config at
# stamp time, the same way it deletes tests/. A consumer's measurement is the
# consumer's decision; adapters/node-ts/ holds a worked wiring to copy.
#
# The tool arrives through npx on demand — the kit commits no package
# manifest and takes no dependency; the harness stays dependency-free ESM.
#
# In-place mode (the config's `inPlace`) exists because Stryker's sandbox copy
# fails on the kit's per-skill symlinks. In place, Stryker backs up, mutates
# and restores the mutated files — and one run was observed to restore a
# file's content and lose its executable bit. The guard below checks the
# tree's mode bits after the run and restores any that drifted, loudly.
#
# Usage: sh scripts/mutation.kit.sh            # ~8 minutes on a laptop
#        sh scripts/mutation.kit.sh --dry-run  # print what would run
#
# Exit: Stryker's own; 2 when run from outside the kit root.

set -u

[ -f VERSION ] && [ -d scripts/docs-conformance/validators ] || {
	echo "mutation.kit.sh: run from the kit root" >&2
	exit 2
}

CONFIG=scripts/mutation.kit.config.json
CMD="npx --yes -p @stryker-mutator/core stryker run $CONFIG"

if [ "${1:-}" = "--dry-run" ]; then
	echo "$CMD"
	exit 0
fi

before=$(git diff --name-only 2>/dev/null)
$CMD
status=$?

# Restore any mode-only drift the in-place run left behind, and say so.
drifted=$(git diff --name-only 2>/dev/null | grep -vxF "$before" || true)
for f in $drifted; do
	if git diff --quiet -- "$f" 2>/dev/null; then
		continue
	fi
	if git diff -- "$f" | grep -q '^old mode'; then
		git checkout -- "$f" && echo "mutation.kit.sh: restored the mode of $f (in-place run dropped it)" >&2
	else
		echo "mutation.kit.sh: $f changed content during the run — inspect before committing" >&2
	fi
done
rm -rf .stryker-tmp

exit "$status"
