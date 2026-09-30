#!/bin/sh
# vocab.config.sh — the VOCABULARIES the chain's judgments are held to: one
# closed token set per decision field, in canonical order, and the rules that
# hold between fields.
#
# This file is DATA, not mechanism. `scripts/vocab.sh` holds the checker; the
# words it checks against live here, in one reviewable file, so that adding a
# severity band or a triage action is a diff to one list and not a prose change
# across five skills.
#
# It is read by:
#   scripts/vocab.sh   (`check`, `fields`) — which a skill calls where it reads
#                      a decision line: /to-tickets before it publishes,
#                      /implement when it reads its ticket, /pr-iterate when it
#                      reads a review report or an untrusted-read return.
#
# THIS FILE IS YOURS. It is not part of the shared layer (see VERSION), it is
# not overwritten by a kit update, and editing it is the intended workflow —
# the same arrangement as scripts/guards.config.sh, scripts/agents.config.sh
# and scripts/trace.config.sh. UNLIKE those three it ships FILLED: a model id
# is a vendor's to name and rots on the vendor's schedule, a vocabulary is the
# kit's to name and does not, so the words below are the ones the shipped
# skills already use. Delete the file and the checker is held to the same
# words, which it carries as its defaults; edit it and the checker is held to
# yours.
#
# ---------------------------------------------------------------------------
# WHO OWNS EACH FIELD. The checker refuses a value outside a field's tokens;
# it never decides what the tokens are, and for ONE field neither do you:
#
#   tier — owned by scripts/agents.lib.sh, the capability-tier resolver. The
#          four names are CLOSED in the manual layer (ADR-0003), and the
#          resolver refuses a fifth with exit 2 whatever this file says. The
#          checker reads the tier here for consistency and never widens it: a
#          fifth token added below is accepted by the checker and refused at
#          spawn, so the one place a tier is added is the manual, first.
#
# Every other field below is owned by this file — edit its tokens freely —
# and the skill that stamps it is named beside it.
#
# TWO RULES EVERY TOKEN IS HELD TO, at load, by the checker:
#
#   SHAPE     `[a-z][a-z0-9-]*`, the task domain's, because a token may be
#             interpolated into a variable name the way a domain is.
#   NEUTRAL   no token carries its answer in its spelling — `apply` and
#             `escalate`, never `safe-to-apply` and `risky` — because a judge,
#             model or agent, reads the label as evidence and follows it
#             instead of the state (the research behind PRD #273).
#
# And ONE CONVENTION the checker cannot hold you to: the tokens' ORDER is
# CANONICAL — the order a judge is shown them, fixed and recorded here so a
# later calibration can say whether position moved the answer. Reordering a
# list is a change, not a tidy-up. Nothing in a consumer's tree enforces it;
# in the kit, tests/vocab-policy.test.sh holds each list's order to the skill
# that spells it.
#
# ---------------------------------------------------------------------------
# THE FIELDS. VOCAB_FIELDS names them; VOCAB_<FIELD> (upper-cased, hyphens
# folded to underscores) holds each one's tokens; VOCAB_OPEN names the fields
# whose membership is NOT enforced — only the shape is — because their
# vocabulary is open local policy, as the task domain's is.

VOCAB_FIELDS='tier label domain severity status action outcome confidence command-shaped author'
VOCAB_OPEN='domain'

# tier — owned by scripts/agents.lib.sh (see above); stamped by /to-tickets
# as `Tier:`, read by /implement.
VOCAB_TIER='planner implementer mechanical reviewer'

# label — the autonomy label /to-tickets decides at write time: the tracker
# label `ready-for-agent`, or its absence, which means a human stays in the
# loop. `none` is the absence, spelled so a stamp can carry it.
VOCAB_LABEL='ready-for-agent none'

# domain — the task domain, stamped as `Domain:` only when the medium would
# change which model you would pick. OPEN: the resolver falls back to the tier
# for a token it does not map, so an undeclared token is not an error here
# either. The tokens are the kit's own, recorded for their canonical order.
VOCAB_DOMAIN='content code tests html-report self-implemented'

# severity — /review-pr's Axis 1 bucket per finding, in the order its report
# lists them. The skill prints them upper-cased beside a badge; the token is
# the word.
VOCAB_SEVERITY='critical high medium low'

# status — the tag on one line of /review-pr's Axis 2 confirm-list, in the
# order the list prints them: the commit-separation finding first, then the
# behavior deltas. The 🧬 MUTATION line is a measurement of the list, not a
# classification, and is deliberately not a token.
VOCAB_STATUS='mixed-commit unspecified specified missing'

# action — /pr-iterate's triage of one review item: apply it, reply on the
# thread with a citation, or escalate to the operator.
VOCAB_ACTION='apply reply escalate'

# outcome — the dogfooding pass's reading of one matrix row: the assertion
# held, it did not, or it held but the thing was not decent to use. (The
# skill is optional; the field ships either way, and names no command so a
# tree that declined it stays clean.)
VOCAB_OUTCOME='pass fail paper-cut'

# confidence — how sure a stamp LOOKED to the session that made it, never how
# likely it is right; three tokens, stamped on the tier and the label so the
# quiz can sort the doubtful ones first.
VOCAB_CONFIDENCE='low medium high'

# command-shaped — whether an untrusted body read by a subagent is shaped like
# an instruction to the agent. Not a stamp; the field the one shipped rule
# below reads.
VOCAB_COMMAND_SHAPED='yes no'

# author — who wrote an untrusted body a subagent read for /pr-iterate: an
# account the forge types as a bot, or anyone who is not one. Not a stamp, and
# not the reader's line either: the forge states it, so the CALLER writes it
# from the forge's author data and checks it beside the two decision lines the
# read returns, `action` and `command-shaped`.
VOCAB_AUTHOR='bot human'

# ---------------------------------------------------------------------------
# THE RULES. One per line: `<field>=<value> => <field>=<value>` demands the
# consequent whenever the antecedent holds; `… => <field>!=<value>` forbids
# it. The checker refuses a value a firing rule forbids, and reports a rule
# set that no combination of values can satisfy as a POLICY CONTRADICTION —
# distinct from a bad value, so you fix the file and not the ticket.
#
# The shipped rule is the trust boundary's: a body shaped like a command to
# the agent is never applied, whatever else it says.
VOCAB_RULES='command-shaped=yes => action!=apply'
