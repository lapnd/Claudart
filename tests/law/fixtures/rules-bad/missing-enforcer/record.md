---
paths: ["**/*"]
description: Bad-case fixture — an otherwise conformant law record missing enforcer.
when_to_use: Fixture only; triggers MISSING-FIELD.
tags: [missing-enforcer-fixture]
level: law
authority: standard
status: approved
since: 2026-01-01
stale_after: 2030-01-01T00:00:00Z
verified:
  - by: human:fixture
    at: 2026-01-01T00:00:00Z
load: auto
---

# Bad Case — Missing `enforcer`

Every field is conformant except `enforcer`, which is absent. Expected finding: `MISSING-FIELD`.
