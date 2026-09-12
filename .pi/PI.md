# CLAUDART Pi Instructions

This repository contains CLAUDART, a markdown-based operating layer for AI coding agents. This file is the Pi layer's instructions index.

Pi does not auto-load this file by name. Per directory it loads the first match of `AGENTS.override.md`, `AGENTS.md`, `AGENTS.MD`, `CLAUDE.md`, `CLAUDE.MD`, starting at `~/.pi/agent/` and walking from ancestors down to the current directory. The project's root `AGENTS.md` carries a CLAUDART route line pointing here; follow it, then follow what this file routes to.

Skills live in `.agents/skills/` (searched in `cwd` and ancestors up to the git root) and are invoked as `/skill:<name>`. Pi asks to trust a project folder before loading project-local resources and `.agents/skills`, so a fresh clone needs that approval once before these commands appear.

## Context Loading

- Read `.pi/CONTEXT.md` for current session state before meaningful work.
- Read `.pi/tasks/index.md` (if it exists) for active implementation plans.
- Read `.pi/guidelines/ai-behavior.md`, then load only the additional guideline files relevant to the current task. Do not read every guideline blindly.
- Read `.pi/guidelines/knowledge-management.md` in full only when the task retrieves, writes, audits, or refactors project knowledge, or when the user asks for a knowledge update or prior-project evidence.
- Do not auto-load `.pi/JOURNAL.md`; use it only for explicit history or learning tasks.
- Do not auto-load `.pi/HANDOFF.md`; it is a one-shot session baton consumed by `/skill:pi-start`.
- Do not auto-load task bodies in `.pi/tasks/*.md` — read individual task files only when resuming or working on them.

## Core Commands

- `/skill:pi-start` — orients a new session from current state, task/spec indexes, the root knowledge map only, and recent Git history; it never runs the knowledge checker.
- `/skill:pi-plan <description>` — creates a persistent implementation plan in `.pi/tasks/`. Use instead of session-only planning for any multi-session or multi-file work.
- `/skill:pi-spec <mission>` — creates a mission-scale spec workspace in `.pi/specs/` — interview → POC artifact → decision-complete SPEC + ROADMAP, approved once as a standing approval.
- `/skill:pi-spec-run <slug>` — executes an approved spec autonomously until final review — verifies acceptance, records ROADMAP task dispositions and evidence, blocks unchanged failure loops, and offers session rotation at phase boundaries.
- `/skill:pi-project-discovery` — interviews the user about a rough project idea and creates a raw synthesis plus structured project docs.
- `/skill:pi-checkpoint` — bulk-maintains current state, task/spec indexes, JOURNAL, and eligible durable knowledge; it is not the only knowledge write gate.
- `/skill:pi-handoff` — writes a single-slot session baton (`.pi/HANDOFF.md`) distilling the session's reasoning state when the context window is nearly full or an investigation pauses mid-flight; the next `/skill:pi-start` consumes and deletes it.
- `/skill:pi-learn` — promotes validated recurring behavior into Pi guidelines and routes descriptive facts to knowledge.
- `/skill:pi-doctor` — runs the read-only mechanical checker plus semantic health audit.
- `/skill:pi-refactor-memory` — consolidates Pi memory and performs controlled, in-place knowledge normalization.

## Working Style

- Keep changes scoped to the user request.
- Prefer repository-local patterns over new abstractions.
- Report stale or conflicting AI-layer files instead of silently overwriting manual work.

## Guidelines

See `.pi/guidelines/ai-behavior.md` for universal AI behavior guidelines.
See `.pi/guidelines/code-health.md` for the continuous, behavior-preserving implementation baseline applied whenever code or code-adjacent artifacts are inspected or changed.
See `.pi/guidelines/task-management.md` for the persistent task-document workflow that replaces session-only plan mode.
See `.pi/guidelines/agent-delegation.md` for Pi subagent and parallel delegation protocol. Trust the harness on whether to delegate; the guideline supplies the how — decomposition, self-contained worker prompts, anti-shadow-run discipline, and persisting delegated findings.
See `.pi/guidelines/spec-workflow.md` for mission-scale spec workspaces in `.pi/specs/` — the loop-engineering layer above tasks, executed autonomously by `/skill:pi-spec-run` under a standing approval.
See `.pi/guidelines/knowledge-management.md` for the full knowledge routing, capture, schema, lifecycle, and validation contract. Load it only under the trigger in Context Loading.
Project knowledge: `.pi/knowledge/INDEX.md` is the root router surfaced by `/skill:pi-start`; topic bodies are read on demand.

## Knowledge Contract

- Map first: stay within 2 maps, 3 direct topics, and 2 one-hop related topics; inspect frontmatter, outline, and the smallest relevant section before a full body. Use bounded `rg`/Git evidence search only when routed context is insufficient; reading never writes.
- Capture only facts that are descriptive, durable beyond current work, current, and evidenced; scope may be narrow. WIP/proposals/state stay in task/spec/CONTEXT, behavior goes through `/skill:pi-learn`, and uncertainty remains a candidate or `review-needed`.
- Patch the existing owner first and update the topic plus its reachable map atomically. Never auto-delete or auto-promote ambiguous unindexed files.
- After every knowledge mutation, run `bash .pi/scripts/knowledge-check.sh --root .`. `/skill:pi-start` never runs it.

## Agent Self-Evolution & Context Maintenance

- "Do not assume a human will document your code patterns. If you build it, document it."
- Existing Pi guidelines change → update the relevant file in `.pi/guidelines/`.
- New domains/layers → create a new guideline file with flow-style `paths: [...]`, `description:`, `when_to_use:`, and inline `tags: [...]` frontmatter, then ensure `PI.md` points to it when globally relevant.
- Durable project facts → follow the four-invariant Knowledge Contract and the full knowledge guideline; a natural-language mid-session update is sufficient when the capture gate passes.
- Live state → update `.pi/CONTEXT.md` through `/skill:pi-checkpoint`.
