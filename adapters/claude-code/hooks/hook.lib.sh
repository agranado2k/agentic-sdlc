#!/bin/sh
# hook.lib.sh — what the hooks beside this file share: the trace hooks and the
# kill guard, and hook_root for the root guard.
#
# WHAT THESE HOOKS ARE. One agent harness can tell the decision trace three
# things nothing else knows: that a session began, what it spent, and that a
# subagent finished. Those are the agent harness's own events, so they live
# here in its adapter rather than in `scripts/trace.sh` (the kit's ADR-0008 clause 8:
# "the agent harness is the adapter's business"). Everything portable — the
# line format, the closed kind vocabulary, where the trace directory is — stays
# in the shared script, which these hooks call and never reimplement.
#
# DORMANT UNTIL SOMETHING NAMES THEM. Nothing under `adapters/` is on an
# execution path; a hook runs only once a settings file wires it (see
# ../README.md, "Wiring the session hooks"). In THIS kit that file is
# `.claude/settings.json`, which is kit-authoring only and never shipped. In
# your project it is yours to write, and until you write it the files here
# are reference material you can read.
#
# THE THREE RULES A HOOK HERE KEEPS, and why each one is not negotiable:
#
#   1. EXIT 0, ALWAYS. A hook is on the agent harness's critical path. A
#      non-zero exit is a signal to the agent harness about the SESSION, and
#      observability that can fail a session is worse than none (PRD #237,
#      story 15; the kit's ADR-0008 clause 4). Every call into the trace ends in `|| :`
#      and every hook ends in `exit 0`. ONE SANCTIONED EXCEPTION: the kill
#      guard, tool-pre-guard.sh, is a guard rather than an observer, and it
#      exits 2 — the agent harness's block status — when, and only when, it
#      refuses a spawned sub-agent's call (#414). Every other path in it is
#      exit 0 like everything else here. root-guard.sh sources this file for
#      hook_root alone, and keeps a rule of its own: it exits 2 to refuse an
#      edit at the root checkout (#392), and 0 on every path it cannot read.
#   2. SILENT ON STDOUT, but for one object. What a hook prints on stdout
#      reaches the agent harness's own parser. The trace's answers go to a
#      file; nothing about the trace is ever said there. STDERR is a different
#      stream and is deliberately loud — the kit's ADR-0008 clause 4 wants a trace error
#      visible. The one exception is session-start's behind note, which is
#      about the code the hooks run, not the trace: stderr on exit 0 reaches
#      no reader on this agent harness, so past its threshold the note is also
#      one JSON object on stdout, written by hook_say_session and nothing else
#      (ticket #427). A trace error never takes that route.
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

# hook_pointer <trace dir> — the per-toplevel pointer file `scripts/trace.sh`
# reads a session id back from, or nothing (status 1) when <trace dir> is empty
# (tracing is off) or git cannot hash the path. Empty spawns nothing.
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
	[ -n "${1:-}" ] || return 1
	_hp_top=$( (unset GIT_DIR GIT_WORK_TREE && git -C "$hook_repo" rev-parse --show-toplevel) 2>/dev/null ) || _hp_top=
	[ -n "$_hp_top" ] || _hp_top=$hook_repo
	hook_current_of "$1" "$_hp_top"
}

# hook_current_of <trace dir> <toplevel> — the per-toplevel path
# `scripts/trace.sh` keys a working tree's pointer file on. Nothing (status 1)
# when <trace dir> is empty (tracing is off) or git cannot hash the path.
# DELIBERATE COUPLING: this repeats the shared script's key derivation
# (trace_key) for the pointer, which hook_pointer writes. The run stack beside
# it is never derived here: hook_run_of asks the shared script for it (#472).
hook_current_of() {
	_hc_dir=${1:-}
	[ -n "$_hc_dir" ] || return 1
	_hc_key=$(printf '%s' "$2" |
		(unset GIT_DIR GIT_WORK_TREE && git hash-object --stdin) 2>/dev/null) || _hc_key=
	[ -n "$_hc_key" ] || return 1
	printf '%s/current/%s' "$_hc_dir" "$_hc_key"
}

# --- the run of the checkout the work happened in ----------------------------

# hook_run_of <trace dir> <dir> [<session id>] — export TRACE_RUN and
# TRACE_PARENT from that session's run stack in the checkout <dir> is in, so
# every emit after it carries that checkout's run. An empty <trace dir> is
# tracing off: nothing is exported and nothing is spawned (#463).
# Ticket #421, retro finding H4 (#417).
#
# WHY. The shared script reads the stack of the toplevel IT lives in, and the
# kit's hooks execute from the ROOT checkout — while a session's `begin` ran
# in a linked worktree, whose stack is keyed on the worktree's toplevel. Read
# the shared script's way, every stop carried the root's run (or none), and no
# subagent's spend joined the ticket it was spent on: 0 of 28 priced agent.stop
# events carried an implement or review run.
#
# WHICH CHECKOUT. <dir>'s — a relative <dir> is taken from this process's
# working directory, once, so the check below and the script, which runs from
# the root checkout, ask about the same directory — when git answers for it
# AND its common directory is this repository's — a cwd in an unrelated
# repository is not a checkout of this one, and its stack would be a
# stranger's. Otherwise nothing is exported
# and the shared script answers with the root's stack, as before. A checkout
# whose stack holds no run exports TRACE_RUN='' — the shared script's spelling
# of "no run" — so an idle worktree never borrows the root's run. The hook
# asks git this itself, before the script: the fallback to the root's run is the
# hook's own, and the script refuses another repository's checkout with the
# same exit 2 as an unreadable stack, which calls for no run instead.
#
# THE STACK IS THE SHARED SCRIPT'S. It is read by `sh scripts/trace.sh stack
# <dir>`, which prints the top of that checkout's stack and the run below it,
# from one read of the file, and refuses — exit 2, saying why on stderr — a
# stack that exists and cannot be read. A refusal is a stop that carries no
# run, never the root's. The adapter keeps no copy of where a stack lives or
# what is in it (#472).
#
# WHOSE STACK. Since #453 the stack is keyed by session as well as by
# toplevel: <session id> is passed as `session=` when it is one the script
# would key on, and the ask is made with TRACE_SESSION empty, the script's
# spelling of "no session", so a payload that names none reads the
# per-toplevel stack —
# another session's run in the same checkout is never this stop's.
#
# THE ENVIRONMENT STILL WINS. A TRACE_RUN already set (a dispatched worker told
# whose trail it joins) is left alone, and with it the parent, exactly as the
# shared script's own precedence has it; a TRACE_PARENT already set is kept.
hook_run_of() {
	[ -n "${TRACE_RUN+set}" ] && return 0
	[ -n "${1:-}" ] || return 0
	shift
	[ -n "${1:-}" ] || return 0
	case $1 in /*) _ro_dir=$1 ;; *) _ro_dir=$PWD/$1 ;; esac
	_ro_common=$(hook_common_dir "$_ro_dir") || return 0
	_ro_own=$(hook_common_dir "$hook_repo") || return 0
	[ "$_ro_common" = "$_ro_own" ] || return 0
	_ro_sess=
	hook_id_ok "${2:-}" && _ro_sess=session=$2
	_ro_pair=$( (cd "$hook_repo" &&
		TRACE_SESSION= sh scripts/trace.sh stack "$_ro_dir" ${_ro_sess:+"$_ro_sess"}) ) || _ro_pair=
	_ro_nl='
'
	_ro_run=${_ro_pair%%"$_ro_nl"*}
	case $_ro_pair in *"$_ro_nl"*) _ro_parent=${_ro_pair#*"$_ro_nl"} ;; *) _ro_parent= ;; esac
	TRACE_RUN=$_ro_run
	export TRACE_RUN
	if [ -z "${TRACE_PARENT+set}" ]; then
		TRACE_PARENT=$_ro_parent
		export TRACE_PARENT
	fi
	return 0
}

# --- the run handed over at spawn -------------------------------------------

# hook_run_handed <transcript> — export TRACE_RUN, and TRACE_PARENT unless
# already set, from the run the spawning session handed this agent; status 0
# when one was handed (or the environment already names a run), 1 when the
# channel is empty and the caller's own resolution answers. Ticket #474.
#
# WHY A CHANNEL AT ALL. A hook runs in the agent harness's process, never the
# subagent's, so nothing exported for a subagent reaches it; and the payload's
# cwd is the SESSION's working directory, not the worktree a subagent worked
# in — #478 measured it: of 151 subagents whose stop recorded a cwd, 143 named
# the root checkout. What the spawning session can fix at spawn time is the
# prompt, and the agent harness writes that prompt, verbatim, as the first user
# line of the agent's own transcript.
#
# THE CHANNEL is the prompt's FIRST line, `Trace-Run: <run id> [<parent run
# id>]`, and nothing else on it: the run, then — after one space — the run it
# nests in, the one the spawner's own prompt handed it (the ticket's TRACE_RUN,
# with TRACE_PARENT). The first line only, so text a spawn prompt quotes
# further down — a ticket body, a review comment — can never name a run. Each
# id is held to the shape the shared script mints (stamp, pid, eight hex
# digits) and is only ever a value on an event: it is never executed, and a
# line that does not match exactly is no channel at all. With no parent on the
# line the parent is empty, never read from this checkout's stack: a run named
# from elsewhere has its lineage elsewhere — the shared script's own rule for an
# environment that names the run.
#
# BOUNDED. Only the first user record among the transcript's first fifty lines
# is read, and only its first 4096 bytes: the prompt opens the record, and a
# 200 KB prompt costs one bounded read, never a pattern match over all of it.
# A channel that does not start inside those bytes is no channel.
#
# THE ENVIRONMENT STILL WINS, as in hook_run_of: a TRACE_RUN already set (a
# dispatched worker told whose trail it joins) is left alone, and a
# TRACE_PARENT already set is kept.
hook_run_handed() {
	[ -n "${TRACE_RUN+set}" ] && return 0
	hook_handed_line "${1:-}" || return 1
	TRACE_RUN=$_rh_run
	export TRACE_RUN
	if [ -z "${TRACE_PARENT+set}" ]; then
		TRACE_PARENT=$_rh_parent
		export TRACE_PARENT
	fi
	return 0
}

# hook_prompt_of <transcript> — set hook_prompt to the opening of the first
# user record's prompt, as JSON-string text, its first 4096 bytes at most;
# status 1 when there is none. The ONE bounded read both channel lines are
# taken from (hook_run_handed above, hook_spawn_handed below): it is kept for
# the file it read, so a hook asking for both reads the transcript once.
hook_prompt_of() {
	[ -n "${1:-}" ] || return 1
	if [ "${_hp_file-}" != "$1" ]; then
		_hp_file=$1
		# Fifty lines: the prompt is written when the agent starts, ahead of
		# everything it does. 4096 bytes: the record's keys and the prompt's
		# first lines fit many times over, and nothing past them is a channel's.
		_hp_line=$(head -n 50 "$1" 2>/dev/null |
			sed -n '/"type"[[:space:]]*:[[:space:]]*"user"/{p;q;}' | cut -b 1-4096)
		# The message's own content, anchored on its role so no nested content
		# block answers for it: one string, or content blocks whose first is text.
		hook_prompt=${_hp_line#*'"role":"user","content":"'}
		[ "$hook_prompt" != "$_hp_line" ] ||
			hook_prompt=${_hp_line#*'"role":"user","content":[{"type":"text","text":"'}
		[ "$hook_prompt" != "$_hp_line" ] || hook_prompt=
	fi
	[ -n "$hook_prompt" ]
}

# hook_handed_line <transcript> — status 0, with _rh_run, _rh_parent and
# _rh_after (the prompt's text past the line's newline, empty when the line
# closed the prompt) set, when the prompt's first line is a well-formed
# `Trace-Run:` line; 1 otherwise. The shape is hook_run_handed's header.
hook_handed_line() {
	hook_prompt_of "${1:-}" || return 1
	case $hook_prompt in 'Trace-Run: '*) ;; *) return 1 ;; esac
	_rh_val=${hook_prompt#Trace-Run: }
	# The line ends where the JSON string's next escape or its close begins,
	# and that escape must be a newline: a tab or anything else after the ids
	# is more on the line, and no channel.
	_rh_run=${_rh_val%%\\*}
	_rh_run=${_rh_run%%\"*}
	_rh_after=${_rh_val#"$_rh_run"}
	case $_rh_after in
	'\n'*) _rh_after=${_rh_after#??} ;;
	'"'*) _rh_after= ;;
	*) return 1 ;;
	esac
	_rh_parent=
	case $_rh_run in *' '*)
		_rh_parent=${_rh_run#* }
		_rh_run=${_rh_run%% *}
		hook_run_id_ok "$_rh_parent" || return 1
		;;
	esac
	hook_run_id_ok "$_rh_run"
}

# hook_spawn_handed <transcript> — set hook_spawn_tier, hook_spawn_domain,
# hook_spawn_skill and hook_spawn_ticket from what the spawn served; status 0
# when the prompt named it, 1 when it did not — and then the tier is
# `unattributed` and the other three are empty. Ticket #583.
#
# THE LINE is the prompt's SECOND, under a well-formed Trace-Run first line
# (hook_run_handed), exactly
#   Trace-Spawn: tier=<tier> domain=<domain|none> skill=<skill> ticket=<#N|none>
# four fields in that order, one space apart, nothing else on the line. The
# tier is one of the four the kit sizes work to; a domain and a skill are
# `[a-z][a-z0-9-]*`, 32 characters at most; a ticket is `#` and a number with
# no leading zero, six digits at most. `none` leaves the domain empty and
# relates no ticket. A line further down, out of order, with an extra field, a
# tab or a value of another shape is no line: the stop is `unattributed`, which
# the summary shows as a row of its own rather than dropping. Each value is
# only ever a field on an event — never executed — and the read is
# hook_prompt_of's, the same bounded one that finds the run, whether or not
# the environment already named the run.
hook_spawn_handed() {
	hook_spawn_tier=unattributed
	hook_spawn_domain=
	hook_spawn_skill=
	hook_spawn_ticket=
	hook_handed_line "${1:-}" || return 1
	case $_rh_after in 'Trace-Spawn: '*) ;; *) return 1 ;; esac
	_hs_val=${_rh_after#Trace-Spawn: }
	_hs_line=${_hs_val%%\\*}
	_hs_line=${_hs_line%%\"*}
	case ${_hs_val#"$_hs_line"} in '\n'* | '"'*) ;; *) return 1 ;; esac
	_hs_t=${_hs_line%% *}
	_hs_r=${_hs_line#* }
	_hs_d=${_hs_r%% *}
	_hs_r=${_hs_r#* }
	_hs_s=${_hs_r%% *}
	_hs_k=${_hs_r#* }
	case $_hs_k in *' '*) return 1 ;; esac
	# DELIBERATE COUPLING, like hook_run_id_ok's: the four tiers are the kit's
	# fixed vocabulary (docs/capability-tiers.md), spelled here too so a hook
	# reads no policy file to size a stop; a typo never mints a summary row.
	case $_hs_t in tier=planner | tier=implementer | tier=mechanical | tier=reviewer) ;; *) return 1 ;; esac
	case $_hs_d in domain=*) ;; *) return 1 ;; esac
	case $_hs_s in skill=*) ;; *) return 1 ;; esac
	case $_hs_k in ticket=*) ;; *) return 1 ;; esac
	_hs_d=${_hs_d#domain=}
	_hs_s=${_hs_s#skill=}
	_hs_k=${_hs_k#ticket=}
	[ "$_hs_d" = none ] || hook_spawn_word_ok "$_hs_d" || return 1
	hook_spawn_word_ok "$_hs_s" || return 1
	case $_hs_k in
	none) ;;
	'#'[1-9] | '#'[1-9][0-9] | '#'[1-9][0-9][0-9] | '#'[1-9][0-9][0-9][0-9] | \
		'#'[1-9][0-9][0-9][0-9][0-9] | '#'[1-9][0-9][0-9][0-9][0-9][0-9]) ;;
	*) return 1 ;;
	esac
	hook_spawn_tier=${_hs_t#tier=}
	[ "$_hs_d" = none ] || hook_spawn_domain=$_hs_d
	hook_spawn_skill=$_hs_s
	[ "$_hs_k" = none ] || hook_spawn_ticket=$_hs_k
	return 0
}

# hook_spawn_word_ok <value> — a domain or a skill as the Trace-Spawn line may
# carry one: `[a-z][a-z0-9-]*`, 32 characters at most.
hook_spawn_word_ok() {
	case ${1:-} in [a-z]*) ;; *) return 1 ;; esac
	case $1 in *[!a-z0-9-]*) return 1 ;; esac
	[ "${#1}" -le 32 ]
}

# hook_run_id_ok <value> — is this a run id the shared script could have
# minted? `<YYYYMMDD>T<HHMMSS>Z-<pid>-<eight hex digits>`, and nothing more;
# 64 characters at most, past any pid a host hands out, so no line of any
# length is carried onto an event.
# DELIBERATE COUPLING: this repeats the shape of the shared script's
# trace_id, which exposes no check of its own. The leg that catches a drift is
# `tests/trace-hooks.test.sh` §47's first: the id a real `begin` printed is
# handed over and carried. One predicate owned by the script is a release,
# recorded as a candidate ticket (review of PR #524).
hook_run_id_ok() {
	case ${1:-} in
	[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-?*-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
	*) return 1 ;;
	esac
	_ri_pid=${1#*Z-}
	_ri_pid=${_ri_pid%-*}
	case $_ri_pid in '' | *[!0-9]*) return 1 ;; esac
	[ "${#1}" -le 64 ]
}

# hook_agent_transcript <session transcript> [<agent id>] — the transcript of
# the agent an event belongs to: the session's own when no agent is named, else
# the subagent's, under subagents/ in the directory named by the session
# transcript's own stem, where the agent harness keeps it (the #246 spike's
# layout, and the stop payload's agent_transcript_path). Built from the
# session's file, not its id, so the two can never disagree. A payload already
# naming the subagent's own file is taken as given. Nothing (status 1) for no
# session transcript, an agent id outside the identifier class — a path is
# never built from one — or a session transcript that is not a .jsonl: a
# subagent that cannot be named never borrows its session's run.
hook_agent_transcript() {
	[ -n "${1:-}" ] || return 1
	if [ -z "${2:-}" ]; then
		printf '%s' "$1"
		return 0
	fi
	hook_id_ok "$2" || return 1
	case $1 in
	*/agent-"$2".jsonl) printf '%s' "$1" ;;
	*.jsonl) printf '%s/subagents/agent-%s.jsonl' "${1%.jsonl}" "$2" ;;
	*) return 1 ;;
	esac
}

# hook_point_at <trace dir> <session id> — write the pointer, or do nothing at
# all.
hook_point_at() {
	_pa_p=$(hook_pointer "${1:-}") || return 0
	mkdir -p "$(dirname "$_pa_p")" 2>/dev/null || return 0
	printf '%s\n' "$2" >"$_pa_p" 2>/dev/null || :
	return 0
}

# --- token counts -----------------------------------------------------------

# hook_anchors <subject> <kind> — how far earlier reads of one subject already
# went: sets hook_recorded to that subject's <kind> events, as `show` prints
# them, and hook_after to the last data.last_msg among them, held to the
# identifier class (empty when none, or when it is not an id). A read hands
# hook_recorded to hook_tokens on stdin under --resume, and hook_after as
# --after. Only the subject is asked, so another subject's read never anchors
# this one; a fail event carries no last_msg, so it never anchors either.
# session-end.sh reads its session's (#307, #408), subagent-stop.sh its
# agent's (#565).
hook_anchors() {
	hook_recorded=$(hook_trace show "$1" --kind "$2")
	hook_after=$(printf '%s\n' "$hook_recorded" |
		sed -n 's/.*,"data":{.*"last_msg":"\([^"]*\)".*/\1/p' | sed -n '$p')
	hook_id_ok "$hook_after" || hook_after=
}

# hook_session_usage <session id> <transcript> [<field>=<value> …] — that
# session's `session.usage` events for what is new in <transcript> since the
# trace's last read of it: hook_anchors, then hook_tokens under --rollup and
# --resume, or one fail event when the transcript cannot be read. The fields
# ride every event. An id hook_id_ok refuses anchors nothing: the whole file. session-end.sh reads a run's end with it, and
# session-start.sh the end a killed run never had (#632).
hook_session_usage() {
	_su_sid=$1
	_su_file=$2
	shift 2
	hook_recorded=
	hook_after=
	hook_id_ok "$_su_sid" && hook_anchors "session:$_su_sid" session.usage
	if [ -n "$_su_file" ] && [ -f "$_su_file" ]; then
		printf '%s\n' "$hook_recorded" |
			hook_tokens "$_su_file" session.usage --rollup --resume ${hook_after:+--after "$hook_after"} "$@"
	else
		hook_trace emit kind=session.usage outcome=fail \
			reason="the transcript the payload named cannot be read: ${_su_file:-none named}" "$@"
	fi
}

# hook_tokens <transcript> <kind> [--rollup] [--resume] [--after <message id>] [<field>=<value> …] —
# one event of <kind> per model in the transcript, carrying that model's four
# token counts, and at least one event whatever happens. Seven shapes, all of
# them exit 0:
#
#   the numbers      one event per model, tokens on it, and how far the read
#                    went FOR THAT MODEL: data.msgs (its messages) and
#                    data.last_msg (its last one), its own resume anchor (#408)
#                    — and data.out_snapshot, only when some of those messages
#                    were written mid-stream: how many, so tok_out is a lower
#                    bound (#608; transcript-usage.mjs says why)
#   node missing     one event, outcome=fail, the reason naming node
#   shape drift      one event, outcome=fail, the reason the extractor gave —
#                    a resume anchor the transcript no longer holds is one
#   nothing to read  one event, outcome=fail, saying the transcript had no
#                    assistant message with a usage block yet
#   nothing new      with --after only: one event, no tokens, no model and no
#                    failure, carrying that id forward as data.last_msg
#   the rollup gap   with --rollup only, beside the numbers: one more event per
#                    model the rollup counts beyond them, data.via=rollup and
#                    data.reason=compaction, with no data.last_msg — it counts
#                    no message, so it never anchors a later read (#407) —
#                    and data.out_snapshot when the messages it was judged
#                    against hold snapshots, whose remainder its tok_out holds
#   rollup refused   with --rollup only: the numbers as usual, then one event,
#                    outcome=fail and data.via=rollup, the extractor's reason
#
# --rollup and --resume read the trace's own earlier events for this subject
# on stdin — hook_anchors reads them, for session-end.sh (a session's) and
# subagent-stop.sh (an agent's, #565). Under --rollup a gap already
# recorded is not recorded again; transcript-usage.mjs says when a rollup is
# judged at all. Under --resume each model is counted only after the last
# data.last_msg the trace holds for THAT model (#307, #408), so an end killed
# between two models' events loses neither: see transcript-usage.mjs for why a
# resumed session needs it and hook_anchors for where the events come from.
#
# --after is an earlier read's data.last_msg: an empty read is then "nothing
# new" rather than "nothing to read", carrying that id forward. Alone, it is
# also the extractor's one anchor for every model (#307). Beside --resume it
# is only that signal and never the anchor — one id for every model is the
# shape a kill partway turned into lost messages (#408) — and hook_anchors
# gives the last data.last_msg the trace holds for the subject, of any model.
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
	_ht_rollup=
	_ht_resume=
	while :; do
		case ${1:-} in
		--rollup) _ht_rollup=--rollup; shift ;;
		--resume) _ht_resume=--resume; shift ;;
		--after)
			_ht_after=${2:-}
			# Never a shift past $#: some shells abort on it, and rule 1 is exit 0.
			if [ $# -ge 2 ]; then shift 2; else shift; fi ;;
		*) break ;;
		esac
	done
	# The extractor's anchor: --resume's per-model anchors, or else the one id.
	_ht_one=
	[ -n "$_ht_resume" ] || _ht_one=$_ht_after
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
		_ht_out=$(node "$hook_here/transcript-usage.mjs" $_ht_rollup $_ht_resume ${_ht_one:+--after "$_ht_one"} "$_ht_file" 2>"$_ht_err")
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
		_ht_out=$(node "$hook_here/transcript-usage.mjs" $_ht_rollup $_ht_resume ${_ht_one:+--after "$_ht_one"} "$_ht_file")
		_ht_st=$?
		_ht_why=
	fi
	# EXIT 3 is --rollup's own: the message rows are good and the rollup was
	# refused. The rows are recorded as usual and the refusal after them.
	if [ "$_ht_st" != 0 ] && [ "$_ht_st" != 3 ]; then
		hook_trace emit kind="$_ht_kind" outcome=fail \
			reason="${_ht_why:-the transcript usage extractor failed and said nothing}" "$@"
		return 0
	fi
	if [ "$_ht_st" = 3 ]; then
		hook_trace emit kind="$_ht_kind" outcome=fail data.via=rollup \
			reason="${_ht_why:-the rollup was refused and the extractor said nothing}" "$@"
	fi
	_ht_gap=$(printf '%s\n' "$_ht_out" | awk '$6 == "rollup"')
	_ht_out=$(printf '%s\n' "$_ht_out" | awk 'NF && $6 != "rollup"')
	printf '%s\n' "$_ht_gap" | while read -r _ht_m _ht_i _ht_o _ht_w _ht_r _ht_v _ht_c _ht_s; do
		[ -n "$_ht_m" ] || continue
		hook_trace emit kind="$_ht_kind" model="$_ht_m" \
			tok_in="$_ht_i" tok_out="$_ht_o" tok_cache_w="$_ht_w" tok_cache_r="$_ht_r" \
			data.via="$_ht_v" data.reason="$_ht_c" ${_ht_s:+data.out_snapshot="$_ht_s"} \
			reason="the agent harness rollup counts these tokens and no assistant line carries them (data.reason $_ht_c)" "$@"
	done
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
	printf '%s\n' "$_ht_out" | while read -r _ht_m _ht_i _ht_o _ht_w _ht_r _ht_n _ht_l _ht_s; do
		[ -n "$_ht_m" ] || continue
		hook_trace emit kind="$_ht_kind" model="$_ht_m" \
			tok_in="$_ht_i" tok_out="$_ht_o" tok_cache_w="$_ht_w" tok_cache_r="$_ht_r" \
			data.msgs="$_ht_n" data.last_msg="$_ht_l" ${_ht_s:+data.out_snapshot="$_ht_s"} "$@"
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
# business (the kit's ADR-0008 clause 8) — so the only reader of TRACE_TOOLS is the hook
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

# hook_dir — the resolved trace directory; nothing, status 1, when tracing is
# off; nothing, status 2, when the ask itself fails — a policy file the shared
# script refuses, or a shared script that could not run at all. Asked
# of the shared script itself, which is the only thing that knows how a relative
# policy value resolves against the root checkout.
#
# OFF IS NOT AN ERROR, AND AN ERROR IS NOT OFF. Off is the documented no-op and
# is said nowhere (rule 3). A refused policy file is the shared script's error,
# and its own line reaches the hook's stderr untouched, the way an emit's would
# (rule 1 keeps the exit 0, the kit's ADR-0008 clause 4 keeps it loud) — so a session
# hook that stops at the ask still says why (H-1, review of PR #518). The tool
# hooks, which run on every tool call, discard it at their own call site.
#
# ASK IT ONCE. There is no cache here on purpose: a caller reads this through a
# command substitution, so anything remembered inside would be remembered in a
# subshell and thrown away — a cache that cannot work, paid for on every tool
# call (M-4, review of PR #295). So each hook asks once, before anything else
# that would spawn a process for the trace, and hands the answer to every
# helper that needs it as that helper's first argument; no helper here asks
# again (#463). With tracing off the hook has its answer, and the trace work
# after it spawns nothing, git included: the end and the stop hooks stop there,
# and the start hook skips its event and pointer and carries on to the export.
hook_dir() {
	_hd_dir=$(cd "$hook_repo" && sh scripts/trace.sh dir) || return 2
	[ -n "$_hd_dir" ] || return 1
	printf '%s' "$_hd_dir"
}

# --- waiting for a subagent's final message ---------------------------------
# Read only by subagent-stop.sh. SubagentStop can run BEFORE the subagent's
# transcript holds its final assistant line (ticket #308 measured the line
# landing 170 and 223 ms after the hook began, in two of seven live stops), and
# a transcript read then either has no usage at all or — worse — holds the turns
# before the last one, whose sum is a confident undercount. So the hook may
# wait, for as long as the policy says — and past it by at most one poll, which
# under a `sleep` that refuses fractions is one whole-second nap (see below).

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
# 0 for yes, with hook_final_by set to how it ended: `message` or `tool`.
#
# FINAL means: its last user-or-assistant line is an ASSISTANT line whose
# stop_reason is set and is not tool_use (by `message`) — or a USER line the
# agent harness marks `"toolEndsTurn":true` (by `tool`, #565). The second is
# how most subagent runs end: the run's last act is a call to a tool that ends
# it (the agent harness's hand-back), the harness writes that call's result as
# a user line carrying the flag, and NO assistant line follows, ever — so a
# wait for one ran out at any bound (the kit's ADR-0008, the #565 amendment). The tool
# call's own line is written mid-stream, stop_reason null, so its usage block
# is the streamed snapshot; `data.final=tool` on the event says so. A flag
# followed by the prompt that resumed the agent is not final, by the rule
# below. Each half of the first rule is load-bearing. "Last user
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
# `stop_reason` — or a `"toolEndsTurn":true` — would read as final. Nothing
# observed writes such a result; if one ever does, the cost is one early read,
# which the extractor then sums. A result's TEXT quoting the flag is escaped,
# `\"toolEndsTurn\"`, and cannot match.
hook_final() {
	hook_final_by=
	_hf_last=$(grep -E '"type"[[:space:]]*:[[:space:]]*"(user|assistant)"' "$1" 2>/dev/null | tail -n 1)
	if printf '%s\n' "$_hf_last" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"user"'; then
		printf '%s\n' "$_hf_last" | grep -Eq '"toolEndsTurn"[[:space:]]*:[[:space:]]*true' || return 1
		hook_final_by=tool
		return 0
	fi
	printf '%s\n' "$_hf_last" | grep -Eq '"type"[[:space:]]*:[[:space:]]*"assistant"' || return 1
	printf '%s\n' "$_hf_last" | grep -Eq '"stop_reason"[[:space:]]*:[[:space:]]*"' || return 1
	printf '%s\n' "$_hf_last" | grep -Eq '"stop_reason"[[:space:]]*:[[:space:]]*"tool_use"' && return 1
	hook_final_by=message
	return 0
}

# hook_now_ms [<file>] — the wall clock in milliseconds, or with a file its
# last modification; status 1 where `date` has no sub-second field. `%N` is not
# POSIX: GNU date answers it, and a date that does not leaves a letter behind,
# which the digit check turns into "no clock".
hook_now_ms() {
	if [ -n "${1:-}" ]; then
		_nm=$(date -r "$1" +%s%N 2>/dev/null) || return 1
	else
		_nm=$(date +%s%N 2>/dev/null) || return 1
	fi
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
# check comes last before giving up, and the overshoot is at most one poll —
# 50 ms and a check, or one whole-second nap and a check where `sleep` refuses
# fractions.
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
# whole-second naps while the naps already taken leave a whole second of the
# bound unspent. THE NAPS ARE WEIGHED AGAINST THE BOUND, THE CHECKS ARE NOT:
# whether a whole second fits is decided on the naps already taken, never on
# what a check cost, so a 1000 ms bound naps its second whatever the first
# check cost. In whole-second mode the wait therefore reaches the bound and may
# overrun it by at most one whole-second nap and a check — a `sleep` that
# refuses fractions cannot trim a nap to what is left. A bound under 1000 ms
# cannot be served by a whole-second sleep at all, and returns without a nap.
# The clock still ends the wait once the bound has passed. Never a busy loop.
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
			_hw_unspent=$(($2 - _hw_count))
			[ "$_hw_unspent" -ge 1000 ] || break
			sleep 1
			_hw_nap=1000
		fi
		_hw_count=$((_hw_count + _hw_nap))
		[ -n "$_hw_t0" ] || _hw_waited=$_hw_count
	done
	printf '%s' "$_hw_waited"
	return 1
}

# hook_tail_facts <transcript> — what a wait that ran out of bound can still
# say about the transcript, for the event that records it (ticket #387): sets
# hook_last_kind to its last line's top-level `type`, as the agent harness
# names it; hook_last_age_ms to how old that line is NOW, in milliseconds; and
# hook_lines to how many non-empty lines it holds. Each is left empty when it
# cannot be read, and the caller then names fewer keys — never a guess. A young
# last line says the bound was too short for an agent still writing; an old one
# says the agent stopped without a final message.
#
# THE TOP-LEVEL TYPE, NOT THE FIRST OR LAST ONE ON THE LINE. A transcript line
# nests objects that carry a `type` of their own — a content block, an
# attachment body, a tool's structured result — on either side of the line's
# own key, so neither a first nor a greedy last match answers. The awk below
# walks the line's characters once, keeping track of string and nesting depth,
# and takes the string value of a `type` key at depth one. Quoted text cannot
# fool it: a brace inside a string is skipped with the string, and a quote
# inside one is escaped. The answer is kept only if it is a plain word — it is
# data from a file a model wrote into, headed for the trace.
#
# THE AGE IS THE FILE'S: the agent harness appends a line at a time, so the
# last modification is the last line landing, and reading the mtime asks
# nothing of the line's own timestamp format. `date -r <file>` gives it on GNU
# and BSD date alike; milliseconds where `%N` answers, whole seconds otherwise.
hook_tail_facts() {
	hook_last_kind=
	hook_last_age_ms=
	hook_lines=
	_tf=$(awk '
		NF { n++; last = $0 }
		END {
			printf "%d ", n
			len = length(last); d = 0; ins = 0; esc = 0; st = 0; key = ""; want = 0
			for (i = 1; i <= len; i++) {
				c = substr(last, i, 1)
				if (ins) {
					if (esc) { esc = 0; continue }
					if (c == "\\") { esc = 1; continue }
					if (c == "\"") {
						ins = 0
						if (d == 1) {
							s = substr(last, st, i - st)
							if (want) { printf "%s", s; exit }
							key = s
						}
					}
					continue
				}
				if (c == "\"") { ins = 1; st = i + 1; continue }
				if (c == "{" || c == "[") { d++; want = 0; key = ""; continue }
				if (c == "}" || c == "]") { d--; continue }
				if (d == 1 && c == ":") { want = (key == "type"); key = ""; continue }
				if (d == 1 && c == ",") { want = 0; key = ""; continue }
			}
		}' "$1" 2>/dev/null) || _tf=
	hook_lines=${_tf%% *}
	case $hook_lines in '' | *[!0-9]*) hook_lines= ;; esac
	_tf_kind=${_tf#* }
	[ "$_tf_kind" != "$_tf" ] && [ "${#_tf_kind}" -le 60 ] && hook_id_ok "$_tf_kind" &&
		hook_last_kind=$_tf_kind
	_tf_now=$(hook_now_ms) || _tf_now=
	if ! _tf_m=$(hook_now_ms "$1") || [ -z "$_tf_now" ]; then
		_tf_m=$(date -r "$1" +%s 2>/dev/null) || _tf_m=
		case $_tf_m in '' | *[!0-9]*) return 0 ;; esac
		_tf_m=$((_tf_m * 1000))
		_tf_now=$(($(date +%s) * 1000))
	fi
	hook_last_age_ms=$((_tf_now - _tf_m))
	[ "$hook_last_age_ms" -ge 0 ] || hook_last_age_ms=0
	return 0
}

# --- how far this checkout is behind main -----------------------------------
# Read only by session-start.sh (ticket #384, retro 20261001T150216Z finding
# G1). A hook runs the code of the checkout it LIVES in, and the kit's own sat
# ~140 commits behind main for four hours with nothing saying so: every adapter
# fix the wave had landed was inert for the trace that should have shown it.

# hook_root — the ROOT checkout: the working tree of git's common directory,
# the derivation scripts/trace.sh and scripts/worktree-cleanup.sh use. From a
# linked worktree that is the main checkout, not the worktree; from the main
# checkout it is itself. Nothing (status 1) when git does not answer.
#
# WHY THE ROOT AND NOT THIS CHECKOUT. The kit's hooks execute from the root
# checkout, and a session opened in worktree/<slug> sits on a feature branch
# where being behind main is normal and says nothing about the code the hooks
# run (review of PR #390, Axis 2 item 3).
hook_root() {
	_hr=$(hook_common_dir "$hook_repo") || return 1
	dirname "$_hr"
}

# hook_common_dir <dir> — the absolute path of git's common directory for the
# checkout <dir> is in, or nothing (status 1) when git does not answer. The ONE
# spelling of that lookup: hook_root derives the root checkout from it, and
# hook_run_of compares two checkouts' answers to tell one repository from
# another. GIT_DIR and GIT_WORK_TREE are scrubbed for hook_pointer's reason.
hook_common_dir() {
	_hcd=$( (unset GIT_DIR GIT_WORK_TREE &&
		git -C "$1" rev-parse --path-format=absolute --git-common-dir) 2>/dev/null ) || return 1
	[ -n "$_hcd" ] || return 1
	printf '%s' "$_hcd"
}

# hook_behind <root> — how many commits the last FETCHED origin/main holds that
# <root>'s HEAD does not, or nothing (status 1) when there is no origin/main,
# no repository, or no git.
#
# NEVER THE NETWORK. A hook is on the session's critical path, so this reads
# the remote-tracking ref as the last fetch left it and never fetches: the
# count is "behind what this machine last saw", which is the honest claim.
# GIT_NO_LAZY_FETCH keeps a partial clone from fetching a missing object behind
# the walk's back; GIT_DIR and GIT_WORK_TREE are scrubbed for hook_pointer's
# reason.
hook_behind() {
	_hb=$( (unset GIT_DIR GIT_WORK_TREE &&
		GIT_NO_LAZY_FETCH=1 git -C "$1" rev-list --count HEAD..refs/remotes/origin/main) 2>/dev/null ) || return 1
	case $_hb in '' | *[!0-9]*) return 1 ;; esac
	printf '%s' "$_hb"
}

# hook_behind_warn <count> <root> — say once on stderr that the root checkout
# <root> is <count> behind, when TRACE_BEHIND_WARN names a threshold and <count> is MORE than it.
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
	_bw_note=$(printf '%s is %s commits behind origin/main as last fetched (TRACE_BEHIND_WARN=%s) — the hooks run the code it holds; sync it' \
		"$2" "$1" "$_bw")
	printf '! session-start: %s\n' "$_bw_note" >&2
	hook_say_session "$_bw_note"
}

# hook_json_str <text> — <text> as the inside of a JSON string: backslash and
# double quote escaped, every control character dropped. A root path is data
# and may hold any of them; one that broke the object would silence the note.
hook_json_str() {
	printf '%s' "$1" | tr -d '\000-\037\177' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# hook_say_session <note> — the ONE thing a hook here prints on stdout (rule 2's
# exception, ticket #427): a single JSON object the agent harness parses on exit
# 0, carrying <note> twice. `systemMessage` is the field the hooks reference
# documents as shown to the user — an interactive session prints it under its
# banner; `hookSpecificOutput.additionalContext` goes to the model, which relays
# it — the only route that reaches a non-interactive run's output. stderr on
# exit 0 reaches neither (the live probe of 2.1.285, adapter README).
hook_say_session() {
	_hs=$(hook_json_str "$1")
	printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s Tell the operator this in your first reply."}}\n' \
		"$_hs" "$_hs"
}

# --- the phantom-stop count ---------------------------------------------------
# A phantom stop writes no event (subagent-stop.sh, ticket #344), but how many
# there were is still worth knowing (ticket #410): the subagent-stop hook adds
# one line to a per-session counter, and the session-end hook records the count
# as data.phantoms on session.end. The counter lives in a directory this
# adapter owns under the trace, claude-code/<session id>.phantoms, so two
# sessions never share one — and never in current/, whose layout the shared
# script keeps to itself (review of PR #432, M-1).

# hook_phantom_add <trace dir> <session id> — one more phantom for that
# session. APPEND, one short line per stop: an O_APPEND write of a few bytes
# lands whole, so two stops at once both count and neither needs a lock.
# Nothing when <trace dir> is empty (tracing is off) or the id is not one
# hook_id_ok accepts — a counter keyed by a refused id would be a path built
# from payload data.
hook_phantom_add() {
	[ -n "${1:-}" ] && hook_id_ok "${2:-}" || return 0
	mkdir -p "$1/claude-code" 2>/dev/null || return 0
	echo . >>"$1/claude-code/$2.phantoms" 2>/dev/null || :
}

# hook_phantom_take <trace dir> <session id> — print that session's count, 0
# when it had none, and remove its counter; print nothing (status 1) when
# <trace dir> is empty (tracing is off) or the id is refused. TAKEN, not read:
# a resumed session keeps its id and ends again, and its next end must count
# only the stops after this one — the same reason session-end.sh anchors its
# usage read (#307). The counter is RENAMED aside before it is counted, so a
# stop landing during the end starts a fresh counter for the next end rather
# than being counted and then deleted.
hook_phantom_take() {
	[ -n "${1:-}" ] && hook_id_ok "${2:-}" || return 1
	_hp_file="$1/claude-code/$2.phantoms"
	_hp_n=0
	if [ -f "$_hp_file" ] && mv "$_hp_file" "$_hp_file.$$" 2>/dev/null; then
		_hp_n=$(wc -l <"$_hp_file.$$" | tr -d ' ')
		rm -f "$_hp_file.$$"
		case $_hp_n in '' | *[!0-9]*) _hp_n=0 ;; esac
	fi
	printf '%s' "$_hp_n"
}

# --- the pending marker: a denied tool call -----------------------------------
# A tool call the permission system or a blocking hook refuses fires PreToolUse
# and nothing after it, so tool-post.sh never sees it (ticket #409; reproduced
# on claude 2.1.278, see tool-post.sh). The pre-tool hook therefore leaves a
# marker per call, the post-tool hook removes it, and the session-end hook
# sweeps what is left into one `tool.use outcome=denied` each. The markers live
# in the directory this adapter owns under the trace, beside the phantom
# counters: claude-code/<session id>.pending/<tool-use id>, holding the tool's
# name on its first line and the input head on its second. Per session, so an
# end never sweeps a call another session still has running.

# hook_pending_ok <id> — may this id name a marker's directory or file? The
# identifier class, the line's length bound tool-post.sh holds a join column
# to, and no leading dot: `.` and `..` are in the class and are not names.
hook_pending_ok() {
	hook_id_ok "${1:-}" || return 1
	[ "${#1}" -le 256 ] || return 1
	case $1 in .*) return 1 ;; esac
	return 0
}

# hook_pending_add <trace dir> <session id> <tool-use id> <tool> <head file> —
# leave the call's marker, owner-only (the head is the command's own text, the
# reason tool-payload.mjs stages owner-only). Nothing at all for an id or a
# tool name that is refused: a marker keyed by a refused id would be a path
# built from payload data.
hook_pending_add() {
	hook_pending_ok "${2:-}" && hook_pending_ok "${3:-}" && hook_id_ok "${4:-}" || return 0
	mkdir -p "$1/claude-code/$2.pending" 2>/dev/null || return 0
	(
		umask 077
		{
			printf '%s\n' "$4"
			cat "$5" 2>/dev/null
			printf '\n'
		} >"$1/claude-code/$2.pending/$3"
	) 2>/dev/null || :
	return 0
}

# hook_pending_drop <trace dir> <session id> <tool-use id> — the call returned,
# so it was not denied: remove its marker, if it has one.
hook_pending_drop() {
	hook_pending_ok "${2:-}" && hook_pending_ok "${3:-}" || return 0
	rm -f "$1/claude-code/$2.pending/$3" 2>/dev/null || :
	return 0
}

# hook_pending_sweep <trace dir> <session id> [<field>=<value> …] — one
# `tool.use outcome=denied` per marker that session left, each carrying the
# fields after the id (the session-end hook's subject and session), then the markers gone.
# TAKEN, the way hook_phantom_take takes its counter: the directory is renamed
# aside first, so a resumed session's next end sweeps only what came after this
# one, and a marker landing during the end waits for that next end.
#
# AND WHAT AN EARLIER END TOOK ASIDE AND NEVER FINISHED. The sweep spawns one
# emit per marker, so an end killed mid-loop leaves <sid>.pending.<pid>
# behind; every directory of that shape for this session is swept here too,
# so no denial is lost to an interrupted end (review of PR #446, M-1).
hook_pending_sweep() {
	[ -n "${1:-}" ] && hook_pending_ok "${2:-}" || return 0
	_ps_d="$1/claude-code/$2.pending"
	shift 2
	[ -d "$_ps_d" ] && { mv "$_ps_d" "$_ps_d.$$" 2>/dev/null || :; }
	for _ps_t in "$_ps_d".*; do
		[ -d "$_ps_t" ] || continue
		hook_pending_take "$_ps_t" "$@"
	done
	return 0
}

# hook_pending_take <taken directory> [<field>=<value> …] — one denial per
# marker in a directory the sweep took aside, then the directory gone.
hook_pending_take() {
	_pt_d=$1
	shift
	for _ps_f in "$_pt_d"/*; do
		[ -f "$_ps_f" ] || continue
		_ps_id=${_ps_f##*/}
		hook_pending_ok "$_ps_id" || continue
		_ps_tool=$(sed -n '1p' "$_ps_f" 2>/dev/null)
		hook_id_ok "$_ps_tool" || _ps_tool=unknown
		hook_trace emit kind=tool.use harness=claude-code outcome=denied \
			data.tool="$_ps_tool" data.tool_use_id="$_ps_id" \
			data.input_head="$(sed -n '2p' "$_ps_f" 2>/dev/null)" \
			reason='the call fired its pre-tool hook and no post-tool hook before the session ended: the permission system or a blocking hook refused it' "$@"
	done
	rm -rf "$_pt_d" 2>/dev/null || :
	return 0
}
