---
name: codex-prove
description: Drive one change through the evidence-first loop — declare a tier, observe each test failing before implementing, run the gauntlet, and end with an evidence report whose numbers a reviewer can trust without reading the code.
---

# Codex Prove

The user's request after `$codex-prove` is one change that needs proof rather than assertion ("make the token refresh reliable", "fix the off-by-one in pagination and prove it stays fixed", "I won't read the code, show me it works"). If empty, ask: "What change should I prove?"

Before doing anything, read `.codex/guidelines/evidence-gauntlet.md` in full. It is the contract; this command drives it and does not duplicate it. Also read the repository quality bar for the standing quality bar and `.codex/guidelines/ai-behavior.md` for honest-reporting obligations.

**Scope boundary.** `$codex-prove` owns **one change that fits one session**. If the work spans several files or sessions, use `$codex-plan` and name a tier in its `Validation & Acceptance` — the contract binds there too. If it is mission scale — a demoable whole, many phases — use `$codex-spec`, and write the gauntlet layers into the roadmap's `verify:` lines. Never run `$codex-prove` over work already owned by an active task or spec; the tier belongs in that artifact instead.

## Inputs

- The change description after the command.
- The repository's existing toolchain. Prefer whatever the project already uses (check `package.json`, `pyproject.toml`, `Makefile`, CI config before proposing anything new).
- If the project has no test runner, no linter, or no type checking, say so and propose the minimal standard toolchain **before** writing tests. A gauntlet cannot run on bare ground. Setup changes the user's environment, so it needs their approval in one step rather than N interruptions — list every new dependency with a one-line justification.

## Procedure

### Step 1 — Declare the tier and the acceptance surface

State the tier and why, per the rule's blast-radius table. Then write the acceptance surface as concrete behaviors: exact inputs, exact expected outputs, edge cases, error cases. "Handles bad input" is not acceptance; `divide(1, 0) raises ZeroDivisionError` is.

Include what the change must **not** do — invariants that must survive, public signatures, performance budgets if stated. These negative constraints are contract clauses like any other: each must end up mapped to a test, a gauntlet layer, or an explicit skipped-with-reason line.

At Tier 3, write the failure model first: how can this specific change hurt, and which layer catches each mode.

Show this to the user in plain language and get approval **before writing implementation**. If running autonomously, state it and proceed — but record `acceptance approval: not obtained` and claim correspondingly lower confidence.

### Step 2 — Loop per behavior

Run RED → GREEN → REFACTOR for one behavior at a time, exactly as the rule defines. The obligations that matter most here:

- Watch each new test fail before implementing it, and record the observation as `red-verified` evidence — the exact command and the decisive failure line. A test never seen failing is unproven, whatever it later scores.
- If a new test passes immediately, break the implementation with a throwaway mutant to prove the test is real, then restore.
- Never edit a test and the implementation in the same step to reach green.
- Commit only under an existing grant — a spec's `commits:` policy or the user's explicit request. This command grants nothing on its own.

### Step 3 — Run the gauntlet

Persist one entry point that runs every applicable layer in sequence and fails on the first broken one, then run it. Home-grown gates fail closed and get a negative control proving they can fail. Record every layer you skipped and why.

At Tier 3, add the property-based and failure-model layers, then do the adversarial pass: one explicit step trying to break your own implementation with hostile inputs before declaring done. If independent verification is warranted, dispatch it under `.codex/guidelines/agent-delegation.md`'s Independent Review Dispatch contract with a fresh-context general-purpose agent — never a named review agent, which is explicit-request-only.

### Step 4 — Report the Evidence

Produce the report from **one final fresh run of the entry point executed after the last edit**. Mid-task numbers are stale and must not appear.

```markdown
## Evidence — <change> (Tier <1|2|3>)

- Acceptance approval: <obtained | not obtained (autonomous run)>
- Source state: <commit sha, or base revision + changed paths for a dirty tree>
- Entry point: <the single command that reruns every layer below>

### Behavior → test

| Behavior               | Test                             | red-verified                      | Status             |
| ---------------------- | -------------------------------- | --------------------------------- | ------------------ |
| <behavior>             | <file>::<name>                   | <command → decisive failure line> | pass               |
| Must NOT: <constraint> | <test / layer / skipped: reason> | —                                 | pass \| unverified |

### Gauntlet (final fresh run)

| Layer                 | Command | Result                                          |
| --------------------- | ------- | ----------------------------------------------- |
| Tests                 | <cmd>   | <N> passed, 0 failed                            |
| Changed-line coverage | <cmd>   | <covered>/<total> changed lines                 |
| Mutation              | <cmd>   | <killed>/<total> killed; <survivors classified> |
| ...                   |         |                                                 |

### Skipped layers

- <layer>: <reason> (or "none")

### Honest notes

- <what failed during the task and how it was resolved; anything reducing confidence>
```

Numbers, never adjectives. "41 passed, 49/49 changed lines, 22/22 mutants killed" — never "tests look good". Bulky output goes to a file and is cited by path.

If any layer is still failing, report the failure verbatim as the outcome. You are not done while the gauntlet is red.

## Anti-Patterns

- Writing tests after the implementation and presenting them as proof. Without an observed red there is no evidence the test can fail.
- Declaring the tier at the end, or reaching for `$codex-prove` to add gates to work that is already at final review — the rule forbids it, and so does `.codex/guidelines/spec-workflow.md`.
- Reporting a coverage percentage from a command that exits 0 regardless of the number.
- Weakening, skipping, or deleting a test to reach green, or broadening an assertion until it passes.
- Reporting a layer that was not run, or numbers from a mid-task run.
- Running this over a change that an active task or spec already owns.
- Duplicating the rule's tier table or gauntlet table into the conversation instead of applying it.
