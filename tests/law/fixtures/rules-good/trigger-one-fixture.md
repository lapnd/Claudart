---
paths: ["**/*"]
description: Fixture law record loaded as a trigger line, first of a pair.
when_to_use: Fixture only; never loaded by a real project.
tags: [trigger-one-fixture]
level: law
authority: standard
status: approved
since: 2026-01-01
stale_after: 2030-01-01T00:00:00Z
verified:
  - by: human:fixture
    at: 2026-01-01T00:00:00Z
enforcer: judgement
load: trigger
order: 50
trigger: "read when the trigger-one fixture condition fires."
digest: "fixture digest line for trigger-one-fixture — carries no real instruction."
---

# Fixture Trigger Record One

A minimal conformant `load: trigger` record used by `tests/law/fixtures/rules-good/`.
