// The reviewer tier's UNMAPPED setting, made audible. A consumer ran a whole
// wave with every tier empty and the gate green throughout (#655): with the
// reviewer tier unmapped the resolver prints nothing, every review spawn
// inherits the session's model, and the independent review the chain sells
// becomes the author re-reading its own diff — with nothing anywhere saying so
// before the wave's reports did.
//
// Only the REVIEWER tier is read. The other tiers unmapped cost money, not
// independence: a planner or a builder on the session's model is a legitimate
// choice, a reviewer on it is the one blind spot the tier exists to close.
//
// Findings here are WARNINGS, never failures: a project with one model has no
// second one to map, and an unmapped tier is a working state the resolver
// handles. The nudge goes quiet once the line names a model.
//
// The policy file is an ORDERED LIST, the first that exists being the one
// read, for the reason the trace-off advisory gives: the resolver reaches a
// repo's own mapping through a seam, and a repo that keeps it in a
// never-shipped twin (the kit does) names the twin first. A tree with no
// policy file at all produces no finding.

import { firstExisting, shellValue } from "./trace-off.mjs";

export const id = "reviewer-unmapped";

export const DEFAULT_POLICY_FILES = ["scripts/agents.config.sh"];
const SETTING = "AGENT_TIER_REVIEWER";

export function run(ctx) {
  const cfg = ctx.config.reviewerUnmapped ?? {};
  const policy = firstExisting(ctx, cfg.policyFiles ?? DEFAULT_POLICY_FILES);

  if (policy == null) return [];
  const raw = ctx.read(policy);
  if (raw == null || (shellValue(raw, SETTING) ?? "") !== "") return [];

  return [
    {
      validator: id,
      severity: "warning",
      file: policy,
      rule: "reviewer-unmapped",
      message: `leaves ${SETTING} empty, so the reviewer tier is unmapped`,
      hint: `Every review spawn then inherits the session's model: the independent review runs on the author's model, sharing its blind spots. Name a model the implementer does not run on in ${SETTING} in ${policy}. reviewerUnmapped in the gate config names the file read.`,
    },
  ];
}
