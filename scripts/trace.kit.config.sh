#!/bin/sh
# trace.kit.config.sh — the KIT'S OWN trace policy. Not shipped.
#
# scripts/trace.config.sh ships with TRACE_DIR empty, by principle (see that
# file). But the kit repo is itself a project (ADR-0001) and the one whose
# product is the chain this trace records, so it turns tracing on here — in a
# twin that bootstrap.sh's KIT_ONLY list deletes before a consumer ever sees
# it, the arrangement ADR-0003's amendment states as general for every policy
# file the kit ships empty.
#
# Reached through the script's TRACE_CONFIG seam; scripts/trace.kit.sh is the
# one-line wrapper that sets it (AGENTS.md, hard rule 10).

# Under the root checkout, gitignored, shared by every worktree.
TRACE_DIR='.trace'
