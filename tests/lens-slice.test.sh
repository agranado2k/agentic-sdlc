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
# A judge reads its policy at POLICY_BASE when set (ADR-0039): a run that
# inherited one would judge every fixture by a ref it does not hold.
unset POLICY_BASE LENS_SLICE_CONFIG

SKILL_DIR="$KIT/.agents/skills/review-pr"
# The six standards lenses, read from the skill's own roster — never a copy:
# the behavior agent and the two non-spawn tokens are not lenses.
LENSES=$(t_roster_of "$SKILL_DIR/SKILL.md" | grep -vx -e spec-behavior -e unattributed -e single-reviewer | tr '\n' ' ')
[ "$(printf '%s' "$LENSES" | wc -w | tr -d ' ')" = 6 ] && pass "six standards lenses on the skill's roster" ||
	fail "expected six standards lenses on the roster, read: $LENSES"

# slice <repo> <out> [env…] — run the kit's slicer in <repo> against main.
slice() {
	_sl_repo=$1
	_sl_out=$2
	shift 2
	t_exec env "$@" sh -c 'cd "$1" && sh "$2" main "$3"' _ "$_sl_repo" "$SLICER" "$_sl_out"
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
	t_write "$REPO" docs/a1.md 'one
'
	t_write "$REPO" 'docs/a[1].md' 'bracket
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
[ "$T_STATUS" = 0 ] && pass "exit 0" || fail "exit $T_STATUS: $T_OUT"
assert_slice "$OUT" security ".githooks/pre-push scripts/tool.sh"
assert_slice "$OUT" api-crud ".githooks/pre-push scripts/tool.sh"
assert_slice "$OUT" test-hygiene ""
assert_slice "$OUT" pattern ".githooks/pre-push bootstrapxsh scripts/tool.sh"
assert_slice "$OUT" behavior ".githooks/pre-push bootstrapxsh scripts/tool.sh"
expect_said "test-hygiene 0 $OUT/test-hygiene.diff"
expect_said "security 2 $OUT/security.diff"
for l in $LENSES behavior; do
	[ -f "$OUT/$l.diff" ] && pass "$l.diff written" || fail "$l.diff not written"
done

banner "a non-ASCII name and an agent-facing skill reach their slices"
base_repo
t_write "$REPO" scripts/café.sh 'echo accent
'
t_write "$REPO" .agents/skills/x/SKILL.md 'Do the thing.
'
t_commit "$REPO" "feat: names" >/dev/null
OUT="$SCRATCH/out1b"
slice "$REPO" "$OUT"
assert_slice "$OUT" security ".agents/skills/x/SKILL.md scripts/café.sh"
assert_slice "$OUT" behavior ".agents/skills/x/SKILL.md scripts/café.sh"

banner "a path with glob characters is matched literally"
base_repo
t_write "$REPO" 'docs/a[1].md' 'bracket, changed
'
t_write "$REPO" docs/a1.md 'one, changed
'
t_commit "$REPO" "docs: brackets" >/dev/null
printf '%s\n' "LENS_SLICE_RULES='security \\[1'" >"$SCRATCH/bracket.sh"
OUT="$SCRATCH/out1c"
slice "$REPO" "$OUT" LENS_SLICE_CONFIG="$SCRATCH/bracket.sh"
assert_slice "$OUT" security "docs/a[1].md"

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

banner "mixed diff: each lens its lane (spend/R10), the behavior axis everything (spend/R11)"
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
[ "$T_STATUS" = 0 ] && pass "exit 0" || fail "exit $T_STATUS"
for l in $LENSES; do
	assert_slice "$OUT" "$l" "docs/guide.md scripts/tool.sh tests/fixtures/run.jsonl tests/tool.test.sh"
done
expect_said "no rules"

banner "refusals: exit 2, nothing sliced"
cat >"$SCRATCH/typo.sh" <<'EOF'
LENS_SLICE_RULES='securty ^scripts/'
EOF
OUT="$SCRATCH/out6"
slice "$REPO" "$OUT" LENS_SLICE_CONFIG="$SCRATCH/typo.sh"
[ "$T_STATUS" = 2 ] && pass "an unknown lens is refused (exit 2)" || fail "unknown lens: exit $T_STATUS"
expect_said "securty"
assert_no_file "$OUT/security.diff"
printf '%s\n' "LENS_SLICE_RULES='security ^scripts/ x extra'" >"$SCRATCH/long.sh"
slice "$REPO" "$SCRATCH/out6b" LENS_SLICE_CONFIG="$SCRATCH/long.sh"
[ "$T_STATUS" = 2 ] && pass "a record of four fields is refused (exit 2)" || fail "four-field record: exit $T_STATUS"
assert_no_file "$SCRATCH/out6b/security.diff"
cp "$SCRATCH/policy.sh" "$REPO/bare-policy.sh"
slice "$REPO" "$SCRATCH/out6c" LENS_SLICE_CONFIG=bare-policy.sh
[ "$T_STATUS" = 0 ] && pass "a bare policy name is read from the cwd, not PATH" || fail "bare policy name: exit $T_STATUS: $T_OUT"
assert_slice "$SCRATCH/out6c" security "docs/guide.md"
slice "$REPO" "$SCRATCH/out7" LENS_SLICE_CONFIG="$SCRATCH/no-such.sh"
[ "$T_STATUS" = 2 ] && pass "a named policy that is absent is refused (exit 2)" || fail "absent named policy: exit $T_STATUS"
t_exec sh -c 'cd "$1" && sh "$2" main' _ "$REPO" "$SLICER"
[ "$T_STATUS" = 2 ] && pass "a missing out dir is a caller error (exit 2)" || fail "missing out dir: exit $T_STATUS"
t_exec sh -c 'cd "$1" && sh "$2" no-such-ref "$3"' _ "$REPO" "$SLICER" "$SCRATCH/out9"
[ "$T_STATUS" = 2 ] && pass "an unresolvable base is a caller error (exit 2)" || fail "bad base: exit $T_STATUS"

banner "--areas: the review areas each path on stdin belongs to, by the same rules (runtime/R45, #875)"
# The trace's record reader counts a landing toward every review area a path
# of it belongs to, and asks the slicer rather than reading the policy itself:
# one parser of LENS_SLICE_RULES. Each lens names itself on a line of its own
# first (`<lens><TAB>`), in roster order, so an area no path belongs to is
# still an area; then one `<lens><TAB><path>` per pair the rules select.
areas() { t_exec env "$@" sh -c 'printf "scripts/a.sh\ntests/a.test.sh\ntests/fixtures/x.jsonl\ndocs/g.md\n" | sh "$1" --areas' _ "$SLICER"; }
TAB=$(printf '\t')
areas LENS_SLICE_CONFIG="$SCRATCH/policy.sh"
[ "$T_STATUS" = 0 ] && pass "--areas exits 0" || fail "--areas exited $T_STATUS: $T_ERR"
want="security$TAB
api-crud$TAB
pattern$TAB
simplicity$TAB
reuse-dry$TAB
test-hygiene$TAB
security${TAB}docs/g.md
api-crud${TAB}scripts/a.sh
api-crud${TAB}tests/a.test.sh
api-crud${TAB}tests/fixtures/x.jsonl
api-crud${TAB}docs/g.md
pattern${TAB}scripts/a.sh
pattern${TAB}tests/a.test.sh
pattern${TAB}tests/fixtures/x.jsonl
pattern${TAB}docs/g.md
simplicity${TAB}scripts/a.sh
simplicity${TAB}tests/a.test.sh
simplicity${TAB}tests/fixtures/x.jsonl
simplicity${TAB}docs/g.md
reuse-dry${TAB}scripts/a.sh
reuse-dry${TAB}tests/a.test.sh
reuse-dry${TAB}tests/fixtures/x.jsonl
reuse-dry${TAB}docs/g.md
test-hygiene${TAB}tests/a.test.sh
test-hygiene${TAB}tests/fixtures/x.jsonl"
[ "$T_OUT" = "$want" ] && pass "every lens named first, then each path in the areas its rule selects — a lens with no rule takes every path" ||
	fail "--areas printed: $(printf '%s' "$T_OUT" | tr '\t\n' '>;')"
areas
printf '%s\n' "$T_OUT" | grep -qxF "security${TAB}scripts/a.sh" && ! printf '%s\n' "$T_OUT" | grep -qxF "test-hygiene${TAB}tests/fixtures/x.jsonl" &&
	pass "the shipped policy's exclude holds: a generated fixture is in no test-hygiene area" ||
	fail "--areas under the shipped policy printed: $(printf '%s' "$T_OUT" | tr '\t\n' '>;')"
areas LENS_SLICE_CONFIG="$SCRATCH/typo.sh"
[ "$T_STATUS" = 2 ] && [ -z "$T_OUT" ] && pass "--areas refuses a policy the slicer refuses, printing nothing" || fail "--areas over a typo policy: exit $T_STATUS, out $T_OUT"
t_exec sh "$SLICER" --areas extra
[ "$T_STATUS" = 2 ] && pass "--areas takes no argument (exit 2)" || fail "--areas with an argument: exit $T_STATUS"

# ---------------------------------------------------------------------------
banner "Judged by the base's lens-slice policy — POLICY_BASE (ADR-0039, PRD-08 slice 4)"
# ---------------------------------------------------------------------------
# A pull request must not narrow the lens that reads it. With POLICY_BASE
# naming a ref, the slicer reads the lens-slice policy through the policy
# reader at that ref; unset, the working tree's copy, as before.

# own_repo — a fixture carrying its own slicer, its loader, the reader and the
# shipped policy on main; the branch `pr` narrows security to exclude scripts/
# and changes scripts/land.kit.sh. Sets REPO; leaves `pr` checked out.
own_repo() {
	t_repo
	mkdir -p "$REPO/scripts"
	cp "$SLICER" "$KIT/scripts/guards.lib.sh" "$KIT/scripts/policy.sh" "$KIT/scripts/lens-slice.config.sh" "$REPO/scripts/"
	t_write "$REPO" scripts/land.kit.sh 'echo land
'
	t_commit "$REPO" "chore: base" >/dev/null
	git -C "$REPO" checkout -q -b pr
	t_write "$REPO" scripts/lens-slice.config.sh "LENS_SLICE_RULES='security ^nothing/'
"
	t_write "$REPO" scripts/land.kit.sh 'echo landed
'
	t_commit "$REPO" "feat: narrow security and change a script" >/dev/null
}

# own_slice <out> [env…] — the fixture's own slicer, run in it against main.
own_slice() {
	_os_out=$1
	shift
	t_exec env "$@" sh -c 'cd "$1" && sh scripts/lens-slice.sh main "$2"' _ "$REPO" "$_os_out"
}

own_repo
own_slice "$SCRATCH/pb1" POLICY_BASE=main
[ "$T_STATUS" = 0 ] && pass "policy/R26: the slicer exits 0 reading main's policy" || fail "POLICY_BASE=main slice: exit $T_STATUS, err $T_ERR"
case " $(files_in "$SCRATCH/pb1/security.diff") " in
*" scripts/land.kit.sh "*) pass "policy/R26: the security slice holds scripts/land.kit.sh — main's rule, not the branch's" ;;
*) fail "policy/R26: the security slice lacks scripts/land.kit.sh: [$(files_in "$SCRATCH/pb1/security.diff")]" ;;
esac
own_slice "$SCRATCH/pb2"
case " $(files_in "$SCRATCH/pb2/security.diff") " in
*" scripts/land.kit.sh "*) fail "policy/R16: unset, the branch's narrowed policy should hide the script from security" ;;
*) pass "policy/R16: with POLICY_BASE unset the working tree's (narrowed) policy is read" ;;
esac
own_slice "$SCRATCH/pb3" POLICY_BASE=main LENS_SLICE_CONFIG=scripts/lens-slice.config.sh
case " $(files_in "$SCRATCH/pb3/security.diff") " in
*" scripts/land.kit.sh "*) pass "policy/R17: an override naming the judging file is read at the base" ;;
*) fail "policy/R17: the override was read from the working tree" ;;
esac
own_slice "$SCRATCH/pb4" POLICY_BASE=main LENS_SLICE_CONFIG="$SCRATCH/typo.sh"
[ "$T_STATUS" = 2 ] && pass "policy/R17: an override outside the repository is read as given (here: refused, a typo policy)" ||
	fail "an outside override under POLICY_BASE: exit $T_STATUS"

# UC4 2a: no lens-slice policy at main — every lens gets the whole diff, exit 3.
git -C "$REPO" checkout -q main
git -C "$REPO" rm -q scripts/lens-slice.config.sh
git -C "$REPO" commit -q -m "chore: drop the policy"
git -C "$REPO" checkout -q pr
own_slice "$SCRATCH/pb5" POLICY_BASE=main
[ "$T_STATUS" = 3 ] && pass "policy/R27: main with no lens-slice policy exits 3" || fail "policy/R27: exit $T_STATUS, err $T_ERR"
printf '%s\n' "$T_OUT" | grep -qx 'fail-closed missing scripts/lens-slice.config.sh' &&
	pass "policy/R27: it prints the fail-closed line" || fail "policy/R27: no fail-closed line on stdout: $T_OUT"
whole=$(files_in "$SCRATCH/pb5/behavior.diff")
[ -n "$whole" ] || fail "policy/R27: the behavior slice is empty"
_r27=ok
for l in $LENSES; do
	[ "$(files_in "$SCRATCH/pb5/$l.diff")" = "$whole" ] || _r27="$l"
done
[ "$_r27" = ok ] && pass "policy/R27: every lens's slice is the whole diff [$whole]" || fail "policy/R27: the $_r27 slice is not the whole diff"
own_slice "$SCRATCH/pb6" POLICY_BASE=no-such-ref
[ "$T_STATUS" = 3 ] && printf '%s\n' "$T_OUT" | grep -qx 'fail-closed no-base scripts/lens-slice.config.sh' &&
	pass "a POLICY_BASE that names no commit fails closed (exit 3)" || fail "POLICY_BASE=no-such-ref: exit $T_STATUS, out $T_OUT"

# Standing in a repository that is not the slicer's own, no override, is the
# strictest path too: the base of a foreign repository is not this slicer's policy.
own_repo
slice "$REPO" "$SCRATCH/pb7" POLICY_BASE=main
[ "$T_STATUS" = 3 ] && pass "a foreign repository's base, no override, fails closed (exit 3)" || fail "foreign base: exit $T_STATUS, err $T_ERR"

areas POLICY_BASE=no-such-ref
[ "$T_STATUS" = 0 ] && pass "--areas ignores POLICY_BASE: it reads the working tree, unchanged" || fail "--areas under POLICY_BASE: exit $T_STATUS"

banner "/review-pr hands each lens its slice (spend/R10), the behavior axis the whole diff (spend/R11)"
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
