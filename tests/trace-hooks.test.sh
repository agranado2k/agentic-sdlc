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
TOOLREADER="$HOOKS/tool-payload.mjs"
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
for f in hook.lib.sh session-start.sh session-end.sh subagent-stop.sh tool-post.sh; do
	if [ -f "$HOOKS/$f" ]; then
		assert_status 0 "adapters/claude-code/hooks/$f parses under sh -n" -- sh -n "$HOOKS/$f"
	else
		fail "adapters/claude-code/hooks/$f does not exist"
	fi
done
if [ "$HAVE_NODE" = 1 ]; then
	assert_status 0 "the extractor parses under node --check" -- node --check "$EXTRACTOR"
	assert_status 0 "the tool payload reader parses under node --check" -- node --check "$TOOLREADER"
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
# TRACE_TOOLS=1 throughout: the three session hooks never read it, and the tool
# hook must be silent because TRACING is off rather than because its own switch
# is — two reasons for one silence, told apart.
for h in session-start session-end subagent-stop tool-post; do
	case $h in
	session-start) P="$SCRATCH/start.json" ;;
	session-end) P="$SCRATCH/end.json" ;;
	subagent-stop) P="$SCRATCH/sub-stop.json" ;;
	*) P="$FIX/tool-post.payload.json" ;;
	esac
	t_run_split env TRACE_DIR= TRACE_TOOLS=1 sh "$HOOKS/$h.sh" <"$P"
	[ "$S_STATUS" = 0 ] && pass "$h.sh exits 0 with tracing off" || fail "$h.sh exited $S_STATUS"
	[ -z "$S_OUT" ] && [ -z "$S_ERR" ] && pass "$h.sh is silent on both streams with tracing off" ||
		fail "$h.sh spoke with tracing off — out: '$S_OUT' err: '$S_ERR'"
	# And an empty payload — a hook must not depend on a key being there.
	t_run_split env TRACE_DIR= TRACE_TOOLS=1 sh "$HOOKS/$h.sh" </dev/null
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
	# EVERY WIRED EVENT, TIED TO ITS OWN COMMAND — and the check shown failing.
	# An event-name grep and a command count are both satisfied by a settings
	# file whose new commands read the SHIPPED policy, which is empty: tool
	# capture would then write nothing while every assertion here stayed green
	# (M-5, review of PR #295). So the JSON is parsed, each event is tied to the
	# script it must run AND the policy it must select, and the same function is
	# run against a sabotaged copy that must FAIL — a check nobody has seen fail
	# is a claim.
	#
	# The while loop reads a FILE, not a pipe: a pipeline's loop runs in a
	# subshell and the count it kept would die with it.
	wiring_rows="$SCRATCH/wiring-252.txt"
	wiring_ok() {
		node -e 'const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
			for (const [ev, groups] of Object.entries(s.hooks || {}))
				for (const g of groups)
					for (const h of (g.hooks || []))
						console.log(ev + " " + String(h.command).replace(/\s+/g, " "));' \
			"$1" >"$wiring_rows" || return 1
		_w_bad=0
		while read -r _w_ev _w_cmd; do
			case $_w_ev in
			SessionStart) _w_want=session-start.sh ;;
			SessionEnd) _w_want=session-end.sh ;;
			SubagentStop) _w_want=subagent-stop.sh ;;
			PostToolUse | PostToolUseFailure) _w_want=tool-post.sh ;;
			*)
				_w_bad=1
				continue
				;;
			esac
			case $_w_cmd in *"/hooks/$_w_want"*) ;; *) _w_bad=1 ;; esac
			case $_w_cmd in *'TRACE_CONFIG=scripts/trace.kit.config.sh'*) ;; *) _w_bad=1 ;; esac
		done <"$wiring_rows"
		[ "$_w_bad" = 0 ]
	}
	if [ "$HAVE_NODE" = 1 ]; then
		wiring_ok "$SETTINGS" &&
			pass "every wired event runs its own hook script through the kit's trace policy" ||
			fail "a wired event names the wrong script or reads the shipped empty policy: $(cat "$wiring_rows")"
		for ev in SessionStart SessionEnd SubagentStop PostToolUse PostToolUseFailure; do
			grep -q "^$ev " "$wiring_rows" && pass "it wires $ev" || fail "it does not wire $ev"
		done
		sed '/tool-post.sh/s|TRACE_CONFIG=scripts/trace.kit.config.sh ||' "$SETTINGS" \
			>"$SCRATCH/settings-sabotaged-252.json"
		[ "$(grep -c 'trace.kit.config.sh' "$SCRATCH/settings-sabotaged-252.json")" -lt \
			"$(grep -c 'trace.kit.config.sh' "$SETTINGS")" ] &&
			pass "the sabotaged copy really does drop the policy from the post-tool commands" ||
			fail "the sabotage changed nothing, so the probe below proves nothing"
		wiring_ok "$SCRATCH/settings-sabotaged-252.json" &&
			fail "the wiring check passes a file whose post-tool commands read the shipped OFF policy" ||
			pass "and the check FAILS on that copy — it is load-bearing"
	else
		for ev in SessionStart SessionEnd SubagentStop PostToolUse PostToolUseFailure; do
			grep -q "\"$ev\"" "$SETTINGS" && pass "it wires $ev" || fail "it does not wire $ev"
		done
		echo "  skip  node is not on PATH — the per-event wiring check needs a JSON parser"
	fi
	# Every command it names must resolve to a file in this tree, with
	# $CLAUDE_PROJECT_DIR standing for the repo root as the agent harness
	# substitutes it. A settings file naming a script nobody wrote is a hook
	# that fails on every session and says so only in a log.
	cmds=$(sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$SETTINGS" | sed 's/\\"/"/g')
	[ -n "$cmds" ] && pass "it names at least one command" || fail "it names no command at all"
	# A `for` loop and not a pipeline: a `while read` in a pipeline runs in a
	# subshell, and every failure it counted would die with it.
	scripts=$(printf '%s\n' "$cmds" | tr ' ' '\n' | grep '/hooks/' | tr -d '"' || :)
	# Five events, four scripts: one script serves both post-tool events,
	# because the only difference between them is the outcome it records.
	[ "$(printf '%s\n' "$scripts" | grep -c .)" = 5 ] &&
		pass "it names a hook script per wired event, five in all" ||
		fail "it names $(printf '%s\n' "$scripts" | grep -c .) hook script(s), expected 5"
	for script in $scripts; do
		resolved=$(printf '%s' "$script" | sed "s|\\\$CLAUDE_PROJECT_DIR|$KIT|; s|\\\${CLAUDE_PROJECT_DIR}|$KIT|")
		[ -f "$resolved" ] && pass "${resolved#"$KIT"/} exists" ||
			fail "the settings file names $resolved, which does not exist"
	done
	# Reaching the KIT's own trace policy rather than the shipped empty one —
	# hard rule 10's arrangement, spelled in the one file that may name a
	# kit-only path because it never ships — is asserted per event above.
	grep -q 'TRACE_CONFIG=scripts/trace.kit.config.sh' "$SETTINGS" &&
		pass "and the kit-only policy path is in the file at all" ||
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
banner "17. Tool capture is a switch of its own, and it ships OFF"
# ---------------------------------------------------------------------------
# Volume is the whole reason TRACE_TOOLS exists beside TRACE_DIR (ADR-0008
# clause 8): one tool call is the least decision-bearing line in the trace and
# there are hundreds of them in a session, so a project that wants its
# decisions traced must still SAY it wants its tool calls. The switch lives in
# the policy file, which ships with it empty, and the kit's never-shipped twin
# is what turns it on here.
#
# The shipped policy file is what answers below: no TRACE_CONFIG is set, so the
# hook discovers scripts/trace.config.sh exactly as scripts/trace.sh does from
# the same directory. That is the consumer's case, tested against the real file
# rather than a fixture of it.
TSESSION=a09ab9f2-8320-4e3b-8247-42e4c7f2b0d1
TUSE=toolu_01XTkTiAfuhWc79ZjF1HK9i7
TUSE_FAIL=toolu_01ULrFzD48yvC1ekTWobKfZZ
# The two payloads a tool call is made of, verbatim from the fixture: this is
# what `git hash-object` is asked about below, and the hook must store these
# bytes and no others.
TIN='{"command":"cat file.txt","description":"Print contents of file.txt"}'
TOUT='{"stdout":"hello","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false}'
TERR='"Exit code 1\ncat: /nonexistent/nope: No such file or directory"'

# hash_of <text> — git's content hash of exactly those bytes, no trailing
# newline. The same hash scripts/trace.sh's blob store names a payload by, and
# the acceptance the ticket states.
hash_of() { printf '%s' "$1" | (unset GIT_DIR GIT_WORK_TREE && git hash-object --stdin); }

# blob_file <hash> — where a stored blob sits under the trace directory.
blob_file() { printf '%s/blobs/%s/%s' "$TDIR" "$(printf '%.2s' "$1")" "$1"; }

# tool_post <env…> — the hook, on the success fixture unless PAYLOAD says else.
tool_post() { t_run_split env "$@" sh "$HOOKS/tool-post.sh" <"$PAYLOAD"; }

PAYLOAD="$FIX/tool-post.payload.json"

new_trace
tool_post TRACE_DIR="$TDIR"
[ "$S_STATUS" = 0 ] && pass "the hook exits 0 with the switch unset" ||
	fail "the hook exited $S_STATUS with the switch unset: $S_ERR"
[ -z "$S_OUT" ] && [ -z "$S_ERR" ] &&
	pass "and is silent on both streams — an unasked-for switch is not a nudge" ||
	fail "the hook spoke with the switch unset — out: '$S_OUT' err: '$S_ERR'"
[ -z "$(events)" ] &&
	pass "and appended NOTHING: the shipped policy file leaves TRACE_TOOLS empty" ||
	fail "the switch is off and an event was written anyway: $(events)"
[ ! -d "$TDIR/blobs" ] && pass "and stored no blob" ||
	fail "the switch is off and a blob was stored: $(find "$TDIR/blobs" -type f)"
grep -q "^TRACE_TOOLS=''" "$KIT/scripts/trace.config.sh" &&
	pass "scripts/trace.config.sh ships the switch empty" ||
	fail "scripts/trace.config.sh does not ship TRACE_TOOLS=''"
grep -q "^TRACE_TOOLS=1" "$KIT/scripts/trace.kit.config.sh" &&
	pass "and the kit's own twin turns it on for this repo" ||
	fail "scripts/trace.kit.config.sh does not set TRACE_TOOLS=1"

if [ "$HAVE_NODE" = 1 ]; then
	# The twin, read through the same seam the settings file uses.
	new_trace
	tool_post TRACE_DIR="$TDIR" TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh"
	[ "$S_STATUS" = 0 ] && pass "with the kit's twin answering, the hook still exits 0" ||
		fail "the hook exited $S_STATUS: $S_ERR"
	[ "$(ev_of tool.use | wc -l | tr -d ' ')" = 1 ] &&
		pass "and the twin's TRACE_TOOLS=1 produces one tool.use event" ||
		fail "expected one tool.use event through the twin, got $(ev_of tool.use | wc -l)"

	# The environment beats the file, both ways — the same precedence
	# scripts/trace.sh gives TRACE_DIR, so a suite and an operator can flip the
	# switch for one process without editing policy.
	new_trace
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	[ "$(ev_of tool.use | wc -l | tr -d ' ')" = 1 ] &&
		pass "TRACE_TOOLS=1 in the environment turns it on over an empty file" ||
		fail "the environment did not turn the switch on: $(events)"
	new_trace
	tool_post TRACE_DIR="$TDIR" TRACE_CONFIG="$KIT/scripts/trace.kit.config.sh" TRACE_TOOLS=
	[ -z "$(events)" ] &&
		pass "and TRACE_TOOLS= in the environment turns it off over a file that says 1" ||
		fail "the environment's OFF lost to the file: $(events)"
else
	echo "  skip  node is not on PATH — the capture legs need the payload reader"
fi

# ---------------------------------------------------------------------------
banner "18. One tool call is ONE event with TWO blobs"
# ---------------------------------------------------------------------------
# The shape the ticket states: the tool, its use id and the head of its input
# on the line; the FULL input and the FULL result in the blob store, named by
# git's hash of the bytes that were stored. One event per call, because a
# reader joining two half-events per tool call is the volume this switch exists
# to contain.
if [ "$HAVE_NODE" = 1 ]; then
	new_trace
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	[ "$S_STATUS" = 0 ] && pass "the hook exits 0" || fail "the hook exited $S_STATUS: $S_ERR"
	[ -z "$S_OUT" ] && pass "and says nothing on stdout — the agent harness reads that stream" ||
		fail "the hook printed on stdout: $S_OUT"
	[ "$(events | wc -l | tr -d ' ')" = 1 ] &&
		pass "exactly one event was appended, of any kind" ||
		fail "expected one event, got $(events | wc -l): $(events)"
	T=$(ev_of tool.use | sed -n '1p')
	[ -n "$T" ] && pass "and it is a tool.use event" || fail "no tool.use event: $(events)"
	[ "$(str "$T" subject)" = "session:$TSESSION" ] &&
		pass "its subject is the session, so \`show session:<id>\` reads the call" ||
		fail "subject is '$(str "$T" subject)', not session:$TSESSION"
	[ "$(str "$T" session)" = "$TSESSION" ] && pass "and it carries the session field too" ||
		fail "session is '$(str "$T" session)'"
	[ "$(str "$T" outcome)" = ok ] && pass "a PostToolUse payload records outcome=ok" ||
		fail "outcome is '$(str "$T" outcome)'"
	[ "$(str "$T" harness)" = claude-code ] && pass "and names the agent harness it came from" ||
		fail "harness is '$(str "$T" harness)'"
	[ "$(str "$T" tool)" = Bash ] && pass "data.tool is the tool's name" ||
		fail "data.tool is '$(str "$T" tool)'"
	[ "$(str "$T" tool_use_id)" = "$TUSE" ] && pass "data.tool_use_id is the payload's id" ||
		fail "data.tool_use_id is '$(str "$T" tool_use_id)'"

	# THE HEAD, inline: the input's first bytes, escaped by the trace's own
	# rules — which is why the assertion looks for the ESCAPED quotes.
	printf '%s\n' "$T" | grep -qF '"input_head":"{\"command\":\"cat file.txt' &&
		pass "data.input_head carries the head of the input, escaped" ||
		fail "data.input_head is not the escaped input: $T"

	# THE TWO BLOBS. Their names are git's hash of the payloads, and the stored
	# bytes are the payloads — both halves asserted, because a hash that
	# matches a file nobody can find is not a record of anything.
	IH=$(hash_of "$TIN")
	RH=$(hash_of "$TOUT")
	[ "$(str "$T" input_blob)" = "$IH" ] &&
		pass "data.input_blob is git's hash of the payload's tool_input" ||
		fail "data.input_blob is '$(str "$T" input_blob)', git says $IH"
	[ "$(str "$T" result_blob)" = "$RH" ] &&
		pass "data.result_blob is git's hash of the payload's tool_response" ||
		fail "data.result_blob is '$(str "$T" result_blob)', git says $RH"
	[ "$(cat "$(blob_file "$IH")" 2>/dev/null)" = "$TIN" ] &&
		pass "and the input blob holds those bytes, under blobs/<first two>/<hash>" ||
		fail "the input blob at $(blob_file "$IH") does not hold the input"
	[ "$(cat "$(blob_file "$RH")" 2>/dev/null)" = "$TOUT" ] &&
		pass "and the result blob holds the result's bytes" ||
		fail "the result blob at $(blob_file "$RH") does not hold the result"
	# A data value is a STRING in schema 1, so the size reads back as one.
	[ "$(str "$T" result_bytes)" = "$(printf '%s' "$TOUT" | wc -c | tr -d ' ')" ] &&
		pass "data.result_bytes is the result's size, so a reader knows before it opens" ||
		fail "data.result_bytes is '$(str "$T" result_bytes)', the result is $(printf '%s' "$TOUT" | wc -c | tr -d ' ') bytes"
	# Identical content is stored ONCE (craft §11), the store's whole promise.
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	[ "$(find "$TDIR/blobs" -type f | wc -l | tr -d ' ')" = 2 ] &&
		pass "the same call captured twice stores two blobs, not four" ||
		fail "re-capturing stored $(find "$TDIR/blobs" -type f | wc -l) blobs, expected 2"
else
	echo "  skip  node is not on PATH — the capture legs need the payload reader"
fi

# ---------------------------------------------------------------------------
banner "19. The adapter keeps no blob store of its own: it asks the shared script's"
# ---------------------------------------------------------------------------
# A tool call has two payloads and one event, and `emit` carries one blob — so
# the first cut of this hook landed both payloads itself, a second writer of a
# content-addressed store with its own staging, mode and hashing, and the review
# of PR #295 found three defects in exactly that duplication. Ticket #306 gave
# the shared script a `blob` subcommand (store, print `<hash> <bytes>`, write no
# event), and the hook now calls it. Two halves, both asserted: the hook's names
# are what `blob` prints for the same bytes, and nothing under the adapter still
# hashes a payload or names the store's layout.
if [ "$HAVE_NODE" = 1 ]; then
	new_trace
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	T19=$(ev_of tool.use | sed -n '1p')
	OWN=$(mktemp -d "$SCRATCH/trace-own.XXXXXX") || exit 2
	printf '%s' "$TIN" >"$SCRATCH/tool-input-252"
	OWNSAYS=$(env TRACE_DIR="$OWN" TRACE_CONFIG="$KIT/scripts/trace.config.sh" \
		sh "$TRACE" blob "$SCRATCH/tool-input-252" 2>/dev/null)
	[ -n "$OWNSAYS" ] && [ "${OWNSAYS%% *}" = "$(str "$T19" input_blob)" ] &&
		pass "the hook's input_blob is the name \`trace.sh blob\` prints for the same bytes: ${OWNSAYS%% *}" ||
		fail "the two disagree — the hook recorded '$(str "$T19" input_blob)', trace.sh blob printed '$OWNSAYS'"
	OWNREL=$(find "$OWN/blobs" -type f 2>/dev/null | sed -n '1p')
	OWNREL=${OWNREL#"$OWN"/}
	HOOKREL=$(blob_file "$(str "$T19" input_blob)")
	HOOKREL=${HOOKREL#"$TDIR"/}
	[ -n "$OWNREL" ] && [ "$OWNREL" = "$HOOKREL" ] &&
		pass "and it sits at the same path under both trace directories: $OWNREL" ||
		fail "the hook's blob is at '$HOOKREL', trace.sh stored it at '$OWNREL'"
else
	echo "  skip  node is not on PATH — the coupling leg needs the payload reader"
fi
# The store code is GONE from the adapter, not merely unused: the old helper
# or a `blobs/` path anywhere under hooks/, or a hash in the tool hook, is a
# second writer waiting to drift again. (hook.lib.sh still hashes one thing —
# the toplevel path the pointer file is keyed by, which is hook_pointer's
# coupling and not a payload.)
STORE_CODE=$(grep -n 'blobs/\|hook_blob' "$HOOKS"/*.sh "$HOOKS"/*.mjs 2>/dev/null
	grep -n 'git.*hash-object' "$HOOKS/tool-post.sh" 2>/dev/null)
[ -z "$STORE_CODE" ] &&
	pass "no file under the adapter's hooks lands a payload, names the store's layout, or hashes a tool payload" ||
	fail "the adapter still carries blob store code: $STORE_CODE"

# ---------------------------------------------------------------------------
banner "20. A tool that failed says so, and its error is the result"
# ---------------------------------------------------------------------------
# PostToolUseFailure is a different event with a different payload: there is no
# `tool_response` on it at all, and the result is the `error` the agent harness
# recorded. One script serves both events, because the only difference is the
# outcome and which key the result came from.
if [ "$HAVE_NODE" = 1 ]; then
	new_trace
	PAYLOAD="$FIX/tool-post-failure.payload.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	[ "$S_STATUS" = 0 ] && pass "the hook exits 0 on a failure payload" ||
		fail "the hook exited $S_STATUS: $S_ERR"
	[ "$(events | wc -l | tr -d ' ')" = 1 ] && pass "and appends exactly one event" ||
		fail "expected one event, got $(events | wc -l)"
	FT=$(ev_of tool.use | sed -n '1p')
	[ "$(str "$FT" outcome)" = fail ] && pass "whose outcome is fail" ||
		fail "outcome is '$(str "$FT" outcome)': $FT"
	[ "$(str "$FT" tool_use_id)" = "$TUSE_FAIL" ] && pass "and whose id is the failed call's" ||
		fail "data.tool_use_id is '$(str "$FT" tool_use_id)'"
	EH=$(hash_of "$TERR")
	[ "$(str "$FT" result_blob)" = "$EH" ] &&
		pass "the result blob is the error the agent harness recorded" ||
		fail "data.result_blob is '$(str "$FT" result_blob)', git says $EH for the error"
	[ "$(cat "$(blob_file "$EH")" 2>/dev/null)" = "$TERR" ] &&
		pass "and it holds the error's bytes, newline escape and all" ||
		fail "the result blob does not hold the error text"
	PAYLOAD="$FIX/tool-post.payload.json"
else
	echo "  skip  node is not on PATH — the failure leg needs the payload reader"
fi

# ---------------------------------------------------------------------------
banner "21. A payload far over the line cap still produces an event"
# ---------------------------------------------------------------------------
# The cap is craft §11's single write made checkable: scripts/trace.sh REFUSES
# an event over 4000 bytes rather than splitting it across two writes. A tool
# input is unbounded — a heredoc, a 40 KB patch — so a hook that put it on the
# line would lose the whole event for the calls that matter most. The blob is
# the answer, and this is the leg that proves the line stays short while
# nothing is lost.
if [ "$HAVE_NODE" = 1 ]; then
	new_trace
	BIG=$(awk 'BEGIN { while (i++ < 20000) printf "x" }')
	printf '{"session_id":"%s","cwd":"/tmp/spike-proj","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"echo %s"},"tool_response":{"stdout":"%s"},"tool_use_id":"%s"}' \
		"$TSESSION" "$BIG" "$BIG" "$TUSE" >"$SCRATCH/tool-big-252.json"
	PAYLOAD="$SCRATCH/tool-big-252.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post.payload.json"
	[ "$S_STATUS" = 0 ] && pass "a 20 KB tool input exits 0" || fail "the hook exited $S_STATUS: $S_ERR"
	B=$(ev_of tool.use | sed -n '1p')
	[ -n "$B" ] && pass "and still produces a tool.use event" ||
		fail "the oversized payload produced no event: $(events)"
	BL=$(printf '%s\n' "$B" | wc -c | tr -d ' ')
	[ -n "$B" ] && [ "$BL" -le 4000 ] && pass "whose whole write is $BL bytes, inside the 4000-byte cap" ||
		fail "the event's write is $BL bytes and the cap is 4000 — it lives on the line, not in the blob"
	BH=$(str "$B" input_blob)
	BB=$(wc -c <"$(blob_file "$BH")" 2>/dev/null | tr -d ' ')
	[ -n "$BB" ] && [ "$BB" -gt 20000 ] &&
		pass "while the blob holds all $BB bytes of it" ||
		fail "the input blob does not hold the 20 KB input (size '$BB')"
	[ "$(str "$B" result_bytes)" -gt 20000 ] 2>/dev/null &&
		pass "and data.result_bytes says how big the result was without opening it" ||
		fail "data.result_bytes is '$(str "$B" result_bytes)'"
else
	echo "  skip  node is not on PATH — the cap leg needs the payload reader"
fi

# ---------------------------------------------------------------------------
banner "22. A payload is data, never a subject the trace cannot match"
# ---------------------------------------------------------------------------
# hook.lib.sh's hook_id_ok, applied to the two ids a tool event joins on. A
# value with a space, a quote or a semicolon in it is one `show` could never
# find and, on the session-start path, one the agent harness would source as
# shell — so the class is the same narrow one everywhere in this adapter. The
# refusal is ONE event with outcome=fail and exit 0, never a silent drop: a
# capture that stopped without saying so is a hole nobody can count.
if [ "$HAVE_NODE" = 1 ]; then
	new_trace
	printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"echo hi"},"tool_response":{"stdout":"hi"},"tool_use_id":"toolu_1; rm -rf /"}' \
		"$TSESSION" >"$SCRATCH/tool-evil-id-252.json"
	PAYLOAD="$SCRATCH/tool-evil-id-252.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post.payload.json"
	[ "$S_STATUS" = 0 ] && pass "a hostile tool_use_id still exits 0" ||
		fail "the hook exited $S_STATUS: $S_ERR"
	[ "$(ev_of tool.use | wc -l | tr -d ' ')" = 1 ] &&
		pass "and leaves exactly one tool.use event" ||
		fail "expected one event, got $(ev_of tool.use | wc -l): $(events)"
	V=$(ev_of tool.use | sed -n '1p')
	[ "$(str "$V" outcome)" = fail ] && pass "whose outcome is fail" ||
		fail "the event's outcome is '$(str "$V" outcome)': $V"
	[ -z "$(str "$V" tool_use_id)" ] && pass "and which does not record the id it refused" ||
		fail "the refused id reached the event: $V"
	[ -z "$(find "$TDIR/blobs" -type f 2>/dev/null)" ] &&
		pass "and stored no blob for a call it cannot name" ||
		fail "blobs were stored for a refused call: $(find "$TDIR/blobs" -type f)"

	# THE COMPACT-PAYLOAD HAZARD, made a case. A tool payload arrives on ONE
	# line, so a text reader anchored on a key name finds the LAST occurrence
	# of it — and a tool result can quote anything, including this very trace's
	# own field names. A result that names another session must not re-file the
	# event under it.
	new_trace
	printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"cat payload.json"},"tool_response":{"stdout":"{\\"session_id\\":\\"ffffffff-0000-0000-0000-000000000000\\"}"},"tool_use_id":"%s"}' \
		"$TSESSION" "$TUSE" >"$SCRATCH/tool-quoting-252.json"
	PAYLOAD="$SCRATCH/tool-quoting-252.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post.payload.json"
	Q=$(ev_of tool.use | sed -n '1p')
	[ "$(str "$Q" session)" = "$TSESSION" ] &&
		pass "a result that quotes another session_id does not re-file the event" ||
		fail "the event was filed under '$(str "$Q" session)' — the payload's own text answered"
else
	echo "  skip  node is not on PATH — the refusal legs need the payload reader"
fi

# ---------------------------------------------------------------------------
banner "23. No node: a recorded reason, never a silent gap"
# ---------------------------------------------------------------------------
# The kit's core is sh and git only, and a tool payload needs a real parser for
# the reason transcript-usage.mjs gives: a tool result can contain the literal
# text of any key this hook reads. So the capture has a runtime, and a machine
# without it gets the same shape the usage path gets — one event, outcome=fail,
# naming node.
if env PATH="$NONODE" sh -c 'command -v node >/dev/null 2>&1'; then
	echo "  skip  the scrubbed PATH still finds node — the leg would prove nothing"
else
	new_trace
	tool_post PATH="$NONODE" TRACE_DIR="$TDIR" TRACE_TOOLS=1
	[ "$S_STATUS" = 0 ] && pass "the hook exits 0 with no node on PATH" ||
		fail "the hook exited $S_STATUS with no node: $S_ERR"
	NN=$(ev_of tool.use | sed -n '1p')
	[ "$(str "$NN" outcome)" = fail ] && pass "and emits tool.use with outcome=fail" ||
		fail "the event's outcome is '$(str "$NN" outcome)': $NN"
	case $NN in *node*) pass "whose reason names node" ;;
	*) fail "the reason does not name node: $NN" ;; esac
	[ -z "$(find "$TDIR/blobs" -type f 2>/dev/null)" ] &&
		pass "and stores no blob it could not read" ||
		fail "a blob was stored without the reader: $(find "$TDIR/blobs" -type f)"
fi

# ---------------------------------------------------------------------------
banner "24. Shape drift in a tool payload is a failure with a reason"
# ---------------------------------------------------------------------------
# The same contract transcript-usage.mjs keeps: exit 2 and say which key, never
# a best-effort blob of the wrong thing. A payload with neither tool_response
# nor error has no result to store, and that is drift rather than an empty
# result — an empty blob would read as "the tool returned nothing".
if [ "$HAVE_NODE" = 1 ]; then
	printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"echo hi"},"tool_use_id":"%s"}' \
		"$TSESSION" "$TUSE" >"$SCRATCH/tool-drift-252.json"
	mkdir -p "$SCRATCH/tool-drift-dir-252"
	t_run_split sh -c 'node "$1" "$2" <"$3"' probe "$HOOKS/tool-payload.mjs" "$SCRATCH/tool-drift-dir-252" "$SCRATCH/tool-drift-252.json"
	[ "$S_STATUS" = 2 ] && pass "the reader exits 2 when a payload carries no result at all" ||
		fail "the reader exited $S_STATUS on a payload with no result (stdout: $S_OUT)"
	case $S_ERR in *tool_response*) pass "and names the key on stderr" ;;
	*) fail "stderr does not name the key: $S_ERR" ;; esac

	new_trace
	PAYLOAD="$SCRATCH/tool-drift-252.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post.payload.json"
	[ "$S_STATUS" = 0 ] && pass "the hook still exits 0 — a trace failure is never a session failure" ||
		fail "the hook exited $S_STATUS on a drifted payload"
	D=$(ev_of tool.use | sed -n '1p')
	[ "$(str "$D" outcome)" = fail ] && pass "and records tool.use outcome=fail" ||
		fail "the event's outcome is '$(str "$D" outcome)': $D"
	case $D in *tool_response*) pass "whose reason names the key that was missing" ;;
	*) fail "the reason does not name the key: $D" ;; esac

	# A CONTROL CHARACTER IN THE HEAD would make scripts/trace.sh refuse the
	# whole event (a value may carry no control character but a tab), which
	# would turn a captured call into no line at all. JSON's own escaping keeps
	# every character below 0x20 out of the text, but DEL is not escaped by it
	# and a shell command can carry one — so the head is scrubbed, and this is
	# the case that says so.
	new_trace
	printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"printf a\177b"},"tool_response":{"stdout":"ok"},"tool_use_id":"%s"}' \
		"$TSESSION" "$TUSE" >"$SCRATCH/tool-del-252.json"
	PAYLOAD="$SCRATCH/tool-del-252.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post.payload.json"
	C=$(ev_of tool.use | sed -n '1p')
	[ -n "$C" ] && [ "$(str "$C" outcome)" = ok ] &&
		pass "a DEL byte in the input still produces the event" ||
		fail "a control character in the input cost the whole event: $(events)"
	if [ -z "$C" ]; then
		fail "there is no event to look for a control character in"
	elif printf '%s' "$C" | LC_ALL=C grep -q '[[:cntrl:]]'; then
		fail "the event line carries a control character, which no reader can parse back"
	else
		pass "and the line carries no control character — the head was scrubbed, the blob kept the bytes"
	fi
	CH=$(str "$C" input_blob)
	LC_ALL=C grep -q "$(printf 'a\177b')" "$(blob_file "$CH")" 2>/dev/null &&
		pass "the blob holds the byte the head could not" ||
		fail "the input blob lost the DEL byte"
else
	echo "  skip  node is not on PATH — the drift legs need the payload reader"
fi

# ---------------------------------------------------------------------------
banner "25. What the independent review of PR #295 found"
# ---------------------------------------------------------------------------
# Four probes an author does not think to run, each one now a regression. They
# are gathered in one section because they share a cause: a second writer of the
# blob store has to keep every promise the first one keeps, and three of these
# are places where it did not.
if [ "$HAVE_NODE" = 1 ]; then
	# H-1. A BLOB IS PRIVATE DATA. The shared script stages through `mktemp`,
	# which is 0600, and the rename preserves it; a payload written with a
	# plain create is 0644 under the usual umask, so every local user who can
	# traverse the trace directory reads every command and every file this
	# session touched. The umask is pinned here rather than inherited: the
	# claim is about the mode the writer asks for, not about the machine the
	# suite happens to run on.
	new_trace
	t_run_split env TRACE_DIR="$TDIR" TRACE_TOOLS=1 \
		sh -c 'umask 022; exec sh "$1"' probe "$HOOKS/tool-post.sh" <"$PAYLOAD"
	[ "$S_STATUS" = 0 ] && pass "the hook exits 0 under a 022 umask" || fail "the hook exited $S_STATUS"
	P25=$(ev_of tool.use | sed -n '1p')
	IH=$(hash_of "$TIN")
	MODE=$(ls -l "$(blob_file "$IH")" 2>/dev/null | cut -c1-10)
	[ "$MODE" = '-rw-------' ] &&
		pass "a stored blob is readable by its owner alone ($MODE)" ||
		fail "a stored blob's mode is '$MODE', so a tool result is world-readable"
	[ -n "$P25" ] && pass "and the event is there beside it" || fail "no event: $(events)"

	# M-1. AN ID CAN BE THE THING THAT BREAKS THE CAP. The class check says
	# nothing about length, and `scripts/trace.sh` refuses an event over 4000
	# bytes — so a 5000-character id that is otherwise perfectly well formed
	# stored two blobs and produced NO line at all, which is the one outcome
	# this hook promises never to have.
	new_trace
	LONGID=$(awk 'BEGIN { while (i++ < 5000) printf "a" }')
	printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"echo hi"},"tool_response":{"stdout":"hi"},"tool_use_id":"%s"}' \
		"$TSESSION" "$LONGID" >"$SCRATCH/tool-longid-252.json"
	PAYLOAD="$SCRATCH/tool-longid-252.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post.payload.json"
	[ "$S_STATUS" = 0 ] && pass "a 5000-character tool_use_id exits 0" || fail "the hook exited $S_STATUS"
	[ "$(ev_of tool.use | wc -l | tr -d ' ')" = 1 ] &&
		pass "and leaves exactly one tool.use event rather than none" ||
		fail "expected one event, got $(ev_of tool.use | wc -l) — an id over the cap lost the line"
	L25=$(ev_of tool.use | sed -n '1p')
	[ "$(str "$L25" outcome)" = fail ] && pass "whose outcome is fail" ||
		fail "the event's outcome is '$(str "$L25" outcome)'"
	[ "$(printf '%s\n' "$L25" | wc -c | tr -d ' ')" -le 4000 ] &&
		pass "and whose own write is inside the cap" ||
		fail "the refusal event is itself over the cap"
	[ -z "$(find "$TDIR/blobs" -type f 2>/dev/null)" ] &&
		pass "and no blob was stored for a call that cannot be named" ||
		fail "blobs were stored for an over-long id: $(find "$TDIR/blobs" -type f)"

	# M-2. THE NAME MUST NOT DEPEND ON WHERE THE HOOK WAS STANDING. `git
	# hash-object` answers in the object format of the repository it runs in,
	# and the agent harness chooses the cwd — so a hook that hashed there would
	# name a payload sha256 while the shared script, which runs from the
	# adapter's own repository, names it sha1. Two names for one payload in one
	# store is the store's whole promise broken.
	new_trace
	S256=$(mktemp -d "$SCRATCH/sha256.XXXXXX") || exit 2
	if git init -q --object-format=sha256 "$S256" 2>/dev/null; then
		t_run_split env TRACE_DIR="$TDIR" TRACE_TOOLS=1 \
			sh -c 'cd "$1" || exit 1; exec sh "$2"' probe "$S256" "$HOOKS/tool-post.sh" <"$PAYLOAD"
		[ "$S_STATUS" = 0 ] && pass "the hook exits 0 when it is run from another repository" ||
			fail "the hook exited $S_STATUS from a foreign cwd: $S_ERR"
		G=$(ev_of tool.use | sed -n '1p')
		[ "$(str "$G" input_blob)" = "$(hash_of "$TIN")" ] &&
			pass "and names the blob what the shared script names it, not what the cwd's object format would" ||
			fail "data.input_blob is '$(str "$G" input_blob)' from a sha256 cwd, expected $(hash_of "$TIN")"
	else
		echo "  skip  this git cannot create a sha256 repository — the object-format leg needs one"
	fi

	# M-3. A BLOB IS PUBLISHED BY RENAME OR NOT AT ALL. Staging outside the
	# trace directory would make the landing a copy across filesystems, which
	# can expose half a payload at the address its whole content will have. So
	# when the trace's own scratch cannot be made, the answer is the recorded
	# failure, never a staging area somewhere else — the hook's, and since
	# ticket #306 the shared script's `blob` too, which stages under the same
	# tmp/ and so refuses the same way. `tmp` is made a FILE here,
	# which is the cheapest way to fail one mkdir while leaving the event file
	# writable.
	new_trace
	: >"$TDIR/tmp"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	[ "$S_STATUS" = 0 ] && pass "a trace directory that cannot stage exits 0" ||
		fail "the hook exited $S_STATUS"
	S25=$(ev_of tool.use | sed -n '1p')
	[ "$(str "$S25" outcome)" = fail ] &&
		pass "and records one tool.use outcome=fail instead of staging elsewhere" ||
		fail "the event's outcome is '$(str "$S25" outcome)': $(events)"
	[ -z "$(find "$TDIR/blobs" -type f 2>/dev/null)" ] &&
		pass "with no blob landed from outside the trace's own filesystem" ||
		fail "a blob was landed from foreign scratch: $(find "$TDIR/blobs" -type f)"
	rm -f "$TDIR/tmp"
else
	echo "  skip  node is not on PATH — the review's regression legs need the payload reader"
fi

t_done "trace hooks"
