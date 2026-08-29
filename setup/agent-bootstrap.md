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
  already has history, a README, CI, maybe its own agent manual. This clone
  then becomes a **scratch kit directory**, not the project: skip the
  numbered steps below and follow **"The existing-repository arm"** at the
  bottom of this document. Do not improvise an overlay by hand — the arm's
  per-file collision policy was decided on the record, at
  <https://github.com/agranado2k/agentic-sdlc/issues/81>.

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
`scripts/guards.config.sh`) and you are done. One of those article lines is
the **mutation decision**, and it is a decision, not a blank: whoever fills
the engineering article — you, if asked — names a tool and its on-demand
command, or writes `none` with the reason, and surfaces the choice to your
human either way. Filling it with silence is how a project ships tests
nobody has ever measured.

## The existing-repository arm

Everything above assumed an empty future. Here the repo already exists —
history, CI, maybe its own agent manual — and this clone is only the **scratch
kit directory** the adopt run reads from. The split of labor is fixed:
`bootstrap.sh --adopt` does what a script is good at (classify every kit file,
install the non-colliding set, report each conflict as one machine-readable
line, resolve nothing), and you do what only you can — propose a resolution
for each conflict and get your human's explicit yes, **one at a time**. The
same trust posture binds, and one more rule joins it: you **never push** from
this flow, and the adoption branch's merge carries your human's name.

### E0. The checkpoint — one plan for the batch, doors handled separately

Infer the project name and one-line description as in §0, and make the
dogfood decision explicit the same way. Then present one plan and get a yes
before anything changes. The plan says exactly this: adoption happens on a
dedicated branch; the non-colliding kit files install in **one approved
batch**; every collision comes back to your human **individually** — nothing
that already exists in their repo is touched without a yes on that specific
file.

### E1. The branch, then the batch

Fill these in first — `KIT_CLONE` is this clone's absolute path:

```sh
KIT_CLONE=/absolute/path/to/this/clone
PROJECT_NAME=my-project
PROJECT_DESC="One line about the project."
DOGFOOD_FLAG=--no-dogfood
```

From inside your human's repository:

```sh
git switch -c chore/adopt-kit
```

```sh
sh "$KIT_CLONE/bootstrap.sh" --adopt "$DOGFOOD_FLAG" "$PROJECT_NAME" "$PROJECT_DESC"
```

Read the result as data. **Exit code 0**: nothing collided — the adoption
completed in one pass; commit and skip to E4. **Exit code 3**: the safe set
is installed and each remaining conflict printed one line of the form
`COLLISION <class> <path> <verb>` — those are the doors, and the run resolved
none of them. Lines that begin `kept` are not doors: project memory (their
diary, their decision records, their README) is never overwritten, full stop.
Commit the batch before opening any door — and look at `git status` first:
`git add -A` stages *everything*, including stray untracked files the repo
was already carrying; if there are any, stage the installed paths instead so
the adoption branch stays only the adoption:

```sh
git add -A
git commit -m "chore: adopt agentic-sdlc — the non-colliding set"
```

### E2. One door at a time

For **each** `COLLISION` line: read the file, propose one concrete
resolution, get your human's yes, apply it, and commit it as its own commit
naming the door. Never batch two doors into one approval. The verb tells you
the shape of the proposal:

- **`relocate`** (a file of theirs at a shared-layer path): propose a new
  name or home for *their* file; the kit's copy arrives byte-verbatim on the
  re-run. Never merge the two — the shared layer's whole update model is
  byte-identity.
- **`distill`** (their agent manual, or a tool file beside it): the marquee
  door. Read their manual as a set of rules. Propose a mapping of each rule
  into the `local-*` articles the kit just installed as templates — their
  engineering rules into the engineering article, their process rules into
  the workflow article — then fill those templates and drop the `.template`
  suffix. The stamped kit manual becomes the root; their rules survive as the
  articles it points at; their original file is removed **only after** the
  distillation commit exists, which preserves it verbatim in history forever.
  Never splice their rules into a shared article.
- **`rename-or-decline`** (a skill of theirs under a kit skill's name): two
  real resolutions, and only one of them is direct. **Rename theirs** — it
  moves, the kit's copy arrives on the re-run, done. **Decline the kit's** —
  adopt mode has no mechanical way to see a decline (its door closes only on
  an absent path or the kit's own bytes), so the flow is rename-for-the-
  duration: move theirs aside in one commit, let the clean run land the
  kit's copy, then **swap back** in a final commit — delete the kit's copy,
  restore your human's skill at the name, and remove the kit's
  quick-reference row for it from the manual, because a row whose skill is
  not the kit's promise fails the gate as `skill-missing`, a violation, not
  an advisory. Cross-skill references to that name then resolve against
  *their* skill — confirm with your human that it can stand in for what the
  chain expects, and record the decline in a local article.
- **`chain`** (their pre-push hook, or a workflow name the kit also ships):
  propose keeping both — their hook moves aside, or the two workflows coexist
  under distinct names. Their automation keeps running exactly as before
  until they approve its door; the kit wires nothing until the final clean
  run. **The chaining itself happens after that run**: the installed
  pre-push hook is yours from the moment it lands (it is not shared layer),
  so once the run exits 0, edit it to invoke their renamed hook — editing it
  *before* the re-run just re-opens the door, because the classifier expects
  the kit's own bytes there.

A `kept` line may still deserve one **optional** proposal: seeding their
diary with the Current-state block protocol, or their decision records with
the index conventions — offered, approved, and committed like any door, or
skipped without consequence.

### E3. Re-run until clean

Run the same adopt fence from E1 again. Doors you resolved disappear; what
remains is what is still pending. When it exits 0 the run finishes the job —
manual stamped, shims written, hook wired — and retires the scratch clone's
bootstrap. Nothing is left to re-run: the clone can be deleted. That
finishing output is working-tree changes like any other; commit it, or the
branch proposes an adoption it does not contain:

```sh
git add -A && git commit -m "chore: adopt agentic-sdlc — the finishing run"
```

### E4. Prove it, then hand the keyboard back

```sh
sh scripts/check.sh
```

Green means the adopted repo now keeps the same rules a freshly bootstrapped
one does. Propose the pull request for `chore/adopt-kit` in whatever way your
human's forge expects — and stop there, exactly as the new-project arm stops:
you never push, and the merge that lands the adoption has a human's name on
it.
