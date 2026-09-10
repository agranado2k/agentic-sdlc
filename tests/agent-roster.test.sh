#!/bin/sh
# tests/agent-roster.test.sh — bootstrap's agent-roster question.
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

# ---------------------------------------------------------------------------
banner "1. The prompt exists, takes both flags, and names no model"
# ---------------------------------------------------------------------------
assert_file_has "$KIT/bootstrap.sh" "--with-agents" "the non-interactive yes"
assert_file_has "$KIT/bootstrap.sh" "--no-agents" "the non-interactive no"

# The load-bearing rule. A model identifier in bootstrap.sh would be a standing
# instruction with a timer on it, shipped in the prompt of the tool that exists
# to stop exactly that. The shapes below are the ones a real roster would use.
if grep -nEi '(claude|gpt|gemini|llama|mistral|sonnet|opus|haiku|fable)-[0-9]' "$KIT/bootstrap.sh" >/dev/null 2>&1; then
	fail "bootstrap.sh names something shaped like a model identifier — the kit names none"
	grep -nEi '(claude|gpt|gemini|llama|mistral|sonnet|opus|haiku|fable)-[0-9]' "$KIT/bootstrap.sh" | sed 's/^/        | /'
else
	pass "bootstrap.sh names nothing shaped like a model identifier"
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
banner "3. The writer only ever fills the shipped-empty form"
# ---------------------------------------------------------------------------
# A project that has already mapped its tiers must not have them overwritten by
# a second run — re-running the wizard over a filled policy file is the
# operator's business to sort out, not something to do behind their back.
fresh_project
sed -i.bak "s|^AGENT_TIER_PLANNER=''|AGENT_TIER_PLANNER='already-chosen'|" "$PROJ/$CONFIG" && rm -f "$PROJ/$CONFIG.bak"
(cd "$PROJ" && sh bootstrap.sh --no-agents "Demo Kept" "A project." </dev/null >/dev/null 2>&1)
line=$(tier_line PLANNER)
[ "$line" = "AGENT_TIER_PLANNER='already-chosen'" ] &&
	pass "a value the project already chose survives bootstrap" ||
	fail "a chosen value was clobbered: $line"

# ---------------------------------------------------------------------------
banner "4. Answering the prompt writes the roster"
# ---------------------------------------------------------------------------
# The read loop needs a terminal, so this leg drives one. It is CONDITIONAL:
# the kit's suites are POSIX sh and git, and a pty needs more than that. Where
# python3 is absent the leg says so and passes rather than pretending.
if command -v python3 >/dev/null 2>&1; then
	fresh_project
	python3 - "$PROJ" <<'PY' >/dev/null 2>&1
import os, pty, sys, select, time
proj = sys.argv[1]
answers = [
    "Demo Roster\n", "A project.\n",   # name, description
    "n\n",                             # the /dogfood question
    "y\n",                             # map the tiers now?
    "\n", "planner-id\n",              # planner: this session's own harness
    "stubharness\n", "implementer-id\n",
    "\n", "\n",                        # mechanical: skipped entirely
    "otherharness\n", "reviewer-id\n",
]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(proj)
    os.execvp("sh", ["sh", "bootstrap.sh"])
out = b""; i = 0; deadline = time.time() + 90
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.4)
    if r:
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        out += data
    elif i < len(answers):
        os.write(fd, answers[i].encode()); i += 1
    elif b"Bootstrapped" in out:
        break
try:
    os.waitpid(pid, 0)
except Exception:
    pass
PY
	line=$(tier_line PLANNER)
	[ "$line" = "AGENT_TIER_PLANNER='planner-id'" ] &&
		pass "a tier answered with no agent harness is written bare" ||
		fail "planner was written as: $line"
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
else
	pass "python3 is absent — the terminal leg is skipped, and says so"
fi

t_done "agent roster"
