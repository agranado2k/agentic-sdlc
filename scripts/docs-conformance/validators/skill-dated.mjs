// Dated kit evidence in a shipped skill body. A SKILL.md is copied verbatim
// into every consumer project, where an agent obeys it as standing
// instructions — so "the kit's retro of 2026-10-07: 114 of 171 raises" or
// "amended 2026-10-01, #385" reads, downstream, as the consumer's own numbers
// and history. Dated evidence belongs in the diary and the decision records;
// the skill keeps the rule and, at most, the record's name (#678).
//
// The policy is data in config.mjs's `skillDated` block: the patterns (POSIX
// EREs, the same text both engines read) and the known exceptions, one
// `<skill>|<token>` each — the skill by name, so an exception holds at
// whichever home a project keeps its skills — that a sweep removes. The skills directory is
// `claudeMdRefs.skillsDir`, its one home; like the other skill-body scanners
// this one enumerates every skill home (skillHomes), once per skill name, the
// configured home first. Each `<home>/<skill>/SKILL.md` is read with its
// fenced blocks stripped — a
// fenced command line's date is an example, not evidence — and each distinct
// token a pattern matches is one VIOLATION. Supporting files beside a
// SKILL.md are not its body and are not read. The POSIX twin in
// scripts/check.sh reads the same block by text and reports the same rule.

import { DEFAULT_SKILLS_DIR, skillHomes, stripFences } from "./claude-md-refs.mjs";

export const id = "skill-dated";

export function run(ctx) {
  const cfg = ctx.config.skillDated;
  if (!cfg) return [];
  const known = new Set(cfg.knownExceptions ?? []);
  const out = [];
  const seen = new Set();
  const files = [];
  for (const home of skillHomes(ctx.config.claudeMdRefs?.skillsDir ?? DEFAULT_SKILLS_DIR)) {
    for (const skill of ctx.list(home)) {
      const file = `${home}/${skill}/SKILL.md`;
      if (seen.has(skill) || ctx.kind(file) !== "file") continue;
      seen.add(skill);
      files.push({ skill, file });
    }
  }
  for (const { skill, file } of files) {
    const body = stripFences(ctx.read(file) ?? "");
    const tokens = new Set();
    for (const pattern of cfg.patterns ?? []) {
      for (const m of body.matchAll(new RegExp(pattern, "g"))) tokens.add(m[0]);
    }
    for (const token of [...tokens].sort()) {
      if (known.has(`${skill}|${token}`)) continue;
      out.push({
        validator: id,
        file,
        rule: "skill-dated-evidence",
        message: `carries dated kit evidence "${token}" — a consumer reads the kit's dates and history as its own`,
        hint: "Keep the rule and drop the evidence: the dates, counts and amendments belong in the diary or a decision record, which the skill may name (the kit's ADR-NNNN).",
      });
    }
  }
  return out;
}
