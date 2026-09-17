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
# POLICY_FILE below is a placeholder — replace the whole word with a real path.
# It is written unquoted here only so this block reads; in your own config it is
# a literal path.
AGENT_HARNESS_GEMINI_CMD='gemini --skip-trust --policy POLICY_FILE {model_flag} < {prompt_file}'
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

## 1/3 — The prompt goes in on stdin, and that is all

Gemini reads a redirected prompt: `gemini < prompt.md` (no `-p`) sends it. The
dispatcher's own `< {prompt_file}` is exactly right, and it is what the wiring
above uses.

One shape does hang — `-p '' < file`, an *empty* `-p` with piped input, which
falls back to interactive mode and waits on a terminal that is not there. The
dispatcher never emits that shape, so do not write `-p` into the template at
all; let `< {prompt_file}` carry the prompt.

The first version of this note had it backwards, and the story is worth
keeping because it is a trap you might hit too. A real dispatch to Gemini *did*
hang — but the cause was the dispatcher letting the worker inherit its own open
stdin pipe (fixed in 0.19.0), not Gemini being unable to read a redirect.
"prompt does not arrive" and "process never returns" look identical from the
outside, and the second was the real one.

**If you get this wrong** by writing `-p ""`: the dispatch never returns.
Which is why the timeout below is not optional insurance.

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

## 3/3 — A headless tool call needs an approval policy, or it is silently withheld

This is the one that matters, and the one the kit will not decide for you.

Gemini gates tool calls on approvals, and headless there is nobody to approve.
What happens then depends on the mode, and it is not always a hang: in
`--approval-mode plan` a `run_shell_command` — `git diff`, say — is **withheld
and the run finishes**, so a reviewer told to read the diff itself does not
hang; it comes back having never read it. That is the quieter failure and the
worse one, because the review looks complete. Other modes can block instead.
Either way the worker did not do its job.

The answer is Gemini's **policy engine**: a `--policy <file>` allowing the
specific tool calls a worker legitimately needs and nothing else. For a
reviewer, that is read-only shell — `git diff`, `git log`, `git show` — and
nothing that writes. `--yolo` also proceeds, and approves *everything*, which
is not what you want a reviewer running with. What a policy file contains is
Gemini's own format and changes on Gemini's schedule; the CLI's documentation
is the source, and this note deliberately does not paste one, for the same
reason `scripts/agents.config.sh` names no model.

Whatever you allow, the worker prompts in `.agents/prompts/` still forbid push
and merge in words, because shared invariant §7 is not something a policy file
can enforce on a model's intentions — only on its hands.

**If you skip this:** in `plan` mode a fast, empty-handed review; in a mode
that blocks, a hang that `--timeout` turns into a 124 and a killed process
tree. Neither is a review.

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

`DISPATCHED` on stdout in well under the timeout means the prompt arrives and
the directory is trusted. A hang until 124 means the prompt shape is wrong
(check for a stray `-p`); a refusal on stderr means the trust flag is missing.
The approval policy (3/3) only bites once a worker tries a *tool*, so a
prompt that asks for one — "run `git log -1` and reply with the sha" — is the
test for that.

## Re-verification note

The three behaviours were observed live against gemini 0.60.0 on 2026-09-17,
and then re-checked in review, which corrected sections 1/3 and 3/3 above — an
earlier draft of this note had the stdin behaviour backwards and called the
plan-mode failure a hang. The rewrite could not itself be re-run end to end
because the account's daily model quota was exhausted at the time; a `--dry-run`
confirms the command expands correctly, and the `agent-dispatch` suite's own
`< {prompt_file}` case confirms the prompt reaches a worker on stdin. Read your
first real Gemini worker's output adversarially, and if a behaviour here does
not match what your version does, trust your version and fix this note.
