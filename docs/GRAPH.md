<!-- AI agents: this is a human-oriented manual. The binding contracts are .claude/rules/graph-development.md and .claude/knowledge/graph-model.md — read those, not this file, when acting. Read this file only when the user asks how the development graph works. -->

# `/graph` — the development graph

`/graph` drives `.claude/scripts/claudart-graph.sh`, a Python-stdlib engine that turns a spec mission's
`architecture.yaml` manifest plus a graph-format `ROADMAP.md` into an executable dependency graph: it
schedules work into waves, hands a worker a self-contained brief, and records every state transition
as an orchestrator-observed event. It never edits `ROADMAP.md`, `SPEC.md`, or your source — the only
files it writes are `<spec>/graph/events.jsonl` and `<spec>/graph/evidence/*.log`.

This describes the engine for **whatever project** it runs against — the graph models that project's
own hexagonal architecture, never CLAUDART's. `/spec` emits a graph-ready mission when it decomposes a
hexagon; `/spec-run` drives it automatically once `architecture.yaml` exists (see
`spec-workflow.md` → "Graph-driven iteration"). Use `/graph` directly to lint, inspect, or debug a
mission's graph between iterations.

## 1. The manifest — `architecture.yaml`

A small YAML subset (no tabs, no flow mappings, no anchors) describing the target hexagon:

```yaml
version: 1
project: example-catalog
profile: hexagonal # hexagonal | debug | library

layout:
  domain: internal/domain
  usecases: internal/app
  ports: internal/ports
  adapters: internal/adapters
  composition: cmd

rules:
  forbid:
    - from: adapter
      to: adapter
    - from: domain
      to: adapter

architecture:
  budget: 0 # the debt ratchet — moves only on a re-measurement, never by hand
```

`domains`, `usecases`, `ports` (with `direction: in|out`), and `adapters` (each naming the `port` it
implements) round out the layout trees. `rules.forbid` is what `lint`/`drift`/`gate` check dependency
direction against; `architecture.budget` is a ratchet, matched exactly in both directions.

## 2. Node metadata in the ROADMAP

Each ROADMAP task carries 6-space-indented metadata under its checkbox:

```markdown
- [ ] P1.1 Catalog domain entities and invariants (verify: go test ./internal/domain/catalog/...) (tier: standard)
      node: domain/catalog | kind: domain
      requires: test/domain-catalog (TEST)
      paths: internal/domain/catalog/\*\*
```

`node: <kind>/<name>` is the id. `requires: <dep> (TYPE)` lists dependency edges; `proves:` marks the
test nodes an implementation flips green on `done`. `paths:` scopes the node to real files (used for
merge-risk detection). Optional: `tier:` (routing, `agent-delegation.md`), `forbid:` (extra local
bans), `exclusive:` (never runs concurrently with anything), `early-ok:` (exempts a later-phase node
with no `requires:` from the orphan check).

## 3. Kinds — hexagonal roles, from the manifest's profile

Kinds are not free text; the manifest's `profile` supplies the vocabulary:

- **`hexagonal`**: domain, usecase, port, adapter, contract, mock, composition, test, merge, gate, spike
- **`debug`**: repro, hypothesis, fix, test, merge, gate, spike
- **`library`**: module, api, test, merge, gate, spike

## 4. Edge types — the graph is a DAG

Registered edge types: `IMPLEMENTATION`, `CONTRACT`, `PORT`, `DATA`, `RUNTIME`, `TEST`, `DEPLOYMENT`,
`EVIDENCE`. Waves are **computed** from these edges, never declared — a `## Phase N` heading is a
human milestone, not a scheduling instruction. The graph must be acyclic.

## 5. The brief — the only thing a worker sees

```bash
bash .claude/scripts/claudart-graph.sh brief <node> --dir <spec>
```

The brief is a byte-budgeted (`brief.max_bytes` in the manifest), self-contained packet: the node's
claim, its verify command, the state of each input, and — for a test node — whether it must currently
fail or currently pass. A worker never receives the raw `ROADMAP.md` or `architecture.yaml`, and it
writes nothing under the spec folder: no ticks, no LEDGER lines, no graph events, and never its own
`done`.

## 6. The event log — state is a fold, never a mutable file

State is folded from `<spec>/graph/events.jsonl`, the only file the engine appends to, and the
**orchestrator alone** writes it — a worktree spawned for a worker cannot even see the (gitignored)
spec folder. Test nodes go `pending → red → green`: `red` needs an observed nonzero exit, and `green`
never happens without a prior `red`. An implementation's `done` event auto-flips the tests it `proves`
from `red` to `green`.

## 7. Exit-code contract

`0` clean / open / accepted · `1` findings / closed / refused · `2` usage / parse failure. Every lint
finding is registered with the rule clause it enforces — run `claudart-graph.sh rules` to look one up.

## 8. The red → green workflow

Architecture → tests (observed red) → implementation, enforced structurally rather than by
convention:

```bash
bash .claude/scripts/claudart-graph.sh lint --dir <spec>                       # parse + report findings
bash .claude/scripts/claudart-graph.sh schedule --dir <spec> --root <repo>     # waves, merge risk, shape
bash .claude/scripts/claudart-graph.sh next --dir <spec> --root <repo>         # what's ready right now
bash .claude/scripts/claudart-graph.sh brief <node> --dir <spec>               # the worker's only input
bash .claude/scripts/claudart-graph.sh event <test-node> red --run --dir <spec> --root <repo>
bash .claude/scripts/claudart-graph.sh event <node> done --run --dir <spec> --root <repo>
```

`event <node> <state> --run` re-executes that node's own `verify:` and records the exit the
orchestrator actually observed — a worker's claimed exit is rejected, never trusted. For a brownfield
project with no manifest yet, `audit` scans the real tree and emits a seeded `architecture.yaml`
(budget = the measured violation count) plus a test-first `refactor-plan.md`:

```bash
bash .claude/scripts/claudart-graph.sh audit --root <tree> --out <dir>
```

`retro --dir <spec>` produces deterministic retrospective signals (verify runtimes, reopen/retry
counts, cost by tier) for `/learn` to consume at mission rotation or close.

See `.claude/rules/graph-development.md` for the full rule set and `.claude/knowledge/graph-model.md`
for the data model this document summarizes.
