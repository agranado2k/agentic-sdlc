#!/bin/sh
# tests/agents-verifier.test.sh — the kit wrapper's verifier walk (PRD-13,
# runtime/R203-R205 and R224-R226; the kit's ADR-0044 clause 2).
#
# `sh scripts/agents.kit.sh reviewer cross-provider`, with the diff's author
# named in $AGENT_SESSION_MODEL, answers the verifier: the first of the
# policy's AGENT_KIT_VERIFIER_CANDIDATES whose provider differs from the
# author's (rung `cross-provider`); else the first model of the reviewer
# tier's ordered walk whose family differs from the author's (rung
# `same-provider`); else nothing, warned, exit 0. A model's provider is its
# agent harness's, declared per harness as AGENT_KIT_PROVIDER_<HARNESS>; an
# unprefixed model runs on the session's own harness.
#
# Every case drives the real wrapper and resolver in a throwaway tree whose
# policy names stand-ins, never a real model. The last block reads the kit's
# own two policies, structurally.
#
# Usage: sh tests/agents-verifier.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

TREE="$SCRATCH/tree"
mkdir -p "$TREE/scripts"
cp "$KIT/scripts/agents.kit.sh" "$KIT/scripts/agents.lib.sh" "$TREE/scripts/"
cat >"$TREE/scripts/agents.kit.config.sh" <<'EOF'
AGENT_HARNESSES='other'
AGENT_HARNESS_OTHER_CMD='other run {model_flag} < {prompt_file}'
AGENT_HARNESS_OTHER_MODEL_FLAG='--model {model}'
AGENT_TIER_PLANNER='vendor-big-1'
AGENT_TIER_IMPLEMENTER='vendor-big-1'
AGENT_TIER_MECHANICAL='vendor-small-1'
AGENT_TIER_REVIEWER='vendor-small-1'
AGENT_TIER_REVIEWER_FALLBACK='vendor-big-1'
AGENT_KIT_PROVIDER_CLAUDE_CODE='home'
AGENT_KIT_PROVIDER_OTHER='away'
AGENT_KIT_VERIFIER_CANDIDATES='vendor-mid-1 other:rival-one-2 other:rival-two-3'
EOF

# verify [<form>] — the wrapper in the tree, the caller's own environment
# (author, unreachable list, harness) passed through `env` by the case.
verify() { # <env assignments…> -- [<form>]
	_v_env=
	while [ $# -gt 0 ] && [ "$1" != -- ]; do
		_v_env="$_v_env$1
"
		shift
	done
	shift
	# One assignment per line: a value holding spaces (an unreachable list)
	# stays one argument to env.
	_v_ifs=$IFS
	IFS='
'
	# shellcheck disable=SC2086 # the assignments, split on newlines on purpose
	t_exec env -C "$TREE" -u AGENT_HARNESS_SELF -u AGENT_SESSION_MODEL -u AGENT_UNREACHABLE_MODELS -u AGENTS_TIER_QUIET $_v_env sh scripts/agents.kit.sh "$@" reviewer cross-provider
	IFS=$_v_ifs
}

banner "rung 1: a candidate of another provider (R203, R204, R226)"
verify AGENT_SESSION_MODEL=vendor-big-1 -- --model
expect_resolved rival-one-2 "an unprefixed author (home): the first candidate of another provider, the same-provider one skipped"
expect_err_has "rung: cross-provider" "the rung is named apart from the model, on stderr"
verify AGENT_SESSION_MODEL=vendor-big-1 --
expect_resolved rival-one-2 "the bare form prints the model the same"
verify AGENT_SESSION_MODEL=vendor-big-1 -- --harness
expect_resolved other "--harness names the candidate's agent harness"
verify AGENT_SESSION_MODEL=vendor-big-1 -- --rung
expect_resolved cross-provider "--rung prints the rung alone"
verify AGENT_SESSION_MODEL=vendor-big-1 -- --alias
expect_resolved '' "--alias prints no spawn word for a candidate that crosses harnesses"
verify AGENT_SESSION_MODEL=vendor-big-1 AGENT_UNREACHABLE_MODELS=rival-one-2 -- --model
expect_resolved rival-two-3 "a candidate the caller named unreachable is skipped, in policy order"
verify AGENT_SESSION_MODEL=vendor-big-1 AGENT_UNREACHABLE_MODELS=other:rival-one-2 -- --model
expect_resolved rival-two-3 "an unreachable name may carry its harness prefix"
verify AGENT_SESSION_MODEL=other:rival-two-3 -- --model
expect_resolved vendor-mid-1 "a prefixed author takes its harness's provider (away): the unprefixed candidate answers"
verify AGENT_SESSION_MODEL=other:rival-two-3 -- --harness
expect_resolved '' "--harness prints nothing for a candidate on the session's own harness"
verify AGENT_SESSION_MODEL=other:rival-two-3 -- --alias
expect_resolved mid "--alias folds an in-session candidate to its spawn word"

banner "rung 2: the reviewer walk, another family (R224, R226)"
UNR='AGENT_UNREACHABLE_MODELS=rival-one-2 rival-two-3'
verify AGENT_SESSION_MODEL=vendor-big-1 "$UNR" -- --model
expect_resolved vendor-small-1 "no other-provider candidate left: the reviewer tier, its family differing from the author's"
expect_err_has "rung: same-provider"
verify AGENT_SESSION_MODEL=vendor-big-1 "$UNR" -- --rung
expect_resolved same-provider "--rung names the second rung"
verify AGENT_SESSION_MODEL=vendor-small-1 "$UNR" -- --model
expect_resolved vendor-big-1 "an author of the reviewer's family walks on to the fallback"
verify AGENT_SESSION_MODEL=vendor-big-1 'AGENT_UNREACHABLE_MODELS=rival-one-2 rival-two-3 small' -- --model
expect_resolved '' "a spawn word named unreachable covers the ids that fold to it, and a spent walk prints nothing"
expect_status 0 "a spent walk exits 0"

EMPTYC="$SCRATCH/empty-candidates"
mkdir -p "$EMPTYC/scripts"
cp "$TREE/scripts/agents.kit.sh" "$TREE/scripts/agents.lib.sh" "$EMPTYC/scripts/"
sed "s/^AGENT_KIT_VERIFIER_CANDIDATES=.*/# AGENT_KIT_VERIFIER_CANDIDATES='other:rival-one-2'   # out until its CLI logs in/" "$TREE/scripts/agents.kit.config.sh" >"$EMPTYC/scripts/agents.kit.config.sh"
t_exec env -C "$EMPTYC" -u AGENT_HARNESS_SELF -u AGENT_UNREACHABLE_MODELS AGENT_SESSION_MODEL=vendor-big-1 sh scripts/agents.kit.sh --rung reviewer cross-provider
expect_resolved same-provider "candidates commented out: the walk takes the same-provider rung"
t_exec env -C "$EMPTYC" -u AGENT_HARNESS_SELF -u AGENT_UNREACHABLE_MODELS AGENT_SESSION_MODEL=vendor-big-1 sh scripts/agents.kit.sh --model reviewer cross-provider
expect_resolved vendor-small-1 "candidates commented out: the reviewer walk's other family answers"

banner "neither rung, or no author's provider (R205)"
verify AGENT_SESSION_MODEL=vendor-small-1 'AGENT_UNREACHABLE_MODELS=rival-one-2 rival-two-3 vendor-big-1' -- --model
expect_resolved '' "both rungs spent: nothing on stdout, exit 0"
expect_err_has "no verifier" "both rungs spent: a warning says so"
verify -- --model
expect_resolved '' "no author named: nothing, exit 0"
expect_err_has "no verifier"
verify AGENT_SESSION_MODEL=vendor-big-1 AGENT_HARNESS_SELF=nowhere -- --model
expect_resolved '' "an unprefixed author on a harness with no declared provider: nothing, exit 0 (R204)"
expect_err_has "provider"
verify 'AGENT_SESSION_MODEL=else:x-y-1' -- --model
expect_resolved '' "an author prefixed with an undeclared harness: nothing, exit 0"
verify 'AGENT_SESSION_MODEL=vendor-big-1' 'AGENT_HARNESS_SELF=a;b' -- --model
expect_resolved '' "a malformed session harness is no declared provider, never evaluated"
verify AGENT_SESSION_MODEL=vendor-big-1 AGENTS_TIER_QUIET=1 "$UNR small" -- --model
expect_out_is '' "quiet, spent: nothing on stdout"
[ -z "$T_ERR" ]
_t_expect $? "AGENTS_TIER_QUIET=1 silences the warning" "stderr was not empty"

banner "the kit's own policies declare the walk (R225)"
for _pol in agents.kit.config.sh agents.kit.codex.config.sh; do
	_vals=$(
		# shellcheck disable=SC1090
		. "$KIT/scripts/$_pol"
		printf '%s|%s|%s\n' "${AGENT_KIT_PROVIDER_CLAUDE_CODE:-}" "${AGENT_KIT_PROVIDER_CODEX:-}" "${AGENT_KIT_VERIFIER_CANDIDATES:-}"
	)
	_cc=${_vals%%|*} _rest=${_vals#*|}
	_cx=${_rest%%|*} _cands=${_rest#*|}
	[ -n "$_cc" ] && [ -n "$_cx" ] && [ "$_cc" != "$_cx" ] && [ -n "$_cands" ]
	_t_expect $? "$_pol declares a provider per agent harness, two apart, and verifier candidates" "providers '$_cc' '$_cx', candidates '$_cands'"
	_ids=$(env -C "$KIT" AGENTS_CONFIG="scripts/$_pol" sh scripts/agents.lib.sh --ids 2>/dev/null)
	_missing=
	for _c in $_cands; do
		printf '%s\n' "$_ids" | grep -qxF "${_c#*:}" || _missing="$_missing $_c"
	done
	[ -z "$_missing" ]
	_t_expect $? "$_pol: every verifier candidate is an id --ids lists, so its spawn can be traced" "unlisted:$_missing"
done
# The other harness's CLI is not logged in (PRD-13 §2): the kit's Claude
# Code policy declares no candidate of another provider, so its implementer's
# diff is verified on the second rung, a model of another family.
_impl=$(env -C "$KIT" -u AGENT_HARNESS_SELF sh scripts/agents.kit.sh --model implementer 2>/dev/null)
_impl_fam=$(env -C "$KIT" -u AGENT_HARNESS_SELF sh scripts/agents.kit.sh --alias implementer 2>/dev/null)
t_exec env -C "$KIT" -u AGENT_HARNESS_SELF -u AGENT_UNREACHABLE_MODELS AGENT_SESSION_MODEL="$_impl" sh scripts/agents.kit.sh --rung reviewer cross-provider
expect_resolved same-provider "the kit's policy, no other-provider candidate: its implementer's diff takes the same-provider rung"
t_exec env -C "$KIT" -u AGENT_HARNESS_SELF -u AGENT_UNREACHABLE_MODELS AGENT_SESSION_MODEL="$_impl" sh scripts/agents.kit.sh --alias reviewer cross-provider
[ -n "$T_OUT" ] && [ -n "$_impl_fam" ] && [ "$T_OUT" != "$_impl_fam" ]
_t_expect $? "the kit's policy: that verifier is of another family than the implementer's ('$_impl_fam')" "--alias printed '${T_OUT:-nothing}'"

t_done "agents verifier walk"
