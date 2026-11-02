# ADR-0047: A low-risk pull request lands through the lane, on a standing authorization that names the operator

- **Status**: Accepted
- **Date**: 2026-11-02
- **Deciders**: the implementer session for #913 (PRD-10 slice 1), under the operator's delegation of rulings; the decision is D-02's Option 3 and PRD-10 §8's, approved by the operator on 2026-10-29 and settled in the D-02 grill of 2026-10-31; the merge of this record's pull request is the operator's yes
- **Supersedes / amends**: supersedes shared invariant §7 for the low-risk lane only; amends ADR-0024 clause 7 and ADR-0036 clause 5 (their caller lists) for the landing script's lane mode, recorded as a new record because ADR-0024 takes no further in-place amendment (ADR-0021 clause 5), as ADR-0036 and ADR-0045 did
- **Superseded by**: —

## Context and problem statement

Shared invariant §7 stops every pull request one click short of the merge,
whatever its risk. The kit's operator already lands most pull requests on a
standing instruction to the session (ADR-0016), so on most of them the stop
is a formality, and on the rest it protects nothing that has been measured:
nothing checks that the review the operator trusts has earned that trust.

D-02 measured that trust first. ADR-0036 records post-merge outcomes and
prints each review area's earned record; ADR-0037 and ADR-0038 put a check
table and a decision log on every pull request; ADR-0039 reads policy from
the base branch and fails closed; ADR-0045 judges each pull request's
effective risk, reports it, and gives the operator a kill switch; ADR-0044
adds a verifier from another provider. Nothing acts on the verdict yet.
D-02's outcome is that a low-risk ticket reaches a landed change with no
human step, and the operator is involved only when something high risk
happens. §7, as written, forbids exactly that.

## Decision drivers

1. A change lands with no per-change human act only when its low risk is
   measured, not asserted: from post-merge outcomes, never from a stamp alone.
2. The human stays the one who authorizes: by name, in a value only they
   land, and they can stop it at once.
3. A mistake the lane lets through returns to that human, and demotes what
   let it through without anyone's act.
4. §7 ships verbatim to projects that will never build a lane, so its text
   stays portable and its exception changes nothing for them.
5. One landing path: every refusal the landing script makes today still
   holds in the lane.

## Considered options

1. **Keep §7 whole; the operator keeps clicking.** The stop stays a
   formality on most pull requests and measures nothing. Rejected: D-02's
   outcome is impossible under it.
2. **The lane as `/merge-train` started by an agent.** The train's first
   rule is that only the operator starts it, and it is a batch tool.
   Rejected.
3. **Supersede §7 whole.** Wider than the need: every pull request outside
   the lane keeps its human click. Rejected.
4. **Supersede §7 for the lane only, behind a standing authorization that
   names the operator, and give §7's text one portable exception.** Chosen
   (D-02 Option 3).

## Decision outcome

Chosen option 4.

1. **The low-risk lane** is the landing script run with `--lane` by
   `/pr-iterate`, with no operator act, once the pull request is green and
   the risk rule has printed `effective: low` at that head. It lands one pull
   request per run, or holds it. Nothing else lands without the operator;
   `/merge-train` stays the operator's to start.
2. **The standing authorization is a name.** The lane policy is a policy
   file of its own under `scripts/`, its name ending `.config.sh`, so it is
   read from the base branch under ADR-0039's contract. It names the lane's
   operator (a forge login), the landing command `/pr-iterate` runs, and the
   hold patterns. It ships empty, with a kit-only twin that holds the kit's
   values, as the agents policy has. The lane is **open** only when that
   policy names an operator and can be read, and **closed** otherwise.
   Opening and closing are changes to that policy, which only the operator
   lands: a lane run holds any pull request that touches it.
3. **Every refusal stays.** In lane mode the landing script makes every
   refusal it makes today, with the same exit and effect, and takes none of
   its override flags (`--no-iteration`, `--no-review`, `--unasked`,
   `--train`).
4. **Then it holds, in a fixed order**, on the first of `closed`, `drift`
   (its own or the risk rule's code differs from the base's), `escape`,
   `path` (a `VERSION`-listed file, a policy file judged from the base, or a
   hold pattern), `base-red`, `check-table`, `verifier` (no verifier `pass`
   at the head, with its reason), `switch` and `risk`. A hold is exit 4, one
   `lane: held <token>` line and one `merge.land outcome=skipped
   data.via=lane` event; a refusal stays exit 2 and silent. Only past all of
   them does it merge the head the risk rule judged, recording `merge.land
   data.via=lane`.
5. **The stop is at once.** The kill switch (ADR-0045) makes every pull
   request high, so a tripped switch holds every lane run; removing the
   operator's name closes the lane. Either alone keeps pull requests off it.
6. **Escaped mistakes return to the operator.** An escape is a post-merge
   outcome (ADR-0036) against a lane landing. Each gets one notice to the
   lane's operator, a forge issue assigned to them; a failed factory QA also
   gets a revert pull request (or a fix ticket where the revert conflicts),
   held for the operator. The area's demotion is the risk rule's, read from
   the earned record: an escape is a missed mistake, so the area reads
   unlearned and the lane holds every pull request touching it.
7. **ADR-0024 clause 7 and ADR-0036 clause 5, amended:** the landing script
   in lane mode, run by `/pr-iterate`, a chain skill, is a trace reader and
   runs the outcome recorder before it judges. It reads the trace through
   the trace's readers and hands the skill back only closed tokens, review
   area names, pull request and ticket numbers, commit shas, run ids and
   digits — never text from a ticket, a pull request body, a commit message
   or a log. No chain skill calls `show`, `summary`, `export`, `record` or
   `outcomes` itself. Both clauses stay binding for everything else.
8. **§5 keeps its text.** The lane lands only when no outward item is open
   (the risk rule's `outward` reason makes the pull request high), and inside
   items are decided and logged as ADR-0038 already allows. What changes is
   when the operator reads the log: after the landing. `/pr-iterate` lists
   the decision-log ids of every pull request the lane lands.
9. **§7's text gains one portable exception**: a change judged low risk from
   measured post-merge outcomes may land with no per-change human act, under
   a standing authorization that names that human, which a human can stop at
   once, and whose escaped mistakes return to that human — and only by a
   project's recorded decision. A project that records none keeps §7 as it
   reads today, so a consumer takes the new text with its lane closed: its
   lane policy ships empty and its `/pr-iterate` runs no landing command.
10. **Not in this record's slice**, so a reader does not assume them built:
    the lane mode itself, its policy file and its holds (PRD-10 slice 2),
    the `lane.escape` kind and the escape handling (slice 3), and the root
    guard on the trip marker. Until slice 2 lands, the lane does not exist and
    §7's exception is unused in the kit. The three K3/K5 proposals raised on
    2026-11-01 (D-02 brief.md `## Raised`) are not decided here.

### Consequences

- Good: a pull request whose risk the kit has measured as low lands without
  a formality click, and the operator's attention goes to the ones held.
- Good: the authorization, the stop and the return of an escape are each a
  named mechanism, not a habit of the session.
- Bad: the operator reads a lane landing's decision log after the merge,
  not before; an inside item they would have ruled otherwise is caught as a
  post-merge outcome, not at review.
- Bad: §7, the shared layer's most quoted rule, now carries an exception a
  consumer must read carefully; the sentence that a project recording no
  such decision keeps §7 whole is what bounds it.

## Confirmation

`tests/land.test.sh` section 23 holds §7's exception to its portable words
and to none of the kit's vocabulary, this record to what it supersedes and
amends and to §5's keeping, its index row, and the glossary's five terms;
the docs gate's portability check holds the new §7 to the shared layer's
contract, and `tests/self-host.test.sh` holds a fresh bootstrap clean. Each
later slice's suite holds its clauses as they are built.
