---
description: Create a behavior-preserving refactor/migration spec mission — pin a baseline, write a behavior contract and blast radius from the pre-change code, then hand the mission to /spec-run for autonomous execution.
---

The user's request after `/refactor` is a refactor or migration mission ("restructure X without changing behavior", "migrate from A to B", "audit this already-refactored module"). If empty, ask: "What's the refactor mission?"

This command is an entry point, not a separate protocol. Run the `/spec` flow (read `.claude/commands/spec.md` and `.claude/rules/spec-workflow.md` first) with its **Refactor Missions** section active from the start:

1. Follow `/spec` Steps 1-6 exactly — same dated folder in `.claude/specs/`, same drafting lock, same SPEC/ROADMAP/NOTES/LEDGER, same standing approval.
2. Apply the Refactor Missions overlay throughout: pin `baseline: <sha>` before anything else; build `artifacts/behavior-contract.md` and the blast radius from the baseline worktree during Steps 2-4; derive Acceptance Scenarios from contract entries; write `verify:` lines in the refactor verification vocabulary; carry the refactor sequencing rules and Definition of Done additions into the ROADMAP.
3. POC fidelity: for a pure refactor the frozen reference is usually the behavior contract plus the pinned baseline itself, not an HTML artifact. Offer the user the choice, defaulting to contract-as-artifact.
4. Execution is unchanged: on approval the user runs `/spec-run <slug>` — the executor needs no refactor-specific knowledge beyond what the ROADMAP carries.

If the request is actually a small, single-file refactor, say so and suggest `/plan` instead — list the at-risk behaviors in the task's Memory Hints and carry the sweeps as Validation checks.
