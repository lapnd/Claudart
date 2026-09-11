---
paths: ["**/*"]
description: The harness default that decides on its own whether and when to spawn subagents, with no project decomposition, worker-prompt, or finding-persistence contract.
when_to_use: Never loaded. Recorded so that `agent-delegation` can override this harness default in data rather than only in prose.
tags: [subagents, delegation, parallelism, orchestration]
level: vendor-default
authority: provisional
status: approved
since: 2026-09-06
stale_after: 2027-03-06T00:00:00Z
verified:
  - by: human:lapnd
    at: 2026-09-06T00:00:00Z
enforcer: judgement
load: never
---

# Vendor Default — Harness Delegation Default

This record names a **harness default**; it does not endorse one. The Claude Code Agent tool
decides on its own whether and when to fan out to subagents, and supplies no project-specific
contract for decomposition, worker prompts, shadow-run avoidance, worktree lifecycle, or how a
delegated finding is persisted.

`.claude/rules/agent-delegation.md` declares `overrides: [vendor/harness-delegation-default]`: the
project keeps the harness's whether/when judgement and replaces the unstated how with its own.
Recording it here makes that precedence checkable data instead of prose.

The record is never loaded (`load: never`) and carries no instruction of its own.
