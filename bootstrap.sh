#!/bin/sh
# agentic-sdlc — one-shot bootstrap.
#
# Run this ONCE, immediately after creating your repo from the template. It
# personalizes the kit, wires the git hook, tells you what to do next, and then
# deletes itself. It commits nothing: the first commit of your project is yours
# to read and to sign.
#
# Usage:
#   sh bootstrap.sh                          # prompts for the values
#   sh bootstrap.sh "My Project"             # name as an argument
#   sh bootstrap.sh "My Project" "One line." # name + description
#
# POSIX sh, git only. No node, no package manager — the kit's core is
# language-agnostic, and bootstrap runs before your project has a toolchain.

set -eu

die() {
	echo "bootstrap: $*" >&2
	exit 1
}

TEMPLATE="constitution/CLAUDE.md.template"
MANUAL="CLAUDE.md"
# The docs-gate policy file: seeded with your project name so the portability
# guard protects the shared layer from your own vocabulary from the first run.
VOCAB_TEMPLATE="scripts/docs-conformance/local-vocabulary.mjs.template"
VOCAB="scripts/docs-conformance/local-vocabulary.mjs"
# Kit-authoring artifacts: they test and ship the kit itself, and mean nothing
# inside a consumer project. Removed at the end together with this script.
#
# The kit's CI goes too: it runs the kit's OWN acceptance test against the kit's
# OWN shared layer, and inheriting it would give a fresh project a workflow that
# fails for reasons that are none of its business. Consumer CI workflow
# templates are installed separately below (K3).
KIT_ONLY="tests/kit-demo.sh tests/lib.sh tests/guards-demo.sh tests/tdd-pairing-guard.test.sh tests/tdd-pairing-guard-ci.test.sh tests/behavior-delta.test.sh .github/workflows/kit-ci.yml .github/workflows/kit-guards.yml"

# --- ground checks ----------------------------------------------------------
# Run from the repo root regardless of where the caller invoked it.
root=$(git rev-parse --show-toplevel 2>/dev/null) ||
	die "not inside a git repository. Run \`git init\` (or clone from the template) first — bootstrap wires a git hook and has nothing to wire otherwise."
cd "$root"

# Idempotency: refuse the second run rather than re-stamping over a manual you
# have since edited. Refusing is cheap; silently overwriting a week of local
# rules is not.
[ -f "$MANUAL" ] &&
	die "$MANUAL already exists — this repo looks bootstrapped already. Delete $MANUAL first if you really mean to re-stamp it."
[ -f "$TEMPLATE" ] ||
	die "$TEMPLATE not found. Either this is not an agentic-sdlc repo, or bootstrap already ran."

# --- gather values ----------------------------------------------------------
name=${1:-}
description=${2:-}

if [ -z "$name" ]; then
	if [ -t 0 ]; then
		printf 'Project name: '
		read -r name
	else
		die "no project name given and no terminal to ask on. Pass it: sh bootstrap.sh \"My Project\""
	fi
fi
[ -n "$name" ] || die "project name cannot be empty."

if [ -z "$description" ]; then
	if [ -t 0 ]; then
		printf 'One-line description (Enter to skip): '
		read -r description || description=""
	fi
fi
[ -n "$description" ] || description="An agent-assisted project built on the agentic-sdlc framework."

# A stamped value containing the placeholder syntax would defeat the gate, and a
# `/` or `&` would corrupt the sed replacement below.
case "$name$description" in
*'{{'* | *'}}'*) die "project name/description must not contain '{{' or '}}'." ;;
esac

# --- stamp ------------------------------------------------------------------
# `|` as the sed delimiter, and the values are escaped for it plus `&` and `\`.
esc() {
	printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}
# The vocabulary file is JavaScript, and the name lands inside a double-quoted
# string literal there. Escape for JS first, then for sed — in that order, or
# the sed pass would escape the backslashes the JS pass just added.
esc_js() {
	printf '%s' "$1" | sed -e 's/["\\]/\\&/g'
}
name_esc=$(esc "$name")
description_esc=$(esc "$description")
name_js_esc=$(esc "$(esc_js "$name")")

sed \
	-e "s|{{PROJECT_NAME}}|$name_esc|g" \
	-e "s|{{PROJECT_DESCRIPTION}}|$description_esc|g" \
	"$TEMPLATE" >"$MANUAL"
rm -f "$TEMPLATE"
echo "  stamped $MANUAL"

if [ -f "$VOCAB_TEMPLATE" ]; then
	sed -e "s|{{PROJECT_NAME}}|$name_js_esc|g" "$VOCAB_TEMPLATE" >"$VOCAB"
	rm -f "$VOCAB_TEMPLATE"
	echo "  stamped $VOCAB"
fi

# --- wire the hook ----------------------------------------------------------
# Native git hooks path. This is per-clone config, not a tracked setting, so
# every collaborator runs it once — which is why the next-steps text says so.
git config core.hooksPath .githooks
chmod +x .githooks/* scripts/*.sh 2>/dev/null || true
echo "  wired core.hooksPath -> .githooks"

# --- install the CI workflow templates --------------------------------------
# The kit ships these under templates/ rather than .github/workflows/ because a
# TEMPLATE repository must not run its consumers' CI against its own tree — the
# docs gate expects a bootstrapped project, and the kit is deliberately not one.
# They become real workflows here, where there IS a project to gate.
#
# Never overwrites: a file already at the destination is somebody's decision.
if [ -d templates/workflows ]; then
	mkdir -p .github/workflows
	for wf in templates/workflows/*; do
		[ -e "$wf" ] || continue
		dest=".github/workflows/$(basename "$wf")"
		if [ -e "$dest" ]; then
			echo "  kept $dest (already present — not overwritten)"
		else
			cp "$wf" "$dest"
			echo "  installed $dest"
		fi
	done
	rm -rf templates/workflows
	rmdir templates 2>/dev/null || true
fi

# --- clean up the kit's own scaffolding -------------------------------------
for f in $KIT_ONLY; do
	if [ -e "$f" ]; then
		rm -f "$f"
		echo "  removed $f (kit-authoring only)"
	fi
done
# Only if now empty — a project that already has its own workflows keeps them.
rmdir tests .github/workflows .github 2>/dev/null || true

# --- next steps -------------------------------------------------------------
cat <<EOF

Bootstrapped: $name

Next:
  1. sh scripts/check.sh          run the docs gate — it should pass now
  2. read CLAUDE.md               it is loaded into every agent session; every
                                  line is yours to keep, cut, or replace
  3. fill in the two articles     constitution/local-engineering.md.template
                                  constitution/local-workflow.md.template
                                  replace the marks, drop the .template suffix,
                                  then point CLAUDE.md's article layer at them
  4. edit scripts/guards.config.sh
                                  the TDD pairing guard is INACTIVE until you
                                  set GUARD_SOURCE_RE to match your source
                                  trees. Until then it warns on every push and
                                  blocks nothing — on purpose, because it cannot
                                  know your layout and will not guess it.
  5. rewrite README.md            it currently describes the kit, not $name
  6. git add -A && git commit     bootstrap committed nothing on purpose

Both gates run automatically before every push (.githooks/pre-push), each with
its own loud bypass: PUSH_WITHOUT_DOCS=1 and PUSH_WITHOUT_TESTS=1. The matching
CI workflows were installed into .github/workflows/, so a local bypass only
defers the failure. Commit linting ships DISABLED as
.github/workflows/commitlint.yml.example — rename it once you have a runner.
Collaborators cloning this repo run \`git config core.hooksPath .githooks\`
once — hooks path is per-clone config and cannot be committed.

With node on PATH the gate runs the full docs-conformance harness
(scripts/docs-conformance); without it, a reduced POSIX fallback runs and says
so. The policy it enforces is data you own: scripts/docs-conformance/config.mjs
and scripts/docs-conformance/local-vocabulary.mjs.

The shared layer (see VERSION) is copied verbatim from the kit and is not
edited here. Everything else is yours.
EOF

# --- self-delete ------------------------------------------------------------
# Last, so a failure above leaves bootstrap runnable.
rm -f "$root/bootstrap.sh"
