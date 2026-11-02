#!/usr/bin/env node
// docs-conformance entry point. Runs every validator against the repo and
// exits non-zero on any violation.
//
// It is invoked by `scripts/check.sh` whenever node is available, and directly
// by the kit's own CI. Optional arg: a repo root (defaults to the repo this
// script lives in), which is how CI points it at a checkout and how the demo
// points it at a throwaway project.

import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { makeContext } from "./context.mjs";
import { runAll } from "./runner.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = process.argv[2] ?? join(here, "..", "..");

const CONFIG = "scripts/docs-conformance/config.mjs";
const VOCABULARY = "scripts/docs-conformance/local-vocabulary.mjs";

/**
 * The gate config that judges. With POLICY_BASE unset, this tree's own
 * config.mjs, as a local push reads it. With POLICY_BASE naming a ref
 * (the kit's ADR-0039), the base's copy, read through the policy reader beside
 * the harness (scripts/policy.sh): the config module and its local-vocabulary
 * sibling are both copied to the reader's directory for that commit, so the
 * copy's import of its sibling resolves there — and a vocabulary missing at the
 * base is an empty one, as it is today. Any other answer the reader cannot
 * give fails CLOSED: its `fail-closed <reason> <path>` line, no validator run,
 * exit 1. The working tree's config is never a fallback.
 */
async function loadConfig() {
  const base = process.env.POLICY_BASE;
  if (!base) return (await import("./config.mjs")).default;

  const reader = join(here, "..", "policy.sh");
  const read = (path) => {
    const r = spawnSync("sh", [reader, "read", path, "--base", base], { cwd: repoRoot, encoding: "utf8" });
    return { status: r.status, out: (r.stdout ?? "").trim(), err: (r.stderr ?? "").trim() };
  };
  const failClosed = (answer, path) => {
    if (answer.out.startsWith("fail-closed ")) console.error(answer.out);
    else {
      if (answer.err) console.error(answer.err);
      console.error(`the policy reader gave no answer for ${path} at POLICY_BASE=${base} (exit ${answer.status}).`);
    }
    console.error(`FAIL  the gate config at POLICY_BASE=${base} cannot be read — failing closed, no validator ran.`);
    process.exit(1);
  };

  const config = read(CONFIG);
  if (config.status !== 0) failClosed(config, CONFIG);
  const vocabulary = read(VOCABULARY);
  if (vocabulary.status !== 0 && vocabulary.out !== `fail-closed missing ${VOCABULARY}`) failClosed(vocabulary, VOCABULARY);
  return (await import(pathToFileURL(config.out).href)).default;
}

const config = await loadConfig();

const ctx = makeContext({ repoRoot, config });
const findings = runAll(ctx);

// Two severities, one boundary: a WARNING is printed and never moves the exit
// code, because the states it names (a declined skill, a recorded fork) are
// legal ones the project may hold deliberately. Everything else is a
// violation and fails the gate exactly as before.
const warnings = findings.filter((f) => f.severity === "warning");
const violations = findings.filter((f) => f.severity !== "warning");

if (warnings.length > 0) {
  console.error("WARN  docs conformance: advisories (gate stays green)\n");
  for (const w of warnings) {
    console.error(`  [${w.validator}] ! ${w.file} [${w.rule}] — ${w.message}`);
    console.error(`      -> ${w.hint}`);
  }
  console.error("");
}

if (violations.length === 0) {
  console.log("OK  docs conformance: all checks passed");
  process.exit(0);
}

// Group by validator for a readable report.
const byValidator = new Map();
for (const v of violations) {
  if (!byValidator.has(v.validator)) byValidator.set(v.validator, []);
  byValidator.get(v.validator).push(v);
}

console.error("FAIL  docs conformance: violations found\n");
for (const [validator, items] of byValidator) {
  console.error(`  [${validator}] (${items.length})`);
  for (const v of items) {
    console.error(`    x ${v.file} [${v.rule}] — ${v.message}`);
    console.error(`      -> ${v.hint}`);
  }
  console.error("");
}
console.error(`${violations.length} violation(s) across ${byValidator.size} validator(s).`);
process.exit(1);
