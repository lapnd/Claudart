---
paths: ["**/*"]
description: The harness default that asks every commit message to end with an AI `Co-Authored-By` trailer and a "Generated with" line.
when_to_use: Never loaded. Recorded so that `git-commits` can override this harness default in data rather than only in prose.
tags: [git, commits, authorship]
level: vendor-default
authority: provisional
status: approved
since: 2026-09-06
stale_after: 2027-03-06T00:00:00Z
verified:
  - by: human:lapnd
    at: 2026-09-06T00:00:00Z
enforcer: judgement
load: never
---

# Vendor Default — Harness Co-Author Trailer

This record names a **harness default**; it does not endorse one. The Claude Code harness may
instruct a session to end every commit message with an AI `Co-Authored-By` trailer and a
"Generated with …" line.

This workspace does not follow that default. `.claude/rules/git-commits.md` declares
`overrides: [vendor/harness-coauthor-trailer]`, so the precedence is recorded as data the law
engine can check instead of a sentence buried in prose that nothing validates.

The record is never loaded (`load: never`) and carries no instruction of its own.
