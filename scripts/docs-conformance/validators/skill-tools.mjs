// Declared tools: a spawned subagent may only ever narrow what its spawner
// may do. Three rules, one validator, because they read the same two
// declarations:
//
//   skill-allowed-tools-missing  a SKILL.md whose frontmatter declares no
//                                `allowed-tools` — nothing states what the
//                                skill may do without reading every step.
//   agent-type-tools-missing     an agent type with no `tools:` line in its
//                                frontmatter — it inherits every tool.
//   spawn-widens-tools           a skill that names a spawn type whose
//                                `tools:` holds a tool absent from the
//                                skill's own `allowed-tools`.
//
// A SPAWN TYPE is a code span naming an agent type followed by the words
// "agent type" — "the `reviewer` agent type" — in any top-level Markdown
// file of the skill's directory, fenced blocks stripped, matched against the
// names of the types found. A spawn that names no type inherits the
// session's, which is within the skill's powers already. A skill with no
// `allowed-tools` is the first rule's finding alone, and a type with no
// `tools:` line the second's: neither is also read as a widening.
//
// A tool list is the frontmatter value — comma- or space-separated, a flow
// list `[A, B]`, or a block list of `- A` lines — each entry kept as written,
// its parenthesised scope included. An empty value declares nothing. A bare
// name in allowed-tools covers its tool at every scope; a scoped entry
// (`Bash(git diff:*)`) covers only the same entry, never the unscoped tool,
// so a skill allowed one git command cannot spawn a type holding all of Bash.
//
// The policy is data in config.mjs's `skillTools` block: the directories the
// agent types live in (`*` a single path segment), and the severity of the
// first rule, "warning" while a project's skills are still being swept — then
// one advisory names every such skill — or "violation", one finding per
// skill. The other two always fail. The POSIX twin in scripts/check.sh reads the same
// block by text and reports the same rules.

import { DEFAULT_SKILLS_DIR, skillHomes, stripFences } from "./claude-md-refs.mjs";

export const id = "skill-tools";

const ALLOWED_HINT =
  "Declare `allowed-tools:` in the SKILL.md frontmatter: the tools the skill's own session uses, every tool of every agent type it spawns among them.";

const DEFAULT_TYPE_DIRS = ["adapters/*/agents", ".claude/agents"];

/** The frontmatter's lines, or null when the file opens with none. */
function frontmatter(raw) {
  const lines = raw.split("\n");
  if (!/^---[ \t\r]*$/.test(lines[0] ?? "")) return null;
  const out = [];
  for (const line of lines.slice(1)) {
    if (/^---[ \t\r]*$/.test(line)) return out;
    out.push(line);
  }
  return out;
}

/** The tools a frontmatter key declares, in order; null when the key is absent or empty. */
export function declaredTools(raw, key) {
  const fm = frontmatter(raw);
  if (!fm) return null;
  const at = fm.findIndex((l) => l.startsWith(`${key}:`));
  if (at < 0) return null;
  const parts = [fm[at].slice(key.length + 1)];
  for (const line of fm.slice(at + 1)) {
    const item = line.match(/^[ \t]+-[ \t]*(.*)$/);
    if (!item) break;
    parts.push(item[1]);
  }
  const tools = parts.join(" ").match(/[^\s,[\]"'()]+(?:\([^)]*\))?/g) ?? [];
  return tools.length ? [...new Set(tools)] : null;
}

/** Whether allowed-tools covers one tool a type declares: the same entry, or its bare name. */
function covers(allowed, tool) {
  return allowed.includes(tool) || allowed.includes(tool.replace(/\(.*$/, ""));
}

/** The frontmatter `name:`, else the file's base name. */
function typeName(raw, file) {
  const named = (frontmatter(raw) ?? []).map((l) => l.match(/^name:[ \t]*["']?([^"'\s]+)/)).find(Boolean);
  return named ? named[1] : file.replace(/^.*\//, "").replace(/\.md$/, "");
}

/** Expand a directory pattern whose `*` segments each stand for one directory. */
function expandDirs(ctx, pattern) {
  let dirs = [""];
  for (const seg of pattern.split("/")) {
    const next = [];
    for (const d of dirs) {
      const base = d ? `${d}/` : "";
      if (seg === "*") {
        for (const n of ctx.list(d || ".")) if (ctx.kind(`${base}${n}`) === "directory") next.push(`${base}${n}`);
      } else if (ctx.kind(`${base}${seg}`) === "directory") next.push(`${base}${seg}`);
    }
    dirs = next;
  }
  return dirs;
}

export function run(ctx) {
  const cfg = ctx.config.skillTools;
  if (!cfg) return [];
  const out = [];

  // The agent types: every `*.md` in every configured directory.
  const types = new Map(); // name -> [{ file, tools }]
  for (const pattern of cfg.agentTypeDirs ?? DEFAULT_TYPE_DIRS) {
    for (const dir of expandDirs(ctx, pattern)) {
      for (const f of ctx.list(dir, ".md")) {
        const file = `${dir}/${f}`;
        if (ctx.kind(file) !== "file") continue;
        const raw = ctx.read(file) ?? "";
        const name = typeName(raw, file);
        const tools = declaredTools(raw, "tools");
        if (!types.has(name)) types.set(name, []);
        types.get(name).push({ file, tools });
        if (tools) continue;
        out.push({
          validator: id,
          file,
          rule: "agent-type-tools-missing",
          message: `${name} has no tools line, so it inherits every tool`,
          hint: "Give the type a `tools:` line in its frontmatter naming the tools it needs, and nothing more.",
        });
      }
    }
  }

  // The skills: every home, once per skill name, the configured home first.
  const skillsDir = ctx.config.claudeMdRefs?.skillsDir ?? DEFAULT_SKILLS_DIR;
  const undeclared = [];
  const seen = new Set();
  for (const home of skillHomes(skillsDir)) {
    for (const skill of ctx.list(home)) {
      const file = `${home}/${skill}/SKILL.md`;
      if (seen.has(skill) || ctx.kind(file) !== "file") continue;
      seen.add(skill);
      const allowed = declaredTools(ctx.read(file) ?? "", "allowed-tools");
      if (!allowed) {
        undeclared.push({ skill, file });
        continue;
      }
      for (const doc of ctx.list(`${home}/${skill}`, ".md")) {
        const docFile = `${home}/${skill}/${doc}`;
        if (ctx.kind(docFile) !== "file") continue;
        const reported = new Set();
        const body = stripFences(ctx.read(docFile) ?? "");
        for (const m of body.matchAll(/`([A-Za-z0-9_-]+)`\s+agent type/g)) {
          for (const { tools } of types.get(m[1]) ?? []) {
            const outside = (tools ?? []).filter((t) => !covers(allowed, t));
            if (!outside.length) continue;
            const message = `${skill} spawns ${m[1]}, whose tools (${outside.join(", ")}) are outside its allowed-tools`;
            if (reported.has(message)) continue;
            reported.add(message);
            out.push({
              validator: id,
              file: docFile,
              rule: "spawn-widens-tools",
              message,
              hint: "Spawn a type whose tools are within the skill's allowed-tools, or widen the skill's allowed-tools in the open — a spawned subagent may only narrow what its spawner may do.",
            });
          }
        }
      }
    }
  }

  // A violation names each skill; an advisory is one line naming them all,
  // so a project mid-sweep reads one line per run, not one per skill.
  if (cfg.missingAllowedTools === "warning") {
    if (undeclared.length)
      out.push({
        validator: id,
        severity: "warning",
        file: skillsDir,
        rule: "skill-allowed-tools-missing",
        message: `no allowed-tools in the frontmatter of ${undeclared.map((u) => u.skill).join(", ")}, so nothing states the tools they use`,
        hint: ALLOWED_HINT,
      });
  } else {
    for (const { skill, file } of undeclared)
      out.push({
        validator: id,
        file,
        rule: "skill-allowed-tools-missing",
        message: `${skill} has no allowed-tools in its frontmatter, so nothing states the tools it uses`,
        hint: ALLOWED_HINT,
      });
  }
  return out;
}
