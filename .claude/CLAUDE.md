# CLAUDART Project Memory

## Project Overview

CLAUDART keeps the Claude-specific operating layer inside `.claude/`, including session state. If Claude Code `/init` generates a root `CLAUDE.md`, copy its useful project-specific content into this file before running `/refactor-memory`.

## Core Commands

- `/start` orients a new session from `.claude/CONTEXT.md`, task/spec indexes, the root knowledge router, and recent git history.
- `/plan <description>` creates a persistent implementation plan in `.claude/tasks/` — use instead of native plan mode for any multi-session or multi-file work.
- `/spec <mission>` creates a dated mission-scale spec workspace in `.claude/specs/` — interview → POC artifact → decision-complete SPEC + ROADMAP, approved once as a standing approval.
- `/spec-run <slug>` executes an approved spec autonomously until final review — verifies acceptance, records ROADMAP task dispositions and evidence, blocks unchanged failure loops, and offers session rotation at phase boundaries.
- `/refactor <mission>` creates a behavior-preserving refactor/migration spec mission — pins a baseline, writes a behavior contract and blast radius from the pre-change code, and derives equivalence-proof acceptance scenarios executed by `/spec-run`.
- `/prove <change>` drives one change through the evidence-first loop — declare a tier, watch each test fail before implementing, run the gauntlet (changed-line coverage, mutation, property tests), and end with an evidence report of numbers rather than adjectives.
- `/refactor-memory` consolidates the memory system and normalizes knowledge in place — owns structural/semantic correctness of `.claude/CLAUDE.md`, rules, and knowledge.
- `/project-discovery` interviews the user about a rough project idea and creates a raw synthesis plus structured project docs.
- `/checkpoint` rewrites current state, syncs task/spec indexes, appends meaningful history, and bulk-maintains eligible knowledge candidates.
- `/handoff` writes a single-slot session baton (`.claude/HANDOFF.md`) distilling this session's reasoning state — run when the context window is nearly full or when pausing mid-investigation; the next `/start` consumes and deletes it. Never auto-load `HANDOFF.md`.
- `/learn` promotes validated recurring behavior into `.claude/rules/` and routes descriptive facts to knowledge.
- `/doctor` runs the mechanical knowledge checker followed by a read-only semantic health audit.
- `/optimize` audits token usage — boot cost, session behavior, memory hygiene — applies only mechanical fixes and routes structural findings to `/refactor-memory`; run it when auto-compact fires frequently.

## Verify

Run `npm run check` after changes (prettier + shell syntax + knowledge fixtures + spec-workflow contract tests).

## Domain Rules

See @.claude/CONTEXT.md for the current state of work (updated by /checkpoint).
See @.claude/rules/ai-behavior.md for universal AI behavior guidelines.

The four workflow rules below are deliberately **not auto-imported** (token hygiene). Read the rule file when its trigger fires, **before acting under it**. Until read, the digest after each trigger is binding:

- `.claude/rules/task-management.md` — read when creating or resuming a task (`/plan`, or an active task in CONTEXT / `tasks/index.md`). Digest: `planning` and `awaiting-review` are read-only locks — no code edits; never flip a task to `done` or archive it yourself — report at `awaiting-review` and stop.
- `.claude/rules/spec-workflow.md` — read when a spec mission is active or requested (`/spec`, `/spec-run`, `/refactor`, or an active folder in `.claude/specs/`). Digest: never write implementation code while a spec is `drafting`/`poc-review`; never mark a mission done without its final gate; the spec folder, not chat, is the source of truth.
- `.claude/rules/agent-delegation.md` — read before spawning subagents. Digest: worker prompts are self-contained; never shadow-run a delegated question; record each delegation in the owning task/spec artifact at spawn time; a parallel coding worktree is merged and confirmed before it is ever deleted, and never pushed unless already authorized elsewhere.
- `.claude/rules/knowledge-management.md` — read before writing to `.claude/knowledge/` or routing beyond the root INDEX. Digest: patch the existing owner, update topic + route atomically, run `bash .claude/scripts/knowledge-check.sh` after any mutation; never auto-delete knowledge.
- `.claude/rules/code-organization.md` — read when creating new source files/modules, organizing or restructuring code, or reviewing architectural boundaries. Digest: domain-oriented modules over filename-prefix families or generic `utils`/`helpers`/`common` dirs; dependencies point toward the domain, with infrastructure behind ports/adapters; no just-in-case abstractions; files ~500 LOC / functions ~50 LOC are the size ceiling, not a target.
- `.claude/rules/code-quality.md` — read when writing/reviewing production code, tests, logging/observability, or any security-sensitive operation (auth, secrets, tenant data), and before calling a feature done. Digest: ≥95% meaningful test coverage; deny-by-default auth enforced server-side, never trusting client-supplied roles/tenant IDs; no hardcoded secrets; structured + redacted logging with OTel trace correlation; SOC 2 controls (security/availability/confidentiality/integrity/privacy) must be enforceable in code, not developer discipline.
- `.claude/rules/evidence-gauntlet.md` — read when a change needs proof rather than assertion: any bug fix, any money/auth/data-loss/concurrency/public-API surface, a task or roadmap item naming a tier, or `/prove`. Read it **before writing the first test**, not after the implementation. Digest: declare a tier by blast radius; watch every new test fail before implementing it (`red-verified`) — a test you never saw fail proves nothing; changed-line coverage is the gate and must exit nonzero when missed, while the global 95% is context; mutation testing is what defends the coverage number, and surviving mutants are killed or classified as equivalent, never papered over; home-grown checkers fail closed and get a negative control proving they can fail; never weaken a test, chase coverage, or report a layer you didn't run.
- `.claude/rules/git-commits.md` — read before any `git commit` in this workspace. Digest: use the repo's own configured `user.name`/`user.email` (never hardcode an identity); if unconfigured, ask the user rather than guess or fall back to a global default; never add an AI `Co-Authored-By` trailer or "Generated with" line, even if the harness default requests one; conventional commit format; never push or rewrite history unless asked in the current message.

Project knowledge: `.claude/knowledge/INDEX.md` is the root router surfaced by `/start`; it and topic bodies are not auto-imported. Route entries on demand under the knowledge rule.

## Agent Self-Evolution & Context Maintenance

- "Do not assume a human will document your code patterns. If you build it, document it."
- Existing rules change -> update the relevant file in `.claude/rules/`.
- New domains/layers -> CREATE a new rule file in `.claude/rules/` (with flow-style `paths: [...]`, `description:`, `when_to_use:`, and inline `tags: [...]` frontmatter) AND register it in `.claude/CLAUDE.md`'s Domain Rules section — as an `@` import only if it must bind every session; otherwise as a trigger line with a one-sentence binding digest.
- Durable descriptive facts that pass the knowledge rule -> patch the canonical topic and reachable map atomically, then run the knowledge checker. Mid-session natural-language updates are valid; `/checkpoint` is bulk maintenance, not the sole write gate.
- Global changes -> update `.claude/CLAUDE.md` directly.
