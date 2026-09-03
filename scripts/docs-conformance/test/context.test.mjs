import assert from "node:assert/strict";
import { chmodSync, mkdirSync, symlinkSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { cleanup, ctxFor } from "./helpers.mjs";

// The context's contract, as a seam: one error mode for `read`, and `kind`
// as the only way to tell a directory from a file. Validators used to wrap
// `read` in their own try/catch to make that distinction; these are the
// cases those wrappers existed for.

test("read returns the text of a file, and null for a missing path", () => {
  const ctx = ctxFor({ "a.md": "hello\n" });
  assert.equal(ctx.read("a.md"), "hello\n");
  assert.equal(ctx.read("missing.md"), null);
  cleanup(ctx);
});

test("read returns null for a directory — it does not throw", () => {
  const ctx = ctxFor({ "dir/inner.md": "x\n" });
  assert.equal(ctx.read("dir"), null);
  cleanup(ctx);
});

test("kind says file, directory, or null", () => {
  const ctx = ctxFor({ "a.md": "hello\n", "dir/inner.md": "x\n" });
  assert.equal(ctx.kind("a.md"), "file");
  assert.equal(ctx.kind("dir"), "directory");
  assert.equal(ctx.kind("missing"), null);
  cleanup(ctx);
});

test("a symlink is reported as what it resolves to; a dangling one as null, and read gives null", () => {
  const ctx = ctxFor({ "real/SKILL.md": "# real\n" });
  mkdirSync(join(ctx.repoRoot, "links"), { recursive: true });
  symlinkSync("../real", join(ctx.repoRoot, "links/good"));
  symlinkSync("../nowhere", join(ctx.repoRoot, "links/dangling"));
  assert.equal(ctx.kind("links/good"), "directory");
  assert.equal(ctx.kind("links/dangling"), null);
  assert.equal(ctx.read("links/dangling"), null);
  cleanup(ctx);
});

test(
  "an unreadable file is a file to kind and null to read — the one shape a validator must report, not skip",
  { skip: process.getuid?.() === 0 && "chmod does not restrain root" },
  () => {
    const ctx = ctxFor({ "locked.md": "secret\n" });
    chmodSync(join(ctx.repoRoot, "locked.md"), 0o000);
    try {
      assert.equal(ctx.kind("locked.md"), "file");
      assert.equal(ctx.read("locked.md"), null);
    } finally {
      chmodSync(join(ctx.repoRoot, "locked.md"), 0o644);
      cleanup(ctx);
    }
  },
);

test("the context exposes exactly read, kind, list and exists — no recursive lister", () => {
  const ctx = ctxFor({});
  assert.deepEqual(Object.keys(ctx).sort(), ["config", "exists", "kind", "list", "read", "repoRoot"]);
  cleanup(ctx);
});
