---
paths: ["**/*"]
description: Claude Code subagent delegation — project guidance on HOW to delegate well (decomposition, worker prompts, anti-shadow-run, persistence), layered on top of the Agent tool's built-in WHEN-to-delegate mechanics.
when_to_use: When delegating to subagents, or planning a task that may parallelize — for the project's decomposition, worker-prompt, anti-shadow-run, and finding-persistence guidance.
tags: [subagents, delegation, parallelism, orchestration]
---

# Agent Delegation

**Trust the harness on _whether and when_ to delegate.** The Agent tool's built-in mechanics already make that call well — reach for a subagent when work parallelizes, when a search spans many files, when an independent investigation can run on the side — exactly as in a vanilla Claude session. This rule does **not** gate that decision and does **not** require the user to pre-authorize routine delegation. Requests for depth, thoroughness, or "be comprehensive" are normal grounds for the harness to fan out; let it.

**What this rule adds is the _how_, not the _whether_.** Claude's Agent tool already encodes the mechanics — launching parallel agents in one message, `SendMessage` to continue a thread, `run_in_background`, `isolation: worktree`, and _"once you've delegated a search, don't also run it yourself — wait for the result."_ On top of that, this rule supplies the project-specific layer: how to decompose work, how to avoid shadow-running, how to write a self-contained worker prompt, and how delegated findings persist into CLAUDART memory.

This protocol governs general-purpose delegation (`subagent_type: general-purpose`, `Explore`, `Plan`). Project-specific agents under `.claude/agents/` carry their own instructions and are invoked by name; their invocation policy stays out of scope here, but the Independent Review Dispatch contract below applies whenever they run. Their capabilities differ: `security-auditor` is review-only, while `clean-code-reviewer` defaults to Review-Only Mode and enters Implementation Mode only when the invocation explicitly authorizes edits — state which one you are asking for when you invoke it.

## Decompose before you fan out

When a task is a candidate for delegation, sketch a short decomposition first — this is strategy guidance, not a permission gate:

- **Main agent critical path**: the next work the parent session will do locally.
- **Sidecar tasks**: bounded tasks that can run in parallel without blocking that critical path.
- **Ownership**: exact files, modules, or read-only question each subagent owns.
- **Merge plan**: how returned findings or patches will be reviewed and integrated.

Do not spawn if the next parent step is blocked on the subtask — that is the dependency test below, not reluctance to delegate. Do blocked work locally; fan out genuinely independent work freely.

### Disjointness test — deciding what can run in parallel

Before choosing parallel over serial execution for a set of candidate tasks (a ROADMAP wave, a plan's independent Concrete Steps, any ad-hoc fan-out), evaluate them against this test rather than assuming a marking is still accurate. Two tasks are disjoint, and therefore safe to run in parallel, only when **all three** hold:

1. **No file/module overlap** — their stated target files/modules (or, for code, their actual touched paths) do not intersect.
2. **No output dependency** — neither task's action, `verify:`, or description consumes an artifact, value, or state the other produces.
3. **No ordering dependency** — neither is listed (in the roadmap phase order, task file step order, or explicit prerequisite) as a prerequisite of the other.

A candidate set that fails any of the three runs serially, or is split so only the disjoint subset parallelizes. This is the test both `spec-workflow.md` (ROADMAP wave marking and the executor's per-iteration wave selection) and `task-management.md` (independent Concrete Steps) apply — defined once here so the two never drift into different definitions of "independent."

## The task-file `delegation:` field records strategy, not permission

The `/plan` task-file `delegation:` field carries a **recorded delegation strategy** from planning into execution — it is a hint, not an authorization switch. The harness still decides whether to delegate at run time; the field just pre-loads a plan so a good decomposition isn't re-derived.

- **`none`** — no specific strategy recorded. On "go", use harness judgment: delegate if the work genuinely parallelizes, run solo if it doesn't. `none` is _not_ an instruction to avoid subagents.
- **`strategy-only`** — a decomposition is recorded as a hint (in Plan of Work / Memory Hints). On "go", proceed by harness judgment, applying the recorded strategy where it fits. No mandatory permission round-trip.
- **`authorized`** — the user recorded a specific delegation plan they want followed. On "go", begin per that plan directly and say you are following the recorded strategy.

This section is the single source of truth for the field's values; `task-management.md` → "Approval Signal" only describes how "go" carries the field into execution.

## Delegate-and-Consume vs. Delegate-and-Continue

The deciding signal is **task structure, not the user's exact words.** Before spawning, ask: _does the request decompose into work genuinely separate from the delegated question, or IS the delegated question the whole task?_

- **Whole task** — the delegated question is the entire request (a single read-only investigation, one bounded fix) → **spawn, then wait and consume the result.** Do NOT shadow-run the same investigation yourself. The harness already says this for searches; it holds for any single delegated unit. Racing it pays for one answer twice and duplicates the subagent's work.
- **Decomposable** — the request splits into disjoint units → either **fan out one agent per unit in a single message**, or advance a genuinely non-overlapping part yourself while a subagent owns another. Claude lets the parent work in parallel, so both shapes are valid — the constraint is non-overlap, not who does the work.

Infer this from what the request _decomposes into_, never from a magic phrase. "Launch an agent to check X and tell me what it finds", "giao cho 1 agent điều tra repo Y", "delegate this audit and read its output" all describe **one delegated unit with no separate parent work** — the same shape, regardless of wording. The reliable tell is **overlap of the same sub-question**: if your own next step (or another agent) would answer the _same_ sub-question this agent owns, that is redundancy, not parallelism — collapse it.

**Dependency test (sharper than overlap).** Parallel parent work is legitimate on Claude, but a local lane is only valid if it needs _nothing_ from the delegated answer. If your "separate" work would **consume** what the subagent is producing — e.g. writing seed data that depends on the routes an explorer is still mapping — it is blocked on the subtask: wait and build on the result; running it now just re-derives the delegated answer. The trap is self-justifying a disjoint lane that secretly depends on the delegated output — that is exactly how a parent drifts into shadow-running. When the lane's independence isn't provable up front, the default is to wait, not to stay busy.

Redundancy is acceptable only when **deliberate and disclosed**: independent review (intentionally asking N agents the same question to cross-check), or a hedge the user authorized on a flaky path. The anti-pattern is _silent, unrequested_ duplication. In particular, if you are unsure the Agent tool will honor a constraint — e.g. a `model` override — **surface that constraint and choose one path** (delegate or do it locally), or ask. Never hedge by silently running both.

## Worker Prompt Contract

A subagent does not inherit the parent's conversation — it sees only the spawn prompt. The most common failure is a prompt that assumes shared knowledge. Make every prompt self-contained: carry the file paths, the exact question, and the constraints into the prompt itself.

Every worker prompt must include: **Goal** (the exact user-visible outcome), **Scope** (files the worker may edit), **Non-overlap** (other agents may be changing nearby code; do not revert their work), **Constraints** (tests, style, security, compatibility), and **Output** (a structured result the parent can consume directly — changed files, the validation command and its result, residual risks; for a read-only explorer, findings anchored to `file:line`, not prose). Prefer read-only explorers before workers when ownership is unclear.

## Integrating Results

- Integrate returned patches **one at a time, in dependency order**, running the relevant validation after each merge — batch-merging N patches and testing once makes a failure unattributable.
- Conflicts between two returned patches are resolved by the parent directly. Never spawn another agent to mediate a conflict.
- When a worker returns a wrong or partial result: retry **once**, with a sharpened prompt that names exactly what the first attempt got wrong; if the retry also fails, pull the unit back and do it locally. Never respawn the identical prompt hoping for a different outcome.

## Worktree Lifecycle for Parallel Coding Work

When a disjoint-task wave (per the test above) involves real code edits, "Safety And Cost" already requires spawning each writer with `isolation: worktree` so concurrent edits cannot conflict. This section is what happens after they return — a worktree is not done just because the worker said so.

1. **Spawn.** Fan out one `Agent` call per disjoint task in a single message, each with `isolation: "worktree"`. The worker prompt follows the standard Worker Prompt Contract; its **Output** must additionally echo the worktree path and branch it worked in, as a cross-check against what the tool result reports.
2. **Collect, and verify the branch actually holds the work.** Take the worktree path and branch from the tool result. **NEVER equate "the branch has no new commits" with "the worker did nothing"** — a worker that edited files but never committed leaves an unmoved branch and a dirty worktree, and merging it yields an empty merge that looks clean. YOU MUST inspect **both** the branch (commits versus the base) and the worktree's working tree (uncommitted and untracked files) before concluding anything. Uncommitted work in a worktree is work that does not exist; either commit it yourself after reviewing it, or send the worker back. This has already happened: a worker reported a complete, correct implementation and had committed none of it.
   Say so in the worker prompt too — require the worker to commit and to echo its own `git log`/`git status` output as proof, so the failure is caught by the worker rather than by you.
3. **Integrate one at a time, in dependency order** — this is the existing "Integrating Results" rule, applied to worktree branches instead of patches: merge the branch into the base branch, then immediately re-run that task's `verify:`/relevant validation against the **merged base**, not against the worker's self-report. A worker's "done" is a claim to check, per "Parent Responsibilities" — merging without re-verifying is trusting it anyway.
   **A worker's suite numbers are measured in its own worktree, which is not your environment.** A fresh worktree lacks gitignored build output the parent has long since generated, so a worker routinely reports failures that are artefacts of its own tree. Re-run on the merged base under `verification-mechanics.md` §2 rather than adopting or arguing with the worker's list — and NEVER accept a worker's "these failures are unrelated/pre-existing" without running the baseline yourself.
   For any claim you would repeat to the user, **re-derive the riskiest assertions with your own check**, not by re-reading the worker's. A short parent-written script exercising the two or three cases most likely to be wrong is cheap and is the only part of the report you actually know.
4. **Confirm the merge landed** before treating the task as complete: the branch's commits are present in the base branch's history and the working tree is clean (e.g. `git log <base>..HEAD` shows them, `git status` is clean). This confirmation, plus the merge command and its result, becomes part of that task's completion evidence.
5. **Push only if already authorized.** This lifecycle never grants a new push authorization — `git-commits.md` still governs: push happens only when the user asked in the current message, and a spec's `commits:` policy never grants push regardless of its value. If a push was already authorized elsewhere, confirm it landed (e.g. the remote ref matches) as part of the same evidence; if not, the confirmed state is "merged locally, not pushed" and that is a complete, valid stopping point.
6. **Delete the worktree only after merge (and push, if any) is confirmed.** Use `git worktree remove <path>` (and `git branch -d <branch>` once merged) — never `ExitWorktree`, which is scoped to worktrees the _current session_ entered via `EnterWorktree` and is a no-op on a worktree an `Agent` call created through `isolation: "worktree"`.
7. **Never delete a worktree still holding unmerged or unconfirmed work.** A merge conflict or a failed re-verify keeps the worktree and its branch on disk; treat it like any other blocked unit under the owning workflow's existing blocked/circuit-breaker handling (`spec-workflow.md`'s convergence rules for spec work, or a direct report for `/plan` work) rather than inventing new failure handling or discarding the branch.

## Independent Review Dispatch

Independent review works only when the reviewer's context is genuinely fresh — a reviewer fed the author's reasoning inherits its rationalizations. When dispatching any review (a project review agent, or a deliberate N-agent cross-check):

- The prompt carries scope **by reference** — a commit range, exact paths, or a diff command to run — never a hand-paraphrased diff and never the author's justification narrative. The reviewer reads the code, not the story.
- The verdict must record the commit or worktree state it reviewed. **Any later change to the reviewed surface voids the verdict** — re-dispatch on the new state instead of patching and keeping the old approval. The classic failure: "reviewer approved, then I made one tiny fix."
- Adversarial cross-checks stop bounded: after 2 consecutive rounds producing no new confirmed finding, stop and report. "Keep looking until nothing is found" is unbounded and un-resumable.

## Parent Responsibilities

The parent session remains responsible for the final result. Beyond the harness mechanics:

- The subagent's final message returns to you as the tool result and is NOT shown to the user — relay what matters.
- Review subagent outputs and integrate only the useful parts; do not treat a subagent patch as final without parent review and validation.
- Run the relevant validation yourself, or verify the validation evidence is trustworthy.
- Record each delegation **at spawn time** in the active task file (the CONTEXT micro-handoff for un-planned work; the spec LEDGER as a `delegated` entry for mission work): the unit, the agent, the expected output, and where it will be integrated; mark it consumed when integrated. A compaction or handoff must never orphan a running subagent — the file, not session memory, is what remembers outstanding delegations.
- Persist task/spec state, WIP, proposals, and uncertain subagent findings in the owning task/spec/CONTEXT surface; do not rely on subagent thread history.
- Route a verified descriptive finding through `.claude/rules/knowledge-management.md` when it is durable beyond the current work. Mid-session promotion requires both the capture gates and one of that rule's immediate-promotion triggers; patch owner + reachable map atomically and run the checker. `/checkpoint` bulk-maintains remaining candidates, while recurring behavior goes to `/learn`.

## Task Documents

For planned work, capture delegation under `## Plan of Work` or `### Memory Hints`, not a separate schema section. Include: the intended decomposition; intended roles; read/write ownership boundaries; validation and review responsibilities; any concurrency or cost limits. When a task is likely to parallelize, record the strategy; otherwise note "Delegation opportunity: <short idea>" when it would materially help a later session.

## Model & Effort Routing

Route each spawn to the cheapest tier that reliably clears it — never default to the strongest. Tiers are abstract; the current harness mapping lives only in this table, so a model launch updates one place:

| Tier     | Claude spawn                             | Route here                                                                                                               |
| -------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| fast     | `model: haiku` (or inherit + low effort) | Read-only sweeps, mechanical edits, index syncs, running `verify:` commands — decision-complete work with a binary check |
| standard | `model: sonnet`                          | Workers executing a decision-complete plan step: implementation, tests, drafting                                         |
| strong   | `model: opus` or inherit                 | Planning, review, verifying strong-tier work, unblocking, security/concurrency/schema surfaces                           |
| frontier | `model: fable`                           | Never auto-selected — explicit user request only                                                                         |

- Verification subagents may run one tier above the executor for high-risk tasks — cheap execution with stronger checking is the cost-optimal asymmetry.
- Context caveat: the fast tier's context window can be much smaller (Haiku: 200K); never route a sweep that could exceed it — split the sweep or use standard.
- The single worker retry (see Integrating Results) also escalates one tier when the first failure was reasoning quality rather than missing context.
- Model tier and context size are independent axes: large-context mechanical reading wants a cheap model across fresh-context subagents; small-context hard reasoning wants a strong model.

## Safety And Cost

- Keep delegation one level deep unless the user explicitly asks for recursive delegation.
- Use read-only subagents (`Explore`) for any read-only delegation whenever possible.
- Give parallel writers `isolation: worktree` so concurrent edits cannot conflict.
- Be cost-aware on template/downstream projects: match fan-out to the size of the request so a trivial ask doesn't spin up expensive parallel work — judgment, not a brake on genuinely parallel work.
