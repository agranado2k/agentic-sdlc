#!/bin/sh
# tests/policy.test.sh — self-tests for scripts/policy.sh, the policy reader:
# a judging file read as the base branch has it, failing closed, and the risk
# policy it reads the thresholds from (PRD-08 slice 1, the kit's ADR-0039).
#
# The reader's whole job is reading git's objects, so every case builds a REAL
# throwaway repository with a `main` and a branch and runs the kit's reader in
# it, asserting the exit status and the exact lines. Every fail-closed reason
# — no-base, missing, unreadable, invalid — has a fixture that produces it.
#
# Usage: sh tests/policy.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
READER="$KIT/scripts/policy.sh"
RISK="$KIT/scripts/risk.config.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

RP=scripts/risk.config.sh

# pol <repo> <args…> — run the kit's reader inside <repo>.
pol() {
	_pl_repo=$1
	shift
	t_exec sh -c 'cd "$1" && shift && sh "$@"' _ "$_pl_repo" "$READER" "$@"
}

# base_repo — main holds the SHIPPED risk policy, a guards policy, a hook, a
# workflow, the docs gate's config and a notes document; HEAD is a branch
# `work` off it with nothing changed yet.
base_repo() {
	t_repo
	mkdir -p "$REPO/scripts"
	cp "$RISK" "$REPO/$RP"
	t_write "$REPO" scripts/guards.config.sh "GUARD_SOURCE_RE='^src/'
"
	t_write "$REPO" .githooks/pre-push 'exit 0
'
	t_write "$REPO" .github/workflows/ci.yml 'on: push
'
	t_write "$REPO" scripts/docs-conformance/config.mjs 'export default {};
'
	t_write "$REPO" docs/notes.md 'notes
'
	t_commit "$REPO" "feat: base" >/dev/null
	git -C "$REPO" checkout -q -b work
}

# set_floor <file> <value> — rewrite the precision floor's assignment.
set_floor() {
	sed "s/^RISK_PRECISION_FLOOR=.*/RISK_PRECISION_FLOOR=$2/" "$1" >"$1.new" && mv "$1.new" "$1"
}

# on_main <repo> <subject> <cmd…> — run a change on main, commit it, return to work.
on_main() {
	_om_repo=$1
	_om_subj=$2
	shift 2
	git -C "$_om_repo" checkout -q main
	(cd "$_om_repo" && "$@")
	t_commit "$_om_repo" "$_om_subj" >/dev/null
	git -C "$_om_repo" checkout -q work
}

# fields_ok — every stdout line that opens fail-closed has exactly three
# fields, a reason from the closed set, and a path the test named.
fields_ok() {
	printf '%s\n' "$T_OUT" | awk -v want="$1" '
		/^fail-closed/ {
			if (NF != 3) bad = 1
			if ($2 !~ /^(no-base|missing|unreadable|invalid)$/) bad = 1
			if ($3 != want) bad = 1
			seen = 1
		}
		END { exit (bad || !seen) }'
	_t_expect $? "${2:-the fail-closed line has three fields, a closed reason and the path}" "a malformed fail-closed line"
}

banner "R15. The risk policy ships filled: 5, 80, no extra path"
# ---------------------------------------------------------------------------
assert_file "$RISK"
t_exec sh -c '. "$1" && printf "%s|%s|%s\n" "$RISK_MISS_RATE_BELOW" "$RISK_PRECISION_FLOOR" "${RISK_JUDGING_EXTRA-unset}"' _ "$RISK"
expect_resolved '5|80|' "policy/R15: the shipped risk policy sets miss-rate-below 5, precision-floor 80, an empty extra list"
t_exec sh -n "$RISK"
expect_status 0 "the shipped risk policy passes sh -n"

banner "R12. thresholds at the base, whatever the branch says"
# ---------------------------------------------------------------------------
base_repo
B=$REPO
set_floor "$B/$RP" 50
t_commit "$B" "chore: lower the floor" >/dev/null
pol "$B" thresholds --base main
expect_resolved 'miss-rate-below 5
precision-floor 80' "policy/R12: thresholds --base main prints main's two lines, not the branch's 50"
pol "$B" thresholds --base work
expect_resolved 'miss-rate-below 5
precision-floor 50' "the same command at the branch reads the branch's 50"

banner "R10. touched: the judging files the diff changes, sorted, exit 1"
# ---------------------------------------------------------------------------
pol "$B" touched main HEAD
expect_status 1 "policy/R10: touched exits 1 when a judging file changed"
expect_out_is "$RP" "touched prints the risk policy"

t_write "$B" scripts/guards.config.sh "GUARD_SOURCE_RE='^lib/'
"
t_write "$B" src/a.sh 'echo a
'
t_write "$B" docs/notes.md 'changed
'
t_write "$B" .githooks/pre-commit 'exit 0
'
t_commit "$B" "chore: more" >/dev/null
pol "$B" touched main HEAD
expect_status 1 "touched exits 1 on several judging files"
expect_out_is ".githooks/pre-commit
scripts/guards.config.sh
$RP" "policy/R10: added and modified judging files, sorted; src/ and docs/ left out"

base_repo
D=$REPO
git -C "$D" rm -q "$RP"
t_commit "$D" "chore: drop the risk policy" >/dev/null
pol "$D" touched main HEAD
expect_status 1 "touched exits 1 on a deleted judging file"
expect_out_is "$RP" "policy/R10: a deleted judging file is touched"

base_repo
N=$REPO
git -C "$N" mv .github/workflows/ci.yml .github/workflows/build.yml
t_commit "$N" "chore: rename" >/dev/null
pol "$N" touched main HEAD
expect_out_is ".github/workflows/build.yml
.github/workflows/ci.yml" "policy/R10: a rename reports both its from and its to"

base_repo
Z=$REPO
t_write "$Z" docs/notes.md 'only notes
'
t_commit "$Z" "docs: notes" >/dev/null
pol "$Z" touched main HEAD
expect_resolved '' "touched prints nothing and exits 0 when no judging file changed"

banner "R1. read: a copy of the base's content, outside the working tree"
# ---------------------------------------------------------------------------
pol "$B" read "$RP" --base main
expect_status 0 "policy/R1: read of a judging file exits 0"
COPY=$T_OUT
case $COPY in
/*) pass "read prints an absolute path" ;;
*) fail "read printed a relative or empty path: [$COPY]" ;;
esac
case $COPY in
"$B"/.git/*) pass "the copy lives under the git directory" ;;
"$B"/*) fail "the copy is inside the working tree: $COPY" ;;
*) fail "the copy is not under the repository's git directory: $COPY" ;;
esac
MAIN_SHA=$(git -C "$B" rev-parse main)
case $COPY in
*/"$MAIN_SHA"/"$RP") pass "the copy sits at its repository-relative path under the base commit's directory" ;;
*) fail "the copy is not at <base commit>/$RP: $COPY" ;;
esac
if [ -f "$COPY" ] && grep -qx 'RISK_PRECISION_FLOOR=80' "$COPY"; then
	pass "the copy holds main's content (80), not the branch's (50)"
else
	fail "the copy does not hold main's precision floor"
fi
[ -z "$(git -C "$B" status --porcelain --untracked-files=all)" ] &&
	pass "read wrote nothing into the working tree" || fail "read left something in the working tree"

pol "$B" read scripts/docs-conformance/config.mjs --base main
expect_status 0 "the docs gate's config module is a judging file"
case $T_OUT in */"$MAIN_SHA"/scripts/docs-conformance/config.mjs) pass "its copy keeps its directory, so a sibling import resolves" ;; *) fail "config.mjs copy at $T_OUT" ;; esac

banner "R3, R9. A path outside the judging set: exit 2, nothing printed, no copy"
# ---------------------------------------------------------------------------
GD=$(git -C "$B" rev-parse --git-common-dir)
case $GD in /*) ;; *) GD=$B/$GD ;; esac
before=$(find "$GD" -type f | wc -l)
pol "$B" read docs/notes.md --base main
expect_status 2 "policy/R3: read docs/notes.md exits 2"
expect_out_is '' "policy/R3: nothing on stdout"
after=$(find "$GD" -type f | wc -l)
[ "$before" = "$after" ] && pass "policy/R3: no copy written" || fail "a file was written under the git directory"

base_repo
O=$REPO
mkdir -p "$O/other/scripts"
cp "$RISK" "$O/other/scripts/risk.config.sh"
t_write "$O" scripts/sub/x.config.sh 'X=1
'
t_write "$O" .githooks/sub/hook 'exit 0
'
t_commit "$O" "chore: lookalikes" >/dev/null
git -C "$O" checkout -q main && git -C "$O" merge -q --ff-only work && git -C "$O" checkout -q work
for p in other/scripts/risk.config.sh scripts/sub/x.config.sh .githooks/sub/hook ./scripts/risk.config.sh scripts/../scripts/risk.config.sh /scripts/risk.config.sh; do
	pol "$O" read "$p" --base main
	[ "$T_STATUS" = 2 ] && [ -z "$T_OUT" ] && pass "policy/R9: $p is not in the judging set (exit 2)" ||
		fail "policy/R9: $p — expected exit 2 and no stdout, got $T_STATUS [$T_OUT]"
done
for p in scripts/guards.config.sh .githooks/pre-push .github/workflows/ci.yml "$RP"; do
	pol "$O" read "$p" --base main
	expect_status 0 "policy/R9: $p is in the judging set"
done

base_repo
X=$REPO
on_main "$X" "chore: an extra judging path" sh -c "sed \"s|^RISK_JUDGING_EXTRA=.*|RISK_JUDGING_EXTRA='docs/notes.md'|\" $RP >$RP.new && mv $RP.new $RP"
pol "$X" read docs/notes.md --base main
expect_status 0 "policy/R9: a path the base's extra list names is in the judging set"
t_write "$X" docs/notes.md 'edited
'
t_commit "$X" "docs: edit notes" >/dev/null
pol "$X" touched main HEAD
expect_out_is "docs/notes.md" "touched reports a path on the base's extra list"
# The extra list is read at the base: the branch naming a path adds nothing.
base_repo
Y=$REPO
sed "s|^RISK_JUDGING_EXTRA=.*|RISK_JUDGING_EXTRA='docs/notes.md'|" "$Y/$RP" >"$Y/$RP.new" && mv "$Y/$RP.new" "$Y/$RP"
t_commit "$Y" "chore: extra on the branch" >/dev/null
pol "$Y" read docs/notes.md --base main
expect_status 2 "policy/R9: an extra path the branch adds is not read at the base"

# The software factory's project manifest is a judging file (process/R227):
# where it holds a value a judge reads, a branch may not change it for itself.
base_repo
FM=$REPO
on_main "$FM" "chore: a factory manifest" sh -c "mkdir -p .factory && printf 'id: f\\nacceptance_tests_since: 2026-11-01\\n' >.factory/project.yaml"
pol "$FM" read .factory/project.yaml --base main
expect_status 0 "policy/R9: the factory's project manifest is in the judging set"
t_write "$FM" .factory/project.yaml 'id: f
acceptance_tests_since: 2030-01-01
'
t_write "$FM" .factory/items/T-01/ticket.md 'x
'
t_commit "$FM" "chore: move the date" >/dev/null
pol "$FM" touched main HEAD
expect_status 1 "touched exits 1 when the manifest changed"
expect_out_is ".factory/project.yaml" "policy/R9: touched reports the manifest, and no other .factory/ file"
pol "$FM" read .factory/items/T-01/ticket.md --base main
expect_status 2 "policy/R9: a factory item is not in the judging set"

banner "R5, R2. Missing at the base: fail closed, no copy, the branch's copy unread"
# ---------------------------------------------------------------------------
base_repo
M=$REPO
on_main "$M" "chore: main loses its risk policy" git rm -q "$RP"
[ -f "$M/$RP" ] && pass "the branch's risk policy is present in the working tree" || fail "fixture: the branch lost its risk policy"
before=$(find "$(git -C "$M" rev-parse --absolute-git-dir)" -path '*/policy/*' -type f | wc -l)
pol "$M" read "$RP" --base main
expect_status 3 "policy/R5: read of a judging file missing at the base exits 3"
expect_out_is "fail-closed missing $RP" "policy/R5: the one fail-closed missing line"
fields_ok "$RP"
after=$(find "$(git -C "$M" rev-parse --absolute-git-dir)" -path '*/policy/*' -type f | wc -l)
[ "$before" = "$after" ] && pass "policy/R5: no copy written" || fail "a copy was written for a missing file"
pol "$M" thresholds --base main
expect_status 3 "thresholds exits 3 when main has no risk policy"
expect_out_is "fail-closed missing $RP" "policy/R2: thresholds does not fall back to the branch's copy"

banner "R4. An unfetched base: no-base"
# ---------------------------------------------------------------------------
pol "$B" read "$RP" --base origin/main
expect_status 3 "policy/R4: a ref naming no commit exits 3"
expect_out_is "fail-closed no-base $RP" "policy/R4: fail-closed no-base and the path"
fields_ok "$RP"
pol "$B" thresholds --base deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
expect_out_is "fail-closed no-base $RP" "thresholds at an unknown commit is no-base"

banner "R6. A non-regular entry: unreadable"
# ---------------------------------------------------------------------------
base_repo
U=$REPO
on_main "$U" "chore: a symlink and a directory" sh -c 'ln -s ../docs/notes.md scripts/link.config.sh && mkdir -p scripts/dir.config.sh && echo x >scripts/dir.config.sh/f'
for p in scripts/link.config.sh scripts/dir.config.sh; do
	pol "$U" read "$p" --base main
	expect_status 3 "policy/R6: $p exits 3"
	expect_out_is "fail-closed unreadable $p" "policy/R6: $p is unreadable"
done

banner "R7, R13. Invalid at the base: a syntax error, a threshold out of shape"
# ---------------------------------------------------------------------------
base_repo
V=$REPO
on_main "$V" "chore: break it" sh -c "printf 'if then\n' >>$RP"
pol "$V" read "$RP" --base main
expect_status 3 "policy/R7: a shell judging file that fails sh -n exits 3"
expect_out_is "fail-closed invalid $RP" "policy/R7: fail-closed invalid"
pol "$V" thresholds --base main
expect_out_is "fail-closed invalid $RP" "thresholds on a syntax error is invalid"
for v in eighty "''" 120 -1 08 '"80 "' '"$(echo 80)x"'; do
	base_repo
	W=$REPO
	on_main "$W" "chore: floor $v" set_floor "$RP" "$v"
	pol "$W" thresholds --base main
	expect_status 3 "policy/R13: precision-floor=$v exits 3"
	expect_out_is "fail-closed invalid $RP" "policy/R13: precision-floor=$v prints only the invalid line, no threshold"
done
base_repo
W=$REPO
on_main "$W" "chore: unset miss rate" sh -c "sed '/^RISK_MISS_RATE_BELOW=/d' $RP >$RP.new && mv $RP.new $RP"
pol "$W" thresholds --base main
expect_out_is "fail-closed invalid $RP" "policy/R13: an unset miss-rate-below is invalid"
for v in 0 100; do
	base_repo
	W=$REPO
	on_main "$W" "chore: floor $v" set_floor "$RP" "$v"
	pol "$W" thresholds --base main
	expect_resolved "miss-rate-below 5
precision-floor $v" "precision-floor=$v is in range"
done

banner "R8. A fail-closed line carries nothing read from a file"
# ---------------------------------------------------------------------------
base_repo
H=$REPO
on_main "$H" "chore: hostile" sh -c "printf 'echo INJECTED\nRISK_PRECISION_FLOOR=\"80 INJECTED\"\n' >>$RP"
pol "$H" thresholds --base main
expect_out_is "fail-closed invalid $RP" "policy/R8: the policy's own output and value never reach stdout"
expect_unsaid INJECTED "policy/R8: nothing the file printed or held reaches either stream"
fields_ok "$RP" "policy/R8: exactly three fields"
base_repo
H=$REPO
on_main "$H" "chore: chatty" sh -c "printf 'echo CHATTY\necho CHATTY >&2\n' >>$RP"
pol "$H" thresholds --base main
expect_resolved 'miss-rate-below 5
precision-floor 80' "policy/R12: a policy that prints still yields exactly the two lines"
expect_unsaid CHATTY "policy/R8: what the policy prints reaches neither stream"

banner "R11. touched while the risk policy fails closed at the base"
# ---------------------------------------------------------------------------
base_repo
T=$REPO
on_main "$T" "chore: break the risk policy" sh -c "printf 'if then\n' >>$RP"
t_write "$T" scripts/guards.config.sh "GUARD_SOURCE_RE=''
"
t_write "$T" .githooks/pre-push 'exit 1
'
t_commit "$T" "chore: loosen" >/dev/null
pol "$T" touched main HEAD
expect_status 3 "policy/R11: touched exits 3 when the risk policy fails closed"
expect_out_is ".githooks/pre-push
scripts/guards.config.sh
fail-closed invalid $RP" "policy/R11: the other touched paths first, then the fail-closed line"
pol "$T" touched nosuchref HEAD
expect_status 3 "touched with an unknown base fails closed"
expect_out_is "fail-closed no-base $RP" "touched names the risk policy as what it could not read"

banner "R14. A judging file is evaluated only in a child process"
# ---------------------------------------------------------------------------
base_repo
E=$REPO
on_main "$E" "chore: a busy risk policy" sh -c "printf 'cd /\nPATH=/nonexistent\nbase=HEAD\ncommit=0000\ngit() { echo hijack; }\nexport LEAKED=1\n' >>$RP"
t_exec sh -c '
	cd "$1" || exit 9
	out=$(sh "$2" thresholds --base main) || exit 8
	[ "$out" = "miss-rate-below 5
precision-floor 80" ] || { echo "got: $out"; exit 7; }
	[ "$(pwd -P)" = "$(cd "$1" && pwd -P)" ] || exit 6
	[ -z "${LEAKED:-}" ] || exit 5
	command -v git >/dev/null || exit 4
	[ "$(type git 2>/dev/null | grep -c function)" = 0 ] || exit 3
	echo clean' _ "$E" "$READER"
expect_resolved clean "the caller of a policy that cds, sets variables and defines a function is unchanged (the reader is its own process; the load-bearing R14 checks are the touched line below and the clobber cases further down)"
t_write "$E" .githooks/pre-push 'exit 2
'
t_commit "$E" "chore: hook" >/dev/null
pol "$E" touched main HEAD
expect_out_is ".githooks/pre-push" "policy/R14: touched still reads git after the policy's own PATH and function"

banner "Run from a subdirectory, paths stay repository-relative (review M-1)"
# ---------------------------------------------------------------------------
pol "$B/scripts" thresholds --base main
expect_resolved 'miss-rate-below 5
precision-floor 80' "policy/R12: thresholds from scripts/ reads the risk policy at the repository's root"
pol "$B/scripts" read .githooks/pre-push --base main
expect_status 0 "policy/R1: read from a subdirectory takes a repository-relative path"

banner "A diff the reader cannot compute fails closed (review M-2)"
# ---------------------------------------------------------------------------
base_repo
R=$REPO
git -C "$R" checkout -q --orphan stray
git -C "$R" rm -rq --cached . >/dev/null
t_write "$R" .githooks/pre-push 'exit 1
'
git -C "$R" add .githooks/pre-push
git -C "$R" commit -q -m "chore: unrelated history"
pol "$R" touched main HEAD
expect_status 3 "policy/R10: touched with no merge base exits 3, never 2"
expect_out_is "fail-closed no-base $RP" "policy/R8: the closed shape, naming the risk policy"

banner "A judging path with a space is still judged"
# ---------------------------------------------------------------------------
base_repo
S=$REPO
t_write "$S" ".githooks/pre push" 'exit 0
'
t_commit "$S" "chore: a spaced hook" >/dev/null
pol "$S" touched main HEAD
expect_out_is ".githooks/pre push" "policy/R10: a judging file whose name holds a space is touched"
on_main "$S" "chore: land it" sh -c 'mkdir -p .githooks && printf "exit 0\n" >".githooks/pre push"'
pol "$S" read ".githooks/pre push" --base main
expect_status 0 "policy/R9: and read at the base"

banner "R13, R14. The caller's environment never fills a value the base lacks"
# ---------------------------------------------------------------------------
base_repo
K=$REPO
on_main "$K" "chore: drop the floor" sh -c "sed '/^RISK_PRECISION_FLOOR=/d' $RP >$RP.new && mv $RP.new $RP"
t_exec env RISK_PRECISION_FLOOR=80 RISK_MISS_RATE_BELOW=5 sh -c 'cd "$1" && sh "$2" thresholds --base main' _ "$K" "$READER"
expect_status 3 "policy/R13: an exported RISK_PRECISION_FLOOR does not stand in for the base's missing one"
expect_out_is "fail-closed invalid $RP" "policy/R13: unset at the base is invalid, whatever the environment holds"

base_repo
Q=$REPO
on_main "$Q" "chore: a policy that clobbers the reader's names" sh -c "sed \"s|^RISK_JUDGING_EXTRA=.*|RISK_JUDGING_EXTRA='docs/notes.md'|\" $RP >$RP.new && mv $RP.new $RP && printf 'COPY=/nonexistent\nRISK_POLICY=elsewhere\ncommit=0000\nstore=/nonexistent\nEXTRA=\nPATH=/nonexistent\n' >>$RP"
pol "$Q" read docs/notes.md --base main
expect_status 0 "policy/R14: read of an extra path survives a policy that sets the reader's own variable names"
QSHA=$(git -C "$Q" rev-parse main)
case $T_OUT in */"$QSHA"/docs/notes.md) pass "policy/R14: the copy is still at <base commit>/docs/notes.md" ;; *) fail "policy/R14: copy at [$T_OUT]" ;; esac
pol "$Q" thresholds --base main
expect_resolved 'miss-rate-below 5
precision-floor 80' "policy/R14: thresholds is unmoved by those names"

banner "Caller errors exit 2 with nothing on stdout"
# ---------------------------------------------------------------------------
for args in "" "read" "read $RP" "read $RP --base" "thresholds" "thresholds --base" "touched main" "frobnicate" "touched main nosuchhead"; do
	# shellcheck disable=SC2086
	pol "$B" $args
	[ "$T_STATUS" = 2 ] && [ -z "$T_OUT" ] && pass "'$args' is a caller error (exit 2, no stdout)" ||
		fail "'$args' — expected exit 2 and no stdout, got $T_STATUS [$T_OUT]"
done

t_done "policy reader"
