#!/bin/sh
# tests/tdd-pairing-guard.test.sh — the TDD pairing rule as a SEAM.
#
# `scripts/tdd-pairing-guard.sh <base> <head>` is the seam: the rule is reachable
# from a hook, from CI, and from here, which is the whole reason it is a script
# and not four lines inside a hook. What is asserted IS the diff classification,
# so every case drives the real script against a real throwaway repository.
#
# Ported from the vitest suite this rule was extracted from, and extended with
# the cases the kit adds: the configuration seam, and the unconfigured default.
#
# Usage: sh tests/tdd-pairing-guard.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$KIT/scripts/tdd-pairing-guard.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

# A representative project shape: TypeScript under src/ and packages/*/src,
# tests beside the code, plus one policy-data exclusion.
CONFIG_STD=$(
	cat <<'EOF'
GUARD_SOURCE_RE='^(src|packages/[^/]+/src)/.*\.(ts|tsx|mjs)$'
GUARD_SOURCE_EXCLUDE_RE='\.d\.ts$|^src/policy\.json$|^packages/[^/]+/src/config\.mjs$'
GUARD_TEST_RE='(\.|_)(test|spec)\.(ts|tsx|mjs)$|\.feature$'
EOF
)

configure() { t_write "$1" "scripts/guards.config.sh" "$2
"; }

# This suite runs the KIT's guard against throwaway repos — a cross-repo call,
# which is exactly what discovery now refuses (a config is code; standing in a
# repo must not run its code). So the config each case writes is handed over
# explicitly, the sanctioned way to cross repos. Same-repo discovery gets its
# own positive case at the bottom of the file.
run_guard() {
	_repo=$1
	shift
	if [ -f "$_repo/scripts/guards.config.sh" ]; then
		(cd "$_repo" && GUARDS_CONFIG="$_repo/scripts/guards.config.sh" sh "$GUARD" "$@")
	else
		(cd "$_repo" && sh "$GUARD" "$@")
	fi
}

# A repo with one base commit; the caller commits the head. Sets `repo` (its
# path) and `BASE` (the base sha).
new_repo_with_base() {
	t_repo
	repo=$REPO
	t_write "$repo" "README.md" "base
"
	BASE=$(t_commit "$repo" "chore: base")
}

# ---------------------------------------------------------------------------
banner "Usage and unrunnable ranges"
# ---------------------------------------------------------------------------
new_repo_with_base
configure "$repo" "$CONFIG_STD"

assert_status 2 "no refs at all is a usage error" -- run_guard "$repo"
assert_out_has "usage"
assert_status 2 "one ref is a usage error" -- run_guard "$repo" HEAD
assert_status 2 "an unknown flag is a usage error" -- run_guard "$repo" --nope
assert_status 2 "a range that cannot be diffed exits 2" -- run_guard "$repo" no-such-ref HEAD

# ---------------------------------------------------------------------------
banner "Unconfigured — the default a fresh project inherits"
# ---------------------------------------------------------------------------
# The load-bearing default. A guard that blocked every push in a repo nobody has
# configured yet would be deleted on day one, and a deleted guard checks nothing.
new_repo_with_base
t_write "$repo" "src/thing.ts" "export const a = 1;
"
head=$(t_commit "$repo" "feat: unpaired source change")

configure "$repo" "GUARD_SOURCE_RE=''"
assert_status 0 "an unconfigured guard passes an unpaired source change" -- run_guard "$repo" "$BASE" "$head"
assert_out_has "INACTIVE"
assert_out_has "GUARD_SOURCE_RE"

# NO config reachable by ANY discovery order — which is not what running the
# kit's guard bare from a config-less fixture tests. Order 3 is the guard
# script's own directory, so the kit's guard always finds the kit's policy,
# and once the kit configured its own guard (#190) that policy was no longer
# empty. To test the truly unconfigured state the guard and its lib are copied
# somewhere with no policy file beside them and no repository above them.
BARE="$SCRATCH/bare-guard"
mkdir -p "$BARE"
cp "$GUARD" "$BARE/tdd-pairing-guard.sh"
cp "$KIT/scripts/guards.lib.sh" "$BARE/guards.lib.sh"
assert_status 0 "with no config reachable by any order, the guard is INACTIVE and passes" -- sh -c "rm -f '$repo/scripts/guards.config.sh'; cd '$repo' && unset GUARDS_CONFIG && sh '$BARE/tdd-pairing-guard.sh' '$BASE' '$head'"
assert_out_has "INACTIVE"

configure "$repo" "GUARD_SOURCE_RE=''"
assert_status 0 "TDD_PAIRING_GUARD_QUIET=1 silences the warning (one push, one warning)" -- sh -c "cd '$repo' && TDD_PAIRING_GUARD_QUIET=1 sh '$GUARD' '$BASE' '$head'"
assert_out_lacks "INACTIVE"

# Configured source but no way to recognise a test would fail EVERY source
# change. That is a broken config, not a verdict — exit 2, not 1.
configure "$repo" "GUARD_SOURCE_RE='^src/'
GUARD_TEST_RE=''"
assert_status 2 "an empty GUARD_TEST_RE is a configuration error, not a verdict" -- run_guard "$repo" "$BASE" "$head"
assert_out_has "GUARD_TEST_RE"

# ---------------------------------------------------------------------------
banner "The rule itself"
# ---------------------------------------------------------------------------
new_repo_with_base
t_write "$repo" "src/report.ts" "export const a = 1;
"
head=$(t_commit "$repo" "feat: source only")
configure "$repo" "$CONFIG_STD"
assert_status 1 "blocks source changes that carry no test changes" -- run_guard "$repo" "$BASE" "$head"
assert_out_has "src/report.ts"
assert_out_has "source changes with no test changes"

new_repo_with_base
t_write "$repo" "packages/domain/src/report.ts" "export const a = 1;
"
t_write "$repo" "packages/domain/src/report.test.ts" "// test
"
head=$(t_commit "$repo" "feat: source with its test")
configure "$repo" "$CONFIG_STD"
assert_status 0 "passes source changes paired with a test change" -- run_guard "$repo" "$BASE" "$head"

new_repo_with_base
t_write "$repo" "src/report.ts" "export const a = 1;
"
t_write "$repo" "features/thing.feature" "Feature: thing
"
head=$(t_commit "$repo" "feat: source with an executable spec")
configure "$repo" "$CONFIG_STD"
assert_status 0 "accepts an executable spec as the paired test change" -- run_guard "$repo" "$BASE" "$head"

new_repo_with_base
t_write "$repo" "docs/diary.md" "log
"
t_write "$repo" "infra/main.tf" "resource {}
"
t_write "$repo" "app/routes/index.tsx" "export default () => null;
"
head=$(t_commit "$repo" "chore: everything outside the covered trees")
configure "$repo" "$CONFIG_STD"
assert_status 0 "ignores changes outside the configured source trees" -- run_guard "$repo" "$BASE" "$head"

# ---------------------------------------------------------------------------
banner "GUARD_SOURCE_EXCLUDE_RE — the carve-outs"
# ---------------------------------------------------------------------------
new_repo_with_base
t_write "$repo" "src/globals.d.ts" "declare const x: 1;
"
head=$(t_commit "$repo" "chore: a type declaration")
configure "$repo" "$CONFIG_STD"
assert_status 0 "ignores type declaration files" -- run_guard "$repo" "$BASE" "$head"

new_repo_with_base
t_write "$repo" "packages/docs/src/config.mjs" "export default {};
"
head=$(t_commit "$repo" "chore: edit reviewable policy data")
configure "$repo" "$CONFIG_STD"
assert_status 0 "exempts reviewable policy DATA named in the exclude pattern" -- run_guard "$repo" "$BASE" "$head"

# ---------------------------------------------------------------------------
banner "Ranges git itself describes oddly"
# ---------------------------------------------------------------------------
t_repo
repo=$REPO
t_write "$repo" "src/report.ts" "export const a = 1;
"
BASE=$(t_commit "$repo" "feat: seed")
git -C "$repo" mv src/report.ts src/moved.ts
head=$(t_commit "$repo" "refactor: move the module")
configure "$repo" "$CONFIG_STD"
assert_status 0 "ignores a pure rename — a move is not new behavior" -- run_guard "$repo" "$BASE" "$head"

new_repo_with_base
configure "$repo" "$CONFIG_STD"
assert_status 0 "passes an empty range" -- run_guard "$repo" "$BASE" "$BASE"

# ---------------------------------------------------------------------------
banner "The caller's voice — label and hint"
# ---------------------------------------------------------------------------
new_repo_with_base
t_write "$repo" "src/report.ts" "export const a = 1;
"
head=$(t_commit "$repo" "feat: source only")
configure "$repo" "$CONFIG_STD"
assert_status 1 "still fails when a caller names itself" -- run_guard "$repo" "$BASE" "$head" --label pre-push --hint "Bypass with FOO=1."
assert_out_has "x pre-push: source changes with no test changes"
assert_out_has "Bypass with FOO=1."

# ---------------------------------------------------------------------------
banner "Where the configuration comes from"
# ---------------------------------------------------------------------------
# Discovery order: $GUARDS_CONFIG, then the repo root's scripts/guards.config.sh.
# Every case above exercised the second; these two pin the first.
new_repo_with_base
t_write "$repo" "src/report.ts" "export const a = 1;
"
head=$(t_commit "$repo" "feat: source only")
configure "$repo" "GUARD_SOURCE_RE=''"
printf '%s\n' "$CONFIG_STD" >"$SCRATCH/elsewhere.config.sh"

assert_status 1 "GUARDS_CONFIG overrides the repo-root config" -- sh -c "cd '$repo' && GUARDS_CONFIG='$SCRATCH/elsewhere.config.sh' sh '$GUARD' '$BASE' '$head'"
assert_out_has "src/report.ts"

assert_status 2 "a GUARDS_CONFIG that does not exist is an error, not a silent fallback" -- sh -c "cd '$repo' && GUARDS_CONFIG='$SCRATCH/no-such.config.sh' sh '$GUARD' '$BASE' '$head'"
assert_out_has "does not exist"

# ---------------------------------------------------------------------------
banner "Config discovery is anchored, never a reward for standing somewhere"
# ---------------------------------------------------------------------------
# guards.config.sh is SOURCED — code, not data. Order 2 therefore loads the
# cwd repo's config only when that repo is ALSO the one the guard came from.

# The consumer shape, positive: a repo carrying its own copies of the guard,
# the loader and a config — the hook/CI reality — still discovers by cwd.
new_repo_with_base
mkdir -p "$repo/scripts"
cp "$GUARD" "$KIT/scripts/guards.lib.sh" "$repo/scripts/"
configure "$repo" "$CONFIG_STD"
t_write "$repo" "src/own.ts" "export const own = 1;
"
head=$(t_commit "$repo" "feat: unpaired source change")
assert_status 1 "a repo's own guard still discovers that repo's config by cwd" -- \
	sh -c "cd '$repo' && sh scripts/tdd-pairing-guard.sh '$BASE' '$head'"
assert_out_has "src/own.ts"

# The same shape from inside a git hook: git exports GIT_DIR to hooks (linked
# worktrees especially), and a pinned identity makes rev-parse answer for the
# pinned repo — or the anchor directory itself — unless the anchor's call
# scrubs it. A repo's own config must not look foreign on a worktree push.
assert_status 1 "a pinned GIT_DIR does not make a repo's own config look foreign" -- \
	sh -c "cd '$repo' && GIT_DIR='$repo/.git' sh scripts/tdd-pairing-guard.sh '$BASE' '$head'"
assert_out_has "src/own.ts"
assert_out_lacks "refusing to source"

# The attack shape, refused: the kit's guard run while standing in a foreign
# clone must not execute that clone's config. The canary prints on stderr the
# moment the config is sourced, so its absence is proof of non-execution.
new_repo_with_base
configure "$repo" "echo 'FOREIGN-GUARDS-CONFIG-EXECUTED' >&2
GUARD_SOURCE_RE='^src/'
GUARD_TEST_RE='\\.test\\.'"
t_write "$repo" "src/mark.ts" "export const mark = 1;
"
head=$(t_commit "$repo" "feat: unpaired source change")
assert_status 0 "a foreign clone's config is refused, and the guard runs unconfigured" -- \
	sh -c "cd '$repo' && sh '$GUARD' '$BASE' '$head'"
assert_out_lacks "FOREIGN-GUARDS-CONFIG-EXECUTED"
assert_out_has "refusing to source"
assert_out_has "GUARDS_CONFIG"

# Operator-confirmed contract: an ANCHORLESS load discovers nothing. The only
# default an anchorless caller could get is the cwd — which is the hole. Same
# hostile fixture: the loader, sourced bare, must return 1 with the canary
# silent.
assert_status 1 "an anchorless load discovers nothing, even standing in a repo carrying a config" -- \
	sh -c "cd '$repo' && unset GUARDS_CONFIG && . '$KIT/scripts/guards.lib.sh' && guards_load_config"
assert_out_lacks "FOREIGN-GUARDS-CONFIG-EXECUTED"

# ---------------------------------------------------------------------------
banner "The kit's own policy — the guard is ON in the repo that ships it"
# ---------------------------------------------------------------------------
# Every push of the 0.18.0 wave printed "TDD pairing guard is INACTIVE — no
# source patterns configured", from the repository whose product is the
# discipline the guard enforces. ADR-0001 says the kit obeys its own
# constitution; this is the check that it does here.
#
# The fixture copies the kit's REAL policy — scripts/guards.kit.config.sh, the
# kit-only file the hook points GUARDS_CONFIG at — rather than restating the
# pattern, so the suite and the policy cannot drift apart. NOT the shipped
# scripts/guards.config.sh: that one stays empty on purpose, because bootstrap
# copies it into every consumer, and the first version of this change filled
# it in and would have made scripts/*.sh every consumer's definition of source.
# tests/guards-demo.sh and tests/adapters-demo.sh both caught that.

# kit_policy <repo> — the kit's own guard policy, in the fixture, under the
# name run_guard reads. The directory is made first: a bare `cp` into a fresh
# fixture failed silently, and the case then passed anyway — because discovery
# order 3 is the guard script's own directory. Which is the coupling this whole
# section exists to remove.
kit_policy() {
	mkdir -p "$1/scripts"
	cp "$KIT/scripts/guards.kit.config.sh" "$1/scripts/guards.config.sh" || exit 2
}

new_repo_with_base
kit_policy "$repo"
t_write "$repo" "scripts/thing.sh" "#!/bin/sh
echo changed
"
head=$(t_commit "$repo" "feat: a kit script changes with no test")
assert_status 1 "a change to a kit script with no test change is BLOCKED" -- run_guard "$repo" "$BASE" "$head"
assert_out_has "scripts/thing.sh"
assert_out_lacks "INACTIVE"
t_write "$repo" "tests/thing.test.sh" "#!/bin/sh
exit 0
"
head=$(t_commit "$repo" "test: and its test")
assert_status 0 "the same change paired with a test under tests/ passes" -- run_guard "$repo" "$BASE" "$head"

new_repo_with_base
kit_policy "$repo"
t_write "$repo" "scripts/docs-conformance/validators/probe.mjs" "export const id = 'probe';
"
head=$(t_commit "$repo" "feat: a validator changes with no test")
assert_status 1 "a change to a docs-harness validator with no test change is BLOCKED" -- run_guard "$repo" "$BASE" "$head"
t_write "$repo" "scripts/docs-conformance/test/probe.test.mjs" "import test from 'node:test';
"
head=$(t_commit "$repo" "test: and its fixture test")
assert_status 0 "…and paired with a test under scripts/docs-conformance/test/ it passes" -- run_guard "$repo" "$BASE" "$head"

# Policy is not source.
new_repo_with_base
kit_policy "$repo"
t_write "$repo" "scripts/agents.config.sh" "AGENT_TIER_PLANNER='changed'
"
head=$(t_commit "$repo" "chore: a policy file changes alone")
assert_status 0 "a policy file changing alone is not a source change" -- run_guard "$repo" "$BASE" "$head"

new_repo_with_base
kit_policy "$repo"
t_write "$repo" "bootstrap.sh" "#!/bin/sh
echo changed
"
head=$(t_commit "$repo" "feat: bootstrap changes with no test")
assert_status 1 "bootstrap.sh is source" -- run_guard "$repo" "$BASE" "$head"

# The wrapper, and the HOOK that selects it. Both were surviving mutants in
# the first version of this change: deleting the hook's selection left every
# suite green. The hook is run the way git runs it — with the docs gate
# bypassed, since a fixture has no docs to gate, and the ref line on stdin —
# against a fixture that carries the kit-only pair.
new_repo_with_base
kit_policy "$repo"
mkdir -p "$repo/.githooks"
cp "$KIT/.githooks/pre-push" "$repo/.githooks/pre-push"
cp "$KIT/scripts/tdd-pairing-guard.sh" "$repo/scripts/tdd-pairing-guard.sh"
cp "$KIT/scripts/guards.lib.sh" "$repo/scripts/guards.lib.sh"
cp "$KIT/scripts/guards.kit.sh" "$repo/scripts/guards.kit.sh"
cp "$KIT/scripts/guards.kit.config.sh" "$repo/scripts/guards.kit.config.sh"
# The fixture's SHIPPED policy stays empty, as the kit's does: the hook must
# reach the kit-only one on its own.
cp "$KIT/scripts/guards.config.sh" "$repo/scripts/guards.config.sh"
t_write "$repo" "scripts/thing.sh" "#!/bin/sh
echo changed
"
head=$(t_commit "$repo" "feat: unpaired, pushed through the hook")

assert_status 1 "the wrapper, run bare, blocks the unpaired change" -- sh -c "cd '$repo' && sh scripts/guards.kit.sh '$BASE' '$head'"
assert_out_lacks "INACTIVE"

assert_status 1 "the HOOK selects the kit-only policy and blocks the push" -- sh -c "cd '$repo' && printf 'refs/heads/main %s refs/heads/main %s\n' '$head' '$BASE' | PUSH_WITHOUT_DOCS=1 sh .githooks/pre-push origin git@example.invalid:x.git"
assert_out_has "scripts/thing.sh"
assert_out_lacks "INACTIVE"

# Downstream: no kit-only pair, and the hook behaves exactly as before.
rm -f "$repo/scripts/guards.kit.sh" "$repo/scripts/guards.kit.config.sh"
assert_status 0 "without the kit-only pair the hook runs the shipped policy — unconfigured, so INACTIVE and passing" -- sh -c "cd '$repo' && printf 'refs/heads/main %s refs/heads/main %s\n' '$head' '$BASE' | PUSH_WITHOUT_DOCS=1 sh .githooks/pre-push origin git@example.invalid:x.git"
assert_out_has "INACTIVE"

# An operator's own GUARDS_CONFIG wins over the kit-only selection.
cp "$KIT/scripts/guards.kit.sh" "$repo/scripts/guards.kit.sh"
cp "$KIT/scripts/guards.kit.config.sh" "$repo/scripts/guards.kit.config.sh"
: >"$SCRATCH/operator.config.sh"
assert_status 0 "an exported GUARDS_CONFIG is respected by the hook over the kit-only pair" -- sh -c "cd '$repo' && printf 'refs/heads/main %s refs/heads/main %s\n' '$head' '$BASE' | GUARDS_CONFIG='$SCRATCH/operator.config.sh' PUSH_WITHOUT_DOCS=1 sh .githooks/pre-push origin git@example.invalid:x.git"
assert_out_has "INACTIVE"

# And the shipped file is still empty — the whole point of the kit-only one.
grep -q "^GUARD_SOURCE_RE=''" "$KIT/scripts/guards.config.sh" &&
	pass "the SHIPPED scripts/guards.config.sh still has no source pattern" ||
	fail "the shipped policy file carries a pattern — it would become every consumer's"

t_done "tdd-pairing-guard.sh"
