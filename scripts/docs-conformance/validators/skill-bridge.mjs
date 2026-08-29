// The symlink bridge's tripwire. Since 0.14.0 the skills live canonically at
// .agents/skills/ and .claude/skills/<name> is a committed relative symlink —
// the per-skill-entry shape the one harness that reads only that address
// documents. A checkout with core.symlinks=false (Git for Windows outside
// developer mode) MATERIALIZES each symlink as a regular text file holding
// the link target, and that harness then goes blind to every skill with no
// error anywhere. This validator names that exact signature.
//
// Findings are WARNINGS: the tree is not wrong, the CHECKOUT is, and the fix
// is per-clone (`git config core.symlinks true` and re-checkout, or work from
// WSL — the kit's gates already require POSIX sh). A real directory at the
// old address is silent: a pre-0.14.0 project staying put is a legal
// permanent state, and this rule names one failure shape, not a layout
// police. Promotion to a violation has no path here by design — a broken
// checkout must still be able to run the gate that diagnoses it.

import { LEGACY_SKILLS_DIR } from "./claude-md-refs.mjs";

export const id = "skill-bridge";

// What git writes into a materialized symlink: the target string, alone.
// Ours are relative and point into the canonical home.
const MATERIALIZED_RE = /^(\.\.\/)+\.agents\/skills\/[A-Za-z0-9._-]+\s*$/;

export function run(ctx) {
  const out = [];
  for (const name of ctx.list(LEGACY_SKILLS_DIR)) {
    const entry = `${LEGACY_SKILLS_DIR}/${name}`;
    // ctx.read throws EISDIR on a directory (and on a symlink resolving to
    // one) — which are exactly the healthy shapes this rule skips. A path
    // suffix probe cannot make the distinction: path.join normalizes
    // `entry/.` back to `entry` before the filesystem ever sees it.
    let raw;
    try {
      raw = ctx.read(entry);
    } catch {
      continue; // a directory — a real skill dir or a resolving symlink
    }
    if (raw == null) continue; // dangling symlink — the gate's path rules own that
    if (!MATERIALIZED_RE.test(raw)) continue; // ordinary file (a licence, a stray)
    out.push({
      validator: id,
      severity: "warning",
      file: entry,
      rule: "skill-bridge-broken",
      message:
        "is a regular file holding a symlink target — this checkout materialized the skill bridge, and the harness that reads only this address sees no skills",
      hint: "Re-checkout with symlinks enabled (`git config core.symlinks true`, then restore the files) or work from an environment that supports them (the kit's gates already require POSIX sh — WSL on Windows). The skills themselves are intact at .agents/skills/.",
    });
  }
  return out;
}
