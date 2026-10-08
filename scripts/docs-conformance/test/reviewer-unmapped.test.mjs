import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import defaultConfig from "../config.mjs";
import { makeContext } from "../context.mjs";
import { run } from "../validators/reviewer-unmapped.mjs";
import { cleanup, ctxFor, hasRule } from "./helpers.mjs";

const here = dirname(fileURLToPath(import.meta.url));

// The agents policy file as the kit ships it: every tier line present, empty.
const policy = (line) =>
  `#!/bin/sh\nAGENT_TIER_PLANNER=''\nAGENT_TIER_IMPLEMENTER=''\n${line}\nAGENT_TIER_REVIEWER_FALLBACK=''\n`;
const cfgWith = (reviewerUnmapped) => ({ ...defaultConfig, reviewerUnmapped });
const DEFAULTS = cfgWith({});

test("an unmapped reviewer tier warns — and only warns", () => {
  const ctx = ctxFor({ "scripts/agents.config.sh": policy("AGENT_TIER_REVIEWER=''") }, DEFAULTS);
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.ok(hasRule(out, "reviewer-unmapped"));
  assert.equal(out[0].severity, "warning");
  assert.equal(out[0].file, "scripts/agents.config.sh");
  // It names the setting, the file and the cost (#655).
  assert.match(out[0].message, /AGENT_TIER_REVIEWER/);
  assert.match(out[0].hint, /author's model/);
  cleanup(ctx);
});

test("a mapped reviewer tier is silent", () => {
  const ctx = ctxFor({ "scripts/agents.config.sh": policy("AGENT_TIER_REVIEWER='some-model'  # the judge") }, DEFAULTS);
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("only the plain reviewer line counts — a domain or fallback line is not the tier", () => {
  const ctx = ctxFor(
    {
      "scripts/agents.config.sh":
        "AGENT_TIER_REVIEWER=''\nAGENT_TIER_REVIEWER_SELF_IMPLEMENTED='m1'\nAGENT_TIER_REVIEWER_FALLBACK='m2'\n",
    },
    DEFAULTS,
  );
  assert.ok(hasRule(run(ctx), "reviewer-unmapped"));
  cleanup(ctx);
});

test("the last assignment wins, as the shell reads it", () => {
  for (const [lines, fires] of [
    ["AGENT_TIER_REVIEWER='m'\nAGENT_TIER_REVIEWER=''", true],
    ["AGENT_TIER_REVIEWER=''\nAGENT_TIER_REVIEWER=\"m\"", false],
    ["# AGENT_TIER_REVIEWER='m'\nAGENT_TIER_REVIEWER=", true],
    ["AGENT_TIER_REVIEWER=m", false],
  ]) {
    const ctx = ctxFor({ "scripts/agents.config.sh": lines }, DEFAULTS);
    assert.equal(hasRule(run(ctx), "reviewer-unmapped"), fires, `lines ${JSON.stringify(lines)}`);
    cleanup(ctx);
  }
});

test("no agents policy file is silent", () => {
  const ctx = ctxFor({ "README.md": "# x\n" }, DEFAULTS);
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("the policy files are an ordered list: the first that exists is the one read", () => {
  const config = cfgWith({ policyFiles: ["scripts/agents.twin.sh", "scripts/agents.config.sh"] });
  let ctx = ctxFor(
    {
      "scripts/agents.twin.sh": policy("AGENT_TIER_REVIEWER='m'"),
      "scripts/agents.config.sh": policy("AGENT_TIER_REVIEWER=''"),
    },
    config,
  );
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
  ctx = ctxFor({ "scripts/agents.config.sh": policy("AGENT_TIER_REVIEWER=''") }, config);
  assert.ok(hasRule(run(ctx), "reviewer-unmapped"));
  cleanup(ctx);
});

// The kit's own tree, read through the real config. These two hold only where
// the kit's never-shipped twin exists: a project's tree is its own business,
// and an advisory there is the channel working, never a failing test.
const ROOT = join(here, "..", "..", "..");
const KIT_ONLY = { skip: !existsSync(join(ROOT, "scripts/agents.kit.config.sh")) && "no kit twin in this tree" };

test("the kit's own tree is silent — it maps its tiers through its never-shipped twin", KIT_ONLY, () => {
  assert.ok(!hasRule(run(makeContext({ repoRoot: ROOT, config: defaultConfig })), "reviewer-unmapped"));
});

test("and only the twin keeps it silent — read by the shipped defaults, the kit's tree fires (its shipped mapping is the empty one)", KIT_ONLY, () => {
  assert.ok(hasRule(run(makeContext({ repoRoot: ROOT, config: DEFAULTS })), "reviewer-unmapped"));
});
