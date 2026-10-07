# `claude-code/` — wiring one agent harness into the kit

Three questions the portable core cannot answer, because each is this agent
harness's own: **where does a resolved capability tier go at spawn time**,
**how is a typed-return reader denied a shell, a forge CLI and the network**,
and **how does a session's token usage reach the decision trace**. The first
two are prose about a mechanism; the third ("Wiring the session hooks") points
at real files under `hooks/`, which ship and arrive inert. One more file there
answers no question of the core's but a rule of the manual's: "Refusing an
edit at the root checkout" wires the guard that holds hard rule 1 for an agent.

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

## One agent type per tier

A spawn that names no agent type gets the harness's catch-all type, which
carries every tool the session has. [`agents/`](agents/) holds four types
instead, one per capability tier, each named with the tier's own word — so
the spawn's agent-type parameter takes the tier you already resolved, and the
`model` parameter takes the resolver's answer exactly as above. **A type
declares tools and never a model**: the model stays a spawn-time answer
(ADR-0003, ADR-0013's ordered fallback), and a `model:` line in a type would
be a second mapping, unrecorded, that outranks the policy file. The docs gate
fails one that carries a model line or anything shaped like a model id
(`agent-type-model`, a POSIX check in `scripts/check.sh`).

| Tier | Tools | Why these and no others |
| ---- | ----- | ----------------------- |
| `planner` | Read, Grep, Glob, Bash, Edit, Write, Skill, Agent | Writes specs, tickets and records (files and the forge CLI through the shell), runs the chain's skills, and fans out to subagents. No web tools: research is an untrusted read, and the trust boundary sends that to a tool-restricted subagent, never to the session that also writes. |
| `implementer` | Read, Grep, Glob, Bash, Edit, Write, Skill, Agent | Builds a ticket test-first and delivers it: edits, runs the suite, pushes and opens the PR through the shell, and spawns its independent reviewer. No web tools, for the planner's reason. |
| `mechanical` | Read, Grep, Glob, Bash, Edit, Write, Skill | The implementer's hands without its fan-out: a mechanical change is held to one oracle command, and its caller (the skill dispatcher's cascade, a fan-out) decides what runs next. No Agent, because a spawn from inside mechanical work is a design call the tier is not sized for; no web tools. |
| `reviewer` | Read, Grep, Glob | Reads a diff and a spec — untrusted content — and judges them. Nothing that writes a file, reaches the network, calls a tool server or spawns an agent that could: that rules out Bash, which is all three, so the spawner hands the diff and the ticket as files to read, and posts the report itself (the offline worker of ADR-0009, in-session). No Skill either: a lens receives its own instructions in its prompt. |

Two consequences worth knowing before you wire them:

- **They arrive dormant.** Claude Code reads agent types from `.claude/agents/`;
  nothing the kit stamps puts them there. Link or copy the four files in when
  your skills start spawning by type — the chain's own spawns move onto them in
  a later release.
- **A tool list is the whole list.** A type with no `tools:` line inherits
  every tool, which is the catch-all again; and a tool server's tools are only
  reachable when listed by name, which is why none of these lists one.

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

### The restricted path — a restriction

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

So the recommended in-session path is the restricted path: **spawn the reader
with the CLI from inside the session.** A session holds a shell, the `-p` line
above runs under it, and the restriction is then real whichever path the skill
started on — the same three flags, from `$scratch`, with the return in the
file the skill names. The **prompt-only spawn is the fallback**, for a
session that cannot run the CLI — no `claude` on the path, or a shell it was
not given — and it keeps the duty the three skills already provide for:
say so at the quiz (`/to-tickets`) or say so in the report
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
live here rather than in the shared script (the kit's ADR-0008 clause 8).

| File | The event it records |
| --- | --- |
| `hooks/session-start.sh` | `session.start`, and the session identity every later emit joins on — with `data.behind`, how far the root checkout is behind `origin/main` |
| `hooks/session-end.sh` | one `session.usage` per model with four token counts — only what is new since this session's last one — then `session.end`, each carrying the run handed over at spawn when the session's own prompt opens on a `Trace-Run: <run id> [<parent run id>]` line (#474), with that parent, the run the shared script resolves otherwise; the denials it sweeps (`tool.use` `outcome=denied`) never carry the handed run — their marker names no agent — and resolve as the shared script does. Precedence, as in every row here: a `TRACE_RUN` already in the environment, then the run handed over, then the fallback |
| `hooks/subagent-stop.sh` | `agent.stop` for one subagent, with its id, its type and its own tokens — and the run handed over at spawn: its spawn prompt's first line, `Trace-Run: <run id> [<parent run id>]`, nothing else on it and each id held to the run id's shape, read back from the first 4096 bytes of the first user record of the subagent's own transcript, with that parent (empty when the line names none) (#474; the payload's `cwd` is the session's, not the subagent's — #478). With none handed, the run open in the checkout the payload's `cwd` names (a linked worktree's, not the root's; the hook's own working directory when the payload names no `cwd`) on that session's stack (the payload's `session_id` keys it, as `scripts/trace.sh` does; the per-toplevel stack when it names none — #453), read through `sh scripts/trace.sh stack <dir> [session=<id>]` so the adapter keeps no copy of the stack's format (#472), with its parent from the same checkout's stack; a checkout with no run open makes a stop that carries no run, never the root's; the root's run when that `cwd` is in no checkout of this repository; a `TRACE_RUN` already in the environment wins, with its parent; a `TRACE_PARENT` alone is kept; that `cwd` itself recorded as `data.cwd`, the expanded value the run was resolved against (a leading `~` read as the home directory) — `session.start` records the raw one — and absent when the payload names none, never the hook's own working directory (#478); how the run ended, `data.final`, `message` or `tool` — a turn-ending tool's result is final (#565) — and each model counted past this agent's own last `data.last_msg`, so a second stop never re-counts the first (#565); and `data.out_snapshot` when some of the messages it counted carry a streamed output snapshot — how many, its `tok_out` a lower bound (#608); and what the spawn served, from the prompt's second line under that one, exactly `Trace-Spawn: tier=<tier> domain=<domain|none> skill=<skill> ticket=<#N|none>` — the tier one of the four, a domain and a skill `[a-z][a-z0-9-]*` of 32 characters at most, a ticket `#` and up to six digits — written into the event's `tier`, `domain` and `skill` columns with the ticket a `related` subject, from the same bounded read; no such line, or one that does not match exactly, records tier `unattributed`, a row `summary --by tier` shows (#583) |
| `hooks/tool-post.sh` | `tool.use` for one tool call — behind its own switch, see below — carrying the run handed over at spawn (`Trace-Run: <run id> [<parent run id>]`, with that parent) to the agent that made the call: the subagent the payload's `agent_id` names, read from its own transcript, or the session itself (#474); the run the shared script resolves when none was handed, never the run handed to its session for a subagent handed none — once the payload is read: a `tool.use` `outcome=fail` written before then (no scratch, no node, a payload the reader refuses) resolves as the shared script does |
| `hooks/tool-pre.sh` | no event: the pending marker a tool call leaves until it returns, swept by the session-end hook into `tool.use` `outcome=denied` when it never does — behind the same switch |
| `hooks/tool-pre-guard.sh` | a guard, not a recorder: refuses a spawned sub-agent's Bash call that signals processes by name, and leaves one `note` — see "The kill guard" below |
| `hooks/transcript-usage.mjs` | not a hook: the extractor the two usage hooks call |
| `hooks/tool-payload.mjs` | not a hook either: the reader `tool-post.sh` and `tool-pre.sh` split a payload with |
| `hooks/hook.lib.sh` | not a hook either: what the six share |

**They are dormant until a settings file names them.** Three properties make
that safe to leave in your tree: every hook exits 0 whatever happens, none of
them writes to stdout but the behind note's one object, and each sets the trace's quiet variable so a project
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
adapter keeps no store of its own. Three more events
wire it: the two post-tool events to the same script — the only difference
between them is the outcome it records — and `PreToolUse` to the marker a
denied call leaves behind (below):

```json
{
  "hooks": {
    "PreToolUse": [ { "hooks": [ { "type": "command",
      "command": "sh \"$CLAUDE_PROJECT_DIR/adapters/claude-code/hooks/tool-pre.sh\"" } ] } ],
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

**A denied call is swept, not seen.** A tool call the permission system
refuses — or a blocking `PreToolUse` hook such as the kill guard below — fires
`PreToolUse` **only**: no `PostToolUse` and no `PostToolUseFailure`, and that
payload is handed to the hook *before* the decision, so nothing on it says the
call was denied. So `hooks/tool-pre.sh` leaves a pending marker per call,
`claude-code/<session id>.pending/<tool-use id>` in the trace directory — the
directory the phantom counters live in, each marker owner-only, holding the
tool's name and the input head — and writes no event; `tool-post.sh` removes the call's
marker when it returns, whatever it then records. At the session's end, **each
marker left is swept into one `tool.use` with `outcome=denied`**, the tool's
name and the input head on it, before `session.end` (ticket #409). Swept per
session, never across: another session's marker may be a call still running.
A marker whose session never fires `SessionEnd` stays on disk until an end for
that session id sweeps it. An *interrupted* call is not a denial: it reaches
`PostToolUseFailure` and reads as `fail`. The marker is behind `TRACE_TOOLS`
as well, because only a post-tool hook that runs can remove it — with capture
off, every call would read as denied — and without node there is no marker,
because the post-tool hook could not read the id that removes it.

Two things the post-tool hook deliberately does not do:

- **It writes no event at `PreToolUse`.** Both post payloads carry the whole
  `tool_input` themselves, so the pre hook has nothing to add to the event;
  its marker is only the evidence that a call began. (The root guard below is
  one more `PreToolUse` hook, and records nothing.)
- **It never reads an event's fields with `hook_field` on a tool payload.**
  One best-effort use is not a field of the event: when the reader refuses a
  post payload, the call still returned, so its pending marker is dropped by
  the ids `hook_field` finds — held to the marker's identifier class, so a
  wrong answer leaves a marker behind and is never a path. Every live payload arrives
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
- **A subagent's output count is often a snapshot nothing closes** (ticket
  #608). A subagent's transcript writes each assistant line as its content
  block closes — before the response's closing usage arrives — and never
  rewrites it: a message whose last line says `stop_reason: null` carries the
  output streamed so far (never more than 182 in those measured), and no later line, usage
  record or other field holds the closing count. On CLI 2.1.287, 4,988 of
  5,585 subagent messages ended so; the session's own transcript writes its
  lines after the response closes. The count cannot be read, so it is
  flagged: an event whose messages include such snapshots carries
  `data.out_snapshot`, how many, and its `tok_out` is a lower bound —
  input and cache counts are whole. On a compaction gap the same key says
  the gap's `tok_out` holds those messages' remainder, which the rollup
  counts and their own events cannot: so "usage plus agent.stop equals the
  rollup" holds for output only where a gap was judged.
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
  therefore says how far it read for its model (`data.last_msg`, that model's
  last message, and `data.msgs`, its message count), and the next end of that
  session counts each model only after the last anchor the trace holds for
  that model — a model with none is read from the start. One anchor per model
  because the events are written one per model: an end killed after the first
  of them leaves the others to the next end rather than skipping them (#408). The events stay a plain sum: `summary`, the export
  and the query below need no rule about which event supersedes which. A
  compaction appends to the same file too, but the call that writes its summary
  leaves no assistant line, so its tokens are in the rollup and in no message.
  The session-end hook therefore reads the rollup beside the messages and
  records the difference, per model, as one more `session.usage` event with
  `data.via=rollup` and `data.reason=compaction` and no `data.last_msg` — so
  the plain sum of the events is the rollup (#407). It judges the rollup only
  in a file that holds a compact boundary, whose last rollup line follows its
  last message and that is not a fork; the subagents' own files and any gap an
  earlier end recorded are taken off first. A rollup smaller than what the
  events already hold records the messages as usual plus one `outcome=fail`,
  `data.via=rollup` event saying why no gap was recorded.
- **Cost is not recorded.** That same rollup carries the vendor's own cost
  figure and the extractor deliberately ignores it: a price is an
  interpretation that rots on the vendor's schedule, so the trace keeps token
  counts and prices them on read, from a table you own (the kit's ADR-0008 clause 6).

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
writing; an old one, a run that ended in a shape the hook does not read as final (see below). A malformed value is refused on stderr and as
`data.wait_refused`, and is never waited. The policy file ships the value
empty, which means no wait and the read-at-once behaviour, partial sum
included. A session's own
`session.usage` is unaffected either way, and the "usage plus agent.stop equals
the rollup" identity holds only for the stops whose file was ready.

**A run ends on a final message or on a turn-ending tool** (ticket #565).
Most subagent runs end on the agent harness's hand-back tool: its result is a
user line carrying `"toolEndsTurn":true`, and no assistant line follows it,
ever — so a wait for one gave up at any bound, 222 of 257 give-ups in the
window #565 measured. The hook reads that line as final, and every priced stop
says how the run ended in `data.final`: `message`, or `tool` — whose last
message was written mid-stream, so its usage block is the streamed snapshot.
**An agent can stop more than once** (an end, a prompt from the harness, a
hand-back), and every stop reads the same file: so a stop counts each model
only after the last `data.last_msg` this agent's own earlier `agent.stop`
events hold, exactly as `session.usage` reads a resumed session. A stop that
gave up holds no anchor, so the next one counts what it could not.

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
`TRACE_BEHIND_WARN` in your trace policy file adds a note when the count is
more than it; the policy file ships it empty, which records the count and says
nothing. A malformed value is refused on stderr and otherwise ignored.

**The note leaves by stdout, as one JSON object, because stderr reaches nobody**
(ticket #427). The note began as a stderr line, and a live probe of the agent
harness at 2.1.285 found a `SessionStart` hook's stderr on exit 0 kept in the
transcript's own records and shown nowhere — not in an interactive terminal,
not on a non-interactive run's stdout or stderr. The hooks reference documents
three other routes; the probe settled which reaches a reader:

| Route | Who reads it | Chosen |
| --- | --- | --- |
| a top-level `systemMessage` in a JSON object on stdout | the operator: documented as shown to the user, and an interactive session prints it under its banner | yes |
| `hookSpecificOutput.additionalContext` in the same object | the model, which relays it — the one route into a non-interactive run's output | yes, beside it |
| plain stdout | the model only, and it would make the object unparseable | no |
| a non-zero, non-2 exit status | whoever the agent harness shows a failure to — and it would break rule 1, exit 0 always (the kit's ADR-0008 clause 4) | no |

So past the threshold the hook prints exactly one object carrying the note in
both fields, still exits 0, and still writes the stderr line for a reader of the
agent harness's records. Under the threshold, and on every other path, stdout
stays empty: nothing about the trace ever takes this route, and `hook.lib.sh`'s
rule 2 names this one object as its only exception.

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

### The kill guard: a sub-agent signals only what it started

Parallel sessions run the same suites on one machine, so a process matched by
name is as likely a sibling's run as one's own — during PR #393's review a
sub-agent ran `pkill -f` on two suite names (#414). `hooks/tool-pre-guard.sh`
is a PreToolUse hook that refuses, for a **spawned sub-agent** only, a Bash
command that signals by name: `pkill`, `killall`, `kill` alongside `pgrep`, or
`kill` handed a word that is not a pid, a job or an expansion. `kill %1`,
`kill $!` and `kill <pid>` pass, and so does everything the operator's own
session runs. A refusal exits 2 — the agent harness's block status, the one
non-zero exit any hook here makes — with the rule, `kill-guard`, named on
stderr, and records one `note` with `outcome=denied` on the session, naming
the rule. With tool capture on, the refused call is also swept at the
session's end into a `tool.use` with `outcome=denied` of its own (#409).

```json
{
  "hooks": {
    "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command",
      "command": "sh \"$CLAUDE_PROJECT_DIR/adapters/claude-code/hooks/tool-pre-guard.sh\"" } ] } ]
  }
}
```

**The marker is `agent_type` on the payload**, which the agent harness sets on
a sub-agent's tool calls and never on the main session's. It is wider than
"a review", deliberately: a review's agents are spawned through the Agent tool
with a general type, so no payload field names a review; an environment
variable cannot be set per in-session sub-agent, because they share the
session's process; and a prompt marker would mean reading the sub-agent's
transcript on every Bash call. Every spawned sub-agent shares the hazard, so
every one is held to it.

**A scan, not a sandbox.** It reads the command's words outside quotes, so
`sh -c '…'`, `eval`, a script written and then run, or a pid list built from
`ps` walks past it; negative pids and process groups are not read either.
It errs closed the other way too: a heredoc's body is read as commands, so a
sub-agent writing a script with a line that starts with `pkill` is refused.
Without node it fails closed for a sub-agent: a payload naming `pkill`,
`killall` or `pgrep` anywhere is refused unread.
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

## Refusing an edit at the root checkout

The manual's first hard rule is "Worktree, always": the root checkout is never
where in-progress work is edited. Git has no hook for an edit, so the rule is
held twice. `.githooks/pre-commit` refuses an agent's commit from the main
working copy or on the default branch; `hooks/root-guard.sh` refuses the edit
itself, before the tool runs. Of the two, the pre-tool hook is the one that
refuses: git lets any committer skip a hook, so the commit hook is a guard a
cooperative agent meets, and the pre-tool hook is what refuses the ways around
it. Wire it to `PreToolUse` in your own `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [ { "matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash", "hooks": [ { "type": "command",
      "command": "sh \"$CLAUDE_PROJECT_DIR/adapters/claude-code/hooks/root-guard.sh\"" } ] } ]
  }
}
```

It reads the tool payload, resolves the target path against the repository's
**main** working tree — found through git's common directory, so a session
started inside a worktree still guards the right tree — and answers in the
agent harness's own terms: exit 2 blocks the call and its one-line reason,
naming hard rule 1 and the `git worktree add` line to run instead, reaches the
model on stderr; exit 0 lets the call through. Nothing goes to stdout.

- **Where the line is:** the line the commit hook draws, by the same test. Git
  answers for the checkout that holds the path: a linked worktree (its own git
  directory is not the common one) on any branch but the default — the branch
  `origin/HEAD` names, or `main` where there is none — is open, and the main
  working copy is not, whatever its branch. So an agent may edit in any linked
  worktree, `worktree/<slug>` or one the agent harness cut for its own
  isolated sessions (this one cuts them under `.claude/worktrees/`), and the
  name of a directory never decides it.
- **Refused:** an Edit, Write, MultiEdit or notebook edit whose path is inside
  the main working copy — a directory under `worktree/` that no worktree
  checks out included — or inside a linked worktree on the default branch: a
  new file as much as an existing one, a relative path resolved against the
  session's directory, a `..` that climbs out of a worktree.
- **Let through:** paths in a linked worktree off the default branch, paths
  outside the repository (a dispatch's scratch lives under `$TMPDIR`), and the
  two runtime directories a session legitimately writes at the root, `.trace/`
  and `.retro/`.
- **It fails open.** A payload it cannot read, a tool it does not know or a
  root it cannot resolve lets the call through: a guard that blocked every
  call on a parse failure would end the session. The commit hook is no
  fail-closed backstop for that — a cooperative agent meets it, and nothing
  more. Unlike the trace hooks above it does exit non-zero — changing the
  session is its whole purpose — and records nothing.

### Which commits the commit hook refuses

`.githooks/pre-commit` refuses agents only. A commit is refused when one of
these variables is set, non-empty, in the committing environment, and the
commit comes from the main working copy or lands on the default branch (the
branch `origin/HEAD` names, or `main` where there is none). With none set, a
human commits as before — so a consumer following `UPDATING.md` by hand on
`main` is let through.

| Variable | Set by | Status |
| --- | --- | --- |
| `CLAUDECODE` | Claude Code, in the shell it runs commands in | verified on a live host |
| `CLAUDE_CODE_SESSION_ID` | Claude Code, the same shell | verified on a live host |
| `TRACE_SESSION` | the kit's trace layer, while a session is traced | verified on a live host |
| `GEMINI_CLI` | Gemini CLI, `1` in every shell command its tool runs | documented only — the CLI's own shell-tool documentation |
| `CODEX_SANDBOX` | Codex, in a command it runs sandboxed | documented only |
| `CODEX_SANDBOX_NETWORK_DISABLED` | Codex, in a sandboxed command with the network off | documented only |
| `CODEX_THREAD_ID` | Codex | found in the 0.159.0 CLI binary, not verified live |

A documented-only marker is the agent harness's own claim, not a run watched
here; an agent harness that sets none of them commits as a human would, and
only the pre-tool hook — where one is wired — still stands between it and the
root. The refusal names hard rule 1 and the manual's quick-reference row, and
never prints its own bypass: that lives in the hook's source and in the row,
where it is the operator's call.

### What Bash coverage it does not give

For Bash it is a tripwire, not a proof. It reads the command roughly as a
shell would — quotes dropped, heredoc bodies skipped, continuation lines
joined, `env`, `sudo` and `VAR=` prefixes stripped, `cd` (and `git -C`)
followed between simple commands — and refuses one that redirects into, or
runs `sed -i`, `tee`, `cp` (onto) or `mv` on, a path that resolves to a
**tracked** file at the root, a symlink to one included. It also refuses `mv`
of a directory holding tracked files, and `git checkout` or `git restore` on
a tracked file, a directory holding one, or `.` (`git restore --staged` alone
touches only the index and passes). Where git acts at the root — the main
working copy, or a linked worktree on the default branch, the edit's line
above — it refuses the
discards of working changes — `git stash` (bare, `push` or `save`), `git reset
--hard` and `git clean -f` — the incident that asked for this guard, and the
three ways around the commit hook: `git commit --no-verify` (or `-n`, read
letter by letter, so the `n` of `-uno` is `-u`'s), `git -c
core.hooksPath=…`, and setting or unsetting `core.hooksPath` with `git
config`. Everything else goes through: a script or an interpreter that writes
(`sh tests/x.sh`, `node -e …`), `rm`, a path spelled through a variable or a
glob it never expands, a `cd` inside a subshell or a function, and any write
to an untracked file. The commit hook is what an agent meets next — a change
this let through is still refused at the commit from the root, for an agent
that keeps its marker and its hooks.

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
  restriction, and it will not: a file there names a tool set in a consumer's
  own tree. The tier types above are reference files under `agents/`, wired
  only by you. The CLI flag is the one restriction this adapter can name
  without owning a file in your tree.
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
