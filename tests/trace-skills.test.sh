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
#      And the `finding.dismiss` kind ADR-0008's amendment of 2026-09-30 gave
#      /pr-iterate alone (#277): on the raise's subject, joined on data.where.
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
# The fourteen are the chain the root manual draws (spec → tickets →
# implementation → review → landing) plus the skills that step out of it and
# decide something. Ticket #250 sized the first thirteen; #309 added
# /grill-with-docs, the variant of /grill-me a project with a glossary actually
# runs, so a plan grilled against the records leaves its decisions too.
# /explain-diff, /dogfood and /improve-codebase-architecture stay outside on
# purpose — rule 3 still holds them, like every skill directory.
#
#   8. The record agrees with rule 3: ADR-0008 clause 7 carries its dated
#      amendment — the readers are the operator and the retrospective skill,
#      and a diagnosis reads by the operator's hand — and the index row for
#      0008 carries the same date (#309).
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

CHAIN="grill-me grill-with-docs to-prd to-tickets implement tdd review-pr pr-iterate merge-train diagnose prototype housekeeping design-brief worktree-cleanup"
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
[ "$n_chain" = 14 ] && pass "all fourteen chain skills exist" || fail "only $n_chain of 14 chain skills exist"
# The README describes this suite by its roster's size; a roster that grows
# without it leaves the kit's public face stale (review of PR #315, M-1).
case $n_chain in 13) n_word=thirteen ;; 14) n_word=fourteen ;; 15) n_word=fifteen ;; *) n_word=$n_chain ;; esac
readme_para=$(awk '/sh tests\/trace-skills\.test\.sh/ { on = 1 } on && /^- `sh tests\// && !/trace-skills/ { exit } on' README.md | tr '\n' ' ' | tr -s ' ')
case $readme_para in
*"each of the $n_word emits"*) pass "README.md describes this suite's roster as the $n_word it is" ;;
*) fail "README.md's paragraph for this suite does not say 'each of the $n_word emits' — the roster is $n_chain" ;;
esac

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
expects grill-with-docs kind=grill.decision
expects to-prd kind=prd.write
expects to-tickets kind=ticket.write tier= data.tier_proposed= data.confidence= data.blocked_by= data.label= data.label_confidence=
expects implement begin kind=ticket.start kind=spawn model= kind=pr.open end
expects tdd kind=tdd.cycle data.test=
expects review-pr begin kind=spawn data.agent= kind=finding.raise kind=review.verdict end
expects pr-iterate begin kind=finding.triage kind=finding.dismiss kind=pr.iterate kind=feedback end
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

# A human's dismissal of a posted finding (ADR-0008, amended 2026-09-30; #277)
# is one event on the subject of the finding.raise it answers. A posted comment
# shows no finding id, so the join is the `file:line` both lines carry as
# data.where; data.thread is what a reader counts once when two iterations saw
# the same closed thread. /pr-iterate is its only emitter: it is the skill that
# fetches the threads, and it learns of the dismissal from the forge.
PI=$(skill_md pr-iterate)
dm=$(grep -F 'kind=finding.dismiss' "$PI")
for tok in 'subject=pr:#<N>' 'outcome=dismissed' 'data.via=thread|review' 'data.where=' 'data.thread='; do
	printf '%s\n' "$dm" | grep -qF -- "$tok" && pass "/pr-iterate's dismissal carries $tok" ||
		fail "/pr-iterate's finding.dismiss line does not carry $tok"
done
raise=$(grep -F 'kind=finding.raise' "$(skill_md review-pr)")
for tok in 'subject=pr:#<N>' 'data.where='; do
	printf '%s\n' "$raise" | grep -qF -- "$tok" && pass "and /review-pr's raise carries $tok — the dismissal joins to it" ||
		fail "/review-pr's finding.raise no longer carries $tok — a dismissal has nothing to join to"
done
printf '%s\n' "$dm" | grep -qF 'quote it in the reason' && printf '%s\n' "$dm" | grep -qi 'summaris' &&
	pass "a human's dismissal message is quoted or summarised — data, never pasted" ||
	fail "/pr-iterate's dismissal does not say a human's words are quoted or summarised (agent trust boundary)"
# What names ONE dismissal is data.thread plus data.where, never data.thread
# alone: a dismissed review is one event per inline comment, every one carrying
# the review's id, so a reader that counted a data.thread once would fold N
# dismissed findings into one. The skill and the record
# say the same key, in the same words.
ADR8=$(tr '\n' ' ' <docs/adr/0008-decisions-are-traced-to-a-local-append-only-record.md | tr -s ' ')
printf '%s\n' "$dm" | grep -qF '`data.thread` plus `data.where`' &&
	pass "/pr-iterate names the pair that identifies one dismissal — data.thread plus data.where" ||
	fail "/pr-iterate does not say one dismissal is \`data.thread\` plus \`data.where\` — a dismissed review's events share one data.thread"
printf '%s\n' "$ADR8" | grep -qF '`data.thread` plus `data.where`' &&
	pass "and ADR-0008's amendment tells the reader to count that pair" ||
	fail "ADR-0008's amendment does not tell the reader to count \`data.thread\` plus \`data.where\`"
# data.where is now FORGE data — a path the pull request's author chose — typed
# into a shell line: it stays inside quotes, as data.thread already does. And
# the line is the one the comment was first posted on: the forge's current line
# moves with later commits and goes empty on an outdated comment, and the join
# then misses in silence.
printf '%s\n' "$dm" | grep -qF "data.where='<file:line>'" &&
	pass "the dismissal's data.where is quoted" ||
	fail "/pr-iterate's finding.dismiss line carries data.where unquoted — the path is forge data (agent trust boundary)"
# Quotes alone are not the rule: a path holding a quote closes them. A path
# outside the plain set is never typed into the line at all.
printf '%s\n' "$dm" | grep -qF 'data.where=unsafe-path' && printf '%s\n' "$dm" | grep -qF 'never typed' &&
	pass "and a path outside the plain character set is never typed — the event carries data.where=unsafe-path" ||
	fail "/pr-iterate does not say what to do with a forge path that cannot be quoted safely — a quote in a filename closes the quotes"
printf '%s\n' "$dm" | grep -qF 'first posted on' && printf '%s\n' "$dm" | grep -qi 'outdated' &&
	pass "and it is the line the comment was first posted on, not the forge's current one" ||
	fail "/pr-iterate does not say data.where is the line the comment was first posted on — an outdated comment's current line is empty"
others=
for s in $CHAIN; do
	[ "$s" = pr-iterate ] && continue
	if grep -qF 'kind=finding.dismiss' "$(skill_md "$s")"; then others="$others /$s"; fi
done
[ -z "$others" ] && pass "no other chain skill emits finding.dismiss" ||
	fail "finding.dismiss is also emitted by$others — /pr-iterate is the one skill that fetches the threads"
# /retro's eighth question attributes a `ticket.write` and a `finding.raise`
# BY KIND when the event and its run name no skill (review of PR #329, H-1):
# /to-tickets opens no run and names no skill on its emit. That is sound only
# while exactly ONE skill emits each kind — a second emitter makes the reader
# credit its stamps to the first. So the fact is held here, over every file
# under the skills' home at any depth — not the chain roster alone — with the
# kind quoted or bare, and so is the pair the reader's text names.
for pair in ticket.write:to-tickets finding.raise:review-pr; do
	k=${pair%%:*}
	want=${pair#*:}
	who=$(grep -rlE "kind=['\"]?$(printf '%s' "$k" | sed 's/\./\\./g')" "$SKILLS" 2>/dev/null | sed "s|^$SKILLS/||; s|/.*||" | sort -u | tr '\n' ' ')
	[ "$who" = "$want " ] && pass "$k is emitted by exactly one skill, /$want — what /retro's attribution by kind rests on" ||
		fail "$k is emitted by: ${who:-nobody} — /retro attributes it to /$want by kind, which holds only for a sole emitter"
	tr '\n' ' ' <"$SKILLS/retro/QUESTIONS.md" | tr -s ' ' | grep -qF "a \`$k\` is \`/$want\`'s" &&
		pass "…and /retro's question 8 names that pair: a $k is /$want's" ||
		fail "/retro's question 8 does not say 'a \`$k\` is \`/$want\`'s' — the reader's pair and the emitter's have drifted"
done
# The emit's PRECONDITION is a fact the snapshot has to fetch (review of PR
# #319, H-1): "a thread resolved that you did not resolve" is unreadable if
# step 1 never asks the forge for a thread's resolved state. The snapshot is
# metadata only since #278, and this holds the one field this emit needs in
# it — so a later edit that drops the field turns the emit into a rule nothing
# can observe, and this goes red instead.
snapshot=$(sed -n '/^### 1 /,/^### 2 /p' "$PI")
printf '%s\n' "$snapshot" | grep -qF 'reviewThreads' && printf '%s\n' "$snapshot" | grep -qF 'isResolved' &&
	pass "the snapshot fetches each review thread's resolved state — the emit has something to read" ||
	fail "/pr-iterate's snapshot does not select a review thread's resolved state — finding.dismiss fires on a fact step 1 never fetched"

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
# The placeholders are made literal by the shared test harness's t_trace_runnable
# (tests/lib.sh) — one definition, shared with the other skill suites.
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

# ---------------------------------------------------------------------------
banner "8. The record agrees: clause 7 names no skill reader but the retrospective"
# ---------------------------------------------------------------------------
# Rule 3 above forbids every skill a read subcommand; the record once named
# /diagnose as a reader beside the operator and the retrospective. The
# disagreement is settled by a dated amendment to clause 7 — a record is
# amended, never rewritten (root manual, hard rule 5) — and the index says so.
ADR8=$(ls docs/adr/0008-*.md 2>/dev/null | head -1)
c7=$(awk '/^7\. \*\*The chain never reads the trace/ { on = 1 } on && /^8\. / { exit } on' "$ADR8" 2>/dev/null)
[ -n "$c7" ] && pass "ADR-0008 has its clause 7" || fail "no clause 7 found in '$ADR8'"
am=$(printf '%s\n' "$c7" | awk '/\*Amended [0-9-]*( \(#[0-9]+\))?:\*/ { on = 1 } on')
[ -n "$am" ] && pass "clause 7 carries a dated amendment" ||
	fail "clause 7 has no '*Amended <date> (#N):*' block — the record still names a skill reader rule 3 forbids"
printf '%s\n' "$am" | tr '\n' ' ' | tr -s ' ' | grep -qiE 'operator.*retrospective skill' &&
	pass "the amendment names the readers: the operator and the retrospective skill" ||
	fail "the amendment does not name the operator and the retrospective skill as the readers"
printf '%s\n' "$am" | tr '\n' ' ' | tr -s ' ' | grep -qiE "diagnosis reads the trace by the operator's hand" &&
	pass "and says a diagnosis reads by the operator's hand" ||
	fail "the amendment does not say a diagnosis reads the trace by the operator's hand"
am_date=$(printf '%s\n' "$am" | sed -n 's/.*\*Amended \([0-9-]*\)[^*:]*:\*.*/\1/p' | tail -1)
row=$(grep -F '| [0008]' docs/adr/INDEX.md)
# Held to THIS amendment, not to any note that shares its date — and an empty
# date is a failure, never a match on an older note (review of PR #315, L-2).
case $row in
*"amended $am_date (#309"*"clause 7"*) [ -n "$am_date" ] &&
	pass "the index row for 0008 carries the clause-7 amendment's dated note ($am_date, #309)" ||
	fail "the amendment carries no date the index row could be held to" ;;
*) fail "the index row for 0008 has no 'amended ${am_date:-<no date>} (#309 …' note naming clause 7: $row" ;;
esac

# ---------------------------------------------------------------------------
banner "9. Every spawn records the resolver's model id, never a typed word"
# ---------------------------------------------------------------------------
# A spawn records the model the resolver answered, never a word a session typed.
# Every `spawn` line in the skill must have `model=` that is either a resolver
# call `$(sh scripts/agents.lib.sh ...)` or a variable reference `$model` /
# `"$model"`, never a literal model name like `opus` or `claude-opus-5-5`.
for s in $CHAIN; do
	f=$(skill_md "$s")
	bad=0
	while IFS= read -r span; do
		[ -n "$span" ] || continue
		# Only check spawn lines
		if printf '%s\n' "$span" | grep -qF 'kind=spawn'; then
			# Check if model= is present
			if printf '%s\n' "$span" | grep -qF 'model='; then
				# Extract the model value - look for model=... and capture what follows
				# Valid patterns are: $model, "$model", or $(sh scripts/agents.lib.sh ...)
				# Invalid patterns are literal strings like 'opus' or 'claude-opus-5-5'
				if printf '%s\n' "$span" | grep -qE 'model=\$model([ \)]|$)' ||
					printf '%s\n' "$span" | grep -qE 'model="\$model"' ||
					printf '%s\n' "$span" | grep -qE "model='\$model'" ||
					printf '%s\n' "$span" | grep -qF 'model=$(sh scripts/agents.lib.sh'; then
					pass "/$s spawn uses resolver or variable for model"
				else
					bad=$((bad + 1))
					fail "/$s spawn does not use resolver/variable for model — should be \$(sh scripts/agents.lib.sh ...) or \$model"
					printf '        | span: %s\n' "$span"
				fi
			fi
		fi
	done <<EOF
$(t_trace_spans "$f")
EOF
	[ "$bad" = 0 ] || true
done

# ---------------------------------------------------------------------------
# banner "10. /implement emits tdd.cycle while driving /tdd's red-green-refactor loop"
# ---------------------------------------------------------------------------
# The /tdd skill defines tdd.cycle as one event per RED, per GREEN and per
# refactor step. When /implement drives /tdd through each seam (step 4), it
# emits tdd.cycle to record the cycle, not only /tdd's own invocation.
# This ensures the operator sees every cycle a session ran, regardless of
# whether /tdd was spawned or driven inline.
IMPL=$(skill_md implement)
impl_tdd=$(grep -F 'kind=tdd.cycle' "$IMPL")
if [ -n "$impl_tdd" ]; then
	pass "/implement emits tdd.cycle"
	# Verify the emit has the required fields
	if printf '%s\n' "$impl_tdd" | grep -qF 'outcome='; then
		pass "/implement's tdd.cycle emit carries outcome="
	else
		fail "/implement's tdd.cycle emit is missing outcome="
	fi
	if printf '%s\n' "$impl_tdd" | grep -qF 'data.test='; then
		pass "/implement's tdd.cycle emit carries data.test="
	else
		fail "/implement's tdd.cycle emit is missing data.test="
	fi
else
	fail "/implement does not emit tdd.cycle — the operator cannot see which cycles a session ran"
fi

# ---------------------------------------------------------------------------
# banner "11. Every spawn emit carries skill= to name which skill made the spawn"
# ---------------------------------------------------------------------------
# When a skill spawns a subagent, the emit must carry skill=<skill_name> to
# identify which skill made the decision to spawn. This allows the trace reader
# to attribute each spawn to its originating skill without relying on event
# ordering or the skill resolver's output.
bad_spawns=0
for s in $CHAIN; do
	f=$(skill_md "$s")
	spawns=$(grep -F 'kind=spawn' "$f" || true)
	if [ -z "$spawns" ]; then
		pass "/$s has no spawns"
		continue
	fi
	# For each spawn line in this skill, check that it carries skill=
	while IFS= read -r spawn_line; do
		[ -z "$spawn_line" ] && continue
		if printf '%s\n' "$spawn_line" | grep -qE 'skill=[a-z-]+' || printf '%s\n' "$spawn_line" | grep -qE 'skill=\$' || printf '%s\n' "$spawn_line" | grep -qE 'skill=\$\{'; then
			pass "/$s's spawn carries skill="
		else
			bad_spawns=$((bad_spawns + 1))
			fail "/$s's spawn does not carry skill= — cannot attribute spawn to originating skill"
			printf '        | span: %s\n' "$spawn_line"
		fi
	done <<EOF
$spawns
EOF
done
[ "$bad_spawns" = 0 ] || true

t_done "trace skills contract"
