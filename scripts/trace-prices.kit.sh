#!/bin/sh
# scripts/trace-prices.kit.sh — refresh the KIT'S OWN price table from the two
# machine-readable sources. Not shipped.
#
# ADR-0008 clause 6 prices a trace on READ, from a table in the policy file, so
# that a price correction reaches the whole past and no event is ever rewritten.
# PRD #237 rejected the obvious alternative — fetching prices at query time —
# for three reasons that all still hold: a cost would depend on network access,
# one trace would total differently on two days, and a vendor URL plus a parser
# would enter a SHARED-LAYER script. The table stays the priced source.
#
# What that leaves is a dated claim that rots quietly, and two answers to it.
# `scripts/trace.sh` prints the advisory when the date goes past the window.
# THIS script is the other half: the refresh, on demand, with the network, in a
# file no consumer receives — bootstrap.sh's KIT_ONLY list deletes it, the same
# way it deletes tests/ and scripts/trace.kit.config.sh beside it. The posture
# is scripts/mutation.kit.sh's exactly: kit-only, operator-invoked, network
# required, NEVER a gate, and it commits nothing.
#
# Usage:
#   sh scripts/trace-prices.kit.sh --check [--source <url|file>] [--cross <url|file>]
#   sh scripts/trace-prices.kit.sh --write [--source <url|file>] [--cross <url|file>]
#
# Exit: 0 the table matches the primary source (--check) or was rewritten
#         (--write); 1 --check found drift; 2 a usage error, a source that could
#         not be read or parsed, a mapped model the primary source does not
#         price, or the two sources disagreeing past TRACE_PRICES_DISAGREE_PCT.
#
# THE MODE IS ALWAYS EXPLICIT. A script whose default rewrote a policy file
# would be one typo away from replacing the operator's own dated claim, so no
# arguments is a usage error rather than a write.
#
# THE SOURCES.
#   primary   LiteLLM's model_prices_and_context_window.json, read raw from
#             GitHub: one object per model key, four costs PER TOKEN.
#   cross     OpenRouter's /api/v1/models: a `data` array, `pricing` strings
#             PER TOKEN. It is a cross-check and not a second opinion to
#             average — where the two disagree past the threshold this script
#             REFUSES and prints both, and the vendors' own pages (named in the
#             twin) are the tie-breaker a human reads.
# Both are overridable with --source / --cross, which is how the suite points
# them at fixture files: a URL is fetched with curl, anything else is read as a
# path, so the whole comparison is testable with no network at all.
#
# NODE DOES THE JSON. Same call the adapter's usage extractor makes and for the
# same reason: a price is a number nested in an object with no guaranteed key
# order, and an awk parser for that would be a second implementation of JSON
# with rounding of its own. This script is kit-only, so depending on node here
# costs a consumer nothing (the shared scripts still need only sh and git).
#
# IT NEVER COMMITS. It rewrites five values, one date and two revision lines in
# the policy file, prints the diff, and stops: what to do with a price change is
# the operator's call, and a commit nobody read is how a wrong number lands.

set -u

die() {
	echo "x trace-prices.kit.sh: $1" >&2
	exit "${2:-2}"
}

usage() {
	cat >&2 <<'EOF'
usage: sh scripts/trace-prices.kit.sh --check|--write [--source <url|file>] [--cross <url|file>]

  --check   compare the price table against the primary source and report.
            Exit 0 they match, 1 they drifted, 2 a source failed or the two
            sources disagree past TRACE_PRICES_DISAGREE_PCT.
  --write   rewrite the table's five values, its `Last checked:` date and its
            two source-revision lines, print the diff, and commit nothing.

The policy file is $TRACE_CONFIG, or scripts/trace.kit.config.sh.
EOF
	exit 2
}

SOURCE_URL='https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json'
CROSS_URL='https://openrouter.ai/api/v1/models'

# THE MAPPING TABLE, explicit on purpose. Four columns:
#
#   <model id as an event spells it>|<price variable suffix>|<LiteLLM key>|<OpenRouter id>
#
# Column 1 is what scripts/agents.kit.config.sh resolves and what lands in an
# event's `model` field. Column 2 is that value folded the way scripts/trace.sh
# folds it (upper-cased, every character that is not a letter or a digit an
# underscore) — written out rather than computed, so the table shows the fold
# and a typo in it is visible; the script checks the two agree before it trusts
# a row. Columns 3 and 4 are the SAME MODEL as each source names it, and the
# `codex:` prefix of column 1 is absent from both: that prefix is the
# DISPATCHER's — it says which agent harness ran the model (ADR-0005) — and no
# vendor has ever heard of it, so it is stripped for the lookup.
#
# These ids rot exactly like the ones in scripts/agents.kit.config.sh. When a
# source renames a model, --check says the primary does not price it and names
# the row to fix.
PRICE_MAP='claude-fable-5-1|CLAUDE_FABLE_5_1|claude-fable-5-1|anthropic/claude-fable-5.1
claude-opus-5-5|CLAUDE_OPUS_5_5|claude-opus-5-5|anthropic/claude-opus-5.5
claude-haiku-4-5-20251001|CLAUDE_HAIKU_4_5_20251001|claude-haiku-4-5-20251001|anthropic/claude-haiku-4.5
codex:gpt-5.6-sol|CODEX_GPT_5_6_SOL|gpt-5.6-sol|openai/gpt-5.6-sol
codex:gpt-6-astra|CODEX_GPT_6_ASTRA|gpt-6-astra|openai/gpt-6-astra'

# --- arguments --------------------------------------------------------------
mode=
while [ $# -gt 0 ]; do
	case $1 in
	--check | --write)
		[ -z "$mode" ] || die "--check and --write are two modes; name one"
		mode=${1#--}
		shift
		;;
	--source)
		[ $# -ge 2 ] || usage
		SOURCE_URL=$2
		shift 2
		;;
	--cross)
		[ $# -ge 2 ] || usage
		CROSS_URL=$2
		shift 2
		;;
	*) usage ;;
	esac
done
[ -n "$mode" ] || usage

# --- ground -----------------------------------------------------------------
# The policy file is resolved BEFORE the cd below, against the caller's own
# directory, so a relative TRACE_CONFIG means what the caller typed rather than
# what the repo root happens to hold — the same thing it means to scripts/trace.sh.
policy=${TRACE_CONFIG:-}
if [ -n "$policy" ]; then
	[ -f "$policy" ] || die "TRACE_CONFIG=$policy does not exist"
	policy=$(cd "$(dirname "$policy")" && pwd -P)/$(basename "$policy")
fi

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$root" || exit 2
[ -f VERSION ] && [ -f scripts/trace.sh ] || die "$root is not the kit — no VERSION, or no scripts/trace.sh whose table this would refresh"
[ -n "$policy" ] || policy=$root/scripts/trace.kit.config.sh
[ -f "$policy" ] || die "$policy does not exist — there is no price table to refresh"

command -v node >/dev/null 2>&1 ||
	die "node is not on PATH, and the JSON is node's job here (see this file's header)"

# The policy file is DATA and this script is the only thing that writes it, so
# reading it is a source — the same thing scripts/trace.sh does with it. And
# sourcing is executing, so what the caller ASKED FOR is saved across it and
# assigned again afterwards: a policy file that set SOURCE_URL, CROSS_URL, mode
# or the mapping table would otherwise win over the command line silently.
# scripts/trace.sh guards its own TRACE_DIR the same way, for the same reason —
# a policy file must not be able to answer a question it was not asked (L-3,
# review of PR #294).
_said_source=$SOURCE_URL
_said_cross=$CROSS_URL
_said_mode=$mode
_said_map=$PRICE_MAP
# shellcheck disable=SC1090
. "$policy"
SOURCE_URL=$_said_source
CROSS_URL=$_said_cross
mode=$_said_mode
PRICE_MAP=$_said_map
threshold=${TRACE_PRICES_DISAGREE_PCT:-}
[ -n "$threshold" ] ||
	die "TRACE_PRICES_DISAGREE_PCT is not set in $policy — how far the two sources may differ before this refuses is policy, not a constant in a script"
# A value has to carry a DIGIT: '.' passed a digits-and-one-dot check, became
# NaN in the comparison, and `worst > NaN` is false for every pair — so the
# refusal that is the whole reason for a cross-check never fired and a disputed
# price would have been written (M-2, review of PR #294). node re-checks it.
case $threshold in
*[!0-9.]* | *.*.*) die "TRACE_PRICES_DISAGREE_PCT='$threshold' is not a percentage" ;;
*[0-9]*) ;;
*) die "TRACE_PRICES_DISAGREE_PCT='$threshold' carries no digit — give a percentage, such as '5'" ;;
esac

work=$(mktemp -d "${TMPDIR:-/tmp}/trace-prices.XXXXXX") || exit 2
# The rewrite's output file lands BESIDE the policy file, not in $work: /tmp is
# usually another filesystem, where `mv` is a copy-then-unlink rather than the
# atomic rename craft §11 asks for (L-2, review of PR #294). Declared here so
# the trap can name it before there is one.
out=
trap 'rm -rf "$work"; [ -n "$out" ] && rm -f "$out"' EXIT INT TERM HUP

# --- fetch ------------------------------------------------------------------
# A URL goes through curl; anything else is a path. One function, so --source
# and --cross behave identically and the suite's fixtures travel the same road
# the network does.
fetch() {
	case $1 in
	http://* | https://*)
		command -v curl >/dev/null 2>&1 || die "curl is not on PATH, and $1 is a URL"
		curl -fsSL --max-time 60 "$1" >"$2" || die "could not fetch $1 (curl exit $?) — this script needs the network, like scripts/mutation.kit.sh"
		;;
	*)
		[ -f "$1" ] || die "$1 is neither a URL nor a readable file"
		cat "$1" >"$2" || die "could not read $1"
		;;
	esac
	[ -s "$2" ] || die "$1 answered with nothing"
}

fetch "$SOURCE_URL" "$work/primary.json"
fetch "$CROSS_URL" "$work/cross.json"

# The REVISION of each payload: git's own hash of the bytes that were read.
# An ETag would be the server's word for it and a date would be this machine's;
# a content hash is checkable by anyone holding the same file, which is what
# makes the line in the policy file worth reading later.
primary_rev=$(git hash-object "$work/primary.json") || die "could not hash the primary payload"
cross_rev=$(git hash-object "$work/cross.json") || die "could not hash the cross-check payload"
today=$(date -u +%Y-%m-%d)

# --- compare ----------------------------------------------------------------
# The current values, one `<suffix><TAB><value>` line each, read out of the
# sourced policy file so node compares against what the table actually holds.
: >"$work/current.tsv"
printf '%s\n' "$PRICE_MAP" | while IFS='|' read -r _mid suffix _lkey _okey; do
	eval "_val=\${TRACE_PRICE_$suffix:-}"
	printf '%s\t%s\n' "$suffix" "$_val" >>"$work/current.tsv"
done

cat >"$work/compare.mjs" <<'JS'
import { readFileSync } from "node:fs";

const fail = (m) => { process.stderr.write("x trace-prices.kit.sh: " + m + "\n"); process.exit(2); };
const read = (path, what) => {
  try { return JSON.parse(readFileSync(path, "utf8")); }
  catch (e) { fail("the " + what + " source is not readable JSON: " + e.message); }
};

const primary = read(process.env.TP_PRIMARY, "primary");
const cross = read(process.env.TP_CROSS, "cross-check");

// Four fields, in the order the four tok_* fields sit in an event, under each
// source's own spelling. Absent is not zero: a source that says nothing about
// cache reads has no opinion, and inventing 0 for it would both price a wave
// wrong and manufacture a disagreement.
const LITELLM = ["input_cost_per_token", "output_cost_per_token",
  "cache_creation_input_token_cost", "cache_read_input_token_cost"];
const OPENROUTER = ["prompt", "completion", "input_cache_write", "input_cache_read"];

// Per MILLION tokens, to six decimals, then trailing zeros trimmed so the
// written value reads the way a human would type it (4, not 4.000000).
const perMillion = (n) => {
  const s = (n * 1e6).toFixed(6);
  return s.includes(".") ? s.replace(/0+$/, "").replace(/\.$/, "") : s;
};
const num = (v) => {
  if (v === undefined || v === null || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? n : null;
};

const fromPrimary = (key) => {
  const e = primary[key];
  if (!e || typeof e !== "object") return { missing: "no entry for " + key };
  const out = [];
  for (const f of LITELLM) {
    const n = num(e[f]);
    if (n === null) return { missing: key + " has no usable " + f };
    out.push(n);
  }
  return { prices: out };
};

if (!cross || !Array.isArray(cross.data)) fail("the cross-check source has no `data` array — is it OpenRouter's /api/v1/models?");
const crossIndex = new Map();
for (const m of cross.data) if (m && typeof m.id === "string") crossIndex.set(m.id, m);
const fromCross = (id) => {
  const e = crossIndex.get(id);
  if (!e || !e.pricing || typeof e.pricing !== "object") return { missing: "no entry for " + id };
  return { prices: OPENROUTER.map((f) => num(e.pricing[f])) };
};

const current = new Map();
for (const line of readFileSync(process.env.TP_CURRENT, "utf8").split("\n")) {
  if (!line) continue;
  const [suffix, value = ""] = line.split("\t");
  current.set(suffix, value);
}

const threshold = Number(process.env.TP_THRESHOLD);
if (!Number.isFinite(threshold) || threshold < 0) fail("TRACE_PRICES_DISAGREE_PCT is not a usable percentage: " + JSON.stringify(process.env.TP_THRESHOLD) + " — a threshold that is NaN makes every comparison false, so nothing would ever be refused");
const EPS = 1e-9;
const rows = [];
for (const line of process.env.TP_MAP.split("\n")) {
  if (!line) continue;
  const [mid, suffix, lkey, okey] = line.split("|");
  const fold = mid.toUpperCase().replace(/[^A-Z0-9]/g, "_");
  if (fold !== suffix) fail("the mapping table is inconsistent: " + mid + " folds to " + fold + ", but the table says " + suffix);

  const p = fromPrimary(lkey);
  if (p.missing) { rows.push([mid, suffix, current.get(suffix) ?? "", "-", "-", "-", "no-primary", p.missing]); continue; }
  const primaryStr = p.prices.map(perMillion).join(",");

  const c = fromCross(okey);
  if (c.missing) { rows.push([mid, suffix, current.get(suffix) ?? "", primaryStr, "-", "-", "no-cross", c.missing]); continue; }
  const crossStr = c.prices.map((n) => (n === null ? "?" : perMillion(n))).join(",");

  let worst = 0, worstField = "";
  for (let i = 0; i < 4; i++) {
    if (c.prices[i] === null) continue;            // no opinion, not a conflict
    const a = p.prices[i], b = c.prices[i];
    const scale = Math.max(Math.abs(a), Math.abs(b));
    const pct = scale < EPS ? 0 : (Math.abs(a - b) / scale) * 100;
    if (pct > worst) { worst = pct; worstField = LITELLM[i]; }
  }
  if (worst > threshold) {
    rows.push([mid, suffix, current.get(suffix) ?? "", primaryStr, crossStr, worst.toFixed(1), "disagree", worstField]);
    continue;
  }

  // Drift is NUMERIC, never string equality: '0.20' and '0.2' are the same
  // price, and a refresh that reported that as drift would rewrite the table
  // every time it ran. And it is compared against what a WRITE WOULD PRODUCE —
  // the per-million figure, rounded — not against the source's per-token
  // number, which is a millionth of the table's unit and never equal to it.
  const wouldWrite = primaryStr.split(",").map(Number);
  const held = (current.get(suffix) ?? "").split(",").map(Number);
  const same = held.length === 4 && held.every((x, i) => Number.isFinite(x) && Math.abs(x - wouldWrite[i]) < EPS);
  rows.push([mid, suffix, current.get(suffix) ?? "", primaryStr, crossStr, worst.toFixed(1), same ? "same" : "drift", ""]);
}
// THE UNIT SEPARATOR, not a tab: tab is IFS whitespace, so the shell's `read`
// collapses a run of them and an EMPTY column shifts every later field one to
// the left — which turned "the table has no value for this model" into a row
// whose status field held a number, matched no case, and was counted as
// neither drift nor refusal (H-1, review of PR #294). \x1f is not IFS
// whitespace, so an empty field stays an empty field.
process.stdout.write(rows.map((r) => r.join("\x1f")).join("\n") + "\n");
JS

TP_PRIMARY="$work/primary.json" TP_CROSS="$work/cross.json" \
	TP_CURRENT="$work/current.tsv" TP_MAP="$PRICE_MAP" TP_THRESHOLD="$threshold" \
	node "$work/compare.mjs" >"$work/rows.tsv" || exit 2

# --- report -----------------------------------------------------------------
# stdout carries the answer, the way every script in this repo does. The report
# names the variable as well as the model, because the variable is what the
# operator has to find in the file.
echo "price table: $policy"
echo "  primary:   $SOURCE_URL"
echo "  cross:     $CROSS_URL"
echo

drift=0
refuse=0
_US=$(printf '\037')
while IFS="$_US" read -r mid suffix cur prim crs worst status why; do
	printf '%s  (TRACE_PRICE_%s)\n' "$mid" "$suffix"
	printf '    table    %s\n' "${cur:-(unset)}"
	printf '    primary  %s\n' "$prim"
	# THE TABLE can be missing an entry too, and this script rewrites lines — it
	# does not add them. A write over a table with no line for a mapped model
	# would re-date the file with the entry still absent, which is the worst of
	# both: a fresh claim over a hole (H-1, review of PR #294).
	if ! grep -q "^TRACE_PRICE_$suffix=" "$policy"; then
		printf '    REFUSED — %s has no TRACE_PRICE_%s line. This refresh rewrites entries, it never adds them: put the line in with any value and run again.\n\n' "$policy" "$suffix"
		refuse=$((refuse + 1))
		continue
	fi
	case $status in
	same)
		printf '    cross    %s   (worst field %s%% apart)\n    same\n' "$crs" "$worst"
		;;
	drift)
		printf '    cross    %s   (worst field %s%% apart)\n    DRIFT\n' "$crs" "$worst"
		drift=$((drift + 1))
		;;
	disagree)
		printf '    cross    %s\n    REFUSED — the two sources are %s%% apart on %s, past the %s%% threshold. The vendor page is the tie-breaker.\n' "$crs" "$worst" "$why" "$threshold"
		refuse=$((refuse + 1))
		;;
	no-primary)
		printf '    REFUSED — the primary source does not price it: %s. Fix the row in this script or the model id in the table.\n' "$why"
		refuse=$((refuse + 1))
		;;
	no-cross)
		printf '    REFUSED — the cross-check source does not price it: %s. Two sources is the rule; one is a number nobody checked.\n' "$why"
		refuse=$((refuse + 1))
		;;
	*)
		# A row whose status is none of the five is a BUG in this script, not a
		# verdict about a price: counted as a refusal so it can never be
		# mistaken for agreement (the shape H-1 arrived in).
		printf '    REFUSED — this script produced the unknown status %s for that row; that is a bug here, not a price change.\n' "$status"
		refuse=$((refuse + 1))
		;;
	esac
	echo
done <"$work/rows.tsv"

if [ "$refuse" -gt 0 ]; then
	echo "refused: $refuse of the mapped models could not be priced from two agreeing sources; nothing was written." >&2
	exit 2
fi

if [ "$mode" = check ]; then
	if [ "$drift" -gt 0 ]; then
		printf 'drift: %s of the mapped entries differ from the primary source. Run --write to take them, or the vendor pages to argue.\n' "$drift"
		exit 1
	fi
	echo "same: every entry matches the primary source, and the cross-check agrees."
	exit 0
fi

# --- write ------------------------------------------------------------------
# Four shapes of line and nothing else: the five values, the first `Last
# checked:` date, and the two revision lines. Rewritten through a temporary file
# and one rename (craft §11), so a policy file is never half-written — and from
# a BACKUP that is also what the diff is taken against.
cp "$policy" "$work/before.sh"
out=$(mktemp "$(dirname "$policy")/.trace-prices.XXXXXX") || die "could not write beside $policy"
awk -v vals="$work/rows.tsv" -v today="$today" -v sep="$_US" \
	-v prim="$SOURCE_URL revision $primary_rev, fetched $today" \
	-v crs="$CROSS_URL revision $cross_rev, fetched $today" '
BEGIN {
	while ((getline line < vals) > 0) {
		n = split(line, f, sep)
		if (n >= 4) newv[f[2]] = f[4]
	}
}
{
	line = $0
	for (v in newv) {
		if (index(line, "TRACE_PRICE_" v "=") == 1) {
			line = "TRACE_PRICE_" v "=\x27" newv[v] "\x27"
			break
		}
	}
	if (!dated && line ~ /Last checked: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) {
		sub(/Last checked: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/, "Last checked: " today, line)
		dated = 1
	}
	if (index(line, "#   primary: ") == 1) line = "#   primary: " prim
	if (index(line, "#   cross: ") == 1) line = "#   cross:   " crs
	print line
}' "$work/before.sh" >"$out" || die "the rewrite failed; $policy is untouched"

# Still a policy file. A rewrite that broke the syntax would be found by the
# next `summary`, which is far too late — and it is checked BEFORE the rename,
# so the file the operator has never stops being the file they had.
sh -n "$out" || die "the rewritten file is not valid POSIX sh; $policy is untouched"
# Same directory, so this is a rename and not a copy: the policy file is either
# the old one or the new one, never half of either (craft §11).
mv "$out" "$policy" || die "could not replace $policy"
# Nothing is left at $out, so the trap has nothing to remove.
out=

echo "rewritten: $policy"
echo
diff -u "$work/before.sh" "$policy" || true
echo
echo "Nothing was committed. Read the diff, then commit it yourself — a price change is a claim, and the commit is where you make it."
exit 0
