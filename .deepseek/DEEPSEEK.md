# CLAUDART DeepSeek Instructions

This repository contains CLAUDART, a markdown-based operating layer for AI coding agents. Treat `DEEPSEEK.md` as the DeepSeek-native project memory index.

## Context Loading

- Read `.deepseek/CONTEXT.md` for current session state before meaningful work.
- Read `.deepseek/tasks/index.md` (if it exists) for active implementation plans.
- Read `.deepseek/guidelines/ai-behavior.md`, then load only the additional guideline files relevant to the current task. Do not read every guideline blindly.
- Read `.deepseek/guidelines/knowledge-management.md` in full only when the task retrieves, writes, audits, or refactors project knowledge, or when the user asks for a knowledge update or prior-project evidence.
- Do not auto-load `.deepseek/JOURNAL.md`; use it only for explicit history or learning tasks.
- Do not auto-load `.deepseek/HANDOFF.md`; it is a one-shot session baton consumed by `$deepseek-start`.
- Do not auto-load task bodies in `.deepseek/tasks/*.md` — read individual task files only when resuming or working on them.

## Core Commands

- `$deepseek-start` — orients a new session from current state, task/spec indexes, the root knowledge map only, and recent Git history; it never runs the knowledge checker.
- `$deepseek-plan <description>` — creates a persistent implementation plan in `.deepseek/tasks/`. Use instead of session-only plan mode for any multi-session or multi-file work.
- `$deepseek-spec <mission>` — creates a mission-scale spec workspace in `.deepseek/specs/` — interview → POC artifact → decision-complete SPEC + ROADMAP, approved once as a standing approval.
- `$deepseek-spec-run <slug>` — executes an approved spec autonomously until final review — verifies acceptance, records ROADMAP task dispositions and evidence, blocks unchanged failure loops, and offers session rotation at phase boundaries.
- `$deepseek-project-discovery` — interviews the user about a rough project idea and creates a raw synthesis plus structured project docs.
- `$deepseek-checkpoint` — bulk-maintains current state, task/spec indexes, JOURNAL, and eligible durable knowledge; it is not the only knowledge write gate.
- `$deepseek-handoff` — writes a single-slot session baton (`.deepseek/HANDOFF.md`) distilling the session's reasoning state when the context window is nearly full or an investigation pauses mid-flight; the next `$deepseek-start` consumes and deletes it.
- `$deepseek-learn` — promotes validated recurring behavior into DeepSeek guidelines and routes descriptive facts to knowledge.
- `$deepseek-doctor` — runs the read-only mechanical checker plus semantic health audit.
- `$deepseek-refactor-memory` — consolidates DeepSeek memory and performs controlled, in-place knowledge normalization.

## Working Style

- Keep changes scoped to the user request.
- Prefer repository-local patterns over new abstractions.
- Report stale or conflicting AI-layer files instead of silently overwriting manual work.

## Guidelines

See `.deepseek/guidelines/ai-behavior.md` for universal AI behavior guidelines.
See `.deepseek/guidelines/code-health.md` for the continuous, behavior-preserving implementation baseline applied whenever code or code-adjacent artifacts are inspected or changed.
See `.deepseek/guidelines/task-management.md` for the persistent task-document workflow that replaces session-only plan mode.
See `.deepseek/guidelines/agent-delegation.md` for DeepSeek subagent and parallel delegation protocol. Trust the harness on whether to delegate; the guideline supplies the how — decomposition, self-contained worker prompts, anti-shadow-run discipline, and persisting delegated findings.
See `.deepseek/guidelines/spec-workflow.md` for mission-scale spec workspaces in `.deepseek/specs/` — the loop-engineering layer above tasks, executed autonomously by `$deepseek-spec-run` under a standing approval.
See `.deepseek/guidelines/knowledge-management.md` for the full knowledge routing, capture, schema, lifecycle, and validation contract. Load it only under the trigger in Context Loading.
Project knowledge: `.deepseek/knowledge/INDEX.md` is the root router surfaced by `$deepseek-start`; topic bodies are read on demand.

## Knowledge Contract

- Map first: stay within 2 maps, 3 direct topics, and 2 one-hop related topics; inspect frontmatter, outline, and the smallest relevant section before a full body. Use bounded `rg`/Git evidence search only when routed context is insufficient; reading never writes.
- Capture only facts that are descriptive, durable beyond current work, current, and evidenced; scope may be narrow. WIP/proposals/state stay in task/spec/CONTEXT, behavior goes through `$deepseek-learn`, and uncertainty remains a candidate or `review-needed`.
- Patch the existing owner first and update the topic plus its reachable map atomically. Never auto-delete or auto-promote ambiguous unindexed files.
- After every knowledge mutation, run `bash .deepseek/scripts/knowledge-check.sh --root .`. `$deepseek-start` never runs it.

## Agent Self-Evolution & Context Maintenance

- "Do not assume a human will document your code patterns. If you build it, document it."
- Existing DeepSeek guidelines change → update the relevant file in `.deepseek/guidelines/`.
- New domains/layers → create a new guideline file with flow-style `paths: [...]`, `description:`, `when_to_use:`, and inline `tags: [...]` frontmatter, then ensure `DEEPSEEK.md` points to it when globally relevant.
- Durable project facts → follow the four-invariant Knowledge Contract and the full knowledge guideline; a natural-language mid-session update is sufficient when the capture gate passes.
- Live state → update `.deepseek/CONTEXT.md` through `$deepseek-checkpoint`.
