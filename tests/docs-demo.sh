#!/bin/sh
# K4's acceptance test — and its demo.
#
# Two claims, both run end to end against throwaway copies of the kit:
#
#   A. Bootstrap produces a PERSONALIZED documentation set — diary with a dated
#      current-state block, ADR index + MADR template, domain glossary, PR
#      template, and a consumer README that describes the project instead of the
#      kit — and the docs gate is green on it.
#   B. UPDATING.md's PART 1 works — the shared layer. A fake older consumer
#      (shared-layer 0.1.0) is diffed against a newer kit (0.5.0) and updated
#      with the exact commands in UPDATING.md, including the drift case, a file
#      joining the layer, and the verbatim check.
#   C. UPDATING.md's PART 2 works — everything else. A consumer bootstrapped at
#      0.3.0 runs Part 1 alone and is held to the INERT HALF-UPDATE that
#      produces (the tier resolver, with no config and no callers); then Part
#      2's steps are run and the skills, the manual section, the workflow
#      template, the config and the adapters all arrive. Optional-skill
#      adoption and removal are exercised in both directions.
#
# Parts B and C each produce the transcript quoted in the matching worked
# example in UPDATING.md. If you change either recipe, re-run this and re-paste
# both — a worked example nobody re-runs is the "stale standing instruction"
# shared invariant §8 is about.
#
# Usage: sh tests/docs-demo.sh

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

assert_file() { [ -e "$1" ] && pass "$1 exists" || fail "$1 is missing"; }
assert_no_file() { [ -e "$1" ] && fail "$1 still exists" || pass "$1 is gone"; }

# assert_has <file> <string>
assert_has() {
	if grep -qF "$2" "$1" 2>/dev/null; then
		pass "$1 mentions '$2'"
	else
		fail "$1 does not mention '$2'"
	fi
}

# assert_same <a> <b> <label>
assert_same() {
	if cmp -s "$1" "$2"; then
		pass "$3"
	else
		fail "$3 — files differ"
	fi
}

# assert_status <expected> <label> -- <command...>
assert_status() {
	expected=$1
	label=$2
	shift 3
	out=$("$@" 2>&1)
	actual=$?
	if [ "$actual" = "$expected" ]; then
		pass "$label (exit $actual)"
	else
		fail "$label — expected exit $expected, got $actual"
		printf '%s\n' "$out" | sed 's/^/        | /'
	fi
	LAST_OUT=$out
}

TODAY=$(date +%Y-%m-%d)

# ###########################################################################
# PART A — bootstrap produces the personalized documentation set
# ###########################################################################

PROJ="$SCRATCH/demo-project"

banner "A0. Setup — simulate 'Use this template'"
mkdir -p "$PROJ"
cp -R "$KIT/." "$PROJ/"
strip_nested_worktrees "$KIT" "$PROJ"
rm -rf "$PROJ/.git"
cd "$PROJ" || exit 2
git init -q -b main
git config user.name "Docs Demo"
git config user.email "demo@example.invalid"
git config commit.gpgsign false
pass "fresh repo at \$SCRATCH/demo-project"

banner "A1. Bootstrap"
assert_status 0 "bootstrap.sh runs" -- \
	sh bootstrap.sh "Aurora Ledger" "A double-entry ledger for small cooperatives."
printf '%s\n' "$LAST_OUT" | sed 's/^/      > /'

banner "A2. The documentation set is in place"
assert_file "README.md"
assert_file "docs/diary.md"
assert_file "docs/domain-glossary.md"
assert_file "docs/adr/INDEX.md"
assert_file "docs/adr/NNNN-template.md"
assert_file ".github/PULL_REQUEST_TEMPLATE.md"
assert_file "UPDATING.md"
assert_no_file "templates/docs"
assert_no_file "templates"

banner "A3. It is PERSONALIZED, not merely present"
assert_has "README.md" "# Aurora Ledger"
assert_has "README.md" "A double-entry ledger for small cooperatives."
assert_has "docs/diary.md" "Current state — $TODAY"
assert_has "docs/diary.md" "Living history of the Aurora Ledger build"
assert_has "docs/diary.md" "### $TODAY — Bootstrapped from the agentic-sdlc kit"
assert_has "docs/domain-glossary.md" "canonical terms for Aurora Ledger"
assert_has "docs/adr/INDEX.md" "architectural decision for Aurora Ledger"

# The K0 README advertised the kit itself. A project whose README tells readers
# to "use it as a GitHub template" is describing the wrong repository.
if grep -qF "Use it as a GitHub template" README.md; then
	fail "README.md is still the KIT's README, not the project's"
else
	pass "README.md no longer describes the kit"
fi

banner "A4. Verbatim files are byte-identical to the kit's"
assert_same "$KIT/templates/docs/adr/NNNN-template.md" "docs/adr/NNNN-template.md" \
	"docs/adr/NNNN-template.md copied verbatim"
assert_same "$KIT/templates/docs/PULL_REQUEST_TEMPLATE.md" ".github/PULL_REQUEST_TEMPLATE.md" \
	".github/PULL_REQUEST_TEMPLATE.md copied verbatim"

banner "A5. The gate is green on the whole set"
# Not `git add`-ed first, deliberately: a just-bootstrapped project has committed
# nothing, and the gate must still see (and scan) every new doc.
assert_status 0 "check.sh passes on the bootstrapped project" -- sh scripts/check.sh
assert_status 0 "shared layer reported" -- sh scripts/check.sh
case "$LAST_OUT" in
*"shared-layer 0.5.0"*) pass "gate reports shared-layer 0.5.0" ;;
*) fail "gate did not report shared-layer 0.5.0: $LAST_OUT" ;;
esac

banner "A6. The gate is NOT vacuous over the new docs"
# If an unstamped mark could survive in docs/, "personalized" would be unchecked.
printf '\n- **Owner** — {{PROJECT_OWNER}}\n' >>docs/domain-glossary.md
assert_status 1 "check.sh rejects an unstamped mark in docs/" -- sh scripts/check.sh
case "$LAST_OUT" in
*"domain-glossary"*) pass "the violation names the glossary" ;;
*) fail "the violation does not name the glossary" ;;
esac
sed '/PROJECT_OWNER/d' docs/domain-glossary.md >"$SCRATCH/glossary.clean"
cp "$SCRATCH/glossary.clean" docs/domain-glossary.md
assert_status 0 "check.sh is green again once the mark is removed" -- sh scripts/check.sh

# And the manual's new references have to resolve.
rm -f docs/diary.md
assert_status 1 "check.sh rejects a deleted docs/diary.md (AGENTS.md points at it)" -- sh scripts/check.sh
case "$LAST_OUT" in
*"path-missing"*) pass "reported as path-missing" ;;
*) fail "not reported as path-missing" ;;
esac

# ###########################################################################
# PART B — the UPDATING.md recipe, executed once
# ###########################################################################
#
# Scenario, constructed in a scratch dir:
#   kit v0.1.0 — shared layer is constitution/shared-invariants.md alone, and
#                its §9/§10 are one heading and one paragraph shorter
#   kit v0.5.0 — the kit as it stands here: §9/§10 tightened, and UPDATING.md
#                JOINS the shared layer
#   consumer   — bootstrapped from v0.1.0, and someone edited the shared file
#                locally (the drift case — the clean case teaches nothing)

banner "B0. Build the fake older kit (v0.1.0) and a consumer on it"

OLDKIT="$SCRATCH/kit-0.1.0"
mkdir -p "$OLDKIT"
cp -R "$KIT/." "$OLDKIT/"
strip_nested_worktrees "$KIT" "$OLDKIT"
rm -rf "$OLDKIT/.git"
rm -f "$OLDKIT/UPDATING.md" # UPDATING.md did not exist at 0.1.0

cat >"$OLDKIT/VERSION" <<'EOF'
# agentic-sdlc — shared-layer manifest

shared-layer: 0.1.0

files:
  constitution/shared-invariants.md
EOF

# Roll the shared rulebook back to its (simulated) 0.1.0 wording.
sed -e "s/^## 9\. Measure the ceiling, don't assume it$/## 9. Measure the ceiling/" \
	-e '/^Per §8 this rule is checkable/,/^$/d' \
	"$KIT/constitution/shared-invariants.md" >"$OLDKIT/constitution/shared-invariants.md"

if cmp -s "$OLDKIT/constitution/shared-invariants.md" "$KIT/constitution/shared-invariants.md"; then
	fail "the fake 0.1.0 rulebook is identical to 0.5.0 — the scenario has no delta"
else
	pass "fake 0.1.0 rulebook differs from 0.5.0"
fi

# A .git-free copy of the kit as it stands: the v0.5.0 release tree.
NEWKIT="$SCRATCH/kit-0.5.0"
mkdir -p "$NEWKIT"
cp -R "$KIT/." "$NEWKIT/"
strip_nested_worktrees "$KIT" "$NEWKIT"
rm -rf "$NEWKIT/.git"

# The two ends, as real git refs in one repo.
HIST="$SCRATCH/kit-history"
mkdir -p "$HIST"
cp -R "$OLDKIT/." "$HIST/"
cd "$HIST" || exit 2
git init -q -b main
git config user.name "Kit Release"
git config user.email "kit@example.invalid"
git config commit.gpgsign false
git config tag.gpgSign false
git config tag.forceSignAnnotated false
git add -A >/dev/null
git commit -q -m "release 0.1.0"
git tag v0.1.0
find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$NEWKIT/." "$HIST/"
git add -A >/dev/null
git commit -q -m "release 0.5.0"
git tag v0.5.0
if git rev-parse -q --verify v0.1.0 >/dev/null && git rev-parse -q --verify v0.5.0 >/dev/null; then
	pass "kit history built with tags v0.1.0 and v0.5.0"
else
	fail "kit history tags were not created"
fi

# A consumer bootstrapped at 0.1.0.
CONSUMER="$SCRATCH/older-consumer"
mkdir -p "$CONSUMER"
cp -R "$OLDKIT/." "$CONSUMER/"
rm -rf "$CONSUMER/.git"
cd "$CONSUMER" || exit 2
git init -q -b main
git config user.name "Older Consumer"
git config user.email "older@example.invalid"
git config commit.gpgsign false
sh bootstrap.sh "Older Consumer" "A project that bootstrapped at shared-layer 0.1.0." >/dev/null 2>&1
git add -A >/dev/null
git commit -q -m "chore: bootstrap from agentic-sdlc"
assert_status 0 "the 0.1.0 consumer's gate is green before the update" -- sh scripts/check.sh

# The local edit that should never have been made to a verbatim file.
printf '\nNOTE (local): §4 is waived for the QA phase in this repo.\n' \
	>>constitution/shared-invariants.md
git commit -qam "docs: note our local exception to invariant 4"
pass "consumer carries one local edit to a shared-layer file (drift)"

# ---------------------------------------------------------------------------
banner "B1. RUN THE RECIPE — the transcript below is UPDATING.md's worked example"
# ---------------------------------------------------------------------------
printf '\n'

recipe() {
	# --- Step 0: point at the kit -------------------------------------------
	KIT_URL="$HIST"
	WORK=$(mktemp -d)
	git clone --bare --quiet "$KIT_URL" "$WORK/kit.git"
	kit() { git --git-dir="$WORK/kit.git" "$@"; }

	FROM_REF="v$(sed -n 's/^shared-layer:[[:space:]]*//p' VERSION | head -1)"
	TO_REF=v0.5.0

	echo "\$ kit tag --list"
	kit tag --list
	echo "\$ echo \"\$FROM_REF -> \$TO_REF\""
	echo "$FROM_REF -> $TO_REF"

	# --- Step 1: read both manifests ----------------------------------------
	manifest() {
		kit show "$1:VERSION" | awk '
			/^files:/       { inlist = 1; next }
			!inlist         { next }
			/^[ \t]*#/      { next }
			/^[ \t]*$/      { next }
			/^[ \t]+[^ \t]/ { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print; next }
			                { inlist = 0 }
		'
	}
	manifest "$FROM_REF" | sort >"$WORK/from.list"
	manifest "$TO_REF" | sort >"$WORK/to.list"

	echo ""
	echo "\$ comm -13 \"\$WORK/from.list\" \"\$WORK/to.list\"   # JOINING"
	comm -13 "$WORK/from.list" "$WORK/to.list"
	echo "\$ comm -23 \"\$WORK/from.list\" \"\$WORK/to.list\"   # LEAVING"
	comm -23 "$WORK/from.list" "$WORK/to.list" | grep . || echo "(none)"

	# --- Step 2: the upstream delta -----------------------------------------
	echo ""
	echo "\$ kit diff --stat \"\$FROM_REF\" \"\$TO_REF\" -- \$(sort -u \"\$WORK/from.list\" \"\$WORK/to.list\")"
	# shellcheck disable=SC2046
	kit diff --stat "$FROM_REF" "$TO_REF" -- $(sort -u "$WORK/from.list" "$WORK/to.list")
	echo ""
	echo "\$ kit diff \"\$FROM_REF\" \"\$TO_REF\" -- constitution/shared-invariants.md"
	kit diff --unified=1 "$FROM_REF" "$TO_REF" -- constitution/shared-invariants.md |
		sed -n '1,40p'

	# --- Step 3: measure your own drift -------------------------------------
	echo ""
	echo "\$ # step 3 — drift check"
	while IFS= read -r f; do
		if [ ! -e "$f" ]; then
			echo "MISSING $f"
			continue
		fi
		if kit show "$FROM_REF:$f" | cmp -s - "$f"; then
			echo "clean   $f"
		else
			echo "DRIFT   $f"
			kit show "$FROM_REF:$f" | diff -u - "$f" | sed -n '3,$p' | sed 's/^/        /'
		fi
	done <"$WORK/from.list"

	# --- Step 3 remediation: move the exception out, restore the shared file --
	echo ""
	echo "\$ # the exception moves to a local article; the shared file is restored"
	{
		echo ""
		echo "## Local exception to shared invariant 4"
		echo ""
		echo "§4 is waived for the QA phase in this repo."
	} >>AGENTS.md
	while IFS= read -r f; do
		kit show "$FROM_REF:$f" >"$f"
	done <"$WORK/from.list"
	git commit -qam "refactor: move the local exception out of the shared layer"
	while IFS= read -r f; do
		kit show "$FROM_REF:$f" | cmp -s - "$f" && echo "clean   $f" || echo "DRIFT   $f"
	done <"$WORK/from.list"

	# --- Step 5: apply ------------------------------------------------------
	echo ""
	echo "\$ # step 5 — apply"
	while IFS= read -r f; do
		mkdir -p "$(dirname "$f")"
		kit show "$TO_REF:$f" >"$f"
		echo "  updated $f"
	done <"$WORK/to.list"
	comm -23 "$WORK/from.list" "$WORK/to.list" | while IFS= read -r f; do
		git rm -q --ignore-unmatch -- "$f" 2>/dev/null || rm -f "$f"
		echo "  removed $f (left the shared layer at $TO_REF)"
	done
	kit show "$TO_REF:VERSION" >VERSION

	# --- Step 6: verify -----------------------------------------------------
	echo ""
	echo "\$ # step 6 — verbatim check, then the gate"
	while IFS= read -r f; do
		if kit show "$TO_REF:$f" | cmp -s - "$f"; then
			echo "verbatim  $f"
		else
			echo "DRIFT     $f"
		fi
	done <"$WORK/to.list"
	echo "\$ sh scripts/check.sh"
	sh scripts/check.sh
	gate=$?
	echo "\$ sed -n 's/^shared-layer:[[:space:]]*//p' VERSION"
	sed -n 's/^shared-layer:[[:space:]]*//p' VERSION
	rm -rf "$WORK"
	return $gate
}

recipe
recipe_status=$?
printf '\n'

banner "B2. Assertions on the updated consumer"
if [ "$recipe_status" = 0 ]; then
	pass "the recipe finished with a green gate"
else
	fail "the recipe finished with gate exit $recipe_status"
fi

cd "$CONSUMER" || exit 2
assert_file "UPDATING.md"
assert_same "$KIT/UPDATING.md" "UPDATING.md" \
	"UPDATING.md joined the layer and is byte-identical to the kit's"
assert_same "$KIT/constitution/shared-invariants.md" "constitution/shared-invariants.md" \
	"constitution/shared-invariants.md is byte-identical to the kit's"
assert_same "$KIT/constitution/shared-code-craft.md" "constitution/shared-code-craft.md" \
	"constitution/shared-code-craft.md joined the layer and is byte-identical to the kit's"
assert_has "VERSION" "shared-layer: 0.5.0"
assert_has "AGENTS.md" "Local exception to shared invariant 4"

# The whole point: the local exception survived the update, in a file that is
# the consumer's own.
if grep -qF "NOTE (local)" constitution/shared-invariants.md; then
	fail "the local edit is still inside the shared file"
else
	pass "the shared file carries no local edit"
fi

banner "B3. The verbatim check is not vacuous"
printf '\nlocal tweak\n' >>constitution/shared-invariants.md
if cmp -s "$KIT/constitution/shared-invariants.md" constitution/shared-invariants.md; then
	fail "an edited shared file still compares equal — the check proves nothing"
else
	pass "an edited shared file is detected as DRIFT"
fi

# ###########################################################################
# PART C — the NON-SHARED update path (UPDATING.md, Part 2)
# ###########################################################################
#
# Part B proves the shared layer moves. This proves the OTHER half, and it
# starts by proving the half-update is real: a consumer that runs Part 1 alone
# on a 0.3.0 -> 0.5.0 update lands the capability-tier RESOLVER (shared layer)
# with no config for it to read, no skill that calls it, and none of the
# release's actual features. Then Part 2's steps are run and each of those
# comes back.
#
# The fake 0.3.0 kit is built by REMOVING the 0.4.0 wave's non-shared additions
# from this tree, the same way B0 rolls the rulebook back. Two of the removals
# are partial-file edits (the Deliver phase out of /implement, the tier rubric
# out of /to-tickets) because a three-way take is only demonstrable when the kit
# changed a file the consumer also has.

banner "C0. Build a fake 0.3.0 kit — the wave's non-shared parts removed"

OLD3="$SCRATCH/kit-0.3.0"
mkdir -p "$OLD3"
cp -R "$KIT/." "$OLD3/"
strip_nested_worktrees "$KIT" "$OLD3"
rm -rf "$OLD3/.git"

# Whole additions of the 0.4.0 wave.
rm -rf "$OLD3/.claude/skills/improve-codebase-architecture"
rm -rf "$OLD3/.claude/skills/dogfood"
rm -rf "$OLD3/adapters/claude-code"
rm -f "$OLD3/constitution/local-product.md.template"
rm -f "$OLD3/scripts/agents.config.sh"
rm -f "$OLD3/scripts/agents.lib.sh"
rm -f "$OLD3/templates/workflows/ai-review.example.yml"
rm -f "$OLD3/templates/workflows/ai-review-prompt.md"

# The 0.3.0 manifest: today's, minus the files that joined after it — the tier
# resolver at 0.4.0 and the code-craft article at 0.5.0. The article's FILE
# stays in the fake tree (the consumer's stamped manual references it), exactly
# as B0 keeps it in the fake 0.1.0 tree; only the manifest entry leaves.
sed '/^  scripts\/agents\.lib\.sh$/d; /^  constitution\/shared-code-craft\.md$/d; s/^shared-layer: 0\.5\.0$/shared-layer: 0.3.0/' \
	"$KIT/VERSION" >"$OLD3/VERSION"

# The 0.3.0 manual template: no capability tiers, no /improve-codebase-architecture.
# Every reference has to go, not just the prose — the docs gate resolves each
# `/command` to a skill directory and each backticked path to a real file, so a
# leftover row would make the fixture red before the test starts.
awk '
	/^## Capability tiers$/ { sec = 1; next }
	sec && /^## / { sec = 0 }
	sec { next }
	/^Four step out of that line/ { par = 1 }
	par {
		if ($0 ~ /^§10\)\.$/) {
			par = 0
			print "Three step out of that line: `/grill-with-docs`, `/prototype` and `/diagnose`."
		}
		next
	}
	/improve-codebase-architecture/ { next }
	/agents\.config\.sh/ { next }
	/agents\.lib\.sh/ { next }
	{ print }
' "$KIT/constitution/AGENTS.md.template" >"$OLD3/constitution/AGENTS.md.template"

# The 0.3.0 local workflow article: no tier block.
awk '
	/^## Capability tiers/ { sec = 1; next }
	sec && /^## / { sec = 0 }
	sec { next }
	{ print }
' "$KIT/constitution/local-workflow.md.template" >"$OLD3/constitution/local-workflow.md.template"

# /implement without its Deliver phase (the consumer will take this verbatim).
awk '
	/^## Deliver — / { sec = 1; next }
	sec && /^## / { sec = 0 }
	sec { next }
	{ print }
' "$KIT/.claude/skills/implement/SKILL.md" >"$OLD3/.claude/skills/implement/SKILL.md"

# /to-tickets without the tier rubric (the consumer will three-way-merge this).
awk '
	/^9\. \*\*Capability tier/ { sec = 1 }
	sec && /^## Trust boundary$/ { sec = 0 }
	sec { next }
	/^- Naming a model in a ticket/ { next }
	{ print }
' "$KIT/.claude/skills/to-tickets/SKILL.md" >"$OLD3/.claude/skills/to-tickets/SKILL.md"

for f in .claude/skills/implement/SKILL.md .claude/skills/to-tickets/SKILL.md \
	constitution/AGENTS.md.template constitution/local-workflow.md.template; do
	if cmp -s "$OLD3/$f" "$KIT/$f"; then
		fail "the fake 0.3.0 $f is identical to 0.5.0 — no delta to adopt"
	else
		pass "fake 0.3.0 $f differs from 0.5.0"
	fi
done

# Both ends as real refs in one repo, exactly as B0 does it.
HIST3="$SCRATCH/kit-history-3"
mkdir -p "$HIST3"
cp -R "$OLD3/." "$HIST3/"
cd "$HIST3" || exit 2
git init -q -b main
git config user.name "Kit Release"
git config user.email "kit@example.invalid"
git config commit.gpgsign false
git config tag.gpgSign false
git config tag.forceSignAnnotated false
git add -A >/dev/null
git commit -q -m "release 0.3.0"
git tag v0.3.0
find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$NEWKIT/." "$HIST3/"
git add -A >/dev/null
git commit -q -m "release 0.5.0"
git tag v0.5.0
pass "kit history built with tags v0.3.0 and v0.5.0"

banner "C1. A consumer bootstrapped at 0.3.0, WITHOUT the optional skill"

C3="$SCRATCH/consumer-0.3.0"
mkdir -p "$C3"
cp -R "$OLD3/." "$C3/"
rm -rf "$C3/.git"
cd "$C3" || exit 2
git init -q -b main
git config user.name "Tier Consumer"
git config user.email "tier@example.invalid"
git config commit.gpgsign false
sh bootstrap.sh --no-dogfood "Tier Consumer" "A project that bootstrapped at shared-layer 0.3.0." >/dev/null 2>&1
git add -A >/dev/null
git commit -q -m "chore: bootstrap from agentic-sdlc"
assert_status 0 "the 0.3.0 consumer's gate is green before the update" -- sh scripts/check.sh
assert_no_file ".claude/skills/dogfood"

# One local edit to a SKILL — legitimate here, unlike B's edit to a shared file.
# Skills are meant to be adapted; this is what makes 9a a three-way rather than
# a copy.
awk 'NR == 4 { print; print ""; print "> LOCAL: tickets in this repo also carry a `Team:` line."; next } { print }' \
	.claude/skills/to-tickets/SKILL.md >"$SCRATCH/tt" && mv "$SCRATCH/tt" .claude/skills/to-tickets/SKILL.md
git commit -qam "docs: our local note on /to-tickets"
pass "consumer carries one local edit to a skill (legitimate — skills are theirs)"

banner "C2. Part 1 ALONE leaves an inert half-update"

# Steps 0-6 of UPDATING.md, run without narration: Part B already proved them.
WORK1=$(mktemp -d)
git clone --bare --quiet "$HIST3" "$WORK1/kit.git"
kit1() { git --git-dir="$WORK1/kit.git" "$@"; }
manifest1() {
	kit1 show "$1:VERSION" | awk '
		/^files:/       { inlist = 1; next }
		!inlist         { next }
		/^[ \t]*#/      { next }
		/^[ \t]*$/      { next }
		/^[ \t]+[^ \t]/ { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print; next }
		                { inlist = 0 }
	'
}
manifest1 v0.3.0 | sort >"$WORK1/from.list"
manifest1 v0.5.0 | sort >"$WORK1/to.list"
while IFS= read -r f; do
	mkdir -p "$(dirname "$f")"
	kit1 show "v0.5.0:$f" >"$f"
done <"$WORK1/to.list"
kit1 show "v0.5.0:VERSION" >VERSION
git add -A >/dev/null
git commit -q -m "chore: update shared layer 0.3.0 -> 0.5.0"

assert_file "scripts/agents.lib.sh"
assert_has "VERSION" "shared-layer: 0.5.0"
assert_status 0 "the gate is green after Part 1 alone" -- sh scripts/check.sh

# …and yet nothing the release is FOR has arrived. This is the gap F8 closes.
assert_no_file "scripts/agents.config.sh"
assert_no_file ".claude/skills/improve-codebase-architecture/SKILL.md"
assert_no_file ".github/workflows/ai-review.example.yml"
if grep -qF "## Deliver" .claude/skills/implement/SKILL.md; then
	fail "/implement already has the Deliver phase — the fixture proves nothing"
else
	pass "/implement still has no Deliver phase after Part 1"
fi
# The resolver is here, and it is inert: no config anywhere, so every tier is
# unmapped. It still exits 0 — an unmapped tier is a working state — which is
# exactly why nothing about this half-update is loud.
assert_status 0 "the resolver runs but resolves nothing" -- sh scripts/agents.lib.sh implementer
if [ -n "$(sh scripts/agents.lib.sh implementer 2>/dev/null)" ]; then
	fail "the resolver printed a model with no config present"
else
	pass "the resolver prints nothing — a resolver with no mapping and no callers"
fi

# ---------------------------------------------------------------------------
banner "C3. RUN PART 2 — the transcript below is UPDATING.md's second worked example"
# ---------------------------------------------------------------------------
printf '\n'

recipe2() {
	WORK=$WORK1
	kit() { kit1 "$@"; }
	# NOT re-derived from VERSION: step 5 already moved it to 0.5.0. Part 2 runs
	# in the same session as Part 1 and reuses its refs.
	FROM_REF=v0.3.0
	TO_REF=v0.5.0

	# --- Step 8: what changed outside the shared layer -----------------------
	kit diff --name-only "$FROM_REF" "$TO_REF" | sort >"$WORK/changed.all"
	sort -u "$WORK/from.list" "$WORK/to.list" >"$WORK/shared.all"
	comm -23 "$WORK/changed.all" "$WORK/shared.all" >"$WORK/changed.yours"

	echo "\$ comm -23 \"\$WORK/changed.all\" \"\$WORK/shared.all\" >\"\$WORK/changed.yours\""
	echo "\$ cat \"\$WORK/changed.yours\""
	cat "$WORK/changed.yours"

	# --- Step 9a: skills ------------------------------------------------------
	echo ""
	echo "\$ # 9a — /implement: the kit changed it, we did not"
	S=.claude/skills/implement/SKILL.md
	echo "\$ kit diff --stat \"\$FROM_REF\" \"\$TO_REF\" -- \"\$S\""
	kit diff --stat "$FROM_REF" "$TO_REF" -- "$S"
	echo "\$ kit show \"\$FROM_REF:\$S\" | diff -u - \"\$S\" | head -1"
	kit show "$FROM_REF:$S" | diff -u - "$S" | head -1 | grep . || echo "(no local edit — take it)"
	kit show "$TO_REF:$S" >"$S"
	echo "  took    $S"

	echo ""
	echo "\$ # 9a — /to-tickets: BOTH changed. Three-way, not a copy."
	T=.claude/skills/to-tickets/SKILL.md
	kit show "$FROM_REF:$T" >"$WORK/base"
	kit show "$TO_REF:$T" >"$WORK/theirs"
	echo "\$ git merge-file \"\$T\" \"\$WORK/base\" \"\$WORK/theirs\""
	if git merge-file "$T" "$WORK/base" "$WORK/theirs"; then
		echo "  merged clean — the kit's delta and our local note both survive"
	else
		echo "  CONFLICT — resolve by reading; there is no verbatim check here"
	fi

	echo ""
	echo "\$ kit diff --name-only --diff-filter=A \"\$FROM_REF\" \"\$TO_REF\" -- .claude/skills"
	kit diff --name-only --diff-filter=A "$FROM_REF" "$TO_REF" -- .claude/skills
	echo "\$ kit archive \"\$TO_REF\" .claude/skills/improve-codebase-architecture | tar -x"
	kit archive "$TO_REF" .claude/skills/improve-codebase-architecture | tar -x

	# The row is a HAND edit, and the gate is why it is not optional.
	echo "\$ sh scripts/check.sh   # the skill is here; the manual does not know"
	sh scripts/check.sh

	# --- Step 9b: the manual -------------------------------------------------
	echo ""
	echo "\$ # 9b — new SECTIONS in the manual template we were stamped from"
	echo "\$ kit diff --stat \"\$FROM_REF\" \"\$TO_REF\" -- constitution/"
	kit diff --stat "$FROM_REF" "$TO_REF" -- constitution/
	echo "\$ # copied across by hand: the Capability tiers section, and two rows"
	kit show "$TO_REF:constitution/AGENTS.md.template" |
		awk '
			/^## Capability tiers$/ { s = 1; print; next }
			s && /^## / { s = 0 }
			s { print }
		' >"$WORK/tiers.section"
	awk -v sec="$WORK/tiers.section" '
		/^## Quick reference$/ { while ((getline l < sec) > 0) print l }
		{ print }
		/^\| Rescue an area that has become hard to change/ { next }
	' AGENTS.md >"$WORK/manual" && mv "$WORK/manual" AGENTS.md
	{
		echo "| Rescue an area that has become hard to change | \`/improve-codebase-architecture\` — deepening candidates, interface design, glossary discipline; hands off to \`/to-tickets\` |"
		echo "| Map a capability tier to a model    | \`scripts/agents.config.sh\` — yours; the kit names no model |"
		echo "| Resolve a tier at spawn time        | \`scripts/agents.lib.sh\` — \`sh scripts/agents.lib.sh <tier>\` |"
	} >>AGENTS.md
	echo "  edited  AGENTS.md (new section + three quick-reference rows)"

	# --- Step 9c: templates ---------------------------------------------------
	echo ""
	echo "\$ # 9c — workflow templates: installed once at bootstrap, never after"
	kit ls-tree --name-only "$TO_REF" templates/workflows/ | while IFS= read -r wf; do
		dest=".github/workflows/$(basename "$wf")"
		if [ ! -e "$dest" ]; then
			echo "NEW       $dest"
		elif kit show "$FROM_REF:$wf" 2>/dev/null | cmp -s - "$dest"; then
			echo "UNTOUCHED $dest"
		else
			echo "YOURS     $dest"
		fi
	done
	kit ls-tree --name-only "$TO_REF" templates/workflows/ | while IFS= read -r wf; do
		dest=".github/workflows/$(basename "$wf")"
		[ -e "$dest" ] || kit show "$TO_REF:$wf" >"$dest"
	done
	echo "  took    .github/workflows/ai-review.example.yml + its prompt file"

	# --- Step 9d: config ------------------------------------------------------
	echo ""
	echo "\$ # 9d — config: ADD or MERGE? Ask before you write."
	C=scripts/agents.config.sh
	echo "\$ # kit cat-file -e \"\$FROM_REF:\$C\" — did it exist at the release we are on?"
	if kit cat-file -e "$FROM_REF:$C" 2>/dev/null; then
		echo "MERGE  $C existed at $FROM_REF — diff the key sets"
		keys() { sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$1" | sort -u; }
		kit show "$TO_REF:$C" >"$WORK/config.new"
		keys "$WORK/config.new" >"$WORK/keys.new"
		keys "$C" >"$WORK/keys.mine"
		comm -13 "$WORK/keys.mine" "$WORK/keys.new"
	else
		echo "ADD    $C is new at $TO_REF — nothing of ours to preserve"
		kit show "$TO_REF:$C" >"$C"
		echo "\$ sed -n 's/^\\(AGENT_TIER_[A-Z]*\\)=.*/\\1/p' \"\$C\""
		sed -n 's/^\(AGENT_TIER_[A-Z]*\)=.*/\1/p' "$C"
	fi

	# --- Step 9e: adapters ----------------------------------------------------
	echo ""
	echo "\$ # 9e — adapters: whole directories, or none"
	echo "\$ kit archive \"\$TO_REF\" adapters | tar -x"
	kit archive "$TO_REF" adapters | tar -x
	ls adapters

	# --- Step 10: the gate is the check --------------------------------------
	echo ""
	echo "\$ sh scripts/check.sh"
	sh scripts/check.sh
	gate2=$?
	return $gate2
}

recipe2
recipe2_status=$?
printf '\n'

banner "C4. Assertions on the fully updated consumer"
cd "$C3" || exit 2
if [ "$recipe2_status" = 0 ]; then
	pass "Part 2 finished with a green gate"
else
	fail "Part 2 finished with gate exit $recipe2_status"
fi

# The ticket's headline claim: a skill actually arrives.
assert_file ".claude/skills/improve-codebase-architecture/SKILL.md"
assert_same "$KIT/.claude/skills/improve-codebase-architecture/SKILL.md" \
	".claude/skills/improve-codebase-architecture/SKILL.md" \
	"the new skill arrived intact"
assert_has "AGENTS.md" "/improve-codebase-architecture"

# The changed skill was taken; the locally-edited one was MERGED, not clobbered.
assert_has ".claude/skills/implement/SKILL.md" "## Deliver"
assert_has ".claude/skills/to-tickets/SKILL.md" "## The tier rubric"
assert_has ".claude/skills/to-tickets/SKILL.md" "LOCAL: tickets in this repo"

# The config that makes the shared resolver mean something.
assert_file "scripts/agents.config.sh"
assert_has "scripts/agents.config.sh" "AGENT_TIER_PLANNER"
assert_has "AGENTS.md" "Capability tiers"

# The workflow, and the prompt file it reads at run time.
assert_file ".github/workflows/ai-review.example.yml"
assert_file ".github/workflows/ai-review-prompt.md"
assert_no_file ".github/workflows/ai-review.yml"

assert_file "adapters/claude-code/README.md"

banner "C5. The gate is what makes the hand edits non-optional"
# A quick-reference row whose skill was never copied is the failure mode Part 2's
# 9a warns about. If the gate did not catch it, "add the row by hand" would be
# advice nothing enforces.
printf '| Do a thing | `/not-a-real-skill` — nope |\n' >>AGENTS.md
assert_status 1 "the gate rejects a row with no skill behind it" -- sh scripts/check.sh
case "$LAST_OUT" in
*"skill-missing"*) pass "reported as skill-missing" ;;
*) fail "not reported as skill-missing: $LAST_OUT" ;;
esac
sed '/not-a-real-skill/d' AGENTS.md >"$SCRATCH/manual.clean"
cp "$SCRATCH/manual.clean" AGENTS.md
assert_status 0 "green again once the row is removed" -- sh scripts/check.sh

banner "C6. Adopting the optional /dogfood skill after bootstrap"
# Bootstrap asked once and deleted itself. Adoption is three things, and the
# gate proves the third is not optional.
kit1 archive v0.5.0 .claude/skills/dogfood | tar -x
kit1 show "v0.5.0:constitution/local-product.md.template" \
	>constitution/local-product.md.template
assert_file ".claude/skills/dogfood/SKILL.md"
assert_status 0 "the gate is green with the skill present but unannounced" -- sh scripts/check.sh
printf '| Use the product before a user does | `/dogfood` — declared personas, real surface |\n' >>AGENTS.md
assert_status 0 "the gate is green once the manual's row is added by hand" -- sh scripts/check.sh
assert_has "AGENTS.md" "/dogfood"

banner "C7. Declining it later — the reverse, proved by the gate"
rm -rf .claude/skills/dogfood
assert_status 1 "removing the skill but not the row fails the gate" -- sh scripts/check.sh
case "$LAST_OUT" in
*"skill-missing"*) pass "the dangling reference is reported as skill-missing" ;;
*) fail "a dangling /dogfood reference was not caught: $LAST_OUT" ;;
esac
sed '/dogfood/d' AGENTS.md >"$SCRATCH/manual.nodog"
cp "$SCRATCH/manual.nodog" AGENTS.md
rm -f constitution/local-product.md.template
assert_status 0 "green once the row goes too — no dangling reference remains" -- sh scripts/check.sh

# ---------------------------------------------------------------------------
banner "Result"
# ---------------------------------------------------------------------------
if [ "$failures" = 0 ]; then
	echo "  ALL GREEN — the docs set is personalized and both halves of the update recipe work."
	exit 0
fi
echo "  $failures assertion(s) failed."
exit 1
