// transcript-usage.mjs — per-model token counts out of one agent-harness transcript.
//
//   node transcript-usage.mjs <transcript.jsonl>
//
// STDOUT is one row per model, five space-separated fields, in the order the
// four token fields sit in a trace event:
//
//   <model> <input> <output> <cache write> <cache read>
//
// so a POSIX `while read -r model tin tout tcw tcr` consumes it without a
// parser. A transcript with no assistant message prints nothing and exits 0.
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

const path = process.argv[2];
if (!path || process.argv.length > 3) {
  die("usage: node transcript-usage.mjs <transcript.jsonl>");
}

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

  const running = totals.get(message.model) ?? { tok_in: 0, tok_out: 0, tok_cache_w: 0, tok_cache_r: 0 };
  for (const [field] of FIELDS) running[field] += counts[field];
  totals.set(message.model, running);
}

let out = "";
for (const [model, c] of totals) {
  out += `${model} ${c.tok_in} ${c.tok_out} ${c.tok_cache_w} ${c.tok_cache_r}\n`;
}
process.stdout.write(out);
