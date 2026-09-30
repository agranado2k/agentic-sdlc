// tool-payload.mjs — one tool-hook payload, split into the parts a trace event needs.
//
//   node tool-payload.mjs <staging directory>   # the payload on standard input
//
// It writes three files into the staging directory —
//
//   input    the payload's `tool_input`, as compact JSON
//   result   the payload's `tool_response`, or its `error` when the call failed
//   head     the first 512 bytes of `input`, safe to put on one trace line
//
// — and prints the scalars the hook puts on the event, one per line, `key value`:
//
//   session <session_id>
//   tool <tool_name>
//   tool_use_id <tool_use_id>
//   event <hook_event_name>
//   result_from tool_response|error
//
// A key the payload does not carry is simply not printed; the hook decides what
// a missing one means. EXIT 2 is shape drift, with the key named on stderr, and
// the hook turns that into one `tool.use` event saying what could not be read —
// the contract transcript-usage.mjs keeps beside it, for the same reason: a
// best-effort blob of the wrong bytes is worse than a recorded gap.
//
// WHY THIS IS JAVASCRIPT IN A KIT WHOSE CORE IS `sh`. A tool payload arrives as
// ONE line of JSON whose values are arbitrary text — a command, a file's
// contents, another payload. A text tool anchored on a key name finds the LAST
// occurrence of it, so a tool result that quotes `"session_id"` (this repository's
// own fixtures do) would rename the session on the event, and one that quotes
// `"tool_response"` would end the result early. Only a real parser reads
// TOP-LEVEL keys; everything below the top level is data that cannot impersonate
// the envelope. The hook beside this file stays POSIX sh, and a machine with no
// node gets a recorded reason rather than a dead hook.
//
// WHAT THE BLOBS ARE, precisely: the value RE-SERIALISED as compact JSON, not a
// byte slice of the payload. A slice would need the parser to hand back offsets,
// which JSON.parse does not do. For every payload this agent harness has been
// seen to emit — compact, no `\u` escapes — the two are byte-identical, which is
// what lets a suite compute the expected hash with `git hash-object` on the
// payload's own text. A payload that escaped a character differently would land
// a canonical copy of the same value under a different hash: still exactly what
// the tool sent, still named by its own bytes.

import { readFileSync, writeFileSync } from "node:fs";

const NAME = "tool-payload";

function die(message) {
  process.stderr.write(`x ${NAME}: ${message}\n`);
  process.exit(2);
}

const dir = process.argv[2];
if (!dir || process.argv.length > 3) {
  die("usage: node tool-payload.mjs <staging directory>   # payload on stdin");
}

let raw;
try {
  // Read whole, the ceiling named rather than discovered: a tool result is
  // unbounded and V8 refuses a string past roughly 512 MB, which arrives here
  // as exit 2 and therefore as an honest `outcome=fail` rather than a wrong
  // blob. Nothing seen on this machine comes within two orders of that.
  raw = readFileSync(0, "utf8");
} catch (error) {
  die(`cannot read the payload on standard input: ${error.code ?? error.message}`);
}

let payload;
try {
  payload = JSON.parse(raw);
} catch {
  die("the payload is not JSON — the agent harness's hook shape has drifted");
}
if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
  die("the payload is not a JSON object — the agent harness's hook shape has drifted");
}

// THE INPUT. `tool_input` is present on every tool hook payload this agent
// harness emits, PreToolUse included; a payload without it is drift rather than
// a tool that took no arguments, which is `{}`.
if (!("tool_input" in payload)) {
  die("key 'tool_input' is missing — a tool call with no input at all is drift, not an empty one");
}
const input = JSON.stringify(payload.tool_input);

// THE RESULT, from whichever key the payload carries. PostToolUse names it
// `tool_response`; PostToolUseFailure carries no `tool_response` at all and puts
// the failure in `error`. Neither key is a payload with nothing to store: an
// empty blob would read as "the tool returned nothing", which is a fact about a
// tool and not about a reader.
let result;
let from;
if ("tool_response" in payload) {
  result = JSON.stringify(payload.tool_response);
  from = "tool_response";
} else if ("error" in payload) {
  result = JSON.stringify(payload.error);
  from = "error";
} else {
  die("neither 'tool_response' nor 'error' is on the payload, so this call has no result to store");
}

// THE HEAD — the first 512 bytes of the input, for the line itself.
//
// SLICED BY BYTES, because a cap on a line is a cap on bytes; a multi-byte
// character split by the slice is dropped rather than left half-written, which
// is what the decoder's replacement character marks and what the trailing-U+FFFD
// trim removes.
//
// AND SCRUBBED OF CONTROL CHARACTERS, which is belt beside a brace: JSON.stringify
// escapes everything below 0x20 by definition, but DEL (0x7F) it passes through
// and a shell command can carry one. `scripts/trace.sh` refuses a value with any
// control character but a tab — so one unscrubbed byte would cost the WHOLE
// event, not just the head. The blob keeps every byte; only the line is scrubbed.
const HEAD_BYTES = 512;
const slice = Buffer.from(input, "utf8").subarray(0, HEAD_BYTES);
let head = new TextDecoder("utf-8").decode(slice).replace(/�+$/u, "");
head = head.replace(/[\u0000-\u001f\u007f]/gu, " ");

// OWNER-ONLY, and asked for at CREATE time rather than fixed afterwards: these
// three files are moved into the blob store as they are, so their mode is the
// mode a tool result is stored with — the commands this session ran and the
// contents of what it read. Under the usual `umask 022` a plain create is 0644,
// which is every local user who can traverse the trace directory (H-1, review of
// PR #295). The shared script gets this for free from `mktemp`; here it is said
// out loud. A mode is masked, never added to, so 0600 cannot widen anything.
const PRIVATE = 0o600;
try {
  writeFileSync(`${dir}/input`, input, { mode: PRIVATE });
  writeFileSync(`${dir}/result`, result, { mode: PRIVATE });
  writeFileSync(`${dir}/head`, head, { mode: PRIVATE });
} catch (error) {
  die(`cannot write the staged payload under ${dir}: ${error.code ?? error.message}`);
}

// THE SCALARS. Printed only when the payload carries them as strings, because a
// hook that read `[object Object]` off a drifted key would put it on a join
// column. One per line, `key value`, which a POSIX `sed` consumes without a
// parser; the values that become ids are checked against this adapter's own
// identifier class by the hook (hook_id_ok), not here.
let out = `result_from ${from}\n`;
for (const key of ["session_id", "tool_name", "tool_use_id", "hook_event_name"]) {
  const value = payload[key];
  if (typeof value !== "string" || value === "") continue;
  // A newline in one of these would forge a second row. Refused rather than
  // trimmed: it cannot happen on a real payload, and if it does, the hook must
  // not be told a plausible lie.
  if (/[\r\n]/u.test(value)) {
    die(`key '${key}' carries a newline, which no id or event name of this agent harness does`);
  }
  const name = { session_id: "session", tool_name: "tool", tool_use_id: "tool_use_id", hook_event_name: "event" }[key];
  out += `${name} ${value}\n`;
}
process.stdout.write(out);
