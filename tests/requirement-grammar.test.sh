#!/bin/sh
# tests/requirement-grammar.test.sh — the requirement-line grammar, once.
#
# What counts as a requirement line, an id, an area and a cited name was
# spelled in six places — the living-spec validator, its POSIX twin in the
# gate, the coverage check, and patterns in three suites — and the
# left-boundary fix (#544) had to land in each (#545). scripts/requirement.lib.sh
# is now the one home on the shell side: the gate's twin, the coverage check
# and the suites source it, and the docs harness's fixture tests hold the
# validator's patterns equal to it (living-spec.test.mjs).
#
# This suite pins the grammar's behavior through the module's surface, pins
# the TWO grammars it holds as two — the living spec's and the PRD's differ,
# and a refactor is not the place to unify them — and proves no copy of an id
# pattern survives outside the home. The home also holds the fence rule
# (#557), which the gate's reduced path check, tests/lib.sh and the kit demo
# read through fence_strip; this suite pins it and proves no copy of the
# fence pattern survives either.
#
# Usage: sh tests/requirement-grammar.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

MODULE="scripts/requirement.lib.sh"

# ---------------------------------------------------------------------------
banner "0. The module exists, is sourceable, and is shared layer"
# ---------------------------------------------------------------------------
[ -f "$ROOT/$MODULE" ] && pass "$MODULE exists" || {
	fail "$MODULE is missing — nothing else in this suite means anything"
	t_done "requirement grammar"
}
# shellcheck disable=SC1090
. "$ROOT/$MODULE"
for fn in req_spec_lines req_spec_ids req_prd_ids fence_strip; do
	command -v "$fn" >/dev/null 2>&1 && pass "sourcing defines $fn" ||
		fail "sourcing $MODULE does not define $fn"
done
for v in REQ_AREA_ERE REQ_FENCE_ERE REQ_FENCE_CLOSE_ERE REQ_LINE_ERE REQ_CITED_NAME_ERE REQ_CITED_TOKEN_ERE \
	REQ_PRD_ID_ERE REQ_PRD_LINE_ERE REQ_BOUNDED_ID_ERE REQ_ID_AREA_MAX REQ_ID_NUM_MAX; do
	eval "val=\${$v:-}"
	[ -n "$val" ] && pass "sourcing sets $v" || fail "sourcing $MODULE leaves $v empty"
done
manifest_section files <"$ROOT/VERSION" | grep -qx "$MODULE" && pass "$MODULE is manifest-listed (shared layer)" ||
	fail "$MODULE is not in VERSION's files: — a consumer's gate would source a file it does not have"

# ---------------------------------------------------------------------------
banner "1. The living spec's grammar (the docs gate's rule, both engines)"
# ---------------------------------------------------------------------------
# A requirement line opens `R<n>.` at the first column, followed by a blank,
# a tab, a carriage return or the line's end; fenced lines are examples, and
# an id is read once. The tab and CR rows are here because they are the two
# characters that reach awk only through -v — a dialect that read them as
# letters would lose those lines.
TAB=$(printf '\t')
CR=$(printf '\r')
SPEC="$SCRATCH/spec.md"
{
	printf '# Billing\n'
	printf 'R1. The invoice SHALL carry the legal name.\n'
	printf 'R2.%sTab-separated.\n' "$TAB"
	printf 'R3.%s\n' "$CR"
	printf 'R4.\n'
	printf 'R0. Numbered from zero, which the living spec admits.\n'
	printf '```\nR5. inside a fence\n```\n'
	printf '~~~\nR6. inside a tilde fence\n~~~\n'
	printf ' R7. indented\n'
	printf 'R8a. not an id\n'
	printf 'R9.x glued\n'
	printf '~~R10.~~ Removed by #1: a tombstone\n'
	printf 'billing/R11. area-qualified, which a living spec line is not\n'
	printf 'R1. again\n'
} >"$SPEC"
got=$(req_spec_ids "$SPEC" | tr '\n' ' ')
[ "$got" = "R1 R2 R3 R4 R0 " ] && pass "req_spec_ids reads R1 R2 R3 R4 R0 — fences, indents, glued and tombstoned lines skipped, each id once" ||
	fail "req_spec_ids read '$got', expected 'R1 R2 R3 R4 R0 '"
lines=$(req_spec_lines "$SPEC" | grep -c '')
[ "$lines" = 6 ] && pass "req_spec_lines prints every requirement line, the repeat included (6)" ||
	fail "req_spec_lines printed $lines lines, expected 6"
got=$(printf 'R1. from stdin\n' | req_spec_lines)
[ "$got" = "R1. from stdin" ] && pass "req_spec_lines reads stdin when given no file" ||
	fail "req_spec_lines on stdin printed '$got'"

for a in billing a a1 sub-billing x-9; do
	printf '%s\n' "$a" | LC_ALL=C grep -Eqx "$REQ_AREA_ERE" && pass "area: '$a' is an area" || fail "area: '$a' was refused"
done
for a in Billing 1billing -billing billing_x 'bill ing' ''; do
	printf '%s\n' "$a" | LC_ALL=C grep -Eqx "$REQ_AREA_ERE" && fail "area: '$a' was accepted" || pass "area: '$a' is no area"
done

# The cited name, with both boundaries: the token ERE swallows one offending
# character on either side and the name ERE, anchored, drops the match.
CITED='(billing/R1) Xbilling/R2 9billing/R3 -billing/R4 sub/billing/R5 billing/R6abc billing/R7_x billing/R8.5 billing/R9. billing/R10-x billing/R11-billing/R12'
got=$(printf '%s\n' "$CITED" | LC_ALL=C grep -o -E "$REQ_CITED_TOKEN_ERE" | LC_ALL=C grep -x -E "$REQ_CITED_NAME_ERE" | tr '\n' ' ')
[ "$got" = "billing/R1 billing/R9 billing/R10 billing/R11 " ] &&
	pass "cited names: only billing/R1, R9, R10 and R11 survive both boundaries" ||
	fail "cited names read '$got', expected 'billing/R1 billing/R9 billing/R10 billing/R11 '"

# ---------------------------------------------------------------------------
banner "1b. Fence detection — one rule, for every reader of a markdown line"
# ---------------------------------------------------------------------------
# A fence OPENS on a line whose first non-blank characters are ``` or ~~~, at
# any indent of blanks and tabs, an info string allowed after the marker. It
# CLOSES on a line holding a run of the SAME character, at least as long as
# the opening run, and nothing after it but blanks, tabs or a carriage return
# — CommonMark's pairing, so a ``` line inside a ~~~ block is quoted material,
# a ```sh line inside a ``` block is too, and a ```` block can quote a ```
# fence. A fence left open runs to the end of its file. Every line from the
# opening to the closing, both included, is quoted material: the living
# spec's readers skip it, and so do the code-span readers — the gate's
# reduced path check, the suites' skill spans, the kit demo's manual commands
# (#557) and the docs harness's readers, which read the same rule from
# validators/living-spec.mjs (#571). fence_strip is that rule as a reader.
DOC="$SCRATCH/fenced.md"
{
	printf 'before `a`\n'
	printf '```sh\nin backtick fence\n```\n'
	printf 'between\n'
	printf '  ~~~\nin indented tilde fence\n  ~~~\n'
	printf '%s```\nin tab-indented fence\n```\n' "$TAB"
	printf '~~~md\n'
	printf '```\n'
	printf 'a backtick line inside a tilde block closes nothing\n'
	printf '```\n'
	printf '~~~\n'
	printf 'after the tilde block\n'
	printf '```\n'
	printf '```sh\n'
	printf 'a closing line with an info string closes nothing\n'
	printf '```%s%s\n' "$TAB" "$CR"
	printf 'after a closing line ending in a tab and a carriage return\n'
	printf '````md\n'
	printf '```\n'
	printf 'a shorter run closes nothing\n'
	printf '`````\n'
	printf 'after a longer closing run\n'
	printf 'x```not a fence\n'
	printf 'after\n'
} >"$DOC"
got=$(fence_strip "$DOC" | tr '\n' '|')
[ "$got" = 'before `a`|between|after the tilde block|after a closing line ending in a tab and a carriage return|after a longer closing run|x```not a fence|after|' ] &&
	pass "fence_strip keeps the lines outside every fence, a marker closed only by its own kind, alone, at least as long" ||
	fail "fence_strip printed '$got'"
printf '~~~\nR1. quoted\n```\nR2. still quoted\n```\n~~~\nR3. outside\n' >"$SCRATCH/mixed-spec.md"
got=$(req_spec_ids "$SCRATCH/mixed-spec.md" | tr '\n' ' ')
[ "$got" = "R3 " ] && pass "req_spec_ids reads the same fences — a ~~~ block quoting a \`\`\` fence hides both of its requirements" ||
	fail "req_spec_ids read '$got' from a ~~~ block quoting a \`\`\` fence, expected 'R3 '"
got=$(printf '```\nhidden\n```\nshown\n' | fence_strip)
[ "$got" = "shown" ] && pass "fence_strip reads stdin when given no file" || fail "fence_strip on stdin printed '$got'"
printf '```\nunclosed\n' >"$SCRATCH/open.md"
printf 'next file\n' >"$SCRATCH/next.md"
got=$(fence_strip "$SCRATCH/open.md"; fence_strip "$SCRATCH/next.md")
[ "$got" = "next file" ] && pass "an unclosed fence hides the rest of its file and no more — one call per file" ||
	fail "an unclosed fence leaked across calls: '$got'"

# ---------------------------------------------------------------------------
banner "2. The PRD's grammar (the coverage check), bounded"
# ---------------------------------------------------------------------------
PRD="$SCRATCH/prd.md"
A32=abcdefghijklmnopqrstuvwxyzabcdef
A33=${A32}g
{
	printf 'R1. A plain requirement.\n'
	printf 'billing/R2. An area-qualified one.\n'
	printf 'R3.\n'
	printf 'R4.%s\n' "$CR"
	printf 'R5.%sTab is no separator here.\n' "$TAB"
	printf 'R0. Not numbered from one.\n'
	printf '%s/R6. at the area bound\n' "$A32"
	printf '%s/R7. past the area bound\n' "$A33"
	printf 'R123456. at the number bound\n'
	printf 'R1234567. past the number bound\n'
	printf ' R8. indented\n'
	printf 'R1. again\n'
} >"$PRD"
got=$(req_prd_ids "$PRD" | tr '\n' ' ')
want="R1 billing/R2 R3 R4 $A32/R6 R123456 "
[ "$got" = "$want" ] && pass "req_prd_ids reads the bounded ids, the CR-ended line included, each once" ||
	fail "req_prd_ids read '$got', expected '$want'"
for id in R1 R999999 billing/R1 "$A32/R1"; do
	printf '%s\n' "$id" | grep -Eqx "$REQ_BOUNDED_ID_ERE" && pass "bounded id: '$id' is an id" || fail "bounded id: '$id' was refused"
done
for id in R0 R01 R1234567 "$A33/R1" Billing/R1 billing/ "R1 "; do
	printf '%s\n' "$id" | grep -Eqx "$REQ_BOUNDED_ID_ERE" && fail "bounded id: '$id' was accepted" || pass "bounded id: '$id' is no id"
done
[ "$REQ_ID_AREA_MAX" = 32 ] && [ "$REQ_ID_NUM_MAX" = 6 ] && pass "the bounds are 32 area characters and 6 digits" ||
	fail "the bounds moved: area $REQ_ID_AREA_MAX, number $REQ_ID_NUM_MAX"
# The bounds are spelled ONCE: req_prd_ids checks them by length (not every
# awk reads an interval) and REQ_BOUNDED_ID_ERE by interval, and both read
# REQ_ID_AREA_MAX and REQ_ID_NUM_MAX. A home whose two values are moved —
# here to 4 and 2 — must move both mechanisms with them; a third spelling
# anywhere in the home stays put and turns this red.
bounds_follow() { # <home> — exit 0 when both mechanisms honor an area of 4 and a number of 2
	sed -e 's/^REQ_ID_AREA_MAX=32$/REQ_ID_AREA_MAX=4/' -e 's/^REQ_ID_NUM_MAX=6$/REQ_ID_NUM_MAX=2/' "$1" >"$SCRATCH/home.moved"
	printf 'abcd/R12. at both\nabcde/R1. past the area\nR123. past the number\n' >"$SCRATCH/bounds.prd"
	(
		# shellcheck disable=SC1091
		. "$SCRATCH/home.moved"
		[ "$(req_prd_ids "$SCRATCH/bounds.prd" | tr '\n' ' ')" = "abcd/R12 " ] || exit 1
		printf 'abcd/R12\n' | grep -Eqx "$REQ_BOUNDED_ID_ERE" || exit 1
		printf 'abcde/R1\n' | grep -Eqx "$REQ_BOUNDED_ID_ERE" && exit 1
		printf 'R123\n' | grep -Eqx "$REQ_BOUNDED_ID_ERE" && exit 1
		exit 0
	)
}
bounds_follow "$ROOT/$MODULE" && pass "the bounds are spelled once: moving the two values moves both the length check and the intervals" ||
	fail "moving REQ_ID_AREA_MAX and REQ_ID_NUM_MAX left a bound behind — the home spells one twice"
# …and the check can go red: a home with a literal interval, or a literal
# length in its awk, keeps a bound the two values no longer say.
sed 's/{0,\$((REQ_ID_AREA_MAX - 1))}/{0,31}/' "$ROOT/$MODULE" >"$SCRATCH/home.interval"
sed 's/-v amax="\$REQ_ID_AREA_MAX"/-v amax=32/' "$ROOT/$MODULE" >"$SCRATCH/home.length"
for h in interval length; do
	! cmp -s "$ROOT/$MODULE" "$SCRATCH/home.$h" && ! bounds_follow "$SCRATCH/home.$h" &&
		pass "the check flags a home that spells the area bound a second time, as a literal $h" ||
		fail "the check passed a home with a literal $h bound — it is vacuous"
done

# ---------------------------------------------------------------------------
banner "3. Two grammars, held as two — the difference is recorded, not unified"
# ---------------------------------------------------------------------------
# The living spec admits R0, a tab and an unbounded id, and no area prefix;
# the PRD admits an area prefix and is bounded. #545 was a refactor, so it
# kept both; a change that merges them changes behavior and is its own ticket.
one() { printf '%s\n' "$1" >"$SCRATCH/one"; }
one 'R0. zero'
[ -n "$(req_spec_ids "$SCRATCH/one")" ] && [ -z "$(req_prd_ids "$SCRATCH/one")" ] &&
	pass "R0. is a living-spec line and no PRD line" || fail "R0. is read alike by both grammars"
one "R1.${TAB}tab"
[ -n "$(req_spec_ids "$SCRATCH/one")" ] && [ -z "$(req_prd_ids "$SCRATCH/one")" ] &&
	pass "a tab after R1. ends a living-spec id and no PRD id" || fail "a tab after R1. is read alike by both grammars"
one 'billing/R1. qualified'
[ -z "$(req_spec_ids "$SCRATCH/one")" ] && [ -n "$(req_prd_ids "$SCRATCH/one")" ] &&
	pass "billing/R1. is a PRD line and no living-spec line" || fail "billing/R1. is read alike by both grammars"
one 'R1234567. long'
[ -n "$(req_spec_ids "$SCRATCH/one")" ] && [ -z "$(req_prd_ids "$SCRATCH/one")" ] &&
	pass "a seven-digit id is a living-spec line and past the PRD's bound" || fail "a seven-digit id is read alike by both grammars"

# ---------------------------------------------------------------------------
banner "4. One home — the readers source it, and no copy survives"
# ---------------------------------------------------------------------------
grep -q 'requirement\.lib\.sh' "$ROOT/scripts/check.sh" && pass "scripts/check.sh sources the home" ||
	fail "scripts/check.sh does not source $MODULE"
grep -q 'requirement\.lib\.sh' "$ROOT/scripts/coverage.sh" && pass "scripts/coverage.sh sources the home" ||
	fail "scripts/coverage.sh does not source $MODULE"
# A COPY is the grammar spelled anywhere but its home. The scans read every
# file kind a pattern could be copied into, each by its own notion of where
# code lives (scan_kind, scan_hits): a shell script, a hook, a workflow or an
# awk program outside its `#` comments; a JavaScript module outside its `//`
# and `*` comment lines; and a markdown file — a skill, an article, a
# template — only INSIDE its fences, which is where a skill's commands are,
# while its prose may name a pattern freely. A `.template` or `.example`
# suffix is read through to the kind beneath it. An id pattern is any of
# `R[0-9]`, `R[1-9]`, `R\d` (or `R\\d`, its spelling inside a JavaScript
# string handed to RegExp, as living-spec.mjs builds its patterns) or
# `R[[:digit:]]`; a fence pattern is the ``` and
# ~~~ alternation in either order — the closing line's run of either kind
# among them — or a three-of-a-kind repetition.
#
# Allowed, and nothing else: the home; the docs harness's validator
# (validators/living-spec.mjs), whose literals living-spec.test.mjs holds
# equal to the home byte for byte (fence.test.mjs holds the two fence
# patterns, and builds its markers so it spells none); that fixture test,
# which plants a drifted copy to prove it fires; and this suite, which plants
# copies of its own.
ID_SPELLINGS='R[0-9]
R[1-9]
R\d
R\\d
R[[:digit:]]'
FENCE_SPELLINGS='```|~~~
~~~|```
```+|~~~+
~~~+|```+
`{3}
~{3}
[`~]{3}
[~`]{3}'
GRAMMAR_ALLOWED="$MODULE
scripts/docs-conformance/validators/living-spec.mjs
scripts/docs-conformance/test/living-spec.test.mjs
tests/requirement-grammar.test.sh"
# The docs harness reads every fence through living-spec.mjs's fencedLines
# (#571): claude-md-refs.mjs's stripFences (and the four validators that call
# it) and banned-words.mjs's leftover pass once kept rules of their own — one
# paired by a backreference, one opened on any whitespace — and now spell no
# fence pattern at all, which the scan below holds.

scan_kind() { # <path> — the kind of code the file holds: sh, js, md, or nothing
	p=$1
	case $p in *.template) p=${p%.template} ;; *.example) p=${p%.example} ;; esac
	case $p in
	*.md) echo md ;;
	*.mjs | *.js | *.cjs) echo js ;;
	*.sh | *.awk | *.yml | *.yaml | .githooks/*) echo sh ;;
	esac
}
scan_hits() { # <spellings> <dir> <file> — <file><TAB><line><TAB><text> per line of code spelling one
	kind=$(scan_kind "$3")
	[ -n "$kind" ] || return 0
	SPELL="$1" awk -v f="$3" -v kind="$kind" -v fence="$REQ_FENCE_ERE" '
		BEGIN { n = split(ENVIRON["SPELL"], s, "\n") }
		kind == "md" { if ($0 ~ fence) { infence = !infence; next } if (!infence) next }
		kind == "sh" && /^[ \t]*#/ { next }
		kind == "js" && /^[ \t]*(\/\/|\/?\*)/ { next }
		{ for (i = 1; i <= n; i++) if (index($0, s[i])) { print f "\t" FNR "\t" $0; next } }
	' "$2/$3"
}
scan_files() { # <dir> — every file of a scanned kind under it, relative, the allowed ones left out
	(cd "$1" && { git ls-files --cached --others --exclude-standard 2>/dev/null ||
		find . \( -name .git -o -name worktree -o -name node_modules -o -path ./.claude/worktrees \) -prune -o -type f -print |
		sed 's|^\./||'; }) | while IFS= read -r f; do
		[ -f "$1/$f" ] && [ -n "$(scan_kind "$f")" ] || continue
		printf '%s\n' "$GRAMMAR_ALLOWED" | grep -Fqx -- "$f" || printf '%s\n' "$f"
	done
}
id_copies() { # <dir> — <file>:<line> of every id pattern spelled outside the home
	scan_files "$1" | while IFS= read -r f; do
		scan_hits "$ID_SPELLINGS" "$1" "$f"
	done | cut -f1,2 | tr '\t' ':'
}
fence_copies() { # <dir> — <file>:<line> of every fence pattern spelled outside the home
	scan_files "$1" | while IFS= read -r f; do
		scan_hits "$FENCE_SPELLINGS" "$1" "$f"
	done | cut -f1,2 | tr '\t' ':'
}

kinds=$(scan_files "$ROOT" | while IFS= read -r f; do scan_kind "$f"; done | sort -u | tr '\n' ' ')
[ "$kinds" = "js md sh " ] && pass "the scans read the kit's shell, JavaScript and markdown files" ||
	fail "the scans read the kinds '$kinds', expected 'js md sh '"
stray=$(id_copies "$ROOT")
[ -z "$stray" ] && pass "no file of any kind outside the home spells an id pattern" ||
	fail "an id pattern is spelled outside $MODULE: $(printf '%s' "$stray" | tr '\n' ' ')"
# Fence detection is one rule in every reader (#557, #571): the gate's reduced
# path check, tests/lib.sh's skill spans and the kit demo's manual commands
# call fence_strip; the docs harness's readers call living-spec.mjs's
# fencedLines, whose patterns its fixture tests hold to the home.
for f in scripts/check.sh tests/lib.sh tests/kit-demo.sh; do
	grep -q 'fence_strip' "$ROOT/$f" && pass "$f reads fence_strip" || fail "$f does not read fence_strip from $MODULE"
done
for f in scripts/docs-conformance/validators/claude-md-refs.mjs scripts/docs-conformance/validators/banned-words.mjs; do
	grep -q '^import { [^}]*fencedLines[^}]* } from "./living-spec.mjs";$' "$ROOT/$f" &&
		pass "$f reads fencedLines from living-spec.mjs" || fail "$f does not import fencedLines from living-spec.mjs"
done
stray=$(fence_copies "$ROOT")
[ -z "$stray" ] && pass "no file of any kind outside the home spells a fence pattern" ||
	fail "a fence pattern is spelled outside $MODULE: $(printf '%s' "$stray" | tr '\n' ' ')"

# …and each scan can go red, in every kind: a tree holding one planted copy
# per kind, beside a comment or prose mention per kind that is no copy.
PLANT="$SCRATCH/plant"
mkdir -p "$PLANT/scripts/docs-conformance/validators" "$PLANT/.agents/skills/x" "$PLANT/.githooks" "$PLANT/templates"
printf '%s\n' '# a comment may say R[0-9] and ```|~~~' "ids=\$(awk '/^R[0-9]+[.]/' \"\$spec\")" \
	"awk '/^[ \\t]*(\`\`\`|~~~)/ { f = !f }' \"\$x\"" >"$PLANT/scripts/plant.sh"
printf '%s\n' '# R[1-9] in a comment' '/^R[1-9][0-9]*[.]/ { print }' '/^[ \t]*(~~~|```)/ { f = !f; next }' >"$PLANT/scripts/plant.awk"
printf '%s\n' '// R\d in a comment' ' * ```|~~~ in a block comment' 'const ID = /^R\d+\./;' 'const FENCE = /^\s*[`~]{3}/;' \
	'const ID_STRING = new RegExp("^R\\d+[.]");' >"$PLANT/scripts/plant.mjs"
printf '%s\n' 'Prose may name `R[[:digit:]]` and ```|~~~ freely.' '' '```sh' "grep -E '^R[[:digit:]]+[.]' spec.md" \
	"awk '/^ *(\`\`\`|~~~)/' x.md" '```' >"$PLANT/.agents/skills/x/SKILL.md"
printf '%s\n' '#!/bin/sh' "grep -E '^R[0-9]+' \"\$1\"" >"$PLANT/.githooks/pre-push"
printf '%s\n' '```' 'grep "R[1-9]" x' '```' >"$PLANT/templates/doc.md.template"
# The two rules the docs harness kept before #571, planted back in their own
# files, and the closing line's pattern copied anywhere: each is flagged.
printf '%s\n' '  return raw.replace(/^[ \t]*(```|~~~)[\s\S]*?^[ \t]*\1[ \t]*$/gm, "");' \
	>"$PLANT/scripts/docs-conformance/validators/claude-md-refs.mjs"
printf '%s\n' '    if (/^\s*(```|~~~)/.test(line)) {' >"$PLANT/scripts/docs-conformance/validators/banned-words.mjs"
printf '%s\n' "awk -v closer='^[ \\t]*(\`\`\`+|~~~+)[ \\t\\r]*\$' '\$0 ~ closer' x.md" >"$PLANT/scripts/closer.sh"
got=$(id_copies "$PLANT" | sort | tr '\n' ' ')
want='.agents/skills/x/SKILL.md:4 .githooks/pre-push:2 scripts/plant.awk:2 scripts/plant.mjs:3 scripts/plant.mjs:5 scripts/plant.sh:2 templates/doc.md.template:2 '
[ "$got" = "$want" ] && pass "the id scan flags a planted copy in a script, an awk program, a module, a hook, a template and a skill's fenced command — and no comment or prose" ||
	fail "the id scan read the planted tree as '$got', expected '$want'"
got=$(fence_copies "$PLANT" | sort | tr '\n' ' ')
want='.agents/skills/x/SKILL.md:5 scripts/closer.sh:1 scripts/docs-conformance/validators/banned-words.mjs:1 scripts/docs-conformance/validators/claude-md-refs.mjs:1 scripts/plant.awk:3 scripts/plant.mjs:4 scripts/plant.sh:3 '
[ "$got" = "$want" ] && pass "the fence scan flags a planted copy of every kind, the harness's two old rules and the closing line's pattern among them" ||
	fail "the fence scan read the planted tree as '$got', expected '$want'"

# ---------------------------------------------------------------------------
banner "5. The readers fail CLOSED without the home"
# ---------------------------------------------------------------------------
# The gate's twin (the reduced engine) and the coverage check both need the
# grammar; a consumer whose copy is missing or empty gets a refusal, never a
# zero-requirement pass.
PROJ="$SCRATCH/proj"
t_consumer_from "$ROOT" "$PROJ" "Grammar Fixture" "grammar@example.invalid" --no-dogfood "Grammar Fixture" "A project with a living spec."
cd "$ROOT" || exit 2
git -C "$PROJ" config core.hooksPath .git/no-such-hooks
# Before the home is taken away: both engines of the gate read one fence rule
# (#571), so a manual whose ~~~ block quotes a ``` fence yields the same code
# spans in both. The quoted span names a file that does not exist, and is
# silent in both engines; the same span after the block is a reference, and
# fails both. Under the toggle the reduced engine kept, the quoted ``` line
# closed the ~~~ block and the span inside fell into the path check.
HAVE_NODE=0; command -v node >/dev/null 2>&1 && HAVE_NODE=1
engines_agree() { # <expected status> <label>
	f=$(cd "$PROJ" && DOCS_CHECK_NO_NODE=1 sh scripts/check.sh >"$SCRATCH/fence-fallback.out" 2>&1; echo $?)
	[ "$f" = "$1" ] && pass "fallback: $2 (exit $f)" ||
		{ fail "fallback: $2 — expected exit $1, got $f"; grep 'missing' "$SCRATCH/fence-fallback.out" | sed 's/^/        | /' | head -4; }
	if [ "$HAVE_NODE" = 1 ]; then
		h=$(cd "$PROJ" && sh scripts/check.sh >/dev/null 2>&1; echo $?)
		[ "$h" = "$1" ] && pass "harness: $2 (exit $h)" || fail "harness: $2 — expected exit $1, got $h"
	else
		printf '  skip  harness half of: %s (no node)\n' "$2"
	fi
}
printf '\n~~~md\n```sh\n`scripts/ghost-quoted.sh`\n```\n~~~\n' >>"$PROJ/AGENTS.md"
engines_agree 0 "a ~~~ block quoting a \`\`\` fence hides the span inside it"
printf '\nSee `scripts/ghost-after.sh`.\n' >>"$PROJ/AGENTS.md"
engines_agree 1 "a span after that block is a reference again"
git -C "$PROJ" checkout -q -- AGENTS.md
(cd "$PROJ" && rm -f "$MODULE" && DOCS_CHECK_NO_NODE=1 sh scripts/check.sh >"$SCRATCH/nogrammar.out" 2>&1; echo $? >"$SCRATCH/nogrammar.rc")
[ "$(cat "$SCRATCH/nogrammar.rc")" = 1 ] && grep -q "shared-layer-missing.*requirement" "$SCRATCH/nogrammar.out" &&
	pass "a missing grammar is a red reduced gate (shared-layer-missing), not a silent pass" ||
	{ fail "with the grammar missing the reduced gate exited $(cat "$SCRATCH/nogrammar.rc")"; sed 's/^/        | /' "$SCRATCH/nogrammar.out" | head -8; }
(cd "$PROJ" && printf '#!/bin/sh\n' >"$MODULE" && DOCS_CHECK_NO_NODE=1 sh scripts/check.sh >"$SCRATCH/emptygrammar.out" 2>&1; echo $? >"$SCRATCH/emptygrammar.rc")
[ "$(cat "$SCRATCH/emptygrammar.rc")" = 2 ] && grep -q "req_spec_ids" "$SCRATCH/emptygrammar.out" &&
	pass "a grammar that defines nothing stops the reduced gate with exit 2, naming the function" ||
	{ fail "with an empty grammar the reduced gate exited $(cat "$SCRATCH/emptygrammar.rc") — expected 2"; sed 's/^/        | /' "$SCRATCH/emptygrammar.out" | head -8; }
(cd "$PROJ" && printf '#!/bin/sh\nreq_spec_ids() { :; }\n' >"$MODULE" && DOCS_CHECK_NO_NODE=1 sh scripts/check.sh >"$SCRATCH/nofence.out" 2>&1; echo $? >"$SCRATCH/nofence.rc")
[ "$(cat "$SCRATCH/nofence.rc")" = 2 ] && grep -q "fence_strip" "$SCRATCH/nofence.out" &&
	pass "a grammar without the fence rule stops the reduced gate with exit 2, naming fence_strip" ||
	{ fail "with no fence_strip the reduced gate exited $(cat "$SCRATCH/nofence.rc") — expected 2"; sed 's/^/        | /' "$SCRATCH/nofence.out" | head -8; }
printf 'R1. one\n' >"$SCRATCH/cov.prd"
printf 'Covers: R1\n' >"$SCRATCH/1"
rm -f "$PROJ/$MODULE"
t_run_split sh "$PROJ/scripts/coverage.sh" "$SCRATCH/cov.prd" "$SCRATCH/1"
[ "$S_STATUS" = 2 ] && [ -z "$S_OUT" ] && printf '%s' "$S_ERR" | grep -q 'requirement\.lib\.sh' &&
	pass "the coverage check without its grammar refuses (exit 2), says why, prints nothing" ||
	fail "the coverage check without its grammar: exit $S_STATUS, stdout '$S_OUT', stderr '$S_ERR'"

t_done "requirement grammar"
