# /to-tickets — the risk rubric

Opened from `/to-tickets` rule 17, while drafting, before any ticket's risk is stamped. `SKILL.md` stays the entry point; this file is the branch. The grammar is the project's vocabulary policy's, read by `sh scripts/vocab.sh fields`.

## The risk stamp

Every ticket body carries one `Risk:` line and one `Risk-confidence:` line, beneath the tier's `Confidence:` line. The risk is the planner's answer to one question: **would a mistake in this change be expensive to find or to undo?** It is `Risk: low`, or `Risk: high <reason>` with exactly one reason. Ask which of these the change touches, in this order, and stamp the first that applies:

- `irreversible` — a change that cannot be undone by a revert: a data migration, a published release or tag, a message sent, a file deleted outside version control.
- `security` — a change to auth, secrets or the trust boundary: who may act, what a credential reaches, what untrusted content can reach.
- `invisible` — a mistake no post-merge outcome would count: no revert or fix would ever follow it, because nothing a user or a check sees would show it.
- `shared-layer` — a file the shared-layer manifest lists, a contract file, or a policy, guard or gate file.
- `unclear` — the planner cannot tell: the ticket's reach is not known well enough to rule the four above out.

Stamp `Risk: low` only when none applies. `low` is a finding, not a default: a ticket you did not ask the question of is `unclear`, never `low`.

`Risk-confidence: <low|medium|high>` is how sure the risk stamp looked, read as rule 14 reads a tier's confidence — `low` when another answer was live while you stamped. It is the risk's own, never the tier's `Confidence:` line.

Two reasons the policy declares are never the planner's: `unlearned` and `outward` are written by the risk rule alone, from the review areas' earned records and a review's unspecified outward items. A planner who writes one has guessed at evidence it does not hold.

**The check, before the quiz.** Each ticket's two lines go to the vocabulary checker as the planner — `sh scripts/vocab.sh --writer planner 'Risk: <level>' 'Risk-confidence: <token>'`, with the stamp's values — in step 3, with the other stamps. A line it refuses (exit 2, one `x vocab:` line naming the field and the value) is repaired and checked again, never shown: a reserved reason is replaced by the planner reason the change touches, or by `unclear`.

<!-- good --> `Risk: high shared-layer` passes, and <!-- refused --> `Risk: high unlearned` is refused to the planner.

**At the quiz** each ticket shows its `Risk:` and `Risk-confidence:` beside its tier, so the human can challenge the risk as they challenge the tier. **On publish** the body carries the risk as the quiz left it, and the `ticket.write` event records three keys: `data.risk` as published, `data.risk_proposed` as you stamped it before the quiz, and `data.risk_confidence`. A quiz override is then visible as `data.risk` differing from `data.risk_proposed`, which is what `/retro` counts.
