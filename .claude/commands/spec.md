---
description: Create a dated mission-scale spec workspace in .claude/specs/ — interview the user, freeze the intent in a reviewable POC artifact, then write a decision-complete SPEC + ROADMAP that a later (often cheaper) session can execute autonomously via /spec-run.
---

You are the expensive planning session. Everything you learn from the user in this conversation dies with it — the spec folder you produce is the only thing the executor will ever see. Spend the tokens here so `/spec-run` doesn't have to.

Before doing anything, read `.claude/rules/spec-workflow.md` and `.claude/rules/knowledge-management.md`. These rules define mission state and knowledge routing; this command does not duplicate them.

## Inputs

- The user's request after `/spec` is the mission description. If empty, ask: "What's the mission?"
- If the request is actually a single feature or fix, say so and suggest `/plan` instead. If it is a raw product idea with no repo and no scope at all, suggest `/project-discovery` first — `/spec` can then build on its `docs/project/` output.
- If the mission is behavior-preserving refactoring or migration, additionally apply the **Refactor Missions** section below throughout the procedure.
- If that migration also crosses a language, runtime, or UI-framework boundary, it is a port: read `.claude/rules/stack-migration.md` and apply it on top of Refactor Missions (`/migrate` enters here directly).

## Procedure

### Step 1 — Read project context

In parallel: `.claude/CONTEXT.md`, `.claude/specs/INDEX.md` (if an active spec already covers this mission, surface it and ask whether to continue it instead), the root knowledge router plus only relevant routed detail within the knowledge budget, `docs/project/` if present, and `git log -5 --oneline`. If the user continues an existing `drafting` spec — including an approved final-review scope amendment returned by `/spec-run` — reuse its dated folder; never create a duplicate mission folder.

Ensure `.claude/specs/done/` exists. Before deciding whether an existing spec is active, check its `SPEC.md` frontmatter status; a top-level spec folder with `status: done` or `status: cancelled` is stale archive state, not an active collision, and should be moved to `.claude/specs/done/` when syncing INDEX.

For a new mission, create `.claude/specs/YYYY-MM-DD-<slug>/` using today's date and the slug rules from the rule file, write a minimal `SPEC.md` with `slug: <slug>`, `status: drafting`, and `rotation: auto` (the executor rotates itself; write `rotation: offer` only when the user asks for a human gate at rotations), and register it in `INDEX.md` with the dated folder link. For a resumed draft, keep its existing dated id and history. From here on, the folder is where everything lands — not chat.

**Drafting lock**: while `status` is `drafting` or `poc-review`, write no implementation code and normally write only the spec folder and its INDEX. The sole exception is an eligible knowledge mutation when the full capture gate and an immediate-promotion trigger in `knowledge-management.md` pass; update owner + reachable map atomically and run the checker.

### Step 2 — Interview, capture-as-you-go

Interview like `/project-discovery` (one highest-leverage question at a time, options with trade-offs) — but aim every question at one target: **what must a POC prove for the user to say "yes, that's it"?**

**Write every confirmed decision into `SPEC.md` as it lands** — after every few answers, not at the end. The chat does not survive compaction; the spec folder does. Keep the draft's working split visible: confirmed / rejected (→ Must-NOT-Have) / open. By the time you start the POC, the core intent is already on disk.

### Step 3 — POC loop, at the fidelity the user picks

A POC exists so the user can _judge intent_ — it is a reference the executor will later compare against, not an early build of the product. Before building anything, propose the smallest artifact set that proves the riskiest aspects of the mission, and let the user choose its shape:

- Default: one self-contained artifact in `artifacts/` — HTML with inline CSS/JS, no external requests, openable by double-click.
- For complex missions, prefer **several narrow artifacts over one high-fidelity build** — each freezing a single aspect: one proving the core interaction/feel with primitive placeholders (shapes, boxes, dummy data — no polish), a separate visual-style reference, an annotated flow demo. Wiring every aspect into one polished artifact is drafting-stage overengineering; do it only if the user explicitly opts in.
- Present, collect reactions, revise. Each iteration converts an open question into a confirmed decision or a Must-NOT-Have, and updates **SPEC.md and the artifact together** — a decision that lives only in the POC, or only in chat, is a defect.
- Loop until the user says the set matches their intent. The approved artifacts are then **frozen as references** the executor verifies against — name each one and what it locks in under `SPEC.md → POC Artifacts`.

### Step 4 — Finalize SPEC.md

The skeleton is already half-full from Steps 2-3; finish it. The hard part is **Acceptance Scenarios**: each one a literal action plus a binary observable, executable by someone who never saw this conversation. Keep scenarios independently traceable without manufacturing duplicate commands: one concrete verifier may cover several scenarios when its output proves each observable, while a scenario whose literal user action matters keeps that action as direct evidence. Push every rejected option and deferred feature into **Must-NOT-Have** — that section is what stops a cheaper executor from gold-plating or wandering.

### Step 5 — Write ROADMAP.md (decision-complete)

Explore the codebase read-only first (existing patterns, constraints, files each phase will touch) — de-risk decisions, don't pre-solve implementation. Fan out read-only `Explore` subagents if the survey is broad.

Then write phases per the rule file. Hold the decision-complete bar: exact paths, chosen approaches with the _why_, per-task `verify:`, phase validation commands, parallelizable waves marked for fan-out — mark a wave only when every pair of its tasks passes `agent-delegation.md`'s disjointness test (no file/module overlap, no output dependency, no ordering dependency); when in doubt, leave tasks unmarked and let `/spec-run` re-derive waves at execution time instead of guessing.

**Tier-annotate tasks** so an executing session can pick the right model: the default is `standard`; append `(tier: fast)` when a step is mechanical with a binary `verify:` touching at most 2 files, and `(tier: strong)` when it carries security/concurrency/db risk, touches a public contract or schema, or its `verify:` needed judgment to write. Set SPEC frontmatter `executor-tier:` to the cheapest tier that covers the roadmap: `standard` when every task is fast or standard; `strong` only when strong-tier tasks dominate — a mostly-standard roadmap with a few strong tasks stays `standard`, and the executor rotates or delegates one tier up for those tasks (tiers per `agent-delegation.md` → Model & Effort Routing). Make final verification coverage legible enough that a future executor can select the smallest non-redundant set: identify which checks prove which scenarios and when a composite check already includes leaf checks. Do not require a second direct run of an included leaf unless the leaf is itself a scenario action or serves a distinct observable. Phase 1 should reach something demoable early — the mission must produce visible progress every phase, not a big-bang integration at the end.

For a new mission, seed `LEDGER.md` with its header and no entries, and `NOTES.md` with what exploration surfaced: how to run, build, and verify the project (dev server, test commands), key files and helpers, non-obvious constraints, pitfalls, planning-time decisions with their rejected alternatives. Include `## Current Acceptance Delta` with `- None.`; it stays compact during execution and is never a second roadmap. For a resumed scope amendment, preserve LEDGER history and existing NOTES, then amend ROADMAP using its disposition rules rather than erasing completed or superseded work. NOTES is the executor's Memory Hints — a roadmap without it forces the executor to re-discover everything you just learned.

#### Hexagonal decomposition — make the roadmap graph-ready

When the mission builds or extends a hexagonal codebase (`code-organization.md`), emit the mission's architecture as a graph the executor can schedule and prove against, per `.claude/rules/graph-development.md` — that rule is the authority on node kinds, TEST-first edges, and one-shared-contract-test-per-port; this step only says what `/spec` produces. Skip this for a mission with no hexagon (a pure doc/config change); apply it in full for any feature system or service.

1. **Write the Hexagonal Decomposition into SPEC.md (or the head of ROADMAP.md)** — the project's own hexagon, never this harness's: its **domains** · **use cases** · **ports** (each tagged `direction: in` or `out`) · **adapters** (each naming the port it implements) · **contracts** (the frozen API seams). A category with nothing in scope says so; an absent one reads as "not considered".
2. **Write `architecture.yaml` in the spec folder** — `profile: hexagonal`, the `layout:` (where each layer lives in the tree), `rules.forbid` (at least the standard four: `adapter→adapter`, `usecase→adapter`, `domain→port`, `domain→adapter`), and `architecture.budget` (`0` greenfield; the measured count for a brownfield extract). Its `domains`/`usecases`/`ports`/`adapters`/`contracts` mirror the decomposition above.
3. **Plan the ROADMAP in graph format**: `graph-format: 1`, `## Phase N` headings, and each task carrying 6-space-indented `node:`/`kind:`/`requires:`/`proves:`/`paths:` metadata. Put a **`test/*` node before every behaviour node** (domain, use case, port, adapter, composition), and make the behaviour node `requires:` it as a `(TEST)` edge — the red-before-green ordering is the edge, not a convention. Write **one shared contract test per outbound port** (a `test/*` node whose `proves:` is that `port/*`), and make **every adapter of that port `requires:` that same test** as a `(TEST)` edge. `verify:` on every node is a real shell command, never prose and never a bare `S<n>` scenario id.
4. **Tier-annotate** exactly as above (`(tier: fast|standard|strong)`), and set SPEC `executor-tier:` to the cheapest tier covering the roadmap.

The reference shape to copy is `tests/graph/fixtures/spec-template/` (`architecture.yaml` + `ROADMAP.sample.md`) — a minimal generic hexagon that lints clean. Verify the emitted manifest + roadmap before presenting: `bash .claude/scripts/claudart-graph.sh lint --dir .claude/specs/YYYY-MM-DD-<slug>` must print `clean` and exit 0. A dirty graph at approval is a defective spec — fix it in the files, do not hand the executor a graph that will not schedule.

### Step 6 — Fresh-eyes check, then present for review

Re-read SPEC.md and ROADMAP.md as if this conversation never happened, pretending you are the cheaper executor. Any task that needs interview context, any scenario that isn't binary, any duplicated leaf/composite verification with no distinct observable, any ambiguous coverage, or any "as discussed" — fix it in the file now. Flip `status: drafting → poc-review`, sync INDEX, and report:

```
## Spec Ready for Review

**Folder**: `.claude/specs/YYYY-MM-DD-<slug>/`
**POC**: `artifacts/<file>` — open it and check it still matches your intent
**Scenarios**: <n> acceptance scenarios | **Roadmap**: <m> phases, <k> tasks
**Commit policy**: `commits: user` — the loop never commits; say "per-task" or "per-phase" before approving if you want git checkpoints during the run
**Rotation**: `rotation: auto` — the executor checkpoints and launches its own successor session at phase boundaries; say "offer" before approving if you want to be asked each time
**Runnable on**: `<executor-tier>` — run /spec-run from a session of that tier; escalation is the same command from a stronger session
**Open questions**: <list, or "none">

Review SPEC.md (especially Must-NOT-Have) and ROADMAP.md. When you approve, that is a STANDING
approval: /spec-run will execute the whole roadmap without asking again until the final review.
Say "go" to approve — then open a fresh session, /start, and /spec-run <slug> (or the dated folder id if there are multiple active specs with the same short slug).
```

Do NOT begin implementing, even after approval — on "go", flip `status → ready`, sync INDEX, and stop. Execution belongs to `/spec-run`.

## Refactor Missions

When the mission is behavior-preserving refactoring or migration ("restructure X without changing behavior", "migrate from A to B"), the spec carries one extra proof obligation: **behavioral equivalence against a pinned baseline**. The burden of proof is on the refactor, not on the reviewer. This section layers onto the normal procedure — same folder, same ROADMAP/LEDGER/gates, no extra machinery. `/refactor <mission>` enters this flow directly.

### Baseline and behavior contract (during Steps 2-4)

- **Pin the baseline**: record `baseline: <sha>` (`git rev-parse HEAD` at spec time) in SPEC.md under Mission. Every contract citation points into the baseline, not the working tree.
- **Write `artifacts/behavior-contract.md` from the PRE-change code**: enumerate the externally observable behavior in scope — business rules, validation, API shape, persistence semantics, security, observability. ID each entry (`B1`, `V1`, …) and cite baseline `file:line`. A category with nothing in scope says "None in scope" — never delete the heading; an absent heading reads as "not considered". Reconstruct the contract from the baseline worktree, never the refactored code — the new code's omissions must not define the standard. (Auditing an already-refactored codebase uses the same procedure; the refactor just already happened.)
- **Blast radius from search, not memory**: for every symbol or module being moved or changed, enumerate inbound call-sites by grep and record the command that found them. Tag risk surfaces (api / db / security / concurrency / perf / ops); high-risk tags demand their own phase-validation scenarios. Record the **worst credible failure** in SPEC.md — if this refactor is wrong in the worst plausible way, what breaks in production, and how would we notice?
- **Derive Acceptance Scenarios from the contract**: the highest-risk entries become scenarios (composite coverage allowed per the rule file). Every blast-radius call-site must end the mission either migrated-with-evidence or explicitly out of scope.

### Verification vocabulary (for ROADMAP `verify:` and phase validations)

- **Differential worktree run**: `git worktree add <tmp> <baseline>`, run the same command/scenario on baseline and head, diff the outputs. Equivalence is the empty diff; any intended delta must be enumerated in SPEC.md.
- **Deletion audit**: `git diff <baseline>..HEAD | grep '^-'` filtered for control-flow keywords (`if |case |catch |throw |return `) — every deleted branch is either relocated (name where) or an approved removal.
- **Stale-reference sweep**: after moves/renames, grep the old names repo-wide — zero hits outside git history is the pass condition.
- The final gate's evidence set must span three families: **static** (sweeps, deletion audit), **dynamic** (tests plus differential runs on a real surface), and **architectural** (the structural claim the mission exists for, checked by an explicit observable such as "zero imports of X from Y"). A skipped pass is recorded with its reason, never silently — a silently skipped pass reads as verified later.

### Sequencing rules (into ROADMAP task design)

- Every task leaves the repo buildable and green; move and modify are separate steps (and separate commits when the `commits:` policy grants them).
- Migration-era names (`*_old`, `*_v2`, compat shims) may exist only mid-mission and must be gone before the final gate — the stale-reference sweep checks this.
- Dead code is removed by proof (a sweep recorded in LEDGER), never by suspicion.
- A pre-existing bug discovered mid-refactor is a finding recorded in NOTES — never a silent fix. Fixing it changes behavior, and scope changes belong to the user.
- **Definition of Done for a refactor mission adds**: old path fully removed, sweeps clean, and zero behavior deltas beyond those enumerated in SPEC.md.

## Anti-Patterns

- Writing implementation code during `drafting`/`poc-review` — POC artifacts are the only runnable things this command produces.
- Batching spec-writing to the end of the interview — confirmed decisions land in SPEC.md immediately; a compaction must never erase what the user already settled.
- Presenting a spec for approval that no POC ever proved — prose alone drifts; the artifact is how intent gets frozen.
- One monolithic high-fidelity POC when narrow artifacts would answer the same questions — fidelity is the user's call, never the default.
- Acceptance scenarios that need judgment ("looks polished") instead of observation ("HUD matches artifacts/poc.html layout").
- Duplicating acceptance commands merely to give every scenario a separate verifier, or listing composite and included leaf checks as mandatory final-gate replays without distinct coverage.
- Leaving decisions in chat instead of the spec folder. The folder is the plan.
- Treating enthusiasm ("great POC!") as the standing approval — wait for an explicit go signal.
