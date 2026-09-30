# `claude-code/` — wiring one agent harness into the kit

Two questions the portable core cannot answer, because both are this agent
harness's own: **where does a resolved capability tier go at spawn time**, and
**how does a session's token usage reach the decision trace**. The first half of
this note is prose about a mechanism; the second half ("Wiring the session
hooks") points at real files under `hooks/`, which ship and arrive inert.

The kit resolves a **capability tier** — and optionally a **task domain** — to a
model identifier and stops there:

```sh
sh scripts/agents.lib.sh implementer           # prints the mapped id, or nothing
sh scripts/agents.lib.sh implementer content   # the same, for prose work
```

What it deliberately does not know is **where that string goes** when an agent
spawns a subagent. That is harness-specific, it is the one part of this feature
that cannot be written portably, and it is why this note exists.

> Read this for the *shape*. If you drive the kit with a different harness, the
> question to answer is the same one — "which parameter of my spawn call takes a
> model identifier, and what does omitting it mean?" — and the answer belongs in
> a sibling directory here, in your own repo.

## The wiring, in one line

Claude Code's sub-agent spawn (the `Task` / `Agent` tool) takes an optional
**`model`** parameter. Omit it and the subagent inherits the parent session's
model — which is exactly why "unmapped resolves to nothing" is a working state
rather than an error: an empty resolution and no parameter are the same call.

So the pattern a skill follows is:

```sh
model=$(sh scripts/agents.lib.sh mechanical)
# then: spawn with model="$model" if it is non-empty, and with no model
#       parameter at all if it is empty.
```

And with a domain, when the ticket carries one — the branch is identical,
because the second axis changes which variable is read and nothing about the
call:

```sh
# ticket says:  Tier: implementer  /  Domain: content
model=$(sh scripts/agents.lib.sh implementer content)
# -> AGENT_TIER_IMPLEMENTER_CONTENT if the project mapped it,
#    AGENT_TIER_IMPLEMENTER if not, and the empty-means-omit branch either way.
```

Two things worth being explicit about:

- **Do not pass an empty string** as the model parameter. Omitting a parameter
  and passing `""` are not the same request, and a harness is within its rights
  to reject the second. Branch on emptiness.
- **The resolver's warning goes to stderr**, never stdout. `$(...)` therefore
  captures the model id and nothing else, and the operator still sees the
  warning. If you ever wrap this in something that merges the streams, you will
  start spawning agents on a model called `! agents: capability tier ...`.

## Filling in `scripts/agents.config.sh`

The values are whatever identifiers your account can actually invoke — not
marketing names, and not the values in anyone's blog post. Get them from the
harness or the provider's own model list at the moment you configure it, and
re-check when a tier's cost/benefit shape moves.

The four variables and the decision each one encodes:

| Variable | Give it | Because |
| --- | --- | --- |
| `AGENT_TIER_PLANNER` | your strongest reasoning model | its output constrains every downstream ticket; a bad decomposition is paid for many times |
| `AGENT_TIER_IMPLEMENTER` | a strong general model | the default for real work — this is where most sessions land |
| `AGENT_TIER_MECHANICAL` | the cheapest model that can hold the task | the suite is the oracle here, so capability past "can follow the pattern" buys nothing |
| `AGENT_TIER_REVIEWER` | a strong model, in fresh context | a review is a verdict, and a cheap verdict is a rubber stamp |

The single biggest saving is `mechanical`, because expand–migrate–contract waves
are mostly migrate tickets. The single most expensive mistake is a cheap
`reviewer`, because it fails silently.

### The optional domain overrides

Each tier also takes `AGENT_TIER_<TIER>_<DOMAIN>`, consulted first and falling
back to the plain variable. Set one only where the medium genuinely changes your
answer — the usual pair being "the best coding model" and "the best writing
model" at the `implementer` tier:

```sh
AGENT_TIER_IMPLEMENTER='<a strong general model>'
AGENT_TIER_IMPLEMENTER_CONTENT='<the one you would hand a launch post to>'
```

Everything you leave unset keeps resolving through the tier, so this stays a
two-line change rather than a matrix to maintain. Note the fold: a domain token
may contain hyphens and a variable name may not, so `html-report` reads
`AGENT_TIER_IMPLEMENTER_HTML_REPORT`.

## Wiring the session hooks

The other half of this adapter is `hooks/`, and it answers a different
question: **what did that session cost, and which model spent it?**
`scripts/trace.sh` records the chain's decisions but knows nothing about a
session — sessions belong to the agent harness, which is why these four files
live here rather than in the shared script (ADR-0008 clause 8).

| File | The event it records |
| --- | --- |
| `hooks/session-start.sh` | `session.start`, and the session identity every later emit joins on |
| `hooks/session-end.sh` | one `session.usage` per model with four token counts — only what is new since this session's last one — then `session.end` |
| `hooks/subagent-stop.sh` | `agent.stop` for one subagent, with its id, its type and its own tokens |
| `hooks/tool-post.sh` | `tool.use` for one tool call — behind its own switch, see below |
| `hooks/transcript-usage.mjs` | not a hook: the extractor the two usage hooks call |
| `hooks/tool-payload.mjs` | not a hook either: the reader `tool-post.sh` splits a payload with |
| `hooks/hook.lib.sh` | not a hook either: what the four share |

**They are dormant until a settings file names them.** Three properties make
that safe to leave in your tree: every hook exits 0 whatever happens, none of
them writes to stdout, and each sets the trace's quiet variable so a project
that never turned tracing on hears nothing. Observability that can fail a
session is worse than none.

To turn them on, wire the three events in your own `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command",
      "command": "sh \"$CLAUDE_PROJECT_DIR/adapters/claude-code/hooks/session-start.sh\"" } ] } ],
    "SessionEnd": [ { "hooks": [ { "type": "command",
      "command": "sh \"$CLAUDE_PROJECT_DIR/adapters/claude-code/hooks/session-end.sh\"" } ] } ],
    "SubagentStop": [ { "hooks": [ { "type": "command",
      "command": "sh \"$CLAUDE_PROJECT_DIR/adapters/claude-code/hooks/subagent-stop.sh\"" } ] } ]
  }
}
```

Then set `TRACE_DIR` in `scripts/trace.config.sh` — without it every emit is a
silent no-op, which is the shipped default and a working state.

### And the tool hook, behind its own switch

Every tool call can be captured too, as one `tool.use` event carrying the tool's
name, the call's id, the first 512 bytes of its input on the line, and the FULL
input and FULL result in the blob store with the result's size. Two more events
wire it, both to the same script — the only difference between them is the
outcome it records:

```json
{
  "hooks": {
    "PostToolUse": [ { "hooks": [ { "type": "command",
      "command": "sh \"$CLAUDE_PROJECT_DIR/adapters/claude-code/hooks/tool-post.sh\"" } ] } ],
    "PostToolUseFailure": [ { "hooks": [ { "type": "command",
      "command": "sh \"$CLAUDE_PROJECT_DIR/adapters/claude-code/hooks/tool-post.sh\"" } ] } ]
  }
}
```

Wiring alone does nothing: the hook reads `TRACE_TOOLS` from your policy file and
that ships empty, so it exits 0 having written nothing until you set it to `1`.
That is a decision, not a formality — a tool call is the least decision-bearing
line in the trace and there are hundreds per session, and a tool *result* is the
contents of whatever was read. Turn it on for a wave you want to study.

Three things this hook deliberately does not do:

- **It records `ok` and `fail`, never `denied`.** A tool call the permission
  system refuses fires `PreToolUse` **only** — no `PostToolUse` and no
  `PostToolUseFailure` — and that payload is handed to the hook *before* the
  decision, so nothing on it says the call was denied. A denied call is
  therefore invisible here. An *interrupted* one is not: it reaches
  `PostToolUseFailure` and reads as `fail`.
- **There is no `PreToolUse` hook.** Both post payloads carry the whole
  `tool_input` themselves, so a pre hook would have nothing to add to the event
  and nothing of its own to emit — one more process per tool call for no line.
- **It never uses `hook_field` on a tool payload.** A tool payload arrives as
  one line of JSON whose values are arbitrary text, so a key-name search finds
  the LAST occurrence — and a tool result can quote `"session_id"` or
  `"tool_response"`. The payload goes through a real parser, which reads only
  top-level keys.

Five details found by watching this run, each of which costs a wrong number if
you get it wrong:

- **A streamed response is written more than once.** One assistant API response
  with two content blocks is two lines of the transcript, repeating the same
  `message.id` and a byte-identical usage block. Summing lines over-counts;
  de-duplicating by `message.id` reproduces the agent harness's own per-model
  rollup exactly.
- **A subagent's tokens are in the subagent's own file.** The `SubagentStop`
  payload carries two paths: `transcript_path` is the *parent session's* and
  `agent_transcript_path` is the subagent's. Read the first one there and every
  subagent that stops is charged with the whole session.
- **The session transcript's totals are not the session's totals.** Its final
  `cost-state` line holds a per-model rollup that *includes* the subagents, and
  the subagents' lines are not in that file. So the trace's total for a session
  is its `session.usage` events **plus** its `agent.stop` events — which is
  what makes them add up to that rollup, and how the suite checks them.
- **A resumed session ends more than once.** `claude -p --resume <id>` and
  `--continue` keep the session id and append to the same transcript, and
  `SessionEnd` fires at the end of every run — so an end that re-read the whole
  file would count every earlier response again. Each `session.usage` event
  therefore says how far it read (`data.last_msg`, and `data.msgs` for its
  model), and the next end of that session counts only what came after the
  last one the trace holds. The events stay a plain sum: `summary`, the export
  and the query below need no rule about which event supersedes which. A
  compaction appends to the same file too, but the call that writes its summary
  leaves no assistant line, so its tokens are in the rollup and in no event.
- **Cost is not recorded.** That same rollup carries the vendor's own cost
  figure and the extractor deliberately ignores it: a price is an
  interpretation that rots on the vendor's schedule, so the trace keeps token
  counts and prices them on read, from a table you own (ADR-0008 clause 6).

One known gap, observed in a live session rather than in a fixture: **the
subagent-stop hook can run before the subagent's transcript has its assistant
line**, and the `agent.stop` event then records that it found no usage and
carries the transcript path instead of tokens. A session's own `session.usage`
is unaffected and exact; what is lost is that session's subagent tokens, so the
"usage plus agent.stop equals the rollup" identity holds only when the file was
ready. Waiting for it is a decision with a timing guess in it and a hook that
sleeps delays a session, so it is deliberately not worked around here.

### Reading it back: DuckDB and SQLite

`sh scripts/trace.sh summary --by model` answers the usual question without
leaving the shell. Past that, the export is flat JSONL or CSV precisely so that
no transform stands between you and a query engine:

```sh
# CSV, priced on read from your own table, with priced_at and price_src columns
sh scripts/trace.sh export --csv --since 2026-09-01 > wave.csv
```

DuckDB reads either form in place — the JSONL directly, so you can query the
day files without exporting at all:

```sh
duckdb -c "SELECT model, sum(tok_in), sum(tok_out), sum(tok_cache_w), sum(tok_cache_r)
           FROM read_json_auto('$(sh scripts/trace.sh dir)/events/*.jsonl')
           WHERE kind IN ('session.usage', 'agent.stop') GROUP BY model ORDER BY 2 DESC"
duckdb wave.duckdb -c "CREATE TABLE events AS SELECT * FROM read_csv_auto('wave.csv')"
```

SQLite wants the CSV, and wants the columns typed after the fact — its importer
makes every column text:

```sh
sqlite3 wave.db <<'SQL'
.mode csv
.import wave.csv events_raw
CREATE TABLE events AS
  SELECT ts, kind, skill, subject, session, run, model, outcome, reason,
         CAST(tok_in AS INTEGER)      AS tok_in,
         CAST(tok_out AS INTEGER)     AS tok_out,
         CAST(tok_cache_w AS INTEGER) AS tok_cache_w,
         CAST(tok_cache_r AS INTEGER) AS tok_cache_r,
         CASE cost_usd WHEN 'unpriced' THEN NULL ELSE CAST(cost_usd AS REAL) END AS cost_usd
  FROM events_raw;
DROP TABLE events_raw;
SQL
```

Two things to know before you trust a row. `export` refuses to print at all
when `verify` fails on the selection, so a half-import is not a shape you can
reach by accident. And `cost_usd` reads the literal `unpriced` — never 0 — for
a token-bearing event whose model has no price in your table, which is why the
`CASE` above exists rather than a bare `CAST`.

## What this adapter deliberately does NOT contain

- **No model identifiers.** Not here either. This directory is reference prose
  about a mechanism; the moment it carried a real id it would rot on the same
  schedule the kit is avoiding, and it would rot somewhere a reader is far more
  likely to copy from than a comment in the policy file.
- **No settings file.** The hooks above are executable and they are inert:
  nothing in a stamped project names them, and the kit's own
  `.claude/settings.json` — the only file that does — is deleted by
  `bootstrap.sh` before your tree is stamped. That is the precise form of
  [`../README.md`](../README.md)'s claim that this tree arrives dormant: the
  scripts arrive, the wiring is yours to write.
- **No workflow, and no check on tier selection.** Tier selection is a
  spawn-time decision inside a session. There is nothing for CI to enforce, and
  a check that asserted "this ticket ran on the right model" would be asserting
  something the repo has no record of — which is what the trace's `spawn`
  events are for instead.
- **No tool-call capture unless you ask for it twice.** The hook is here, and
  wiring it is not enough: `TRACE_TOOLS` in your policy file is the second
  answer, and it ships empty. Two switches for one feature is the point — the
  volume and the privacy of a tool result are a different decision from the
  volume and privacy of a decision trail.

## Verifying it once

After filling the policy file in, from the repo root:

```sh
for t in planner implementer mechanical reviewer; do
  printf '%s -> %s\n' "$t" "$(sh scripts/agents.lib.sh "$t")"
done
```

Four non-empty values and no `UNMAPPED` warning on stderr means the mapping is
live. Any tier you deliberately left unmapped will print an empty value and warn
once — which is a decision, as long as it is one you made.

If you mapped any domains, check that the ones you meant to differ actually do:

```sh
for d in code content; do
  printf 'implementer/%s -> %s\n' "$d" "$(sh scripts/agents.lib.sh implementer "$d")"
done
```

Two identical values here mean the override is not being read — most likely the
variable name does not match the token (remember the hyphen fold), and the
resolver fell back to the tier exactly as designed, without a word. That silence
is the right default for the domains you never mapped, which is why this check
is worth running once on the ones you did.
