<!-- AI agents: this is a human-oriented manual. The binding contract is .claude/rules/stack-migration.md — read that, not this file, when acting. Read this file only when the user asks how to run a migration. -->

# `/migrate` — porting a codebase to another stack

How to run a port mission from nothing to cutover. The worked example is **NiceGUI (Python) → Go backend + Vue SPA, hexagonal, modular**, but the procedure is identical for Django→Nest, Streamlit→React, or a Python worker→Go.

- [README](../README.md) is the pitch · [GUIDE](GUIDE.md) is the cookbook for every command
- The binding contract for the agent is `.claude/rules/stack-migration.md`; this file explains it to you

## Contents

- [When to use `/migrate`](#when-to-use-migrate)
- [The shape of the work](#the-shape-of-the-work)
- [Step 0 — Before you type the command](#step-0--before-you-type-the-command)
- [Step 1 — The planning session (`/migrate`)](#step-1--the-planning-session-migrate)
- [The underlying principle: translate behavior, not structure](#the-underlying-principle-translate-behavior-not-structure)
- [Step 2 — Review before you say "go"](#step-2--review-before-you-say-go)
- [Step 3 — The execution sessions (`/spec-run`)](#step-3--the-execution-sessions-spec-run)
- [Model and token budget](#model-and-token-budget)
- [Step 4 — Cutover and closing the mission](#step-4--cutover-and-closing-the-mission)
- [The two reference skills](#the-two-reference-skills)
- [Worked example: eDT Installer (Cloudfabric `cf`) → Go + Vue](#worked-example-edt-installer-cloudfabric-cf--go--vue)
- [Symptom → cause → fix](#symptom--cause--fix)
- [FAQ](#faq)

## When to use `/migrate`

| Situation                                                     | Use             |
| ------------------------------------------------------------- | --------------- |
| Language, runtime, or UI framework changes; behavior must not | `/migrate`      |
| Restructuring inside one language and one build               | `/refactor`     |
| One module, no framework boundary crossed                     | `/plan` + skill |
| A rewrite where behavior is **allowed** to change             | `/spec`         |

The deciding line: `/refactor` proves equivalence by diffing inside **one** build. A port has **two** builds — no diff can span them — so parity is proved by standing both stacks up and comparing what a user would see. That is the entire reason `/migrate` exists.

## The shape of the work

```
SESSION 1 (expensive, strong model)    ← you sit with it, answering the interview
  /migrate ...
    ├─ interview: three decisions
    ├─ pin baseline + behavior contract
    ├─ translation-rules.md   ← the load-bearing artifact
    ├─ module-inventory.md
    ├─ api-contract/ (OpenAPI)  ← frozen BEFORE any target code
    └─ SPEC.md + ROADMAP.md   → you approve ONCE

SESSIONS 2..N (cheap, autonomous)      ← you only read the phase reports
  /spec-run <slug>
    loop: one translation unit → red test first → implement → differential run → tick
    rotate at each phase boundary (fresh session, /start, /spec-run again)

FINAL SESSION                          ← you confirm the demo
  awaiting-final-review → you say "approved" → done
```

Your effort concentrates in session 1 and at the confirmation points. The translation itself runs autonomously and resumes after any interruption — the state lives in `.claude/specs/`, not in a session.

## Step 0 — Before you type the command

Five things done first save hours later:

1. **Source repo clean and committed.** The baseline is pinned by SHA; a dirty tree makes every contract citation ambiguous.
2. **Know how to run the source app in one command.** Parity means running both stacks; if the Python side takes ten manual steps to boot, every verification hurts.
3. **Have real data, or a copy with a real shape.** The data-migration rehearsal happens in the first phase that touches persistence, not the last.
4. **Know what you are dropping.** Any feature not being ported belongs in the interview, so it lands in `Must-NOT-Have`. That section is the fence that stops the executor gold-plating.
5. **Decide the target repository.** Same repo or a new one? For a new one, `/migrate` records `target-repo:` in SPEC.

You do **not** need to prepare an idiom table, a Go package layout, or an endpoint list — producing those is what session 1 is for.

## Step 1 — The planning session (`/migrate`)

```
you>  /start
you>  /migrate port the NiceGUI app in app/ to a Go backend and a Vue SPA, hexagonal, modular
```

The agent reads `.claude/rules/stack-migration.md`, creates `.claude/specs/YYYY-MM-DD-<slug>/`, and starts interviewing. **While the spec is `drafting`, the agent may not write a line of implementation code** — that is a hard lock, not politeness.

### The three questions the source code cannot answer

Have answers ready for these:

**1. Target shape.** One service, or split backend + SPA? Which frameworks? Where does the seam sit — REST/OpenAPI, gRPC, events? Be specific; "Go and Vue" is not enough to freeze a contract.

**2. Cutover shape.** Pick one:

| Shape             | Means                                               | Fits when                                     |
| ----------------- | --------------------------------------------------- | --------------------------------------------- |
| **Big-bang**      | Switch once, turn the old stack off                 | Internal, few users, rollback is cheap        |
| **Strangler-fig** | A proxy routes traffic to the target piece by piece | Live in production, risk must be staged       |
| **Parallel-run**  | Both stacks serve, responses diffed, no cut yet     | High stakes, you need evidence before cutting |

Asked here, not at the final gate — discovering it late reopens the roadmap.

**3. Scope of the source.** What is ported, what is dropped, what stays on Python indefinitely.

### What session 1 produces

In `.claude/specs/YYYY-MM-DD-<slug>/artifacts/`:

| File                   | What it is                                                                             | Why it matters                                                                                |
| ---------------------- | -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `behavior-contract.md` | Every observable behavior, IDed `B1`/`V1`, cited to baseline `file:line`               | The standard to compare against; written from the **pre-change** code, never from ported code |
| `translation-rules.md` | **This project's** idiom table: source pattern → target pattern → why → a real example | What keeps session 9 translating a decorator the way session 2 did                            |
| `module-inventory.md`  | Each source file → target package/component, dependency order, risk tag                | A derivation input for the ROADMAP — **not** a second checklist                               |
| `api-contract/`        | The frozen OpenAPI (or proto) seam                                                     | Without it the public API becomes an accident of generation order                             |

The agent also runs a **phantom-feature sweep**: every deprecated comment, orphaned type hint, and stale schema reference in the source is classified — either deleted from the source (and the baseline re-pinned) or written into `Must-NOT-Have`. Skipping this is how an agent faithfully rebuilds a feature that was removed two years ago.

### About `translation-rules.md`

This is the artifact worth reading closely. The reference skills seed it, but **every row must be replaced with a real example from your code**. A generic row anchored to no source gets interpreted differently by every session.

```markdown
| Source                            | Target                                          | Why                                     | Example                                             |
| --------------------------------- | ----------------------------------------------- | --------------------------------------- | --------------------------------------------------- |
| `@dataclass` with `__post_init__` | struct + `NewX() (X, error)`, unexported fields | the invariant must not be bypassable    | `app/booking.py:12` → `internal/booking/booking.go` |
| `app.storage.user['cart']`        | server-side session record + signed cookie      | it was server state, never client state | `app/cart.py:8` → `internal/session`                |
```

## The underlying principle: translate behavior, not structure

This is the easiest thing to get wrong and the most expensive to fix late.

**What must survive 1-1 is observable behavior — not the shape of the code.** The behavior contract is binding. The implementation beneath it is not: wherever Go offers a better data structure, a better concurrency model, a better standard-library primitive, or a mature library that already solved the problem, **take it**. A faithful line-by-line translation is a defect wearing the costume of fidelity.

The parity gate is exactly what buys this freedom: a differential run pins behavior, so everything underneath is yours to redesign.

Four signals that a construct should be rewritten rather than translated:

| In Python                                                                                    | In Go it should be                                                                        |
| -------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| A hand-rolled utility Python lacked (ring buffer + lock, retry/backoff, `dict` dispatch)     | Usually **deletable** — `chan`, `context`, `sync`, and generics already cover it          |
| A structure that exists because of the GIL (thread pool around blocking I/O, work queues)    | Goroutines + `errgroup`; smaller and faster, not merely different                         |
| A dynamic shape Python could afford and Go should not (`dict[str, Any]`, `getattr` dispatch) | Give the thing a type. Carrying `map[string]any` across carries the missing schema across |
| A **pull** API that exists only because the framework could only poll                        | Go can **push** — SSE/WebSocket. Do not port a poll loop the target does not need         |

Deleted code is the best possible translation.

The fence is still `ai-behavior.md` §3/§4: choose the better Go form of _the behavior being ported_, never invent capability the source never had. "Go does it this way" is a reason; "we might need it later" is not.

### Libraries: permissive only, never GPL/AGPL

A port is when a codebase acquires most of its new dependencies, so license discipline is cheapest here and most expensive later.

- **No GPL, no AGPL** in the dependency graph of shipped code. AGPL extends copyleft to network use — for a SaaS product that is the difference between shipping and publishing your source. MIT, BSD-2/3, Apache-2.0, ISC only. MPL-2.0 is file-level copyleft, usually workable, but record it as a decision.
- **Linking is not deploying.** This governs what the shipped binary or bundle links or derives from. Running an **unmodified** copyleft program as a separate service or container is a different situation — if the mission does that, write it into `NOTES.md` rather than letting the rule silently permit or silently forbid it.
- **Check the license at the pinned version, not from memory.** Several widely-used projects have relicensed; a two-year-old blog post is not evidence.
- **Prefer stdlib → a small permissive module → a framework.** `net/http`, `encoding/json`, `database/sql`, `log/slog`, `context`, and `sync` cover most of it; many Python dependencies simply have no Go counterpart worth adding.
- **Enforce with a command, not a policy.** A license scan over the resolved dependency graph, exiting nonzero on a denied license, run in phase validation. A list in a document is not a gate.

Reliable permissive starting points (MIT / BSD / Apache-2.0 — **verify at your pinned version**): `chi` or the `net/http` mux; `pgx`/`sqlx` with `sqlc`; `golang-migrate` or `goose`; `log/slog`; `koanf` or `envconfig`; `golang.org/x/sync/errgroup`; `testify`; `oapi-codegen` or `ogen`; `google/uuid`; `shopspring/decimal`. On the Vue side, Vue, Vue Router, Pinia, Vite and the mainstream component libraries are MIT.

## Step 2 — Review before you say "go"

The agent stops at `poc-review` and reports. Read four things before approving:

- [ ] **`SPEC.md` → Must-NOT-Have.** This is the fence. A gap here is work the executor will invent.
- [ ] **`SPEC.md` → Acceptance Scenarios.** Each must be a _literal action → binary observable_. "The UI works" is a broken scenario; "POST /bookings with fixture 3 → 201 and body matches baseline" is a good one.
- [ ] **`artifacts/translation-rules.md`.** Any row still carrying a generic example? Fixing it now is cheaper than in phase 4.
- [ ] **New dependencies.** Any GPL/AGPL among them? Require a license gate that runs in phase validation, not a promise in a document.
- [ ] **Tier annotations.** Does every task carry `(tier: …)`, and is `executor-tier:` the cheapest tier that covers the roadmap?
- [ ] **`ROADMAP.md` phase 1.** Phase 1 must end with a **running end-to-end smoke path**. If phase 1 is all scaffolding, send it back: a port whose first end-to-end run lands in the final phase has no early evidence.

Approve with "go". **That is a standing approval** — `/spec-run` then executes the whole roadmap without asking again until the final gate.

If you want git checkpoints during the run, say so **before** approving: "per-task" or "per-phase". The default is `commits: user` — the agent never commits on its own.

## Step 3 — The execution sessions (`/spec-run`)

Open a **fresh** session (this is the design, not a suggestion):

```
you>  /start
you>  /spec-run <slug>
```

Each iteration: pick one translation unit → write the test derived from the Python behavior and **watch it fail first** → implement → run its `verify:` → tick and log evidence to the LEDGER.

### The three kinds of evidence you will see

- **Differential run** — both stacks up, same inputs, responses diffed. This is the only thing that counts as parity evidence.
- **Contract diff** — OpenAPI regenerated from the target versus the contract extracted from the baseline. The cheapest signal; runs at every phase boundary touching the seam.
- **Architecture gate** — a command with an exit code, e.g. the domain package's transitive dependencies contain no `net/http`, no `database/sql`, no UI package. Directory names prove nothing.

### Rotate at phase boundaries

At each phase close the agent asks _"checkpoint and rotate, or continue?"_. **Rotate.** A port is long, and a fresh session re-reading the files beats a compacted one recalling them. Rotating is `/checkpoint`, close the terminal, open a new session, `/start`, `/spec-run <slug>`.

You can also just kill the terminal at any point. The next session recovers from the files, even mid-task.

### When the spec goes `blocked`

Run the **same command** from a stronger session:

```
you>  /spec-run <slug>          # from a stronger-model session
```

Escalation is not a different workflow. The stronger session reads the diagnosis, finds a materially different path, unblocks the task, then offers to rotate back down for the routine remainder.

### What you should do yourself between phases

- Open the real target app and click through a couple of flows. Green tests do not prove the app runs.
- **Open two browser sessions at once.** Nearly every defect caused by implicit server-held state shows up here and nowhere else.
- Read `NOTES.md → Current Acceptance Delta`. If it has not changed across several phases, the progress is bookkeeping, not progress.

## Model and token budget

A port is the longest mission shape CLAUDART runs, so tier discipline is not a refinement — it decides whether the mission finishes or burns its budget in phase 2. The roadmap must carry `(tier: …)` annotations so an executing session acts on them instead of re-deriving them.

| Tier         | Port work that belongs there                                                                                                                                                                                                      |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **fast**     | Mechanical units with a binary `verify:` — a value object becoming a struct, a comprehension becoming a loop, a DTO mapping, regenerating the client from the contract, running a sweep, running the architecture or license gate |
| **standard** | The bulk: one use case with its tests, one SPA feature module, one adapter                                                                                                                                                        |
| **strong**   | Decomposing a fused callback, anything touching concurrency or shared state, designing the seam, schema and data migration, the auth boundary, and every unblock                                                                  |

Five levers that actually save money:

1. **The artifacts are the token optimization.** `behavior-contract.md`, `translation-rules.md`, and `module-inventory.md` exist so the expensive reasoning happens **once**, in the planning session, and every later session reads a decision instead of re-deriving it. A mission where cheap sessions keep re-reading the whole source has an artifact problem, not a model problem.
2. **Read the unit, not the module.** The inventory names the source lines a task needs. Loading a 4,000-line UI file to port one callback is the largest avoidable cost in a port.
3. **Verify one tier above execution on risk surfaces.** Cheap execution with stronger checking is the cost-optimal asymmetry, and it is exactly where a port's expensive defects live (concurrency, state ownership, auth).
4. **Bulky output goes to a file, referenced by path.** Differential runs, contract diffs, and license scans never get pasted into the LEDGER or the session.
5. **Rotate at phase boundaries instead of pushing a degrading session.** A fresh session re-reading four files costs less than a compacted one reconstructing them — and makes fewer mistakes.

Escalate by rotating, not by grinding: two failed attempts on one unit is the signal, and a third at the same tier costs more than the stronger session would have. When a tier proves wrong — a `fast` task that needed escalation, a `strong` task that turned out mechanical — record it in `NOTES.md` so the remaining roadmap is re-tiered instead of repeating the misjudgment for another thirty units.

## Step 4 — Cutover and closing the mission

Once the final gate passes, the spec flips to `awaiting-final-review` and **stops**. The agent does not close the mission.

A port's Definition of Done adds three items beyond `/refactor`:

- [ ] Cutover executed, or explicitly scheduled with its trigger
- [ ] Source repository marked (archived, frozen, or scoped to what remains)
- [ ] A stated rollback path

A target nobody switched to is an unfinished mission, not a completed one. When you confirm, the agent flips `done`, writes the JOURNAL line, and moves the folder to `.claude/specs/done/`.

## The two reference skills

Loaded on demand, never auto-loaded. The agent reaches for them when the matching construct is in front of it; you can also name one directly.

| Skill                 | Use when                                                                                                    |
| --------------------- | ----------------------------------------------------------------------------------------------------------- |
| `nicegui-to-vue`      | **First.** Split NiceGUI callbacks into domain / transport / view, and inventory implicit server-held state |
| `python-to-go-idioms` | **Second.** Translate each Python construct into idiomatic Go, placed in the right hexagonal layer          |

The order matters. Translating a callback that still fuses UI, state, and domain produces a Go program shaped like an event loop, and no later refactor recovers from it.

## Worked example: eDT Installer (Cloudfabric `cf`) → Go + Vue

This example comes from a real codebase: **Cloudfabric Installer** (`~/workspace/byoc/src`, package `cf`, v0.1.93) — the tool that deploys the eDT platform to AWS/Azure/on-prem, written in Python with a NiceGUI front end. Every number below was read from the repo, not invented.

### Survey: it is not fused the way a typical NiceGUI app is

This is the most important finding, and it changes the shape of the whole mission:

```
~93,000 lines of Python (tests included)

ONLY 7 files import nicegui — all under cf/web/:
  ui.py (4,679)  panels.py (3,403)  app.py  theme.py
  maintenance_ui.py  costguide.py  guide_content.py

NO nicegui import — i.e. already portable:
  cf/engine.py        cf/declarative.py (5,200)   cf/state.py
  cf/steps/           cf/providers/{aws,azure,onprem,local}/
  cf/teardown.py      cf/upgrade/                 cf/labtemplates.py
  cf/compliance/      cf/dns/                     cf/cli.py
  cf/web/jobs.py (1,858)  ← its docstring says so: "Nothing here imports NiceGUI"
```

The domain is **already** separated: `cf/web/jobs.py` drives the same `cf.engine.Engine` the CLI drives, on a background thread. So the genuinely fused surface is `ui.py` + `panels.py` — about 8,100 lines — not the codebase.

Consequence for the SPEC: most of `cf/` is **idiom translation** (`python-to-go-idioms`); only `cf/web/ui.py` and `cf/web/panels.py` need **decomposition** (`nicegui-to-vue`). Do not put the whole mission on one strategy.

### The seam already exists — it is just in disguise

`cf/web/jobs.py` keeps events in a locked ring:

```python
_events: deque = field(default_factory=lambda: deque(maxlen=RING_SIZE))   # RING_SIZE = 20_000
_seq: int = 0
_lock: threading.Lock = ...

def events_since(self, cursor: int) -> tuple[list[dict], int]:
    """Return events newer than ``cursor`` and the new cursor (latest seq)."""
    with self._lock:
        fresh = [e for e in self._events if e["seq"] > cursor]
        return fresh, self._seq
```

`events_since(cursor)` **is an API contract** already written, in Python. It maps straight onto the target's seam:

```yaml
POST   /api/jobs                      → {id}                    # jobs.start
GET    /api/jobs/{id}                 → snapshot()              # status + step_status + outputs
GET    /api/jobs/{id}/events?since=N  → {events[], cursor}      # events_since — polling fallback
GET    /api/jobs/{id}/stream          → text/event-stream       # the primary path, replays from since
POST   /api/jobs/{id}/cancel          → 202                     # request_cancel()
```

The general lesson: **before designing a seam from scratch, look for one the source already has.** A module that deliberately does not import the UI framework is usually your contract already, missing only its HTTP layer.

### Three destinations for one real callback

The Deploy button in `panels.py`:

```
domain     → cf.engine.Engine.Run(ctx, project, env, action, opts) — already framework-free,
             ported to internal/engine with python-to-go-idioms
transport  → POST /api/jobs  +  GET /api/jobs/{id}/stream   (table above)
view       → DeployPanel.vue + useJobStream(jobId) in a Pinia store;
             progress, log and topology are three components reading one stream
```

### What "don't translate 1-1" looks like here

Four examples from this code — these are the rows worth writing into `translation-rules.md`:

| `cf` (Python)                                                             | What Go should **not** do                             | What Go **should** do                                                                                                                                |
| ------------------------------------------------------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `deque(maxlen=20_000)` + `threading.Lock` + a client-side `ui.timer` poll | Port the ring and lock as-is, keep the client polling | The job publishes to a channel; the handler streams SSE. Keep the ring **only** so a late joiner replays from `since`. The 0.1s poll loop disappears |
| `threading.Thread` + `threading.Event` for `request_cancel()`             | `sync.WaitGroup` plus a mutex-guarded `bool`          | `context.WithCancel`; `request_cancel()` becomes `cancel()`, and every sub-step cancels for free                                                     |
| Events as `dict`: `{kind, step_id, title, detail, attempt, seq, ts}`      | `map[string]any`                                      | A typed struct with `EventKind` as an enum; a misspelled `kind` becomes a compile error instead of a silent log line                                 |
| `_MANAGER` / `_UPTIME_KUMA_MANAGER` process-wide singletons               | A package-level var in Go (now a data race)           | One `PortForwardManager` injected from the composition root, keyed per user/session                                                                  |

Three of those four make the Go **shorter** than the Python, not longer. That is what a correct translation looks like.

### `ui.timer` is not one pattern — it is three

`cf/web` contains 33 `ui.timer` calls (20 in `panels.py`, 13 in `ui.py`) doing three unrelated jobs. Translating them uniformly gets all three wrong:

| Use                                              | Example in the repo                       | Destination                                                |
| ------------------------------------------------ | ----------------------------------------- | ---------------------------------------------------------- |
| Polling job events                               | the main poll loop in `ui.py`             | **Disappears** — Go pushes over SSE                        |
| Debouncing an input                              | `_dash_search_deb` 0.35s; `_dbounce` 0.4s | `watchDebounced` on the client; nothing runs on the server |
| Pumping a web terminal                           | `_pump` 0.1s + `_check_target` 0.5s       | A bidirectional WebSocket to a PTY adapter in Go           |
| Refreshing a panel after an action (`once=True`) | throughout `panels.py`                    | **Disappears** — Vue reactivity, or a store refetch        |

### Hidden debt that must be named before porting

- `observability.py` says it in a comment: _"Process-wide singleton so the forward survives page reloads (single-user tool)."_ That **single-user** assumption breaks the moment the SPA serves several people. It belongs in the behavior contract with an explicit destination, never left implicit.
- Multi-user is half-built already: `workspace_subpath`, the `JobManager` owner key, `Runner.base_env` (see `tests/test_web_multiuser.py`). The port is when that gets finished, not when a half-state gets copied.
- The codebase uses **no** `app.storage.*` at all — so its implicit state lives in module-level singletons and closures, not where you would normally look. Grep for `^[A-Z_]+ = ` and `global `, not just for `storage`.
- The only mutable source of truth is the **engine's JSON state file**. That dictates phase order: the data-migration rehearsal belongs in the first phase that touches state, not the last.

### Suggested phases and tiers

| Phase | Content                                                                    | Dominant tier                                  |
| ----- | -------------------------------------------------------------------------- | ---------------------------------------------- |
| 1     | Freeze the jobs seam (OpenAPI) + handlers + SSE + a **running smoke path** | `strong` for the seam, `standard` for handlers |
| 2     | `engine` / `state` / `steps` → `internal/`; providers behind ports         | `standard`, `strong` for concurrency           |
| 3     | SPA feature modules: deploy, status, log, topology                         | `standard`                                     |
| 4     | Observability, terminal, multi-user — where `_MANAGER` detonates           | `strong`                                       |
| 5     | Strangler-fig cutover: proxy routes each screen to the target              | `standard`                                     |

Phase 1 ends with one real deployment running end to end from the SPA through the engine — not scaffolding. From there every phase has a differential run to compare against.

### The launch command

```
you>  /start
you>  /migrate port the eDT Installer (~/workspace/byoc/src, package cf) to a Go backend and a
      Vue SPA. cf/web/ui.py and panels.py are the fused surface that needs decomposition; the
      rest of cf/ is already framework-free. Hexagonal, modular. The seam is REST + SSE around
      jobs. Permissive libraries only — no GPL/AGPL.
```

Three answers to have ready for the interview: **target** = Go API + Vue SPA, seam REST/OpenAPI + SSE; **cutover** = strangler-fig (it has live users); **scope** = does `cf/cli.py` stay or port later, and are `costguide`/`guide_content` in or out.

## Symptom → cause → fix

| Symptom                                                | Actual cause                                                                                          | Fix                                                                                                                                 |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Go that reads like Python with braces                  | Transliteration instead of translation                                                                | Ground `translation-rules.md` in real examples; read `python-to-go-idioms`                                                          |
| The Go backend is shaped like a UI event loop          | The decomposition step was skipped                                                                    | Stop and run `nicegui-to-vue` over the ported callbacks                                                                             |
| Tests green, application returns wrong results         | No differential run — only unit tests                                                                 | Require a smoke path and a differential run as phase validation                                                                     |
| The agent rebuilt a feature that no longer exists      | A phantom reference in the source                                                                     | Re-run the phantom sweep; classify into Must-NOT-Have or delete at source                                                           |
| Two concurrent users see each other's data             | `app.storage.*` / globals never inventoried or destined                                               | Add the state inventory to the behavior contract, reopen the owning task                                                            |
| Everything sits under `internal/`, no clear public API | The seam was not frozen before code generation                                                        | Write `api-contract/` first and generate the client from it                                                                         |
| A task retries while the delta never moves             | The retry is not materially different                                                                 | Escalate: `/spec-run` from a stronger session                                                                                       |
| Go that is longer than the Python for the same job     | Structure was translated instead of behavior — ring+lock, thread pools, dict dispatch ported verbatim | Revisit `translation-rules.md`; ask "does Go already have this?" before porting                                                     |
| A GPL/AGPL dependency turns up deeply woven in         | No license gate in phase validation                                                                   | Add an exit-nonzero license scan now; replace the library while it is still in one place                                            |
| Tokens burn fast while progress is slow                | Every unit runs at a strong tier, or whole modules get loaded to port one function                    | Re-tier per rule §10; read units via `module-inventory.md`, not whole files                                                         |
| You find a pre-existing bug in the Python              | —                                                                                                     | Record it in `NOTES.md` as a finding; **never** fix it silently — it changes behavior and the parity diff will read as a regression |

## FAQ

**Should I keep a `MIGRATION.md` checklist of files?**
No. `ROADMAP.md` is already the only task list and `LEDGER.md` is already the log. A parallel checklist drifts, and then you cannot tell which one is true. `module-inventory.md` is the input the roadmap is derived from, not a place to tick.

**Can `/spec-run` run on a cheap model?**
Yes — that is the design. `SPEC.md` records `executor-tier:`, the cheapest tier expected to clear the roadmap. Hard tasks escalate through the same command from a stronger session.

**How long does a mission take?**
Count phases and translation units, not hours. The right size for a unit is one source module or one cohesive behavior — comfortably one iteration of one context window.

**Can I port part of it and stop?**
Yes, if you say so during the interview: what stays on Python goes into `Must-NOT-Have`, and the cutover shape is strangler-fig. What is not allowed is _silently_ stopping halfway and calling it done.

**Can the agent change scope on its own?**
No. The executor may append genuinely missing implementation work, but changing intent is yours — it has to return to `/spec` for a fresh approval.
