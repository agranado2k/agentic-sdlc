// Aggregates every validator. A validator that throws is itself reported as a
// finding (validator-crash, a violation) rather than taking the whole run down.
//
// VALIDATORS is the registration list: a validator arrives as data here. The
// reduced POSIX notice in scripts/check.sh must name every scan on it, and
// the kit's self-host suite holds the notice to this list (#129).

import * as bannedWords from "./validators/banned-words.mjs";
import * as claudeMdRefs from "./validators/claude-md-refs.mjs";
import * as designBrief from "./validators/design-brief.mjs";
import * as housekeepingDue from "./validators/housekeeping-due.mjs";
import * as livingSpec from "./validators/living-spec.mjs";
import * as mutationDecision from "./validators/mutation-decision.mjs";
import * as reviewerUnmapped from "./validators/reviewer-unmapped.mjs";
import * as skillBridge from "./validators/skill-bridge.mjs";
import * as skillCeiling from "./validators/skill-ceiling.mjs";
import * as skillPaths from "./validators/skill-paths.mjs";
import * as skillWeb from "./validators/skill-web.mjs";
import * as traceOff from "./validators/trace-off.mjs";

export const VALIDATORS = [bannedWords, claudeMdRefs, designBrief, housekeepingDue, livingSpec, mutationDecision, reviewerUnmapped, skillBridge, skillCeiling, skillPaths, skillWeb, traceOff];

/** Run all validators against the context; returns a flat list of findings —
 * violations and warnings alike. `index.mjs` splits them by severity; only it
 * decides the exit code. */
export function runAll(ctx) {
  const findings = [];
  for (const validator of VALIDATORS) {
    try {
      findings.push(...validator.run(ctx));
    } catch (err) {
      findings.push({
        validator: validator.id,
        file: "-",
        rule: "validator-crash",
        message: `Validator threw: ${err?.message ?? String(err)}`,
        hint: "This is a bug in the validator, not the docs.",
      });
    }
  }
  return findings;
}
