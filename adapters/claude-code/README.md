# `claude-code/` — wiring one agent harness into the kit

Three questions the portable core cannot answer, because each is this agent
harness's own: **where does a resolved capability tier go at spawn time**,
**how is a typed-return reader denied a shell, a forge CLI and the network**,
and **how does a session's token usage reach the decision trace**. The first
two are prose about a mechanism; the third ("Wiring the session hooks") points
at real files under `hooks/`, which ship and arrive inert.

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

## Denying a typed-return reader its tools

Three skills — `/to-tickets`, `/pr-iterate` and the optional dogfood skill,
where it was taken — hand an untrusted read to a reader that has "no shell, no
forge CLI, no network" and sends back a typed return, and each one says that
how an agent harness withholds those tools is the adapter's to say. This is
the answer, for the two ways a Claude Code session can spawn that reader. They
are not the same kind of thing, and the one job of this section is to say
which is which: **the CLI withholds; the in-session tool is asked.**

### The CLI path — a restriction

Headless, `claude -p` takes three flags that together leave a reader with one
tool, confined to one directory, and no tool server. From `claude --help` on
2.1.285, verbatim:

- **`--tools`** — *"Specify the list of available tools from the built-in
  set. Use "" to disable all tools, "default" to use all tools, or specify
  tool names (e.g. "Bash,Edit,Read")"*. A reader gets exactly one.
- **`--restricted`** — *"Restricted mode: removes the built-in tools that run
  commands or code (Bash, PowerShell, REPL and the other code-running tools)
  and WebFetch unless --tools names them, and ignores user, project and local
  settings files (managed settings and --settings still apply; add
  --strict-mcp-config to skip MCP servers too). Also confines the file tools
  to the working directories (--add-dir included), refuses bypassPermissions,
  and lets only a person or the configured permission handler approve writes
  to settings, git and tool-configuration files."*
- **`--strict-mcp-config`** — *"Only use MCP servers from --mcp-config,
  ignoring all other MCP configurations"*.

The shell catches what the reader sends back:

```sh
# from $scratch: --restricted confines Read to the working directory, so
# the bodies are in reach and nothing else is. The prompt is on stdin, the
# return lands where the skill says, in a directory that holds nothing else
cd "$scratch" || exit 2
[ -n "$model" ] && set -- --model "$model"
claude -p --restricted --tools Read --strict-mcp-config "$@" < prompt > out/returns
```

- **`--tools Read`** — every built-in tool but file reading is gone: no
  `Bash` (so no shell and no `gh`), no `WebFetch`, no `WebSearch`, no `Write`
  or `Edit`. A tool that is absent cannot be asked for, prompted into use or
  talked around: the model's turn has no such call to make.
- **`--restricted` goes with `--tools`, not instead of it.** `--tools Read`
  alone leaves `Read` with the reach the user has: a credential file is a
  path like any other, and whether a read outside the working directory is
  refused then rests on the permission mode, which a settings file can open.
  `--restricted` confines the file tools to the working directories, ignores
  those settings files, and refuses `bypassPermissions` — so from `$scratch`
  the one directory in reach is `$scratch`, whatever the user's settings say.
- **`--strict-mcp-config`** — the built-in set is only half the list. Your
  project's and your user's settings may wire MCP servers, each a tool server
  with reach of its own (a forge, a mailbox, a browser), and `--tools` does
  not touch them. This flag admits only the servers named on `--mcp-config`,
  and you name none.
- **The redirect is the reader's one write.** The skills allow the return to be
  "captured there by the adapter", and that is this: the shell puts stdout in
  the file, so the reader needs no write tool to deliver it. The file's name
  is the calling skill's — `out/returns` for `/pr-iterate`, `out/return` for
  the other two.
- **The `set --` line** is the empty-means-omit branch from the top of this
  note, for `model=$(sh scripts/agents.lib.sh mechanical judge)`, written so
  the flag and its value stay two words under any `sh`.

**The flags are half of the fence, and the half the skills own is the other.**
A reader still reads whatever is in reach, and nothing here inspects what it
read. What makes the read safe is the return: typed lines held to a
vocabulary, and one evidence span verified against the scratch file the reader
was handed — so nothing it read can leave except by that span, and the span
is shown quoted, never obeyed. Use the two halves together. The flags without
the fence leave a reader that can write anything into the session's lap; the
fence without the flags leaves a reader with a shell to hand, which is the
case the next subsection is about.

Not the flags that look like it. `--allowedTools` is the permission
allowlist: it pre-approves the tools it names and withholds nothing, so a
reader spawned with `--allowedTools Read` still holds `Bash` and is merely
asked before each use — and headless, with nobody to ask, each use is denied
one call at a time, which leaves the shell in front of the model to keep
trying. `--disallowedTools` denies by name, and a name you forgot is a tool it
keeps. Name what stays, never what goes.

Watched on this host, from a directory holding one file, with the `-p` line
above and three prompts — the tool names, the tools the reader must not have,
and a read outside the directory:

```text
$ claude -p --restricted --tools Read --strict-mcp-config --model haiku 'List the names of every tool you can call, one per line, nothing else. …'
Read
$ claude -p --restricted --tools Read --strict-mcp-config --model haiku 'Run `git status` and `gh pr list`, then fetch https://example.com. For each, report in one line whether you could, and by which tool. …'
I don't have shell execution tools available in my current environment—only the Read tool for reading files. I cannot run `git status`, `gh pr list`, or fetch URLs. …
$ claude -p --restricted --tools Read --strict-mcp-config --model haiku 'Read ./one, then read /etc/hostname. For each, one line: the contents, or the error the tool returned, verbatim. …'
alpha beta
/etc/hostname is outside /tmp/…/358-probe.EBvjNu; --restricted confines the file tools to the working directory.
```

A reader dispatched through `scripts/agent-dispatch.sh` is on this path too,
with one thing to know: the dispatcher runs the command template you wrote,
`AGENT_HARNESS_<TOKEN>_CMD`, with `{model_flag}` and `{prompt_file}` filled,
from the caller's own directory, and writes no flag of its own — the script's
header says the autonomy flags "are yours to choose". So the three flags above
belong in that template, and a reader's template needs the working directory
to be the scratch directory — `--add-dir` reaches it too, but leaves the
caller's directory in reach beside it. An agent harness token the reader's
tier alone maps to is the shape that fits: the template that runs implementers
needs `Bash`, so it cannot carry `--tools Read`. The kit ships no template, as
it ships no mapping.

### The in-session path — a request

Inside a session, a skill spawns through the `Agent` tool, and that call has no
tool list: a prompt, a type, an optional model, and nothing that withholds. A
subagent's tools come from its type's definition, and the types a plain
session offers for a read both hold `Bash`: the general-purpose type holds
every tool, and the read-only `Explore` type drops the write tools and keeps
the shell. So "read this file and nothing else: no shell, no forge CLI, no
network" written into the prompt is a **request, not a restriction**: a
reader that honours it is well behaved, and a line injected into the file it
reads can ask it to do otherwise with a shell to hand.

So the recommended in-session path is the CLI one: **spawn the reader with the
CLI from inside the session.** A session holds a shell, the `-p` line above
runs under it, and the restriction is then real whichever path the skill
started on — the same three flags, from `$scratch`, with the return in the
file the skill names. The **prompt-only spawn is the fallback**, for a
session that cannot run the CLI — no `claude` on the path, or a shell it was
not given — and it keeps the duty the three skills already provide for: where
yours cannot, say so at the quiz (`/to-tickets`) or say so in the report
(`/pr-iterate` and the dogfood skill). Say what fenced the read — for
example, that the reader was tool-restricted by prompt alone — so the human
reading the quiz or the report knows: the return's shape check and the
vocabulary check, which do not weaken (a return that fails them is still
refused unread), and not an absent tool. What the prompt cannot do is take the
shell away for the length of the read.

A project can author an agent type of its own under `.claude/agents/`, whose
definition names the tools it holds, and spawn the reader as that type; the
kit ships none, and the list at the end of this note says why.

## Wiring the session hooks

The other half of this adapter is `hooks/`, and it answers a different
question: **what did that session cost, and which model spent it?**
`scripts/trace.sh` records the chain's decisions but knows nothing about a
session — sessions belong to the agent harness, which is why these four files
live here rather than in the shared script (ADR-0008 clause 8).

| File | The event it records |
| --- | --- |
| `hooks/session-start.sh` | `session.start`, and the session identity every later emit joins on — with `data.behind`, how far the root checkout is behind `origin/main` |
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

### When node is managed per user

The extractor is the one part of this adapter with a runtime, so `node` has to
be on the path **the hooks run with** — the agent harness's own, not your
shell's. A node managed per user (a version manager that keeps it under your
home directory and puts it on the path from your shell's startup files) is on
every path you type at and on none of the hooks': every `session.usage` and
every `agent.stop` then records `outcome=fail` with a reason naming node, and a
session's cost goes unmeasured while nothing visibly breaks — the hooks exit 0,
as always. That reason points here.

The fix is policy, not code: put the directory on the path through the `env`
block of **`.claude/settings.local.json`** — the per-project settings file the
agent harness keeps for one person's overrides, and keeps uncommitted (it adds
the file to git's global excludes the first time it writes one; a file you
create by hand you add to `.gitignore` yourself).

```json
{
  "env": {
    "PATH": "<the directory your node lives in>:<the path the hooks had before>"
  }
}
```

`dirname "$(command -v node)"` in your own shell prints the first half. Three
things about the entry:

- **The value is literal and whole** — checked against a live hook, not read
  off a page. The agent harness expands nothing in it (`$HOME` arrives as five
  characters) and merges nothing: what you write is the entire path. So write
  the directory out, and keep the directories the hooks already relied on
  after it.
- **It reaches the hooks** — the same probe — and, by the agent harness's own
  account, a settings `env` overrides the shell's exports for the whole
  session, the shell behind its command tool included. That is why the second
  half matters, and why this is the one place a path that is right on exactly
  one machine belongs.
- **It is one person's, and that is the whole rule.** A directory under one
  person's home is wrong on every other machine, which is why it never goes
  into the shared `.claude/settings.json` that wires the hooks, and never into
  a hook's own command line. The shared file says *which* hooks run; the
  personal one says *where* their runtime is.

### And the tool hook, behind its own switch

Every tool call can be captured too, as one `tool.use` event carrying the tool's
name, the call's id, the first 512 bytes of its input on the line, and the FULL
input and FULL result in the blob store with the result's size — each stored
by `sh scripts/trace.sh blob`, which prints the name the event carries, so the
adapter keeps no store of its own. Two more events
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
- **It never uses `hook_field` on a tool payload.** Every live payload arrives
  compact, as one line of JSON, so a key-name search finds the LAST occurrence
  — harmless for the session payloads, whose keys occur once, but a tool
  payload nests arbitrary objects, and a tool result can carry `"session_id"`
  or `"tool_response"` as keys of its own. The payload goes through a real
  parser, which reads only top-level keys.

Five details found by watching this run, each of which costs a wrong number if
you get it wrong:

- **A streamed response is written more than once.** One assistant API response
  with two content blocks is two lines of the transcript, repeating the same
  `message.id`. Summing lines over-counts; de-duplicating by `message.id`
  reproduces the agent harness's own per-model rollup exactly — taking the
  **last** usage block per id, because the blocks are not always identical: a
  response that opens with a thinking block is written first with a partial
  usage snapshot and then with the final one (#343). Only `output_tokens`
  may differ, and only by growing; a later block that shrinks it, or changes
  the input or cache counts, is still drift.
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

One race, observed in a live session rather than in a fixture: **the
subagent-stop hook can run before the subagent's transcript has its final
assistant line.** Read then, the file holds no usage at all or, worse, the
turns before the last one, which sum to an undercount that looks like success.
Two of seven live stops lost that race by 170 and 223 ms. The hook can wait for
it: `TRACE_AGENT_WAIT_MS` in your trace policy file is how many milliseconds
it may poll for the transcript to end on a final message. When the final
message lands in time, `agent.stop` carries the tokens and `data.waited_ms`.
When the bound passes first, it records `outcome=fail` with no counts and the
wait it gave, plus what the file can say of why: `data.last_kind` (the last
line's `type`), `data.last_age_ms` (that line's age when the bound passed) and
`data.lines`. A young last line means the bound is too short for an agent still
writing; an old one, an agent that never wrote a final message. A malformed value is refused on stderr and as
`data.wait_refused`, and is never waited. The policy file ships the value
empty, which means no wait and the read-at-once behaviour, partial sum
included. A session's own
`session.usage` is unaffected either way, and the "usage plus agent.stop equals
the rollup" identity holds only for the stops whose file was ready.

**The session-start hook says how stale its own code is.** A hook runs the
code of the checkout it lives in, so a checkout that has fallen behind main
runs hooks main has already fixed, and nothing else says so (ticket #384).
Every `session.start` therefore carries `data.behind`: how many commits the
last FETCHED `origin/main` holds that the ROOT checkout's `HEAD` does not —
the working tree of git's common directory, so a session opened in a linked
worktree measures the root, never its own feature branch, and says so with
`data.behind_of=root` — counted with plain git and never a fetch of its own,
`0` when level. A checkout with
no `origin/main`, or no repository, records no field and still exits 0.
`TRACE_BEHIND_WARN` in your trace policy file adds one line on stderr when the
count is more than it; the policy file ships it empty, which records the count
and says nothing. A malformed value is refused on stderr and otherwise
ignored.

**A phantom stop writes no event.** Most `SubagentStop` payloads in a long
session name a subagent transcript that does not exist and never appears:
1,418 of 1,614 stops in one window of the kit's own trace, about one every 30
seconds, under agent ids no transcript holds. No subagent's work stands behind
one, so the hook neither waits for it nor records it (ticket #344). Two shapes
were weighed. One `agent.stop` with a new `outcome=phantom` and no tokens would
keep a count of them, but every rate `/retro` reads off the `agent.stop` count
would then carry them in its denominator, and the trace decision record would
need a dated amendment for a word only this hook writes. No event costs neither,
and the distinction it has to keep still holds: a transcript that **exists and
cannot be read** is a real stop whose usage is lost, recorded at once as
`agent.stop outcome=fail` with a reason saying so and naming the path — never
polled, since a file the hook cannot open never ends on a final message. A
payload that names no transcript at all is still recorded, as before.

**The phantom count survives on `session.end`.** No event per phantom still
leaves the question of how many there were, and a sudden rise is worth seeing
(ticket #410). So each phantom stop adds one line to a per-session counter,
`claude-code/<session id>.phantoms` in the trace directory — a directory this
adapter owns, never the shared script's `current/` — appended, so two stops
at once both count without a lock, and keyed by the payload's session id, so
two sessions never share one. The session-end hook takes that counter and
records it as `data.phantoms` on `session.end`. **A session with no phantom
stops records `phantoms=0`** rather than leaving the key out: `0` says the
count was taken and came to nothing, while an absent key keeps meaning the hook
could not take one — tracing off, a payload with no usable session id, or a
`session.end` written before the count existed. Taking the counter removes it,
so a resumed session's next end counts only the phantoms since the last one —
the same once-only rule the usage read keeps; `/retro` sums a session's ends.
A counter left by a session that never fires `SessionEnd` stays where it is
until an end for that session id takes it — a resumed session's next end
counts it — and is otherwise harmless.

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
- **No agent type for the reader.** The in-session path above is a request
  because the kit ships no `.claude/agents/` definition that would make it a
  restriction, and it will not: that file names a tool set, which is a
  consumer's decision in a consumer's file. The CLI flag is the one restriction
  this adapter can name without owning a file in your tree.
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
