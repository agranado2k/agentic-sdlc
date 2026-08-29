import assert from "node:assert/strict";
import { mkdirSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { run } from "../validators/skill-bridge.mjs";
import { cleanup, ctxFor, hasRule, makeFixture } from "./helpers.mjs";
import defaultConfig from "../config.mjs";
import { makeContext } from "../context.mjs";

// The signature this validator hunts: a checkout where core.symlinks=false
// materialized the .claude/skills/<name> bridge as a REGULAR FILE holding the
// link target's text. The harness that reads only that address then goes
// blind to every skill, silently.
const TARGET = "../../.agents/skills/tdd";

test("a materialized bridge — a text file holding the link target — warns, and only warns", () => {
  const ctx = ctxFor({
    ".agents/skills/tdd/SKILL.md": "# tdd\n",
    ".claude/skills/tdd": TARGET,
  });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.ok(hasRule(out, "skill-bridge-broken"));
  assert.equal(out[0].severity, "warning");
  assert.equal(out[0].file, ".claude/skills/tdd");
  cleanup(ctx);
});

test("a healthy symlink bridge is silent", () => {
  const root = makeFixture({
    ".agents/skills/tdd/SKILL.md": "# tdd\n",
  });
  mkdirSync(join(root, ".claude/skills"), { recursive: true });
  symlinkSync("../../.agents/skills/tdd", join(root, ".claude/skills/tdd"));
  const ctx = makeContext({ repoRoot: root, config: defaultConfig });
  assert.deepEqual(run(ctx), []);
});

test("a real directory at the old address is silent — staying put is legal", () => {
  const ctx = ctxFor({
    ".claude/skills/tdd/SKILL.md": "# their own tdd, real files\n",
  });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("an ordinary file that is not link-shaped is silent — this rule names one signature only", () => {
  const ctx = ctxFor({
    ".claude/skills/LICENSE-mattpocock-skills.md": "# a licence, many lines\nof prose\n",
  });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("no .claude/skills directory, no finding", () => {
  const ctx = ctxFor({ "README.md": "nothing here\n" });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("the kit's own tree is silent — its bridges are real symlinks", () => {
  const here = dirname(fileURLToPath(import.meta.url));
  const ctx = makeContext({ repoRoot: join(here, "..", "..", ".."), config: defaultConfig });
  assert.deepEqual(run(ctx), []);
});

test("the hint names the canonical path repo-relatively, and only claims it is there when it is", () => {
  const present = ctxFor({
    ".agents/skills/tdd/SKILL.md": "# tdd\n",
    ".claude/skills/tdd": TARGET,
  });
  const withSkill = run(present);
  assert.match(withSkill[0].hint, /is intact at \.agents\/skills\/tdd\./);
  cleanup(present);

  // Both copies lost: the hint must not assert a file that is not there.
  const absent = ctxFor({ ".claude/skills/tdd": TARGET });
  const withoutSkill = run(absent);
  assert.match(withoutSkill[0].hint, /should be at \.agents\/skills\/tdd\./);
  cleanup(absent);
});
