import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import defaultConfig from "../config.mjs";
import { makeContext } from "../context.mjs";
import { run } from "../validators/skill-tools.mjs";
import { cleanup, ctxFor, hasRule, makeFixture } from "./helpers.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const KIT = join(here, "..", "..", "..");

// Declared tools: a skill's `allowed-tools`, an agent type's `tools:` line,
// and a spawn that may only narrow. One fixture tree per rule, each failing
// and passing; the shipped policy holds the first rule at a warning until
// every kit skill declares its tools, so the failing arm runs under a policy
// that turns it to a violation.

const STRICT = { ...defaultConfig, skillTools: { ...defaultConfig.skillTools, missingAllowedTools: "violation" } };

const TYPES = {
  "adapters/claude-code/agents/reviewer.md": "---\nname: reviewer\ndescription: reads.\ntools: Read, Grep, Glob\n---\nBody.\n",
  "adapters/claude-code/agents/implementer.md":
    "---\nname: implementer\ndescription: builds.\ntools: Read, Grep, Glob, Bash, Edit, Write, Skill, Agent\n---\nBody.\n",
};

const skill = (frontmatter, body = "Do the work.\n") => `---\nname: demo\ndescription: a demo.\n${frontmatter}---\n\n# demo\n\n${body}`;

// --- R30: a SKILL.md with no allowed-tools fails ---------------------

test("R30: a SKILL.md with no allowed-tools fails, naming the skill", () => {
  const ctx = ctxFor({ ".agents/skills/demo/SKILL.md": skill("") }, STRICT);
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].rule, "skill-allowed-tools-missing");
  assert.equal(out[0].file, ".agents/skills/demo/SKILL.md");
  assert.notEqual(out[0].severity, "warning");
  assert.match(out[0].message, /^demo has no allowed-tools in its frontmatter/);
  cleanup(ctx);
});

test("R30: a SKILL.md that declares allowed-tools passes", () => {
  const ctx = ctxFor({ ".agents/skills/demo/SKILL.md": skill("allowed-tools: Read, Grep, Glob\n") }, STRICT);
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("R30: the Agent Skills spellings all declare — space-separated, a flow list, a block list, a scoped tool", () => {
  for (const fm of [
    "allowed-tools: Read Grep Bash(git diff:*)\n",
    "allowed-tools: [Read, Grep]\n",
    "allowed-tools:\n  - Read\n  - Grep\n",
  ]) {
    const ctx = ctxFor({ ".agents/skills/demo/SKILL.md": skill(fm) }, STRICT);
    assert.deepEqual(run(ctx), [], fm);
    cleanup(ctx);
  }
});

test("R30: an empty allowed-tools declares nothing, and a key in the body is not frontmatter", () => {
  for (const raw of [skill("allowed-tools:\n"), "# demo\n\nallowed-tools: Read\n"]) {
    const ctx = ctxFor({ ".agents/skills/demo/SKILL.md": raw }, STRICT);
    assert.ok(hasRule(run(ctx), "skill-allowed-tools-missing"), raw);
    cleanup(ctx);
  }
});

test("R30: the shipped policy holds the missing-allowed-tools rule at a warning", () => {
  assert.equal(defaultConfig.skillTools.missingAllowedTools, "warning");
  const ctx = ctxFor({
    ".agents/skills/demo/SKILL.md": skill(""),
    ".agents/skills/other/SKILL.md": skill(""),
    ".agents/skills/typed/SKILL.md": skill("allowed-tools: Read\n"),
  });
  const out = run(ctx);
  assert.equal(out.length, 1, "one advisory names every undeclared skill");
  assert.equal(out[0].severity, "warning");
  assert.equal(out[0].file, ".agents/skills");
  assert.equal(out[0].message, "no allowed-tools in the frontmatter of demo, other, so nothing states the tools they use");
  cleanup(ctx);
});

test("R30: a skill at both homes is read once, from the configured home", () => {
  const ctx = ctxFor(
    {
      ".agents/skills/demo/SKILL.md": skill(""),
      ".claude/skills/demo/SKILL.md": skill(""),
    },
    STRICT,
  );
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].file, ".agents/skills/demo/SKILL.md");
  cleanup(ctx);
});

// --- R31: an agent type with no tools: line fails -------------------

test("R31: an agent type with no tools line fails — UC2 2a's message", () => {
  const ctx = ctxFor({
    ...TYPES,
    "adapters/claude-code/agents/reviewer.md": "---\nname: reviewer\ndescription: reads.\n---\nBody.\n",
  });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].rule, "agent-type-tools-missing");
  assert.equal(out[0].file, "adapters/claude-code/agents/reviewer.md");
  assert.notEqual(out[0].severity, "warning");
  assert.equal(out[0].message, "reviewer has no tools line, so it inherits every tool");
  cleanup(ctx);
});

test("R31: every agent type with a tools line passes, and the wired directory is read too", () => {
  const ctx = ctxFor({ ...TYPES, ".claude/agents/planner.md": "---\nname: planner\ntools: Read\n---\n" });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("R31: an empty tools line, or one only in the body, is no tools line", () => {
  for (const raw of ["---\nname: planner\ntools:\n---\n", "---\nname: planner\n---\ntools: Read\n"]) {
    const ctx = ctxFor({ ".claude/agents/planner.md": raw });
    const out = run(ctx);
    assert.ok(hasRule(out, "agent-type-tools-missing"), raw);
    assert.equal(out[0].file, ".claude/agents/planner.md");
    cleanup(ctx);
  }
});

test("R31: a type with no name line is named by its file", () => {
  const ctx = ctxFor({ ".claude/agents/scout.md": "---\ndescription: looks.\n---\n" });
  assert.equal(run(ctx)[0].message, "scout has no tools line, so it inherits every tool");
  cleanup(ctx);
});

// --- R32: a spawn type only narrows ----------------------------------

const REVIEW_PR = (type) =>
  `---\nname: review-pr\ndescription: reviews.\nallowed-tools: Read, Grep, Glob, Bash, Skill\n---\n\n# review-pr\n\nSpawn each lens as the \`${type}\` agent type on that answer.\n`;

test("R32: a skill spawning a type whose tools are outside its own fails — UC2's message", () => {
  const ctx = ctxFor({ ...TYPES, ".agents/skills/review-pr/SKILL.md": REVIEW_PR("implementer") });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].rule, "spawn-widens-tools");
  assert.equal(out[0].file, ".agents/skills/review-pr/SKILL.md");
  assert.notEqual(out[0].severity, "warning");
  assert.equal(out[0].message, "review-pr spawns implementer, whose tools (Edit, Write, Agent) are outside its allowed-tools");
  cleanup(ctx);
});

test("R32: a spawn type within the skill's tools passes", () => {
  const ctx = ctxFor({ ...TYPES, ".agents/skills/review-pr/SKILL.md": REVIEW_PR("reviewer") });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

const WIDE = (allowed) =>
  REVIEW_PR("implementer").replace("allowed-tools: Read, Grep, Glob, Bash, Skill", `allowed-tools: ${allowed}`);

test("R32: a scoped entry in allowed-tools does not cover the type's unscoped tool", () => {
  const ctx = ctxFor({ ...TYPES, ".agents/skills/review-pr/SKILL.md": WIDE("Read Grep Glob Bash(git diff:*) Skill Edit Write Agent") });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].rule, "spawn-widens-tools");
  assert.equal(out[0].message, "review-pr spawns implementer, whose tools (Bash) are outside its allowed-tools");
  cleanup(ctx);
});

test("R32: a bare name covers every scope of its tool, and a scoped entry covers only its own spelling", () => {
  const SCOUT = { ".claude/agents/scout.md": "---\nname: scout\ntools: Read, Bash(git diff:*)\n---\n" };
  const spawns = (allowed) => ({
    ...SCOUT,
    ".agents/skills/look/SKILL.md": `---\nname: look\ndescription: looks.\nallowed-tools: ${allowed}\n---\n\nSpawn the \`scout\` agent type.\n`,
  });
  for (const allowed of ["Read, Bash", "Read, Bash(git diff:*)"]) {
    const ctx = ctxFor(spawns(allowed));
    assert.deepEqual(run(ctx), [], allowed);
    cleanup(ctx);
  }
  const ctx = ctxFor(spawns("Read, Bash(git log:*)"));
  assert.deepEqual(
    run(ctx).map((f) => f.message),
    ["look spawns scout, whose tools (Bash(git diff:*)) are outside its allowed-tools"],
  );
  cleanup(ctx);
});

test("R32: a spawn named in a supporting file of the skill counts, across a line break", () => {
  const ctx = ctxFor({
    ...TYPES,
    ".agents/skills/review-pr/SKILL.md": REVIEW_PR("reviewer"),
    ".agents/skills/review-pr/LENS.md": "Spawn it as the `implementer`\nagent type.\n",
  });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].file, ".agents/skills/review-pr/LENS.md");
  cleanup(ctx);
});

test("R32: a token that names no agent type, or sits in a fence, is no spawn", () => {
  const ctx = ctxFor({
    ...TYPES,
    ".agents/skills/review-pr/SKILL.md": REVIEW_PR("ghost").replace(
      "on that answer.",
      "on that answer.\n\n```\nthe `implementer` agent type\n```\n",
    ),
  });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("R32: a skill with no allowed-tools is R30's finding alone, never a widening", () => {
  const ctx = ctxFor(
    { ...TYPES, ".agents/skills/review-pr/SKILL.md": REVIEW_PR("implementer").replace(/allowed-tools:.*\n/, "") },
    STRICT,
  );
  const out = run(ctx);
  assert.deepEqual(
    out.map((f) => f.rule),
    ["skill-allowed-tools-missing"],
  );
  cleanup(ctx);
});

// --- the kit itself ------------------------------------------------------------

test("the kit's own tree: every agent type names its tools, and no skill widens", () => {
  const ctx = makeContext({ repoRoot: KIT, config: STRICT });
  const out = run(ctx).filter((f) => f.rule !== "skill-allowed-tools-missing");
  assert.deepEqual(out, []);
});

// --- both engines, end to end ------------------------------------------------

// A project carrying the gate, its harness and the kit's config.mjs, and the
// fixture files — not a copy of the kit, whose tree would bring every other
// rule's findings with it.
function project(files, { node, strict = false }) {
  let cfg = readFileSync(join(KIT, "scripts/docs-conformance/config.mjs"), "utf8");
  if (strict) cfg = cfg.replace('missingAllowedTools: "warning"', 'missingAllowedTools: "violation"');
  const shim = readFileSync(join(KIT, "CLAUDE.md"), "utf8");
  const root = makeFixture({
    "AGENTS.md": "# Manual\n",
    "CLAUDE.md": shim,
    "GEMINI.md": readFileSync(join(KIT, "GEMINI.md"), "utf8"),
    VERSION: "shared-layer: 0.0.0\n",
    ...files,
    "scripts/docs-conformance/config.mjs": cfg,
  });
  const harness = join(KIT, "scripts/docs-conformance");
  for (const f of ["index.mjs", "context.mjs", "runner.mjs"]) copyFileSync(join(harness, f), join(root, "scripts/docs-conformance", f));
  mkdirSync(join(root, "scripts/docs-conformance/validators"), { recursive: true });
  for (const f of readdirValidators()) copyFileSync(join(harness, "validators", f), join(root, "scripts/docs-conformance/validators", f));
  for (const f of ["scripts/check.sh", "scripts/manifest.lib.sh", "scripts/requirement.lib.sh"]) copyFileSync(join(KIT, f), join(root, f));
  return spawnSync("sh", ["scripts/check.sh"], {
    cwd: root,
    encoding: "utf8",
    env: { ...process.env, DOCS_CHECK_NO_NODE: node ? "" : "1", GIT_CEILING_DIRECTORIES: dirname(root) },
  });
}

function readdirValidators() {
  return spawnSync("ls", [join(KIT, "scripts/docs-conformance/validators")], { encoding: "utf8" }).stdout.split("\n").filter(Boolean);
}

for (const node of [true, false]) {
  const engine = node ? "the docs harness" : "the POSIX fallback";

  test(`${engine}: UC2 fails with the PRD's message, and the reviewer spawn passes`, () => {
    const bad = project({ ...TYPES, ".agents/skills/review-pr/SKILL.md": REVIEW_PR("implementer") }, { node });
    assert.equal(bad.status, 1, `${bad.stdout}${bad.stderr}`);
    assert.match(bad.stderr, /spawn-widens-tools/);
    assert.match(bad.stderr, /review-pr spawns implementer, whose tools \(Edit, Write, Agent\) are outside its allowed-tools/);
    const good = project({ ...TYPES, ".agents/skills/review-pr/SKILL.md": REVIEW_PR("reviewer") }, { node });
    assert.equal(good.status, 0, `${good.stdout}${good.stderr}`);
  });

  test(`${engine}: UC2 2a fails with the PRD's message`, () => {
    const res = project(
      { ...TYPES, ".claude/agents/reviewer.md": "---\nname: reviewer\ndescription: reads.\n---\n" },
      { node },
    );
    assert.equal(res.status, 1, `${res.stdout}${res.stderr}`);
    assert.match(res.stderr, /agent-type-tools-missing/);
    assert.match(res.stderr, /\.claude\/agents\/reviewer\.md/);
    assert.match(res.stderr, /reviewer has no tools line, so it inherits every tool/);
  });

  test(`${engine}: R32 — a scoped entry covers only its own spelling, never the unscoped tool`, () => {
    const scoped = project(
      { ...TYPES, ".agents/skills/review-pr/SKILL.md": WIDE("Read, Grep, Glob, Bash(git diff:*), Skill, Edit, Write, Agent") },
      { node },
    );
    assert.equal(scoped.status, 1, `${scoped.stdout}${scoped.stderr}`);
    assert.match(scoped.stderr, /review-pr spawns implementer, whose tools \(Bash\) are outside its allowed-tools/);
    const scout = (allowed) =>
      project(
        {
          ".claude/agents/scout.md": "---\nname: scout\ntools: Read, Bash(git diff:*)\n---\n",
          ".agents/skills/look/SKILL.md": `---\nname: look\ndescription: looks.\nallowed-tools: ${allowed}\n---\n\nSpawn the \`scout\` agent type.\n`,
        },
        { node },
      );
    const same = scout("Read, Bash(git diff:*)");
    assert.equal(same.status, 0, `${same.stdout}${same.stderr}`);
    const other = scout("Read, Bash(git log:*)");
    assert.equal(other.status, 1, `${other.stdout}${other.stderr}`);
    assert.match(other.stderr, /look spawns scout, whose tools \(Bash\(git diff:\*\)\) are outside its allowed-tools/);
  });

  test(`${engine}: a skill with no allowed-tools warns under the shipped policy and fails under a strict one`, () => {
    const files = { ".agents/skills/demo/SKILL.md": skill("") };
    const warned = project(files, { node });
    assert.equal(warned.status, 0, `${warned.stdout}${warned.stderr}`);
    assert.match(warned.stderr, /skill-allowed-tools-missing/);
    assert.match(warned.stderr, /no allowed-tools in the frontmatter of demo, so nothing states the tools they use/);
    const failed = project(files, { node, strict: true });
    assert.equal(failed.status, 1, `${failed.stdout}${failed.stderr}`);
    assert.match(failed.stderr, /demo has no allowed-tools in its frontmatter/);
    const declared = project({ ".agents/skills/demo/SKILL.md": skill("allowed-tools: Read\n") }, { node, strict: true });
    assert.equal(declared.status, 0, `${declared.stdout}${declared.stderr}`);
    assert.doesNotMatch(declared.stderr, /skill-allowed-tools-missing/);
  });
}
