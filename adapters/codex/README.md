# Codex task-entry adapter

This adapter records the host-specific edge around the portable task command.
It was checked locally with `codex-cli 0.159.0` on 2026-09-30: `codex features
list` reported `hooks` as stable and enabled. The portable mechanism remains
`scripts/task.sh`; this directory adds no broker, dispatcher, settings file, or
active hook.

## The ordinary-request entry rule

Before the first production edit, classify the request, write its task contract
outside the repository, and run:

```sh
sh scripts/task.sh start . /tmp/task.contract
```

If start refuses, do not edit. Follow the proportional route recorded by the
contract using the existing skill chain. A small implementation goes to
`/implement`; a wave goes through its PRD and decomposition before one ticket is
implemented; read-only and report-only work end at their artifact. Preserve the
contract's endpoint and standing authorization. Never infer merge authority.

This is an instruction-level boundary and is **advisory** in Codex until a live
host integration demonstrates interception before every production-edit path.
The command proves that scope existed when it ran; it cannot prove by itself
that the host invoked it first.

## Optional hooks, reviewed before trust

Codex 0.159.0 exposes interactive `/hooks` as the review and trust surface for
hook definitions. A project must be trusted, and a current non-managed hook
definition hash must be approved, before that definition is trusted. This
adapter deliberately ships no Codex hook definition and changes no trust state.
An operator who adds one should use `/hooks` to inspect and approve the exact
definition; never use `--dangerously-bypass-hook-trust`, and do not use
`--ignore-user-config` as a way around trust settings.

The documented `PreToolUse` event can cover the canonical `apply_patch` and
`Bash` shell tool names, but specialized tool paths may opt out. Malformed hook
responses may fail open. A `Stop` hook can request another turn, and must use
`stop_hook_active` to avoid a repeated-stop loop. Those limits are why an
offline checker, a transcript check, or a pre-push hook is not described as
runtime enforcement here. Whether non-interactive `codex exec` reuses persisted
interactive hook trust was not verified and remains unknown.

The live enabled-versus-disabled demonstration, including covered and bypass
paths, belongs in the lifecycle evaluation slice. If provider credits or a
trusted runtime are unavailable, record that demonstration as blocked rather
than treating this dormant adapter as a pass.

Official references checked for this adapter:

- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Codex configuration basics](https://learn.chatgpt.com/docs/config-file/config-basic)
- [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode)
- [Codex skills](https://learn.chatgpt.com/docs/build-skills)
