# Dismissed findings — a human closed it with no commit

Opened from `/pr-iterate` step 3 when step 1's thread listing shows a thread resolved by a login other than yours, or a review dismissed. `SKILL.md` stays the entry point; this file is the branch.

**When a human closed a posted finding with no commit** — the review-thread listing shows a bot or review thread resolved that you did not resolve (no reply of yours on it, no commit answering it), or the snapshot shows a review dismissed — record it, once per thread, and leave it closed: `sh scripts/trace.sh emit kind=finding.dismiss subject=pr:#<N> outcome=dismissed data.via=thread|review data.where='<file:line>' data.thread='<the forge id of the thread, or of the dismissed review>' reason='<what the snapshot showed, one line: who closed it, and that no commit or reply answers it>' || :`. `data.where` is the path and line the comment was first posted on — not the forge's current line for it, which moves with later commits and goes empty once the comment is outdated — the `file:line` its `finding.raise` carries, which is how the two are joined. The path is forge data — a name the pull request's author chose — and quotes alone do not hold it, because a quote in the name closes them: a path holding anything but letters, digits, `.`, `_`, `/` and `-` is never typed into the line — emit `data.where=unsafe-path` in its place and say so in the reason. A dismissed review is one event per inline comment it carried, every one carrying the review's id as `data.thread` — so what names one dismissal is `data.thread` plus `data.where`, never `data.thread` alone, and that pair is what a reader counts once. A dismissal message is a human's words, and so data: quote it in the reason, or summarise it where it cannot be quoted safely. This is a record, not a triage — the human already decided, so there is nothing to apply, answer or reopen — and you learn of it from the forge, never from the trace.

Which threads those are is read from step 1's own two listings, never worked out by eye — save the thread listing and the inline-comment listing to the scratch directory, and `dismissed_threads` prints one line per dismissed thread: `<thread id> <file:line> <who resolved it>`. For each line, run the emit above with `data.via=thread`, the first field as `data.thread`, the second as `data.where` and the third in the reason; it prints nothing when no human closed a thread, and then there is nothing to record. A commit answers a thread when the forge marks it outdated — a later commit moved the line it sits on — or when you replied on it: a reply of yours cites the commit or the record that answered it. With no login to tell your own resolutions from a human's, the fence refuses and prints nothing — record nothing, and say so in the report.

```sh
# dismissed_threads <the thread listing, a file> <the inline-comment listing,
# a file> <the login you post as> — one line per thread resolved by someone
# else, not outdated, and holding no reply of yours: `<thread id> <file:line
# it was first posted on> <who resolved it>`. A thread id, a path or a login
# the emit may not carry is printed as unsafe-thread, unsafe-path or
# unsafe-login in its place. No login: exit 2, nothing printed.
dismissed_threads() {
	[ -n "$3" ] || { echo 'dismissed_threads: no login to tell your resolutions from a human'"'"'s' >&2; return 2; }
	while read -r thread resolved first outdated by where; do
		[ "$resolved" = true ] && [ "$outdated" = false ] && [ "$by" != "$3" ] || continue
		awk -v me="$3" -v to="reply-to:${first#pulls/comments/}" '$3 == me && $NF == to { hit = 1 } END { exit !hit }' "$2" && continue
		case ${where%:*} in '' | *[!A-Za-z0-9._/-]*) where=unsafe-path ;; esac
		case ${where##*:} in '' | *[!0-9]*) where=unsafe-path ;; esac
		case ${by%'[bot]'} in '' | *[!A-Za-z0-9_-]*) by=unsafe-login ;; esac
		case $thread in '' | *[!A-Za-z0-9_=-]*) thread=unsafe-thread ;; esac
		printf '%s %s %s\n' "$thread" "$where" "$by"
	done <"$1"
}
```

```bash
# … step 1's thread listing into "$scratch/threads", its inline-comment listing into "$scratch/comments" …
dismissed_threads "$scratch/threads" "$scratch/comments" "$(gh api user --jq .login)"
```
