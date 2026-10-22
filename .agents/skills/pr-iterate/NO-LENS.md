# A review in which no lens ran — never converged

Opened from `/pr-iterate` step 6's no-lens bullet (`/review-pr` §5 and its `NO-LENS.md`). `SKILL.md` stays the entry point; this file is the branch.

**A review whose Axis-1 verdict is `blocked` with the reason `no lens ran` is no verdict for step 6's converged condition: the PR is not converged, whatever its checks and threads say.** Its report's Verdict line reads `BLOCKED — no lens ran; this is not a review`, and its trace line carries `outcome=blocked data.lenses=0` — nothing audited the head, so there are no findings to triage and nothing a fix here can turn green. A re-run of `/review-pr` that also ran no lens is the same answer, never a second try's pass.

Escalate it at the top of the report, directly below the ⚠️ block: the Output format and hard rule 4 put the ⚠️ items first, above everything else, and a blocked review moves nothing above them. The escalation stands once, as its own line, and the `/review-pr:` status line carries the review's Verdict text in place of counts that count nothing:

```
PR #<N> — "<title>" — iteration <i>

⚠️ For you (behavior confirm-list, human-only):
  <verbatim ⚠️ UNSPECIFIED / 🔀 MIXED COMMIT lines, or "none">

🟡 Escalated: no lens ran — the review audited nothing on this head

Status:
  /review-pr:    BLOCKED — no lens ran; this is not a review

Next: stop — escalation
```

The other Status lines and the iteration's lists keep the Output format's shape; the `Escalated:` list does not name this one again. Record the iteration `stopped`, the escalation as its reason. Ending a `/loop` is the operator's, who decides whether the review's lens rules should select this diff or a single reviewer should read it by hand.
