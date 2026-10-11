#!/bin/sh
# tests/harness-fixture-cleanup.test.sh — a full docs-harness run leaves the
# temp directory as it found it.
#
# The harness's fixture helper makes a docs-conf-* temp directory per fixture.
# Left to each test to clean up, they piled up: 29,378 of them in /tmp on
# 2026-10-10, until the per-user quota stopped a release's transcript
# re-capture (#731). The helper now removes every fixture a test file made when
# that file finishes. This suite runs the whole harness with a private TMPDIR
# and counts what is left, then runs a copy of it with the helper's after-hook
# disabled to prove the count can go red. The single-file case — a test that
# fails before its own cleanup — is the harness's own fixture-cleanup.test.mjs.
#
# Usage: sh tests/harness-fixture-cleanup.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

# leftovers <dir> — how many docs-conf-* entries <dir> holds.
leftovers() { find "$1" -mindepth 1 -maxdepth 1 -name 'docs-conf-*' | wc -l | tr -d ' '; }
# harness <conformance dir> <tmpdir> — run every fixture test under <dir> with
# <tmpdir> as the only temp directory; print node's exit status.
harness() {
	(cd "$1" && TMPDIR=$2 TMP=$2 TEMP=$2 node --test test/*.test.mjs >"$2.log" 2>&1)
	echo $?
}

if ! command -v node >/dev/null 2>&1; then
	banner "node is not on PATH"
	skip "the docs harness needs node; nothing here can run"
	t_done "harness fixture cleanup"
fi

# ---------------------------------------------------------------------------
banner "1. the full harness run leaves the docs-conf-* count unchanged"
# ---------------------------------------------------------------------------
TMP1="$SCRATCH/tmp-full"
mkdir -p "$TMP1"
before=$(leftovers "$TMP1")
status=$(harness "$ROOT/scripts/docs-conformance" "$TMP1")
[ "$status" = 0 ] && pass "the harness passes" || fail "the harness exited $status — see $(tail -20 "$TMP1.log" | tr '\n' '|')"
after=$(leftovers "$TMP1")
[ "$after" = "$before" ] && pass "docs-conf-* count unchanged ($before before, $after after)" ||
	fail "the harness left $((after - before)) docs-conf-* directories behind"

# ---------------------------------------------------------------------------
banner "2. the count goes red when the helper's after-hook is gone"
# ---------------------------------------------------------------------------
COPY="$SCRATCH/docs-conformance"
cp -R "$ROOT/scripts/docs-conformance" "$COPY"
# The hook becomes an immediately-run function: the registry is emptied once
# at import, before any fixture exists, and never again.
sed 's/^after(() => {$/(() => {/; s/^});$/})();/' "$ROOT/scripts/docs-conformance/test/helpers.mjs" >"$COPY/test/helpers.mjs"
if grep -q '^after(' "$COPY/test/helpers.mjs"; then
	fail "the after-hook survived the surgery; the red case proves nothing"
else
	TMP2="$SCRATCH/tmp-nohook"
	mkdir -p "$TMP2"
	harness "$COPY" "$TMP2" >/dev/null
	left=$(leftovers "$TMP2")
	[ "$left" -gt 0 ] && pass "without the hook the run leaves $left docs-conf-* directories, and the count sees them" ||
		fail "without the hook nothing leaked — the count cannot tell the hook is there"
fi

t_done "harness fixture cleanup"
