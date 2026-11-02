#!/bin/sh
# guards.lib.sh — the one loader the guards share.
#
# Sourced, never executed. Its only job is finding and reading
# scripts/guards.config.sh so that three scripts do not carry three copies of
# the same resolution order (and drift).
#
# Resolution order, first hit wins:
#   1. $GUARDS_CONFIG        — explicit. If it is set and does not exist, that
#                              is an ERROR (exit 2): the caller named a file, so
#                              silently falling back would run a policy nobody
#                              asked for. Tests rely on this.
#   2. <repo root of the cwd>/scripts/guards.config.sh — the repo being
#      guarded. Sourced ONLY when that root is also the calling script's own
#      repo root: a config is sourced, i.e. CODE, and standing in a repository
#      must never be enough to run its code as you. (Discovery deliberately
#      stays cwd-based — the cwd repo IS the guard's subject, its config
#      describes the diff being classified — so the check verifies ownership
#      rather than re-anchoring discovery elsewhere.) On a mismatch the loader
#      says so on stderr and REFUSES: discovery ends there, unconfigured.
#      Crossing repos on purpose is what $GUARDS_CONFIG is for.
#   3. <calling script's directory>/guards.config.sh
#
# A missing config is NOT an error. Each guard decides what an unconfigured repo
# means for it; the pairing guard warns once and passes.
#
# Shared layer (see VERSION): copied verbatim, not edited downstream. Your
# policy goes in guards.config.sh.

# guards_load_config [<dir of the calling script>]
#
# The parameter is the anchor the mismatch check verifies against. Without it
# the check cannot run, so orders 2 and 3 are skipped entirely — an anchorless
# caller in an unconfigured state, exactly like a repo with no config file.
guards_load_config() {
	_gl_here=${1:-}

	if [ -z "$_gl_here" ] && [ -z "${GUARDS_CONFIG:-}" ]; then
		return 1
	fi

	if [ -n "${GUARDS_CONFIG:-}" ]; then
		if [ ! -f "$GUARDS_CONFIG" ]; then
			echo "guards: GUARDS_CONFIG=$GUARDS_CONFIG does not exist." >&2
			exit 2
		fi
		. "$GUARDS_CONFIG"
		return 0
	fi

	_gl_root=$(git rev-parse --show-toplevel 2>/dev/null) || _gl_root=
	if [ -n "$_gl_root" ] && [ -f "$_gl_root/scripts/guards.config.sh" ]; then
		# The anchor's rev-parse runs with inherited git identity scrubbed:
		# git exports GIT_DIR into hooks (linked worktrees especially), and a
		# pinned GIT_DIR makes rev-parse answer for the pinned repo — or for
		# the anchor directory itself — instead of for the anchor's own tree,
		# refusing a repo its own config on every worktree push.
		_gl_own=$( (unset GIT_DIR GIT_WORK_TREE && git -C "$_gl_here" rev-parse --show-toplevel) 2>/dev/null ) || _gl_own=
		if [ "$_gl_root" = "$_gl_own" ]; then
			. "$_gl_root/scripts/guards.config.sh"
			return 0
		fi
		echo "guards: refusing to source $_gl_root/scripts/guards.config.sh — it belongs to the repository this process is standing in, not to the guard's own (${_gl_own:-unknown}). A config is code; set GUARDS_CONFIG to cross repositories on purpose." >&2
		return 1
	fi

	if [ -f "$_gl_here/guards.config.sh" ]; then
		. "$_gl_here/guards.config.sh"
		return 0
	fi

	return 1
}

# guards_load_policy [<dir of the calling script>]
#
# The entry point a judge calls. With POLICY_BASE unset it is
# guards_load_config, unchanged: a local push reads the working tree. With
# POLICY_BASE naming a ref it reads the guards policy as that ref has it,
# through the policy reader beside the calling script (scripts/policy.sh,
# the kit's ADR-0039), and never falls back to the working tree:
#
#   - no override: scripts/guards.config.sh of the repository being guarded,
#     under the same ownership check as discovery order 2;
#   - $GUARDS_CONFIG naming a JUDGING FILE (relative to the cwd, or absolute
#     inside the repository): that file, at the base;
#   - $GUARDS_CONFIG naming a path outside the judging set — outside the
#     repository, or a file the reader answers is not judged: read as given,
#     as guards_load_config reads it.
#
# The base's copy is evaluated in a child shell; only GUARD_SOURCE_RE,
# GUARD_SOURCE_EXCLUDE_RE and GUARD_TEST_RE come back from it.
#
# Returns 0 loaded, 1 unconfigured (POLICY_BASE unset only). When the base
# cannot be read it prints the reader's `fail-closed <reason> <path>` line, or
# its own account when the reader gave none, on stderr and returns 3: the
# caller's strictest path, never its unconfigured one.
guards_load_policy() {
	[ -n "${POLICY_BASE:-}" ] || {
		guards_load_config "${1:-}"
		return
	}
	_gp_here=${1:-}
	_gp_top=$(git rev-parse --show-toplevel 2>/dev/null) && _gp_top=$(cd "$_gp_top" && pwd -P) || {
		echo "guards: POLICY_BASE is set but this is not a git working tree." >&2
		return 3
	}

	if [ -n "${GUARDS_CONFIG:-}" ]; then
		case $GUARDS_CONFIG in
		/*) _gp_abs=$GUARDS_CONFIG ;;
		*) _gp_abs=$(pwd -P)/$GUARDS_CONFIG ;;
		esac
		# Resolve the directory physically where it exists, so a `..` or a
		# symlink cannot dress a judging file up as some other path.
		_gp_dir=$(cd "$(dirname "$_gp_abs")" 2>/dev/null && pwd -P) &&
			_gp_abs=$_gp_dir/$(basename "$_gp_abs")
		case $_gp_abs in
		"$_gp_top"/*) _gp_path=${_gp_abs#"$_gp_top"/} ;;
		*)
			guards_load_config "$_gp_here"
			return
			;;
		esac
	else
		_gp_own=$( (unset GIT_DIR GIT_WORK_TREE && git -C "${_gp_here:-/}" rev-parse --show-toplevel) 2>/dev/null) &&
			_gp_own=$(cd "$_gp_own" && pwd -P) || _gp_own=
		if [ "$_gp_top" != "$_gp_own" ]; then
			echo "guards: refusing to read $_gp_top's guards policy at $POLICY_BASE — it belongs to the repository this process is standing in, not to the guard's own (${_gp_own:-unknown}). Set GUARDS_CONFIG to cross repositories on purpose." >&2
			return 3
		fi
		_gp_path=scripts/guards.config.sh
	fi

	_gp_reader=$_gp_here/policy.sh
	if [ -z "$_gp_here" ] || [ ! -f "$_gp_reader" ]; then
		echo "guards: POLICY_BASE is set but no policy reader sits beside the guard (${_gp_reader:-none}); the policy at $POLICY_BASE cannot be read." >&2
		return 3
	fi
	_gp_err=$(mktemp) || return 3
	_gp_rc=0
	_gp_copy=$(cd "$_gp_top" && sh "$_gp_reader" read "$_gp_path" --base "$POLICY_BASE" 2>"$_gp_err") || _gp_rc=$?
	_gp_why=$(cat "$_gp_err")
	rm -f "$_gp_err"
	case $_gp_rc in
	0) ;;
	2)
		# Exit 2 with "not a judging file" is the reader's answer that the
		# path is outside the set — read it as given. Any other exit 2 is an
		# error, and an error is the strictest path.
		case $_gp_why in
		*"not a judging file"*)
			guards_load_config "$_gp_here"
			return
			;;
		esac
		printf '%s\n' "$_gp_why" >&2
		echo "guards: the policy reader could not read $_gp_path at $POLICY_BASE (exit 2)." >&2
		return 3
		;;
	*)
		case $_gp_copy in
		fail-closed\ *) printf '%s\n' "$_gp_copy" >&2 ;;
		*)
			[ -z "$_gp_why" ] || printf '%s\n' "$_gp_why" >&2
			echo "guards: the policy reader gave no answer for $_gp_path at $POLICY_BASE (exit $_gp_rc)." >&2
			;;
		esac
		return 3
		;;
	esac
	[ -f "$_gp_copy" ] || {
		echo "guards: the policy reader named no readable copy of $_gp_path at $POLICY_BASE." >&2
		return 3
	}

	# shellcheck disable=SC2016 # expanded by the child, not here
	# The trap answers even when the file ends the child with its own `exit`.
	_gp_eval='trap '"'"'eval "printf %s \"\${$2:-}\""'"'"' EXIT; . "$1" >/dev/null 2>&1'
	GUARD_SOURCE_RE=$(sh -c "$_gp_eval" _ "$_gp_copy" GUARD_SOURCE_RE </dev/null)
	GUARD_SOURCE_EXCLUDE_RE=$(sh -c "$_gp_eval" _ "$_gp_copy" GUARD_SOURCE_EXCLUDE_RE </dev/null)
	GUARD_TEST_RE=$(sh -c "$_gp_eval" _ "$_gp_copy" GUARD_TEST_RE </dev/null)
	return 0
}
