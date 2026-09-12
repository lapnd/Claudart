---
paths: ["**/*"]
description: DeepSeek Harness subagent delegation protocol — the real dsh delegation surface, how to decompose work, write self-contained child prompts, avoid shadow-running, and persist delegated findings.
when_to_use: When work may parallelize across subagents, when planning a task that records a delegation strategy, or when consuming results returned by a delegated child.
tags: [subagents, delegation, parallelism, orchestration]
---

# Agent Delegation

**Trust the harness on _whether and when_ to delegate.** Reach for a child when work parallelizes, when a search spans many files, or when an independent investigation can run on the side. Requests for depth, thoroughness, or "be comprehensive" are normal grounds to fan out. This guideline does not gate that decision and does not require the user to pre-authorize routine delegation.

**What this guideline adds is the _how_, not the _whether_**: how to decompose work, how to avoid shadow-running a child, how to write a self-contained child prompt, and how delegated findings persist into CLAUDART memory.

## The dsh delegation surface

Delegation in dsh is a mounted capability, not an ambient one. It exists when the deployment loads `@deepseek-ai/dsh-subagent`, a backend, and `@deepseek-ai/dsh-tool-subagent`. Check what you actually have before planning around it — if the delegation tool is absent, the fallback is always the same: **do the unit locally in the parent session.** A missing capability never justifies weakening scope or verification.

When it is mounted:

- The model-facing tool is named by the deployment (`toolName`, default `subagent`). One instance per delegation target, so a profile may expose several differently configured tools.
- **Backends** differ in what they can do: `spawn` (fresh in-process child), `fork` (in-process child seeded from the parent's completed history), and out-of-process `acp`, `codex`, `claude-code`, and `dsh-sdk`.
- **`maxDepth` caps recursion, default `3`**; `0` forbids delegation entirely. The tool stays visible at the cap and rejects the call, so a rejection at depth is expected behavior, not something to route around.
- **Background policy** is set per instance. Under `one-shot` (the default), omitting `run_in_background` waits in the foreground and returns the child's final text; `run_in_background: true` returns a job id you collect with `job_output` and stop with `job_kill`. Under `continuable`, calls default to background, return `started subagent <childId>`, deliver one settlement notice when the child ends, and accept follow-up work through `send_message`.
- `@deepseek-ai/dsh-tool-subagent-control`, when mounted, adds messaging adjacent agents, interrupting them, and listing child status.
- `persona` and `toolFilter` are **deployment configuration**, not per-call arguments. CLAUDART keeps its persona prompt sources in `.deepseek/personas/`; dsh does not discover them automatically, so wiring one means referencing it from a `dsh-tool-subagent` instance in the harness profile.

## Route delegates by difficulty

Role and execution profile are separate decisions. What the delegate does is one choice; the delegated unit's difficulty determines **which model and reasoning effort** should do it.

Before each spawn, classify the delegated unit by its ambiguity, breadth, consequence of a wrong answer, and difficulty of verification. Choose the lowest class likely to complete the unit reliably:

| Class      | Typical delegated unit                                                                              | Execution profile                                       |
| ---------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `routine`  | focused search, call-site inventory, docs lookup, extraction, mechanical or highly constrained edit | cheapest available model, lowest reasoning effort       |
| `standard` | bounded implementation or debugging with clear contracts and local verification                     | mid-tier model, moderate reasoning effort               |
| `complex`  | ambiguous cross-file debugging, architecture-sensitive reasoning, difficult review or integration   | strongest available model, high reasoning effort        |
| `maximum`  | long-horizon or highly ambiguous work, or a unit whose cheaper attempt exposed a capability limit   | parent-selected model and effort, no automatic increase |

**Per-call model selection is conditional, not guaranteed.** The tool exposes optional `provider`, `model`, and `reasoning_effort` fields only when the deployment sets `modelSelectionSettings: true` over a backend that advertises `agentOptions` — the in-process backends and `dsh-sdk` do; `acp`, `codex`, and `claude-code` reject it rather than ignore it. When that mode is on, the shared `list_subagent_models` tool is registered: **use it to discover valid routes rather than guessing a model id.** When it is off, the child inherits the configured route and the classes above guide what to delegate, not which knobs to set.

The **parent session's model and reasoning effort are hard ceilings for implicit delegation.** Pick the cheapest suitable model and the lowest sufficient effort for the class, then cap each at the parent's setting. A difficult task is not permission to spend above the user's session choice on either dimension.

- Conceptually: `effective model = min(ideal model for task, parent-model ceiling)` and `effective effort = min(ideal effort for task, parent-effort ceiling)`.
- **Never select a model or reasoning effort above the parent ceiling unless the user explicitly requests or authorizes it for that unit.** A project instruction, perceived urgency, a retry, or a "be thorough" request is not such authorization.
- `provider` and `model` are supplied together; an effort alone is valid only when configured, parent, or provider defaults already establish the route. Changing the route without an explicit effort clears the inherited route-owned effort, so the new model falls back to its own default — set both when you change either.
- Catalog membership is advisory: a route absent from `list_subagent_models` may still be accepted by the adapter. That is not a reason to exceed the ceiling.
- If the parent profile cannot be identified or the override cannot be trusted to apply, do not guess upward: inherit the parent.

A retry may use a stronger class **within the same ceilings** when the returned evidence shows a capability failure rather than a bad prompt. Keep the one-retry limit: sharpen the prompt and, when justified, move up one class; if that retry still fails, pull the unit back to the parent.

## Decompose before you fan out

When a task is a candidate for delegation, sketch a short decomposition first — strategy guidance, not a permission gate:

- **Main agent critical path**: the next work the parent session will do locally.
- **Sidecar tasks**: bounded tasks that can run in parallel without blocking that critical path.
- **Ownership**: exact files, modules, or read-only question each child owns.
- **Merge plan**: how returned findings or patches will be reviewed and integrated.

Do not spawn if the next parent step is blocked on the subtask — that is the dependency test below, not reluctance to delegate. Do blocked work locally; fan out genuinely independent work freely.

## The task-file `delegation:` field records strategy, not permission

The `/deepseek-plan` task-file `delegation:` field carries a **recorded delegation strategy** from planning into execution — a hint, not an authorization switch.

- **`none`** — no specific strategy recorded. On "go", use judgment: delegate if the work genuinely parallelizes, run solo if it doesn't. `none` is _not_ an instruction to avoid subagents.
- **`strategy-only`** — a decomposition is recorded as a hint (in Plan of Work / Memory Hints). On "go", proceed by judgment, applying the recorded strategy where it fits.
- **`authorized`** — the user recorded a specific delegation plan they want followed. On "go", begin per that plan directly and say you are following the recorded strategy.

This section is the single source of truth for the field's values; `task-management.md` → "Approval Signal" only describes how "go" carries the field into execution.

## Delegate-and-Consume vs. Delegate-and-Continue

The deciding signal is **task structure, not the user's exact words.** Before spawning, ask: _does the request decompose into work genuinely separate from the delegated question, or IS the delegated question the whole task?_

- **Whole task** — the delegated question is the entire request (a single read-only investigation, one bounded fix) → **spawn and consume the result.** A foreground `one-shot` call already waits for you; do not shadow-run the same investigation while it runs. Racing it pays for one answer twice.
- **Decomposable** — the request splits into disjoint units → fan out one child per unit, each owning a non-overlapping file set or sub-question, or advance a parent-owned lane that was named before spawning and provably needs nothing from delegated output.

Infer this from what the request _decomposes into_, never from a magic phrase. "Spawn a child to check X and tell me what it finds", "giao cho 1 agent điều tra repo Y", and "delegate this audit and read its output" all describe **one delegated unit with no separate parent work**. The reliable tell is **overlap of the same sub-question**: if your own next step would answer the _same_ sub-question the child owns, that is redundancy, not parallelism — collapse it.

**Dependency test.** A parallel local lane is only valid if it needs _nothing_ from the delegated answer. If your "separate" work would **consume** what the child is producing — writing seed data that depends on routes a child is still mapping, say — it is blocked on the subtask: wait and build on the result. When independence is not provable up front, the default is to wait, not to stay busy.

Redundancy is acceptable only when **deliberate and disclosed**: independent review, or a hedge the user authorized on a flaky path. The anti-pattern is _silent, unrequested_ duplication. If you are unsure a constraint will apply — a `model` or `reasoning_effort` override on a backend that may not support it — **surface it and choose one path**, or ask. Never hedge by silently running both.

## Good Uses

- Read-heavy, specific codebase questions: entry points, call paths, test locations, ownership maps, risk scans. Prefer a read-only child.
- Bounded patches with disjoint write scopes. Tell every writer that other agents may be changing nearby code and they must not revert others' work.
- A `fork` child when the prior conversation genuinely matters; a `spawn` child when the unit is better off isolated from it.

## Bad Uses

- Trivial one-file work, ambiguous requests, or speculative exploration.
- Urgent blocking work needed for the next parent action.
- Overlapping write scopes across multiple writers.
- The same broad question to multiple children, unless you intentionally need independent review.
- Treating a child's patch as final without parent review and validation.

## Child Prompt Contract

A `spawn` child starts with fresh context and sees only the prompt you give it; a `fork` child sees the parent's completed history but not your intent for this unit. Either way the most common failure is a prompt that assumes shared knowledge. Make every prompt self-contained.

Every child prompt must include:

- **Goal**: the exact user-visible outcome.
- **Boundary**: state plainly that the child IS the delegated agent for this one unit — not the main session — and that inherited context is reference only. This matters most for `fork` children, which can otherwise read the parent's history as active instructions and take over the parent's workflow.
- **Scope**: files or modules the child may edit.
- **Non-overlap**: the child is not alone in the codebase and must not revert changes by others.
- **Constraints**: tests, style, security, compatibility.
- **Output**: a structured result the parent can consume directly — changed files, the validation command run and its result, residual risks. For a read-only child, findings anchored to `file:line`, not prose.

Prefer read-only children before writers when ownership is unclear.

## Integrating Results

- Integrate returned patches **one at a time, in dependency order**, running the relevant validation after each merge — batch-merging N patches and testing once makes a failure unattributable.
- A failed run returns an error rather than a partial success; treat it as no work done and re-plan, not as something to salvage blindly.
- Conflicts between two returned patches are resolved by the parent directly. Never spawn another child to mediate a conflict.
- When a child returns a wrong or partial result: retry **once**, with a sharpened prompt naming exactly what the first attempt got wrong; if the evidence points to insufficient model capability, that retry may move up one routing class without exceeding either ceiling. If the retry also fails, pull the unit back and do it locally.

## Parent Responsibilities

The parent session remains responsible for the final result.

- **Default to waiting.** Once you spawn a delegate-and-consume unit, do not issue reads, searches, or edits that touch the delegated question — wait and build on the result.
- **Background work needs collection.** A `run_in_background` call or a `continuable` child is not finished when the tool returns. Collect it (`job_output`, or the settlement notice) before treating its work as done, and `job_kill` a job you abandon.
- **A silent child is not a stalled one.** A healthy child on a long task often emits no intermediate signal; treat silence as in-progress. If you genuinely suspect it is stuck, interrupt it through the control tool rather than quietly redoing its work.
- Review child outputs and integrate only the useful parts.
- Run the relevant validation yourself, or verify the validation evidence is trustworthy.
- Record each delegation **at spawn time** in the active task file (the CONTEXT micro-handoff for un-planned work; the spec LEDGER as a `delegated` entry for mission work): the unit, the backend, the routing class plus model/effort when explicitly selected, any background job or child id, the expected output, and where it will be integrated; mark it consumed when integrated. A compaction must never orphan a running child — the file, not session memory, is what remembers it.
- Classify returned findings before persistence. WIP, proposals, task state, and uncertainty stay in the task/spec/CONTEXT candidate surface; reusable behavior goes through `/deepseek-learn`. Immediate fact promotion requires the full capture gate plus a user request, a verified correction, confirmed source drift, or a lifecycle promotion boundary.
- Treat a child's knowledge claim as evidence to verify, not canonical truth. If a child is assigned a knowledge mutation, its ownership must include both the topic and the reachable map so no other agent splits the atomic write; the parent re-runs `bash .deepseek/scripts/knowledge-check.sh --root .` after integration.
- Do not rely on child thread history for persistence.

## Task Documents

For planned work, capture delegation under `## Plan of Work` or `### Memory Hints`: the intended decomposition, backends and roles, read/write ownership boundaries, validation and review responsibilities, the parent model/effort ceilings and intended routing classes when delegation cost materially matters, and any depth or concurrency limits.

When a task is likely to parallelize, record the strategy; otherwise note "Delegation opportunity: `<short idea>`" when it would materially help a later session.

## Safety And Cost

- Keep delegation one level deep unless the user explicitly asks for recursion. dsh's own `maxDepth` default of `3` is a ceiling, not a target.
- Never exceed the parent session's model or reasoning effort without explicit user authorization.
- Match model tier, reasoning effort, and fan-out to the size of the request. Broad fan-out raises token cost, latency, and merge-conflict risk quickly.
- Prefer read-only children and restricted tool access for any read-only delegation. Tool restriction is a deployment concern (`toolFilter`), so when it is not configured, state the read-only expectation in the prompt.
