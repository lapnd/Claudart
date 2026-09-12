---
paths: ["**/*"]
description: How to handle work that would normally be delegated, given that Pi has no built-in subagents — decompose in place, or hand a self-contained unit to a separate Pi instance.
when_to_use: When work looks parallelizable, when planning a task that records a delegation strategy, or when consuming results produced by a separate Pi instance.
tags: [delegation, decomposition, parallelism, single-agent]
---

# Agent Delegation

**Pi has no built-in subagents.** It ships a small core — `read`, `write`, `edit`, `bash`, extended by skills, prompt templates, extensions and packages — and deliberately skips sub-agent spawning and plan mode. There is no spawn API to call, no explorer/worker roles, and no per-delegate model selection.

That does not make this guideline empty. The failure modes delegation exists to prevent — losing track of what a unit owns, re-deriving the same answer twice, accepting an unverified result, letting findings evaporate when the context window compacts — all still apply to a single long-running session. This file is how CLAUDART handles them without subagents.

Do not invent a spawn mechanism. If a project instruction, a habit from another harness, or a user request assumes one, say plainly that Pi does not have it and use one of the two paths below.

## The two real options

**1. Do the unit inline (the default).** Most work that another harness would delegate is simply the next thing to do. Decompose it explicitly — see below — and work through the parts in order, keeping the task or spec file updated as you go.

**2. Hand it to a separate Pi instance.** For genuinely independent work that would otherwise bloat this session's context, start a second Pi in another terminal or tmux pane, scoped to its own unit. This is manual and the user drives it: propose it, name the unit, and let them decide. The two sessions share nothing but the repository, so everything the second instance needs must be written down — that is what the Unit Brief below is for.

Prefer (1) unless the unit is large enough that carrying it inline would force a compaction, or the user explicitly wants parallel terminals.

## Decompose before you commit to an order

Even without fan-out, write the decomposition down before starting a multi-part change:

- **Critical path**: what must happen first, and why the rest depends on it.
- **Independent parts**: work that could be done in any order, or by a second instance.
- **Ownership**: the exact files or question each part covers, so two parts never edit the same region.
- **Merge and verification plan**: how each part gets checked before the next begins.

Record this under `## Plan of Work` or `### Memory Hints` in the task file, or in the spec `NOTES.md`. A decomposition that lives only in the session is lost at the next compaction.

## The task-file `delegation:` field

The `/skill:pi-plan` task-file `delegation:` field records a strategy, not a permission. On Pi its values mean:

- **`none`** — no specific strategy recorded. Work through the plan inline.
- **`strategy-only`** — a decomposition is recorded in Plan of Work / Memory Hints. Follow it inline, in the recorded order.
- **`authorized`** — the user recorded a plan that involves a second Pi instance. On "go", follow it and say which unit you are taking and which one you are leaving for the other instance.

This section is the single source of truth for the field's values on this layer; `task-management.md` → "Approval Signal" only describes how "go" carries the field into execution.

## Avoid re-deriving your own work

The single-session version of shadow-running is answering the same sub-question twice: re-reading files you already summarized, re-searching for a symbol you already located, re-running an investigation whose conclusion is already in the task file.

- When you establish a fact, write it where it will survive — task file, spec `NOTES.md`, or `CONTEXT.md` — and refer back to it instead of re-deriving it.
- Before a broad search, check whether the answer is already in the current task's Memory Hints or a knowledge topic.
- After a compaction, re-orient from files rather than from what you think you remember. The files are the truth; the summary is lossy.

## Unit Brief — what a second Pi instance needs

A second instance inherits nothing. If the user runs one, write the brief into the repository (the task file, or a spec `NOTES.md` entry) rather than pasting it into chat, so the other session can read it and so this session can check the result later:

- **Goal**: the exact user-visible outcome for that unit.
- **Scope**: files or modules that instance may edit.
- **Non-overlap**: what this session is editing concurrently, and that neither side may revert the other's work.
- **Constraints**: tests, style, security, compatibility.
- **Output**: what it must leave behind — changed files, the validation command it ran and the result, residual risks.

Then record the handoff at the moment it happens: in the task file for planned work, or as a `delegated` entry in the spec `LEDGER.md`. Mark it consumed once you have integrated and verified the result. A compaction must never orphan work running in another terminal — the file, not session memory, is what remembers it.

## Integrating work from a second instance

- Review its diff yourself. Another Pi's "done" is a claim to check, not a result to record.
- Integrate one coherent change at a time, running the relevant validation after each — a batch merge with one test run makes a failure unattributable.
- Resolve conflicts directly. Do not bounce a conflict back and forth between terminals.
- If the result is wrong or partial, take the unit back into this session rather than re-issuing the same brief.

## Persisting findings

- Task/spec state, WIP, proposals, and uncertain claims stay in the owning task, spec, or `CONTEXT.md`.
- Recurring behavioral lessons go through `/skill:pi-learn`.
- A durable descriptive fact may be promoted immediately only when the capture gate and one of `knowledge-management.md`'s immediate-promotion triggers pass. Patch the owner and its reachable map atomically, then run `bash .pi/scripts/knowledge-check.sh --root .`.

## Task Documents

For planned work, capture the decomposition under `## Plan of Work` or `### Memory Hints`: the parts and their order, ownership boundaries, verification responsibility, and whether any part is intended for a second instance. When a task is unlikely to need any of that, a single line — "Delegation opportunity: `<short idea>`" — is enough to help a later session.

## Safety And Cost

- Never claim to have spawned an agent. Report what this session did, and what a second instance did if the user ran one.
- Keep a second instance to one extra level. Chains of instances handing work to each other are untraceable.
- Match effort to the request: a small ask does not justify a second terminal.
- The parent session remains responsible for the final result, the validation, and what reaches the user.
