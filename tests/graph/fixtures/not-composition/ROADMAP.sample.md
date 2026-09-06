# ROADMAP — User Management (reference output shape, v2 after second review)

Phases are milestones for a human reader. Waves are computed from `requires:`.
TDD is in the edges: an implementation node `requires:` its test node (`TEST`) and becomes ready
only when that test is **red** (observed failing). Kinds follow hexagonal roles (D16); every
outbound port has ONE shared contract test that all its adapters require (D17).

## Phase 1 — Architecture first: domain, use cases, ports

Goal: the hexagon's inside is specified by red tests before any adapter exists.

- [ ] P1.0 User domain tests (verify: go test ./internal/domain/user/...)
      node: test/domain-user | kind: test
      proves: domain/user
      paths: internal/domain/user/\*\_test.go
- [ ] P1.1 User domain entities and invariants (verify: go test ./internal/domain/user/...)
      node: domain/user | kind: domain
      requires: test/domain-user (TEST)
      paths: internal/domain/user/\*\*
- [ ] P1.2 UserRepository outbound port contract tests — shared by every adapter (verify: go test ./internal/ports/user_repository/...)
      node: test/port-user-repository | kind: test
      proves: port/user-repository
      requires: domain/user (IMPLEMENTATION)
      paths: internal/ports/user_repository/contract_test.go
- [ ] P1.3 UserRepository outbound port (verify: go build ./... && go test ./internal/ports/user_repository/...)
      node: port/user-repository | kind: port
      requires: test/port-user-repository (TEST)
      paths: internal/ports/user_repository/port.go
- [ ] P1.4 Notification outbound port contract tests (verify: go test ./internal/ports/notification/...)
      node: test/port-notification | kind: test
      proves: port/notification
      requires: domain/user (IMPLEMENTATION)
      paths: internal/ports/notification/contract_test.go
- [ ] P1.5 Notification outbound port (verify: go build ./... && go test ./internal/ports/notification/...)
      node: port/notification | kind: port
      requires: test/port-notification (TEST)
      paths: internal/ports/notification/port.go
- [ ] P1.6 ListUsers use-case tests with in-memory fakes (verify: go test ./internal/app/listusers/...)
      node: test/usecase-list-users | kind: test
      proves: usecase/list-users
      requires: port/user-repository (PORT)
      paths: internal/app/listusers/\*\_test.go
- [ ] P1.7 ListUsers use case — inbound port + service (verify: go test ./internal/app/listusers/...)
      node: usecase/list-users | kind: usecase
      requires: test/usecase-list-users (TEST), port/user-repository (PORT)
      paths: internal/app/listusers/\*\*
- [ ] P1.8 RegisterUser use-case tests (verify: go test ./internal/app/registeruser/...)
      node: test/usecase-register-user | kind: test
      proves: usecase/register-user
      requires: port/user-repository (PORT), port/notification (PORT)
      paths: internal/app/registeruser/\*\_test.go
- [ ] P1.9 RegisterUser use case (verify: go test ./internal/app/registeruser/...)
      node: usecase/register-user | kind: usecase
      requires: test/usecase-register-user (TEST), port/user-repository (PORT), port/notification (PORT)
      paths: internal/app/registeruser/\*\*
- [ ] P1.10 UserAPI v1 OpenAPI contract (verify: npx @redocly/cli lint api/contracts/user-api.v1.yaml)
      node: contract/user-api | kind: contract
      paths: api/contracts/user-api.v1.yaml

**Phase validation**: `go test ./internal/domain/... ./internal/app/... ./internal/ports/...`

## Phase 2 — Driven adapters, mock, HTTP contract tests — all in parallel

Goal: every adapter proves itself against the SAME port contract test; the frontend is unblocked by a mock that itself passed the API contract test.

- [ ] P2.0 PostgreSQL adapter for UserRepository (verify: go test ./internal/adapters/postgres/...)
      node: adapter/postgres-user | kind: adapter
      requires: port/user-repository (PORT), test/port-user-repository (TEST)
      paths: internal/adapters/postgres/\*\*
- [ ] P2.1 In-memory adapter for UserRepository — used by use-case tests and the mock (verify: go test ./internal/adapters/memory/...)
      node: adapter/memory-user | kind: adapter
      requires: port/user-repository (PORT), test/port-user-repository (TEST)
      paths: internal/adapters/memory/\*\*
- [ ] P2.2 SMTP adapter for Notification (verify: go test ./internal/adapters/smtp/...)
      node: adapter/smtp-notify | kind: adapter
      requires: port/notification (PORT), test/port-notification (TEST)
      paths: internal/adapters/smtp/\*\*
- [ ] P2.3 HTTP contract tests against UserAPI v1 (verify: go test ./test/contract/...)
      node: test/contract-user-api | kind: test
      proves: composition/user-service
      requires: contract/user-api (CONTRACT)
      paths: test/contract/\*\*
- [ ] P2.4 Mock API server generated from the contract — must pass the same contract tests (verify: go test ./test/contract/... -target=mock)
      node: mock/user-api | kind: mock
      requires: contract/user-api (CONTRACT), test/contract-user-api (TEST)
      paths: tools/mock/\*\*

**Phase validation**: `go test ./internal/adapters/... ./test/contract/...`

## Phase 3 — Driving adapters, composition root, frontend

Goal: the real service replaces the mock and the frontend does not change.

- [ ] P3.0 HTTP driving adapter tests (verify: go test ./internal/adapters/http/...)
      node: test/adapter-http | kind: test
      proves: adapter/http
      requires: usecase/list-users (PORT), usecase/register-user (PORT), contract/user-api (CONTRACT)
      paths: internal/adapters/http/\*\_test.go
- [ ] P3.1 HTTP driving adapter — routes call inbound ports only (verify: go test ./internal/adapters/http/...)
      node: adapter/http | kind: adapter
      requires: test/adapter-http (TEST), adapter/postgres-user (IMPLEMENTATION), adapter/smtp-notify (IMPLEMENTATION)
      paths: internal/adapters/http/\*\*
- [ ] P3.2 Composition root — wires adapters to use cases; the only place that knows both (verify: go test ./cmd/user-service/... ./test/contract/...)
      node: composition/user-service | kind: composition
      requires: adapter/http (IMPLEMENTATION), adapter/postgres-user (IMPLEMENTATION), adapter/smtp-notify (IMPLEMENTATION), test/contract-user-api (TEST)
      paths: cmd/user-service/\*\*
- [ ] P3.3 Frontend component tests against mock fixtures (verify: npm --prefix web test -- users)
      node: test/frontend-users | kind: test
      proves: adapter/frontend-users
      requires: contract/user-api (CONTRACT), mock/user-api (RUNTIME)
      paths: web/src/features/users/\*_/_.test.ts
- [ ] P3.4 Frontend users feature — a driving adapter over the API contract (verify: npm --prefix web test -- users)
      node: adapter/frontend-users | kind: adapter
      requires: test/frontend-users (TEST), contract/user-api (CONTRACT)
      paths: web/src/features/users/\*\*
- [ ] P3.5 End-to-end tests on the real stack (verify: go test ./test/e2e/...)
      node: test/e2e | kind: test
      proves: gate/release
      requires: composition/user-service (RUNTIME), adapter/frontend-users (RUNTIME)
      paths: test/e2e/\*\*
- [ ] P3.6 Release gate — every test green, drift clean, mutation score recorded (verify: bash .claude/scripts/claudart-graph.sh gate && gremlins unleash)
      node: gate/release | kind: gate
      requires: test/e2e (TEST)

**Phase validation**: `claudart-graph gate`
