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
# maximum dies before it resolves the tier — with a status of its own (4: 0
# dispatched, 2 usage, 3 in-session, 124 timed out) so a caller can tell a
# refusal from anything a worker exits with.
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
s_assert_out_lacks 'ARGV:' "…running nothing"

# A depth or a maximum that is not a whole number from 1 is a usage error,
# not a guess: 0 would refuse every dispatch, and a top-level one is depth 1.
t_run_split env AGENT_DISPATCH_DEPTH=abc sh "$DISPATCH" implementer --prompt 'x'
s_assert_status 2 "a malformed AGENT_DISPATCH_DEPTH is refused as a usage error"
s_assert_err_has "AGENT_DISPATCH_DEPTH"
t_run_split env AGENT_DISPATCH_DEPTH=0 sh "$DISPATCH" implementer --prompt 'x'
s_assert_status 2 "AGENT_DISPATCH_DEPTH=0 is refused — a top-level dispatch is depth 1"
CFG_DEPTH0="$SCRATCH/depth0.config.sh"
{ cat "$CFG"; printf "AGENT_DISPATCH_MAX_DEPTH='0'\n"; } >"$CFG_DEPTH0"
t_run_split env AGENTS_CONFIG="$CFG_DEPTH0" sh "$DISPATCH" implementer --prompt 'x'
s_assert_status 2 "AGENT_DISPATCH_MAX_DEPTH=0 is refused — it would refuse every dispatch"
s_assert_err_has "AGENT_DISPATCH_MAX_DEPTH"

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
