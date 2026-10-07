#!/bin/sh
# tests/cheap-reads.test.sh — every spawned worker is pointed at the
# cheap-reads reference before it reads (#594, PRD #580 R23).
#
# Code reads and whole diffs were about 76% of spawn tool output in PRD
# #580's baseline. The reference names the reads that return the smallest
# exact answer; a reference no worker is told about saves nothing, so what is
# held here is the pointing, not only the file.
#
# What is asserted: the reference exists and names the four reads; every
# spawn site in a shipped skill — a line carrying a `Trace-Spawn:` stamp,
# which #615 put on every one — names the reference on that same line; and
# each dispatched worker contract under .agents/prompts/ names it too.
#
# Usage: sh tests/cheap-reads.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

cd "$ROOT" || exit 2

REF=.agents/prompts/cheap-reads.md

banner "the reference exists and names the four reads"
assert_file "$REF"
for want in 'git diff --stat' 'git log -S' 'grep -w' 'line range'; do
	if [ -f "$REF" ] && grep -qF -- "$want" "$REF"; then
		pass "$REF names '$want'"
	else
		fail "$REF does not name '$want'"
	fi
done

banner "every skill spawn site names the reference"
sites=0
for f in .agents/skills/*/*.md; do
	# grep -n output: <line>:<text>; a spawn site is a line carrying the stamp.
	grep -n 'Trace-Spawn: tier=' "$f" >"$SCRATCH/sites" || continue
	while IFS= read -r line; do
		sites=$((sites + 1))
		n=${line%%:*}
		case $line in
		*"$REF"*) pass "$f:$n names $REF" ;;
		*) fail "$f:$n spawns a worker without naming $REF" ;;
		esac
	done <"$SCRATCH/sites"
done
# Six spawn sites today (implement 2, pr-iterate 2, to-tickets 1, review-pr 1):
# fewer means the stamp moved and this suite went vacuous, not that it passed.
[ "$sites" -ge 6 ] &&
	pass "$sites spawn sites checked" ||
	fail "only $sites spawn sites found — the Trace-Spawn stamp moved, re-aim this suite"

banner "every dispatched worker contract names the reference"
for f in .agents/prompts/*-worker.md; do
	[ -f "$f" ] || { fail "no worker contract under .agents/prompts/"; continue; }
	grep -qF "$REF" "$f" &&
		pass "$f names $REF" ||
		fail "$f does not name $REF"
done

t_done "cheap reads"
