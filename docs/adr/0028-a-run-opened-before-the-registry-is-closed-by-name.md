# ADR-0028: A run opened before the open-run registry is closed by name, stopped

- **Status**: Accepted
- **Date**: 2026-10-14
- **Deciders**: the implementer session for #772, under the operator's delegation of rulings; the merge of its pull request is the operator's yes
- **Supersedes / amends**: amends ADR-0024 clause 5 — `end` gains a second form — and refines ADR-0026 clause 2's "a run with no entry and not on the stack is refused as before"; recorded as a new record because ADR-0024 already names five in-place amendments and takes no sixth (ADR-0021 clause 5)
- **Superseded by**: —

## Context and problem statement

Twelve runs begun between 2026-09-28 and 2026-10-05 have a `run.start`
and no `run.end`. They were opened before the open-run registry existed
(ADR-0026), so none has an entry. Each one is still on a run stack, but
ten of those stacks are keyed on linked worktrees that have since been
removed. The other two are on the root checkout's stack with no session,
which only an emit with `TRACE_SESSION` set empty reads. `end <run>`
closes a detached run through its entry and a stack run only from the
top of the caller's own stack. So no caller can close the ten, and every
`/retro` counts them again as runs nobody closed (retro
`retro-20261014T104726Z`). The ticket's example,
`20261002T092408Z-97625-f1766e79`, is one of the two on the root
checkout's stack.

The log is append-only (ADR-0024 clause 5's lineage, ADR-0008 clause 5).
The fix is a closing line, never an edit to old ones.

## Decision drivers

- **Never close a run an owner can still close.** A run that is registered,
  or sits on a stack something can still read, belongs to that owner. A
  second closer would write a second `run.end` once the owner gets there.
- **Explicit, and only for this case.** It is not a general force-close.
- **Nothing written on refusal**: not the log, not a stack, not the
  registry.
- **A reader tells it from an owner's end.**

## Considered options

1. **A named form of `end` that closes only a run no owner can reach**
   *(chosen)*.
2. **Let `end <run>` close any run with no entry that is not on the
   caller's stack.** Rejected: it would close a run below the top of
   another session's live stack, or one on another checkout's stack, with
   nothing to show the caller meant to.
3. **Hand-write the twelve `run.end` lines into the log.** Rejected: that
   bypasses the one writer and its checks (ADR-0024 clause 1), and it does
   nothing for the next run left the same way.
4. **Teach `/retro` to ignore runs older than the registry.** Rejected:
   it hides the open runs instead of closing them, and every reader of the
   log would need the same exception.

## Decision outcome

Chosen: **option 1.**

1. **`sh scripts/trace.sh end --unregistered <run> reason=<text>
   [<field>=<value> …]`** appends one `run.end` for `<run>` with
   `outcome=stopped`, the reason given, the `parent` its `run.start`
   named, and `data.via=unregistered`. It writes nothing else. It touches
   no stack and does not add to the registry.
2. **It closes a run only when all four hold**: the log has a `run.start`
   naming it; the log has no `run.end` naming it; the registry has no entry
   for it; and it is on no run stack of a **live** checkout. A live
   checkout is one of this repository's worktrees that still exists. Its
   toplevel is hashed the way a stack's key is hashed. A stack keyed on a
   removed checkout has nobody left to read it.
3. **Any other run is exit 2, and nothing is written.** That covers a run
   that is registered, already ended, never started, or on a live stack.
   The refusal names the reason, and for a live stack it names the
   checkout to end the run from. A missing or empty `reason=`, any
   `outcome=` (the form sets it), a value that is not a run id, and no run
   at all are also exit 2. A stack, the stack directory, an event file or
   the worktree list that cannot be read is exit 2 as well. An incomplete
   answer would read as "on no live stack".
4. **Unconfigured, it is the silent no-op** every call is.
5. **Clause 7 stands.** This is an operator's tool. No chain skill calls
   it.

## Consequences

- **Good**: the ten runs on removed checkouts close with one command each,
  and `/retro` stops counting them.
- **Good**: a reader can tell such an end apart by `data.via=unregistered`
  and `outcome=stopped`.
- **Neutral**: the two runs on the root checkout's session-less stack are
  on a live checkout, so this form refuses them. The ordinary `end` closes
  them from the root checkout with `TRACE_SESSION` set empty, top first.
- **Bad / trade-off**: `scripts/trace.sh` is shared layer, so the form ships
  in a release (0.76.0).
- **Honest limitation**: liveness is per checkout, not per session. A run
  buried under another run on a stack of a checkout that still exists
  stays unclosable until that checkout is removed.
- **Honest limitation**: a trace directory shared with another repository
  (an absolute `TRACE_DIR`) holds stacks keyed on that repository's
  checkouts, which this repository's worktree list does not name. Those
  stacks read as removed checkouts.

## More information

- Built for #772, from the retro of 2026-10-14.
- Held by `tests/trace.test.sh` section 38.
