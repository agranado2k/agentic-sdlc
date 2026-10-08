// The trace's OFF setting, made audible. A consumer bootstrapped from v0.62.0
// ran a whole wave with its trace off and the gate green throughout (#655):
// nothing read the setting, so nobody learned that `/retro` would have nothing
// to read. Since #654 bootstrap asks once and writes the answer into the trace
// policy file — but every project bootstrapped before that question existed
// carries the shipped empty line, decided by nobody.
//
// The advisory fires only when the trace COULD be on at no further cost: the
// policy leaves TRACE_DIR empty while the ignore file already ignores the
// trace directory. Without the ignore entry, turning the trace on would write
// private plain text into a tree that can push it — that project has a step
// to take first, and bootstrap's next-steps text names it; this nudge would
// be the wrong one.
//
// Findings here are WARNINGS, never failures: an off trace is a legal
// decision (the policy file's own header says so), and a project may keep it
// off on purpose. The way to silence the nudge for good is to decide out loud
// — set TRACE_DIR, or drop the ignore entry the trace no longer needs.
//
// The policy file is an ORDERED LIST, the first that exists being the one
// read, because the trace script itself resolves its policy through a seam:
// a repo that keeps its own policy in a never-shipped twin (the kit does)
// names the twin first, and a tree without the twin falls through to the
// shipped file. A tree with no policy file at all produces no finding.

export const id = "trace-off";

export const DEFAULT_POLICY_FILES = ["scripts/trace.config.sh"];
export const DEFAULT_IGNORE_FILE = ".gitignore";
export const DEFAULT_DIR = ".trace";

/** The first path in `paths` that exists in the tree, or null. */
export function firstExisting(ctx, paths) {
  return paths.find((p) => ctx.exists(p)) ?? null;
}

/**
 * The value a POSIX shell would give `name` after sourcing `text`: the LAST
 * plain assignment wins, single- or double-quoted or bare; a commented line is
 * not an assignment. Returns null when nothing assigns it. Expansions are not
 * evaluated — a policy file is data, and the kit's are written as literals.
 */
export function shellValue(text, name) {
  const re = new RegExp(`^[ \\t]*(?:export[ \\t]+)?${name}=(.*)$`, "gm");
  let value = null;
  for (const m of text.matchAll(re)) {
    const rest = m[1];
    const quoted = /^(['"])(.*?)\1/.exec(rest);
    value = quoted ? quoted[2] : (/^[^\s#;]*/.exec(rest)?.[0] ?? "");
  }
  return value;
}

/** Whether an ignore file carries a plain, un-negated entry for `dir`. */
function ignores(text, dir) {
  const wanted = new Set([dir, `${dir}/`, `/${dir}`, `/${dir}/`]);
  return text.split(/\r?\n/).some((line) => wanted.has(line.trimEnd()));
}

export function run(ctx) {
  const cfg = ctx.config.traceOff ?? {};
  const policy = firstExisting(ctx, cfg.policyFiles ?? DEFAULT_POLICY_FILES);
  const ignoreFile = cfg.ignoreFile ?? DEFAULT_IGNORE_FILE;
  const dir = cfg.dir ?? DEFAULT_DIR;

  if (policy == null) return [];
  const raw = ctx.read(policy);
  if (raw == null || (shellValue(raw, "TRACE_DIR") ?? "") !== "") return [];
  const ignored = ctx.exists(ignoreFile) ? ctx.read(ignoreFile) : null;
  if (ignored == null || !ignores(ignored, dir)) return [];

  return [
    {
      validator: id,
      severity: "warning",
      file: policy,
      rule: "trace-off",
      message: `leaves TRACE_DIR empty, so the trace is off — while ${ignoreFile} already ignores ${dir}/`,
      hint: `Nothing the chain decides is being recorded, so \`/retro\` will have no trace to read. Set TRACE_DIR='${dir}' in ${policy} to turn it on (the ignore entry already keeps it out of every push), or, if off is your decision, drop the ${dir}/ line from ${ignoreFile} to say so. traceOff in the gate config names the files read.`,
    },
  ];
}
