// Dated kit evidence in a shipped skill body. A SKILL.md is copied verbatim
// into every consumer project, where an agent obeys it as standing
// instructions — so "the kit's retro of 2026-10-07: 114 of 171 raises" or
// "amended 2026-10-01, #385" reads, downstream, as the consumer's own numbers
// and history. Dated evidence belongs in the diary and the decision records;
// the skill keeps the rule and, at most, the record's name (#678).
//
// The policy is data in config.mjs's `skillDated` block: the skills
// directory, the patterns (POSIX EREs, the same text both engines read), and
// the known exceptions, one `<file>|<token>` each, that a sweep removes. Every
// `<skillsDir>/<skill>/SKILL.md` is read with its fenced blocks stripped — a
// fenced command line's date is an example, not evidence — and each distinct
// token a pattern matches is one VIOLATION. Supporting files beside a
// SKILL.md are not its body and are not read. The POSIX twin in
// scripts/check.sh reads the same block by text and reports the same rule.

import { stripFences } from "./claude-md-refs.mjs";

export const id = "skill-dated";

export function run(ctx) {
  const cfg = ctx.config.skillDated;
  if (!cfg) return [];
  const known = new Set(cfg.knownExceptions ?? []);
  const out = [];
  for (const skill of ctx.list(cfg.skillsDir)) {
    const file = `${cfg.skillsDir}/${skill}/SKILL.md`;
    if (ctx.kind(file) !== "file") continue;
    const body = stripFences(ctx.read(file) ?? "");
    const tokens = new Set();
    for (const pattern of cfg.patterns ?? []) {
      for (const m of body.matchAll(new RegExp(pattern, "g"))) tokens.add(m[0]);
    }
    for (const token of [...tokens].sort()) {
      if (known.has(`${file}|${token}`)) continue;
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
