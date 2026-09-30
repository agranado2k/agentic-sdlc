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
# Sections 10 to 16 are the SECOND slice (ticket #248): a run has an identity
# and a payload has a home. `begin` and `end` are a run's two ends, identity
# has one precedence (an explicit field, the environment, then the pointer file
# and the run stack), only those two subcommands rewrite the stack and both by
# rename, an event over 4000 bytes is refused rather than split across two
# writes, a payload is stored once by git's own content hash, and the trace
# directory names the schema its lines were written under.
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

banner "5a. feedback is in the vocabulary — the human's verdict on a landed slice (PRD #237, scenario 13; ticket #250)"
# The "adjust aim" record between tracer bullets: /merge-train emits it at
# landing, /pr-iterate when a human comment changes the plan. Before #250 the
# kind was unknown and exit 2, the same refusal `bogus` gets above.
for _fb in hit adjusted missed; do
	t_run_split env TRACE_CONFIG=$ON sh "$TRACE" emit kind=feedback subject='ticket:#247' outcome=$_fb reason='#248 and #253 re-cut after the review'
	[ "$S_STATUS" = 0 ] && pass "feedback outcome=$_fb is accepted" || fail "feedback outcome=$_fb exited $S_STATUS: $S_ERR"
done
case $(tail -n 1 "$FILE") in *'"kind":"feedback"'*'"subject":"ticket:#247"'*'"outcome":"missed","reason":"#248 and #253 re-cut after the review"}') pass "and the line carries the slice, the verdict and its reason" ;; *) fail "feedback line wrong: $(tail -n 1 "$FILE")" ;; esac

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

banner "8b. show run:<id> reads the envelope's run field, and a child run's pair under its parent"
# PRD #237 story 25, found missing by #263's review: a run id lives in the `run`
# field, never in `subject`, so a subject-only reader answered nothing for the
# one question a run id is for. The events are emitted with explicit run= and
# parent= fields rather than through begin/end, so this case stays hermetic and
# independent of a working tree's run stack (sections 10 to 13 own that).
R="$SCRATCH/runs"; RON=$(policy "$R")
TRACE_CONFIG=$RON sh "$TRACE" emit kind=run.start skill=implement run=r1 subject='ticket:#7' reason=outer-start
TRACE_CONFIG=$RON sh "$TRACE" emit kind=note run=r1 reason=inside-one
TRACE_CONFIG=$RON sh "$TRACE" emit kind=note run=r1 reason=inside-two
TRACE_CONFIG=$RON sh "$TRACE" emit kind=run.start skill=review-pr run=r1c parent=r1 reason=child-start
TRACE_CONFIG=$RON sh "$TRACE" emit kind=note run=r1c parent=r1 reason=inside-child
TRACE_CONFIG=$RON sh "$TRACE" emit kind=run.end run=r1c parent=r1 reason=child-end
TRACE_CONFIG=$RON sh "$TRACE" emit kind=run.end run=r1 reason=outer-end
TRACE_CONFIG=$RON sh "$TRACE" emit kind=note run=r12 reason=longer-run
TRACE_CONFIG=$RON sh "$TRACE" emit kind=note data.run=r1 reason=run-decoy
TRACE_CONFIG=$RON sh "$TRACE" emit kind=note subject='run:r1' reason=about-the-run

t_run_split env TRACE_CONFIG=$RON sh "$TRACE" show 'run:r1'
[ "$(printf '%s\n' "$S_OUT" | grep -c .)" = 7 ] && pass "show run:r1 returns the seven events that belong to it" || fail "show run:r1 returned: $S_OUT"
case $S_OUT in *outer-start*) pass "the run's own run.start is one of them" ;; *) fail "run.start was not matched: $S_OUT" ;; esac
case $S_OUT in *inside-one*) pass "and an event emitted inside the run" ;; *) fail "an event carrying run=r1 was not matched: $S_OUT" ;; esac
case $S_OUT in *about-the-run*) pass "and an event that names the run as its SUBJECT — the run field is added to the match, not substituted for it" ;; *) fail "subject='run:r1' stopped matching: $S_OUT" ;; esac
# The one thing a prefix reader gets wrong, exactly as ticket:#3 must never
# find ticket:#34: r1 is a prefix of r12, and an id is matched whole or not
# at all.
case $S_OUT in *longer-run*) fail "show run:r1 matched run=r12 — a prefix match, not an exact one" ;; *) pass "and never the longer run=r12" ;; esac
case $S_OUT in *run-decoy*) fail "show run:r1 matched a data.run decoy — it read the data map, not the envelope" ;; *) pass "a data.run named r1 is not the event's run" ;; esac
# A dispatched worker's pair shows under the run that dispatched it (PRD
# scenario 11), which is the whole point of reading `parent` — but only for the
# pair: an event a child emitted between them belongs to the child's own id, or
# a nested run would flatten its whole body into its parent's view.
case $S_OUT in *child-start*) pass "the child run's run.start appears under its parent's id" ;; *) fail "a child run.start with parent=r1 was not matched: $S_OUT" ;; esac
case $S_OUT in *child-end*) pass "and its run.end" ;; *) fail "a child run.end with parent=r1 was not matched: $S_OUT" ;; esac
case $S_OUT in *inside-child*) fail "an event the child emitted (parent=r1, kind note) was flattened into the parent's view" ;; *) pass "but not the events between them — those are the child run's own" ;; esac

t_run_split env TRACE_CONFIG=$RON sh "$TRACE" show 'run:r1c'
[ "$(printf '%s\n' "$S_OUT" | grep -c .)" = 3 ] && pass "show run:r1c returns the child's own three events" || fail "show run:r1c returned: $S_OUT"
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" show 'run:r1' --kind note
[ "$(printf '%s\n' "$S_OUT" | grep -c .)" = 3 ] && pass "--kind still narrows a run's view" || fail "--kind note over run:r1 returned: $S_OUT"
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" show 'run:r1' --since 2999-01-01
[ -z "$S_OUT" ] && [ "$S_STATUS" = 0 ] && pass "--since still narrows it, exit 0" || fail "--since over run:r1 returned '$S_OUT' (exit $S_STATUS)"
# The ids above are hand-written so the cases stay hermetic, but the id an
# operator actually types is the one `begin` mints — a stamp, a process id and
# eight hex digits, uppercase letters and hyphens included. Round-trip one, so
# the shape the demo uses is a shape the suite has read back (L-1, review of
# PR #284).
REAL=$(env TRACE_CONFIG=$RON sh "$TRACE" begin implement subject='ticket:#272')
env TRACE_CONFIG=$RON sh "$TRACE" emit kind=tdd.cycle outcome=green reason=real-id-inside
env TRACE_CONFIG=$RON sh "$TRACE" end outcome=green reason=real-id-done
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" show "run:$REAL"
[ "$(printf '%s\n' "$S_OUT" | grep -c .)" = 3 ] && pass "an id begin actually minted round-trips through show" || fail "show run:<a minted id> returned: $S_OUT"
# The type is what switches the run field on: a ticket subject must not start
# matching run ids, or `show ticket:#3` in section 8 would answer for a run
# called `#3`. The decoy carries the REFERENCE the subject would be reduced to
# — `${subject#*:}` of `ticket:#3` is `#3`, never `3` — because a decoy the
# wrong shape leaves the assertion passing with the type switch deleted, which
# is a check that cannot fail (H-1, review of PR #284).
TRACE_CONFIG=$RON sh "$TRACE" emit kind=note run='#3' reason=run-called-three
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" show 'ticket:#3'
[ -z "$S_OUT" ] && pass "and a non-run subject never reads the run field" || fail "show ticket:#3 matched on the run field: $S_OUT"

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

banner "10. A run has an identity: begin hands one out, an emit picks it up, end closes it"
R="$SCRATCH/runs"; RON=$(policy "$R")
RFILE="$R/events/$TODAY.jsonl"
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" begin implement subject='ticket:#248'
[ "$S_STATUS" = 0 ] && pass "begin exits 0" || fail "begin exited $S_STATUS — out: '$S_OUT' err: '$S_ERR'"
RUN1=$S_OUT
printf '%s\n' "$RUN1" | grep -qE '^[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9a-f]{8}$' &&
	pass "begin prints a run id of the documented shape: sortable stamp, pid, random bytes" || fail "begin printed '$RUN1'"
case $(tail -n 1 "$RFILE") in
*'"kind":"run.start","skill":"implement","subject":"ticket:#248","run":"'"$RUN1"'"'*) pass "and appends run.start naming the skill, the subject and the run" ;;
*) fail "run.start wrong: $(tail -n 1 "$RFILE")" ;;
esac
case $(tail -n 1 "$RFILE") in *'"parent"'*) fail "the outermost run was given a parent" ;; *) pass "the outermost run has no parent — the field is omitted, not empty" ;; esac
env TRACE_CONFIG=$RON sh "$TRACE" emit kind=tdd.cycle outcome=red reason='the first case'
case $(tail -n 1 "$RFILE") in *'"run":"'"$RUN1"'"'*) pass "an emit inside the run carries it without being told" ;; *) fail "the emit did not pick the run up: $(tail -n 1 "$RFILE")" ;; esac
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" begin tdd
RUN2=$S_OUT
[ -n "$RUN2" ] && [ "$RUN2" != "$RUN1" ] && pass "a nested begin hands out a different id" || fail "the nested begin printed '$RUN2'"
case $(tail -n 1 "$RFILE") in *'"run":"'"$RUN2"'","parent":"'"$RUN1"'"'*) pass "and records the run it nests inside as parent" ;; *) fail "the nested run.start: $(tail -n 1 "$RFILE")" ;; esac
env TRACE_CONFIG=$RON sh "$TRACE" emit kind=tdd.cycle outcome=green reason='it passes'
case $(tail -n 1 "$RFILE") in *'"run":"'"$RUN2"'","parent":"'"$RUN1"'"'*) pass "an emit inside the nested run carries both" ;; *) fail "the nested emit: $(tail -n 1 "$RFILE")" ;; esac
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" end outcome=ok reason='the cycle is done'
[ "$S_STATUS" = 0 ] && pass "end exits 0" || fail "end exited $S_STATUS: $S_ERR"
case $(tail -n 1 "$RFILE") in *'"kind":"run.end"'*'"run":"'"$RUN2"'","parent":"'"$RUN1"'"'*'"outcome":"ok"'*) pass "and emits run.end for the run it popped" ;; *) fail "run.end wrong: $(tail -n 1 "$RFILE")" ;; esac
env TRACE_CONFIG=$RON sh "$TRACE" emit kind=note reason='after the pop'
case $(tail -n 1 "$RFILE") in *'"run":"'"$RUN1"'"'*) pass "the next emit is back on the outer run — end popped, it did not clear" ;; *) fail "after the pop: $(tail -n 1 "$RFILE")" ;; esac
case $(tail -n 1 "$RFILE") in *'"parent"'*) fail "the outer run acquired a parent" ;; *) pass "and has no parent again" ;; esac
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" end outcome=ok
[ "$S_STATUS" = 0 ] && pass "the outer run closes too" || fail "the second end exited $S_STATUS: $S_ERR"
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" end
[ "$S_STATUS" = 2 ] && pass "end with no run open is exit 2 — there is nothing to close" || fail "end on an empty stack exited $S_STATUS"
case $S_ERR in *begin*) pass "and the refusal says what opens one" ;; *) fail "the refusal did not name begin: $S_ERR" ;; esac
env TRACE_CONFIG=$RON sh "$TRACE" emit kind=note reason='no run open'
case $(tail -n 1 "$RFILE") in *'"run"'*) fail "an emit outside any run still carried one: $(tail -n 1 "$RFILE")" ;; *) pass "with no run open the run field is omitted" ;; esac
assert_status 2 "begin being told its kind is exit 2 — the subcommand owns it" -- env TRACE_CONFIG="$RON" sh "$TRACE" begin implement kind=note
assert_out_has "begin sets kind itself"
assert_status 2 "end being told which run it closes is exit 2 — the stack says which" -- env TRACE_CONFIG="$RON" sh "$TRACE" end run=made-up
assert_out_has "end sets run itself"
assert_status 2 "begin with no skill is exit 2" -- env TRACE_CONFIG="$RON" sh "$TRACE" begin
# Review C-1..L-7 (PR #263): begin owns `skill` through its positional argument
# as firmly as it owns `kind`, and a trailing skill= silently won (L-2).
assert_status 2 "begin being told a second skill is exit 2 — the positional argument is the skill" -- env TRACE_CONFIG="$RON" sh "$TRACE" begin implement skill=something-else
assert_out_has "begin sets skill itself"
# H-1: end popped BEFORE its own event could be refused, so a rejected
# argument destroyed the entry, wrote no run.end, and the retry closed the run
# OUTSIDE it — permanently wrong in a record that can only be appended to.
RUN_A=$(env TRACE_CONFIG=$RON sh "$TRACE" begin implement)
RUN_B=$(env TRACE_CONFIG=$RON sh "$TRACE" begin tdd)
OVER=$(awk 'BEGIN { while (i++ < 4100) printf "x" }')
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" end outcome=ok reason="$OVER"
[ "$S_STATUS" = 2 ] && pass "an end whose own event is refused is exit 2" || fail "the refused end exited $S_STATUS"
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" end outcome=ok reason='the retry'
case $(tail -n 1 "$RFILE") in *'"run":"'"$RUN_B"'"'*) pass "and the retry closes the run that was still open, not the one outside it" ;; *) fail "the refused end popped anyway — the retry closed: $(tail -n 1 "$RFILE")" ;; esac
case $(tail -n 1 "$RFILE") in *'"run":"'"$RUN_A"'"'*) fail "the retry closed the OUTER run — the stack lost an entry to a refusal" ;; *) pass "and the outer run is untouched by either" ;; esac
env TRACE_CONFIG=$RON sh "$TRACE" end outcome=ok reason='and the outer one'

banner "11. Identity precedence: the environment first, then the pointer file and the stack, then omitted"
STACK=$(ls "$R"/current/*.runs 2>/dev/null | head -n 1)
[ -n "$STACK" ] && pass "the run stack sits at current/<toplevel key>.runs under the trace directory" || fail "no run stack under $R/current"
KEY=$(basename "$STACK" .runs)
printf 'sess-from-pointer\n' >"$R/current/$KEY"
env TRACE_CONFIG=$RON sh "$TRACE" emit kind=note reason=pointer
case $(tail -n 1 "$RFILE") in *'"session":"sess-from-pointer"'*) pass "the pointer file beside the stack, under the same key, names the session" ;; *) fail "the pointer was not read: $(tail -n 1 "$RFILE")" ;; esac
env TRACE_CONFIG=$RON TRACE_SESSION=sess-from-env sh "$TRACE" emit kind=note reason=env-session
case $(tail -n 1 "$RFILE") in *'"session":"sess-from-env"'*) pass "TRACE_SESSION in the environment beats the pointer file" ;; *) fail "the environment lost to the pointer: $(tail -n 1 "$RFILE")" ;; esac
RUN3=$(env TRACE_CONFIG=$RON sh "$TRACE" begin implement)
RUN4=$(env TRACE_CONFIG=$RON sh "$TRACE" begin review-pr)
env TRACE_CONFIG=$RON sh "$TRACE" emit kind=note reason=from-the-stack
case $(tail -n 1 "$RFILE") in *'"run":"'"$RUN4"'","parent":"'"$RUN3"'"'*) pass "two deep, the stack answers both run and parent" ;; *) fail "the stack answered: $(tail -n 1 "$RFILE")" ;; esac
env TRACE_CONFIG=$RON TRACE_RUN=run-from-env sh "$TRACE" emit kind=note reason=env-run
case $(tail -n 1 "$RFILE") in *'"run":"run-from-env"'*) pass "TRACE_RUN beats the stack — a dispatched worker is told its run" ;; *) fail "TRACE_RUN lost to the stack: $(tail -n 1 "$RFILE")" ;; esac
case $(tail -n 1 "$RFILE") in *'"parent"'*) fail "a run named by the environment borrowed a parent from a stack that is not its own: $(tail -n 1 "$RFILE")" ;; *) pass "and the local stack's parent is not borrowed for it" ;; esac
env TRACE_CONFIG=$RON TRACE_RUN=run-from-env TRACE_PARENT=parent-from-env sh "$TRACE" emit kind=note reason=env-parent
case $(tail -n 1 "$RFILE") in *'"run":"run-from-env","parent":"parent-from-env"'*) pass "TRACE_PARENT is how the dispatcher names the run it spawned from" ;; *) fail "TRACE_PARENT was not read: $(tail -n 1 "$RFILE")" ;; esac
env TRACE_CONFIG=$RON TRACE_RUN=run-from-env sh "$TRACE" emit kind=note run=run-from-arg reason=arg
case $(tail -n 1 "$RFILE") in *'"run":"run-from-arg"'*) pass "an explicit run= argument is the most specific answer of the three" ;; *) fail "the argument lost: $(tail -n 1 "$RFILE")" ;; esac
# H-3 (review, PR #263): SET-BUT-EMPTY is the environment SAYING there is no
# run — `RUN=$(trace.sh begin …)` is empty for every consumer whose policy file
# is untouched — and it must not read as "ask the local stack", which is the one
# thing the specification forbids. Same distinction trace_load_config keeps for
# TRACE_DIR a hundred lines above.
env TRACE_CONFIG=$RON TRACE_RUN= sh "$TRACE" emit kind=note reason='a worker whose run came back empty'
case $(tail -n 1 "$RFILE") in *'"run"'*) fail "TRACE_RUN set to the empty string borrowed the local stack: $(tail -n 1 "$RFILE")" ;; *) pass "TRACE_RUN set to the empty string means NO run, as an empty TRACE_DIR means OFF" ;; esac
case $(tail -n 1 "$RFILE") in *'"parent"'*) fail "and it borrowed a parent from a stack that is not its own too" ;; *) pass "and no parent borrowed either" ;; esac
env TRACE_CONFIG=$RON TRACE_SESSION= sh "$TRACE" emit kind=note reason='no session, said explicitly'
case $(tail -n 1 "$RFILE") in *'"session"'*) fail "TRACE_SESSION set to the empty string still read the pointer file" ;; *) pass "and TRACE_SESSION set to the empty string skips the pointer file" ;; esac
# L-6: a pointer naming something `show` could never match would be written to
# every line and queryable from none of them.
printf 'not a session at all\n' >"$R/current/$KEY"
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" emit kind=note reason='an unqueryable pointer'
case $(tail -n 1 "$RFILE") in *'"session"'*) fail "an unqueryable session id reached the line: $(tail -n 1 "$RFILE")" ;; *) pass "a session id show could never match is ignored rather than written" ;; esac
case $S_ERR in *"trace:"*) pass "and the reason is on stderr, trace-prefixed" ;; *) fail "nothing was said about it: $S_ERR" ;; esac
printf 'sess-from-pointer\n' >"$R/current/$KEY"

banner "12. Only begin and end rewrite the run stack, and both by rename"
STACK="$R/current/$KEY.runs"
[ -f "$STACK" ] && pass "the stack is a file at the key the pointer shares" || fail "no stack file at $STACK"
INODE=$(ls -i "$STACK" | awk '{ print $1 }')
env TRACE_CONFIG=$RON sh "$TRACE" emit kind=note reason='an emit only appends'
[ "$(ls -i "$STACK" | awk '{ print $1 }')" = "$INODE" ] && pass "an emit leaves the stack file exactly as it was — same inode" || fail "an emit rewrote the run stack"
env TRACE_CONFIG=$RON sh "$TRACE" begin tdd >/dev/null
PUSHED=$(ls -i "$STACK" | awk '{ print $1 }')
[ "$PUSHED" != "$INODE" ] && pass "begin replaces the file by rename — a parallel reader sees the old stack or the new one, never half of one" || fail "begin wrote the stack in place"
env TRACE_CONFIG=$RON sh "$TRACE" end outcome=ok
[ "$(ls -i "$STACK" | awk '{ print $1 }')" != "$PUSHED" ] && pass "and so does end" || fail "end wrote the stack in place"
[ -z "$(find "$R/current" -name '*.runs.*' 2>/dev/null)" ] && pass "and neither leaves its staging file behind" || fail "a staging file survives under $R/current"
# H-2 (review, PR #263): the push staged through a command group whose exit
# status was printf's, so a `cat` that could not READ the existing stack was
# indistinguishable from an empty one — every open run replaced by a single
# entry, and exit 0. Skipped as root, where chmod 000 denies nothing.
if [ "$(id -u)" != 0 ]; then
	STACK_WAS=$(cat "$STACK")
	chmod 000 "$STACK"
	t_run_split env TRACE_CONFIG=$RON sh "$TRACE" begin review-pr
	chmod 600 "$STACK"
	[ "$S_STATUS" != 0 ] && pass "a begin that cannot read the run stack refuses instead of reporting success" || fail "begin exited 0 on an unreadable stack"
	[ "$(cat "$STACK")" = "$STACK_WAS" ] && pass "and every open run is still there — nothing was overwritten" || fail "the unreadable stack was replaced by: $(cat "$STACK")"
	case $S_ERR in *"trace:"*) pass "and every diagnostic is trace-prefixed, none of them raw from awk or cat" ;; *) fail "the diagnostics were not trace-prefixed: $S_ERR" ;; esac
	case $S_ERR in *"awk:"* | *"cat:"*) fail "a raw awk or cat diagnostic leaked: $S_ERR" ;; *) pass "and no tool's own error text leaked past it (M-4)" ;; esac
	[ "$(printf '%s\n' "$S_ERR" | grep -c 'exists and cannot be read')" = 1 ] && pass "and says it once, not once per question asked of the stack" || fail "the note was repeated: $S_ERR"
else
	echo "  skip  running as root — chmod 000 denies no read, so the unreadable-stack case cannot be driven"
fi

banner "13. Fifty emits in parallel all land, all verify, carry the open run, and leave the stack alone"
# The first draft ran the fifty against a trace where no run had ever been
# opened, so the run stack this section is named for did not exist and the case
# was green the day it was written (review M-1, PR #263). A run is open now, so
# the section fails an emit that pushes, pops or rewrites the stack — which is
# the claim: fifty writers of events, none of the stack.
P="$SCRATCH/parallel"; PON=$(policy "$P")
PRUN=$(env TRACE_CONFIG=$PON sh "$TRACE" begin implement)
PSTACK=$(ls "$P"/current/*.runs)
PINODE=$(ls -i "$PSTACK" | awk '{ print $1 }')
n=0
while [ "$n" -lt 50 ]; do
	env TRACE_CONFIG=$PON sh "$TRACE" emit kind=note subject="ticket:#$n" reason="parallel $n" &
	n=$((n + 1))
done
wait
PFILE="$P/events/$TODAY.jsonl"
[ "$(grep -c '"reason":"parallel ' "$PFILE")" = 50 ] && pass "fifty backgrounded emits appended fifty whole lines" || fail "expected 50 parallel lines, got $(grep -c '"reason":"parallel ' "$PFILE")"
t_run_split env TRACE_CONFIG=$PON sh "$TRACE" verify
[ "$S_STATUS" = 0 ] && pass "and every one of them verifies" || fail "verify failed after fifty parallel appends: $S_OUT"
[ "$(grep -c "\"run\":\"$PRUN\"" "$PFILE")" = 51 ] && pass "and all fifty carry the run that was open, as does the run.start above them" || fail "only $(grep -c "\"run\":\"$PRUN\"" "$PFILE") of the 51 lines carry the run"
[ "$(ls -i "$PSTACK" | awk '{ print $1 }')" = "$PINODE" ] && pass "and not one of them touched the run stack — fifty readers, no writer" || fail "a parallel emit rewrote the run stack"
[ "$(grep -c . "$PSTACK")" = 1 ] && pass "which still holds exactly the one run that was opened" || fail "the stack holds $(grep -c . "$PSTACK") entries, not 1"
[ "$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' "$PFILE" | sort -u | wc -l | tr -d ' ')" = 51 ] &&
	pass "and no two ids collide — the random bytes are what make that true within one second" || fail "ids collided across the fifty"

banner "14. An event is capped at 4000 bytes, so an append stays one write"
BEFORE=$(wc -l <"$RFILE" | tr -d ' ')
BIG=$(awk 'BEGIN { while (i++ < 4100) printf "x" }')
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" emit kind=note reason="$BIG"
[ "$S_STATUS" = 2 ] && pass "a line over the cap is exit 2" || fail "an over-cap line exited $S_STATUS"
case $S_ERR in *4000*) pass "and the refusal names the cap" ;; *) fail "the refusal did not name the cap: $S_ERR" ;; esac
case $S_ERR in *--blob*) pass "and points at --blob, where a payload that size belongs" ;; *) fail "the refusal did not point at --blob: $S_ERR" ;; esac
[ "$(wc -l <"$RFILE" | tr -d ' ')" = "$BEFORE" ] && pass "and nothing was appended" || fail "the refused event was written anyway"
NEARLY=$(awk 'BEGIN { while (i++ < 3600) printf "y" }')
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" emit kind=note reason="$NEARLY"
[ "$S_STATUS" = 0 ] && pass "a long line under the cap is still written" || fail "a line under the cap was refused: $S_ERR"
# M-5 (review, PR #263): 3600 accepted and 4100 refused left a 500-byte gap in
# which the enforced number could be anything, and the assertion that names the
# cap reads the MESSAGE, which interpolates the constant. The probe below is
# measured with a dry run in the same trace state; the envelope's own length
# still moves by a byte with the writer's pid width, since the id carries it,
# so the two cases sit two bytes either side — four bytes of slack, not five
# hundred.
CAP=4000
BASE=$(env TRACE_CONFIG=$RON sh "$TRACE" emit --dry-run kind=note reason=x | wc -c | tr -d ' ')
UNDER=$(awk -v n=$((CAP - BASE - 1)) 'BEGIN { while (i++ < n) printf "z" }')
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" emit kind=note reason="$UNDER"
[ "$S_STATUS" = 0 ] && pass "a line two bytes under the cap is accepted" || fail "a line two bytes under the cap was refused: $S_ERR"
OVERBY=$(awk -v n=$((CAP - BASE + 3)) 'BEGIN { while (i++ < n) printf "z" }')
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" emit kind=note reason="$OVERBY"
[ "$S_STATUS" = 2 ] && pass "and a line two bytes over it is refused" || fail "a line two bytes over the cap was accepted"

banner "15. --blob gives a payload a home: git's own content hash, stored once, moved into place"
PAY="$SCRATCH/payload.txt"
printf 'line one\nline two\na quote " and a backslash \\ and a tab\there\n' >"$PAY"
HASH=$(git hash-object "$PAY")
FAN=$(printf '%.2s' "$HASH")
BYTES=$(wc -c <"$PAY" | tr -d ' ')
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" emit kind=spike.verdict subject='ticket:#248' --blob "$PAY" outcome=confirmed reason='the evidence is in the blob'
[ "$S_STATUS" = 0 ] && pass "an emit carrying a blob exits 0" || fail "the blob emit exited $S_STATUS: $S_ERR"
[ -f "$R/blobs/$FAN/$HASH" ] && pass "the payload is stored at blobs/<first two of the hash>/<the hash>" || fail "no blob at $R/blobs/$FAN/$HASH"
[ "$HASH" = "$(git hash-object "$R/blobs/$FAN/$HASH")" ] && pass "and its name is git's hash of its own content — one hashing mechanism, not a second one" || fail "the stored blob does not hash to its name"
cmp -s "$PAY" "$R/blobs/$FAN/$HASH" && pass "byte for byte what was handed in" || fail "the stored blob differs from the payload"
case $(tail -n 1 "$RFILE") in *'"blob":"'"$HASH"'","blob_bytes":'"$BYTES"'}') pass "and the event carries the hash and the byte count, last before data" ;; *) fail "the blob fields are wrong: $(tail -n 1 "$RFILE")" ;; esac
BLOB_INODE=$(ls -i "$R/blobs/$FAN/$HASH" | awk '{ print $1 }')
COPY="$SCRATCH/payload-copy.txt"; cp "$PAY" "$COPY"
env TRACE_CONFIG=$RON sh "$TRACE" emit kind=note --blob "$COPY" reason='the same payload under another name'
[ "$(find "$R/blobs" -type f | wc -l | tr -d ' ')" = 1 ] && pass "identical content under another name is stored once" || fail "the same payload was stored twice"
[ "$(ls -i "$R/blobs/$FAN/$HASH" | awk '{ print $1 }')" = "$BLOB_INODE" ] && pass "and the one already there was not rewritten" || fail "an existing blob was rewritten"
BLOB_OUT=$(cat "$PAY" | env TRACE_CONFIG=$RON sh "$TRACE" emit kind=note --blob - reason='the payload arrived on stdin' 2>&1)
case $(tail -n 1 "$RFILE") in *'"blob":"'"$HASH"'"'*) pass "--blob - hashes what it reads on stdin to the very same name" ;; *) fail "stdin hashed differently: $(tail -n 1 "$RFILE") ($BLOB_OUT)" ;; esac
[ "$(find "$R/blobs" -type f | wc -l | tr -d ' ')" = 1 ] && pass "and that payload too was stored once" || fail "the stdin payload was stored again"
[ -z "$(find "$R/tmp" -type f 2>/dev/null)" ] && pass "and the scratch it staged through is left with nothing in it" || fail "staging files survive under $R/tmp"
assert_status 2 "--blob naming no file is exit 2" -- env TRACE_CONFIG="$RON" sh "$TRACE" emit kind=note --blob "$SCRATCH/no-such-payload"
# C-1 (review, PR #263 — CRITICAL): the name has to be git's hash of the bytes
# that were STORED. git trusts st_size on a seekable descriptor, so hashing a
# payload whose size the filesystem does not know THROUGH A REDIRECTION read
# nothing and returned the EMPTY blob's hash, while the copy that landed carried
# real bytes: a 28-byte payload stored at the empty blob's address, where every
# later empty payload would then find it instead of its own.
if [ -r /proc/loadavg ]; then
	t_run_split env TRACE_CONFIG=$RON sh "$TRACE" emit kind=spike.verdict subject='ticket:#248' --blob /proc/loadavg reason='a payload whose size the filesystem does not know'
	[ "$S_STATUS" = 0 ] && pass "a payload whose st_size is 0 and whose content is not is accepted" || fail "it was refused: $S_ERR"
	STsomething=$(tail -n 1 "$RFILE")
	NAMED=$(printf '%s' "$STsomething" | sed -n 's/.*"blob":"\([^"]*\)".*/\1/p')
	NAMED_BYTES=$(printf '%s' "$STsomething" | sed -n 's/.*"blob_bytes":\([0-9]*\).*/\1/p')
	STORED="$R/blobs/$(printf '%.2s' "$NAMED")/$NAMED"
	[ -f "$STORED" ] && pass "and it is stored" || fail "no blob at $STORED"
	[ "$NAMED" = "$(git hash-object "$STORED")" ] && pass "and the name it was given IS git's hash of the bytes that landed" || fail "the blob is named $NAMED but the stored bytes hash to $(git hash-object "$STORED")"
	[ "$NAMED_BYTES" = "$(wc -c <"$STORED" | tr -d ' ')" ] && pass "and blob_bytes counts those same bytes" || fail "blob_bytes says $NAMED_BYTES, the stored payload is $(wc -c <"$STORED" | tr -d ' ') bytes"
	[ "$NAMED" != e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 ] && pass "and it did not land at the empty blob's address, where every later empty payload would have found it" || fail "a payload with content was stored as git's EMPTY blob"
else
	echo "  skip  no readable /proc/loadavg — the st_size-lies-about-content case cannot be driven here"
fi
# M-2: naming a blob ran before the dry-run and unconfigured checks, so a dry
# run created the store it promised not to write and an unconfigured emit gained
# an exit status it must never have (ADR-0008 clause 4).
DRY="$SCRATCH/dry-trace"; DRYON=$(policy "$DRY")
DRY_OUT=$(cat "$PAY" | env TRACE_CONFIG=$DRYON sh "$TRACE" emit --dry-run kind=note --blob - reason='a dry run carrying a payload' 2>&1)
case $DRY_OUT in *'"blob":"'"$HASH"'"'*) pass "--dry-run still names the blob it would have stored" ;; *) fail "--dry-run printed: $DRY_OUT" ;; esac
[ ! -e "$DRY" ] && pass "and created nothing whatever — not even the store it would have written into" || fail "a dry run brought $DRY into being: $(find "$DRY")"
assert_status 0 "an unconfigured emit whose --blob names nothing is still a silent no-op, never an exit status a caller acts on" -- env TRACE_DIR= TRACE_QUIET=1 sh "$TRACE" emit kind=note --blob "$SCRATCH/no-such-payload" reason=x
assert_status 2 "blob= as a field is exit 2 — a blob is stored by --blob, never asserted" -- env TRACE_CONFIG="$RON" sh "$TRACE" emit kind=note blob=deadbeef


banner "15b. blob stores a payload WITHOUT an event: the same store, the same name, one line of answer (ticket #306)"
# The tool hooks (#252) store two payloads and then write ONE event naming
# both, and `emit` carries one blob — so until this subcommand the adapter kept
# a second writer of the store, whose review found three defects in exactly
# that duplication. `blob` is the store on its own: the same staging, hashing
# and landing an emit's payload gets, answered as `<hash> <bytes>` on stdout.
BL="$SCRATCH/blob-trace"; BLON=$(policy "$BL")
BPAY="$SCRATCH/blob-payload.txt"
printf 'a tool result\nwith a "quote", a \\ and a tab\there\n' >"$BPAY"
BHASH=$(git hash-object "$BPAY")
BBYTES=$(wc -c <"$BPAY" | tr -d ' ')
t_run_split env TRACE_CONFIG=$BLON sh -c 'umask 022; exec sh "$1" blob "$2"' probe "$TRACE" "$BPAY"
[ "$S_STATUS" = 0 ] && pass "blob <file> exits 0" || fail "blob <file> exited $S_STATUS: $S_ERR"
[ "$S_OUT" = "$BHASH $BBYTES" ] && pass "and prints '<hash> <bytes>' on one line, the hash git's own for the same bytes" ||
	fail "blob printed '$S_OUT', git says '$BHASH $BBYTES'"
[ -z "$S_ERR" ] && pass "and says nothing on stderr" || fail "blob spoke on stderr: $S_ERR"
BSTORED="$BL/blobs/$(printf '%.2s' "$BHASH")/$BHASH"
cmp -s "$BPAY" "$BSTORED" && pass "the bytes are stored at blobs/<first two>/<hash>, byte for byte" ||
	fail "no faithful copy at $BSTORED"
BMODE=$(ls -l "$BSTORED" 2>/dev/null | cut -c1-10)
[ "$BMODE" = '-rw-------' ] && pass "readable by its owner alone under a 022 umask ($BMODE) — a payload is private data" ||
	fail "the stored blob's mode is '$BMODE' under a 022 umask"
[ -z "$(find "$BL" -name '*.jsonl' 2>/dev/null)" ] && pass "and NO event file was written — storing is not a decision" ||
	fail "blob wrote an event: $(find "$BL" -name '*.jsonl' -exec cat {} \;)"
[ -z "$(find "$BL/tmp" -type f 2>/dev/null)" ] && pass "and its staging scratch is left empty" ||
	fail "staging files survive under $BL/tmp"
# The SAME store an emit writes: the name `blob` prints is the name an emit
# records for the same bytes, and the emit that follows stores nothing new.
BINODE=$(ls -i "$BSTORED" | awk '{ print $1 }')
env TRACE_CONFIG=$BLON sh "$TRACE" emit kind=note reason='the same bytes, through --blob' --blob "$BPAY"
BLINE=$(cat "$BL/events/$TODAY.jsonl" 2>/dev/null)
case $BLINE in *'"blob":"'"$BHASH"'","blob_bytes":'"$BBYTES"'}') pass "emit --blob records the very name and size blob printed" ;;
*) fail "emit --blob recorded something else: $BLINE" ;; esac
[ "$(find "$BL/blobs" -type f | wc -l | tr -d ' ')" = 1 ] && [ "$(ls -i "$BSTORED" | awk '{ print $1 }')" = "$BINODE" ] &&
	pass "and identical content is stored once, the stored file never rewritten" ||
	fail "the store holds $(find "$BL/blobs" -type f | wc -l) files, or the first was rewritten"
BEFORE=$(cat "$BL/events/$TODAY.jsonl")
BSTDIN=$(env TRACE_CONFIG=$BLON sh "$TRACE" blob - <"$BPAY")
[ "$BSTDIN" = "$BHASH $BBYTES" ] && pass "blob - reads standard input to the same answer" ||
	fail "blob - printed '$BSTDIN'"
[ "$(cat "$BL/events/$TODAY.jsonl")" = "$BEFORE" ] && [ "$(find "$BL/blobs" -type f | wc -l | tr -d ' ')" = 1 ] &&
	pass "and grew no event file and stored nothing twice" ||
	fail "blob - appended an event or stored a second copy"
# Unconfigured is the working state every write has: nothing stored, nothing on
# stdout, exit 0 — and the payload is not even read, so a missing file cannot
# hand a consumer who never opened the policy file a new exit status.
t_run_split env TRACE_DIR= TRACE_QUIET=1 sh "$TRACE" blob "$BPAY"
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && [ -z "$S_ERR" ] &&
	pass "unconfigured, blob is a silent no-op: exit 0, nothing on either stream" ||
	fail "unconfigured blob: status $S_STATUS, out '$S_OUT', err '$S_ERR'"
assert_status 0 "and a missing payload is still exit 0 when nothing would be stored" -- env TRACE_DIR= TRACE_QUIET=1 sh "$TRACE" blob "$SCRATCH/no-such-payload"
t_run_split env TRACE_CONFIG=$OFF sh "$TRACE" blob "$BPAY"
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && pass "without TRACE_QUIET it still prints nothing on stdout, where a caller reads the name" ||
	fail "unconfigured blob printed '$S_OUT' (status $S_STATUS)"
# Configured, the grammar is the caller's to get right.
assert_status 2 "blob naming no file is exit 2" -- env TRACE_CONFIG="$BLON" sh "$TRACE" blob "$SCRATCH/no-such-payload"
assert_status 2 "blob with no argument is exit 2" -- env TRACE_CONFIG="$BLON" sh "$TRACE" blob
assert_status 2 "blob with two arguments is exit 2 — one payload, one name" -- env TRACE_CONFIG="$BLON" sh "$TRACE" blob "$BPAY" "$BPAY"

banner "16. The trace directory says which schema its lines are, and the marker survives an interrupted write (the refusal itself is section 20's)"
[ "$(cat "$R/SCHEMA" 2>/dev/null)" = 1 ] && pass "the first write left a SCHEMA file naming version 1" || fail "SCHEMA says '$(cat "$R/SCHEMA" 2>/dev/null)'"
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" verify
[ "$S_STATUS" = 0 ] && pass "verify is green on a schema it knows" || fail "verify failed a clean trace: $S_OUT $S_ERR"
# M-6 (review, PR #263): an interrupted first write can leave a marker that
# names nothing, and an existence-only guard declined to repair it for good.
: >"$R/SCHEMA"
t_run_split env TRACE_CONFIG=$RON sh "$TRACE" verify
[ "$S_STATUS" = 0 ] && pass "a marker that names nothing reads as a trace from before the marker existed — verify proceeds rather than refusing" || fail "verify refused an empty marker (exit $S_STATUS): $S_ERR"
env TRACE_CONFIG=$RON sh "$TRACE" emit kind=note reason='after the marker was emptied'
[ "$(cat "$R/SCHEMA")" = 1 ] && pass "and the next write repairs it, so no trace stays nameless" || fail "SCHEMA is still '$(cat "$R/SCHEMA")'"

banner "17. The kit's own wrapper resolves through the kit twin, and passes every argument through"
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

banner "18. The wiring around the script — what the rest of the repo must say"
grep -qx '\.trace/' "$KIT/.gitignore" && pass ".gitignore keeps .trace/ out of version control" || fail ".gitignore does not list .trace/"
for f in scripts/trace.kit.config.sh scripts/trace.kit.sh tests/trace.test.sh; do
	grep -q "KIT_ONLY=.*$f" "$KIT/bootstrap.sh" && pass "$f is on bootstrap's KIT_ONLY list" || fail "$f is missing from KIT_ONLY"
done
grep -qF 'tests/trace.test.sh' "$KIT/README.md" && pass "README names this suite" || fail "README does not name tests/trace.test.sh"
grep -q 'scripts/trace.kit.sh' "$KIT/AGENTS.md" && pass "the root manual names the kit wrapper" || fail "AGENTS.md does not name scripts/trace.kit.sh"
grep -qF '`begin`/`end`' "$KIT/AGENTS.md" && pass "and names begin/end, the two subcommands this slice adds" || fail "AGENTS.md's row does not name begin/end"
grep -qF 'run stack' "$KIT/docs/domain-glossary.md" && pass "the glossary names the run stack" || fail "the glossary has no run stack"
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

banner "20. A schema this reader does not know is its own exit code — 3, cannot judge this trace (ADR-0008 clause 4, amended 2026-09-28 for #271)"
# The state the amendment separates from both its neighbours: nothing failed and
# nobody typed anything wrong, so it is neither verify's verdict (1) nor a caller
# error (2). Driven RED against the script that returned 1 here — where `export`
# refused with a message about a bad line there was none of, and `summary` said
# "verify: FAILED — 0 bad line(s)", a count of nothing that reads as almost clean.
UNS="$SCRATCH/unsupported"
mkdir -p "$UNS/events"
printf '%s\n' '{"v":1,"ts":"'"$TODAY"'T11:00:00Z","id":"u1","kind":"session.usage","skill":"implement","subject":"session:su","session":"su","model":"m1","tok_in":1000000,"tok_out":0,"tok_cache_w":0,"tok_cache_r":0}' >"$UNS/events/$TODAY.jsonl"
UPOL=$(policy "$UNS")
printf "TRACE_PRICE_M1='3,15,3.75,0.30'\n" >>"$UPOL"
# The two baselines first, because this section must move neither of them.
t_run_split env TRACE_CONFIG=$UPOL sh "$TRACE" verify
[ "$S_STATUS" = 0 ] && pass "with no SCHEMA marker at all, verify is green — a trace from before the marker existed is still this reader's" || fail "verify exited $S_STATUS with no marker: $S_ERR"
printf '1\n' >"$UNS/SCHEMA"
t_run_split env TRACE_CONFIG=$UPOL sh "$TRACE" verify
[ "$S_STATUS" = 0 ] && pass "and a marker naming version 1 is green too" || fail "verify exited $S_STATUS on schema 1: $S_ERR"

printf '2\n' >"$UNS/SCHEMA"
t_run_split env TRACE_CONFIG=$UPOL sh "$TRACE" verify
[ "$S_STATUS" = 3 ] && pass "a SCHEMA of 2 makes verify exit 3 — no verdict is not a bad verdict (1), and the caller's command was well formed (2)" || fail "verify exited $S_STATUS on schema 2, and 3 is the code for a trace it cannot judge"
case $S_ERR in *"schema 2"*) pass "and the refusal names the version it found" ;; *) fail "the refusal did not name version 2: $S_ERR" ;; esac
case $S_ERR in *"reads 1"*) pass "and the version it does read, so the operator knows which end is behind" ;; *) fail "the refusal did not name the version it reads: $S_ERR" ;; esac
[ -z "$S_OUT" ] && pass "and it judges no line" || fail "verify judged lines under a schema it cannot read: $S_OUT"

t_run_split env TRACE_CONFIG=$UPOL sh "$TRACE" export
[ "$S_STATUS" = 3 ] && pass "export refuses with the same 3 — a caller told 1 would hunt for a bad line there is none of" || fail "export exited $S_STATUS on an unsupported schema"
[ -z "$S_OUT" ] && pass "and prints nothing at all" || fail "export printed rows under a schema it cannot read: $S_OUT"
# H-1 (review, PR #292): matching *schema* here matched VERIFY's own line
# flowing through, so deleting export's whole refusal branch left the suite
# green. Match export's OWN sentence, and pin the absence of the wrong one.
case $S_ERR in *"export refused — the schema"*) pass "and export's OWN refusal says the schema is why" ;; *) fail "export's refusal did not name the schema: $S_ERR" ;; esac
case $S_ERR in *"verify fails on this selection"*) fail "export blamed a failing verify, the one message this state exists to suppress: $S_ERR" ;; *) pass "and never says verify fails, which would send the operator hunting for a bad line" ;; esac
case $S_ERR in *"$TODAY.jsonl:"*) fail "export blamed a line when no line was judged: $S_ERR" ;; *) pass "and blames no line, because none was judged" ;; esac
t_run_split env TRACE_CONFIG=$UPOL sh "$TRACE" export --csv
[ "$S_STATUS" = 3 ] && [ -z "$S_OUT" ] && pass "the CSV form refuses the same way, header included" || fail "export --csv did not refuse with 3 (exit $S_STATUS): $S_OUT"

t_run_split env TRACE_CONFIG=$UPOL sh "$TRACE" summary --by model
[ "$S_STATUS" = 0 ] && pass "summary still exits 0 — a glance is not an import" || fail "summary exited $S_STATUS on an unsupported schema"
case $(printf '%s\n' "$S_OUT" | sed -n 1p) in "verify: UNSUPPORTED SCHEMA 2") pass "and its FIRST line is that marker, naming the version" ;; *) fail "summary's first line was: $(printf '%s\n' "$S_OUT" | sed -n 1p)" ;; esac
case $S_OUT in *"bad line"*) fail "summary counted bad lines under a schema it never judged: $S_OUT" ;; *) pass "and counts no bad lines, because it judged none" ;; esac
[ "$(summary_row "$S_OUT" m1)" = "1 1000000 0 0 0 3.000000" ] && pass "and the rows below are still the rows, priced as ever" || fail "the m1 row changed under an unsupported schema: $(summary_row "$S_OUT" m1)"

# The two states must not collapse into one another.
printf '1\n' >"$UNS/SCHEMA"
printf 'hand-edited, not an event\n' >>"$UNS/events/$TODAY.jsonl"
t_run_split env TRACE_CONFIG=$UPOL sh "$TRACE" verify
[ "$S_STATUS" = 1 ] && pass "a bad line under a KNOWN schema is still exit 1 — the verdict code did not move" || fail "verify exited $S_STATUS on a bad line"
t_run_split env TRACE_CONFIG=$UPOL sh "$TRACE" export
[ "$S_STATUS" = 1 ] && pass "and export still carries that verdict out" || fail "export exited $S_STATUS on a bad line"
t_run_split env TRACE_CONFIG=$UPOL sh "$TRACE" summary --by model
case $(printf '%s\n' "$S_OUT" | sed -n 1p) in "verify: FAILED — 1 bad line"*) pass "and summary still counts the bad line" ;; *) fail "summary's first line was: $(printf '%s\n' "$S_OUT" | sed -n 1p)" ;; esac
printf '2\n' >"$UNS/SCHEMA"
t_run_split env TRACE_CONFIG=$UPOL sh "$TRACE" verify
[ "$S_STATUS" = 3 ] && pass "and a damaged trace under an UNKNOWN schema reports the schema, not the damage — a reader that cannot read the shape cannot call the line bad" || fail "verify exited $S_STATUS on a bad line under schema 2"
: >"$UNS/SCHEMA"
t_run_split env TRACE_CONFIG=$UPOL sh "$TRACE" verify
[ "$S_STATUS" = 1 ] && pass "while a marker that names nothing is no version at all, and the bad line is judged as ever (M-6, PR #263)" || fail "verify exited $S_STATUS on an empty marker"

# The contract is only widened where its readers look for it.
case $(sed -n '/^# STREAMS AND EXIT CODES/,/^#$/p' "$TRACE") in *"exit 3"*) pass "the script's own exit-code paragraph names 3" ;; *) fail "the header's exit-code paragraph does not name exit 3" ;; esac
# L-1 (review, PR #292): the label says ROW, so the check has to say row —
# a bare file-wide grep keeps passing when some other row names the code.
grep -F 'scripts/trace.sh' "$KIT/AGENTS.md" | grep -qF 'exit 3' && pass "and the root manual's trace ROW names it" || fail "AGENTS.md's trace row does not name exit 3"
grep -qF 'Amended 2026-09-28 (#271)' "$KIT/docs/adr/0008-decisions-are-traced-to-a-local-append-only-record.md" &&
	pass "and ADR-0008 carries the dated amendment that chose it" || fail "ADR-0008 has no dated amendment for #271"

t_done "trace script"
