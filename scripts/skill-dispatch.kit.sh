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
	echo "  phases: planner implementer tester mechanical reviewer" >&2
	exit 2
}

# phase_tier <phase> — the resolver arguments a phase means, on one line.
# `tester` is the only one that carries a domain; see the header.
phase_tier() {
	case "$1" in
	planner | implementer | mechanical | reviewer) printf '%s\n' "$1" ;;
	tester) printf 'implementer tests\n' ;;
	*) die "unknown phase '$1'. The vocabulary is closed: planner implementer tester mechanical reviewer." ;;
	esac
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
_count=$#
while [ "$_count" -gt 0 ]; do
	a=$1
	shift
	_count=$((_count - 1))
	case "$a" in
	--tier)
		[ "$_count" -gt 0 ] || die "--tier needs one of: planner implementer mechanical reviewer"
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
# 2, the refused text never printed. Sets TIER_ARGS, or _fs_none on exit 3.
_fs_read_stamp() {
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
	case "$_fs_tier" in
	planner | implementer | mechanical | reviewer) TIER_ARGS="$_fs_tier${_fs_domain:+ $_fs_domain}" ;;
	*) _fs_none=1 ;;
	esac
}

if [ -n "$OVERRIDE_TIER" ]; then
	case "$OVERRIDE_TIER" in
	planner | implementer | mechanical | reviewer) ;;
	*) die "unknown tier '$OVERRIDE_TIER'. The vocabulary is closed: planner implementer mechanical reviewer." ;;
	esac
	TIER_ARGS="$OVERRIDE_TIER${OVERRIDE_DOMAIN:+ $OVERRIDE_DOMAIN}"
	TIER_SOURCE="the ticket's stamp"
else
	[ -z "$OVERRIDE_DOMAIN" ] || die "--domain without --tier: a domain is the second half of a ticket's stamp, not a sizing of its own"
	TIER_ARGS=''
	_fs_none=''
	[ -z "$CASCADE_TICKET" ] || _fs_read_stamp
	if [ -n "$TIER_ARGS" ]; then
		TIER_SOURCE="the ticket file's stamp"
	else
		TIER_ARGS=$(phase_tier "$(skill_phase "$SKILL")")
		TIER_SOURCE="$SKILL's own phase${_fs_none:+ (the ticket file carries no stamp)}"
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
# The run is the one this dispatch runs under, asked of the trace script the
# way agent-dispatch.sh asks it (a dry-run emit, which writes nothing); with no
# trace script, the environment's. No run, no lines: a Trace-Spawn line with
# no Trace-Run line above it is no line to the hook.
SPAWN_LINES=''
_sl_run=${TRACE_RUN:-} _sl_parent=${TRACE_PARENT:-}
if [ -f "$ROOT/scripts/trace.sh" ]; then
	_sl_ev=$(TRACE_QUIET=1 sh "$ROOT/scripts/trace.sh" emit kind=note --dry-run 2>/dev/null) || _sl_ev=''
	_sl_run=$(printf '%s\n' "$_sl_ev" | sed -n 's/.*"run":"\([^"]*\)".*/\1/p')
	_sl_parent=$(printf '%s\n' "$_sl_ev" | sed -n 's/.*"parent":"\([^"]*\)".*/\1/p')
fi
_sl_id_ok() { printf '%s\n' "$1" | grep -Eqx '[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9a-f]{8}'; }
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
# record is the verdict, not a second crossing. A rung the dispatcher could not
# run itself (agent-dispatch exit 3 or 69, the caller spawns it) is recorded
# `in-session` on the mapped rung and `refused` on the cheap one, which then
# falls through to the plain path: an oracle cannot judge work this process
# never ran.
#
# EXIT. 0 a rung passed; 1 the mapped rung was red; any dispatch status that is
# not a worker's (2, 3, 4, 69) passes through untouched.

CASCADE=0
CASCADE_MODEL=''
CASCADE_ORACLE=''
_cascade_tier=${TIER_ARGS%% *}
_cascade_domain=''
case "$TIER_ARGS" in *' '*) _cascade_domain=${TIER_ARGS#* } ;; esac

# _cascade_oracle_line <ticket file> — the line that opens the ticket's
# Acceptance section, when it is an oracle line; nothing otherwise. An oracle
# line anywhere else in the body is prose, as /implement step 1 reads it.
_cascade_oracle_line() {
	[ -f "$1" ] || return 0
	awk '
		/^#+[ \t]*Acceptance[ \t]*$/ { in_acc = 1; next }
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
for a in "$@"; do
	[ "$a" = --dry-run ] || continue
	if [ "$CASCADE" = 1 ]; then
		echo "skill-dispatch: cascade — rung 1 on the cascade model, judged by '$CASCADE_ORACLE' and the pairing guard; a red rung resets to $CASCADE_BASE and rung 2 runs on the tier's mapped model, or the implementer tier's when that is the cascade model itself. A dry run runs neither." >&2
		CASCADE=0
	fi
	break
done

# _cascade_emit <field=value …> — one event under the cascade's run, or none.
_cascade_emit() {
	[ -f "$ROOT/scripts/trace.sh" ] || return 0
	TRACE_RUN=$CASCADE_RUN TRACE_PARENT=$CASCADE_PARENT \
		sh "$ROOT/scripts/trace.sh" emit kind=spawn subject="run:$CASCADE_RUN" \
		tier=mechanical ${_cascade_domain:+domain=$_cascade_domain} skill="${SKILL#/}" "$@" >/dev/null 2>&1 || :
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

# _cascade <dispatch args…> — the two rungs. Never returns.
_cascade() {
	CASCADE_RUN="$(date -u +%Y%m%dT%H%M%SZ)-$$-cascade"
	CASCADE_PARENT=${TRACE_RUN:-}
	if [ -z "${TRACE_RUN+set}" ] && [ -f "$ROOT/scripts/trace.sh" ]; then
		CASCADE_PARENT=$(TRACE_QUIET=1 sh "$ROOT/scripts/trace.sh" emit kind=note --dry-run 2>/dev/null |
			sed -n 's/.*"run":"\([^"]*\)".*/\1/p')
	fi
	_cs_tmp=$(mktemp -d "${TMPDIR:-/tmp}/skill-cascade.XXXXXX") || die "no scratch for the cascade"
	trap 'rm -rf "$_cs_tmp"' EXIT
	case "$AGENTS_CONFIG" in *"'"*) die "the policy path carries a quote; the cascade cannot stage its rung policy" ;; esac
	{
		printf ". '%s'\n" "$AGENTS_CONFIG"
		printf 'AGENT_TIER_MECHANICAL=$AGENT_CASCADE_MECHANICAL\n'
		[ -n "$_cascade_domain" ] &&
			printf 'unset AGENT_TIER_MECHANICAL_%s\n' "$(printf '%s' "$_cascade_domain" | tr 'a-z-' 'A-Z_')"
	} >"$_cs_tmp/cheap.config.sh"

	_cascade_rung 1 "$_cs_tmp/cheap.config.sh" "$_cs_tmp/rung1.out" "$@"
	case "$RUNG_STATUS" in
	3 | 69)
		_cascade_emit model="$(_cascade_model "$_cs_tmp/cheap.config.sh")" outcome=refused data.rung=1 \
			reason='the cascade model is not dispatchable from here; an oracle cannot judge work this process never ran'
		echo "skill-dispatch: cascade refused — the cascade model names no agent harness this dispatcher can run (exit $RUNG_STATUS); running on the mechanical tier's mapped model" >&2
		rm -rf "$_cs_tmp"
		# shellcheck disable=SC2086
		exec sh "$ROOT/scripts/agent-dispatch.sh" $TIER_ARGS "$@"
		;;
	2 | 4) cat "$_cs_tmp/rung1.out"; exit "$RUNG_STATUS" ;;
	esac
	_m1=$(_cascade_model "$_cs_tmp/cheap.config.sh")
	if [ "$ORACLE_EXIT" = 0 ] && [ "$GUARD_EXIT" = 0 ]; then
		_cascade_emit model="$_m1" outcome=passed data.rung=1 data.oracle_exit=0 data.guard_exit=0 \
			reason='the oracle and the pairing guard are green on the cascade model'
		cat "$_cs_tmp/rung1.out"
		exit 0
	fi
	_cascade_emit model="$_m1" outcome=escalated data.rung=1 data.oracle_exit="$ORACLE_EXIT" \
		data.guard_exit="$GUARD_EXIT" reason='the oracle or the pairing guard is red on the cascade model'
	echo "skill-dispatch: cascade escalated — oracle exit $ORACLE_EXIT, pairing guard exit $GUARD_EXIT on the cascade model; resetting the worktree to $CASCADE_BASE and running the mechanical tier's mapped model" >&2
	(cd "$CASCADE_WT" && git reset -q --hard "$CASCADE_BASE" && git clean -qfd) ||
		die "the reset of '$CASCADE_WT' to $CASCADE_BASE failed; rung 2 does not run on a dirty tree"

	# THE ESCALATION MUST CHANGE THE MODEL (ADR-0018). When the mechanical
	# tier itself maps the cascade's model — the kit's own policy since its
	# mechanical tier follows the Sonnet family — rung 2 on "the tier's mapped
	# model" would be the same model drawn twice. It escalates to the
	# implementer tier's model instead (the ticket's domain carried through),
	# both halves of it, staged as the mechanical mapping for that one rung.
	_cs_cfg2=$AGENTS_CONFIG
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
			echo "skill-dispatch: the mechanical tier maps the cascade's own model ($_m1); rung 2 escalates to the implementer tier's model ($_esc_model)" >&2
		fi
	fi

	_cascade_rung 2 "$_cs_cfg2" "$_cs_tmp/rung2.out" "$@"
	_m2=$(_cascade_model "$_cs_cfg2")
	case "$RUNG_STATUS" in
	3 | 69)
		_cascade_emit model="$_m2" outcome=in-session data.rung=2 \
			reason='the mapped model names no agent harness this dispatcher runs; the caller spawns it and holds the oracle'
		cat "$_cs_tmp/rung2.out"
		exit "$RUNG_STATUS"
		;;
	2 | 4) cat "$_cs_tmp/rung2.out"; exit "$RUNG_STATUS" ;;
	esac
	cat "$_cs_tmp/rung2.out"
	if [ "$ORACLE_EXIT" = 0 ] && [ "$GUARD_EXIT" = 0 ]; then
		_cascade_emit model="$_m2" outcome=passed data.rung=2 data.oracle_exit=0 data.guard_exit=0 \
			reason='the oracle and the pairing guard are green on the mapped model'
		exit 0
	fi
	_cascade_emit model="$_m2" outcome=failed data.rung=2 data.oracle_exit="$ORACLE_EXIT" \
		data.guard_exit="$GUARD_EXIT" reason='the oracle or the pairing guard is red on the mapped model too'
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

case "${SKILL#/}" in
review-pr)
	# The header above says why: the worker is offline, so it gets the
	# contract, never an instruction to run a skill that needs the network.
	# With no --prompt the contract alone is the prompt — the spec arrives as
	# `--set-file SPEC=<path>` when a ticket body is too large for argv.
	if [ "$PROMPT_SEEN" != file ]; then
		CONTRACT="$ROOT/.agents/prompts/review-worker.md"
		[ -f "$CONTRACT" ] || die "no worker contract at .agents/prompts/review-worker.md — /review-pr cannot be dispatched without it"
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
