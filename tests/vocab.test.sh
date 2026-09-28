#!/bin/sh
# tests/vocab.test.sh — the vocabulary checker as a SEAM.
#
# `sh scripts/vocab.sh [check] [<line> …]` is the seam: one question — "is
# this value legal for this field, given the other fields?" — asked by a skill
# about to publish a ticket, by a session reading one, and by this suite. What
# is asserted is the VERDICT through the script's public surface (its lines
# in, its exit code, the stdout/stderr split), never its internals.
#
# Every case drives the real script against a real throwaway policy file
# pointed at by $VOCAB_CONFIG — the same policy-as-data seam the tier resolver
# has in $AGENTS_CONFIG and the trace in $TRACE_CONFIG — or against the shipped
# vocabularies when none is named. PRD #273, ticket #274.
#
# Usage: sh tests/vocab.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
VOCAB="$KIT/scripts/vocab.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

# vocab <args…> — the script, run as a skill runs it, streams kept apart.
vocab() { t_run_split sh "$VOCAB" "$@"; }

# ---------------------------------------------------------------------------
banner "The demo — PRD scenario 1: a misspelled tier is refused before the quiz"
# ---------------------------------------------------------------------------
# The one judgment that already had a closed vocabulary was the tier, and only
# at the resolver — a ticket body saying `Tier: Implementor` passed every
# check until /implement read it. The checker refuses it where it is written,
# names the field, the value and the vocabulary, and exits 2.
unset VOCAB_CONFIG
vocab 'Tier: Implementor'
s_assert_status 2 "'Tier: Implementor' is refused with exit 2"
s_assert_err_has "tier: 'Implementor' is not one of planner implementer mechanical reviewer"
[ -z "$S_OUT" ] && pass "stdout carries nothing — the reasons are diagnostics, on stderr" ||
	fail "stdout should be empty, got '$S_OUT'"

vocab 'Tier: implementer'
s_assert_resolved "" "'Tier: implementer' is accepted with exit 0 and no output"

# ---------------------------------------------------------------------------
banner "Every shipped vocabulary accepts its own tokens, in the shipped words"
# ---------------------------------------------------------------------------
# The shipped policy file and the script's built-in defaults are held equal by
# tests/vocab-policy.test.sh; here the question is only that each token the
# script SAYS it accepts, it accepts — read back through `fields`, so the
# list this loop walks is the script's own answer and not a copy.
vocab fields
s_assert_status 0 "'fields' prints the effective vocabularies"
s_assert_out_has "tier: planner implementer mechanical reviewer" "the tier's four names, in the manual's order"
s_assert_out_has "domain (open):" "the task domain is marked OPEN — membership is not enforced on it"
FIELDS_OUT=$S_OUT
printf '%s\n' "$FIELDS_OUT" | sed 's/ (open)//' | while IFS=: read -r field tokens; do
	for tok in $tokens; do
		if sh "$VOCAB" "$field: $tok" 2>"$SCRATCH/err"; then
			pass "$field accepts '$tok'"
		else
			fail "$field refused its own token '$tok': $(cat "$SCRATCH/err")"
		fi
	done
done
# The inner loop ran in a pipeline's subshell, so its failures never reached
# $failures; count them again from the outside.
n_fields=$(printf '%s\n' "$FIELDS_OUT" | wc -l | tr -d ' ')
[ "$n_fields" -ge 8 ] && pass "at least eight decision fields are declared ($n_fields)" ||
	fail "expected the PRD's eight decision fields at least, got $n_fields"
printf '%s\n' "$FIELDS_OUT" | sed 's/ (open)//' | while IFS=: read -r field tokens; do
	for tok in $tokens; do sh "$VOCAB" "$field: $tok" 2>/dev/null || echo "$field:$tok"; done
done >"$SCRATCH/refused"
[ ! -s "$SCRATCH/refused" ] && pass "no shipped token is refused by its own field" ||
	fail "shipped tokens refused: $(tr '\n' ' ' <"$SCRATCH/refused")"

# ---------------------------------------------------------------------------
banner "An invented token, an empty value, a value outside the shape"
# ---------------------------------------------------------------------------
vocab 'Severity: Medium-High'
s_assert_status 2 "'Severity: Medium-High' — a band nobody declared — is exit 2"
s_assert_err_has "severity: 'Medium-High' is not one of critical high medium low"

vocab 'Tier: senior'
s_assert_status 2 "'Tier: senior' — an invented tier — is exit 2"
s_assert_err_has "tier: 'senior' is not one of"

vocab 'Tier:'
s_assert_status 2 "'Tier:' with no value is exit 2"
s_assert_err_has "tier: the value is empty"

vocab 'Confidence:    '
s_assert_status 2 "a value that is only blanks is empty too"
s_assert_err_has "confidence: the value is empty"

# The task domain is OPEN — an undeclared token is local policy, never an
# error (the resolver falls back to the tier in silence) — but its SHAPE is
# not: the token is interpolated into a variable name.
vocab 'Domain: judge'
s_assert_resolved "" "an undeclared domain token of the right shape is accepted — the domain is open"
vocab 'Domain: Content'
s_assert_status 2 "a domain token outside the shape is exit 2"
s_assert_err_has "domain: 'Content' is not a well-formed token"
s_assert_err_has "[a-z][a-z0-9-]*"
vocab 'Domain: html report'
s_assert_status 2 "a domain token with a space is exit 2"

# Several violations, several reasons — one line each, all of them.
vocab 'Tier: senior' 'Label: hitl' 'Severity: critical'
s_assert_status 2 "two bad values in one call are exit 2"
s_assert_err_has "tier: 'senior'"
s_assert_err_has "label: 'hitl'"
s_assert_err_lacks "severity:"

# ---------------------------------------------------------------------------
banner "The input is lines — arguments, or stdin; a whole body may be handed over"
# ---------------------------------------------------------------------------
BODY="$SCRATCH/ticket.body"
cat >"$BODY" <<'BODYEOF'
**Objective (PRD #273):** The chain's closed-set judgments become values.

Part of #273. Design: https://example.invalid/8OK_QmBCZT

Tier: planner
Domain: content
Blocked by: #271
Note: this line has a colon and is not a decision.

## Acceptance
- A suite drives the script red first: every shipped vocabulary accepts.
BODYEOF
t_run_split sh "$VOCAB" <"$BODY"
s_assert_resolved "" "a whole ticket body on stdin checks clean — prose lines with colons are not decisions"
sed 's/^Tier: planner$/tier: Implementor/' "$BODY" >"$SCRATCH/bad.body"
t_run_split sh "$VOCAB" <"$SCRATCH/bad.body"
s_assert_status 2 "the same body with a misspelled tier is exit 2 on stdin"
s_assert_err_has "tier: 'Implementor'"
t_run_split sh "$VOCAB" check <"$SCRATCH/bad.body"
s_assert_status 2 "'check' spelled out reads stdin the same way"
printf 'Tier: reviewer' >"$SCRATCH/nonl"
t_run_split sh "$VOCAB" <"$SCRATCH/nonl"
s_assert_resolved "" "a last line with no trailing newline is still read"

# The field name is matched without regard to case or separator; the value
# exactly.
vocab 'TIER: mechanical'
s_assert_resolved "" "the field name is case-insensitive"
vocab 'Command shaped: yes' 'command_shaped: no'
s_assert_resolved "" "spaces and underscores in a field name read as hyphens"
vocab 'Tier: MECHANICAL'
s_assert_status 2 "the value is not case-folded — a token is spelled one way"

# A body that carries no decision line at all is legal: nothing to refuse.
vocab 'just prose'
s_assert_resolved "" "a line with no colon is ignored"
vocab 'Blocked by: #12'
s_assert_resolved "" "a line whose key is not a declared field is ignored"

# One ticket body checks in under a second — it is called inside the quiz
# loop. Five runs in four wall seconds bounds each at under one.
t0=$(date +%s)
for _ in 1 2 3 4 5; do sh "$VOCAB" <"$BODY"; done
t1=$(date +%s)
[ $((t1 - t0)) -le 4 ] && pass "five body checks took $((t1 - t0))s — under one second each" ||
	fail "five body checks took $((t1 - t0))s — over the one-second budget per body"

# ---------------------------------------------------------------------------
banner "Usage — a caller that asks the wrong thing gets an error, not a guess"
# ---------------------------------------------------------------------------
vocab --frobnicate
s_assert_status 2 "an unknown option exits 2"
s_assert_err_has "usage"
vocab fields extra
s_assert_status 2 "'fields' takes no argument"
s_assert_err_has "usage"

# ---------------------------------------------------------------------------
banner "Where the vocabularies come from"
# ---------------------------------------------------------------------------
# A policy file a project wrote: a narrower severity scale, a field of its own,
# and the domain kept open.
write_config() {
	mkdir -p "$(dirname "$1")"
	printf '%s\n' "$2" >"$1"
}
CONFIG_OWN=$(
	cat <<'EOFC'
VOCAB_FIELDS='tier severity mood'
VOCAB_OPEN=''
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_SEVERITY='blocking advisory'
VOCAB_MOOD='calm brisk'
VOCAB_RULES=''
EOFC
)
OWN="$SCRATCH/own.config.sh"
write_config "$OWN" "$CONFIG_OWN"

VOCAB_CONFIG=$OWN
export VOCAB_CONFIG
vocab 'Severity: advisory' 'Mood: brisk'
s_assert_resolved "" "a named policy file's own vocabularies answer"
vocab 'Severity: high'
s_assert_status 2 "the shipped severity is refused once a project narrowed the scale"
s_assert_err_has "severity: 'high' is not one of blocking advisory"
vocab 'Domain: content'
s_assert_resolved "" "a field the policy file does not declare is not a decision line — ignored"
vocab fields
s_assert_out_is "tier: planner implementer mechanical reviewer
severity: blocking advisory
mood: calm brisk" "'fields' prints the named file's vocabularies, one field per line, canonical order"

VOCAB_CONFIG="$SCRATCH/absent.config.sh"
vocab 'Tier: planner'
s_assert_status 2 "a policy file named explicitly and missing is exit 2"
s_assert_err_has "does not exist"
unset VOCAB_CONFIG

# Orders 2 and 3 anchor on where the SCRIPT lives — never on the cwd. The
# fixture is the resolver suite's: the operator's own copy, invoked by
# absolute path, from inside somebody else's clone whose policy file would
# announce itself if run.
install_vocab() {
	mkdir -p "$1"
	cp "$VOCAB" "$1/vocab.sh"
}
_run_from_body() { _rf_cwd=$1; _rf_script=$2; shift 2; cd "$_rf_cwd" && unset VOCAB_CONFIG && sh "$_rf_script" "$@"; }
run_from() { t_run_split _run_from_body "$@"; }

t_repo
OWN_REPO=$REPO
install_vocab "$OWN_REPO/tools"
write_config "$OWN_REPO/scripts/vocab.config.sh" "$CONFIG_OWN"
run_from "$OWN_REPO" "$OWN_REPO/tools/vocab.sh" 'Severity: advisory'
s_assert_resolved "" "the script's own repo root supplies scripts/vocab.config.sh with no env var set"

t_repo
FOREIGN=$REPO
write_config "$FOREIGN/scripts/vocab.config.sh" "$(
	cat <<'EOFC'
echo "FOREIGN-CONFIG-EXECUTED" >&2
VOCAB_FIELDS='severity'
VOCAB_SEVERITY='foreign'
EOFC
)"
run_from "$FOREIGN" "$OWN_REPO/tools/vocab.sh" 'Severity: advisory'
s_assert_resolved "" "the script's own repo supplies the vocabularies, not the repo the caller stands in"
s_assert_err_lacks "FOREIGN-CONFIG-EXECUTED"

LOOSE="$SCRATCH/loose"
install_vocab "$LOOSE"
write_config "$LOOSE/vocab.config.sh" "$CONFIG_OWN"
run_from "$FOREIGN" "$LOOSE/vocab.sh" 'Mood: calm'
s_assert_resolved "" "a sibling vocab.config.sh is found for a script outside any repo"
s_assert_err_lacks "FOREIGN-CONFIG-EXECUTED"

# No policy file anywhere is a WORKING STATE: the shipped vocabularies apply.
BARE="$SCRATCH/bare"
install_vocab "$BARE"
run_from "$FOREIGN" "$BARE/vocab.sh" 'Severity: high'
s_assert_resolved "" "with no policy file anywhere the shipped vocabularies apply"
run_from "$FOREIGN" "$BARE/vocab.sh" 'Severity: foreign'
s_assert_status 2 "…and the foreign repo's word is not among them"
s_assert_err_lacks "FOREIGN-CONFIG-EXECUTED"

t_done "vocab"
