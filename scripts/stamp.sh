#!/bin/sh
# stamp.sh — read a ticket's stamp lines, checked, out of an untrusted body.
#
#   sh scripts/stamp.sh <issue-number>
#   sh scripts/stamp.sh T-<n>          (a factory ticket, in a factory project)
#
# A FACTORY TICKET (process/R128 to R134, R138; PRD-12). The one argument is
# digits — an issue number, read from the tracker as below — or a factory
# ticket id, `T-` and 1 to 6 digits; anything else, a temporary `T-~<hex>` id
# included, is a usage error, exit 2. For an id, the checkout is a factory
# project only when the git top level this file lives in holds
# .factory/project.yaml (exit 2 otherwise, nothing run); the reader then runs
# `factory stamp <id>` from that top level, opens no file under .factory/ and
# calls no tracker. What that prints is an untrusted body like an issue's —
# the same lift, bound and checker below, `Label:` lines lifted here and only
# here (an issue's label is the tracker's, never a body line) — and its stderr
# is discarded: every case is named from its exit. Its 2 is 2, 3 is 3, 5 is
# 5, and any other status is 3; a factory ticket never exits 4, since nothing
# is fetched. No `factory` on PATH: exit 3, one stderr line naming the binary
# and the forge-issue form, `sh scripts/stamp.sh <issue-number>`.
#
# WHAT IT ANSWERS. Which `Tier:`, `Confidence:`, `Domain:`, `Targets:`,
# `Class:`, `Covers:`, `Risk:`, `Risk-confidence:` and `Test-tier:` lines a
# ticket carries — `Targets:` a trace filter /retro's before-and-after check
# reads (process/R25), held to its grammar rather than to tokens; `Class:`
# the class /implement records as data.class (#819); `Risk:`,
# `Risk-confidence:` and `Test-tier:` the ticket contract's, fixed by
# the kit's ADR-0037 — and whether the vocabulary checker accepts them. `Covers:` is
# no vocabulary field: this script holds it to the coverage check's grammar
# — a comma-separated list of bounded requirement ids, or `none
# (prefactor|open-issue|release)` — read from req_covers_ids in
# scripts/requirement.lib.sh beside it, the one definition both read, and
# fails closed (exit 3) without that file or that function. A ticket with no `Risk:`
# line gets none printed: the reader that acts on risk reads the absence as
# `high unclear`, and this script never writes a line the planner did not.
# The checker is asked as the default writer, the planner, always: a ticket
# never names a reason the policy reserves for the risk rule. /implement reads
# its ticket's stamp through this script and nothing else: the ticket body is
# untrusted, and a value typed into a quoted shell argument closes the quote
# and runs whatever follows it — so the body never passes through a command an
# agent types, and the only ticket text that leaves this script is lines the
# checker has passed. It replaces a one-line pipe whose status was the
# checker's alone, so a ticket with no stamp and a fetch that failed both
# looked like nothing at all (#331).
#
# EXIT STATUS, one outcome each; stdout carries the stamp and nothing else:
#   0  the checked stamp lines on stdout, as the ticket spells them. A line
#      whose field the policy does not declare is one the checker would
#      ignore, so it is never printed: stderr names its field, and with one
#      dropped the exit is 0 only when the Tier: line was checked and printed;
#   2  a refused value, or a usage error: NOTHING on stdout, the reason on
#      stderr naming the field — never the refused text, which is the
#      ticket's, untrusted; read the line in the ticket, quote it only in a
#      report;
#   3  no stamp read, NOTHING on stdout, and stderr says which case: the
#      body carries no stamp lines (a ticket written before the stamp
#      existed — not a refusal); the checker is gone from this project, or
#      cannot run (its `fields` fails — a policy file missing or malformed —
#      or its check exits with anything but 0 or 2), which fails CLOSED;
#      or a stamp line names a field the policy does not declare, and no
#      Tier: line was left to check. Only a 2 from the check of the lines
#      themselves is a refusal;
#   4  the fetch failed, twice — one retry, never a loop. Never read it as a
#      missing line: it is a stop;
#   5  too many stamp lines — more of one key than the policy's bound (its
#      `bound:` lines under `fields`: 8 a key and 32 `Test-tier:` lines as
#      shipped; STAMP_PER_KEY, 8, for every key when the policy publishes
#      none): a stop, NOTHING on stdout, and stderr names the key and the
#      count, never the lines. Not a refusal and not "no stamp lines"; nothing reaches the
#      checker. (A signal exits 128 + its number, nothing printed — never a
#      verdict.)
#
# THE BOUND. The lift reads by key, and the checker's work is linear in the
# lines it is handed: 2,000 `Tier:` lines cost about 30 CPU-seconds and came
# back at exit 0, every one printed (PR #382). So at most the bound's lines of
# each key go on — enough that a field written twice with two values still reaches the
# checker and is refused (exit 2) — and the count is the one pass over the
# lifted lines that runs before any per-line work, so a body past the bound
# costs what reading it costs.
#
# WHAT IS A STAMP LINE: a BARE `Key: value` line whose key is tier,
# confidence, domain, targets, class, covers, risk, risk-confidence or
# test-tier in any case, indented or not, a space or an underscore standing
# for the hyphen — the way the checker reads a key, so a line the checker
# would read is never one this filter missed. A markdown-wrapped line (`- Tier: …`, `**Tier:** …`) is not one, to
# the filter as to the checker. The locale is pinned to C here, so
# [[:space:]] is ASCII space whatever the caller runs in: a key dressed in a
# no-break or zero-width space is never lifted.
#
# THE TRACKER is GitHub's CLI: `gh issue view <N> --json body --jq .body`.
# THE CHECKER is scripts/vocab.sh, found from the repository root THIS FILE
# lives in — never the caller's cwd, for the reason scripts/vocab.sh gives: a
# foreign clone's scripts are not run as you.
#
# Shared layer (see VERSION): this file is copied verbatim.
set -u
LC_ALL=C
export LC_ALL

_stamp_here=$(cd "$(dirname "$0")" && pwd -P)

stamp_say() { printf 'x stamp: %s\n' "$*" >&2; }

usage() {
	stamp_say "usage: sh scripts/stamp.sh <issue-number> | T-<n> — the issue's number, digits only, or a factory ticket id, T- and 1 to 6 digits (a temporary T-~<hex> id is not stampable)"
	exit 2
}

[ $# = 1 ] || usage
case $1 in
T-[0123456789]*)
	case ${1#T-} in *[!0123456789]*) usage ;; esac
	[ ${#1} -le 8 ] || usage
	ticket=$1 _subj="ticket $1" _label_word='Label:, ' _lift_label='label|'
	;;
'' | *[!0123456789]*) usage ;;
*) issue=$1 ticket= _subj="issue #$1" _label_word= _lift_label= ;;
esac

_stamp_root=$( (unset GIT_DIR GIT_WORK_TREE && git -C "$_stamp_here" rev-parse --show-toplevel) 2>/dev/null) ||
	_stamp_root=$(dirname "$_stamp_here")
vocab="$_stamp_root/scripts/vocab.sh"

# --- a factory ticket: a factory project, and the factory's own reader -------
# Decided before anything is made or run: the manifest's presence, read and
# nothing more, then the binary. Nothing is fetched, so no case here is 4.
if [ -n "$ticket" ]; then
	if [ ! -f "$_stamp_root/.factory/project.yaml" ]; then
		stamp_say "$ticket: this checkout is no factory project — no .factory/project.yaml at its git top level, $_stamp_root; nothing read"
		exit 2
	fi
	if ! command -v factory >/dev/null 2>&1; then
		stamp_say "$ticket: no \`factory\` binary on PATH, so no factory stamp read — read the ticket's forge issue instead: sh scripts/stamp.sh <issue-number>"
		exit 3
	fi
fi

# --- fetch, once more on failure -------------------------------------------
_stamp_tmp=$(mktemp -d "${TMPDIR:-/tmp}/stamp.XXXXXX") || {
	stamp_say "no scratch directory — nothing read"
	[ -n "$ticket" ] && exit 3
	exit 4
}
# The EXIT trap cleans up; a signal EXITS, so the script never reads on with
# its scratch directory gone (a handler that only cleaned up would return).
trap 'rm -rf "$_stamp_tmp"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

stamp_fetch() { gh issue view "$issue" --json body --jq .body >"$_stamp_tmp/body"; }
if [ -n "$ticket" ]; then
	# Run from the git top level, its stdout the untrusted body below; its
	# stderr discarded — every case is named here, from the status alone.
	_frc=0
	(cd "$_stamp_root" && unset GIT_DIR GIT_WORK_TREE && exec factory stamp "$ticket") >"$_stamp_tmp/body" 2>/dev/null || _frc=$?
	case $_frc in
	0) ;;
	2)
		stamp_say "$ticket: factory stamp refused it — no such ticket, or a refused value; nothing printed"
		exit 2
		;;
	3)
		stamp_say "$ticket: factory stamp read no stamp — no stamp line, or no checker; not a refusal, nothing printed"
		exit 3
		;;
	5)
		stamp_say "$ticket: factory stamp found too many stamp lines of a key — a stop, nothing printed"
		exit 5
		;;
	*)
		stamp_say "$ticket: factory stamp exited $_frc, a status it does not define — no stamp read, nothing printed"
		exit 3
		;;
	esac
elif ! stamp_fetch && ! stamp_fetch; then
	stamp_say "fetching issue #$issue failed twice (the tracker's error is above) — a stop, never a missing line"
	exit 4
fi

# --- the checker: present, runnable, and what it declares --------------------
# Asked BEFORE anything is lifted. A checker that cannot answer `fields` —
# gone, or a policy file missing or malformed — cannot check either, and its
# exit 2 there is not a refusal of the ticket: exit 3, nothing printed.
if [ ! -f "$vocab" ]; then
	stamp_say "the checker $vocab is gone from this project — no stamp read, nothing unchecked printed"
	exit 3
fi
if ! sh "$vocab" fields >"$_stamp_tmp/fields" 2>/dev/null; then
	stamp_say "the checker $vocab cannot run here (its policy file missing or malformed?) — no stamp read, nothing unchecked printed"
	exit 3
fi
# stamp_declared <key> — does the policy declare the field?
stamp_declared() { grep -qE "^$1( \\((open|query|qualified|keyed)\\))?:( |\$)" "$_stamp_tmp/fields"; }
# stamp_key <line> — the line's key, folded as the checker folds one: case
# dropped, a run of spaces or underscores read as a hyphen. It is one of the
# words the filter matched, so it is safe to print; the value is not.
stamp_key() {
	printf '%s\n' "${1%%:*}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
		-e 's/[[:space:]_][[:space:]_]*/-/g' | tr 'A-Z' 'a-z'
}
# stamp_covers_value <line> — a Covers: line's value, trimmed.
stamp_covers_value() { printf '%s\n' "${1#*:}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
# stamp_covers_ok <line> — a Covers: line in the coverage check's grammar,
# req_covers_ids in scripts/requirement.lib.sh: one definition, both read it.
stamp_covers_ok() { req_covers_ids "$(stamp_covers_value "$1")" >/dev/null; }

# --- lift ------------------------------------------------------------------
# A NUL is a line break here: GNU grep reads a body holding one as binary and
# lifts nothing, and a NUL inside a value must split it, never vanish from it.
tr -d '\r' <"$_stamp_tmp/body" | tr '\000' '\n' |
	grep -iE "^[[:space:]]*(${_lift_label}tier|confidence|domain|targets|class|covers|risk|risk(-|[[:space:]_]+)confidence|test(-|[[:space:]_]+)tier)[[:space:]]*:" >"$_stamp_tmp/lifted"
if [ ! -s "$_stamp_tmp/lifted" ]; then
	stamp_say "$_subj carries no Tier:, Confidence:, ${_label_word}Domain:, Targets:, Class:, Covers:, Risk:, Risk-confidence: or Test-tier: line — no stamp read, not a refusal"
	exit 3
fi
# The bound, per key whatever its spelling: the keys are the filter's words,
# folded, safe to print, and so is a count; the lines are not. The policy
# publishes it (`bound: <n>`, `bound <field>: <n>`); one that publishes none
# leaves every key at STAMP_PER_KEY.
STAMP_PER_KEY=8
_over=$(awk -v max="$STAMP_PER_KEY" '
	FILENAME == bounds {
		if ($0 ~ /^bound: [0-9]+$/) { sub(/^bound: /, ""); max = $0 + 0 }
		else if ($0 ~ /^bound [a-z][a-z0-9-]*: [0-9]+$/) { k = $2; sub(/:$/, "", k); b[k] = $3 + 0 }
		next
	}
	{
		k = $0; sub(/:.*/, "", k); sub(/^[[:space:]]*/, "", k); sub(/[[:space:]]*$/, "", k)
		gsub(/[[:space:]_]+/, "-", k); n[tolower(k)]++
	}
	END {
		split("class confidence covers domain label risk risk-confidence targets test-tier tier", ks, " ")
		for (i = 1; i in ks; i++) {
			k = ks[i]; m = (k in b) ? b[k] : max
			if (n[k] > m) printf "%s%d %s lines", (s++ ? ", " : ""), n[k], k
		}
		if (s) { printf " — past the bound of %d a key", max; for (k in b) printf ", %d %s", b[k], k }
	}' bounds="$_stamp_tmp/fields" "$_stamp_tmp/fields" "$_stamp_tmp/lifted")
if [ -n "$_over" ]; then
	stamp_say "$_subj: too many stamp lines — $_over; nothing checked, nothing printed — a stop"
	exit 5
fi

# A line whose field the policy does not declare is one the checker would
# ignore — so it is never checked, and never printed.
_dropped=0
_covers=0
: >"$_stamp_tmp/lines"
while IFS= read -r line; do
	key=$(stamp_key "$line")
	if [ "$key" = covers ]; then
		printf '%s\n' "$line" >>"$_stamp_tmp/lines"
		_covers=1
	elif stamp_declared "$key"; then
		printf '%s\n' "$line" >>"$_stamp_tmp/lines"
	else
		stamp_say "$_subj: the $key line names a field this project's policy does not declare — not checked, not printed"
		_dropped=1
	fi
done <"$_stamp_tmp/lifted"

# --- check -----------------------------------------------------------------
# Covers: lines first, against the requirement grammar: each in its shape,
# and one value however many lines say it. Without the grammar no Covers:
# line can be read, and nothing unchecked is printed.
_cov_bad=0
if [ "$_covers" = 1 ]; then
	_grammar="$_stamp_root/scripts/requirement.lib.sh"
	if [ ! -r "$_grammar" ]; then
		stamp_say "$_subj carries a Covers: line and the requirement grammar $_grammar is gone — no stamp read, nothing unchecked printed"
		exit 3
	fi
	# shellcheck disable=SC1090
	. "$_grammar"
	command -v req_covers_ids >/dev/null 2>&1 || {
		stamp_say "$_subj carries a Covers: line and the requirement grammar $_grammar defines no req_covers_ids — no stamp read, nothing unchecked printed"
		exit 3
	}
	_cov_seen=
	while IFS= read -r line; do
		[ "$(stamp_key "$line")" = covers ] || continue
		_cov_v=$(stamp_covers_value "$line")
		req_covers_ids "$_cov_v" >/dev/null || { _cov_bad=1; continue; }
		[ -z "$_cov_seen" ] || [ "$_cov_seen" = "$_cov_v" ] || _cov_bad=1
		_cov_seen=$_cov_v
	done <"$_stamp_tmp/lines"
fi
_rc=0
[ -s "$_stamp_tmp/lines" ] && { sh "$vocab" <"$_stamp_tmp/lines" 2>/dev/null || _rc=$?; }
[ "$_rc" = 0 ] && [ "$_cov_bad" = 1 ] && _rc=2
case $_rc in
0)
	if [ "$_dropped" = 1 ] && ! grep -qiE '^[[:space:]]*tier[[:space:]]*:' "$_stamp_tmp/lines"; then
		stamp_say "$_subj: no Tier: line was checked — no stamp read"
		exit 3
	fi
	cat "$_stamp_tmp/lines"
	exit 0
	;;
2) ;;
*)
	stamp_say "the checker $vocab cannot run the check (exit $_rc) — no stamp read, nothing unchecked printed"
	exit 3
	;;
esac

# Refused. Name the field of each line the checker refuses on its own, and
# say so when only the lines together are refused.
_named=0
while IFS= read -r line; do
	key=$(stamp_key "$line")
	if [ "$key" = covers ]; then
		stamp_covers_ok "$line" && continue
		stamp_say "$_subj: the covers line is refused — it is neither a comma-separated list of requirement ids nor none (prefactor|open-issue|release); the value is not printed: it is the ticket's text"
		_named=1
		continue
	fi
	printf '%s\n' "$line" | sh "$vocab" 2>/dev/null && continue
	stamp_say "$_subj: the $key line is refused — its value is not in the $key vocabulary ($(sed -n -e "s/^$key (query):.*/a trace filter: kind=<kind> and up to seven <key>=<value> terms/p" -e "s/^$key (keyed): \\(.*\\)/a requirement id, then one of \\1/p" -e "s/^$key\\( (open)\\)\\{0,1\\}: //p" -e "s/^$key (qualified): //p" "$_stamp_tmp/fields")); the value is not printed: it is the ticket's text"
	_named=1
done <"$_stamp_tmp/lines"
[ "$_named" = 1 ] ||
	stamp_say "$_subj: the stamp lines are refused together — a field given two values, or a rule across fields; read them in the ticket"
exit 2
