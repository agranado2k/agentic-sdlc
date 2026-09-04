import assert from "node:assert/strict";
import { test } from "node:test";
import { parseEntries, run } from "../validators/banned-words.mjs";
import { cleanup, ctxFor, hasRule } from "./helpers.mjs";

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
    { term: "install", replacements: ["bootstrap", "stamp"], allowed: ["dependency install", "npm install"] },
    { term: "strategic design", replacements: ["context map"], allowed: [] },
  ]);
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
