# Claude Code hook and transcript fixtures

Captured by the `/prototype` spike for ticket #246 (PRD #237) on **2026-09-23**
with the `claude` CLI at **2.1.278** and node **v26.8.1**, on Linux. They are the
oracle the adapter's suite reads: a real `SessionStart`, `SessionEnd` and
`SubagentStop` payload, and one real streamed transcript whose token sums are
known.

## How they were captured

A throwaway project directory under the scratchpad carried a
`.claude/settings.json` wiring three hooks, each a one-line shell script that
wrote its stdin to a file:

```json
{
  "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "…/hook-session-start.sh" } ] } ],
    "SubagentStop": [ { "hooks": [ { "type": "command", "command": "…/hook-subagent-stop.sh" } ] } ],
    "SessionEnd":   [ { "hooks": [ { "type": "command", "command": "…/hook-session-end.sh" } ] } ]
  }
}
```

The session was one non-interactive run that spawned exactly one subagent:

```sh
claude -p '…spawn one subagent that echoes $TRACE_SESSION…' \
  --output-format json --permission-mode bypassPermissions
```

The transcripts are the files the agent harness itself wrote under
`~/.claude/projects/<encoded cwd>/`.

## The files

| File | What it is |
| --- | --- |
| `session-start.payload.json` | the `SessionStart` hook's stdin, verbatim but for paths |
| `session-end.payload.json` | the `SessionEnd` hook's stdin |
| `subagent-stop.payload.json` | the `SubagentStop` hook's stdin — note `agent_transcript_path`, `agent_id`, `agent_type` |
| `transcript.redacted.jsonl` | the main session transcript, 30 lines, one assistant response split across two lines |
| `subagent-transcript.redacted.jsonl` | the subagent's own transcript, 20 lines, every line `isSidechain` |
| `tool-post.payload.json` | a `PostToolUse` hook's stdin — a shell call that succeeded |
| `tool-post-failure.payload.json` | a `PostToolUseFailure` hook's stdin — the same shell, a command that exited 1 |

## The second capture: the two tool payloads

The two `tool-*.payload.json` files above were captured separately for ticket
#252, on **2026-09-28**, with the same `claude` CLI (**2.1.278**) and the same
node (**v26.8.1**), the same way: a throwaway project under the scratchpad whose
settings file wired `PreToolUse`, `PostToolUse` and `PostToolUseFailure` to a
one-line script that wrote its stdin to a file, and one non-interactive run —

```sh
printf 'Run the shell command: cat file.txt ; then run the shell command: cat /nonexistent/nope.' |
  claude -p --permission-mode acceptEdits --allowedTools Bash
```

— so the pair is one session's successful call and its failed one. Three
properties of that capture are what the suite leans on, and none of them is
guessable from the session payloads beside them:

- **A tool payload arrives COMPACT**, on one line, unlike the pretty-printed
  session payloads in this directory. That is why `tool-post.sh` reads its
  payload with a real parser: a key-name search on one line finds the *last*
  occurrence, and a tool result can quote any key.
- **`PostToolUseFailure` carries no `tool_response` at all.** The failure is in
  `error`, beside `is_interrupt`, and that is the result the hook stores.
- **A DENIED call fires `PreToolUse` only.** Reproduced with a `Bash(rm:*)` deny
  rule: no `PostToolUse`, no `PostToolUseFailure`, and the `PreToolUse` payload —
  handed over before the decision — says nothing about the denial. There is no
  fixture for a denied call because there is no payload to capture.

## What was redacted

Structure, key order, ids and **every number** are untouched. Replaced:

- the capturing machine's home directory, with `~`;
- the throwaway project path and its encoded form, with `/tmp/spike-proj` and
  `-tmp-spike-proj`;
- every free-text body — prompt text, assistant text, thinking blocks and
  signatures, tool inputs, tool results, `rendered`, `toolUseResult`,
  `lastPrompt`, `wireToolInputs`, and each `attachment` body — with a
  `[REDACTED …, N chars]` placeholder that keeps the original length.

Session, message and request identifiers are kept, because the fixture's whole
point is that they join.

## The numbers a test may assert

De-duplicating assistant lines by `message.id` and summing the four usage keys
gives, for the main transcript, `input 34`, `output 287`,
`cache_creation 10793`, `cache_read 37519`; for the subagent transcript,
`input 34`, `output 156`, `cache_creation 17138`, `cache_read 14968`. Their sum
is exactly the `modelUsage` block on the main transcript's final `cost-state`
line: `68 / 443 / 27931 / 52487` for `claude-fable-5-1`. Summing without
de-duplicating gives `36 / 526 / 21036 / 51157` and is wrong.
