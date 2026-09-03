---
paths: ["**/*"]
description: Evidence-first proof discipline for code changes — tier calibration by blast radius, observed-red-before-green ordering, a gauntlet of executable layers (changed-line coverage, mutation, property-based tests), absolute anti-gaming rules, and fail-closed checkers. Supplies the proof half that code-quality.md's coverage bar assumes.
when_to_use: When a change needs proof rather than assertion — a task or roadmap item that names a tier, any bug fix, any security- or money-sensitive surface, or an invocation of /prove. Read before writing the first test, not after the implementation.
tags: [testing, evidence, tdd, mutation, verification]
---

# Evidence Gauntlet

`code-quality.md` sets the bar (≥95% coverage, behavior not implementation). This rule is how that bar is **proved rather than asserted**. Its premise: a reviewer who reads every line does not scale to agent-written code, so trust has to move from inspection to constraints the author cannot quietly weaken.

Be honest about what that buys. The gauntlet turns the constraints a spec expresses into executable evidence. It **cannot** show the spec expresses everything that matters, and it is not self-authenticating — a checker can be unsound, and a mapping can claim more than it demonstrates. That is why acceptance is approved by the user before code exists, and why evidence reports layered confidence, never proof.

## 1. Calibration — declare a tier before writing anything

Scale effort to **blast radius**, and state which tier you chose. A tier is selected at planning time — in a task's `Validation & Acceptance`, a roadmap task's `verify:`, or the opening of `/prove` — and **never injected at final review**. `spec-workflow.md` forbids a bounded review patch from adding quality gates; a tier that arrives after the work is exactly that, and it is out of bounds.

| Tier                     | Scope                                                             | Required layers                                                                                                                                                                                  |
| ------------------------ | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Tier 1 — trivial**     | typo, comment, config value, doc edit                             | full suite + lint. No new tests, but state why the change is untestable or already covered.                                                                                                      |
| **Tier 2 — normal**      | bug fix, small feature                                            | the full loop below + changed-line coverage gate + mutation. A bug fix MUST start with a red test reproducing the bug — the fix is not done until yesterday's bug is tomorrow's regression test. |
| **Tier 3 — high stakes** | money, auth, data loss, concurrency, public API, tenant isolation | Tier 2 + a written failure model + property-based tests + an adversarial pass. Independent verification optional (§7).                                                                           |

Tier 3 starts with the **failure model**: list the ways this specific change can hurt (race, partial write, hostile input, overflow, unbounded growth, failed rollback, silent production failure), and for each mode add a layer that can actually catch it. Mutation and coverage cannot substitute for these — the generic gauntlet is the floor, not the ceiling. Failure modes deliberately not covered are recorded as known limits, never omitted.

## 2. The loop

```
declare tier → RED → GREEN → REFACTOR → GAUNTLET → EVIDENCE
                ↑________________|
                  repeat per behavior
```

### RED — prove each test can fail

Write the test for one behavior, run it, and **watch it fail before writing the implementation**. **A test you never saw fail proves nothing** — it may be testing nothing at all. Record the observation as a `red-verified` evidence line (§6).

- If the module under test does not exist yet, create a stub that raises so the test fails on **behavior, not import**. A collection error is a weaker red than an assertion failure.
- Related behaviors may share one red run, as long as each new test is individually observed failing.
- If a new test passes immediately it is either vacuous or the behavior already exists. **Do not just assert which — prove it**: break the implementation with a **throwaway mutant**, watch the test fail, restore. Then record it as pre-existing behavior kept as regression armor.

### GREEN — minimal implementation

Write the least code that makes the failing test pass. Run the full suite, not just the new test.

### REFACTOR — clean up under green, assertions frozen

What is frozen is **behavioral assertions**, not test files wholesale.

- Implementation refactors touch no test files at all.
- Test-structure refactors (extracting helpers and fixtures) are a **separate step**: assertions unchanged, suite green before and after, then rerun mutation — a refactor that blunts the tests is a silent hole in the gauntlet.
- Anything requiring an edited assertion is a behavior change, not a refactor. It goes back to the acceptance surface and its owner.

## 3. The gauntlet

Run every applicable layer for the declared tier. **Never skip a layer silently** — if a layer does not apply or a tool is unavailable, record that with its reason.

| Layer                     | What it catches                     | Gate                                                                                                                                                                                                                                                                                                                   |
| ------------------------- | ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Full test suite           | regressions                         | zero **new** failures; record pre-existing failures as a baseline first, **with the tools and build state it was captured under** — a baseline that does not state its own preconditions expires silently (`verification-mechanics.md` §2)                                                                             |
| Static types              | whole classes of bugs               | zero new errors                                                                                                                                                                                                                                                                                                        |
| Lint + format             | latent bugs, drift                  | zero new warnings                                                                                                                                                                                                                                                                                                      |
| **Changed-line coverage** | untested code paths                 | every changed/added line executed, branch coverage where supported. **This layer must exit nonzero when its threshold is missed** (`--cov-fail-under`, `diff-cover --fail-under`, equivalent) — a layer that prints a percentage and exits 0 is a report, not a gate, and it will sit there green while coverage falls |
| Mutation                  | tests that assert nothing           | every mutant killed, or classified (§5)                                                                                                                                                                                                                                                                                |
| Property-based            | edge cases nobody imagined          | invariants for parsing, math, serialization: round-trip, idempotence, ordering                                                                                                                                                                                                                                         |
| Real execution            | "passes tests, doesn't run"         | actually drive the app/CLI/endpoint once on realistic input, not only the harness                                                                                                                                                                                                                                      |
| Supply chain & secrets    | vulnerable deps, leaked credentials | audit when the dependency set changed; scan the diff; check the capability diff — did this change start using network / subprocess / filesystem / env it did not before?                                                                                                                                               |
| Suite health              | flaky or order-dependent tests      | randomized order; repeat suspected flakes. Every number below rests on the suite being deterministic                                                                                                                                                                                                                   |

**Global percentage is context, changed-line coverage is the gate.** `code-quality.md`'s ≥95% remains the project standard; it is a detector of drift across the codebase. What blocks this change is whether the lines this change touched are exercised.

A gauntlet layer is enforceable only when it is **named in an acceptance scenario or a `verify:` line**. `spec-workflow.md` forbids inferring a defect from broad language like "quality" or "production-ready" — so an unnamed layer is advisory, and naming it is what makes it binding.

## 4. Anti-gaming rules (absolute)

The gauntlet creates trust only if it cannot be gamed. These are hard rules, extending `ai-behavior.md` §5.

1. **Never weaken a test to make it pass.** No broadened assertions, added skips, raised tolerances, or deleted failures. A test that seems wrong is an acceptance conversation — surface it, do not bury it.
2. **Never edit a test and the implementation in the same step to reach green.** Change one, run, then the other. Simultaneous edits let you redefine correctness to match your bug.
3. **Never mock the unit under test**, or mock so much that the test only exercises mocks. Mock boundaries — network, clock, filesystem — not logic.
4. **Never chase the coverage number.** **Coverage is a detector** of untested code, not a target. A test added only to touch lines, with no meaningful assertion, is gaming — mutation testing exists precisely to catch this, including yours.
5. **Never report a layer you didn't run.** An honest "skipped: no mutation tool available, did manual mutation instead" preserves trust; an invented result destroys the entire scheme.
6. **A failing gauntlet blocks done.** You are not finished while any layer fails. If genuinely blocked, report the failure verbatim as the outcome.

## 5. Mutation — the guard on the coverage bar

Prefer the ecosystem's tool (mutmut, Stryker, cargo-mutants, PIT). With no tool, script the manual procedure and **persist the script in the repo** — hand-editing invites restore mistakes, and §6 requires a final fresh run, so you will run the mutants at least twice.

1. Take the new/changed implementation code.
2. One at a time, introduce 3-5 plausible bugs biased toward the logic that matters: flip a comparison, off-by-one a bound, delete a branch or early return, swap `and`/`or`, replace a returned value with a constant.
3. Run the suite after each. **Every mutant must make at least one test fail.** A survivor means a missing or vacuous assertion — add the test that kills it.
4. Restore and confirm green; verify the restore by diffing against an **explicit saved copy** of the file taken before the first mutant, never by eyeball and NEVER with `git diff` against `HEAD` — the implementation under mutation is normally uncommitted, so a `HEAD` diff shows your own in-progress work and could not distinguish a bad restore from it (`verification-mechanics.md` §5, `.claude/lesson.md` §14).

**Kills are attributed to whichever test fails first**, so a 7/7 score validates the suite as a whole, not every layer in it. At Tier 3, rerun the mutants against the property suite alone before claiming the properties verify anything.

With a tool, a survivor is not automatically a failure: some mutants are semantically **equivalent mutant**s and cannot be killed. Classify these as "equivalent, because `<reason>`" rather than adding a meaningless test to kill them — that would violate rule 4. Hand-written mutants get no such excuse: you chose them, so choose real bugs.

A survivor has a third resolution besides "kill it" and "classify it equivalent": **the mutated code may be unobservable, in which case delete the code.** A defensive branch whose removal no test can detect, because a later expression already handles the case, is not a coverage gap to be papered over with a contrived test — it is dead code that `ai-behavior.md` §2 says not to have written. Deleting it is the honest fix and lowers the changed-line count the gate has to cover. NEVER reach instead for a more elaborate test to make an unobservable branch look tested; a test written to reach a line rather than to pin a behavior is rule 4's exact violation, and mutation is what exposes it.

## 6. Checkers, entry point, and evidence

**Home-grown checks must fail closed.** Off-the-shelf tools have earned their failure behavior; grep gates, custom scripts and manual mutation runners have not. The dangerous failure is fail-open: nothing crashes, the layer prints pass. So: `set -e`, no `|| true`, no `2>/dev/null`, and spell out ambiguous exit codes. The classic trap is a must-find-nothing grep — rc 1 (no matches) is the only pass; rc 0 means the forbidden pattern exists and rc ≥ 2 means the check itself broke, and both must fail the layer.

**Prove a checker can fail before trusting its pass.** Run it once against a known-bad input — a **negative control** — and watch it fail. This is the RED principle applied to checkers. Be precise about what it buys: a negative control proves one known-bad case reaches the failure path. It does **not** prove the checker recognizes every violation of the rule it serves. Where the gate is narrower than the rule, say so where the rule is written.

Persist one **gauntlet entry point** that runs every layer in sequence and fails on the first broken one. Start it by deleting stale artifacts from previous runs so no layer can read a prior run's output — freshness by mechanism, not discipline. Pin dev-tool versions so a rerun uses the same gauntlet — and **pin each tool's rule set in-repo as well**, because a version pin alone does not fix a gate's meaning: a linter with no configuration section reports whatever the installed version defaults to, so the next upgrade silently redefines the layer. See `verification-mechanics.md` §4.

Evidence follows the anatomy already defined in `spec-workflow.md` — the claim, the exact command, 1-3 decisive output lines, and the revision observed at. This rule adds one event and two obligations:

- **`red-verified`** — the test was observed failing before the implementation existed. At Tier 2 and above a tick requires this transition on record; without it the test is unproven, whatever it scores.
- All reported numbers come from **one final fresh run of the entry point after the last edit**. Mid-task numbers are stale.
- Layers skipped, and why. Anything that failed and how it was resolved. A gauntlet passed first try and a gauntlet fixed your way through are equally fine; a gauntlet quietly weakened is the only failure.

Bulky output goes to a file and is referenced by path, never pasted inline.

Commits during the loop are **not** this rule's grant. Cadence routes through the existing policy — a spec's `commits:` frontmatter (`user` | `per-task` | `per-phase`) or the user's explicit request — under `git-commits.md`. Never impose a commit cadence on a repo whose owner has not agreed to one.

## 7. Independent verification (Tier 3, optional)

The gauntlet is evidence, not self-authentication. Where stakes justify it, a fresh-context agent attacks the finished work before evidence is signed. This reduces **task-context** correlation, not model correlation, and it is **not a gauntlet layer** — a layer is an executable check with a machine-evaluable result; this returns prose a human must judge.

Dispatch it under `agent-delegation.md`'s **Independent Review Dispatch** contract, which already carries the load-bearing constraints: scope by reference and never the author's narrative, the verdict voided by any later change to the reviewed surface, and a stop after two consecutive rounds producing no new confirmed finding. Use a fresh-context general-purpose agent. The project's named review agents are explicit-request-only and must never be auto-dispatched from inside a loop.

The verifier fixes nothing; findings return through the normal loop, and a gap in the acceptance surface goes to the user rather than to the author to self-amend.

Four states are recorded: `passed` finalizes; `failed` and `blocked` do not; **`not performed`** finalizes only as a declared downgrade, with its reason. Verification is source-state-specific — **a state no verifier saw is `not performed`**, however many rounds preceded it. A behavioral finding fixed after the last verified round therefore ships an unverified state; declare that rather than inheriting the earlier verdict.

## Anti-Patterns

- Writing the test after the implementation and calling it TDD. Without an observed red, the test is unproven.
- Declaring a tier after the work is done, or introducing one at final review.
- Reporting a coverage percentage from a command that exits 0 regardless of the number.
- Adding a test whose only purpose is to touch lines.
- Reporting a mutation score from a runner that never executed the mutants, or whose restores were never verified.
- Treating a green gauntlet as proof the acceptance surface is complete.
- Reading a layer's exit status through a pipe, so the formatter's success is reported as the layer's (`verification-mechanics.md` §1).
- Auto-dispatching a review agent from inside a task or spec loop.
