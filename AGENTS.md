# CLAUDART Repository Instructions

This file applies only when working on the **CLAUDART source repository itself**. Codex CLI, DeepSeek Harness (`dsh`), and Pi all auto-load it, so it serves every non-Claude harness working here. It is repository-maintainer guidance, not part of any installable layer, and must not be copied into downstream projects.

- For Git/GitHub operations in this repository — issues, branches, commits, pull requests, merge strategy, and post-merge cleanup — read and follow `CONTRIBUTING.md`.
- Downstream repositories own their own Git workflow. Do not encode CLAUDART's repository contribution policy inside `.claude/`, `.codex/`, `.deepseek/`, `.pi/`, `.agents/`, `install.sh`, or the downstream integration payload.
- For layer-specific CLAUDART operating-layer guidance, also follow the file matching the harness you are, and the files it routes to:
  - Codex CLI → `.codex/AGENTS.md`
  - DeepSeek Harness (dsh) → `.deepseek/DEEPSEEK.md`
  - Pi → `.pi/PI.md`
- In a downstream project these routes live inside a managed `claudart:routes` block in the project's own root `AGENTS.md`. This repository lists them inline because this file is maintainer guidance, not an installed router.
- Keep repository contribution changes scoped and preserve parity only where the underlying CLAUDART product concept is actually mirrored across Claude, Codex, DeepSeek, and Pi.
