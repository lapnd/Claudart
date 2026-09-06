---
name: codex-mirror-pattern
description: "How .codex/guidelines files mirror their .claude/rules counterparts, and the two that do not."
type: reference
status: active
updated: 2026-09-06
last_verified: 2026-09-06
scope:
  - "path:.codex/guidelines/**"
sources:
  - "../../.codex/guidelines/spec-workflow.md"
  - "../../.codex/guidelines/task-management.md"
  - "../../.codex/guidelines/agent-delegation.md"
  - "../../.codex/guidelines/knowledge-management.md"
---

# Codex Mirror Pattern

Most `.codex/guidelines/*.md` files are near-mechanical mirrors of their `.claude/rules/*.md`
counterparts: only paths (`.claude` → `.codex`) and slash commands (`/spec` → `$codex-spec`,
`/spec-run` → `$codex-spec-run`, etc.) differ. Confirmed for `spec-workflow.md` and
`task-management.md` — a `diff` shows only that substitution pattern.

**Two files are exceptions**, and both are independently written rather than substituted.

`agent-delegation.md` is the first. Its `.codex` mirror is an independently rewritten,
Codex-specific version: different delegation vocabulary (`explorer`/`worker`/`default` agents vs.
the `Agent` tool), a different concurrency model (`max_concurrent_threads_per_session`, Ultra
proactive delegation), no per-agent worktree-isolation bullet in its own "Safety And Cost", and
extra sections ("Good Uses", "Bad Uses", "How to Invoke") that `.claude/rules/agent-delegation.md`
does not have.

`knowledge-management.md` is the second (verified 2026-09-06). `.claude/rules/knowledge-management.md`
is 62 lines with 4 `##` sections (Retrieve With Progressive Disclosure · Capture And Route · Canonical
Frontmatter · Maps And Size Bounds); `.codex/guidelines/knowledge-management.md` is 148 lines with 6
differently-named sections (Route With A Fixed Budget · Capture Gate And Destination · Mutation
Contract · Canonical Topic Frontmatter · Canonical Domain Map Frontmatter · Router Grammar And Scale).
They are also mutually exclusive by content — the Codex document names `.codex/knowledge` and
`$codex-` commands, the Claude rule names `.claude/knowledge` — so **no single byte-identical file can
serve both layers**. A plan that asks for one is working from a false premise.

Before editing either of these two `.claude/rules/*` files, diff it against its `.codex/guidelines/`
counterpart first — do not assume the mirror update is a simple substitution the way it is for most
other rule files.
