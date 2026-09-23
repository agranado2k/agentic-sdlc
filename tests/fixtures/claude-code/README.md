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
