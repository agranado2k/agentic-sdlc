import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after } from "node:test";
import defaultConfig from "../config.mjs";
import { makeContext } from "../context.mjs";

// Every fixture this test file made, removed when the file's tests finish —
// passed, failed or never cleaned up by hand (#731). Each test file runs in
// its own process under `node --test`, so a root-level after-hook is per file.
const made = new Set();
after(() => {
  for (const root of made) rmSync(root, { recursive: true, force: true });
  made.clear();
});

/** Write a `{ 'rel/path': 'content' }` map into a fresh temp dir; return root. */
export function makeFixture(files) {
  const root = mkdtempSync(join(tmpdir(), "docs-conf-"));
  made.add(root);
  for (const [rel, content] of Object.entries(files)) {
    const p = join(root, rel);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, content);
  }
  return root;
}

/** Build a context over a fixture tree, with an optional config override. */
export function ctxFor(files, config = defaultConfig) {
  return makeContext({ repoRoot: makeFixture(files), config });
}

export function cleanup(ctx) {
  rmSync(ctx.repoRoot, { recursive: true, force: true });
}

/** A rule id appears among the given violations. */
export function hasRule(violations, rule) {
  return violations.some((v) => v.rule === rule);
}

/**
 * The shipped config with one section replaced. Used by tests that exercise a
 * policy knob (a local vocabulary, a different constitution directory) without
 * mutating the module-level config every other test shares.
 */
export function configWith(overrides) {
  return {
    ...defaultConfig,
    claudeMdRefs: { ...defaultConfig.claudeMdRefs, ...overrides },
  };
}
