---
paths: ["**/*"]
description: DeepSeek subagent delegation protocol — how to decompose work, write self-contained worker prompts, avoid shadow-running delegates, and integrate results.
when_to_use: When work may parallelize across subagents, when planning a task that records a delegation strategy, or when consuming results returned by delegated agents.
tags: [subagents, delegation, parallelism, orchestration]
---

# Agent Delegation

**Trust the harness on _whether and when_ to delegate.** Reach for a subagent when work parallelizes, when a search spans many files, or when an independent investigation can run on the side. Requests for depth, thoroughness, or "be comprehensive" are normal grounds to fan out. This guideline does not gate that decision and does not require the user to pre-authorize routine delegation.

**What this guideline adds is the _how_, not the _whether_**: how to decompose work, how to avoid shadow-running a delegate, how to write a self-contained worker prompt, and how delegated findings persist into CLAUDART memory.

## Harness capability is not assumed

DeepSeek terminal harnesses differ in what they support, and subagent support is newer and less uniform than the rest of this layer. **Verify before relying on a mechanic**, and prefer explicit instruction over implicit behavior:

- Confirm what your harness actually offers — subagent spawning, parallel fan-out, per-delegate model or reasoning-effort selection, thread steering — from its own documentation or `--help`, not from this file.
- If a mechanic is unavailable, the fallback is always the same: **do the unit locally in the parent session.** A missing delegation feature never justifies weakening scope, verification, or the ceilings below.
- If an expected fan-out does not materialize, name the delegation explicitly ("spawn one read-only explorer per module, wait for all of them, then summarize") instead of assuming the harness acted on this file.

Project-specific custom agents under `.deepseek/agents/` carry their own instructions and are invoked directly by name; they are out of scope here.

## Route delegates by difficulty

Role and execution profile are separate decisions. What the delegate does (read-only exploration, bounded implementation, general-purpose work) is one choice; the delegated unit's difficulty determines **which model and reasoning effort** should do it. Named project specialists under `.deepseek/agents/` keep their own model policy and must not be silently down-routed by this guideline.

Before each ordinary spawn, classify the delegated unit by its ambiguity, breadth, consequence of a wrong answer, and difficulty of verification. Choose the lowest class likely to complete the unit reliably:

| Class      | Typical delegated unit                                                                              | Execution profile                                       |
| ---------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `routine`  | focused search, call-site inventory, docs lookup, extraction, mechanical or highly constrained edit | cheapest available model, lowest reasoning effort       |
| `standard` | bounded implementation or debugging with clear contracts and local verification                     | mid-tier model, moderate reasoning effort               |
| `complex`  | ambiguous cross-file debugging, architecture-sensitive reasoning, difficult review or integration   | strongest available model, high reasoning effort        |
| `maximum`  | long-horizon or highly ambiguous work, or a unit whose cheaper attempt exposed a capability limit   | parent-selected model and effort, no automatic increase |

Resolve the concrete model against your harness's current model list rather than a slug written here; available DeepSeek models change, and account or workspace allowlists still apply.

The **parent session's selected model and reasoning effort are hard ceilings for implicit delegation.** Treat them as two independent dimensions: pick the cheapest suitable model and the lowest sufficient reasoning effort for the class, then cap each at the parent's setting. A difficult task is not permission to spend above the user's session choice on either dimension.

- Conceptually: `effective model = min(ideal model for task, parent-model ceiling)` and `effective effort = min(ideal effort for task, parent-effort ceiling)`.
- **Never launch a model or reasoning effort above the parent ceiling unless the user explicitly requests or authorizes it for that unit.** A project instruction, perceived urgency, a retry, or a "be thorough" request is not such authorization.
- When your harness resolves model and reasoning effort independently, set **both** explicitly whenever you change either, so a model's default effort cannot silently raise the intended compute budget. If both effective values equal the parent's, omit the overrides and inherit.
- If the ideal effort is unsupported by the chosen child model, take the nearest supported effort that does not exceed the parent ceiling. Never compensate by raising the model.
- If the parent profile cannot be identified, the desired child profile is unavailable, or the override cannot be trusted to apply, do not guess upward: inherit the parent, or pick a known-available pair no more capable than the parent.
- Do not rewrite the project's intentional custom-agent model definitions to implement this policy.

A retry may use a stronger class **within the same ceilings** when the returned evidence shows a capability failure rather than a bad prompt. Keep the one-retry limit: sharpen the prompt and, when justified, move up one class; if that retry still fails, pull the unit back to the parent. Do not climb through multiple paid retries, and never cross either ceiling implicitly.

## Decompose before you fan out

When a task is a candidate for delegation, sketch a short decomposition first — strategy guidance, not a permission gate:

- **Main agent critical path**: the next work the parent DeepSeek session will do locally.
- **Sidecar tasks**: bounded tasks that can run in parallel without blocking that critical path.
- **Ownership**: exact files, modules, or read-only question each subagent owns.
- **Merge plan**: how returned findings or patches will be reviewed and integrated.

Do not spawn if the next parent step is blocked on the subtask — that is the dependency test below, not reluctance to delegate. Do blocked work locally; fan out genuinely independent work freely.

## The task-file `delegation:` field records strategy, not permission

The `$deepseek-plan` task-file `delegation:` field carries a **recorded delegation strategy** from planning into execution — a hint, not an authorization switch. The harness still decides whether to delegate at run time; the field pre-loads a plan so a good decomposition is not re-derived.

- **`none`** — no specific strategy recorded. On "go", use judgment: delegate if the work genuinely parallelizes, run solo if it doesn't. `none` is _not_ an instruction to avoid subagents.
- **`strategy-only`** — a decomposition is recorded as a hint (in Plan of Work / Memory Hints). On "go", proceed by judgment, applying the recorded strategy where it fits. No mandatory permission round-trip.
- **`authorized`** — the user recorded a specific delegation plan they want followed. On "go", begin per that plan directly and say you are following the recorded strategy.

This section is the single source of truth for the field's values; `task-management.md` → "Approval Signal" only describes how "go" carries the field into execution.

## Delegate-and-Consume vs. Delegate-and-Continue

The deciding signal is **task structure, not the user's exact words.** Before spawning, ask: _does the request decompose into work genuinely separate from the delegated question, or IS the delegated question the whole task?_

- **Whole task** — the delegated question is the entire request (a single read-only investigation, one bounded fix) → **spawn, then wait and consume the result.** Do NOT shadow-run the same investigation in the parent thread. Racing it locally pays for one answer twice and duplicates the subagent's work.
- **Decomposable** — the request splits into disjoint units → either **fan out one subagent per unit** (each owning a non-overlapping file set or sub-question), or advance a parent-owned lane that was named before spawning and provably needs nothing from delegated output.

Infer this from what the request _decomposes into_, never from a magic phrase. "Spawn an explorer to check X and tell me what it finds", "giao cho 1 agent điều tra repo Y", and "delegate this audit and read its output" all describe **one delegated unit with no separate parent work** — the same shape, regardless of wording. The reliable tell is **overlap of the same sub-question**: if your own next step (or another subagent) would answer the _same_ sub-question this subagent owns, that is redundancy, not parallelism — collapse it.

**Dependency test.** A parallel local lane is only valid if it needs _nothing_ from the delegated answer. If your "separate" work would **consume** what the subagent is producing — e.g. writing seed data that depends on the routes an explorer is still mapping — it is blocked on the subtask: wait and build on the result. The trap is self-justifying a disjoint lane that secretly depends on delegated output; that is exactly how a parent drifts into shadow-running. When independence is not provable up front, the default is to wait, not to stay busy.

Redundancy is acceptable only when **deliberate and disclosed**: independent review (intentionally asking N agents the same question to cross-check), or a hedge the user authorized on a flaky path. The anti-pattern is _silent, unrequested_ duplication. If you are unsure a constraint will be honored — a per-agent model or reasoning-effort override, for instance — **surface it and choose one path** (delegate or do it locally), or ask. Never hedge by silently running both.

## Good Uses

- Read-heavy, specific codebase questions: entry points, call paths, test locations, ownership maps, risk scans. Prefer a read-only delegate.
- Bounded patches with disjoint write scopes. Tell every writer that other agents may be changing nearby code and they must not revert others' work.

## Bad Uses

- Trivial one-file work, ambiguous requests, or speculative exploration.
- Urgent blocking work needed for the next parent action.
- Overlapping write scopes across multiple writers.
- The same broad question to multiple agents, unless you intentionally need independent review.
- Treating a subagent patch as final without parent review and validation.

## Worker Prompt Contract

A subagent does not inherit the parent session's conversation. It starts with fresh context and sees only what the spawn prompt gives it, so the most common failure is a prompt that assumes shared knowledge. Make every prompt self-contained — carry the file paths, the exact question, and the constraints into the prompt itself.

Every worker prompt must include:

- **Goal**: the exact user-visible outcome.
- **Boundary**: state plainly that the worker IS the delegated agent for this one unit — not the main session — and that any inherited context is reference only. A delegate that misreads inherited context as an active instruction drifts into the parent's role; explicit boundary text prevents it.
- **Scope**: files or modules the worker may edit.
- **Non-overlap**: the worker is not alone in the codebase and must not revert changes by others.
- **Constraints**: tests, style, security, and compatibility requirements.
- **Output**: a structured result the parent can consume directly, not a chat reply — changed files, the validation command run and its result, residual risks. For a read-only explorer, concrete findings anchored to `file:line`, not prose.

Prefer read-only explorers before writers when ownership is unclear.

## Integrating Results

- Integrate returned patches **one at a time, in dependency order**, running the relevant validation after each merge — batch-merging N patches and testing once makes a failure unattributable.
- Conflicts between two returned patches are resolved by the parent directly. Never spawn another agent to mediate a conflict.
- When a worker returns a wrong or partial result: retry **once**, with a sharpened prompt naming exactly what the first attempt got wrong; if the evidence points to insufficient model capability, that retry may move up one routing class without exceeding either ceiling. If the retry also fails, pull the unit back and do it locally. Never respawn the identical prompt hoping for a different outcome.

## Parent Responsibilities

The parent DeepSeek session remains responsible for the final result.

- **Default to waiting.** Once you spawn a delegate-and-consume unit, do not issue further reads, searches, or edits that touch the delegated question — wait for the result and build on it. Re-running the same investigation locally is the single most common failure. "Stay busy after spawning" is not a goal; non-redundant progress is.
- **Parallel local work is the exception**, and only for a lane named _before_ spawning that provably needs nothing from delegated output.
- **A silent subagent is not a stalled one.** A healthy delegate on a long task often emits no intermediate signal; treat silence as in-progress, not failure. If you genuinely suspect it is stuck, steer or stop it through the harness's own controls — never quietly redo its work.
- Review subagent outputs and integrate only the useful parts.
- Run the relevant validation yourself, or verify the validation evidence is trustworthy.
- Record each delegation **at spawn time** in the active task file (the CONTEXT micro-handoff for un-planned work; the spec LEDGER as a `delegated` entry for mission work): the unit, the agent, the routing class plus model/effort when explicitly selected, the expected output, and where it will be integrated; mark it consumed when integrated. A compaction or handoff must never orphan a running subagent — the file, not session memory, is what remembers outstanding delegations.
- Classify returned findings before persistence. WIP, proposals, task state, and uncertainty stay in the task/spec/CONTEXT candidate surface; reusable behavior goes through `$deepseek-learn`. Immediate fact promotion requires the full capture gate plus a user request, a verified correction needed to avoid continued reliance on known-wrong canonical knowledge, confirmed source drift, or a lifecycle promotion boundary. Otherwise persist the finding as a candidate. For a promotion, read `knowledge-management.md`, patch the existing owner plus reachable route atomically, and run the checker.
- Treat a subagent's knowledge claim as evidence to verify, not canonical truth. If a worker is explicitly assigned a knowledge mutation, its ownership must include both the topic and the reachable map so no other agent splits the atomic write; the parent re-runs `bash .deepseek/scripts/knowledge-check.sh --root .` after integration.
- Do not rely on subagent thread history for persistence.

## Task Documents

For planned work, capture delegation under `## Plan of Work` or `### Memory Hints` rather than a separate schema section. Include:

- the intended decomposition;
- intended subagent roles;
- read/write ownership boundaries;
- validation and review responsibilities;
- the parent model/effort ceilings and intended routing classes when delegation cost materially matters;
- any concurrency or other cost limits.

When a task is likely to parallelize, record the strategy; otherwise note "Delegation opportunity: <short idea>" when it would materially help a later session.

## Safety And Cost

- Keep delegation one level deep unless the user explicitly asks for recursive delegation.
- Never exceed the parent session's model or reasoning effort through ordinary delegation without explicit user authorization.
- Keep concurrency conservative. High multi-agent fan-out increases token usage, latency, and local resource consumption quickly; if your harness exposes a concurrency cap, set it deliberately rather than leaving it unbounded.
- Match model tier, reasoning effort, and fan-out to the size of the request so a trivial ask does not spin up expensive parallel work — judgment, not a brake on genuinely parallel work.
- Use read-only delegates and read-only sandboxing for any read-only delegation whenever possible.
