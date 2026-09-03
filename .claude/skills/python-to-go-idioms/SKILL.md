---
name: python-to-go-idioms
description: Translate Python constructs into idiomatic Go for a hexagonal target — classes, decorators, generators, exceptions, async, dataclasses, pydantic, SQLAlchemy, FastAPI. Use when porting Python to Go, when unsure how a Python pattern should look in Go, or when reviewing ported Go that still reads like Python.
---

# Python → Go Idioms

A pattern dictionary for **translating** Python to Go, not transliterating it. Load it, find the construct, place the result in the right hexagonal layer, move on.

Target: Go 1.23+ for `iter.Seq` and range-over-func; 1.18+ for generics. Everything else is version-independent.

## How to use this during a port

1. Identify the Python construct in the source unit being ported.
2. Take the row below; read the detailed entry in [references/pattern-catalog.md](references/pattern-catalog.md) if the one-liner is not enough.
3. **Decide the layer before writing the code** — most porting damage is a correct translation put in the wrong package.
4. Record the row you used in the mission's `artifacts/translation-rules.md` with a real example from this codebase. The generic table is a starting point; the project's own table is what keeps ten sessions consistent.

## Quick reference

| Python                        | Go                                                   | Layer it usually belongs to                                  |
| ----------------------------- | ---------------------------------------------------- | ------------------------------------------------------------ |
| `def gen(): yield x`          | `iter.Seq[T]` / channel                              | wherever the source is                                       |
| `class Child(Base)`           | interface for the contract + embedding for reuse     | contract in domain, impl in adapter                          |
| `@abstractmethod`             | interface method, defined by consumer                | domain / application port                                    |
| `@decorator`                  | middleware chain, or functional options              | adapter (middleware), constructor (options)                  |
| `try/except/finally`          | `if err != nil` + `defer` + `errors.As`              | translate at the boundary                                    |
| `raise DomainError(...)`      | sentinel `var ErrX = errors.New(...)` or typed error | domain                                                       |
| `async def` + `gather`        | goroutines + `errgroup`                              | application                                                  |
| `@dataclass`                  | struct + `NewX()` returning `(T, error)`             | domain                                                       |
| `pydantic.BaseModel`          | struct + explicit `Validate() error`                 | DTO in adapter, entity in domain — never one struct for both |
| `[f(x) for x in xs if p(x)]`  | plain loop; generic helper only if reused            | anywhere                                                     |
| `Optional[T]`                 | `*T`, or `(T, bool)`, or `(T, error)`                | pick by meaning, see §8                                      |
| `Union[A, B]`                 | interface, or generic constraint                     | domain                                                       |
| `dict[str, Any]` payloads     | a named struct                                       | adapter                                                      |
| SQLAlchemy model / session    | repository **port** + SQL adapter                    | port in domain, impl in adapter                              |
| FastAPI route handler         | thin HTTP handler calling a use case                 | adapter                                                      |
| module-level singleton/global | constructor-injected dependency                      | wired at composition root                                    |
| `logging.getLogger(__name__)` | injected `*slog.Logger`                              | injected, never global                                       |
| `os.environ[...]` at import   | one typed config struct at `main()`                  | composition root                                             |

## Rule zero: the Python structure is not the spec

The behavior is the spec. The shape is not. Before translating a construct, ask whether Go has a better answer than the one the Python was forced into — and if it does, take it:

- **A hand-rolled Python utility that Go has natively.** A polling loop feeding a UI, a thread-safe ring buffer behind a lock, a hand-written retry/backoff, a `dict`-based dispatch table — Go's channels, `context`, `sync`, `iter`, and generics frequently delete the code rather than translate it. Deleted code is the best possible translation.
- **A structure Python chose because of the GIL.** A thread pool that exists to work around blocking I/O, a queue-of-work simulating concurrency, an event loop hand-driven with `asyncio` — the Go version is usually goroutines plus `errgroup`, and it is smaller and faster, not merely different.
- **A dynamic shape Python could afford and Go should not.** `dict[str, Any]` payloads, duck-typed plugin registries, `getattr` dispatch — the port is the moment to give the thing a type. Carrying `map[string]any` across is carrying the missing schema across.
- **A pull API that could be a push API.** If the Python UI polled because the framework only allowed polling, the Go version can stream. Do not port a poll loop that the target does not need.

The parity gate is what makes this safe. A differential run against the running baseline pins observable behavior, so everything beneath it is yours to design. **Fidelity is owed to behavior, never to layout** — and the fence stays `ai-behavior.md` §2/§4: choose the better Go form of _the behavior being ported_, never a speculative framework for behavior nobody asked for.

## Choosing libraries: permissive only

A port is when a codebase acquires most of its new dependencies, so license discipline is cheapest here and most expensive later.

- **No GPL or AGPL in the dependency graph of shipped code.** AGPL extends copyleft to network use, which for a SaaS product is the difference between shipping and publishing your source. Permissive only: MIT, BSD-2/3, Apache-2.0, ISC. MPL-2.0 is file-level copyleft — usually workable, but record it as a decision.
- **Check the license at the pinned version, from the module itself.** Several widely-used projects have relicensed away from permissive terms; a memory or a two-year-old blog post is not evidence.
- **Prefer the standard library, then a small permissive module, then a framework.** Every dependency is a license, a supply-chain surface, and an upgrade obligation. Go's standard library covers HTTP, JSON, SQL, templating, logging (`log/slog`), and concurrency well enough that many Python dependencies have no Go counterpart to add at all.
- **Enforce it with a command, not a policy.** A license scan over the resolved graph that exits nonzero on a denied license, run in phase validation. See `.claude/rules/stack-migration.md` §6.

Reliable permissive starting points, all MIT / BSD / Apache-2.0 at the time of writing — **verify at your pinned version**: `chi` or the standard `net/http` mux for routing, `pgx` or `sqlx` with `sqlc` for Postgres, `golang-migrate` or `goose` for schema, `log/slog` for logging, `koanf` or `envconfig` for config, `golang.org/x/sync/errgroup` for concurrency, `testify` for assertions, `oapi-codegen` or `ogen` for OpenAPI, `google/uuid`, `shopspring/decimal` for money. On the Vue side: Vue, Vue Router, Pinia, Vite, and the mainstream component libraries are MIT.

## The eight rules that matter more than the table

1. **Errors are values, and they are translated at boundaries.** A `sqlx` error must not travel to the HTTP handler. The adapter maps it to a domain error; the handler maps the domain error to a status code. Python's habit of letting one exception type traverse every layer has no Go equivalent and should not be simulated with one giant error type.

2. **`context.Context` is the first parameter of anything that can block or be cancelled.** Python code being ported usually has no equivalent, so the port introduces it. Thread it from the entry point; never store it in a struct.

3. **Interfaces are declared where they are consumed, not where they are implemented.** Python's ABC sits above the implementations; the Go port inverts that. The domain declares `type Repo interface { Get(ctx, id) (Thing, error) }`; the Postgres package just happens to satisfy it. Do not create an `XServiceInterface` mirroring one struct.

4. **Composition, not inheritance.** A `class Child(Base)` hierarchy nearly always becomes one interface (the contract) plus embedding (the shared behavior). A deep Python hierarchy is a signal to re-model, not to reproduce; embedding is not inheritance and will not save a design that depended on `super()` chains.

5. **Zero values are part of the design.** Python constructors run arbitrary code; Go structs can be created empty by anyone. Either make the zero value valid, or make the type unconstructable outside its package and expose `NewX()`. Do not port a Python `__init__` full of defaults into a struct anyone can bypass.

6. **Concurrency is not async/await.** `asyncio.gather` becomes `errgroup.Group`; an event loop with implicit single-threading becomes real parallelism, which means shared state that was safe in Python is now a race. Every ported global, cache, or memoization is a data race until proven otherwise — run the race detector on the ported unit, not at the end.

7. **No `interface{}`/`any` as a translation shortcut.** `Dict[str, Any]` in the source means the source had no schema. The port is the moment to give it one — a named struct with real fields — not the moment to carry the missing schema across.

8. **Do not `panic` where Python raised.** An exception in Python is ordinary control flow; a panic in Go is a bug. `raise` becomes `return err` everywhere except genuinely impossible states.

## Layer placement, in one paragraph

`code-organization.md` is the authority. The port-time shorthand: business rules go in a domain package that imports nothing but the standard library; orchestration goes in an application/use-case package that depends on interfaces; every framework, driver, and SDK lives behind those interfaces in an adapter package; `main()` is the only place that knows the concrete types. If a translated function needs `net/http`, `database/sql`, or a UI type to compile, it is in the wrong package — that is the check, and it is mechanical.

## Anti-patterns

- Translating a construct the target does not need — a poll loop that could be a stream, a lock-and-ring that could be a channel, a thread pool that could be goroutines.
- Adding a GPL/AGPL dependency, or assuming a license instead of checking it at the pinned version.
- Transliterating: Go that reads as Python with braces — `Manager`/`Helper` classes-as-structs, getters and setters on every field, exceptions simulated with panic/recover.
- One struct serving as ORM row, API DTO, and domain entity because Python's model class did all three.
- `map[string]interface{}` anywhere except the outermost decode of genuinely dynamic input.
- Porting a Python decorator by writing a Go decorator function that wraps and rewraps until the call site is unreadable — use middleware for cross-cutting behavior and functional options for configuration.
- Reproducing `**kwargs` with a variadic `...any` or a giant options struct with thirty pointer fields.
- Goroutines launched with no cancellation and no `errgroup`, because the Python original just awaited.

## See also

- [references/pattern-catalog.md](references/pattern-catalog.md) — worked before/after for every row above.
- `.claude/skills/nicegui-to-vue/SKILL.md` — when the Python source is a NiceGUI/Streamlit-style fused UI, decompose it with that skill **before** applying this one.
- `.claude/rules/stack-migration.md` — the mission-level contract; this skill is only the dictionary.
