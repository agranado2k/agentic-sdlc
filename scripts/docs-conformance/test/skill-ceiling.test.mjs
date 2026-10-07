import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import defaultConfig from "../config.mjs";
import { makeContext } from "../context.mjs";
import { run } from "../validators/skill-ceiling.mjs";
import { cleanup, ctxFor, makeFixture } from "./helpers.mjs";

// R8: the docs gate fails a SKILL.md over the byte ceiling its policy
// declares for it, naming the file, its size and the ceiling — in both engines.

const here = dirname(fileURLToPath(import.meta.url));
const KIT = join(here, "..", "..", "..");
const SKILL = ".agents/skills/big/SKILL.md";
const withCeilings = (skillCeilings) => ({ ...defaultConfig, skillCeilings });

test("R8: a SKILL.md over its ceiling fails, naming the file, its size and the ceiling", () => {
  const ctx = ctxFor({ [SKILL]: "x".repeat(120) }, withCeilings({ [SKILL]: 100 }));
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].rule, "skill-over-ceiling");
  assert.notEqual(out[0].severity, "warning");
  assert.equal(out[0].file, SKILL);
  assert.match(out[0].message, /\b120 bytes\b/);
  assert.match(out[0].message, /\b100 bytes\b/);
  cleanup(ctx);
});

test("R8: the same tree under its ceiling, and exactly at it, is green", () => {
  const under = ctxFor({ [SKILL]: "x".repeat(99) }, withCeilings({ [SKILL]: 100 }));
  assert.deepEqual(run(under), []);
  cleanup(under);
  const at = ctxFor({ [SKILL]: "x".repeat(100) }, withCeilings({ [SKILL]: 100 }));
  assert.deepEqual(run(at), []);
  cleanup(at);
});

test("R8: the size is bytes, not characters", () => {
  // 60 two-byte characters: 60 characters, 120 bytes.
  const ctx = ctxFor({ [SKILL]: "é".repeat(60) }, withCeilings({ [SKILL]: 100 }));
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.match(out[0].message, /\b120 bytes\b/);
  cleanup(ctx);
});

test("R8: a skill with no declared ceiling, and a ceiling on an absent file, are silent", () => {
  const ctx = ctxFor(
    { [SKILL]: "x".repeat(500) },
    withCeilings({ ".agents/skills/gone/SKILL.md": 10 }),
  );
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
  const none = ctxFor({ [SKILL]: "x".repeat(500) }, withCeilings(undefined));
  assert.deepEqual(run(none), []);
  cleanup(none);
});

test("R8: the kit's own skills sit under the ceilings its policy declares", () => {
  const ctx = makeContext({ repoRoot: KIT, config: defaultConfig });
  assert.ok(Object.keys(defaultConfig.skillCeilings ?? {}).length >= 4, "the policy declares the four largest skills' ceilings");
  assert.deepEqual(run(ctx), []);
});

test("R8: every ceiling the kit declares names a skill the kit ships — a mistyped path would be silent", () => {
  const ctx = makeContext({ repoRoot: KIT, config: defaultConfig });
  for (const file of Object.keys(defaultConfig.skillCeilings ?? {})) {
    assert.equal(ctx.kind(file), "file", `${file} has a ceiling but is no file in the kit`);
  }
});

// The POSIX twin: scripts/check.sh without node reads the same policy by text
// from config.mjs, so the fixture carries the kit's real wrapper, its two
// sourced libraries and a config whose block is spelled as the kit's is.
function posixProject(skillBytes) {
  const root = makeFixture({
    "AGENTS.md": "# Manual\n",
    VERSION: "shared-layer: 0.0.0\n",
    [SKILL]: "x".repeat(skillBytes),
    "scripts/docs-conformance/config.mjs": [
      "const skillCeilings = {",
      `  "${SKILL}": 100,`,
      "};",
      "export default { skillCeilings };",
      "",
    ].join("\n"),
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

test("R8: the POSIX fallback reports the same failure — file, size and ceiling", () => {
  const res = posixProject(120);
  assert.equal(res.status, 1, `expected exit 1, got ${res.status}\n${res.stdout}${res.stderr}`);
  assert.match(res.stderr, /skill-over-ceiling/);
  assert.match(res.stderr, /\.agents\/skills\/big\/SKILL\.md/);
  assert.match(res.stderr, /\b120 bytes\b/);
  assert.match(res.stderr, /\b100 bytes\b/);
});

test("R8: the POSIX fallback is green on the same tree under its ceiling", () => {
  const res = posixProject(100);
  assert.equal(res.status, 0, `expected exit 0, got ${res.status}\n${res.stdout}${res.stderr}`);
  assert.doesNotMatch(res.stderr, /skill-over-ceiling/);
});
