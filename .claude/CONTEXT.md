<!--
.claude/CONTEXT.md — current state of work in this repo.

Maintained by /checkpoint. This file is declarative: it describes what is true RIGHT NOW.
Old work is removed, not archived. Permanent decisions graduate to .claude/rules/ via /learn.
History lives in git log + .claude/JOURNAL.md (the latter is NOT loaded into Claude sessions).

Hard ceiling: 150 lines. Target: under 100.

DO NOT track git commit status here. The user commits independently.
Never mention "uncommitted changes" or reference git status — it will be stale immediately.
-->

## In Progress

- Running spec `governed-intelligence-poc` (see .claude/specs/2026-09-06-governed-intelligence-poc/SPEC.md) — status `running`; `executor-tier: strong`, `commits: user`, `rotation: auto`, deadline 2026-09-08. Graph `nodes 38 done 13 | tests green 6/10 | lint clean`. Next task: **P1.7 `contract/rules-frontmatter`** (its red is on disk: `bash tests/law/repo.sh` -> 1 passed, 10 failed). Recount progress from ROADMAP checkboxes, never from this line. <!-- since: 2026-09-06 -->
- Research deliverable `docs/research/2026-09-06-governed-personal-intelligence/` (README, README_VI, landscape, poc, council-review, conflict-count) is complete and is the spec's read-only input; artifact https://claude.ai/code/artifact/f88e5863-d968-40d9-86cb-be4c9e61410e. <!-- since: 2026-09-06 -->

## Open Questions / Blockers

- **`commits:` policy — awaiting the user.** `commits: user` makes `isolation: worktree` unusable for any node with an INPUT (completed work is squash-merged but uncommitted, so a worktree branched from `main` cannot see it). Recommendation: `per-phase`, worked on a branch per `git-commits.md`, never pushed. SPEC Open Questions already pre-authorised this alternative. <!-- since: 2026-09-06 -->
- `QUEUE-STALE` anchoring: D6 says "past its expiry", `cli.py` anchors on `created`. The fixture was aged so no test depends on the answer, but the implementation embodies one reading. <!-- since: 2026-09-06 -->
- DEFECT (open): `validate` exits 2 with `unexpected error: 'since'` instead of reporting `MISSING-FIELD` at exit 1 when a record lacks `since`. Reproduce: `bash .claude/scripts/claudart-law.sh validate --rules .claude/rules --budget .claude/budget.yaml`. <!-- since: 2026-09-06 -->
- Real downstream repository for the second pilot (the spec uses a fresh `install.sh` scaffold; the real one is the user's choice after the mission). <!-- since: 2026-09-06 -->
- `budget.yaml` defaults (4 reviewer-hours / 4 proposals per month) and commit policy (`user` vs `per-phase`) — confirm or change before "go". <!-- since: 2026-09-06 -->

## Recent Decisions (not yet promoted to rules)

- Laws are the existing `.claude/rules/*.md` with added frontmatter; precedence is compile-time declaration lint (`overrides:` etc.), no runtime resolver — evidence in `conflict-count.md`. <!-- since: 2026-09-06 -->
- Retirement is fail-soft tiered by `authority` (`core` never below block); `validate` never writes, `tally` owns every write. <!-- since: 2026-09-06 -->
- Knowledge layer adopts OKF v0.2 vocabulary served by okf-agent-memory pinned at `c05ce5d`, built from source under `.claude/scripts/bin/` (gitignored); MCP over `.claude/knowledge/` only. <!-- since: 2026-09-06 -->
- User: AGPL/GPL are acceptable for internal tooling (this is a build tool, not shipped code); conversation in Vietnamese, repo docs English + `_VI` twin. <!-- since: 2026-09-06 -->

## Next Session Should Start By

- Open a fresh strong session → `/start` → `/spec-run governed-intelligence-poc`. <!-- since: 2026-09-06 -->
