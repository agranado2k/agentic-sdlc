#!/bin/sh
# vocab.sh — THE vocabulary checker. One implementation, every caller.
#
#   sh scripts/vocab.sh [check] [<line> …]     lines as arguments, or on stdin
#                                              when none are given
#   sh scripts/vocab.sh fields                 print the effective vocabularies
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
# exactly, one token whole. A field that appears twice with two different
# values is refused — a body with two answers has none, and a line appended
# to it cannot withdraw a rule — while the same value repeated is one answer.
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
# `(open)`, then one line per rule. Every reason is on
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

# ---------------------------------------------------------------------------
# THE SHIPPED VOCABULARIES. scripts/vocab.config.sh restates every line of
# this block, and tests/vocab-policy.test.sh holds the two equal — so a
# project that deletes the policy file is held to the same words, and one
# that edits it is held to its own. They apply ONLY when discovery finds no
# file: a file is the whole policy, never a layer over these — a rule it
# does not carry is not enforced, a field it does not name is not a field.
vocab_shipped_defaults() {
	VOCAB_FIELDS='tier label domain severity status action outcome confidence command-shaped author-kind'
	VOCAB_OPEN='domain'
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
	VOCAB_RULES='command-shaped=yes => action!=apply'
}

usage() {
	cat >&2 <<'USAGE'
usage: sh scripts/vocab.sh [check] [<line> …]   lines as arguments, or on stdin
       sh scripts/vocab.sh fields               print the effective vocabularies
  a line is `<Field>: <value>`; a field is one the policy file declares;
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

# vocab_has_token <field> <value> — membership in the field's vocabulary: one
# token, matched whole.
vocab_has_token() { vocab_in_list "$(vocab_tokens "$1")" "$2"; }

# vocab_shape_ok <token> — the task-domain shape, alphabet spelled out.
vocab_shape_ok() {
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
			vocab_refuse "policy: field name '$_vp_f' is not a well-formed token — a field is a $VOCAB_TOKEN_SHAPE"
			continue
		}
		# A field's tokens live in VOCAB_<FIELD>, the namespace the checker's
		# own variables share: a field named `fields` would make the field
		# list its own vocabulary, silently.
		case $_vp_f in
		fields | open | rules | token-shape | config)
			vocab_refuse "policy: field name '$_vp_f' is reserved — $(vocab_var "$_vp_f") is the checker's own variable"
			continue
			;;
		esac
		_vp_tokens=$(vocab_tokens "$_vp_f")
		if [ -z "$_vp_tokens" ] && ! vocab_is_open "$_vp_f"; then
			vocab_refuse "policy: field '$_vp_f' declares no tokens ($(vocab_var "$_vp_f") is empty)"
			continue
		fi
		for _vp_t in $_vp_tokens; do
			vocab_shape_ok "$_vp_t" || {
				vocab_refuse "policy: $_vp_f token '$_vp_t' is not a well-formed token — a token is a $VOCAB_TOKEN_SHAPE"
				continue
			}
			vocab_neutral_ok "$_vp_t" ||
				vocab_refuse "policy: $_vp_f token '$_vp_t' carries its answer in its spelling ('$_vocab_answer_word') — tokens are neutral names"
		done
	done
	_vocab_rule_lines=
	vocab_each_rule vocab_check_policy_rule
	# Rules sharing an antecedent all fire together: hold each such group.
	vocab_report_conflicts "$_vocab_rule_lines" by-antecedent
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
	# A CLOSED field answers by membership, whatever the value's shape: a
	# reader of `Tier: Implementor` wants the four names, not a note about
	# capitals. Membership implies the shape, because every token in the
	# policy file passed it at load. An OPEN field has only the shape.
	if vocab_is_open "$1"; then
		if ! vocab_shape_ok "$2"; then
			vocab_refuse "$1: '$2' is not a well-formed token — a token is a $VOCAB_TOKEN_SHAPE"
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
	vocab_check_value "$_cl_key" "$_cl_value" || return 0
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

vocab_check() {
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
		if vocab_is_open "$_vf_field"; then
			printf '%s (open): %s\n' "$_vf_field" "$(vocab_tokens "$_vf_field")"
		else
			printf '%s: %s\n' "$_vf_field" "$(vocab_tokens "$_vf_field")"
		fi
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
