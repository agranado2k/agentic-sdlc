---
name: explain-diff
description: Produce a rich, interactive, self-contained HTML explanation of a code change — background, intuition with diagrams, a code walkthrough, and a comprehension quiz. Use when the user asks to explain a diff, branch, commit range, or PR, wants to understand a change before reviewing or merging it, or wants to pay down cognitive debt on code an agent wrote.
---

# Skill: Explain Diff

Make the reader a rich, interactive explanation of the specified code change.

This skill exists to fight **cognitive debt** — the gap that opens when code
lands faster than anyone's understanding of it. `/review-pr` answers "is it
built right / is it the right thing"; this skill answers the question that comes
*before* both: **do I actually understand what changed?** It teaches; it never
judges, comments, or fixes. Run it on a branch you are about to review, a PR
you are about to merge, or a change an agent just made on your behalf.

A useful discipline the explanation should enable: the author takes the quiz
at the end **before** sending the change to anyone else. Failing your own quiz
is the cheapest possible signal that the change outran your understanding.

## Scope — what change to explain

Resolve the target from `$ARGUMENTS` (a PR number, a branch name, or an
explicit commit range). Given nothing, explain the current branch's divergence
from the default branch: `git fetch origin`, find the merge-base against the
default branch (`constitution/local-workflow.md` names it), and take
`<merge-base>..HEAD` as the change. Never modify the branch.

For the Background section you should **broadly explore the surrounding code**
— unlike a review, reading beyond the diff is the point here. Where the
project defines its own vocabulary, use it and link to it: the names in
`docs/domain-glossary.md`, the binding decisions in `docs/adr/`. If a decision
record explains *why* the code is shaped the way the diff assumes, cite it —
the "why" is exactly what a diff cannot show.

## Sections

The explanation has these sections, in this order:

- **Background**: Explain the existing system relevant to this change. We
  don't know how much the reader already knows, so include a deep background
  for beginners (note that it can be skipped if the reader is already
  familiar), and then a more narrow background directly relevant to the change.
- **Intuition**: Explain the core intuition for the code change. The focus
  here is to explain the essence, not the full details. Use concrete examples
  with toy data. Use figures and diagrams liberally.
- **Code**: Do a high-level walkthrough of the changes to the code.
  Group/order the changes in an understandable way — by logical flow, never by
  file order.
- **Quiz**: Come up with five questions that test the reader's knowledge of
  this change. Medium difficulty: difficult enough that you actually need to
  understand the substance of the change to answer, but not gotchas. The goal
  is to help readers confirm they've actually understood. Present them as
  interactive multiple-choice questions; when the reader clicks, say whether
  they were correct and give feedback. **Randomize the position of the correct
  answer across questions** — a quiz whose right answer is always option B
  tests pattern-matching, not understanding.

## Format

- Output a single **self-contained HTML file** which includes its CSS and
  JavaScript inline — no external dependencies. Make the whole thing one long
  page with section headers and a table of contents. Don't use tabs for the
  top-level structure. Basic responsive styling so it reads on a phone is nice
  too.
- Put the file **outside the repo tree** so it never lands in version control,
  and start the filename with today's date in `YYYY-MM-DD-` format so the
  files stay time-sorted. For example:
  `/tmp/2026-01-12-explanation-<slug>.html`. Tell the user the path when done.
- Write with the clarity and flow of Martin Kleppmann — engaging, classic
  style, with smooth transitions between sections.
- Tips on diagrams: pick a **small number of diagram families** that can be
  reused throughout the explanation to explain the various cases. Useful
  kinds:
  - A very simplified version of the UI the user sees in the app, to explain
    UI changes.
  - A system diagram showing data flow or communication between components —
    and make sure to include example data in it.
- **Don't use ASCII diagrams.** Always use simple HTML designs for your
  diagrams, HTML lists for lists of things, etc.
- When the load-bearing concept of the change is **dynamic** — time,
  concurrency, state transitions, load — consider embedding one **micro-world**:
  a small manipulable simulation the reader learns from by poking.
  [MICROWORLDS.md](./MICROWORLDS.md) carries the catalog of world types, the
  when-to-use heuristics, and the honesty rules (one world per explanation;
  simulate the model, not the code; label the fidelity; play it before
  shipping). A static change needs diagrams, not a toy.
- For code blocks, always use `<pre>` tags. If you use a custom styled div
  instead, it **must** have `white-space: pre-wrap` in its CSS, or the browser
  will collapse all newlines into a single line. Before saving the file, scan
  each code block in the HTML source and confirm its CSS includes
  `white-space: pre` or `pre-wrap`.
- Use callouts for key concepts or definitions, important edge cases, etc.

## What this skill never does

It produces an explanation and nothing else: no code changes, no review
comments, no PR activity. If explaining the change surfaces something that
looks wrong, say so to the user in one line and point at `/review-pr` — a
teaching pass that quietly turns into a review destroys the reader's trust
that the explainer has no agenda.

---

*Adapted from Geoffrey Litt's `explain-diff-html` skill
([gist](https://gist.github.com/geoffreylitt/a29df1b5f9865506e8952488eac3d524)),
shared in ["Understanding is the new bottleneck"](https://www.geoffreylitt.com/2026/07/02/understanding-is-the-new-bottleneck)
— see `.claude/skills/LICENSE-mattpocock-skills.md` for the provenance record.
The sections and format rules are his; this kit added the scope lock, the
glossary/ADR grounding, the quiz answer randomization, the no-review
boundary, and the `MICROWORLDS.md` sidecar.*
