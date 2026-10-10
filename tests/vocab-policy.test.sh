#!/bin/sh
# tests/vocab-policy.test.sh — the shipped vocabularies, held to the skills
# that use them.
#
# scripts/vocab.config.sh ships FILLED, and every word in it is a word some
# skill already prints or reads: /review-pr's severity buckets and confirm-list
# tags, /pr-iterate's triage verbs, /to-tickets' tier stamp, autonomy label and
# confidence stamp, /dogfood's row readings, the resolver's four tier names. A
# token added to a
# skill's prose without this file, or to this file without the skill, is the
# drift the checker exists to refuse — so this suite reads each vocabulary
# OUT OF THE SKILL'S OWN TEXT and holds the policy file equal to it, order
# included, wherever the skill spells its set in one place. Where a skill
# spells a set by construction rather than as a list (the label: one name and
# its absence), the direction that can be checked is.
#
# It also holds the shipped file to the checker's built-in defaults: the two
# are one vocabulary spelled twice on purpose (a project that deletes the file
# is held to the same words), and a drift between them would make "delete it"
# and "keep it" mean different things.
#
# Usage: sh tests/vocab-policy.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
VOCAB="$KIT/scripts/vocab.sh"
POLICY="$KIT/scripts/vocab.config.sh"
REVIEW="$KIT/.agents/skills/review-pr/SKILL.md"
ITERATE="$KIT/.agents/skills/pr-iterate/SKILL.md"
TICKETS="$KIT/.agents/skills/to-tickets/SKILL.md"
DOGFOOD="$KIT/.agents/skills/dogfood/SKILL.md"
RESOLVER="$KIT/scripts/agents.lib.sh"
GLOSSARY="$KIT/docs/domain-glossary.md"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

# t_field_tokens <field> is sourced from tests/lib.sh — the shipped file's
# tokens for a field, through the script's own reader, so the suite parses
# nothing itself.
FIELDS=$(VOCAB_CONFIG="$POLICY" sh "$VOCAB" fields 2>"$SCRATCH/fields.err") || {
	fail "the shipped policy file does not load: $(cat "$SCRATCH/fields.err")"
	t_done "vocab-policy"
}

# assert_equal <label> <expected> <actual>
assert_equal() {
	if [ "$2" = "$3" ]; then
		pass "$1"
	else
		fail "$1 — skill spells '$2', policy file spells '$3'"
	fi
}

# ---------------------------------------------------------------------------
banner "0. The files under test"
# ---------------------------------------------------------------------------
for f in "$POLICY" "$REVIEW" "$ITERATE" "$TICKETS" "$DOGFOOD" "$RESOLVER"; do
	[ -f "$f" ] && pass "${f#"$KIT"/} exists" || fail "${f#"$KIT"/} is missing"
done

# ---------------------------------------------------------------------------
banner "1. The shipped file restates the checker's defaults, line for line"
# ---------------------------------------------------------------------------
# The defaults are read the one way they apply: a copy of the script with no
# policy file anywhere near it — not an empty file, which declares nothing
# and is refused at load.
mkdir -p "$SCRATCH/bare" && cp "$VOCAB" "$SCRATCH/bare/vocab.sh"
DEFAULTS=$(sh "$SCRATCH/bare/vocab.sh" fields 2>"$SCRATCH/bare.err") ||
	fail "a bare copy of the checker does not load its own defaults: $(cat "$SCRATCH/bare.err")"
if [ "$DEFAULTS" = "$FIELDS" ]; then
	pass "scripts/vocab.config.sh and the checker's built-in defaults are one vocabulary"
else
	fail "the shipped policy file and the checker's defaults have drifted apart"
	printf '%s\n' "$DEFAULTS" >"$SCRATCH/defaults"
	printf '%s\n' "$FIELDS" >"$SCRATCH/shipped"
	diff -u "$SCRATCH/defaults" "$SCRATCH/shipped" | sed -e '1,2d' -e 's/^/        | /'
fi
# …and it is the file the kit itself is held to: run from the kit with no
# env var, discovery finds this file (order 2), not another.
t_run_split sh "$VOCAB" fields
[ "$S_OUT" = "$FIELDS" ] && pass "run from the kit, the checker reads scripts/vocab.config.sh" ||
	fail "run from the kit, the checker read something other than the shipped policy file"

# ---------------------------------------------------------------------------
banner "2. tier — the resolver's one spelling, and /to-tickets' stamp"
# ---------------------------------------------------------------------------
resolver_tiers=$(sh -c ". '$RESOLVER'; agents_tier_names")
assert_equal "the tier vocabulary is the resolver's four names, in its order" "$resolver_tiers" "$(t_field_tokens tier)"
stamp_tiers=$(sed -n 's/.*`Tier: <\([a-z|]*\)>`.*/\1/p' "$TICKETS" | head -1 | tr '|' ' ')
assert_equal "/to-tickets stamps the same four, in the same order" "$stamp_tiers" "$(t_field_tokens tier)"
assert_file_has "$POLICY" "tier — owned by scripts/agents.lib.sh" "the file says the tier is not its to widen"

# ---------------------------------------------------------------------------
banner "3. label — one name and its absence"
# ---------------------------------------------------------------------------
assert_file_has "$TICKETS" '**`ready-for-agent` label**' "the one autonomy label"
assert_file_has "$TICKETS" '**no label**' "and its absence"
# EXTRACTED, not restated: the skill's own trace line spells both tokens in
# the vocabulary's order — `data.label='<ready-for-agent, or none>'` — so a
# token renamed in the skill's prose and not here goes red, which is the
# direction a literal could not see.
skill_labels=$(sed -n "s/.*data\.label='<\([a-z][a-z0-9-]*\), or \([a-z][a-z0-9-]*\)>'.*/\1 \2/p" "$TICKETS" | head -1)
[ -n "$skill_labels" ] || fail "/to-tickets no longer spells the label pair in its ticket.write line — the extractor has nothing to read"
assert_equal "the label vocabulary is the pair /to-tickets writes, in its order" "$skill_labels" "$(t_field_tokens label)"

# ---------------------------------------------------------------------------
banner "4. domain — open, and every shipped token is one the glossary names"
# ---------------------------------------------------------------------------
# NOT extracted, and it cannot be: the task domain's vocabulary is OPEN local
# policy (ADR-0007), so no skill spells a closed set to compare against — an
# unmapped token is a working state, not a drift. The glossary is the only
# oracle available, and naming every shipped token there is the whole check.
printf '%s\n' "$FIELDS" | grep -q '^domain (open):' && pass "the task domain is declared open" ||
	fail "the task domain must be OPEN — its vocabulary is local policy (ADR-0007)"
for tok in $(t_field_tokens domain); do
	grep -q -F -- "\`$tok\`" "$GLOSSARY" && pass "domain token '$tok' is a name the glossary uses" ||
		fail "domain token '$tok' is not spelled anywhere in docs/domain-glossary.md"
done

# ---------------------------------------------------------------------------
banner "5. severity — /review-pr's count table, in its order"
# ---------------------------------------------------------------------------
table_severities=$(sed -n 's/^| [^|]* | \([A-Z]*\) | X |$/\1/p' "$REVIEW" | tr 'A-Z' 'a-z' | tr '\n' ' ' | sed 's/ $//')
assert_equal "the severity vocabulary is the report's four buckets, top to bottom" "$table_severities" "$(t_field_tokens severity)"

# ---------------------------------------------------------------------------
banner "6. status — /review-pr's confirm-list tags, in the list's order"
# ---------------------------------------------------------------------------
# The §5b fence: glyph, TAG in capitals, then the item. 🧬 MUTATION is on the
# list and is deliberately NOT a token — the skill says it is a measurement,
# not a classification — so the extractor drops it and the suite holds the
# skill to still saying so.
fence_tags=$(awk '/present Agent 7.s output verbatim in this shape/ { on = 1; next } on && /^```$/ { if (seen) exit; seen = 1; next } on && seen { print }' "$REVIEW" |
	sed -n 's/^[^ ]* \([A-Z][A-Z ]*[A-Z]\)  *<.*/\1/p' | grep -v '^MUTATION$' | tr 'A-Z ' 'a-z-' | tr '\n' ' ' | sed 's/ $//')
assert_equal "the status vocabulary is the confirm-list's tags, in the list's order" "$fence_tags" "$(t_field_tokens status)"
assert_file_has "$REVIEW" "It is **not** a classification" "the mutation line is a measurement, so it is no token"

# ---------------------------------------------------------------------------
banner "7. action — /pr-iterate's three triage arrows, in their order"
# ---------------------------------------------------------------------------
arrows=$(sed -n 's/^- If the suggestion .*→ \*\*\([a-z]*\).*/\1/p' "$ITERATE" | tr '\n' ' ' | sed 's/ $//')
assert_equal "the action vocabulary is the triage's three verbs, in the skill's order" "$arrows" "$(t_field_tokens action)"

# ---------------------------------------------------------------------------
banner "8. outcome — /dogfood's two readings of a row"
# ---------------------------------------------------------------------------
assert_file_has "$DOGFOOD" "decides pass or fail" "the binary reading"
assert_file_has "$DOGFOOD" "**paper cuts**" "the decency reading"
# EXTRACTED, not restated. The skill writes English and the vocabulary writes
# tokens, so the third reading is folded the way a field key is: the phrase
# `paper cuts` is singular-and-hyphenated to `paper-cut`. The first two need
# no fold. A reading renamed in the skill and not here now goes red.
skill_binary=$(sed -n 's/.*decides \([a-z][a-z0-9-]*\) or \([a-z][a-z0-9-]*\)\..*/\1 \2/p' "$DOGFOOD" | head -1)
skill_cut=$(sed -n 's/.*\*\*\([a-z][a-z0-9]*\) \([a-z][a-z0-9]*\)s\*\*.*/\1-\2/p' "$DOGFOOD" | head -1)
[ -n "$skill_binary" ] && [ -n "$skill_cut" ] ||
	fail "/dogfood no longer spells its readings where the extractor reads them"
assert_equal "the outcome vocabulary is the three readings /dogfood names" "$skill_binary $skill_cut" "$(t_field_tokens outcome)"

# ---------------------------------------------------------------------------
banner "9. confidence — /to-tickets' stamp, three tokens in its order"
# ---------------------------------------------------------------------------
# EXTRACTED, not restated: /to-tickets spells the set once, in the stamp's own
# shape — `Confidence: <low|medium|high>` — the way rule 9 spells the tier's.
# The size is the PRD's: three, so a quiz can sort the doubtful ones first.
# confidence_stamp <file> — the tokens of the first such stamp in a skill.
confidence_stamp() { sed -n 's/.*`Confidence: <\([a-z|-]*\)>`.*/\1/p' "$1" | head -1 | tr '|' ' '; }
skill_confidence=$(confidence_stamp "$TICKETS")
[ -n "$skill_confidence" ] || fail "/to-tickets spells no \`Confidence: <…>\` stamp — the extractor has nothing to read"
assert_equal "the confidence vocabulary is the three tokens /to-tickets stamps, in its order" "$skill_confidence" "$(t_field_tokens confidence)"
n=$(t_field_tokens confidence | wc -w | tr -d ' ')
[ "$n" = 3 ] && pass "the confidence vocabulary has three tokens" || fail "the confidence vocabulary has $n tokens, the PRD says three"
# BAIT — a rule with no failing check is a claim. Rename one token in a copy
# of the skill and nowhere else: the extractor must read the renamed set, so
# the comparison above would have gone red on it.
first=$(t_field_tokens confidence | cut -d' ' -f1)
sed "s/\`Confidence: <$first|/\`Confidence: <renamed|/" "$TICKETS" >"$SCRATCH/to-tickets.bait.md"
bait_confidence=$(confidence_stamp "$SCRATCH/to-tickets.bait.md")
if [ -n "$bait_confidence" ] && [ "$bait_confidence" != "$(t_field_tokens confidence)" ]; then
	pass "bait: a token renamed in the skill alone reads '$bait_confidence' — the comparison goes red on it"
else
	fail "bait: a token renamed in the skill alone was not seen (read '$bait_confidence') — the extractor is vacuous"
fi

# ---------------------------------------------------------------------------
banner "10. The one shipped rule is the trust boundary's"
# ---------------------------------------------------------------------------
printf '%s\n' "$FIELDS" | grep -q -F 'rule: command-shaped=yes => action!=apply' &&
	pass "a command-shaped body never triages as apply" ||
	fail "the shipped rule 'command-shaped=yes => action!=apply' is missing"

# ---------------------------------------------------------------------------
banner "11. author-kind — /pr-iterate's two kinds of review thread, in their order"
# ---------------------------------------------------------------------------
# The snapshot step buckets a thread by who wrote it, and the caller stamps
# that kind as a decision line from the forge's author data (#278) — the
# delegated read is never asked it. Read out of the two bucket
# headings — `**Bot review threads**`, `**Human threads**` — case folded.
kinds=$(sed -n 's/^- \*\*\([A-Z][a-z]*\) \(review \)\{0,1\}threads\*\*.*/\1/p' "$ITERATE" | tr 'A-Z\n' 'a-z ' | sed 's/ $//')
assert_equal "the author-kind vocabulary is the two thread kinds, in the skill's order" "$kinds" "$(t_field_tokens author-kind)"

# ---------------------------------------------------------------------------
banner "12. The four tier names are spelled together only in the vocabulary policy and its owner (#681)"
# ---------------------------------------------------------------------------
# The tier names live in the vocabulary policy and, once, in the resolver
# that owns them (the policy file's header says so): agents_tier_names. The
# resolver keeps that one spelling because it is also SOURCED with nothing
# anchoring it — no directory, so no checker or policy file it could find —
# and still owes such a caller a closed answer; section 2 holds it equal to
# the policy. Everything else — the dispatchers, bootstrap — reads the names
# from the resolver instead of spelling them. So three lines may carry the
# four names together: the policy file's VOCAB_TIER, the checker's shipped
# default it restates (section 1 holds them equal), and agents_tier_names.
# The adapter's hooks are out of reach on purpose — hook.lib.sh records its
# deliberate coupling: a hook reads no policy file to size a stop.
tier_spellers() {
	(cd "$1" && grep -rnE 'planner.{0,40}implementer.{0,40}mechanical.{0,40}reviewer' bootstrap.sh scripts) |
		grep -vE "^scripts/vocab(\.config)?\.sh:[0-9]+:[[:space:]]*VOCAB_TIER='[a-z ]*'\$" |
		grep -vE "^scripts/agents\.lib\.sh:[0-9]+:agents_tier_names\(\) \{ printf '%s' '[a-z ]*'; \}\$"
}
spellers=$(tier_spellers "$KIT")
assert_equal "no script and not bootstrap spells the four tier names together" "$spellers" ""

# BAIT — the grep must see a spelling where one is planted.
mkdir -p "$SCRATCH/bait-tiers/scripts"
printf '%s\n' "for t in planner implementer mechanical reviewer; do :; done" >"$SCRATCH/bait-tiers/bootstrap.sh"
printf '%s\n' "VOCAB_TIER='planner implementer mechanical reviewer'" >"$SCRATCH/bait-tiers/scripts/vocab.config.sh"
bait_spellers=$(tier_spellers "$SCRATCH/bait-tiers")
assert_equal "bait: a planted loop is found, the policy line is not" "$bait_spellers" "bootstrap.sh:1:for t in planner implementer mechanical reviewer; do :; done"
printf '%s\n' "agents_tier_names() { printf '%s' 'planner implementer mechanical reviewer'; }" \
	"echo 'tier is one of: planner implementer mechanical reviewer'" >"$SCRATCH/bait-tiers/scripts/agents.lib.sh"
bait_spellers=$(tier_spellers "$SCRATCH/bait-tiers" | sed 's/:.*//' | sort | tr '\n' ' ')
assert_equal "bait: the resolver's one function is allowed, a second spelling in it is not" "$bait_spellers" "bootstrap.sh scripts/agents.lib.sh "
bait_lines=$(tier_spellers "$SCRATCH/bait-tiers" | grep -c '^scripts/agents\.lib\.sh:')
assert_equal "bait: exactly the echo line of the planted resolver is found" "$bait_lines" "1"

# The names the dispatchers print are the resolver's, read rather than spelled.
t_run_split sh "$KIT/scripts/skill-dispatch.kit.sh" --phase-tier bogus
s_assert_status 2 "the skill dispatcher refuses an unknown phase"
s_assert_err_has "The vocabulary is closed: planner implementer tester mechanical reviewer." "…naming the phases, tester after implementer"
t_run_split sh "$KIT/scripts/agent-dispatch.sh"
s_assert_err_has "tier is one of: planner implementer mechanical reviewer" "the agent-harness dispatcher's usage names the resolver's tiers"

# A skill dispatcher with no resolver beside it says so, never "closed: ."
mkdir -p "$SCRATCH/lonely/scripts"
cp "$KIT/scripts/skill-dispatch.kit.sh" "$KIT/scripts/agents.kit.sh" "$KIT/scripts/agents.kit.config.sh" "$SCRATCH/lonely/scripts/"
t_run_split sh "$SCRATCH/lonely/scripts/skill-dispatch.kit.sh" --phase-tier reviewer
s_assert_status 2 "a skill dispatcher with no resolver beside it exits 2"
s_assert_err_has "cannot read the tier names" "…and says it could not read the tier names"

# Bootstrap asks the checker, not the resolver: a kit tree older than the
# resolver (docs-demo's 0.3.0 kit) still bootstraps and still strips the
# kit's agent types, one per tier.
OLDKIT="$SCRATCH/pre-resolver-kit"
t_kit_tree "$KIT" "$OLDKIT"
rm -f "$OLDKIT/scripts/agents.lib.sh"
(cd "$OLDKIT" && git init -q -b main && git config user.name t && git config user.email t@example.invalid &&
	git config commit.gpgsign false && git add -A && git commit -q -m init --no-verify)
t_run_split sh -c "cd '$OLDKIT' && sh bootstrap.sh 'Old Kit' 'A kit tree with no resolver.' </dev/null"
s_assert_status 0 "bootstrap runs in a kit tree with no resolver"
left=$(ls "$OLDKIT/.claude/agents" 2>/dev/null | tr '\n' ' ')
assert_equal "…and strips every tier's agent type" "$left" ""

t_done "vocab-policy"
