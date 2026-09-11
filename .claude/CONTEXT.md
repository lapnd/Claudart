<!-- .claude/CONTEXT.md — current state of work. Updated by /checkpoint. Declarative, not a log. -->

## In Progress

- Running spec `governed-intelligence-poc` (see .claude/specs/2026-09-06-governed-intelligence-poc/SPEC.md) — status `running`, `executor-tier: strong`, `commits: user`, deadline 2026-09-08. **Phase 1 is complete and phase-validated (S1 ticked)**; Phases 2–4 remain. Recount progress from ROADMAP checkboxes and `claudart-graph status`, never from this file. <!-- since: 2026-09-06 -->
- Research deliverable `docs/research/2026-09-06-governed-personal-intelligence/` is complete and is the spec's read-only input; artifact https://claude.ai/code/artifact/f88e5863-d968-40d9-86cb-be4c9e61410e. <!-- since: 2026-09-06 -->

## Open Questions / Blockers

- **Phase 1 is staged but UNCOMMITTED and needs the user's commit.** `commits: user` plus the council's "Phase 1 lands as one commit" means the executor cannot commit it. Until then the worker branch `worktree-agent-a8b37e771cfe56502` (`50ecc94`, worktree under `.claude/worktrees/`) is Phase 1's only restore point — **do not delete it before the commit**. Starting Phase 2/3 work first would mix phases into one tree and destroy the clean single commit. <!-- since: 2026-09-06 -->
- **P3.3 is half-landed and currently regresses `npm run test:portability` (17 failures).** `cb1d053` shipped the migrated _reader_ (`knowledge-check.sh` + `.codex` twin, green) but not the _writers_: `claudart-restore.sh` still emits `review-needed` topics and an `INDEX.md` router, its own shadow checker gate then rejects them, restore exits 1, and 16 assertions cascade. Measured, not assumed — baseline `f4c5f7c` is rc 0 / 103-of-103; the earlier "pre-existing" reading came from baselining against `cb1d053`, which already contained the defect. Fix = P3.3 + P3.4 landing together. <!-- since: 2026-09-06 -->
- **`.claude/knowledge/` is mid-migration and its checker rejects it** (`bash .claude/scripts/knowledge-check.sh` → exit 1: K114 declared-empty lists, K200 route grammar, the `INDEX.md` case clash). **No knowledge topic may be written until P3.4 lands**, because the knowledge rule's mandatory post-mutation check cannot come back clean. <!-- since: 2026-09-06 -->
- **`rotation: auto` is non-functional here.** `claudart-rotate.sh` launches the successor with `--permission-mode acceptEdits` plus a scoped `--allowedTools`, neither of which grants writes under `.claude/specs/`; the 15:37Z successor oriented correctly, was refused on `LEDGER.md`, and advanced nothing. Treat rotation as `offer` and ask the user. <!-- since: 2026-09-06 -->
- DEFECT (open): `cli.py` runs the retirement stage even after schema findings, so a record lacking `since` exits 2 (`unexpected error: 'since'`) instead of reporting `MISSING-FIELD` at exit 1. **No longer reproduces on the live rules dir** (every record now carries `since`); the fix needs its own `rules-bad/missing-since` fixture and a red test first. <!-- since: 2026-09-06 -->
- `QUEUE-STALE` anchoring: D6 says "past its expiry", `cli.py` anchors on `created`. The fixture was aged so no test depends on the answer, but the implementation still embodies one reading — settle at final review. <!-- since: 2026-09-06 -->
- Real downstream repository for the second pilot (the spec uses a fresh `install.sh` scaffold; the real one is the user's choice after the mission). <!-- since: 2026-09-06 -->
- `budget.yaml` defaults (4 reviewer-hours / 4 proposals per month) are placeholders the user may edit at any time. <!-- since: 2026-09-06 -->

## Recent Decisions (not yet promoted to rules)

- Commit policy stays `commits: user`; mission work lives on branch `feature/governed-intelligence-poc`, never pushed. <!-- since: 2026-09-06 -->
- `constitution-check.sh` check 2 now scans the constitution's **prose body only** — its own law frontmatter is mandated metadata that every law record repeats, so whole-file shingling produced guaranteed false positives. Rule files are still scanned in full; proven with a control pair (clean → rc 0; constitution prose appended → rc 1; that prose pasted into a rule's `description:` → rc 1). Do not revert to whole-file scanning. <!-- since: 2026-09-06 -->
- User: AGPL/GPL acceptable for internal tooling (this is a build tool, not shipped code); conversation in Vietnamese, repo docs English + `_VI` twin. <!-- since: 2026-09-06 -->

## Next Session Should Start By

- Commit Phase 1 (the user's action), then `/spec-run governed-intelligence-poc`. Next unit is **P3.3 + P3.4 landing together**: migrate the writers (`claudart-{restore,backup}.sh` + both `.codex` twins, `tests/portability/run.sh`, the `INDEX.md` literals in `tests/{graph,install-live-state,knowledge-check}/run.sh`), then the real `.claude/knowledge` + `.codex/knowledge` bundles and the doc/skill sweep. Do **not** fire an auto-rotation. Hold `test/law-suite-fold` until Phase 2 — `fold.sh` sorts before `repo.sh`/`schema.sh` in the aggregate runner and would redden `npm run test:law`. <!-- since: 2026-09-06 -->
