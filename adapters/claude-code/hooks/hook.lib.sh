#!/bin/sh
# hook.lib.sh — what the three trace hooks beside this file share.
#
# WHAT THESE HOOKS ARE. One agent harness can tell the decision trace three
# things nothing else knows: that a session began, what it spent, and that a
# subagent finished. Those are the agent harness's own events, so they live
# here in its adapter rather than in `scripts/trace.sh` (ADR-0008 clause 8:
# "the agent harness is the adapter's business"). Everything portable — the
# line format, the closed kind vocabulary, where the trace directory is — stays
# in the shared script, which these hooks call and never reimplement.
#
# DORMANT UNTIL SOMETHING NAMES THEM. Nothing under `adapters/` is on an
# execution path; a hook runs only once a settings file wires it (see
# ../README.md, "Wiring the session hooks"). In THIS kit that file is
# `.claude/settings.json`, which is kit-authoring only and never shipped. In
# your project it is yours to write, and until you write it these five files
# are reference material you can read.
#
# THE THREE RULES A HOOK HERE KEEPS, and why each one is not negotiable:
#
#   1. EXIT 0, ALWAYS. A hook is on the agent harness's critical path. A
#      non-zero exit is a signal to the agent harness about the SESSION, and
#      observability that can fail a session is worse than none (PRD #237,
#      story 15; ADR-0008 clause 4). Every call into the trace ends in `|| :`
#      and every hook ends in `exit 0`.
#   2. SILENT ON STDOUT. What a hook prints on stdout can reach the agent
#      harness's own parser. The trace's answers go to a file; nothing here
#      has anything to say. STDERR is a different stream and is deliberately
#      loud — ADR-0008 clause 4 wants a trace error visible, and the operator
#      is the reader.
#   3. TRACE_QUIET=1. An unconfigured trace prints one note per process, which
#      is the right nudge for an operator typing a command and pure noise on
#      every session start of a project that has decided not to trace.
#
# Sourced, not executed: `. "$(dirname "$0")/hook.lib.sh"` at the top of each
# hook. It defines functions, exports the trace's quiet variable and resolves
# two paths; it emits nothing of its own.

TRACE_QUIET=1
export TRACE_QUIET

# WHERE THINGS ARE, from this file's own location and never from the caller's
# cwd. A hook is invoked by the agent harness with a cwd of its own choosing,
# and `sh scripts/trace.sh` has to mean the script in THIS repository.
hook_here=$(cd "$(dirname "$0")" && pwd -P)
hook_repo=$(cd "$hook_here/../../.." && pwd -P)

# hook_trace <args…> — the plain shared script, run FROM THE REPO ROOT so that a
# relative TRACE_CONFIG (which is how this kit reaches its own never-shipped
# policy file) resolves against the repository rather than against wherever the
# agent harness happened to stand. `|| :` is rule 1: a trace error is loud on
# stderr and never in a status a caller acts on.
hook_trace() {
	(cd "$hook_repo" && sh scripts/trace.sh "$@") || :
}

# --- the payload ------------------------------------------------------------
# A hook is handed one JSON object on stdin. It arrives COMPACT from this agent
# harness — the whole object on one line, no whitespace between tokens; the
# pretty-printed payloads under tests/fixtures/claude-code/ are the redaction's
# reformatting, not the live shape (#309). The fields these hooks read are ids
# and paths, so a whole JSON parser is not needed — and must not be needed,
# because the extractor is the one part of this adapter with a runtime and
# `node missing` has to stay a recorded reason rather than a dead hook.

hook_json=

# hook_read — the payload, into a shell variable. No temporary file, so there
# is nothing to clean up on a path that must never fail.
hook_read() { hook_json=$(cat 2>/dev/null) || hook_json=; }

# hook_field <key> — the payload's top-level string value for <key>, or empty.
#
# THE KEY IS MATCHED WITH ITS QUOTES and anchored on the character before the
# opening one — a `{`, a `,` or whitespace — because `transcript_path` is the
# PARENT session's file and `agent_transcript_path` is the subagent's own, and
# a pattern that matched the bare name would read the tail of the second and
# silently open the wrong transcript (the #246 spike's finding Q2). A key a
# model quoted inside a string value never answers either: JSON escapes that
# quote, so the text is `\"key\"`, and no `{`, `,` or space precedes it.
#
# WHICH MATCH WINS, precisely, because the loose answer was wrong: sed's `.*`
# is greedy, so within ONE LINE the last occurrence wins. The live payload is
# one line, so on it the reader returns the LAST occurrence of the key anywhere
# in the object, and a key nested inside another object reads as top-level. It
# is right today because every key these hooks read occurs once, at top level
# — `tests/trace-hooks.test.sh`, "The field reader on a compact payload",
# drives it on that compact shape. A payload that nested one of these keys
# after its top-level twin would answer with the nested value; that is the day
# to reach for a parser (L-1, review of PR #291). On a pretty-printed payload, one key per line, the first matching
# line wins instead — which is all the checked-in fixtures exercise.
hook_field() {
	printf '%s\n' "$hook_json" |
		sed -n 's/.*[{,[:space:]]"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
		sed -n '1p'
}

# hook_id_ok <value> — is this an identifier this adapter may use?
#
# TWO REQUIREMENTS, and the second is why the class is this narrow. It has to
# be QUERYABLE — `scripts/trace.sh` matches a subject exactly, so a value with
# a space or a quote is one `show` could never find. And it has to be SAFE TO
# WRITE INTO A FILE THE AGENT HARNESS SOURCES AS SHELL: session-start.sh
# appends an export to the file `CLAUDE_ENV_FILE` names, and that file is read
# back into every later tool call of the session. An id carrying `;` or `$` is
# then arbitrary code in the operator's next command — reproduced against the
# first draft of this adapter, which wrote the value after the trace had
# already refused it as a malformed subject (H-1, review of PR #291).
#
# So: letters, digits, dot, dash, underscore, and nothing else. That is what a
# session id and an agent id are, and a payload is DATA — the root manual's
# trust boundary applied at the one place in this adapter where it is
# load-bearing. A value outside the class is refused, loudly, and the hook goes
# on to exit 0 like everything else here.
hook_id_ok() {
	case ${1:-} in
	'' | *[!A-Za-z0-9._-]*) return 1 ;;
	esac
	return 0
}

# hook_expand <path> — a leading `~` is the home directory of whoever ran the
# agent harness. The live capture's paths are absolute, and the `~` in the
# checked-in fixtures is the REDACTION's substitution rather than anything the
# agent harness emitted — so this branch guards a shape nothing here has been
# seen to produce, and `tests/trace-hooks.test.sh` section 16 is the case that
# keeps it honest rather than untested.
hook_expand() {
	case $1 in
	'~') printf '%s' "${HOME:-~}" ;;
	'~/'*) printf '%s/%s' "${HOME:-~}" "${1#\~/}" ;;
	*) printf '%s' "$1" ;;
	esac
}

# --- the session pointer ----------------------------------------------------

# hook_pointer — the per-toplevel pointer file `scripts/trace.sh` reads a
# session id back from, or nothing (status 1) when tracing is off or git cannot
# hash the path.
#
# THIS IS A DELIBERATE COUPLING, and it is the one thing in this file worth
# reviewing twice. The shared script derives that path from git's hash of the
# toplevel it itself lives in; nothing exposes it, so a writer has to derive it
# the same way. The check that the two derivations agree is not a comparison of
# strings — it is `tests/trace-hooks.test.sh`'s assertion that an emit made
# AFTER this hook carries the session, which is the only thing the pointer is
# for. GIT_DIR and GIT_WORK_TREE are scrubbed because git exports them into
# hooks and a pinned pair would answer for another repository.
hook_pointer() {
	_hp_dir=$( (cd "$hook_repo" && sh scripts/trace.sh dir) 2>/dev/null ) || _hp_dir=
	[ -n "$_hp_dir" ] || return 1
	_hp_top=$( (unset GIT_DIR GIT_WORK_TREE && git -C "$hook_repo" rev-parse --show-toplevel) 2>/dev/null ) || _hp_top=
	[ -n "$_hp_top" ] || _hp_top=$hook_repo
	_hp_key=$(printf '%s' "$_hp_top" |
		(unset GIT_DIR GIT_WORK_TREE && git hash-object --stdin) 2>/dev/null) || _hp_key=
	[ -n "$_hp_key" ] || return 1
	printf '%s/current/%s' "$_hp_dir" "$_hp_key"
}

# hook_point_at <session id> — write the pointer, or do nothing at all.
hook_point_at() {
	_pa_p=$(hook_pointer) || return 0
	mkdir -p "$(dirname "$_pa_p")" 2>/dev/null || return 0
	printf '%s\n' "$1" >"$_pa_p" 2>/dev/null || :
	return 0
}

# --- token counts -----------------------------------------------------------

# hook_tokens <transcript> <kind> [--after <message id>] [<field>=<value> …] —
# one event of <kind> per model in the transcript, carrying that model's four
# token counts, and at least one event whatever happens. Five shapes, all of
# them exit 0:
#
#   the numbers      one event per model, tokens on it, and how far the read
#                    went: data.msgs (that model's messages) and data.last_msg
#   node missing     one event, outcome=fail, the reason naming node
#   shape drift      one event, outcome=fail, the reason the extractor gave —
#                    an --after anchor the transcript no longer holds is one
#   nothing to read  one event, outcome=fail, saying the transcript had no
#                    assistant message with a usage block yet
#   nothing new      with --after only: one event, no tokens and no failure,
#                    carrying the anchor forward as data.last_msg
#
# --after is the previous read's data.last_msg, and with it only the messages
# after it are counted (#307): see transcript-usage.mjs for why a resumed
# session needs it and session-end.sh for where the anchor comes from.
#
# EVERY FAILURE SHAPE CARRIES outcome=fail AND NO TOKEN COUNTS. The counts,
# because a partial sum is the failure this whole path exists to avoid and an
# event saying "this is what I could not read" is worth more than one saying
# zero. The flag, because the last shape is the live gap subagent-stop.sh
# documents — a transcript read before it was flushed — and without a field to
# filter on it is indistinguishable from a subagent that genuinely spent
# nothing, so the holes cannot be counted and the ticket that closes them has
# no acceptance (M-6, review of PR #291).
hook_tokens() {
	_ht_file=$1
	_ht_kind=$2
	shift 2
	_ht_after=
	if [ "${1:-}" = --after ]; then
		_ht_after=${2:-}
		# Never a shift past $#: some shells abort on it, and rule 1 is exit 0.
		if [ $# -ge 2 ]; then shift 2; else shift; fi
	fi
	# THE REASON NAMES THE FIX, not only the gap. A node managed per user
	# (a version manager under the home directory) is on the operator's shell
	# PATH and on none of the agent harness's, and every usage event of every
	# session then fails this way — 4 of 4 session.usage and 41 agent.stop
	# events in one retro window (F5a, 2026-10-01) — while the event said only
	# what was missing. The fix is policy, not code: a personal, uncommitted
	# settings entry that puts that directory on the path, whose shape the
	# adapter README gives. No machine path is spelled here: the one on this
	# machine is wrong on every other, and a reason is copied.
	if ! command -v node >/dev/null 2>&1; then
		hook_trace emit kind="$_ht_kind" outcome=fail \
			reason='node is not on PATH, so the transcript could not be read for token counts — put its directory on the path through a personal, uncommitted .claude/settings.local.json env entry (see adapters/claude-code/README.md: When node is managed per user)' "$@"
		return 0
	fi
	# TWO STREAMS, KEPT APART. The first draft merged them, and a node that
	# prints a warning of its own — an ExperimentalWarning, a version shim's
	# notice — then fed that line to the row reader on the success path and
	# recorded it as the drift reason on the failure path (M-1, review of
	# PR #291). Never parse a stream the runtime shares. Without a scratch
	# file the two cannot be told apart, so that case takes the rows and lets
	# node's own stderr reach the operator instead of guessing.
	_ht_err=$(mktemp "${TMPDIR:-/tmp}/cc-hook.XXXXXX" 2>/dev/null) || _ht_err=
	if [ -n "$_ht_err" ]; then
		_ht_out=$(node "$hook_here/transcript-usage.mjs" ${_ht_after:+--after "$_ht_after"} "$_ht_file" 2>"$_ht_err")
		_ht_st=$?
		# THE EXTRACTOR'S OWN LINE, by its prefix, and only then the first
		# line: a runtime warning arrives BEFORE the refusal it precedes, so
		# "the first line" recorded node's chatter as the reason a key drifted.
		# One line, trimmed, either way — an event is capped at 4000 bytes
		# (craft §11's single write, made checkable) and a reason is a sentence.
		_ht_why=$(sed -n '/^x transcript-usage:/{p;q;}' "$_ht_err" 2>/dev/null | cut -c1-300)
		[ -n "$_ht_why" ] || _ht_why=$(sed -n '1p' "$_ht_err" 2>/dev/null | cut -c1-300)
		rm -f "$_ht_err"
	else
		_ht_out=$(node "$hook_here/transcript-usage.mjs" ${_ht_after:+--after "$_ht_after"} "$_ht_file")
		_ht_st=$?
		_ht_why=
	fi
	if [ "$_ht_st" != 0 ]; then
		hook_trace emit kind="$_ht_kind" outcome=fail \
			reason="${_ht_why:-the transcript usage extractor failed and said nothing}" "$@"
		return 0
	fi
	if [ -z "$_ht_out" ] && [ -n "$_ht_after" ]; then
		hook_trace emit kind="$_ht_kind" data.last_msg="$_ht_after" data.msgs=0 \
			reason="nothing new in the transcript since $_ht_after, which an earlier usage event counted" "$@"
		return 0
	fi
	if [ -z "$_ht_out" ]; then
		hook_trace emit kind="$_ht_kind" outcome=fail \
			reason='the transcript carries no assistant message with a usage block — nothing to read yet' "$@"
		return 0
	fi
	printf '%s\n' "$_ht_out" | while read -r _ht_m _ht_i _ht_o _ht_w _ht_r _ht_n _ht_l; do
		[ -n "$_ht_m" ] || continue
		hook_trace emit kind="$_ht_kind" model="$_ht_m" \
			tok_in="$_ht_i" tok_out="$_ht_o" tok_cache_w="$_ht_w" tok_cache_r="$_ht_r" \
			data.msgs="$_ht_n" data.last_msg="$_ht_l" "$@"
	done
	return 0
}

# --- tool capture: the switch, and the trace directory ----------------------
# Everything below is read only by tool-post.sh. It sits here, beside the
# payload reader and the pointer, because it is the same kind of thing: what
# this adapter has to know about the shared script in order to speak to it.
# The blob store is NOT here: the hook hands each payload to `scripts/trace.sh
# blob`, which stores it exactly as an emit's payload is stored and prints its
# name, so there is one writer of that store (ticket #306).

# hook_policy — the trace policy file this repository's hooks read.
#
# The same two candidates `scripts/trace.sh` discovers when it is run from this
# repository, which is how `hook_trace` always runs it: an explicit
# TRACE_CONFIG (relative values against the repository, never against wherever
# the agent harness stood), else scripts/trace.config.sh beside the script. One
# answer for "is tracing on", reached from either side.
hook_policy() {
	if [ -n "${TRACE_CONFIG:-}" ]; then
		case $TRACE_CONFIG in
		/*) printf '%s' "$TRACE_CONFIG" ;;
		*) printf '%s/%s' "$hook_repo" "$TRACE_CONFIG" ;;
		esac
		return 0
	fi
	printf '%s/scripts/trace.config.sh' "$hook_repo"
}

# hook_tools_on — is tool capture asked for? Status 0 for yes, 1 for no.
#
# WHY A HOOK READS POLICY AT ALL, when every other answer here comes out of
# `scripts/trace.sh`: the shared script has no opinion on tool capture. An event
# is an event, whoever asked for it, and the agent harness is the adapter's
# business (ADR-0008 clause 8) — so the only reader of TRACE_TOOLS is the hook
# that would do the capturing. It reads the same file with the same precedence
# the shared script gives TRACE_DIR: the environment wins over the file, and an
# environment value of '' is the documented OFF even when the file says 1.
#
# SOURCING IS EXECUTING, which is why the file is the one this adapter's own
# repository names and never one found from a cwd the agent harness chose — the
# reason scripts/agents.lib.sh anchors its discovery the same way. A file that
# is missing or that cannot be read answers OFF, because OFF is the safe default
# for a switch whose ON state writes down everything every tool returned.
hook_tools_on() {
	if [ -n "${TRACE_TOOLS+set}" ]; then
		[ -n "$TRACE_TOOLS" ]
		return $?
	fi
	_ht_file=$(hook_policy)
	[ -f "$_ht_file" ] || return 1
	# The policy file's own output goes nowhere: only the printf below is this
	# substitution's answer, so a file that echoes cannot turn a switch on.
	_ht_want=$(
		. "$_ht_file" >/dev/null 2>&1
		printf '%s' "${TRACE_TOOLS:-}"
	)
	[ -n "$_ht_want" ]
}

# hook_dir — the resolved trace directory, or nothing (status 1) when tracing is
# off. Asked of the shared script itself, which is the only thing that knows how
# a relative policy value resolves against the root checkout.
#
# ASK IT ONCE. There is no cache here on purpose: a caller reads this through a
# command substitution, so anything remembered inside would be remembered in a
# subshell and thrown away — a cache that cannot work, paid for on every tool
# call (M-4, review of PR #295). The one caller resolves it once and hands it
# down.
hook_dir() {
	_hd_dir=$( (cd "$hook_repo" && sh scripts/trace.sh dir) 2>/dev/null ) || _hd_dir=
	[ -n "$_hd_dir" ] || return 1
	printf '%s' "$_hd_dir"
}

# --- waiting for a subagent's final message ---------------------------------
# Read only by subagent-stop.sh. SubagentStop can run BEFORE the subagent's
# transcript holds its final assistant line (ticket #308 measured the line
# landing 170 and 223 ms after the hook began, in two of seven live stops), and
# a transcript read then either has no usage at all or — worse — holds the turns
# before the last one, whose sum is a confident undercount. So the hook may
# wait, for as long as the policy says and never longer.

# hook_wait_bound — set hook_wait_ms to the bound TRACE_AGENT_WAIT_MS names, in
# milliseconds, or to nothing for no wait; set hook_wait_bad to a refused value.
#
# The same file and precedence hook_tools_on reads: the environment wins, an
# environment value of '' is the documented no-wait even when the file names a
# bound, and a policy file that is missing or unreadable is no wait — the
# behaviour the agent harness had before this bound existed.
#
# A MALFORMED VALUE IS REFUSED like every other policy value: anything but one
# to five digits with no leading zero (sh arithmetic reads 0100 as octal, so it
# would silently be 64). Refused means NOT waited, and the value lands in
# hook_wait_bad for the caller to name — on stderr and on the event, and only
# when tracing is on, so a project that traces nothing is not told about a typo
# on every subagent stop (review of PR #323). The hook still exits 0, because a
# typo in a policy file must never become a stalled session. '0' is no wait,
# like ''.
hook_wait_bound() {
	hook_wait_ms=
	hook_wait_bad=
	if [ -n "${TRACE_AGENT_WAIT_MS+set}" ]; then
		_wb=$TRACE_AGENT_WAIT_MS
	else
		_wb_file=$(hook_policy)
		_wb=
		[ -f "$_wb_file" ] && _wb=$(
			. "$_wb_file" >/dev/null 2>&1
			printf '%s' "${TRACE_AGENT_WAIT_MS:-}"
		)
	fi
	case $_wb in
	'' | 0) return 0 ;;
	*[!0-9]* | 0* | ??????*)
		# One line, at most 60 characters: a policy value is anything at all.
		hook_wait_bad=$(printf '%s' "$_wb" | tr -d '\n' | cut -c1-60)
		return 0
		;;
	esac
	hook_wait_ms=$_wb
}

# hook_final <transcript> — does the transcript end on a final message? Status
# 0 for yes.
#
# FINAL means: its last user-or-assistant line is an ASSISTANT line whose
# stop_reason is set and is not tool_use. Each half is load-bearing. "Last user
# or assistant line", because a subagent resumed after an earlier stop already
# holds an end_turn from that stop, and the user line that resumed it comes
# after — so an old final message never reads as this stop's. "Not tool_use and
# not null", because a turn that called a tool is followed by more turns, and a
# streamed response writes one line per content block with stop_reason null on
# the ones before its last. The keys are matched as JSON punctuation, with any
# whitespace around the colon — a transcript written with `"type": "assistant"`
# is the same transcript (review of PR #323).
#
# WHAT IT CANNOT RULE OUT, stated rather than claimed away: the match is on the
# line, not on its top-level object. Text inside a message is an escaped string
# and cannot match, but a tool's STRUCTURED result is written as a JSON object,
# so a user line whose result object itself holds a `"type":"assistant"` and a
# `stop_reason` would read as final. Nothing observed writes such a result; if
# one ever does, the cost is one early read, which the extractor then sums.
hook_final() {
	_hf_last=$(grep -E '"type"[[:space:]]*:[[:space:]]*"(user|assistant)"' "$1" 2>/dev/null | tail -n 1)
	printf '%s\n' "$_hf_last" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"assistant"' || return 1
	printf '%s\n' "$_hf_last" | grep -Eq '"stop_reason"[[:space:]]*:[[:space:]]*"' || return 1
	printf '%s\n' "$_hf_last" | grep -Eq '"stop_reason"[[:space:]]*:[[:space:]]*"tool_use"' && return 1
	return 0
}

# hook_now_ms — the wall clock in milliseconds, or status 1 where `date` has no
# sub-second field. `%N` is not POSIX: GNU date answers it, and a date that does
# not leaves a letter behind, which the digit check turns into "no clock".
hook_now_ms() {
	_nm=$(date +%s%N 2>/dev/null) || return 1
	case $_nm in '' | *[!0-9]*) return 1 ;; esac
	[ "${#_nm}" -gt 6 ] || return 1
	printf '%s' "${_nm%??????}"
}

# hook_wait_final <transcript> <bound ms> — poll until the transcript ends on a
# final message or the bound passes, and print the milliseconds waited. Status
# 0 when it became final, 1 when the bound passed first.
#
# WALL TIME where the clock allows it, because the bound is a promise about the
# session and a loaded machine makes every poll slower than its nap: counting
# only the naps, a 2000 ms bound reported 2000 on a machine at load average 29
# while the hook ran six seconds end to end. So on a clock with milliseconds the wait is measured, the
# check comes last before giving up, and the overshoot is at most one poll.
# Without one (POSIX `date` stops at seconds) the figure is the sum of the naps
# taken — honest about what it is, and the best a portable shell can say.
#
# THE NAPS ARE COUNTED EVEN WITH A CLOCK, and the wait is whichever of the two
# is larger. The clock is the realtime one, and a clock that steps BACK would
# otherwise read as time un-passing: the review reproduced a 500 ms bound
# holding the hook for 3566 ms (review of PR #323). The naps taken are a floor
# no clock can lower.
#
# A nap is 50 ms, trimmed so the next check lands on the bound. A `sleep` that
# refuses a fraction (POSIX promises only whole seconds) is answered with
# whole-second naps while about a whole second remains — within one poll of
# it, so a bound of exactly 1000 still gets its nap after the first check has
# spent a few milliseconds — and the wait otherwise ends early rather than
# overrun. Never a busy loop; past the bound by at most one poll.
hook_wait_final() {
	_hw_t0=$(hook_now_ms) || _hw_t0=
	_hw_waited=0
	_hw_count=0
	_hw_step=50
	while :; do
		if hook_final "$1"; then
			printf '%s' "$_hw_waited"
			return 0
		fi
		if [ -n "$_hw_t0" ]; then
			# A clock that stops answering mid-wait hands over to counting from
			# here, rather than reading as no time passing — which would never end.
			if _hw_now=$(hook_now_ms); then
				_hw_waited=$((_hw_now - _hw_t0))
			else
				_hw_t0=
			fi
		fi
		[ "$_hw_waited" -ge "$_hw_count" ] || _hw_waited=$_hw_count
		_hw_left=$(($2 - _hw_waited))
		[ "$_hw_left" -gt 0 ] || break
		[ "$_hw_left" -lt "$_hw_step" ] && _hw_nap=$_hw_left || _hw_nap=$_hw_step
		if [ "$_hw_step" = 1000 ] || ! sleep "0.$(printf '%03d' "$_hw_nap")" 2>/dev/null; then
			_hw_step=1000
			[ "$_hw_left" -ge 950 ] || break
			sleep 1
			_hw_nap=1000
		fi
		_hw_count=$((_hw_count + _hw_nap))
		[ -n "$_hw_t0" ] || _hw_waited=$_hw_count
	done
	printf '%s' "$_hw_waited"
	return 1
}

# --- how far this checkout is behind main -----------------------------------
# Read only by session-start.sh (ticket #384, retro 20261001T150216Z finding
# G1). A hook runs the code of the checkout it LIVES in, and the kit's own sat
# ~140 commits behind main for four hours with nothing saying so: every adapter
# fix the wave had landed was inert for the trace that should have shown it.

# hook_behind — how many commits the last FETCHED origin/main holds that this
# checkout's HEAD does not, or nothing (status 1) when there is no origin/main,
# no repository, or no git.
#
# NEVER THE NETWORK. A hook is on the session's critical path, so this reads
# the remote-tracking ref as the last fetch left it and never fetches: the
# count is "behind what this machine last saw", which is the honest claim.
# GIT_NO_LAZY_FETCH keeps a partial clone from fetching a missing object behind
# the walk's back; GIT_DIR and GIT_WORK_TREE are scrubbed for hook_pointer's
# reason.
hook_behind() {
	_hb=$( (unset GIT_DIR GIT_WORK_TREE && GIT_NO_LAZY_FETCH=1 &&
		export GIT_NO_LAZY_FETCH &&
		git -C "$hook_repo" rev-list --count HEAD..refs/remotes/origin/main) 2>/dev/null ) || return 1
	case $_hb in '' | *[!0-9]*) return 1 ;; esac
	printf '%s' "$_hb"
}

# hook_behind_warn <count> — say once on stderr that the checkout is <count>
# behind, when TRACE_BEHIND_WARN names a threshold and <count> is MORE than it.
#
# The same file and precedence as TRACE_AGENT_WAIT_MS: the environment wins, an
# environment value of '' is off even when the file names one, and a missing
# policy file is off. A malformed value is refused and named — one line — and
# is never a failure. Said whether or not the trace is on: the note is about
# the code the hooks run, not about the trace.
hook_behind_warn() {
	if [ -n "${TRACE_BEHIND_WARN+set}" ]; then
		_bw=$TRACE_BEHIND_WARN
	else
		_bw_file=$(hook_policy)
		_bw=
		[ -f "$_bw_file" ] && _bw=$(
			. "$_bw_file" >/dev/null 2>&1
			printf '%s' "${TRACE_BEHIND_WARN:-}"
		)
	fi
	case $_bw in
	'') return 0 ;;
	0) ;;
	*[!0-9]* | 0* | ??????*)
		printf "! session-start: TRACE_BEHIND_WARN='%s' is not a whole number of commits; ignored\n" \
			"$(printf '%s' "$_bw" | tr -d '\n' | cut -c1-60)" >&2
		return 0
		;;
	esac
	[ "$1" -gt "$_bw" ] || return 0
	printf '! session-start: %s is %s commits behind origin/main as last fetched (TRACE_BEHIND_WARN=%s) — the hooks run the code it holds; sync it\n' \
		"$hook_repo" "$1" "$_bw" >&2
}
