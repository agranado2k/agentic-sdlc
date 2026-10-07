# Updating from a kit release

Your project took a copy of the kit when it was bootstrapped. **Two different
things came with it, and they update by two different rules** — because they
are two different kinds of thing:

| | What it covers | The right question at update time |
| --- | --- | --- |
| **Part 1** — steps 0–7 below | the files listed under `files:` in `VERSION` — the **shared layer** | *Is my copy byte-identical to the release?* |
| **Part 2** — steps 8–10 | skills, the manual and its articles, templates, policy files, adapters | *What did the kit change, and did I change the same thing?* |

Part 1's files are a **copy**, so a byte comparison answers the question
completely. Part 2's files are **not** a copy: bootstrap stamped or copied
them and they became yours, and editing them is the intended workflow. A byte
comparison there answers the wrong question — it flags every local edit you were
invited to make, and following it would tell you to overwrite your own work.

**Both halves are one update.** Part 1 on its own is an *inert half-update*, and
the 0.4.0 wave is the illustration: `scripts/agents.lib.sh` (the
capability-tier resolver) joined the shared layer, so Part 1 delivers it —
while the policy file it reads, the skills that call it, and the manual section
that defines its vocabulary are all Part 2. Take Part 1 only and you land a
resolver with no mapping and no callers.

It is a **manual, reviewable update**, not a dependency bump — deliberately. The
shared layer is prose that every agent session loads; a silent upgrade of the
rules an agent works under is exactly the kind of change that should require a
human to read the diff.

> This file is itself shared layer. Do not edit it locally — an edited recipe
> drifts from the kit's actual layout and then tells you to do the wrong thing.
> Local notes go in a local article.

---

## Part 1 — what the shared layer is

The files listed under `files:` in `VERSION`, and nothing else.

They are copied **verbatim** from the kit. They name no product, no command, and
no vendor, which is exactly what makes them copyable at all. Everything else in
your repo — `AGENTS.md` and its shims, `README.md`, `docs/`, your skills, your
adapters — was stamped from a template and became **yours** the moment bootstrap
wrote it. Those are never *overwritten* for you; carrying a release's changes
into them is a decision you make, file by file, and that is Part 2.

`VERSION` records which release of the layer you are on:

```sh
sed -n 's/^shared-layer:[[:space:]]*//p' VERSION
```

`VERSION` is itself copied wholesale during an update (step 5). It carries no
project-specific content — only which release you are on and what that release
covers — so there is nothing in it to merge.

**A local exception to a shared rule never gets edited into the shared file.**
It goes in a local article, and the shared copy stays byte-identical. That rule
exists precisely so that this update stays a copy instead of an archaeology
exercise.

---

## Before you start

- A clean working tree (`git status` empty). Step 5 overwrites files in place.
- You are on a branch, not `main` — this lands as a reviewed PR like anything
  else. Shared invariant §7: an agent may take it to one click away and stops.
- **Every block below is POSIX `sh`, and `sh` is what you should run it in**
  (`sh` for a whole block, `sh -c '…'` for one line). It is also written to be
  safe in `bash` and `zsh`, because the shell you paste into is your login
  shell and on macOS that is `zsh` — but a shell that is neither of those three
  is not something this recipe has been run in.
- **After step 5, re-read this file from disk before you continue.** It is
  itself shared layer, so step 5 replaces the copy you are reading with the one
  that ships with the release you are adopting — and a release that changed its
  own update recipe is exactly the release whose recipe change you need. Step 5
  prints a `NOTE` when it happens, but that note lives in the *new* recipe, so
  the consumer who most needs it is following an old copy that never had it.
  This line is here to be the one thing every past copy of this file could have
  carried: **do not finish an update on the recipe you started it with.**

## Step 0 — point at the kit

```sh
KIT_URL=https://github.com/agranado2k/agentic-sdlc.git
WORK=$(mktemp -d)

git clone --bare --quiet "$KIT_URL" "$WORK/kit.git"
kit() { git --git-dir="$WORK/kit.git" "$@"; }
```

A bare clone: you are only ever *reading* out of it, and a second working tree
on disk is one more thing to get out of sync.

One more helper, and it is the one that keeps this recipe from destroying your
work. Part 2 repeatedly **takes** a file — writes the release's copy over one of
yours — and the obvious spelling, `kit show "$REF:$path" >"$mine"`, is unsafe:
the shell opens and **truncates `$mine` before `kit` is even started**, so a path
that is absent at that ref leaves you with zero bytes and a `fatal:` on stderr.
Absent is not exotic — a skill the kit renamed, an article you never stamped, a
policy file the kit ships only as a `.template`. Fetch first, write second:

```sh
kit_take() {                       # kit_take <ref> <path in the kit> <your file>
	kit show "${1}:$2" >"$WORK/take.$$" || { rm -f "$WORK/take.$$"; return 1; }
	cat "$WORK/take.$$" >"$3" && rm -f "$WORK/take.$$"
}
```

`cat >` rather than `mv` on the last line deliberately: it still truncates, but
only once the bytes are in hand, and it leaves your file's existing mode alone
(step 5 explains why a mode matters and why `>` cannot carry one). A take that
finds nothing returns non-zero and writes nothing, so `kit_take … || echo "…"`
is a verdict you can print rather than a file you have to restore from git.

Now pick the two points you are comparing.

```sh
FROM_REF="v$(sed -n 's/^shared-layer:[[:space:]]*//p' VERSION | head -1)"   # what you have

kit tag --list --sort=-v:refname        # the releases on offer, newest first

TO_REF=               # ← what you want: fill it in from the list above

# Two guards, because what they catch is SILENT. An unset TO_REF, or one equal
# to FROM_REF, makes every step below succeed on a no-op: clean, all verbatim,
# gate green, nothing adopted. This recipe cannot ship a working default —
# whatever release number were written here would be the wrong one by the time
# you read it.
[ -n "$TO_REF" ] ||
	{ echo "TO_REF is unset — pick a release from the list above" >&2; false; }
[ "$FROM_REF" != "$TO_REF" ] ||
	{ echo "FROM_REF = TO_REF = $FROM_REF — you are already on it; there is nothing to update" >&2; false; }
```

> **Release refs.** Releases are the `v`-prefixed tags — `kit tag --list` above
> is the offer, and the kit holds itself to tagging every bump. The sort is
> by version, newest first: git's own order is by name, which puts `v0.10.0`
> before `v0.9.0` and the newest release wherever its name happens to fall. Any ref the
> clone can resolve still works for an experiment, but an update you record in
> `VERSION` should come from a tag: an untagged ref is a point in someone's
> history, not a release.

### If your steps are separate processes

`$WORK`, the `kit()` function and both refs are shell state created here that
**every later step needs**, all the way through step 10. One terminal session
carries them for free. An agent running one command per tool call, a CI job with
a step per stage, or a human resuming tomorrow does not — and each of those
arrives at step 1 with `kit: command not found` or an empty `$WORK`.

Write the state down rather than carrying it. Run step 0's clone this way — with
a fixed `$WORK` rather than a temp one, because a path you cannot name is a path
the next process cannot find. User-scoped and mode 700, because a fixed name
under a shared `/tmp` is otherwise a name somebody else can claim first and a
directory somebody else can read:

```sh
WORK="${TMPDIR:-/tmp}/kit-update-$(id -u)"   # not mktemp -d: you must name it twice
mkdir -p -m 700 "$WORK"
git clone --bare --quiet "$KIT_URL" "$WORK/kit.git"
```

Then — **still in this same process** — pick `FROM_REF` and `TO_REF` exactly as
above, and only after that write the state down. An `env.sh` written before the
refs are picked persists empty refs, and every later step then succeeds on the
silent no-op the two guards above exist to catch:

```sh
cat >"$WORK/env.sh" <<EOF
WORK=$WORK
FROM_REF=$FROM_REF
TO_REF=$TO_REF
EOF

# The two functions go in with a QUOTED heredoc, so their `$` survive as written
# rather than being expanded now against this shell's empty variables.
cat >>"$WORK/env.sh" <<'EOF'
kit() { git --git-dir="$WORK/kit.git" "$@"; }
kit_take() {
	kit show "${1}:$2" >"$WORK/take.$$" || { rm -f "$WORK/take.$$"; return 1; }
	cat "$WORK/take.$$" >"$3" && rm -f "$WORK/take.$$"
}
EOF
```

Then start every later step with `. "${TMPDIR:-/tmp}/kit-update-$(id -u)/env.sh"`,
and delete the directory at the end of step 10 as usual. The refs go in the file
too: `FROM_REF` must **not** be re-derived from `VERSION` after step 5 (see step
8), and a fresh process is exactly where somebody would re-derive it.

## Step 1 — read both manifests

The file **list** can change between releases, so read it at both ends rather
than assuming your local one is current.

```sh
manifest() {
	kit show "${1}:VERSION" | awk '
		/^files:/       { inlist = 1; next }
		!inlist         { next }
		/^[ \t]*#/      { next }
		/^[ \t]*$/      { next }
		/^[ \t]+[^ \t]/ { sub(/^[ \t]+/, ""); print $1; next }
		                { inlist = 0 }
	'
}

manifest "$FROM_REF" | sort >"$WORK/from.list"
manifest "$TO_REF" | sort >"$WORK/to.list"

comm -13 "$WORK/from.list" "$WORK/to.list"   # files JOINING the shared layer
comm -23 "$WORK/from.list" "$WORK/to.list"   # files LEAVING it
```

That awk is the grammar `scripts/manifest.lib.sh` holds and `scripts/check.sh`
sources; the copy is here because this recipe runs in a consumer whose local
module is still the old one, and the kit's own suite holds the two equal. Two
grammars for one file format is two chances to disagree about what your own
manifest says — which is why the name of an entry is its first word in both
sections, and anything after it is annotation.

The notes below run **newest first**, one per release, and step 1 is where
Part 1's half of each is read. Their Part 2 halves are needed later, at the
step each one names, so you do not carry them there by hand: step 8 ends by
printing **your path** — every note from your release up, oldest first, under
the step 9 sub-step that needs it.

**Arriving from 0.64.0 or older, one script joins and each review lens reads its slice.**
One file joins at 0.65.0, `scripts/lens-slice.sh`; none leaves, and no other
shared file changes but this recipe. The slicer is what `/review-pr`'s
coordinator now runs once per review: one `<lens>.diff` per standards lens,
the changed paths its rule selects, and `behavior.diff`, the whole diff. Its
rules are policy, in `scripts/lens-slice.config.sh`, which is yours and
ships filled for a kit-shaped layout — take it whole in 9d when absent, then
retune `LENS_SLICE_RULES` to your layout; with no rules every lens reads the
whole diff, and the slicer says so on stderr. In 9d, too, `config.mjs`'s
`skillCeilings` lowers the `review-pr` and `implement` ceilings after their
splits. Part 2 takes the rest in 9a and 9f: `/review-pr`'s six lenses move
into `lens-*.md` files beside its SKILL.md, and `/implement`'s rare branches
into `COVERS.md`, `DISPATCHED-REVIEW.md` and `STAMP.md` — take both skill
directories whole; `.agents/prompts/cheap-reads.md` is new, and every
spawning skill and both worker contracts point a worker at it.

**Arriving from 0.63.0 or older, the recipe reads in order.**
No file joins or leaves at 0.64.0, and no shared file changes but this
recipe — so re-read it from disk after step 5, as always. Step 0 lists the
releases by version, newest first. Step 7 gains a verbatim check you can run
any time, which needs nothing step 10 deleted. Step 8 prints every changed
path beside the 9 sub-step that takes it, skipping none, and then your path:
each of these notes from your release up, oldest first, under the sub-step it
names. In 9a the kit is read at `.agents/skills/…` first, for the base and for
`theirs`; 9c lists where every docs template landed, `docs/specs/README.md`
among them, and calls a starter newer than your bootstrap `NEW`; 9d prints a
`.sh` policy file's diff after its key sets, for a key shipped commented out;
and a new 9f takes the files no other sub-step does, the docs harness's
`README.md` and fixture tests among them. Nothing else in Part 2 moves.

**Arriving from 0.62.0 or older, a spawn's model is held at emit to an id your agents policy maps.**
One file joins at 0.63.0, `scripts/docs-conformance/validators/skill-ceiling.mjs`
(#585, below); none leaves. `scripts/agents.lib.sh` gains
`--ids`, which prints every model id your `scripts/agents.config.sh` maps,
in the form `--model` prints; `scripts/trace.sh emit kind=spawn` now
refuses, exit 2 and nothing written, a `model` that is not one of them — the
word your agent harness's spawn parameter took in place of a pinned id
(`model=$model` must carry the resolver's answer, not the word), an id with
its harness prefix left on, or any model at all when your policy maps none,
since an unmapped resolver prints nothing and the spawn then carries no
model. A spawn with no model still writes, and other kinds' `model` is not
held. `verify` names a spawn already written off the list on stderr, as
history, judged against the policy as it is now; its verdict does not
change, and `summary` and `export` say the count once. After step 5, check
any spawn line you own — a skill you adapted, a wrapper that sets
`AGENTS_CONFIG` for your own policy file — passes the resolver's id, and
that `scripts/trace.sh` can reach the policy your resolver reads. Part 2 has
three takes: `.agents/skills/implement/SKILL.md` and
`.agents/skills/review-pr/SKILL.md` say which form their spawn lines carry,
and `adapters/claude-code/README.md` says it for the Claude Code spawn
parameter; take them as any changed skill and adapter. Two more
changes ride along from main since 0.62.0: both skills also end a spawn its
vendor refused as `spawn.end` `unreachable`, not `fail`, and re-resolve past
the model the session spawned on (#609); and the Claude Code adapter's
`hooks/transcript-usage.mjs` and `hooks/hook.lib.sh` mark a usage event
whose `tok_out` is a streamed snapshot with `data.out_snapshot`, which
`.agents/skills/retro/QUESTIONS.md` reads as a lower bound (#612); and
`hooks/subagent-stop.sh` reads a spawn prompt's `Trace-Spawn:` second line
through `hook.lib.sh` to attribute the `agent.stop` it files, while
`scripts/trace.sh summary` gains `--by tier` and `--by domain` (#583) —
take the adapter files as 9e says. And a skill that outgrows its byte
ceiling now fails the docs gate (#585): the joining validator, its twin in
`scripts/check.sh`, and `context.mjs`'s `size(rel)` arrive in step 5, but
the ceilings are policy — merge the `skillCeilings` block into your
`scripts/docs-conformance/config.mjs` in 9d, one literal `"<path>": <bytes>,`
per line, or declare none and the rule checks nothing. Two more ride
along (#584, #586): `scripts/check.sh` fails a Claude Code agent type that
carries a model, for the four new `adapters/claude-code/agents/*.md` types
(one per tier, tools and no model — take them with the adapter, 9e), and
`scripts/trace.sh` declares `passed`, `escalated` and `failed` for a
cascade rung's `spawn`; your `scripts/agents.config.sh` gains
`AGENT_CASCADE_MECHANICAL`, empty — add it in 9d — and `--ids` lists the
model it maps.

**Arriving from 0.61.0 or older, a cite of the kit's records says whose it is.**
No file joins or leaves at 0.62.0, and nothing changes behavior: eight
shared files change comments, and two stderr lines their wording, so that
every decision record they cite reads "the kit's ADR-NNNN" — the kit's
records never reach you, and a record of yours under the same number is
a different decision.
Part 2 takes the rest: in 9a the same spelling in sixteen skills, which
you may take or leave; in 9b, `constitution/AGENTS.md.template`'s tiers
section gains the reviewer sentence the 0.53.0 paragraph below told you to
write yourself — say what you run on with `AGENT_SESSION_MODEL`, and after
a reviewer spawn fails on its first call re-resolve with
`AGENT_UNREACHABLE_MODELS` naming the dead model; in 9c,
`templates/docs/specs/README.md` now says a ticket's `Covers:` line cites
plain `R<n>` under a new area's PRD (`<area>/R<n>` covered nothing there)
and stops claiming to be the only file bootstrap put in the directory, and
`templates/docs/adr/INDEX.md.template` says where the kit's records live;
in 9d and 9e, comment lines only, in your policy files and the adapter —
beside the adapter fix that rides along (#606): `subagent-stop.sh` reads a
run that ends on the hand-back tool as final, with `hook.lib.sh`'s shared
anchor reader, and `/retro`'s `QUESTIONS.md` question 6 reads `data.final`.

**Arriving from 0.60.0 or older, a finding raise's id is held at emit.**
No file joins or leaves at 0.61.0. `scripts/trace.sh emit kind=finding.raise`
now refuses, exit 2 and nothing written, a `data.id` that is not the review's
severity id, `[CHML]-[0-9]+` — `H-3`, never the literal `INITIAL-N`
placeholder, and never a confirm-list `A2-N`, which is triaged but never
raised. A raise with no id still writes. `verify` names a raise already
written off the shape on stderr, as history, and its verdict does not
change, so your old trace stays readable; `summary` and `export` say the
count once. After step 5, check any raise line
you own — a review skill you adapted, a script — passes the finding's own
id. Part 2 has one take, in 9a: `.agents/skills/review-pr/SKILL.md`'s two raise
lines spell the shape in place of the placeholder; take it as any changed
skill.

**Arriving from 0.59.0 or older, a living requirement may stop passing on the harness's word.**
No file joins or leaves at 0.60.0. `validators/living-spec.mjs` and its twin in
`scripts/check.sh` now read no citation from a file under
`scripts/docs-conformance/`, whatever your test globs match: the harness's
fixture tests are about the gate, and the shipped `living-spec.test.mjs`
spelled ids such as `billing` R1 to R3 from a path the default globs match,
so a living spec of that area passed with no test of your own (#561). If the
gate goes red after step 5 naming a requirement, nothing of yours ever named
it — write the test. Part 2 has one take, in 9f: replace
`scripts/docs-conformance/test/living-spec.test.mjs` (yours, shipped) with
the kit's, which builds every id at runtime and scans the harness for a
spelled one — or take it whole if you have none; a fixture test you added
there builds its ids the same way.

**Arriving from 0.58.0 or older, delete one file the kit leaked to you.**
No file joins or leaves at 0.59.0, and no shared file changes behavior.
`scripts/agents.kit.codex.config.sh` is the kit's own tier → model mapping
for a codex session, and bootstrap should have deleted it: it was missing
from the kit-only deletion list, so a project bootstrapped while it was in
the kit carries the kit's model ids. Delete it if present — `git rm -q
--ignore-unmatch scripts/agents.kit.codex.config.sh` — in the same commit as
step 5; a project bootstrapped before it existed has none, and the command
then does nothing. Nothing
outside the kit reads it, so the delete changes nothing; your own mapping is
`scripts/agents.config.sh`, which this does not touch. No other kit-only file
leaked: any other `*.kit.*` name in your tree is yours.

**Arriving from 0.57.0 or older, both engines read a code fence by one rule.**
No file joins or leaves at 0.58.0. A fence now pairs as CommonMark pairs it:
it opens on a line whose first non-blank characters are ``` or ~~~, and
closes only on a run of the same character, at least as long, alone on its
line; one left open runs to the end of the file. `scripts/requirement.lib.sh`
holds the rule (it gains `REQ_FENCE_CLOSE_ERE`), and the docs harness reads
it through `validators/living-spec.mjs`'s new `fencedLines`, which
`validators/claude-md-refs.mjs` and `validators/banned-words.mjs` now import
— so take those four files in the same step 5. A
verdict changes only on a document whose fences mix kinds or lengths, or
leave one open: a ``` line inside a ~~~ block no longer closes it in the
reduced gate or the living-spec rule, an unclosed fence now hides the rest of
its file from the harness's path and reference checks, and banned-words no
longer reads a form feed before a marker as a fence. Read such a document
once after the update. Part 2 has one optional take, in 9f:
`scripts/docs-conformance/test/fence.test.mjs` (yours) is new — copy it if
you run the fixture tests; it holds the harness's fence patterns to the
grammar file.

**Arriving from 0.56.0 or older, a bare `end` says it is deprecated.**
No file joins or leaves at 0.57.0. `scripts/trace.sh end` with no run id still
closes the top of the stack, as it always has, and then prints one line on
stderr naming the run it closed and the named form, `sh scripts/trace.sh end
<that run>`: a later release makes the id mandatory, and a bare `end` then
becomes a usage error. So after step 5, find every bare `end` in what you own —
a skill you wrote, a hook, a script, a suite — and pass it the id the matching
`begin` printed, held in a variable or a file between the two. The shipped
skills already do; nothing to take in Part 2.

**Arriving from 0.55.0 or older, a release is tagged at its merge.**
No shared file changes behavior at 0.56.0, and none joins or leaves. Part 2
has one take, in 9a: `.agents/skills/merge-train/SKILL.md` now tags a merge
that bumps `VERSION`'s release line right after the merge, before its
post-merge wait, re-runs once each run that failed after the tag is on the
remote (`gh run rerun <id> --failed`), and judges only that second result.
Take it as any changed skill; a project that never bumps a release line
sees no difference.

**Arriving from 0.54.0 or older, the fence rule moves into the grammar file.**
No file joins or leaves at 0.55.0. `scripts/requirement.lib.sh` gains
`fence_strip`, the one reading of "is this line inside a ``` or ~~~ fence?",
and `scripts/check.sh`'s reduced path check calls it instead of its own
pattern — so take the two in the same step 5. The reduced gate now sources
the grammar file before its path check: without the file it reports
`shared-layer-missing` and skips the path check rather than read fences some
other way, and a file that defines no `fence_strip` stops it with exit 2,
naming the function. No verdict of either engine changes on a project that
has both files. Nothing to take in Part 2.

**Arriving from 0.53.0 or older, one grammar file joins and nothing changes behavior.**
`scripts/requirement.lib.sh` joins the shared layer at 0.54.0 — see "When a
file joins the shared layer" below. It is the requirement-line grammar's one
home: `scripts/check.sh` sources it for the living-spec rule's POSIX twin and
`scripts/coverage.sh` sources it from beside itself, so take all three in the
same step 5. Without it the reduced gate reports `shared-layer-missing` and
the coverage check refuses with exit 2 — neither reads nothing and passes.
`validators/living-spec.mjs` now exports its five patterns under the file's
names; no verdict of either engine or of the coverage check changes. Part 2
has one optional take, in 9f: `scripts/docs-conformance/test/living-spec.test.mjs`
(yours) gains the test that holds the validator's patterns equal to the new
file — copy its two new tests and the `readFileSync` import if you run the
fixture tests. **No such file in your tree** means you bootstrapped before
0.49.0 created it: take it whole from `${TO_REF}` instead, as 9f says.

**Arriving from 0.52.0 or older, the reviewer gains an ordered fallback.**
`scripts/agents.lib.sh` changes content at 0.53.0; take it as step 5 says.
Nothing else in the layer moves, and nothing changes for you until you opt
in: for the reviewer tier only, the resolver now walks the answer, the plain
reviewer, then `AGENT_TIER_REVIEWER_FALLBACK` from your policy file —
space-separated, in order — skipping the caller's `AGENT_SESSION_MODEL` and
every model a caller names in `AGENT_UNREACHABLE_MODELS` after a spawn failed
on its first call, both in your policy file's own words. Unset, it answers
exactly as before. Part 2: in 9d, add the variable to your
`scripts/agents.config.sh` by hand if you want a next answer; in 9b, tell your
sessions to re-resolve with the dead model named rather than override the
reviewer by hand.

**Arriving from 0.51.0 or older, `end` can name the run it closes.**
`scripts/trace.sh end` takes the run id `begin` printed as an optional first
argument at 0.52.0: named, it closes that run or nothing — exit 2 naming the
run that is open, nothing written — so a subagent that shares its session's
stack in the same checkout and skipped its own `begin` cannot close its
parent's run with a bare `end`. A bare `end` keeps its meaning, so step 5
breaks nothing your skills already type. Part 2 is how you take the rest: in
9a, the six skills that close a run (`/diagnose`, `/implement`,
`/merge-train`, `/pr-iterate`, `/retro`, `/review-pr`) name it at `end`, `end
<the run id your begin printed>`; a skill of your own that opens a run can do
the same.

**Arriving from 0.50.0 or older, a test may stop citing a requirement.**
No file joins or leaves at 0.51.0. `validators/living-spec.mjs` and its twin in
`scripts/check.sh` now bound a cited `<area>/R<n>` on its left as well as its
right: preceded by a letter, a digit, `_`, `-` or `/`, it is part of a longer
token and cites nothing, so `Xbilling/R1` or `specs/billing/R1` no longer
names billing/R1. Step 6's gate says which requirement lost its test; name the
id on its own — after a blank, an opening parenthesis or at the start of the
line — and it is green again. Part 2 has nothing new to take.

**Arriving from 0.49.0 or older, one script joins and four skills cite requirement ids.**
`scripts/coverage.sh` joins the shared layer at 0.50.0 — see "When a file
joins the shared layer" below; a project bootstrapped as new from the kit's
main between 0.49.0 and 0.50.0 already holds a copy, which step 5 overwrites.
`/to-tickets` runs it before its quiz on the PRD body and one file per drafted
ticket, so a project without it says so at the quiz and never reads that as a
pass; it reads no policy file. Nothing else in the layer changes. Part 2 is
how you take the rest: in 9a, `/to-tickets` stamps a `Covers:` line on every
ticket under a PRD with requirements, `/implement` names those ids and applies
a living spec's deltas beside the test that names them, `/review-pr` and
`.agents/prompts/review-worker.md` cite the ids on Axis 2, and `/to-prd`
writes `### ADDED`, `### MODIFIED` and `### REMOVED` deltas for an area with a
living spec; in 9c, take `templates/workflows/ai-review-prompt.md` like any
workflow template, and copy `templates/docs/specs/README.md` to
`docs/specs/README.md` by hand if you have none — the starter holds no
requirement, so the gate stays green with it.

**Arriving from 0.48.0 or older, one validator joins and it can fail the gate.**
`scripts/docs-conformance/validators/living-spec.mjs` joins the shared layer
at 0.49.0; `runner.mjs` registers it and `scripts/check.sh` carries its POSIX
twin, so the three land together at step 5. It is silent until you keep a
living spec in `docs/specs/`. Its policy is a `livingSpec` block in your
`config.mjs` — Part 2, step 9d: merge the block by hand, keeping its two
values literal, because the twin reads them by text.

**Arriving from 0.47.0 or older, the trace script reads a run stack.**
`scripts/trace.sh` changes content at 0.48.0: a read subcommand, `stack`,
prints a checkout's open run and its parent, and the claude-code adapter's
stop hook reads through it. It needs git 2.31 or newer. Take the file as
step 5 says; the adapter change is Part 2's.

**Arriving from 0.46.0 or older, nothing in the shared layer moves.**
No shared file changes at 0.47.0. Skills, two constitution templates, the
claude-code hooks and the guards' surface list move — `/to-tickets` names only
the oracle forms `/implement` runs, states a session cap and merges a retro's
candidates into a sibling retro's tickets; your stamped
`constitution/local-workflow.md` gains a **Session cap** line to fill in. The
history note in `VERSION` lists every file; Part 2 is how you take them.

**Arriving from 0.45.0 or older, `/implement` writes one more line.**
No shared file changes at 0.46.0. The skill's delivery step now ends its
PR body with `<!-- implement: ticket=#<N> tier=<tier> -->`, an HTML comment
the forge does not render, so a landing tool can tell a PR the skill opened
from one it did not. Part 2 is how you take it, in 9a; nothing reads the line
unless your landing path does.

**Arriving from 0.44.0 or older, no shared file changes; two skills do.**
`/review-pr` accounts for every lens it planned — a refused one is recorded
as refused, a failed one as `fail` with its cause, and the report names
both on a `Lenses not run:` line — and `/retro`'s chain-health question
reads a refused spawn on its own row. Part 2 is how you take them, in 9a.

**Arriving from 0.43.0 or older, a signal ends a dispatch with 128+signal.**
`scripts/agent-dispatch.sh` (shared, changed at 0.44.0) exits 130, 143 or
129 on INT, TERM or HUP at any point of a dispatch, where a signal before
its timed trap used to read as 127 and one on the untimed path let the
worker's status through. A wrapper that reads the dispatcher's exit status
should read those three as "interrupted". Nothing else in the layer moves.

**Arriving from 0.42.0 or older, three more trace lines are held at emit.**
`scripts/trace.sh` (shared, changed at 0.43.0) refuses a `finding.triage`
whose source is not one of check, bot, human or local, or whose local id is
not `[CHML]-N` or `A2-N`, and a green or red `pr.iterate` without its three
digit counts — exit 2, where it used to write them. A missing source or id
still writes; your existing trace needs nothing. The two review prompts
under `.agents/prompts/` and `templates/workflows/` gained the reuse/DRY
ruling — Part 2 is how you take them.

**Arriving from 0.41.0 or older, the run stack is keyed by session.**
`scripts/trace.sh` (shared, changed at 0.42.0) keeps one run stack per
session in each working tree — `current/<toplevel key>.<session>.runs` —
when a session id is known, and the per-toplevel stack, as before, when
none is; see "When a shared file's BEHAVIOUR changes". Close any run you
have open before you take Part 1, or close it after with
`TRACE_SESSION= sh scripts/trace.sh end`. In Part 2 (9e), if you kept the
Claude Code adapter, take `hooks/hook.lib.sh` and `hooks/subagent-stop.sh`
with this release: the stop hook repeats the stack's path, and the 0.41.0
copy reads a stack no session writes any more.

**Arriving from 0.40.0 or older, one header changes and nothing else.**
`scripts/vocab.sh` (shared, prose-only change at 0.41.0) says in its header
what the checker takes: bare `Field: value` lines a caller lifted, never a
whole body — the contract every kit caller has kept since 0.35.0. Take it
with Part 1 as usual; no behaviour moves, and your policy file is untouched.

**Arriving from 0.39.0 or older, a denied tool call is visible.**
`scripts/trace.sh` (shared, changed at 0.40.0) declares `denied` on
`tool.use` and on no other kind — a widening, see "When a shared file's
BEHAVIOUR changes": an emit 0.39.0 refused now writes, and nothing that
wrote before changes. In Part 2 (9e), the Claude Code adapter gains
`hooks/tool-pre.sh`, a `PreToolUse` hook that leaves a pending marker per
tool call; `hooks/tool-post.sh` removes it when the call returns and
`hooks/session-end.sh` sweeps each marker left into one `tool.use` with
`outcome=denied`, through `hooks/hook.lib.sh`, with `hooks/tool-payload.mjs`
reading the pre-tool payload and `README.md` saying so. If you wired the tool
hook, wire `tool-pre.sh` on `PreToolUse` beside it, as the adapter README
shows; it is behind the same `TRACE_TOOLS` switch. In 9a, `/retro`'s
`QUESTIONS.md` question 6 counts the denials. Beside the skills,
`.agents/prompts/review-worker.md` (changed at 0.38.0, named here) asks a
dispatched reviewer for a `↳ lens:` line per finding.

**Arriving from 0.38.0 or older, the stamp reader bounds its lift.**
`scripts/stamp.sh` (shared, changed at 0.39.0) lifts at most 8 lines of any
one stamp key from a ticket body; past that it is exit 5, "too many stamp
lines", with nothing printed and nothing checked — a stop `/implement`
reports like a refusal. No real ticket meets the bound; a hostile one no
longer costs thirty CPU-seconds. Your manual's vocab.sh row may gain the
fifth exit the template's now names — Part 2 is how you take it.

**Arriving from 0.37.0 or older, the workflow article's rubric tightens one
line.** `constitution/local-workflow.md.template` (shared, changed at 0.38.0)
asks two more things before a ticket is stamped `mechanical`: it names the
one command that is its oracle, and it is one file or one pattern applied
uniformly; a ticket that fails either goes on to the rubric's later
questions. Your stamped copy of the article is yours — Part 2 is how you
take the line if you want it; nothing else in the layer changes.

**Arriving from 0.36.0 or older, two trace keys gain a shape.**
`scripts/trace.sh` (shared, changed at 0.37.0) refuses a `finding.triage`
whose `data.id` is not one token, and a `pr.iterate` whose `data.iteration`
is not digits — exit 2 naming the kind, the key and the shape — where it
used to write them. A missing key still writes; only a present key of the
wrong shape is refused, and an unconfigured trace refuses the same line it
would have ignored. Your existing trace files need nothing: `verify` draws
no advisory on lines written before.

**Arriving from 0.35.0 or older, no shared file changes; a task contract is
admitted before an ordinary request's first edit.** Nothing in Part 1 moves
at 0.36.0 but this file, and Part 2 is how you take the rest. Fresh bootstraps
carry `scripts/task.sh` and `scripts/task.md` — `sh scripts/task.sh start .
<contract>` refuses a missing scope, a route out of proportion to the request
and a dirty baseline the contract did not say to preserve, and records scope,
endpoint, authorization, catalogue identity and separate branch, HEAD, index,
worktree and untracked baseline identities under the worktree's own git
directory; `status` reads it back — with the executable's row in
`scripts/catalogue.config` and the dormant `adapters/codex/README.md` (9e),
which records the entry rule and the hook trust boundary observed on Codex
CLI 0.159.0 and installs no hook. They sit outside `files:` on the footing
`scripts/catalogue.sh` took at 0.27.0: inspect them through Part 2, and take
them by hand knowing that #302, the wave's adoption ticket, decides how the
lifecycle mechanisms are adopted — one operational slice in service is not
that adoption. Also in 9a, untagged since 0.35.0: `/to-tickets`' step 1 reads
the PRD copy its pre-screen reader screened, never a second fetch, and removes
it when the decomposition ends; `/dogfood`'s per-row `Outcome:` check fails
closed on a missing or broken checker and names the row by step and position
instead of printing an outcome; `/merge-train` says a PR landed by hand goes
through the landing script your root manual names, and `/implement` and
`/pr-iterate` run their closing `end` from the checkout that ran `begin`. In
9e, the Claude Code adapter's `session-start.sh` records `data.behind` — how
far the root checkout is behind the last fetched `origin/main`, never a fetch
of its own — through `hook.lib.sh`, and its `README.md` says so; `/housekeeping`'s
`CHECKLIST.md` asks for that count. In 9d, your `scripts/trace.config.sh` gains
`TRACE_BEHIND_WARN`, shipped empty: a number makes the hook say so on stderr
past it. Also in 9e, `subagent-stop.sh`'s wait-bound failure records the last
transcript line's kind, age and the line count. Take the hooks if you wired
them.

**Arriving from 0.34.0 or older, one file joins.** `scripts/stamp.sh` joins
the shared layer at 0.35.0 — see "When a file joins the shared layer" below:
a project bootstrapped as new at 0.35.0 or later has it, one that adopted
the kit into an existing repo takes it with Part 1. `/implement` now reads a
ticket's `Tier:`, `Confidence:` and `Domain:` lines through it and nothing
else, so a project without the script reads every ticket at the defaults
and says so — the script's four exits are in its header. Nothing else in the
layer changes.

**Arriving from 0.33.0 or older, every trace kind holds its outcome to a
vocabulary.** `scripts/trace.sh` (shared, changed at 0.34.0) refuses an
`outcome=` its kind does not declare — exit 2, naming the kind, the value
and the words it takes — where it used to write it. That NARROWS the emit,
see "When a shared file's BEHAVIOUR changes": an emit line of your own with
a typo or a sentence in `outcome=` stops silently succeeding, and because it
ends `|| :` it now writes nothing. Run each of yours once with `--dry-run`
to find it. Lines already in your trace are history: `verify` names each as
an advisory and its exit status does not change. In Part 2, `/merge-train`
(9a) records `outcome=unasked` for a landing nobody could answer, and the
Claude Code adapter's `hooks/subagent-stop.sh` and `README.md` (9e) write no
event for a subagent stop whose transcript never existed. Also in 9a: the
typed-return fence in `/pr-iterate`, `/to-tickets` and `/dogfood` finds the
checker in the repository that holds the skills and refuses an evidence span
under 8 bytes; `/to-tickets` records its drafted label and `/retro`'s
`QUESTIONS.md` rates it; `/review-pr` holds `data.agent` to a closed roster
and records a relayed review's findings, and `/implement` points at that.

**Arriving from 0.32.0 or older, a dispatched review lands through a broker,
and two skills pre-screen what they read.** No shared file changes at 0.33.0;
seven skills, one worker prompt and the Claude Code adapter do, and Part 2
is how you take them.
`/implement`'s review step now lands a *dispatched* review — one run on
another agent harness — through a **broker**, a host-side role your root
manual names, and never by hand: the worker is offline, prints its findings
and stops, and the session checks the dispatcher's exit status before anything
reads the report. A manual that names no broker is a working state — the
in-session reviewer is the review, and the report says no cross-vendor review
ran — so a project that dispatches nothing needs nothing here. The worker
contract `.agents/prompts/review-worker.md` opens by saying the worker is
offline and makes `REVIEWED: <sha>` the report's first line; it ships, so take
it in 9a's three-way. The broker script itself is the kit's own and is not
shipped. `/to-tickets` and `/dogfood` pre-screen an untrusted PRD body or
product output through a tool-restricted reader whose two-line return is
checked before it is read; `/retro` asks an eighth question, stamp
calibration, and `QUESTIONS.md` carries it — so the count in your manual's
`/retro` row and chain paragraph (9b) moves from seven to eight, as
`constitution/AGENTS.md.template`'s did; it also writes its report under
`.retro/` at your root checkout instead of the OS temp directory, and
`/housekeeping`'s `CHECKLIST.md` looks for it there — add `.retro/` to your
ignore file, since the skill will not. `/implement` and `/review-pr` record
a `tdd.cycle` per cycle, a `spawn.end` per spawn and the resolver's model id
captured rather than typed; in `/implement` a refused `Confidence:` value now
stops the session as a refused tier does. `/pr-iterate` sets aside a red whose
own output says `release-bound:` instead of iterating on it. In 9e, the Claude
Code adapter's `README.md` gains the section on denying a typed-return reader
its tools and the one on where a per-user node goes, its `hook.lib.sh` names
that fix in its no-node reason, and its `transcript-usage.mjs` hook takes the
last usage block per message id — take the hooks if you wired them.

**Arriving from 0.31.0 or older, a ticket's stamp gains a line.** No shared
file changes at 0.32.0; two skills do, and Part 2 is how you take them.
`/to-tickets` now writes `Confidence: low|medium|high` under a ticket's
`Tier:` line, and `/implement` reads it: a `low` sends the session back to
its restatement before it builds. Tickets you wrote before this carry no
such line and need none — a missing line is not a blocker. The three tokens
are the policy file's `confidence` vocabulary, declared since 0.25.0.

**Arriving from 0.30.0 or older, the trace's kind vocabulary gains one
word.** `scripts/trace.sh` (shared, changed at 0.31.0) accepts
`kind=finding.dismiss`: a human closed a posted finding with no commit
answering it. `/pr-iterate` emits it, on the subject of the `finding.raise`
it answers, and nothing reads it but the retrospective. Your existing trace
files need nothing — the vocabulary only widened — and if you do not trace,
the emit is the same silent no-op every other one is.

**Arriving from 0.28.0 or older, one file joins and one changes behaviour.**
`scripts/trace.sh`, the decision trace, joins the shared layer — see "When a
file joins the shared layer" below, because a consumer bootstrapped as a new
project at 0.25.0 or later already has it, and one that adopted the kit into
an existing repo does not. `scripts/agent-dispatch.sh` now records every spawn
in that trace — a widening, see "When a shared file's BEHAVIOUR changes". The
policy file beside the trace stays yours, and it is 9d's to add.

**Arriving from 0.16.0 or older, no file joins and one changed content.** This
recipe itself: its prose now uses the kit's own words — *policy files* where
it said `config files` (step 9d is renamed accordingly), *copied* where it said
`installed` — and the banned phrase it quotes in 9c is a code span. The
banned-words advisory has never scanned the recipe (it reads your manual,
your local articles and your skills); this is the shared-layer half of the
kit's own rewording, deferred to a release because this file is copied
verbatim. No step changed.

**Arriving from 0.15.0 or older, two files join.** `scripts/manifest.lib.sh`
joins the shared layer at 0.16.0 and `scripts/check.sh` sources it, so the two
land together at step 5 and the gate fails closed without the module. This
recipe's own parser changed dialect with them: it used to print the whole
trimmed line, and now prints the first word, so an annotated `files:` entry
reads the same here as in the gate. The second is
`scripts/docs-conformance/validators/banned-words.mjs`, an advisory the
runner registers: it reads your glossary's "Words this project does not use"
section and warns on each banned word in your manual, your local articles,
your skills, and the glossary's own other entries. It arrives with the runner (step 5) and reads a section your
glossary already has, so the first gate after the update may print warnings
you have never seen — that is the section doing what it always said; 9c and
9d below say how to carve out a legitimate sense.

## Step 2 — read the upstream delta

What the **kit** changed between the two releases. This is what you are being
asked to adopt.

```sh
kit diff --stat "$FROM_REF" "$TO_REF" -- $(sort -u "$WORK/from.list" "$WORK/to.list")

# then read the ones that moved, in full — this is the part a human must read
kit diff "$FROM_REF" "$TO_REF" -- constitution/shared-invariants.md
```

Read it as rules, not as text. "§9 now requires X" is a change to how every
future session in this repo behaves.

## Step 3 — measure your own drift

What **you** changed. This should print `clean` for every file. Anything else is
a local edit to a file that was not yours to edit, and it is the only thing that
can make this update hard.

```sh
while IFS= read -r f; do
	if [ ! -e "$f" ]; then
		echo "MISSING $f"
		continue
	fi
	if kit show "$FROM_REF:$f" | cmp -s - "$f"; then
		echo "clean   $f"
	else
		echo "DRIFT   $f"
		kit show "$FROM_REF:$f" | diff -u - "$f" | sed 's/^/        /'
	fi
done <"$WORK/from.list"
```

**If you have drift**, stop and resolve it *before* step 5, not during:

1. Read what you changed and why. It is almost always a local exception someone
   needed and wrote in the nearest available place.
2. Move it to a local article — `AGENTS.md`'s local-rules section, or a
   `constitution/local-*.md` — where it belongs and where it survives updates.
3. Restore the shared file to its `FROM_REF` content
   (`kit_take "$FROM_REF" "$f" "$f"`), confirm step 3 is clean, and commit that
   as its **own** change. Untangling drift and adopting a new release in one
   commit makes both unreviewable (shared invariant §10).
4. If the exception is genuinely universal rather than local, it is a kit issue,
   not a local edit. Open one.

## Step 4 — decide

You now have three facts: what upstream changed, that your copy is unmodified,
and which files join or leave the layer. Decide, per file, whether you are taking
it. The default is **all of it** — a partial take is possible (step 7) but leaves
you on no release at all.

## Step 5 — apply

```sh
# every file in the TARGET manifest, taken verbatim — bytes AND mode
# shellcheck disable=SC2046
kit archive "$TO_REF" -- $(cat "$WORK/to.list") | tar -x
sed 's/^/  updated /' "$WORK/to.list"

# anything that LEFT the shared layer is no longer kit-owned. Deleting is the
# usual answer; keeping it means it is now an ordinary file of yours.
comm -23 "$WORK/from.list" "$WORK/to.list" | while IFS= read -r f; do
	git rm -q --ignore-unmatch -- "$f" 2>/dev/null || rm -f "$f"
	echo "  removed $f (left the shared layer at $TO_REF)"
done

# the manifest itself, wholesale — version marker and file list together
kit_take "$TO_REF" VERSION VERSION

# THIS FILE is shared layer, so the extract above just replaced it.
if ! kit diff --quiet "$FROM_REF" "$TO_REF" -- UPDATING.md; then
	echo "  NOTE  UPDATING.md changed in $TO_REF — RE-READ IT before continuing"
fi
```

**If that last line printed, stop and re-read this file from disk.** You opened
the recipe that shipped with `$FROM_REF`; step 5 has just overwritten it with
`$TO_REF`'s, and the copy in front of you is the old one. A release that changed
its own update recipe is precisely a release whose recipe change you need — 0.4.0
is the worked example: it is the release that added Part 2, and a consumer
following 0.3.0's copy reaches the end of step 6 and stops, because in that copy
step 6 *was* the end.

**`kit archive | tar -x`, not `kit show >`.** A `>` redirect writes bytes and
nothing else: the **mode bit is lost**, so a shared file that is `100755` in the
kit lands `100644` in your repo and fails the first time anything runs it. Git
carries exactly one mode bit and `git archive` carries it across; a redirect
cannot. It only bites files *joining* the layer — a file you already had keeps
the mode bootstrap gave it — which is precisely why it is easy to miss. (`tar`
creates the intermediate directories, so there is no `mkdir -p` to do.)

`kit_take` does not change that, and is not a substitute for it: it writes bytes
too, and deliberately leaves the destination's mode alone. It is for **Part 2**,
where every file is one you already have and its mode is already right. `VERSION`
uses it above only because a bad `$TO_REF` should not be able to empty your
version marker — the one file in this step that is not in the manifest and so is
not re-checked by step 6.

## Step 6 — verify the verbatim claim, then the gate

The version marker is only worth something if it is checkable. This is the check:

```sh
while IFS= read -r f; do
	want=$(kit ls-tree "$TO_REF" -- "$f" | awk '{print $1}')
	case "$want" in
	100755) wx=yes ;;
	*) wx=no ;;
	esac
	if [ -x "$f" ]; then hx=yes; else hx=no; fi

	if ! kit show "$TO_REF:$f" | cmp -s - "$f"; then
		echo "DRIFT     $f"
	elif [ "$wx" != "$hx" ]; then
		echo "MODE      $f (kit has $want)"
	else
		echo "verbatim  $f"
	fi
done <"$WORK/to.list"

sh scripts/check.sh
```

The mode leg is not decoration. A content-only `cmp` reports `verbatim` for a
file whose executable bit is wrong — a green check over the exact failure step 5
used to produce. Git records one mode bit and no more, so that is all this
compares; the rest of the permissions come from your umask and are yours.

Every line `verbatim`, and the gate green — with one designed exception. **When
a constitution article joins the layer** (0.5.0's `shared-code-craft.md` is the
first), step 6 ends **red** with `article-unreferenced`: the article is shared
layer, but the *pointer* to it lives in your root manual, which is yours. That
red is the recipe working — it is what forces the shared half and the manual
half of the update to land together. Add one pointer line to the manual's
article layer, re-run the gate, and only then commit. One caveat: that rule
lives in the node harness — the reduced no-node fallback cannot check article
reachability (its NOTICE says exactly that), so without the runtime this red
never fires and remembering the pointer is on you. Then:

```sh
git add -A
git commit -m "chore: update shared layer ${FROM_REF#v} -> ${TO_REF#v}"

echo "Part 1 complete — shared layer at $TO_REF. The update is not done: go to step 8."
```

Note it in `docs/diary.md` — a change to the rules every session loads is a
diary entry by the update protocol ("decision reversed or vendor changed").

**Do not stop here, and do not read the green gate as "done".** The gate is
green because the shared layer is intact, which is all it checks. It cannot see
that the policy file the new shared code reads, the skills that call it and the manual
section that names its vocabulary have not arrived — those are Part 2, steps
8–10, and the only honest end of an update is the end of step 10. `$WORK` stays
where it is; step 8 reuses it.

---

## Step 7 — taking only part of a release

Sometimes one file's change needs a discussion you are not having today. Take
the rest:

```sh
kit archive "$TO_REF" -- constitution/shared-invariants.md | tar -x
```

Same tool as step 5, for the same reason: one file taken with a `>` redirect is
one file whose mode you may have just changed.

…and then **do not bump `shared-layer:`**. A partial take is not the release.
Leave the marker at `FROM_REF`, and record what you deferred and why — in the
diary, or as an issue. The next update then starts from a version you are
genuinely on.

The check in step 6 is what makes this honest: it is the difference between "we
are on 0.3.0" and "we believe we are on 0.3.0". Run it any time, not only during
an update — but not by re-running step 6 itself once the update is over: it
reads `$WORK`, which step 10 deletes. This form needs nothing from step 0. It
clones into a scratch directory of its own, reads the file list from your own
`VERSION` through your own copy of the manifest grammar (shared layer, so it
is the release's), and removes the clone when it is done:

```sh
VERIFY=$(mktemp -d)
git clone --bare --quiet "${KIT_URL:-https://github.com/agranado2k/agentic-sdlc.git}" "$VERIFY/kit.git"
REF="v$(sed -n 's/^shared-layer:[[:space:]]*//p' VERSION | head -1)"
. scripts/manifest.lib.sh
manifest_section files <VERSION | while IFS= read -r f; do
	want=$(git --git-dir="$VERIFY/kit.git" ls-tree "$REF" -- "$f" | awk '{print $1}')
	if [ "$want" = 100755 ]; then wx=yes; else wx=no; fi
	if [ -x "$f" ]; then hx=yes; else hx=no; fi
	if ! git --git-dir="$VERIFY/kit.git" show "${REF}:$f" 2>/dev/null | cmp -s - "$f"; then
		echo "DRIFT     $f"
	elif [ "$wx" != "$hx" ]; then
		echo "MODE      $f (kit has $want)"
	else
		echo "verbatim  $f"
	fi
done
rm -rf "$VERIFY"
```

## When a file joins the shared layer

Step 5 writes it for you. Three things to check afterwards:

- **You may already have a file at that path.** Step 5 overwrote it. If it had
  local content, recover it from git and move that content to a local article —
  the path is kit-owned from this release on.
- **Its MODE has to arrive with it.** A joining file is the only case where the
  mode can be wrong: a file you already had keeps the one bootstrap gave it,
  while a new one gets whatever step 5 wrote. That is why step 5 uses
  `kit archive | tar -x` and why step 6 compares the executable bit — a shared
  *script* that arrives non-executable fails the first time something runs it,
  and a byte comparison calls it verbatim.
- **The gate now requires it.** `scripts/check.sh` fails if a file named in
  `VERSION` is missing, so deleting it later fails your push rather than silently
  degrading.
- **A constitution article additionally needs a pointer.** The gate refuses an
  article the root manual never references (`article-unreferenced`), so step 6
  stays red until one line joins `AGENTS.md`'s article layer. Deliberate: an
  article nothing points at binds nobody, and would drift unnoticed. (Node
  engine only — the reduced fallback cannot check reachability, and says so.)

**0.29.0 is the joining file you may already have.** `scripts/trace.sh` has
shipped with every NEW-PROJECT bootstrap since 0.25.0, outside `files:`, so a
consumer bootstrapped that way since then holds a copy that step 3 never measured — it was not in
`from.list`, so no drift report names it. Before step 5 overwrites it, compare
it with the release it came from, and move any local change out as step 3 says:

```sh
# no output means nothing of yours is in it
kit show "${FROM_REF}:scripts/trace.sh" | diff - scripts/trace.sh
```

A consumer from before 0.25.0 has no file there, and neither has one that
ADOPTED the kit into an existing repo at any release before 0.29.0 — the
adoption arm copied neither the script nor its policy file. For both, step 5
simply writes the script, and 9d's policy file is a take, not a merge.
Either way the script arrives **inert**: its policy file,
`scripts/trace.config.sh`, is not shared layer and ships with `TRACE_DIR`
empty, so every emit exits 0 having written nothing, after one note on stderr.
That is a working state, not a failure — and it is the half-update this
release is most likely to leave you in, which is why 9d names the one line
that turns it on.

## When a shared file's BEHAVIOUR changes

Most releases move prose. Some move **code**, and step 5 replaces it without
asking, because that is what "verbatim copy" means. The question a code change
leaves you with is not *did I get the bytes* — step 6 answers that — but **does
anything I own need to change to match**.

Read the release's `VERSION` comment block first: it says what changed and, for
each change, which half of the wave it sits in. Then ask, in this order:

- **Did the shared code's contract NARROW?** A new required argument, a removed
  variable, a stricter check. Your own callers — scripts, hooks, anything in a
  local article that quotes a command — have to be found and fixed, and Part 1
  alone will have already broken them. Nothing but the release notes will tell
  you; the gate only checks the layer is intact.
- **Did it WIDEN?** A new optional argument, a new variable it will read if you
  set one. Nothing of yours breaks, and nothing of yours has to change — but the
  feature is inert until Part 2 brings across the skills that use it and, in
  most cases, until you add something to a policy file of your own (9d).

**0.7.0 is a widening, and the cleanest example of one yet.**
`scripts/agents.lib.sh` gained an optional second argument, the task **domain**:

```sh
sh scripts/agents.lib.sh implementer            # exactly as before
sh scripts/agents.lib.sh implementer content    # new: prefers
                                                # AGENT_TIER_IMPLEMENTER_CONTENT
```

Called with one argument it behaves as it did at 0.6.0, so a consumer on 0.6.0
runs Part 1, gets the new resolver, and **nothing they own needs to change at
all**. What the release is *for* is Part 2 and one edit of your own:

- **9d, your `scripts/agents.config.sh`** — optional, and the only place a
  mapping can live. Add `AGENT_TIER_<TIER>_<DOMAIN>` variables for the
  distinctions your repo actually has (`AGENT_TIER_IMPLEMENTER_CONTENT` is the
  usual first one) and leave the rest alone: an unmapped domain falls back to
  the plain tier, silently and correctly. The kit's copy gained only a comment
  block describing the convention — the key-set diff in 9d will show no new
  keys, because the kit ships every mapping empty and always will. Take the
  comment across by hand if you want the documentation next to the data;
  skipping it costs you nothing but the documentation.
- **9a, the skills** — `/to-tickets` learned to stamp an optional `Domain:` line
  when the medium of the work would change which model you would pick, and
  `/implement` learned to pass that line through as the second argument. Without
  these two hunks the resolver's new axis is reachable only by hand.
- **9b, the manual** — the "Capability tiers" section gained a paragraph on the
  domain axis and the fact that its vocabulary is open and local, unlike the
  four closed tier names.
- **9e, the adapters** — if you kept the tree, `adapters/claude-code/README.md`
  works a domain-qualified spawn through end to end.

Take Part 1 alone here and you are not broken, merely unchanged: the seam is
present and nothing reaches it. That is the same inert half-update this file
opens with, in its mildest form.

**0.29.0 is a widening of the same kind.** `scripts/agent-dispatch.sh` appends
a `spawn` line to the decision trace when it crosses to another agent harness —
tier, domain, agent harness, model, depth, prompt size — and a `spawn.end` at
every way out past that point, with its outcome (`ok`, `timeout`, `budget`,
`unreachable`, or `fail` with the exit status). The worker it starts is handed
a run of its own in `TRACE_RUN`, with the dispatching run as its parent in
`TRACE_PARENT`, so its emits join the dispatching trail. No
exit status, argument or stdout changes, and every emit ends `|| :`, so nothing
you call it from has to change. What it adds is one optional key in **your**
`scripts/agents.config.sh` (9d): `AGENT_DISPATCH_TRACE_PROMPT='1'` keeps each
worker prompt in the trace as a blob. Leave it out to keep prompts out; any
other value is refused with exit 2 rather than read as off, because a switch
about private data whose answer is hidden is worse than none. With the trace
policy file empty, none of this writes anything.

**0.34.0 is a narrowing, and the first one in the trace.** `scripts/trace.sh`
now holds each kind's `outcome` to a vocabulary of its own — `review.verdict`
takes `pass`, `blocked` or `confirm`, `merge.land` takes `landed`, `skipped`
or `stopped`, and so on for every kind; the script's header carries the
table beside its kind list. The kit's ADR-0008 records the decision, and
no copy of it reaches you, since decision records are yours.
An emit with no outcome is legal on every kind, `run.start` and
`session.end` take none, and `note` takes any one word. What used to write
and now exits 2 is an outcome its kind does not declare:

```sh
sh scripts/trace.sh emit kind=review.verdict outcome='not blocking'  # exit 2
sh scripts/trace.sh emit kind=review.verdict outcome=pass            # writes
```

No argument, variable or stdout changes otherwise. Every emit the kit's
skills, the Claude Code adapter's hooks and the dispatcher write is
declared, so nothing the kit ships is affected; what you have to find is
your OWN emit lines — a skill you wrote, a hook of yours, a local article
that quotes one. Each ends `|| :`, so a refusal costs you the event and
nothing else, silently: run each once with `--dry-run` and read stderr.
Your existing trace needs nothing — `verify` names each old line whose
outcome the table does not declare as an advisory, and `summary` and
`export` say the count once, all with the exit status they had.

**0.40.0 is a widening of the table 0.34.0 closed.** `scripts/trace.sh`'s
kind table declares one more word, `denied`, on `tool.use` alone:

```sh
sh scripts/trace.sh emit kind=tool.use outcome=denied    # writes (exit 2 at 0.39.0)
sh scripts/trace.sh emit kind=agent.stop outcome=denied  # exit 2, as before
```

No argument, variable or stdout changes, and nothing that wrote before stops
writing, so nothing you own needs to change. What the word is *for* is Part
2: the Claude Code adapter's pending marker (9e), which is what writes it,
and `/retro`'s question 6 (9a), which counts it. Take Part 1 alone and the
word is declared and nobody writes it.

**0.42.0 moves where the run stack lives, and only for a caller with a
session id.** `begin` and `end` kept one stack per working tree, so two
sessions in one checkout read each other's open run and an `end` in one
could pop the other's. The stack is now keyed by session as well:

```sh
TRACE_SESSION=a sh scripts/trace.sh begin implement   # pushes on current/<key>.a.runs
TRACE_SESSION=b sh scripts/trace.sh end               # exit 2: session b has no run open
sh scripts/trace.sh begin implement                   # no session id: current/<key>.runs, as before
```

The session is the one the event's own `session` field would take — a
`session=` on the line, then `TRACE_SESSION`, then the pointer file — and an
id that is not one path segment of `[A-Za-z0-9._-]` keys nothing. No
argument, exit status or stdout changes, so if nothing you own sets a
session id, nothing you own sees a difference. What can: a script of yours
that reads `current/*.runs` by path (the Claude Code adapter's stop hook is
the kit's one, and Part 2 brings its fix), and a `begin` in one process
whose `end` runs in another with a different `TRACE_SESSION` — they now
name two stacks, and the `end` is exit 2 until both say the same session.

## When a shared file's path changes

Treat it as one leaving and one joining: it falls out of `from.list` and into
`to.list`, and step 5 handles both halves. Check the upstream diff for the
rename note so you know it is the same file, not a deletion plus an unrelated
addition.

---

## Worked example — Part 1

A real run, captured from `tests/docs-demo.sh` in the kit. The setup: a consumer
that bootstrapped at shared-layer **0.1.0** (whose layer was
`constitution/shared-invariants.md` alone), updating to **0.65.0** (by which point
the guards, the gate, the harness engine, the tier resolver, the code-craft
article and this file have all joined the layer). The consumer has one local edit to a shared file — the
drift case, because the clean case teaches nothing.

Refs are local paths here rather than tags, per the pre-1.0 note in step 0. Both
transcripts are captured under `LC_ALL=C`, so a reader who runs the recipe in
another locale may see the same lines sorted differently — `sort` and `comm`
order by the locale's collation, and only the paths move, never the verdicts.

```console
$ kit tag --list --sort=-v:refname
v0.65.0
v0.1.0
$ echo "$FROM_REF -> $TO_REF"
v0.1.0 -> v0.65.0

$ comm -13 "$WORK/from.list" "$WORK/to.list"   # JOINING
UPDATING.md
constitution/shared-code-craft.md
scripts/agent-dispatch.sh
scripts/agents.lib.sh
scripts/behavior-delta.sh
scripts/check.sh
scripts/coverage.sh
scripts/docs-conformance/context.mjs
scripts/docs-conformance/index.mjs
scripts/docs-conformance/runner.mjs
scripts/docs-conformance/validators/banned-words.mjs
scripts/docs-conformance/validators/claude-md-refs.mjs
scripts/docs-conformance/validators/design-brief.mjs
scripts/docs-conformance/validators/housekeeping-due.mjs
scripts/docs-conformance/validators/living-spec.mjs
scripts/docs-conformance/validators/mutation-decision.mjs
scripts/docs-conformance/validators/skill-bridge.mjs
scripts/docs-conformance/validators/skill-ceiling.mjs
scripts/docs-conformance/validators/skill-paths.mjs
scripts/docs-conformance/validators/skill-web.mjs
scripts/guards.lib.sh
scripts/lens-slice.sh
scripts/manifest.lib.sh
scripts/requirement.lib.sh
scripts/stamp.sh
scripts/tdd-pairing-guard-ci.sh
scripts/tdd-pairing-guard.sh
scripts/trace.sh
scripts/vocab.sh
$ comm -23 "$WORK/from.list" "$WORK/to.list"   # LEAVING
(none)

$ kit diff --stat "$FROM_REF" "$TO_REF" -- $(sort -u "$WORK/from.list" "$WORK/to.list")
 UPDATING.md                       | 2826 +++++++++++++++++++++++++++++++++++++
 constitution/shared-code-craft.md |  147 ++
 constitution/shared-invariants.md |    8 +-
 3 files changed, 2980 insertions(+), 1 deletion(-)

$ kit diff "$FROM_REF" "$TO_REF" -- constitution/shared-invariants.md
diff --git a/constitution/shared-invariants.md b/constitution/shared-invariants.md
index 7661602..5c18e6a 100644
--- a/constitution/shared-invariants.md
+++ b/constitution/shared-invariants.md
@@ -96,3 +96,3 @@ A rule that is neither is a suggestion. Label it as one or delete it.
 
-## 9. Measure the ceiling
+## 9. Measure the ceiling, don't assume it
 
@@ -117,2 +117,8 @@ refactor first, on its own, with the suite green before and after.
 
+Per §8 this rule is checkable rather than merely asserted, because the claim is machine-
+visible: a commit whose declared type says "structure only" while its own diff touches a
+contract artifact has contradicted itself. Review tooling should surface those commits as
+a confirm item — the author either splits the commit or relabels it, and both outcomes are
+better than a reviewer discovering the mix by reading.
+
 ## 11. The context budget is a real budget

$ # step 3 — drift check
DRIFT   constitution/shared-invariants.md
        @@ -122,3 +122,5 @@
         push elaboration into articles read on demand; scope package-specific rules to the
         package. Duplicated guidance is not redundancy, it is drift waiting to happen — every
         rule has exactly one home, and everywhere else points at it.
        +
        +NOTE (local): §4 is waived for the QA phase in this repo.

$ # the exception moves to a local article; the shared file is restored
clean   constitution/shared-invariants.md

$ # step 5 — apply
  updated UPDATING.md
  updated constitution/shared-code-craft.md
  updated constitution/shared-invariants.md
  updated scripts/agent-dispatch.sh
  updated scripts/agents.lib.sh
  updated scripts/behavior-delta.sh
  updated scripts/check.sh
  updated scripts/coverage.sh
  updated scripts/docs-conformance/context.mjs
  updated scripts/docs-conformance/index.mjs
  updated scripts/docs-conformance/runner.mjs
  updated scripts/docs-conformance/validators/banned-words.mjs
  updated scripts/docs-conformance/validators/claude-md-refs.mjs
  updated scripts/docs-conformance/validators/design-brief.mjs
  updated scripts/docs-conformance/validators/housekeeping-due.mjs
  updated scripts/docs-conformance/validators/living-spec.mjs
  updated scripts/docs-conformance/validators/mutation-decision.mjs
  updated scripts/docs-conformance/validators/skill-bridge.mjs
  updated scripts/docs-conformance/validators/skill-ceiling.mjs
  updated scripts/docs-conformance/validators/skill-paths.mjs
  updated scripts/docs-conformance/validators/skill-web.mjs
  updated scripts/guards.lib.sh
  updated scripts/lens-slice.sh
  updated scripts/manifest.lib.sh
  updated scripts/requirement.lib.sh
  updated scripts/stamp.sh
  updated scripts/tdd-pairing-guard-ci.sh
  updated scripts/tdd-pairing-guard.sh
  updated scripts/trace.sh
  updated scripts/vocab.sh
  NOTE  UPDATING.md changed in v0.65.0 — RE-READ IT before continuing

$ # step 6 — verbatim check (bytes AND mode), then the gate
verbatim  UPDATING.md
verbatim  constitution/shared-code-craft.md
verbatim  constitution/shared-invariants.md
verbatim  scripts/agent-dispatch.sh
verbatim  scripts/agents.lib.sh
verbatim  scripts/behavior-delta.sh
verbatim  scripts/check.sh
verbatim  scripts/coverage.sh
verbatim  scripts/docs-conformance/context.mjs
verbatim  scripts/docs-conformance/index.mjs
verbatim  scripts/docs-conformance/runner.mjs
verbatim  scripts/docs-conformance/validators/banned-words.mjs
verbatim  scripts/docs-conformance/validators/claude-md-refs.mjs
verbatim  scripts/docs-conformance/validators/design-brief.mjs
verbatim  scripts/docs-conformance/validators/housekeeping-due.mjs
verbatim  scripts/docs-conformance/validators/living-spec.mjs
verbatim  scripts/docs-conformance/validators/mutation-decision.mjs
verbatim  scripts/docs-conformance/validators/skill-bridge.mjs
verbatim  scripts/docs-conformance/validators/skill-ceiling.mjs
verbatim  scripts/docs-conformance/validators/skill-paths.mjs
verbatim  scripts/docs-conformance/validators/skill-web.mjs
verbatim  scripts/guards.lib.sh
verbatim  scripts/lens-slice.sh
verbatim  scripts/manifest.lib.sh
verbatim  scripts/requirement.lib.sh
verbatim  scripts/stamp.sh
verbatim  scripts/tdd-pairing-guard-ci.sh
verbatim  scripts/tdd-pairing-guard.sh
verbatim  scripts/trace.sh
verbatim  scripts/vocab.sh
$ sh scripts/check.sh
FAIL  docs gate: violations found

FAIL  docs conformance: violations found

  [claude-md-refs] (1)
    x constitution/shared-code-craft.md [article-unreferenced] — is not referenced from AGENTS.md — no agent will ever be pointed at it
      -> Add a pointer to it in AGENTS.md's article layer, or delete the article — an unreachable standing instruction binds nobody and drifts unnoticed.

1 violation(s) across 1 validator(s).

Fix them, or see .githooks/pre-push for the logged bypass.

$ # RED, deliberately: the ARTICLE is shared layer, the POINTER to it is
$ # yours (the root manual — Part 2 territory). Add it and re-run.
$ sh scripts/check.sh
OK  docs gate: all checks passed (shared-layer 0.65.0, engine: docs harness)
$ sed -n 's/^shared-layer:[[:space:]]*//p' VERSION
0.65.0
Part 1 complete — shared layer at v0.65.0. The update is not done: go to step 8.
```

**Read the last two lines before the drift block.** `NOTE  UPDATING.md changed`
is step 5 telling this consumer that the recipe it is running is no longer the
recipe on disk — at 0.1.0 there was no `UPDATING.md` at all, and at 0.4.0 there
is one with a Part 2 in it. And the run does not end on the green gate; it ends
by naming step 8. A green gate here means "the shared layer is intact", which is
a smaller claim than "you are updated".

Read the drift block again. The consumer had written a local exception **into**
the shared rulebook. Step 3 found it in one command; the fix was to move those
two lines to `AGENTS.md` and restore the shared file to its 0.1.0 bytes, as its
own commit. Only then did step 5 run — and it is a plain overwrite, because
there was nothing left to merge.

Had the exception stayed where it was, step 5 would have silently destroyed it
and nobody would have known which paragraph used to be there.

The lesson is step 3. The update itself is one `git archive` extract over the
whole manifest; what makes it cheap or expensive is entirely whether anyone
edited a file that was not theirs to edit.

---

# Part 2 — the parts that are yours

Everything bootstrap stamped, copied or left behind is **yours**: the skills
(canonical under `.agents/skills/` since 0.14.0, with `.claude/skills/`
symlinks; a pre-0.14.0 project has real files at `.claude/skills/` and that
stays legal), `AGENTS.md` and the `constitution/local-*.md` articles,
the workflows under `.github/workflows/`, the policy files, `README.md`, `docs/`,
and `adapters/`.

"Yours" does not mean frozen. The kit keeps improving them, and a release's
actual *features* usually live here rather than in the shared layer — 0.4.0's
value is a Deliver phase in `/implement`, tier-aware planning in `/to-tickets`,
two new skills and a cross-provider review workflow, none of which is
manifest-listed. What "yours" means is that **nothing here is ever overwritten
without you looking at it**, and that there is no verbatim check at the end: the
docs gate is the check.

Do Part 2 *after* Part 1 and commit it separately (shared invariant §10). Part 1
is a mechanical overwrite anybody can re-derive; Part 2 is a series of
judgements, and a reviewer reading the two mixed together can check neither.

## Step 8 — list what changed outside the shared layer

Reuse the bare clone, the two refs, and the two manifests from steps 0 and 1.
Every path the kit changed outside the layer prints once, beside the step 9
sub-step that takes it:

```sh
kit diff --name-only "$FROM_REF" "$TO_REF" | sort >"$WORK/changed.all"
sort -u "$WORK/from.list" "$WORK/to.list" >"$WORK/shared.all"
comm -23 "$WORK/changed.all" "$WORK/shared.all" >"$WORK/changed.yours"

step_of() {                        # step_of <path> — the step 9 sub-step that takes it
	case "$1" in
	AGENTS.md | CLAUDE.md | GEMINI.md | README.md | VERSION | bootstrap.sh | \
		EXCLUSIONS.md | SETUP.md | setup/* | docs/* | tests/* | *.kit.* | \
		.github/workflows/kit-* | .github/PULL_REQUEST_TEMPLATE.md | \
		.claude/settings.json) echo kit ;;
	.agents/skills/* | .claude/skills/*) echo 9a ;;
	constitution/*) echo 9b ;;
	templates/*) echo 9c ;;
	scripts/*.config.sh | scripts/docs-conformance/config.mjs | \
		scripts/docs-conformance/local-vocabulary.mjs.template) echo 9d ;;
	adapters/*) echo 9e ;;
	*) echo 9f ;;
	esac
}
while IFS= read -r p; do
	printf '%-4s %s\n' "$(step_of "$p")" "$p"
done <"$WORK/changed.yours" | sort >"$WORK/changed.steps"
cat "$WORK/changed.steps"
```

Do **not** re-derive `FROM_REF` from `VERSION` here: step 5 already moved it to
the release you are adopting. Part 2 runs in the same session as Part 1, on the
same two refs.

**No line is skipped here, and a path you do not have is not a reason to.**
Bootstrap consumed `templates/docs/` into `docs/`, so no consumer has a path
under it, and the living specs' starter that 0.49.0 added there is exactly the
file a consumer bootstrapped before it needs from 9c. A file the kit created
after your bootstrap is absent from your tree for the same reason. Each step
below says what absence means for its category.

**`kit` marks the kit's own files.** Bootstrap deletes the kit's scaffolding
(`tests/`, `.github/workflows/kit-*.yml`, `EXCLUSIONS.md`, `bootstrap.sh`
itself, every `*.kit.*` file), and `VERSION` prints because it is not an entry
in its own manifest — step 5 already copied it. The other `kit` lines are
paths you **do** have, because they are the kit's copy of a file you own. The
kit self-hosts the constitution it ships, so it has its own `AGENTS.md`, its
`CLAUDE.md` / `GEMINI.md` shims, its `README.md`, its `docs/diary.md`, its
`docs/adr/*` and its `docs/domain-glossary.md` — and every one of those is a real
path in your repo too. Say it plainly: **the kit's own manual and docs are never
your base.** They are one project's filled-in copy, exactly as yours is; two
consumers of the kit are not each other's upstream.

The trap is `AGENTS.md`, because it is the one where the mistake produces a
plausible-looking diff. Your manual's base is `constitution/AGENTS.md.template`
(9b), which is the file bootstrap stamped and the only kit file your manual
descends from. Diff against the kit's root `AGENTS.md` instead and you are
reading someone else's local rules — hard rule numbering, worktree conventions,
a capability-tier wrapper that exists in the kit and nowhere else — and every one
of them looks like a section you are missing. `README.md`, `docs/diary.md` and
`docs/adr/` are the same shape one notch less dangerous: 9c already says a kit
change under `templates/docs/`' descendants is something to read and borrow
from, never something to copy over the top. This is that rule, stated where the
line actually appears in front of you.

**Then print your path.** Step 1's release notes are newest first, and from
0.44.0 on a note that carries a Part 2 take names the sub-step it belongs to.
This reads them from the recipe on disk — which step 5 made `$TO_REF`'s — and
prints every note from your release up, **oldest first**, under each sub-step
it names; a note inside a 9 sub-step's own section counts for that sub-step,
and `--` marks a note that names none — a Part 1 note, or one from before
0.44.0 that says only "Part 2 is how you take them" — to read whole:

```sh
awk -v from="${FROM_REF#v}" '
	function num(v,  p) { split(v, p, "."); return p[1] * 1000000 + p[2] * 1000 + p[3] }
	function out(s) { printf "%s %09d %s  %s\n", s, num(v), v, lead }
	function flush(  t, s, n) {
		if (!on) return
		on = 0
		lead = para
		sub(/^ *\*\*/, "", lead)
		sub(/\*\*.*/, "", lead)
		split("", seen)
		n = 0
		t = para
		while (match(t, /(^|[^0-9.])9[a-f]([^a-z0-9]|$)/)) {
			s = substr(t, RSTART, RLENGTH)
			sub(/^[^9]*/, "", s)
			s = substr(s, 1, 2)
			if (!(s in seen)) { seen[s] = 1; out(s); n++ }
			t = substr(t, RSTART + RLENGTH)
		}
		if (sec != "" && !(sec in seen)) { out(sec); n++ }
		if (!n) out("--")
	}
	/^## /                     { flush(); sec = "" }
	/^### 9[a-f]/              { flush(); sec = substr($2, 1, 2) }
	/^\*\*Arriving from [0-9]/ {
		flush()
		match($0, /[0-9]+\.[0-9]+\.[0-9]+/)
		v = substr($0, RSTART, RLENGTH)
		if (num(v) >= num(from)) { on = 1; para = "" }
	}
	on && /^$/                 { flush(); next }
	on                         { para = para " " $0 }
	END                        { flush() }
' UPDATING.md | sort | sed 's/^\([^ ]*\) [0-9]\{9\} /\1  /'
```

Each line is one note — the release you arrive from, then its bold lead — and
the note itself is in step 1, or in the section it sits in. A consumer moving
from 0.48.0 sees the `livingSpec` block under 9d at 0.48.0, the living specs'
starter under 9c at 0.49.0, and the reviewer fallback under 9d at 0.52.0, in
the order they apply. Read a sub-step's lines when you reach it, before its
commands.

## Step 9 — take each category by its own rule

One rule per category, because the categories differ in what a local edit
*means*:

| Category | Paths | The rule |
| --- | --- | --- |
| **Skills** (9a) | `.agents/skills/*/` (kit-side since 0.14.0; yours are wherever bootstrap put them) | three-way: kit's old → kit's new → yours. Take the delta unless you deliberately forked |
| **Manual & articles** (9b) | `AGENTS.md`, `constitution/local-*.md` | three-way against the `.template` they were stamped from; you are hunting for **sections** you do not have |
| **Templates** (9c) | `templates/workflows/*` → `.github/workflows/`; `templates/docs/*` → `docs/`, `README.md` and `.github/PULL_REQUEST_TEMPLATE.md` | copy only what the release changed and you have not customized; a template you deleted stays deleted; a doc starter newer than your bootstrap is a take |
| **Policy files** (9d) | `scripts/*.config.sh`, `scripts/docs-conformance/config.mjs`, `.../local-vocabulary.mjs` | **never overwrite.** Ask about both refs, then diff the key sets (`.sh`) and read the diff (always) — the new shared code may read a key you do not set |
| **Adapters** (9e) | `adapters/` | opt-in, whole-directory. Take a tree or leave it; never half of one |
| **Everything else bootstrap copied** (9f) | `scripts/docs-conformance/README.md` and `scripts/docs-conformance/test/`, `.agents/prompts/`, `.githooks/`, `.gitignore`, `scripts/task.*`, `scripts/catalogue.*`, `scripts/worktree-cleanup.sh` | yours, copied once: take what you never edited, three-way what you did, take whole what is newer than your bootstrap |

### 9a. Skills — a three-way, not a copy

**Start with the inventory, not the diff.** Since 0.11.0 the kit's `VERSION`
carries a `skills:` section — every skill the release ships, by name. It is
**state, not delta**: however many releases this update spans, and however
many earlier windows were skimmed or skipped, the comparison below prints
exactly what your project lacks. Step 8's `changed.yours` cannot promise that
— a skill added before your `FROM_REF` is in no diff you will ever run, which
is precisely how a real consumer lost a whole skill with a green gate. Only
the newer ref's list is read, so a `FROM_REF` that predates the section does
not matter — and a `TO_REF` that predates it makes the fence say so rather
than print an empty gap list, because a silence that means "I could not look"
must never read as "nothing is missing".

```sh
kit show "${TO_REF}:VERSION" | awk '
	/^skills:/      { inlist = 1; next }
	!inlist         { next }
	/^[ \t]*#/      { next }
	/^[ \t]*$/      { next }
	/^[ \t]+[^ \t]/ { sub(/^[ \t]+/, ""); print $1; next }
	                { inlist = 0 }
' | sort >"$WORK/skills.manifest"
[ -s "$WORK/skills.manifest" ] ||
	echo "no skills: manifest at ${TO_REF} (pre-0.11.0 kit?) — the inventory cannot answer" >&2

for d in .claude/skills/*/; do
	[ -d "$d" ] || continue
	basename "$d"
done | sort >"$WORK/skills.installed"

comm -23 "$WORK/skills.manifest" "$WORK/skills.installed"   # skills you LACK
```

Read each printed name against what you know: it is either a **decline you
recorded** (the optional skill you said no to, a fork you wrote down — nothing
to do) or a **feature nobody ever told you about** — adopt it as a new skill
(the directory copy further down), and read its release's history note in the
newer `VERSION` for the wiring that shipped with it, because a skill's whole
value can hang on one bullet in another skill and one marker in a template.
Only the first word of a manifest entry is the name; anything after it is
annotation.

**Arriving from 0.10.0 or older, check `/explain-diff` by name.** It shipped
in the v0.8.0 window and predates this inventory, so it is the skill the list
above most likely prints. Adopting it is the directory copy plus **two wiring
points**: your `/implement` skill's Deliver phase gains the appendix bullet
(that arrives as an ordinary 9a take or merge of `/implement` below), and your
pull-request template gains the `<!-- explain-diff-appendix -->` marker
paragraph (that is a 9c template take). The copy without the wiring puts in place a
skill nothing invokes.

**Arriving from 0.16.0 or older, the inventory prints no new name — eight
skills changed a phrase.** `/design-brief`, `/diagnose`, `/dogfood`,
`/housekeeping` (its checklist), `/improve-codebase-architecture`,
`/prototype`, `/review-pr` and `/tdd` each lost a banned word to the
glossary's term: *bootstrapping* or *copying in* for the bootstrap sense of
`install`, *policy file* for the consumer's own configuration, *configuration*
in the general sense, *the kit* for `the framework`. Ordinary three-way merges;
none changes what a skill does.

**Arriving from 0.15.0 or older, the inventory prints no new name — six
skills and the licence file changed body.** All are ordinary three-way merges
here: `/implement`'s
Deliver step names the rule that the reviewer is never the model that
implemented, and the `reviewer self-implemented` domain to resolve when the
session itself wrote the diff (its mapping is 9d); `/tdd`'s `deep-modules.md`
draws its two diagrams in mermaid and `/grill-with-docs` lists its file tree
as a nested list, both in place of character art (craft rule §10 now has a
check); `/grill-with-docs`'s `GLOSSARY-FORMAT.md` quotes the banned phrase it
mentions as a code span, so the new banned-words advisory leaves it alone;
`/diagnose`'s human-in-the-loop script moved one level up (the paragraph on
a removed file inside a skill, above, is about exactly this); `/explain-diff`'s
filename example carries a date placeholder; `/tdd`'s own provenance line
says which sidecar was redrawn, and `/improve-codebase-architecture`'s
`PRESENTING.md` names mermaid as the diagram language its reports render;
the licence file's provenance rows follow the diagrams.

**Arriving from 0.14.0 or older, the inventory prints at least two names you
have not seen before: `design-brief` and `housekeeping`.** Both are directory
copies plus wiring, and the two takes are symmetric. `/design-brief` needs its
quick-reference row and chain sentence in your manual (9b), the three anchors
in your engineering article to write into (9b again), the `designBrief`
section in your gate config that names the article its advisory reads (9d),
and the rule 11 that `/to-tickets` gains in this release plus the re-entry
paragraph `/improve-codebase-architecture` gains (both ordinary 9a merges of
skills you already have). `/housekeeping` needs its quick-reference row and
chain sentence (9b), the diary's `**Last housekeeping**` row it stamps (9c),
and the `housekeepingDue` section in your gate config that sets its cadence
(9d). Either copy without its wiring is a skill nothing invokes. Two items of
the release's wiring are kit-side and reach you only at bootstrap — the
bootstrap `Next:` list's design-brief item and the setup payload's hand-back
sentence — so there is nothing of yours to take for them; your manual's row
(9b) is what does their job in a repo that already exists.

After the inventory, the per-skill question for what you DO have. A skill is
prose an agent loads, and adapting it to your repo is the intended way to make
the chain fit. So "is it byte-identical to the release?" is the wrong question
here; the right one is **"what did the kit change, and did I change the same
lines?"**

```sh
S=.agents/skills/implement/SKILL.md          # YOURS — .claude/skills/… if you never moved (9a-bis)
K=.agents/skills/implement/SKILL.md          # the KIT's — canonical since 0.14.0
O=.claude/skills/implement/SKILL.md          # the kit's address before 0.14.0

kit_take "$FROM_REF" "$K" "$WORK/base" 2>/dev/null || kit_take "$FROM_REF" "$O" "$WORK/base" ||
	{ echo "no $K or $O at $FROM_REF"; false; }

kit diff -M "$FROM_REF" "$TO_REF" -- "$O" "$K"   # what the KIT changed; -M pairs
                                                 # the 0.14.0 home move as a rename
diff -u "$WORK/base" "$S"                        # what YOU changed since bootstrap
```

**The kit is always read at `$K` first, whatever your own address.** From
0.14.0 on, the kit's `.claude/skills/<name>` is a symlink, and `git show` at a
tag does not follow one — so `kit show "$REF:$O"` finds nothing at any release
past the move, and the base falls back to `$O` only for a `FROM_REF` older
than it. Listing both paths with `-M` gives one clean content diff either way.
Your own copy's address never has to move — set `$S` to wherever it lives, and
see the 0.14.0 migration note below for making the move if you want it.

Four outcomes, and only one of them needs a human:

- **kit clean, you clean** — nothing to do.
- **kit changed, you clean** — take it: `kit_take "$TO_REF" "$K" "$S"` (the
  kit-side path, written to yours).
- **kit clean, you changed** — nothing to do. Your version stands.
- **both changed** — merge; do not pick a side. The base is the one fetched
  above; `theirs` comes from the canonical path too:

```sh
kit_take "$TO_REF" "$K" "$WORK/theirs" || { echo "no $K at $TO_REF"; false; }
git merge-file "$S" "$WORK/base" "$WORK/theirs"
```

`git merge-file` merges in place and exits non-zero after writing conflict
markers where the two edits overlap. Read those; there is no verbatim check to
fall back on, which is exactly why this category is not automatable.

The takes are guarded even though they only write scratch files, because
`git merge-file` writes **`$S` itself**. Hand it an empty `theirs` — which is
what a plain `kit show … >"$WORK/theirs"` leaves behind when the kit renamed
the skill — and every line of your file reads as "deleted upstream", so the
merge empties it. Guarding a temp file is guarding `$S`, one step removed.

**If you deliberately forked a skill, write the fork down** — one line in a
local article ("`/review-pr`'s Axis-2 section is ours; we replaced the
confirm-list format"). That single line is the whole difference between a fork
and drift, because the next update is run by somebody who was not there. It is
the same rule as Part 1's step 3, moved one category over: the exception lives
in a local article, not in the file the kit owns.

**A new skill is a directory copy, and it is not live until the manual
points at it.**

```sh
kit diff --name-only --diff-filter=A -M "$FROM_REF" "$TO_REF" -- \
	.agents/skills .claude/skills | grep '^\.agents/skills/' || true

kit archive "$TO_REF" .agents/skills/improve-codebase-architecture | tar -x
ln -s ../../.agents/skills/improve-codebase-architecture \
	.claude/skills/improve-codebase-architecture
```

(`-M` over both homes pairs the 0.14.0 move as renames, so mostly only
genuinely new files print — but a file edited heavily across the move can
break the pairing and print anyway, so cross-check the list against 9a's
inventory before copying anything. The grep keeps the kit's `.claude/skills`
symlink entries out of the list. The `ln -s` lays the bridge the harness that reads only
`.claude/skills` needs — skip it if your project migrated and your gate policy
names `.agents/skills`.)

Then add its row to `AGENTS.md`'s quick reference **by hand**. That is not
bookkeeping. The docs gate resolves every `/command` in the manual layer to a
skill directory, so a row whose skill you did not copy fails your next push
(`skill-missing`) — and a skill with no row is a command nobody in this repo
will ever find.

**A removed skill** (`--diff-filter=D`) is the reverse: delete the directory and
the row in the same commit, and let the gate catch the half you forgot.

**A removed file inside a skill** — a sidecar that moved or left — shows up
in the same `D` list, and it is a delete too: remove the old path, take the new
one from the `A` list if there is one, and know that no gate flags the orphan
you leave behind (an unreferenced file is not a violation). The 0.16.0 release
is the first to need this: `diagnose/scripts/hitl-loop.template.sh` became
`diagnose/hitl-loop.template.sh`.

### 9a-bis. The 0.14.0 home move — optional, and reversible by not doing it

At **0.14.0** the kit's own skills moved to `.agents/skills/`, the address the
Agent Skills ecosystem reads, with one committed symlink per skill left at
`.claude/skills/` so the harness that reads only that address still finds
them. Your project's skills did not move: bootstrap put them where your
release put them, and they are yours.

**Staying put is a legal permanent state, not a debt.** A `/command` resolves
at your configured skills directory *or* at `.claude/skills`, forever, and
both addresses are scanned — the gate carries that fallback deliberately, so
a project that never migrates keeps its full coverage and never goes red for
the command web. Migrate only if you want the neutral address: a second agent
tool in the room, or a contributor who looks for skills where the ecosystem
documents them.

**The promise covers the command web, and nothing else — the bound bites
twice.** The fallback resolves `/commands` at either address. A **literal
path** is not a command: it is checked against the filesystem with no
fallback, so a `.agents/skills/…` path in a tree that has no `.agents/skills`
is simply dead, and every file the kit ships that names one carries that dead
path into a staying-put project.

- **At 9a**, the skills themselves. Eleven of the 0.14.0 skill files point at
  a sibling by literal path — most at
  `.agents/skills/LICENSE-mattpocock-skills.md`. Take them into a staying-put
  tree and every gate run prints a `skill-path-missing` **advisory** for each.
  Advisories never fail a build, so this is noise rather than a wall, but it
  is noise on every run until you either migrate or rewrite the paths.
- **At 9b**, the manual. The template writes that same licence pointer as
  `.agents/skills/LICENSE-mattpocock-skills.md`, and in the manual a dead
  literal path is a **violation**, not an advisory — take that row verbatim
  and your next push fails on `path-missing`.

Both have the same fix, and it is the same rule as every other 9b take: the
section is the thing you want, the path inside it is yours to fit.

If you do want it, this is the whole move. It relocates only what is still a
real directory at the old address, laying the bridge as it goes, and it is
safe to re-run — an interrupted migration is finished by running it again:

```sh
mkdir -p .agents/skills
here=$(cd .agents/skills && pwd -P)
# zsh aborts a block on a pattern that matches nothing, where sh and bash
# leave it unexpanded for the guards below to drop. sh never runs this line.
[ -n "${ZSH_VERSION-}" ] && setopt no_nomatch
for d in .claude/skills/*/; do
	[ -d "$d" ] || continue
	s=$(basename "$d")
	[ -L ".claude/skills/$s" ] && continue   # already bridged — nothing to do
	if [ -e ".agents/skills/$s" ] || [ -L ".agents/skills/$s" ]; then
		# One directory reached by two names is NOT a conflict, and must never
		# be reported as one: the advice below would delete the only copy.
		[ -L ".agents/skills/$s" ] && continue
		[ "$(cd ".claude/skills/$s" && pwd -P)" = "$(cd ".agents/skills/$s" && pwd -P)" ] && continue
		echo "SKIPPED $s — a SEPARATE real directory exists at both addresses; delete the one you do not want, then re-run" >&2
		continue
	fi
	mv ".claude/skills/$s" ".agents/skills/$s" &&
		ln -s "../../.agents/skills/$s" ".claude/skills/$s"
done
for f in .claude/skills/*.md; do
	[ -f "$f" ] || continue
	[ -L "$f" ] && continue
	b=$(basename "$f")
	if [ -e ".agents/skills/$b" ] || [ -L ".agents/skills/$b" ]; then
		[ -L ".agents/skills/$b" ] && continue
		[ "$(cd .claude/skills && pwd -P)" = "$here" ] && continue
		echo "SKIPPED $b — a SEPARATE real file exists at both addresses; delete the one you do not want, then re-run" >&2
		continue
	fi
	mv "$f" ".agents/skills/$b" &&
		ln -s "../../.agents/skills/$b" ".claude/skills/$b"
done
# Finish anything a previous interrupted run moved but did not yet bridge.
# The loops above walk the OLD address, so they cannot see those on a re-run.
if [ -d .claude/skills ] && [ ! -L .claude/skills ]; then
	for n in .agents/skills/*/ .agents/skills/*.md; do
		[ -e "$n" ] || continue
		b=$(basename "$n")
		[ -e ".claude/skills/$b" ] || [ -L ".claude/skills/$b" ] ||
			ln -s "../../.agents/skills/$b" ".claude/skills/$b"
	done
fi
sh scripts/check.sh
```

Four notes on what it does **not** do. It never rewrites a symlink, and it
never moves a skill you already moved — so an interrupted run really is
finished by running it again, including the window between the `mv` and the
`ln -s`, which the final loop closes by bridging anything already sitting at
the canonical address unbridged.

It does **not** silently reconcile a skill that exists as a **separate real
directory** at both addresses, which is what a `cp` instead of a `mv` leaves
behind: it prints `SKIPPED` and leaves the choice to you, because which copy
is the real one is not a question a recipe can answer.

It does **not** mistake one directory reached by two names for that conflict
— a bridge laid at the directory level rather than per skill, or a link
pointing back the other way. There is one copy there, so the block passes
over it in silence. This distinction is the reason the `SKIPPED` line says
*separate*: acting on that advice when the two names share a directory would
delete the only copy you have.

And it leaves `claudeMdRefs.skillsDir` in your
`scripts/docs-conformance/config.mjs` alone: that file is yours, both
addresses resolve, and pointing it at `.agents/skills` is a one-word edit you
can make whenever you like — or never.

It relocates every real directory under `.claude/skills/`, whether or not it
holds a `SKILL.md`. That is deliberate: a notes folder you keep beside your
skills stays reachable at both addresses afterwards, and a rule that inspected
contents would strand exactly the files nobody remembers putting there.

**On Windows, check the bridge survived the checkout.** A clone with
`core.symlinks=false` materializes each link as a small text file holding its
target, and the harness that reads `.claude/skills` then sees no skills at all
— silently. The gate warns about exactly that shape (`skill-bridge-broken`);
the fix is a checkout that supports symlinks, or working from WSL, which the
kit's POSIX-sh gates already assume.

### 9b. The manual and the local articles — hunt for missing SECTIONS

`AGENTS.md` was stamped from `constitution/AGENTS.md.template`; each
`constitution/local-*.md` was stamped from its `.template` sibling. All of them
are yours, and bootstrap refuses to run twice, so a release's changes to those
templates reach you only if you carry them.

```sh
kit diff "$FROM_REF" "$TO_REF" -- constitution/
```

Read that diff for **new sections**, not new lines. When a release introduces a
*concept*, it introduces it here, and your stamped copy simply has no paragraph
about it. 0.3.0 → 0.4.0 adds a "Capability tiers" section to the manual template
and a matching block to the workflow article: skip them and your repo has skills
that speak four tier names and no file that says what they mean.

Copy the new sections across by hand, adapting the wording to your repo. Never
re-stamp a template over a manual you have been editing for six months.

**Arriving from 0.16.0 or older, nothing moved in this category either.**

**Arriving from 0.15.0 or older, nothing moved in this category.** The manual
template and the three article templates are byte-identical between the two
releases; the only manual that changed is the kit's own, which never ships.
The one thing to know: the banned-words advisory now reads your glossary
against your manual and articles, so a word your glossary bans and your manual
uses is a warning from the first push — reword it, or carve the sense out (9c).

**Arriving from 0.14.0 or older, four things in this category.** The
engineering article's Architecture section gains three anchor lines —
`**Paradigm**:`, `**Architectural style**:`, `**Context map**:` — each a
decision or an explicit `none — <reason>`, bold label at the start of its own
line, never a bullet; the design-brief advisory warns on a stamped article
that carries none of them, so add the lines (the template's comment beside
each says what it asks) or run `/design-brief` and let it write them. The
manual template's chain section gains two sentences and its quick-reference
table two rows, for `/design-brief` and `/housekeeping` — carry them, or the
skills you took at 9a have no map entry. And the manual's two mentions of the
craft article's count say **thirteen** rules now; the template had read "ten"
since 0.10.0, so yours almost certainly says ten too.

**First check that there is a manual you have been editing.** That headline rule
assumes you stamped the article; plenty of repos never did. Bootstrap leaves
`constitution/local-*.md.template` in place with its marks intact, the manual
points at the `.template` path, and the gate accepts it — an unfilled article is
a legitimate state, not a broken one. For that state the right action is the
*opposite* of the headline: nothing of yours is in the file, so take the new one
whole.

```sh
A=constitution/local-workflow.md
[ -e "$A" ] || A="$A.template"     # never stamped — still the template
SRC=constitution/local-workflow.md.template

if kit show "${FROM_REF}:$SRC" | cmp -s - "$A"; then
	echo "UNSTAMPED $A — nothing of yours in it; take the new template whole"
	kit_take "$TO_REF" "$SRC" "$A"
else
	echo "YOURS     $A — hunt for new SECTIONS, as above"
fi
```

**Note the braces on `${FROM_REF}`, and keep them.** Every `$REF:` in this recipe
is followed by a `$` or by a brace, never by a bare letter, and that is not
style. `zsh` — macOS's default shell, and one an operator will paste this into —
applies **history modifiers** to `$var:x` *inside double quotes*: drop the braces
and the `:c` beginning `constitution/…` is taken as a modifier, so git is handed
`v0.10.0` followed by `onstitution/…`. It resolves nothing, so `kit show` prints
`fatal:` and nothing else — and the `cmp` above then compares your article
against **empty input** and answers `YOURS` for a file that is verbatim the
template. Silence in the wrong arm; the take you needed never runs. `:c` is not
the only one reachable (`:a :e :h :l :q :r :s :t :u :x` and `:g&` all are), which
is why the rule is "brace it", not "avoid the letter c".

The test is "is my copy byte-identical to the `.template` it came from", not
"does its name end in `.template`" — a stamped `.md` nobody has edited yet is the
same case and gets the same answer. Once you have edited it, this returns `YOURS`
by itself and never fires again.

**A section you carry may cite a tree you declined.** 0.4.0's "Capability tiers"
section — the one this release asks you to copy — ends by pointing at
`adapters/claude-code/README.md`, and `adapters` is a path root the docs gate
resolves. If you deleted `adapters/` at bootstrap (9e says that is a supported
answer), copying the section verbatim makes your next push red with
`path-missing`, and neither section warns you. That is the general rule rather
than a special case: **the manual layer is checked, so a paragraph you borrow has
to be true in *your* repo.** Drop the sentence, or re-point it at your own
harness note, as you copy.

### 9c. Templates — take what moved, keep what you removed

**Arriving from 0.16.0 or older, nothing moved in this category.**

**Arriving from 0.15.0 or older, the glossary template's banned-words section
learned one clause.** An entry may end with `Except:` followed by the phrases,
as code spans, in which the banned word is legitimate — `dependency install`
for a word banned in its bootstrap sense — and a use inside one of those
phrases is silent to the banned-words advisory. The template's placeholder
entry shows the shape and its header comment says what the gate now does with
the section. Your glossary is yours: add the clause to any entry the first
warnings show needs it.

**Arriving from 0.14.0 or older, two of your docs gained a section.** The
glossary template grew a **Context map** section — one block per context, one
line per edge, every edge declared from both sides with the same relationship
word and opposite roles — and its banned-words list gained `strategic design`
(say context map). The diary template's Current state table grew a
`**Last housekeeping**` row holding an ISO date, which the housekeeping-due
advisory reads and `/housekeeping` stamps. Both are under `templates/docs/`,
which bootstrap consumed into your `docs/` once: read the release's diff of
the two templates and add the section and the row to your own files by hand,
dating the row your last pass or today.

`templates/workflows/` is copied into `.github/workflows/` **once**, at
bootstrap, and bootstrap never overwrites a file that is already there (it prints
`kept …`). So a release's changes here reach you only by hand.

```sh
kit ls-tree --name-only "$TO_REF" templates/workflows/ | while IFS= read -r wf; do
	dest=".github/workflows/$(basename "$wf")"

	if [ ! -e "$dest" ]; then
		if kit cat-file -e "$FROM_REF:$wf" 2>/dev/null; then
			echo "DECLINED  $dest"        # you had it and removed it
		else
			echo "NEW       $dest"        # first appearance in this release
		fi
	elif kit diff --quiet "$FROM_REF" "$TO_REF" -- "$wf"; then
		echo "UNCHANGED $dest"                # the release did not touch it
	elif kit show "$FROM_REF:$wf" 2>/dev/null | cmp -s - "$dest"; then
		echo "UNTOUCHED $dest"                # yours is the old release's, verbatim
	else
		echo "YOURS     $dest"                # you customized it
	fi
done
```

- **`NEW`** and **`UNTOUCHED`** are both `kit_take "$TO_REF" "$wf" "$dest"` —
  and unlike step 5 there is no mode to carry, because workflow templates are
  plain 100644 files. `UNTOUCHED` is the one that needs the guarded take: the
  destination is a file you already have, and `$wf` came from a listing of
  `$TO_REF`, so the only way it is absent there is a race with a re-tag — rare,
  and it costs you a workflow.
- **`YOURS`** is a three-way merge, exactly as in 9a.
- **`UNCHANGED`** and **`DECLINED`** are *nothing to do*.

**`DECLINED` is the outcome that matters, and it is why this loop asks two
questions instead of one.** "The file is not there" cannot tell *you never had
this* from *you deliberately removed it* — and bootstrap copied every template
that existed at the release you bootstrapped from, so for those, absence is
always a decision. Folding two gates into one CI workflow and deleting the kit's
copy is a normal, supported thing to have done; a recipe that reads that as `NEW`
tells you to re-add a duplicate gate to every PR, and you will do it, because the
line said `NEW`.

If a release *changed* something you declined, the verdict is still `DECLINED` —
re-adopting it is a decision, not an update. Read `kit diff "$FROM_REF" "$TO_REF"
-- "$wf"` if you want to reconsider, and if you take it back, say so where the
decision was written down.

**A workflow can have a file it needs beside it.** 0.4.0's
`ai-review.example.yml` reads `.github/workflows/ai-review-prompt.md` at run
time; take one without the other and you have a workflow that fails on its first
run. Take a template together with its neighbours, and keep the `.example`
suffix until you have added a provider secret — it ships inert on purpose.

`templates/docs/` is a different case: bootstrap consumed it and deleted it. Its
descendants are ordinary files of yours now, and this is where each one lives:

| Template | Bootstrap made it into |
| --- | --- |
| `templates/docs/README.md.template` | `README.md` |
| `templates/docs/PULL_REQUEST_TEMPLATE.md` | `.github/PULL_REQUEST_TEMPLATE.md` |
| `templates/docs/diary.md.template` | `docs/diary.md` |
| `templates/docs/domain-glossary.md.template` | `docs/domain-glossary.md` |
| `templates/docs/adr/INDEX.md.template` | `docs/adr/INDEX.md` |
| `templates/docs/adr/NNNN-template.md` | `docs/adr/NNNN-template.md` |
| `templates/docs/specs/README.md` | `docs/specs/README.md` — the living specs' starter, new at 0.49.0 |

A kit change to one you have is something you may read and borrow from; it is
never something to copy over the top. One you do **not** have is either a
starter newer than your bootstrap — `docs/specs/README.md` for anyone who
bootstrapped before 0.49.0 — or one you removed, and the same two questions as
the workflow loop tell them apart:

```sh
kit ls-tree -r --name-only "$TO_REF" templates/docs/ | while IFS= read -r t; do
	case "$t" in
	templates/docs/README.md.template) dest=README.md ;;
	templates/docs/PULL_REQUEST_TEMPLATE.md) dest=.github/PULL_REQUEST_TEMPLATE.md ;;
	*)
		dest="docs/${t#templates/docs/}"
		dest="${dest%.template}"
		;;
	esac

	if [ ! -e "$dest" ]; then
		if kit cat-file -e "${FROM_REF}:$t" 2>/dev/null; then
			echo "DECLINED  $dest"        # bootstrap made it and you removed it
		else
			echo "NEW       $dest"        # newer than your bootstrap: take it
		fi
	elif kit diff --quiet "$FROM_REF" "$TO_REF" -- "$t"; then
		echo "UNCHANGED $dest"
	else
		echo "CHANGED   $dest"            # yours: read the diff of $t and borrow
	fi
done
```

`NEW` is a take into a directory that may not exist yet —
`mkdir -p docs/specs && kit_take "$TO_REF" templates/docs/specs/README.md
docs/specs/README.md` for the living specs' starter, which holds no
requirement, so the gate stays green with it. A `NEW` file ending `.template`
carries the double-brace marks bootstrap would have filled: fill them by hand
as you take it. `CHANGED` is the read-and-borrow above, and `UNCHANGED` and
`DECLINED` are nothing to do.

### 9d. Policy files — never overwrite, and never guess which ref has them

**This is the category that breaks silently**, because both failure modes are
quiet. Overwrite the file and your provider and model choices vanish with no
error. Skip it and the release's new shared code reads a key you never set,
resolves it to empty, and carries on.

The policy files are the ones `VERSION` names in its "everything NOT shared"
comment, and the list is deliberately reproduced here with what each one *is*,
because both facts change what you do with it:

| Policy file | In the kit it is | Compared by |
| --- | --- | --- |
| `scripts/guards.config.sh` | a file at that path | key sets (`NAME=`), then the diff |
| `scripts/agents.config.sh` | a file at that path, since 0.4.0 | key sets (`NAME=`), then the diff |
| `scripts/docs-conformance/config.mjs` | a file at that path | reading the diff |
| `scripts/docs-conformance/local-vocabulary.mjs` | **only a `.template`** | reading the diff of the `.template` |
| `scripts/vocab.config.sh` | a file at that path, since 0.25.0 — and shipped **filled** | key sets (`NAME=`), then the diff of the values |
| `scripts/trace.config.sh` | a file at that path, in new-project bootstraps since 0.25.0, adopted repos since 0.29.0, and named here since 0.29.0 — shipped **empty** | key sets (`NAME=`), then the diff |

The fourth row is not a footnote. It is why the first question below has to be
asked about *both* refs rather than one.

**Arriving from 0.29.0 or older, the vocabulary policy file gains one field.**
`scripts/vocab.sh` (shared, changed at 0.30.0) now ships an `author-kind`
vocabulary — `bot`, `human` — for the line `/pr-iterate` stamps from the
forge's own author data before it triages a review comment. If you took
`scripts/vocab.config.sh` as yours, add the entry from the kit's copy at
`${TO_REF}`; without it the checker still holds the line to its shipped
default, and a copy that redeclares the field list without the entry is the
one state where `Author-kind:` goes unchecked. The checker's header and usage
text also say what it has always done: it takes bare `Field: value` lines,
and a line wearing a list marker or emphasis is not a decision line to it.

**Arriving from 0.28.0 or older, the trace's policy file becomes a row, and
one line in it turns tracing on.** `scripts/trace.config.sh` is what
`scripts/trace.sh` — shared from this release — reads to decide whether to
write anything. Ask YOUR tree, not only the kit's ref: a repo that adopted the
kit before 0.29.0 has no copy even though the kit had one at `${FROM_REF}`.
Missing in your tree, take it whole
(`kit_take "${TO_REF}" scripts/trace.config.sh scripts/trace.config.sh`); present,
diff its keys as below — 0.29.0 added `TRACE_NUMBERED_TYPES` and
`TRACE_AGENT_WAIT_MS`, 0.27.0 `TRACE_TOOLS` and `TRACE_PRICES_STALE_DAYS`, all
shipped empty. It ships with every value empty, so
until you decide otherwise the chain's emits, the dispatcher's spawn records
and the adapter's hooks write nothing. **To turn tracing on, this is the one
line** — plus the ignore rule, because a trace is findings, reasons and prompts
in plain text, and it is never meant to be committed:

```sh
sed -i.bak "s|^TRACE_DIR=''|TRACE_DIR='.trace'|" scripts/trace.config.sh && rm scripts/trace.config.sh.bak
printf '.trace/\n' >>.gitignore
sh scripts/trace.sh emit kind=note reason='tracing on'   # silent, exit 0
ls "$(sh scripts/trace.sh dir)/events"                    # a day file now holds it
```

A relative `TRACE_DIR` resolves against the root checkout, so an emit from a
linked worktree lands beside the root's `.git`. The other keys are refinements
you can leave empty: `TRACE_TOOLS` captures every tool call (volume and
privacy both grow — read its comment first), `TRACE_NUMBERED_TYPES` holds your
forge's numbered references to one spelling, `TRACE_AGENT_WAIT_MS` bounds how
long a subagent-stop hook waits for its transcript, and the price table with
its `TRACE_PRICES_STALE_DAYS` window prices tokens on read.

**Arriving from 0.27.0 or older, one skill joins and nothing in Part 1
moves.** `/retro` is the reader of the decision trace: over a window it
answers a fixed set of questions — tier calibration, review signal, recurring
failures, diagnosis calibration, spend, chain health, aim calibration — and
hands each finding to `/to-tickets` as a candidate; it never edits a skill.
Step 9a's inventory finds it for you as a missing name: take
`.agents/skills/retro/` whole and lay its bridge. It reads only what
`scripts/trace.sh` wrote, so it is inert until you set `TRACE_DIR` in your
trace policy file — a project that does not trace gains a command that says
it has nothing to read. `/housekeeping`'s checklist gained the line that
asks whether a retro ran inside its window; merge that hunk if you keep the
skill, drop it if you do not.

**Arriving from 0.26.0, the catalogue slice changes this recipe only in
Part 1; no mechanism joins the shared layer yet.** Fresh bootstraps retain
`scripts/catalogue.sh`, `scripts/catalogue.config` and `scripts/catalogue.md`:
canonical skill content can be compared with declared active roots, with exact
path case and executable-reference checks. The declaration belongs to the
repository or caller; admission proves filesystem identity, not model loading.
Existing consumers can inspect those files in the kit, but the lifecycle wave's
final release supplies their adoption recipe. This slice introduces no scope,
review, delivery or resume state. Its release bump keeps this revised recipe
reachable while the operational mechanisms remain outside the manifest.
The tag also includes already-landed trace changes outside Part 1:
`scripts/trace.sh` reports unsupported schemas distinctly and warns on stale
pricing when configured. `adapters/claude-code/README.md` and its
`hooks/hook.lib.sh`, `hooks/tool-payload.mjs`, and `hooks/tool-post.sh` add opt-in
tool-call capture with private JSON blobs. Inspect and adopt these through
Part 2, preserving your trace policy; wiring `PostToolUse` and
`PostToolUseFailure` and enabling `TRACE_TOOLS` are deliberate consumer choices.
Never copy the kit's `scripts/trace.kit.config.sh` or
`scripts/trace-prices.kit.sh` as consumer policy.

**Arriving from 0.25.0 or older, nothing in the layer changes shape — one
worked example re-pins.** The kit's own manual and the manual template you
were stamped from gained a paragraph naming the **`judge`** task domain by
its contract: state and typed questions in, typed answers with per-option
probabilities out, in two shapes a mapping answers one of — *decide* among
supplied options, *rank-or-verify* over supplied candidates. It ships
UNMAPPED and the kit maps it for nobody, so nothing you run changes; map
`AGENT_TIER_MECHANICAL_JUDGE` in `scripts/agents.config.sh` only if you have
a typed-decision model you trust, and read the kit's ADR-0010 (its
`docs/adr/0010-…`, in the kit's repository) first for the one rule that
comes with it: a decider is never handed a verification, and no typed judge
takes the review verdict. Part 2's worked example below re-pins because it
quotes the manual template's own diff stat.

**Arriving from 0.24.0 or older, one policy file joins, and it arrives
filled.** `scripts/vocab.config.sh` holds the vocabularies that
`scripts/vocab.sh` (shared, new at 0.25.0) refuses a decision line outside
of — one closed token set per field the chain stamps, in canonical order, and
the cross-field rules. Unlike every other row above it ships with the kit's
own words in it, because a vocabulary is the kit's to name where a model id
or a source pattern is not: it does not exist at `${FROM_REF}`, so take it whole
(`kit_take "${TO_REF}:scripts/vocab.config.sh" scripts/vocab.config.sh`) and
edit it as yours from then on. A consumer that never takes it is held to the
same words all the same — the checker carries them as its defaults — so the
only silent state is a stale copy of your own. The tier entry is the
resolver's, read by the checker and never widened; the file's header says so.

**Arriving from 0.16.0 or older, nothing moved in this category.** The kit's
own glossary carved out `config-as-data` as a qualified use; yours is yours.

**Arriving from 0.15.0 or older, `config.mjs` gained one policy section, and
the tier policy file may want one line.** `bannedWords` names the glossary the
advisory reads (default `docs/domain-glossary.md`) and the files it leaves
alone (default: the two shared articles under your constitution directory,
because they are not yours to reword); both are read with defaults when
absent. And `scripts/agents.config.sh` — yours, never overwritten — may map
`AGENT_TIER_REVIEWER_SELF_IMPLEMENTED` to a model that differs from your
reviewer's, so `sh scripts/agents.lib.sh reviewer self-implemented` has an
answer when the session that wrote a diff is the reviewer tier's own model;
unmapped, it falls back to the reviewer tier and `/implement` says to report
that the review shares the author's model.

**Arriving from 0.14.0 or older, `config.mjs` gained two policy sections**:
`designBrief` (which article the design-brief advisory reads; the default is
the engineering article) and `housekeepingDue` (`windowDays`, default 30, and
an optional `diary` path). Both are read with defaults when absent, so a
policy file that predates them still works; take them so the cadence and the
article are yours to change, and so the comment beside `windowDays` says why
a month.

**Ask about BOTH refs before you write anything.** Two questions, three answers
— and the third one is the one that eats files:

```sh
C=scripts/agents.config.sh

if kit cat-file -e "${FROM_REF}:$C" 2>/dev/null; then
	echo "MERGE   $C existed at $FROM_REF — diff the keys, below"
elif kit cat-file -e "${TO_REF}:$C" 2>/dev/null; then
	echo "ADD     $C is new at $TO_REF — copy it whole"
	kit_take "$TO_REF" "$C" "$C"
else
	echo "STAMPED $C — the kit has no such path at either ref; see below"
fi
```

`MERGE` is the 0.4.0 → 0.65.0 case for this file, and `ADD` is the 0.3.0 → 0.65.0
one: `scripts/agents.config.sh` did **not** exist at 0.3.0 — it arrived with the
0.4.0 wave's tier resolver — so a 0.3.0 consumer copies the whole file and then
edits it. Nothing is at risk there, which is precisely why it is worth checking
rather than assuming: the same path is a destructive overwrite for a consumer who
*did* have it.

**`STAMPED` is not a rare third case — it is half the list above.**
`scripts/docs-conformance/local-vocabulary.mjs` is yours because bootstrap
*stamped* it from `local-vocabulary.mjs.template`, and the kit therefore has that
path at **neither** ref, in every release there has ever been. A branch that asks
only about `FROM_REF` reads that `no` as "then it is new upstream", prints
`ADD … copy it whole` — which was never true of this path — and runs a take that
cannot succeed. It is the same `.template`-versus-stamped asymmetry 9b handles
one category over, and 9d has to answer it the same way: **the file to compare
against is the `.template`**, and there is nothing at `$C` to take.

```sh
kit diff "$FROM_REF" "$TO_REF" -- "$C.template"   # what the kit changed in the SOURCE
```

Read that diff and carry across what applies, exactly as in 9b. Never re-stamp
the template over the file — the whole point of stamping is that the copy became
yours.

Note what `kit_take` bought in the `ADD` arm even so. The obvious spelling,
`kit show "$TO_REF:$C" >"$C"`, truncates `$C` before `kit` runs, so the moment
the two questions above are asked in the wrong order — or a release renames the
path — the consumer's policy file is zero bytes and the only copy is in git history.
Step 0 explains the shape; this is the branch where it was first paid for.

**For the MERGE case, never `kit show >` the file.** How you compare depends on
what shape the policy file is, and the four above are two different shapes:

**The `.sh` policy files are `NAME=value` lines, so diff the key sets.**

```sh
keys() { sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$1" | sort -u; }

kit_take "$TO_REF" "$C" "$WORK/config.new" || { echo "no $C at $TO_REF"; false; }
keys "$WORK/config.new" >"$WORK/keys.new"
keys "$C" >"$WORK/keys.mine"

# A key extractor that finds NOTHING has not found "no new keys" — it has failed
# to read the file, and the two `comm`s would then print nothing whatever the
# truth is. So they only run when there is something to compare.
if [ -s "$WORK/keys.new" ]; then
	comm -13 "$WORK/keys.mine" "$WORK/keys.new"   # keys the RELEASE expects, you lack
	comm -23 "$WORK/keys.mine" "$WORK/keys.new"   # keys only you have — yours, or removed upstream
	kit diff "$FROM_REF" "$TO_REF" -- "$C"        # and READ this: a key shipped commented out
	                                              # is no NAME= line, so the comms cannot see it
else
	echo "keys(): no NAME= lines in $C — wrong tool for this file; read the diff" >&2
	false
fi
```

**The key sets are not the whole answer, so the block prints the file's diff
too.** A key the kit ships *commented out* — an opt-in it documents but will
not set for you — is no `NAME=` line on either side. 0.53.0's reviewer
fallback is the case that was missed in the field: the release added
`#   AGENT_TIER_REVIEWER_FALLBACK='<a second reviewer> <a third>'` to
`scripts/agents.config.sh`, the two `comm`s printed nothing, and the key was
visible only in the diff. Read it for every `.sh` policy file, after the
`comm`s.

Add each missing key to your file **with your value**, and bring the kit's
comment block for it across so the next reader knows what it is for. An unset
key is not automatically a bug — `agents.config.sh` ships all four tiers empty
and unset is a documented working state — but it has to be a key you decided to
leave unset, not one you never saw.

**The `.mjs` policy files are read, not extracted — and that is not a gap to fill
later.** `keys()` above understands shell assignments only, so pointing it at
`config.mjs` or `local-vocabulary.mjs` yields an empty set, and two empty sets
`comm` as "nothing missing" no matter what changed. The guard line above is what
turns that silence into a sentence. But **a smarter extractor would not fix
this**, because the changes that matter in these files are not new keys:

```sh
kit diff "$FROM_REF" "$TO_REF" -- scripts/docs-conformance/config.mjs
```

0.5.0 is the worked example, and it is the one this method missed in the field.
`constitution/shared-code-craft.md` joined the shared layer, and the consumer's
own `config.mjs` had to add that path to the **array under `portability.files`**
or the gate would never check the new article for vocabulary leaks. Every key in
that file was already present at both refs. A key-set diff reports `(nothing)`
and is telling the truth about keys while being useless about the release.

So: read the diff, with the same question 9b asks of the manual — *what does
the release now expect this file to say?* Then edit yours by hand. It is the
smallest of the five categories and the one where being told a false "nothing
to do" costs the most, because the thing it silently skips is a gate that stops
checking.

Then re-read `scripts/agents.lib.sh` (or whatever shared code reads the policy file).
It is shared layer, so Part 1 already replaced it: what it reads *now* is the
authority on what your policy file has to provide.

### 9e. Adapters — opt-in, whole-directory

**Arriving from 0.28.0 or older, the Claude Code adapter's hooks changed.**
If you kept the `hooks` directory of `adapters/claude-code`, take it whole as this
category says: `subagent-stop.sh` and `hook.lib.sh` now wait, up to
`TRACE_AGENT_WAIT_MS` from your trace policy file (empty: no wait, as before),
for a subagent's transcript to hold its final message before reading its
usage, and record the absence rather than a partial sum when it never does;
`adapters/claude-code/README.md` says a live payload is compact. Dormant for
a consumer who wired no hooks.

**Arriving from 0.23.0 or older, the dispatcher gained an exit status**: 69
(EX_UNAVAILABLE) now means the agent harness a tier names is not installed
here, where that used to be exit 2 alongside your own usage errors. If you
branch on the dispatcher's status anywhere, a check for `2` that meant "the
crossing is missing" needs to become `69`; `2` keeps only the caller's own
mistakes, and `3` — no agent harness mapped at all — is unchanged. On 69,
stdout is the model the tier maps to — empty when it maps only an agent
harness, the same "nothing means inherit" the status-3 path uses — so you can
spawn it yourself; the
dispatcher deliberately does not do that for you, because a review that
quietly ran on the author's own model is the thing the tiers exist to
prevent. Say what ran, in whatever reports the work.

**Arriving from 0.22.0 or older, two corrections**: the wiring example in the
paragraph below this one used to resolve a *tier* into `AGENT_SESSION_MODEL`,
which is the assumption the rule it wires exists to remove — if you copied it,
replace the substitution with the model your session actually runs on, or the
refusal silently never fires. And the housekeeping-due advisory no longer calls
a row dated today future-dated when your clock is ahead of UTC; if you saw that
warning near midnight, it was this and it needed no action from you.

**Arriving from 0.21.0 or older, the resolver can refuse a reviewer that is
the session's own model — if you wire it**: `scripts/agents.lib.sh` gained one
rule, and it is **opt-in and inert until a caller uses it**. Taking the delta
in step 5 changes nothing on its own. To adopt it, whatever spawns your
reviewer must set `AGENT_SESSION_MODEL` to the model the calling session is
running on, spelled **exactly as your `scripts/agents.config.sh` spells it**
— the comparison is literal, because folding ids to a family word would mean
guessing each vendor's id order and a wrong guess refuses two different models
as if they were one:

```sh
AGENT_SESSION_MODEL='<the id your policy gives the model THIS session runs on>' \
  sh scripts/agents.lib.sh reviewer self-implemented
```

That value is the session's **actual** model, never a tier's answer. Resolving
a tier there — `AGENT_SESSION_MODEL="$(sh scripts/agents.lib.sh planner)"` —
re-introduces exactly the assumption this rule removes: it is right only when
the session happens to be a spawn of that tier, and on any other session it
names a model nobody is running, so an answer equal to the real one is handed
straight back unrefused.

With that set, a `reviewer` answer equal to the session's model falls back to
the plain reviewer tier with a warning, and when nothing differs the resolver
prints nothing and says the review would share the author's model — the same
"nothing means inherit" contract an unmapped tier already has. Where it pays
is a `reviewer self-implemented` mapping, which answers one fixed model chosen
assuming your sessions run on a different one: the day they run on that one,
it was handing the author its own diff. Nothing in the shipped skills sets the
variable yet, so wiring it is yours. `/implement` also gains a line: a
ticket's `Tier:` outranks a skill's `metadata.phase`.

**Arriving from 0.20.0 or older, every skill gained a phase, and two changed
their prose**: each `SKILL.md` now carries a `metadata.phase` line — one of
`planner`, `implementer`, `tester`, `mechanical`, `reviewer` — inside the
`metadata` block the Agent Skills specification defines. It is a claim about
the work, not about a vendor, so it is yours to read with your own tooling.
That includes `/dogfood` if you took the optional skill at bootstrap — it is
`reviewer` work, and `VERSION`'s note deliberately does not spell that one,
because a project that declined it would inherit a dead reference. Map the
phase to a model the way you map a tier in `scripts/agents.config.sh`.
Four of the five phases ARE tier names, so they map directly; the fifth does
not, because the tier vocabulary is closed:

| phase | resolves as | policy variable |
| --- | --- | --- |
| `planner` | tier `planner` | `AGENT_TIER_PLANNER` |
| `implementer` | tier `implementer` | `AGENT_TIER_IMPLEMENTER` |
| `tester` | tier `implementer`, domain `tests` | `AGENT_TIER_IMPLEMENTER_TESTS` |
| `mechanical` | tier `mechanical` | `AGENT_TIER_MECHANICAL` |
| `reviewer` | tier `reviewer` | `AGENT_TIER_REVIEWER` |

No shipped script reads `metadata.phase` yet — this release ships the
declaration, and reading it is yours or a later release's.
Take the delta for every skill in step 9a; a skill you have forked keeps your
prose, and adding the two frontmatter lines by hand is the whole of it.
`/to-prd` and `/to-tickets` also changed substantially this release (the
Objective, Scenarios, Alternatives Considered and Open Issues sections; the
open-issue gate and feedback-first ordering) — `VERSION`'s 0.21.0 note has the
detail, and those two are worth reading rather than merging blind if you have
edited them.

**Arriving from 0.16.0 or older, six adapter documents changed a phrase**
(`adapters/README.md`, `claude-code/README.md`, `node-ts/README.md`,
`node-ts/INSTALL.md`, `node-ts/evals/README.md`, `ruby/README.md`): the same
rewording as the skills, prose only. Whole-directory copy as always, if you
kept the tree.

`adapters/` is reference material. Nothing in it runs, nothing was stamped from
it, and no gate reads it. If you deleted the tree at bootstrap — a documented,
supported answer — a release's changes there are none of your business.

**With one exception, and 9b is where it reaches you.** No gate reads the
adapters, but the gate absolutely reads the *manual*, and a section you copy in
9b may cite an `adapters/…` path. A declined tree therefore constrains what your
manual may say: cite a file in a tree you do not have and step 10 goes red with
`path-missing`. Declining is a standing decision, and the manual layer has to
keep agreeing with it.

If you kept it, take whole directories:

```sh
kit archive "$TO_REF" adapters | tar -x
```

Never merge a single adapter file. Each directory is one worked wiring that has
to stay internally consistent; half of the release's on top of half of yours is a
configuration nobody has ever run.

### 9f. Everything else bootstrap copied — yours, and taken by what you did to it

Some files bootstrap copied fit none of the five categories above: the docs
harness's own `scripts/docs-conformance/README.md` and its fixture tests under
`scripts/docs-conformance/test/`, the worker prompts under `.agents/prompts/`,
the hooks under `.githooks/`, `.gitignore`, and the scripts that sit beside
the shared layer without being in it (`scripts/task.sh`, `scripts/catalogue.sh`,
`scripts/worktree-cleanup.sh` and their notes). Step 8 marks each with `9f`.
They are yours like the rest of Part 2 — copied once, edited if you chose to —
so the question is the 9a one, asked of a single file:

```sh
grep '^9f ' "$WORK/changed.steps" | cut -c6- | while IFS= read -r f; do
	if ! kit cat-file -e "${TO_REF}:$f" 2>/dev/null; then
		echo "REMOVED   $f"        # the kit deleted it: delete yours unless you use it
	elif [ ! -e "$f" ]; then
		if kit cat-file -e "${FROM_REF}:$f" 2>/dev/null; then
			echo "DECLINED  $f"    # you had it and removed it
		else
			echo "NEW       $f"    # newer than your bootstrap: take it whole
		fi
	elif kit show "${FROM_REF}:$f" 2>/dev/null | cmp -s - "$f"; then
		echo "UNTOUCHED $f"        # the old release's copy, verbatim: take it
	else
		echo "YOURS     $f"        # you edited it: three-way, as 9a
	fi
done
```

- **`NEW`** is `kit archive "$TO_REF" -- "$f" | tar -x`, as step 5 takes a
  file, because a new file's mode has to arrive with it — a hook under
  `.githooks/` taken through a redirect lands without its executable bit, and
  git skips it in silence. Take one only if you use what it is for: a fixture
  test is worth taking if you run the harness's tests.
  `scripts/docs-conformance/test/living-spec.test.mjs` is the one that was
  missed in the field — created at 0.49.0, so a consumer bootstrapped before
  that has none, and a note telling you to edit it means take it whole.
- **`UNTOUCHED`** is `kit_take "$TO_REF" "$f" "$f"`: the file is already
  yours, and keeps its mode.
- **`YOURS`** is the three-way of 9a, with `$K` and `$S` both set to `$f`.
- **`REMOVED`** and **`DECLINED`** are nothing to take; a removed file you
  still have is yours to keep or delete.

## Step 10 — verify with the gate, then commit

Part 2 has no verbatim claim to check, so the gate is the check — and it is not a
formality here. It is what catches the quick-reference row whose skill you did not
copy, the article the manual points at that you never created, and the path
reference that moved.

```sh
sh scripts/check.sh
```

```sh
git add -A
git commit -m "chore: adopt kit ${TO_REF#v} outside the shared layer"

rm -rf "$WORK"   # the bare clone and both manifests — the update is over
```

That `rm` belongs *here* and nowhere earlier: `$WORK` holds the bare clone, both
manifests and `changed.yours`, and every step from 8 on reuses them. Nothing
after it does: the verbatim check you can run any time is step 7's own form,
which makes its own clone.

Note it in `docs/diary.md` alongside the Part 1 entry. Part 2 is where the
release's behaviour actually changed, so it is the half a future reader will want
explained.

## Optional skills — adopting or declining one after bootstrap

The kit ships exactly one **optional** skill, `/dogfood`, and bootstrap asked
about it **once, at bootstrap**. There is no second question: bootstrap deleted
itself, and no update step will ever ask again. So both directions are manual,
and both are more than a directory.

**Adopting `/dogfood` later** — you now have a runnable user-facing surface:

```sh
kit archive "$TO_REF" .agents/skills/dogfood | tar -x
ln -s ../../.agents/skills/dogfood .claude/skills/dogfood
kit_take "$TO_REF" constitution/local-product.md.template \
	constitution/local-product.md.template
```

Then, by hand, the part no command can do for you — **in this order**:

1. **Fill in the DOGFOOD DECLARATION in `constitution/local-product.md.template`
   and drop the `.template` suffix**, exactly as with the other local articles.
   Until it is filled in, the skill stops and says so, which is correct: a
   guessed persona produces a report about a user who does not exist.
2. **Then copy the manual's `/dogfood` lines across, naming the `.md` you just
   produced.** `kit show "${TO_REF}:constitution/AGENTS.md.template"` shows exactly
   which lines bootstrap would have kept — they sit between
   `<!-- DOGFOOD:BEGIN -->` and `<!-- DOGFOOD:END -->`, and there are three of
   them: the quick-reference row, the paragraph that introduces the skill, and
   the article-layer pointer. **In the kit those lines name
   `constitution/local-product.md.template`, because in the kit it is still a
   template.** In your repo it is not. Re-point them at
   `constitution/local-product.md` as you copy — the same "change its pointer to
   the `.md` path" the manual's own kit note asks for.

Do it in the other order — rows first, rename second — and the gate stops you:
the pointer names a path you have just renamed away (`path-missing`) and the
article nobody points at is `article-unreferenced`. That is the kit
working, and it is still two steps you can simply take in the right order.

3. **Restore the skill's gate exemption.** Bootstrap stripped it when you
   declined: re-add `"docs/dogfood-reports/"` to `skillPaths.exemptTokens` in
   `scripts/docs-conformance/config.mjs` (yours, so this is an ordinary edit),
   or accept a standing `skill-path-missing` advisory until the skill's first
   run creates that directory. The gate stays green either way — the advisory
   channel is why — but a warning you have decided to ignore is training, and
   the wrong kind.

```sh
sh scripts/check.sh
```

**Declining it later** is the exact reverse, and the order matters just as much —
references first, then the files, so the gate is red in between rather than green
over a half-removal. So: remove *every* mention from the manual layer — the
quick-reference row, the paragraph that introduces it, and the article-layer
pointer — and only then delete what they pointed at.

```sh
rm -rf .agents/skills/dogfood .claude/skills/dogfood
rm -f constitution/local-product.md constitution/local-product.md.template
```

```sh
sh scripts/check.sh
```

**The gate is the proof that nothing dangles.** A `/dogfood` mention left
anywhere in the manual layer with no skill directory behind it is `skill-missing`
and fails the push — which is the point. A half-removed skill is worse than
either whole state: the manual promises a command the repo does not have, and
every session loads that promise.

---

## Worked example — Part 2

The same test, a different consumer. This one bootstrapped at shared-layer
**0.3.0** with `/dogfood` declined, adapted `/to-tickets` with a local note (a
legitimate edit — skills are yours), **deleted `.github/workflows/tdd-pairing.yml`
on purpose** after folding that gate into its own CI, and has just finished Part
1: its `VERSION` says 0.65.0 and `scripts/agents.lib.sh` is on disk — and the gate
is **red** with `article-unreferenced`, because Part 1 landed the code-craft
article and nothing in this consumer's manual points at it yet. That pointer is
step 9b's hand edit, which is the point.

> **The file list below is this pair of releases, and this consumer.** What
> `changed.yours` prints is every non-shared path the kit touched between *your*
> two refs — a real `v0.3.0 → v0.65.0` clone prints more lines than the fixture
> here, because the fixture models only the parts of the wave the example is
> about. Read the transcript for the **shape** of each decision, never as a list
> to check yours against: a line you have and this one does not is normal.

**And nothing the release is for has arrived.** `tests/docs-demo.sh` asserts
exactly that before running a single Part 2 command: no `scripts/agents.config.sh`,
no `/improve-codebase-architecture`, no review workflow, no Deliver phase in
`/implement`, and a resolver that runs, prints nothing, and exits 0 — because an
unmapped tier is a working state. Beyond the article's red gate, the half-update
is *silent*, which is why that red is the only alarm that fires. Part 2 is what
fixes all of it:

```console
$ # step 8 — every path the kit changed outside the layer, by the step that takes it
9a   .agents/skills/LICENSE-mattpocock-skills.md
9a   .agents/skills/design-brief/BRIEF-FORMAT.md
9a   .agents/skills/design-brief/SKILL.md
9a   .agents/skills/diagnose/SKILL.md
9a   .agents/skills/diagnose/hitl-loop.template.sh
9a   .agents/skills/dogfood/SKILL.md
9a   .agents/skills/explain-diff/MICROWORLDS.md
9a   .agents/skills/explain-diff/SKILL.md
9a   .agents/skills/grill-me/SKILL.md
9a   .agents/skills/grill-with-docs/ADR-FORMAT.md
9a   .agents/skills/grill-with-docs/GLOSSARY-FORMAT.md
9a   .agents/skills/grill-with-docs/SKILL.md
9a   .agents/skills/housekeeping/CHECKLIST.md
9a   .agents/skills/housekeeping/SKILL.md
9a   .agents/skills/implement/COVERS.md
9a   .agents/skills/implement/DISPATCHED-REVIEW.md
9a   .agents/skills/implement/SKILL.md
9a   .agents/skills/implement/STAMP.md
9a   .agents/skills/improve-codebase-architecture/DEEPENING.md
9a   .agents/skills/improve-codebase-architecture/INTERFACE-DESIGN.md
9a   .agents/skills/improve-codebase-architecture/LANGUAGE.md
9a   .agents/skills/improve-codebase-architecture/PRESENTING.md
9a   .agents/skills/improve-codebase-architecture/SKILL.md
9a   .agents/skills/merge-train/SKILL.md
9a   .agents/skills/pr-iterate/DISMISSALS.md
9a   .agents/skills/pr-iterate/RELEASE-BOUND.md
9a   .agents/skills/pr-iterate/SKILL.md
9a   .agents/skills/prototype/SKILL.md
9a   .agents/skills/retro/QUESTIONS.md
9a   .agents/skills/retro/SKILL.md
9a   .agents/skills/review-pr/SKILL.md
9a   .agents/skills/review-pr/lens-api-crud.md
9a   .agents/skills/review-pr/lens-pattern.md
9a   .agents/skills/review-pr/lens-reuse-dry.md
9a   .agents/skills/review-pr/lens-security.md
9a   .agents/skills/review-pr/lens-simplicity.md
9a   .agents/skills/review-pr/lens-test-hygiene.md
9a   .agents/skills/tdd/SKILL.md
9a   .agents/skills/tdd/deep-modules.md
9a   .agents/skills/tdd/interface-design.md
9a   .agents/skills/tdd/mocking.md
9a   .agents/skills/tdd/refactoring.md
9a   .agents/skills/tdd/tests.md
9a   .agents/skills/to-prd/SKILL.md
9a   .agents/skills/to-tickets/RETRO-CANDIDATES.md
9a   .agents/skills/to-tickets/SKILL.md
9a   .agents/skills/worktree-cleanup/SKILL.md
9a   .claude/skills/LICENSE-mattpocock-skills.md
9a   .claude/skills/design-brief
9a   .claude/skills/diagnose
9a   .claude/skills/dogfood
9a   .claude/skills/explain-diff
9a   .claude/skills/grill-me
9a   .claude/skills/grill-with-docs
9a   .claude/skills/housekeeping
9a   .claude/skills/implement
9a   .claude/skills/implement/SKILL.md
9a   .claude/skills/improve-codebase-architecture
9a   .claude/skills/merge-train
9a   .claude/skills/pr-iterate
9a   .claude/skills/prototype
9a   .claude/skills/retro
9a   .claude/skills/review-pr
9a   .claude/skills/tdd
9a   .claude/skills/to-prd
9a   .claude/skills/to-tickets
9a   .claude/skills/worktree-cleanup
9b   constitution/AGENTS.md.template
9b   constitution/local-engineering.md.template
9b   constitution/local-product.md.template
9b   constitution/local-workflow.md.template
9c   templates/docs/specs/README.md
9c   templates/workflows/ai-review-prompt.md
9c   templates/workflows/ai-review.example.yml
9d   scripts/agents.config.sh
9e   adapters/claude-code/README.md
9f   .agents/prompts/README.md
9f   .agents/prompts/cheap-reads.md
9f   .agents/prompts/implement-worker.md
9f   .agents/prompts/review-worker.md
9f   scripts/catalogue.md
kit  AGENTS.md
kit  EXCLUSIONS.md
kit  README.md
kit  VERSION
kit  bootstrap.sh
kit  docs/adr/0011-task-local-contracts-bound-the-lifecycle.md
kit  docs/adr/0015-a-release-is-tagged-by-its-landing-before-main-is-judged.md
kit  docs/diary.md
kit  docs/domain-glossary.md
kit  setup/agent-bootstrap.md

$ # 9a — the INVENTORY first: state, not delta (one is a decline, one is a gap)
$ comm -23 "$WORK/skills.manifest" "$WORK/skills.installed"   # skills you LACK
dogfood
improve-codebase-architecture

$ # 9a — /implement: the kit changed it, we did not
$ kit diff -M --stat "$FROM_REF" "$TO_REF" -- "$O" "$K"
 .agents/skills/implement/SKILL.md | 66 +++++++++++++++++++++++++++++++++++++++
 .claude/skills/implement/SKILL.md | 44 --------------------------
 2 files changed, 66 insertions(+), 44 deletions(-)
$ diff -u "$WORK/base" "$S" | head -1
(no local edit — take it)
  took    .claude/skills/implement/SKILL.md

$ # 9a — /to-tickets: BOTH changed. Three-way, not a copy.
$ git merge-file "$T" "$WORK/base" "$WORK/theirs"
  merged clean — the kit's delta and our local note both survive

$ kit diff --name-only --diff-filter=A -M "$FROM_REF" "$TO_REF" -- .agents/skills .claude/skills | grep '^\.agents/skills/' || true
.agents/skills/LICENSE-mattpocock-skills.md
.agents/skills/dogfood/SKILL.md
.agents/skills/implement/SKILL.md
.agents/skills/improve-codebase-architecture/DEEPENING.md
.agents/skills/improve-codebase-architecture/INTERFACE-DESIGN.md
.agents/skills/improve-codebase-architecture/LANGUAGE.md
.agents/skills/improve-codebase-architecture/PRESENTING.md
.agents/skills/improve-codebase-architecture/SKILL.md
$ kit archive "$TO_REF" .agents/skills/improve-codebase-architecture | tar -x
$ ln -s ../../.agents/skills/improve-codebase-architecture .claude/skills/improve-codebase-architecture
$ sh scripts/check.sh   # still red from Part 1: the ARTICLE is here; the manual does not know
FAIL  docs gate: violations found

WARN  docs conformance: advisories (gate stays green)

  [skill-paths] ! .agents/skills/improve-codebase-architecture/SKILL.md [skill-path-missing] — references `.agents/skills/LICENSE-mattpocock-skills.md` but neither it nor `.agents/skills/LICENSE-mattpocock-skills.md.template` exists
      -> Fix the reference, restore the file, or finish the update that delivers it — an agent obeying this skill will be pointed at it. An upstream-verbatim file goes in skillPaths.exemptFiles; a path that exists only after something creates it goes in skillPaths.exemptTokens. Reasons on every entry.
  [skill-paths] ! .agents/skills/improve-codebase-architecture/SKILL.md [skill-path-missing] — references `scripts/agents.config.sh` but neither it nor `scripts/agents.config.sh.template` exists
      -> Fix the reference, restore the file, or finish the update that delivers it — an agent obeying this skill will be pointed at it. An upstream-verbatim file goes in skillPaths.exemptFiles; a path that exists only after something creates it goes in skillPaths.exemptTokens. Reasons on every entry.
  [skill-paths] ! .claude/skills/design-brief/SKILL.md [skill-path-missing] — references `scripts/agents.config.sh` but neither it nor `scripts/agents.config.sh.template` exists
      -> Fix the reference, restore the file, or finish the update that delivers it — an agent obeying this skill will be pointed at it. An upstream-verbatim file goes in skillPaths.exemptFiles; a path that exists only after something creates it goes in skillPaths.exemptTokens. Reasons on every entry.
  [skill-paths] ! .claude/skills/housekeeping/CHECKLIST.md [skill-path-missing] — references `scripts/agents.config.sh` but neither it nor `scripts/agents.config.sh.template` exists
      -> Fix the reference, restore the file, or finish the update that delivers it — an agent obeying this skill will be pointed at it. An upstream-verbatim file goes in skillPaths.exemptFiles; a path that exists only after something creates it goes in skillPaths.exemptTokens. Reasons on every entry.
  [skill-paths] ! .claude/skills/implement/SKILL.md [skill-path-missing] — references `adapters/claude-code/README.md` but neither it nor `adapters/claude-code/README.md.template` exists
      -> Fix the reference, restore the file, or finish the update that delivers it — an agent obeying this skill will be pointed at it. An upstream-verbatim file goes in skillPaths.exemptFiles; a path that exists only after something creates it goes in skillPaths.exemptTokens. Reasons on every entry.
  [skill-paths] ! .claude/skills/implement/SKILL.md [skill-path-missing] — references `scripts/agents.config.sh` but neither it nor `scripts/agents.config.sh.template` exists
      -> Fix the reference, restore the file, or finish the update that delivers it — an agent obeying this skill will be pointed at it. An upstream-verbatim file goes in skillPaths.exemptFiles; a path that exists only after something creates it goes in skillPaths.exemptTokens. Reasons on every entry.
  [skill-paths] ! .claude/skills/retro/QUESTIONS.md [skill-path-missing] — references `scripts/agents.config.sh` but neither it nor `scripts/agents.config.sh.template` exists
      -> Fix the reference, restore the file, or finish the update that delivers it — an agent obeying this skill will be pointed at it. An upstream-verbatim file goes in skillPaths.exemptFiles; a path that exists only after something creates it goes in skillPaths.exemptTokens. Reasons on every entry.
  [skill-paths] ! .claude/skills/retro/SKILL.md [skill-path-missing] — references `scripts/agents.config.sh` but neither it nor `scripts/agents.config.sh.template` exists
      -> Fix the reference, restore the file, or finish the update that delivers it — an agent obeying this skill will be pointed at it. An upstream-verbatim file goes in skillPaths.exemptFiles; a path that exists only after something creates it goes in skillPaths.exemptTokens. Reasons on every entry.
  [skill-paths] ! .claude/skills/to-tickets/SKILL.md [skill-path-missing] — references `scripts/agents.config.sh` but neither it nor `scripts/agents.config.sh.template` exists
      -> Fix the reference, restore the file, or finish the update that delivers it — an agent obeying this skill will be pointed at it. An upstream-verbatim file goes in skillPaths.exemptFiles; a path that exists only after something creates it goes in skillPaths.exemptTokens. Reasons on every entry.

FAIL  docs conformance: violations found

  [claude-md-refs] (1)
    x constitution/shared-code-craft.md [article-unreferenced] — is not referenced from AGENTS.md — no agent will ever be pointed at it
      -> Add a pointer to it in AGENTS.md's article layer, or delete the article — an unreachable standing instruction binds nobody and drifts unnoticed.

1 violation(s) across 1 validator(s).

Fix them, or see .githooks/pre-push for the logged bypass.

$ # 9b — new SECTIONS in the manual template we were stamped from
$ kit diff --stat "$FROM_REF" "$TO_REF" -- constitution/
 constitution/AGENTS.md.template            |  78 ++++++++++++++-
 constitution/local-engineering.md.template |   2 +-
 constitution/local-product.md.template     | 103 ++++++++++++++++++++
 constitution/local-workflow.md.template    |  53 +++++++++++
 constitution/shared-code-craft.md          | 147 +++++++++++++++++++++++++++++
 5 files changed, 379 insertions(+), 4 deletions(-)
$ # copied across by hand: the Capability tiers section, and two rows
  edited  AGENTS.md (new section + three quick-reference rows + the code-craft pointer)

$ # 9c — workflow templates: installed once at bootstrap, never after
NEW       .github/workflows/ai-review-prompt.md
NEW       .github/workflows/ai-review.example.yml
UNCHANGED .github/workflows/commitlint.yml.example
UNCHANGED .github/workflows/docs-gate.yml
DECLINED  .github/workflows/tdd-pairing.yml
  took    .github/workflows/ai-review.example.yml + its prompt file

$ # 9c — the docs bootstrap made from templates/docs/: one newer than yours is a take
UNCHANGED .github/PULL_REQUEST_TEMPLATE.md
UNCHANGED README.md
UNCHANGED docs/adr/INDEX.md
UNCHANGED docs/adr/NNNN-template.md
UNCHANGED docs/diary.md
UNCHANGED docs/domain-glossary.md
NEW       docs/specs/README.md
  took    docs/specs/README.md

$ # 9d — config: MERGE, ADD or STAMPED? Ask about BOTH refs first.
$ # kit cat-file -e "${FROM_REF}:$C" — did it exist at the release we are on?
ADD     scripts/agents.config.sh is new at v0.65.0 — nothing of ours to preserve
$ sed -n 's/^\(AGENT_TIER_[A-Z]*\)=.*/\1/p' "$C"
AGENT_TIER_PLANNER
AGENT_TIER_IMPLEMENTER
AGENT_TIER_MECHANICAL
AGENT_TIER_REVIEWER
$ # …and the same three questions for the config bootstrap STAMPED
STAMPED scripts/docs-conformance/local-vocabulary.mjs — the kit has no such path at either ref
$ kit diff --stat "$FROM_REF" "$TO_REF" -- "$C.template"
(the source template did not change in this release)

$ # 9e — adapters: whole directories, or none
$ kit archive "$TO_REF" adapters | tar -x
README.md
claude-code
codex
gemini-cli
node-ts
ruby

$ sh scripts/check.sh
WARN  docs conformance: advisories (gate stays green)

  [skill-paths] ! .agents/skills/improve-codebase-architecture/SKILL.md [skill-path-missing] — references `.agents/skills/LICENSE-mattpocock-skills.md` but neither it nor `.agents/skills/LICENSE-mattpocock-skills.md.template` exists
      -> Fix the reference, restore the file, or finish the update that delivers it — an agent obeying this skill will be pointed at it. An upstream-verbatim file goes in skillPaths.exemptFiles; a path that exists only after something creates it goes in skillPaths.exemptTokens. Reasons on every entry.

OK  docs gate: all checks passed (shared-layer 0.65.0, engine: docs harness)
```

Seven things in that transcript are worth reading twice.

**`WARN  docs conformance: advisories (gate stays green)`, on the final run.**
That block is the gate's warning channel, relayed through `scripts/check.sh`
since 0.15.0 — before that a green wrapper swallowed it, so an advisory was
audible only to someone running the harness by hand. What it names here is
real and sanctioned: the skill-paths advisory sees a skill pointing at the
provenance file 9a delivers, in a consumer that took 9a's delta for one skill
and not the file beside it. Read every advisory the way you read this one: a
finding about prose you own, printed so you can decide, never a failed push.

**`ADD     scripts/agents.config.sh is new at v0.65.0`.** The tier→model map did
not exist at 0.3.0; it arrived with the resolver. So this consumer copies the
whole file — nothing of theirs is at risk — and then edits it. That is *this*
pair of releases, not a rule: the same path is a destructive overwrite for a
consumer who already had the file, which is why 9d asks before it writes.

**`STAMPED scripts/docs-conformance/local-vocabulary.mjs`, two lines below it.**
Same command, same pair of releases, opposite answer — and the reason is not the
release at all. The kit has never had that path: bootstrap *stamps* it from
`local-vocabulary.mjs.template`, so `cat-file -e` is false at both ends. A
version of 9d that asked only about `FROM_REF` printed `ADD` here and emptied
the file, which is what the third verdict exists to stop. The line above it and
the line below it are the same question with three possible answers, and only
asking twice tells them apart.

**`merged clean — the kit's delta and our local note both survive`.** The kit
added a tier rubric to `/to-tickets`; the consumer had added a line of their own.
A copy would have destroyed one of them, and a byte comparison would have called
a legitimate local adaptation "drift". Neither is the right question for a skill.

**The gate ran twice, and the first run was red.** Red since Part 1, in fact —
`article-unreferenced`, the shared article with no manual pointer — and landing
the new skill's directory changed nothing, because the two absences are treated
oppositely on purpose: a skill with no row is merely invisible, while an article
with no pointer is a violation. The teeth meet in the middle — a row with no
skill is `skill-missing`, an article with no pointer is `article-unreferenced` —
which is what makes 9b's hand edits steps rather than suggestions. The test
proves both directions, and proves them again for `/dogfood` adopted and then
declined after bootstrap.

**`NEW       .github/workflows/ai-review-prompt.md`.** The workflow next to it
reads that file at run time. Taking one and not the other produces a review
workflow that fails on its first PR — which is why 9c says take a template with
its neighbours.

**`DECLINED  .github/workflows/tdd-pairing.yml`, one line below two `NEW`s.**
All three are files that are not in `.github/workflows/`, and only two of them
are missing by accident. This consumer folded the pairing gate into its own CI
and deleted the kit's copy; the release did not touch that file, so there is
nothing to adopt and nothing to decide. A classifier that only asks "is it
there?" prints `NEW` for all three, and the reader — reasonably — adds a
duplicate gate to every PR of theirs.
