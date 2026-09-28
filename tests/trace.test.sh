#!/bin/sh
# tests/trace.test.sh — the trace script records a decision and shows it back.
#
# scripts/trace.sh is the first tracer bullet of PRD #237 (ticket #247): one
# JSON line per decision, appended to a trace directory the policy file names,
# read back by subject. What this suite holds it to is the contract a later
# session builds on — the exit codes, the split streams, the escaper, the
# closed kind vocabulary, and the one property that makes the trace survive
# the kit's own way of working: an emit from inside a linked worktree lands
# under the ROOT checkout, so pruning the worktree loses nothing.
#
# Every case is driven RED first (hard rule 9): the suite was written against
# no script at all, and each assertion names the wrong implementation it
# would catch.
#
# Usage: sh tests/trace.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

KIT="$ROOT"
TRACE="$KIT/scripts/trace.sh"
TODAY=$(date -u +%Y-%m-%d)

# A policy file with the given TRACE_DIR value, written to scratch, named
# FROM THE VALUE: the first draft rewrote one path, so every handle pointed at
# the last value written and an "unconfigured" case read a configured trace;
# the second draft counted calls, and a counter inside `$(...)` runs in a
# subshell and never advances. A name derived from the value cannot collide
# with a different value or drift with the caller.
policy() {
	_pn=$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')
	[ -n "$_pn" ] || _pn=off
	printf "TRACE_DIR='%s'\n" "$1" >"$SCRATCH/policy.$_pn.sh"
	printf '%s\n' "$SCRATCH/policy.$_pn.sh"
}

banner "1. Unconfigured is a working state: the emit is a no-op, said once, silenced by TRACE_QUIET"
OFF=$(policy '')
# Hermetic: a fixture repo carrying the script and an EMPTY policy file, so
# "wrote nothing" is asserted against a tree that had nothing — the checkout
# this suite runs from may legitimately hold a trace already (H-6, PR #257).
t_repo
QUIET_REPO=$REPO
mkdir -p "$QUIET_REPO/scripts"
cp "$TRACE" "$QUIET_REPO/scripts/trace.sh"
printf "TRACE_DIR=''\n" >"$QUIET_REPO/scripts/trace.config.sh"
t_run_split env TRACE_CONFIG=$OFF sh "$TRACE" emit kind=note reason=hello
[ "$S_STATUS" = 0 ] && pass "an unconfigured emit exits 0" || fail "an unconfigured emit exited $S_STATUS, not 0"
[ -z "$S_OUT" ] && pass "and prints nothing on stdout" || fail "stdout carried: $S_OUT"
case $S_ERR in *unconfigured*) pass "and says 'unconfigured' on stderr" ;; *) fail "stderr did not say unconfigured: $S_ERR" ;; esac
( cd "$QUIET_REPO" && sh scripts/trace.sh emit kind=note reason=hello 2>/dev/null )
[ -z "$(find "$QUIET_REPO" -name '*.jsonl' -o -name events -o -name .trace 2>/dev/null)" ] &&
	pass "and wrote nothing anywhere under a fixture whose policy file is empty" || fail "an unconfigured emit wrote under $QUIET_REPO: $(find "$QUIET_REPO" -name '*.jsonl' -o -name .trace)"
t_run_split env TRACE_CONFIG=$OFF TRACE_QUIET=1 sh "$TRACE" emit kind=note reason=hello
[ -z "$S_ERR" ] && pass "TRACE_QUIET=1 silences the note" || fail "TRACE_QUIET=1 still printed: $S_ERR"
t_run_split env TRACE_CONFIG=$OFF sh "$TRACE" dir
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && pass "dir prints nothing when unconfigured" || fail "dir printed '$S_OUT' (exit $S_STATUS)"

banner "2. A policy file named explicitly and missing is a caller error"
assert_status 2 "TRACE_CONFIG pointing nowhere is exit 2" -- env TRACE_CONFIG="$SCRATCH/no-such-policy.sh" sh "$TRACE" emit kind=note reason=x
assert_out_has "does not exist"

banner "3. A configured emit appends one line to today's file, fields in a fixed order"
DIR="$SCRATCH/abs-trace"
ON=$(policy "$DIR")
t_run_split env TRACE_CONFIG=$ON sh "$TRACE" emit kind=ticket.write subject='ticket:#34' related='prd:#12' tier=implementer domain=content outcome=stamped reason='the first slice' data.position=1/7 data.label=''
[ "$S_STATUS" = 0 ] && pass "emit exits 0" || fail "emit exited $S_STATUS: $S_ERR"
[ -z "$S_OUT" ] && [ -z "$S_ERR" ] && pass "and is silent on both streams" || fail "emit was not silent — out: '$S_OUT' err: '$S_ERR'"
FILE="$DIR/events/$TODAY.jsonl"
[ -f "$FILE" ] && pass "today's file exists at events/$TODAY.jsonl" || fail "no $FILE"
[ "$(wc -l <"$FILE" | tr -d ' ')" = 1 ] && pass "with exactly one line" || fail "expected one line, got $(wc -l <"$FILE")"
LINE=$(cat "$FILE")
case $LINE in '{"v":1,"ts":"'*) pass "the line opens with the schema version and the timestamp" ;; *) fail "unexpected opening: $LINE" ;; esac
case $LINE in *'"kind":"ticket.write","subject":"ticket:#34","related":"prd:#12","tier":"implementer","domain":"content","outcome":"stamped","reason":"the first slice","data":{"position":"1/7","label":""}}') pass "fields follow the documented order, absent optionals omitted, empty data values kept" ;; *) fail "field order or content wrong: $LINE" ;; esac
case $LINE in *'"id":"'[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-*) pass "the id opens with a sortable UTC stamp" ;; *) fail "id shape wrong: $LINE" ;; esac
t_run_split env TRACE_CONFIG=$ON sh "$TRACE" emit --dry-run kind=note reason=dry
case $S_OUT in '{"v":1,'*'"kind":"note"'*'"reason":"dry"}') pass "--dry-run prints the line it would append" ;; *) fail "--dry-run printed: $S_OUT" ;; esac
[ "$(wc -l <"$FILE" | tr -d ' ')" = 1 ] && pass "and writes nothing" || fail "--dry-run appended a line"
t_run_split env TRACE_CONFIG=$ON sh "$TRACE" emit kind=session.usage subject='session:abc' model=m tok_in=10 tok_out=20 tok_cache_w=0 tok_cache_r=5
case $(tail -n 1 "$FILE") in *'"model":"m","tok_in":10,"tok_out":20,"tok_cache_w":0,"tok_cache_r":5}') pass "token counts are written as bare numbers" ;; *) fail "token fields wrong: $(tail -n 1 "$FILE")" ;; esac
assert_status 2 "a non-numeric token count is refused" -- env TRACE_CONFIG="$ON" sh "$TRACE" emit kind=session.usage tok_in=ten

banner "4. The escaper: quotes, backslashes, tabs and non-ASCII survive; a newline is refused"
TAB=$(printf '\t')
MARK=$(t_mark NOT_A_MARK)
t_run_split env TRACE_CONFIG=$ON sh "$TRACE" emit kind=note reason="say \"hi\" \\ back${TAB}tab é ${MARK}"
[ "$S_STATUS" = 0 ] && pass "the awkward reason is accepted" || fail "escaper refused a legal value: $S_ERR"
case $(tail -n 1 "$FILE") in *'"reason":"say \"hi\" \\ back\ttab é '"$MARK"'"}') pass "quotes, backslashes and tabs are escaped, UTF-8 and the mark-shaped literal pass through" ;; *) fail "escaping wrong: $(tail -n 1 "$FILE")" ;; esac
if command -v node >/dev/null 2>&1; then
	node -e 'const fs=require("fs");for(const l of fs.readFileSync(process.argv[1],"utf8").split("\n"))if(l)JSON.parse(l)' "$FILE" 2>/dev/null &&
		pass "every line so far is JSON a real parser accepts" ||
		fail "a line is not valid JSON"
else
	echo "  skip  node is not on PATH — JSON.parse check not run"
fi
NL=$(printf 'two\nlines')
t_run_split env TRACE_CONFIG=$ON sh "$TRACE" emit kind=note reason="$NL"
[ "$S_STATUS" = 2 ] && pass "a value with a newline is exit 2" || fail "a newline was accepted (exit $S_STATUS)"
case $S_ERR in *blob*) pass "and the refusal points at --blob" ;; *) fail "the refusal did not point at --blob: $S_ERR" ;; esac

banner "5. The vocabulary is closed and the grammar is checked at emit"
assert_status 2 "an unknown kind is exit 2" -- env TRACE_CONFIG="$ON" sh "$TRACE" emit kind=bogus
assert_out_has "kind"
assert_status 2 "a subject with a space is exit 2" -- env TRACE_CONFIG="$ON" sh "$TRACE" emit kind=note subject='ticket 34'
assert_status 2 "a subject with no type prefix is exit 2" -- env TRACE_CONFIG="$ON" sh "$TRACE" emit kind=note subject='34'
assert_status 2 "an unknown top-level key is exit 2 (almost always a typo for data.)" -- env TRACE_CONFIG="$ON" sh "$TRACE" emit kind=note reasn=x
assert_status 2 "a capitalised key is exit 2" -- env TRACE_CONFIG="$ON" sh "$TRACE" emit kind=note Data.x=1
assert_status 2 "no kind at all is exit 2" -- env TRACE_CONFIG="$ON" sh "$TRACE" emit reason=x
assert_status 2 "an unknown subcommand is exit 2" -- env TRACE_CONFIG="$ON" sh "$TRACE" frobnicate
assert_status 2 "a leading-zero token count is exit 2 — it is not a JSON integer (H-1)" -- env TRACE_CONFIG="$ON" sh "$TRACE" emit kind=session.usage tok_in=01
assert_status 2 "two adjacent kinds in one value are exit 2 — membership is per entry, not substring (H-4)" -- env TRACE_CONFIG="$ON" sh "$TRACE" emit 'kind=run.start run.end'
assert_status 2 "a field name with a space is exit 2, never a membership hit or an eval" -- env TRACE_CONFIG="$ON" sh "$TRACE" emit kind=note 'subject related=x'
[ "$(wc -l <"$FILE" | tr -d ' ')" = 3 ] && pass "none of the refusals wrote a line" || fail "a refused emit still wrote: $(wc -l <"$FILE") lines"

banner "6. A relative TRACE_DIR resolves to the ROOT checkout — from inside a linked worktree too"
t_repo
mkdir -p "$REPO/scripts"
cp "$TRACE" "$REPO/scripts/trace.sh"
printf "TRACE_DIR='.trace'\n" >"$REPO/scripts/trace.config.sh"
t_commit "$REPO" "chore: carry the trace script" >/dev/null
git -C "$REPO" worktree add -q "$REPO/worktree/w" -b feat/w 2>/dev/null || fail "could not add a linked worktree"
( cd "$REPO/worktree/w" && sh scripts/trace.sh emit kind=note subject='worktree:w' reason='from the worktree' ) ||
	fail "emit from inside the worktree failed"
[ -f "$REPO/.trace/events/$TODAY.jsonl" ] && pass "the event landed under the root checkout's .trace/" || fail "no event under $REPO/.trace"
[ ! -e "$REPO/worktree/w/.trace" ] && pass "and nothing was written inside the worktree" || fail "a .trace/ appeared inside the worktree"
( cd "$REPO/worktree/w" && sh scripts/trace.sh dir ) | grep -qx "$REPO/.trace" &&
	pass "dir, from the worktree, names the root's directory" || fail "dir from the worktree printed something else"
git -C "$REPO" worktree remove --force "$REPO/worktree/w" 2>/dev/null || fail "could not remove the worktree"
grep -q 'from the worktree' "$REPO/.trace/events/$TODAY.jsonl" && pass "the event survives the worktree's removal" || fail "the event went with the worktree"
# The policy file next to the script is order 3 — and order 2, the script's
# own repo root, must never be the CALLER's cwd repo: a foreign clone's policy
# file is code nobody asked to run.
FOREIGN="$SCRATCH/foreign"; mkdir -p "$FOREIGN/scripts"
printf "TRACE_DIR='%s'\n" "$SCRATCH/foreign-trace" >"$FOREIGN/scripts/trace.config.sh"
git -C "$FOREIGN" init -q -b main 2>/dev/null
( cd "$FOREIGN" && sh "$REPO/scripts/trace.sh" dir ) | grep -qx "$REPO/.trace" &&
	pass "standing in a foreign repo does not change which policy file is read" || fail "the cwd's repo leaked into policy discovery"
# Git exports GIT_DIR and GIT_WORK_TREE into hooks and some callers inherit
# them; a pinned pair makes rev-parse answer for the pinned repo, so both
# anchored lookups must scrub them (C-1, PR #257; the guards loader does).
t_run_split env GIT_DIR="$FOREIGN/.git" GIT_WORK_TREE="$FOREIGN" sh "$REPO/scripts/trace.sh" dir
[ "$S_OUT" = "$REPO/.trace" ] && pass "an inherited GIT_DIR/GIT_WORK_TREE cannot redirect discovery to a foreign checkout's policy" || fail "inherited git identity redirected discovery: dir printed '$S_OUT'"

banner "7. The environment overrides the policy file — including with an explicitly empty value"
t_run_split env TRACE_CONFIG=$ON TRACE_DIR="$SCRATCH/env-abs" sh "$TRACE" dir
[ "$S_OUT" = "$SCRATCH/env-abs" ] && pass "an absolute TRACE_DIR in the environment beats the file" || fail "dir printed '$S_OUT'"
t_run_split env TRACE_CONFIG=$ON TRACE_DIR= sh "$TRACE" dir
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && pass "TRACE_DIR set to the empty string turns tracing OFF for that process (H-3)" || fail "an empty environment TRACE_DIR did not switch tracing off: dir printed '$S_OUT'"
( cd "$REPO" && TRACE_DIR=elsewhere sh scripts/trace.sh dir ) | grep -qx "$REPO/elsewhere" &&
	pass "a relative one still resolves under the root checkout" || fail "relative env TRACE_DIR did not resolve under the root"

banner "8. show matches a subject exactly, by subject or by related token, filtered by kind and date"
Q="$SCRATCH/q"; QON=$(policy "$Q")
TRACE_CONFIG=$QON sh "$TRACE" emit kind=ticket.write subject='ticket:#3' reason=three
TRACE_CONFIG=$QON sh "$TRACE" emit kind=ticket.write subject='ticket:#34' reason=thirty-four
TRACE_CONFIG=$QON sh "$TRACE" emit kind=pr.open subject='pr:#9' related='ticket:#3 branch:feat/x' reason=opened
t_run_split env TRACE_CONFIG=$QON sh "$TRACE" show 'ticket:#3'
[ "$(printf '%s\n' "$S_OUT" | grep -c .)" = 2 ] && pass "show ticket:#3 returns the two events that name it" || fail "show returned: $S_OUT"
case $S_OUT in *thirty-four*) fail "ticket:#3 matched ticket:#34 — a prefix match, not an exact one" ;; *) pass "and never the longer ticket:#34" ;; esac
case $S_OUT in *opened*) pass "a related token counts as a match" ;; *) fail "the related token was not matched" ;; esac
t_run_split env TRACE_CONFIG=$QON sh "$TRACE" show 'ticket:#3' --kind pr.open
[ "$(printf '%s\n' "$S_OUT" | grep -c .)" = 1 ] && pass "--kind narrows to one" || fail "--kind returned: $S_OUT"
t_run_split env TRACE_CONFIG=$QON sh "$TRACE" show 'ticket:#3' --since 2999-01-01
[ -z "$S_OUT" ] && [ "$S_STATUS" = 0 ] && pass "--since a future date returns nothing, exit 0" || fail "--since returned '$S_OUT' (exit $S_STATUS)"
assert_status 2 "show with a malformed subject is exit 2" -- env TRACE_CONFIG="$QON" sh "$TRACE" show 'ticket 3'
# The data map is open: a key may be called subject, related or kind. The
# reader must look at the envelope only (H-2, PR #257).
TRACE_CONFIG=$QON sh "$TRACE" emit kind=note subject='ticket:#34' data.subject='ticket:#3' data.related='ticket:#3' reason=decoy
TRACE_CONFIG=$QON sh "$TRACE" emit kind=note subject='ticket:#3' data.kind=pr.open reason=decoy-kind
t_run_split env TRACE_CONFIG=$QON sh "$TRACE" show 'ticket:#3'
case $S_OUT in *'"reason":"decoy"'*) fail "show matched a data.subject/data.related decoy — it read the data map, not the envelope" ;; *) pass "a data.subject or data.related named ticket:#3 is not a match" ;; esac
t_run_split env TRACE_CONFIG=$QON sh "$TRACE" show 'ticket:#3' --kind pr.open
case $S_OUT in *decoy-kind*) fail "--kind matched a data.kind decoy" ;; *) pass "a data.kind is not the event's kind" ;; esac
[ "$(printf '%s\n' "$S_OUT" | grep -c .)" = 1 ] && pass "--kind pr.open still finds the one real pr.open" || fail "--kind returned: $S_OUT"

banner "9. verify names the file and line of a bad event, and exits 1"
t_run_split env TRACE_CONFIG=$QON sh "$TRACE" verify
[ "$S_STATUS" = 0 ] && pass "a clean trace verifies (exit 0)" || fail "verify failed a clean trace: $S_OUT $S_ERR"
printf '{"v":1,"ts":"2026-09-23T00:00:00Z","id":"x","kind":"bogus","reason":"hand-edited"}\n' >>"$Q/events/$TODAY.jsonl"
printf 'not json at all\n' >>"$Q/events/$TODAY.jsonl"
t_run_split env TRACE_CONFIG=$QON sh "$TRACE" verify
[ "$S_STATUS" = 1 ] && pass "a trace with bad lines is exit 1" || fail "verify exited $S_STATUS on bad lines"
case $S_OUT in *"$TODAY.jsonl:6"*) pass "the unknown kind is named by file:line" ;; *) fail "line 6 not named: $S_OUT" ;; esac
case $S_OUT in *"$TODAY.jsonl:7"*) pass "the non-JSON line is named by file:line" ;; *) fail "line 7 not named: $S_OUT" ;; esac
t_run_split env TRACE_CONFIG=$OFF sh "$TRACE" verify
[ "$S_STATUS" = 0 ] && pass "verify on an unconfigured trace is exit 0 — nothing to check" || fail "verify unconfigured exited $S_STATUS — out: $S_OUT err: $S_ERR"

banner "10. The kit's own wrapper resolves through the kit twin, and passes every argument through"
# The suite may itself be running from a linked worktree of the kit, so the
# expected answer is the ROOT checkout's .trace/ — the same derivation the
# script uses, asked of git rather than assumed.
KIT_ROOT=$(dirname "$(git -C "$KIT" rev-parse --path-format=absolute --git-common-dir)")
( cd "$KIT" && sh scripts/trace.kit.sh dir ) | grep -qx "$KIT_ROOT/.trace" &&
	pass "trace.kit.sh dir names the kit's own .trace/ at the root checkout" || fail "trace.kit.sh dir printed something other than $KIT_ROOT/.trace"
( cd "$KIT" && sh scripts/trace.kit.sh emit --dry-run kind=note reason=pass-through ) | grep -q '"reason":"pass-through"' &&
	pass "the wrapper hands the whole argument list to the script" || fail "arguments did not reach the script through the wrapper"
( cd "$KIT" && sh scripts/trace.kit.sh emit --dry-run kind=bogus >/dev/null 2>&1 ); [ $? = 2 ] &&
	pass "and the script's exit status comes back through it" || fail "exit status was lost through the wrapper"
grep -q "^TRACE_DIR=''" "$KIT/scripts/trace.config.sh" && pass "the shipped policy file carries TRACE_DIR empty" || fail "scripts/trace.config.sh does not ship TRACE_DIR empty"
grep -q "^TRACE_DIR='.trace'" "$KIT/scripts/trace.kit.config.sh" && pass "the kit twin turns tracing on here" || fail "scripts/trace.kit.config.sh does not set TRACE_DIR"

banner "11. The wiring around the script — what the rest of the repo must say"
grep -qx '\.trace/' "$KIT/.gitignore" && pass ".gitignore keeps .trace/ out of version control" || fail ".gitignore does not list .trace/"
for f in scripts/trace.kit.config.sh scripts/trace.kit.sh tests/trace.test.sh; do
	grep -q "KIT_ONLY=.*$f" "$KIT/bootstrap.sh" && pass "$f is on bootstrap's KIT_ONLY list" || fail "$f is missing from KIT_ONLY"
done
grep -qF 'tests/trace.test.sh' "$KIT/README.md" && pass "README names this suite" || fail "README does not name tests/trace.test.sh"
grep -q 'scripts/trace.kit.sh' "$KIT/AGENTS.md" && pass "the root manual names the kit wrapper" || fail "AGENTS.md does not name scripts/trace.kit.sh"
grep -q '^- \*\*Trace\*\*' "$KIT/docs/domain-glossary.md" && pass "the glossary defines Trace" || fail "the glossary has no Trace entry"
[ -f "$KIT"/docs/adr/0008-*.md ] && pass "ADR-0008 exists" || fail "no ADR-0008"

banner "12. summary groups the trace, counts it, sums its tokens and prices it on read"
# A READER fixture is written as FILES, not emitted: only a file whose name is
# an older date can exercise --since, and the emitter always writes today's.
# Every line below is shaped exactly as the emitter writes one, so `verify`
# passes on it — which banner 15's refusal case then relies on.
SUM="$SCRATCH/priced"
mkdir -p "$SUM/events"
OLD="$SUM/events/2026-01-02.jsonl"
NOW="$SUM/events/$TODAY.jsonl"
printf '%s\n' \
	'{"v":1,"ts":"2026-01-02T09:00:00Z","id":"a1","kind":"session.usage","skill":"implement","subject":"session:s1","session":"s1","model":"m1","outcome":"ok","tok_in":1000000,"tok_out":1000000,"tok_cache_w":400000,"tok_cache_r":2000000}' >"$OLD"
printf '%s\n' \
	'{"v":1,"ts":"'"$TODAY"'T10:00:00Z","id":"a2","kind":"session.usage","skill":"review-pr","subject":"session:s2","session":"s2","model":"m1","tok_in":1000,"tok_out":0,"tok_cache_w":0,"tok_cache_r":0}' \
	'{"v":1,"ts":"'"$TODAY"'T10:01:00Z","id":"a3","kind":"session.usage","skill":"review-pr","subject":"session:s2","session":"s2","model":"m2","tok_in":5000,"tok_out":0,"tok_cache_w":0,"tok_cache_r":0}' \
	'{"v":1,"ts":"'"$TODAY"'T10:02:00Z","id":"a4","kind":"note","skill":"implement","subject":"ticket:#253","reason":"say \"hi\", back\\ tab\there é","data":{"note":"1,2"}}' \
	'{"v":1,"ts":"'"$TODAY"'T10:03:00Z","id":"a5","kind":"session.usage","skill":"review-pr","subject":"session:s2","session":"s2","model":"v:pro-1.5","tok_in":2000000,"tok_out":1000000,"tok_cache_w":0,"tok_cache_r":0}' \
	'{"v":1,"ts":"'"$TODAY"'T10:04:00Z","id":"a6","kind":"session.usage","skill":"review-pr","subject":"session:s2","session":"s2","model":"9-bad","tok_in":1000,"tok_out":0,"tok_cache_w":0,"tok_cache_r":0}' >"$NOW"
# The price table is POLICY, in the same file as TRACE_DIR. Two models are
# priced and two are not, on purpose: the unpriced pair is what proves the cost
# column never quietly reads zero. `v:pro-1.5` is priced through a name that
# only survives the fold if a colon and a dot both become underscores, and
# `9-bad` folds to `9_BAD`, a legal suffix (banner 19) that this table simply
# does not price — so it reads unpriced like any other unknown model.
PRICED="$SCRATCH/policy.priced.sh"
{
	printf "TRACE_DIR='%s'\n" "$SUM"
	printf "TRACE_PRICE_M1='3,15,3.75,0.30'\n"
	printf "TRACE_PRICE_V_PRO_1_5='1,2,0,0'\n"
} >"$PRICED"

# summary_row <stdout> <key> — one group's row as space-separated fields, so
# the assertions read the numbers and never the column widths.
summary_row() { printf '%s\n' "$1" | awk -v k="$2" '$1 == k { print $2, $3, $4, $5, $6, $7 }'; }

t_run_split env TRACE_CONFIG=$PRICED sh "$TRACE" summary --by model
[ "$S_STATUS" = 0 ] && pass "summary --by model exits 0" || fail "summary exited $S_STATUS: $S_ERR"
case $(printf '%s\n' "$S_OUT" | head -1) in
model*events*tok_in*tok_out*tok_cache_w*tok_cache_r*cost_usd*) pass "the header names the axis and the six columns" ;;
*) fail "unexpected header: $(printf '%s\n' "$S_OUT" | head -1)" ;;
esac
[ "$(summary_row "$S_OUT" m1)" = "2 1001000 1000000 400000 2000000 20.103000" ] &&
	pass "m1: two events, the token sums, and 20.103000 — 3 and 15 per million on input and output, then 400000 cache writes at 3.75 and 2000000 cache reads at 0.30" ||
	fail "m1 row was: $(summary_row "$S_OUT" m1)"
[ "$(summary_row "$S_OUT" 'v:pro-1.5')" = "1 2000000 1000000 0 0 4.000000" ] &&
	pass "v:pro-1.5: the model id folds through a colon and a dot to reach its price" ||
	fail "v:pro-1.5 row was: $(summary_row "$S_OUT" 'v:pro-1.5')"
[ "$(summary_row "$S_OUT" m2)" = "1 5000 0 0 0 unpriced" ] &&
	pass "m2 carries tokens and no price, so its cost reads unpriced and never 0" ||
	fail "m2 row was: $(summary_row "$S_OUT" m2)"
[ "$(summary_row "$S_OUT" 9-bad)" = "1 1000 0 0 0 unpriced" ] &&
	pass "a model whose folded name is no legal variable is unpriced, never evaluated" ||
	fail "9-bad row was: $(summary_row "$S_OUT" 9-bad)"
[ "$(summary_row "$S_OUT" '(none)')" = "1 0 0 0 0 0.000000" ] &&
	pass "an event with no model and no tokens groups under (none) and costs 0 — zero tokens cost nothing at any price" ||
	fail "(none) row was: $(summary_row "$S_OUT" '(none)')"
[ "$(summary_row "$S_OUT" TOTAL)" = "6 3007000 2000000 400000 2000000 unpriced" ] &&
	pass "TOTAL sums every group and refuses to name a figure while any token-bearing event is unpriced" ||
	fail "TOTAL row was: $(summary_row "$S_OUT" TOTAL)"
case $S_ERR in *m2*) pass "stderr names a model that carried tokens and had no price" ;; *) fail "stderr did not name m2: $S_ERR" ;; esac
case $S_ERR in *9-bad*) pass "and the digit-initial one the table does not price" ;; *) fail "stderr did not name 9-bad: $S_ERR" ;; esac

t_run_split env TRACE_CONFIG=$PRICED sh "$TRACE" summary --by skill
[ "$(summary_row "$S_OUT" implement)" = "2 1000000 1000000 400000 2000000 20.100000" ] &&
	pass "--by skill prices a group whose only token-bearing event is priced" ||
	fail "implement row was: $(summary_row "$S_OUT" implement)"
[ "$(summary_row "$S_OUT" review-pr)" = "4 2007000 1000000 0 0 unpriced" ] &&
	pass "and a group that mixes a priced and an unpriced model reads unpriced, never a partial sum" ||
	fail "review-pr row was: $(summary_row "$S_OUT" review-pr)"
t_run_split env TRACE_CONFIG=$PRICED sh "$TRACE" summary --by kind
[ "$(summary_row "$S_OUT" session.usage)" = "5 3007000 2000000 400000 2000000 unpriced" ] && pass "--by kind groups on the closed vocabulary" || fail "session.usage row was: $(summary_row "$S_OUT" session.usage)"
t_run_split env TRACE_CONFIG=$PRICED sh "$TRACE" summary --by session
[ "$(summary_row "$S_OUT" s1)" = "1 1000000 1000000 400000 2000000 20.100000" ] && pass "--by session groups on the session field" || fail "s1 row was: $(summary_row "$S_OUT" s1)"
t_run_split env TRACE_CONFIG=$PRICED sh "$TRACE" summary --by model --since "$TODAY"
[ "$(summary_row "$S_OUT" m1)" = "1 1000 0 0 0 0.003000" ] &&
	pass "--since drops the older day's file: 1000 input tokens at 3 per million is 0.003000" ||
	fail "m1 row since $TODAY was: $(summary_row "$S_OUT" m1)"
t_run_split env TRACE_CONFIG=$PRICED sh "$TRACE" summary
case $(printf '%s\n' "$S_OUT" | head -1) in kind*) pass "--by defaults to kind" ;; *) fail "the default axis is not kind: $(printf '%s\n' "$S_OUT" | head -1)" ;; esac
assert_status 2 "an unknown --by axis is exit 2 — the axis vocabulary is closed" -- env TRACE_CONFIG="$PRICED" sh "$TRACE" summary --by tier
assert_out_has "kind, skill, model, session"
assert_status 2 "a malformed --since is exit 2" -- env TRACE_CONFIG="$PRICED" sh "$TRACE" summary --since yesterday
t_run_split env TRACE_CONFIG=$OFF sh "$TRACE" summary --by model
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && pass "summary on an unconfigured trace is exit 0 and silent on stdout" || fail "summary unconfigured printed '$S_OUT' (exit $S_STATUS)"

banner "13. A price is four numbers per million tokens, and a malformed one is the operator error it is"
BADP="$SCRATCH/policy.badprice.sh"
printf "TRACE_DIR='%s'\nTRACE_PRICE_M1='3,15'\n" "$SUM" >"$BADP"
assert_status 2 "a price missing two of its four fields is exit 2" -- env TRACE_CONFIG="$BADP" sh "$TRACE" summary --by model
assert_out_has "TRACE_PRICE_M1"
BADP2="$SCRATCH/policy.badprice2.sh"
printf "TRACE_DIR='%s'\nTRACE_PRICE_M1='3,15,free,0.30'\n" "$SUM" >"$BADP2"
assert_status 2 "a price field that is not a number is exit 2, never silently zero" -- env TRACE_CONFIG="$BADP2" sh "$TRACE" summary --by model

banner "14. export is the importable artifact: JSONL verbatim, CSV flat and priced"
t_run_split env TRACE_CONFIG=$PRICED sh "$TRACE" export
[ "$S_STATUS" = 0 ] && [ "$(printf '%s\n' "$S_OUT" | grep -c .)" = 6 ] && pass "export prints the six selected events" || fail "export printed $(printf '%s\n' "$S_OUT" | grep -c .) lines (exit $S_STATUS): $S_ERR"
# The WHOLE stream against the files, not just its first line: an export that
# rewrote every event after the first would have passed a first-line check.
[ "$S_OUT" = "$(cat "$OLD" "$NOW")" ] && pass "and prints them verbatim, every line of them, oldest day first — an event is a fact, so the JSONL form adds nothing" || fail "the JSONL form is not the files' own bytes"
t_run_split env TRACE_CONFIG=$PRICED sh "$TRACE" export --since "$TODAY"
# WHICH five, not how many: --since returning any five events would have passed
# a count.
[ "$S_OUT" = "$(cat "$NOW")" ] && pass "--since selects by the file's date — exactly today's five events, and the older day's not at all" || fail "export --since printed something other than today's file: $S_OUT"

t_run_split env TRACE_CONFIG=$PRICED sh "$TRACE" export --csv
[ "$S_STATUS" = 0 ] && pass "export --csv exits 0" || fail "export --csv exited $S_STATUS: $S_ERR"
CSVH=$(printf '%s\n' "$S_OUT" | head -1)
# Head and tail rather than the whole row: the envelope's middle is the field
# list in scripts/trace.sh, and a later slice adding a field there should widen
# this CSV without failing this assertion.
# The WHOLE header, not head and tail fragments: a CSV that dropped or reordered
# a middle envelope column would have kept both ends intact and passed. The
# column order IS the contract a database reads, so a later slice that adds a
# field to the event owes this line an edit.
WANT_H='v,ts,id,kind,skill,subject,related,session,run,parent,tier,domain,harness,model,outcome,reason,tok_in,tok_out,tok_cache_w,tok_cache_r,cost_usd,priced_at,price_src,data'
[ "$CSVH" = "$WANT_H" ] &&
	pass "the header is the event envelope's own columns in order, then the three computed on read, then the data map" ||
	fail "CSV header is not the documented column list:$(printf '\n    got:  %s\n    want: %s' "$CSVH" "$WANT_H")"
[ "$(printf '%s\n' "$S_OUT" | grep -c .)" = 7 ] && pass "one header row and six event rows" || fail "CSV had $(printf '%s\n' "$S_OUT" | grep -c .) lines"
ROW1=$(printf '%s\n' "$S_OUT" | grep ',a1,')
case $ROW1 in *,1000000,1000000,400000,2000000,20.100000,*) pass "the priced row carries bare token counts and its computed cost_usd" ;; *) fail "row a1 was: $ROW1" ;; esac
case $ROW1 in *,20.100000,2[0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z,"$PRICED",*) pass "priced_at stamps when it was priced and price_src names the table that priced it" ;; *) fail "priced_at/price_src wrong in: $ROW1" ;; esac
ROW3=$(printf '%s\n' "$S_OUT" | grep ',a3,')
case $ROW3 in *,unpriced,*) pass "an unpriced model exports the word, not a number" ;; *) fail "row a3 was: $ROW3" ;; esac
# The escaper's inverse: the CSV column carries the REAL value, so a quote is
# doubled per RFC 4180 and the JSON backslash escapes are gone.
WANT=$(printf '"say ""hi"", back\\ tab\there é"')
ROW4=$(printf '%s\n' "$S_OUT" | grep ',a4,')
case $ROW4 in *"$WANT"*) pass "a reason with a quote, a comma, a backslash, a tab and non-ASCII round-trips into one CSV field" ;; *) fail "the reason cell was not CSV-escaped: $ROW4" ;; esac
case $ROW4 in *'"{""note"":""1,2""}"'*) pass "the data map travels as one JSON string column" ;; *) fail "the data cell was not one quoted JSON column: $ROW4" ;; esac
case $ROW4 in *,0.000000,*) pass "an event with no tokens costs 0.000000 whatever its model" ;; *) fail "row a4 cost was not 0.000000: $ROW4" ;; esac
case $ROW4 in *ticket:#253*) pass "and a value needing no quoting is left bare, so a database reads its own types" ;; *) fail "subject missing from row a4: $ROW4" ;; esac
if command -v node >/dev/null 2>&1; then
	printf '%s\n' "$S_OUT" | node -e '
		const rows = require("fs").readFileSync(0, "utf8").trim().split("\n");
		const cols = (l) => { const o = []; let f = "", q = false; for (let i = 0; i < l.length; i++) { const c = l[i];
			if (q) { if (c === "\"" && l[i + 1] === "\"") { f += "\""; i++; } else if (c === "\"") q = false; else f += c; }
			else if (c === "\"") q = true; else if (c === ",") { o.push(f); f = ""; } else f += c; } o.push(f); return o; };
		const n = cols(rows[0]).length;
		for (const r of rows) if (cols(r).length !== n) { console.error("row has " + cols(r).length + " fields, not " + n + ": " + r); process.exit(1); }' &&
		pass "every row parses to the header's field count under a real CSV reader" ||
		fail "a CSV row does not have the header's field count"
else
	echo "  skip  node is not on PATH — the CSV field-count check not run"
fi
t_run_split env TRACE_CONFIG=$OFF sh "$TRACE" export --csv
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && pass "export on an unconfigured trace is exit 0 and silent on stdout" || fail "export unconfigured printed '$S_OUT' (exit $S_STATUS)"

banner "15. export refuses while verify fails — a corrupt trace is never an import"
printf 'hand-edited, not an event\n' >>"$NOW"
t_run_split env TRACE_CONFIG=$PRICED sh "$TRACE" export
[ "$S_STATUS" = 1 ] && pass "export over a trace with a bad line is exit 1 — verify's own verdict" || fail "export exited $S_STATUS on a bad line"
[ -z "$S_OUT" ] && pass "and prints no rows at all, so half an import is impossible" || fail "export printed rows despite the bad line"
case $S_ERR in *"$TODAY.jsonl:6"*) pass "and names the file and line on stderr" ;; *) fail "the refusal did not name file:line: $S_ERR" ;; esac
t_run_split env TRACE_CONFIG=$PRICED sh "$TRACE" export --csv
[ "$S_STATUS" = 1 ] && [ -z "$S_OUT" ] && pass "the CSV form refuses the same way" || fail "export --csv did not refuse (exit $S_STATUS)"

banner "16. The price table is policy: the shipped file documents the shape, the kit twin carries it filled and dated"
assert_file_has "$KIT/scripts/trace.config.sh" "TRACE_PRICE_" "the shipped policy file documents the price variable"
grep -q '^TRACE_PRICE_' "$KIT/scripts/trace.config.sh" &&
	fail "the shipped policy file ASSIGNS a price — the kit ships none, for the reason it ships no model id" ||
	pass "and assigns none: the kit ships no price, for the reason it ships no model id"
# The twin owes an entry per model its own tier mapping names, each carrying
# FOUR numbers per million tokens, and a header that says when they were read
# off the vendors' pages. An empty value is the honest state for a table
# nobody checked; a filled one is a claim with a date on it (operator decision,
# 2026-09-28: the numbers come from the vendors' own pricing pages).
TWIN_N=$(grep -c "^TRACE_PRICE_[A-Z0-9_]*='[0-9][0-9.]*,[0-9][0-9.]*,[0-9][0-9.]*,[0-9][0-9.]*'$" "$KIT/scripts/trace.kit.config.sh")
[ "$TWIN_N" -ge 5 ] &&
	pass "the kit twin carries the price table FILLED — $TWIN_N entries with four numbers each, one per model its tier mapping names" ||
	fail "scripts/trace.kit.config.sh carries $TWIN_N filled TRACE_PRICE_ entries, fewer than the five models scripts/agents.kit.config.sh maps"
grep -q "^TRACE_PRICE_[A-Z0-9_]*=''" "$KIT/scripts/trace.kit.config.sh" &&
	fail "an entry in the kit twin's price table is still empty — every mapped model owes its four numbers" ||
	pass "and none of them is left empty"
grep -qE 'Last checked: *20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$KIT/scripts/trace.kit.config.sh" &&
	pass "and the table's header carries the date the numbers were read" ||
	fail "the kit twin's price table header does not say 'Last checked: <YYYY-MM-DD>'"
grep -qi 'last checked: *never' "$KIT/scripts/trace.kit.config.sh" &&
	fail "the header still says NEVER over filled values — a claim nobody made" ||
	pass "and no longer says NEVER"
grep -qE 'https?://' "$KIT/scripts/trace.kit.config.sh" &&
	pass "and names the vendor pages the numbers came from" ||
	fail "the kit twin does not name a source for its prices"
assert_file_has "$KIT/AGENTS.md" "summary" "the root manual's trace row names the reading subcommands"
assert_file_has "$KIT/AGENTS.md" "export" "the root manual's trace row names the reading subcommands"

banner "17. The reader's price lookup is the operator's own name for the model (review of PR #262)"
# Every case here is a finding from the independent review on PR #262, each
# reproduced against the branch before it was fixed, each named by its finding
# id so the next reader can follow the trail back to the thread.

# H-1. The lookup folded the JSON-ESCAPED field body, so a model carrying a
# quote, a backslash or a tab resolved to a variable name no operator would
# ever write: `a"b` folded to A__B rather than the A_B they typed. Emitted
# through the real emitter, so the escaping is the emitter's own.
H1="$SCRATCH/h1"
H1P="$SCRATCH/policy.h1.sh"
printf "TRACE_DIR='%s'\nTRACE_PRICE_A_B='1,1,1,1'\nTRACE_PRICE_C_D='2,0,0,0'\n" "$H1" >"$H1P"
TRACE_CONFIG=$H1P sh "$TRACE" emit kind=session.usage model='a"b' tok_in=1000000
TRACE_CONFIG=$H1P sh "$TRACE" emit kind=session.usage model="c${TAB}d" tok_in=1000000
t_run_split env TRACE_CONFIG=$H1P sh "$TRACE" summary --by model
[ "$(summary_row "$S_OUT" 'a"b')" = "1 1000000 0 0 0 1.000000" ] &&
	pass "H-1: a model carrying a quote is priced by the name the operator typed, not by the escaped body" ||
	fail "H-1: the a\"b row was: $(summary_row "$S_OUT" 'a\"b') / $(summary_row "$S_OUT" 'a"b')"
case $S_ERR in *'a\"b'*) fail "H-1: the unpriced note still names the escaped body" ;; *) pass "H-1: and the diagnostics name the real id too" ;; esac
t_run_split env TRACE_CONFIG=$H1P sh "$TRACE" export --csv
case $S_OUT in *',2.000000,'*) pass "H-1: a model carrying a tab prices in the CSV as well" ;; *) fail "H-1: the tab-carrying model did not price: $S_OUT" ;; esac

# H-2. `for m in $models` and `set -- $(files)` field-split AND glob. A model
# called `alpha*` was silently replaced by whatever file the CALLER's cwd
# happened to hold, so the price of one model was looked up under another
# model's name — and the diagnostics named the wrong one.
H2="$SCRATCH/h2"
H2P="$SCRATCH/policy.h2.sh"
printf "TRACE_DIR='%s'\nTRACE_PRICE_ALPHA_='5,0,0,0'\n" "$H2" >"$H2P"
TRACE_CONFIG=$H2P sh "$TRACE" emit kind=session.usage model='alpha*' tok_in=1000000
mkdir -p "$SCRATCH/globbait" && : >"$SCRATCH/globbait/alphax"
t_run_split env TRACE_CONFIG=$H2P sh -c "cd '$SCRATCH/globbait' && sh '$TRACE' summary --by model"
[ "$(summary_row "$S_OUT" 'alpha*')" = "1 1000000 0 0 0 5.000000" ] &&
	pass "H-2: a model carrying a glob character is read literally, whatever files the caller's cwd holds" ||
	fail "H-2: the alpha* row was: $(summary_row "$S_OUT" 'alpha*')"
case $S_ERR in *alphax*) fail "H-2: a filename from the caller's cwd leaked into the price lookup" ;; *) pass "H-2: and no filename from that directory reached the diagnostics" ;; esac
# The same expansion selects the event FILES, so a trace directory whose own
# path carries a glob character must still be read.
H2G="$SCRATCH/glob[1]dir"
H2GP="$SCRATCH/policy.h2g.sh"
printf "TRACE_DIR='%s'\n" "$H2G" >"$H2GP"
TRACE_CONFIG=$H2GP sh "$TRACE" emit kind=note subject='ticket:#262' reason='under a bracketed path'
t_run_split env TRACE_CONFIG=$H2GP sh "$TRACE" export
case $S_OUT in *'under a bracketed path'*) pass "H-2: and a trace directory whose path carries a glob character is still read" ;; *) fail "H-2: export found nothing under $H2G: '$S_OUT'" ;; esac

# H-3. The two-stage pipeline rounded each group to six places and then summed
# the rounded rows, so the SAME events totalled differently depending on which
# axis you grouped them by. A total that moves when you change the question is
# not a total.
H3="$SCRATCH/h3"
H3P="$SCRATCH/policy.h3.sh"
printf "TRACE_DIR='%s'\nTRACE_PRICE_T='0.4,0,0,0'\n" "$H3" >"$H3P"
TRACE_CONFIG=$H3P sh "$TRACE" emit kind=note skill=one model=t tok_in=1
TRACE_CONFIG=$H3P sh "$TRACE" emit kind=note skill=two model=t tok_in=1
BY_SKILL=$(env TRACE_CONFIG=$H3P sh "$TRACE" summary --by skill 2>/dev/null | awk '$1 == "TOTAL" { print $7 }')
BY_KIND=$(env TRACE_CONFIG=$H3P sh "$TRACE" summary --by kind 2>/dev/null | awk '$1 == "TOTAL" { print $7 }')
BY_MODEL=$(env TRACE_CONFIG=$H3P sh "$TRACE" summary --by model 2>/dev/null | awk '$1 == "TOTAL" { print $7 }')
[ "$BY_SKILL" = "$BY_KIND" ] && [ "$BY_KIND" = "$BY_MODEL" ] &&
	pass "H-3: TOTAL is the same figure on every axis over the same events ($BY_KIND) — the rounding happens at display, not between the two stages" ||
	fail "H-3: TOTAL moved with the axis — by skill $BY_SKILL, by kind $BY_KIND, by model $BY_MODEL"
[ "$BY_KIND" = "0.000001" ] && pass "H-3: and it is the sum of the two unrounded costs, not the sum of two rounded zeros" || fail "H-3: TOTAL was $BY_KIND, not 0.000001"

# M-1. `IFS=,` word splitting drops a TRAILING empty field, so '1,2,3,4,'
# counted as four prices and was accepted.
BADP3="$SCRATCH/policy.badprice3.sh"
printf "TRACE_DIR='%s'\nTRACE_PRICE_M1='3,15,3.75,0.30,'\n" "$SUM" >"$BADP3"
assert_status 2 "M-1: a price with a trailing comma is exit 2 — word splitting hid the empty fifth field" -- env TRACE_CONFIG="$BADP3" sh "$TRACE" summary --by model
BADP4="$SCRATCH/policy.badprice4.sh"
printf "TRACE_DIR='%s'\nTRACE_PRICE_M1=',3,15,3.75'\n" "$SUM" >"$BADP4"
assert_status 2 "M-1: and a leading comma is too" -- env TRACE_CONFIG="$BADP4" sh "$TRACE" summary --by model

# M-2. A missing field and a field whose literal value is the text `(none)`
# were merged into one row, so both counts and both costs were wrong.
M2="$SCRATCH/m2"
M2P=$(policy "$M2")
TRACE_CONFIG=$M2P sh "$TRACE" emit kind=note reason='the skill field is absent'
TRACE_CONFIG=$M2P sh "$TRACE" emit kind=note skill='(none)' reason='the skill field literally says (none)'
t_run_split env TRACE_CONFIG=$M2P sh "$TRACE" summary --by skill
[ "$(printf '%s\n' "$S_OUT" | awk '$1 == "(none)"' | grep -c .)" = 2 ] &&
	pass "M-2: an absent field and a literal (none) are two rows, never one merged count" ||
	fail "M-2: the two groups did not stay apart: $S_OUT"
[ "$(printf '%s\n' "$S_OUT" | awk '$1 == "TOTAL" { print $2 }')" = 2 ] && pass "M-2: and the total still counts both events once" || fail "M-2: TOTAL was wrong: $S_OUT"

# M-3. The script lost its executable bit to a `mv` while it was being edited.
# Nothing in this suite invokes it directly, which is exactly why the bit could
# go missing without a single assertion noticing.
[ -x "$TRACE" ] && pass "M-3: scripts/trace.sh is executable, so a direct invocation still works" || fail "M-3: scripts/trace.sh has lost its executable bit"

# The reviewer's coverage audit: cache_write and cache_read were weighted by
# equal token counts everywhere, so swapping the two rates left the whole suite
# green. A cache-only event with unequal counts is the cheapest oracle.
CACHE="$SCRATCH/cache"
CACHEP="$SCRATCH/policy.cache.sh"
printf "TRACE_DIR='%s'\nTRACE_PRICE_K='0,0,10,1'\n" "$CACHE" >"$CACHEP"
TRACE_CONFIG=$CACHEP sh "$TRACE" emit kind=session.usage model=k tok_cache_w=100000 tok_cache_r=3000000
t_run_split env TRACE_CONFIG=$CACHEP sh "$TRACE" summary --by model
[ "$(summary_row "$S_OUT" k)" = "1 0 0 100000 3000000 4.000000" ] &&
	pass "the cache rates are weighted by their own counts — 100000 at 10 plus 3000000 at 1 is 4.000000, and swapping the two rates would read 31.000000" ||
	fail "the cache-only row was: $(summary_row "$S_OUT" k)"

banner "18. summary over a damaged trace says so in its own first line — a total nobody mistakes for clean (operator decision, 2026-09-28)"
DAMAGED="$SCRATCH/damaged"
mkdir -p "$DAMAGED/events"
cp "$SUM/events/2026-01-02.jsonl" "$DAMAGED/events/"
grep -v 'hand-edited' "$NOW" >"$DAMAGED/events/$TODAY.jsonl"
DPOL=$(policy "$DAMAGED")
printf "TRACE_PRICE_M1='3,15,3.75,0.30'\n" >>"$DPOL"
t_run_split env TRACE_CONFIG=$DPOL sh "$TRACE" summary --by model
[ "$S_STATUS" = 0 ] && pass "summary on a clean trace exits 0" || fail "summary exited $S_STATUS on a clean trace: $S_ERR"
case $S_OUT in *"verify: FAILED"*) fail "a clean trace was marked as failed verify" ;; *) pass "and carries no verify marker when the trace is clean" ;; esac
printf 'hand-edited, not an event\n' >>"$DAMAGED/events/$TODAY.jsonl"
t_run_split env TRACE_CONFIG=$DPOL sh "$TRACE" summary --by model
[ "$S_STATUS" = 0 ] && pass "summary on a damaged trace still exits 0 — a glance is not an import" || fail "summary exited $S_STATUS on a damaged trace"
case $(printf '%s\n' "$S_OUT" | sed -n 1p) in "verify: FAILED"*) pass "and its FIRST line says verify FAILED, so the totals below are never quoted as clean" ;; *) fail "the first line of summary did not mark the failed verify: $(printf '%s\n' "$S_OUT" | sed -n 1p)" ;; esac
case $S_OUT in *"1 bad line"*) pass "and counts the bad LINES — one, however many findings verify raised for it" ;; *) fail "the marker does not count the bad lines: $S_OUT" ;; esac
# The trap the count fell into once: with node on PATH verify names the same
# line twice, structurally and from the parse, and a marker that counted
# findings said 2. Pin the double report, so the count's job stays visible.
if command -v node >/dev/null 2>&1; then
	[ "$(printf '%s\n' "$S_ERR" | grep -c "$TODAY.jsonl:")" -ge 2 ] &&
		pass "verify reported that one line more than once on stderr (structural and parse), and the marker still said 1" ||
		fail "expected verify to name the bad line at least twice with node present: $S_ERR"
fi
case $S_ERR in *"$TODAY.jsonl:"*) pass "and verify's own findings go to stderr, file:line" ;; *) fail "stderr did not carry verify's file:line: $S_ERR" ;; esac
[ "$(summary_row "$S_OUT" m1)" = "2 1001000 1000000 400000 2000000 20.103000" ] &&
	pass "and the rows themselves are still the rows" || fail "m1 row changed: $(summary_row "$S_OUT" m1)"

banner "19. A model id that starts with a digit is priceable — the fold's token only has to be a legal suffix (review of PR #262)"
NINE="$SCRATCH/nine"
mkdir -p "$NINE/events"
printf '%s\n' '{"v":1,"ts":"'"$TODAY"'T10:04:00Z","id":"n1","kind":"session.usage","skill":"review-pr","subject":"session:s9","session":"s9","model":"9-bad","tok_in":1000000,"tok_out":0,"tok_cache_w":0,"tok_cache_r":0}' >"$NINE/events/$TODAY.jsonl"
NPOL=$(policy "$NINE")
printf "TRACE_PRICE_9_BAD='2,0,0,0'\n" >>"$NPOL"
t_run_split env TRACE_CONFIG=$NPOL sh "$TRACE" summary --by model
[ "$(summary_row "$S_OUT" 9-bad)" = "1 1000000 0 0 0 2.000000" ] &&
	pass "TRACE_PRICE_9_BAD prices the model 9-bad — a digit-initial token is a legal variable suffix" ||
	fail "9-bad did not price through TRACE_PRICE_9_BAD: $(summary_row "$S_OUT" 9-bad)"

t_done "trace script"
