import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, rmSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import defaultConfig from "../config.mjs";
import { makeContext } from "../context.mjs";
import { REQ_CITED_NAME_ERE, globToRegExp, run } from "../validators/living-spec.mjs";
import { cleanup, ctxFor, hasRule, makeFixture } from "./helpers.mjs";

const here = dirname(fileURLToPath(import.meta.url));

// No citable id is spelled in this file (#561). It sits where a project's
// test globs look, so a literal `<area>/R<n>` here would satisfy a project's
// living spec of that area with no test of its own: every id is built at
// runtime by `cite`, and the last tests scan the harness to hold that. A test
// you add here builds its ids the same way.
const cite = (area, n) => `${area}/R${n}`;
const named = (name) => `${name} is named by no test`;
const B1 = cite("billing", 1);
const B2 = cite("billing", 2);
const B3 = cite("billing", 3);

// The living spec of one area (the kit's ADR-0012 clause 7): requirement lines carry an
// id `R<n>` at the start of the line; everything else is prose. The test
// titles cite PRD #527's ids bare.
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
const messages = (out) => untested(out).map((f) => f.message);

test("R12: a requirement no test names fails, naming the file and the id", () => {
  const ctx = ctxFor({
    "docs/specs/billing.md": BILLING,
    "tests/billing.test.sh": `# holds ${B1}\n`,
  });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].rule, "living-spec-untested");
  assert.equal(out[0].file, "docs/specs/billing.md");
  assert.equal(out[0].message, named(B2));
  assert.notEqual(out[0].severity, "warning");
  cleanup(ctx);
});

test("R12: every requirement named by a test is silent", () => {
  const ctx = ctxFor({
    "docs/specs/billing.md": BILLING,
    "tests/billing.test.sh": `# ${B1}\n`,
    "src/pay/retry.test.ts": `it('${B2} retries once', () => {});\n`,
  });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("R12: a name in a file the test globs do not match counts for nothing", () => {
  const ctx = ctxFor({
    "docs/specs/billing.md": BILLING,
    "src/billing.ts": `// ${B1} ${B2}\n`,
    "docs/notes.md": `${B1} ${B2}\n`,
  });
  assert.equal(untested(run(ctx)).length, 2);
  cleanup(ctx);
});

test("R12: the name is a whole token — R1 is not R10, and process is not subprocess", () => {
  const ctx = ctxFor({
    "docs/specs/process.md": "R1. The process SHALL start.\n",
    "tests/a.test.sh": `# ${cite("process", 10)} and ${cite("subprocess", 1)}\n`,
  });
  assert.deepEqual(messages(run(ctx)), [named(cite("process", 1))]);
  cleanup(ctx);
});

test("R12: the name ends where the id ends — R1abc, R1_x and R1.5 are not R1", () => {
  // The trailing boundary (#537 review, L-1): a cited id followed by a letter,
  // a digit, `_`, or `.` and a digit is a different token, not a citation.
  // A sentence's full stop after the id still cites it.
  const ctx = ctxFor({
    "docs/specs/billing.md": BILLING,
    "tests/a.test.sh": `# ${B1}abc ${B1}_retry ${B1}.5 ${B2}x\n`,
  });
  assert.equal(untested(run(ctx)).length, 2);
  cleanup(ctx);
  const ok = ctxFor({
    "docs/specs/billing.md": BILLING,
    "tests/a.test.sh": `# holds ${B1}.\n# (${B2})\n`,
  });
  assert.deepEqual(run(ok), []);
  cleanup(ok);
});

test("R12: the name begins where the area begins — X-, sub- and specs/-prefixed ids are not the billing id", () => {
  // The leading boundary (#544): a cited id preceded by a letter, a digit,
  // `_`, `-` or `/` is part of a longer token, not a citation of the area it
  // happens to end with. An opening parenthesis, a blank or the start of the
  // line still cites it.
  for (const near of [`X${B1}`, `sub-${B1}`, `9${B1}`, `_${B1}`, `-${B1}`, `specs/${B1}`]) {
    const ctx = ctxFor({
      "docs/specs/billing.md": BILLING,
      "tests/a.test.sh": `# ${near}\n# ${B2}\n`,
    });
    assert.deepEqual(messages(run(ctx)), [named(B1)], `${near} cited ${B1}`);
    cleanup(ctx);
  }
  for (const line of [`# (${B1})`, `# ${B1}`, B1]) {
    const ok = ctxFor({
      "docs/specs/billing.md": BILLING,
      "tests/a.test.sh": `${line}\n# ${B2}\n`,
    });
    assert.deepEqual(run(ok), [], `${line} did not cite ${B1}`);
    cleanup(ok);
  }
});

test("R12: a hyphenated area's id cites its own area, never the area its tail spells", () => {
  // The positive half of the leading boundary (#550 review, M-2): a hyphenated
  // area is one token, so it satisfies its own requirement and not the area
  // its tail happens to spell.
  const ctx = ctxFor({
    "docs/specs/billing.md": BILLING,
    "docs/specs/sub-billing.md": "R1. The sub-ledger SHALL roll up.\n",
    "tests/a.test.sh": `# ${cite("sub-billing", 1)}\n# ${B2}\n`,
  });
  assert.deepEqual(messages(run(ctx)), [named(B1)]);
  cleanup(ctx);
});

test("R12: two ids joined by - or / cite the first alone — the leading boundary's documented cost", () => {
  // #550 review, M-1: the second id's match swallows the joining `-` or `/`
  // and is dropped, as any id after `-` or `/` is. Pinned so the cost is a
  // decision, not an accident: name each id on its own.
  for (const joined of [`${B1}-${B2}`, `${B1}/${B2}`]) {
    const ctx = ctxFor({
      "docs/specs/billing.md": BILLING,
      "tests/a.test.sh": `# ${joined}\n`,
    });
    assert.deepEqual(messages(run(ctx)), [named(B2)], joined);
    cleanup(ctx);
  }
});

test("R12: a requirement line inside a fence is quoted material, not a requirement", () => {
  const ctx = ctxFor({
    "docs/specs/billing.md": "# Billing\n\n```md\nR9. An example line.\n```\n\nR1. Real.\n",
    "tests/b.test.sh": `# ${B1}\n`,
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
  const red = ctxFor({ "docs/specs/billing.md": "R1. One.\n", "tests/billing.test.sh": `# ${B1}\n` }, cfg);
  assert.equal(untested(run(red)).length, 1);
  cleanup(red);
  const green = ctxFor({ "docs/specs/billing.md": "R1. One.\n", "checks/one.sh": `# ${B1}\n` }, cfg);
  assert.deepEqual(run(green), []);
  cleanup(green);
});

test("R12: no test globs configured — every requirement fails, and the hint names the policy", () => {
  const cfg = { ...defaultConfig, livingSpec: undefined };
  const ctx = ctxFor({ "docs/specs/billing.md": "R1. One.\n", "tests/x.test.sh": `# ${B1}\n` }, cfg);
  const out = untested(run(ctx));
  assert.equal(out.length, 1);
  assert.match(out[0].hint, /testGlobs/);
  cleanup(ctx);
});

test("R12: in a git work tree the surface is git's — an ignored file's name counts for nothing", () => {
  const ctx = ctxFor({
    ".gitignore": "build/\n",
    "docs/specs/billing.md": "R1. One.\nR2. Two.\n",
    "build/tests/out.test.sh": `# ${B1} ${B2}\n`,
    "tests/billing.test.sh": `# ${B1}\n`,
  });
  const init = spawnSync("git", ["-C", ctx.repoRoot, "init", "-q"], { encoding: "utf8" });
  assert.equal(init.status, 0, init.stderr);
  assert.deepEqual(messages(run(ctx)), [named(B2)]);
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

test("R11: a REMOVED id's tombstone is no requirement — no test need name it", () => {
  // `/implement` step 4 replaces a removed line with `~~R<n>.~~ Removed by
  // #<PRD>: <why>`: struck through, so it does not open `R<n>.`, and kept, so
  // the id is never reused.
  const ctx = ctxFor({
    "docs/specs/billing.md": `# Billing\n\nR1. One.\n~~R2.~~ Removed by #12: folded into ${B1}.\n`,
    "tests/billing.test.sh": `# ${B1}\n`,
  });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("#533: the docs/specs README starter is no area file — its fenced examples are silent", () => {
  // Bootstrap lays `docs/specs/README.md`, which explains the format with
  // examples in fences and holds no requirement: neither engine reads one from
  // it. Its name is no area token, so a README that grew a requirement line
  // outside a fence is reported — a requirement there could never be cited.
  const starter = [
    "# Living specs",
    "",
    "```md",
    "R1. The invoice SHALL carry the customer's legal name.",
    `~~R2.~~ Removed by #12: folded into ${B1}.`,
    "```",
    "",
    "```md",
    "### ADDED",
    `${B3}. The invoice SHALL carry its date.`,
    "```",
    "",
  ].join("\n");
  const silent = ctxFor({ "docs/specs/README.md": starter });
  assert.deepEqual(run(silent), []);
  cleanup(silent);
  const grown = ctxFor({ "docs/specs/README.md": `${starter}R1. A requirement outside a fence.\n` });
  assert.ok(hasRule(run(grown), "living-spec-area-invalid"));
  cleanup(grown);
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

test("this repo's own tree is silent — every living requirement it holds is named by a test", () => {
  const ctx = makeContext({ repoRoot: join(here, "..", "..", ".."), config: defaultConfig });
  assert.deepEqual(run(ctx), []);
});

// The grammar has one home (#545): scripts/requirement.lib.sh, which the
// gate's POSIX twin, the coverage check and the suites source. The validator
// keeps its own literals — a fixture-tree run must not depend on a shell file
// — so this test holds every one of them to the home, byte for byte.
const GRAMMAR = ["REQ_AREA_ERE", "REQ_FENCE_ERE", "REQ_LINE_ERE", "REQ_CITED_NAME_ERE", "REQ_CITED_TOKEN_ERE"];

function homeValues(lib) {
  const script = `. "$1" && for v in ${GRAMMAR.join(" ")}; do eval "printf '%s\\n' \\"\\$$v\\""; done`;
  const res = spawnSync("sh", ["-c", script, "sh", lib], { encoding: "utf8" });
  assert.equal(res.status, 0, `sourcing ${lib} failed: ${res.stderr}`);
  return res.stdout.split("\n").slice(0, GRAMMAR.length);
}
const HOME = join(here, "..", "..", "requirement.lib.sh");

test("the validator's grammar is the shell home's, byte for byte", async () => {
  const mod = await import("../validators/living-spec.mjs");
  const home = homeValues(HOME);
  GRAMMAR.forEach((name, i) => {
    assert.equal(typeof mod[name], "string", `living-spec.mjs exports no ${name}`);
    assert.equal(mod[name], home[i], `${name} diverges from scripts/requirement.lib.sh`);
  });
});

test("the comparison can go red — a home whose requirement line moves diverges", async () => {
  const mod = await import("../validators/living-spec.mjs");
  const root = makeFixture({
    "requirement.lib.sh": `${readFileSync(HOME, "utf8")}\nREQ_LINE_ERE='^R[1-9][0-9]*[.]([ \\t\\r]|$)'\n`,
  });
  const moved = homeValues(join(root, "requirement.lib.sh"));
  assert.notEqual(moved[GRAMMAR.indexOf("REQ_LINE_ERE")], mod.REQ_LINE_ERE);
  assert.equal(moved[GRAMMAR.indexOf("REQ_AREA_ERE")], mod.REQ_AREA_ERE);
});

test("end to end: an untested requirement fails the harness, naming the file and the id", () => {
  const SHIM = "<!-- Shim: the agent manual is AGENTS.md. Edit that file, not this one. -->\n@AGENTS.md\n";
  const root = makeFixture({
    "AGENTS.md": "# Manual\n",
    "CLAUDE.md": SHIM,
    "GEMINI.md": SHIM,
    "docs/specs/billing.md": BILLING,
    "tests/billing.test.sh": `# ${B1}\n`,
  });
  const res = spawnSync(process.execPath, [join(here, "..", "index.mjs"), root], { encoding: "utf8" });
  assert.equal(res.status, 1, `expected exit 1, got ${res.status}\n${res.stdout}${res.stderr}`);
  assert.match(res.stderr, /living-spec-untested/);
  assert.match(res.stderr, /docs\/specs\/billing\.md/);
  assert.ok(res.stderr.includes(named(B2)), res.stderr);
});

// #561, found by a real upgrade: these fixtures once spelled the very ids a
// project's first living spec holds, from a path the default test globs
// match, so a consumer's `docs/specs/billing.md` passed with no test of its
// own. Two answers, each enough alone: the ENGINE never reads a name from
// the harness's own tree, `scripts/docs-conformance/` at the repo root, and
// no shipped harness file spells a citable id at all.

test("#561: a name inside the docs harness's own tree cites nothing — its tests are the gate's, not the project's", () => {
  const ctx = ctxFor({
    "docs/specs/billing.md": BILLING,
    "scripts/docs-conformance/test/living-spec.test.mjs": `// ${B1} ${B2}\n`,
    "scripts/docs-conformance/test/mine.test.mjs": `// ${B1}\n`,
    "tests/billing.test.sh": `# ${B2}\n`,
  });
  assert.deepEqual(messages(run(ctx)), [named(B1)]);
  cleanup(ctx);
});

test("#561: the exclusion is the harness tree exactly — a nested tree or a longer name is the project's", () => {
  // Anchored at the repo root and ending at the directory's slash (#578
  // review, M-2): only `scripts/docs-conformance/` itself is excluded.
  for (const near of [
    "vendor/scripts/docs-conformance/test/a.test.mjs",
    "docs/scripts/docs-conformance/test/a.test.mjs",
    "scripts/docs-conformance-extra/test/a.test.mjs",
  ]) {
    const ctx = ctxFor({ "docs/specs/billing.md": BILLING, [near]: `// ${B1} ${B2}\n` });
    assert.deepEqual(run(ctx), [], `${near} did not cite`);
    cleanup(ctx);
  }
});

// The scan: every file of the harness tree, and the gate's two shell files
// beside it, held to spelling no `<area>/R<n>` — the cited name's pattern
// as a substring, stricter than a citation, so no boundary rule can let one
// back in.
const SCRIPTS = join(here, "..", "..");

function spelledIds(root, rels) {
  const re = new RegExp(REQ_CITED_NAME_ERE, "g");
  const found = [];
  const visit = (rel) => {
    const abs = join(root, rel);
    if (!existsSync(abs)) return;
    if (statSync(abs).isDirectory()) {
      for (const name of readdirSync(abs)) {
        if (name === "node_modules" || name.startsWith(".")) continue;
        visit(`${rel}/${name}`);
      }
      return;
    }
    for (const m of readFileSync(abs, "utf8").match(re) ?? []) found.push(`${rel}: ${m}`);
  };
  rels.forEach(visit);
  return found;
}
const HARNESS_FILES = ["docs-conformance", "check.sh", "requirement.lib.sh"];

test("#561: no shipped harness file spells a citable id", () => {
  assert.deepEqual(spelledIds(SCRIPTS, HARNESS_FILES), []);
});

test("#561: the scan can go red — a fixture or a comment that spells an id is found", () => {
  const root = makeFixture({
    "docs-conformance/test/a.test.mjs": `// ${cite("billing", 1)}\n`,
    "docs-conformance/validators/v.mjs": `// X${cite("ledger", 20)}abc\n`,
    "docs-conformance/clean.mjs": "// <area>/R<n> and ${area}/R${n} spell none\n",
    "check.sh": `# ${cite("journal", 3)}\n`,
  });
  assert.deepEqual(spelledIds(root, HARNESS_FILES).sort(), [
    `check.sh: ${cite("journal", 3)}`,
    `docs-conformance/test/a.test.mjs: ${cite("billing", 1)}`,
    `docs-conformance/validators/v.mjs: ${cite("ledger", 20)}`,
  ]);
  rmSync(root, { recursive: true, force: true });
});
