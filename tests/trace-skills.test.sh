#!/bin/sh
# tests/trace-skills.test.sh — every chain skill emits at its decision points,
# and no skill ever reads the trace back.
#
# ADR-0008 decides that the chain WRITES the decision trace and never reads it
# (clause 7, shared invariant §4: a reviewer must not see implementation
# history), and that an emit is never load-bearing (clause 4: every call site
# tolerates failure). Ticket #250 of PRD #237 gives each of the thirteen chain
# skills one emit line per decision point. A skill is a document, so — the same
# honest boundary as tests/implement-deliver.test.sh — the external behavior IS
# the text, and this suite pins the tokens an agent following the document
# must run; it never simulates a session.
#
# What it holds every chain skill to:
#   1. The plain script name, `sh scripts/trace.sh …`, and never the kit's
#      never-shipped wrapper: skills ship unstamped to every consumer, so none
#      of them may name a kit-only file. In THIS repo a session substitutes
#      the wrapper by hand (root manual, hard rule 10).
#   2. Every emit, begin and end ends in `|| :` — the trace changes no skill's
#      outcome, whatever the trace does.
#   3. Never `show`, `summary` or `export` — the chain does not read its own
#      history. Held over EVERY skill directory, chain or not, with ONE named
#      exception: /retro, the sanctioned reader (ADR-0008 clause 7, #254),
#      which the same rule holds to the opposite — it MUST read.
#   4. Every kind a skill emits is one scripts/trace.sh knows: the vocabulary is
#      closed, and a skill that emits an unknown kind emits nothing.
#   5. The decision points themselves: the plan's table of one kind per
#      decision, per skill (PRD #237, "Skills: one emit line per decision
#      point"), plus the `feedback` kind the PRD's re-evaluation added to
#      /merge-train and /pr-iterate with its three verdicts.
#   6. /review-pr resolves the reviewer tier ONCE, before its sub-agents, and
#      records a spawn per agent carrying that model and the agent's name.
#   7. Every documented line RUNS: each `sh scripts/trace.sh …` span, with a
#      literal in place of every <placeholder> and the [optionals] dropped, is
#      executed in file order against a scratch trace and exits 0, and what it
#      wrote verifies. A placeholder that stands for prose gets a two-word
#      literal, so an unquoted `reason=<one line>` — exit 2 at the script,
#      swallowed by `|| :` — is red here instead of a silent hole in every
#      consumer's trace (review of PR #286, H-1).
#
# The thirteen are the chain the root manual draws (spec → tickets →
# implementation → review → landing) plus the skills that step out of it and
# decide something. /grill-with-docs, /explain-diff, /dogfood and
# /improve-codebase-architecture are outside this suite on purpose: the ticket
# (#250) sized the thirteen; a grill.decision from /grill-with-docs is a
# candidate ticket, not an oversight this suite should hide.
#
# Every case is driven RED first (hard rule 9): the suite was written against
# skills that emitted nothing and a script that knew no `feedback`.
#
# Usage: sh tests/trace-skills.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

cd "$ROOT" || exit 2

CHAIN="grill-me to-prd to-tickets implement tdd review-pr pr-iterate merge-train diagnose prototype housekeeping design-brief worktree-cleanup"
SKILLS=".agents/skills"
TRACE="scripts/trace.sh"

skill_md() { printf '%s/%s/SKILL.md' "$SKILLS" "$1"; }

# The span tokeniser and the placeholder filler are tests/lib.sh's
# (t_trace_lines, t_trace_spans, t_trace_runnable): held once, shared with
# tests/retro-skill.test.sh.

# ---------------------------------------------------------------------------
banner "0. The files under test, and the vocabulary they are held to"
# ---------------------------------------------------------------------------
KINDS=$(sed -n "s/^TRACE_KINDS='\(.*\)'\$/\1/p" "$ROOT/$TRACE")
[ -n "$KINDS" ] && pass "$TRACE names its closed kind vocabulary ($(printf '%s\n' "$KINDS" | wc -w | tr -d ' ') kinds)" ||
	fail "$TRACE has no TRACE_KINDS line — rule 4 has nothing to check against"
n_chain=0
for s in $CHAIN; do
	if [ -f "$(skill_md "$s")" ]; then n_chain=$((n_chain + 1)); else fail "$(skill_md "$s") is missing"; fi
done
[ "$n_chain" = 13 ] && pass "all thirteen chain skills exist" || fail "only $n_chain of 13 chain skills exist"

# ---------------------------------------------------------------------------
banner "1. Every chain skill emits, by the plain script name — never the kit wrapper"
# ---------------------------------------------------------------------------
for s in $CHAIN; do
	f=$(skill_md "$s")
	n=$(t_trace_lines "$f" | wc -l | tr -d ' ')
	[ "$n" -gt 0 ] && pass "/$s runs sh $TRACE ($n lines)" || fail "/$s never runs sh $TRACE — a chain skill with no emit leaves a hole the retrospective reads as a fact"
done
# Over EVERY skill directory: a sidecar that names the wrapper ships too.
for d in "$SKILLS"/*/; do
	s=$(basename "$d")
	if grep -rqF 'trace.kit.sh' "$d"; then
		fail "/$s names trace.kit.sh — a kit-only file, deleted by bootstrap; a consumer following this line runs nothing"
	else
		pass "/$s never names the kit wrapper"
	fi
done

# ---------------------------------------------------------------------------
banner "2. An emit is never load-bearing: every emit, begin and end ends in '|| :'"
# ---------------------------------------------------------------------------
for s in $CHAIN; do
	f=$(skill_md "$s")
	bare=$(grep -nE "sh scripts/trace\\.sh +(emit|begin|end)" "$f" | grep -vF '|| :' || true)
	if [ -z "$bare" ]; then
		pass "/$s: every trace call tolerates failure"
	else
		fail "/$s has a trace call with no '|| :' — ADR-0008 clause 4: a trace error must not become an exit status a skill acts on:"
		printf '%s\n' "$bare" | sed 's/^/        | /'
	fi
	# A span wrapped across two lines by a prose reflow would vanish from every
	# line-oriented rule here in silence; hold each span to its line.
	open=$(grep -n '`sh scripts/trace\.sh' "$f" | grep -vE '`sh scripts/trace\.sh[^`]*`' || true)
	[ -z "$open" ] && pass "/$s: every trace span closes on the line it opens" ||
		{ fail "/$s has a trace span that runs past its line — the rules above cannot see it:"; printf '%s\n' "$open" | sed 's/^/        | /'; }
done

# ---------------------------------------------------------------------------
banner "3. The chain never reads the trace: no show, summary or export in any skill but the reader"
# ---------------------------------------------------------------------------
# The exclusion is explicit and named: ADR-0008 clause 7 makes the
# retrospective the reader, so /retro is held to reading and every other
# skill to not. A second name here would be a second reader, and that is a
# decision record's to make, not this list's.
READER=retro
for d in "$SKILLS"/*/; do
	s=$(basename "$d")
	reads=$(grep -rnE "trace\.sh +(show|summary|export)\b" "$d" || true)
	if [ "$s" = "$READER" ]; then
		[ -n "$reads" ] && pass "/$s is the one sanctioned reader, and reads (show, summary, export)" ||
			fail "/$s is the sanctioned reader and never reads the trace — the exclusion is dead"
		continue
	fi
	if [ -z "$reads" ]; then
		pass "/$s never reads the trace"
	else
		fail "/$s reads the trace — ADR-0008 clause 7, shared invariant §4: no skill calls show, summary or export; the trace is read after the fact, by the operator or the retrospective:"
		printf '%s\n' "$reads" | sed 's/^/        | /'
	fi
done

# ---------------------------------------------------------------------------
banner "4. Every kind a skill emits is one the script knows"
# ---------------------------------------------------------------------------
for s in $CHAIN; do
	f=$(skill_md "$s")
	for k in $(t_trace_lines "$f" | grep -oE 'kind=[a-z][a-z.]*' | sed 's/^kind=//' | sort -u); do
		case " $KINDS " in
		*" $k "*) pass "/$s emits $k, which $TRACE knows" ;;
		*) fail "/$s emits kind=$k, which $TRACE does not know — the vocabulary is closed, and this emit would be exit 2" ;;
		esac
	done
done

# ---------------------------------------------------------------------------
banner "5. The decision points: one emit per decision, per skill"
# ---------------------------------------------------------------------------
# expects <skill> <token>… — each token appears on one of the skill's trace
# lines. `begin` and `end` are subcommands; a `kind=` token is an emit; a
# `data.x=` or `--blob` token is a field the emit must carry.
expects() {
	_ex_s=$1; shift
	_ex_f=$(skill_md "$_ex_s")
	_ex_lines=$(t_trace_lines "$_ex_f")
	for _ex_tok; do
		case $_ex_tok in
		begin | end) _ex_needle="sh $TRACE $_ex_tok" ;;
		*) _ex_needle=$_ex_tok ;;
		esac
		printf '%s\n' "$_ex_lines" | grep -qF -- "$_ex_needle" &&
			pass "/$_ex_s records $_ex_tok" ||
			fail "/$_ex_s does not record $_ex_tok on any trace line"
	done
}
expects grill-me kind=grill.decision
expects to-prd kind=prd.write
expects to-tickets kind=ticket.write tier= data.tier_proposed= data.blocked_by= data.label=
expects implement begin kind=ticket.start kind=spawn model= kind=pr.open end
expects tdd kind=tdd.cycle data.test=
expects review-pr begin kind=spawn data.agent= kind=finding.raise kind=review.verdict end
expects pr-iterate begin kind=finding.triage kind=pr.iterate kind=feedback end
expects merge-train begin kind=merge.land kind=feedback end data.tag=
expects diagnose begin kind=hypothesis end
expects prototype kind=spike.verdict --blob
expects housekeeping kind=housekeeping.finding
expects design-brief kind=brief.decide
expects worktree-cleanup kind=worktree.prune

# The feedback verdicts are a three-word vocabulary both emitters share.
for s in merge-train pr-iterate; do
	f=$(skill_md "$s")
	fb=$(grep -F 'kind=feedback' "$f")
	for v in hit adjusted missed; do
		printf '%s\n' "$fb" | grep -qw "$v" && pass "/$s's feedback names the verdict '$v'" ||
			fail "/$s's feedback line does not name the verdict '$v' — the vocabulary is hit|adjusted|missed"
	done
done

# ---------------------------------------------------------------------------
banner "6. /review-pr resolves the reviewer tier once, before the seven sub-agents"
# ---------------------------------------------------------------------------
RP=$(skill_md review-pr)
resolves=$(grep -c 'sh scripts/agents.lib.sh reviewer' "$RP" | tr -d ' ')
[ "$resolves" = 1 ] && pass "/review-pr resolves the reviewer tier exactly once" ||
	fail "/review-pr resolves the reviewer tier $resolves times — once, before the sub-agents, so every spawn records the same answer"
r_line=$(grep -n 'sh scripts/agents.lib.sh reviewer' "$RP" | head -1 | cut -d: -f1)
a1_line=$(grep -n '^#### Agent 1' "$RP" | head -1 | cut -d: -f1)
if [ -n "$r_line" ] && [ -n "$a1_line" ] && [ "$r_line" -lt "$a1_line" ]; then
	pass "the resolve (line $r_line) comes before Agent 1 (line $a1_line)"
else
	fail "the resolve is not before the sub-agents — resolve='$r_line' Agent 1='$a1_line'"
fi
spawn=$(t_trace_lines "$RP" | grep -F 'kind=spawn')
printf '%s\n' "$spawn" | grep -qF 'model=' && pass "the per-agent spawn records the resolved model" ||
	fail "the per-agent spawn does not carry model= — story 19: the review's independence is a fact only when recorded"
printf '%s\n' "$spawn" | grep -qF 'data.agent=' && pass "and names the agent" ||
	fail "the per-agent spawn does not carry data.agent="

# ---------------------------------------------------------------------------
banner "7. Every documented line runs: placeholders filled, the span executes and verifies"
# ---------------------------------------------------------------------------
# runnable <span> — the span an agent would type, with the document's
# placeholders made literal: `[optional]` groups dropped; `<one word>`
# becomes `x` and `<several words>` becomes `x y`, so a prose placeholder that
# the document left unquoted breaks exactly as the real value would; an
# `a|b|c` choice becomes its first option; `$model` becomes a model id; the
# `--blob` file becomes a real one; the trailing `|| :` goes, so the exit
# status is the script's own.
BLOBF="$SCRATCH/blob.x"
printf 'evidence\n' >"$BLOBF"
for s in $CHAIN; do
	f=$(skill_md "$s")
	dir="$SCRATCH/run.$s"
	n=0; bad=0
	while IFS= read -r span; do
		[ -n "$span" ] || continue
		n=$((n + 1))
		cmd=$(t_trace_runnable "$span" "$BLOBF")
		err=$( cd "$ROOT" && TRACE_DIR="$dir" TRACE_QUIET=1 sh -c "$cmd" 2>&1 >/dev/null ); st=$?
		if [ "$st" != 0 ]; then
			bad=$((bad + 1))
			fail "/$s line does not run (exit $st): $span"
			printf '        | as run: %s\n        | %s\n' "$cmd" "$err"
		fi
	done <<EOF
$(t_trace_spans "$f")
EOF
	[ "$bad" = 0 ] && pass "/$s: all $n documented trace lines run" || true
	if [ -d "$dir" ]; then
		( cd "$ROOT" && TRACE_DIR="$dir" TRACE_QUIET=1 sh "$TRACE" verify >/dev/null 2>&1 ) &&
			pass "/$s: and what they wrote verifies" ||
			fail "/$s: the lines ran but the trace they wrote does not verify"
	fi
done

t_done "trace skills contract"
