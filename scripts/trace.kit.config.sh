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
# THESE NUMBERS ARE UNSET ON PURPOSE. Last checked: NEVER — no figure below has
# been filled in, and none was invented. A price is a claim about a vendor's
# current rate card, and a wrong one does not fail loudly the way a wrong model
# id fails a spawn: it produces a confident number in a cost column that
# nobody re-derives. An empty value means exactly what it says — every cost
# column reads `unpriced` for that model, never 0, and the reader names it on
# stderr. FILLING THESE IN IS AN OPERATOR ACTION: put the four numbers from the
# vendor's own pricing page in, and replace the date above with the day you
# read it. Re-check whenever a vendor moves its prices; the trace does not
# need re-writing, because nothing in it was ever priced.
TRACE_PRICE_CLAUDE_FABLE_5_1=''
TRACE_PRICE_CLAUDE_OPUS_5_5=''
TRACE_PRICE_CLAUDE_HAIKU_4_5_20251001=''
TRACE_PRICE_CODEX_GPT_5_6_SOL=''
TRACE_PRICE_CODEX_GPT_6_ASTRA=''
