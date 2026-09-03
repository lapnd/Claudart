# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Releases after 1.0.0 have not been tagged yet; milestone dates below refer to the
commits that landed them on `main`.

## [Unreleased] — 2026-08-11

### Added

- **`/migrate` command and `stack-migration.md` rule**: cross-runtime port missions (Python→Go, NiceGUI→Vue, any language/runtime/UI-framework change) layer onto the Refactor Missions overlay — one translation unit per task fed the source code rather than a prose retelling, a frozen API seam and a project-specific `translation-rules.md` written before any target code, UI-fused callbacks decomposed into domain/transport/view with every implicit server-held state given an explicit destination, and parity proved by differential runs against the running baseline plus a Phase-1 smoke path, early data-migration rehearsal, and per-phase dead-code sweeps. Ships with `.claude/skills/` reference skills (`python-to-go-idioms`, `nicegui-to-vue`) — now a template-owned path in the installer and backup engines — an end-to-end user guide in `docs/MIGRATE.md` / `docs/MIGRATE_VI.md` built around a real NiceGUI codebase, and three constraints the rule makes binding: fidelity is owed to behavior rather than structure (take the better target-native data structure, concurrency shape, or library instead of transliterating), no GPL/AGPL in the shipped dependency graph enforced by a license gate in phase validation, and a port-specific tier distribution so the loop runs cheap and escalates by rotation.
- **`/refactor` command** (`$codex-refactor`) and a **Refactor Missions** overlay in `/spec`: behavior-preserving refactors and migrations pin a baseline commit, build a behavior contract and blast radius from the pre-change code, and prove equivalence through differential worktree runs, deletion audits, and stale-reference sweeps across static/dynamic/architectural evidence.
- **`/optimize` command** (`$codex-optimize`): read-only token-usage audit for when auto-compact fires frequently — boot cost vs a ~3k budget (including parent/global instruction files and MCP schemas), a session-behavior walk (repeated reads, inline output floods, oversized fan-out), and memory-hygiene sizing — with ranked fixes routed to apply-now / `/checkpoint` / `/learn` / user.
- **Model & effort routing**: abstract fast/standard/strong/frontier tiers in `agent-delegation.md`; `/spec` and `/plan` tier-annotate tasks; SPEC frontmatter records `executor-tier:`; `/spec-run` surfaces it, logs the session tier, and treats a second failed validation below the strong tier as an escalation signal; `/learn` gains a routing retrospective.
- **AI-ROS discipline absorbed into the rules**: stop conditions and honest reporting ("a truthful blocked is always acceptable; a false done is the single worst violation"), a pre-done self-critique, LEDGER evidence-entry anatomy ("no evidence line, no tick"), crash-recovery quadrants ("re-verify rather than re-do, re-do rather than assume done"), and an independent review-dispatch contract with verdict freshness (later changes void the verdict) and bounded adversarial rounds.
- **`--upgrade` installer mode**: refreshes template-owned files in place, never touches live state (CONTEXT, JOURNAL, tasks, specs, knowledge) or user-evolved indexes; warns on a dirty git tree; reports copied/upgraded/unchanged/skipped.
- **`--council` installer flag**: optionally installs the [Council of High Intelligence](https://github.com/0xNyk/council-of-high-intelligence) `/council` deliberation companion to user scope, layer-matched.
- **`docs/GUIDE.md`**: flow-ordered user cookbook — setup once, every session, executing by size, while working, closing the loop — with concrete walkthroughs for every command.
- **Portability — `/backup` + `/restore`** (`$codex-backup` / `$codex-restore`): export a portable CLAUDART bundle (the project `.claude/` layer plus this project's Claude Code sessions, memory, and history) behind an allow-list collection, a length-constrained secret-scan gate, and six-encoding path-token cataloguing; restore translates every token via boundary-anchored sentinel substitution proven by independent occurrence arithmetic, then merges structurally — regenerating declared caches, line-unioning curated routers, sidecaring keyed-unit collisions — under a never-overwrite invariant with pre-write backups, `receipt.txt`, conflict parking, and a shadow `knowledge-check.sh` gate. Both engines ship as byte-identical Codex twins covered by a synthetic-fixture suite.

### Changed

- **Always-on session context cut ~90%** (≈22k → ≈2.2k tokens): `CLAUDE.md` now `@`-imports only CONTEXT and ai-behavior; the four workflow rules load on trigger lines with binding one-line digests; `AGENTS.md` mirrors the digests; `/start` reuses the imported CONTEXT copy and fires rule triggers at boot; human docs carry agent-skip markers.
- `clean-code-reviewer` moved to the standard tier (`model: sonnet`); `security-auditor` stays strong-tier.
- Installer defaults now select both layers, the council companion, upgrade, and force.

### Fixed

- Reinstalls no longer leave a duplicate `.codex/AGENTS.md` beside the canonical root copy.

### Removed

- The imported `ai/` (AI-ROS) directory — its generic mechanisms were absorbed into the rules and commands above; its project overlay belonged to another repository.

### Tests

- 18 new prose-contract assertions guard the evidence anatomy, recovery classification, tier vocabulary, and baseline-anchored refactor contract across both layers.

## Untagged milestones — after 1.0.0

- **2026-07-30** — Project knowledge system: `.claude/knowledge/` with bounded frontmatter grammar, map-first routing, lifecycle states, and a dependency-free Bash checker shipped byte-identical in both layers with fixture tests; scoped final-gate revalidation (full-baseline / scoped-review cumulative gates).
- **2026-07-26** — Codex agents updated to `gpt-5.6-sol` with tuned reasoning effort.
- **2026-07-23** — All three review agents gated to explicit-request-only.
- **2026-07-06 → 07-08** — Spec workflow: mission-scale dated folders (SPEC/ROADMAP/NOTES/LEDGER), standing approval, convergence rules and circuit breakers, session rotation, `done/` archives.
- **2026-06-11** — `/handoff` single-slot session baton consumed by the next `/start`.
- **2026-05-03** — `/project-discovery` interview-first workflow for both layers.

## [1.0.0] - 2026-04-28

### Added

- Initial public release of the **CLAUDART** foundation template.
- Core AI workflows mapped into `.claude/commands` (`/refactor-memory`, `/learn`, `/checkpoint`, `/doctor`, `/sync`) and Codex-native `.codex/commands` plus `.agents/skills`.
- Initial structural support for `.claude/agents`.
- Shared `.claudart/` memory core, Codex-native template layer, and downstream Claude/Codex sync contract.
- Documentation foundation: `README.md`, `CONTRIBUTING.md`, and `LICENSE`.
