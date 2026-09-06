<!-- AI agents: human-oriented pitch. The binding contracts live in .claude/rules/ and .codex/guidelines/ — read those, not this file, when acting. -->

<div align="center">
  <h1>CLAUDART</h1>
  <p><strong>A markdown operating layer for Claude Code &amp; Codex CLI — memory, plans, review, and an executable architecture graph, all in git.</strong></p>

  <p>
    <a href="https://github.com/lapnd/Claudart/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/github/license/lapnd/Claudart?style=for-the-badge&color=orange"></a>
    <img alt="Pure Markdown" src="https://img.shields.io/badge/memory-pure_markdown-blue?style=for-the-badge">
    <img alt="Offline-friendly" src="https://img.shields.io/badge/works-offline-green?style=for-the-badge">
    <a href="https://github.com/lapnd/Claudart/issues"><img alt="Issues" src="https://img.shields.io/github/issues/lapnd/Claudart?style=for-the-badge&color=blue"></a>
  </p>
</div>

---

Coding agents forget. Close the terminal and the plan is gone. The next session starts blind, re-reads half the repo, and re-litigates a decision you settled last Tuesday. Meanwhile `CLAUDE.md` keeps growing, because nobody trusts it enough to delete anything from it.

CLAUDART deals with this using files. A handful of slash commands maintain a small set of markdown documents under `.claude/` and `.codex/`: what's true right now, the plan for each task, the facts and rules worth keeping. On top of that sits an optional **architecture layer** — the software you build is described as an executable dependency graph the agent plans and proves against, so structure and test-discipline are checked by tools, not by trust. Everything is committed to git, reviewable in a PR, and readable without any tooling. There is no vector database and no daemon. Nothing to host, nothing to babysit.

## Install

```bash
# Flag after `bash -s --`:  --claude (default) · --codex · --both · --upgrade (refresh template files; never touches live state) · --force (overwrite everything) · --council (adds the /council deliberation companion, user scope) · --repo=<owner/name> (install from a fork; env CLAUDART_REPO — a local run auto-detects its checkout origin)
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- --claude
```

To update an existing install to the latest template (live state and your customized `CLAUDE.md`/`AGENTS.md` are never touched — commit first, review with `git diff`, then run `/doctor`):

```bash
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- --upgrade   # layers auto-detected; add --claude/--codex/--both to override
```

`install.sh` does a fresh copy, which is the wrong move for a project that already has its own setup. In that case, paste this into your agent instead. It reads the repo, diffs against your project, and merges only what you approve:

> Read https://raw.githubusercontent.com/lapnd/Claudart/main/INTEGRATE.md and follow it to integrate CLAUDART into this project. Ask me before touching anything I've customized.

Existing installations use `INTEGRATE.md` to derive their actual delta against current upstream instead of assuming a starting release. For the knowledge contract currently declared upstream, reconciliation runs `doctor → refactor-memory → doctor`; no additional recall or migration command is part of that workflow.

## What it solves

| Pain                                                         | What CLAUDART does about it                                                                                                                |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Every session starts blind                                   | `/start` reads the current state, open tasks, and recent commits before touching anything                                                  |
| Plans die when the session closes                            | `/plan` writes the plan to a task file that any later session can pick up where you left off                                               |
| A mission is too big for one session or plan                 | `/spec` freezes the intent in a POC + roadmap you approve once; `/spec-run` loops it to final review                                       |
| Structure drifts and nobody notices                          | `/graph` makes the target hexagonal architecture an executable graph — forbidden dependencies, missing tests, and debt fail a check        |
| An existing codebase has no architecture to speak of         | `/graph audit` scans it, measures the violations, and emits a test-first refactor plan you can run as a mission                            |
| A refactor must not change behavior                          | `/refactor` pins a baseline, writes a behavior contract + blast radius, and proves equivalence                                             |
| A rewrite in another language or UI stack                    | `/migrate` freezes the API seam and this project's translation rules, then proves parity by running both stacks ([guide](docs/MIGRATE.md)) |
| Tests that pass without proving anything                     | `/prove` watches each test fail first, then gates on changed-line coverage and mutation                                                    |
| A long autonomous run stalls, or hits a usage limit          | the run checkpoints and rotates its own successor; a watchdog relaunches a hung chain and resumes after a limit lifts                      |
| Rules that everyone ignores because nothing enforces them    | every architectural MUST is tagged to a mechanical enforcer; `constitution-check` fails the build when a rule loses its legislation        |
| A productive session hits the context ceiling                | `/handoff` saves the session's reasoning — hypothesis, evidence, dead ends — for the next `/start`                                         |
| The same decisions get re-discovered weekly                  | `/learn` turns recurring behavior corrections into path-scoped rules                                                                       |
| `CLAUDE.md` bloats into a token sink                         | `/refactor-memory` trims it back to an index and files the content where it belongs                                                        |
| Memory rots silently                                         | `/doctor` runs a shipped read-only checker, then audits semantic drift and misfiled content                                                |
| Switching machines, or carrying context into another project | `/backup` exports a portable bundle; `/restore` merges it elsewhere without ever overwriting a file                                        |

Three review agents ship alongside the commands — `clean-code-reviewer`, `security-auditor`, and `ui-visual-critic`, each invoked on explicit request only (never automatically, not even inside a task or spec loop) — plus a delegation protocol that keeps parallel subagent work bounded instead of letting it sprawl.

## Architecture

CLAUDART is two layers. The first is always on; the second is opt-in and turns on the moment a project adopts an `architecture.yaml`.

### Layer 1 — the operating layer (memory & workflow)

Four kinds of memory, four different lifetimes:

```text
SESSION STATE (volatile)                DURABLE REFERENCE (survives sessions)

CONTEXT.md       JOURNAL.md             rules/ · guidelines/   knowledge/
what's true now  what happened          how to behave          what the project is
(declarative)    (history log)          (prescriptive)         (descriptive facts)

always loaded    never loaded           auto-loads on          INDEX on /start,
in context       (audit only)           a matching path        detail on demand
```

`/checkpoint` rebuilds `CONTEXT.md` at the end of a session, retires history to `JOURNAL.md`, and bulk-promotes remaining durable facts. It is not the only knowledge write boundary: during a long exploration, saying “update knowledge from what we just verified, then continue” triggers an immediate distillation pass. Verified, current project facts go to `knowledge/`; task/WIP/proposed state stays in its task, spec, or context; uncertain claims remain candidates unless evidence invalidates an existing owner, in which case that topic becomes `review-needed`; recurring behavior goes to rules through `/learn`.

Retrieval is map-first and bounded: root `INDEX.md`, at most the relevant domain maps, then topic frontmatter/outline and the smallest useful section. Full files and source-history search are fallbacks, not the default. Above every rule sits the **Engineering Constitution** (`.claude/rules/constitution.md`) — a decision-priority ladder and sixteen Golden Rules that settle conflicts (correctness first, cost discipline last and never over correctness).

### Layer 2 — the architecture layer (the software you build)

The software's own architecture stops being prose an agent re-interprets each session and becomes an **executable dependency graph** it consumes. A small `architecture.yaml` manifest declares the target — hexagonal (ports & adapters) by default — and the roadmap's tasks carry graph metadata:

```text
architecture.yaml            ROADMAP.md (graph-format)         events.jsonl (append-only)
profile + layout + budget    nodes = claim · verifier · state  the only file the engine writes
rules.forbid (directions)    edges = real dependencies         state is a fold over this log
```

A single dependency-free engine (`claudart-graph`, Python stdlib, itself hexagonal) reads that and:

- **lints** the graph — forbidden dependency directions (adapters importing adapters, a domain reaching infrastructure), cycles, dangling edges, an architecture-debt budget that ratchets only downward;
- **enforces TDD structurally** — a behaviour node cannot go `done` until its test was _observed failing_ first; the engine refuses a green a red never preceded;
- **schedules** — waves and the critical path are computed from the edges, so independent work fans out in parallel and merges reconcile through explicit nodes;
- **audits a brownfield tree** — `/graph audit` measures the real violations and writes a seeded manifest plus a test-first refactor plan;
- **stays honest** — every architectural MUST in the rules is tagged to a named enforcer, and `constitution-check` fails the build if a rule loses its legislation or an agent claims a result the engine did not observe.

Greenfield or brownfield, the graph evolves continuously: start from a coarse hexagon, refine it, re-run the fold, and reopened nodes drag their dependents back for re-proof. Full reference: **[docs/GRAPH.md](docs/GRAPH.md)**.

## Usage scenarios

Different situations, different entry points — all the same file-based state underneath:

- **Day-to-day change** — `/start` to orient, `/plan add JWT middleware` to write a task the agent executes after your approval. Small, single-session work.
- **A mission too big for one plan (greenfield)** — `/spec build the demo game` interviews you, freezes intent in a POC + roadmap you approve once; `/spec-run` then executes it across fresh sessions autonomously until final review, checkpointing and rotating its own successor at phase boundaries.
- **A hexagonal build with real structure** — the spec emits an `architecture.yaml` and a graph-format roadmap; `/graph` schedules the waves and proves each layer test-first. Ports are frozen before adapters; every adapter passes the one shared contract test.
- **An existing codebase you inherited** — `/graph audit <path>` reports what its architecture actually _is_, scores the violations, and hands you a test-first refactor plan; adopt it with `/refactor` and drive the debt budget down over time.
- **A refactor that must not change behavior** — `/refactor` pins a baseline, reconstructs the behavior contract from the pre-change code, and proves equivalence with differential runs.
- **A rewrite across languages or UI stacks** — `/migrate` (e.g. NiceGUI→Go+Vue) freezes the API seam and this project's translation rules, then proves parity by running both stacks.
- **A pure debugging session** — the `debug` profile models repro → hypothesis → fix → test as graph nodes; a fix is refused without a confirmed cause and a red repro.
- **Proving a specific fix** — `/prove` runs the evidence gauntlet: red before green, changed-line coverage, mutation, and a report of numbers instead of adjectives.
- **A long unattended run** — set `rotation: auto`; the executor rotates itself, and `claudart-supervise` polls health, relaunches a stalled chain, and backs off then resumes when a usage limit lifts — no work lost when the limit clears.
- **Keeping the setup healthy** — `/checkpoint` at session end, `/doctor` when something feels off, `/optimize` when auto-compact fires too often, `/backup` + `/restore` to move between machines or projects.

## Quick start

```bash
# In a project with CLAUDART installed
/start                          # orient the session
/plan add JWT middleware        # write a task file; the agent waits for your approval before coding
/spec build the demo game       # mission too big for one plan? interview → POC → roadmap, approved once
/spec-run demo-game             # fresh sessions execute the approved mission autonomously until final review
/graph audit ./legacy-service   # scan an existing tree → violations + a test-first refactor plan
/graph next demo-game           # what's runnable now in the mission's dependency graph
/refactor migrate auth to v2    # refactor mission: pinned baseline + behavior contract prove equivalence
/migrate nicegui app to go+vue  # port mission: contract-first seam, translation rules, differential parity runs
/prove fix the pagination bug   # evidence-first: red before green, gauntlet, then numbers instead of adjectives
/handoff                        # context nearly full? save your reasoning, resume fresh with /start
/checkpoint                     # rebuild CONTEXT.md at session end
/learn                          # promote recurring decisions into rules
/doctor                         # health check when the setup feels off
/optimize                       # auto-compact too often? audit where the tokens go
/backup                         # moving machines? export sessions + memory as a portable bundle
/restore                        # import that bundle elsewhere — dry run first, never overwrites
```

Codex CLI runs the same flow with `$codex-` instead of `/` (e.g. `$codex-start`, `$codex-graph`).

## Documentation

**[docs/GUIDE.md](docs/GUIDE.md)** is the cookbook — pick your situation, follow the recipe: concrete walkthroughs for every command and scenario.
**[docs/WORKFLOW.md](docs/WORKFLOW.md)** is the manual — architecture, the full task lifecycle, every command, directory layout.
**[docs/GRAPH.md](docs/GRAPH.md)** is the architecture-graph reference — the manifest, node metadata, kinds, the event log, and the red→green workflow.
This README is just the pitch.

## Comparison

|                                |        CLAUDART        |              Mem0               |          Zep          |        LangMem        |               Understand-Anything               |                     MemPalace                      |
| ------------------------------ | :--------------------: | :-----------------------------: | :-------------------: | :-------------------: | :---------------------------------------------: | :------------------------------------------------: |
| **Setup**                      |     `curl \| bash`     | vector DB + Docker + OpenAI key | Neo4j + managed cloud | PostgreSQL + pgvector |            `curl \| bash` or plugin             |            `pip install` + 300 MB model            |
| **Human-readable**             |           ✅           |               ❌                |          ❌           |          ❌           |               ⚠️ JSON + dashboard               |            ⚠️ verbatim text, binary DB             |
| **Works offline / air-gapped** |           ✅           |               ❌                |          ❌           |          ❌           |                 ❌ LLM required                 |                         ✅                         |
| **PR-reviewable memory**       |           ✅           |               ❌                |          ❌           |          ❌           |            ✅ JSON committed to git             |            ❌ ChromaDB + SQLite binary             |
| **Enforced architecture**      |    ✅ graph + lint     |               ❌                |          ❌           |          ❌           |                       ❌                        |                         ❌                         |
| **Tool support**               | Claude Code, Codex CLI |            API only             |       API only        |    LangGraph only     | Claude, Codex, Cursor, Copilot, Gemini + 6 more | Claude Code, Codex CLI, Gemini CLI, MCP-compatible |

Plain markdown in the repo won this argument: `AGENTS.md` provides a versioned convention that multiple coding agents can share. CLAUDART builds the missing workflow on top of it — orientation, planning, learning, hygiene, review, and an architecture the tools can check.

## License

MIT, see [`LICENSE`](LICENSE). Contributions welcome; [`CONTRIBUTING.md`](CONTRIBUTING.md) has the ground rules.
