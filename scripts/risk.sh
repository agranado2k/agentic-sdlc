#!/bin/sh
# risk.sh — the RISK RULE: a pull request's effective risk, judged from the
# planner's `Risk:` stamp and the earned records of the review areas its diff
# touches, printed as closed tokens and recorded once as a `risk.judge` event.
#
#   sh scripts/risk.sh <base> <head> --pr <N> [--ticket <N>|T-<n>] [--ticket-file <path>]
#
# REPORT-ONLY. What it prints changes no exit code and no action of any skill
# or script; /pr-iterate puts the effective line at the top of its report,
# marked reported only (the kit's PRD-09; the decision record that lets a chain
# skill run it amends the kit's ADR-0024 clauses 7 and 9).
#
# WHAT IT PRINTS, on stdout, in this order and nothing else (runtime/R53):
#   effective: <risk>
#   planner: <risk>
#   rule: <risk>
#   area: <review area> earned|unlearned     one per area the diff touches,
#                                            in the lens roster's order, then
#                                            `area: none unlearned` when a
#                                            changed path is in no area
#   switch: on|tripped
# A <risk> is `low` or `high <reason>`, each checked by the vocabulary checker
# as the risk rule (`--writer risk-rule`); a refusal prints nothing, exit 2.
#
# THE PLANNER'S RISK is the ticket's `Risk:` line and nothing else, lifted by
# the stamp reader (scripts/stamp.sh) from `--ticket` — an issue number, or a
# factory ticket id — or from `--ticket-file`, a body the stamp reader reads
# through a stand-in tracker, as the skill dispatcher reads one. No ticket, no
# `Risk:` line, or any stamp-reader exit but 0 reads `high unclear`
# (the kit's ADR-0037 clause 3); nothing is written into the ticket.
#
# THE RULE'S RISK. Each review area the diff (merge-base(<base>, <head>) to
# <head>) touches is EARNED when the trace's record reader, in its settled form
# (`trace.sh record --settled`), shows 20 settled landings, a miss rate below
# the risk policy's `miss-rate-below`, a precision at or above its
# `precision-floor`, and no missed mistake on a landing still inside the fix
# window (runtime/R55); any other area is UNLEARNED, and so is a path in no
# area (`none`). The thresholds are read through the policy reader at <base>
# (`policy.sh thresholds --base`), never the pull request's tree.
#
# THE REVIEW AT THE HEAD. The rule reads the latest Axis-2 `review.verdict`
# on the PR stamped at or after the head commit's committer date (UTC), as
# the landing script reads "at the head". Its `data.outward` of 1 or more —
# something outside the PR relies on an unspecified change
# (the kit's ADR-0038) — makes the rule's risk `high outward` while it counts
# more outward items than are ruled `keep` at that head, as the ruling
# recorder (scripts/ruling.sh) reads it: the latest `operator` or `default`
# ruling of the item at the head reads keep, and a `session` ruling never
# counts (runtime/R59). A verdict that names no outward items is lifted by no
# ruling, and neither is one the recorder cannot read. No such verdict, one
# only at an older commit, or one that carries no outward count in digits
# makes it `high unclear`: the rule cannot rule out an outward item
# it has not seen (runtime/R60).
#
# The reason, in order: `outward`, then `unlearned` (any unlearned area),
# then `unclear`; else `low`. Unlearned areas keep their `area:` lines and
# `data.unlearned` whichever reason prints.
#
# FAILING CLOSED. A policy reader exit other than 0 (thresholds it cannot
# give), an unconfigured trace, a trace whose SCHEMA the reader cannot judge,
# or a record reader exit other than 0 makes every area unlearned; the cause is
# said on stderr, the lines are printed, and the exit is 0. An unconfigured or
# unjudgeable trace records nothing.
#
# THE EFFECTIVE RISK is the higher of the two, `high` above `low`; on high it
# carries the rule's reason when the rule says high, the planner's otherwise
# (runtime/R61). The two DISAGREE when their levels differ.
#
# THE KILL SWITCH is TRIPPED when the risk policy at <base> sets
# `RISK_KILL_SWITCH=tripped`, when that value cannot be read there (the policy
# reader's `read` fails closed, or the value is unset or neither `on` nor
# `tripped`), or when the TRIP MARKER, a file named `risk-switch-tripped` in
# the clone's git directory (`git rev-parse --git-common-dir`, so every
# worktree of the clone shares it), exists; it is `on` otherwise (runtime/R66).
# While it is tripped, a rule's `low` becomes `high unlearned`; a rule already
# high keeps its reason (runtime/R65). The value is read only from the base's
# copy of the policy, evaluated in a child process with the name unset — never
# the environment, never the pull request's tree (runtime/R67). Anyone may
# trip it; resetting is the operator's: delete the marker, or land the value.
#
# THE EVENT. One `risk.judge`, subject `pr:#<N>`, `related` the ticket when a
# `--ticket` names one, outcome `agreed` or `disagreed`, and in data the head
# commit, the planner's, rule's and effective risks, the unlearned areas and
# the switch (runtime/R63). When the trace already holds a `risk.judge` for
# that PR and head with the same risks and switch, nothing is recorded
# (runtime/R64). Nothing else is written (runtime/R68).
#
# WHAT LEAVES IT: risk tokens, review area names from the lens-slice policy,
# `none`, the switch words, digits and commit shas — never text from a ticket
# body, a pull request body or a commit message (runtime/R69).
#
# Exit: 0 whatever risk it prints; 2 a caller error, or a value the
# vocabulary checker refused — nothing on stdout, nothing recorded.
#
# Shared layer (see VERSION): copied verbatim, not edited downstream. The
# thresholds are yours, in scripts/risk.config.sh; the review areas in
# scripts/lens-slice.config.sh.

set -u
LC_ALL=C
export LC_ALL

_here=$(cd "$(dirname "$0")" && pwd -P)

die() {
	echo "risk: $*" >&2
	exit 2
}
say() { echo "risk: $*" >&2; }

usage='usage: sh scripts/risk.sh <base> <head> --pr <N> [--ticket <N>|T-<n>] [--ticket-file <path>]'
[ $# -ge 2 ] || die "$usage"
base_ref=$1
head_ref=$2
shift 2
pr= ticket= ticket_file=
while [ $# -gt 0 ]; do
	case $1 in
	--pr | --ticket | --ticket-file)
		[ $# -ge 2 ] || die "$usage"
		case $1 in
		--pr) pr=$2 ;;
		--ticket) ticket=$2 ;;
		--ticket-file) ticket_file=$2 ;;
		esac
		shift 2
		;;
	*) die "$usage" ;;
	esac
done
case $pr in '' | 0* | *[!0-9]*) die "--pr takes a pull request's number, digits: $usage" ;; esac
case $ticket in
'') ;;
T-[0-9]*) case ${ticket#T-} in *[!0-9]*) die "--ticket takes an issue number or a factory ticket id" ;; esac ;;
0* | *[!0-9]*) die "--ticket takes an issue number or a factory ticket id" ;;
esac
[ -z "$ticket_file" ] || [ -f "$ticket_file" ] || die "--ticket-file is not a file"
base=$(git rev-parse --verify --quiet "$base_ref^{commit}") || die "the base names no commit here"
head=$(git rev-parse --verify --quiet "$head_ref^{commit}") || die "the head names no commit here"
mb=$(git merge-base "$base" "$head" 2>/dev/null) || die "the base and the head share no history"

_tmp=$(mktemp -d "${TMPDIR:-/tmp}/risk.XXXXXX") || die "no scratch directory"
trap 'rm -rf "$_tmp"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# --- the planner's risk -------------------------------------------------------
# risk_of <stamp lines file> — the value of the one `Risk:` line, normalized,
# when it is of the risk grammar; nothing otherwise.
risk_of() {
	sed -n 's/^[[:space:]]*[Rr][Ii][Ss][Kk][[:space:]]*:[[:space:]]*//p' "$1" | head -n 1 |
		tr -s ' \t' '  ' | sed 's/[[:space:]]*$//' | grep -xE 'low|high [a-z-]+'
}
planner='high unclear'
if [ -n "$ticket" ] || [ -n "$ticket_file" ]; then
	_rc=0
	if [ -n "$ticket_file" ] && [ "${ticket#T-}" = "$ticket" ]; then
		# The body is read THROUGH the stamp reader: a stand-in tracker hands it
		# the file as the issue's body, so its lift, bound and checker apply.
		printf '#!/bin/sh\nexec cat "$RISK_TICKET_FILE"\n' >"$_tmp/gh"
		chmod +x "$_tmp/gh"
		PATH="$_tmp:$PATH" RISK_TICKET_FILE=$ticket_file sh "$_here/stamp.sh" "${ticket:-1}" >"$_tmp/stamp" 2>/dev/null || _rc=$?
	else
		sh "$_here/stamp.sh" "$ticket" >"$_tmp/stamp" 2>/dev/null || _rc=$?
	fi
	if [ "$_rc" = 0 ]; then
		_p=$(risk_of "$_tmp/stamp") && [ -n "$_p" ] && planner=$_p
	fi
fi

# --- the review areas the diff touches ----------------------------------------
git -c core.quotePath=false diff --name-only -z --no-renames "$mb" "$head" 2>/dev/null | tr '\0' '\n' | sed '/^$/d' >"$_tmp/paths" ||
	die "git cannot produce the diff"
sh "$_here/lens-slice.sh" --areas <"$_tmp/paths" >"$_tmp/areas" 2>/dev/null || die "the lens-slice policy cannot be read"
# The areas touched, in roster order: the roster is the lines with no path.
awk -F '\t' '$2 == "" { r[++n] = $1; next } { hit[$1] = 1; seen[$2] = 1 }
	END { for (i = 1; i <= n; i++) if (r[i] in hit) print r[i] }' "$_tmp/areas" >"$_tmp/touched"
_none=$(awk -F '\t' 'NR == FNR { if ($2 != "") seen[$2] = 1; next } NF && !($0 in seen) { print "none"; exit }' "$_tmp/areas" "$_tmp/paths")

# --- the earned records ---------------------------------------------------------
closed=
miss= floor=
_rc=0
sh "$_here/policy.sh" thresholds --base "$base" >"$_tmp/thr" 2>/dev/null || _rc=$?
if [ "$_rc" = 0 ]; then
	miss=$(sed -n 's/^miss-rate-below \([0-9][0-9]*\)$/\1/p' "$_tmp/thr")
	floor=$(sed -n 's/^precision-floor \([0-9][0-9]*\)$/\1/p' "$_tmp/thr")
fi
if [ -z "$miss" ] || [ -z "$floor" ]; then
	say "the risk policy's thresholds cannot be read at the base — every area is unlearned"
	closed=1
fi
record=1
if [ -z "$(sh "$_here/trace.sh" dir 2>/dev/null)" ]; then
	say "the trace is unconfigured — every area is unlearned, nothing recorded"
	closed=1 record=
else
	_rc=0
	sh "$_here/trace.sh" record --settled >"$_tmp/record" 2>/dev/null || _rc=$?
	case $_rc in
	0) ;;
	3)
		say "the trace's SCHEMA is not one this reader can judge — every area is unlearned, nothing recorded"
		closed=1 record=
		;;
	*)
		say "the record reader exited $_rc — every area is unlearned"
		closed=1
		;;
	esac
fi

# The verdict per touched area: earned only when the record says so.
if [ -n "$closed" ]; then
	awk '{ print $1 "\tunlearned" }' "$_tmp/touched" >"$_tmp/verdicts"
else
	awk -v miss="$miss" -v floor="$floor" -v full=20 '
		NR == FNR {
			if (NF == 11 && $2 == "landings" && $4 == "missed" && $6 == "held" && $8 == "judged" && $10 == "window-missed")
				ok[$1] = ($3 == full && $5 * 100 < miss * $3 && $9 > 0 && $7 * 100 >= floor * $9 && $11 == 0)
			next
		}
		{ print $1 "\t" (($1 in ok) && ok[$1] ? "earned" : "unlearned") }' "$_tmp/record" "$_tmp/touched" >"$_tmp/verdicts"
fi
[ -z "$_none" ] || printf 'none\tunlearned\n' >>"$_tmp/verdicts"
unlearned=$(awk -F '\t' '$2 == "unlearned" { printf "%s%s", s, $1; s = " " }' "$_tmp/verdicts")

# --- the review at the head -----------------------------------------------------
# The latest Axis-2 review.verdict on pr:#<N> stamped at or after the head
# commit's committer date, both UTC ISO seconds compared as strings — the
# landing script's reading of "at the head" (the kit's ADR-0032). The
# envelope (subject, stamp) is read up to the data map; axis and outward from
# the map. Prints its data.outward, `-` when it carries no count in digits;
# nothing when there is no such verdict, or the trace cannot be read.
outward=
if [ -n "$record" ]; then
	head_at=$(TZ=UTC git show -s --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd "$head" 2>/dev/null)
	outward=$(sh "$_here/trace.sh" show "pr:#$pr" --kind review.verdict 2>/dev/null |
		awk -v s="\"subject\":\"pr:#$pr\"" -v h="$head_at" '
			{ e = $0; m = ""; d = index(e, ",\"data\":{"); if (d) { m = substr(e, d); e = substr(e, 1, d - 1) } }
			h != "" && index(e, s) && match(e, /"ts":"[^"]*"/) && substr(e, RSTART + 6, RLENGTH - 7) >= h &&
			match(m, /"axis":"2"/) {
				o = match(m, /"outward":"[0-9]+"/) ? substr(m, RSTART + 11, RLENGTH - 12) : "-"
			}
			END { if (o != "") print o }')
fi
# The outward items ruled `keep` at the head, as the ruling recorder reads
# them: the latest operator or default ruling of the item at that head reads
# keep, and a session ruling never counts (runtime/R59). Only its `ruled:`
# lines are counted; a recorder that is absent, refuses or fails counts none.
ruled=0
case $outward in
'' | - | 0) ;;
*)
	if [ -f "$_here/ruling.sh" ]; then
		_rc=0
		sh "$_here/ruling.sh" "$pr" --unruled --head "$head" >"$_tmp/ruled" 2>/dev/null || _rc=$?
		[ "$_rc" = 0 ] && ruled=$(grep -c '^ruled: A2-[0-9][0-9]* ' "$_tmp/ruled")
	fi
	;;
esac

# --- the kill switch ----------------------------------------------------------------
# The base's value, read through the policy reader and evaluated in a child
# process that starts with the name unset, so neither the environment nor the
# pull request's tree can stand in for it; then the trip marker.
switch=tripped
_sw=
_copy=$(sh "$_here/policy.sh" read scripts/risk.config.sh --base "$base" 2>/dev/null) && [ -f "$_copy" ] &&
	_sw=$(sh -c 'unset RISK_KILL_SWITCH; . "$1" >/dev/null 2>&1 </dev/null; command printf "%s\n" "${RISK_KILL_SWITCH-}"' _ "$_copy" 2>/dev/null)
case $_sw in
on) switch=on ;;
tripped) ;;
*) say "the kill switch's value cannot be read at the base — the switch reads tripped" ;;
esac
_gd=$(git rev-parse --git-common-dir 2>/dev/null) || _gd=
if [ -z "$_gd" ] || [ -e "$_gd/risk-switch-tripped" ] || [ -L "$_gd/risk-switch-tripped" ]; then
	switch=tripped
fi

# --- the verdict ------------------------------------------------------------------
# The rule's reason, in order: outward, then unlearned, then unclear.
rule=low
case $outward in
'' | -) rule='high unclear' ;;
esac
[ -z "$unlearned" ] || rule='high unlearned'
case $outward in '' | - | 0) ;; *) [ "$ruled" -ge "$outward" ] || rule='high outward' ;; esac
# A tripped switch lets the rule call nothing low (runtime/R65).
[ "$switch" = on ] || [ "$rule" != low ] || rule='high unlearned'
plevel=${planner%% *}
rlevel=${rule%% *}
if [ "$rlevel" = high ]; then
	effective=$rule
elif [ "$plevel" = high ]; then
	effective=$planner
else
	effective=low
fi
outcome=agreed
[ "$plevel" = "$rlevel" ] || outcome=disagreed

# risk_checked <risk> — the one value, of the risk grammar's shape, checked as
# the risk rule. One call per value: the checker refuses one field written
# twice with two values.
risk_checked() {
	case $1 in low | "high "*) ;; *) return 1 ;; esac
	sh "$_here/vocab.sh" check --writer risk-rule "Risk: $1" >/dev/null 2>&1
}
# Every Risk value checked before a line is printed.
for _v in "$effective" "$planner" "$rule"; do
	risk_checked "$_v" || die "the vocabulary checker refused a risk value — nothing printed"
done

{
	printf 'effective: %s\nplanner: %s\nrule: %s\n' "$effective" "$planner" "$rule"
	awk -F '\t' '{ print "area: " $1 " " $2 }' "$_tmp/verdicts"
	printf 'switch: %s\n' "$switch"
} >"$_tmp/out"
cat "$_tmp/out"

# --- the event --------------------------------------------------------------------
[ -n "$record" ] || exit 0
# Already judged: the same PR, head, risks and switch.
sh "$_here/trace.sh" show "pr:#$pr" --kind risk.judge 2>/dev/null |
	grep -F "\"head\":\"$head\"" | grep -F "\"planner\":\"$planner\"" | grep -F "\"rule\":\"$rule\"" |
	grep -F "\"effective\":\"$effective\"" | grep -qF "\"switch\":\"$switch\"" && exit 0
related=
case $ticket in
'') ;;
T-*) related="ticket:$ticket" ;;
*) related="ticket:#$ticket" ;;
esac
TRACE_QUIET=1 sh "$_here/trace.sh" emit kind=risk.judge "subject=pr:#$pr" ${related:+"related=$related"} "outcome=$outcome" \
	"data.head=$head" "data.planner=$planner" "data.rule=$rule" "data.effective=$effective" \
	${unlearned:+"data.unlearned=$unlearned"} "data.switch=$switch" >/dev/null 2>&1 ||
	say "the trace refused the risk.judge event — the verdict above stands, unrecorded"
exit 0
