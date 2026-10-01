// transcript-usage.mjs — per-model token counts out of one agent-harness transcript.
//
//   node transcript-usage.mjs [--rollup] [--after <message id>] <transcript.jsonl>
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
// numbers you can trust; exit 3, under --rollup only, is rows you can trust
// beside a rollup that was refused (see the foot of this file). There is no
// "best effort": the caller turns a 2 into one event that says what could
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
// TWO JSONL lines that repeat the same `message.id` and the same `requestId`.
// Summing lines counts that response twice; summing distinct `message.id`
// reproduces the rollup the agent harness itself writes on the transcript's
// last line, exactly. The request id is 1:1 with the message id in the
// capture, so it is used as a CROSS-CHECK — if two lines ever share a message
// id and disagree about the model or the request, that is drift and it stops
// here rather than becoming a number.
//
// THE LAST USAGE BLOCK PER ID WINS (#343, PRD #237's implementation decision
// as amended 2026-10-01). The usage is NOT always byte-identical across those
// lines: a response that opens with a thinking block is written first with a
// partial usage snapshot (output_tokens 1, say) and then with the final one
// (113). The final block is what the rollup counts, so the last block read
// for an id replaces any earlier one, and a superseded block contributes
// nothing. Only output_tokens may differ, and only by growing: a later block
// that shrinks it, or that changes the input or cache counts, is drift (M-1,
// review of PR #363). Every line is still checked for shape — a renamed key
// on a superseded line is drift all the same.
//
// WHAT THIS FILE DOES NOT DO. It never takes a message's count, or a row's,
// from the transcript's `cost-state` rollup, though that line holds per-model
// totals and a cost figure and would save all the work below. Two reasons:
// the cost is the vendor's interpretation, which ADR-0008 clause 6 keeps out
// of an event, and the rollup includes subagent tokens that live in files the
// session transcript never names — so attributing it to the session would
// double-count against the subagent events. The rollup is the oracle; the one
// thing read from it is the compaction gap under --rollup, which takes those
// subagent files off first (#407, at the foot of this file).
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
// line either way, and a later block of an id the earlier read counted is not
// counted again: that read saw the response finished, so it took the final
// block. An anchor the file does not hold means this is not the file
// the anchor was read from, or it was rewritten: that is drift, exit 2, because
// both "count everything" and "count nothing" would be a confident wrong number.

// READ WHOLE, and the ceiling named rather than discovered: `readFileSync` plus
// `split` holds the transcript twice, and V8 refuses a string past roughly
// 512 MB with ERR_STRING_TOO_LONG — which arrives here as exit 2 and therefore
// as an honest `outcome=fail`, not as a wrong number. The largest transcript
// seen on the machine this was built on is 8 MB. A `node:readline` stream is
// the answer the day that stops being true (L-3, review of PR #291).

import { readFileSync, readdirSync } from "node:fs";

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

const USAGE = "usage: node transcript-usage.mjs [--after <message id>] [--rollup] <transcript.jsonl>";
const args = process.argv.slice(2);
let after = null;
let rollup = false;
while (args[0] === "--after" || args[0] === "--rollup") {
  if (args[0] === "--rollup") {
    rollup = true;
    args.splice(0, 1);
    continue;
  }
  if (args.length < 2 || args[1] === "") die(USAGE);
  after = args[1];
  args.splice(0, 2);
}
const path = args[0];
if (!path || args.length > 1) die(USAGE);

/** A non-negative integer, and nothing that merely looks like one. */
const isCount = (v) => typeof v === "number" && Number.isInteger(v) && v >= 0;

/**
 * One transcript, read once: its messages de-duplicated, how far the read
 * went, and what the --rollup judgement needs. `where` prefixes a drift
 * message, so a subagent file's line is never mistaken for the session's, and
 * `fail` is what drift does — exit 2 for the file whose rows are printed.
 */
function scan(file, after, where = "", fail = die) {
  let raw;
  try {
    raw = readFileSync(file, "utf8");
  } catch (error) {
    fail(`cannot read ${file}: ${error.code ?? error.message}`);
  }

  /**
   * message.id -> { model, requestId, counts, fresh }, in first-seen order. The
   * model and request id are the first line's, for the duplicate check; `counts`
   * is the LAST block read for the id; `fresh` is false for an id first seen at
   * or before the --after anchor, which an earlier read already counted.
   */
  const seen = new Map();
  /** Still at or before the anchor: ids first seen here were counted by an earlier read. */
  let before = after !== null;
  /** The id of the last message summed, which the next read passes as --after. */
  let last = "";
  /** The last `cost-state` line's per-model rollup, and the line each kind was last seen on. */
  let lastRollup = null;
  let rollupLine = 0;
  let lastMessageLine = 0;
  /** A compact boundary was seen; an assistant line had every count zero (a fork's copy). */
  let compacted = false;
  let copied = false;

  let lineNo = 0;
  for (const line of raw.split("\n")) {
    lineNo += 1;
    if (line.trim() === "") continue;

    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      fail(`${where}line ${lineNo} is not JSON — the transcript's shape has drifted`);
    }
    if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
      fail(`${where}line ${lineNo} is not a JSON object — the transcript's shape has drifted`);
    }
    // The agent harness's own rollup, and the mark a compaction leaves: read
    // only for the --rollup judgement below, never as a source of rows.
    if (entry.type === "cost-state") {
      lastRollup = entry.modelUsage;
      rollupLine = lineNo;
      continue;
    }
    if (entry.type === "system" && entry.subtype === "compact_boundary") compacted = true;
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
      fail(`${where}line ${lineNo}: an assistant line with no 'message' object — the transcript's shape has drifted`);
    }
    if (typeof message.id !== "string" || message.id === "") {
      fail(`${where}line ${lineNo}: key 'message.id' is missing or not a string, so a streamed response cannot be de-duplicated`);
    }
    // The id is the ANCHOR the next read of this transcript is handed, and the
    // hook drops an anchor outside this class rather than put it on a command
    // line — which would silently fall back to the whole-file read, the double
    // count (M-1, review of PR #316). So it is refused here, loudly, instead.
    if (!/^[A-Za-z0-9._-]+$/.test(message.id)) {
      fail(`${where}line ${lineNo}: message.id '${message.id}' is not letters, digits, dot, dash and underscore, so it cannot anchor the next read of this transcript`);
    }
    if (typeof message.model !== "string" || message.model === "") {
      fail(`${where}line ${lineNo}: key 'message.model' is missing or not a string, so these tokens belong to no model`);
    }
    // The model becomes a field on a trace event and a word in a shell `read`
    // loop. Refused here rather than escaped downstream: a model id with a space
    // in it would silently shift four numbers by one column.
    if (/[\s"\\]/.test(message.model)) {
      fail(`${where}line ${lineNo}: message.model '${message.model}' carries whitespace, a quote or a backslash, which an event cannot record unambiguously`);
    }
    const usage = message.usage;
    if (usage === null || typeof usage !== "object") {
      fail(`${where}line ${lineNo}: key 'message.usage' is missing on an assistant line — the transcript's shape has drifted`);
    }

    const counts = {};
    for (const [field, key] of FIELDS) {
      if (!isCount(usage[key])) {
        fail(`${where}line ${lineNo}: key 'message.usage.${key}' is missing or not a non-negative integer — refusing to read it as 0`);
      }
      counts[field] = usage[key];
    }
    // A fork's copies of its parent's messages carry their usage zeroed; a real
    // response always has at least one token in it.
    if (FIELDS.every(([field]) => counts[field] === 0)) copied = true;
    lastMessageLine = lineNo;
    const requestId = typeof entry.requestId === "string" ? entry.requestId : "";

    const first = seen.get(message.id);
    if (first) {
      // A streamed response, written once per content block. Its model and its
      // request must repeat — anything else is drift, not a second response —
      // and its usage is the last block read (#343: a thinking block's line
      // carries a partial snapshot the next line supersedes). The superseding
      // is NARROW (review of PR #363, M-1): only output_tokens may move, and
      // only up. A snapshot cannot exceed the final count, so a later block
      // that shrinks it is the pair out of order, and the input and cache
      // counts are fixed before the first token streams — either is drift.
      if (first.model !== message.model) {
        fail(`${where}line ${lineNo}: message.id ${message.id} appears again under a different model ('${first.model}' then '${message.model}')`);
      }
      if (first.requestId !== requestId) {
        fail(`${where}line ${lineNo}: message.id ${message.id} appears again under a different requestId ('${first.requestId}' then '${requestId}')`);
      }
      for (const [field] of FIELDS) {
        const was = first.counts[field];
        const now = counts[field];
        if (field === "tok_out" ? now < was : now !== was) {
          fail(`${where}line ${lineNo}: message.id ${message.id} appears again with ${field} ${was} then ${now} — a later block may only grow tok_out, with the other counts unchanged, so this is not the same response's final snapshot`);
        }
      }
      first.counts = counts;
      continue;
    }
    seen.set(message.id, { model: message.model, requestId, counts, fresh: !before });
    if (before) {
      if (message.id === after) before = false;
      continue;
    }
    last = message.id;
  }

  if (before) {
    fail(`the anchor ${after} is not an assistant message in ${file} — the transcript is not the append-only file an earlier read stopped in, so what is new cannot be told apart from what was counted`);
  }
  return { seen, last, compacted, copied, rollup: rollupLine > lastMessageLine ? lastRollup : null };
}

const { seen, last, compacted, copied, rollup: lastRollup } = scan(path, after);

/** Per-model totals and distinct-message counts, in first-seen order. */
const totals = new Map();
const counted = new Map();
for (const { model, counts, fresh } of seen.values()) {
  if (!fresh) continue;
  counted.set(model, (counted.get(model) ?? 0) + 1);
  const running = totals.get(model) ?? { tok_in: 0, tok_out: 0, tok_cache_w: 0, tok_cache_r: 0 };
  for (const [field] of FIELDS) running[field] += counts[field];
  totals.set(model, running);
}

let out = "";
for (const [model, c] of totals) {
  out += `${model} ${c.tok_in} ${c.tok_out} ${c.tok_cache_w} ${c.tok_cache_r} ${counted.get(model)} ${last}\n`;
}

// --rollup: THE COMPACTION GAP (#407). The call that writes a compaction
// summary leaves no assistant line, so its tokens reach the agent harness's
// own `cost-state` rollup and no row above. With --rollup the difference is
// one more row per model —
//
//   <model> <input> <output> <cache write> <cache read> rollup compaction
//
// — so that the plain sum of the events IS the rollup. The gap is the WHOLE
// file's, whatever the anchor: the rollup minus every message in the file
// (counted now or by an earlier read), minus every subagent file beside it
// (the subagent-stop hook records those), minus every gap the trace already
// holds for this session, which the caller hands over on stdin as the trace's
// own lines. The rollup stays the oracle for what was spent and never the
// source of a message's count, and its cost figure is still never read
// (ADR-0008 clause 6).
//
// JUDGED ONLY WHERE IT MEANS WHAT IT SAYS — each condition is a shape real
// transcripts on the machine this was built on have:
//   - the file holds a compact boundary. A rollup with no compaction behind
//     its gap counts calls this file cannot attribute (a title generated on a
//     second model, a subagent filed elsewhere), and a gap row named for a
//     compaction would then be a double count with a confident label;
//   - the last `cost-state` line comes after the last assistant line. In a
//     long interactive session that line can be thousands of lines stale, a
//     rollup of some earlier end, not of this one;
//   - no assistant line has every count zero. A forked session copies its
//     parent's messages with their usage zeroed and carries the parent's
//     rollup, so its gap would be the parent's whole spend a second time.
//
// A ROLLUP SMALLER THAN THE SUM is drift, but drift in the ROLLUP, not in the
// rows above: those are this file's facts, so they are printed and the exit is
// 3 — "the rows are good, the rollup is refused" — with the reason on stderr.
// A rollup that only starts partway through a session (an agent-harness build
// that wrote none before) is that shape, and exit 2 would throw away every
// message of every later end with it.
const ROLLUP = [
  ["tok_in", "inputTokens"],
  ["tok_out", "outputTokens"],
  ["tok_cache_w", "cacheCreationInputTokens"],
  ["tok_cache_r", "cacheReadInputTokens"],
];

class Refused extends Error {}
const refuse = (message) => {
  throw new Refused(message);
};

/** model -> four counts, summed into `into`. */
function add(into, model, counts) {
  const running = into.get(model) ?? { tok_in: 0, tok_out: 0, tok_cache_w: 0, tok_cache_r: 0 };
  for (const [field] of FIELDS) running[field] += counts[field];
  into.set(model, running);
}

function judgeRollup() {
  if (!compacted || copied || lastRollup === null) return "";
  if (typeof lastRollup !== "object" || Array.isArray(lastRollup)) {
    refuse("the rollup's 'modelUsage' is not an object, so no gap can be judged");
  }
  // What the rollup says, per model. A context-window variant is a suffix on
  // the rollup's key (`claude-opus-5[1m]`) and on no message's model, so the
  // two are the same model here.
  const said = new Map();
  for (const [key, usage] of Object.entries(lastRollup)) {
    const counts = {};
    for (const [field, k] of ROLLUP) {
      if (!isCount(usage?.[k])) refuse(`the rollup's '${key}.${k}' is missing or not a non-negative integer`);
      counts[field] = usage[k];
    }
    add(said, key.replace(/\[[^\]]*\]$/, ""), counts);
  }
  // What the events hold, or are about to.
  const held = new Map();
  for (const { model, counts } of seen.values()) add(held, model, counts);
  const dir = path.replace(/\.jsonl$/, "") + "/subagents";
  let names = [];
  try {
    names = readdirSync(dir).filter((n) => /^agent-.*\.jsonl$/.test(n)).sort();
  } catch {
    names = [];
  }
  for (const name of names) {
    for (const { model, counts } of scan(`${dir}/${name}`, null, `subagents/${name}: `, refuse).seen.values()) {
      add(held, model, counts);
    }
  }
  let recorded = "";
  try {
    recorded = readFileSync(0, "utf8");
  } catch {
    recorded = "";
  }
  let n = 0;
  for (const line of recorded.split("\n")) {
    n += 1;
    if (line.trim() === "") continue;
    let event;
    try {
      event = JSON.parse(line);
    } catch {
      refuse(`line ${n} of the recorded events on stdin is not JSON`);
    }
    if (event?.data?.via !== "rollup" || event.outcome === "fail") continue;
    const counts = {};
    for (const [field] of FIELDS) {
      if (!isCount(event[field])) refuse(`recorded gap event ${n} has no count '${field}'`);
      counts[field] = event[field];
    }
    if (typeof event.model !== "string" || event.model === "") refuse(`recorded gap event ${n} names no model`);
    add(held, event.model, counts);
  }

  let rows = "";
  for (const model of new Set([...said.keys(), ...held.keys()])) {
    const r = said.get(model) ?? { tok_in: 0, tok_out: 0, tok_cache_w: 0, tok_cache_r: 0 };
    const h = held.get(model) ?? { tok_in: 0, tok_out: 0, tok_cache_w: 0, tok_cache_r: 0 };
    const gap = {};
    for (const [field] of FIELDS) {
      gap[field] = r[field] - h[field];
      if (gap[field] < 0) {
        refuse(`the rollup's ${field} for ${model} is ${r[field]}, smaller than the ${h[field]} the messages, subagents and recorded gaps already hold — no gap recorded`);
      }
    }
    if (FIELDS.every(([field]) => gap[field] === 0)) continue;
    rows += `${model} ${gap.tok_in} ${gap.tok_out} ${gap.tok_cache_w} ${gap.tok_cache_r} rollup compaction\n`;
  }
  return rows;
}

if (rollup) {
  try {
    out += judgeRollup();
  } catch (error) {
    if (!(error instanceof Refused)) throw error;
    process.stdout.write(out);
    process.stderr.write(`x ${NAME}: ${error.message}\n`);
    process.exit(3);
  }
}
process.stdout.write(out);
