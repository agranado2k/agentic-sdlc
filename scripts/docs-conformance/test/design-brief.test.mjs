import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import defaultConfig from "../config.mjs";
import { makeContext } from "../context.mjs";
import { run } from "../validators/design-brief.mjs";
import { cleanup, ctxFor, hasRule, makeFixture } from "./helpers.mjs";

const here = dirname(fileURLToPath(import.meta.url));

// The engineering article once a consumer has filled it. The three anchors
// are the shape the 0.15.0 template stamps into the Architecture section; the
// validator only asks whether a filled article still carries at least one of
// them, in either of its two honest forms — a decision, or none-with-reason.
const ALL_THREE = [
  "# Engineering",
  "",
  "**Paradigm**: object-oriented at the domain layer; pure functions in the read models.",
  "**Architectural style**: ports and adapters — the domain never imports an adapter.",
  "**Context map**: see the glossary's context map; Billing conforms to Ledger.",
  "",
].join("\n");
const ONE_OF_THREE = "# Engineering\n\n**Paradigm**: functional — no classes outside adapters.\n";
const NONE_FORM =
  "# Engineering\n\n**Context map**: none — a single context until the second product line exists.\n";
const SILENT = "# Engineering\n\n## Architecture\n\nIt has one. Trust us.\n";

test("an article carrying all three anchors is silent", () => {
  const ctx = ctxFor({ "constitution/local-engineering.md": ALL_THREE });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("one anchor is enough — a decision was recorded", () => {
  const ctx = ctxFor({ "constitution/local-engineering.md": ONE_OF_THREE });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("an explicit none-with-reason is silent — a recorded choice is the point", () => {
  const ctx = ctxFor({ "constitution/local-engineering.md": NONE_FORM });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("an article with no anchor at all warns — and only warns", () => {
  const ctx = ctxFor({ "constitution/local-engineering.md": SILENT });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.ok(hasRule(out, "design-brief-missing"));
  assert.equal(out[0].severity, "warning");
  assert.equal(out[0].file, "constitution/local-engineering.md");
  // The message names all three anchors, so the fix is readable from the
  // warning alone.
  for (const label of ["Paradigm", "Architectural style", "Context map"]) {
    assert.match(out[0].message, new RegExp(label));
  }
  cleanup(ctx);
});

test("labels with nothing after them are not decisions", () => {
  const ctx = ctxFor({
    "constitution/local-engineering.md":
      "# Engineering\n\n**Paradigm**:\n**Architectural style**:\n**Context map**:\n",
  });
  assert.ok(hasRule(run(ctx), "design-brief-missing"));
  cleanup(ctx);
});

test("an empty label mid-document is not a decision — the match must not cross the line break", () => {
  const ctx = ctxFor({
    "constitution/local-engineering.md":
      "# Engineering\n\n**Architectural style**:\n\n## Test tiers\n\nWords.\n",
  });
  assert.ok(hasRule(run(ctx), "design-brief-missing"));
  cleanup(ctx);
});

test("CRLF line endings: an empty label still warns, a filled one is still silent", () => {
  const empty = ctxFor({
    "constitution/local-engineering.md": "# E\r\n\r\n**Paradigm**:\r\nNext line.\r\n",
  });
  assert.ok(hasRule(run(empty), "design-brief-missing"));
  cleanup(empty);
  const filled = ctxFor({
    "constitution/local-engineering.md": "# E\r\n\r\n**Paradigm**: functional.\r\n",
  });
  assert.deepEqual(run(filled), []);
  cleanup(filled);
});

test("anchors only inside a fenced code block are quoted material, not decisions", () => {
  const ctx = ctxFor({
    "constitution/local-engineering.md": [
      "# Engineering",
      "",
      "```md",
      "**Paradigm**: the convention, quoted as an example.",
      "**Architectural style**: likewise.",
      "**Context map**: likewise.",
      "```",
      "",
      "No decision of our own.",
      "",
    ].join("\n"),
  });
  assert.ok(hasRule(run(ctx), "design-brief-missing"));
  cleanup(ctx);
});

test("the designBrief.article override points the rule at a different file", () => {
  // configWith only spreads claudeMdRefs, so build the config literally.
  const cfg = { ...defaultConfig, designBrief: { article: "docs/eng.md" } };
  const ctx = ctxFor({ "docs/eng.md": SILENT }, cfg);
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].file, "docs/eng.md");
  cleanup(ctx);
});

test("no stamped article, no finding — the templates-stamped rule owns that state", () => {
  // The marks are spelled from parts: a literal one outside a .template is
  // itself a gate violation, and this test file is not a template.
  const mark = (name) => "{{" + name + "}}";
  const ctx = ctxFor({
    "constitution/local-engineering.md.template": [
      `**Paradigm**: ${mark("PARADIGM")}`,
      `**Architectural style**: ${mark("ARCHITECTURAL_STYLE")}`,
      `**Context map**: ${mark("CONTEXT_MAP")}`,
      "",
    ].join("\n"),
  });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("the kit's own tree is silent — it ships the template, never a stamped article", () => {
  const ctx = makeContext({ repoRoot: join(here, "..", "..", ".."), config: defaultConfig });
  assert.deepEqual(run(ctx), []);
});

test("end to end: a silent article warns on stderr and the gate still exits 0", () => {
  const SHIM = "<!-- Shim: the agent manual is AGENTS.md. Edit that file, not this one. -->\n@AGENTS.md\n";
  const root = makeFixture({
    "AGENTS.md": "Engineering practice lives in `constitution/local-engineering.md`.\n",
    "CLAUDE.md": SHIM,
    "GEMINI.md": SHIM,
    "constitution/local-engineering.md": SILENT,
  });
  const res = spawnSync(process.execPath, [join(here, "..", "index.mjs"), root], {
    encoding: "utf8",
  });
  assert.equal(res.status, 0, `expected exit 0, got ${res.status}\n${res.stderr}`);
  assert.match(res.stderr, /design-brief-missing/);
  assert.match(res.stdout, /OK {2}docs conformance/);
});
