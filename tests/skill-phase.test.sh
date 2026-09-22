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

# The dispatch itself needs the OTHER vendor's CLI on PATH, and the dispatcher
# checks that before it prints anything — even for a dry run, deliberately, so
# an uninstalled agent harness reports itself rather than surfacing as a shell
# "not found" mixed into a worker's output. CI has neither vendor's CLI, and a
# suite that made the kit's own tests depend on a third party being installed
# would be asserting the host, not the kit — and a check that is skipped where
# it is meant to run is a claim (hard rule 9). So the dispatch runs against a
# STUB agent harness, the way tests/agent-dispatch.test.sh already does: the
# whole path executes with nothing third-party installed, and the stub echoes
# what it was handed so the prompt can be asserted rather than inferred.
#
# The seam is the wrapper's own policy selection: $AGENT_HARNESS_SELF picks
# `scripts/agents.kit.<self>.config.sh`, resolved relative to the directory it
# runs in, so a scratch tree carrying that name IS the override. Nothing here
# touches the repo's policy files.
STUBTREE="$SCRATCH/stubtree"
mkdir -p "$STUBTREE/scripts"
cp "$ROOT/scripts/agents.kit.sh" "$ROOT/scripts/agents.lib.sh" \
	"$ROOT/scripts/agent-dispatch.sh" "$ROOT/scripts/skill-dispatch.kit.sh" "$STUBTREE/scripts/"
cp -R "$ROOT/.agents" "$STUBTREE/.agents"
STUB="$SCRATCH/stub-agent-harness"
cat >"$STUB" <<'STUB_EOF'
#!/bin/sh
echo "ARGV: $*"
echo "STDIN-BEGIN"
cat
echo "STDIN-END"
STUB_EOF
chmod +x "$STUB"
cat >"$STUBTREE/scripts/agents.kit.stub.config.sh" <<STUB_CFG
AGENT_HARNESSES='stub'
AGENT_HARNESS_STUB_CMD='$STUB --flag {model_flag} < {prompt_file}'
AGENT_HARNESS_STUB_MODEL_FLAG='--model {model}'
AGENT_TIER_PLANNER='stub:model-for-planning'
AGENT_TIER_IMPLEMENTER='stub:model-for-building'
AGENT_TIER_IMPLEMENTER_TESTS='stub:model-for-testing'
AGENT_TIER_MECHANICAL='stub:model-for-mechanics'
AGENT_TIER_REVIEWER='stub:model-for-reviewing'
STUB_CFG
stub_dispatch() { t_run_split env -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh "$@"; }

# A reviewer-phase skill reaches the reviewer's model, and the prompt that
# arrives says which skill to run — the one thing this wrapper adds over the
# dispatcher it delegates to.
stub_dispatch /review-pr --prompt 'review the branch'
if [ "$S_STATUS" = 0 ]; then
	pass "a dispatch of /review-pr runs end to end against a stub agent harness"
	printf '%s\n' "$S_OUT" | grep -q 'model-for-reviewing' &&
		pass "…on the model its reviewer phase resolves to" ||
		fail "…but not on the reviewer's model: $S_OUT"
	printf '%s\n' "$S_OUT" | grep -q 'Run /review-pr\.' &&
		pass "…and the prompt it hands over says which skill to run" ||
		fail "…but the prompt never names the skill: $S_OUT"
	printf '%s\n' "$S_OUT" | grep -q 'review the branch' &&
		pass "…with the caller's own prompt still in it" ||
		fail "…and the caller's prompt was lost: $S_OUT"
else
	fail "a stub dispatch of /review-pr exited $S_STATUS"
	printf '%s\n' "$S_ERR" | sed 's/^/        | /'
fi

# The tester phase carries its domain across the hop — the one phase that is
# not a tier, so the one whose resolution a wrapper could silently drop.
stub_dispatch /tdd --prompt 'write the failing test'
printf '%s\n' "$S_OUT" | grep -q 'model-for-testing' &&
	pass "/tdd reaches the tests domain's model, not the plain implementer's" ||
	fail "/tdd reached '$S_OUT'"

# A --prompt-file is the caller's own document: passed through unrewritten,
# because rewriting a file someone wrote is a surprise. This pair is a
# REGRESSION guard rather than a pinned rule: the wrapper cannot rewrite a
# file today even if its text branch ran, because the prefix is only ever
# applied to a --prompt value it has in hand. The assertion is here for the
# day someone teaches it to read the file.
echo 'the file the caller wrote' >"$SCRATCH/caller-prompt.md"
stub_dispatch /review-pr --prompt-file "$SCRATCH/caller-prompt.md"
printf '%s\n' "$S_OUT" | grep -q 'the file the caller wrote' &&
	pass "a --prompt-file reaches the other session verbatim" ||
	fail "the prompt file did not arrive: $S_OUT"
printf '%s\n' "$S_OUT" | grep -q 'Run /review-pr\.' &&
	fail "the prompt file was rewritten — a file the caller wrote is not ours to edit" ||
	pass "…and was not rewritten on the way"

# An argument whose value carries a space survives the exec as ONE argument;
# split, it would arrive as a stray positional the dispatcher reads as a task
# domain, and the work would silently resolve somewhere else.
stub_dispatch /review-pr --prompt 'x' --set 'TITLE=two words'
printf '%s\n' "$S_OUT$S_ERR" | grep -q 'domain' &&
	fail "a --set value with a space was split into a task domain: $S_ERR" ||
	pass "a --set value with a space survives the hop as one argument"

# ---------------------------------------------------------------------------
banner "4b. A ticket's stamp beats the skill's phase (#229)"
# ---------------------------------------------------------------------------
# Two sizings now exist and they answer different questions. A skill's phase
# says what KIND of work that skill is, and it is all you have when there is
# no ticket — running /review-pr by hand. A ticket's `Tier:` is decided when
# the ticket is written, by the only actor with a view of the whole wave, and
# the root manual is explicit that the call is not the spawning agent's. So
# the phase is the DEFAULT and the stamp OVERRIDES it; without that rule the
# dispatcher silently replaces a decomposer's decision with a skill author's.
stub_dispatch /review-pr --tier mechanical --prompt 'x'
printf '%s\n' "$S_OUT" | grep -q 'model-for-mechanics' &&
	pass "an explicit --tier beats the skill's own phase" ||
	fail "--tier mechanical on /review-pr reached '$S_OUT'"
stub_dispatch /review-pr --tier implementer --domain tests --prompt 'x'
printf '%s\n' "$S_OUT" | grep -q 'model-for-testing' &&
	pass "--tier with --domain resolves the pair, not the tier alone" ||
	fail "--tier implementer --domain tests reached '$S_OUT'"
stub_dispatch /review-pr --prompt 'x'
printf '%s\n' "$S_OUT" | grep -q 'model-for-reviewing' &&
	pass "with no override the phase still answers — the default is unchanged" ||
	fail "an un-overridden dispatch reached '$S_OUT'"
# The override is held to the same closed vocabulary as every other tier.
stub_dispatch /review-pr --tier janitor --prompt 'x'
[ "$S_STATUS" = 2 ] && pass "an override outside the four tiers is exit 2, like every other unknown tier" ||
	fail "--tier janitor exited $S_STATUS"
stub_dispatch /review-pr --tier --prompt 'x'
[ "$S_STATUS" = 2 ] && pass "--tier with no value is a usage error" || fail "--tier with no value exited $S_STATUS"
# A dry run says WHICH of the two answered, so an operator reading it can tell
# a ticket's decision from a skill's default.
stub_dispatch /review-pr --tier mechanical --prompt 'x' --dry-run
printf '%s\n' "$S_ERR$S_OUT" | grep -qi "ticket" &&
	pass "a dry run names the ticket as the source when it overrode the phase" ||
	fail "the dry run does not say where the tier came from: $S_ERR"
stub_dispatch /review-pr --prompt 'x' --dry-run
printf '%s\n' "$S_ERR$S_OUT" | grep -qi "phase" &&
	pass "…and names the phase when the phase answered" ||
	fail "the dry run does not name the phase as the source: $S_ERR"

# ---------------------------------------------------------------------------
banner "5. EVERY skill, in BOTH policies, resolves to a model something can run"
# ---------------------------------------------------------------------------
# The declaration is only worth having if it ends in an executable spawn. For
# every skill on the roster, under each agent harness's policy: the phase maps
# to a tier, the tier resolves to a non-empty model, and that model is
# reachable by exactly one of the two paths — an in-session spawn word when it
# is local, a dispatch to a declared agent harness when it crosses. A tier
# that is neither is the silent inherit the whole mechanism exists to stop.
for cfg in scripts/agents.kit.config.sh scripts/agents.kit.codex.config.sh; do
	_clabel=$(basename "$cfg")
	_unreachable=0
	_checked=0
	for d in .agents/skills/*/; do
		[ -f "$d/SKILL.md" ] || continue
		_skill=$(basename "$d")
		_tier_args=$(sh "$DISPATCH" --tier-of "$_skill") || {
			fail "$_clabel: /$_skill has no tier"
			continue
		}
		_checked=$((_checked + 1))
		# shellcheck disable=SC2086  # one or two words, by construction
		_model=$(AGENTS_CONFIG="$cfg" sh "$ROOT/scripts/agents.lib.sh" $_tier_args 2>/dev/null)
		# shellcheck disable=SC2086
		_harness=$(AGENTS_CONFIG="$cfg" sh "$ROOT/scripts/agents.lib.sh" --harness $_tier_args 2>/dev/null)
		if [ -z "$_model" ]; then
			fail "$_clabel: /$_skill ($_tier_args) resolves to no model — it would inherit the session silently"
			_unreachable=$((_unreachable + 1))
			continue
		fi
		if [ -n "$_harness" ]; then
			# A crossing must name an agent harness the policy declares AND
			# gave a command template, or the dispatch dies at run time.
			_decl=$(AGENTS_CONFIG="$cfg" sh -c '. "$0" 2>/dev/null; printf "%s" "${AGENT_HARNESSES:-}"' "$cfg")
			_cmdvar="AGENT_HARNESS_$(printf '%s' "$_harness" | tr 'a-z-' 'A-Z_')_CMD"
			_cmd=$(AGENTS_CONFIG="$cfg" sh -c '. "$0" 2>/dev/null; eval printf "%s" "\$$1"' "$cfg" "$_cmdvar")
			case " $_decl " in
			*" $_harness "*) : ;;
			*)
				fail "$_clabel: /$_skill crosses to '$_harness', which AGENT_HARNESSES does not declare"
				_unreachable=$((_unreachable + 1))
				continue
				;;
			esac
			[ -n "$_cmd" ] || {
				fail "$_clabel: /$_skill crosses to '$_harness', which has no ${_cmdvar} — the dispatch would die at run time"
				_unreachable=$((_unreachable + 1))
				continue
			}
		elif [ "$cfg" = scripts/agents.kit.config.sh ]; then
			# Local to Claude Code: the in-session spawn parameter takes the
			# family word, so a pinned id must fold to one it accepts.
			# shellcheck disable=SC2086
			_alias=$(sh "$ROOT/scripts/agents.kit.sh" --alias $_tier_args)
			case "$_alias" in
			fable | opus | sonnet | haiku) : ;;
			*)
				fail "$_clabel: /$_skill resolves to '$_model', which folds to '$_alias' — not a word the spawn parameter accepts"
				_unreachable=$((_unreachable + 1))
				;;
			esac
		fi
	done
	[ "$_checked" -ge 17 ] && [ "$_unreachable" = 0 ] &&
		pass "$_clabel: all $_checked skills resolve to a model that is actually runnable" ||
		fail "$_clabel: $_unreachable of $_checked skills resolve to nothing runnable"
done

# And the phases are not all the same answer: a policy where every phase
# resolved to one model would pass everything above and mean nothing.
_distinct=$(for ph in planner implementer tester mechanical reviewer; do
	sh "$DISPATCH" --phase-tier "$ph" | while read -r a b; do
		AGENTS_CONFIG=scripts/agents.kit.config.sh sh "$ROOT/scripts/agents.lib.sh" $a $b 2>/dev/null
	done
done | sort -u | grep -c .)
[ "$_distinct" -ge 3 ] &&
	pass "the five phases resolve to $_distinct distinct models — the phase changes the answer" ||
	fail "the five phases resolve to only $_distinct model(s) — the phase is not changing anything"

t_done "skill phases"
