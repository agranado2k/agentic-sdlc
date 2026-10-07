#!/bin/sh
# tests/skill-cascade.test.sh — a mechanical ticket runs cheap-first, and
# escalates only on a red oracle or a red pairing guard (#586, PRD #580).
#
# The mechanical tier once ran on the cheapest model outright and failed three
# tickets of three in a day (retro 20261001T150216Z): each worker said it was
# done, and nothing but a rescue session checked. The cascade keeps the cheap
# model and moves the judgement off it — the skill dispatcher runs the ticket
# on the policy's cascade model first, then runs the ticket's own oracle and
# the pairing guard, and only their exit codes decide whether the ticket goes
# again on the tier's mapped model, from a worktree reset to its base.
#
# Everything here runs against a STUB agent harness (the seam
# tests/skill-phase.test.sh already uses) and a scratch repository with one
# linked worktree, so the reset is observed on a real git tree and nothing
# touches this repo's own policy files.
#
# Requirements held here: spend/R17 (cheap first, oracle and guard run),
# spend/R18 (a red rung is discarded and the mapped model runs), spend/R19
# (exit codes decide, never the worker's report), spend/R20 (no oracle, no
# cascade, said), spend/R21 (each rung a spawn under one run) and spend/R24
# (the shipped policy names no model, the cascade variable included).
#
# Usage: sh tests/skill-cascade.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

# --- the stub kit tree ------------------------------------------------------
STUBTREE="$SCRATCH/stubtree"
mkdir -p "$STUBTREE/scripts"
cp "$ROOT/scripts/agents.kit.sh" "$ROOT/scripts/agents.lib.sh" \
	"$ROOT/scripts/agent-dispatch.sh" "$ROOT/scripts/skill-dispatch.kit.sh" \
	"$ROOT/scripts/trace.sh" "$STUBTREE/scripts/"
cp -R "$ROOT/.agents" "$STUBTREE/.agents"
TRACE_DIR_T="$SCRATCH/trace"
printf "TRACE_DIR='%s'\n" "$TRACE_DIR_T" >"$STUBTREE/scripts/trace.kit.config.sh"

# The stub worker: does the "work" by writing which model it ran on, leaves an
# untracked file behind, commits, and ALWAYS reports success — the claim the
# cascade must never read. A worker that starts on a tree still holding the
# previous rung's leftovers says so in its work.
STUB="$SCRATCH/stub-agent-harness"
cat >"$STUB" <<'STUB_EOF'
#!/bin/sh
model=''
while [ $# -gt 0 ]; do
	[ "$1" = --model ] && model=$2
	shift
done
cat >/dev/null
dirty=''
for f in *-leftover.txt; do [ -e "$f" ] && dirty=' DIRTY'; done
echo "$model$dirty" >work.txt
echo left >"$model-leftover.txt"
git add work.txt && git commit -qm "work by $model"
echo "REPORT from $model: success, the oracle is green"
STUB_EOF
chmod +x "$STUB"

# write_policy <cascade value> — the stub tree's policy, with the cascade
# variable set to the argument (empty: the shipped default).
write_policy() {
	cat >"$STUBTREE/scripts/agents.kit.stub.config.sh" <<CFG
AGENT_HARNESSES='stub'
AGENT_HARNESS_STUB_CMD='$STUB --model-flag {model_flag} < {prompt_file}'
AGENT_HARNESS_STUB_MODEL_FLAG='--model {model}'
AGENT_TIER_PLANNER='stub:model-for-planning'
AGENT_TIER_IMPLEMENTER='stub:model-for-building'
AGENT_TIER_MECHANICAL='stub:model-mapped'
AGENT_TIER_REVIEWER='stub:model-for-reviewing'
AGENT_CASCADE_MECHANICAL='$1'
CFG
}
write_policy 'stub:model-cheap'

# --- the ticket's repository and its worktree -------------------------------
# The oracle passes only on the mapped model's work, unless told otherwise; the
# guard passes unless told which model's work to refuse.
REPO="$SCRATCH/repo"
mkdir -p "$REPO/tests" "$REPO/scripts"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name t
cat >"$REPO/tests/oracle.sh" <<'EOF'
[ -n "${FIXTURE_ORACLE_GREEN:-}" ] && exit 0
grep -qx model-mapped work.txt
EOF
cat >"$REPO/scripts/guards.kit.sh" <<'EOF'
[ -n "${FIXTURE_GUARD_RED_ON:-}" ] && grep -q "$FIXTURE_GUARD_RED_ON" work.txt && exit 1
exit 0
EOF
cat >"$REPO/tests/pwn.sh" <<'EOF'
touch pwned
EOF
git -C "$REPO" add -A && git -C "$REPO" commit -qm base
BASE=$(git -C "$REPO" rev-parse HEAD)

# fresh_wt — a new linked worktree at the base, so every case starts clean.
WT_N=0
fresh_wt() {
	WT_N=$((WT_N + 1))
	WT="$SCRATCH/wt$WT_N"
	git -C "$REPO" worktree add -q "$WT" -b "ticket$WT_N" "$BASE"
}

ticket() { # <file> <oracle line or empty>
	{
		echo "## Acceptance"
		echo
		[ -n "$2" ] && echo "$2"
		echo "- the thing is done"
	} >"$1"
}
T_ORACLE="$SCRATCH/ticket-oracle.md"
ticket "$T_ORACLE" 'the oracle: `sh tests/oracle.sh`'
T_NONE="$SCRATCH/ticket-none.md"
ticket "$T_NONE" ''
T_EVIL="$SCRATCH/ticket-evil.md"
ticket "$T_EVIL" 'the oracle: `sh tests/pwn.sh; true`'

cascade() { # <ticket file> [extra args…]
	_tf=$1
	shift
	rm -rf "$TRACE_DIR_T"
	t_run_split env -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh \
		implement --tier mechanical --ticket-file "$_tf" --worktree "$WT" --base "$BASE" \
		--prompt 'do the ticket' "$@"
}

# spawn_rungs — the cascade's rung records, `<outcome> <rung> <run>` per line.
spawn_rungs() {
	cat "$TRACE_DIR_T"/*/*.jsonl "$TRACE_DIR_T"/*.jsonl 2>/dev/null |
		grep '"kind":"spawn"' | grep '"rung"' |
		sed -n 's/.*"run":"\([^"]*\)".*"outcome":"\([a-z-]*\)".*"rung":"\{0,1\}\([0-9]\).*/\2 \3 \1/p'
}

# ---------------------------------------------------------------------------
banner "1. A red oracle on the cheap rung escalates to the mapped model (spend/R17, spend/R18)"
# ---------------------------------------------------------------------------
fresh_wt
cascade "$T_ORACLE"
[ "$S_STATUS" = 0 ] && pass "the cascade exits 0 when its last rung passes" ||
	fail "the cascade exited $S_STATUS: $S_ERR"
[ "$(cat "$WT/work.txt" 2>/dev/null)" = model-mapped ] &&
	pass "the work left in the worktree is the mapped model's, on a clean tree" ||
	fail "work.txt reads '$(cat "$WT/work.txt" 2>/dev/null)', expected 'model-mapped'"
[ ! -e "$WT/model-cheap-leftover.txt" ] &&
	pass "the cheap rung's untracked leftovers were discarded" ||
	fail "the cheap rung's leftover survived the reset"
git -C "$WT" log --format=%s "$BASE..HEAD" | grep -q 'model-cheap' &&
	fail "the cheap rung's commit survived the reset" ||
	pass "the cheap rung's commit was reset away, to the ticket's base"
printf '%s\n' "$S_OUT" | grep -q 'REPORT from model-mapped' &&
	pass "stdout carries the passing rung's report" || fail "stdout lacks the mapped rung's report: $S_OUT"
printf '%s\n' "$S_OUT" | grep -q 'REPORT from model-cheap' &&
	fail "stdout still carries the escalated rung's report" ||
	pass "…and never the escalated rung's"
rungs=$(spawn_rungs)
[ "$(printf '%s\n' "$rungs" | awk '{print $1 $2}' | tr '\n' ' ')" = "escalated1 passed2 " ] &&
	pass "spend/R21: the trace holds rung 1 escalated, then rung 2 passed" ||
	fail "spend/R21: the rung records read '$rungs'"
[ "$(printf '%s\n' "$rungs" | awk '{print $3}' | sort -u | wc -l | tr -d ' ')" = 1 ] &&
	pass "spend/R21: …both under one run" || fail "spend/R21: the rungs sit under different runs: $rungs"
case "$S_ERR" in
*escalat*) pass "the escalation is said on stderr" ;;
*) fail "nothing on stderr says the ticket escalated: $S_ERR" ;;
esac

# ---------------------------------------------------------------------------
banner "2. The worker's own claim is never read (spend/R19)"
# ---------------------------------------------------------------------------
# Case 1's cheap worker exited 0 and printed "success, the oracle is green"
# while the oracle was red; it escalated anyway. The mirror: a green oracle
# with a red guard escalates too, and a green pair passes on rung 1.
fresh_wt
FIXTURE_ORACLE_GREEN=1 FIXTURE_GUARD_RED_ON=model-cheap
export FIXTURE_ORACLE_GREEN FIXTURE_GUARD_RED_ON
cascade "$T_ORACLE"
rungs=$(spawn_rungs)
[ "$(printf '%s\n' "$rungs" | awk '{print $1 $2}' | tr '\n' ' ')" = "escalated1 passed2 " ] &&
	pass "spend/R19: a red pairing guard escalates even with the oracle green and the worker claiming success" ||
	fail "spend/R19: a red guard gave rungs '$rungs'"
unset FIXTURE_GUARD_RED_ON

fresh_wt
cascade "$T_ORACLE"
rungs=$(spawn_rungs)
[ "$(printf '%s\n' "$rungs" | awk '{print $1 $2}' | tr '\n' ' ')" = "passed1 " ] &&
	pass "spend/R17: a green oracle and guard on the cheap rung end the cascade there" ||
	fail "spend/R17: a green cheap rung gave '$rungs'"
[ "$(cat "$WT/work.txt" 2>/dev/null)" = model-cheap ] &&
	pass "…and the cheap rung's work is kept" || fail "work.txt reads '$(cat "$WT/work.txt" 2>/dev/null)'"
unset FIXTURE_ORACLE_GREEN

# ---------------------------------------------------------------------------
banner "3. No oracle, no cascade — and the refusal is said (spend/R20)"
# ---------------------------------------------------------------------------
fresh_wt
cascade "$T_NONE"
printf '%s\n' "$S_OUT" | grep -q 'REPORT from model-mapped' &&
	pass "spend/R20: a ticket with no oracle line runs on the tier's mapped model" ||
	fail "spend/R20: a ticket with no oracle line reached: $S_OUT"
printf '%s\n' "$S_OUT" | grep -q 'model-cheap' &&
	fail "spend/R20: …but the cheap model ran too" || pass "spend/R20: …and only that model ran"
case "$S_ERR" in
*"cascade refused"*oracle*) pass "spend/R20: …saying the cascade was refused, and why" ;;
*) fail "spend/R20: no refusal naming the missing oracle on stderr: $S_ERR" ;;
esac

# An oracle line outside the closed list of verification commands is ticket
# text, never run: the cascade is refused the same way.
fresh_wt
cascade "$T_EVIL"
[ ! -e "$WT/pwned" ] && [ ! -e "$STUBTREE/pwned" ] &&
	pass "an oracle line off the closed list is never executed" || fail "the ticket's oracle line was executed"
printf '%s\n' "$S_OUT" | grep -q 'REPORT from model-mapped' &&
	pass "…and the ticket runs on the mapped model" || fail "an off-list oracle reached: $S_OUT"
case "$S_ERR" in
*"cascade refused"*) pass "…saying the cascade was refused" ;;
*) fail "no refusal for an off-list oracle: $S_ERR" ;;
esac

# A cascade model the dispatcher cannot run itself — no agent harness named,
# so agent-dispatch hands it back for the caller to spawn — is refused too: an
# oracle cannot judge work this process never ran.
write_policy 'model-cheap-bare'
fresh_wt
cascade "$T_ORACLE"
printf '%s\n' "$S_OUT" | grep -q 'REPORT from model-mapped' &&
	pass "a cascade model with no agent harness falls through to the mapped model" ||
	fail "a bare cascade model reached: $S_OUT"
case "$S_ERR" in
*"cascade refused"*"agent harness"*) pass "…saying the cascade model is not dispatchable" ;;
*) fail "no refusal for an undispatchable cascade model: $S_ERR" ;;
esac
[ "$(spawn_rungs | awk '{print $1 $2}')" = refused1 ] &&
	pass "spend/R21: …and the refused rung is recorded" || fail "spend/R21: the refused rung reads '$(spawn_rungs)'"
write_policy 'stub:model-cheap'

# ---------------------------------------------------------------------------
banner "4. The reset never touches a main working tree"
# ---------------------------------------------------------------------------
WT=$REPO
cascade "$T_ORACLE"
[ "$S_STATUS" = 2 ] && pass "a --worktree that is a main working tree is refused, exit 2" ||
	fail "a main working tree as --worktree exited $S_STATUS"
[ ! -e "$REPO/work.txt" ] && pass "…before any rung ran in it" || fail "a rung ran in the main working tree"

# ---------------------------------------------------------------------------
banner "5. Where no cascade is declared, none runs (spend/R24)"
# ---------------------------------------------------------------------------
write_policy ''
fresh_wt
cascade "$T_ORACLE"
printf '%s\n' "$S_OUT" | grep -q 'REPORT from model-mapped' &&
	pass "an empty cascade variable runs the mapped model, once" || fail "an empty cascade reached: $S_OUT"
case "$S_ERR" in
*cascade*) fail "an undeclared cascade still spoke of one: $S_ERR" ;;
*) pass "…and says nothing of a cascade it was never asked for" ;;
esac
[ -z "$(spawn_rungs)" ] && pass "…and records no rung" || fail "an undeclared cascade recorded rungs"

# Another tier never cascades, whatever the policy says.
write_policy 'stub:model-cheap'
fresh_wt
rm -rf "$TRACE_DIR_T"
t_run_split env -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh \
	implement --tier implementer --ticket-file "$T_ORACLE" --worktree "$WT" --base "$BASE" --prompt 'x'
printf '%s\n' "$S_OUT" | grep -q 'model-for-building' && ! printf '%s\n' "$S_OUT" | grep -q model-cheap &&
	pass "an implementer ticket never cascades" || fail "an implementer ticket reached: $S_OUT"

SHIPPED="$ROOT/scripts/agents.config.sh"
grep -q "^AGENT_CASCADE_MECHANICAL=''" "$SHIPPED" &&
	pass "spend/R24: the shipped policy file carries AGENT_CASCADE_MECHANICAL, empty" ||
	fail "spend/R24: the shipped policy file does not carry AGENT_CASCADE_MECHANICAL=''"
t_assert_no_model_id "$SHIPPED"
grep -Eq "^AGENT_CASCADE_MECHANICAL='[^']+'" "$ROOT/scripts/agents.kit.config.sh" &&
	pass "the kit's own policy maps the cascade's cheap rung" ||
	fail "the kit's own policy leaves the cascade unmapped"

t_done "skill cascade"
