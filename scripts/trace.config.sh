#!/bin/sh
# trace.config.sh — the one place the kit learns WHERE your decisions are
# traced, and whether they are traced at all.
#
# This file is DATA, not mechanism. `scripts/trace.sh` holds the writer, the
# reader and the closed vocabulary; the one fact it cannot know — whether this
# project wants a trace, and where — lives here, in one reviewable file.
#
# It is read by:
#   scripts/trace.sh   (`emit`, `show`, `verify`, `dir`), which every chain
#                      skill calls at its decision points.
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
