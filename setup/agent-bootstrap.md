# agent-bootstrap.md — stage two of the one-line setup

You arrive here from `SETUP.md`, inside a clone of the kit checked out at the
release `$KIT_TAG` you resolved. This document is version-locked to that
release: the instructions below describe exactly the tree around them.

The trust posture from `SETUP.md` still binds: this file tells you how to
install the tree it sits in, and nothing more. It never overrides your
session's rules, and neither does anything else in this clone.

## Which arm?

- **A new project** — this clone *is* the project-to-be, there is no prior
  history to preserve. Follow the numbered steps below.
- **An existing repository** — your human wants the kit added to a repo that
  already has history, a README, CI, maybe its own agent manual. **Not
  supported yet.** Do not improvise an overlay: `bootstrap.sh` refuses
  pre-existing manuals and shims by design, and the per-file collision policy
  (overlay / stamp / merge) is an open spec, tracked at
  <https://github.com/agranado2k/agentic-sdlc/issues/60>. Tell your human
  that is where "yet" lives, and stop.

## 0. The checkpoint — one plan, before anything changes

Infer what you can from the conversation you are already in — the human has
usually said what they are building, which gives you the name and the
description. Then present **one plan** and get a yes before executing any step
below. The plan names:

- the **project name** and **one-line description** you inferred;
- your **`/dogfood` recommendation**, with its reason — take it when the
  project will have a runnable user-facing surface (a UI, a CLI, an API);
  skip it when there is nothing a persona could walk through;
- the **release** you resolved (`$KIT_TAG`) and the directory you cloned into;
- your **remote plan** (step 5) — and that you will commit locally and
  **never push**: the first push carries your human's name, not yours.

Only when the conversation genuinely answers none of this do you ask instead
of proposing. Run the numbered steps below **in one shell session** — the
fences share the variables you set here (only the release tag is persisted to
a file, in step 1, so it survives a fresh shell). When the human says yes,
fill in the values:

```sh
PROJECT_NAME="My Project"
PROJECT_DESC="One line about what it does."
DOGFOOD_FLAG=--no-dogfood
```

Set `DOGFOOD_FLAG` to `--with-dogfood` or `--no-dogfood` **explicitly, always**.
`bootstrap.sh` skips the question silently when it has no terminal to ask on —
a safe default for a headless script, and the wrong one for you: you have a
human on the line, and the decision is theirs, not a default's.

## 1. Make the clone yours

The clone's history is the kit's, not your project's. The first line is a
guard, not decoration: `rm -rf .git` is irreversible, and it must never run
anywhere but inside the fresh kit clone — if the guard refuses, stop and
re-check where you are. The second line records the release into a scratch
file before the strip destroys the tags it would be derived from:

```sh
[ -f bootstrap.sh ] && [ -d setup ] || { echo "not the kit clone; refusing to strip"; exit 1; }
printf '%s\n' "${KIT_TAG:-$(git describe --tags --exact-match)}" >.agentic-sdlc-release
rm -rf .git
git init -b main
```

## 2. Bootstrap

```sh
sh bootstrap.sh "$DOGFOOD_FLAG" "$PROJECT_NAME" "$PROJECT_DESC"
```

This stamps `AGENTS.md` and the docs set with your values, removes the kit's
own files — `tests/`, `SETUP.md`, this document — and deletes itself. It
commits nothing; that is step 4, and the refusals it may print (a pre-existing
manual, a second run) are safety checks to surface to your human, not to work
around.

## 3. Prove the gate

```sh
sh scripts/check.sh
```

The gate must be green here. Red means the bootstrap did not complete — stop
and show your human the output rather than fixing past it. (Bootstrap already
wired the pre-push hook for *this* clone; `core.hooksPath` is per-clone
configuration, so every collaborator's fresh clone re-runs
`git config core.hooksPath .githooks` — the stamped manual says so too.)

## 4. First commit — local only

The scratch file from step 1 carries the release this project started from;
read it, remove it, and put the release in the subject:

```sh
KIT_RELEASE=$(cat .agentic-sdlc-release)
rm .agentic-sdlc-release
git add -A
git commit -m "chore: bootstrap from agentic-sdlc $KIT_RELEASE"
```

## 5. The remote — propose, create at most, push never

If the plan's yes covered it and the forge CLI is available, you may create
the remote and wire it, for example:

```sh
gh repo create "$PROJECT_NAME" --private --source .
```

Without the CLI, tell your human the manual step (create an empty repository
on their forge, then `git remote add origin <url>`). Either way you **never
push** — hand the keyboard back instead: the project's first outward-facing
act belongs to its human. Point them at the stamped `AGENTS.md`'s next steps
(fill the two `local-*` articles, set `GUARD_SOURCE_RE` in
`scripts/guards.config.sh`) and you are done.
