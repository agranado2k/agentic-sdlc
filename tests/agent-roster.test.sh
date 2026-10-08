#!/bin/sh
# tests/agent-roster.test.sh — bootstrap's agent-roster question, and the
# trace question asked beside it (section 7).
#
# scripts/agents.config.sh ships EMPTY and stays empty until somebody reads its
# comments, so a fresh project runs every tier on the session's own model and
# the tier mechanism decides nothing. This asks once, at the moment the operator
# is already answering questions about their project.
#
# THE RULE THIS SUITE EXISTS TO PROTECT is that the prompt ASKS and never
# SUGGESTS. The kit names no model identifier anywhere — they rot on a vendor's
# schedule — and a suggestion inside the prompt of the tool built to prevent
# that rot would be the worst possible place for one. So the suite reads
# bootstrap.sh itself and holds it to carrying no model id, the same way the
# tier suite refuses to name one.
#
# NOT ASKING IS A WORKING STATE, and most of what follows checks that: no
# terminal, or --no-agents, and the file is untouched and the project starts
# exactly where every project started before this existed.
#
# THE TRACE QUESTION (#654) sits beside it for the same reason: a consumer
# whose scripts/trace.config.sh shipped empty ran a whole wave and recorded
# nothing, and nothing ever asked. Section 7 drives it both ways on a terminal,
# unattended through both flags, and with no terminal at all — and holds the
# next-steps text to naming the decision whenever it was left off.
#
# Usage: sh tests/agent-roster.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

CONFIG=scripts/agents.config.sh

# fresh_project — an unstamped copy of the kit to bootstrap, minus nested
# worktrees, as t_kit_tree gives the other bootstrap suites.
fresh_project() {
	PROJ=$(mktemp -d "$SCRATCH/proj.XXXXXX") || exit 2
	t_kit_tree "$KIT" "$PROJ"
	# A real repo, hermetic: bootstrap wires a hooks path and the kit's own arm
	# expects to be inside version control. Same shape mk_project builds in the
	# opt-in suite, for the same reason.
	t_git_identity "$PROJ" "Roster Fixture" "fixture@example.invalid"
}

tier_line() { grep "^AGENT_TIER_$1=" "$PROJ/$CONFIG" | head -1; }

# HAVE_PTY — the terminal legs need one, and the kit's suites are otherwise
# POSIX sh and git. Where python3 is absent those legs are SKIPPED and say so,
# rather than printing ok for something that did not run.
HAVE_PTY=0
command -v python3 >/dev/null 2>&1 && HAVE_PTY=1
: >"$SCRATCH/answers.none"

# run_bootstrap_pty <project> <answers file> [bootstrap flags...] — drive a real
# bootstrap on a pty, feeding one line per prompt.
#
# The driver must never outlive the test. An earlier version fed a fixed list
# and then blocked in waitpid: one question short — which any new optional-skill
# prompt would cause — and it hung until something external killed it, in CI,
# forever. So: --no-dogfood pins the question count, a hard deadline bounds the
# run, and the child is killed and reaped without blocking.
run_bootstrap_pty() {
	_rp_proj=$1
	_rp_answers=$2
	shift 2
	python3 - "$_rp_proj" "$_rp_answers" "$@" <<'PY' >"$SCRATCH/pty.log" 2>&1
import os, pty, select, signal, sys, time

proj, answers_path = sys.argv[1], sys.argv[2]
flags = sys.argv[3:]
with open(answers_path) as fh:
    answers = [ln.rstrip("\n") + "\n" for ln in fh]

argv = ["sh", "bootstrap.sh", "--no-dogfood", *flags, "Demo Roster", "A project."]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(proj)
    os.execvp("sh", argv)

out = b""
i = 0
deadline = time.time() + 60
while time.time() < deadline:
    try:
        r, _, _ = select.select([fd], [], [], 0.3)
    except OSError:
        break
    if r:
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        out += data
    elif i < len(answers):
        try:
            os.write(fd, answers[i].encode())
        except OSError:
            break
        i += 1
    elif b"Bootstrapped" in out or b"Next:" in out:
        break

# Kill first, reap second, and never block on either: a child still sitting on
# the pty is what turned a short answer list into a hung job.
for sig in (signal.SIGTERM, signal.SIGKILL):
    # The process GROUP, not just the child: pty.fork() makes the child a
    # session leader and bootstrap runs subshells, so signalling the pid alone
    # can leave grandchildren holding the pty open.
    try:
        os.killpg(os.getpgid(pid), sig)
    except (ProcessLookupError, PermissionError, OSError):
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            break
    for _ in range(20):
        try:
            done, _ = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            done = pid
        if done:
            break
        time.sleep(0.05)
    else:
        continue
    break
try:
    os.close(fd)
except OSError:
    pass
sys.stdout.write(out.decode(errors="replace"))
PY
}

# ---------------------------------------------------------------------------
banner "1. The prompt exists, takes both flags, and names no model"
# ---------------------------------------------------------------------------
assert_file_has "$KIT/bootstrap.sh" "--with-agents" "the non-interactive yes"
assert_file_has "$KIT/bootstrap.sh" "--no-agents" "the non-interactive no"
assert_file_has "$KIT/bootstrap.sh" "--with-trace" "the trace question's unattended yes"
assert_file_has "$KIT/bootstrap.sh" "--no-trace" "the trace question's unattended no"

# The load-bearing rule. A model identifier in bootstrap.sh would be a standing
# instruction with a timer on it, shipped in the prompt of the tool that exists
# to stop exactly that. The shapes below are the ones a real roster would use.
if grep -nEi '(claude|gpt|gemini|llama|mistral|sonnet|opus|haiku|fable)-[0-9]' "$KIT/bootstrap.sh" >/dev/null 2>&1; then
	fail "bootstrap.sh names something shaped like a model identifier — the kit names none"
	grep -nEi '(claude|gpt|gemini|llama|mistral|sonnet|opus|haiku|fable)-[0-9]' "$KIT/bootstrap.sh" | sed 's/^/        | /'
else
	pass "bootstrap.sh names nothing shaped like a model identifier"
fi

# The same rule, one level up. A hardcoded list of vendor CLIs to look for on
# PATH is still the kit asserting which agent harnesses exist in the world —
# ADR-0005 driver 2 forbids naming a vendor's command line in the same breath
# as a model id. The operator names their own, as they name their own models.
if grep -nE "command -v [\"']?(claude|codex|gemini|opencode|cursor|aider)" "$KIT/bootstrap.sh" >/dev/null 2>&1; then
	fail "bootstrap.sh probes PATH for named vendor CLIs — the kit names no agent harness either"
	grep -nE "command -v [\"']?(claude|codex|gemini|opencode|cursor|aider)" "$KIT/bootstrap.sh" | sed 's/^/        | /'
else
	pass "bootstrap.sh names no vendor CLI to probe for"
fi

# ---------------------------------------------------------------------------
banner "2. --no-agents and no-terminal both write nothing"
# ---------------------------------------------------------------------------
fresh_project
if (cd "$PROJ" && sh bootstrap.sh --no-agents "Demo No" "A project." </dev/null >/dev/null 2>&1); then
	pass "bootstrap --no-agents runs"
else
	fail "bootstrap --no-agents failed"
fi
for t in PLANNER IMPLEMENTER MECHANICAL REVIEWER; do
	line=$(tier_line "$t")
	[ "$line" = "AGENT_TIER_$t=''" ] &&
		pass "AGENT_TIER_$t is still empty after --no-agents" ||
		fail "AGENT_TIER_$t was written: $line"
done
line=$(grep "^AGENT_HARNESSES=" "$PROJ/$CONFIG" | head -1)
[ "$line" = "AGENT_HARNESSES=''" ] &&
	pass "AGENT_HARNESSES is still empty after --no-agents" ||
	fail "AGENT_HARNESSES was written: $line"

fresh_project
(cd "$PROJ" && sh bootstrap.sh "Demo Quiet" "A project." </dev/null >/dev/null 2>&1)
line=$(tier_line IMPLEMENTER)
[ "$line" = "AGENT_TIER_IMPLEMENTER=''" ] &&
	pass "with no terminal the question is skipped and nothing is written" ||
	fail "something was written with no terminal: $line"

# ---------------------------------------------------------------------------
banner "4. With a terminal: the flags decide, and the answers are written"
# ---------------------------------------------------------------------------
# These legs NEED a terminal, and that is the point. Without one the wizard
# returns early for a reason that has nothing to do with the flags, so a leg
# run headless proves nothing about them: deleting the --no-agents return
# outright left the earlier version of this suite fully green. A check whose
# failure path cannot be reached is a claim.
if [ "$HAVE_PTY" = 1 ]; then
	# --no-agents, WITH a terminal: the flag is the only thing that can stop
	# the question now.
	# The answers below WOULD be written if the flag were ignored — that is the
	# whole point. Feeding an empty file instead would make "nothing was
	# written" true whether the flag worked or not, which is how the first
	# version of this leg passed while the flag's early return was deleted.
	fresh_project
	cat >"$SCRATCH/answers.none" <<'PY_ANSWERS'

would-have-been-written
stubharness
also-written




PY_ANSWERS
	run_bootstrap_pty "$PROJ" "$SCRATCH/answers.none" --no-agents --no-trace
	line=$(tier_line PLANNER)
	[ "$line" = "AGENT_TIER_PLANNER=''" ] &&
		pass "--no-agents suppresses the question even with answers waiting on a terminal" ||
		fail "--no-agents did not suppress it: $line"
	line=$(grep "^AGENT_HARNESSES=" "$PROJ/$CONFIG" | head -1)
	[ "$line" = "AGENT_HARNESSES=''" ] &&
		pass "…and declares nothing" ||
		fail "AGENT_HARNESSES was written: $line"

	# --with-agents skips the yes/no and goes straight to the tiers, so the
	# answer file carries no "y".
	fresh_project
	# Eight prompts: an agent harness and a model for each of the four tiers,
	# in order. A blank line is a real answer — "no opinion here".
	cat >"$SCRATCH/answers.with" <<'PY_ANSWERS'

planner-id
stubharness
implementer-id


otherharness
reviewer-id
PY_ANSWERS
	run_bootstrap_pty "$PROJ" "$SCRATCH/answers.with" --with-agents --no-trace
	line=$(tier_line PLANNER)
	[ "$line" = "AGENT_TIER_PLANNER='planner-id'" ] &&
		pass "--with-agents asks the tiers without the yes/no question" ||
		fail "--with-agents wrote planner as: $line"
	line=$(tier_line IMPLEMENTER)
	[ "$line" = "AGENT_TIER_IMPLEMENTER='stubharness:implementer-id'" ] &&
		pass "a tier answered with an agent harness is written prefixed" ||
		fail "implementer was written as: $line"
	line=$(tier_line MECHANICAL)
	[ "$line" = "AGENT_TIER_MECHANICAL=''" ] &&
		pass "a tier the operator skipped stays empty — unmapped is a working state" ||
		fail "mechanical was written as: $line"
	line=$(grep "^AGENT_HARNESSES=" "$PROJ/$CONFIG" | head -1)
	case "$line" in
	*stubharness*otherharness* | *otherharness*stubharness*)
		pass "every agent harness the operator named is declared, once each" ;;
	*) fail "AGENT_HARNESSES was written as: $line" ;;
	esac

	# ---------------------------------------------------------------------
	banner "5. A tier the project already mapped is not even asked about"
	# ---------------------------------------------------------------------
	# Asking and discarding is worse than not asking: the operator types a
	# considered choice, nothing records it, and the agent harness they named
	# was still declared — leaving a file naming a harness no tier used.
	fresh_project
	sed "s|^AGENT_TIER_PLANNER=''|AGENT_TIER_PLANNER='already-chosen'|" \
		"$PROJ/$CONFIG" >"$PROJ/$CONFIG.tmp" && mv "$PROJ/$CONFIG.tmp" "$PROJ/$CONFIG"
	# Six prompts, not eight: planner is already mapped and is not asked about,
	# which is the behaviour under test.
	cat >"$SCRATCH/answers.filled" <<'PY_ANSWERS'
stubharness
implementer-id




PY_ANSWERS
	run_bootstrap_pty "$PROJ" "$SCRATCH/answers.filled" --with-agents --no-trace
	line=$(tier_line PLANNER)
	[ "$line" = "AGENT_TIER_PLANNER='already-chosen'" ] &&
		pass "a value the project already chose survives, untouched" ||
		fail "a chosen value was clobbered: $line"
	line=$(tier_line IMPLEMENTER)
	[ "$line" = "AGENT_TIER_IMPLEMENTER='stubharness:implementer-id'" ] &&
		pass "…while the tiers below it are still asked and written" ||
		fail "implementer was written as: $line"
	line=$(grep "^AGENT_HARNESSES=" "$PROJ/$CONFIG" | head -1)
	case "$line" in
	*stubharness*) pass "the declaration names the agent harness that was actually written" ;;
	*) fail "AGENT_HARNESSES was written as: $line" ;;
	esac

	# ---------------------------------------------------------------------
	banner "6. The writer only ever fills a blank"
	# ---------------------------------------------------------------------
	# With already-mapped tiers now skipped before the writer is reached, the
	# `^VAR=''` anchor is only exercised through the DECLARATION — which a
	# project may also have filled. Loosening the anchor to `^VAR=` would
	# rewrite it, so this is the leg that holds the rule.
	fresh_project
	sed "s|^AGENT_HARNESSES=''|AGENT_HARNESSES='pre-existing'|" \
		"$PROJ/$CONFIG" >"$PROJ/$CONFIG.tmp" && mv "$PROJ/$CONFIG.tmp" "$PROJ/$CONFIG"
	run_bootstrap_pty "$PROJ" "$SCRATCH/answers.with" --with-agents --no-trace
	line=$(grep "^AGENT_HARNESSES=" "$PROJ/$CONFIG" | head -1)
	[ "$line" = "AGENT_HARNESSES='pre-existing'" ] &&
		pass "a declaration the project already wrote is not rewritten" ||
		fail "the existing declaration was clobbered: $line"
else
	skip "no python3 — the terminal legs (flags, writing, the already-mapped case) are NOT covered on this machine"
fi

# ---------------------------------------------------------------------------
banner "7. The trace question: asked, flagged, or said to be unasked (#654)"
# ---------------------------------------------------------------------------
# scripts/trace.config.sh still SHIPS empty (the kit's ADR-0008, as amended):
# what changed is that a project decides it on day one. A yes writes the
# directory the stamped .gitignore already covers; a no, a --no-trace and a
# run with no terminal leave it empty — and each of those says so in the
# next-steps text, so "off" is never inherited by silence.
trace_line() { grep '^TRACE_DIR=' "$PROJ/scripts/trace.config.sh" | head -1; }
OUT="$SCRATCH/trace.out"

# trace_says_off <output file> <what> — the next-steps text names the decision
# AND how to reverse it; trace_says_on the opposite.
trace_says_off() {
	if grep -q 'The trace is OFF' "$1" && grep -q 'day-one decision' "$1" &&
		grep -qF "TRACE_DIR='.trace'" "$1"; then
		pass "$2: the next-steps text names the trace as a day-one decision, and how to turn it on"
	else
		fail "$2: the next-steps text does not name the trace decision"
		sed 's/^/        | /' "$1" | tail -25
	fi
}
trace_says_on() {
	if grep -q 'The trace is ON' "$1" && ! grep -q 'The trace is OFF' "$1"; then
		pass "$2: the next-steps text says the trace is on"
	else
		fail "$2: the next-steps text does not say the trace is on"
		sed 's/^/        | /' "$1" | tail -25
	fi
}

# Unattended, no terminal and no flag: nothing written, and it SAYS it was not
# asked — the case the consumer who traced nothing was in.
fresh_project
(cd "$PROJ" && sh bootstrap.sh --no-agents "Demo Trace Quiet" "A project." </dev/null >"$OUT" 2>&1)
[ "$(trace_line)" = "TRACE_DIR=''" ] &&
	pass "with no terminal the trace policy file stays empty" ||
	fail "something was written with no terminal: $(trace_line)"
grep -q 'trace question was not asked' "$OUT" &&
	pass "…and bootstrap says the question was not asked" ||
	fail "bootstrap left the trace off with no terminal and did not say it was not asked"
trace_says_off "$OUT" "no terminal"

# The stamped ignore file: the trace directory a yes writes is covered, and the
# comment over it describes the consumer's own policy file — never a kit-only
# file, which bootstrap has just deleted from this very tree.
if git -C "$PROJ" check-ignore -q .trace/probe; then
	pass "the stamped .gitignore covers the trace directory a yes writes"
else
	fail "the stamped .gitignore does not ignore .trace/"
fi
kit_only=$(sed -n 's/^KIT_ONLY="\(.*\)"$/\1/p' "$KIT/bootstrap.sh")
leaked=''
for f in $kit_only; do
	grep -qF "$f" "$PROJ/.gitignore" && leaked="$leaked $f"
done
grep -qE '[a-z-]+\.kit\.[a-z.]+' "$PROJ/.gitignore" && leaked="$leaked $(grep -oE '[a-z/-]+\.kit\.[a-z.]+' "$PROJ/.gitignore" | tr '\n' ' ')"
[ -n "$kit_only" ] && [ -z "$leaked" ] &&
	pass "the stamped .gitignore names no kit-only file" ||
	fail "the stamped .gitignore names a kit-only file:${leaked:- (or KIT_ONLY could not be read)}"
grep -q 'scripts/trace.config.sh' "$PROJ/.gitignore" &&
	pass "…and its trace comment names the project's own trace policy file" ||
	fail "the stamped .gitignore's trace comment does not name scripts/trace.config.sh"

# Unattended through the flags: --with-trace needs no terminal, because the
# answer is the whole question.
fresh_project
(cd "$PROJ" && sh bootstrap.sh --no-agents --with-trace "Demo Trace Yes" "A project." </dev/null >"$OUT" 2>&1)
[ "$(trace_line)" = "TRACE_DIR='.trace'" ] &&
	pass "--with-trace writes the trace directory, unattended" ||
	fail "--with-trace wrote: $(trace_line)"
trace_says_on "$OUT" "--with-trace"

fresh_project
(cd "$PROJ" && sh bootstrap.sh --no-agents --no-trace "Demo Trace No" "A project." </dev/null >"$OUT" 2>&1)
[ "$(trace_line)" = "TRACE_DIR=''" ] &&
	pass "--no-trace leaves the trace policy file empty" ||
	fail "--no-trace wrote: $(trace_line)"
grep -q 'trace question was not asked' "$OUT" &&
	fail "--no-trace was reported as not asked — it was answered" ||
	pass "…and is reported as answered, not as unasked"
trace_says_off "$OUT" "--no-trace"

# On a terminal: the question itself, both ways, and the flag stopping it with
# a yes waiting. One answer each — --no-agents keeps the roster's prompts out.
if [ "$HAVE_PTY" = 1 ]; then
	printf 'y\n' >"$SCRATCH/answers.trace-yes"
	printf 'n\n' >"$SCRATCH/answers.trace-no"

	fresh_project
	run_bootstrap_pty "$PROJ" "$SCRATCH/answers.trace-yes" --no-agents
	grep -q 'Trace the chain' "$SCRATCH/pty.log" &&
		pass "on a terminal the trace question is asked" ||
		fail "no trace question appeared on the terminal"
	[ "$(trace_line)" = "TRACE_DIR='.trace'" ] &&
		pass "a yes on the terminal writes the trace directory" ||
		fail "a yes wrote: $(trace_line)"
	trace_says_on "$SCRATCH/pty.log" "a terminal yes"

	fresh_project
	run_bootstrap_pty "$PROJ" "$SCRATCH/answers.trace-no" --no-agents
	[ "$(trace_line)" = "TRACE_DIR=''" ] &&
		pass "a no on the terminal leaves it empty" ||
		fail "a no wrote: $(trace_line)"
	trace_says_off "$SCRATCH/pty.log" "a terminal no"

	# The yes is WAITING — so an empty line is the flag's doing, not a quiet run's.
	fresh_project
	run_bootstrap_pty "$PROJ" "$SCRATCH/answers.trace-yes" --no-agents --no-trace
	[ "$(trace_line)" = "TRACE_DIR=''" ] &&
		pass "--no-trace suppresses the question even with a yes waiting on a terminal" ||
		fail "--no-trace did not suppress it: $(trace_line)"
else
	skip "no python3 — the trace question's terminal legs are NOT covered on this machine"
fi

t_done "agent roster"
