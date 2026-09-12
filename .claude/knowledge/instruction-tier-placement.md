---
name: instruction-tier-placement
description: "Where an instruction file belongs across the eager, lazy, and on-demand tiers, and the inversion failure that silently keeps a universal rule out of context."
type: architecture
status: active
updated: 2026-09-12
last_verified: 2026-09-12
aliases:
  - "rule placement"
  - "two-speed rules"
triggers:
  - "where should this rule go"
  - "rule or skill"
  - "when_to_use"
scope:
  - "path:.claude/rules/**"
  - "path:.claude/skills/**"
related:
  - "knowledge:context-cost-model"
verify: "In a scratch repo, ask a session `state this project's constitution priority ladder; if it is not in your context answer NOT IN CONTEXT` with the rule carrying `paths:` and again without it."
sensitivity: public
---

# Instruction Tier Placement

Three tiers exist, and the difference between them is **when the text enters context**, not how important it is. Measured costs are in [[context-cost-model]].

| Tier      | How it is declared                      | When it loads                       |
| --------- | --------------------------------------- | ----------------------------------- |
| Eager     | `.claude/rules/`, **no** `paths:` field | Session start, unconditionally      |
| Lazy      | `.claude/rules/` **with** `paths:`      | First time a matching file is read  |
| On demand | `.claude/skills/<name>/SKILL.md`        | Only when something loads the skill |

## The two-speed pattern

A mature layer splits a subject in two: a short principle file in the eager tier, and the long mechanics file one tier down. A 17-rule downstream layer studied on 2026-09-12 did this deliberately — a four-point delegation principle file beside a full delegation protocol, a six-point verification principle file beside the low-level mechanics of exit status, baselines and gates. The principles are always present; the mechanics arrive when the work actually needs them.

This is the right shape. Prefer it over putting one long file in either tier alone.

## The inversion failure

`paths: ["**/*"]` reads like "applies everywhere" and behaves like "load late". A file whose own `when_to_use` says _every task_ but which carries that glob therefore never reaches context until some file is read — and a session that only answers a question, plans, or inspects git never reads one.

In the layer studied, the two files declaring `when_to_use: Every task` both carried `paths: ["**/*"]`, while three files with no stated trigger at all carried no frontmatter and so loaded first. The tiers were exactly inverted against intent.

The consequence is not theoretical. Asked to state the project's constitution priority ladder or answer `NOT IN CONTEXT`, a session on that layer answered:

> NOT IN CONTEXT — the provided context references priorities … but does not contain the complete, ordered priority ladder itself.

The constitution exists to decide conflicts between principles. It was absent at the moment a conflict would first arise. Removing `paths:` from those two files made the same session recite the ladder correctly.

## How to place a file

Read the file's own `when_to_use` and take it literally.

- _Every task_, or a tie-breaker other rules defer to → **eager**: no `paths:` field. Keep these short; everything here is paid for on every session.
- Applies whenever code of a given shape is touched → **lazy**: `paths:` naming that shape. A narrow glob is better than `**/*`, which only defers to the first file read.
- Names a workflow, a command, a directory, or a domain that most sessions never enter → **on demand**: a skill.

Rebalancing the studied layer along these lines — five principle files eager, three code rules lazy, nine workflow and domain contracts as skills — measured **+217 tokens** on a session that opens no file and **−41,077** on one doing real spec work, a 41% reduction.

## Guard the on-demand tier

A skill loads when something asks for it, so a contract carrying an enforcement gate must be pulled in explicitly rather than hopefully. Every command that depends on a workflow skill states loading it as its first step, and the layer's memory index lists the load triggers. Without that, `task-management`'s read-only locks could be absent from a session that is editing under one.
