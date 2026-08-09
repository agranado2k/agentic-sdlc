#!/bin/sh
# F1's acceptance test — the /implement delivery contract, checked as TEXT.
#
# WHAT THIS CAN AND CANNOT PROVE, stated up front because the honest boundary is
# the whole point of the test:
#
#   Simulable here (and checked below): the skill is a document, so everything
#   that makes the document internally consistent is machine-checkable — every
#   slash command it names resolves to a skill on disk, every repo path it names
#   is real (or templated, or installed by bootstrap, or explicitly conditional),
#   the two review mechanisms appear in the order the ticket fixed them in, the
#   §7 merge boundary is cited, and no merge/approve/auto-merge/force/bypass
#   invocation appears anywhere in it.
#
#   Simulable elsewhere, already: the push half of the Deliver phase. A real
#   `git push` through the real `.githooks/pre-push` at a real bare remote is
#   driven end to end by `tests/kit-demo.sh` (step 5) and `tests/guards-demo.sh`.
#   Not repeated here.
#
#   NOT simulable at all, and deliberately not faked: `gh pr create` against a
#   live forge, a review workflow firing on PR open, and the ticket's own demo
#   ("one ticket run ends with an open PR carrying a review, and nothing
#   merged"). Those need a real remote, real CI, and real provider credentials.
#   A mocked `gh` would only prove that the mock was called — a test that cannot
#   fail for the reason it claims to exist (shared invariant §3), so it is not
#   written. What IS asserted about that leg is the text that drives it.
#
# The docs gate does not reach this file: `scripts/docs-conformance/config.mjs`
# scopes reference checking to the manual layer (root manual + articles + nested
# manuals) and deliberately excludes `.claude/skills/**`. So the skills' own
# references need a check of their own, and this is it for the one skill whose
# references now include a forge, a hook, and a config file that does not exist
# yet.
#
# Usage: sh tests/implement-deliver.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"

SKILL=".claude/skills/implement/SKILL.md"
SKILL_ABS="$ROOT/$SKILL"

cd "$ROOT" || exit 2

# Code spans outside fenced blocks, one token per line — the same reading
# `tests/kit-demo.sh` uses on the manual, applied to a skill.
skill_spans() {
	awk '/^[ \t]*(```|~~~)/ { fence = !fence; next } !fence { print }' "$SKILL_ABS" |
		grep -o '`[^`]*`' | tr -d '`' | tr ' \t' '\n\n'
}

has() { grep -qF -- "$1" "$SKILL_ABS"; }

assert_has() {
	if has "$1"; then
		pass "the skill says '$1'"
	else
		fail "the skill never says '$1'"
	fi
}

assert_lacks() {
	if has "$1"; then
		fail "the skill contains '$1' — $2"
		grep -nF -- "$1" "$SKILL_ABS" | sed 's/^/        | /'
	else
		pass "no '$1' anywhere in the skill ($2)"
	fi
}

# line_of <literal> — first matching line number, or empty.
line_of() { grep -nF -- "$1" "$SKILL_ABS" | head -1 | cut -d: -f1; }

# ---------------------------------------------------------------------------
banner "0. The file under test"
# ---------------------------------------------------------------------------
[ -f "$SKILL_ABS" ] && pass "$SKILL exists" || {
	fail "$SKILL is missing — nothing else in this suite means anything"
	t_done "/implement delivery contract"
}

# ---------------------------------------------------------------------------
banner "1. The Deliver phase exists, and ends where shared invariant §7 says"
# ---------------------------------------------------------------------------
# The ticket's requirement is not merely "push and open a PR" — it is that the
# autonomy boundary stays visible in the text that extends autonomy.
assert_has "## Deliver"
assert_has "shared invariant §7"
assert_has "one click away"
assert_has "gh pr create"
assert_has "git push -u origin HEAD"

# ---------------------------------------------------------------------------
banner "2. Delivery stops short of landing — no merge verb is reachable"
# ---------------------------------------------------------------------------
# Each of these would be a way to land, approve, or force a change from inside
# the session. A skill that names one has quietly renegotiated §7.
assert_lacks "gh pr merge" "merging is the human's action (shared invariant §7)"
assert_lacks "--auto" "auto-merge is a merge with a delay, not a non-merge"
assert_lacks "--admin" "an admin override bypasses the very gate §7 protects"
assert_lacks "--force" "delivery never rewrites a pushed branch"
assert_lacks "--no-verify" "the pre-push hook is the gate, not an obstacle"
assert_lacks "pr review --approve" "an author approving its own PR is not review"

# ---------------------------------------------------------------------------
banner "3. The review request is mechanism-ORDERED: forge workflows first"
# ---------------------------------------------------------------------------
# The order is the ticket's decision, and it is load-bearing: only the workflow
# leg runs where the secrets are, so only it can reach a different vendor. If a
# later edit flips these, the skill still reads fine and the cross-provider leg
# has silently become the fallback — which is exactly what this asserts against.
a=$(line_of "(a) Forge review workflows")
b=$(line_of "(b) An in-harness")
if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then
	pass "forge review workflows (line $a) come before the in-harness fallback (line $b)"
else
	fail "mechanism order is wrong or unfindable — forge='$a' in-harness='$b'"
fi

if [ -n "$a" ] && sed -n "${a}p" "$SKILL_ABS" | grep -q "first-class"; then
	pass "the forge-workflow mechanism is labelled first-class"
else
	fail "the forge-workflow mechanism is not labelled first-class"
fi
if [ -n "$b" ] && sed -n "${b}p" "$SKILL_ABS" | grep -q "fallback"; then
	pass "the in-harness /review-pr mechanism is labelled the fallback"
else
	fail "the in-harness mechanism is not labelled a fallback"
fi

# The REASON has to survive too, or the order looks arbitrary to the next editor.
assert_has "different vendor"
assert_has "different model tier"
assert_has "fresh context"

# ---------------------------------------------------------------------------
banner "4. F2's tier config is referenced CONDITIONALLY — neither ticket blocks the other"
# ---------------------------------------------------------------------------
# The sibling ticket adds `scripts/agents.config.sh`. This skill may name it, but
# only in a form that reads correctly both before and after that lands. Both
# outcomes are green here, which is the property being tested: this suite does
# not care which PR merges first.
TIER_CFG="scripts/agents.config.sh"
if has "$TIER_CFG"; then
	if [ -e "$ROOT/$TIER_CFG" ]; then
		pass "$TIER_CFG has landed and the skill's reference resolves"
	elif grep -F -- "$TIER_CFG" "$SKILL_ABS" | grep -qi 'when .*exist'; then
		pass "$TIER_CFG does not exist yet, and the skill names it conditionally"
	else
		fail "$TIER_CFG is named unconditionally but does not exist — this blocks on the tier-config ticket"
	fi
else
	pass "the skill does not name a tier config (acceptable: it names no unresolvable path)"
fi

# ---------------------------------------------------------------------------
banner "5. It composes with /pr-iterate instead of duplicating it"
# ---------------------------------------------------------------------------
assert_has "/pr-iterate"
# The iterate loop's own mechanics — thread resolution, reply endpoints, the
# poll — belong to that skill. Two skills owning one PR's review loop is how a
# comment gets answered twice and a fix gets pushed on top of itself.
assert_lacks "resolveReviewThread" "resolving review threads is /pr-iterate's job"
assert_lacks "comments/\$COMMENT_ID/replies" "replying to review threads is /pr-iterate's job"

# ---------------------------------------------------------------------------
banner "6. Every slash command the skill names resolves to a skill on disk"
# ---------------------------------------------------------------------------
# Mirrors `claudeMdRefs.ignoreCommands` in scripts/docs-conformance/config.mjs —
# real commands that are deliberately not repo skills.
is_ignored() {
	case "$1" in
	/loop | /security-review | /review | /init) return 0 ;;
	esac
	return 1
}

resolved=0
for cmd in $(skill_spans | grep '^[([{"]*/[a-z]' | grep -o '/[a-z][a-z0-9-]*' | sort -u); do
	is_ignored "$cmd" && continue
	if [ -f ".claude/skills/${cmd#/}/SKILL.md" ]; then
		resolved=$((resolved + 1))
	else
		fail "$SKILL names $cmd but .claude/skills/${cmd#/}/SKILL.md does not exist"
	fi
done
[ "$resolved" -ge 3 ] &&
	pass "all $resolved slash commands in the skill resolve" ||
	fail "only $resolved commands resolved — the skill should name at least /tdd, /review-pr and /pr-iterate"

# ---------------------------------------------------------------------------
banner "7. Every repo path the skill names is real, templated, installed, or conditional"
# ---------------------------------------------------------------------------
# A skill is copied into a project VERBATIM, so it may legitimately name paths
# the kit itself does not carry — a file bootstrap stamps, or a template's
# stamped name. Those are the exemptions, and each is checkable rather than
# assumed. Anything outside them is a dead reference in every consumer project.
path_verdict() {
	p=$1
	[ -e "$ROOT/$p" ] && { echo "exists in this tree"; return 0; }
	[ -e "$ROOT/$p.template" ] && { echo "shipped as $p.template"; return 0; }
	grep -qF -- "$p" "$ROOT/bootstrap.sh" && { echo "installed by bootstrap.sh"; return 0; }
	grep -F -- "$p" "$SKILL_ABS" | grep -qi 'when .*exist' && { echo "named conditionally"; return 0; }
	return 1
}

checked=0
for tok in $(skill_spans | sed 's/[),.;:]*$//' | grep -v '[<>*$]' | grep '/' | sort -u); do
	case "$tok" in
	constitution/* | scripts/* | docs/* | tests/* | adapters/* | templates/* | .githooks/* | .github/* | .claude/*) ;;
	*) continue ;;
	esac
	checked=$((checked + 1))
	if why=$(path_verdict "$tok"); then
		pass "$tok — $why"
	else
		fail "$tok is named by $SKILL but resolves to nothing, in this tree or a bootstrapped one"
	fi
done
[ "$checked" -ge 4 ] && pass "$checked repo paths checked" ||
	fail "only $checked repo paths found — the extraction is probably broken, not the skill"

# ---------------------------------------------------------------------------
banner "8. The docs that describe /implement's ending agree with it"
# ---------------------------------------------------------------------------
# The gate enforces that every /command in the manual RESOLVES; nothing enforces
# that the row still describes what the skill does. A quick-reference row is the
# first thing an agent reads, so a stale one costs a wrong action.
row=$(grep -F 'Build one ticket' constitution/AGENTS.md.template)
case "$row" in
*PR*review*) pass "the manual's /implement quick-ref row mentions the PR and the review" ;;
*) fail "constitution/AGENTS.md.template still describes /implement as ending before the PR: $row" ;;
esac

if grep -q 'ending at' README.md && grep -qF 'delivers to the PR boundary' README.md; then
	pass "README describes /implement's ending as an open, reviewed PR"
else
	fail "README still describes the chain as if /implement ended at a commit"
fi

t_done "/implement delivery contract"
