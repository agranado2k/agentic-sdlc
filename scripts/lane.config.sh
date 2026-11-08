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

LANE_OPERATOR=''
