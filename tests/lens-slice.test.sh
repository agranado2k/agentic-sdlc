#!/bin/sh
# tests/lens-slice.test.sh — self-tests for scripts/lens-slice.sh, the slicer
# that hands each /review-pr standards lens only the part of the diff its path
# rules select, and the behavior axis the whole diff.
#
# Like behavior-delta, the slicer's whole job is reading git, so every case
# builds a REAL throwaway repository and runs the kit's script against it: the
# shipped policy (scripts/lens-slice.config.sh) over three fixture diffs —
# scripts-only, tests-only, mixed — then a retuned policy, a missing one, and
# the refusals.
#
# Usage: sh tests/lens-slice.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
SLICER="$KIT/scripts/lens-slice.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

LENSES='security api-crud pattern simplicity reuse-dry test-hygiene'

# slice <repo> <out> [env…] — run the kit's slicer in <repo> against main.
slice() {
	_sl_repo=$1
	_sl_out=$2
	shift 2
	t_run env "$@" sh -c 'cd "$1" && sh "$2" main "$3"' _ "$_sl_repo" "$SLICER" "$_sl_out"
}

# files_in <diff file> — the b/ paths a diff file carries, one per line, sorted.
files_in() { sed -n 's|^diff --git a/.* b/||p' "$1" | sort | tr '\n' ' ' | sed 's/ $//'; }

assert_slice() {
	# $1 out dir, $2 lens, $3 expected space-separated sorted paths ('' = empty)
	if [ ! -f "$1/$2.diff" ]; then
		fail "$2: no slice file written"
		return
	fi
	_as_got=$(files_in "$1/$2.diff")
	if [ "$_as_got" = "$3" ]; then
		pass "$2 slice = [${3}]"
	else
		fail "$2 slice — expected [$3], got [$_as_got]"
	fi
}

# A repo with one file in every lane on main, so a branch modifies, never adds.
base_repo() {
	t_repo
	t_write "$REPO" scripts/tool.sh 'echo one
'
	t_write "$REPO" .githooks/pre-push 'exit 0
'
	t_write "$REPO" tests/tool.test.sh 'sh scripts/tool.sh
'
	t_write "$REPO" tests/fixtures/run.jsonl '{"a":1}
'
	t_write "$REPO" docs/guide.md 'guide
'
	t_commit "$REPO" "chore: base" >/dev/null
	git -C "$REPO" checkout -q -b feat/x
}

banner "scripts-only diff: security and api-crud see it, test-hygiene sees nothing"
base_repo
t_write "$REPO" scripts/tool.sh 'echo two
'
t_write "$REPO" .githooks/pre-push 'exit 1
'
# A name the rule's escaped dot must NOT match: `bootstrap\.sh$` is literal.
t_write "$REPO" bootstrapxsh 'x
'
t_commit "$REPO" "feat: scripts" >/dev/null
OUT="$SCRATCH/out1"
slice "$REPO" "$OUT"
[ "$LAST_STATUS" = 0 ] && pass "exit 0" || fail "exit $LAST_STATUS: $LAST_OUT"
assert_slice "$OUT" security ".githooks/pre-push scripts/tool.sh"
assert_slice "$OUT" api-crud ".githooks/pre-push scripts/tool.sh"
assert_slice "$OUT" test-hygiene ""
assert_slice "$OUT" pattern ".githooks/pre-push bootstrapxsh scripts/tool.sh"
assert_slice "$OUT" behavior ".githooks/pre-push bootstrapxsh scripts/tool.sh"
assert_out_has "test-hygiene 0 $OUT/test-hygiene.diff"
assert_out_has "security 2 $OUT/security.diff"

banner "tests-only diff: test-hygiene sees the test, never the generated fixture"
base_repo
t_write "$REPO" tests/tool.test.sh 'sh scripts/tool.sh --flag
'
t_write "$REPO" tests/fixtures/run.jsonl '{"a":2}
'
t_commit "$REPO" "test: tests" >/dev/null
OUT="$SCRATCH/out2"
slice "$REPO" "$OUT"
assert_slice "$OUT" test-hygiene "tests/tool.test.sh"
assert_slice "$OUT" security ""
assert_slice "$OUT" api-crud ""
for l in pattern simplicity reuse-dry; do assert_slice "$OUT" "$l" "tests/tool.test.sh"; done
assert_slice "$OUT" behavior "tests/fixtures/run.jsonl tests/tool.test.sh"

banner "mixed diff: each lens its lane, the behavior axis everything"
base_repo
t_write "$REPO" scripts/tool.sh 'echo three
'
t_write "$REPO" tests/tool.test.sh 'sh scripts/tool.sh three
'
t_write "$REPO" tests/fixtures/run.jsonl '{"a":3}
'
t_write "$REPO" docs/guide.md 'guide, revised
'
t_commit "$REPO" "feat: mixed" >/dev/null
OUT="$SCRATCH/out3"
slice "$REPO" "$OUT"
assert_slice "$OUT" security "scripts/tool.sh"
assert_slice "$OUT" api-crud "scripts/tool.sh"
assert_slice "$OUT" test-hygiene "tests/tool.test.sh"
for l in pattern simplicity reuse-dry; do
	assert_slice "$OUT" "$l" "docs/guide.md scripts/tool.sh tests/tool.test.sh"
done
assert_slice "$OUT" behavior "docs/guide.md scripts/tool.sh tests/fixtures/run.jsonl tests/tool.test.sh"
git -C "$REPO" diff "$(git -C "$REPO" merge-base main HEAD)" HEAD >"$SCRATCH/whole.diff"
if cmp -s "$OUT/behavior.diff" "$SCRATCH/whole.diff"; then pass "behavior.diff is the whole diff, byte for byte"; else fail "behavior.diff differs from the whole diff"; fi

banner "a retuned policy is data: a consumer's rules, no skill edit"
cat >"$SCRATCH/policy.sh" <<'EOF'
LENS_SLICE_RULES='security ^docs/
test-hygiene ^tests/'
EOF
OUT="$SCRATCH/out4"
slice "$REPO" "$OUT" LENS_SLICE_CONFIG="$SCRATCH/policy.sh"
assert_slice "$OUT" security "docs/guide.md"
assert_slice "$OUT" test-hygiene "tests/fixtures/run.jsonl tests/tool.test.sh"
assert_slice "$OUT" api-crud "docs/guide.md scripts/tool.sh tests/fixtures/run.jsonl tests/tool.test.sh"

banner "no policy: every lens gets the whole diff, and the slicer says so"
printf '' >"$SCRATCH/empty.sh"
OUT="$SCRATCH/out5"
slice "$REPO" "$OUT" LENS_SLICE_CONFIG="$SCRATCH/empty.sh"
[ "$LAST_STATUS" = 0 ] && pass "exit 0" || fail "exit $LAST_STATUS"
for l in $LENSES; do
	assert_slice "$OUT" "$l" "docs/guide.md scripts/tool.sh tests/fixtures/run.jsonl tests/tool.test.sh"
done
assert_out_has "no rules"

banner "refusals: exit 2, nothing sliced"
cat >"$SCRATCH/typo.sh" <<'EOF'
LENS_SLICE_RULES='securty ^scripts/'
EOF
OUT="$SCRATCH/out6"
slice "$REPO" "$OUT" LENS_SLICE_CONFIG="$SCRATCH/typo.sh"
[ "$LAST_STATUS" = 2 ] && pass "an unknown lens is refused (exit 2)" || fail "unknown lens: exit $LAST_STATUS"
assert_out_has "securty"
[ -e "$OUT/security.diff" ] && fail "a refused policy still wrote slices" || pass "a refused policy writes no slice"
slice "$REPO" "$SCRATCH/out7" LENS_SLICE_CONFIG="$SCRATCH/no-such.sh"
[ "$LAST_STATUS" = 2 ] && pass "a named policy that is absent is refused (exit 2)" || fail "absent named policy: exit $LAST_STATUS"
t_run sh -c 'cd "$1" && sh "$2" main' _ "$REPO" "$SLICER"
[ "$LAST_STATUS" = 2 ] && pass "a missing out dir is a caller error (exit 2)" || fail "missing out dir: exit $LAST_STATUS"
t_run sh -c 'cd "$1" && sh "$2" no-such-ref "$3"' _ "$REPO" "$SLICER" "$SCRATCH/out9"
[ "$LAST_STATUS" = 2 ] && pass "an unresolvable base is a caller error (exit 2)" || fail "bad base: exit $LAST_STATUS"

banner "/review-pr hands each worker its slice, the behavior axis the whole diff"
SKILL_DIR="$KIT/.agents/skills/review-pr"
for l in $LENSES; do
	if grep -qF "Your diff is the slice \`$l.diff\`" "$SKILL_DIR/lens-$l.md"; then
		pass "lens-$l.md names its slice"
	else
		fail "lens-$l.md does not name its slice $l.diff"
	fi
done
n=$(grep -c 'sh scripts/lens-slice.sh <base>' "$SKILL_DIR/SKILL.md")
[ "$n" = 1 ] && pass "the coordinator runs the slicer once" || fail "the coordinator names the slicer command $n times, not once"
grep -qF "beside its slice" "$SKILL_DIR/SKILL.md" && pass "lenses spawn beside their slice" || fail "lenses are not spawned beside their slice"
grep -qF "the slicer's \`behavior.diff\`, never a lens's slice" "$SKILL_DIR/SKILL.md" &&
	pass "Agent 7 reads the whole diff" || fail "Agent 7 is not handed the whole diff"

t_done "lens-slice"
