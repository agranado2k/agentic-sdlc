#!/bin/sh
# tests/shell-parse.test.sh — every tracked shell file parses under the two
# shells `sh` really is: dash (Linux, and the kit's CI) and bash 3.2 (macOS's
# /bin/sh).
#
# scripts/agents.kit.sh and tests/vocab.test.sh sat broken on every Mac while
# CI stayed green: bash 3.2 ends a `$( … )` at the first `)` it cannot pair, so
# a `case` pattern with no leading `(`, or a heredoc whose text holds a lone
# `)` or an odd quote, is a syntax error there and nowhere else. dash parses
# both, and every kit CI job ran dash.
#
# WHERE IT CAN FAIL. Only a host that has bash 3.2 can see that failure, so
# this suite's job in kit-ci.yml runs on a macOS runner, which carries both
# shells. Where a shell is missing the suite says so and skips it — except
# under CI (the `CI` variable the runner sets), where a missing shell FAILS: a
# job moved to a runner with no bash 3.2 must not read as one that passed.
#
# WHAT IT CANNOT CATCH. It parses (`-n`) and runs nothing:
# - bash 3.2 reads a `$( … )` inside DOUBLE QUOTES only when it runs it, so
#   `"$(case $x in a) … esac)"` passes here and fails at run time;
# - text handed to a shell later — `eval`, `sh -c '…'`, a script a heredoc
#   writes, a workflow's `run:` block, a Markdown fence — is not a tracked
#   shell file, and is never read as one;
# - a construct that parses in both shells and behaves differently in one.
#
# A shell file is a tracked path ending `.sh` or `.sh.<anything>`, or one whose
# first line is an sh, dash or bash shebang. A bash script is held to bash
# alone: dash never runs it.
#
# Kit-only: bootstrap.sh's KIT_ONLY list deletes it, like every suite.
#
# Usage: sh tests/shell-parse.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
cd "$ROOT" || exit 2
t_init

# bash32 [candidate...] — the first candidate that is bash 3.2, or nothing.
bash32() {
	for _b in "$@"; do
		[ -x "$_b" ] || continue
		case $("$_b" -c 'printf %s "${BASH_VERSION:-}"' 2>/dev/null) in
		3.2.*) printf '%s\n' "$_b" && return 0 ;;
		esac
	done
	return 1
}

# dash_of [candidate...] — the first candidate that is there, or nothing.
dash_of() {
	for _d in "$@"; do
		[ -x "$_d" ] && printf '%s\n' "$_d" && return 0
	done
	return 1
}

# shell_files <repo> — the tracked shell files there, one `<kind> <path>` per
# line, kind `bash` or `sh`.
shell_files() {
	git -C "$1" ls-files | while IFS= read -r f; do
		[ -f "$1/$f" ] || continue
		IFS= read -r first <"$1/$f" || first=${first:-}
		case $first in
		'#!'*/bash | '#!'*/bash' '* | '#!'*' bash' | '#!'*' bash '*) printf 'bash %s\n' "$f" && continue ;;
		'#!'*/sh | '#!'*/sh' '* | '#!'*' sh' | '#!'*' sh '* | '#!'*/dash | '#!'*/dash' '*) printf 'sh %s\n' "$f" && continue ;;
		esac
		case $f in *.sh | *.sh.*) printf 'sh %s\n' "$f" ;; esac
	done
}

# parse_findings <repo> <label> <shell> — one line per tracked shell file under
# <repo> that <shell> does not parse, and one when it read no file at all: a
# scan of nothing holds nothing. Exit 1 when any, 0 when none.
parse_findings() {
	_list=$(shell_files "$1")
	[ -n "$_list" ] || {
		echo "no tracked shell file read under $1"
		return 1
	}
	_found=$(printf '%s\n' "$_list" | while read -r _kind _f; do
		if [ "$_kind" = bash ] && [ "$2" = dash ]; then continue; fi
		_err=$("$3" -n "$1/$_f" 2>&1) ||
			printf '%s does not parse under %s: %s\n' "$_f" "$2" "$(printf '%s\n' "$_err" | head -1)"
	done)
	[ -z "$_found" ] && return 0
	printf '%s\n' "$_found"
	return 1
}

# missing <label> — a shell this host does not have: a failure under CI, a
# visible skip anywhere else.
missing() {
	if [ -n "${CI:-}" ]; then
		fail "this runner has no $1, so a $1 parse failure cannot be seen here"
	else
		note "no $1 on this host — its half is the CI job's to hold"
	fi
}

# fixture <name> — an empty repo the scan can read.
fixture() {
	mkdir -p "$SCRATCH/$1" && git -C "$SCRATCH/$1" init -q && printf '%s\n' "$SCRATCH/$1"
}
track() { git -C "$1" add -A; }

BASH32=$(bash32 /bin/sh /bin/bash) || BASH32=
DASH=$(dash_of /bin/dash /usr/bin/dash) || DASH=

banner "1. The scan itself, under this shell"
d=$(fixture broken)
mkdir -p "$d/scripts" "$d/.githooks"
printf '#!/bin/sh\necho fine\n' >"$d/scripts/fine.sh"
printf '#!/bin/sh\nif true; then\n' >"$d/scripts/broken.sh"
printf '#!/bin/sh\nif true; then\n' >"$d/.githooks/pre-thing"
printf 'if true; then\n' >"$d/scripts/policy.sh.example"
printf 'if this is prose, then (\n' >"$d/README.md"
track "$d"
printf '#!/bin/sh\nif true; then\n' >"$d/scripts/untracked.sh"
out=$(parse_findings "$d" sh /bin/sh) && fail "a tracked file that does not parse passed" ||
	pass "a tracked file that does not parse fails the scan"
for f in scripts/broken.sh .githooks/pre-thing scripts/policy.sh.example; do
	case $out in *"$f does not parse under sh"*) pass "$f is named" ;; *) fail "$f went unnamed: $out" ;; esac
done
for f in scripts/fine.sh README.md scripts/untracked.sh; do
	case $out in *"$f"*) fail "$f was reported: $out" ;; *) pass "$f is not reported" ;; esac
done

d=$(fixture nothing)
out=$(parse_findings "$d" sh /bin/sh) && fail "a scan that read no file passed" ||
	case $out in *"no tracked shell file read"*) pass "a scan that read no file is reported" ;; *) fail "the report does not say nothing was read: $out" ;; esac

d=$(fixture bash-only)
printf '#!/usr/bin/env bash\nx=(a b)\n' >"$d/arrays"
track "$d"
case $(shell_files "$d") in "bash arrays") pass "a bash shebang is held to bash" ;; *) fail "a bash script was read as: $(shell_files "$d")" ;; esac
if [ -n "$DASH" ]; then
	out=$(parse_findings "$d" dash "$DASH") && pass "dash is not asked to parse a bash script" ||
		fail "a bash script was held to dash: $out"
fi

# The two failures a macOS runner is here for.
d=$(fixture bash32)
cat >"$d/case-arm.sh" <<'EOF'
x=$(
	case a in
	a) echo hi ;;
	esac
)
EOF
cat >"$d/heredoc.sh" <<'EOF'
x=$(
	cat <<'EOT'
case $1 in low) ;; esac
EOT
)
EOF
cat >"$d/paired-arm.sh" <<'EOF'
x=$(
	case a in
	(a) echo hi ;;
	esac
)
EOF
track "$d"

banner "2. bash 3.2 — macOS's /bin/sh"
if [ -n "$BASH32" ]; then
	out=$(parse_findings "$d" 'bash 3.2' "$BASH32") && fail "the two constructs bash 3.2 cannot read passed" ||
		pass "a construct bash 3.2 cannot read fails the scan"
	for f in case-arm.sh heredoc.sh; do
		case $out in *"$f does not parse under bash 3.2"*) pass "$f is named" ;; *) fail "$f went unnamed: $out" ;; esac
	done
	case $out in *paired-arm.sh*) fail "the paired pattern was reported: $out" ;; *) pass "a pattern with its leading ( is not reported" ;; esac
	out=$(parse_findings "$ROOT" 'bash 3.2' "$BASH32") && pass "every tracked shell file parses under bash 3.2 ($BASH32)" ||
		fail "$out"
else
	missing 'bash 3.2'
fi

banner "3. dash — Linux's sh"
if [ -n "$DASH" ]; then
	out=$(parse_findings "$d" dash "$DASH") && pass "dash parses the same two constructs: it cannot stand in for bash 3.2" ||
		fail "dash refused a fixture only bash 3.2 should: $out"
	out=$(parse_findings "$ROOT" dash "$DASH") && pass "every tracked shell file parses under dash ($DASH)" ||
		fail "$out"
else
	missing dash
fi

banner "4. A missing shell fails under CI and is a visible skip elsewhere"
out=$(bash32 "$SCRATCH/no-such-shell" ${DASH:+"$DASH"}) && fail "a shell that is not bash 3.2 was taken for it: $out" ||
	pass "a shell that is absent, or is not bash 3.2, is not taken for it"
out=$(CI=true && failures=0 && missing 'bash 3.2' && [ "$failures" = 1 ]) &&
	pass "under CI a missing shell is a failure" || fail "under CI a missing shell passed: $out"
out=$(CI= && failures=0 && missing 'bash 3.2' && [ "$failures" = 0 ]) &&
	pass "outside CI a missing shell is a skip" || fail "outside CI a missing shell failed: $out"
case $out in *"no bash 3.2 on this host"*) pass "the skip names the shell" ;; *) fail "the skip is silent: $out" ;; esac

t_done "every tracked shell file parses under bash 3.2 and dash"
