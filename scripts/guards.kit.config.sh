#!/bin/sh
# guards.kit.config.sh — the KIT'S OWN guard policy. Not shipped.
#
# scripts/guards.config.sh ships with GUARD_SOURCE_RE empty to every consumer,
# by principle: the kit cannot know what "source" means in a project it has
# never seen, and an unconfigured pairing guard warns once and passes rather
# than blocking a push in a repo nobody has configured.
#
# But the kit repo is itself a project (ADR-0001: the kit follows its own
# constitution), and an empty pattern here meant the guard the kit ships was
# inactive in the one repo whose product is the discipline it enforces — every
# push of the 0.18.0 wave said so. The obvious fix, filling in the shipped
# file, was wrong and two demo suites caught it: bootstrap copies that file
# into every new project, so the kit's pattern — scripts/*.sh, bootstrap.sh —
# would have become every consumer's definition of source.
#
# So the kit carries its OWN policy in a file that is kit-authoring only and
# never reaches a consumer (bootstrap.sh's KIT_ONLY list deletes it at stamp
# time, beside scripts/agents.kit.config.sh which exists for exactly the same
# reason — ADR-0003). It is reached through the guard's existing $GUARDS_CONFIG
# seam (discovery order 1 in scripts/guards.lib.sh): .githooks/pre-push points
# GUARDS_CONFIG at this file when it exists, and it never exists downstream.
#
# THE KIT'S SOURCE is its shell and the docs harness's JavaScript: every script
# under scripts/, the engine and validators under scripts/docs-conformance/,
# bootstrap.sh at the root, and the hooks under .githooks/ — the manual names
# those as the kit's POSIX-sh code. Its tests live under tests/ and
# scripts/docs-conformance/test/, which the shipped GUARD_TEST_RE already
# matches. tests/tdd-pairing-guard.test.sh copies THIS file into a fixture and
# holds each claim to a real diff, so the pattern and the suite cannot drift.
GUARD_SOURCE_RE='^(bootstrap\.sh|\.githooks/[^/]+|scripts/[^/]+\.sh|scripts/docs-conformance/([^/]+|validators/[^/]+)\.mjs)$'

# Policy is not source: a tier mapping or a guard pattern changing alone is
# not a behaviour change a test could pair with. The kit's own never-shipped
# copies end in .config.sh too, so one pattern covers all of them.
# scripts/docs-conformance/config.mjs is the docs gate's policy — the manual
# calls it "policy as data" — and is excluded for the same reason.
GUARD_SOURCE_EXCLUDE_RE='(\.d\.ts|\.min\.js|\.config\.sh|/docs-conformance/config\.mjs)$'

# Unchanged from the shipped file; repeated because a config is sourced whole
# and an unset GUARD_TEST_RE is an error, not a default.
GUARD_TEST_RE='(\.|_|/)(test|tests|spec|specs)(\.|_|/)|(^|/)(test|tests|spec|specs)/|_test\.|\.feature$'
