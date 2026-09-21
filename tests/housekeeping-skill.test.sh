#!/bin/sh
# tests/housekeeping-skill.test.sh — the /housekeeping contract, checked as TEXT.
#
# The skill is a checklist an agent obeys. What is machine-checkable: every
# item names its source; the two routes (a module-level red flag to the
# architecture skill, a style-level one back to the brief) are present; the
# never-fix rule and the one permitted write (the diary stamp) are stated;
# the pass is documented as planner-tier work; frontmatter uses only the
# fields the Agent Skills specification defines; every slash command and
# repo path it names resolves; the bridge symlink resolves; the roster knows
# the skill.
#
# NOT simulable here: the pass itself, which reads a whole repo and spawns a
# scan. The ticket's demo — run it on the kit, see the tdd sidecar's ASCII
# diagrams filed as a candidate ticket and not fixed, see the diary row
# dated today — is run by hand and quoted in the delivering PR.
#
# Usage: sh tests/housekeeping-skill.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"

SKILL=".agents/skills/housekeeping/SKILL.md"
SKILL_ABS="$ROOT/$SKILL"
SIDECAR=".agents/skills/housekeeping/CHECKLIST.md"
SIDECAR_ABS="$ROOT/$SIDECAR"

cd "$ROOT" || exit 2

# ---------------------------------------------------------------------------
banner "0. The files under test"
# ---------------------------------------------------------------------------
[ -f "$SKILL_ABS" ] && pass "$SKILL exists" || {
	fail "$SKILL is missing — nothing else in this suite means anything"
	t_done "/housekeeping contract"
}
[ -f "$SIDECAR_ABS" ] && pass "$SIDECAR exists — the items in full live beside the order" ||
	fail "$SIDECAR is missing"
if [ -L "$ROOT/.claude/skills/housekeeping" ] && [ -f "$ROOT/.claude/skills/housekeeping/SKILL.md" ]; then
	pass "the harness bridge symlink resolves to the canonical skill"
else
	fail "no resolving symlink at .claude/skills/housekeeping"
fi

# ---------------------------------------------------------------------------
banner "1. Frontmatter: the open standard's fields, nothing harness-specific"
# ---------------------------------------------------------------------------
t_assert_skill_frontmatter "$(dirname "$SKILL_ABS")"

# ---------------------------------------------------------------------------
banner "2. Every checklist item names its source"
# ---------------------------------------------------------------------------
# Eight items, eight sources, in the skill's own order.
# Only the checklist section counts — the procedure below it numbers its
# steps too.
checklist() { awk '/^## The checklist/ { on = 1; next } /^## / { on = 0 } on' "$SKILL_ABS"; }
items=$(checklist | grep -c '^[1-8]\. \*\*')
[ "$items" = 8 ] && pass "the checklist has eight numbered items" || fail "the checklist has $items numbered items, not eight"
sources=$(checklist | grep -c '\*Source:')
[ "$sources" -ge 8 ] && pass "every item carries a *Source:* line ($sources)" || fail "only $sources *Source:* lines for eight items"
assert_file_has "$SKILL" "Audit your Agent files"
assert_file_has "$SKILL" "shared invariant §11"
assert_file_has "$SKILL" "shared invariant §9"
assert_file_has "$SKILL" "Ousterhout"
assert_file_has "$SKILL" "/worktree-cleanup"
# The sidecar carries the items in full, each with the same source line.
sidecar_sources=$(grep -c '^\*Source:' "$SIDECAR_ABS")
[ "$sidecar_sources" -ge 8 ] && pass "the sidecar states a source for each of the eight items" ||
	fail "the sidecar states only $sidecar_sources sources"
# Item 5 also reports the dispatch scratch a dead dispatch left on the host
# (#210): the dispatcher sweeps what is past the sweep age, and the pass
# LISTS what is there — each directory by name and age — not only a count,
# because #210 says "lists what it found" and a count cannot say which.
assert_file_has "$SIDECAR" "dispatch scratch" "item 5 reports the stale dispatch scratch the dispatcher sweeps"
assert_file_has "$SIDECAR" "lists each \`agent-dispatch.*\` directory" "item 5 lists what it found, not only how many"
assert_file_has "$SIDECAR" "by name and age" "…and the listing carries what a count cannot: which, and how old"

# ---------------------------------------------------------------------------
banner "3. The red flags, and the two routes"
# ---------------------------------------------------------------------------
# The flags and the routes are held in BOTH files: the sidecar is the half
# the pass executes item by item.
for flag in 'shallow module' 'information leakage' 'temporal decomposition' 'pass-through method' 'conjoined methods' 'repetition' 'vague name'; do
	assert_file_has "$SKILL" "$flag"
done
for flag in 'Shallow module' 'Information leakage' 'Temporal decomposition' 'Pass-through method' 'Conjoined methods' 'Repetition' 'vague name'; do
	assert_file_has "$SIDECAR" "$flag"
done
for f in "$SKILL" "$SIDECAR"; do
	assert_file_has "$f" "/improve-codebase-architecture"
	assert_file_has "$f" "/design-brief"
	assert_file_has "$f" "/to-tickets"
done
# Routing is decided in the skill, in a section of its own.
grep -q '^## Routing' "$SKILL_ABS" && pass "routing has its own section" || fail "no Routing section"

# ---------------------------------------------------------------------------
banner "4. It never fixes; its one write is the stamp; the pass is planner work"
# ---------------------------------------------------------------------------
assert_file_has "$SKILL" "never fixes"
assert_file_has "$SKILL" "Last housekeeping"
assert_file_has "$SKILL" "one write"
assert_file_has "$SKILL" "planner"
for f in "$SKILL" "$SIDECAR"; do
	assert_file_lacks "$f" "gh pr merge" "the pass records; it never merges"
	assert_file_lacks "$f" "git push" "the pass records; it never pushes"
	assert_file_lacks "$f" "--force" "the pass rewrites nothing"
done
assert_file_has "$SKILL" "one delegated action"

# ---------------------------------------------------------------------------
banner "5. Every slash command the skill names resolves to a skill on disk"
# ---------------------------------------------------------------------------
# The helper reads the exemptions from the gate's policy file, never mirrored.
t_assert_skill_commands 4 "the skill should name at least /to-tickets, /worktree-cleanup, /improve-codebase-architecture and /design-brief" "$SKILL_ABS" "$SIDECAR_ABS"

# ---------------------------------------------------------------------------
banner "6. Every repo path the skill names is real, templated, or installed"
# ---------------------------------------------------------------------------
t_assert_skill_paths 4 "the skill should name the manual, the glossary, the records, the article and the diary" "$SKILL_ABS" "$SIDECAR_ABS"

# ---------------------------------------------------------------------------
banner "7. The roster knows the skill"
# ---------------------------------------------------------------------------
t_assert_skill_in_roster "housekeeping"
# The advisory that sends an agent here names the skill in its hint, and the
# brief names the pass as one of its entry points, by command now that it ships.
grep -q '/housekeeping' "$ROOT/scripts/docs-conformance/validators/housekeeping-due.mjs" &&
	pass "the housekeeping-due advisory's hint names the skill" ||
	fail "the housekeeping-due advisory never names /housekeeping — the nudge points at nothing"
grep -q '`/housekeeping`' "$ROOT/.agents/skills/design-brief/SKILL.md" &&
	pass "/design-brief names /housekeeping as an entry point" ||
	fail "/design-brief still names the pass in prose only"

t_done "/housekeeping contract"
