---
created: 2026-06-01
expires: 2026-07-01
candidate_law: git-commits
lessons:
  - lesson-2026-07-10-ai-coauthor-trailer
  - lesson-2026-07-18-branch-not-main
---

# Proposal — git-commits

An open reviewer-queue proposal, fixed at `created: 2026-06-01` / `expires: 2026-07-01` — both well
past `queue_max_age_days: 30` relative to the fixture "today" of `2026-09-06`. Used as the
`QUEUE-STALE` negative control: `validate` must fail with exit 1 when this directory is the open
proposal queue.

## Lesson summaries

- Two sessions independently proposed banning the AI `Co-Authored-By` trailer after the harness
  default kept reinserting it.
- One session proposed codifying "branch, don't commit implementation to `main`" after observing
  four direct-to-`main` implementation commits in one day.
