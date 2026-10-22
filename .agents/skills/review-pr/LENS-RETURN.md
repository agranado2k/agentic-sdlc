# A lens's return, and the raises its parent records

Opened from `/review-pr` §3. `SKILL.md` stays the entry point; this file is the branch, and a `§` points into `SKILL.md`.

Where the agent harness offers tier agent types, every Axis-1 judging context this review spawns — the six lenses, and the single-reviewer pass — runs as the `reviewer` type: it reads and searches, and holds no shell, so it can run no trace line. It never records. It returns its findings as raise lines, and the context that spawned it — the coordinator — records them. The coordinator judges nothing: it slices, spawns, records, renumbers and posts, which is planner work, so the session that hands it this skill stamps and spawns it `planner`, and a reviewer-tier spawn on a wider type is one the adapter's spawn guard refuses.

## The shape a lens returns

Its report is §5's anatomy, its ids numbered within its own report — `H-1` its first HIGH. It ends with one raise line per finding it reported, in its report's order, then the count line, and nothing after it:

```
Raise: <its id, [CHML]-[0-9]+> <file:line>
Raises: <count>
```

The id's letter is the severity: `C` critical, `H` high, `M` medium, `L` low. A report with no findings ends `Raises: 0`. The coordinator must quote the fence above in its spawn prompt, so every lens returns the same lines.

## The parent-side emit

Save each return, byte for byte, to a file outside the tree with your file-writing tool — never through a shell heredoc, whose terminator a return could carry — and run `lens_raise` on it from the project root, with your path's answer to the post question (§6) — `yes` on path (a) told to post, `no` told not to. It checks the whole return before it records anything: the last line `Raises: <n>`, exactly `n` raise lines in the lines just above it, none elsewhere, each on the shape. A return off the shape is refused whole — exit 2, nothing recorded, nothing of it printed — and that lens ends `fail`, named under `Lenses not run:` with the cause `return off shape`. On the shape it numbers each raise in arrival order across the review — the tally file, one per review, holds the count per letter — records one `finding.raise` per line, §6 step 3's line, a LOW always `data.posted=no`, a place off the plain set `data.where=unsafe-path`, and prints `<lens id> <review id>` per line: the renumbering your §5 report prints.

```sh
# lens_raise <PR number> <roster token> <yes|no> <return file> <tally file>
lens_raise() {
	_lr_n=$(sed -n '$s/^Raises: \([0-9][0-9]*\)$/\1/p' "$4")
	[ -n "$_lr_n" ] || { echo "lens_raise: refused — the return does not end in its count line" >&2; return 2; }
	[ "$(grep -c '^Raise:' "$4")" -eq "$_lr_n" ] &&
		[ "$(tail -n "$((_lr_n + 1))" "$4" | sed '$d' | grep -cE '^Raise: [CHML]-[0-9]+ [^[:space:]]+$')" -eq "$_lr_n" ] ||
		{ echo "lens_raise: refused — the raise lines are off the shape or disagree with the count" >&2; return 2; }
	touch "$5" || return 2
	grep '^Raise:' "$4" | while read -r _lr_tag _lr_id _lr_where; do
		_lr_l=${_lr_id%%-*}
		case $_lr_l in C) _lr_s=critical ;; H) _lr_s=high ;; M) _lr_s=medium ;; *) _lr_s=low ;; esac
		_lr_i=$(($(grep -c "^$_lr_l\$" "$5") + 1))
		echo "$_lr_l" >>"$5"
		case $_lr_where in *[!A-Za-z0-9._/:-]*) _lr_where=unsafe-path ;; esac
		_lr_p=$3
		[ "$_lr_s" = low ] && _lr_p=no
		sh scripts/trace.sh emit kind=finding.raise subject="pr:#$1" outcome=raised data.id="$_lr_l-$_lr_i" \
			data.severity="$_lr_s" data.agent="$2" data.where="$_lr_where" data.posted="$_lr_p" || :
		echo "$_lr_id $_lr_l-$_lr_i"
	done
}
```

On paths (b) and (c) the post answer comes after the report: keep the returns and run `lens_raise` at §6, once.

## The single-reviewer pass, as a spawn

Where the agent harness offers tier types, §3's single-reviewer pass is one `reviewer`-type spawn on §3's resolved answer, handed every lens file and its slice — `behavior.diff` when every slice was empty ([`NO-LENS.md`](NO-LENS.md)) — returning the shape above, which you record with `data.agent=single-reviewer`; its spawn record and `spawn.end` carry that token too. The coordinator audits no lens in its own context: a lens whose reviewer walk is spent is named under `Lenses not run:`, cause `walk spent`, and the review is never audited by a model the walk did not name. Only a context with no subagent tool at all audits a lens in place.
