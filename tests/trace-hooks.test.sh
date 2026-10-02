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
			# Two scripts on PreToolUse: the kill guard (#414) and the
			# pending marker a denied call leaves behind (#409).
			PreToolUse) case $_w_cmd in *"/hooks/tool-pre.sh"*) _w_want=tool-pre.sh ;; *) _w_want=tool-pre-guard.sh ;; esac ;;
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
		for ev in SessionStart SessionEnd SubagentStop PreToolUse PostToolUse PostToolUseFailure; do
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
		for ev in SessionStart SessionEnd SubagentStop PreToolUse PostToolUse PostToolUseFailure; do
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
	# Six events, seven commands, six scripts: one script serves both
	# post-tool events, because the only difference between them is the
	# outcome it records; PreToolUse runs two — the kill guard (#414) and the
	# pending marker a denied call leaves behind (#409).
	[ "$(printf '%s\n' "$scripts" | grep -c .)" = 7 ] &&
		pass "it names a hook script per wired command, seven in all" ||
		fail "it names $(printf '%s\n' "$scripts" | grep -c .) hook script(s), expected 7"
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
	"$MODEL 34 287 10793 37519 2 msg_011CfLYV2YMEW5if4Ghh8U3S") pass "while the real model's numbers are untouched, and the placeholder is never the last message read" ;;
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
# `-e` twice rather than a BRE `\|`, which is a GNU extension: a grep without
# it would match nothing, and nothing is this check's PASS. For the same reason
# the files it reads must exist before an empty answer means anything.
[ -f "$HOOKS/tool-post.sh" ] && [ -f "$HOOKS/hook.lib.sh" ] && [ -f "$HOOKS/tool-payload.mjs" ] ||
	fail "the store-code check cannot read the adapter's hooks under $HOOKS"
STORE_CODE=$(grep -n -e 'blobs/' -e 'hook_blob' "$HOOKS"/*.sh "$HOOKS"/*.mjs
	grep -n 'git.*hash-object' "$HOOKS/tool-post.sh")
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
	# failure, never a staging area somewhere else. `tmp` is made a FILE here,
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

	# A STORE THAT REFUSES IS ONE fail EVENT (review of PR #317). Since #306 the
	# hook stages fine and it is the shared script's `blob` that is refused, which
	# answers with nothing on stdout — so `blobs` is made a FILE here, the
	# cheapest way to fail the store's own mkdir while leaving tmp/ and the
	# event file writable.
	new_trace
	: >"$TDIR/blobs"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	[ "$S_STATUS" = 0 ] && pass "a blob store that refuses the bytes exits 0" ||
		fail "the hook exited $S_STATUS"
	[ "$(ev_of tool.use | wc -l | tr -d ' ')" = 1 ] &&
		[ "$(str "$(ev_of tool.use | sed -n '1p')" outcome)" = fail ] &&
		pass "and records exactly one tool.use outcome=fail rather than an event naming blobs nobody can open" ||
		fail "expected one fail event, got: $(events)"
	[ -z "$(find "$TDIR/tmp" -mindepth 1 2>/dev/null)" ] &&
		pass "and sweeps its scratch and the shared script's" ||
		fail "scratch survives under $TDIR/tmp: $(find "$TDIR/tmp" -mindepth 1)"
	rm -f "$TDIR/blobs"
else
	echo "  skip  node is not on PATH — the review's regression legs need the payload reader"
fi

# ---------------------------------------------------------------------------
banner "26. A resumed session's usage is counted once, however many ends it had"
# ---------------------------------------------------------------------------
# Ticket #307. `claude -p --resume <id>` keeps the session id and APPENDS to the
# one transcript, and SessionEnd fires at the end of every run — so a hook that
# re-reads the whole file at each end records the first run's tokens twice, and
# `summary` totals them twice (tests/fixtures/claude-code/README.md, "The third
# capture"). The fixture is that session as the second end found it; its first
# 25 lines are the file as the first end found it. The oracle is the rollup the
# agent harness wrote at each end — line 25, then line 34, which is cumulative.
RFIX="$FIX/resumed-transcript.redacted.jsonl"
RSESSION=8b4bc828-f171-457e-9b1c-36fbc3814818
RMODEL=claude-haiku-4-5-20251001
RMSG1=msg_011CfZUaaukeMZhpc1dwr6cP
RMSG2=msg_011CfZUbi2QmUtjefTNH55Qb

# rrollup <line> <key> — one number from the resumed fixture's cost-state line.
rrollup() {
	sed -n "$1p" "$RFIX" | sed -n 's/.*"'"$RMODEL"'":{\([^}]*\)}.*/\1/p' |
		sed -n 's/.*"'"$2"'":\([0-9]*\).*/\1/p'
}

# model_row <model> — the four token columns of that model's `summary --by
# model` row, space-separated, or nothing.
model_row() {
	env TRACE_DIR="$TDIR" TRACE_QUIET=1 sh "$TRACE" summary --by model 2>/dev/null |
		awk -v m="$1" '$1 == m { print $3, $4, $5, $6 }'
}

# data_of <line> <key> — a data-map value, or empty.
data_of() { printf '%s\n' "$1" | sed -n 's/.*,"data":{.*"'"$2"'":"\([^"]*\)".*/\1/p'; }

R25="$(rrollup 25 inputTokens) $(rrollup 25 outputTokens) $(rrollup 25 cacheCreationInputTokens) $(rrollup 25 cacheReadInputTokens)"
R34="$(rrollup 34 inputTokens) $(rrollup 34 outputTokens) $(rrollup 34 cacheCreationInputTokens) $(rrollup 34 cacheReadInputTokens)"
[ "$R25" = "10 41 10151 13796" ] && [ "$R34" = "20 72 10239 37743" ] &&
	pass "the fixture's two rollups are the ones its README records" ||
	fail "the fixture's rollups moved: line 25 '$R25', line 34 '$R34'"

if [ "$HAVE_NODE" = 1 ]; then
	# THE EXTRACTOR, ASKED FOR WHAT IS NEW. Given the last message id a previous
	# read counted, it counts only what came after, and says where it stopped.
	t_run_split node "$EXTRACTOR" --after "$RMSG1" "$RFIX"
	[ "$S_STATUS" = 0 ] && pass "the extractor takes --after <message id>" ||
		fail "the extractor exited $S_STATUS with --after: $S_ERR"
	[ "$S_OUT" = "$RMODEL 10 31 88 23947 1 $RMSG2" ] &&
		pass "and counts only the resume's one response: line 34's rollup less line 25's" ||
		fail "--after $RMSG1 printed '$S_OUT'"
	t_run_split node "$EXTRACTOR" "$RFIX"
	[ "$S_OUT" = "$RMODEL 20 72 10239 37743 2 $RMSG2" ] &&
		pass "without it, the whole file: two messages, the last one named" ||
		fail "the whole-file read printed '$S_OUT'"
	t_run_split node "$EXTRACTOR" --after "$RMSG2" "$RFIX"
	[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
		pass "an anchor on the last message is nothing new: exit 0, no row" ||
		fail "--after the last message: status $S_STATUS, stdout '$S_OUT'"
	# An anchor the file does not hold means the file is not the append-only
	# transcript the anchor was read from. Counting "everything" would be the
	# double count again, and counting nothing would hide spend — so it is drift.
	t_run_split node "$EXTRACTOR" --after msg_nowhere "$RFIX"
	[ "$S_STATUS" = 2 ] && pass "an anchor the transcript does not hold is exit 2" ||
		fail "an unknown anchor exited $S_STATUS (stdout: $S_OUT)"
	case $S_ERR in *msg_nowhere*) pass "and names the anchor it could not find" ;;
	*) fail "stderr does not name the anchor: $S_ERR" ;; esac
	[ -z "$S_OUT" ] && pass "and prints no numbers" || fail "printed numbers anyway: $S_OUT"
	sed 's/"output_tokens":/"output_tokenz":/g' "$RFIX" >"$SCRATCH/resumed-drift-307.jsonl"
	t_run_split node "$EXTRACTOR" --after "$RMSG1" "$SCRATCH/resumed-drift-307.jsonl"
	[ "$S_STATUS" = 2 ] && pass "shape drift is still exit 2 with --after, even before the anchor" ||
		fail "drift with --after exited $S_STATUS"

	# TWO ENDS OF ONE SESSION, through the hook and the shared script's summary.
	new_trace
	head -25 "$RFIX" >"$SCRATCH/resumed-307.jsonl"
	set_key transcript_path "$SCRATCH/resumed-307.jsonl" <"$FIX/session-end.payload.json" |
		set_key session_id "$RSESSION" >"$SCRATCH/end-resumed-307.json"
	# Another session's usage event naming this session's last message must not
	# anchor it: the anchor is read under this session's subject only.
	env TRACE_DIR="$TDIR" TRACE_QUIET=1 sh "$TRACE" emit kind=session.usage subject=session:other-307 \
		session=other-307 model="$RMODEL" tok_in=1 data.last_msg="$RMSG1" data.msgs=1
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-resumed-307.json"
	[ "$S_STATUS" = 0 ] && pass "the first end exits 0" || fail "the first end exited $S_STATUS: $S_ERR"
	U1=$(ev_of session.usage | grep -F "\"subject\":\"session:$RSESSION\"" | sed -n '1p')
	[ "$(num "$U1" tok_in) $(num "$U1" tok_out) $(num "$U1" tok_cache_w) $(num "$U1" tok_cache_r)" = "$R25" ] &&
		pass "the first end records the first run: line 25's rollup ($R25)" ||
		fail "the first end recorded: $U1"
	[ "$(data_of "$U1" last_msg)" = "$RMSG1" ] && [ "$(data_of "$U1" msgs)" = 1 ] &&
		pass "and says how far it read: data.last_msg=$RMSG1, data.msgs=1" ||
		fail "the first usage event does not say how far it read: $U1"

	cp "$RFIX" "$SCRATCH/resumed-307.jsonl"
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-resumed-307.json"
	[ "$S_STATUS" = 0 ] && pass "the second end, after the resume, exits 0" ||
		fail "the second end exited $S_STATUS: $S_ERR"
	[ "$(ev_of session.usage | grep -F "\"subject\":\"session:$RSESSION\"" | sed -n '1p')" = "$U1" ] &&
		pass "and the first usage event is still byte for byte what it was — never rewritten" ||
		fail "the first usage event changed"
	U2=$(ev_of session.usage | grep -F "\"subject\":\"session:$RSESSION\"" | sed -n '2p')
	[ "$(data_of "$U2" last_msg)" = "$RMSG2" ] && [ "$(data_of "$U2" msgs)" = 1 ] &&
		pass "the second says it read one more message, up to $RMSG2" ||
		fail "the second usage event: $U2"
	# The other session's one token is on the same model row, so take it off.
	GOT=$(model_row "$RMODEL" | awk '{ print $1 - 1, $2, $3, $4 }')
	[ "$GOT" = "$R34" ] &&
		pass "summary --by model totals the session at line 34's rollup ($R34), not twice the first run" ||
		fail "summary --by model totals '$GOT' for the session, the rollup says '$R34'"

	# A third end with nothing new — a resume that was ended before it answered.
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-resumed-307.json"
	[ "$S_STATUS" = 0 ] && pass "a third end with nothing new exits 0" || fail "the third end exited $S_STATUS"
	GOT=$(model_row "$RMODEL" | awk '{ print $1 - 1, $2, $3, $4 }')
	[ "$GOT" = "$R34" ] && pass "and adds nothing to the total" || fail "the total moved to '$GOT'"
	U3=$(ev_of session.usage | grep -F "\"subject\":\"session:$RSESSION\"" | sed -n '3p')
	[ -n "$U3" ] && [ "$(str "$U3" outcome)" != fail ] && [ -z "$(num "$U3" tok_in)" ] &&
		[ "$(data_of "$U3" last_msg)" = "$RMSG2" ] &&
		pass "while still leaving one usage event, not a failure, that says where it stands" ||
		fail "the nothing-new end left: $U3"

	# A transcript that no longer holds the anchor is drift, recorded and exit 0.
	grep -v "$RMSG1" "$RFIX" >"$SCRATCH/resumed-307.jsonl"
	new_trace
	env TRACE_DIR="$TDIR" TRACE_QUIET=1 sh "$TRACE" emit kind=session.usage subject="session:$RSESSION" \
		session="$RSESSION" model="$RMODEL" tok_in=10 data.last_msg="$RMSG1" data.msgs=1
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-resumed-307.json"
	[ "$S_STATUS" = 0 ] && pass "a transcript that lost its anchor still exits 0" || fail "exited $S_STATUS"
	F26=$(ev_of session.usage | sed -n '2p')
	[ "$(str "$F26" outcome)" = fail ] && [ -z "$(num "$F26" tok_in)" ] &&
		pass "and records one usage event, outcome=fail, carrying no tokens" ||
		fail "the lost-anchor end left: $(ev_of session.usage)"
	case $F26 in *"$RMSG1"*) pass "whose reason names the anchor" ;; *) fail "the reason does not name the anchor: $F26" ;; esac

	# M-1, review of PR #316: an id the anchor cannot carry is drift at the
	# extractor, never a row whose anchor the next end drops in silence and so
	# falls back to the whole-file read — the double count again.
	sed "s/$RMSG1/msg:one/g; s/$RMSG2/msg:two/g" "$RFIX" >"$SCRATCH/resumed-colon-307.jsonl"
	t_run_split node "$EXTRACTOR" "$SCRATCH/resumed-colon-307.jsonl"
	[ "$S_STATUS" = 2 ] && [ -z "$S_OUT" ] &&
		pass "a message id outside letters, digits, dot, dash, underscore is exit 2 with no row" ||
		fail "an id with a colon: status $S_STATUS, stdout '$S_OUT'"
	case $S_ERR in *msg:one*) pass "and the refusal names the id" ;; *) fail "stderr does not name the id: $S_ERR" ;; esac
	new_trace
	set_key transcript_path "$SCRATCH/resumed-colon-307.jsonl" <"$SCRATCH/end-resumed-307.json" >"$SCRATCH/end-colon-307.json"
	env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-colon-307.json" >/dev/null 2>&1
	env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-colon-307.json" >/dev/null 2>&1
	[ "$(ev_of session.usage | grep -c '"outcome":"fail"')" = 2 ] && [ "$(sum_tok tok_in session.usage)" = 0 ] &&
		pass "so two ends over such ids record two failures and no tokens, not a double count" ||
		fail "two ends over unusable ids left: $(ev_of session.usage)"

	# M-2, review of PR #316: a FAIL event between two good ends is passed over —
	# the anchor is the last read that succeeded, so the third end counts the
	# resume once and the total is still the rollup.
	new_trace
	head -25 "$RFIX" >"$SCRATCH/resumed-307.jsonl"
	env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-resumed-307.json" >/dev/null 2>&1
	sed 's/"output_tokens":/"output_tokenz":/g' "$RFIX" >"$SCRATCH/resumed-307.jsonl"
	env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-resumed-307.json" >/dev/null 2>&1
	cp "$RFIX" "$SCRATCH/resumed-307.jsonl"
	env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-resumed-307.json" >/dev/null 2>&1
	[ "$(ev_of session.usage | grep -c '"outcome":"fail"')" = 1 ] &&
		pass "a drifted end between two good ones records its failure" ||
		fail "the drifted end left: $(ev_of session.usage)"
	[ "$(model_row "$RMODEL")" = "$R34" ] &&
		pass "and the end after it still totals the rollup ($R34) — the anchor skipped the failure" ||
		fail "ok, drift, ok totals '$(model_row "$RMODEL")', the rollup says '$R34'"

	# M-2: more than one model under --after. The message count is per model,
	# and so is the last id since #408 (section 39): each row names its own
	# model's last message. A third message on a second model is appended to
	# the fixture for this.
	sed -n '30,31p' "$RFIX" | sed "s/$RMSG2/msg_three307/; s/$RMODEL/claude-other-307/g" >"$SCRATCH/third-307.jsonl"
	cat "$RFIX" "$SCRATCH/third-307.jsonl" >"$SCRATCH/two-models-307.jsonl"
	t_run_split node "$EXTRACTOR" --after "$RMSG1" "$SCRATCH/two-models-307.jsonl"
	[ "$S_OUT" = "$RMODEL 10 31 88 23947 1 $RMSG2
claude-other-307 10 31 88 23947 1 msg_three307" ] &&
		pass "two models after the anchor: one row each, one message each, each its own last id" ||
		fail "two models after the anchor printed: $S_OUT"

	# A FRESH single-end session is unchanged, apart from saying how far it read.
	new_trace
	env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end.json" >/dev/null 2>&1
	F1=$(ev_of session.usage | sed -n '1p')
	[ "$(num "$F1" tok_in) $(num "$F1" tok_out) $(num "$F1" tok_cache_w) $(num "$F1" tok_cache_r)" = "34 287 10793 37519" ] &&
		pass "a fresh session's one end still records 34 / 287 / 10793 / 37519" ||
		fail "a fresh session's end recorded: $F1"
	[ "$(data_of "$F1" msgs)" = 2 ] && [ "$(data_of "$F1" last_msg)" = msg_011CfLYV2YMEW5if4Ghh8U3S ] &&
		pass "and says it read two messages, up to the last one" ||
		fail "a fresh session's end does not say how far it read: $F1"
else
	echo "  skip  node is not on PATH — the resumed-session legs need the extractor"
fi

# ---------------------------------------------------------------------------
banner "27. SubagentStop waits, within a bound, for the subagent's final message"
# ---------------------------------------------------------------------------
# The policy file's own comment on the bound is held here, beside the behaviour
# it describes (#401).
# Since PR #434 the wait may run past its bound by one poll (hook_wait_final,
# below), so the shipped policy file may not promise "never longer".
WAIT_CONFIG="$KIT/scripts/trace.config.sh"
assert_file_lacks "$WAIT_CONFIG" "and never longer" "the wait may run past the bound by one poll"
assert_file_has "$WAIT_CONFIG" "the actual wait may" "the comment admits the overrun"
assert_file_has "$WAIT_CONFIG" "one whole-second nap and a check" "and names the hook's own bound on it, a nap AND a check"

# Ticket #308. Live, SubagentStop can run BEFORE the subagent's transcript holds
# its final assistant line: two of seven stops in the ticket's own measurement
# found the file present and the last line 170 and 223 ms away. Read then, the
# hook either finds no usage at all or — worse — sums the turns that WERE there
# and records a confident undercount. So the hook waits for the transcript to
# END ON A FINAL MESSAGE (its last user-or-assistant line is an assistant line
# with a stop_reason other than tool_use or null), polling, never past the
# bound TRACE_AGENT_WAIT_MS names. Empty is no wait: today's behaviour, and
# what the shipped policy file says.
#
# TIMING WITHOUT FLAKES. Wall time is read with `date +%s`, whole seconds, and
# floor(end) - floor(start) is never less than the whole seconds that really
# passed — so "at least the bound" is asserted exactly. Nothing asserts a TIGHT
# upper limit on wall time, because a loaded machine (this section was written
# at load average 29) stretches every hook run: "no wait" is proved instead by
# a `sleep` on PATH that logs each nap it is asked for, and "stopped early" by
# the wait the event itself reports. The appearing transcript is written by a
# background writer one second in, against a ten-second bound: a machine that
# stalls long enough for the writer to finish first still yields the tokens,
# which is the claim.
#
# THE STAGES, cut from the subagent fixture at its natural seam: its first 19
# lines end on the tool_result user line, after one assistant turn that used a
# tool — exactly the live shape that yields a partial sum.
head -n 19 "$FIX/subagent-transcript.redacted.jsonl" >"$SCRATCH/sub-head-308.jsonl"
sed -n '20,$p' "$FIX/subagent-transcript.redacted.jsonl" >"$SCRATCH/sub-tail-308.jsonl"
[ -s "$SCRATCH/sub-tail-308.jsonl" ] && pass "the fixture splits before its final message" ||
	fail "the subagent fixture has no line 20 — the stage cut moved"

# THE POLICY, shipped and kit. The shipped file names the variable and leaves
# it empty — no wait, the behaviour a consumer had before this bound existed;
# the kit's twin sets its own, from the measurement.
grep -q "^TRACE_AGENT_WAIT_MS=''$" "$KIT/scripts/trace.config.sh" &&
	pass "scripts/trace.config.sh ships TRACE_AGENT_WAIT_MS empty" ||
	fail "scripts/trace.config.sh does not ship TRACE_AGENT_WAIT_MS=''"
grep -qE "^TRACE_AGENT_WAIT_MS='[1-9][0-9]{0,4}'$" "$KIT/scripts/trace.kit.config.sh" &&
	pass "scripts/trace.kit.config.sh sets a bound the hook accepts" ||
	fail "scripts/trace.kit.config.sh sets no well-formed TRACE_AGENT_WAIT_MS"

# stop_on <transcript> — the SubagentStop payload, pointed at that transcript.
stop_on() {
	set_key transcript_path "$SCRATCH/main.jsonl" <"$FIX/subagent-stop.payload.json" |
		set_key agent_transcript_path "$1" >"$SCRATCH/stop-308.json"
}

# THE STUBS. A `sleep` that logs each nap and then really sleeps; one that
# also refuses a fraction, as a POSIX-only sleep may; and a `date` with no
# sub-second field, as POSIX date has none. Each is found first on PATH and
# hands everything else to the real command.
REAL_SLEEP=$(command -v sleep)
REAL_DATE=$(command -v date)
mkdir -p "$SCRATCH/naps-308" "$SCRATCH/whole-308" "$SCRATCH/noclock-308"
printf '#!/bin/sh\necho "$1" >>"%s/naps-308.log"\nexec "%s" "$@"\n' "$SCRATCH" "$REAL_SLEEP" >"$SCRATCH/naps-308/sleep"
printf '#!/bin/sh\necho "$1" >>"%s/naps-308.log"\ncase $1 in *.*) exit 1 ;; esac\nexec "%s" "$@"\n' "$SCRATCH" "$REAL_SLEEP" >"$SCRATCH/whole-308/sleep"
printf '#!/bin/sh\ncase "$*" in *%%N*) echo "$("%s" +%%s)N" ;; *) exec "%s" "$@" ;; esac\n' "$REAL_DATE" "$REAL_DATE" >"$SCRATCH/noclock-308/date"
chmod +x "$SCRATCH/naps-308/sleep" "$SCRATCH/whole-308/sleep" "$SCRATCH/noclock-308/date"

# timed <env assignments…> — run the hook on the staged payload with the
# logging sleep first on PATH ($STUBS, default the plain logger, overrides
# it), and set ELAPSED to the whole seconds it took and NAPS to how many naps
# it asked for.
timed() {
	: >"$SCRATCH/naps-308.log"
	_t0=$(date +%s)
	t_run_split env PATH="${STUBS:-$SCRATCH/naps-308}:$PATH" "$@" sh "$HOOKS/subagent-stop.sh" <"$SCRATCH/stop-308.json"
	ELAPSED=$(($(date +%s) - _t0))
	NAPS=$(wc -l <"$SCRATCH/naps-308.log" | tr -d ' ')
}

if [ "$HAVE_NODE" = 1 ]; then
	# THE RACE, WON. The file is there, one turn short; the last turn lands once
	# the hook has taken its first nap, inside a ten-second bound. The writer is
	# driven by the nap log rather than by a clock, so a slow preamble cannot let
	# the turn land before the hook first looks — which would let a hook that
	# checks once and never polls pass this leg (review of PR #323).
	new_trace
	cp "$SCRATCH/sub-head-308.jsonl" "$SCRATCH/sub-late-308.jsonl"
	stop_on "$SCRATCH/sub-late-308.jsonl"
	: >"$SCRATCH/naps-308.log"
	(
		_w=0
		while [ ! -s "$SCRATCH/naps-308.log" ] && [ "$_w" -lt 600 ]; do
			sleep 0.05 2>/dev/null || sleep 1
			_w=$((_w + 1))
		done
		cat "$SCRATCH/sub-tail-308.jsonl" >>"$SCRATCH/sub-late-308.jsonl"
	) &
	WRITER=$!
	timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=10000
	wait "$WRITER"
	[ "$S_STATUS" = 0 ] && pass "the hook exits 0 while it waits" || fail "the hook exited $S_STATUS: $S_ERR"
	[ -z "$S_OUT" ] && pass "and says nothing on stdout" || fail "stdout carried: $S_OUT"
	W=$(ev_of agent.stop | sed -n '1p')
	for pair in tok_in=34 tok_out=156 tok_cache_w=17138 tok_cache_r=14968; do
		f=${pair%=*}
		want=${pair#*=}
		got=$(num "$W" "$f")
		[ "$got" = "$want" ] && pass "$f is $want — the final turn was waited for, not the partial sum" ||
			fail "$f is '$got', expected $want: $W"
	done
	[ -n "$(str "$W" waited_ms)" ] && pass "and data.waited_ms says how long it waited ($(str "$W" waited_ms) ms)" ||
		fail "no data.waited_ms on the event: $W"
	[ "$NAPS" -ge 1 ] && [ "$(str "$W" waited_ms)" -gt 0 ] 2>/dev/null &&
		pass "and it really polled: $NAPS nap(s) before the turn landed" ||
		fail "the hook took $NAPS naps and reported waited_ms '$(str "$W" waited_ms)' — it did not poll"
	[ "$(str "$W" waited_ms)" -lt 10000 ] 2>/dev/null &&
		pass "and it stopped waiting once the turn landed, inside the 10000 ms bound" ||
		fail "data.waited_ms is '$(str "$W" waited_ms)' — it waited out the bound instead of polling"

	# THE RACE, LOST. The final turn never lands: the absence is recorded as
	# before, with the wait it gave — after the bound, and not before.
	new_trace
	stop_on "$SCRATCH/sub-head-308.jsonl"
	timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=2000
	[ "$S_STATUS" = 0 ] && pass "a transcript that never completes still exits 0" ||
		fail "the hook exited $S_STATUS: $S_ERR"
	[ "$ELAPSED" -ge 2 ] && pass "and only after the 2000 ms bound (${ELAPSED}s)" ||
		fail "the hook gave up after ${ELAPSED}s, before its 2000 ms bound"
	[ "$NAPS" -le 41 ] && pass "and it asked for no more naps than the bound holds ($NAPS of at most 41)" ||
		fail "the hook asked for $NAPS naps against a 2000 ms bound of 50 ms naps"
	[ "$ELAPSED" -le 30 ] && pass "and not without end (${ELAPSED}s — the slack is for a loaded machine, the catch is a hang)" ||
		fail "the hook took ${ELAPSED}s against a 2000 ms bound — it blocks past the bound"
	L=$(ev_of agent.stop | sed -n '1p')
	[ "$(ev_of agent.stop | wc -l | tr -d ' ')" = 1 ] && pass "one agent.stop event, as ever" ||
		fail "expected one agent.stop, got $(ev_of agent.stop | wc -l)"
	[ "$(str "$L" outcome)" = fail ] && pass "with outcome=fail" ||
		fail "the event's outcome is '$(str "$L" outcome)': $L"
	[ -z "$(num "$L" tok_out)" ] && pass "and no partial sum of the turns that were there" ||
		fail "the event carried tokens from an unfinished transcript: $L"
	[ "$(str "$L" waited_ms)" -ge 2000 ] 2>/dev/null && pass "and data.waited_ms is the wait it gave, at least the bound ($(str "$L" waited_ms))" ||
		fail "data.waited_ms is '$(str "$L" waited_ms)': $L"

	# EMPTY IS NO WAIT — from the environment, and from a policy file. Today's
	# behaviour exactly: read what is there, now, and say nothing of a wait.
	for how in env zero file; do
		new_trace
		if [ "$how" = env ]; then
			timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=
		elif [ "$how" = zero ]; then
			timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=0
		else
			printf "TRACE_AGENT_WAIT_MS=''\n" >"$SCRATCH/policy-308.sh"
			timed TRACE_DIR="$TDIR" TRACE_CONFIG="$SCRATCH/policy-308.sh"
		fi
		E=$(ev_of agent.stop | sed -n '1p')
		[ "$S_STATUS" = 0 ] && [ "$NAPS" = 0 ] &&
			pass "an empty bound ($how) is no wait: exit 0, not one nap" ||
			fail "an empty bound ($how) napped $NAPS times, exit $S_STATUS"
		[ -n "$E" ] && [ -z "$(str "$E" waited_ms)" ] && pass "and the event claims no wait ($how)" ||
			fail "the event with an empty bound ($how): $E"
	done

	# A BOUND FROM THE POLICY FILE is the kit's own case: its twin sets one.
	new_trace
	printf "TRACE_AGENT_WAIT_MS='1000'\n" >"$SCRATCH/policy-308.sh"
	timed TRACE_DIR="$TDIR" TRACE_CONFIG="$SCRATCH/policy-308.sh"
	[ "$ELAPSED" -ge 1 ] && [ "$(str "$(ev_of agent.stop | sed -n '1p')" waited_ms)" -ge 1000 ] 2>/dev/null &&
		pass "a bound in the policy file is read and waited (${ELAPSED}s, 1000 ms)" ||
		fail "the policy file's 1000 ms bound was not waited: ${ELAPSED}s, $(events)"

	# A MALFORMED BOUND IS REFUSED, like every other policy value: named on
	# stderr, on the event, and never waited — but still exit 0, because a hook
	# never fails a session. A leading zero is refused with the rest: sh
	# arithmetic reads 0100 as octal.
	for bad in soon 1.5 -5 0100 1000000; do
		new_trace
		timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS="$bad"
		B=$(ev_of agent.stop | sed -n '1p')
		[ "$S_STATUS" = 0 ] && [ "$NAPS" = 0 ] &&
			pass "TRACE_AGENT_WAIT_MS='$bad' exits 0 without a nap" ||
			fail "TRACE_AGENT_WAIT_MS='$bad' napped $NAPS times, exit $S_STATUS"
		case $S_ERR in *TRACE_AGENT_WAIT_MS*"$bad"*) pass "and is refused on stderr, naming the value" ;;
		*) fail "no refusal on stderr for '$bad': $S_ERR" ;; esac
		[ "$(str "$B" wait_refused)" = "$bad" ] && [ -z "$(str "$B" waited_ms)" ] &&
			pass "and on the event, which claims no wait" ||
			fail "the event for '$bad' does not carry the refusal: $B"
	done

	# NO FILE AT ALL IS NOT WAITED FOR. In every measured stop the transcript
	# already existed; in the kit's own trace every stop that named a missing
	# file named one that never appeared. Waiting for those would cost every
	# such stop the whole bound and buy nothing.
	new_trace
	stop_on "$SCRATCH/never-there-308.jsonl"
	timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=5000
	[ "$S_STATUS" = 0 ] && [ "$NAPS" = 0 ] &&
		pass "a transcript that does not exist is not waited for" ||
		fail "a missing transcript napped $NAPS times against a 5000 ms bound"
	# What it records instead — nothing — is section 29's claim (#344).

	# TRACING OFF IS NO WAIT, whatever the bound: there is nothing to write.
	stop_on "$SCRATCH/sub-head-308.jsonl"
	timed TRACE_DIR= TRACE_AGENT_WAIT_MS=5000
	[ "$S_STATUS" = 0 ] && [ "$NAPS" = 0 ] && [ -z "$S_ERR" ] &&
		pass "with tracing off a 5000 ms bound is not waited, and the hook is silent" ||
		fail "with tracing off the hook napped $NAPS times, exit $S_STATUS, stderr '$S_ERR'"

	# NO MILLISECOND CLOCK: the wait is counted instead of clocked. POSIX date
	# stops at seconds, so without %N the figure is the sum of the naps — here
	# six 50 ms naps against a 300 ms bound, exactly.
	new_trace
	stop_on "$SCRATCH/sub-head-308.jsonl"
	STUBS="$SCRATCH/noclock-308:$SCRATCH/naps-308" timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=300
	C=$(ev_of agent.stop | sed -n '1p')
	[ "$S_STATUS" = 0 ] && [ "$(str "$C" waited_ms)" = 300 ] && [ "$NAPS" = 6 ] &&
		pass "with no millisecond clock the wait is six counted 50 ms naps, reported as 300" ||
		fail "no-clock wait: exit $S_STATUS, $NAPS naps, event $C"

	# NO FRACTIONAL SLEEP: whole-second naps while a whole second remains, and
	# the wait ends short of the bound rather than past it — and never spins.
	new_trace
	STUBS="$SCRATCH/noclock-308:$SCRATCH/whole-308" timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=2500
	H=$(ev_of agent.stop | sed -n '1p')
	[ "$S_STATUS" = 0 ] && [ "$(str "$H" waited_ms)" = 2000 ] &&
		pass "a sleep that refuses fractions naps whole seconds and stops at 2000 of a 2500 ms bound" ||
		fail "whole-second wait: exit $S_STATUS, event $H"
	[ "$NAPS" = 3 ] && pass "in three asks: one refused fraction, then two whole seconds" ||
		fail "the hook asked for $NAPS naps: $(tr '\n' ' ' <"$SCRATCH/naps-308.log")"

	# FROM THE REVIEW OF PR #323 — each a regression now.
	#
	# A CLOCK THAT STEPS BACK must not stretch the wait. `date +%s%N` is the
	# realtime clock; the stub answers once with the real time and from then on
	# with the real time two seconds EARLIER, so read naively the wait is two
	# seconds longer than its bound — the review reproduced 3566 ms for a 500.
	mkdir -p "$SCRATCH/backclock-308"
	printf '#!/bin/sh\ncase "$*" in *%%N*) if [ -f "%s/back-308.seen" ]; then echo $(($("%s" +%%s%%N) - 2000000000)); else : >"%s/back-308.seen"; exec "%s" +%%s%%N; fi ;; *) exec "%s" "$@" ;; esac\n' \
		"$SCRATCH" "$REAL_DATE" "$SCRATCH" "$REAL_DATE" "$REAL_DATE" >"$SCRATCH/backclock-308/date"
	chmod +x "$SCRATCH/backclock-308/date"
	rm -f "$SCRATCH/back-308.seen"
	new_trace
	stop_on "$SCRATCH/sub-head-308.jsonl"
	STUBS="$SCRATCH/backclock-308:$SCRATCH/naps-308" timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=300
	K=$(ev_of agent.stop | sed -n '1p')
	[ "$S_STATUS" = 0 ] && [ "$NAPS" -le 7 ] && [ "$(str "$K" waited_ms)" = 300 ] &&
		pass "a clock stepping back still ends the wait at the bound ($NAPS naps, waited_ms 300)" ||
		fail "a backwards clock: exit $S_STATUS, $NAPS naps, event $K"

	# A SUB-SECOND BOUND IS NOT SERVED BY A WHOLE-SECOND SLEEP: the first
	# fraction is refused, no whole second fits in 500 ms, and the hook returns
	# without a nap — one ask, the refused one, and well under a second.
	new_trace
	stop_on "$SCRATCH/sub-head-308.jsonl"
	STUBS="$SCRATCH/whole-308" timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=500
	U=$(ev_of agent.stop | sed -n '1p')
	[ "$S_STATUS" = 0 ] && [ "$NAPS" = 1 ] && [ "$(str "$U" waited_ms)" -lt 1000 ] 2>/dev/null &&
		pass "a 500 ms bound with a whole-second sleep returns without a nap ($(str "$U" waited_ms) ms, $NAPS ask)" ||
		fail "a 500 ms bound with a whole-second sleep: exit $S_STATUS, $NAPS asks, event $U"

	# The legs below need a millisecond clock; on a host without one they would
	# pass or fail on nothing, so they say so instead.
	case $("$REAL_DATE" +%s%N) in
	*[!0-9]*) HAVE_MS_CLOCK=0 ;;
	*) HAVE_MS_CLOCK=1 ;;
	esac
	if [ "$HAVE_MS_CLOCK" = 0 ]; then
		note "no millisecond clock on this host: the real-clock whole-second legs did not run"
	else
		# A MILLISECOND CLOCK WITH A WHOLE-SECOND SLEEP waits the kit's own bound
		# out: one refused fraction, then the whole second.
		new_trace
		stop_on "$SCRATCH/sub-head-308.jsonl"
		STUBS="$SCRATCH/whole-308" timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=1000
		J=$(ev_of agent.stop | sed -n '1p')
		[ "$S_STATUS" = 0 ] && [ "$(str "$J" waited_ms)" -ge 1000 ] 2>/dev/null && [ "$NAPS" = 2 ] &&
			pass "a real clock and a whole-second sleep wait a 1000 ms bound out ($(str "$J" waited_ms) ms, $NAPS asks)" ||
			fail "a real clock and a whole-second sleep: exit $S_STATUS, $NAPS asks, event $J"

		# THE READINESS CHECK IS SPENT INSIDE THE BOUND (#403). On a loaded host
		# the first check alone cost just over 50 ms, and the hook gave up at
		# waited_ms 51 without one nap. A `tail` that costs 60 ms makes that host
		# deterministic, and one whose own fractional sleep fails says so rather
		# than quietly costing nothing.
		REAL_TAIL=$(command -v tail)
		mkdir -p "$SCRATCH/slowcheck-403"
		printf '#!/bin/sh\n"%s" 0.06 || { : >"%s/slowcheck-403.broken"; exit 1; }\nexec "%s" "$@"\n' \
			"$REAL_SLEEP" "$SCRATCH" "$REAL_TAIL" >"$SCRATCH/slowcheck-403/tail"
		chmod +x "$SCRATCH/slowcheck-403/tail"
		rm -f "$SCRATCH/slowcheck-403.broken"
		new_trace
		stop_on "$SCRATCH/sub-head-308.jsonl"
		STUBS="$SCRATCH/slowcheck-403:$SCRATCH/whole-308" timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=1000
		W=$(ev_of agent.stop | sed -n '1p')
		[ "$S_STATUS" = 0 ] && [ "$(str "$W" waited_ms)" -ge 1000 ] 2>/dev/null && [ "$NAPS" = 2 ] &&
			[ ! -e "$SCRATCH/slowcheck-403.broken" ] &&
			pass "a readiness check costing 60 ms still waits a 1000 ms bound out ($(str "$W" waited_ms) ms, $NAPS asks)" ||
			fail "a 60 ms readiness check cut the wait short: exit $S_STATUS, $NAPS asks, event $W"

		# THE OVERRUN IS BOUNDED. In whole-second mode the wait reaches the bound
		# and may pass it by at most one whole-second nap plus a check: a 2500 ms
		# bound with the same 60 ms check takes two whole seconds and no third,
		# and reports no more than 2500 + 1000 + the check's cost (60 ms and the
		# process it runs in, 200 ms in all).
		new_trace
		stop_on "$SCRATCH/sub-head-308.jsonl"
		STUBS="$SCRATCH/slowcheck-403:$SCRATCH/whole-308" timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=2500
		O=$(ev_of agent.stop | sed -n '1p')
		[ "$S_STATUS" = 0 ] && [ "$NAPS" = 3 ] && [ "$(str "$O" waited_ms)" -le 3700 ] 2>/dev/null &&
			[ ! -e "$SCRATCH/slowcheck-403.broken" ] &&
			pass "a 2500 ms bound overruns by at most one nap and a check ($(str "$O" waited_ms) ms, $NAPS asks)" ||
			fail "a 2500 ms whole-second wait overran its ceiling: exit $S_STATUS, $NAPS asks, event $O"
	fi

	# THE READINESS RULE, half by half (hook_final's comment calls each one
	# load-bearing, so each has a leg that fails without it). Built from the
	# fixture: line 11 is a user line, line 20 the final assistant line.
	sed -n '20p' "$FIX/subagent-transcript.redacted.jsonl" >"$SCRATCH/final-line-308.jsonl"
	sed -n '11p' "$FIX/subagent-transcript.redacted.jsonl" >"$SCRATCH/user-line-308.jsonl"
	# final <label> <file> <expect: final|not> — run the hook with a short bound
	# and read which way it went.
	final() {
		new_trace
		stop_on "$2"
		timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=300
		_f=$(ev_of agent.stop | sed -n '1p')
		if [ "$3" = final ]; then
			[ -n "$(num "$_f" tok_out)" ] && pass "$1 reads as final" || fail "$1 did not read as final: $_f"
		else
			[ "$(str "$_f" outcome)" = fail ] && [ -z "$(num "$_f" tok_out)" ] &&
				pass "$1 is not final" || fail "$1 read as final: $_f"
		fi
	}
	cat "$FIX/subagent-transcript.redacted.jsonl" "$SCRATCH/user-line-308.jsonl" >"$SCRATCH/resumed-308.jsonl"
	final "an old end_turn followed by the user line that resumed the subagent" "$SCRATCH/resumed-308.jsonl" not
	{ cat "$SCRATCH/sub-head-308.jsonl"; sed 's/"stop_reason":"end_turn"/"stop_reason":null/' "$SCRATCH/final-line-308.jsonl"; } >"$SCRATCH/null-308.jsonl"
	final "a last assistant line with stop_reason null (a streamed block before its last)" "$SCRATCH/null-308.jsonl" not
	{ cat "$SCRATCH/sub-head-308.jsonl"; sed 's/"stop_reason":"end_turn"/"stop_reason":"max_tokens"/' "$SCRATCH/final-line-308.jsonl"; } >"$SCRATCH/max-308.jsonl"
	final "a last assistant line that stopped on max_tokens" "$SCRATCH/max-308.jsonl" final
	sed 's/"type":"\(user\|assistant\)"/"type": "\1"/g; s/"stop_reason":"/"stop_reason": "/g' \
		"$FIX/subagent-transcript.redacted.jsonl" >"$SCRATCH/spaced-308.jsonl"
	grep -q '"type": "assistant"' "$SCRATCH/spaced-308.jsonl" &&
		final "a transcript serialised with a space after each colon" "$SCRATCH/spaced-308.jsonl" final ||
		fail "the spaced fixture was not built"

	# A MALFORMED BOUND WITH TRACING OFF says nothing: there is nothing to wait
	# for and nowhere to write, so a typo must not speak on every stop.
	stop_on "$SCRATCH/sub-head-308.jsonl"
	timed TRACE_DIR= TRACE_AGENT_WAIT_MS=soon
	[ "$S_STATUS" = 0 ] && [ -z "$S_ERR" ] && [ "$NAPS" = 0 ] &&
		pass "with tracing off a malformed bound is not refused aloud" ||
		fail "with tracing off a malformed bound: exit $S_STATUS, $NAPS naps, stderr '$S_ERR'"
else
	echo "  skip  node is not on PATH — the wait legs read tokens with the extractor"
fi

# ---------------------------------------------------------------------------
banner "28. The field reader on a compact payload, the shape a live hook gets"
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
# The two READMEs beside the hooks tell the same story as the comment: every
# live payload is compact, and the session fixtures are pretty only because
# the redaction reformatted them (review of PR #315, M-2).
for doc in "$FIX/README.md" "$KIT/adapters/claude-code/README.md"; do
	d=$(tr '\n' ' ' <"$doc" | tr -s ' ' | tr '[:upper:]' '[:lower:]')
	case $d in
	*"unlike the pretty-printed session payloads"*)
		fail "${doc#"$KIT"/} still says the session payloads arrive pretty-printed — every live payload is compact" ;;
	*"every live payload arrives compact"*) pass "${doc#"$KIT"/} says every live payload arrives compact" ;;
	*) fail "${doc#"$KIT"/} does not say every live payload arrives compact" ;;
	esac
done

# ---------------------------------------------------------------------------
banner "29. One message id, two usage blocks: the last one is the message's usage"
# ---------------------------------------------------------------------------
# Ticket #343, retro 20261001T093317Z finding F5c. A response that opens with a
# thinking block is written as a line carrying a PARTIAL usage snapshot, then
# as the tool-use or text line carrying the final one — same message.id, same
# requestId, a different output_tokens. The byte-identical-usage decision did
# not hold, and the drift refusal turned 60 real subagent stops into `fail`.
# The fixture pair is one real captured session (2.1.285) with one subagent;
# its cost-state line is the oracle, exactly as section 5's is: the session's
# usage plus the subagent's must equal it, and that holds only if the LAST
# block per id is the one counted (the first gives tok_out 307, not 419).
TFIX="$FIX/thinking-transcript.redacted.jsonl"
TSUB="$FIX/thinking-subagent-transcript.redacted.jsonl"
TMODEL=claude-haiku-4-5-20251001
TSESSION343=bb589627-2e22-472c-a3fc-92fa18e27ce4
TAGENT343=acfe6f1fbadd45fac
# The premise, checked rather than assumed: one id, two different tok_out.
tdup=$(grep -o '"id":"msg_011CfZXyUJMx7CpnvxyFG4X1"' "$TSUB" | wc -l | tr -d ' ')
[ "$tdup" = 2 ] && grep -q '"output_tokens":1,' "$TSUB" && grep -q '"output_tokens":113,' "$TSUB" &&
	pass "premise: the subagent fixture carries one id twice, output_tokens 1 then 113" ||
	fail "premise: the fixture no longer carries the two-block id"
# trollup <key> — one number from the thinking fixture's cost-state line.
trollup() {
	sed -n '$p' "$TFIX" | sed -n 's/.*"'"$TMODEL"'":{\([^}]*\)}.*/\1/p' |
		sed -n 's/.*"'"$1"'":\([0-9]*\).*/\1/p'
}
if [ "$HAVE_NODE" = 1 ]; then
	t_run_split node "$EXTRACTOR" "$TSUB"
	[ "$S_STATUS" = 0 ] && pass "the extractor reads the two-block transcript (exit 0)" ||
		fail "the extractor exited $S_STATUS on the two-block transcript: $S_ERR"
	[ "$S_OUT" = "$TMODEL 18 158 15600 13892 2 msg_011CfZXycwXfJKUZUXVPyGsv" ] &&
		pass "one row: the last block per id, two messages, nothing from the superseded block" ||
		fail "the row is '$S_OUT'"

	# The demo: the subagent-stop hook over the fixture.
	new_trace
	set_key transcript_path "$SCRATCH/thinking-main-343.jsonl" <"$FIX/subagent-stop.payload.json" |
		set_key agent_transcript_path "$SCRATCH/thinking-sub-343.jsonl" |
		set_key session_id "$TSESSION343" | set_key agent_id "$TAGENT343" >"$SCRATCH/thinking-stop-343.json"
	cp "$TFIX" "$SCRATCH/thinking-main-343.jsonl"
	cp "$TSUB" "$SCRATCH/thinking-sub-343.jsonl"
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/subagent-stop.sh" <"$SCRATCH/thinking-stop-343.json"
	[ "$S_STATUS" = 0 ] && pass "the subagent-stop hook exits 0" || fail "the hook exited $S_STATUS: $S_ERR"
	[ "$(ev_of agent.stop | wc -l | tr -d ' ')" = 1 ] && pass "exactly one agent.stop event" ||
		fail "expected one agent.stop, got: $(ev_of agent.stop)"
	A=$(ev_of agent.stop | sed -n '1p')
	[ "$(str "$A" outcome)" != fail ] && [ -n "$(num "$A" tok_out)" ] &&
		pass "it carries tokens, not a fail" || fail "the agent.stop is: $A"
	[ "$(str "$A" model)" = "$TMODEL" ] && pass "and names $TMODEL" || fail "model is '$(str "$A" model)'"

	# The oracle: session.usage + agent.stop = the rollup, all four counts.
	set_key transcript_path "$SCRATCH/thinking-main-343.jsonl" <"$FIX/session-end.payload.json" |
		set_key session_id "$TSESSION343" >"$SCRATCH/thinking-end-343.json"
	env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/thinking-end-343.json" >/dev/null 2>&1
	for pair in tok_in:inputTokens tok_out:outputTokens \
		tok_cache_w:cacheCreationInputTokens tok_cache_r:cacheReadInputTokens; do
		f=${pair%:*}
		key=${pair#*:}
		want=$(trollup "$key")
		got=$(($(sum_tok "$f" session.usage) + $(sum_tok "$f" agent.stop)))
		[ -n "$want" ] && [ "$got" = "$want" ] &&
			pass "$f: session.usage + agent.stop = $want, the rollup's $key" ||
			fail "$f: the trace totals $got, the rollup says '$want'"
	done

	# The superseded block is still READ: shape drift on it is still drift.
	sed '12s/"output_tokens":/"output_tokenz":/' "$TSUB" >"$SCRATCH/thinking-drift-343.jsonl"
	t_run_split node "$EXTRACTOR" "$SCRATCH/thinking-drift-343.jsonl"
	[ "$S_STATUS" = 2 ] && case $S_ERR in *output_tokens*) true ;; *) false ;; esac &&
		pass "a renamed usage key on the superseded line still exits 2, naming the key" ||
		fail "a renamed key on the superseded line: exit $S_STATUS, '$S_ERR'"
	sed '13s/"model":"[^"]*"/"model":"claude-other-1"/' "$TSUB" >"$SCRATCH/thinking-model-343.jsonl"
	t_run_split node "$EXTRACTOR" "$SCRATCH/thinking-model-343.jsonl"
	[ "$S_STATUS" = 2 ] && case $S_ERR in *"different model"*) true ;; *) false ;; esac &&
		pass "the same id under a different model is still drift, and says so" ||
		fail "a changed model under one id: exit $S_STATUS, '$S_ERR'"
	sed '13s/"requestId":"[^"]*"/"requestId":"req_other"/' "$TSUB" >"$SCRATCH/thinking-req-343.jsonl"
	t_run_split node "$EXTRACTOR" "$SCRATCH/thinking-req-343.jsonl"
	[ "$S_STATUS" = 2 ] && case $S_ERR in *"different requestId"*) true ;; *) false ;; esac &&
		pass "the same id under a different requestId is still drift, and says so" ||
		fail "a changed requestId under one id: exit $S_STATUS, '$S_ERR'"
	sed '13s/"model":"[^"]*",//' "$TSUB" >"$SCRATCH/thinking-nomodel-343.jsonl"
	t_run_split node "$EXTRACTOR" "$SCRATCH/thinking-nomodel-343.jsonl"
	[ "$S_STATUS" = 2 ] && case $S_ERR in *"message.model"*) true ;; *) false ;; esac &&
		pass "a missing model on the final block is still drift, naming the key" ||
		fail "a missing model: exit $S_STATUS, '$S_ERR'"

	# THE SUPERSEDING RULE IS NARROW (review of PR #363, M-1). Only a later
	# block that GROWS output_tokens with the other three counts equal is the
	# final snapshot. The same pair written final-first would sum 46 where the
	# truth is 158 — so a shrinking output, or any change in the input or cache
	# counts, is still drift: exit 2, naming the id and the field.
	sed -n '13p' "$TSUB" >"$SCRATCH/thinking-l13-343.jsonl"
	{ sed -n '1,11p' "$TSUB"; cat "$SCRATCH/thinking-l13-343.jsonl"; sed -n '12p;14,$p' "$TSUB"; } >"$SCRATCH/thinking-swap-343.jsonl"
	t_run_split node "$EXTRACTOR" "$SCRATCH/thinking-swap-343.jsonl"
	[ "$S_STATUS" = 2 ] && case $S_ERR in *msg_011CfZXyUJMx7CpnvxyFG4X1*tok_out*) true ;; *) false ;; esac &&
		pass "the pair written final-first (output 113 then 1) is drift, naming the id and tok_out" ||
		fail "the final-first pair: exit $S_STATUS, row '$S_OUT', '$S_ERR'"
	for pair in tok_in:input_tokens tok_cache_w:cache_creation_input_tokens tok_cache_r:cache_read_input_tokens; do
		f=${pair%:*}
		key=${pair#*:}
		sed '13s/"'"$key"'":\([0-9]*\)/"'"$key"'":9\1/' "$TSUB" >"$SCRATCH/thinking-$f-343.jsonl"
		t_run_split node "$EXTRACTOR" "$SCRATCH/thinking-$f-343.jsonl"
		[ "$S_STATUS" = 2 ] && case $S_ERR in *msg_011CfZXyUJMx7CpnvxyFG4X1*"$f"*) true ;; *) false ;; esac &&
			pass "a later block whose $f differs is drift, naming the id and $f" ||
			fail "a later block with a different $f: exit $S_STATUS, row '$S_OUT', '$S_ERR'"
	done

	# A delta read anchored on the two-block id counts it once, in the earlier
	# read, and the anchor's later block is not a new message.
	t_run_split node "$EXTRACTOR" --after msg_011CfZXyUJMx7CpnvxyFG4X1 "$TSUB"
	[ "$S_STATUS" = 0 ] && [ "$S_OUT" = "$TMODEL 8 45 1708 13892 1 msg_011CfZXycwXfJKUZUXVPyGsv" ] &&
		pass "--after the two-block id counts only the message after it" ||
		fail "--after the two-block id: exit $S_STATUS, '$S_OUT'"
else
	echo "  skip  node is not on PATH — the two-block legs need the extractor"
fi

# ---------------------------------------------------------------------------
banner "30. No node: the reason names the fix, and the README says where it goes (#350)"
# ---------------------------------------------------------------------------
# Section 7 holds that a hook without node records a reason naming node. The
# retro of 2026-10-01 (finding F5a) found 4 of 4 session.usage and 41 agent.stop
# events in one window failing exactly that way, in a repository whose node is
# managed per user and lives nowhere the hooks' PATH reaches. The reason said
# what was missing and nothing about what to do; the fix is a personal,
# uncommitted settings entry in the agent harness — never a committed machine
# path — and the event is where an operator first meets the gap. So the reason
# names that file, and points at the adapter README section that gives the
# entry's shape — by its heading, which this section reads back out of the
# reason and looks up, so a renamed heading is a red suite rather than a
# pointer at nothing. Driven RED first against the section-7 reason and a
# README with no such section. Section 7 already asserts the session-end leg
# exits 0 and names node; here that pair is asserted on the subagent leg only.
#
# A MACHINE PATH, for both the reason and the README section: anything rooted
# at a directory that is one machine's or one platform's. One pattern for the
# two, so they cannot drift apart (review of PR #367, M-2).
MACHINE_PATH='(^|[^A-Za-z0-9_])/(home|Users|root|opt|usr|nix|var)/'
ADAPTER_README="$KIT/adapters/claude-code/README.md"
if env PATH="$NONODE" sh -c 'command -v node >/dev/null 2>&1'; then
	fail "the scrubbed PATH still finds node — the leg would prove nothing"
else
	for h in session-end subagent-stop; do
		case $h in
		session-end) P="$SCRATCH/end.json" K=session.usage ;;
		*) P="$SCRATCH/sub-stop.json" K=agent.stop ;;
		esac
		new_trace
		t_run_split env PATH="$NONODE" TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS= sh "$HOOKS/$h.sh" <"$P"
		F=$(ev_of "$K" | sed -n '1p')
		R=$(str "$F" reason)
		if [ "$h" = subagent-stop ]; then
			[ "$S_STATUS" = 0 ] && pass "$h.sh exits 0 with no node on PATH" ||
				fail "$h.sh exited $S_STATUS with no node: $S_ERR"
			case $R in
			*node*) pass "$K's reason names node" ;;
			*) fail "$K's reason does not name node: $F" ;;
			esac
		fi
		case $R in
		*settings.local.json*) pass "$K's reason names the personal settings file the path goes in" ;;
		*) fail "$K's reason does not say where the path goes (no settings.local.json): $F" ;;
		esac
		case $R in
		*adapters/claude-code/README.md*) pass "and points at the adapter README for the entry's shape" ;;
		*) fail "$K's reason does not point at adapters/claude-code/README.md: $F" ;;
		esac
		if printf '%s\n' "$R" | grep -Eq "$MACHINE_PATH"; then
			fail "$K's reason carries a machine path: $F"
		else
			pass "and carries no machine path of its own"
		fi
		# The heading the reason cites is the one the README has — read out of
		# the event, never typed here twice.
		H=$(printf '%s\n' "$R" | sed -n 's/.*adapters\/claude-code\/README\.md: \([^)]*\)).*/\1/p')
		if [ -z "$H" ]; then
			fail "$K's reason names the README but no section heading after it: $F"
		elif grep -Fxq "### $H" "$ADAPTER_README"; then
			pass "and the heading it cites, '$H', is a section of the README"
		else
			fail "$K's reason cites a README heading that does not exist: '$H'"
		fi
	done
fi

# The README section the reason points at. Its heading names the case (node
# managed per user); its body gives the settings file, the env block and the
# PATH key; and it holds no absolute machine path — a path that is right on
# one machine is wrong on every other, and a reader copies the nearest
# example. The section is the heading through to the next heading.
SECTION=$(awk '
	/^#+ / && found { exit }
	/^#+ / && tolower($0) ~ /node/ && tolower($0) ~ /per user/ { found = 1 }
	found { print }
' "$ADAPTER_README")
if [ -n "$SECTION" ]; then
	pass "adapters/claude-code/README.md has a section on node managed per user"
	for want in settings.local.json '"env"' PATH; do
		case $SECTION in
		*"$want"*) pass "and the section names $want" ;;
		*) fail "the section never names $want" ;;
		esac
	done
	case $SECTION in
	*uncommitted* | *"not committed"* | *"never committed"*) pass "and says the entry is uncommitted" ;;
	*) fail "the section does not say the entry stays uncommitted" ;;
	esac
	if printf '%s\n' "$SECTION" | grep -Eq "$MACHINE_PATH"; then
		fail "the section names an absolute machine path: $(printf '%s\n' "$SECTION" | grep -E "$MACHINE_PATH" | sed -n '1p')"
	else
		pass "and names no absolute machine path"
	fi
else
	fail "adapters/claude-code/README.md has no heading naming node managed per user"
fi

banner "31. A phantom stop writes nothing; an unreadable transcript is a named failure"
# ---------------------------------------------------------------------------
# Ticket #344 (retro 20261001T093317Z, F5b). A payload naming a transcript
# that does not exist is a phantom and writes no event; one naming a file that
# exists and cannot be read is a real stop whose usage is lost, recorded
# outcome=fail at once, naming the cause. The adapter README holds the why.
#
# None of these legs needs node: neither shape reaches the extractor.

# stop_on and timed are section 27's, defined outside its node guard.

# THE PHANTOM, with no bound and with one: nothing in the day file, nothing on
# either stream, no nap.
for bound in '' 5000; do
	new_trace
	stop_on "$SCRATCH/never-there-344.jsonl"
	timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS="$bound"
	[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && [ -z "$S_ERR" ] && [ "$NAPS" = 0 ] &&
		pass "a phantom stop (bound '${bound:-none}') exits 0, silent, without a nap" ||
		fail "a phantom stop (bound '${bound:-none}'): exit $S_STATUS, $NAPS naps, stdout '$S_OUT', stderr '$S_ERR'"
	[ -z "$(ev_of agent.stop)" ] &&
		pass "and writes no agent.stop event" ||
		fail "a phantom stop was recorded: $(ev_of agent.stop)"
	case $(events) in *'"outcome":"fail"'*) fail "a phantom stop put a fail line in the day file: $(events)" ;;
	*) pass "and the day file gains no fail line" ;; esac
done

# THE UNREADABLE FILE, with no bound and with one. Root reads a mode-000 file,
# so the leg cannot be driven there and says so.
if [ "$(id -u)" = 0 ]; then
	echo "  skip  running as root — a mode-000 file is readable, so the unreadable leg cannot be driven"
else
	cp "$FIX/subagent-transcript.redacted.jsonl" "$SCRATCH/unreadable-344.jsonl"
	chmod 000 "$SCRATCH/unreadable-344.jsonl"
	for bound in '' 5000; do
		new_trace
		stop_on "$SCRATCH/unreadable-344.jsonl"
		timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS="$bound"
		U=$(ev_of agent.stop)
		[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && [ -z "$S_ERR" ] && [ "$NAPS" = 0 ] &&
			pass "an unreadable transcript (bound '${bound:-none}') exits 0, silent, without a nap" ||
			fail "an unreadable transcript (bound '${bound:-none}'): exit $S_STATUS, $NAPS naps, stdout '$S_OUT', stderr '$S_ERR'"
		[ "$(printf '%s\n' "$U" | grep -c .)" = 1 ] && [ "$(str "$U" outcome)" = fail ] && [ -z "$(num "$U" tok_out)" ] &&
			pass "and records one agent.stop outcome=fail with no tokens" ||
			fail "an unreadable transcript recorded: $U"
		case $(str "$U" reason) in *'cannot be read'*) pass "whose reason names the cause" ;;
		*) fail "the reason does not say the transcript cannot be read: $(str "$U" reason)" ;; esac
	done
	chmod 600 "$SCRATCH/unreadable-344.jsonl"
fi

# THE RECORD. The adapter README says which shape a phantom takes.
d=$(tr '\n' ' ' <"$KIT/adapters/claude-code/README.md" | tr -s ' ' | tr '[:upper:]' '[:lower:]')
case $d in *"a phantom stop writes no event"*) pass "the adapter README records that a phantom stop writes no event" ;;
*) fail "the adapter README does not record the phantom stop's shape" ;; esac

# ---------------------------------------------------------------------------
banner "32. SessionStart records how far its checkout is behind origin/main (#384)"
# ---------------------------------------------------------------------------
# Retro 20261001T150216Z, finding G1. The kit's hooks execute the checkout they
# live in, and that checkout sat ~140 commits behind main for four hours with
# nothing saying so: every adapter fix of the wave was inert for the kit's own
# trace. The session-start hook now records the lag as data.behind — read with
# plain git from the LAST FETCHED origin/main, never a fetch of its own — and,
# past the policy threshold TRACE_BEHIND_WARN, says so once on stderr. With no
# origin/main it records nothing and still exits 0.
#
# A hook measures the checkout it LIVES in, so each leg copies the hooks and
# the shared script into a scratch repository with a real remote, and runs the
# copy. None of these legs needs node.

# behind_copy <dir> — the hooks and trace.sh, copied where a checkout would hold them.
behind_copy() {
	mkdir -p "$1/adapters/claude-code/hooks" "$1/scripts"
	cp "$HOOKS"/*.sh "$HOOKS"/*.mjs "$1/adapters/claude-code/hooks/"
	cp "$KIT/scripts/trace.sh" "$KIT/scripts/trace.config.sh" "$1/scripts/"
}

# behind_kit <dir> — a scratch checkout holding that copy, one commit, no
# remote yet.
behind_kit() {
	behind_copy "$1"
	t_git_identity "$1" "Behind Fixture" "behind@example.invalid"
	git -C "$1" add -A >/dev/null
	git -C "$1" commit -q -m "chore: the checkout the hooks run from"
}

# behind_remote <dir> <commits ahead> — give <dir> an origin whose main is
# <commits ahead> past its HEAD, FETCHED, so the lag is in the last fetched ref.
behind_remote() {
	git init -q --bare -b main "$1.remote.git"
	git -C "$1" remote add origin "$1.remote.git"
	git -C "$1" push -q origin main 2>/dev/null
	git clone -q "$1.remote.git" "$1.other" 2>/dev/null
	t_git_identity "$1.other" "Behind Fixture" "behind@example.invalid" >/dev/null 2>&1
	_br_i=0
	while [ "$_br_i" -lt "$2" ]; do
		_br_i=$((_br_i + 1))
		git -C "$1.other" commit -q --allow-empty -m "feat: main moves on $_br_i"
	done
	git -C "$1.other" push -q origin main 2>/dev/null
	git -C "$1" fetch -q origin 2>/dev/null
}

# start_in <dir> [env assignments…] — run <dir>'s copy of the session-start hook
# on the fixture payload, into a fresh trace. Sets S_* and START.
start_in() {
	_si_dir=$1
	shift
	new_trace
	t_run_split env TRACE_DIR="$TDIR" "$@" \
		sh "$_si_dir/adapters/claude-code/hooks/session-start.sh" <"$SCRATCH/start.json"
	START=$(ev_of session.start | sed -n '1p')
}

# behind_notes — how many stderr lines of the last run say the checkout is behind.
behind_notes() { printf '%s\n' "$S_ERR" | grep -c 'behind origin/main' || :; }

# BEHIND BY TWO: the field says 2; past a threshold of 1 the note prints ONCE.
B2="$SCRATCH/behind-two-384"
behind_kit "$B2"
behind_remote "$B2" 2
start_in "$B2"
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	pass "a checkout two behind: the hook exits 0, silent on stdout" ||
	fail "a checkout two behind: exit $S_STATUS, stdout '$S_OUT', stderr '$S_ERR'"
[ "$(str "$START" behind)" = 2 ] &&
	pass "and its session.start carries data.behind=2" ||
	fail "a checkout two behind recorded: $START"
[ "$(behind_notes)" = 0 ] &&
	pass "with no threshold set, nothing is said on stderr — the shipped default is silence" ||
	fail "with no threshold the hook still said: $S_ERR"
start_in "$B2" TRACE_BEHIND_WARN=1
[ "$S_STATUS" = 0 ] && [ "$(str "$START" behind)" = 2 ] &&
	pass "past a threshold of 1: still exit 0, still data.behind=2 (stdout's object is section 35's)" ||
	fail "past the threshold: exit $S_STATUS, stdout '$S_OUT', event $START"
[ "$(behind_notes)" = 1 ] &&
	pass "and stderr says so exactly once" ||
	fail "past the threshold stderr said it $(behind_notes) times: $S_ERR"
case $S_ERR in *'is 2 commits behind'*'TRACE_BEHIND_WARN=1'*) pass "the note names the count and the threshold's variable" ;;
*) fail "the note does not name the count and TRACE_BEHIND_WARN: $S_ERR" ;; esac
start_in "$B2" TRACE_BEHIND_WARN=2
[ "$(behind_notes)" = 0 ] &&
	pass "AT the threshold (2 behind, threshold 2) nothing is said — the note is for MORE than it" ||
	fail "at the threshold the hook still said: $S_ERR"

# THE POLICY FILE, not only the environment: the kit's twin is how this repo
# sets it, so the file has to be read the way TRACE_AGENT_WAIT_MS is.
printf "TRACE_BEHIND_WARN='1'\n" >"$SCRATCH/behind-policy-384.sh"
start_in "$B2" TRACE_CONFIG="$SCRATCH/behind-policy-384.sh"
[ "$(behind_notes)" = 1 ] &&
	pass "a threshold the policy file names is read too" ||
	fail "the policy file's TRACE_BEHIND_WARN=1 produced: '$S_ERR'"
start_in "$B2" TRACE_CONFIG="$SCRATCH/behind-policy-384.sh" TRACE_BEHIND_WARN=
[ "$(behind_notes)" = 0 ] &&
	pass "and an environment value of '' turns it off even when the file names one" ||
	fail "an empty environment threshold still printed: $S_ERR"

# A MALFORMED THRESHOLD is refused, named, and never a failure — the values
# section 27 drives for TRACE_AGENT_WAIT_MS, the leading zero (sh reads 0100 as
# octal) and six digits among them.
for bad in ten 1.5 -5 0100 1000000; do
	start_in "$B2" TRACE_BEHIND_WARN="$bad"
	[ "$S_STATUS" = 0 ] && [ "$(behind_notes)" = 0 ] && [ "$(str "$START" behind)" = 2 ] &&
		pass "a malformed threshold '$bad': exit 0, no behind note, the field still recorded" ||
		fail "a malformed threshold '$bad': exit $S_STATUS, event $START, stderr '$S_ERR'"
	case $S_ERR in *TRACE_BEHIND_WARN*"'$bad'"*) pass "and the refused '$bad' is named on stderr" ;;
	*) fail "the malformed threshold '$bad' was not named: $S_ERR" ;; esac
done

# NEVER A FETCH: main moves again on the remote, unfetched; the hook still
# reads the last fetched ref, so the count does not move.
git -C "$B2.other" commit -q --allow-empty -m "feat: main moves, unfetched"
git -C "$B2.other" push -q origin main 2>/dev/null
start_in "$B2"
[ "$(str "$START" behind)" = 2 ] &&
	pass "a commit pushed but not fetched does not count — the hook never fetches" ||
	fail "after an unfetched push the hook recorded: $START"

# LEVEL: the field says 0, and no threshold makes a note of it.
L0="$SCRATCH/level-384"
behind_kit "$L0"
behind_remote "$L0" 0
start_in "$L0" TRACE_BEHIND_WARN=0
[ "$S_STATUS" = 0 ] && [ "$(str "$START" behind)" = 0 ] &&
	pass "a checkout level with origin/main records data.behind=0" ||
	fail "a level checkout: exit $S_STATUS, event $START"
[ "$(behind_notes)" = 0 ] &&
	pass "and says nothing, even at threshold 0" ||
	fail "a level checkout still said: $S_ERR"

# NO REMOTE: no field, exit 0, nothing on either stream about it.
N0="$SCRATCH/no-remote-384"
behind_kit "$N0"
start_in "$N0" TRACE_BEHIND_WARN=0
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && [ -n "$START" ] &&
	pass "a checkout with no origin/main: exit 0, silent, the session.start still written" ||
	fail "no remote: exit $S_STATUS, stdout '$S_OUT', event '$START', stderr '$S_ERR'"
case $START in *'"behind"'*) fail "a checkout with no origin/main recorded a behind field: $START" ;;
*) pass "and it carries no behind field" ;; esac
[ "$(behind_notes)" = 0 ] &&
	pass "and nothing is said about a lag it cannot read" ||
	fail "with no remote the hook still said: $S_ERR"

# NOT A REPOSITORY AT ALL: the hooks copied somewhere git does not answer.
NG="$SCRATCH/no-git-384"
behind_copy "$NG"
start_in "$NG" GIT_CEILING_DIRECTORIES="$SCRATCH" TRACE_BEHIND_WARN=0
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	case $START in *'"behind"'*) false ;; *) true ;; esac &&
	pass "outside any repository: exit 0, silent, no behind field" ||
	fail "outside a repository: exit $S_STATUS, stdout '$S_OUT', event '$START'"

# A LINKED WORKTREE MEASURES THE ROOT. The kit's hooks execute from the root
# checkout, so a session opened in worktree/<slug> must report the ROOT's lag
# — the working tree of git's common directory, the derivation scripts/trace.sh
# uses — and never its own feature branch's, where being behind is normal.
WR="$SCRATCH/wt-root-384"
behind_kit "$WR"
WBASE=$(git -C "$WR" rev-parse HEAD)
behind_remote "$WR" 2
git -C "$WR" merge -q --ff-only origin/main
git -C "$WR" worktree add -q -b feat/wt-384 "$WR.wt" "$WBASE" 2>/dev/null
start_in "$WR.wt" TRACE_BEHIND_WARN=1
[ "$S_STATUS" = 0 ] && [ "$(str "$START" behind)" = 0 ] &&
	pass "from a worktree two behind on its feature branch, a level ROOT records data.behind=0" ||
	fail "a level root seen from a worktree: exit $S_STATUS, event $START"
[ "$(str "$START" behind_of)" = root ] &&
	pass "and the event says what was measured: data.behind_of=root" ||
	fail "no data.behind_of=root on: $START"
[ "$(behind_notes)" = 0 ] &&
	pass "and says nothing about the feature branch" ||
	fail "a level root still drew a note from the worktree: $S_ERR"
git -C "$WR" reset -q --hard "$WBASE"
start_in "$WR.wt" TRACE_BEHIND_WARN=1
[ "$(str "$START" behind)" = 2 ] &&
	pass "a root two behind records data.behind=2 from inside the worktree" ||
	fail "a root two behind, seen from the worktree: $START"
case $S_ERR in *"$WR is 2 commits behind"*) pass "and the note names the root's path, not the worktree's" ;;
*) fail "the note does not name the root path $WR: $S_ERR" ;; esac

# THE POLICY. The shipped file documents the variable and leaves it empty; the
# kit's twin sets it.
grep -q "^TRACE_BEHIND_WARN=''$" "$KIT/scripts/trace.config.sh" &&
	pass "scripts/trace.config.sh documents TRACE_BEHIND_WARN and ships it empty" ||
	fail "scripts/trace.config.sh has no empty TRACE_BEHIND_WARN line"
grep -qE "^TRACE_BEHIND_WARN='[1-9][0-9]*'$" "$KIT/scripts/trace.kit.config.sh" &&
	pass "the kit's own policy file sets a threshold" ||
	fail "scripts/trace.kit.config.sh sets no TRACE_BEHIND_WARN"

# THE RECORD. The adapter README documents the field and the switch beside
# their siblings.
d=$(tr '\n' ' ' <"$KIT/adapters/claude-code/README.md" | tr -s ' ')
case $d in *'data.behind'*'TRACE_BEHIND_WARN'*) pass "the adapter README documents data.behind and TRACE_BEHIND_WARN" ;;
*) fail "the adapter README does not document data.behind and TRACE_BEHIND_WARN" ;; esac

# THE READER. /housekeeping's checklist names the value and where it comes from.
d=$(tr '\n' ' ' <"$KIT/.agents/skills/housekeeping/CHECKLIST.md" | tr -s ' ')
case $d in *'session.start'*'data.behind'*) pass "the housekeeping checklist names the last session.start's data.behind" ;;
*) fail "the housekeeping checklist does not name session.start's data.behind" ;; esac

# ---------------------------------------------------------------------------
banner "33. A wait-bound stop says why: the transcript's last line, its age, its length"
# ---------------------------------------------------------------------------
# Ticket #387 (retro 20261001T150216Z, G4). 158 subagent stops in one window
# hit the ready-wait bound and said only that the transcript "did not end on a
# final message within the bound" — which cannot tell a bound too short (a
# young last line, still streaming) from an agent that never wrote a final
# message (an old one). So the fail event carries data.last_kind (the last
# line's top-level `type`, as the agent harness names it), data.last_age_ms
# (how old that line was when the bound elapsed) and data.lines. A transcript
# that ends inside the bound records tokens and none of the three.
#
# THE FIXTURE NEVER ENDS: section 27's first 19 lines, then one assistant line
# that called a tool — not final — written so that neither the first nor the
# last "type" on it is the top-level one, with an unbalanced brace and an
# escaped quoted key inside strings. Its mtime is set 30 s in the past: the
# age is the file's, since the last write is the last line landing.
{
	cat "$SCRATCH/sub-head-308.jsonl"
	printf '%s\n' '{"message":{"type":"message","role":"assistant","content":[{"type":"text","text":"a { brace and \"type\":\"fake\""},{"type":"tool_use","id":"t1","name":"Bash","input":{}}],"stop_reason":"tool_use"},"note":"\"type\":\"decoy\"","type":"assistant","toolUseResult":{"type":"text"},"uuid":"u-387"}'
} >"$SCRATCH/never-387.jsonl"
AGO_387=$(($(date +%s) - 30))
touch -d "@$AGO_387" "$SCRATCH/never-387.jsonl" 2>/dev/null ||
	touch -t "$(date -r "$AGO_387" +%Y%m%d%H%M.%S)" "$SCRATCH/never-387.jsonl"

new_trace
stop_on "$SCRATCH/never-387.jsonl"
timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=50
G=$(ev_of agent.stop)
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && [ "$(printf '%s\n' "$G" | grep -c .)" = 1 ] &&
	[ "$(str "$G" outcome)" = fail ] && [ -z "$(num "$G" tok_out)" ] &&
	pass "a transcript that never ends, 50 ms bound: exit 0, one agent.stop outcome=fail, no tokens" ||
	fail "never-ending transcript: exit $S_STATUS, stdout '$S_OUT', events: $G"
[ "$(str "$G" last_kind)" = assistant ] &&
	pass "data.last_kind is the last line's top-level type (assistant), not a nested one" ||
	fail "data.last_kind is '$(str "$G" last_kind)', expected assistant: $G"
[ "$(str "$G" lines)" = 20 ] && pass "data.lines is the transcript's 20 lines" ||
	fail "data.lines is '$(str "$G" lines)', expected 20: $G"
AGE_387=$(str "$G" last_age_ms)
[ "$AGE_387" -ge 30000 ] 2>/dev/null && [ "$AGE_387" -lt 150000 ] &&
	pass "data.last_age_ms is the last line's age when the bound elapsed (${AGE_387} ms, written 30 s before)" ||
	fail "data.last_age_ms is '$AGE_387', expected 30000 and up (slack for a loaded machine): $G"

# WHAT CANNOT BE READ IS LEFT OUT, never guessed (review of PR #394, M-1). A
# last line whose top-level type is not a plain word names no last_kind — not
# an empty one, not a placeholder, and not the nested "assistant" beneath it —
# while the other two keys still arrive.
{
	cat "$SCRATCH/sub-head-308.jsonl"
	printf '%s\n' '{"message":{"type":"assistant","stop_reason":"tool_use"},"type":"a b;c","uuid":"u-387b"}'
} >"$SCRATCH/oddkind-387.jsonl"
touch -d "@$AGO_387" "$SCRATCH/oddkind-387.jsonl" 2>/dev/null ||
	touch -t "$(date -r "$AGO_387" +%Y%m%d%H%M.%S)" "$SCRATCH/oddkind-387.jsonl"
new_trace
stop_on "$SCRATCH/oddkind-387.jsonl"
timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=50
O=$(ev_of agent.stop)
case $O in *'"last_kind"'*) fail "an unreadable top-level type still named a last_kind: $O" ;;
*) pass "a top-level type that is not a plain word names no last_kind" ;; esac
[ "$(str "$O" lines)" = 20 ] && [ "$(str "$O" last_age_ms)" -ge 30000 ] 2>/dev/null &&
	pass "and lines and last_age_ms still arrive" ||
	fail "lines or last_age_ms missing beside an unreadable kind: $O"

# NO MILLISECOND CLOCK: the age falls back to the file's whole seconds.
new_trace
stop_on "$SCRATCH/never-387.jsonl"
STUBS="$SCRATCH/noclock-308:$SCRATCH/naps-308" timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=50
N=$(ev_of agent.stop)
AGE_387=$(str "$N" last_age_ms)
[ "$AGE_387" -ge 30000 ] 2>/dev/null && [ $((AGE_387 % 1000)) = 0 ] &&
	pass "with no millisecond clock the age is whole seconds, still the file's (${AGE_387} ms)" ||
	fail "no-clock age is '$AGE_387', expected a whole-second multiple of at least 30000: $N"

# A TRANSCRIPT THAT ENDS INSIDE THE BOUND records tokens and none of the keys.
if [ "$HAVE_NODE" = 1 ]; then
	new_trace
	stop_on "$FIX/subagent-transcript.redacted.jsonl"
	timed TRACE_DIR="$TDIR" TRACE_AGENT_WAIT_MS=50
	F=$(ev_of agent.stop)
	[ "$(num "$F" tok_out)" = 156 ] && [ -z "$(str "$F" outcome)" ] &&
		pass "a transcript final inside the bound records its tokens" ||
		fail "a final transcript did not record its tokens: $F"
	case $F in *'"last_kind"'* | *'"last_age_ms"'* | *'"lines"'*)
		fail "a final transcript carried a wait-bound key: $F" ;;
	*) pass "and none of last_kind, last_age_ms, lines" ;; esac
else
	echo "  skip  node is not on PATH — the final-transcript leg reads tokens with the extractor"
fi

# ---------------------------------------------------------------------------
banner "34. PostToolUseFailure records the first line of the error as reason"
# ---------------------------------------------------------------------------
# A failed tool call's error may span many lines. The event's reason holds its
# first non-empty line, as written — quotes, dollar signs, backticks and
# backslashes included, since trace.sh escapes for JSON and nothing else needs
# to — with every character the trace refuses turned into a space and at most
# 300 characters kept; the full error stays in the result blob (#388).
# reason_of <event line> — the event's reason, DECODED from its JSON string, so
# a leg compares the text a reader gets back rather than the escaped bytes.
reason_of() {
	printf '%s\n' "$1" | node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(0, "utf8")).reason ?? "")'
}
if [ "$HAVE_NODE" = 1 ]; then
	# A simple error with multiple lines: first line as reason, full error in blob
	new_trace
	printf '{"session_id":"%s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"cat /nope"},"tool_use_id":"%s","error":"Exit code 1\\ncat: /nope: No such file or directory"}' \
		"$TSESSION" "$TUSE" >"$SCRATCH/tool-fail-reason-388.json"
	PAYLOAD="$SCRATCH/tool-fail-reason-388.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post-failure.payload.json"
	[ "$S_STATUS" = 0 ] && pass "a PostToolUseFailure with multiline error exits 0" ||
		fail "the hook exited $S_STATUS: $S_ERR"
	[ "$(ev_of tool.use | grep -c '')" = 1 ] && [ "$(events | grep -c '')" = 1 ] &&
		pass "the failure writes exactly one event, a tool.use" ||
		fail "the failure wrote $(events | grep -c '') line(s): $(events)"
	VOUT=$(TRACE_DIR="$TDIR" sh "$KIT/scripts/trace.sh" verify 2>&1) &&
		pass "and trace.sh verify accepts the day file it was written to" ||
		fail "trace.sh verify refuses the day file: $VOUT"
	E=$(ev_of tool.use | sed -n '1p')
	[ "$(str "$E" outcome)" = fail ] && pass "the event records outcome=fail" ||
		fail "the outcome is '$(str "$E" outcome)': $E"
	REASON=$(str "$E" reason)
	[ "$REASON" = "Exit code 1" ] && pass "the reason is the first line of the error: '$REASON'" ||
		fail "the reason is '$REASON', expected 'Exit code 1'"
	# Verify the full error is in the result blob
	ERH=$(str "$E" result_blob)
	FULL_ERR=$(cat "$(blob_file "$ERH")" 2>/dev/null)
	case $FULL_ERR in *"No such file or directory"*) pass "the result blob holds the full error" ;;
	*) fail "the result blob does not hold the full error: $FULL_ERR" ;; esac

	# An error with a single quote in the first line (should still be quote-safe)
	new_trace
	printf '{"session_id":"%s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"cmd"},"tool_use_id":"%s","error":"Can'"'"'t do it\\nmore details"}' \
		"$TSESSION" "$TUSE" >"$SCRATCH/tool-fail-quote-388.json"
	PAYLOAD="$SCRATCH/tool-fail-quote-388.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post-failure.payload.json"
	[ "$S_STATUS" = 0 ] && pass "an error with a quote in first line exits 0" ||
		fail "the hook exited $S_STATUS: $S_ERR"
	EQ=$(ev_of tool.use | sed -n '1p')
	QREASON=$(str "$EQ" reason)
	[ -n "$QREASON" ] && [ "$QREASON" = "Can't do it" ] &&
		pass "the reason with a quote is: '$QREASON'" ||
		fail "the reason with quote is '$QREASON', expected \"Can't do it\""
	# Verify no newline ended up in the reason
	case $EQ in *"$QREASON"*) pass "the event line contains the reason" ;;
	*) fail "the reason was not found in the event: $EQ" ;; esac

	# An error with nothing after the first line (single-line error)
	new_trace
	printf '{"session_id":"%s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"cmd"},"tool_use_id":"%s","error":"Something went wrong"}' \
		"$TSESSION" "$TUSE" >"$SCRATCH/tool-fail-single-388.json"
	PAYLOAD="$SCRATCH/tool-fail-single-388.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post-failure.payload.json"
	ES=$(ev_of tool.use | sed -n '1p')
	SR=$(str "$ES" reason)
	[ "$SR" = "Something went wrong" ] && pass "a single-line error's first line is: '$SR'" ||
		fail "a single-line error's reason is '$SR', expected 'Something went wrong'"

	# An error with double quotes (shell metacharacter)
	new_trace
	printf '{"session_id":"%s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"cmd"},"tool_use_id":"%s","error":"%s"}' \
		"$TSESSION" "$TUSE" 'Error opening \"config.json\"' >"$SCRATCH/tool-fail-dquote-388.json"
	PAYLOAD="$SCRATCH/tool-fail-dquote-388.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post-failure.payload.json"
	[ "$S_STATUS" = 0 ] && pass "an error with double quotes exits 0" ||
		fail "the hook exited $S_STATUS: $S_ERR"
	EDQ=$(ev_of tool.use | sed -n '1p')
	[ "$(str "$EDQ" outcome)" = fail ] && pass "the event records the double-quote error" ||
		fail "the outcome is not fail: $EDQ"
	[ "$(reason_of "$EDQ")" = 'Error opening "config.json"' ] && pass "the reason holds the double-quote error as written" ||
		fail "the reason of the double-quote error decodes to '$(reason_of "$EDQ")'"

	# An error with dollar sign (shell variable expansion metacharacter)
	new_trace
	printf '{"session_id":"%s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"cmd"},"tool_use_id":"%s","error":"Invalid value: $VAR"}' \
		"$TSESSION" "$TUSE" >"$SCRATCH/tool-fail-dollar-388.json"
	PAYLOAD="$SCRATCH/tool-fail-dollar-388.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post-failure.payload.json"
	[ "$S_STATUS" = 0 ] && pass "an error with dollar sign exits 0" ||
		fail "the hook exited $S_STATUS: $S_ERR"
	EDL=$(ev_of tool.use | sed -n '1p')
	[ "$(str "$EDL" outcome)" = fail ] && pass "the event records the dollar-sign error" ||
		fail "the outcome is not fail: $EDL"
	[ "$(reason_of "$EDL")" = 'Invalid value: $VAR' ] && pass "the reason holds the dollar-sign error as written" ||
		fail "the reason of the dollar-sign error decodes to '$(reason_of "$EDL")'"

	# An error with backtick (shell command substitution metacharacter)
	new_trace
	printf '{"session_id":"%s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"cmd"},"tool_use_id":"%s","error":"Failed: `whoami`"}' \
		"$TSESSION" "$TUSE" >"$SCRATCH/tool-fail-backtick-388.json"
	PAYLOAD="$SCRATCH/tool-fail-backtick-388.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post-failure.payload.json"
	[ "$S_STATUS" = 0 ] && pass "an error with backtick exits 0" ||
		fail "the hook exited $S_STATUS: $S_ERR"
	EBK=$(ev_of tool.use | sed -n '1p')
	[ "$(str "$EBK" outcome)" = fail ] && pass "the event records the backtick error" ||
		fail "the outcome is not fail: $EBK"
	[ "$(reason_of "$EBK")" = 'Failed: `whoami`' ] && pass "the reason holds the backtick error as written" ||
		fail "the reason of the backtick error decodes to '$(reason_of "$EBK")'"

	# An error with backslash (shell escape character)
	new_trace
	printf '{"session_id":"%s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"cmd"},"tool_use_id":"%s","error":"Path: C:\\\\Users\\\\file"}' \
		"$TSESSION" "$TUSE" >"$SCRATCH/tool-fail-backslash-388.json"
	PAYLOAD="$SCRATCH/tool-fail-backslash-388.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post-failure.payload.json"
	[ "$S_STATUS" = 0 ] && pass "an error with backslash exits 0" ||
		fail "the hook exited $S_STATUS: $S_ERR"
	EBS=$(ev_of tool.use | sed -n '1p')
	[ "$(str "$EBS" outcome)" = fail ] && pass "the event records the backslash error" ||
		fail "the outcome is not fail: $EBS"
	[ "$(reason_of "$EBS")" = 'Path: C:\Users\file' ] && pass "the reason holds the backslash error as written" ||
		fail "the reason of the backslash error decodes to '$(reason_of "$EBS")'"

	# Every character trace_json_str's [[:cntrl:]] refuses under a UTF-8 locale
	# — C0, DEL, C1 (U+0085 among them), U+2028 and U+2029 — becomes a space: a
	# reason carrying one would be refused by trace.sh and lose the event.
	new_trace
	printf '{"session_id":"%s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"cmd"},"tool_use_id":"%s","error":"a\\u0001b\\u007fc\\u0085d\\u009fe\\u2028f\\u2029g"}' \
		"$TSESSION" "$TUSE" >"$SCRATCH/tool-fail-cntrl-388.json"
	PAYLOAD="$SCRATCH/tool-fail-cntrl-388.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post-failure.payload.json"
	ECT=$(ev_of tool.use | sed -n '1p')
	[ "$(reason_of "$ECT")" = 'a b c d e f g' ] &&
		pass "every control character the trace refuses, U+0085 U+2028 U+2029 included, becomes a space" ||
		fail "the scrubbed reason decodes to '$(reason_of "$ECT")': $ECT"

	# The cap is 300 CHARACTERS, counted by code point: a character outside the
	# BMP at the boundary is kept whole, never split into half a surrogate pair.
	LONG=$(printf '%0299d' 0 | tr 0 x)
	new_trace
	printf '{"session_id":"%s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"cmd"},"tool_use_id":"%s","error":"%s\\ud83d\\ude00yyyy"}' \
		"$TSESSION" "$TUSE" "$LONG" >"$SCRATCH/tool-fail-cap-388.json"
	PAYLOAD="$SCRATCH/tool-fail-cap-388.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post-failure.payload.json"
	ECP=$(ev_of tool.use | sed -n '1p')
	[ "$(reason_of "$ECP")" = "$LONG$(printf '\360\237\230\200')" ] &&
		pass "the reason is capped at 300 characters, the last one kept whole" ||
		fail "the capped reason decodes to '$(reason_of "$ECP")'"

	# An error that OPENS with an empty line: the reason is the first line that
	# says something, not the empty one and not nothing.
	new_trace
	printf '{"session_id":"%s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"cmd"},"tool_use_id":"%s","error":"\\n\\r\\nPermission denied\\nmore"}' \
		"$TSESSION" "$TUSE" >"$SCRATCH/tool-fail-blankfirst-388.json"
	PAYLOAD="$SCRATCH/tool-fail-blankfirst-388.json"
	tool_post TRACE_DIR="$TDIR" TRACE_TOOLS=1
	PAYLOAD="$FIX/tool-post-failure.payload.json"
	EBF=$(ev_of tool.use | sed -n '1p')
	[ "$(reason_of "$EBF")" = 'Permission denied' ] &&
		pass "an error opening with an empty line records its first non-empty line" ||
		fail "the reason after an empty first line decodes to '$(reason_of "$EBF")'"
else
	echo "  skip  node is not on PATH — the tool failure reason legs need the payload reader"
fi

# ---------------------------------------------------------------------------
banner "35. PreToolUse: a spawned sub-agent cannot signal processes by name"
# ---------------------------------------------------------------------------
# Ticket #414 (retro 20261001T150216Z, the reviewer that killed suites). During
# PR #393's review a sub-agent ran `pkill -f` on two suite names and may have
# killed sibling sessions' runs. tool-pre-guard.sh refuses a Bash command that
# signals by NAME — pkill, killall, kill fed by pgrep, kill given a name — when
# the payload carries `agent_type`, which the agent harness sets on a spawned
# sub-agent's calls only. It exits 2, the agent harness's block status, with
# the rule named on stderr, and records one `note` (outcome=denied) on the
# session. The operator's own session (no agent_type) and a signal to a job or
# a pid pass through, exit 0 and silent.
GUARD="$HOOKS/tool-pre-guard.sh"
# guard_payload <agent_type or empty> <command> — a compact PreToolUse payload
# for a Bash call, the command JSON-escaped (backslash, then double quote).
guard_payload() {
	_gp_cmd=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')
	_gp_at=
	[ -n "$1" ] && _gp_at=",\"agent_id\":\"a1b2c3d4e5f60718\",\"agent_type\":\"$1\""
	printf '{"session_id":"%s","cwd":"/tmp/x","permission_mode":"default","hook_event_name":"PreToolUse"%s,"tool_name":"Bash","tool_input":{"command":"%s","description":"d"},"tool_use_id":"%s"}' \
		"$TSESSION" "$_gp_at" "$_gp_cmd" "$TUSE"
}
# guard <agent_type or empty> <command> [env…] — run the hook on that payload.
guard() {
	_g_at=$1
	_g_cmd=$2
	shift 2
	guard_payload "$_g_at" "$_g_cmd" >"$SCRATCH/guard-414.json"
	t_run_split env TRACE_DIR="$TDIR" "$@" sh "$GUARD" <"$SCRATCH/guard-414.json"
}
if [ -f "$GUARD" ]; then
	assert_status 0 "adapters/claude-code/hooks/tool-pre-guard.sh parses under sh -n" -- sh -n "$GUARD"
else
	fail "adapters/claude-code/hooks/tool-pre-guard.sh does not exist"
fi

new_trace
guard general-purpose 'pkill -f tests/x'
[ "$S_STATUS" = 2 ] && pass "a spawned sub-agent's 'pkill -f tests/x' is blocked with exit 2" ||
	fail "a spawned sub-agent's pkill exited $S_STATUS, not 2: $S_ERR"
# Anchored at the start: this very worktree's path holds the rule's name, and
# a "No such file" error quoting it must not read as the rule named.
case $S_ERR in kill-guard:*) pass "and stderr names the rule, kill-guard" ;;
*) fail "stderr does not name the rule: $S_ERR" ;; esac
[ -z "$S_OUT" ] && pass "and says nothing on stdout" || fail "the guard printed on stdout: $S_OUT"
[ "$(events | grep -c '')" = 1 ] && [ "$(ev_of note | grep -c '')" = 1 ] &&
	pass "the refusal is recorded as exactly one note" ||
	fail "the refusal wrote $(events | grep -c '') line(s): $(events)"
GN=$(ev_of note | sed -n '1p')
[ "$(str "$GN" outcome)" = denied ] && [ "$(str "$GN" subject)" = "session:$TSESSION" ] &&
	[ "$(str "$GN" rule)" = kill-guard ] && [ "$(str "$GN" tool_use_id)" = "$TUSE" ] &&
	pass "the note is outcome=denied on the session, naming the rule and the call" ||
	fail "the note is not denied/session/rule/call: $GN"

# The operator's own session carries no agent_type and is never refused.
new_trace
guard '' 'pkill -f tests/x'
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && [ -z "$(events)" ] &&
	pass "the operator's own 'pkill -f tests/x' passes through, exit 0, nothing recorded" ||
	fail "the operator's own pkill exited $S_STATUS or wrote: $S_OUT $(events)"

# Signalling a job or a pid the sub-agent holds passes through.
for c in 'kill %1' 'kill 12345' 'kill -9 12345' 'kill -s TERM 12345' 'sleep 30 & kill $!' \
	'grep -n pkill adapters/claude-code/hooks/tool-pre-guard.sh' "rg 'pkill|killall' ." \
	'git log --grep=killall' 'kill $pid 2>/dev/null' 'kill 123 >/dev/null 2>&1' 'kill 123 > /dev/null' \
	'kill $! # stop it' 'xargs kill < pids'; do
	new_trace
	guard general-purpose "$c"
	[ "$S_STATUS" = 0 ] && [ -z "$(events)" ] &&
		pass "a spawned sub-agent's '$c' passes through" ||
		fail "a spawned sub-agent's '$c' exited $S_STATUS: $S_ERR"
done

# Signalling by name, in each shape, is blocked.
for c in 'killall node' '/usr/bin/pkill -f vitest' 'cd tests && pkill -f x' 'sudo pkill x' \
	'kill -9 $(pgrep -f tests/x)' 'pgrep -f tests/x | xargs kill' 'kill -TERM vitest' \
	'timeout 5 killall sh' 'true; pkill x' 'sudo -u nobody pkill x' \
	'echo "a'"'"'b"; pkill -f x; echo "'"'"'"'; do
	new_trace
	guard general-purpose "$c"
	[ "$S_STATUS" = 2 ] && pass "a spawned sub-agent's '$c' is blocked" ||
		fail "a spawned sub-agent's '$c' exited $S_STATUS, not 2: $S_ERR"
done

# A tool that is not Bash is not the guard's business, whatever its input says.
new_trace
guard_payload general-purpose 'pkill x' | sed 's/"tool_name":"Bash"/"tool_name":"Grep"/' >"$SCRATCH/guard-grep-414.json"
t_run_split env TRACE_DIR="$TDIR" sh "$GUARD" <"$SCRATCH/guard-grep-414.json"
[ "$S_STATUS" = 0 ] && pass "a Grep call whose input names pkill passes through" ||
	fail "a non-Bash call exited $S_STATUS"

# Tracing off still blocks: the refusal is the guard, the note is a record.
new_trace
guard_payload general-purpose 'pkill -f tests/x' >"$SCRATCH/guard-414.json"
t_run_split env TRACE_DIR= TRACE_CONFIG="$KIT/scripts/trace.config.sh" sh "$GUARD" <"$SCRATCH/guard-414.json"
[ "$S_STATUS" = 2 ] && [ -z "$(events)" ] && pass "with tracing off the pkill is still blocked, and nothing is written" ||
	fail "with tracing off the guard exited $S_STATUS"

# WITHOUT NODE it fails CLOSED for a sub-agent: a payload naming a kill-by-name
# word is blocked rather than waved through unread.
new_trace
guard general-purpose 'pkill -f tests/x' PATH="$(no_node_path)"
[ "$S_STATUS" = 2 ] && pass "with node off PATH a sub-agent's pkill is still blocked" ||
	fail "with node off PATH the guard exited $S_STATUS: $S_ERR"
new_trace
guard general-purpose 'kill %1' PATH="$(no_node_path)"
[ "$S_STATUS" = 0 ] && pass "and its 'kill %1' still passes" ||
	fail "with node off PATH 'kill %1' exited $S_STATUS: $S_ERR"

# THE WIRING: the kit's settings file runs the guard on PreToolUse for Bash.
if [ "$HAVE_NODE" = 1 ]; then
	PRE=$(node -e 'const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
		for (const g of (s.hooks.PreToolUse || [])) for (const h of g.hooks || []) console.log(g.matcher + " " + h.command);' "$SETTINGS")
	case $PRE in Bash\ *tool-pre-guard.sh*) pass "the settings file wires tool-pre-guard.sh on PreToolUse, matcher Bash" ;;
	*) fail "the settings file does not wire the guard on PreToolUse for Bash: $PRE" ;; esac
else
	echo "  skip  node is not on PATH — the PreToolUse wiring check needs a JSON parser"
fi

# ---------------------------------------------------------------------------
banner "36. The behind note reaches the operator: one JSON object on stdout (#427)"
# ---------------------------------------------------------------------------
# Ticket #427, from the live check of #384. On the agent harness as it is, a
# SessionStart hook's stderr on exit 0 reaches nobody: the note of section 32
# landed only in the transcript's own records. Two channels do reach a reader,
# and the adapter README records the probe that chose them: a top-level
# `systemMessage`, which the agent harness documents as shown to the user and
# an interactive session prints under its banner, and
# `hookSpecificOutput.additionalContext`, which the model reads and relays —
# the one that reaches a non-interactive run's output. So past the threshold
# the hook prints exactly one JSON object carrying both, still exits 0, and
# still says the line on stderr. Under the threshold stdout stays empty.

# behind_json_ok <stdout> <needle> — node parses the object: systemMessage and
# additionalContext both hold <needle>, the event name is SessionStart. Status 0
# for yes. Without node the caller skips the leg.
behind_json_ok() {
	printf '%s' "$1" | node -e '
		let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
			const o = JSON.parse(s), n = process.argv[1], h = o.hookSpecificOutput || {};
			const ok = typeof o.systemMessage === "string" && o.systemMessage.includes(n) &&
				h.hookEventName === "SessionStart" &&
				typeof h.additionalContext === "string" && h.additionalContext.includes(n);
			process.exit(ok ? 0 : 1);
		});' "$2" 2>/dev/null
}

J2="$SCRATCH/behind-json-427"
behind_kit "$J2"
behind_remote "$J2" 2
start_in "$J2" TRACE_BEHIND_WARN=1
[ "$S_STATUS" = 0 ] && [ "$(printf '%s\n' "$S_OUT" | grep -c .)" = 1 ] &&
	case $S_OUT in '{'*'}') true ;; *) false ;; esac &&
	pass "past the threshold: exit 0, and stdout is exactly one line holding one JSON object" ||
	fail "past the threshold: exit $S_STATUS, stdout '$S_OUT'"
case $S_OUT in *'"systemMessage":"'*'is 2 commits behind origin/main'*'"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"'*'is 2 commits behind origin/main'*)
	pass "the object carries the note as systemMessage and as SessionStart additionalContext" ;;
*) fail "the object does not carry the note in both fields: $S_OUT" ;; esac
[ "$(behind_notes)" = 1 ] && [ "$(str "$START" behind)" = 2 ] &&
	pass "and the stderr line and data.behind=2 are both still there" ||
	fail "stderr said it $(behind_notes) times, event $START"
if [ "$HAVE_NODE" = 1 ]; then
	behind_json_ok "$S_OUT" 'is 2 commits behind origin/main' &&
		pass "the object parses as JSON, both fields holding the note" ||
		fail "the object does not parse or lacks the note: $S_OUT"
else
	echo "  skip  node is not on PATH — the JSON parse leg needs it"
fi

start_in "$J2" TRACE_BEHIND_WARN=2
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	pass "AT the threshold stdout stays empty — no object when there is nothing to say" ||
	fail "at the threshold stdout held: '$S_OUT'"
start_in "$J2"
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	pass "with no threshold stdout stays empty" ||
	fail "with no threshold stdout held: '$S_OUT'"
start_in "$J2" TRACE_BEHIND_WARN=ten
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
	pass "a malformed threshold is refused on stderr only — stdout stays empty" ||
	fail "a malformed threshold put on stdout: '$S_OUT'"

# A ROOT PATH THAT NEEDS ESCAPING: a quote and a backslash in the directory
# name still make one valid object — the path is data, not JSON.
JQ="$SCRATCH/behind \"q\\427"
behind_kit "$JQ"
behind_remote "$JQ" 3
start_in "$JQ" TRACE_BEHIND_WARN=1
[ "$S_STATUS" = 0 ] && [ "$(printf '%s\n' "$S_OUT" | grep -c .)" = 1 ] &&
	pass "a root path holding a quote and a backslash: exit 0, one line on stdout" ||
	fail "an escaping root path: exit $S_STATUS, stdout '$S_OUT'"
if [ "$HAVE_NODE" = 1 ]; then
	behind_json_ok "$S_OUT" "$JQ is 3 commits behind origin/main" &&
		pass "and it parses, the path read back exactly as written" ||
		fail "the escaping root path broke the object: $S_OUT"
fi

# THE RECORD. The adapter README says which channel and why.
d=$(tr '\n' ' ' <"$KIT/adapters/claude-code/README.md" | tr -s ' ')
case $d in *'#427'*'systemMessage'*'additionalContext'*'rule 1'*) pass "the adapter README records the channel: systemMessage, additionalContext, and the ticket" ;;
*) fail "the adapter README does not record the behind note's channel" ;; esac
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
banner "37. The phantom-stop count survives on session.end (#410)"
# ---------------------------------------------------------------------------
# Ticket #410 (a known gap of 2026-10-01, origin #344). A phantom stop still
# writes no event (section 31), but it now adds one line to a per-session
# counter in the adapter's own claude-code/ directory under the trace, and the
# session-end hook
# records the count as data.phantoms on session.end — 0 when there were none —
# and takes the counter with it, so a resumed session's next end counts only
# what came after. None of these legs needs node: a phantom never reaches the
# extractor, and session.end is written whether the usage read worked or not.

# phantom_of <session id> — a SubagentStop payload for that session, naming a
# subagent transcript that does not exist.
phantom_of() {
	set_key session_id "$1" <"$FIX/subagent-stop.payload.json" |
		set_key transcript_path "$SCRATCH/main.jsonl" |
		set_key agent_transcript_path "$SCRATCH/never-there-410.jsonl" >"$SCRATCH/phantom-410.json"
	env TRACE_DIR="$TDIR" sh "$HOOKS/subagent-stop.sh" <"$SCRATCH/phantom-410.json" >/dev/null 2>&1
}

# end_of <session id> — the SessionEnd hook for that session.
end_of() {
	set_key session_id "$1" <"$FIX/session-end.payload.json" |
		set_key transcript_path "$SCRATCH/main.jsonl" >"$SCRATCH/end-410.json"
	env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-410.json" >/dev/null 2>&1
}

# end_line <session id> — that session's session.end lines.
end_line() { ev_of session.end | grep -F "\"subject\":\"session:$1\"" || :; }

S410A=sess-410-a
S410B=sess-410-b
new_trace
phantom_of "$S410A"
phantom_of "$S410A"
phantom_of "$S410B"
phantom_of "$S410A"
[ -z "$(ev_of agent.stop)" ] && pass "four phantom stops still write no agent.stop event" ||
	fail "a phantom stop was recorded: $(ev_of agent.stop)"
[ "$(find "$TDIR/claude-code" -name '*.phantoms' 2>/dev/null | wc -l | tr -d ' ')" = 2 ] &&
	pass "the stops are counted in the adapter's own claude-code/ directory, one counter per session" ||
	fail "expected two counters under claude-code/, found: $(find "$TDIR" -type f ! -path '*/events/*' 2>/dev/null)"
[ -z "$(find "$TDIR/current" -name '*.phantoms*' 2>/dev/null)" ] &&
	pass "and none in current/, whose layout the shared trace script owns" ||
	fail "a counter landed in current/: $(find "$TDIR/current" -name '*.phantoms*')"
end_of "$S410A"
EA=$(end_line "$S410A")
[ "$(data_of "$EA" phantoms)" = 3 ] &&
	pass "three phantoms then a session end: session.end carries phantoms=3" ||
	fail "session.end for $S410A carries phantoms='$(data_of "$EA" phantoms)': $EA"
end_of "$S410B"
EB=$(end_line "$S410B")
[ "$(data_of "$EB" phantoms)" = 1 ] &&
	pass "the counter is per session: the other session reads its own one" ||
	fail "session.end for $S410B carries phantoms='$(data_of "$EB" phantoms)': $EB"

# NONE, and a resumed session's second end: 0, written rather than left out.
end_of "$S410A"
EA2=$(end_line "$S410A" | sed -n '2p')
[ "$(data_of "$EA2" phantoms)" = 0 ] &&
	pass "a second end of the same session counts only what came after it: phantoms=0" ||
	fail "the second session.end for $S410A carries phantoms='$(data_of "$EA2" phantoms)': $EA2"
end_of sess-410-none
[ "$(data_of "$(end_line sess-410-none)" phantoms)" = 0 ] &&
	pass "a session with no phantom stops records phantoms=0" ||
	fail "a session with none recorded: $(end_line sess-410-none)"
[ -z "$(find "$TDIR" -name '*.phantoms*' 2>/dev/null)" ] &&
	pass "and every ended session's counter is gone from the trace directory" ||
	fail "a counter outlived its session's end: $(find "$TDIR" -name '*.phantoms*')"

# A REFUSED ID — hostile, traversing, or absent — is never a path: no counter
# lands anywhere, and that session's end carries no phantoms key at all.
new_trace
for bad in 'abc; touch PWNED-410' '../../escape-410'; do
	phantom_of "$bad"
	end_of "$bad"
done
set_key agent_transcript_path "$SCRATCH/never-there-410.jsonl" <"$FIX/subagent-stop.payload.json" |
	grep -v '"session_id"' >"$SCRATCH/phantom-noid-410.json"
env TRACE_DIR="$TDIR" sh "$HOOKS/subagent-stop.sh" <"$SCRATCH/phantom-noid-410.json" >/dev/null 2>&1
grep -v '"session_id"' <"$FIX/session-end.payload.json" >"$SCRATCH/end-noid-410.json"
env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-noid-410.json" >/dev/null 2>&1
LEFT=$(
	find "$TDIR" -name '*.phantoms*' 2>/dev/null
	find "$SCRATCH" "$(dirname "$SCRATCH")" -maxdepth 1 \( -name 'escape-410*' -o -name 'PWNED-410*' \) 2>/dev/null
)
[ -z "$LEFT" ] &&
	pass "a hostile, traversing or missing session id leaves no counter anywhere" ||
	fail "a refused id left files: $LEFT"
case $(ev_of session.end) in *'"phantoms"'*) fail "a session end with a refused or missing id carried a phantoms key: $(ev_of session.end)" ;;
*) [ -n "$(ev_of session.end)" ] && pass "and its session.end carries no phantoms key" ||
	fail "no session.end was written for the refused ids" ;; esac

# TRACING OFF — no TRACE_DIR and the shipped, empty policy file: the counter
# has nowhere to go, and the hook still exits 0 and says nothing.
t_run_split env -u TRACE_DIR TRACE_CONFIG="$KIT/scripts/trace.config.sh" sh "$HOOKS/subagent-stop.sh" <"$SCRATCH/phantom-410.json"
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && [ -z "$S_ERR" ] &&
	pass "with tracing off a phantom stop exits 0 and says nothing" ||
	fail "with tracing off: exit $S_STATUS, stdout '$S_OUT', stderr '$S_ERR'"

# THE RECORD. The adapter README says what a session with none writes.
d=$(tr '\n' ' ' <"$KIT/adapters/claude-code/README.md" | tr -s ' ' | tr '[:upper:]' '[:lower:]')
case $d in *"a session with no phantom stops records \`phantoms=0\`"*) pass "the adapter README records that a session with none writes 0" ;;
*) fail "the adapter README does not say what a session with no phantom stops records" ;; esac

# ---------------------------------------------------------------------------
banner "38. A compaction's summary call is counted: the rollup gap becomes an event (#407)"
# ---------------------------------------------------------------------------
# The call that writes a compaction summary leaves NO assistant line, so its
# tokens reach the agent harness's own rollup and no message-by-message sum
# (tests/fixtures/claude-code/README.md, "The fifth capture"). The session-end
# hook now reads the rollup beside the sums and records the difference, per
# model, as one more `session.usage` event with data.via=rollup and
# data.reason=compaction — so the plain sum of the events IS the rollup. The
# compacted fixture is the #307 session in full: three runs, a /compact, two
# more answers; its first 34 lines are the resumed fixture's session.
CFIX="$FIX/compacted-transcript.redacted.jsonl"
KFIX="$FIX/forked-transcript.redacted.jsonl"
CLAST=msg_011CfZUqmQSnMv2oo8z5oPGf
CGAP="$RMODEL 1473 453 38 24035 rollup compaction"

# crollup <line> — the four rollup numbers of that cost-state line, in event order.
crollup() {
	_cr=$(sed -n "$1p" "$CFIX" | sed -n 's/.*"'"$RMODEL"'":{\([^}]*\)}.*/\1/p')
	for _k in inputTokens outputTokens cacheCreationInputTokens cacheReadInputTokens; do
		printf '%s\n' "$_cr" | sed -n 's/.*"'"$_k"'":\([0-9]*\).*/\1/p'
	done | paste -sd' ' -
}
R85=$(crollup 85)
[ "$R85" = "1521 744 17305 128201" ] && [ "$(crollup 58)" = "1503 556 10354 85813" ] &&
	pass "the compacted fixture's rollups are the ones its README records" ||
	fail "the compacted fixture's rollups moved: line 58 '$(crollup 58)', line 85 '$R85'"
grep -q '"subtype":"compact_boundary"' "$CFIX" && pass "and it holds the compact boundary" ||
	fail "the compacted fixture holds no compact boundary"

if [ "$HAVE_NODE" = 1 ]; then
	# THE EXTRACTOR, asked to judge the rollup. Without the flag nothing moves:
	# the subagent-stop hook reads a subagent's file, which carries no rollup.
	t_run_split node "$EXTRACTOR" "$CFIX"
	[ "$S_STATUS" = 0 ] && [ "$S_OUT" = "$RMODEL 48 291 17267 104166 5 $CLAST" ] &&
		pass "without --rollup the compacted file is its five messages, as before" ||
		fail "the plain read printed '$S_OUT' (status $S_STATUS)"
	t_run_split node "$EXTRACTOR" --rollup "$CFIX" </dev/null
	[ "$S_STATUS" = 0 ] && pass "the extractor takes --rollup" ||
		fail "--rollup exited $S_STATUS: $S_ERR"
	[ "$(printf '%s\n' "$S_OUT" | sed -n '1p')" = "$RMODEL 48 291 17267 104166 5 $CLAST" ] &&
		pass "the message row is unchanged under --rollup" ||
		fail "the message row under --rollup: $(printf '%s\n' "$S_OUT" | sed -n '1p')"
	[ "$(printf '%s\n' "$S_OUT" | sed -n '2p')" = "$CGAP" ] &&
		pass "and one more row is the gap: line 85's rollup less the messages ($CGAP)" ||
		fail "the gap row is '$(printf '%s\n' "$S_OUT" | sed -n '2p')', expected '$CGAP'"
	[ "$(printf '%s\n' "$S_OUT" | grep -c '')" = 2 ] && pass "and nothing else" ||
		fail "--rollup printed: $S_OUT"
	t_run_split node "$EXTRACTOR" --rollup --after "$RMSG2" "$CFIX" </dev/null
	[ "$(printf '%s\n' "$S_OUT" | sed -n '$p')" = "$CGAP" ] &&
		pass "the gap is the whole file's, whatever the anchor: an anchor counts messages, not the gap" ||
		fail "--rollup --after $RMSG2 printed '$S_OUT'"

	# EQUAL IS NO EVENT. The resumed session's rollup is its messages exactly.
	t_run_split node "$EXTRACTOR" --rollup "$RFIX" </dev/null
	[ "$S_STATUS" = 0 ] && [ "$S_OUT" = "$RMODEL 20 72 10239 37743 2 $RMSG2" ] &&
		pass "a rollup equal to the sum adds no row" ||
		fail "the resumed fixture under --rollup: status $S_STATUS, '$S_OUT'"
	# NO BOUNDARY, NO GAP. The first capture's rollup also counts its subagent,
	# whose events the subagent-stop hook writes: a gap here would count it twice.
	t_run_split node "$EXTRACTOR" --rollup "$SCRATCH/main.jsonl" </dev/null
	[ "$S_STATUS" = 0 ] && [ "$(printf '%s\n' "$S_OUT" | grep -c ' rollup ')" = 0 ] &&
		pass "a transcript with no compact boundary is never judged against its rollup" ||
		fail "the uncompacted transcript under --rollup: status $S_STATUS, '$S_OUT'"
	# A FORK carries the parent's rollup and the parent's messages with their
	# usage zeroed, so its gap would be the parent's whole spend a second time.
	t_run_split node "$EXTRACTOR" --rollup "$KFIX" </dev/null
	[ "$S_STATUS" = 0 ] && [ "$S_OUT" = "$RMODEL 10 39 6725 17813 2 msg_011CfZUgBT2SxFuAbdAdifgs" ] &&
		pass "a forked transcript (copied messages, usage zeroed) records no gap" ||
		fail "the forked fixture under --rollup: status $S_STATUS, '$S_OUT'"
	# A STALE ROLLUP: messages after the last cost-state line mean the rollup
	# does not describe this end, so nothing is judged against it.
	head -83 "$CFIX" >"$SCRATCH/compacted-stale-407.jsonl"
	t_run_split node "$EXTRACTOR" --rollup "$SCRATCH/compacted-stale-407.jsonl" </dev/null
	[ "$S_STATUS" = 0 ] && [ "$(printf '%s\n' "$S_OUT" | grep -c ' rollup ')" = 0 ] &&
		pass "a rollup older than the last message is never judged" ||
		fail "the stale rollup: status $S_STATUS, '$S_OUT'"

	# A GAP ALREADY RECORDED is read back from the trace on stdin, so a later
	# end of the same session never records it twice.
	printf '%s\n' '{"kind":"session.usage","model":"'"$RMODEL"'","tok_in":1473,"tok_out":453,"tok_cache_w":38,"tok_cache_r":24035,"data":{"via":"rollup","reason":"compaction"}}' \
		>"$SCRATCH/recorded-407.jsonl"
	t_run_split node "$EXTRACTOR" --rollup "$CFIX" <"$SCRATCH/recorded-407.jsonl"
	[ "$S_STATUS" = 0 ] && [ "$S_OUT" = "$RMODEL 48 291 17267 104166 5 $CLAST" ] &&
		pass "a gap the trace already holds is not a gap again" ||
		fail "with the gap recorded: status $S_STATUS, '$S_OUT'"

	# THE SUBAGENTS' FILES are what the rollup counts beside the session's
	# lines, so they are taken off before the gap is judged.
	mkdir -p "$SCRATCH/compacted-sub-407/subagents"
	cp "$FIX/thinking-subagent-transcript.redacted.jsonl" "$SCRATCH/compacted-sub-407/subagents/agent-a1.jsonl"
	sed '$s/"inputTokens":1521,"outputTokens":744,"thinkingTokens":599,"cacheReadInputTokens":128201,"cacheCreationInputTokens":17305/"inputTokens":1539,"outputTokens":902,"thinkingTokens":599,"cacheReadInputTokens":142093,"cacheCreationInputTokens":32905/' \
		"$CFIX" >"$SCRATCH/compacted-sub-407.jsonl"
	t_run_split node "$EXTRACTOR" --rollup "$SCRATCH/compacted-sub-407.jsonl" </dev/null
	[ "$S_STATUS" = 0 ] && [ "$(printf '%s\n' "$S_OUT" | sed -n '$p')" = "$CGAP" ] &&
		pass "a subagent's tokens in the rollup are its own events', never the gap's" ||
		fail "with a subagent: status $S_STATUS, '$S_OUT' ($S_ERR)"

	# SMALLER THAN THE SUM is drift — but the message rows are facts the
	# rollup cannot unmake, so they are still printed, and the exit is 3.
	sed '$s/"inputTokens":1521,/"inputTokens":21,/' "$CFIX" >"$SCRATCH/compacted-short-407.jsonl"
	t_run_split node "$EXTRACTOR" --rollup "$SCRATCH/compacted-short-407.jsonl" </dev/null
	[ "$S_STATUS" = 3 ] && pass "a rollup smaller than the sum exits 3" ||
		fail "a short rollup exited $S_STATUS: $S_OUT"
	[ "$S_OUT" = "$RMODEL 48 291 17267 104166 5 $CLAST" ] &&
		pass "and still prints the message rows, with no gap row" ||
		fail "a short rollup printed '$S_OUT'"
	case $S_ERR in *"x transcript-usage:"*tok_in*) pass "and names the field that came up short" ;;
	*) fail "a short rollup's stderr: $S_ERR" ;; esac

	# THROUGH THE HOOK, end by end as the session ran: three runs, the
	# /compact run, then the last — the files as each end found them.
	new_trace
	set_key transcript_path "$SCRATCH/compacted-407.jsonl" <"$FIX/session-end.payload.json" |
		set_key session_id "$RSESSION" >"$SCRATCH/end-compacted-407.json"
	for n in 25 34 42 58 85; do
		head -"$n" "$CFIX" >"$SCRATCH/compacted-407.jsonl"
		t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-compacted-407.json"
		[ "$S_STATUS" = 0 ] || fail "the end at line $n exited $S_STATUS: $S_ERR"
	done
	[ "$(model_row "$RMODEL")" = "$R85" ] &&
		pass "five ends later, summary --by model totals the session at line 85's rollup ($R85)" ||
		fail "summary --by model totals '$(model_row "$RMODEL")', the rollup says '$R85'"
	GAPS=$(ev_of session.usage | grep -F '"via":"rollup"')
	[ "$(printf '%s\n' "$GAPS" | grep -c .)" = 1 ] && pass "with exactly one rollup-gap event" ||
		fail "rollup-gap events: $GAPS"
	[ "$(num "$GAPS" tok_in) $(num "$GAPS" tok_out) $(num "$GAPS" tok_cache_w) $(num "$GAPS" tok_cache_r)" = "1473 453 38 24035" ] &&
		[ "$(str "$GAPS" model)" = "$RMODEL" ] && [ "$(data_of "$GAPS" reason)" = compaction ] &&
		pass "on the model, with the compaction's counts and data.reason=compaction" ||
		fail "the rollup-gap event: $GAPS"
	[ -z "$(data_of "$GAPS" last_msg)" ] && [ -z "$(data_of "$GAPS" msgs)" ] &&
		pass "and no last_msg or msgs: it counts no message, so it never anchors a read" ||
		fail "the gap event carries an anchor: $GAPS"
	ULAST=$(ev_of session.usage | grep -F '"last_msg"' | sed -n '$p')
	[ "$(data_of "$ULAST" last_msg)" = "$CLAST" ] && [ "$(data_of "$ULAST" msgs)" = 2 ] &&
		pass "the last end's anchor is still the last message it counted: $CLAST, two messages" ||
		fail "the anchor after the last end: $ULAST"
	[ -z "$(ev_of session.usage | grep -F '"outcome":"fail"')" ] && pass "and no end recorded a failure" ||
		fail "an end failed: $(ev_of session.usage | grep -F '"outcome":"fail"')"
	# One more end with nothing new adds nothing.
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-compacted-407.json"
	[ "$(model_row "$RMODEL")" = "$R85" ] && pass "a sixth end with nothing new leaves the total at the rollup" ||
		fail "a sixth end moved the total to '$(model_row "$RMODEL")'"

	# One end over the whole file: the same total, from one read.
	new_trace
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-compacted-407.json"
	[ "$(model_row "$RMODEL")" = "$R85" ] && pass "a single end over the whole file totals the rollup too" ||
		fail "a single end totals '$(model_row "$RMODEL")'"

	# Through the hook, a short rollup: the messages are recorded and the
	# refusal is its own failure event, and the hook still exits 0.
	new_trace
	cp "$SCRATCH/compacted-short-407.jsonl" "$SCRATCH/compacted-407.jsonl"
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-compacted-407.json"
	[ "$S_STATUS" = 0 ] && pass "a short rollup through the hook exits 0" || fail "the hook exited $S_STATUS"
	[ "$(model_row "$RMODEL")" = "48 291 17267 104166" ] && pass "and the messages are still recorded" ||
		fail "with a short rollup the total is '$(model_row "$RMODEL")'"
	SHORT=$(ev_of session.usage | grep -F '"outcome":"fail"')
	[ "$(printf '%s\n' "$SHORT" | grep -c .)" = 1 ] && [ "$(data_of "$SHORT" via)" = rollup ] &&
		pass "beside one failure event, data.via=rollup, that says why no gap was recorded" ||
		fail "the short-rollup failure: $SHORT"

	# FROM THE REVIEW OF PR #438 — each a regression now.
	# H-1: a rollup key's context-window suffix names the same model.
	sed '$s/"'"$RMODEL"'":{"inputTokens"/"'"$RMODEL"'[1m]":{"inputTokens"/' "$CFIX" >"$SCRATCH/compacted-suffix-407.jsonl"
	t_run_split node "$EXTRACTOR" --rollup "$SCRATCH/compacted-suffix-407.jsonl" </dev/null
	[ "$S_STATUS" = 0 ] && [ "$(printf '%s\n' "$S_OUT" | sed -n '$p')" = "$CGAP" ] &&
		pass "a rollup key with a context-window suffix ([1m]) is the message's model" ||
		fail "the suffixed rollup key: status $S_STATUS, '$S_OUT'"
	# H-1: drift in a subagent file refuses the rollup, names the file, keeps the rows.
	mkdir -p "$SCRATCH/compacted-subdrift-407/subagents"
	sed 's/"output_tokens":/"output_tokenz":/g' "$FIX/thinking-subagent-transcript.redacted.jsonl" \
		>"$SCRATCH/compacted-subdrift-407/subagents/agent-x.jsonl"
	cp "$CFIX" "$SCRATCH/compacted-subdrift-407.jsonl"
	t_run_split node "$EXTRACTOR" --rollup "$SCRATCH/compacted-subdrift-407.jsonl" </dev/null
	[ "$S_STATUS" = 3 ] && [ "$S_OUT" = "$RMODEL 48 291 17267 104166 5 $CLAST" ] &&
		case $S_ERR in *"subagents/agent-x.jsonl: "*) true ;; *) false ;; esac &&
		pass "a subagent file's drift refuses the rollup (exit 3), names the file and keeps the rows" ||
		fail "subagent drift: status $S_STATUS, '$S_OUT', '$S_ERR'"
	# H-1: a modelUsage that is not an object, and a recorded line that is not JSON.
	sed '$s/"modelUsage":{/"modelUsage":[{/; $s/}},"hasUnknownModelCost"/}}],"hasUnknownModelCost"/' "$CFIX" >"$SCRATCH/compacted-arr-407.jsonl"
	t_run_split node "$EXTRACTOR" --rollup "$SCRATCH/compacted-arr-407.jsonl" </dev/null
	[ "$S_STATUS" = 3 ] && pass "a modelUsage that is not an object is refused (exit 3)" ||
		fail "an array modelUsage: status $S_STATUS, '$S_OUT', '$S_ERR'"
	t_run_split sh -c 'printf "not json\n" | node "$1" --rollup "$2"' rollup-case "$EXTRACTOR" "$CFIX"
	[ "$S_STATUS" = 3 ] && pass "a recorded event that is not JSON is refused (exit 3)" ||
		fail "a non-JSON recorded line: status $S_STATUS, '$S_OUT'"
	# H-2: a rollup key an event cannot record unambiguously is refused, never a shifted row.
	sed '$s/"modelUsage":{/"modelUsage":{"bad model":{"inputTokens":900,"outputTokens":10,"cacheReadInputTokens":0,"cacheCreationInputTokens":0},/' \
		"$CFIX" >"$SCRATCH/compacted-space-407.jsonl"
	t_run_split node "$EXTRACTOR" --rollup "$SCRATCH/compacted-space-407.jsonl" </dev/null
	[ "$S_STATUS" = 3 ] && [ "$S_OUT" = "$RMODEL 48 291 17267 104166 5 $CLAST" ] &&
		pass "a rollup key with whitespace is refused (exit 3), never a row with shifted columns" ||
		fail "a rollup key with a space: status $S_STATUS, '$S_OUT'"
	# M-1: an unreadable subagents directory or stdin is a refusal, never "nothing there".
	cp "$CFIX" "$SCRATCH/compacted-notdir-407.jsonl"
	: >"$SCRATCH/compacted-notdir-407"
	t_run_split node "$EXTRACTOR" --rollup "$SCRATCH/compacted-notdir-407.jsonl" </dev/null
	[ "$S_STATUS" = 3 ] && pass "a subagents path that cannot be listed is refused (exit 3)" ||
		fail "an unlistable subagents path: status $S_STATUS, '$S_OUT'"
	t_run_split node "$EXTRACTOR" --rollup "$CFIX" <"$SCRATCH"
	[ "$S_STATUS" = 3 ] && pass "a stdin that cannot be read is refused (exit 3), not read as no gap recorded" ||
		fail "an unreadable stdin: status $S_STATUS, '$S_OUT'"
else
	echo "  skip  node is not on PATH — the rollup-gap legs need the extractor"
fi

# ---------------------------------------------------------------------------
banner "39. A multi-model session end killed partway loses nothing: one anchor per model (#408)"
# ---------------------------------------------------------------------------
# Ticket #408 (a known gap of 2026-10-01, origin #307 L-1). The session-end hook
# writes one session.usage event per model. Until this ticket every one of them
# carried the SAME resume anchor — the last message of the whole read — so an
# end killed after the first model's event left the trace saying "read up to
# here" for a model whose event was never written, and the next end started
# after messages nobody recorded. Now each model's event carries that model's
# own last message, and the next end resumes each model from the trace's last
# anchor FOR THAT MODEL; a model with no anchor is read from the start.
#
# The kill is simulated by cutting the trace after the end's first usage event:
# exactly what a SIGKILL between two emits leaves, and deterministic. The
# transcript is synthetic — two models, one message each per run, distinct
# counts — so a message counted twice or not at all moves a total visibly.
S408=c0ffee00-0408-4000-8000-000000000408
MA=claude-alpha-408
MB=claude-beta-408

# asst408 <id> <model> <in> <out> <cache w> <cache r> — one assistant line.
asst408() {
	printf '{"type":"assistant","requestId":"req_%s","message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"output_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}}}\n' \
		"$1" "$1" "$2" "$3" "$4" "$5" "$6"
}

# cut_after_first_usage — the trace as a kill after this end's first usage
# event leaves it: every line after that event, the session.end included, gone.
# <n> is how many usage events of this session the trace held before the end.
cut_after_first_usage() {
	for _f in "$TDIR"/events/*.jsonl; do
		awk -v n="$1" -v s="\"subject\":\"session:$S408\"" '
			index($0, "\"kind\":\"session.usage\"") && index($0, s) { u += 1 }
			{ print } u > n { exit }' "$_f" >"$_f.cut" && mv "$_f.cut" "$_f"
	done
}

usage408() { ev_of session.usage | grep -F "\"subject\":\"session:$S408\"" || :; }

{
	asst408 msg_a1 "$MA" 1 10 100 1000
	asst408 msg_b1 "$MB" 4 40 400 4000
} >"$SCRATCH/run1-408.jsonl"
{
	cat "$SCRATCH/run1-408.jsonl"
	asst408 msg_a2 "$MA" 2 20 200 2000
	asst408 msg_b2 "$MB" 8 80 800 8000
} >"$SCRATCH/run2-408.jsonl"
set_key transcript_path "$SCRATCH/t-408.jsonl" <"$FIX/session-end.payload.json" |
	set_key session_id "$S408" >"$SCRATCH/end-408.json"

if [ "$HAVE_NODE" = 1 ]; then
	# THE EXTRACTOR: each row's last id is its own model's last message.
	t_run_split node "$EXTRACTOR" "$SCRATCH/run2-408.jsonl"
	[ "$S_STATUS" = 0 ] && [ "$S_OUT" = "$MA 3 30 300 3000 2 msg_a2
$MB 12 120 1200 12000 2 msg_b2" ] &&
		pass "the extractor's last-id column is per model: msg_a2 for alpha, msg_b2 for beta" ||
		fail "a two-model read printed '$S_OUT' (status $S_STATUS)"

	# --resume: the anchors come from the recorded events on stdin, per model.
	printf '%s\n' \
		'{"kind":"session.usage","model":"'"$MA"'","tok_in":1,"data":{"msgs":"1","last_msg":"msg_a1"}}' \
		>"$SCRATCH/rec-a-408.jsonl"
	t_run_split sh -c 'node "$1" --resume "$2" <"$3"' resume-case "$EXTRACTOR" "$SCRATCH/run2-408.jsonl" "$SCRATCH/rec-a-408.jsonl"
	# The rows are compared as a set: their order is not a contract (L-4,
	# review of PR #447).
	[ "$S_STATUS" = 0 ] && [ "$(printf '%s\n' "$S_OUT" | sort)" = "$MA 2 20 200 2000 1 msg_a2
$MB 12 120 1200 12000 2 msg_b2" ] &&
		pass "--resume reads alpha after its anchor and beta, anchorless, from the start" ||
		fail "--resume with alpha's anchor only printed '$S_OUT' (status $S_STATUS: $S_ERR)"
	t_run_split sh -c 'node "$1" --resume "$2" </dev/null' resume-case "$EXTRACTOR" "$SCRATCH/run2-408.jsonl"
	[ "$S_STATUS" = 0 ] && [ "$S_OUT" = "$MA 3 30 300 3000 2 msg_a2
$MB 12 120 1200 12000 2 msg_b2" ] &&
		pass "--resume with nothing recorded is the whole file" ||
		fail "--resume with an empty stdin printed '$S_OUT' (status $S_STATUS)"
	printf '%s\n' '{"kind":"session.usage","model":"'"$MB"'","data":{"msgs":"1","last_msg":"msg_gone"}}' \
		>"$SCRATCH/rec-gone-408.jsonl"
	t_run_split sh -c 'node "$1" --resume "$2" <"$3"' resume-case "$EXTRACTOR" "$SCRATCH/run2-408.jsonl" "$SCRATCH/rec-gone-408.jsonl"
	[ "$S_STATUS" = 2 ] && [ -z "$S_OUT" ] && case $S_ERR in *msg_gone*) true ;; *) false ;; esac &&
		pass "a model's anchor the transcript does not hold is drift: exit 2, no row, the anchor named" ||
		fail "a lost per-model anchor: status $S_STATUS, '$S_OUT', '$S_ERR'"
	# Under --resume the recorded events ARE the anchors: a line that is not
	# JSON, or no stdin to read, is exit 2 — never "nothing recorded", which
	# would be the whole-file read and the double count.
	t_run_split sh -c 'printf "not json\n" | node "$1" --resume "$2"' resume-case "$EXTRACTOR" "$SCRATCH/run2-408.jsonl"
	[ "$S_STATUS" = 2 ] && [ -z "$S_OUT" ] &&
		pass "a recorded line that is not JSON is exit 2 under --resume, no row" ||
		fail "a non-JSON recorded line under --resume: status $S_STATUS, '$S_OUT'"
	t_run_split node "$EXTRACTOR" --resume "$SCRATCH/run2-408.jsonl" <"$SCRATCH"
	[ "$S_STATUS" = 2 ] && [ -z "$S_OUT" ] &&
		pass "a stdin that cannot be read is exit 2 under --resume, no row" ||
		fail "an unreadable stdin under --resume: status $S_STATUS, '$S_OUT'"
	# M-1, review of PR #447: hook_tokens --after WITHOUT --resume is still the
	# one anchor for every model, never silently a whole-file read.
	new_trace
	t_run_split env TRACE_DIR="$TDIR" sh -c '. "$0"; hook_tokens "$1" agent.stop --after msg_a1 subject=agent:m1-408' \
		"$HOOKS/hook.lib.sh" "$SCRATCH/run2-408.jsonl"
	[ "$S_STATUS" = 0 ] && [ "$(sum_tok tok_in agent.stop)" = 14 ] &&
		pass "hook_tokens --after alone still anchors every model: b1, a2, b2 counted (14), a1 not" ||
		fail "hook_tokens --after alone counted tok_in $(sum_tok tok_in agent.stop): $(ev_of agent.stop)"
	t_run_split node "$EXTRACTOR" --resume --after msg_a1 "$SCRATCH/run2-408.jsonl" </dev/null
	[ "$S_STATUS" = 2 ] && pass "--resume and --after together is a usage error: two answers to one question" ||
		fail "--resume with --after: status $S_STATUS, '$S_OUT'"

	# THE KILL. End 1 over run 1, cut after its first usage event; then a full
	# end over run 2. Every message counted exactly once, per model.
	new_trace
	cp "$SCRATCH/run1-408.jsonl" "$SCRATCH/t-408.jsonl"
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-408.json"
	[ "$S_STATUS" = 0 ] && pass "the two-model first end exits 0" || fail "the first end exited $S_STATUS: $S_ERR"
	UA=$(usage408 | grep -F "\"model\":\"$MA\"")
	UB=$(usage408 | grep -F "\"model\":\"$MB\"")
	[ "$(data_of "$UA" last_msg)" = msg_a1 ] && [ "$(data_of "$UB" last_msg)" = msg_b1 ] &&
		pass "each model's event carries its own anchor: msg_a1 on alpha, msg_b1 on beta" ||
		fail "the per-model anchors: alpha '$(data_of "$UA" last_msg)', beta '$(data_of "$UB" last_msg)'"
	cut_after_first_usage 0
	[ "$(usage408 | grep -c .)" = 1 ] && [ -z "$(ev_of session.end)" ] &&
		pass "the kill leaves one usage event and no session.end" ||
		fail "the cut trace holds: $(events)"
	cp "$SCRATCH/run2-408.jsonl" "$SCRATCH/t-408.jsonl"
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-408.json"
	[ "$S_STATUS" = 0 ] && pass "the full end after the kill exits 0" || fail "exited $S_STATUS: $S_ERR"
	[ "$(model_row "$MA")" = "3 30 300 3000" ] && [ "$(model_row "$MB")" = "12 120 1200 12000" ] &&
		pass "summary --by model: alpha 3/30/300/3000, beta 12/120/1200/12000 — every message once" ||
		fail "after the kill alpha totals '$(model_row "$MA")', beta '$(model_row "$MB")'"
	[ -z "$(usage408 | grep -F '"outcome":"fail"')" ] &&
		pass "and no usage event of the two ends is a failure" ||
		fail "a failure was recorded: $(usage408 | grep -F '"outcome":"fail"')"

	# A THIRD END WITH NOTHING NEW: one event, no tokens, the totals unmoved.
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-408.json"
	N3=$(usage408 | sed -n '$p')
	[ "$S_STATUS" = 0 ] && [ -z "$(num "$N3" tok_in)" ] && [ "$(str "$N3" outcome)" != fail ] &&
		[ "$(data_of "$N3" msgs)" = 0 ] &&
		[ "$(model_row "$MA")" = "3 30 300 3000" ] && [ "$(model_row "$MB")" = "12 120 1200 12000" ] &&
		pass "a third end with nothing new leaves one tokenless event and moves no total" ||
		fail "the nothing-new end: '$N3', alpha '$(model_row "$MA")', beta '$(model_row "$MB")'"
	# AND IT ANCHORS NOBODY (L-3, review of PR #447): it names no model, so a
	# fourth end with one new message per model counts exactly those two.
	{
		asst408 msg_a3 "$MA" 16 160 1600 16000
		asst408 msg_b3 "$MB" 32 320 3200 32000
	} >>"$SCRATCH/t-408.jsonl"
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-408.json"
	[ "$S_STATUS" = 0 ] && [ "$(model_row "$MA")" = "19 190 1900 19000" ] &&
		[ "$(model_row "$MB")" = "44 440 4400 44000" ] &&
		pass "a fourth end after it counts each model's one new message, no more" ||
		fail "the fourth end: alpha '$(model_row "$MA")', beta '$(model_row "$MB")'"

	# A TRACE THE OLD HOOK WROTE: both events carried the whole read's last id,
	# and the kill took beta's. Alpha's anchor is a POSITION in the file, so it
	# still counts alpha's messages after it; beta has none and starts over.
	new_trace
	cp "$SCRATCH/run2-408.jsonl" "$SCRATCH/t-408.jsonl"
	env TRACE_DIR="$TDIR" TRACE_QUIET=1 sh "$TRACE" emit kind=session.usage subject="session:$S408" \
		session="$S408" model="$MA" tok_in=1 tok_out=10 tok_cache_w=100 tok_cache_r=1000 \
		data.msgs=1 data.last_msg=msg_b1
	t_run_split env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-408.json"
	[ "$S_STATUS" = 0 ] && [ "$(model_row "$MA")" = "3 30 300 3000" ] && [ "$(model_row "$MB")" = "12 120 1200 12000" ] &&
		pass "a trace the old hook wrote and a kill cut recovers too: every message once" ||
		fail "from an old-style anchor alpha totals '$(model_row "$MA")', beta '$(model_row "$MB")'"

	# A SINGLE-MODEL SESSION IS UNCHANGED: section 26's two ends, again.
	new_trace
	head -25 "$RFIX" >"$SCRATCH/resumed-307.jsonl"
	env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-resumed-307.json" >/dev/null 2>&1
	cp "$RFIX" "$SCRATCH/resumed-307.jsonl"
	env TRACE_DIR="$TDIR" sh "$HOOKS/session-end.sh" <"$SCRATCH/end-resumed-307.json" >/dev/null 2>&1
	[ "$(ev_of session.usage | sed -n 's/.*"last_msg":"\([^"]*\)".*/\1/p' | paste -sd' ' -)" = "$RMSG1 $RMSG2" ] &&
		[ "$(model_row "$RMODEL")" = "$R34" ] &&
		pass "a single-model session: the same two anchors and the same total ($R34)" ||
		fail "the single-model session: $(ev_of session.usage)"
else
	echo "  skip  node is not on PATH — the per-model anchor legs need the extractor"
fi

# ---------------------------------------------------------------------------
banner "40. A denied tool call is visible: a pending marker swept at session end (#409)"
# ---------------------------------------------------------------------------
# Ticket #409 (a known gap of 2026-10-01, origin #252). A call the operator
# denies fires PreToolUse and nothing after it, so tool-post.sh never sees it.
# The pre-tool hook now writes a pending marker in the adapter's own
# claude-code/ directory, keyed by session and tool-use id; the post-tool hook
# removes it; the session-end hook sweeps what is left into one
# `tool.use outcome=denied` each, the tool name and the input head on it.
# Behind TRACE_TOOLS, the switch tool-post.sh reads: a marker no post hook
# would ever remove would read every call as denied.

# pre_of <session> <tool_use_id> <command> — the PreToolUse hook on a compact
# payload, the live shape, with tool capture on.
pre_of() {
	printf '{"session_id":"%s","transcript_path":"%s","cwd":"/tmp/spike-proj","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_use_id":"%s"}' \
		"$1" "$SCRATCH/main.jsonl" "$3" "$2" >"$SCRATCH/pre-409.json"
	env TRACE_DIR="$TDIR" TRACE_TOOLS=1 sh "$HOOKS/tool-pre.sh" <"$SCRATCH/pre-409.json"
}

# post_of <session> <tool_use_id> <command> — the PostToolUse hook for that call.
post_of() {
	printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"stdout":"hi"},"tool_use_id":"%s"}' \
		"$1" "$3" "$2" >"$SCRATCH/post-409.json"
	env TRACE_DIR="$TDIR" TRACE_TOOLS=1 sh "$HOOKS/tool-post.sh" <"$SCRATCH/post-409.json" >/dev/null 2>&1
}

# denied_of <session> — that session's tool.use events with outcome=denied.
denied_of() { ev_of tool.use | grep -F "\"subject\":\"session:$1\"" | grep -F '"outcome":"denied"' || :; }

# markers — every pending marker under the trace directory.
markers() { find "$TDIR" -path '*.pending*' -type f 2>/dev/null; }

if [ -f "$HOOKS/tool-pre.sh" ]; then
	assert_status 0 "adapters/claude-code/hooks/tool-pre.sh parses under sh -n" -- sh -n "$HOOKS/tool-pre.sh"
else
	fail "adapters/claude-code/hooks/tool-pre.sh does not exist"
fi

if [ "$HAVE_NODE" = 1 ]; then
	S409=sess-409-a
	new_trace
	# THE DENIAL: a pre-tool event with no post-tool event, then the end.
	t_run_split pre_of "$S409" toolu_409_denied 'rm -rf build'
	[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] &&
		pass "the pre-tool hook exits 0 and says nothing on stdout" ||
		fail "tool-pre.sh: exit $S_STATUS, stdout '$S_OUT', stderr '$S_ERR'"
	[ -z "$(ev_of tool.use)" ] && pass "and writes no event of its own — the marker is not a record yet" ||
		fail "the pre-tool hook wrote an event: $(ev_of tool.use)"
	M=$(markers)
	[ "$(printf '%s\n' "$M" | grep -c .)" = 1 ] &&
		case $M in "$TDIR/claude-code/$S409.pending/toolu_409_denied") true ;; *) false ;; esac &&
		pass "one marker, in the adapter's claude-code/ directory, keyed by session and tool-use id" ||
		fail "expected claude-code/$S409.pending/toolu_409_denied, found: $M"
	case $(ls -l "$M" 2>/dev/null) in -rw-------*) pass "and owner-only: it holds the command's head" ;;
	*) fail "the marker is not mode 600: $(ls -l "$M" 2>/dev/null)" ;; esac
	end_of "$S409"
	D=$(denied_of "$S409")
	[ "$(printf '%s\n' "$D" | grep -c .)" = 1 ] &&
		pass "a pre-tool event with no post-tool event, then a session end: one tool.use outcome=denied" ||
		fail "expected one denied tool.use for $S409, got: $D"
	[ "$(data_of "$D" tool)" = Bash ] && [ "$(data_of "$D" tool_use_id)" = toolu_409_denied ] &&
		pass "naming the tool and the call's id" || fail "the denial lacks tool or id: $D"
	# Matched on the line itself: the head is JSON inside a JSON string, so
	# its quotes are escaped and data_of's plain-string reader stops at one.
	case $D in *'"input_head":"{\"command\":\"rm -rf build\"}"'*) pass "and carrying the input head the marker kept" ;;
	*) fail "the denial does not carry the input head: $D" ;; esac
	[ "$(str "$D" session)" = "$S409" ] && [ "$(str "$D" harness)" = claude-code ] &&
		pass "filed under the session, from the claude-code agent harness" || fail "the denial's session or harness is wrong: $D"
	# Inside the session: the denial is written before session.end.
	_order=$(events | grep -F "session:$S409" | sed -n 's/.*"kind":"\([a-z.]*\)".*/\1/p' | tr '\n' ' ')
	case $_order in *tool.use*session.end*) pass "and written before the session.end it belongs to" ;;
	*) fail "the order of $S409's events is: $_order" ;; esac
	[ -z "$(markers)" ] && pass "the swept marker is gone" || fail "a marker outlived the sweep: $(markers)"
	t_run_split env TRACE_DIR="$TDIR" sh "$TRACE" show "session:$S409" --kind tool.use
	case $S_OUT in *denied*toolu_409_denied*) pass "show session:<id> --kind tool.use prints the denial — the ticket's demo" ;;
	*) fail "show did not print the denial: $S_OUT" ;; esac

	# A MATCHED PAIR: the post-tool hook removes the marker, and the end
	# sweeps nothing.
	S409B=sess-409-b
	pre_of "$S409B" toolu_409_ok 'echo hi' >/dev/null 2>&1
	post_of "$S409B" toolu_409_ok 'echo hi'
	[ -z "$(markers)" ] && pass "the post-tool hook removes the call's marker" || fail "a matched call left a marker: $(markers)"
	end_of "$S409B"
	[ -z "$(denied_of "$S409B")" ] && pass "a matched pre and post, then a session end: no denied event" ||
		fail "a call that completed was swept as denied: $(denied_of "$S409B")"
	ev_of tool.use | grep -F "session:$S409B" | grep -q '"outcome":"ok"' &&
		pass "and the call's own ok event stands" || fail "the matched call has no ok event: $(ev_of tool.use)"

	# NO END YET: the marker stays on disk, and the next end of the session
	# sweeps it — once.
	S409C=sess-409-c
	pre_of "$S409C" toolu_409_late 'git push --force' >/dev/null 2>&1
	pre_of "$S409B" toolu_409_other 'make' >/dev/null 2>&1
	[ "$(markers | grep -c "$S409C.pending/toolu_409_late")" = 1 ] &&
		pass "a marker with no session end stays on disk" || fail "the marker is not on disk: $(markers)"
	end_of "$S409C"
	[ "$(denied_of "$S409C" | grep -c .)" = 1 ] && pass "and the next end sweeps it" ||
		fail "the next end swept: $(denied_of "$S409C")"
	end_of "$S409C"
	[ "$(denied_of "$S409C" | grep -c .)" = 1 ] && pass "a second end of the same session sweeps nothing again" ||
		fail "a second end recorded the denial twice: $(denied_of "$S409C")"
	[ "$(markers | grep -c "$S409B.pending/toolu_409_other")" = 1 ] &&
		pass "and another session's marker is left alone — its call may still be running" ||
		fail "a session end swept another session's marker: $(markers)"

	# A REFUSED ID is never a path: a hostile or traversing session or
	# tool-use id writes no marker anywhere.
	new_trace
	pre_of 'abc; touch PWNED-409' toolu_409_x 'ls' >/dev/null 2>&1
	pre_of sess-409-d '../../escape-409' 'ls' >/dev/null 2>&1
	pre_of sess-409-d '..' 'ls' >/dev/null 2>&1
	pre_of '..' toolu_409_y 'ls' >/dev/null 2>&1
	LEFT=$(
		find "$TDIR" -path '*.pending*' 2>/dev/null
		find "$SCRATCH" "$(dirname "$SCRATCH")" -maxdepth 1 \( -name 'escape-409*' -o -name 'PWNED-409*' \) 2>/dev/null
	)
	[ -z "$LEFT" ] && pass "a hostile or traversing session or tool-use id leaves no marker anywhere" ||
		fail "a refused id left files: $LEFT"

	# THE SWITCH: tool capture off, or tracing off — no marker, exit 0, silent.
	new_trace
	t_run_split env TRACE_DIR="$TDIR" TRACE_TOOLS= sh "$HOOKS/tool-pre.sh" <"$SCRATCH/pre-409.json"
	[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && [ -z "$(markers)" ] &&
		pass "with tool capture off the pre-tool hook writes no marker and exits 0" ||
		fail "TRACE_TOOLS off: exit $S_STATUS, stdout '$S_OUT', markers $(markers)"
	t_run_split env -u TRACE_DIR TRACE_TOOLS=1 TRACE_CONFIG="$KIT/scripts/trace.config.sh" sh "$HOOKS/tool-pre.sh" <"$SCRATCH/pre-409.json"
	[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && [ -z "$S_ERR" ] &&
		pass "with tracing off it exits 0 and says nothing" ||
		fail "tracing off: exit $S_STATUS, stdout '$S_OUT', stderr '$S_ERR'"

	# REVIEW OF PR #446. H-1: a post payload the reader refuses still drops
	# the call's marker — the call returned, so it was not denied.
	new_trace
	pre_of sess-409-e toolu_409_drift 'echo hi' >/dev/null 2>&1
	printf '{"session_id":"sess-409-e","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"echo hi"},"tool_use_id":"toolu_409_drift"}' |
		env TRACE_DIR="$TDIR" TRACE_TOOLS=1 sh "$HOOKS/tool-post.sh" >/dev/null 2>&1
	[ -z "$(markers)" ] && ev_of tool.use | grep -q '"outcome":"fail"' &&
		pass "a post payload the reader refuses records its fail and still drops the marker (review of PR #446, H-1)" ||
		fail "after a refused post payload: markers '$(markers)', events $(ev_of tool.use)"
	end_of sess-409-e
	[ -z "$(denied_of sess-409-e)" ] && pass "and the session end records no denial for it" ||
		fail "a call whose post payload drifted was swept as denied: $(denied_of sess-409-e)"

	# M-1: a sweep that died after taking the directory aside left
	# <sid>.pending.<pid>; the next end of that session sweeps it too.
	new_trace
	mkdir -p "$TDIR/claude-code/sess-409-f.pending.4242"
	printf 'Bash\n{"command":"rm -rf x"}\n' >"$TDIR/claude-code/sess-409-f.pending.4242/toolu_409_orphan"
	mkdir -p "$TDIR/claude-code/sess-409-g.pending.4243"
	printf 'Bash\n{}\n' >"$TDIR/claude-code/sess-409-g.pending.4243/toolu_409_notmine"
	end_of sess-409-f
	[ "$(denied_of sess-409-f | grep -c toolu_409_orphan)" = 1 ] &&
		pass "a directory an interrupted sweep took aside is swept by the session's next end (review of PR #446, M-1)" ||
		fail "the orphaned taken-aside directory was not swept: $(denied_of sess-409-f)"
	[ ! -e "$TDIR/claude-code/sess-409-f.pending.4242" ] && [ -e "$TDIR/claude-code/sess-409-g.pending.4243/toolu_409_notmine" ] &&
		pass "and it is removed, while another session's is left alone" ||
		fail "orphans after the end: $(find "$TDIR/claude-code" 2>/dev/null)"

	# L-4: the kill guard refuses a sub-agent's call, the marker hook ran on
	# the same payload, the session ends: the guard's note AND one denial.
	new_trace
	printf '{"session_id":"sess-409-h","hook_event_name":"PreToolUse","agent_type":"general-purpose","tool_name":"Bash","tool_input":{"command":"pkill -f suite"},"tool_use_id":"toolu_409_guard"}' >"$SCRATCH/guard-409.json"
	env TRACE_DIR="$TDIR" sh "$HOOKS/tool-pre-guard.sh" <"$SCRATCH/guard-409.json" >/dev/null 2>&1
	_g409=$?
	env TRACE_DIR="$TDIR" TRACE_TOOLS=1 sh "$HOOKS/tool-pre.sh" <"$SCRATCH/guard-409.json" >/dev/null 2>&1
	end_of sess-409-h
	[ "$_g409" = 2 ] && ev_of note | grep -q 'kill-guard' && [ "$(denied_of sess-409-h | grep -c toolu_409_guard)" = 1 ] &&
		pass "a call the kill guard refused is the guard's note and one swept tool.use denied (review of PR #446, L-4)" ||
		fail "guard exit $_g409; note $(ev_of note); denials $(denied_of sess-409-h)"
else
	echo "  skip  node is not on PATH — the marker needs the payload reader's input head"
fi

# THE WIRING AND THE RECORD.
grep -q 'hooks/tool-pre.sh' "$SETTINGS" && pass "the kit's settings file wires tool-pre.sh" ||
	fail "the kit's settings file does not wire tool-pre.sh"
d=$(tr '\n' ' ' <"$KIT/adapters/claude-code/README.md" | tr -s ' ' | tr '[:upper:]' '[:lower:]')
case $d in *"swept into one \`tool.use\` with \`outcome=denied\`"*) pass "the adapter README records the sweep" ;;
*) fail "the adapter README does not say a leftover marker is swept into one tool.use with outcome=denied" ;; esac

# ---------------------------------------------------------------------------
banner "41. A stop carries the run of the checkout the subagent worked in (#421)"
# ---------------------------------------------------------------------------
# Retro finding H4 (#417): 0 of 28 priced agent.stop events carried an
# implement or review run. The hooks execute from the ROOT checkout, so the
# shared script keyed the run stack on the root's toplevel — while the session
# whose spend it was had run `begin` in a linked worktree, whose stack is keyed
# on the worktree's toplevel. The hook now reads the stack of the checkout the
# payload's cwd names (the process's own cwd when the payload names none),
# provided it is a checkout of the same repository, and the root's otherwise.
#
# Each leg runs the ROOT's copy of the hook, the way the kit's wiring does.

R421="$SCRATCH/run-root-421"
behind_kit "$R421"
git -C "$R421" worktree add -q -b feat/wt-421 "$R421.wt" 2>/dev/null
HOOK421="$R421/${HOOKS#"$KIT"/}/subagent-stop.sh"
new_trace
ROOTRUN=$(cd "$R421" && env TRACE_DIR="$TDIR" sh scripts/trace.sh begin implement 2>/dev/null)
WTOUTER=$(cd "$R421.wt" && env TRACE_DIR="$TDIR" sh scripts/trace.sh begin implement 2>/dev/null)
WTINNER=$(cd "$R421.wt" && env TRACE_DIR="$TDIR" sh scripts/trace.sh begin review-pr 2>/dev/null)
[ -n "$ROOTRUN" ] && [ -n "$WTOUTER" ] && [ -n "$WTINNER" ] &&
	pass "a run is open at the root and two nested runs are open in its linked worktree" ||
	fail "the fixture runs did not open: root '$ROOTRUN', worktree '$WTOUTER' / '$WTINNER'"

# stop_from <cwd or ''> [env assignments…] — the root's hook on the fixture
# payload with its cwd field set to <cwd> (removed when empty), run from the
# kit's own directory. Sets S_* and STOP, the agent.stop this run wrote — and
# fails the leg unless exactly one was added, so no leg can pass on the event
# an earlier leg left behind (M-4, local review of PR #449).
stop_from() {
	_sf_cwd=$1
	shift
	if [ -n "$_sf_cwd" ]; then
		set_key cwd "$_sf_cwd" <"$FIX/subagent-stop.payload.json"
	else
		grep -v '"cwd":' "$FIX/subagent-stop.payload.json"
	fi | set_key agent_transcript_path "$SCRATCH/sub.jsonl" >"$SCRATCH/stop-421.json"
	_sf_before=$(ev_of agent.stop | grep -c '')
	t_run_split env TRACE_DIR="$TDIR" GIT_CEILING_DIRECTORIES="$SCRATCH" "$@" \
		sh "$HOOK421" <"$SCRATCH/stop-421.json"
	_sf_added=$(($(ev_of agent.stop | grep -c '') - _sf_before))
	[ "$_sf_added" = 1 ] ||
		fail "a stop from '$_sf_cwd' wrote $_sf_added agent.stop events, want exactly 1"
	STOP=$(ev_of agent.stop | sed -n '$p')
}

stop_from "$R421.wt"
[ "$S_STATUS" = 0 ] && [ -z "$S_OUT" ] && [ -z "$S_ERR" ] && pass "a stop from the linked worktree exits 0, silent on stdout and stderr" ||
	fail "a stop from the worktree: exit $S_STATUS, stdout '$S_OUT', stderr '$S_ERR'"
[ "$(str "$STOP" run)" = "$WTINNER" ] &&
	pass "it carries the worktree's open run, not the root's" ||
	fail "a stop from the worktree carries run '$(str "$STOP" run)', want $WTINNER (root's is $ROOTRUN)"
[ "$(str "$STOP" parent)" = "$WTOUTER" ] &&
	pass "and that run's parent, the run below it on the worktree's stack" ||
	fail "a stop from the worktree carries parent '$(str "$STOP" parent)', want $WTOUTER"

mkdir -p "$R421.wt/scripts/deeper"
stop_from "$R421.wt/scripts/deeper"
[ "$(str "$STOP" run)" = "$WTINNER" ] &&
	pass "a cwd deep inside the worktree names the same checkout" ||
	fail "a stop from below the worktree's top carries run '$(str "$STOP" run)', want $WTINNER"

stop_from "$R421"
[ "$(str "$STOP" run)" = "$ROOTRUN" ] && [ -z "$(str "$STOP" parent)" ] &&
	pass "a stop from the root carries the root's run" ||
	fail "a stop from the root carries run '$(str "$STOP" run)' parent '$(str "$STOP" parent)', want $ROOTRUN"

mkdir -p "$SCRATCH/nowhere-421"
stop_from "$SCRATCH/nowhere-421"
[ "$(str "$STOP" run)" = "$ROOTRUN" ] &&
	pass "a stop from outside any checkout falls back to the root's run" ||
	fail "a stop from outside a checkout carries run '$(str "$STOP" run)', want $ROOTRUN"

stop_from "$SCRATCH/never-there-421"
[ "$S_STATUS" = 0 ] && [ "$(str "$STOP" run)" = "$ROOTRUN" ] &&
	pass "a cwd that does not exist falls back to the root's run, exit 0" ||
	fail "a missing cwd: exit $S_STATUS, run '$(str "$STOP" run)', want $ROOTRUN"

OTHER421="$SCRATCH/other-repo-421"
mkdir -p "$OTHER421"
git init -q "$OTHER421"
stop_from "$OTHER421"
[ "$(str "$STOP" run)" = "$ROOTRUN" ] &&
	pass "a cwd in an UNRELATED repository is not a checkout of this one: the root's run" ||
	fail "a stop from an unrelated repository carries run '$(str "$STOP" run)', want $ROOTRUN"

# A GIT_DIR / GIT_WORK_TREE pair pinned to another repository — git exports
# them into hooks — answers for nothing here: every lookup scrubs them, and the
# stop still carries the worktree's run (M-3, local review of PR #449).
stop_from "$R421.wt" GIT_DIR="$OTHER421/.git" GIT_WORK_TREE="$OTHER421"
[ "$(str "$STOP" run)" = "$WTINNER" ] && [ "$(str "$STOP" parent)" = "$WTOUTER" ] &&
	pass "a pinned GIT_DIR/GIT_WORK_TREE for another repository does not move the run" ||
	fail "with GIT_DIR pinned elsewhere the stop carries run '$(str "$STOP" run)' parent '$(str "$STOP" parent)', want $WTINNER / $WTOUTER"

# No cwd in the payload: the hook's own working directory answers. The hook is
# run from the worktree in THIS shell, not a subshell, so S_STATUS and S_ERR
# survive to be asserted on (L, review of PR #449).
_here421=$PWD
cd "$R421.wt" || fail "cannot enter the fixture worktree $R421.wt"
stop_from ''
cd "$_here421" || fail "cannot return to $_here421"
[ "$S_STATUS" = 0 ] && [ "$(str "$STOP" run)" = "$WTINNER" ] &&
	pass "a payload with no cwd field: the hook's own working directory names the checkout, exit 0" ||
	fail "with no cwd field, a hook run inside the worktree: exit $S_STATUS, run '$(str "$STOP" run)', want $WTINNER"

# The environment still beats every stack, as it does for the shared script.
stop_from "$R421.wt" TRACE_RUN=run-from-env-421
[ "$(str "$STOP" run)" = run-from-env-421 ] && [ -z "$(str "$STOP" parent)" ] &&
	pass "a TRACE_RUN in the environment still wins over the worktree's stack" ||
	fail "with TRACE_RUN set the stop carries run '$(str "$STOP" run)' parent '$(str "$STOP" parent)'"

# A TRACE_PARENT alone is kept, and the run still comes from the worktree's
# stack: the parent is the caller's to say, the run is not (M, review of PR #449).
stop_from "$R421.wt" TRACE_PARENT=parent-from-env-421
[ "$S_STATUS" = 0 ] && [ "$(str "$STOP" run)" = "$WTINNER" ] && [ "$(str "$STOP" parent)" = parent-from-env-421 ] &&
	pass "a TRACE_PARENT with no TRACE_RUN: the worktree's run, the environment's parent" ||
	fail "with only TRACE_PARENT set the stop carries run '$(str "$STOP" run)' parent '$(str "$STOP" parent)', want $WTINNER / parent-from-env-421"

# A stack that EXISTS and cannot be read is said, on stderr, and the stop
# carries no run — never the root's (H-1, review of PR #449). Root reads a
# mode-000 file, so the leg cannot be driven there and says so.
if [ "$(id -u)" = 0 ]; then
	echo "  skip  running as root — a mode-000 file is readable, so the unreadable-stack leg cannot be driven"
else
	STACK421=$(grep -lF "$WTINNER" "$TDIR"/current/*.runs 2>/dev/null)
	[ -f "$STACK421" ] && pass "the worktree's run stack is where the leg looks for it" ||
		fail "no run stack at $STACK421"
	chmod 000 "$STACK421"
	stop_from "$R421.wt"
	chmod 600 "$STACK421"
	[ "$S_STATUS" = 0 ] && [ -n "$STOP" ] && [ -z "$(str "$STOP" run)" ] && [ -z "$(str "$STOP" parent)" ] &&
		pass "an unreadable worktree stack: exit 0, the stop carries no run and no parent, not the root's" ||
		fail "an unreadable worktree stack: exit $S_STATUS, run '$(str "$STOP" run)' parent '$(str "$STOP" parent)', event '$STOP'"
	case $S_ERR in *"$STACK421 exists and cannot be read"*) pass "and stderr names the stack that could not be read" ;;
	*) fail "an unreadable worktree stack says nothing on stderr naming it: '$S_ERR'" ;; esac
fi

# A worktree with NO run open says so: it never borrows the root's.
(cd "$R421.wt" && env TRACE_DIR="$TDIR" sh scripts/trace.sh end >/dev/null 2>&1 &&
	env TRACE_DIR="$TDIR" sh scripts/trace.sh end >/dev/null 2>&1)
stop_from "$R421.wt"
[ "$S_STATUS" = 0 ] && [ -z "$(str "$STOP" run)" ] && [ -n "$STOP" ] &&
	pass "a worktree with no open run: the stop carries no run, not the root's" ||
	fail "a worktree with no open run: exit $S_STATUS, run '$(str "$STOP" run)', event '$STOP'"

# THE RECORD: the adapter README's row for the hook says all of it — the
# parent from the same stack, and an idle checkout's stop carrying no run
# (M, review of PR #449).
ROW421=$(grep -F '| `hooks/subagent-stop.sh` |' "$KIT/adapters/claude-code/README.md")
case $ROW421 in *"parent from the same checkout's stack"*) pass "the README row says the parent comes from the same checkout's stack" ;;
*) fail "the README row for subagent-stop.sh does not say the parent comes from the same checkout's stack" ;; esac
case $ROW421 in *"a checkout with no run open makes a stop that carries no run, never the root's"*) pass "the README row says an idle checkout's stop carries no run" ;;
*) fail "the README row for subagent-stop.sh does not say a checkout with no run open makes a stop that carries no run" ;; esac
case $ROW421 in *"the hook's own working directory when the payload names no \`cwd\`"*) pass "the README row names the no-cwd fallback" ;;
*) fail "the README row for subagent-stop.sh does not name the hook's own working directory as the no-cwd fallback" ;; esac
case $ROW421 in *"a \`TRACE_RUN\` already in the environment wins, with its parent; a \`TRACE_PARENT\` alone is kept"*) pass "the README row names the environment's precedence" ;;
*) fail "the README row for subagent-stop.sh does not say a TRACE_RUN in the environment wins and a TRACE_PARENT alone is kept" ;; esac

t_done "trace hooks"
