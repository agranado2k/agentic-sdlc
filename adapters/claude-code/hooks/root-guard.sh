#!/bin/sh
# root-guard.sh — the PreToolUse hook: the root checkout refuses an agent's edit.
#
# THE RULE IS THE MANUAL'S, hard rule 1: "Worktree, always. Never edit the root
# checkout for in-progress work." Git has no hook for an edit, so this is the
# half of that rule the agent harness can hold; `.githooks/pre-commit` holds the
# other half, at the commit.
#
# WHAT IT REFUSES. A call to an editing tool (Edit, Write, MultiEdit,
# NotebookEdit) whose target resolves inside the repository's MAIN working tree
# but not under `worktree/`. The runtime directories sessions legitimately
# write at the root — `.trace/` and `.retro/` — pass, and so does every path
# outside the repository (a dispatch's scratch lives under $TMPDIR). For Bash
# it is a TRIPWIRE, not a proof: a command that redirects into, or runs
# `sed -i`, `tee`, `cp`, `mv`, `git checkout` or `git restore` (not
# `--staged` alone, which touches only the index) on, a path that resolves to
# a TRACKED file at the root, `git -C` followed; and, where git acts at the
# root, the three ways around the commit guard — `git commit --no-verify` (or
# `-n`), `git -c core.hooksPath=…`, and setting or unsetting
# `core.hooksPath` with `git config`. Everything else a shell can do — a
# script, an interpreter, `rm`, a variable or a glob it never expands, a `cd`
# inside a subshell — goes through. ../README.md says so too.
#
# THE ROOT IS FOUND FROM THIS FILE, never from the caller's cwd, through git's
# common directory: a session started inside a worktree runs the worktree's
# copy of this hook, and the tree it guards is still the main one.
#
# HOW IT ANSWERS — the agent harness's PreToolUse contract: exit 2 blocks the
# call and stderr is shown to the model, exit 0 lets it through. Nothing is
# ever written to stdout, which the agent harness parses.
#
# IT FAILS OPEN, deliberately. A payload it cannot read, a tool it does not
# know or a root it cannot resolve is exit 0: a guard that blocked every call
# on a parse failure would brick the session. The commit hook is no fail-closed
# backstop for it — git lets any committer skip a hook, which is why this one
# refuses the ways around it. Of the two, this is the layer that refuses; the
# commit hook is a guard a cooperative agent meets.
#
# NOT hook.lib.sh's rule 1. The trace hooks beside this file exit 0 always,
# because observability must never change a session; this hook exists to
# change one, and shares nothing with them but the directory.

set -u

here=$(cd "$(dirname "$0")" && pwd -P) || exit 0
root=$(
	unset GIT_DIR GIT_WORK_TREE
	cd "$here" 2>/dev/null || exit 1
	common=$(git rev-parse --git-common-dir 2>/dev/null) || exit 1
	case $common in */.git | .git) ;; *) exit 1 ;; esac
	cd "$common/.." 2>/dev/null && pwd -P
) || exit 0
[ -n "$root" ] || exit 0

json=$(cat 2>/dev/null) || exit 0

# field <key> — the payload's string value for <key>, JSON escapes undone. The
# key is matched WITH its quotes and preceded by `{`, `,` or whitespace, so a
# key quoted inside a string value (escaped, so preceded by a backslash) never
# answers; the value's escapes are walked pairwise, so an escaped quote inside
# a command does not end it early.
field() {
	printf '%s\n' "$json" |
		sed -n -E 's/.*[{,[:space:]]"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' |
		sed -n '1p' |
		awk '{
			out = ""; n = length($0); i = 1
			while (i <= n) {
				c = substr($0, i, 1)
				if (c == "\\" && i < n) {
					d = substr($0, i + 1, 1)
					if (d == "n") out = out "\n"
					else if (d == "t") out = out "\t"
					else if (d != "r") out = out d
					i += 2
				} else { out = out c; i++ }
			}
			printf "%s", out
		}'
}

# resolve <path> <base> — <path> made absolute against <base>, `.` and `..`
# folded, symlinks resolved for the part that exists. A file not yet written
# is resolved through its nearest existing parent.
resolve() {
	_p=$1
	case $_p in
	'~') _p=${HOME:-/} ;;
	'~/'*) _p="${HOME:-}/${_p#\~/}" ;;
	/*) ;;
	*) _p="$2/$_p" ;;
	esac
	_p=$(printf '%s\n' "$_p" | awk -F/ '{
		n = 0
		for (i = 1; i <= NF; i++) {
			if ($i == "" || $i == ".") continue
			if ($i == "..") { if (n > 0) n--; continue }
			seg[++n] = $i
		}
		out = ""
		for (i = 1; i <= n; i++) out = out "/" seg[i]
		print (out == "" ? "/" : out)
	}')
	_d=$_p
	_rest=
	while [ ! -d "$_d" ]; do
		_rest="/${_d##*/}$_rest"
		_d=${_d%/*}
		[ -n "$_d" ] || _d=/
	done
	_d=$(cd "$_d" 2>/dev/null && pwd -P) || _d=
	printf '%s%s' "${_d%/}" "$_rest"
}

# guarded <absolute path> — status 0 when the path is the root's own, the
# place this rule forbids an edit.
guarded() {
	case $1 in
	"$root"/worktree | "$root"/worktree/*) return 1 ;;
	"$root"/.trace | "$root"/.trace/* | "$root"/.retro | "$root"/.retro/*) return 1 ;;
	"$root" | "$root"/*) return 0 ;;
	esac
	return 1
}

# tracked <absolute path> — status 0 when the root's index holds exactly it.
tracked() {
	_rel=${1#"$root"/}
	[ "$(
		unset GIT_DIR GIT_WORK_TREE
		git --literal-pathspecs -C "$root" ls-files -z -- "$_rel" 2>/dev/null | tr '\0' '\n' | sed -n '1p'
	)" = "$_rel" ]
}

refuse() {
	echo "x root-guard: $1 on ${2#"$root"/} — the root checkout is not for in-progress work (hard rule 1, \"Worktree, always\")." >&2
	echo "  Open a worktree and work there: git worktree add worktree/<slug> -b <type>/<slug>" >&2
	exit 2
}

tool=$(field tool_name)
cwd=$(field cwd)
[ -n "$cwd" ] || cwd=$root

case $tool in
Edit | Write | MultiEdit | NotebookEdit)
	target=$(field file_path)
	[ -n "$target" ] || target=$(field notebook_path)
	[ -n "$target" ] || exit 0
	abs=$(resolve "$target" "$cwd")
	guarded "$abs" && refuse "$tool" "$abs"
	exit 0
	;;
Bash) ;;
*) exit 0 ;;
esac

command=$(field command)
[ -n "$command" ] || exit 0

# THE PLAN: the command read as a shell would, roughly — one line per `cd` it
# makes and per path it would write. Heredoc bodies are skipped (they are
# data), continuation lines joined, quotes dropped, and `&&`, `||`, `;`, `|`,
# `&`, parentheses and newlines end a simple command. A redirect's target is a
# write; so are the operands of `sed -i`, `tee`, `mv`, `git checkout` and
# `git restore`, and the last operand of `cp`. A git write is a `gwrite` line
# carrying the directory any `-C` moved git to, and a way around the commit
# guard is an `around` line carrying the same.
plan=$(printf '%s\n' "$command" | awk '
function endseg(   i, j, k, c, s, inplace, last) {
	i = 1
	while (i <= nw && words[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) i++
	while (i <= nw && (words[i] == "env" || words[i] == "sudo" || words[i] == "command" || words[i] == "nohup" || words[i] == "exec" || words[i] == "time")) {
		p = words[i]; i++
		# The options of the prefix, and the ones that take a word with them.
		while (i <= nw && (words[i] ~ /^-/ || words[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) {
			if ((p == "env" && words[i] ~ /^-[uCS]$/) || (p == "sudo" && words[i] ~ /^-[ugCDhprtUT]$/)) i++
			i++
		}
	}
	if (i > nw) { nw = 0; return }
	c = words[i]; sub(/.*\//, "", c)
	if (c == "cd") {
		j = i + 1
		while (j <= nw && words[j] ~ /^-./) j++
		print "cd " (j <= nw ? words[j] : "~")
	} else if (c == "sed" || c == "gsed") {
		inplace = 0
		for (j = i + 1; j <= nw; j++) if (words[j] ~ /^-[A-Za-z]*i/ || words[j] ~ /^--in-place/) inplace = 1
		if (inplace) for (j = i + 1; j <= nw; j++) if (words[j] !~ /^-/) print "write " words[j]
	} else if (c == "tee" || c == "mv") {
		for (j = i + 1; j <= nw; j++) if (words[j] !~ /^-/) print "write " words[j]
	} else if (c == "cp") {
		last = ""
		for (j = i + 1; j <= nw; j++) if (words[j] !~ /^-/) last = words[j]
		if (last != "") print "write " last
	} else if (c == "git") {
		gdir = "."; around = 0
		j = i + 1
		while (j <= nw && words[j] ~ /^-/) {
			if (words[j] == "-C" && j + 1 <= nw) {
				gdir = (words[j + 1] ~ /^\// ? words[j + 1] : gdir "/" words[j + 1]); j += 2
			} else if (words[j] == "-c" && j + 1 <= nw) {
				kv = tolower(words[j + 1]); sub(/=.*/, "", kv)
				if (kv == "core.hookspath") around = 1
				j += 2
			} else j++
		}
		s = words[j]
		if (s == "commit") {
			# A short cluster is read letter by letter: `n` is --no-verify,
			# but an option that takes an argument ends the cluster, so the
			# `n` of `-uno` or `-Fn` is that argument, and `-m` alone takes
			# the next word whole, `-n` or not.
			for (k = j + 1; k <= nw; k++) {
				w = words[k]
				if (w == "--") break
				if (w == "--no-verify") around = 1
				else if (w ~ /^--(message|file|author|date|template|reuse-message|reedit-message|fixup|squash|trailer|cleanup)$/) k++
				else if (w ~ /^-[^-]/)
					for (q = 2; q <= length(w); q++) {
						ch = substr(w, q, 1)
						if (ch == "n") around = 1
						else if (index("mFcCt", ch)) { if (q == length(w)) k++; break }
						else if (index("uS", ch)) break
					}
			}
		} else if (s == "config") {
			key = 0; setting = 0
			for (k = j + 1; k <= nw; k++) {
				w = words[k]
				if (k == j + 1 && (w == "set" || w == "unset")) { setting = 1; continue }
				if (w ~ /^--(unset|unset-all|replace-all|add)$/) { setting = 1; continue }
				if (w ~ /^-/) continue
				if (key) { setting = 1; continue }
				if (tolower(w) == "core.hookspath") key = 1
			}
			if (key && setting) around = 1
		} else if (s == "checkout" || s == "restore") {
			staged = 0; tree = 0
			if (s == "restore")
				for (k = j + 1; k <= nw; k++) {
					if (words[k] == "--staged" || words[k] ~ /^-[A-Za-z]*S[A-Za-z]*$/) staged = 1
					if (words[k] == "--worktree" || words[k] ~ /^-[A-Za-z]*W[A-Za-z]*$/) tree = 1
				}
			if (!staged || tree)
				for (k = j + 1; k <= nw; k++) if (words[k] !~ /^-/) print "gwrite " gdir "\t" words[k]
		}
		if (around) print "around " gdir
	}
	nw = 0
}
function scan(s,   n, t, i, expect) {
	gsub(/["\047]/, "", s)
	gsub(/&&|\|\||;|\(|\)/, " ; ", s)
	gsub(/&>>?|[0-9]*>>?\|?/, " > ", s)
	gsub(/\|/, " ; ", s)
	n = split(s, t, /[ \t]+/)
	expect = 0
	for (i = 1; i <= n; i++) {
		if (t[i] == "") continue
		if (t[i] == ";" || t[i] == "&") { expect = 0; endseg(); continue }
		if (t[i] == ">") { expect = 1; continue }
		if (expect) { expect = 0; if (t[i] !~ /^&/) print "write " t[i]; continue }
		if (t[i] ~ /^</) continue
		words[++nw] = t[i]
	}
	endseg()
}
BEGIN { hd = ""; acc = ""; nw = 0 }
{
	line = $0
	if (hd != "") {
		probe = line; sub(/^\t+/, "", probe)
		if (probe == hd) hd = ""
		next
	}
	if (line ~ /\\$/) { acc = acc substr(line, 1, length(line) - 1) " "; next }
	line = acc line; acc = ""
	pending = ""
	probe = line; gsub(/<<</, " ", probe)
	if (match(probe, /<<-?[ \t]*["\047]?[A-Za-z_0-9]+/)) {
		pending = substr(probe, RSTART, RLENGTH)
		sub(/^<<-?[ \t]*/, "", pending); gsub(/["\047]/, "", pending)
	}
	scan(line)
	if (pending != "") hd = pending
}
END { if (acc != "") scan(acc) }
') || exit 0

tab=$(printf '\t')
here_cwd=$cwd
while IFS= read -r step; do
	case $step in
	'cd '*)
		_to=${step#cd }
		case $_to in -) continue ;; esac
		here_cwd=$(resolve "$_to" "$here_cwd")
		;;
	'write '*)
		_t=${step#write }
		case $_t in /dev/*) continue ;; esac
		abs=$(resolve "$_t" "$here_cwd")
		if guarded "$abs" && tracked "$abs"; then
			refuse "Bash" "$abs"
		fi
		;;
	'gwrite '*)
		# A git write, relative to where git acts: the cwd moved by any -C.
		_g=${step#gwrite }
		_t=${_g#*"$tab"}
		abs=$(resolve "$_t" "$(resolve "${_g%%"$tab"*}" "$here_cwd")")
		if guarded "$abs" && tracked "$abs"; then
			refuse "Bash" "$abs"
		fi
		;;
	'around '*)
		# A way around the commit guard — `commit --no-verify`, `-c
		# core.hooksPath=…`, or setting core.hooksPath — where git acts at
		# the root.
		abs=$(resolve "${step#around }" "$here_cwd")
		guarded "$abs" && refuse "Bash (a way around the commit guard)" "$abs"
		;;
	esac
done <<EOF
$plan
EOF

exit 0
