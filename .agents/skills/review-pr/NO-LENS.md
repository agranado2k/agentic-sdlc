# A review in which no lens ran

Opened from `/review-pr` §3 when every lens's slice counts 0, and from §5 when no Axis-1 lens returned a report. `SKILL.md` stays the entry point; this file is the branch, and a `§` points into `SKILL.md`.

## Every slice empty (§3)

**A diff whose every lens slice is empty still gets a review: run the single-reviewer pass over the whole diff, `behavior.diff`, and record no Axis-1 verdict before that pass returns.** A slice is a lens's lane, chosen by path rules that are policy data; a change no rule selects — a new top-level directory, a file kind no rule names — is unreviewed by those rules, not reviewed and clean. The pass is §3's single-reviewer pass, run for this case even when the host could spawn the lens agents, because there is no slice to hand one: read each lens's file, audit `behavior.diff` through it, and raise every finding `data.agent=single-reviewer`. The summary names each lens on the `Lenses not run:` line as `<lens> — empty slice, run in this context instead`, and `Lenses run:` reads `0 of 0`. The verdict is then recorded from the pass, as §5 records any, with `data.agent=single-reviewer data.lenses=0 data.roster=0`.

## No lens and no pass returned (§5)

**When no Axis-1 lens returned a report and no single-reviewer pass returned, the review records `blocked` and says that no lens ran.** Two roads lead here: every slice was empty and the pass above failed before it returned, or every lens spawn failed and no pass audited the lenses in their place. Nothing audited the diff, so `pass` would be a claim nobody checked — record the axis as:

`sh scripts/trace.sh emit kind=review.verdict subject=pr:#<N> outcome=blocked data.axis=1 data.lenses=0 data.roster=<count> reason='no lens ran' || :`

— `data.roster` the lenses planned, as §5 counts it, `0` when every slice was empty. The summary's first line is then

`**Verdict:** BLOCKED — no lens ran; this is not a review`

and the count table's zeros count nothing, which that line is there to say. Axis 2 is unchanged: Agent 7 reads `behavior.diff` and records its own verdict, and both verdicts are still recorded before anything is posted. A review in which some lenses ran is unchanged: its verdict is decided on the lenses that returned, and the rest are named under `Lenses not run:`.
