---
name: codex-optimize
description: Audit where this session's tokens went and what would make the next session cheaper — boot cost, session behavior, memory hygiene — then apply approved fixes. Run when auto-compact fires frequently.
---

# Codex Optimize

You are running a token-usage audit. Frequent auto-compaction is the trigger symptom; your job is to find the cause, rank the fixes by estimated savings, and route each fix to its rightful owner. **Read-only until Step 5** — you measure and diagnose first, apply only what the user approves.

Estimate tokens as `bytes / 4` and label every number an estimate. Never full-read `.codex/JOURNAL.md` or task/spec bodies to audit them — size them with `wc -l` / `wc -c`.

## Step 1 — Boot-cost audit (what every session pays before work starts)

Enumerate the always-loaded surface and estimate each item:

1. `AGENTS.md` at the project root, and any guideline files a session reads blindly rather than on their Context Loading triggers.
2. `.codex/CONTEXT.md`.
3. Every `.codex/agents/*.toml` — their descriptions and any prompt content loaded per session.
4. **Parent and global instruction files** — check `~/.codex/AGENTS.md` and every ancestor directory between `$HOME` and the repo root for an `AGENTS.md`. A foreign or stale one is pure waste and may carry conflicting instructions.
5. `.codex/config.toml` — MCP servers or providers configured but unused by this project.

Compare against budgets: the whole boot surface should stay under **~3k tokens**; any single always-on item over **~1k** needs a stated justification. Flag specifically:

- A guideline read every session that the Context Loading trigger table (AGENTS.md) says should load on demand.
- A parent/global `AGENTS.md` that doesn't apply to this project.
- Agent TOML descriptions that could be tightened without losing routing signal.

## Step 2 — Session-behavior walk (where this session's tokens went)

If this session has meaningful history, walk it chronologically — same pass `$codex-learn` makes for behavior, but scoring token waste. Catalog occurrences of:

- **Repeated reads**: the same file read twice with no edits in between — the first read should have left a note in the task file, NOTES, or CONTEXT.
- **Whole-file reads** of large files where a targeted `rg` or a bounded section read would have answered the question.
- **Inline command floods**: command output over ~100 lines streamed into context instead of redirected to a file and read with `tail`/`rg` (see `ai-behavior.md` → output hygiene).
- **Human-doc reads**: README/WORKFLOW/GUIDE content read despite their agent-skip markers, when the binding guideline would have sufficed.
- **Oversized fan-out**: subagents spawned for work a few local tool calls would finish, or subagent reports relayed wholesale instead of distilled.
- **Re-derivation**: facts re-established that CONTEXT, NOTES, or knowledge already held — a routing failure, not a reading failure.

Count occurrences and estimate the per-occurrence cost; recurring patterns are `$codex-learn` candidates, one-offs are just noted.

## Step 3 — Memory hygiene sweep (mechanical, sizes only)

- `.codex/CONTEXT.md` line count vs its 150-line ceiling; items with `since:` stamps that no longer earn their place (route to `$codex-checkpoint`, don't trim here).
- Knowledge topics approaching the 10 KiB split-candidate bound; root INDEX vs its word budget.
- Active spec `NOTES.md` vs its 150-line ceiling; LEDGER read habits (tail-only is correct).
- Task files whose Memory Hints have grown past ~40 lines of prose.

## Step 4 — Diagnose the compaction pattern

Name the dominant cause before proposing fixes:

- **Boot cost dominates** (heavy always-on surface) → trigger-based loading, parent-file cleanup, config pruning. Biggest lasting savings.
- **Behavior dominates** (repeated reads, inline floods) → `$codex-learn` candidates so the fix becomes a guideline, not a one-session resolution.
- **Long spec sessions compact often** → this is **not** a trimming problem. Rotation exists for exactly this; recommend a tighter rotation cadence (fewer tasks per session) and point at the guideline file's Session Rotation section.
- **Genuinely large working set** (big files, wide missions) → recommend delegation patterns (fresh-context explorers per sweep) over fighting compaction.

## Step 5 — Report, then apply only what's approved

```markdown
## Token Audit — <date>

**Compaction diagnosis**: <dominant cause, one sentence>
**Boot surface**: ~<n>k tokens (budget ~3k) — <over/under>

| #   | Finding   | Est. cost        | Fix   | Owner                                               |
| --- | --------- | ---------------- | ----- | --------------------------------------------------- |
| 1   | <finding> | ~<n> tok/session | <fix> | apply-now / $codex-checkpoint / $codex-learn / user |

**Apply now (needs your ok)**: <numbered subset — mechanical, safe edits only>
**Routed**: <items sent to $codex-checkpoint or $codex-learn, and why>
**Yours**: <user-level items with the exact command to run>
```

Wait for explicit approval, apply only the approved subset, then re-measure the boot surface and report the delta.

## Boundaries

- Read-only until the user approves the apply subset; never edit live state semantics (CONTEXT content decisions belong to `$codex-checkpoint`).
- Behavioral fixes become guidelines only through `$codex-learn` — this skill surfaces candidates, it does not write guidelines.
- **Never trade correctness for tokens**: no weakening guidelines, no skipping verifies, no shrinking digests below their binding content.
- One run's findings are evidence, not policy — only recurring findings graduate.
