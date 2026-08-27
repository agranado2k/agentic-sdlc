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
#      (shared-layer 0.1.0) is diffed against a newer kit (0.9.0) and updated
#      with the exact commands in UPDATING.md, including the drift case, a file
#      joining the layer, and the verbatim check.
#   C. UPDATING.md's PART 2 works — everything else. A consumer bootstrapped at
#      0.3.0 runs Part 1 alone and is held to the INERT HALF-UPDATE that
#      produces (the tier resolver, with no config and no callers); then Part
#      2's steps are run and the skills, the manual section, the workflow
#      template, the config and the adapters all arrive. Optional-skill
#      adoption and removal are exercised in both directions.
#
#   D. Both worked examples in UPDATING.md are the transcripts B and C just
#      produced — compared byte for byte, so "re-run and re-paste" is a check
#      and not a request. A worked example nobody re-runs is the "stale standing
#      instruction" shared invariant §8 is about; D is what stops this one
#      becoming that. When it fails, re-run this script and re-paste the block
#      it names. Never hand-edit a transcript to match.
#
# Usage: sh tests/docs-demo.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
SCRATCH=$(mktemp -d) || exit 2

trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP

# The shared helper library. This suite overrides several helpers below with
# variants of its own, but `assert_out_has` and `strip_nested_worktrees` come
# from here — the sourcing was missing, so both were silently
# command-not-found: one C2 assertion never asserted and the nested-worktree
# stripping never stripped, while the suite stayed green. Exactly the vacuity
# class this suite exists to catch.
# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"

failures=0

banner() { printf '\n=== %s ===\n' "$*"; }
pass() { printf '  ok    %s\n' "$*"; }
fail() {
	printf '  FAIL  %s\n' "$*"
	failures=$((failures + 1))
}

# note <text> — a visible line that is neither a pass nor a fail.
#
# Some cases below can only run against a shell that is installed. Silently
# skipping one would let a machine (or a CI image) quietly drop an entire axis
# while still printing ALL GREEN, so a skip says so out loud — here, and again
# beside the final summary, where a reader who only checks the last lines will
# actually see it. Same convention as tests/agents-tiers.test.sh.
SKIPPED=0
note() {
	printf '  --    %s\n' "$*"
	SKIPPED=$((SKIPPED + 1))
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

# step6_check <kit-command> <ref> <list-file>
#
# UPDATING.md step 6's verification, as the recipe writes it: a shared file is
# verbatim only if BOTH its bytes and its executable bit match the release. Git
# records one mode bit (100755 vs 100644) and nothing else, so that — not the
# full octal — is what is compared; `tar -x` applies the umask to the rest.
step6_check() {
	_k=$1
	_r=$2
	while IFS= read -r f; do
		_want=$("$_k" ls-tree "$_r" -- "$f" | awk '{print $1}')
		case "$_want" in
		100755) _wx=yes ;;
		*) _wx=no ;;
		esac
		if [ -x "$f" ]; then _hx=yes; else _hx=no; fi
		if ! "$_k" show "$_r:$f" | cmp -s - "$f"; then
			echo "DRIFT     $f"
		elif [ "$_wx" != "$_hx" ]; then
			echo "MODE      $f (kit has $_want)"
		else
			echo "verbatim  $f"
		fi
	done <"$3"
}

# recipe_block <awk-pattern> — the body of the ```sh fence in UPDATING.md whose
# FIRST line matches, printed verbatim.
#
# The two data-loss cases below run the recipe's OWN TEXT rather than a copy of
# it. Every other executable claim in this suite is mirrored by hand (recipe,
# recipe2, step6_check) and pinned to the document by section D's transcript
# comparison — but a branch that destroys a file prints nothing into a
# transcript, so there is no D to pin it with. A mirror is exactly the wrong
# instrument there: it can be fixed in this file while the document a consumer
# actually follows stays broken, which is the shape of the bug that shipped.
recipe_block() {
	awk -v pat="$1" '
		/^```sh$/       { grab = 1; n = 0; buf = ""; hit = 0; next }
		grab && /^```$/ { grab = 0; if (hit) { printf "%s", buf; exit } next }
		grab {
			n++
			if (n == 1 && $0 ~ pat) hit = 1
			buf = buf $0 "\n"
		}
	' "$KIT/UPDATING.md"
}

# assert_block <pattern> <destination> <label> — extract, and refuse to be vacuous.
#
# An extractor that finds nothing would make every assertion below it pass on an
# empty script. That is the same vacuity 9d's own key-set diff falls into, so it
# gets the same treatment: no match is a failure, loudly.
assert_block() {
	recipe_block "$1" >"$2"
	if [ -s "$2" ]; then
		pass "$3"
	else
		fail "$3 — no such block in UPDATING.md; this suite can no longer find the recipe it tests"
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

# Both transcripts this script produces are compared byte-for-byte against the
# worked examples pasted into UPDATING.md (section D). `git diff --stat` scales
# its graph to the terminal width, and git reads COLUMNS before it asks the
# terminal — so pin it, or the same run produces different bytes on a wide
# terminal than in a pipe.
COLUMNS=80
export COLUMNS

# Same reasoning, second axis: `sort`, `comm` and `ls` order by the collation the
# locale names, so the same manifest lists in a different order under en_US.UTF-8
# than under C. Surfaced the day this suite got a CI job — the pinned transcripts
# had been captured on macOS under UTF-8, where `UPDATING.md` sorts after
# `scripts/...`, and CI's C locale puts it before `constitution/...`. C is the
# one collation every platform has, so capture under it.
LC_ALL=C
export LC_ALL

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
*"shared-layer 0.9.0"*) pass "gate reports shared-layer 0.9.0" ;;
*) fail "gate did not report shared-layer 0.9.0: $LAST_OUT" ;;
esac

banner "A6. The gate is NOT vacuous over the new docs"
# If an unstamped mark could survive in docs/, "personalized" would be unchecked.
printf '\n- **Owner** — %s\n' "$(t_mark PROJECT_OWNER)" >>docs/domain-glossary.md
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
#   kit v0.9.0 — the kit as it stands here: §9/§10 tightened, and UPDATING.md
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
# Neither did the code-craft article (it joins at 0.5.0) — and a faithful old
# kit must not REFERENCE it either, or the article-unreferenced red in B1's
# step 6 (the whole point of the article-joins-the-layer case) could never
# fire and the recipe's claim about it would be untestable.
rm -f "$OLDKIT/constitution/shared-code-craft.md"
awk '
	/^- `constitution\/shared-code-craft\.md`/ { craft = 1; next }
	craft && /^- `constitution\// { craft = 0 }
	craft { next }
	/shared-code-craft/ { next }
	{ print }
' "$KIT/constitution/AGENTS.md.template" >"$OLDKIT/constitution/AGENTS.md.template"

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
	fail "the fake 0.1.0 rulebook is identical to 0.9.0 — the scenario has no delta"
else
	pass "fake 0.1.0 rulebook differs from 0.9.0"
fi

# A .git-free copy of the kit as it stands: the v0.9.0 release tree.
NEWKIT="$SCRATCH/kit-0.9.0"
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
git commit -q -m "release 0.9.0"
git tag v0.9.0
if git rev-parse -q --verify v0.1.0 >/dev/null && git rev-parse -q --verify v0.9.0 >/dev/null; then
	pass "kit history built with tags v0.1.0 and v0.9.0"
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
	TO_REF=v0.9.0

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
	# shellcheck disable=SC2046  # manifest paths, one per line, none with spaces
	kit archive "$TO_REF" -- $(cat "$WORK/to.list") | tar -x
	sed 's/^/  updated /' "$WORK/to.list"
	comm -23 "$WORK/from.list" "$WORK/to.list" | while IFS= read -r f; do
		git rm -q --ignore-unmatch -- "$f" 2>/dev/null || rm -f "$f"
		echo "  removed $f (left the shared layer at $TO_REF)"
	done
	kit show "$TO_REF:VERSION" >VERSION
	if ! kit diff --quiet "$FROM_REF" "$TO_REF" -- UPDATING.md; then
		echo "  NOTE  UPDATING.md changed in $TO_REF — RE-READ IT before continuing"
	fi

	# --- Step 6: verify -----------------------------------------------------
	echo ""
	echo "\$ # step 6 — verbatim check (bytes AND mode), then the gate"
	step6_check kit "$TO_REF" "$WORK/to.list"
	echo "\$ sh scripts/check.sh"
	sh scripts/check.sh 2>&1
	first_gate=$?
	if [ "$first_gate" = 0 ]; then
		echo "UNEXPECTED: green before the manual pointer — the fixture is not faithful,"
		echo "or node is missing (the reduced fallback cannot check article reachability)"
		rm -rf "$WORK"
		return 1
	fi
	echo ""
	echo "\$ # RED, deliberately: the ARTICLE is shared layer, the POINTER to it is"
	echo "\$ # yours (the root manual — Part 2 territory). Add it and re-run."
	{
		echo ""
		echo "Craft rules for the code itself: \`constitution/shared-code-craft.md\` —"
		echo "load it before writing or reviewing code (shared layer, see \`VERSION\`)."
	} >>AGENTS.md
	git commit -qam "docs: point the manual at the code-craft article (0.5.0 Part 2)"
	echo "\$ sh scripts/check.sh"
	sh scripts/check.sh
	gate=$?
	echo "\$ sed -n 's/^shared-layer:[[:space:]]*//p' VERSION"
	sed -n 's/^shared-layer:[[:space:]]*//p' VERSION
	echo "Part 1 complete — shared layer at $TO_REF. The update is not done: go to step 8."
	# NOT `rm -rf "$WORK"`: the bare clone, the refs and both manifests are what
	# step 8 reuses. The cleanup lives at the end of step 10.
	return $gate
}

recipe >"$SCRATCH/part1.transcript" 2>&1
recipe_status=$?
cat "$SCRATCH/part1.transcript"
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
assert_has "VERSION" "shared-layer: 0.9.0"
assert_has "AGENTS.md" "Local exception to shared invariant 4"
assert_has "AGENTS.md" "shared-code-craft"

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

banner "B4. Step 5 says out loud that it replaced the recipe being followed"
# UPDATING.md is manifest-listed, so step 5 overwrote the very file the operator
# opened. Silence there is how a 0.3.0 consumer reaches the end of step 6 — in
# THEIR copy, the last step — and stops, half-updated, with a green gate.
assert_has "$SCRATCH/part1.transcript" "UPDATING.md changed in v0.9.0 — RE-READ IT"
assert_has "$SCRATCH/part1.transcript" "The update is not done: go to step 8."
# The note is a condition, not an unconditional echo. Same predicate, same two
# refs, aimed at a shared file this release did not touch: silent.
if git -C "$HIST" diff --quiet v0.1.0 v0.9.0 -- scripts/check.sh; then
	pass "the same predicate stays silent for a file the release did not change"
else
	fail "scripts/check.sh moved between the fixture's releases — pick another control"
fi

# Part B stops at step 7, so nothing here reaches step 10's cleanup.
rm -rf "$WORK"

# ###########################################################################
# PART C — the NON-SHARED update path (UPDATING.md, Part 2)
# ###########################################################################
#
# Part B proves the shared layer moves. This proves the OTHER half, and it
# starts by proving the half-update is real: a consumer that runs Part 1 alone
# on a 0.3.0 -> 0.9.0 update lands the capability-tier RESOLVER (shared layer)
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

# And the 0.5.0 wave's shared addition: a faithful 0.3.0 has neither the
# code-craft article nor any manual reference to it (same reasoning as B0).
rm -f "$OLD3/constitution/shared-code-craft.md"

# The 0.3.0 manifest: today's, minus the files that joined after it — the tier
# resolver at 0.4.0 and the code-craft article at 0.5.0 (whose file and manual
# references were stripped above, exactly as B0 strips them from the fake
# 0.1.0 kit).
#
# The marker line is matched by SHAPE, never by the literal version this kit
# happens to be on: a pinned `s/^shared-layer: 0\.6\.0$/` stops matching the
# first release after it is written, and a rewrite that stops matching is
# silent.
sed '/^  scripts\/agents\.lib\.sh$/d; /^  constitution\/shared-code-craft\.md$/d; s/^shared-layer: *[0-9][0-9.]*$/shared-layer: 0.3.0/' \
	"$KIT/VERSION" >"$OLD3/VERSION"
# The rollback is the fixture's whole premise, so assert it happened. Matching
# the marker by SHAPE rather than by a pinned literal is what keeps that true:
# the pinned form went silently dead the first release after it was written, the
# fixture then carried the CURRENT version, and C2's "the update landed 0.x.0"
# assertion passed on a version that had never moved.
assert_has "$OLD3/VERSION" "shared-layer: 0.3.0"

# The 0.3.0 manual template: no capability tiers, no /improve-codebase-architecture.
# Every reference has to go, not just the prose — the docs gate resolves each
# `/command` to a skill directory and each backticked path to a real file, so a
# leftover row would make the fixture red before the test starts.
awk '
	/^- `constitution\/shared-code-craft\.md`/ { craft = 1; next }
	craft && /^- `constitution\// { craft = 0 }
	craft { next }
	/shared-code-craft/ { next }
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
		fail "the fake 0.3.0 $f is identical to 0.9.0 — no delta to adopt"
	else
		pass "fake 0.3.0 $f differs from 0.9.0"
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
git commit -q -m "release 0.9.0"
git tag v0.9.0
pass "kit history built with tags v0.3.0 and v0.9.0"

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

# A workflow this consumer DELETED on purpose: it folded the pairing gate into
# its own CI. `.github/workflows/tdd-pairing.yml` exists at 0.3.0 and does not
# change in 0.4.0, so its absence is a decision — the case 9c's `[ ! -e ]` test
# cannot tell from "you never had this".
assert_file ".github/workflows/tdd-pairing.yml"
rm -f .github/workflows/tdd-pairing.yml
git commit -qam "ci: fold the pairing gate into our own workflow"
assert_status 0 "the gate is green with a workflow deliberately removed" -- sh scripts/check.sh

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
manifest1 v0.9.0 | sort >"$WORK1/to.list"
# shellcheck disable=SC2046  # manifest paths, one per line, none with spaces
kit1 archive v0.9.0 -- $(cat "$WORK1/to.list") | tar -x
kit1 show "v0.9.0:VERSION" >VERSION
git add -A >/dev/null
git commit -q -m "chore: update shared layer 0.3.0 -> 0.9.0"

assert_file "scripts/agents.lib.sh"
assert_has "VERSION" "shared-layer: 0.9.0"
# Part 1 landed a constitution ARTICLE, and the manual that should point at it
# is the consumer's own — Part 2 territory. So the gate goes red here, by
# design: article-unreferenced is what forces the two halves to land together.
assert_status 1 "the gate is RED after Part 1 alone — the article landed, its manual pointer is Part 2" -- sh scripts/check.sh
assert_out_has "article-unreferenced"

# …and beyond the red, nothing the release is FOR has arrived. This is the gap
# F8 closes.
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

banner "C2b. Step 5 carries the MODE, and step 6 checks it"
# `scripts/agents.lib.sh` is 100755 in the kit and JOINS the layer at 0.4.0 —
# the exact shape that bites: a `kit show >` redirect writes bytes and drops the
# mode bit, and a content-only verbatim check then calls the result correct.
# Only files JOINING the layer are exposed, because a file you already had keeps
# whatever mode it landed with at bootstrap.
if [ -x scripts/agents.lib.sh ]; then
	pass "an executable shared file landed executable in the consumer"
else
	fail "scripts/agents.lib.sh landed non-executable — step 5 dropped the mode bit"
fi

step6_check kit1 v0.9.0 "$WORK1/to.list" >"$SCRATCH/step6.clean"
if grep -qv '^verbatim  ' "$SCRATCH/step6.clean"; then
	fail "step 6 reported something other than verbatim after a clean apply"
	sed 's/^/        | /' "$SCRATCH/step6.clean"
else
	pass "step 6 reports every shared file verbatim after the apply"
fi

# …and that green is not free. Break ONLY the mode and the check must fire —
# otherwise it is a check that reports success on the failure it exists for.
chmod -x scripts/agents.lib.sh
step6_check kit1 v0.9.0 "$WORK1/to.list" >"$SCRATCH/step6.mode"
case "$(grep 'scripts/agents\.lib\.sh' "$SCRATCH/step6.mode")" in
MODE*) pass "step 6 catches a mode-only difference" ;;
*)
	fail "step 6 did not catch a mode-only difference"
	grep 'scripts/agents\.lib\.sh' "$SCRATCH/step6.mode" | sed 's/^/        | /'
	;;
esac
if kit1 show "v0.9.0:scripts/agents.lib.sh" | cmp -s - scripts/agents.lib.sh; then
	pass "the bytes are still identical — which is why the mode leg has to exist"
else
	fail "the mode-only break changed the bytes too — the fixture proves nothing"
fi
chmod +x scripts/agents.lib.sh

# ---------------------------------------------------------------------------
banner "C3. RUN PART 2 — the transcript below is UPDATING.md's second worked example"
# ---------------------------------------------------------------------------
printf '\n'

recipe2() {
	WORK=$WORK1
	kit() { kit1 "$@"; }
	# NOT re-derived from VERSION: step 5 already moved it to 0.9.0. Part 2 runs
	# in the same session as Part 1 and reuses its refs.
	FROM_REF=v0.3.0
	TO_REF=v0.9.0

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
	echo "\$ sh scripts/check.sh   # still red from Part 1: the ARTICLE is here; the manual does not know"
	sh scripts/check.sh 2>&1

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
	{
		echo ""
		echo "Craft rules for the code itself: \`constitution/shared-code-craft.md\` —"
		echo "load it before writing or reviewing code (shared layer, see \`VERSION\`)."
	} >>AGENTS.md
	echo "  edited  AGENTS.md (new section + three quick-reference rows + the code-craft pointer)"

	# --- Step 9c: templates ---------------------------------------------------
	echo ""
	echo "\$ # 9c — workflow templates: installed once at bootstrap, never after"
	kit ls-tree --name-only "$TO_REF" templates/workflows/ | while IFS= read -r wf; do
		dest=".github/workflows/$(basename "$wf")"

		if [ ! -e "$dest" ]; then
			if kit cat-file -e "$FROM_REF:$wf" 2>/dev/null; then
				echo "DECLINED  $dest"
			else
				echo "NEW       $dest"
			fi
		elif kit diff --quiet "$FROM_REF" "$TO_REF" -- "$wf"; then
			echo "UNCHANGED $dest"
		elif kit show "$FROM_REF:$wf" 2>/dev/null | cmp -s - "$dest"; then
			echo "UNTOUCHED $dest"
		else
			echo "YOURS     $dest"
		fi
	done >"$WORK/workflows.verdicts"
	cat "$WORK/workflows.verdicts"

	# NEW and UNTOUCHED are a copy. UNCHANGED, DECLINED and YOURS are not.
	while read -r verdict dest; do
		case "$verdict" in
		NEW | UNTOUCHED) kit show "$TO_REF:templates/workflows/${dest##*/}" >"$dest" ;;
		esac
	done <"$WORK/workflows.verdicts"
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
		# printf, not echo: this is the one echoed line carrying a literal
		# backslash, and `echo` is where shells still disagree — dash expands
		# `\1` to a control character, bash and the macOS shell print it as
		# written. Same class as the COLUMNS and LC_ALL pins above: the
		# transcript must not record which shell captured it.
		printf '%s\n' "\$ sed -n 's/^\\(AGENT_TIER_[A-Z]*\\)=.*/\\1/p' \"\$C\""
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

recipe2 >"$SCRATCH/part2.transcript" 2>&1
recipe2_status=$?
cat "$SCRATCH/part2.transcript"
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
assert_same "$KIT/constitution/shared-code-craft.md" "constitution/shared-code-craft.md" \
	"the code-craft article arrived intact"
assert_has "AGENTS.md" "shared-code-craft"

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

banner "C4b. 9c does not undo a deliberate deletion"
# The destructive case: a `[ ! -e "$dest" ]` classifier reads "you deliberately
# removed this" as "you never had this" and copies it back — silently re-adding a
# duplicate gate to every PR. The release did not touch this file; there is
# nothing to adopt, and re-adding it is not an update.
assert_no_file ".github/workflows/tdd-pairing.yml"

# classified <regex for a workflow basename> — 9c's verdict line, as printed.
classified() {
	grep -E "^[A-Z]+[[:space:]]+\.github/workflows/$1([[:space:]]|\$)" \
		"$SCRATCH/part2.transcript" | head -1
}
# assert_verdict <expected word> <basename regex> <why it matters>
assert_verdict() {
	_line=$(classified "$2")
	case "$_line" in
	"$1"*) pass "9c says $1 for $2 — $3" ;;
	*)
		fail "9c said '${_line:-nothing}' for $2, expected $1 — $3"
		;;
	esac
}
assert_verdict DECLINED 'tdd-pairing\.yml' "unchanged upstream, and gone on purpose"
# …and it still says NEW for a workflow that is genuinely new. That is the
# distinction `[ ! -e "$dest" ]` alone could not make: under the old rule both of
# these printed NEW and both were copied in.
assert_verdict NEW 'ai-review\.example\.yml' "did not exist at 0.3.0"

assert_file "adapters/claude-code/README.md"

# ---------------------------------------------------------------------------
# The two data-loss cases. Both run UPDATING.md's own text (see recipe_block).
# ---------------------------------------------------------------------------

# recipe_prelude <file> — the shell state steps 8-10 assume, written to <file>.
# Step 0 created it in the real recipe; the cases below re-create it so one
# block can be run on its own.
recipe_prelude() {
	cat >"$1" <<EOF
WORK=\$(mktemp -d)
kit() { git --git-dir="$WORK1/kit.git" "\$@"; }
FROM_REF=v0.3.0
TO_REF=v0.9.0
EOF
	recipe_block '^kit_take\(\)' >>"$1"
}

banner "C4c. 9d does not destroy a config the kit ships only as a .template"
# `scripts/docs-conformance/local-vocabulary.mjs` is one of the four config
# files 9d names, and in the kit that path exists ONLY as
# `local-vocabulary.mjs.template` — bootstrap stamps it, which is why the
# consumer has the `.mjs` and the kit never does, at EITHER ref.
#
# So 9d's opening question, "did it exist at the release you are on?", is false
# — and a branch that reads one `no` as "then it is new at the target" runs
# `kit show "$TO_REF:$C" >"$C"`. The shell truncates the consumer's file before
# kit is started; kit then exits 128 having written nothing. The product
# vocabulary that arms the portability guard is gone, and the line above it said
# `ADD … copy it whole`, which was never true of this path.
#
# 9b already handles this exact `.template`-vs-stamped asymmetry. 9d is the same
# question asked one category over, and it needs the same three answers.
cd "$C3" || exit 2
VOCAB=scripts/docs-conformance/local-vocabulary.mjs
assert_file "$VOCAB"
assert_has "$VOCAB" "Tier Consumer"
cp "$VOCAB" "$SCRATCH/vocab.saved"
vocab_before=$(wc -c <"$VOCAB")

recipe_prelude "$SCRATCH/prelude.sh"
assert_block '^C=scripts/' "$SCRATCH/9d.sh" "UPDATING.md's 9d config block is extractable"
# The same block, pointed at another of the four files 9d itself lists.
sed '1s|^C=.*|C=scripts/docs-conformance/local-vocabulary.mjs|' "$SCRATCH/9d.sh" \
	>"$SCRATCH/9d.vocab.sh"
sh -c '. "$1"; . "$2"' _ "$SCRATCH/prelude.sh" "$SCRATCH/9d.vocab.sh" \
	>"$SCRATCH/9d.vocab.out" 2>&1
sed 's/^/      > /' "$SCRATCH/9d.vocab.out"

vocab_after=$(wc -c <"$VOCAB")
if [ "$vocab_after" = "$vocab_before" ]; then
	pass "9d left the stamped-from-template config at its $vocab_before bytes"
else
	fail "9d destroyed $VOCAB — $vocab_before bytes before, $vocab_after after"
fi
assert_has "$VOCAB" "Tier Consumer"
# …and the verdict is not the false claim that put the redirect there.
if grep -q '^ADD ' "$SCRATCH/9d.vocab.out"; then
	fail "9d said ADD for a path that is absent at the TARGET ref too"
else
	pass "9d did not claim the path is new at the release being adopted"
fi
# Restore, so a RED run of the case above does not cascade into every later
# section: an empty local-vocabulary.mjs is a broken import, and the gate would
# then fail for a reason that is not the one under test.
cp "$SCRATCH/vocab.saved" "$VOCAB"

banner "C4d. 9b behaves the same under zsh as under sh"
# The recipe never says which shell it is written for, and macOS — this
# framework's own target — defaults to zsh. zsh applies HISTORY MODIFIERS to
# `$var:x` even inside double quotes, so `"$TO_REF:constitution/…"` is `$TO_REF`
# with the `:c` modifier applied, followed by the literal `onstitution/…`. The
# ref never reaches git.
#
# 9b is where that lands on a file, in both of its arms: the take truncates the
# local article to zero before the failing `kit show` writes anything, and the
# `cmp` arm above it — reading the same broken expansion — compares against
# EMPTY input and answers `YOURS` for an article that is verbatim the template.
#
# `"$TO_REF:$C"`, `"$FROM_REF:$f"` and `"$TO_REF:VERSION"` are unaffected (`$`
# and `V` are not modifiers), which is exactly why this hid.
#
# The fixture is the UNSTAMPED case — a consumer who never filled the article
# in, so bootstrap left the `.template` and it is byte-identical to FROM_REF's.
# The correct outcome is therefore a TAKE, and the assertion is not "the bytes
# never move" (they should) but the two things that are true either way: the two
# shells must agree, and no shell may leave a zero-byte article behind.
if command -v zsh >/dev/null 2>&1; then
	assert_block '^A=constitution/local-workflow\.md$' "$SCRATCH/9b.sh" \
		"UPDATING.md's 9b unstamped-article block is extractable"

	# One pristine fixture tree per shell. 9b touches only this one path, so a
	# directory holding only it is a faithful stage and isolates the mutation.
	for _sh in sh zsh; do
		rm -rf "$SCRATCH/9b-$_sh"
		mkdir -p "$SCRATCH/9b-$_sh/constitution"
		kit1 show "v0.3.0:constitution/local-workflow.md.template" \
			>"$SCRATCH/9b-$_sh/constitution/local-workflow.md.template"
	done
	art_before=$(wc -c <"$SCRATCH/9b-sh/constitution/local-workflow.md.template")

	# `zsh -f`: no user rc files, so this measures the shell and not the
	# operator's dotfiles.
	(cd "$SCRATCH/9b-sh" && sh -c '. "$1"; . "$2"' _ "$SCRATCH/prelude.sh" "$SCRATCH/9b.sh") \
		>"$SCRATCH/9b.sh.out" 2>&1
	(cd "$SCRATCH/9b-zsh" && zsh -f -c '. "$1"; . "$2"' _ "$SCRATCH/prelude.sh" "$SCRATCH/9b.sh") \
		>"$SCRATCH/9b.zsh.out" 2>&1
	sed 's/^/      > sh:  /' "$SCRATCH/9b.sh.out"
	sed 's/^/      > zsh: /' "$SCRATCH/9b.zsh.out"

	_zart="$SCRATCH/9b-zsh/constitution/local-workflow.md.template"
	art_after=$(wc -c <"$_zart")
	if [ "$art_after" -gt 0 ]; then
		pass "zsh: 9b left $art_after bytes in the local article (started at $art_before)"
	else
		fail "zsh: 9b destroyed the local article — $art_before bytes before, 0 after"
	fi
	assert_same "$SCRATCH/9b-sh/constitution/local-workflow.md.template" "$_zart" \
		"zsh and sh leave the local article in the same state"
	assert_same "$SCRATCH/9b.sh.out" "$SCRATCH/9b.zsh.out" \
		"zsh and sh reach the same 9b verdict"
	# `v0.3.0onstitution/…` is the mangled ref, and `fatal:` is git refusing it.
	# Match the digit-then-`onstitution` boundary, not the bare word: every
	# correct verdict line names `constitution/…` and contains it as a substring.
	if grep -qE '[0-9]onstitution/|^fatal:' "$SCRATCH/9b.zsh.out"; then
		fail "zsh: a history modifier ate the ref — the expansion is still unbraced"
	else
		pass "zsh: the ref reached git intact"
	fi
else
	note "zsh is not installed here — 9b's real-shell case did not run, and a CI image without zsh proves less than this host would"
fi

banner "C4e. A take of a path that is NOT at the ref leaves your file alone"
# 9d is where the truncate-before-failure shape was caught, but the shape is the
# bug: `kit show "$REF:$path" >"$mine"` is the recipe's idiom for "take the
# release's copy", and the shell empties `$mine` before kit is started. Every
# one of those in the recipe is one absent path away from the same 1807-byte
# loss — a renamed skill in 9a, a `.template`-only config in 9d, an article in
# 9b. So the recipe carries ONE take helper and this is its case.
assert_block '^kit_take\(\)' "$SCRATCH/take.sh" \
	"UPDATING.md defines a take helper (step 0)"
# The two assertions below would both PASS against a helper that does not exist
# — `command not found` writes nothing either — so they only run once there is
# something to run. A vacuous green is what this suite exists to prevent.
if [ -s "$SCRATCH/take.sh" ]; then
mkdir -p "$SCRATCH/take-fixture"
printf 'mine, and irreplaceable\n' >"$SCRATCH/take-fixture/mine"
take_before=$(wc -c <"$SCRATCH/take-fixture/mine")
{
	echo "WORK=$SCRATCH/take-fixture"
	echo "kit() { git --git-dir=\"$WORK1/kit.git\" \"\$@\"; }"
	cat "$SCRATCH/take.sh"
	echo 'kit_take v0.9.0 no/such/path/at/this/ref "$WORK/mine" && echo "TOOK" || echo "declined to write"'
} >"$SCRATCH/take-case.sh"
sh "$SCRATCH/take-case.sh" >"$SCRATCH/take.out" 2>&1
sed 's/^/      > /' "$SCRATCH/take.out"
take_after=$(wc -c <"$SCRATCH/take-fixture/mine" 2>/dev/null || echo missing)
if [ "$take_after" = "$take_before" ]; then
	pass "a failed take left the destination at its $take_before bytes"
else
	fail "a failed take wrote over the destination — $take_before bytes before, $take_after after"
fi
if grep -q '^TOOK' "$SCRATCH/take.out"; then
	fail "the take helper reported success for a path that is not at the ref"
else
	pass "the take helper reported failure rather than a silent empty write"
fi
fi

banner "C4f. No ref expansion in the recipe is one letter from a zsh modifier"
# C4d proves the behaviour on the block that was caught. This proves the SHAPE
# across the whole document, because the next one will be introduced by an
# ordinary edit: `"$TO_REF:$C"` is safe and `"$TO_REF:constitution/…"` is not,
# and the only difference is what the author happened to type after the colon.
#
# The rule the recipe now keeps: a `ref:path` expansion is followed by a `$` or
# by a brace, never by a bare letter. `$` can never begin a modifier; `${REF}`
# ends the expansion before the colon is read. Anything else is one rename away
# from handing git a ref that does not exist — and from a `cmp` that answers on
# empty input rather than failing.
#
# Prose that deliberately QUOTES the unsafe spelling uses `$path`/`$C` after the
# colon, so it is not matched here — the counterexample is allowed to exist.
zsh_modifier_risk=$(grep -nE '"\$[A-Za-z0-9_]+:[A-Za-z]' "$KIT/UPDATING.md" || true)
if [ -z "$zsh_modifier_risk" ]; then
	pass "every ref expansion in UPDATING.md is braced or followed by a \$"
else
	fail "UPDATING.md has ref expansions a zsh history modifier can eat"
	printf '%s\n' "$zsh_modifier_risk" | sed 's/^/        | /'
fi
# …and the check is not vacuous: the pattern it hunts for has to match when it
# is present.
printf 'kit show "$TO_REF:constitution/x.md"\n' >"$SCRATCH/shape.probe"
if grep -qE '"\$[A-Za-z0-9_]+:[A-Za-z]' "$SCRATCH/shape.probe"; then
	pass "the shape check matches an unbraced ref expansion when there is one"
else
	fail "the shape check cannot detect the shape it exists for"
fi

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
kit1 archive v0.9.0 .claude/skills/dogfood | tar -x
kit1 show "v0.9.0:constitution/local-product.md.template" \
	>constitution/local-product.md.template
assert_file ".claude/skills/dogfood/SKILL.md"
assert_status 0 "the gate is green with the skill present but unannounced" -- sh scripts/check.sh
printf '| Use the product before a user does | `/dogfood` — declared personas, real surface |\n' >>AGENTS.md
assert_status 0 "the gate is green once the manual's row is added by hand" -- sh scripts/check.sh
assert_has "AGENTS.md" "/dogfood"

banner "C6b. The article the skill needs — and the ORDER the gate enforces"
# The kit's DOGFOOD block names `constitution/local-product.md.template`, because
# in the KIT it is a template. Copy that pointer into your manual first and then
# drop the suffix — the written order — and the manual names a path you have just
# renamed away.
sed 's/{{[A-Za-z0-9_]*}}/a filled-in value/g' constitution/local-product.md.template \
	>constitution/local-product.md
rm -f constitution/local-product.md.template
printf -- '- `constitution/local-product.md.template` — what `/dogfood` needs: personas and surfaces.\n' \
	>>AGENTS.md
assert_status 1 "the manual pointing at the .template it no longer has fails the gate" -- sh scripts/check.sh
case "$LAST_OUT" in
*path-missing* | *article-unreferenced*) pass "reported as a dangling article reference" ;;
*) fail "the wrong order was not reported: $LAST_OUT" ;;
esac
# The documented order: fill it in and drop the suffix FIRST, then point the
# manual at the `.md` that now exists.
sed 's|constitution/local-product\.md\.template|constitution/local-product.md|' AGENTS.md \
	>"$SCRATCH/manual.product" && cp "$SCRATCH/manual.product" AGENTS.md
assert_status 0 "green once the pointer names the .md the rename produced" -- sh scripts/check.sh

banner "C7. Declining it later — the reverse, proved by the gate"
rm -rf .claude/skills/dogfood
assert_status 1 "removing the skill but not the row fails the gate" -- sh scripts/check.sh
case "$LAST_OUT" in
*"skill-missing"*) pass "the dangling reference is reported as skill-missing" ;;
*) fail "a dangling /dogfood reference was not caught: $LAST_OUT" ;;
esac
sed '/dogfood/d' AGENTS.md >"$SCRATCH/manual.nodog"
cp "$SCRATCH/manual.nodog" AGENTS.md
rm -f constitution/local-product.md constitution/local-product.md.template
assert_status 0 "green once the row goes too — no dangling reference remains" -- sh scripts/check.sh

# ###########################################################################
# PART D — the worked examples in UPDATING.md are THIS run's output
# ###########################################################################
#
# Shared invariant §8: a worked example nobody re-runs is a stale standing
# instruction. UPDATING.md's two ```console blocks are transcripts of the two
# recipes above, so "re-run and re-paste" can be a check rather than a request —
# and a reader who compares their own output against a transcript is comparing
# against something that was true this morning.

banner "D. UPDATING.md's worked examples match the run above"

# console_block <file> <n> — the contents of the Nth ```console fence.
console_block() {
	awk -v want="$2" '
		/^```console$/ { n++; if (n == want) { inblock = 1; next } }
		inblock && /^```$/ { exit }
		inblock { print }
	' "$1"
}

# Leading and trailing blank lines are markdown formatting, not transcript.
trim_blank_edges() {
	awk '{ line[NR] = $0; if (NF) { if (!first) first = NR; last = NR } }
	     END { for (i = first; i <= last; i++) print line[i] }'
}

# assert_transcript <n> <captured file> <label>
assert_transcript() {
	console_block "$KIT/UPDATING.md" "$1" | trim_blank_edges >"$SCRATCH/doc.$1"
	trim_blank_edges <"$2" >"$SCRATCH/run.$1"
	if cmp -s "$SCRATCH/doc.$1" "$SCRATCH/run.$1"; then
		pass "UPDATING.md's $3 worked example is byte-identical to this run"
	else
		fail "UPDATING.md's $3 worked example is STALE — re-run this script and re-paste it"
		diff -u "$SCRATCH/doc.$1" "$SCRATCH/run.$1" |
			sed -e '1,2d' -e 's/^/        | /'
	fi
}

assert_transcript 1 "$SCRATCH/part1.transcript" "Part 1"
assert_transcript 2 "$SCRATCH/part2.transcript" "Part 2"

# ---------------------------------------------------------------------------
banner "Result"
# ---------------------------------------------------------------------------
if [ "$SKIPPED" -gt 0 ]; then
	printf '  --    %s case(s) skipped above — this host proved less than a full-shell host would\n' "$SKIPPED"
fi
if [ "$failures" = 0 ]; then
	echo "  ALL GREEN — the docs set is personalized and both halves of the update recipe work."
	exit 0
fi
echo "  $failures assertion(s) failed."
exit 1
