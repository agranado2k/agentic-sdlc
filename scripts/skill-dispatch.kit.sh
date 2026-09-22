#!/bin/sh
# skill-dispatch.kit.sh — run a SKILL on the model its phase deserves.
# Kit-authoring only, never shipped (bootstrap.sh's KIT_ONLY deletes it).
#
#   sh scripts/skill-dispatch.kit.sh <skill> --prompt <text>      [--dry-run]
#   sh scripts/skill-dispatch.kit.sh <skill> --prompt-file <path> [--dry-run]
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
# WHY `tester` IS NOT A TIER. The four tier names are a CLOSED vocabulary (an
# unknown one is exit 2, and widening it is a resolver change, a manual change
# and a release). Writing the failing test is implementer work by tier — one
# behaviour, test-first, through a seam — whose MEDIUM is different, which is
# exactly what the open domain axis is for. So the phase `tester` maps to the
# tier `implementer` with the domain `tests`, and the policy files map that
# pair to whichever model should be reading specifications that day.
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

usage() {
	echo "usage: sh scripts/skill-dispatch.kit.sh <skill> --prompt <text> [--dry-run]" >&2
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
TIER_ARGS=$(phase_tier "$(skill_phase "$SKILL")")

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
[ -n "$PROMPT_SEEN" ] || die "no --prompt or --prompt-file — there is nothing to send"

if [ "$PROMPT_SEEN" = text ]; then
	_count=$#
	take_next=0
	while [ "$_count" -gt 0 ]; do
		a=$1
		shift
		_count=$((_count - 1))
		if [ "$take_next" = 1 ]; then
			take_next=0
			set -- "$@" --prompt "Run $SKILL. $a"
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
fi
# shellcheck disable=SC2086  # TIER_ARGS is one or two words, by construction
exec sh "$ROOT/scripts/agent-dispatch.sh" $TIER_ARGS "$@"
