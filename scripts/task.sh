#!/bin/sh
# Start and inspect a task-local lifecycle contract.
set -eu
LC_ALL=C
export LC_ALL

task_here=$(cd "$(dirname "$0")" && pwd -P)
die() { printf 'task: %s\n' "$*" >&2; exit 2; }
has_phase() { case " $phases " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
need_phase() { has_phase "$1" || die "missing required phase for $kind/$size: $1"; }
forbid_phase() { has_phase "$1" && die "phase $1 is not permitted for $kind/$size"; return 0; }

[ "$#" -ge 2 ] || die 'usage: sh scripts/task.sh start REPOSITORY CONTRACT | status REPOSITORY'
command=$1
repository=$2
case $command in
start) [ "$#" = 3 ] || die 'usage: sh scripts/task.sh start REPOSITORY CONTRACT' ;;
status) [ "$#" = 2 ] || die 'usage: sh scripts/task.sh status REPOSITORY' ;;
*) die "unknown command: $command" ;;
esac

repository=$(cd "$repository" 2>/dev/null && pwd -P) || die "cannot open repository: $repository"
git_dir=$(git -C "$repository" rev-parse --path-format=absolute --git-dir 2>/dev/null) ||
	die "not a git repository: $repository"
state_dir=$git_dir/agentic-sdlc
state=$state_dir/task

catalogue_receipt() {
	_catalogue_out=$(sh "$task_here/catalogue.sh" check "$repository" 2>&1) || {
		printf '%s\n' "$_catalogue_out" >&2
		die 'catalogue admission failed'
	}
	printf '%s\n' "$_catalogue_out" | git hash-object --stdin
}

if [ "$command" = status ]; then
	[ -f "$state" ] || die 'no task has started'
	stored_worktree=$(sed -n 's/^worktree|//p' "$state")
	stored_branch=$(sed -n 's/^branch|//p' "$state")
	stored_catalogue=$(sed -n 's/^catalogue-receipt|//p' "$state")
	[ -n "$stored_worktree" ] && [ -n "$stored_branch" ] && [ -n "$stored_catalogue" ] ||
		die 'stored task state is malformed'
	[ "$stored_worktree" = "$repository" ] || die "task belongs to worktree: $stored_worktree"
	branch=$(git -C "$repository" symbolic-ref --quiet --short HEAD 2>/dev/null) ||
		die 'task worktree has no branch'
	[ "$stored_branch" = "$branch" ] || die "task belongs to branch: $stored_branch"
	current_catalogue=$(catalogue_receipt)
	[ "$stored_catalogue" = "$current_catalogue" ] || die 'catalogue changed; start a new task contract'
	cat "$state"
	exit 0
fi

contract=$3
[ -f "$contract" ] || die "missing contract: $contract"
[ ! -e "$state" ] || die 'a task has already started in this worktree'
scratch=$(mktemp -d "${TMPDIR:-/tmp}/task.XXXXXX") || die 'cannot create task scratch directory'
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
contract_copy=$scratch/contract
cp "$contract" "$contract_copy" || die 'cannot snapshot task contract'

kind=
size=
scope=
acceptance_count=0
phases=
endpoint=
authorization=
provenance=
baseline=
exception=
consequence=
seen=
first=1
while IFS= read -r line || [ -n "$line" ]; do
	if [ "$first" = 1 ]; then
		[ "$line" = 'task|1' ] || die 'first record must be task|1'
		first=0
		continue
	fi
	case $line in *'|'*) ;; *) die "malformed contract record: $line" ;; esac
	field=${line%%|*}
	value=${line#*|}
	[ -n "$value" ] || die "empty $field"
	case $value in *'|'* | *"	"*) die "unsupported $field value" ;; esac
	case $field in
	acceptance) acceptance_count=$((acceptance_count + 1)) ;;
	kind | size | scope | phases | endpoint | authorization | provenance | baseline | exception | consequence)
		case " $seen " in *" $field "*) die "duplicate $field" ;; esac
		seen="$seen $field"
		case $field in
		kind) kind=$value ;;
		size) size=$value ;;
		scope) scope=$value ;;
		phases) phases=$value ;;
		endpoint) endpoint=$value ;;
		authorization) authorization=$value ;;
		provenance) provenance=$value ;;
		baseline) baseline=$value ;;
		exception) exception=$value ;;
		consequence) consequence=$value ;;
		esac
		;;
	*) die "unknown contract field: $field" ;;
	esac
done <"$contract_copy"
[ "$first" = 0 ] || die 'missing task schema'
[ -n "$kind" ] || die 'missing kind'
[ -n "$size" ] || die 'missing size'
[ -n "$scope" ] || die 'missing scope'
[ "$acceptance_count" -gt 0 ] || die 'missing acceptance'
[ -n "$phases" ] || die 'missing phases'
[ -n "$endpoint" ] || die 'missing endpoint'
[ -n "$authorization" ] || die 'missing authorization'
[ -n "$provenance" ] || die 'missing provenance'
[ -z "$baseline" ] || [ "$baseline" = preserve ] || die 'baseline must be preserve'

case $kind in implementation | investigation | read-only | report-only) ;; *) die "unknown kind: $kind" ;; esac
case $size in small | wave) ;; *) die "unknown size: $size" ;; esac
case $endpoint in reviewed-pr | tickets | artifact | local-worktree) ;; *) die "unknown endpoint: $endpoint" ;; esac
[ "$endpoint" = local-worktree ] || [ -z "$exception$consequence" ] ||
	die 'exception and consequence are only valid for a local-worktree endpoint'
case $phases in '' | ' '* | *' ' | *'  '*) die 'phases must be single-space-separated tokens' ;; esac
phase_seen=
for phase in $phases; do
	case $phase in
	specification | decomposition | investigation | analysis | artifact | implementation | technical-verification | review | acceptance-qa | delivery) ;;
	*) die "unknown phase: $phase" ;;
	esac
	case " $phase_seen " in *" $phase "*) die "duplicate phase: $phase" ;; esac
	phase_seen="$phase_seen $phase"
done

case $kind/$size in
implementation/small)
	case $endpoint in
	reviewed-pr)
		need_phase implementation
		need_phase technical-verification
		need_phase review
		need_phase delivery
		;;
	local-worktree)
		[ -n "$exception" ] && [ -n "$consequence" ] ||
			die 'local-worktree endpoint requires exception and consequence'
		need_phase implementation
		need_phase technical-verification
		forbid_phase delivery
		;;
	*) die 'small implementation endpoint must be reviewed-pr or local-worktree' ;;
	esac
	;;
implementation/wave)
	[ "$endpoint" = tickets ] || die 'wave implementation endpoint must be tickets'
	need_phase specification
	need_phase decomposition
	forbid_phase implementation
	forbid_phase delivery
	;;
investigation/small)
	[ "$endpoint" = artifact ] || die 'investigation endpoint must be artifact'
	need_phase investigation
	need_phase artifact
	forbid_phase implementation
	forbid_phase delivery
	;;
investigation/wave)
	[ "$endpoint" = tickets ] || die 'wave investigation endpoint must be tickets'
	need_phase specification
	need_phase decomposition
	forbid_phase investigation
	forbid_phase implementation
	forbid_phase delivery
	;;
read-only/small | report-only/small)
	[ "$endpoint" = artifact ] || die "$kind endpoint must be artifact"
	need_phase analysis
	need_phase artifact
	forbid_phase implementation
	forbid_phase review
	forbid_phase delivery
	;;
read-only/wave | report-only/wave) die "$kind cannot have wave size" ;;
esac

branch=$(git -C "$repository" symbolic-ref --quiet --short HEAD 2>/dev/null) ||
	die 'task worktree has no branch'
case $repository in *'|'*) die 'worktree path cannot contain a pipe' ;; esac
baseline_head=$(git -C "$repository" rev-parse HEAD 2>/dev/null) || die 'task worktree has no HEAD commit'
index_receipt=$scratch/index
worktree_receipt=$scratch/worktree
untracked=$scratch/untracked
untracked_receipt=$scratch/untracked-receipt
git -C "$repository" diff --cached --binary --no-ext-diff HEAD -- >"$index_receipt" ||
	die 'cannot read staged baseline'
git -C "$repository" diff --binary --no-ext-diff -- >"$worktree_receipt" ||
	die 'cannot read unstaged baseline'
baseline_index=$(git hash-object --no-filters -- "$index_receipt") ||
	die 'cannot hash staged baseline'
baseline_worktree=$(git hash-object --no-filters -- "$worktree_receipt") ||
	die 'cannot hash unstaged baseline'
git -C "$repository" -c core.quotePath=true ls-files --others --exclude-standard >"$untracked" ||
	die 'cannot list untracked baseline'
: >"$untracked_receipt"
while IFS= read -r path || [ -n "$path" ]; do
	case $path in
	\"* | *'|'*) die "unsupported untracked path: $path" ;;
	esac
	[ ! -L "$repository/$path" ] || die "unsupported untracked symlink: $path"
	[ -f "$repository/$path" ] ||
		die "untracked path is not a file: $path"
	file_receipt=$(git hash-object --no-filters -- "$repository/$path") ||
		die "cannot hash untracked file: $path"
	printf 'untracked|%s|%s\n' "$path" "$file_receipt" >>"$untracked_receipt"
done <"$untracked"
baseline_untracked=$(git hash-object --no-filters -- "$untracked_receipt") ||
	die 'cannot hash untracked baseline'
worktree_status=$(git -C "$repository" status --porcelain --untracked-files=all) ||
	die 'cannot read worktree status'
if [ -n "$worktree_status" ] && [ "$baseline" != preserve ]; then
	die 'dirty baseline requires baseline|preserve; task start never resets or adopts prior work implicitly'
fi
catalogue=$(catalogue_receipt)

[ ! -L "$state_dir" ] || die "task state directory must not be a symlink: $state_dir"
mkdir -p "$state_dir" || die "cannot create task state directory: $state_dir"
tmp=$(mktemp "$state_dir/task.XXXXXX") || die 'cannot create temporary task state'
trap 'rm -f "$tmp"; rm -rf "$scratch"' EXIT HUP INT TERM
{
	cat "$contract_copy"
	printf 'worktree|%s\nbranch|%s\nbaseline-head|%s\nbaseline-index|%s\nbaseline-worktree|%s\nbaseline-untracked|%s\ncatalogue-receipt|%s\n' \
		"$repository" "$branch" "$baseline_head" "$baseline_index" "$baseline_worktree" "$baseline_untracked" "$catalogue"
} >"$tmp"
chmod 600 "$tmp"
mv "$tmp" "$state"
rm -rf "$scratch"
trap - EXIT HUP INT TERM
printf 'started|1\n'
