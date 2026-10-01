# Task entry

`scripts/task.sh` records the boundary between an ordinary request and lifecycle
work. It is a validator and a small worktree-local record, not a dispatcher or
workflow engine. It calls the runtime catalogue admission command, but it never
reads optional trace history and it does not launch a skill.

Write the contract outside the repository so creating it is not itself a
production edit, then start the task from its worktree:

```sh
sh scripts/task.sh start . /tmp/task.contract
sh scripts/task.sh status .
```

`start` exits 2 without creating state when the contract, catalogue, Git
worktree, branch, or routing combination is invalid. Success prints `started|1`.
It stores mode-600
state under this linked worktree's Git directory, so sibling worktrees do not
share a current task. A second start is refused. Later lifecycle slices extend
that record with evidence and resumable outcomes.

Start records the branch, HEAD, staged diff, unstaged diff, and untracked file
content as separate Git identities. A dirty worktree is accepted only when the
contract says `baseline|preserve`; the command never resets, stages, deletes, or
silently adopts prior work. Untracked paths containing a pipe, newline, or
another byte Git must quote are refused because the line record cannot identify
them unambiguously.

`status` rechecks the current branch and the complete catalogue admission
receipt before printing the contract. Catalogue bytes that changed after start
make status exit 2 and require a new task contract. Filesystem admission is
provenance evidence; it still does not prove which instructions a model loaded.

## Contract grammar

Contracts are data and are never sourced as shell. The first line is `task|1`.
Every following line is `field|value`; values are one non-empty line without a
pipe or tab. Each field appears once except `acceptance`, which may repeat:

```text
task|1
kind|implementation
size|small
scope|Change only the named command and its acceptance test.
acceptance|Missing scope is refused before task state exists.
acceptance|The accepted task reports its worktree and catalogue identities.
phases|implementation technical-verification review delivery
endpoint|reviewed-pr
authorization|The operator authorized implementation, push and review; merge remains human-only.
provenance|ticket:#123
```

Keep `scope`, `acceptance`, `authorization`, and `provenance` compact. Record the
source and the authority needed to resume; do not copy secrets, credentials, or
whole private conversations into the task record.

`kind` is one of `implementation`, `investigation`, `read-only`, or
`report-only`. `size` is `small` or `wave`. Phase tokens are
`specification`, `decomposition`, `investigation`, `analysis`, `artifact`,
`implementation`, `technical-verification`, `review`, `acceptance-qa`, and
`delivery`. The order is the requested order of work.

`baseline|preserve` is optional on a clean worktree and required on a dirty one.
An implementation with an explicit do-not-push boundary uses
`endpoint|local-worktree` and adds one `exception` and one `consequence` record.
Both explain why remote delivery is omitted and what stronger completion cannot
be claimed.

## Proportional routes

| Request | Required phases | Endpoint |
| --- | --- | --- |
| Small implementation | `implementation technical-verification review delivery` | `reviewed-pr` |
| Explicit local implementation exception | `implementation technical-verification`; `review` remains optional | `local-worktree`, with `exception` and `consequence` |
| Multi-session implementation wave | `specification decomposition` | `tickets` |
| Small investigation | `investigation artifact` | `artifact` |
| Multi-session investigation wave | `specification decomposition` | `tickets` |
| Read-only or report-only | `analysis artifact` | `artifact` |

A wave contract refuses `implementation` and `delivery`: its job is to create
the PRD and bounded tickets before any production edit. Each resulting ticket
gets its own small implementation contract in a fresh worktree. Read-only and
report-only contracts refuse implementation, review, and delivery, so an
artifact request cannot silently acquire a pull request endpoint. The
authorization text is evidence of authority already granted, not a prompt to
ask for it again and not authority to merge.
