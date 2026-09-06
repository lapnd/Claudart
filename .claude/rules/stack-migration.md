---
paths: ["**/*"]
description: Cross-runtime port missions — porting a codebase to another language, runtime, or UI framework while preserving observable behavior; translation-unit sizing, contract-first seam, UI-fused source decomposition, and parity proof.
when_to_use: When a mission ports code across a language/runtime/UI-framework boundary (Python→Go, NiceGUI→Vue, Django→Nest, Streamlit→SPA), when running /migrate, or when a spec folder carries a source-baseline plus a separate target stack.
tags: [migration, porting, parity, architecture]
---

# Stack Migration (Cross-Runtime Port)

## Scope

This rule fires when the **language, runtime, or UI framework changes** while user-observable behavior is preserved: Python → Go, NiceGUI → Vue SPA, Django → NestJS, Streamlit → React. `/migrate` enters this flow.

It layers onto `spec-workflow.md`'s **Refactor Missions** section — same dated spec folder, same baseline pin, same behavior contract, same LEDGER and gates. Where the two differ for a port mission, this file wins, because Refactor Missions assumes one codebase with one build, and a port has two of each.

A port that is genuinely one file with no framework boundary crossed is not a mission — that is `/plan` plus the idiom skill.

## 1. The Compiler Contract

A migration is a translation whose **source of truth is the baseline code**. The translator is probabilistic: identical prompts produce identical output for a trivial function and nine different programs for a feature-sized one. Determinism degrades as the input becomes higher-variance prose and the requested output grows.

Everything below follows from that one fact:

- **L1 — Code is the input; prose is the fallback.** Feed the agent the source of the unit being ported, not an English retelling of it. English is reserved for invariants the source cannot express (the _why_, the business rule behind the branch), never for restating what the code plainly says. A prose retelling is a lossy re-encode, and it is where invented behavior enters.
- **L2 — One translation unit per task.** A unit is one source module, or one cohesive behavior, mapping to one target package or one target feature module. "Port the service" and "add pagination to every list endpoint" are not units; context-window-scale cross-cutting edits are the documented failure mode — tasks get silently skipped and implementations degrade.
- **L3 — Two passes, never one.** Generation is followed by a **separate** pass that re-reads the pinned source and diffs it against the produced target. The pass that wrote the code never certifies it in the same breath.
- **L4 — Determinism is bought with tests, not with prompt wording.** A behavior counts as ported only when a test derived from baseline behavior was seen failing against the empty target and passing after. `evidence-gauntlet.md` governs how that failure is witnessed.
- **L5 — A compiler preserves semantics, not structure — and so does this.** The behavior contract is what must survive 1-1. The implementation must **not**. Where the target language offers a better data structure, a better concurrency shape, a better standard-library primitive, or a mature library that removes hand-rolled code, **use it** — a faithful transliteration is a defect wearing the costume of fidelity. The parity gate is precisely what makes this safe: observable behavior is pinned by a differential run, so everything underneath it is free. A port that reproduces the source's structure produces a codebase nobody wants to own, and it forfeits the one benefit that justified the migration.
  The fence is the same as everywhere else (`ai-behavior.md` §3/§4, `code-organization.md` §11): choose the better target-native form of _the behavior being ported_; do not invent capability the source never had. "Go does it this way" is a reason; "we might need it later" is not.

Control is not a dial to turn to maximum. Tightening the _what_ — the frozen contract, the translation rules, the parity checks — buys determinism where it pays. Tightening the _how_ — dictating the target's internal implementation line by line — buys nothing and costs the judgment you are paying the translator for. `ROADMAP.md` already draws this line: it carries decisions and `verify:`, not solutions. A port mission that specifies every function body has stopped being a migration and become a slow transcription.

## 2. Spec-Time Artifacts

Beyond the Refactor Missions set, a port mission's spec folder carries:

- **`baseline: <sha>`** of the **source** repo in `SPEC.md`. When the target is a separate repository, record `target-repo:` and its own starting sha as well. Every contract citation points into the source baseline.
- **`artifacts/behavior-contract.md`** — built from the pre-change source, per Refactor Missions.
- **`artifacts/translation-rules.md`** — _this project's_ idiom table (source pattern → target pattern → why → one example from this codebase). Generic catalogs seed it; every row the mission actually relies on is restated here with a real example from the source. This artifact is the single most load-bearing thing the planning session produces: it is what keeps ten sessions translating the same construct the same way.
- **`artifacts/module-inventory.md`** — every source file mapped to its target package/component, with dependency order and a risk tag. It is a **derivation input for the ROADMAP, not a second task list**. `ROADMAP.md` stays the only place tasks are ticked; a parallel `MIGRATION.md` checklist duplicates the LEDGER and drifts out of sync with it.
- **`artifacts/api-contract/`** — the frozen seam between the target's halves (§4).

## 3. Phantom-Feature Hygiene (before Phase 1)

Deprecated comments, orphaned type hints, and stale schema references in the source are read by the agent as requirements, and it will faithfully rebuild a feature that was removed years ago. Before any target code is written, sweep the source for dead references and record each one as either:

- **deleted in the source** — which changes the baseline, so re-pin `baseline:` and say so in the LEDGER; or
- **present in source, deliberately not ported** — an explicit `SPEC.md → Must-NOT-Have` line.

Implicit is not an option. An unclassified dead reference will be ported.

## 4. Contract-First Seam

When the port splits one process into two (backend + SPA, service + client), the target's **public API is designed and frozen before any target code exists**. Left undesigned, the agent takes the language default — everything under Go's `internal/`, handler shapes invented per endpoint — and the API becomes an accident of generation order.

- The seam is an explicit machine-readable contract: OpenAPI for REST, proto for gRPC, a schema document for events.
- **Parity gate**: the contract regenerated from the ported target diffs clean against the contract extracted from the baseline, minus deltas enumerated in `SPEC.md`. This gate runs at every phase boundary that touches the seam, not once at the end.
- The target's client library (typed SDK, generated Vue API layer) is a first-class deliverable with its own acceptance scenario, not a byproduct.
- Configuration is one typed struct resolved at the composition root. Per-package defaults scattered through the target are a port-time regression, not a style question.

## 5. UI-Fused Sources Must Be Decomposed Before Translation

NiceGUI, Streamlit, Gradio, Dash, Shiny, and server-side Blazor fuse **domain logic, application state, and UI** inside one server-side callback, with the reactive binding hidden in the framework's own transport. There is no file-to-file mapping to a Go + SPA target, and attempting one produces a Go program shaped like a UI event loop.

Every source callback is split into three **named** destinations before a line of target code is written:

1. **Domain / use case** → the target's framework-free core (`code-organization.md` §3–§4).
2. **Transport** → an explicit endpoint or event on the §4 contract. This is the piece the framework was hiding, and it is where most porting bugs live.
3. **View / interaction** → the SPA component plus its store.

Implicit server-held per-user state (`app.storage.user`, module-level globals, closures capturing the client) has **no** equivalent on the other side. Enumerate every instance in the behavior contract, and give each one an explicit destination — client state, or a server-side session record with a stated lifetime. An unenumerated one is a silent data-loss bug that surfaces only under concurrent users.

## 6. Target Architecture and Dependencies Are Enforced, Not Aspirational

`code-organization.md` defines the hexagonal target and is not restated here. A port adds only this: **every architectural claim in the SPEC carries a command that fails when the claim is false.**

- Dependency direction gets an executable observable, e.g. the domain package's transitive dependency list contains no HTTP, SQL, or UI package — asserted by a command whose exit status is the gate, run at every phase validation.
- The SPA mirrors the backend's domain boundaries as feature modules; network access lives only in a typed client at the adapter edge; stores hold application state and never a second copy of a domain rule that the backend owns.
- Directory names prove nothing. A claim like "the domain is framework-free" that no command checks is decoration, and by the final gate it will be false.

**Dependency licensing is a hard constraint on every library the port introduces, not a review-time afterthought.** A port is the moment a codebase acquires most of its new dependencies, and by the time one is woven through twenty files, replacing it is a project.

- **No GPL or AGPL anywhere in the dependency graph of shipped code**, unless the user has explicitly approved that specific dependency. Permissive licenses only — MIT, BSD-2/3, Apache-2.0, ISC. MPL-2.0 is file-level copyleft and is usually acceptable, but it is a decision to record, not to assume.
- **Why AGPL specifically**: it extends copyleft to network use, so serving the software over a network can trigger source-disclosure obligations. For a product delivered as SaaS that is the difference between shipping and publishing your source.
- **Linking is not deployment.** This constraint governs what the shipped binary or bundle links or derives from. Running an unmodified copyleft program as a separate service or container is a different situation with different obligations — if the mission does that, record it as an explicit decision in `NOTES.md` rather than letting the rule silently cover or silently forbid it.
- **Verify the license at the pinned version, never from memory.** Licenses change under a project's feet, and several widely-used systems have relicensed away from OSI-permissive terms. A library that was safe in a blog post from two years ago is not evidence.
- **The gate is a command, like every other claim here**: a license scan over the resolved dependency graph, run in phase validation, exiting nonzero on any denied license. A list in a document is not a gate. This is `code-quality.md` §10's license check, made binding for the port.

## 7. Parity Verification — Three Families

`spec-workflow.md` requires static, dynamic, and architectural evidence. For a port, they specialize:

- **Differential run against the running baseline** (dynamic). Both stacks up, same inputs, responses diffed. This is the only evidence that counts as parity. Unit tests green on both sides while the assembled application returns wrong results is the documented, expensive failure mode.
- **Smoke test from Phase 1** — one command that boots the target and drives one real end-to-end user path. It exists before the second unit is ported and runs at every phase gate. A port with no smoke test until the end is a port whose first integration happens after every decision is expensive to reverse.
- **Contract diff** (§4) — static, and the cheapest parity signal available.
- **Data migration rehearsal early** — against a copy of real production-shaped data, in the first phase that touches persistence. Schema and encoding faults found in the last phase invalidate everything built on them.
- **Dead-code sweep after every phase** — unreferenced exported symbols in the target are removed by proof recorded in the LEDGER, or justified there. Refactoring during a port leaves orphans that the target's own compiler is happy to keep.
- **Stale-reference sweep** — no `*_old`, `*_v2`, or compat shim survives to the final gate.

A skipped pass is recorded with its reason. Silence reads as verification later.

## 8. Cutover and the Source's Fate

A port is not done because the target passes. `SPEC.md` states the cutover shape up front — big-bang, strangler-fig behind a routing seam, or parallel-run with response diffing — and the **Definition of Done adds**: cutover executed or explicitly scheduled with its trigger, the source repository marked (archived, frozen, or scoped to what remains), and a stated rollback path. A target nobody switched to is an unfinished mission, not a completed one.

## 9. Session Discipline

- The spec folder is the resumption state. Each session re-reads `SPEC.md`, `ROADMAP.md`, `NOTES.md`, and the LEDGER tail, and derives its next unit from them — `/spec-run` already is the loop. Do not build a second autonomous loop with its own checklist file beside it.
- Rotate at phase boundaries; a port is long, and a fresh session re-reading the files beats a compacted one recalling them.
- Two failed attempts at the same unit escalate the tier. A third attempt with the same approach is a token sink.
- A pre-existing bug discovered in the source is a `NOTES.md` finding, never a silent fix — fixing it changes behavior, and the parity diff will flag it as a regression.

## 10. Model and Token Economy

A port is the longest mission shape CLAUDART runs, so tier discipline is not a nicety here — it is the difference between a mission that finishes and one that burns its budget on phase 2. `agent-delegation.md` → Model & Effort Routing owns the tiers; this section says how a port distributes across them, and the ROADMAP must carry that distribution as `(tier: …)` annotations so an executing session can act on it without re-deriving it.

| Tier         | Port work that belongs there                                                                                                                                                                                                      |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **fast**     | Mechanical units with a binary `verify:` — a value object becoming a struct, a comprehension becoming a loop, a DTO mapping, regenerating the client from the contract, running a sweep, running the architecture or license gate |
| **standard** | The bulk: porting one use case with its tests, one SPA feature module, one adapter                                                                                                                                                |
| **strong**   | Decomposing a fused callback, anything touching concurrency or shared state, designing the seam, schema and data migration, the auth boundary, and every unblock                                                                  |

- **The artifacts are the token optimization.** `behavior-contract.md`, `translation-rules.md`, and `module-inventory.md` exist so the expensive reasoning happens once, in the planning session, and every later session reads a decision instead of re-deriving it. A mission where cheap sessions keep re-reading the whole source has an artifact problem, not a model problem.
- **Read the unit, not the module.** The inventory names the source lines a task needs. Loading a 4,000-line UI file to port one callback is the single largest avoidable cost in a port.
- **Verify one tier above execution on risk surfaces.** Cheap execution with stronger checking is the cost-optimal asymmetry, and it is exactly where a port's expensive defects live (concurrency, state ownership, auth).
- **Bulky evidence goes to a file and is referenced by path.** Differential runs, contract diffs, and license scans produce output that must never be pasted into the LEDGER or the session.
- **Rotate at phase boundaries rather than pushing a degrading session.** A fresh session re-reading four files costs less than a compacted one reconstructing them, and it makes fewer mistakes.
- **Escalate by rotation, not by grinding.** Two failed attempts at one unit is the signal; a third attempt at the same tier costs more than the stronger session would have.
- Record a tier that proved wrong — a `fast` task that needed escalation, or a `strong` task that was mechanical — in `NOTES.md`, so the remaining roadmap is re-tiered rather than repeating the misjudgment for thirty more units.

## Anti-Patterns

- Transliterating source syntax into the target language instead of translating to target idiom — the result compiles, reads as foreign, and rots.
- Preserving the source's data structures, class layout, or hand-rolled utilities when the target language has a better native answer — fidelity is owed to behavior, never to shape.
- Pulling in a GPL/AGPL dependency during the port because it was the first search result, or assuming a license from memory instead of checking it at the pinned version.
- Porting UI-framework callbacks file-to-file, carrying the fused UI/state/domain structure into the new stack.
- Writing the API contract after the handlers, and calling whatever was generated "the contract".
- Treating unit tests as parity evidence when no differential run against the baseline was ever executed.
- A `MIGRATION.md` checklist living beside `ROADMAP.md` — two task lists, one of them stale.
- Feeding the agent a prose summary of the source module instead of the module.
- One task that changes every endpoint, every model, or every component at once.
- Leaving the target's public API surface to the language's default (`internal/` everywhere, or nothing).
- Declaring the mission done while every user is still on the source stack.
- Running every translation unit on the strongest available model because the mission feels important, or loading a whole source module to port one function.
