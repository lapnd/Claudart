---
description: Drive the deterministic development-graph engine (lint, schedule, brief, event, gate) for an active spec's architecture manifest
---

You are operating `.claude/scripts/claudart-graph.sh`, a Python-stdlib engine that turns a spec's `architecture.yaml` + `ROADMAP.md` into a dependency graph, schedules work, and records state in `<spec>/graph/events.jsonl`. It never edits `ROADMAP.md`, `SPEC.md`, or any source file — it only writes `<spec>/graph/events.jsonl` and `<spec>/graph/evidence/*.log`. Exit codes: `0` clean/open/accepted, `1` findings/closed/refused, `2` usage/parse failure.

The command is **idempotent and re-runnable at any point in a mission**: the architecture evolves while a mission executes, so every run re-parses the manifest and re-derives the graph from scratch rather than trusting cached state. Run it as often as needed — before picking work, mid-phase, after a refinement — with no risk of double-applying anything.

## Resolve the spec folder

The argument (`$ARGUMENTS`) is a slug or dated folder id under `.claude/specs/`. Resolve it the same way `/spec-run` does: exact folder-id match, then `slug:` frontmatter match, excluding `.claude/specs/done/`. If omitted, scan active `SPEC.md` frontmatter for the single spec with status `ready` or `running`; if several qualify, ask which one. Use `--dir <that folder>` on every invocation below, and `--root <repo root>` wherever a subcommand accepts it (schedule, next, event) so merge-risk and verify resolve against real files.

## Procedure

1. **Lint first, always.** Run `lint --dir <spec>`. Exit `0` means clean — proceed. Exit `1` means findings were reported — print them verbatim and stop; do not schedule or brief against a graph with open findings. Exit `2` means the manifest or ROADMAP itself is unparseable/rejected — report that and stop; this is a structural problem in the spec folder, not something to route around.
2. **Orient.** Run `status --dir <spec>` and print it. Then run `next --dir <spec> --root <repo root>` and print it — it shows exactly what is ready now and, for everything else, which unmet dependency blocks it.
3. **Brief a node on request** (or when about to hand work to a worker): run `brief <node> --dir <spec>`. The brief is the **only** artifact a worker receives — never hand a worker the raw ROADMAP or architecture.yaml, and the worker writes nothing under the spec folder (no ROADMAP ticks, no LEDGER entries, no graph events). The worker returns files changed, the verify command it ran, and its observed exit.
4. **Record state as the orchestrator, never the worker.** After a worker reports done, YOU (the orchestrator) run `event <node> done --run --root <repo root> --dir <spec>`. `--run` re-executes the node's `verify:` yourself and records the exit **you** observed — a worker's self-reported exit is never trusted or substituted. Other transitions (`running`, `red`, `green`, `blocked`, `reopened`, `confirmed`, `refuted`, `validation-failed`, `open`, `testing`) follow the same pattern: the orchestrator observes, the orchestrator records.
5. **Reopen** a node with `reopen <node> --dir <spec>` when evidence contradicts a prior `done` — this also invalidates every transitive dependent, which the next `lint`/`status` will surface as stale.

## Other subcommands (one line each)

- `progress [--fail-on-regression] --dir <spec>` — Red-to-Green counts across TDD-tracked nodes; use it to watch a phase converge, and `--fail-on-regression` in an automated check to catch a green test going red again.
- `gate [--violations N] [--mutation X] [--check-evidence] [--running-budget S] --dir <spec>` — is the mission done? Lists exactly what's still missing (untested nodes, unmet mutation score, architecture-debt budget). Run it before proposing a final gate to the user.
- `retro --dir <spec>` — deterministic retrospective signals (verify runtimes, reopen counts, retry counts, cost) for `/learn` to consume; run at mission rotation or close, never mid-task.
- `manifest-diff <old-manifest> --dir <spec>` — classify an `architecture.yaml` edit as a scope change (needs the user's approval, per `manifest-diff-needs-approval`-style spec rules) versus an executor-level refinement that can proceed under standing approval.
- `measure <count> --dir <spec>` — record one architecture-debt measurement (e.g., a linter's violation count) so `gate`'s debt ratchet has data.
- `rules` — print the full enforcer registry (what each lint finding code means and which project rule it makes checkable); read this when a `lint` finding code is unfamiliar.

## Debugging entry point

For a pure debugging investigation with no broader mission, `init --profile debug --dir <new-or-existing-folder> --title "<bug>" --repro "<repro command>"` seeds a lightweight debug manifest: it requires the repro node to go RED first, tracks hypotheses, and refuses a fix (`FIX-WITHOUT-CAUSE`) until a hypothesis reaches `confirmed` via observed `EVIDENCE`. This is the light-entry alternative to a full `/spec` or `/migrate` mission when the only goal is "find and fix this bug."

## Auditing a brownfield project

`/graph audit <root>` scans an **existing** project tree for hexagonal-architecture violations and turns what it finds into a starting graph — without touching the tree it scans. Use it as the on-ramp for a project that predates CLAUDART, or any codebase with no `architecture.yaml` yet.

Run: `bash .claude/scripts/claudart-graph.sh audit --root <tree> --out <dir> [--profile hexagonal]`

It writes two files under `--out` (never into `<tree>`):

- **`architecture.yaml`** — a seeded manifest whose `architecture.budget` equals the measured violation count. This is the same ratchet `drift`/`gate` read elsewhere: the budget only moves when a re-measurement says it should, never by hand.
- **`refactor-plan.md`** — a graph-format ROADMAP fixing every violation **test-first**: each finding gets a `test/*` node (a failing test pinning the correct dependency) followed by the `adapter/*`/`domain/*` node that fixes it and `requires:`s that test. `claudart-graph lint` accepts this file as-is — it is a real ROADMAP, not a preview.

Exit codes follow the engine convention: `1` means violations were found and both files were written (a normal, expected outcome — not a crash); `0` means the tree is already clean and the emitted manifest carries `budget: 0`. Either way, feed `--out <dir>` straight into `/refactor` as the mission's starting artifacts — see `.claude/commands/refactor.md`.

## Anti-Patterns

- Reading the whole `ROADMAP.md`/`architecture.yaml` into a worker's prompt instead of handing it only that node's `brief` output.
- Letting a worker record its own `done` transition — the orchestrator always runs `event ... --run` and trusts only what it observed, never a worker's claimed exit.
- Treating a `MERGE RISK` line in `schedule`/`next` output as a reason to serialize work — it means isolate the conflicting nodes in separate worktrees and order the merge, never drop the parallelism.
- Weakening a node's `verify:` line to force a green — a `REFUSED-TRANSITION` or `CLAIMED-EXIT-REJECTED` finding means the evidence is wrong, not that the check is.
- Skipping `lint` because the graph "hasn't changed" — the manifest may have been refined since the last run, and lint is cheap.
