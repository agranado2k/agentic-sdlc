#!/bin/sh
# skill-dispatch.kit.sh — run a SKILL on the model its phase deserves.
# Kit-authoring only, never shipped (bootstrap.sh's KIT_ONLY deletes it).
#
#   sh scripts/skill-dispatch.kit.sh <skill> --prompt <text>      [--dry-run]
#   sh scripts/skill-dispatch.kit.sh <skill> --prompt-file <path> [--dry-run]
#   sh scripts/skill-dispatch.kit.sh <skill> --tier <tier> [--domain <token>] ...
#   sh scripts/skill-dispatch.kit.sh <skill> --ticket <N> ...   (the Trace-Spawn line's ticket)
#   sh scripts/skill-dispatch.kit.sh review-pr --set BRANCH=<b> --set BASE=<b> \
#                                     (--prompt <spec> | --set-file SPEC=<path>) [--dry-run]
#   sh scripts/skill-dispatch.kit.sh --tier-of <skill>
#   sh scripts/skill-dispatch.kit.sh --phase-tier <phase>
#
# WHY THIS EXISTS. A ticket's `Tier:` says how much judgement THAT TICKET is
# worth. It says nothing about the skill doing the work, so a session running
# `/review-pr` and one running `/to-tickets` resolved the same model even
# though the two are opposite kinds of work — one reads a finished diff
# adversarially, the other decides a whole wave's shape. The missing fact is
# the PHASE of work a skill is, and it belongs to the skill: a claim about
# the work, not about a vendor's roster. So each SKILL.md declares it in the
# `metadata` block the Agent Skills specification already defines, it ships
# with the skill, and every project maps it onto their own models.
#
# THE ONE THING THIS ADDS over scripts/agent-dispatch.sh: that script takes a
# tier and a prompt. This one takes a SKILL NAME, reads the phase the skill
# declares, maps it to the tier (and, for `tester`, the domain), and hands the
# rest over. Nothing here resolves a model itself — scripts/agents.lib.sh is
# still the only thing that does, reached through scripts/agents.kit.sh's
# policy choice.
#
# WHOSE SIZING WINS (#229). Two sizings exist and they answer different
# questions. A skill's PHASE says what kind of work that skill is, and it is
# all there is when nobody wrote a ticket — an operator running /review-pr by
# hand. A ticket's `Tier:` is decided when the ticket is written, by the only
# actor with a view of the whole wave, and the root manual is explicit that
# the call is not the spawning agent's to make. So the phase is the DEFAULT
# and `--tier` (with optional `--domain`) OVERRIDES it. A dispatcher that
# ignored the stamp would quietly replace a decomposer's decision with a skill
# author's, which is the same failure in the opposite direction from an agent
# sizing itself. `--dry-run` names which of the two answered. With no
# `--tier`, a `--ticket-file`'s own stamp is that override (#672), read
# through scripts/stamp.sh; a file with none leaves the phase answering.
#
# WHY `tester` IS NOT A TIER. The four tier names are a CLOSED vocabulary (an
# unknown one is exit 2, and widening it is a resolver change, a manual change
# and a release). Writing the failing test is implementer work by tier — one
# behaviour, test-first, through a seam — whose MEDIUM is different, which is
# exactly what the open domain axis is for. So the phase `tester` maps to the
# tier `implementer` with the domain `tests`, and the policy files map that
# pair to whichever model should be reading specifications that day.
#
# WHY /review-pr IS SENT A CONTRACT, NOT "Run /review-pr." (#266, PRD #261).
# A dispatched worker runs under its agent harness's default sandbox: a
# read-only tree and no network — and it must, because with network it would
# hold a writable tree, the operator's forge token and an untrusted diff at
# once. `/review-pr` needs a `git fetch`, a forge call and a human at its last
# prompt, so a worker told to run it came back every time with the same "no
# network" line and the session relayed the findings by hand. So for that one
# skill this script stages .agents/prompts/review-worker.md — the same two
# axes, returned on stdout, opening by telling the worker it is offline — and
# the caller's --prompt fills the contract's %%SPEC%% slot; %%BRANCH%% and
# %%BASE%% travel as the dispatcher's own `--set`. A --prompt-file is still the
# caller's own document and is never swapped. Every other skill keeps the
# prefix: their dispatched session has the same tree and the same rules, and
# "run this skill" is the right instruction for it.
#
# KIT-ONLY FOR NOW. scripts/agent-dispatch.sh below it is shared layer, and
# adding a second shared script is a release action (root AGENTS.md hard rule
# 3). A later release carries the promotion — #226 — and until then the
# phases ship with every skill while this runner does not.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

die() { echo "skill-dispatch: $1" >&2; exit 2; }

# tier_names — the closed tier vocabulary, read from the resolver that owns it
# rather than spelled here (#681). is_tier <word> — is it one of them? A
# shaped word holds no space, so contiguous text inside the padded list
# (`planner implementer`) never passes as a member.
# Read once, here: a resolver that cannot be sourced stops the dispatcher
# loudly rather than leaving it an empty vocabulary.
TIER_NAMES=$(. "$ROOT/scripts/agents.lib.sh" 2>/dev/null && agents_tier_names) && [ -n "$TIER_NAMES" ] ||
	die "cannot read the tier names from $ROOT/scripts/agents.lib.sh"
tier_names() { printf '%s' "$TIER_NAMES"; }
is_tier() {
	case $1 in '' | *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;; esac
	case " $(tier_names) " in *" $1 "*) return 0 ;; esac
	return 1
}
# phase_names — the phases: the tiers, with `tester` after implementer.
phase_names() { tier_names | sed 's/implementer/& tester/'; }

# The policy this session resolves through is scripts/agents.kit.sh's choice,
# asked for by name rather than recomputed: one definition of "which agent
# harness am I", in the script whose job that already is.
# $ROOT-anchored: --policy answers with a repo-relative path, and this script
# is runnable from any directory, so exporting it as-is would resolve against
# the caller's cwd and die "does not exist" one hop later.
AGENTS_CONFIG="$ROOT/$(cd "$ROOT" && sh scripts/agents.kit.sh --policy)"
export AGENTS_CONFIG

# The dispatcher records every spawn through scripts/trace.sh, which reads the
# SHIPPED trace policy file unless told otherwise — empty by principle, so the
# kit's own dispatches would be traced nowhere. Name the kit's twin, the choice
# scripts/trace.kit.sh makes for a session, $ROOT-anchored for the reason above.
TRACE_CONFIG="$ROOT/scripts/trace.kit.config.sh"
export TRACE_CONFIG

usage() {
	echo "usage: sh scripts/skill-dispatch.kit.sh <skill> [--tier <tier> [--domain <token>]] [--ticket <N>] --prompt <text> [--dry-run]" >&2
	echo "       sh scripts/skill-dispatch.kit.sh review-pr --set BRANCH=<b> --set BASE=<b> (--prompt <spec> | --set-file SPEC=<path>) [--dry-run]" >&2
	echo "       sh scripts/skill-dispatch.kit.sh --tier-of <skill>" >&2
	echo "       sh scripts/skill-dispatch.kit.sh --phase-tier <phase>" >&2
	echo "  phases: $(phase_names)" >&2
	exit 2
}

# phase_tier <phase> — the resolver arguments a phase means, on one line.
# `tester` is the only one that carries a domain; see the header.
phase_tier() {
	if is_tier "$1"; then
		printf '%s\n' "$1"
	elif [ "$1" = tester ]; then
		printf 'implementer tests\n'
	else
		die "unknown phase '$1'. The vocabulary is closed: $(phase_names)."
	fi
}

# skill_phase <skill> — the metadata.phase a skill declares. The leading
# slash is optional, so a command as typed in the manual works verbatim.
skill_phase() {
	_sp_name=${1#/}
	_sp_file="$ROOT/.agents/skills/$_sp_name/SKILL.md"
	[ -f "$_sp_file" ] || die "no skill '$_sp_name' — .agents/skills/$_sp_name/SKILL.md does not exist"
	_sp_phase=$(awk '
		NR == 1 && /^---/ { fm = 1; next }
		fm && /^---/ { exit }
		fm && /^metadata:/ { in_meta = 1; next }
		in_meta && /^[A-Za-z]/ { in_meta = 0 }
		in_meta && /^[ \t]+phase:/ { sub(/^[ \t]+phase:[ \t]*/, ""); print; exit }
	' "$_sp_file")
	[ -n "$_sp_phase" ] || die "skill '$_sp_name' declares no metadata.phase"
	printf '%s\n' "$_sp_phase"
}

[ $# -gt 0 ] || usage

case "$1" in
--phase-tier)
	[ $# -eq 2 ] || usage
	phase_tier "$2"
	exit 0
	;;
--tier-of)
	[ $# -eq 2 ] || usage
	phase_tier "$(skill_phase "$2")"
	exit 0
	;;
-h | --help) usage ;;
-*) die "unknown option '$1'" ;;
esac

# The call as typed, shell-quoted, without the flags that only steer one call:
# a hand-back stages it, so a refused --deliver can name the --rung-done call
# in full (#777).
_q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
DISPATCH_CALL="sh $(_q "$0")"
for a in "$@"; do
	case "$a" in --rung-done | --deliver | --restart | --dry-run) continue ;; esac
	DISPATCH_CALL="$DISPATCH_CALL $(_q "$a")"
done

SKILL=$1
shift
[ $# -gt 0 ] || usage

# The ticket's stamp, if the caller carried one. Pulled out of the argument
# list before anything else sees it: agent-dispatch takes a bare tier and an
# optional domain positionally, so these two are this wrapper's own vocabulary
# and must not reach it as flags.
OVERRIDE_TIER=''
OVERRIDE_DOMAIN=''
TICKET=''
CASCADE_TICKET=''
CASCADE_WT=''
CASCADE_BASE=''
RUNG_DONE=0
DELIVER=0
RESTART=0
PROMPT_RAW=''
PROMPT_FILE_RAW=''
_count=$#
while [ "$_count" -gt 0 ]; do
	a=$1
	shift
	_count=$((_count - 1))
	case "$a" in
	--tier)
		[ "$_count" -gt 0 ] || die "--tier needs one of: $(tier_names)"
		OVERRIDE_TIER=$1
		shift
		_count=$((_count - 1))
		;;
	--domain)
		[ "$_count" -gt 0 ] || die "--domain needs a token"
		OVERRIDE_DOMAIN=$1
		shift
		_count=$((_count - 1))
		;;
	--ticket)
		[ "$_count" -gt 0 ] || die "--ticket needs the number of the ticket the dispatch serves"
		TICKET=${1#\#}
		shift
		_count=$((_count - 1))
		case "$TICKET" in
		[1-9] | [1-9][0-9] | [1-9][0-9][0-9] | [1-9][0-9][0-9][0-9] | [1-9][0-9][0-9][0-9][0-9] | [1-9][0-9][0-9][0-9][0-9][0-9]) ;;
		*) die "--ticket takes a ticket number, '#' optional, no leading zero, six digits at most" ;;
		esac
		;;
	--rung-done) RUNG_DONE=1 ;;
	--deliver) DELIVER=1 ;;
	--restart) RESTART=1 ;;
	--ticket-file | --worktree | --base)
		[ "$_count" -gt 0 ] || die "$a needs a value"
		case "$a" in
		--ticket-file) CASCADE_TICKET=$1 ;;
		--worktree) CASCADE_WT=$1 ;;
		--base) CASCADE_BASE=$1 ;;
		esac
		shift
		_count=$((_count - 1))
		;;
	--prompt | --prompt-file)
		# Kept as typed, for an in-session rung's prompt (#682): the
		# rewrite below prefixes the dispatcher's own lines to it.
		[ "$_count" -gt 0 ] && case "$a" in
		--prompt) PROMPT_RAW=$1 ;;
		*) PROMPT_FILE_RAW=$1 ;;
		esac
		set -- "$@" "$a"
		;;
	*) set -- "$@" "$a" ;;
	esac
done

# _fs_read_stamp — the --ticket-file's stamp, as TIER_ARGS, when no --tier was
# given (#672). Without it, `implement --ticket-file <f>` was sized by the
# skill's phase whatever the file said, and a mechanical ticket never reached
# the cascade unless its caller repeated the tier by hand.
#
# The file is ticket text, untrusted, so it is read THROUGH scripts/stamp.sh —
# its lift, its bound and its checker, never a second reading of the body
# here. stamp.sh fetches by issue number and is shared layer (a file form of
# its own would be a release action), so a stand-in `gh` on its PATH hands it
# the file as the tracker's answer. Its exits keep their meaning: 0 the
# checked lines, of which only the Tier: and Domain: values are taken; 3 no
# stamp, and the skill's phase answers, said; anything else is a stop, exit
# 2, the refused text never printed. Sets _fs_tier and _fs_domain, or _fs_none
# on exit 3 or on a stamp naming no tier.
_fs_read_stamp() {
	_fs_tier='' _fs_domain='' _fs_none=''
	[ -f "$CASCADE_TICKET" ] || die "--ticket-file '$CASCADE_TICKET' is not a file"
	if [ ! -f "$ROOT/scripts/stamp.sh" ]; then
		_fs_none=1
		return 0
	fi
	_fs_tmp=$(mktemp -d "${TMPDIR:-/tmp}/skill-dispatch-stamp.XXXXXX") || die "no scratch to read the ticket file's stamp"
	printf '#!/bin/sh\nexec cat "$SKILL_DISPATCH_TICKET_FILE"\n' >"$_fs_tmp/gh"
	chmod +x "$_fs_tmp/gh"
	_fs_rc=0
	_fs_lines=$(PATH="$_fs_tmp:$PATH" SKILL_DISPATCH_TICKET_FILE=$CASCADE_TICKET \
		sh "$ROOT/scripts/stamp.sh" "${TICKET:-0}" 2>"$_fs_tmp/err") || _fs_rc=$?
	_fs_err=$(cat "$_fs_tmp/err")
	rm -rf "$_fs_tmp"
	case "$_fs_rc" in
	0) ;;
	3)
		_fs_none=1
		return 0
		;;
	*) die "the ticket file's stamp was not read (stamp.sh exit $_fs_rc): ${_fs_err:-no reason given}" ;;
	esac
	# The checked lines only: a value the checker passed, one word each.
	_fs_tier=$(printf '%s\n' "$_fs_lines" | sed -n 's/^[[:space:]]*[Tt][Ii][Ee][Rr][[:space:]]*:[[:space:]]*\([a-z]*\)[[:space:]]*$/\1/p' | head -n 1)
	_fs_domain=$(printf '%s\n' "$_fs_lines" | sed -n 's/^[[:space:]]*[Dd][Oo][Mm][Aa][Ii][Nn][[:space:]]*:[[:space:]]*\([a-z-]*\)[[:space:]]*$/\1/p' | head -n 1)
	is_tier "$_fs_tier" || { _fs_tier='' _fs_none=1; }
}

# _cascade_oracle_line <ticket file> — the line that opens the ticket's
# Acceptance section, when it is an oracle line; nothing otherwise. An oracle
# line anywhere else in the body is prose, as /implement step 1 reads it. The
# section opens with a heading (`## Acceptance`, any level) or a bold lead at
# the start of a line (`**Acceptance.**` or `**Acceptance**`); text after the
# lead on its own line is the section's first line, and with none the first
# non-blank line below it is (#759). A bold lead with text after it that is
# not an oracle line is prose and opens nothing: a heading below still can.
_cascade_oracle_line() {
	[ -f "$1" ] || return 0
	awk '
		/^#+[ \t]*Acceptance[ \t]*$/ { in_acc = 1; next }
		!in_acc && /^\*\*Acceptance\.?\*\*/ {
			rest = $0
			sub(/^\*\*Acceptance\.?\*\*[ \t]*/, "", rest)
			if (rest == "") { in_acc = 1; next }
			if (index(rest, "the oracle: `")) { print rest; exit }
			next
		}
		in_acc && /^[ \t]*$/ { next }
		in_acc { if (index($0, "the oracle: `")) print; exit }
	' "$1"
}

# _cascade_oracle <ticket file> <worktree> — the closed-list command the
# ticket's oracle line selects, or nothing. Typed from this list, never from
# the ticket.
_cascade_oracle() {
	_co_text=$(_cascade_oracle_line "$1" | sed -n 's/^.*the oracle: `\([^`]*\)`.*$/\1/p')
	case "$_co_text" in
	'sh scripts/check.sh' | 'scripts/check.sh') printf '%s\n' 'sh scripts/check.sh' ;;
	"sh -c 'for t in tests/*.sh; do sh \"\$t\" || exit 1; done'")
		printf '%s\n' "$_co_text"
		;;
	'sh tests/'*.sh)
		_co_name=${_co_text#sh tests/}
		_co_name=${_co_name%.sh}
		case "$_co_name" in
		'' | *[!A-Za-z0-9._-]*) return 0 ;;
		esac
		[ -f "$2/tests/$_co_name.sh" ] && printf 'sh tests/%s.sh\n' "$_co_name"
		;;
	esac
	return 0
}

if [ -n "$OVERRIDE_TIER" ]; then
	is_tier "$OVERRIDE_TIER" ||
		die "unknown tier '$OVERRIDE_TIER'. The vocabulary is closed: $(tier_names)."
	TIER_ARGS="$OVERRIDE_TIER${OVERRIDE_DOMAIN:+ $OVERRIDE_DOMAIN}"
	TIER_SOURCE="the ticket's stamp"
else
	[ -z "$OVERRIDE_DOMAIN" ] || die "--domain without --tier: a domain is the second half of a ticket's stamp, not a sizing of its own"
	TIER_ARGS=''
	_fs_none='' _fs_tier=''
	[ -z "$CASCADE_TICKET" ] || _fs_read_stamp
	[ -z "$_fs_tier" ] || TIER_ARGS="$_fs_tier${_fs_domain:+ $_fs_domain}"
	if [ -n "$TIER_ARGS" ]; then
		TIER_SOURCE="the ticket file's stamp"
	else
		TIER_ARGS=$(phase_tier "$(skill_phase "$SKILL")")
		TIER_SOURCE="$SKILL's own phase${_fs_none:+ (the ticket file carries no stamp)}"
	fi
fi
# --- the review of a cascade-built diff (#778, ADR-0030) --------------------
# WHY. ADR-0027 gives a diff the Sonnet family wrote an Opus reviewer only when
# the session names the rung's model as the author, and nothing checked it:
# the rung's commits carry a co-author trailer naming the SESSION's family, so
# a session that trusts git gets a same-family review. So a passed verdict
# records its rung's model as the author (_cascade_verdict, below), in the
# trace and in the worktree's git dir, and here the review dispatch reads it
# back: for a review-pr dispatch, the recorded author is AGENT_SESSION_MODEL,
# whatever the session named. A cascade-built ticket — a --ticket-file stamped
# mechanical, whose oracle line selects a closed-list command, under a policy
# that declares a cascade, AND for which a cascade actually ran: its hand-back
# state or a recorded verdict is in the worktree's git dir — with no author
# recorded for it is refused, exit 2: the session's own model is the wrong
# answer, so no default stands in for it. The stamp alone proves nothing
# (#881): a mechanical ticket a session built itself leaves no cascade record,
# and is reviewed like any self-implemented diff, from the author it names.
# The record is the worktree's: --worktree, or the checkout this runs in.
CASCADE_AUTHOR_NAME=skill-cascade-author
if [ "${SKILL#/}" = review-pr ]; then
	_ra_wt=${CASCADE_WT:-.}
	_ra_author='' _ra_file='' _ra_ran=0
	_ra_gd=$(cd "$_ra_wt" 2>/dev/null && git rev-parse --absolute-git-dir 2>/dev/null) &&
		_ra_file="$_ra_gd/$CASCADE_AUTHOR_NAME"
	# A cascade ran here when its hand-back state or its recorded author is
	# left in the git dir — the state's name is the one _cascade stages.
	[ -n "$_ra_file" ] && { [ -e "$_ra_gd/skill-cascade" ] || [ -f "$_ra_file" ]; } && _ra_ran=1
	if [ -n "$_ra_file" ] && [ -f "$_ra_file" ]; then
		_ra_model=$(sed -n 's/^model=//p' "$_ra_file" | head -n 1)
		_ra_ticket=$(sed -n 's/^ticket=//p' "$_ra_file" | head -n 1)
		# A record answers the dispatch's own ticket, or a ticketless
		# dispatch only when the cascade itself ran with no ticket: another
		# ticket's record left in this worktree is no author for this review.
		[ "$_ra_ticket" = "${TICKET:+#}${TICKET:-none}" ] && _ra_author=$_ra_model
	fi
	_ra_built=0
	if [ "$_ra_ran" = 1 ] && [ -n "$CASCADE_TICKET" ]; then
		_fs_read_stamp
		if [ "$_fs_tier" = mechanical ] &&
			[ -n "$(sh -c '. "$1" >/dev/null 2>&1; printf "%s" "${AGENT_CASCADE_MECHANICAL:-}"' _ "$AGENTS_CONFIG")" ] &&
			[ -n "$(_cascade_oracle "$CASCADE_TICKET" "$_ra_wt")" ]; then
			_ra_built=1
		fi
	fi
	if [ -n "$_ra_author" ]; then
		AGENT_SESSION_MODEL=$_ra_author
		export AGENT_SESSION_MODEL
		echo "skill-dispatch: the diff's author is '$_ra_author', the model its cascade's passed verdict recorded; the reviewer is resolved against that author, not the session" >&2
	elif [ "$_ra_built" = 1 ]; then
		die "review refused — ticket ${TICKET:+#$TICKET }is cascade-built and '$_ra_wt' holds no rung author recorded for it; the reviewer is resolved from the author, never the session's own model. Judge the rung first — the cascade's own call with --rung-done records its verdict and its author — then dispatch the review again"
	fi
fi

for a in "$@"; do
	[ "$a" = --dry-run ] || continue
	echo "skill-dispatch: tier '$TIER_ARGS' — from $TIER_SOURCE" >&2
	# The spawn's agent type and model (#588, spend/R6–R7): under the Claude
	# Code adapter a spawn takes its tier's agent type and the resolver's
	# model for the tier and domain; no model means the spawn inherits. A
	# resolver that refuses is not an unmapped tier: its own stderr says why.
	# shellcheck disable=SC2086  # TIER_ARGS is one or two words, by construction
	_dr_model=$(AGENTS_TIER_QUIET=1 sh "$ROOT/scripts/agents.lib.sh" --model $TIER_ARGS) ||
		die "the tier resolver refused '$TIER_ARGS' — no agent type or model to name"
	if [ -n "$_dr_model" ]; then
		echo "skill-dispatch: agent type '${TIER_ARGS%% *}', model '$_dr_model'" >&2
	else
		echo "skill-dispatch: agent type '${TIER_ARGS%% *}', no model — the spawn inherits the session's" >&2
	fi
	break
done

# What the spawn served, on the prompt's first two lines (#587, spend/R1):
# `Trace-Run: <run> [<parent>]`, then `Trace-Spawn: tier=<tier>
# domain=<domain|none> skill=<skill> ticket=<#N|none>` — exactly the channel
# the adapter's subagent-stop hook reads (ADR-0008 clause 5, #583 amendment).
# The run is the one this dispatch runs under, asked of the trace with
# `current` — the run and parent an emit from here would stamp (#746). An
# unconfigured trace answers no identity, so there the environment's is used,
# as it is with no trace script. Each id is held to the shape with the trace's
# own `id --check`; with no trace script nothing can be checked and nothing is
# written. No run, no lines: a Trace-Spawn line with no Trace-Run line above
# it is no line to the hook.
TRACE_SH="$ROOT/scripts/trace.sh"
SPAWN_LINES=''
_sl_run=${TRACE_RUN:-} _sl_parent=${TRACE_PARENT:-}
if [ -f "$TRACE_SH" ] && [ -n "$(TRACE_QUIET=1 sh "$TRACE_SH" dir 2>/dev/null)" ]; then
	_sl_cur=$(TRACE_QUIET=1 sh "$TRACE_SH" current 2>/dev/null) || _sl_cur=''
	_sl_run=${_sl_cur%% *} _sl_parent=''
	case $_sl_cur in *' '*) _sl_parent=${_sl_cur#* } ;; esac
fi
_sl_id_ok() { [ -n "$1" ] && [ -f "$TRACE_SH" ] && sh "$TRACE_SH" id --check "$1" 2>/dev/null; }
if [ -n "$_sl_run" ] && _sl_id_ok "$_sl_run"; then
	_sl_id_ok "$_sl_parent" || _sl_parent=''
	_sl_tier=${TIER_ARGS%% *} _sl_domain=none
	case "$TIER_ARGS" in *' '*) _sl_domain=${TIER_ARGS#* } ;; esac
	_sl_ticket=none
	[ -z "$TICKET" ] || _sl_ticket="#$TICKET"
	SPAWN_LINES="Trace-Run: $_sl_run${_sl_parent:+ $_sl_parent}
Trace-Spawn: tier=$_sl_tier domain=$_sl_domain skill=${SKILL#/} ticket=$_sl_ticket
"
fi
# --- the cascade: cheap first, where an oracle decides (#586, PRD #580) ------
# WHY. The mechanical tier once ran on the cheapest model outright and failed
# three tickets of three in a day (retro 20261001T150216Z): each worker said
# it was done, and nothing checked but a rescue session. The cascade keeps the
# cheap model and moves the judgement off it. Where the policy declares
# AGENT_CASCADE_MECHANICAL, a mechanical ticket runs on that model first; the
# ticket's own oracle and the pairing guard then run in the ticket's worktree,
# and only their two exit codes decide (spend/R19) — the worker's report is
# never read, and on escalation it is never even printed. A red rung is
# discarded by resetting the worktree to the ticket's base, never the root
# checkout, and the ticket runs again on the tier's mapped model.
#
# THE INPUTS, the dispatcher's own flags, never forwarded:
#   --ticket-file <path>   the ticket body, read for its oracle line only
#   --worktree <dir>       the ticket's linked worktree, where rungs run
#   --base <ref>           the ticket's base, what a red rung is reset to
#
# THE ORACLE LINE is ticket text, untrusted: it SELECTS a command from the
# closed list /implement step 1 names — the docs gate, one suite under tests/
# that exists in the worktree, or the full-suite loop — and never supplies one.
# A ticket with no line, or a line that matches none, is refused the cascade
# and runs on the mapped model, said on stderr (spend/R20).
#
# THE TRACE. One run for the cascade; each rung a `spawn` under it carrying
# data.rung, data.oracle_exit and data.guard_exit, outcome `passed`,
# `escalated`, or — the mapped rung red, nothing left to escalate to — `failed`
# (spend/R21). A rung's own crossing is still agent-dispatch.sh's
# `dispatched` spawn and its spawn.end, filed under the same run; the rung
# record is the verdict, not a second crossing. A rung whose model names no
# agent harness (agent-dispatch exit 3) is handed back in-session and recorded
# `in-session`, its verdict recorded when the caller's --rung-done judges it
# (#682, below). A rung whose agent harness is unreachable (exit 69) is
# recorded `refused` on the cheap rung, which falls through to the plain path,
# and `in-session` on the mapped one, handed to the caller unjudged.
#
#   --rung-done            judge the rung this worktree handed back, go on
#   --deliver              run nothing: 0 when no rung handed back here awaits
#                          its verdict, else 2 naming the --rung-done call (#777)
#   --restart              start over from rung 1 though a rung handed back
#                          here awaits its verdict, ending that rung's run
#                          stopped; without it, that plain call is exit 2 (#787)
#
# EXIT. 0 a rung passed; 1 the mapped rung was red; 3 a rung handed back for
# the caller to spawn; any other dispatch status that is not a worker's (2, 4,
# 69) passes through untouched.

CASCADE=0
CASCADE_MODEL=''
CASCADE_ORACLE=''
_cascade_tier=${TIER_ARGS%% *}
_cascade_domain=''
case "$TIER_ARGS" in *' '*) _cascade_domain=${TIER_ARGS#* } ;; esac

if [ "$_cascade_tier" = mechanical ]; then
	CASCADE_MODEL=$(sh -c '. "$1" >/dev/null 2>&1; printf "%s" "${AGENT_CASCADE_MECHANICAL:-}"' _ "$AGENTS_CONFIG")
fi
if [ -n "$CASCADE_MODEL" ]; then
	CASCADE_ORACLE=$(_cascade_oracle "$CASCADE_TICKET" "${CASCADE_WT:-.}")
	if [ -z "$(_cascade_oracle_line "$CASCADE_TICKET")" ]; then
		echo "skill-dispatch: cascade refused — the ticket names no oracle command (its Acceptance section opens with none); running on the mechanical tier's mapped model" >&2
	elif [ -z "$CASCADE_ORACLE" ]; then
		echo "skill-dispatch: cascade refused — the ticket's oracle line names no command on the closed list (the docs gate, one suite under tests/, the full suite); it is not run, and the ticket runs on the mechanical tier's mapped model" >&2
	else
		[ -n "$CASCADE_WT" ] && [ -n "$CASCADE_BASE" ] ||
			die "a cascade needs --worktree <the ticket's worktree> and --base <its base>: a red rung is reset to the base, in that worktree"
		[ -d "$CASCADE_WT" ] || die "--worktree '$CASCADE_WT' is not a directory"
		_gd=$(cd "$CASCADE_WT" && git rev-parse --absolute-git-dir 2>/dev/null) || die "--worktree '$CASCADE_WT' is not a git working tree"
		_gc=$(cd "$CASCADE_WT" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
		[ "$(cd "$_gd" && pwd -P)" != "$_gc" ] ||
			die "--worktree '$CASCADE_WT' is a main working tree; a cascade resets only a linked worktree, never a root checkout"
		CASCADE_BASE=$(cd "$CASCADE_WT" && git rev-parse --verify -q "$CASCADE_BASE^{commit}") ||
			die "--base names no commit in '$CASCADE_WT'"
		if [ -f "$CASCADE_WT/scripts/guards.kit.sh" ]; then
			CASCADE_GUARD='scripts/guards.kit.sh'
		elif [ -f "$CASCADE_WT/scripts/tdd-pairing-guard.sh" ]; then
			CASCADE_GUARD='scripts/tdd-pairing-guard.sh'
		else
			CASCADE_GUARD=''
		fi
		if [ -z "$CASCADE_GUARD" ]; then
			echo "skill-dispatch: cascade refused — the worktree carries no pairing guard to judge a rung by; running on the mechanical tier's mapped model" >&2
		else
			CASCADE=1
		fi
	fi
fi
[ "$RUNG_DONE" = 0 ] || [ "$CASCADE" = 1 ] ||
	die "--rung-done judges a rung a cascade handed back in-session, and this dispatch runs no cascade"
[ "$DELIVER" = 0 ] || [ "$CASCADE" = 1 ] ||
	die "--deliver asks a cascade whether a rung it handed back awaits its verdict, and this dispatch runs no cascade"
[ "$DELIVER" = 0 ] || [ "$RUNG_DONE" = 0 ] ||
	die "--deliver and --rung-done are two calls: --rung-done records the rung's verdict, then --deliver asks whether the PR may open"
[ "$RESTART" = 0 ] || [ "$CASCADE" = 1 ] ||
	die "--restart starts a cascade over, and this dispatch runs no cascade"
[ "$RESTART" = 0 ] || { [ "$RUNG_DONE" = 0 ] && [ "$DELIVER" = 0 ]; } ||
	die "--restart starts the cascade over; it is never the same call as --rung-done or --deliver"

# The worktree's hand-back state, and — while a rung handed back there awaits
# its verdict — the --rung-done call that records it: the call the hand-back
# saved, or this one when the state predates the saved call.
CASCADE_STATE=''
[ "$CASCADE" = 1 ] && CASCADE_STATE="$(cd "$CASCADE_WT" && git rev-parse --absolute-git-dir)/skill-cascade"
_staged_call() {
	_sc_call=$(cat "$CASCADE_STATE/call" 2>/dev/null) || _sc_call=''
	printf '%s --rung-done' "${_sc_call:-$DISPATCH_CALL}"
}

# --- the open-PR step (#777) -------------------------------------------------
# WHY. PR #762 was opened by hand after the cascade's cheap rung, which was
# never judged through --rung-done: its verdict was never recorded and its
# spawn never ended. A session resuming after a usage-limit stop is where that
# happens — it finds commits in the worktree and takes them for a passed rung.
# So the open-PR step is the dispatcher's to hand out: the same command with
# --deliver runs nothing and exits 0 only when no rung it handed back in the
# worktree awaits a verdict. A staged hand-back is exactly that — the state
# under <git dir>/skill-cascade is written at the hand-back and removed once a
# verdict is recorded — so while it stands, --deliver is exit 2, naming the
# --rung-done call that records the verdict.
if [ "$DELIVER" = 1 ]; then
	[ ! -f "$CASCADE_STATE/rung" ] ||
		die "--deliver refused — rung $(cat "$CASCADE_STATE/rung") was handed back in '$CASCADE_WT' and has no recorded verdict; the pull request does not open until it has one. Record it first: $(_staged_call)"
	echo "skill-dispatch: no rung handed back in '$CASCADE_WT' awaits a verdict; deliver: push and open the pull request" >&2
	exit 0
fi
for a in "$@"; do
	[ "$a" = --dry-run ] || continue
	if [ "$CASCADE" = 1 ]; then
		echo "skill-dispatch: cascade — rung 1 on the cascade model, judged by '$CASCADE_ORACLE' and the pairing guard; a red rung resets to $CASCADE_BASE and rung 2 runs on the tier's mapped model, or the implementer tier's when that is the cascade model itself. A dry run runs neither." >&2
		CASCADE=0
	fi
	break
done

# --- a re-run while a rung awaits its verdict (#787) --------------------------
# WHY. Re-running the plain cascade command while a rung it handed back still
# awaited its verdict once wiped the hand-back, left the earlier cascade's run
# open in the open-run registry and started over — and a session resuming
# after a usage-limit stop is the one likely to re-run it. So that call
# refuses, exit 2, naming the --rung-done call --deliver names, and touches
# neither the worktree nor the run. Starting over is an explicit choice: the
# same call with --restart ends the staged rung's run, stopped, said, and runs
# the cascade from rung 1 under a new one. It never resets the worktree.
if [ "$CASCADE" = 1 ] && [ "$RUNG_DONE" = 0 ] && [ -f "$CASCADE_STATE/rung" ]; then
	[ "$RESTART" = 1 ] ||
		die "cascade refused — rung $(cat "$CASCADE_STATE/rung") was handed back in '$CASCADE_WT' and has no recorded verdict; re-running the cascade would discard it. Record its verdict: $(_staged_call) — or start over, ending its run, with the same call and --restart"
	_rs_run=$(cat "$CASCADE_STATE/run" 2>/dev/null) || _rs_run=''
	if _sl_id_ok "$_rs_run"; then
		TRACE_QUIET=1 sh "$TRACE_SH" end "$_rs_run" outcome=stopped \
			reason="the cascade was restarted with rung $(cat "$CASCADE_STATE/rung") unjudged" >/dev/null 2>&1 || :
		echo "skill-dispatch: --restart — rung $(cat "$CASCADE_STATE/rung") was handed back unjudged; its run $_rs_run is ended, stopped, and the cascade starts over from rung 1" >&2
	fi
	rm -rf "$CASCADE_STATE"
fi

# _cascade_emit <field=value …> — one event under the cascade's run, or none.
_cascade_emit() {
	[ -f "$ROOT/scripts/trace.sh" ] || return 0
	TRACE_RUN=$CASCADE_RUN TRACE_PARENT=$CASCADE_PARENT \
		sh "$ROOT/scripts/trace.sh" emit kind=spawn subject="run:$CASCADE_RUN" \
		tier=mechanical ${_cascade_domain:+domain=$_cascade_domain} skill="${SKILL#/}" "$@" >/dev/null 2>&1 || :
}

# _cascade_verdict <rung> <model> <outcome> <reason> — a judged rung's record:
# passed, escalated or failed, with the oracle's and the guard's exit codes,
# and the rung's model as data.author — the model that wrote the rung's work
# (#778). The one place a verdict is written, so a field it gains is added
# here once. A PASSED verdict also leaves the author in the worktree's git dir
# (never its working tree, which the guard judges), the record the review
# dispatch above resolves its reviewer from: the passed rung's work is the
# diff under review, and no other rung's is.
_cascade_verdict() {
	_cascade_emit model="$2" outcome="$3" data.rung="$1" data.oracle_exit="$ORACLE_EXIT" \
		data.guard_exit="$GUARD_EXIT" ${2:+data.author="$2"} reason="$4"
	[ "$3" = passed ] && [ -n "$2" ] || return 0
	printf 'model=%s\nticket=%s\n' "$2" "${TICKET:+#}${TICKET:-none}" >"$CASCADE_AUTHOR"
}

# _cascade_close <status> — end the cascade's run, once: ok on 0, stopped on
# anything else. A hand-back leaves it open for --rung-done to close.
_cascade_close() {
	[ "${CASCADE_OPEN:-0}" = 1 ] || return 0
	CASCADE_OPEN=0
	if [ "$1" = 0 ]; then _cc_outcome=ok; else _cc_outcome=stopped; fi
	TRACE_QUIET=1 sh "$TRACE_SH" end "$CASCADE_RUN" outcome="$_cc_outcome" \
		reason="the cascade exited $1" >/dev/null 2>&1 || :
}

# _cascade_rung <n> <policy file> <out file> <args…> — one rung, in the
# worktree. Sets RUNG_STATUS, and ORACLE_EXIT / GUARD_EXIT when it was judged.
_cascade_rung() {
	_cr_n=$1 _cr_cfg=$2 _cr_out=$3
	shift 3
	RUNG_STATUS=0
	ORACLE_EXIT='' GUARD_EXIT=''
	# shellcheck disable=SC2086  # TIER_ARGS is one or two words, by construction
	(cd "$CASCADE_WT" && TRACE_RUN=$CASCADE_RUN TRACE_PARENT=$CASCADE_PARENT AGENTS_CONFIG=$_cr_cfg \
		sh "$ROOT/scripts/agent-dispatch.sh" $TIER_ARGS "$@") >"$_cr_out" || RUNG_STATUS=$?
	case "$RUNG_STATUS" in 2 | 3 | 4 | 69) return 0 ;; esac
	_cascade_judge
}

# _cascade_judge — the oracle and the pairing guard on what the worktree holds.
# Sets ORACLE_EXIT and GUARD_EXIT; the rung's own report is never an input.
_cascade_judge() {
	ORACLE_EXIT=0 GUARD_EXIT=0
	(cd "$CASCADE_WT" && eval "$CASCADE_ORACLE") >&2 || ORACLE_EXIT=$?
	(cd "$CASCADE_WT" && sh "$CASCADE_GUARD" "$CASCADE_BASE" HEAD) >&2 || GUARD_EXIT=$?
	# The guard reads commits only, so work a rung left uncommitted would pass
	# it unseen: a tree the rung left dirty is a red guard, exit 3, said.
	if [ "$GUARD_EXIT" = 0 ] && [ -n "$(cd "$CASCADE_WT" && git status --porcelain --untracked-files=all)" ]; then
		echo "skill-dispatch: the rung left uncommitted work in '$CASCADE_WT'; the pairing guard cannot judge it, so the guard counts red" >&2
		GUARD_EXIT=3
	fi
	return 0
}

# _cascade_model <policy file> — the model a rung resolves to, for its record.
_cascade_model() {
	# shellcheck disable=SC2086
	AGENTS_CONFIG=$1 sh "$ROOT/scripts/agents.lib.sh" $TIER_ARGS 2>/dev/null || :
}

# --- the in-session rung (#682) ---------------------------------------------
# WHY. A rung whose model names no agent harness — the kit's own cascade
# model, a family word for the session's own vendor — is one this process
# cannot run: only the calling session can spawn it. It used to be refused,
# so the kit's cascade was declared and never ran. Now the rung is HANDED
# BACK: exit 3, the model on stdout exactly as agent-dispatch's in-session
# exit prints it, and the spawn prompt — Trace-Run and Trace-Spawn lines
# first, so the spawn guard passes it and the subagent's stop files under the
# cascade's run — written to the worktree's git dir, never its working tree
# (a file there would dirty the tree the guard judges). The session spawns the
# rung on the tier's agent type and that model, waits for it, then runs the
# SAME command again with --rung-done: the oracle and the pairing guard run on
# what the rung committed, the verdict is recorded under the same run, and
# the cascade goes on from that rung exactly as it would have here.
#
# THE STATE is four small files under <git dir>/skill-cascade: the run, its
# parent, the rung handed back and the base it was handed back against. A
# --rung-done whose base differs, or with no state at all, is exit 2. The
# state is removed when the cascade ends.

# _cascade_handback <n> <out file> <policy file> — hand rung <n> back. Exits 3.
_cascade_handback() {
	_hb_n=$1 _hb_out=$2 _hb_cfg=$3
	rm -rf "$CASCADE_STATE"
	mkdir -p "$CASCADE_STATE" || die "cannot stage the in-session rung under '$CASCADE_STATE'"
	printf '%s\n' "$CASCADE_RUN" >"$CASCADE_STATE/run"
	printf '%s\n' "$CASCADE_PARENT" >"$CASCADE_STATE/parent"
	printf '%s\n' "$_hb_n" >"$CASCADE_STATE/rung"
	printf '%s\n' "$CASCADE_BASE" >"$CASCADE_STATE/base"
	printf '%s\n' "$DISPATCH_CALL" >"$CASCADE_STATE/call"
	_hb_parent=''
	_sl_id_ok "$CASCADE_PARENT" && _hb_parent=" $CASCADE_PARENT"
	_hb_lines=0
	_sl_id_ok "$CASCADE_RUN" && _hb_lines=1
	_hb_ticket=none
	[ -z "$TICKET" ] || _hb_ticket="#$TICKET"
	{
		if [ "$_hb_lines" = 1 ]; then
			printf 'Trace-Run: %s%s\n' "$CASCADE_RUN" "$_hb_parent"
			printf 'Trace-Spawn: tier=%s domain=%s skill=%s ticket=%s\n' \
				"$_cascade_tier" "${_cascade_domain:-none}" "${SKILL#/}" "$_hb_ticket"
		fi
		printf 'You are rung %s of a cheap-first cascade. Work only in the worktree %s, and commit your work there.\n' \
			"$_hb_n" "$CASCADE_WT_ABS"
		printf 'Stop before anything leaves that worktree: no push, no pull request, no review request, and never dispatch this ticket again.\n'
		printf 'Your report is never read: the ticket'"'"'s oracle and the pairing guard judge what you committed.\n\n'
		if [ -n "$PROMPT_FILE_RAW" ]; then
			cat "$PROMPT_FILE_RAW"
		else
			printf 'Run %s. %s\n' "$SKILL" "$PROMPT_RAW"
		fi
	} >"$CASCADE_STATE/prompt"
	_hb_model=$(_cascade_model "$_hb_cfg")
	_cascade_emit model="$_hb_model" outcome=in-session data.rung="$_hb_n" \
		reason='the model names no agent harness this dispatcher runs; the calling session spawns the rung, then runs the dispatch again with --rung-done'
	echo "skill-dispatch: rung $_hb_n is yours to spawn in-session — agent type '$_cascade_tier', model '${_hb_model:-none: the spawn inherits}', its prompt verbatim from $CASCADE_STATE/prompt. When the rung returns, run this same command again with --rung-done: the oracle and the pairing guard judge what it committed in $CASCADE_WT_ABS." >&2
	cat "$_hb_out"
	# The run stays open: the session works the rung under it, and the
	# --rung-done call that judges the rung closes it.
	CASCADE_OPEN=0
	exit 3
}

# _cascade <dispatch args…> — the two rungs. Never returns.
_cascade() {
	CASCADE_AUTHOR="${CASCADE_STATE%/*}/$CASCADE_AUTHOR_NAME"
	CASCADE_WT_ABS=$(cd "$CASCADE_WT" && pwd)
	_cs_tmp=$(mktemp -d "${TMPDIR:-/tmp}/skill-cascade.XXXXXX") || die "no scratch for the cascade"
	CASCADE_RUN='' CASCADE_OPEN=0
	trap '_cs_rc=$?; rm -rf "$_cs_tmp"; _cascade_close "$_cs_rc"' EXIT
	case "$AGENTS_CONFIG" in *"'"*) die "the policy path carries a quote; the cascade cannot stage its rung policy" ;; esac
	{
		printf ". '%s'\n" "$AGENTS_CONFIG"
		printf 'AGENT_TIER_MECHANICAL=$AGENT_CASCADE_MECHANICAL\n'
		[ -n "$_cascade_domain" ] &&
			printf 'unset AGENT_TIER_MECHANICAL_%s\n' "$(printf '%s' "$_cascade_domain" | tr 'a-z-' 'A-Z_')"
	} >"$_cs_tmp/cheap.config.sh"
	_m1=$(_cascade_model "$_cs_tmp/cheap.config.sh")

	if [ "$RUNG_DONE" = 1 ]; then
		[ -f "$CASCADE_STATE/run" ] && [ -f "$CASCADE_STATE/rung" ] && [ -f "$CASCADE_STATE/base" ] ||
			die "--rung-done: no rung was handed back in '$CASCADE_WT' — run the dispatch without it first"
		[ "$(cat "$CASCADE_STATE/base")" = "$CASCADE_BASE" ] ||
			die "--rung-done: the rung was handed back against another --base; judge it with that --base, or start over with the plain call and --restart"
		CASCADE_RUN=$(cat "$CASCADE_STATE/run")
		CASCADE_PARENT=$(cat "$CASCADE_STATE/parent" 2>/dev/null || :)
		_sl_id_ok "$CASCADE_RUN" && CASCADE_OPEN=1
		_cs_done=$(cat "$CASCADE_STATE/rung")
		_cascade_judge
		case "$_cs_done" in
		1) _cascade_after1 "$@" ;;
		2)
			_cs_cfg2=$AGENTS_CONFIG
			_cascade_escalation_policy
			_cascade_after2
			;;
		*) die "--rung-done: the hand-back state names no rung this cascade has" ;;
		esac
	fi

	# The cascade's run is the trace's: `begin --detached` mints it, registers
	# it with the run this dispatch is under as its parent — the one the
	# Trace-Run line above was read from — and pushes no stack. It stays open
	# across a hand-back, and _cascade_close ends it when the cascade does
	# (#746). Called as this process's own child, never in a pipe, so the
	# registry records this dispatcher as the run's process.
	CASCADE_PARENT=$_sl_run
	if [ -f "$TRACE_SH" ] && CASCADE_RUN=$(TRACE_QUIET=1 sh "$TRACE_SH" begin --detached "${SKILL#/}" \
		${TICKET:+"subject=ticket:#$TICKET"}) && [ -n "$CASCADE_RUN" ]; then
		CASCADE_OPEN=1
	else
		CASCADE_RUN=''
	fi
	rm -rf "$CASCADE_STATE" "$CASCADE_AUTHOR"

	_cascade_rung 1 "$_cs_tmp/cheap.config.sh" "$_cs_tmp/rung1.out" "$@"
	case "$RUNG_STATUS" in
	3) _cascade_handback 1 "$_cs_tmp/rung1.out" "$_cs_tmp/cheap.config.sh" ;;
	69)
		_cascade_emit model="$_m1" outcome=refused data.rung=1 \
			reason='the cascade model names an agent harness that is not reachable from here; an oracle cannot judge work this process never ran'
		echo "skill-dispatch: cascade refused — the cascade model's agent harness is not reachable from here (exit $RUNG_STATUS); running on the mechanical tier's mapped model" >&2
		rm -rf "$_cs_tmp"
		_cascade_close 69
		# shellcheck disable=SC2086
		exec sh "$ROOT/scripts/agent-dispatch.sh" $TIER_ARGS "$@"
		;;
	2 | 4) cat "$_cs_tmp/rung1.out"; exit "$RUNG_STATUS" ;;
	esac
	_cascade_after1 "$@"
}

# _cascade_after1 <dispatch args…> — rung 1's verdict, then rung 2 on a red
# one. Never returns.
_cascade_after1() {
	if [ "$ORACLE_EXIT" = 0 ] && [ "$GUARD_EXIT" = 0 ]; then
		_cascade_verdict 1 "$_m1" passed 'the oracle and the pairing guard are green on the cascade model'
		rm -rf "$CASCADE_STATE"
		[ ! -f "$_cs_tmp/rung1.out" ] || cat "$_cs_tmp/rung1.out"
		exit 0
	fi
	_cascade_verdict 1 "$_m1" escalated 'the oracle or the pairing guard is red on the cascade model'
	echo "skill-dispatch: cascade escalated — oracle exit $ORACLE_EXIT, pairing guard exit $GUARD_EXIT on the cascade model; resetting the worktree to $CASCADE_BASE and running the mechanical tier's mapped model" >&2
	(cd "$CASCADE_WT" && git reset -q --hard "$CASCADE_BASE" && git clean -qfd) ||
		die "the reset of '$CASCADE_WT' to $CASCADE_BASE failed; rung 2 does not run on a dirty tree"
	rm -rf "$CASCADE_STATE"

	_cs_cfg2=$AGENTS_CONFIG
	_cascade_escalation_policy loud
	_cascade_rung 2 "$_cs_cfg2" "$_cs_tmp/rung2.out" "$@"
	case "$RUNG_STATUS" in
	3) _cascade_handback 2 "$_cs_tmp/rung2.out" "$_cs_cfg2" ;;
	69)
		_cascade_emit model="$(_cascade_model "$_cs_cfg2")" outcome=in-session data.rung=2 \
			reason='the mapped model names an agent harness that is not reachable from here; the caller spawns it and holds the oracle'
		cat "$_cs_tmp/rung2.out"
		exit "$RUNG_STATUS"
		;;
	2 | 4) cat "$_cs_tmp/rung2.out"; exit "$RUNG_STATUS" ;;
	esac
	cat "$_cs_tmp/rung2.out"
	_cascade_after2
}

# _cascade_escalation_policy [loud] — sets _cs_cfg2 to the policy rung 2 runs
# under. THE ESCALATION MUST CHANGE THE MODEL (ADR-0018). When the mechanical
# tier itself maps the cascade's model — the kit's own policy since its
# mechanical tier follows the Sonnet family — rung 2 on "the tier's mapped
# model" would be the same model drawn twice. It escalates to the implementer
# tier's model instead (the ticket's domain carried through), both halves of
# it, staged as the mechanical mapping for that one rung.
_cascade_escalation_policy() {
	# shellcheck disable=SC2086
	if [ "$_m1" = "$(_cascade_model "$AGENTS_CONFIG")" ] &&
		[ "$(AGENTS_CONFIG=$_cs_tmp/cheap.config.sh sh "$ROOT/scripts/agents.lib.sh" --harness $TIER_ARGS 2>/dev/null)" = \
			"$(AGENTS_CONFIG=$AGENTS_CONFIG sh "$ROOT/scripts/agents.lib.sh" --harness $TIER_ARGS 2>/dev/null)" ]; then
		# shellcheck disable=SC2086
		_esc_model=$(AGENTS_CONFIG=$AGENTS_CONFIG sh "$ROOT/scripts/agents.lib.sh" implementer $_cascade_domain 2>/dev/null) || _esc_model=''
		# shellcheck disable=SC2086
		_esc_harness=$(AGENTS_CONFIG=$AGENTS_CONFIG sh "$ROOT/scripts/agents.lib.sh" --harness implementer $_cascade_domain 2>/dev/null) || _esc_harness=''
		if [ -n "$_esc_model" ]; then
			case "$_esc_harness$_esc_model" in *"'"*) die "the implementer tier's value carries a quote; the cascade cannot stage its escalation" ;; esac
			{
				printf ". '%s'\n" "$AGENTS_CONFIG"
				printf "AGENT_TIER_MECHANICAL='%s%s'\n" "${_esc_harness:+$_esc_harness:}" "$_esc_model"
				[ -n "$_cascade_domain" ] &&
					printf 'unset AGENT_TIER_MECHANICAL_%s\n' "$(printf '%s' "$_cascade_domain" | tr 'a-z-' 'A-Z_')"
			} >"$_cs_tmp/escalate.config.sh"
			_cs_cfg2=$_cs_tmp/escalate.config.sh
			[ -z "${1:-}" ] ||
				echo "skill-dispatch: the mechanical tier maps the cascade's own model ($_m1); rung 2 escalates to the implementer tier's model ($_esc_model)" >&2
		fi
	fi
}

# _cascade_after2 — rung 2's verdict. Never returns.
_cascade_after2() {
	_m2=$(_cascade_model "$_cs_cfg2")
	rm -rf "$CASCADE_STATE"
	if [ "$ORACLE_EXIT" = 0 ] && [ "$GUARD_EXIT" = 0 ]; then
		_cascade_verdict 2 "$_m2" passed 'the oracle and the pairing guard are green on the mapped model'
		exit 0
	fi
	_cascade_verdict 2 "$_m2" failed 'the oracle or the pairing guard is red on the mapped model too'
	echo "skill-dispatch: cascade failed — the mapped model's rung is red too (oracle exit $ORACLE_EXIT, pairing guard exit $GUARD_EXIT); the ticket goes back to a human" >&2
	exit 1
}

# _dispatch <dispatch args…> — the one way out: the cascade, or the exec.
_dispatch() {
	[ "$CASCADE" = 1 ] && _cascade "$@"
	# shellcheck disable=SC2086  # TIER_ARGS is one or two words, by construction
	exec sh "$ROOT/scripts/agent-dispatch.sh" $TIER_ARGS "$@"
}

# The prompt the dispatched session receives has to say what to run, because
# the skill name is this script's input and the other session's instruction.
# A --prompt is prefixed; a --prompt-file is left alone, since a file is the
# caller's own document and rewriting it would be a surprise.
#
# Every argument is carried through as a POSITIONAL, never accumulated into a
# string: agent-dispatch takes `--set NAME=VALUE`, and a value with a space in
# it would word-split at the exec and arrive as a stray positional, which that
# script reads as the task DOMAIN. One loop, `set -- "$@" "$a"`, and the
# quoting survives the hop.
PROMPT_SEEN=''
for a in "$@"; do
	case "$a" in
	--prompt) PROMPT_SEEN=text ;;
	--prompt-file) PROMPT_SEEN=file ;;
	esac
done

# dispatch_rewritten <prefix | spec> <args…> — one pass over the arguments,
# replacing each `--prompt <text>` pair in place, then the exec. A function,
# because a rewritten "$@" cannot be handed back to the caller's positionals,
# and both rewrites end in the same exec anyway.
#   prefix   `--prompt "Run <skill>. <text>"` — the instruction every other
#            skill's dispatched session needs.
#   spec     `--set SPEC=<text>` — the caller's text fills the review
#            contract's own slot; the contract itself rides in as the
#            trailing `--prompt-file` the review-pr branch appends below.
dispatch_rewritten() {
	_dr_mode=$1
	shift
	_count=$#
	take_next=0
	while [ "$_count" -gt 0 ]; do
		a=$1
		shift
		_count=$((_count - 1))
		if [ "$take_next" = 1 ]; then
			take_next=0
			case "$_dr_mode" in
			prefix) set -- "$@" --prompt "${SPAWN_LINES}Run $SKILL. $a" ;;
			spec) set -- "$@" --set "SPEC=$a" ;;
			esac
			continue
		fi
		case "$a" in
		--prompt)
			take_next=1
			continue
			;;
		esac
		set -- "$@" "$a"
	done
	# The dispatcher would refuse a trailing `--prompt` itself; a rewrite
	# that swallowed it would send a contract with an empty spec instead.
	[ "$take_next" = 0 ] || die "--prompt needs text"
	_dispatch "$@"
}

# --- the in-session review (#880) -------------------------------------------
# WHY. The manual's review one-liner redirects this dispatcher to a file and
# runs the broker only on exit 0. A reviewer tier whose model names no agent
# harness is agent-dispatch's in-session exit 3, so the broker half never ran:
# the session got a model id and nothing to spawn, and every review in the
# 2026-10-23 wave was improvised by hand. So the review is HANDED BACK the way
# the cascade hands back a rung: exit 3, the model on stdout exactly as
# agent-dispatch prints it, and the contract staged — Trace-Run and
# Trace-Spawn first — at <git dir>/skill-review/prompt, never the working
# tree. The session spawns the reviewer on the tier's agent type with that
# prompt verbatim, saves the report it returns, and runs the broker on it.
#
# THE DIFF IS STAGED TOO. The reviewer agent type reads files and runs no
# command, and the contract tells the worker to run `git rev-parse` and `git
# diff`. So the hand-back pins the branch's commit and writes `git diff
# <base>...<commit>` beside the prompt, and a preamble under the two trace
# lines tells the reviewer to read those instead. The rendering below mirrors
# agent-dispatch's header strip and one-pass marker fill: that script is
# shared layer and exits 3 before it renders anything, and moving its renderer
# into a shared helper is a release action, not a passenger on this ticket.
#
# A dry run stages nothing. A --prompt-file is the caller's own document and
# is never rendered here: it keeps agent-dispatch's plain exit 3.

# _review_handback <contract> <dispatch args…> — stage the review, exit 3.
_review_handback() {
	_rh_contract=$1
	shift
	_rh_n=0 _rh_branch='' _rh_base=''
	_count=$#
	while [ "$_count" -gt 0 ]; do
		a=$1
		shift
		_count=$((_count - 1))
		case "$a" in
		--prompt | --set | --set-file)
			[ "$_count" -gt 0 ] || die "$a needs a value"
			_rh_v=$1
			shift
			_count=$((_count - 1))
			case "$a" in
			--prompt) _rh_k=SPEC _rh_f='' ;;
			*)
				case "$_rh_v" in *=*) ;; *) die "$a takes NAME=VALUE, got '$_rh_v'" ;; esac
				_rh_k=${_rh_v%%=*} _rh_v=${_rh_v#*=} _rh_f=''
				[ "$a" = --set ] || { _rh_f=$_rh_v _rh_v=''; }
				;;
			esac
			case "$_rh_k" in
			'' | [!A-Za-z_]* | *[!A-Za-z0-9_]*) die "a marker NAME must match [A-Za-z_][A-Za-z0-9_]*, got '$_rh_k'" ;;
			esac
			[ -z "$_rh_f" ] || [ -f "$_rh_f" ] || die "--set-file path is not a readable file: $_rh_f"
			_rh_i=1
			while [ "$_rh_i" -le "$_rh_n" ]; do
				[ "$(eval "printf '%s' \"\$RH_K_$_rh_i\"")" != "$_rh_k" ] ||
					die "marker '$_rh_k' is set twice — a NAME may appear in one --set or --set-file only"
				_rh_i=$((_rh_i + 1))
			done
			_rh_n=$((_rh_n + 1))
			eval "RH_K_$_rh_n=\$_rh_k RH_V_$_rh_n=\$_rh_v RH_F_$_rh_n=\$_rh_f"
			eval "export RH_K_$_rh_n RH_V_$_rh_n RH_F_$_rh_n"
			case "$_rh_k" in
			BRANCH) _rh_branch=$_rh_v ;;
			BASE) _rh_base=$_rh_v ;;
			esac
			;;
		*) set -- "$@" "$a" ;;
		esac
	done
	_rh_missing=''
	[ -n "$_rh_branch" ] || _rh_missing='--set BRANCH=<branch>'
	[ -n "$_rh_base" ] || _rh_missing="${_rh_missing:+$_rh_missing and }--set BASE=<base>"
	[ -z "$_rh_missing" ] ||
		die "missing $_rh_missing; an in-session review is handed back with its diff staged, so it needs both refs — repair the call and dispatch again"
	for _rh_ref in "$_rh_branch" "$_rh_base"; do
		case "$_rh_ref" in -*) die "BRANCH and BASE name refs; '$_rh_ref' opens with '-' and would read as an option" ;; esac
	done
	_rh_wt=${CASCADE_WT:-.}
	_rh_sha=$(cd "$_rh_wt" && git rev-parse --verify -q "$_rh_branch^{commit}") ||
		die "BRANCH '$_rh_branch' names no commit in '$_rh_wt' — the in-session review pins the commit it hands back"
	(cd "$_rh_wt" && git rev-parse --verify -q "$_rh_base^{commit}" >/dev/null) ||
		die "BASE '$_rh_base' names no commit in '$_rh_wt'"
	_rh_state="$(cd "$_rh_wt" && git rev-parse --absolute-git-dir)/skill-review"
	rm -rf "$_rh_state"
	mkdir -p "$_rh_state" || die "cannot stage the in-session review under '$_rh_state'"
	(cd "$_rh_wt" && git diff "$_rh_base...$_rh_sha") >"$_rh_state/diff" ||
		{ rm -rf "$_rh_state"; die "cannot stage the diff of '$_rh_base...$_rh_sha'"; }
	printf '%s\n' "$_rh_sha" >"$_rh_state/commit"
	{
		printf '%s' "$SPAWN_LINES"
		printf 'You run in this session, on an agent type that reads files and runs no command, so the dispatcher ran git for you. The commit to review is %s — `git rev-parse %s` when this review was handed back — and `git diff %s...%s` is staged at %s. Wherever the text below tells you to run either command, read those instead, and report that sha as REVIEWED.\n\n' \
			"$_rh_sha" "$_rh_branch" "$_rh_base" "$_rh_sha" "$_rh_state/diff"
		RH_N=$_rh_n awk '
			BEGIN {
				n = ENVIRON["RH_N"] + 0
				for (i = 1; i <= n; i++) {
					k[i] = "%%" ENVIRON["RH_K_" i] "%%"
					kl[i] = length(k[i])
					path = ENVIRON["RH_F_" i]
					if (path != "") {
						s = ""
						while ((getline ln < path) > 0) s = s ln "\n"
						close(path)
						v[i] = s
					} else v[i] = ENVIRON["RH_V_" i]
				}
			}
			NR == 1 && $0 == "<!--" { hdr = 1; next }
			hdr { if ($0 == "-->") { hdr = 0; lead = 1 }; next }
			lead && $0 == "" { next }
			{
				lead = 0; line = $0; out = ""; pos = 1; len = length(line)
				while (pos <= len) {
					hit = 0
					for (i = 1; i <= n; i++)
						if (substr(line, pos, kl[i]) == k[i]) { out = out v[i]; pos += kl[i]; hit = 1; break }
					if (!hit) { out = out substr(line, pos, 1); pos++ }
				}
				print out
			}
			END { exit(hdr ? 1 : 0) }
		' "$_rh_contract"
	} >"$_rh_state/prompt" || { rm -rf "$_rh_state"; die "cannot render the worker contract into '$_rh_state/prompt'"; }
	_rh_rc=0
	# shellcheck disable=SC2086  # TIER_ARGS is one or two words, by construction
	_rh_model=$(sh "$ROOT/scripts/agent-dispatch.sh" $TIER_ARGS "$@" --prompt-file "$_rh_state/prompt") || _rh_rc=$?
	if [ "$_rh_rc" != 3 ]; then
		rm -rf "$_rh_state"
		[ -z "$_rh_model" ] || printf '%s\n' "$_rh_model"
		exit "$_rh_rc"
	fi
	echo "skill-dispatch: the review is yours to spawn in-session — agent type '${TIER_ARGS%% *}', model '${_rh_model:-none: the spawn inherits}', its prompt verbatim from $_rh_state/prompt (commit $_rh_sha, its diff beside it). Save the report it returns to a file outside the working tree, then run the broker on that file with --commit $_rh_sha: the broker validates and posts it." >&2
	[ -z "$_rh_model" ] || printf '%s\n' "$_rh_model"
	exit 3
}

case "${SKILL#/}" in
review-pr)
	# The header above says why: the worker is offline, so it gets the
	# contract, never an instruction to run a skill that needs the network.
	# With no --prompt the contract alone is the prompt — the spec arrives as
	# `--set-file SPEC=<path>` when a ticket body is too large for argv.
	if [ "$PROMPT_SEEN" != file ]; then
		CONTRACT="$ROOT/.agents/prompts/review-worker.md"
		[ -f "$CONTRACT" ] || die "no worker contract at .agents/prompts/review-worker.md — /review-pr cannot be dispatched without it"
		_rh_dry=0
		for a in "$@"; do [ "$a" != --dry-run ] || _rh_dry=1; done
		# shellcheck disable=SC2086  # TIER_ARGS is one or two words, by construction
		if [ "$_rh_dry" = 0 ] &&
			[ -z "$(AGENTS_TIER_QUIET=1 sh "$ROOT/scripts/agents.lib.sh" --harness $TIER_ARGS 2>/dev/null)" ]; then
			_review_handback "$CONTRACT" "$@"
		fi
		if [ -n "$SPAWN_LINES" ]; then
			# The two lines go under the contract's editor header, which the
			# dispatcher strips, so they open what the worker reads. A copy,
			# never the contract itself; removed when the dispatch returns.
			_sl_contract=$(mktemp "${TMPDIR:-/tmp}/skill-dispatch.XXXXXX") || die "cannot stage the worker contract"
			SPAWN_LINES=$SPAWN_LINES awk '
				BEGIN { lines = ENVIRON["SPAWN_LINES"] }
				NR == 1 && $0 != "<!--" { printf "%s", lines; done = 1 }
				{ print }
				!done && $0 == "-->" { printf "%s", lines; done = 1 }
			' "$CONTRACT" >"$_sl_contract"
			_sl_rc=0
			(dispatch_rewritten spec "$@" --prompt-file "$_sl_contract") || _sl_rc=$?
			rm -f "$_sl_contract"
			exit "$_sl_rc"
		fi
		dispatch_rewritten spec "$@" --prompt-file "$CONTRACT"
	fi
	;;
*)
	[ -n "$PROMPT_SEEN" ] || die "no --prompt or --prompt-file — there is nothing to send"
	[ "$PROMPT_SEEN" != text ] || dispatch_rewritten prefix "$@"
	;;
esac
# A --prompt-file, whichever the skill: the caller's own document, untouched.
_dispatch "$@"
