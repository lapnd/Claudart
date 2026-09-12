---
name: context-cost-model
description: "Measured per-request context cost of the Claude layer and what makes a rule expensive versus a skill nearly free."
type: architecture
status: active
updated: 2026-09-12
last_verified: 2026-09-12
aliases:
  - "token cost"
  - "context budget"
triggers:
  - "context cost"
  - "token budget"
  - "rule vs skill"
scope:
  - "path:.claude/**"
sources:
  - "../skills/task-management/SKILL.md"
  - "../skills/spec-workflow/SKILL.md"
related:
  - "knowledge:instruction-tier-placement"
verify: "Re-run `claude -p 'ok' --model haiku --output-format json` and a Read-forcing prompt in a scratch repo, comparing usage.iterations[0] context against a repo with no .claude/."
sensitivity: public
---

# Context Cost Model

Measured 2026-09-12 with `claude -p --output-format json` on Haiku, 2-3 repetitions per cell, variance under 10 tokens. The figure that matters is **per-request context** from `usage.iterations[0]` — `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`. Summing those fields across a whole run double-counts the cached prefix on multi-turn runs and overstated one fixture by 2.4x.

## Loading is lazy, and that dominates everything

A rule in `.claude/rules/` carrying `paths:` does **not** load at session start. It enters context the first time Claude reads a file matching the glob. `paths: ["**/*"]` therefore means "on first file read", not "always".

A rule with **no** `paths:` field loads unconditionally at launch.

Consequence measured on this repo: with `paths:` present, a session that never touches a file cost 37,451 tokens and one that read a single file cost 59,992. Removing `paths:` made both 61,954 — no gain on the working session, and **+24,503 on the light one**.

An `@` import in `.claude/CLAUDE.md` of a file that also lives in `.claude/rules/` is deduplicated: it neither adds a second copy nor forces an early load. Two variants differing only by that import measured within 6 tokens of each other.

## What each tier costs

`.claude/commands/` held 127,971 bytes across ten files and cost **37 tokens** at launch, because only the catalog line loads. `.claude/rules/` held 97,185 bytes and cost **22,381 tokens** on a file-touching session. Same repository, 795x difference in cost per byte, decided purely by which directory the file sits in. `.claude/skills/` behaves like commands.

Per-file cost of the original six rules, isolated one at a time, summing to within 3 tokens of the combined measurement:

| File                                   | Tokens |  Bytes |
| -------------------------------------- | -----: | -----: |
| `spec-workflow`                        |  8,162 | 33,789 |
| `task-management`                      |  5,372 | 21,112 |
| `code-health`                          |  3,445 | 17,586 |
| `agent-delegation`                     |  3,057 | 14,202 |
| `ai-behavior` + `knowledge-management` |  2,348 | 10,496 |
| `CLAUDE.md` + `CONTEXT.md`             |  1,113 |  5,100 |

Roughly 4.1 bytes per token for dense instructional Markdown.

HTML comments are stripped from memory files before injection: `CONTEXT.md` is 807 bytes on disk but only 252 bytes reach context, so its comment header measured as zero. Explanatory headers in seed files are free.

Claude Code does **not** read `.agents/skills/`, so the Codex, DeepSeek and Pi skill sets in this repository cost a Claude session nothing.

## The tier decision

Choose by **when the text must be in context**, not by how important it is.

A constraint that applies to essentially every turn belongs in `.claude/rules/` — `ai-behavior` and `code-health` qualify. A contract that only applies inside one workflow belongs in `.claude/skills/`, where it costs a catalog line until something loads it.

Moving the four workflow contracts to skills measured 59,998 → 46,150 on a file-touching session here, and 91,441 → 68,057 on a larger downstream layer. The light-session cost rose 328 tokens for the four catalog entries.

Lazy loading has a real failure mode: `task-management` owns the read-only planning and awaiting-review locks, so a session that never loads it could edit code while a lock is in force. The mitigation is explicit, not probabilistic — every dependent command opens with a "First step: load the `<skill>` skill" line rather than relying on the model to notice.
