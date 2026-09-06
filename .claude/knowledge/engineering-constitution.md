---
name: engineering-constitution
description: "The decision-priority ladder and sixteen Golden Rules that rank engineering values across any CLAUDART project."
type: reference
status: active
updated: 2026-09-06
last_verified: 2026-09-06
scope:
  - "path:.claude/rules/constitution.md"
related:
  - "rule:constitution"
  - "rule:graph-development"
sources:
  - "../rules/constitution.md"
---

# Engineering Constitution (reference)

The binding form lives in `.claude/rules/constitution.md` (auto-imported); this is the archival
reference. It ranks the values that collide in real work and states the standing defaults.

## Decision Priority (higher wins on conflict)

1. Correctness and safety — cost/speed never justifies a wrong result or unsafe design.
2. Architectural integrity — hexagonal boundaries and dependency direction.
3. Long-term maintainability — optimise the system, not the ticket.
4. Reliability and reproducibility — evidence over assertion.
5. Reuse and automation — deterministic artifacts over repeated LLM work.
6. Parallelism and execution speed — independent work runs concurrently.
7. LLM / context / cache efficiency — minimise the boundary and tokens.
8. Short-term convenience — last.

Ties on 1–4 break toward the cheaper, faster, more deterministic, more reusable option.

## The Sixteen Golden Rules

1. Think before executing. 2. Reuse before creating. 3. Cache before recomputing. 4. Reduce before
   reasoning. 5. Compute locally. 6. Minimize the LLM boundary. 7. Preserve stable context.
2. Increment, don't rebuild. 9. Batch and parallelize. 10. Automate repetition. 11. Prefer
   deterministic artifacts. 12. Learn after every task. 13. Improve the Constitution. 14. Design for
   the long term. 15. Hexagonal and modular by default. 16. Management enables parallelism.

Cost discipline is standing and real, and it stops at correctness (priority 1).
