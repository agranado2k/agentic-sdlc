#!/bin/sh
# tests/skill-phase.test.sh — every skill declares the PHASE of work it is,
# and one command runs a skill on the model that phase maps to.
#
# The tier on a ticket says how much judgement that ticket is worth. It says
# nothing about the skill doing the work, so a session running `/review-pr`
# and one running `/to-tickets` resolved the same model even though the two
# are opposite kinds of work. A phase is that missing fact, and it belongs to
# the SKILL rather than to this repo: it is a claim about the work, not about
# a vendor's roster, so it ships in the skill's own frontmatter (a `metadata`
# key the Agent Skills specification already defines) and every consumer maps
# it onto their own models.
#
# What is asserted here: every shipped skill declares a phase; the vocabulary
# is closed and each phase resolves to a tier the resolver accepts (with
# `tester` the one that carries a domain, because the tier vocabulary is
# closed and a tester is implementer work on a different medium); and
# scripts/skill-dispatch.kit.sh turns a skill name into the right resolve.
#
# NOT simulable here: actually running another vendor's CLI. --dry-run is the
# seam, the same one tests/agent-dispatch.test.sh uses.
#
# Usage: sh tests/skill-phase.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

cd "$ROOT" || exit 2

DISPATCH="$ROOT/scripts/skill-dispatch.kit.sh"

# phase_of <skill dir> — the metadata.phase value, or empty.
phase_of() {
	awk '
		NR == 1 && /^---/ { fm = 1; next }
		fm && /^---/ { exit }
		fm && /^metadata:/ { in_meta = 1; next }
		in_meta && /^[A-Za-z]/ { in_meta = 0 }
		in_meta && /^[ \t]+phase:/ { sub(/^[ \t]+phase:[ \t]*/, ""); print; exit }
	' "$1/SKILL.md"
}

# ---------------------------------------------------------------------------
banner "1. Every shipped skill declares a phase, from a closed vocabulary"
# ---------------------------------------------------------------------------
# The five words are the four tiers plus `tester`. `tester` is not a fifth
# tier — the tier vocabulary is closed and widening it is a resolver change,
# a manual change and a release — it is implementer work whose medium is a
# test, which is what the domain axis is for.
PHASES="planner implementer tester mechanical reviewer"
declared=0
for d in .agents/skills/*/; do
	[ -f "$d/SKILL.md" ] || continue
	s=$(basename "$d")
	p=$(phase_of "$d")
	if [ -z "$p" ]; then
		fail "$s declares no metadata.phase — a session running it cannot resolve the model its work deserves"
		continue
	fi
	case " $PHASES " in
	*" $p "*)
		declared=$((declared + 1))
		pass "$s is $p work"
		;;
	*) fail "$s declares phase '$p', which is not one of: $PHASES" ;;
	esac
done
[ "$declared" -ge 17 ] && pass "$declared skills carry a phase" ||
	fail "only $declared skills carry a phase — the roster has more than that"

# A vocabulary nothing spans is a vocabulary nobody thought about: the kit's
# own chain runs every phase, so every phase must appear at least once.
for p in $PHASES; do
	n=0
	for d in .agents/skills/*/; do
		[ "$(phase_of "$d")" = "$p" ] && n=$((n + 1))
	done
	[ "$n" -gt 0 ] && pass "some skill is $p work ($n)" ||
		fail "no skill declares phase '$p' — either the word is dead or a skill is mislabelled"
done

# ---------------------------------------------------------------------------
banner "2. The frontmatter stays what the specification allows"
# ---------------------------------------------------------------------------
# metadata is one of the specification's own keys, so declaring a phase costs
# no vendor lock-in — but a typo in the block would silently read as no phase
# at all, so the helper that guards the key set runs over every skill here.
for d in .agents/skills/*/; do
	[ -f "$d/SKILL.md" ] || continue
	t_assert_skill_frontmatter "$d" >/dev/null 2>&1 || fail "$(basename "$d"): frontmatter is not specification-clean"
done
pass "every skill's frontmatter uses only the specification's keys"

# ---------------------------------------------------------------------------
banner "3. A phase resolves to a tier the resolver accepts"
# ---------------------------------------------------------------------------
[ -f "$DISPATCH" ] && pass "scripts/skill-dispatch.kit.sh exists" || {
	fail "scripts/skill-dispatch.kit.sh is missing — the phase is declared and nothing reads it"
	t_done "skill phases"
}
for p in $PHASES; do
	t_run_split sh "$DISPATCH" --phase-tier "$p"
	case "$p" in
	tester) want="implementer tests" ;;
	*) want="$p" ;;
	esac
	[ "$S_STATUS" = 0 ] && [ "$S_OUT" = "$want" ] &&
		pass "phase '$p' resolves to tier '$want'" ||
		fail "phase '$p' resolved '$S_OUT' (status $S_STATUS), expected '$want'"
done
t_run_split sh "$DISPATCH" --phase-tier not-a-phase
[ "$S_STATUS" = 2 ] && pass "an unknown phase is a usage error, not a guess" ||
	fail "an unknown phase exited $S_STATUS, expected 2"

# ---------------------------------------------------------------------------
banner "4. A skill name resolves to its own phase's model"
# ---------------------------------------------------------------------------
# The whole point: one command, and the session need not know which tier a
# skill is. --dry-run is the seam; nothing else here runs another vendor's CLI.
t_run_split sh "$DISPATCH" --tier-of /review-pr
[ "$S_OUT" = reviewer ] && pass "/review-pr is reviewer work, by its own declaration" ||
	fail "/review-pr resolved tier '$S_OUT'"
t_run_split sh "$DISPATCH" --tier-of /tdd
[ "$S_OUT" = "implementer tests" ] && pass "/tdd is tester work, carried as the tests domain" ||
	fail "/tdd resolved tier '$S_OUT'"
t_run_split sh "$DISPATCH" --tier-of to-tickets
[ "$S_OUT" = planner ] && pass "the leading slash is optional — 'to-tickets' resolves too" ||
	fail "'to-tickets' resolved tier '$S_OUT'"
t_run_split sh "$DISPATCH" --tier-of /no-such-skill
[ "$S_STATUS" = 2 ] && pass "a skill that does not exist is a usage error" ||
	fail "an unknown skill exited $S_STATUS, expected 2"

t_run_split sh "$DISPATCH" /review-pr --prompt 'review the branch' --dry-run
if [ "$S_STATUS" = 0 ]; then
	pass "a dry-run dispatch of /review-pr succeeds"
	printf '%s\n' "$S_OUT$S_ERR" | grep -q 'review-pr' &&
		pass "…and the prompt it would send names the skill" ||
		fail "…but the dry-run never names the skill: $S_OUT"
else
	fail "a dry-run dispatch of /review-pr exited $S_STATUS"
	printf '%s\n' "$S_ERR" | sed 's/^/        | /'
fi

t_done "skill phases"
