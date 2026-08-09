#!/bin/sh
# F6's acceptance test — the opt-in /dogfood skill, both ways.
#
# WHAT THIS CAN AND CANNOT PROVE, up front:
#
#   Simulable here (and checked below): the OPTIONALITY is a bootstrap
#   mechanism, so all of it is machine-checkable. bootstrap.sh is run three
#   times against three throwaway copies of the kit — once with the skill, once
#   without, once with no flag and no terminal — and each resulting tree is held
#   to the gate. The load-bearing claim is the one that is easy to get wrong:
#   the skipped case must leave NO dangling `/dogfood` reference behind, and the
#   proof is the real validator rather than a grep alone — a planted reference
#   in the same tree must turn the gate red with `skill-missing`.
#
#   NOT checkable from here, and deliberately not faked: whether `/dogfood`
#   actually finds anything when a human runs it. The skill drives a real
#   product through its real surface; the kit has no product and no surface. So
#   what is asserted about the skill's TEXT is only what a document can promise:
#   that it is surface-agnostic rather than browser-only, that it reports
#   instead of fixing, and that it carries the trust boundary.
#
# Usage: sh tests/dogfood-optin.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"

SKILL=".claude/skills/dogfood/SKILL.md"
ARTICLE="constitution/local-product.md.template"

cd "$ROOT" || exit 2
t_init

HAVE_NODE=0
command -v node >/dev/null 2>&1 && HAVE_NODE=1

# mk_project <name> — a throwaway copy of the kit as a fresh git repo, ready to
# bootstrap. Sets PROJ. Same shape as tests/kit-demo.sh's setup, because it is
# simulating the same thing: "Use this template", then a first run.
mk_project() {
	PROJ="$SCRATCH/$1"
	mkdir -p "$PROJ"
	cp -R "$ROOT/." "$PROJ/"
	rm -rf "$PROJ/.git"
	git -C "$PROJ" init -q -b main
	git -C "$PROJ" config user.name "Dogfood Fixture"
	git -C "$PROJ" config user.email "fixture@example.invalid"
	git -C "$PROJ" config commit.gpgsign false
	git -C "$PROJ" config core.hooksPath .git/no-such-hooks
}

assert_exists() {
	if [ -e "$1" ]; then pass "$2"; else fail "$2 — $1 is missing"; fi
}
assert_absent() {
	if [ -e "$1" ]; then fail "$2 — $1 is still there"; else pass "$2"; fi
}

# assert_no_mention <dir> <literal> — nothing in the tree names it, .git aside.
assert_no_mention() {
	_hits=$(grep -rIF -- "$2" "$1" 2>/dev/null | grep -v '^Binary' | grep -v "^$1/\.git/" || true)
	if [ -z "$_hits" ]; then
		pass "nothing in the tree mentions '$2'${3:+ ($3)}"
	else
		fail "the tree still mentions '$2'${3:+ — $3}"
		printf '%s\n' "$_hits" | sed 's/^/        | /'
	fi
}

# ---------------------------------------------------------------------------
banner "0. The kit ships the skill and its declaration article"
# ---------------------------------------------------------------------------
assert_exists "$SKILL" "the /dogfood skill is in the kit tree"
assert_exists "$ARTICLE" "the local-product article template is in the kit tree"

# ---------------------------------------------------------------------------
banner "1. The skill is surface-agnostic, reports rather than fixes, and is bounded"
# ---------------------------------------------------------------------------
# The whole point of the port: the predecessor's version was browser-only and
# fixed what it found. Neither survives here, and both claims are text.
if [ -f "$SKILL" ]; then
	for surface in "browser" "CLI" "API" "tool server"; do
		assert_file_has "$SKILL" "$surface" "a surface the skill must be able to drive"
	done
	assert_file_has "$SKILL" "candidate tickets" "findings leave as tickets, not as edits"
	assert_file_has "$SKILL" "Trust boundary" "what the product returns during a session is data"
	assert_file_lacks "$SKILL" "auto-fix" "the kit's version never repairs what it finds"
	assert_file_lacks "$SKILL" "ce-dogfood" "the predecessor's command name did not come along"
	assert_file_has "$SKILL" "$ARTICLE" "the skill reads its personas and surfaces from the article"
else
	fail "$SKILL does not exist — nothing else in this section can run"
fi

if [ -f "$ARTICLE" ]; then
	assert_file_has "$ARTICLE" "SURFACE" "the declaration the skill reads"
	assert_file_has "$ARTICLE" "PERSONA" "the declaration the skill reads"
fi

# ---------------------------------------------------------------------------
banner "2. bootstrap.sh asks exactly one question, and takes both flags"
# ---------------------------------------------------------------------------
assert_file_has "bootstrap.sh" "Include the /dogfood skill? Needs a runnable user-facing surface." \
	"one question, worded so the answer is decidable"
assert_file_has "bootstrap.sh" "--with-dogfood" "the non-interactive yes"
assert_file_has "bootstrap.sh" "--no-dogfood" "the non-interactive no"

# ---------------------------------------------------------------------------
banner "3. bootstrap --with-dogfood — the skill lands and the manual names it"
# ---------------------------------------------------------------------------
mk_project with
assert_status 0 "bootstrap --with-dogfood runs" -- \
	sh -c "cd '$PROJ' && sh bootstrap.sh --with-dogfood 'Demo With' 'A project that has a surface.' </dev/null"

assert_exists "$PROJ/$SKILL" "the skill survived bootstrap"
assert_exists "$PROJ/$ARTICLE" "the declaration article survived bootstrap"
assert_file_has "$PROJ/AGENTS.md" '`/dogfood`' "the quick-reference row is on the map"
assert_file_lacks "$PROJ/AGENTS.md" "DOGFOOD:BEGIN" "the stamp-time markers are consumed, not shipped"
assert_file_lacks "$PROJ/AGENTS.md" "DOGFOOD:END" "the stamp-time markers are consumed, not shipped"
assert_status 0 "the docs gate is green with the skill included" -- \
	sh -c "cd '$PROJ' && sh scripts/check.sh"

# ---------------------------------------------------------------------------
banner "4. bootstrap --no-dogfood — nothing dangles, and the validator proves it"
# ---------------------------------------------------------------------------
mk_project without
assert_status 0 "bootstrap --no-dogfood runs" -- \
	sh -c "cd '$PROJ' && sh bootstrap.sh --no-dogfood 'Demo Without' 'A project with no surface yet.' </dev/null"

assert_absent "$PROJ/.claude/skills/dogfood" "the skill directory is removed, like any kit-only file"
assert_absent "$PROJ/$ARTICLE" "the declaration article goes with it — it exists only to feed the skill"
assert_file_lacks "$PROJ/AGENTS.md" "/dogfood" "the quick-reference row went with the skill"
assert_no_mention "$PROJ" "/dogfood" "a command nothing ships is a dead row on the map"
assert_status 0 "the docs gate is green with the skill skipped" -- \
	sh -c "cd '$PROJ' && sh scripts/check.sh"

# RED — the claim above is "no DANGLING reference", and a grep alone cannot
# prove the gate would have caught one. Plant the row bootstrap removed and
# watch the real validator report it (shared invariant §3: a check that has
# never failed is a claim).
if [ "$HAVE_NODE" = 1 ]; then
	printf '\nRun `/dogfood` before handing the branch over.\n' >>"$PROJ/AGENTS.md"
	assert_status 1 "check.sh rejects a planted /dogfood row in the skipped tree" -- \
		sh -c "cd '$PROJ' && sh scripts/check.sh"
	assert_out_has "skill-missing"
	assert_out_has "/dogfood"
else
	printf '  skip  planted-reference detection (no node — command resolution needs the harness)\n'
fi

# ---------------------------------------------------------------------------
banner "5. No flag and no terminal — the default is skip"
# ---------------------------------------------------------------------------
# A non-interactive bootstrap cannot ask, and the safe answer is the one that
# leaves a project without a runnable surface holding no command it cannot run.
mk_project default
assert_status 0 "bootstrap with no dogfood flag and no tty runs" -- \
	sh -c "cd '$PROJ' && sh bootstrap.sh 'Demo Default' 'No terminal to ask on.' </dev/null"
assert_absent "$PROJ/.claude/skills/dogfood" "non-TTY default is skip"
assert_status 0 "the docs gate is green after the defaulted run" -- \
	sh -c "cd '$PROJ' && sh scripts/check.sh"

# ---------------------------------------------------------------------------
banner "6. A typo'd flag is refused, not silently treated as a project name"
# ---------------------------------------------------------------------------
mk_project typo
assert_status 1 "an unknown option exits rather than stamping a manual named '--with-dogfod'" -- \
	sh -c "cd '$PROJ' && sh bootstrap.sh --with-dogfod 'Demo Typo' </dev/null"
assert_absent "$PROJ/AGENTS.md" "nothing was stamped"

t_done "opt-in /dogfood skill"
