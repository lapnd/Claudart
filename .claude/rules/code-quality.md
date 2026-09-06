---
paths: ["**/*"]
description: Production code quality, security, observability, and SOC 2 compliance rules — coverage bar, secure-by-default posture, structured/redacted logging, OpenTelemetry, and the CI/CD gates that enforce them. Applies to Go, Python, TypeScript/JavaScript, Vue/Nuxt, and other languages in this workspace.
when_to_use: When writing or reviewing production code, tests, logging/observability instrumentation, or any security-sensitive operation (auth, secrets, tenant data) — and before considering a feature done.
tags: [quality, security, testing, observability, compliance]
---

# Code Quality, Security & Compliance

## Goal

A feature is not production-ready because it passes functional tests. All production code must be:

**Correct → Tested → Secure → Observable → Auditable → Maintainable → SOC 2 compliant**

## 1. Test Coverage — Minimum 95%

Application/business code must maintain **at least 95%** automated coverage — overall, for critical business/domain logic, for security-sensitive code, and for new production code alike. Coverage must come from meaningful behavioral tests, never padding: unit tests for domain/application logic, integration tests for important adapters, API/contract tests at external boundaries, E2E tests for critical workflows, and a regression test for every bug fix. Generated code may be excluded, but **every exclusion needs a documented reason** — never exclude code just to raise the percentage.

The 95% figure is the project **standard**; it detects drift across the codebase. What gates an individual change is **changed-line coverage**: every line that change touched must be executed by a test, enforced by a command that exits nonzero when the threshold is missed (`--cov-fail-under`, `diff-cover --fail-under`, equivalent). A command that prints a percentage and exits 0 is a report, not a gate.

**Cost never buys down proof.** Where the Constitution's cost/efficiency principles (priority 7, Golden Rules 4-6) seem to argue for testing less, the §26 priority ladder settles it: correctness (1) and reliability/reproducibility (4) outrank efficiency (7). The 95% standard and the changed-line gate are not negotiable downward for cost; cost discipline governs _how_ the suite runs — reuse, local compute, no redundant reruns (Golden Rules 3, 8) — never _whether_ the change is proven.

Coverage alone cannot tell a test that pins behavior from one that merely executes a line, so the bar is defended by **mutation** testing: introduce plausible bugs into the changed code and confirm the suite kills each one. A surviving mutant means a missing or vacuous assertion. `evidence-gauntlet.md` owns the full procedure, the tier calibration that decides how much of it applies, and the red-before-green ordering that makes a test's failure observable in the first place.

## 2. Test Quality

Tests validate **behavior**, not implementation details (Given → When → Then). Cover happy paths, validation failures, authorization failures, edge/boundary conditions, concurrency, retry/idempotency, dependency failures, timeouts, and security-sensitive cases. Tests must be deterministic — no dependence on developer machines, local filesystem state, arbitrary timing, uncontrolled external services, or execution order.

A test that cannot fail is worse than no test, because it reports safety that does not exist. Never ship an assertion-free or tautological test, never mock the unit under test or mock so heavily that only the mocks are exercised, and never bless a snapshot you have not read. Never weaken a test — broadened assertions, added skips, raised tolerances, a deleted failure — to reach green; a test that seems wrong is a specification conversation, not an obstacle.

## 3. Security by Default

Security is part of the design, not bolted on after. Every feature considers authentication, authorization, tenant isolation, input validation, output encoding, secrets, encryption, network boundaries, dependency security, auditability, data exposure, and abuse/rate limiting where applicable. Use **deny-by-default**: if authorization cannot be established, access is denied. A hidden UI element is never a substitute for a backend check.

## 4. Authentication and Authorization

Authentication ("who are you?") and authorization ("what are you allowed to do?") are separate concerns; every protected operation enforces authorization at the backend boundary. **Never** trust frontend checks, hidden UI, route visibility, or client-provided roles/tenant IDs/ownership — the server always derives and validates its own security context (`User → Identity → Role/Permission → Tenant/Organization → Resource → Action`). Cross-tenant access must be explicitly prevented **and tested**.

## 5. Secrets Management

Never hard-code passwords, API keys, tokens, private keys, or credentials, and never commit a secret to Git. Never let a secret flow through source code, logs, URLs, query parameters, exception messages, frontend bundles, or Docker images. Use the project's approved secrets-management mechanism — environment variables are a delivery channel, not a substitute for one.

## 6. Sensitive Data Protection

Identify sensitive data (credentials, tokens, session ids, payment/personal information, confidential business data) before implementing logging, storage, APIs, or telemetry around it. It must be minimized, encrypted in transit and at rest where required, access-controlled, retained only as long as necessary, and excluded from logs unless explicitly required and protected.

## 7. Structured Logging & Redaction

All application logs are **structured** (JSON or another machine-readable format), not free-text ("Invoice created successfully for tenant abc"). Use consistent fields across services — at minimum, where applicable: `timestamp, level, service, environment, operation, request_id, trace_id, span_id, tenant_id, user_id, status, duration_ms, error_code`.

Logs must **never** contain secrets or sensitive data. Sensitive fields (`password, token, access_token, refresh_token, authorization, cookie, api_key, secret, private_key, client_secret`) are redacted centrally — never rely on developers remembering to redact per call site — and URLs are reviewed too, since query parameters can carry secrets by accident. Treat every log as potentially sensitive production data.

## 8. Observability — Tracing, Correlation, Metrics

Production services use **OpenTelemetry** for distributed tracing: instrument HTTP/RPC calls, database operations, external API calls, queues, background jobs, and important use-case operations, propagating trace context across service boundaries (`trace_id, span_id, service.name, service.version, deployment.environment`). Create meaningful spans for important business operations — not thousands of noise spans.

Traces, logs, and metrics must correlate: a `trace_id`/`span_id` in structured logs should let an engineer move `metric → trace → span → log → error` without guessing which request produced which event.

Important services expose meaningful metrics: availability (`request_count`, error count, success rate), latency (`p50/p95/p99` duration), capacity (queue depth, worker count, resource/connection-pool usage), and business metrics where appropriate (e.g. `orders_processed`, `deployment_failures`). Metrics exist to support operational decisions, not merely to exist.

## 9. Error Handling

Errors are classified, structured, traceable, and actionable — prefer stable codes (`AUTHENTICATION_FAILED`, `AUTHORIZATION_DENIED`, `RESOURCE_NOT_FOUND`, `VALIDATION_FAILED`, `DEPENDENCY_UNAVAILABLE`, `TIMEOUT`, `INTERNAL_ERROR`). Never expose internal implementation detail to an external consumer (a raw "PostgreSQL connection failed at 10.0.2.14"); return a generic message externally while the detailed diagnostic goes to secure logs/traces.

## 10. Dependency and Supply-Chain Security

Review every dependency for security risk, maintenance status, license, transitive dependencies, and necessity — prefer fewer, well-maintained dependencies. Where tooling supports it, wire in dependency vulnerability scanning, container image scanning, secret scanning, SAST, license checks, and outdated-dependency detection.

## 11. Secure Coding & Input Validation

Defend against injection (SQL/command), XSS, CSRF, SSRF, path traversal, insecure deserialization, broken access control, IDOR, race conditions, unsafe file handling, resource exhaustion, and improper cryptography. **Never** build SQL, shell commands, HTML, or other executable formats via unsafe string concatenation — use parameterized APIs and safe encoders.

Never trust external input. Validate at every system boundary (HTTP, CLI, message queue, webhook, file upload, external API, database-derived untrusted data) for type, format, size, range, allowed values, ownership, and authorization. Frontend validation is never sufficient on its own — backend validation is mandatory.

## 12. Resource and Abuse Protection

Externally reachable services consider rate limiting, request/upload size limits, pagination limits, timeout/concurrency/retry/queue limits. Avoid unbounded loops, memory allocations, database queries, uploads, or retries — every retry must consider idempotency.

## 13. SOC 2 Compliance Mapping

Architecture supports the org's SOC 2 control objectives: **Security** (least privilege, authn/authz, encryption, secrets management, vulnerability management), **Availability** (health checks, monitoring, alerting, failure handling, backup/recovery), **Confidentiality** (access control, encryption, tenant isolation, sensitive-data protection), **Processing Integrity** (input validation, deterministic processing, transaction integrity, auditability), and **Privacy** where applicable (data minimization, controlled access, retention policy). Controls must be **enforceable and auditable in code**, not dependent on developer discipline alone.

## 14. Audit Logging

Security-sensitive operations are auditable: login/logout, auth failures, role/permission changes, tenant/user creation or deletion, credential/configuration changes, billing changes, resource provisioning, data export, administrative actions. An audit event must answer _who did what, to which resource, when, from where, and whether it succeeded_ — without carrying secrets or unnecessary sensitive payloads — and audit logs are protected from unauthorized modification or deletion.

## 15. Least Privilege & Secure Defaults

Every component (user, service account, container, K8s workload, cloud IAM role, database, CI/CD, repo, storage, secret) gets the minimum permission it needs — never admin/root for convenience; temporary elevation must be explicit and auditable. Default configuration is secure: authN/authZ/TLS enabled, debug mode and verbose error responses disabled, public access disabled, CORS restrictive, secrets redacted. Insecure behavior is never the shipped default on the assumption an operator will fix it later.

## 16. Production Configuration

Production config is explicit, validated at startup, typed where possible, documented, and auditable — **fail fast** when required security config is missing rather than silently falling back to an empty password, anonymous access, HTTP instead of HTTPS, or a wildcard authorization rule.

## 17. CI/CD Quality Gates & No Warning Debt

Pull requests enforce automated gates that fail the pipeline on violation: build, unit tests, integration tests where applicable, coverage ≥ 95%, lint, format, type checking, SAST, dependency scanning, secret scanning, container/image scanning where applicable, security tests. Do not let "known" failures accumulate silently.

Warnings are not ignored indefinitely — a suppressed lint rule, disabled scanner, skipped test, or security TODO/FIXME needs a reason, an owner where appropriate, a tracking issue, and an expiration/review point where practical.

## 18. Code Review Quality

A review evaluates more than functionality: architecture, correctness, security, testing, observability, performance, error handling, data protection, maintainability, compliance. Ask explicitly: _can this fail safely? can we diagnose it in production? can we prove who performed a sensitive operation? could this expose data across tenants? what happens when a dependency is unavailable?_

## 19. Definition of Done

- [ ] Business behavior correct; architecture follows `code-organization.md`
- [ ] Automated coverage ≥ 95%; critical paths have meaningful tests
- [ ] Changed lines covered and gated; new tests observed failing before they passed; mutants killed or classified at the declared tier
- [ ] Auth/authz enforced; tenant/resource isolation verified
- [ ] Secrets and sensitive data protected; nothing committed to Git
- [ ] Logs structured, sensitive fields redacted, trace context propagated
- [ ] OTel instrumentation and operational metrics present where appropriate
- [ ] Audit events exist for security-sensitive operations
- [ ] Dependencies scanned; static/security analysis passes; CI/CD gates pass
- [ ] Errors are safe for external consumers; internals stay in secure logs
- [ ] SOC 2 control requirements considered; docs updated where required

## Core Principle

**Production quality is a system property, not a code-style property.** Do not optimize only for "the feature works" — optimize for "the feature works correctly, is well-designed, secure, tested, observable, auditable, compliant, and maintainable in production": **95%+ Coverage → Secure by Default → Least Privilege → Structured & Redacted Logs → OTel → Metrics → Auditability → SOC 2 → Production Ready.**
