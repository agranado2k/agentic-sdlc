# agent-forge-token.md — agent sessions on a token that cannot change the rules

For the operator, after setup. The default branch is guarded by rules on the
forge — a ruleset or branch protection, its required checks, its approval
gate. Those rules guard against agents only when the token an agent session
holds cannot change them. An agent session holding the operator's own admin
token once edited the default branch's ruleset, so the ruleset could not
guard itself.

This page is one documented way to close that gap: agent sessions run on a
**bot** token that the forge itself forbids from administering the
repository, and the operator's admin token stays where no agent process can
read it. The adapter's hook that refuses an agent's write to the branch rules
([The forge's branch rules](../adapters/claude-code/README.md#the-forges-branch-rules))
is an earlier tripwire in front of this lock, and it says so itself: the
guarantee is the token, not the hook.

The examples use GitHub and its CLI, `gh`, and 1Password and its CLI, `op`.
Every name in angle brackets is a placeholder for your own:
`<owner>/<repo>`, `<bot-login>`, `<agent-vault>`, `<bot-item>`,
`<personal-account>`, `<private-vault>`, `<admin-item>`,
`<service-account-token-file>`, `<agent-cli>`. Nothing on this page creates
an account, a token or a rule for you; each step is yours to take.

## 1. A bot identity

Create a separate forge account for the agents and add it to the repository
as a collaborator with the **Write role**. Write can push branches, open pull
requests and merge what the rules allow; it cannot administer the repository
— rulesets, branch protection, collaborators, secrets — and the forge
enforces that, whatever the agent tries. Give the bot a fine-grained token
scoped to this one repository; whatever permissions it lists, the Write role
caps what the token can do here.

Keep the bot off every bypass list in the ruleset. A bot that may bypass the
rules has the admin's reach back by another door.

Store the bot's token in a vault of its own — the **agent vault**,
`<agent-vault>` — and nothing else in it.

## 2. Agent sessions

Create a 1Password **service account** with read-only access to the agent
vault and no other vault. Save its token to `<service-account-token-file>`,
readable by your user only. That file may sit where an agent can read it: the
most it unlocks is the bot token the agent already holds.

The launcher reads the bot token through the service account and hands it to
the one command it starts, as `GH_TOKEN` — never through your shell profile,
where every terminal and every process would inherit it:

```sh
#!/bin/sh
# agent-session — run one command on the bot token.
set -eu
OP_SERVICE_ACCOUNT_TOKEN=$(cat '<service-account-token-file>')
export OP_SERVICE_ACCOUNT_TOKEN
bot_token=$(op read 'op://<agent-vault>/<bot-item>/token')
unset OP_SERVICE_ACCOUNT_TOKEN
GH_TOKEN=$bot_token exec "$@"
```

Start every agent session through it: `agent-session <agent-cli>`. The
service account's token never enters the agent's environment, so an `op`
call from inside the session falls back to your personal account — which
asks first (step 3).

Pushes take the same token only when git asks `gh` for its credentials: use
an HTTPS remote and run `gh auth setup-git` once. A remote that pushes over
SSH with your own key pushes as you, not as the bot.

## 3. Admin sessions

The admin token lives in your **personal** 1Password account, in
`<private-vault>`, behind the password manager's **system-authentication**
prompt (the desktop app's CLI integration: fingerprint, system password).
A second launcher reads it:

```sh
#!/bin/sh
# admin-session — run one command on the admin token, after the prompt.
set -eu
unset OP_SERVICE_ACCOUNT_TOKEN
admin_token=$(op read --account '<personal-account>' 'op://<private-vault>/<admin-item>/token')
GH_TOKEN=$admin_token exec "$@"
```

Know its limit. The prompt authorizes the **whole account**, not one item,
and every process in that terminal shares the authorization until it
expires — after about **ten idle minutes**. So an admin session runs in its
own terminal, never with an agent in it and never in an agent's auto mode,
and the terminal is closed after use. For most admin changes, prefer the
forge's web UI: it needs no token on the machine at all.

## 4. Remove the stored login

The forge CLI keeps a stored login of its own, and it answers whenever
`GH_TOKEN` is unset — so an agent that unsets the variable falls back to
whatever token you once logged in with. Remove it:

```sh
gh auth logout --hostname github.com
gh auth status
```

`gh auth status` outside the launchers should now report no account. From
here on, every `gh` call on this machine runs on a token a launcher handed it.

## 5. Require an approving review

Once pull requests are opened by the bot, add a pull request rule to the
default branch's ruleset that requires one approving review — in the web UI,
or with the `pull_request` rule's `required_approving_review_count` set to
`1`. The bot cannot approve its own pull request, so your approval becomes
part of every landing: the approval gate now stands between an agent and the
default branch, not only between a careless human and it.

## 6. Verify

From a **fresh** agent session started through `agent-session`, run each of
these. All four must hold before you rely on the setup.

1. **The token is the bot's.** `gh api user --jq .login` prints
   `<bot-login>`, and `gh api repos/<owner>/<repo> --jq .permissions.admin`
   prints `false`.
2. **A write to the ruleset is refused.** Inside an agent session the
   adapter's hook refuses this call before the forge sees it, which tests the
   hook, not the token — so run it through the launcher with no agent in
   between:

   ```sh
   agent-session gh api -X POST repos/<owner>/<repo>/rulesets -f name=token-probe
   ```

   The forge must answer 403 or 404. A 422 means the token got past the
   permission check and only the request's shape stopped it: the token can
   administer, so stop and fix step 1. The probe's body is deliberately
   incomplete; never probe with a body that would be a valid ruleset.
3. **The password manager answers nothing without a prompt.** `op vault list`
   lists nothing on its own: it raises the system-authentication prompt — deny
   it — and then fails. `printenv OP_SERVICE_ACCOUNT_TOKEN` prints nothing.
4. **The environment holds no admin token.**

   ```sh
   printenv | cut -d= -f1 | grep -E 'TOKEN|_PAT$'
   gh auth status
   ```

   The first names `GH_TOKEN` and no other forge or password-manager token
   (`GITHUB_TOKEN`, `OP_SERVICE_ACCOUNT_TOKEN`); the second reports one
   account, `<bot-login>`, from `GH_TOKEN`.

## What this does not stop

The agent still runs as your OS user. It can read every file your user can,
start any program your user can, and wait at a terminal for an admin session
you open beside it. Full isolation needs a container or a separate OS user
for the agent, with its own home directory and nothing of yours in it. This
page narrows what the agent's **forge token** can do; it does not make the
machine the agent runs on a boundary.
