#!/bin/sh
# tests/no-box-art.test.sh — craft rule §10 as a failing check: no character
# art in the shipped prose.
#
# constitution/shared-code-craft.md §10 says diagrams are drawings, never
# character art. The rule is portable text; this is the check that makes it
# more than a claim (hard rule 9) for the part of the kit that ships AS prose
# — the skills, the constitution and the templates. The harness's own fixture
# tests use box characters as comment rules; those are code, not documents,
# and are outside the scan on purpose.
#
# What is scanned: the Unicode Box Drawing block (U+2500–U+257F), which is
# what a drawn box, a tree or a table rule is made of. In UTF-8 the block is
# the lead byte E2 followed by 94 or 95, so the scan runs byte-wise under
# LC_ALL=C and needs no locale.
#
# Usage: sh tests/no-box-art.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
cd "$ROOT" || exit 2
t_init

SHIPPED=".agents/skills constitution templates"
BOX=$(printf '\342[\224\225]')

# box_hits <dir>... — every line carrying a box-drawing character, file:line:text.
# No error suppression: a root that does not exist must be heard, not
# certified — every caller below scans roots it has checked or created.
box_hits() {
	LC_ALL=C grep -rn -- "$BOX" "$@"
}

# ---------------------------------------------------------------------------
banner "1. The shipped prose carries no box drawing"
# ---------------------------------------------------------------------------
# A root that moved while SHIPPED kept its old name would be scanned as
# nothing and certified as clean; say so instead.
for r in $SHIPPED; do
	[ -d "$r" ] && pass "shipped root $r exists and is scanned" ||
		fail "shipped root $r does not exist — the scan is not covering it"
done
# shellcheck disable=SC2086  # SHIPPED is a list on purpose.
hits=$(box_hits $SHIPPED)
if [ -z "$hits" ]; then
	pass "no box-drawing character in $SHIPPED"
else
	fail "box-drawing characters in the shipped prose — craft §10 says draw it or write it"
	printf '%s\n' "$hits" | sed 's/^/        | /'
fi

# ---------------------------------------------------------------------------
banner "2. A planted diagram is caught, in each shipped root (RED)"
# ---------------------------------------------------------------------------
# bait_tree — a scratch tree carrying every shipped root, empty, so the scan
# runs exactly as it does on the kit and a planted file is the only hit.
BAIT="$SCRATCH/bait"
bait_tree() {
	rm -rf "$BAIT"
	for r in $SHIPPED; do mkdir -p "$BAIT/$r"; done
}
# The roots are spelled again here on purpose: this loop is an independent
# oracle, so a root dropped from SHIPPED goes red instead of vanishing from
# both sides at once. The block has two halves in UTF-8 (lead byte E2 94 for
# single lines, E2 95 for double), so one of the planted boxes is drawn in
# double lines — a pattern that lost either half must fail here.
for root in .agents/skills constitution templates; do
	bait_tree && mkdir -p "$BAIT/$root/planted"
	if [ "$root" = constitution ]; then
		printf '# Planted\n\n╔═══════╗\n║ a box ║\n╚═══════╝\n' >"$BAIT/$root/planted/DOC.md"
	else
		printf '# Planted\n\n┌───────┐\n│ a box │\n└───────┘\n' >"$BAIT/$root/planted/DOC.md"
	fi
	# shellcheck disable=SC2086  # SHIPPED is a list on purpose.
	case "$(cd "$BAIT" && box_hits $SHIPPED)" in
	*"$root/planted/DOC.md:3:"*) pass "a box drawn under $root/ is reported with its file and line" ;;
	*) fail "a box drawn under $root/ went unreported" ;;
	esac
done
# A single glyph is enough — the block, not a whole picture — from each half.
bait_tree
printf 'root\n├── child\n' >"$BAIT/constitution/tree.md"
printf 'cross ╬ here\n' >"$BAIT/templates/cross.md"
# shellcheck disable=SC2086  # SHIPPED is a list on purpose.
found=$(cd "$BAIT" && box_hits $SHIPPED)
case "$found" in *"tree.md:2:"*) pass "a lone single-line tree glyph is reported" ;; *) fail "a lone tree glyph went unreported" ;; esac
case "$found" in *"cross.md:1:"*) pass "a lone double-line glyph is reported" ;; *) fail "a lone double-line glyph went unreported" ;; esac
# Ordinary prose with a non-ASCII dash or arrow is not art.
bait_tree
printf 'spec — tickets → code; “quotes”, café.\n' >"$BAIT/constitution/prose.md"
# shellcheck disable=SC2086  # SHIPPED is a list on purpose.
[ -z "$(cd "$BAIT" && box_hits $SHIPPED)" ] &&
	pass "dashes, arrows, quotes and accents are not reported" ||
	fail "ordinary non-ASCII prose was reported as art"

t_done "no character art in the shipped prose (craft §10)"
