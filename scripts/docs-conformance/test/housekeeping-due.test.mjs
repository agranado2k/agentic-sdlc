import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import defaultConfig from "../config.mjs";
import { makeContext } from "../context.mjs";
import { run } from "../validators/housekeeping-due.mjs";
import { cleanup, ctxFor, hasRule, makeFixture } from "./helpers.mjs";

const here = dirname(fileURLToPath(import.meta.url));

// The diary's Current state table, as bootstrap stamps it, with the row the
// 0.15.0 template adds. Dates are computed against the real clock, so the
// fixtures stay fresh or stale by construction rather than by calendar.
const DAY_MS = 24 * 60 * 60 * 1000;
const iso = (daysAgo) => new Date(Date.now() - daysAgo * DAY_MS).toISOString().slice(0, 10);
const diaryWith = (rowValue) =>
  [
    "# Development diary",
    "",
    "## Current state — 2026-01-01",
    "",
    "| Field | Value |",
    "| --- | --- |",
    "| **Phase** | Shipping. |",
    ...(rowValue == null ? [] : [`| **Last housekeeping** | ${rowValue} |`]),
    "| **Active worktrees** | None. |",
    "",
    "## Entries",
    "",
  ].join("\n");

const cfgWith = (housekeepingDue) => ({ ...defaultConfig, housekeepingDue });

test("a row dated today is silent", () => {
  const ctx = ctxFor({ "docs/diary.md": diaryWith(`${iso(0)} — bootstrapped; first pass due in a month.`) });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("a row inside the window is silent — the window is inclusive of its last day", () => {
  const ctx = ctxFor({ "docs/diary.md": diaryWith(iso(30)) });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("a row older than the window warns, naming the age and the window", () => {
  const ctx = ctxFor({ "docs/diary.md": diaryWith(`${iso(60)} — the pass found nothing.`) });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.ok(hasRule(out, "housekeeping-due"));
  assert.equal(out[0].severity, "warning");
  assert.equal(out[0].file, "docs/diary.md");
  assert.match(out[0].message, /60 days/);
  assert.match(out[0].message, /30/);
  cleanup(ctx);
});

test("a missing row warns naming the row — and only warns", () => {
  const ctx = ctxFor({ "docs/diary.md": diaryWith(null) });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.ok(hasRule(out, "housekeeping-row-missing"));
  assert.equal(out[0].severity, "warning");
  assert.match(out[0].message, /Last housekeeping/);
  cleanup(ctx);
});

test("a row with no ISO date is a missing row, not a fresh one", () => {
  const ctx = ctxFor({ "docs/diary.md": diaryWith("soon") });
  assert.ok(hasRule(run(ctx), "housekeeping-row-missing"));
  cleanup(ctx);
});

test("the window is policy: a wider windowDays keeps an older row silent", () => {
  const ctx = ctxFor({ "docs/diary.md": diaryWith(iso(60)) }, cfgWith({ windowDays: 90 }));
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("the window is policy: a narrower windowDays makes a younger row warn", () => {
  const ctx = ctxFor({ "docs/diary.md": diaryWith(iso(10)) }, cfgWith({ windowDays: 7 }));
  const out = run(ctx);
  assert.ok(hasRule(out, "housekeeping-due"));
  assert.match(out[0].message, /10 days/);
  assert.match(out[0].message, /7/);
  cleanup(ctx);
});

test("the housekeepingDue.diary override points the rule at a different file", () => {
  const ctx = ctxFor({ "notes/log.md": diaryWith(null) }, cfgWith({ diary: "notes/log.md" }));
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].file, "notes/log.md");
  cleanup(ctx);
});

test("a row only inside a fenced code block is quoted material, not a date", () => {
  const ctx = ctxFor({
    "docs/diary.md": [
      "# Development diary",
      "",
      "```md",
      `| **Last housekeeping** | ${iso(0)} |`,
      "```",
      "",
      "No row of our own.",
      "",
    ].join("\n"),
  });
  assert.ok(hasRule(run(ctx), "housekeeping-row-missing"));
  cleanup(ctx);
});

test("no diary, no finding — a tree without one is not this rule's business", () => {
  const ctx = ctxFor({ "AGENTS.md": "# Manual\n" });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("the kit's own tree is silent — its diary carries a fresh row", () => {
  const ctx = makeContext({ repoRoot: join(here, "..", "..", ".."), config: defaultConfig });
  assert.deepEqual(run(ctx), []);
});

test("end to end: a stale row warns on stderr and the gate still exits 0", () => {
  const SHIM = "<!-- Shim: the agent manual is AGENTS.md. Edit that file, not this one. -->\n@AGENTS.md\n";
  const root = makeFixture({
    "AGENTS.md": "The diary is `docs/diary.md`.\n",
    "CLAUDE.md": SHIM,
    "GEMINI.md": SHIM,
    "docs/diary.md": diaryWith(iso(60)),
  });
  const res = spawnSync(process.execPath, [join(here, "..", "index.mjs"), root], {
    encoding: "utf8",
  });
  assert.equal(res.status, 0, `expected exit 0, got ${res.status}\n${res.stderr}`);
  assert.match(res.stderr, /housekeeping-due/);
  assert.match(res.stdout, /OK {2}docs conformance/);
});
