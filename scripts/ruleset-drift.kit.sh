#!/bin/sh
# scripts/ruleset-drift.kit.sh — the default branch's rules, held to a
# committed snapshot (ticket #951, factory T-85). KIT-ONLY, never shipped.
#
# The root guard refuses an agent's edit in the root checkout and the agent's
# forge token has no administration permission; neither notices a change to
# the rules ALREADY made, in the forge's settings page, outside any review.
# This does: it fetches every ruleset the repository holds, normalises them,
# and compares them with .github/rulesets.kit.json, whose history in git is
# the rules' history. Changing the rules is then an ordinary reviewed PR: edit
# the rules, run `print` into the snapshot, open the PR.
#
#   sh scripts/ruleset-drift.kit.sh check [--snapshot <file>] [--workflows <dir>]
#   sh scripts/ruleset-drift.kit.sh print
#
# The normal form drops ids, node ids, timestamps, links, the source and the
# caller's own bypass answer; keys every ruleset by name, every rule by type
# (a rule with no parameters is `true`), every required status check by its
# context and every bypass actor by `<actor_type>:<actor_id>`; and sorts every
# list. `print` writes it as sorted, indented JSON — the snapshot's shape.
#
# `check` prints one `drift: <field path>` per differing field, with the
# snapshot's and the live value under it, and one `no-job: <context>` per
# required status check that names no job in the workflows directory — a
# required check nothing reports blocks every PR forever (the `kit` context of
# 2026-10-30). It reads; it never writes a ruleset, and prints no token.
#
# Exit: 0 the rules match and every required check names a job; 1 drift or a
# check with no job; 2 a caller error (usage, no snapshot); 3 it cannot judge
# — no jq, a failed fetch, or a ruleset whose bypass actors the token cannot
# see. The forge hides bypass_actors from a token without the administration
# permission, and the workflow's own GITHUB_TOKEN can never hold that one, so
# CI reads through the RULESET_READ_TOKEN secret (README, "The default
# branch's rules"); a hidden bypass actor is the very drift this exists for,
# so its absence is refused, never read as none.
#
# Kit-only: it needs jq and the forge CLI, and the kit's core needs neither.
# tests/ruleset-drift.test.sh drives it against a stub forge CLI.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SNAPSHOT="$ROOT/.github/rulesets.kit.json"
WORKFLOWS="$ROOT/.github/workflows"

usage() {
	echo "usage: sh scripts/ruleset-drift.kit.sh check [--snapshot <file>] [--workflows <dir>] | print" >&2
	exit 2
}
refuse() {
	echo "ruleset-drift: $*" >&2
	exit 3
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case "$cmd" in check | print) ;; *) usage ;; esac
while [ $# -gt 0 ]; do
	case "$1" in
	--snapshot) [ $# -ge 2 ] || usage; SNAPSHOT=$2; shift 2 ;;
	--workflows) [ $# -ge 2 ] || usage; WORKFLOWS=$2; shift 2 ;;
	*) usage ;;
	esac
done
[ "$cmd" = print ] || [ -f "$SNAPSHOT" ] || {
	echo "ruleset-drift: no snapshot at $SNAPSHOT" >&2
	exit 2
}

command -v jq >/dev/null 2>&1 || refuse "no jq on PATH: cannot normalise the rules"
command -v gh >/dev/null 2>&1 || refuse "no forge CLI (gh) on PATH"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ruleset-drift.XXXXXX") || exit 3
trap 'rm -rf "$tmp"' EXIT INT TERM HUP

# --- fetch: the list, then each ruleset by id (the list carries no rules) ----
gh api --paginate 'repos/{owner}/{repo}/rulesets' >"$tmp/list.json" 2>"$tmp/err" ||
	refuse "the forge refused the ruleset list: $(head -1 "$tmp/err")"
ids=$(jq -r '.[].id' "$tmp/list.json") || refuse "the ruleset list is not JSON"
: >"$tmp/live.jsonl"
for id in $ids; do
	case "$id" in *[!0-9]*) refuse "a ruleset id is not a number" ;; esac
	gh api "repos/{owner}/{repo}/rulesets/$id" >>"$tmp/live.jsonl" 2>"$tmp/err" ||
		refuse "the forge refused ruleset $id: $(head -1 "$tmp/err")"
done
hidden=$(jq -rs 'map(select(has("bypass_actors") | not) | .name) | join(", ")' "$tmp/live.jsonl") ||
	refuse "a ruleset answer is not JSON"
[ -z "$hidden" ] || refuse "the token cannot see the bypass actors of: $hidden — read through a token with the administration permission (the RULESET_READ_TOKEN secret, README)"

# --- normalise ------------------------------------------------------------------
NORM='
def srt: walk(if type == "array" then sort else . end);
def checks: if type == "object" and has("required_status_checks")
	then .required_status_checks |= (map({key: .context, value: del(.context)}) | from_entries)
	else . end;
map({key: .name, value: {
	target, enforcement,
	conditions: ((.conditions // {}) | srt),
	bypass_actors: ((.bypass_actors // []) | map({key: "\(.actor_type):\(.actor_id // "any")", value: .bypass_mode}) | from_entries),
	rules: ((.rules // []) | map({key: .type, value: ((.parameters // true) | checks | srt)}) | from_entries)
}}) | from_entries'
jq -s -S "$NORM" "$tmp/live.jsonl" >"$tmp/live.norm" || refuse "cannot normalise the live rules"

if [ "$cmd" = print ]; then
	cat "$tmp/live.norm"
	exit 0
fi

# --- compare, field by field ----------------------------------------------------
# One `<path>\t<json value>` line per leaf: a scalar, a whole list, an empty object.
FLAT='
def seg: if type == "number" then "[\(.)]"
	elif test("^[A-Za-z_][A-Za-z0-9_]*$") then ".\(.)"
	else "[\(tojson)]" end;
def flat($p): if type == "object" and length > 0
	then (to_entries[] as $e | $e.value | flat($p + [$e.key]))
	else [$p, .] end;
flat([]) | "\(.[0] | map(seg) | join("") | ltrimstr("."))\t\(.[1] | tojson)"'
jq -r "$FLAT" "$SNAPSHOT" >"$tmp/snap.flat" 2>/dev/null || {
	echo "ruleset-drift: the snapshot at $SNAPSHOT is not JSON" >&2
	exit 2
}
jq -r "$FLAT" "$tmp/live.norm" >"$tmp/live.flat" || refuse "cannot flatten the live rules"

status=0
awk -F '\t' '
	FNR == NR { s[$1] = $2; seen[$1] = 1; next }
	{ l[$1] = $2; seen[$1] = 1 }
	END {
		for (p in seen) {
			sv = (p in s) ? s[p] : "(absent)"
			lv = (p in l) ? l[p] : "(absent)"
			if (sv != lv) printf "%s\t%s\t%s\n", p, sv, lv
		}
	}' "$tmp/snap.flat" "$tmp/live.flat" | sort |
	awk -F '\t' '{ printf "drift: %s\n  snapshot: %s\n  live: %s\n", $1, $2, $3 }' >"$tmp/drift"
[ -s "$tmp/drift" ] && { cat "$tmp/drift"; status=1; }

# --- every required check names a job ---------------------------------------
# A check run's context is its job's `name:`, or the job's id when it has none.
for wf in "$WORKFLOWS"/*.yml "$WORKFLOWS"/*.yaml; do
	[ -f "$wf" ] || continue
	awk '
		function flush() { if (id != "") print (name != "" ? name : id); id = ""; name = "" }
		/^jobs:/ { injobs = 1; next }
		injobs && /^[^ #]/ { flush(); injobs = 0 }
		injobs && /^  [A-Za-z0-9_-]+:/ { flush(); id = $1; sub(/:$/, "", id); next }
		injobs && /^    name:/ {
			n = $0; sub(/^    name:[ \t]*/, "", n); sub(/[ \t]+$/, "", n)
			if (n ~ /^".*"$/ || n ~ /^\047.*\047$/) n = substr(n, 2, length(n) - 2)
			name = n
		}
		END { flush() }' "$wf"
done | sort -u >"$tmp/jobs"
jq -r '.[] | .rules.required_status_checks.required_status_checks // {} | keys[]' "$tmp/live.norm" | sort -u >"$tmp/required"
orphans=$(comm -23 "$tmp/required" "$tmp/jobs")
if [ -n "$orphans" ]; then
	printf '%s\n' "$orphans" | sed 's/^/no-job: /'
	status=1
fi

[ "$status" = 0 ] && echo "rules match snapshot: $(jq 'length' "$tmp/live.norm") ruleset(s), every required check names a job"
exit "$status"
