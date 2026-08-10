---
description: Audit where this session's tokens went and what would make the next session cheaper — boot cost, session behavior, memory hygiene — then apply approved fixes. Run when auto-compact fires frequently.
---

You are running a token-usage audit. Frequent auto-compaction is the trigger symptom; your job is to find the cause, rank the fixes by estimated savings, and route each fix to its rightful owner. **Read-only until Step 5** — you measure and diagnose first, apply only what the user approves.

Estimate tokens as `bytes / 4` and label every number an estimate. Never full-read `JOURNAL.md` or task/spec bodies to audit them — size them with `wc -l` / `wc -c`.

## Step 1 — Boot-cost audit (what every session pays before work starts)

Enumerate the always-loaded surface and estimate each item:

1. `.claude/CLAUDE.md` itself, plus every file it `@`-imports (resolve each `@path` and size it).
2. `.claude/CONTEXT.md`.
3. Every `.claude/agents/*.md` frontmatter `description:` (these load into every session's agent roster).
4. **Parent and global instruction files** — check `~/.claude/CLAUDE.md` and every ancestor directory between `$HOME` and the repo root for a `CLAUDE.md`. These load into every session here and are invisible from inside the repo; a foreign or stale one is pure waste and may carry conflicting instructions.
5. `.claude/settings*.json` — enabled MCP servers (their tool schemas cost tokens every session; flag any not used by this project).

Compare against budgets: the whole boot surface should stay under **~3k tokens**; any single always-on item over **~1k** needs a stated justification. Flag specifically:

- A workflow rule still `@`-imported when a trigger line + digest would do (see `CLAUDE.md` → Domain Rules for the pattern).
- A parent/global `CLAUDE.md` that doesn't apply to this project.
- Agent descriptions that could be tightened without losing routing signal.

## Step 2 — Session-behavior walk (where this session's tokens went)

If this session has meaningful history, walk it chronologically — same pass `/learn` makes for behavior, but scoring token waste. Catalog occurrences of:

- **Repeated reads**: the same file read twice with no edits in between — the first read should have left a note in the task file, NOTES, or CONTEXT.
- **Whole-file reads** of large files where a section (`offset`/`limit`) or a targeted grep would have answered the question.
- **Inline command floods**: command output over ~100 lines streamed into context instead of redirected to a file and read with `tail`/`grep` (see `ai-behavior.md` → output hygiene).
- **Human-doc reads**: README/WORKFLOW/GUIDE content read despite their agent-skip markers, when the binding rule would have sufficed.
- **Oversized fan-out**: subagents spawned for work a few local tool calls would finish, or subagent reports relayed wholesale instead of distilled.
- **Re-derivation**: facts re-established that CONTEXT, NOTES, or knowledge already held — a routing failure, not a reading failure.

Count occurrences and estimate the per-occurrence cost; recurring patterns are `/learn` candidates, one-offs are just noted.

## Step 3 — Memory hygiene sweep (mechanical, sizes only)

- `CONTEXT.md` line count vs its 150-line ceiling; items with `since:` stamps that no longer earn their place (route to `/checkpoint`, don't trim here).
- Knowledge topics approaching the 10 KiB split-candidate bound; root INDEX vs its word budget.
- Active spec `NOTES.md` vs its 150-line ceiling; LEDGER read habits (tail-only is correct).
- Task files whose Memory Hints have grown past ~40 lines of prose.

## Step 4 — Diagnose the compaction pattern

Name the dominant cause before proposing fixes:

- **Boot cost dominates** (heavy always-on surface) → trigger-line conversions, parent-file cleanup, MCP pruning. Biggest lasting savings.
- **Behavior dominates** (repeated reads, inline floods) → `/learn` candidates so the fix becomes a rule, not a one-session resolution.
- **Long spec sessions compact often** → this is **not** a trimming problem. Rotation exists for exactly this; recommend a tighter rotation cadence (fewer tasks per session) and point at the rule file's Session Rotation section.
- **Genuinely large working set** (big files, wide missions) → recommend delegation patterns (fresh-context subagents per sweep) over fighting compaction.

## Step 5 — Report, then apply only what's approved

```markdown
## Token Audit — <date>

**Compaction diagnosis**: <dominant cause, one sentence>
**Boot surface**: ~<n>k tokens (budget ~3k) — <over/under>

| #   | Finding   | Est. cost        | Fix   | Owner                                   |
| --- | --------- | ---------------- | ----- | --------------------------------------- |
| 1   | <finding> | ~<n> tok/session | <fix> | apply-now / /checkpoint / /learn / user |

**Apply now (needs your ok)**: <numbered subset — mechanical, safe edits only:
trigger-line conversions, agent-skip markers, description tightening>
**Routed**: <items sent to /checkpoint or /learn, and why>
**Yours**: <user-level items with the exact command to run — parent CLAUDE.md,
MCP config, model-tier choices>
```

Wait for explicit approval, apply only the approved subset, then re-measure the boot surface and report the delta.

## Boundaries

- Read-only until the user approves the apply subset; never edit live state semantics (CONTEXT content decisions belong to `/checkpoint`).
- Behavioral fixes become rules only through `/learn` — this command surfaces candidates, it does not write rules.
- **Never trade correctness for tokens**: no weakening rules, no skipping verifies, no shrinking digests below their binding content.
- One run's findings are evidence, not policy — only recurring findings graduate.
