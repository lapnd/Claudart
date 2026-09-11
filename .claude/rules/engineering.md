---
level: law
authority: standard
status: approved
since: 2026-09-03
stale_after: 2027-09-03T00:00:00Z
verified:
  - by: human:lapnd
    at: 2026-09-03T00:00:00Z
enforcer: judgement
load: auto
---

These are the deterministic-execution and evidence practices behind the Constitution's Golden Rules
5 (compute locally) and 11 (prefer deterministic artifacts) and priority 4 (reliability and
reproducibility) — the Constitution ranks the value, this rule is the procedure.

1. Use the project's actual tools and versions

The same command can produce different results with different binaries or versions.

Apply:

command -v <tool>
<tool> --version

Compare them with the project's declared requirements before trusting the result.

2. Do not weaken verification to make it pass

If a check does not test the intended property, do not silently change the interpretation or weaken the check.

Apply: Report the literal result, define a sharper check for the intended property, and test that separately.

3. Do not add unsupported abstractions

Configuration or fields without a real producer and consumer create the appearance of functionality.

Apply: Before adding an abstraction, identify who sets it, who consumes it, and what behaviour it enables.

4. Prefer durable rules over temporary facts

Versions, paths, machine state, and configuration change over time.

Apply: Encode the invariant or verification procedure, not today's specific answer. Re-check measurements before acting on old lessons.

5. Let evidence override assumptions

When evidence contradicts an assumption, correct the model instead of defending the assumption.

Apply: State the correction clearly, update the conclusion, and continue from the new evidence. Before asking the user a question, check the SPEC, project rules, architecture, and existing decisions first.
