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
# One pass, from a file rather than a pipeline so a failure reaches
# $failures, with the `rule:` lines left out — a rule is not a field.
printf '%s\n' "$S_OUT" | grep -v '^rule: ' | sed 's/ (open)//' >"$SCRATCH/fields"
: >"$SCRATCH/refused"
while IFS=: read -r field tokens; do
	for tok in $tokens; do
		sh "$VOCAB" "$field: $tok" </dev/null 2>>"$SCRATCH/refused" || echo "  $field:$tok" >>"$SCRATCH/refused"
	done
done <"$SCRATCH/fields"
[ ! -s "$SCRATCH/refused" ] && pass "every shipped token is accepted by its own field" ||
	fail "shipped tokens refused: $(tr '\n' ' ' <"$SCRATCH/refused")"
for field in tier label domain severity status action outcome confidence command-shaped author-kind; do
	grep -q "^$field:" "$SCRATCH/fields" && pass "the PRD's field '$field' is declared" ||
		fail "the PRD's field '$field' is not declared"
done

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

# A value that is SEVERAL tokens at once is no member: `Tier: planner
# implementer` is an agent echoing the vocabulary instead of choosing from
# it, and `Action: apply reply` would carry `apply` past the shipped rule's
# `!=` — a contiguous run of the list is still not one of its tokens.
vocab 'Tier: planner implementer'
s_assert_status 2 "a value made of two tokens is exit 2 — a closed field takes one"
s_assert_err_has "tier: 'planner implementer' is not one of planner implementer mechanical reviewer"
vocab 'Command shaped: yes' 'Action: apply reply'
s_assert_status 2 "…so two tokens cannot smuggle 'apply' past the shipped rule"
s_assert_err_has "action: 'apply reply' is not one of apply reply escalate"

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
printf 'Tier: Implementor' >"$SCRATCH/nonl"
t_run_split sh "$VOCAB" <"$SCRATCH/nonl"
s_assert_status 2 "a last line with no trailing newline is still read — refused, so the read is proved"
s_assert_err_has "tier: 'Implementor'"
t_run_split sh "$VOCAB" </dev/null
s_assert_resolved "" "empty stdin — a body with no decision line in it yet — is legal"

# The field name is matched without regard to case or separator; the value
# exactly.
vocab 'TIER: mechanical'
s_assert_resolved "" "the field name is case-insensitive"
vocab 'Tier: planner' 'tier: planner'
s_assert_resolved "" "a field repeated with the same value is one answer"
vocab 'Command shaped: yes' 'command_shaped: no'
s_assert_status 2 "spaces and underscores in a field name read as hyphens — the two spellings are one field, and it now has two values"
s_assert_err_has "command-shaped: 'no' repeats the field, which already read 'yes'"
vocab 'Tier: MECHANICAL'
s_assert_status 2 "the value is not case-folded — a token is spelled one way"

# A body that carries no decision line at all is legal: nothing to refuse.
vocab check 'just prose'
s_assert_resolved "" "a line with no colon is ignored"
vocab 'Blocked by: #12'
s_assert_resolved "" "a line whose key is not a declared field is ignored"
# …but a FIRST argument with no colon is not a line at all: it is a
# subcommand nobody declared, and a silent exit 0 on `fieldz` would be a
# pass a caller never earned.
vocab fieldz
s_assert_status 2 "a first argument that is neither a subcommand nor a 'Field: value' line is a usage error"
s_assert_err_has "usage"

# One check is bounded in CPU time at the sizes the callers send. The claim
# is about the CHECKER's work, so it is the checker's own CPU time that is
# measured — user plus system, of five child runs, as the shell's `times`
# reports it — and not the wall clock: this assertion used to read `date +%s`
# around the loop, and on a loaded host the same five checks took 7 and 22
# wall seconds while doing the same work, a red that said nothing about the
# checker. CPU time is what a slower checker moves and what a busy host
# leaves alone. The bounds are what is claimed and no more: a ticket's dozen
# lines, and a typed return's four — the most any kit call site hands over
# (the section after this one holds them to it). They are not a claim about
# scale: the checker does per-line work on every line that carries a colon,
# linear in their number (#337 measured 2,000 such lines at 7 to 32
# CPU-seconds a check, by whether their keys are declared fields).
#
# five_checks_ms <checker> <input> — the CPU milliseconds of five checks of
# <input>, or "unmeasured".
five_checks_ms() {
	(
		for _ in 1 2 3 4 5; do sh "$1" <"$2"; done >/dev/null 2>&1
		times
	) | awk 'NR == 2 { for (i = 1; i <= 2; i++) { split($i, a, "m"); sub(/s$/, "", a[2]); sub(/,/, ".", a[2]); t += a[1] * 60 + a[2] }
	printf "%d", t * 1000; seen = 1 } END { if (!seen) printf "unmeasured" }'
}
# within_budget <checker> <input> <ms for five> <what> — pass or fail it.
within_budget() {
	cpu_ms=$(five_checks_ms "$1" "$2")
	case $cpu_ms in
	*[!0-9]* | "") fail "five checks of $4 — the shell's \`times\` gave no children's CPU time to read ('$cpu_ms')" ;;
	*)
		[ "$cpu_ms" -le "$3" ] && pass "five checks of $4 cost ${cpu_ms}ms of CPU — within ${3}ms" ||
			fail "five checks of $4 cost ${cpu_ms}ms of CPU — over the ${3}ms budget"
		;;
	esac
}
within_budget "$VOCAB" "$BODY" 2500 "a ticket body"
RETURN4="$SCRATCH/typed.return"
printf '%s\n' 'Author-kind: human' 'Command-shaped: no' 'Action: apply' 'Evidence: "a quoted span"' >"$RETURN4"
within_budget "$VOCAB" "$RETURN4" 2000 "a typed return's four lines"
# The bait: a checker that does twelve times the work fails that budget —
# the bound can go red, so its green says something.
cat >"$SCRATCH/costly.vocab.sh" <<EOCOSTLY
in=\$(mktemp) && cat >"\$in"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do sh "$VOCAB" <"\$in"; done
rm -f "\$in"
EOCOSTLY
costly_ms=$(five_checks_ms "$SCRATCH/costly.vocab.sh" "$RETURN4")
case $costly_ms in
*[!0-9]* | "") fail "the costly bait went unmeasured ('$costly_ms')" ;;
*)
	[ "$costly_ms" -gt 2000 ] &&
		pass "a checker twelve times as costly breaks the four-line budget (${costly_ms}ms) — the bound can fail" ||
		fail "a checker twelve times as costly stays within the four-line budget (${costly_ms}ms) — the bound proves nothing"
	;;
esac

# ---------------------------------------------------------------------------
banner "Every call site hands the checker lifted lines, never a body (#337)"
# ---------------------------------------------------------------------------
# The checker's cost is per line that carries a colon, and linear: one check
# of 3 such lines costs about 0.15 CPU-seconds, of 100 about 1.5, of 2,000
# between 7 (keys no policy declares) and 32 (every line a declared field).
# That last number is never paid, because no caller hands it a body: each
# lifts the lines it owes before the check. This section holds the kit's
# callers to that. Every invocation of the checker in a shipped file is found
# — `sh` on scripts/vocab.sh, on "$checker", on "$vocab" — and must be one of:
#   - `fields`, which reads no input;
#   - a prose mention of the command, closed by a backtick;
#   - the argument form with the caller's own placeholder tokens,
#     'Field: <token>', which nothing untrusted fills;
#   - the argument form with one positional token, "Field: $2" — one
#     argument, one line, the token the caller stamped itself;
#   - or a site in LIFTED below: the input it reads (a fixed string on the
#     call's line or the one before it — a pipe's head) and the lift stage
#     that bounds that input, a fixed string earlier in the same function.
# A new call site, a site whose input changed, or a site whose lift stage was
# removed is named and fails — the baits below prove each of the three.
#
# stamp.sh lifts by KEY, not by count: a body carrying 2,000 `Tier:` lines
# would hand over 2,000. That is a degenerate ticket, not a body handed whole,
# and it is the one unbounded input this inventory admits.
LIFTED=$(
	cat <<'EOLIFT'
scripts/stamp.sh@@-@@<"$_stamp_tmp/lines"@@grep -iE '^[[:space:]]*(tier|confidence|domain)[[:space:]]*:'
scripts/stamp.sh@@-@@printf '%s\n' "$line" | sh "$vocab"@@grep -iE '^[[:space:]]*(tier|confidence|domain)[[:space:]]*:'
.agents/skills/pr-iterate/SKILL.md@@typed_return_ok@@printf 'Author-kind: %s\n%s\n' "$1" "$3" |@@[ "$(printf '%s\n' "$3" | grep -c '')" -eq 3 ] || return 1
.agents/skills/to-tickets/SKILL.md@@prescreen_ok@@sh "$checker" <"$2"@@[ "$(grep -c '' "$2" 2>/dev/null)" = 2 ] || return 1
.agents/skills/dogfood/SKILL.md@@prescreen_ok@@sh "$checker" <"$2"@@[ "$(grep -c '' "$2" 2>/dev/null)" = 2 ] || return 1
EOLIFT
)

# checker_calls <root> — one record per invocation of the checker in the
# shipped files under <root> that is not exempt above:
# <file>\t<line>\t<function's first line>\t<function>\t<line before> <line>
CALLS_AWK=$(
	cat <<'EOAWK'
FNR == 1 { fn = "-"; start = 1; prev = "" }
/^[ \t]*#/ { prev = $0; next }
/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ {
	fn = $1; sub(/\(\).*/, "", fn); start = FNR
	one = ($0 ~ /\}[ \t]*$/)
}
{
	s = $0
	while (match(s, /(^|[ \t(|`;&])sh ("[^"]*vocab\.sh"|[^ "`]*vocab\.sh|"\$checker"|"\$vocab")/)) {
		tail = substr(s, RSTART + RLENGTH); s = tail
		if (tail ~ /^`/ || tail ~ /^ fields/) continue
		if (tail ~ /^( '<?[A-Za-z-]+>?: <[^>']*>')+( …)?($|[`.,;)])/) continue
		if (tail ~ /^ "[A-Za-z-]+: \$[0-9]"([ \t]|$)/) continue
		printf "%s\t%d\t%d\t%s\t%s %s\n", FILENAME, FNR, start, fn, prev, $0
	}
	prev = $0
}
/^}/ || one { fn = "-"; start = 1; one = 0 }
EOAWK
)
checker_calls() (
	cd "$1" || exit 2
	find scripts .agents/skills .githooks adapters constitution templates -type f \
		\( -name '*.sh' -o -name '*.md' -o -name '*.template' -o -name 'pre-*' \) \
		! -path scripts/vocab.sh 2>/dev/null | sort | xargs awk "$CALLS_AWK"
)

# unlifted <root> — every call record no LIFTED entry accounts for, one per
# line; nothing when every site lifts.
unlifted() {
	checker_calls "$1" | while IFS="$(printf '\t')" read -r file line start fn text; do
		ok=0
		while IFS= read -r entry; do
			e_file=${entry%%@@*} rest=${entry#*@@}
			e_fn=${rest%%@@*} rest=${rest#*@@}
			e_input=${rest%%@@*} e_guard=${rest#*@@}
			[ "$e_file" = "$file" ] && [ "$e_fn" = "$fn" ] || continue
			case $text in *"$e_input"*) ;; *) continue ;; esac
			sed -n "${start},$((line - 1))p" "$1/$file" | grep -qF -- "$e_guard" || continue
			ok=1 && break
		done <<EOENTRIES
$LIFTED
EOENTRIES
		[ "$ok" = 1 ] || printf '%s:%s (%s)\n' "$file" "$line" "$fn"
	done
}

calls=$(checker_calls "$KIT" | grep -c '')
[ "$calls" -ge 5 ] && pass "the audit finds the kit's $calls checker calls that read input" ||
	fail "the audit finds $calls checker calls that read input — fewer than the five lifted sites; it has gone blind"
bad=$(unlifted "$KIT")
[ -z "$bad" ] && pass "every checker call in a shipped file reads lifted lines — none hands a body" ||
	fail "a checker call reads input no lift stage bounds: $(printf '%s' "$bad" | tr '\n' ' ')"

# The baits: a copy of the call sites, each broken one way, must be named.
BAIT="$SCRATCH/lift-bait"
bait_reset() {
	rm -rf "$BAIT"
	for f in scripts/stamp.sh .agents/skills/pr-iterate/SKILL.md .agents/skills/to-tickets/SKILL.md \
		.agents/skills/dogfood/SKILL.md; do
		mkdir -p "$BAIT/$(dirname "$f")" && cp "$KIT/$f" "$BAIT/$f"
	done
}
# bait_named <file> <what was broken> — the audit names a site in <file>.
bait_named() {
	case $(unlifted "$BAIT") in
	*"$1:"*) pass "the audit names $1 when $2" ;;
	*) fail "the audit stays quiet when $2 in $1" ;;
	esac
}
# bait_edit <file> <sed script> — break one site in the copy, portably.
bait_edit() { sed "$2" "$BAIT/$1" >"$BAIT/edit" && mv "$BAIT/edit" "$BAIT/$1"; }
bait_reset
[ -z "$(unlifted "$BAIT")" ] && pass "the unbroken copy of the call sites is clean" ||
	fail "the unbroken copy of the call sites is named: $(unlifted "$BAIT")"
bait_edit .agents/skills/pr-iterate/SKILL.md "/grep -c '')\" -eq 3 \] || return 1/d"
bait_named .agents/skills/pr-iterate/SKILL.md "the typed return's line count is removed"
bait_reset
bait_edit scripts/stamp.sh 's|sh "$vocab" <"$_stamp_tmp/lines"|sh "$vocab" <"$_stamp_tmp/body"|'
bait_named scripts/stamp.sh "the fetched body is handed over in place of the lifted lines"
bait_reset
bait_edit .agents/skills/dogfood/SKILL.md 's|sh "$checker" <"$2"|sh "$checker" <"$1"|'
bait_named .agents/skills/dogfood/SKILL.md "the pre-screen checks the output it screened instead of the return"
bait_reset
printf '\tsh scripts/vocab.sh <"$body"\n' >>"$BAIT/.agents/skills/to-tickets/SKILL.md"
bait_named .agents/skills/to-tickets/SKILL.md "a new call site hands a body"

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
banner "Bare lines — a markdown-wrapped line is not a decision line"
# ---------------------------------------------------------------------------
# Review of PR #289 (M-4): a decision line wearing markdown — a list marker,
# emphasis — is silently unrecognized. Resolved as the contract already read
# (PRD #273: "the calling skill hands it the lines"), and said where a caller
# meets it: the usage text and the header, in so many words. The behavior is
# pinned beside the words, so the day the checker learns to read through
# markup the sentence that says it does not goes red with it.
vocab fieldz
s_assert_err_has "the caller hands it bare \`Field: value\` lines" "the usage text says what the caller hands over"
s_assert_err_has "a markdown-wrapped line" "…and names the line it does not read"
s_assert_err_has "is not a decision line to it" "…in those words"
assert_file_has "$VOCAB" "The caller hands it BARE \`Field: value\` lines" "the header says it too"
assert_file_has "$VOCAB" "is not a decision line to" "the header says it too"
printf '%s\n' '- Tier: Implementor' >"$SCRATCH/listed"
t_run_split sh "$VOCAB" <"$SCRATCH/listed"
s_assert_resolved "" "a list-marked line on stdin is ignored, not checked — its key is '- Tier', no declared field"
vocab '**Tier:** Implementor'
s_assert_resolved "" "an emphasized line is ignored, not checked"
vocab check '- Tier: Implementor' 'Tier: Implementor'
s_assert_status 2 "the same line handed over bare is refused — lifting it out is the caller's job"
s_assert_err_has "tier: 'Implementor' is not one of"

# A declared field is a word every body handed over is now read for, so it
# must be a word no ordinary body uses as a key. `Author:` is one a ticket, a
# commit trailer or a forge's own issue header carries — declared as a field,
# a whole body piped in went from exit 0 to exit 2 on its author's name
# (review of PR #318). The field is `author-kind`, and `Author:` is prose.
printf 'Author: Arthur\n' >"$SCRATCH/authored"
t_run_split sh "$VOCAB" <"$SCRATCH/authored"
s_assert_resolved "" "a plain 'Author: <name>' line in a body is not a decision line"
vocab 'Author-kind: maintainer'
s_assert_status 2 "'Author-kind: maintainer' — a kind nobody declared — is refused"
s_assert_err_has "author-kind: 'maintainer' is not one of bot human"

# ---------------------------------------------------------------------------
banner "Where the vocabularies come from"
# ---------------------------------------------------------------------------
# A policy file a project wrote: a narrower severity scale, a field of its own,
# and the domain kept open.
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
t_write "$SCRATCH" own.config.sh "$CONFIG_OWN"

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

# The file is the WHOLE policy: the built-in words stand in only when no
# file is found, never underneath one. A file that declares no rule enforces
# none, a field it does not declare is not a decision line, and an empty
# file declares nothing — refused as such, not quietly held to the kit's words.
t_write "$SCRATCH" norules.config.sh "VOCAB_FIELDS='action command-shaped'
VOCAB_ACTION='apply reply escalate'
VOCAB_COMMAND_SHAPED='yes no'"
VOCAB_CONFIG="$SCRATCH/norules.config.sh"
vocab 'Command shaped: yes' 'Action: apply'
s_assert_resolved "" "a policy file with no VOCAB_RULES line enforces no rule — the shipped rule is not sourced beneath it"
vocab fields
s_assert_out_is "action: apply reply escalate
command-shaped: yes no" "'fields' prints the file's two fields and no rule — nothing of the defaults leaks through"
: >"$SCRATCH/empty.config.sh"
VOCAB_CONFIG="$SCRATCH/empty.config.sh"
vocab 'Tier: planner'
s_assert_status 2 "an EMPTY policy file declares no field, and is refused as such rather than falling back to the shipped words"
s_assert_err_has "policy: VOCAB_FIELDS declares no field"

VOCAB_CONFIG="$SCRATCH/absent.config.sh"
vocab 'Tier: planner'
s_assert_status 2 "a policy file named explicitly and missing is exit 2"
s_assert_err_has "does not exist"
unset VOCAB_CONFIG

# A slash-less name is the cwd's file — the one the existence check saw —
# and never a same-named file on $PATH, which is where `.` would otherwise
# look first.
mkdir -p "$SCRATCH/cwd" "$SCRATCH/onpath"
t_write "$SCRATCH/cwd" decoy.config.sh "$CONFIG_OWN"
t_write "$SCRATCH/onpath" decoy.config.sh "echo DECOY-FROM-PATH >&2
VOCAB_FIELDS='tier'
VOCAB_TIER='planner'"
_run_cwd_body() { cd "$SCRATCH/cwd" && PATH="$SCRATCH/onpath:$PATH" VOCAB_CONFIG=decoy.config.sh sh "$VOCAB" fields; }
t_run_split _run_cwd_body
s_assert_status 0 "a slash-less VOCAB_CONFIG loads"
s_assert_out_has "mood: calm brisk" "…the cwd's file, the one the existence check saw"
s_assert_err_lacks "DECOY-FROM-PATH"

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
t_write "$OWN_REPO" scripts/vocab.config.sh "$CONFIG_OWN"
run_from "$OWN_REPO" "$OWN_REPO/tools/vocab.sh" 'Severity: advisory'
s_assert_resolved "" "the script's own repo root supplies scripts/vocab.config.sh with no env var set"

t_repo
FOREIGN=$REPO
t_write "$FOREIGN" scripts/vocab.config.sh "$(
	cat <<'EOFC'
echo "FOREIGN-CONFIG-EXECUTED" >&2
VOCAB_FIELDS='severity'
VOCAB_SEVERITY='foreign'
EOFC
)"
run_from "$FOREIGN" "$OWN_REPO/tools/vocab.sh" 'Severity: advisory'
s_assert_resolved "" "the script's own repo supplies the vocabularies, not the repo the caller stands in"
s_assert_err_lacks "FOREIGN-CONFIG-EXECUTED"
# …nor the repo an inherited GIT_DIR points at: git exports it into hooks,
# and .githooks/pre-push is a real caller. The script unsets both before it
# asks git where it lives.
t_run_split env GIT_DIR="$FOREIGN/.git" GIT_WORK_TREE="$FOREIGN" sh "$OWN_REPO/tools/vocab.sh" 'Severity: advisory'
s_assert_resolved "" "an inherited GIT_DIR/GIT_WORK_TREE aimed at the foreign clone does not redirect discovery"
s_assert_err_lacks "FOREIGN-CONFIG-EXECUTED"

LOOSE="$SCRATCH/loose"
install_vocab "$LOOSE"
t_write "$LOOSE" vocab.config.sh "$CONFIG_OWN"
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

# ---------------------------------------------------------------------------
banner "A cross-field rule refuses the forbidden pair and accepts the others"
# ---------------------------------------------------------------------------
# The shipped rule: a command-shaped body never triages as apply. An
# implication between two field-value pairs, data in the policy file, refused
# by a script rather than remembered by an agent.
unset VOCAB_CONFIG
vocab 'Command shaped: yes' 'Action: apply'
s_assert_status 2 "command-shaped=yes with action=apply is refused"
s_assert_err_has "action: 'apply' is refused by the rule command-shaped=yes => action!=apply"
vocab 'Command shaped: yes' 'Action: escalate'
s_assert_resolved "" "command-shaped=yes with action=escalate is accepted"
vocab 'Command shaped: no' 'Action: apply'
s_assert_resolved "" "command-shaped=no with action=apply is accepted — the antecedent does not hold"
vocab 'Action: apply'
s_assert_resolved "" "action=apply alone is accepted — the rule constrains a pair, not a field"
vocab 'Command shaped: yes'
s_assert_resolved "" "command-shaped=yes alone is accepted — the consequent's field is absent"

# A field that appears twice with two different values has no single value:
# refused, whichever line comes last — so appending one line to an untrusted
# body cannot talk a firing rule out of firing.
vocab 'Command shaped: yes' 'Action: apply' 'Command shaped: no'
s_assert_status 2 "a later line cannot withdraw the antecedent — the repeat is refused"
s_assert_err_has "command-shaped: 'no' repeats the field, which already read 'yes'"
vocab 'Command shaped: yes' 'Action: apply' 'Action: reply'
s_assert_status 2 "…nor replace the consequent's value"
s_assert_err_has "action: 'reply' repeats the field, which already read 'apply'"
s_assert_err_has "action: 'apply' is refused by the rule command-shaped=yes => action!=apply"

# The other direction of an implication: `=>` with `=`.
CONFIG_RULES=$(
	cat <<'EOFC'
VOCAB_FIELDS='tier label kind'
VOCAB_OPEN=''
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_LABEL='ready-for-agent none'
VOCAB_KIND='spike build'
VOCAB_RULES='kind=spike => tier=planner
tier=mechanical => label=ready-for-agent'
EOFC
)
RULES="$SCRATCH/rules.config.sh"
t_write "$SCRATCH" rules.config.sh "$CONFIG_RULES"
VOCAB_CONFIG=$RULES
export VOCAB_CONFIG
vocab 'Kind: spike' 'Tier: planner'
s_assert_resolved "" "a rule demanding a value accepts that value"
vocab 'Kind: spike' 'Tier: implementer'
s_assert_status 2 "…and refuses another"
s_assert_err_has "tier: 'implementer' is refused by the rule kind=spike => tier=planner"
vocab 'Kind: build' 'Tier: implementer'
s_assert_resolved "" "the antecedent not holding, the rule is silent"
vocab fields
s_assert_out_has "rule: kind=spike => tier=planner" "'fields' prints each rule after the fields"

# ---------------------------------------------------------------------------
banner "A rule set no combination can satisfy is a POLICY CONTRADICTION"
# ---------------------------------------------------------------------------
# Distinct from a bad value: the value is fine, the policy is wrong, and the
# reason says so in those words so the operator fixes the file and not the
# ticket.
CONFIG_CONTRA=$(
	cat <<'EOFC'
VOCAB_FIELDS='tier label'
VOCAB_OPEN=''
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_LABEL='ready-for-agent none'
VOCAB_RULES='tier=planner => label=none
tier=planner => label!=none'
EOFC
)
CONTRA="$SCRATCH/contra.config.sh"
t_write "$SCRATCH" contra.config.sh "$CONFIG_CONTRA"
VOCAB_CONFIG=$CONTRA
vocab 'Tier: planner' 'Label: none'
s_assert_status 2 "two rules on one antecedent that cannot both hold are exit 2"
s_assert_err_has "policy contradiction"
s_assert_err_has "tier=planner => label=none"
s_assert_err_has "tier=planner => label!=none"
s_assert_err_lacks "is not one of"
vocab fields
s_assert_status 2 "'fields' reports the contradiction too — the file is wrong before any value arrives"
s_assert_err_has "policy contradiction"

# Two antecedents that hold together, demanding two different values of one
# closed field: satisfiable rule by rule, unsatisfiable for these inputs.
CONFIG_CONTRA2=$(
	cat <<'EOFC'
VOCAB_FIELDS='tier label kind'
VOCAB_OPEN=''
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_LABEL='ready-for-agent none'
VOCAB_KIND='spike build'
VOCAB_RULES='kind=spike => label=none
tier=mechanical => label=ready-for-agent'
EOFC
)
CONTRA2="$SCRATCH/contra2.config.sh"
t_write "$SCRATCH" contra2.config.sh "$CONFIG_CONTRA2"
VOCAB_CONFIG=$CONTRA2
vocab fields
s_assert_status 0 "rule by rule the set is fine — 'fields' is green"
vocab 'Kind: spike' 'Tier: mechanical' 'Label: none'
s_assert_status 2 "a mechanical spike has no legal label — a contradiction for these inputs"
s_assert_err_has "policy contradiction: 'kind=spike => label=none' and 'tier=mechanical => label=ready-for-agent' cannot both hold"
# With the label not given at all, no ordinary rule check can speak — the
# check-time contradiction pass is the one thing that does.
vocab 'Kind: spike' 'Tier: mechanical'
s_assert_status 2 "…and with no label given, the contradiction is the one reason — the ordinary rule check is silent"
s_assert_err_has "policy contradiction: 'kind=spike => label=none' and 'tier=mechanical => label=ready-for-agent' cannot both hold"
s_assert_err_lacks "is refused by the rule"
vocab 'Kind: build' 'Tier: mechanical' 'Label: ready-for-agent'
s_assert_resolved "" "a build on the mechanical tier is fine — only one rule fires"

# A `!=` for every token of a closed field leaves nothing to choose.
CONFIG_CONTRA3=$(
	cat <<'EOFC'
VOCAB_FIELDS='kind label'
VOCAB_OPEN=''
VOCAB_KIND='spike build'
VOCAB_LABEL='ready-for-agent none'
VOCAB_RULES='kind=spike => label!=none
kind=spike => label!=ready-for-agent'
EOFC
)
CONTRA3="$SCRATCH/contra3.config.sh"
t_write "$SCRATCH" contra3.config.sh "$CONFIG_CONTRA3"
VOCAB_CONFIG=$CONTRA3
vocab 'Kind: spike'
s_assert_status 2 "rules excluding every token of a field are a contradiction"
s_assert_err_has "policy contradiction: the rules on label exclude every one of its tokens"

# ---------------------------------------------------------------------------
banner "The policy file is held to the same rules as a value — at load"
# ---------------------------------------------------------------------------
# A rule naming a field or a token the file does not declare, a token outside
# the shape: each is a policy error, not a bad value.
CONFIG_BADRULE=$(
	cat <<'EOFC'
VOCAB_FIELDS='tier'
VOCAB_OPEN=''
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_RULES='tier=planner => label=none'
EOFC
)
t_write "$SCRATCH" badrule.config.sh "$CONFIG_BADRULE"
VOCAB_CONFIG="$SCRATCH/badrule.config.sh"
vocab 'Tier: planner'
s_assert_status 2 "a rule naming an undeclared field is a policy error"
s_assert_err_has "policy: rule 'tier=planner => label=none' names 'label', which is not a declared field"

CONFIG_BADTOK=$(
	cat <<'EOFC'
VOCAB_FIELDS='tier'
VOCAB_OPEN=''
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_RULES='tier=senior => tier!=planner'
EOFC
)
t_write "$SCRATCH" badtok.config.sh "$CONFIG_BADTOK"
VOCAB_CONFIG="$SCRATCH/badtok.config.sh"
vocab 'Tier: planner'
s_assert_status 2 "a rule naming a token outside its field's vocabulary is a policy error"
s_assert_err_has "policy: rule 'tier=senior => tier!=planner' names 'senior', which tier does not declare"

CONFIG_BADSHAPE=$(
	cat <<'EOFC'
VOCAB_FIELDS='severity'
VOCAB_OPEN=''
VOCAB_SEVERITY='Critical High'
VOCAB_RULES=''
EOFC
)
t_write "$SCRATCH" badshape.config.sh "$CONFIG_BADSHAPE"
VOCAB_CONFIG="$SCRATCH/badshape.config.sh"
vocab 'Severity: Critical'
s_assert_status 2 "a token outside the shape IN THE POLICY FILE is a policy error"
s_assert_err_has "policy: severity token 'Critical' is not a well-formed token"

CONFIG_NOTOK=$(
	cat <<'EOFC'
VOCAB_FIELDS='severity mood'
VOCAB_OPEN=''
VOCAB_SEVERITY='high low'
VOCAB_RULES=''
EOFC
)
t_write "$SCRATCH" notok.config.sh "$CONFIG_NOTOK"
VOCAB_CONFIG="$SCRATCH/notok.config.sh"
vocab 'Severity: high'
s_assert_status 2 "a declared closed field with no tokens is a policy error"
s_assert_err_has "policy: field 'mood' declares no tokens"

# A malformed rule is a policy error, never a rule quietly ignored — `fields`
# would print nothing for it, and nothing else would say.
t_write "$SCRATCH" malformed.config.sh "VOCAB_FIELDS='tier label'
VOCAB_OPEN=''
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_LABEL='ready-for-agent none'
VOCAB_RULES='tier planner => label=none'"
VOCAB_CONFIG="$SCRATCH/malformed.config.sh"
vocab 'Tier: planner'
s_assert_status 2 "a rule with no '=' on its left is malformed — a policy error"
s_assert_err_has "policy: rule 'tier planner => label=none' is malformed"
t_write "$SCRATCH" malformed2.config.sh "VOCAB_FIELDS='tier'
VOCAB_OPEN=''
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_RULES='tier=planner'"
VOCAB_CONFIG="$SCRATCH/malformed2.config.sh"
vocab fields
s_assert_status 2 "a rule with no '=>' is malformed too, and 'fields' says so before any value arrives"
s_assert_err_has "policy: rule 'tier=planner' is malformed"

# A field may not take one of the checker's own names: `fields` would make
# the field list its own vocabulary, and nothing would say so.
for reserved in fields open rules token-shape config; do
	t_write "$SCRATCH" reserved.config.sh "VOCAB_FIELDS='tier $reserved'
VOCAB_OPEN=''
VOCAB_TIER='planner'
VOCAB_RULES=''"
	VOCAB_CONFIG="$SCRATCH/reserved.config.sh"
	vocab fields
	s_assert_status 2 "a field named '$reserved' is refused at load — the name is the checker's own"
	s_assert_err_has "policy: field name '$reserved' is reserved"
done

# A FIELD NAME is held to the shape as a token is.
t_write "$SCRATCH" badfield.config.sh "VOCAB_FIELDS='Tier'
VOCAB_OPEN=''
VOCAB_TIER='planner'
VOCAB_RULES=''"
VOCAB_CONFIG="$SCRATCH/badfield.config.sh"
vocab 'Tier: planner'
s_assert_status 2 "a field name outside the shape is a policy error"
s_assert_err_has "policy: field name 'Tier' is not a well-formed token"

# A rule may name an OPEN field, whose values have only the shape to meet.
t_write "$SCRATCH" openrule.config.sh "VOCAB_FIELDS='domain tier'
VOCAB_OPEN='domain'
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_RULES='domain=Content => tier=planner'"
VOCAB_CONFIG="$SCRATCH/openrule.config.sh"
vocab 'Tier: planner'
s_assert_status 2 "a rule naming an out-of-shape value on an open field is a policy error"
s_assert_err_has "policy: rule 'domain=Content => tier=planner' names 'Content', which is not a well-formed token"
t_write "$SCRATCH" openrule2.config.sh "VOCAB_FIELDS='domain tier'
VOCAB_OPEN='domain'
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_RULES='domain=content => tier=planner'"
VOCAB_CONFIG="$SCRATCH/openrule2.config.sh"
vocab 'Domain: content' 'Tier: implementer'
s_assert_status 2 "…and a well-formed one fires like any other rule"
s_assert_err_has "tier: 'implementer' is refused by the rule domain=content => tier=planner"

# ---------------------------------------------------------------------------
banner "The NEUTRAL-NAME rule — no token carries its answer in its spelling"
# ---------------------------------------------------------------------------
# A judge, model or agent, reads the label as evidence: shown `safe-to-apply`
# and `risky` it follows the word instead of the state. The checker refuses
# such a token at load, so the rule is a script's refusal and not a reviewer's
# taste.
CONFIG_LEADING=$(
	cat <<'EOFC'
VOCAB_FIELDS='action'
VOCAB_OPEN=''
VOCAB_ACTION='safe-to-apply risky'
VOCAB_RULES=''
EOFC
)
t_write "$SCRATCH" leading.config.sh "$CONFIG_LEADING"
VOCAB_CONFIG="$SCRATCH/leading.config.sh"
vocab 'Action: risky'
s_assert_status 2 "a vocabulary whose tokens carry their answer is refused"
s_assert_err_has "policy: action token 'safe-to-apply' carries its answer in its spelling ('safe')"
s_assert_err_has "policy: action token 'risky' carries its answer in its spelling ('risky')"
s_assert_err_has "neutral"

# The rule walks EVERY hyphen-separated word, not only the first: the answer
# hides as readily at the end of a token.
t_write "$SCRATCH" leading2.config.sh "VOCAB_FIELDS='action'
VOCAB_OPEN=''
VOCAB_ACTION='apply mostly-risky'
VOCAB_RULES=''"
VOCAB_CONFIG="$SCRATCH/leading2.config.sh"
vocab 'Action: apply'
s_assert_status 2 "a token whose offending word is not its first is refused too"
s_assert_err_has "policy: action token 'mostly-risky' carries its answer in its spelling ('risky')"

# The deny list is the CHECKER'S, not the policy file's: a file that
# reassigns it — or empties it — has not switched the rule off.
t_write "$SCRATCH" off.config.sh "VOCAB_LEADING_WORDS=''
VOCAB_FIELDS='action'
VOCAB_OPEN=''
VOCAB_ACTION='safe-to-apply risky'
VOCAB_RULES=''"
VOCAB_CONFIG="$SCRATCH/off.config.sh"
vocab 'Action: risky'
s_assert_status 2 "a policy file cannot switch the neutral-name rule off by emptying the word list"
s_assert_err_has "policy: action token 'safe-to-apply' carries its answer in its spelling ('safe')"

CONFIG_NEUTRAL=$(
	cat <<'EOFC'
VOCAB_FIELDS='action'
VOCAB_OPEN=''
VOCAB_ACTION='apply escalate'
VOCAB_RULES=''
EOFC
)
t_write "$SCRATCH" neutral.config.sh "$CONFIG_NEUTRAL"
VOCAB_CONFIG="$SCRATCH/neutral.config.sh"
vocab 'Action: escalate'
s_assert_resolved "" "the neutral pair — apply, escalate — passes"
unset VOCAB_CONFIG

# ---------------------------------------------------------------------------
banner "The tier is READ here and never WIDENED — the resolver owns it"
# ---------------------------------------------------------------------------
# PRD scenario 10: a consumer adds a fifth tier to the vocabulary policy
# file. The checker accepts it, because the file is theirs; the resolver,
# which owns the tier vocabulary, refuses it with exit 2 exactly as before —
# so the one place a tier is widened is the manual layer, and the policy
# file's header says so.
CONFIG_FIFTH=$(
	cat <<'EOFC'
VOCAB_FIELDS='tier'
VOCAB_OPEN=''
VOCAB_TIER='planner implementer mechanical reviewer senior'
VOCAB_RULES=''
EOFC
)
t_write "$SCRATCH" fifth.config.sh "$CONFIG_FIFTH"
VOCAB_CONFIG="$SCRATCH/fifth.config.sh"
export VOCAB_CONFIG
vocab 'Tier: senior'
s_assert_resolved "" "the checker accepts a fifth tier the policy file declares — the file is the consumer's"
unset VOCAB_CONFIG
printf '%s\n' "AGENT_TIER_PLANNER='m'" >"$SCRATCH/agents.config.sh"
AGENTS_CONFIG="$SCRATCH/agents.config.sh" t_run_split sh "$KIT/scripts/agents.lib.sh" senior
s_assert_status 2 "the resolver still refuses it — the tier vocabulary is closed where it is owned"
s_assert_err_has "unknown capability tier 'senior'"
assert_file_has "$KIT/scripts/vocab.config.sh" "owned by" "the shipped policy file says who owns each field"

t_done "vocab"
