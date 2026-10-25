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
vocab() { t_exec sh "$VOCAB" "$@"; }

# ---------------------------------------------------------------------------
banner "The demo — PRD scenario 1: a misspelled tier is refused before the quiz"
# ---------------------------------------------------------------------------
# The one judgment that already had a closed vocabulary was the tier, and only
# at the resolver — a ticket body saying `Tier: Implementor` passed every
# check until /implement read it. The checker refuses it where it is written,
# names the field, the value and the vocabulary, and exits 2.
unset VOCAB_CONFIG
vocab 'Tier: Implementor'
expect_status 2 "'Tier: Implementor' is refused with exit 2"
expect_err_has "tier: 'Implementor' is not one of planner implementer mechanical reviewer"
[ -z "$T_OUT" ] && pass "stdout carries nothing — the reasons are diagnostics, on stderr" ||
	fail "stdout should be empty, got '$T_OUT'"

vocab 'Tier: implementer'
expect_resolved "" "'Tier: implementer' is accepted with exit 0 and no output"

# ---------------------------------------------------------------------------
banner "Every shipped vocabulary accepts its own tokens, in the shipped words"
# ---------------------------------------------------------------------------
# The shipped policy file and the script's built-in defaults are held equal by
# tests/vocab-policy.test.sh; here the question is only that each token the
# script SAYS it accepts, it accepts — read back through `fields`, so the
# list this loop walks is the script's own answer and not a copy.
vocab fields
expect_status 0 "'fields' prints the effective vocabularies"
expect_out_has "tier: planner implementer mechanical reviewer" "the tier's four names, in the manual's order"
expect_out_has "domain (open):" "the task domain is marked OPEN — membership is not enforced on it"
# One pass, from a file rather than a pipeline so a failure reaches
# $failures, with the `rule:` lines left out — a rule is not a field.
printf '%s\n' "$T_OUT" | grep -v '^rule: ' | sed 's/ (open)//' >"$SCRATCH/fields"
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
expect_status 2 "'Severity: Medium-High' — a band nobody declared — is exit 2"
expect_err_has "severity: 'Medium-High' is not one of critical high medium low"

vocab 'Tier: senior'
expect_status 2 "'Tier: senior' — an invented tier — is exit 2"
expect_err_has "tier: 'senior' is not one of"

vocab 'Tier:'
expect_status 2 "'Tier:' with no value is exit 2"
expect_err_has "tier: the value is empty"

vocab 'Confidence:    '
expect_status 2 "a value that is only blanks is empty too"
expect_err_has "confidence: the value is empty"

# The task domain is OPEN — an undeclared token is local policy, never an
# error (the resolver falls back to the tier in silence) — but its SHAPE is
# not: the token is interpolated into a variable name.
vocab 'Domain: judge'
expect_resolved "" "an undeclared domain token of the right shape is accepted — the domain is open"
vocab 'Domain: Content'
expect_status 2 "a domain token outside the shape is exit 2"
expect_err_has "domain: 'Content' is not a well-formed token"
expect_err_has "[a-z][a-z0-9-]*"
vocab 'Domain: html report'
expect_status 2 "a domain token with a space is exit 2"

# A value that is SEVERAL tokens at once is no member: `Tier: planner
# implementer` is an agent echoing the vocabulary instead of choosing from
# it, and `Action: apply reply` would carry `apply` past the shipped rule's
# `!=` — a contiguous run of the list is still not one of its tokens.
vocab 'Tier: planner implementer'
expect_status 2 "a value made of two tokens is exit 2 — a closed field takes one"
expect_err_has "tier: 'planner implementer' is not one of planner implementer mechanical reviewer"
vocab 'Command shaped: yes' 'Action: apply reply'
expect_status 2 "…so two tokens cannot smuggle 'apply' past the shipped rule"
expect_err_has "action: 'apply reply' is not one of apply reply escalate"

# Several violations, several reasons — one line each, all of them.
vocab 'Tier: senior' 'Label: hitl' 'Severity: critical'
expect_status 2 "two bad values in one call are exit 2"
expect_err_has "tier: 'senior'"
expect_err_has "label: 'hitl'"
expect_err_lacks "severity:"

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
t_exec sh "$VOCAB" <"$BODY"
expect_resolved "" "a whole ticket body on stdin checks clean — prose lines with colons are not decisions"
sed 's/^Tier: planner$/tier: Implementor/' "$BODY" >"$SCRATCH/bad.body"
t_exec sh "$VOCAB" <"$SCRATCH/bad.body"
expect_status 2 "the same body with a misspelled tier is exit 2 on stdin"
expect_err_has "tier: 'Implementor'"
t_exec sh "$VOCAB" check <"$SCRATCH/bad.body"
expect_status 2 "'check' spelled out reads stdin the same way"
printf 'Tier: Implementor' >"$SCRATCH/nonl"
t_exec sh "$VOCAB" <"$SCRATCH/nonl"
expect_status 2 "a last line with no trailing newline is still read — refused, so the read is proved"
expect_err_has "tier: 'Implementor'"
t_exec sh "$VOCAB" </dev/null
expect_resolved "" "empty stdin — a body with no decision line in it yet — is legal"

# The field name is matched without regard to case or separator; the value
# exactly.
vocab 'TIER: mechanical'
expect_resolved "" "the field name is case-insensitive"
vocab 'Tier: planner' 'tier: planner'
expect_resolved "" "a field repeated with the same value is one answer"
vocab 'Command shaped: yes' 'command_shaped: no'
expect_status 2 "spaces and underscores in a field name read as hyphens — the two spellings are one field, and it now has two values"
expect_err_has "command-shaped: 'no' repeats the field, which already read 'yes'"
vocab 'Tier: MECHANICAL'
expect_status 2 "the value is not case-folded — a token is spelled one way"

# A body that carries no decision line at all is legal: nothing to refuse.
vocab check 'just prose'
expect_resolved "" "a line with no colon is ignored"
vocab 'Blocked by: #12'
expect_resolved "" "a line whose key is not a declared field is ignored"
# …but a FIRST argument with no colon is not a line at all: it is a
# subcommand nobody declared, and a silent exit 0 on `fieldz` would be a
# pass a caller never earned.
vocab fieldz
expect_status 2 "a first argument that is neither a subcommand nor a 'Field: value' line is a usage error"
expect_err_has "usage"

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
five_checks() { for _ in 1 2 3 4 5; do sh "$1" <"$2"; done; }
five_checks_ms() { t_cpu_ms five_checks "$1" "$2"; }
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
RETURN4_MS=2000 # five checks of the four lines; the bait below must break it
within_budget "$VOCAB" "$RETURN4" "$RETURN4_MS" "a typed return's four lines"
# The bait: a checker that does twelve times the work fails that budget —
# the bound can go red, so its green says something. It is the only bait:
# the body's bound shares its measurement, five_checks_ms, and has none.
cat >"$SCRATCH/costly.vocab.sh" <<EOCOSTLY
in=\$(mktemp) && cat >"\$in"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do sh "$VOCAB" <"\$in"; done
rm -f "\$in"
EOCOSTLY
costly_ms=$(five_checks_ms "$SCRATCH/costly.vocab.sh" "$RETURN4")
case $costly_ms in
*[!0-9]* | "") fail "the costly bait went unmeasured ('$costly_ms')" ;;
*)
	[ "$costly_ms" -gt "$RETURN4_MS" ] &&
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
# — `sh` or `bash`, after any single-dash options (`sh -e`), on a word ending
# in vocab.sh (quoted, bare, or a quoted prefix: "$ROOT"/scripts/vocab.sh) or
# on $checker or $vocab (quoted or bare, braced or not), however spaced, a
# backslash-continued line read as one. Those forms and no others: a call
# through `.` or `source`, a shell named by its path (`/bin/sh`), as `dash`
# or by a variable, an option that takes an argument (`sh -o errexit`), or
# `env`, `exec` or `xargs` running the checker with no `sh` before it is not
# found. Each one found must be one of (each exemption tagged in the audit,
# and baited below):
#   - `fields`, which reads no input;
#   - a prose mention of the command, closed by a backtick, in Markdown;
#   - the argument form with the caller's own placeholder tokens,
#     'Field: <token>', which nothing untrusted fills;
#   - the argument form with one positional token, "Field: $2" — one
#     argument, one line, the token the caller stamped itself;
#   - or a site in LIFTED below: the input it reads, spelled with the call
#     itself so nothing can stand between them (a fixed string in the
#     call's own command — its line cut at `;`, `&&`, `||` and a lone `&`,
#     joined to the head of a pipe the line before ends with), and the lift
#     stage that bounds that input, a fixed string on an uncommented line
#     earlier in the same function.
# A new call site, a site whose input changed, or a site whose lift stage was
# removed is named and fails — the baits below prove each of the three. So is
# an entry no call matches: the inventory holds no more than the tree.
#
# stamp.sh lifts by KEY and bounds the count: at most the policy's bound of
# one key (8, 32 for Test-tier:; 8 when it publishes none) reach the checker,
# and a body with more is its exit 5, nothing checked (#400, #869) — so
# its lift is bounded like every other site here.
LIFTED=$(
	cat <<'EOLIFT'
scripts/stamp.sh@@-@@sh "$vocab" <"$_stamp_tmp/lines"@@grep -iE '^[[:space:]]*(tier|confidence|domain|targets|class|covers|risk|risk(-|[[:space:]_]+)confidence|test(-|[[:space:]_]+)tier)[[:space:]]*:'
scripts/stamp.sh@@-@@printf '%s\n' "$line" | sh "$vocab"@@grep -iE '^[[:space:]]*(tier|confidence|domain|targets|class|covers|risk|risk(-|[[:space:]_]+)confidence|test(-|[[:space:]_]+)tier)[[:space:]]*:'
.agents/skills/pr-iterate/SKILL.md@@typed_return_ok@@printf 'Author-kind: %s\n%s\n' "$1" "$3" | sh "$checker"@@[ "$(printf '%s\n' "$3" | grep -c '')" -eq 3 ] || return 1
.agents/skills/to-tickets/SKILL.md@@prescreen_ok@@sh "$checker" <"$2"@@[ "$(grep -c '' "$2" 2>/dev/null)" = 2 ] || return 1
.agents/skills/dogfood/SKILL.md@@prescreen_ok@@sh "$checker" <"$2"@@[ "$(grep -c '' "$2" 2>/dev/null)" = 2 ] || return 1
EOLIFT
)

# checker_calls <root> [awk program] — one record per invocation of the
# checker in the shipped files under <root> that is not exempt above, found
# by <awk program> (CALLS_AWK by default):
# <file>\t<line>\t<function's first line>\t<function>\t<the call's command>
# The command is the call's own: the line cut at `;`, `&&` and `||` around
# the call, joined to the line before only when that line ends in a pipe.
CALLS_AWK=$(
	cat <<'EOAWK'
# scan <line> <file> — print a record for each call on one logical line
function scan(line, file,    cut, i, s, off, from, to, tail, before, after, command) {
	# cut: the line with each &&, || and lone & spelled as ; — the same
	# length, so a command is the span between two ; at line's offsets
	cut = line; gsub(/&&|\|\|/, ";;", cut)
	for (i = 1; i <= length(cut); i++)
		if (substr(cut, i, 1) == "&" && substr(cut, i - 1, 1) !~ /[<>]/ && substr(cut, i + 1, 1) != ">")
			cut = substr(cut, 1, i - 1) ";" substr(cut, i + 1)
	s = line; off = 0
	while (match(s, /(^|[ \t(|`;&])(ba)?sh([ \t]+-[A-Za-z]+)*[ \t]+("[^"]*vocab\.sh"|[^ \t`]*vocab\.sh"?|"?\$\{?(checker|vocab)\}?"?)/)) {
		from = off + RSTART; to = off + RSTART + RLENGTH
		tail = substr(s, RSTART + RLENGTH); s = tail; off = to - 1
		if (tail ~ /^[A-Za-z0-9_]/) continue # a longer name, not the checker
		if (tail ~ /^`/ && file ~ /\.md(\.template)?$/) continue # exempt:prose
		if (tail ~ /^[ \t]+fields/) continue # exempt:fields
		if (tail ~ /^( '<?[A-Za-z-]+>?: <[^>']*>')+( …)?($|[`.,;)])/) continue # exempt:quiz-tokens
		if (tail ~ /^ "[A-Za-z-]+: \$[0-9]"([ \t]|$)/) continue # exempt:positional
		# before keeps the character the match opened on: it may be the ;
		before = substr(cut, 1, from); sub(/.*;/, "", before)
		after = substr(cut, to); sub(/;.*/, "", after)
		command = before substr(line, from + 1, to - from - 1) after
		if (before ~ /^[ \t{(]*$/ && pipe_head != "") command = pipe_head " " command
		gsub(/[ \t]+/, " ", command); sub(/^ /, "", command); sub(/ $/, "", command)
		printf "%s\t%d\t%d\t%s\t%s\n", file, at, start, fn, command
	}
	pipe_head = cut; sub(/.*;/, "", pipe_head)
	if (pipe_head !~ /\|[ \t]*$/) pipe_head = ""
}
# a continued line still open when its file ends is a call all the same
FNR == 1 && cont != "" { scan(cont, cont_file) }
FNR == 1 { fn = "-"; start = 1; pipe_head = ""; cont = "" }
/^[ \t]*#/ { pipe_head = ""; next }
/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ {
	fn = $1; sub(/\(\).*/, "", fn); start = FNR
	one = ($0 ~ /\}[ \t]*$/)
}
/\\$/ {
	if (cont == "") at = FNR
	cont = cont substr($0, 1, length($0) - 1) " "; cont_file = FILENAME
	next
}
{
	if (cont == "") at = FNR
	line = cont $0; cont = ""
	scan(line, FILENAME)
}
/^}/ || one { fn = "-"; start = 1; one = 0 }
END { if (cont != "") scan(cont, cont_file) }
EOAWK
)
checker_calls() (
	awk_prog=${2:-$CALLS_AWK}
	cd "$1" || exit 2
	find scripts .agents/skills .githooks adapters constitution templates -type f \
		\( -name '*.sh' -o -name '*.md' -o -name '*.template' -o -name 'pre-*' \) \
		! -path scripts/vocab.sh 2>/dev/null | sort | xargs awk "$awk_prog"
)

# entry_matches <LIFTED entry> <file> <function> <call text> — exit 0 when
# the entry names this call: its file, its function, and its input in the
# call's text. The one reading of an entry, so `unlifted` and `stale` cannot
# disagree on what an entry matches; sets e_guard, the entry's lift stage.
entry_matches() {
	e_file=${1%%@@*} rest=${1#*@@}
	e_fn=${rest%%@@*} rest=${rest#*@@}
	e_input=${rest%%@@*} e_guard=${rest#*@@}
	[ "$2" = "$e_file" ] && [ "$3" = "$e_fn" ] || return 1
	case $4 in *"$e_input"*) return 0 ;; esac
	return 1
}

# unlifted <root> [awk program] — every call record no LIFTED entry accounts
# for, one per line; nothing when every site lifts.
unlifted() {
	checker_calls "$1" "${2:-}" | while IFS="$(printf '\t')" read -r file line start fn text; do
		ok=0
		while IFS= read -r entry; do
			entry_matches "$entry" "$file" "$fn" "$text" || continue
			sed -n "${start},$((line - 1))p" "$1/$file" | grep -v '^[[:space:]]*#' | grep -qF -- "$e_guard" || continue
			ok=1 && break
		done <<EOENTRIES
$LIFTED
EOENTRIES
		[ "$ok" = 1 ] || printf '%s:%s (%s)\n' "$file" "$line" "$fn"
	done
}

# stale <root> [inventory] — every inventory entry (LIFTED by default) that
# matches no call record under <root>, one per line; nothing when each does.
# Its second argument is the inventory, not `unlifted`'s awk program: stale
# always reads the calls through CALLS_AWK, since no mutant of it is baited.
stale() {
	records=$(checker_calls "$1")
	while IFS= read -r entry; do
		found=0
		while IFS="$(printf '\t')" read -r file line start fn text; do
			entry_matches "$entry" "$file" "$fn" "$text" && found=1 && break
		done <<EORECORDS
$records
EORECORDS
		[ "$found" = 1 ] || printf '%s\n' "$entry"
	done <<EOENTRIES
${2:-$LIFTED}
EOENTRIES
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
	for f in $(printf '%s\n' "$LIFTED" | sed 's/@@.*//' | sort -u); do
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
bait_edit .agents/skills/pr-iterate/SKILL.md "/grep -c '')\" -eq 3 \] || return 1/s/^/# /"
bait_named .agents/skills/pr-iterate/SKILL.md "the typed return's line count is commented out"
bait_reset
bait_edit scripts/stamp.sh 's|sh "$vocab" <"$_stamp_tmp/lines"|sh "$vocab" <"$_stamp_tmp/body"|'
bait_named scripts/stamp.sh "the fetched body is handed over in place of the lifted lines"
bait_reset
bait_edit .agents/skills/dogfood/SKILL.md 's|sh "$checker" <"$2"|sh "$checker" <"$1"|'
bait_named .agents/skills/dogfood/SKILL.md "the pre-screen checks the output it screened instead of the return"
bait_reset
printf '\tsh scripts/vocab.sh <"$body"\n' >>"$BAIT/.agents/skills/to-tickets/SKILL.md"
bait_named .agents/skills/to-tickets/SKILL.md "a new call site hands a body"

# The call's spelling: each form the audit claims above is found — two
# spaces, braces on the variable, `bash` for `sh`, the call split over a
# backslash-continued line, a quoted prefix of the path, an option before the
# checker, the variable bare. Each planted in a copy of a skill must be named.
# planted <how it is spelled> <printf format of the call> — plant the call in
# a copy of a skill; the audit must name it.
planted() {
	bait_reset
	# shellcheck disable=SC2059 # the format is the call itself, by design
	printf "$2" >>"$BAIT/.agents/skills/to-tickets/SKILL.md"
	bait_named .agents/skills/to-tickets/SKILL.md "a call $1 hands a body"
}
planted "with two spaces after \`sh\`" '\tsh  "$checker" <"$body"\n'
planted "with braces on the variable" '\tsh "${checker}" <"$body"\n'
planted "run by \`bash\`" '\tbash "$checker" <"$body"\n'
planted "split over a backslash-continued line" '\tsh \\\n\t\t"$checker" <"$body"\n'
planted "on a quoted prefix of the path" '\tsh "$ROOT"/scripts/vocab.sh <"$body"\n'
planted "with an option before the checker" '\tsh -e "$checker" <"$body"\n'
planted "on the variable unquoted" '\tsh $checker <"$body"\n'
planted "with braces on \$vocab" '\tsh "${vocab}" <"$body"\n'
planted "continued on the file's last line" '\tsh "$checker" <"$body" \\\n'
# … and on the last file the audit reads, where only the end of input is left
bait_reset
printf '\tsh "$vocab" <"$body" \\\n' >>"$BAIT/scripts/stamp.sh"
bait_named scripts/stamp.sh "a call continued on the last file's last line hands a body"
# A continued call is named at its first line, where a reader would look.
bait_reset
first=$(($(grep -c '' "$BAIT/.agents/skills/to-tickets/SKILL.md") + 1))
printf '\tsh \\\n\t\t"$checker" <"$body"\n' >>"$BAIT/.agents/skills/to-tickets/SKILL.md"
case $(unlifted "$BAIT") in
*".agents/skills/to-tickets/SKILL.md:$first "*) pass "a continued call is named at its first line ($first)" ;;
*) fail "a continued call is not named at its first line ($first): $(unlifted "$BAIT")" ;;
esac
# A backtick closes a prose mention only in prose: in a script it opens a
# command substitution, and the call inside it is a call.
bait_reset
printf '%s\n' 'out=`printf x | sh "$vocab"`' >>"$BAIT/scripts/stamp.sh"
bait_named scripts/stamp.sh "a call in a backtick substitution hands a body"
# A longer name is not the checker: `$checker_x` is somebody else's variable.
bait_reset
printf '\tsh "$checker_x" <"$body"\n' >>"$BAIT/.agents/skills/to-tickets/SKILL.md"
[ -z "$(unlifted "$BAIT")" ] && pass "a call on a longer name than \$checker is not taken for the checker" ||
	fail "a call on \$checker_x is taken for the checker: $(unlifted "$BAIT")"

# The inventory holds no more than the tree: every LIFTED entry matches a
# call the audit found, so a site removed or rewritten leaves no entry behind
# vouching for nothing.
bad=$(stale "$KIT")
[ -z "$bad" ] && pass "every LIFTED entry matches a checker call the audit found" ||
	fail "a LIFTED entry matches no checker call: $(printf '%s' "$bad" | tr '\n' ' ')"
bait_reset
STALE_ENTRY='.agents/skills/to-tickets/SKILL.md@@prescreen_ok@@sh "$checker" <"$body"@@return 1'
bad=$(stale "$BAIT" "$LIFTED
$STALE_ENTRY")
[ "$bad" = "$STALE_ENTRY" ] && pass "an inventory entry no call matches is named stale, and only it" ||
	fail "a stale inventory entry is not named alone: '$bad'"
bait_edit .agents/skills/dogfood/SKILL.md '/sh "$checker" <"$2"/d'
case $(stale "$BAIT") in
.agents/skills/dogfood/SKILL.md@@prescreen_ok@@*) pass "a call site removed leaves its entry named stale" ;;
*) fail "a call site removed leaves its entry vouching for nothing" ;;
esac

# The input an entry names is the call's own: on the call's command, or at
# the head of a pipe the line before ends with — never merely nearby. The
# old input left on the line before, or beside the call in another command
# on its line, vouches for nothing: the rewritten call is named, and so is
# the entry it no longer matches.
# rewritten <file> <how> <sed script> — the site in <file> rewritten <how>;
# the audit names it, and the entry is stale.
rewritten() {
	bait_reset
	bait_edit "$1" "$3"
	bait_named "$1" "a call is rewritten $2"
	case $(stale "$BAIT") in
	*"$1@@"*) pass "the entry left behind by a call rewritten $2 is named stale" ;;
	*) fail "a call rewritten $2 leaves its entry vouching for it in $1" ;;
	esac
}
rewritten .agents/skills/dogfood/SKILL.md "under a comment carrying the old input" 's|sh "$checker" <"$2"|# sh "$checker" <"$2"\
	sh "$checker" <"$body"|'
rewritten .agents/skills/dogfood/SKILL.md "under a line quoting the old input" "s|sh \"\$checker\" <\"\$2\"|: 'sh \"\$checker\" <\"\$2\"'\\
	sh \"\$checker\" <\"\$body\"|"
rewritten scripts/stamp.sh "beside the old input in another command" 's|{ sh "$vocab" <"$_stamp_tmp/lines"|{ : <"$_stamp_tmp/lines"; sh "$vocab" <"$_stamp_tmp/body"|'
# beside <file> <how> <sed script> — a second call planted beside the lifted
# one in <file>, sharing its line but not its command; the audit names it.
beside() {
	bait_reset
	bait_edit "$1" "$3"
	bait_named "$1" "a call is planted $2"
}
beside .agents/skills/dogfood/SKILL.md "glued to the lifted call by a bare \`;\`" 's|sh "$checker" <"$2"|sh "$checker" <"$2";sh "$checker" <"$body"|'
beside .agents/skills/dogfood/SKILL.md "after the lifted call and a lone \`&\`" 's|sh "$checker" <"$2"|sh "$checker" <"$2" \& sh "$checker" <"$body"|'
beside .agents/skills/dogfood/SKILL.md "after the lifted call and \`&&\`" 's|sh "$checker" <"$2"|sh "$checker" <"$2" \&\& sh "$checker" <"$body"|'
beside .agents/skills/dogfood/SKILL.md "before the lifted call and \`;\`" 's|sh "$checker" <"$2"|sh "$checker" <"$body"; sh "$checker" <"$2"|'
rewritten scripts/stamp.sh "behind a pipe from the old input" 's|{ sh "$vocab" <"$_stamp_tmp/lines"|{ : <"$_stamp_tmp/lines" \| sh "$vocab" <"$_stamp_tmp/body"|'
# A comment between a pipe's head and the call ends the join: the audit
# reads no further back than the line before, and names the call.
bait_reset
bait_edit .agents/skills/pr-iterate/SKILL.md 's|^\([[:space:]]*\)sh "$checker" >/dev/null|\1# a comment\
\1sh "$checker" >/dev/null|'
bait_named .agents/skills/pr-iterate/SKILL.md "a comment parts the pipe's head from the call"

# Every exemption is load-bearing: the audit with one exemption cut out of it
# names the real site that exemption admits. An exemption no site needs is
# one nobody would notice turning into a hole.
# exemption_bait <tag> <file the mutant must name> <the form>
exemption_bait() {
	mutant=$(printf '%s\n' "$CALLS_AWK" | grep -v "exempt:$1")
	case $(unlifted "$KIT" "$mutant") in
	*"$2:"*) pass "without the $3 exemption the audit names $2 — the exemption is load-bearing" ;;
	*) fail "without the $3 exemption the audit still passes $2 — the exemption admits nothing, or is not cut out by its tag" ;;
	esac
}
exemption_bait fields scripts/stamp.sh "\`fields\`"
exemption_bait positional .agents/skills/dogfood/SKILL.md "one-positional-token"
exemption_bait quiz-tokens .agents/skills/to-tickets/SKILL.md "quiz's own tokens"
exemption_bait prose .agents/skills/to-tickets/SKILL.md "prose mention"

# ---------------------------------------------------------------------------
banner "Usage — a caller that asks the wrong thing gets an error, not a guess"
# ---------------------------------------------------------------------------
vocab --frobnicate
expect_status 2 "an unknown option exits 2"
expect_err_has "usage"
vocab fields extra
expect_status 2 "'fields' takes no argument"
expect_err_has "usage"

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
expect_err_has "the caller hands it bare \`Field: value\` lines" "the usage text says what the caller hands over"
expect_err_has "a markdown-wrapped line" "…and names the line it does not read"
expect_err_has "is not a decision line to it" "…in those words"
assert_file_has "$VOCAB" "The caller hands it BARE \`Field: value\` lines" "the header says it too"
assert_file_has "$VOCAB" "is not a decision line to" "the header says it too"
# The header no longer invites a body (#401): since v0.35.0 every call site
# lifts first (PR #382's audit, above), and the header states the contract
# once — a calling skill lifts the decision lines and hands them over. The
# literals below each sit on one line of the file they are held against.
assert_file_lacks "$VOCAB" "body may be piped in" "the contract changed in v0.35.0 — a body is the caller's to lift"
assert_file_lacks "$VOCAB" "the caller may hand over a" "nor does a function comment invite one"
assert_file_has "$VOCAB" "a calling skill lifts the decision" "the header states the contract: lifting is the caller's job"
printf '%s\n' '- Tier: Implementor' >"$SCRATCH/listed"
t_exec sh "$VOCAB" <"$SCRATCH/listed"
expect_resolved "" "a list-marked line on stdin is ignored, not checked — its key is '- Tier', no declared field"
vocab '**Tier:** Implementor'
expect_resolved "" "an emphasized line is ignored, not checked"
vocab check '- Tier: Implementor' 'Tier: Implementor'
expect_status 2 "the same line handed over bare is refused — lifting it out is the caller's job"
expect_err_has "tier: 'Implementor' is not one of"

# A declared field is a word every body handed over is now read for, so it
# must be a word no ordinary body uses as a key. `Author:` is one a ticket, a
# commit trailer or a forge's own issue header carries — declared as a field,
# a whole body piped in went from exit 0 to exit 2 on its author's name
# (review of PR #318). The field is `author-kind`, and `Author:` is prose.
printf 'Author: Arthur\n' >"$SCRATCH/authored"
t_exec sh "$VOCAB" <"$SCRATCH/authored"
expect_resolved "" "a plain 'Author: <name>' line in a body is not a decision line"
vocab 'Author-kind: maintainer'
expect_status 2 "'Author-kind: maintainer' — a kind nobody declared — is refused"
expect_err_has "author-kind: 'maintainer' is not one of bot human"

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
expect_resolved "" "a named policy file's own vocabularies answer"
vocab 'Severity: high'
expect_status 2 "the shipped severity is refused once a project narrowed the scale"
expect_err_has "severity: 'high' is not one of blocking advisory"
vocab 'Domain: content'
expect_resolved "" "a field the policy file does not declare is not a decision line — ignored"
vocab fields
expect_out_is "tier: planner implementer mechanical reviewer
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
expect_resolved "" "a policy file with no VOCAB_RULES line enforces no rule — the shipped rule is not sourced beneath it"
vocab fields
expect_out_is "action: apply reply escalate
command-shaped: yes no" "'fields' prints the file's two fields and no rule — nothing of the defaults leaks through"
: >"$SCRATCH/empty.config.sh"
VOCAB_CONFIG="$SCRATCH/empty.config.sh"
vocab 'Tier: planner'
expect_status 2 "an EMPTY policy file declares no field, and is refused as such rather than falling back to the shipped words"
expect_err_has "policy: VOCAB_FIELDS declares no field"

VOCAB_CONFIG="$SCRATCH/absent.config.sh"
vocab 'Tier: planner'
expect_status 2 "a policy file named explicitly and missing is exit 2"
expect_err_has "does not exist"
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
t_exec _run_cwd_body
expect_status 0 "a slash-less VOCAB_CONFIG loads"
expect_out_has "mood: calm brisk" "…the cwd's file, the one the existence check saw"
expect_err_lacks "DECOY-FROM-PATH"

# Orders 2 and 3 anchor on where the SCRIPT lives — never on the cwd. The
# fixture is the resolver suite's: the operator's own copy, invoked by
# absolute path, from inside somebody else's clone whose policy file would
# announce itself if run.
install_vocab() {
	mkdir -p "$1"
	cp "$VOCAB" "$1/vocab.sh"
}
_run_from_body() { _rf_cwd=$1; _rf_script=$2; shift 2; cd "$_rf_cwd" && unset VOCAB_CONFIG && sh "$_rf_script" "$@"; }
run_from() { t_exec _run_from_body "$@"; }

t_repo
OWN_REPO=$REPO
install_vocab "$OWN_REPO/tools"
t_write "$OWN_REPO" scripts/vocab.config.sh "$CONFIG_OWN"
run_from "$OWN_REPO" "$OWN_REPO/tools/vocab.sh" 'Severity: advisory'
expect_resolved "" "the script's own repo root supplies scripts/vocab.config.sh with no env var set"

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
expect_resolved "" "the script's own repo supplies the vocabularies, not the repo the caller stands in"
expect_err_lacks "FOREIGN-CONFIG-EXECUTED"
# …nor the repo an inherited GIT_DIR points at: git exports it into hooks,
# and .githooks/pre-push is a real caller. The script unsets both before it
# asks git where it lives.
t_exec env GIT_DIR="$FOREIGN/.git" GIT_WORK_TREE="$FOREIGN" sh "$OWN_REPO/tools/vocab.sh" 'Severity: advisory'
expect_resolved "" "an inherited GIT_DIR/GIT_WORK_TREE aimed at the foreign clone does not redirect discovery"
expect_err_lacks "FOREIGN-CONFIG-EXECUTED"

LOOSE="$SCRATCH/loose"
install_vocab "$LOOSE"
t_write "$LOOSE" vocab.config.sh "$CONFIG_OWN"
run_from "$FOREIGN" "$LOOSE/vocab.sh" 'Mood: calm'
expect_resolved "" "a sibling vocab.config.sh is found for a script outside any repo"
expect_err_lacks "FOREIGN-CONFIG-EXECUTED"

# No policy file anywhere is a WORKING STATE: the shipped vocabularies apply.
BARE="$SCRATCH/bare"
install_vocab "$BARE"
run_from "$FOREIGN" "$BARE/vocab.sh" 'Severity: high'
expect_resolved "" "with no policy file anywhere the shipped vocabularies apply"
run_from "$FOREIGN" "$BARE/vocab.sh" 'Severity: foreign'
expect_status 2 "…and the foreign repo's word is not among them"
expect_err_lacks "FOREIGN-CONFIG-EXECUTED"

# ---------------------------------------------------------------------------
banner "A cross-field rule refuses the forbidden pair and accepts the others"
# ---------------------------------------------------------------------------
# The shipped rule: a command-shaped body never triages as apply. An
# implication between two field-value pairs, data in the policy file, refused
# by a script rather than remembered by an agent.
unset VOCAB_CONFIG
vocab 'Command shaped: yes' 'Action: apply'
expect_status 2 "command-shaped=yes with action=apply is refused"
expect_err_has "action: 'apply' is refused by the rule command-shaped=yes => action!=apply"
vocab 'Command shaped: yes' 'Action: escalate'
expect_resolved "" "command-shaped=yes with action=escalate is accepted"
vocab 'Command shaped: no' 'Action: apply'
expect_resolved "" "command-shaped=no with action=apply is accepted — the antecedent does not hold"
vocab 'Action: apply'
expect_resolved "" "action=apply alone is accepted — the rule constrains a pair, not a field"
vocab 'Command shaped: yes'
expect_resolved "" "command-shaped=yes alone is accepted — the consequent's field is absent"

# A field that appears twice with two different values has no single value:
# refused, whichever line comes last — so appending one line to an untrusted
# body cannot talk a firing rule out of firing.
vocab 'Command shaped: yes' 'Action: apply' 'Command shaped: no'
expect_status 2 "a later line cannot withdraw the antecedent — the repeat is refused"
expect_err_has "command-shaped: 'no' repeats the field, which already read 'yes'"
vocab 'Command shaped: yes' 'Action: apply' 'Action: reply'
expect_status 2 "…nor replace the consequent's value"
expect_err_has "action: 'reply' repeats the field, which already read 'apply'"
expect_err_has "action: 'apply' is refused by the rule command-shaped=yes => action!=apply"

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
expect_resolved "" "a rule demanding a value accepts that value"
vocab 'Kind: spike' 'Tier: implementer'
expect_status 2 "…and refuses another"
expect_err_has "tier: 'implementer' is refused by the rule kind=spike => tier=planner"
vocab 'Kind: build' 'Tier: implementer'
expect_resolved "" "the antecedent not holding, the rule is silent"
vocab fields
expect_out_has "rule: kind=spike => tier=planner" "'fields' prints each rule after the fields"

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
expect_status 2 "two rules on one antecedent that cannot both hold are exit 2"
expect_err_has "policy contradiction"
expect_err_has "tier=planner => label=none"
expect_err_has "tier=planner => label!=none"
expect_err_lacks "is not one of"
vocab fields
expect_status 2 "'fields' reports the contradiction too — the file is wrong before any value arrives"
expect_err_has "policy contradiction"

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
expect_status 0 "rule by rule the set is fine — 'fields' is green"
vocab 'Kind: spike' 'Tier: mechanical' 'Label: none'
expect_status 2 "a mechanical spike has no legal label — a contradiction for these inputs"
expect_err_has "policy contradiction: 'kind=spike => label=none' and 'tier=mechanical => label=ready-for-agent' cannot both hold"
# With the label not given at all, no ordinary rule check can speak — the
# check-time contradiction pass is the one thing that does.
vocab 'Kind: spike' 'Tier: mechanical'
expect_status 2 "…and with no label given, the contradiction is the one reason — the ordinary rule check is silent"
expect_err_has "policy contradiction: 'kind=spike => label=none' and 'tier=mechanical => label=ready-for-agent' cannot both hold"
expect_err_lacks "is refused by the rule"
vocab 'Kind: build' 'Tier: mechanical' 'Label: ready-for-agent'
expect_resolved "" "a build on the mechanical tier is fine — only one rule fires"

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
expect_status 2 "rules excluding every token of a field are a contradiction"
expect_err_has "policy contradiction: the rules on label exclude every one of its tokens"

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
expect_status 2 "a rule naming an undeclared field is a policy error"
expect_err_has "policy: rule 'tier=planner => label=none' names 'label', which is not a declared field"

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
expect_status 2 "a rule naming a token outside its field's vocabulary is a policy error"
expect_err_has "policy: rule 'tier=senior => tier!=planner' names 'senior', which tier does not declare"

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
expect_status 2 "a token outside the shape IN THE POLICY FILE is a policy error"
expect_err_has "policy: severity token 'Critical' is not a well-formed token"

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
expect_status 2 "a declared closed field with no tokens is a policy error"
expect_err_has "policy: field 'mood' declares no tokens"

# A malformed rule is a policy error, never a rule quietly ignored — `fields`
# would print nothing for it, and nothing else would say.
t_write "$SCRATCH" malformed.config.sh "VOCAB_FIELDS='tier label'
VOCAB_OPEN=''
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_LABEL='ready-for-agent none'
VOCAB_RULES='tier planner => label=none'"
VOCAB_CONFIG="$SCRATCH/malformed.config.sh"
vocab 'Tier: planner'
expect_status 2 "a rule with no '=' on its left is malformed — a policy error"
expect_err_has "policy: rule 'tier planner => label=none' is malformed"
t_write "$SCRATCH" malformed2.config.sh "VOCAB_FIELDS='tier'
VOCAB_OPEN=''
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_RULES='tier=planner'"
VOCAB_CONFIG="$SCRATCH/malformed2.config.sh"
vocab fields
expect_status 2 "a rule with no '=>' is malformed too, and 'fields' says so before any value arrives"
expect_err_has "policy: rule 'tier=planner' is malformed"

# A field may not take one of the checker's own names: `fields` would make
# the field list its own vocabulary, and nothing would say so.
for reserved in fields open rules token-shape config; do
	t_write "$SCRATCH" reserved.config.sh "VOCAB_FIELDS='tier $reserved'
VOCAB_OPEN=''
VOCAB_TIER='planner'
VOCAB_RULES=''"
	VOCAB_CONFIG="$SCRATCH/reserved.config.sh"
	vocab fields
	expect_status 2 "a field named '$reserved' is refused at load — the name is the checker's own"
	expect_err_has "policy: field name '$reserved' is reserved"
done

# A FIELD NAME is held to the shape as a token is.
t_write "$SCRATCH" badfield.config.sh "VOCAB_FIELDS='Tier'
VOCAB_OPEN=''
VOCAB_TIER='planner'
VOCAB_RULES=''"
VOCAB_CONFIG="$SCRATCH/badfield.config.sh"
vocab 'Tier: planner'
expect_status 2 "a field name outside the shape is a policy error"
expect_err_has "policy: field name 'Tier' is not a well-formed token"

# A rule may name an OPEN field, whose values have only the shape to meet.
t_write "$SCRATCH" openrule.config.sh "VOCAB_FIELDS='domain tier'
VOCAB_OPEN='domain'
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_RULES='domain=Content => tier=planner'"
VOCAB_CONFIG="$SCRATCH/openrule.config.sh"
vocab 'Tier: planner'
expect_status 2 "a rule naming an out-of-shape value on an open field is a policy error"
expect_err_has "policy: rule 'domain=Content => tier=planner' names 'Content', which is not a well-formed token"
t_write "$SCRATCH" openrule2.config.sh "VOCAB_FIELDS='domain tier'
VOCAB_OPEN='domain'
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_RULES='domain=content => tier=planner'"
VOCAB_CONFIG="$SCRATCH/openrule2.config.sh"
vocab 'Domain: content' 'Tier: implementer'
expect_status 2 "…and a well-formed one fires like any other rule"
expect_err_has "tier: 'implementer' is refused by the rule domain=content => tier=planner"

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
expect_status 2 "a vocabulary whose tokens carry their answer is refused"
expect_err_has "policy: action token 'safe-to-apply' carries its answer in its spelling ('safe')"
expect_err_has "policy: action token 'risky' carries its answer in its spelling ('risky')"
expect_err_has "neutral"

# The rule walks EVERY hyphen-separated word, not only the first: the answer
# hides as readily at the end of a token.
t_write "$SCRATCH" leading2.config.sh "VOCAB_FIELDS='action'
VOCAB_OPEN=''
VOCAB_ACTION='apply mostly-risky'
VOCAB_RULES=''"
VOCAB_CONFIG="$SCRATCH/leading2.config.sh"
vocab 'Action: apply'
expect_status 2 "a token whose offending word is not its first is refused too"
expect_err_has "policy: action token 'mostly-risky' carries its answer in its spelling ('risky')"

# The deny list is the CHECKER'S, not the policy file's: a file that
# reassigns it — or empties it — has not switched the rule off.
t_write "$SCRATCH" off.config.sh "VOCAB_LEADING_WORDS=''
VOCAB_FIELDS='action'
VOCAB_OPEN=''
VOCAB_ACTION='safe-to-apply risky'
VOCAB_RULES=''"
VOCAB_CONFIG="$SCRATCH/off.config.sh"
vocab 'Action: risky'
expect_status 2 "a policy file cannot switch the neutral-name rule off by emptying the word list"
expect_err_has "policy: action token 'safe-to-apply' carries its answer in its spelling ('safe')"

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
expect_resolved "" "the neutral pair — apply, escalate — passes"
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
expect_resolved "" "the checker accepts a fifth tier the policy file declares — the file is the consumer's"
unset VOCAB_CONFIG
printf '%s\n' "AGENT_TIER_PLANNER='m'" >"$SCRATCH/agents.config.sh"
AGENTS_CONFIG="$SCRATCH/agents.config.sh" t_exec sh "$KIT/scripts/agents.lib.sh" senior
expect_status 2 "the resolver still refuses it — the tier vocabulary is closed where it is owned"
expect_err_has "unknown capability tier 'senior'"
assert_file_has "$KIT/scripts/vocab.config.sh" "owned by" "the shipped policy file says who owns each field"

# ---------------------------------------------------------------------------
banner "Targets: — a QUERY field, a trace filter held to a grammar (process/R25, #802)"
# ---------------------------------------------------------------------------
# A ticket that edits a review lens or a skill names the trace events it means
# to move, as `Targets: kind=<kind> [<key>=<value> …]`. No token set can hold
# that, so the policy declares the field a QUERY (VOCAB_QUERY) and the checker
# holds the value to the grammar instead: one to eight `<key>=<value>` terms,
# exactly one `kind=`, no key twice, a key a field name or `data.<key>` in the
# trace's own shape, and a value of the token alphabet with dots — never a
# quote, a space inside, or a character a shell or awk would read.
vocab fields
expect_out_has "targets (query):" "the targets field is marked a QUERY — a filter, not a token"
vocab 'Targets: kind=finding.raise data.agent=security data.severity=high'
expect_resolved "" "the PRD's own example is accepted"
vocab 'Targets: kind=review.verdict outcome=blocked'
expect_resolved "" "a field term beside the kind is accepted"
vocab 'Targets: data.agent=security'
expect_status 2 "a filter with no kind= term is refused"
expect_err_has "targets: the filter names no kind= term"
vocab 'Targets: kind=finding.raise kind=review.verdict'
expect_status 2 "a key twice is refused — two answers are none"
expect_err_has "targets: the key 'kind' appears twice"
vocab 'Targets: kind=finding.raise data.Agent=security'
expect_status 2 "a data key outside the trace's [a-z][a-z0-9_]* is refused"
expect_err_has "targets: 'data.Agent' is not a field name or data.<key>"
vocab "Targets: kind=finding.raise data.agent=sec'urity"
expect_status 2 "a value carrying a quote is refused"
expect_err_has "targets: the value of 'data.agent' is not"
vocab 'Targets: kind=finding.raise data.agent'
expect_status 2 "a term with no = is refused"
expect_err_has "targets: 'data.agent' is not a <key>=<value> term"
vocab 'Targets: kind=a data.a=1 data.b=1 data.c=1 data.d=1 data.e=1 data.f=1 data.g=1 data.h=1'
expect_status 2 "nine terms are refused — the filter is bounded"
expect_err_has "targets: more than 8 terms"
vocab 'Targets: kind=finding.raise data.agent=$(id)'
expect_status 2 "a value shaped like a command is refused"

# ---------------------------------------------------------------------------
banner "Class: — the ticket's class, an OPEN token field /retro counts toil by (#819)"
# ---------------------------------------------------------------------------
# /retro's flow section reads toil's share from ticket.start's data.class,
# and /implement records one only from a `Class:` line this checker passed.
# The class is the consumer's — the kit names no class of its own (PRD-03) —
# so the field is OPEN, like domain: any well-formed token, held to the shape
# and a bound, and never a quote, a capital or a command.
vocab fields
expect_out_has "class (open): " "the class field is declared open, with no tokens of the kit's own"
vocab 'Class: toil'
expect_resolved "" "a Class: toil line is accepted"
vocab 'Class: chore'
expect_resolved "" "a class the kit never named is accepted — the field is open"
vocab 'Class: Toil'
expect_status 2 "a class outside the token shape is refused"
expect_err_has "class: 'Toil' is not a well-formed token"
vocab "Class: toil';touch PWN;'"
expect_status 2 "a class carrying a quote is refused"
vocab "Class: $(printf '%065d' 0 | tr 0 a)"
expect_status 2 "a class past 64 bytes is refused — the token is bounded"
vocab "Class: $(printf '%064d' 0 | tr 0 a)"
expect_resolved "" "a class of exactly 64 bytes is accepted"

# ---------------------------------------------------------------------------
banner "Risk: — a QUALIFIED field: a level, and one reason for the levels that take one (process/R38)"
# ---------------------------------------------------------------------------
# The ticket contract's risk stamp (the kit's ADR-0037). `low` stands alone;
# `high` takes exactly one reason from the policy's risk reasons. The checker
# refuses any other value and names the field.
unset VOCAB_CONFIG
vocab fields
expect_out_has "risk (qualified): low high; reasons for high: irreversible security invisible shared-layer unclear unlearned outward; reserved: unlearned outward" \
	"process/R38: fields prints risk as a qualified field — its levels, the reasons and the reserved ones"
vocab 'Risk: low'
expect_resolved "" "process/R38: 'Risk: low' is accepted — the level alone"
vocab 'Risk: high shared-layer'
expect_resolved "" "process/R38: 'Risk: high shared-layer' is accepted — a level and one reason"
for reason in irreversible security invisible shared-layer unclear; do
	vocab "Risk: high $reason"
	expect_resolved "" "process/R38: 'Risk: high $reason' is accepted from the planner"
done
vocab 'Risk: high'
expect_status 2 "process/R38: 'Risk: high' — a level that takes a reason, given none — is refused"
expect_err_has "risk: 'high' takes exactly one reason"
vocab 'Risk: low security'
expect_status 2 "process/R38: 'Risk: low security' — a reason on a level that takes none — is refused"
expect_err_has "risk: 'low' takes no reason"
vocab 'Risk: high security invisible'
expect_status 2 "process/R38: two reasons are refused — exactly one"
expect_err_has "risk:"
vocab 'Risk: high sloppy'
expect_status 2 "process/R38: a reason the policy does not declare is refused"
expect_err_has "risk: 'sloppy' is not one of irreversible security invisible shared-layer unclear unlearned outward"
vocab 'Risk: medium'
expect_status 2 "process/R38: a level the policy does not declare is refused"
expect_err_has "risk: 'medium' is not one of low high"
vocab 'Risk: High security'
expect_status 2 "process/R38: a capitalised level is refused — tokens match whole"
vocab 'Risk: high  security'
expect_resolved "" "process/R38: blanks between the level and its reason are one separator"
vocab 'Risk: high security' 'Risk: high security'
expect_resolved "" "process/R38: the same risk said twice is one answer"
vocab 'Risk: high security' 'Risk: low'
expect_status 2 "process/R38: two different risks are refused — one value per field"
expect_err_has "risk: 'low' repeats the field"

# ---------------------------------------------------------------------------
banner "Risk: — the reserved reasons have one writer, the risk rule (process/R39)"
# ---------------------------------------------------------------------------
# `unlearned` and `outward` are the risk rule's alone. The default writer is
# the planner, so a ticket, a stamp or a factory line can never name one; a
# caller that declares itself the risk rule may.
for reason in unlearned outward; do
	vocab "Risk: high $reason"
	expect_status 2 "process/R39: 'Risk: high $reason' from the default (planner) writer is refused"
	expect_err_has "risk: the reason '$reason' is reserved for the risk rule"
	vocab check --writer planner "Risk: high $reason"
	expect_status 2 "process/R39: 'Risk: high $reason' from a declared planner is refused"
	vocab check --writer risk-rule "Risk: high $reason"
	expect_resolved "" "process/R39: 'Risk: high $reason' from a caller declared as the risk rule is accepted"
	vocab --writer risk-rule "Risk: high $reason"
	expect_resolved "" "process/R39: --writer may open the command line, the check implied"
	printf 'Risk: high %s\n' "$reason" >"$SCRATCH/risk-rule.lines"
	t_exec sh "$VOCAB" check --writer risk-rule <"$SCRATCH/risk-rule.lines"
	expect_resolved "" "process/R39: the risk rule's lines may come on stdin"
done
vocab check --writer risk-rule 'Risk: high'
expect_status 2 "process/R39: the risk rule is held to the grammar like anyone — a reason is still owed"
vocab check --writer judge 'Risk: low'
expect_status 2 "process/R39: a writer the checker does not know is a usage error"
expect_err_has "usage"
vocab check --writer
expect_status 2 "process/R39: --writer with no word is a usage error"
# The writer is a flag, never the environment: a caller cannot inherit it.
t_exec env VOCAB_WRITER=risk-rule sh "$VOCAB" 'Risk: high outward'
expect_status 2 "process/R39: no environment variable makes a caller the risk rule"

# ---------------------------------------------------------------------------
banner "Test-tier: — a KEYED field: a requirement id, then one test tier (process/R40)"
# ---------------------------------------------------------------------------
vocab fields
expect_out_has "test-tier (keyed): unit suite e2e manual" "process/R40: fields prints test-tier as a keyed field and its four tiers"
vocab 'Test-tier: process/R41 suite'
expect_resolved "" "process/R40: one Test-tier: line is accepted"
vocab 'Test-tier: R7 manual'
expect_resolved "" "process/R40: a PRD's plain id is an id too"
vocab 'Test-tier: process/R41 suite' 'Test-tier: process/R42 unit'
expect_resolved "" "process/R40: one line per distinct id is accepted"
vocab 'Test-tier: process/R41 suite' 'Test-tier: process/R41 suite'
expect_resolved "" "process/R40: the same id with the same tier is one answer"
vocab 'Test-tier: process/R41 suite' 'Test-tier: process/R41 unit'
expect_status 2 "process/R40: the same id given two tiers is refused"
expect_err_has "test-tier: 'process/R41' is given two tiers"
vocab 'Test-tier: process/R41 smoke'
expect_status 2 "process/R40: a tier the policy does not declare is refused"
expect_err_has "test-tier: 'smoke' is not one of unit suite e2e manual"
vocab 'Test-tier: process/R41'
expect_status 2 "process/R40: an id with no tier is refused"
expect_err_has "test-tier:"
vocab 'Test-tier: process/R41 suite unit'
expect_status 2 "process/R40: an id with two tiers on one line is refused"
vocab 'Test-tier: Process/R41 suite'
expect_status 2 "process/R40: an id outside the requirement grammar is refused"
expect_err_has "test-tier: the id is not a requirement id"
vocab "Test-tier: $(printf '%033d' 0 | tr 0 a)/R1 suite"
expect_status 2 "process/R40: an area past 32 characters is no id — the grammar is bounded"
vocab 'Test-tier: process/R1234567 suite'
expect_status 2 "process/R40: a number past 6 digits is no id"
vocab 'Test-tier: process/R0 suite'
expect_status 2 "process/R40: R0 is no PRD id"
vocab "Test-tier: x;touch\$(id) suite"
expect_status 2 "process/R40: an id shaped like a command is refused"
# The id's grammar is the requirement library's: without it the checker
# cannot read an id, and refuses rather than pass one unread.
mkdir -p "$SCRATCH/nolib"
cp "$VOCAB" "$SCRATCH/nolib/vocab.sh"
t_exec sh "$SCRATCH/nolib/vocab.sh" 'Test-tier: process/R41 suite'
expect_status 2 "process/R40: with no requirement library beside the checker, a Test-tier: line is refused"
expect_err_has "requirement.lib.sh"
t_exec sh "$SCRATCH/nolib/vocab.sh" fields
expect_status 0 "…while fields still answers — the library is read only to check an id"

# ---------------------------------------------------------------------------
banner "The contract's new closed fields and the per-key line bounds (process/R41)"
# ---------------------------------------------------------------------------
vocab fields
expect_out_has "risk-confidence: low medium high" "process/R41: risk-confidence is its own closed field"
expect_out_has "result: pass fail skipped" "process/R41: a check-table row's result"
expect_out_has "scope: inside outward" "process/R41: an unspecified item's scope"
expect_out_has "bound: 8" "process/R41: every stamp key is bounded at 8 lines"
expect_out_has "bound test-tier: 32" "process/R41: test-tier is bounded at 32"
vocab 'Risk-confidence: medium' 'Confidence: high'
expect_resolved "" "process/R41: Risk-confidence: and Confidence: are two fields — two answers, no conflict"
vocab 'Risk confidence: medium'
expect_resolved "" "process/R41: the key folds like every key — 'Risk confidence' names risk-confidence"
vocab 'Risk-confidence: sure'
expect_status 2 "process/R41: risk-confidence is closed"
vocab 'Result: skipped' 'Scope: outward'
expect_resolved "" "process/R41: result and scope accept their tokens"
vocab 'Scope: elsewhere'
expect_status 2 "process/R41: scope is closed"

# ---------------------------------------------------------------------------
banner "A qualified or keyed field in the policy file is held at load"
# ---------------------------------------------------------------------------
# policy_refused <label> <expected stderr> <config text>
policy_refused() {
	t_write "$SCRATCH" kind.config.sh "$3"
	t_exec env VOCAB_CONFIG="$SCRATCH/kind.config.sh" sh "$VOCAB" fields
	expect_status 2 "$1: a policy error, exit 2"
	expect_err_has "$2"
}
policy_refused "a reserved reason the field does not declare" "policy: risk reserves 'judged', which is not one of its reasons" "$(
	cat <<'EOFC'
VOCAB_FIELDS='risk'
VOCAB_QUALIFIED='risk'
VOCAB_RISK='low high'
VOCAB_RISK_QUALIFIED='high'
VOCAB_RISK_REASONS='security'
VOCAB_RISK_RESERVED='judged'
EOFC
)"
policy_refused "a qualified level the field does not declare" "policy: risk qualifies 'medium', which is not one of its levels" "$(
	cat <<'EOFC'
VOCAB_FIELDS='risk'
VOCAB_QUALIFIED='risk'
VOCAB_RISK='low high'
VOCAB_RISK_QUALIFIED='medium'
VOCAB_RISK_REASONS='security'
EOFC
)"
policy_refused "a qualified field with no reasons" "policy: qualified field 'risk' declares no reasons" "$(
	cat <<'EOFC'
VOCAB_FIELDS='risk'
VOCAB_QUALIFIED='risk'
VOCAB_RISK='low high'
VOCAB_RISK_QUALIFIED='high'
EOFC
)"
policy_refused "a reason carrying its answer" "policy: risk reason 'risky' carries its answer in its spelling" "$(
	cat <<'EOFC'
VOCAB_FIELDS='risk'
VOCAB_QUALIFIED='risk'
VOCAB_RISK='low high'
VOCAB_RISK_QUALIFIED='high'
VOCAB_RISK_REASONS='security risky'
EOFC
)"
policy_refused "a field of two kinds" "one kind per field" "$(
	cat <<'EOFC'
VOCAB_FIELDS='test-tier'
VOCAB_KEYED='test-tier'
VOCAB_OPEN='test-tier'
VOCAB_TEST_TIER='unit suite'
EOFC
)"
policy_refused "a rule on a keyed field" "a rule reads one token" "$(
	cat <<'EOFC'
VOCAB_FIELDS='test-tier tier'
VOCAB_KEYED='test-tier'
VOCAB_TEST_TIER='unit suite'
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_RULES='tier=planner => test-tier=unit'
EOFC
)"
policy_refused "a bound on an undeclared field" "policy: VOCAB_BOUNDS names 'covers', which is not a declared field" "$(
	cat <<'EOFC'
VOCAB_FIELDS='tier'
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_BOUND=8
VOCAB_BOUNDS='covers=32'
EOFC
)"
policy_refused "a bound that is not a count" "policy: VOCAB_BOUND '0' is not a count of lines" "$(
	cat <<'EOFC'
VOCAB_FIELDS='tier'
VOCAB_TIER='planner implementer mechanical reviewer'
VOCAB_BOUND=0
EOFC
)"
policy_refused "a field named for a qualified field's own variable" "is reserved" "$(
	cat <<'EOFC'
VOCAB_FIELDS='risk risk-reasons'
VOCAB_QUALIFIED='risk'
VOCAB_RISK='low high'
VOCAB_RISK_QUALIFIED='high'
VOCAB_RISK_REASONS='security'
EOFC
)"
# A policy that predates the bound declares none: fields prints no bound
# line, and the stamp reader falls back to its own 8 (tests/stamp.test.sh).
t_write "$SCRATCH" nobound.config.sh "VOCAB_FIELDS='tier'
VOCAB_TIER='planner implementer mechanical reviewer'
"
t_exec env VOCAB_CONFIG="$SCRATCH/nobound.config.sh" sh "$VOCAB" fields
expect_status 0 "a policy with no bound loads"
expect_out_lacks "bound" "…and prints no bound line"

t_done "vocab"
