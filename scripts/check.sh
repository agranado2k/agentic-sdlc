#!/bin/sh
# The docs gate.
#
# Shared invariant §8: "a rule written in a document that nothing checks decays
# into a lie, and stale standing instructions are worse than absent ones."
# This script is that enforcement for a bootstrapped project.
#
# ---------------------------------------------------------------------------
# TWO ENGINES, ONE GATE — and why
# ---------------------------------------------------------------------------
# The kit's core is language-agnostic on purpose: a project that has not chosen
# a toolchain yet must still inherit a working gate on day one. But the
# reference checks worth having (slash-command resolution, the article layer,
# reachability, the portability deny-list) are real parsing work, and POSIX sh
# is the wrong tool for them — the shell version of the path check below is a
# word-splitter that cannot tell a code span from a fence.
#
# So the gate is split by what each check actually needs:
#
#   ALWAYS, in POSIX sh — the checks that are cheap AND exact in shell:
#     1. placeholder-unstamped  no double-brace mark survived bootstrap
#     2. shared-layer-missing   every file VERSION lists still exists
#     3. root-manual-missing    the root agent manual (AGENTS.md) exists at all
#     4. agent-type-model       no adapter agent type names a model
#
#   (3) stays in shell rather than moving into the harness on purpose: the
#   harness treats an absent manual as "this repo does not model that layer" and
#   stays silent, which is right for a validator run over fixture trees and
#   wrong for a gate. A bootstrapped project without a root manual is broken,
#   whichever engine is available.
#
#   REFERENCES — delegated to the node harness (scripts/docs-conformance) when
#   node is on PATH. That is the real validator: layered manuals, command
#   resolution, article reachability, package-relative paths, and the
#   portability deny-list on the shared article.
#
#   NO NODE? A reduced POSIX fallback runs instead: repo paths named in code
#   spans of the root manual and the articles must exist, and every living
#   requirement must be named by a test (the living-spec rule's twin, which
#   reads its policy from the harness's config.mjs). It prints a NOTICE
#   saying exactly what it is NOT checking, because a gate that quietly
#   downgrades itself is how a project ends up believing in coverage it lost.
#
# Set DOCS_CHECK_NO_NODE=1 to force the fallback (the kit's demo does, to prove
# both engines).
#
# Exit: 0 clean, 1 violations found, 2 could not run. A clean run may still
# write the harness's advisory block to stderr — advisories are relayed on a
# green gate and never change the exit code.

set -u

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root=$(pwd)
cd "$repo_root" || {
	echo "check.sh: cannot enter repo root '$repo_root'" >&2
	exit 2
}

HARNESS="scripts/docs-conformance/index.mjs"
# The header the harness prints above its advisory block. Keep this in step
# with `scripts/docs-conformance/index.mjs` — two engines, one contract; the
# advisory suite goes red if the two drift.
advisory_header="WARN  docs conformance"

# Findings go to a tempfile rather than a variable because every scan below
# is a `while … done` fed by a pipe, which POSIX sh runs in a subshell: a flag
# set inside it is lost when the loop ends. The file is the one channel that
# survives; "any finding at all" is then the file's size (see posix_failed).
vfile=$(mktemp) || exit 2
trap 'rm -f "$vfile" "$vfile.specs" "$vfile.cited" "$vfile.body" "$vfile.seen" "$vfile.types" "$vfile.warn"' EXIT INT TERM HUP

# report <rule> <file> <message> <hint>
report() {
	printf '  [%s] %s\n    x %s\n      -> %s\n\n' "$1" "$2" "$3" "$4" >>"$vfile"
}

# The reviewed surface. `git ls-files -co --exclude-standard` is tracked files
# PLUS untracked-but-not-ignored ones, which is exactly right for a project that
# has just been bootstrapped and has not committed yet, while still respecting
# .gitignore so build output never reaches the gate.
list_files() {
	if git rev-parse --git-dir >/dev/null 2>&1; then
		git ls-files -co --exclude-standard
	else
		find . -type f ! -path './.git/*' | sed 's|^\./||'
	fi
}

# ---------------------------------------------------------------------------
# 1. No unstamped placeholders  (always, POSIX)
# ---------------------------------------------------------------------------
# The pattern is assembled from variables so this script does not itself contain
# the literal mark. Otherwise the gate would have to exempt its own source, and
# a gate with a blind spot over itself is not a gate.
ob='{'
cb='}'
placeholder_re="${ob}${ob}[A-Z][A-Z0-9_]*${cb}${cb}"

list_files | while IFS= read -r f; do
	[ -f "$f" ] || continue
	# `*.template` files are SUPPOSED to carry placeholders — they are the
	# unstamped source bootstrap (or you, by hand) reads. Everything else is
	# stamped output and is held to it.
	case "$f" in
	*.template) continue ;;
	esac
	grep -n -I "$placeholder_re" "$f" 2>/dev/null | while IFS= read -r hit; do
		report "placeholder-unstamped" "$f:${hit%%:*}" \
			"still contains an unstamped placeholder" \
			"Stamp it, or delete the line. An agent loading this file loads the hole."
	done
done

# ---------------------------------------------------------------------------
# 2. The shared layer named in VERSION is intact  (always, POSIX)
# ---------------------------------------------------------------------------
if [ ! -f VERSION ]; then
	report "shared-layer-missing" "VERSION" \
		"the shared-layer manifest does not exist" \
		"Restore VERSION from the kit — without it nothing records which files are shared layer, or at which version."
else
	shared_version=$(sed -n 's/^shared-layer:[[:space:]]*//p' VERSION | head -1)
	[ -n "$shared_version" ] || report "shared-layer-missing" "VERSION" \
		"has no 'shared-layer: <version>' line" \
		"The manifest must state the version it pins, or the update recipe has no anchor to diff from."

	# One grammar for the manifest, shared with bootstrap and the suites; the
	# module is itself manifest-listed, so a consumer's gate has it — and the
	# gate fails CLOSED without it: a missing module is a missing shared file,
	# and a module that defines nothing is a broken gate, never a silent pass.
	manifest_lib="$repo_root/scripts/manifest.lib.sh"
	if [ ! -r "$manifest_lib" ]; then
		report "shared-layer-missing" "scripts/manifest.lib.sh" \
			"the manifest parser is missing, so the shared-layer check cannot run" \
			"Restore scripts/manifest.lib.sh from the kit at the pinned version; scripts/check.sh sources it."
	else
		# shellcheck disable=SC1090
		. "$manifest_lib"
		command -v manifest_section >/dev/null 2>&1 || {
			echo "check.sh: scripts/manifest.lib.sh did not define manifest_section — the gate cannot run" >&2
			exit 2
		}
	fi
	command -v manifest_section >/dev/null 2>&1 && manifest_section files <VERSION | while IFS= read -r shared; do
		[ -e "$shared" ] && continue
		report "shared-layer-missing" "$shared" \
			"is listed in VERSION as shared layer but does not exist" \
			"Restore it from the kit at the pinned version. Shared-layer files are copied verbatim, not edited or deleted locally."
	done
fi

# ---------------------------------------------------------------------------
# 3. The root agent manual exists  (always, POSIX)
# ---------------------------------------------------------------------------
# AGENTS.md, not a tool-specific filename: one manual, and the tool-specific
# files beside it are shims that import it. The harness checks the shims' shape
# (`shim-invalid`); this shell check owns only the manual's existence, because
# an absent manual breaks the repo whichever engine is available.
[ -f AGENTS.md ] || report "root-manual-missing" "AGENTS.md" \
	"the root agent manual does not exist" \
	"Run bootstrap.sh to stamp constitution/AGENTS.md.template into AGENTS.md. Every other layer hangs off this one, and CLAUDE.md / GEMINI.md are only shims importing it."

# ---------------------------------------------------------------------------
# 4. No agent type names a model  (always, POSIX)
# ---------------------------------------------------------------------------
# An adapter's agent types (adapters/<harness>/agents/*.md) carry tools, never
# a model: the model is the tier resolver's answer at spawn time, so a model
# line in a type is a second mapping that outranks the policy file, and an
# identifier anywhere in one rots on a vendor's schedule. Two shapes fail: a
# `model:` key in the frontmatter, whatever its value, and anything shaped
# like a model identifier anywhere in the file. The key is matched in any
# case and spacing, since a spelling the gate missed may still be read.
model_id_re='(claude|gpt|gemini|llama|mistral|sonnet|opus|haiku|fable)-[0-9]|claude-[a-z]+-[0-9]|(opus|sonnet|haiku|fable) [0-9]'
list_files | grep -E '^adapters/[^/]+/agents/[^/]+\.md$' | while IFS= read -r f; do
	[ -f "$f" ] || continue
	line=$(awk 'NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
		fm && /^---[[:space:]]*$/ { exit }
		fm && tolower($0) ~ /^[[:space:]]*model[[:space:]]*:/ { print NR; exit }' "$f")
	[ -n "$line" ] && report "agent-type-model" "$f:$line" \
		"an agent type carries a model line" \
		"Delete it. The spawn passes the model the tier resolver printed, or none to inherit the session's; the type declares tools only."
	grep -n -i -E "$model_id_re" "$f" 2>/dev/null | while IFS= read -r hit; do
		report "agent-type-model" "$f:${hit%%:*}" \
			"an agent type names a model identifier" \
			"Name the tier, never the model: the identifier belongs in the project's tier policy file, which the resolver reads."
	done
done

# ---------------------------------------------------------------------------
# 5. References — the node harness, or the reduced POSIX fallback
# ---------------------------------------------------------------------------
harness_out=""
harness_status=0
engine="fallback"

if [ "${DOCS_CHECK_NO_NODE:-}" != "1" ] && [ -f "$HARNESS" ] && command -v node >/dev/null 2>&1; then
	engine="docs harness"
	harness_out=$(node "$HARNESS" "$repo_root" 2>&1)
	harness_status=$?
fi

if [ "$engine" = "fallback" ]; then
	# The requirement grammar and the fence rule: scripts/requirement.lib.sh,
	# their one home (#545, #557), read by the path check (fence_strip) and the
	# living-spec twin below. The reduced form fails CLOSED without it, the
	# same footing as the manifest parser above: a missing file is a missing
	# shared file, and a file that defines nothing is a broken gate.
	req_lib="$repo_root/scripts/requirement.lib.sh"
	if [ ! -r "$req_lib" ]; then
		report "shared-layer-missing" "scripts/requirement.lib.sh" \
			"the requirement grammar is missing, so neither the path check nor the living-spec check can run" \
			"Restore scripts/requirement.lib.sh from the kit at the pinned version; scripts/check.sh sources it."
	else
		# shellcheck disable=SC1090
		. "$req_lib"
		for fn in req_spec_ids fence_strip; do
			command -v "$fn" >/dev/null 2>&1 || {
				echo "check.sh: scripts/requirement.lib.sh did not define $fn — the gate cannot run" >&2
				exit 2
			}
		done
	fi

	# Reduced form. Path roots: the trees a manual is allowed to point into. A
	# backticked token that starts with one of these roots followed by `/` is
	# a repo path and must resolve; anything else is left alone. A root may
	# itself carry a `/` (`.agents/skills`), exactly as the harness's do.
	#
	# This list IS `claudeMdRefs.pathRoots` in scripts/docs-conformance/
	# config.mjs, entry for entry — two engines, one policy, and the
	# duplication is the price of running without a runtime. The harness's
	# list is the truth; tests/gate-path-roots.test.sh fails when they differ.
	path_roots='constitution scripts docs tests adapters .githooks .github .agents/skills .claude/hooks .claude/skills .claude/constitution'

	scan_manual() {
		manual=$1
		[ -f "$manual" ] || return 0
		command -v fence_strip >/dev/null 2>&1 || return 0 # no grammar: reported above
		# Strip fenced blocks (their ``` markers would be read as span
		# delimiters), pull out every `code span`, then split spans into words so
		# a span like `sh scripts/check.sh` still yields the path.
		fence_strip "$manual" |
			grep -o '`[^`]*`' |
			tr -d '`' |
			tr ' \t' '\n\n' |
			sort -u |
			while IFS= read -r token; do
				case "$token" in
				*/*) ;;
				*) continue ;; # no separator: not a path
				esac
				# Globs are patterns, not paths — the harness ignores them too.
				case "$token" in
				*'*'* | *'?'*) continue ;;
				esac
				is_root=0
				for r in $path_roots; do
					case "$token" in
					"$r"/*) is_root=1 && break ;;
					esac
				done
				[ "$is_root" = 1 ] || continue
				# Trailing punctuation from prose, and trailing slash on dirs.
				clean=$(printf '%s' "$token" | sed 's/[.,;:)]*$//')
				if [ -e "$clean" ] || [ -e "${clean%/}" ]; then
					continue
				fi
				report "path-missing" "$manual" \
					"references \`$token\` but that path does not exist" \
					"Create it or remove the reference — the manual must describe reality, not intent."
			done
	}

	scan_manual AGENTS.md
	for article in constitution/*.md; do
		[ -e "$article" ] || continue
		case "$article" in
		constitution/shared-invariants.md | constitution/shared-code-craft.md) continue ;; # shared layer: portability is the harness's job
		esac
		scan_manual "$article"
	done

	# The living-spec rule's POSIX twin (validators/living-spec.mjs, the kit's ADR-0012
	# clause 10): every requirement — a line opening `R<n>.` outside a fence in
	# <specsDir>/<area>.md — must be named, as `<area>/R<n>`, by a file the
	# test globs match. Vacuous with no living spec. The GRAMMAR is sourced
	# from scripts/requirement.lib.sh, its one home, which the validator's
	# fixture tests hold the harness's patterns equal to (#545) — sourced at
	# the top of this reduced form, and failing CLOSED without it.
	# The POLICY is not copied here at all: the specs directory and the globs
	# are read BY TEXT from config.mjs's `livingSpec` block, which is why that
	# block keeps them literal. No block (a config older than the rule) is no
	# globs, so a requirement fails with the hint that names the policy — the
	# harness's answer too. One exclusion is the engine's, not the policy's: a
	# file under the harness's own tree, scripts/docs-conformance/, never
	# cites, in both engines (#561).
	ls_cfg="scripts/docs-conformance/config.mjs"
	specs_dir="" spec_globs=""
	if [ -f "$ls_cfg" ]; then
		specs_dir=$(sed -n 's/^[[:space:]]*specsDir:[[:space:]]*"\([^"]*\)".*/\1/p' "$ls_cfg" | head -1)
		spec_globs=$(awk '/^[[:space:]]*testGlobs:[[:space:]]*\[/ { on = 1; next } on && /^[[:space:]]*\]/ { exit } on { print }' "$ls_cfg" |
			sed -n 's/^[[:space:]]*"\([^"]*\)",\{0,1\}[[:space:]]*$/\1/p')
	fi
	[ -n "$specs_dir" ] || specs_dir="docs/specs"
	: >"$vfile.specs"
	command -v req_spec_ids >/dev/null 2>&1 && for spec in "$specs_dir"/*.md; do
		[ -f "$spec" ] || continue
		ids=$(req_spec_ids "$spec")
		[ -n "$ids" ] || continue
		area=$(basename "$spec" .md)
		if ! printf '%s\n' "$area" | LC_ALL=C grep -Eqx "$REQ_AREA_ERE"; then
			report "living-spec-area-invalid" "$spec" \
				"holds requirements, but \"$area\" is not an area name — one lowercase token, $REQ_AREA_ERE" \
				"Rename the file to its area (docs/specs/<area>.md); its requirements are cited as <area>/R<n>, so an area that cannot be cited cannot be held to a test."
			continue
		fi
		for rid in $ids; do
			printf '%s\t%s/%s\n' "$spec" "$area" "$rid" >>"$vfile.specs"
		done
	done
	if [ -s "$vfile.specs" ]; then
		# The cited names, from every file a glob matches. `set -f` keeps the
		# unquoted glob list from expanding against the tree: each one is a
		# `case` pattern, where `*` crosses `/` exactly as the harness reads it.
		# Both boundaries are the harness's too: the match swallows one letter,
		# digit, `_`, `-` or `/` before the id and one letter, digit, `_`, or
		# `.` and a digit after it, and the second grep, anchored at both ends,
		# drops it (`<a>` is any area, #561) — `X<a>/R1`, `sub/<a>/R1`, `<a>/R1abc` and
		# `<a>/R1.5` cite nothing, and `<a>/R1-<a>/R2` cites R1 alone.
		list_files | {
			set -f
			_ifs=$IFS
			IFS='
'
			while read -r f; do
				[ -f "$f" ] || continue
				# The harness's own tree cites nothing, whatever the globs
				# match (#561, the validator's header says why).
				case "$f" in
				scripts/docs-conformance/*) continue ;;
				esac
				for g in $spec_globs; do
					# shellcheck disable=SC2254  # the glob is a pattern on purpose
					case "$f" in
					$g)
						LC_ALL=C grep -o -h -I -E "$REQ_CITED_TOKEN_ERE" "$f" 2>/dev/null
						break
						;;
					esac
				done
			done
			IFS=$_ifs
		} | LC_ALL=C grep -x -E "$REQ_CITED_NAME_ERE" | sort -u >"$vfile.cited"
		while IFS='	' read -r spec name; do
			grep -qxF -- "$name" "$vfile.cited" && continue
			report "living-spec-untested" "$spec" \
				"$name is named by no test" \
				"Name \`$name\` in a test (its name, or a comment beside it) in a file livingSpec.testGlobs in scripts/docs-conformance/config.mjs matches, or retire the requirement with a REMOVED delta. A living requirement no test names is a claim (shared invariant §8)."
		done <"$vfile.specs"
	fi

	# The skill-ceiling rule's POSIX twin (validators/skill-ceiling.mjs): a
	# SKILL.md over the byte ceiling config.mjs's `skillCeilings` block
	# declares for it fails, naming the file, its size and the ceiling. The
	# block is read BY TEXT, one `"<path>": <bytes>,` per line, which is why
	# config.mjs keeps it literal. No block is no ceilings; an absent file is
	# silent — the harness's answers too.
	if [ -f "$ls_cfg" ]; then
		awk '/^const skillCeilings = \{/ { on = 1; next } on && /^\};/ { exit } on { print }' "$ls_cfg" |
			sed -n 's/^[[:space:]]*"\([^"]*\)":[[:space:]]*\([0-9][0-9]*\),\{0,1\}[[:space:]]*$/\1 \2/p' |
			while read -r skill ceiling; do
				[ -f "$skill" ] || continue
				size=$(wc -c <"$skill" | tr -d ' ')
				[ "$size" -gt "$ceiling" ] || continue
				report "skill-over-ceiling" "$skill" \
					"is $size bytes, over its ceiling of $ceiling bytes" \
					"Move the parts only a worker or a rare branch needs into files the SKILL.md names, or raise the ceiling in config.mjs's skillCeilings — a visible policy diff."
			done
	fi

	# The skill-dated rule's POSIX twin (validators/skill-dated.mjs, #678): a
	# SKILL.md whose fence-stripped body matches one of the patterns
	# config.mjs's `skillDated` block declares fails, once per distinct
	# token, unless `<skill>|<token>` is on its knownExceptions. Every skill
	# home is read — the configured one (claudeMdRefs' skillsDir), then
	# .agents/skills and .claude/skills — once per skill name, the first home
	# winning, as the harness's skillHomes does. The block is read BY TEXT,
	# one `"<value>",` per line — its patterns are EREs with no backslash, so
	# grep reads the text node compiles. No block is no rule — the harness's
	# answer too.
	if [ -f "$ls_cfg" ] && command -v fence_strip >/dev/null 2>&1; then
		sd_block=$(awk '/^const skillDated = \{/ { on = 1; next } on && /^\};/ { exit } on { print }' "$ls_cfg")
		# sd_list <key> — the quoted values of one array in the block.
		sd_list() {
			printf '%s\n' "$sd_block" | awk -v k="$1" '$0 ~ "^[[:space:]]*" k ":[[:space:]]*\\[" { on = 1; next } on && /^[[:space:]]*\]/ { exit } on { print }' |
				sed -n 's/^[[:space:]]*"\(.*\)",\{0,1\}[[:space:]]*$/\1/p'
		}
		sd_dir=$(sed -n 's/^[[:space:]]*skillsDir:[[:space:]]*"\([^"]*\)".*/\1/p' "$ls_cfg" | head -1)
		sd_patterns=$(sd_list patterns)
		sd_known=$(sd_list knownExceptions)
		if [ -n "$sd_patterns" ]; then
			: >"$vfile.seen"
			for skill in "${sd_dir:-.agents/skills}"/*/SKILL.md .agents/skills/*/SKILL.md .claude/skills/*/SKILL.md; do
				[ -f "$skill" ] || continue
				sd_name=${skill%/SKILL.md}
				sd_name=${sd_name##*/}
				grep -qxF -- "$sd_name" "$vfile.seen" && continue
				printf '%s\n' "$sd_name" >>"$vfile.seen"
				fence_strip "$skill" >"$vfile.body"
				printf '%s\n' "$sd_patterns" | while IFS= read -r pat; do
					grep -o -E -- "$pat" "$vfile.body" 2>/dev/null
				done | sort -u | while IFS= read -r token; do
					printf '%s\n' "$sd_known" | grep -qxF -- "$sd_name|$token" && continue
					report "skill-dated-evidence" "$skill" \
						"carries dated kit evidence \"$token\" — a consumer reads the kit's dates and history as its own" \
						"Keep the rule and drop the evidence: the dates, counts and amendments belong in the diary or a decision record, which the skill may name (the kit's ADR-NNNN)."
				done
			done
		fi
	fi

	# The supersession rule's POSIX twin (validators/supersession.mjs, #683):
	# a record `<recordsDir>/NNNN-*.md` whose "Supersedes / amends" line has a
	# `;`-separated clause opening "supersedes" (any case) obliges every
	# ADR-NNNN that clause names — itself and a record with no file aside — to
	# carry its id on the "Superseded by" line, unless
	# `<superseded>|<superseding>`, both by file name without .md, is on the
	# knownExceptions. The block is read
	# BY TEXT from config.mjs's `supersession` block; no block is no rule.
	if [ -f "$ls_cfg" ]; then
		ss_block=$(awk '/^const supersession = \{/ { on = 1; next } on && /^\};/ { exit } on { print }' "$ls_cfg")
		ss_dir=$(printf '%s\n' "$ss_block" | sed -n 's/^[[:space:]]*recordsDir:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
		ss_known=$(printf '%s\n' "$ss_block" | awk '/^[[:space:]]*knownExceptions:[[:space:]]*\[/ { on = 1; next } on && /^[[:space:]]*\]/ { exit } on { print }' |
			sed -n 's/^[[:space:]]*"\(.*\)",\{0,1\}[[:space:]]*$/\1/p')
		if [ -n "$ss_dir" ] && [ -d "$ss_dir" ]; then
			for rec in "$ss_dir"/[0-9][0-9][0-9][0-9]-*.md; do
				[ -f "$rec" ] || continue
				ss_self=ADR-$(basename "$rec" | cut -c1-4)
				sed -n 's/^- \*\*Supersedes \/ amends\*\*:\(.*\)$/\1/p' "$rec" | head -1 | tr ';' '\n' |
					sed 's/^[[:space:]]*//' | grep -iE '^supersedes([^[:alnum:]_]|$)' |
					grep -oE 'ADR-[0-9]{4}' | sort -u | while IFS= read -r ss_id; do
					[ "$ss_id" = "$ss_self" ] && continue
					ss_old=""
					for f in "$ss_dir/${ss_id#ADR-}"-*.md; do
						[ -f "$f" ] && { ss_old=$f; break; }
					done
					[ -n "$ss_old" ] || continue
					sed -n 's/^- \*\*Superseded by\*\*:\(.*\)$/\1/p' "$ss_old" | head -1 | grep -qF -- "$ss_self" && continue
					printf '%s\n' "$ss_known" | grep -qxF -- "$(basename "$ss_old" .md)|$(basename "$rec" .md)" && continue
					report "supersession-one-sided" "$ss_old" \
						"$ss_id is superseded by $ss_self (its \"Supersedes / amends\" line says so), but $ss_id's \"Superseded by\" line does not name $ss_self" \
						"Name $ss_self on $ss_id's \"Superseded by\" line, and in what respect — the old record is where a reader learns it stopped binding."
				done
			done
		fi
	fi

	# The skill-tools rules' POSIX twin (validators/skill-tools.mjs, #800): an
	# agent type with no `tools:` line, a SKILL.md with no `allowed-tools`
	# (an advisory while the block's missingAllowedTools is "warning"), and a
	# skill naming "the `<type>` agent type" whose tools hold one outside its
	# allowed-tools. Every skill home, once per skill name, as skill-dated
	# reads them. The block is read BY TEXT from config.mjs's `skillTools`
	# block; no block is no rule — the harness's answer too.
	if [ -f "$ls_cfg" ] && command -v fence_strip >/dev/null 2>&1; then
		st_block=$(awk '/^const skillTools = \{/ { on = 1; next } on && /^\};/ { exit } on { print }' "$ls_cfg")
		if [ -n "$st_block" ]; then
			st_dirs=$(printf '%s\n' "$st_block" | awk '/^[[:space:]]*agentTypeDirs:[[:space:]]*\[/ { on = 1; next } on && /^[[:space:]]*\]/ { exit } on { print }' |
				sed -n 's/^[[:space:]]*"\(.*\)",\{0,1\}[[:space:]]*$/\1/p')
			st_sev=$(printf '%s\n' "$st_block" | sed -n 's/^[[:space:]]*missingAllowedTools:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
			st_dir=$(sed -n 's/^[[:space:]]*skillsDir:[[:space:]]*"\([^"]*\)".*/\1/p' "$ls_cfg" | head -1)
			# st_tools <file> <key> — the tools one frontmatter key declares,
			# one per line, each scope dropped; exit 3 when the key is absent.
			st_tools() {
				awk -v k="$2:" 'NR == 1 { if ($0 ~ /^---[ \t\r]*$/) { fm = 1; next } exit }
					/^---[ \t\r]*$/ { exit }
					inlist { if ($0 ~ /^[ \t]+-/) { sub(/^[ \t]+-[ \t]*/, ""); print; next } inlist = 0 }
					!found && index($0, k) == 1 { found = 1; inlist = 1; print substr($0, length(k) + 1) }
					END { if (!found) exit 3 }' "$1" |
					sed 's/([^)]*)//g; s/[][,"'"'"']/ /g' | tr -s ' \t\r' '\n\n\n' | grep -v '^$' | awk '!seen[$0]++'
			}
			# The agent types: `<name>\t<file>\t<tools, space-joined>` per line.
			: >"$vfile.types"
			for st_d in $st_dirs; do
				for st_f in $st_d/*.md; do
					[ -f "$st_f" ] || continue
					st_name=$(awk 'NR == 1 { if ($0 ~ /^---[ \t\r]*$/) { fm = 1; next } exit }
						/^---[ \t\r]*$/ { exit }
						/^name:/ { sub(/^name:[ \t]*["'"'"']?/, ""); sub(/["'"'"' \t\r].*$/, ""); print; exit }' "$st_f")
					[ -n "$st_name" ] || st_name=$(basename "$st_f" .md)
					st_t=$(st_tools "$st_f" tools | tr '\n' ' ')
					printf '%s\t%s\t%s\n' "$st_name" "$st_f" "$st_t" >>"$vfile.types"
					[ -n "$st_t" ] && continue
					report "agent-type-tools-missing" "$st_f" \
						"$st_name has no tools line, so it inherits every tool" \
						"Give the type a \`tools:\` line in its frontmatter naming the tools it needs, and nothing more."
				done
			done
			: >"$vfile.seen"
			st_undeclared=""
			st_hint="Declare \`allowed-tools:\` in the SKILL.md frontmatter: the tools the skill's own session uses, every tool of every agent type it spawns among them."
			for skill in "${st_dir:-.agents/skills}"/*/SKILL.md .agents/skills/*/SKILL.md .claude/skills/*/SKILL.md; do
				[ -f "$skill" ] || continue
				st_skdir=${skill%/SKILL.md}
				st_name=${st_skdir##*/}
				grep -qxF -- "$st_name" "$vfile.seen" && continue
				printf '%s\n' "$st_name" >>"$vfile.seen"
				st_allowed=$(st_tools "$skill" allowed-tools)
				if [ -z "$st_allowed" ]; then
					# An advisory names every such skill on one line; a
					# violation, one finding per skill — the harness's split.
					if [ "$st_sev" = "warning" ]; then
						st_undeclared="${st_undeclared:+$st_undeclared, }$st_name"
					else
						report "skill-allowed-tools-missing" "$skill" \
							"$st_name has no allowed-tools in its frontmatter, so nothing states the tools it uses" \
							"$st_hint"
					fi
					continue
				fi
				for st_doc in "$st_skdir"/*.md; do
					[ -f "$st_doc" ] || continue
					fence_strip "$st_doc" | tr '\n' ' ' | grep -oE '`[A-Za-z0-9_-]+`[[:space:]]+agent type' |
						sed 's/^`\([^`]*\)`.*/\1/' | while IFS= read -r st_type; do
						awk -F '\t' -v n="$st_type" '$1 == n { print $3 }' "$vfile.types" | while IFS= read -r st_tt; do
							st_out=""
							for st_tool in $st_tt; do
								printf '%s\n' "$st_allowed" | grep -qxF -- "$st_tool" && continue
								st_out="${st_out:+$st_out, }$st_tool"
							done
							[ -n "$st_out" ] || continue
							printf '%s\n' "$st_name spawns $st_type, whose tools ($st_out) are outside its allowed-tools"
						done
					done | awk '!seen[$0]++' | while IFS= read -r st_msg; do
						report "spawn-widens-tools" "$st_doc" "$st_msg" \
							"Spawn a type whose tools are within the skill's allowed-tools, or widen the skill's allowed-tools in the open — a spawned subagent may only narrow what its spawner may do."
					done
				done
			done
			[ -n "$st_undeclared" ] &&
				printf '  [skill-tools] ! %s [skill-allowed-tools-missing] — no allowed-tools in the frontmatter of %s, so nothing states the tools they use\n      -> %s\n' \
					"${st_dir:-.agents/skills}" "$st_undeclared" "$st_hint" >>"$vfile.warn"
		fi
	fi
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
if [ "$engine" = "fallback" ]; then
	echo "NOTICE  docs gate running WITHOUT node — reduced coverage." >&2
	echo "        Checked: unstamped placeholders, shared-layer manifest, repo paths in the manual layer," >&2
	echo "        living specs against the test globs (the living-spec rule, its POSIX twin)," >&2
	echo "        skill byte ceilings (the skill-ceiling rule, its POSIX twin)," >&2
	echo "        dated kit evidence in skill bodies (the skill-dated rule, its POSIX twin)," >&2
	echo "        supersession held both ways between decision records (the supersession rule, its POSIX twin)," >&2
	echo "        and declared tools — allowed-tools, agent types' tools lines, spawns that only narrow (the skill-tools rules, their POSIX twin)." >&2
	echo "        NOT checked: slash-command resolution, article reachability, nested manuals," >&2
	echo "        package-relative paths, shim integrity (CLAUDE.md / GEMINI.md) and the" >&2
	echo "        portability deny-list on the shared article — the claude-md-refs rules" >&2
	echo "        beyond repo paths; cross-skill references (the skill-web advisory)," >&2
	echo "        path references inside skill bodies" >&2
	echo "        (the skill-paths rule), the engineering article's mutation" >&2
	echo "        decision (the mutation-decision advisory) and its design brief" >&2
	echo "        (the design-brief advisory), the diary's housekeeping date (the" >&2
	echo "        housekeeping-due advisory), materialized skill-bridge symlinks" >&2
	echo "        (the skill-bridge advisory), the glossary's banned words" >&2
	echo "        (the banned-words advisory), an off trace beside an ignored trace" >&2
	echo "        directory (the trace-off advisory) and an unmapped reviewer tier" >&2
	echo "        (the reviewer-unmapped advisory)." >&2
	echo "        Install node and re-run to get the full harness (scripts/docs-conformance)." >&2
	echo "" >&2
fi

posix_failed=0
[ -s "$vfile" ] && posix_failed=1

# The reduced form's advisories (a skill with no allowed-tools while the
# policy holds that rule at a warning), under the harness's own header: they
# are printed whatever the verdict and never move the exit code.
if [ -s "$vfile.warn" ]; then
	{
		echo "$advisory_header: advisories (gate stays green)"
		echo ""
		cat "$vfile.warn"
		echo ""
	} >&2
fi

if [ "$posix_failed" = 0 ] && [ "$harness_status" = 0 ]; then
	# A green harness may still carry ADVISORIES — findings on the warning
	# channel that never fail the gate. Relay them: this wrapper is the entry
	# point the hook and CI run, and a warning only the harness printed is a
	# warning nobody saw. Quiet when there is nothing to advise, and trimmed
	# to the advisory block — the harness's own OK line is not repeated.
	case "$harness_out" in
	*"$advisory_header"*)
		printf '%s\n' "$harness_out" | sed '/^OK  docs conformance/d' >&2
		;;
	esac
	echo "OK  docs gate: all checks passed (shared-layer ${shared_version:-unknown}, engine: $engine)"
	exit 0
fi

echo "FAIL  docs gate: violations found" >&2
echo "" >&2
if [ "$posix_failed" = 1 ]; then
	cat "$vfile" >&2
fi
if [ "$harness_status" != 0 ] && [ -n "$harness_out" ]; then
	printf '%s\n\n' "$harness_out" >&2
fi
echo "Fix them, or see .githooks/pre-push for the logged bypass." >&2
exit 1
