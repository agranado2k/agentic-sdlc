import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

/**
 * Build the read-only context every validator receives. Rooted at `repoRoot`
 * so tests can point it at a fixture tree instead of the real repo.
 *
 * ONE ERROR MODE. `read` returns null for every failure to read — missing,
 * a directory, unreadable, a dangling symlink — because a validator has one
 * question ("do I have a body to check?") and used to answer it with a
 * try/catch of its own around a wrapper that leaked errno codes. A validator
 * that needs to tell a directory from a file asks `kind`.
 *
 * There is deliberately no `paths` map of well-known project locations here:
 * every path a validator cares about is policy and lives in `config.mjs`, so a
 * project can move its docs without patching the harness.
 *
 * @param {{ repoRoot: string, config: object }} opts
 */
export function makeContext({ repoRoot, config }) {
  /** The text of a repo-relative file, or null for anything that is not a readable file. */
  const read = (rel) => {
    try {
      return readFileSync(join(repoRoot, rel), "utf8");
    } catch {
      return null;
    }
  };

  /** "file", "directory", or null when nothing usable is there (a dangling symlink included). */
  const kind = (rel) => {
    try {
      const st = statSync(join(repoRoot, rel));
      return st.isDirectory() ? "directory" : st.isFile() ? "file" : null;
    } catch {
      return null;
    }
  };

  /** List file names in a repo-relative dir, optionally filtered by extension. */
  const list = (relDir, ext) => {
    const p = join(repoRoot, relDir);
    if (!existsSync(p)) return [];
    return readdirSync(p)
      .filter((f) => !ext || f.endsWith(ext))
      .sort();
  };

  const exists = (rel) => existsSync(join(repoRoot, rel));

  return { repoRoot, config, read, kind, list, exists };
}
