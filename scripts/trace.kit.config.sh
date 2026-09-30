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

# The kit's forge numbers tickets, PRs and PRDs with digits, so its own trace
# holds them to one spelling, `<type>:#<digits>` (#305). The shipped file
# leaves this empty: which types a tracker numbers is each project's call.
TRACE_NUMBERED_TYPES='ticket pr prd'

# TOOL CAPTURE IS ON HERE, and this is the one file in the repository that says
# so. The kit's product IS the chain, so what its own sessions actually did —
# which command, against which file, with what result — is the raw material a
# retrospective reads, and the volume the shipped default protects a consumer
# from is the volume this repo wants. Nothing outside `.trace/` grows: the
# directory is gitignored and no event ever leaves the machine.
#
# Read by the Claude Code adapter's tool hooks, which .claude/settings.json — the
# only file in this repository that names them — points at this file through the
# TRACE_CONFIG seam. Turn capture off for one command with `TRACE_TOOLS= …`, the
# way TRACE_DIR is turned off.
TRACE_TOOLS=1

# ---------------------------------------------------------------------------
# THE PRICE TABLE — the SHAPE is here; the numbers are the operator's.
#
# `summary` and `export` price an event's token counts on READ (ADR-0008 clause
# 6), from one variable per model: four prices in USD PER MILLION TOKENS, in
# the order the four token fields sit in the event —
#
#   TRACE_PRICE_<MODEL>='<in>,<out>,<cache_write>,<cache_read>'
#
# — where <MODEL> is the model id as the events spell it, upper-cased with
# every character that is not a letter or a digit folded to an underscore. The
# five entries below are the five models scripts/agents.kit.config.sh maps, run
# through that fold, so the table's shape matches this repo's own tier mapping
# and an operator filling it in has nowhere to guess at a name. Two of them are
# reached through the dispatcher as `<harness>:<model>`, and the name here
# folds the whole value the resolver prints, because that is what an event
# records.
#
# THESE NUMBERS ARE A CLAIM WITH A DATE ON IT. Last checked: 2026-09-28, by the
# operator, against the vendors' own pricing pages — the only sources a price
# may come from here, because a made-up rate produces a confident number in a
# cost column that nobody re-derives, and unlike a wrong model id it never
# fails loudly. Four USD figures per million tokens: input, output, cache
# write (the 5-minute write, which is what a session's hooks record), cache
# read. Re-check whenever a vendor moves its prices and replace the date; the
# trace never needs re-writing, because nothing in it was ever priced.
#
# THE WINDOW AND THE THRESHOLD, the kit's own two answers:
#
#   TRACE_PRICES_STALE_DAYS   how long the date above stays unremarked. Past it,
#                             every priced read prints one advisory on stderr —
#                             never a failure. Thirty days, because that is the
#                             housekeeping cadence this repo already runs on, so
#                             a stale table is noticed by the pass that would
#                             have to act on it. The shipped policy file leaves
#                             it empty, by principle; this is the kit deciding
#                             for itself, like TRACE_DIR above.
#   TRACE_PRICES_DISAGREE_PCT how far the two machine-readable sources may differ
#                             on one price field before the refresh script
#                             REFUSES to write and prints both. Five per cent:
#                             wide enough for rounding and a promotional rate
#                             one source has not picked up, narrow enough that a
#                             real move by either shows up as a refusal rather
#                             than as a silently averaged number. Read only by
#                             scripts/trace-prices.kit.sh — the shipped policy
#                             file names no threshold, because the script that
#                             reads one is kit-only.
TRACE_PRICES_STALE_DAYS='30'
TRACE_PRICES_DISAGREE_PCT='5'

# The machine-readable sources, and the revision of each payload the last
# refresh actually read. These two lines are REWRITTEN by
# scripts/trace-prices.kit.sh (kit-only, on demand, network required): the hash
# is git's own of the bytes it fetched, so "which revision said that" is a
# question with an answer rather than a memory. They are the only lines in this
# file, besides the five values and the date above, that the script owns.
#   primary: (never refreshed — the values above were read by hand)
#   cross:   (never refreshed — the values above were read by hand)
#
# The human tie-breakers — the vendors' own pages, which decide when the two
# machine-readable sources disagree, and which the values below were first read
# off by hand on the date above:
#   https://platform.claude.com/docs/en/about-claude/pricing   (Fable, Opus, Haiku)
#   https://developers.openai.com/api/docs/pricing             (gpt-6-astra, gpt-5.6-sol)
# No figure is repeated in this comment on purpose: the values are below, and a
# second copy in prose is a second thing to keep in step — one a refresh would
# leave contradicting the variables it just rewrote. What the pages said that
# does not fit in a price field: cache read is 0.025x input on Fable 5.1 and
# 0.05x on Opus 5.5, and gpt-5.6-sol's rate is promotional through 2026-11-21
# at least.
#   Cache writes on both vendors are 1.25x the input rate; long-context
#   surcharges (OpenAI above ~272K input) are NOT modelled — a wave here never
#   reaches them, and a price is one number per token field.
TRACE_PRICE_CLAUDE_FABLE_5_1='10,50,12.50,0.25'
TRACE_PRICE_CLAUDE_OPUS_5_5='4,20,5,0.20'
TRACE_PRICE_CLAUDE_HAIKU_4_5_20251001='1,5,1.25,0.10'
TRACE_PRICE_CODEX_GPT_5_6_SOL='4,20,5,0.40'
TRACE_PRICE_CODEX_GPT_6_ASTRA='10,50,12.50,1.00'
