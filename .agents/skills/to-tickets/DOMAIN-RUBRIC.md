# /to-tickets — the domain rubric

Opened from `/to-tickets` when a ticket's medium may be distinctive — the work is made of something other than the tier's ordinary stuff — before a `Domain:` line is stamped (rule 10). `SKILL.md` stays the entry point; this file is the branch.

## The domain rubric

The tier answers "how much judgement is this worth?". It does not answer "what is this work made **of**?" — and a ticket that writes the launch announcement and one that writes the retry logic are both `implementer`. Where the medium is distinctive, add a second line:

```
Domain: content
```

**One question decides it: would the medium of this work change which model you would pick, if you were picking?** If yes, stamp it. If the honest answer is "no, it's just work at that tier", leave the line off — that is the ordinary case, and a `Domain:` on every ticket is the same non-decision as one tier on every ticket.

- The token is lowercase `[a-z][a-z0-9-]*`. `code` and `content` are the common split; a repo whose hard part is elsewhere might use `sql` or `html-report`.
- **The vocabulary is open and it is the repo's, not yours to invent freshly each wave.** Read `scripts/agents.config.sh` for the domains this project has actually mapped and prefer those words. A domain nobody has mapped is harmless — the resolver falls back to the tier — but it is also inert, so a new token is worth raising at the quiz rather than slipping in.
- Still never a model name. `Domain: content` is a fact about the work; `Domain: <some-model>` is the rot rule 9 avoids, wearing a different label.
