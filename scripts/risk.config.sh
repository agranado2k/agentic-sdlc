#!/bin/sh
# risk.config.sh — the RISK POLICY: the two numbers a review area must meet
# before a pull request in it may be called low risk, and the paths beyond the
# fixed judging set that a pull request may not loosen for itself.
#
# This file is DATA, and it is always read AT A BASE: `scripts/policy.sh
# thresholds --base <ref>` reads it as the base branch has it, never as a pull
# request left it, so a branch that lowers a number is judged by the number
# it lowered. A copy that is missing, fails `sh -n`, or holds a threshold out
# of shape FAILS CLOSED (`fail-closed <reason> scripts/risk.config.sh`, exit
# 3) — never a quiet default. It is evaluated only in a child process.
#
# THIS FILE IS YOURS. It is not part of the shared layer (see VERSION), it is
# not overwritten by a kit update, and editing it is the intended workflow. Like
# scripts/vocab.config.sh it ships FILLED: the numbers are a stance the kit can
# take for you, not a vendor's identifier that rots. Tighten them here; a
# tightening binds every pull request judged after it lands on the base branch.
#
# RISK_MISS_RATE_BELOW   a whole percent, 0 to 100. An area meets it when its
#                        reviews' miss rate, in percent, is strictly below it.
#                        5: fewer than 1 escaped mistake in 20 landings.
# RISK_PRECISION_FLOOR   a whole percent, 0 to 100. An area meets it when its
#                        lens precision, in percent, is at or above it.
#                        80: at least 4 in 5 lens findings hold up.
# RISK_JUDGING_EXTRA     more repository-relative paths, whitespace-separated,
#                        to treat as JUDGING FILES beside the fixed set (the
#                        `.config.sh` files directly under scripts/, the docs
#                        gate's config and local-vocabulary modules, the files
#                        directly under .githooks/ and .github/workflows/, and
#                        this file). Read at the base too, so a pull request
#                        can add to it for the next one, never shorten it for
#                        itself. Each entry is a plain relative path: no
#                        leading `/`, no `.` or `..` segment, no space.
# RISK_KILL_SWITCH       `on` or `tripped`. The KILL SWITCH's value: while it
#                        is `tripped` the risk rule calls no pull request low.
#                        Read at the base like the rest, so a pull request can
#                        neither reset it for itself nor trip it for itself;
#                        unset or any other value reads tripped. Its other
#                        trip is the TRIP MARKER, a file named
#                        `risk-switch-tripped` in the clone's git directory
#                        (`git rev-parse --git-common-dir`), outside version
#                        control: create it to trip the switch in this clone
#                        at once, delete it to reset. No environment variable
#                        reaches either.
# RISK_RULING_DEFAULTS   RULING DEFAULTS, whitespace-separated, each of the
#                        form `<review area>:<surface>`: the operator's answer
#                        given in advance. `sh scripts/ruling.sh <PR>
#                        --defaults --base <ref>` records an outward item of
#                        that surface ruled `keep` by default when every review
#                        area the pull request's diff touches is paired with
#                        it — `security:exit-code` rules an exit-code item on a
#                        PR touching security alone, never one that also
#                        touches test-hygiene. The area must be a review area
#                        of scripts/lens-slice.config.sh and the surface a word
#                        of the vocabulary's `surface` field other than
#                        `other`; any other entry is named on stderr and not
#                        applied. Read at the base like the rest, so a pull
#                        request cannot add one for itself. Ships EMPTY:
#                        a default is the operator's call, and `/retro`
#                        proposes one only from rulings that recur.

RISK_MISS_RATE_BELOW=5
RISK_PRECISION_FLOOR=80
RISK_JUDGING_EXTRA=''
RISK_KILL_SWITCH=on
RISK_RULING_DEFAULTS=''
