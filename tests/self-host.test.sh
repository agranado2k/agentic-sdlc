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

# The reduced form must SAY what it cannot check, and the skill-web advisory is
# harness-only by decision (a grep approximation would re-implement the command
# grammar badly). The claim of reduced coverage is itself held here.
if (cd "$KIT" && DOCS_CHECK_NO_NODE=1 sh scripts/check.sh 2>&1 >/dev/null) | grep -q "skill-web advisory"; then
	pass "the no-node NOTICE names the skill-web advisory among what it cannot run"
else
	fail "the no-node NOTICE does not admit the skill-web advisory is skipped — reduced coverage is claiming more than it checks"
fi

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

# The kit's own tier -> model mapping (f13) never reaches a consumer: it names
# a model, and the kit names no model to consumers. It is kit-authoring only,
# same deletion list as tests/ and the kit's own CI.
[ -e "$PROJ/scripts/agents.kit.config.sh" ] &&
	fail "scripts/agents.kit.config.sh leaked into the project — the kit's own model mapping reached a consumer" ||
	pass "no scripts/agents.kit.config.sh in the project — the kit's own mapping stayed kit-side"
# Its wrapper (f13 review M-2) is kit-authoring only for the same reason: it
# exists only to reach a kit-only config that no longer exists in a stamped
# project, so it would be dead weight at best and a broken command at worst.
[ -e "$PROJ/scripts/agents.kit.sh" ] &&
	fail "scripts/agents.kit.sh leaked into the project — the kit's own resolver wrapper reached a consumer" ||
	pass "no scripts/agents.kit.sh in the project — the kit's own wrapper stayed kit-side"
# The consumer's own mapping file still ships, still empty.
[ -f "$PROJ/scripts/agents.config.sh" ] &&
	pass "scripts/agents.config.sh (the consumer-shipped mapping) is still present" ||
	fail "scripts/agents.config.sh did not reach the project"

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

# ---------------------------------------------------------------------------
banner "E. Consumer content in the strip's reach is never silently destroyed"
# ---------------------------------------------------------------------------
# Sections C and D prove the strip works. This one proves its GUARDS work, and
# it exists because they did not have a check that could fail: the sentinel
# condition could be deleted from bootstrap.sh outright and every suite in this
# repo stayed green. A rule with no failing check is a claim (hard rule 9), and
# this is the highest-consequence line in the kit — the one that deletes a
# consumer's files, before they have run anything else, without asking.
#
# The window matters. Bootstrap runs ONCE, right after "Use this template", and
# that is exactly when somebody writes their first ADR or personalizes the
# manual they were just handed. Every fixture below is that person.
#
# Fixtures here COMMIT, unlike C and D: "Use this template" hands you a repo
# with an initial commit, and bootstrap's third condition compares against it.

# consumer_repo <dest> — a consumer's tree as GitHub hands it over.
consumer_repo() {
	t_kit_copy "$1"
	git -C "$1" add -A
	git -C "$1" commit -q -m "Initial commit from template"
}

# --- E1: a manual the consumer wrote themselves, before bootstrapping -------
# No sentinel, so condition 2 stops the strip. This is the case the F12 comment,
# the README and the PR description all claim is safe, and until now no suite
# said so: removing the sentinel check turns all four assertions below red.
HAND="$SCRATCH/hand-written"
consumer_repo "$HAND"
printf '# House rules\n\nOurs, hand written, no sentinel anywhere.\n' >"$HAND/AGENTS.md"
git -C "$HAND" add AGENTS.md
git -C "$HAND" commit -q -m "docs: our own manual"
cp "$HAND/AGENTS.md" "$SCRATCH/hand-written.AGENTS.md"

assert_status 1 "a hand-written manual with no sentinel is refused" -- \
	sh -c "cd '$HAND' && sh bootstrap.sh --no-dogfood 'Other Name' 'One line.'"
assert_out_has "already exists"
if cmp -s "$HAND/AGENTS.md" "$SCRATCH/hand-written.AGENTS.md"; then
	pass "the hand-written manual is byte-identical after the refusal"
else
	fail "bootstrap rewrote or deleted a manual that is not the kit's"
fi
[ -f "$HAND/docs/adr/0001-the-kit-self-hosts-its-own-constitution.md" ] &&
	pass "nothing was stripped — the refusal came before any deletion" ||
	fail "bootstrap deleted files on a run it went on to refuse"

# --- E2: decisions the consumer recorded before bootstrapping ---------------
# The strip names FILES. A directory-wide `rm -rf docs/adr` takes these two with
# it, and the uncommitted one is gone for good.
ADRS="$SCRATCH/consumer-adrs"
consumer_repo "$ADRS"
printf '# We will use Postgres\n\nRecorded and committed before the first bootstrap.\n' \
	>"$ADRS/docs/adr/0002-we-will-use-postgres.md"
git -C "$ADRS" add docs/adr/0002-we-will-use-postgres.md
git -C "$ADRS" commit -q -m "docs: our first decision"
printf '# We will queue with SQS\n\nStill a draft, never committed.\n' \
	>"$ADRS/docs/adr/0003-draft.md"

assert_status 0 "bootstrap still runs on a tree holding consumer ADRs" -- \
	sh -c "cd '$ADRS' && sh bootstrap.sh --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
assert_file_has "$ADRS/docs/adr/0002-we-will-use-postgres.md" "Recorded and committed" \
	"a consumer's committed ADR is not the kit's to delete"
assert_file_has "$ADRS/docs/adr/0003-draft.md" "Still a draft" \
	"an uncommitted ADR is unrecoverable — git history cannot give it back"
[ -e "$ADRS/docs/adr/0001-the-kit-self-hosts-its-own-constitution.md" ] &&
	fail "the kit's own ADR survived beside the consumer's" ||
	pass "the kit's own ADR was stripped from beside the consumer's"

# --- E3: the kit's manual, personalized in place ----------------------------
# An edit leaves the sentinel comment intact — it says so itself — so condition
# 2 cannot see this consumer at all. Condition 3 is what turns a silent delete
# and exit 0 into a refusal that names the file.
EDITED="$SCRATCH/edited-manual"
consumer_repo "$EDITED"
printf '\n## Our house rule\n\nAlways rebase, never merge.\n' >>"$EDITED/AGENTS.md"

assert_status 1 "the kit's manual with local edits is refused, not deleted" -- \
	sh -c "cd '$EDITED' && sh bootstrap.sh --no-dogfood '$PROJECT_NAME' '$PROJECT_DESC'"
assert_out_has "local changes"
assert_file_has "$EDITED/AGENTS.md" "Always rebase, never merge." \
	"the edit survives — the refusal is the point of condition 3"
# And the refusal is atomic: the whole set is checked before any of it is
# deleted, so a tree that gets refused is a tree nothing happened to.
for f in CLAUDE.md GEMINI.md docs/diary.md docs/adr/INDEX.md .github/PULL_REQUEST_TEMPLATE.md; do
	[ -f "$EDITED/$f" ] &&
		pass "$f survived the refusal (the strip is all-or-nothing)" ||
		fail "$f was deleted before the refusal fired — the tree is half-stripped"
done

# --- E4: the enumeration cannot silently go stale ---------------------------
# Naming files instead of a directory buys the safety above and owes one debt:
# a kit ADR added later has to join the list. This is that debt's check.
kit_own_line=$(grep '^KIT_OWN=' "$KIT/bootstrap.sh")
for a in "$KIT"/docs/adr/*; do
	[ -f "$a" ] || continue
	rel="docs/adr/$(basename "$a")"
	case "$kit_own_line" in
	*"$rel"*) pass "bootstrap names $rel explicitly" ;;
	*) fail "$rel is one of the kit's own but is not on bootstrap's KIT_OWN list — it would ride into every consumer's tree" ;;
	esac
done
# …and the other half of the same debt: not one entry may be a DIRECTORY, or the
# enumeration is decorative and everything beside it goes too.
kit_own_files=$(printf '%s\n' "$kit_own_line" | sed 's/^KIT_OWN=//; s/"//g')
dir_entries=0
for entry in $kit_own_files; do
	if [ -d "$KIT/$entry" ]; then
		fail "bootstrap's KIT_OWN names the DIRECTORY $entry — everything a consumer put in it goes with the strip"
		dir_entries=$((dir_entries + 1))
	fi
done
[ "$dir_entries" = 0 ] &&
	pass "every KIT_OWN entry is a file the kit ships, not a directory"

# --- E5: every record has an index row, and every row has a record ---------
# The index is what says which decisions are binding. A record with no row is
# invisible to the reader the index exists for; a row with no file is a
# decision nobody can read. One probe covers both halves; it runs on the kit
# and then on two baits, because a rule with no failing check is a claim
# (hard rule 9). Numbered records only: the template is NNNN, not digits.
# One notion of "row" for both directions: a table line `| [N](file) …`,
# extracted once. A record linked only from the index's prose is NOT
# indexed — the table is what the reader scans. A link's `#fragment` is
# dropped before the file test.
adr_index_gaps() {
	_rows=$(sed -n 's/^| \[[0-9][0-9]*\](\([^)#]*\)[^)]*).*/\1/p' "$1/INDEX.md")
	for _a in "$1"/[0-9][0-9][0-9][0-9]-*.md; do
		[ -f "$_a" ] || continue
		printf '%s\n' "$_rows" | grep -q -x -F "$(basename "$_a")" || echo "unindexed: $(basename "$_a")"
	done
	printf '%s\n' "$_rows" | while IFS= read -r _f; do
		[ -n "$_f" ] || continue
		[ -f "$1/$_f" ] || echo "no such record: $_f"
	done
}
gaps=$(adr_index_gaps "$KIT/docs/adr")
[ -z "$gaps" ] &&
	pass "every record under docs/adr/ has an index row, and every row names a record" ||
	fail "docs/adr/ and its index disagree — $(printf '%s' "$gaps" | tr '\n' ';')"
BAIT="$SCRATCH/adr-bait"
mkdir -p "$BAIT" && cp "$KIT"/docs/adr/*.md "$BAIT"/
printf '# ADR-9999: Bait\n' >"$BAIT/9999-bait-without-a-row.md"
case "$(adr_index_gaps "$BAIT")" in
*"unindexed: 9999-bait-without-a-row.md"*) pass "the probe catches a record with no index row" ;;
*) fail "the probe missed an unindexed record" ;;
esac
# Linked from prose only, never given a row: still unindexed.
printf '\n- See [9999](9999-bait-without-a-row.md) — mentioned, never tabled.\n' >>"$BAIT/INDEX.md"
case "$(adr_index_gaps "$BAIT")" in
*"unindexed: 9999-bait-without-a-row.md"*) pass "a record linked only from the index's prose is still unindexed" ;;
*) fail "a prose-only link passed as an index row" ;;
esac
rm -f "$BAIT/9999-bait-without-a-row.md"
printf '| [9998](9998-row-without-a-record.md) | Bait | Accepted 2026-09-02 |\n' >>"$BAIT/INDEX.md"
case "$(adr_index_gaps "$BAIT")" in
*"no such record: 9998-row-without-a-record.md"*) pass "the probe catches an index row with no record" ;;
*) fail "the probe missed a row with no file" ;;
esac
# A row whose link carries a fragment still names its record.
printf '| [9997](0001-the-kit-self-hosts-its-own-constitution.md#decision-outcome) | Bait | Accepted 2026-09-02 |\n' >>"$BAIT/INDEX.md"
case "$(adr_index_gaps "$BAIT")" in
*"#decision-outcome"*) fail "a row link with a fragment was reported as a missing record" ;;
*) pass "a row link with a fragment resolves to its record" ;;
esac

# ---------------------------------------------------------------------------
banner "F. The kit's public face stays current"
# ---------------------------------------------------------------------------
# Two staleness modes the merge train of 2026-08-27 caught in the wild, each
# now a check instead of a diary follow-up (hard rule 9).

# --- F1: every suite runs in CI ---------------------------------------------
# README.md names every suite; nothing said every suite is WIRED. A suite with
# no CI job is local-only — its claim holds exactly as long as somebody
# remembers to run it, which is the failure mode docs-demo.sh actually shipped.
#
# Only real `run:` lines count — a comment mentioning a suite must not satisfy
# this — and quotes are stripped so `run: sh "tests/x.sh"` still matches. A
# suite invoked through a variable is NOT recognized and fails red: the safe
# direction, and the price of keeping this a text check rather than a parser.
workflow_runs=$(sed -n 's/^[[:space:]]*run:[[:space:]]*//p' \
	"$KIT"/.github/workflows/*.yml | tr -d '"'\''')
for suite in "$KIT"/tests/*.sh; do
	rel="tests/$(basename "$suite")"
	[ "$rel" = "tests/lib.sh" ] && continue # the harness, not a suite
	case "$workflow_runs" in
	*"sh $rel"*) pass "$rel is invoked by a workflow in .github/workflows/" ;;
	*) fail "$rel has no CI job — it is a suite in name only until a workflow runs it" ;;
	esac
done

# A run line is only as good as the workflow that carries it: a file the forge
# refuses to load runs NOTHING, while every `run:` line in it still reads as
# wired above. The observed failure mode is a job block pasted over a sibling,
# leaving one job with two `name:`/`runs-on:`/`steps:` — so hold every job to
# unique immediate keys. Indentation-based on purpose: both kit workflows are
# hand-written two-space YAML, and this is a tripwire for one edit class, not
# a parser.
for wf in "$KIT"/.github/workflows/*.yml; do
	dup=$(awk '
		/^  [A-Za-z0-9_-]+:/ { delete seen }
		/^    [A-Za-z0-9_-]+:/ {
			key = $1
			if (key in seen) { print FILENAME ": duplicate key " key " in one job"; bad = 1 }
			seen[key] = 1
		}
		END { exit bad }
	' "$wf") || {
		fail "$(basename "$wf") has a job with duplicate keys — the forge will refuse the whole workflow"
		printf '%s\n' "$dup" | sed 's/^/        | /'
		continue
	}
	pass "$(basename "$wf") has no job with duplicate keys"
done

# --- F2: README's shared-layer claim tracks VERSION -------------------------
# README quotes the manifest's marker as a worked example. An example pinned to
# a dead release teaches the reader the wrong current state — the same defect
# class the diary's Current state block guards against, one file over.
version_now=$(sed -n 's/^shared-layer: *//p' "$KIT/VERSION")
[ -n "$version_now" ] || fail "VERSION carries no shared-layer marker to compare against"
# The marker's dots are regex wildcards to grep; escape them, or 0x7x0 passes.
version_re=$(printf '%s' "$version_now" | sed 's/\./\\./g')
stale_readme=$(grep -n 'shared-layer: *[0-9][0-9.]*' "$KIT/README.md" | grep -v "shared-layer: *$version_re" || true)
if [ -z "$stale_readme" ]; then
	pass "every shared-layer marker README quotes is the current one ($version_now)"
else
	fail "README quotes a shared-layer marker that is not $version_now:"
	printf '%s\n' "$stale_readme" | sed 's/^/        | /'
fi

# --- F2b: the manuals' craft-rule count tracks the article -----------------
# The manual template and the kit's own manual both say how many portable
# craft rules the shared article carries, and the number rotted twice in a
# row: "ten" survived §11 and §12 joining in 0.10.0, and stamped consumers
# inherited the wrong count for four releases. Count the article's numbered
# sections, spell the number the way prose does, and hold every sentence that
# names the count to it. A sentence that stops matching the shape is its own
# failure — a probe that finds nothing must not pass.
craft_sections=$(grep -c '^## [0-9][0-9]*\. ' "$KIT/constitution/shared-code-craft.md")
case "$craft_sections" in
10) craft_word=ten ;; 11) craft_word=eleven ;; 12) craft_word=twelve ;;
13) craft_word=thirteen ;; 14) craft_word=fourteen ;; 15) craft_word=fifteen ;;
16) craft_word=sixteen ;; 17) craft_word=seventeen ;; 18) craft_word=eighteen ;;
19) craft_word=nineteen ;; 20) craft_word=twenty ;;
*) craft_word="" ;;
esac
[ -n "$craft_word" ] ||
	fail "shared-code-craft.md has $craft_sections numbered sections — extend this check's number words"
# Prose wraps, so the count and its noun can sit on different lines: join the
# file before probing, and read every "<word> portable [craft] rules" phrase.
# Each manual names the count TWICE — the article-layer sentence and the
# quick-reference row — so the probe holds the number of phrases as well as
# their content: a reworded sentence that drops the count would otherwise
# narrow the check silently.
craft_probe() {
	_cp_manual=$1
	_cp_expect=$2
	_cp_phrases=$(tr '\n' ' ' <"$_cp_manual" | tr -s ' ' |
		grep -oi '[a-z]* portable \(craft \)\{0,1\}rules' || true)
	_cp_found=$(printf '%s\n' "$_cp_phrases" | grep -c . || true)
	[ "$_cp_found" -ge "$_cp_expect" ] || return 1
	_cp_stale=$(printf '%s\n' "$_cp_phrases" | tr 'A-Z' 'a-z' | grep -v "^$craft_word " || true)
	[ -z "$_cp_stale" ] || { printf '%s\n' "$_cp_stale"; return 2; }
	return 0
}
for manual in constitution/AGENTS.md.template AGENTS.md; do
	if out=$(craft_probe "$KIT/$manual" 2); then
		pass "$manual says $craft_word portable craft rules in both places, matching the article's $craft_sections sections"
	elif [ $? = 1 ]; then
		fail "$manual names the craft-rule count fewer than twice — a count sentence was reworded out of the probe's reach"
	else
		fail "$manual names a craft-rule count that is not $craft_word (the article has $craft_sections sections):"
		printf '%s\n' "$out" | sed 's/^/        | /'
	fi
done
# The probe can go red, in both directions: a wrong word, and a lost sentence.
printf 'the ten portable craft rules; and the ten portable rules\n' >"$SCRATCH/craft.wrong"
craft_probe "$SCRATCH/craft.wrong" 2 >/dev/null; [ $? = 2 ] &&
	pass "the craft-count probe rejects a manual naming the wrong count" ||
	fail "the craft-count probe passed a manual naming the wrong count — the check is vacuous"
printf 'the %s portable craft rules\n' "$craft_word" >"$SCRATCH/craft.one"
craft_probe "$SCRATCH/craft.one" 2 >/dev/null; [ $? = 1 ] &&
	pass "the craft-count probe rejects a manual that lost one of its count sentences" ||
	fail "the craft-count probe passed a manual with a count sentence missing"

# --- F5b: no ticket is enumerated twice in the current note -----------------
# Stacked branches each grew the current note; merging them up pasted one
# ticket's clause twice, and F5 only checks the marker exists. Read the
# current note (from its heading to the version line), count each "From #N"
# reference, and fail on any that appears more than once — with its own bait.
current_note() {
	awk -v v="$1" '
		$0 ~ ("^# " v " ") { on = 1 }
		on && /^shared-layer:/ { exit }
		on { print }
	' "$2"
}
dup_refs() { current_note "$1" "$2" | grep -o 'From #[0-9]*' | sort | uniq -d; }
if [ -n "$(dup_refs "$version_now" "$KIT/VERSION")" ]; then
	fail "the $version_now note enumerates a ticket twice: $(dup_refs "$version_now" "$KIT/VERSION" | tr '\n' ' ')"
else
	pass "the $version_now note enumerates each ticket once"
fi
{ printf '# %s — bait\n# From #1: a. From #1: again.\n#   NON-MANIFEST HALF: x\nshared-layer: %s\n' "$version_now" "$version_now"; } >"$SCRATCH/version.f5bbait"
[ -n "$(dup_refs "$version_now" "$SCRATCH/version.f5bbait")" ] &&
	pass "the duplicate-clause probe rejects a note that repeats a ticket" ||
	fail "the duplicate-clause probe passed a note that repeats a ticket — the check is vacuous"

# --- F3: the shared layer is REACHABLE — a declared release has its tag ----
# The lesson of the v0.9.0 wave, learned in a consumer's clone: UPDATING.md
# derives FROM_REF/TO_REF from release tags, so a VERSION bump that never gets
# its tag is a release no consumer can follow — declared, unshipped, invisible.
# Two legs, both ways:
#   (i)  the marker VERSION declares has a v-tag. RED on push to main — the
#        deliberate forcing function that makes cutting the tag part of
#        landing the bump — and a spoken note on pull requests, where the tag
#        rightly does not exist yet. Locally (no CI env) the tolerant arm runs.
#   (ii) the tag's content still matches the tree: a manifest-listed file that
#        drifted past the tag with no bump is the 0.5.0-interval failure — an
#        unreleased change wearing a released version's number. RED always,
#        pull requests included, because the drift is already in the diff.

# The manifest parser scripts/check.sh and UPDATING.md step 1 both use — same
# awk, so all three read one file format the same way.
manifest_files() {
	awk '
		/^files:/       { inlist = 1; next }
		!inlist         { next }
		/^[ \t]*#/      { next }
		/^[ \t]*$/      { next }
		/^[ \t]+[^ \t]/ { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print; next }
		                { inlist = 0 }
	' "$KIT/VERSION"
}

if git -C "$KIT" rev-parse -q --verify "v$version_now^{commit}" >/dev/null 2>&1; then
	pass "the declared shared layer has its tag (v$version_now)"
	drift=0
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		if ! git -C "$KIT" cat-file -e "v$version_now:$f" 2>/dev/null; then
			# Absent at the tag is its own failure, not "differs": a joined
			# file — even an EMPTY one, which a bare cmp against empty stdin
			# would wave through — is a layer change wearing an old number.
			fail "$f is manifest-listed but absent at v$version_now — a file joined the layer with no bump"
			drift=$((drift + 1))
		elif git -C "$KIT" show "v$version_now:$f" 2>/dev/null | cmp -s - "$KIT/$f"; then
			:
		else
			fail "$f differs from v$version_now — shared content drifted past the tag with no bump (bump VERSION, or the change is unreachable)"
			drift=$((drift + 1))
		fi
	done <<EOF
$(manifest_files)
EOF
	[ "$drift" = 0 ] &&
		pass "every manifest-listed file is byte-identical to v$version_now"
else
	if [ "${GITHUB_EVENT_NAME:-}" = "push" ]; then
		fail "shared-layer $version_now has NO tag — an untagged bump is a release no consumer can reach. Cut it: git tag -a v$version_now <merge sha> && git push origin v$version_now"
	else
		printf '  --    v%s does not exist yet — fine before the bump merges; on main this stays RED until the tag is cut\n' "$version_now"
	fi
fi

# --- F4: the skills manifest names exactly the shipped set ------------------
#
# Skills are versioned as a SET — by name and release, never by bytes: adapting
# a skill's prose locally is the intended workflow, so a byte check would flag
# every invited edit. What the manifest owes a consumer is the NAME list, and
# it owes it as STATE, not delta: the update recipe diffs `skills:` in VERSION
# against the consumer's installed set, so any number of skipped update windows
# still yields the exact missing list. A manifest that drifts from the shipped
# directories re-opens the gap it exists to close, in one of two ways: a
# shipped skill the manifest misses is invisible to every consumer forever,
# and a manifest entry with no directory promises a skill the release does not
# ship. Both directions fail here.
#
# An entry may carry an annotation after the name (the optional skill does);
# only the first word is the name. The list also must NOT leak into the files:
# parser above — `skills:` is a sibling section, and a parser that swallowed it
# would tell step 5 of the recipe to copy skill names as shared files.

manifest_skills() {
	awk '
		/^skills:/      { inlist = 1; next }
		!inlist         { next }
		/^[ \t]*#/      { next }
		/^[ \t]*$/      { next }
		/^[ \t]+[^ \t]/ { sub(/^[ \t]+/, ""); print $1; next }
		                { inlist = 0 }
	' "$KIT/VERSION"
}

manifest_skills | sort >"$SCRATCH/skills.manifest"
for d in "$KIT"/.agents/skills/*/; do
	basename "$d"
done | sort >"$SCRATCH/skills.shipped"

# The bridge holds, per skill: every canonical directory has a .claude/skills
# symlink that resolves back to it, and no bridge entry is a stray real file.
# Written as a function over a root so the SAME code can be pointed at a tree
# built to fail it — the f5_check convention below, applied here.
bridge_bad_for() {
	_root="$1"
	_bad=""
	for _d in "$_root"/.agents/skills/*/; do
		[ -d "$_d" ] || continue
		_s=$(basename "$_d")
		if [ ! -L "$_root/.claude/skills/$_s" ] || [ ! -f "$_root/.claude/skills/$_s/SKILL.md" ]; then
			_bad="$_bad $_s"
		fi
	done
	# The licence is a FILE symlink, not a directory one, and bootstrap lays it
	# deliberately so an adopted tree matches a templated one — the directory
	# glob above would never see it.
	for _f in "$_root"/.agents/skills/*.md; do
		[ -f "$_f" ] || continue
		_b=$(basename "$_f")
		if [ ! -L "$_root/.claude/skills/$_b" ] || [ ! -f "$_root/.claude/skills/$_b" ]; then
			_bad="$_bad $_b"
		fi
	done
	printf '%s' "$_bad"
}

bridge_bad=$(bridge_bad_for "$KIT")
if [ -z "$bridge_bad" ]; then
	pass "every canonical skill and sidecar has a resolving .claude/skills bridge"
else
	fail "bridge broken or missing for:$bridge_bad — the harness that reads only .claude/skills goes blind there"
fi

# …and the leg is not vacuous. The previous form of this probe asked whether a
# name that was never created lacks a bridge, which is true of any nonexistent
# path however the loop above behaves — it passed even when the loop was broken.
# Drive the real code instead: a tree with a canonical skill and a canonical
# sidecar, neither bridged, must come back naming both.
probe_root="$SCRATCH/bridge-probe"
mkdir -p "$probe_root/.agents/skills/probe-skill" "$probe_root/.claude/skills"
: >"$probe_root/.agents/skills/probe-skill/SKILL.md"
: >"$probe_root/.agents/skills/probe-sidecar.md"
probe_bad=$(bridge_bad_for "$probe_root")
case " $probe_bad " in
*" probe-skill "*)
	case " $probe_bad " in
	*" probe-sidecar.md "*)
		pass "the bridge check reports an unbridged skill AND an unbridged sidecar — it can go red"
		;;
	*) fail "the bridge check missed an unbridged SIDECAR (got:$probe_bad) — the *.md leg is vacuous" ;;
	esac
	;;
*) fail "the bridge check missed an unbridged SKILL (got:$probe_bad) — the directory leg is vacuous" ;;
esac

# The delta guard has to SEE the canonical skills home, or a wave that
# rewrites every skill in the kit reports no agent-surface change at all.
# tests/behavior-delta.test.sh cannot cover this: it drives the script with a
# synthetic four-surface config of its own, so the kit's real one is never
# read there and the entry could be deleted with that suite green.
#
# surface_covers <path> — the path matches some pattern in the kit's own
# BEHAVIOR_DELTA_SURFACES. Each record is `Label|re|re|…`; a label cannot
# match a path, so splitting on | and testing every field is enough.
surface_covers() {
	# The patterns come out through a FILE, not a pipe: a `while read` on the
	# right of a pipe runs in a subshell, so its `return` would leave the
	# loop rather than the function and every call answered "no match".
	# shellcheck source=/dev/null
	( . "$KIT/scripts/guards.config.sh" >/dev/null 2>&1
	  printf '%s\n' "$BEHAVIOR_DELTA_SURFACES" | tr '|' '\n' ) >"$SCRATCH/surfaces.re"
	while IFS= read -r _re; do
		[ -n "$_re" ] || continue
		printf '%s\n' "$1" | grep -Eq "$_re" && return 0
	done <"$SCRATCH/surfaces.re"
	return 1
}

if surface_covers ".agents/skills/tdd/SKILL.md"; then
	pass "the delta guard's surfaces cover the canonical skills home"
else
	fail "BEHAVIOR_DELTA_SURFACES does not match .agents/skills/… — a wave that rewrites every skill would report no agent-surface change"
fi
# …and the check discriminates: a path on no surface must not match, or the
# leg above would pass for any string at all.
if surface_covers "some/ordinary/file.txt"; then
	fail "the surface check matched a path on no surface — it is vacuous"
else
	pass "the surface check rejects a path on no surface — it can go red"
fi

if [ ! -s "$SCRATCH/skills.manifest" ]; then
	fail "VERSION has no skills: section — the skill set ships unversioned, and a consumer's update has no state to diff against"
else
	unshipped=$(comm -23 "$SCRATCH/skills.manifest" "$SCRATCH/skills.shipped")
	unlisted=$(comm -13 "$SCRATCH/skills.manifest" "$SCRATCH/skills.shipped")
	if [ -n "$unshipped" ]; then
		fail "manifest-listed but not shipped: $(printf '%s' "$unshipped" | tr '\n' ' ')— VERSION promises a skill this release does not carry"
	elif [ -n "$unlisted" ]; then
		fail "shipped but not manifest-listed: $(printf '%s' "$unlisted" | tr '\n' ' ')— invisible to every consumer's update, the exact gap the manifest closes"
	else
		pass "skills: in VERSION and .agents/skills/ name the same set ($(wc -l <"$SCRATCH/skills.manifest" | tr -d ' ') skills)"
	fi

	# First word only on BOTH sides: skills.manifest already holds first words,
	# and an annotated entry that leaked into the files list would otherwise
	# arrive as its whole line and never match. Paths have no spaces here, so
	# the files side loses nothing.
	leaked=$(manifest_files | awk '{ print $1 }' | sort | comm -12 - "$SCRATCH/skills.manifest")
	if [ -n "$leaked" ]; then
		fail "skills entries leak into the files: parser: $(printf '%s' "$leaked" | tr '\n' ' ')— the shared-file list would copy skill names as paths"
	else
		pass "the files: parser stops before skills: — no entry leaks between the sections"
	fi
fi

# --- F5: the current release note enumerates its non-manifest half ----------
#
# The manifest (F4) covers skills; everything else a wave ships outside the
# files: list — wiring bullets, template markers, workflow changes — has
# exactly one carrier: the release's history note in VERSION, which Part 2 of
# the recipe points consumers at. A wave that forgets the enumeration re-opens
# the #69 gap for every non-skill feature, so the CURRENT version's note must
# exist and must carry the enumeration marker. (The dots in the version are
# regex-any here, which can only ever make the match more permissive.)

# The window closes at the NEXT note heading as well as at shared-layer: —
# without that, a current note filed above an older one would let the older
# note's marker satisfy this check (found vacuous exactly that way by the
# independent review of the 0.13.0 wave).
f5_check() {
	awk -v v="$version_now" '
		$0 ~ ("^# " v " — ") { innote = 1; next }
		innote && /^# [0-9]+\.[0-9]+\.[0-9]+ — / { innote = 0 }
		innote && /NON-MANIFEST HALF/ { hit = 1 }
		/^shared-layer:/ { innote = 0 }
		END { exit !hit }
	' "$1"
}

if f5_check "$KIT/VERSION"; then
	pass "the $version_now history note enumerates its NON-MANIFEST HALF"
else
	fail "VERSION's $version_now note is missing or has no 'NON-MANIFEST HALF' enumeration — the recipe's Part 2 has nothing to point a consumer at"
fi

# …and the check is not vacuous: the same awk over a copy whose marker is
# rewritten must fail (the C4f/C4h bait convention — a green-on-arrival check
# earns its keep by proving it can go red).
sed 's/NON-MANIFEST HALF/nonmanifest part/' "$KIT/VERSION" >"$SCRATCH/version.f5bait"
if f5_check "$SCRATCH/version.f5bait"; then
	fail "F5's pattern passed a note whose enumeration marker was rewritten — the check is vacuous"
else
	pass "F5's pattern fails when the enumeration marker is absent"
fi

# …and the window really is ONE note: gut only the current note's marker while
# an OLDER note keeps its own, and the check must still fail. This is the
# vacuity the review reproduced — a current note filed out of order borrowed
# the 0.12.0 note's marker and passed.
awk -v v="$version_now" '
	$0 ~ ("^# " v " — ") { innote = 1; print; next }
	innote && /^# [0-9]+\.[0-9]+\.[0-9]+ — / { innote = 0 }
	/^shared-layer:/ { innote = 0 }
	innote { gsub(/NON-MANIFEST HALF/, "nonmanifest part") }
	{ print }
' "$KIT/VERSION" >"$SCRATCH/version.f5bait2"
if f5_check "$SCRATCH/version.f5bait2"; then
	fail "F5 passed when only an OLDER note carries the marker — the window spans more than the current note"
else
	pass "F5's window is the current note alone — an older note's marker cannot stand in"
fi

t_done "self-host"
