#!/bin/sh
# K5's acceptance test — the adapters tree.
#
# An adapter is reference material, not mechanism: nothing in `adapters/` runs
# in this repo, and the kit has no Node project to run it against. That is
# exactly why it needs a test. Two claims are made about this tree, both of them
# the kind that rot silently:
#
#   A. THE FILES ARE WELL-FORMED. Every shell file parses under `sh -n`, every
#      module parses under `node --check`, every config file really sets the
#      variables the guards read, and every regex is an ERE `grep -E` accepts.
#      A worked example with a syntax error is worse than no example: it is
#      copied, it fails, and the reader blames their own repo.
#
#   B. IT ARRIVES IN A CONSUMER DORMANT. bootstrap.sh does not copy out of
#      `adapters/`, does not delete it, and installs no workflow from it — and
#      the docs gate stays green with it present. That is the K5 decision
#      (adapters/node-ts/INSTALL.md, "Why bootstrap.sh does not touch this
#      directory") stated as a check rather than as prose, per shared
#      invariant §8.
#
# What this CANNOT prove is stated where it belongs, in INSTALL.md's
# "What is verified, and what is not": no Stryker run, no promptfoo run, no
# workflow parsed by GitHub. Nothing here pretends otherwise.
#
# Usage: sh tests/adapters-demo.sh

# tests/lib.sh pins collation and puts this suite under the worker budget (its
# header says how, and how to turn it off); the assertion helpers are this
# suite's own, so nothing else of the harness is used.
. "$(dirname "$0")/lib.sh"

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
# Scratch carries the harness's prefix (#221) rather than mktemp's anonymous
# default: a suite killed at its budget ceiling dies before its trap, and what
# it leaves must be identifiable by name alone.
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/${T_SCRATCH_PREFIX}XXXXXX") || exit 2
PROJ="$SCRATCH/demo-project"

trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP

failures=0
HAVE_NODE=0
command -v node >/dev/null 2>&1 && HAVE_NODE=1

check() {
	# check <label> -- <command...>
	_label=$1
	shift 2
	if out=$("$@" 2>&1); then
		pass "$_label"
	else
		fail "$_label"
		printf '%s\n' "$out" | sed 's/^/        | /'
	fi
}

cd "$KIT" || exit 2

# ---------------------------------------------------------------------------
banner "A1. Every adapter shell file parses (sh -n)"
# ---------------------------------------------------------------------------
# `.example` files included: they are copied verbatim into scripts/ and sourced
# from there, so a syntax error in one is a syntax error in the consumer.
found=0
for f in $(find adapters -name '*.sh' -o -name '*.sh.example' | sort); do
	found=$((found + 1))
	check "sh -n $f" -- sh -n "$f"
done
[ "$found" -gt 0 ] && pass "$found shell file(s) checked" ||
	fail "no shell files found under adapters/ — did the tree move?"

# ---------------------------------------------------------------------------
banner "A2. Every adapter module parses (node --check)"
# ---------------------------------------------------------------------------
if [ "$HAVE_NODE" = 1 ]; then
	found=0
	for f in $(find adapters \( -name '*.mjs' -o -name '*.js' -o -name '*.mjs.example' \) | sort); do
		found=$((found + 1))
		# node --check reads the module goal from the extension, and `.example`
		# has none it knows. Copy to a real extension first.
		tmp="$SCRATCH/$(basename "${f%.example}")"
		cp "$f" "$tmp"
		check "node --check $f" -- node --check "$tmp"
	done
	[ "$found" -gt 0 ] && pass "$found module(s) checked" ||
		fail "no modules found under adapters/ — did the tree move?"
else
	skip "node is not available — module syntax checks skipped"
fi

# ---------------------------------------------------------------------------
banner "A3. The guards config example really configures the guards"
# ---------------------------------------------------------------------------
# Sourcing it and reading the variables back is the only honest check: a config
# file that parses but sets nothing would leave the pairing guard INACTIVE while
# looking installed, which is the failure mode the whole file exists to prevent.
GUARDS_EXAMPLE="adapters/node-ts/guards.config.sh.example"
(
	# shellcheck source=/dev/null
	. "./$GUARDS_EXAMPLE"
	[ -n "${GUARD_SOURCE_RE:-}" ] || exit 1
	[ -n "${GUARD_TEST_RE:-}" ] || exit 2
	[ -n "${GUARD_SOURCE_EXCLUDE_RE:-}" ] || exit 3
	[ -n "${BEHAVIOR_DELTA_SURFACES:-}" ] || exit 4
	# Valid EREs, judged by the same grep the guards use.
	printf 'x\n' | grep -E "$GUARD_SOURCE_RE" >/dev/null 2>&1
	[ $? -gt 1 ] && exit 5
	printf 'x\n' | grep -E "$GUARD_TEST_RE" >/dev/null 2>&1
	[ $? -gt 1 ] && exit 6
	printf 'x\n' | grep -E "$GUARD_SOURCE_EXCLUDE_RE" >/dev/null 2>&1
	[ $? -gt 1 ] && exit 7
	exit 0
)
case $? in
0) pass "$GUARDS_EXAMPLE sets all four settings, and its regexes are valid ERE" ;;
1) fail "$GUARDS_EXAMPLE leaves GUARD_SOURCE_RE empty — the guard would stay INACTIVE" ;;
2) fail "$GUARDS_EXAMPLE leaves GUARD_TEST_RE empty — the guard would exit 2" ;;
3) fail "$GUARDS_EXAMPLE leaves GUARD_SOURCE_EXCLUDE_RE empty" ;;
4) fail "$GUARDS_EXAMPLE leaves BEHAVIOR_DELTA_SURFACES empty" ;;
*) fail "$GUARDS_EXAMPLE carries a regex grep -E rejects" ;;
esac

# The example must match the trees it documents, and must NOT match a test file
# (the guard subtracts tests, but a SOURCE pattern that swallows them is still
# a smell worth catching here).
(
	# shellcheck source=/dev/null
	. "./$GUARDS_EXAMPLE"
	printf 'packages/domain/src/policy.ts\n' | grep -qE "$GUARD_SOURCE_RE" || exit 1
	printf 'apps/web/src/handler.ts\n' | grep -qE "$GUARD_SOURCE_RE" || exit 2
	printf 'docs/diary.md\n' | grep -qE "$GUARD_SOURCE_RE" && exit 3
	printf 'packages/domain/src/policy.test.ts\n' | grep -qE "$GUARD_TEST_RE" || exit 4
	printf 'packages/domain/src/index.ts\n' | grep -qE "$GUARD_SOURCE_EXCLUDE_RE" || exit 5
	exit 0
)
case $? in
0) pass "its patterns classify a source file, an app file, a doc, a test and a barrel correctly" ;;
*) fail "its patterns misclassify at least one of: source / app / doc / test / barrel" ;;
esac

# ---------------------------------------------------------------------------
banner "A4. The mutation config example really configures the diagnostic"
# ---------------------------------------------------------------------------
MUTATION_EXAMPLE="adapters/node-ts/mutation/mutation.config.sh.example"
(
	# shellcheck source=/dev/null
	. "./$MUTATION_EXAMPLE"
	[ -n "${MUTATION_PKG_DIR:-}" ] || exit 1
	[ -n "${MUTATION_PKG_NAME:-}" ] || exit 2
	[ -n "${MUTATION_REPORT:-}" ] || exit 3
	printf 'x\n' | grep -E "${MUTATION_SRC_RE:-}" >/dev/null 2>&1
	[ $? -gt 1 ] && exit 4
	printf 'src/policy.ts\n' | grep -qE "$MUTATION_SRC_RE" || exit 5
	printf 'src/index.ts\n' | grep -qE "$MUTATION_SRC_EXCLUDE_RE" || exit 6
	exit 0
)
case $? in
0) pass "$MUTATION_EXAMPLE sets a scope, a report path, and patterns that classify correctly" ;;
*) fail "$MUTATION_EXAMPLE is incomplete or its patterns misclassify" ;;
esac

# mutation-delta.sh must REFUSE to run with no config rather than guessing a
# package — a silent default here would measure the wrong tree and report a
# score for it.
out=$(MUTATION_CONFIG=/nonexistent/mutation.config.sh sh adapters/node-ts/mutation/mutation-delta.sh --list 2>&1)
if [ $? = 2 ] && printf '%s' "$out" | grep -q 'does not exist'; then
	pass "mutation-delta.sh errors (exit 2) on an explicit config that does not exist"
else
	fail "mutation-delta.sh did not reject a missing explicit MUTATION_CONFIG"
	printf '%s\n' "$out" | sed 's/^/        | /'
fi

# ---------------------------------------------------------------------------
banner "A5. The ruby adapter keeps its field notes and its shape"
# ---------------------------------------------------------------------------
# The ruby adapter's chief value is the reasoning left in: two structural
# blind spots of its mutation tool that read as catastrophic coverage when
# the tests are fine (issue #85). Lose the notes and the adapter is a config
# file; lose the table row and the adapter is invisible.
RUBY_README="adapters/ruby/README.md"
if grep -q 'Data\.define' "$RUBY_README" 2>/dev/null &&
	grep -q 'module_function' "$RUBY_README" 2>/dev/null; then
	pass "$RUBY_README carries both mutant blind-spot field notes"
else
	fail "$RUBY_README lost a field note (Data.define / module_function) — the 1.5%-coverage trap is unexplained again"
fi

if grep -q 'opensource' "$RUBY_README" 2>/dev/null; then
	pass "$RUBY_README records the licence posture (opensource usage)"
else
	fail "$RUBY_README never mentions the opensource usage mode — the first run dies on licensing instead of mutants"
fi

if grep -qE '^\| \[`ruby/`\]' adapters/README.md 2>/dev/null; then
	pass "adapters/README.md's table has the ruby row"
else
	fail "adapters/README.md's table has no ruby row — the adapter exists but the index does not say so"
fi

# ---------------------------------------------------------------------------
banner "A6. The Claude Code adapter says how a typed-return reader is denied its tools"
# ---------------------------------------------------------------------------
# Three skills (/to-tickets, /pr-iterate, /dogfood) fence an untrusted read
# behind a reader that has "no shell, no forge CLI, no network", and each one
# defers the HOW to the adapter: "How an agent harness withholds those tools is
# the adapter's, not this skill's, to say". A pointer with nothing at the other
# end is a claim (shared invariant §8), so this block holds both ends: the
# adapter names the mechanism for each of its two spawn paths, and the skills
# still point at it. Two paths because they are not the same kind of thing —
# the CLI's tool flags are a RESTRICTION, and a prompt to the in-session agent
# tool is a REQUEST — and the section must say which is which (#335).
#
# Every assertion below is on the SECTION, cut out of the README first, so a
# phrase the rest of a 400-line note happens to carry cannot keep one green.
CC_README="adapters/claude-code/README.md"
cc_sec=$(sed -n '/^## Denying a typed-return reader/,/^## Wiring/p' "$CC_README")
cc_low=$(printf '%s' "$cc_sec" | tr -d '`' | tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]')
# cc_says <phrase, case-insensitive, backticks ignored> <pass> <fail> — one
# stanza for the section's prose; what it must say, in the words a reader of
# the skills will look for.
cc_says() {
	case $cc_low in
	*"$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"*) pass "$2" ;;
	*) fail "$3" ;;
	esac
}

if [ -n "$cc_sec" ]; then
	pass "$CC_README has a section on the typed-return reader"
else
	fail "$CC_README has no section on the typed-return reader — the skills defer to an adapter that says nothing"
fi

# The flags, by their real names on the CLI this adapter wires (`claude
# --help`: "--tools <tools...>  Specify the list of available tools from the
# built-in set"; "--restricted … confines the file tools to the working
# directories"; "--strict-mcp-config  Only use MCP servers from --mcp-config"),
# and ON THE ONE LINE a reader copies: the `claude -p` line of the fenced sh
# block. Prose that names a flag three paragraphs away from the line sends the
# reader to a line without it, so each flag is asserted on that line itself —
# a per-line match, not a glob over the flattened note.
cc_cmd=$(printf '%s\n' "$cc_sec" | grep -E '^claude -p ')
if [ -n "$cc_cmd" ] && [ "$(printf '%s\n' "$cc_cmd" | grep -c '')" -eq 1 ]; then
	pass "…and has exactly one \`claude -p\` line in its fenced sh block, the headless form the fence spawns"
else
	fail "…but has $(printf '%s' "$cc_cmd" | grep -c '') \`claude -p\` lines in its fenced sh block — the reader needs one line to copy"
fi
for flag in '--restricted' '--tools Read' '--strict-mcp-config'; do
	case " $cc_cmd " in
	*" $flag "*) pass "…and that line carries $flag" ;;
	*) fail "…but that line does not carry $flag — a reader that copies it keeps what the flag withholds" ;;
	esac
done

# What each flag does is quoted from the CLI's own help, not paraphrased, so a
# release that changes a flag's meaning is a diff against a quote and not a
# drift nobody notices. `--restricted` is the one that confines Read to the
# working directory — the confinement `--tools Read` alone does not give —
# and it goes WITH `--tools`, not instead of it.
cc_says 'confines the file tools to the working directories' \
	"…and quotes --restricted's own help: it confines the file tools to the working directories" \
	"…but never quotes what --restricted does — the confinement of Read to \$scratch is asserted, not shown"
cc_says '--restricted goes with --tools' \
	"…and says --restricted goes with --tools, not instead of it" \
	"…but never says --restricted goes with --tools Read"

# The flag that looks like it and is not: `--allowedTools` is the permission
# allowlist, which pre-approves and withholds nothing. A reader spawned with it
# keeps the shell, so the section must name it and say what it fails to do.
cc_says '--allowedTools' \
	"…and names --allowedTools, the flag that looks like the restriction" \
	"…but does not name \`--allowedTools\` — the flag that looks like the restriction and is not"
cc_says 'withholds nothing' \
	"…and says it withholds nothing" \
	"…but does not say \`--allowedTools\` withholds nothing"

# The read is still a read of whatever is in reach, and what makes that safe is
# the FENCE the skills put around the return — typed lines and one evidence
# span verified against the scratch file — not the flag. The section must say
# so, in those terms, so nobody reads the flag as the whole of the boundary.
cc_says 'one evidence span' \
	"…and names the fence — the typed return and its one evidence span — as what the flags are used together with" \
	"…but never names the fence (the typed return and its one evidence span) beside the flags"

# The in-session path: the Agent tool's spawn call takes no tool list, so a
# skill run inside a session can only ASK — unless it runs the CLI line above
# itself, from the shell every session holds, which is the recommended path.
# The section must say the prompt-only spawn is a request, say that the CLI
# from inside the session is the way out, and keep the fence's duty for when
# it cannot: "say so at the quiz" (/to-tickets) and "say so in the report"
# (/pr-iterate, /dogfood) — the fallback's own words, not a bare "in the
# report" any later prose could carry.
# One name per concept (review of PR #440, M-2): the skills say "a restricted
# path through the agent CLI", so the adapter names its path the same way.
cc_says 'the restricted path' \
	"…and names the path by the skills' name: the restricted path" \
	"…but never names the restricted path — the skills' name for it, one name per concept"
cc_says 'request, not a restriction' \
	"…and says the in-session prompt is a request, not a restriction" \
	"…but never says plainly that the in-session prompt is a request, not a restriction"
cc_says 'from inside the session' \
	"…and recommends spawning the reader with the CLI from inside the session" \
	"…but does not recommend the CLI from inside the session"
cc_says 'prompt-only spawn is the fallback' \
	"…with the prompt-only spawn as the fallback" \
	"…but does not make the prompt-only spawn the fallback"
cc_says 'say so at the quiz' \
	"…and carries the fallback /to-tickets requires: say so at the quiz" \
	"…but does not carry \"say so at the quiz\" — /to-tickets's fallback is unstated"
cc_says 'say so in the report' \
	"…and the one /pr-iterate and /dogfood require: say so in the report" \
	"…but does not carry \"say so in the report\" — /pr-iterate's and /dogfood's fallback is unstated"

# A dispatched reader (scripts/agent-dispatch.sh) runs the command template the
# consumer wrote, AGENT_HARNESS_<TOKEN>_CMD; the kit writes no flag into it. So
# the section may not claim the restriction is real on that path unless it
# says where the flags go: the template.
cc_says 'AGENT_HARNESS_' \
	"…and says a dispatched reader's flags live in the AGENT_HARNESS_<TOKEN>_CMD template, which the kit does not write" \
	"…but says nothing about where a dispatched reader's flags go — agent-dispatch.sh adds none of its own"

# The index row in adapters/README.md names the topic, so a reader who starts
# at the index finds the section — one grep beside the ruby-row check above.
if grep -E '^\| \[`claude-code/`\]' adapters/README.md | grep -q 'typed-return reader'; then
	pass "adapters/README.md's claude-code row names the typed-return reader"
else
	fail "adapters/README.md's claude-code row does not name the typed-return reader — the index does not say the section exists"
fi

# The other end of the pointer: each of the three skills still defers to the
# adapter in the one sentence the section above answers. Lose it from a skill
# and the adapter's section documents a mechanism nothing invokes.
for s in to-tickets pr-iterate dogfood; do
	sk=".agents/skills/$s/SKILL.md"
	if tr '\n' ' ' <"$sk" | tr -s ' ' | grep -q "How an agent harness withholds those tools is the adapter's, not this skill's, to say"; then
		pass "$sk still defers the how to the adapter"
	else
		fail "$sk no longer says how the tools are withheld is the adapter's to say — the pointer this section answers is gone"
	fi
done

# ---------------------------------------------------------------------------
banner "A7. The Claude Code adapter offers one agent type per tier (spend/R4, spend/R5, spend/R24)"
# ---------------------------------------------------------------------------
# A spawn that names no agent type inherits the catch-all one, with every tool
# the harness has. The adapter ships one type per capability tier instead,
# each declaring the tools that tier's work needs and NO model: the model is
# the resolver's answer at spawn time (ADR-0003, ADR-0013), so a model line in
# a type would be a second, unrecorded mapping that outranks the policy file.
# The lists below are the decision, held here and recorded with each reason in
# the adapter's README ("One agent type per tier") — the suite and the README
# move together.
TYPES_DIR="$KIT/adapters/claude-code/agents"

# fm_field <file> <key> — the value of a frontmatter key, or empty.
fm_field() {
	awk -v k="$2" '
		NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
		fm && /^---[[:space:]]*$/ { exit }
		fm && index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[[:space:]]+/, "", v); print v; exit }
	' "$1"
}
# fm_has <file> <key> — the frontmatter carries the key at all.
fm_has() {
	awk -v k="$2" '
		NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
		fm && /^---[[:space:]]*$/ { exit }
		fm && index($0, k ":") == 1 { found = 1; exit }
		END { exit !found }
	' "$1"
}

for spec in \
	'planner|Read, Grep, Glob, Bash, Edit, Write, Skill, Agent' \
	'implementer|Read, Grep, Glob, Bash, Edit, Write, Skill, Agent' \
	'mechanical|Read, Grep, Glob, Bash, Edit, Write, Skill' \
	'reviewer|Read, Grep, Glob'; do
	tier=${spec%%|*}
	want=${spec#*|}
	f="$TYPES_DIR/$tier.md"
	if [ ! -f "$f" ]; then
		fail "adapters/claude-code/agents/$tier.md is missing — the $tier tier has no agent type (spend/R4)"
		continue
	fi
	[ "$(fm_field "$f" name)" = "$tier" ] &&
		pass "$tier.md names itself '$tier' — the tier word is the type's name" ||
		fail "$tier.md's name is '$(fm_field "$f" name)', not '$tier'"
	[ -n "$(fm_field "$f" description)" ] &&
		pass "$tier.md carries a description" ||
		fail "$tier.md has no description — the harness lists the type with nothing to choose it by"
	# An absent tools line is the dangerous default: the type then inherits
	# every tool, which is the catch-all this ticket exists to replace.
	got=$(fm_field "$f" tools)
	[ "$got" = "$want" ] &&
		pass "$tier.md declares exactly: $want (spend/R4)" ||
		fail "$tier.md declares tools '$got', not '$want' — change the README's table and this list together (spend/R4)"
	fm_has "$f" model &&
		fail "$tier.md carries a model line — the model is the resolver's answer at spawn time (spend/R4, spend/R24)" ||
		pass "$tier.md carries no model line (spend/R4)"
	t_assert_no_model_id "$f"
done

n=$(find "$TYPES_DIR" -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = 4 ] && pass "exactly four agent types — one per tier" ||
	fail "$n agent types under adapters/claude-code/agents — expected four, one per tier"

# The reviewer reads untrusted content (a diff, a ticket) and judges it. It
# holds nothing that writes a file, reaches the network, calls a tool server
# or spawns another agent that could: Bash is all three, so it is out too,
# and the spawner hands the reviewer its diff as a file to read.
if [ -f "$TYPES_DIR/reviewer.md" ]; then
	rtools=$(fm_field "$TYPES_DIR/reviewer.md" tools)
	for bad in Write Edit NotebookEdit Bash WebFetch WebSearch Agent Task 'mcp__'; do
		case ", $rtools," in
		*", $bad"*) fail "the reviewer type carries $bad — it may not write, reach the network or call a tool server (spend/R5)" ;;
		*) pass "the reviewer type carries no $bad (spend/R5)" ;;
		esac
	done
fi

# The README records each type's tools and why, and names the directory.
CC_TYPES_README="$KIT/adapters/claude-code/README.md"
if grep -q '^## One agent type per tier' "$CC_TYPES_README"; then
	pass "the adapter README has its 'One agent type per tier' section"
	for tier in planner implementer mechanical reviewer; do
		sed -n '/^## One agent type per tier/,/^## [^O]/p' "$CC_TYPES_README" | grep -q "^| \`$tier\` |" &&
			pass "the README's table has a row for $tier" ||
			fail "the README's table has no row for $tier — the decision is not recorded where it is read"
	done
else
	fail "the adapter README has no 'One agent type per tier' section — the tool lists are not recorded with their reasons"
fi

# ---------------------------------------------------------------------------
banner "A8. The chain's spawns take their tier's agent type (spend/R6, spend/R7)"
# ---------------------------------------------------------------------------
# The types above are worth nothing until a spawn names one. /implement and
# /review-pr say so in their spawn instructions, by tier, with the resolver's
# model beside it (none: the spawn inherits); the dispatcher's dry run says it
# too (tests/skill-phase.test.sh, 4e). A harness that offers no such type
# spawns as before, which is why each sentence is conditioned on the offer.
# The /review-pr coordinator /implement spawns is the one spawn not on its
# tier's type: it runs a skill, fans out its lenses and posts, which the
# reviewer type's read-only envelope cannot, so it takes the planner type on
# the reviewer tier's model — recorded in the adapter's README.
flat() { tr '\n' ' ' <"$KIT/.agents/skills/$1/SKILL.md" | tr -s ' '; }
for spec in \
	'implement|as the agent type named for its tier' \
	'implement|the `planner` agent type' \
	'review-pr|as the `reviewer` agent type'; do
	s=${spec%%|*} want=${spec#*|}
	case "$(flat "$s")" in
	*"$want"*) pass "/$s's spawn instruction names it: '$want' (spend/R6)" ;;
	*) fail "/$s's spawn instruction no longer says '$want' — its spawns fall back to the catch-all type (spend/R6)" ;;
	esac
done
case "$(flat review-pr)" in
*"as files to read"*) pass "/review-pr hands its read-only lenses the diff as files to read" ;;
*) fail "/review-pr no longer says its lenses get the diff as files to read — a reviewer-type lens has no shell to fetch it" ;;
esac

# THIS repo's own sessions spawn by type, so its .claude/agents links each
# tier's type in from the adapter — one source, never a copy that drifts.
# Kit-only: bootstrap strips the links (B2 below), so a consumer's adapter
# still arrives dormant.
for tier in planner implementer mechanical reviewer; do
	l="$KIT/.claude/agents/$tier.md"
	if [ -L "$l" ] && [ "$(readlink "$l")" = "../../adapters/claude-code/agents/$tier.md" ] && [ -f "$l" ]; then
		pass ".claude/agents/$tier.md links the adapter's $tier type"
	else
		fail ".claude/agents/$tier.md is not a resolving link to ../../adapters/claude-code/agents/$tier.md"
	fi
done

# ---------------------------------------------------------------------------
banner "B. Setup — simulate 'Use this template'"
# ---------------------------------------------------------------------------
mkdir -p "$PROJ"
cp -R "$KIT/." "$PROJ/"
rm -rf "$PROJ/.git"
cd "$PROJ" || exit 2

git init -q -b main
git config user.name "Adapters Demo"
git config user.email "demo@example.invalid"
git config commit.gpgsign false
git add -A
pass "fresh repo at \$SCRATCH/demo-project"

# ---------------------------------------------------------------------------
banner "B1. bootstrap leaves adapters/ INTACT"
# ---------------------------------------------------------------------------
if out=$(sh bootstrap.sh "Adapters Demo" "A throwaway project proving adapters arrive dormant." 2>&1); then
	pass "bootstrap.sh runs"
else
	fail "bootstrap.sh failed"
	printf '%s\n' "$out" | sed 's/^/        | /'
fi

for f in \
	adapters/README.md \
	adapters/claude-code/README.md \
	adapters/codex/README.md \
	adapters/gemini-cli/README.md \
	adapters/node-ts/README.md \
	adapters/node-ts/INSTALL.md \
	adapters/node-ts/guards.config.sh.example \
	adapters/node-ts/mutation/mutation-delta.sh \
	adapters/node-ts/mutation/mutation-delta-report.mjs \
	adapters/node-ts/mutation/stryker.config.mjs.example \
	adapters/node-ts/evals/promptfooconfig.yaml \
	adapters/node-ts/workflows/mutation-delta.yml \
	adapters/node-ts/workflows/prompt-evals.yml \
	adapters/ruby/README.md \
	adapters/ruby/mutant.yml.example; do
	[ -f "$f" ] && pass "$f survived bootstrap" || fail "$f is missing after bootstrap"
done

if grep -qE '^\| \[`codex/`\]' adapters/README.md 2>/dev/null &&
	grep -q 'codex-cli 0.159.0' adapters/codex/README.md 2>/dev/null &&
	grep -q 'advisory' adapters/codex/README.md 2>/dev/null &&
	grep -q '/hooks' adapters/codex/README.md 2>/dev/null; then
	pass 'the Codex adapter indexes its observed version and advisory hook boundary'
else
	fail 'the Codex adapter is absent from the index or overstates its runtime boundary'
fi

# The whole tree, byte for byte: an adapter that arrived STAMPED would mean
# bootstrap had quietly claimed it as its own.
if diff -r "$KIT/adapters" adapters >/dev/null 2>&1; then
	pass "adapters/ is byte-identical to the kit's — nothing stamped, nothing removed"
else
	fail "adapters/ differs from the kit's copy after bootstrap"
	diff -r "$KIT/adapters" adapters 2>&1 | sed 's/^/        | /'
fi

# ---------------------------------------------------------------------------
banner "B2. Nothing from adapters/ was installed or activated"
# ---------------------------------------------------------------------------
for wf in mutation-delta.yml prompt-evals.yml; do
	[ -e ".github/workflows/$wf" ] &&
		fail ".github/workflows/$wf was installed — adapters must not auto-activate" ||
		pass ".github/workflows/$wf was NOT installed (dormant, as designed)"
done

# The Claude Code adapter's trace hooks SHIP — they are under adapters/, which
# arrives intact — and they must arrive UNWIRED. The only thing that wires them
# is a settings file, and the kit's own is kit-authoring only (bootstrap's
# KIT_ONLY list, ADR-0008 clause 8). A consumer inheriting it would have three
# session hooks pointing at a trace policy file the strip has already deleted.
[ -e ".claude/settings.json" ] &&
	fail ".claude/settings.json reached the project — the kit's own agent-harness wiring leaked, and the adapter is not dormant" ||
	pass "no .claude/settings.json in the project — the trace hooks arrived unwired"
[ -e ".claude/agents" ] &&
	fail ".claude/agents reached the project — the kit's own agent-type wiring leaked, and the adapter is not dormant" ||
	pass "no .claude/agents in the project — the agent types arrived unwired"
for h in hook.lib.sh session-start.sh session-end.sh subagent-stop.sh tool-post.sh \
	tool-pre-guard.sh tool-pre.sh transcript-usage.mjs tool-payload.mjs; do
	[ -f "adapters/claude-code/hooks/$h" ] &&
		pass "adapters/claude-code/hooks/$h survived bootstrap (reference material, dormant)" ||
		fail "adapters/claude-code/hooks/$h is missing after bootstrap"
done

[ ! -e .codex ] && pass 'no .codex settings or hooks were installed' ||
	fail '.codex reached the project — the Codex adapter is not dormant'
[ "$(find adapters/codex -type f | wc -l | tr -d ' ')" = 1 ] &&
	pass 'the Codex adapter ships documentation only, with no trusted hook definition' ||
	fail 'the Codex adapter contains an active artifact beyond its README'

# The guards must still be INACTIVE: the adapter ships a filled-in config, and
# if bootstrap ever copied it over scripts/guards.config.sh it would be
# enforcing a layout this project does not have.
if grep -q "^GUARD_SOURCE_RE=''" scripts/guards.config.sh; then
	pass "scripts/guards.config.sh is still the kit's unconfigured copy"
else
	fail "scripts/guards.config.sh was replaced — the adapter's config leaked into the project"
fi

# ---------------------------------------------------------------------------
banner "B3. The docs gate stays green with adapters/ present"
# ---------------------------------------------------------------------------
# The gate scans EVERY file in the repo for unstamped placeholders, adapters
# included. A double-brace mark in an adapter file would fail a consumer's gate
# on day one, for a directory they never touched.
if out=$(sh scripts/check.sh 2>&1); then
	pass "scripts/check.sh passes with adapters/ in the tree"
else
	fail "scripts/check.sh fails with adapters/ in the tree"
	printf '%s\n' "$out" | sed 's/^/        | /'
fi

if [ "$HAVE_NODE" = 1 ]; then
	if out=$(DOCS_CHECK_NO_NODE=1 sh scripts/check.sh 2>&1); then
		pass "the POSIX fallback passes too"
	else
		fail "the POSIX fallback fails with adapters/ in the tree"
		printf '%s\n' "$out" | sed 's/^/        | /'
	fi
fi

# ---------------------------------------------------------------------------
banner "B4. The gate fails an agent type that names a model (spend/R24)"
# ---------------------------------------------------------------------------
# Three plants, one rule: a model line in a type's frontmatter (spelled as
# the harness writes it, and spaced or capitalised, since a key the gate
# misses by spelling is a key the harness may still read), and a model
# identifier anywhere in its body. Each must turn the project's gate red under
# both engines — the check is POSIX and runs in either — and naming the file.
# The identifier is assembled from parts so this suite carries none.
fam=sonnet
plant_line="model: $fam"
plant_id="claude-$fam-9-9"
for plant in line spaced id; do
	case "$plant" in
	line) body="---
name: rogue
description: a fixture type that names a model
tools: Read
$plant_line
---
A fixture.
" ;;
	spaced) body="---
name: rogue
description: a fixture type that names a model
tools: Read
Model : $fam
---
A fixture.
" ;;
	id) body="---
name: rogue
description: a fixture type that names a model
tools: Read
---
Spawn this on $plant_id.
" ;;
	esac
	mkdir -p adapters/claude-code/agents
	printf '%s' "$body" >adapters/claude-code/agents/rogue.md
	for engine in node posix; do
		[ "$engine" = node ] && [ "$HAVE_NODE" = 0 ] && continue
		if [ "$engine" = posix ]; then
			out=$(DOCS_CHECK_NO_NODE=1 sh scripts/check.sh 2>&1)
		else
			out=$(sh scripts/check.sh 2>&1)
		fi
		st=$?
		if [ "$st" = 1 ] && printf '%s' "$out" | grep -q 'agent-type-model' &&
			printf '%s' "$out" | grep -q 'adapters/claude-code/agents/rogue.md'; then
			pass "the gate ($engine) fails a type whose $plant names a model, naming the file (spend/R24)"
		else
			fail "the gate ($engine) did not fail a type whose $plant names a model (status $st)"
			printf '%s\n' "$out" | tail -8 | sed 's/^/        | /'
		fi
	done
done
rm -f adapters/claude-code/agents/rogue.md
if out=$(DOCS_CHECK_NO_NODE=1 sh scripts/check.sh 2>&1); then
	pass "the plant removed, the gate is green again"
else
	fail "the gate stays red with the plant removed"
	printf '%s\n' "$out" | tail -8 | sed 's/^/        | /'
fi

# ---------------------------------------------------------------------------
printf '\n'
if [ "$failures" = 0 ]; then
	printf '  ALL GREEN — adapters demo\n'
	exit 0
fi
printf '  %s check(s) failed — adapters demo\n' "$failures"
exit 1
