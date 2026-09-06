---
paths: ["**/*"]
description: Bad-case fixture — a convention record whose overrides illegally targets a law.
when_to_use: Fixture only; triggers BAD-LAYER.
tags: [convention-overrides-law-fixture]
level: convention
authority: standard
status: approved
since: 2026-01-01
stale_after: 2030-01-01T00:00:00Z
verified:
  - by: human:fixture
    at: 2026-01-01T00:00:00Z
enforcer: judgement
overrides: [law]
load: auto
---

# Bad Case — Convention Overrides Law

A `level: convention` record may only `layers_on` a `level: law` record. This record instead uses
`overrides: [law]`. Expected finding: `BAD-LAYER`.
