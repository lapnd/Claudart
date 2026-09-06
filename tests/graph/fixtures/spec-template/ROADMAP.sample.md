# ROADMAP — Example Catalog (spec-template reference output shape)

graph-format: 1

Phases are milestones for a human reader; waves are computed from `requires:`. TDD is in the edges:
an implementation node `requires:` its `test/*` node and becomes ready only when that test is
observed **red**. Kinds are hexagonal roles (`graph-development.md` §2); every outbound port has ONE
shared contract test that all its adapters require (§4). Tiers annotate each task for the executor.

<!--
Hexagonal Decomposition (what /spec emits for the mission; here a generic example)

- Domains:   catalog
- Use cases: list-items (inbound)
- Ports:
    - item-repository  (direction: out)  — the domain's persistence seam
    - list-items       (direction: in)   — driving port for the use case
- Adapters:
    - memory-items     implements port item-repository
- Contracts: none in this minimal example (add contract/<name> nodes for a frozen API seam)

Every behaviour node (domain/usecase/port/adapter) is preceded by and requires its test/* node;
every adapter of an outbound port requires that port's single shared contract test.
-->

## Phase 1 — Architecture first: domain, ports, use case (test-first)

Goal: the hexagon's inside is specified by red tests before any adapter exists.

- [ ] P1.0 Catalog domain tests (verify: go test ./internal/domain/catalog/...) (tier: standard)
      node: test/domain-catalog | kind: test
      proves: domain/catalog
      paths: internal/domain/catalog/\*\_test.go
- [ ] P1.1 Catalog domain entities and invariants (verify: go test ./internal/domain/catalog/...) (tier: standard)
      node: domain/catalog | kind: domain
      requires: test/domain-catalog (TEST)
      paths: internal/domain/catalog/\*\*
- [ ] P1.2 ItemRepository outbound port contract tests — shared by every adapter (verify: go test ./internal/ports/item_repository/...) (tier: strong)
      node: test/port-item-repository | kind: test
      proves: port/item-repository
      requires: domain/catalog (IMPLEMENTATION)
      paths: internal/ports/item_repository/contract_test.go
- [ ] P1.3 ItemRepository outbound port (verify: go build ./... && go test ./internal/ports/item_repository/...) (tier: standard)
      node: port/item-repository | kind: port
      requires: test/port-item-repository (TEST)
      paths: internal/ports/item_repository/port.go
- [ ] P1.4 ListItems use-case tests with an in-memory fake (verify: go test ./internal/app/listitems/...) (tier: standard)
      node: test/usecase-list-items | kind: test
      proves: usecase/list-items
      requires: port/item-repository (PORT)
      paths: internal/app/listitems/\*\_test.go
- [ ] P1.5 ListItems use case — inbound port + service (verify: go test ./internal/app/listitems/...) (tier: standard)
      node: usecase/list-items | kind: usecase
      requires: test/usecase-list-items (TEST), port/item-repository (PORT)
      paths: internal/app/listitems/\*\*

**Phase validation**: `go test ./internal/domain/... ./internal/app/... ./internal/ports/...`

## Phase 2 — Driven adapter proves itself against the shared port contract test

Goal: the adapter passes the SAME contract test the port defined; no adapter invents its own.

- [ ] P2.0 In-memory adapter for ItemRepository (verify: go test ./internal/adapters/memory/...) (tier: standard)
      node: adapter/memory-items | kind: adapter
      requires: port/item-repository (PORT), test/port-item-repository (TEST)
      paths: internal/adapters/memory/\*\*

**Phase validation**: `go test ./internal/adapters/...`
