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

# mk_kitcopy — a fresh scratch kit clone; adopt self-deletes bootstrap on a
# clean exit, so sections that need a live one rebuild it.
mk_kitcopy() {
	rm -rf "$KITCOPY"
	mkdir -p "$KITCOPY"
	cp -R "$KIT/." "$KITCOPY/"
	strip_nested_worktrees "$KIT" "$KITCOPY"
	rm -rf "$KITCOPY/.git"
}

mk_kitcopy
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
mk_kitcopy
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
# The adopt arm installs both addresses: canonical real files at the neutral
# home, and the per-skill symlink bridge at the vendor-named one (issue #97).
[ -f "$TARGET/.agents/skills/dogfood/SKILL.md" ] && [ ! -L "$TARGET/.agents/skills/dogfood" ] &&
	pass "the adopt arm lays the canonical home as real files" ||
	fail "the adopt arm did not install .agents/skills/dogfood as real files (issue #97)"
[ -L "$TARGET/.claude/skills/dogfood" ] &&
	pass "the adopt arm lays the per-skill symlink bridge" ||
	fail "the adopt arm's .claude/skills/dogfood is not a symlink (issue #97)"
assert_file_has "$TARGET/scripts/docs-conformance/config.mjs" "docs/dogfood-reports/" \
	"the exemption ships with the skill"
assert_file_lacks "$TARGET/scripts/docs-conformance/config.mjs" "DOGFOOD:BEGIN" "markers consumed on the accept path too"
assert_status 0 "the clean adoption's gate is green" -- \
	sh -c "cd '$TARGET' && sh scripts/check.sh"

# ---------------------------------------------------------------------------
banner "F. The contract refuses bad ground — and the format probe is not vacuous"
# ---------------------------------------------------------------------------
mk_kitcopy
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

# ---------------------------------------------------------------------------
banner "F2. Review regressions — links, modes, and the flag flip (PR #84 findings)"
# ---------------------------------------------------------------------------
# H-1: a DANGLING symlink at a kit path is still THEIRS — presence tests that
# use `[ -e ]` alone read it as absent, and a follow-through cp then writes
# OUTSIDE the repo and exits 0. It must be a collision, and nothing may land
# beyond the target's boundary.
mk_kitcopy
mk_target
OUTSIDE=$(mktemp -d "$SCRATCH/outside.XXXXXX")
mkdir -p "$TARGET/scripts"
ln -s "$OUTSIDE/stolen.sh" "$TARGET/scripts/check.sh"
git -C "$TARGET" add -A 2>/dev/null || true
assert_status 3 "a dangling symlink at a shared path is a collision, not an install" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
assert_out_has "COLLISION shared scripts/check.sh relocate"
[ -e "$OUTSIDE/stolen.sh" ] &&
	fail "adopt wrote THROUGH their symlink to a path outside the repo" ||
	pass "nothing landed outside the target — the link was never followed"
[ -L "$TARGET/scripts/check.sh" ] &&
	pass "their symlink itself is untouched" ||
	fail "adopt replaced their symlink without a yes"

# M-2: their file MODES are theirs too — the clean exit must not chmod a
# pre-existing 644 script into 755.
mk_target
t_write "$TARGET" "scripts/theirs.sh" "#!/bin/sh
echo their tool
"
chmod 644 "$TARGET/scripts/theirs.sh"
git -C "$TARGET" add -A && git -C "$TARGET" commit -q -m "feat: their tool"
assert_status 0 "a clean tree with their own script adopts fully" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
case "$(ls -l "$TARGET/scripts/theirs.sh")" in
-rw-r--r--*) pass "their 644 script kept its mode through the clean exit" ;;
*) fail "the clean exit changed their script's mode: $(ls -l "$TARGET/scripts/theirs.sh")" ;;
esac
[ -x "$TARGET/.githooks/pre-push" ] && pass "the kit's hook still arrived executable" ||
	fail "the kit's hook lost its executable bit"

# M-1: flipping the dogfood flag between runs, with the gate policy already
# installed stripped, must SAY that the kept config lacks the exemption the
# skill now needs — a silent contradiction is a latent gate warning.
mk_kitcopy
mk_target
t_write "$TARGET" ".githooks/pre-push" "#!/bin/sh
echo their hook
"
git -C "$TARGET" add -A && git -C "$TARGET" commit -q -m "feat: their hook"
t_run sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
[ "$LAST_STATUS" = 3 ] && pass "first run parks on the hook collision" || fail "expected exit 3, got $LAST_STATUS"
t_run sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --with-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
assert_out_has "kept scripts/docs-conformance/config.mjs"
case "$LAST_OUT" in
*"docs/dogfood-reports/"*) pass "the flag flip names the exemption the kept config now lacks" ;;
*) fail "the dogfood flag flipped against a kept config and nothing said so — a latent gate warning ships silently" ;;
esac

# ---------------------------------------------------------------------------
banner "F3. Neutral-home review regressions (PR #104 findings)"
# ---------------------------------------------------------------------------
# H-2: a target whose .claude/skills (or .agents) is itself a SYMLINK would
# have every bridge written THROUGH it — outside the repo, exit 0. The arm
# must refuse before touching either side, and nothing may land beyond the
# target's boundary.
# All FOUR parents the refusal names get the same probe. Covering only two of
# them was itself a hard-rule-9 hole: dropping either of the other two from
# the loop in bootstrap.sh left this suite entirely green, and each dropped
# name is a real write-through (28 files outside the repo for .agents/skills,
# 17 for .claude).
for a_link in .claude/skills .agents/skills .claude .agents \
	.githooks .github .github/workflows constitution docs docs/adr \
	scripts scripts/docs-conformance; do
	mk_kitcopy
	mk_target
	OUTSIDE=$(mktemp -d "$SCRATCH/outside.XXXXXX")
	# The link's own parent has to exist for the nested cases, and must not
	# itself be a link — this probe is about ONE symlinked parent at a time.
	a_dir=$(dirname "$a_link")
	[ "$a_dir" = "." ] || mkdir -p "$TARGET/$a_dir"
	ln -s "$OUTSIDE" "$TARGET/$a_link"
	assert_status 1 "a symlinked $a_link is a refusal, not a write-through" -- \
		sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
	assert_out_has "is a symlink"
	[ -z "$(ls -A "$OUTSIDE" 2>/dev/null)" ] &&
		pass "nothing landed outside the target through the linked $a_link" ||
		fail "adopt wrote through the symlinked $a_link into foreign ground"
	# …and nothing landed INSIDE either. A refusal that fires after three
	# sections have written is a half-adopted repo behind a message that
	# reads like nothing happened, so the check has to precede every write.
	[ -e "$TARGET/AGENTS.md" ] &&
		fail "adopt wrote AGENTS.md before refusing $a_link — the refusal runs after the manual is installed" ||
		pass "nothing landed inside the target either — the refusal precedes every write"
done

# The same refusal owes the same answer to a REGULAR FILE at one of those
# names. Without it the run died later, at the mkdir, having already laid
# bridges — a partial write behind a message that says nothing about why.
for a_file in .claude .agents; do
	mk_kitcopy
	mk_target
	printf 'not a directory\n' >"$TARGET/$a_file"
	assert_status 1 "a regular file at $a_file is refused up front" -- \
		sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
	assert_out_has "is a file, not a directory"
	[ -f "$TARGET/$a_file" ] &&
		pass "the file at $a_file is untouched by the refusal" ||
		fail "adopt replaced or removed the regular file at $a_file"
done

# A DANGLING parent resolves nowhere at all, so "inside the repo" cannot be
# established — and writing through it would create the destination wherever
# the link happens to point. Refused with the escaping ones.
mk_kitcopy
mk_target
ln -s ../nowhere-at-all "$TARGET/docs"
assert_status 1 "a dangling parent link is refused too" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
assert_out_has "does not resolve inside this repository"
[ -e "$TARGET/../nowhere-at-all" ] &&
	fail "adopt created the dangling link's destination outside the repo" ||
	pass "the dangling link's destination was never created"

# …and the mirror of that rule: a link that stays INSIDE the repository is a
# layout choice, not a hole. The project's files still land in the project,
# which is the whole requirement, so adopt must proceed rather than refuse.
mk_kitcopy
mk_target
mkdir -p "$TARGET/documentation"
rm -rf "$TARGET/docs"
ln -s documentation "$TARGET/docs"
assert_status 0 "a parent linked INSIDE the repo is adopted, not refused" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
[ -f "$TARGET/documentation/diary.md" ] &&
	pass "the files landed inside the repo, through the link" ||
	fail "adopt refused or misplaced files for an in-repo link — nothing landed at documentation/"

# The one-link skills bridge UPDATING.md blesses: .claude/skills IS
# .agents/skills. A per-skill link there would point at itself, so the arm
# must lay none — and the tree must still pass the gate.
mk_kitcopy
mk_target
mkdir -p "$TARGET/.agents/skills" "$TARGET/.claude"
ln -s ../.agents/skills "$TARGET/.claude/skills"
assert_status 0 "a directory-level skills bridge adopts clean" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
[ -f "$TARGET/.agents/skills/tdd/SKILL.md" ] &&
	pass "skills installed at the canonical home under a directory-level bridge" ||
	fail "no canonical skill installed under a directory-level bridge"
[ -L "$TARGET/.agents/skills/tdd" ] &&
	fail "a self-referential per-skill link was laid inside the shared home" ||
	pass "no self-referential per-skill link was laid — the alias IS the bridge"
assert_status 0 "the directory-bridged tree's gate is green" -- \
	sh -c "cd '$TARGET' && sh scripts/check.sh"

# M-1: a pre-existing symlink at a bridge slot that is NOT our bridge (foreign
# target, or dangling) is a non-identical occupant — a COLLISION, never a
# silent keep that leaves the gate red after a "complete" adopt.
mk_kitcopy
mk_target
mkdir -p "$TARGET/.claude/skills"
ln -s /nonexistent/evil "$TARGET/.claude/skills/tdd"
assert_status 3 "a foreign symlink at a bridge slot is a collision" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
assert_out_has "COLLISION skill .claude/skills/tdd rename-or-decline"
[ -e "$TARGET/.agents/skills/tdd" ] &&
	fail "canonical /tdd was installed despite the unresolved bridge collision" ||
	pass "canonical /tdd held back until the bridge collision is resolved"

# M-2: a target already holding a byte-identical canonical skill but no
# bridge must adopt clean AND leave the bridge laid — exit 0 with a red gate
# is the shape this pin forbids.
mk_kitcopy
mk_target
mkdir -p "$TARGET/.agents/skills"
cp -R "$KITCOPY/.agents/skills/tdd" "$TARGET/.agents/skills/tdd"
git -C "$TARGET" add -A 2>/dev/null || true
assert_status 0 "an identical canonical skill without its bridge adopts clean" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
[ -L "$TARGET/.claude/skills/tdd" ] && [ -f "$TARGET/.claude/skills/tdd/SKILL.md" ] &&
	pass "the missing bridge was repaired on the clean path" ||
	fail "an identical canonical skill was left with no bridge — clean exit, red gate"
# L-1: a DANGLING canonical licence is a collision, not a silent keep. Every
# shipped skill names this path literally, so keeping the dead link means a
# clean "adopt: complete" whose very next gate run is red on all of them.
mk_kitcopy
mk_target
mkdir -p "$TARGET/.agents/skills"
ln -s /nonexistent/licence "$TARGET/.agents/skills/LICENSE-mattpocock-skills.md"
assert_status 3 "a dangling canonical licence is a collision, not a clean exit" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
assert_out_has "COLLISION skill .agents/skills/LICENSE-mattpocock-skills.md"

# L-2: the licence file gets the same bridge the skills do.
[ -L "$TARGET/.claude/skills/LICENSE-mattpocock-skills.md" ] &&
	pass "the licence bridge is laid too — adopted trees match template trees" ||
	fail "the licence bridge is missing — adopted trees differ from template trees by one entry"

# ---------------------------------------------------------------------------
banner "G. The payload document's existing-repo arm — its own fences drive the flow"
# ---------------------------------------------------------------------------
# #83: the Which-arm pointer stops saying "not yet" and becomes the arm. The
# doc's promises are pinned as text, and its fenced steps are extracted and
# EXECUTED (the setup-demo Part-D pattern): a doc whose own bytes cannot run
# is a doc that drifted from the mode it documents.
PAYLOAD="$KIT/setup/agent-bootstrap.md"

assert_file_lacks "$PAYLOAD" "supported yet" "the arm exists now — 'yet' arrived (single-line token, so this pin CAN fire)"
assert_file_has "$PAYLOAD" "one at a time" "per-collision approval is the arm's spine"
assert_file_has "$PAYLOAD" "COLLISION" "the arm teaches the machine contract it consumes"
assert_file_has "$PAYLOAD" "Exit code 3" "pending is a documented state, not a surprise"
assert_file_has "$PAYLOAD" "never push" "propose-only, same as the new-project arm"
assert_file_has "$PAYLOAD" "distill" "the marquee collision has its walkthrough"
assert_file_lacks "$PAYLOAD" "issues/60" "the open-spec pointer retired with the spec"
assert_file_has "$PAYLOAD" "swap back" "declining the kit's skill has a flow that actually finishes"
assert_file_has "$PAYLOAD" "edit it to invoke" "their chained hook runs again after the clean exit"
assert_file_has "$PAYLOAD" "the finishing run" "E3's output gets committed, not just proposed"

# take_g <first-line awk pattern> <dest> — first fenced sh block whose first
# line matches; extraction to a fresh file, then refuse-to-be-vacuous.
take_g() {
	awk -v pat="$1" '
		/^```sh$/       { grab = 1; n = 0; buf = ""; hit = 0; next }
		grab && /^```$/ { grab = 0; if (hit) { printf "%s", buf; exit } next }
		grab {
			n++
			if (n == 1 && $0 ~ pat) hit = 1
			buf = buf $0 "\n"
		}
	' "$PAYLOAD" >"$SCRATCH/take_g.$$"
	if [ -s "$SCRATCH/take_g.$$" ]; then
		cat "$SCRATCH/take_g.$$" >"$2"
		pass "extracted the arm's fence: $1"
	else
		: >"$2"
		fail "no fenced block starting '$1' in the payload — the spine below cannot run"
	fi
}

take_g '^git switch -c' "$SCRATCH/arm.branch"
# The $ is doubled for awk -v (escape processing eats one) so the anchor stays
# an anchor rather than becoming an end-of-line match mid-pattern.
take_g '^sh "\\$KIT_CLONE/bootstrap' "$SCRATCH/arm.adopt"
take_g '^git add -A$' "$SCRATCH/arm.commit"
take_g '^git add -A && git commit' "$SCRATCH/arm.finish"
take_g '^sh scripts/check' "$SCRATCH/arm.gate"

# Fresh fixture pair, then the DOC's own fences do the driving.
mk_kitcopy
mk_target
t_write "$TARGET" "AGENTS.md" "# Their rules
"
t_write "$TARGET" ".githooks/pre-push" "#!/bin/sh
echo their hook
"
git -C "$TARGET" add -A && git -C "$TARGET" commit -q -m "feat: their state"

arm_env() {
	{
		echo "KIT_CLONE='$KITCOPY'"
		echo "PROJECT_NAME='$PROJECT_NAME'"
		echo "PROJECT_DESC='$PROJECT_DESC'"
		echo "DOGFOOD_FLAG=--no-dogfood"
		cat "$@"
	} >"$SCRATCH/arm.run"
	(cd "$TARGET" && sh "$SCRATCH/arm.run")
}

t_run arm_env "$SCRATCH/arm.branch" "$SCRATCH/arm.adopt"
[ "$LAST_STATUS" = 3 ] && pass "the doc's own branch + adopt fences reach exit 3 on a colliding tree" ||
	fail "the doc's fences exited $LAST_STATUS, expected 3"
assert_out_has "COLLISION manual AGENTS.md distill"
[ "$(git -C "$TARGET" branch --show-current)" = "chore/adopt-kit" ] &&
	pass "adoption runs on the dedicated branch the doc creates" ||
	fail "the branch fence did not land on the adoption branch"

t_run arm_env "$SCRATCH/arm.commit"
[ "$LAST_STATUS" = 0 ] && pass "the doc's commit fence records the safe set" ||
	fail "the commit fence failed: $LAST_OUT"

(cd "$TARGET" && mv AGENTS.md docs-legacy-rules.md && mv .githooks/pre-push .githooks/pre-push.local)
t_run arm_env "$SCRATCH/arm.adopt"
[ "$LAST_STATUS" = 0 ] && pass "the same adopt fence flips to 0 once the doors are resolved" ||
	fail "the re-run fence exited $LAST_STATUS, expected 0"
t_run arm_env "$SCRATCH/arm.finish"
[ "$LAST_STATUS" = 0 ] && pass "the doc's finishing-run commit fence records the clean exit's output" ||
	fail "the finishing commit fence failed: $LAST_OUT"
git -C "$TARGET" diff --quiet && git -C "$TARGET" diff --cached --quiet &&
	pass "nothing uncommitted after the finishing commit — the branch is one reviewable unit" ||
	fail "the finishing run's output sits uncommitted after E3"
t_run arm_env "$SCRATCH/arm.gate"
[ "$LAST_STATUS" = 0 ] && pass "the doc-driven adoption ends at a green gate (E4's own fence)" ||
	fail "E4's gate fence exited $LAST_STATUS"
[ "$(git -C "$TARGET" remote | wc -l | tr -d ' ')" = "0" ] &&
	pass "no remote was added and nothing was pushed — propose-only held" ||
	fail "the doc-driven flow touched a remote"

# ---------------------------------------------------------------------------
banner "H. The decline dance — the door closes, the swap-back holds the gate green"
# ---------------------------------------------------------------------------
# Declining the kit's skill while keeping yours at the name has no mechanical
# expression in the classifier (the door closes only on absent or
# byte-identical), so the arm documents a rename-for-the-duration flow. This
# section proves that flow FINISHES: exit 0, then the swap-back commit, then
# a green gate with references resolving against THEIR skill.
mk_kitcopy
mk_target
t_write "$TARGET" ".claude/skills/prototype/SKILL.md" "their own spike skill
"
git -C "$TARGET" add -A && git -C "$TARGET" commit -q -m "feat: their skill"
t_run sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
[ "$LAST_STATUS" = 3 ] && pass "their same-name skill parks the run" || fail "expected exit 3, got $LAST_STATUS"
assert_out_has "COLLISION skill .claude/skills/prototype rename-or-decline"
(cd "$TARGET" && mv .claude/skills/prototype .claude/skills/their-prototype-hold)
assert_status 0 "renamed for the duration, the run finishes clean" -- \
	sh -c "cd '$TARGET' && sh '$KITCOPY/bootstrap.sh' --adopt --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
(
	cd "$TARGET" || exit 2
	rm -rf .claude/skills/prototype
	mv .claude/skills/their-prototype-hold .claude/skills/prototype
	grep -v '/prototype' AGENTS.md >AGENTS.md.decline && mv AGENTS.md.decline AGENTS.md
)
assert_status 0 "after the swap-back, the gate is green — their skill stands in at the name" -- \
	sh -c "cd '$TARGET' && sh scripts/check.sh"

t_done "adopt demo"
