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

- Working task `claudart-portability` (see .claude/tasks/2026-08-13-001-claudart-portability.md) — Steps 1-6 done and tested (`claudart-restore.sh` is functionally complete: Plan, Materialize, all 8 merge classes, shadow knowledge-check.sh gate, Commit with backups/receipt/ledger; `/backup`+`/restore` commands and Codex skill mirrors created; 98 assertions in tests/portability/run.sh). Remaining: Step 7 (docs — README/GUIDE/WORKFLOW/INTEGRATE/CHANGELOG/CLAUDE.md/CONTRIBUTING/doctor.md required-list) — see the task's "Step 7 surface map" and Memory Hints.
