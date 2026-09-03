#!/bin/sh
# tests/manifest.test.sh — the manifest parser as a SEAM.
#
# `manifest_section <section>` is the one grammar for VERSION's two sections:
# it reads the manifest on stdin and prints one name per line. Before this
# module existed the grammar lived in eleven hand-copied awk programs in three
# dialects, and two of them disagreed on what an annotated entry means —
# bootstrap took the first word, the gate took the whole line. This suite pins
# the grammar once, then holds every remaining copy to it: the recipe's own
# fenced copies (which must stay self-contained, because they run in a
# consumer with only sh and git) are extracted from UPDATING.md and run over
# the same fixtures as the module, and any difference in output is red.
#
# Usage: sh tests/manifest.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

MODULE="scripts/manifest.lib.sh"

# ---------------------------------------------------------------------------
banner "0. The module exists and is sourceable"
# ---------------------------------------------------------------------------
[ -f "$ROOT/$MODULE" ] && pass "$MODULE exists" || {
	fail "$MODULE is missing — nothing else in this suite means anything"
	# ---------------------------------------------------------------------------
banner "5. The gate fails CLOSED without its parser"
# ---------------------------------------------------------------------------
# The wrapper sources the module; a consumer whose copy is missing or empty
# must get a red gate, never a zero-iteration check that reads as green.
PROJ="$SCRATCH/proj"; mkdir -p "$PROJ"; cp -R "$ROOT/." "$PROJ/"; strip_nested_worktrees "$ROOT" "$PROJ"; rm -rf "$PROJ/.git"
( cd "$PROJ" && git init -q -b main && rm -f scripts/manifest.lib.sh && sh scripts/check.sh >"$SCRATCH/noparser.out" 2>&1; echo $? >"$SCRATCH/noparser.rc" )
[ "$(cat "$SCRATCH/noparser.rc")" = 1 ] && grep -q "shared-layer-missing" "$SCRATCH/noparser.out" &&
	pass "a missing manifest module is a red gate (shared-layer-missing), not a silent pass" ||
	{ fail "with the module missing the gate exited $(cat "$SCRATCH/noparser.rc") — it fails OPEN"; sed 's/^/        | /' "$SCRATCH/noparser.out" | head -5; }
( cd "$PROJ" && printf '#!/bin/sh\n' >scripts/manifest.lib.sh && sh scripts/check.sh >"$SCRATCH/emptyparser.out" 2>&1; echo $? >"$SCRATCH/emptyparser.rc" )
[ "$(cat "$SCRATCH/emptyparser.rc")" = 2 ] && grep -q "manifest_section" "$SCRATCH/emptyparser.out" &&
	pass "a module that defines nothing stops the gate with exit 2, naming the function" ||
	{ fail "with an empty module the gate exited $(cat "$SCRATCH/emptyparser.rc") — expected 2"; sed 's/^/        | /' "$SCRATCH/emptyparser.out" | head -5; }

t_done "manifest parser"
}
# shellcheck disable=SC1090
. "$ROOT/$MODULE"
command -v manifest_section >/dev/null 2>&1 && pass "sourcing defines manifest_section" ||
	{ fail "sourcing $MODULE does not define manifest_section"; t_done "manifest parser"; }
manifest_section files <"$ROOT/VERSION" | grep -qx "$MODULE" && pass "$MODULE is manifest-listed (shared layer)" ||
	fail "$MODULE is not in VERSION's files: — a consumer's gate would source a file it does not have"

# ---------------------------------------------------------------------------
banner "1. The grammar, one fixture at a time"
# ---------------------------------------------------------------------------
FIX="$SCRATCH/VERSION"
cat >"$FIX" <<'EOF'
# a manifest — comments precede the sections
shared-layer: 9.9.9

files:
  constitution/shared-invariants.md
  # a comment inside the list
  scripts/check.sh   trailing annotation on a files entry

  scripts/agents.lib.sh
not-indented-line-ends-the-list
  tests/should-not-appear.sh

skills:
  # a comment inside the skills list
  diagnose

  dogfood            optional — bootstrap asks; declining is a recorded choice
  tdd
notes:
  not-a-skill
EOF

out=$(manifest_section files <"$FIX")
expect='constitution/shared-invariants.md
scripts/check.sh
scripts/agents.lib.sh'
[ "$out" = "$expect" ] && pass "files: entries, one name per line, first word only, comments and blanks skipped, list ends at the first unindented line" ||
	{ fail "files: parse differs from the expected list"; printf '%s\n' "$out" | sed 's/^/        | /'; }

out=$(manifest_section skills <"$FIX")
expect='diagnose
dogfood
tdd'
[ "$out" = "$expect" ] && pass "skills: entries through the same grammar — the annotation is not part of the name" ||
	{ fail "skills: parse differs from the expected list"; printf '%s\n' "$out" | sed 's/^/        | /'; }

# The two sections never bleed into each other.
manifest_section files <"$FIX" | grep -q '^diagnose$' &&
	fail "a skills: entry leaked into the files: list" ||
	pass "files: does not contain skills: entries"
manifest_section skills <"$FIX" | grep -q 'check.sh' &&
	fail "a files: entry leaked into the skills: list" ||
	pass "skills: does not contain files: entries"

# An absent section is an empty list, not an error — the recipe relies on
# "no skills: manifest at this ref" being a silence it can test for.
printf 'shared-layer: 1.0.0\nfiles:\n  a/b.sh\n' | manifest_section skills >"$SCRATCH/absent"
[ ! -s "$SCRATCH/absent" ] && pass "an absent section prints nothing and exits 0" || fail "an absent section printed something"

# A malformed section name is a caller bug: exit 2, nothing printed.
manifest_section 'Files' </dev/null >"$SCRATCH/bad.out" 2>"$SCRATCH/bad.err"; bad_rc=$?
[ "$bad_rc" = 2 ] && [ ! -s "$SCRATCH/bad.out" ] && pass "a capitalised section name exits 2 with nothing on stdout" ||
	fail "a capitalised section name exited $bad_rc (expected 2) — the guard is a no-op under this locale"

# Tabs are indentation too.
printf 'files:\n\tscripts/x.sh\n' | manifest_section files | grep -qx 'scripts/x.sh' &&
	pass "a tab-indented entry is an entry" || fail "a tab-indented entry was not read"

# The kit's own manifest, both sections, non-empty and plausible.
kit_files=$(manifest_section files <"$ROOT/VERSION" | grep -c .)
kit_skills=$(manifest_section skills <"$ROOT/VERSION" | grep -c .)
[ "$kit_files" -ge 10 ] && pass "the kit's files: list has $kit_files entries" || fail "the kit's files: list read $kit_files entries"
[ "$kit_skills" -ge 15 ] && pass "the kit's skills: list has $kit_skills entries" || fail "the kit's skills: list read $kit_skills entries"
manifest_section files <"$ROOT/VERSION" | while IFS= read -r f; do
	[ -e "$ROOT/$f" ] || fail "manifest lists $f but it does not exist — the parser or the manifest is wrong"
done

# ---------------------------------------------------------------------------
banner "2. The recipe's own copies match the module's grammar"
# ---------------------------------------------------------------------------
# UPDATING.md must stay self-contained: it runs in a consumer at an older
# release, with only sh and git, where the local scripts/ is the OLD copy. So
# its parsers are not replaced — they are held equal. Extract the fenced sh
# block containing each awk, run it over the fixture with `kit show` stubbed,
# and compare with the module byte for byte.
fence_containing() {
	awk -v pat="$1" '
		/^```sh$/       { grab = 1; buf = ""; hit = 0; next }
		grab && /^```$/ { grab = 0; if (hit) { printf "%s", buf; exit } next }
		grab            { buf = buf $0 "\n"; if (index($0, pat) > 0) hit = 1 }
	' "$ROOT/UPDATING.md"
}
kit() { cat "$FIX"; }   # the recipe's `kit show <ref>:VERSION`, stubbed to the fixture
export FIX

fence_containing '^files:' >"$SCRATCH/recipe.files.sh"
[ -s "$SCRATCH/recipe.files.sh" ] && pass "found the recipe's files: parser fence" || fail "the recipe's files: parser fence is unfindable"
# The fence defines manifest() and may run other steps; source only the function.
awk '/^manifest\(\) \{/,/^\}/' "$SCRATCH/recipe.files.sh" >"$SCRATCH/recipe.manifest.sh"
# shellcheck disable=SC1090
. "$SCRATCH/recipe.manifest.sh"
recipe_out=$(manifest any-ref)
module_out=$(manifest_section files <"$FIX")
[ "$recipe_out" = "$module_out" ] && pass "the recipe's files: parser and the module agree on the fixture" ||
	{ fail "the recipe's files: parser DIFFERS from the module:"; printf '%s\n' "recipe: $recipe_out" "module: $module_out" | sed 's/^/        | /'; }

fence_containing '^skills:' >"$SCRATCH/recipe.skills.sh"
[ -s "$SCRATCH/recipe.skills.sh" ] && pass "found the recipe's skills: parser fence" || fail "the recipe's skills: parser fence is unfindable"
# Run only the pipeline that produces the manifest list: from `kit show` to the sort.
WORK="$SCRATCH/work"; mkdir -p "$WORK"; export WORK; TO_REF=any; export TO_REF
awk '/^kit show/,/skills\.manifest"$/' "$SCRATCH/recipe.skills.sh" >"$SCRATCH/recipe.skills.pipe.sh"
# shellcheck disable=SC1090
. "$SCRATCH/recipe.skills.pipe.sh"
recipe_skills=$(cat "$WORK/skills.manifest")
module_skills=$(manifest_section skills <"$FIX" | sort)
[ "$recipe_skills" = "$module_skills" ] && pass "the recipe's skills: parser and the module agree on the fixture" ||
	{ fail "the recipe's skills: parser DIFFERS from the module:"; printf '%s\n' "recipe: $recipe_skills" "module: $module_skills" | sed 's/^/        | /'; }

# ---------------------------------------------------------------------------
banner "3. The copies are gone — one grammar, sourced"
# ---------------------------------------------------------------------------
# Repo-wide, not a hand-kept list: the only file allowed to carry the awk's
# section matchers is the recipe, and it carries exactly two.
carriers=$(cd "$ROOT" && git grep -l -E '/\^(files|skills):/' -- . ':!worktree' 2>/dev/null || true)
[ "$carriers" = "UPDATING.md" ] && pass "the only file carrying an inline manifest parser is UPDATING.md" ||
	{ fail "inline manifest parsers survive outside the recipe:"; printf '%s\n' "$carriers" | sed 's/^/        | /'; }
copies=$(grep -c -E '/\^(files|skills):/' "$ROOT/UPDATING.md")
[ "$copies" = 2 ] && pass "UPDATING.md keeps exactly its two self-contained copies" ||
	fail "UPDATING.md has $copies parser copies, expected 2 (files: and skills:)"

# ---------------------------------------------------------------------------
banner "4. The roster helper in the shared harness"
# ---------------------------------------------------------------------------
command -v t_assert_skill_in_roster >/dev/null 2>&1 && pass "tests/lib.sh defines t_assert_skill_in_roster" ||
	fail "tests/lib.sh does not define t_assert_skill_in_roster — each skill suite clones the roster block instead"
for s in tests/design-brief-skill.test.sh tests/housekeeping-skill.test.sh; do
	grep -q 't_assert_skill_in_roster' "$ROOT/$s" && pass "$s uses the roster helper" || fail "$s does not use the roster helper"
done

t_done "manifest parser"
