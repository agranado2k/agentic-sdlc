#!/bin/sh
# Catalogue admission through its public command, including consumer bootstrap.
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd)
COMMAND="$KIT/scripts/catalogue.sh"
. "$KIT/tests/lib.sh"
t_init

mkdir -p "$SCRATCH/project/.agents/skills/example"
PROJECT=$(cd "$SCRATCH/project" && pwd -P)
printf '%s\n' '# Example skill' >"$PROJECT/.agents/skills/example/SKILL.md"
mkdir -p "$PROJECT/runtime"
cp -R "$PROJECT/.agents/skills/." "$PROJECT/runtime/"
printf '%s\n' 'catalogue|1' 'active|runtime|identical' >"$PROJECT/catalogue"

expect_exit 0 'identical active catalogue is admitted' -- sh "$COMMAND" check "$PROJECT" catalogue
expect_said 'admitted|1'
HASH=$(git hash-object "$PROJECT/.agents/skills/example/SKILL.md")
expect_said "source|.agents/skills/example/SKILL.md|$HASH"
expect_said "active|runtime/example/SKILL.md|$HASH"

printf '%s\n' '# Stale skill' >"$PROJECT/runtime/example/SKILL.md"
expect_exit 2 'stale copy is refused' -- sh "$COMMAND" check "$PROJECT" catalogue
expect_said 'stale copy: runtime/example/SKILL.md'
expect_unsaid 'admitted|1'
cp "$PROJECT/.agents/skills/example/SKILL.md" "$PROJECT/runtime/example/SKILL.md"
printf '%s\n' 'catalogue|1' 'active|Runtime|identical' >"$PROJECT/catalogue"
expect_exit 2 'wrong case refused even on a case-insensitive filesystem' -- sh "$COMMAND" check "$PROJECT" catalogue
expect_said 'missing or wrong-case path: Runtime'
printf '%s\n' 'catalogue|1' 'active|runtime|transform-v1' >"$PROJECT/catalogue"
expect_exit 2 'unverified transformation refused' -- sh "$COMMAND" check "$PROJECT" catalogue
expect_said 'unsupported transformation: transform-v1'

printf '%s\n' 'catalogue|1' 'active|runtime|identical' 'reference|executable|scripts/dead.sh' >"$PROJECT/catalogue"
expect_exit 2 'dead executable dependency is refused' -- sh "$COMMAND" check "$PROJECT" catalogue
expect_said 'missing or wrong-case path: scripts/dead.sh'
mkdir -p "$PROJECT/scripts"
printf '%s\n' '#!/bin/sh' 'exit 79' >"$PROJECT/scripts/dead.sh"
expect_exit 0 'declared executable dependency resolves without being executed' -- sh "$COMMAND" check "$PROJECT" catalogue
expect_said "reference|executable|scripts/dead.sh|$(git hash-object "$PROJECT/scripts/dead.sh")"
printf '%s\n' 'catalogue|1' 'active|runtime|identical' 'reference|optional|missing.md' >"$PROJECT/catalogue"
expect_exit 0 'absent optional reference is admitted and reported absent' -- sh "$COMMAND" check "$PROJECT" catalogue
expect_said 'reference|optional|missing.md|absent'
printf '%s\n' 'catalogue|1' 'active|runtime|identical' 'reference|optional|scripts/dead.sh' >"$PROJECT/catalogue"
expect_exit 0 'present optional reference reports its content hash' -- sh "$COMMAND" check "$PROJECT" catalogue
expect_said "reference|optional|scripts/dead.sh|$(git hash-object "$PROJECT/scripts/dead.sh")"
printf '%s\n' 'catalogue|1' 'active|runtime|identical' 'reference|optional|scripts/Dead.sh' >"$PROJECT/catalogue"
if [ -e "$PROJECT/scripts/Dead.sh" ]; then
	expect_exit 2 'present optional reference with wrong case is refused' -- sh "$COMMAND" check "$PROJECT" catalogue
	expect_said 'missing or wrong-case path: scripts/Dead.sh'
else
	expect_exit 0 'case-distinct absent optional path is reported absent' -- sh "$COMMAND" check "$PROJECT" catalogue
	expect_said 'reference|optional|scripts/Dead.sh|absent'
fi
printf '%s\n' 'catalogue|1' 'active|runtime|identical' 'reference|example|not-a-local-file' >"$PROJECT/catalogue"
expect_exit 0 'example reference reports that it was not checked' -- sh "$COMMAND" check "$PROJECT" catalogue
expect_said 'reference|example|not-a-local-file|not-checked'
printf '%s\n' 'catalogue|1' 'active|runtime|identical' 'reference|external|https://example.invalid/path' >"$PROJECT/catalogue"
expect_exit 0 'external reference reports that it was not checked' -- sh "$COMMAND" check "$PROJECT" catalogue
expect_said 'reference|external|https://example.invalid/path|not-checked'
printf '%s\n' 'catalogue|1' 'active|runtime|identical' 'reference|executable|scripts/Dead.sh' >"$PROJECT/catalogue"
expect_exit 2 'executable path case is exact' -- sh "$COMMAND" check "$PROJECT" catalogue
expect_said 'missing or wrong-case path: scripts/Dead.sh'
printf '%s\n' 'active|runtime|identical' >"$PROJECT/catalogue"
expect_exit 2 'missing schema is refused' -- sh "$COMMAND" check "$PROJECT" catalogue
printf '%s\n' 'catalogue|1' >"$PROJECT/catalogue"
expect_exit 2 'no declared active roots is refused' -- sh "$COMMAND" check "$PROJECT" catalogue
printf '%s\n' 'catalogue|1' 'active|runtime|identical|unparsed' >"$PROJECT/catalogue"
expect_exit 2 'surplus declaration fields are refused' -- sh "$COMMAND" check "$PROJECT" catalogue

printf '%s\n' 'catalogue|1' 'active|runtime|identical' >"$PROJECT/catalogue"
mkdir -p "$PROJECT/runtime/example/extra"
expect_exit 2 'undeclared extra active directory refused' -- sh "$COMMAND" check "$PROJECT" catalogue
rmdir "$PROJECT/runtime/example/extra"
mv "$PROJECT/runtime/example/SKILL.md" "$PROJECT/skill.saved"
expect_exit 2 'missing active skill refused' -- sh "$COMMAND" check "$PROJECT" catalogue
mkdir "$PROJECT/runtime/example/SKILL.md"
expect_exit 2 'directory replacing a skill file refused' -- sh "$COMMAND" check "$PROJECT" catalogue
rmdir "$PROJECT/runtime/example/SKILL.md"
mv "$PROJECT/skill.saved" "$PROJECT/runtime/example/SKILL.md"
printf '%s\n' 'sidecar' >"$PROJECT/.agents/skills/example/guide.md"
expect_exit 2 'missing sidecar refused' -- sh "$COMMAND" check "$PROJECT" catalogue
cp "$PROJECT/.agents/skills/example/guide.md" "$PROJECT/runtime/example/guide.md"
ln -s .agents/skills "$PROJECT/linked"
printf '%s\n' 'catalogue|1' 'active|runtime|identical' 'active|linked|identical' >>"$PROJECT/roots"
expect_exit 0 'multiple copied and linked roots agree with source' -- sh "$COMMAND" check "$PROJECT" roots
expect_said "active|linked/example/SKILL.md|$HASH"
cp -R "$PROJECT/runtime" "$PROJECT/second"
printf '%s\n' '# Stale second root' >"$PROJECT/second/example/SKILL.md"
printf '%s\n' 'catalogue|1' 'active|runtime|identical' 'active|second|identical' >"$PROJECT/second-stale"
expect_exit 2 'stale second root is refused even when the first root is valid' -- sh "$COMMAND" check "$PROJECT" second-stale
expect_said 'stale copy: second/example/SKILL.md'
printf '%s\n' 'catalogue|1' "active|$PROJECT/runtime|identical" >"$PROJECT/absolute"
expect_exit 0 'caller can declare an absolute active root' -- sh "$COMMAND" check "$PROJECT" absolute
mkdir "$PROJECT/looproot"
ln -s ../looproot "$PROJECT/looproot/example"
printf '%s\n' 'catalogue|1' 'active|looproot|identical' >"$PROJECT/loop"
expect_exit 2 'active symlink cycle refused against finite canonical tree' -- sh "$COMMAND" check "$PROJECT" loop
mkdir "$SCRATCH/repository with spaces"
cp -R "$PROJECT/." "$SCRATCH/repository with spaces/"
expect_exit 0 'repository argument supports spaces with relative declared roots' -- sh "$COMMAND" check "$SCRATCH/repository with spaces" catalogue
printf '%s\n' 'catalogue|1' 'active|root with spaces|identical' >"$PROJECT/unsupported"
expect_exit 2 'unsupported declared path has actionable diagnostic' -- sh "$COMMAND" check "$PROJECT" unsupported
expect_said 'unsupported path: root with spaces'
printf '%s\n' 'named-file bytes' >"$PROJECT/--stdin"
printf '%s\n' 'catalogue|1' 'active|runtime|identical' 'reference|executable|--stdin' >"$PROJECT/options"
expect_exit 0 'option-shaped dependency is hashed as a filename' -- sh "$COMMAND" check "$PROJECT" options
expect_said "reference|executable|--stdin|$(git hash-object -- "$PROJECT/--stdin")"
expect_exit 2 'declaration filename must have exact case' -- sh "$COMMAND" check "$PROJECT" Catalogue
expect_said 'missing or wrong-case path: Catalogue'

mkdir -p "$SCRATCH/linked-source/.agents" "$SCRATCH/linked-source/runtime"
ln -s "$PROJECT/.agents/skills" "$SCRATCH/linked-source/.agents/skills"
cp "$PROJECT/catalogue" "$SCRATCH/linked-source/catalogue"
expect_exit 2 'canonical root cannot itself be a linked directory' -- sh "$COMMAND" check "$SCRATCH/linked-source" catalogue
expect_said 'canonical directory must not be linked: .agents/skills'

mkdir -p "$SCRATCH/empty/.agents/skills" "$SCRATCH/empty/runtime"
cp "$PROJECT/catalogue" "$SCRATCH/empty/catalogue"
expect_exit 2 'empty canonical catalogue refused' -- sh "$COMMAND" check "$SCRATCH/empty" catalogue
mkdir -p "$SCRATCH/empty/.agents/skills/broken" "$SCRATCH/empty/runtime/broken"
printf '%s\n' 'orphan' >"$SCRATCH/empty/.agents/skills/broken/README.md"
cp "$SCRATCH/empty/.agents/skills/broken/README.md" "$SCRATCH/empty/runtime/broken/README.md"
expect_exit 2 'canonical skill without SKILL.md refused' -- sh "$COMMAND" check "$SCRATCH/empty" catalogue

mkdir -p "$PROJECT/.agents/skills/.hidden" "$PROJECT/runtime/.hidden"
expect_exit 2 'hidden canonical skill without SKILL.md is refused' -- sh "$COMMAND" check "$PROJECT" catalogue
expect_said 'missing or wrong-case path: .agents/skills/.hidden/SKILL.md'
rmdir "$PROJECT/.agents/skills/.hidden" "$PROJECT/runtime/.hidden"

TREE="$SCRATCH/kit"
t_kit_tree "$KIT" "$TREE"
t_consumer_from "$TREE" "$SCRATCH/consumer" 'Catalogue Fixture' 'catalogue@example.invalid' --no-dogfood 'Catalogue Fixture' 'Catalogue admission fixture.'
expect_exit 0 'clean bootstrap reproduces an admitted catalogue without optional skill' -- sh scripts/catalogue.sh check .
expect_said 'admitted|1'
expect_unsaid '/dogfood/'
[ ! -e tests/catalogue.test.sh ] && pass 'bootstrap strips catalogue test' || fail 'bootstrap leaked catalogue test'
[ ! -e docs/adr/0011-task-local-contracts-bound-the-lifecycle.md ] && pass 'bootstrap strips kit ADR' || fail 'bootstrap leaked kit ADR'
expect_exit 0 'repeat admission is reproducible' -- sh scripts/catalogue.sh check .
first="$T_OUT|$T_ERR"
t_exec sh scripts/catalogue.sh check .
[ "$first" = "$T_OUT|$T_ERR" ] && pass 'unchanged catalogue has identical admission output' || fail 'admission changed without source changes'

t_done catalogue
