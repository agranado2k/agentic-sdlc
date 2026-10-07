// The skill byte ceiling. Every byte of a SKILL.md is re-read by every agent
// that runs the skill (shared invariant §11), so the policy declares the most
// bytes a named skill may hold and this rule fails one that outgrows it,
// naming the file, its size and its ceiling. A VIOLATION, not an advisory: a
// ceiling that only warns is a number nobody has to respect.
//
// The ceilings are data in config.mjs's `skillCeilings` block, keyed by the
// file's repo-relative path. A skill the policy does not name has no ceiling,
// and a ceiling whose file is absent is silent — a project that declined or
// moved a skill has nothing to measure. The POSIX twin in scripts/check.sh
// reads the same block by text and reports the same rule.

export const id = "skill-ceiling";

export function run(ctx) {
  const out = [];
  for (const [file, ceiling] of Object.entries(ctx.config.skillCeilings ?? {})) {
    const size = ctx.size(file);
    if (size == null || size <= ceiling) continue;
    out.push({
      validator: id,
      file,
      rule: "skill-over-ceiling",
      message: `is ${size} bytes, over its ceiling of ${ceiling} bytes`,
      hint: "Move the parts only a worker or a rare branch needs into files the SKILL.md names, or raise the ceiling in config.mjs's skillCeilings — a visible policy diff.",
    });
  }
  return out;
}
