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
	t_exec sh "$DISPATCH" --phase-tier "$p"
	case "$p" in
	tester) want="implementer tests" ;;
	*) want="$p" ;;
	esac
	[ "$T_STATUS" = 0 ] && [ "$T_OUT" = "$want" ] &&
		pass "phase '$p' resolves to tier '$want'" ||
		fail "phase '$p' resolved '$T_OUT' (status $T_STATUS), expected '$want'"
done
t_exec sh "$DISPATCH" --phase-tier not-a-phase
[ "$T_STATUS" = 2 ] && pass "an unknown phase is a usage error, not a guess" ||
	fail "an unknown phase exited $T_STATUS, expected 2"

# ---------------------------------------------------------------------------
banner "4. A skill name resolves to its own phase's model"
# ---------------------------------------------------------------------------
# The whole point: one command, and the session need not know which tier a
# skill is. --dry-run is the seam; nothing else here runs another vendor's CLI.
t_exec sh "$DISPATCH" --tier-of /review-pr
[ "$T_OUT" = reviewer ] && pass "/review-pr is reviewer work, by its own declaration" ||
	fail "/review-pr resolved tier '$T_OUT'"
t_exec sh "$DISPATCH" --tier-of /tdd
[ "$T_OUT" = "implementer tests" ] && pass "/tdd is tester work, carried as the tests domain" ||
	fail "/tdd resolved tier '$T_OUT'"
t_exec sh "$DISPATCH" --tier-of to-tickets
[ "$T_OUT" = planner ] && pass "the leading slash is optional — 'to-tickets' resolves too" ||
	fail "'to-tickets' resolved tier '$T_OUT'"
t_exec sh "$DISPATCH" --tier-of /no-such-skill
[ "$T_STATUS" = 2 ] && pass "a skill that does not exist is a usage error" ||
	fail "an unknown skill exited $T_STATUS, expected 2"

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
cp "$ROOT/scripts/agents.kit.sh" "$ROOT/scripts/agents.lib.sh" "$ROOT/scripts/budget.lib.sh" \
	"$ROOT/scripts/agent-dispatch.sh" "$ROOT/scripts/skill-dispatch.kit.sh" "$ROOT/scripts/trace.sh" "$STUBTREE/scripts/"
cp -R "$ROOT/.agents" "$STUBTREE/.agents"
# The trace script rides along, as it does in the kit: the dispatcher checks a
# run id with its `id --check` (#746). Its twin names no directory, so nothing
# is recorded unless a leg points it at one, and puts this line back after.
TRACE_OFF="TRACE_DIR=''"
printf '%s\n' "$TRACE_OFF" >"$STUBTREE/scripts/trace.kit.config.sh"
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
stub_dispatch() { t_exec env -u TRACE_RUN -u TRACE_PARENT -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh "$@"; }

# staged_prompt — what the stub read on stdin, which is the prompt the worker
# would have received: the dispatcher's own stdout is the worker's.
staged_prompt() { printf '%s\n' "$T_OUT" | sed -n '/^STDIN-BEGIN$/,/^STDIN-END$/p'; }

# A reviewer-phase skill reaches the reviewer's model — and what arrives is
# NOT "Run /review-pr." (#266, PRD #261). That skill needs a `git fetch`, a
# forge call and a human at its last prompt, and a headless worker in another
# agent harness's default sandbox has none of the three: told to run it, every
# dispatched review came back with the same "no network" line and the session
# relayed the findings by hand. So for this one skill the dispatcher stages the
# worker contract, .agents/prompts/review-worker.md, with the caller's --prompt
# filling its %%SPEC%% slot — and that contract opens by telling the worker it
# is offline, so the budget goes on the diff rather than on discovering the
# sandbox.
stub_dispatch /review-pr --prompt 'review the branch'
if [ "$T_STATUS" = 0 ]; then
	pass "a dispatch of /review-pr runs end to end against a stub agent harness"
	printf '%s\n' "$T_OUT" | grep -q 'model-for-reviewing' &&
		pass "…on the model its reviewer phase resolves to" ||
		fail "…but not on the reviewer's model: $T_OUT"
	staged=$(staged_prompt)
	printf '%s\n' "$staged" | grep -q 'Run /review-pr\.' &&
		fail "…but the worker was told to run /review-pr, which needs a fetch, a forge and a human it does not have" ||
		pass "…and the prompt never tells the worker to run /review-pr itself"
	# The OPENING line, not a mention somewhere below: a worker that reads
	# "no network" after it has already tried three fetches got the fact late.
	first=$(printf '%s\n' "$staged" | sed '1d;$d' | grep -m1 .)
	case "$first" in
	*"no network"*) pass "…the staged prompt is the worker contract, and its first line says the worker has no network" ;;
	*) fail "…the staged prompt does not open by saying the worker is offline; it opens: '$first'" ;;
	esac
	printf '%s\n' "$staged" | grep -q 'no credentials' &&
		pass "…and that it has no credentials" ||
		fail "…and it never says the worker has no credentials"
	printf '%s\n' "$staged" | grep -q '^ *REVIEWED: ' &&
		pass "…and requires the REVIEWED line that names the commit it diffed" ||
		fail "…but the contract has no REVIEWED line — the session cannot tell a moved head from a missed commit"
	printf '%s\n' "$staged" | grep -q 'review the branch' &&
		pass "…with the caller's own prompt filling the contract's spec slot" ||
		fail "…and the caller's prompt was lost: $T_OUT"
else
	fail "a stub dispatch of /review-pr exited $T_STATUS"
	printf '%s\n' "$T_ERR" | sed 's/^/        | /'
fi

# The contract's other markers are the shared dispatcher's own --set path,
# untouched: the branch and its base arrive filled when the caller names them,
# and the "unfilled marker" note is the dispatcher's, not a silent blank.
stub_dispatch /review-pr --prompt 'x' --set BRANCH=feat/under-review --set BASE=main
staged=$(staged_prompt)
printf '%s\n' "$staged" | grep -q 'feat/under-review' &&
	pass "--set BRANCH=… reaches the contract's %%BRANCH%% through the dispatcher's own substitution" ||
	fail "the BRANCH marker was not filled from --set: $T_OUT"
case "$T_ERR" in
*"unfilled marker"*) fail "every marker was set and the dispatcher still reports one unfilled: $T_ERR" ;;
*) pass "…and with BRANCH, BASE and SPEC all set, nothing is reported unfilled" ;;
esac

# A spec too large for argv comes through --set-file, and then there is no
# --prompt to give: for /review-pr the contract IS the prompt, so the
# dispatcher does not demand one. Every other skill still does, below.
printf 'the whole ticket body\n' >"$SCRATCH/spec.md"
stub_dispatch /review-pr --set-file "SPEC=$SCRATCH/spec.md" --set BRANCH=b --set BASE=main
[ "$T_STATUS" = 0 ] && pass "/review-pr dispatches with no --prompt at all — the contract is the prompt" ||
	fail "/review-pr with --set-file SPEC and no --prompt exited $T_STATUS: $T_ERR"
staged_prompt | grep -q 'the whole ticket body' &&
	pass "…and the --set-file spec reaches the worker" ||
	fail "…but the --set-file spec did not arrive: $T_OUT"
stub_dispatch /tdd --set BRANCH=b
[ "$T_STATUS" = 2 ] && pass "any other skill with no --prompt is still refused — there is nothing to send" ||
	fail "/tdd with no prompt exited $T_STATUS, expected 2"

# The tester phase carries its domain across the hop — the one phase that is
# not a tier, so the one whose resolution a wrapper could silently drop. And
# its prompt keeps today's shape: the skill-name prefix is what every skill
# but /review-pr still receives.
stub_dispatch /tdd --prompt 'write the failing test'
printf '%s\n' "$T_OUT" | grep -q 'model-for-testing' &&
	pass "/tdd reaches the tests domain's model, not the plain implementer's" ||
	fail "/tdd reached '$T_OUT'"
staged_prompt | grep -q 'Run /tdd\. write the failing test' &&
	pass "…and its prompt still opens with 'Run /tdd.' — the contract swap is /review-pr's alone" ||
	fail "…but /tdd's prompt lost its skill-name prefix: $T_OUT"

# A --prompt-file is the caller's own document: passed through unrewritten,
# because rewriting a file someone wrote is a surprise. This pair is a
# REGRESSION guard rather than a pinned rule: the wrapper cannot rewrite a
# file today even if its text branch ran, because the prefix is only ever
# applied to a --prompt value it has in hand. The assertion is here for the
# day someone teaches it to read the file.
echo 'the file the caller wrote' >"$SCRATCH/caller-prompt.md"
stub_dispatch /review-pr --prompt-file "$SCRATCH/caller-prompt.md"
printf '%s\n' "$T_OUT" | grep -q 'the file the caller wrote' &&
	pass "a --prompt-file reaches the other session verbatim" ||
	fail "the prompt file did not arrive: $T_OUT"
printf '%s\n' "$T_OUT" | grep -q 'Run /review-pr\.' &&
	fail "the prompt file was rewritten — a file the caller wrote is not ours to edit" ||
	pass "…and was not rewritten on the way"
staged_prompt | grep -q 'no network' &&
	fail "the caller's own prompt file was replaced by the worker contract — a file the caller wrote is what they meant to send" ||
	pass "…nor replaced by the worker contract: the swap applies to --prompt, never to a caller's file"

# An argument whose value carries a space survives the exec as ONE argument;
# split, it would arrive as a stray positional the dispatcher reads as a task
# domain, and the work would silently resolve somewhere else.
stub_dispatch /review-pr --prompt 'x' --set 'TITLE=two words'
printf '%s\n' "$T_OUT$T_ERR" | grep -q 'domain' &&
	fail "a --set value with a space was split into a task domain: $T_ERR" ||
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
printf '%s\n' "$T_OUT" | grep -q 'model-for-mechanics' &&
	pass "an explicit --tier beats the skill's own phase" ||
	fail "--tier mechanical on /review-pr reached '$T_OUT'"
stub_dispatch /review-pr --tier implementer --domain tests --prompt 'x'
printf '%s\n' "$T_OUT" | grep -q 'model-for-testing' &&
	pass "--tier with --domain resolves the pair, not the tier alone" ||
	fail "--tier implementer --domain tests reached '$T_OUT'"
stub_dispatch /review-pr --prompt 'x'
printf '%s\n' "$T_OUT" | grep -q 'model-for-reviewing' &&
	pass "with no override the phase still answers — the default is unchanged" ||
	fail "an un-overridden dispatch reached '$T_OUT'"
# The override is held to the same closed vocabulary as every other tier.
stub_dispatch /review-pr --tier janitor --prompt 'x'
[ "$T_STATUS" = 2 ] && pass "an override outside the four tiers is exit 2, like every other unknown tier" ||
	fail "--tier janitor exited $T_STATUS"
# A trailing `--tier` has nothing after it to take, which is the shape the
# guard exists for. `--tier --prompt x` is NOT that shape — it swallows the
# next word and dies on the unknown tier `--prompt`, loudly but for another
# reason, so asserting only the status let the guard be deleted.
stub_dispatch /review-pr --prompt 'x' --tier
[ "$T_STATUS" = 2 ] && pass "a trailing --tier with nothing after it is a usage error" ||
	fail "a trailing --tier exited $T_STATUS"
case "$T_ERR" in
*"--tier needs one of"*) pass "…and says what it needed" ;;
*) fail "…without saying what it needed: '$T_ERR'" ;;
esac
stub_dispatch /review-pr --tier --prompt 'x'
[ "$T_STATUS" = 2 ] && pass "--tier followed by another flag dies on the tier it read, not silently" ||
	fail "--tier --prompt exited $T_STATUS"
case "$T_ERR" in
*"unknown tier '--prompt'"*) pass "…naming the word it took, so the cause is legible" ;;
*) fail "…without naming what it read: '$T_ERR'" ;;
esac
# A domain is the second half of a ticket's stamp, never a sizing of its own.
stub_dispatch /review-pr --domain tests --prompt 'x'
[ "$T_STATUS" = 2 ] && pass "--domain without --tier is refused" || fail "--domain alone exited $T_STATUS"
case "$T_ERR" in
*"not a sizing of its own"*) pass "…and says why" ;;
*) fail "…without saying why: '$T_ERR'" ;;
esac
# A dry run says WHICH of the two answered, so an operator reading it can tell
# a ticket's decision from a skill's default.
stub_dispatch /review-pr --tier mechanical --prompt 'x' --dry-run
printf '%s\n' "$T_ERR$T_OUT" | grep -qi "ticket" &&
	pass "a dry run names the ticket as the source when it overrode the phase" ||
	fail "the dry run does not say where the tier came from: $T_ERR"
stub_dispatch /review-pr --prompt 'x' --dry-run
printf '%s\n' "$T_ERR$T_OUT" | grep -qi "phase" &&
	pass "…and names the phase when the phase answered" ||
	fail "the dry run does not name the phase as the source: $T_ERR"

# ---------------------------------------------------------------------------
banner "4c. The kit's own dispatches are traced (owed since #249's review)"
# ---------------------------------------------------------------------------
# The dispatcher records every spawn through scripts/trace.sh, which reads the
# SHIPPED policy file unless TRACE_CONFIG names another — and the shipped one
# is empty by principle, so a kit dispatch that did not name the kit's twin
# wrote nothing at all. The wrapper names it, $ROOT-anchored like
# AGENTS_CONFIG. The stub tree carries a twin pointing at scratch, and no
# shipped policy file, so only the wrapper's choice can make the line appear.
printf "TRACE_DIR='%s'\n" "$SCRATCH/kit-trace" >"$STUBTREE/scripts/trace.kit.config.sh"
stub_dispatch /review-pr --prompt 'traced review'
if grep -rqs '"kind":"spawn"' "$SCRATCH/kit-trace"; then
	pass "a kit dispatch writes its spawn record to the kit's own trace"
else
	fail "a kit dispatch wrote no spawn record — the wrapper does not name scripts/trace.kit.config.sh (exit $T_STATUS)"
fi
printf '%s\n' "$TRACE_OFF" >"$STUBTREE/scripts/trace.kit.config.sh"

# ---------------------------------------------------------------------------
banner "4d. A dispatched worker's prompt opens with the run and what the spawn served (#587)"
# ---------------------------------------------------------------------------
# spend/R1: every spawn the chain makes says what it served, so a wave's stops
# come out attributed without anyone tagging them by hand. The channel is the
# spawn prompt's first two lines — `Trace-Run: <run> [<parent>]`, then
# `Trace-Spawn: tier=<tier> domain=<domain|none> skill=<skill> ticket=<#N|none>`
# — exactly as the adapter's subagent-stop hook reads them (ADR-0008 clause 5,
# #583 amendment). The dispatcher writes both, from the run it is dispatched
# under and the stamp it resolved; --ticket names the ticket. With no run there
# is nothing for the second line to sit under, and neither is written.
RUN587=20261007T104205Z-4242-0a1b2c3d
PARENT587=20261007T090000Z-17-deadbeef
spawn_dispatch() { t_exec env -u TRACE_RUN -u TRACE_PARENT -C "$STUBTREE" AGENT_HARNESS_SELF=stub "$@"; }
# dry_prompt — the prompt a dry run shows, between its two rules.
dry_prompt() { printf '%s\n' "$T_OUT" | sed -n '/^--- prompt (/,/^--- end prompt ---$/p' | sed '1d;$d'; }

spawn_dispatch TRACE_RUN=$RUN587 sh scripts/skill-dispatch.kit.sh /tdd --tier implementer --ticket 587 --prompt 'build it' --dry-run
p=$(dry_prompt)
[ "$T_STATUS" = 0 ] || fail "a dry run with --ticket exited $T_STATUS: $T_ERR"
[ "$(printf '%s\n' "$p" | sed -n 1p)" = "Trace-Run: $RUN587" ] &&
	pass "a dry run's prompt opens with the run it was dispatched under" ||
	fail "the prompt's first line is not 'Trace-Run: $RUN587': $(printf '%s\n' "$p" | sed -n 1p)"
[ "$(printf '%s\n' "$p" | sed -n 2p)" = "Trace-Spawn: tier=implementer domain=none skill=tdd ticket=#587" ] &&
	pass "…then the Trace-Spawn line: the stamp's tier, no domain, the skill, the ticket" ||
	fail "the prompt's second line is not the Trace-Spawn line: $(printf '%s\n' "$p" | sed -n 2p)"
[ "$(printf '%s\n' "$p" | sed -n 3p)" = "Run /tdd. build it" ] &&
	pass "…and the instruction follows them" ||
	fail "the instruction does not follow the two lines: $(printf '%s\n' "$p" | sed -n 3p)"

spawn_dispatch TRACE_RUN=$RUN587 TRACE_PARENT=$PARENT587 sh scripts/skill-dispatch.kit.sh /tdd --tier implementer --domain tests --prompt 'build it' --dry-run
p=$(dry_prompt)
[ "$(printf '%s\n' "$p" | sed -n 1p)" = "Trace-Run: $RUN587 $PARENT587" ] &&
	pass "a run that nests in another carries its parent after one space" ||
	fail "the parent is not on the first line: $(printf '%s\n' "$p" | sed -n 1p)"
[ "$(printf '%s\n' "$p" | sed -n 2p)" = "Trace-Spawn: tier=implementer domain=tests skill=tdd ticket=none" ] &&
	pass "with no --ticket the line says ticket=none, and the stamp's domain rides along" ||
	fail "the no-ticket Trace-Spawn line is wrong: $(printf '%s\n' "$p" | sed -n 2p)"

spawn_dispatch TRACE_RUN=$RUN587 sh scripts/skill-dispatch.kit.sh /review-pr --ticket '#587' --prompt 'the spec' --set BRANCH=b --set BASE=main --dry-run
p=$(dry_prompt)
[ "$(printf '%s\n' "$p" | sed -n 1p)" = "Trace-Run: $RUN587" ] &&
	[ "$(printf '%s\n' "$p" | sed -n 2p)" = "Trace-Spawn: tier=reviewer domain=none skill=review-pr ticket=#587" ] &&
	pass "the review worker's contract opens with both lines too, the phase's tier on the second" ||
	fail "the review contract does not open with both lines: $(printf '%s\n' "$p" | sed -n 1,2p)"
case "$(printf '%s\n' "$p" | sed -n 3,4p)" in
*"no network"*) pass "…and the contract's offline line follows them at once" ;;
*) fail "the contract's opening line does not follow the two lines: $(printf '%s\n' "$p" | sed -n 3,4p)" ;;
esac
case "$p" in *'<!--'*) fail "…but the contract's editor header was sent with them" ;;
*) pass "…and the contract's editor header is still stripped" ;; esac
# The spawn guard admits what the dispatcher hands out (#834, review of #844):
# the review worker's two lines, spawned on the agent type the dry run names,
# pass the kit's own wired guard — and the same lines on a wider type are
# refused, so the pass is the reviewer type's, not a guard that read nothing.
_sg834_type=$(printf '%s\n' "$T_ERR" | sed -n "s/^skill-dispatch: agent type '\([a-z-]*\)'.*/\1/p")
_sg834_lines=$(printf '%s\n' "$p" | sed -n 1,2p | awk '{ printf "%s\\n", $0 }')
for _sg834 in "$_sg834_type:0" general-purpose:2; do
	printf '{"session_id":"s-834","transcript_path":"/nowhere.jsonl","cwd":"/tmp/x","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"description":"d","prompt":"%sReview it.","subagent_type":"%s"},"tool_use_id":"u-834"}' \
		"$_sg834_lines" "${_sg834%:*}" >"$SCRATCH/sg-834.json"
	rm -rf "$SCRATCH/sg-834-trace"
	t_exec env TRACE_DIR="$SCRATCH/sg-834-trace" sh "$ROOT/adapters/claude-code/hooks/spawn-guard.sh" <"$SCRATCH/sg-834.json"
	[ -n "$_sg834_type" ] && [ "$T_STATUS" = "${_sg834#*:}" ] &&
		pass "the review worker's lines on the '${_sg834%:*}' agent type: the wired spawn guard exits ${_sg834#*:}" ||
		fail "the review worker's lines on the '${_sg834%:*}' agent type (dry run named '$_sg834_type'): the spawn guard exited $T_STATUS: $T_ERR"
done

spawn_dispatch TRACE_RUN= sh scripts/skill-dispatch.kit.sh /tdd --ticket 587 --prompt 'build it' --dry-run
p=$(dry_prompt)
[ "$(printf '%s\n' "$p" | sed -n 1p)" = "Run /tdd. build it" ] &&
	pass "with no run, neither line is written — a Trace-Spawn line under no run is no line" ||
	fail "a dispatch under no run still opened with: $(printf '%s\n' "$p" | sed -n 1p)"

for bad in 0587 abc '#' 1234567 '587 x'; do
	spawn_dispatch TRACE_RUN=$RUN587 sh scripts/skill-dispatch.kit.sh /tdd --ticket "$bad" --prompt 'x' --dry-run
	[ "$T_STATUS" = 2 ] && pass "--ticket '$bad' is refused (exit 2)" ||
		fail "--ticket '$bad' exited $T_STATUS"
done

# runtime/R2.
# INSIDE A DISPATCHED WORKER (#743). scripts/agent-dispatch.sh opens the
# worker's run with the trace's `begin --detached` (#746) and hands it down
# as TRACE_RUN, the dispatching run as TRACE_PARENT; a skill dispatch the
# worker runs reads both back through the trace script and checks each
# against the trace's id shape. A worker run in any other shape is dropped
# there, and the two lines with it — so this leg runs the real crossing, a
# stub worker that dispatches a skill, and reads the prompt that worker's
# skill dispatch staged.
NEST743="$SCRATCH/nesting-worker"
cat >"$NEST743" <<NEST_EOF
#!/bin/sh
cat >/dev/null
echo "worker TRACE_RUN=\${TRACE_RUN-unset}"
cd "$STUBTREE" && AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh /tdd --tier implementer --ticket 743 --prompt 'nested' --dry-run
NEST_EOF
chmod +x "$NEST743"
cat >"$SCRATCH/nesting.config.sh" <<NEST_CFG
AGENT_HARNESSES='nest'
AGENT_HARNESS_NEST_CMD='$NEST743 {model_flag} < {prompt_file}'
AGENT_HARNESS_NEST_MODEL_FLAG=''
AGENT_TIER_IMPLEMENTER='nest:'
NEST_CFG
printf "TRACE_DIR='%s'\n" "$SCRATCH/nest-trace" >"$STUBTREE/scripts/trace.kit.config.sh"
spawn_dispatch AGENTS_CONFIG="$SCRATCH/nesting.config.sh" TRACE_DIR="$SCRATCH/nest-trace" \
	TRACE_RUN=$PARENT587 sh scripts/agent-dispatch.sh implementer --prompt 'x'
printf '%s\n' "$TRACE_OFF" >"$STUBTREE/scripts/trace.kit.config.sh"
[ "$T_STATUS" = 0 ] || fail "the dispatch whose worker runs a skill dispatch exited $T_STATUS: $T_ERR"
worker743=$(printf '%s\n' "$T_OUT" | sed -n 's/^worker TRACE_RUN=//p')
p=$(dry_prompt)
[ "$(printf '%s\n' "$p" | sed -n 1p)" = "Trace-Run: $worker743 $PARENT587" ] &&
	pass "a skill dispatch inside a dispatched worker opens with the worker's run, the dispatching run its parent" ||
	fail "the nested prompt's first line is not 'Trace-Run: $worker743 $PARENT587': $(printf '%s\n' "$p" | sed -n 1p)"
[ "$(printf '%s\n' "$p" | sed -n 2p)" = "Trace-Spawn: tier=implementer domain=none skill=tdd ticket=#743" ] &&
	pass "…then the Trace-Spawn line" ||
	fail "the nested prompt's second line is not the Trace-Spawn line: $(printf '%s\n' "$p" | sed -n 2p)"

# ---------------------------------------------------------------------------
banner "4e. A dry run names the spawn's agent type and model (#588)"
# ---------------------------------------------------------------------------
# spend/R6–R7: under the Claude Code adapter a spawn takes its tier's agent
# type (adapters/claude-code/agents/<tier>.md) and the model the resolver
# printed for that tier and domain; an unmapped tier keeps its agent type and
# names no model, so the spawn inherits the session's. The dry run says both,
# so a session spawning in its own harness reads them off one line.
cat >"$STUBTREE/scripts/agents.kit.local.config.sh" <<'LOCAL_CFG'
AGENT_TIER_REVIEWER='model-for-reviewing'
AGENT_TIER_IMPLEMENTER_TESTS='model-for-testing'
LOCAL_CFG
local_dispatch() { t_exec env -u TRACE_RUN -u TRACE_PARENT -C "$STUBTREE" AGENT_HARNESS_SELF=local sh scripts/skill-dispatch.kit.sh "$@"; }
local_dispatch /review-pr --prompt 'x' --dry-run
case "$T_ERR" in
*"agent type 'reviewer', model 'model-for-reviewing'"*) pass "a mapped tier's dry run names its agent type and the resolver's model" ;;
*) fail "the dry run does not name agent type and model for a mapped tier: $T_ERR" ;;
esac
local_dispatch /tdd --tier implementer --domain tests --prompt 'x' --dry-run
case "$T_ERR" in
*"agent type 'implementer', model 'model-for-testing'"*) pass "…the model is the tier-and-domain answer, the type the tier's" ;;
*) fail "the dry run does not resolve the domain for the model: $T_ERR" ;;
esac
local_dispatch /tdd --tier planner --prompt 'x' --dry-run
case "$T_ERR" in
*"agent type 'planner', no model"*) pass "an unmapped tier's dry run names its agent type and no model — the spawn inherits" ;;
*) fail "the dry run does not name the agent type with no model for an unmapped tier: $T_ERR" ;;
esac
# A resolver that REFUSES is not an unmapped tier: a value it cannot accept
# must not read as "no model — the spawn inherits" (PR #618 review, M-2):
# here the policy file the dispatch names does not exist.
t_exec env -u TRACE_RUN -u TRACE_PARENT -C "$STUBTREE" AGENT_HARNESS_SELF=absent sh scripts/skill-dispatch.kit.sh /tdd --tier planner --prompt 'x' --dry-run
case "$T_STATUS:$T_ERR" in
0:* | *"no model"*) fail "a refused resolution read as an unmapped tier (exit $T_STATUS): $T_ERR" ;;
*) pass "a resolver that refuses fails the dry run instead of printing 'no model'" ;;
esac

# ---------------------------------------------------------------------------
banner "4f. An in-session reviewer is handed back with its staged contract (#880)"
# ---------------------------------------------------------------------------
# The manual's review one-liner redirects the dispatcher to a file and runs the
# broker only on exit 0. A reviewer tier that names no agent harness is exit 3,
# so the broker half never ran and every review was improvised by hand. Now the
# dispatcher hands the review back as the cascade hands back a rung: exit 3,
# the model on stdout, and the offline contract staged — Trace-Run and
# Trace-Spawn first — under the checkout's git dir, never its working tree.
# The reviewer agent type reads files and runs nothing, so the dispatcher pins
# the branch's commit and stages its diff beside the prompt.
HBTREE="$SCRATCH/handback-tree"
cp -R "$STUBTREE" "$HBTREE"
git -C "$HBTREE" init -q -b main
git -C "$HBTREE" -c user.name=t -c user.email=t@t add -A
git -C "$HBTREE" -c user.name=t -c user.email=t@t commit -qm base
git -C "$HBTREE" checkout -qb feat/under-review
printf 'a reviewed line\n' >"$HBTREE/reviewed.txt"
git -C "$HBTREE" -c user.name=t -c user.email=t@t add reviewed.txt
git -C "$HBTREE" -c user.name=t -c user.email=t@t commit -qm 'feat: under review'
HB_SHA=$(git -C "$HBTREE" rev-parse HEAD)
HB_STATE="$(git -C "$HBTREE" rev-parse --absolute-git-dir)/skill-review"
printf 'the ticket body as spec\n' >"$SCRATCH/hb-spec.md"
hb_dispatch() { t_exec env -u TRACE_RUN -u TRACE_PARENT -C "$HBTREE" AGENT_HARNESS_SELF="$1" TRACE_RUN=$RUN587 sh scripts/skill-dispatch.kit.sh /review-pr --ticket 880 --set BRANCH=feat/under-review --set BASE=main --set-file "SPEC=$SCRATCH/hb-spec.md" ${2:+"$2"}; }

hb_dispatch local
[ "$T_STATUS" = 3 ] && [ "$T_OUT" = model-for-reviewing ] &&
	pass "an in-session reviewer tier is handed back: exit 3, the model alone on stdout" ||
	fail "the in-session review exited $T_STATUS with stdout '$T_OUT': $T_ERR"
if [ -f "$HB_STATE/prompt" ]; then
	pass "…and the contract is staged at <git dir>/skill-review/prompt, outside the working tree"
	hb_p=$(cat "$HB_STATE/prompt")
	[ "$(printf '%s\n' "$hb_p" | sed -n 1p)" = "Trace-Run: $RUN587" ] &&
		[ "$(printf '%s\n' "$hb_p" | sed -n 2p)" = "Trace-Spawn: tier=reviewer domain=none skill=review-pr ticket=#880" ] &&
		pass "…opening with the Trace-Run and Trace-Spawn lines" ||
		fail "the staged prompt does not open with both lines: $(printf '%s\n' "$hb_p" | sed -n 1,2p)"
	case "$hb_p" in
	*'<!--'* | *'%%'[A-Z]*'%%'*) fail "…but the editor header or an unfilled marker reached it" ;;
	*) pass "…its editor header stripped and every marker filled" ;;
	esac
	case "$hb_p" in
	*'no network'*'feat/under-review'*'the ticket body as spec'*) pass "…the offline contract, the branch and the spec in it" ;;
	*) fail "the staged prompt lacks the contract, the branch or the spec" ;;
	esac
	case "$hb_p" in
	*"$HB_SHA"*"$HB_STATE/diff"*) pass "…naming the pinned commit and the staged diff it reads in place of git" ;;
	*) fail "the staged prompt names neither the pinned commit $HB_SHA nor $HB_STATE/diff" ;;
	esac
	[ "$(cat "$HB_STATE/diff" 2>/dev/null)" = "$(git -C "$HBTREE" diff "main...$HB_SHA")" ] &&
		[ -n "$(cat "$HB_STATE/diff")" ] &&
		pass "…and the staged diff is the branch's diff against its base at that commit" ||
		fail "the staged diff is missing or is not 'git diff main...$HB_SHA'"
else
	fail "no contract staged at $HB_STATE/prompt for the session to spawn"
fi
case "$T_ERR" in
*"$HB_STATE/prompt"*broker*) pass "…and stderr names the prompt and sends the saved report to the broker" ;;
*) fail "stderr does not name the staged prompt and the broker: $T_ERR" ;;
esac
[ -z "$(git -C "$HBTREE" status --porcelain)" ] &&
	pass "…the working tree left clean" ||
	fail "the hand-back dirtied the working tree: $(git -C "$HBTREE" status --porcelain)"

rm -rf "$HB_STATE"
hb_dispatch local --dry-run
[ ! -e "$HB_STATE" ] && pass "a dry run stages nothing" ||
	fail "a dry run staged a hand-back under $HB_STATE"

hb_dispatch stub
[ "$T_STATUS" = 0 ] && printf '%s\n' "$T_OUT" | grep -q 'model-for-reviewing' &&
	printf '%s\n' "$T_OUT" | grep -q 'no network' &&
	pass "a harness-backed reviewer is dispatched as before, the contract on the worker's stdin" ||
	fail "the harness-backed review exited $T_STATUS: $T_ERR"
[ ! -e "$HB_STATE" ] && pass "…and nothing is staged for a hand-back" ||
	fail "a dispatched review staged a hand-back under $HB_STATE"

t_exec env -u TRACE_RUN -u TRACE_PARENT -C "$HBTREE" AGENT_HARNESS_SELF=local sh scripts/skill-dispatch.kit.sh /review-pr --set BRANCH=no-such-branch --set BASE=main --prompt 'x'
[ "$T_STATUS" = 2 ] && [ ! -e "$HB_STATE" ] &&
	pass "a branch that names no commit is refused (exit 2), nothing staged" ||
	fail "an unresolvable branch exited $T_STATUS: $T_ERR"

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
			# Whether it is declared is the resolver's answer, asked of its
			# agents_split_harness under this policy — the one membership
			# test (#597), never a copy kept here to drift from it.
			_split=$(
				. "$ROOT/scripts/agents.lib.sh"
				. "$cfg" >/dev/null 2>&1
				AGENTS_TIER_QUIET=1
				agents_split_harness "$_harness:$_model"
				printf '%s' "$_ah_harness"
			)
			_cmdvar="AGENT_HARNESS_$(printf '%s' "$_harness" | tr 'a-z-' 'A-Z_')_CMD"
			_cmd=$(AGENTS_CONFIG="$cfg" sh -c '. "$0" 2>/dev/null; eval printf "%s" "\$$1"' "$cfg" "$_cmdvar")
			case "$_split" in
			"$_harness") : ;;
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
