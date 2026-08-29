#!/bin/sh
# tests/adopt-demo.sh — the existing-repo adoption arm's referee (#82, PRD #81).
#
# The contract under test is bootstrap's ADOPT MODE, run from inside a target
# repository against a scratch kit clone:
#
#   - classify every kit file per the per-class collision policy;
#   - install the non-colliding set in one pass;
#   - print ONE stable machine-readable line per conflict:
#         COLLISION <class> <path> <verb>
#     and resolve nothing itself;
#   - exit 3 while collisions pend, 0 when the tree is (or has become) clean —
#     completing exactly as the new-project arm does: stamped manual, shims,
#     dogfood under the same flags, hook wired, self-deletion only then;
#   - be idempotent: a re-run neither duplicates installs nor damages anything,
#     and after the agent resolves the collisions a re-run flips to 0.
#
# One deliberate collision per COLLISION class (shared, manual, skill,
# workflow, hook), plus the memory case — which is deliberately NOT a
# collision: project memory is kept with a "kept" line, because a classifier
# verdict must be resolvable and "your diary exists" never stops being true.
#
# Usage: sh tests/adopt-demo.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

PROJECT_NAME="Adopted Proj"
PROJECT_DESC="An existing repository adopting the kit."

# ---------------------------------------------------------------------------
banner "A. Fixtures — a scratch kit clone, and a target with one collision per class"
# ---------------------------------------------------------------------------
KITCOPY="$SCRATCH/kit-clone"
mkdir -p "$KITCOPY"
cp -R "$KIT/." "$KITCOPY/"
strip_nested_worktrees "$KIT" "$KITCOPY"
rm -rf "$KITCOPY/.git"
[ -f "$KITCOPY/bootstrap.sh" ] && pass "the scratch kit clone carries bootstrap.sh" ||
	fail "kit copy failed — nothing else can run"

mk_target() {
	TARGET=$(mktemp -d "$SCRATCH/target.XXXXXX") || exit 2
	git -C "$TARGET" init -q -b main
	git -C "$TARGET" config user.name "Adopting Team"
	git -C "$TARGET" config user.email "team@example.invalid"
	git -C "$TARGET" config commit.gpgsign false
	t_write "$TARGET" "README.md" "# Their project

Their readme, theirs to keep.
"
	git -C "$TARGET" add -A
	git -C "$TARGET" commit -q -m "chore: their root"
}

mk_target
# One collision per class, each with content that must survive byte-for-byte
# until a human approves its resolution.
t_write "$TARGET" "AGENTS.md" "# Their rules

- releases happen on Fridays, reviewed by two humans
"
t_write "$TARGET" "docs/diary.md" "their project log — theirs, never overwritten
"
t_write "$TARGET" ".claude/skills/tdd/SKILL.md" "their own tdd skill
"
t_write "$TARGET" ".githooks/pre-push" "#!/bin/sh
echo their hook
"
t_write "$TARGET" "scripts/check.sh" "#!/bin/sh
echo their checker
"
t_write "$TARGET" ".github/workflows/docs-gate.yml" "name: their gate
"
git -C "$TARGET" add -A
git -C "$TARGET" commit -q -m "feat: their pre-adoption state"

# Byte-truth anchors for "theirs is untouched".
for f in AGENTS.md docs/diary.md scripts/check.sh README.md .githooks/pre-push .github/workflows/docs-gate.yml; do
	mkdir -p "$SCRATCH/theirs/$(dirname "$f")"
	cp "$TARGET/$f" "$SCRATCH/theirs/$f"
done

# ---------------------------------------------------------------------------
banner "B. First adopt run — safe set installs, five verdicts, exit 3, nothing of theirs moves"
# ---------------------------------------------------------------------------
assert_status 3 "adopt on a colliding tree exits 3 (partial: collisions pending)" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"

ADOPT1_OUT="$LAST_OUT"
assert_out_has "COLLISION shared scripts/check.sh relocate"
assert_out_has "COLLISION manual AGENTS.md distill"
assert_out_has "COLLISION skill .claude/skills/tdd rename-or-decline"
assert_out_has "COLLISION workflow .github/workflows/docs-gate.yml chain"
assert_out_has "COLLISION hook .githooks/pre-push chain"

# The line format is a machine contract: class and verb from closed sets, one
# space, no prose. Five collisions, five conforming lines, nothing else
# COLLISION-shaped.
conforming=$(printf '%s\n' "$ADOPT1_OUT" |
	grep -cE '^COLLISION (shared|manual|skill|workflow|hook) [^ ]+ (relocate|distill|rename-or-decline|chain)$')
total=$(printf '%s\n' "$ADOPT1_OUT" | grep -c '^COLLISION' || true)
if [ "$conforming" = 5 ] && [ "$total" = 5 ]; then
	pass "exactly five COLLISION lines, all in the stable format"
else
	fail "COLLISION lines: $total total, $conforming conforming — the machine contract drifted"
	printf '%s\n' "$ADOPT1_OUT" | grep '^COLLISION' | sed 's/^/        | /'
fi

# Memory is kept, never a collision: a verdict must be resolvable, and "your
# diary exists" never stops being true.
assert_out_has "kept docs/diary.md"
assert_out_lacks "COLLISION memory"

# The safe set landed.
for f in VERSION scripts/guards.lib.sh constitution/shared-invariants.md \
	constitution/shared-code-craft.md .claude/skills/implement/SKILL.md \
	docs/domain-glossary.md docs/adr/INDEX.md docs/adr/NNNN-template.md \
	.github/PULL_REQUEST_TEMPLATE.md .github/workflows/tdd-pairing.yml \
	scripts/docs-conformance/config.mjs scripts/agents.config.sh \
	scripts/guards.config.sh scripts/docs-conformance/local-vocabulary.mjs; do
	[ -e "$TARGET/$f" ] && pass "installed: $f" || fail "safe set is missing $f"
done
assert_file_has "$TARGET/docs/domain-glossary.md" "$PROJECT_NAME" "stamped, not copied"
assert_file_has "$TARGET/scripts/docs-conformance/local-vocabulary.mjs" "$PROJECT_NAME" "the vocabulary is armed from the first run"

# Dogfood declined: the skill stays out and the config's marked exemption
# block leaves with it — the same contract the new-project arm keeps.
[ -e "$TARGET/.claude/skills/dogfood" ] &&
	fail "dogfood installed despite --no-dogfood" ||
	pass "no dogfood skill under --no-dogfood"
assert_file_lacks "$TARGET/scripts/docs-conformance/config.mjs" "DOGFOOD:BEGIN" "markers are consumed, not shipped"
assert_file_lacks "$TARGET/scripts/docs-conformance/config.mjs" "docs/dogfood-reports" "the exemption travels with the skill"

# Nothing of theirs moved, and nothing manual-shaped was written around them.
for f in AGENTS.md docs/diary.md scripts/check.sh README.md .githooks/pre-push .github/workflows/docs-gate.yml; do
	cmp -s "$SCRATCH/theirs/$f" "$TARGET/$f" &&
		pass "theirs, byte-identical: $f" ||
		fail "adopt touched their $f before any approval"
done
[ -e "$TARGET/CLAUDE.md" ] && fail "a shim was written while the manual collision pends" ||
	pass "no shims while the manual collision pends — one manual, never two"
hookspath=$(git -C "$TARGET" config core.hooksPath || true)
[ "$hookspath" = ".githooks" ] &&
	fail "the hook was wired while their pre-push collision pends" ||
	pass "core.hooksPath untouched while the hook collision pends"

# Kit-authoring never crosses over.
for f in tests SETUP.md EXCLUSIONS.md scripts/agents.kit.sh scripts/agents.kit.config.sh setup; do
	[ -e "$TARGET/$f" ] && fail "kit-authoring artifact leaked into the target: $f" ||
		pass "no kit-authoring leak: $f"
done

# ---------------------------------------------------------------------------
banner "C. Idempotency — a second run changes nothing and reports the same pending set"
# ---------------------------------------------------------------------------
assert_status 3 "re-run still exits 3 with the collisions unresolved" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
rerun_total=$(printf '%s\n' "$LAST_OUT" | grep -c '^COLLISION' || true)
[ "$rerun_total" = 5 ] && pass "the same five collisions, no duplicates" ||
	fail "re-run reported $rerun_total collisions, expected the same 5"
cmp -s "$SCRATCH/theirs/docs/diary.md" "$TARGET/docs/diary.md" &&
	pass "their diary still byte-identical after the re-run" ||
	fail "the re-run touched their diary"
assert_file_has "$TARGET/docs/domain-glossary.md" "$PROJECT_NAME" "the installed set survived the re-run unduplicated"

# ---------------------------------------------------------------------------
banner "D. Resolutions applied (as the agent would, each human-approved) — the run flips to 0"
# ---------------------------------------------------------------------------
# Mechanical stand-ins for the payload arm's proposals, one per verdict verb:
(
	cd "$TARGET" || exit 2
	mv scripts/check.sh scripts/legacy-check.sh                # relocate
	mkdir -p docs && mv AGENTS.md docs/legacy-agent-rules.md   # distill (stand-in)
	mv .claude/skills/tdd .claude/skills/their-tdd             # rename-or-decline
	mv .github/workflows/docs-gate.yml .github/workflows/legacy-gate.yml # chain
	mv .githooks/pre-push .githooks/pre-push.local             # chain
)
assert_status 0 "after every resolution, adopt completes clean (exit 0)" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
assert_out_lacks "COLLISION"

assert_file_has "$TARGET/AGENTS.md" "$PROJECT_NAME" "the manual is stamped, at last"
for shim in CLAUDE.md GEMINI.md; do
	[ -f "$TARGET/$shim" ] && pass "shim written: $shim" || fail "missing shim after the clean run: $shim"
done
cmp -s "$KITCOPY/scripts/check.sh" "$TARGET/scripts/check.sh" &&
	pass "the shared check.sh is the kit's, byte-verbatim" ||
	fail "scripts/check.sh is not the kit's copy after the clean run"
[ "$(git -C "$TARGET" config core.hooksPath)" = ".githooks" ] &&
	pass "the hook is wired once its collision was resolved" ||
	fail "core.hooksPath is still unwired after the clean run"
cmp -s "$SCRATCH/theirs/docs/diary.md" "$TARGET/docs/diary.md" &&
	pass "their diary survived the whole adoption byte-identical" ||
	fail "the adoption modified their diary"
assert_file_has "$TARGET/docs/legacy-agent-rules.md" "releases happen on Fridays" \
	"their rules are still reachable where the resolution put them"

assert_status 0 "the adopted repo's own gate is green" -- \
	sh -c "cd '$TARGET' && sh scripts/check.sh"

[ -f "$KITCOPY/bootstrap.sh" ] &&
	fail "bootstrap.sh survived the clean exit — self-deletion is the clean exit's job" ||
	pass "bootstrap self-deleted from the scratch clone on the final clean exit"

# ---------------------------------------------------------------------------
banner "E. A collision-free repo adopts in ONE run — and dogfood's yes works too"
# ---------------------------------------------------------------------------
rm -rf "$KITCOPY" && mkdir -p "$KITCOPY" && cp -R "$KIT/." "$KITCOPY/" &&
	strip_nested_worktrees "$KIT" "$KITCOPY" && rm -rf "$KITCOPY/.git"
mk_target
assert_status 0 "a clean tree adopts fully, first run" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --with-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
assert_out_lacks "COLLISION"
assert_file_has "$TARGET/AGENTS.md" "$PROJECT_NAME" "stamped in one pass"
cmp -s "$SCRATCH/theirs/README.md" "$TARGET/README.md" &&
	pass "their README is kept even on the clean path — an adopted repo keeps its front page" ||
	fail "the clean path overwrote their README"
[ -f "$TARGET/.claude/skills/dogfood/SKILL.md" ] && pass "dogfood installed under --with-dogfood" ||
	fail "--with-dogfood did not install the skill"
assert_file_has "$TARGET/scripts/docs-conformance/config.mjs" "docs/dogfood-reports/" \
	"the exemption ships with the skill"
assert_file_lacks "$TARGET/scripts/docs-conformance/config.mjs" "DOGFOOD:BEGIN" "markers consumed on the accept path too"
assert_status 0 "the clean adoption's gate is green" -- \
	sh -c "cd '$TARGET' && sh scripts/check.sh"

# ---------------------------------------------------------------------------
banner "F. The contract refuses bad ground — and the format probe is not vacuous"
# ---------------------------------------------------------------------------
rm -rf "$KITCOPY" && mkdir -p "$KITCOPY" && cp -R "$KIT/." "$KITCOPY/" &&
	strip_nested_worktrees "$KIT" "$KITCOPY" && rm -rf "$KITCOPY/.git"
mk_target
assert_status 1 "adopt without a project name dies with usage, not a half-adoption" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood"
[ -e "$TARGET/VERSION" ] && fail "a refused run still installed files" ||
	pass "a refused run installs nothing"

assert_status 1 "adopt from inside the kit clone itself is refused" -- \
	sh -c "cd '$KITCOPY' && git init -q -b main && sh bootstrap.sh --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"

# The format probe above must be able to fail: a COLLISION line with prose
# appended, an unknown class, or an unknown verb all fall out of the grep.
for bait in \
	"COLLISION shared scripts/x.sh relocate (please fix)" \
	"COLLISION mystery scripts/x.sh relocate" \
	"COLLISION shared scripts/x.sh shrug"; do
	if printf '%s\n' "$bait" |
		grep -qE '^COLLISION (shared|manual|skill|workflow|hook) [^ ]+ (relocate|distill|rename-or-decline|chain)$'; then
		fail "the format probe accepted a malformed line: $bait"
	else
		pass "the format probe rejects: $bait"
	fi
done

t_done "adopt demo"
