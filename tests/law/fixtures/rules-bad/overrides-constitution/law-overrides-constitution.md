---
paths: ["**/*"]
description: Bad-case fixture — a law record whose overrides illegally targets a constitution record.
when_to_use: Fixture only; triggers OVERRIDES-CONSTITUTION.
tags: [overrides-constitution-target-fixture]
level: law
authority: standard
status: approved
since: 2026-01-01
stale_after: 2030-01-01T00:00:00Z
verified:
  - by: human:fixture
    at: 2026-01-01T00:00:00Z
enforcer: judgement
overrides: [constitution]
load: auto
---

# Bad Case — Overrides Constitution

`overrides: [constitution]` names `constitution.md`, whose `level` is `constitution`. Expected
finding: `OVERRIDES-CONSTITUTION`.
