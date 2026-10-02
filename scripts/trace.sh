#!/bin/sh
# trace.sh — THE decision trace. One implementation, every caller.
#
#   sh scripts/trace.sh emit kind=<kind> [subject=<type:ref>] [related='<type:ref> …']
#                            [<field>=<value> …] [data.<key>=<value> …]
#                            [--blob <file>|--blob=<file>|-] [--dry-run]
#   sh scripts/trace.sh blob <file>|-
#   sh scripts/trace.sh begin <skill> [subject=<type:ref>] [<field>=<value> …]
#   sh scripts/trace.sh end [outcome=<outcome>] [reason=<text>] [<field>=<value> …]
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
# prints the resolved directory, `begin` the run id it just opened, `show` the
# matching lines, `summary` its table, `export` its rows, `emit --dry-run` the
# line it would append; a successful `emit` and a successful `end` print
# nothing. Every diagnostic is on stderr, prefixed `trace:`. Exit 0 is done,
# INCLUDING the unconfigured no-op; exit 2 is a usage error, an unknown kind,
# an outcome its kind does not declare, a data value its kind's shape refuses
# (TRACE_SHAPES), a malformed subject, value or price, or a policy file named
# explicitly and missing; exit 1 is `verify`'s
# verdict, and an `export` that refuses because verify fails carries that
# same verdict out. `begin` and `end` add two exits
# of their own to the 2 — closing a run that is not open, and a run stack that
# cannot be named or read. Both are CALLER errors, the thing the caller asked
# for did not happen, which ADR-0008 clause 4 (as amended) keeps apart from a
# trace error: an `emit` never fails a caller this way.
#   And exit 3 is A TRACE THIS READER CANNOT JUDGE — a SCHEMA naming a version
# this script does not read. Neither of the two above: nothing failed and the
# call was well formed, there is simply no verdict to give. It is the docs
# gate's "could not run" by meaning and not by number, because 2 here is the
# caller's own error and the two ask opposite things — fix your command, versus
# update the shared layer and change nothing about the call. `verify` exits 3
# and judges no line; `export` refuses with 3 and prints nothing; `summary`
# still exits 0 and says so in its first line (ADR-0008 clause 4, as amended
# 2026-09-28 for #271).
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
# tier), and so is each kind's `outcome` (TRACE_OUTCOMES below); `data.*`
# keys are OPEN (like task domains), string values only, except the two shapes
# the kind table declares (TRACE_SHAPES below), which hold a present key. A subject is
# `<type>:<reference>` — lowercase type, then anything without a space, a
# quote or a backslash — so a PRD, a ticket, a PR, a branch, a session and a
# run all join on one column. The types a project's policy
# file names in TRACE_NUMBERED_TYPES are spelled one way, `<type>:#<digits>`,
# because a join key with synonyms is not one (#305); every other type, and
# every type when the list is empty as it ships, stays open.
# Token counts are bare integers.
# A value may not carry a control character other than a tab: a multi-line
# payload is a blob, not a field.
#
# Craft §11: an event is one `printf` of one short line to an append-mode
# descriptor, and nothing here ever truncates a file it did not create. The
# 4000-byte CAP is that single write made checkable — an event whose write
# would exceed it is refused at emit, with the refusal pointing at --blob,
# rather than split across two writes that a parallel emit could interleave.
# The cap is on THE WRITE, which is the line and its newline, so the longest
# event line is 3999 bytes; the refusal prints the number it measured.
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
# spike evidence. `--blob <file>` (or `--blob=<file>`, the same thing; or `-`
# for standard input) stores it under blobs/<first two of the hash>/<hash>,
# named by GIT's own content hash OF THE BYTES THAT WERE STORED — the payload
# is staged first and the staged copy is what is hashed, counted and landed, so
# a file whose size the filesystem does not know cannot be named as something
# it is not. Identical content is stored once and never rewritten; the landing
# is a rename.
#
# SCHEMA, a file in the trace directory, names the version of the lines under
# it. `verify` refuses a trace whose schema it does not know rather than
# reporting every line as malformed, and that refusal is exit 3 — the code
# above, for a trace this reader cannot judge.
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
# AND A DATED TABLE ROTS. Pricing on read is what lets a correction reach the
# whole past; the price of it is a table nobody re-checks. So a priced read —
# `summary`, and `export --csv` — reads the `Last checked: <YYYY-MM-DD>` line
# the table's header carries and prints ONE advisory on stderr when it is older
# than TRACE_PRICES_STALE_DAYS days. Never a failure, never on stdout, silenced
# by TRACE_QUIET=1; and silent when the window is empty (no window, no
# advisory, the way an empty TRACE_DIR is no trace) or when no dated line
# exists. The JSONL `export` prices nothing, so it says nothing.
#
# Shared layer (see VERSION): copied verbatim, not edited downstream. Your
# policy goes in scripts/trace.config.sh.

set -u

_trace_here=$(cd "$(dirname "$0")" && pwd -P)

TRACE_SCHEMA=1
# The exit status for a trace this reader cannot judge, kept as a name because
# three readers have to agree on it: verify returns it, export refuses with it,
# and summary recognises it to mark its own first line (ADR-0008 clause 4).
TRACE_EX_SCHEMA=3
TRACE_EVENT_CAP=4000
# THE KIND TABLE: every kind, and the outcome vocabulary of its own (ADR-0008
# clause 1, as amended 2026-10-01 for #348). The kind set was closed from the
# start; the outcome was open per kind, so a whole sentence could stand where
# a verdict belonged and every reader counting the verdict missed it. Each
# entry is `<kind>=<word>|<word>…`; `<kind>=` with nothing after it is a kind
# that carries NO outcome, and any outcome on it is refused; `note=*` is the
# one open kind, held to a single word ([a-z][a-z0-9-]*) and to nothing else,
# because a note is the free remark. An emit with no outcome at all is legal
# on every kind: the field is optional, as every field but kind is. The kind
# list after it stays a literal line, because the skill suites read it as
# one; the trace suite holds the two to the same kinds, row for row.
TRACE_OUTCOMES='session.start=fail session.end= session.usage=ok|fail agent.stop=ok|fail tool.use=ok|fail|denied run.start= run.end=ok|stopped spawn=dispatched|in-session|refused spawn.end=ok|fail|timeout|budget|unreachable prd.write=published ticket.write=stamped ticket.start=read|defaulted|disputed tdd.cycle=red|green|refactor review.verdict=pass|blocked|confirm finding.raise=raised finding.triage=accepted|rejected|escalated|answered finding.dismiss=dismissed pr.open=opened pr.iterate=green|red|stopped merge.land=landed|skipped|stopped hypothesis=proposed|confirmed|refuted|inconclusive spike.verdict=true|false|inconclusive brief.decide=presented|recorded housekeeping.finding=ticket|deepening|brief|deletion|none worktree.prune=removed|kept grill.decision=accepted|overridden feedback=hit|adjusted|missed|unasked note=*'
TRACE_KINDS='session.start session.end session.usage agent.stop tool.use run.start run.end spawn spawn.end prd.write ticket.write ticket.start tdd.cycle review.verdict finding.raise finding.triage finding.dismiss pr.open pr.iterate merge.land hypothesis spike.verdict brief.decide housekeeping.finding worktree.prune grill.decision feedback note'
# THE SHAPES, beside the outcome words (ADR-0008 clause 1, as amended
# 2026-10-01 for #420): a data key a reader joins on, held at emit to a
# shape. Each entry is `<kind>=<key>:<class>`, the class a bracket
# expression's inside, so a value is `[<class>]+` — one or more of it and
# nothing else. Only a PRESENT key is held: data.* stays open, and an emit
# missing the key writes as before.
TRACE_SHAPES='finding.triage=id:A-Za-z0-9._#- pr.iterate=iteration:0-9'
TRACE_STRING_FIELDS='skill subject related session run parent tier domain harness model outcome reason'
TRACE_TOKEN_FIELDS='tok_in tok_out tok_cache_w tok_cache_r'

usage() {
	cat >&2 <<'USAGE'
usage: sh scripts/trace.sh emit kind=<kind> [subject=<type:ref>] [<field>=<value> …] [data.<key>=<value> …] [--blob <file>|-] [--dry-run]
       sh scripts/trace.sh blob <file>|-
       sh scripts/trace.sh begin <skill> [subject=<type:ref>] [<field>=<value> …]
       sh scripts/trace.sh end [outcome=<outcome>] [reason=<text>] [<field>=<value> …]
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

# PATHNAME EXPANSION OFF, around every unquoted split below. `for x in $list`
# and `set -- $(...)` field-split AND glob, and what they split here is a model
# id and a directory path — either may legally carry *, ? or [. Before this
# guard a model called `alpha*` was silently replaced by a file of that shape in
# the CALLER's cwd, so one model's tokens were looked up under another model's
# name and the diagnostics named the wrong one (H-2, review of PR #262). The
# previous setting is read rather than assumed, so a caller that already runs
# with globbing off keeps it off.
_trace_had_f=0
trace_glob_off() {
	case $- in
	*f*) _trace_had_f=1 ;;
	*)
		_trace_had_f=0
		set -f
		;;
	esac
}
trace_glob_on() { [ "$_trace_had_f" = 1 ] || set +f; }

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
	# Each numbered type is a type word, or the check that reads the list would
	# silently never match it — a policy error, said as one.
	trace_glob_off
	for _tl_w in $TRACE_NUMBERED_TYPES; do
		case $_tl_w in *[!a-z]*) trace_glob_on; die "TRACE_NUMBERED_TYPES word '$_tl_w' in $_tl_path is not a lowercase type" ;; esac
	done
	trace_glob_on
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

# trace_check_outcome <kind> <value> — the kind's own vocabulary, read from
# TRACE_OUTCOMES. Returns 1 with TRACE_OUTCOME_WHY set to the refusal's tail,
# in the vocabulary checker's shape: the kind, the value, then the words.
trace_check_outcome() {
	_co_v=" $TRACE_OUTCOMES "
	case $_co_v in *" $1="*) ;; *) TRACE_OUTCOME_WHY="$1 has no row in TRACE_OUTCOMES — the table and the kind list have drifted" && return 1 ;; esac
	_co_v=${_co_v#* "$1"=}
	_co_v=${_co_v%% *}
	case $_co_v in
	'*')
		case $2 in [!a-z]* | *[!a-z0-9-]*) TRACE_OUTCOME_WHY="$1: outcome '$2' is not one word — $1's outcome is open, held to [a-z][a-z0-9-]*" && return 1 ;; esac
		return 0
		;;
	'') TRACE_OUTCOME_WHY="$1: outcome '$2' — $1 carries no outcome; drop it" && return 1 ;;
	esac
	# A `|` is never part of a word: the alternation the skills print, copied
	# whole, holds only declared words and must not pass as one of them.
	case $2 in *'|'*) ;; *) case "|$_co_v|" in *"|$2|"*) return 0 ;; esac ;; esac
	TRACE_OUTCOME_WHY="$1: outcome '$2' is not one of $(printf '%s' "$_co_v" | tr '|' ' ')"
	return 1
}

# trace_check_shapes <kind> <key=value lines> — every data value the kind's
# TRACE_SHAPES rows name, held to its class. The lines are the emit's data
# arguments in order, one per line (a value never holds a newline: the
# escaper refuses control characters first), so a second occurrence of a key
# is checked too. Returns 1 with TRACE_SHAPE_WHY set in the vocabulary
# checker's shape: the kind, the key, the value, then the shape.
trace_check_shapes() {
	for _cs_e in $TRACE_SHAPES; do
		case $_cs_e in "$1="*) ;; *) continue ;; esac
		_cs_e=${_cs_e#*=}
		_cs_key=${_cs_e%%:*}
		_cs_class=${_cs_e#*:}
		while IFS= read -r _cs_l; do
			case $_cs_l in "$_cs_key="*) ;; *) continue ;; esac
			_cs_v=${_cs_l#*=}
			case $_cs_v in
			'' | *[!$_cs_class]*)
				TRACE_SHAPE_WHY="$1: data.$_cs_key '$_cs_v' is not [$_cs_class]+"
				return 1
				;;
			esac
		done <<EOF
$2
EOF
	done
	return 0
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
# question rather than a comparison). On a refusal TRACE_SUBJECT_FORM names
# the form the value should have taken, for the caller's message.
#   A NUMBERED type takes ONE spelling, `<type>:#<digits>` with no leading
# zero: the first retrospective over the kit's own trace found a ticket written
# three ways, and `show` on the documented one missed the rest (#305). WHICH
# types are numbered is the project's policy, not this script's: the kit names
# no tracker, and one that writes PROJ-12 must not be refused. So the list is
# TRACE_NUMBERED_TYPES in the policy file, empty by default — every type open,
# as before — and only the policy file may set it: the assignment below runs
# before the file is sourced, so an environment value never reaches the check.
# `verify` holds the same rule to the lines already written, as an advisory,
# and hands its awk this same list as `numbered` — one list, never two.
TRACE_NUMBERED_TYPES=''
trace_check_subject() {
	TRACE_SUBJECT_FORM='<type>:<reference>'
	case $1 in *' '* | *'"'* | *'\'* | '') return 1 ;; esac
	_cs_type=${1%%:*}
	_cs_ref=${1#*:}
	[ "$_cs_ref" = "$1" ] && return 1
	[ -z "$_cs_ref" ] && return 1
	case $_cs_type in '' | *[!a-z]*) return 1 ;; esac
	case " $TRACE_NUMBERED_TYPES " in
	*" $_cs_type "*)
		TRACE_SUBJECT_FORM="$_cs_type:#<digits> (no leading zero)"
		case $_cs_ref in '#' | '#'*[!0-9]* | '#0'?* | [!#]*) return 1 ;; esac
		;;
	esac
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

# trace_pointer_session — the session the pointer file names, when it names one
# that can be asked for again. A value carrying a space, a quote or a backslash
# is one `show` could never match, so it is refused with a note rather than
# written onto every line: a MISSING identity is a fact this file records
# happily, an unqueryable one is a line nobody can join on.
trace_pointer_session() {
	_pt_v=$(trace_first_line "$TRACE_POINTER")
	[ -n "$_pt_v" ] || return 0
	if trace_check_subject "session:$_pt_v"; then
		printf '%s' "$_pt_v"
	else
		echo "!  trace: $TRACE_POINTER names a session that show could never match ('$_pt_v') — this event carries no session." >&2
	fi
	return 0
}

# trace_stack top|below — the run at the top of this working tree's stack, or
# the one under it, which is the top's parent. Empty when there is none, and
# non-zero when the file cannot be read — ask trace_stack_readable first, which
# is where that case is reported. The awk's own stderr is closed off for the
# reason the header gives: every diagnostic here is `trace:`-prefixed, and
# awk's is not.
# trace_stack_readable — 0 when the stack can be answered for (missing, which
# means no run is open, or readable), 1 when it EXISTS and cannot be read, which
# is a different fact and not an answer. Called from the parent shell on
# purpose: the once-flag is what keeps one broken file from producing one note
# per question, and a flag set inside a command substitution dies with the
# subshell that set it — which is why the note is not in trace_stack itself.
_trace_stack_said=
trace_stack_readable() {
	[ -e "$TRACE_STACK" ] || return 0
	[ -r "$TRACE_STACK" ] && return 0
	[ -n "$_trace_stack_said" ] || echo "x  trace: the run stack at $TRACE_STACK exists and cannot be read." >&2
	_trace_stack_said=1
	return 1
}

trace_stack() {
	[ -e "$TRACE_STACK" ] || return 0
	[ -r "$TRACE_STACK" ] || return 1
	awk -v want="$1" '{ below = top; top = $0 } END {
		if (want == "top") print top
		else if (NR >= 2) print below
	}' "$TRACE_STACK" 2>/dev/null
	return 0
}

# trace_identity — sets _id_session, _id_run and _id_parent from the
# environment, then from the pointer file and the stack, then leaves them
# empty. An explicit field on the emit is applied by the caller, on top.
trace_identity() {
	# SET-OR-UNSET is remembered separately from the value, exactly as
	# trace_load_config does for TRACE_DIR: `TRACE_RUN=` is a worker SAYING it
	# has no run, and must not read as "ask the local stack" — that stack
	# belongs to another process's trail. It is the reachable spelling, not a
	# contrived one: `RUN=$(trace.sh begin …)` is empty for every consumer
	# whose policy file is untouched, and `TRACE_RUN=$RUN` follows.
	_id_session=${TRACE_SESSION:-}
	_id_run=${TRACE_RUN:-}
	_id_parent=${TRACE_PARENT:-}
	_id_session_set=${TRACE_SESSION+set}
	_id_run_set=${TRACE_RUN+set}
	_id_parent_set=${TRACE_PARENT+set}
	[ -n "${TRACE_ROOT_DIR:-}" ] || return 0
	trace_key || return 0
	[ -n "$_id_session_set" ] || _id_session=$(trace_pointer_session)
	# Once the environment has named the run, the stack is not consulted for
	# the PARENT either: a run from elsewhere has its lineage elsewhere, and
	# reading this working tree's stack for it would invent an edge. TRACE_PARENT
	# on its own is a different case and still stands — each field takes the
	# most specific answer it has.
	if [ -z "$_id_run_set" ] && trace_stack_readable; then
		_id_run=$(trace_stack top)
		[ -n "$_id_parent_set" ] || _id_parent=$(trace_stack below)
	fi
	return 0
}

# trace_push <run id> / trace_pop — the ONLY two writers of the run stack, and
# both write by RENAME: the new stack is staged beside the old one and replaces
# it in one step, so a parallel emit reading the stack sees one whole stack or
# the other and never a partial file. Nothing here appends to it in place.
trace_push() {
	mkdir -p "$(dirname "$TRACE_STACK")" || die "cannot create $(dirname "$TRACE_STACK")"
	_trace_stage=$(mktemp "$TRACE_STACK.XXXXXX") || die "cannot stage the run stack beside $TRACE_STACK"
	# The READ's exit status, on a line of its own. Inside a command group the
	# group's status is the LAST command's, so a `cat` that could not read an
	# existing stack was indistinguishable from an empty one — and the push
	# then replaced every open run with a single entry and exited 0. Craft §11
	# is not only about the redirect: check the PRODUCER's exit.
	if [ -e "$TRACE_STACK" ]; then
		cat "$TRACE_STACK" >"$_trace_stage" 2>/dev/null || die "cannot read the run stack at $TRACE_STACK"
	fi
	printf '%s\n' "$1" >>"$_trace_stage" || die "cannot stage the run stack at $_trace_stage"
	mv "$_trace_stage" "$TRACE_STACK" || die "cannot replace the run stack at $TRACE_STACK"
	_trace_stage=
}

trace_pop() {
	_trace_stage=$(mktemp "$TRACE_STACK.XXXXXX") || die "cannot stage the run stack beside $TRACE_STACK"
	sed '$d' "$TRACE_STACK" >"$_trace_stage" 2>/dev/null || die "cannot read the run stack at $TRACE_STACK"
	mv "$_trace_stage" "$TRACE_STACK" || die "cannot replace the run stack at $TRACE_STACK"
	_trace_stage=
}

# ---------------------------------------------------------------------------
# Blobs: a payload that does not fit on a line, stored once by content hash.

# The scratch this process is holding: a staged payload and a staged run stack,
# both removed however it ends — the cap can refuse a line after the payload was
# staged, and a die can land between staging a stack and renaming it.
_trace_blob_tmp=
_trace_stage=
trace_cleanup() {
	[ -n "$_trace_blob_tmp" ] && rm -f "$_trace_blob_tmp"
	[ -n "$_trace_stage" ] && rm -f "$_trace_stage"
	return 0
}
# A signal trap whose handler RETURNS resumes the script, so each signal gets
# its own trap that exits with the conventional 128+n — otherwise SIGINT
# cleaned up and carried on with a deleted file still named.
trap trace_cleanup EXIT
trap 'trace_cleanup; exit 130' INT
trap 'trace_cleanup; exit 143' TERM
trap 'trace_cleanup; exit 129' HUP

# trace_blob_name <path|-> <1 if it will be stored> — STAGES the payload, then
# names it: sets TRACE_BLOB to git's hash of the staged copy and
# TRACE_BLOB_BYTES to its size. Nothing lands in the store yet, so the line can
# be assembled and checked against the cap first.
#
# STAGING FIRST IS WHAT MAKES THE NAME HONEST. git trusts st_size on a seekable
# descriptor, so hashing a payload whose size the filesystem does not know — a
# /proc or /sys file, some FUSE mounts, a character device — through a
# redirection reads NOTHING and answers with the hash of the EMPTY blob, while
# the copy that lands carries real bytes. Three disagreeing facts on one line,
# at the one address every later empty payload also resolves to, in a store
# whose whole promise is that a name identifies content. A payload that grows
# while it is read has the same shape. One copy, hashed and counted as the
# stored bytes, and the name is provably the hash of what was stored.
trace_blob_name() {
	_bn_src=$1
	if [ "$2" = 1 ]; then
		# Staged on the same filesystem as the store, so landing it is a
		# rename rather than a second copy.
		mkdir -p "$TRACE_ROOT_DIR/tmp" || die "cannot create $TRACE_ROOT_DIR/tmp"
		_trace_blob_tmp=$(mktemp "$TRACE_ROOT_DIR/tmp/payload.XXXXXX") || die "cannot stage the payload"
	else
		# A dry run stores nothing, so its staging must not bring the store
		# into being either.
		_trace_blob_tmp=$(mktemp "${TMPDIR:-/tmp}/trace-blob.XXXXXX") || die "cannot stage the payload"
	fi
	if [ "$_bn_src" = - ]; then
		cat >"$_trace_blob_tmp" || die "cannot stage the payload arriving on standard input"
	else
		[ -f "$_bn_src" ] || die "--blob $_bn_src: no such file"
		cat "$_bn_src" >"$_trace_blob_tmp" || die "--blob $_bn_src: cannot be read"
	fi
	TRACE_BLOB=$(trace_hash_file "$_trace_blob_tmp")
	[ -n "$TRACE_BLOB" ] || die "--blob: git could not hash the staged payload, and git's hash is the blob's name"
	TRACE_BLOB_BYTES=$(wc -c <"$_trace_blob_tmp" | tr -d ' ')
}

# trace_blob_store — lands the staged payload at blobs/<first two>/<hash>, once.
# The store is content-addressed, so a payload already there is left EXACTLY as
# it is: identical content is stored once and nothing rewrites a stored blob
# (craft §11). The landing is a rename, so a reader never opens half a payload.
trace_blob_store() {
	_bs_dest="$TRACE_ROOT_DIR/blobs/$(printf '%.2s' "$TRACE_BLOB")/$TRACE_BLOB"
	if [ -f "$_bs_dest" ]; then
		rm -f "$_trace_blob_tmp"
		_trace_blob_tmp=
		return 0
	fi
	mkdir -p "$(dirname "$_bs_dest")" || die "cannot create the blob store under $TRACE_ROOT_DIR"
	mv "$_trace_blob_tmp" "$_bs_dest" || die "cannot move the payload into $_bs_dest"
	_trace_blob_tmp=
	return 0
}

# trace_blob <path|-> — the blob subcommand: the store with no event. The same
# two functions an emit's payload goes through, so there is one writer of the
# store and one name for a payload however it arrived. Unconfigured, the
# payload is not even read — the reason trace_emit gives for its own --blob.
trace_blob() {
	[ $# -eq 1 ] || usage
	case $1 in -?*) usage ;; esac
	trace_dir || { trace_unconfigured_note; return 0; }
	trace_blob_name "$1" 1
	trace_blob_store
	printf '%s %s\n' "$TRACE_BLOB" "$TRACE_BLOB_BYTES"
}

# trace_write_schema — the trace directory says which schema its lines are, so
# a reader that does not know that schema can refuse instead of guessing. It is
# written once, by rename, and never rewritten.
trace_write_schema() {
	# Content-based, not existence-based: an interrupted first write can leave
	# a marker that names NOTHING, and a guard that only asked whether the file
	# exists would decline to repair it for good.
	[ -n "$(trace_first_line "$TRACE_ROOT_DIR/SCHEMA")" ] && return 0
	_ws_stage=$(mktemp "$TRACE_ROOT_DIR/SCHEMA.XXXXXX") || die "cannot stage $TRACE_ROOT_DIR/SCHEMA"
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
	_em_dlines=
	_em_blob_src=
	_em_outcome=
	_em_on=0
	TRACE_BLOB=
	TRACE_BLOB_BYTES=
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
				_em_dlines="${_em_dlines:+$_em_dlines
}$_em_sub=$_em_val"
				;;
			*)
				case " $TRACE_STRING_FIELDS " in
				*" $_em_key "*)
					case $_em_key in
					subject) [ -z "$_em_val" ] || trace_check_subject "$_em_val" || die "subject '$_em_val' is not $TRACE_SUBJECT_FORM" ;;
					related)
						for _em_tok in $_em_val; do
							trace_check_subject "$_em_tok" || die "related token '$_em_tok' is not $TRACE_SUBJECT_FORM"
						done
						;;
					esac
					_em_esc=$(trace_json_str "$_em_val") || die "$_em_key carries a control character; a multi-line value is a blob, not a field, and --blob is a later slice."
					eval "_em_v_$_em_key=\$_em_esc"
					[ "$_em_key" = outcome ] && _em_outcome=$_em_val
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
	# Checked once the kind is known, which may be after the outcome on the
	# command line. An empty value is no outcome: the line omits it.
	[ -z "$_em_outcome" ] || trace_check_outcome "$_em_kind" "$_em_outcome" || die "$TRACE_OUTCOME_WHY"
	trace_check_shapes "$_em_kind" "$_em_dlines" || die "$TRACE_SHAPE_WHY"

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

	# A blob is READ only when something will come of it. A dry run needs the
	# hash for the line it prints; an unconfigured emit needs nothing at all,
	# and reading a payload there would hand a consumer who never opened the
	# policy file a brand-new way for an emit to exit non-zero (ADR-0008
	# clause 4: a trace error is never in an exit status a caller acts on).
	if [ -n "$_em_blob_src" ]; then
		if [ "$_em_dry" = 1 ]; then
			trace_blob_name "$_em_blob_src" 0
		elif [ "$_em_on" = 1 ]; then
			trace_blob_name "$_em_blob_src" 1
		fi
	fi

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
		skill=*)
			# begin's skill is its positional argument; a trailing skill= used
			# to win silently, which relabels the run the caller asked to open.
			[ "$_ro_cmd" = begin ] && die "begin sets skill itself — it is the positional argument — drop it"
			;;
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
	trace_stack_readable || die "cannot close a run this working tree's stack will not answer for"
	_en_run=$(trace_stack top)
	[ -n "$_en_run" ] || die "no run is open for this working tree — begin opens one, end closes it"
	_en_parent=$(trace_stack below)
	# The event FIRST, the pop after it: `run` and `parent` are passed
	# explicitly, so writing the event with the run still on the stack changes
	# nothing about the line — and popping first meant a refused argument
	# destroyed the entry, wrote no run.end, and left the retry closing the run
	# OUTSIDE this one. An append-only record cannot be corrected, only added
	# to (ADR-0008 clause 5), so it would have stayed wrong.
	if [ -n "$_en_parent" ]; then
		trace_emit kind=run.end run="$_en_run" parent="$_en_parent" "$@"
	else
		trace_emit kind=run.end run="$_en_run" "$@"
	fi
	trace_pop
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
	trace_check_subject "$_sh_subject" || die "subject '$_sh_subject' is not $TRACE_SUBJECT_FORM — the one spelling emit writes, so the only one worth asking for"
	# A run id never appears as a subject: `begin` writes it into the `run`
	# field and every event inside the run carries it there, so a subject-only
	# reader answered nothing for `run:<id>` — the one question a run id is for
	# (PRD #237 story 25, found by the review of PR #263). The TYPE is what
	# switches that second look on, so no other subject type starts reading a
	# field it never meant.
	_sh_run=
	case ${_sh_subject%%:*} in run) _sh_run=${_sh_subject#*:} ;; esac
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
		#
		# `run` adds a third place to look, it does not replace the first two: an
		# event that names the run as its own subject still belongs in the view.
		# The quoted `,"run":"<id>"` is an exact comparison for the same reason
		# the subject one is — a reference carries no quote, backslash or space
		# (trace_check_subject), so r1 can never match r12; the leading comma is
		# free strictness, since neither field is ever the line's first.
		# `parent` is matched ONLY for the run.start/run.end pair, so a
		# dispatched worker's two ends show under the run that dispatched it
		# (PRD scenario 11) while the body of that worker's run stays its own —
		# matching parent for every kind would flatten a nested run into its
		# parent's view and make `show` useless for the nesting it records.
		awk -v s="$_sh_subject" -v k="$_sh_kind" -v run="$_sh_run" '
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
			if (!hit && run != "") {
				if (index(env, ",\"run\":\"" run "\"")) hit = 1
				else if (index(env, ",\"parent\":\"" run "\"") &&
					(index(env, ",\"kind\":\"run.start\"") || index(env, ",\"kind\":\"run.end\""))) hit = 1
			}
			if (hit && (k == "" || index(env, "\"kind\":\"" k "\""))) print
		}' "$_sh_f"
	done
}

# TRACE_AWK_SPELLED — the awk half of the numbered-subject rule, shared by
# verify's per-line advisory and the count `summary` and `export` say once.
# The caller defines spelled(field, value), called for every subject and
# related token in a line's ENVELOPE — the data map is cut off first, as
# `show` cuts it, so a data key called subject is never read as the event's.
# spelled_ok is trace_check_subject's numbered arm, in awk; `numbered` is
# TRACE_NUMBERED_TYPES, handed over, so the two cannot name different lists.
# Single-quoted, so it may carry no apostrophe.
TRACE_AWK_SPELLED='
function spelled_type(v,   t) { t = v; sub(/:.*/, "", t); return t }
function spelled_ok(v,   t, r) {
	t = spelled_type(v)
	if (index(numbered, " " t " ") == 0) return 1
	r = substr(v, length(t) + 2)
	return (r ~ /^#(0|[1-9][0-9]*)$/)
}
function spelled_scan(line,   env, d, m, i, tok) {
	env = line
	d = index(env, ",\"data\":{")
	if (d) env = substr(env, 1, d - 1)
	if (match(env, /,"subject":"[^"]*"/)) spelled("subject", substr(env, RSTART + 12, RLENGTH - 13))
	if (match(env, /,"related":"[^"]*"/)) {
		m = split(substr(env, RSTART + 12, RLENGTH - 13), tok, " ")
		for (i = 1; i <= m; i++) spelled("related token", tok[i])
	}
}
'

# TRACE_AWK_OUTCOME — the awk half of the per-kind outcome rule (#348), shared
# by verify's per-line advisory and the count `summary` and `export` say once.
# outcome_ok is trace_check_outcome in awk; `outcomes` is TRACE_OUTCOMES,
# handed over, so the two cannot read different tables. outcome_scan reads the
# ENVELOPE only — a data key called outcome is never the event's — and calls
# the caller's outcome_bad(kind, value) for a value its kind does not declare.
# An event with no outcome is never one. Single-quoted: no apostrophe in it.
TRACE_AWK_OUTCOME='
function outcome_words(k,   i, v) {
	i = index(outcomes, " " k "=")
	if (i == 0) return ""
	v = substr(outcomes, i + length(k) + 2)
	sub(/ .*/, "", v)
	return v
}
function outcome_ok(k, o,   v) {
	if (index(o, "|")) return 0
	v = outcome_words(k)
	if (v == "*") return (o ~ /^[a-z][a-z0-9-]*$/)
	if (v == "") return 0
	return (index("|" v "|", "|" o "|") > 0)
}
function outcome_scan(line,   env, d, k, o) {
	env = line
	d = index(env, ",\"data\":{")
	if (d) env = substr(env, 1, d - 1)
	if (!match(env, /,"kind":"[a-z.]+"/)) return
	k = substr(env, RSTART + 9, RLENGTH - 10)
	# Shown up to the first escaped quote: a value carrying one was written
	# before the rule and is advised on whatever its tail says.
	if (!match(env, /,"outcome":"[^"]*"/)) return
	o = substr(env, RSTART + 12, RLENGTH - 13)
	if (!outcome_ok(k, o)) outcome_bad(k, o)
}
'

# trace_spelling_note [<since>] — the stderr lines `summary` and `export` say
# when the trace holds history a rule younger than it would refuse: old
# numbered spellings (#305) and outcomes their kind does not declare (#348).
# One line each, the count and where the list is. Repeating verify's per-line
# advisories on every read would bury the command's own output under history
# nobody may rewrite. Reads the lines that open as an event does; a line that
# does not is verify's verdict, not this.
trace_spelling_note() {
	_sn_n=0
	_sn_o=0
	_sn_files=$(trace_files "${1:-}")
	_sn_ifs=$IFS
	IFS=$_trace_nl
	trace_glob_off
	for _sn_f in $_sn_files; do
		IFS=$_sn_ifs
		_sn_c=$(awk -v numbered=" $TRACE_NUMBERED_TYPES " -v outcomes=" $TRACE_OUTCOMES " "$TRACE_AWK_SPELLED$TRACE_AWK_OUTCOME"'
		function spelled(field, v) { if (!spelled_ok(v)) n++ }
		function outcome_bad(k, o) { m++ }
		substr($0, 1, 13) == "{\"v\":1,\"ts\":\"" { spelled_scan($0); outcome_scan($0) }
		END { print n + 0, m + 0 }' "$_sn_f")
		_sn_n=$((_sn_n + ${_sn_c%% *}))
		_sn_o=$((_sn_o + ${_sn_c#* }))
	done
	IFS=$_sn_ifs
	trace_glob_on
	[ "$_sn_n" = 0 ] || echo "!  trace: $_sn_n numbered subject(s) in the trace are spelled the old way — kept as history; sh scripts/trace.sh verify names each with file and line" >&2
	[ "$_sn_o" = 0 ] || echo "!  trace: $_sn_o outcome(s) in the trace are not a word their kind declares — kept as history; sh scripts/trace.sh verify names each with file and line" >&2
	return 0
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
	# file said what, and judges no line. Its own exit code, not the verdict's:
	# a caller told 1 goes looking for the bad line, and there is none to find.
	_vf_schema=$(trace_first_line "$TRACE_ROOT_DIR/SCHEMA")
	if [ -n "$_vf_schema" ] && [ "$_vf_schema" != "$TRACE_SCHEMA" ]; then
		echo "x  trace: $TRACE_ROOT_DIR/SCHEMA says schema $_vf_schema and this script reads $TRACE_SCHEMA — a trace it does not know is not its to judge; update the shared layer before reading this one." >&2
		return "$TRACE_EX_SCHEMA"
	fi
	_vf_bad=0
	_vf_node=0
	command -v node >/dev/null 2>&1 && _vf_node=1
	# One file per line from trace_files, split on newlines alone — a `for`
	# rather than a `while read` pipeline, because the verdict is set inside
	# the loop and a pipeline's loop body runs in a subshell that keeps it.
	# The list is captured FIRST, with pathname expansion still on, because
	# trace_files finds the day files with a glob of its own; only the SPLIT of
	# that list runs with globbing off. Nothing in the loop body globs.
	_vf_files=$(trace_files "$_vf_since")
	_vf_ifs=$IFS
	IFS=$_trace_nl
	trace_glob_off
	for _vf_f in $_vf_files; do
		IFS=$_vf_ifs
		# A numbered subject in any spelling but `<type>:#<digits>` is an
		# ADVISORY, never a bad line: the rule (#305) is younger than the trace,
		# and history is never rewritten, so a line written before it is still a
		# good line. Only a line that is otherwise good is read for it, and the
		# note goes to stderr through a pipe, which POSIX awk has where it has no
		# /dev/stderr. `summary` and `export` switch the per-line notes off and
		# say the count once instead (trace_spelling_note).
		awk -v kinds=" $TRACE_KINDS " -v numbered=" $TRACE_NUMBERED_TYPES " -v outcomes=" $TRACE_OUTCOMES " -v q="'" -v f="$_vf_f" -v advise="${_trace_quiet_advice:-list}" "$TRACE_AWK_SPELLED$TRACE_AWK_OUTCOME"'
		function spelled(field, v) {
			if (advise != "list" || spelled_ok(v)) return
			printf "!  trace: %s:%d: %s %s is not %s:#<digits> — written before the rule, kept as history; advisory, the verdict is unchanged\n", f, NR, field, v, spelled_type(v) | "cat 1>&2"
		}
		function outcome_bad(k, o,   w) {
			if (advise != "list") return
			w = outcome_words(k)
			if (w == "") w = "allowed — the kind carries no outcome"
			else if (w == "*") w = "one word"
			else { gsub(/\|/, " ", w); w = "one of " w }
			printf "!  trace: %s:%d: %s outcome %s%s%s is not %s — written before the rule, kept as history; advisory, the verdict is unchanged\n", f, NR, k, q, o, q, w | "cat 1>&2"
		}
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
			else { spelled_scan($0); outcome_scan($0) }
		}
		END { close("cat 1>&2"); exit (n > 0) }' "$_vf_f" || _vf_bad=1
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
	trace_glob_on
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
# the four PRICES, a tab, then the model id, and a newline between entries. awk
# cannot see the shell variables a policy file set, so the shell has to hand it
# down — and it hands it down here rather than through `-v`, because awk applies BACKSLASH
# ESCAPE PROCESSING to a -v value, which would turn a model id carrying an
# escape into a key that no longer matches the one read out of the event. Same
# reason for the price table source below.
#
# Prices FIRST and the id after the first tab, so a model id that carries a tab
# of its own still arrives whole: only one of the two halves can be variable
# length, and it is the id.
function tr_prices(into,   spec, n, i, rows, t) {
	spec = ENVIRON["TRACE_PRICES"]
	n = split(spec, rows, "\n")
	for (i = 1; i <= n; i++) {
		if (rows[i] == "") continue
		t = index(rows[i], "\t")
		into[substr(rows[i], t + 1)] = substr(rows[i], 1, t - 1)
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
	# The token is a SUFFIX of TRACE_PRICE_, so it may start with a digit:
	# TRACE_PRICE_9_BAD is a legal name. Only a character outside [A-Z0-9_]
	# — none can survive the fold — or an empty token is refused; the first
	# draft also refused a leading digit, a restriction the shell never had
	# and the resolver's own domain fold does not impose (review of PR #262).
	case $_pv_tok in '' | *[!A-Z0-9_]*) return 1 ;; esac
	printf '%s' "$_pv_tok"
}

# trace_check_price <variable token> <value> — four non-negative decimal
# numbers, comma separated. A malformed one is exit 2 and not a shrug: a price
# the reader quietly skipped would report a wave as cheaper than it was.
trace_check_price() {
	# The DELIMITERS are checked on the raw string before any splitting: word
	# splitting DROPS a trailing empty field, so '1,2,3,4,' counted as four
	# prices and was accepted (M-1, review of PR #262).
	case $2 in
	,* | *, | *,,*)
		die "TRACE_PRICE_$1='$2' has an empty price field — give four values as <in>,<out>,<cache_write>,<cache_read>, with no leading, trailing or doubled comma"
		;;
	esac
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
				# The DECODED id: the price variable is named after the model
				# the operator knows, not after its JSON escaping, so folding
				# the escaped body looked one up under a name nobody would ever
				# write (H-1, review of PR #262). A decoded NEWLINE would break
				# this one-per-line list; only a hand-written event can carry
				# one, and such a model is dropped here so that it reads
				# `unpriced` rather than being priced as something else.
				m = tr_unesc(tr_str(e, "model"))
				if (m != "" && index(m, "\n") == 0) print m
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
	trace_glob_off
	for _lp_m in $_lp_models; do
		IFS=$_lp_ifs
		_lp_val=
		_lp_var=$(trace_price_var "$_lp_m") || _lp_var=
		[ -n "$_lp_var" ] && eval "_lp_val=\${TRACE_PRICE_$_lp_var:-}"
		if [ -n "$_lp_val" ]; then
			trace_check_price "$_lp_var" "$_lp_val"
			TRACE_PRICE_TABLE="${TRACE_PRICE_TABLE:+$TRACE_PRICE_TABLE$_trace_nl}$_lp_val$_trace_tab$_lp_m"
		else
			TRACE_PRICE_MISSING="${TRACE_PRICE_MISSING:+$TRACE_PRICE_MISSING }$_lp_m"
		fi
		IFS=$_trace_nl
	done
	IFS=$_lp_ifs
	trace_glob_on
	return 0
}

trace_note_unpriced() {
	[ -n "$TRACE_PRICE_MISSING" ] || return 0
	echo "!  trace: no price for: $TRACE_PRICE_MISSING — set TRACE_PRICE_<MODEL> in the policy file; until then those tokens read 'unpriced', never 0." >&2
	return 0
}

# --- the table's age --------------------------------------------------------
# A price is an interpretation with a date on it (ADR-0008 clause 6): pricing on
# read is what lets a correction reach the whole past, and the cost of that
# choice is a table that rots QUIETLY. A cost column nobody re-derives is
# exactly the number an operator believes, and unlike a wrong model id a stale
# price never fails loudly. So the table says its own age, on the read where it
# is applied, and says nothing else: never on stdout (it would land inside the
# table a spreadsheet parses), never in an exit status (the answer was correct),
# and silenced by TRACE_QUIET=1 with every other note.

# trace_days <YYYY-MM-DD> — the date as a day count, so two of them subtract.
# Arithmetic and not `date -d`: that switch is GNU's, and a staleness window
# that works on one vendor's coreutils is a rule half the hosts do not keep.
# The formula is the standard Julian day number; the leading zeros are stripped
# because POSIX arithmetic reads 09 as octal and refuses it.
trace_days() {
	_dd_y=${1%%-*}
	_dd_rest=${1#*-}
	_dd_m=${_dd_rest%%-*}
	_dd_d=${_dd_rest#*-}
	_dd_y=${_dd_y#0}
	_dd_m=${_dd_m#0}
	_dd_d=${_dd_d#0}
	_dd_a=$(((14 - _dd_m) / 12))
	_dd_yy=$((_dd_y + 4800 - _dd_a))
	_dd_mm=$((_dd_m + 12 * _dd_a - 3))
	printf '%s' "$((_dd_d + (153 * _dd_mm + 2) / 5 + 365 * _dd_yy + _dd_yy / 4 - _dd_yy / 100 + _dd_yy / 400 - 32045))"
}

# trace_note_stale_prices — one advisory when the price table in the policy file
# THAT IS IN EFFECT was last checked longer ago than TRACE_PRICES_STALE_DAYS.
#
# The date is read from a COMMENT — the `Last checked: <YYYY-MM-DD>` line the
# table's header carries — and not from a variable, because it is the
# operator's claim about the table rather than a value the script assigns; the
# first such line in the file answers. Two silences are deliberate: an EMPTY
# window is no window, exactly as an empty TRACE_DIR is no trace, because a
# default of thirty days would be the kit deciding a consumer's freshness for
# them; and a window with no dated line has nothing to compare, so it says
# nothing rather than guessing that undated means old.
trace_note_stale_prices() {
	_ns_win=${TRACE_PRICES_STALE_DAYS:-}
	[ -n "$_ns_win" ] || return 0
	# The WIDTH as well as the alphabet: a window of thirty digits is a number
	# the shell's arithmetic cannot hold, and `[ … -gt … ]` answered it with
	# `integer expected` on the stderr of a SHIPPED script (L-1, review of PR
	# #294). Seven digits is 2739 years, so the cap costs nobody a window.
	case $_ns_win in
	*[!0-9]* | ????????*) die "TRACE_PRICES_STALE_DAYS='$_ns_win' is not a number of days — give a whole number of at most seven digits, or leave it empty for no window" ;;
	esac
	[ -n "${TRACE_CONFIG_PATH:-}" ] && [ -f "${TRACE_CONFIG_PATH:-}" ] || return 0
	_ns_date=$(sed -n 's/.*Last checked: *\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\).*/\1/p' "$TRACE_CONFIG_PATH" | head -1)
	[ -n "$_ns_date" ] || return 0
	# The shape is not the calendar. `2026-00-00` matched the pattern above and
	# came out as a real number of days ago, and `2026-99-99` came out in the
	# FUTURE and went silent — which is what a fresh table looks like, so the
	# wrong answer was the invisible one (M-1, review of PR #294). Refused with
	# the same voice as a malformed window: both are the operator's own typo.
	_ns_mon=${_ns_date#*-}
	_ns_mon=${_ns_mon%%-*}
	_ns_day=${_ns_date##*-}
	case $_ns_mon in 0[1-9] | 1[0-2]) ;; *) die "the price table's 'Last checked: $_ns_date' in $TRACE_CONFIG_PATH is not a calendar date — the month must be 01 to 12" ;; esac
	case $_ns_day in 0[1-9] | [12][0-9] | 3[01]) ;; *) die "the price table's 'Last checked: $_ns_date' in $TRACE_CONFIG_PATH is not a calendar date — the day must be 01 to 31" ;; esac
	_ns_age=$(($(trace_days "$(date -u +%Y-%m-%d)") - $(trace_days "$_ns_date")))
	[ "$_ns_age" -gt "$_ns_win" ] || return 0
	[ "${TRACE_QUIET:-}" = 1 ] && return 0
	echo "!  trace: the price table was last checked $_ns_date, $_ns_age days ago — past the ${_ns_win}-day window TRACE_PRICES_STALE_DAYS sets in $TRACE_CONFIG_PATH. The costs below were priced from it anyway; re-check the table and replace the date. Nothing failed." >&2
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
	# A glance is not an import: summary never refuses, but a damaged trace
	# is said in summary's OWN first line, so a total nobody mistakes for
	# clean; verify's findings go to stderr as they do for export, which still
	# refuses outright (operator decision, 2026-09-28).
	_su_vst=0
	_trace_quiet_advice=count
	if [ -n "$_su_since" ]; then
		_su_bad=$(trace_verify --since "$_su_since") || _su_vst=$?
	else
		_su_bad=$(trace_verify) || _su_vst=$?
	fi
	_trace_quiet_advice=
	[ "$_su_vst" = "$TRACE_EX_SCHEMA" ] || trace_spelling_note "$_su_since"
	if [ "$_su_vst" = "$TRACE_EX_SCHEMA" ]; then
		# A different marker, because it is a different state: verify judged no
		# line, so there is no count to print and a count of 0 would read as
		# almost clean. The version is read back from the marker file rather
		# than out of verify, which answered on stderr and in a subshell.
		printf 'verify: UNSUPPORTED SCHEMA %s\n' "$(trace_first_line "$TRACE_ROOT_DIR/SCHEMA")"
	elif [ "$_su_vst" != 0 ]; then
		[ -n "$_su_bad" ] && printf '%s\n' "$_su_bad" >&2
		# Distinct file:line pairs, not findings: with node on PATH verify names
		# a bad line twice, once structurally and once from the parse.
		_su_n=$(printf '%s\n' "$_su_bad" | cut -d: -f1,2 | sort -u | grep -c .)
		printf 'verify: FAILED — %s bad line(s) on this selection; the totals below include them\n' "$_su_n"
	fi
	trace_load_prices "$_su_since"
	trace_note_unpriced
	trace_note_stale_prices
	# %d and not %s for the counts: awk converts a number to a string through
	# CONVFMT, which is %.6g, and would print 3007000 as 3.007e+06.
	_su_hfmt='%-30s %8s %13s %13s %13s %13s %13s\n'
	_su_rfmt='%-30s %8d %13d %13d %13d %13d %13s\n'
	# The event files as positional parameters, split on newlines ALONE: one awk
	# invocation has to see them all, because a group spans days, and a path
	# with a space in it must still arrive as one argument. This function has
	# consumed its own arguments by here, so $@ is free.
	_su_ifs=$IFS
	# Captured before the split, so trace_files keeps the glob it needs; the
	# split itself runs with pathname expansion off, so a trace directory whose
	# own path carries *, ? or [ still names its files (H-2, PR #262).
	_su_files=$(trace_files "$_su_since")
	IFS=$_trace_nl
	trace_glob_off
	# shellcheck disable=SC2086  # deliberate: IFS is a newline, one file per word
	set -- $_su_files
	IFS=$_su_ifs
	trace_glob_on
	if [ $# -eq 0 ]; then
		printf "$_su_hfmt" "$_su_by" events tok_in tok_out tok_cache_w tok_cache_r cost_usd
		printf "$_su_rfmt" TOTAL 0 0 0 0 0 0.000000
		return 0
	fi
	# TWO STAGES, and what crosses between them is deliberate. The COST crosses
	# at full precision and is rounded once, for display, in the second: rounding
	# each group to six places and then adding the rounded rows made the same
	# events total differently depending on which axis you grouped them by, and a
	# total that moves when you change the question is not a total (H-3, review
	# of PR #262). The KEY crosses LAST, and the sort is told so (-k7 is field 7
	# to the end of the line), because a decoded key may carry a tab of its own
	# and the six numbers in front of it may not.
	TRACE_PRICES="$TRACE_PRICE_TABLE" awk -v by="$_su_by" "$TRACE_AWK_LIB"'
	BEGIN { tr_prices(price) }
	{
		e = tr_env($0)
		# DECODED, so the row an operator reads is the value they would type —
		# and, on --by model, the same string the price table is keyed by. The
		# EMPTY key is the absent field and nothing else: trace_emit omits a
		# field whose value is empty, so no PRESENT value can ever be "", and an
		# event whose skill literally reads "(none)" therefore keeps its own row
		# instead of being merged into the absent one (M-2, review of PR #262).
		key = tr_unesc(tr_str(e, by))
		n[key]++
		a = tr_num(e, "tok_in") + 0
		b = tr_num(e, "tok_out") + 0
		c = tr_num(e, "tok_cache_w") + 0
		d = tr_num(e, "tok_cache_r") + 0
		s_in[key] += a; s_out[key] += b; s_cw[key] += c; s_cr[key] += d
		if (a + b + c + d > 0) {
			m = tr_unesc(tr_str(e, "model"))
			if (m != "" && (m in price)) cost[key] += tr_cost(price[m], a, b, c, d)
			else miss[key]++
		}
	}
	END {
		for (k in n)
			printf "%d\t%d\t%d\t%d\t%d\t%s\t%s\n", n[k], s_in[k], s_out[k], s_cw[k], s_cr[k],
				(miss[k] > 0 ? "unpriced" : sprintf("%.12f", cost[k] + 0)), k
	}' "$@" | LC_ALL=C sort -t"$_trace_tab" -k7 |
		awk -F'\t' -v hfmt="$_su_hfmt" -v rfmt="$_su_rfmt" -v by="$_su_by" '
		BEGIN { printf hfmt, by, "events", "tok_in", "tok_out", "tok_cache_w", "tok_cache_r", "cost_usd" }
		{
			key = $7
			for (i = 8; i <= NF; i++) key = key "\t" $i
			if (key == "") key = "(none)"
			printf rfmt, key, $1, $2, $3, $4, $5, ($6 == "unpriced" ? "unpriced" : sprintf("%.6f", $6))
			n += $1; a += $2; b += $3; c += $4; d += $5
			# One rule, applied to a group and to the total alike: a cost that
			# is missing a price is not a smaller cost.
			if ($6 == "unpriced") miss = 1; else total += $6
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
	_trace_quiet_advice=count
	if [ -n "$_ex_since" ]; then
		_ex_bad=$(trace_verify --since "$_ex_since") || _ex_vst=$?
	else
		_ex_bad=$(trace_verify) || _ex_vst=$?
	fi
	_trace_quiet_advice=
	[ "$_ex_vst" = "$TRACE_EX_SCHEMA" ] || trace_spelling_note "$_ex_since"
	if [ "$_ex_vst" = "$TRACE_EX_SCHEMA" ]; then
		# Not a bad line — no line was read at all. Saying "verify fails" here
		# would send the operator hunting for damage that is not there, when the
		# fix is a newer reader.
		echo "x trace: export refused — the schema of this trace is not this reader's, so nothing here can honestly be exported. Nothing was printed; verify's own line above names both versions." >&2
		return "$_ex_vst"
	fi
	if [ "$_ex_vst" != 0 ]; then
		[ -n "$_ex_bad" ] && printf '%s\n' "$_ex_bad" >&2
		echo "x trace: export refused — verify fails on this selection. Nothing was printed; a correction is a new event, never an edit to a file." >&2
		return "$_ex_vst"
	fi
	if [ "$_ex_csv" = 1 ]; then
		trace_load_prices "$_ex_since"
		trace_note_unpriced
		# The advisory travels with the PRICED read: the JSONL form prints events
		# verbatim and applies no price, so the table's age is not its business.
		trace_note_stale_prices
	fi
	_ex_cols="v ts id kind $TRACE_STRING_FIELDS $TRACE_TOKEN_FIELDS cost_usd priced_at price_src data"
	_ex_ifs=$IFS
	# Captured before the split, so trace_files keeps the glob it needs; the
	# split itself runs with pathname expansion off, so a trace directory whose
	# own path carries *, ? or [ still names its files (H-2, PR #262).
	_ex_files=$(trace_files "$_ex_since")
	IFS=$_trace_nl
	trace_glob_off
	# shellcheck disable=SC2086  # deliberate: see the same idiom in trace_summary
	set -- $_ex_files
	IFS=$_ex_ifs
	trace_glob_on
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
		m = tr_unesc(tr_str(e, "model"))
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
_trace_quiet_advice=
_trace_cmd=$1
shift
trace_load_config
case $_trace_cmd in
emit) trace_emit "$@" ;;
blob) trace_blob "$@" ;;
begin) trace_begin "$@" ;;
end) trace_end "$@" ;;
show) trace_show "$@" ;;
summary) trace_summary "$@" ;;
export) trace_export "$@"; exit $? ;;
verify) trace_verify "$@"; exit $? ;;
dir) trace_dir && printf '%s\n' "$TRACE_ROOT_DIR"; exit 0 ;;
*) usage ;;
esac
