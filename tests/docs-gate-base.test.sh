#!/bin/sh
# tests/docs-gate-base.test.sh — the docs gate is judged by the BASE's config.
#
# A pull request that adds a violation and, in the same diff, the config edit
# that exempts it must still fail: with POLICY_BASE naming a ref, the gate
# reads scripts/docs-conformance/config.mjs (and the local-vocabulary module
# beside it) as that ref has it, through scripts/policy.sh — in its full form
# and in its reduced POSIX form — and fails closed when the base has no
# readable config (the kit's ADR-0039; docs/specs/policy.md R22 to R25).
#
# Every case runs in a project bootstrapped from this tree, with a `main` and
# a branch, and asserts the exit and the exact fail-closed line.
#
# Usage: sh tests/docs-gate-base.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

KIT="$ROOT"
CFG=scripts/docs-conformance/config.mjs
VOC=scripts/docs-conformance/local-vocabulary.mjs
INV=constitution/shared-invariants.md
_ob='$'
_ob="$_ob{{"
# The fixture's requirement area, spelled in two halves: bootstrap copies this
# suite into the project, and a literal citation here would cite it there.
AREA=gate
AREA="${AREA}demo"

have_node=0
command -v node >/dev/null 2>&1 && have_node=1

gate_node() { sh scripts/check.sh; }
gate_posix() { DOCS_CHECK_NO_NODE=1 sh scripts/check.sh; }
harness() { node scripts/docs-conformance/index.mjs .; }

banner "0. A bootstrapped project, green on main"
t_kit_tree "$KIT" "$SCRATCH/kit"
t_consumer_from "$SCRATCH/kit" "$SCRATCH/proj" "Base Suite" "suite@example.invalid" \
	--no-dogfood "Zorblax Demo" "A throwaway to prove the gate reads the base's config."
# Bootstrap wires the project's own hooks; this suite's commits are the
# fixture's history, made as a consumer's human would make them.
git config core.hooksPath .git/no-such-hooks
t_as_human
grep -q 'Zorblax Demo' "$VOC" &&
	pass "bootstrap stamped the project name into the local vocabulary" ||
	fail "the fixture degraded — no project name in $VOC"
expect_exit 0 "the reduced form is green on main" -- gate_posix
if [ "$have_node" = 1 ]; then
	expect_exit 0 "the full form is green on main" -- gate_node
fi
MAIN=$(git rev-parse HEAD)

# ---------------------------------------------------------------------------
banner "1. A PR exempts its own violation in the gate config (policy/R22, policy/R16)"
# ---------------------------------------------------------------------------
# Two violations, each exempted by the same PR's config: a living requirement
# named only by a file the PR adds to the test globs (both forms see it), and
# the project's own name in the shared article with the local vocabulary
# dropped from the portability deny-list (the full form sees it).
git checkout -q -b pr-config
mkdir -p docs/specs notes
printf '# Demo\n\nR1. The demo SHALL hold.\n' >"docs/specs/$AREA.md"
printf '%s/R1 is named here, and nothing runs this file.\n' "$AREA" >notes/demo.txt
sed -i.bak 's#^\([[:space:]]*\)"tests/\*",$#\1"tests/*",\n\1"notes/*",#' "$CFG" && rm "$CFG.bak"
sed -i.bak '/\.\.\.localVocabulary\.map(denyEntryFromTerms),/d' "$CFG" && rm "$CFG.bak"
printf '\nZorblax Demo was here.\n' >>"$INV"
grep -q '"notes/\*",' "$CFG" && ! grep -q 'localVocabulary.map' "$CFG" &&
	pass "the PR's config carries both exemptions" ||
	fail "the fixture degraded — the PR's config does not carry both exemptions"
git add -A && git commit -q -m "docs: a requirement and a name, exempted by the PR's own config"

expect_exit 0 "unset, the reduced form reads the working tree's config and passes (policy/R16)" -- gate_posix
expect_exit 1 "POLICY_BASE=main, the reduced form reads main's test globs and fails (policy/R22)" -- \
	env POLICY_BASE=main sh -c 'DOCS_CHECK_NO_NODE=1 sh scripts/check.sh'
expect_said "$AREA/R1"
if [ "$have_node" = 1 ]; then
	expect_exit 0 "unset, the full form passes on the PR's own config (policy/R16)" -- gate_node
	expect_exit 1 "POLICY_BASE=main, the full form loads main's config and fails (policy/R22)" -- \
		env POLICY_BASE=main sh scripts/check.sh
	expect_said "$AREA/R1"
	expect_said "product-name"
	expect_exit 1 "POLICY_BASE=main, the harness run directly fails too (policy/R22)" -- \
		env POLICY_BASE=main node scripts/docs-conformance/index.mjs .
	expect_said "product-name"
else
	note "node is absent — the full form's legs of policy/R22 did not run here"
fi

# ---------------------------------------------------------------------------
banner "2. A PR empties the local vocabulary to pass its own leak (policy/R22)"
# ---------------------------------------------------------------------------
git checkout -q -b pr-vocab main
sed -i.bak 's/"Zorblax Demo"//' "$VOC" && rm "$VOC.bak"
printf '\nZorblax Demo was here.\n' >>"$INV"
git add -A && git commit -q -m "docs: a name, exempted by the PR's own vocabulary"
if [ "$have_node" = 1 ]; then
	expect_exit 0 "unset, the PR's emptied vocabulary lets the name through" -- gate_node
	expect_exit 1 "POLICY_BASE=main, the gate loads main's local vocabulary and fails" -- \
		env POLICY_BASE=main sh scripts/check.sh
	expect_said "product-name"
else
	note "node is absent — the local vocabulary is a full-form rule"
fi

# ---------------------------------------------------------------------------
banner "3. main has no local-vocabulary module: an empty vocabulary (policy/R24)"
# ---------------------------------------------------------------------------
git checkout -q main
git rm -q "$VOC" && git commit -q -m "chore: no local vocabulary"
NOVOC=$(git rev-parse HEAD)
git checkout -q -b pr-novocab
printf 'export default [{ id: "quux", terms: ["Quuxly"], reason: "a branch-only word" }];\n' >"$VOC"
printf '\nQuuxly was here.\n' >>"$INV"
git add -A && git commit -q -m "docs: a word the branch's own vocabulary bans"
if [ "$have_node" = 1 ]; then
	expect_exit 1 "unset, the branch's own vocabulary bans the word" -- gate_node
	expect_said "Quuxly"
	expect_exit 0 "POLICY_BASE at a main with no module reads an empty vocabulary, as today" -- \
		env POLICY_BASE="$NOVOC" sh scripts/check.sh
	expect_unsaid "Quuxly"
	expect_unsaid "fail-closed"
else
	note "node is absent — the local vocabulary is a full-form rule"
fi

# ---------------------------------------------------------------------------
banner "4. main has no gate config: fail closed, no validator (policy/R23)"
# ---------------------------------------------------------------------------
git checkout -q -b main-nocfg "$MAIN"
git rm -q "$CFG" && git commit -q -m "chore: no gate config"
NOCFG=$(git rev-parse HEAD)
git checkout -q pr-config
for form in posix node harness; do
	case $form in
	posix) run() { env POLICY_BASE="$NOCFG" DOCS_CHECK_NO_NODE=1 sh scripts/check.sh; } ;;
	node) run() { env POLICY_BASE="$NOCFG" sh scripts/check.sh; } ;;
	harness) run() { env POLICY_BASE="$NOCFG" node scripts/docs-conformance/index.mjs .; } ;;
	esac
	if [ "$form" != posix ] && [ "$have_node" = 0 ]; then
		note "node is absent — the $form leg of policy/R23 did not run here"
		continue
	fi
	expect_exit 1 "$form: a base with no gate config exits 1" -- run
	expect_said "fail-closed missing $CFG"
	expect_unsaid "$AREA/R1" "$form: no validator ran — the requirement went unjudged"
	expect_unsaid "OK  docs" "$form: nothing reports a pass"
	expect_unsaid "NOTICE" "$form: the reduced form never started"
done

expect_exit 1 "an unfetched base fails closed too, never falls back to the working tree" -- \
	env POLICY_BASE=no-such-ref DOCS_CHECK_NO_NODE=1 sh scripts/check.sh
expect_said "fail-closed no-base $CFG"
if [ "$have_node" = 1 ]; then
	expect_exit 1 "…and the harness run directly says the same" -- \
		env POLICY_BASE=no-such-ref node scripts/docs-conformance/index.mjs .
	expect_said "fail-closed no-base $CFG"
fi

# ---------------------------------------------------------------------------
banner "5. The workflows set POLICY_BASE from the PR's base commit, fetched (policy/R25)"
# ---------------------------------------------------------------------------
# job_text <workflow> <job id> — the job's block, from its id to the next.
job_text() {
	awk -v id="  $2:" '$0 == id { on = 1; print; next } on && /^  [A-Za-z0-9_-]+:$/ { exit } on { print }' "$1"
}
# holds <workflow> <job id> <run line> — the job fetches full history and the
# step running <run line> carries POLICY_BASE from the PR's base commit.
holds() {
	_h_job=$(job_text "$1" "$2")
	_h_step=$(printf '%s\n' "$_h_job" | awk -v run="$3" '/- name:/ { buf = "" } { buf = buf $0 "\n" } index($0, run) { printf "%s", buf; exit }')
	case $_h_step in
	*"POLICY_BASE: $_ob github.event.pull_request.base.sha }}"*)
		pass "policy/R25: $(basename "$1") job $2 sets POLICY_BASE on the step running '$3'" ;;
	*) fail "policy/R25: $(basename "$1") job $2 — the step running '$3' does not set POLICY_BASE from github.event.pull_request.base.sha" ;;
	esac
	case $_h_job in
	*"fetch-depth: 0"*) pass "policy/R25: $(basename "$1") job $2 holds the base commit (fetch-depth: 0)" ;;
	*) fail "policy/R25: $(basename "$1") job $2 checks out too shallow to hold the base commit" ;;
	esac
}
holds "$KIT/templates/workflows/docs-gate.yml" docs-gate "sh scripts/check.sh"
holds "$KIT/.github/workflows/kit-ci.yml" portability "node scripts/docs-conformance/index.mjs ."
holds "$KIT/.github/workflows/kit-ci.yml" self-host "sh scripts/check.sh"

t_done "docs gate judged by the base"
