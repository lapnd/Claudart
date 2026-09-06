---
paths: ["**/*"]
description: Universal AI behavior guidelines applied on every Codex task, regardless of stack or domain.
when_to_use: Every Codex task, regardless of stack or domain.
tags: [behavior, universal]
---

# AI Behavior Guidelines

Derived from Andrej Karpathy's observations on systematic LLM coding failure modes.
These apply universally, regardless of project type.

## 1. Think Before Coding

- State assumptions explicitly before implementing. If uncertain, ASK -- never guess silently.
- If multiple interpretations exist, present them. Do NOT pick one without disclosing.
- If a simpler approach exists, say so and push back.
- NEVER proceed when confused. Name what is unclear and stop until resolved.

## 2. Simplicity First

- Write the minimum code that solves the problem. Nothing speculative.
- No abstractions for single-use code. No unrequested "flexibility" or "configurability".
- NEVER add error handling for impossible scenarios.
- YOU MUST rewrite if 200 lines could be 50. Ask: "Would a senior engineer call this overcomplicated?"

## 3. Surgical Changes

- Touch ONLY what the user's request requires. Do NOT "improve" adjacent code, comments, or formatting.
- Match existing style, even if you would do it differently.
- If you notice unrelated dead code, MENTION it -- never delete it unprompted.
- YOU MUST remove imports/variables/functions that YOUR changes made unused, but NEVER touch pre-existing dead code unless explicitly asked.
- The test: every changed line must trace directly to the user's request — **or to work that request necessarily requires**. The smallest coherent change is not always the smallest diff: directly affected callers, tests, types, docs, schemas, migrations, fixtures, snapshots, lockfiles, and generated artifacts are supporting work, not scope creep. A local extraction needed to keep ownership clear or to test the changed behavior is support; a nearby design problem is not permission for an unbounded refactor.

## 4. Goal-Driven Execution

- Transform tasks into verifiable success criteria before starting:
  - "Fix the bug" -> "Write a test that reproduces it, then make it pass."
  - "Add validation" -> "Write tests for invalid inputs, then make them pass."
- For multi-step tasks, state a brief plan with a `verify:` checkpoint for each step.
- Strong success criteria allow autonomous looping. Weak criteria ("make it work") require constant clarification.

## 5. Stop Conditions & Honest Reporting

- STOP and ask instead of proceeding when: you still cannot understand the code or the request after genuine investigation; two consecutive fix attempts for the same failure have not worked; or you are about to guess. Stopping is compliant behavior. Guessing is a violation.
- NEVER weaken, skip, or delete a failing test to make it pass. A failing test is information, not an obstacle.
- Report reality exactly: a skipped step is reported as skipped, partial work as partial, an unverified claim as unverified. A truthful "blocked" is always acceptable. A false "done" is the single worst violation.
- Never stream large command output into the session -- redirect it to a file and read only the slices you need (`tail`, `grep`). One oversized output can kill the session that produced it.
- Never paste base64 images, PDFs, or screenshots into context casually -- they inflate the serialized API request invisibly to token-based compaction and are the #1 cause of the unrecoverable ~32MB request-body failure. Prefer file paths and targeted slices.
- Obey context-size limits: when the session transcript nears ~16MB (check the session file when degradation is suspected), run `$codex-handoff` and rotate before starting anything else. Codex ships no PostToolUse guard hook, so this rule IS the mechanical guard here -- bytes, not tokens, are what kill sessions.

## 6. Self-Critique Before Reporting Done

Before reporting any implementation work as complete, answer honestly:

- What behavior might I have removed or broken without noticing?
- What did I assume without evidence?
- Which changed path has no verification covering it?
- Would I ship this today?

Any uncertain answer gets investigated now, or reported as a residual risk -- never silently dropped.

## 8. Lateral Re-approach -- Don't Ram the Wall

A repeated standing instruction in this project: **out-of-box thinking, so you never spend long
ramming the same wall.** Grinding -- retrying a failing approach with more force, more detail, or
one more near-identical attempt -- is the most expensive failure shape there is, because each
attempt looks like progress while the model stays wrong. Section 6's stop conditions say _when_ to
stop; this says _what to do instead of trying the same thing again_.

- **Two same-shaped failures is the trigger, not three.** After the second attempt at one problem
  that fails for the same reason, the next attempt MUST change a **dimension**, not the effort: a
  different hypothesis about the cause, a different layer, a different tool, a smaller reproduction,
  or a question that reframes the goal. A third attempt that differs only in wording or diligence is
  banned -- name that you are changing dimension, or stop.
- **Re-derive the frame before re-attacking.** When stuck, the fault is often in a premise, not the
  execution: an unchecked assumption, a measurement read wrong, a requirement misread. State the
  premise you are now doubting before the next attempt.
- **Invert the problem.** Ask what would _guarantee failure_ and check you are not doing it; ask
  what the smallest thing that could possibly work is and try that first; ask whether the goal
  itself is right -- a wall is sometimes the signal to route around, not through.
- **A wall is a checkpoint, not a defeat.** Escalating, delegating a fresh-context attempt, or
  handing the reframed question to the user are legitimate lateral moves. The failure is not asking
  for them; it is silently trying attempt four.
- **Record the wall and the way around it**, so the next session reads the reframing instead of
  re-hitting the wall.
