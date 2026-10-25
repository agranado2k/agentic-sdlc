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
cp "$ROOT/scripts/agents.kit.sh" "$ROOT/scripts/agents.lib.sh" "$ROOT/scripts/budget.lib.sh" \
	"$ROOT/scripts/agent-dispatch.sh" "$ROOT/scripts/skill-dispatch.kit.sh" \
	"$ROOT/scripts/trace.sh" "$ROOT/scripts/stamp.sh" "$ROOT/scripts/vocab.sh" \
	"$ROOT/scripts/vocab.config.sh" "$STUBTREE/scripts/"
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
[ -z "${FIXTURE_RUNS_LOG:-}" ] || { echo "rung on $model"; sh "$FIXTURE_TRACE" runs; } >>"$FIXTURE_RUNS_LOG" 2>&1
dirty=''
for f in *-leftover.txt; do [ -e "$f" ] && dirty=' DIRTY'; done
echo "$model$dirty" >work.txt
[ -n "${FIXTURE_CHEAP_LEFTOVER:-}" ] && [ "$model" = model-cheap ] && echo left >"$model-leftover.txt"
if [ -n "${FIXTURE_CHEAP_NO_COMMIT:-}" ] && [ "$model" = model-cheap ]; then :; else
	git add work.txt && git commit -qm "work by $model"
fi
echo "REPORT from $model: success, the oracle is green"
STUB_EOF
chmod +x "$STUB"

# write_policy <cascade value> [<mapped value>] — the stub tree's policy, with
# the cascade variable set to the argument (empty: the shipped default).
write_policy() {
	cat >"$STUBTREE/scripts/agents.kit.stub.config.sh" <<CFG
AGENT_HARNESSES='stub'
AGENT_HARNESS_STUB_CMD='$STUB --model-flag {model_flag} < {prompt_file}'
AGENT_HARNESS_STUB_MODEL_FLAG='--model {model}'
AGENT_TIER_PLANNER='stub:model-for-planning'
AGENT_TIER_IMPLEMENTER='stub:model-for-building'
AGENT_TIER_MECHANICAL='${2:-stub:model-mapped}'
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
[ -n "${FIXTURE_ORACLE_RED:-}" ] && exit 1
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
# An oracle line that does not open the Acceptance section is prose.
T_BURIED="$SCRATCH/ticket-buried.md"
ticket "$T_BURIED" ''
echo 'the oracle: `sh tests/oracle.sh`' >>"$T_BURIED"

cascade() { # <ticket file> [extra args…]
	_tf=$1
	shift
	rm -rf "$TRACE_DIR_T"
	t_exec env -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh \
		implement --tier mechanical --ticket-file "$_tf" --worktree "$WT" --base "$BASE" \
		--prompt 'do the ticket' "$@"
}

# spawn_rungs — the cascade's rung records, `<outcome> <rung> <subject>` per
# line; every rung record's subject is the cascade's run, `run:<id>`.
spawn_rungs() {
	cat "$TRACE_DIR_T"/*/*.jsonl "$TRACE_DIR_T"/*.jsonl 2>/dev/null |
		grep '"kind":"spawn"' | grep '"rung"' |
		sed -n 's/.*"subject":"\([^"]*\)".*"outcome":"\([a-z-]*\)".*"rung":"\{0,1\}\([0-9]\).*/\2 \3 \1/p'
}
# trace_t <trace.sh argument …> — the stub tree's trace, on the suite's trace.
trace_t() { env TRACE_CONFIG="$STUBTREE/scripts/trace.kit.config.sh" TRACE_QUIET=1 sh "$STUBTREE/scripts/trace.sh" "$@"; }

# ---------------------------------------------------------------------------
banner "1. A red oracle on the cheap rung escalates to the mapped model (spend/R17, spend/R18)"
# ---------------------------------------------------------------------------
fresh_wt
FIXTURE_CHEAP_LEFTOVER=1 FIXTURE_RUNS_LOG="$SCRATCH/runs-746.log" FIXTURE_TRACE="$STUBTREE/scripts/trace.sh"
export FIXTURE_CHEAP_LEFTOVER FIXTURE_RUNS_LOG FIXTURE_TRACE
rm -f "$FIXTURE_RUNS_LOG"
cascade "$T_ORACLE"
unset FIXTURE_CHEAP_LEFTOVER FIXTURE_RUNS_LOG FIXTURE_TRACE
[ "$T_STATUS" = 0 ] && pass "the cascade exits 0 when its last rung passes" ||
	fail "the cascade exited $T_STATUS: $T_ERR"
[ "$(cat "$WT/work.txt" 2>/dev/null)" = model-mapped ] &&
	pass "the work left in the worktree is the mapped model's, on a clean tree" ||
	fail "work.txt reads '$(cat "$WT/work.txt" 2>/dev/null)', expected 'model-mapped'"
[ ! -e "$WT/model-cheap-leftover.txt" ] &&
	pass "the cheap rung's untracked leftovers were discarded" ||
	fail "the cheap rung's leftover survived the reset"
git -C "$WT" log --format=%s "$BASE..HEAD" | grep -q 'model-cheap' &&
	fail "the cheap rung's commit survived the reset" ||
	pass "the cheap rung's commit was reset away, to the ticket's base"
printf '%s\n' "$T_OUT" | grep -q 'REPORT from model-mapped' &&
	pass "stdout carries the passing rung's report" || fail "stdout lacks the mapped rung's report: $T_OUT"
printf '%s\n' "$T_OUT" | grep -q 'REPORT from model-cheap' &&
	fail "stdout still carries the escalated rung's report" ||
	pass "…and never the escalated rung's"
rungs=$(spawn_rungs)
[ "$(printf '%s\n' "$rungs" | awk '{print $1 $2}' | tr '\n' ' ')" = "escalated1 passed2 " ] &&
	pass "spend/R21: the trace holds rung 1 escalated, then rung 2 passed" ||
	fail "spend/R21: the rung records read '$rungs'"
[ "$(printf '%s\n' "$rungs" | awk '{print $3}' | sort -u | wc -l | tr -d ' ')" = 1 ] &&
	pass "spend/R21: …both under one run" || fail "spend/R21: the rungs sit under different runs: $rungs"
case "$T_ERR" in
*escalat*) pass "the escalation is said on stderr" ;;
*) fail "nothing on stderr says the ticket escalated: $T_ERR" ;;
esac
# THE CASCADE'S RUN IS A RUN OF THE TRACE'S (#746): `begin --detached` opens
# it, `end <run>` closes it, so `runs` lists it while a rung works and not after.
_cs_run=$(printf '%s\n' "$rungs" | sed -n '1s/.* run://p')
t_exec trace_t id --check "$_cs_run"
expect_status 0 "the cascade's run is one the trace minted"
_cs_log=$(cat "$SCRATCH/runs-746.log" 2>/dev/null)
case $_cs_log in
*"rung on model-cheap"*"$_cs_run detached live"*) pass "while rung 1 works, runs lists the cascade's run, detached and live" ;;
*) fail "the runs rung 1 saw: $_cs_log" ;;
esac
_cs_worker=$(printf '%s\n' "$_cs_log" | sed -n '/rung on model-cheap/,/rung on/p' | awk -v p="$_cs_run" '$5 == p { print $1 }' | head -1)
[ -n "$_cs_worker" ] && pass "…and the rung's own worker run beside it, the cascade's run its parent" ||
	fail "no run in rung 1's runs names the cascade's run as parent: $_cs_log"
t_exec trace_t runs
expect_resolved "" "…and once the cascade is over, runs lists nothing"
case $(cat "$TRACE_DIR_T"/*/*.jsonl "$TRACE_DIR_T"/*.jsonl 2>/dev/null | grep '"kind":"run.end"' | grep -F "\"run\":\"$_cs_run\"") in
*'"outcome":"ok"'*) pass "…its run closed by a run.end, outcome ok" ;;
*) fail "the cascade's run has no run.end with outcome ok" ;;
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

# Work the cheap rung left uncommitted is work the pairing guard never saw:
# a dirty tree counts as a red guard, however green the oracle.
fresh_wt
FIXTURE_CHEAP_NO_COMMIT=1
export FIXTURE_CHEAP_NO_COMMIT
cascade "$T_ORACLE"
unset FIXTURE_CHEAP_NO_COMMIT
rungs=$(spawn_rungs)
[ "$(printf '%s\n' "$rungs" | awk '{print $1 $2}' | tr '\n' ' ')" = "escalated1 passed2 " ] &&
	pass "spend/R19: a rung that left its work uncommitted escalates, the oracle green" ||
	fail "spend/R19: uncommitted cheap work gave rungs '$rungs'"
case "$T_ERR" in
*uncommitted*) pass "…saying the guard could not judge uncommitted work" ;;
*) fail "nothing on stderr names the uncommitted work: $T_ERR" ;;
esac
unset FIXTURE_ORACLE_GREEN

# ---------------------------------------------------------------------------
banner "2b. The mapped rung red too: nothing left to escalate to"
# ---------------------------------------------------------------------------
fresh_wt
FIXTURE_ORACLE_RED=1
export FIXTURE_ORACLE_RED
cascade "$T_ORACLE"
unset FIXTURE_ORACLE_RED
[ "$T_STATUS" = 1 ] && pass "a red mapped rung exits 1" || fail "a red mapped rung exited $T_STATUS"
rungs=$(spawn_rungs)
[ "$(printf '%s\n' "$rungs" | awk '{print $1 $2}' | tr '\n' ' ')" = "escalated1 failed2 " ] &&
	pass "spend/R21: the trace holds rung 1 escalated, then rung 2 failed" ||
	fail "spend/R21: a red mapped rung gave '$rungs'"
case "$T_ERR" in
*"back to a human"*) pass "…and says the ticket goes back to a human" ;;
*) fail "no hand-back on stderr: $T_ERR" ;;
esac

# A mapped model the dispatcher cannot cross to is handed back to the caller,
# exit 3 with its model id, recorded in-session.
write_policy 'stub:model-cheap' 'model-mapped-bare'
fresh_wt
cascade "$T_ORACLE"
[ "$T_STATUS" = 3 ] && printf '%s\n' "$T_OUT" | grep -qx 'model-mapped-bare' &&
	pass "a mapped rung with no agent harness exits 3 with its model id, for the caller to spawn" ||
	fail "an undispatchable mapped rung exited $T_STATUS with '$T_OUT'"
rungs=$(spawn_rungs)
[ "$(printf '%s\n' "$rungs" | awk '{print $1 $2}' | tr '\n' ' ')" = "escalated1 in-session2 " ] &&
	pass "spend/R21: …recorded in-session on rung 2" || fail "spend/R21: an in-session rung 2 gave '$rungs'"
write_policy 'stub:model-cheap'

# ---------------------------------------------------------------------------
banner "3. No oracle, no cascade — and the refusal is said (spend/R20)"
# ---------------------------------------------------------------------------
fresh_wt
cascade "$T_NONE"
printf '%s\n' "$T_OUT" | grep -q 'REPORT from model-mapped' &&
	pass "spend/R20: a ticket with no oracle line runs on the tier's mapped model" ||
	fail "spend/R20: a ticket with no oracle line reached: $T_OUT"
printf '%s\n' "$T_OUT" | grep -q 'model-cheap' &&
	fail "spend/R20: …but the cheap model ran too" || pass "spend/R20: …and only that model ran"
case "$T_ERR" in
*"cascade refused"*oracle*) pass "spend/R20: …saying the cascade was refused, and why" ;;
*) fail "spend/R20: no refusal naming the missing oracle on stderr: $T_ERR" ;;
esac

# An oracle line outside the closed list of verification commands is ticket
# text, never run: the cascade is refused the same way.
fresh_wt
cascade "$T_EVIL"
[ ! -e "$WT/pwned" ] && [ ! -e "$STUBTREE/pwned" ] &&
	pass "an oracle line off the closed list is never executed" || fail "the ticket's oracle line was executed"
printf '%s\n' "$T_OUT" | grep -q 'REPORT from model-mapped' &&
	pass "…and the ticket runs on the mapped model" || fail "an off-list oracle reached: $T_OUT"
case "$T_ERR" in
*"cascade refused"*) pass "…saying the cascade was refused" ;;
*) fail "no refusal for an off-list oracle: $T_ERR" ;;
esac

fresh_wt
cascade "$T_BURIED"
case "$T_ERR" in
*"cascade refused"*oracle*) pass "an oracle line that does not open the Acceptance section is refused as no oracle" ;;
*) fail "a buried oracle line was read: $T_ERR" ;;
esac

# ---------------------------------------------------------------------------
banner "3b. The section opens by a heading or a bold lead, either way (#759)"
# ---------------------------------------------------------------------------
# /to-tickets once wrote the section as a bold paragraph lead, and the reader
# knew only a heading: two mechanical tickets lost their cascade (#750, #751).
# acc_ticket <file> <the section's opening line> <its first line> [<a line after>]
acc_ticket() {
	{
		echo "Some context, then the ticket's Acceptance section."
		echo
		echo "$2"
		[ -n "$3" ] && echo "$3"
		[ -n "${4:-}" ] && echo "$4"
		echo "- the thing is done"
	} >"$1"
}
# shape_finds <name> <ticket file> — the oracle is read: the cheap rung runs
# and, its oracle green, passes.
shape_finds() {
	fresh_wt
	FIXTURE_ORACLE_GREEN=1
	export FIXTURE_ORACLE_GREEN
	cascade "$2"
	unset FIXTURE_ORACLE_GREEN
	case "$T_ERR" in
	*"cascade refused"*) fail "$1: the cascade was refused: $T_ERR" ;;
	*) printf '%s\n' "$T_OUT" | grep -q 'REPORT from model-cheap' &&
		pass "$1: the oracle is read and the cheap rung staged" ||
		fail "$1: the cheap rung never ran: $T_OUT" ;;
	esac
}
# shape_none <name> <ticket file> — no oracle is read: refused, said.
shape_none() {
	fresh_wt
	cascade "$2"
	case "$T_ERR" in
	*"cascade refused"*"names no oracle"*) pass "$1: no oracle is read" ;;
	*) fail "$1: an oracle was read: $T_ERR $T_OUT" ;;
	esac
}
_oline='the oracle: `sh tests/oracle.sh`'
T_S="$SCRATCH/shape"
acc_ticket "$T_S-h3" '### Acceptance' '' "$_oline"
shape_finds "a level-3 heading, a blank line, the oracle" "$T_S-h3"
acc_ticket "$T_S-bold-dot" '**Acceptance.**' "$_oline"
shape_finds "a bold lead '**Acceptance.**' alone, the oracle on the next line" "$T_S-bold-dot"
acc_ticket "$T_S-bold" '**Acceptance**' '' "$_oline"
shape_finds "a bold lead '**Acceptance**' alone, a blank line, the oracle" "$T_S-bold"
acc_ticket "$T_S-bold-inline" "**Acceptance.** $_oline" ''
shape_finds "a bold lead followed on its line by the oracle" "$T_S-bold-inline"
acc_ticket "$T_S-bold-prose" '**Acceptance.** The suite case holds it.' "$_oline"
shape_none "a bold lead whose first line is prose, the oracle after it" "$T_S-bold-prose"
acc_ticket "$T_S-bold-prose2" '**Acceptance.**' '- the suite case holds it' "$_oline"
shape_none "a bold lead alone whose next line is not the oracle" "$T_S-bold-prose2"
acc_ticket "$T_S-outside" "$_oline" '' '**Acceptance.**'
shape_none "an oracle line before any Acceptance section" "$T_S-outside"
acc_ticket "$T_S-midline" 'The **Acceptance.** lead mid-sentence opens nothing.' "$_oline"
shape_none "a bold 'Acceptance' that does not open its line" "$T_S-midline"
# A bold "Acceptance" in prose that names no oracle opens nothing: a heading
# further down still opens the section (review of #768, M-1).
acc_ticket "$T_S-prose-then-heading" '**Acceptance** is below, under its heading.' '## Acceptance' "$_oline"
shape_finds "prose led by a bold 'Acceptance', then the heading and its oracle" "$T_S-prose-then-heading"

# A worktree with no pairing guard has nothing to judge a rung by.
fresh_wt
rm "$WT/scripts/guards.kit.sh"
cascade "$T_ORACLE"
case "$T_ERR" in
*"cascade refused"*"pairing guard"*) pass "a worktree with no pairing guard is refused the cascade" ;;
*) fail "a guardless worktree was not refused: $T_ERR" ;;
esac
printf '%s\n' "$T_OUT" | grep -q 'REPORT from model-mapped' &&
	pass "…and runs on the mapped model" || fail "a guardless worktree reached: $T_OUT"

# A cascade model the dispatcher cannot run itself — no agent harness named —
# was once refused here and fell through to the mapped model, so the kit's own
# cascade never ran (#682). It is now handed back in-session: section 7.
write_policy 'model-cheap-bare'
fresh_wt
cascade "$T_ORACLE"
printf '%s\n' "$T_OUT" | grep -q 'REPORT from' &&
	fail "a cascade model with no agent harness still fell through to a dispatched rung: $T_OUT" ||
	pass "a cascade model with no agent harness no longer falls through to the mapped model"
write_policy 'stub:model-cheap'

# ---------------------------------------------------------------------------
banner "4. The reset never touches a main working tree"
# ---------------------------------------------------------------------------
WT=$REPO
cascade "$T_ORACLE"
[ "$T_STATUS" = 2 ] && pass "a --worktree that is a main working tree is refused, exit 2" ||
	fail "a main working tree as --worktree exited $T_STATUS"
[ ! -e "$REPO/work.txt" ] && pass "…before any rung ran in it" || fail "a rung ran in the main working tree"

# ---------------------------------------------------------------------------
banner "5. Where no cascade is declared, none runs (spend/R24)"
# ---------------------------------------------------------------------------
write_policy ''
fresh_wt
cascade "$T_ORACLE"
printf '%s\n' "$T_OUT" | grep -q 'REPORT from model-mapped' &&
	pass "an empty cascade variable runs the mapped model, once" || fail "an empty cascade reached: $T_OUT"
case "$T_ERR" in
*cascade*) fail "an undeclared cascade still spoke of one: $T_ERR" ;;
*) pass "…and says nothing of a cascade it was never asked for" ;;
esac
[ -z "$(spawn_rungs)" ] && pass "…and records no rung" || fail "an undeclared cascade recorded rungs"

# Another tier never cascades, whatever the policy says.
write_policy 'stub:model-cheap'
fresh_wt
rm -rf "$TRACE_DIR_T"
t_exec env -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh \
	implement --tier implementer --ticket-file "$T_ORACLE" --worktree "$WT" --base "$BASE" --prompt 'x'
printf '%s\n' "$T_OUT" | grep -q 'model-for-building' && ! printf '%s\n' "$T_OUT" | grep -q model-cheap &&
	pass "an implementer ticket never cascades" || fail "an implementer ticket reached: $T_OUT"

# ---------------------------------------------------------------------------
banner "A cascade rung equal to the mapped model escalates to the implementer's (ADR-0018)"
# ---------------------------------------------------------------------------
# When the mechanical tier itself runs on the cheap model the cascade names,
# rung 2 on "the tier's mapped model" would run the same model again — a
# second draw, not an escalation. The dispatcher then escalates to the
# implementer tier's model instead, and says so.
write_policy 'stub:model-same' 'stub:model-same'
fresh_wt
FIXTURE_ORACLE_GREEN=1 FIXTURE_GUARD_RED_ON=model-same
export FIXTURE_ORACLE_GREEN FIXTURE_GUARD_RED_ON
cascade "$T_ORACLE"
unset FIXTURE_ORACLE_GREEN FIXTURE_GUARD_RED_ON
[ "$T_STATUS" = 0 ] && [ "$(cat "$WT/work.txt" 2>/dev/null)" = model-for-building ] &&
	pass "rung 2 ran on the implementer's model, not the cheap model a second time" ||
	fail "rung 2 left '$(cat "$WT/work.txt" 2>/dev/null)' (status $T_STATUS): $T_ERR"
case "$T_ERR" in
*implementer*) pass "…and stderr says the escalation went to the implementer tier's model" ;;
*) fail "…but stderr does not name the implementer tier: $T_ERR" ;;
esac
_esc_models=$(cat "$TRACE_DIR_T"/*/*.jsonl "$TRACE_DIR_T"/*.jsonl 2>/dev/null | grep '"rung"' |
	sed -n 's/.*"model":"\([^"]*\)".*/\1/p' | tr '\n' ' ')
[ "$_esc_models" = "model-same model-for-building " ] &&
	pass "the rung records carry the cheap model, then the implementer's" ||
	fail "the rung records' models read '$_esc_models'"
write_policy 'stub:model-cheap'

# ---------------------------------------------------------------------------
banner "6. With no --tier, a ticket file's stamp sizes the run (#672)"
# ---------------------------------------------------------------------------
# A cascade dry run sized `implement --ticket-file <f>` from the skill's own
# phase and ignored the file's `Tier: mechanical`, so a mechanical ticket never
# reached the cascade unless the caller repeated the tier by hand.
stamped() { # <file> <stamp lines…> — the oracle ticket, stamped
	cp "$T_ORACLE" "$1"
	_sf=$1
	shift
	printf '\n' >>"$_sf"
	printf '%s\n' "$@" >>"$_sf"
}
T_MECH="$SCRATCH/ticket-mech.md"
stamped "$T_MECH" 'Blocked by: none' 'Tier: mechanical' 'Confidence: high'
nostamp() { # <ticket file> [extra args…] — the dispatch with no --tier
	_tf=$1
	shift
	rm -rf "$TRACE_DIR_T"
	t_exec env -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh \
		implement --ticket-file "$_tf" --worktree "$WT" --base "$BASE" --prompt 'do the ticket' "$@"
}

fresh_wt
nostamp "$T_MECH"
[ "$T_STATUS" = 0 ] && [ "$(spawn_rungs | awk '{print $1 $2}' | tr '\n' ' ')" = "escalated1 passed2 " ] &&
	pass "a 'Tier: mechanical' ticket file with no --tier dispatches as mechanical, and cascades" ||
	fail "a stamped mechanical ticket gave status $T_STATUS, rungs '$(spawn_rungs)': $T_ERR"

fresh_wt
nostamp "$T_MECH" --dry-run
case "$T_ERR" in
*"tier 'mechanical'"*"ticket file's stamp"*) pass "--dry-run names the ticket file's stamp as the source" ;;
*) fail "--dry-run does not name the file's stamp: $T_ERR" ;;
esac

fresh_wt
rm -rf "$TRACE_DIR_T"
t_exec env -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh \
	implement --tier implementer --ticket-file "$T_MECH" --worktree "$WT" --base "$BASE" --prompt 'x'
printf '%s\n' "$T_OUT" | grep -q 'model-for-building' && [ -z "$(spawn_rungs)" ] &&
	pass "an explicit --tier overrides the file's stamp" || fail "--tier implementer over a mechanical stamp reached: $T_OUT"

fresh_wt
nostamp "$T_ORACLE" --dry-run
case "$T_ERR" in
*"tier 'implementer'"*"implement's own phase"*) pass "a stampless file falls back to the skill's phase, saying so" ;;
*) fail "a stampless file did not fall back to the phase: $T_ERR" ;;
esac
case "$T_ERR" in
*"no stamp"*) pass "…and says the file carried no stamp" ;;
*) fail "…but nothing says the file carried no stamp: $T_ERR" ;;
esac

# The domain travels with the tier; a refused stamp is never a sizing.
T_DOM="$SCRATCH/ticket-dom.md"
stamped "$T_DOM" 'Tier: mechanical' 'Domain: content'
fresh_wt
nostamp "$T_DOM" --dry-run
case "$T_ERR" in
*"tier 'mechanical content'"*"ticket file's stamp"*) pass "the stamp's Domain: line travels with its tier" ;;
*) fail "the stamp's domain was lost: $T_ERR" ;;
esac
T_BAD="$SCRATCH/ticket-bad.md"
stamped "$T_BAD" 'Tier: wizard'
fresh_wt
nostamp "$T_BAD"
[ "$T_STATUS" = 2 ] && [ ! -e "$WT/work.txt" ] && [ -z "$(spawn_rungs)" ] &&
	pass "a refused stamp is exit 2, and nothing runs" || fail "a refused stamp exited $T_STATUS: $T_ERR"
case "$T_ERR" in
*wizard*) fail "the refused value was printed: $T_ERR" ;;
*) pass "…and the refused value, ticket text, is never printed" ;;
esac
# Any tier the stamp names sizes the run, not only mechanical.
T_PLAN="$SCRATCH/ticket-plan.md"
stamped "$T_PLAN" 'Tier: planner'
fresh_wt
nostamp "$T_PLAN" --dry-run
case "$T_ERR" in
*"tier 'planner'"*"ticket file's stamp"*) pass "a 'Tier: planner' stamp sizes the run as planner" ;;
*) fail "a planner stamp did not size the run: $T_ERR" ;;
esac
# A tree with no stamp checker reads no stamp: the phase answers, said.
mv "$STUBTREE/scripts/stamp.sh" "$SCRATCH/stamp.sh.away"
fresh_wt
nostamp "$T_MECH" --dry-run
mv "$SCRATCH/stamp.sh.away" "$STUBTREE/scripts/stamp.sh"
case "$T_ERR" in
*"tier 'implementer'"*"implement's own phase"*"no stamp"*) pass "with no scripts/stamp.sh the phase answers, and says no stamp was read" ;;
*) fail "a tree with no stamp checker gave: $T_ERR" ;;
esac
fresh_wt
nostamp "$SCRATCH/no-such-ticket.md" --dry-run
[ "$T_STATUS" = 2 ] && pass "a --ticket-file that is no file is exit 2" || fail "a missing ticket file exited $T_STATUS: $T_ERR"

# ---------------------------------------------------------------------------
banner "7. A rung whose model names no agent harness runs in-session, judged on return (#682)"
# ---------------------------------------------------------------------------
# The kit's own cascade model names no agent harness, so the dispatcher cannot
# run its rung — only the calling session can spawn it. The dispatcher hands
# the rung back (exit 3: the model on stdout, the spawn prompt in the
# worktree's git dir), the session spawns it, then runs the same command again
# with --rung-done: the oracle and the pairing guard run on what the rung
# committed, the verdict is recorded, and the cascade escalates from there.
# The "session" here is a stub in-session spawn: the stub worker, run in the
# worktree on the handed-back model and fed the handed-back prompt.
cascade_keep() { # <ticket file> [extra args…] — the cascade, the trace kept
	_tf=$1
	shift
	t_exec env -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh \
		implement --tier mechanical --ticket 682 --ticket-file "$_tf" --worktree "$WT" --base "$BASE" \
		--prompt 'do the ticket' "$@"
}
state_dir() { echo "$(git -C "$WT" rev-parse --absolute-git-dir)/skill-cascade"; }
spawn_in_session() { # <model> — the stub session's spawn of the handed-back rung
	(cd "$WT" && "$STUB" --model "$1" <"$(state_dir)/prompt") >/dev/null
}
rung_seq() { spawn_rungs | awk '{print $1 $2}' | tr '\n' ' '; }

write_policy 'model-cheap-bare'
fresh_wt
rm -rf "$TRACE_DIR_T"
cascade_keep "$T_ORACLE"
[ "$T_STATUS" = 3 ] && printf '%s\n' "$T_OUT" | grep -qx 'model-cheap-bare' &&
	pass "rung 1 with no agent harness is handed back: exit 3, its model on stdout" ||
	fail "an in-session rung 1 exited $T_STATUS with '$T_OUT': $T_ERR"
[ ! -e "$WT/work.txt" ] && [ -z "$(git -C "$WT" status --porcelain --untracked-files=all)" ] &&
	pass "…nothing ran in the worktree, and the hand-back left it clean" ||
	fail "the hand-back touched the worktree: $(git -C "$WT" status --porcelain)"
_p="$(state_dir)/prompt"
_l1=$(sed -n 1p "$_p" 2>/dev/null) _l2=$(sed -n 2p "$_p" 2>/dev/null)
# Well-formed is the trace's to judge: `Trace-Run: ` then one or two ids the
# trace's `id --check` accepts, and nothing more.
_hb_ids=${_l1#Trace-Run: }
_hb_run=${_hb_ids%% *} _hb_parent=''
case $_hb_ids in *' '*) _hb_parent=${_hb_ids#* } ;; esac
case $_l1 in 'Trace-Run: '*) ;; *) _hb_run='' ;; esac
trace_t id --check "$_hb_run" && { [ -z "$_hb_parent" ] || trace_t id --check "$_hb_parent"; } &&
	pass "the rung's prompt opens with a well-formed Trace-Run line" || fail "the rung prompt's first line reads '$_l1'"
[ "$_l2" = 'Trace-Spawn: tier=mechanical domain=none skill=implement ticket=#682' ] &&
	pass "…and a Trace-Spawn line under it, naming the tier, skill and ticket" ||
	fail "the rung prompt's second line reads '$_l2'"
grep -q 'do the ticket' "$_p" && grep -q "$WT" "$_p" && grep -qi 'never dispatch' "$_p" &&
	pass "…carrying the caller's prompt, the worktree, and a bar on dispatching the ticket again" ||
	fail "the rung prompt reads: $(cat "$_p" 2>/dev/null)"
case "$T_ERR" in
*"agent type 'mechanical'"*--rung-done*) pass "stderr names the agent type to spawn and the --rung-done call that follows" ;;
*) fail "stderr does not say how to drive the rung: $T_ERR" ;;
esac
# The handed-back rung is still the cascade's: its run stays open across the
# hand-back, so `runs` lists it while the session works the rung.
t_exec trace_t runs
expect_out_has "$_hb_run detached" "the cascade's run stays in runs across the hand-back"
[ "$(rung_seq)" = "in-session1 " ] && pass "the hand-back is recorded in-session on rung 1" ||
	fail "the hand-back recorded '$(spawn_rungs)'"

# The stub session spawns the rung; the oracle wants the mapped model's work,
# so rung 1 is red, and rung 2 — dispatchable — runs on the mapped model.
spawn_in_session model-cheap-bare
cascade_keep "$T_ORACLE" --rung-done
[ "$T_STATUS" = 0 ] && [ "$(cat "$WT/work.txt" 2>/dev/null)" = model-mapped ] &&
	pass "--rung-done judges the in-session rung red, resets, and the mapped rung passes" ||
	fail "--rung-done exited $T_STATUS, work '$(cat "$WT/work.txt" 2>/dev/null)': $T_ERR"
git -C "$WT" log --format=%s "$BASE..HEAD" | grep -q 'model-cheap-bare' &&
	fail "the in-session rung's commit survived the reset" || pass "…the in-session rung's commit reset away"
[ "$(rung_seq)" = "in-session1 escalated1 passed2 " ] &&
	pass "the trace holds rung 1 in-session, then escalated, then rung 2 passed" ||
	fail "the rung records read '$(spawn_rungs)'"
[ "$(spawn_rungs | awk '{print $3}' | sort -u | wc -l | tr -d ' ')" = 1 ] &&
	pass "…all under the one cascade run, across both calls" || fail "the rungs sit under different runs: $(spawn_rungs)"
_r1=$(cat "$TRACE_DIR_T"/*/*.jsonl "$TRACE_DIR_T"/*.jsonl 2>/dev/null | grep '"outcome":"escalated"')
case "$_r1" in
*'"oracle_exit":"1"'*'"guard_exit":"0"'* | *'"oracle_exit":1'*'"guard_exit":0'*) pass "…the escalation carries the oracle's and the guard's exit codes" ;;
*) fail "the escalated rung's record reads: $_r1" ;;
esac
[ ! -e "$(state_dir)" ] && pass "a finished cascade leaves no hand-back state behind" ||
	fail "the hand-back state survived the cascade"
t_exec trace_t runs
expect_out_lacks "$_hb_run" "…and --rung-done's end closes the cascade's run: runs no longer lists it"

# Both rungs in-session: the escalation hands rung 2 back the same way, and a
# green in-session rung 2 ends the cascade.
write_policy 'model-cheap-bare' 'model-mapped-bare'
fresh_wt
rm -rf "$TRACE_DIR_T"
FIXTURE_ORACLE_GREEN=1 FIXTURE_GUARD_RED_ON=model-cheap
export FIXTURE_ORACLE_GREEN FIXTURE_GUARD_RED_ON
cascade_keep "$T_ORACLE"
spawn_in_session model-cheap-bare
cascade_keep "$T_ORACLE" --rung-done
[ "$T_STATUS" = 3 ] && printf '%s\n' "$T_OUT" | grep -qx 'model-mapped-bare' &&
	[ "$(sed -n 2p "$(state_dir)/prompt" 2>/dev/null)" = 'Trace-Spawn: tier=mechanical domain=none skill=implement ticket=#682' ] &&
	pass "a red in-session rung 1 hands rung 2 back in-session, on the mapped model" ||
	fail "rung 2's hand-back exited $T_STATUS with '$T_OUT': $T_ERR"
spawn_in_session model-mapped-bare
cascade_keep "$T_ORACLE" --rung-done
unset FIXTURE_ORACLE_GREEN FIXTURE_GUARD_RED_ON
[ "$T_STATUS" = 0 ] && [ "$(rung_seq)" = "in-session1 escalated1 in-session2 passed2 " ] &&
	pass "a green in-session rung 2 passes: rung 1 in-session, escalated, rung 2 in-session, passed" ||
	fail "two in-session rungs gave status $T_STATUS, rungs '$(spawn_rungs)': $T_ERR"
[ "$(cat "$WT/work.txt" 2>/dev/null)" = model-mapped-bare ] &&
	pass "…and rung 2's work is kept" || fail "work.txt reads '$(cat "$WT/work.txt" 2>/dev/null)'"

# A red in-session rung 2: nothing left to escalate to.
fresh_wt
rm -rf "$TRACE_DIR_T"
FIXTURE_ORACLE_RED=1
export FIXTURE_ORACLE_RED
cascade_keep "$T_ORACLE"
spawn_in_session model-cheap-bare
cascade_keep "$T_ORACLE" --rung-done
spawn_in_session model-mapped-bare
cascade_keep "$T_ORACLE" --rung-done
unset FIXTURE_ORACLE_RED
[ "$T_STATUS" = 1 ] && [ "$(rung_seq)" = "in-session1 escalated1 in-session2 failed2 " ] &&
	pass "a red in-session rung 2 exits 1, recorded failed" ||
	fail "a red in-session rung 2 gave status $T_STATUS, rungs '$(spawn_rungs)'"

# A green in-session rung 1 ends the cascade there; its work is kept.
write_policy 'model-cheap-bare'
fresh_wt
rm -rf "$TRACE_DIR_T"
FIXTURE_ORACLE_GREEN=1
export FIXTURE_ORACLE_GREEN
cascade_keep "$T_ORACLE"
spawn_in_session model-cheap-bare
cascade_keep "$T_ORACLE" --rung-done
[ "$T_STATUS" = 0 ] && [ "$(rung_seq)" = "in-session1 passed1 " ] &&
	[ "$(cat "$WT/work.txt" 2>/dev/null)" = model-cheap-bare ] &&
	pass "a green in-session rung 1 passes, its work kept" ||
	fail "a green in-session rung 1 gave status $T_STATUS, rungs '$(spawn_rungs)'"

# A rung that committed nothing is judged on what it left: dirty is red.
fresh_wt
rm -rf "$TRACE_DIR_T"
cascade_keep "$T_ORACLE"
echo uncommitted >"$WT/work.txt"
cascade_keep "$T_ORACLE" --rung-done
unset FIXTURE_ORACLE_GREEN
[ "$(rung_seq | cut -d' ' -f1-2)" = "in-session1 escalated1" ] &&
	pass "an in-session rung that left its work uncommitted escalates" ||
	fail "uncommitted in-session work gave rungs '$(spawn_rungs)'"

# --rung-done with no rung handed back in that worktree is refused.
fresh_wt
rm -rf "$TRACE_DIR_T"
cascade_keep "$T_ORACLE" --rung-done
[ "$T_STATUS" = 2 ] && [ ! -e "$WT/work.txt" ] && [ -z "$(spawn_rungs)" ] &&
	pass "--rung-done with no hand-back in the worktree is exit 2, nothing judged" ||
	fail "a stray --rung-done exited $T_STATUS: $T_ERR"
# …and so is one against another --base than the hand-back's: the guard
# would judge a different range, and the reset would land somewhere else.
fresh_wt
rm -rf "$TRACE_DIR_T"
cascade_keep "$T_ORACLE"
spawn_in_session model-cheap-bare
cascade_keep "$T_ORACLE" --rung-done --base "$(git -C "$WT" rev-parse HEAD)"
[ "$T_STATUS" = 2 ] && [ "$(rung_seq)" = "in-session1 " ] &&
	[ "$(cat "$WT/work.txt" 2>/dev/null)" = model-cheap-bare ] &&
	pass "--rung-done against another --base is exit 2: nothing judged, nothing reset" ||
	fail "--rung-done against another base exited $T_STATUS, rungs '$(spawn_rungs)': $T_ERR"
# …and outside a cascade it means nothing.
t_exec env -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh \
	implement --tier implementer --prompt x --rung-done
[ "$T_STATUS" = 2 ] && pass "--rung-done outside a cascade is exit 2" || fail "--rung-done outside a cascade exited $T_STATUS"

# ---------------------------------------------------------------------------
banner "8. No open-PR step while a staged rung has no verdict (#777)"
# ---------------------------------------------------------------------------
# PR #762 was opened by hand after the cheap rung, never judged through
# --rung-done: its verdict was never recorded and its spawn never ended. A
# session resuming after a usage-limit stop is where that happens. So the
# open-PR step is the dispatcher's to hand out: the same command with
# --deliver exits 0 only when no rung it staged in the worktree awaits a
# verdict, and otherwise refuses, naming the --rung-done call that records it.
write_policy 'model-cheap-bare' 'model-mapped-bare'
fresh_wt
rm -rf "$TRACE_DIR_T"
FIXTURE_ORACLE_GREEN=1
export FIXTURE_ORACLE_GREEN
cascade_keep "$T_ORACLE"
spawn_in_session model-cheap-bare
cascade_keep "$T_ORACLE" --deliver
[ "$T_STATUS" = 2 ] && pass "a staged rung with no verdict: --deliver refuses, exit 2" ||
	fail "--deliver with rung 1 unjudged exited $T_STATUS: $T_ERR"
case "$T_ERR" in
*"rung 1"*"scripts/skill-dispatch.kit.sh"*"'$T_ORACLE'"*--rung-done*) pass "…naming the rung and the --rung-done call that records its verdict, in full" ;;
*) fail "…but stderr does not name the --rung-done call: $T_ERR" ;;
esac
[ "$(rung_seq)" = "in-session1 " ] && [ -e "$(state_dir)/rung" ] &&
	[ "$(cat "$WT/work.txt" 2>/dev/null)" = model-cheap-bare ] &&
	pass "…and the refusal judges nothing, records nothing and keeps the hand-back" ||
	fail "the refusal moved something: rungs '$(spawn_rungs)', work '$(cat "$WT/work.txt" 2>/dev/null)'"
cascade_keep "$T_ORACLE" --rung-done
[ "$T_STATUS" = 0 ] && [ "$(rung_seq)" = "in-session1 passed1 " ] &&
	pass "the named --rung-done call records the verdict" ||
	fail "--rung-done after the refusal exited $T_STATUS, rungs '$(spawn_rungs)': $T_ERR"
cascade_keep "$T_ORACLE" --deliver
[ "$T_STATUS" = 0 ] && pass "after --rung-done, --deliver proceeds: exit 0" ||
	fail "--deliver after the verdict exited $T_STATUS: $T_ERR"
[ "$(rung_seq)" = "in-session1 passed1 " ] && pass "…recording nothing of its own" ||
	fail "--deliver recorded rungs '$(spawn_rungs)'"
unset FIXTURE_ORACLE_GREEN

# Rung 2 handed back after rung 1's verdict is a staged rung too.
fresh_wt
rm -rf "$TRACE_DIR_T"
cascade_keep "$T_ORACLE"
spawn_in_session model-cheap-bare
cascade_keep "$T_ORACLE" --rung-done
spawn_in_session model-mapped-bare
cascade_keep "$T_ORACLE" --deliver
case "$T_STATUS $T_ERR" in
"2 "*"rung 2"*--rung-done*) pass "a handed-back rung 2 with no verdict is refused the same way" ;;
*) fail "--deliver with rung 2 unjudged exited $T_STATUS: $T_ERR" ;;
esac

# A worktree no rung was handed back in has nothing awaiting a verdict.
fresh_wt
cascade_keep "$T_ORACLE" --deliver
[ "$T_STATUS" = 0 ] && [ ! -e "$WT/work.txt" ] &&
	pass "--deliver where nothing was staged is exit 0, and runs no rung" ||
	fail "--deliver on a fresh worktree exited $T_STATUS: $T_ERR"
cascade_keep "$T_ORACLE" --deliver --rung-done
[ "$T_STATUS" = 2 ] && pass "--deliver with --rung-done is exit 2: one asks, the other judges" ||
	fail "--deliver --rung-done exited $T_STATUS"
t_exec env -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh \
	implement --tier implementer --prompt x --deliver
[ "$T_STATUS" = 2 ] && pass "--deliver outside a cascade is exit 2" || fail "--deliver outside a cascade exited $T_STATUS"
grep -q -- '--deliver' "$ROOT/.agents/skills/implement/CASCADE.md" 2>/dev/null &&
	pass "/implement's CASCADE.md names the --deliver call before the open-PR step" ||
	fail "CASCADE.md does not name --deliver"
write_policy 'stub:model-cheap'

# The calling skill says how a session drives a rung.
_cascade_doc="$ROOT/.agents/skills/implement/CASCADE.md"
grep -q -- '--rung-done' "$_cascade_doc" 2>/dev/null && grep -q 'CASCADE.md' "$ROOT/.agents/skills/implement/SKILL.md" &&
	pass "/implement opens CASCADE.md, which names the --rung-done call" ||
	fail "/implement does not say how a session drives an in-session rung"

# ---------------------------------------------------------------------------
banner "9. A cascade diff's reviewer is resolved from the author its verdict recorded (#778)"
# ---------------------------------------------------------------------------
# ADR-0027 gives a diff the Sonnet family wrote an Opus reviewer only when the
# session names the rung's model as the author. Nothing checked it, and the
# rung's commits carry a co-author trailer naming the session's family. So a
# passed verdict records its rung's model as the author — in the trace, and in
# the worktree's git dir where the review dispatch reads it — and the review
# dispatch for a cascade-built ticket resolves against that author, whatever
# the session names, and refuses when none is recorded (ADR-0030).
cat >"$STUBTREE/scripts/agents.kit.stub.config.sh" <<'CFG'
AGENT_HARNESSES='stub'
AGENT_HARNESS_STUB_CMD='STUB --model-flag {model_flag} < {prompt_file}'
AGENT_HARNESS_STUB_MODEL_FLAG='--model {model}'
AGENT_TIER_PLANNER='opus'
AGENT_TIER_IMPLEMENTER='opus'
AGENT_TIER_MECHANICAL='sonnet'
AGENT_TIER_REVIEWER='sonnet'
AGENT_TIER_REVIEWER_FALLBACK='opus'
AGENT_CASCADE_MECHANICAL='sonnet'
CFG
sed -i "s|STUB --model-flag|$STUB --model-flag|" "$STUBTREE/scripts/agents.kit.stub.config.sh"
T_MECH_CASC="$SCRATCH/ticket-mech-cascade.md"
{
	echo "Tier: mechanical"
	echo
	echo "## Acceptance"
	echo
	echo 'the oracle: `sh tests/oracle.sh`'
	echo "- the thing is done"
} >"$T_MECH_CASC"
T_IMPL="$SCRATCH/ticket-impl.md"
{
	echo "Tier: implementer"
	echo
	echo "## Acceptance"
	echo "- the thing is done"
} >"$T_IMPL"
review() { # <session model or empty> <ticket file> [extra args…]
	# BRANCH and BASE name real commits: an in-session review is handed back
	# with its commit pinned and its diff staged (#880).
	_rv_ses=$1 _rv_tf=$2
	shift 2
	t_exec env -C "$STUBTREE" AGENT_HARNESS_SELF=stub ${_rv_ses:+AGENT_SESSION_MODEL=$_rv_ses} \
		sh scripts/skill-dispatch.kit.sh review-pr --tier reviewer --ticket 682 \
		--ticket-file "$_rv_tf" --worktree "$WT" \
		--set BRANCH=HEAD --set BASE="$BASE" --set-file SPEC="$_rv_tf" "$@"
}
# The cascade: rung 1 on the Sonnet family, in-session, green.
fresh_wt
rm -rf "$TRACE_DIR_T"
FIXTURE_ORACLE_GREEN=1
export FIXTURE_ORACLE_GREEN
cascade_keep "$T_ORACLE"
spawn_in_session sonnet
cascade_keep "$T_ORACLE" --rung-done
unset FIXTURE_ORACLE_GREEN
[ "$T_STATUS" = 0 ] && [ "$(rung_seq)" = "in-session1 passed1 " ] ||
	fail "the Sonnet rung did not pass: status $T_STATUS, rungs '$(spawn_rungs)': $T_ERR"
_pv=$(cat "$TRACE_DIR_T"/*/*.jsonl "$TRACE_DIR_T"/*.jsonl 2>/dev/null | grep '"outcome":"passed"')
case "$_pv" in
*'"author":"sonnet"'*) pass "the passed verdict records the rung's model as the author" ;;
*) fail "the passed verdict carries no author: $_pv" ;;
esac
for _ses in opus sonnet claude-fable-5-1 ''; do
	review "$_ses" "$T_MECH_CASC"
	[ "$T_STATUS" = 3 ] && [ "$T_OUT" = opus ] &&
		pass "a Sonnet rung's diff gets the Opus reviewer, the session naming '${_ses:-nothing}'" ||
		fail "the session naming '${_ses:-nothing}' got '$T_OUT', exit $T_STATUS: $T_ERR"
done
case "$T_ERR" in
*"author"*sonnet*) pass "…and stderr says the reviewer was resolved against the recorded author" ;;
*) fail "stderr does not name the recorded author: $T_ERR" ;;
esac
review opus "$T_MECH_CASC" --dry-run
case "$T_ERR" in
*"model 'opus'"*) pass "the dry run names the reviewer the recorded author resolves" ;;
*) fail "the dry run does not name the opus reviewer: $T_ERR" ;;
esac

# The record holds for its own ticket only.
review opus "$T_MECH_CASC" --ticket 999
[ "$T_STATUS" = 2 ] && pass "a record for another ticket is no author: the cascade ticket's review is refused" ||
	fail "a record for ticket #682 answered ticket #999: exit $T_STATUS, '$T_OUT'"

# A mechanical-stamped ticket no cascade ran for is no cascade-built ticket
# (#881): its worktree holds no cascade state and no recorded verdict, so the
# session built it, and its review resolves from the author the session names.
fresh_wt
review opus "$T_MECH_CASC"
[ "$T_STATUS" = 3 ] && [ "$T_OUT" = sonnet ] &&
	pass "a mechanical ticket no cascade built is reviewed: an Opus author gets the Sonnet reviewer" ||
	fail "a mechanical ticket with no cascade record exited $T_STATUS with '$T_OUT': $T_ERR"
review sonnet "$T_MECH_CASC"
[ "$T_STATUS" = 3 ] && [ "$T_OUT" = opus ] &&
	pass "…and a Sonnet author the session names gets the Opus reviewer" ||
	fail "a Sonnet-named mechanical review with no cascade record exited $T_STATUS with '$T_OUT': $T_ERR"
case "$T_ERR" in
*"no rung author"*) fail "a ticket no cascade ran for was called cascade-built: $T_ERR" ;;
*"no cascade record"*) pass "…nothing calls it cascade-built, and stderr says no cascade record was found there" ;;
*) fail "the fall-through does not say no cascade record was found in the worktree: $T_ERR" ;;
esac
# A passed verdict with no model to name still leaves its record (review
# finding M-1 on #889): an empty author is no author, and the review of the
# ticket it ran for is refused, never resolved from the session.
_ra_gd=$(cd "$WT" && git rev-parse --absolute-git-dir)
printf 'model=\nticket=#682\n' >"$_ra_gd/skill-cascade-author"
review opus "$T_MECH_CASC"
[ "$T_STATUS" = 2 ] && [ -z "$T_OUT" ] &&
	pass "a record with an empty author refuses the review: a cascade ran, and named nobody" ||
	fail "an empty-author record let the review through: exit $T_STATUS, '$T_OUT': $T_ERR"
rm -f "$_ra_gd/skill-cascade-author"
# And the writer: a cascade whose passing rung names no model — rung 2 on an
# unmapped mechanical and implementer tier, spawned inheriting — still leaves
# its record, the author empty, and the review of its ticket is refused.
_cfg9=$(cat "$STUBTREE/scripts/agents.kit.stub.config.sh")
cat >"$STUBTREE/scripts/agents.kit.stub.config.sh" <<CFG
AGENT_HARNESSES='stub'
AGENT_HARNESS_STUB_CMD='$STUB --model-flag {model_flag} < {prompt_file}'
AGENT_HARNESS_STUB_MODEL_FLAG='--model {model}'
AGENT_TIER_REVIEWER='sonnet'
AGENT_TIER_REVIEWER_FALLBACK='opus'
AGENT_CASCADE_MECHANICAL='model-cheap-bare'
CFG
fresh_wt
FIXTURE_ORACLE_GREEN=1 FIXTURE_GUARD_RED_ON=model-cheap
export FIXTURE_ORACLE_GREEN FIXTURE_GUARD_RED_ON
cascade_keep "$T_ORACLE"
spawn_in_session model-cheap-bare
cascade_keep "$T_ORACLE" --rung-done
spawn_in_session ''
cascade_keep "$T_ORACLE" --rung-done
unset FIXTURE_ORACLE_GREEN FIXTURE_GUARD_RED_ON
_ra_gd=$(cd "$WT" && git rev-parse --absolute-git-dir)
[ "$T_STATUS" = 0 ] && [ "$(sed -n 's/^model=//p' "$_ra_gd/skill-cascade-author" 2>/dev/null)" = '' ] &&
	grep -qx 'model=' "$_ra_gd/skill-cascade-author" 2>/dev/null &&
	pass "a passed rung that names no model still writes its record, the author empty" ||
	fail "a model-less passed rung left no record: status $T_STATUS, record '$(cat "$_ra_gd/skill-cascade-author" 2>/dev/null)': $T_ERR"
review opus "$T_MECH_CASC"
[ "$T_STATUS" = 2 ] && [ -z "$T_OUT" ] &&
	pass "…and its ticket's review is refused, never resolved from the session" ||
	fail "a model-less cascade's review exited $T_STATUS with '$T_OUT': $T_ERR"
printf '%s\n' "$_cfg9" >"$STUBTREE/scripts/agents.kit.stub.config.sh"
# A rung handed back and never judged is a cascade record with no author:
# still refused, with the existing message (ADR-0030).
cascade_keep "$T_ORACLE"
spawn_in_session sonnet
review opus "$T_MECH_CASC"
[ "$T_STATUS" = 2 ] && [ -z "$T_OUT" ] &&
	pass "a handed-back rung with no verdict records no author: refused, exit 2, no reviewer named" ||
	fail "an unjudged rung's review exited $T_STATUS with '$T_OUT': $T_ERR"
case "$T_ERR" in
*"is cascade-built and"*"no rung author"*--rung-done*) pass "…naming what is missing and the --rung-done call that records it" ;;
*) fail "the refusal does not say what is missing: $T_ERR" ;;
esac

# A cascade with no passed verdict records no author for a review to use:
# rung 1 escalated, rung 2 handed back and not yet judged.
fresh_wt
rm -rf "$TRACE_DIR_T"
FIXTURE_ORACLE_RED=1
export FIXTURE_ORACLE_RED
cascade_keep "$T_ORACLE"
spawn_in_session sonnet
cascade_keep "$T_ORACLE" --rung-done
unset FIXTURE_ORACLE_RED
review opus "$T_MECH_CASC"
[ "$T_STATUS" = 2 ] && pass "a cascade that escalated, with no passed verdict, leaves no author: refused" ||
	fail "a failed cascade's review exited $T_STATUS with '$T_OUT'"
# A fresh cascade forgets the author an earlier one in the worktree recorded.
fresh_wt
FIXTURE_ORACLE_GREEN=1
export FIXTURE_ORACLE_GREEN
cascade_keep "$T_ORACLE"
spawn_in_session sonnet
cascade_keep "$T_ORACLE" --rung-done
unset FIXTURE_ORACLE_GREEN
cascade_keep "$T_ORACLE"
review opus "$T_MECH_CASC"
[ "$T_STATUS" = 2 ] && pass "a cascade started again clears the author the last one recorded" ||
	fail "a restarted cascade's review exited $T_STATUS with '$T_OUT'"

# A ticket the cascade did not build keeps resolving against the session.
fresh_wt
review opus "$T_IMPL"
[ "$T_STATUS" = 3 ] && [ "$T_OUT" = sonnet ] &&
	pass "an implementer ticket's review resolves against the session as before" ||
	fail "an implementer ticket's review exited $T_STATUS with '$T_OUT': $T_ERR"

# A review dispatched with no --ticket takes only a record the cascade wrote
# with no ticket (`ticket=none`), never one another ticket's cascade left.
review_nt() { # <session model> <ticket file> [extra args…] — no --ticket
	_rv_ses=$1 _rv_tf=$2
	shift 2
	t_exec env -C "$STUBTREE" AGENT_HARNESS_SELF=stub AGENT_SESSION_MODEL="$_rv_ses" \
		sh scripts/skill-dispatch.kit.sh review-pr --tier reviewer \
		--ticket-file "$_rv_tf" --worktree "$WT" \
		--set BRANCH=HEAD --set BASE="$BASE" --set-file SPEC="$_rv_tf" "$@"
}
fresh_wt
FIXTURE_ORACLE_GREEN=1
export FIXTURE_ORACLE_GREEN
cascade_keep "$T_ORACLE"
spawn_in_session sonnet
cascade_keep "$T_ORACLE" --rung-done
unset FIXTURE_ORACLE_GREEN
review_nt opus "$T_IMPL"
[ "$T_STATUS" = 3 ] && [ "$T_OUT" = sonnet ] &&
	pass "a ticketless review ignores the record ticket #682's cascade left" ||
	fail "a ticketless review took ticket #682's author: exit $T_STATUS, '$T_OUT': $T_ERR"
review_nt opus "$T_MECH_CASC"
[ "$T_STATUS" = 2 ] && [ -z "$T_OUT" ] &&
	pass "…and a ticketless cascade-built review with only another ticket's record is refused" ||
	fail "a ticketless cascade review exited $T_STATUS with '$T_OUT': $T_ERR"
# A cascade run with no --ticket records `ticket=none`, which a ticketless
# review takes.
fresh_wt
FIXTURE_ORACLE_GREEN=1
export FIXTURE_ORACLE_GREEN
t_exec env -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh \
	implement --tier mechanical --ticket-file "$T_ORACLE" --worktree "$WT" --base "$BASE" \
	--prompt 'do the ticket'
spawn_in_session sonnet
t_exec env -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh \
	implement --tier mechanical --ticket-file "$T_ORACLE" --worktree "$WT" --base "$BASE" \
	--prompt 'do the ticket' --rung-done
unset FIXTURE_ORACLE_GREEN
review_nt opus "$T_MECH_CASC"
[ "$T_STATUS" = 3 ] && [ "$T_OUT" = opus ] &&
	pass "a ticketless cascade's record answers a ticketless review: the Opus reviewer" ||
	fail "a ticketless review of a ticketless cascade exited $T_STATUS with '$T_OUT': $T_ERR"

# An escalated cascade whose rung 2 passes: the author is rung 2's model, the
# implementer's, so the reviewer is resolved against that family, not rung 1's.
fresh_wt
rm -rf "$TRACE_DIR_T"
FIXTURE_ORACLE_RED=1
export FIXTURE_ORACLE_RED
cascade_keep "$T_ORACLE"
spawn_in_session sonnet
cascade_keep "$T_ORACLE" --rung-done
unset FIXTURE_ORACLE_RED
FIXTURE_ORACLE_GREEN=1
export FIXTURE_ORACLE_GREEN
spawn_in_session opus
cascade_keep "$T_ORACLE" --rung-done
unset FIXTURE_ORACLE_GREEN
[ "$T_STATUS" = 0 ] && [ "$(rung_seq)" = "in-session1 escalated1 in-session2 passed2 " ] ||
	fail "the escalated cascade did not pass on rung 2: status $T_STATUS, rungs '$(spawn_rungs)': $T_ERR"
_pv=$(cat "$TRACE_DIR_T"/*/*.jsonl "$TRACE_DIR_T"/*.jsonl 2>/dev/null | grep '"outcome":"passed"')
case "$_pv" in
*'"author":"opus"'*) pass "a rung-2 pass records rung 2's model as the author" ;;
*) fail "the rung-2 passed verdict reads: $_pv" ;;
esac
review sonnet "$T_MECH_CASC"
[ "$T_STATUS" = 3 ] && [ "$T_OUT" = sonnet ] &&
	pass "…so its review resolves against the Opus author, whatever the session names: the Sonnet reviewer" ||
	fail "a rung-2 diff's review exited $T_STATUS with '$T_OUT': $T_ERR"
write_policy 'stub:model-cheap'

SHIPPED="$ROOT/scripts/agents.config.sh"
grep -q "^AGENT_CASCADE_MECHANICAL=''" "$SHIPPED" &&
	pass "spend/R24: the shipped policy file carries AGENT_CASCADE_MECHANICAL, empty" ||
	fail "spend/R24: the shipped policy file does not carry AGENT_CASCADE_MECHANICAL=''"
t_assert_no_model_id "$SHIPPED"
grep -Eq "^AGENT_CASCADE_MECHANICAL='[^']+'" "$ROOT/scripts/agents.kit.config.sh" &&
	pass "the kit's own policy maps the cascade's cheap rung" ||
	fail "the kit's own policy leaves the cascade unmapped"
# ADR-0018: the kit's mechanical tier follows the Sonnet family, and so does
# its cascade rung — the same word, so the escalation rule above is what
# makes the cascade's rung 2 the implementer's model.
_kit_casc=$(sh -c '. "$1"; printf "%s" "$AGENT_CASCADE_MECHANICAL"' _ "$ROOT/scripts/agents.kit.config.sh")
_kit_mech=$(sh -c '. "$1"; printf "%s" "$AGENT_TIER_MECHANICAL"' _ "$ROOT/scripts/agents.kit.config.sh")
[ "$_kit_casc" = "$_kit_mech" ] &&
	pass "the kit's cascade rung is the mechanical tier's own model ('$_kit_casc'), so a red rung escalates to the implementer's" ||
	fail "the kit's cascade rung '$_kit_casc' differs from the mechanical tier's '$_kit_mech' (ADR-0018 makes them one)"

# ---------------------------------------------------------------------------
banner "10. Re-running the cascade refuses while a staged rung has no verdict (#787)"
# ---------------------------------------------------------------------------
# Re-running the plain command once wiped the staged rung, left the earlier
# cascade's run open in the registry and started over — and a session resuming
# after a usage-limit stop is the one likely to re-run it. Now it refuses,
# naming the --rung-done call --deliver names, and moves nothing. Starting
# over is --restart: explicit, and it ends the staged rung's run.
write_policy 'model-cheap-bare'
fresh_wt
rm -rf "$TRACE_DIR_T"
FIXTURE_ORACLE_GREEN=1
export FIXTURE_ORACLE_GREEN
cascade_keep "$T_ORACLE"
spawn_in_session model-cheap-bare
_rr_run=$(cat "$(state_dir)/run" 2>/dev/null)
_rr_head=$(git -C "$WT" rev-parse HEAD)
_rr_state=$(cat "$(state_dir)"/* 2>/dev/null | cksum)
cascade_keep "$T_ORACLE"
[ "$T_STATUS" = 2 ] && pass "a staged rung with no verdict: the plain cascade refuses, exit 2" ||
	fail "re-running the cascade with rung 1 unjudged exited $T_STATUS: $T_ERR"
case "$T_ERR" in
*"rung 1"*"scripts/skill-dispatch.kit.sh"*"'$T_ORACLE'"*--rung-done*--restart*) pass "…naming the --rung-done call --deliver names, and --restart to start over" ;;
*) fail "…but stderr does not name the --rung-done call: $T_ERR" ;;
esac
[ "$(git -C "$WT" rev-parse HEAD)" = "$_rr_head" ] && [ "$(cat "$WT/work.txt" 2>/dev/null)" = model-cheap-bare ] &&
	[ -z "$(git -C "$WT" status --porcelain --untracked-files=all)" ] &&
	pass "…the worktree untouched: the rung's commit and its work stand" ||
	fail "the refusal touched the worktree: head $(git -C "$WT" rev-parse HEAD), work '$(cat "$WT/work.txt" 2>/dev/null)'"
[ "$(cat "$(state_dir)"/* 2>/dev/null | cksum)" = "$_rr_state" ] && [ "$(rung_seq)" = "in-session1 " ] &&
	pass "…the staged rung kept as it was, nothing recorded" ||
	fail "the refusal moved the hand-back: rungs '$(spawn_rungs)'"
t_exec trace_t runs
expect_out_has "$_rr_run detached" "…and the staged rung's run still open, the only cascade run"
[ "$(printf '%s\n' "$T_OUT" | grep -c detached)" = 1 ] && pass "…no second cascade run begun" ||
	fail "the refusal began a run: $T_OUT"
cascade_keep "$T_ORACLE" --rung-done
[ "$T_STATUS" = 0 ] && [ "$(rung_seq)" = "in-session1 passed1 " ] &&
	pass "the named --rung-done call records the verdict" ||
	fail "--rung-done after the refusal exited $T_STATUS, rungs '$(spawn_rungs)': $T_ERR"
cascade_keep "$T_ORACLE"
[ "$T_STATUS" = 3 ] && [ -n "$(cat "$(state_dir)/run" 2>/dev/null)" ] &&
	[ "$(cat "$(state_dir)/run")" != "$_rr_run" ] &&
	pass "after --rung-done the plain cascade runs again, under a new run" ||
	fail "the cascade after the verdict exited $T_STATUS: $T_ERR"

# Starting over is the explicit --restart: the staged rung's run ends,
# stopped, and the cascade runs from rung 1 under a new one.
_rr_run=$(cat "$(state_dir)/run" 2>/dev/null)
spawn_in_session model-cheap-bare
cascade_keep "$T_ORACLE" --restart
[ "$T_STATUS" = 3 ] && [ "$(cat "$(state_dir)/run" 2>/dev/null)" != "$_rr_run" ] &&
	pass "--restart starts the cascade over from rung 1, under a new run" ||
	fail "--restart exited $T_STATUS: $T_ERR"
case "$T_ERR" in
*"$_rr_run"*) pass "…said on stderr, naming the run it ended" ;;
*) fail "--restart said nothing of the run it ended: $T_ERR" ;;
esac
t_exec trace_t runs
expect_out_lacks "$_rr_run" "…and ends the staged rung's run: runs no longer lists it"
cat "$TRACE_DIR_T"/*/*.jsonl "$TRACE_DIR_T"/*.jsonl 2>/dev/null | grep '"kind":"run.end"' | grep -q "$_rr_run.*stopped\|stopped.*$_rr_run" &&
	pass "…recorded stopped" || fail "no stopped run.end for the restarted run"
cascade_keep "$T_ORACLE" --restart --rung-done
[ "$T_STATUS" = 2 ] && pass "--restart with --rung-done is exit 2: one starts over, the other judges" ||
	fail "--restart --rung-done exited $T_STATUS"
cascade_keep "$T_ORACLE" --restart --deliver
[ "$T_STATUS" = 2 ] && pass "--restart with --deliver is exit 2" || fail "--restart --deliver exited $T_STATUS"
t_exec env -C "$STUBTREE" AGENT_HARNESS_SELF=stub sh scripts/skill-dispatch.kit.sh \
	implement --tier implementer --prompt x --restart
[ "$T_STATUS" = 2 ] && pass "--restart outside a cascade is exit 2" || fail "--restart outside a cascade exited $T_STATUS"
grep -q -- '--restart' "$ROOT/.agents/skills/implement/CASCADE.md" 2>/dev/null &&
	pass "/implement's CASCADE.md names --restart as the explicit start-over" ||
	fail "CASCADE.md does not name --restart"
unset FIXTURE_ORACLE_GREEN
write_policy 'stub:model-cheap'

t_done "skill cascade"
