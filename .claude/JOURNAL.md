# Claude Session Journal

Append-only audit log. Format: YYYY-MM-DD | <type> | <one-line summary>
Types: decision, completed, pivot, blocker-resolved

Never full-read this file in a session. Use tail/grep for pattern analysis.
NEVER import this file into session context (@.claude/JOURNAL.md must not appear in CLAUDE.md or rules).

---

2026-08-18 | completed | parallel-worktree-execution — added disjointness test + Worktree Lifecycle for Parallel Coding Work to agent-delegation.md, wired into spec-workflow/spec/spec-run/task-management (+ .codex mirrors), see tasks/done/2026-08-18-001-parallel-worktree-execution.md
2026-08-18 | completed | evidence-gauntlet — added evidence-gauntlet.md rule + /prove command (RED/GREEN/mutation/tiered proof), wired into spec-workflow/code-quality/task-management (+ .codex mirrors), see tasks/done/2026-08-14-001-evidence-gauntlet.md
2026-08-18 | completed | install.sh no longer ships CLAUDART's own dogfooded live state (CONTEXT/JOURNAL/tasks/specs/knowledge) into a fresh install — added is_live_state_path(), wired into copy_tree, tests/install-live-state/run.sh (red-verified vs pre-fix HEAD), wired into npm run check
2026-08-22 | completed | claudart-portability — /backup + /restore shipped end to end (export/import engines + byte-identical Codex twins + commands/skills + 98-assertion suite) and every doc surface landed (README/\_VI, GUIDE Part 6, WORKFLOW/\_VI, INTEGRATE, CHANGELOG, CONTRIBUTING, CLAUDE.md, doctor lists), see tasks/done/2026-08-13-001-claudart-portability.md
2026-08-22 | completed | output-limit-resilience — context-guard PostToolUse hook (WARN ≥8MB / ACT ≥16MB transcript bytes, fail-visible) + committed settings.json wiring (autocompact 70%, bash output 30K) + 28-assert suite + 6/6 mutants + portability + rules/mirrors + GUIDE runbook; final gauntlet all exit 0, see tasks/done/2026-08-22-001-output-limit-resilience.md
2026-09-06 | completed | graph-driven-development — executable architecture graph + Constitution + brownfield audit + autonomous rotation/watchdog; 41/41 nodes, npm check green; landed main f0c1110
2026-09-06 | completed | research governed-personal-intelligence — 16-deliverable report (README/\_VI, landscape matrix, poc H1–H7, 7-member council review, conflict count), see docs/research/2026-09-06-governed-personal-intelligence/
2026-09-06 | decision | Laws = existing .claude/rules with frontmatter; precedence is compile-time declaration lint, no runtime resolver (all 6 historical collisions were authoring-time, conflict-count.md)
2026-09-06 | decision | Retirement fail-soft tiered by authority (core never below block); retirement + reviewer budget ship in one commit (council dealbreaker)
2026-09-06 | decision | Knowledge layer adopts OKF v0.2 + okf-agent-memory pinned c05ce5d (MIT), built from source, MCP over knowledge/ only
2026-09-06 | pivot | POC evaluation compressed from four weeks to a two-day autonomous run (deadline 2026-09-08) using the repo's historical correction corpus (SPEC D17)
2026-09-06 | decision | Commit policy stays `commits: user`; user authorised one mid-Phase-1 restore point instead of switching to per-phase — mission work on branch feature/governed-intelligence-poc, commit cb1d053, never pushed
2026-09-06 | decision | rotation: auto is non-functional in this environment — claudart-rotate.sh's successor cannot write .claude/specs/ (sensitive-file refusal), so it consumed a session and advanced nothing; treat rotation as offer until the permission grant is fixed
2026-09-06 | completed | spec governed-intelligence-poc Phase 1 — 16 rule files + 2 vendor records migrated to law frontmatter, budget.yaml/.template added, test:law wired into npm check; phase validation green and S1 ticked (all 7 negative controls observed exiting 1 with their named code); staged uncommitted under commits: user
2026-09-06 | decision | constitution-check.sh check 2 now scans the constitution's prose body only — its own law frontmatter is mandated metadata every record repeats, so whole-file shingling was a guaranteed false positive; rule files still scanned in full, verified with a control pair
2026-09-06 | decision | The 17 portability failures are a regression from the half-landed P3.3 checker migration, NOT pre-existing — baseline f4c5f7c is rc 0 with 103/103 green; the "pre-existing" call had baselined against cb1d053, which already contained the defect
