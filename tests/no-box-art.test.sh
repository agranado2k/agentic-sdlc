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
box_hits() {
	LC_ALL=C grep -rn -- "$BOX" "$@" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
banner "1. The shipped prose carries no box drawing"
# ---------------------------------------------------------------------------
# shellcheck disable=SC2086 — SHIPPED is a list on purpose.
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
BAIT="$SCRATCH/bait"
for root in .agents/skills constitution templates; do
	rm -rf "$BAIT" && mkdir -p "$BAIT/$root/planted"
	printf '# Planted\n\n┌───────┐\n│ a box │\n└───────┘\n' >"$BAIT/$root/planted/DOC.md"
	case "$(cd "$BAIT" && box_hits $SHIPPED)" in
	*"$root/planted/DOC.md:3:"*) pass "a box drawn under $root/ is reported with its file and line" ;;
	*) fail "a box drawn under $root/ went unreported" ;;
	esac
done
# A single tree-drawing glyph is enough — the block, not a whole picture.
rm -rf "$BAIT" && mkdir -p "$BAIT/constitution"
printf 'root\n├── child\n' >"$BAIT/constitution/tree.md"
case "$(cd "$BAIT" && box_hits $SHIPPED)" in
*"tree.md:2:"*) pass "a lone tree glyph is reported too" ;;
*) fail "a lone tree glyph went unreported" ;;
esac
# Ordinary prose with a non-ASCII dash or arrow is not art.
rm -rf "$BAIT" && mkdir -p "$BAIT/constitution"
printf 'spec — tickets → code; “quotes”, café.\n' >"$BAIT/constitution/prose.md"
[ -z "$(cd "$BAIT" && box_hits $SHIPPED)" ] &&
	pass "dashes, arrows, quotes and accents are not reported" ||
	fail "ordinary non-ASCII prose was reported as art"

t_done "no character art in the shipped prose (craft §10)"
