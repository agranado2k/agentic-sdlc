#!/bin/sh
# trace.config.sh — the one place the kit learns WHERE your decisions are
# traced, and whether they are traced at all.
#
# This file is DATA, not mechanism. `scripts/trace.sh` holds the writer, the
# reader and the closed vocabulary; the one fact it cannot know — whether this
# project wants a trace, and where — lives here, in one reviewable file.
#
# It is read by:
#   scripts/trace.sh   (`emit`, `show`, `summary`, `export`, `verify`, `dir`) —
#                      which every chain skill calls at its decision points, and
#                      which you call to read the trail back.
#
# THIS FILE IS YOURS. It is not part of the shared layer (see VERSION), it is
# not overwritten by a kit update, and editing it is the intended workflow —
# the same arrangement as scripts/guards.config.sh and scripts/agents.config.sh,
# for the same reason: the kit owns mechanism, your repo owns policy.
#
# ---------------------------------------------------------------------------
# WHY THE KIT SHIPS THIS EMPTY
#
# A trace is findings, reasons, prompts and token counts, on disk, in plain
# text — private data by the root manual's own trust boundary. Turning that on
# unasked would write a hidden directory of it into every consumer's tree, and
# the kit does not own your ignore file. So: UNSET IS A WORKING STATE. With
# TRACE_DIR empty every emit exits 0 having written nothing, after one note on
# stderr. The note is the whole nudge; nothing fails.
#
# The kit itself traces its own sessions — through a never-shipped twin of this
# file, reached by the TRACE_CONFIG seam, exactly as its tier mapping and its
# guard policy are (ADR-0003, as amended).
#
# ---------------------------------------------------------------------------
# TRACE_DIR — where the trace lives. Three honest values:
#
#   ''               tracing is OFF (the shipped default)
#   '.trace'         a directory under the ROOT CHECKOUT: an emit from inside a
#                    linked worktree lands beside the root's .git, so pruning
#                    the worktree loses nothing. Add it to .gitignore — the
#                    trace is local by design, never pushed by the kit.
#   '/abs/path'      anywhere else, taken as given.
#
# An environment TRACE_DIR overrides this line for one process.
TRACE_DIR=''

# ---------------------------------------------------------------------------
# THE PRICE TABLE — what a token costs, so `summary` and `export` can say what
# a wave cost.
#
# Cost is computed when you READ the trace, never when an event is written
# (ADR-0008 clause 6). An event carries the model and four raw token counts,
# because those are facts; a price is an interpretation that rots on a vendor's
# schedule. Writing a cost into an event would freeze one day's price into
# history and make a price correction unable to reach it. Pricing on read means
# you can re-price the whole past by editing this file.
#
# One variable per model, four prices in USD PER MILLION TOKENS, in the order
# the four token fields sit in the event:
#
#   TRACE_PRICE_<MODEL>='<in>,<out>,<cache_write>,<cache_read>'
#
# <MODEL> is the model id as your events spell it, folded to a variable token:
# upper-cased, with every character that is not a letter or a digit turned into
# an underscore. So a model id `some-vendor:model-1.5` is priced by
# TRACE_PRICE_SOME_VENDOR_MODEL_1_5. Illustrative shape, NOT a real price:
#
#   TRACE_PRICE_SOME_VENDOR_MODEL_1_5='1,5,1.25,0.10'
#
# THE KIT ASSIGNS NOTHING HERE, for the same reason scripts/agents.config.sh
# names no model: a price the kit shipped would be a number with a timer on it,
# wrong on some silent future day and believed anyway. A model with no price
# reads `unpriced` in every cost column — never 0 — and the models that needed
# a price and lacked one are named on stderr. Date the table when you fill it
# in, and re-check it when your vendor moves: an export stamps `priced_at` and
# `price_src` so an old export and a new one can be told apart.
#
# ---------------------------------------------------------------------------
# DATE THE TABLE, AND SAY HOW LONG A DATE IS GOOD FOR.
#
# Write the day you read the prices as a comment anywhere in this file, in
# exactly this shape — the first such line is the one the script reads:
#
#   # Last checked: 2026-01-31
#
# TRACE_PRICES_STALE_DAYS is how many days that claim stays unremarked. Past it,
# every priced read — `summary`, and `export --csv` — prints ONE advisory on
# stderr naming the date and this window. It is an ADVISORY in the full sense:
# nothing fails, no exit status changes, the figures are still printed, and
# TRACE_QUIET=1 silences it with every other note.
#
# EMPTY IS NO WINDOW AND NO ADVISORY — the same working state an empty TRACE_DIR
# is. A number the kit picked for you would be the kit deciding how fresh your
# cost figures have to be, which is exactly the decision it has no standing to
# make. Thirty days is a reasonable first answer if you want one.
TRACE_PRICES_STALE_DAYS=''

# WHERE TO READ A PRICE, when the advisory fires. Three suggestions, no figures
# — the kit states no price as fact, here or anywhere:
#
#   * LiteLLM's `model_prices_and_context_window.json` (in its repository on
#     GitHub) — machine-readable, one object per model, costs per token, and
#     the broadest coverage of the three.
#   * OpenRouter's `/api/v1/models` — machine-readable too, and a useful
#     CROSS-CHECK rather than a replacement: two independent sources that
#     agree are worth more than one that is convenient.
#   * Your vendors' own pricing pages — the human TIE-BREAKER, and the only
#     authority. When the two machine-readable sources disagree, the vendor's
#     page decides; when they agree, it is still what you would quote.
#
# Both of the first two rot on somebody else's schedule and neither is a
# contract. Read two, believe the vendor, and write the date.
