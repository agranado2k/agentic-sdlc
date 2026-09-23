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

t_done "trace script"
