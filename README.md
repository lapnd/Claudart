# CLAUDART

[Tiếng Việt](README_VI.md) · [Workflow guide](docs/WORKFLOW.md)

CLAUDART is a repository-local workflow for Claude Code, Codex CLI, DeepSeek Harness (`dsh`), and Pi. It keeps session state, implementation plans, project knowledge, and agent instructions in versioned Markdown files alongside the code.

The four runtime layers are independent. Install any one of them, or several. CLAUDART does not require a database, daemon, or hosted service.

## What it adds

- **Session orientation:** start a new session from current state, active work, project knowledge, and recent Git history.
- **Persistent plans:** keep multi-step work in task files instead of leaving the plan in chat.
- **Large-work specifications:** define and execute work that spans several tasks or sessions under one approved specification.
- **Project knowledge:** store durable facts separately from behavioral rules and temporary work state.
- **Session handoff:** preserve an unfinished investigation when the context window is nearly full.
- **Maintenance tools:** check and normalize the memory structure without introducing a separate service.
- **On-demand specialists:** use focused agents for code health, security review, and visual review only when requested.

## Installation

### New project

The default installation adds the Claude Code layer:

```bash
curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash
```

Choose a layer explicitly when needed:

```bash
# Claude Code
curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash -s -- --claude

# Codex CLI
curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash -s -- --codex

# DeepSeek Harness (dsh)
curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash -s -- --deepseek

# Pi
curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash -s -- --pi

# Claude Code and Codex
curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash -s -- --both

# All four
curl -fsSL https://raw.githubusercontent.com/vankhaivn/Claudart/main/install.sh | bash -s -- --all
```

The installer copies missing files and skips files that already exist. `--force` overwrites existing files and should be used only when that is intentional.

### The shared `AGENTS.md` router

Codex, `dsh`, and Pi all auto-load `AGENTS.md` from the project root. Rather than fighting over that one filename, CLAUDART treats it as a shared router: each layer keeps its instructions in its own directory (`.codex/AGENTS.md`, `.deepseek/DEEPSEEK.md`, `.pi/PI.md`) and the installer adds one route line pointing at it.

```markdown
<!-- claudart:routes:start -->

- Codex CLI → follow `.codex/AGENTS.md`
- DeepSeek Harness (dsh) → follow `.deepseek/DEEPSEEK.md`
- Pi → follow `.pi/PI.md`

<!-- claudart:routes:end -->
```

The installer only ever writes inside those markers. If your project already has an `AGENTS.md`, its content is preserved exactly and the block is appended. Claude Code does not read this file; its layer loads through `.claude/CLAUDE.md`.

`.agents/skills/` is likewise shared by all three harnesses. The installer copies only the skills belonging to the layer you asked for, so a single-layer install stays clean; with several layers installed, every harness sees every prefix (`codex-*`, `deepseek-*`, `pi-*`) and you invoke the one matching your layer.

### Existing project or existing CLAUDART installation

Do not use the installer as a merge tool. It can copy or overwrite files, but it does not reconcile custom instructions, live state, tasks, specifications, or project knowledge.

Ask your coding agent to follow the integration protocol instead:

> Read https://raw.githubusercontent.com/vankhaivn/Claudart/main/INTEGRATE.md and follow it to integrate or update CLAUDART in this project. Preserve project-specific content and show me the proposed changes before writing them.

The protocol compares the current project with the current `main` branch and separates stale CLAUDART files from project-authored customizations.

### First run

After installation or reconciliation, run the health and normalization sequence once:

| Claude Code        | Codex CLI                | DeepSeek (dsh)              | Pi                          |
| ------------------ | ------------------------ | --------------------------- | --------------------------- |
| `/doctor`          | `$codex-doctor`          | `/deepseek-doctor`          | `/skill:pi-doctor`          |
| `/refactor-memory` | `$codex-refactor-memory` | `/deepseek-refactor-memory` | `/skill:pi-refactor-memory` |
| `/doctor`          | `$codex-doctor`          | `/deepseek-doctor`          | `/skill:pi-doctor`          |

Then begin a normal session with `/start`, `$codex-start`, `/deepseek-start`, or `/skill:pi-start`.

## Daily workflow

| Purpose                                           | Claude Code        | Codex CLI                | DeepSeek (dsh)              | Pi                          |
| ------------------------------------------------- | ------------------ | ------------------------ | --------------------------- | --------------------------- |
| Orient a session                                  | `/start`           | `$codex-start`           | `/deepseek-start`           | `/skill:pi-start`           |
| Create a persistent implementation plan           | `/plan <task>`     | `$codex-plan <task>`     | `/deepseek-plan <task>`     | `/skill:pi-plan <task>`     |
| Define large, multi-session work                  | `/spec <mission>`  | `$codex-spec <mission>`  | `/deepseek-spec <mission>`  | `/skill:pi-spec <mission>`  |
| Execute an approved specification                 | `/spec-run <slug>` | `$codex-spec-run <slug>` | `/deepseek-spec-run <slug>` | `/skill:pi-spec-run <slug>` |
| Preserve an unfinished investigation              | `/handoff`         | `$codex-handoff`         | `/deepseek-handoff`         | `/skill:pi-handoff`         |
| Rebuild current state at a natural stopping point | `/checkpoint`      | `$codex-checkpoint`      | `/deepseek-checkpoint`      | `/skill:pi-checkpoint`      |
| Turn recurring behavior into a rule               | `/learn`           | `$codex-learn`           | `/deepseek-learn`           | `/skill:pi-learn`           |
| Check the installation                            | `/doctor`          | `$codex-doctor`          | `/deepseek-doctor`          | `/skill:pi-doctor`          |

Use a task plan for multi-step or multi-file implementation. Use a specification when the work contains several phases, needs a proof-of-concept or acceptance scenarios, or must continue across many sessions.

## How state is organized

| Location                  | Purpose                                         | Loading behavior                                    |
| ------------------------- | ----------------------------------------------- | --------------------------------------------------- |
| `CONTEXT.md`              | Current project and work state                  | Read at session start; rewritten by checkpoint      |
| `JOURNAL.md`              | Retired history                                 | Append-only; not loaded automatically               |
| `rules/` or `guidelines/` | Prescriptive instructions for agent behavior    | Loaded when applicable                              |
| `knowledge/`              | Durable descriptive facts about the project     | Routed through `INDEX.md`; details loaded on demand |
| `tasks/`                  | Persistent implementation plans                 | Read when a task is active or resumed               |
| `specs/`                  | Large-work specifications and execution records | Read when a specification is active                 |
| `HANDOFF.md`              | One-session reasoning handoff                   | Consumed by the next start, then removed            |

The important boundary is simple: **rules say how the agent should work; knowledge records what is true about the project; tasks and specifications record work in progress.**

## Specialized agents

These agents never run automatically. The Claude and Codex layers ship them as definitions their harness loads. The DeepSeek layer ships the same prompts in `.deepseek/personas/` as sources for a subagent `persona`, because dsh has no on-disk agent discovery. The Pi layer omits them: Pi has no built-in subagents, so `.pi/guidelines/agent-delegation.md` routes that work inline or to a separate Pi instance instead.

| Agent               | Role                                                                                                                    |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Clean-code reviewer | Makes a scoped, behavior-preserving code-health improvement and validates it. A review-only request keeps it read-only. |
| Security auditor    | Performs a read-only, evidence-based security audit and writes a report.                                                |
| UI visual critic    | Reviews rendered UI or visual output on explicit request.                                                               |

The parent agent remains responsible for scope, integration, and validation of delegated work.

## Developing CLAUDART

This repository uses Prettier for Markdown and Bash-based checks for the installer, knowledge contract, and specification workflow.

```bash
npm ci
npm run check
```

To use the repository's pre-commit hook:

```bash
npm run hooks:install
```

## Documentation

- [Workflow guide](docs/WORKFLOW.md)
- [Vietnamese workflow guide](docs/WORKFLOW_VI.md)
- [Integration and upgrade protocol](INTEGRATE.md)
- [Contributing](CONTRIBUTING.md)

## License

CLAUDART is available under the [MIT License](LICENSE).
