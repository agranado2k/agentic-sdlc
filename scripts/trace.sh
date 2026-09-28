#!/bin/sh
# trace.sh — THE decision trace. One implementation, every caller.
#
#   sh scripts/trace.sh emit kind=<kind> [subject=<type:ref>] [related='<type:ref> …']
#                            [<field>=<value> …] [data.<key>=<value> …] [--dry-run]
#   sh scripts/trace.sh show <type:ref> [--since YYYY-MM-DD] [--kind <kind>]
#   sh scripts/trace.sh summary [--by kind|skill|model|session] [--since YYYY-MM-DD]
#   sh scripts/trace.sh export [--since YYYY-MM-DD] [--csv]
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
# prints the resolved directory, `show` the matching lines, `summary` its table,
# `export` its rows, `emit --dry-run` the line it would append; a successful
# `emit` prints nothing. Every diagnostic is on stderr, prefixed `trace:`. Exit
# 0 is done, INCLUDING the unconfigured no-op; exit 2 is a usage error, an
# unknown kind, a malformed subject, value or price, or a policy file named
# explicitly and missing; exit 1 is `verify`'s verdict, and an `export` that
# refuses because verify fails carries that same verdict out.
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
# COST IS COMPUTED ON READ, NEVER ON WRITE (ADR-0008 clause 6). An event carries
# raw token counts and the model that spent them, because that is a fact; a
# price is an interpretation that rots on a vendor's schedule. So `summary` and
# `export` price the tokens at the moment you ask, from the policy file:
#
#   TRACE_PRICE_<MODEL>='<in>,<out>,<cache_write>,<cache_read>'
#
# four USD-per-MILLION-token prices, in the order the four `tok_*` fields sit
# in. <MODEL> is the model id folded to a variable token the way a task domain
# is in scripts/agents.lib.sh, with the wider alphabet a model id needs: every
# character that is not a letter or a digit becomes `_`, and the result is
# upper-cased. A fold that does not come out as `[A-Z][A-Z0-9_]*` is refused
# rather than evaluated — the fold is a convenience, that check is the
# whitelist standing in front of the eval. A malformed price is exit 2 and
# names the variable: a typo that silently priced a wave at zero would be worse
# than a stopped command.
#
# WHAT `unpriced` MEANS. A cost cell reads `unpriced` — never 0 — when an event
# carries tokens and its model has no price. An event with NO tokens costs
# 0.000000 whatever its model, because zero tokens cost nothing at any price,
# and that is most events: a decision is not a spend. A `summary` GROUP reads
# `unpriced` as soon as one token-bearing event in it is, rather than showing a
# partial sum a reader would take for the group's cost; the models that were
# missing a price are named on stderr, and `--by model` is how you see which.
# An export stamps `priced_at` (when it was read) and `price_src` (the policy
# file that priced it) beside the figure, so a re-priced export is comparable
# with an older one. The kit itself ships no price, for the reason it ships no
# model id.
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
       sh scripts/trace.sh summary [--by kind|skill|model|session] [--since YYYY-MM-DD]
       sh scripts/trace.sh export [--since YYYY-MM-DD] [--csv]
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
	# Which file answered, remembered so an export can stamp price_src with the
	# table that priced it. Assigned AFTER each source, for the same reason
	# TRACE_DIR is below: a policy file must not be able to misname itself.
	_tl_path=
	if [ -n "${TRACE_CONFIG:-}" ]; then
		[ -f "$TRACE_CONFIG" ] || die "TRACE_CONFIG=$TRACE_CONFIG does not exist."
		. "$TRACE_CONFIG"
		_tl_path=$TRACE_CONFIG
	else
		_tl_root=$(trace_git rev-parse --show-toplevel) || _tl_root=
		if [ -n "$_tl_root" ] && [ -f "$_tl_root/scripts/trace.config.sh" ]; then
			. "$_tl_root/scripts/trace.config.sh"
			_tl_path="$_tl_root/scripts/trace.config.sh"
		elif [ -f "$_trace_here/trace.config.sh" ]; then
			. "$_trace_here/trace.config.sh"
			_tl_path="$_trace_here/trace.config.sh"
		fi
	fi
	TRACE_CONFIG_PATH=$_tl_path
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
# Reading a WHOLE event: the JSON reader the aggregate commands share.
#
# `show` filters lines and prints them untouched, so it needs no reader. The
# two commands below take events apart, and a second hand-rolled parser would
# be the place the two drifted — so there is one, prepended to every awk
# program here. No jq: the kit runs before a consumer has chosen a toolchain
# (root manual, "What this repo is"), and awk is in every POSIX box.
#
# WHY A HAND-ROLLED READER IS SAFE HERE, and would not be on arbitrary JSON:
# every line was written by trace_emit, which escapes each string value so the
# only bare `"` characters in a line are the envelope's own. So the text
# `,"<key>":"` cannot occur inside a value, and finding it IS finding the
# field — the same argument that lets `show` cut the envelope at `,"data":{`.
# A line that did NOT come from the emitter is exactly what `verify` is for,
# and `export` refuses to run while verify fails.
#
# Single-quoted, so the awk source reaches awk verbatim; nothing in it may
# carry an apostrophe.
TRACE_AWK_LIB='
# tr_env(line) — the envelope: the line up to the open data map, or all of it.
function tr_env(line,   d) {
	d = index(line, ",\"data\":{")
	if (d) return substr(line, 1, d - 1)
	return line
}
# tr_data(line) — the data map as its own JSON text, or the empty string. The
# map is the LAST field, so it runs from its brace to the character before the
# events closing brace, whatever its own content is.
function tr_data(line,   d) {
	d = index(line, ",\"data\":{")
	if (!d) return ""
	return substr(line, d + 8, length(line) - d - 8)
}
# tr_str(env, key) — a string field, still JSON-escaped, or the empty string.
# The scan stops at the first unescaped quote: a backslash consumes the byte
# after it, so an escaped quote inside the value never ends it.
function tr_str(env, key,   m, i, c, out) {
	m = index(env, ",\"" key "\":\"")
	if (m == 0) return ""
	i = m + length(key) + 5
	out = ""
	while (i <= length(env)) {
		c = substr(env, i, 1)
		if (c == "\\") { out = out substr(env, i, 2); i = i + 2; continue }
		if (c == "\"") break
		out = out c
		i = i + 1
	}
	return out
}
# tr_num(env, key) — an integer field as text, or the empty string. Also finds
# the schema version, which opens the line with a brace instead of a comma.
function tr_num(env, key,   m, i, c, out) {
	m = index(env, ",\"" key "\":")
	if (m == 0) m = index(env, "{\"" key "\":")
	if (m == 0) return ""
	i = m + length(key) + 4
	out = ""
	while (i <= length(env)) {
		c = substr(env, i, 1)
		if (c !~ /[0-9]/) break
		out = out c
		i = i + 1
	}
	return out
}
# tr_unesc(s) — the inverse of the emitters escaper: the real value behind a
# JSON string body. Left to right, because a lone gsub of the tab escape would
# also fire inside an escaped backslash that happens to be followed by a t.
function tr_unesc(s,   i, n, c, out) {
	out = ""
	n = length(s)
	i = 1
	while (i <= n) {
		c = substr(s, i, 1)
		if (c == "\\" && i < n) {
			c = substr(s, i + 1, 1)
			if (c == "t") out = out "\t"
			else if (c == "n") out = out "\n"
			else if (c == "r") out = out "\r"
			else out = out c
			i = i + 2
			continue
		}
		out = out c
		i = i + 1
	}
	return out
}
# tr_csv(s) — one CSV field, RFC 4180. Quoted ONLY when it has to be, so the
# numeric columns arrive as numbers and an absent optional arrives as an empty
# field a database reads as null rather than as an empty string.
function tr_csv(s,   t) {
	t = s
	if (index(t, "\"") || index(t, ",") || index(t, "\n") || index(t, "\r") || index(t, "\t") ||
	    substr(t, 1, 1) == " " || substr(t, length(t), 1) == " ") {
		gsub(/"/, "\"\"", t)
		return "\"" t "\""
	}
	return t
}
# tr_cost(prices, in, out, cache_write, cache_read) — USD, from the four
# prices per MILLION tokens in the order the four token fields sit in.
function tr_cost(p, a, b, c, d,   f) {
	split(p, f, ",")
	return a * f[1] / 1000000 + b * f[2] / 1000000 + c * f[3] / 1000000 + d * f[4] / 1000000
}
# tr_prices(into) — the price table, read out of the ENVIRONMENT as one string:
# a tab between model and prices, a newline between entries. awk cannot see the
# shell variables a policy file set, so the shell has to hand it down — and it
# hands it down here rather than through `-v`, because awk applies BACKSLASH
# ESCAPE PROCESSING to a -v value, which would turn a model id carrying an
# escape into a key that no longer matches the one read out of the event. Same
# reason for the price table source below.
function tr_prices(into,   spec, n, i, rows, t) {
	spec = ENVIRON["TRACE_PRICES"]
	n = split(spec, rows, "\n")
	for (i = 1; i <= n; i++) {
		if (rows[i] == "") continue
		t = index(rows[i], "\t")
		into[substr(rows[i], 1, t - 1)] = substr(rows[i], t + 1)
	}
}
'

# ---------------------------------------------------------------------------
# The price table: policy, read at query time.

# trace_price_var <model id> — the model id folded to the variable token that
# carries its price, or return 1 when the fold is not a name a shell may hold.
# The refusal is the point: the folded token is interpolated into an eval, so
# this check is the whitelist and the fold is only the convenience.
trace_price_var() {
	_pv_tok=$(printf '%s' "$1" | tr 'a-z' 'A-Z' | sed 's/[^A-Z0-9]/_/g')
	case $_pv_tok in '' | [!A-Z]* | *[!A-Z0-9_]*) return 1 ;; esac
	printf '%s' "$_pv_tok"
}

# trace_check_price <variable token> <value> — four non-negative decimal
# numbers, comma separated. A malformed one is exit 2 and not a shrug: a price
# the reader quietly skipped would report a wave as cheaper than it was.
trace_check_price() {
	_cp_n=0
	_cp_ifs=$IFS
	IFS=,
	for _cp_f in $2; do
		_cp_n=$((_cp_n + 1))
		case $_cp_f in
		'' | *[!0-9.]* | *.*.* | .* | *.)
			IFS=$_cp_ifs
			die "TRACE_PRICE_$1='$2' is not four prices — <in>,<out>,<cache_write>,<cache_read>, each a non-negative number of USD per million tokens"
			;;
		esac
	done
	IFS=$_cp_ifs
	[ "$_cp_n" = 4 ] ||
		die "TRACE_PRICE_$1='$2' carries $_cp_n field(s), not four — <in>,<out>,<cache_write>,<cache_read>, USD per million tokens"
	return 0
}

# trace_spending_models [<since>] — the distinct models on events whose token
# counts add up to more than zero, one per line.
trace_spending_models() {
	trace_files "${1:-}" | while IFS= read -r _sm_f; do
		awk "$TRACE_AWK_LIB"'
		{
			e = tr_env($0)
			if (tr_num(e, "tok_in") + tr_num(e, "tok_out") + tr_num(e, "tok_cache_w") + tr_num(e, "tok_cache_r") > 0) {
				m = tr_str(e, "model")
				if (m != "") print m
			}
		}' "$_sm_f"
	done | LC_ALL=C sort -u
}

# trace_load_prices [<since>] — sets TRACE_PRICE_TABLE (what awk is handed) and
# TRACE_PRICE_MISSING (the models to name on stderr) from the models that
# actually SPENT something in the selection. Only those need a price, so only
# those can be reported as missing one: a `note` with no tokens is not a hole
# in the table.
TRACE_PRICE_TABLE=
TRACE_PRICE_MISSING=
trace_load_prices() {
	TRACE_PRICE_TABLE=
	TRACE_PRICE_MISSING=
	_lp_models=$(trace_spending_models "${1:-}")
	[ -n "$_lp_models" ] || return 0
	_lp_ifs=$IFS
	IFS=$_trace_nl
	for _lp_m in $_lp_models; do
		IFS=$_lp_ifs
		_lp_val=
		_lp_var=$(trace_price_var "$_lp_m") || _lp_var=
		[ -n "$_lp_var" ] && eval "_lp_val=\${TRACE_PRICE_$_lp_var:-}"
		if [ -n "$_lp_val" ]; then
			trace_check_price "$_lp_var" "$_lp_val"
			TRACE_PRICE_TABLE="${TRACE_PRICE_TABLE:+$TRACE_PRICE_TABLE$_trace_nl}$_lp_m$_trace_tab$_lp_val"
		else
			TRACE_PRICE_MISSING="${TRACE_PRICE_MISSING:+$TRACE_PRICE_MISSING }$_lp_m"
		fi
		IFS=$_trace_nl
	done
	IFS=$_lp_ifs
	return 0
}

trace_note_unpriced() {
	[ -n "$TRACE_PRICE_MISSING" ] || return 0
	echo "!  trace: no price for: $TRACE_PRICE_MISSING — set TRACE_PRICE_<MODEL> in the policy file; until then those tokens read 'unpriced', never 0." >&2
	return 0
}

# ---------------------------------------------------------------------------
# summary

trace_summary() {
	_su_since=
	_su_by=kind
	while [ $# -gt 0 ]; do
		case $1 in
		--since)
			[ $# -ge 2 ] || usage
			trace_check_date "$2"
			_su_since=$2
			shift 2
			;;
		--by)
			[ $# -ge 2 ] || usage
			case $2 in
			kind | skill | model | session) _su_by=$2 ;;
			*) die "--by '$2' is not an axis — the axes are kind, skill, model, session" ;;
			esac
			shift 2
			;;
		*) usage ;;
		esac
	done
	trace_dir || {
		trace_unconfigured_note
		return 0
	}
	trace_load_prices "$_su_since"
	trace_note_unpriced
	# %d and not %s for the counts: awk converts a number to a string through
	# CONVFMT, which is %.6g, and would print 3007000 as 3.007e+06.
	_su_hfmt='%-30s %8s %13s %13s %13s %13s %13s\n'
	_su_rfmt='%-30s %8d %13d %13d %13d %13d %13s\n'
	# The event files as positional parameters, split on newlines ALONE: one awk
	# invocation has to see them all, because a group spans days, and a path
	# with a space in it must still arrive as one argument. This function has
	# consumed its own arguments by here, so $@ is free.
	_su_ifs=$IFS
	IFS=$_trace_nl
	# shellcheck disable=SC2046  # deliberate: IFS is a newline, one file per word
	set -- $(trace_files "$_su_since")
	IFS=$_su_ifs
	if [ $# -eq 0 ]; then
		printf "$_su_hfmt" "$_su_by" events tok_in tok_out tok_cache_w tok_cache_r cost_usd
		printf "$_su_rfmt" TOTAL 0 0 0 0 0 0.000000
		return 0
	fi
	TRACE_PRICES="$TRACE_PRICE_TABLE" awk -v by="$_su_by" "$TRACE_AWK_LIB"'
	BEGIN { tr_prices(price) }
	{
		e = tr_env($0)
		key = tr_str(e, by)
		if (key == "") key = "(none)"
		n[key]++
		a = tr_num(e, "tok_in") + 0
		b = tr_num(e, "tok_out") + 0
		c = tr_num(e, "tok_cache_w") + 0
		d = tr_num(e, "tok_cache_r") + 0
		s_in[key] += a; s_out[key] += b; s_cw[key] += c; s_cr[key] += d
		if (a + b + c + d > 0) {
			m = tr_str(e, "model")
			if (m != "" && (m in price)) cost[key] += tr_cost(price[m], a, b, c, d)
			else miss[key]++
		}
	}
	END {
		for (k in n)
			printf "%s\t%d\t%d\t%d\t%d\t%d\t%s\n", k, n[k], s_in[k], s_out[k], s_cw[k], s_cr[k],
				(miss[k] > 0 ? "unpriced" : sprintf("%.6f", cost[k] + 0))
	}' "$@" | LC_ALL=C sort |
		awk -F'\t' -v hfmt="$_su_hfmt" -v rfmt="$_su_rfmt" -v by="$_su_by" '
		BEGIN { printf hfmt, by, "events", "tok_in", "tok_out", "tok_cache_w", "tok_cache_r", "cost_usd" }
		{
			printf rfmt, $1, $2, $3, $4, $5, $6, $7
			n += $2; a += $3; b += $4; c += $5; d += $6
			# One rule, applied to a group and to the total alike: a cost that
			# is missing a price is not a smaller cost.
			if ($7 == "unpriced") miss = 1; else total += $7
		}
		END { printf rfmt, "TOTAL", n + 0, a + 0, b + 0, c + 0, d + 0, (miss ? "unpriced" : sprintf("%.6f", total + 0)) }'
}

# ---------------------------------------------------------------------------
# export
#
# The CSV columns are DERIVED from the field lists at the top of this file
# rather than spelled a second time, so a field added to the event becomes a
# column on the same commit. The three computed ones and the data map close the
# row: the envelope is fact, everything after it is this read.

trace_export() {
	_ex_since=
	_ex_csv=0
	while [ $# -gt 0 ]; do
		case $1 in
		--since)
			[ $# -ge 2 ] || usage
			trace_check_date "$2"
			_ex_since=$2
			shift 2
			;;
		--csv)
			_ex_csv=1
			shift
			;;
		*) usage ;;
		esac
	done
	trace_dir || {
		trace_unconfigured_note
		return 0
	}
	# An export is the artifact something else imports, so it is the one place a
	# bad line must stop the command rather than travel with the good ones: half
	# an import is worse than none, because the row that silently vanished is
	# the one nobody goes looking for. verify's findings are the answer to WHY
	# there is no answer, so they leave with it, on stderr.
	_ex_vst=0
	if [ -n "$_ex_since" ]; then
		_ex_bad=$(trace_verify --since "$_ex_since") || _ex_vst=$?
	else
		_ex_bad=$(trace_verify) || _ex_vst=$?
	fi
	if [ "$_ex_vst" != 0 ]; then
		[ -n "$_ex_bad" ] && printf '%s\n' "$_ex_bad" >&2
		echo "x trace: export refused — verify fails on this selection. Nothing was printed; a correction is a new event, never an edit to a file." >&2
		return "$_ex_vst"
	fi
	if [ "$_ex_csv" = 1 ]; then
		trace_load_prices "$_ex_since"
		trace_note_unpriced
	fi
	_ex_cols="v ts id kind $TRACE_STRING_FIELDS $TRACE_TOKEN_FIELDS cost_usd priced_at price_src data"
	_ex_ifs=$IFS
	IFS=$_trace_nl
	# shellcheck disable=SC2046  # deliberate: see the same idiom in trace_summary
	set -- $(trace_files "$_ex_since")
	IFS=$_ex_ifs
	if [ $# -eq 0 ]; then
		[ "$_ex_csv" = 1 ] && printf '%s\n' "$_ex_cols" | tr ' ' ,
		return 0
	fi
	TRACE_PRICES="$TRACE_PRICE_TABLE" TRACE_SRC="${TRACE_CONFIG_PATH:-none}" \
		awk -v csv="$_ex_csv" -v cols="$_ex_cols" -v nums="v $TRACE_TOKEN_FIELDS" \
		-v at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TRACE_AWK_LIB"'
	BEGIN {
		src = ENVIRON["TRACE_SRC"]
		tr_prices(price)
		ncol = split(cols, col, " ")
		nnum = split(nums, num, " ")
		for (i = 1; i <= nnum; i++) isnum[num[i]] = 1
		if (csv) {
			row = ""
			for (i = 1; i <= ncol; i++) row = row (i > 1 ? "," : "") tr_csv(col[i])
			print row
		}
	}
	{
		if (!csv) { print; next }
		e = tr_env($0)
		a = tr_num(e, "tok_in") + 0
		b = tr_num(e, "tok_out") + 0
		c = tr_num(e, "tok_cache_w") + 0
		d = tr_num(e, "tok_cache_r") + 0
		m = tr_str(e, "model")
		if (a + b + c + d == 0) cost = sprintf("%.6f", 0)
		else if (m != "" && (m in price)) cost = sprintf("%.6f", tr_cost(price[m], a, b, c, d))
		else cost = "unpriced"
		row = ""
		for (i = 1; i <= ncol; i++) {
			k = col[i]
			if (k == "cost_usd") v = cost
			else if (k == "priced_at") v = at
			else if (k == "price_src") v = src
			else if (k == "data") v = tr_data($0)
			else if (isnum[k]) v = tr_num(e, k)
			else v = tr_unesc(tr_str(e, k))
			row = row (i > 1 ? "," : "") tr_csv(v)
		}
		print row
	}' "$@"
}

# ---------------------------------------------------------------------------

[ $# -ge 1 ] || usage
_trace_cmd=$1
shift
trace_load_config
case $_trace_cmd in
emit) trace_emit "$@" ;;
show) trace_show "$@" ;;
summary) trace_summary "$@" ;;
export) trace_export "$@"; exit $? ;;
verify) trace_verify "$@"; exit $? ;;
dir) trace_dir && printf '%s\n' "$TRACE_ROOT_DIR"; exit 0 ;;
*) usage ;;
esac
