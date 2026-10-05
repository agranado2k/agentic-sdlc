import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import defaultConfig from "../config.mjs";
import { makeContext } from "../context.mjs";
import { globToRegExp, run } from "../validators/living-spec.mjs";
import { cleanup, ctxFor, hasRule, makeFixture } from "./helpers.mjs";

const here = dirname(fileURLToPath(import.meta.url));

// The living spec of one area (ADR-0012 clause 7): requirement lines carry an
// id `R<n>` at the start of the line; everything else is prose. The kit has no
// living spec of its own yet, so these tests cite PRD #527's ids bare.
const BILLING = [
  "# Billing",
  "",
  "The current requirements of the billing area.",
  "",
  "R1. The invoice SHALL carry the customer's legal name.",
  "R2. WHEN a payment fails, the system SHALL retry once.",
  "",
].join("\n");

const untested = (out) => out.filter((f) => f.rule === "living-spec-untested");

test("R12: a requirement no test names fails, naming the file and the id", () => {
  const ctx = ctxFor({
    "docs/specs/billing.md": BILLING,
    "tests/billing.test.sh": "# holds billing/R1\n",
  });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].rule, "living-spec-untested");
  assert.equal(out[0].file, "docs/specs/billing.md");
  assert.match(out[0].message, /billing\/R2/);
  assert.notEqual(out[0].severity, "warning");
  cleanup(ctx);
});

test("R12: every requirement named by a test is silent", () => {
  const ctx = ctxFor({
    "docs/specs/billing.md": BILLING,
    "tests/billing.test.sh": "# billing/R1\n",
    "src/pay/retry.test.ts": "it('billing/R2 retries once', () => {});\n",
  });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("R12: a name in a file the test globs do not match counts for nothing", () => {
  const ctx = ctxFor({
    "docs/specs/billing.md": BILLING,
    "src/billing.ts": "// billing/R1 billing/R2\n",
    "docs/notes.md": "billing/R1 billing/R2\n",
  });
  assert.equal(untested(run(ctx)).length, 2);
  cleanup(ctx);
});

test("R12: the name is a whole token — R1 is not R10, and process is not subprocess", () => {
  const ctx = ctxFor({
    "docs/specs/process.md": "R1. The process SHALL start.\n",
    "tests/a.test.sh": "# process/R10 and subprocess/R1\n",
  });
  const out = untested(run(ctx));
  assert.equal(out.length, 1);
  assert.match(out[0].message, /process\/R1\b/);
  cleanup(ctx);
});

test("R12: the name ends where the id ends — R1abc, R1_x and R1.5 are not R1", () => {
  // The trailing boundary (#537 review, L-1): a cited id followed by a letter,
  // a digit, `_`, or `.` and a digit is a different token, not a citation.
  // A sentence's full stop after the id still cites it.
  const ctx = ctxFor({
    "docs/specs/billing.md": BILLING,
    "tests/a.test.sh": "# billing/R1abc billing/R1_retry billing/R1.5 billing/R2x\n",
  });
  assert.equal(untested(run(ctx)).length, 2);
  cleanup(ctx);
  const ok = ctxFor({
    "docs/specs/billing.md": BILLING,
    "tests/a.test.sh": "# holds billing/R1.\n# (billing/R2)\n",
  });
  assert.deepEqual(run(ok), []);
  cleanup(ok);
});

test("R12: a requirement line inside a fence is quoted material, not a requirement", () => {
  const ctx = ctxFor({
    "docs/specs/billing.md": "# Billing\n\n```md\nR9. An example line.\n```\n\nR1. Real.\n",
    "tests/b.test.sh": "# billing/R1\n",
  });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("R12: only a line that opens with R<n>. is a requirement", () => {
  const ctx = ctxFor({
    "docs/specs/billing.md":
      "Prose citing R4. in passing.\n  R5. indented is prose.\nRx. not an id.\nR6.no space is not one either\n",
  });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("R12: CRLF line endings still read the requirement", () => {
  const ctx = ctxFor({ "docs/specs/billing.md": "# B\r\n\r\nR1. One.\r\n" });
  assert.equal(untested(run(ctx)).length, 1);
  cleanup(ctx);
});

test("R12: a spec file whose name is no area is reported, not skipped", () => {
  const ctx = ctxFor({ "docs/specs/Billing_Area.md": "R1. Something.\n" });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.ok(hasRule(out, "living-spec-area-invalid"));
  assert.equal(out[0].file, "docs/specs/Billing_Area.md");
  cleanup(ctx);
});

test("R12: the test globs are policy — an override moves what counts as a test", () => {
  const cfg = { ...defaultConfig, livingSpec: { ...defaultConfig.livingSpec, testGlobs: ["checks/*"] } };
  const red = ctxFor({ "docs/specs/billing.md": "R1. One.\n", "tests/billing.test.sh": "# billing/R1\n" }, cfg);
  assert.equal(untested(run(red)).length, 1);
  cleanup(red);
  const green = ctxFor({ "docs/specs/billing.md": "R1. One.\n", "checks/one.sh": "# billing/R1\n" }, cfg);
  assert.deepEqual(run(green), []);
  cleanup(green);
});

test("R12: no test globs configured — every requirement fails, and the hint names the policy", () => {
  const cfg = { ...defaultConfig, livingSpec: undefined };
  const ctx = ctxFor({ "docs/specs/billing.md": "R1. One.\n", "tests/x.test.sh": "# billing/R1\n" }, cfg);
  const out = untested(run(ctx));
  assert.equal(out.length, 1);
  assert.match(out[0].hint, /testGlobs/);
  cleanup(ctx);
});

test("R12: in a git work tree the surface is git's — an ignored file's name counts for nothing", () => {
  const ctx = ctxFor({
    ".gitignore": "build/\n",
    "docs/specs/billing.md": "R1. One.\nR2. Two.\n",
    "build/tests/out.test.sh": "# billing/R1 billing/R2\n",
    "tests/billing.test.sh": "# billing/R1\n",
  });
  const init = spawnSync("git", ["-C", ctx.repoRoot, "init", "-q"], { encoding: "utf8" });
  assert.equal(init.status, 0, init.stderr);
  const out = untested(run(ctx));
  assert.deepEqual(
    out.map((f) => f.message),
    ["billing/R2 is named by no test"],
  );
  cleanup(ctx);
});

test("R13: no docs/specs at all passes", () => {
  const ctx = ctxFor({ "tests/x.test.sh": "# nothing\n" });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("R13: an empty docs/specs passes, and so does a spec with no requirement yet", () => {
  const empty = ctxFor({ "docs/specs/.keep": "" });
  assert.deepEqual(run(empty), []);
  cleanup(empty);
  const prose = ctxFor({ "docs/specs/notes.md": "# Notes\n\nNo requirement yet.\n" });
  assert.deepEqual(run(prose), []);
  cleanup(prose);
});

test("a glob's * crosses directories and ? is one character, as in a shell case pattern", () => {
  assert.ok(globToRegExp("tests/*").test("tests/a/b.sh"));
  assert.ok(globToRegExp("*.test.*").test("src/a/b.test.ts"));
  assert.ok(!globToRegExp("tests/*").test("src/tests/a.sh"));
  assert.ok(globToRegExp("t?st/*").test("test/a"));
  assert.ok(!globToRegExp("a.b").test("axb"));
});

test("the shipped policy names the specs directory and a non-empty list of test globs", () => {
  assert.equal(defaultConfig.livingSpec.specsDir, "docs/specs");
  assert.ok(defaultConfig.livingSpec.testGlobs.length > 0);
  for (const g of defaultConfig.livingSpec.testGlobs) assert.equal(typeof g, "string");
});

test("the kit's own tree is silent — it ships the check and no living spec", () => {
  const ctx = makeContext({ repoRoot: join(here, "..", "..", ".."), config: defaultConfig });
  assert.deepEqual(run(ctx), []);
});

test("end to end: an untested requirement fails the harness, naming the file and the id", () => {
  const SHIM = "<!-- Shim: the agent manual is AGENTS.md. Edit that file, not this one. -->\n@AGENTS.md\n";
  const root = makeFixture({
    "AGENTS.md": "# Manual\n",
    "CLAUDE.md": SHIM,
    "GEMINI.md": SHIM,
    "docs/specs/billing.md": BILLING,
    "tests/billing.test.sh": "# billing/R1\n",
  });
  const res = spawnSync(process.execPath, [join(here, "..", "index.mjs"), root], { encoding: "utf8" });
  assert.equal(res.status, 1, `expected exit 1, got ${res.status}\n${res.stdout}${res.stderr}`);
  assert.match(res.stderr, /living-spec-untested/);
  assert.match(res.stderr, /docs\/specs\/billing\.md/);
  assert.match(res.stderr, /billing\/R2/);
});
