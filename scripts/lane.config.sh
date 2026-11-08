#!/bin/sh
# lane.config.sh — the LANE POLICY: who stands behind the low-risk lane, the
# one path on which a pull request judged low risk may land with no
# per-change human act.
#
# This file is DATA, not mechanism. It is read at the BASE BRANCH, through the
# policy reader (`sh scripts/policy.sh read scripts/lane.config.sh --base
# <ref>`), never from a pull request's tree: its name ends `.config.sh`
# directly under scripts/, so it is a judging file, and no pull request can
# open the lane that judges it.
#
# THIS FILE IS YOURS. It is not part of the shared layer (see VERSION), and a
# kit update does not overwrite it.
#
# ---------------------------------------------------------------------------
# WHY THE KIT SHIPS THIS EMPTY, AND WILL KEEP SHIPPING IT EMPTY
# ---------------------------------------------------------------------------
# Landing with no human act is an exception to shared invariant §7, and the
# exception holds only under a standing authorization that names the human
# behind it. A kit cannot name your operator, so the lane ships CLOSED: with
# no operator named, or a file the policy reader cannot read at the base, the
# lane holds every pull request with `closed`, and every pull request lands
# the way it does today, by a human. Opening it is your decision, recorded in
# a decision record of your own, and landed on the base branch by the human
# it names; closing it again is deleting the name.
#
# ---------------------------------------------------------------------------
# THE KEYS
# ---------------------------------------------------------------------------
# LANE_OPERATOR  the lane's operator, a forge login: 1 to 39 letters, digits
#                and single inner hyphens. Any other value reads as none, and
#                the lane stays closed.
# LANE_HOLD_PATTERNS  paths no lane run lands, whatever their risk: shell
#                patterns separated by spaces, matched against each path the
#                pull request's diff touches, of letters, digits, `.`, `_`,
#                `/`, `-` and `*` — a `*` crosses a `/`. A pattern out of that
#                shape holds every pull request with `path`. Ships empty: what
#                your lane must never land is yours to name. The files your
#                shared-layer manifest lists and the policy files read at the
#                base branch are held whatever you name here.
# LANE_LAND_COMMAND  the landing command /pr-iterate runs, with `--lane`, the
#                pull request and its ticket, once an iteration records green
#                and the risk rule prints `effective: low` at that head (its
#                LANE.md): plain words of letters, digits, `.`, `_`, `/` and
#                `-`, single spaces between; any other value reads as none.
#                Ships empty: with no command named, /pr-iterate runs none and
#                reports as it always has, whoever LANE_OPERATOR names.

LANE_OPERATOR=''
LANE_HOLD_PATTERNS=''
LANE_LAND_COMMAND=''
