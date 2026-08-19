---
paths: ["**/*"]
description: Code organization and architecture rules — hexagonal (ports & adapters) boundaries, module structure, and size/complexity limits, applied to any language written in this workspace.
when_to_use: When creating new source files or modules, adding a package/domain, organizing or restructuring existing code, or reviewing code for architectural boundaries.
tags: [architecture, hexagonal, code-organization, modularity]
---

# Code Organization & Architecture

## Goal

Code must be **well-designed, modular, clean, maintainable, and easy to extend** — across every language or framework in this workspace (Go, Python, TypeScript/JavaScript, Vue/Nuxt, Java, Rust, etc.).

Target architecture is **Hexagonal (Ports & Adapters)**:

- **Domain** — business concepts and rules
- **Application / Use Cases** — orchestration and workflows
- **Ports** — explicit interfaces/contracts
- **Adapters** — infrastructure, external systems, frameworks, databases, APIs, UI
- **Composition / Entry Points** — wiring and dependency injection

Business logic must not couple to infrastructure, frameworks, deployment environments, or specific implementations.

## 1. A Shared Filename Prefix Is a Module Waiting to Be Created

When two or more files share a concept, they belong in a directory named for that concept, not a flat list of prefixed names beside unrelated code.

```text
✗ finance_engine.go / finance_stripe.go / finance_local.go
✓ finance/engine.go, finance/stripe.go, finance/local.go
```

If a name repeatedly starts with `billing_`, `finance_`, `user_`, `aws_`, etc., stop and ask whether those files should form a module. When one member of that family grows, it becomes a directory in turn (`finance/stripe/engine.go`, `finance/stripe/metrics.go`). **Do not use naming conventions to compensate for poor module boundaries.**

## 2. Domain-Oriented Structure, Not Technical Buckets

Organize around business/domain concepts (`billing/`, `finance/`, `tenant/`, `capacity/`), not technical catch-alls (`services/`, `utils/`, `helpers/`, `managers/`, `common/`, `misc/`). Before adding to `utils`, ask: _what domain does this actually belong to?_ If it's genuinely cross-cutting infrastructure, give it an explicit technical name and boundary instead of a generic bucket.

## 3. Hexagonal Layering — Dependencies Point Toward the Domain

```text
Adapters (HTTP/DB/cloud/UI) → Ports → Application (Use Cases) → Domain (Business Rules)
```

The domain must **never** import database drivers, HTTP frameworks, cloud SDKs, Kubernetes/Terraform clients, message brokers, UI frameworks, or environment-specific config. Define ports at the boundary; implement them in adapters. A project is not Hexagonal merely because it has folders named `domain/`, `application/`, `ports/`, `adapters/` — verify the actual dependency graph, not the directory names.

## 4. Domain Must Be Framework-Agnostic; Dependencies Are Explicit

Business rules must be constructible and executable without a database, HTTP server, container orchestrator, cloud SDK, or web framework — inject collaborators through constructors/functions, never through hidden global state, singletons, or implicit service discovery.

```python
✗ class BillingService: def __init__(self, postgres_connection): ...
✓ class BillingService: def __init__(self, contract_repository): ...  # Postgres implements it as an adapter
```

The composition root wires concrete implementations together; nothing else does.

## 5. Interfaces Must Represent Real Boundaries

Create an interface only because multiple implementations are expected, a dependency crosses an architectural boundary, a test needs a real seam, or it represents a domain/application port. Do not create `XServiceInterface` mirrors of a single implementation "because clean architecture requires interfaces." Prefer small, capability-oriented contracts (`PaymentAuthorizer.Authorize(...)`) over giant interfaces bundling unrelated operations. **Interfaces are discovered from consumers, not designed as mirrors of implementations.**

## 6. Adapters Stay Thin; Domain Models Stay Separate From Infrastructure Models

Adapters translate between external systems and the application/domain — they must not carry core business rules. Don't put substantial business logic inside HTTP handlers, SQL repositories, ORM models, controllers, or SDK wrappers; they should handle protocol translation, serialization, persistence, and mapping. Symmetrically, never auto-expose database models, ORM entities, API DTOs, or cloud SDK structures as domain models — external models change for external reasons, domain models change because business rules change.

## 7. No Cross-Domain Leakage; No Circular Dependencies

A domain must not reach directly into another domain's internals or database tables (`billing → internal fields of contract`). Cross-domain communication happens through a defined public contract (`Billing → Contract Port → Contract Application API`). If a dependency cycle appears (`A → B → C → A`), stop and reconsider the boundary — extract a shared concept, introduce a port, or invert the dependency. Never solve a cycle with import hacks.

## 8. Composition Over Conditional Complexity

When behavior genuinely varies by capability, profile, or provider, model that variation explicitly as a directory/strategy per case (`profile/on-prem/`, `profile/cloud/`) or a capability interface (`CanCreateTenant`, `CanUseCredit`) — not a growing `if profile == "..."` chain scattered through the codebase. Profile names should be configuration/data, not architectural concepts, and environment variables should carry deployment-specific config, not decide business behavior (`Profile → Capabilities → Configuration → Application behavior`, not a pile of `ENV_A`/`ENV_B`/`ENV_C` flags).

## 9. Testability

Core business logic must be constructible and testable with small in-memory/fake dependencies — no Docker, Kubernetes, live database, network, or cloud credentials required. Integration/E2E tests still validate boundaries but must not compensate for untestable business logic. Tests live next to the code they test (`billing/calculate_usage.go` + `billing/calculate_usage_test.go`), following the same module boundaries as production code — not a detached global test tree.

## 10. Size & Complexity Are Design Signals

Default limits: files under ~500 LOC (excluding comments/docstrings), functions typically 10–30 LOC, 50 LOC max without justification. Don't split files just to satisfy a number — the goal is cohesion, not fragmentation. Treat these as warning signs that the model needs rework, not more code: deep nesting, long switch/if-elif chains on profile/provider, duplicated validation, boolean-parameter explosions, large constructors, many dependencies, copy/paste implementations.

## 11. Duplication and Abstraction

Centralize a business rule that's duplicated across API/CLI/worker/frontend/repository layers by identifying its correct owner — but do not prematurely build a "common" abstraction for code that only happens to look similar. **Remove meaningful duplication, not superficial similarity.** Symmetrically, don't add unused interfaces, factories, generic frameworks, speculative extension points, or configuration nobody needs — design for known variation, not every hypothetical future. Represent variation that is _already real_ (providers, profiles, deployment models) explicitly rather than hiding it in conditionals.

## 12. Errors and Logging Stay at Boundaries

Translate infrastructure errors into application/domain errors at the adapter boundary — don't leak `pq.Error`, `sqlalchemy.exc.*`, or cloud-SDK exceptions through the whole call stack. Log at meaningful boundaries with structured context (operation, resource id, correlation id, error category), not the same error re-logged at every layer. **Never log passwords, tokens, secrets, credentials, or sensitive payloads.**

## 13. Small Public API Surface; Intent-Revealing Names

Keep a symbol private/internal unless it's genuinely part of the module's contract — every export becomes maintenance surface. Name for intent (`CalculateEntitlement`, `CreateInvoice`), not implementation history or a generic suffix (`Manager`, `Helper`, `Util`, `Processor`, `Handler`) unless that word genuinely represents the concept. Frameworks (FastAPI, Django, Gin, Vue, GORM, cloud SDKs, K8s clients) stay implementation details at the edge — the architecture should allow replacing one without rewriting the domain.

## 14. Refactoring Existing Code

Distinguish three cases when touching existing structure:

- **Required architectural change** — the current structure blocks the requested feature; restructure as part of the task.
- **Independent cleanup** — restructuring unrelated to the request; do not mix it into the implementation, record it separately instead.
- **Mechanical migration** — a flat filename-prefix family becoming a module; treat it as its own step, and verify build/type-check, unit + integration tests, imports, and runtime behavior afterward. Do not perform broad restructuring without verification.

**Do NOT restructure** when a scheduled task will rename/re-key the same files soon, the move is unrelated to the current task, generated files are involved (sqlc/protobuf/OpenAPI/mocks — regenerate via the generator, never hand-edit output), or the architectural benefit doesn't justify the regression risk.

## 15. Definition of Done for New Code

- [ ] Clear domain/module; responsibilities separated; dependency direction correct (toward the domain)
- [ ] Business logic independent from infrastructure; external systems behind ports/adapters
- [ ] Dependencies explicit (constructor/function injection, no hidden globals)
- [ ] Profile/provider variation modeled explicitly; environment variables minimized
- [ ] No duplicated business logic; no unnecessary `utils`/`helpers`/`common` dumping grounds
- [ ] Files/functions within size limits; tests colocated and able to run without infrastructure
- [ ] Errors translated at boundaries; public API minimized; framework dependencies kept at the edge
- [ ] The resulting structure would be easy for a new developer to understand

## The Core Principle

Do not optimize for _"where can I put this code so the feature works?"_ — optimize for _"what is the correct domain, responsibility, boundary, dependency direction, and extension point for this code?"_ A feature is not well-designed merely because it works: correct behavior + correct architecture + maintainability are all part of done.

This is the architecture-specific instance of `ai-behavior.md`'s §3 (Correct Model Over Quick Fix — Bounded by Scope): favor the durable, correct structure over a shortcut, but stop at what the request actually needs — §1/§11's rejection of unrequested interfaces, frameworks, and speculative extension points is this rule's own scope fence, not a license to redesign adjacent code.
