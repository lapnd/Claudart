---
paths: ["src/**/*.go"]
description: Bad-case fixture — second of two records with overlapping paths and a shared tag.
when_to_use: Fixture only; triggers UNDECLARED-OVERLAP.
tags: [fixture, undeclared-overlap-fixture]
level: law
authority: standard
status: approved
since: 2026-01-01
stale_after: 2030-01-01T00:00:00Z
verified:
  - by: human:fixture
    at: 2026-01-01T00:00:00Z
enforcer: judgement
load: auto
---

# Bad Case — Undeclared Overlap (record B)

Overlaps `record-a.md`'s `paths` glob and shares the `undeclared-overlap-fixture` tag. Neither
record declares `overrides`/`supersedes_in_scope`/`layers_on` toward the other. Expected finding:
`UNDECLARED-OVERLAP`.
