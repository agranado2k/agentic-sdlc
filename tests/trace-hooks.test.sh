#!/bin/sh
# tests/trace-hooks.test.sh — a Claude Code session leaves its usage in the trace.
#
# Ticket #251 of PRD #237: the Claude Code adapter gains three hooks and a
# transcript usage extractor, dormant for consumers, plus a kit-only settings
# file that wires them for THIS repo. ADR-0008 clause 8 is the record — the
# agent harness is the adapter's business, and only a never-shipped settings
# file turns it on here.
#
# WHAT THIS SUITE IS FOR. Three claims rot silently and each has cost a wave
# somewhere already:
#
#   1. THE POINTER AGREES WITH THE SCRIPT. The session-start hook writes the
#      per-toplevel pointer file `scripts/trace.sh` reads a session id back
#      from, and it derives that path itself. Two derivations of one path is a
#      coupling, so the assertion is not "a file appeared" but "a LATER emit
#      carries the session" — the only thing the pointer is for.
#   2. THE TOKEN SUMS ARE EXACT. A streamed assistant response is written once
#      per content block with the same `message.id`, so a sum that does not
#      de-duplicate is wrong by whatever streaming happened to do. The
#      fixtures' final `cost-state` line carries the agent harness's OWN
#      per-model rollup, and this suite reads that line as the ORACLE: the
#      session's usage plus the subagent's must equal it exactly. It is never
#      the source — the rollup also carries the vendor's cost figure, which
#      ADR-0008 clause 6 says the trace never stores.
#   3. EVERY HOOK EXITS 0. A hook is on the agent harness's critical path: a
#      non-zero exit or a word on stdout changes a session's behaviour, and
#      observability that can break a session is worse than none (PRD #237,
#      story 15). So every leg below asserts the exit status too — including
#      the two failure shapes, shape drift and a missing node.
#
# The fixtures are the #246 spike's capture (tests/fixtures/claude-code/README.md
# records the CLI build, the method and what was redacted). Their numbers are
# the assertion: main transcript 34 / 287 / 10793 / 37519, subagent transcript
# 34 / 156 / 17138 / 14968, and the rollup 68 / 443 / 27931 / 52487.
#
# Every case was driven RED first (hard rule 9), against no hooks at all.
#
# Usage: sh tests/trace-hooks.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

KIT="$ROOT"
HOOKS="$KIT/adapters/claude-code/hooks"
FIX="$KIT/tests/fixtures/claude-code"
EXTRACTOR="$HOOKS/transcript-usage.mjs"
SETTINGS="$KIT/.claude/settings.json"
TRACE="$KIT/scripts/trace.sh"
TODAY=$(date -u +%Y-%m-%d)

failures=0
HAVE_NODE=0
command -v node >/dev/null 2>&1 && HAVE_NODE=1

# --- fixture helpers ---------------------------------------------------------

# new_trace — a fresh, EMPTY trace directory, absolute so trace.sh takes it as
# given rather than resolving it against the root checkout. Sets TDIR.
new_trace() {
	TDIR=$(mktemp -d "$SCRATCH/trace.XXXXXX") || exit 2
}

# events — every line written to the trace so far, oldest file first.
events() { cat "$TDIR"/events/*.jsonl 2>/dev/null; }

# ev_of <kind> — the trace lines of that kind.
ev_of() { events | grep -F "\"kind\":\"$1\"" || :; }

# set_key <key> <value> — filter a pretty-printed payload on stdin, replacing
# one top-level string value. ANCHORED at the line's leading whitespace, so
# `transcript_path` never rewrites `agent_transcript_path` (they differ by a
# prefix, and an unanchored pattern matches the tail of the longer one).
set_key() {
	sed 's|^\([[:space:]]*\)"'"$1"'": "[^"]*"|\1"'"$1"'": "'"$2"'"|'
}

# num <line> <field> — an integer field's value, or empty.
num() { printf '%s\n' "$1" | sed -n 's/.*"'"$2"'":\([0-9]*\).*/\1/p'; }

# str <line> <field> — a string field's value, or empty.
str() { printf '%s\n' "$1" | sed -n 's/.*"'"$2"'":"\([^"]*\)".*/\1/p'; }

# sum_tok <field> <kind> — that token field summed over every event of <kind>.
sum_tok() {
	ev_of "$2" | sed -n 's/.*"'"$1"'":\([0-9]*\).*/\1/p' |
		awk '{ s += $1 } END { print s + 0 }'
}

# rollup <key> — one number from the main transcript's final `cost-state`
# line: the agent harness's own per-model rollup, this suite's oracle.
#
# KEYED ON THE MODEL'S OWN BLOCK, not read off the whole line. A greedy `.*`
# takes the LAST match, which is one arbitrary model's number the day a
# two-model capture replaces this fixture — right today and silently wrong
# then (L-2, review of PR #291). `[^}]*` stops at the end of that model's
# object, so the number read is the number under $MODEL.
rollup() {
	sed -n '$p' "$FIX/transcript.redacted.jsonl" |
		sed -n 's/.*"'"$MODEL"'":{\([^}]*\)}.*/\1/p' |
		sed -n 's/.*"'"$1"'":\([0-9]*\).*/\1/p'
}

# no_node_path — PATH with every directory that holds a node executable
# removed, and nothing else touched. Scrubbing PATH outright would take sed,
# git and mkdir with it and prove only that a hook needs a shell.
no_node_path() {
	_nn=
	_nn_ifs=$IFS
	IFS=:
	for _nn_d in $PATH; do
		[ -n "$_nn_d" ] || continue
		[ -x "$_nn_d/node" ] && continue
		_nn="${_nn:+$_nn:}$_nn_d"
	done
	IFS=$_nn_ifs
	printf '%s' "$_nn"
}

SESSION=8fd7c235-bd26-4c7a-9ffd-586578d4b54b
AGENT=a7df5125ff7592e06
MODEL=claude-fable-5-1

# Working copies of the two transcripts, so a payload can name a real path.
cp "$FIX/transcript.redacted.jsonl" "$SCRATCH/main.jsonl"
cp "$FIX/subagent-transcript.redacted.jsonl" "$SCRATCH/sub.jsonl"

# ---------------------------------------------------------------------------
banner "1. The files exist and parse"
# ---------------------------------------------------------------------------
for f in hook.lib.sh session-start.sh session-end.sh subagent-stop.sh; do
	if [ -f "$HOOKS/$f" ]; then
		assert_status 0 "adapters/claude-code/hooks/$f parses under sh -n" -- sh -n "$HOOKS/$f"
	else
		fail "adapters/claude-code/hooks/$f does not exist"
	fi
done
if [ "$HAVE_NODE" = 1 ]; then
	assert_status 0 "the extractor parses under node --check" -- node --check "$EXTRACTOR"
else
	echo "  skip  node is not on PATH — node --check not run"
fi

# ---------------------------------------------------------------------------
banner "2. SessionStart: the pointer a later emit reads, and the exported session"
# ---------------------------------------------------------------------------
new_trace
ENVF="$SCRATCH/session-env.sh"
: >"$ENVF"
set_key transcript_path "$SCRATCH/main.jsonl" <"$FIX/session-start.payload.json" >"$SCRATCH/start.json"
t_run_split env TRACE_DIR="$TDIR" CLAUDE_ENV_FILE="$ENVF" \
	sh "$HOOKS/session-start.sh" <"$SCRATCH/start.json"
[ "$S_STATUS" = 0 ] && pass "the hook exits 0" || fail "the hook exited $S_STATUS: $S_ERR"
[ -z "$S_OUT" ] && pass "and says nothing on stdout — the agent harness reads that stream" ||
	fail "the hook printed on stdout: $S_OUT"

LINE=$(ev_of session.start | sed -n '1p')
[ -n "$LINE" ] && pass "one session.start event was appended" || fail "no session.start event in $TDIR"
[ "$(str "$LINE" subject)" = "session:$SESSION" ] &&
	pass "its subject is the payload's session id" ||
	fail "subject is '$(str "$LINE" subject)', not session:$SESSION"

# THE COUPLING CHECK. The pointer is only worth writing if scripts/trace.sh
# reads it back — the hook derives that path itself, and one derivation
# drifting from the other is invisible in any check that only looks for a file.
t_run_split env TRACE_DIR="$TDIR" TRACE_CONFIG="$KIT/scripts/trace.config.sh" \
	sh "$TRACE" emit kind=note reason='after the hook'
NOTE=$(ev_of note | sed -n '1p')
[ "$(str "$NOTE" session)" = "$SESSION" ] &&
	pass "a later emit from this working tree carries the session — the pointer is where trace.sh looks" ||
	fail "a later emit carried session '$(str "$NOTE" session)', so the pointer is not where trace.sh reads it"

grep -q "export TRACE_SESSION='$SESSION'" "$ENVF" &&
	pass "the export was appended to the file CLAUDE_ENV_FILE names, single-quoted" ||
	fail "no quoted 'export TRACE_SESSION=$SESSION' in $ENVF: $(cat "$ENVF")"
# And it is really shell that defines that variable and nothing else.
SOURCED=$(sh -c ". '$ENVF' && printf '%s' \"\$TRACE_SESSION\"" 2>&1)
[ "$SOURCED" = "$SESSION" ] &&
	pass "and sourcing the file sets TRACE_SESSION to exactly the session id" ||
	fail "sourcing the env file produced '$SOURCED'"

# The env-file facility is the agent harness's, and the #246 spike could not
# establish it for a resumed session. With no CLAUDE_ENV_FILE the pointer
# alone must still carry the identity.
new_trace
t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-start.sh" <"$SCRATCH/start.json"
[ "$S_STATUS" = 0 ] && pass "with no CLAUDE_ENV_FILE set the hook still exits 0" ||
	fail "the hook exited $S_STATUS with no env file: $S_ERR"
t_run_split env TRACE_DIR="$TDIR" TRACE_CONFIG="$KIT/scripts/trace.config.sh" \
	sh "$TRACE" emit kind=note reason='pointer only'
[ "$(str "$(ev_of note | sed -n '1p')" session)" = "$SESSION" ] &&
	pass "and the pointer alone still names the session on a later emit" ||
	fail "without the env file the session was lost"

# ---------------------------------------------------------------------------
banner "3. SessionEnd: one usage event per model, the streamed duplicate counted once"
# ---------------------------------------------------------------------------
new_trace
set_key transcript_path "$SCRATCH/main.jsonl" <"$FIX/session-end.payload.json" >"$SCRATCH/end.json"
if [ "$HAVE_NODE" = 1 ]; then
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end.json"
	[ "$S_STATUS" = 0 ] && pass "the hook exits 0" || fail "the hook exited $S_STATUS: $S_ERR"
	[ -z "$S_OUT" ] && pass "and says nothing on stdout" || fail "stdout carried: $S_OUT"

	[ "$(ev_of session.usage | wc -l | tr -d ' ')" = 1 ] &&
		pass "exactly one session.usage event — one model ran" ||
		fail "expected one session.usage event, got $(ev_of session.usage | wc -l)"
	U=$(ev_of session.usage | sed -n '1p')
	[ "$(str "$U" model)" = "$MODEL" ] && pass "it names the model the transcript names" ||
		fail "model is '$(str "$U" model)'"
	[ "$(str "$U" subject)" = "session:$SESSION" ] && pass "and carries the session as its subject" ||
		fail "subject is '$(str "$U" subject)'"
	# The four numbers, exact. De-duplicating by message.id gives these;
	# summing every assistant LINE gives 36 / 526 / 21036 / 51157, which is the
	# wrong implementation this assertion exists to catch.
	for pair in tok_in=34 tok_out=287 tok_cache_w=10793 tok_cache_r=37519; do
		f=${pair%=*}
		want=${pair#*=}
		got=$(num "$U" "$f")
		[ "$got" = "$want" ] && pass "$f is $want" || fail "$f is '$got', expected $want"
	done
	[ -n "$(ev_of session.end)" ] && pass "and a session.end event closes the session" ||
		fail "no session.end event"
	E=$(ev_of session.end | sed -n '1p')
	[ "$(str "$E" subject)" = "session:$SESSION" ] && pass "session.end carries the same subject" ||
		fail "session.end subject is '$(str "$E" subject)'"
else
	echo "  skip  node is not on PATH — the usage legs need the extractor"
fi

# ---------------------------------------------------------------------------
banner "4. SubagentStop: the tokens come from agent_transcript_path"
# ---------------------------------------------------------------------------
new_trace
set_key transcript_path "$SCRATCH/main.jsonl" <"$FIX/subagent-stop.payload.json" |
	set_key agent_transcript_path "$SCRATCH/sub.jsonl" >"$SCRATCH/sub-stop.json"
grep -q "\"transcript_path\": \"$SCRATCH/main.jsonl\"" "$SCRATCH/sub-stop.json" &&
	grep -q "\"agent_transcript_path\": \"$SCRATCH/sub.jsonl\"" "$SCRATCH/sub-stop.json" &&
	pass "the fixture payload still names the two transcripts apart" ||
	fail "the payload rewrite collapsed the two transcript keys"
if [ "$HAVE_NODE" = 1 ]; then
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/subagent-stop.sh" <"$SCRATCH/sub-stop.json"
	[ "$S_STATUS" = 0 ] && pass "the hook exits 0" || fail "the hook exited $S_STATUS: $S_ERR"
	A=$(ev_of agent.stop | sed -n '1p')
	[ -n "$A" ] && pass "one agent.stop event was appended" || fail "no agent.stop event"
	[ "$(str "$A" subject)" = "agent:$AGENT" ] && pass "its subject is the agent id" ||
		fail "subject is '$(str "$A" subject)'"
	[ "$(str "$A" related)" = "session:$SESSION" ] &&
		pass "and it relates to the session that spawned it" ||
		fail "related is '$(str "$A" related)'"
	case $A in *'"agent_type":"general-purpose"'*) pass "the agent type is on the event's data map" ;;
	*) fail "no agent_type in the data map: $A" ;; esac
	# The subagent's OWN numbers, from its own file — not the parent's.
	for pair in tok_in=34 tok_out=156 tok_cache_w=17138 tok_cache_r=14968; do
		f=${pair%=*}
		want=${pair#*=}
		got=$(num "$A" "$f")
		[ "$got" = "$want" ] && pass "$f is $want (the subagent's transcript, not the parent's)" ||
			fail "$f is '$got', expected $want"
	done
else
	echo "  skip  node is not on PATH — the subagent usage leg needs the extractor"
fi

# ---------------------------------------------------------------------------
banner "5. The agent harness's own rollup is the oracle for both sums together"
# ---------------------------------------------------------------------------
# The final `cost-state` line holds the session's per-model rollup and it
# INCLUDES the subagents' tokens, which live in a file the session transcript
# never names. So the trace's two halves — session.usage from the session
# transcript, agent.stop from the subagent's — must add up to it exactly. This
# is the whole reason the fixture was captured with a subagent in it.
if [ "$HAVE_NODE" = 1 ]; then
	new_trace
	env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end.json" >/dev/null 2>&1
	env TRACE_DIR="$TDIR" sh "$HOOKS/subagent-stop.sh" <"$SCRATCH/sub-stop.json" >/dev/null 2>&1
	for pair in tok_in:inputTokens tok_out:outputTokens \
		tok_cache_w:cacheCreationInputTokens tok_cache_r:cacheReadInputTokens; do
		f=${pair%:*}
		key=${pair#*:}
		want=$(rollup "$key")
		got=$(($(sum_tok "$f" session.usage) + $(sum_tok "$f" agent.stop)))
		[ -n "$want" ] || {
			fail "the fixture's cost-state line has no $key — the oracle moved"
			continue
		}
		[ "$got" = "$want" ] && pass "$f: session.usage + agent.stop = $want, the rollup's $key" ||
			fail "$f: the trace totals $got, the rollup says $want"
	done
else
	echo "  skip  node is not on PATH — the oracle leg needs the extractor"
fi

# ---------------------------------------------------------------------------
banner "6. Shape drift: the extractor exits 2, the hook records a failure and exits 0"
# ---------------------------------------------------------------------------
# A renamed usage key is the drift that matters most, because the honest
# alternative — treating a missing key as zero — produces a confident wrong
# number that nobody re-derives. `output_tokens_details` sits beside
# `output_tokens` in the real usage block, so the rename is anchored on the
# colon to move exactly one key.
sed 's/"output_tokens":/"output_tokenz":/g' "$SCRATCH/main.jsonl" >"$SCRATCH/drifted.jsonl"
grep -q '"output_tokenz":' "$SCRATCH/drifted.jsonl" && pass "the drifted fixture renames output_tokens" ||
	fail "the drift fixture was not built — nothing to test"
if [ "$HAVE_NODE" = 1 ]; then
	t_run_split node "$EXTRACTOR" "$SCRATCH/drifted.jsonl"
	[ "$S_STATUS" = 2 ] && pass "the extractor exits 2 on a renamed usage key" ||
		fail "the extractor exited $S_STATUS on drifted input (stdout: $S_OUT)"
	case $S_ERR in *output_tokens*) pass "and names the key on stderr" ;;
	*) fail "stderr does not name the key: $S_ERR" ;; esac
	case $S_ERR in *"line 19"*) pass "and names the line it gave up on" ;;
	*) fail "stderr does not name the line: $S_ERR" ;; esac
	[ -z "$S_OUT" ] && pass "and prints no numbers — a partial sum is the failure mode" ||
		fail "the extractor printed numbers anyway: $S_OUT"

	new_trace
	set_key transcript_path "$SCRATCH/drifted.jsonl" <"$FIX/session-end.payload.json" >"$SCRATCH/end-drift.json"
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-drift.json"
	[ "$S_STATUS" = 0 ] && pass "the hook still exits 0 — a trace failure is never a session failure" ||
		fail "the hook exited $S_STATUS on drifted input"
	F=$(ev_of session.usage | sed -n '1p')
	[ "$(str "$F" outcome)" = fail ] && pass "and emits session.usage with outcome=fail" ||
		fail "the usage event's outcome is '$(str "$F" outcome)': $F"
	case $F in *output_tokens*) pass "whose reason names the key that drifted" ;;
	*) fail "the reason does not name the key: $F" ;; esac
	[ -z "$(num "$F" tok_out)" ] && pass "and carries no token counts it could not read" ||
		fail "the fail event carried tokens: $F"
	[ -n "$(ev_of session.end)" ] && pass "and session.end is still emitted" || fail "no session.end after drift"
else
	echo "  skip  node is not on PATH — the drift legs need the extractor"
fi

# ---------------------------------------------------------------------------
banner "7. No node: the same shape, naming node"
# ---------------------------------------------------------------------------
# The kit's core is sh and git only; the extractor is the one part of this
# adapter with a runtime. A consumer without node must get a recorded reason,
# not a silent gap and not a broken session.
NONODE=$(no_node_path)
if env PATH="$NONODE" sh -c 'command -v node >/dev/null 2>&1'; then
	fail "the scrubbed PATH still finds node — the leg would prove nothing"
else
	pass "the scrubbed PATH finds no node"
	new_trace
	t_run_split env PATH="$NONODE" TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end.json"
	[ "$S_STATUS" = 0 ] && pass "the hook exits 0 with no node on PATH" ||
		fail "the hook exited $S_STATUS with no node: $S_ERR"
	F=$(ev_of session.usage | sed -n '1p')
	[ "$(str "$F" outcome)" = fail ] && pass "and emits session.usage with outcome=fail" ||
		fail "the usage event's outcome is '$(str "$F" outcome)': $F"
	case $F in *node*) pass "whose reason names node" ;;
	*) fail "the reason does not name node: $F" ;; esac
	[ -n "$(ev_of session.end)" ] && pass "and session.end is still emitted" ||
		fail "no session.end without node"
fi

# ---------------------------------------------------------------------------
banner "8. Unconfigured is a working state, and a hook is silent about it"
# ---------------------------------------------------------------------------
# Every hook sets TRACE_QUIET=1 (ADR-0008 clause 2): the unconfigured note is
# a nudge for an operator running a command, and a hook runs unattended on
# every session start. A word on stderr per session is noise nobody asked for.
for h in session-start session-end subagent-stop; do
	case $h in
	session-start) P="$SCRATCH/start.json" ;;
	session-end) P="$SCRATCH/end.json" ;;
	*) P="$SCRATCH/sub-stop.json" ;;
	esac
	t_run_split env TRACE_DIR= sh "$HOOKS/$h.sh" <"$P"
	[ "$S_STATUS" = 0 ] && pass "$h.sh exits 0 with tracing off" || fail "$h.sh exited $S_STATUS"
	[ -z "$S_OUT" ] && [ -z "$S_ERR" ] && pass "$h.sh is silent on both streams with tracing off" ||
		fail "$h.sh spoke with tracing off — out: '$S_OUT' err: '$S_ERR'"
	# And an empty payload — a hook must not depend on a key being there.
	t_run_split env TRACE_DIR= sh "$HOOKS/$h.sh" </dev/null
	[ "$S_STATUS" = 0 ] && pass "$h.sh exits 0 on an empty payload" ||
		fail "$h.sh exited $S_STATUS on an empty payload: $S_ERR"
done

# A payload with no session id, traced: the hook records the absence rather
# than emitting an event nobody can join on, and still exits 0.
new_trace
t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-start.sh" </dev/null
[ "$S_STATUS" = 0 ] && pass "session-start.sh exits 0 on an empty payload with tracing on" ||
	fail "session-start.sh exited $S_STATUS"
N=$(ev_of session.start | sed -n '1p')
[ "$(str "$N" outcome)" = fail ] && pass "and records session.start outcome=fail instead of a subject it does not have" ||
	fail "the event's outcome is '$(str "$N" outcome)': $N"
[ -z "$(str "$N" subject)" ] && pass "with no subject invented for it" ||
	fail "a subject was invented: $(str "$N" subject)"

# ---------------------------------------------------------------------------
banner "9. The kit's settings file parses, and names only commands that exist"
# ---------------------------------------------------------------------------
if [ -f "$SETTINGS" ]; then
	pass ".claude/settings.json exists"
	if [ "$HAVE_NODE" = 1 ]; then
		assert_status 0 ".claude/settings.json is JSON a real parser accepts" -- \
			node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$SETTINGS"
	else
		echo "  skip  node is not on PATH — the JSON parse check needs it"
	fi
	for ev in SessionStart SessionEnd SubagentStop; do
		grep -q "\"$ev\"" "$SETTINGS" && pass "it wires $ev" || fail "it does not wire $ev"
	done
	# Every command it names must resolve to a file in this tree, with
	# $CLAUDE_PROJECT_DIR standing for the repo root as the agent harness
	# substitutes it. A settings file naming a script nobody wrote is a hook
	# that fails on every session and says so only in a log.
	cmds=$(sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$SETTINGS" | sed 's/\\"/"/g')
	[ -n "$cmds" ] && pass "it names at least one command" || fail "it names no command at all"
	# A `for` loop and not a pipeline: a `while read` in a pipeline runs in a
	# subshell, and every failure it counted would die with it.
	scripts=$(printf '%s\n' "$cmds" | tr ' ' '\n' | grep '/hooks/' | tr -d '"' || :)
	[ "$(printf '%s\n' "$scripts" | grep -c .)" = 3 ] &&
		pass "it names one hook script per event, three in all" ||
		fail "it names $(printf '%s\n' "$scripts" | grep -c .) hook script(s), expected 3"
	for script in $scripts; do
		resolved=$(printf '%s' "$script" | sed "s|\\\$CLAUDE_PROJECT_DIR|$KIT|; s|\\\${CLAUDE_PROJECT_DIR}|$KIT|")
		[ -f "$resolved" ] && pass "${resolved#"$KIT"/} exists" ||
			fail "the settings file names $resolved, which does not exist"
	done
	# And it must reach the KIT's own trace policy, not the shipped empty one —
	# hard rule 10's arrangement, spelled in the one file that may name a
	# kit-only path because it never ships.
	grep -q 'TRACE_CONFIG=scripts/trace.kit.config.sh' "$SETTINGS" &&
		pass "it points the hooks at the kit's own trace policy file" ||
		fail "it does not set TRACE_CONFIG=scripts/trace.kit.config.sh — the hooks would read the empty shipped policy and write nothing"
else
	fail ".claude/settings.json does not exist"
fi

# ---------------------------------------------------------------------------
banner "10. The adapter stays dormant for a consumer"
# ---------------------------------------------------------------------------
# The hooks SHIP (adapters/ is not on the kit-only list) and must arrive inert:
# nothing in the tree may name them. The settings file is the only wiring, and
# it is kit-only — tests/adapters-demo.sh asserts a bootstrapped consumer has
# none, and tests/self-host.test.sh asserts it never leaks.
# Two files outside the adapter and its suite may name a hook path, and both
# earn it: the kit-only settings file, which is the wiring, and bootstrap.sh,
# whose KIT_ONLY note explains why the scripts ship and the wiring does not. A
# THIRD one is the thing to look at — it is how a dormant adapter quietly
# acquires a caller. (That a CONSUMER receives no wiring is a different claim,
# and tests/adapters-demo.sh proves it against a real bootstrap.)
#
# THE TRACKED TREE, through `git grep`, not the working tree through `grep -r`:
# the claim is about what the kit SHIPS, and a scratch file left beside the
# checkout ships nowhere. The first draft read the working tree and went red on
# the PR body this very ticket's session left in the worktree (M-5, review of
# PR #291) — a suite that fails on an untracked file is failing about the
# wrong tree.
#
# It is a TRIPWIRE, not a proof: it matches the literal `claude-code/hooks/`,
# so a file that spells the same call as `$HOOKS/session-start.sh` walks past
# it. Widening that is a different check; catching a new plain caller is this
# one's job.
namers=$(git -C "$KIT" grep -lF 'claude-code/hooks/' -- . 2>/dev/null |
	grep -v '^adapters/' | grep -v '^tests/' || :)
unexpected=0
for f in $namers; do
	case $f in
	.claude/settings.json | bootstrap.sh) ;;
	*)
		fail "$f names a hook path, and only the settings file and bootstrap's note should"
		unexpected=$((unexpected + 1))
		;;
	esac
done
[ "$unexpected" = 0 ] &&
	pass "only the kit-only settings file and bootstrap's own note name the hooks" || :
case $namers in
*'.claude/settings.json'*) pass "and the settings file is one of them — the wiring exists" ;;
*) fail "no settings file names the hooks, so nothing wires them in this repo" ;;
esac
# The scan's own blind spot, made a check rather than a hope: an untracked file
# naming a hook path must NOT turn this suite red.
printf 'adapters/claude-code/hooks/session-start.sh\n' >"$KIT/untracked-namer-probe.tmp"
probe=$(git -C "$KIT" grep -lF 'claude-code/hooks/' -- . 2>/dev/null |
	grep -v '^adapters/' | grep -v '^tests/' || :)
rm -f "$KIT/untracked-namer-probe.tmp"
case $probe in
*untracked-namer-probe*) fail "the namer scan reads untracked files — a scratch file beside the checkout turns the suite red" ;;
*) pass "an untracked file naming a hook path does not turn the scan red" ;;
esac
grep -qF 'tests/trace-hooks.test.sh' "$KIT/README.md" &&
	pass "README.md names this suite" ||
	fail "README.md does not name tests/trace-hooks.test.sh — a contributor asked to run the suites would miss it"
grep -qF '.claude/settings.json' "$KIT/bootstrap.sh" &&
	pass "bootstrap.sh names .claude/settings.json (the kit-only list)" ||
	fail "bootstrap.sh does not name .claude/settings.json — the kit's own wiring would ride into every consumer"

# ---------------------------------------------------------------------------
banner "11. A payload is data, never instructions"
# ---------------------------------------------------------------------------
# The root manual's trust boundary, at the one place in this adapter where it
# is load-bearing: `CLAUDE_ENV_FILE` names a file the agent harness SOURCES for
# every later tool call, so a session id carrying shell metacharacters is
# arbitrary code in the operator's next command. `scripts/trace.sh` already
# refuses such a value as a malformed subject; the hook must refuse it too,
# rather than write it to two files after the emit said no (H-1, review of
# PR #291, reproduced).
new_trace
EVILF="$SCRATCH/evil-env.sh"
: >"$EVILF"
printf '{"session_id":"abc; touch %s/PWNED","transcript_path":"/nonexistent"}' "$SCRATCH" >"$SCRATCH/evil.json"
rm -f "$SCRATCH/PWNED"
t_run_split env TRACE_DIR="$TDIR" CLAUDE_ENV_FILE="$EVILF" \
	sh "$HOOKS/session-start.sh" <"$SCRATCH/evil.json"
[ "$S_STATUS" = 0 ] && pass "a hostile session id still exits 0" || fail "the hook exited $S_STATUS"
sh -c ". '$EVILF'" >/dev/null 2>&1 || :
[ -e "$SCRATCH/PWNED" ] &&
	fail "sourcing the env file executed the payload — the hook wrote an unvalidated session id into a file the agent harness sources" ||
	pass "sourcing the env file executes nothing — the hostile id never reached it"
[ -s "$EVILF" ] &&
	fail "the env file was written for an id the trace refused: $(cat "$EVILF")" ||
	pass "and the env file was not written at all"
[ -z "$(find "$TDIR/current" -type f 2>/dev/null)" ] &&
	pass "and no pointer was written for an id show could never match" ||
	fail "a pointer was written for a refused id: $(cat "$TDIR"/current/* 2>/dev/null)"
V=$(ev_of session.start | sed -n '1p')
[ "$(str "$V" outcome)" = fail ] &&
	pass "and the event records the refusal with outcome=fail" ||
	fail "the event's outcome is '$(str "$V" outcome)': $V"

# ---------------------------------------------------------------------------
banner "12. The hook's own session id wins over the pointer file"
# ---------------------------------------------------------------------------
# The pointer is per-toplevel, so two sessions in one checkout overwrite each
# other's. A hook HOLDS the authoritative id — it is on the payload — and must
# put it on its own events rather than letting a stale pointer answer: without
# that, the first session's session.end is filed under the second session's id
# while its subject says the first, and `summary --by session` lies (M-2,
# review of PR #291).
new_trace
mkdir -p "$TDIR/current"
for p in "$TDIR"/current/*; do :; done
env TRACE_DIR="$TDIR" sh "$HOOKS/session-start.sh" <"$SCRATCH/start.json" >/dev/null 2>&1
# Now overwrite the pointer with ANOTHER session, as a second session start in
# the same checkout would, and close the first one.
for p in "$TDIR"/current/*; do [ -e "$p" ] && printf 'ffffffff-0000-0000-0000-000000000000\n' >"$p"; done
if [ "$HAVE_NODE" = 1 ]; then
	env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end.json" >/dev/null 2>&1
	env TRACE_DIR="$TDIR" sh "$HOOKS/subagent-stop.sh" <"$SCRATCH/sub-stop.json" >/dev/null 2>&1
	for k in session.usage session.end agent.stop; do
		L=$(ev_of "$k" | sed -n '1p')
		[ "$(str "$L" session)" = "$SESSION" ] &&
			pass "$k carries the payload's own session, not the pointer's" ||
			fail "$k carries session '$(str "$L" session)', so a stale pointer answered for it"
	done
else
	echo "  skip  node is not on PATH — the usage legs need the extractor"
fi

# ---------------------------------------------------------------------------
banner "13. Node's own stderr never becomes a token count or a reason"
# ---------------------------------------------------------------------------
# The extractor's rows and node's diagnostics are two streams, and merging them
# means an ExperimentalWarning either feeds a garbage row to `emit` or is
# recorded as the reason a key drifted (M-1, review of PR #291). The fixture is
# a node that warns and then execs the real one.
if [ "$HAVE_NODE" = 1 ]; then
	REALNODE=$(command -v node)
	mkdir -p "$SCRATCH/warnbin"
	{
		printf '#!/bin/sh\n'
		printf 'echo "(node:999) ExperimentalWarning: something is experimental" >&2\n'
		printf 'exec %s "$@"\n' "$REALNODE"
	} >"$SCRATCH/warnbin/node"
	chmod +x "$SCRATCH/warnbin/node"

	new_trace
	env PATH="$SCRATCH/warnbin:$PATH" TRACE_DIR="$TDIR" \
		sh "$HOOKS/session-end.sh" <"$SCRATCH/end.json" >/dev/null 2>&1
	W=$(ev_of session.usage | sed -n '1p')
	[ "$(str "$W" model)" = "$MODEL" ] && [ "$(num "$W" tok_in)" = 34 ] &&
		pass "a warning on node's stderr leaves the row intact" ||
		fail "node's warning contaminated the row: $W"
	[ "$(ev_of session.usage | wc -l | tr -d ' ')" = 1 ] &&
		pass "and adds no second usage event" ||
		fail "node's warning produced $(ev_of session.usage | wc -l) usage events"

	new_trace
	env PATH="$SCRATCH/warnbin:$PATH" TRACE_DIR="$TDIR" \
		sh "$HOOKS/session-end.sh" <"$SCRATCH/end-drift.json" >/dev/null 2>&1
	W=$(ev_of session.usage | sed -n '1p')
	case $W in
	*ExperimentalWarning*) fail "the recorded reason is node's warning, not the key that drifted: $W" ;;
	*output_tokens*) pass "and a drift reason still names the key, not the warning" ;;
	*) fail "the drift reason names neither: $W" ;;
	esac
else
	echo "  skip  node is not on PATH — the warning legs need a real node to wrap"
fi

# ---------------------------------------------------------------------------
banner "14. A transcript's placeholder model never becomes a row"
# ---------------------------------------------------------------------------
# An API error is written as an assistant line whose model is a placeholder and
# whose counts are all zero. It passes every shape check, and `model` is a join
# column — so it would grow a row in every `summary --by model` that every
# later reader has to know to ignore (M-3, review of PR #291).
if [ "$HAVE_NODE" = 1 ]; then
	{
		cat "$SCRATCH/main.jsonl"
		printf '%s\n' '{"type":"assistant","isApiErrorMessage":true,"requestId":"req_err","message":{"id":"msg_err","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
	} >"$SCRATCH/synthetic.jsonl"
	t_run_split node "$EXTRACTOR" "$SCRATCH/synthetic.jsonl"
	[ "$S_STATUS" = 0 ] && pass "a placeholder-model line does not make the extractor exit 2" ||
		fail "the extractor exited $S_STATUS on a placeholder line: $S_ERR"
	case $S_OUT in
	*'<synthetic>'*) fail "the placeholder model became a row: $S_OUT" ;;
	*) pass "and it produces no row of its own" ;;
	esac
	case $S_OUT in
	"$MODEL 34 287 10793 37519") pass "while the real model's numbers are untouched" ;;
	*) fail "the real row changed: $S_OUT" ;;
	esac
else
	echo "  skip  node is not on PATH — the placeholder leg needs the extractor"
fi

# ---------------------------------------------------------------------------
banner "15. A transcript with no usage to read is a countable failure"
# ---------------------------------------------------------------------------
# The live gap this adapter documents — SubagentStop running before the
# subagent's transcript has its assistant line — must be countable from the
# trace, or the follow-up ticket that closes it has no acceptance (M-6, review
# of PR #291). Without outcome=fail it is indistinguishable from a subagent
# that genuinely spent nothing.
if [ "$HAVE_NODE" = 1 ]; then
	new_trace
	printf '{"type":"user","message":{"role":"user"}}\n' >"$SCRATCH/nousage.jsonl"
	set_key agent_transcript_path "$SCRATCH/nousage.jsonl" <"$SCRATCH/sub-stop.json" >"$SCRATCH/sub-nousage.json"
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/subagent-stop.sh" <"$SCRATCH/sub-nousage.json"
	[ "$S_STATUS" = 0 ] && pass "the hook exits 0 when the transcript has no usage yet" ||
		fail "the hook exited $S_STATUS"
	G=$(ev_of agent.stop | sed -n '1p')
	[ "$(str "$G" outcome)" = fail ] &&
		pass "and the event carries outcome=fail, so the holes can be counted" ||
		fail "the event's outcome is '$(str "$G" outcome)': $G"
	case $G in *'"subject":"agent:'*) pass "while still naming the agent it could not price" ;;
	*) fail "the event lost its subject: $G" ;; esac
else
	echo "  skip  node is not on PATH — this leg needs the extractor"
fi

# ---------------------------------------------------------------------------
banner "16. A transcript path the agent harness abbreviated still opens"
# ---------------------------------------------------------------------------
# `hook_expand` turns a leading `~` into the home directory. The fixtures carry
# `~` because the REDACTION put it there, not because the agent harness emits
# it — the live capture's paths are absolute. So the branch guards a shape
# nothing here produces, which is exactly why it needs a case of its own rather
# than a comment (M-4, review of PR #291).
if [ "$HAVE_NODE" = 1 ]; then
	HOMEDIR=$(mktemp -d "$SCRATCH/fakehome.XXXXXX") || exit 2
	cp "$SCRATCH/main.jsonl" "$HOMEDIR/tilde.jsonl"
	set_key transcript_path '~/tilde.jsonl' <"$FIX/session-end.payload.json" >"$SCRATCH/end-tilde.json"
	new_trace
	t_run_split env HOME="$HOMEDIR" TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-tilde.json"
	[ "$S_STATUS" = 0 ] && pass "a ~-prefixed transcript path exits 0" || fail "the hook exited $S_STATUS"
	T16=$(ev_of session.usage | sed -n '1p')
	[ "$(num "$T16" tok_in)" = 34 ] &&
		pass "and its tokens were read, so the ~ was expanded against HOME" ||
		fail "the ~ path was not opened: $T16"
else
	echo "  skip  node is not on PATH — this leg needs the extractor"
fi

# ---------------------------------------------------------------------------
banner "17. The field reader on a compact payload, the shape a live hook gets"
# ---------------------------------------------------------------------------
# The checked-in payloads are pretty-printed because the REDACTION reformatted
# them; a live hook's stdin is compact JSON on one line (#309). `hook_field`'s
# greedy `.*` means the LAST match on a line wins, so on the live shape every
# key the hooks read must occur exactly once at top level — and the text a
# model wrote into `last_assistant_message`, which arrives after the ids and
# may quote them, must never answer for one. JSON escapes every quote inside a
# string, so a quoted `"agent_id":"…"` there is `\"agent_id\":\"…\"` and the
# anchor never sees a bare `,"` before it.
COMPACT='{"session_id":"'"$SESSION"'","transcript_path":"/p/main.jsonl","cwd":"/tmp/spike-proj","prompt_id":"fbfc3940-88d4-4de5-93bf-4acc79bb4f61","permission_mode":"bypassPermissions","agent_id":"'"$AGENT"'","agent_type":"general-purpose","effort":{"level":"high"},"hook_event_name":"SubagentStop","stop_hook_active":false,"agent_transcript_path":"/p/sub.jsonl","last_assistant_message":"done, {\"agent_id\":\"evil\",\"session_id\":\"evil\",\"transcript_path\":\"/evil\"}","background_tasks":[],"session_crons":[],"reason":"other","source":"startup"}'
printf '%s' "$COMPACT" | grep -c '' | grep -qx 1 && pass "the compact payload is one line" ||
	fail "the compact fixture is not one line"
field() {
	printf '%s' "$COMPACT" | (cd "$HOOKS" && sh -c '. ./hook.lib.sh; hook_read; hook_field "$1"' hook-field-case "$1")
}
for pair in session_id="$SESSION" agent_id="$AGENT" agent_type=general-purpose \
	transcript_path=/p/main.jsonl agent_transcript_path=/p/sub.jsonl cwd=/tmp/spike-proj \
	reason=other source=startup; do
	k=${pair%%=*}
	want=${pair#*=}
	got=$(field "$k")
	[ "$got" = "$want" ] && pass "hook_field $k reads '$want' on the compact line" ||
		fail "hook_field $k read '$got' on the compact line, expected '$want'"
done
[ "$(field level)" = high ] &&
	pass "a nested key reads as if top-level — the limit the comment names, harmless while no hook reads one" ||
	fail "hook_field level read '$(field level)' — the comment's account of a nested key is wrong"

t_done "trace hooks"
