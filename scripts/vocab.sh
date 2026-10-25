#!/bin/sh
# vocab.sh — THE vocabulary checker. One implementation, every caller.
#
#   sh scripts/vocab.sh [check] [--writer <w>] [<line> …]
#                                   lines as arguments, or on stdin when none
#                                   are given; <w> is planner (the default)
#                                   or risk-rule
#   sh scripts/vocab.sh fields      print the effective vocabularies
#
# WHAT IT ANSWERS. One question: "is this value legal for this field, given the
# other fields?" The chain makes a closed-set judgment at every hand-off — a
# ticket's tier, its autonomy label, a finding's severity, a behavior delta's
# status, a triage action — and until this script only the tier had a closed
# vocabulary, and only at the resolver. A body saying `Tier: Implementor` or a
# report saying `Severity: Medium-High` passed everything and broke the reader
# downstream. This script refuses the value where it is read. PRD #273.
#
# THE INPUT is LINES, never a document: a calling skill lifts the decision
# lines out of the ticket body, the review report or a subagent's return and
# hands them over — this script never reads the tracker or a PR. A line is
# `<Field>: <value>`; the field name is matched without regard to case, with
# spaces and underscores read as hyphens (`Tier:`, `tier:`, `Command shaped:`
# and `command_shaped:` all name a field), and a line whose key is not a
# declared field is not a decision line and is ignored. The VALUE is matched
# exactly, one token whole — a QUERY field's value against its grammar
# instead (vocab_query_ok). A field that appears twice with two different
# values is refused — a body with two answers has none, and a line appended
# to it cannot withdraw a rule — while the same value repeated is one answer.
#
# FOUR KINDS OF FIELD beside the closed one, each named by a policy list:
#   OPEN       (VOCAB_OPEN) — the shape alone is held, never membership.
#   QUERY      (VOCAB_QUERY) — a trace filter, held to vocab_query_ok.
#   QUALIFIED  (VOCAB_QUALIFIED) — a LEVEL token, then, for the levels
#              VOCAB_<FIELD>_QUALIFIED names, exactly one REASON token from
#              VOCAB_<FIELD>_REASONS; a level not named takes none. The
#              reasons VOCAB_<FIELD>_RESERVED names have ONE WRITER, the risk
#              rule: refused unless the caller declares itself so with
#              `--writer risk-rule`. The default writer is the planner, so a
#              ticket, a stamp or a factory line can never name one — and the
#              writer is a flag, never the environment, so no caller inherits
#              it. `Risk: high shared-layer` is one.
#   KEYED      (VOCAB_KEYED) — a requirement KEY, then one token: `Test-tier:
#              process/R41 suite`. The key is held to the requirement
#              library's bounded id (scripts/requirement.lib.sh beside this
#              file, read only when a keyed line is checked, refused without
#              it); the checker holds the token and never the id's meaning.
#              The field repeats once per key: the same key with two tokens
#              is refused, the same key with the same token is one answer.
# A rule reads one token, so no rule may name a query, qualified or keyed
# field. The kit's ADR-0037 fixes the ticket contract these serve.
#
# LINE BOUNDS are policy too, PUBLISHED here for every reader of a stamp:
# VOCAB_BOUND is how many lines of one stamp key a reader lifts, VOCAB_BOUNDS
# its per-field exceptions (`test-tier=32`). The checker validates them and
# prints them under `fields`; scripts/stamp.sh enforces them. A policy that
# declares none prints none, and that reader keeps its own bound of 8.
#
# The caller hands it BARE `Field: value` lines. A markdown-wrapped line —
# `- Tier: implementer`, `**Tier:** implementer` — is not a decision line to
# it: the key it reads is `- Tier` or `**Tier`, no declared field, so the line
# is ignored like any other prose and its value is never checked. Lifting a
# line out of its markup is the caller's job, and so is refusing a return
# that should have been nothing but decision lines and was not.
#
# STREAMS AND EXIT CODES. stdout carries the answer and nothing else: `check`
# prints nothing, `fields` prints one field per line, an open one marked
# `(open)`, a query one marked `(query)` with no tokens (its value is a trace
# filter held to a grammar, VOCAB_QUERY), a qualified one marked
# `(qualified)` with its levels, the reasons and the reserved reasons, a
# keyed one marked `(keyed)` with its tokens, then a `bound:` line and a
# `bound <field>:` line per exception, then one line per rule. Every reason is on
# stderr, prefixed `x vocab:`, one line per violation naming the field, the
# value and the vocabulary. Exit 0 is legal; exit 2 is a refused value, a
# usage error, a policy file named explicitly and missing, or a policy file
# that is itself malformed — including a rule set no combination of values can
# satisfy, which is reported as a POLICY CONTRADICTION, in those words, so it
# is never mistaken for a bad value.
#
# THE VOCABULARIES ARE DATA in scripts/vocab.config.sh, one entry per field,
# tokens in a fixed CANONICAL ORDER (the order a judge is shown them, recorded
# so position bias can be measured later), and cross-field RULES as entries of
# their own. Unlike the tier mapping the kit ships that file FILLED: a model id
# is a vendor's to name and rots, a vocabulary is the kit's to name and does
# not. The same vocabularies are the defaults below, so a project with no
# policy file at all is held to the shipped words — an absent default file is
# a working state, a named and missing one is exit 2. A file that IS found is
# the whole policy: nothing of the defaults is sourced underneath it.
#
# TWO RULES EVERY TOKEN IS HELD TO, in the policy file as much as on the
# command line. Its SHAPE is the task domain's, `[a-z][a-z0-9-]*`, because a
# token may be interpolated into a variable name the way a domain is. And the
# NEUTRAL-NAME rule: a token never carries its answer in its spelling — `apply`
# and `escalate`, never `safe-to-apply` and `risky` — because a judge, model or
# agent, reads the label as evidence and follows it instead of the state.
#
# POLICY DISCOVERY, first hit wins — anchored on where THIS FILE lives, never
# on the caller's cwd, for the reason scripts/agents.lib.sh gives: a policy
# file is sourced, which is to say executed, and standing in a foreign clone
# must never run its code as you.
#   1. $VOCAB_CONFIG            — explicit; set and missing is exit 2.
#   2. <this file's repo root>/scripts/vocab.config.sh
#   3. <this file's directory>/vocab.config.sh
#
# Shared layer (see VERSION): this file is copied verbatim; the vocabularies
# in scripts/vocab.config.sh are yours, never overwritten by an update.
set -u

_vocab_here=$(cd "$(dirname "$0")" && pwd -P)

# The shape every token and every field name is held to. Spelled out again at
# the `case` sites below, for the locale reason scripts/agents.lib.sh gives: a
# bracket RANGE collates by locale, and `[!a-z]` accepts `CONTENT` under
# en_US.UTF-8. The two spellings are kept in step by hand.
VOCAB_TOKEN_SHAPE='[a-z][a-z0-9-]*'
# A token is bounded too: an open field's value (domain, class) is a
# ticket's text, so a well-formed token of any length would still reach a
# trace line unbounded. 64 bytes, the same bound a query value carries.
VOCAB_TOKEN_MAX=64

# ---------------------------------------------------------------------------
# THE SHIPPED VOCABULARIES. scripts/vocab.config.sh restates every line of
# this block, and tests/vocab-policy.test.sh holds the two equal — so a
# project that deletes the policy file is held to the same words, and one
# that edits it is held to its own. They apply ONLY when discovery finds no
# file: a file is the whole policy, never a layer over these — a rule it
# does not carry is not enforced, a field it does not name is not a field.
vocab_shipped_defaults() {
	VOCAB_FIELDS='tier label domain severity status action outcome confidence command-shaped author-kind targets class risk risk-confidence test-tier result scope'
	VOCAB_OPEN='domain class'
	VOCAB_QUERY='targets'
	VOCAB_QUALIFIED='risk'
	VOCAB_KEYED='test-tier'
	VOCAB_TIER='planner implementer mechanical reviewer'
	VOCAB_LABEL='ready-for-agent none'
	VOCAB_DOMAIN='content code tests html-report self-implemented'
	VOCAB_SEVERITY='critical high medium low'
	VOCAB_STATUS='mixed-commit unspecified specified missing'
	VOCAB_ACTION='apply reply escalate'
	VOCAB_OUTCOME='pass fail paper-cut'
	VOCAB_CONFIDENCE='low medium high'
	VOCAB_COMMAND_SHAPED='yes no'
	VOCAB_AUTHOR_KIND='bot human'
	VOCAB_RISK='low high'
	VOCAB_RISK_QUALIFIED='high'
	VOCAB_RISK_REASONS='irreversible security invisible shared-layer unclear unlearned outward'
	VOCAB_RISK_RESERVED='unlearned outward'
	VOCAB_RISK_CONFIDENCE='low medium high'
	VOCAB_TEST_TIER='unit suite e2e manual'
	VOCAB_RESULT='pass fail skipped'
	VOCAB_SCOPE='inside outward'
	VOCAB_BOUND='8'
	VOCAB_BOUNDS='test-tier=32'
	VOCAB_RULES='command-shaped=yes => action!=apply'
}

usage() {
	cat >&2 <<'USAGE'
usage: sh scripts/vocab.sh [check] [--writer <w>] [<line> …]
                                lines as arguments, or on stdin
       sh scripts/vocab.sh fields
                                print the effective vocabularies
  a line is `<Field>: <value>`; a field is one the policy file declares;
  <w> is planner (the default) or risk-rule — the one writer of a reason
  the policy reserves;
  the caller hands it bare `Field: value` lines: a markdown-wrapped line
  (`- Tier: …`, `**Tier:** …`) is not a decision line to it, and is ignored;
  a first argument with no colon is a subcommand, and only these two exist
USAGE
	exit 2
}

# ---------------------------------------------------------------------------
# Policy.

vocab_git() {
	(unset GIT_DIR GIT_WORK_TREE && git -C "$_vocab_here" "$@") 2>/dev/null
}

# vocab_load_config — the policy file found is the WHOLE policy: the three
# list variables start empty so a file that omits one is held to nothing for
# it, and the shipped words are assigned only when no file is found.
vocab_load_config() {
	VOCAB_FIELDS=
	VOCAB_OPEN=
	VOCAB_QUERY=
	VOCAB_QUALIFIED=
	VOCAB_KEYED=
	VOCAB_BOUND=
	VOCAB_BOUNDS=
	VOCAB_RULES=
	if [ -n "${VOCAB_CONFIG:-}" ]; then
		[ -f "$VOCAB_CONFIG" ] || {
			vocab_refuse "VOCAB_CONFIG=$VOCAB_CONFIG does not exist."
			exit 2
		}
		# `.` searches $PATH for a slash-less operand; the file the test
		# above saw is the cwd's, so name it as such.
		case $VOCAB_CONFIG in
		*/*) . "$VOCAB_CONFIG" ;;
		*) . "./$VOCAB_CONFIG" ;;
		esac
		return 0
	fi
	_vl_root=$(vocab_git rev-parse --show-toplevel) || _vl_root=
	if [ -n "$_vl_root" ] && [ -f "$_vl_root/scripts/vocab.config.sh" ]; then
		. "$_vl_root/scripts/vocab.config.sh"
	elif [ -f "$_vocab_here/vocab.config.sh" ]; then
		. "$_vocab_here/vocab.config.sh"
	else
		vocab_shipped_defaults
	fi
	return 0
}

# vocab_var <field> — the policy variable a field's tokens live in:
# upper-cased, hyphens folded to underscores, as AGENT_TIER_<TIER>_<DOMAIN>
# folds a domain.
vocab_var() { printf 'VOCAB_%s' "$(printf '%s' "$1" | tr 'a-z-' 'A-Z_')"; }

# vocab_tokens <field> — the field's tokens, in canonical order, on stdout.
vocab_tokens() { eval "printf '%s' \"\${$(vocab_var "$1"):-}\""; }

# vocab_is_field <name> — is it a declared field? A `case` against a padded
# string, not a loop over an unquoted expansion, for the zsh reason the
# resolver documents (SH_WORD_SPLIT). A candidate with a space in it —
# `planner implementer` — is contiguous text INSIDE the list and must not
# pass as a member; the guard is trace_is_kind's, for the same reason.
vocab_in_list() {
	case $2 in
	'' | *' '*) return 1 ;;
	esac
	case " $1 " in
	*" $2 "*) return 0 ;;
	esac
	return 1
}

vocab_is_field() { vocab_in_list "$VOCAB_FIELDS" "$1"; }

vocab_is_open() { vocab_in_list "${VOCAB_OPEN:-}" "$1"; }

vocab_is_query() { vocab_in_list "${VOCAB_QUERY:-}" "$1"; }

vocab_is_qualified() { vocab_in_list "${VOCAB_QUALIFIED:-}" "$1"; }

vocab_is_keyed() { vocab_in_list "${VOCAB_KEYED:-}" "$1"; }

# vocab_sub <field> <part> — a qualified field's own list: QUALIFIED,
# REASONS or RESERVED, in VOCAB_<FIELD>_<PART>.
vocab_sub() { eval "printf '%s' \"\${$(vocab_var "$1")_$2:-}\""; }

# vocab_req_id_ok <id> — a bounded requirement id, in the requirement
# library's grammar (REQ_BOUNDED_ID_ERE), the library sourced from beside
# this file on first use. Returns 2 when the library is missing.
_vocab_req_loaded=0
vocab_req_id_ok() {
	if [ "$_vocab_req_loaded" = 0 ]; then
		[ -r "$_vocab_here/requirement.lib.sh" ] || return 2
		# shellcheck disable=SC1091
		. "$_vocab_here/requirement.lib.sh"
		[ -n "${REQ_BOUNDED_ID_ERE:-}" ] || return 2
		_vocab_req_loaded=1
	fi
	case $1 in *"$_vocab_nl"*) return 1 ;; esac
	printf '%s\n' "$1" | LC_ALL=C grep -Eqx "$REQ_BOUNDED_ID_ERE"
}

# vocab_query_ok <field> <value> — a QUERY field's value is a trace filter,
# held to a grammar because no token set can hold it: one to
# VOCAB_QUERY_TERMS `<key>=<value>` terms split on blanks, exactly one of them
# `kind=`, no key twice; a key is a field name or `data.<key>` in the trace's
# own `[a-z][a-z0-9_]*`; a value is `[a-z0-9][a-z0-9._-]*`, at most 64
# characters. That alphabet is the point: the value is ticket text, and a
# filter that passes here carries nothing a shell, awk or a JSON reader would
# read as syntax. Mechanism, not policy — a literal, like the neutral list.
VOCAB_QUERY_TERMS=8
vocab_query_ok() {
	_qo_field=$1
	# Split the value into terms once, with globbing off, so a term is never
	# expanded against the cwd and no return path has to restore it.
	set -f
	# shellcheck disable=SC2086  # the split into terms is the point
	set -- $2
	set +f
	if [ $# -gt "$VOCAB_QUERY_TERMS" ]; then
		vocab_refuse "$_qo_field: more than $VOCAB_QUERY_TERMS terms — a filter is bounded"
		return 1
	fi
	_qo_keys=' '
	_qo_kind=0
	for _qo_t in "$@"; do
		case $_qo_t in
		*=*) ;;
		*)
			vocab_refuse "$_qo_field: '$_qo_t' is not a <key>=<value> term"
			return 1
			;;
		esac
		_qo_k=${_qo_t%%=*}
		_qo_v=${_qo_t#*=}
		case ${_qo_k#data.} in
		'' | [!abcdefghijklmnopqrstuvwxyz]* | *[!abcdefghijklmnopqrstuvwxyz0123456789_]*)
			vocab_refuse "$_qo_field: '$_qo_k' is not a field name or data.<key> — a key is [a-z][a-z0-9_]*"
			return 1
			;;
		esac
		case $_qo_v in
		'' | [!abcdefghijklmnopqrstuvwxyz0123456789]* | *[!abcdefghijklmnopqrstuvwxyz0123456789._-]*)
			vocab_refuse "$_qo_field: the value of '$_qo_k' is not [a-z0-9][a-z0-9._-]*"
			return 1
			;;
		esac
		if [ "${#_qo_v}" -gt 64 ]; then
			vocab_refuse "$_qo_field: the value of '$_qo_k' is longer than 64 characters"
			return 1
		fi
		case $_qo_keys in
		*" $_qo_k "*)
			vocab_refuse "$_qo_field: the key '$_qo_k' appears twice — one value per key"
			return 1
			;;
		esac
		_qo_keys="$_qo_keys$_qo_k "
		[ "$_qo_k" = kind ] && _qo_kind=1
	done
	if [ "$_qo_kind" = 0 ]; then
		vocab_refuse "$_qo_field: the filter names no kind= term — a filter is over one kind"
		return 1
	fi
	return 0
}

# vocab_has_token <field> <value> — membership in the field's vocabulary: one
# token, matched whole.
vocab_has_token() { vocab_in_list "$(vocab_tokens "$1")" "$2"; }

# vocab_shape_ok <token> — the task-domain shape, alphabet spelled out.
vocab_shape_ok() {
	[ "${#1}" -le "$VOCAB_TOKEN_MAX" ] || return 1
	case $1 in
	'' | [!abcdefghijklmnopqrstuvwxyz]* | *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;;
	esac
	return 0
}

# vocab_neutral_ok <token> — THE NEUTRAL-NAME RULE, as a deny list of the
# words that carry an answer: a token any of whose hyphen-separated words is
# one of these is refused, and the word is left in $_vocab_answer_word for
# the refusal to quote. These are words that EVALUATE the option they name
# (`safe-to-apply`, `risky`, `best-effort`), never words that merely name a
# level or a category (`high`, `fail`, `yes`) — a level is what the judge
# decides, an evaluation is the judge told what to decide. Mechanism, not
# policy: the list is a literal here and not a VOCAB_* variable, because a
# policy file is sourced into this shell and one that could reassign the
# list would have no rule (the reason scripts/agents.lib.sh keeps no list
# variable for the tiers).
vocab_neutral_ok() {
	_no_rest=$1
	while [ -n "$_no_rest" ]; do
		_vocab_answer_word=${_no_rest%%-*}
		case " safe unsafe risky right wrong correct incorrect good bad best worst better worse ok okay recommended preferred obvious proper improper " in
		*" $_vocab_answer_word "*) return 1 ;;
		esac
		case $_no_rest in
		*-*) _no_rest=${_no_rest#*-} ;;
		*) _no_rest= ;;
		esac
	done
	return 0
}

# ---------------------------------------------------------------------------
# Refusals. Every reason is one stderr line; the first refusal flips the exit.

_vocab_bad=0
vocab_refuse() {
	_vocab_bad=1
	echo "x vocab: $*" >&2
}

# ---------------------------------------------------------------------------
# Rules. `<field>=<value> => <field>=<value>` or `… => <field>!=<value>`, one
# per line of VOCAB_RULES. Parsed once into a canonical spelling so a refusal
# quotes the rule one way however the file spaced it.

# vocab_rule_parts <rule> — sets _r_af _r_av _r_cf _r_op _r_cv and _r_text
# (the canonical spelling); returns 1 on a malformed rule.
vocab_rule_parts() {
	case $1 in
	*'=>'*) ;;
	*) return 1 ;;
	esac
	_rp_lhs=$(vocab_trim "${1%%=>*}")
	_rp_rhs=$(vocab_trim "${1#*=>}")
	case $_rp_lhs in
	*=*) ;;
	*) return 1 ;;
	esac
	_r_af=$(vocab_trim "${_rp_lhs%%=*}")
	_r_av=$(vocab_trim "${_rp_lhs#*=}")
	case $_rp_rhs in
	*'!='*)
		_r_op='!='
		_r_cf=$(vocab_trim "${_rp_rhs%%!=*}")
		_r_cv=$(vocab_trim "${_rp_rhs#*!=}")
		;;
	*=*)
		_r_op='='
		_r_cf=$(vocab_trim "${_rp_rhs%%=*}")
		_r_cv=$(vocab_trim "${_rp_rhs#*=}")
		;;
	*) return 1 ;;
	esac
	[ -n "$_r_af" ] && [ -n "$_r_av" ] && [ -n "$_r_cf" ] && [ -n "$_r_cv" ] || return 1
	_r_text="$_r_af=$_r_av => $_r_cf$_r_op$_r_cv"
	return 0
}

# vocab_rule_side_ok <rule text> <field> <value> — the half of a rule names a
# declared field and a value that field admits.
vocab_rule_side_ok() {
	if ! vocab_is_field "$2"; then
		vocab_refuse "policy: rule '$1' names '$2', which is not a declared field"
		return 1
	fi
	if vocab_is_query "$2"; then
		vocab_refuse "policy: rule '$1' names '$2', a query field — a rule reads tokens, and a query has none"
		return 1
	fi
	if vocab_is_qualified "$2" || vocab_is_keyed "$2"; then
		vocab_refuse "policy: rule '$1' names '$2', a qualified or keyed field — a rule reads one token, and its value holds two"
		return 1
	fi
	if vocab_is_open "$2"; then
		vocab_shape_ok "$3" || {
			vocab_refuse "policy: rule '$1' names '$3', which is not a well-formed token"
			return 1
		}
	elif ! vocab_has_token "$2" "$3"; then
		vocab_refuse "policy: rule '$1' names '$3', which $2 does not declare"
		return 1
	fi
	return 0
}

# vocab_each_rule <callback> — the callback once per non-blank rule line,
# with the parsed parts set. Runs in the current shell so a callback's
# refusals count.
vocab_each_rule() {
	_er_rest=${VOCAB_RULES:-}
	while [ -n "$_er_rest" ]; do
		case $_er_rest in
		*"$_vocab_nl"*)
			_er_line=${_er_rest%%"$_vocab_nl"*}
			_er_rest=${_er_rest#*"$_vocab_nl"}
			;;
		*)
			_er_line=$_er_rest
			_er_rest=
			;;
		esac
		_er_line=$(vocab_trim "$_er_line")
		[ -n "$_er_line" ] || continue
		"$1" "$_er_line"
	done
}
_vocab_nl=$(printf '\nx')
_vocab_nl=${_vocab_nl%x}

# vocab_conflicts <as-one|by-antecedent> — stdin carries `T <field> <tokens…>`
# for every closed field and `R <af> <av> <cf> <op> <cv>` for the rules under
# test. Rules are judged in GROUPS whose antecedents all hold at once: at
# check time the triggered set is one group (`as-one`), at load time every
# rule sharing an antecedent is one (`by-antecedent`). Prints one line per
# way a group cannot be satisfied: two rules demanding different values of
# one field, a rule demanding a value another excludes, or exclusions
# covering every token of a closed field. Empty output is a satisfiable set.
vocab_conflicts() {
	case $1 in
	as-one | by-antecedent) ;;
	*)
		echo "x vocab: internal: unknown grouping '$1' — as-one or by-antecedent" >&2
		return 2
		;;
	esac
	awk -v grouping="$1" '
	function q(s) { return "\047" s "\047" }
	function both(a, b) { print "policy contradiction: " q(a) " and " q(b) " cannot both hold" }
	$1 == "T" { ntok[$2] = NF - 2; next }
	$1 == "R" {
		g = grouping == "by-antecedent" ? $2 "=" $3 : ""
		cf = $4; op = $5; cv = $6
		r = $2 "=" $3 " => " cf op cv
		if (op == "=") {
			if ((g, cf) in eq) { if (eqv[g, cf] != cv) both(eq[g, cf], r) }
			else { eq[g, cf] = r; eqv[g, cf] = cv }
			if ((g, cf, cv) in ne) both(ne[g, cf, cv], r)
		} else {
			if (!((g, cf, cv) in ne)) {
				ne[g, cf, cv] = r; nen[g, cf]++
				nel[g, cf] = nel[g, cf] (nel[g, cf] ? "; " : "") r
				nef[g, cf] = cf
			}
			if ((g, cf) in eq && eqv[g, cf] == cv) both(eq[g, cf], r)
		}
	}
	END {
		for (k in nen) {
			f = nef[k]
			if ((f in ntok) && nen[k] >= ntok[f])
				print "policy contradiction: the rules on " f " exclude every one of its tokens: " nel[k]
		}
	}'
}

# vocab_token_lines — the `T` lines vocab_conflicts reads.
vocab_token_lines() {
	for _tl_f in $VOCAB_FIELDS; do
		vocab_is_open "$_tl_f" && continue
		vocab_is_query "$_tl_f" && continue
		vocab_is_qualified "$_tl_f" && continue
		vocab_is_keyed "$_tl_f" && continue
		printf 'T %s %s\n' "$_tl_f" "$(vocab_tokens "$_tl_f")"
	done
}

# vocab_report_conflicts <R lines> <as-one|by-antecedent> — run the detector
# and refuse each finding.
vocab_report_conflicts() {
	[ -n "$1" ] || return 0
	_rc_out=$({ vocab_token_lines; printf '%s\n' "$1"; } | vocab_conflicts "$2")
	[ -n "$_rc_out" ] || return 0
	printf '%s\n' "$_rc_out" | while IFS= read -r _rc_line; do
		echo "x vocab: $_rc_line" >&2
	done
	_vocab_bad=1
	return 1
}

# ---------------------------------------------------------------------------
# The policy, validated at load: field names and tokens have the shape,
# tokens are neutral, every closed field has tokens, every rule names what
# the file declares, and rules that share an antecedent can hold together.

vocab_check_policy_rule() {
	if ! vocab_rule_parts "$1"; then
		vocab_refuse "policy: rule '$1' is malformed — expected '<field>=<value> => <field>=<value>' or '… => <field>!=<value>'"
		return 0
	fi
	vocab_rule_side_ok "$_r_text" "$_r_af" "$_r_av" || return 0
	vocab_rule_side_ok "$_r_text" "$_r_cf" "$_r_cv" || return 0
	_vocab_rule_lines="$_vocab_rule_lines${_vocab_rule_lines:+$_vocab_nl}R $_r_af $_r_av $_r_cf $_r_op $_r_cv"
	return 0
}

vocab_validate_policy() {
	[ -n "${VOCAB_FIELDS:-}" ] || vocab_refuse "policy: VOCAB_FIELDS declares no field"
	for _vp_f in $VOCAB_FIELDS; do
		vocab_shape_ok "$_vp_f" || {
			vocab_refuse "policy: field name '$_vp_f' is not a well-formed token — a field is a $VOCAB_TOKEN_SHAPE of at most $VOCAB_TOKEN_MAX bytes"
			continue
		}
		# A field's tokens live in VOCAB_<FIELD>, the namespace the checker's
		# own variables share: a field named `fields` would make the field
		# list its own vocabulary, silently.
		case $_vp_f in
		fields | open | rules | token-shape | config | qualified | keyed | bound | bounds)
			vocab_refuse "policy: field name '$_vp_f' is reserved — $(vocab_var "$_vp_f") is the checker's own variable"
			continue
			;;
		esac
		for _vp_q in ${VOCAB_QUALIFIED:-}; do
			case $_vp_f in
			"$_vp_q-qualified" | "$_vp_q-reasons" | "$_vp_q-reserved")
				vocab_refuse "policy: field name '$_vp_f' is reserved — $(vocab_var "$_vp_f") is qualified field '$_vp_q''s own list"
				continue 2
				;;
			esac
		done
		_vp_kinds=0
		for _vp_k in open query qualified keyed; do
			"vocab_is_$_vp_k" "$_vp_f" && _vp_kinds=$((_vp_kinds + 1))
		done
		[ "$_vp_kinds" -le 1 ] ||
			vocab_refuse "policy: field '$_vp_f' is declared more than one of open, query, qualified and keyed — one kind per field"
		_vp_tokens=$(vocab_tokens "$_vp_f")
		if vocab_is_query "$_vp_f"; then
			[ -z "$_vp_tokens" ] || vocab_refuse "policy: field '$_vp_f' is a query and declares tokens ($(vocab_var "$_vp_f")) — a query is held to its grammar, never to tokens"
			continue
		fi
		if [ -z "$_vp_tokens" ] && ! vocab_is_open "$_vp_f"; then
			vocab_refuse "policy: field '$_vp_f' declares no tokens ($(vocab_var "$_vp_f") is empty)"
			continue
		fi
		for _vp_t in $_vp_tokens; do
			vocab_shape_ok "$_vp_t" || {
				vocab_refuse "policy: $_vp_f token '$_vp_t' is not a well-formed token — a token is a $VOCAB_TOKEN_SHAPE of at most $VOCAB_TOKEN_MAX bytes"
				continue
			}
			vocab_neutral_ok "$_vp_t" ||
				vocab_refuse "policy: $_vp_f token '$_vp_t' carries its answer in its spelling ('$_vocab_answer_word') — tokens are neutral names"
		done
		vocab_is_qualified "$_vp_f" && vocab_validate_qualified "$_vp_f"
	done
	for _vp_list in QUERY QUALIFIED KEYED; do
		for _vp_q in $(eval "printf '%s' \"\${VOCAB_$_vp_list:-}\""); do
			vocab_is_field "$_vp_q" || vocab_refuse "policy: VOCAB_$_vp_list names '$_vp_q', which is not a declared field"
		done
	done
	vocab_validate_bounds
	_vocab_rule_lines=
	vocab_each_rule vocab_check_policy_rule
	# Rules sharing an antecedent all fire together: hold each such group.
	vocab_report_conflicts "$_vocab_rule_lines" by-antecedent
	return 0
}

# vocab_validate_qualified <field> — the levels that take a reason are
# levels; the reasons are well-formed, neutral and declared; the reserved
# reasons are reasons.
vocab_validate_qualified() {
	_vq_levels=$(vocab_tokens "$1")
	_vq_reasons=$(vocab_sub "$1" REASONS)
	[ -n "$(vocab_sub "$1" QUALIFIED)" ] ||
		vocab_refuse "policy: qualified field '$1' names no level that takes a reason ($(vocab_var "$1")_QUALIFIED is empty)"
	[ -n "$_vq_reasons" ] ||
		vocab_refuse "policy: qualified field '$1' declares no reasons ($(vocab_var "$1")_REASONS is empty)"
	for _vq_l in $(vocab_sub "$1" QUALIFIED); do
		vocab_in_list "$_vq_levels" "$_vq_l" ||
			vocab_refuse "policy: $1 qualifies '$_vq_l', which is not one of its levels ($_vq_levels)"
	done
	for _vq_r in $_vq_reasons; do
		vocab_shape_ok "$_vq_r" || {
			vocab_refuse "policy: $1 reason '$_vq_r' is not a well-formed token — a token is a $VOCAB_TOKEN_SHAPE of at most $VOCAB_TOKEN_MAX bytes"
			continue
		}
		vocab_neutral_ok "$_vq_r" ||
			vocab_refuse "policy: $1 reason '$_vq_r' carries its answer in its spelling ('$_vocab_answer_word') — tokens are neutral names"
	done
	for _vq_r in $(vocab_sub "$1" RESERVED); do
		vocab_in_list "$_vq_reasons" "$_vq_r" ||
			vocab_refuse "policy: $1 reserves '$_vq_r', which is not one of its reasons ($_vq_reasons)"
	done
	return 0
}

# vocab_count_ok <n> — a count of lines: 1 to 999, digits only.
vocab_count_ok() {
	case $1 in
	'' | 0* | *[!0123456789]* | ????*) return 1 ;;
	esac
	return 0
}

# vocab_validate_bounds — VOCAB_BOUND a count, each VOCAB_BOUNDS entry a
# declared field and a count. Both may be empty: a policy that predates them.
vocab_validate_bounds() {
	if [ -n "${VOCAB_BOUND:-}" ] && ! vocab_count_ok "$VOCAB_BOUND"; then
		vocab_refuse "policy: VOCAB_BOUND '$VOCAB_BOUND' is not a count of lines — 1 to 999"
	fi
	for _vb_e in ${VOCAB_BOUNDS:-}; do
		_vb_f=${_vb_e%%=*}
		_vb_n=${_vb_e#*=}
		case $_vb_e in
		*=*) ;;
		*)
			vocab_refuse "policy: VOCAB_BOUNDS entry '$_vb_e' is not <field>=<count>"
			continue
			;;
		esac
		vocab_is_field "$_vb_f" || {
			vocab_refuse "policy: VOCAB_BOUNDS names '$_vb_f', which is not a declared field"
			continue
		}
		vocab_count_ok "$_vb_n" ||
			vocab_refuse "policy: VOCAB_BOUNDS gives $_vb_f '$_vb_n', which is not a count of lines — 1 to 999"
	done
	return 0
}

# ---------------------------------------------------------------------------
# Checking values.

vocab_trim() {
	printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# vocab_field_key <raw key> — a line's key folded to a field name: case
# dropped, spaces and underscores read as hyphens, surrounding blanks trimmed.
vocab_field_key() {
	printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
		-e 's/[[:space:]_][[:space:]_]*/-/g' | tr 'A-Z' 'a-z'
}

# vocab_check_value <field> <value> — one pair against its vocabulary.
vocab_check_value() {
	if [ -z "$2" ]; then
		vocab_refuse "$1: the value is empty; expected one of $(vocab_tokens "$1")"
		return 1
	fi
	if vocab_is_query "$1"; then
		vocab_query_ok "$1" "$2"
		return
	fi
	# A CLOSED field answers by membership, whatever the value's shape: a
	# reader of `Tier: Implementor` wants the four names, not a note about
	# capitals. Membership implies the shape, because every token in the
	# policy file passed it at load. An OPEN field has only the shape.
	if vocab_is_open "$1"; then
		if ! vocab_shape_ok "$2"; then
			vocab_refuse "$1: '$2' is not a well-formed token — a token is a $VOCAB_TOKEN_SHAPE of at most $VOCAB_TOKEN_MAX bytes"
			return 1
		fi
		return 0
	fi
	if ! vocab_has_token "$1" "$2"; then
		vocab_refuse "$1: '$2' is not one of $(vocab_tokens "$1")"
		return 1
	fi
	return 0
}

# vocab_check_qualified <field> <value> — a level, then one reason for a
# level that takes one; a reserved reason only from the risk rule. Leaves
# the value with single blanks in $_vocab_norm, for the repeat check.
vocab_check_qualified() {
	_cq_f=$1
	_cq_levels=$(vocab_tokens "$_cq_f")
	_cq_reasons=$(vocab_sub "$_cq_f" REASONS)
	set -f
	# shellcheck disable=SC2086  # the split into level and reason is the point
	set -- $2
	set +f
	if [ $# = 0 ]; then
		vocab_refuse "$_cq_f: the value is empty; expected one of $_cq_levels"
		return 1
	fi
	if ! vocab_in_list "$_cq_levels" "$1"; then
		vocab_refuse "$_cq_f: '$1' is not one of $_cq_levels"
		return 1
	fi
	if ! vocab_in_list "$(vocab_sub "$_cq_f" QUALIFIED)" "$1"; then
		if [ $# != 1 ]; then
			vocab_refuse "$_cq_f: '$1' takes no reason — the level stands alone"
			return 1
		fi
		_vocab_norm=$1
		return 0
	fi
	if [ $# != 2 ]; then
		vocab_refuse "$_cq_f: '$1' takes exactly one reason, one of $_cq_reasons"
		return 1
	fi
	if ! vocab_in_list "$_cq_reasons" "$2"; then
		vocab_refuse "$_cq_f: '$2' is not one of $_cq_reasons"
		return 1
	fi
	if vocab_in_list "$(vocab_sub "$_cq_f" RESERVED)" "$2" && [ "$_vocab_writer" != risk-rule ]; then
		vocab_refuse "$_cq_f: the reason '$2' is reserved for the risk rule — this caller writes as the $_vocab_writer"
		return 1
	fi
	_vocab_norm="$1 $2"
	return 0
}

# vocab_check_keyed <field> <value> — a requirement id, then one token; one
# token per id across the lines, in $_vocab_keyed as `<field> <id> <token>`.
_vocab_keyed=
vocab_check_keyed() {
	_ck_f=$1
	_ck_tokens=$(vocab_tokens "$_ck_f")
	set -f
	# shellcheck disable=SC2086  # the split into id and token is the point
	set -- $2
	set +f
	if [ $# != 2 ]; then
		vocab_refuse "$_ck_f: expected '<requirement id> <tier>', the tier one of $_ck_tokens"
		return 1
	fi
	vocab_req_id_ok "$1"
	case $? in
	0) ;;
	2)
		vocab_refuse "$_ck_f: the requirement grammar $_vocab_here/requirement.lib.sh is missing beside the checker — no id can be read"
		return 1
		;;
	*)
		vocab_refuse "$_ck_f: the id is not a requirement id — R<n> or <area>/R<n>, the area at most 32 characters, n at most 6 digits"
		return 1
		;;
	esac
	if ! vocab_in_list "$_ck_tokens" "$2"; then
		vocab_refuse "$_ck_f: '$2' is not one of $_ck_tokens"
		return 1
	fi
	_ck_prev=$(printf '%s\n' "$_vocab_keyed" | awk -v f="$_ck_f" -v k="$1" '$1 == f && $2 == k { print $3; exit }')
	if [ -n "$_ck_prev" ]; then
		[ "$_ck_prev" = "$2" ] && return 0
		vocab_refuse "$_ck_f: '$1' is given two tiers, '$2' after '$_ck_prev' — one per requirement id"
		return 1
	fi
	_vocab_keyed="$_vocab_keyed${_vocab_keyed:+$_vocab_nl}$_ck_f $1 $2"
	return 0
}

# The values seen so far, per field, for the rules: _vocab_val_<VAR>=<value>.
# A remembered value is never empty — vocab_check_value refused it first —
# so an empty answer from vocab_value_of means the field was not seen. The
# last line for a field is the one the rules read.
vocab_remember() {
	eval "_vocab_val_$(vocab_var "$1")=\$2"
}
vocab_value_of() { eval "printf '%s' \"\${_vocab_val_$(vocab_var "$1"):-}\""; }

# vocab_check_line <line> — a decision line, or not one. A line with no colon,
# or whose key is not a declared field, is ignored: prose beside a decision
# line is not a judgment, and a body is the caller's to lift (see the header).
vocab_check_line() {
	case $1 in
	*:*) ;;
	*) return 0 ;;
	esac
	_cl_key=$(vocab_field_key "${1%%:*}")
	vocab_is_field "$_cl_key" || return 0
	_cl_value=$(vocab_trim "${1#*:}")
	if vocab_is_keyed "$_cl_key"; then
		vocab_check_keyed "$_cl_key" "$_cl_value"
		return 0
	fi
	if vocab_is_qualified "$_cl_key"; then
		vocab_check_qualified "$_cl_key" "$_cl_value" || return 0
		_cl_value=$_vocab_norm
	else
		vocab_check_value "$_cl_key" "$_cl_value" || return 0
	fi
	# A field said twice with two values has no value: refused, whichever
	# line comes last, so one appended line cannot withdraw a firing rule's
	# antecedent or replace its consequent in an untrusted body.
	_cl_prev=$(vocab_value_of "$_cl_key")
	if [ -n "$_cl_prev" ] && [ "$_cl_prev" != "$_cl_value" ]; then
		vocab_refuse "$_cl_key: '$_cl_value' repeats the field, which already read '$_cl_prev' — one value per field"
		return 0
	fi
	vocab_remember "$_cl_key" "$_cl_value"
	return 0
}

# vocab_apply_rule <rule> — one rule against the values seen: silent unless
# its antecedent holds; then the consequent's field, if seen, must comply.
# Triggered rules are collected for the contradiction pass.
vocab_apply_rule() {
	# The call sets the _r_* parts; its failure branch is unreachable, since
	# load-time validation refused every malformed rule before dispatch.
	vocab_rule_parts "$1" || return 0
	# $_r_av is never empty (vocab_rule_parts), so an unseen field's "" never matches.
	[ "$(vocab_value_of "$_r_af")" = "$_r_av" ] || return 0
	_vocab_fired="$_vocab_fired${_vocab_fired:+$_vocab_nl}R $_r_af $_r_av $_r_cf $_r_op $_r_cv"
	_ar_v=$(vocab_value_of "$_r_cf")
	[ -n "$_ar_v" ] || return 0
	case $_r_op in
	=) [ "$_ar_v" = "$_r_cv" ] || vocab_refuse "$_r_cf: '$_ar_v' is refused by the rule $_r_text" ;;
	'!=') [ "$_ar_v" != "$_r_cv" ] || vocab_refuse "$_r_cf: '$_ar_v' is refused by the rule $_r_text" ;;
	esac
	return 0
}

_vocab_writer=planner
vocab_check() {
	if [ "${1:-}" = --writer ]; then
		[ $# -ge 2 ] || usage
		case $2 in
		planner | risk-rule) _vocab_writer=$2 ;;
		*) usage ;;
		esac
		shift 2
	fi
	if [ $# -gt 0 ]; then
		for _vc_line in "$@"; do
			vocab_check_line "$_vc_line"
		done
	else
		while IFS= read -r _vc_line || [ -n "$_vc_line" ]; do
			vocab_check_line "$_vc_line"
		done
	fi
	_vocab_fired=
	vocab_each_rule vocab_apply_rule
	vocab_report_conflicts "$_vocab_fired" as-one
	[ "$_vocab_bad" = 0 ] || exit 2
	exit 0
}

vocab_print_rule() {
	# Unreachable failure branch, as in vocab_apply_rule.
	vocab_rule_parts "$1" && printf 'rule: %s\n' "$_r_text"
}

vocab_fields() {
	for _vf_field in $VOCAB_FIELDS; do
		if vocab_is_query "$_vf_field"; then
			printf '%s (query):\n' "$_vf_field"
		elif vocab_is_open "$_vf_field"; then
			printf '%s (open): %s\n' "$_vf_field" "$(vocab_tokens "$_vf_field")"
		elif vocab_is_qualified "$_vf_field"; then
			printf '%s (qualified): %s; reasons for %s: %s' "$_vf_field" "$(vocab_tokens "$_vf_field")" \
				"$(vocab_sub "$_vf_field" QUALIFIED)" "$(vocab_sub "$_vf_field" REASONS)"
			[ -z "$(vocab_sub "$_vf_field" RESERVED)" ] || printf '; reserved: %s' "$(vocab_sub "$_vf_field" RESERVED)"
			printf '\n'
		elif vocab_is_keyed "$_vf_field"; then
			printf '%s (keyed): %s\n' "$_vf_field" "$(vocab_tokens "$_vf_field")"
		else
			printf '%s: %s\n' "$_vf_field" "$(vocab_tokens "$_vf_field")"
		fi
	done
	[ -z "${VOCAB_BOUND:-}" ] || printf 'bound: %s\n' "$VOCAB_BOUND"
	for _vf_b in ${VOCAB_BOUNDS:-}; do
		printf 'bound %s: %s\n' "${_vf_b%%=*}" "${_vf_b#*=}"
	done
	vocab_each_rule vocab_print_rule
	exit 0
}

# ---------------------------------------------------------------------------
# Dispatch.

vocab_load_config
vocab_validate_policy
[ "$_vocab_bad" = 0 ] || exit 2

case "${1:-check}" in
check)
	[ $# -gt 0 ] && shift
	vocab_check "$@"
	;;
fields)
	[ $# -eq 1 ] || usage
	vocab_fields
	;;
--writer) vocab_check "$@" ;;
-*) usage ;;
*)
	# A bare line as the first argument — `sh scripts/vocab.sh 'Tier: x'` —
	# is the check, exactly as the usage line says. A first argument with
	# no colon is not a line: it is a subcommand nobody declared, and a
	# silent exit 0 on `fieldz` would be a pass the caller never earned.
	case $1 in
	*:*) vocab_check "$@" ;;
	*) usage ;;
	esac
	;;
esac
