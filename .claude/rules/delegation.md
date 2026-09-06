1. Resolve the target before delegating

An agent can successfully modify the wrong file or wrong branch.

Apply: Give each worker the exact file/path, required base commit, scope, owned files, and verification command.

2. Parallelize implementation, serialize verification

Parallel work is useful; parallel verification creates ambiguous failures.

Apply: Let agents implement independently, then merge and verify each change on the actual integrated state.

3. Treat agent reports as claims

"Tests passed" from a worker is not independent evidence.

Apply: Before accepting delegated work, verify the diff, changed files, branch base, and relevant tests yourself. Require workers to state what they did not run.

4. Route every unit to the cheapest tier that clears it

This is the delegation-specific instance of the Constitution's cost discipline (priority 7; Golden
Rules 4-6 and 9 — the canonical statement lives there, not here). What this rule adds is the
operational default: NEVER the strongest model. An expensive session spending its own context on
mechanical work is the most common waste here, and it is invisible unless it is named. Cost is a
standing constraint, never re-litigated — but per the priority ladder it never overrides correctness.

Apply: Choose the tier from the work, before spawning.

| Tier     | Route here                                                                                                                                          |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| fast     | Read-only sweeps, greps, index/LEDGER/CONTEXT syncs, mechanical edits, running a `verify:` command — anything decision-complete with a binary check |
| standard | Workers executing a decision-complete plan/roadmap step: implementation, tests, drafting                                                            |
| strong   | Planning, review, verifying strong-tier work, unblocking, and any money/auth/data-loss/concurrency/schema surface                                   |
| frontier | Never auto-selected — explicit user request only                                                                                                    |

The harness mapping for these tiers lives in ONE place, `agent-delegation.md` → Model & Effort
Routing. Never restate a model name here; a model launch must update one table, not two.

Also binding on the parent session, which is usually the expensive one:

- **Do the cheap thing cheaply, or delegate it.** If a unit is a sweep, a sync, or a command whose
  result is a pass/fail, it does not belong in a strong session's context. Delegate it, or run it
  as a bash command whose bulky output goes to a file you read in slices.
- **Never stream large output into context.** Redirect to a file; read with `tail`/`grep`/`sed -n`.
  One oversized output costs more than the work it was checking.
- **A long loop belongs in a fresh, cheaper session.** `spec-workflow.md` is amnesia-first by
  design: a `/spec-run` iteration re-orients from SPEC/ROADMAP/NOTES/LEDGER and needs none of the
  planning session's context. Honour the spec's `executor-tier`; do not inherit a strong session
  into routine execution just because it is already open.
- **Escalate on evidence, not on nerves.** A cheap unit that fails for reasoning quality retries
  ONCE, one tier up (`agent-delegation.md` → Integrating Results). Pre-emptively picking `strong`
  because a task "feels" important is the exact habit this rule exists to stop.
- **Fan-out is sized to the request.** Match agent count to the work, not to a wish to be thorough;
  a trivial ask must never spin up parallel workers.

None of this licenses a worse answer. Cheap-and-wrong is the most expensive outcome there is: when
a tier genuinely cannot clear a unit, say so and escalate rather than shipping a degraded result.
