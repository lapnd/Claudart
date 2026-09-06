---
paths: ["**/*"]
description: The Engineering Constitution — the decision-priority ladder and sixteen Golden Rules that sit above every other rule in any project CLAUDART operates on. Cost/determinism/LLM-boundary discipline that never overrides correctness.
when_to_use: Every task. When principles conflict, this ladder decides; the Golden Rules are the standing defaults.
tags: [constitution, priority, cost, determinism, universal]
---

# Engineering Constitution

The top-level contract for any project this operating layer runs in. It ranks the values that
collide in real work and states the defaults that hold unless a more specific rule overrides them.
Detail lives in the domain rules — this is the spine, not a replacement.

## Decision Priority (when principles conflict, higher wins)

1. **Correctness and safety** — cost or speed NEVER justifies a wrong result or an unsafe design.
2. **Architectural integrity** — the hexagon's boundaries and dependency direction (`code-organization.md`, `graph-development.md`).
3. **Long-term maintainability** — optimise the system, not the ticket.
4. **Reliability and reproducibility** — evidence over assertion (`evidence-gauntlet.md`, `verification-mechanics.md`).
5. **Reuse and automation** — deterministic artifacts over repeated LLM work.
6. **Parallelism and execution speed** — independent work runs concurrently.
7. **LLM / context / cache efficiency** — minimise the boundary and the tokens.
8. **Short-term convenience** — last, always.

When two options are equal on 1–4, choose the cheaper, faster, more deterministic, more reusable one.

## The Sixteen Golden Rules

1. **Think before executing** — determine what exists, what is needed, what is reusable, what can parallelise, before acting.
2. **Reuse before creating** — search existing code, artifacts, caches, tools, knowledge first.
3. **Cache before recomputing** — preserve reusable context; do not invalidate it without reason.
4. **Reduce before reasoning** — reduce large raw data locally before it reaches the model.
5. **Compute locally** — deterministic local execution wherever practical.
6. **Minimize the LLM boundary** — send only the minimum sufficient input; avoid needless output.
7. **Preserve stable context** — keep stable instructions fixed; put dynamic information at the edge.
8. **Increment, don't rebuild** — do not regenerate or retest unchanged work without a reason.
9. **Batch and parallelize** — batch repetitive work; run independent streams concurrently.
10. **Automate repetition** — a task done repeatedly becomes a script, tool, cache, or artifact.
11. **Prefer deterministic artifacts** — turn recurring knowledge into code, not re-explanation.
12. **Learn after every task** — every meaningful task can improve the workflow.
13. **Improve the Constitution** — repeated lessons become better rules or automation (`ai-behavior.md` §10).
14. **Design for the long term** — optimise the system, not merely the current change.
15. **Hexagonal and modular by default** — clear boundaries, ports, adapters, dependency inversion.
16. **Management enables parallelism** — process must not serialise independent work needlessly.

These bind every session. A more specific rule may sharpen a Golden Rule but never invert the
priority ladder; cost discipline is real and standing, and it stops at correctness.
