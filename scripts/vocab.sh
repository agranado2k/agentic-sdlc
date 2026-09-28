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
# declared field is not a decision line and is ignored — so a whole ticket
# body may be piped in. The VALUE is matched exactly.
#
# STREAMS AND EXIT CODES. stdout carries the answer and nothing else: `check`
# prints nothing, `fields` prints one field per line. Every reason is on
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
# a working state, a named and missing one is exit 2.
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
# that edits it is held to its own.
VOCAB_FIELDS='tier label domain severity status action outcome confidence command-shaped'
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
VOCAB_RULES='command-shaped=yes => action!=apply'

usage() {
	cat >&2 <<'USAGE'
usage: sh scripts/vocab.sh [check] [<line> …]   lines as arguments, or on stdin
       sh scripts/vocab.sh fields               print the effective vocabularies
  a line is `<Field>: <value>`; a field is one the policy file declares
USAGE
	exit 2
}

die() {
	echo "x vocab: $*" >&2
	exit 2
}

# ---------------------------------------------------------------------------
# Policy.

vocab_git() {
	(unset GIT_DIR GIT_WORK_TREE && git -C "$_vocab_here" "$@") 2>/dev/null
}

vocab_load_config() {
	if [ -n "${VOCAB_CONFIG:-}" ]; then
		[ -f "$VOCAB_CONFIG" ] || die "VOCAB_CONFIG=$VOCAB_CONFIG does not exist."
		. "$VOCAB_CONFIG"
		return 0
	fi
	_vl_root=$(vocab_git rev-parse --show-toplevel) || _vl_root=
	if [ -n "$_vl_root" ] && [ -f "$_vl_root/scripts/vocab.config.sh" ]; then
		. "$_vl_root/scripts/vocab.config.sh"
	elif [ -f "$_vocab_here/vocab.config.sh" ]; then
		. "$_vocab_here/vocab.config.sh"
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
# resolver documents (SH_WORD_SPLIT).
vocab_is_field() {
	case " $VOCAB_FIELDS " in
	*" $1 "*) return 0 ;;
	esac
	return 1
}

vocab_is_open() {
	case " ${VOCAB_OPEN:-} " in
	*" $1 "*) return 0 ;;
	esac
	return 1
}

# vocab_has_token <field> <value> — membership in the field's vocabulary.
vocab_has_token() {
	case " $(vocab_tokens "$1") " in
	*" $2 "*) return 0 ;;
	esac
	return 1
}

# vocab_shape_ok <token> — the task-domain shape, alphabet spelled out.
vocab_shape_ok() {
	case $1 in
	'' | [!abcdefghijklmnopqrstuvwxyz]* | *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;;
	esac
	return 0
}

# ---------------------------------------------------------------------------
# Checking.

_vocab_bad=0
vocab_refuse() {
	_vocab_bad=1
	echo "x vocab: $*" >&2
}

# vocab_check_value <field> <value> — one field-value pair against its
# vocabulary. The field is a declared one by the time this runs.
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

# vocab_field_key <raw key> — a line's key folded to a field name: case
# dropped, spaces and underscores read as hyphens, surrounding blanks trimmed.
vocab_field_key() {
	printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
		-e 's/[[:space:]_][[:space:]_]*/-/g' | tr 'A-Z' 'a-z'
}

vocab_trim() {
	printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# vocab_check_line <line> — a decision line, or not one. A line with no colon,
# or whose key is not a declared field, is ignored: the caller may hand over a
# whole body, and the body's prose is not a judgment.
vocab_check_line() {
	case $1 in
	*:*) ;;
	*) return 0 ;;
	esac
	_cl_key=$(vocab_field_key "${1%%:*}")
	vocab_shape_ok "$_cl_key" || return 0
	vocab_is_field "$_cl_key" || return 0
	_cl_value=$(vocab_trim "${1#*:}")
	vocab_check_value "$_cl_key" "$_cl_value"
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
	[ "$_vocab_bad" = 0 ] || exit 2
	exit 0
}

vocab_fields() {
	for _vf_field in $VOCAB_FIELDS; do
		if vocab_is_open "$_vf_field"; then
			printf '%s (open): %s\n' "$_vf_field" "$(vocab_tokens "$_vf_field")"
		else
			printf '%s: %s\n' "$_vf_field" "$(vocab_tokens "$_vf_field")"
		fi
	done
	exit 0
}

# ---------------------------------------------------------------------------
# Dispatch.

vocab_load_config

case "${1:-check}" in
check)
	[ $# -gt 0 ] && shift
	vocab_check "$@"
	;;
fields)
	[ $# -eq 1 ] || usage
	vocab_fields
	;;
-h | --help | -*) usage ;;
*)
	# A bare line as the first argument — `sh scripts/vocab.sh 'Tier: x'` —
	# is the check, exactly as the usage line says.
	vocab_check "$@"
	;;
esac
