#!/bin/sh
# tests/trace-prices.test.sh — the price table says when it is stale, and
# refreshes on demand (PRD #237, ticket #270).
#
# ADR-0008 clause 6 prices a trace on READ, from a table in the policy file, so
# that nothing in the trace is ever re-written when a vendor moves. The cost of
# that choice is a table with a date on it, and a dated claim rots quietly: a
# cost column nobody re-derives is exactly the number an operator believes. Two
# mechanisms answer it, and this suite is their oracle.
#
#   1. A STALENESS ADVISORY, in the shared script. `summary` and the priced
#      `export --csv` read the `Last checked: <YYYY-MM-DD>` line of the policy
#      file THAT IS IN EFFECT and print one note on stderr when it is older
#      than TRACE_PRICES_STALE_DAYS. Never a failure, never on stdout, silenced
#      by TRACE_QUIET=1 — and silent when the window is empty, because an empty
#      policy value is "no opinion" everywhere else in this kit and a default
#      window would be the kit deciding for a consumer.
#   2. A KIT-ONLY REFRESH SCRIPT, scripts/trace-prices.kit.sh, on demand and
#      network-required like scripts/mutation.kit.sh: two machine-readable
#      sources, a refusal when they disagree past a threshold, and a write that
#      rewrites the twin's five entries, its date and its source revisions and
#      prints the diff for the operator to commit.
#
# Every case is driven RED first (hard rule 9): the suite was written against
# no advisory and no refresh script at all, each assertion naming the wrong
# implementation it would catch. The fixtures are SYNTHETIC and absurd
# (tests/fixtures/prices/README.md says why) so that no assertion here can
# pass by coincidence with a real price.
#
# Usage: sh tests/trace-prices.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=./lib.sh
. "$ROOT/tests/lib.sh"
t_init

KIT="$ROOT"
TRACE="$KIT/scripts/trace.sh"
REFRESH="$KIT/scripts/trace-prices.kit.sh"
TWIN="$KIT/scripts/trace.kit.config.sh"
SHIPPED="$KIT/scripts/trace.config.sh"
FIX="$KIT/tests/fixtures/prices"
TODAY=$(date -u +%Y-%m-%d)
# Old enough that no window this repo would ever set reaches it, and a literal
# rather than arithmetic: `date -d '30 days ago'` is not POSIX, and a suite
# that needs GNU date to say "stale" is a suite that passes on one host.
ANCIENT=2020-01-01

# A reader fixture: one token-bearing event, shaped exactly as the emitter
# writes one so `verify` passes on it and `summary` has something to price.
SUM="$SCRATCH/priced"
mkdir -p "$SUM/events"
printf '%s\n' \
	'{"v":1,"ts":"'"$TODAY"'T10:00:00Z","id":"p1","kind":"session.usage","skill":"implement","subject":"session:s1","session":"s1","model":"m1","tok_in":1000,"tok_out":0,"tok_cache_w":0,"tok_cache_r":0}' \
	>"$SUM/events/$TODAY.jsonl"

# policy_at <label> <last-checked date or ''> <window value> — a policy file in
# scratch over that fixture. The date line is written in the twin's own prose
# shape, because the advisory has to find it in a COMMENT rather than in a
# variable: the date is the operator's claim about the table, not a value the
# script assigns.
policy_at() {
	_pa=$SCRATCH/policy.$1.sh
	{
		printf "TRACE_DIR='%s'\n" "$SUM"
		printf "TRACE_PRICE_M1='3,15,3.75,0.30'\n"
		printf "TRACE_PRICES_STALE_DAYS='%s'\n" "$3"
		[ -n "$2" ] && printf '# THESE NUMBERS ARE A CLAIM WITH A DATE ON IT. Last checked: %s, by the\n# operator, against the vendors own pages.\n' "$2"
	} >"$_pa"
	printf '%s\n' "$_pa"
}

# ---------------------------------------------------------------------------
banner "1. A dated table says when it is stale — on stderr, never as a failure"
# ---------------------------------------------------------------------------
# An advisory ON STDOUT would land in the middle of the table a spreadsheet
# reads, and a NON-ZERO exit would make a stale price table fail a command that
# answered correctly. Both are the wrong-implementation cases these legs catch.
FRESH=$(policy_at fresh "$TODAY" 30)
STALE=$(policy_at stale "$ANCIENT" 30)
NOWIN=$(policy_at nowin "$ANCIENT" '')
WIDE=$(policy_at wide "$ANCIENT" 99999)
NODATE=$(policy_at nodate '' 30)

t_run_split env TRACE_CONFIG="$FRESH" sh "$TRACE" summary --by model
s_assert_status 0 "summary over a table checked today exits 0"
case $S_ERR in
*'last checked'*) fail "a table checked today still drew the staleness advisory: $S_ERR" ;;
*) pass "and says nothing about staleness — inside the window is silence" ;;
esac

t_run_split env TRACE_CONFIG="$STALE" sh "$TRACE" summary --by model
s_assert_status 0 "summary over a table older than the window still exits 0 — an advisory is never a failure"
case $S_ERR in
*'last checked'*"$ANCIENT"*) pass "and names the date the table carries, on stderr" ;;
*) fail "stderr did not carry the advisory with $ANCIENT: $S_ERR" ;;
esac
# The PHRASE and not the number: `*30*` also matched any 30 in the scratch path
# the advisory prints, and mktemp names carry digits — so the leg could pass
# without the window ever being named (L-4, review of PR #294).
case $S_ERR in
*'30-day window'*) pass "and the window it is past, so the operator can tell which policy line spoke" ;;
*) fail "the advisory does not name the 30-day window: $S_ERR" ;;
esac
case $S_OUT in
*'last checked'* | *'stale'*) fail "the advisory leaked onto stdout, into the table a reader parses: $S_OUT" ;;
*) pass "and stdout carries the table alone" ;;
esac
STALE_OUT=$S_OUT
t_run_split env TRACE_CONFIG="$WIDE" sh "$TRACE" summary --by model
[ "$S_OUT" = "$STALE_OUT" ] &&
	pass "a wider window prints the same table — the advisory changes no answer" ||
	fail "the table differed between two windows: the advisory is not advisory"
case $S_ERR in
*'last checked'*) fail "a 99999-day window still advised: the window is hardcoded, not read from policy" ;;
*) pass "and says nothing: the window comes from TRACE_PRICES_STALE_DAYS, not from a number in the script" ;;
esac

t_run_split env TRACE_CONFIG="$NOWIN" sh "$TRACE" summary --by model
case $S_ERR in
*'last checked'*) fail "an EMPTY window still advised — empty must mean no window, as it does for TRACE_DIR: $S_ERR" ;;
*) pass "an empty window is no window and no advisory, the way every other empty policy value is no opinion" ;;
esac
s_assert_status 0 "and the command is unaffected"

t_run_split env TRACE_CONFIG="$NODATE" sh "$TRACE" summary --by model
case $S_ERR in
*'last checked'*) fail "a policy file with no 'Last checked' line advised anyway — about a date nobody wrote: $S_ERR" ;;
*) pass "a window with no dated line is silent — there is nothing to compare"  ;;
esac

t_run_split env TRACE_CONFIG="$STALE" TRACE_QUIET=1 sh "$TRACE" summary --by model
[ -z "$S_ERR" ] &&
	pass "TRACE_QUIET=1 silences the advisory, the way it silences the unconfigured note" ||
	fail "TRACE_QUIET=1 left stderr carrying: $S_ERR"

t_run_split env TRACE_CONFIG="$STALE" sh "$TRACE" export --csv
s_assert_status 0 "export --csv over a stale table exits 0"
case $S_ERR in
*'last checked'*) pass "and advises too — the priced export is the other place a rotten price reaches a spreadsheet" ;;
*) fail "export --csv did not advise: $S_ERR" ;;
esac
t_run_split env TRACE_CONFIG="$STALE" sh "$TRACE" export
case $S_ERR in
*'last checked'*) fail "the JSONL export advised about a price it never applied: $S_ERR" ;;
*) pass "the JSONL export stays silent — it prices nothing, so a price's age is not its business" ;;
esac

BADWIN=$(policy_at badwin "$ANCIENT" thirty)
assert_status 2 "a window that is not a number of days is exit 2 — the operator error a malformed price is" -- \
	env TRACE_CONFIG="$BADWIN" sh "$TRACE" summary --by model
assert_out_has "TRACE_PRICES_STALE_DAYS"
# A window past the shell's integer width made the comparison print
# '[: …: integer expected' out of a SHIPPED script (L-1, review of PR #294).
# Refused with the rest of the malformed values instead.
WIDEWIN=$(policy_at widewin "$ANCIENT" 999999999999999999999999999999)
t_run_split env TRACE_CONFIG="$WIDEWIN" sh "$TRACE" summary --by model
s_assert_status 2 "a window too wide for the shell's arithmetic is refused, not attempted"
case $S_ERR in
*'integer expected'*) fail "the shell's own arithmetic error leaked out of a shipped script: $S_ERR" ;;
*) pass "and says so in the script's own words, never the shell's" ;;
esac

# An impossible CALENDAR date passed the shape check and produced a number: a
# table dated 2026-00-00 advised '302 days ago' about a day that does not
# exist, and 2026-99-99 computed a date in the FUTURE and went silent — the
# worse of the two, because silence is what a fresh table looks like (M-1,
# review of PR #294).
for bad in 2026-00-00 2026-99-99 2026-13-01 2026-01-32; do
	BADDATE=$(policy_at "baddate$(printf '%s' "$bad" | tr -d -)" "$bad" 30)
	t_run_split env TRACE_CONFIG="$BADDATE" sh "$TRACE" summary --by model
	s_assert_status 2 "'Last checked: $bad' is refused — the shape is not the calendar"
done

# The advisory is printed by a SHIPPED script, so it may not send a consumer to
# a file that only exists in this repo — the rule every SKILL.md keeps.
assert_file_lacks "$TRACE" "trace-prices.kit.sh" \
	"scripts/trace.sh ships; a kit-only path in its advisory would point a consumer at a file bootstrap deleted"

# ---------------------------------------------------------------------------
banner "1b. The date the advisory reads is the OPERATOR'S, and the day count is right"
# ---------------------------------------------------------------------------
# C-1, the finding that blocked this branch: the SHIPPED policy file's own
# EXAMPLE line carried a real date (2026-01-31), which matched the advisory's
# regex — so a consumer who did exactly what that file tells them (set the
# window, write today's date) was told their table was 240 days stale, naming a
# date they never wrote. The example is the first such line in the file, and
# first wins.
consumer_policy() { # <label> <appended lines…> — the shipped file, plus a tail
	_cp=$SCRATCH/consumer.$1.sh
	shift
	cp "$SHIPPED" "$_cp"
	{
		printf "TRACE_DIR='%s'\n" "$SUM"
		printf "TRACE_PRICE_M1='3,15,3.75,0.30'\n"
		printf "TRACE_PRICES_STALE_DAYS='30'\n"
		for _cl in "$@"; do printf '%s\n' "$_cl"; done
	} >>"$_cp"
	printf '%s\n' "$_cp"
}
CONS_DATED=$(consumer_policy dated "# Last checked: $ANCIENT")
t_run_split env TRACE_CONFIG="$CONS_DATED" sh "$TRACE" summary --by model
case $S_ERR in
*"$ANCIENT"*) pass "a consumer's own dated line is what the advisory names" ;;
*) fail "the advisory named something other than the consumer's date: $S_ERR" ;;
esac
case $S_ERR in
*2026-01-31*) fail "the advisory read a date out of the SHIPPED file's prose, not the consumer's line: $S_ERR" ;;
*) pass "and no date out of the shipped file's own instructions" ;;
esac
CONS_UNDATED=$(consumer_policy undated)
t_run_split env TRACE_CONFIG="$CONS_UNDATED" sh "$TRACE" summary --by model
[ -z "$S_ERR" ] &&
	pass "and the shipped file with a window but no dated line says nothing at all — its example is not a claim" ||
	fail "the shipped file advised about a date nobody wrote: $S_ERR"

# H-2: the day count had no load-bearing test — both dates were 2465 days apart
# or identical, so `y*365 + m*31 + d` would have passed every leg. `date` is
# shimmed rather than the arithmetic called directly, because the seam is the
# command and a suite that reaches inside the script tests the wrong thing.
# POSIX: no `date -d` anywhere.
REALDATE=$(command -v date)
mkdir -p "$SCRATCH/bin"
{
	printf '#!/bin/sh\n'
	printf 'case "$*" in\n'
	printf '"-u +%%Y-%%m-%%d") printf %%s\\\\n "$TP_TODAY"; exit 0 ;;\n'
	printf 'esac\n'
	printf 'exec %s "$@"\n' "$REALDATE"
} >"$SCRATCH/bin/date"
chmod +x "$SCRATCH/bin/date"
t_run_split env PATH="$SCRATCH/bin:$PATH" TP_TODAY=2024-03-01 sh -c 'date -u +%Y-%m-%d'
s_assert_out_is 2024-03-01 "the date shim pins today for the run"

# days_apart <last checked> <pinned today> <window> — the advisory's own age.
age_of() {
	_ap=$(policy_at "age$(printf '%s%s%s' "$1" "$2" "$3" | tr -d -)" "$1" "$3")
	t_run_split env PATH="$SCRATCH/bin:$PATH" TP_TODAY="$2" TRACE_CONFIG="$_ap" sh "$TRACE" summary --by model
}
# A leap day: 2024-02-28 to 2024-03-01 is TWO days, not one and not three.
age_of 2024-02-28 2024-03-01 1
case $S_ERR in
*'2 days ago'*) pass "2024-02-28 to 2024-03-01 is 2 days — 29 February is counted" ;;
*) fail "the leap-day span was not 2 days: $S_ERR" ;;
esac
age_of 2024-02-28 2024-03-01 2
[ -z "$S_ERR" ] && pass "and a window of exactly that many days is silent — 'older than' is strict" ||
	fail "a window equal to the age still advised: $S_ERR"
# A year boundary: the naive formula puts these 738 days apart.
age_of 2023-12-31 2024-01-01 0
case $S_ERR in
*'1 days ago'*) pass "2023-12-31 to 2024-01-01 is 1 day across a year boundary" ;;
*) fail "the year-boundary span was not 1 day: $S_ERR" ;;
esac
# A non-leap February, and a month with 30 days, both under one window.
age_of 2023-02-28 2023-03-01 0
case $S_ERR in
*'1 days ago'*) pass "and 2023-02-28 to 2023-03-01 is 1 day — 2023 has no 29 February" ;;
*) fail "the non-leap span was not 1 day: $S_ERR" ;;
esac
age_of 2026-04-30 2026-05-01 0
case $S_ERR in
*'1 days ago'*) pass "and 2026-04-30 to 2026-05-01 is 1 day — April has 30" ;;
*) fail "the 30-day-month span was not 1 day: $S_ERR" ;;
esac

# ---------------------------------------------------------------------------
banner "2. --check compares the table against the sources and says which way it drifted"
# ---------------------------------------------------------------------------
[ -f "$REFRESH" ] && pass "scripts/trace-prices.kit.sh exists" || fail "there is no scripts/trace-prices.kit.sh"
assert_status 2 "no mode is a usage error — a script that rewrites a policy file asks to be told which" -- \
	sh "$REFRESH"
assert_out_has "--check"

if command -v node >/dev/null 2>&1; then
	# A COPY of the twin, so every write below lands in scratch. The copy is the
	# real file, because "rewrites the five entries and leaves the rest alone"
	# is only worth asserting against the bytes the kit actually ships itself.
	COPY=$SCRATCH/twin.sh
	cp "$TWIN" "$COPY"

	t_run_split env TRACE_CONFIG="$COPY" sh "$REFRESH" --check \
		--source "$FIX/litellm-moved.json" --cross "$FIX/openrouter-moved.json"
	s_assert_status 1 "--check against a source that moved is exit 1 — drift is a verdict, not an error"
	s_assert_out_has "7.77,33.33,9.71,0.77" "and prints what the primary source now says"
	s_assert_out_has "TRACE_PRICE_CLAUDE_FABLE_5_1" "named by the variable the table carries, so the operator can find the line"
	s_assert_out_has "drift" "and says the word"
	# The current value has to be in the report too: a report that showed only
	# the new numbers would leave the operator unable to see what moved.
	CUR_FABLE=$(sed -n "s/^TRACE_PRICE_CLAUDE_FABLE_5_1='\\(.*\\)'\$/\\1/p" "$COPY")
	s_assert_out_has "$CUR_FABLE" "beside the value the table holds today"

	t_run_split env TRACE_CONFIG="$COPY" sh "$REFRESH" --check \
		--source "$SCRATCH/no-such-source.json" --cross "$FIX/openrouter-moved.json"
	s_assert_status 2 "a source that cannot be fetched is exit 2 — a source failure, never 'no drift'"

	# A primary that does not know one of the five is a source failure and not a
	# shrug: the wrong implementation writes four entries and leaves the fifth
	# silently dated as if it had been checked.
	t_run_split env TRACE_CONFIG="$COPY" sh "$REFRESH" --check \
		--source "$FIX/litellm-partial.json" --cross "$FIX/openrouter-moved.json"
	s_assert_status 2 "a primary source missing one of the mapped models is exit 2"
	s_assert_out_has "gpt-6-astra" "and names the model it could not price"

	t_run_split env TRACE_CONFIG="$COPY" sh "$REFRESH" --check \
		--source "$FIX/litellm-moved.json" --cross "$FIX/openrouter-disagrees.json"
	s_assert_status 2 "two sources disagreeing past the threshold is exit 2 — the refusal, in check mode too"
	s_assert_out_has "6.66" "and prints the primary's figure"
	s_assert_out_has "13.32" "and the cross-check's, so the operator can pick the tie-breaker"

	# TWO SOURCES IS THE RULE, so the cross-check failing is a refusal too — both
	# of its shapes, neither of which had a leg (M-3, review of PR #294): a cross
	# source that does not know one of the five, and one that is valid JSON of
	# the wrong shape entirely.
	t_run_split env TRACE_CONFIG="$COPY" sh "$REFRESH" --check \
		--source "$FIX/litellm-moved.json" --cross "$FIX/openrouter-partial.json"
	s_assert_status 2 "a cross-check source missing one of the mapped models is exit 2 — one source is a number nobody checked"
	s_assert_out_has "openai/gpt-6-astra" "and names the id it looked for"
	t_run_split env TRACE_CONFIG="$COPY" sh "$REFRESH" --check \
		--source "$FIX/litellm-moved.json" --cross "$FIX/litellm-moved.json"
	s_assert_status 2 "a cross-check source of the wrong shape is exit 2, not an empty cross-check that agrees with everything"
	case $S_OUT$S_ERR in
	*data*) pass "and says which shape it wanted" ;;
	*) fail "the wrong-shape refusal does not name the shape it expected" ;;
	esac

	# THE TABLE, not just the source, can be missing an entry. `read` with a tab
	# IFS collapsed the empty `table` column and shifted every field left, so a
	# mapped model with no TRACE_PRICE_ line at all was reported `same`, counted
	# as neither drift nor refusal, and a write re-dated the file with the entry
	# still absent (H-1, review of PR #294). The refresh REWRITES lines; it does
	# not add them, so a missing line is a refusal.
	GAP=$SCRATCH/twin.gap.sh
	grep -v '^TRACE_PRICE_CODEX_GPT_6_ASTRA=' "$TWIN" >"$GAP"
	cp "$GAP" "$SCRATCH/twin.gap.before.sh"
	t_run_split env TRACE_CONFIG="$GAP" sh "$REFRESH" --check \
		--source "$FIX/litellm-moved.json" --cross "$FIX/openrouter-moved.json"
	s_assert_status 2 "a table with no line for a mapped model is exit 2, never 'same'"
	s_assert_out_has "TRACE_PRICE_CODEX_GPT_6_ASTRA" "and names the variable the table is missing"
	s_assert_out_lacks "same: every entry" "and never reports the whole table as matching"
	t_run_split env TRACE_CONFIG="$GAP" sh "$REFRESH" --write \
		--source "$FIX/litellm-moved.json" --cross "$FIX/openrouter-moved.json"
	s_assert_status 2 "the write refuses the same way"
	cmp -s "$SCRATCH/twin.gap.before.sh" "$GAP" &&
		pass "and re-dates nothing — a fresh 'Last checked' over a missing entry is the worst of both" ||
		fail "the refused write still touched the policy file (the date, most likely)"

	# The threshold is read as a number, and '.' passed the shell's shape check
	# while being NaN in the comparison — so the refusal never fired and a
	# disputed price would have been written (M-2, review of PR #294).
	sed "s/^TRACE_PRICES_DISAGREE_PCT=.*/TRACE_PRICES_DISAGREE_PCT='.'/" "$COPY" >"$SCRATCH/twin.dot.sh"
	t_run_split env TRACE_CONFIG="$SCRATCH/twin.dot.sh" sh "$REFRESH" --check \
		--source "$FIX/litellm-moved.json" --cross "$FIX/openrouter-disagrees.json"
	s_assert_status 2 "a threshold that is not a number is exit 2 — never a comparison that is always false"
	# On STDERR: it is a diagnostic about the policy file, not an answer.
	s_assert_err_has "TRACE_PRICES_DISAGREE_PCT" "and names the policy line to fix"

	# ---------------------------------------------------------------------------
	banner "3. A write rewrites the five entries, the date and the source revisions — and nothing else"
	# ---------------------------------------------------------------------------
	HEAD_BEFORE=$(git -C "$KIT" rev-parse HEAD)
	STATUS_BEFORE=$(git -C "$KIT" status --porcelain)
	t_run_split env TRACE_CONFIG="$COPY" sh "$REFRESH" --write \
		--source "$FIX/litellm-moved.json" --cross "$FIX/openrouter-moved.json"
	s_assert_status 0 "a write against two agreeing sources exits 0"
	s_assert_out_has "TRACE_PRICE_CLAUDE_FABLE_5_1" "and prints the diff it just made, for the operator to read before committing"

	for pair in \
		"CLAUDE_FABLE_5_1 7.77,33.33,9.71,0.77" \
		"CLAUDE_OPUS_5_5 6.66,22.22,8.32,0.66" \
		"CLAUDE_HAIKU_4_5_20251001 1.11,4.44,1.38,0.11" \
		"CODEX_GPT_5_6_SOL 5.55,21.21,6.93,0.55" \
		"CODEX_GPT_6_ASTRA 9.99,44.44,12.48,0.99"; do
		_var=${pair%% *}
		_want=${pair#* }
		_got=$(sed -n "s/^TRACE_PRICE_$_var='\\(.*\\)'\$/\\1/p" "$COPY")
		[ "$_got" = "$_want" ] &&
			pass "TRACE_PRICE_$_var now reads $_want — the source's per-token figures, times a million" ||
			fail "TRACE_PRICE_$_var reads '$_got', not '$_want'"
	done
	# The fold is not a guess: the codex entries prove the agent-harness prefix a
	# dispatched model carries in an event survives into the variable name while
	# the source is looked up without it.
	grep -q "^TRACE_PRICE_CODEX_GPT_6_ASTRA='9.99," "$COPY" &&
		pass "a cross-harness model keeps its codex: prefix in the variable and is looked up in the source without it" ||
		fail "the codex-prefixed entry did not resolve"

	grep -q "Last checked: $TODAY" "$COPY" &&
		pass "the table's header now says it was checked today" ||
		fail "the header does not say 'Last checked: $TODAY': $(grep -n 'Last checked' "$COPY")"
	grep -q '^#   primary: .*litellm-moved.json' "$COPY" &&
		pass "the Sources block records which primary source answered" ||
		fail "no primary revision line naming the source: $(grep -n '^#   primary' "$COPY")"
	grep -qE '^#   primary: .*[0-9a-f]{40}' "$COPY" &&
		pass "with the revision of the bytes it read — git's own hash of the payload" ||
		fail "the primary revision line carries no content hash"
	grep -q '^#   cross: .*openrouter-moved.json' "$COPY" &&
		pass "and which cross-check source agreed with it" ||
		fail "no cross revision line: $(grep -n '^#   cross' "$COPY")"

	# WHICH lines changed, not how many: the date line legitimately does not
	# change on a day the table was already checked, so a count would be a
	# calendar-dependent assertion. Anything outside the four owned shapes is a
	# rewrite of prose the script has no business touching.
	diff "$TWIN" "$COPY" >"$SCRATCH/twin.diff" 2>/dev/null
	STRAY=$(sed -n 's/^[<>] //p' "$SCRATCH/twin.diff" |
		grep -v -e "^TRACE_PRICE_" -e "Last checked: " -e "^#   primary: " -e "^#   cross: " |
		grep -c . || true)
	[ "${STRAY:-0}" = 0 ] &&
		pass "and every other byte of the twin is untouched — no prose, no comment, no other variable" ||
		fail "the write changed lines it does not own:$(printf '\n')$(sed -n 's/^[<>] //p' "$SCRATCH/twin.diff" | grep -v -e '^TRACE_PRICE_' -e 'Last checked: ' -e '^#   primary: ' -e '^#   cross: ' | grep . | sed 's/^/        | /')"
	NEWVALS=$(grep -c '^> TRACE_PRICE_' "$SCRATCH/twin.diff" || true)
	[ "${NEWVALS:-0}" = 5 ] && pass "exactly five price lines were rewritten" || fail "$NEWVALS price lines changed, not five"

	# Still a policy file: a rewrite that broke the shell syntax would be found
	# by the next `summary`, which is too late to be a test.
	t_run_split sh -n "$COPY"
	s_assert_status 0 "the rewritten file is still valid POSIX sh"
	t_run_split env TRACE_CONFIG="$COPY" TRACE_DIR="$SUM" sh "$TRACE" summary --by model
	s_assert_status 0 "and the trace script still reads it"

	[ "$(git -C "$KIT" rev-parse HEAD)" = "$HEAD_BEFORE" ] &&
		pass "the refresh committed nothing — HEAD is where it was" ||
		fail "the refresh moved HEAD: it committed for the operator"
	[ "$(git -C "$KIT" status --porcelain)" = "$STATUS_BEFORE" ] &&
		pass "and staged nothing, and touched no file in the checkout — the write went where TRACE_CONFIG pointed" ||
		fail "the refresh changed the working tree outside the policy file it was given"

	# Idempotent: the second run has nothing to move, so --check is quiet and a
	# write is a re-dating rather than a change of numbers.
	t_run_split env TRACE_CONFIG="$COPY" sh "$REFRESH" --check \
		--source "$FIX/litellm-moved.json" --cross "$FIX/openrouter-moved.json"
	s_assert_status 0 "--check right after a write is exit 0 — same, not drift"
	s_assert_out_has "same" "and says so"

	# The refusal must leave the file ALONE. A script that wrote the primary's
	# numbers and then noticed the disagreement would have already destroyed the
	# operator's own last-checked claim.
	cp "$COPY" "$SCRATCH/twin.before-refusal.sh"
	t_run_split env TRACE_CONFIG="$COPY" sh "$REFRESH" --write \
		--source "$FIX/litellm-moved.json" --cross "$FIX/openrouter-disagrees.json"
	s_assert_status 2 "a write refuses while the two sources disagree past the threshold"
	cmp -s "$SCRATCH/twin.before-refusal.sh" "$COPY" &&
		pass "and the policy file is byte-identical — a refusal writes nothing at all" ||
		fail "the refused write still modified the policy file"

	# The threshold is policy, not a constant: widening it past the planted
	# disagreement must let the same pair through.
	sed "s/^TRACE_PRICES_DISAGREE_PCT=.*/TRACE_PRICES_DISAGREE_PCT='150'/" "$COPY" >"$SCRATCH/twin.wide.sh"
	t_run_split env TRACE_CONFIG="$SCRATCH/twin.wide.sh" sh "$REFRESH" --check \
		--source "$FIX/litellm-moved.json" --cross "$FIX/openrouter-disagrees.json"
	# The VERDICT and not "anything but 2": `!= 2` passed on a crash (126, 127)
	# as readily as on the intended answer, and the intended answer is known —
	# that pair drifts from the twin (L-4, review of PR #294).
	s_assert_status 0 "a threshold wide enough to cover the planted gap stops refusing — the number comes from policy"
	s_assert_out_has "same:" "and reports the plain verdict, which by here is 'same': the write above already took these numbers"
else
	echo "  skip  node is not on PATH — the refresh script's source legs not run (the JSON is node's job, as it is for the adapter's extractor)"
fi

# ---------------------------------------------------------------------------
banner "4. The wiring: kit-only, in CI, in the README, and in both policy files"
# ---------------------------------------------------------------------------
for f in scripts/trace-prices.kit.sh tests/trace-prices.test.sh \
	tests/fixtures/prices/README.md \
	tests/fixtures/prices/litellm-moved.json \
	tests/fixtures/prices/litellm-partial.json \
	tests/fixtures/prices/openrouter-moved.json \
	tests/fixtures/prices/openrouter-disagrees.json \
	tests/fixtures/prices/openrouter-partial.json; do
	grep -q "[ \"]$f[ \"]" "$KIT/bootstrap.sh" &&
		pass "$f is on bootstrap's KIT_ONLY list" ||
		fail "$f is not on KIT_ONLY — a consumer would receive it (the script names a vendor URL and this repo's own model ids)"
done
grep '^rmdir ' "$KIT/bootstrap.sh" | grep -q 'tests/fixtures/prices' &&
	pass "and bootstrap removes the fixture directory once its files are gone" ||
	fail "bootstrap's rmdir line does not name tests/fixtures/prices — a stamped project keeps an empty directory"

grep -q 'sh tests/trace-prices.test.sh' "$KIT/.github/workflows/kit-ci.yml" &&
	pass "kit-ci.yml runs this suite" ||
	fail "no CI job runs tests/trace-prices.test.sh — it is a suite in name only"
assert_file_has "$KIT/README.md" "tests/trace-prices.test.sh" "README.md names every suite"
assert_file_has "$KIT/AGENTS.md" "trace-prices.kit.sh" "the quick reference gains a row per script this repo gains"

# The shipped policy file: the window documented and EMPTY, the three source
# suggestions named, and still not one price asserted as fact.
assert_file_has "$SHIPPED" "TRACE_PRICES_STALE_DAYS=''" "the window ships empty — no window, no advisory, no kit deciding for a consumer"
for src in LiteLLM OpenRouter; do
	assert_file_has "$SHIPPED" "$src" "the shipped comments name the machine-readable sources"
done
grep -qi "tie-break" "$SHIPPED" &&
	pass "and the vendors' own pages as the human tie-breaker — the third suggestion" ||
	fail "the shipped policy file does not name the human tie-breaker"
grep -q '^TRACE_PRICE_' "$SHIPPED" &&
	fail "the shipped policy file ASSIGNS a price — naming a source must not become stating a number" ||
	pass "and still assigns no price: the sources are named, no figure is claimed"

# The twin: both numbers the kit decided for itself.
grep -qE "^TRACE_PRICES_STALE_DAYS='[0-9]+'" "$TWIN" &&
	pass "the kit twin sets its own staleness window" ||
	fail "scripts/trace.kit.config.sh sets no TRACE_PRICES_STALE_DAYS"
grep -qE "^TRACE_PRICES_DISAGREE_PCT='[0-9.]+'" "$TWIN" &&
	pass "and the threshold two sources may differ by before a refresh refuses" ||
	fail "scripts/trace.kit.config.sh sets no TRACE_PRICES_DISAGREE_PCT"
assert_file_has "$TWIN" "#   primary: " "the twin carries the revision line a refresh rewrites"
assert_file_has "$TWIN" "#   cross: " "and the cross-check's"

t_done "tests/trace-prices.test.sh"
