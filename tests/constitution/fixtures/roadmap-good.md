# ROADMAP — sample

## Phase 1 — domain

- [ ] P1.0 domain tests (verify: go test ./internal/domain/...)
      node: test/domain-user | kind: test
      proves: domain/user
- [x] P1.1 domain entities (verify: go test ./internal/domain/...)
      node: domain/user | kind: domain
      requires: test/domain-user (TEST)
