---
slug: evidence-gauntlet
status: done
created: 2026-08-14
updated: 2026-08-18
agent: claude
delegation: none
tags: [testing, evidence, tdd, mutation, verification]
---

# Evidence Gauntlet — `/prove` and the evidence-first proof contract

## Purpose

> "let study this to see if we can utklize for our developement code process https://github.com/AmazingAng/old-coder"

CLAUDART gains the proof half it currently lacks. Today `code-quality.md` §1 mandates ≥95% coverage but nothing defends that number — no red-green ordering, no mutation testing, no prohibition on assertion-free tests, and no requirement that the agent ever run a coverage command. After this change, a `/prove` command and an `evidence-gauntlet` rule supply that discipline, wired into the existing `/plan` and `/spec` layers rather than standing beside them. The user sees it working by running `/prove` on a small change and getting a tier declaration, a recorded red→green transition, a mutation score, and pasted numbers instead of adjectives.

## Context & Orientation

### Related Code

- `.claude/rules/spec-workflow.md` — owns LEDGER evidence anatomy and the event vocabulary. Gains `red-verified`.
- `.claude/rules/code-quality.md` — owns the 95% bar. Gains changed-line coverage as the _gate_ and mutation as the guard.
- `.claude/commands/refactor.md` — 14-line model for a command that drives a rule without duplicating it.
- `.claude/commands/spec.md:77-101` — Refactor Missions overlay; the repo's richest existing evidence protocol (static/dynamic/architectural families). Vocabulary to mirror.
- `.claude/commands/doctor.md:22` — hardcoded required-command list; must gain `prove.md`.
- `install.sh:189-195` — `is_template_path()`; all new paths are already template-owned, so no installer change.
- `tests/spec-workflow/run.sh` — TAP-ish `assert_contains`/`assert_not_contains` harness over both layers. The pattern for the new contract test.

### Related Docs

- `/Users/administrator/.claude/plans/radiant-shimmying-hamming.md` — **the approved plan; read it first.** Carries the adopt/adapt/reject table and the six conflicts.
- https://github.com/AmazingAng/old-coder — upstream source (MIT). `skills/old-coder/SKILL.md`, `references/gauntlet.md`, `references/verifier.md`.

### Memory Hints

- **`.claude/rules/*.md` DO have frontmatter** (`paths:` flow list, `description:`, `when_to_use:`, `tags:` inline array). An early exploration claimed otherwise — verified false against disk on 2026-08-14.
- **There is no `.claude/skills/`.** The Claude layer is `.claude/commands/*.md` with a **single `description:` key** — no `name:`, no `argument-hint:`, no `allowed-tools:`. The Codex twin at `.agents/skills/codex-<name>/SKILL.md` adds `name:`.
- **`npm run check` was dead at HEAD.** Commit `3f46ce9` deleted all 45 files under `tests/`; restored via `git checkout 3f46ce9^ -- tests/`. Both harnesses pass (51 + 65 assertions).
- **`tests/portability/run.sh` has never existed in any commit**, yet `package.json` references it from both `test:portability` and `check:shell`. It belongs to the in-progress task `2026-08-13-001-claudart-portability`. Do not implement its real contract here.
- Six live rule constraints the design must accommodate — see the plan's "Six conflicts" section. The two sharpest: a bounded review patch may **not** add quality gates, and the three review agents are EXPLICIT-REQUEST-ONLY so Tier 3 verification must use a fresh-context `general-purpose` agent instead.
- `code-quality.md`, `code-organization.md`, `git-commits.md` have **no Codex counterpart**. That asymmetry predates this work; do not "fix" it here.

## Plan of Work

Restore the test ground first, because the deliverable is proven by a contract test and that test must be seen failing before the files exist. Then write the contract test RED, build the rule and command in both layers to turn it GREEN, wire the existing rules to consume the new contract, and document.

The rule is the contract; the command is one driver. This avoids a third lifecycle competing with `/plan` and `/spec`.

## Concrete Steps

- [x] (2026-08-14 10:58Z) Step 0 — restore `tests/` from `3f46ce9^` (verify: `npm run test:knowledge && npm run test:spec-workflow` both exit 0 — 51 and 65 assertions passed)
- [x] (2026-08-14 11:12Z) Step 1 — write `tests/evidence-gauntlet/run.sh` pinning load-bearing phrases across all four new surfaces (verify: `/bin/bash tests/evidence-gauntlet/run.sh` → 68 assertions, 67 `not ok`, exit 1 — **RED observed**)
- [x] (2026-08-14 11:20Z) Step 2 — write `.claude/rules/evidence-gauntlet.md` + `.codex/guidelines/evidence-gauntlet.md` (verify: rule assertions flipped to `ok`; 7 wiring assertions still red)
- [x] (2026-08-14 11:26Z) Step 3 — write `.claude/commands/prove.md` + `.agents/skills/codex-prove/SKILL.md` (verify: 61/68 `ok`; command assertions green)
- [x] (2026-08-14 11:33Z) Step 4 — wire `spec-workflow.md` (`red-verified` event), `code-quality.md` (§1 gate, §2 anti-gaming, §19 DoD), `task-management.md` (tier on acceptance items), plus Codex mirrors (verify: `npm run test:spec-workflow` → 65 assertions, exit 0 — no regression)
- [x] (2026-08-14 11:36Z) Step 5 — register in `.claude/CLAUDE.md`, `.codex/AGENTS.md`, `doctor.md:22` required list (verify: `/bin/bash tests/evidence-gauntlet/run.sh` → 68/68 `ok`, exit 0 — **GREEN**)
- [x] (2026-08-14 11:44Z) Step 6 — docs: `README.md`, `README_VI.md`, `docs/GUIDE.md`, `docs/WORKFLOW.md`, `docs/WORKFLOW_VI.md` (verify: `npm run format:md:check` → exit 0)
- [x] (2026-08-14 11:40Z) Step 7 — wrote a real `tests/portability/run.sh` asserting the backup CLI contract that exists today, rather than deleting the reference (verify: `npm run check` → exit 0)

## Validation & Acceptance

- [x] `tests/evidence-gauntlet/run.sh` was observed failing before the rule and command existed, and passing after — RED: 67 `not ok` / 68, exit 1. GREEN: 68/68 `ok`, exit 0.
- [x] `npm run check` exits 0 — 203 `ok` assertions across four harnesses (knowledge-check 51, spec-workflow 65, portability 19, evidence-gauntlet 68)
- [x] `bash .claude/scripts/knowledge-check.sh` exits 0
- [x] `/doctor` run in full: knowledge checker exit 0; all 13 required commands present incl. `prove.md`; every rule carries valid `paths:`/`description:`/`when_to_use:`/`tags:` frontmatter; every rule reachable from `CLAUDE.md`; no `@JOURNAL`/`@HANDOFF` leak; `CLAUDE.md` 51 lines (~1.4k tokens, under the 100-line target). One finding, fixed: `tasks/index.md` did not list this task.
- [x] `git status` shows no modification to `CONTEXT.md`, `JOURNAL.md`, `knowledge/`, `specs/`, or another task's file

### Negative controls (this rule's own requirement)

- `tests/evidence-gauntlet/run.sh` — proven able to fail by the RED run above (67 failures against a tree missing the four files).
- `tests/portability/run.sh` — run against a planted known-bad tree (a backup script that exits 0 on every input, no usage text): 12 `not ok`, exit 1, while the 7 still-true assertions kept passing. The gate fails closed **and** discriminates.

## Decision Log

- **Separate contract harness** (2026-08-14, claude): the new assertions go in `tests/evidence-gauntlet/run.sh`, not appended to `tests/spec-workflow/run.sh`.
  **Rationale**: that file is named for a different contract; `code-organization.md` §1 treats a shared prefix as a module boundary, and the repo already keeps one harness per contract (`knowledge-check`, `spec-workflow`). Only the `red-verified` phrase — which lands _inside_ `spec-workflow.md` — is asserted from the spec-workflow harness. Rejected: appending everything to the spec-workflow harness (approved plan's preview showed this), because it would couple two unrelated contracts to one file.

## Surprises & Discoveries

- (2026-08-14 10:58Z) `npm run check` was already broken at HEAD before this task started — `tests/` deleted by `3f46ce9`, and `test:portability` added pointing at a file that has never existed in any revision.
- (2026-08-14 11:38Z) The first `tests/portability/run.sh` passed 19/19 while printing corrupted labels: bash 3.2 has no `local`, so the assertion helpers' `label` variable clobbered the caller's loop variable and each label accumulated the previous one. A green suite that reports garbage is exactly the failure mode this task exists to catch — fixed by renaming the helper variables to `_label`/`_pattern`/`_expected` and the loop variable to `SCRIPT_LABEL`.
- (2026-08-14 11:50Z) `/doctor` flagged that `tasks/index.md` never listed this task. Fixed. Also note a benign false positive in any naive `grep '^tags:' .claude/rules/*.md` audit: `task-management.md` embeds a task-file template whose placeholder line reads `tags: [1-5 lowercase kebab-case tags]`.

## Outcomes & Retrospective

**Delivered.** CLAUDART now has an evidence-first proof layer, mirrored across both agent layers:

- `.claude/rules/evidence-gauntlet.md` + `.codex/guidelines/evidence-gauntlet.md` — the contract: tier calibration by blast radius, observed-red-before-green, the gauntlet layer table, six absolute anti-gaming rules, fail-closed checkers with negative controls, the manual mutation procedure, and the four independent-verification states.
- `.claude/commands/prove.md` + `.agents/skills/codex-prove/SKILL.md` — the standalone driver for one change, ending in an evidence report.
- Wiring so the contract is not inert: `red-verified` joined the LEDGER event vocabulary in both spec-workflow layers; `code-quality.md` §1 gained changed-line coverage as the gate and mutation as the guard on its 95% bar, §2 gained the anti-gaming prohibitions, §19 gained an evidence line; `task-management.md` Plan Altitude gained the tier hint in both layers.
- `tests/evidence-gauntlet/run.sh` (68 assertions) pins all of it across both layers, and `npm run check` runs it.

**Design choice that shaped everything**: the rule is the contract and the command is one driver of it. A third lifecycle beside `/plan` and `/spec` would have collided with `spec-workflow.md`'s "never run both layers over the same work". Six existing rule constraints were accommodated rather than overridden — the sharpest being that a bounded review patch may not add quality gates (so a tier is selected at planning time and never injected at final review) and that the three review agents are explicit-request-only (so Tier 3 verification dispatches a fresh-context general-purpose agent instead).

**Deliberately not done**: no Codex counterpart was created for `code-quality.md` — that asymmetry predates this work and inventing one would have been scope creep. `tests/portability/run.sh` asserts only the CLI contract that exists today; the bundle format, merge strategy and restore side remain owned by task `2026-08-13-001-claudart-portability`.

**Gap worth naming**: the gauntlet is currently proved on a markdown repo, where the layers that exercised it were phrase-contract tests and shell exit codes. Its coverage/mutation/property layers have not yet been driven against a real application codebase. The first live `/prove` run on such a project is where the ecosystem tooling table gets its first genuine test.
