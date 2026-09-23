#!/bin/sh
# trace.sh — THE decision trace. One implementation, every caller.
#
#   sh scripts/trace.sh emit kind=<kind> [subject=<type:ref>] [related='<type:ref> …']
#                            [<field>=<value> …] [data.<key>=<value> …] [--dry-run]
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
# prints the resolved directory, `show` the matching lines, `emit --dry-run` the
# line it would append; a successful `emit` prints nothing. Every diagnostic is
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
# payload is a blob, not a field, and --blob arrives with #248.
#
# Craft §11: an event is one `printf` of one short line to an append-mode
# descriptor, and nothing here ever truncates a file it did not create.
#
# Shared layer (see VERSION): copied verbatim, not edited downstream. Your
# policy goes in scripts/trace.config.sh.

set -u

_trace_here=$(cd "$(dirname "$0")" && pwd -P)

TRACE_KINDS='session.start session.end session.usage agent.stop tool.use run.start run.end spawn spawn.end prd.write ticket.write ticket.start tdd.cycle review.verdict finding.raise finding.triage pr.open pr.iterate merge.land hypothesis spike.verdict brief.decide housekeeping.finding worktree.prune grill.decision note'
TRACE_STRING_FIELDS='skill subject related session run parent tier domain harness model outcome reason'
TRACE_TOKEN_FIELDS='tok_in tok_out tok_cache_w tok_cache_r'

usage() {
	cat >&2 <<'USAGE'
usage: sh scripts/trace.sh emit kind=<kind> [subject=<type:ref>] [<field>=<value> …] [data.<key>=<value> …] [--dry-run]
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

trace_load_config() {
	_tl_env_dir=${TRACE_DIR:-}
	if [ -n "${TRACE_CONFIG:-}" ]; then
		[ -f "$TRACE_CONFIG" ] || die "TRACE_CONFIG=$TRACE_CONFIG does not exist."
		. "$TRACE_CONFIG"
	else
		_tl_root=$(git -C "$_trace_here" rev-parse --show-toplevel 2>/dev/null) || _tl_root=
		if [ -n "$_tl_root" ] && [ -f "$_tl_root/scripts/trace.config.sh" ]; then
			. "$_tl_root/scripts/trace.config.sh"
		elif [ -f "$_trace_here/trace.config.sh" ]; then
			. "$_trace_here/trace.config.sh"
		fi
	fi
	# The environment wins over the file — set on its own line after the
	# source, so a policy file that assigns TRACE_DIR cannot undo it.
	[ -n "$_tl_env_dir" ] && TRACE_DIR=$_tl_env_dir
	return 0
}

# trace_dir — sets TRACE_ROOT_DIR to the resolved directory, or returns 1 when
# tracing is off. Never creates anything.
trace_dir() {
	case ${TRACE_DIR:-} in
	'') return 1 ;;
	/*) TRACE_ROOT_DIR=$TRACE_DIR ;;
	*)
		_td_common=$(git -C "$_trace_here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || _td_common=
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

trace_is_kind() {
	case " $TRACE_KINDS " in *" $1 "*) return 0 ;; esac
	return 1
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
# emit

trace_emit() {
	_em_dry=0
	_em_kind=
	_em_data=
	for _em_f in $TRACE_STRING_FIELDS $TRACE_TOKEN_FIELDS; do eval "_em_v_$_em_f="; done

	for _em_arg in "$@"; do
		case $_em_arg in
		--dry-run) _em_dry=1 ;;
		--blob | --blob=*) die "--blob is not in this slice yet; a multi-line payload has no home until it lands." ;;
		--*) usage ;;
		*=*)
			_em_key=${_em_arg%%=*}
			_em_val=${_em_arg#*=}
			case $_em_key in
			kind)
				trace_is_kind "$_em_val" || die "unknown kind '$_em_val' — the vocabulary is closed: $TRACE_KINDS"
				_em_kind=$_em_val
				;;
			data.*)
				_em_sub=${_em_key#data.}
				case $_em_sub in '' | [!a-z]* | *[!a-z0-9_]*) die "data key '$_em_sub' is not [a-z][a-z0-9_]*" ;; esac
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
						case $_em_val in '' | *[!0-9]*) die "$_em_key='$_em_val' is not a whole number" ;; esac
						eval "_em_v_$_em_key=\$_em_val"
						;;
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

	_em_line="{\"v\":1,\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"id\":\"$(trace_id)\",\"kind\":\"$_em_kind\""
	for _em_f in $TRACE_STRING_FIELDS; do
		eval "_em_v=\${_em_v_$_em_f}"
		[ -n "$_em_v" ] && _em_line="$_em_line,\"$_em_f\":\"$_em_v\""
	done
	for _em_f in $TRACE_TOKEN_FIELDS; do
		eval "_em_v=\${_em_v_$_em_f}"
		[ -n "$_em_v" ] && _em_line="$_em_line,\"$_em_f\":$_em_v"
	done
	[ -n "$_em_data" ] && _em_line="$_em_line,\"data\":{$_em_data}"
	_em_line="$_em_line}"

	if [ "$_em_dry" = 1 ]; then
		printf '%s\n' "$_em_line"
		return 0
	fi
	trace_dir || { trace_unconfigured_note; return 0; }
	mkdir -p "$TRACE_ROOT_DIR/events" || die "cannot create $TRACE_ROOT_DIR/events"
	printf '%s\n' "$_em_line" >>"$TRACE_ROOT_DIR/events/$(date -u +%Y-%m-%d).jsonl"
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
		# An exact comparison, never a pattern built from the subject: index()
		# on the quoted subject, and token equality over the related field, so
		# ticket:#3 never matches ticket:#34.
		awk -v s="$_sh_subject" -v k="$_sh_kind" '
		{
			hit = index($0, "\"subject\":\"" s "\"")
			if (!hit && match($0, /"related":"[^"]*"/)) {
				r = substr($0, RSTART + 11, RLENGTH - 12)
				n = split(r, t, " ")
				for (i = 1; i <= n; i++) if (t[i] == s) hit = 1
			}
			if (hit && (k == "" || index($0, "\"kind\":\"" k "\""))) print
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
show) trace_show "$@" ;;
verify) trace_verify "$@"; exit $? ;;
dir) trace_dir && printf '%s\n' "$TRACE_ROOT_DIR"; exit 0 ;;
*) usage ;;
esac
