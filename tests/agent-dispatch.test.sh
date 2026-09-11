#!/bin/sh
# tests/agent-dispatch.test.sh — running a capability tier on another agent harness.
#
# The suite drives a STUB AGENT HARNESS: a script that prints its argv and its
# stdin and exits. That is deliberate and it is the only honest way to test
# this file. A real vendor would make the suite depend on an account, a
# network, a model's mood and a bill — none of which are properties of the
# dispatcher — and it would be testing the vendor rather than the wiring. What
# this file is responsible for is which command got built, what reached it, and
# what happened when something was wrong. A stub answers all three exactly.
#
# THE CASE THAT MATTERS MOST IS EXIT 3. An unconfigured project declares no
# agent harness, every tier is in-session, and the dispatcher must hand the
# caller the model id and get out of the way — the behaviour the kit had before
# this file existed. A dispatcher that treated "no agent harness" as an error
# would break every project that never asked for one.
#
# THE CASE THAT MATTERS SECOND IS THE MODEL WHITELIST. The command template is
# eval'd, so a model id is interpolated into a string that is then executed. An
# id carrying a semicolon is a command, and the suite plants one.
#
# Usage: sh tests/agent-dispatch.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
DISPATCH="$KIT/scripts/agent-dispatch.sh"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

STUB="$SCRATCH/stub-agent-harness"
cat >"$STUB" <<'EOF'
#!/bin/sh
echo "ARGV: $*"
echo "STDIN-BEGIN"
cat
echo "STDIN-END"
EOF
chmod +x "$STUB"

CFG="$SCRATCH/agents.config.sh"
cat >"$CFG" <<EOF
AGENT_HARNESSES='stub other'
AGENT_HARNESS_STUB_CMD='$STUB --flag {model_flag} < {prompt_file}'
AGENT_HARNESS_STUB_MODEL_FLAG='--model {model}'
AGENT_TIER_IMPLEMENTER='stub:model-for-implementing'
AGENT_TIER_IMPLEMENTER_CONTENT='stub:model-for-prose'
AGENT_TIER_PLANNER='model-for-planning'
AGENT_TIER_REVIEWER='other:model-for-reviewing'
AGENT_TIER_MECHANICAL='stub:bad;id'
EOF
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

dispatch() {
	D_ERR=$(mktemp "$SCRATCH/err.XXXXXX")
	D_OUT=$(sh "$DISPATCH" "$@" 2>"$D_ERR")
	D_STATUS=$?
	D_ERR_TEXT=$(cat "$D_ERR")
	rm -f "$D_ERR"
}

assert_status_is() {
	if [ "$D_STATUS" = "$1" ]; then
		pass "$2"
	else
		fail "$2 — expected status $1, got $D_STATUS"
		printf '%s\n' "$D_OUT" | sed 's/^/        > /'
		printf '%s\n' "$D_ERR_TEXT" | sed 's/^/        | /'
	fi
}

assert_out_matches() {
	case "$D_OUT" in
	*"$1"*) pass "$2" ;;
	*)
		fail "$2 — stdout lacks '$1'"
		printf '%s\n' "$D_OUT" | sed 's/^/        > /'
		;;
	esac
}

assert_out_exact() {
	if [ "$D_OUT" = "$1" ]; then
		pass "$2"
	else
		fail "$2 — expected exactly '$1', got '$D_OUT'"
	fi
}

assert_out_lacks() {
	case "$D_OUT" in
	*"$1"*)
		fail "$2 — stdout should NOT contain '$1'"
		printf '%s\n' "$D_OUT" | sed 's/^/        > /'
		;;
	*) pass "$2" ;;
	esac
}

assert_err_has() {
	case "$D_ERR_TEXT" in
	*"$1"*) pass "stderr mentions '$1'" ;;
	*)
		fail "stderr does not mention '$1'"
		printf '%s\n' "$D_ERR_TEXT" | sed 's/^/        | /'
		;;
	esac
}

# ---------------------------------------------------------------------------
banner "The in-session case — the default, and not a failure"
# ---------------------------------------------------------------------------
dispatch planner --prompt 'anything'
assert_status_is 3 "a tier naming no agent harness exits 3 — 'spawn this yourself'"
assert_out_exact 'model-for-planning' "…and hands the caller the model id, on stdout, alone"
assert_err_has "names no agent harness"

# ---------------------------------------------------------------------------
banner "Dispatching — what the worker actually receives"
# ---------------------------------------------------------------------------
dispatch implementer --prompt 'Implement ticket #7.'
assert_status_is 0 "a mapped agent harness dispatches"
assert_out_matches 'ARGV: --flag --model model-for-implementing' "the model lands where the flag template put it"
assert_out_matches 'Implement ticket #7.' "the prompt reaches the worker"

# Prose carries quotes, dollars, newlines and code fences, and every one of them
# would be interpreted on the way if the prompt were an argv element. The claim
# is byte-identical arrival, and only a diff can state it: the hazardous text is
# IN the prompt, so every token in it legitimately appears in the worker's echo,
# and a substring check cannot tell "quoted safely" from "executed".
HAZARD="$SCRATCH/hazard.md"
cat >"$HAZARD" <<'EOF'
Line one with "double" and 'single' quotes.
$HOME `date` $(echo hi) ; rm -rf / && echo pwned
```sh
echo "a fenced block"
```
EOF
dispatch implementer --prompt-file "$HAZARD"
assert_status_is 0 "a prompt full of shell metacharacters dispatches"
printf '%s\n' "$D_OUT" | sed -n '/^STDIN-BEGIN$/,/^STDIN-END$/p' | sed '1d;$d' >"$SCRATCH/received.md"
if diff -q "$HAZARD" "$SCRATCH/received.md" >/dev/null 2>&1; then
	pass "the prompt reaches the worker byte-identical — nothing expanded, nothing eaten"
else
	fail "the prompt was altered in transit"
	diff "$HAZARD" "$SCRATCH/received.md" | sed 's/^/        | /'
fi

dispatch implementer content --prompt 'x' --dry-run
assert_out_matches 'model-for-prose' "the task domain selects its own model"

# ---------------------------------------------------------------------------
banner "An agent harness with no model omits the flag entirely"
# ---------------------------------------------------------------------------
# adapters/claude-code/README.md's rule: omitting a parameter and passing "" are
# not the same request, and a harness is within its rights to reject the second.
# `{model_flag}` is that rule made declarative.
CFG2="$SCRATCH/nomodel.config.sh"
cat >"$CFG2" <<EOF
AGENT_HARNESSES='stub'
AGENT_HARNESS_STUB_CMD='$STUB --flag {model_flag} < {prompt_file}'
AGENT_HARNESS_STUB_MODEL_FLAG='--model {model}'
AGENT_TIER_REVIEWER='stub:'
EOF
AGENTS_CONFIG="$CFG2"
export AGENTS_CONFIG
dispatch reviewer --prompt 'x'
assert_status_is 0 "a tier naming an agent harness with no model still dispatches"
assert_out_matches 'ARGV: --flag' "…and the worker runs"
assert_out_lacks '--model' "…with the model flag omitted entirely, not passed empty"

AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

# ---------------------------------------------------------------------------
banner "--dry-run runs nothing and shows everything"
# ---------------------------------------------------------------------------
dispatch implementer --prompt 'Do not run me.' --dry-run
assert_status_is 0 "a dry run succeeds"
assert_out_matches 'agent harness:  stub' "it names the agent harness"
assert_out_matches 'model:          model-for-implementing' "it names the model"
assert_out_matches '--model model-for-implementing' "it shows the expanded command"
assert_out_matches 'Do not run me.' "it shows the prompt"
assert_out_lacks 'ARGV:' "and the worker never ran"

# ---------------------------------------------------------------------------
banner "Markers, and the header that documents them"
# ---------------------------------------------------------------------------
# A template's header documents its markers BY WRITING THEM, so a dispatcher
# that substituted before stripping would rewrite the documentation into
# nonsense and send it as the worker's opening instruction. Strip, then fill.
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

TPL="$SCRATCH/template.md"
cat >"$TPL" <<'EOF'
<!--
EDITOR NOTE: the markers are %%TICKET%% and %%BODY%%.
Everything below is sent to the model verbatim.
-->

Implement %%TICKET%%.
%%BODY%%
Again: %%TICKET%%. And %%NEVER_SET%% stays.
EOF

dispatch implementer --prompt-file "$TPL" --set 'TICKET=#42' \
	--set 'BODY=has "quotes", $(echo NOPE), a|pipe and a\backslash'
assert_status_is 0 "a template with a header and markers dispatches"
assert_out_lacks 'EDITOR NOTE' "the editor's header never reaches the worker"
assert_out_matches 'Implement #42.' "a marker is filled"
assert_out_matches 'Again: #42.' "…every occurrence of it, not just the first"
assert_out_matches '$(echo NOPE)' "a value carrying shell syntax is INSERTED, not executed"
assert_out_matches 'a|pipe' "…and cannot close the substitution expression"
assert_out_matches '%%NEVER_SET%%' "an unfilled marker is left alone rather than emptied"
assert_err_has "unfilled marker"

if grep -q '%%TICKET%%' "$TPL"; then
	pass "the template file itself is untouched — it is read many times"
else
	fail "the template was consumed: substitution wrote back into the caller's file"
fi

dispatch implementer --prompt 'no header here' --dry-run
assert_out_matches 'no header here' "a prompt with no header passes through whole"

dispatch implementer --prompt 'x' --set 'NOT_A_PAIR'
assert_status_is 2 "--set without NAME=VALUE is refused"

# ---------------------------------------------------------------------------
banner "The shipped worker prompts"
# ---------------------------------------------------------------------------
# One file per task kind, never one per provider: asking two vendors different
# questions measures the prompts rather than the models, and two files that
# must stay byte-identical eventually are not.
for wp in implement-worker review-worker; do
	f="$KIT/.agents/prompts/$wp.md"
	[ -f "$f" ] && pass "$wp.md ships" || { fail "$wp.md is missing"; continue; }
	head -n 1 "$f" | grep -q '^<!--' &&
		pass "$wp.md opens with an editor header the dispatcher strips" ||
		fail "$wp.md has no editor header"
	grep -q '%%' "$f" &&
		pass "$wp.md carries markers" ||
		fail "$wp.md carries no markers"
	# Shared invariant §7 is not the dispatcher's to enforce, so it has to be
	# in the words the worker actually reads.
	grep -qi 'do not push' "$f" && grep -qi 'merge' "$f" &&
		pass "$wp.md forbids pushing and merging in so many words" ||
		fail "$wp.md does not forbid push/merge — §7 lives in the prompt or nowhere"
done

# Every marker a shipped prompt declares must be fillable, and the dispatcher
# reports any that are not — so a prompt naming a marker nobody documents is
# caught here rather than by a confused worker.
for wp in implement-worker review-worker; do
	f="$KIT/.agents/prompts/$wp.md"
	[ -f "$f" ] || continue
	sets=""
	for m in $(grep -o '%%[A-Z_][A-Z0-9_]*%%' "$f" | sort -u | tr -d '%'); do
		sets="$sets --set $m=filled-$m"
	done
	# shellcheck disable=SC2086
	dispatch implementer --prompt-file "$f" $sets --dry-run
	assert_status_is 0 "$wp.md dispatches with every marker filled"
	case "$D_ERR_TEXT" in
	*"unfilled marker"*) fail "$wp.md left a marker unfilled after filling all of them" ;;
	*) pass "$wp.md has no marker the caller cannot fill" ;;
	esac
done

# ---------------------------------------------------------------------------
banner "Misconfiguration reports itself, and points at the fix"
# ---------------------------------------------------------------------------
dispatch reviewer --prompt 'x'
assert_status_is 2 "an agent harness named without a command template is refused"
assert_err_has "AGENT_HARNESS_OTHER_CMD"

dispatch mechanical --prompt 'x'
assert_status_is 2 "a model id carrying a shell metacharacter is REFUSED, not escaped"
assert_err_has "will not interpolate"

dispatch not-a-tier --prompt 'x'
assert_status_is 2 "the closed tier vocabulary still closes"

dispatch implementer --nonsense --prompt 'x'
assert_status_is 2 "an unknown option is refused rather than read as a tier"
assert_err_has "unknown option"

dispatch implementer
assert_status_is 2 "no prompt at all is a usage error"

dispatch implementer --prompt-file "$SCRATCH/does-not-exist.md"
assert_status_is 2 "a missing prompt file is refused before anything runs"

CFG3="$SCRATCH/ghost.config.sh"
cat >"$CFG3" <<'EOF'
AGENT_HARNESSES='ghost'
AGENT_HARNESS_GHOST_CMD='definitely-not-a-real-binary-9f3a {model_flag} < {prompt_file}'
AGENT_HARNESS_GHOST_MODEL_FLAG='--model {model}'
AGENT_TIER_IMPLEMENTER='ghost:some-id'
EOF
AGENTS_CONFIG="$CFG3"
export AGENTS_CONFIG
dispatch implementer --prompt 'x'
assert_status_is 2 "an uninstalled agent harness is caught before it is invoked"
assert_err_has "not on PATH"

# ---------------------------------------------------------------------------
banner "The prompt path is data, and is treated as such"
# ---------------------------------------------------------------------------
# The caller's path is not this script's to trust: a branch name becomes a
# worktree slug becomes a directory, and `;` `$` `(` `&` `|` and spaces are all
# legal in a branch name. This path is interpolated into the eval'd template,
# and passing it through unstaged EXECUTED it.
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

HOSTILE="$SCRATCH/a;\$(touch $SCRATCH/PWNED)b"
mkdir -p "$HOSTILE"
printf 'the prompt survives\n' >"$HOSTILE/p.md"
dispatch implementer --prompt-file "$HOSTILE/p.md"
assert_status_is 0 "a prompt under a hostile directory name dispatches"
if [ -f "$SCRATCH/PWNED" ]; then
	fail "the prompt path was EXECUTED — command substitution in a path reached the eval"
	rm -f "$SCRATCH/PWNED"
else
	pass "the prompt path was not executed"
fi
assert_out_matches 'the prompt survives' "…and the prompt still reached the worker"

SPACED="$SCRATCH/with space"
mkdir -p "$SPACED"
printf 'spaces are fine\n' >"$SPACED/p.md"
dispatch implementer --prompt-file "$SPACED/p.md"
assert_status_is 0 "a path containing a space dispatches"
assert_out_matches 'spaces are fine' "…and arrives whole, not split at the space"

# $TMPDIR is somebody else's data too, so staging alone is not the fix.
D_ERR=$(mktemp "$SCRATCH/err.XXXXXX")
mkdir -p "$SCRATCH/tmp;x"
TMPDIR="$SCRATCH/tmp;x" sh "$DISPATCH" implementer --prompt 'hi' >/dev/null 2>"$D_ERR"
D_STATUS=$?
D_ERR_TEXT=$(cat "$D_ERR")
rm -f "$D_ERR"
assert_status_is 2 "a TMPDIR this script cannot safely interpolate is refused, not escaped"

dispatch implementer --prompt-file /dev/null
assert_status_is 2 "an empty prompt file is refused — a worker given nothing invents something"

# ---------------------------------------------------------------------------
banner "The worker's own status, and a template that sets the environment"
# ---------------------------------------------------------------------------
EXITER="$SCRATCH/exiter"
cat >"$EXITER" <<'EOF'
#!/bin/sh
cat >/dev/null
echo "MARKER=${MARKER:-unset}"
exit 7
EOF
chmod +x "$EXITER"
CFG_EXIT="$SCRATCH/exit.config.sh"
cat >"$CFG_EXIT" <<EOF
AGENT_HARNESSES='ex'
AGENT_HARNESS_EX_CMD='MARKER=set $EXITER {model_flag} < {prompt_file}'
AGENT_HARNESS_EX_MODEL_FLAG='--model {model}'
AGENT_TIER_IMPLEMENTER='ex:some-id'
EOF
AGENTS_CONFIG="$CFG_EXIT"
export AGENTS_CONFIG
dispatch implementer --prompt 'x'
assert_status_is 7 "the worker's own exit status passes through untouched"
assert_out_matches 'MARKER=set' "a template may set the environment the worker runs in"

# A mapped model with nowhere to put it is a config error, not a silent drop.
CFG_NOFLAG="$SCRATCH/noflag.config.sh"
cat >"$CFG_NOFLAG" <<EOF
AGENT_HARNESSES='ex'
AGENT_HARNESS_EX_CMD='$EXITER {model_flag} < {prompt_file}'
AGENT_TIER_IMPLEMENTER='ex:some-id'
EOF
AGENTS_CONFIG="$CFG_NOFLAG"
export AGENTS_CONFIG
dispatch implementer --prompt 'x'
assert_status_is 2 "a mapped model with no MODEL_FLAG is refused rather than dropped"
assert_err_has "MODEL_FLAG"

# ---------------------------------------------------------------------------
banner "Every shell an operator might run this under"
# ---------------------------------------------------------------------------
# The file claims three-shell portability in a comment; a comment is not a
# check. sh on this machine may BE bash, so naming them separately is the point.
SHELLS='sh bash zsh'
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG
for shell_bin in $SHELLS; do
	command -v "$shell_bin" >/dev/null 2>&1 || {
		pass "$shell_bin is not installed — skipped, and says so"
		continue
	}
	"$shell_bin" -n "$DISPATCH" 2>/dev/null &&
		pass "$shell_bin parses agent-dispatch.sh" ||
		fail "$shell_bin cannot parse agent-dispatch.sh"
	s_out=$("$shell_bin" "$DISPATCH" implementer --prompt 'shell check' 2>/dev/null)
	case "$s_out" in
	*"shell check"*) pass "$shell_bin dispatches, and the prompt arrives" ;;
	*) fail "$shell_bin dispatched wrongly: $s_out" ;;
	esac
	# The case every consumer in the field is in.
	s_out=$("$shell_bin" "$DISPATCH" planner --prompt 'x' 2>/dev/null)
	s_st=$?
	{ [ "$s_st" = 3 ] && [ "$s_out" = "model-for-planning" ]; } &&
		pass "$shell_bin exits 3 with the model id for an unconfigured tier" ||
		fail "$shell_bin gave status $s_st, stdout '$s_out'"
done

unset AGENTS_CONFIG
t_done "agent dispatch"
