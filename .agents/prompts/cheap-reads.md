# Cheap reads — the smallest exact answer first

Every byte a read returns is context you pay for and re-read. Whole files and
whole diffs were most of what spawned workers read, so ask the narrow question
before the broad one:

| You want to know…                    | Read this                                  | Not this                     |
| ------------------------------------ | ------------------------------------------ | ---------------------------- |
| what a change touches                | `git diff --stat <base>...HEAD`, then `git diff <base>...HEAD -- <path>` for the paths that matter | the whole `git diff` |
| when a string appeared or vanished   | `git log -S '<string>' --oneline [-- <path>]` | `git log -p` read end to end |
| where a name is used                 | `grep -rnw '<name>' <dir>` (or `grep -w`), word-bounded | a bare substring grep, then opening every hit |
| what a function or section says      | the file by line range: `sed -n '<from>,<to>p' <file>`, or your reader's offset and limit, after a `grep -n` found the lines | the whole file |

Widen only when the narrow read was not enough, and say why. A count
(`grep -c`, `wc -l`) answers "how many" without the lines themselves.
