#!/bin/sh
# F5's acceptance test — the deliberate-exclusions record.
#
# WHAT THIS CAN AND CANNOT PROVE, stated up front because the honest boundary is
# the point:
#
#   Simulable here (and checked below): EXCLUSIONS.md is a FILE, so everything
#   about the file is machine-checkable — it exists, each entry it marks
#   `(excluded)` really names a command this kit does NOT ship, each entry
#   carries a reason rather than only a name, `/ce-dogfood` is recorded as
#   optional rather than excluded, the standing rule and the origin story are in
#   the file rather than only in a pull request nobody re-reads, and the file is
#   wired as kit-authoring material (bootstrap deletes it; the shared-layer
#   manifest does not list it).
#
#   The load-bearing check is the STALENESS one, and it runs in both
#   directions: green against the real record, then red against a fixture that
#   marks a shipped skill as excluded. A record that says "we left X out" while
#   `.claude/skills/X/` sits on disk is worse than no record — it is a
#   confident, wrong answer to exactly the "decision or slip?" question this
#   file exists to answer.
#
#   NOT checkable from here, and deliberately not faked: whether a REASON is a
#   good one. Prose quality is a review judgement, not an assertion. What is
#   asserted is that every entry has one, so an empty row cannot pass as a
#   decision.
#
# Usage: sh tests/exclusions.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"

REC="EXCLUSIONS.md"
SKILLS=".claude/skills"

cd "$ROOT" || exit 2
t_init

# excluded_entries <file>
#
# The record's machine-readable surface: a level-3 heading of the exact shape
# `### /<command> (excluded)`. ASCII only and anchored at both ends on purpose —
# the parser has to survive being read in any locale, and a shape that a
# paragraph could accidentally match would make the staleness check below
# vacuous. Entries under any other heading (the `optional` section) are not
# claims of exclusion and are not parsed as one.
excluded_entries() {
	sed -n 's|^### /\([a-z][a-z0-9-]*\) (excluded)$|\1|p' "$1"
}

# stale_entries <record-file> <skills-dir>
#
# The whole point of the suite: every name the record claims is NOT shipped, but
# which IS on disk as a skill. Empty output is the only passing answer.
stale_entries() {
	for _n in $(excluded_entries "$1"); do
		[ -f "$2/$_n/SKILL.md" ] && printf '%s\n' "$_n"
	done
	return 0
}

# assert_says <file> <phrase> [<why>]
#
# `assert_file_has` from tests/lib.sh is line-based, which is right for a YAML
# key or a flag. These are PROSE assertions, and prose gets rewrapped: a check
# that goes red because a paragraph was re-flowed is testing the line breaks
# rather than the content, and the next person to widen a sentence would learn
# to distrust the suite. So fold whitespace first, then look for the phrase.
assert_says() {
	if printf '%s' "$(tr '\n' ' ' <"$1" | tr -s ' ')" | grep -qF -- "$2"; then
		pass "$1 says '$2'${3:+ ($3)}"
	else
		fail "$1 never says '$2'${3:+ — $3}"
	fi
}

# reason_for <record-file> <name> — the first non-blank line under the entry's
# heading. A heading followed by nothing, or by the next heading, has no reason.
reason_for() {
	awk -v h="### /$2 (excluded)" '
		$0 == h { found = 1; next }
		found && /^[[:space:]]*$/ { next }
		found { print; exit }
	' "$1"
}

# ---------------------------------------------------------------------------
banner "0. The record exists"
# ---------------------------------------------------------------------------
if [ -f "$REC" ]; then
	pass "$REC exists"
else
	fail "$REC is missing — nothing else in this suite means anything"
	t_done "deliberate-exclusions record"
fi

# ---------------------------------------------------------------------------
banner "1. Every entry names a command, and carries a reason"
# ---------------------------------------------------------------------------
entries=$(excluded_entries "$REC")
count=$(printf '%s\n' "$entries" | grep -c '[a-z]')
if [ "$count" -ge 3 ]; then
	pass "$count excluded entries parsed from $REC"
else
	fail "only $count excluded entries parsed — the record should name at least the three skills F5 landed with"
fi

for want in report-comments zoom-out review-and-evaluate; do
	if printf '%s\n' "$entries" | grep -qx "$want"; then
		pass "$REC records /$want as excluded"
	else
		fail "$REC never records /$want as excluded"
	fi
done

for n in $entries; do
	[ -n "$n" ] || continue
	r=$(reason_for "$REC" "$n")
	case "$r" in
	"" | "#"*) fail "/$n is listed with no reason under it — a name without a reason is not a decision" ;;
	*) pass "/$n carries a reason" ;;
	esac
done

# ---------------------------------------------------------------------------
banner "2. No stale entry — nothing marked excluded is actually shipped"
# ---------------------------------------------------------------------------
stale=$(stale_entries "$REC" "$SKILLS")
if [ -z "$stale" ]; then
	pass "every excluded entry really is absent from $SKILLS"
else
	fail "the record claims these are excluded, but they ship as skills:"
	printf '%s\n' "$stale" | sed 's/^/        | \//'
fi

# RED — the same check against a record that lies. A check that has never
# failed is a claim (shared invariant §3), and this is the one check the whole
# file is for.
FIXTURE="$SCRATCH/stale-EXCLUSIONS.md"
cat >"$FIXTURE" <<'EOF'
# A record that has gone stale

### /tdd (excluded)

Someone wrote this, then the skill shipped anyway and nobody came back.
EOF
if [ "$(stale_entries "$FIXTURE" "$SKILLS")" = "tdd" ]; then
	pass "the staleness check really fires on a record naming a shipped skill"
else
	fail "the staleness check did NOT fire on a record naming /tdd, which ships — the check is vacuous"
fi

# ---------------------------------------------------------------------------
banner "3. /ce-dogfood is recorded as optional, not excluded"
# ---------------------------------------------------------------------------
assert_says "$REC" "optional, not excluded" "dogfooding was never rejected — only the predecessor's own personas and browser wiring stayed behind"
assert_says "$REC" "#27" "the opt-in /dogfood skill is tracked, so the row stays true before and after it lands"
if printf '%s\n' "$entries" | grep -qx "ce-dogfood"; then
	fail "/ce-dogfood is marked (excluded) — it is optional, and the two are not the same record"
else
	pass "/ce-dogfood is not in the excluded set"
fi

# ---------------------------------------------------------------------------
banner "4. The standing rule and the origin story are IN the file"
# ---------------------------------------------------------------------------
# Both are the reason the file survives its first month. A rule that lives only
# in the pull request that introduced it is a rule nobody will apply on the day
# it matters (shared invariant §8).
assert_says "$REC" "in the same pull request that excludes it" "the standing rule"
assert_says "$REC" "a decision or a slip" "the origin story, in the words of the question the repo could not answer"
assert_says "$REC" "two releases" "how long the slip lasted — the detail that makes the story a fact rather than a moral"
assert_says "$REC" "improve-codebase-architecture" "the skill whose slip is why this file exists"

# ---------------------------------------------------------------------------
banner "5. Kit-authoring material — bootstrap removes it, the manifest omits it"
# ---------------------------------------------------------------------------
# The record answers "what does THIS KIT not ship". Inside a consumer project
# that sentence has no referent, so the file follows the same route as the kit's
# own tests and CI: named in KIT_ONLY, deleted with bootstrap.sh. It is not
# shared layer for the simplest possible reason — it never arrives.
assert_file_has "bootstrap.sh" "KIT_ONLY=" "the removal list"
if grep -q '^KIT_ONLY=.*EXCLUSIONS\.md' bootstrap.sh; then
	pass "EXCLUSIONS.md is in bootstrap's KIT_ONLY list"
else
	fail "EXCLUSIONS.md is not in bootstrap's KIT_ONLY list — consumers would inherit a record about a kit they do not maintain"
fi
if grep -q '^  EXCLUSIONS\.md' VERSION; then
	fail "EXCLUSIONS.md is listed under files: in VERSION — a file bootstrap deletes cannot be shared layer"
else
	pass "VERSION does not list EXCLUSIONS.md (it is deleted at bootstrap, so it cannot be copied verbatim)"
fi

# ---------------------------------------------------------------------------
banner "6. The record is reachable — README points at it"
# ---------------------------------------------------------------------------
# Same reasoning as the docs gate's article-reachability rule: a document
# nothing points at is a document nobody loads, so it rots.
assert_file_has "README.md" "EXCLUSIONS.md" "an unreferenced record is an unread record"

t_done "deliberate-exclusions record"
