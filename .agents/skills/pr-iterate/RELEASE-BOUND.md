# Release-bound reds — set aside, never cured on the branch

Opened from `/pr-iterate` step 3 when a failing check's own log carries the `release-bound:` marker. `SKILL.md` stays the entry point; this file is the branch.

**A release-bound red is set aside before it is classified.** Some reds cannot pass on a branch by decision: a check that waits on a release — a pinned transcript only the version bump re-captures, a shared-layer file that moved past its release tag — goes green when the release merges and on no commit of this PR. What marks one is the check's **own output**: a failing line carrying `release-bound:`, which the check prints because it knows why it is red. It is never inferred from a check's name, nor from a list of check names kept here: a name says what a check is, not why it failed this time. Save each failing check's **own** log to the iteration's scratch directory — `gh run view <run-id> --job <job-id> --log-failed >"$scratch/checks/<i>"`, the job id read from the check's link in `gh pr checks`, the names one per line in `$scratch/checks/list` — and split them. Per job, never per run: one run holds many checks, and a run-wide log would carry one check's marker into every other red beside it.

```sh
# triage_reds <the failing checks, one name per line> <a directory holding
# log i of that list as <directory>/i> — prints `triage <name>` for a red this
# iteration classifies and acts on, and `set-aside <name>` for a red whose own
# output says it waits on a release.
triage_reds() {
	i=0
	while IFS= read -r name; do
		i=$((i + 1))
		if grep -qF 'release-bound:' "$2/$i" 2>/dev/null; then
			printf 'set-aside %s\n' "$name"
		else
			printf 'triage %s\n' "$name"
		fi
	done <"$1"
}
```

A set-aside red is **never fixed, never triaged and never re-run** — no commit aimed at it, no re-run of the job, no empty push to try it again — on this iteration or any later one: the next iteration's split sets it aside again. Every `triage` red goes through the table below exactly as before. When the set-aside reds are all that is left — nothing to triage, no open bot thread, no unanswered human thread — the iteration stops there (step 6), and the release-bound red is the operator's to carry to the release.
