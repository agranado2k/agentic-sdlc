#!/bin/sh
# tests/factory-config.test.sh — the kit's configuration reads in a factory
# project: a value the factory also defines is read from the factory's key in
# its project manifest, and the kit's own policy file is read for it only in a
# repository that is not a factory project, for a value the kit defines
# there (PRD-12 slice 4, process/R226 and
# process/R227, the kit's ADR-0040).
#
# The shared read is `sh scripts/policy.sh value <name> [--base <ref>]`. Today
# one value has a factory key, the acceptance-test adoption date, so every case
# here holds the read on that date: the manifest's `acceptance_tests_since`,
# and nothing outside a factory project: the date has no kit-side home.
# Every case builds a REAL throwaway repository: a factory project is the
# manifest's presence at the git top level, and the base read is git's objects.
#
# Usage: sh tests/factory-config.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
READER="$KIT/scripts/policy.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

MF=.factory/project.yaml
GP=scripts/guards.config.sh
NAME=acceptance-tests-since

# pol <repo> <args…> — run the kit's reader inside <repo>.
pol() {
	_pl_repo=$1
	shift
	t_exec sh -c 'cd "$1" && shift && sh "$@"' _ "$_pl_repo" "$READER" "$@"
}

# manifest <date-line> — a factory manifest whose adoption line is <date-line>.
manifest() {
	printf 'id: fixture\nname: fixture\nrepo: .\n%s\nstages:\n  ticket: [proposed, ready, build, review, qa, done]\n' "$1"
}

# factory_repo — main holds a manifest dated 2026-11-01 and a guards policy
# that sets a date of its own (2025-01-01), which is never read; HEAD is a
# branch `work` off it.
factory_repo() {
	t_repo
	t_write "$REPO" "$MF" "$(manifest 'acceptance_tests_since: 2026-11-01')
"
	t_write "$REPO" "$GP" "GUARD_SOURCE_RE='^src/'
GUARD_ACCEPTANCE_TESTS_SINCE=2025-01-01
"
	t_commit "$REPO" "feat: base" >/dev/null
	git -C "$REPO" checkout -q -b work
}

# plain_repo — the same fixture without the manifest.
plain_repo() {
	t_repo
	t_write "$REPO" "$GP" "GUARD_SOURCE_RE='^src/'
GUARD_ACCEPTANCE_TESTS_SINCE=2025-01-01
"
	t_commit "$REPO" "feat: base" >/dev/null
	git -C "$REPO" checkout -q -b work
}

# set_manifest <repo> <date-line> — rewrite the working tree's manifest.
set_manifest() {
	t_write "$1" "$MF" "$(manifest "$2")
"
}

banner "R226. In a factory project the manifest's value wins, the working tree with no base"
# ---------------------------------------------------------------------------
factory_repo
F=$REPO
pol "$F" value "$NAME"
expect_resolved "$NAME 2026-11-01" "process/R226: with no base, the manifest's date, not the guards policy's"
set_manifest "$F" 'acceptance_tests_since: 2026-12-24'
pol "$F" value "$NAME"
expect_resolved "$NAME 2026-12-24" "process/R226: with no base, the working tree's manifest is read"
mkdir -p "$F/sub/dir"
t_exec sh -c 'cd "$1" && sh "$2" value "$3"' _ "$F/sub/dir" "$READER" "$NAME"
expect_resolved "$NAME 2026-12-24" "the read is the git top level's, from any subdirectory"
set_manifest "$F" "acceptance_tests_since: '2026-12-24'  # quoted, with a comment"
pol "$F" value "$NAME"
expect_resolved "$NAME 2026-12-24" "a quoted date with a trailing comment reads as the date"
set_manifest "$F" 'acceptance_tests_since: 2026-12-24'

banner "R227. With a base, the manifest is read at the base ref"
# ---------------------------------------------------------------------------
t_commit "$F" "chore: move the date on the branch" >/dev/null
pol "$F" value "$NAME" --base main
expect_resolved "$NAME 2026-11-01" "process/R227: at --base main, main's manifest date, not the branch's"
pol "$F" value "$NAME" --base work
expect_resolved "$NAME 2026-12-24" "at --base work, the branch's date"

# The base is git's objects: an uncommitted edit changes nothing there.
set_manifest "$F" 'acceptance_tests_since: 2027-01-01'
pol "$F" value "$NAME" --base main
expect_resolved "$NAME 2026-11-01" "process/R227: an uncommitted manifest edit is not read at the base"

# A branch that deletes the manifest still has the base's manifest read: it
# cannot make itself a non-factory project and fall back to the kit's policy.
factory_repo
DEL=$REPO
git -C "$DEL" rm -q "$MF"
t_commit "$DEL" "chore: drop the manifest" >/dev/null
pol "$DEL" value "$NAME" --base main
expect_resolved "$NAME 2026-11-01" "process/R227: a branch deleting the manifest is still read from the base's manifest"

banner "R226. Without the manifest, no adoption date: nothing printed, never a kit file"
# ---------------------------------------------------------------------------
# Only a factory project has an adoption date (PRD-14 §8, the operator's
# ruling of 2026-10-31): a repository with no manifest owes nothing, and the
# guards policy's GUARD_ACCEPTANCE_TESTS_SINCE, set in this fixture, is never
# read — the value has no kit-side home.
plain_repo
P=$REPO
pol "$P" value "$NAME"
expect_resolved "" "process/R226: no manifest, nothing printed (exit 0), the guards policy unread"
pol "$P" value "$NAME" --base main
expect_resolved "" "process/R226: no manifest at the base or the head, nothing printed (exit 0)"

# A stray .factory/ folder with no manifest is not a factory project.
mkdir -p "$P/.factory/items"
t_write "$P" .factory/items/note.md 'x
'
pol "$P" value "$NAME"
expect_resolved "" "process/R226: a .factory/ folder without the manifest is no factory project"

# The caller's environment never stands in for a missing home.
t_exec env GUARD_ACCEPTANCE_TESTS_SINCE=2020-01-01 sh -c 'cd "$1" && sh "$2" value "$3" --base work' _ "$P" "$READER" "$NAME"
expect_resolved "" "a caller's exported GUARD_ACCEPTANCE_TESTS_SINCE is not read at the base"
t_exec env GUARD_ACCEPTANCE_TESTS_SINCE=2020-01-01 sh -c 'cd "$1" && sh "$2" value "$3"' _ "$P" "$READER" "$NAME"
expect_resolved "" "nor in the working tree"

factory_repo
UM=$REPO
set_manifest "$UM" 'acceptance_tests_since:'
pol "$UM" value "$NAME"
expect_resolved "$NAME unset" "a manifest key written with no value: unset"
set_manifest "$UM" 'other: 1'
pol "$UM" value "$NAME"
expect_resolved "$NAME unset" "a manifest without the key: unset, never the guards policy's date"

banner "R227. At the base, an absent manifest or a malformed value fails closed"
# ---------------------------------------------------------------------------
# A branch that makes the repository a factory project: the base has no
# manifest, so the base cannot say, and the kit's policy is not a fallback.
plain_repo
A=$REPO
set_manifest "$A" 'acceptance_tests_since: 2026-11-01'
t_commit "$A" "feat: adopt the factory" >/dev/null
pol "$A" value "$NAME" --base main
[ "$T_STATUS" = 3 ] && [ "$T_OUT" = "fail-closed missing $MF" ] &&
	pass "process/R227: an absent manifest at the base fails closed (exit 3), no fallback" ||
	fail "absent manifest at the base — expected exit 3 'fail-closed missing $MF', got $T_STATUS [$T_OUT]"

for bad in 'acceptance_tests_since: 2026-13-01' 'acceptance_tests_since: 2026-02-30' \
	'acceptance_tests_since: tomorrow' 'acceptance_tests_since: 2026-11-01 extra' \
	"acceptance_tests_since: 2026-11-01
acceptance_tests_since: 2026-11-02"; do
	factory_repo
	M=$REPO
	git -C "$M" checkout -q main
	set_manifest "$M" "$bad"
	t_commit "$M" "chore: a malformed date" >/dev/null
	git -C "$M" checkout -q work
	git -C "$M" merge -q --ff-only main
	pol "$M" value "$NAME" --base main
	[ "$T_STATUS" = 3 ] && [ "$T_OUT" = "fail-closed invalid $MF" ] &&
		pass "process/R227: '$bad' at the base fails closed invalid (exit 3)" ||
		fail "'$bad' at the base — expected exit 3 'fail-closed invalid $MF', got $T_STATUS [$T_OUT]"
	pol "$M" value "$NAME"
	[ "$T_STATUS" = 3 ] && [ "$T_OUT" = "fail-closed invalid $MF" ] &&
		pass "'$bad' in the working tree fails closed too" ||
		fail "'$bad' in the working tree — expected exit 3, got $T_STATUS [$T_OUT]"
done

pol "$F" value "$NAME" --base nosuchref
[ "$T_STATUS" = 3 ] && [ "$T_OUT" = "fail-closed no-base $MF" ] &&
	pass "a base naming no commit fails closed no-base" ||
	fail "no-base — expected exit 3 'fail-closed no-base $MF', got $T_STATUS [$T_OUT]"

banner "Caller errors: exit 2, nothing on stdout"
# ---------------------------------------------------------------------------
for args in "value" "value no-such-value" "value $NAME --base" "value $NAME --since main" "value $NAME --base main extra"; do
	# shellcheck disable=SC2086
	pol "$F" $args
	[ "$T_STATUS" = 2 ] && [ -z "$T_OUT" ] && pass "'$args' is a caller error (exit 2, no stdout)" ||
		fail "'$args' — expected exit 2 and no stdout, got $T_STATUS [$T_OUT]"
done

t_done "factory configuration reads"
