import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { parseEntries, run } from "../validators/banned-words.mjs";
import { cleanup, configWith, ctxFor, hasRule, makeFixture } from "./helpers.mjs";

const here = dirname(fileURLToPath(import.meta.url));

const GLOSSARY = `# Glossary

## Words this project does not use

<!-- a comment that mentions **decoy** — comments are not entries -->

- **install** — ambiguous here (nothing is installed). Use **bootstrap** for
  the run, or **stamp** for a file. Except: **the dependency sense** —
  \`dependency install\`, \`npm install\`.
- **strategic design** — ambiguous. Use **context map**.

## Another section

- **install** here is prose, not an entry.
`;

test("the section's entries parse: term, replacements, carve-out phrases", () => {
  const entries = parseEntries(GLOSSARY.split("## Words this project does not use")[1].split("## Another")[0]);
  assert.deepEqual(entries, [
    { term: "install", replacements: ["bootstrap", "stamp"], guidance: "ambiguous here (nothing is installed). Use bootstrap for the run, or stamp for a file.", allowed: ["dependency install", "npm install"] },
    { term: "strategic design", replacements: ["context map"], guidance: "ambiguous. Use context map.", allowed: [] },
  ]);
});

test("an entry with no bold replacement still says what the glossary says", () => {
  const ctx = ctxFor({
    "docs/domain-glossary.md": "# G\n\n## Words this project does not use\n\n- **config** — ambiguous on its own. Say which.\n",
    "AGENTS.md": "# Manual\n\nEdit the config.\n",
  });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.match(out[0].message, /the glossary says: ambiguous on its own\. Say which\./);
  cleanup(ctx);
});

test("the line reported is the real line, below a fenced block too", () => {
  const ctx = ctxFor({
    "docs/domain-glossary.md": GLOSSARY,
    "AGENTS.md": "# Manual\n\n```sh\nnpm install\necho hi\n```\n\nThen install the kit.\n",
  });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].line, 8);
  cleanup(ctx);
});

test("a multi-word term split across a line break is a use, reported on its first line", () => {
  const ctx = ctxFor({
    "docs/domain-glossary.md": GLOSSARY,
    "AGENTS.md": "# Manual\n\nWe did some strategic\ndesign here.\n",
  });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].line, 3);
  assert.match(out[0].message, /"strategic design"/);
  cleanup(ctx);
});

test("the banned section may be the last section of the glossary — no heading after it", () => {
  const ctx = ctxFor({
    "docs/domain-glossary.md": "# G\n\n## Terms\n\n- **kit** — this.\n\n## Words this project does not use\n\n- **install** — no. Use **bootstrap**.\n",
    "AGENTS.md": "# Manual\n\ninstall it\n",
  });
  assert.equal(run(ctx).length, 1);
  cleanup(ctx);
});

test("a deeper heading inside the section does not end it; a same-level one does", () => {
  const ctx = ctxFor({
    "docs/domain-glossary.md": "# G\n\n## Words this project does not use\n\n### Nouns\n\n- **install** — no. Use **bootstrap**.\n\n## Later\n\n- **kit** — not banned.\n",
    "AGENTS.md": "# Manual\n\ninstall the kit\n",
  });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.match(out[0].message, /"install"/);
  cleanup(ctx);
});

test("a consumer whose constitution lives elsewhere still has its shared articles excluded", () => {
  const ctx = ctxFor(
    {
      "docs/domain-glossary.md": GLOSSARY,
      "AGENTS.md": "# Manual\n",
      ".claude/constitution/shared-invariants.md": "install — verbatim from the kit\n",
      ".claude/constitution/local-engineering.md": "install here\n",
    },
    configWith({ constitutionDir: ".claude/constitution" }),
  );
  assert.deepEqual(run(ctx).map((f) => f.file), [".claude/constitution/local-engineering.md"]);
  cleanup(ctx);
});

test("end to end: the gate reports a banned word on stderr and still exits 0 — the validator is registered", () => {
  const SHIM = "<!-- Shim: the agent manual is AGENTS.md. Edit that file, not this one. -->\n@AGENTS.md\n";
  const root = makeFixture({
    "AGENTS.md": "# Manual\n\nBootstrap asks before installing it.\n",
    "CLAUDE.md": SHIM,
    "GEMINI.md": SHIM,
    "docs/domain-glossary.md": GLOSSARY,
  });
  const res = spawnSync(process.execPath, [join(here, "..", "index.mjs"), root], { encoding: "utf8" });
  assert.equal(res.status, 0, `expected exit 0, got ${res.status}\n${res.stderr}`);
  assert.match(res.stderr, /banned-word/);
  assert.match(res.stdout, /OK {2}docs conformance/);
});

test("a banned word in the manual warns, naming the word, the line and the replacement", () => {
  const ctx = ctxFor({
    "docs/domain-glossary.md": GLOSSARY,
    "AGENTS.md": "# Manual\n\nBootstrap asks before installing it.\n",
  });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.ok(hasRule(out, "banned-word"));
  assert.equal(out[0].severity, "warning");
  assert.equal(out[0].file, "AGENTS.md");
  assert.equal(out[0].line, 3);
  assert.match(out[0].message, /"installing"/);
  assert.match(out[0].message, /"bootstrap" or "stamp"/);
  cleanup(ctx);
});

test("a carve-out phrase is silent; the same word outside it still warns", () => {
  const ctx = ctxFor({
    "docs/domain-glossary.md": GLOSSARY,
    "AGENTS.md": "# Manual\n\nRun a dependency install first.\nThen npm install again.\nThen install the kit.\n",
  });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.equal(out[0].line, 5);
  cleanup(ctx);
});

test("a multi-word term is matched as a phrase, case-insensitively", () => {
  const ctx = ctxFor({
    "docs/domain-glossary.md": GLOSSARY,
    "AGENTS.md": "# Manual\n\nWe did Strategic Design here, and strategic thinking there.\n",
  });
  const out = run(ctx);
  assert.equal(out.length, 1);
  assert.match(out[0].message, /"Strategic Design"/);
  cleanup(ctx);
});

test("a glossary with no banned section, or no glossary, is silent", () => {
  const a = ctxFor({ "docs/domain-glossary.md": "# Glossary\n\n## Terms\n\n- **kit** — this.\n", "AGENTS.md": "install everything\n" });
  assert.deepEqual(run(a), []);
  cleanup(a);
  const b = ctxFor({ "AGENTS.md": "install everything\n" });
  assert.deepEqual(run(b), []);
  cleanup(b);
});

test("quoted material is silent — fenced blocks and code spans", () => {
  const ctx = ctxFor({
    "docs/domain-glossary.md": GLOSSARY,
    "AGENTS.md": "# Manual\n\n```sh\nnpm install && install-thing\n```\n\nRun `install-thing` then `sh install.sh`.\n",
  });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});

test("the articles and every skill file are scanned; the shared articles are not", () => {
  const ctx = ctxFor({
    "docs/domain-glossary.md": GLOSSARY,
    "AGENTS.md": "# Manual\n",
    "constitution/local-engineering.md": "install here\n",
    "constitution/shared-invariants.md": "install there — verbatim from the kit\n",
    ".agents/skills/tdd/SKILL.md": "# tdd\n\ninstall\n",
    ".agents/skills/tdd/SIDECAR.md": "installed\n",
    ".agents/skills/LICENSE-x.md": "install — not a skill directory\n",
  });
  const files = run(ctx).map((f) => f.file).sort();
  assert.deepEqual(files, [".agents/skills/tdd/SIDECAR.md", ".agents/skills/tdd/SKILL.md", "constitution/local-engineering.md"]);
  cleanup(ctx);
});

test("a substring is not a use — 'installation' is a different word, 'reinstall' too", () => {
  const ctx = ctxFor({
    "docs/domain-glossary.md": GLOSSARY,
    "AGENTS.md": "# Manual\n\nThe installation and a reinstall.\n",
  });
  assert.deepEqual(run(ctx), []);
  cleanup(ctx);
});
