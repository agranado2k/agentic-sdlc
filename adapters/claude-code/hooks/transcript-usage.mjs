// transcript-usage.mjs — per-model token counts out of one agent-harness transcript.
//
//   node transcript-usage.mjs [--after <message id>] <transcript.jsonl>
//
// STDOUT is one row per model, seven space-separated fields — the four token
// fields in the order they sit in a trace event, then how far the read went:
//
//   <model> <input> <output> <cache write> <cache read> <messages> <last id>
//
// so a POSIX `while read -r` consumes it without a parser. <messages> is how
// many distinct assistant messages of THAT model the row counts; <last id> is
// the message id counted last in the whole read, the same on every row, and it
// is what the next read of this transcript passes as --after. A transcript with
// no assistant message — or none after the anchor — prints nothing and exits 0.
// EXIT 2 is shape drift, with the line number and the key on stderr; exit 0 is
// numbers you can trust. There is no third answer, and in particular there is
// no "best effort": the caller turns a 2 into one event that says what could
// not be read, which is worth more than a confident wrong number in a cost
// column nobody re-derives.
//
// WHY THIS IS JAVASCRIPT IN A KIT WHOSE CORE IS `sh`. De-duplication needs an
// id out of a nested object with no guaranteed key order, and a transcript's
// free text can contain the literal string `"input_tokens"` — a tool result
// quoting this very file would do it. A line-oriented text tool cannot tell
// the two apart; a real parser can, in one branch. The hooks beside this file
// stay POSIX sh, and a machine with no node gets a recorded reason rather than
// a dead hook (see hook.lib.sh's `hook_tokens`).
//
// WHAT DE-DUPLICATION MEANS HERE (#246's Q3, PRD #237's implementation
// decision). One assistant API response with two content blocks is written as
// TWO JSONL lines that repeat the same `message.id`, the same `requestId` and a
// byte-identical `message.usage`. Summing lines counts that response twice;
// summing distinct `message.id` reproduces the rollup the agent harness itself
// writes on the transcript's last line, exactly. The request id is 1:1 with the
// message id in the capture, so it is used as a CROSS-CHECK — if two lines ever
// share a message id and disagree about anything, that is drift and it stops
// here rather than becoming a number.
//
// WHAT THIS FILE DOES NOT DO. It never reads the transcript's `cost-state`
// rollup, though that line holds per-model totals and a cost figure and would
// save all the work below. Two reasons: the cost is the vendor's
// interpretation, which ADR-0008 clause 6 keeps out of an event, and the rollup
// includes subagent tokens that live in files the session transcript never
// names — so attributing it to the session would double-count against the
// subagent events. The rollup is the SUITE's oracle, never this extractor's
// source.
//
// It also sums every assistant line of whichever file it is handed, and does
// not filter on `isSidechain`. In the captured agent-harness build a subagent's
// lines live in the subagent's own file, so the session transcript and each
// subagent transcript are disjoint and their events add up to the rollup. A
// build that inlined a subagent's lines into the session transcript would
// count them in both places; that would be shape drift of a kind no key check
// can see, and the suite's oracle assertion is what would catch it.

// --after: A RESUMED SESSION IS READ AS A DELTA (#307, PRD #237's
// implementation decision of 2026-09-30). `claude -p --resume <id>` and
// `--continue` keep the session id and APPEND to this one file, and SessionEnd
// fires at the end of every run; a compaction appends too. So an end that read
// the whole file again would count every earlier response a second time. With
// --after, every message id FIRST SEEN at or before the anchor's first line is
// taken as already counted — exactly the set a read that stopped at the anchor
// counted, because the file only ever grows — and only the ids first seen after
// it are summed. Their streamed duplicates are still checked against the first
// line either way. An anchor the file does not hold means this is not the file
// the anchor was read from, or it was rewritten: that is drift, exit 2, because
// both "count everything" and "count nothing" would be a confident wrong number.

// READ WHOLE, and the ceiling named rather than discovered: `readFileSync` plus
// `split` holds the transcript twice, and V8 refuses a string past roughly
// 512 MB with ERR_STRING_TOO_LONG — which arrives here as exit 2 and therefore
// as an honest `outcome=fail`, not as a wrong number. The largest transcript
// seen on the machine this was built on is 8 MB. A `node:readline` stream is
// the answer the day that stops being true (L-3, review of PR #291).

import { readFileSync } from "node:fs";

const NAME = "transcript-usage";

// The event's four token fields, and the usage key each one reads. The ORDER is
// the event's order, because the row is consumed positionally.
const FIELDS = [
  ["tok_in", "input_tokens"],
  ["tok_out", "output_tokens"],
  ["tok_cache_w", "cache_creation_input_tokens"],
  ["tok_cache_r", "cache_read_input_tokens"],
];

function die(message) {
  process.stderr.write(`x ${NAME}: ${message}\n`);
  process.exit(2);
}

const USAGE = "usage: node transcript-usage.mjs [--after <message id>] <transcript.jsonl>";
const args = process.argv.slice(2);
let after = null;
if (args[0] === "--after") {
  if (args.length < 2 || args[1] === "") die(USAGE);
  after = args[1];
  args.splice(0, 2);
}
const path = args[0];
if (!path || args.length > 1) die(USAGE);

let raw;
try {
  raw = readFileSync(path, "utf8");
} catch (error) {
  die(`cannot read ${path}: ${error.code ?? error.message}`);
}

/** A non-negative integer, and nothing that merely looks like one. */
const isCount = (v) => typeof v === "number" && Number.isInteger(v) && v >= 0;

/** Per-model running totals, in first-seen order. */
const totals = new Map();
/** message.id -> what the first line carrying it said, for the duplicate check. */
const seen = new Map();
/** Per-model count of the distinct messages summed, in step with `totals`. */
const counted = new Map();
/** Still at or before the anchor: ids first seen here were counted by an earlier read. */
let before = after !== null;
/** The id of the last message summed, which the next read passes as --after. */
let last = "";

let lineNo = 0;
for (const line of raw.split("\n")) {
  lineNo += 1;
  if (line.trim() === "") continue;

  let entry;
  try {
    entry = JSON.parse(line);
  } catch {
    die(`line ${lineNo} is not JSON — the transcript's shape has drifted`);
  }
  if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
    die(`line ${lineNo} is not a JSON object — the transcript's shape has drifted`);
  }
  // Assistant lines are the only ones that carry usage (#246). Anything else
  // is skipped without comment: a transcript is full of other line types and
  // the set grows on the agent harness's schedule, not this file's.
  if (entry.type !== "assistant") continue;
  // An API ERROR is written as an assistant line too, with a placeholder model
  // and zero counts. It passes every check below, and `model` is a join column
  // (ADR-0008 clause 1) — so it would grow a row in every `summary --by model`
  // that each later reader has to know to ignore. Skipped by the flag the
  // agent harness sets, and by the angle-bracket shape of the name, because one
  // of the two may be absent (M-3, review of PR #291).
  if (entry.isApiErrorMessage === true) continue;
  if (typeof entry.message?.model === "string" && entry.message.model.startsWith("<")) continue;

  const message = entry.message;
  if (message === null || typeof message !== "object") {
    die(`line ${lineNo}: an assistant line with no 'message' object — the transcript's shape has drifted`);
  }
  if (typeof message.id !== "string" || message.id === "") {
    die(`line ${lineNo}: key 'message.id' is missing or not a string, so a streamed response cannot be de-duplicated`);
  }
  // The id is the ANCHOR the next read of this transcript is handed, and the
  // hook drops an anchor outside this class rather than put it on a command
  // line — which would silently fall back to the whole-file read, the double
  // count (M-1, review of PR #316). So it is refused here, loudly, instead.
  if (!/^[A-Za-z0-9._-]+$/.test(message.id)) {
    die(`line ${lineNo}: message.id '${message.id}' is not letters, digits, dot, dash and underscore, so it cannot anchor the next read of this transcript`);
  }
  if (typeof message.model !== "string" || message.model === "") {
    die(`line ${lineNo}: key 'message.model' is missing or not a string, so these tokens belong to no model`);
  }
  // The model becomes a field on a trace event and a word in a shell `read`
  // loop. Refused here rather than escaped downstream: a model id with a space
  // in it would silently shift four numbers by one column.
  if (/[\s"\\]/.test(message.model)) {
    die(`line ${lineNo}: message.model '${message.model}' carries whitespace, a quote or a backslash, which an event cannot record unambiguously`);
  }
  const usage = message.usage;
  if (usage === null || typeof usage !== "object") {
    die(`line ${lineNo}: key 'message.usage' is missing on an assistant line — the transcript's shape has drifted`);
  }

  const counts = {};
  for (const [field, key] of FIELDS) {
    if (!isCount(usage[key])) {
      die(`line ${lineNo}: key 'message.usage.${key}' is missing or not a non-negative integer — refusing to read it as 0`);
    }
    counts[field] = usage[key];
  }
  const requestId = typeof entry.requestId === "string" ? entry.requestId : "";

  const first = seen.get(message.id);
  if (first) {
    // A streamed response, written once per content block. Everything about it
    // must repeat; anything that does not is drift, not a second response.
    if (first.model !== message.model) {
      die(`line ${lineNo}: message.id ${message.id} appears again under a different model ('${first.model}' then '${message.model}')`);
    }
    if (first.requestId !== requestId) {
      die(`line ${lineNo}: message.id ${message.id} appears again under a different requestId ('${first.requestId}' then '${requestId}')`);
    }
    for (const [field] of FIELDS) {
      if (first.counts[field] !== counts[field]) {
        die(`line ${lineNo}: message.id ${message.id} appears again with a different ${field} (${first.counts[field]} then ${counts[field]}) — de-duplicating would drop real tokens`);
      }
    }
    continue;
  }
  seen.set(message.id, { model: message.model, requestId, counts });
  if (before) {
    if (message.id === after) before = false;
    continue;
  }

  last = message.id;
  counted.set(message.model, (counted.get(message.model) ?? 0) + 1);
  const running = totals.get(message.model) ?? { tok_in: 0, tok_out: 0, tok_cache_w: 0, tok_cache_r: 0 };
  for (const [field] of FIELDS) running[field] += counts[field];
  totals.set(message.model, running);
}

if (before) {
  die(`the anchor ${after} is not an assistant message in ${path} — the transcript is not the append-only file an earlier read stopped in, so what is new cannot be told apart from what was counted`);
}

let out = "";
for (const [model, c] of totals) {
  out += `${model} ${c.tok_in} ${c.tok_out} ${c.tok_cache_w} ${c.tok_cache_r} ${counted.get(model)} ${last}\n`;
}
process.stdout.write(out);
