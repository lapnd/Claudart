---
name: graph-model
description: "The development-graph data model: node = claim + verifier + state, edge types, the append-only event schema, and engine exit codes."
type: architecture
status: active
updated: 2026-09-06
last_verified: 2026-09-06
scope:
  - "path:.claude/scripts/graph/**"
related:
  - "rule:graph-development"
verify: "bash .claude/scripts/claudart-graph.sh rules"
sources:
  - "../scripts/graph/core/graph.py"
  - "../scripts/graph/core/fold.py"
  - "../scripts/graph/adapters/jsonl_events.py"
---

# Development-Graph Model

The engine (`.claude/scripts/claudart-graph.sh`) makes a project's hexagonal architecture an
executable graph. It is itself hexagonal: `graph/core/` is pure (AST-checked — no I/O, no adapter
import), `graph/adapters/` owns every file format.

## Node

A node is a **claim + verifier + state**. `Node(id, kind, task, title, verify, requires, paths,
forbid, proves, tier, phase, exclusive, early_ok)`. `id` is `<kind>/<name>`. `kind` comes from the
manifest `profile`: `hexagonal` = domain, usecase, port, adapter, contract, mock, composition, test,
merge, gate, spike; `debug` = repro, hypothesis, fix, test, merge, gate, spike; `library` = module,
api, test, merge, gate, spike.

## Edges

Registered edge types: IMPLEMENTATION, CONTRACT, PORT, DATA, RUNTIME, TEST, DEPLOYMENT, EVIDENCE.
Waves are computed from edges; the DAG is acyclic; `rules.forbid` bans dependency directions
(e.g. adapter→adapter, domain→adapter).

## State is a fold over an append-only event log

State is never stored; it is folded from `<spec>/graph/events.jsonl`, the only file the engine
appends to and the orchestrator alone writes. `Event(ts, node, frm, to, cmd, exit, evidence, agent,
worktree, commit, model, tokens_in, tokens_out, duration_s, mutation)`. Test nodes go
`pending → red → green`; `red` needs an observed nonzero exit; a test reaches `green` only after a
prior `red`; an implementation `done` auto-flips the tests it `proves` from red→green. `[x]` ROADMAP
ticks seed done/green.

## Exit codes

`0` clean / open / accepted · `1` findings / closed / refused · `2` usage / parse failure. Every
lint category is an enforcer listed by `claudart-graph rules`.
