#!/bin/sh
# ruling.sh — the RULING RECORDER: records a `keep` or `change` ruling on one
# outward item of a pull request's Axis-2 confirm-list as a `ruling` event, and
# lists the outward items not yet ruled `keep` at the head, each with the two
# commands that would rule it (the kit's PRD-11 slice 3; the kit's ADR-0048 clauses 7, 8).
#
#   sh scripts/ruling.sh <PR> <A2-n> keep|change [--head <commit>]
#   sh scripts/ruling.sh <PR> --unruled [--head <commit>]
#
# THE INTERFACE — the later tickets build on it, so it is fixed here:
#   * arguments: the PR's number (digits), then the item id `A2-<n>` and one
#     of `keep` and `change`, or `--unruled`. `--head <commit>` names the head
#     to rule at, read from the local clone; left out, the head is the forge's
#     (`gh pr view <PR> --json headRefOid,commits`), its sha and committed date.
#     Any other argument is a caller error, and so is any argument naming
#     `by` (`--by`, `by=…`, `data.by=…`): who rules is never the caller's word
#     (runtime/R145).
#   * THE VERDICT AT THE HEAD: the latest Axis-2 `review.verdict` on pr:#<PR>
#     in the trace, which must be stamped at or after the head commit's
#     committed date (UTC) — the landing script's reading of "at the head"
#     (the kit's ADR-0032), the one the risk rule reads. Its
#     `data.outward_items`, `A2-<n>:<surface>` entries, are the outward items;
#     a surface the vocabulary's `surface` field does not hold reads `other`
#     (process/R148). No Axis-2 verdict, a latest one older than the head, or
#     an item not among its outward items: exit 2, nothing recorded
#     (runtime/R144).
#   * WHO RULES (`data.by`): `session` when any agent-harness marker below is
#     set and non-empty, `operator` otherwise — the pre-commit hook's list,
#     word for word, held equal by tests/ruling.test.sh. `default` is written
#     only by the ruling defaults (a later slice: `--defaults`, reserved here
#     and refused today as a caller error).
#   * THE EVENT: `ruling`, subject pr:#<PR>, outcome keep|change,
#     `data.item`, `data.surface`, `data.head` (the head's 40-hex sha) and
#     `data.by`. When the trace already holds a ruling with the same PR, item,
#     head, by and outcome, nothing is recorded (runtime/R146).
#   * RULED: an outward item is ruled `keep` at a head when the latest of its
#     rulings at that head by `operator` or `default` reads `keep` — a
#     `session` ruling never counts (the risk rule's runtime/R59).
#   * STDOUT, recording: one line, `ruling: <outcome> pr:#<PR> <item>
#     <surface> <head> <by>` — printed also when the ruling was already held.
#     `--unruled`, per outward item in confirm-list order: `ruled: <item>
#     <surface> <by>` for one ruled keep at the head; otherwise
#     `unruled: <item> <surface>`, then `keep: sh <self> <PR> <item> keep` and
#     `change: sh <self> <PR> <item> change`, which /pr-iterate prints beside
#     the item and runs neither (process/R150). <self> is scripts/ruling.sh, or
#     the wrapper RULING_SELF names when it is of the form scripts/<name>.sh
#     (the kit's own, scripts/ruling.kit.sh).
#   * NOTHING ELSE LEAVES IT: item ids, surface tokens, PR numbers, commit
#     shas and the `ruling` kind's words — never text from a PR, a comment, a
#     commit message or a ticket (runtime/R147). The forge is asked for a sha
#     and a date, each held to its shape before use.
#
# An unconfigured trace records nothing, prints nothing on stdout, says so on
# stderr and exits 0 (runtime/R148).
#
# Exit: 0 recorded, already held, listed, or an unconfigured trace; 1 the trace
# refused the event; 2 a caller error, or no verdict or item to rule on —
# nothing recorded; 3 a trace whose SCHEMA the reader cannot judge; 4 the forge
# named no head.
#
# Shared layer (see VERSION): copied verbatim, not edited downstream.

set -u
LC_ALL=C
export LC_ALL

_here=$(cd "$(dirname "$0")" && pwd -P)

die() {
	echo "ruling: $*" >&2
	exit 2
}
say() { echo "ruling: $*" >&2; }

# The agent-harness markers: .githooks/pre-commit's agent_markers, word for word.
agent_markers='CLAUDECODE CLAUDE_CODE_SESSION_ID TRACE_SESSION GEMINI_CLI CODEX_SANDBOX CODEX_SANDBOX_NETWORK_DISABLED CODEX_THREAD_ID'

usage='usage: sh scripts/ruling.sh <PR> <A2-n> keep|change [--head <commit>] | <PR> --unruled [--head <commit>]'
[ $# -ge 2 ] || die "$usage"
pr=$1
shift
for _a in "$@"; do
	case $_a in
	--by | --by=* | by=* | data.by=*) die "who rules is read from the environment, never an argument — nothing recorded" ;;
	esac
done
case $pr in '' | 0* | *[!0-9]*) die "the PR is its number, digits: $usage" ;; esac
[ ${#pr} -le 9 ] || die "the PR is its number, digits: $usage"
mode= item= outcome= head_arg=
while [ $# -gt 0 ]; do
	case $1 in
	--unruled) [ -z "$mode" ] || die "$usage"; mode=unruled; shift ;;
	--head) [ $# -ge 2 ] || die "$usage"; head_arg=$2; shift 2 ;;
	A2-*)
		[ -z "$mode" ] || die "$usage"
		case ${1#A2-} in '' | *[!0-9]*) die "an item is A2-<n>: $usage" ;; esac
		[ ${#1} -le 11 ] || die "an item is A2-<n>: $usage"
		[ $# -ge 2 ] || die "$usage"
		case $2 in keep | change) ;; *) die "a ruling is keep or change: $usage" ;; esac
		mode=rule item=$1 outcome=$2
		shift 2
		;;
	*) die "$usage" ;;
	esac
done
[ -n "$mode" ] || die "$usage"

self=scripts/ruling.sh
case ${RULING_SELF-} in
scripts/*.sh) case ${RULING_SELF#scripts/} in *[!a-z0-9.-]* | .*) ;; *) self=$RULING_SELF ;; esac ;;
esac

# --- the trace ----------------------------------------------------------------
if [ -z "$(sh "$_here/trace.sh" dir 2>/dev/null)" ]; then
	say "the trace is unconfigured — nothing recorded"
	exit 0
fi

# --- the head -----------------------------------------------------------------
iso='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
if [ -n "$head_arg" ]; then
	head=$(git rev-parse --verify --quiet "$head_arg^{commit}" 2>/dev/null) || die "--head names no commit here"
	head_at=$(TZ=UTC git show -s --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd "$head" 2>/dev/null)
else
	_f=$(gh pr view "$pr" --json headRefOid,commits --jq '.headRefOid as $h
		| {oid: $h, committedDate: ((.commits // []) | map(select(.oid == $h)) | last | .committedDate // "")}
		| to_entries[] | "\(.key)=\(.value | tostring | gsub("[\r\n]"; " "))"' 2>/dev/null) || _f=
	head=$(printf '%s\n' "$_f" | sed -n 's/^oid=//p' | head -n 1)
	head_at=$(printf '%s\n' "$_f" | sed -n 's/^committedDate=//p' | head -n 1)
fi
printf '%s\n' "$head" | grep -qxE '[0-9a-f]{40}' || {
	echo "ruling: the forge named no head commit for PR #$pr — nothing recorded" >&2
	exit 4
}
expr "x$head_at" : "x$iso\$" >/dev/null || {
	echo "ruling: the head commit of PR #$pr carries no committed date — nothing recorded" >&2
	exit 4
}

# --- the verdict at the head --------------------------------------------------
_tmp=$(mktemp -d "${TMPDIR:-/tmp}/ruling.XXXXXX") || die "no scratch directory"
trap 'rm -rf "$_tmp"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# show <kind> — the PR's events of that kind, subject matched on the envelope.
show() {
	_rc=0
	sh "$_here/trace.sh" show "pr:#$pr" --kind "$1" >"$_tmp/$1" 2>/dev/null || _rc=$?
	case $_rc in
	0) ;;
	3)
		echo "ruling: the trace's SCHEMA is not one this reader can judge — nothing recorded" >&2
		exit 3
		;;
	*) die "the trace could not be read — nothing recorded" ;;
	esac
	awk -v s="\"subject\":\"pr:#$pr\"" '{ e = $0; d = index(e, ",\"data\":{"); if (d) e = substr(e, 1, d - 1) } index(e, s)' "$_tmp/$1"
}

# The latest Axis-2 verdict: its stamp, then its outward items one a line.
show review.verdict | awk '
	{ e = $0; m = ""; d = index(e, ",\"data\":{"); if (d) { m = substr(e, d); e = substr(e, 1, d - 1) } }
	match(m, /"axis":"2"/) {
		t = match(e, /"ts":"[^"]*"/) ? substr(e, RSTART + 6, RLENGTH - 7) : ""
		l = match(m, /"outward_items":"[^"]*"/) ? substr(m, RSTART + 17, RLENGTH - 18) : ""
	}
	END { if (t != "") { print t; n = split(l, a, ","); for (i = 1; i <= n; i++) print a[i] } }' >"$_tmp/verdict"
verdict_at=$(sed -n 1p "$_tmp/verdict")
[ -n "$verdict_at" ] || die "PR #$pr has no Axis-2 verdict in the trace — nothing recorded"
expr "x$verdict_at" : "x$iso\$" >/dev/null && [ "$(expr "$verdict_at" \>= "$head_at")" = 1 ] ||
	die "PR #$pr's latest Axis-2 verdict predates its head $head — review the head first; nothing recorded"

# surface_of <word> — the word when the vocabulary's surface field holds it,
# `other` otherwise (process/R148).
surface_checked() { sh "$_here/vocab.sh" "Surface: $1" >/dev/null 2>&1; }
surface_of() {
	case $1 in '' | *[!a-z0-9-]*) echo other; return ;; esac
	if [ -f "$_here/vocab.sh" ] && ! surface_checked "$1"; then echo other; else echo "$1"; fi
}
# The outward items, `<item> <surface>` a line, in confirm-list order.
: >"$_tmp/items"
sed 1d "$_tmp/verdict" | while IFS= read -r _e; do
	_i=${_e%%:*}
	printf '%s\n' "$_i" | grep -qxE 'A2-[0-9]+' || continue
	printf '%s %s\n' "$_i" "$(surface_of "${_e#*:}")"
done >"$_tmp/items"

# The rulings at the head: `<item> <by> <outcome>` a line, oldest first.
show ruling | grep -F "\"head\":\"$head\"" | awk '
	function v(k) { return match($0, "\"" k "\":\"[^\"]*\"") ? substr($0, RSTART + length(k) + 4, RLENGTH - length(k) - 5) : "" }
	{ print v("item"), v("by"), v("outcome") }' >"$_tmp/rulings"

# ruled_by <item> — the maker of the latest operator or default ruling at the
# head when it reads keep; nothing otherwise.
ruled_by() {
	awk -v i="$1" '$1 == i && ($2 == "operator" || $2 == "default") { b = $2; o = $3 } END { if (o == "keep") print b }' "$_tmp/rulings"
}

if [ "$mode" = unruled ]; then
	while read -r _i _s; do
		_b=$(ruled_by "$_i")
		if [ -n "$_b" ]; then
			printf 'ruled: %s %s %s\n' "$_i" "$_s" "$_b"
		else
			printf 'unruled: %s %s\nkeep: sh %s %s %s keep\nchange: sh %s %s %s change\n' "$_i" "$_s" "$self" "$pr" "$_i" "$self" "$pr" "$_i"
		fi
	done <"$_tmp/items"
	exit 0
fi

# --- the ruling -----------------------------------------------------------------
surface=$(awk -v i="$item" '$1 == i { print $2; exit }' "$_tmp/items")
[ -n "$surface" ] || die "$item is not among the outward items of PR #$pr's latest Axis-2 verdict — nothing recorded"
by=operator
for _m in $agent_markers; do
	eval "_v=\${$_m:-}"
	[ -z "$_v" ] || { by=session; break; }
done
line="ruling: $outcome pr:#$pr $item $surface $head $by"
if awk -v i="$item" -v b="$by" -v o="$outcome" '$1 == i && $2 == b && $3 == o { f = 1 } END { exit !f }' "$_tmp/rulings"; then
	say "that ruling is already in the trace — nothing recorded"
	printf '%s\n' "$line"
	exit 0
fi
TRACE_QUIET=1 sh "$_here/trace.sh" emit kind=ruling "subject=pr:#$pr" "outcome=$outcome" \
	"data.item=$item" "data.surface=$surface" "data.head=$head" "data.by=$by" >/dev/null 2>&1 || {
	echo "ruling: the trace refused the ruling — nothing recorded" >&2
	exit 1
}
printf '%s\n' "$line"
exit 0
