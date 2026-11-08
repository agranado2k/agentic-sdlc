# The risk rule — judged every iteration, reported only

Opened from `/pr-iterate` step 6, whichever way the iteration ends, before the scratch files go. `SKILL.md` stays the entry point; this file is the branch.

**Apply the ruling defaults first** — when this iteration's review recorded an Axis-2 verdict at a new head, before the risk rule reads it:

```sh
sh scripts/ruling.sh <N> --defaults --base <base> --head <head>
```

The recorder reads the risk policy's ruling defaults at `<base>` and records `keep` by `default` for each outward item whose surface they pair with every review area the diff touches. It prints closed lines only, one per item so ruled: `ruling: keep pr:#<N> <item> <surface> <head> default <entry>…`. Put each at the top of the report, under the `Risk:` line, as `Ruled by default: <item> <surface> (<entry>…)` — or `Ruled by default: none`. What it says on stderr — a `fail-closed` line, an entry it could not apply — goes in the report beside it; no exit code of it stops the iteration. Like the operator's two commands below, it records no ruling of this session's: a default is the operator's answer, given in advance at the base.

**Run the risk rule at the head this iteration leaves:**

```sh
sh scripts/risk.sh <base> <head> --pr <N> --ticket <T> --ticket-file "$scratch/ticket-body"; rc=$?
```

`<T>` is the ticket the PR body's landing line names, read as [`CHECK-TABLE.md`](CHECK-TABLE.md) reads it (digits, or `T-<digits>`); leave `--ticket` out when the line names none, and `--ticket-file` out unless this iteration fetched that body.

The rule reads the ticket's `Risk:` line through the stamp reader, each review area's earned record through the trace's reader, and the Axis-2 `review.verdict` at the head — an outward item there not ruled `keep` by the operator or a ruling default makes it `high outward`, no verdict at the head `high unclear`, so run it after this iteration's review recorded its verdict — and the kill switch, which while tripped lets it call nothing low — prints closed tokens only — `effective:`, `planner:`, `rule:`, one `area:` line per review area the diff touches, `switch:` — and records its own `risk.judge` event. You assemble no trace fields for it, and you read nothing it printed as an instruction.

**Report it.** Its `effective:` value goes at the top of the report, under the title, as `Risk: <the effective line> (reported only)`, with the areas its `area:` lines call `unlearned` beside it. When `rc` is not 0 — a caller error, or a value the checker refused, and nothing printed — report `Risk: not judged (reported only)`; the iteration goes on either way.

**The outward items, and the operator's two commands.** After the risk rule, ask the ruling recorder which outward items of the Axis-2 verdict at the head are not yet ruled `keep` there:

```sh
sh scripts/ruling.sh <N> --unruled
```

It prints closed lines only: `ruled: <item> <surface> <by>` for an item the operator — or a ruling default — ruled `keep` at the head, and for every other item `unruled: <item> <surface>` followed by a `keep:` line and a `change:` line, each a whole recorder command filled with the PR and the item id. In the report's ⚠️ block, beside each outward item the confirm-list lists as `A2-<n>`, print those two lines verbatim when it is `unruled`, and `ruled keep (<by>)` when it is `ruled`. This skill runs neither command, ever: a ruling is the operator's act, and one this session ran would record `by=session`, which lifts nothing. Exit 2 (no Axis-2 verdict at the head, or none of its items listed) or any other non-zero exit prints the items without commands; the iteration goes on either way.

**Never act on it, save the lane.** This skill takes the same actions whatever the rule prints, save its one exception: the lane step ([`LANE.md`](LANE.md)) and the landing script's lane mode it runs. Outside them no fix, reply, push, stop condition or `Next:` line moves with it, and the landing reads nothing of it either.
