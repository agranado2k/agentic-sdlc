#!/bin/sh
# tests/docs-gate-advisory.test.sh — an advisory is VISIBLE through the gate.
#
# The docs gate has a warning channel since 0.11.0: a validator may report a
# finding with severity "warning", the harness prints it and still exits 0.
# Every advisory the kit ships (the glossary's **Advisory** entry is the
# roster) rides that channel, and every release note
# since has said "prints a warning, never a failure".
#
# What nothing checked, found by running ticket #108's demo by hand: the
# operator never runs the harness. They run `sh scripts/check.sh` — the hook
# does, CI does — and the wrapper captured the harness's output and relayed it
# ONLY on a non-zero status. A green gate swallowed every advisory, so the
# channel was a claim (shared invariant §8): a warning nobody could see is
# silence with a longer name. This suite drives that path through the same
# entry point the hook uses, on a project bootstrapped from this tree.
#
# Usage: sh tests/docs-gate-advisory.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

KIT="$ROOT"
PROJ="$SCRATCH/proj"

# A project from this tree, bootstrapped, with the engineering article stamped
# and its Architecture section left without a single anchor — the shape the
# design-brief advisory names.
banner "0. A bootstrapped project whose engineering article records no design brief"
mkdir -p "$PROJ"
cp -R "$KIT/." "$PROJ/"
strip_nested_worktrees "$KIT" "$PROJ"
rm -rf "$PROJ/.git"
cd "$PROJ" || exit 2
git init -q -b main
git config user.name "Advisory Suite"
git config user.email "suite@example.invalid"
git config commit.gpgsign false
sh bootstrap.sh --no-dogfood "Advisory Demo" "A throwaway to prove the warning channel is audible." >/dev/null 2>&1 ||
	{ fail "bootstrap did not run"; t_done "docs gate advisory visibility"; }

# Stamp the article: drop the template's header comment (it quotes an example
# path the gate would resolve), fill every mark, remove the three anchors.
awk 'BEGIN { skip = 1 } skip && /^-->/ { skip = 0; next } !skip' \
	constitution/local-engineering.md.template >"$SCRATCH/article.stripped" || { fail "awk could not strip the header comment"; t_done "docs gate advisory visibility"; }
sed -e '/^\*\*Paradigm\*\*:/d' -e '/^\*\*Architectural style\*\*:/d' -e '/^\*\*Context map\*\*:/d' \
	-e "s/$(t_mark '[A-Z_0-9]*')/filled/g" "$SCRATCH/article.stripped" >constitution/local-engineering.md || { fail "sed could not stamp the article"; t_done "docs gate advisory visibility"; }
rm constitution/local-engineering.md.template
sed -i.bak 's#`constitution/local-engineering.md.template`#`constitution/local-engineering.md`#' AGENTS.md && rm AGENTS.md.bak
# Positive shape first: a degenerate (empty) article would also trip the
# advisory, so prove the fixture is a real stamped article — the mutation
# anchor survived, filled — before proving what it lacks.
grep -q '^\*\*Mutation decision\*\*: filled' constitution/local-engineering.md &&
	pass "the stamped article is real — the mutation anchor survived the stamp, filled" ||
	fail "the fixture degraded — no filled mutation anchor, so this is not a stamped article"
for anchor in 'Paradigm' 'Architectural style' 'Context map'; do
	grep -q "^\*\*$anchor\*\*:" constitution/local-engineering.md &&
		fail "the fixture still carries the $anchor anchor — it cannot drive the advisory" ||
		pass "the stamped article carries no $anchor anchor"
done

banner "1. The harness reports the advisory and exits 0 — the channel itself works"
assert_status 0 "the harness exits 0 on a warning-only tree" -- node scripts/docs-conformance/index.mjs .
assert_out_has "design-brief-missing"

banner "2. The SAME finding is visible through scripts/check.sh — the entry point the hook runs"
assert_status 0 "the gate exits 0 — an advisory never fails a push" -- sh scripts/check.sh
assert_out_has "design-brief-missing"
assert_out_has "OK  docs gate"

banner "3. A tree with nothing to advise prints no advisory block — the relay is not noise"
printf '\n**Paradigm**: functional — pure domain, classes only at the adapters.\n' >>constitution/local-engineering.md
assert_status 0 "the gate is green once one anchor is filled" -- sh scripts/check.sh
assert_out_lacks "design-brief-missing"
assert_out_lacks "advisories"
# The probe that tells "relay advisories" from "relay everything": on a clean
# tree the harness still prints its own OK line, and an unconditional relay
# would echo it here.
assert_out_lacks "docs conformance"

banner "4. The reduced POSIX form says it cannot run this scan"
DOCS_CHECK_NO_NODE=1
export DOCS_CHECK_NO_NODE
assert_status 0 "the fallback gate exits 0" -- sh scripts/check.sh
assert_out_has "design-brief advisory"
assert_out_has "housekeeping-due advisory"
unset DOCS_CHECK_NO_NODE

t_done "docs gate advisory visibility"
