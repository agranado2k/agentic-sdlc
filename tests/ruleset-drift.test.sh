#!/bin/sh
# tests/ruleset-drift.test.sh — the default branch's rules are held to a
# committed snapshot (ticket #951, factory T-85).
#
# The root guard refuses an agent's edit in the root checkout, and the agent's
# forge token carries no administration permission; neither one NOTICES a
# change to the rules already made. scripts/ruleset-drift.kit.sh does: it
# fetches the live rulesets, normalises them the way the committed snapshot
# .github/rulesets.kit.json is normalised — ids, timestamps and links stripped,
# lists sorted, rules keyed by type, required checks by context, bypass actors
# by actor — and exits 1 naming each field path that differs. It also exits 1
# when a required status check names no job in the repository's workflows: the
# `kit` context that blocked every PR on 2026-10-30 was exactly that.
#
# Every case runs against a STUB forge CLI on PATH that answers the two GETs
# from fixture files and logs its argv, so the suite needs no network and no
# token, and can prove the script never asks for a write and never prints the
# token it was handed.
#
# Usage: sh tests/ruleset-drift.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=./lib.sh
. "$ROOT/tests/lib.sh"
t_init

DRIFT="$ROOT/scripts/ruleset-drift.kit.sh"
TOKEN=t85-sentinel-token-value

if ! command -v jq >/dev/null 2>&1; then
	note "no jq on PATH — the drift script's cases cannot run here; CI's runner has it"
	t_done "the default branch's rules are held to their snapshot"
fi

# --- the stub forge -----------------------------------------------------------
# `gh api <path>` prints $STUB_DIR/list.json for the list and $STUB_DIR/<id>.json
# for one ruleset; STUB_FAIL makes every call fail the way a 401 does.
STUBDIR="$SCRATCH/bin"
mkdir -p "$STUBDIR"
cat >"$STUBDIR/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_DIR/argv.log"
[ -n "${STUB_FAIL:-}" ] && { echo "gh: Bad credentials (HTTP 401)" >&2; exit 1; }
[ "$1" = api ] || { echo "stub: not an api call: $*" >&2; exit 64; }
for a in "$@"; do
	case "$a" in -X | --method | -f | -F | --field | --raw-field | --input) echo "stub: a write was asked: $*" >&2; exit 65 ;; esac
done
path=
for a in "$@"; do case "$a" in repos/*) path=$a ;; esac; done
case "$path" in
'repos/{owner}/{repo}/rulesets') cat "$STUB_DIR/list.json" ;;
'repos/{owner}/{repo}/rulesets/'*) id=${path##*/}; [ -f "$STUB_DIR/$id.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }; cat "$STUB_DIR/$id.json" ;;
*) echo "stub: unknown path: $path" >&2; exit 64 ;;
esac
EOF
chmod +x "$STUBDIR/gh"
STUB_DIR="$SCRATCH/forge"
mkdir -p "$STUB_DIR"
export STUB_DIR
PATH="$STUBDIR:$PATH"
export PATH

# The fixture workflows: two jobs, one named, one known by its id.
WF="$SCRATCH/workflows"
mkdir -p "$WF"
cat >"$WF/ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  guards:
    name: Guard test tiers + demo
    runs-on: ubuntu-latest
    steps:
      - run: true
  self-host:
    runs-on: ubuntu-latest
    steps:
      - name: The kit passes its own gate
        run: true
  docs:
    name: "The kit passes its own gate"
    runs-on: ubuntu-latest
    steps:
      - run: true
EOF

# live <ruleset json> — the stub's answer: a list naming id 7 and the ruleset.
live() {
	printf '[{"id":7,"name":"main","target":"branch","enforcement":"active","node_id":"X","_links":{"self":{"href":"https://example.invalid/7"}},"created_at":"2026-10-30T10:53:36Z","updated_at":"2026-10-31T11:59:45Z"}]\n' >"$STUB_DIR/list.json"
	printf '%s\n' "$1" >"$STUB_DIR/7.json"
}

# The ruleset as the forge returns it, with every field the snapshot drops.
BASE='{"id":7,"name":"main","target":"branch","source_type":"Repository","source":"o/r","enforcement":"active",
"conditions":{"ref_name":{"exclude":[],"include":["~DEFAULT_BRANCH"]}},
"rules":[{"type":"deletion"},{"type":"non_fast_forward"},
{"type":"pull_request","parameters":{"required_approving_review_count":0,"allowed_merge_methods":["squash","merge","rebase"]}},
{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,"required_status_checks":[{"context":"The kit passes its own gate","integration_id":15368},{"context":"Guard test tiers + demo","integration_id":15368}]}}],
"node_id":"RRS_x","created_at":"2026-10-30T10:53:36Z","updated_at":"2026-10-31T11:59:45Z",
"bypass_actors":[],"current_user_can_bypass":"never","_links":{"self":{"href":"https://example.invalid/7"},"html":{"href":"https://example.invalid/r/7"}}}'

# with <jq program> — BASE changed by one edit, the live answer for one case.
with() { printf '%s' "$BASE" | jq -c "$1"; }

SNAP="$SCRATCH/rulesets.kit.json"
run() { t_exec env GH_TOKEN="$TOKEN" sh "$DRIFT" "$@"; }
check() { run check --snapshot "$SNAP" --workflows "$WF"; }

# ---------------------------------------------------------------------------
banner "1. print writes the normalised rules a snapshot holds"
# ---------------------------------------------------------------------------
live "$BASE"
run print
expect_status 0 "print exits 0 on a readable live answer"
printf '%s\n' "$T_OUT" >"$SNAP"
for k in '"id"' node_id created_at updated_at _links current_user_can_bypass source_type '"source"'; do
	expect_out_lacks "$k" "the snapshot drops $k"
done
expect_out_has '"enforcement": "active"' "the snapshot holds the enforcement"
expect_out_has '"~DEFAULT_BRANCH"' "the snapshot holds the target conditions"
expect_out_has '"bypass_actors": {}' "the snapshot holds the bypass actors, none"
expect_out_has '"Guard test tiers + demo"' "the snapshot keys a required check by its context"
expect_out_has '"deletion": true' "a rule with no parameters is held by its type"
expect_out_has '"merge",' "the snapshot holds a rule's parameters"
[ "$(printf '%s' "$T_OUT" | jq -r '.main.rules.pull_request.allowed_merge_methods | join(",")')" = "merge,rebase,squash" ] &&
	pass "a list is sorted, so it diffs cleanly" || fail "a list kept the forge's order"

# ---------------------------------------------------------------------------
banner "2. A live answer equal to the snapshot passes (GREEN)"
# ---------------------------------------------------------------------------
check
expect_status 0 "the live rules equal to the snapshot pass"
expect_out_has "match" "the pass says the rules match"

# Same rules, different ids, timestamps, links and list order: still equal.
live "$(with '.id=99 | .updated_at="2027-01-01T00:00:00Z" | ._links.self.href="https://example.invalid/x" | .rules|=reverse | (.rules[]|select(.type=="required_status_checks")|.parameters.required_status_checks)|=reverse')"
printf '[{"id":7,"name":"main"}]\n' >"$STUB_DIR/list.json"
check
expect_status 0 "ids, timestamps, links and order are not drift"

# ---------------------------------------------------------------------------
banner "3. Each kind of drift fails, naming the field (RED)"
# ---------------------------------------------------------------------------
# drifts <label> <jq edit> <field path> — the edit is drift, named by its path.
drifts() {
	live "$(with "$2")"
	check
	expect_status 1 "$1 fails the check"
	expect_out_has "drift: $3" "$1 is named as $3"
}
drifts "a removed rule" 'del(.rules[]|select(.type=="deletion"))' 'main.rules.deletion'
drifts "an added bypass actor" '.bypass_actors=[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]' 'main.bypass_actors'
expect_out_has 'RepositoryRole:5' "the added actor is named by type and id"
drifts "a changed required check" '(.rules[]|select(.type=="required_status_checks")|.parameters.required_status_checks[0].integration_id)=1' 'main.rules.required_status_checks.required_status_checks["The kit passes its own gate"].integration_id'
drifts "enforcement turned off" '.enforcement="disabled"' 'main.enforcement'
expect_out_has 'snapshot: "active"' "the snapshot's value is shown"
expect_out_has 'live: "disabled"' "the live value is shown"
drifts "a changed parameter" '(.rules[]|select(.type=="pull_request")|.parameters.required_approving_review_count)=1' 'main.rules.pull_request.required_approving_review_count'
drifts "a ruleset added" '.name="other"' 'other'
expect_out_has 'drift: main' "the ruleset no longer live is named too"

# ---------------------------------------------------------------------------
banner "4. A required check naming no workflow job fails (RED)"
# ---------------------------------------------------------------------------
# The `kit` context of 2026-10-30: in the snapshot AND live, so no drift — and
# still a check that can never report.
ORPHAN='(.rules[]|select(.type=="required_status_checks")|.parameters.required_status_checks)+=[{"context":"kit","integration_id":15368}]'
live "$(with "$ORPHAN")"
run print
printf '%s\n' "$T_OUT" >"$SNAP"
check
expect_status 1 "a required check no job reports fails the check"
expect_out_has "no-job: kit" "the orphan context is named"
expect_out_lacks "drift:" "the orphan is not reported as drift"
expect_out_lacks "no-job: Guard test tiers + demo" "a check a named job reports is not an orphan"
expect_out_lacks "no-job: The kit passes its own gate" "a check a quoted job name reports is not an orphan"

# A job known only by its id reports under the id.
live "$(with '(.rules[]|select(.type=="required_status_checks")|.parameters.required_status_checks)+=[{"context":"self-host","integration_id":15368}]')"
run print
printf '%s\n' "$T_OUT" >"$SNAP"
check
expect_status 0 "a check naming an unnamed job's id passes"

# A workflows directory with no workflow cannot vouch for any check.
mkdir -p "$SCRATCH/empty"
run check --snapshot "$SNAP" --workflows "$SCRATCH/empty"
expect_status 1 "no workflow at all leaves every required check orphaned"
expect_out_has "no-job: self-host"

# ---------------------------------------------------------------------------
banner "5. What the script cannot judge, it refuses (exit 3)"
# ---------------------------------------------------------------------------
live "$BASE"
run print
printf '%s\n' "$T_OUT" >"$SNAP"

# A token without the administration permission sees no bypass_actors at all:
# a hidden bypass actor is exactly the drift this exists for, so fail closed.
live "$(with 'del(.bypass_actors)')"
check
expect_status 3 "a ruleset whose bypass actors the token cannot see is refused"
expect_err_has "bypass actors" "the refusal names what it could not read"
expect_err_has "RULESET_READ_TOKEN" "and the secret that fixes it"

live "$BASE"
STUB_FAIL=1 t_exec env GH_TOKEN="$TOKEN" STUB_FAIL=1 sh "$DRIFT" check --snapshot "$SNAP" --workflows "$WF"
expect_status 3 "a failed fetch is refused, never read as no rules"

run check --snapshot "$SCRATCH/absent.json" --workflows "$WF"
expect_status 2 "a missing snapshot is a caller error"
run frobnicate
expect_status 2 "an unknown subcommand is a caller error"

# ---------------------------------------------------------------------------
banner "6. It reads, and prints no token"
# ---------------------------------------------------------------------------
: >"$STUB_DIR/argv.log"
live "$(with '.enforcement="disabled"')"
check
expect_unsaid "$TOKEN" "the token never reaches either stream"
grep -q 'stub: a write' "$STUB_DIR/argv.log" && fail "the script asked the forge for a write" ||
	pass "every forge call is a GET"
grep -q 'rulesets/7' "$STUB_DIR/argv.log" && pass "each ruleset is fetched by id, for its bypass actors" ||
	fail "the ruleset was never fetched by id"

# ---------------------------------------------------------------------------
banner "7. The kit's own snapshot and workflow"
# ---------------------------------------------------------------------------
REAL="$ROOT/.github/rulesets.kit.json"
if [ -f "$REAL" ]; then
	pass "the kit commits its rules' snapshot"
	[ "$(jq -S . "$REAL")" = "$(cat "$REAL")" ] && pass "the snapshot is stored normalised: sorted keys, pretty" ||
		fail "the snapshot is not in the shape print writes"
	jq -e '[.. | objects | keys[]] | any(. == "id" or . == "node_id" or . == "created_at" or . == "_links")' "$REAL" >/dev/null &&
		fail "the snapshot carries an id, a timestamp or a link" || pass "the snapshot carries no id, timestamp or link"
	# Every required check it holds names a job the kit's own workflows run.
	for ctx in $(jq -r '.[].rules.required_status_checks.required_status_checks // {} | keys[] | @base64' "$REAL"); do
		c=$(printf '%s' "$ctx" | base64 -d)
		grep -rqF -- "name: $c" "$ROOT/.github/workflows" || fail "the snapshot requires '$c', which no kit job is named"
	done
	pass "every required check in the snapshot was looked up in the kit's workflows"
else
	fail "no .github/rulesets.kit.json"
fi

W="$ROOT/.github/workflows/kit-rules.yml"
assert_file_has "$W" "schedule:" "the drift check runs daily"
assert_file_has "$W" "workflow_dispatch:" "and on demand"
assert_file_has "$W" "branches: [main]" "and on every push to the default branch"
assert_file_has "$W" "sh scripts/ruleset-drift.kit.sh check" "it runs the drift script"
assert_file_has "$W" "secrets.RULESET_READ_TOKEN" "with the read-only secret, by name"
assert_file_lacks "$W" ": write" "it asks for no write permission"
assert_file_has "$ROOT/README.md" "RULESET_READ_TOKEN" "the README says how to make the secret"

t_done "the default branch's rules are held to their snapshot"
