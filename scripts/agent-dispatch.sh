#!/bin/sh
# agent-dispatch.sh — run a capability tier on the AGENT HARNESS its mapping names.
#
#   sh scripts/agent-dispatch.sh <tier> [domain] --prompt-file <path> [--dry-run]
#   sh scripts/agent-dispatch.sh <tier> [domain] --prompt <text>      [--dry-run]
#
# THE ONE THING THIS ADDS. `scripts/agents.lib.sh` answers which agent harness
# and which model a tier runs on; it deliberately stops there, because where a
# model id goes at spawn time is specific to the agent harness
# (`adapters/claude-code/README.md` is the worked example). That was a complete
# answer while every tier ran in the caller's own session: a skill read the
# model and passed it to its own spawn call.
#
# It stops being complete the moment a tier names a DIFFERENT agent harness,
# because crossing to one means leaving the session, and no in-session spawn
# call can do that. `templates/workflows/ai-review.example.yml` says so in its
# own header: the cross-provider leg "is unreachable from inside the authoring
# harness", which is why the kit's only cross-vendor review runs in CI, where
# the secrets are. This file is that leg, reachable locally. ADR-0005 records
# the decision and why this script is shared layer.
#
# WHY THIS EXECUTES AND adapters/ DOES NOT. `adapters/README.md` is explicit
# that nothing under it is on an execution path — an adapter is reference prose
# a human reads while wiring the kit up. This is mechanism, so it lives in
# scripts/ beside the resolver it calls.
#
# EXIT STATUS, and why 3 is not a failure:
#   0  dispatched — stdout is the worker's own output
#   3  NOT dispatched, because this tier names no agent harness. stdout is the
#      model id (possibly empty, meaning "inherit"). The caller spawns it
#      itself, exactly as it did before this file existed. This is the DEFAULT
#      for an unconfigured project and it is a working state.
#   2  usage error, unknown tier, or an agent harness with no command template
#   *  the worker's own exit status, passed through untouched
#
# CONFIGURATION lives in scripts/agents.config.sh beside the tier mapping:
#
#   AGENT_HARNESSES='<token> ...'
#   AGENT_HARNESS_<TOKEN>_CMD='<command> {model_flag} < {prompt_file}'
#   AGENT_HARNESS_<TOKEN>_MODEL_FLAG='<the flag> {model}'
#
# `{model_flag}` expands to the MODEL_FLAG template with `{model}` filled when a
# model is mapped, and to NOTHING when one is not — which is
# `adapters/claude-code/README.md`'s "do not pass an empty string as the model
# parameter; branch on emptiness" rule, made declarative. `{prompt_file}` is the
# assembled prompt.
#
# Everything else in the template is yours — in particular the AUTONOMY FLAGS a
# headless worker needs (approval modes, sandbox settings, tool allowlists) are
# yours to choose, because their blast radius is yours to own. The kit writes
# none of them, for the same reason it names no model: a standing instruction
# about someone else's security posture is worse than none.
#
# THE TEMPLATE IS EVAL'D, which is safe for the same reason sourcing the policy
# file is: it is your file, and a file that can define shell variables can
# already define shell functions. It is not a boundary against a hostile config,
# and it is not one against a hostile MODEL ID either — hence the whitelist
# below, which is.
#
# WHAT A WORKER MAY NOT DO. Shared invariant §7 puts a human's name on the
# merge, and nothing here changes that: a dispatched worker writes to the
# working tree and says what it did. It does not push and it does not merge.
# That is a property of the prompt and of the flags in your template, not
# something this script can enforce — which is exactly why it is written here.

set -u

_here=$(dirname "$0")
LIB="$_here/agents.lib.sh"
[ -f "$LIB" ] || {
	echo "x dispatch: cannot find agents.lib.sh beside $0" >&2
	exit 2
}

usage() {
	echo "usage: agent-dispatch.sh <tier> [domain] (--prompt-file <path> | --prompt <text>) [--dry-run]" >&2
	echo "  tier is one of: planner implementer mechanical reviewer" >&2
	echo "  --dry-run  print the agent harness, the model, the expanded command and" >&2
	echo "             the prompt; run nothing." >&2
}

die() {
	echo "x dispatch: $1" >&2
	exit 2
}

TIER="" DOMAIN="" PROMPT_FILE="" PROMPT_TEXT="" DRY_RUN=0 HAVE_PROMPT=0

while [ $# -gt 0 ]; do
	case "$1" in
	--prompt-file)
		[ $# -ge 2 ] || die "--prompt-file needs a path"
		PROMPT_FILE=$2 HAVE_PROMPT=1
		shift 2
		;;
	--prompt)
		[ $# -ge 2 ] || die "--prompt needs a value"
		PROMPT_TEXT=$2 HAVE_PROMPT=1
		shift 2
		;;
	--dry-run)
		DRY_RUN=1
		shift
		;;
	--*)
		echo "x dispatch: unknown option '$1'." >&2
		usage
		exit 2
		;;
	*)
		if [ -z "$TIER" ]; then TIER=$1
		elif [ -z "$DOMAIN" ]; then DOMAIN=$1
		else
			echo "x dispatch: unexpected argument '$1'." >&2
			usage
			exit 2
		fi
		shift
		;;
	esac
done

[ -n "$TIER" ] || {
	usage
	exit 2
}
[ "$HAVE_PROMPT" = 1 ] || die "no prompt — pass --prompt-file or --prompt"
[ -n "$PROMPT_FILE" ] && [ -n "$PROMPT_TEXT" ] && die "--prompt-file and --prompt are alternatives, not a pair"
[ -n "$PROMPT_FILE" ] && [ ! -f "$PROMPT_FILE" ] && die "prompt file does not exist: $PROMPT_FILE"
[ -n "$PROMPT_FILE" ] && [ ! -s "$PROMPT_FILE" ] && die "prompt file is empty: $PROMPT_FILE
   A worker given nothing to do will invent something to do."

# --- resolution -------------------------------------------------------------
# Two calls rather than one parse of a joined value: the resolver owns the
# split, and a caller that re-implemented it here would be the second place the
# `<name>:<tag>` rule has to be right.
# Two calls, so two processes, so the resolver's once-per-process warning memo
# cannot span them and an unconfigured project heard the UNMAPPED warning twice.
# The --harness call is silenced: it asks a question whose answer for such a
# project is "none", and the --model call that follows says everything the
# operator needs to hear, once.
if [ -n "$DOMAIN" ]; then
	HARNESS=$(AGENTS_TIER_QUIET=1 sh "$LIB" --harness "$TIER" "$DOMAIN") || exit $?
	MODEL=$(sh "$LIB" --model "$TIER" "$DOMAIN") || exit $?
else
	HARNESS=$(AGENTS_TIER_QUIET=1 sh "$LIB" --harness "$TIER") || exit $?
	MODEL=$(sh "$LIB" --model "$TIER") || exit $?
fi

# --- the in-session case, which is the default and not a failure ------------
if [ -z "$HARNESS" ]; then
	echo "i  dispatch: tier '$TIER' names no agent harness — spawn it in your own session, as before." >&2
	[ -n "$MODEL" ] && printf '%s\n' "$MODEL"
	exit 3
fi

# The token reached here through the resolver's shape check and the project's
# own declaration, so it is already a `[a-z][a-z0-9-]*` token — safe to fold
# into a variable name the way a task domain is.
H_UPPER=$(printf '%s' "$HARNESS" | tr 'a-z-' 'A-Z_')

# The policy file is sourced in a SUBSHELL: this script must not inherit
# whatever else it defines, and needs exactly two values out of it. The
# assignments sit on their own lines because bash and zsh drop a prefix
# assignment on `.` — agents.lib.sh says so in its own header, and doing it the
# short way sources the library with AGENTS_CONFIG unset.
_read_policy() {
	(
		AGENTS_CONFIG=${AGENTS_CONFIG:-}
		export AGENTS_CONFIG
		_agents_here="$_here"
		. "$LIB"
		agents_load_config >/dev/null 2>&1 || true
		eval "printf '%s' \"\${$1:-}\""
	)
}
CMD_TEMPLATE=$(_read_policy "AGENT_HARNESS_${H_UPPER}_CMD")
FLAG_TEMPLATE=$(_read_policy "AGENT_HARNESS_${H_UPPER}_MODEL_FLAG")

[ -n "$CMD_TEMPLATE" ] || die "agent harness '$HARNESS' has no AGENT_HARNESS_${H_UPPER}_CMD in your agents config.
   The tier mapping names an agent harness the config never says how to invoke.
   Add it beside the tier mapping, e.g.
     AGENT_HARNESS_${H_UPPER}_CMD='$HARNESS ... {model_flag} < {prompt_file}'"

# --- the model id whitelist -------------------------------------------------
# THIS one is a boundary. The template is eval'd and the model id is
# interpolated into it, so an id carrying a quote, a semicolon or a backtick
# would be executed rather than passed. Model identifiers are drawn from a
# narrow alphabet in practice — letters, digits, and `. _ - : /`, the last for
# the `provider/model` form some CLIs use — and anything outside it is refused
# rather than escaped: refusing is checkable, escaping is a claim.
#
# The alphabet is spelled out rather than written as a range for the locale
# reason agents.lib.sh documents at its own two `case` sites: under en_US.UTF-8
# a bracket range collates case-insensitively, and a whitelist whose meaning
# moves with $LANG is not a whitelist.
#
# An EMPTY model is not refused. It means "this agent harness, on its own
# default", and the flag is omitted entirely below.
_alnum='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
if [ -n "$MODEL" ]; then
	case "$MODEL" in
	[!$_alnum]* | *[!$_alnum._:/-]*)
		die "model id '$MODEL' contains a character this script will not interpolate.
   Allowed: letters, digits, and . _ - : /
   The command template is eval'd, so an id outside that set is refused rather
   than escaped." ;;
	esac
fi

# --- the model flag ---------------------------------------------------------
# Omitting a parameter and passing "" are not the same request, and an agent
# harness is within its rights to reject the second. So an unmapped model
# removes the WHOLE flag, not just its value.
if [ -n "$MODEL" ] && [ -n "$FLAG_TEMPLATE" ]; then
	MODEL_FLAG=$(printf '%s' "$FLAG_TEMPLATE" | sed "s|{model}|$MODEL|g")
elif [ -n "$MODEL" ]; then
	# A project that wired no MODEL_FLAG but mapped a model has said where the
	# model goes nowhere. Better to say so than to drop it silently.
	die "agent harness '$HARNESS' maps a model but has no AGENT_HARNESS_${H_UPPER}_MODEL_FLAG.
   Without it there is nowhere to put '$MODEL'. Add it beside the command, e.g.
     AGENT_HARNESS_${H_UPPER}_MODEL_FLAG='--model {model}'"
else
	MODEL_FLAG=""
fi

# --- the prompt -------------------------------------------------------------
# Always a FILE, even when the caller passed text: the template redirects from
# {prompt_file}, and a prompt is prose that will contain quotes, newlines and
# code fences. Putting it on the command line would put all three through the
# shell.
SCRATCH=""
cleanup() { [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; }
trap cleanup EXIT INT TERM HUP

# The prompt is ALWAYS staged into a file this script created, even when the
# caller passed one. The caller's path is data — a branch name becomes a
# worktree slug becomes a directory, and `;` `$` `(` `&` `|` and spaces are all
# legal in a branch name — and this path is interpolated into the eval'd
# template. Passing it through directly executed it: a prompt file under a
# directory named `a;$(touch PWNED)b` created PWNED.
#
# Staging is not by itself the fix, because $TMPDIR is also somebody else's
# data. So the staged path is held to the same refuse-don't-escape rule as the
# model id, and single-quoted at the substitution on top of that.
SCRATCH=$(mktemp -d) || die "cannot create a scratch directory"
_staged="$SCRATCH/prompt.md"
if [ -n "$PROMPT_FILE" ]; then
	cat -- "$PROMPT_FILE" >"$_staged" || die "cannot read the prompt file: $PROMPT_FILE"
else
	printf '%s\n' "$PROMPT_TEXT" >"$_staged"
fi
PROMPT_FILE="$_staged"

case "$PROMPT_FILE" in
*[!$_alnum._/-]*)
	die "the scratch path '$PROMPT_FILE' contains a character this script will not
   interpolate into a command. TMPDIR is the usual cause — point it somewhere
   made of letters, digits and . _ - / and run again." ;;
esac

# --- expansion --------------------------------------------------------------
# `|` is the sed delimiter because it is excluded from the model whitelist above
# and from any path mktemp produces, so neither substitution can close the
# expression early.
# The path is single-quoted as well as whitelisted: the whitelist keeps the
# sed expression and the eval intact, and the quotes keep a path with a space
# in it one word to the redirect. Belt and braces, because this is the value
# that got it wrong once.
CMD=$(printf '%s' "$CMD_TEMPLATE" |
	sed -e "s|{model_flag}|$MODEL_FLAG|g" -e "s|{prompt_file}|'$PROMPT_FILE'|g")

# The command's own name, checked before anything runs, so an uninstalled agent
# harness reports itself rather than surfacing as a shell "not found" mixed into
# the worker's output, where a caller would read it as the worker's answer.
# The command's own name, checked before anything runs. Leading `VAR=value`
# words are skipped: a template that sets an environment variable for the
# worker is the natural way to write one, and taking the first word blindly
# reported `FOO=1` as a missing program.
CMD_REST=$CMD
while :; do
	CMD_BIN=${CMD_REST%% *}
	case "$CMD_BIN" in
	[!=]*=*)
		_next=${CMD_REST#* }
		[ "$_next" = "$CMD_REST" ] && break
		CMD_REST=$_next
		;;
	*) break ;;
	esac
done
command -v "$CMD_BIN" >/dev/null 2>&1 ||
	die "agent harness '$HARNESS' invokes '$CMD_BIN', which is not on PATH."

if [ "$DRY_RUN" = 1 ]; then
	printf 'tier:           %s%s\n' "$TIER" "${DOMAIN:+ (domain: $DOMAIN)}"
	printf 'agent harness:  %s\n' "$HARNESS"
	# The default text is a plain variable, not a ${VAR:-word} default: bash
	# treats an apostrophe inside ${...} as quoting even within double quotes,
	# so "harness's" there unbalanced every quote in the rest of the file. sh
	# and zsh parsed it happily, which is exactly why the three-shell check
	# exists.
	_shown_model=$MODEL
	[ -n "$_shown_model" ] || _shown_model="<the default model of that agent harness>"
	printf 'model:          %s\n' "$_shown_model"
	printf 'command:        %s\n' "$CMD"
	printf '\n--- prompt (%s bytes) ---\n' "$(wc -c <"$PROMPT_FILE" | tr -d ' ')"
	cat "$PROMPT_FILE"
	printf '\n--- end prompt ---\n'
	exit 0
fi

echo "i  dispatch: tier '$TIER' -> agent harness '$HARNESS', model '${MODEL:-<default>}'" >&2
eval "$CMD"
