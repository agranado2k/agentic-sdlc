#!/bin/sh
# trace.sh — THE decision trace. One implementation, every caller.
#
#   sh scripts/trace.sh emit kind=<kind> [subject=<type:ref>] [related='<type:ref> …']
#                            [<field>=<value> …] [data.<key>=<value> …]
#                            [--blob <file>|-] [--dry-run]
#   sh scripts/trace.sh begin <skill> [subject=<type:ref>] [<field>=<value> …]
#   sh scripts/trace.sh end [outcome=<outcome>] [reason=<text>] [<field>=<value> …]
#   sh scripts/trace.sh show <type:ref> [--since YYYY-MM-DD] [--kind <kind>]
#   sh scripts/trace.sh verify [--since YYYY-MM-DD]
#   sh scripts/trace.sh dir
#
# WHAT IT IS. Every decision the chain makes — a tier stamped, a model resolved,
# a finding raised or rejected, a PR iterated, a merge landed — is one JSON line
# appended to a per-day file under the trace directory. The chain writes it and
# never reads it (shared invariant §4: a reviewer must not see implementation
# history); the operator, a diagnosis and a retrospective read it after the
# fact. ADR-0008 is the record; PRD #237 the design.
#
# STREAMS AND EXIT CODES. stdout carries the answer and nothing else — `dir`
# prints the resolved directory, `begin` the run id it just opened, `show` the
# matching lines, `emit --dry-run` the line it would append; a successful
# `emit` and a successful `end` print nothing. Every diagnostic is
# on stderr, prefixed `trace:`. Exit 0 is done, INCLUDING the unconfigured
# no-op; exit 2 is a usage error, an unknown kind, a malformed subject or value,
# or a policy file named explicitly and missing; exit 1 comes from `verify`
# alone and is its verdict.
#
# UNCONFIGURED IS A WORKING STATE. The policy file scripts/trace.config.sh ships
# with TRACE_DIR empty, and an empty TRACE_DIR means every emit exits 0 having
# written nothing, after one note on stderr (TRACE_QUIET=1 silences it — hooks
# set that). This is the arrangement the guards and the tiers have: mechanism
# is shared, the decision to trace is the consumer's, and the kit's own answer
# lives in a never-shipped twin reached through the TRACE_CONFIG seam.
#
# POLICY DISCOVERY, first hit wins — anchored on where THIS FILE lives, never
# on the caller's cwd, for the reason scripts/agents.lib.sh gives: a policy
# file is sourced, which is to say executed, and standing in a foreign clone
# must never run its code as you.
#   1. $TRACE_CONFIG            — explicit; set and missing is exit 2.
#   2. <this file's repo root>/scripts/trace.config.sh
#   3. <this file's directory>/trace.config.sh
# An environment TRACE_DIR beats the file's: that is how a suite points the
# script at scratch, and how an operator keeps the trace outside the tree.
#
# WHERE THE DIRECTORY IS. A relative TRACE_DIR resolves against the ROOT
# CHECKOUT, found through git's common directory — the same derivation
# scripts/worktree-cleanup.sh uses — so an emit from inside a linked worktree
# lands beside the root's .git, and pruning the worktree loses nothing. An
# absolute value is taken as given. Outside any repository a relative value
# resolves against this file's parent directory.
#
# THE LINE. Fields in a fixed order, absent optionals omitted, no nulls:
#   v ts id kind · skill subject related session run parent · tier domain
#   harness model · outcome reason · tok_in tok_out tok_cache_w tok_cache_r ·
#   blob · data
# `kind` is a CLOSED vocabulary (an unknown one is exit 2, like an unknown
# tier); `data.*` keys are OPEN (like task domains), string values only. A
# subject is `<type>:<reference>` — lowercase type, then anything without a
# space, a quote or a backslash — so a PRD, a ticket, a PR, a branch, a
# session and a run all join on one column. Token counts are bare integers.
# A value may not carry a control character other than a tab: a multi-line
# payload is a blob, not a field.
#
# Craft §11: an event is one `printf` of one short line to an append-mode
# descriptor, and nothing here ever truncates a file it did not create. The
# 4000-byte CAP is that single write made checkable — an event over it is
# refused at emit, with the refusal pointing at --blob, rather than split
# across two writes that a parallel emit could interleave.
#
# A RUN IS A SKILL INVOCATION, and `begin`/`end` are its two ends: `begin`
# prints a fresh run id, appends run.start and pushes the run onto a stack
# under the trace directory; `end` pops it and appends run.end with the
# outcome. Every emit in between carries that run without being told, and a
# nested `begin` carries the outer run as its `parent`. Identity's precedence
# is an explicit field, then TRACE_SESSION / TRACE_RUN / TRACE_PARENT in the
# environment (how a dispatched worker is told whose trail it joins), then the
# pointer file and the run stack, then the field is omitted. The stack is
# per-working-tree, and `begin` and `end` are its only writers — an emit never
# touches it, so fifty parallel sub-agents only ever append.
#
# A BLOB IS A PAYLOAD THAT DOES NOT FIT ON A LINE — a prompt, a tool result,
# spike evidence. `--blob <file>` (or `-` for standard input) stores it under
# blobs/<first two of the hash>/<hash>, named by GIT's own content hash, and
# the event carries the hash and the byte count. Identical content is stored
# once and never rewritten; the write is staged and lands by rename.
#
# SCHEMA, a file in the trace directory, names the version of the lines under
# it. `verify` refuses a trace whose schema it does not know rather than
# reporting every line as malformed.
#
# Shared layer (see VERSION): copied verbatim, not edited downstream. Your
# policy goes in scripts/trace.config.sh.

set -u

_trace_here=$(cd "$(dirname "$0")" && pwd -P)

TRACE_SCHEMA=1
TRACE_EVENT_CAP=4000
TRACE_KINDS='session.start session.end session.usage agent.stop tool.use run.start run.end spawn spawn.end prd.write ticket.write ticket.start tdd.cycle review.verdict finding.raise finding.triage pr.open pr.iterate merge.land hypothesis spike.verdict brief.decide housekeeping.finding worktree.prune grill.decision note'
TRACE_STRING_FIELDS='skill subject related session run parent tier domain harness model outcome reason'
TRACE_TOKEN_FIELDS='tok_in tok_out tok_cache_w tok_cache_r'

usage() {
	cat >&2 <<'USAGE'
usage: sh scripts/trace.sh emit kind=<kind> [subject=<type:ref>] [<field>=<value> …] [data.<key>=<value> …] [--blob <file>|-] [--dry-run]
       sh scripts/trace.sh begin <skill> [subject=<type:ref>] [<field>=<value> …]
       sh scripts/trace.sh end [outcome=<outcome>] [reason=<text>] [<field>=<value> …]
       sh scripts/trace.sh show <type:ref> [--since YYYY-MM-DD] [--kind <kind>]
       sh scripts/trace.sh verify [--since YYYY-MM-DD]
       sh scripts/trace.sh dir
USAGE
	exit 2
}

die() {
	echo "x trace: $*" >&2
	exit 2
}

# ---------------------------------------------------------------------------
# Policy and the directory.

# trace_git <args…> — git asked about THIS FILE's repository, with the
# inherited repository-selection variables scrubbed. Git exports GIT_DIR (and
# GIT_WORK_TREE) into hooks, and a caller that inherits a pinned pair would
# make `git -C` answer for the pinned repository — so an anchored lookup that
# trusted the environment could source a foreign checkout's policy file. The
# guards loader scrubs the same two for the same reason.
trace_git() {
	(unset GIT_DIR GIT_WORK_TREE && git -C "$_trace_here" "$@") 2>/dev/null
}

trace_load_config() {
	# Set-or-unset is remembered separately from the value: TRACE_DIR='' in
	# the environment is the documented OFF, and must win over a policy file
	# that turns tracing on.
	_tl_env_set=${TRACE_DIR+set}
	_tl_env_dir=${TRACE_DIR:-}
	if [ -n "${TRACE_CONFIG:-}" ]; then
		[ -f "$TRACE_CONFIG" ] || die "TRACE_CONFIG=$TRACE_CONFIG does not exist."
		. "$TRACE_CONFIG"
	else
		_tl_root=$(trace_git rev-parse --show-toplevel) || _tl_root=
		if [ -n "$_tl_root" ] && [ -f "$_tl_root/scripts/trace.config.sh" ]; then
			. "$_tl_root/scripts/trace.config.sh"
		elif [ -f "$_trace_here/trace.config.sh" ]; then
			. "$_trace_here/trace.config.sh"
		fi
	fi
	# The environment wins over the file — set on its own line after the
	# source, so a policy file that assigns TRACE_DIR cannot undo it, even
	# when what the environment said was "off".
	[ -n "$_tl_env_set" ] && TRACE_DIR=$_tl_env_dir
	return 0
}

# trace_dir — sets TRACE_ROOT_DIR to the resolved directory, or returns 1 when
# tracing is off. Never creates anything.
trace_dir() {
	case ${TRACE_DIR:-} in
	'') return 1 ;;
	/*) TRACE_ROOT_DIR=$TRACE_DIR ;;
	*)
		_td_common=$(trace_git rev-parse --path-format=absolute --git-common-dir) || _td_common=
		if [ -n "$_td_common" ]; then
			_td_base=$(dirname "$_td_common")
		else
			_td_base=$(cd "$_trace_here/.." && pwd -P)
		fi
		TRACE_ROOT_DIR="$_td_base/$TRACE_DIR"
		;;
	esac
	return 0
}

trace_unconfigured_note() {
	[ "${TRACE_QUIET:-}" = 1 ] && return 0
	echo "!  trace: unconfigured — set TRACE_DIR in scripts/trace.config.sh to record decisions; nothing was written." >&2
}

# ---------------------------------------------------------------------------
# Grammar.

# trace_is_kind <value> — membership in the closed vocabulary, one entry at a
# time: a value with a space in it ("run.start run.end") is contiguous text
# inside the list and must not pass as a member.
trace_is_kind() {
	case $1 in '' | *' '*) return 1 ;; esac
	case " $TRACE_KINDS " in *" $1 "*) return 0 ;; esac
	return 1
}

# trace_check_token <value> — a field or data key: [a-z][a-z0-9_]*. Checked
# BEFORE any membership test or eval, so a key with a space in it is refused
# as a key and never reaches the list or the assignment.
trace_check_token() {
	case $1 in '' | [!a-z]* | *[!a-z0-9_]*) return 1 ;; esac
	return 0
}

# trace_check_subject <value> — `<type>:<reference>`: a lowercase type, a
# colon, then a non-empty reference with no space, quote or backslash (the
# three characters that would make the exact-match filter in `show` a
# question rather than a comparison).
trace_check_subject() {
	case $1 in *' '* | *'"'* | *'\'* | '') return 1 ;; esac
	_cs_type=${1%%:*}
	_cs_ref=${1#*:}
	[ "$_cs_ref" = "$1" ] && return 1
	[ -z "$_cs_ref" ] && return 1
	case $_cs_type in '' | *[!a-z]*) return 1 ;; esac
	return 0
}

# trace_json_str <value> — prints the JSON string body, without the quotes.
# Escapes backslash, double quote and tab; REFUSES (return 1) every other
# control character, newline included. The awk alternative was rejected
# because gsub's replacement-string backslash handling differs between awks;
# POSIX sed's `s/\\/\\\\/g` does not.
_trace_nl=$(printf '\nx')
_trace_nl=${_trace_nl%x}
_trace_tab=$(printf '\t')
trace_json_str() {
	case $1 in *"$_trace_nl"*) return 1 ;; esac
	_js_rest=$(printf '%s' "$1" | tr -d '\t')
	case $_js_rest in *[[:cntrl:]]*) return 1 ;; esac
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/${_trace_tab}/\\\\t/g"
}

trace_id() {
	_ti_rand=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
	[ -n "$_ti_rand" ] || _ti_rand=$(awk 'BEGIN { srand(); printf "%08x", int(rand() * 4294967295) }')
	printf '%s-%s-%s' "$(date -u +%Y%m%dT%H%M%SZ)" "$$" "$_ti_rand"
}

# ---------------------------------------------------------------------------
# Identity: the session, the run, and the run this one nests inside.
#
# PRECEDENCE, most specific answer first — an explicit field on the emit, then
# the environment, then this working tree's pointer file and run stack, then
# the field is omitted. A missing identity is a FACT, not an error: a bare emit
# from a hook belongs to no run, and saying so is the honest line.
#
# WHY PER WORKING TREE. The trace directory is the root checkout's and every
# worktree appends to it, so one shared stack would interleave two sessions'
# runs. The pointer file and the stack sit under a key derived from the
# toplevel THIS SCRIPT lives in — git's hash of that path, the same hash the
# blob store names payloads by, so there is one hashing mechanism here.
#
# WHY ONLY begin AND end WRITE THE STACK. Fifty parallel sub-agents all emit;
# an emit that touched the stack would make fifty writers race over one file.
# An emit only appends to the day's event file, and both stack writers replace
# the file by RENAME, so a concurrent reader sees one whole stack or the other.
# The stack's OWNER is a skill's main thread, one begin and one end at a time;
# two concurrent begins in the same working tree would still lose a push, which
# is why a parallel worker is handed TRACE_RUN instead of opening a run here.

# trace_hash_stdin / trace_hash_file <path> — git's content hash. `--stdin` for
# both: it applies no attribute filter, so the name a payload gets here is the
# name `git hash-object` gives it anywhere, and a path is never parsed as an
# option. GIT_DIR and GIT_WORK_TREE are scrubbed for trace_git's reason.
trace_hash_stdin() { (unset GIT_DIR GIT_WORK_TREE && git hash-object --stdin) 2>/dev/null; }
trace_hash_file() { (unset GIT_DIR GIT_WORK_TREE && git hash-object --stdin <"$1") 2>/dev/null; }

# trace_key — sets TRACE_KEY, TRACE_POINTER and TRACE_STACK for this working
# tree. Needs TRACE_ROOT_DIR. Returns 1 when git cannot hash the path, which
# leaves identity to the environment alone rather than failing an emit.
trace_key() {
	_tk_top=$(trace_git rev-parse --show-toplevel) || _tk_top=
	[ -n "$_tk_top" ] || _tk_top=$(cd "$_trace_here/.." && pwd -P)
	TRACE_KEY=$(printf '%s' "$_tk_top" | trace_hash_stdin)
	[ -n "$TRACE_KEY" ] || return 1
	TRACE_POINTER="$TRACE_ROOT_DIR/current/$TRACE_KEY"
	TRACE_STACK="$TRACE_ROOT_DIR/current/$TRACE_KEY.runs"
	return 0
}

trace_first_line() {
	[ -f "$1" ] && sed -n '1p' "$1"
	return 0
}

# trace_stack top|below — the run at the top of this working tree's stack, or
# the one under it, which is the top's parent. Empty when there is none.
trace_stack() {
	[ -f "$TRACE_STACK" ] || return 0
	awk -v want="$1" '{ below = top; top = $0 } END {
		if (want == "top") print top
		else if (NR >= 2) print below
	}' "$TRACE_STACK"
	return 0
}

# trace_identity — sets _id_session, _id_run and _id_parent from the
# environment, then from the pointer file and the stack, then leaves them
# empty. An explicit field on the emit is applied by the caller, on top.
trace_identity() {
	_id_session=${TRACE_SESSION:-}
	_id_run=${TRACE_RUN:-}
	_id_parent=${TRACE_PARENT:-}
	[ -n "${TRACE_ROOT_DIR:-}" ] || return 0
	trace_key || return 0
	[ -n "$_id_session" ] || _id_session=$(trace_first_line "$TRACE_POINTER")
	# The stack answers run and parent TOGETHER or not at all: a worker whose
	# run came from the environment belongs to another process's trail, and
	# borrowing this working tree's stack for its parent would invent an edge.
	if [ -z "$_id_run" ]; then
		_id_run=$(trace_stack top)
		[ -n "$_id_parent" ] || _id_parent=$(trace_stack below)
	fi
	return 0
}

# trace_push <run id> / trace_pop — the ONLY two writers of the run stack, and
# both write by RENAME: the new stack is staged beside the old one and replaces
# it in one step, so a parallel emit reading the stack sees one whole stack or
# the other and never a partial file. Nothing here appends to it in place.
trace_push() {
	mkdir -p "$(dirname "$TRACE_STACK")" || die "cannot create $(dirname "$TRACE_STACK")"
	_ps_stage="$TRACE_STACK.$$"
	{
		[ -f "$TRACE_STACK" ] && cat "$TRACE_STACK"
		printf '%s\n' "$1"
	} >"$_ps_stage" || die "cannot stage the run stack at $_ps_stage"
	mv "$_ps_stage" "$TRACE_STACK" || die "cannot replace the run stack at $TRACE_STACK"
}

trace_pop() {
	_pp_stage="$TRACE_STACK.$$"
	sed '$d' "$TRACE_STACK" >"$_pp_stage" || die "cannot stage the run stack at $_pp_stage"
	mv "$_pp_stage" "$TRACE_STACK" || die "cannot replace the run stack at $TRACE_STACK"
}

# ---------------------------------------------------------------------------
# Blobs: a payload that does not fit on a line, stored once by content hash.

# The scratch copy of a payload that arrived on standard input, removed however
# this process ends — the cap can refuse the line after the payload was staged.
_trace_blob_tmp=
trace_cleanup() {
	[ -n "$_trace_blob_tmp" ] && rm -f "$_trace_blob_tmp"
	return 0
}
trap trace_cleanup EXIT INT TERM HUP

# trace_blob_name <path|-> — NAMES the payload without storing it: sets
# TRACE_BLOB to git's hash of its content, TRACE_BLOB_BYTES to its size and
# TRACE_BLOB_SRC to the file to store. Naming is a read, so the line can be
# assembled and checked against the cap before anything is written.
trace_blob_name() {
	_bn_src=$1
	if [ "$_bn_src" = - ]; then
		# Staged on the same filesystem as the blob store when there is one,
		# so the store below is a rename rather than a second copy. Asked of
		# TRACE_ROOT_DIR rather than of the caller: the helper then holds no
		# opinion about who called it or what that caller called the answer.
		if [ -n "${TRACE_ROOT_DIR:-}" ]; then
			mkdir -p "$TRACE_ROOT_DIR/tmp" || die "cannot create $TRACE_ROOT_DIR/tmp"
			_trace_blob_tmp="$TRACE_ROOT_DIR/tmp/stdin.$$"
		else
			_trace_blob_tmp=$(mktemp "${TMPDIR:-/tmp}/trace-blob.XXXXXX") || die "cannot stage standard input"
		fi
		cat >"$_trace_blob_tmp" || die "cannot stage standard input at $_trace_blob_tmp"
		_bn_src=$_trace_blob_tmp
	else
		[ -f "$_bn_src" ] || die "--blob $_bn_src: no such file"
	fi
	TRACE_BLOB=$(trace_hash_file "$_bn_src")
	[ -n "$TRACE_BLOB" ] || die "--blob: git could not hash $_bn_src, and git's hash is the blob's name"
	TRACE_BLOB_BYTES=$(wc -c <"$_bn_src" | tr -d ' ')
	TRACE_BLOB_SRC=$_bn_src
}

# trace_blob_store — puts the payload at blobs/<first two>/<hash>, once. The
# store is content-addressed, so a payload already there is left EXACTLY as it
# is: identical content is stored once and nothing rewrites a stored blob
# (craft §11). The write is staged in the same tree and lands by rename, so a
# reader never opens half a payload.
trace_blob_store() {
	_bs_dest="$TRACE_ROOT_DIR/blobs/$(printf '%.2s' "$TRACE_BLOB")/$TRACE_BLOB"
	[ -f "$_bs_dest" ] && return 0
	mkdir -p "$(dirname "$_bs_dest")" "$TRACE_ROOT_DIR/tmp" || die "cannot create the blob store under $TRACE_ROOT_DIR"
	if [ "$TRACE_BLOB_SRC" = "$_trace_blob_tmp" ]; then
		mv "$_trace_blob_tmp" "$_bs_dest" || die "cannot move the payload into $_bs_dest"
		_trace_blob_tmp=
	else
		_bs_stage="$TRACE_ROOT_DIR/tmp/blob.$$"
		cp "$TRACE_BLOB_SRC" "$_bs_stage" && mv "$_bs_stage" "$_bs_dest" ||
			die "cannot store the payload at $_bs_dest"
	fi
	return 0
}

# trace_write_schema — the trace directory says which schema its lines are, so
# a reader that does not know that schema can refuse instead of guessing. It is
# written once, by rename, and never rewritten.
trace_write_schema() {
	[ -f "$TRACE_ROOT_DIR/SCHEMA" ] && return 0
	_ws_stage="$TRACE_ROOT_DIR/SCHEMA.$$"
	printf '%s\n' "$TRACE_SCHEMA" >"$_ws_stage" && mv "$_ws_stage" "$TRACE_ROOT_DIR/SCHEMA" ||
		die "cannot write $TRACE_ROOT_DIR/SCHEMA"
	return 0
}

# ---------------------------------------------------------------------------
# emit

trace_emit() {
	_em_dry=0
	_em_kind=
	_em_data=
	_em_blob_src=
	_em_on=0
	TRACE_BLOB=
	TRACE_BLOB_BYTES=
	TRACE_BLOB_SRC=
	for _em_f in $TRACE_STRING_FIELDS $TRACE_TOKEN_FIELDS; do eval "_em_v_$_em_f="; done

	# A while loop rather than a `for`, because --blob takes the NEXT argument
	# and a `for` cannot consume one.
	while [ $# -gt 0 ]; do
		_em_arg=$1
		shift
		case $_em_arg in
		--dry-run) _em_dry=1 ;;
		--blob)
			[ -z "$_em_blob_src" ] || die "one blob per event: a second --blob has nowhere to go"
			[ $# -ge 1 ] || die "--blob needs a file, or - to read the payload from standard input"
			_em_blob_src=$1
			shift
			;;
		--blob=*)
			[ -z "$_em_blob_src" ] || die "one blob per event: a second --blob has nowhere to go"
			_em_blob_src=${_em_arg#--blob=}
			[ -n "$_em_blob_src" ] || die "--blob needs a file, or - to read the payload from standard input"
			;;
		--*) usage ;;
		*=*)
			_em_key=${_em_arg%%=*}
			_em_val=${_em_arg#*=}
			case $_em_key in
			data.*) trace_check_token "${_em_key#data.}" || die "data key '${_em_key#data.}' is not [a-z][a-z0-9_]*" ;;
			*) trace_check_token "$_em_key" || die "field name '$_em_key' is not [a-z][a-z0-9_]*" ;;
			esac
			case $_em_key in
			kind)
				trace_is_kind "$_em_val" || die "unknown kind '$_em_val' — the vocabulary is closed: $TRACE_KINDS"
				_em_kind=$_em_val
				;;
			data.*)
				_em_sub=${_em_key#data.}
				_em_esc=$(trace_json_str "$_em_val") || die "data.$_em_sub carries a control character; a multi-line value is a blob, not a field, and --blob is a later slice."
				_em_data="${_em_data:+$_em_data,}\"$_em_sub\":\"$_em_esc\""
				;;
			*)
				case " $TRACE_STRING_FIELDS " in
				*" $_em_key "*)
					case $_em_key in
					subject) [ -z "$_em_val" ] || trace_check_subject "$_em_val" || die "subject '$_em_val' is not <type>:<reference>" ;;
					related)
						for _em_tok in $_em_val; do
							trace_check_subject "$_em_tok" || die "related token '$_em_tok' is not <type>:<reference>"
						done
						;;
					esac
					_em_esc=$(trace_json_str "$_em_val") || die "$_em_key carries a control character; a multi-line value is a blob, not a field, and --blob is a later slice."
					eval "_em_v_$_em_key=\$_em_esc"
					;;
				*)
					case " $TRACE_TOKEN_FIELDS " in
					*" $_em_key "*)
						case $_em_val in '' | *[!0-9]* | 0?*) die "$_em_key='$_em_val' is not a JSON integer — digits only, no leading zero" ;; esac
						eval "_em_v_$_em_key=\$_em_val"
						;;
					blob | blob_bytes) die "$_em_key is set by --blob <file>, never as a field — a blob's name is git's hash of what was stored, not the caller's claim" ;;
					*) die "unknown field '$_em_key' — a free key belongs under data.<key>" ;;
					esac
					;;
				esac
				;;
			esac
			;;
		*) usage ;;
		esac
	done
	[ -n "$_em_kind" ] || die "emit needs kind=<kind>"

	# The directory first: identity's fallbacks and the blob store both live in
	# it, and whether it resolves at all is what makes this emit a no-op.
	trace_dir && _em_on=1

	# Identity, least specific last: a field given on the command line stands,
	# anything it left empty is answered by the environment, then by this
	# working tree's pointer file and run stack.
	trace_identity
	for _em_f in session run parent; do
		eval "_em_cur=\${_em_v_$_em_f}"
		[ -n "$_em_cur" ] && continue
		eval "_em_v=\$_id_$_em_f"
		[ -n "$_em_v" ] || continue
		_em_esc=$(trace_json_str "$_em_v") || die "the $_em_f id carries a control character: '$_em_v'"
		eval "_em_v_$_em_f=\$_em_esc"
	done

	[ -n "$_em_blob_src" ] && trace_blob_name "$_em_blob_src"

	_em_line="{\"v\":1,\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"id\":\"$(trace_id)\",\"kind\":\"$_em_kind\""
	for _em_f in $TRACE_STRING_FIELDS; do
		eval "_em_v=\${_em_v_$_em_f}"
		[ -n "$_em_v" ] && _em_line="$_em_line,\"$_em_f\":\"$_em_v\""
	done
	for _em_f in $TRACE_TOKEN_FIELDS; do
		eval "_em_v=\${_em_v_$_em_f}"
		[ -n "$_em_v" ] && _em_line="$_em_line,\"$_em_f\":$_em_v"
	done
	[ -n "$TRACE_BLOB" ] && _em_line="$_em_line,\"blob\":\"$TRACE_BLOB\",\"blob_bytes\":$TRACE_BLOB_BYTES"
	[ -n "$_em_data" ] && _em_line="$_em_line,\"data\":{$_em_data}"
	_em_line="$_em_line}"

	# The cap is craft §11's single write made checkable: a short line is one
	# printf to an append-mode descriptor, which is what lets fifty parallel
	# emits interleave without splitting one. Over it, the answer is a blob —
	# never a truncated field, and never two writes.
	_em_bytes=$(printf '%s\n' "$_em_line" | wc -c | tr -d ' ')
	[ "$_em_bytes" -le "$TRACE_EVENT_CAP" ] ||
		die "the event is $_em_bytes bytes and the cap is $TRACE_EVENT_CAP, so it would not be one write — move the payload into a blob: --blob <file> stores it once by content hash and the event carries the hash."

	if [ "$_em_dry" = 1 ]; then
		printf '%s\n' "$_em_line"
		return 0
	fi
	[ "$_em_on" = 1 ] || { trace_unconfigured_note; return 0; }
	[ -n "$TRACE_BLOB" ] && trace_blob_store
	mkdir -p "$TRACE_ROOT_DIR/events" || die "cannot create $TRACE_ROOT_DIR/events"
	trace_write_schema
	printf '%s\n' "$_em_line" >>"$TRACE_ROOT_DIR/events/$(date -u +%Y-%m-%d).jsonl"
}

# ---------------------------------------------------------------------------
# begin / end — the two ends of a run.

# trace_reject_owned <subcommand> <argument…> — begin and end own kind, run and
# parent: the subcommand decides all three, so a caller passing one is not
# overriding a default, it is asking for an event that says something else
# happened. Refused, rather than left to whichever assignment comes last.
trace_reject_owned() {
	_ro_cmd=$1
	shift
	for _ro_a in "$@"; do
		case $_ro_a in
		kind=* | run=* | parent=*) die "$_ro_cmd sets ${_ro_a%%=*} itself — drop it" ;;
		-*) usage ;;
		esac
	done
	return 0
}

# trace_begin <skill> [<field>=<value> …] — prints a fresh run id, appends
# run.start, and pushes the run. The event is written BEFORE the push, so a
# refused argument leaves no run open that nobody will close.
trace_begin() {
	[ $# -ge 1 ] || usage
	_bg_skill=$1
	shift
	case $_bg_skill in '' | -* | *=*) usage ;; esac
	trace_reject_owned begin "$@"
	trace_dir || { trace_unconfigured_note; return 0; }
	trace_key || die "cannot name this working tree's run stack: git could not hash its path"
	_bg_run=$(trace_id)
	# The run that is current NOW is the one this one nests inside.
	trace_identity
	if [ -n "$_id_run" ]; then
		trace_emit kind=run.start skill="$_bg_skill" run="$_bg_run" parent="$_id_run" "$@"
	else
		trace_emit kind=run.start skill="$_bg_skill" run="$_bg_run" "$@"
	fi
	trace_push "$_bg_run"
	printf '%s\n' "$_bg_run"
}

# trace_end [<field>=<value> …] — pops this working tree's current run and
# appends run.end for it. With no run open it is exit 2: a pop with nothing to
# pop is a caller's mistake, not an outcome to record.
trace_end() {
	trace_reject_owned end "$@"
	trace_dir || { trace_unconfigured_note; return 0; }
	trace_key || die "cannot name this working tree's run stack: git could not hash its path"
	_en_run=$(trace_stack top)
	[ -n "$_en_run" ] || die "no run is open for this working tree — begin opens one, end closes it"
	_en_parent=$(trace_stack below)
	# Popped first, so the run.end line is the last event that carries the run
	# and the next emit is already back on the run outside it.
	trace_pop
	if [ -n "$_en_parent" ]; then
		trace_emit kind=run.end run="$_en_run" parent="$_en_parent" "$@"
	else
		trace_emit kind=run.end run="$_en_run" "$@"
	fi
}

# ---------------------------------------------------------------------------
# Reading: the per-day files, oldest first, from a since-date on.

# trace_files [<since>] — prints the event files to read, one per line.
trace_files() {
	for _tf_f in "$TRACE_ROOT_DIR"/events/*.jsonl; do
		[ -e "$_tf_f" ] || continue
		_tf_name=$(basename "$_tf_f" .jsonl)
		if [ -n "${1:-}" ] && [ "$(expr "$_tf_name" \< "$1")" = 1 ]; then continue; fi
		printf '%s\n' "$_tf_f"
	done
}

trace_check_date() {
	case $1 in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) return 0 ;; esac
	die "'$1' is not a YYYY-MM-DD date"
}

trace_show() {
	[ $# -ge 1 ] || usage
	_sh_subject=$1
	shift
	trace_check_subject "$_sh_subject" || die "subject '$_sh_subject' is not <type>:<reference>"
	_sh_since=
	_sh_kind=
	while [ $# -gt 0 ]; do
		case $1 in
		--since) [ $# -ge 2 ] || usage; trace_check_date "$2"; _sh_since=$2; shift 2 ;;
		--kind) [ $# -ge 2 ] || usage; trace_is_kind "$2" || die "unknown kind '$2'"; _sh_kind=$2; shift 2 ;;
		*) usage ;;
		esac
	done
	trace_dir || { trace_unconfigured_note; return 0; }
	trace_files "$_sh_since" | while IFS= read -r _sh_f; do
		# An exact comparison over the ENVELOPE only: the data map is the last
		# field and its keys are open, so a data key called subject, related
		# or kind must never read as the event's own. The envelope is the line
		# up to `,"data":{` — a sequence no string value can carry, since every
		# quote inside a value is escaped. Then index() on the quoted subject
		# and token equality over related, so ticket:#3 never matches ticket:#34.
		awk -v s="$_sh_subject" -v k="$_sh_kind" '
		{
			env = $0
			d = index(env, ",\"data\":{")
			if (d) env = substr(env, 1, d - 1)
			hit = index(env, "\"subject\":\"" s "\"")
			if (!hit && match(env, /"related":"[^"]*"/)) {
				r = substr(env, RSTART + 11, RLENGTH - 12)
				n = split(r, t, " ")
				for (i = 1; i <= n; i++) if (t[i] == s) hit = 1
			}
			if (hit && (k == "" || index(env, "\"kind\":\"" k "\""))) print
		}' "$_sh_f"
	done
}

trace_verify() {
	_vf_since=
	while [ $# -gt 0 ]; do
		case $1 in
		--since) [ $# -ge 2 ] || usage; trace_check_date "$2"; _vf_since=$2; shift 2 ;;
		*) usage ;;
		esac
	done
	trace_dir || { trace_unconfigured_note; return 0; }
	# The schema first. A trace written under a version this script does not
	# know is not this reader's to judge — a reader that does not know the shape
	# would report every line as malformed — so it refuses the trace, says which
	# file said what, and judges no line.
	_vf_schema=$(trace_first_line "$TRACE_ROOT_DIR/SCHEMA")
	if [ -n "$_vf_schema" ] && [ "$_vf_schema" != "$TRACE_SCHEMA" ]; then
		echo "x  trace: $TRACE_ROOT_DIR/SCHEMA says schema $_vf_schema and this script reads $TRACE_SCHEMA — a trace it does not know is not its to judge; update the shared layer before reading this one." >&2
		return 1
	fi
	_vf_bad=0
	_vf_node=0
	command -v node >/dev/null 2>&1 && _vf_node=1
	# One file per line from trace_files, split on newlines alone — a `for`
	# rather than a `while read` pipeline, because the verdict is set inside
	# the loop and a pipeline's loop body runs in a subshell that keeps it.
	_vf_ifs=$IFS
	IFS=$_trace_nl
	for _vf_f in $(trace_files "$_vf_since"); do
		IFS=$_vf_ifs
		awk -v kinds=" $TRACE_KINDS " -v f="$_vf_f" '
		{
			bad = ""
			if (substr($0, 1, 13) != "{\"v\":1,\"ts\":\"") bad = "does not open with the schema version and a timestamp"
			else if (substr($0, length($0), 1) != "}") bad = "does not close with }"
			else if (!match($0, /"ts":"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z"/)) bad = "timestamp is not UTC ISO seconds"
			else if (!match($0, /"kind":"[a-z.]+"/)) bad = "carries no kind"
			else {
				k = substr($0, RSTART + 8, RLENGTH - 9)
				if (index(kinds, " " k " ") == 0) bad = "unknown kind " k
			}
			if (bad != "") { printf "%s:%d: %s\n", f, NR, bad; n++ }
		}
		END { exit (n > 0) }' "$_vf_f" || _vf_bad=1
		if [ "$_vf_node" = 1 ]; then
			node -e '
				const fs = require("fs"); let bad = 0;
				fs.readFileSync(process.argv[1], "utf8").split("\n").forEach((l, i) => {
					if (!l) return;
					try { JSON.parse(l); } catch (e) { console.log(process.argv[1] + ":" + (i + 1) + ": not JSON — " + e.message); bad = 1; }
				});
				process.exit(bad);' "$_vf_f" || _vf_bad=1
		fi
	done
	IFS=$_vf_ifs
	[ "$_vf_node" = 1 ] || echo "i  trace: node is not on PATH — lines were checked structurally, not parsed" >&2
	return $_vf_bad
}

# ---------------------------------------------------------------------------

[ $# -ge 1 ] || usage
_trace_cmd=$1
shift
trace_load_config
case $_trace_cmd in
emit) trace_emit "$@" ;;
begin) trace_begin "$@" ;;
end) trace_end "$@" ;;
show) trace_show "$@" ;;
verify) trace_verify "$@"; exit $? ;;
dir) trace_dir && printf '%s\n' "$TRACE_ROOT_DIR"; exit 0 ;;
*) usage ;;
esac
