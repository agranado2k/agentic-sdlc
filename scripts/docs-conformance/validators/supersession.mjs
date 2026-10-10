// Supersession held both ways between decision records. A record whose
// "Supersedes / amends" header line says it supersedes another — whole or a
// clause — owes the superseded record a "Superseded by" line that names it:
// a reader who opens the old record is otherwise never told it stopped
// binding, and the index is the only place that knows (#683).
//
// A record is `<recordsDir>/NNNN-*.md`, its id `ADR-NNNN` from the file name;
// the records template is not one. The header line is split on `;` into
// clauses, and a clause that opens with "supersedes" (any case) obliges every
// `ADR-NNNN` it names — an amendment, a "builds on", a parenthetical mention
// oblige nothing. A named record with no file, or the record itself, is not
// this rule's to judge. Each open link is one VIOLATION, filed on the
// superseded record, the file that has to change.
//
// The policy is data in config.mjs's `supersession` block: the records
// directory and the known exceptions, one `<superseded>|<superseding>` each,
// both named by file name without `.md` — never a bare number, which another
// project's records share — that a sweep removes. The POSIX twin in scripts/check.sh reads the same
// block by text and reports the same rule.

export const id = "supersession";

const RECORD = /^(\d{4})-.*\.md$/;
const stem = (file) => file.slice(file.lastIndexOf("/") + 1, -".md".length);
const header = (text, field) => {
  const m = text.match(new RegExp(`^- \\*\\*${field}\\*\\*:(.*)$`, "m"));
  return m ? m[1] : null;
};

export function run(ctx) {
  const cfg = ctx.config.supersession;
  if (!cfg?.recordsDir || ctx.kind(cfg.recordsDir) !== "directory") return [];
  const known = new Set(cfg.knownExceptions ?? []);
  const records = new Map();
  for (const name of ctx.list(cfg.recordsDir, ".md")) {
    const m = name.match(RECORD);
    const file = `${cfg.recordsDir}/${name}`;
    if (m && !records.has(`ADR-${m[1]}`) && ctx.kind(file) === "file") records.set(`ADR-${m[1]}`, file);
  }
  const out = [];
  for (const [self, file] of records) {
    const line = header(ctx.read(file) ?? "", "Supersedes / amends") ?? "";
    const targets = new Set();
    for (const clause of line.split(";")) {
      if (!/^supersedes\b/i.test(clause.trim())) continue;
      for (const m of clause.matchAll(/ADR-\d{4}/g)) targets.add(m[0]);
    }
    for (const target of [...targets].sort()) {
      const old = records.get(target);
      if (target === self || !old) continue;
      if ((header(ctx.read(old) ?? "", "Superseded by") ?? "").includes(self)) continue;
      if (known.has(`${stem(old)}|${stem(file)}`)) continue;
      out.push({
        validator: id,
        file: old,
        rule: "supersession-one-sided",
        message: `${target} is superseded by ${self} (its "Supersedes / amends" line says so), but ${target}'s "Superseded by" line does not name ${self}`,
        hint: `Name ${self} on ${target}'s "Superseded by" line, and in what respect — the old record is where a reader learns it stopped binding.`,
      });
    }
  }
  return out;
}
