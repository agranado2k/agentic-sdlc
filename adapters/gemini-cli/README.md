# `gemini-cli/` — wiring a dispatched tier into one agent harness

`scripts/agent-dispatch.sh` turns a resolved (agent harness, model) pair into a
running worker and stops there. What it deliberately does not know is **how a
given agent CLI takes a prompt, trusts a directory, and approves a tool call**
headlessly — that is specific to the agent harness, it is the one part of a
dispatch that cannot be written portably, and it is why this note exists.

> Read this for the *shape*. If you dispatch to a different agent harness, the
> three questions to answer are the same ones below, and the answers belong in
> a sibling directory here, in your own repo. `claude-code/` is the note for
> the other half of the same feature — where a model id goes at *spawn* time
> rather than at dispatch.

Every detail here was found by dispatching to Gemini and watching it not
return. None of them is guessable from the dispatcher's own documentation, and
each one, skipped, produces a hang or a refusal rather than an error.

## The wiring, in four lines

```sh
AGENT_HARNESSES='gemini'
AGENT_HARNESS_GEMINI_CMD='gemini --skip-trust --policy <your policy file> {model_flag} -p "$(cat {prompt_file})"'
AGENT_HARNESS_GEMINI_MODEL_FLAG='-m {model}'
AGENT_TIER_REVIEWER='gemini:'
```

The last line names the agent harness and no model, which resolves to that
CLI's own default — its router picks. Name a model when you have a reason to;
the kit never suggests one, and neither does this note.

Then, before spending a token:

```sh
sh scripts/agent-dispatch.sh reviewer --prompt 'x' --dry-run
```

## 1/3 — The prompt goes in as an argument, not on stdin

Gemini does not read its prompt from stdin headlessly. Its `-p` flag says the
prompt is "appended to input on stdin (if any)" — but an *empty* `-p` falls
back to interactive mode and waits on a terminal that is not there. A template
written the way the dispatcher's own examples are, `< {prompt_file}`, hangs.

The command template is eval'd, and `{prompt_file}` arrives single-quoted and
whitelisted, so the wiring is:

```sh
-p "$(cat {prompt_file})"
```

**If you skip this:** the dispatch never returns. With `--timeout` it returns
124 after the timeout; without one, only an external kill ends it.

## 2/3 — The directory has to be trusted

Gemini refuses to run headless in a directory it does not trust:

```
Gemini CLI is not running in a trusted directory. To proceed, either use
`--skip-trust`, set the `GEMINI_CLI_TRUST_WORKSPACE=true` environment
variable, or trust this directory in interactive mode.
```

Three ways, and the choice is a security posture, not a convenience: trusting
a directory lets the CLI's tools act in it. `--skip-trust` in the template is
the explicit, per-dispatch form. Trusting the directory once interactively is
the durable one. The environment variable is the one that follows you into
places you did not mean.

**If you skip this:** an immediate refusal, exit non-zero, with the message
above on stderr — the one failure in this note that is loud.

## 3/3 — A headless tool call needs an approval policy

This is the one that matters, and the one the kit will not decide for you.

Gemini gates tool calls on approvals. In `--approval-mode plan` (read-only)
and `auto_edit`, a `run_shell_command` — `git diff`, say — **blocks until a
human approves it.** Headless, there is no human. A reviewer told to read the
diff itself waits forever. Only `--yolo` proceeds, and `--yolo` approves
*everything*, which is not what you want a reviewer running with.

The narrow answer is Gemini's **policy engine**: a `--policy <file>` allowing
the specific tool calls a worker legitimately needs and nothing else. For a
reviewer, that is read-only shell — `git diff`, `git log`, `git show` — and
nothing that writes. What such a file contains is Gemini's own format and
changes on Gemini's schedule; the CLI's documentation is the source, and this
note deliberately does not paste one, for the same reason
`scripts/agents.config.sh` names no model.

Whatever you allow, the worker prompts in `.agents/prompts/` still forbid push
and merge in words, because shared invariant §7 is not something a policy
file can enforce on a model's intentions — only on its hands.

**If you skip this:** the dispatch hangs on the first tool call. With
`--timeout` on the dispatch it returns 124 after the timeout, and the worker's
process tree is killed. Without one, forever.

## What this adapter deliberately does NOT contain

- **No model identifier.** Not here either. `AGENT_TIER_REVIEWER='gemini:'`
  in the example is the point: the router chooses, and when you choose, you
  choose from what your account offers today.
- **No policy file.** Its format is Gemini's and rots on Gemini's schedule.
- **No executable file.** Nothing under `adapters/` is on an execution path
  (see [`../README.md`](../README.md)); this is read by a human wiring the
  kit up.
- **No claim that the constitution is obeyed.** The kit ships `GEMINI.md` as
  a shim importing `AGENTS.md`, and that import was confirmed to resolve by the
  CLI's own import algorithm; a probe on 2026-09-17 had Gemini answer four of
  five questions about this repo's rules precisely from it. That is delivery,
  and strong evidence of obedience, and not a guarantee. Read a worker's first
  outputs adversarially.

## Verifying it once

```sh
sh scripts/agent-dispatch.sh reviewer --prompt 'Reply with exactly DISPATCHED.' --timeout 120
```

`DISPATCHED` on stdout in well under the timeout means all three details are
right. A hang until 124 means one of the first or third is wrong; a refusal
on stderr means the second.
