#!/bin/sh
# tests/vocab-policy.test.sh — the shipped vocabularies, held to the skills
# that use them.
#
# scripts/vocab.config.sh ships FILLED, and every word in it is a word some
# skill already prints or reads: /review-pr's severity buckets and confirm-list
# tags, /pr-iterate's triage verbs, /to-tickets' tier stamp and autonomy label,
# /dogfood's row readings, the resolver's four tier names. A token added to a
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

# field_tokens <field> — the shipped file's tokens for a field, through the
# script's own reader, so the suite parses nothing itself.
FIELDS=$(VOCAB_CONFIG="$POLICY" sh "$VOCAB" fields 2>"$SCRATCH/fields.err") || {
	fail "the shipped policy file does not load: $(cat "$SCRATCH/fields.err")"
	t_done "vocab-policy"
}
field_tokens() { printf '%s\n' "$FIELDS" | sed -n "s/^$1\( (open)\)\{0,1\}: //p"; }

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
: >"$SCRATCH/empty.config.sh"
DEFAULTS=$(VOCAB_CONFIG="$SCRATCH/empty.config.sh" sh "$VOCAB" fields 2>/dev/null)
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
banner "2. tier — the resolver's literal, and /to-tickets' stamp"
# ---------------------------------------------------------------------------
resolver_tiers=$(sed -n 's/^[[:space:]]*\([a-z]* | [a-z]* | [a-z]* | [a-z]*\)) _rt_known=1 ;;$/\1/p' "$RESOLVER" | sed 's/ | / /g')
assert_equal "the tier vocabulary is the resolver's four names, in its order" "$resolver_tiers" "$(field_tokens tier)"
stamp_tiers=$(sed -n 's/.*`Tier: <\([a-z|]*\)>`.*/\1/p' "$TICKETS" | head -1 | tr '|' ' ')
assert_equal "/to-tickets stamps the same four, in the same order" "$stamp_tiers" "$(field_tokens tier)"
assert_file_has "$POLICY" "tier — owned by scripts/agents.lib.sh" "the file says the tier is not its to widen"

# ---------------------------------------------------------------------------
banner "3. label — one name and its absence"
# ---------------------------------------------------------------------------
assert_file_has "$TICKETS" '**`ready-for-agent` label**' "the one autonomy label"
assert_file_has "$TICKETS" '**no label**' "and its absence"
assert_equal "the label vocabulary is the name and the absence" "ready-for-agent none" "$(field_tokens label)"

# ---------------------------------------------------------------------------
banner "4. domain — open, and every shipped token is one the glossary names"
# ---------------------------------------------------------------------------
printf '%s\n' "$FIELDS" | grep -q '^domain (open):' && pass "the task domain is declared open" ||
	fail "the task domain must be OPEN — its vocabulary is local policy (ADR-0007)"
for tok in $(field_tokens domain); do
	grep -q -F -- "\`$tok\`" "$GLOSSARY" && pass "domain token '$tok' is a name the glossary uses" ||
		fail "domain token '$tok' is not spelled anywhere in docs/domain-glossary.md"
done

# ---------------------------------------------------------------------------
banner "5. severity — /review-pr's count table, in its order"
# ---------------------------------------------------------------------------
table_severities=$(sed -n 's/^| [^|]* | \([A-Z]*\) | X |$/\1/p' "$REVIEW" | tr 'A-Z' 'a-z' | tr '\n' ' ' | sed 's/ $//')
assert_equal "the severity vocabulary is the report's four buckets, top to bottom" "$table_severities" "$(field_tokens severity)"

# ---------------------------------------------------------------------------
banner "6. status — /review-pr's confirm-list tags, in the list's order"
# ---------------------------------------------------------------------------
# The §5b fence: glyph, TAG in capitals, then the item. 🧬 MUTATION is on the
# list and is deliberately NOT a token — the skill says it is a measurement,
# not a classification — so the extractor drops it and the suite holds the
# skill to still saying so.
fence_tags=$(awk '/present Agent 7.s output verbatim in this shape/ { on = 1; next } on && /^```$/ { if (seen) exit; seen = 1; next } on && seen { print }' "$REVIEW" |
	sed -n 's/^[^ ]* \([A-Z][A-Z ]*[A-Z]\)  *<.*/\1/p' | grep -v '^MUTATION$' | tr 'A-Z ' 'a-z-' | tr '\n' ' ' | sed 's/ $//')
assert_equal "the status vocabulary is the confirm-list's tags, in the list's order" "$fence_tags" "$(field_tokens status)"
assert_file_has "$REVIEW" "It is **not** a classification" "the mutation line is a measurement, so it is no token"

# ---------------------------------------------------------------------------
banner "7. action — /pr-iterate's three triage arrows, in their order"
# ---------------------------------------------------------------------------
arrows=$(sed -n 's/^- If the suggestion .*→ \*\*\([a-z]*\).*/\1/p' "$ITERATE" | tr '\n' ' ' | sed 's/ $//')
assert_equal "the action vocabulary is the triage's three verbs, in the skill's order" "$arrows" "$(field_tokens action)"

# ---------------------------------------------------------------------------
banner "8. outcome — /dogfood's two readings of a row"
# ---------------------------------------------------------------------------
assert_file_has "$DOGFOOD" "decides pass or fail" "the binary reading"
assert_file_has "$DOGFOOD" "**paper cuts**" "the decency reading"
assert_equal "the outcome vocabulary is pass, fail and the paper cut" "pass fail paper-cut" "$(field_tokens outcome)"

# ---------------------------------------------------------------------------
banner "9. confidence — three tokens, as the PRD sizes it"
# ---------------------------------------------------------------------------
# No skill stamps a confidence yet — that is the confidence ticket's slice,
# and its text probe joins this section when it lands. What the PRD fixes
# now is the size: three, so a quiz can sort low first.
n=$(field_tokens confidence | wc -w | tr -d ' ')
[ "$n" = 3 ] && pass "the confidence vocabulary has three tokens" || fail "the confidence vocabulary has $n tokens, the PRD says three"

# ---------------------------------------------------------------------------
banner "10. The one shipped rule is the trust boundary's"
# ---------------------------------------------------------------------------
printf '%s\n' "$FIELDS" | grep -q -F 'rule: command-shaped=yes => action!=apply' &&
	pass "a command-shaped body never triages as apply" ||
	fail "the shipped rule 'command-shaped=yes => action!=apply' is missing"

t_done "vocab-policy"
