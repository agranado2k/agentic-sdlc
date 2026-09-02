#!/bin/sh
# tests/design-brief-skill.test.sh — the /design-brief contract, checked as TEXT.
#
# The skill is a document an agent obeys, so what makes it internally
# consistent is machine-checkable: it names the three anchors the engineering
# article stamps, the design-it-twice discipline and the complexity criterion
# it compares on, the human stop that precedes every write, the decision
# record it produces, and its two entry points; every slash command it names
# resolves to a skill on disk and every repo path it names is real, templated,
# or installed by bootstrap; its frontmatter uses only the fields the Agent
# Skills specification defines; and the harness bridge symlink resolves.
#
# NOT simulable here, and deliberately not faked: a real design brief needs a
# real brief and a human saying yes. The ticket's demo — invoke it on the kit,
# see two candidates, say no, see nothing on disk change — is run by hand and
# quoted in the delivering PR. What IS asserted is the text that drives it.
#
# Usage: sh tests/design-brief-skill.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"

SKILL=".agents/skills/design-brief/SKILL.md"
SKILL_ABS="$ROOT/$SKILL"
SIDECAR=".agents/skills/design-brief/BRIEF-FORMAT.md"

cd "$ROOT" || exit 2

# Code spans outside fenced blocks, one token per line — the same reading the
# other skill suites use.
skill_spans() {
	for f in "$SKILL_ABS" "$ROOT/$SIDECAR"; do
		[ -f "$f" ] || continue
		awk '/^[ \t]*(```|~~~)/ { fence = !fence; next } !fence { print }' "$f"
	done | grep -o '`[^`]*`' | tr -d '`' | tr ' \t' '\n\n'
}

# ---------------------------------------------------------------------------
banner "0. The files under test"
# ---------------------------------------------------------------------------
[ -f "$SKILL_ABS" ] && pass "$SKILL exists" || {
	fail "$SKILL is missing — nothing else in this suite means anything"
	t_done "/design-brief contract"
}
[ -f "$ROOT/$SIDECAR" ] && pass "$SIDECAR exists — the shapes the brief writes live beside the procedure" ||
	fail "$SIDECAR is missing — the skill has nowhere to keep the shapes it writes"
if [ -L "$ROOT/.claude/skills/design-brief" ] && [ -f "$ROOT/.claude/skills/design-brief/SKILL.md" ]; then
	pass "the harness bridge symlink resolves to the canonical skill"
else
	fail "no resolving symlink at .claude/skills/design-brief — the harness that reads only that address is blind to it"
fi

# ---------------------------------------------------------------------------
banner "1. Frontmatter: the open standard's fields, nothing harness-specific"
# ---------------------------------------------------------------------------
keys=$(awk 'NR == 1 { next } /^---/ { exit } /^[a-z_-]+:/ { sub(/:.*/, ""); print }' "$SKILL_ABS")
for k in $keys; do
	case "$k" in
	name | description | license | compatibility | metadata | allowed-tools) ;;
	*) fail "frontmatter key '$k' is not one the Agent Skills specification defines — the kit ships vendor-neutral skills" ;;
	esac
done
printf '%s\n' "$keys" | grep -qx name && pass "frontmatter carries name" || fail "frontmatter lacks name"
printf '%s\n' "$keys" | grep -qx description && pass "frontmatter carries description" || fail "frontmatter lacks description"
desc_len=$(awk '/^description:/ { sub(/^description: */, ""); print length($0); exit }' "$SKILL_ABS")
[ "${desc_len:-0}" -le 1024 ] && pass "description is $desc_len chars, within the specification's 1024" ||
	fail "description is $desc_len chars — the specification caps it at 1024"

# ---------------------------------------------------------------------------
banner "2. It records the three anchors the engineering article stamps"
# ---------------------------------------------------------------------------
for anchor in 'Paradigm' 'Architectural style' 'Context map'; do
	assert_file_has "$SKILL" "**$anchor**:"
done
assert_file_has "$SKILL" "none — "

# ---------------------------------------------------------------------------
banner "3. Design it twice, compared on complexity — and a recommendation, not a menu"
# ---------------------------------------------------------------------------
assert_file_has "$SKILL" "esign it twice"
assert_file_has "$SKILL" "dependencies"
assert_file_has "$SKILL" "obscurity"
assert_file_has "$SKILL" "over-application"
assert_file_has "$SKILL" "core"
assert_file_has "$SKILL" "supporting"
assert_file_has "$SKILL" "generic"
assert_file_has "$SKILL" "from both sides"

# ---------------------------------------------------------------------------
banner "4. The human stop precedes every write"
# ---------------------------------------------------------------------------
assert_file_has "$SKILL" "before writing anything"
assert_file_has "$SKILL" "nothing on disk"
# The stop must come BEFORE the recording step in the procedure's order.
stop_line=$(grep -n "before writing anything" "$SKILL_ABS" | head -1 | cut -d: -f1)
record_line=$(grep -n "^### .*Record" "$SKILL_ABS" | head -1 | cut -d: -f1)
if [ -n "$stop_line" ] && [ -n "$record_line" ] && [ "$stop_line" -lt "$record_line" ]; then
	pass "the stop (line $stop_line) precedes the Record step (line $record_line)"
else
	fail "the stop does not precede the Record step — stop='$stop_line' record='$record_line'"
fi

# ---------------------------------------------------------------------------
banner "5. The decision record, the coexistence clause, and the two entry points"
# ---------------------------------------------------------------------------
assert_file_has "$SKILL" "decision record"
assert_file_has "$SKILL" "test-driven development"
assert_file_has "$SKILL" "hand-back"
assert_file_has "$SKILL" "housekeeping"
assert_file_has "$SKILL" "/improve-codebase-architecture"
# Strategic means Ousterhout here, and the skill says so where a reader meets
# the word first.
assert_file_has "$SKILL" "Ousterhout"
assert_file_has "$SKILL" "context map"

# ---------------------------------------------------------------------------
banner "6. It never lands anything"
# ---------------------------------------------------------------------------
assert_file_lacks "$SKILL" "gh pr merge" "the brief records; it never merges"
assert_file_lacks "$SKILL" "git push" "the brief records; delivery is /implement's"

# ---------------------------------------------------------------------------
banner "7. Every slash command the skill names resolves to a skill on disk"
# ---------------------------------------------------------------------------
# Mirrors `claudeMdRefs.ignoreCommands` in scripts/docs-conformance/config.mjs:
# real commands that are not repo skills, and command-shaped paths.
is_ignored() {
	case "$1" in
	/loop | /security-review | /review | /init | /tmp | /codebase-design) return 0 ;;
	esac
	return 1
}
resolved=0
for cmd in $(skill_spans | grep '^[([{"]*/[a-z]' | grep -o '/[a-z][a-z0-9-]*' | sort -u); do
	is_ignored "$cmd" && continue
	if [ -f ".agents/skills/${cmd#/}/SKILL.md" ]; then
		resolved=$((resolved + 1))
	else
		fail "$SKILL names $cmd but .agents/skills/${cmd#/}/SKILL.md does not exist"
	fi
done
[ "$resolved" -ge 2 ] &&
	pass "all $resolved slash commands in the skill resolve" ||
	fail "only $resolved commands resolved — the skill should name at least /to-tickets and /improve-codebase-architecture"

# ---------------------------------------------------------------------------
banner "8. Every repo path the skill names is real, templated, or installed"
# ---------------------------------------------------------------------------
path_verdict() {
	p=$1
	[ -e "$ROOT/$p" ] && { echo "exists in this tree"; return 0; }
	[ -e "$ROOT/$p.template" ] && { echo "shipped as $p.template"; return 0; }
	grep -F -- "$p" "$ROOT/bootstrap.sh" | grep -qv '^KIT_ONLY=' &&
		{ echo "installed by bootstrap.sh"; return 0; }
	return 1
}
checked=0
for tok in $(skill_spans | sed 's/[),.;:]*$//' | grep -v '[<>*$]' | grep '/' | sort -u); do
	case "$tok" in
	constitution/* | scripts/* | docs/* | tests/* | adapters/* | templates/* | .githooks/* | .github/* | .agents/* | .claude/*) ;;
	*) continue ;;
	esac
	checked=$((checked + 1))
	if why=$(path_verdict "$tok"); then
		pass "$tok — $why"
	else
		fail "$SKILL names $tok, which is a dead reference in every consumer project"
	fi
done
[ "$checked" -ge 3 ] && pass "$checked repo paths checked" ||
	fail "only $checked repo paths found — the skill should name the article, the glossary and the decision records"

# ---------------------------------------------------------------------------
banner "9. The roster knows the skill"
# ---------------------------------------------------------------------------
awk '/^skills:/ { inlist = 1; next } !inlist { next } /^[ \t]+[^ \t#]/ { print $1; next } /^[^ \t]/ { inlist = 0 }' "$ROOT/VERSION" |
	grep -qx design-brief && pass "VERSION's skills manifest names design-brief" ||
	fail "VERSION's skills manifest does not name design-brief — no consumer will ever be told it exists"
grep -q '`/design-brief`' "$ROOT/constitution/AGENTS.md.template" &&
	pass "the consumer manual template names /design-brief" ||
	fail "the consumer manual template never names /design-brief — a stamped project cannot find it"
grep -q 'design-brief' "$ROOT/.agents/skills/LICENSE-mattpocock-skills.md" &&
	pass "the provenance file accounts for design-brief" ||
	fail "the provenance file does not account for design-brief"

t_done "/design-brief contract"
