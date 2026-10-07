import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { run as bannedWords } from "../validators/banned-words.mjs";
import { stripFences } from "../validators/claude-md-refs.mjs";
import * as livingSpec from "../validators/living-spec.mjs";
import { cleanup, ctxFor, makeFixture } from "./helpers.mjs";

const here = dirname(fileURLToPath(import.meta.url));

// One fence rule for every reader of a markdown line, in both engines (#571).
// A fence OPENS on a line whose first non-blank characters are three
// backticks or three tildes, and CLOSES on a line holding a run of the same
// character, at least as long as the opening run, and nothing after it but
// blanks, tabs or a carriage return; one left open runs to the end of its
// file. The shell home is scripts/requirement.lib.sh (fence_strip); the docs
// harness reads the rule through living-spec.mjs's fencedLines, and this test
// holds the two together — the patterns byte for byte, the reading line for
// line. The fixtures build every marker from these two constants, so no
// pattern is spelled here.
const B = "`".repeat(3);
const T = "~".repeat(3);
const HOME = join(here, "..", "..", "requirement.lib.sh");

function homeValue(lib, name) {
  const res = spawnSync("sh", ["-c", `. "$1" && printf '%s' "$${name}"`, "sh", lib], { encoding: "utf8" });
  assert.equal(res.status, 0, `sourcing ${lib} failed: ${res.stderr}`);
  return res.stdout;
}

function homeStrip(text) {
  const res = spawnSync("sh", ["-c", '. "$1" && fence_strip', "sh", HOME], { input: text, encoding: "utf8" });
  assert.equal(res.status, 0, `fence_strip failed: ${res.stderr}`);
  return res.stdout;
}

// The shell suite's fixture (tests/requirement-grammar.test.sh §1b), case for case.
const DOC = [
  "before `a`",
  `${B}sh`, "in backtick fence", B,
  "between",
  `  ${T}`, "in indented tilde fence", `  ${T}`,
  `\t${B}`, "in tab-indented fence", B,
  `${T}md`, B, "a backtick line inside a tilde block closes nothing", B, T,
  "after the tilde block",
  B, `${B}sh`, "a closing line with an info string closes nothing", `${B}\t\r`,
  "after a closing line ending in a tab and a carriage return",
  `${B}\`md`, B, "a shorter run closes nothing", `${B}\`\``,
  "after a longer closing run",
  `x${B}not a fence`,
  "after",
  "",
].join("\n");

test("the fence patterns are the shell home's, byte for byte", () => {
  for (const name of ["REQ_FENCE_ERE", "REQ_FENCE_CLOSE_ERE"]) {
    assert.equal(typeof livingSpec[name], "string", `living-spec.mjs exports no ${name}`);
    assert.equal(livingSpec[name], homeValue(HOME, name), `${name} diverges from scripts/requirement.lib.sh`);
  }
});

test("the comparison can go red — a home whose closing line moves diverges", () => {
  const root = makeFixture({
    "requirement.lib.sh": `${readFileSync(HOME, "utf8")}\nREQ_FENCE_CLOSE_ERE='^(${B}|${T})$'\n`,
  });
  assert.notEqual(homeValue(join(root, "requirement.lib.sh"), "REQ_FENCE_CLOSE_ERE"), livingSpec.REQ_FENCE_CLOSE_ERE);
});

test("stripFences keeps exactly the lines the shell home's fence_strip keeps", () => {
  const kept = "before `a`\nbetween\nafter the tilde block\nafter a closing line ending in a tab and a carriage return\n" +
    `after a longer closing run\nx${B}not a fence\nafter\n`;
  assert.equal(homeStrip(DOC), kept);
  assert.equal(stripFences(DOC), kept);
});

test("fencedLines marks the fence lines and everything between them", () => {
  const lines = [`${T}md`, B, "quoted", B, T, "prose", `${B}`, "open to the end"];
  assert.deepEqual(livingSpec.fencedLines(lines), [true, true, true, true, true, false, true, true]);
});

// The full engine's code-span readers (claude-md-refs and the four validators
// on stripFences) — each case one their old backreference read differently.
test("stripFences: a fence left open hides the rest of its file", () => {
  assert.equal(stripFences(`prose\n${B}sh\n\`scripts/ghost.sh\`\n`), "prose");
});

test("stripFences: a longer opening run is not closed by a shorter one", () => {
  assert.equal(stripFences(`${B}\`md\n${B}\n\`scripts/ghost.sh\`\n${B}\n${B}\`\nprose\n`), "prose\n");
});

test("stripFences: a closing line ending in a carriage return closes", () => {
  assert.equal(stripFences(`${B}sh\r\n\`scripts/ghost.sh\`\r\n${B}\r\nprose\r\n`), "prose\r\n");
});

// banned-words' leftover pass — each case one its old toggle read differently.
const GLOSSARY = "# G\n\n## Words this project does not use\n\n- **install** — ambiguous. Use **bootstrap**.\n";
const banned = (manual) => {
  const ctx = ctxFor({ "docs/domain-glossary.md": GLOSSARY, "AGENTS.md": manual });
  const out = bannedWords(ctx).filter((f) => f.file === "AGENTS.md");
  cleanup(ctx);
  return out.map((f) => f.line);
};

test("banned-words: a backtick line inside a tilde block closes nothing", () => {
  assert.deepEqual(banned(`# M\n\n${T}md\n${B}\ninstall it\n${B}\n${T}\n\nThen install.\n`), [9]);
});

test("banned-words: a line opening with a form feed or a vertical tab is no fence", () => {
  assert.deepEqual(banned(`# M\n\n\f${B}\ninstall it\n\v${B}\n`), [4]);
});

test("banned-words: a closing line with an info string closes nothing", () => {
  assert.deepEqual(banned(`# M\n\n${B}\n${B}sh\ninstall it\n${B}\n\nThen install.\n`), [8]);
});

// The living spec's reader — the case the old toggle read differently.
test("living-spec: a tilde block quoting a backtick fence hides every requirement in it", () => {
  const spec = `# Billing\n\n${T}md\nR1. quoted\n${B}\nR2. still quoted\n${B}\n${T}\n`;
  const ctx = ctxFor({ "docs/specs/billing.md": spec });
  assert.deepEqual(livingSpec.run(ctx), []);
  cleanup(ctx);
});
