#!/bin/sh
# tests/gate-path-roots.test.sh — the docs gate's two engines agree on their
# path roots, and this suite is what holds them to it.
#
# The harness reads `claudeMdRefs.pathRoots` from the policy file; the
# reduced POSIX form in scripts/check.sh carries its own copy, because it
# runs where there is no runtime to read the policy with. Two copies of one
# policy drift, and they had: the wrapper admitted all of `.agents` and
# `.claude` where the harness admitted four subtrees, so a reference the
# harness ignored could fail the fallback and vice versa. The harness's list
# is the truth. Three sections: the lists are equal; the comparison can go
# red (two baits); and a reference under a subtree only one engine admitted
# before is judged identically by both, on a bootstrapped project.
#
# Usage: sh tests/gate-path-roots.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
cd "$ROOT" || exit 2
t_init

# wrapper_roots <check.sh> — the fallback's list, one per line, sorted.
wrapper_roots() {
	sed -n "s/^[^#]*path_roots='\(.*\)'$/\1/p" "$1" | tr ' ' '\n' | grep . | sort
}
# policy_roots <config.mjs> — the harness's list, one per line, sorted. No
# node here on purpose: the suite must run where the fallback runs.
policy_roots() {
	awk '/^[[:space:]]*pathRoots: \[/ { inlist = 1; next } inlist && /^[[:space:]]*\],?/ { exit } inlist { print }' "$1" |
		sed 's/^[[:space:]]*"//; s/",\{0,1\}[[:space:]]*$//' | grep . | sort
}
# roots_diff <check.sh> <config.mjs> — empty when the two lists are equal,
# else the entries each side holds alone.
roots_diff() {
	_w=$(wrapper_roots "$1"); _p=$(policy_roots "$2")
	[ "$_w" = "$_p" ] && return 0
	_wo=""; for _r in $_w; do printf '%s\n' "$_p" | grep -qxF -- "$_r" || _wo="$_wo $_r"; done
	_po=""; for _r in $_p; do printf '%s\n' "$_w" | grep -qxF -- "$_r" || _po="$_po $_r"; done
	printf 'wrapper only:%s; policy only:%s' "$_wo" "$_po"
}

# ---------------------------------------------------------------------------
banner "1. The two lists are equal, entry for entry"
# ---------------------------------------------------------------------------
n=$(policy_roots scripts/docs-conformance/config.mjs | wc -l | tr -d ' ')
[ "$n" -ge 4 ] && pass "the policy list was read ($n roots)" || fail "the policy list could not be read from config.mjs ($n entries)"
d=$(roots_diff scripts/check.sh scripts/docs-conformance/config.mjs)
[ -z "$d" ] && pass "scripts/check.sh's path_roots equals claudeMdRefs.pathRoots" || fail "the two engines disagree on their path roots — $d"

# ---------------------------------------------------------------------------
banner "2. The comparison can go red — one side gains an entry (RED)"
# ---------------------------------------------------------------------------
W="$SCRATCH/check.sh"; P="$SCRATCH/config.mjs"
cp scripts/check.sh "$W"; cp scripts/docs-conformance/config.mjs "$P"
sed "s/^\([^#]*path_roots='.*\)'$/\1 extra-root'/" scripts/check.sh >"$W"
case "$(roots_diff "$W" "$P")" in
*"wrapper only: extra-root"*) pass "a root added to the wrapper alone is reported" ;;
*) fail "a root added to the wrapper alone went unreported" ;;
esac
awk '{ print } /^[[:space:]]*"constitution",$/ { print "    \"extra-root\"," }' scripts/docs-conformance/config.mjs >"$P"
[ -z "$(roots_diff "$W" "$P")" ] && pass "added to the other side too, the lists agree again" || fail "the lists still differ after adding the root to both: $(roots_diff "$W" "$P")"
cp scripts/check.sh "$W"
case "$(roots_diff "$W" "$P")" in
*"policy only: extra-root"*) pass "a root added to the policy alone is reported" ;;
*) fail "a root added to the policy alone went unreported" ;;
esac

# ---------------------------------------------------------------------------
banner "3. Both engines judge the same reference the same way"
# ---------------------------------------------------------------------------
# A bootstrapped project, then three references appended to its manual: a
# missing file under a subtree both engines admit (`.agents/skills`), a
# missing file under a subtree the wrapper ALONE used to admit (`.agents/x`),
# and a missing file under `.claude/hooks`. The harness and the fallback must
# return the same status for each.
PROJ="$SCRATCH/project"
here=$(pwd)
t_consumer_from "$ROOT" "$PROJ" "Roots Fixture" "roots@example.invalid" --no-dogfood "Roots Fixture" "A project that references paths."
cd "$here" || exit 2
git -C "$PROJ" config core.hooksPath .git/no-such-hooks
HAVE_NODE=0; command -v node >/dev/null 2>&1 && HAVE_NODE=1
judge() { # <token> <expected status> <label>
	printf '\nSee `%s` for the rest.\n' "$1" >>"$PROJ/AGENTS.md"
	f=$(cd "$PROJ" && DOCS_CHECK_NO_NODE=1 sh scripts/check.sh >/dev/null 2>&1; echo $?)
	[ "$f" = "$2" ] && pass "fallback: $3 (exit $f)" || fail "fallback: $3 — expected exit $2, got $f"
	if [ "$HAVE_NODE" = 1 ]; then
		h=$(cd "$PROJ" && sh scripts/check.sh >/dev/null 2>&1; echo $?)
		[ "$h" = "$f" ] && pass "harness agrees with the fallback on $3 (exit $h)" || fail "the engines disagree on $3 — harness $h, fallback $f"
	else
		printf '  skip  harness comparison for %s (no node)\n' "$3"
	fi
	git -C "$PROJ" checkout -q -- AGENTS.md
}
judge ".agents/skills/ghost/SKILL.md" 1 "a missing file under a root both engines admit"
judge ".agents/ghost/notes.md" 0 "a missing file under a subtree only the wrapper used to admit — not a checkable reference for either"
judge ".claude/hooks/ghost.sh" 1 "a missing file under .claude/hooks"

t_done "the gate's two engines agree on their path roots"
