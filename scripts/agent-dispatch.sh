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
#   4  NOT dispatched, because this dispatch would nest past the policy
#      maximum depth. A worker may run this script itself; one whose tier maps
#      back to its own agent harness is a fork bomb with a model in the loop,
#      and this is what stops it. Refused before the tier is resolved or the
#      prompt is read, so nothing spawns. AGENT_DISPATCH_MAX_DEPTH below.
# 124  the worker ran past --timeout and its process tree was killed
#   *  the worker's own exit status, passed through untouched
#
# CONFIGURATION lives in scripts/agents.config.sh beside the tier mapping:
#
#   AGENT_HARNESSES='<token> ...'
#   AGENT_HARNESS_<TOKEN>_CMD='<command> {model_flag} < {prompt_file}'
#   AGENT_HARNESS_<TOKEN>_MODEL_FLAG='<the flag> {model}'
#   AGENT_DISPATCH_MAX_DEPTH='<how deep a dispatch may nest>'   empty: 3
#
# THE DEPTH travels the way the other per-dispatch facts do — through the
# worker's environment. AGENT_DISPATCH_DEPTH is this dispatch's own depth,
# unset meaning a top-level dispatch at depth 1; the worker is spawned with it
# set one higher, so a dispatch the worker runs reads its own depth on entry.
# A worker may read it too. A dispatch AT the maximum still runs; one past it
# is exit 4. The ceiling is COOPERATIVE: a worker owns its own environment,
# so `env -u AGENT_DISPATCH_DEPTH` restarts the count at depth 1. It stops an
# accidental loop, not a worker that chooses to nest.
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
	echo "usage: agent-dispatch.sh <tier> [domain] (--prompt-file <path> | --prompt <text>)" >&2
	echo "                          [--set NAME=VALUE ...] [--timeout <seconds>] [--dry-run]" >&2
	echo "  tier is one of: planner implementer mechanical reviewer" >&2
	echo "  --set      replace %%NAME%% in the prompt with VALUE. Repeatable." >&2
	echo "  --set-file replace %%NAME%% with the CONTENTS of a file. For a value" >&2
	echo "             too large for a command line — a diff, say. Repeatable." >&2
	echo "  --timeout  kill the worker after that many seconds and exit 124." >&2
	echo "  --dry-run  print the agent harness, the model, the expanded command and" >&2
	echo "             the prompt; run nothing." >&2
}

die() {
	echo "x dispatch: $1" >&2
	exit 2
}

# _whole_from_one <value> — a whole number from 1, and one `[ -gt ]` can
# compare: past the shell's integer range `[` errors instead of comparing, and
# an error there would fail OPEN — the refusal skipped, the worker run. Nine
# digits is under every shell's range, and no dispatcher produces a depth
# anywhere near it.
DEPTH_MAX_DIGITS=9
_whole_from_one() {
	case "$1" in
	'' | *[!0123456789]* | 0*) return 1 ;;
	esac
	[ "${#1}" -le "$DEPTH_MAX_DIGITS" ]
}

# The policy file is sourced in a SUBSHELL: this script must not inherit
# whatever else it defines, and needs exactly three values out of it. The
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

TIER="" DOMAIN="" PROMPT_FILE="" PROMPT_TEXT="" DRY_RUN=0 HAVE_PROMPT=0 SETS_N=0 TIMEOUT=""

# _record_set <name> <value> — one marker substitution, into its own numbered
# pair of exported variables for the single awk pass below. The obvious
# alternative — accumulating "NAME=VALUE" lines in one string and reading them
# back — is what this replaced, and it was broken twice over: a value with a
# newline was truncated at the first one, and any line inside a value that
# looked like NAME=VALUE was promoted to a substitution of its own. Ticket
# bodies are untrusted content (AGENTS.md's trust boundary) and `%%BODY%%` is
# exactly where one goes. --set and --set-file both come through here, so their
# NAME shape-check cannot drift.
_record_set() {
	case "$1" in
	'' | [!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_]* | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]*)
		die "a marker NAME must match [A-Za-z_][A-Za-z0-9_]*, got '$1'" ;;
	esac
	# A NAME twice is a caller mistake, not a last-wins convenience: which value
	# reached the worker would depend on argument order, which is exactly the
	# kind of quiet ambiguity a reviewer worker reading an untrusted body should
	# not be subject to.
	_rs_j=1
	while [ "$_rs_j" -le "$SETS_N" ]; do
		if [ "$(eval "printf '%s' \"\$PD_K_$_rs_j\"")" = "$1" ]; then
			die "marker '$1' is set twice — a NAME may appear in one --set or --set-file only"
		fi
		_rs_j=$((_rs_j + 1))
	done
	SETS_N=$((SETS_N + 1))
	# PD_F is cleared for EVERY pair, not only set on a --set-file: an inherited
	# PD_F_n from this shell (a nested dispatch, a stale export) would otherwise
	# make a plain --set read a file. --set-file sets it after this returns.
	eval "PD_K_$SETS_N=\$1; PD_V_$SETS_N=\$2; PD_F_$SETS_N="
	eval "export PD_K_$SETS_N PD_V_$SETS_N PD_F_$SETS_N"
}

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
	--set)
		[ $# -ge 2 ] || die "--set needs NAME=VALUE"
		case "$2" in
		*=*) ;;
		*) die "--set takes NAME=VALUE, got '$2'" ;;
		esac
		_record_set "${2%%=*}" "${2#*=}"
		shift 2
		;;
	--set-file)
		# The value too large for argv: a --set value is one argv element, so a
		# big diff hits the exec ceiling. The file's bytes become the value,
		# whole, read the same way the inline form's are — through the
		# environment into the one awk pass — so a newline, a %%marker%% or a
		# pipe inside a diff is as safe here as there.
		[ $# -ge 2 ] || die "--set-file needs NAME=path"
		case "$2" in
		*=*) ;;
		*) die "--set-file takes NAME=path, got '$2'" ;;
		esac
		_sf_path=${2#*=}
		[ -e "$_sf_path" ] || die "--set-file path does not exist: $_sf_path"
		[ -d "$_sf_path" ] && die "--set-file path is a directory: $_sf_path"
		[ -r "$_sf_path" ] || die "--set-file path is not readable: $_sf_path"
		# The PATH is recorded, not the file's bytes: a megabyte in an
		# environment variable hits ARG_MAX at the worker's own exec just as it
		# would on argv. awk reads the file itself in the pass below, so nothing
		# large ever crosses an exec boundary.
		_record_set "${2%%=*}" ""
		eval "PD_F_$SETS_N=\$_sf_path; export PD_F_$SETS_N"
		shift 2
		;;
	--timeout)
		[ $# -ge 2 ] || die "--timeout needs a number of seconds"
		case "$2" in
		'' | *[!0123456789]*) die "--timeout takes a whole number of seconds, got '$2'" ;;
		0 | 0*) die "--timeout 0 is not a timeout. Omit the flag to run without one." ;;
		esac
		TIMEOUT=$2
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

# --- the depth ---------------------------------------------------------------
# Before the tier is resolved and before the prompt is read: a dispatch that
# may not nest has nothing else worth checking, and in the runaway case every
# process spent past this point is one the host has lost. The default is the
# deepest legitimate shape today: a planner that dispatches implementers that
# dispatch reviewers, three deep. It is a ceiling on runaway nesting, not a
# budget, and the policy file raises it.
DEPTH_DEFAULT_MAX=3
DEPTH=${AGENT_DISPATCH_DEPTH:-1}
_whole_from_one "$DEPTH" || die "AGENT_DISPATCH_DEPTH must be a whole number from 1 (at most $DEPTH_MAX_DIGITS digits), got '$DEPTH'.
   It is set by the dispatcher that spawned this worker; unset or empty means depth 1."
MAX_DEPTH=$(_read_policy AGENT_DISPATCH_MAX_DEPTH)
[ -n "$MAX_DEPTH" ] || MAX_DEPTH=$DEPTH_DEFAULT_MAX
_whole_from_one "$MAX_DEPTH" || die "AGENT_DISPATCH_MAX_DEPTH must be a whole number from 1 (at most $DEPTH_MAX_DIGITS digits), got '$MAX_DEPTH'.
   Empty means the kit default of $DEPTH_DEFAULT_MAX."
if [ "$DEPTH" -gt "$MAX_DEPTH" ]; then
	# Read, more often than not, by the refused WORKER — a model with tools —
	# so this says what a worker does with it and never how to lift the
	# ceiling. The maximum is named by its variable, not by a path: the policy
	# file is wherever AGENTS_CONFIG resolved it, which need not be the default.
	echo "x dispatch: refusing to nest — this dispatch would run at depth $DEPTH and the maximum is $MAX_DEPTH." >&2
	echo "   The maximum is AGENT_DISPATCH_MAX_DEPTH in the agents policy file, and it is the" >&2
	echo "   operator's to change. A worker that sees this must stop and report it." >&2
	exit 4
fi

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

# --- the editor's header ----------------------------------------------------
# A prompt template opens with an HTML comment addressed to whoever EDITS it:
# which markers exist, why the file is shaped the way it is. Every template in
# .agents/prompts/ ends that header with "everything below is sent to the model
# verbatim", and this step is what makes the sentence true.
#
# Stripping it is not cosmetic. The header documents the markers BY WRITING
# THEM, so substituting first rewrites the documentation into nonsense and
# sends it as the worker's opening instruction.
#
# Only a header at the very TOP goes, and only through the first `-->`. A
# comment further down is content: a prompt may legitimately show markup.
if [ "$(head -n 1 "$PROMPT_FILE" 2>/dev/null)" = "<!--" ]; then
	# The terminator is a line that IS `-->`, not a line that CONTAINS one.
	# Matching anywhere closed the header early on any `-->` inside it — a
	# fenced example, or prose — and the rest of the header was then filled and
	# sent as the worker's opening instruction, which is the exact outcome
	# stripping before substituting exists to prevent.
	#
	# An UNTERMINATED header is not stripped at all. Dropping to end-of-file
	# left a zero-byte prompt, and the emptiness check runs before this point,
	# so the worker was exec'd with nothing to do and exited 0.
	# awk's status is read on its OWN, not through a pipeline: the exit status
	# of `awk … | sed …` is SED's, so the unterminated-header branch below
	# never ran and the empty prompt went out anyway. Found by testing the
	# branch rather than by reading it.
	if awk 'NR==1 && $0=="<!--" { inhdr=1; next }
	        inhdr { if ($0 == "-->") { inhdr=0; seen=1 } ; next }
	        { print }
	        END { exit(seen ? 0 : 1) }' "$PROMPT_FILE" >"$SCRATCH/header-stripped.md"; then
		sed '/./,$!d' "$SCRATCH/header-stripped.md" >"$SCRATCH/stripped.md" &&
			mv "$SCRATCH/stripped.md" "$PROMPT_FILE"
		rm -f "$SCRATCH/header-stripped.md"
	else
		rm -f "$SCRATCH/header-stripped.md" "$SCRATCH/stripped.md"
		echo "!  dispatch: the prompt opens with '<!--' and never closes it on a line of" >&2
		echo "   its own. Leaving the header in rather than sending an empty prompt." >&2
	fi
	[ -s "$PROMPT_FILE" ] || die "the prompt is empty after its editor header was stripped.
   A worker given nothing to do will invent something to do."
fi

# --- marker substitution ----------------------------------------------------
# `%%NAME%%`, filled by --set. The syntax and the reasoning are
# templates/workflows/ai-review-prompt.md's, which explains why the markers are
# not any agent harness's own expression syntax: an expression inside a data
# file is never expanded, because it is evaluated by whatever READS the file.
# The reading step does the substitution — there, the workflow; here, this
# script.
#
# The prompt was already staged into a file this script created, so filling it
# in place cannot touch the caller's template. That matters: a template is read
# many times with different values, and a dispatcher that consumed its own
# input would work exactly once.
if [ "$SETS_N" -gt 0 ]; then
	# ONE pass over the file, scanning each line left to right and splicing the
	# first marker that matches at the current position. Two things follow from
	# that shape, and both were bugs in the per-pair version it replaced:
	#
	#   - a value is never re-scanned, so `--set 'A=[%%B%%]' --set B=bee` leaves
	#     `[%%B%%]` whatever order the pairs arrive in. A value is data, not a
	#     template, and reading it as one made the result order-dependent.
	#   - an inline value comes from the environment and a --set-file value is
	#     read from its file here, so a newline in either is just a character
	#     and a value too large for argv never crosses an exec.
	PD_N=$SETS_N
	export PD_N
	awk '
		BEGIN {
			n = ENVIRON["PD_N"] + 0
			for (i = 1; i <= n; i++) {
				k[i] = "%%" ENVIRON["PD_K_" i] "%%"
				kl[i] = length(k[i])
				path = ENVIRON["PD_F_" i]
				if (path != "") {
					# A --set-file value: read the file whole, here, so it never
					# crosses an exec. getline drops each line separator and this
					# rejoins with a newline, so a file with no trailing newline
					# gains one; a diff always ends with one, which is the case
					# this exists for.
					# A SCALAR accumulator, assigned to the array once at the
					# end: appending to an array element defeats the
					# in-place string-growth optimisation and made this
					# quadratic in the line count — 8 MiB took eighteen
					# seconds. A scalar does it in milliseconds.
					s = ""
					while ((getline ln < path) > 0) s = s ln "\n"
					close(path)
					v[i] = s
				} else {
					v[i] = ENVIRON["PD_V_" i]
				}
			}
		}
		{
			line = $0; out = ""; pos = 1; len = length(line)
			while (pos <= len) {
				hit = 0
				for (i = 1; i <= n; i++) {
					if (substr(line, pos, kl[i]) == k[i]) {
						out = out v[i]; pos += kl[i]; hit = 1; break
					}
				}
				if (!hit) { out = out substr(line, pos, 1); pos++ }
			}
			print out
		}
	' "$PROMPT_FILE" >"$PROMPT_FILE.tmp" ||
		die "substituting markers failed — a --set-file may be unreadable or too large for memory"
	mv "$PROMPT_FILE.tmp" "$PROMPT_FILE"
fi

# An unfilled marker is a caller that forgot one, and it reaches the worker as
# literal `%%TICKET%%` — which the worker will cheerfully reason about. Say so;
# do not refuse, because a prompt may legitimately discuss the syntax itself.
if grep -q '%%[A-Za-z_][A-Za-z0-9_]*%%' "$PROMPT_FILE" 2>/dev/null; then
	echo "!  dispatch: the prompt still carries unfilled markers:" >&2
	grep -o '%%[A-Za-z_][A-Za-z0-9_]*%%' "$PROMPT_FILE" | sort -u | sed 's/^/     /' >&2
fi

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
	printf 'depth:          %s of %s\n' "$DEPTH" "$MAX_DEPTH"
	[ -n "$TIMEOUT" ] && printf 'timeout:        %ss\n' "$TIMEOUT"
	printf '\n--- prompt (%s bytes) ---\n' "$(wc -c <"$PROMPT_FILE" | tr -d ' ')"
	cat "$PROMPT_FILE"
	printf '\n--- end prompt ---\n'
	exit 0
fi

echo "i  dispatch: tier '$TIER' -> agent harness '$HARNESS', model '${MODEL:-<default>}'" >&2
# The worker runs one level deeper than this dispatch, and a dispatch it runs
# reads that on entry. Exported here, above both spawn paths, so the plain
# eval and the timed `sh -c` cannot disagree about it.
AGENT_DISPATCH_DEPTH=$((DEPTH + 1))
export AGENT_DISPATCH_DEPTH
# The worker never inherits this script's stdin. Found live: an agent CLI that
# reads stdin when it is not a tty blocked forever on the dispatcher's own
# inherited pipe, and a dispatch that took fourteen seconds with </dev/null on
# the dispatcher hung indefinitely without it. The prompt reaches the worker by
# {prompt_file}, so it has no legitimate use for the parent's stdin: a template
# that redirects `< {prompt_file}` still gets it — a redirect inside the
# eval'd command wins over this outer one — and a template that does not gets
# nothing, which is what it would have got from a terminal that had moved on.
if [ -z "$TIMEOUT" ]; then
	eval "$CMD" </dev/null
	exit $?
fi

# --- with a timeout ---------------------------------------------------------
# Headless agent CLIs gate tool calls on approvals, and headless there is no
# human: a reviewer told to run `git diff` in an approval-gated mode waits
# forever. Found live; only an external timeout ended it. The kit writes no
# autonomy flags — that posture is the operator's — but a dispatch that can
# never return is a different thing from one that returns a refusal.
#
# Four things the first version of this got wrong, each found by review:
#
#   1. The worker's process TREE is snapshotted ONCE, before any signal, and
#      that same list is signalled twice — TERM, a grace, then KILL. Walking
#      the tree after TERM found nothing, because a killed parent's children
#      are reparented to init and no longer under the worker's pid; a worker
#      that ignored TERM therefore ran to completion while this script said
#      "killed". An agent CLI is a node or python process under a shell, and
#      the shell dying is not the CLI dying.
#   2. The verdict is a FLAG the watchdog writes before it signals, not an
#      inference from the worker's exit status. Reading 143 as "timed out"
#      was wrong both ways: a worker that trapped TERM and exited 0 reported
#      success with "timed out" on stderr, and a worker that killed itself
#      reported a timeout with no message.
#   3. The watchdog is killed WITH its sleep. Killing the subshell alone left
#      `sleep N` holding this script's stdout, so any caller capturing output
#      waited the whole timeout after a worker that finished in a second.
#   4. This script traps its own INT/TERM/HUP and takes the worker and the
#      watchdog down with it. Backgrounded children of a non-interactive
#      shell start with SIGINT ignored, so a Ctrl-C on the dispatcher used to
#      leave the worker running with no timeout left.
#
# setsid would give one process group to signal but is not POSIX; walking
# `ps -A -o pid= -o ppid=` is.
_tree_of() {
	# Every descendant of $1, deepest last, then $1 itself — so TERM reaches
	# the leaves before their parents and a parent cannot respawn a child
	# that was already signalled.
	_to_kids=$(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$1" '$2 == p { print $1 }')
	for _to_k in $_to_kids; do _tree_of "$_to_k"; done
	printf '%s\n' "$1"
}
_signal_list() {
	# $1 signal, rest pids. Failures are expected — a pid may be gone already.
	_sl_sig=$1
	shift
	for _sl_p in "$@"; do kill "-$_sl_sig" "$_sl_p" 2>/dev/null; done
}
_down() {
	# Take the worker's tree and the watchdog down. Idempotent; safe to call
	# from the trap and from the normal path both.
	[ -n "${_worker:-}" ] && _signal_list TERM $(_tree_of "$_worker")
	[ -n "${_watchdog:-}" ] && _signal_list TERM $(_tree_of "$_watchdog")
}
TIMED_OUT="$SCRATCH/timed-out"
# The scratch cleanup trap from earlier is extended, not replaced: on a
# signal, the worker and the watchdog go first, then the scratch, then the
# conventional 128+n.
trap '_down; cleanup; exit 130' INT
trap '_down; cleanup; exit 143' TERM
trap '_down; cleanup; exit 129' HUP

sh -c "$CMD" </dev/null &
_worker=$!
(
	sleep "$TIMEOUT" &
	_wd_sleep=$!
	# The watchdog dies with its sleep: a TERM here forwards to the sleep, so
	# reaping the watchdog never leaves a sleeper holding the caller's stdout.
	trap 'kill "$_wd_sleep" 2>/dev/null; exit 0' TERM
	wait "$_wd_sleep" || exit 0
	# Verdict first, then the snapshot, then the signals — in that order, so a
	# worker that dies from TERM on line one of its handler still reads as a
	# timeout, and a child reparented by its parent's death is still on the
	# list it is about to be sent.
	: >"$TIMED_OUT"
	echo "!  dispatch: worker timed out after ${TIMEOUT}s — killing its process tree" >&2
	_wd_list=$(_tree_of "$_worker")
	_signal_list TERM $_wd_list
	sleep 1
	_signal_list KILL $_wd_list
) &
_watchdog=$!
wait "$_worker" 2>/dev/null
_status=$?
if [ -f "$TIMED_OUT" ]; then
	# The watchdog fired: let it finish its KILL pass rather than racing it.
	wait "$_watchdog" 2>/dev/null
	exit 124
fi
# The worker finished in time. The watchdog and its sleep go together.
kill -TERM "$_watchdog" 2>/dev/null
wait "$_watchdog" 2>/dev/null
exit "$_status"
