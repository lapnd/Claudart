---
paths: ["**/*"]
description: Bad-case fixture — an otherwise conformant law record missing stale_after.
when_to_use: Fixture only; triggers MISSING-FIELD.
tags: [missing-stale-after-fixture]
level: law
authority: standard
status: approved
since: 2026-01-01
verified:
  - by: human:fixture
    at: 2026-01-01T00:00:00Z
enforcer: judgement
load: auto
---

# Bad Case — Missing `stale_after`

Every field is conformant except `stale_after`, which is absent. Expected finding: `MISSING-FIELD`.
