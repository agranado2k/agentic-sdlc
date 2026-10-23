#!/bin/sh
# tool-pre-guard.sh — the PreToolUse hook on Bash, holding two rules: a
# spawned sub-agent cannot signal processes by NAME (kill-guard), and nobody
# waits in a loop on `pgrep -f`, which never ends (wait-guard).
#
# WHY IT EXISTS. During PR #393's review a sub-agent ran `pkill -f` on two
# suite names and may have killed sibling sessions' runs (#414; retro
# 20261001T150216Z). Several sessions run the same suites in parallel on one
# machine, so a process matched by name is as likely a sibling's as one's own.
# The review skill's "stay in your lane" was prose; this is the mechanism.
#
# WHAT IT REFUSES. A Bash call, from a SPAWNED SUB-AGENT, whose command signals
# by name: `pkill`, `killall`, `kill` alongside `pgrep` (`kill $(pgrep …)`,
# `pgrep … | xargs kill`), or `kill` handed a word that is not a pid, a job
# (`%1`) or an expansion (`$!`, `$pid`). Signalling what the sub-agent started —
# `kill %1`, `kill $!`, `kill 12345` — passes.
#
# THE MARKER IS `agent_type` ON THE PAYLOAD, which the agent harness sets on a
# sub-agent's tool calls and never on the operator's own session. It is wider
# than "a review": the review skill spawns its agents through the agent
# harness's Agent tool with a general type, so no field names a review, an
# environment variable cannot be set per in-session sub-agent (they share the
# session's process), and a prompt marker would mean reading the sub-agent's
# transcript on every Bash call. Every spawned sub-agent shares the hazard, so
# every one is held to it; see ../README.md, "The kill guard".
#
# A SCAN, NOT A SANDBOX. It reads the command's words outside quotes, so a
# command it cannot see into — `sh -c '…'`, `eval`, a script written and then
# run, a pid list from `ps | awk` — walks past it. It catches the reflex the
# retro saw, and says so rather than claiming more.
#
# A GUARD, SO IT MAY EXIT NON-ZERO. hook.lib.sh's rule 1 is "exit 0,
# always", because observability must never change a session. This hook is a
# guard rather than an observer, as spawn-guard.sh and root-guard.sh are: exit
# 2 is the agent harness's block status, its stderr goes back to the
# sub-agent as the reason, and it is this hook's only non-zero exit — every other path, a payload it cannot read included, is
# exit 0. With node missing it fails CLOSED for a sub-agent only: a payload
# naming pkill, killall or pgrep anywhere is refused unread.
#
# THE WAIT RULE, FOR EVERY CALLER (#849). `until ! pgrep -f "<command>"`
# matches its own shell, whose command line carries the pattern, so the loop
# never exits; it then holds a worktree "live" and the cleanup keeps it (retro
# 20261023T103804Z, R4: ten such loops in one window, one stuck on
# `gh pr checks 841 --watch` two days running, killed by hand at wrap-up). A
# `while` or `until` loop that polls `pgrep -f` (or `--full`, or a cluster such
# as `-af`) is refused, for the operator's own session as much as for a
# sub-agent: the hazard is the loop, not who typed it. A command that opens with
# its own non-zero `timeout <n>` is bounded and passes, and so does every loop
# the scan cannot see — `timeout 30m sh -c '…'` among them. The refusal names
# the bounded alternatives. Without node the command cannot be read and the
# operator's call is let through, as it always was; a sub-agent's payload
# naming pgrep is refused unread by the kill rule's fallback above.
#
# THE RECORD. One `note` with outcome=denied on the session, naming the rule
# and the call; with tool capture on, the call's pending marker (tool-pre.sh,
# #409) is also swept at session end into a `tool.use` with outcome=denied.
# Tracing off still blocks; the note is the record, the exit status is the
# guard.

set -u

. "$(dirname "$0")/hook.lib.sh"

hook_read

[ "$(hook_field tool_name)" = Bash ] || exit 0
atype=$(hook_field agent_type)
# The operator's own session is held to the wait rule alone, and only a command
# naming pgrep can break it: anything else is let through without starting node.
if [ -z "$atype" ]; then
	case $hook_json in *pgrep*) ;; *) exit 0 ;; esac
fi

# guard_why <sub> — the first rule the command on stdin breaks, as one line
# `<rule> <why>`, or nothing: `kill-guard` (signal by name) only when <sub> is
# 1, a spawned sub-agent's call; `wait-guard` (a loop polling pgrep -f) for
# any. Quoted text is literal to the shell, so a single-quoted segment, and a double-quoted one with no substitution inside, is dropped
# before the words are read: `rg 'pkill|killall'` searches, it does not signal.
# The quotes are read left to right, one character at a time, so a `'` inside
# double quotes is text and never opens a single-quoted segment (review of PR
# #433, L-1). A heredoc's body is not told apart from commands: a line in it
# that starts with pkill is refused, which errs closed.
guard_why() {
	awk -v q="'" -v sub_agent="$1" '
	{ s = s $0 "\n" }
	function base(w) { sub(/.*\//, "", w); return w }
	END {
		t = ""; st = ""; buf = ""
		for (x = 1; x <= length(s); x++) {
			ch = substr(s, x, 1)
			if (st == "s") { if (ch == q) { st = ""; t = t " " } continue }
			if (st == "d") {
				if (ch == "\\") { buf = buf ch substr(s, x + 1, 1); x++; continue }
				if (ch == "\"") { st = ""; t = t " " (buf ~ /\$\(|`/ ? buf : "") " "; continue }
				buf = buf ch; continue
			}
			if (ch == q) { st = "s"; continue }
			if (ch == "\"") { st = "d"; buf = ""; continue }
			t = t ch
		}
		s = t
		gsub(/\$\(|[`;&|(){}\n]/, "\n", s)
		n = split(s, segs, "\n")
		# lp: the open loops, innermost last, each "w" (while/until) or "f" (for).
		# bd: the command opens with its own non-zero timeout. wt: a pgrep -f
		# polled inside an open while or until.
		nl = 0; bd = 0; seen = 0
		for (k = 1; k <= n; k++) {
			m = split(segs[k], w, /[ \t]+/)
			i = 1
			while (i <= m && (w[i] == "" || w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ ||
				w[i] ~ /^(sudo|xargs|exec|nohup|env|command|time|timeout|nice|then|do|else|if|while|until|!)$/ ||
				w[i] ~ /^-/ || w[i] ~ /^[0-9.]+[smhd]?$/)) {
				if (w[i] == "while" || w[i] == "until") lp[++nl] = "w"
				# The first command word is timeout: its duration, past its own
				# options (-k and -s take the next word), is the bound.
				if (!seen && w[i] == "timeout") {
					for (j = i + 1; j <= m; j++) {
						if (w[j] ~ /^-[ks]$/) { j++; continue }
						if (w[j] ~ /^-/) continue
						if (w[j] ~ /^[0-9.]+[smhd]?$/ && w[j] + 0 > 0) bd = 1
						break
					}
				}
				if (w[i] != "" && w[i] !~ /^[A-Za-z_][A-Za-z0-9_]*=/) seen = 1
				# sudo -u <user>, sudo -g <group>: the option takes the next word.
				if (w[i] ~ /^-[ugCDhpRrTt]$/) i++
				i++
			}
			if (i > m) continue
			seen = 1
			c = base(w[i])
			if (c == "for" || c == "select") { lp[++nl] = "f"; continue }
			if (c == "done") { if (nl) nl--; continue }
			if (c == "pgrep") {
				for (l = 1; l <= nl; l++) if (lp[l] == "w") break
				if (l <= nl) for (j = i + 1; j <= m; j++)
					if (w[j] == "--full" || w[j] ~ /^-[A-Za-z]*f/) { wt = 1; break }
			}
			if (!sub_agent) continue
			if (c == "pkill" || c == "killall") { print "kill-guard " c " signals every process whose name matches"; exit }
			if (c == "pgrep") pg = 1
			if (c != "kill") continue
			kl = 1
			for (j = i + 1; j <= m; j++) {
				if (w[j] == "") continue
				# A comment ends the command; a redirect is not an argument, and
				# a bare one takes the next word as its target (review of PR
				# #433, H-1: `kill $pid 2>/dev/null` is a pid, not a name).
				if (w[j] ~ /^#/) break
				if (w[j] ~ /^([0-9]*[<>]+&?|&>+)$/) { j++; continue }
				if (w[j] ~ /^([0-9]*[<>]|&>)/) continue
				if (w[j] ~ /^-(s|n|-signal)$/) { j++; continue }
				if (w[j] ~ /^-/ || w[j] ~ /^([0-9]+|%.*|\$.*)$/) continue
				print "kill-guard kill was handed a name, " w[j] ", rather than a pid or a job"; exit
			}
		}
		if (kl && pg) { print "kill-guard kill is fed by pgrep, which matches by name"; exit }
		if (wt && !bd) print "wait-guard a while or until loop polls pgrep -f, which matches the loop\047s own shell"
	}'
}

sub=0
[ -n "$atype" ] && sub=1
why=
if command -v node >/dev/null 2>&1; then
	why=$(printf '%s' "$hook_json" |
		node -e 'try { const c = JSON.parse(require("fs").readFileSync(0, "utf8")).tool_input?.command; if (typeof c === "string") process.stdout.write(c) } catch {}' 2>/dev/null |
		guard_why "$sub")
elif [ "$sub" = 1 ]; then
	case $hook_json in *pkill* | *killall* | *pgrep*)
		why='kill-guard node is not on PATH, so the command could not be read, and it names pkill, killall or pgrep' ;;
	esac
fi
[ -n "$why" ] || exit 0
rule=${why%% *}
why=${why#* }
set --
if [ "$sub" = 1 ]; then
	hook_id_ok "$atype" || atype=unnamed
	set -- data.agent_type="$atype"
fi

if [ "$rule" = wait-guard ]; then
	hook_deny wait-guard "wait-guard refused a Bash call: $why" "$@"
	echo "wait-guard: refused — $why, so it never exits and holds its worktree live until somebody kills it. Bound the wait instead: run the command you are waiting on in the foreground under timeout <n> (timeout 30m gh pr checks <PR> --watch), or run it in the background and wait for the harness's notification when a background command ends." >&2
	exit 2
fi

hook_deny kill-guard "kill-guard refused a spawned sub-agent's Bash call: $why" "$@"

echo "kill-guard: refused — a spawned sub-agent ($atype) may not signal processes by name: $why. Parallel sessions run the same suites on this machine, so a name match may be a sibling's run. Signal only what you started: a job (kill %1) or a pid you hold (kill \$!)." >&2
exit 2
