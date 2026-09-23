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
# references now reach outside the manual layer entirely — a forge, a hook, and
# the capability-tier config.
#
# Usage: sh tests/implement-deliver.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"

SKILL=".claude/skills/implement/SKILL.md"
SKILL_ABS="$ROOT/$SKILL"

cd "$ROOT" || exit 2

# assert_file_has / assert_file_lacks come from tests/lib.sh — same shape, one
# implementation, used here and by the AI review template suite.

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
assert_file_has "$SKILL" "## Deliver"
assert_file_has "$SKILL" "shared invariant §7"
assert_file_has "$SKILL" "one click away"
assert_file_has "$SKILL" "gh pr create"
assert_file_has "$SKILL" "git push -u origin HEAD"

# ---------------------------------------------------------------------------
banner "2. Delivery stops short of landing — no merge verb is reachable"
# ---------------------------------------------------------------------------
# Each of these would be a way to land, approve, or force a change from inside
# the session. A skill that names one has quietly renegotiated §7.
assert_file_lacks "$SKILL" "gh pr merge" "merging is the human's action (shared invariant §7)"
assert_file_lacks "$SKILL" "--auto" "auto-merge is a merge with a delay, not a non-merge"
assert_file_lacks "$SKILL" "--admin" "an admin override bypasses the very gate §7 protects"
assert_file_lacks "$SKILL" "--force" "delivery never rewrites a pushed branch"
assert_file_lacks "$SKILL" "--no-verify" "the pre-push hook is the gate, not an obstacle"
assert_file_lacks "$SKILL" "pr review --approve" "an author approving its own PR is not review"

# ---------------------------------------------------------------------------
banner "3. The review request is mechanism-ORDERED: forge workflows first"
# ---------------------------------------------------------------------------
# The order is the ticket's decision, and it is load-bearing: only the workflow
# leg runs where the secrets are, so only it can reach a different vendor. If a
# later edit flips these, the skill still reads fine and the cross-provider leg
# has silently become the fallback — which is exactly what this asserts against.
a=$(line_of "(a) Forge review workflows")
# Matched on the bold LABEL, never on the prose after it: this asserts where
# the mechanism sits and what it is called, so an editorial change to its
# sentence must not fail it. Bare `(b)` is not enough — it appears earlier in
# the file.
b=$(line_of "**(b)")
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
assert_file_has "$SKILL" "different vendor"
assert_file_has "$SKILL" "different model tier"
# The rule itself, and the case that defeats a plain tier lookup (#144): the
# session implemented on the model the reviewer tier maps to, so the reviewer
# is resolved through a domain that names that situation. Consumer-correct:
# the skill names the command and the domain, never a model.
assert_file_has "$SKILL" "the reviewer is never the model that implemented"
assert_file_has "$SKILL" "sh scripts/agents.lib.sh reviewer self-implemented"
assert_file_has "$SKILL" "fresh context"

# ---------------------------------------------------------------------------
banner "3b. The review is INVOKED by name, and lands on the PR"
# ---------------------------------------------------------------------------
# Three ways a session has actually skipped this step, each closed by one
# assertion. (1) It went from opening the PR straight to reporting done: the
# step has to read as an imperative, not as background on two mechanisms.
# (2) It wrote its own review prompt instead of invoking the skill, and got
# prose back rather than the two axes /review-pr exists to separate. (3) It
# ran a reviewer that reported to the SESSION, so the findings were acted on
# but the PR carried no review at all — the human arrives at a diff with
# nothing on it, which is indistinguishable from never having reviewed.
assert_file_has "$SKILL" "invoke \`/review-pr\`"
assert_file_has "$SKILL" "Not a review prompt of your own"
assert_file_has "$SKILL" "A review that reported only to you is not a review"
assert_file_has "$SKILL" "posted on the PR"
# The report names where the review landed, so its absence is conspicuous
# rather than something the reader has to think to check.
assert_file_has "$SKILL" "the URL of the review it posted"
# And the step is an ordered part of Deliver, not an aside: it must come after
# the PR is opened and before the skill stops.
_open=$(line_of "Open the pull request")
_review=$(line_of "invoke \`/review-pr\`")
_stop=$(line_of "**Stop.**")
if [ -n "$_open" ] && [ -n "$_review" ] && [ -n "$_stop" ] &&
	[ "$_open" -lt "$_review" ] && [ "$_review" -lt "$_stop" ]; then
	pass "the invocation sits between opening the PR (line $_open) and stopping (line $_stop)"
else
	fail "the review invocation is out of order — open='$_open' invoke='$_review' stop='$_stop'"
fi

# ---------------------------------------------------------------------------
banner "4. The tier config the skill sends the agent to actually exists"
# ---------------------------------------------------------------------------
# The skill tells the agent to read `scripts/agents.config.sh` to pick the
# reviewer's model tier. That file ships in this kit, so the reference either
# resolves or the skill is wrong — the tolerant "not landed yet" branches this
# check carried while the two tickets were in flight described a state that no
# longer exists, and a test that passes in a state that cannot occur is not
# testing anything.
TIER_CFG="scripts/agents.config.sh"
assert_file_has "$SKILL" "$TIER_CFG"
[ -e "$ROOT/$TIER_CFG" ] &&
	pass "$TIER_CFG exists — the skill's tier reference resolves" ||
	fail "$TIER_CFG does not exist, but the skill sends the agent to read it"

# ---------------------------------------------------------------------------
banner "5. It composes with /pr-iterate instead of duplicating it"
# ---------------------------------------------------------------------------
assert_file_has "$SKILL" "/pr-iterate"
# The iterate loop's own mechanics — thread resolution, reply endpoints, the
# poll — belong to that skill. Two skills owning one PR's review loop is how a
# comment gets answered twice and a fix gets pushed on top of itself.
assert_file_lacks "$SKILL" "resolveReviewThread" "resolving review threads is /pr-iterate's job"
assert_file_lacks "$SKILL" "comments/\$COMMENT_ID/replies" "replying to review threads is /pr-iterate's job"

# ---------------------------------------------------------------------------
banner "6. Every slash command the skill names resolves to a skill on disk"
# ---------------------------------------------------------------------------
# The helper reads the exemptions from the gate's policy file, never mirrored.
t_assert_skill_commands 3 "the skill should name at least /tdd, /review-pr and /pr-iterate" "$SKILL_ABS"

# ---------------------------------------------------------------------------
banner "7. Every repo path the skill names is real, templated, installed, or conditional"
# ---------------------------------------------------------------------------
# A skill is copied into a project VERBATIM, so it may legitimately name paths
# the kit itself does not carry — a file bootstrap stamps, or a template's
# stamped name. Those are the exemptions, and each is checkable rather than
# assumed. Anything outside them is a dead reference in every consumer project.
t_assert_skill_paths 4 "the extraction is probably broken, not the skill" "$SKILL_ABS"

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
