#!/bin/sh
# Task entry through its public POSIX command.
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd)
COMMAND="$KIT/scripts/task.sh"
. "$KIT/tests/lib.sh"
t_init

task_repo() {
	t_repo
	mkdir -p "$REPO/.agents/skills/example" "$REPO/scripts"
	printf '%s\n' '# Example skill' >"$REPO/.agents/skills/example/SKILL.md"
	cp "$KIT/scripts/catalogue.sh" "$REPO/scripts/catalogue.sh"
	printf '%s\n' \
		'catalogue|1' \
		'active|.agents/skills|identical' \
		>"$REPO/scripts/catalogue.config"
	git -C "$REPO" add -A
	git -C "$REPO" commit -q -m 'chore: add task fixture'
}

task_repo

cat >"$SCRATCH/missing-scope.task" <<'EOF'
task|1
kind|implementation
size|small
acceptance|The command demonstrates the requested behavior.
phases|implementation technical-verification review delivery
endpoint|reviewed-pr
authorization|The operator authorized this task.
provenance|ticket:#fixture
EOF

expect_exit 2 'a contract without scope is refused before task state exists' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/missing-scope.task"
expect_said 'missing scope'
STATE=$(git -C "$REPO" rev-parse --path-format=absolute --git-dir)/agentic-sdlc/task
[ ! -e "$STATE" ] && pass 'missing scope created no task state' || fail 'missing scope created task state'

cat >"$SCRATCH/small.task" <<'EOF'
task|1
kind|implementation
size|small
scope|Change only the example task boundary.
acceptance|Missing scope is refused before state exists.
acceptance|A valid small change reports its task-local status.
phases|implementation technical-verification review delivery
endpoint|reviewed-pr
authorization|The operator authorized implementation, push, and review; merge stays human-only.
provenance|ticket:#fixture
EOF

expect_exit 0 'a small implementation contract starts through the public boundary' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/small.task"
expect_said 'started|1'
expect_exit 0 'status returns the admitted task-local contract' -- sh "$COMMAND" status "$REPO"
expect_said 'kind|implementation'
expect_said 'scope|Change only the example task boundary.'
expect_said 'acceptance|Missing scope is refused before state exists.'
expect_said 'endpoint|reviewed-pr'
expect_said 'authorization|The operator authorized implementation, push, and review; merge stays human-only.'
expect_said 'provenance|ticket:#fixture'
PHYSICAL_REPO=$(cd "$REPO" && pwd -P)
expect_said "worktree|$PHYSICAL_REPO"
expect_said 'branch|main'
expect_said 'catalogue-receipt|'
printf '%s\n' '# Changed skill bytes' >"$REPO/.agents/skills/example/SKILL.md"
expect_exit 2 'status refuses catalogue bytes that changed after task start' -- sh "$COMMAND" status "$REPO"
expect_said 'catalogue changed; start a new task contract'

task_repo
printf '%s\n' 'committed base' >"$REPO/product.txt"
printf '%s\n' 'worktree base' >"$REPO/worktree.txt"
git -C "$REPO" add product.txt worktree.txt
git -C "$REPO" commit -q -m 'chore: add baseline files'
printf '%s\n' 'staged before scope was admitted' >"$REPO/product.txt"
git -C "$REPO" add product.txt
printf '%s\n' 'unstaged before scope was admitted' >"$REPO/worktree.txt"
printf '%s\n' 'untracked before scope was admitted' >"$REPO/untracked.txt"
cat >"$SCRATCH/late.task" <<'EOF'
task|1
kind|implementation
size|small
scope|Add one bounded product change.
acceptance|The product change is technically verified.
phases|implementation technical-verification review delivery
endpoint|reviewed-pr
authorization|The operator authorized this bounded change.
provenance|ordinary-request
EOF
expect_exit 2 'task start refuses a production edit made before scope admission' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/late.task"
expect_said 'dirty baseline requires baseline|preserve'
STATE=$(git -C "$REPO" rev-parse --path-format=absolute --git-dir)/agentic-sdlc/task
[ ! -e "$STATE" ] && pass 'pre-scope edit created no task state' || fail 'pre-scope edit created task state'

sed '/^provenance|/i\
baseline|preserve' "$SCRATCH/late.task" >"$SCRATCH/preserve.task"
expect_exit 0 'an explicitly acknowledged dirty baseline is preserved' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/preserve.task"
expect_exit 0 'dirty baseline status carries separate content identities' -- sh "$COMMAND" status "$REPO"
INDEX_ID=$(printf '%s\n' "$T_OUT" | sed -n 's/^baseline-index|//p')
WORKTREE_ID=$(printf '%s\n' "$T_OUT" | sed -n 's/^baseline-worktree|//p')
UNTRACKED_ID=$(printf '%s\n' "$T_OUT" | sed -n 's/^baseline-untracked|//p')
expect_said 'baseline|preserve'
expect_said 'baseline-head|'
expect_said 'baseline-index|'
expect_said 'baseline-worktree|'
expect_said 'baseline-untracked|'
[ "$INDEX_ID" != "$WORKTREE_ID" ] && pass 'staged and unstaged baseline identities are distinct' ||
	fail 'staged and unstaged baseline identities collapsed into one receipt'
[ "$(cat "$REPO/product.txt")" = 'staged before scope was admitted' ] &&
	[ "$(cat "$REPO/worktree.txt")" = 'unstaged before scope was admitted' ] &&
	[ "$(cat "$REPO/untracked.txt")" = 'untracked before scope was admitted' ] &&
	pass 'task start did not reset, stage, or remove prior work' ||
	fail 'task start changed the prior work it was told to preserve'

task_repo
printf '%s\n' 'untracked before scope was admittee' >"$REPO/untracked.txt"
expect_exit 0 'a second acknowledged untracked baseline starts' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/preserve.task"
expect_exit 0 'the second baseline reports its identities' -- sh "$COMMAND" status "$REPO"
CHANGED_UNTRACKED_ID=$(printf '%s\n' "$T_OUT" | sed -n 's/^baseline-untracked|//p')
[ "$UNTRACKED_ID" != "$CHANGED_UNTRACKED_ID" ] &&
	pass 'a one-byte untracked change changes the baseline identity' ||
	fail 'a one-byte untracked change kept the same baseline identity'

task_repo
printf '%s\n' 'ambiguous path' >"$REPO/bad|path"
expect_exit 2 'an untracked path that cannot be represented is refused' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/preserve.task"
expect_said 'unsupported untracked path: bad|path'
STATE=$(git -C "$REPO" rev-parse --path-format=absolute --git-dir)/agentic-sdlc/task
[ ! -e "$STATE" ] && pass 'unsupported path created no task state' || fail 'unsupported path created task state'

task_repo
ln -s /etc/passwd "$REPO/untracked-link"
expect_exit 2 'an untracked symlink cannot pull outside bytes into the baseline' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/preserve.task"
expect_said 'unsupported untracked symlink: untracked-link'

task_repo
REAL_GIT=$(command -v git)
mkdir "$SCRATCH/failing-git"
cat >"$SCRATCH/failing-git/git" <<EOF
#!/bin/sh
case "\$*" in *'diff --cached'*) exit 70 ;; esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$SCRATCH/failing-git/git"
expect_exit 2 'a staged-diff read failure cannot be masked by hashing an empty stream' -- \
	env PATH="$SCRATCH/failing-git:$PATH" sh "$COMMAND" start "$REPO" "$SCRATCH/small.task"
expect_said 'cannot read staged baseline'

task_repo
printf '%s\n' 'untracked input' >"$REPO/untracked.txt"
mkdir "$SCRATCH/failing-untracked-hash"
cat >"$SCRATCH/failing-untracked-hash/git" <<EOF
#!/bin/sh
case "\$*" in *'hash-object --no-filters -- '*'untracked.txt') exit 71 ;; esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$SCRATCH/failing-untracked-hash/git"
expect_exit 2 'an untracked-content hash failure cannot be masked by receipt formatting' -- \
	env PATH="$SCRATCH/failing-untracked-hash:$PATH" sh "$COMMAND" start "$REPO" "$SCRATCH/preserve.task"
expect_said 'cannot hash untracked file: untracked.txt'

task_repo
mkdir "$SCRATCH/failing-status"
cat >"$SCRATCH/failing-status/git" <<EOF
#!/bin/sh
case "\$*" in *'status --porcelain --untracked-files=all'*) exit 72 ;; esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$SCRATCH/failing-status/git"
expect_exit 2 'a worktree-status failure cannot look like a clean baseline' -- \
	env PATH="$SCRATCH/failing-status:$PATH" sh "$COMMAND" start "$REPO" "$SCRATCH/small.task"
expect_said 'cannot read worktree status'

task_repo
cat >"$SCRATCH/wave-incomplete.task" <<'EOF'
task|1
kind|implementation
size|wave
scope|Build the lifecycle wave.
acceptance|The wave is decomposed into bounded tickets.
phases|specification
endpoint|tickets
authorization|The operator authorized planning this wave.
provenance|prd:#fixture
EOF
expect_exit 2 'a wave cannot reach production work before decomposition' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/wave-incomplete.task"
expect_said 'missing required phase for implementation/wave: decomposition'
sed 's/phases|specification/phases|specification decomposition/' \
	"$SCRATCH/wave-incomplete.task" >"$SCRATCH/wave.task"
expect_exit 0 'a decomposed wave ends at bounded tickets' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/wave.task"
expect_exit 0 'wave status records the tickets endpoint' -- sh "$COMMAND" status "$REPO"
expect_said 'endpoint|tickets'
printf '%s\n' "$T_OUT" | grep -qx 'phases|specification decomposition' &&
	pass 'wave status carries the exact admitted phases record' ||
	fail 'wave status does not carry the exact phases record'

task_repo
sed 's/phases|specification decomposition/phases|specification decomposition implementation/' \
	"$SCRATCH/wave.task" >"$SCRATCH/wave-implementation.task"
expect_exit 2 'a wave contract naming the implementation phase is refused' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/wave-implementation.task"
expect_said 'phase implementation is not permitted for implementation/wave'

task_repo
cat >"$SCRATCH/investigation-wave.task" <<'EOF'
task|1
kind|investigation
size|wave
scope|Investigate a multi-session system question.
acceptance|The investigation is decomposed before its sessions begin.
phases|investigation artifact
endpoint|artifact
authorization|The operator authorized read-only investigation.
provenance|ordinary-request
EOF
expect_exit 2 'a multi-session investigation must decompose before investigating' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/investigation-wave.task"
expect_said 'wave investigation endpoint must be tickets'
sed -e 's/phases|investigation artifact/phases|specification decomposition/' \
	-e 's/endpoint|artifact/endpoint|tickets/' \
	"$SCRATCH/investigation-wave.task" >"$SCRATCH/investigation-tickets.task"
expect_exit 0 'a multi-session investigation ends at bounded tickets' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/investigation-tickets.task"

task_repo
cat >"$SCRATCH/report.task" <<'EOF'
task|1
kind|report-only
size|small
scope|Report the current repository state.
acceptance|The requested report exists.
phases|analysis artifact
endpoint|artifact
authorization|The operator authorized read-only inspection and the report artifact.
provenance|ordinary-request
EOF
expect_exit 0 'a report-only request ends at its artifact without an invented PR' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/report.task"
expect_exit 0 'report status preserves its explicit endpoint and authorization' -- sh "$COMMAND" status "$REPO"
expect_said 'kind|report-only'
expect_said 'phases|analysis artifact'
expect_said 'endpoint|artifact'
expect_said 'authorization|The operator authorized read-only inspection and the report artifact.'
expect_unsaid 'reviewed-pr'

task_repo
sed 's/kind|report-only/kind|read-only/' "$SCRATCH/report.task" >"$SCRATCH/read-only.task"
expect_exit 0 'a read-only request also ends at its artifact' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/read-only.task"

task_repo
sed 's/endpoint|artifact/endpoint|reviewed-pr/' "$SCRATCH/report.task" >"$SCRATCH/report-pr.task"
expect_exit 2 'report-only scope cannot silently grow to a PR endpoint' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/report-pr.task"
expect_said 'report-only endpoint must be artifact'

task_repo
cat >"$SCRATCH/local.task" <<'EOF'
task|1
kind|implementation
size|small
scope|Prepare the bounded change only in this worktree.
acceptance|The change is technically verified without remote delivery.
phases|implementation technical-verification review
endpoint|local-worktree
authorization|The operator authorized local implementation and independent review, but said do not push.
provenance|ordinary-request
exception|The operator explicitly said do not push.
consequence|No remote delivery or reviewed-PR completion may be claimed.
EOF
expect_exit 0 'an explicit do-not-push implementation ends in the local worktree' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/local.task"
expect_exit 0 'local endpoint status preserves its exception and consequence' -- sh "$COMMAND" status "$REPO"
expect_said 'endpoint|local-worktree'
expect_said 'phases|implementation technical-verification review'
expect_said 'exception|The operator explicitly said do not push.'
expect_said 'consequence|No remote delivery or reviewed-PR completion may be claimed.'

task_repo
sed '/^exception|/d' "$SCRATCH/local.task" >"$SCRATCH/local-no-exception.task"
expect_exit 2 'a local endpoint without an explicit exception is refused' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/local-no-exception.task"
expect_said 'local-worktree endpoint requires exception and consequence'

task_repo
sed 's/phases|implementation technical-verification review/phases|implementation technical-verification review delivery/' \
	"$SCRATCH/local.task" >"$SCRATCH/local-delivery.task"
expect_exit 2 'a local endpoint cannot claim remote delivery' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/local-delivery.task"
expect_said 'phase delivery is not permitted for implementation/small'

task_repo
printf '%s\n' 'task|1' 'kind|implementation' 'size|small' \
	'scope|Change only the example task boundary.' \
	'acceptance|An unterminated contract round-trips through status.' \
	'phases|implementation technical-verification review delivery' \
	'endpoint|reviewed-pr' 'authorization|The operator authorized this task.' >"$SCRATCH/unterminated.task"
printf '%s' 'provenance|ticket:#fixture' >>"$SCRATCH/unterminated.task"
expect_exit 0 'a contract whose last record has no newline starts' -- \
	sh "$COMMAND" start "$REPO" "$SCRATCH/unterminated.task"
expect_exit 0 'status reads back the state an unterminated contract wrote' -- \
	sh "$COMMAND" status "$REPO"
printf '%s\n' "$T_OUT" | grep -qx 'provenance|ticket:#fixture' &&
	pass 'the last contract record stays its own record' ||
	fail 'the last contract record ran into the generated identity'

[ -f "$KIT/scripts/task.md" ] && pass 'task grammar and routes are documented beside the command' ||
	fail 'scripts/task.md is missing'
grep -q 'Contracts are data and are never sourced as shell' "$KIT/scripts/task.md" &&
	pass 'task documentation preserves the data-only trust boundary' ||
	fail 'task documentation does not say contracts are data'

t_done task
