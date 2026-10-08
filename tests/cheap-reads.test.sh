#!/bin/sh
# tests/cheap-reads.test.sh — every spawning skill and every dispatched worker
# contract points its worker at the cheap-reads reference before it reads
# (#594, PRD #580 R23).
#
# Code reads and whole diffs were about 76% of spawn tool output in PRD
# #580's baseline. The reference names the reads that return the smallest
# exact answer; a reference no worker is told about saves nothing, so what is
# held here is the pointing, not only the file.
#
# What is asserted: the reference exists and names the four reads; every
# skill that resolves a tier to spawn (`agents.lib.sh` anywhere in its files,
# bar the line reporting an unmapped reviewer tier)
# names the reference; every stamped spawn site (a `Trace-Spawn:` line) names
# it on that same line — "always" for a worker that holds the tree and a
# shell, "never" for a judge reader, whose reach is its scratch files alone;
# and each dispatched worker contract under .agents/prompts/ names it too.
# The kit-only skill dispatcher's own composed prompts are not held here.
#
# Usage: sh tests/cheap-reads.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

cd "$ROOT" || exit 2

REF=.agents/prompts/cheap-reads.md
ALWAYS="names \`$REF\` always"
NEVER="never names \`$REF\`"

banner "the reference exists and names the four reads"
assert_file "$REF"
for want in 'git diff --stat' 'git log -S' 'grep -w' 'line range'; do
	assert_file_has "$REF" "$want"
done

banner "every spawning skill names the reference"
skills=0
# The one line that names the resolver without spawning is the day-one
# finding (#654) — a report that the reviewer tier answered nothing — so a
# line carrying it does not make a skill a spawning one.
for d in .agents/skills/*/; do
	grep -hs 'agents\.lib\.sh' "$d"*.md | grep -qvF 'reviewer tier unmapped — the review shared' || continue
	skills=$((skills + 1))
	if grep -qsF "$REF" "$d"*.md; then
		pass "$d names $REF"
	else
		fail "$d resolves a tier to spawn but never names $REF"
	fi
done
# Eight spawning skills today: fewer means the resolve moved and this block
# went vacuous, not that it passed.
[ "$skills" -ge 8 ] &&
	pass "$skills spawning skills checked" ||
	fail "only $skills spawning skills found — the tier resolve moved, re-aim this suite"

banner "every stamped spawn site names the reference, judge readers as never"
sites=0
for f in .agents/skills/*/*.md; do
	# grep -n output: <line>:<text>; a spawn site is a line carrying the stamp.
	grep -n 'Trace-Spawn: tier=' "$f" >"$SCRATCH/sites" || continue
	while IFS= read -r line; do
		sites=$((sites + 1))
		n=${line%%:*}
		case $line in
		*'domain=judge'*) want=$NEVER ;;
		*) want=$ALWAYS ;;
		esac
		case $line in
		*"$want"*) pass "$f:$n says '$want'" ;;
		*) fail "$f:$n spawns a worker without saying '$want'" ;;
		esac
	done <"$SCRATCH/sites"
done
# Six stamped sites today (implement 2, pr-iterate 2, to-tickets 1, review-pr 1).
[ "$sites" -ge 6 ] &&
	pass "$sites spawn sites checked" ||
	fail "only $sites spawn sites found — the Trace-Spawn stamp moved, re-aim this suite"

banner "every dispatched worker contract names the reference"
for f in .agents/prompts/*-worker.md; do
	[ -f "$f" ] || { fail "no worker contract under .agents/prompts/"; continue; }
	assert_file_has "$f" "$REF"
done

t_done "cheap reads"
