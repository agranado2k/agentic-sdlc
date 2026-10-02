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
#      `mv`, `git checkout` / `git restore` on, a TRACKED file at the root, and
#      the three ways around the git layer (`--no-verify`, `-c
#      core.hooksPath`, `git config core.hooksPath`) where git acts there.
#   2. THE GIT LAYER refuses an agent's commit. `.githooks/pre-commit` refuses
#      a commit from the main working copy or on the default branch when an
#      agent-harness marker is in the environment, and lets a human with none
#      through; a loud bypass in the pre-push hook's shape, never printed to
#      the agent it refuses. Git lets any committer skip a hook, so this layer
#      is a guard a cooperative agent meets; layer 1 is the one that refuses.
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
# Newlines and tabs are written as their escapes, so a multi-line command
# (a heredoc, a continuation line) arrives on one line, as it does live.
json_str() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' |
		awk '{ gsub(/\t/, "\\t"); printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }'
}

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

# The tripwire's own edge cases (the review's LOW findings): `cd` options are
# not its directory, `git -C` moves where git acts, and a restore that only
# touches the index writes no file.
guard_on "$(payload Bash command 'cd -P . && echo x > README.md')"
refused "a redirect after cd -P ."
guard_on "$(payload Bash command "git -C $FIX checkout -- README.md" "$WT")"
refused "git -C <the root> checkout from a cwd inside the worktree"
guard_on "$(payload Bash command "git -C $OUTSIDE checkout -- README.md")"
allowed "git -C <elsewhere> checkout, which writes elsewhere"
guard_on "$(payload Bash command 'git restore --staged README.md')"
allowed "git restore --staged, which touches only the index"
guard_on "$(payload Bash command 'git restore -S README.md')"
allowed "git restore -S, the same"
guard_on "$(payload Bash command 'git restore --staged --worktree README.md')"
refused "git restore --staged --worktree, which writes the file"

# ---------------------------------------------------------------------------
banner "4b. The agent harness layer: Bash may not walk past the commit guard"
# ---------------------------------------------------------------------------
# The commit guard is a git hook, and git has three ways around its own hooks.
# From the main working tree the agent harness layer refuses all three, since
# it is the layer an agent cannot opt out of (review finding M-1).
guard_on "$(payload Bash command 'git commit --no-verify -m x')"
refused "git commit --no-verify from the root"
guard_on "$(payload Bash command 'git commit -qn -m x')"
refused "git commit -n (the short form) from the root"
guard_on "$(payload Bash command 'git -c core.hooksPath=/dev/null commit -m x')"
refused "git -c core.hooksPath=… from the root"
guard_on "$(payload Bash command 'git -c core.hookspath=/dev/null commit -m x')"
refused "git -c with the key in another case (git config keys are case-blind)"
guard_on "$(payload Bash command 'git config core.hooksPath /dev/null')"
refused "git config core.hooksPath <value> from the root"
guard_on "$(payload Bash command 'git config --unset core.hooksPath')"
refused "git config --unset core.hooksPath from the root"
guard_on "$(payload Bash command 'git config set core.hooksPath x')"
refused "git config set core.hooksPath from the root"
guard_on "$(payload Bash command 'git config core.hooksPath')"
allowed "git config core.hooksPath with no value, which only reads it"
guard_on "$(payload Bash command 'git commit --no-verify -m x' "$WT")"
allowed "git commit --no-verify from a cwd inside the worktree"
guard_on "$(payload Bash command 'cd worktree/x && git commit --no-verify -m x')"
allowed "git commit --no-verify after cd into a worktree"
guard_on "$(payload Bash command "git -C $WT commit --no-verify -m x")"
allowed "git -C <a worktree> commit --no-verify from the root"

# ---------------------------------------------------------------------------
banner "4c. The Bash plan: heredocs, continuation lines and command prefixes"
# ---------------------------------------------------------------------------
# The plan reads a command roughly as a shell would. Each of these is a branch
# of it that review finding H-1 found untested.
guard_on "$(payload Bash command "cat <<EOF >/tmp/rg-note.txt
echo hi > README.md
EOF")"
allowed "a heredoc whose BODY names a redirect into README.md (the body is data)"
guard_on "$(payload Bash command "cat <<'EOF' >/tmp/rg-note.txt
echo hi > README.md
EOF
echo done > README.md")"
refused "a redirect into README.md on the line after a quoted heredoc ends"
guard_on "$(payload Bash command "cat <<-EOF >/tmp/rg-note.txt
	sed -i s/a/b/ README.md
	EOF
echo done > README.md")"
refused "a redirect after a <<- heredoc whose tab-indented terminator ends it"
guard_on "$(payload Bash command "cat <<-EOF >/tmp/rg-note.txt
	sed -i s/a/b/ README.md
	EOF")"
allowed "the same <<- heredoc alone, its body data"
guard_on "$(payload Bash command 'echo hi \
  > README.md')"
refused "a redirect split across a backslash-newline"
guard_on "$(payload Bash command 'sed -i s/readme/x/ \
  README.md')"
refused "sed -i whose operand is on a continuation line"
guard_on "$(payload Bash command 'env FOO=1 sed -i s/readme/x/ README.md')"
refused "sed -i behind env VAR=…"
guard_on "$(payload Bash command 'sudo tee README.md </dev/null')"
refused "tee behind sudo"
guard_on "$(payload Bash command 'FOO=bar git checkout -- README.md')"
refused "git checkout behind a VAR= assignment"
guard_on "$(payload Bash command 'env -u X GIT_TRACE=1 git commit --no-verify -m x')"
refused "git commit --no-verify behind env with an option and an assignment"
guard_on "$(payload Bash command 'FOO=bar cat README.md')"
allowed "a read behind a VAR= assignment"

# ---------------------------------------------------------------------------
banner "5. The agent harness layer fails open on a payload it cannot read"
# ---------------------------------------------------------------------------
# A guard that blocks every tool call on a parse failure bricks the session;
# this one is a tripwire. The git layer below is no backstop for it either: it
# is a guard a cooperative agent meets, and section 4b is where this layer
# refuses the ways around it.
guard_on ""
allowed "an empty payload"
guard_on "not json at all"
allowed "a payload that is not JSON"

# ---------------------------------------------------------------------------
banner "6. The git layer refuses an AGENT's commit from the main working copy"
# ---------------------------------------------------------------------------
# The guard refuses agents only: a commit is refused when an agent-harness
# marker is in the environment. A human on main, with none, commits as before,
# so the UPDATING recipe a consumer follows by hand keeps working.
# T_AGENT_MARKERS (tests/lib.sh) is the marker list; section 8 holds it equal
# to the hook's own.

# as_human <command…> — run it with every agent-harness marker unset.
as_human() { (t_as_human && "$@"); }
# as_agent <marker> <command…> — the same, with only <marker> set.
as_agent() { (_m=$1 && shift && t_as_human && eval "$_m=1" && export "$_m" && "$@"); }

# refused_commit <label> — non-zero, the rule named, its bypass never printed.
refused_commit() {
	[ "$S_STATUS" != 0 ] && pass "$1 is refused" || fail "$1 went through"
	case $S_ERR in
	*'hard rule 1'*) pass "and names hard rule 1" ;;
	*) fail "$1: the refusal does not name hard rule 1: $S_ERR" ;;
	esac
	case $S_ERR in
	*COMMIT_WITHOUT_WORKTREE*) fail "$1: the refusal prints its own bypass to the agent it refuses (M-2)" ;;
	*) pass "and does not print its own bypass (M-2)" ;;
	esac
}

git -C "$FIX" config core.hooksPath .githooks
n=0
# stage_root — one fresh staged change at the root.
stage_root() {
	n=$((n + 1))
	printf 'x%s\n' "$n" >>"$FIX/README.md"
	git -C "$FIX" add README.md
}

stage_root
t_run_split as_agent CLAUDECODE git -C "$FIX" commit -q -m "docs: from the root"
refused_commit "an agent's commit (CLAUDECODE=1) on main from the main working copy"
case $S_ERR in
*'Keep work out of the root checkout'*) pass "and points at the manual's row" ;;
*) fail "the refusal does not name the manual's row: $S_ERR" ;;
esac

t_run_split as_human git -C "$FIX" commit -q -m "docs: a human, from the root"
s_assert_status 0 "the same commit with no agent marker goes through — a human on main is let through"
case $S_ERR in
*refused*) fail "a human's commit printed a refusal: $S_ERR" ;;
*) pass "and says nothing about a refusal" ;;
esac

for m in $T_AGENT_MARKERS; do
	stage_root
	t_run_split as_agent "$m" git -C "$FIX" commit -q -m "docs: from the root, $m"
	[ "$S_STATUS" != 0 ] && pass "$m alone marks an agent, and the commit is refused" ||
		fail "$m=1 alone did not refuse a root commit"
done

stage_root
t_run_split as_human env CLAUDECODE= git -C "$FIX" commit -q -m "docs: an empty marker"
s_assert_status 0 "a marker set to the empty string is no marker"

git -C "$FIX" checkout -q -b feat/on-root
stage_root
t_run_split as_agent CLAUDECODE git -C "$FIX" commit -q -m "docs: from the root, on a feature branch"
refused_commit "an agent's commit from the main working copy on a feature branch"

stage_root
t_run_split as_agent CLAUDECODE env COMMIT_WITHOUT_WORKTREE=1 git -C "$FIX" commit -q -m "docs: the operator's own, bypassed"
s_assert_status 0 "COMMIT_WITHOUT_WORKTREE=1 lets it through"
case $S_ERR in
*COMMIT_WITHOUT_WORKTREE=1*BYPASSED*) pass "and says so, loudly, on stderr" ;;
*) fail "the bypass was silent: $S_ERR" ;;
esac
assert_file_has "$PRECOMMIT_SRC" "COMMIT_WITHOUT_WORKTREE=1" "the bypass stays documented in the hook's source"

# ---------------------------------------------------------------------------
banner "7. The git layer: a linked worktree on a feature branch commits"
# ---------------------------------------------------------------------------
printf 'y\n' >>"$WT/README.md"
git -C "$WT" add -A
t_run_split as_agent CLAUDECODE git -C "$WT" commit -q -m "docs: from a worktree"
s_assert_status 0 "an agent's commit from worktree/x on feat/x goes through"

# A linked worktree on the default branch is still the default branch.
git -C "$FIX" worktree add -q "$FIX/worktree/m" main 2>/dev/null
printf 'z\n' >>"$FIX/worktree/m/README.md"
git -C "$FIX/worktree/m" add README.md
t_run_split as_agent CLAUDECODE git -C "$FIX/worktree/m" commit -q -m "docs: on main, in a worktree"
refused_commit "an agent's commit on main from a linked worktree"
t_run_split as_human git -C "$FIX/worktree/m" commit -q -m "docs: on main, in a worktree, by a human"
s_assert_status 0 "a human's commit on main from a linked worktree goes through"

# The default branch is the repository's, not a hard-coded name: where
# origin/HEAD names one, that is the branch an agent may not commit on.
git -C "$FIX" update-ref refs/remotes/origin/trunk HEAD
git -C "$FIX" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
git -C "$FIX" worktree add -q "$FIX/worktree/t" -b trunk 2>/dev/null
printf 't\n' >>"$FIX/worktree/t/README.md"
git -C "$FIX/worktree/t" add README.md
t_run_split as_agent CLAUDECODE git -C "$FIX/worktree/t" commit -q -m "docs: on trunk, the default"
refused_commit "an agent's commit on the default branch origin/HEAD names (trunk)"
printf 'z2\n' >>"$FIX/worktree/m/README.md"
git -C "$FIX/worktree/m" add README.md
t_run_split as_agent CLAUDECODE git -C "$FIX/worktree/m" commit -q -m "docs: on main, which is not the default here"
s_assert_status 0 "with trunk the default, a worktree on a branch named main is a branch like any other"
git -C "$FIX" symbolic-ref --delete refs/remotes/origin/HEAD

# The first commit of a fresh repository has no worktree to come from: nothing
# exists yet to branch one off, so the root commit passes, agent or not.
FRESH=$(mktemp -d "$SCRATCH/fresh.XXXXXX") || exit 2
git -C "$FRESH" init -q -b main
git -C "$FRESH" config user.name "Guard Fixture"
git -C "$FRESH" config user.email "fixture@example.invalid"
git -C "$FRESH" config commit.gpgsign false
mkdir -p "$FRESH/.githooks"
[ -f "$PRECOMMIT_SRC" ] && cp "$PRECOMMIT_SRC" "$FRESH/.githooks/pre-commit"
git -C "$FRESH" config core.hooksPath .githooks
git -C "$FRESH" add -A
t_run_split as_agent CLAUDECODE git -C "$FRESH" commit -q -m "chore: bootstrap"
s_assert_status 0 "a repository's root commit goes through — there is nothing to cut a worktree from yet"

# ---------------------------------------------------------------------------
banner "8. Wiring, docs and what ships"
# ---------------------------------------------------------------------------
SETTINGS="$KIT/.claude/settings.json"
grep -q '"PreToolUse"' "$SETTINGS" && pass "the kit's settings wire PreToolUse" ||
	fail ".claude/settings.json does not wire PreToolUse"
grep -q 'hooks/root-guard.sh' "$SETTINGS" && pass "to the root guard" ||
	fail ".claude/settings.json does not name the root guard"
# Each tool is matched as a whole alternative of the matcher, so `Edit` is
# never satisfied by `MultiEdit` or `NotebookEdit` (review finding M-4).
matcher_tools=$(grep '"matcher"' "$SETTINGS" | grep 'Bash' | sed 's/.*"matcher"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | tr '|' '\n')
for t in Edit Write MultiEdit NotebookEdit Bash; do
	printf '%s\n' "$matcher_tools" | grep -qx "$t" && pass "the matcher covers $t" ||
		fail "the PreToolUse matcher does not cover $t as a whole alternative"
done
# The marker list the suites unset is the hook's own, word for word.
hook_markers=$(sed -n "s/^agent_markers='\(.*\)'$/\1/p" "$PRECOMMIT_SRC")
[ -n "$hook_markers" ] && [ "$hook_markers" = "$T_AGENT_MARKERS" ] &&
	pass "tests/lib.sh's T_AGENT_MARKERS is the hook's agent_markers list" ||
	fail "the hook's markers ($hook_markers) differ from tests/lib.sh's ($T_AGENT_MARKERS)"
for m in $T_AGENT_MARKERS; do
	assert_file_has "$KIT/adapters/claude-code/README.md" "\`$m\`" "the adapter README names every marker the guard reads"
done
assert_file_has "$KIT/README.md" "| \`.githooks/pre-commit\` |" "the ship table names every hook the kit ships"
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

# Neither hook names a model, a vendor or a kit-only file: both ship. The one
# exception is the commit guard's agent markers, which are environment variable
# names the agent harnesses chose; they are read out before the check, and
# nothing else in the file may name a vendor.
for f in "$GUARD_SRC" "$PRECOMMIT_SRC"; do
	[ -f "$f" ] || continue
	unmarked=$(cat "$f")
	for m in $T_AGENT_MARKERS; do unmarked=$(printf '%s\n' "$unmarked" | sed "s/$m//g"); done
	if printf '%s\n' "$unmarked" | grep -niE 'anthropic|openai|claude|codex|gemini|gpt-|opus|sonnet|haiku|fable' >/dev/null; then
		fail "${f#"$KIT"/} names a model or a vendor"
		printf '%s\n' "$unmarked" | grep -niE 'anthropic|openai|claude|codex|gemini|gpt-|opus|sonnet|haiku|fable' | sed 's/^/        | /'
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
