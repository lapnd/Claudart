# Contributing to CLAUDART

First off, thank you for considering contributing to **CLAUDART**! It's people like you that make CLAUDART a powerful, universal "brain" template for everyone.

By participating in this project, you agree to abide by our code of conduct.

> **Repository-only workflow.** The Git/GitHub conventions in this file govern contributions to the `lapnd/Claudart` source repository only. They are not part of the CLAUDART runtime/template installed into downstream projects. Downstream repositories own their own issue, branch, commit, PR, and merge workflow.

## How Can I Contribute?

### 1. Reporting Bugs

Before opening a bug report, search existing GitHub Issues and pull requests to avoid duplicate tracking.

For a new bug, open an Issue with:

- a clear, Conventional Commit-style title when practical, such as `fix: ...`;
- the observed problem and expected behavior;
- reproduction steps or the smallest executable example available;
- relevant environment/version details;
- acceptance criteria for considering the bug fixed.

### 2. Suggesting Enhancements

Search existing Issues and pull requests first. For a new enhancement, open an Issue that explains:

- the problem or limitation being addressed;
- the desired outcome;
- why the change is broadly useful to CLAUDART users;
- acceptance criteria;
- important non-goals or compatibility constraints.

### 3. Contributing Code & Agents

We welcome new AI commands and highly specialized agents. If you add a durable Claude-side rule, command, or agent, maintain the Codex-, DeepSeek-, and Pi-native equivalents too when the concept applies to those tools.

Use the repository Git and GitHub workflow below for CLAUDART source changes. Add or modify files within the relevant AI layer: `.claude/` for Claude Code, and `.codex/`, `.deepseek/`, or `.pi/` plus `.agents/skills/` for Codex, DeepSeek, and Pi. Session state lives inside each layer as `CONTEXT.md` and `JOURNAL.md`.

If you've changed APIs, commands, or the knowledge contract, update both English and Vietnamese documentation where a mirrored page exists.

## Git and GitHub Workflow

CLAUDART uses a lightweight GitHub Flow:

**issue when non-trivial → short-lived branch from current `main` → coherent commits → focused PR → merge → branch cleanup**.

`main` is the integration branch. Keep one logical change per branch and pull request, and do not reuse a merged branch for new work.

### Step 1 — Reuse or open an issue

Before creating a branch, search relevant open Issues and pull requests. Reuse existing tracking when it already owns the work.

Create an Issue before branching when the change is a bug, feature, enhancement, workflow/behavior change, compatibility change, non-trivial multi-file/refactor effort, or requires durable acceptance criteria/design discussion.

A separate Issue is optional for a truly trivial, self-explanatory maintenance change such as a typo, tiny documentation correction, or metadata-only edit with no meaningful design decision or follow-up value. Avoid tracking noise for its own sake.

A useful Issue contains **Problem**, **Desired outcome**, **Acceptance criteria**, and **Non-goals**. If implementation discovers a distinct problem outside the tracked scope, create a new Issue instead of silently growing the current change.

### Step 2 — Create a typed branch from `main`

Start from the current `main` branch. When an Issue exists, name the branch:

```text
<type>/<issue-number>-<kebab-case-slug>
```

Examples:

```text
docs/2-git-contribution-workflow
fix/42-knowledge-check-paths
feat/57-agent-state-export
```

For an issue-free trivial change, use `<type>/<kebab-case-slug>`.

Allowed types normally mirror Conventional Commits: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `build`, `perf`, and `revert`.

Branch names should be lowercase, concise, and describe the purpose of the change. Avoid generic prefixes such as `feature/`, `update/`, or `work/`, and avoid personal names or agent/model/tool names unless that name is actually the subject of the change.

Do not branch from another feature branch unless the work is intentionally stacked and both PRs make that dependency explicit.

### Step 3 — Make coherent Conventional Commits

Use this subject format:

```text
<type>(<optional-scope>): <imperative summary>
```

Examples:

```text
docs(workflow): define issue and branch conventions
fix(checker): reject stale knowledge routes
feat(agents): add bounded review role
```

Keep subjects concise (target at most 72 characters), imperative, and specific. Add a body when the reason, trade-off, migration note, or non-obvious validation matters.

Each commit should be one coherent, reviewable step and leave the branch in a sensible state. Avoid final-history messages such as `WIP`, `fix stuff`, `updates`, or `address comments`. Squash or reword temporary fixups before merge when safe.

Do not add `Co-authored-by` trailers for AI models, coding agents, tools, or vendors unless the user explicitly requests that attribution. Do not invent human co-authors.

Do not rewrite or force-push a branch other contributors may be using without explicit coordination.

### Step 4 — Open a focused pull request

Open the PR against `main` unless it is an explicitly documented stacked change. Use a draft PR when the **change itself** is still incomplete or intentionally not ready for review. A tool/runtime limitation that prevents one local validation command from running should be reported in the PR; it does not by itself require the PR to remain draft.

PR titles should be Conventional Commit-compatible and describe the final change. The PR body should include:

- **Summary** — what changed;
- **Rationale** — why it is needed when not obvious;
- **Validation** — exact checks/tests and results, including anything not run;
- **Risks / notes** — compatibility, follow-up, or limitations when relevant;
- `Closes #<issue>` when the PR completes a tracked Issue.

For visible UI changes, include screenshots or equivalent rendered evidence when practical.

Before merge, validate the changed scope. The repository baseline is:

```bash
git diff --check
npm run check
```

Also run targeted validation required by the changed area, inspect the actual changed-file list/patch, and confirm unrelated work did not enter the branch. If an agent/tool environment cannot execute a required command, state that clearly instead of claiming success; the maintainer decides whether the missing check blocks merge or should be run elsewhere. If `main` moved materially or conflicts exist, update the branch safely before merge.

Opening a PR does not authorize merging it. AI-assisted contributors must not merge, enable auto-merge, or close a PR unless the user explicitly asks.

### Step 5 — Merge deliberately

**Squash merge is the default** for ordinary short-lived branches. It keeps `main` concise while allowing iterative commits during review.

Use **rebase merge** only when the branch contains a deliberately curated sequence of independently meaningful commits worth preserving on `main`.

Use a **merge commit** only when preserving branch topology or a multi-commit integration boundary is itself useful and the maintainer intentionally chooses it.

Keep the final merge title Conventional Commit-compatible so `main` history stays searchable by change type.

### Step 6 — Clean up after merge

After merge:

- treat the merged branch as finished and do not add new work to it;
- delete the remote feature branch when possible;
- return to `main`, update it from the remote, and prune stale refs before starting the next change;
- confirm the linked Issue closed, or update/close it explicitly when needed;
- create a fresh Issue/branch for follow-up work rather than reopening the merged branch.

## Repository-Local Agent Guidance

The root `CLAUDE.md` and root `AGENTS.md` in this source repository are intentionally **repository-only** pointers to this contribution workflow. Root `AGENTS.md` is the file Codex, `dsh`, and Pi all auto-load, so it serves every non-Claude harness working on this repository. Both must remain separate from `.claude/CLAUDE.md`, `.codex/AGENTS.md`, `.deepseek/DEEPSEEK.md`, and `.pi/PI.md`, which are part of CLAUDART's installable/runtime templates.

Do not move this repository Git workflow into `.claude/rules/`, `.codex/guidelines/`, `.deepseek/guidelines/`, `.pi/guidelines/`, `.agents/skills/`, `install.sh`, or the downstream integration payload. A downstream project may use trunk-based development, GitFlow, GitHub Flow, Gerrit, stacked PRs, or another process entirely; CLAUDART must not overwrite that choice.

## Understanding the Architecture Structure

If you're contributing new logic, please adhere to our directory structure:

- `.claude/commands/`: CLAUDART slash commands (`/learn`, `/checkpoint`, etc.). Your command files here should detail the steps the AI takes.
- `.claude/agents/`: Highly specialized role-based instruction sets (`reviewer.md`, `architect.md`, etc.). Make sure agent prompts are self-contained and heavily instruct the AI on its specific persona and constraints.
- `.claude/knowledge/`, `.codex/knowledge/`, `.deepseek/knowledge/`, and `.pi/knowledge/`: Durable, **descriptive** project reference — domain, architecture, glossary, and pointers to canonical docs in other folders. Distinct from rules/guidelines (prescriptive). Only the root `INDEX.md` is surfaced by `start`; optional `_maps/`, topic outlines, and the smallest useful sections are loaded on demand.
- `knowledge-management.md` in `.claude/rules/` and in each harness layer's `guidelines/`: the mirrored semantic contract for capture, lifecycle, bounded retrieval, and project-fact classification. Keep their intent in parity.
- `knowledge-check.sh` under `.claude/scripts/`, `.codex/scripts/`, `.deepseek/scripts/`, and `.pi/scripts/`: four byte-identical copies of the dependency-free, read-only mechanical checker. Change and test them as one unit; `tests/knowledge-check/run.sh` asserts the copies stay identical.
- `.codex/`, `.deepseek/`, `.pi/`, and `.agents/skills/`: harness-native source templates. They should preserve the same intent and quality as the Claude side, not act as lossy generated artifacts. `.agents/skills/` is shared by all three harness layers, so keep the `codex-*`, `deepseek-*`, and `pi-*` name prefixes distinct.
- **Invocation forms differ per harness and are not interchangeable.** Codex uses `$codex-<name>` (`TOOL_MENTION_SIGIL` is `$`); dsh invokes a user-invocable skill with `/<name>`; Pi registers skills as `/skill:<name>`. A layer forked from another must have its command form re-checked against that harness's source, not carried over.
- **A specialist file only counts if the harness actually loads it.** Codex requires an `[agents.<role>]` declaration in `.codex/config.toml` with a `config_file`; dsh has no on-disk agent discovery at all (persona lives in the harness profile), which is why its prompts sit in `.deepseek/personas/`; Pi has no sub-agents. When adding a specialist to a layer, verify the load path before assuming parity with Claude.
- **Never write inside a harness's own configuration namespace.** `.dsh/` (settings, skills, cache) belongs to dsh, so the DeepSeek layer lives in `.deepseek/`. Pi owns `.pi/settings.json`, `.pi/skills/`, `.pi/npm/`, `.pi/sessions/`, `.pi/extensions/`, `.pi/agent`, `.pi/SYSTEM.md`, and `.pi/APPEND_SYSTEM.md`; the Pi layer shares `.pi/` but must never add a path in that list.
- `agent-delegation.md` in each layer: the per-harness delegation protocols. Keep each one accurate against that harness's own source, not against the shape of a sibling layer. The DeepSeek protocol describes the real `dsh-tool-subagent` surface (backends, `maxDepth`, background modes, the conditional `provider`/`model`/`reasoning_effort` fields); the Pi protocol states that Pi ships no sub-agents and routes the work inline or to a second Pi instance. Do not copy mechanics between layers, and do not assert a model slug, config key, or tool name you have not read in that harness's repository.
- `.codex/AGENTS.md`: the Codex layer's **instructions file**, pointed at from the root router; it is distinct from this repository's root `AGENTS.md`.
- `.deepseek/DEEPSEEK.md` and `.pi/PI.md`: each harness layer's **instructions file**, which stays in its own directory. The installer never relocates them to the project root; it adds a route line for each inside the root `AGENTS.md` marker block.
- `.agents/AGENTS.md`: the template for the shared root router created when a project has no `AGENTS.md`. Anything the installer writes lives between the `claudart:routes` markers; `tests/install/run.sh` asserts that content outside them survives untouched.
- `.claude/CLAUDE.md`: the installable Claude project-memory template; it is distinct from this repository's root `CLAUDE.md`.
- `INTEGRATE.md`: the AI-native install/upgrade protocol an agent follows to merge CLAUDART into an existing project (the alternative to `install.sh` for non-empty setups). Its "What CLAUDART contains" manifest is orientation only — the agent clones the repo as source of truth — but keep it roughly in sync when you add or remove a top-level piece.

Knowledge-check fixtures must be anonymous and synthetic: do not copy proprietary repository names, absolute home paths, source bodies, credentials, or other downstream project data into this repository.

## Pull Request Review

1. Maintainers review the PR for scope, correctness, mirrored intent across the layers it touches, and validation evidence.
2. Requested changes should stay within the tracked Issue/PR scope; create a separate Issue for unrelated follow-up work.
3. Once approved and sufficiently validated for the change, merge using the strategy above.

Thank you for making CLAUDART smarter! 🚀
