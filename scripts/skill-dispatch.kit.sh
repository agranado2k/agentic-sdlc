#!/bin/sh
# skill-dispatch.kit.sh — run a SKILL on the model its phase deserves.
# Kit-authoring only, never shipped (bootstrap.sh's KIT_ONLY deletes it).
#
#   sh scripts/skill-dispatch.kit.sh <skill> --prompt <text>      [--dry-run]
#   sh scripts/skill-dispatch.kit.sh <skill> --prompt-file <path> [--dry-run]
#   sh scripts/skill-dispatch.kit.sh <skill> --tier <tier> [--domain <token>] ...
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
# sizing itself. `--dry-run` names which of the two answered.
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
	echo "usage: sh scripts/skill-dispatch.kit.sh <skill> [--tier <tier> [--domain <token>]] --prompt <text> [--dry-run]" >&2
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
	*) set -- "$@" "$a" ;;
	esac
done

if [ -n "$OVERRIDE_TIER" ]; then
	case "$OVERRIDE_TIER" in
	planner | implementer | mechanical | reviewer) ;;
	*) die "unknown tier '$OVERRIDE_TIER'. The vocabulary is closed: planner implementer mechanical reviewer." ;;
	esac
	TIER_ARGS="$OVERRIDE_TIER${OVERRIDE_DOMAIN:+ $OVERRIDE_DOMAIN}"
	TIER_SOURCE="the ticket's stamp"
else
	[ -z "$OVERRIDE_DOMAIN" ] || die "--domain without --tier: a domain is the second half of a ticket's stamp, not a sizing of its own"
	TIER_ARGS=$(phase_tier "$(skill_phase "$SKILL")")
	TIER_SOURCE="$SKILL's own phase"
fi
for a in "$@"; do
	[ "$a" = --dry-run ] || continue
	echo "skill-dispatch: tier '$TIER_ARGS' — from $TIER_SOURCE" >&2
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
	# shellcheck disable=SC2086  # TIER_ARGS is one or two words, by construction
	exec sh "$ROOT/scripts/agent-dispatch.sh" $TIER_ARGS "$@"
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
# shellcheck disable=SC2086  # TIER_ARGS is one or two words, by construction
exec sh "$ROOT/scripts/agent-dispatch.sh" $TIER_ARGS "$@"
