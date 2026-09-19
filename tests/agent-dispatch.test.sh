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

# dispatch <args> — the dispatcher, streams kept apart (t_run_split in
# tests/lib.sh owns why).
dispatch() { t_run_split sh "$DISPATCH" "$@"; }







# ---------------------------------------------------------------------------
banner "The in-session case — the default, and not a failure"
# ---------------------------------------------------------------------------
dispatch planner --prompt 'anything'
s_assert_status 3 "a tier naming no agent harness exits 3 — 'spawn this yourself'"
s_assert_out_is 'model-for-planning' "…and hands the caller the model id, on stdout, alone"
s_assert_err_has "names no agent harness"

# ---------------------------------------------------------------------------
banner "Dispatching — what the worker actually receives"
# ---------------------------------------------------------------------------
dispatch implementer --prompt 'Implement ticket #7.'
s_assert_status 0 "a mapped agent harness dispatches"
s_assert_out_has 'ARGV: --flag --model model-for-implementing' "the model lands where the flag template put it"
s_assert_out_has 'Implement ticket #7.' "the prompt reaches the worker"

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
s_assert_status 0 "a prompt full of shell metacharacters dispatches"
printf '%s\n' "$S_OUT" | sed -n '/^STDIN-BEGIN$/,/^STDIN-END$/p' | sed '1d;$d' >"$SCRATCH/received.md"
if diff -q "$HAZARD" "$SCRATCH/received.md" >/dev/null 2>&1; then
	pass "the prompt reaches the worker byte-identical — nothing expanded, nothing eaten"
else
	fail "the prompt was altered in transit"
	diff "$HAZARD" "$SCRATCH/received.md" | sed 's/^/        | /'
fi

dispatch implementer content --prompt 'x' --dry-run
s_assert_out_has 'model-for-prose' "the task domain selects its own model"

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
s_assert_status 0 "a tier naming an agent harness with no model still dispatches"
s_assert_out_has 'ARGV: --flag' "…and the worker runs"
s_assert_out_lacks '--model' "…with the model flag omitted entirely, not passed empty"

AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

# ---------------------------------------------------------------------------
banner "--dry-run runs nothing and shows everything"
# ---------------------------------------------------------------------------
dispatch implementer --prompt 'Do not run me.' --dry-run
s_assert_status 0 "a dry run succeeds"
s_assert_out_has 'agent harness:  stub' "it names the agent harness"
s_assert_out_has 'model:          model-for-implementing' "it names the model"
s_assert_out_has '--model model-for-implementing' "it shows the expanded command"
s_assert_out_has 'Do not run me.' "it shows the prompt"
s_assert_out_lacks 'ARGV:' "and the worker never ran"

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
s_assert_status 0 "a template with a header and markers dispatches"
s_assert_out_lacks 'EDITOR NOTE' "the editor's header never reaches the worker"
s_assert_out_has 'Implement #42.' "a marker is filled"
s_assert_out_has 'Again: #42.' "…every occurrence of it, not just the first"
s_assert_out_has '$(echo NOPE)' "a value carrying shell syntax is INSERTED, not executed"
s_assert_out_has 'a|pipe' "…and cannot close the substitution expression"
s_assert_out_has '%%NEVER_SET%%' "an unfilled marker is left alone rather than emptied"
s_assert_err_has "unfilled marker"

if grep -q '%%TICKET%%' "$TPL"; then
	pass "the template file itself is untouched — it is read many times"
else
	fail "the template was consumed: substitution wrote back into the caller's file"
fi

dispatch implementer --prompt 'no header here' --dry-run
s_assert_out_has 'no header here' "a prompt with no header passes through whole"

dispatch implementer --prompt 'x' --set 'NOT_A_PAIR'
s_assert_status 2 "--set without NAME=VALUE is refused"

# --set-file NAME=path — for a value too large for argv. A --set value is one
# argv element, so a big diff hits the exec ceiling (~128 KiB single arg on
# Linux); the ticket names "a diff" as a value, so the limit is reachable by
# the intended use. The file's bytes become the value, whole.
BIG="$SCRATCH/big-value"
# A megabyte, well past the argv ceiling, with the hazards --set already handles.
awk 'BEGIN { for (i = 0; i < 20000; i++) print "line " i " with $(echo x) and %%B%% and | pipe" }' >"$BIG"
printf 'Diff follows:\n%%%%DIFF%%%%\nend\n' >"$SCRATCH/df.md"
dispatch implementer --prompt-file "$SCRATCH/df.md" --set-file "DIFF=$BIG" --set 'B=bee'
s_assert_status 0 "a value of a megabyte is delivered from a file"
s_assert_out_has "line 19999 with" "…whole, to the last line"
s_assert_out_has 'line 0 with $(echo x) and %%B%% and | pipe' "…unexpanded, and a marker inside it is not re-scanned"

# --set and --set-file mix, and order is preserved.
printf 'A is %%%%A%%%%\nF is %%%%F%%%%\n' >"$SCRATCH/mix.md"
printf 'from-a-file\n' >"$SCRATCH/fval"
dispatch implementer --prompt-file "$SCRATCH/mix.md" --set 'A=inline' --set-file "F=$SCRATCH/fval"
s_assert_out_has "A is inline" "--set fills its marker when composed with --set-file"
s_assert_out_has "F is from-a-file" "…and --set-file fills its own from the file"

dispatch implementer --prompt 'x' --set-file 'F=/no/such/file/here'
s_assert_status 2 "--set-file with a missing path is refused before anything runs"

dispatch implementer --prompt 'x' --set-file 'NOPAIR'
s_assert_status 2 "--set-file without NAME=path is refused"

dispatch implementer --prompt 'x' --set-file "1bad=$BIG"
s_assert_status 2 "--set-file NAME is shape-checked like --set"

# An unreadable file that exists is refused before dispatch, not substituted as
# empty (which would send the worker a prompt with a hole in it and exit 0).
UNREAD="$SCRATCH/unreadable"
printf 'secret\n' >"$UNREAD"
chmod 000 "$UNREAD"
dispatch implementer --prompt 'x' --set-file "V=$UNREAD"
# root reads anything, so a chmod-000 file is only a real test as non-root.
if [ "$(id -u)" = 0 ]; then
	skip "running as root — an unreadable file cannot be simulated"
else
	s_assert_status 2 "an unreadable --set-file path is refused before dispatch"
	s_assert_err_has "not readable"
fi
chmod 644 "$UNREAD"

dispatch implementer --prompt 'x' --set-file "V=$SCRATCH"
s_assert_status 2 "a --set-file path that is a directory is refused"
s_assert_err_has "directory"

# A --set-file value must not leak into a later --set of a different NAME, and
# must not reach the worker's own environment for a nested dispatch to read.
# A stale PD_F in this shell is the reproduction: set one, then run a plain
# --set, and confirm the plain value wins.
printf 'FROM-FILE\n' >"$SCRATCH/leak.src"
printf 'A is %%%%A%%%%.\n' >"$SCRATCH/leak.md"
PD_F_1="$SCRATCH/leak.src" PD_K_1=A
export PD_F_1 PD_K_1
dispatch implementer --prompt-file "$SCRATCH/leak.md" --set 'A=inline-value'
s_assert_out_has "A is inline-value." "a stale PD_F in the environment does not turn a --set into a file read"
s_assert_out_lacks "FROM-FILE" "…the leaked file is not read"
unset PD_F_1 PD_K_1

# The same NAME twice is refused, whichever forms it takes.
dispatch implementer --prompt 'x' --set 'A=1' --set 'A=2'
s_assert_status 2 "a NAME set twice by --set is refused"
s_assert_err_has "set twice"
dispatch implementer --prompt 'x' --set 'A=1' --set-file "A=$SCRATCH/leak.src"
s_assert_status 2 "a NAME set by both --set and --set-file is refused"

# H-2: an unreadable path was accepted, substituted empty, exit 0 — the ticket
# says it is refused. (Skipped as root, where the mode is ignored.)
if [ "$(id -u)" != 0 ]; then
	printf 'secret\n' >"$SCRATCH/noperm"
	chmod 000 "$SCRATCH/noperm"
	dispatch implementer --prompt 'x' --set-file "V=$SCRATCH/noperm"
	s_assert_status 2 "an unreadable --set-file path is refused, not substituted empty"
	chmod 644 "$SCRATCH/noperm"
fi
dispatch implementer --prompt 'x' --set-file "V=$SCRATCH"
s_assert_status 2 "a --set-file path that is a directory is refused"

# H-3: a --set-file leaves no path behind for a later plain --set to inherit,
# and nothing of the sort reaches the worker's environment. A nested dispatch
# is the sharp case: the inner --set must not read the outer --set-file's file.
printf 'inner sees: %%%%A%%%%\n' >"$SCRATCH/nested.md"
printf 'OUTER-FILE-CONTENTS\n' >"$SCRATCH/outer"
NEST="$SCRATCH/nest.sh"
cat >"$NEST" <<EOF
#!/bin/sh
cat >/dev/null
# Runs INSIDE a --set-file dispatch, so PD_F_* is in its environment. Its own
# --set for the same slot must not pick up the outer file. It dispatches the
# REVIEWER tier, which the nest policy maps to the echoing harness: had it
# dispatched implementer it would resolve to this very stub again — the
# inherited AGENTS_CONFIG makes that a fork bomb, not a test (it filled a
# host's task ceiling in under three minutes).
sh "$DISPATCH" reviewer --prompt-file "$SCRATCH/nested.md" --set 'A=inline-only'
EOF
chmod +x "$NEST"
CFG_NEST="$SCRATCH/nest.config.sh"
cat >"$CFG_NEST" <<EOF
AGENT_HARNESSES='nest'
AGENT_HARNESS_NEST_CMD='$NEST {model_flag} < {prompt_file}'
AGENT_HARNESS_NEST_MODEL_FLAG=''
AGENT_TIER_IMPLEMENTER='nest:'
AGENT_TIER_REVIEWER='w:'
AGENT_HARNESSES='nest w'
AGENT_HARNESS_W_CMD='$SCRATCH/echo-stdin {model_flag} < {prompt_file}'
AGENT_HARNESS_W_MODEL_FLAG=''
EOF
printf '#!/bin/sh\ncat\n' >"$SCRATCH/echo-stdin"; chmod +x "$SCRATCH/echo-stdin"
printf 'x\n' >"$SCRATCH/anyprompt.md"
AGENTS_CONFIG="$CFG_NEST" dispatch implementer --prompt-file "$SCRATCH/anyprompt.md" --set-file "OUTER=$SCRATCH/outer"
s_assert_out_has "inner sees: inline-only" "a nested --set does not inherit the outer --set-file's path"
s_assert_out_lacks "OUTER-FILE-CONTENTS" "…and the outer file's contents never reach the inner worker"
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

# M-1: the same NAME twice is refused, not silently resolved by argument order.
dispatch implementer --prompt 'x' --set 'A=one' --set 'A=two'
s_assert_status 2 "the same marker NAME in two --set is refused"
dispatch implementer --prompt 'x' --set 'A=one' --set-file "A=$SCRATCH/outer"
s_assert_status 2 "…and across --set and --set-file"

# A ticket body is untrusted content, and %%BODY%% is exactly where one goes.
# The pairs used to be joined into one string and read back line by line, so a
# multi-line value was truncated at its first newline AND any line inside it
# shaped NAME=VALUE was promoted to a substitution of its own.
printf 'BODY:\n%%%%BODY%%%%\nC was: %%%%C%%%%\n' >"$SCRATCH/multi.md"
dispatch implementer --prompt-file "$SCRATCH/multi.md" --set 'C=legit' --set 'BODY=line one
C=INJECTED
line three'
s_assert_out_has 'line three' "a multi-line value arrives whole, not truncated at the first newline"
s_assert_out_has 'C=INJECTED' "…including a line inside it that looks like a pair"
s_assert_out_has 'C was: legit' "…which does not hijack the marker of that name"

# A value is data, not a template. Re-scanning it made the result depend on the
# order the pairs happened to arrive in.
printf 'X: %%%%A%%%%\n' >"$SCRATCH/rescan.md"
dispatch implementer --prompt-file "$SCRATCH/rescan.md" --set 'A=[%%B%%]' --set 'B=bee'
s_assert_out_has 'X: [%%B%%]' "a marker inside a VALUE is not substituted"
dispatch implementer --prompt-file "$SCRATCH/rescan.md" --set 'B=bee' --set 'A=[%%B%%]'
s_assert_out_has 'X: [%%B%%]' "…in either order — substitution is one pass, not one per pair"

dispatch implementer --prompt 'x' --set 'a b=1'
s_assert_status 2 "a NAME that could never be a marker is refused"

# The header strip's two edges.
printf '<!--\nan example: a-->b\nMarkers: %%%%T%%%%\n-->\n\nReal line %%%%T%%%%.\n' >"$SCRATCH/edge.md"
dispatch implementer --prompt-file "$SCRATCH/edge.md" --set T=filled
s_assert_out_has 'Real line filled.' "a --> inside the header does not close it early"
s_assert_out_lacks 'an example' "…and the whole header is still removed"
s_assert_out_lacks 'Markers: filled' "…so the header's own marker documentation is never filled"

printf '<!--\nnever closed\n' >"$SCRATCH/unterm.md"
dispatch implementer --prompt-file "$SCRATCH/unterm.md" --dry-run
s_assert_status 0 "an unterminated header does not abort"
s_assert_out_has 'never closed' "…and the prompt is kept rather than stripped to nothing"
s_assert_err_has "never closes it"

printf '<!--\nx\n-->\n\n\n' >"$SCRATCH/blanks.md"
dispatch implementer --prompt-file "$SCRATCH/blanks.md"
s_assert_status 2 "a prompt that is only a header is refused, not sent empty"

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
	# The PROHIBITION, not the word. `grep -qi merge` was satisfied by the
	# review prompt's "never merge them" — the sentence about the two axes —
	# so deleting "or merge" from the actual prohibition left this green.
	grep -qiE 'do not (commit, )?push' "$f" &&
		grep -qiE 'do not[^.]*merge|never[^.]*merge a pull request' "$f" &&
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
	s_assert_status 0 "$wp.md dispatches with every marker filled"
	case "$S_ERR" in
	*"unfilled marker"*) fail "$wp.md left a marker unfilled after filling all of them" ;;
	*) pass "$wp.md has no marker the caller cannot fill" ;;
	esac
done

# ---------------------------------------------------------------------------
banner "Misconfiguration reports itself, and points at the fix"
# ---------------------------------------------------------------------------
dispatch reviewer --prompt 'x'
s_assert_status 2 "an agent harness named without a command template is refused"
s_assert_err_has "AGENT_HARNESS_OTHER_CMD"

dispatch mechanical --prompt 'x'
s_assert_status 2 "a model id carrying a shell metacharacter is REFUSED, not escaped"
s_assert_err_has "will not interpolate"

dispatch not-a-tier --prompt 'x'
s_assert_status 2 "the closed tier vocabulary still closes"

dispatch implementer --nonsense --prompt 'x'
s_assert_status 2 "an unknown option is refused rather than read as a tier"
s_assert_err_has "unknown option"

dispatch implementer
s_assert_status 2 "no prompt at all is a usage error"

dispatch implementer --prompt-file "$SCRATCH/does-not-exist.md"
s_assert_status 2 "a missing prompt file is refused before anything runs"

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
s_assert_status 2 "an uninstalled agent harness is caught before it is invoked"
s_assert_err_has "not on PATH"

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
s_assert_status 0 "a prompt under a hostile directory name dispatches"
if [ -f "$SCRATCH/PWNED" ]; then
	fail "the prompt path was EXECUTED — command substitution in a path reached the eval"
	rm -f "$SCRATCH/PWNED"
else
	pass "the prompt path was not executed"
fi
s_assert_out_has 'the prompt survives' "…and the prompt still reached the worker"

SPACED="$SCRATCH/with space"
mkdir -p "$SPACED"
printf 'spaces are fine\n' >"$SPACED/p.md"
dispatch implementer --prompt-file "$SPACED/p.md"
s_assert_status 0 "a path containing a space dispatches"
s_assert_out_has 'spaces are fine' "…and arrives whole, not split at the space"

# $TMPDIR is somebody else's data too, so staging alone is not the fix.
mkdir -p "$SCRATCH/tmp;x"
t_run_split env TMPDIR="$SCRATCH/tmp;x" sh "$DISPATCH" implementer --prompt 'hi'
s_assert_status 2 "a TMPDIR this script cannot safely interpolate is refused, not escaped"

dispatch implementer --prompt-file /dev/null
s_assert_status 2 "an empty prompt file is refused — a worker given nothing invents something"

# ---------------------------------------------------------------------------
banner "A worker never inherits the dispatcher's stdin"
# ---------------------------------------------------------------------------
# Found live: a CLI that reads stdin when it is not a tty (Gemini's -p appends
# stdin "if any") blocked forever on the dispatcher's inherited open pipe. The
# prompt already reaches the worker by {prompt_file}, so the worker has no
# legitimate use for the parent's stdin — it gets the prompt file when the
# template redirects it, and nothing otherwise, never an open pipe.
READER="$SCRATCH/stdin-reader"
cat >"$READER" <<'EOF'
#!/bin/sh
n=$(cat | wc -c | tr -d ' ')
echo "STDIN-BYTES=$n"
EOF
chmod +x "$READER"
CFG_STDIN="$SCRATCH/stdin.config.sh"
cat >"$CFG_STDIN" <<EOF
AGENT_HARNESSES='rd'
AGENT_HARNESS_RD_CMD='$READER {model_flag}'
AGENT_HARNESS_RD_MODEL_FLAG=''
AGENT_TIER_IMPLEMENTER='rd:'
EOF
AGENTS_CONFIG="$CFG_STDIN"
export AGENTS_CONFIG
# The dispatcher's OWN stdin is a FIFO whose write end a background process
# holds open without writing — the shape that hung. A worker that inherits it
# blocks until that process exits; one that does not returns at once with
# nothing. The holder is a background job so the timing measures the
# dispatcher, not the fixture: a `(sleep; echo) | dispatcher` pipeline would
# have waited on its own sleep whatever the dispatcher did.
FIFO="$SCRATCH/held-open"
# Checked, because a mkfifo that quietly does nothing — a scratch dir on a
# filesystem without FIFO support — leaves $FIFO absent, the redirect below
# fails, and every assertion in this leg then passes with the fix reverted.
# The suite's scratch is mktemp's, which is tmpfs or ext4 everywhere the kit
# runs; where that is not so, this says so rather than going green.
mkfifo "$FIFO" || {
	fail "mkfifo failed under $SCRATCH — this leg cannot hold the stdin rule on this filesystem"
	FIFO=""
}
sleep 20 >"${FIFO:-/dev/null}" &
holder=$!
start=$(date +%s)
t_run_split sh -c 'sh "$1" implementer --prompt hi <"$2"' _ "$DISPATCH" "$FIFO"
took=$(( $(date +%s) - start ))
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null
s_assert_status 0 "a worker whose template does not redirect stdin still dispatches"
s_assert_out_has "STDIN-BYTES=0" "…and reads NOTHING from the dispatcher's open pipe"
[ "$took" -lt 10 ] &&
	pass "…and returns at once rather than waiting on the pipe (${took}s)" ||
	fail "the worker waited on the dispatcher's stdin (${took}s) — it inherited the pipe"

CFG_STDIN_NORED="$SCRATCH/stdin-nored.config.sh"
cp "$CFG_STDIN" "$CFG_STDIN_NORED"

# A template that DOES redirect from the prompt file still gets it: a redirect
# inside the eval'd command wins over the default.
cat >"$CFG_STDIN" <<EOF
AGENT_HARNESSES='rd'
AGENT_HARNESS_RD_CMD='$READER {model_flag} < {prompt_file}'
AGENT_HARNESS_RD_MODEL_FLAG=''
AGENT_TIER_IMPLEMENTER='rd:'
EOF
t_run_split sh "$DISPATCH" implementer --prompt "twelve bytes"
s_assert_out_has "STDIN-BYTES=13" "a template that redirects from {prompt_file} still receives the prompt"

AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

# ---------------------------------------------------------------------------
banner "A worker that never returns is killed, and says so distinctly"
# ---------------------------------------------------------------------------
# Headless agent CLIs gate tool calls on approvals, and headless there is no
# human — a reviewer told to run git diff in an approval-gated mode waits
# forever. Found live; only an external timeout ended it.
#
# These legs write the worker's stdout to a FILE and read it back, never
# through $(...): a command substitution returns only when every holder of
# its stdout has exited, so a survivor would make the capture wait for it and
# a "nothing left behind" assertion could never fail on its own. And each
# sleeper writes its pid to a file, so survival is asserted with kill -0
# rather than inferred from the capture returning.
SLEEPER="$SCRATCH/sleeper"
PIDFILE="$SCRATCH/sleeper.pid"
OUTFILE="$SCRATCH/sleeper.out"
cat >"$SLEEPER" <<EOF
#!/bin/sh
cat >/dev/null
echo "\$\$" >"$PIDFILE"
echo "started"
sleep 30
echo "finished"
EOF
chmod +x "$SLEEPER"
CFG_SLOW="$SCRATCH/slow.config.sh"
cat >"$CFG_SLOW" <<EOF
AGENT_HARNESSES='slow'
AGENT_HARNESS_SLOW_CMD='$SLEEPER {model_flag} < {prompt_file}'
AGENT_HARNESS_SLOW_MODEL_FLAG=''
AGENT_TIER_IMPLEMENTER='slow:'
EOF
AGENTS_CONFIG="$CFG_SLOW"
export AGENTS_CONFIG

start=$(date +%s)
sh "$DISPATCH" implementer --prompt 'x' --timeout 2 >"$OUTFILE" 2>"$SCRATCH/sleeper.err"
S_STATUS=$?
took=$(( $(date +%s) - start ))
S_OUT=$(cat "$OUTFILE"); S_ERR=$(cat "$SCRATCH/sleeper.err")
s_assert_status 124 "a worker past --timeout is killed, with a status the caller can tell from the worker's own"
s_assert_out_has "started" "…after whatever it had already written"
s_assert_out_lacks "finished" "…and before it could finish"
s_assert_err_has "timed out"
[ "$took" -lt 10 ] &&
	pass "…within the timeout, not the worker's own duration (${took}s)" ||
	fail "the dispatch took ${took}s — the timeout did not fire"
sleep 1
if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
	fail "the timed-out worker (pid $(cat "$PIDFILE")) is still running — the tree was not killed"
	kill -KILL "$(cat "$PIDFILE")" 2>/dev/null
else
	pass "the timed-out worker is gone"
fi

# A worker that IGNORES TERM. This is the case the first version got wrong:
# it signalled the tree after TERM had already reparented the survivors, so
# the KILL pass found nothing and a TERM-ignoring worker ran to completion.
cat >"$SLEEPER" <<EOF
#!/bin/sh
trap '' TERM
cat >/dev/null
echo "\$\$" >"$PIDFILE"
echo "stubborn"
sleep 30
echo "finished"
EOF
start=$(date +%s)
sh "$DISPATCH" implementer --prompt 'x' --timeout 2 >"$OUTFILE" 2>/dev/null
S_STATUS=$?
took=$(( $(date +%s) - start ))
S_OUT=$(cat "$OUTFILE")
s_assert_status 124 "a worker that ignores TERM is still reported as timed out"
s_assert_out_lacks "finished" "…and did not run to completion"
[ "$took" -lt 10 ] &&
	pass "…and the dispatch returned inside the timeout plus grace (${took}s)" ||
	fail "the dispatch took ${took}s — KILL never followed TERM"
sleep 1
if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
	fail "the TERM-ignoring worker survived — KILL was never sent to the snapshotted tree"
	kill -KILL "$(cat "$PIDFILE")" 2>/dev/null
else
	pass "the TERM-ignoring worker is gone — KILL followed TERM"
fi

# A worker whose CHILD ignores TERM and would be reparented when the worker
# dies. The snapshot must be taken before the first signal, or the child is
# no longer under the worker's pid when the KILL pass looks.
cat >"$SLEEPER" <<EOF
#!/bin/sh
cat >/dev/null
sh -c 'trap "" TERM; echo \$\$ >"$PIDFILE"; sleep 30' &
echo "parent"
wait
echo "finished"
EOF
sh "$DISPATCH" implementer --prompt 'x' --timeout 2 >"$OUTFILE" 2>/dev/null
S_STATUS=$?
s_assert_status 124 "a worker whose child ignores TERM is reported as timed out"
sleep 1
if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
	fail "the reparented grandchild survived — the tree was walked after TERM, not before"
	kill -KILL "$(cat "$PIDFILE")" 2>/dev/null
else
	pass "the grandchild is gone — the tree was snapshotted before the first signal"
fi

# A worker that traps TERM and exits 0 must NOT read as success, and one that
# kills itself must NOT read as a timeout: the verdict is the watchdog's flag,
# not the worker's exit status.
cat >"$SLEEPER" <<EOF
#!/bin/sh
trap 'exit 0' TERM
cat >/dev/null
sleep 30
EOF
sh "$DISPATCH" implementer --prompt 'x' --timeout 2 >/dev/null 2>&1
S_STATUS=$?
s_assert_status 124 "a worker that traps TERM and exits 0 is still a timeout — the verdict is the watchdog's"
cat >"$SLEEPER" <<EOF
#!/bin/sh
cat >/dev/null
kill -TERM \$\$
EOF
sh "$DISPATCH" implementer --prompt 'x' --timeout 30 >/dev/null 2>"$SCRATCH/self.err"
S_STATUS=$?
S_ERR=$(cat "$SCRATCH/self.err")
[ "$S_STATUS" = 143 ] && pass "a worker that kills itself with TERM is reported as 143, not 124" ||
	fail "a self-killed worker was reported as $S_STATUS"
s_assert_err_lacks "timed out"

# A FAST worker under a long --timeout must not cost the timeout: killing the
# watchdog without its sleep left `sleep N` holding the caller's stdout, and
# every capturing caller waited the full N.
cat >"$SLEEPER" <<EOF
#!/bin/sh
cat >/dev/null
echo "quick"
exit 5
EOF
start=$(date +%s)
dispatch implementer --prompt 'x' --timeout 20
took=$(( $(date +%s) - start ))
s_assert_status 5 "a worker that finishes inside --timeout passes its own status through"
s_assert_out_has "quick" "…and its output"
[ "$took" -lt 8 ] &&
	pass "…and a capturing caller returns when the worker does, not when the timeout would (${took}s)" ||
	fail "a fast worker cost ${took}s — the watchdog's sleep was left holding stdout"
# And nothing of the dispatcher's is left running.
sleep 1
# Exact-args match, not `pgrep -f`: a loose pattern matches any process whose
# command line mentions the number — including the suite's own — and counted
# three ghosts here before this line was written.
sleeps_alive() { ps -eo args= 2>/dev/null | awk -v n="$1" '$1 == "sleep" && $2 == n' | wc -l | tr -d ' '; }
leftover=$(sleeps_alive 20)
[ "$leftover" = 0 ] &&
	pass "the watchdog's sleep is gone with the watchdog" ||
	fail "$leftover 'sleep 20' still running — the watchdog was killed without its sleep"

dispatch implementer --prompt 'x' --timeout 2 --dry-run
s_assert_out_has "timeout:        2s" "--dry-run shows the timeout"
s_assert_out_lacks "quick" "…and never started the worker"
dispatch implementer --prompt 'x' --timeout abc
s_assert_status 2 "a timeout that is not a whole number of seconds is refused"
dispatch implementer --prompt 'x' --timeout 0
s_assert_status 2 "--timeout 0 is refused — it is not a timeout"

# Signalling the DISPATCHER takes the worker with it. Backgrounded children of
# a non-interactive shell start with SIGINT ignored, so without a trap a
# Ctrl-C on the dispatcher left the worker running with no timeout left.
cat >"$SLEEPER" <<EOF
#!/bin/sh
cat >/dev/null
echo "\$\$" >"$PIDFILE"
sleep 30
EOF
sh "$DISPATCH" implementer --prompt 'x' --timeout 50 >/dev/null 2>&1 &
disp=$!
sleep 2
kill -TERM "$disp" 2>/dev/null
wait "$disp" 2>/dev/null
disp_status=$?
sleep 1
[ "$disp_status" = 143 ] && pass "a TERM to the dispatcher exits 143" || fail "a TERM to the dispatcher exited $disp_status"
if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
	fail "the worker outlived a TERM to the dispatcher — orphaned with no timeout left"
	kill -KILL "$(cat "$PIDFILE")" 2>/dev/null
else
	pass "a TERM to the dispatcher takes the worker down with it"
fi
leftover=$(sleeps_alive 50)
[ "$leftover" = 0 ] && pass "…and the watchdog's sleep" || fail "$leftover watchdog sleep(s) outlived the dispatcher"

AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

# ---------------------------------------------------------------------------
banner "A dispatch refuses to nest past the policy maximum depth"
# ---------------------------------------------------------------------------
# A worker may run the dispatcher itself, and a worker whose tier maps back to
# its own stub is a fork bomb with nothing to stop it: the H-3 stub above was
# exactly that in its first version and filled a host's task ceiling in under
# three minutes. The depth reaches each dispatch through the worker's
# environment, a top-level dispatch is depth 1, and a dispatch past the
# maximum dies before it resolves the tier — with a status of its own, 4,
# distinct from every status the dispatcher itself produces (0 dispatched, 2
# usage, 3 in-session, 124 timed out). A worker's own status still passes
# through untouched, so a worker that exits 4 is the ambiguity 124 already
# has; the header's EXIT STATUS table is the one home for that contract.
#
# The stub RECORDS each worker in a file rather than the suite counting
# processes: the claim is that the chain is bounded by the maximum, not by
# the host, and a line per worker is that count exactly.
SELF="$SCRATCH/self-dispatching"
RAN="$SCRATCH/self.ran"
cat >"$SELF" <<EOF
#!/bin/sh
cat >/dev/null
echo "worker at depth \${AGENT_DISPATCH_DEPTH:-unset}" >>"$RAN"
exec sh "$DISPATCH" implementer --prompt 'again'
EOF
chmod +x "$SELF"
CFG_SELF="$SCRATCH/self.config.sh"
cat >"$CFG_SELF" <<EOF
AGENT_HARNESSES='self'
AGENT_HARNESS_SELF_CMD='$SELF {model_flag} < {prompt_file}'
AGENT_HARNESS_SELF_MODEL_FLAG=''
AGENT_TIER_IMPLEMENTER='self:'
EOF
AGENTS_CONFIG="$CFG_SELF"
export AGENTS_CONFIG
: >"$RAN"
dispatch implementer --prompt 'x'
s_assert_status 4 "a chain of self-dispatching workers ends in the depth refusal's own status"
s_assert_err_has "AGENT_DISPATCH_MAX_DEPTH"
s_assert_err_has "depth 4"
s_assert_err_has "maximum is 3"
ran=$(wc -l <"$RAN" | tr -d ' ')
[ "$ran" = 3 ] &&
	pass "exactly 3 workers ran — the kit default, planner → implementer → reviewer deep" ||
	fail "$ran workers ran under the default maximum of 3"
[ "$(sed -n 1p "$RAN")" = "worker at depth 2" ] &&
	pass "the first worker sees depth 2 — its dispatch was the top-level one" ||
	fail "the first worker saw '$(sed -n 1p "$RAN")'"
[ "$(sed -n 3p "$RAN")" = "worker at depth 4" ] &&
	pass "the last worker sees depth 4, and its own dispatch is the one refused" ||
	fail "the last worker saw '$(sed -n 3p "$RAN")'"

# The consumer's policy file overrides the default, and the chain is bounded
# by THAT number: two here, so a maximum the host never sees.
printf "AGENT_DISPATCH_MAX_DEPTH='2'\n" >>"$CFG_SELF"
: >"$RAN"
dispatch implementer --prompt 'x'
s_assert_status 4 "a policy maximum of 2 refuses the third dispatch"
s_assert_err_has "maximum is 2"
ran=$(wc -l <"$RAN" | tr -d ' ')
[ "$ran" = 2 ] &&
	pass "exactly 2 workers ran — the policy file's number, not the kit's" ||
	fail "$ran workers ran under a policy maximum of 2"

# At the maximum a dispatch still RUNS; one past it never spawns the worker.
# The depth is a fact in the environment, so a suite can stand at any depth
# without building the chain. The echoing stub says whether it ran.
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG
t_run_split env AGENT_DISPATCH_DEPTH=3 sh "$DISPATCH" implementer --prompt 'at the maximum'
s_assert_status 0 "a dispatch AT the maximum depth runs"
s_assert_out_has 'at the maximum' "…and the worker gets its prompt"
t_run_split env AGENT_DISPATCH_DEPTH=4 sh "$DISPATCH" implementer --prompt 'past it'
s_assert_status 4 "a dispatch one past the maximum is refused"
s_assert_out_lacks 'ARGV:' "…and the worker never ran"
s_assert_err_has "refusing to nest"
# The reader of that stderr is usually the refused worker — a model with
# tools — so the message tells it to stop and report, never how to lift the
# ceiling; and the policy file is named by its variable, not by a path the
# dispatcher may not have read (AGENTS_CONFIG resolves first).
s_assert_err_has "stop and report"
s_assert_err_lacks "scripts/agents.config.sh"
s_assert_err_lacks "Raise"

# The worker is spawned one deeper than its dispatch, through BOTH spawn
# paths: the plain eval and the timed `sh -c`. The dispatcher's comment says
# the two cannot disagree; this stub, which prints the depth it was given,
# holds them to it — the timed path is the wiring an approval-gated CLI runs
# under, and it was the one nothing asserted on.
DEPTH_STUB="$SCRATCH/depth-echoing"
cat >"$DEPTH_STUB" <<'EOF'
#!/bin/sh
cat >/dev/null
echo "worker at depth ${AGENT_DISPATCH_DEPTH:-unset}"
EOF
chmod +x "$DEPTH_STUB"
CFG_DEPTH="$SCRATCH/depth.config.sh"
cat >"$CFG_DEPTH" <<EOF
AGENT_HARNESSES='seen'
AGENT_HARNESS_SEEN_CMD='$DEPTH_STUB < {prompt_file}'
AGENT_HARNESS_SEEN_MODEL_FLAG=''
AGENT_TIER_IMPLEMENTER='seen:'
EOF
t_run_split env AGENTS_CONFIG="$CFG_DEPTH" AGENT_DISPATCH_DEPTH=2 sh "$DISPATCH" implementer --prompt 'x'
s_assert_out_is 'worker at depth 3' "a dispatch at depth 2 spawns its worker at depth 3 — the plain path"
t_run_split env AGENTS_CONFIG="$CFG_DEPTH" AGENT_DISPATCH_DEPTH=2 sh "$DISPATCH" implementer --prompt 'x' --timeout 5
s_assert_status 0 "…and the timed path runs the same worker"
s_assert_out_is 'worker at depth 3' "…which sees the same depth 3"

# Refused BEFORE the tier is resolved or the prompt is read: an in-session
# tier (normally exit 3) and a missing prompt file (normally exit 2) both
# report the depth first, because the invocation has nothing else to say.
t_run_split env AGENT_DISPATCH_DEPTH=4 sh "$DISPATCH" planner --prompt 'x'
s_assert_status 4 "an in-session tier past the maximum is refused, not handed back as exit 3"
s_assert_out_lacks 'model-for-planning' "…and no model id is printed"
t_run_split env AGENT_DISPATCH_DEPTH=4 sh "$DISPATCH" implementer --prompt-file "$SCRATCH/does-not-exist.md"
s_assert_status 4 "the depth is refused before the prompt file is looked at"

# --dry-run shows the depth the dispatch would run at, against the maximum.
dispatch implementer --prompt 'x' --dry-run
s_assert_out_has 'depth:          1 of 3' "--dry-run shows a top-level dispatch at depth 1 of the default 3"
t_run_split env AGENT_DISPATCH_DEPTH=2 sh "$DISPATCH" implementer --prompt 'x' --dry-run
s_assert_out_has 'depth:          2 of 3' "…and the inherited depth when there is one"
dispatch
s_assert_err_has "the depth, the budget and the prompt" # usage() lists what --dry-run prints, and the depth is one of them
s_assert_out_lacks 'ARGV:' "…running nothing"
# Under a policy maximum the second number is the policy's, not the default:
# the two assertions above cannot tell them apart.
t_run_split env AGENTS_CONFIG="$CFG_SELF" sh "$DISPATCH" implementer --prompt 'x' --dry-run
s_assert_out_has 'depth:          1 of 2' "…and the maximum shown is the policy file's when it sets one"

# A depth or a maximum that is not a whole number from 1 is a usage error,
# not a guess: 0 would refuse every dispatch, and a top-level one is depth 1.
# Empty is not malformed — it reads as unset, depth 1 — and a value past the
# shell's integer range is refused rather than compared: `[ -gt ]` errors on
# it, and an error there would skip the refusal and run the worker.
t_run_split env AGENT_DISPATCH_DEPTH=abc sh "$DISPATCH" implementer --prompt 'x'
s_assert_status 2 "a malformed AGENT_DISPATCH_DEPTH is refused as a usage error"
s_assert_err_has "AGENT_DISPATCH_DEPTH"
t_run_split env AGENT_DISPATCH_DEPTH=0 sh "$DISPATCH" implementer --prompt 'x'
s_assert_status 2 "AGENT_DISPATCH_DEPTH=0 is refused — a top-level dispatch is depth 1"
t_run_split env AGENT_DISPATCH_DEPTH='' sh "$DISPATCH" implementer --prompt 'x' --dry-run
s_assert_status 0 "an EMPTY AGENT_DISPATCH_DEPTH is not malformed"
s_assert_out_has 'depth:          1 of 3' "…it reads as unset: a top-level dispatch at depth 1"
t_run_split env AGENT_DISPATCH_DEPTH=9999999999 sh "$DISPATCH" implementer --prompt 'x'
s_assert_status 2 "a depth past the shell's integer range is refused, not compared"
s_assert_out_lacks 'ARGV:' "…and the worker never ran — an overflow does not fail open"
CFG_DEPTH0="$SCRATCH/depth0.config.sh"
{ cat "$CFG"; printf "AGENT_DISPATCH_MAX_DEPTH='0'\n"; } >"$CFG_DEPTH0"
t_run_split env AGENTS_CONFIG="$CFG_DEPTH0" sh "$DISPATCH" implementer --prompt 'x'
s_assert_status 2 "AGENT_DISPATCH_MAX_DEPTH=0 is refused — it would refuse every dispatch"
s_assert_err_has "AGENT_DISPATCH_MAX_DEPTH"
# A typo in the policy file must not silently lift the ceiling: without the
# non-digit arm, `[ -gt ]` errors on 'abc', the refusal is skipped, and the
# worker runs.
CFG_DEPTHABC="$SCRATCH/depthabc.config.sh"
{ cat "$CFG"; printf "AGENT_DISPATCH_MAX_DEPTH='abc'\n"; } >"$CFG_DEPTHABC"
t_run_split env AGENTS_CONFIG="$CFG_DEPTHABC" sh "$DISPATCH" implementer --prompt 'x'
s_assert_status 2 "a non-numeric AGENT_DISPATCH_MAX_DEPTH is refused as a usage error"
s_assert_out_lacks 'ARGV:' "…and the worker never ran — a malformed maximum does not disable the ceiling"
CFG_DEPTHBIG="$SCRATCH/depthbig.config.sh"
{ cat "$CFG"; printf "AGENT_DISPATCH_MAX_DEPTH='9999999999'\n"; } >"$CFG_DEPTHBIG"
t_run_split env AGENTS_CONFIG="$CFG_DEPTHBIG" sh "$DISPATCH" implementer --prompt 'x'
s_assert_status 2 "a maximum past the shell's integer range is refused, the same as a depth"

AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

# ---------------------------------------------------------------------------
banner "Dispatch scratch names itself, and stale scratch is swept"
# ---------------------------------------------------------------------------
# A dispatch that dies before its trap — KILL, a budget, a host out of tasks
# — leaves its scratch behind, and `mktemp -d` named it tmp.XXXXXX: 267 of
# those on one host, none attributable. Every leg here runs under its own
# TMPDIR so the sweep sees only what this suite planted.
SWEEP_TMP="$SCRATCH/sweep-tmp"
mkdir -p "$SWEEP_TMP"
AGENTS_CONFIG="$CFG_SLOW"
export AGENTS_CONFIG
cat >"$SLEEPER" <<EOF
#!/bin/sh
cat >/dev/null
echo "\$\$" >"$PIDFILE"
sleep 30
EOF
env TMPDIR="$SWEEP_TMP" sh "$DISPATCH" implementer --prompt 'x' >/dev/null 2>&1 &
disp=$!
sleep 2
# KILL is uncatchable, so the cleanup trap never runs; the worker is orphaned
# and reaped here so it cannot outlive the suite.
kill -KILL "$disp" 2>/dev/null
wait "$disp" 2>/dev/null
kill -KILL "$(cat "$PIDFILE")" 2>/dev/null
LEFTOVER=$(ls -d "$SWEEP_TMP"/agent-dispatch.* 2>/dev/null)
if [ -n "$LEFTOVER" ] && [ "$(printf '%s\n' "$LEFTOVER" | wc -l | tr -d ' ')" = 1 ] && [ -f "$LEFTOVER/prompt.md" ]; then
	pass "a dispatch killed with KILL leaves ONE directory named agent-dispatch.* — dispatch scratch by name alone"
else
	fail "the leftover scratch is not recognisable by name: $(ls "$SWEEP_TMP" | tr '\n' ' ')"
	LEFTOVER="$SWEEP_TMP/agent-dispatch.unnamed"
	mkdir -p "$LEFTOVER"
fi

# Age the leftover past the sweep age, and plant what the sweep must NOT
# touch: a fresh dispatch scratch (a dispatch still running), a stale
# directory without the prefix, a stale plain file that carries it, a stale
# prefixed directory NESTED under the unrelated one (the sweep is depth one —
# a scratch below the temp location is somebody else's), and a prefixed
# symlink to a stale directory outside the temp location (find is physical:
# a link is not a directory, so neither the link nor its target goes).
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG
OLD=202001010000
touch -t "$OLD" "$LEFTOVER"
mkdir -p "$SWEEP_TMP/agent-dispatch.fresh" "$SWEEP_TMP/tmp.unrelated/agent-dispatch.nested"
touch -t "$OLD" "$SWEEP_TMP/tmp.unrelated" "$SWEEP_TMP/tmp.unrelated/agent-dispatch.nested"
printf 'x\n' >"$SWEEP_TMP/agent-dispatch.notadir"
touch -t "$OLD" "$SWEEP_TMP/agent-dispatch.notadir"
LINK_TARGET="$SCRATCH/sweep-link-target"
mkdir -p "$LINK_TARGET"
touch -t "$OLD" "$LINK_TARGET"
ln -s "$LINK_TARGET" "$SWEEP_TMP/agent-dispatch.link"

t_run_split env TMPDIR="$SWEEP_TMP" sh "$DISPATCH" implementer --prompt 'x' --dry-run
s_assert_status 0 "a dry run with stale scratch beside it succeeds"
[ -d "$LEFTOVER" ] && pass "…and removes nothing — a dry run runs nothing" || fail "a dry run swept the stale scratch"

t_run_split env TMPDIR="$SWEEP_TMP" sh "$DISPATCH" implementer --prompt 'x'
s_assert_status 0 "a dispatch with stale scratch beside it dispatches"
s_assert_err_has "swept 1 stale dispatch scratch"
[ -d "$LEFTOVER" ] && fail "the stale dispatch scratch survived the sweep" || pass "the stale dispatch scratch is gone"
[ -d "$SWEEP_TMP/agent-dispatch.fresh" ] && pass "a fresh dispatch scratch — a dispatch still running — is left alone" || fail "the sweep removed a fresh dispatch scratch"
[ -d "$SWEEP_TMP/tmp.unrelated" ] && pass "a stale directory without the prefix is never touched" || fail "the sweep removed a directory that is not dispatch scratch"
[ -f "$SWEEP_TMP/agent-dispatch.notadir" ] && pass "a stale plain file carrying the prefix is never touched" || fail "the sweep removed a file"
[ -d "$SWEEP_TMP/tmp.unrelated/agent-dispatch.nested" ] && pass "a stale prefixed directory below depth one is never touched — the sweep does not recurse" || fail "the sweep recursed under the temp location and removed a nested directory"
[ -L "$SWEEP_TMP/agent-dispatch.link" ] && pass "a prefixed symlink is never touched — find is physical, and a link is not a directory" || fail "the sweep removed a symlink carrying the prefix"
[ -d "$LINK_TARGET" ] && pass "…and what it points to survives" || fail "the sweep followed a symlink and removed its target"
remaining=$(ls -d "$SWEEP_TMP"/agent-dispatch.* 2>/dev/null | grep -Evc 'agent-dispatch\.(fresh|notadir|link)$')
[ "$remaining" = 0 ] && pass "…and the dispatch's own scratch went with its trap" || fail "$remaining dispatch scratch director(ies) left by a dispatch that returned normally"

t_run_split env TMPDIR="$SWEEP_TMP" sh "$DISPATCH" implementer --prompt 'x'
s_assert_err_lacks "swept"

# The sweep age is policy: AGENT_DISPATCH_SWEEP_DAYS beside the tier mapping.
CFG_SWEEP="$SCRATCH/sweep.config.sh"
{ cat "$CFG"; echo "AGENT_DISPATCH_SWEEP_DAYS=100000"; } >"$CFG_SWEEP"
touch -t "$OLD" "$SWEEP_TMP/agent-dispatch.fresh"
t_run_split env TMPDIR="$SWEEP_TMP" AGENTS_CONFIG="$CFG_SWEEP" sh "$DISPATCH" implementer --prompt 'x'
s_assert_status 0 "a dispatch under a long sweep age dispatches"
[ -d "$SWEEP_TMP/agent-dispatch.fresh" ] && pass "a scratch younger than the policy's sweep age is kept" || fail "the policy's sweep age was not read — the kit default swept it"
s_assert_err_lacks "swept"

# A --timeout that reaches the sweep age would let a later dispatch sweep a
# worker still running under it; refused before anything runs.
t_run_split env TMPDIR="$SWEEP_TMP" sh "$DISPATCH" implementer --prompt 'x' --timeout 86400
s_assert_status 2 "a --timeout at or past the sweep age is refused"
s_assert_err_has "sweep age"
s_assert_out_lacks 'ARGV:' "…before the worker runs"

for bad in 0 abc; do
	{ cat "$CFG"; echo "AGENT_DISPATCH_SWEEP_DAYS=$bad"; } >"$CFG_SWEEP"
	t_run_split env TMPDIR="$SWEEP_TMP" AGENTS_CONFIG="$CFG_SWEEP" sh "$DISPATCH" implementer --prompt 'x'
	s_assert_status 2 "AGENT_DISPATCH_SWEEP_DAYS='$bad' is refused — a sweep age is a whole number of days, at least one"
done

# The variable is documented where the mapping is edited, and ships EMPTY —
# empty is the kit's default, the way an unmapped tier is a working state.
SHIPPED_CFG="$KIT/scripts/agents.config.sh"
grep -q "^AGENT_DISPATCH_SWEEP_DAYS=''" "$SHIPPED_CFG" &&
	pass "the shipped agents config carries AGENT_DISPATCH_SWEEP_DAYS, empty" ||
	fail "the shipped agents config does not carry AGENT_DISPATCH_SWEEP_DAYS='' — the sweep age is policy nobody can find"
assert_file_has "$SHIPPED_CFG" "sweep age" "the variable is explained in the glossary's name for it, beside the --timeout it must exceed"

# The boundary. "At least N days old" over POSIX find's whole-day arithmetic
# is an off-by-one waiting to happen in either direction, and a fixture from
# 2020 cannot see it. A scratch thirty-six hours old is past a one-day sweep
# age and short of a two-day one. Aging a directory to a RELATIVE time needs
# date arithmetic POSIX date lacks; GNU's -d has it, and elsewhere this leg
# says it was skipped rather than passing on nothing.
if AGED=$(date -d '36 hours ago' +%Y%m%d%H%M 2>/dev/null) && [ -n "$AGED" ]; then
	mkdir -p "$SWEEP_TMP/agent-dispatch.aged"
	touch -t "$AGED" "$SWEEP_TMP/agent-dispatch.aged"
	{ cat "$CFG"; echo "AGENT_DISPATCH_SWEEP_DAYS=2"; } >"$CFG_SWEEP"
	t_run_split env TMPDIR="$SWEEP_TMP" AGENTS_CONFIG="$CFG_SWEEP" sh "$DISPATCH" implementer --prompt 'x'
	[ -d "$SWEEP_TMP/agent-dispatch.aged" ] && pass "a scratch 36 hours old is kept under a two-day sweep age" || fail "a two-day sweep age swept a scratch 36 hours old"
	t_run_split env TMPDIR="$SWEEP_TMP" sh "$DISPATCH" implementer --prompt 'x'
	[ -d "$SWEEP_TMP/agent-dispatch.aged" ] && fail "the default one-day sweep age kept a scratch 36 hours old" || pass "…and swept under the default one-day sweep age"
	s_assert_err_has "swept 1 stale dispatch scratch"
else
	pass "date -d is not available — the 36-hour boundary leg was skipped, and says so"
fi
rm -rf "$SWEEP_TMP"

AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

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
s_assert_status 7 "the worker's own exit status passes through untouched"
s_assert_out_has 'MARKER=set' "a template may set the environment the worker runs in"

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
s_assert_status 2 "a mapped model with no MODEL_FLAG is refused rather than dropped"
s_assert_err_has "MODEL_FLAG"

# ---------------------------------------------------------------------------
banner "The budget — derived from the host, shown by --dry-run"
# ---------------------------------------------------------------------------
# ADR-0006: a task ceiling and a memory ceiling for the worker's whole tree,
# each a percentage of a HOST fact clamped to a policy floor and ceiling.
# The host facts are read from files under a root the dispatcher takes from
# AGENT_DISPATCH_HOST_ROOT (test-only, documented at the read site), so the
# arithmetic is asserted against numbers this suite chose, not against
# whatever machine runs it. The real host is read once, at the end, to prove
# the same code can.
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG
HOST="$SCRATCH/host"
SLICE="$HOST/sys/fs/cgroup/user.slice/user-1000.slice"
mkdir -p "$HOST/proc/self" "$SLICE/session-1.scope"
printf '0::/user.slice/user-1000.slice/session-1.scope\n' >"$HOST/proc/self/cgroup"
echo max >"$HOST/sys/fs/cgroup/user.slice/pids.max"
echo 10008 >"$SLICE/pids.max"
echo max >"$SLICE/session-1.scope/pids.max"
# The incident's host: MemAvailable 2141820 kB is 2091 MiB.
printf 'MemTotal:        3902724 kB\nMemFree:          200000 kB\nMemAvailable:    2141820 kB\n' >"$HOST/proc/meminfo"
# hostdry <args> — a dry run against the fake host.
hostdry() { t_run_split env AGENT_DISPATCH_HOST_ROOT="$HOST" sh "$DISPATCH" implementer --prompt 'x' --dry-run "$@"; }

hostdry
s_assert_status 0 "a dry run derives a budget"
s_assert_out_has 'tasks 2502' "the task ceiling is 25% of the slice's 10008"
s_assert_out_has '25% of 10008' "…and says the percentage and the base"
s_assert_out_has 'user-1000.slice' "…and names the cgroup the base came from"
s_assert_out_has 'memory 1045 MiB' "the memory ceiling is 50% of the 2091 MiB available"
s_assert_out_has '50% of 2091 MiB' "…and says so"
s_assert_out_has 'MemAvailable' "…naming the host fact"
s_assert_out_has 'enforced:' "the dry run names whether the budget is enforced"
s_assert_out_lacks 'NOT applied in this release' "…and no longer says enforcement is deferred (#208 applies it)"
s_assert_out_lacks 'ARGV:' "and the worker never ran"

# The smallest ceiling on the path wins: a session scope tighter than its
# slice is the ceiling this session actually runs under.
echo 3000 >"$SLICE/session-1.scope/pids.max"
hostdry
s_assert_out_has 'tasks 750' "the smallest pids.max on the cgroup path is the base"
s_assert_out_has 'session-1.scope' "…and the dry run names that cgroup, not the slice"
echo max >"$SLICE/session-1.scope/pids.max"

# A container with a private cgroup namespace: the dispatcher's own cgroup is
# the root, 0::/, and the pids limit sits right on it. The line names it "/".
printf '0::/\n' >"$HOST/proc/self/cgroup"
echo 2048 >"$HOST/sys/fs/cgroup/pids.max"
hostdry
s_assert_out_has 'tasks 512' "a pids.max on the root cgroup is the base (25% of 2048)"
s_assert_out_has 'pids.max of cgroup /' "…and the root cgroup is named /, not an empty string"
rm -f "$HOST/sys/fs/cgroup/pids.max"
printf '0::/user.slice/user-1000.slice/session-1.scope\n' >"$HOST/proc/self/cgroup"

# The floor is a clamp UP that is said out loud; the ceiling is a clamp DOWN
# in silence (ADR-0006 clause 2).
echo 400 >"$SLICE/pids.max"
hostdry
s_assert_out_has 'tasks 256' "25% of 400 is 100, below the floor — the floor stands"
s_assert_out_has 'below the floor 256' "…and the dry run says why"
s_assert_err_has "below the floor"
echo 100000 >"$SLICE/pids.max"
hostdry
s_assert_out_has 'tasks 4096' "25% of 100000 is 25000, above the ceiling — the ceiling stands"
s_assert_out_has 'above the ceiling 4096' "…and the dry run says why"
s_assert_err_lacks "above the ceiling"
echo 10008 >"$SLICE/pids.max"
printf 'MemAvailable:    600000 kB\n' >"$HOST/proc/meminfo"
hostdry
s_assert_out_has 'memory 512 MiB' "50% of 585 MiB is 292, below the floor — the floor stands"
s_assert_out_has 'below the floor 512' "…and the dry run says why"
printf 'MemAvailable:   40000000 kB\n' >"$HOST/proc/meminfo"
hostdry
s_assert_out_has 'memory 8192 MiB' "50% of 39062 MiB is above the ceiling — the ceiling stands"
printf 'MemAvailable:    2141820 kB\n' >"$HOST/proc/meminfo"

# The percentages and clamps are the policy file's.
CFG_BUDGET="$SCRATCH/budget.config.sh"
{ cat "$CFG"; printf "AGENT_BUDGET_TASKS_PERCENT=10\nAGENT_BUDGET_MEMORY_PERCENT=25\nAGENT_BUDGET_TASKS_FLOOR=8\nAGENT_BUDGET_MEMORY_FLOOR_MIB=100\nAGENT_BUDGET_MEMORY_CEILING_MIB=300\n"; } >"$CFG_BUDGET"
AGENTS_CONFIG="$CFG_BUDGET" hostdry
s_assert_out_has 'tasks 1000' "a policy percentage replaces the default (10% of 10008)"
s_assert_out_has 'memory 300 MiB' "a policy ceiling replaces the default (25% of 2091 is 522, held to 300)"
s_assert_out_has 'floor 8' "a policy floor is the one shown"
{ cat "$CFG"; printf "AGENT_BUDGET_TASKS_FLOOR='lots'\n"; } >"$CFG_BUDGET"
AGENTS_CONFIG="$CFG_BUDGET" hostdry
s_assert_status 2 "a budget variable that is not a whole number is refused, not defaulted"
s_assert_err_has "AGENT_BUDGET_TASKS_FLOOR"
# One validator for the flags and the policy file (ADR-0006 clause 3): 0 and a
# leading zero are refused on both, a percentage is 1–99, a floor is at most
# its ceiling.
{ cat "$CFG"; printf "AGENT_BUDGET_TASKS_PERCENT=025\n"; } >"$CFG_BUDGET"
AGENTS_CONFIG="$CFG_BUDGET" hostdry
s_assert_status 2 "a policy value with a leading zero is refused — arithmetic would read it as octal"
s_assert_err_has "AGENT_BUDGET_TASKS_PERCENT"
{ cat "$CFG"; printf "AGENT_BUDGET_MEMORY_PERCENT=0\n"; } >"$CFG_BUDGET"
AGENTS_CONFIG="$CFG_BUDGET" hostdry
s_assert_status 2 "a policy value of 0 is refused, as the flag refuses 0"
s_assert_err_has "AGENT_BUDGET_MEMORY_PERCENT"
{ cat "$CFG"; printf "AGENT_BUDGET_TASKS_PERCENT=100\n"; } >"$CFG_BUDGET"
AGENTS_CONFIG="$CFG_BUDGET" hostdry
s_assert_status 2 "a percentage of 100 or more is refused — the budget sits below the session's ceiling"
s_assert_err_has "below 100"
{ cat "$CFG"; printf "AGENT_BUDGET_TASKS_PERCENT=99\n"; } >"$CFG_BUDGET"
AGENTS_CONFIG="$CFG_BUDGET" hostdry
s_assert_status 0 "…and 99 is the last one accepted"
{ cat "$CFG"; printf "AGENT_BUDGET_TASKS_FLOOR=5000\n"; } >"$CFG_BUDGET"
AGENTS_CONFIG="$CFG_BUDGET" hostdry
s_assert_status 2 "a floor above its ceiling is refused"
s_assert_err_has "AGENT_BUDGET_TASKS_CEILING"
hostdry --budget-tasks 010
s_assert_status 2 "--budget-tasks with a leading zero is refused the same way"

# No cgroup ceiling on the path: the per-user process limit is the base —
# RLIMIT_NPROC, read from /proc/self/limits under the same fake root, so the
# expected number is one this suite chose rather than this shell's own limit,
# which a container or a locked-down runner may not let a test lower.
printf '0::/\n' >"$HOST/proc/self/cgroup"
limits() { printf 'Limit                     Soft Limit           Hard Limit           Units     \nMax processes             %s                 %s                processes \n' "$1" "$1" >"$HOST/proc/self/limits"; }
limits 8000
hostdry
s_assert_status 0 "a session with no cgroup pids.max still derives a budget"
s_assert_out_has 'tasks 2000' "…25% of the per-user process limit, 8000"
s_assert_out_has 'the per-user process limit' "…and the dry run names that source"
s_assert_out_lacks 'pids.max' "…not a cgroup it never found"
# No host fact at all — the limit is unlimited, or cannot be read: nothing to
# take a percentage of, so the policy CEILING stands in (ADR-0006 clause 2),
# never the floor, which answers a host known to be small.
limits unlimited
hostdry
s_assert_out_has 'tasks 4096' "an unlimited per-user limit leaves no base — the policy ceiling stands in"
s_assert_out_has 'the policy ceiling' "…and the dry run says so"
s_assert_out_has 'unlimited' "…naming the fact it found"
rm -f "$HOST/proc/self/limits"
hostdry
s_assert_out_has 'tasks 4096' "an unreadable per-user limit is the same case"
s_assert_out_has 'unreadable' "…and is named as such"
s_assert_err_lacks "below the floor"
printf '0::/user.slice/user-1000.slice/session-1.scope\n' >"$HOST/proc/self/cgroup"
# The same rule on the memory side: a /proc/meminfo with no MemAvailable has
# no fact to derive from, and the policy ceiling stands in there too.
printf 'MemTotal:        3902724 kB\nMemFree:          200000 kB\n' >"$HOST/proc/meminfo"
hostdry
s_assert_out_has 'memory 8192 MiB' "no MemAvailable: the policy ceiling stands in, not the floor"
s_assert_out_has 'no MemAvailable' "…and the dry run says what was missing"
s_assert_err_lacks "below the floor"
printf 'MemTotal:        3902724 kB\nMemFree:          200000 kB\nMemAvailable:    2141820 kB\n' >"$HOST/proc/meminfo"

# Per-dispatch overrides, and the loud off switch (ADR-0006 clause 4).
hostdry --budget-tasks 100 --budget-memory 300
s_assert_out_has 'tasks 100' "--budget-tasks replaces the derived task ceiling"
s_assert_out_has '--budget-tasks' "…and is named as its source"
s_assert_out_has 'memory 300 MiB' "--budget-memory replaces the derived memory ceiling"
s_assert_out_lacks '25% of' "…and nothing is derived for a value given explicitly"
s_assert_err_has "below the floor"
hostdry --budget-tasks 0
s_assert_status 2 "--budget-tasks 0 is refused"
hostdry --budget-memory abc
s_assert_status 2 "--budget-memory that is not a whole number of MiB is refused"
hostdry --no-budget --budget-tasks 5
s_assert_status 2 "--no-budget with an override is a contradiction, refused"
hostdry --no-budget
s_assert_status 0 "--no-budget dry-runs"
s_assert_out_has 'DISABLED' "…and the budget line says the budget is off"
s_assert_out_lacks 'tasks 2502' "…deriving nothing"
s_assert_err_has "no budget"

# Nesting: an inner dispatch runs inside the outer's budget and never opens a
# fresh one (ADR-0006 clause 7). The outer's numbers reach it by environment.
t_run_split env AGENT_DISPATCH_HOST_ROOT="$HOST" AGENT_DISPATCH_BUDGET_TASKS=777 AGENT_DISPATCH_BUDGET_MEMORY_MIB=888 \
	sh "$DISPATCH" implementer --prompt 'x' --dry-run
s_assert_status 0 "a dispatch inside a budgeted worker dry-runs"
s_assert_out_has 'inherited' "…and says it inherited the outer budget"
s_assert_out_has 'tasks 777' "…the outer's task ceiling"
s_assert_out_has 'memory 888 MiB' "…and the outer's memory ceiling"
s_assert_out_lacks '25% of' "…deriving nothing of its own"
# --no-budget on the inner dispatch does not win: it is already inside the
# outer scope's cgroup, and no flag on it can leave.
t_run_split env AGENT_DISPATCH_HOST_ROOT="$HOST" AGENT_DISPATCH_BUDGET_TASKS=777 AGENT_DISPATCH_BUDGET_MEMORY_MIB=888 \
	sh "$DISPATCH" implementer --prompt 'x' --dry-run --no-budget
s_assert_status 0 "--no-budget inside a budgeted worker dry-runs"
s_assert_out_has 'inherited' "…and the inherited budget wins"
s_assert_out_has 'cannot escape' "…the budget line saying that --no-budget cannot leave the outer cgroup"
s_assert_out_lacks 'DISABLED' "…not the off switch"
s_assert_err_has "cannot escape"
# The inherited pair is held to the same validator as everything else, and
# an outer dispatch exports both or neither: a lone task ceiling is refused,
# not shown beside a '?'.
t_run_split env AGENT_DISPATCH_HOST_ROOT="$HOST" AGENT_DISPATCH_BUDGET_TASKS='rm -rf x' AGENT_DISPATCH_BUDGET_MEMORY_MIB=888 \
	sh "$DISPATCH" implementer --prompt 'x' --dry-run
s_assert_status 2 "an inherited task ceiling that is not a whole number is refused"
s_assert_err_has "AGENT_DISPATCH_BUDGET_TASKS"
t_run_split env AGENT_DISPATCH_HOST_ROOT="$HOST" AGENT_DISPATCH_BUDGET_TASKS=777 \
	sh "$DISPATCH" implementer --prompt 'x' --dry-run
s_assert_status 2 "an inherited task ceiling with no memory ceiling beside it is refused"
s_assert_err_has "AGENT_DISPATCH_BUDGET_MEMORY_MIB"

# The rung is probed, not configured. A stub systemctl on PATH that answers
# stands in for a user service manager; one that fails stands in for none.
# A manager that answers is reachable, not necessarily able to bound: the
# scope rung also needs the pids and memory controllers delegated to it,
# read from cgroup.controllers on the dispatcher's own cgroup (ADR-0006
# clause 5).
SDBIN="$SCRATCH/sd-yes"; mkdir -p "$SDBIN"
printf '#!/bin/sh\nexit 0\n' >"$SDBIN/systemctl"; cp "$SDBIN/systemctl" "$SDBIN/systemd-run"; chmod +x "$SDBIN/systemctl" "$SDBIN/systemd-run"
CONTROLLERS="$SLICE/session-1.scope/cgroup.controllers"
echo 'cpu memory pids' >"$CONTROLLERS"
t_run_split env PATH="$SDBIN:$PATH" AGENT_DISPATCH_HOST_ROOT="$HOST" sh "$DISPATCH" implementer --prompt 'x' --dry-run
s_assert_out_has 'transient scope' "with a user service manager and both controllers the rung is a transient scope"
s_assert_out_has 'systemd-run --user --scope' "…and names the mechanism"
s_assert_out_has 'TasksMax and MemoryMax' "…carrying both ceilings"
echo 'cpu pids' >"$CONTROLLERS"
t_run_split env PATH="$SDBIN:$PATH" AGENT_DISPATCH_HOST_ROOT="$HOST" sh "$DISPATCH" implementer --prompt 'x' --dry-run
s_assert_out_has 'transient scope' "with pids delegated and memory not, the scope is still the rung — the task bound is the incident's"
s_assert_out_has 'memory controller is not delegated' "…and the dry run says the memory ceiling has no mechanism on this host"
s_assert_out_lacks 'TasksMax and MemoryMax' "…so it does not claim MemoryMax"
echo 'cpu' >"$CONTROLLERS"
t_run_split env PATH="$SDBIN:$PATH" AGENT_DISPATCH_HOST_ROOT="$HOST" sh "$DISPATCH" implementer --prompt 'x' --dry-run
s_assert_out_has 'rlimits' "with pids not delegated a scope bounds nothing that matters — the rung is rlimits"
s_assert_out_lacks 'transient scope' "…not a scope that would apply nothing"
rm -f "$CONTROLLERS"
t_run_split env PATH="$SDBIN:$PATH" AGENT_DISPATCH_HOST_ROOT="$HOST" sh "$DISPATCH" implementer --prompt 'x' --dry-run
s_assert_out_has 'rlimits' "an unreadable cgroup.controllers is treated as nothing delegated"
echo 'cpu memory pids' >"$CONTROLLERS"
NOSD="$SCRATCH/sd-no"; mkdir -p "$NOSD"
printf '#!/bin/sh\nexit 1\n' >"$NOSD/systemctl"; chmod +x "$NOSD/systemctl"
t_run_split env PATH="$NOSD:$PATH" AGENT_DISPATCH_HOST_ROOT="$HOST" sh "$DISPATCH" implementer --prompt 'x' --dry-run
s_assert_out_has 'rlimits' "without one the rung is rlimits"
s_assert_out_has 'weaker' "…and the dry run says that is the weaker promise"
s_assert_out_lacks 'transient scope' "…not the scope it cannot open"

# The real host, no fake root: the same code reads a real /proc and /sys.
dispatch implementer --prompt 'x' --dry-run
s_assert_out_has 'budget:' "the real host yields a budget line"
case "$S_OUT" in
*"tasks "[0-9]*) pass "…with a numeric task ceiling read from this host" ;;
*) fail "no numeric task ceiling on the real host"; printf '%s\n' "$S_OUT" | sed 's/^/        > /' ;;
esac
case "$S_OUT" in
*"memory "[0-9]*" MiB"*) pass "…and a numeric memory ceiling" ;;
*) fail "no numeric memory ceiling on the real host" ;;
esac

# CGSTUB reports what reached the worker: its cgroup, its rlimits, the
# dispatcher's own RLIMIT_NPROC (through /proc, walking up to the dispatch),
# and whether any of the scope wrapper's private names leaked into its
# environment.
CGSTUB="$SCRATCH/cg-stub"
cat >"$CGSTUB" <<'EOF'
#!/bin/sh
cat >/dev/null
echo "CG=$(sed -n 's/^0:://p' /proc/self/cgroup)"
echo "NPROC=$(ulimit -u 2>/dev/null || ulimit -p 2>/dev/null)"
echo "DATA=$(ulimit -d 2>/dev/null)"
echo "WRAPPER_ENV=[${SCOPE_STARTED:-}${SCOPE_VERDICT:-}${AGENT_DISPATCH_SCOPE_CMD:-}]"
p=$PPID
while [ "$p" -gt 1 ]; do
	if tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | grep -q 'agent-dispatch\.sh'; then
		echo "DISPATCHER_NPROC=$(awk '/^Max processes/ { print $3 }' "/proc/$p/limits")"
		break
	fi
	p=$(awk '{ print $4 }' "/proc/$p/stat")
done
EOF
chmod +x "$CGSTUB"
CFG_CG="$SCRATCH/cg.config.sh"
cat >"$CFG_CG" <<EOF
AGENT_HARNESSES='cg'
AGENT_HARNESS_CG_CMD='$CGSTUB {model_flag} < {prompt_file}'
AGENT_HARNESS_CG_MODEL_FLAG=''
AGENT_TIER_IMPLEMENTER='cg:'
EOF
# A real dispatch now APPLIES the budget (#208): a within-budget worker runs
# and exits 0, but it runs inside a transient scope rather than bare. The
# derived budget under the suite's own capped scope hits the task floor, which
# is announced — so this uses within-floor overrides to keep stderr about the
# run, not the floor, and asserts the worker ran unharmed.
AGENTS_CONFIG="$CFG_CG" dispatch implementer --prompt 'x' --budget-tasks 300 --budget-memory 600
s_assert_status 0 "a within-budget real dispatch runs the worker and exits 0"
s_assert_out_has 'CG=' "…the worker ran"
s_assert_err_lacks "hit its" "…and hit no ceiling"
s_assert_out_has 'WRAPPER_ENV=[]' "…and the scope wrapper's paths and command never reach the worker's environment"

# ---------------------------------------------------------------------------
banner "The budget is ENFORCED — a runaway worker stops, the session survives"
# ---------------------------------------------------------------------------
# ADR-0006 #208: the derived budget is now APPLIED down the ladder. These legs
# drive real runaways with SMALL budgets (--budget-tasks / --budget-memory, far
# below the floor, honoured as given) so they end in seconds. They need the
# scope rung, which a dry run on this host reports; where it is absent the
# scope-specific legs say they were skipped and the rlimit leg below still runs.
AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG
SCOPE_OK=0
t_run_split sh "$DISPATCH" implementer --prompt 'probe' --dry-run
case "$S_OUT" in *"transient scope"*) SCOPE_OK=1 ;; esac

if [ "$SCOPE_OK" = 1 ]; then
	# A stub that forks without bound (a bounded self-spawning sh loop whose peak
	# concurrency exceeds the ceiling) stops at the TASK budget. The dispatch
	# exits 71 and names the ceiling; a command in the calling shell right after
	# still forks. Every runaway here also carries a --timeout: the suite's own
	# capped scope is no backstop — a scope from inside a scope is a sibling —
	# so the watchdog is the one bound that owes nothing to the mechanism under
	# test.
	FORKER="$SCRATCH/forker"
	cat >"$FORKER" <<'EOF'
#!/bin/sh
cat >/dev/null
i=0
while [ $i -lt 400 ]; do
	sleep 2 &
	i=$((i + 1))
done
echo "forker finished its loop"
EOF
	chmod +x "$FORKER"
	CFG_FORK="$SCRATCH/forker.config.sh"
	cat >"$CFG_FORK" <<EOF
AGENT_HARNESSES='fk'
AGENT_HARNESS_FK_CMD='$FORKER {model_flag} < {prompt_file}'
AGENT_HARNESS_FK_MODEL_FLAG=''
AGENT_TIER_IMPLEMENTER='fk:'
EOF
	AGENTS_CONFIG="$CFG_FORK" dispatch implementer --prompt 'run away' --budget-tasks 64 --budget-memory 512 --timeout 30
	s_assert_status 71 "a task runaway stops at the budget and the dispatch exits 71"
	s_assert_err_has "TASK ceiling"
	# The whole point: the operator's own shell is unharmed.
	if sh -c 'exit 0'; then
		pass "a command in the calling shell right after the runaway still forks"
	else
		fail "the calling shell could not fork after the runaway — the budget did not contain it"
	fi

	# A stub that allocates past the MEMORY budget stops there with 71. The
	# allocation is self-bounding — 27 doublings, about 128 MiB, twice the 64
	# MiB budget — so where enforcement does not bite it ends on its own and
	# SAYS so, and the allocated-it-all line is a line the leg can fail on.
	# Only the greedy process is killed (OOMPolicy=continue — the kernel takes
	# the offender, not the tree), so the shell around it goes on; the verdict
	# is the counter, not the shell's fate.
	GREEDY="$SCRATCH/greedy"
	cat >"$GREEDY" <<'EOF'
#!/bin/sh
cat >/dev/null
echo "greedy begins"
awk 'BEGIN { s = "x"; for (i = 0; i < 27; i++) s = s s; print "greedy allocated it all" }'
echo "greedy went on after the allocation"
exit 0
EOF
	chmod +x "$GREEDY"
	CFG_GREEDY="$SCRATCH/greedy.config.sh"
	cat >"$CFG_GREEDY" <<EOF
AGENT_HARNESSES='gr'
AGENT_HARNESS_GR_CMD='$GREEDY {model_flag} < {prompt_file}'
AGENT_HARNESS_GR_MODEL_FLAG=''
AGENT_TIER_IMPLEMENTER='gr:'
EOF
	AGENTS_CONFIG="$CFG_GREEDY" dispatch implementer --prompt 'eat all' --budget-tasks 256 --budget-memory 64 --timeout 30
	s_assert_status 71 "a memory runaway stops at the budget and the dispatch exits 71"
	s_assert_err_has "MEMORY ceiling"
	s_assert_out_lacks "greedy allocated it all" "…the greedy process was OOM-killed before it finished"

	# --timeout and the budget COMPOSE: a worker that is both greedy and slow
	# exits with whichever fired first (ADR-0006 clause 6). Here the task budget
	# fires well inside a long timeout, so the verdict is 71, not 124.
	AGENTS_CONFIG="$CFG_FORK" dispatch implementer --prompt 'run away' --budget-tasks 64 --budget-memory 512 --timeout 40
	s_assert_status 71 "budget and --timeout compose — the budget fired first, so 71"
	s_assert_err_has "TASK ceiling"
else
	pass "this host offers no transient scope — the scope enforcement legs were skipped, and say so"
fi

# THE SCOPE RUNG IS DECIDED BEFORE THE SPAWN (ADR-0006 clause 5, "when the rung
# refuses at execution"). A pre-flight opens and closes an empty scope with the
# real properties; when systemd-run refuses there, the ladder falls to rlimits,
# loudly, and the worker runs ONCE under them. SDBIN (systemctl and systemd-run
# that both answer) with the HOST fixture's controllers stands in for a
# manager that passes every probe; a systemd-run that refuses stands in for
# one that will not open scopes.
SDREFUSE="$SCRATCH/sd-refuse"; mkdir -p "$SDREFUSE"
cp "$SDBIN/systemctl" "$SDREFUSE/systemctl"
printf '#!/bin/sh\necho "Failed to start transient scope unit: refused by fixture" >&2\nexit 1\n' >"$SDREFUSE/systemd-run"
chmod +x "$SDREFUSE/systemctl" "$SDREFUSE/systemd-run"
t_run_split env PATH="$SDREFUSE:$PATH" AGENT_DISPATCH_HOST_ROOT="$HOST" AGENTS_CONFIG="$CFG_CG" \
	sh "$DISPATCH" implementer --prompt 'x' --budget-tasks 5000 --budget-memory 128
s_assert_status 0 "a scope refused at the pre-flight falls to rlimits and the worker runs"
s_assert_err_has "refused by fixture"
s_assert_err_has "rlimit"
s_assert_out_has "NPROC=5000" "…under the rlimit rung's task ceiling"
[ "$(printf '%s\n' "$S_OUT" | grep -c '^CG=')" = 1 ] &&
	pass "…and the worker ran exactly once" ||
	fail "the worker ran $(printf '%s\n' "$S_OUT" | grep -c '^CG=') times"

# After the real spawn, a missing started-marker is reported, never retried: a
# systemd-run that passes the pre-flight and then runs nothing (SDBIN, which
# exits 0 and touches nothing) leaves the worker un-run — and the dispatch says
# so and passes the run's status through rather than running the worker a
# second time under a weaker rung. The marker is a file; a worker's tree or a
# sweep can remove one, and a re-run is the one thing this must never do.
t_run_split env PATH="$SDBIN:$PATH" AGENT_DISPATCH_HOST_ROOT="$HOST" AGENTS_CONFIG="$CFG_CG" \
	sh "$DISPATCH" implementer --prompt 'x' --budget-tasks 5000 --budget-memory 128
s_assert_status 0 "a spawn whose marker never appears passes the run's own status through"
s_assert_err_has "marker"
s_assert_out_lacks "CG=" "…and the worker is NOT run again under a weaker rung"
s_assert_err_lacks "rlimit rung instead"

# The OFF switch (ADR-0006 clause 4): --no-budget runs the worker unbounded,
# in the session's own cgroup, and says so on stderr on a REAL dispatch (not
# only the dry run — #208 lifted the note). A small --timeout keeps the leg
# bounded whatever the worker does.
TEST_CG=$(sed -n 's/^0:://p' /proc/self/cgroup)
AGENTS_CONFIG="$CFG_CG" dispatch implementer --prompt 'x' --no-budget --timeout 10
s_assert_status 0 "--no-budget runs the worker"
s_assert_err_has "no budget"
case "$S_OUT" in
*"CG=$TEST_CG"*) pass "--no-budget runs the worker in the session's own cgroup — no scope opened" ;;
*) fail "--no-budget opened a cgroup of its own: $(printf '%s' "$S_OUT" | grep CG=)" ;;
esac

# NESTING (ADR-0006 clause 7): a dispatch that finds the budget in its
# environment inherits it and OPENS NO SCOPE. A fake systemd-run on PATH records
# whether it was called; an inherited dispatch must never call it, and the
# worker runs in the caller's own cgroup.
SDREC="$SCRATCH/sd-record"; mkdir -p "$SDREC"
printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$SCRATCH/sd-was-called" >"$SDREC/systemd-run"
chmod +x "$SDREC/systemd-run"
rm -f "$SCRATCH/sd-was-called"
t_run_split env PATH="$SDREC:$PATH" AGENTS_CONFIG="$CFG_CG" \
	AGENT_DISPATCH_BUDGET_TASKS=500 AGENT_DISPATCH_BUDGET_MEMORY_MIB=500 \
	sh "$DISPATCH" implementer --prompt 'x'
s_assert_status 0 "an inherited dispatch runs the worker"
[ -f "$SCRATCH/sd-was-called" ] &&
	fail "an inherited dispatch opened a scope — systemd-run was called" ||
	pass "an inherited dispatch opens no scope — systemd-run was never called"
case "$S_OUT" in
*"CG=$TEST_CG"*) pass "…and the inherited worker runs in the caller's own cgroup" ;;
*) fail "the inherited worker did not run in the caller's cgroup: $(printf '%s' "$S_OUT" | grep CG=)" ;;
esac

# The RLIMIT rung (ADR-0006 ladder rung 2): with no user service manager the
# ladder falls to rlimits in the worker's shell. NOSD — a systemctl that
# answers nothing — is how "no manager" is simulated. The task bound is applied
# as `ulimit -u/-p` and the memory bound as `ulimit -d` (KiB) — proven by a
# stub that reports its own limits, a builtin that never forks, so a large safe
# task value can be asserted without risking this uid's own fork ceiling. A
# ceiling hit is not observable on this rung, so there is no 71 to assert.
t_run_split env PATH="$NOSD:$PATH" AGENTS_CONFIG="$CFG_CG" \
	sh "$DISPATCH" implementer --prompt 'x' --budget-tasks 5000 --budget-memory 128
s_assert_status 0 "the rlimit rung runs the worker"
s_assert_out_has "NPROC=5000" "…the task ceiling is applied as ulimit -u/-p in the worker's shell"
s_assert_out_has "DATA=131072" "…and the memory ceiling as ulimit -d (128 MiB = 131072 KiB)"
OWN_NPROC=$(ulimit -u 2>/dev/null || ulimit -p 2>/dev/null)
s_assert_out_has "DISPATCHER_NPROC=$OWN_NPROC" "…and the dispatcher's own shell keeps the limit it was given — the rung is the worker's, not the dispatcher's"
t_run_split env PATH="$NOSD:$PATH" AGENTS_CONFIG="$CFG_CG" \
	sh "$DISPATCH" implementer --prompt 'x' --dry-run
s_assert_out_has "rlimits" "…and a dry run with no user service manager names the rlimit rung"
s_assert_out_has "best-effort via rlimits" "…and says the rung is best-effort"
# The limits land in the WORKER's shell, on both spawn paths, and die with it
# (#208 acceptance line 4: "the task case still holds"). A fork loop under a
# task ceiling just above what this uid already runs is refused inside the
# worker's own shell — RLIMIT_NPROC counts every task of the uid, so the
# ceiling is the uid's thread count plus a margin, and the loop's own forks
# are what cross it. The dispatcher, in the shell that ran the limit-free
# dispatch, still forks: its cleanup trap removes the scratch, and a command
# in the calling shell right after succeeds. The status passes through (clause
# 6: nothing is observed on this rung), never 71 — and it is the shell's own
# verdict on its refused forks, which differs by shell: dash carries on and
# exits 0, bash retries, aborts and exits 254. The leg holds the status to
# "the worker's own", not to a number.
RLFORK="$SCRATCH/rl-forker"
cat >"$RLFORK" <<'EOF'
#!/bin/sh
cat >/dev/null
echo "rl-forker begins"
i=0
while [ $i -lt 60 ]; do
	sleep 1 &
	i=$((i + 1))
done
echo "rl-forker finished its loop"
EOF
chmod +x "$RLFORK"
CFG_RLFORK="$SCRATCH/rl-forker.config.sh"
cat >"$CFG_RLFORK" <<EOF
AGENT_HARNESSES='rf'
AGENT_HARNESS_RF_CMD='$RLFORK {model_flag} < {prompt_file}'
AGENT_HARNESS_RF_MODEL_FLAG=''
AGENT_TIER_IMPLEMENTER='rf:'
EOF
UID_TASKS=$(ps -u "$(id -u)" -o nlwp= | awk '{ s += $1 } END { print s + 0 }')
RL_TMP="$SCRATCH/rl-tmp"; mkdir -p "$RL_TMP"
t_run_split env PATH="$NOSD:$PATH" AGENTS_CONFIG="$CFG_RLFORK" TMPDIR="$RL_TMP" \
	sh "$DISPATCH" implementer --prompt 'run away' --budget-tasks $((UID_TASKS + 40)) --budget-memory 512
case "$S_STATUS" in
2 | 3 | 4 | 71 | 124) fail "a task runaway on the rlimit rung should pass the worker's own status through, got $S_STATUS"; _s_dump ;;
*) pass "a task runaway on the rlimit rung passes the worker's own status through ($S_STATUS) — not 71" ;;
esac
s_assert_err_has "fork"
s_assert_out_has "rl-forker begins" "…the worker ran, its forks refused inside its own shell"
if sh -c 'exit 0'; then
	pass "a command in the calling shell right after the runaway still forks"
else
	fail "the calling shell could not fork after the rlimit-rung runaway"
fi
[ -z "$(ls "$RL_TMP")" ] &&
	pass "…and the dispatcher's own shell still forked its cleanup — no scratch left behind" ||
	fail "the dispatcher could not fork its cleanup — the limit landed in its own shell: $(ls "$RL_TMP")"
# The timed path runs the string under sh, whatever shell runs the dispatcher;
# the flag is chosen where the ulimit runs, so dash and bash both apply it.
t_run_split env PATH="$NOSD:$PATH" AGENTS_CONFIG="$CFG_CG" \
	sh "$DISPATCH" implementer --prompt 'x' --budget-tasks 5000 --budget-memory 128 --timeout 10
s_assert_status 0 "the rlimit rung under --timeout runs the worker"
s_assert_out_has "NPROC=5000" "…and applies the task ceiling under the shell that runs the string"
s_assert_out_has "DATA=131072" "…and the memory ceiling"
s_assert_out_has "DISPATCHER_NPROC=$OWN_NPROC" "…while the dispatcher's own limit is untouched"

AGENTS_CONFIG="$CFG"
export AGENTS_CONFIG

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
	# The stdin rule, per shell: a worker with no redirect in its template
	# reads nothing from a pipe the dispatcher was given.
	s_out=$(printf hello | env AGENTS_CONFIG="$CFG_STDIN_NORED" "$shell_bin" "$DISPATCH" implementer --prompt 'x' 2>/dev/null)
	case "$s_out" in
	*"STDIN-BYTES=0"*) pass "$shell_bin gives the worker nothing from the dispatcher's stdin" ;;
	*) fail "$shell_bin let the worker read the dispatcher's stdin: $s_out" ;;
	esac
	# The case every consumer in the field is in.
	s_out=$("$shell_bin" "$DISPATCH" planner --prompt 'x' 2>/dev/null)
	s_st=$?
	{ [ "$s_st" = 3 ] && [ "$s_out" = "model-for-planning" ]; } &&
		pass "$shell_bin exits 3 with the model id for an unconfigured tier" ||
		fail "$shell_bin gave status $s_st, stdout '$s_out'"
	# The depth arithmetic, per shell — the one construct here with a known
	# shell divergence — and, separately, the refusal, which fires before
	# the arithmetic is reached.
	s_out=$(AGENTS_CONFIG="$CFG_DEPTH" AGENT_DISPATCH_DEPTH=2 "$shell_bin" "$DISPATCH" implementer --prompt 'x' 2>/dev/null)
	[ "$s_out" = "worker at depth 3" ] &&
		pass "$shell_bin spawns the worker one deeper than its dispatch" ||
		fail "$shell_bin spawned the worker at '$s_out'"
	s_out=$(AGENT_DISPATCH_DEPTH=4 "$shell_bin" "$DISPATCH" implementer --prompt 'x' 2>/dev/null)
	s_st=$?
	{ [ "$s_st" = 4 ] && [ -z "$s_out" ]; } &&
		pass "$shell_bin refuses a dispatch past the maximum depth with exit 4 and no worker" ||
		fail "$shell_bin gave status $s_st past the maximum depth, stdout '$s_out'"
done

unset AGENTS_CONFIG
t_done "agent dispatch"
