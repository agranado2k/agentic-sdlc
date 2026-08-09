#!/bin/sh
# F3's acceptance test — the cross-provider AI review workflow template.
#
# WHAT THIS CAN AND CANNOT PROVE, stated up front because the honest boundary is
# the point:
#
#   Simulable here (and checked below): the template is a FILE, so everything
#   about the file is machine-checkable — it parses as YAML, it carries the
#   invariants it claims (PR triggers, advisory steps, concurrency cancel,
#   read-only contents), it names no merge/approve/push verb, its two provider
#   jobs differ only at the three marked choice points, its two prompts have not
#   drifted apart, and the prompt points at this kit's manual rather than at the
#   product it was extracted from. Then bootstrap really runs, and the file is
#   really still inert on the other side.
#
#   NOT simulable at all, and deliberately not faked: whether GitHub Actions
#   accepts the workflow, whether either vendor's action still takes these
#   inputs, and whether the review a model posts is any good. Those need a live
#   forge, live actions and live credentials. A mocked run would only prove the
#   mock was called — a test that cannot fail for the reason it claims to exist
#   (shared invariant §3). What IS asserted is the file that drives them.
#
#   The YAML parse needs a YAML parser, and the kit's core is POSIX sh with no
#   runtime. So the parse runs on python3 or ruby when one is present and SAYS
#   SO when neither is — the same stance scripts/check.sh takes about node.
#
# Usage: sh tests/ai-review-template.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"

TPL="templates/workflows/ai-review.example.yml"
TPL_ABS="$ROOT/$TPL"

cd "$ROOT" || exit 2
t_init

skip() { printf '  skip  %s\n' "$*"; }
has() { grep -qF -- "$1" "$TPL_ABS"; }

assert_has() {
	if has "$1"; then
		pass "the template says '$1'"
	else
		fail "the template never says '$1'"
	fi
}

assert_lacks() {
	if has "$1"; then
		fail "the template contains '$1' — $2"
		grep -nF -- "$1" "$TPL_ABS" | sed 's/^/        | /'
	else
		pass "no '$1' anywhere in the template ($2)"
	fi
}

# ---------------------------------------------------------------------------
banner "0. The file under test, and the suffix that keeps it off"
# ---------------------------------------------------------------------------
[ -f "$TPL_ABS" ] && pass "$TPL exists" || {
	fail "$TPL is missing — nothing else in this suite means anything"
	t_done "AI review workflow template"
}

# The whole install contract rests on the suffix: GitHub Actions reads .yml and
# .yaml, so `.example.yml` is a file it never loads. If a future edit renames
# this to ai-review.yml inside the kit, bootstrap would install a LIVE workflow
# into every consumer project — the exact opposite of the ticket.
case "$TPL" in
*.example.yml) pass "the name ends in .example.yml — GitHub Actions will not load it" ;;
*) fail "$TPL is not a .example.yml — it would install as a live workflow" ;;
esac
[ -e "$ROOT/templates/workflows/ai-review.yml" ] &&
	fail "templates/workflows/ai-review.yml exists — an active twin of the example" ||
	pass "no active ai-review.yml ships beside the example"

# ---------------------------------------------------------------------------
banner "1. It parses as YAML — really parsed, not pattern-matched"
# ---------------------------------------------------------------------------
# Every shipped workflow template goes through the parser, not just the new one:
# a template repo whose templates do not parse hands every consumer a broken
# .github/workflows/ on day one, and bootstrap copies them sight unseen.
PARSER=""
if python3 -c 'import yaml' >/dev/null 2>&1; then
	PARSER="python3"
elif command -v ruby >/dev/null 2>&1 && ruby -ryaml -e '' >/dev/null 2>&1; then
	PARSER="ruby"
fi

yaml_parse() { # yaml_parse <file> — exit 0 if it parses
	case "$PARSER" in
	python3) python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$1" ;;
	ruby) ruby -ryaml -e 'YAML.safe_load(File.read(ARGV[0]), aliases: false)' "$1" ;;
	*) return 0 ;;
	esac
}

if [ -n "$PARSER" ]; then
	pass "YAML parser available ($PARSER)"
	for f in "$ROOT"/templates/workflows/*; do
		[ -e "$f" ] || continue
		if err=$(yaml_parse "$f" 2>&1); then
			pass "$(basename "$f") parses as YAML"
		else
			fail "$(basename "$f") is not valid YAML"
			printf '%s\n' "$err" | sed 's/^/        | /'
		fi
	done
else
	skip "no python3+PyYAML and no ruby — the YAML parse is NOT covered on this machine"
	skip "  (the kit's own CI has both; the structural checks below still run)"
fi

# Structural, parser-free, and therefore always run: tabs are illegal as YAML
# indentation and are the single most common way a hand-edited workflow dies.
if grep -q "$(printf '\t')" "$TPL_ABS"; then
	fail "the template contains a TAB — YAML forbids tabs as indentation"
else
	pass "no tabs — indentation is spaces throughout"
fi

# ---------------------------------------------------------------------------
banner "2. The invariants the header claims are actually in the file"
# ---------------------------------------------------------------------------
# Each of these is a line the header promises. A header that promises what the
# YAML does not do is worse than no header: it is a rule nothing checks.
assert_has "types: [opened, synchronize, ready_for_review, reopened]"
assert_has "cancel-in-progress: true"
assert_has "contents: read"
assert_has "pull-requests: write"

# Advisory means every step that talks to a vendor is continue-on-error. Two
# provider jobs, so two of them; a third provider added without one turns a
# vendor outage into a red PR.
coe=$(grep -c 'continue-on-error: true' "$TPL_ABS")
[ "$coe" -ge 2 ] &&
	pass "$coe review steps are continue-on-error (advisory, per the header)" ||
	fail "only $coe continue-on-error steps — an outage would fail the PR check"

# The instruction not to make these required checks is the operator-facing half
# of "advisory", and it lives nowhere else.
assert_has "REQUIRED STATUS CHECKS"

# ---------------------------------------------------------------------------
banner "3. Nothing here can land a change (shared invariant §7)"
# ---------------------------------------------------------------------------
# These jobs hold a token with write on the PR conversation. The boundary
# between "posts a review" and "lands the change" is exactly this list.
assert_lacks "gh pr merge" "merging is the human's action (shared invariant §7)"
assert_lacks "pr review --approve" "a bot approving is not review"
assert_lacks "git push" "a review workflow never writes to the branch"
assert_lacks "contents: write" "read-only on contents is what makes it a reviewer"
assert_lacks "--auto" "auto-merge is a merge with a delay"
# And the prompt has to say it too — permissions stop the action, the prompt
# stops the attempt (and the confusing half-done state it leaves behind).
assert_has "do not approve, do not merge"

# ---------------------------------------------------------------------------
banner "4. Two providers, and the three choice points marked in both"
# ---------------------------------------------------------------------------
# The file shape decision: ONE example holding TWO filled variants, because the
# cross-provider leg IS the feature — a single-provider example would ship the
# plumbing and drop the point. The markers are what make it a template rather
# than two workflows glued together: they say which lines a third provider
# changes.
for job in "claude-review:" "gemini-review:"; do
	assert_has "$job"
done

for choice in "PROVIDER CHOICE 1/3" "PROVIDER CHOICE 2/3" "PROVIDER CHOICE 3/3"; do
	n=$(grep -cF -- "$choice" "$TPL_ABS")
	[ "$n" -ge 2 ] &&
		pass "'$choice' is marked in both jobs ($n occurrences)" ||
		fail "'$choice' appears $n time(s) — it must be marked in every provider job"
done

# A provider with no secret configured must be a skip, not a red step: renaming
# the file with one key (or none) is the common case, and a workflow that is red
# by default is a workflow everybody learns to ignore.
gates=$(grep -c 'Is this provider configured?' "$TPL_ABS")
[ "$gates" -ge 2 ] &&
	pass "each provider job gates itself on its own secret ($gates gates)" ||
	fail "only $gates secret gates — an unconfigured provider would fail on every PR"

# ---------------------------------------------------------------------------
banner "5. The two prompts have not drifted apart"
# ---------------------------------------------------------------------------
# Asking two vendors different questions and comparing the answers measures the
# prompts, not the models — which destroys the only reason to run two.
extract_prompts() {
	awk '
		function ind(l,	n) { n = match(l, /[^ ]/); return n ? n - 1 : -1 }
		/^[ ]*prompt: \|[ ]*$/ && !collecting { collecting = 1; base = ind($0); n++; next }
		collecting {
			if ($0 ~ /^[ ]*$/) { print n "\t"; next }
			if (ind($0) > base) { print n "\t" substr($0, base + 3); next }
			collecting = 0
		}
	' "$TPL_ABS"
}
extract_prompts >"$SCRATCH/prompts.txt"
sed -n 's/^1	//p' "$SCRATCH/prompts.txt" >"$SCRATCH/p1.txt"
sed -n 's/^2	//p' "$SCRATCH/prompts.txt" >"$SCRATCH/p2.txt"

if [ ! -s "$SCRATCH/p1.txt" ] || [ ! -s "$SCRATCH/p2.txt" ]; then
	fail "could not extract two block prompts from the template"
elif cmp -s "$SCRATCH/p1.txt" "$SCRATCH/p2.txt"; then
	pass "both provider prompts are byte-identical ($(wc -l <"$SCRATCH/p1.txt" | tr -d ' ') lines each)"
else
	fail "the two provider prompts have drifted apart"
	diff "$SCRATCH/p1.txt" "$SCRATCH/p2.txt" | sed 's/^/        | /'
fi

# ---------------------------------------------------------------------------
banner "6. The prompt is de-productized — it points at the manual, not at rules"
# ---------------------------------------------------------------------------
# This template was extracted from a real project whose prompts enumerated that
# project's own decision records. Copying those in would ship a second, stale
# copy of somebody else's rulebook. The generalized prompt REFERENCES instead.
assert_has "AGENTS.md"
assert_has "constitution/"
assert_has "shared-invariants.md"
assert_has "docs/adr/"

# The two-axis split is the one rule the prompt states rather than references,
# because it describes the shape of the review's own output and no reviewer
# infers it (shared invariant §5).
assert_has "AXIS 1 — STANDARDS"
assert_has "AXIS 2 — BEHAVIOR"
assert_has "CONFIRM-LIST"
# Axis 2 is human-only. A bot that answers its own confirm-list has quietly
# converted a human decision into an autonomous one.
assert_has "Do not answer them yourself, do not resolve them"

# The extraction source's product vocabulary must not have come along for the
# ride. Numbered ADR citations are the tell: they are true of exactly one repo.
# Each token here is a literal SUBSTRING search, so it has to be one that cannot
# occur innocently — "viewer" was tried and rejected, because "reviewer".
for leak in "ADR-0" "Centaur" "fp-ts" "Remeda" "Origin-Agent-Cluster" "db-design"; do
	if has "$leak"; then
		fail "'$leak' leaked in from the extraction source — this template is project-agnostic"
		grep -nF -- "$leak" "$TPL_ABS" | sed 's/^/        | /'
	else
		pass "no '$leak' — the source project's vocabulary stayed behind"
	fi
done

# ---------------------------------------------------------------------------
banner "7. The docs that point at this template still resolve"
# ---------------------------------------------------------------------------
# /implement's Deliver phase names the forge-workflow mechanism first-class and
# now names THIS file as the kit's one. A pointer nothing checks is the stale
# standing instruction shared invariant §8 exists to prevent.
SKILL="$ROOT/.claude/skills/implement/SKILL.md"
if grep -qF ".github/workflows/ai-review.example.yml" "$SKILL"; then
	pass "/implement's Deliver phase points at the installed template"
else
	fail "/implement never names .github/workflows/ai-review.example.yml"
fi
if grep -qF "ai-review.example.yml" "$ROOT/README.md"; then
	pass "README documents the template"
else
	fail "README does not mention ai-review.example.yml"
fi

# ---------------------------------------------------------------------------
banner "8. Bootstrap installs it — and it is still INERT on the other side"
# ---------------------------------------------------------------------------
# The claim under test is a whole install, so it gets a whole install: a real
# copy of the kit, a real git repo, the real bootstrap.sh.
PROJ="$SCRATCH/consumer"
mkdir -p "$PROJ"
cp -R "$ROOT/." "$PROJ/"
rm -rf "$PROJ/.git"
(
	cd "$PROJ" || exit 2
	git init -q -b main
	git config user.name "AI Review Fixture"
	git config user.email "fixture@example.invalid"
	git config commit.gpgsign false
	git add -A
) || exit 2

assert_status 0 "bootstrap.sh runs in the consumer" -- \
	sh -c "cd '$PROJ' && sh bootstrap.sh 'Consumer Project' 'Proves the review template installs inert.'"
# Bootstrap's next-steps text is the only place a human is told the file is
# there and switched off. Without the mention, the file is a directory nobody
# introduced (the same reasoning K5 applies to adapters/).
assert_out_has "ai-review.example.yml"

[ -f "$PROJ/.github/workflows/ai-review.example.yml" ] &&
	pass ".github/workflows/ai-review.example.yml was installed" ||
	fail "the template was not installed into .github/workflows/"

# THE inertness assertion. Anything GitHub Actions would load is a live
# workflow; the example must not be one, and must not have grown a live twin.
for live in ai-review.yml ai-review.yaml ai-review.example.yaml; do
	[ -e "$PROJ/.github/workflows/$live" ] &&
		fail ".github/workflows/$live exists — the review workflow installed ACTIVE" ||
		pass "no .github/workflows/$live — nothing loadable was installed"
done

# Same install contract as commitlint: present, suffixed, off. If commitlint
# ever stops shipping this way, the sentence "like commitlint" in the header
# needs rewriting, and this is what notices.
[ -f "$PROJ/.github/workflows/commitlint.yml.example" ] &&
	pass "commitlint.yml.example installs the same way (the contract this copies)" ||
	fail "commitlint.yml.example is not installed as an example — the contracts have diverged"

# Copied verbatim, never stamped: a workflow with an unstamped {{MARK}} in it
# would be a broken file the docs gate then reports on forever.
if cmp -s "$TPL_ABS" "$PROJ/.github/workflows/ai-review.example.yml"; then
	pass "installed byte-for-byte identical to the kit's copy (copied, not stamped)"
else
	fail "the installed template differs from the kit's copy"
fi

# And the templates directory is gone, so there is no second copy to edit.
[ -e "$PROJ/templates/workflows" ] &&
	fail "templates/workflows survived bootstrap — two copies, one of them stale" ||
	pass "templates/workflows was removed after the install"

# The gate must be green on the tree that now carries the template.
assert_status 0 "the docs gate passes on the bootstrapped consumer" -- \
	sh -c "cd '$PROJ' && sh scripts/check.sh"

t_done "AI review workflow template"
