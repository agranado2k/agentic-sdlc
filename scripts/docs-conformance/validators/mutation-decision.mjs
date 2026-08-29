// The engineering article's MUTATION DECISION, refereed. Shared invariant §9
// says a green suite is a claim, not a measurement, and the mutation tool is
// the instrument that measures it — but the decision to wire one (or to
// record why not) proved skippable in practice: a real consumer shipped a
// green, guard-armed project with no mutation tool and noticed only
// afterwards (#85). The engineering article template stamps a labeled anchor
// for exactly this (#91); this validator asks whether a FILLED article still
// carries it, in either of its two honest forms — a tool with its on-demand
// command, or an explicit none-with-reason. Silence is the one shape it
// names.
//
// Findings here are WARNINGS, the same posture as skill-web and skill-paths,
// and for the same structural reason: the stamped article is CONSUMER-OWNED
// prose, and an article filled from a pre-#91 template is sanctioned version
// skew, not a defect — a red gate would punish every consumer whose article
// predates the anchor. The promotion path, if the warning proves ignorable:
// flip this validator's severity once the anchor has been in every supported
// release long enough that "my template predates it" stops being true.
//
// A repo with NO stamped article produces no finding: the article-not-written
// state belongs to the templates-stamped and article-reachability rules, not
// to this one.

export const id = "mutation-decision";

const ANCHOR_RE = /^\*\*Mutation decision\*\*:\s*\S/m;

export function run(ctx) {
  const refsCfg = ctx.config.claudeMdRefs ?? {};
  const cfg = ctx.config.mutationDecision ?? {};
  const dir = refsCfg.constitutionDir ?? "constitution";
  const article = cfg.article ?? `${dir}/local-engineering.md`;

  if (!ctx.exists(article)) return [];
  const raw = ctx.read(article);
  if (raw == null || ANCHOR_RE.test(raw)) return [];

  return [
    {
      validator: id,
      severity: "warning",
      file: article,
      rule: "mutation-decision-missing",
      message:
        "records no mutation decision — no `**Mutation decision**:` line in either honest form",
      hint: "Add the line: name a tool and its on-demand command, or write `none — <reason>`. Surviving mutants are the objective form of \"this test enforces nothing\" (shared invariants §9); deciding not to measure is legal, but only out loud.",
    },
  ];
}
