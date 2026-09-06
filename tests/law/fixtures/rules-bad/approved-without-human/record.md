---
paths: ["**/*"]
description: Bad-case fixture — status approved with no human verifier.
when_to_use: Fixture only; triggers APPROVED-WITHOUT-HUMAN.
tags: [approved-without-human-fixture]
level: law
authority: standard
status: approved
since: 2026-01-01
stale_after: 2030-01-01T00:00:00Z
verified:
  - by: agent:claude
    at: 2026-01-01T00:00:00Z
enforcer: judgement
load: auto
---

# Bad Case — Approved Without Human

`status: approved` but the only `verified` entry has `by: agent:claude`, never a `human:<id>`
entry. Expected finding: `APPROVED-WITHOUT-HUMAN`.
