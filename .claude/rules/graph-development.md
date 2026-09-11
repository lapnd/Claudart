---
paths: ["**/*"]
description: Graph-driven development — the architecture of the software being built is an executable dependency graph of nodes (claim + verifier + state) that AI plans, schedules, and proves against, layered on the hexagonal target of code-organization.md.
when_to_use: When a spec mission carries an architecture.yaml + a graph-format ROADMAP, when running claudart-graph, when decomposing a hexagon into nodes/edges, or when scheduling or verifying graph-driven work.
tags: [architecture, hexagonal, graph, tdd, scheduling]
level: law
authority: standard
status: approved
since: 2026-09-06
stale_after: 2027-09-06T00:00:00Z
verified:
  - by: human:lapnd
    at: 2026-09-06T00:00:00Z
enforcer: check:.claude/scripts/constitution-check.sh
layers_on: [code-organization, evidence-gauntlet]
load: trigger
order: 80
trigger: "read when a spec mission carries an `architecture.yaml` + a graph-format ROADMAP, when running `claudart-graph`, or when decomposing/scheduling/verifying a hexagon as a node graph."
digest: "the adopting project's hexagonal architecture is an executable dependency graph of nodes (claim + verifier + state) folded from an append-only event log the orchestrator alone writes; kinds are hexagonal roles from the manifest profile; contract/port before implementation and one shared contract test per outbound port; TDD is an edge — behaviour requires an observed-red test, never weaken a test; a port/contract/domain change is a scope change; every MUST is tagged to an enforcer (`claudart-graph rules`) or marked judgement; layers on `code-organization.md` and `evidence-gauntlet.md`."
---

# Graph-Driven Development

The software's hexagonal architecture (`code-organization.md`) is not prose an agent re-reads and
re-interprets each session — it is an **executable dependency graph** the agent consumes. Every
claim about the architecture is a node with a verifier the orchestrator can run; the graph's state
is a fold over an append-only event log, never a mutable file an agent edits. This rule defines the
graph; `claudart-graph` (`.claude/scripts/claudart-graph.sh`) is its engine, and every MUST below
is tagged with the enforcer that makes it checkable (`claudart-graph rules`) — or marked
`⟦judgement⟧` where no machine can decide it and a reasoning agent must (D29). An untagged MUST is a
rule with no legislation, and CLAUDART does not keep those in any project it operates on.

## 1. A node is a claim + a verifier + a state

Each node asserts one thing about the architecture (`domain/user` exists and holds its invariants;
`port/notification` is implemented by every adapter) and carries a `verify:` command that decides
the claim. State is never written by hand: it is folded from `graph/events.jsonl`, the one file the
engine appends to and the **orchestrator alone** writes.

- MUST: node ids are `<kind>/<name>` and kinds come from the manifest's profile. ⟦enforcer: BAD-ID, UNKNOWN-KIND, UNKNOWN-PROFILE-KIND⟧
- MUST: `verify:` is a shell command the orchestrator can execute, never prose about one and never a bare scenario id. ⟦enforcer: VERIFY-NOT-COMMAND⟧
- MUST: a workflow that has no runnable verifier is not a node yet — every roadmap task carries a scheduling decision. ⟦enforcer: UNANALYSED-TASK⟧

## 2. Kinds are hexagonal roles, from a profile

Kinds are not free text; they are the roles of the target architecture, supplied by the manifest's
`profile` (`hexagonal`: domain, usecase, port, adapter, contract, mock, composition, test, merge,
gate, spike — `debug` and `library` are other profiles). This is what makes the graph a picture of
the hexagon rather than a generic TODO list.

- MUST: only the composition root wires more than one adapter. ⟦enforcer: NOT-COMPOSITION⟧
- MUST: a gate node writes nothing — it only checks. ⟦enforcer: GATE-WRITES⟧
- MUST: dependency direction obeys the manifest's `rules.forbid`; **adapters never import adapters**, the domain imports no infrastructure. ⟦enforcer: FORBIDDEN⟧
- ⟦judgement⟧ A port is an **interface, not a utility drawer**: a capability the domain owns, discovered from its consumers. Two small consumer-discovered interfaces beat one union interface; a global with a setter is worse than the import it replaced. The lint proves direction, not taste — this clause is yours to hold.

## 3. Edges are real dependencies; the graph is a DAG

An edge is a dependency that actually exists (IMPLEMENTATION, CONTRACT, PORT, DATA, RUNTIME, TEST,
DEPLOYMENT, EVIDENCE), never a "these feel related". Waves are **computed** from the edges, not
declared; a phase heading is a human milestone, and phase order is itself an ordering dependency
unless `early-ok` says otherwise.

- MUST: every `requires`/`proves` target exists and the edge type is registered. ⟦enforcer: DANGLING, BAD-EDGE⟧
- MUST: the graph is acyclic. ⟦enforcer: CYCLE⟧
- MUST: a node in a later phase with no `requires` and no `early-ok` is a mis-scheduled orphan. ⟦enforcer: PHASE-ORPHAN⟧
- MUST: a path query that matches nothing in the real tree is a wrong query and fails closed. ⟦enforcer: EMPTY-PATH-QUERY⟧

## 4. Contract before implementation; the port is a scheduling device

Freeze the seam first. A port/contract is designed and its shared contract test written **before**
any adapter, because the port is what lets independent adapters fan out in one wave — the port task
ships its own fake so consumers can proceed. Doubling both sides of a frozen seam is the unit of
parallelism (`stack-migration.md` §4, Lessons II.2).

- MUST: one shared contract test per outbound port, and every adapter passes it. ⟦enforcer: PORT-TEST-MISSING, ADAPTER-SKIPS-PORT-TEST⟧
- MUST: adding or removing a port, contract, or domain in the manifest is a **scope change**, surfaced for approval — the executor does not silently re-shape the hexagon. ⟦enforcer: MANIFEST-CHANGE-NEEDS-APPROVAL⟧
- MUST: architecture debt (`architecture.budget`) is a ratchet matched exactly in both directions; a debt drop with no port/move/merge is hiding, not fixing. ⟦enforcer: GATE-BUDGET, UNEXPLAINED-DEBT-DROP⟧
- MUST: recurring merge conflicts on the same files reveal a missing port or contract, not bad luck. ⟦enforcer: HIDDEN-DEPENDENCY⟧

## 5. TDD is structural: architecture → tests (observed red) → implementation

The ordering is not a culture, it is an edge: a behaviour node `requires:` its test node, and becomes
ready only when that test is **red** — observed failing, not merely written. Red → Green → Refactor,
and a test must **fail, never panic** (a collection/import error is a weaker red than an assertion).
This is the same gate as `evidence-gauntlet.md`'s `red-verified`; the graph is where it is enforced
per node.

- MUST: architecture → tests → implementation. A behaviour node has a TEST edge; `done` needs an observed red first; `red` needs a nonzero exit; a test's `green` follows only a prior red. ⟦enforcer: NO-TEST-FIRST, TEST-PROVES-NOTHING, REFUSED-TRANSITION⟧
- MUST NOT: skip, disable, weaken, or delete a test to reach green — a failing test is information (`ai-behavior.md` §5, `code-quality.md` §2). ⟦judgement⟧ (the engine enforces ordering; not weakening an assertion is yours)
- MUST: a strong-tier implementation records a mutation score; surviving mutants are killed or classified, never papered over. For Go, the mutation tool is **gremlins** (<https://gremlins.dev/latest/>); other stacks use their ecosystem's tool (`evidence-gauntlet.md` §5). ⟦enforcer: MUTATION-MISSING⟧
- In the `debug` profile the same shape holds: a `fix` requires a CONFIRMED hypothesis and a red repro. ⟦enforcer: FIX-WITHOUT-CAUSE⟧

## 6. The orchestrator observes; workers never write the graph

A worker receives a **brief** and returns a claim. The orchestrator runs the `verify:` itself and
records what **it** observed — a worker's "tests passed" is a claim, not evidence (`delegation.md`
§3, D30). The worktree cannot even see the gitignored spec folder, so a worker physically cannot
write the graph; this is by design, not convention.

- MUST: the orchestrator runs verify; a worker's claimed exit is checked against the observed one. ⟦enforcer: CLAIMED-EXIT-REJECTED⟧
- MUST: an absent or empty evidence file means the job never ran — it is a failure, not a pass. ⟦enforcer: EVIDENCE-MISSING⟧
- MUST: timestamps come from the clock, never typed. ⟦enforcer: FUTURE-TIMESTAMP⟧
- MUST: the brief has a byte budget — it is all an agent receives, so it carries the source and the decision, not a novel. ⟦enforcer: BRIEF-OVERSIZE⟧
- MUST: a spec running past its budget with no terminal event is a crash to recover, not progress. ⟦enforcer: STALE-RUNNING⟧

## 7. Refinement reopens dependents; the graph evolves continuously

The graph is not drawn once. A greenfield mission starts from a coarse hexagon and refines it —
each refinement re-runs the fold, and reopening a node marks its transitive dependents stale so they
are re-verified against the new reality. A brownfield project is **scanned** (`claudart-graph audit`)
into a seeded manifest + a test-first refactor plan, then evolved the same way.

- MUST: an adapter reopened after its port test went green has a weak contract test — the seam did not hold. ⟦enforcer: UNSTABLE-CONTRACT⟧
- MUST: overlapping coding waves isolate in worktrees and reconcile through a **merge node**; a merge is a node with a verifier, not an afterthought. ⟦enforcer: HIDDEN-DEPENDENCY (recurring conflicts) ; judgement for the merge itself⟧
- ⟦judgement⟧ Remediation of a drift finding follows the four-case taxonomy (Lessons III.6): **repoint** to the port the symbols belong to · **inject** at the composition root · **extract** a package named for the concept · **move** a misfiled pure computation to the domain. The extractor prints the class; choosing correctly is judgement.

## 8. Cost and re-approach discipline

- MUST: route each unit to the cheapest tier that clears it; a failed attempt at one tier followed by success one tier up cost both, and a task that retries more than once without escalating is grinding. ⟦enforcer: WRONG-TIER, HIGH-RETRY⟧
- ⟦judgement⟧ Two same-shaped failures against one node change a **dimension**, never just the effort (`ai-behavior.md` §6, Lateral Re-approach): a wall hit twice becomes a NOTES `→ graduate` lesson, not a third identical attempt.

## Relationship to the rest of the harness

This rule is the graph-specific instance of `code-organization.md` (the hexagon it encodes),
`evidence-gauntlet.md` (whose `red-verified` gate it enforces per node), `spec-workflow.md` (the
mission loop that drives the graph), and `delegation.md` (the brief/observe contract). Where they
overlap it does not restate them; it makes their claims **checkable** as graph nodes and edges.
