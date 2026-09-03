---
description: Create a cross-runtime port mission — pin the source baseline, decompose a UI-fused source, freeze the target API seam and translation rules, then hand the mission to /spec-run for autonomous session-by-session execution.
---

The user's request after `/migrate` is a port mission across a language, runtime, or UI-framework boundary ("migrate this NiceGUI app to Go + Vue", "port the Python worker to Go", "replace Streamlit with a real SPA"). If empty, ask: "What is being ported, from what stack to what stack?"

This command is an entry point, not a separate protocol. Before anything, read `.claude/rules/stack-migration.md` — it is the binding contract for port missions and this command does not duplicate it. Then run the `/spec` flow (read `.claude/commands/spec.md` and `.claude/rules/spec-workflow.md`) with **both** the Refactor Missions overlay and the stack-migration rule active from the start.

## What this adds on top of `/refactor`

`/refactor` proves equivalence inside one codebase with one build. A port has a source stack and a target stack, so equivalence cannot be diffed in-process — it is proved by running both and comparing observable output. Use `/refactor` when the language and runtime stay put; use `/migrate` when they do not.

## Procedure

1. **Follow `/spec` Steps 1-6 exactly** — same dated folder in `.claude/specs/`, same drafting lock, same SPEC/ROADMAP/NOTES/LEDGER, same standing approval, same `/spec-run` execution.

2. **Interview for the three decisions the source cannot answer** (Step 2), and write each into `SPEC.md` as it lands:
   - **Target shape** — one service or split backend/SPA; which frameworks; where the seam sits.
   - **Cutover shape** — big-bang, strangler-fig, or parallel-run, and what triggers it (rule §8). Ask this at spec time; discovering it at the final gate reopens the roadmap.
   - **Scope of the source** — what is ported, what is dropped (straight into Must-NOT-Have), and what stays on the source stack indefinitely.

3. **Build the spec-time artifacts** (rule §2) during Steps 2-4, from the pinned source baseline and never from a half-ported target:
   - `artifacts/behavior-contract.md` — Refactor Missions, unchanged.
   - `artifacts/translation-rules.md` — this project's idiom table. Seed it from the reference skills (`.claude/skills/python-to-go-idioms/`, `.claude/skills/nicegui-to-vue/`), then **replace every generic example with a real one from this codebase**. A row nobody grounded in this source is a row a later session will interpret differently.
   - `artifacts/module-inventory.md` — source file → target package/component, dependency order, risk tag. It feeds the ROADMAP; it never becomes a second checklist.
   - `artifacts/api-contract/` — the frozen seam (rule §4), written before any target code is planned.
   - Run the phantom-feature sweep (rule §3) here, not later: every dead reference in the source ends up deleted-and-re-pinned or in Must-NOT-Have.

4. **POC fidelity**: for a port, the frozen reference is usually the behavior contract, the API contract, and the pinned baseline itself. When the mission changes the UI stack, the user is also choosing how the new UI should look and feel — offer a narrow visual artifact for the screens that change, and default to contract-as-artifact for everything the port is supposed to leave alone.

5. **Roadmap the units, not the files** (Step 5). One task ports one translation unit (rule §1, L2) and leaves both stacks buildable and green. Phase 1 ends with a running smoke path through the target (rule §7) — a port whose first end-to-end run happens in the last phase has no early evidence. Give every phase validation an executable architectural check and a differential run; write the dead-code and stale-reference sweeps in as phase validations, not as final-gate cleanup.

6. **Tier-annotate every task** per `/spec` Step 5 and rule §10 — a port's distribution is lopsided (most units are `standard`, sweeps and mechanical value objects are `fast`, and callback decomposition, concurrency, seam design, schema/data migration and auth are `strong`). Set `executor-tier:` to the cheapest tier that covers the roadmap so the loop runs cheap and escalates by rotation.
7. **Carry the rule into the ROADMAP**, because the executor reads the roadmap, not this command: per-task `verify:` lines in the parity vocabulary (differential run, contract diff, architecture command), the Definition of Done additions from rule §8, and a NOTES entry recording how to boot both stacks side by side.

## Handoff

On approval the user runs `/spec-run <slug>` from a fresh session and rotates at phase boundaries — that loop is the migration loop, and it resumes from the spec folder after any interruption. The executor needs no port-specific knowledge beyond what SPEC, ROADMAP, NOTES, and the artifacts carry; if it would, that is a defect in the spec, not something to explain in chat.

If the request is really a single module with no framework boundary crossed, say so and suggest `/plan` plus the relevant reference skill instead.
