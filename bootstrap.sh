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
# Kit-authoring artifacts: they test and ship the kit itself, and mean nothing
# inside a consumer project. Removed at the end together with this script.
# Space-separated; each kit ticket that adds a demo adds its script here.
KIT_ONLY="tests/skeleton-demo.sh tests/docs-demo.sh"

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
name_esc=$(esc "$name")
description_esc=$(esc "$description")

sed \
	-e "s|{{PROJECT_NAME}}|$name_esc|g" \
	-e "s|{{PROJECT_DESCRIPTION}}|$description_esc|g" \
	"$TEMPLATE" >"$MANUAL"
rm -f "$TEMPLATE"
echo "  stamped $MANUAL"

# --- wire the hook ----------------------------------------------------------
# Native git hooks path. This is per-clone config, not a tracked setting, so
# every collaborator runs it once — which is why the next-steps text says so.
git config core.hooksPath .githooks
chmod +x .githooks/* scripts/*.sh 2>/dev/null || true
echo "  wired core.hooksPath -> .githooks"

# ============================================================================
# K4 BEGIN — the documentation set (#6)
# ----------------------------------------------------------------------------
# Everything between this banner and `K4 END` belongs to K4. bootstrap.sh is
# touched by several kit tickets (K1 constitution articles, K3 guards); keeping
# each one's edits inside a named block is the difference between a three-way
# merge and a rewrite. Do not interleave.
#
# The skeletons live under templates/docs/ and are put in place here:
#   *.template      -> stamped through sed (they carry double-brace marks)
#   everything else -> copied verbatim (it must carry NO marks: once it lands
#                      it is ordinary repo content and the gate scans it)
#
# The templates/docs/ source tree is removed afterwards. A project holding both
# a stamped docs/diary.md and an unstamped templates/docs/diary.md.template has
# two answers to the same question, and bootstrap does not run a second time to
# reconcile them — same reasoning as constitution/CLAUDE.md.template above.
DOCS_TEMPLATES="templates/docs"
today=$(date +%Y-%m-%d)
today_esc=$(esc "$today")

# stamp <source> <destination>
stamp() {
	mkdir -p "$(dirname "$2")"
	sed \
		-e "s|{{PROJECT_NAME}}|$name_esc|g" \
		-e "s|{{PROJECT_DESCRIPTION}}|$description_esc|g" \
		-e "s|{{BOOTSTRAP_DATE}}|$today_esc|g" \
		"$1" >"$2"
	echo "  stamped $2"
}

# copy <source> <destination>
copy() {
	mkdir -p "$(dirname "$2")"
	cp "$1" "$2"
	echo "  copied  $2"
}

if [ -d "$DOCS_TEMPLATES" ]; then
	# The kit's own README describes the kit. Overwriting it is the point:
	# a project whose README advertises the template it came from tells every
	# reader the wrong thing on day one.
	stamp "$DOCS_TEMPLATES/README.md.template" "README.md"
	stamp "$DOCS_TEMPLATES/diary.md.template" "docs/diary.md"
	stamp "$DOCS_TEMPLATES/domain-glossary.md.template" "docs/domain-glossary.md"
	stamp "$DOCS_TEMPLATES/adr/INDEX.md.template" "docs/adr/INDEX.md"

	# Verbatim: the MADR skeleton stays a working template inside the project
	# (it is copied per new decision), and GitHub reads the PR template from
	# .github/ by name.
	copy "$DOCS_TEMPLATES/adr/NNNN-template.md" "docs/adr/NNNN-template.md"
	copy "$DOCS_TEMPLATES/PULL_REQUEST_TEMPLATE.md" ".github/PULL_REQUEST_TEMPLATE.md"

	rm -rf "$DOCS_TEMPLATES"
	rmdir templates 2>/dev/null || true
	echo "  removed $DOCS_TEMPLATES (stamped into place)"
else
	echo "  skipped the documentation set — $DOCS_TEMPLATES not found"
fi
# K4 END
# ============================================================================

# --- clean up the kit's own scaffolding -------------------------------------
for f in $KIT_ONLY; do
	[ -e "$f" ] && rm -f "$f" && echo "  removed $f (kit-authoring only)"
done
rmdir tests 2>/dev/null || true

# --- next steps -------------------------------------------------------------
cat <<EOF

Bootstrapped: $name

Next:
  1. sh scripts/check.sh          run the docs gate — it should pass now
  2. read CLAUDE.md               it is loaded into every agent session; make
                                  the "Local rules" section yours
  3. fill in docs/diary.md        the "Current state" block at the top is what
                                  an agent reads first; README.md is stamped
                                  but thin — make it say what $name is
  4. git add -A && git commit     bootstrap committed nothing on purpose

The gate runs automatically before every push (.githooks/pre-push).
Collaborators cloning this repo run \`git config core.hooksPath .githooks\`
once — hooks path is per-clone config and cannot be committed.

The shared layer (see VERSION) is copied verbatim from the kit and is not
edited here. Everything else is yours.
EOF

# --- self-delete ------------------------------------------------------------
# Last, so a failure above leaves bootstrap runnable.
rm -f "$root/bootstrap.sh"
