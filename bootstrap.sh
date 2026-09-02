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
# Options (they may appear anywhere among the arguments):
#   --with-dogfood   install the optional /dogfood skill
#   --no-dogfood     skip it
# Without either flag the script asks, once, on a terminal; with no terminal to
# ask on it skips. See the F6 block below for why skip is the safe default.
#
# POSIX sh, git only. No node, no package manager — the kit's core is
# language-agnostic, and bootstrap runs before your project has a toolchain.

set -eu

die() {
	echo "bootstrap: $*" >&2
	exit 1
}

# The double-brace MARK, assembled from two variables so this script never
# contains a literal one.
#
# `scripts/check.sh` scans every file in the tree for a surviving mark and
# exempts only `*.template` sources — deliberately, because a gate blind to its
# own tooling is not a gate, and check.sh spells its own pattern out of
# variables for exactly this reason. Now that the kit repo is itself
# bootstrapped (docs/adr/0001-the-kit-self-hosts-its-own-constitution.md), that
# scan runs over THIS file too, so the kit-authoring scripts that have to NAME
# the mark spell it the same way rather than carving an exemption into a
# shared-layer file every consumer also receives.
ob='{'
cb='}'
# mark <NAME> — the placeholder as it appears in a template, e.g. PROJECT_NAME.
mark() { printf '%s%s%s%s%s' "$ob" "$ob" "$1" "$cb" "$cb"; }

# --- single-source constants both arms share --------------------------------
# The new-project arm (F6/K4/K7 below) and the adopt arm (F13) write the same
# bytes in several places. One definition each, or the two arms drift the day
# one of them is edited alone.
#
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
# A shim's exact bytes: the gate's shim-invalid rule rejects anything else, so
# there is exactly one writer.
shim_body() {
	printf '%s\n%s\n' "<!-- Shim: the agent manual is $MANUAL. Edit that file, not this one. -->" "@$MANUAL"
}
# The optional-skill marker filters, one pair per comment dialect: KEEP drops
# only the scaffolding markers, STRIP drops the whole marked block.
DOGFOOD_MD_KEEP='/<!-- DOGFOOD:BEGIN -->/d;/<!-- DOGFOOD:END -->/d'
DOGFOOD_MD_STRIP='/<!-- DOGFOOD:BEGIN -->/,/<!-- DOGFOOD:END -->/d'
DOGFOOD_JS_KEEP='/\/\/ DOGFOOD:BEGIN/d;/\/\/ DOGFOOD:END/d'
DOGFOOD_JS_STRIP='/\/\/ DOGFOOD:BEGIN/,/\/\/ DOGFOOD:END/d'
# The one question, asked by whichever arm runs.
DOGFOOD_PROMPT='Include the /dogfood skill? Needs a runnable user-facing surface. [y/N] '

TEMPLATE="constitution/AGENTS.md.template"
MANUAL="AGENTS.md"
# The manual is ONE file. AGENTS.md is the filename the agent-tool ecosystem has
# converged on, and the tools that read a differently-named file get a SHIM: one
# import line pointing at the manual, no rules of its own. Two manuals is the
# failure mode this prevents — the moment a tool-specific file can hold a rule,
# it does, and the rules diverge silently per tool.
SHIMS="CLAUDE.md GEMINI.md"
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
# EXCLUSIONS.md goes the same way, and it is one of two entries here that are
# not a test: it records what the KIT deliberately does not ship, which is a
# sentence with no referent inside a consumer project — a reader there would
# take it for a record of their own decisions. It is prose, not scaffolding,
# but its lifetime is the kit's. That is also why it is not shared layer (see
# VERSION): a file bootstrap deletes cannot be copied verbatim or diffed
# against a later release.
#
# scripts/agents.kit.config.sh is the other non-test entry, and a different
# class again: it is the kit's OWN capability-tier -> model mapping (AGENTS.md,
# "Capability tiers"). scripts/agents.config.sh — the file every consumer
# edits — ships EMPTY by principle, because the kit names no model to a
# consumer; but this repo is itself a consumer of the mechanism it ships, and
# needs a real mapping so its own subagents do not silently fall back to
# whatever model the session happens to be running on. Naming a model is
# exactly the kind of content with no business surviving into a stamped
# project. scripts/agents.kit.sh sits beside it for the same reason: it exists
# only to reach a config that does not exist in a stamped project, so keeping
# it would ship a broken command rather than a useless one.
#
# Space-separated; each kit ticket that adds a demo, or a kit-authoring-only
# script, adds its entry here.
KIT_ONLY="tests/kit-demo.sh tests/docs-demo.sh tests/lib.sh tests/self-host.test.sh tests/guards-demo.sh tests/adapters-demo.sh tests/tdd-pairing-guard.test.sh tests/tdd-pairing-guard-ci.test.sh tests/behavior-delta.test.sh tests/worktree-cleanup.test.sh tests/agents-tiers.test.sh tests/implement-deliver.test.sh tests/ai-review-template.test.sh tests/exclusions.test.sh tests/dogfood-optin.test.sh tests/setup-demo.sh tests/review-pr-output.test.sh tests/adopt-demo.sh tests/docs-gate-advisory.test.sh tests/design-brief-skill.test.sh tests/housekeeping-skill.test.sh .github/workflows/kit-ci.yml .github/workflows/kit-guards.yml EXCLUSIONS.md scripts/agents.kit.config.sh scripts/agents.kit.sh scripts/mutation.kit.sh scripts/mutation.kit.config.json SETUP.md setup/agent-bootstrap.md"

# NOT in KIT_ONLY, and deliberately: adapters/. It is reference material a
# project wants LATER — on the day it turns a guard on, typically weeks after
# bootstrap — so it arrives intact and dormant rather than being deleted here or
# installed automatically. Nothing in it is copied, stamped or activated; see
# adapters/node-ts/INSTALL.md, "Why bootstrap.sh does not touch this directory".
# tests/adapters-demo.sh asserts exactly that, byte for byte.

# --- ground checks ----------------------------------------------------------
# Run from the repo root regardless of where the caller invoked it.
root=$(git rev-parse --show-toplevel 2>/dev/null) ||
	die "not inside a git repository. Run \`git init\` (or clone from the template) first — bootstrap wires a git hook and has nothing to wire otherwise."
cd "$root"

# ============================================================================
# F13 BEGIN — ADOPT MODE: the existing-repo arm (#82, PRD #81)
# ----------------------------------------------------------------------------
# `--adopt` runs FROM INSIDE a target repository, against the scratch kit
# clone this script lives in. A script meeting a collision can only refuse or
# clobber, so adopt mode does exactly and only what a script is good at:
# CLASSIFY every kit file per the recorded per-class policy, INSTALL the
# non-colliding set in one pass, and REPORT each conflict as one stable line —
#
#     COLLISION <class> <path> <verb>
#
# — resolving nothing itself. Exit 3 means "partial: collisions pending" (the
# agent and the human resolve them per the payload document's existing-repo
# arm, one approval at a time, then re-run this same command); exit 0 means
# the tree was — or has become — clean, and the run completes exactly as the
# new-project arm does: stamped manual, shims, hook wired, self-deletion.
# Re-runs are idempotent: an installed file compares equal and stays silent.
#
# This block sits BEFORE the F12 strip and the idempotency refusals on
# purpose: those checks read "AGENTS.md exists" as "already bootstrapped",
# which is exactly wrong for a target repo whose manual is the adoption's
# hardest collision. Everything below F13 END is the new-project arm,
# untouched.
ADOPT=0
for a_arg in "$@"; do
	[ "$a_arg" = "--adopt" ] && ADOPT=1
done
if [ "$ADOPT" = 1 ]; then
	a_kit=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) ||
		die "cannot resolve the kit clone's own directory from $0"
	[ -f "$a_kit/constitution/AGENTS.md.template" ] && [ -f "$a_kit/VERSION" ] ||
		die "--adopt needs an UNSTAMPED kit clone beside the script — constitution/AGENTS.md.template or VERSION is missing next to $0"
	[ "$a_kit" = "$root" ] &&
		die "--adopt runs from inside the TARGET repository, against a kit clone elsewhere: cd <your repo> && sh <kit-clone>/bootstrap.sh --adopt [--with-dogfood|--no-dogfood] \"My Project\" \"One line.\""

	# Arguments: same vocabulary as the new-project arm, parsed self-contained
	# so an unknown flag dies instead of becoming a project name.
	a_name="" a_desc="" a_have=0 a_dog=ask
	for a_arg in "$@"; do
		case "$a_arg" in
		--adopt) ;;
		--with-dogfood) a_dog=yes ;;
		--no-dogfood) a_dog=no ;;
		-*) die "unknown option '$a_arg' for --adopt. Supported: --with-dogfood, --no-dogfood." ;;
		*)
			if [ "$a_have" = 0 ]; then
				a_name=$a_arg a_have=1
			elif [ "$a_have" = 1 ]; then
				a_desc=$a_arg a_have=2
			else
				die "too many arguments. Usage: sh <kit-clone>/bootstrap.sh --adopt [--with-dogfood|--no-dogfood] \"My Project\" \"One line.\""
			fi
			;;
		esac
	done
	[ "$a_have" = 2 ] ||
		die "usage: sh <kit-clone>/bootstrap.sh --adopt [--with-dogfood|--no-dogfood] \"My Project\" \"One line.\""
	case "$a_name$a_desc" in
	*'{{'* | *'}}'*) die "project name/description must not contain '{{' or '}}'." ;;
	esac
	if [ "$a_dog" = ask ]; then
		if [ -t 0 ]; then
			printf %s "$DOGFOOD_PROMPT"
			read -r a_ans || a_ans=""
			case "$a_ans" in
			[Yy] | [Yy][Ee][Ss]) a_dog=yes ;;
			*) a_dog=no ;;
			esac
		else
			a_dog=no
		fi
	fi
	if [ "$a_dog" = yes ] && [ ! -f "$a_kit/.agents/skills/dogfood/SKILL.md" ]; then
		echo "  note: /dogfood was requested but the kit clone does not carry it — skipping" >&2
		a_dog=no
	fi

	a_name_esc=$(esc "$a_name")
	a_desc_esc=$(esc "$a_desc")
	a_name_js_esc=$(esc "$(esc_js "$a_name")")
	a_today_esc=$(esc "$(date +%Y-%m-%d)")
	a_scratch=$(mktemp -d) || die "cannot create a scratch directory"
	trap 'rm -rf "$a_scratch"' EXIT

	a_collisions=0
	a_hit() {
		printf 'COLLISION %s %s %s\n' "$1" "$2" "$3"
		a_collisions=$((a_collisions + 1))
	}
	# Presence, as OWNERSHIP: a symlink is theirs even when its destination is
	# gone. `[ -e ]` alone reads a dangling link as an empty slot, and a copy
	# into that slot writes THROUGH the link — outside the repo, on a clean
	# exit. That is the one hole a classifier absolutely may not have.
	a_exists() { [ -e "$1" ] || [ -L "$1" ]; }
	# a_stamp <kit-relative template> <destination> — always via scratch: sed
	# writes a temp file and the bytes move only once they exist (craft §11).
	a_stamp() {
		sed \
			-e "s|$(mark PROJECT_NAME)|$a_name_esc|g" \
			-e "s|$(mark PROJECT_DESCRIPTION)|$a_desc_esc|g" \
			-e "s|$(mark BOOTSTRAP_DATE)|$a_today_esc|g" \
			"$a_kit/$1" >"$a_scratch/stamp.$$" || die "stamping $1 failed"
		mkdir -p "$(dirname "$2")"
		mv "$a_scratch/stamp.$$" "$2"
		echo "  stamped $2"
	}
	# Scratch-then-move, files and directories alike: mv replaces whatever name
	# is at the destination (a link included) instead of writing through it —
	# the same §11 posture a_stamp already keeps. The destinations are only
	# ever absent slots (a_exists gated), so this is defense in depth, not the
	# primary control.
	a_copy() {
		mkdir -p "$(dirname "$2")"
		cp -p "$a_kit/$1" "$a_scratch/copy.$$" && mv "$a_scratch/copy.$$" "$2"
		echo "  installed $2"
	}
	a_copy_dir() {
		mkdir -p "$(dirname "$2")"
		rm -rf "$a_scratch/dir.$$"
		cp -Rp "$a_kit/$1" "$a_scratch/dir.$$" && mv "$a_scratch/dir.$$" "$2"
		echo "  installed $2/"
	}
	# kept, and said so once per run: project memory and policy already in
	# place is a fact, not a conflict — a verdict must be resolvable, and
	# "your diary exists" never stops being true.
	a_keep() { echo "  kept $1 (yours — never overwritten)"; }

	# A symlinked PARENT routes every write below through it. What matters is
	# WHERE it lands: a link that stays inside the repository is a layout
	# choice — the one-link `.claude/skills -> ../.agents/skills` bridge
	# UPDATING.md blesses is exactly that — and the project's files still end
	# up in the project, which is the whole requirement. A link that leaves
	# the repository (or resolves nowhere) is the hole: the files land
	# outside, on a clean exit, and git never sees them. So the test is
	# containment, not symlink-ness, and it covers EVERY directory this arm
	# writes beneath rather than a hand-picked four.
	a_root=$(pwd -P)
	# a_escapes <path> — the path is a link that does not resolve to
	# somewhere inside this repository.
	a_escapes() {
		[ -L "$1" ] || return 1
		a_dest=$(cd "$1" 2>/dev/null && pwd -P)
		[ -n "$a_dest" ] || return 0 # dangling — nothing to write into
		case "$a_dest/" in
		"$a_root"/*) return 1 ;;
		*) return 0 ;;
		esac
	}
	for a_parent in .claude .claude/skills .agents .agents/skills \
		.githooks .github .github/workflows constitution docs docs/adr \
		scripts scripts/docs-conformance; do
		a_escapes "$a_parent" &&
			die "adopt: $a_parent is a symlink that does not resolve inside this repository — refusing to write the project's own files outside it. Point it inside the repo (or make it a real directory) and re-run."
		[ -e "$a_parent" ] && [ ! -d "$a_parent" ] &&
			die "adopt: $a_parent is a file, not a directory — refusing to write beneath it. Move it aside and re-run."
	done
	# --- 1. the shared layer: byte-verbatim or a relocation proposal --------
	# This awk is the manifest parser scripts/check.sh, UPDATING.md step 1 and
	# two suites also carry — four twins by prior decision (a consumer's copy
	# must parse VERSION with no other file in reach). Move them together.
	a_manifest() {
		awk '
			/^files:/       { inlist = 1; next }
			!inlist         { next }
			/^[ \t]*#/      { next }
			/^[ \t]*$/      { next }
			/^[ \t]+[^ \t]/ { sub(/^[ \t]+/, ""); print $1; next }
			                { inlist = 0 }
		' "$a_kit/VERSION"
	}
	for f in $(a_manifest) VERSION; do
		if a_exists "$f"; then
			cmp -s "$a_kit/$f" "$f" || a_hit shared "$f" relocate
		else
			a_copy "$f" "$f"
		fi
	done

	# --- 2. the manual and its shims: one group, all or nothing -------------
	# Stamp what the manual SHOULD be into scratch first, so a re-run that
	# meets its own earlier output stays silent instead of colliding with it.
	a_manual_pending=0
	sed \
		-e "s|$(mark PROJECT_NAME)|$a_name_esc|g" \
		-e "s|$(mark PROJECT_DESCRIPTION)|$a_desc_esc|g" \
		-e "$([ "$a_dog" = yes ] && printf '%s' "$DOGFOOD_MD_KEEP" || printf '%s' "$DOGFOOD_MD_STRIP")" \
		"$a_kit/constitution/AGENTS.md.template" >"$a_scratch/manual.expected"
	for shim in $SHIMS; do
		shim_body >"$a_scratch/shim.$shim"
	done
	if a_exists "$MANUAL" && ! cmp -s "$a_scratch/manual.expected" "$MANUAL"; then
		a_hit manual "$MANUAL" distill
		a_manual_pending=1
	fi
	for shim in $SHIMS; do
		if a_exists "$shim" && ! cmp -s "$a_scratch/shim.$shim" "$shim"; then
			a_hit manual "$shim" distill
			a_manual_pending=1
		fi
	done
	if [ "$a_manual_pending" = 0 ]; then
		if ! a_exists "$MANUAL"; then
			mkdir -p "$(dirname "$MANUAL")" 2>/dev/null || true
			mv "$a_scratch/manual.expected" "$MANUAL"
			echo "  stamped $MANUAL"
		fi
		for shim in $SHIMS; do
			a_exists "$shim" || { mv "$a_scratch/shim.$shim" "$shim"; echo "  wrote   $shim (shim -> $MANUAL)"; }
		done
	fi

	# --- 3. project memory: install where absent, keep where present --------
	a_exists "docs/diary.md" && a_keep "docs/diary.md" || a_stamp "templates/docs/diary.md.template" "docs/diary.md"
	a_exists "docs/domain-glossary.md" && a_keep "docs/domain-glossary.md" || a_stamp "templates/docs/domain-glossary.md.template" "docs/domain-glossary.md"
	a_exists "docs/adr/INDEX.md" && a_keep "docs/adr/INDEX.md" || a_stamp "templates/docs/adr/INDEX.md.template" "docs/adr/INDEX.md"
	a_exists "docs/adr/NNNN-template.md" && a_keep "docs/adr/NNNN-template.md" || a_copy "templates/docs/adr/NNNN-template.md" "docs/adr/NNNN-template.md"
	a_exists ".github/PULL_REQUEST_TEMPLATE.md" && a_keep ".github/PULL_REQUEST_TEMPLATE.md" || a_copy "templates/docs/PULL_REQUEST_TEMPLATE.md" ".github/PULL_REQUEST_TEMPLATE.md"
	# Their README is their front page; an adopted repo keeps it, always.
	a_exists "README.md" && a_keep "README.md" || a_stamp "templates/docs/README.md.template" "README.md"

	# --- 4. skills: the kit's set, name collisions surfaced -----------------
	# Canonical home is the vendor-neutral .agents/skills/; .claude/skills/<s>
	# is a committed per-skill symlink (the shape one harness's docs support).
	# A collision is a NON-IDENTICAL occupant at EITHER address; identical
	# content at the old address is our own earlier install (or a consumer's
	# deliberate real copy) and stays silent. The symlink is laid
	# scratch-then-move like every other copy.
	a_link_skill() {
		rm -f "$a_scratch/link.$$"
		ln -s "../../.agents/skills/$1" "$a_scratch/link.$$" &&
			mv "$a_scratch/link.$$" ".claude/skills/$1"
	}
	# The bridge slot's states, classified: absent -> lay ours; our own link
	# -> nothing to do; anything else (foreign or dangling link, a stray
	# file) -> a collision at that address. Returns 0 when the canonical
	# install may proceed. Their identical REAL directory is handled by the
	# caller before this runs — that one is theirs to keep, bridge and all.
	# A bridge's identity is WHERE it points, not how it is spelled. The
	# byte-compare in a_bridge is the fast path for our own spelling; this
	# asks the same question of every other one — an absolute path, a repo
	# reached through a link — so a bridge that is already correct is not
	# reported as a foreign occupant the operator is told to rename, which
	# is advice with nothing to act on. The link's PARENT is resolved rather
	# than the link itself, so a bridge laid before its canonical skill
	# exists still reads as ours, exactly as the relative spelling does.
	a_points_home() {
		a_p_target=$(readlink ".claude/skills/$1")
		[ "$(basename "$a_p_target")" = "$1" ] || return 1
		a_p_dir=$(cd ".claude/skills" 2>/dev/null &&
			cd "$(dirname "$a_p_target")" 2>/dev/null && pwd -P)
		[ -n "$a_p_dir" ] && [ "$a_p_dir" = "$a_new_home" ]
	}
	a_bridge() {
		# When the two addresses ARE one directory, the alias is already the
		# bridge and a per-skill link would point at itself.
		[ "$a_same_home" = yes ] && return 0
		if [ -L ".claude/skills/$1" ]; then
			[ "$(readlink ".claude/skills/$1")" = "../../.agents/skills/$1" ] && return 0
			a_points_home "$1" && return 0
			a_hit skill ".claude/skills/$1" rename-or-decline
			return 1
		elif a_exists ".claude/skills/$1"; then
			return 2 # a real occupant — the caller decides identical vs collision
		fi
		a_link_skill "$1"
	}
	mkdir -p .claude/skills .agents/skills
	# Do the two skill addresses name the same directory? They do under a
	# directory-level bridge, and then every per-skill link below would be
	# self-referential. Resolved once, after the mkdir, so the answer is the
	# same for the licence as for the skills.
	a_same_home=no
	a_old_home=$(cd .claude/skills 2>/dev/null && pwd -P)
	a_new_home=$(cd .agents/skills 2>/dev/null && pwd -P)
	[ -n "$a_new_home" ] && [ "$a_old_home" = "$a_new_home" ] && a_same_home=yes
	for d in "$a_kit"/.agents/skills/*/; do
		[ -d "$d" ] || continue
		s=$(basename "$d")
		[ "$s" = "dogfood" ] && [ "$a_dog" != yes ] && continue
		if a_exists ".agents/skills/$s"; then
			if diff -rq "$a_kit/.agents/skills/$s" ".agents/skills/$s" >/dev/null 2>&1; then
				# Our own earlier install (or their identical copy) — repair
				# a missing bridge so a clean exit never leaves a red gate.
				a_bridge "$s" || :
			else
				a_hit skill ".agents/skills/$s" rename-or-decline
			fi
		elif a_exists ".claude/skills/$s" && [ ! -L ".claude/skills/$s" ]; then
			if diff -rq "$a_kit/.agents/skills/$s" ".claude/skills/$s" >/dev/null 2>&1; then
				: # identical real copy at the old address — theirs to keep
			else
				a_hit skill ".claude/skills/$s" rename-or-decline
			fi
		else
			# The bridge slot decides whether the install may proceed: a
			# foreign or dangling link there is a collision, and canonical
			# holds back until it is resolved (all-or-nothing per skill).
			if a_bridge "$s"; then
				a_copy_dir ".agents/skills/$s" ".agents/skills/$s"
			fi
		fi
	done
	# The licence is classified like a skill, not merely kept. `a_exists` is
	# ownership, so a DANGLING link at the canonical address counted as
	# present and the file was skipped — a clean exit whose gate is red on
	# every skill, because each one names this path literally. Same verdict
	# the skills get: hold, and let a human decide.
	if [ -L ".agents/skills/LICENSE-mattpocock-skills.md" ] &&
		[ ! -e ".agents/skills/LICENSE-mattpocock-skills.md" ]; then
		a_hit skill ".agents/skills/LICENSE-mattpocock-skills.md" rename-or-decline
	elif ! a_exists ".agents/skills/LICENSE-mattpocock-skills.md"; then
		a_copy ".agents/skills/LICENSE-mattpocock-skills.md" ".agents/skills/LICENSE-mattpocock-skills.md"
	fi
	# The licence gets the same bridge the skills do — an adopted tree should
	# not differ from a templated one by one entry.
	if [ "$a_same_home" != yes ] &&
		[ ! -L ".claude/skills/LICENSE-mattpocock-skills.md" ] &&
		! a_exists ".claude/skills/LICENSE-mattpocock-skills.md"; then
		rm -f "$a_scratch/link.$$"
		ln -s "../../.agents/skills/LICENSE-mattpocock-skills.md" "$a_scratch/link.$$" &&
			mv "$a_scratch/link.$$" ".claude/skills/LICENSE-mattpocock-skills.md"
	fi

	# --- 5. policy and local files: install only where absent ---------------
	if ! a_exists "scripts/docs-conformance/config.mjs"; then
		# The dogfood-marked exemption block travels with the skill, exactly
		# as the new-project arm stamps it (both markers or neither; the kit's
		# own copy always carries the pair).
		sed \
			-e "$([ "$a_dog" = yes ] && printf '%s' "$DOGFOOD_JS_KEEP" || printf '%s' "$DOGFOOD_JS_STRIP")" \
			"$a_kit/scripts/docs-conformance/config.mjs" >"$a_scratch/config.mjs" ||
			die "preparing the gate policy file failed"
		mkdir -p scripts/docs-conformance
		mv "$a_scratch/config.mjs" "scripts/docs-conformance/config.mjs"
		echo "  installed scripts/docs-conformance/config.mjs"
	else
		a_keep "scripts/docs-conformance/config.mjs"
		# A kept policy file plus a dogfood YES can contradict each other — the
		# flag may have flipped between runs, or their config predates the
		# exemption. The gate would only whisper about it later (a skill-path
		# advisory on the skill's first report), so say it now, while the human
		# is already approving things.
		if [ "$a_dog" = yes ] && ! grep -q 'docs/dogfood-reports/' "scripts/docs-conformance/config.mjs"; then
			echo "  note: config.mjs is yours and was kept, but it lacks the dogfood exemption the" >&2
			echo "  note: skill needs — add \"docs/dogfood-reports/\" to skillPaths.exemptTokens by hand," >&2
			echo "  note: or the gate will warn the day the first dogfood report is written." >&2
		fi
	fi
	if ! a_exists "scripts/docs-conformance/local-vocabulary.mjs"; then
		sed -e "s|$(mark PROJECT_NAME)|$a_name_js_esc|g" \
			"$a_kit/scripts/docs-conformance/local-vocabulary.mjs.template" >"$a_scratch/vocab.mjs" ||
			die "stamping the vocabulary failed"
		mv "$a_scratch/vocab.mjs" "scripts/docs-conformance/local-vocabulary.mjs"
		echo "  stamped scripts/docs-conformance/local-vocabulary.mjs"
	else
		a_keep "scripts/docs-conformance/local-vocabulary.mjs"
	fi
	for f in scripts/guards.config.sh scripts/agents.config.sh scripts/worktree-cleanup.sh \
		scripts/docs-conformance/README.md \
		constitution/local-engineering.md.template constitution/local-workflow.md.template; do
		if a_exists "$f"; then a_keep "$f"; else a_copy "$f" "$f"; fi
	done
	if [ "$a_dog" = yes ]; then
		f=constitution/local-product.md.template
		if a_exists "$f"; then a_keep "$f"; else a_copy "$f" "$f"; fi
	fi
	for d in scripts/docs-conformance/test adapters; do
		if a_exists "$d"; then
			a_keep "$d/"
		else
			a_copy_dir "$d" "$d"
		fi
	done

	# --- 6. automation: additive, with chaining proposals -------------------
	for wf in "$a_kit"/templates/workflows/*; do
		[ -e "$wf" ] || continue
		dest=".github/workflows/$(basename "$wf")"
		if a_exists "$dest"; then
			cmp -s "$wf" "$dest" || a_hit workflow "$dest" chain
		else
			a_copy "templates/workflows/$(basename "$wf")" "$dest"
		fi
	done
	if a_exists ".githooks/pre-push"; then
		cmp -s "$a_kit/.githooks/pre-push" ".githooks/pre-push" ||
			a_hit hook ".githooks/pre-push" chain
	else
		a_copy ".githooks/pre-push" ".githooks/pre-push"
	fi
	a_hookspath=$(git config core.hooksPath 2>/dev/null || true)
	if [ -n "$a_hookspath" ] && [ "$a_hookspath" != ".githooks" ]; then
		# Their config value can carry a space; the verdict token must not. The
		# stable key IS the finding.
		a_hit hook "core.hooksPath" chain
	fi

	# --- the verdict ---------------------------------------------------------
	if [ "$a_collisions" -gt 0 ]; then
		echo ""
		echo "adopt: $a_collisions collision(s) pending — nothing above was resolved for you."
		echo "adopt: resolve each with your human, one approval at a time (the payload document's"
		echo "adopt: existing-repo arm is the walkthrough), then re-run this exact command."
		exit 3
	fi
	# Clean: wire and finish exactly as the new-project arm would. The hook is
	# wired only here, on the clean exit, so a parked adoption leaves the
	# target's own automation exactly as it found it.
	git config core.hooksPath .githooks
	echo "  wired core.hooksPath -> .githooks"
	# No chmod sweep: their files' modes are theirs (a 644 script of theirs must
	# stay 644), and every kit file arrived through cp -p with its own mode.
	echo ""
	echo "adopt: complete. The gate is yours now — run: sh scripts/check.sh"
	echo "adopt: the scratch kit clone at $a_kit can be deleted; its bootstrap has retired itself."
	rm -f "$a_kit/bootstrap.sh"
	exit 0
fi
# F13 END
# ============================================================================

# ============================================================================
# F12 BEGIN — the kit's own bootstrapped state (#f12)
# ----------------------------------------------------------------------------
# The kit repo follows the framework it ships: it has a root AGENTS.md written
# for its own authoring context, the two shims beside it, and a documentation
# set. Every one of those files is sitting in the tree you just created your
# repo from — so they have to come OUT before the idempotency check below, which
# would otherwise read the kit's own manual as evidence that YOUR repo is
# already bootstrapped and refuse every consumer's first run.
#
# Removed and then re-created from the templates, not kept: a manual describing
# how to author the kit is worse than no manual inside a project that is not the
# kit. Everything on this list has a stamped replacement further down (K4, K7),
# which is why the strip is safe rather than lossy — the two-run byte-identity
# check in `tests/self-host.test.sh` is what holds that claim.
#
# The list is FILES, one per line-item, never a directory. `rm -rf docs/adr`
# would take the first ADR a consumer wrote in the window between creating their
# repo and running this script — the exact window in which people write one —
# and an uncommitted one would be gone for good. Deleting only the names the kit
# itself ships means a consumer's `docs/adr/0002-….md` is never in reach of this
# block at all. `tests/self-host.test.sh` section E holds that, and also holds
# that every file in the kit's own `docs/adr/` is named here — a kit ADR added
# later and forgotten shows up as a failing assertion rather than as a leak.
#
# THREE CONDITIONS, all required, because this deletes files without asking:
#   1. constitution/AGENTS.md.template is still here — i.e. this tree has not
#      been stamped yet. A bootstrapped project has no template, so a second run
#      strips nothing and still hits "already exists" below.
#   2. the root manual carries the kit-own SENTINEL. That is what keeps the old
#      safety intact for the one case that would otherwise regress: a repo
#      created from the template whose owner hand-wrote an AGENTS.md BEFORE
#      running bootstrap. Their file has no sentinel, so nothing is removed and
#      they get the same refusal they get today.
#   3. every file about to be deleted is still the kit's — git reports no local
#      modification to it. A consumer who personalized the manual IN PLACE (the
#      sentinel comment survives an edit, so condition 2 cannot see them) gets a
#      refusal naming the file instead of a silent delete and exit 0. Refusing
#      is cheap; silently overwriting an afternoon of local rules is not — the
#      same reasoning as the idempotency check below.
#
# What condition 3 can and cannot see: a modification git has not been told
# about yet — the overwhelmingly common shape, since the file arrived in the
# template's own initial commit and an edit sits in the working tree. It cannot
# see an edit the consumer already COMMITTED (that one is at least recoverable
# from their own history), and it is skipped entirely in a tree with no commits,
# where there is no "as it arrived" to compare against. Ruling those out would
# take a shipped hash of every kit-own file — including `docs/diary.md`, which
# this repo rewrites in every ticket — and a stale hash would refuse EVERY
# consumer's first run. A protection whose failure mode is worse than the bug is
# not worth the maintenance.
KIT_OWN_SENTINEL="agentic-sdlc:kit-own"
KIT_OWN="AGENTS.md CLAUDE.md GEMINI.md docs/diary.md docs/domain-glossary.md docs/adr/INDEX.md docs/adr/0001-the-kit-self-hosts-its-own-constitution.md docs/adr/0002-strategic-means-ousterhout.md docs/adr/NNNN-template.md .github/PULL_REQUEST_TEMPLATE.md"

if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
	have_head=1
else
	have_head=0
fi

# kit_own_touched <path> — true when git can see a local change to a tracked
# kit-own file. Untracked or historyless means "no evidence either way", which
# reads as untouched: see the note above.
kit_own_touched() {
	[ "$have_head" = 1 ] || return 1
	git ls-files --error-unmatch -- "$1" >/dev/null 2>&1 || return 1
	! git diff --quiet HEAD -- "$1"
}

if [ -f "$TEMPLATE" ] && [ -f "$MANUAL" ] && grep -q "$KIT_OWN_SENTINEL" "$MANUAL" 2>/dev/null; then
	# Check the WHOLE set before deleting any of it. A refusal that fires halfway
	# through leaves a half-stripped tree, which is a worse place to stand than
	# either end of the run.
	for f in $KIT_OWN; do
		[ -f "$f" ] || continue
		if kit_own_touched "$f"; then
			die "$f is the kit's own file and you have local changes to it — bootstrap replaces it and would take your edits with it.
  Save what you wrote somewhere outside the repo, restore the file with \`git checkout -- $f\`, and run bootstrap again.
  (Everything the kit ships at that path is re-created from the templates; write your own rules into the manual bootstrap stamps, not into this one.)"
		fi
	done
	for f in $KIT_OWN; do
		if [ -f "$f" ]; then
			rm -f "$f"
			echo "  removed $f (the kit's own; yours is stamped below)"
		fi
	done
	# Only if now empty. K4 re-creates both, and a directory still holding
	# something is holding a consumer's file — `rmdir` refuses, which is the
	# behavior we want and the reason this is not `rm -rf`.
	rmdir docs/adr 2>/dev/null || true
	rmdir docs 2>/dev/null || true
fi
# F12 END
# ============================================================================

# Idempotency: refuse the second run rather than re-stamping over a manual you
# have since edited. Refusing is cheap; silently overwriting a week of local
# rules is not.
[ -f "$MANUAL" ] &&
	die "$MANUAL already exists — this repo looks bootstrapped already. Delete $MANUAL first if you really mean to re-stamp it."
# Same reasoning one level down: a shim is written unconditionally, so a
# pre-existing file at that path would be destroyed. If you arrived here with a
# hand-written CLAUDE.md, its content is the thing worth keeping — move it into
# the manual yourself, then delete it and re-run.
for shim in $SHIMS; do
	if [ -e "$shim" ]; then
		die "$shim already exists, and bootstrap would overwrite it with a one-line shim. Move its content into $MANUAL, delete $shim, then re-run."
	fi
done
[ -f "$TEMPLATE" ] ||
	die "$TEMPLATE not found. Either this is not an agentic-sdlc repo, or bootstrap already ran."

# --- gather values ----------------------------------------------------------
# Options and positionals are parsed in one pass so a flag may sit before or
# after the name. An UNKNOWN option is a hard error rather than a positional:
# `--with-dogfod` silently becoming the project name is the kind of typo you
# only discover in the stamped manual a week later.
name=""
description=""
have_name=0
have_desc=0
# ask | yes | no — resolved once, in the F6 block below.
dogfood_choice=ask

# take_positional <value> — name first, then description, then it is an error.
take_positional() {
	if [ "$have_name" = 0 ]; then
		name=$1
		have_name=1
	elif [ "$have_desc" = 0 ]; then
		description=$1
		have_desc=1
	else
		die "too many arguments. Usage: sh bootstrap.sh [--with-dogfood|--no-dogfood] \"My Project\" \"One line.\""
	fi
}

while [ $# -gt 0 ]; do
	case "$1" in
	--with-dogfood) dogfood_choice=yes ;;
	--no-dogfood) dogfood_choice=no ;;
	--) # everything after this is positional, even if it looks like a flag
		shift
		while [ $# -gt 0 ]; do
			take_positional "$1"
			shift
		done
		break
		;;
	-*) die "unknown option '$1'. Supported: --with-dogfood, --no-dogfood." ;;
	*) take_positional "$1" ;;
	esac
	shift
done

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

# ============================================================================
# F6 BEGIN — the optional /dogfood skill (#27)
# ----------------------------------------------------------------------------
# Everything F6 does lives in this block and in one extra `-e` on the stamp
# below. Same discipline as K4/K5/K7: bootstrap.sh is touched by several kit
# tickets, and a named block is the difference between a merge and a rewrite.
#
# WHY THIS ONE IS OPTIONAL AND THE OTHERS ARE NOT. Every other skill
# works on the day the repo is created — they operate on specs, tickets,
# diffs, branches and worktrees, all of which a one-hour-old project already
# has. `/dogfood` operates on a RUNNING PRODUCT: it walks declared personas
# through a real user-facing surface. A project with no such surface would
# inherit a command it cannot run and a row on the manual's map pointing at it,
# which is the exact failure the docs gate exists to prevent one level up.
#
# ONE QUESTION, and only when there is somebody to ask. With no terminal the
# answer is SKIP, because the two mistakes are not symmetric: a project that
# skipped it copies the skill back out of the kit in a minute, while a project
# that took it silently carries a dead command until someone notices.
#
# WHAT "SKIP" REMOVES: the skill directory (the way KIT_ONLY files go, further
# down), the product article that exists only to feed it, and — at stamp time,
# below — the manual's rows about it. The shims are untouched: they hold one
# import line and no rules, so there is nothing in them to be conditional about.
if [ "$dogfood_choice" = ask ]; then
	if [ -t 0 ]; then
		printf %s "$DOGFOOD_PROMPT"
		read -r dogfood_answer || dogfood_answer=""
		case "$dogfood_answer" in
		[Yy] | [Yy][Ee][Ss]) dogfood_choice=yes ;;
		*) dogfood_choice=no ;;
		esac
	else
		dogfood_choice=no
	fi
fi

# "Yes" is only answerable if the skill is actually in this tree. If somebody
# pruned it before running bootstrap, stamping its rows anyway would hand the
# project a manual whose own gate rejects it on the first push — so say what
# happened and fall back to skipping.
if [ "$dogfood_choice" = yes ] && [ ! -f .agents/skills/dogfood/SKILL.md ]; then
	echo "  note: /dogfood was requested but .agents/skills/dogfood/ is not in this tree — skipping it" >&2
	dogfood_choice=no
fi

# The stamp-time filter for the manual's optional rows. The template marks them
# with a matched pair of HTML comments; the marker lines themselves ALWAYS go,
# so a project never inherits scaffolding it did not ask about, and when the
# skill is declined the lines between them go too.
if [ "$dogfood_choice" = yes ]; then
	dogfood_filter=$DOGFOOD_MD_KEEP
else
	dogfood_filter=$DOGFOOD_MD_STRIP
fi
# F6 END
# ============================================================================

# A stamped value containing the placeholder syntax would defeat the gate, and a
# `/` or `&` would corrupt the sed replacement below.
case "$name$description" in
*'{{'* | *'}}'*) die "project name/description must not contain '{{' or '}}'." ;;
esac

# --- stamp ------------------------------------------------------------------
# esc/esc_js live at the top of the file — both arms stamp with them.
name_esc=$(esc "$name")
description_esc=$(esc "$description")
name_js_esc=$(esc "$(esc_js "$name")")

sed \
	-e "s|$(mark PROJECT_NAME)|$name_esc|g" \
	-e "s|$(mark PROJECT_DESCRIPTION)|$description_esc|g" \
	-e "$dogfood_filter" \
	"$TEMPLATE" >"$MANUAL"
rm -f "$TEMPLATE"
echo "  stamped $MANUAL"

# ============================================================================
# K7 BEGIN — the tool shims (#16)
# ----------------------------------------------------------------------------
# One manual, several tool-specific filenames. Each shim is written from
# scratch — never stamped, never appended to — and holds exactly two lines: a
# comment saying what it is, and the import line the tool resolves.
#
# The comment is an HTML comment on purpose: it renders as nothing and reads as
# metadata rather than as a rule, which is the whole point. A shim that can hold
# a rule stops being a shim.
#
# The docs gate enforces the shape (`shim-invalid` in the docs-conformance
# harness), so a shim that grows a second instruction fails the push rather than
# quietly becoming a rival manual.
for shim in $SHIMS; do
	shim_body >"$shim"
	echo "  wrote   $shim (shim -> $MANUAL)"
done
# K7 END
# ============================================================================

if [ -f "$VOCAB_TEMPLATE" ]; then
	sed -e "s|$(mark PROJECT_NAME)|$name_js_esc|g" "$VOCAB_TEMPLATE" >"$VOCAB"
	rm -f "$VOCAB_TEMPLATE"
	echo "  stamped $VOCAB"
fi

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
# reconcile them — same reasoning as constitution/AGENTS.md.template above.
DOCS_TEMPLATES="templates/docs"
today=$(date +%Y-%m-%d)
today_esc=$(esc "$today")

# stamp <source> <destination>
stamp() {
	mkdir -p "$(dirname "$2")"
	sed \
		-e "s|$(mark PROJECT_NAME)|$name_esc|g" \
		-e "s|$(mark PROJECT_DESCRIPTION)|$description_esc|g" \
		-e "s|$(mark BOOTSTRAP_DATE)|$today_esc|g" \
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

# --- the declined optional skill (F6, #27) ----------------------------------
# Removed exactly the way the kit-authoring files below are: no archive, no
# `.disabled` suffix, no commented-out row left in the manual. A skill that is
# half-present is worse than an absent one — the manual's map and the skills
# directory are supposed to be the same set, and the gate checks it.
#
# The product article goes too: it exists to hold the persona/surface
# declaration `/dogfood` reads, so on its own it would be an unfilled template
# nothing points at.
if [ "$dogfood_choice" != yes ]; then
	# -L as well as -e: once the canonical dir is gone, the .claude/skills
	# symlink is dangling, and a bare -e follows it to "no".
	for f in .agents/skills/dogfood .claude/skills/dogfood constitution/local-product.md.template; do
		if [ -e "$f" ] || [ -L "$f" ]; then
			rm -rf "$f"
			echo "  removed $f (/dogfood not selected)"
		fi
	done
fi

# The gate policy's dogfood-only exemption travels with the skill: the token
# it exempts names the report directory only that skill ever creates, and a
# declined tree must not mention the command anywhere (the opt-in suite holds
# it to that). Same marker-pair contract as the manual's optional rows, in
# the comment syntax this file speaks: declined, the whole block goes;
# accepted, only the scaffolding markers go.
dogfood_cfg=scripts/docs-conformance/config.mjs
if [ -f "$dogfood_cfg" ]; then
	# Both markers or neither: the decline branch's RANGE delete would run to
	# end-of-file on a lone BEGIN — a truncated policy file with exit 0, the
	# silent-data-loss shape §11 exists for. A lone marker is a broken pair
	# somebody edited; refuse loudly rather than guess which half they meant.
	dogfood_marks=$(grep -c '// DOGFOOD:\(BEGIN\|END\)' "$dogfood_cfg" || true)
	case "$dogfood_marks" in
	0) ;; # nothing to stamp — already consumed, or a consumer's own config
	2)
		if [ "$dogfood_choice" = yes ]; then
			sed "$DOGFOOD_JS_KEEP" "$dogfood_cfg" >"$dogfood_cfg.stamp" &&
				mv "$dogfood_cfg.stamp" "$dogfood_cfg"
		else
			sed "$DOGFOOD_JS_STRIP" "$dogfood_cfg" >"$dogfood_cfg.stamp" &&
				mv "$dogfood_cfg.stamp" "$dogfood_cfg"
		fi
		;;
	*) die "$dogfood_cfg carries a broken DOGFOOD marker pair ($dogfood_marks marker(s)) — fix the pair before stamping" ;;
	esac
fi

# --- clean up the kit's own scaffolding -------------------------------------
for f in $KIT_ONLY; do
	if [ -e "$f" ]; then
		rm -f "$f"
		echo "  removed $f (kit-authoring only)"
	fi
done
# Only if now empty — a project that already has its own workflows keeps them.
rmdir setup tests .github/workflows .github 2>/dev/null || true

# --- next steps -------------------------------------------------------------
cat <<EOF

Bootstrapped: $name

Next:
  1. sh scripts/check.sh          run the docs gate — it should pass now
  2. read AGENTS.md               it is loaded into every agent session; every
                                  line is yours to keep, cut, or replace.
                                  CLAUDE.md and GEMINI.md are one-line shims
                                  importing it — never edit those
  3. fill in the two articles     constitution/local-engineering.md.template
                                  constitution/local-workflow.md.template
                                  replace the marks, drop the .template suffix,
                                  then point AGENTS.md's article layer at them.
                                  The engineering article includes the
                                  mutation decision: name a tool and its
                                  on-demand command, or "none" with the reason —
                                  never leave it to silence (adapters/ holds
                                  worked wirings to copy the shape from).
                                  Its Architecture section carries the other
                                  day-one decision, the design brief: run
                                  /design-brief before the first feature diff
                                  — it designs the shape twice and records
                                  paradigm, style and context map after your
                                  yes, or "none" with the reason on each
  4. edit scripts/guards.config.sh
                                  the TDD pairing guard is INACTIVE until you
                                  set GUARD_SOURCE_RE to match your source
                                  trees. Until then it warns on every push and
                                  blocks nothing — on purpose, because it cannot
                                  know your layout and will not guess it.
  5. edit scripts/agents.config.sh
                                  map the four capability tiers (planner,
                                  implementer, mechanical, reviewer) onto your
                                  provider's model ids. Unmapped is a working
                                  state: every tier then runs on the session's
                                  own model and the resolver warns once. The
                                  kit ships no model id on purpose — they rot.
  6. fill in docs/diary.md        the "Current state" block at the top is what
                                  an agent reads first; README.md is stamped
                                  but thin — make it say what $name is
  7. git add -A && git commit     bootstrap committed nothing on purpose
  8. start your next agent session IN THIS DIRECTORY
                                  a harness discovers skills from the directory
                                  a session starts in, so the slash commands the
                                  manual's chain names are invisible to a session
                                  launched a level above. In Claude Code, /cd
                                  moves a live session here (2.1.246 or newer);
                                  --add-dir does it at startup

Both gates run automatically before every push (.githooks/pre-push), each with
its own loud bypass: PUSH_WITHOUT_DOCS=1 and PUSH_WITHOUT_TESTS=1. The matching
CI workflows were installed into .github/workflows/, so a local bypass only
defers the failure. Commit linting ships DISABLED as
.github/workflows/commitlint.yml.example — rename it once you have a runner.

Cross-provider AI review ships DISABLED the same way, as
.github/workflows/ai-review.example.yml: two advisory reviewers from two
vendors, firing on PR open. Add one or both provider secrets, then rename the
file — a provider with no secret skips itself, so one key is enough to start.
This is the review \`/implement\` requests when it delivers a pull request.

Collaborators cloning this repo run \`git config core.hooksPath .githooks\`
once — hooks path is per-clone config and cannot be committed.

With node on PATH the gate runs the full docs-conformance harness
(scripts/docs-conformance); without it, a reduced POSIX fallback runs and says
so. The policy it enforces is data you own: scripts/docs-conformance/config.mjs
and scripts/docs-conformance/local-vocabulary.mjs.

The shared layer (see VERSION) is copied verbatim from the kit and is not
edited here. Everything else is yours.
EOF

# ============================================================================
# F6 BEGIN — what the dogfood answer meant (#27)
# ----------------------------------------------------------------------------
# Say it either way. "Nothing happened" is not a report: a project that skipped
# the skill needs to know it can still have it, and one that took it needs to
# know the skill will not run until the declaration is filled in.
if [ "$dogfood_choice" = yes ]; then
	cat <<'EOF'

/dogfood is installed, and it does NOT work yet. It walks your personas through
your real user-facing surface, and both of those are yours to declare: fill in
the DOGFOOD DECLARATION in constitution/local-product.md.template, drop the
.template suffix, and point AGENTS.md's article layer at it — the same three
steps as the other two local articles. Until then the skill stops and says so,
which is the correct behaviour: a guessed persona produces a report about a
user who does not exist.
EOF
else
	cat <<'EOF'

/dogfood was NOT installed — it needs a runnable user-facing surface, and the
default is to skip. Nothing is lost: copy .agents/skills/dogfood/ and
constitution/local-product.md.template out of the kit on the day you have one,
and add a row for it to AGENTS.md's quick reference.
EOF
fi
# F6 END
# ============================================================================

# ============================================================================
# K5 BEGIN — the adapters pointer (#7)
# ----------------------------------------------------------------------------
# adapters/ is NOT copied, stamped or removed by this script (see KIT_ONLY
# above). It arrives dormant. All this block does is TELL you it is there —
# without a mention, a fresh project contains a directory nobody introduced,
# which is how reference material gets mistaken for a description of the
# project. A pointer, not an install.
if [ -d adapters ]; then
	cat <<'EOF'
adapters/ holds worked reference wirings — one directory per stack, copied from
a real project with the reasoning left in. Nothing in it runs, nothing in it was
stamped, and no gate reads it: it is documentation you can copy from on the day
you configure a guard. Read adapters/README.md. If no adapter matches your
stack, `rm -rf adapters` is the right answer.
EOF
fi
# K5 END
# ============================================================================

# --- self-delete ------------------------------------------------------------
# Last, so a failure above leaves bootstrap runnable.
rm -f "$root/bootstrap.sh"
