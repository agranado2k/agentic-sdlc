import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import defaultConfig from "../config.mjs";
import { makeContext } from "../context.mjs";
import { run } from "../validators/skill-dated.mjs";
import { cleanup, ctxFor, makeFixture } from "./helpers.mjs";

// #678: the docs gate refuses dated kit-only evidence — an ISO date, a cite
// of the kit's retro, an amendment's issue — in a shipped SKILL.md body, in
// both engines. Fenced examples are not evidence.

const here = dirname(fileURLToPath(import.meta.url));
const KIT = join(here, "..", "..", "..");
const SKILL = ".agents/skills/demo/SKILL.md";
const CLEAN = "# Demo\n\nRecord the verdict on the slice (the kit's ADR-0008).\n";
const DATED = `${CLEAN}The evidence (the kit's retro of 2026-10-07): 114 of 171 raises were LOW.\n`;
const policy = (over = {}) => ({
  ...defaultConfig,
  skillDated: { ...defaultConfig.skillDated, knownExceptions: [], ...over },
});

test("a dated line in a skill body fails, naming the file and the dated token", () => {
  const ctx = ctxFor({ [SKILL]: DATED }, policy());
  const out = run(ctx);
  assert.deepEqual(out.map((f) => f.rule), ["skill-dated-evidence", "skill-dated-evidence"]);
  for (const f of out) {
    assert.equal(f.file, SKILL);
    assert.notEqual(f.severity, "warning");
  }
  assert.ok(out.some((f) => f.message.includes("2026-10-07")));
  assert.ok(out.some((f) => f.message.includes("the kit's retro")));
  cleanup(ctx);
});

test("the same tree without the dated line is green", () => {
  const ctx = ctxFor({ [SKILL]: CLEAN }, policy());
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("an amendment's issue cite fails even with no date beside it", () => {
  const ctx = ctxFor({ [SKILL]: `${CLEAN}This rule (amended #385) holds.\n` }, policy());
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.match(out[0].message, /amended #385/);
  cleanup(ctx);
});

test("a date inside a fence is an example, not evidence; a supporting file is not the body", () => {
  const ctx = ctxFor(
    {
      [SKILL]: `${CLEAN}\n\`\`\`sh\nsh scripts/retro.sh --since 2026-01-01\n\`\`\`\n`,
      ".agents/skills/demo/NOTES.md": DATED,
    },
    policy(),
  );
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("a skill at the legacy home is read too, and one at both homes once, under the configured home", () => {
  const legacy = ".claude/skills/old/SKILL.md";
  const ctx = ctxFor(
    { [legacy]: DATED, [SKILL]: DATED, ".claude/skills/demo/SKILL.md": DATED },
    policy(),
  );
  const files = run(ctx).map((f) => f.file);
  assert.deepEqual([...new Set(files)].sort(), [legacy, SKILL].sort());
  assert.equal(files.length, 4);
  cleanup(ctx);
});

test("a known exception silences exactly its file and token", () => {
  const ctx = ctxFor(
    { [SKILL]: DATED },
    policy({ knownExceptions: [`${SKILL}|2026-10-07`] }),
  );
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.match(out[0].message, /the kit's retro/);
  cleanup(ctx);
});

test("the kit's own skills pass under the policy it ships", () => {
  const ctx = makeContext({ repoRoot: KIT, config: defaultConfig });
  assert.deepEqual(run(ctx), []);
});

test("every known exception still names a dated token in its file — a fixed site leaves the list", () => {
  for (const entry of defaultConfig.skillDated.knownExceptions) {
    const [file, token] = entry.split("|");
    const body = readFileSync(join(KIT, file), "utf8");
    assert.ok(body.includes(token), `${entry} is listed but its file no longer carries the token`);
  }
});

// The POSIX twin: scripts/check.sh without node reads the same block by text.
function posixProject(skillBody, exceptions = [], extra = {}) {
  const cfg = readFileSync(join(KIT, "scripts/docs-conformance/config.mjs"), "utf8");
  const block = cfg.match(/^const skillDated = \{[\s\S]*?^\};$/m)[0]
    .replace(/knownExceptions: \[[\s\S]*?\]/, `knownExceptions: [\n${exceptions.map((e) => `    "${e}",\n`).join("")}  ]`);
  const root = makeFixture({
    "AGENTS.md": "# Manual\n",
    VERSION: "shared-layer: 0.0.0\n",
    [SKILL]: skillBody,
    ...extra,
    "scripts/docs-conformance/config.mjs": `const claudeMdRefs = {\n  skillsDir: ".agents/skills",\n};\n${block}\nexport default { claudeMdRefs, skillDated };\n`,
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

test("the POSIX fallback reports the same failure — file and every token, the amendment cite included", () => {
  const res = posixProject(`${DATED}This rule (amended #385) holds.\n`);
  assert.equal(res.status, 1, `expected exit 1, got ${res.status}\n${res.stdout}${res.stderr}`);
  assert.equal(res.stderr.match(/\[skill-dated-evidence\]/g)?.length, 3);
  assert.match(res.stderr, /\.agents\/skills\/demo\/SKILL\.md/);
  assert.match(res.stderr, /2026-10-07/);
  assert.match(res.stderr, /the kit's retro/);
  assert.match(res.stderr, /amended #385/);
});

test("the POSIX fallback is green on the same tree without the dated line", () => {
  const res = posixProject(CLEAN);
  assert.equal(res.status, 0, `expected exit 0, got ${res.status}\n${res.stdout}${res.stderr}`);
  assert.doesNotMatch(res.stderr, /skill-dated-evidence/);
});

test("the POSIX fallback skips a date inside a fence", () => {
  const res = posixProject(`${CLEAN}\`\`\`\n2026-01-01\n\`\`\`\n`);
  assert.equal(res.status, 0, `expected exit 0, got ${res.status}\n${res.stdout}${res.stderr}`);
  assert.doesNotMatch(res.stderr, /skill-dated-evidence/);
});

test("the POSIX fallback's known exception silences exactly its file and token", () => {
  const res = posixProject(DATED, [`${SKILL}|2026-10-07`]);
  assert.equal(res.status, 1, `expected exit 1, got ${res.status}\n${res.stdout}${res.stderr}`);
  assert.equal(res.stderr.match(/\[skill-dated-evidence\]/g)?.length, 1);
  assert.match(res.stderr, /the kit's retro/);
  assert.doesNotMatch(res.stderr, /2026-10-07/);
});

test("the POSIX fallback reads the legacy home too, and a skill at both homes once", () => {
  const res = posixProject(DATED, [], { ".claude/skills/old/SKILL.md": DATED, ".claude/skills/demo/SKILL.md": DATED });
  assert.equal(res.status, 1, `expected exit 1, got ${res.status}\n${res.stdout}${res.stderr}`);
  assert.equal(res.stderr.match(/\[skill-dated-evidence\]/g)?.length, 4);
  assert.match(res.stderr, /\.claude\/skills\/old\/SKILL\.md/);
  assert.doesNotMatch(res.stderr, /\.claude\/skills\/demo\/SKILL\.md/);
});
