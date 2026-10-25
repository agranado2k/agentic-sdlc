#!/bin/sh
# tests/ci-timeouts.test.sh — every job in the kit's own workflows is bounded.
#
# A kit CI job sat thirty minutes on its "Install zsh" step (#864) before the
# runner's own default killed it: nothing in the kit's workflows bounded a job
# or a step, so one stuck package mirror held a PR for half an hour (#882).
# The rule: every job under .github/workflows/ declares a job-level
# `timeout-minutes`, sized to its measured run plus headroom, and every step
# that installs packages carries one of its own, tighter than its job's.
#
# Indentation-based on purpose, like self-host's duplicate-key check: the kit's
# workflows are hand-written two-space YAML, and this is a tripwire for one
# omission, not a parser. A job is a two-space key under `jobs:`, its own keys
# sit at four spaces, a step opens at `      - ` and its keys sit at eight.
# A `timeout-minutes` anywhere else — a step's, a comment's — does not bound
# the job.
#
# Usage: sh tests/ci-timeouts.test.sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/tests/lib.sh"
cd "$ROOT" || exit 2
t_init

# timeout_findings <workflow>... — one line per unbounded job or install step;
# exit 1 when any, 0 when none. A file with no `jobs:` key is reported too: a
# scan that found nothing to hold must not read as a scan that passed.
timeout_findings() {
	awk '
		function close_step() {
			if (in_step && install) {
				if (step_to == "")
					printf "%s: job %s step %s installs packages with no timeout-minutes of its own\n", cur, job, step_name
				else
					steps[++ns] = job "\t" step_name "\t" step_to
			}
			in_step = 0; install = 0; step_to = ""; step_name = "(unnamed)"
		}
		function close_job(   i, parts) {
			close_step()
			if (job != "") {
				jobs_seen++
				if (job_to == "")
					printf "%s: job %s has no timeout-minutes\n", cur, job
				for (i = 1; i <= ns; i++) {
					split(steps[i], parts, "\t")
					if (job_to != "" && parts[3] + 0 >= job_to + 0)
						printf "%s: job %s step %s timeout-minutes %s is not tighter than its job'"'"'s %s\n", cur, job, parts[2], parts[3], job_to
				}
			}
			job = ""; job_to = ""; ns = 0
		}
		FNR == 1 { if (NR > 1) finish(prev); in_jobs = 0; jobs_seen = 0; prev = cur = FILENAME }
		function finish(f) {
			close_job()
			if (!jobs_seen) printf "%s: no jobs found to hold\n", f
		}
		/^[[:space:]]*#/ { next }
		/^jobs:/ { in_jobs = 1; next }
		/^[^[:space:]]/ { close_job(); in_jobs = 0; next }
		!in_jobs { next }
		/^  [A-Za-z0-9_-]+:/ { close_job(); job = $1; sub(/:$/, "", job); next }
		/^    timeout-minutes:/ { job_to = $2; next }
		/^      - / {
			close_step(); in_step = 1
			line = $0; sub(/^      - /, "        ", line)
		}
		!/^      - / { line = $0 }
		in_step && line ~ /^        name:/ { step_name = line; sub(/^        name:[[:space:]]*/, "", step_name) }
		in_step && line ~ /^        timeout-minutes:/ { step_to = line; sub(/^        timeout-minutes:[[:space:]]*/, "", step_to) }
		in_step && line ~ /(apt-get|apt|brew|dnf|yum|apk) (-[^ ]+ )*install|pip3? install|npm (install|ci)/ { install = 1 }
		END { if (NR > 0) finish(prev) }
	' "$@" | grep . && return 1
	return 0
}

FIX="$SCRATCH/wf"
mkdir -p "$FIX"
# wf <name> — write stdin as a fixture workflow, print its path.
wf() { cat >"$FIX/$1.yml"; printf '%s' "$FIX/$1.yml"; }

# ---------------------------------------------------------------------------
banner "1. A job with no timeout-minutes is caught (RED)"
# ---------------------------------------------------------------------------
f=$(wf missing <<'EOF'
name: Fixture
on: [push]
jobs:
  bounded:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
  unbounded:
    runs-on: ubuntu-latest
    steps:
      - run: sh tests/x.test.sh
EOF
)
out=$(timeout_findings "$f") && fail "a job with no timeout-minutes passed" ||
	pass "a job with no timeout-minutes fails the check"
case "$out" in *"job unbounded has no timeout-minutes"*) pass "the unbounded job is named" ;; *) fail "the unbounded job went unnamed: $out" ;; esac
case "$out" in *"job bounded "*) fail "the bounded job was reported: $out" ;; *) pass "the bounded job beside it is not reported" ;; esac

# A step's timeout bounds the step, not the job; a comment bounds nothing.
f=$(wf elsewhere <<'EOF'
jobs:
  step-only:
    runs-on: ubuntu-latest
    # timeout-minutes: 5
    steps:
      - name: Suite
        timeout-minutes: 5
        run: sh tests/x.test.sh
EOF
)
out=$(timeout_findings "$f") && fail "a step's or a comment's timeout passed for the job" ||
	pass "a timeout on a step or in a comment does not bound the job"
case "$out" in *"job step-only has no timeout-minutes"*) pass "the step-only job is named" ;; *) fail "the step-only job went unnamed: $out" ;; esac

# A file the scan finds no job in is a finding, not a pass.
f=$(wf empty <<'EOF'
name: Nothing here
on: [push]
EOF
)
out=$(timeout_findings "$f") && fail "a workflow with no jobs passed as held" ||
	pass "a workflow with no jobs is reported rather than certified"

# ---------------------------------------------------------------------------
banner "2. A package install needs a tighter timeout of its own (RED)"
# ---------------------------------------------------------------------------
f=$(wf install <<'EOF'
jobs:
  docs:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - name: Install zsh
        run: sudo apt-get update -qq && sudo apt-get install -y -qq zsh
      - name: Suite
        run: sh tests/x.test.sh
EOF
)
out=$(timeout_findings "$f") && fail "an install step with no timeout passed" ||
	pass "an install step with no timeout of its own fails the check"
case "$out" in *"step Install zsh installs packages with no timeout-minutes"*) pass "the install step is named" ;; *) fail "the install step went unnamed: $out" ;; esac
case "$out" in *"step Suite"*) fail "a step that installs nothing was reported: $out" ;; *) pass "a step that installs nothing needs no timeout of its own" ;; esac

f=$(wf loose <<'EOF'
jobs:
  docs:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: Install zsh
        timeout-minutes: 5
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y -qq zsh
EOF
)
out=$(timeout_findings "$f") && fail "an install timeout no tighter than its job's passed" ||
	pass "an install timeout no tighter than its job's fails the check"
case "$out" in *"timeout-minutes 5 is not tighter than its job's 5"*) pass "both numbers are named" ;; *) fail "the loose install step went unnamed: $out" ;; esac

# ---------------------------------------------------------------------------
banner "3. A bounded workflow passes (GREEN)"
# ---------------------------------------------------------------------------
f=$(wf clean <<'EOF'
jobs:
  docs:
    name: Docs
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - name: Install zsh
        timeout-minutes: 6
        run: sudo apt-get install -y zsh
  other:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - run: sh tests/x.test.sh
EOF
)
out=$(timeout_findings "$f") && pass "a workflow whose jobs and install step are bounded passes" ||
	fail "a bounded workflow was reported: $out"

# ---------------------------------------------------------------------------
banner "4. The kit's own workflows are bounded"
# ---------------------------------------------------------------------------
set -- .github/workflows/*.yml
[ -f "$1" ] || fail "no workflow under .github/workflows/ — the scan is covering nothing"
for w in "$@"; do
	if out=$(timeout_findings "$w"); then
		pass "$w: every job and every install step carries timeout-minutes"
	else
		fail "$w is not bounded"
		printf '%s\n' "$out" | sed 's/^/        | /'
	fi
done

t_done "every kit CI job carries a timeout"
