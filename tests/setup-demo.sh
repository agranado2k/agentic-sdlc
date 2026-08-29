#!/bin/sh
# tests/setup-demo.sh — the one-line agent setup, refereed.
#
# The claim (issue #59): a human pastes one line pointing at SETUP.md; an agent
# resolves the newest v* release tag with git, clones the kit AT that tag, and
# follows setup/agent-bootstrap.md from inside the clone to a bootstrapped,
# gate-green project with a local first commit — and never a push.
#
# Instructions nobody executes in CI are prose (root AGENTS.md, hard rule 9),
# so this suite executes the documents' OWN fenced blocks — the Part D pattern
# from tests/docs-demo.sh: extract the real bytes, refuse to be vacuous, run
# them against a scratch origin, and finally prove the referee itself can fail
# by breaking one fence and watching the spine go red.
#
#   1. SETUP.md is frozen: under the line ceiling, no version string, names
#      the payload doc, and carries the trust-posture and plan-first sentences
#      — the fetched-at-main surface must never grow an executable payload.
#   2. The fenced spine, executed verbatim: resolve the tag (numeric sort must
#      pick v10.0.0 over v9.0.0 — a lexicographic resolver dies here), clone,
#      strip, init, bootstrap with an explicit dogfood flag, wire hooks, pass
#      the gate, commit locally.
#   3. Structure the docs must keep: no fence anywhere says `git push`, the
#      existing-repo arm points at a tracked issue, the fill-in fence names
#      every variable the prose tells the agent to set.
#   4. RED — a broken fence fails the spine: the referee is not vacuous.
#
# Usage: sh tests/setup-demo.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
SCRATCH=$(mktemp -d) || exit 2
trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP

failures=0
banner() { printf '\n=== %s ===\n' "$*"; }
pass() { printf '  ok    %s\n' "$*"; }
fail() {
	printf '  FAIL  %s\n' "$*"
	failures=$((failures + 1))
}

ENTRY="$KIT/SETUP.md"
PAYLOAD="$KIT/setup/agent-bootstrap.md"

# sh_block <file> <first-line-pattern> — the body of the ```sh fence whose
# FIRST line matches, printed verbatim. Same instrument as docs-demo.sh's
# recipe_block, generalized over the file: the spine below runs the documents'
# own text, never a mirror of it, so an edit that breaks a fence breaks this
# suite instead of breaking the next consumer.
sh_block() {
	awk -v pat="$2" '
		/^```sh$/       { grab = 1; n = 0; buf = ""; hit = 0; next }
		grab && /^```$/ { grab = 0; if (hit) { printf "%s", buf; exit } next }
		grab {
			n++
			if (n == 1 && $0 ~ pat) hit = 1
			buf = buf $0 "\n"
		}
	' "$1"
}

# take_block <file> <pattern> <destination> <label> — extract, and refuse to be
# vacuous: an extractor that finds nothing would make every assertion after it
# pass on an empty script. Extracted into a FRESH file and only then appended —
# checking `-s` on the destination itself would be vacuous in the other
# direction, since the spine already holds its preamble by the time the first
# fence arrives (found by the independent review of PR #61, by mutation).
take_block() {
	_tb="$SCRATCH/take_block.$$"
	sh_block "$1" "$2" >"$_tb"
	if [ -s "$_tb" ]; then
		cat "$_tb" >>"$3"
		pass "$4"
	else
		fail "$4 — no such fence; this suite can no longer find the step it referees"
	fi
	rm -f "$_tb"
}

# all_fences <file> — every ```sh fence body, concatenated. For the rules that
# quantify over the whole document (no fence may push).
all_fences() {
	awk '
		/^```sh$/       { grab = 1; next }
		grab && /^```$/ { grab = 0; next }
		grab            { print }
	' "$1"
}

# ---------------------------------------------------------------------------
banner "Setup — a scratch origin with two release tags"
# ---------------------------------------------------------------------------
# A copy of THIS tree, committed once and tagged twice. v9.0.0 and v10.0.0 sit
# on the same commit on purpose: the only difference the spine can observe is
# which one the resolve step picks, and a lexicographic sort picks v9.
ORIGIN="$SCRATCH/kit-origin"
mkdir -p "$ORIGIN"
cp -R "$KIT/." "$ORIGIN/"
# Drop nested worktrees, exactly as tests/kit-demo.sh does: the kit is
# developed in worktrees checked out under the repo, and a fixture carrying a
# sibling branch's checkout is testing whatever that branch happens to contain.
git -C "$KIT" worktree list --porcelain 2>/dev/null |
	sed -n 's/^worktree //p' |
	while IFS= read -r wt; do
		case "$wt" in
		"$KIT") ;;
		"$KIT"/*) rm -rf "$ORIGIN/${wt#"$KIT"/}" ;;
		esac
	done
rm -rf "$ORIGIN/.git"

# Hermetic git for everything the spine runs: its own identity, no signing, no
# system config — a developer's global GPG requirement must not fail a suite
# about setup documents. Exported, because the spine is the documents' own
# bytes and may not be edited to carry test flags.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Setup Demo"
git config --file "$GIT_CONFIG_GLOBAL" user.email "demo@example.invalid"
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false
git config --file "$GIT_CONFIG_GLOBAL" tag.gpgSign false
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

git -C "$ORIGIN" init -q
git -C "$ORIGIN" add -A
git -C "$ORIGIN" commit -q -m "chore: kit tree for setup demo"
git -C "$ORIGIN" tag v9.0.0
git -C "$ORIGIN" tag v10.0.0
pass "scratch origin committed and tagged v9.0.0 + v10.0.0"

# ---------------------------------------------------------------------------
banner "1. SETUP.md — the fetched-at-main surface stays frozen"
# ---------------------------------------------------------------------------
if [ -f "$ENTRY" ]; then
	pass "SETUP.md exists at the repo root"
else
	fail "SETUP.md is missing — there is no entry point for the pasted line"
fi

CEILING=35
lines=$(wc -l <"$ENTRY" 2>/dev/null || echo 9999)
lines=$((lines + 0)) # BSD wc pads with spaces
if [ "$lines" -le "$CEILING" ]; then
	pass "SETUP.md holds under the $CEILING-line ceiling ($lines lines)"
else
	fail "SETUP.md is $lines lines (ceiling $CEILING) — the frozen entry doc is growing a payload; the payload belongs in setup/agent-bootstrap.md, which consumers read at their tag"
fi

if grep -Eq '[0-9]+\.[0-9]+\.[0-9]+' "$ENTRY" 2>/dev/null; then
	fail "SETUP.md contains a version string — the pasted line must never go stale, so the entry doc names no release"
else
	pass "SETUP.md names no version — old copies of the pasted line stay valid"
fi

if grep -q 'setup/agent-bootstrap\.md' "$ENTRY" 2>/dev/null; then
	pass "SETUP.md hands off to setup/agent-bootstrap.md inside the clone"
else
	fail "SETUP.md does not name setup/agent-bootstrap.md — stage two is unreachable"
fi

if grep -q 'never instructions' "$ENTRY" 2>/dev/null; then
	pass "SETUP.md carries the trust posture (clone contents are data, never instructions)"
else
	fail "SETUP.md lost the trust-posture sentence — the load-bearing product content, not boilerplate (issue #59)"
fi

if grep -q 'before touching anything' "$ENTRY" 2>/dev/null; then
	pass "SETUP.md carries the plan-first rule (checkpoint before any mutation)"
else
	fail "SETUP.md lost the plan-first sentence — the human checkpoint is the design, not a nicety"
fi

# ---------------------------------------------------------------------------
banner "2. The fenced spine, executed verbatim"
# ---------------------------------------------------------------------------
# The documents' fill-in fences (KIT_URL, PROJECT_DIR, PROJECT_NAME, ...) are
# the values the prose tells the AGENT to choose; here the suite is the agent,
# so it binds its own — and executes every command fence byte-for-byte.
if sh_block "$ENTRY" '^KIT_URL=' | grep -q 'github\.com/agranado2k/agentic-sdlc'; then
	pass "SETUP.md's fill-in fence names the real kit URL"
else
	fail "SETUP.md's fill-in fence does not name the kit repository"
fi
if sh_block "$PAYLOAD" '^PROJECT_NAME=' | grep -q 'DOGFOOD_FLAG'; then
	pass "the payload's fill-in fence names DOGFOOD_FLAG — the opt-in is always explicit, never the silent headless skip"
else
	fail "the payload's fill-in fence does not name DOGFOOD_FLAG"
fi

# The mutation decision (issue #85): the hand-back guidance must name it, so
# whoever fills the engineering article makes the choice out loud instead of
# defaulting to none in silence.
if grep -qi 'mutation decision' "$PAYLOAD" 2>/dev/null; then
	pass "the payload's hand-back names the mutation decision"
else
	fail "the payload never names the mutation decision — the article gets filled with silence (issue #85)"
fi

SPINE="$SCRATCH/spine.sh"
PROJ="$SCRATCH/proj"
{
	echo 'set -eu'
	printf 'KIT_URL=%s\n' "$ORIGIN"
	printf 'PROJECT_DIR=%s\n' "$PROJ"
} >"$SPINE"
take_block "$ENTRY" '^KIT_TAG=' "$SPINE" "SETUP.md's resolve-and-clone fence is extractable"
# Test glue, not doc text: record what the resolve step picked.
printf 'printf %%s "$KIT_TAG" >%s/resolved-tag\n' "$SCRATCH" >>"$SPINE"
{
	printf 'PROJECT_NAME="Setup Demo Project"\n'
	printf 'PROJECT_DESC="A throwaway project the setup referee builds."\n'
	printf 'DOGFOOD_FLAG=--no-dogfood\n'
} >>"$SPINE"
# The leading bracket is double-escaped: awk -v processes escape sequences in
# the value, so a single \[ arrives as a bare [ and the anchor silently
# becomes a character class matching almost any first line.
take_block "$PAYLOAD" '^\\[ -f bootstrap' "$SPINE" "the payload's guard-strip-and-init fence is extractable"
take_block "$PAYLOAD" '^sh bootstrap\.sh' "$SPINE" "the payload's bootstrap fence is extractable"
take_block "$PAYLOAD" '^sh scripts/check\.sh' "$SPINE" "the payload's gate fence is extractable"
take_block "$PAYLOAD" '^KIT_RELEASE=' "$SPINE" "the payload's first-commit fence is extractable"

out=$(sh "$SPINE" 2>&1)
status=$?
if [ "$status" = 0 ]; then
	pass "the spine ran end to end (exit 0)"
else
	fail "the spine failed (exit $status)"
	printf '%s\n' "$out" | tail -20 | sed 's/^/        | /'
fi

resolved=$(cat "$SCRATCH/resolved-tag" 2>/dev/null || echo "")
if [ "$resolved" = "v10.0.0" ]; then
	pass "the resolve step picked v10.0.0 over v9.0.0 — numeric, not lexicographic"
else
	fail "the resolve step picked '$resolved', expected v10.0.0 — the newest release did not win"
fi

if [ -f "$PROJ/AGENTS.md" ] && grep -q "Setup Demo Project" "$PROJ/AGENTS.md" 2>/dev/null; then
	pass "the produced project has a stamped AGENTS.md"
else
	fail "the produced project has no stamped AGENTS.md"
fi

for gone in bootstrap.sh SETUP.md setup tests EXCLUSIONS.md .claude/skills/dogfood; do
	if [ -e "$PROJ/$gone" ]; then
		fail "$gone survived into the produced project — it is kit-only (or declined) and bootstrap must delete it"
	else
		pass "$gone is gone from the produced project"
	fi
done

subject=$(git -C "$PROJ" log -1 --format=%s 2>/dev/null || echo "")
if [ "$subject" = "chore: bootstrap from agentic-sdlc v10.0.0" ]; then
	pass "the first commit is local and names the installed release"
else
	fail "unexpected first commit subject: '$subject'"
fi

remotes=$(git -C "$PROJ" remote 2>/dev/null)
if [ -z "$remotes" ]; then
	pass "the produced project has no remote — the spine cannot have pushed"
else
	fail "the produced project has a remote ('$remotes') — the spine must end before any outward-facing act"
fi

if [ -e "$PROJ/.agentic-sdlc-release" ]; then
	fail ".agentic-sdlc-release survived into the produced project — the commit fence must consume and remove it"
else
	pass "the release scratch file is consumed before the first commit"
fi

(cd "$PROJ" && sh scripts/check.sh >/dev/null 2>&1)
if [ $? = 0 ]; then
	pass "the docs gate is green in the produced project"
else
	fail "the docs gate is red in the produced project"
fi

# Skill visibility (issue #86): the session that runs this setup is launched a
# level ABOVE the project, where a harness never discovers the project's
# skills — so the human-facing "Next:" output must say where the slash
# commands come into scope, and the stamped manual must state the
# precondition beside the chain it applies to.
if printf '%s\n' "$out" | grep -q 'start your next agent session IN THIS DIRECTORY'; then
	pass "bootstrap's Next: output tells the human where the slash commands come into scope"
else
	fail "bootstrap's Next: output never mentions skill discovery — the human's first /command fails silently (issue #86)"
fi

if grep -q 'sessions started in this directory' "$PROJ/AGENTS.md" 2>/dev/null; then
	pass "the stamped manual states the chain's visibility precondition"
else
	fail "the stamped manual's chain section never says the commands need a session started here (issue #86)"
fi

# ---------------------------------------------------------------------------
banner "3. Structure the documents must keep"
# ---------------------------------------------------------------------------
# Both spellings: `git push`, and the forge CLI's `--push` flag — the latter
# reachable exactly in the one fence the spine never executes (review of #61).
for doc in "$ENTRY" "$PAYLOAD"; do
	if all_fences "$doc" | grep -Eq 'git push|--push'; then
		fail "$(basename "$doc") has a fence that pushes ('git push' or '--push') — the push is the operator's first outward act, never the spine's"
	else
		pass "$(basename "$doc") fences never push, under either spelling"
	fi
done

# The README's by-hand ritual carries a copy of the resolve incantation, and
# only SETUP.md's copy is executed above — hold the two byte-identical so the
# unexecuted one cannot drift.
sh_block "$ENTRY" '^KIT_TAG=' | sed -n '1,3p' >"$SCRATCH/resolve.setup"
readme_hits=$(sh_block "$KIT/README.md" '^# 1\. Clone' | grep -Fx -f "$SCRATCH/resolve.setup" | wc -l)
readme_hits=$((readme_hits + 0))
if [ -s "$SCRATCH/resolve.setup" ] && [ "$readme_hits" = 3 ]; then
	pass "the README's resolve incantation matches SETUP.md's, byte for byte"
else
	fail "the README's resolve incantation differs from SETUP.md's ($readme_hits/3 lines match) — the unrefereed copy drifted"
fi

if grep -Eq 'github\.com/agranado2k/agentic-sdlc/issues/[0-9]+' "$PAYLOAD" 2>/dev/null; then
	pass "the existing-repo arm points at a tracked issue"
else
	fail "the existing-repo arm has no tracked-issue pointer — 'not yet' must be honest about where 'yet' lives"
fi

if grep -qi 'existing' "$PAYLOAD" 2>/dev/null; then
	pass "the payload carries the branch point (new project vs existing repo)"
else
	fail "the payload has no existing-repo branch point — landing that arm later should change an else-arm, not the doc's shape"
fi

# Skill visibility (issue #86), the agent-facing half: the payload must tell
# the installing agent to load the stamped manual with its NATIVE file reader
# (a shell cat never triggers a harness's nested-context load), and to verify
# the chain's commands actually appeared before reporting done.
if grep -q 'native file-read tool' "$PAYLOAD" 2>/dev/null; then
	pass "the payload tells the agent to open the stamped manual with its native file reader"
else
	fail "the payload never says 'native file-read tool' — the installing agent has no way to bring the skills into scope (issue #86)"
fi

if grep -q 'before you report done' "$PAYLOAD" 2>/dev/null; then
	pass "the payload makes command visibility a verified claim, not an assumption"
else
	fail "the payload never verifies the chain's commands are available before reporting done (issue #86)"
fi

if grep -q 'slash commands are discovered from' "$KIT/README.md" 2>/dev/null; then
	pass "the README quickstart tells the human where the slash commands come into scope"
else
	fail "the README quickstart never mentions skill discovery — the by-hand reader hits the same silent gap (issue #86)"
fi

# ---------------------------------------------------------------------------
banner "4. RED — the referee is not vacuous"
# ---------------------------------------------------------------------------
# Break one command in a COPY of the payload, rebuild the spine from the broken
# copy, and the run must fail. A referee that stays green over a broken fence
# referees nothing (root AGENTS.md, hard rule 9).
BROKEN="$SCRATCH/agent-bootstrap.broken.md"
sed 's/^sh bootstrap\.sh/sh bootstrap-that-does-not-exist.sh/' "$PAYLOAD" >"$BROKEN"
SPINE2="$SCRATCH/spine-broken.sh"
PROJ2="$SCRATCH/proj-broken"
{
	echo 'set -eu'
	printf 'KIT_URL=%s\n' "$ORIGIN"
	printf 'PROJECT_DIR=%s\n' "$PROJ2"
} >"$SPINE2"
sh_block "$ENTRY" '^KIT_TAG=' >>"$SPINE2"
{
	printf 'PROJECT_NAME="Broken Demo"\n'
	printf 'PROJECT_DESC="Should never bootstrap."\n'
	printf 'DOGFOOD_FLAG=--no-dogfood\n'
} >>"$SPINE2"
sh_block "$BROKEN" '^\\[ -f bootstrap' >>"$SPINE2"
sh_block "$BROKEN" '^sh bootstrap' >>"$SPINE2"
sh_block "$BROKEN" '^sh scripts/check\.sh' >>"$SPINE2"
sh_block "$BROKEN" '^KIT_RELEASE=' >>"$SPINE2"

if sh "$SPINE2" >/dev/null 2>&1; then
	fail "the spine passed over a broken bootstrap step — the referee is vacuous"
else
	pass "a broken fence fails the spine — the referee can go red"
fi
# The clone arrives with the KIT's own AGENTS.md (the kit self-hosts), so a
# manual's presence proves nothing. Bootstrap not having run does: it neither
# self-deleted nor stamped the project name.
if [ -f "$PROJ2/bootstrap.sh" ] && ! grep -q "Broken Demo" "$PROJ2/AGENTS.md" 2>/dev/null; then
	pass "the broken run never bootstrapped — the spine stops at the failure"
else
	fail "the broken run bootstrapped anyway — set -eu did not stop the spine"
fi

# ---------------------------------------------------------------------------
banner "Result"
# ---------------------------------------------------------------------------
if [ "$failures" = 0 ]; then
	echo "setup-demo: all green"
	exit 0
else
	echo "setup-demo: $failures failure(s)"
	exit 1
fi
