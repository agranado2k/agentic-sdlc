#!/bin/sh
# The kit follows its own framework — and stamping still produces a clean project.
#
# Two claims, and they pull in opposite directions, which is the whole reason
# this suite exists:
#
#   A. THE KIT IS BOOTSTRAPPED. It has a root AGENTS.md written for its own
#      authoring context, the two shims beside it, the documentation set, and a
#      GREEN docs gate at its own root. A framework whose own repo cannot pass
#      the gate it ships is selling a rule it does not keep.
#
#   B. A CONSUMER STILL GETS A CLEAN PROJECT. Consumers create their repo FROM
#      this tree, so every kit-own file above is sitting in the tree bootstrap
#      runs against. Bootstrap must strip them before its idempotency check
#      would trip on them, and the stamped result must be exactly what it was
#      when the kit had none of them.
#
# (B) is asserted as byte-identity rather than as a spot-check: bootstrap runs
# twice, once against the kit tree as it really is and once against the same
# tree with the kit-own files removed by hand, and the two results must be
# identical file for file. A spot-check only finds the leaks somebody thought
# of; a diff finds the ones nobody did.
#
# Usage: sh tests/self-host.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
. "$KIT/tests/lib.sh"

t_init

PROJECT_NAME="Self Host Demo"
PROJECT_DESC="A throwaway project proving the kit strips its own files."

# The kit's own files — the ones bootstrap has to take out of a consumer's way.
# Kept here rather than derived from bootstrap.sh so the two lists can disagree
# and something notices.
KIT_OWN="AGENTS.md CLAUDE.md GEMINI.md docs/diary.md docs/domain-glossary.md docs/adr/INDEX.md .github/PULL_REQUEST_TEMPLATE.md"

# t_kit_copy <dest> — "Use this template", as tests/kit-demo.sh simulates it:
# the whole tree minus the .git dir and minus any nested worktree, which `cp -R`
# would otherwise drag along.
t_kit_copy() {
	mkdir -p "$1"
	cp -R "$KIT/." "$1/"
	strip_nested_worktrees "$KIT" "$1"
	rm -rf "$1/.git"
	git -C "$1" init -q -b main
	git -C "$1" config user.name "Self Host"
	git -C "$1" config user.email "self-host@example.invalid"
	git -C "$1" config commit.gpgsign false
	git -C "$1" config core.hooksPath .git/no-such-hooks
}

# ---------------------------------------------------------------------------
banner "A. The kit is bootstrapped — its own manual layer exists"
# ---------------------------------------------------------------------------
for f in $KIT_OWN; do
	[ -f "$KIT/$f" ] && pass "$f exists in the kit" || fail "$f is missing from the kit"
done

# The ADR that records this decision. Numbered, so a glob rather than a name:
# renumbering it is a documentation choice, having none is a framework failure.
adr_count=0
for a in "$KIT"/docs/adr/0*.md; do
	[ -f "$a" ] && adr_count=$((adr_count + 1))
done
[ "$adr_count" -ge 1 ] &&
	pass "the kit records at least one decision of its own in docs/adr/" ||
	fail "docs/adr/ holds no numbered ADR — the kit decides nothing on the record"

# The shims are shims. Same shape bootstrap writes, held to the same rule the
# gate applies to a consumer's: one import line, at most one comment.
for shim in CLAUDE.md GEMINI.md; do
	[ -f "$KIT/$shim" ] || continue
	imports=$(grep -c '^@AGENTS\.md$' "$KIT/$shim")
	other=$(grep -v '^[[:space:]]*$' "$KIT/$shim" | grep -vc -e '^@AGENTS\.md$' -e '^<!--.*-->$')
	if [ "$imports" = 1 ] && [ "$other" = 0 ]; then
		pass "$shim is a pure shim (one @AGENTS.md import, no rules of its own)"
	else
		fail "$shim is not a pure shim — $imports import line(s), $other other line(s)"
	fi
done

# The hooks path is per-clone config and cannot be committed, so the only thing
# a test can hold is that the manual TELLS a fresh clone to set it.
assert_file_has "$KIT/AGENTS.md" "git config core.hooksPath .githooks" \
	"per-clone setup — a clone that skips it pushes past both gates"

# ---------------------------------------------------------------------------
banner "B. The kit's own gate is GREEN at the kit root"
# ---------------------------------------------------------------------------
# This is the claim the whole ticket exists for. Run from the kit root, both
# engines: the harness (which alone sees shims, reachability and commands) and
# the POSIX fallback a consumer without node would get.
assert_status 0 "check.sh passes at the kit root" -- sh "$KIT/scripts/check.sh"
assert_status 0 "check.sh passes at the kit root without node" -- \
	env DOCS_CHECK_NO_NODE=1 sh "$KIT/scripts/check.sh"

# ---------------------------------------------------------------------------
banner "C. Bootstrap strips the kit's own files, and stamps a clean project"
# ---------------------------------------------------------------------------
PROJ="$SCRATCH/consumer"
t_kit_copy "$PROJ"
assert_status 0 "bootstrap runs on a tree that already holds the kit's own files" -- \
	sh -c "cd '$PROJ' && sh bootstrap.sh --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"

# The manual is the CONSUMER's, stamped from the template — not the kit's.
grep -q "$PROJECT_NAME" "$PROJ/AGENTS.md" &&
	pass "AGENTS.md carries the project name (stamped from the template)" ||
	fail "AGENTS.md was not stamped — the kit's own manual survived"
assert_file_lacks "$PROJ/AGENTS.md" "agentic-sdlc:kit-own" \
	"the kit-own sentinel must never reach a consumer"

# Nothing kit-authored leaked into the documentation set.
for a in "$PROJ"/docs/adr/0*.md; do
	[ -e "$a" ] && fail "a kit ADR leaked into the project: ${a#"$PROJ"/}"
done
[ -e "$PROJ/docs/adr/0001-the-kit-self-hosts-its-own-constitution.md" ] &&
	fail "the kit's own ADR-0001 leaked into the project" ||
	pass "no kit ADR leaked into the project"
grep -q "$PROJECT_NAME" "$PROJ/docs/diary.md" &&
	pass "docs/diary.md is the stamped starter, not the kit's diary" ||
	fail "docs/diary.md was not stamped — the kit's diary survived"
grep -q "$PROJECT_NAME" "$PROJ/docs/domain-glossary.md" &&
	pass "docs/domain-glossary.md is the stamped starter, not the kit's glossary" ||
	fail "docs/domain-glossary.md was not stamped — the kit's glossary survived"

assert_status 0 "the stamped project's gate is green" -- \
	sh -c "cd '$PROJ' && sh scripts/check.sh"

# Nothing kit-authoring survived either. `tests/` is the whole set: every suite
# is on bootstrap's KIT_ONLY list, so the directory itself must be gone — which
# is the assertion that catches a NEW suite somebody forgot to add to that list.
[ -e "$PROJ/tests" ] &&
	fail "tests/ survived bootstrap — a suite is missing from KIT_ONLY: $(ls "$PROJ/tests")" ||
	pass "tests/ is gone — every suite is on bootstrap's KIT_ONLY list"

# Idempotency is unchanged: the strip must not turn "already bootstrapped" into
# a silent re-stamp. It is guarded on the kit's own sentinel, and a stamped
# project carries neither that nor the template.
cp "$KIT/bootstrap.sh" "$PROJ/bootstrap.sh"
assert_status 1 "a second bootstrap is still refused" -- \
	sh -c "cd '$PROJ' && sh bootstrap.sh 'Other Name'"
assert_out_has "already exists"
rm -f "$PROJ/bootstrap.sh"

# ---------------------------------------------------------------------------
banner "D. The stamped result is byte-identical to a kit without kit-own files"
# ---------------------------------------------------------------------------
# The regression this ticket could most easily cause is invisible: a kit-own
# file that bootstrap forgets, quietly riding into every project made from the
# template forever after. Two runs, one diff.
BASE="$SCRATCH/baseline"
t_kit_copy "$BASE"
for f in $KIT_OWN; do rm -rf "${BASE:?}/$f"; done
rm -rf "$BASE/docs"
assert_status 0 "bootstrap runs on a tree with the kit-own files pre-removed" -- \
	sh -c "cd '$BASE' && sh bootstrap.sh --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"

rm -rf "$PROJ/.git" "$BASE/.git"
if diff -r "$BASE" "$PROJ" >"$SCRATCH/bootstrap.diff" 2>&1; then
	pass "both bootstraps produced byte-identical trees"
else
	fail "the kit's own files changed what a consumer gets"
	sed 's/^/        | /' "$SCRATCH/bootstrap.diff"
fi

t_done "self-host"
