#!/bin/sh
# tests/root-guard.test.sh — the root checkout refuses an agent's edit and an
# agent's commit (hard rule 1, ticket #392).
#
# WHY TWO LAYERS. Git has no hook for an edit, so the rule is held twice:
#
#   1. THE AGENT HARNESS LAYER refuses the edit. A pre-tool hook in the Claude
#      Code adapter reads the tool payload, resolves the target path against
#      the repository's MAIN working tree (found through git's common
#      directory, so a session started inside a worktree still knows which
#      tree is the root), and blocks a path inside that tree but not under
#      `worktree/` — the runtime directories `.trace/` and `.retro/` excepted.
#      For Bash it is a tripwire: a redirect into, or `sed -i`, `tee`, `cp`,
#      `mv`, `git checkout` / `git restore` on, a TRACKED file at the root.
#   2. THE GIT LAYER refuses the commit. `.githooks/pre-commit` refuses a
#      commit from the main working copy or on `main`, with a loud bypass in
#      the pre-push hook's shape.
#
# On 2026-10-01 a session edited two suites in the root checkout and left
# them uncommitted; the root's `main` then could not fast-forward for a day.
# Nothing enforced the rule. Every case below was driven RED first (hard rule
# 9), against no guard at all.
#
# Usage: sh tests/root-guard.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
t_init

KIT="$ROOT"
GUARD_SRC="$KIT/adapters/claude-code/hooks/root-guard.sh"
PRECOMMIT_SRC="$KIT/.githooks/pre-commit"

# --- fixture ------------------------------------------------------------------
# A repository with a tracked README.md and AGENTS.md at its root, the guard
# copied in where the adapter keeps it (the hook finds its repository from its
# own location, never from the caller's cwd), and one linked worktree under
# `worktree/x` on a feature branch.
t_repo
FIX=$(cd "$REPO" && pwd -P)
printf 'readme\n' >"$FIX/README.md"
printf 'manual\n' >"$FIX/AGENTS.md"
printf 'worktree/\n.trace/\n.retro/\n' >"$FIX/.gitignore"
mkdir -p "$FIX/tests" && printf 'echo hi\n' >"$FIX/tests/x.sh"
mkdir -p "$FIX/.githooks"
[ -f "$PRECOMMIT_SRC" ] && cp "$PRECOMMIT_SRC" "$FIX/.githooks/pre-commit"
t_commit "$FIX" "chore: tracked files" >/dev/null
git -C "$FIX" worktree add -q "$FIX/worktree/x" -b feat/x 2>/dev/null
WT="$FIX/worktree/x"

HOOKDIR="$FIX/adapters/claude-code/hooks"
mkdir -p "$HOOKDIR"
[ -f "$GUARD_SRC" ] && cp "$GUARD_SRC" "$HOOKDIR/root-guard.sh"
GUARD="$HOOKDIR/root-guard.sh"

OUTSIDE=$(mktemp -d "$SCRATCH/outside.XXXXXX") || exit 2

# json_str <text> — <text> as a JSON string body: backslash and quote escaped.
json_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# payload <tool> <key> <value> [<cwd>] — one compact PreToolUse payload, the
# shape a live hook receives: the whole object on one line.
payload() {
	printf '{"session_id":"s-1","transcript_path":"/nowhere.jsonl","cwd":"%s","permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"%s":"%s"},"tool_use_id":"toolu_1"}' \
		"$(json_str "${4:-$FIX}")" "$1" "$2" "$(json_str "$3")"
}

# guard_on <payload> — run the guard with the payload on stdin; S_OUT, S_ERR,
# S_STATUS as t_run_split sets them.
guard_on() {
	printf '%s' "$1" >"$SCRATCH/payload.json"
	t_run_split sh "$GUARD" <"$SCRATCH/payload.json"
}

# refused <label> — status 2 (the agent harness's blocking status), the rule
# named on stderr, and nothing on stdout.
refused() {
	s_assert_status 2 "$1 is refused with the blocking status"
	case $S_ERR in
	*'hard rule 1'*) pass "and stderr names hard rule 1" ;;
	*) fail "$1: stderr does not name hard rule 1: $S_ERR" ;;
	esac
	s_assert_out_is "" "and stdout stays empty"
}

# allowed <label> — status 0 and silence on stdout.
allowed() {
	s_assert_status 0 "$1 goes through"
	s_assert_out_is "" "and stdout stays empty"
}

# ---------------------------------------------------------------------------
banner "1. The files exist"
# ---------------------------------------------------------------------------
[ -f "$GUARD_SRC" ] && pass "the adapter carries the root guard hook" ||
	fail "adapters/claude-code/hooks/root-guard.sh does not exist"
[ -f "$PRECOMMIT_SRC" ] && pass ".githooks/pre-commit exists" ||
	fail ".githooks/pre-commit does not exist"
[ -x "$PRECOMMIT_SRC" ] && pass "and it is executable, as git requires of a hook" ||
	fail ".githooks/pre-commit is not executable — git would skip it with a hint, silently in CI"

# ---------------------------------------------------------------------------
banner "2. The agent harness layer: a write at the root is refused"
# ---------------------------------------------------------------------------
guard_on "$(payload Write file_path "$FIX/README.md")"
refused "a Write to README.md at the root"
case $S_ERR in
*worktree*) pass "and the reason points at a worktree" ;;
*) fail "the reason does not mention a worktree: $S_ERR" ;;
esac

# The demo line: an Edit on AGENTS.md from the root is refused, and the
# message says to open a worktree.
guard_on "$(payload Edit file_path "$FIX/AGENTS.md")"
refused "an Edit on AGENTS.md at the root"
case $S_ERR in
*'git worktree add'*) pass "and the message says how to open a worktree" ;;
*) fail "the message does not say how to open a worktree: $S_ERR" ;;
esac

guard_on "$(payload MultiEdit file_path "$FIX/README.md")"
refused "a MultiEdit at the root"
guard_on "$(payload NotebookEdit notebook_path "$FIX/nb.ipynb")"
refused "a NotebookEdit at the root (the notebook editor names its path notebook_path)"
guard_on "$(payload Write file_path "$FIX/new-file.md")"
refused "a Write that creates a NEW file at the root"
guard_on "$(payload Write file_path "README.md")"
refused "a relative path, resolved against the payload's cwd"
guard_on "$(payload Write file_path "$WT/../../README.md")"
refused "a path that climbs out of a worktree with .."

# ---------------------------------------------------------------------------
banner "3. The agent harness layer: what passes"
# ---------------------------------------------------------------------------
guard_on "$(payload Write file_path "$WT/README.md")"
allowed "the same Write under worktree/x"
guard_on "$(payload Write file_path "$WT/brand/new/dir/file.md")"
allowed "a Write that creates new directories inside a worktree"
guard_on "$(payload Write file_path "$OUTSIDE/README.md")"
allowed "a Write outside the repository"
guard_on "$(payload Write file_path "$FIX/.trace/events/2026-10-01.jsonl")"
allowed "a Write under .trace/"
guard_on "$(payload Write file_path "$FIX/.retro/2026/10/retro.md")"
allowed "a Write under .retro/"
guard_on "$(payload Write file_path "README.md" "$WT")"
allowed "a relative path from a cwd inside the worktree"
guard_on "$(payload Read file_path "$FIX/README.md")"
allowed "a tool that does not edit (Read)"

# A session started INSIDE a worktree runs the worktree's copy of the hook:
# the root it guards is still the main working tree, found through git's
# common directory — and the worktree's own files are not the root's.
mkdir -p "$WT/adapters/claude-code/hooks"
[ -f "$GUARD_SRC" ] && cp "$GUARD_SRC" "$WT/adapters/claude-code/hooks/root-guard.sh"
printf '%s' "$(payload Write file_path "$WT/README.md" "$WT")" >"$SCRATCH/payload.json"
t_run_split sh "$WT/adapters/claude-code/hooks/root-guard.sh" <"$SCRATCH/payload.json"
allowed "the worktree's copy of the hook, writing in that worktree"
printf '%s' "$(payload Write file_path "$FIX/README.md" "$WT")" >"$SCRATCH/payload.json"
t_run_split sh "$WT/adapters/claude-code/hooks/root-guard.sh" <"$SCRATCH/payload.json"
refused "the worktree's copy of the hook, writing at the main root"

# ---------------------------------------------------------------------------
banner "4. The agent harness layer: Bash is a tripwire"
# ---------------------------------------------------------------------------
guard_on "$(payload Bash command 'echo hi > README.md')"
refused "a Bash redirect into README.md"
guard_on "$(payload Bash command 'echo hi >>README.md')"
refused "an appending redirect with no space"
guard_on "$(payload Bash command "printf \"%s\\n\" \"a\" > \"$FIX/README.md\"")"
refused "a redirect after escaped quotes, into a quoted absolute path"
guard_on "$(payload Bash command 'sed -i s/readme/x/ README.md')"
refused "sed -i on a tracked file"
guard_on "$(payload Bash command 'echo hi | tee README.md')"
refused "tee into a tracked file"
guard_on "$(payload Bash command 'cp /etc/hostname AGENTS.md')"
refused "cp onto a tracked file"
guard_on "$(payload Bash command 'mv README.md elsewhere.md')"
refused "mv of a tracked file"
guard_on "$(payload Bash command 'git checkout -- README.md')"
refused "git checkout of a tracked file"
guard_on "$(payload Bash command 'git restore README.md')"
refused "git restore of a tracked file"
guard_on "$(payload Bash command 'cd /tmp && echo hi > README.md' "$FIX")"
allowed "a redirect after cd elsewhere"
guard_on "$(payload Bash command "cd worktree/x && echo hi > README.md")"
allowed "a redirect after cd into a worktree"

guard_on "$(payload Bash command 'sh tests/x.sh')"
allowed "sh tests/x.sh"
guard_on "$(payload Bash command 'cat README.md > /dev/null 2>&1')"
allowed "a read whose redirects go to /dev/null"
guard_on "$(payload Bash command 'echo hi > untracked-scratch.txt')"
allowed "a redirect into an UNTRACKED file at the root"
guard_on "$(payload Bash command 'cp README.md /tmp/copy.md')"
allowed "cp FROM a tracked file to somewhere else"
guard_on "$(payload Bash command 'echo hi > README.md' "$WT")"
allowed "a redirect from a cwd inside the worktree"
guard_on "$(payload Bash command 'git checkout -b feat/y')"
allowed "git checkout of a branch name that is no tracked file"

# ---------------------------------------------------------------------------
banner "5. The agent harness layer fails open on a payload it cannot read"
# ---------------------------------------------------------------------------
# A guard that blocks every tool call on a parse failure bricks the session;
# this one is a tripwire, and the git layer below is the half that fails
# closed.
guard_on ""
allowed "an empty payload"
guard_on "not json at all"
allowed "a payload that is not JSON"

# ---------------------------------------------------------------------------
banner "6. The git layer: a commit from the main working copy is refused"
# ---------------------------------------------------------------------------
git -C "$FIX" config core.hooksPath .githooks
printf 'x\n' >>"$FIX/README.md"
git -C "$FIX" add README.md
t_run_split git -C "$FIX" commit -q -m "docs: from the root"
[ "$S_STATUS" != 0 ] && pass "a commit from the main working copy exits non-zero" ||
	fail "a commit from the main working copy went through"
case $S_ERR in
*'hard rule 1'*) pass "and names the rule" ;;
*) fail "the refusal does not name hard rule 1: $S_ERR" ;;
esac

git -C "$FIX" checkout -q -b feat/on-root
printf 'x2\n' >>"$FIX/README.md"
git -C "$FIX" add README.md
t_run_split git -C "$FIX" commit -q -m "docs: from the root, on a feature branch"
[ "$S_STATUS" != 0 ] && pass "the main working copy is refused on a feature branch too" ||
	fail "a feature branch in the main working copy went through"

printf 'x3\n' >>"$FIX/README.md"
git -C "$FIX" add README.md
t_run_split env COMMIT_WITHOUT_WORKTREE=1 git -C "$FIX" commit -q -m "docs: the operator's own, bypassed"
s_assert_status 0 "COMMIT_WITHOUT_WORKTREE=1 lets it through"
case $S_ERR in
*COMMIT_WITHOUT_WORKTREE=1*BYPASSED*) pass "and says so, loudly, on stderr" ;;
*) fail "the bypass was silent: $S_ERR" ;;
esac

# ---------------------------------------------------------------------------
banner "7. The git layer: a linked worktree on a feature branch commits"
# ---------------------------------------------------------------------------
printf 'y\n' >>"$WT/README.md"
git -C "$WT" add -A
t_run_split git -C "$WT" commit -q -m "docs: from a worktree"
s_assert_status 0 "a commit from worktree/x on feat/x goes through"

# A linked worktree on main is still main.
git -C "$FIX" checkout -q feat/on-root
git -C "$FIX" worktree add -q "$FIX/worktree/m" main 2>/dev/null
printf 'z\n' >>"$FIX/worktree/m/README.md"
git -C "$FIX/worktree/m" add README.md
t_run_split git -C "$FIX/worktree/m" commit -q -m "docs: on main, in a worktree"
[ "$S_STATUS" != 0 ] && pass "a linked worktree on main is refused" ||
	fail "a commit on main from a linked worktree went through"

# The first commit of a fresh repository has no worktree to come from: nothing
# exists yet to branch one off, so the root commit passes.
FRESH=$(mktemp -d "$SCRATCH/fresh.XXXXXX") || exit 2
git -C "$FRESH" init -q -b main
git -C "$FRESH" config user.name "Guard Fixture"
git -C "$FRESH" config user.email "fixture@example.invalid"
git -C "$FRESH" config commit.gpgsign false
mkdir -p "$FRESH/.githooks"
[ -f "$PRECOMMIT_SRC" ] && cp "$PRECOMMIT_SRC" "$FRESH/.githooks/pre-commit"
git -C "$FRESH" config core.hooksPath .githooks
git -C "$FRESH" add -A
t_run_split git -C "$FRESH" commit -q -m "chore: bootstrap"
s_assert_status 0 "a repository's root commit goes through — there is nothing to cut a worktree from yet"

# ---------------------------------------------------------------------------
banner "8. Wiring, docs and what ships"
# ---------------------------------------------------------------------------
SETTINGS="$KIT/.claude/settings.json"
grep -q '"PreToolUse"' "$SETTINGS" && pass "the kit's settings wire PreToolUse" ||
	fail ".claude/settings.json does not wire PreToolUse"
grep -q 'hooks/root-guard.sh' "$SETTINGS" && pass "to the root guard" ||
	fail ".claude/settings.json does not name the root guard"
for t in Edit Write MultiEdit NotebookEdit Bash; do
	grep '"matcher"' "$SETTINGS" | grep -q "$t" && pass "the matcher covers $t" ||
		fail "the PreToolUse matcher does not cover $t"
done
assert_file_has "$KIT/README.md" "tests/root-guard.test.sh" "a contributor asked to run the suites would miss it"
assert_file_has "$KIT/.github/workflows/kit-ci.yml" "sh tests/root-guard.test.sh" "CI runs every suite"
assert_file_has "$KIT/bootstrap.sh" "tests/root-guard.test.sh" "the suite is kit-only"
assert_file_has "$KIT/adapters/claude-code/README.md" "hooks/root-guard.sh" "a consumer wires it from there"
assert_file_has "$KIT/adapters/claude-code/README.md" "## Refusing an edit at the root checkout" "the section a consumer wires it from"
assert_file_has "$KIT/adapters/claude-code/README.md" "What Bash coverage it does not give" "a tripwire says where it stops"
grep -q 'root-guard' "$KIT/AGENTS.md" && pass "the manual's quick reference names the guard" ||
	fail "AGENTS.md has no row for the root guard"
lines=$(wc -l <"$KIT/AGENTS.md")
[ "$lines" -le 350 ] && pass "AGENTS.md stays within its 350-line budget ($lines)" ||
	fail "AGENTS.md is $lines lines, over its 350-line budget (ADR-0004)"

# Neither hook names a model, a vendor or a kit-only file: both ship.
for f in "$GUARD_SRC" "$PRECOMMIT_SRC"; do
	[ -f "$f" ] || continue
	if grep -niE 'anthropic|openai|claude|codex|gemini|gpt-|opus|sonnet|haiku|fable' "$f" >/dev/null; then
		fail "${f#"$KIT"/} names a model or a vendor"
		grep -niE 'anthropic|openai|claude|codex|gemini|gpt-|opus|sonnet|haiku|fable' "$f" | sed 's/^/        | /'
	else
		pass "${f#"$KIT"/} names no model and no vendor"
	fi
	if grep -nE '\.kit\.|kit\.config' "$f" >/dev/null; then
		fail "${f#"$KIT"/} names a kit-only file"
	else
		pass "${f#"$KIT"/} names no kit-only file"
	fi
done

t_done "root-guard"
