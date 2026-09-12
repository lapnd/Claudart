# CLAUDART Project Memory

## Project Overview

CLAUDART keeps the Claude-specific operating layer inside `.claude/`, including session state. If Claude Code `/init` generates a root `CLAUDE.md`, copy its useful project-specific content into this file before running `/refactor-memory`.

## Core Commands

- `/start` orients a new session from `.claude/CONTEXT.md`, task/spec indexes, the root knowledge router, and recent git history.
- `/plan <description>` creates a persistent implementation plan in `.claude/tasks/` — use instead of native plan mode for any multi-session or multi-file work.
- `/spec <mission>` creates a dated mission-scale spec workspace in `.claude/specs/` — interview → POC artifact → decision-complete SPEC + ROADMAP, approved once as a standing approval.
- `/spec-run <slug>` executes an approved spec autonomously until final review — verifies acceptance, records ROADMAP task dispositions and evidence, blocks unchanged failure loops, and offers session rotation at phase boundaries.
- `/refactor-memory` consolidates the memory system and normalizes knowledge in place.
- `/project-discovery` interviews the user about a rough project idea and creates a raw synthesis plus structured project docs.
- `/checkpoint` rewrites current state, syncs task/spec indexes, appends meaningful history, and bulk-maintains eligible knowledge candidates.
- `/handoff` writes a single-slot session baton (`.claude/HANDOFF.md`) distilling this session's reasoning state — run when the context window is nearly full or when pausing mid-investigation; the next `/start` consumes and deletes it. Never auto-load `HANDOFF.md`.
- `/learn` promotes validated recurring behavior into `.claude/rules/` and routes descriptive facts to knowledge.
- `/doctor` runs the mechanical knowledge checker followed by a read-only semantic health audit.

## Domain Rules

See @.claude/CONTEXT.md for the current state of work (updated by /checkpoint).
See @.claude/rules/ai-behavior.md for universal AI behavior guidelines.
See @.claude/rules/code-health.md for the continuous, behavior-preserving implementation baseline applied whenever code or code-adjacent artifacts are inspected or changed.

## Workflow Skills

These four contracts live in `.claude/skills/` and load on demand, not every session. Load the matching skill **before** acting in its area — do not work from memory of it.

Load `task-management` before creating, resuming, or completing anything in `.claude/tasks/`, and whenever a task file is open. It owns the read-only planning and awaiting-review locks, so acting without it risks editing code while a lock is in force.
Load `spec-workflow` before any work inside `.claude/specs/`, and whenever a spec is `ready`, `running`, or `blocked`. It owns the standing approval, the ROADMAP dispositions, and the final gate.
Load `agent-delegation` before delegating to subagents or recording a delegation strategy.
Load `knowledge-management` before reading, writing, routing, or auditing `.claude/knowledge/`.

Project knowledge: `.claude/knowledge/INDEX.md` is the root router surfaced by `/start`; it and topic bodies are not auto-imported. Route entries on demand under the knowledge rule.

## Agent Self-Evolution & Context Maintenance

- "Do not assume a human will document your code patterns. If you build it, document it."
- Existing rules change -> update the relevant file in `.claude/rules/`.
- New domains/layers -> decide the tier by **when it must be in context**. A constraint that applies to essentially every turn becomes a rule in `.claude/rules/` with flow-style `paths: [...]`, `description:`, `when_to_use:`, and inline `tags: [...]`, plus an `@` import here. A contract that only applies inside one workflow becomes a skill in `.claude/skills/<name>/SKILL.md` with `name:` and `description:`, plus a "load it before…" line under Workflow Skills. Measured on this repo: a rule costs its full body on every file-touching session; a skill costs only its catalog line until something loads it.
- Durable descriptive facts that pass the knowledge rule -> patch the canonical topic and reachable map atomically, then run the knowledge checker. Mid-session natural-language updates are valid; `/checkpoint` is bulk maintenance, not the sole write gate.
- Global changes -> update `.claude/CLAUDE.md` directly.
