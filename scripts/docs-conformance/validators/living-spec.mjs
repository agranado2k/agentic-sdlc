// The LIVING SPEC, held to the suite (ADR-0012 clauses 7 and 10). Each area
// keeps its current requirements in `docs/specs/<area>.md`, one per line that
// opens with its id `R<n>.`; outside the file a requirement is cited as
// `<area>/R<n>`. Every such requirement must be NAMED by at least one file the
// policy's test globs match — in a test's name or a comment beside it. A
// requirement nothing names is a claim (shared invariant §8), and this rule is
// a VIOLATION: the living spec drifting from the suite is the failure it exists
// to stop, not a legal state a project may hold.
//
// Honest limitation, stated where the rule lives: a name is not an assertion.
// A test can cite `<area>/R3` and check nothing about it; the review's
// behavior axis and the human reading it remain the check on that.
//
// VACUOUS without a living spec — no directory, an empty one, or files with no
// requirement line yet all pass, so a project that never adopts the mechanism
// never meets it.
//
// TWO ENGINES. scripts/check.sh carries this rule's POSIX twin for a project
// without node, and it reads the same two policy values from config.mjs BY
// TEXT — which is why `testGlobs` must stay a literal list, one quoted glob
// per line. The grammar below (area, requirement line, cited name, glob) is
// spelled identically in both; tests/docs-demo.sh drives the twin red and
// green on a bootstrapped project.

import { spawnSync } from "node:child_process";
import { readdirSync, realpathSync } from "node:fs";
import { join } from "node:path";

export const id = "living-spec";

const AREA_RE = /^[a-z][a-z0-9-]*$/;
const REQUIREMENT_RE = /^R([0-9]+)\.(?:[ \t\r]|$)/;
const FENCE_RE = /^[ \t]*(```|~~~)/;
// Leftmost-longest is the same answer as JS's greedy match for this pattern,
// so `subprocess/R1` is one name (not `process/R1`) and `process/R10` is never
// `process/R1` — in both engines.
const CITED_RE = /[a-z][a-z0-9-]*\/R[0-9]+/g;

/**
 * A glob as a shell `case` pattern reads it: `*` is any run of characters,
 * `/` included, `?` exactly one, everything else literal, anchored at both
 * ends. Brackets are literal here and a class in the POSIX twin — the shipped
 * globs use neither, and the config says so.
 */
export function globToRegExp(glob) {
  const body = glob
    .split("")
    .map((c) => (c === "*" ? ".*" : c === "?" ? "." : c.replace(/[.+^${}()|[\]\\]/g, "\\$&")))
    .join("");
  return new RegExp(`^${body}$`);
}

/** The requirement ids of one spec body, fences skipped, in file order, once each. */
function requirementIds(raw) {
  const ids = [];
  let fence = false;
  for (const line of raw.split("\n")) {
    if (FENCE_RE.test(line)) {
      fence = !fence;
      continue;
    }
    if (fence) continue;
    const m = REQUIREMENT_RE.exec(line);
    if (m && !ids.includes(`R${m[1]}`)) ids.push(`R${m[1]}`);
  }
  return ids;
}

/**
 * The repo's reviewed surface, repo-relative — the same set scripts/check.sh
 * scans: git's tracked plus untracked-but-not-ignored files when the root is a
 * git work tree's top, which keeps ignored output and nested worktrees out;
 * otherwise (a fixture tree) a walk that skips `.git` and `node_modules`.
 */
function surface(root) {
  const top = spawnSync("git", ["-C", root, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
  if (top.status === 0 && sameDir(top.stdout.trim(), root)) {
    const ls = spawnSync("git", ["-C", root, "ls-files", "-co", "--exclude-standard", "-z"], {
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    });
    if (ls.status === 0) return ls.stdout.split("\0").filter(Boolean);
  }
  const out = [];
  const walk = (rel) => {
    for (const e of readdirSync(join(root, rel), { withFileTypes: true })) {
      const p = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory()) {
        if (e.name !== ".git" && e.name !== "node_modules") walk(p);
      } else if (e.isFile()) out.push(p);
    }
  };
  walk("");
  return out;
}

function sameDir(a, b) {
  try {
    return realpathSync(a) === realpathSync(b);
  } catch {
    return false;
  }
}

export function run(ctx) {
  const cfg = ctx.config.livingSpec ?? {};
  const dir = cfg.specsDir ?? "docs/specs";
  const globs = (cfg.testGlobs ?? []).map(globToRegExp);

  const findings = [];
  const specs = [];
  for (const name of ctx.list(dir, ".md")) {
    const file = `${dir}/${name}`;
    if (ctx.kind(file) !== "file") continue;
    const ids = requirementIds(ctx.read(file) ?? "");
    if (ids.length === 0) continue;
    const area = name.slice(0, -".md".length);
    if (!AREA_RE.test(area)) {
      findings.push({
        validator: id,
        file,
        rule: "living-spec-area-invalid",
        message: `holds requirements, but "${area}" is not an area name — one lowercase token, [a-z][a-z0-9-]*`,
        hint: "Rename the file to its area (docs/specs/<area>.md); its requirements are cited as <area>/R<n>, so an area that cannot be cited cannot be held to a test.",
      });
      continue;
    }
    specs.push({ file, area, ids });
  }
  if (specs.length === 0) return findings;

  const cited = new Set();
  if (globs.length > 0) {
    for (const rel of surface(ctx.repoRoot)) {
      if (!globs.some((re) => re.test(rel)) || ctx.kind(rel) !== "file") continue;
      for (const name of (ctx.read(rel) ?? "").match(CITED_RE) ?? []) cited.add(name);
    }
  }

  for (const { file, area, ids } of specs) {
    for (const rid of ids) {
      const name = `${area}/${rid}`;
      if (cited.has(name)) continue;
      findings.push({
        validator: id,
        file,
        rule: "living-spec-untested",
        message: `${name} is named by no test`,
        hint: `Name \`${name}\` in a test (its name, or a comment beside it) in a file livingSpec.testGlobs in scripts/docs-conformance/config.mjs matches, or retire the requirement with a REMOVED delta. A living requirement no test names is a claim (shared invariant §8).`,
      });
    }
  }
  return findings;
}
