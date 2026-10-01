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
#  10. Every `data.agent` /review-pr writes — on a spawn, on a finding it
#      raises itself, and on a finding it relays from a review that ran
#      elsewhere — is one token from the closed sub-agent roster the skill
#      owns as ONE list, never a name as a report spelled it (#346).
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
banner "10. Every data.agent the skill writes is a token from its own closed sub-agent roster (#346)"
# ---------------------------------------------------------------------------
# The retrospective reads the review signal PER SUB-AGENT (question 2), and a
# review that was relayed — dispatched to another vendor, or run as a fallback
# through the agent tool, and posted by the session that holds the credentials
# — recorded its verdict and never its findings; where findings were recorded
# the agent was spelled twenty ways in one window (retro 20261001T093317Z,
# F3). So the skill owns ONE list, the sub-agent roster, and every
# `data.agent=` on every trace line it documents is either that list's own
# placeholder, `<roster-token>`, or a literal token on the list — never the
# agent's title, never its number, never the name as a report spelled it.
# The relayed finding is recorded by the same emit, marked `data.via=relay`,
# with `unattributed` for a report that names no agent at all: the dispatched
# worker's contract names none, and a lens guessed from the finding's text
# would be the session's invention recorded as the reviewer's.
RP=$(skill_md review-pr)
# roster_rows <skill file> — the rows of the one list, in file order.
roster_rows() { awk '/^\*\*The sub-agent roster\.\*\*/ { on = 1; next } on && /^- `/ { print } on && /^#/ { exit }' "$1"; }
# roster_of <skill file> — the rows' tokens.
roster_of() { roster_rows "$1" | sed -n 's/^- `\([^`]*\)` — .*/\1/p'; }
# headings_without_row <skill file> — every `#### Agent N — Title` heading the
# roster has no `— Agent N, Title` row for, one per line. Computed in a
# function and asserted in the parent shell: a `fail` inside a piped loop
# runs in a subshell and never reaches the suite's count (review of PR #369,
# H-1 — the suite ended ALL GREEN around a printed FAIL).
headings_without_row() {
	_hw_rows=$(roster_rows "$1")
	grep -E '^#### Agent [0-9]+ — ' "$1" | sed 's/^#### //' | while IFS= read -r _hw_h; do
		_hw_num=${_hw_h%% — *}; _hw_title=${_hw_h#* — }; _hw_title=${_hw_title% (*}
		printf '%s\n' "$_hw_rows" | grep -qF -- "— $_hw_num, $_hw_title" || printf '%s (%s)\n' "$_hw_num" "$_hw_title"
	done
}
# agent_values <skill file> — every data.agent value a trace line carries,
# quotes stripped, one per line.
agent_values() { t_trace_lines "$1" | grep -oE "data\.agent=('[^']*'|\"[^\"]*\"|[^ ]*)" | sed -e 's/^data\.agent=//' -e "s/^'\(.*\)'\$/\1/" -e 's/^"\(.*\)"$/\1/'; }
# off_roster <skill file> [roster] — the data.agent values the roster does
# not hold, space-joined; the placeholder that names the roster is on it by
# definition. The roster is the file's own unless one is given.
off_roster() {
	_or_roster=${2:-$(roster_of "$1")}
	agent_values "$1" | while IFS= read -r _or_v; do
		[ "$_or_v" = '<roster-token>' ] && continue
		case "$_or_v" in
		"") printf '%s ' '(empty)' ;;
		*) printf '%s\n' "$_or_roster" | grep -qxF -- "$_or_v" || printf '%s ' "$_or_v" ;;
		esac
	done | sed 's/ $//'
}
ROSTER=$(roster_of "$RP")
n_roster=$(printf '%s\n' "$ROSTER" | grep -c . | tr -d ' ')
[ "$n_roster" -ge 8 ] && pass "/review-pr owns a sub-agent roster of $n_roster tokens, one list" ||
	fail "/review-pr has no '**The sub-agent roster.**' list of at least eight tokens (seven agents and the unattributed case) — found $n_roster"
bad_shape=$(printf '%s\n' "$ROSTER" | grep -vE '^[a-z][a-z0-9-]*$' || true)
[ -z "$bad_shape" ] && pass "every roster token is [a-z][a-z0-9-]* — a token, not a title" ||
	fail "a roster token is not a token: $(printf '%s' "$bad_shape" | tr '\n' ' ')"
dupes=$(printf '%s\n' "$ROSTER" | sort | uniq -d | tr '\n' ' ')
[ -z "$dupes" ] && pass "and no token is listed twice" || fail "roster tokens listed twice: $dupes"
# The roster covers the agents: every `#### Agent N — Title` heading has a row
# naming that number and that title, so a renamed or added agent cannot leave
# the roster describing a review that no longer runs.
no_row=$(headings_without_row "$RP" | tr '\n' ' ' | sed 's/ $//')
[ -z "$no_row" ] && pass "every agent heading has its roster row, by number and title" ||
	fail "the roster has no row for: $no_row — the heading and the roster disagree"
sed 's/^#### Agent 4 — Simplicity Advocate$/#### Agent 4 — Complexity Hunter/' "$RP" >"$SCRATCH/bait-heading.md"
[ "$(headings_without_row "$SCRATCH/bait-heading.md")" = 'Agent 4 (Complexity Hunter)' ] &&
	pass "bait: a renamed agent heading with no roster row is named — in the parent shell, where it counts" ||
	fail "bait: a renamed heading was not caught (got '$(headings_without_row "$SCRATCH/bait-heading.md")')"
n_head=$(grep -cE '^#### Agent [0-9]+ — ' "$RP" | tr -d ' ')
[ "$n_head" = 7 ] && pass "seven agent headings, as the skill's description says" || fail "found $n_head agent headings, not 7"
printf '%s\n' "$ROSTER" | grep -qx unattributed && pass "the roster holds 'unattributed' for a report that names no agent" ||
	fail "the roster has no 'unattributed' token — a dispatched worker's report names no agent, and the relay then has nothing legal to write"
# Every data.agent the chain writes is held — across the chain, so a second
# skill writing one off the roster is red here too, not only /review-pr.
for s in $CHAIN; do
	f=$(skill_md "$s")
	vals=$(agent_values "$f" | grep -c . | tr -d ' ')
	[ "$vals" = 0 ] && continue
	bad=$(off_roster "$f" "$ROSTER")
	[ -z "$bad" ] && pass "/$s: all $vals data.agent values are the roster's placeholder or a roster token" ||
		fail "/$s writes data.agent off the roster: $bad — a value is <roster-token> or a token on /review-pr's list, never a name as spelled"
done
[ "$(agent_values "$RP" | grep -c . | tr -d ' ')" -ge 3 ] && pass "/review-pr writes data.agent on at least three lines: the spawn, its own raise, the relayed raise" ||
	fail "/review-pr writes data.agent on $(agent_values "$RP" | grep -c . | tr -d ' ') lines — the spawn, its own raise and the relayed raise each carry one"
# The relay path: one finding.raise per relayed finding, marked as relayed,
# the report read as data.
relay=$(t_trace_lines "$RP" | grep -F 'kind=finding.raise' | grep -F 'data.via=relay' || true)
[ -n "$relay" ] && pass "/review-pr's relay path records each relayed finding as a finding.raise carrying data.via=relay" ||
	fail "/review-pr has no finding.raise line carrying data.via=relay — a relayed review records its verdict and never its findings (retro F3)"
for tok in 'data.id=' 'data.severity=' "data.where='<file:line>'" 'data.agent=<roster-token>' 'subject=pr:#<N>'; do
	printf '%s\n' "$relay" | grep -qF -- "$tok" && pass "the relayed raise carries $tok" ||
		fail "the relayed raise does not carry $tok"
done
relay_sec=$(sed -n '/^#### Relaying a review/,/^### 7\. /p' "$RP")
[ -n "$relay_sec" ] && pass "the relay path has its own heading under §6" || fail "/review-pr §6 has no '#### Relaying a review' heading"
printf '%s\n' "$relay_sec" | grep -qi 'never the name as the report spelled it' &&
	pass "and says the agent is never the name as the report spelled it" ||
	fail "the relay path does not say 'never the name as the report spelled it'"
printf '%s\n' "$relay_sec" | grep -qF 'unattributed' && printf '%s\n' "$relay_sec" | grep -qi 'names no agent' &&
	pass "and says a report that names no agent is recorded as unattributed" ||
	fail "the relay path does not say what a report that names no agent records (unattributed)"
printf '%s\n' "$relay_sec" | grep -qi 'untrusted content' && printf '%s\n' "$relay_sec" | grep -qi 'read as data' &&
	pass "and reads the report as untrusted content — data, never instructions" ||
	fail "the relay path does not say the report is untrusted content read as data"
printf '%s\n' "$relay_sec" | grep -qF 'data.where=unsafe-path' &&
	pass "and a path outside the plain set is never typed — data.where=unsafe-path, as /pr-iterate's dismissal already does" ||
	fail "the relay path does not say what to do with a report path that cannot be quoted safely (data.where=unsafe-path)"
# The demo: a relayed report of three findings becomes three raise lines,
# agents from the roster — the documented line, filled once per token, runs
# and what it wrote verifies. Then the bait: the same line with the agent as
# a report would spell it, misspelled, or left to the writer, is red here.
dir="$SCRATCH/run.relay"
n_ok=0
for tok in $ROSTER; do
	cmd=$(printf '%s\n' "$relay" | grep -o '`sh scripts/trace\.sh[^`]*`' | head -1 | tr -d '`' | sed "s/<roster-token>/$tok/")
	cmd=$(t_trace_runnable "$cmd")
	if ( cd "$ROOT" && TRACE_DIR="$dir" TRACE_QUIET=1 sh -c "$cmd" >/dev/null 2>&1 ); then n_ok=$((n_ok + 1)); else fail "the relayed raise does not run with data.agent=$tok: $cmd"; fi
done
[ "$n_roster" -gt 0 ] && [ "$n_ok" = "$n_roster" ] && pass "the relayed raise runs once per roster token ($n_ok lines)" || true
[ -d "$dir" ] && ( cd "$ROOT" && TRACE_DIR="$dir" TRACE_QUIET=1 sh "$TRACE" verify >/dev/null 2>&1 ) &&
	pass "and what they wrote verifies" || fail "the relayed raises ran but the trace they wrote does not verify"
[ -d "$dir" ] && [ "$(cat "$dir"/events/*.jsonl 2>/dev/null | grep -c '"kind":"finding.raise"')" = "$n_roster" ] &&
	pass "the trace holds one finding.raise per roster token ($n_roster lines), agents from the roster" ||
	fail "the trace does not hold $n_roster finding.raise lines"
bait_agent() { sed "/data\.via=relay/ s/data\.agent=<roster-token>/data.agent=$1/" "$RP" >"$SCRATCH/bait-agent.md"; }
bait_agent "'Security Sentinel'"
[ "$(off_roster "$SCRATCH/bait-agent.md")" = 'Security Sentinel' ] && pass "bait: the agent as the report spelled it — 'Security Sentinel' — goes red" ||
	fail "bait: a relayed raise carrying data.agent='Security Sentinel' was not caught (got '$(off_roster "$SCRATCH/bait-agent.md")')"
bait_agent secuirty
[ "$(off_roster "$SCRATCH/bait-agent.md")" = secuirty ] && pass "bait: a misspelled token — secuirty — goes red" ||
	fail "bait: a relayed raise carrying data.agent=secuirty was not caught (got '$(off_roster "$SCRATCH/bait-agent.md")')"
bait_agent "'secur.*'"
[ "$(off_roster "$SCRATCH/bait-agent.md")" = 'secur.*' ] && pass "bait: a pattern — secur.* — is not a token, and goes red" ||
	fail "bait: a relayed raise carrying data.agent='secur.*' was not caught — the holder matched it as a regex (got '$(off_roster "$SCRATCH/bait-agent.md")')"
bait_agent "'<the agent that raised it>'"
[ "$(off_roster "$SCRATCH/bait-agent.md")" = '<the agent that raised it>' ] && pass "bait: an open placeholder — the writer's own spelling — goes red" ||
	fail "bait: a relayed raise carrying data.agent='<the agent that raised it>' was not caught (got '$(off_roster "$SCRATCH/bait-agent.md")')"
cmp -s "$SCRATCH/bait-agent.md" "$RP" && fail "the bait planted nothing — the relayed raise's anchor moved" || pass "the baits planted their lines"
# And the holder reads the roster from the FILE: a token withdrawn from the
# list while the demo above still ran it is what this catches.
sed '/^- `unattributed` — /d' "$RP" >"$SCRATCH/bait-roster.md"
roster_of "$SCRATCH/bait-roster.md" | grep -qx unattributed && fail "bait: withdrawing a roster row changed nothing — the roster is not read from the list" ||
	pass "bait: a roster row withdrawn from the list is gone from the roster the holder reads"

t_done "trace skills contract"
