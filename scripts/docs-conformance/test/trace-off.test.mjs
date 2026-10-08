import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import defaultConfig from "../config.mjs";
import { makeContext } from "../context.mjs";
import { run } from "../validators/trace-off.mjs";
import { cleanup, ctxFor, hasRule } from "./helpers.mjs";

const here = dirname(fileURLToPath(import.meta.url));

// The trace policy file as the kit ships it, with its one decision line, and
// the ignore file a new project is stamped with (#654).
const policy = (line) => `#!/bin/sh\n# TRACE_DIR — where the trace lives.\n${line}\nTRACE_TOOLS=''\n`;
const IGNORED = "worktree/\n\n# The decision trace lands here.\n.trace/\n";
const NOT_IGNORED = "worktree/\nnode_modules/\n";
const cfgWith = (traceOff) => ({ ...defaultConfig, traceOff });
// The shipped defaults, whatever the kit's own config.mjs points at.
const DEFAULTS = cfgWith({});

test("an empty TRACE_DIR beside an ignored trace directory warns — and only warns", () => {
  const ctx = ctxFor({ "scripts/trace.config.sh": policy("TRACE_DIR=''"), ".gitignore": IGNORED }, DEFAULTS);
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.ok(hasRule(out, "trace-off"));
  assert.equal(out[0].severity, "warning");
  assert.equal(out[0].file, "scripts/trace.config.sh");
  // It names the setting, the file and the cost (#655).
  assert.match(out[0].message, /TRACE_DIR/);
  assert.match(out[0].hint, /\/retro/);
  cleanup(ctx);
});

test("a filled TRACE_DIR is silent", () => {
  const ctx = ctxFor({ "scripts/trace.config.sh": policy("TRACE_DIR='.trace'"), ".gitignore": IGNORED }, DEFAULTS);
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("an empty TRACE_DIR with no ignore entry is silent — the trace has nowhere safe to land yet", () => {
  const ctx = ctxFor({ "scripts/trace.config.sh": policy("TRACE_DIR=''"), ".gitignore": NOT_IGNORED }, DEFAULTS);
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("an empty TRACE_DIR with no ignore file at all is silent", () => {
  const ctx = ctxFor({ "scripts/trace.config.sh": policy("TRACE_DIR=''") }, DEFAULTS);
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("no trace policy file is silent — a project without the trace has nothing to decide", () => {
  const ctx = ctxFor({ ".gitignore": IGNORED }, DEFAULTS);
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("the ignore entry is read in its other spellings, and never from a comment or a negation", () => {
  for (const entry of [".trace", "/.trace/", "/.trace", ".trace/  "]) {
    const ctx = ctxFor({ "scripts/trace.config.sh": policy("TRACE_DIR=''"), ".gitignore": `${entry}\n` }, DEFAULTS);
    assert.ok(hasRule(run(ctx), "trace-off"), `expected ${JSON.stringify(entry)} to count as the entry`);
    cleanup(ctx);
  }
  for (const entry of ["# .trace/", "!.trace/", ".tracer/", "x/.trace/"]) {
    const ctx = ctxFor({ "scripts/trace.config.sh": policy("TRACE_DIR=''"), ".gitignore": `${entry}\n` }, DEFAULTS);
    assert.deepEqual(run(ctx), [], `expected ${JSON.stringify(entry)} not to count as the entry`);
    cleanup(ctx);
  }
});

test("a later negation un-ignores the directory, as git reads it — the last matching line wins", () => {
  for (const [lines, fires] of [
    [".trace/\n!.trace/\n", false],
    ["!.trace/\n.trace/\n", true],
    [".trace/\n!/.trace\n", false],
  ]) {
    const ctx = ctxFor({ "scripts/trace.config.sh": policy("TRACE_DIR=''"), ".gitignore": lines }, DEFAULTS);
    assert.equal(hasRule(run(ctx), "trace-off"), fires, `ignore file ${JSON.stringify(lines)}`);
    cleanup(ctx);
  }
});

test("the value is read as the shell reads it: quoted, bare or double-quoted, the last line winning", () => {
  for (const [line, fires] of [
    ['TRACE_DIR=""', true],
    ["TRACE_DIR=", true],
    ["TRACE_DIR=   # off for now", true],
    ['TRACE_DIR=".trace"', false],
    ["TRACE_DIR=.trace", false],
    ["TRACE_DIR='/var/trace'  # elsewhere", false],
    ["TRACE_DIR='.trace'\nTRACE_DIR=''", true],
    ["TRACE_DIR=''\nTRACE_DIR='.trace'", false],
    ["# TRACE_DIR='.trace'\nTRACE_DIR=''", true],
  ]) {
    const ctx = ctxFor({ "scripts/trace.config.sh": policy(line), ".gitignore": IGNORED }, DEFAULTS);
    assert.equal(hasRule(run(ctx), "trace-off"), fires, `line ${JSON.stringify(line)}`);
    cleanup(ctx);
  }
});

test("a policy file with no TRACE_DIR line at all leaves the trace off", () => {
  const ctx = ctxFor({ "scripts/trace.config.sh": "#!/bin/sh\nTRACE_TOOLS=''\n", ".gitignore": IGNORED }, DEFAULTS);
  assert.ok(hasRule(run(ctx), "trace-off"));
  cleanup(ctx);
});

test("the policy files are an ordered list: the first that exists is the one read", () => {
  const config = cfgWith({ policyFiles: ["scripts/trace.twin.sh", "scripts/trace.config.sh"] });
  // The twin exists and traces: the empty shipped file behind it is not read.
  let ctx = ctxFor(
    {
      "scripts/trace.twin.sh": policy("TRACE_DIR='.trace'"),
      "scripts/trace.config.sh": policy("TRACE_DIR=''"),
      ".gitignore": IGNORED,
    },
    config,
  );
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
  // No twin: the list falls through to the shipped file, and it is off.
  ctx = ctxFor({ "scripts/trace.config.sh": policy("TRACE_DIR=''"), ".gitignore": IGNORED }, config);
  const out = run(ctx);
  assert.ok(hasRule(out, "trace-off"));
  assert.equal(out[0].file, "scripts/trace.config.sh");
  cleanup(ctx);
});

test("the ignore file and the directory are policy", () => {
  const config = cfgWith({ ignoreFile: ".hgignore", dir: ".decisions" });
  const ctx = ctxFor({ "scripts/trace.config.sh": policy("TRACE_DIR=''"), ".hgignore": ".decisions/\n" }, config);
  assert.ok(hasRule(run(ctx), "trace-off"));
  cleanup(ctx);
});

// The kit's own tree, read through the real config. These two hold only where
// the kit's never-shipped twin exists: a project's tree is its own business,
// and an advisory there is the channel working, never a failing test.
const ROOT = join(here, "..", "..", "..");
const KIT_ONLY = { skip: !existsSync(join(ROOT, "scripts/trace.kit.config.sh")) && "no kit twin in this tree" };

test("the kit's own tree is silent — it traces through its never-shipped twin", KIT_ONLY, () => {
  assert.ok(!hasRule(run(makeContext({ repoRoot: ROOT, config: defaultConfig })), "trace-off"));
});

test("and only the twin keeps it silent — read by the shipped defaults, the kit's tree fires (its shipped policy file is the empty one)", KIT_ONLY, () => {
  assert.ok(hasRule(run(makeContext({ repoRoot: ROOT, config: DEFAULTS })), "trace-off"));
});
