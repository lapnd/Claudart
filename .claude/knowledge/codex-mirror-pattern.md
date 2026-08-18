---
name: codex-mirror-pattern
description: "How .codex/guidelines files mirror their .claude/rules counterparts."
type: reference
status: active
updated: 2026-08-18
last_verified: 2026-08-18
scope:
  - "path:.codex/guidelines/**"
sources:
  - "../../.codex/guidelines/spec-workflow.md"
  - "../../.codex/guidelines/task-management.md"
  - "../../.codex/guidelines/agent-delegation.md"
---

# Codex Mirror Pattern

Most `.codex/guidelines/*.md` files are near-mechanical mirrors of their `.claude/rules/*.md`
counterparts: only paths (`.claude` → `.codex`) and slash commands (`/spec` → `$codex-spec`,
`/spec-run` → `$codex-spec-run`, etc.) differ. Confirmed for `spec-workflow.md` and
`task-management.md` — a `diff` shows only that substitution pattern.

`agent-delegation.md` is the exception. Its `.codex` mirror is an independently rewritten,
Codex-specific version: different delegation vocabulary (`explorer`/`worker`/`default` agents vs.
the `Agent` tool), a different concurrency model (`max_concurrent_threads_per_session`, Ultra
proactive delegation), no per-agent worktree-isolation bullet in its own "Safety And Cost", and
extra sections ("Good Uses", "Bad Uses", "How to Invoke") that `.claude/rules/agent-delegation.md`
does not have.

Before editing `.claude/rules/agent-delegation.md`, diff it against
`.codex/guidelines/agent-delegation.md` first — do not assume the mirror update is a simple
substitution the way it is for most other rule files.
