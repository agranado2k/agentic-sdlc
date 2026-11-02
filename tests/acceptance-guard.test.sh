#!/bin/sh
# tests/acceptance-guard.test.sh — self-tests for scripts/acceptance-guard.sh,
# the ACCEPTANCE GUARD: a factory ticket's approved acceptance test files held
# from the approval to the ticket's done, judged from the base, failing closed
# (PRD-14 slice 2, factory T-94; the kit's ADR-0046).
#
# The guard reads git's objects and factory tickets, so every case builds a
# REAL throwaway factory project — a `main`, a branch, an approval commit off
# `main` — and runs the kit's guard in it, asserting exit statuses and exact
# lines. Every fail-closed cause has a fixture. The last section runs the CI
# step the shipped pairing workflow and the kit's guards workflow carry,
# extracted from the YAML, against a pull request that edits the guard itself.
#
# Usage: sh tests/acceptance-guard.test.sh

set -u

KIT=$(cd "$(dirname "$0")/.." && pwd)
GUARD="$KIT/scripts/acceptance-guard.sh"
TPL="$KIT/templates/workflows/tdd-pairing.yml"
KITWF="$KIT/.github/workflows/kit-guards.yml"

# shellcheck source=./lib.sh
. "$KIT/tests/lib.sh"
t_init

TF=tests/report.test.sh
T90=.factory/items/T-90/ticket.md

# ag <repo> <env assignment…> -- <guard args…> — run the kit's guard in <repo>.
ag() {
	_ag_repo=$1
	shift
	_ag_env=
	while [ $# -gt 0 ] && [ "$1" != -- ]; do
		_ag_env="$_ag_env $1"
		shift
	done
	shift
	# shellcheck disable=SC2086 # the assignments split on purpose
	t_exec sh -c 'cd "$1" && shift && "$@"' _ "$_ag_repo" env -u POLICY_BASE $_ag_env sh "$GUARD" "$@"
}

# ticket <id> <stage> <created> <approval commit|-> <body> — a factory ticket
# file's text. `-` writes no `tests:` record.
ticket() {
	printf -- '---\nid: %s\ntype: ticket\ntitle: SECRET-TITLE do not print me\nstage: %s\n' "$1" "$2"
	[ -z "$3" ] || printf 'created: %s\n' "$3"
	if [ "$4" != - ]; then
		printf 'tests:\n  commit: "%s"\n  by: "SECRET-BY"\n  at: 2026-11-02\n' "$4"
	fi
	printf -- '---\n\n# %s · SECRET-HEADING\n\n%s\n' "$1" "$5"
}

STAMP='Covers: report/R3, report/R4
Test-tier: report/R3 suite
Test-tier: report/R4 manual
Accept-test: report/R3 tests/report.test.sh::totals by area
Accept-test: report/R3 tests/report.test.sh::empty window prints zero'

# fp_repo [<manifest date line>] — a factory project. main holds the guards
# policy, the manifest, and T-90 approved at APPROVAL — a commit on the side
# branch `t90-tests`, never on main, that holds the approved test file. HEAD
# is the branch `work` off main, which brought the file in unchanged.
fp_repo() {
	t_repo
	_fp_date=${1-acceptance_tests_since: 2026-11-01}
	t_write "$REPO" scripts/guards.config.sh "GUARD_SOURCE_RE='^src/'
"
	t_write "$REPO" .factory/project.yaml "id: fixture
$_fp_date
"
	t_commit "$REPO" "chore: a factory project" >/dev/null
	git -C "$REPO" checkout -q -b t90-tests
	t_write "$REPO" "$TF" 'test "totals by area"
test "empty window prints zero"
'
	APPROVAL=$(t_commit "$REPO" "test: T-90's acceptance tests")
	git -C "$REPO" checkout -q main
	t_write "$REPO" "$T90" "$(ticket T-90 build 2026-11-02 "$APPROVAL" "$STAMP")"
	t_commit "$REPO" "chore: approve T-90's tests" >/dev/null
	git -C "$REPO" checkout -q -b work
	git -C "$REPO" checkout -q "$APPROVAL" -- "$TF"
	t_commit "$REPO" "test: bring in T-90's approved tests" >/dev/null
}

# on_main <repo> <path> <content> — write a file on main, commit, back to work
# (work is then rebased so it sees main's commit, as a fresh branch would).
on_main() {
	git -C "$1" checkout -q main
	t_write "$1" "$2" "$3"
	t_commit "$1" "chore: $2 on main" >/dev/null
	git -C "$1" checkout -q work
	git -C "$1" rebase -q main >/dev/null 2>&1
}

banner "R8, R11. check: a held file changed on the branch fails; left at its approval passes"
# ---------------------------------------------------------------------------
fp_repo
R=$REPO
ag "$R" POLICY_BASE=main -- check main HEAD
expect_resolved '' "acceptance/R8: the approved file at its approval content — exit 0, nothing printed, though the approval commit is not on main"
printf 'weakened\n' >>"$R/$TF"
t_commit "$R" "test: weaken an assertion" >/dev/null
ag "$R" POLICY_BASE=main -- check main HEAD
expect_status 1 "acceptance/R8: a held file changed at the head — exit 1"
expect_out_is "changed: T-90 report/R3 $TF" "acceptance/R8: one changed: line, the ticket, the id and the path — once, though two tests name the file"

banner "R11. A branch that rewrites its own approval record is judged by the base's"
# ---------------------------------------------------------------------------
head=$(git -C "$R" rev-parse HEAD)
t_write "$R" "$T90" "$(ticket T-90 build 2026-11-02 "$head" "$STAMP")"
t_commit "$R" "chore: approve my own tests" >/dev/null
ag "$R" POLICY_BASE=main -- check main HEAD
expect_status 1 "acceptance/R11: POLICY_BASE=main reads main's tests.commit, not the branch's — still exit 1"
expect_out_is "changed: T-90 report/R3 $TF" "acceptance/R11: the same changed: line"

banner "R12. POLICY_BASE unset: the tickets are read from the working tree"
# ---------------------------------------------------------------------------
ag "$R" -- check main HEAD
expect_resolved '' "acceptance/R12: unset, the working tree's rewritten record is the one read — exit 0"

banner "R10. A held file absent at the head is changed"
# ---------------------------------------------------------------------------
fp_repo
R=$REPO
git -C "$R" rm -q "$TF"
t_commit "$R" "test: delete the approved file" >/dev/null
ag "$R" POLICY_BASE=main -- check main HEAD
expect_status 1 "acceptance/R10: a deleted held file — exit 1"
expect_out_is "changed: T-90 report/R3 $TF" "acceptance/R10: the deleted file is reported as changed"

banner "R9. Only an approved ticket not at done is held"
# ---------------------------------------------------------------------------
fp_repo
R=$REPO
on_main "$R" .factory/items/T-88/ticket.md "$(ticket T-88 done 2026-11-02 "$APPROVAL" 'Covers: other/R1
Test-tier: other/R1 suite
Accept-test: other/R1 tests/other.test.sh::x')"
on_main "$R" .factory/items/T-89/ticket.md "$(ticket T-89 build 2026-11-02 - 'Covers: more/R1
Test-tier: more/R1 suite
Accept-test: more/R1 tests/more.test.sh::y')"
t_write "$R" tests/other.test.sh 'changed
'
t_write "$R" tests/more.test.sh 'changed
'
t_commit "$R" "test: change T-88's and T-89's named files" >/dev/null
ag "$R" POLICY_BASE=main -- check main HEAD
expect_resolved '' "acceptance/R9: a done ticket and an unapproved one are not held — exit 0"
ag "$R" POLICY_BASE=main -- held --base main
expect_resolved "T-90 $TF" "acceptance/R37: held lists exactly the held ticket's file, once"

banner "R13. An approval record the guard cannot hold fails closed"
# ---------------------------------------------------------------------------
# closed_with <label> <text builder> — main's T-90 rewritten by the builder,
# run after the fixture exists; check exits 3 with the invalid line naming
# the ticket file.
closed_with() {
	fp_repo
	on_main "$REPO" "$T90" "$($2)"
	ag "$REPO" POLICY_BASE=main -- check main HEAD
	expect_status 3 "acceptance/R13: $1 — exit 3"
	expect_out_is "fail-closed invalid $T90" "acceptance/R13: $1 — the invalid line names the ticket file"
}
unknown_commit() { ticket T-90 build 2026-11-02 0123456789abcdef0123456789abcdef01234567 "$STAMP"; }
no_by() { printf -- '---\nstage: build\ntests:\n  commit: "%s"\n  at: 2026-11-02\n---\n%s\n' "$APPROVAL" "$STAMP"; }
flow_record() { printf -- '---\nstage: build\ntests: {commit: "%s", by: x, at: 2026-11-02}\n---\n%s\n' "$APPROVAL" "$STAMP"; }
closed_with "an approval commit this clone does not hold" unknown_commit
closed_with "an approval record with no by" no_by
closed_with "an approval record the guard cannot read field by field" flow_record
fp_repo
on_main "$REPO" "$T90" "$(ticket T-90 build 2026-11-02 "$APPROVAL" 'Covers: report/R3
Test-tier: report/R3 suite
Accept-test: report/R3 tests/report test.sh::totals')"
ag "$REPO" POLICY_BASE=main -- check main HEAD
expect_status 3 "acceptance/R13: an Accept-test: line the checker refuses — exit 3"
expect_out_is "fail-closed invalid $T90" "acceptance/R13: the refused line is never printed, only the ticket file"
fp_repo
on_main "$REPO" "$T90" "$(ticket T-90 build 2026-11-02 "$APPROVAL" 'Covers: report/R3
Test-tier: report/R3 suite
Accept-test: report/R3 tests/absent.test.sh::totals')"
ag "$REPO" POLICY_BASE=main -- check main HEAD
expect_status 3 "acceptance/R13: an approved path absent at the approval commit — exit 3"
expect_out_is "fail-closed invalid $T90" "acceptance/R13: the absent path gives the invalid line"
ag "$REPO" POLICY_BASE=main -- tests T-90 --base main
expect_status 3 "acceptance/R13: tests fails closed on the same record"

banner "R14. The policy reader failing closed is the guard failing closed"
# ---------------------------------------------------------------------------
fp_repo
git -C "$REPO" checkout -q main
git -C "$REPO" rm -q scripts/guards.config.sh
t_commit "$REPO" "chore: drop the guards policy" >/dev/null
git -C "$REPO" checkout -q work && git -C "$REPO" rebase -q main >/dev/null 2>&1
ag "$REPO" POLICY_BASE=main -- check main HEAD
expect_status 3 "acceptance/R14: the guards policy missing at the base — exit 3"
expect_out_is "fail-closed missing scripts/guards.config.sh" "acceptance/R14: the reader's own line"
fp_repo
git -C "$REPO" checkout -q main
git -C "$REPO" rm -q "$T90"
mkdir -p "$REPO/.factory/items/T-90" && ln -s ../../project.yaml "$REPO/$T90"
t_commit "$REPO" "chore: a ticket file that is a link" >/dev/null
git -C "$REPO" checkout -q work && git -C "$REPO" rebase -q main >/dev/null 2>&1
ag "$REPO" POLICY_BASE=main -- check main HEAD
expect_status 3 "acceptance/R14: a factory ticket the reader cannot read — exit 3"
expect_out_is "fail-closed unreadable $T90" "acceptance/R14: the reader's unreadable line"

banner "R15. No factory project: nothing printed, exit 0"
# ---------------------------------------------------------------------------
# no_factory <label> — the work branch changed the file a stray T-90 names.
no_factory() {
	printf 'weakened\n' >>"$REPO/$TF"
	t_commit "$REPO" "test: weaken" >/dev/null
	for _nf_env in POLICY_BASE=main ""; do
		ag "$REPO" $_nf_env -- check main HEAD
		expect_resolved '' "acceptance/R15: $1${_nf_env:+ (POLICY_BASE=main)} — exit 0, nothing on stdout"
	done
}
fp_repo
git -C "$REPO" checkout -q main
git -C "$REPO" rm -q -r .factory
t_commit "$REPO" "chore: no factory" >/dev/null
git -C "$REPO" checkout -q work && git -C "$REPO" rebase -q main >/dev/null 2>&1
no_factory "no .factory/ at all"
fp_repo
git -C "$REPO" checkout -q main
git -C "$REPO" rm -q .factory/project.yaml
t_commit "$REPO" "chore: a bare .factory/" >/dev/null
git -C "$REPO" checkout -q work && git -C "$REPO" rebase -q main >/dev/null 2>&1
no_factory "a .factory/ with tickets and no manifest"
OUTER=$(mktemp -d "$SCRATCH/outer.XXXXXX")
mkdir -p "$OUTER/.factory"
printf 'id: home\nacceptance_tests_since: 2026-11-01\n' >"$OUTER/.factory/project.yaml"
fp_repo
git -C "$REPO" checkout -q main
git -C "$REPO" rm -q .factory/project.yaml
t_commit "$REPO" "chore: the manifest only above" >/dev/null
git -C "$REPO" checkout -q work && git -C "$REPO" rebase -q main >/dev/null 2>&1
mv "$REPO" "$OUTER/repo"
REPO=$OUTER/repo
no_factory "a manifest only above the git top level"

banner "R16. Nothing read from a ticket is printed but ids, commits and checked lines"
# ---------------------------------------------------------------------------
fp_repo
R=$REPO
printf 'weakened\n' >>"$R/$TF"
t_commit "$R" "test: weaken" >/dev/null
for args in "check main HEAD" "tests T-90 --base main" "held --base main"; do
	# shellcheck disable=SC2086
	ag "$R" POLICY_BASE=main -- $args
	expect_unsaid SECRET "acceptance/R16: $args prints no title, heading or approver"
done

banner "R17 to R20, R35. tests: approved, owed, and the no-tests reasons"
# ---------------------------------------------------------------------------
fp_repo
R=$REPO
ag "$R" -- tests T-90 --base main
expect_resolved "approved $APPROVAL
Accept-test: report/R3 tests/report.test.sh::totals by area
Accept-test: report/R3 tests/report.test.sh::empty window prints zero" "acceptance/R17: approved <commit>, then the Accept-test: lines as spelled"
SUITE='Covers: report/R5
Test-tier: report/R5 suite'
on_main "$R" .factory/items/T-91/ticket.md "$(ticket T-91 build 2026-11-05 - "$SUITE")"
on_main "$R" .factory/items/T-12/ticket.md "$(ticket T-12 build 2026-10-01 - "$SUITE")"
on_main "$R" .factory/items/T-13/ticket.md "$(ticket T-13 build 2026-11-05 - 'Covers: report/R6
Test-tier: report/R6 manual')"
on_main "$R" .factory/items/T-15/ticket.md "$(ticket T-15 build 2026-11-05 - 'No stamp here.')"
on_main "$R" .factory/items/T-14/ticket.md "$(ticket T-14 build yesterday - "$SUITE")"
on_main "$R" .factory/items/T-16/ticket.md "$(ticket T-16 build '' - "$SUITE")"
ag "$R" -- tests T-91 --base main
expect_status 4 "acceptance/R20: a ticket owed its tests — exit 4"
expect_out_is "owed T-91" "acceptance/R20: owed T-91"
ag "$R" -- tests T-12 --base main
expect_resolved "no-tests T-12 created-before-adoption" "acceptance/R18: created before the adoption date — no-tests, exit 0"
ag "$R" -- tests T-13 --base main
expect_resolved "no-tests T-13 no-automated-id" "acceptance/R19: every covered id manual — no-tests, exit 0"
ag "$R" -- tests T-15 --base main
expect_resolved "no-tests T-15 no-automated-id" "acceptance/R19: no Covers: line — no-tests, exit 0"
ag "$R" -- tests T-14 --base main
expect_status 4 "acceptance/R35: a created that is not a date never exempts — exit 4"
expect_out_is "owed T-14" "acceptance/R35: owed T-14"
ag "$R" -- tests T-16 --base main
expect_out_is "owed T-16" "acceptance/R35: a missing created never exempts"
# The base is the judge: a branch that approves T-91 for itself is still owed.
t_write "$R" .factory/items/T-91/ticket.md "$(ticket T-91 build 2026-11-05 "$APPROVAL" "$SUITE")"
t_commit "$R" "chore: approve myself" >/dev/null
ag "$R" -- tests T-91 --base main
expect_out_is "owed T-91" "acceptance/R11: tests reads the ticket at --base, not the branch's approval"

banner "R21. No adoption date: nothing owed, and approvals still held"
# ---------------------------------------------------------------------------
for line in "" "acceptance_tests_since:"; do
	fp_repo "$line"
	R=$REPO
	on_main "$R" .factory/items/T-91/ticket.md "$(ticket T-91 build 2026-11-05 - "$SUITE")"
	ag "$R" -- tests T-91 --base main
	expect_resolved "no-tests T-91 no-adoption-date" "acceptance/R21: the date ${line:+written empty}${line:-absent} — no-tests, exit 0"
	printf 'weakened\n' >>"$R/$TF"
	t_commit "$R" "test: weaken" >/dev/null
	ag "$R" POLICY_BASE=main -- check main HEAD
	expect_status 1 "acceptance/R21: check still holds T-90 with no adoption date"
done

banner "R22. An adoption date out of shape fails closed"
# ---------------------------------------------------------------------------
fp_repo "acceptance_tests_since: 2026-13-01"
R=$REPO
for args in "check main HEAD" "tests T-90 --base main" "held --base main"; do
	# shellcheck disable=SC2086
	ag "$R" POLICY_BASE=main -- $args
	expect_status 3 "acceptance/R22: $args — exit 3"
	expect_out_is "fail-closed invalid .factory/project.yaml" "acceptance/R22: $args — the manifest's invalid line"
done

banner "Caller errors exit 2 with nothing on stdout"
# ---------------------------------------------------------------------------
fp_repo
R=$REPO
for args in "" "check main" "check main no-such-ref" "tests T-90" "tests 'T 90' --base main" "tests ../x --base main" "held" "bogus"; do
	eval "set -- $args"
	t_exec sh -c 'cd "$1" && shift && sh "$@"' _ "$R" "$GUARD" "$@"
	[ "$T_STATUS" = 2 ] && [ -z "$T_OUT" ] && pass "'$args' — exit 2, nothing on stdout" ||
		fail "'$args' — expected exit 2 and no stdout, got $T_STATUS [$T_OUT]"
done

banner "R23, R36. The CI step runs the base's guard with POLICY_BASE set"
# ---------------------------------------------------------------------------
# step_of <workflow> — the run block of the step named "Approved acceptance
# tests unchanged", dedented; its env lines checked separately.
step_of() {
	awk '
		/- name: Approved acceptance tests unchanged/ { on = 1; next }
		on && /^ *- name:/ { exit }
		on && /^ *run: \|/ { run = 1; next }
		on && run { sub(/^          /, ""); print }' "$1"
}
env_of() { awk '/- name: Approved acceptance tests unchanged/ { on = 1; next } on && /^ *- name:/ { exit } on' "$1"; }
for wf in "$TPL" "$KITWF"; do
	name=${wf#"$KIT"/}
	env_of "$wf" | grep -q 'POLICY_BASE: \${{ github.event.pull_request.base.sha }}' &&
		pass "acceptance/R23: $name sets POLICY_BASE to the pull request's base commit" ||
		fail "acceptance/R23: $name — the acceptance step sets no POLICY_BASE from the base sha"
	env_of "$wf" | grep -q 'HEAD_SHA: \${{ github.event.pull_request.head.sha }}' &&
		pass "acceptance/R23: $name hands the step the head commit" ||
		fail "acceptance/R23: $name — no HEAD_SHA from the head sha"
done
[ "$(step_of "$TPL")" = "$(step_of "$KITWF")" ] && [ -n "$(step_of "$TPL")" ] &&
	pass "acceptance/R23: the shipped workflow and the kit's run the same step" ||
	fail "acceptance/R23: the two workflows' acceptance steps differ, or one is missing"
awk '/^  acceptance:/ { on = 1 } on && /fetch-depth: 0/ { f = 1 } END { exit !f }' "$KITWF" &&
	pass "acceptance/R23: the kit's acceptance job checks out full history" ||
	fail "acceptance/R23: the kit's acceptance job has no fetch-depth: 0"
STEP=$(step_of "$TPL")

# kit_scripts <repo> — the guard and its helpers committed on main, as a
# consumer's bootstrap leaves them.
kit_scripts() {
	git -C "$1" checkout -q main
	for f in acceptance-guard.sh policy.sh vocab.sh vocab.config.sh requirement.lib.sh; do
		cp "$KIT/scripts/$f" "$1/scripts/$f"
	done
	t_commit "$1" "chore: the kit's scripts" >/dev/null
	git -C "$1" checkout -q work && git -C "$1" rebase -q main >/dev/null 2>&1
}
# run_step <repo> — the step's script, run in the repo as the runner would.
run_step() {
	t_exec sh -c 'cd "$1" && BASE_SHA=$(git rev-parse main) HEAD_SHA=$(git rev-parse HEAD) POLICY_BASE=$(git rev-parse main) sh -ec "$2"' _ "$1" "$STEP"
}
fp_repo
R=$REPO
kit_scripts "$R"
run_step "$R"
expect_status 0 "acceptance/R36: a pull request leaving the approved file alone passes the step"
printf 'weakened\n' >>"$R/$TF"
printf '#!/bin/sh\nexit 0\n' >"$R/scripts/acceptance-guard.sh"
t_commit "$R" "test: weaken, and make the guard always pass" >/dev/null
run_step "$R"
[ "$T_STATUS" != 0 ] && pass "acceptance/R36: a PR that edits the guard to always pass still fails — the base's guard judged it" ||
	fail "acceptance/R36: the head's edited guard judged its own PR"
expect_out_has "changed: T-90 report/R3 $TF" "acceptance/R36: the base's guard printed the changed: line"
fp_repo
R=$REPO
run_step "$R"
expect_status 0 "a base with no acceptance guard yet: the step passes"
expect_out_has "::notice::" "and says so in a notice"

t_done "acceptance guard"
