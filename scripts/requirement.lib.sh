#!/bin/sh
# scripts/requirement.lib.sh — the one grammar for requirement lines and ids,
# and for the fences that hide a markdown line from every reader of one.
#
# THE FENCE (#557, #571) — CommonMark's pairing. A fence OPENS on a line
# whose first non-blank characters are ``` or ~~~ (REQ_FENCE_ERE: any indent
# of blanks and tabs, an info string allowed after the marker), and CLOSES on
# a line holding a run of the SAME character at least as long as the opening
# run, with nothing after it but blanks, tabs or a carriage return
# (REQ_FENCE_CLOSE_ERE, plus the kind and the length, which no ERE can
# compare). So a ``` line inside a ~~~ block is quoted material, a ```sh line
# inside a ``` block is too, and a ```` block can quote a ``` fence — which
# is why a manual reaches for the other kind or a longer run. A fence left
# open runs to the end of its file. Every line from the opening to the
# closing, both included, is quoted material: the requirement reader below
# skips them, and so does every code-span reader of the shell side — the
# gate's reduced path check (scripts/check.sh), the suites' skill spans
# (tests/lib.sh) and the kit demo's manual commands, all through fence_strip.
# The docs harness reads the same rule through validators/living-spec.mjs's
# fencedLines (its code-span readers, banned-words' prose pass and the living
# spec's reader), and its fixture tests hold both patterns equal to this file
# byte for byte and its reading equal to fence_strip line for line. The fence
# lives HERE rather than in a module of its own because the requirement
# grammar was its first home and a 0.54.0 consumer's fixture test already
# holds REQ_FENCE_ERE to this file: a move would turn that test red for
# nothing. Before #571 this home TOGGLED on either marker, and the harness
# kept two rules of its own; the three agreed on every document the kit
# tracks, and disagreed only on mixed or longer fences.
#
# A requirement is a numbered line (ADR-0012). Two readers read it, and they
# read DIFFERENT shapes on purpose, so this file holds two grammars side by
# side and never derives one from the other:
#
#   THE LIVING SPEC (the docs gate's living-spec rule, both engines) — a line
#   of `<specsDir>/<area>.md` that opens `R<n>.` at the first column, then a
#   blank, a tab, a carriage return or the line's end, outside a ``` or ~~~
#   fence. The area is the file's name; outside the file the requirement is
#   cited as `<area>/R<n>`. n is any run of digits — R0 included — and no id
#   is bounded.
#
#   THE PRD (the coverage check, scripts/coverage.sh) — a line of a PRD body
#   that opens `R<n>.` or `<area>/R<n>.` at the first column, then a space or
#   the line's end once a trailing carriage return is dropped — a tab is no
#   separator here. n is from 1, and an id is BOUNDED: the area at most
#   REQ_ID_AREA_MAX characters, the number at most REQ_ID_NUM_MAX digits, so
#   no id can carry prose to an output stream.
#
# The two differ in four ways — R0, a tab after the full stop, an area prefix
# on the line, and the bounds — and tests/requirement-grammar.test.sh pins
# each difference: unifying them is a behavior change, its own ticket (#545
# was a refactor and recorded them, nothing more). What they share is the
# AREA token, which both spell from REQ_AREA_ERE.
#
# DIALECT. Every pattern here is an ERE that means the same thing to awk, to
# `grep -E` and to JavaScript's RegExp: a literal full stop is `[.]`, never a
# backslash, and the only backslashes are `\t` and `\r`, in the three patterns
# awk reads only through `-v` (the two fence patterns and REQ_LINE_ERE), which
# turns them into the characters themselves in every awk. The docs harness's
# validator
# (validators/living-spec.mjs) keeps its own copies of the living-spec
# patterns, because a fixture-tree run must not depend on a shell file, and
# its fixture tests hold each one equal to this file byte for byte.
#
# Sourceable (`. scripts/requirement.lib.sh`), then:
#
#   req_spec_lines [<file>]   the living-spec requirement lines, fences skipped
#   req_spec_ids [<file>]     their ids, `R<n>`, in file order, each once
#   req_prd_ids [<file>]      a PRD body's bounded ids, in order, each once
#   fence_strip [<file>]      the lines outside every fence, fence lines dropped
#
# Each reads stdin when given no file, prints nothing but what it names, and
# exits with awk's status. Fence state lasts one call, so a caller with
# several files calls once per file: a fence left open hides the rest of its
# own file and no more.
#
# Shared layer: this file is manifest-listed and copied verbatim into a
# consumer, where scripts/check.sh (its reduced engine) and scripts/coverage.sh
# source it; both fail closed without it.

# The area: one lowercase token. Unanchored — `grep -x` and the callers add
# the anchors.
REQ_AREA_ERE='[a-z][a-z0-9-]*'

# --- the living spec --------------------------------------------------------
REQ_FENCE_ERE='^[ \t]*(```|~~~)'
REQ_FENCE_CLOSE_ERE='^[ \t]*(```+|~~~+)[ \t\r]*$'
REQ_LINE_ERE='^R[0-9]+[.]([ \t\r]|$)'
# A cited name, unanchored; and the token the gate cuts out of a test file:
# it swallows one letter, digit, `_`, `-` or `/` before the name and one
# letter, digit, `_`, or `.` and a digit after it, so the name ERE, anchored
# at both ends, then drops a match that was the middle of a longer token (the
# leading boundary, #544, and the trailing one).
REQ_CITED_NAME_ERE="$REQ_AREA_ERE/R[0-9]+"
REQ_CITED_TOKEN_ERE="[A-Za-z0-9_/-]?$REQ_CITED_NAME_ERE([A-Za-z0-9_]|[.][0-9])?"

# --- the PRD ----------------------------------------------------------------
REQ_ID_AREA_MAX=32
REQ_ID_NUM_MAX=6
REQ_PRD_ID_ERE='R[1-9][0-9]*'
# The line's opening, unbounded: req_prd_ids checks the bounds by length, not
# by an interval in the pattern, because not every awk reads one.
REQ_PRD_LINE_ERE="^($REQ_AREA_ERE/)?$REQ_PRD_ID_ERE[.]"
# One bounded id, for `grep -E` (which does read intervals): the area token
# held to REQ_ID_AREA_MAX characters, the number to REQ_ID_NUM_MAX digits.
REQ_BOUNDED_ID_ERE="([a-z][a-z0-9-]{0,$((REQ_ID_AREA_MAX - 1))}/)?R[1-9][0-9]{0,$((REQ_ID_NUM_MAX - 1))}"

# The fence as an awk program's opening rules, read with -v opener= and
# -v closer= set to the two fence patterns: every fence line and every line
# between is consumed (`next`), so the rules after it see the lines outside
# every fence and nothing else. `run` is the run of marker characters a line
# opens with once its indent is dropped — the kind is its first character.
_REQ_FENCE_AWK='
	function run(s,    c, n) {
		sub(/^[ \t]*/, "", s)
		c = substr(s, 1, 1)
		for (n = 1; substr(s, n + 1, 1) == c; n++);
		return substr(s, 1, n)
	}
	fence == "" && $0 ~ opener { fence = run($0); next }
	fence != "" {
		if ($0 ~ closer) {
			r = run($0)
			if (substr(r, 1, 1) == substr(fence, 1, 1) && length(r) >= length(fence)) fence = ""
		}
		next
	}
'

req_spec_lines() {
	awk -v opener="$REQ_FENCE_ERE" -v closer="$REQ_FENCE_CLOSE_ERE" -v line="$REQ_LINE_ERE" \
		"$_REQ_FENCE_AWK"'$0 ~ line' "$@"
}

fence_strip() {
	awk -v opener="$REQ_FENCE_ERE" -v closer="$REQ_FENCE_CLOSE_ERE" "$_REQ_FENCE_AWK"'{ print }' "$@"
}

req_spec_ids() {
	req_spec_lines "$@" | awk '{ sub(/[.].*/, ""); if (!seen[$0]++) print }'
}

req_prd_ids() {
	awk -v id="$REQ_PRD_LINE_ERE" -v amax="$REQ_ID_AREA_MAX" -v nmax="$REQ_ID_NUM_MAX" '
		{ sub(/\r$/, "") }
		$0 ~ id "$" || $0 ~ id " " {
			r = $0; sub(/[.].*/, "", r)
			a = r; if (!sub(/\/.*/, "", a)) a = ""
			n = r; sub(/^.*R/, "", n)
			if (length(a) > amax || length(n) > nmax) next
			if (!seen[r]++) print r
		}
	' "$@"
}
