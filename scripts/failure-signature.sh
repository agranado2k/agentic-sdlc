#!/bin/sh
# failure-signature.sh — the failure signature, and how many runs running
# each one has come back.
#
#   sh scripts/failure-signature.sh sign <name> [<log>|-]
#   sh scripts/failure-signature.sh streak <state-file>
#
# WHAT IT ANSWERS. A loop that fixes and re-runs — /pr-iterate on a PR's
# checks, /implement on its full suite — must stop when the same failure
# comes back unchanged, rather than spend its iterations on a loop that is
# not converging. "The same failure" is this script's to say, so the loop
# stops on evidence and not on its own judgement of progress.
#
# sign — prints one FAILURE SIGNATURE: <name>, a tab, and the first error
# line of the log (a file, or stdin when the log is absent or `-`). The
# first error line is the first line holding `error`, `fail`, `expected`,
# `assert` or `not ok`, case aside; a log with none gives its first
# non-blank line, and an empty log the name and the tab alone. A carriage
# return is dropped and the line trimmed. The digits that are only RUN IDS
# OR TIMESTAMPS are written as one word each, so two runs of one failure
# sign the same:
#   - a date, a time or a date-time — `2026-10-21`, `10:41:40.123`,
#     `2026-10-21T10:41:40.1234567Z`, `20261021T104216Z` — is `<time>`;
#   - a run of 6 or more digits, and a run of 7 or more lowercase hex
#     characters holding a digit and a letter — a run id, a process id, a
#     commit, a trace run's tail — is `<id>`.
# Every other digit is kept: `line 212: expected 3, got 2` is the failure.
# The line is then cut to its first 240 bytes. Two failures are identical
# when their signatures are equal.
#
# streak — reads this run's signatures on stdin, one per line, and prints
# `<count><tab><signature>` for each, in input order, a repeat within the
# run counted once. The count is one more than the state file held for that
# signature, or 1 when it held none — so a signature that differs from the
# previous run's starts again at 1, and one absent from a run (it passed, or
# failed some other way) is forgotten. The state file is then rewritten to
# this run's counts, so the caller runs streak once per run, an empty stdin
# for a run with no failure. A missing state file is an empty one.
#
# EXIT STATUS: 0 the answer on stdout; 2 a caller error — no verb or an
# unknown one, no name, a name that is empty or holds a tab or a newline, an
# unreadable log, no state file, a state file that cannot be written —
# NOTHING on stdout, the reason on stderr.
#
# It reads the log and the state file and writes the state file only; no
# network, no git. The log is untrusted text: it is compared and printed,
# never run.

set -u

die() {
	printf 'failure-signature.sh: %s\n' "$*" >&2
	exit 2
}

usage='usage: failure-signature.sh sign <name> [<log>|-] | streak <state-file>'

# The awk program both verbs share: sig(line) normalises one log line.
# Intervals are spelled out, not written {n}: an awk older than POSIX's
# intervals reads a brace as a literal.
SIG_AWK='
function idrun(s,    out, tok, digit) {
	out = ""
	while (match(s, /[0-9a-f]+/)) {
		tok = substr(s, RSTART, RLENGTH)
		digit = (tok ~ /[0-9]/)
		if ((tok ~ /^[0-9]+$/ && length(tok) >= 6) || (length(tok) >= 7 && digit && tok ~ /[a-f]/))
			tok = "<id>"
		out = out substr(s, 1, RSTART - 1) tok
		s = substr(s, RSTART + RLENGTH)
	}
	return out s
}
function sig(s) {
	sub(/\r$/, "", s)
	gsub(/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9][0-9]:[0-9][0-9]:[0-9][0-9](\.[0-9]+)?Z?/, "<time>", s)
	gsub(/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z?/, "<time>", s)
	gsub(/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/, "<time>", s)
	gsub(/[0-9][0-9]:[0-9][0-9]:[0-9][0-9](\.[0-9]+)?/, "<time>", s)
	s = idrun(s)
	sub(/^[ \t]+/, "", s)
	sub(/[ \t]+$/, "", s)
	return substr(s, 1, 240)
}
'

sign() {
	[ $# -ge 1 ] || die "sign needs a name — $usage"
	name=$1
	[ -n "$name" ] || die "the name is empty"
	case $name in *'	'* | *'
'*) die "the name holds a tab or a newline" ;; esac
	log=${2:--}
	if [ "$log" != - ]; then
		[ -f "$log" ] && [ -r "$log" ] || die "cannot read the log: $log"
	fi
	# Values reach awk through the environment, never -v: -v processes
	# backslash escapes, and a name or a path is the caller's text.
	FS_SIGN_NAME=$name awk "$SIG_AWK"'
		BEGIN { name = ENVIRON["FS_SIGN_NAME"] }
		first == "" && tolower($0) ~ /error|fail|expected|assert|not ok/ { first = $0 }
		blank == "" && $0 !~ /^[ \t\r]*$/ { blank = $0 }
		END {
			line = (first != "") ? first : blank
			printf "%s\t%s\n", name, (line == "" ? "" : sig(line))
		}
	' "$log"
}

streak() {
	[ $# -ge 1 ] && [ -n "$1" ] || die "streak needs a state file — $usage"
	state=$1
	dir=$(dirname "$state")
	[ -d "$dir" ] && [ -w "$dir" ] || die "cannot write the state file's directory: $dir"
	prev=$state
	[ -f "$state" ] || prev=/dev/null
	tmp=$(mktemp "$state.XXXXXX") || die "cannot write beside the state file: $state"
	# shellcheck disable=SC2064
	trap "rm -f '$tmp'" EXIT HUP INT TERM
	FS_STREAK_OUT=$tmp awk '
		BEGIN { out = ENVIRON["FS_STREAK_OUT"] }
		phase != 2 {
			t = index($0, "\t")
			if (t > 0) count[substr($0, t + 1)] = substr($0, 1, t - 1) + 0
			next
		}
		$0 == "" || ($0 in seen) { next }
		{
			seen[$0] = 1
			n = (($0 in count) ? count[$0] : 0) + 1
			printf "%d\t%s\n", n, $0
			printf "%d\t%s\n", n, $0 >out
		}
	' "$prev" phase=2 - >"$tmp.out" || {
		rm -f "$tmp.out"
		die "cannot read the state file: $state"
	}
	[ -f "$tmp" ] || : >"$tmp"
	mv "$tmp" "$state" || {
		rm -f "$tmp.out"
		die "cannot write the state file: $state"
	}
	cat "$tmp.out"
	rm -f "$tmp.out"
}

[ $# -ge 1 ] || die "$usage"
verb=$1
shift
case $verb in
sign) sign "$@" ;;
streak) streak "$@" ;;
*) die "unknown verb '$verb' — $usage" ;;
esac
