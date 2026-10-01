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
# TRACE_NUMBERED_TYPES — the subject types your forge numbers, held to ONE
# spelling: `<type>:#<digits>`, no leading zero. A subject is the trace's join
# key, and a join key with synonyms is not one — `show ticket:#12` never finds
# an event written `ticket:12`. With a type listed here, `emit` and `show`
# refuse any other spelling of it (exit 2, naming the accepted form), and
# `verify` names each old spelling already in the trace as an advisory.
#
#   ''                 no type is held to a spelling (the shipped default) —
#                      the grammar stays open, so a tracker that writes
#                      `ticket:PROJ-12` is never refused
#   'ticket pr prd'    a forge that numbers tickets, pull requests and PRDs
#                      with digits — the kit's own answer for itself
#
# Lowercase type words, space-separated; anything else is exit 2. Only this
# file sets it: an environment value is ignored.
TRACE_NUMBERED_TYPES=''

# TRACE_TOOLS — whether every TOOL CALL is captured too. Two honest values:
#
#   ''    tool capture is OFF (the shipped default)
#   1     every tool call your agent harness's tool hooks see becomes one
#         `tool.use` event, with the head of the input on the line and the full
#         input and full result in the blob store
#
# A SWITCH OF ITS OWN, beside TRACE_DIR rather than folded into it, because the
# two answers are genuinely different. A decision is one line a day; a tool call
# is hundreds of lines a session, and the least decision-bearing of them
# (ADR-0008 clause 8). So "trace my decisions" must not silently mean "keep
# every file I read and every command I ran, with its output".
#
# WHAT IT COSTS WHEN IT IS ON: disk, in your trace directory, proportional to
# what your tools returned — and a second look at privacy, because a tool result
# is the contents of whatever was read. Turn it on for a wave you want to study,
# and turn it off again; nothing rewrites what was already recorded.
#
# WHO READS IT: the tool hooks of an agent-harness adapter, which is the only
# place a tool call is visible at all. `scripts/trace.sh` never reads this line
# — an event is an event, whoever asked for it. With TRACE_DIR empty this switch
# changes nothing, for the same reason: there is nowhere to write.
#
# An environment TRACE_TOOLS overrides this line for one process, and an
# environment value of '' is the documented OFF even when this file says 1 —
# the precedence TRACE_DIR has.
TRACE_TOOLS=''

# ---------------------------------------------------------------------------
# TRACE_AGENT_WAIT_MS — how long, in milliseconds, a subagent-stop hook may wait
# for the subagent's transcript to hold its final message before reading what
# that subagent spent. Two honest values:
#
#   ''       no wait (the shipped default): the transcript is read the moment
#            the hook runs, exactly as before this line existed
#   <1-99999>  wait up to that many milliseconds, polling, and never longer
#
# WHY A HOOK WOULD WAIT AT ALL. An agent harness can run its subagent-stop hook
# a moment BEFORE the subagent's final turn reaches its transcript. Read then,
# the transcript holds no usage at all, or the turns before the last one — a
# sum that looks like success and is an undercount. Waiting closes that gap; a
# wait that runs out records the absence, with the wait it gave, and never a
# partial sum.
#
# WHY THE KIT SHIPS NO NUMBER. A hook is on the session's critical path, so this
# is how long your sessions may be held at every subagent stop whose transcript
# never completes — a trade between measured spend and latency that only you
# can price. The kit measured its own gap and chose its own bound, in its
# never-shipped twin of this file; read the adapter's subagent-stop hook for
# what was measured before you pick yours.
#
# A value that is not one to five digits with no leading zero is REFUSED: named
# on stderr and on the event, and not waited — the hook still exits 0. An
# environment TRACE_AGENT_WAIT_MS overrides this line for one process, and an
# environment value of '' is no wait even when this file names a bound. With
# TRACE_DIR empty nothing is waited for: there is nowhere to write. Keep the
# bound well under your agent harness's own time limit for a hook: a hook that
# is killed for running long leaves no agent.stop event at all.
TRACE_AGENT_WAIT_MS=''

# ---------------------------------------------------------------------------
# TRACE_BEHIND_WARN — how many commits the checkout your agent-harness hooks run
# from may sit behind origin/main before the session-start hook says so. Two
# honest values:
#
#   ''         no note (the shipped default)
#   <0-99999>  one line on stderr at every session start whose checkout is
#              MORE than that many commits behind
#
# WHY IT EXISTS. A hook runs the code of the checkout it lives in. When that
# checkout falls behind main, every fix to the hooks that main has landed is
# inert for the sessions it starts, and nothing says so. The session-start hook
# of an agent-harness adapter records the lag on every `session.start` whatever
# this line says — data.behind, counted with plain git against the LAST FETCHED
# origin/main, never a fetch of its own; a checkout with no origin/main records
# nothing — and this line only decides when that number is also said out loud.
#
# WHY THE KIT SHIPS NO NUMBER. How far behind is too far depends on how fast
# your main moves and how often you sync, which only you know.
#
# A value that is not a whole number of at most five digits with no leading
# zero is refused, named on stderr, and otherwise ignored — the hook still
# exits 0. An environment TRACE_BEHIND_WARN overrides this line for one
# process, and an environment value of '' is no note even when this file names
# one.
TRACE_BEHIND_WARN=''

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
# exactly this shape — the first such line is the one the script reads, so the
# placeholder below is deliberately NOT a date: an example with real digits in
# it would be the line the advisory found, and you would be told a date you
# never wrote (review of PR #294).
#
#   # Last checked: <YYYY-MM-DD>
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
