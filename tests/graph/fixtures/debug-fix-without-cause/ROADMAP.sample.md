# ROADMAP — Intermittent 500 on GET /users (debug profile)

## Phase 1 — Reproduce before anything

- [ ] P1.0 Deterministic reproduction under load (verify: sh scripts/repro-500.sh)
      node: repro/users-500 | kind: repro
      paths: scripts/repro-500.sh, test/repro/\*\*

## Phase 2 — Hypotheses, cheapest discriminator first

- [ ] P2.0 H1: connection pool exhausted under concurrency (verify: sh scripts/check-pool.sh)
      node: hypothesis/pool-exhausted | kind: hypothesis
      requires: repro/users-500 (TEST)
      paths: scripts/check-pool.sh
- [ ] P2.1 H1a: pool size < concurrent requests (verify: sh scripts/check-pool-size.sh)
      node: hypothesis/pool-too-small | kind: hypothesis
      requires: hypothesis/pool-exhausted (EVIDENCE)
      paths: scripts/check-pool-size.sh
- [ ] P2.2 H1b: connections leaked on error path (verify: sh scripts/check-leak.sh)
      node: hypothesis/conn-leak | kind: hypothesis
      requires: hypothesis/pool-exhausted (EVIDENCE)
      paths: scripts/check-leak.sh
- [ ] P2.3 H2: upstream timeout mis-set (verify: sh scripts/check-timeout.sh)
      node: hypothesis/timeout | kind: hypothesis
      requires: repro/users-500 (TEST)
      paths: scripts/check-timeout.sh

## Phase 3 — Fix only what was proven

- [ ] P3.0 Regression test for the confirmed cause (verify: go test ./internal/adapters/postgres/... -run TestLeak)
      node: test/regression-leak | kind: test
      proves: fix/close-on-error
      requires: hypothesis/conn-leak (EVIDENCE)
      paths: internal/adapters/postgres/leak_test.go
- [ ] P3.1 Close connection on the error path (verify: go test ./internal/adapters/postgres/... && sh scripts/repro-500.sh)
      node: fix/close-on-error | kind: fix
      requires: test/regression-leak (TEST), repro/users-500 (TEST)
      paths: internal/adapters/postgres/repo.go
- [ ] P3.2 Gate — repro green, regression green (verify: bash .claude/scripts/claudart-graph.sh gate)
      node: gate/resolved | kind: gate
      requires: fix/close-on-error (IMPLEMENTATION)
