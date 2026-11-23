#!/bin/sh
# tests/factory-no-mirror.test.sh — the kit stops mirroring its factory tickets
# as forge issues (PRD-15 slice 6, T-92).
#
# Until PRD-15 landed, every factory ticket of this repository was also opened
# as a GitHub issue, and the ticket's body pointed at it with a
# `GitHub issue: #<N>` line: the chain could only build a ticket by its issue
# number. Slices 1 to 5 taught the chain the factory id, so from the stop date
# on a factory ticket has no issue, and this suite is what holds that:
#
# - process/R243: a ticket created on or after the stop date that carries a
#   `GitHub issue:` line fails the suite, named;
# - process/R244: a ticket created before the stop date keeps its line and
#   passes — its stamp lives in that issue, so it is built by number until
#   done.
#
# The stop date is the day T-92 landed; D-02's decisions.md and the diary's
# Current state record the same date. A ticket with no readable `created:` date
# is reported too: a scan that cannot date a ticket must not read as one that
# passed it.
#
# Kit-only: bootstrap.sh's KIT_ONLY list deletes it, like every suite. A
# consumer factory project never mirrored, so it has nothing to hold.
#
# Usage: sh tests/factory-no-mirror.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
cd "$ROOT" || exit 2
t_init

STOP_DATE=2026-11-23

# mirror_findings <items-dir> — one line per factory ticket under <items-dir>
# that breaks the stop; exit 1 when any, 0 when none. A ticket is an item whose
# front matter says `type: ticket`; its line is one that reads exactly
# `GitHub issue: #<digits>`, so the form quoted in prose is not one. ISO dates
# compare as strings.
mirror_findings() {
	find "$1" -name '*.md' -type f | LC_ALL=C sort | while IFS= read -r f; do
		awk -v stop="$STOP_DATE" '
			NR == 1 && $0 == "---" { fm = 1; next }
			fm && $0 == "---" { fm = 0; next }
			fm && /^id: / { id = substr($0, 5) }
			fm && /^type: / { type = substr($0, 7) }
			fm && /^created: / { created = substr($0, 10) }
			!fm && /^GitHub issue: #[0-9]+$/ { line = $0 }
			END {
				if (type != "ticket") exit
				if (created !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/)
					printf "%s: no created date the stop can be judged against\n", id
				else if (line != "" && created >= stop)
					printf "%s: created %s, on or after the stop date %s, carries \"%s\"\n", id, created, stop, line
			}
		' "$f"
	done | awk '{ print } END { exit NR > 0 }'
}

# ticket <dir> <id> <created> [<body line>] — write one fixture ticket.
ticket() {
	mkdir -p "$1/$2"
	{
		printf -- '---\nid: %s\ntype: ticket\ntitle: A fixture ticket\n' "$2"
		[ -n "$3" ] && printf 'created: %s\n' "$3"
		printf 'stage: ready\n---\n\n# %s · A fixture ticket\n\n## Acceptance\n\n' "$2"
		[ -n "${4:-}" ] && printf '%s\n' "$4"
	} >"$1/$2/ticket.md"
}

# --- process/R243: on or after the stop date, a mirrored ticket fails, named ---
d="$SCRATCH/on-stop"
ticket "$d" T-95 "$STOP_DATE" 'GitHub issue: #980'
out=$(mirror_findings "$d") && fail "process/R243: a ticket created on the stop date with a GitHub issue line passed" ||
	case $out in *T-95*) pass "process/R243: a ticket created on the stop date with a GitHub issue line fails, named" ;;
	*) fail "process/R243: the failure does not name T-95: $out" ;; esac

d="$SCRATCH/after-stop-mirrored"
ticket "$d" T-96 2026-12-01 'GitHub issue: #981'
out=$(mirror_findings "$d") && fail "process/R243: a ticket created after the stop date with a GitHub issue line passed" ||
	case $out in *T-96*) pass "process/R243: a ticket created after the stop date with a GitHub issue line fails, named" ;;
	*) fail "process/R243: the failure does not name T-96: $out" ;; esac

d="$SCRATCH/after-stop-clean"
ticket "$d" T-97 2026-12-01
out=$(mirror_findings "$d") && pass "process/R243: a ticket created after the stop date with no GitHub issue line passes" ||
	fail "process/R243: a ticket with no GitHub issue line failed: $out"

# --- process/R244: before the stop date, the line is kept and passes ---
d="$SCRATCH/before-stop"
ticket "$d" T-60 2026-11-22 'GitHub issue: #923'
out=$(mirror_findings "$d") && pass "process/R244: a ticket created the day before the stop date keeps its GitHub issue line and passes" ||
	fail "process/R244: a ticket created before the stop date failed: $out"

# --- a ticket the scan cannot date is reported, never passed ---
d="$SCRATCH/undated"
ticket "$d" T-98 '' 'GitHub issue: #982'
out=$(mirror_findings "$d") && fail "a ticket with no created date passed unjudged" ||
	case $out in *T-98*) pass "a ticket with no created date is reported, named" ;;
	*) fail "the undated report does not name T-98: $out" ;; esac

# --- the same line in a non-ticket item, or quoted in prose, is not a mirror ---
d="$SCRATCH/not-a-line"
ticket "$d" T-99 2026-12-01 'The old form was `GitHub issue: #1`, now gone.'
mkdir -p "$d/PRD-20" && printf -- '---\nid: PRD-20\ntype: prd\ncreated: 2026-12-01\n---\n\nGitHub issue: #5\n' >"$d/PRD-20/prd.md"
out=$(mirror_findings "$d") && pass "only a ticket's own GitHub issue line counts: prose and other items pass" ||
	fail "prose or a non-ticket item was read as a mirror: $out"

# --- process/R243, process/R244: this repository's own factory items, at the head ---
out=$(mirror_findings "$ROOT/.factory/items") && pass "process/R243, process/R244: this repository's factory tickets keep the stop" ||
	fail "process/R243: this repository's factory tickets break the stop: $out"

t_done
