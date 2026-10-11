import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

// The helper, not each test, owns fixture cleanup (#731): a test that fails
// before its own cleanup — or never calls it — must leave no docs-conf-*
// directory behind. Proven in a child run with a private temp directory, so
// the count is this run's alone and no other process's fixtures can blur it.

const helpers = pathToFileURL(join(import.meta.dirname, "helpers.mjs")).href;

test("fixtures a failing test made are gone when its file finishes", () => {
  const tmp = mkdtempSync(join(tmpdir(), "fixture-cleanup-"));
  try {
    const file = join(tmp, "child.test.mjs");
    writeFileSync(
      file,
      [
        'import { test } from "node:test";',
        'import assert from "node:assert/strict";',
        `import { ctxFor, makeFixture } from ${JSON.stringify(helpers)};`,
        'test("fails before its cleanup", () => {',
        '  ctxFor({ "AGENTS.md": "x\\n" });',
        '  assert.fail("on purpose");',
        "});",
        'test("never calls cleanup at all", () => {',
        '  console.log("FIXTURE " + makeFixture({ "a.md": "y\\n" }));',
        "});",
        "",
      ].join("\n"),
    );
    // The parent runner's NODE_TEST_CONTEXT would turn the child into one of
    // its own subtests, reporting upward and exiting 0; drop it.
    const { NODE_TEST_CONTEXT: _, ...env } = process.env;
    const run = spawnSync(process.execPath, ["--test", file], {
      env: { ...env, TMPDIR: tmp, TMP: tmp, TEMP: tmp },
      encoding: "utf8",
    });
    assert.notEqual(run.status, 0, "the child run should fail on purpose");
    assert.match(run.stdout, /on purpose/, "the failing test should have run");
    // Non-vacuous: the child really made its fixtures in the private tmp.
    assert.ok(
      run.stdout.includes(`FIXTURE ${join(tmp, "docs-conf-")}`),
      `the child should have made a fixture under ${tmp}:\n${run.stdout}`,
    );
    const left = readdirSync(tmp).filter((n) => n.startsWith("docs-conf-"));
    assert.deepEqual(left, [], "every fixture the child made is removed");
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
});
