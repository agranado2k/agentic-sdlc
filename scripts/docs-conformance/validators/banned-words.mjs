// The glossary's OTHER half, refereed. A ubiquitous language names one word
// per concept and, just as importantly, names the words it does NOT use — the
// ones that are ambiguous in this project. The glossary template ships that
// section ("Words this project does not use"); nothing read it. This
// validator does: each entry's banned term is searched for in the manual
// layer and the skills, and every use is a WARNING naming the word and the
// replacement the entry prescribes.
//
// An entry may carve out a legitimate sense with an `Except:` clause whose
// code spans are the phrases in which the word is fine — `dependency
// install` for a word banned in its bootstrap sense. A use inside one of
// those phrases is silent. Quoted material is silent too: fenced blocks and
// code spans are commands and paths, not prose.
//
// Warnings, never violations: a banned word is a wording debt, and the
// glossary is the consumer's own policy — an entry added on Monday must not
// break Tuesday's hotfix push. A glossary with no such section, or no entries
// in it, produces nothing.

import { DEFAULT_SKILLS_DIR, skillHomes, stripFences } from "./claude-md-refs.mjs";

export const id = "banned-words";

// The same defaults the reference validator applies when the policy is
// silent; read from config.claudeMdRefs first, as every validator does.
const DEFAULT_ROOT_MANUAL = "AGENTS.md";
const DEFAULT_CONSTITUTION_DIR = "constitution";

export const DEFAULT_GLOSSARY = "docs/domain-glossary.md";
export const SECTION_HEADING = "Words this project does not use";
// The shared articles are copied verbatim from the kit: a consumer's banned
// list cannot be a rule about prose the consumer may not edit.
export const DEFAULT_EXCLUDE = ["constitution/shared-invariants.md", "constitution/shared-code-craft.md"];

const SUFFIX = "(?:s|es|ed|ing)?";

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** The section's text: from its heading to the next heading of the same or higher level. */
function bannedSection(raw) {
  const lines = stripFences(raw).split("\n");
  let start = -1;
  let level = 0;
  for (let i = 0; i < lines.length; i++) {
    const m = /^(#{1,6})\s+(.*?)\s*$/.exec(lines[i]);
    if (!m) continue;
    if (start < 0) {
      if (m[2] === SECTION_HEADING) {
        start = i + 1;
        level = m[1].length;
      }
    } else if (m[1].length <= level) {
      return lines.slice(start, i).join("\n");
    }
  }
  return start < 0 ? null : lines.slice(start).join("\n");
}

/**
 * Parse the section's entries. One entry is a list item starting with a bold
 * term: `- **term** — why. Use **x** or **y**. Except: **sense** — `phrase`,
 * `phrase`.` Continuation lines belong to the item above them.
 */
export function parseEntries(sectionText) {
  const items = [];
  for (const line of sectionText.replace(/<!--[\s\S]*?-->/g, "").split("\n")) {
    if (/^\s*[-*]\s+\*\*/.test(line)) items.push(line.replace(/^\s*[-*]\s+/, ""));
    else if (items.length && line.trim()) items[items.length - 1] += " " + line.trim();
  }
  const entries = [];
  for (const item of items) {
    const term = /^\*\*(.+?)\*\*/.exec(item)?.[1]?.trim();
    if (!term || /^<.*>$/.test(term)) continue; // the template's placeholder entry
    const exceptAt = item.indexOf("Except:");
    const body = exceptAt >= 0 ? item.slice(0, exceptAt) : item;
    const except = exceptAt >= 0 ? item.slice(exceptAt) : "";
    const useAt = body.search(/\bUse\b/);
    const replacements = useAt >= 0 ? [...body.slice(useAt).matchAll(/\*\*(.+?)\*\*/g)].map((m) => m[1]) : [];
    const allowed = [...except.matchAll(/`([^`]+)`/g)].map((m) => m[1]);
    entries.push({ term, replacements, allowed });
  }
  return entries;
}

/** Prose only: fences and code spans removed, line structure kept. */
function prose(raw) {
  return stripFences(raw).replace(/`[^`\n]*`/g, (m) => " ".repeat(m.length));
}

function scanTargets(ctx) {
  const refs = ctx.config.claudeMdRefs ?? {};
  const cfg = ctx.config.bannedWords ?? {};
  const rootManual = refs.rootManual ?? DEFAULT_ROOT_MANUAL;
  const constitutionDir = refs.constitutionDir ?? DEFAULT_CONSTITUTION_DIR;
  const skillsDir = refs.skillsDir ?? DEFAULT_SKILLS_DIR;
  const exclude = new Set(cfg.exclude ?? DEFAULT_EXCLUDE);
  const files = [rootManual];
  for (const f of ctx.list(constitutionDir, ".md")) files.push(`${constitutionDir}/${f}`);
  const seen = new Set();
  for (const home of skillHomes(skillsDir)) {
    for (const name of ctx.list(home)) {
      // A skill is a directory holding SKILL.md; a licence file or a stray
      // beside the skills is neither and is not listed into.
      if (seen.has(name) || !ctx.exists(`${home}/${name}/SKILL.md`)) continue;
      seen.add(name);
      for (const f of ctx.list(`${home}/${name}`, ".md")) files.push(`${home}/${name}/${f}`);
    }
  }
  return files.filter((f) => !exclude.has(f));
}

export function run(ctx) {
  const cfg = ctx.config.bannedWords ?? {};
  const glossary = cfg.glossary ?? DEFAULT_GLOSSARY;
  const glossaryRaw = ctx.read(glossary);
  if (glossaryRaw == null) return [];
  const section = bannedSection(glossaryRaw);
  if (section == null) return [];
  const entries = parseEntries(section);
  if (entries.length === 0) return [];

  const out = [];
  for (const file of scanTargets(ctx)) {
    const raw = ctx.read(file);
    if (raw == null) continue;
    const lines = prose(raw).split("\n");
    for (const entry of entries) {
      const termRe = new RegExp(`\\b${escapeRe(entry.term).replace(/\s+/g, "\\s+")}${SUFFIX}\\b`, "gi");
      lines.forEach((line, i) => {
        // Carved-out phrases are blanked before the word is looked for, so a
        // use inside one cannot match.
        let text = line;
        for (const phrase of entry.allowed) {
          text = text.replace(new RegExp(escapeRe(phrase).replace(/\s+/g, "\\s+"), "gi"), (m) => " ".repeat(m.length));
        }
        for (const m of text.matchAll(termRe)) {
          const use = entry.replacements.length ? ` — the glossary says use ${entry.replacements.map((r) => `"${r}"`).join(" or ")}` : "";
          out.push({
            validator: id,
            severity: "warning",
            file,
            line: i + 1,
            rule: "banned-word",
            message: `line ${i + 1} uses "${m[0]}", a word this project does not use${use}`,
            hint: `See "${SECTION_HEADING}" in ${glossary}. If this is a legitimate sense, add an \`Except:\` clause to the entry naming the phrase as a code span.`,
          });
        }
      });
    }
  }
  return out;
}
