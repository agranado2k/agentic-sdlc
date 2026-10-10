import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import defaultConfig from "../config.mjs";
import { makeContext } from "../context.mjs";
import { run } from "../validators/supersession.mjs";
import { cleanup, ctxFor, makeFixture } from "./helpers.mjs";

// #683: the docs gate holds supersession both ways between decision records.
// A record whose "Supersedes / amends" line says it supersedes another (whole
// or a clause) obliges the superseded record's "Superseded by" line to name
// it, in both engines. An amendment is not a supersession.

const here = dirname(fileURLToPath(import.meta.url));
const KIT = join(here, "..", "..", "..");
const A = (n) => `ADR-${n}`; // spelled from parts: a shipped file names no record literally
const record = (n, title, supersedes, supersededBy) =>
  `# ${A(n)}: ${title}\n\n- **Status**: Accepted\n- **Supersedes / amends**: ${supersedes}\n- **Superseded by**: ${supersededBy}\n\n## Context\n\nText.\n`;
const OLD = "docs/adr/0001-old.md";
const NEW = "docs/adr/0002-new.md";
const ONE_SIDED = {
  [OLD]: record("0001", "Old", "—", "—"),
  [NEW]: record("0002", "New", `supersedes ${A("0001")} clause 2; amends nothing else`, "—"),
};
const TWO_SIDED = {
  ...ONE_SIDED,
  [OLD]: record("0001", "Old", "—", `— (clause 2 superseded by ${A("0002")})`),
};
const policy = (over = {}) => ({
  ...defaultConfig,
  supersession: { ...defaultConfig.supersession, knownExceptions: [], ...over },
});

test("a one-sided supersession fails, on the superseded record, naming both", () => {
  const ctx = ctxFor(ONE_SIDED, policy());
  const out = run(ctx);
  assert.deepEqual(out.map((f) => f.rule), ["supersession-one-sided"]);
  assert.equal(out[0].file, OLD);
  assert.notEqual(out[0].severity, "warning");
  assert.ok(out[0].message.includes(A("0002")));
  assert.ok(out[0].message.includes(A("0001")));
  cleanup(ctx);
});

test("the two-sided supersession is green", () => {
  const ctx = ctxFor(TWO_SIDED, policy());
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("an amendment obliges nothing, and neither does a parenthetical mention", () => {
  const ctx = ctxFor(
    {
      [OLD]: record("0001", "Old", "—", "—"),
      [NEW]: record("0002", "New", `amends ${A("0001")} in one respect — (builds on ${A("0001")})`, "—"),
    },
    policy(),
  );
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("every record a supersedes clause names is held, wherever the id sits in the clause", () => {
  const ctx = ctxFor(
    {
      [OLD]: record("0001", "Old", "—", "—"),
      "docs/adr/0003-other.md": record("0003", "Other", "—", "—"),
      [NEW]: record("0002", "New", `Supersedes ${A("0001")} clause 1; supersedes the amendment of ${A("0003")} (#9)`, "—"),
    },
    policy(),
  );
  assert.deepEqual(run(ctx).map((f) => f.file), [OLD, "docs/adr/0003-other.md"]);
  cleanup(ctx);
});

test("a supersession of a record with no file, or of itself, is not this rule's to judge", () => {
  const ctx = ctxFor(
    { [NEW]: record("0002", "New", `supersedes ${A("0009")} and ${A("0002")}'s draft`, "—") },
    policy(),
  );
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("the records template is not a record", () => {
  const ctx = ctxFor(
    { [OLD]: record("0001", "Old", "—", "—"), "docs/adr/NNNN-template.md": record("NNNN", "T", `supersedes ${A("0001")}`, "—") },
    policy(),
  );
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("no records directory, or no policy block, is no rule", () => {
  const ctx = ctxFor({ "AGENTS.md": "# Manual\n" }, policy());
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
  const bare = ctxFor(ONE_SIDED, { ...defaultConfig, supersession: undefined });
  assert.deepEqual(run(bare), []);
  cleanup(bare);
});

test("a known exception silences exactly its pair", () => {
  const ctx = ctxFor(
    { ...ONE_SIDED, "docs/adr/0003-other.md": record("0003", "Other", "—", "—"), [NEW]: record("0002", "New", `supersedes ${A("0001")} and ${A("0003")}`, "—") },
    policy({ knownExceptions: ["0001|0002"] }),
  );
  assert.deepEqual(run(ctx).map((f) => f.file), ["docs/adr/0003-other.md"]);
  cleanup(ctx);
});

test("the kit's own records pass under the policy it ships", () => {
  const ctx = makeContext({ repoRoot: KIT, config: defaultConfig });
  assert.deepEqual(run(ctx), []);
});

test("every known exception is still one-sided — a closed link leaves the list", () => {
  const ctx = makeContext({ repoRoot: KIT, config: policy() });
  const open = new Set(run(ctx).map((f) => {
    const [, old, by] = f.message.match(/^ADR-(\d{4}) is superseded by ADR-(\d{4})/);
    return `${old}|${by}`;
  }));
  for (const entry of defaultConfig.supersession.knownExceptions) {
    assert.ok(open.has(entry), `${entry} is listed but the link is no longer one-sided`);
  }
});

// The POSIX twin: scripts/check.sh without node reads the same block by text.
function posixProject(records, exceptions = []) {
  const cfg = readFileSync(join(KIT, "scripts/docs-conformance/config.mjs"), "utf8");
  const block = cfg.match(/^const supersession = \{[\s\S]*?^\};$/m)[0]
    .replace(/knownExceptions: \[[\s\S]*?\]/, `knownExceptions: [\n${exceptions.map((e) => `    "${e}",\n`).join("")}  ]`);
  const root = makeFixture({
    "AGENTS.md": "# Manual\n",
    VERSION: "shared-layer: 0.0.0\n",
    ...records,
    "scripts/docs-conformance/config.mjs": `${block}\nexport default { supersession };\n`,
  });
  for (const f of ["scripts/check.sh", "scripts/manifest.lib.sh", "scripts/requirement.lib.sh"]) {
    mkdirSync(dirname(join(root, f)), { recursive: true });
    copyFileSync(join(KIT, f), join(root, f));
  }
  const res = spawnSync("sh", ["scripts/check.sh"], {
    cwd: root,
    encoding: "utf8",
    env: { ...process.env, DOCS_CHECK_NO_NODE: "1", GIT_CEILING_DIRECTORIES: dirname(root) },
  });
  rmSync(root, { recursive: true, force: true });
  return res;
}

test("the POSIX fallback reports the same one-sided supersession", () => {
  const res = posixProject(ONE_SIDED);
  assert.equal(res.status, 1, `expected exit 1, got ${res.status}\n${res.stdout}${res.stderr}`);
  assert.equal(res.stderr.match(/\[supersession-one-sided\]/g)?.length, 1);
  assert.match(res.stderr, /docs\/adr\/0001-old\.md/);
  assert.ok(res.stderr.includes(`${A("0001")} is superseded by ${A("0002")}`));
});

test("the POSIX fallback is green on the two-sided tree, and on an amendment", () => {
  for (const records of [TWO_SIDED, { [OLD]: record("0001", "Old", "—", "—"), [NEW]: record("0002", "New", `amends ${A("0001")}`, "—") }]) {
    const res = posixProject(records);
    assert.equal(res.status, 0, `expected exit 0, got ${res.status}\n${res.stdout}${res.stderr}`);
    assert.doesNotMatch(res.stderr, /supersession-one-sided/);
  }
});

test("the POSIX fallback holds every id in a supersedes clause, and skips the template", () => {
  const res = posixProject({
    [OLD]: record("0001", "Old", "—", "—"),
    "docs/adr/0003-other.md": record("0003", "Other", "—", "—"),
    "docs/adr/NNNN-template.md": record("NNNN", "T", `supersedes ${A("0001")}`, "—"),
    [NEW]: record("0002", "New", `Supersedes ${A("0001")} clause 1; supersedes the amendment of ${A("0003")} (#9)`, "—"),
  });
  assert.equal(res.status, 1, `expected exit 1, got ${res.status}\n${res.stdout}${res.stderr}`);
  assert.equal(res.stderr.match(/\[supersession-one-sided\]/g)?.length, 2);
  assert.match(res.stderr, /0003-other\.md/);
});

test("the POSIX fallback's known exception silences exactly its pair", () => {
  const res = posixProject(ONE_SIDED, ["0001|0002"]);
  assert.equal(res.status, 0, `expected exit 0, got ${res.status}\n${res.stdout}${res.stderr}`);
});
