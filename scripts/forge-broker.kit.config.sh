#!/bin/sh
# forge-broker.kit.config.sh — the KIT'S OWN broker policy: the allow-list of
# forge operations scripts/forge-broker.kit.sh may perform on a dispatched
# worker's behalf. Kit-authoring only, never shipped (bootstrap.sh's KIT_ONLY
# list deletes it, the same as tests/ and the broker beside it).
#
# POLICY AS DATA (PRD #261, ADR-0009). The broker is the ONE thing standing
# between a worker that read untrusted content and the operator's forge
# token, so what it may do is a LIST here, read by a script with a suite,
# not a case block inside the script. Allowing a new operation later — an
# implementer worker opening a PR, a reply on a review thread — is an entry
# added to this list and a case added to the broker, each with its assertion,
# never a rewrite. An operation NOT on the list does not exist to the broker:
# nothing in a worker's report can name one, and a policy that omits one the
# broker was asked to perform is exit 78 (EX_CONFIG) with nothing posted.
#
# THE FORGE IS GITHUB, THROUGH `gh`. The endpoints below are paths under
# `repos/{owner}/{repo}/`, with `{pr}` standing for the PR number the OPERATOR
# named on the command line — never one read from the report. A second forge
# is a second policy file with its own endpoints, not a second broker.

# The operations the broker may perform, by name. Two in this release: a pull
# request review carrying the standards findings as inline comments, and one
# top-level comment carrying the behavior confirm-list.
BROKER_OPERATIONS='review comment'

# review — POST one pull request review.
BROKER_OP_REVIEW_ENDPOINT='pulls/{pr}/reviews'
# The review EVENT is a constant of this policy and is never a field of the
# report: a worker's word must not approve or block a PR. The broker accepts
# only COMMENT here — a blank event leaves the review PENDING and invisible to
# everyone but its author, and APPROVE or REQUEST_CHANGES would let a review
# satisfy branch protection on the say-so of the least-trusted agent in the
# chain. Widening this is a new decision record, not an edit.
BROKER_OP_REVIEW_EVENT='COMMENT'

# comment — POST one top-level issue comment on the PR.
BROKER_OP_COMMENT_ENDPOINT='issues/{pr}/comments'
