#!/bin/sh
# tests/acceptance-tripwires.test.sh — the edit-time tripwires: an agent's
# edit or commit of an approved acceptance test file is refused before CI
# (PRD-14 slice 5, factory T-91; acceptance/R38, acceptance/R39).
#
# Two hooks ask the acceptance guard (scripts/acceptance-guard.sh `held`, read
# at the default branch, the guard run as the default branch holds it) which
# files are held:
#
#   1. the Claude Code adapter's pre-tool hook, root-guard.sh, refuses an
#      Edit, Write, MultiEdit or notebook edit of a held file (R38);
#   2. `.githooks/pre-commit` refuses an agent's commit that stages a held
#      file at content other than its approved content (R39).
#
# Both are tripwires for an honest build, never the judge: both fail open when
# the guard is missing or errors, because CI's `check` fails closed behind
# them. Every case was driven RED first, against hooks with no tripwire.
#
# Usage: sh tests/acceptance-tripwires.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
. "$KIT/tests/lib.sh"
t_init

TF=tests/report.test.sh
T90=.factory/items/T-90/ticket.md
HELD_LINE="held: T-90 $TF"

# --- fixture ------------------------------------------------------------------
# A factory project. main holds the acceptance guard and the scripts it reads
# through, the guards policy, the manifest, and T-90 approved at APPROVAL — a
# commit on the side branch `t90-tests` that holds the approved test file. The
# root guard and the commit hook are copied in where the kit keeps them, and
# the session builds T-90 in the linked worktree `worktree/b`.
t_repo
FIX=$(cd "$REPO" && pwd -P)
for f in acceptance-guard.sh policy.sh vocab.sh vocab.config.sh guards.lib.sh requirement.lib.sh; do
	mkdir -p "$FIX/scripts" && cp "$KIT/scripts/$f" "$FIX/scripts/$f"
done
t_write "$FIX" scripts/guards.config.sh "GUARD_SOURCE_RE='^src/'
"
t_write "$FIX" .factory/project.yaml 'id: fixture
acceptance_tests_since: 2026-11-01
'
printf 'worktree/\n' >"$FIX/.gitignore"
mkdir -p "$FIX/.githooks" && cp "$KIT/.githooks/pre-commit" "$FIX/.githooks/pre-commit"
t_commit "$FIX" "chore: a factory project" >/dev/null
git -C "$FIX" checkout -q -b t90-tests
t_write "$FIX" "$TF" 'test "totals by area"
'
APPROVAL=$(t_commit "$FIX" "test: T-90's acceptance tests")
git -C "$FIX" checkout -q main
t_write "$FIX" "$T90" "---
id: T-90
type: ticket
title: totals by area
stage: build
created: 2026-11-02
tests:
  commit: \"$APPROVAL\"
  by: \"operator\"
  at: 2026-11-02
---

# T-90

Covers: report/R3
Test-tier: report/R3 suite
Accept-test: report/R3 $TF::totals by area
"
t_commit "$FIX" "chore: approve T-90's tests" >/dev/null
git -C "$FIX" config core.hooksPath "$FIX/.githooks"
git -C "$FIX" worktree add -q "$FIX/worktree/b" -b feat/t-90 2>/dev/null
WT="$FIX/worktree/b"

HOOKDIR="$FIX/adapters/claude-code/hooks"
mkdir -p "$HOOKDIR"
cp "$KIT/adapters/claude-code/hooks/root-guard.sh" "$KIT/adapters/claude-code/hooks/hook.lib.sh" "$HOOKDIR/"
GUARD="$HOOKDIR/root-guard.sh"

# payload <tool> <file_path> [<cwd>] — one compact PreToolUse payload.
payload() {
	printf '{"session_id":"s-1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"file_path":"%s","content":"x"},"tool_use_id":"toolu_1"}' \
		"${3:-$WT}" "$1" "$2"
}

# hook_on <payload> — the pre-tool hook with the payload on stdin.
hook_on() {
	printf '%s' "$1" >"$SCRATCH/payload.json"
	t_exec sh "$GUARD" <"$SCRATCH/payload.json"
}

# as_agent <cmd…> — run with one agent-harness marker set, the others unset.
as_agent() { (t_as_human && CLAUDECODE=1 && export CLAUDECODE && "$@"); }

# commit_in_wt <subject> — an agent's commit of what is staged in the worktree.
commit_in_wt() { t_exec as_agent git -C "$WT" commit -q -m "$1"; }

# refused <label> <blocking status> — the status, the guard's line on stderr.
refused() {
	expect_status "$2" "$1 is refused"
	expect_err_has "$HELD_LINE" "and the refusal names the ticket and the path"
	expect_out_is "" "and stdout stays empty"
}

# ---------------------------------------------------------------------------
banner "acceptance/R38: the pre-tool hook refuses an edit or a write of a held file"
# ---------------------------------------------------------------------------
hook_on "$(payload Edit "$WT/$TF")"
refused "an Edit of $TF in the build's worktree" 2
hook_on "$(payload Write "$WT/$TF")"
refused "a Write of $TF in the build's worktree" 2
hook_on "$(payload MultiEdit "$TF")"
refused "a MultiEdit of $TF, the path relative to the session's directory" 2
hook_on "$(payload Write "$WT/tests/other.test.sh")"
expect_status 0 "a Write of a file no held ticket names goes through"
expect_err_lacks "held:" "and says nothing"
printf '{"session_id":"s-1","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"NotebookEdit","tool_input":{"notebook_path":"%s"},"tool_use_id":"toolu_1"}' "$WT" "$WT/$TF" >"$SCRATCH/payload.json"
t_exec sh "$GUARD" <"$SCRATCH/payload.json"
refused "a notebook edit of $TF" 2
# A path under a directory that does not exist at the filesystem's root: the
# walk up to an existing directory must end, and the hook fail open (#1009 M-1).
printf '%s' "$(payload Write /t91-no-such-dir/x.sh)" >"$SCRATCH/payload.json"
t_exec timeout 20 sh "$GUARD" <"$SCRATCH/payload.json"
expect_status 0 "a Write under a missing top-level directory goes through, and the hook ends"

# ---------------------------------------------------------------------------
banner "acceptance/R39: the commit hook refuses an agent's commit staging a held file"
# ---------------------------------------------------------------------------
git -C "$WT" checkout -q "$APPROVAL" -- "$TF"
commit_in_wt "test: T-90's approved acceptance tests"
expect_status 0 "the build's first commit, the held file at its approved content, goes through"

printf 'test "totals by area"\ntrue\n' >"$WT/$TF"
git -C "$WT" add "$TF"
commit_in_wt "test: loosen the approved test"
refused "a commit staging a change to $TF" 1
t_exec git -C "$WT" diff --cached --name-only
expect_out_is "$TF" "the change is still staged, nothing committed"

git -C "$WT" reset -q -- "$TF"
git -C "$WT" checkout -q -- "$TF"
t_write "$WT" src/report.sh 'echo totals
'
git -C "$WT" add src/report.sh
commit_in_wt "feat: totals by area"
expect_status 0 "a commit staging no held file goes through"

git -C "$WT" rm -q "$TF"
commit_in_wt "test: drop the approved test"
refused "a commit deleting $TF" 1
git -C "$WT" reset -q -- "$TF" && git -C "$WT" checkout -q -- "$TF"

printf 'test "totals by area"\ntrue\n' >"$WT/$TF"
git -C "$WT" add "$TF"
as_human() { (t_as_human && "$@"); }
t_exec as_human git -C "$WT" commit -q -m "test: the operator re-approves"
expect_status 0 "a human's commit (no agent-harness marker) is the operator's, let through"

# ---------------------------------------------------------------------------
banner "Both fail open when the guard at the default branch is missing"
# ---------------------------------------------------------------------------
git -C "$FIX" rm -q scripts/acceptance-guard.sh
as_agent git -C "$FIX" commit -q --no-verify -m "chore: no guard" >/dev/null
hook_on "$(payload Edit "$WT/$TF")"
expect_status 0 "with no guard at main, the pre-tool hook lets the edit through"
printf 'test "totals by area"\ntrue\ntrue\n' >"$WT/$TF"
git -C "$WT" add "$TF"
commit_in_wt "test: with no guard to ask"
expect_status 0 "with no guard at main, the commit hook lets the commit through"

# ---------------------------------------------------------------------------
banner "The README and the hooks' comments say what the tripwires are"
# ---------------------------------------------------------------------------
README="$KIT/adapters/claude-code/README.md"
assert_file_has "$README" "## Refusing an edit of an approved acceptance test" "the adapter's README has the tripwires' section"
for f in "$README" "$KIT/adapters/claude-code/hooks/root-guard.sh" "$KIT/.githooks/pre-commit"; do
	assert_file_has "$f" "never the judge" "${f#"$KIT"/} says the tripwire is never the judge"
	assert_file_has "$f" "fails open" "${f#"$KIT"/} says the tripwire fails open"
done

t_done
