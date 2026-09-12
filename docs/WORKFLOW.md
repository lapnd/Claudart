# CLAUDART Workflow Guide

[Tiếng Việt](WORKFLOW_VI.md) · [README](../README.md)

This guide explains how to use CLAUDART after it has been installed. It focuses on the operator workflow: how a session starts, where information belongs, when to create a task or specification, and how work is reviewed and resumed.

The exact machine-facing contracts remain in the runtime files themselves:

- Claude Code: `.claude/commands/` and `.claude/rules/`
- Codex CLI: `.agents/skills/` and `.codex/guidelines/`
- DeepSeek Harness (dsh): `.agents/skills/` and `.deepseek/guidelines/`
- Pi: `.agents/skills/` and `.pi/guidelines/`

Those files are authoritative when a command schema or lifecycle detail changes.

## 1. Choose a runtime layer

CLAUDART provides four independent layers.

| Runtime        | Installed files                 | Command form                                   | Layer instructions      |
| -------------- | ------------------------------- | ---------------------------------------------- | ----------------------- |
| Claude Code    | `.claude/`                      | `/start`, `/plan`, and so on                   | `.claude/CLAUDE.md`     |
| Codex CLI      | `.codex/`, `.agents/skills/`    | `$codex-start`, `$codex-plan`, and so on       | `.codex/AGENTS.md`      |
| DeepSeek (dsh) | `.deepseek/`, `.agents/skills/` | `/deepseek-start`, `/deepseek-plan`, and so on | `.deepseek/DEEPSEEK.md` |
| Pi             | `.pi/`, `.agents/skills/`       | `/skill:pi-start`, `/skill:pi-plan`, and so on | `.pi/PI.md`             |

Install one layer or several. The workflows have the same intent, but their command and delegation files are written for the mechanics of each tool.

All four layers include the same dependency-free Bash knowledge checker. No database or background process is required.

### Two shared paths, and how CLAUDART keeps them safe

Codex, `dsh`, and Pi converge on the same two conventions, so CLAUDART treats both as shared rather than letting any layer claim them:

- **Root `AGENTS.md` is a router.** All three harnesses auto-load it. Instead of one layer owning the filename, the installer writes a marker block holding one route line per installed layer, each pointing at that layer's own instructions file. Content outside the markers — including a project's own `AGENTS.md` written before CLAUDART arrived — is never read, moved, or rewritten. Claude Code does not read this file; its layer loads through `.claude/CLAUDE.md`.
- **`.agents/skills/` is shared.** The installer copies only the skills for the layer you asked for, so a single-layer install contains nothing else. With several layers installed, each harness sees every prefix (`codex-*`, `deepseek-*`, `pi-*`); the prefixes and the layer named in each skill description are what keep them apart. Invoke the prefix matching your layer.

### Specialist agents and delegation differ by layer

The Claude and Codex layers ship three specialist agents their harnesses load directly.

**DeepSeek** has real subagents — `@deepseek-ai/dsh-tool-subagent` over a `spawn`, `fork`, `acp`, `codex`, `claude-code`, or `dsh-sdk` backend, with `maxDepth` defaulting to 3 — but no on-disk agent discovery. `.deepseek/guidelines/agent-delegation.md` documents that surface, and the three specialist prompts live in `.deepseek/personas/` as sources for a `persona` you wire up in the harness profile.

**Pi** ships none, on purpose. Pi's README states it "skips features like sub agents and plan mode" and points at spawning separate pi instances via tmux, extensions, or a package. `.pi/guidelines/agent-delegation.md` says so plainly and routes that work two ways: do the unit inline, or hand a written brief to a second Pi instance. Pi's answer to plan mode — "write plans to files" — is what CLAUDART's task and spec layers already provide.

## 2. Install or integrate

### New project

```bash
# Claude Code, the default
curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash

# Codex CLI
curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash -s -- --codex

# DeepSeek Harness (dsh)
curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash -s -- --deepseek

# Pi
curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash -s -- --pi

# Claude Code and Codex
curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash -s -- --both

# All four runtimes
curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash -s -- --all
```

The installer copies files that are missing and skips existing files unless `--force` is supplied. It is suitable for a clean installation, not for merging a customized setup.

Each harness layer also adds its route line to the root `AGENTS.md` router, creating that file when it does not exist. The layer's own instructions stay inside its directory.

### Existing project or upgrade

Use [INTEGRATE.md](../INTEGRATE.md). The integration protocol asks an agent to:

1. compare the current project with the current upstream repository;
2. identify unchanged files, stale CLAUDART templates, and project-authored customizations;
3. present a concrete add, replace, merge, move, or retire plan;
4. wait for approval before writing;
5. preserve live state, task files, specification folders, and project knowledge;
6. run the current reconciliation checks after the approved changes.

A useful prompt is:

> Read https://raw.githubusercontent.com/vankhaivn/Claudart/main/INTEGRATE.md and follow it to integrate or update CLAUDART in this project. Preserve project-specific content and show me the proposed changes before writing them.

### Initial reconciliation

Run this sequence once after installation or upgrade:

```text
Claude:   /doctor → /refactor-memory → /doctor
Codex:    $codex-doctor → $codex-refactor-memory → $codex-doctor
DeepSeek: /deepseek-doctor → /deepseek-refactor-memory → /deepseek-doctor
Pi:       /skill:pi-doctor → /skill:pi-refactor-memory → /skill:pi-doctor
```

`doctor` checks structure and semantic consistency. `refactor-memory` normalizes the memory layout in place. A second `doctor` confirms that the resulting state is healthy.

## 3. A normal session

A typical session follows this shape:

```text
start
  ↓
choose direct work, a task plan, or a specification
  ↓
implement and verify
  ↓
handoff only if the investigation must continue in a fresh session
  ↓
checkpoint at a meaningful stopping point
  ↓
user review and closure
```

### Start with orientation

Run `/start`, `$codex-start`, `/deepseek-start`, or `/skill:pi-start`.

The start command reads:

- current state from `CONTEXT.md`;
- the task and specification indexes;
- the root knowledge index, not every knowledge topic;
- a small amount of recent Git history;
- an outstanding `HANDOFF.md`, when one exists.

It does not run the knowledge checker. Start is intended to be lightweight.

### Choose the right work mode

| Mode          | Use it for                                                                  | Persistence                                |
| ------------- | --------------------------------------------------------------------------- | ------------------------------------------ |
| Direct work   | Small, clear, low-risk changes that do not need a durable plan              | Conversation and normal repository history |
| Task plan     | Multi-step, multi-file, interruptible, or review-gated implementation       | One file in `tasks/`                       |
| Specification | Work with several phases, acceptance scenarios, artifacts, or many sessions | One folder in `specs/`                     |

A specification replaces task plans within its approved scope. Do not create task files for work already owned by an active specification.

### End or pause cleanly

Use `/checkpoint`, `$codex-checkpoint`, `/deepseek-checkpoint`, or `/skill:pi-checkpoint` at a meaningful stopping point. Checkpoint rebuilds current state, synchronizes indexes, records retired history, and distills eligible durable facts.

Use `/handoff`, `$codex-handoff`, `/deepseek-handoff`, or `/skill:pi-handoff` only when a difficult investigation must continue in a fresh session. Handoff records the current hypothesis, evidence, failed approaches, constraints, and exact next step. It is not a general session summary.

## 4. Memory and knowledge

CLAUDART separates information by purpose and lifetime.

| Store                     | Contains                                              | Does not contain                                  |
| ------------------------- | ----------------------------------------------------- | ------------------------------------------------- |
| `CONTEXT.md`              | Current facts needed to resume work now               | Long history or stable reference material         |
| `JOURNAL.md`              | Compact history of retired state                      | Instructions that should load every session       |
| `rules/` or `guidelines/` | Prescriptive behavior: how the agent should work      | Descriptive project facts                         |
| `knowledge/`              | Durable, evidenced facts about the project            | Temporary plans, proposals, or unverified guesses |
| `tasks/`                  | State and decisions for one implementation task       | General project documentation                     |
| `specs/`                  | Approved intent and execution evidence for large work | Unrelated tasks                                   |
| `HANDOFF.md`              | Reasoning needed by the next session                  | Permanent history                                 |

### Current state

`CONTEXT.md` is declarative: it describes what is true now. Checkpoint rewrites it rather than appending forever. The shipped rules keep it at no more than 150 lines.

`JOURNAL.md` is append-only and is not loaded automatically. It exists for audits and historical lookup without consuming normal session context.

### Durable knowledge

The knowledge store is descriptive. Typical topics include architecture, terminology, domain rules, external system contracts, and pointers to canonical documents.

A claim belongs in knowledge when it is:

1. supported by repository or user-provided evidence;
2. true now;
3. likely to remain useful after the current task ends;
4. placed under the topic that already owns that fact, when one exists.

Work in progress, proposed designs, and task-specific discoveries remain in the task, specification, or `CONTEXT.md` until they become durable.

A useful capture test is:

> Would this still be true and useful if the current task were cancelled tomorrow?

### Retrieval

Knowledge retrieval is map-first and bounded:

1. read the root `INDEX.md`;
2. follow only the relevant domain map or topics;
3. inspect topic metadata and headings;
4. read the smallest section that answers the question;
5. use bounded repository or Git search only when routed knowledge is insufficient.

Reading knowledge never changes it.

### Topic contract and lifecycle

Knowledge topics use constrained YAML-compatible front matter. The required fields are:

```yaml
---
name: example-topic
description: "What this topic owns."
type: domain
status: active
updated: YYYY-MM-DD
last_verified: YYYY-MM-DD
sources:
  - "../../docs/example.md"
---
```

The supported lifecycle states are:

- `active`: current, verified authority;
- `review-needed`: visible uncertainty or conflict that must be checked before use as authority;
- `superseded`: replaced by another topic;
- `retired`: intentionally historical.

The exact field grammar, routing limits, map thresholds, and mutation rules live in the runtime's `knowledge-management` rule or guideline.

### Validation

The shipped checker validates structure, routes, references, lifecycle fields, freshness anchors, and size or sensitivity budgets. It does not decide whether a statement is true.

Run it directly only when maintaining the knowledge store:

```bash
bash .claude/scripts/knowledge-check.sh --root .
bash .codex/scripts/knowledge-check.sh --root .
bash .deepseek/scripts/knowledge-check.sh --root .
bash .pi/scripts/knowledge-check.sh --root .
```

The normal `/doctor` and `/refactor-memory` commands call the relevant checker as part of their own workflows.

## 5. Persistent task workflow

Use `/plan <task>`, `$codex-plan <task>`, `/deepseek-plan <task>`, or `/skill:pi-plan <task>` when the work should survive the current conversation.

The command creates a dated task file under `.claude/tasks/`, `.codex/tasks/`, `.deepseek/tasks/`, or `.pi/tasks/`. A useful task file records:

- the user's request and observable purpose;
- relevant code, documents, and knowledge pointers;
- an ordered plan and one verification checkpoint per step;
- acceptance criteria;
- important decisions and rejected alternatives;
- discoveries that changed the plan;
- the final outcome and retrospective.

The task file should be sufficient for a later session to continue without relying on the original chat.

### State machine

```text
planning ── user approves ──▶ in-progress
in-progress ── agent finishes ──▶ awaiting-review
awaiting-review ── user confirms ──▶ done
awaiting-review ── user reports a problem ──▶ in-progress
in-progress ── blocked ──▶ blocked
blocked ── blocker cleared ──▶ in-progress
any state ── user cancels ──▶ cancelled
```

`planning` and `awaiting-review` are write locks for source code:

- In `planning`, the agent may refine the task file but does not implement yet.
- In `awaiting-review`, the agent has finished its checks and waits for the user's review.
- A reported problem reopens the task and returns it to `in-progress`.

### Approval and completion

Approval is expressed in ordinary language. Clear phrases such as “go,” “implement,” or “approved” can start an approved plan. Clear completion phrases such as “looks good,” “confirmed,” or “close it” allow the task to be archived.

Praise, questions, or manual edits to the task file are not treated as approval.

Completion has two distinct steps:

1. **Agent completion:** implementation and validation finish; status becomes `awaiting-review`.
2. **User confirmation:** the user reviews the result; the task moves to `done`, its file is archived, and the journal receives a compact record.

### Resuming later

A new session should read the whole task file, verify that completed steps still hold against the current repository, record any drift, and continue from the next valid unchecked step.

A task file is a resumable plan, not proof that the repository has remained unchanged.

## 6. Specification workflow

Use `/spec <mission>`, `$codex-spec <mission>`, `/deepseek-spec <mission>`, or `/skill:pi-spec <mission>` when one task file is not enough.

A specification workspace lives under:

```text
.claude/specs/YYYY-MM-DD-<slug>/
.codex/specs/YYYY-MM-DD-<slug>/
.deepseek/specs/YYYY-MM-DD-<slug>/
.pi/specs/YYYY-MM-DD-<slug>/
```

Each workspace contains:

| File         | Purpose                                                                        |
| ------------ | ------------------------------------------------------------------------------ |
| `SPEC.md`    | Approved intent, acceptance scenarios, scope limits, and commit policy         |
| `ROADMAP.md` | Phases, executable work items, and a verification checkpoint for each item     |
| `NOTES.md`   | Curated working knowledge, decisions, constraints, and current acceptance gaps |
| `LEDGER.md`  | Append-only execution and validation evidence                                  |
| `artifacts/` | Approved proof-of-concept or reference artifacts                               |

### Planning and approval

The specification command interviews the user, records decisions in the workspace, and may create proof-of-concept artifacts. It then prepares a roadmap that another session can execute without access to the original interview.

The user approves `SPEC.md` and `ROADMAP.md` once. That approval applies to the work inside the approved scope. It does not authorize unrelated refactoring or a change in product intent.

The approved specification also records the commit policy. The default is no automatic commits; pushing is never implied.

### Execution

Run `/spec-run <slug>`, `$codex-spec-run <slug>`, `/deepseek-spec-run <slug>`, or `/skill:pi-spec-run <slug>` in a fresh session when practical.

Each iteration:

1. re-orients from the specification files;
2. selects the first runnable pending item;
3. implements and verifies it on an appropriate real surface;
4. updates the roadmap disposition;
5. appends evidence to the ledger;
6. records blockers with a concrete condition for resuming.

A failed check is retried only when the hypothesis, implementation, or verifier has materially changed. Repeating the same failed attempt is not progress.

At phase boundaries, rotate to a fresh session when useful. The specification workspace is the handoff; spec execution does not use `HANDOFF.md`.

### Final review

When all work is complete or explicitly superseded and no blocker remains, the executor runs a fresh acceptance gate. Every acceptance scenario must have current evidence before the specification moves to `awaiting-final-review`.

The user, not the agent, marks the specification done.

If review feedback changes only a bounded implementation detail, rerun the affected acceptance scenarios and any shared dependencies. If the impact cannot be defended, rerun the full gate. Feedback that changes intent or violates the approved scope requires a specification amendment and renewed approval.

## 7. Delegation and specialized agents

Delegation is optional. The active tool and repository instructions decide whether it is useful.

When work is delegated:

- split the request into non-overlapping units first;
- give each worker an explicit question or file scope;
- keep explorers read-only;
- give parallel writers disjoint ownership;
- avoid doing the same investigation locally and in a worker unless independent cross-checking is intentional;
- integrate returned work in dependency order and validate each result;
- keep the parent agent responsible for the final outcome.

The project includes three explicit-request-only specialist agents:

| Agent               | Behavior                                                                                                                             |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Clean-code reviewer | May make a scoped, behavior-preserving improvement and run relevant checks. Review-only mode is available when explicitly requested. |
| Security auditor    | Reads code, performs an evidence-based audit, and writes a dated report.                                                             |
| UI visual critic    | Reviews rendered visual output and reports actionable design findings.                                                               |

None of these agents runs automatically, including during task or specification execution.

The shipped Codex configuration limits concurrent subagent threads to six per session. Delegation remains one level deep unless the user explicitly requests recursion.

## 8. Command reference

| Claude Code          | Codex CLI                  | DeepSeek (dsh)                | Pi                            | Purpose                                                                                 |
| -------------------- | -------------------------- | ----------------------------- | ----------------------------- | --------------------------------------------------------------------------------------- |
| `/start`             | `$codex-start`             | `/deepseek-start`             | `/skill:pi-start`             | Orient a session from current state, indexes, knowledge routing, and recent Git history |
| `/plan <task>`       | `$codex-plan <task>`       | `/deepseek-plan <task>`       | `/skill:pi-plan <task>`       | Create a persistent implementation task                                                 |
| `/spec <mission>`    | `$codex-spec <mission>`    | `/deepseek-spec <mission>`    | `/skill:pi-spec <mission>`    | Create and approve a multi-phase specification                                          |
| `/spec-run <slug>`   | `$codex-spec-run <slug>`   | `/deepseek-spec-run <slug>`   | `/skill:pi-spec-run <slug>`   | Execute an approved specification to final review                                       |
| `/project-discovery` | `$codex-project-discovery` | `/deepseek-project-discovery` | `/skill:pi-project-discovery` | Turn a rough project idea into structured project documents                             |
| `/checkpoint`        | `$codex-checkpoint`        | `/deepseek-checkpoint`        | `/skill:pi-checkpoint`        | Rebuild current state, synchronize indexes, and distill durable information             |
| `/handoff`           | `$codex-handoff`           | `/deepseek-handoff`           | `/skill:pi-handoff`           | Preserve an unfinished investigation for the next session                               |
| `/learn`             | `$codex-learn`             | `/deepseek-learn`             | `/skill:pi-learn`             | Promote recurring behavior into rules or guidelines                                     |
| `/doctor`            | `$codex-doctor`            | `/deepseek-doctor`            | `/skill:pi-doctor`            | Run structural and semantic health checks                                               |
| `/refactor-memory`   | `$codex-refactor-memory`   | `/deepseek-refactor-memory`   | `/skill:pi-refactor-memory`   | Normalize and reorganize the memory structure in place                                  |

## 9. Installed layout

A Claude installation centers on:

```text
.claude/
├── CLAUDE.md
├── CONTEXT.md
├── JOURNAL.md
├── commands/
├── agents/
├── rules/
├── knowledge/
│   └── INDEX.md
├── scripts/
├── tasks/
│   ├── index.md
│   └── done/
└── specs/
    └── INDEX.md
```

`HANDOFF.md` appears only between a handoff and the next start. Task files, specification workspaces, knowledge topics, and maps are created as the project evolves.

A Codex installation centers on:

```text
AGENTS.md
.agents/
└── skills/
.codex/
├── CONTEXT.md
├── JOURNAL.md
├── config.toml
├── agents/
├── guidelines/
├── knowledge/
│   └── INDEX.md
├── scripts/
├── tasks/
│   ├── index.md
│   └── done/
└── specs/
    └── INDEX.md
```

`.codex/AGENTS.md` is the Codex layer's own instructions file, pointed at from the root `AGENTS.md` router. It is distinct from this repository's root `AGENTS.md`, which is maintainer guidance.

A DeepSeek installation centers on:

```text
DEEPSEEK.md
.agents/
└── skills/
.deepseek/
├── CONTEXT.md
├── JOURNAL.md
├── personas/
├── guidelines/
├── knowledge/
│   └── INDEX.md
├── scripts/
├── tasks/
│   ├── index.md
│   └── done/
└── specs/
    └── INDEX.md
```

`.deepseek/personas/` holds the three specialist prompts as text. dsh has no on-disk agent or persona discovery — a child's persona and tool access are set through `persona` and `toolFilter` on a `@deepseek-ai/dsh-tool-subagent` instance in the harness profile — so these files are sources you point at, not definitions that load themselves. CLAUDART writes no `.deepseek/config.toml`: dsh's project configuration is `.dsh/settings.yaml`, which belongs to dsh.

A Pi installation centers on:

```text
AGENTS.md
.agents/
└── skills/
.pi/
├── PI.md
├── CONTEXT.md
├── JOURNAL.md
├── guidelines/
├── knowledge/
│   └── INDEX.md
├── scripts/
├── tasks/
│   ├── index.md
│   └── done/
└── specs/
    └── INDEX.md
```

CLAUDART shares `.pi/` with Pi itself and stays out of Pi's own paths: it never writes `.pi/settings.json`, `.pi/skills/`, `.pi/npm/`, or `.pi/agents/`. That last one is also why the Pi layer ships no specialist agents.

## 10. Maintaining CLAUDART itself

Contributors should keep equivalent Claude, Codex, DeepSeek, and Pi behavior in sync where the concept applies to more than one runtime. When a public command, file contract, or workflow changes, update both English and Vietnamese documentation.

Run the repository checks before opening a pull request:

```bash
npm ci
npm run check
```

See [CONTRIBUTING.md](../CONTRIBUTING.md) for contribution rules and [INTEGRATE.md](../INTEGRATE.md) for downstream upgrades.
