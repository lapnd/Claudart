---
name: deepseek-doctor
description: Run a read-only DeepSeek installation health check using the knowledge checker plus semantic audits of memory and workflow wiring.
---

# DeepSeek Doctor

Run a read-only health check on this repository's CLAUDART installation from the DeepSeek side. This is diagnostic only. Do not auto-fix anything. Report findings so the user can run `$deepseek-refactor-memory`, `/refactor-memory`, or edit files manually.

## What to Check

### 1. Required Structure

- A DeepSeek memory index exists: root `DEEPSEEK.md` for an installed downstream project, or `.deepseek/DEEPSEEK.md` for the CLAUDART source template copied by the installer. If both exist, compare them and flag drift.
- `.deepseek/CONTEXT.md` exists. Warn if missing because the user may not have run checkpoint yet.
- `.deepseek/JOURNAL.md` exists. Warn if missing.
- `.deepseek/guidelines/` exists and contains at least `ai-behavior.md`, `code-health.md`, `task-management.md`, `agent-delegation.md`, `spec-workflow.md`, and `knowledge-management.md`.
- `.deepseek/knowledge/` exists with `INDEX.md` (warn if missing — `$deepseek-refactor-memory` will recreate it).
- `.deepseek/scripts/knowledge-check.sh` exists and is readable. Missing checker is **High** because doctor cannot mechanically validate the canonical knowledge contract; do not emulate it with ad hoc parsing.
- `.deepseek/agents/` exists, even if the user removed shipped agents.
- `.deepseek/config.toml` exists. It ships intentionally empty because project-local configuration support varies by DeepSeek harness; treat a missing file as informational and a populated file as valid only if its keys are documented by the harness in use.
- `.deepseek/tasks/` exists with `index.md` and `done/` subdirectory (warn if missing — `$deepseek-plan` will create on first use).
- `.deepseek/specs/` exists with `INDEX.md` and `done/` archive folder (informational if missing — `$deepseek-spec` creates it on first use).
- `.agents/skills/` exists and contains `deepseek-start`, `deepseek-checkpoint`, `deepseek-learn`, `deepseek-doctor`, `deepseek-refactor-memory`, `deepseek-plan`, `deepseek-handoff`, `deepseek-project-discovery`, `deepseek-spec`, and `deepseek-spec-run`.

For each missing path, report which workflow would create or repair it.

### 2. Frontmatter and Metadata Validity

For every `.md` file under `.deepseek/guidelines/`:

- Verify the file starts with YAML frontmatter delimited by `---`.
- Confirm `paths:`, `description:`, `when_to_use:`, and `tags:` are present.
- Confirm `paths:` uses YAML flow sequence style, e.g. `paths: ["src/**/*.ts", "test/**/*.ts"]`. Flag block-list style (`paths:` followed by `- item`) because frontmatter conventions should stay compact and grep-friendly.
- Confirm `tags:` uses inline YAML array style on one line, e.g. `tags: [architecture, nestjs, boundaries]`. Flag block-list style (`tags:` followed by `- item`) because tag indexing depends on single-line frontmatter.
- Confirm `tags:` contains 1-5 lowercase kebab-case tags describing domain or scope.
- Report malformed YAML, missing required keys, or obviously broken frontmatter.

For every `.agents/skills/*/SKILL.md` file:

- Verify the file starts with YAML frontmatter.
- Confirm `name:` and `description:` are present.
- Confirm the skill contains sufficient procedure detail to execute the workflow.

For every `.deepseek/agents/*.md` file:

- Verify the file starts with YAML frontmatter and confirm `name:`, `description:`, and `tools:` are present. CLAUDART ships these as Markdown with YAML frontmatter, the format DeepSeek harnesses read for Claude-compatible agent definitions. If the project instead declares agents in a harness-native format, validate against that harness's documented keys rather than this shape, and do not rewrite a deliberate choice.
- Confirm the declared `tools:` match the agent's purpose: an explorer or a review-only/audit-only agent must not list write tools. A write-capable refiner or worker is valid only when its declared purpose explicitly requires implementation.
- Confirm every write-capable agent clearly defines scope expectations, protects unrelated user work, requires validation, and warns that other agents may be editing in parallel.

### 3. Guideline Path Coverage

For every guideline file in `.deepseek/guidelines/*.md`:

- Read each glob pattern in `paths:`.
- Verify each pattern matches at least one real file in the repo.
- Patterns matching zero files -> flag as possibly dead guideline. Suggest re-scoping or removal.

`paths: ["**/*"]` is allowed for universal guidelines such as `ai-behavior.md`.

### 4. DeepSeek Memory Cross-Linking

- Determine the active memory index to inspect:
  - If root `DEEPSEEK.md` exists, read it.
  - Otherwise read `.deepseek/DEEPSEEK.md` and report that this is the template source copied to root by `install.sh`.
  - If both exist, compare them and flag drift unless the project deliberately documents a different canonical file.
- Confirm the memory index points DeepSeek to `.deepseek/CONTEXT.md`, requires the universal behavior guideline, and tells agents to load other guidelines selectively by task.
- Find the guideline section in the memory index.
- For every explicit `.deepseek/guidelines/*.md` reference there, confirm the target file exists.
- Require direct references for globally relevant workflow guidelines. A task-scoped guideline may instead be discoverable through clear frontmatter and targeted routing; do not require a pointer that would force every guideline to load.
- Flag any instruction that blindly full-reads `.deepseek/guidelines/*.md`.

### 5. AI Behavior Wiring

- Confirm `.deepseek/guidelines/ai-behavior.md` exists.
- Confirm the active memory index references `.deepseek/guidelines/ai-behavior.md`.
- If missing, flag as High severity because universal behavior guidelines are not loaded.

### 5a. Code Health Wiring

- Confirm `.deepseek/guidelines/code-health.md` exists.
- Confirm the active memory index references `.deepseek/guidelines/code-health.md` as the continuous implementation baseline for code and code-adjacent work.
- If missing or unwired, flag as High because ordinary implementation would bypass the shared correctness, scope, behavior-preservation, testing, and validation contract.

### 5b. Agent Delegation Wiring

- Confirm `.deepseek/guidelines/agent-delegation.md` exists.
- Confirm the active memory index references `.deepseek/guidelines/agent-delegation.md`.
- Confirm the guideline states the parent model/reasoning ceiling for implicit delegation. If `.deepseek/config.toml` declares a subagent concurrency cap, confirm it is a positive integer and flag a large value as Medium unless documented, because broad fan-out can create token cost and merge-conflict risk. An empty config is the shipped default and is not a finding.
- Confirm delegation guidance covers the "how" of delegation: decomposition before fan-out, self-contained worker prompts, no shadow-running a delegated question, and one-level delegation depth unless the user asks for recursion. If missing, flag as High because delegated work may be duplicated or unbounded.

### 5c. Knowledge Base Wiring (`.deepseek/knowledge/`)

Skip this section if `.deepseek/knowledge/` does not exist.

Read `.deepseek/guidelines/knowledge-management.md` in full before this audit.

#### Mechanical pass

1. If `.deepseek/scripts/knowledge-check.sh` is missing or unreadable, report **High** and continue only with the semantic pass. Do not invent a replacement parser.
2. Otherwise run `bash .deepseek/scripts/knowledge-check.sh --root .` exactly once with its default failure threshold. The checker is read-only; any changed file is a High-severity integrity failure.
3. Interpret exit `1` as reported contract findings. Exit `2` is a checker usage, precondition, or internal/runtime failure; report it as High and continue only with the semantic pass.
4. Report every checker finding with its path and severity. The checker owns restricted frontmatter grammar, enum/date/name checks, route reachability, map depth, typed relations/scope, local source resolution and source-newer-than-`last_verified` warnings, map/topic size thresholds, and sensitive absolute-path leakage.
5. Treat an empty tier as informational. Treat an ambiguous unindexed file as a review item, not proof that it is active, retired, or safe to delete.

#### Semantic pass

The checker cannot decide whether prose is true or correctly tiered. Audit:

- **Capture quality**: active claims are descriptive, durable beyond current work, current, and evidenced; narrowly scoped claims carry an accurate typed `scope`.
- **Tier separation**: roadmap, backlog, acceptance state, WIP, proposals, and behavioral `MUST`/`NEVER` content do not masquerade as descriptive knowledge.
- **Authority**: `review-needed`, conflicting, superseded, or retired topics are not presented as current authority; `status_note` and evidence explain the state.
- **Ownership**: overlapping facts have one focused canonical owner; related topics link rather than copy. Preserve deliberate external routes and curated hooks.
- **Verification meaning**: `updated` means content edit and `last_verified` means evidence check. Source drift takes priority over age; age alone is only a review nudge.
- **Retrieval shape**: root → topic is acceptable for a small store; root → `_maps/<domain>.md` → topic is the only mapped shape. Maps never nest. A topic over 10 KiB is a reviewed split candidate, not an automatic rewrite.
- **Loading behavior**: `$deepseek-start` reads only the root router and never runs this checker. Detail topics are not globally auto-loaded.

Use bounded source inspection to verify suspicious claims. Never fetch URLs merely to satisfy doctor unless the user separately requested current external verification. Doctor remains read-only and never fixes, promotes, retires, supersedes, or deletes knowledge.

### 6. CONTEXT/JOURNAL Wiring

- Confirm `.deepseek/CONTEXT.md` is referenced in the active memory index.
- `.deepseek/CONTEXT.md` line count must be at most 150. Use `wc -l`; do not full-read the file just to count.
- Report approximate `.deepseek/CONTEXT.md` tokens using both estimates:
  - `wc -w .deepseek/CONTEXT.md | awk '{printf "~%d tokens\n", $1 * 1.3}'`
  - `wc -c .deepseek/CONTEXT.md | awk '{printf "~%d tokens (byte estimate)\n", $1 / 4}'`
- Search the active memory index and `.deepseek/guidelines/` for any operational auto-load instruction for `.deepseek/JOURNAL.md`. If found, flag as Critical.
- Search `.deepseek/CONTEXT.md` for `<!-- since: YYYY-MM-DD -->` comments. Flag items older than 30 days as graduation candidates if they remain in Recent Decisions or otherwise look durable. If an obviously long-lived decision has no `since:` comment, warn that future `$deepseek-checkpoint` should preserve/add one.
- For `.deepseek/JOURNAL.md` integrity, use spot-checks rather than full reads:
  - `head -n 20 .deepseek/JOURNAL.md`
  - `wc -l .deepseek/JOURNAL.md`
  - `tail -n 5 .deepseek/JOURNAL.md`
- Skip deeper validation unless a malformed line is suspected.

### 6b. Task Document Health (`.deepseek/tasks/`)

Skip this section if `.deepseek/tasks/` does not exist.

- Confirm `.deepseek/tasks/index.md` exists. If missing, flag as Medium — `$deepseek-checkpoint` or `$deepseek-plan` should regenerate it.
- Count `.deepseek/tasks/index.md` lines via `wc -l`. Hard ceiling 100. If exceeded, flag as High — trim Recently Done.
- For every `.deepseek/tasks/*.md` file (excluding `index.md` and `done/`), check the YAML frontmatter:
  - Required keys: `slug`, `status`, `created`, `updated`, `agent`, `tags`.
  - `status` must be one of: `planning`, `in-progress`, `awaiting-review`, `blocked`, `done`, `cancelled`.
  - `slug` must match the filename (excluding the `YYYY-MM-DD-NNN-` prefix and `.md` suffix).
  - `tags` must be inline YAML array style with 1-5 lowercase kebab-case tags.
- Flag any task in the top-level folder with `status: done` or `status: cancelled` — these should have been moved to `done/` by `$deepseek-checkpoint`. Suggest running `$deepseek-checkpoint`.
- Apply the **Staleness Thresholds** table in `.deepseek/guidelines/task-management.md` (the canonical numbers — do not redefine them here): flag stalled `in-progress` and stuck `awaiting-review` tasks as Medium severity (for the latter, surface prominently and suggest the user verify and give the close-out signal, or reject), and flag abandoned `planning` tasks as cancellation candidates.
- Cross-check `index.md` Active entries against actual task files: every Active entry must correspond to a real file; every real file with `status` in {planning, in-progress, awaiting-review, blocked} must appear in Active. Mismatches -> suggest `$deepseek-checkpoint` to resync.
- Required sections in every task file body: `## Purpose`, `## Context & Orientation`, `## Plan of Work`, `## Concrete Steps`, `## Validation & Acceptance`, `## Decision Log`, `## Surprises & Discoveries`, `## Outcomes & Retrospective`. Flag missing sections.
- Within `## Context & Orientation`, flag if `### Memory Hints` is missing or empty — that section is the cross-session lifeline.
- Redundant `.gitkeep`: if `.deepseek/tasks/done/.gitkeep` exists AND `.deepseek/tasks/done/` contains at least one real `.md` file, flag as Low severity. The `.gitkeep` exists only to track an empty folder; once real archived tasks live there, it is redundant. Mention that `$deepseek-refactor-memory` will clean it up, or the user can `rm` it manually.

### 6c. Session Handoff Hygiene (`.deepseek/HANDOFF.md`)

`.deepseek/HANDOFF.md` is a transient single-slot baton written by `$deepseek-handoff` and consumed (deleted) by the next `$deepseek-start`. Absent is the normal state — never warn when it is missing.

- If present, it is an unconsumed baton. Report it informationally. If its frontmatter `created:` is more than 7 days old, flag as Medium — reasoning state rots fast; suggest resuming via `$deepseek-start` or deleting it.
- Line count must be at most 150 (use `wc -l`). If exceeded, flag as High — the baton is drifting toward a transcript dump; `$deepseek-handoff`'s distillation rules were not honored.
- Search the active memory index (`DEEPSEEK.md` / `.deepseek/DEEPSEEK.md`) and `.deepseek/guidelines/` for any operational auto-load instruction for `.deepseek/HANDOFF.md`. If found, flag as Critical — the baton is consumed once by `$deepseek-start`, never auto-loaded into every session.
- Multiple handoff artifacts (`HANDOFF-*.md`, dated copies, a `handoff/` directory under `.deepseek/`) -> flag as Medium — violates the single-slot contract; suggest consolidating into one `HANDOFF.md` or deleting stale copies.

### 6d. Spec Workspace Health (`.deepseek/specs/`)

Skip this section if `.deepseek/specs/` does not exist.

- Confirm `.deepseek/specs/INDEX.md` exists. If missing, flag as Medium — `$deepseek-spec` or `$deepseek-checkpoint` should regenerate it.
- Confirm `.deepseek/specs/done/` exists. If missing, flag as Low — `$deepseek-spec` or `$deepseek-checkpoint` should create it.
- INDEX ↔ folders match (both directions): every active `YYYY-MM-DD-<slug>/` folder directly under `.deepseek/specs/` with an active status must be listed under `## Active`; every archived `done/YYYY-MM-DD-<slug>/` folder with `status: done` or `status: cancelled` must be listed under `## Done`; every INDEX entry must point to an existing `SPEC.md` (dead -> Low).
- Ignore `.deepseek/specs/done/` itself when enumerating active spec folders.
- For every active or archived spec folder, confirm the core files exist: `SPEC.md`, `ROADMAP.md`, `NOTES.md`, `LEDGER.md`. Missing -> Medium.
- `NOTES.md` line count ≤ 150 (`wc -l`). Exceeded -> Medium — the working memory is drifting toward a log; distill it and evaluate any durable descriptive candidates under the knowledge capture gate.
- `SPEC.md` frontmatter: required keys `slug`, `status`, `created`, `updated`, `agent`; `status` in {drafting, poc-review, ready, running, blocked, awaiting-final-review, done, cancelled}; folder name must be `created` + `-` + `slug`; `commits` (if present) in {user, per-task, per-phase}.
- For specs at `poc-review` or later: every `artifacts/` path referenced under `## POC Artifacts` must exist on disk. Missing -> Medium (the executor's frozen UI reference is gone).
- ROADMAP disposition consistency: `- [ ] ~~task~~` -> Medium (invalid legacy state; reconcile it to checked + superseded or an explicit blocker before `$deepseek-spec-run`); a checked + struck row missing `superseded by <task-id or reason>` -> Medium; a blocked row missing either its condition or `unlock:` requirement -> Medium. Do not equate every plain unticked row with runnable work — honor dependency notes. `running` where dependency inspection finds no runnable pending row and at least one blocker -> Medium (the circuit-breaker/status transition was missed); `running` with every row terminal -> Medium (the final gate never ran); `blocked` with no explicit blocked row -> Medium (the diagnosis/unlock state is not durable); `blocked` where dependency inspection finds any independent runnable row -> Medium (the whole-loop transition happened too early); `awaiting-final-review` or `done` with any unticked row -> Medium (the final gate contradicts ROADMAP state). Top-level spec folder with `status: done`/`cancelled` -> Low (resync via `$deepseek-checkpoint` to archive it under `done/`). Archived spec folder whose status is not `done`/`cancelled` -> Medium (it is shelved in the wrong place). `status: done`/`cancelled` still listed under `## Active` in INDEX -> Low (resync via `$deepseek-checkpoint`).
- Staleness (mirror the Staleness Thresholds table in `.deepseek/guidelines/task-management.md`; do not redefine the numbers): `running` stale as `in-progress`; `poc-review` and `awaiting-final-review` stale as `awaiting-review` — surface prominently, these wait on the user's verdict; `drafting` stale as `planning`.
- `LEDGER.md` spot-check via `tail -n 15`: recent entries match the `### YYYY-MM-DD HH:MMZ — <event>` heading format. Do not slurp the whole file.

### 7. Anti-Patterns

- Inlined code blocks longer than about 5 lines inside guideline or agent files. These usually violate the no-stale-snippets rule.
- Stale metadata such as `Last Updated: <date>`.
- Hardcoded shell pattern lists inside agent instructions. Agents should use repository tooling or discover patterns from the codebase.
- Vague DeepSeek skills that do not contain sufficient detail to execute the workflow.
- Agent delegation instructions that override the active harness policy or omit bounded decomposition, ownership, and parent validation.
- Worker agent instructions that allow overlapping writes or omit ownership boundaries.
- Mis-tiered guideline (descriptive, not prescriptive): a `.deepseek/guidelines/` file whose body states only facts (how a subsystem works, an integration detail, a domain term, a doc pointer) with no behavioral constraint (`MUST`/`NEVER`/`should`/`avoid`/`always`/`never`) -> flag as Low: it likely belongs in `.deepseek/knowledge/`. Mirror of §5c's descriptive-only check; the boundary runs both ways. Universal guidance like `ai-behavior.md` is exempt.

### 8. Size Sanity

- Count lines in the active memory index. Target is under 100 lines.
- Report approximate tokens using both estimates:
  - `wc -w <active-memory-index> | awk '{printf "~%d tokens\n", $1 * 1.3}'`
  - `wc -c <active-memory-index> | awk '{printf "~%d tokens (byte estimate)\n", $1 / 4}'`
- If bloated, recommend `$deepseek-refactor-memory`.

### 9. Guideline Tag Index And Overlap

- Build a tag index from guideline frontmatter only, e.g. `grep -h '^tags:' .deepseek/guidelines/*.md | sort -u`.
- Flag guidelines missing `tags:`, using block-list tags, or using vague/non-domain tags.
- Use overlapping tags as an initial signal for possible duplicate guidelines; read bodies only when tags or paths suggest overlap.

### 10. Agent Overlap

For all files in `.deepseek/agents/`, compare their `description` and responsibilities.

If two agents share more than 50% of trigger keywords or review scope, flag possible overlap. They may waste tokens or compete for the same work.

## Output Format

```text
# CLAUDART DeepSeek Health Check

## Passing
- [item 1]
- [item 2]

## Warnings
[file:line or section] - [what is wrong] -> [suggested action]

## Errors
[file or section] - [what is broken] -> [suggested action]

## Recommended Next Step
[Single actionable suggestion]
```

If everything passes, output:

```text
CLAUDART DeepSeek installation healthy. <n> guidelines, <n> knowledge entries, <n> agents, <n> skills, <n> specs. Delegation wiring: <ok/warnings>.
```

Reminder: this command is read-only. Never modify files.
