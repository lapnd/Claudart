# Project Agent Instructions

This file is the shared entry point for terminal coding agents that auto-load `AGENTS.md` — Codex CLI, DeepSeek Harness (`dsh`), and Pi all read it from the project root.

CLAUDART keeps each runtime's operating layer in its own directory and routes to it from here. Read the line matching the agent you are, then follow that file and the files it routes to. Ignore the other lines.

<!-- claudart:routes:start -->
<!-- Managed by install.sh. Edit the layer bodies, not these lines. Content outside this block is never touched by the installer. -->
<!-- claudart:routes:end -->

Claude Code does not read this file; its layer is loaded through `.claude/CLAUDE.md`.

Anything you add outside the marked block above is yours and is preserved across installs and upgrades.
