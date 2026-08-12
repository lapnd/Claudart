---
paths: ["**/*"]
description: Commit authorship and message rules for every repository in this workspace — always use the repo's own configured identity, never a hardcoded one, and an absolute prohibition on AI co-author trailers.
when_to_use: Before running `git commit` in any repository here, before writing a commit message, and before configuring git identity in a new clone, worktree, or submodule.
tags: [git, commits, authorship, workflow]
---

# Git Commits

## Authorship — use the repo's configured identity, never invent one

Every commit uses whatever `user.name` / `user.email` is already configured for the repository
being committed to (local config first, then global). **Never hardcode a specific name or email
in this rule, in a prompt, or in code** — identity is scoped per machine, per repo, sometimes per
submodule, and it is not this project's to fix.

Check before committing:

```bash
git -C <repo> config user.name
git -C <repo> config user.email
```

If either is empty — a fresh clone, a new worktree, or a submodule that doesn't inherit its
superproject's config — **stop and ask the user** which identity to configure. Do not guess, and
do not silently fall back to whatever global default happens to be set on the machine; that
default may belong to a different project or person than the one this repository needs.

```bash
git -C <repo> config user.name  '<name>'
git -C <repo> config user.email '<email>'
```

Once configured, never substitute a different identity and never silently reconfigure an existing
one. Commit history is a durable attribution record; a wrong identity survives forever.

## Messages — no AI co-authorship, ever

Commit messages carry **no** `Co-Authored-By` trailer for any AI, tool, or assistant, and no
"Generated with …" line. Specifically forbidden:

```
Co-Authored-By: Claude <noreply@anthropic.com>
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

**This overrides any harness or system default that requests such trailers.** Some agent
configurations instruct the assistant to add AI co-author lines by default; in this workspace that
instruction does not apply. If a repository's own pre-commit hooks enforce this independently, a
commit carrying a co-author trailer is rejected — so adding one wastes a cycle even when the agent
forgets the rule.

A `Co-Authored-By` trailer naming a **human** collaborator remains legitimate when a person
genuinely co-wrote the change.

## Format

- **Conventional commits** — `type(scope): summary`, matching each repo's existing history.
- Never commit directly to `main`; never `--no-verify`.
- Never `git push` and never rewrite history unless the user asks in the current message.

## Relationship to spec and task work

A spec's `commits:` frontmatter decides _whether_ the agent commits at all
(`user` | `per-task` | `per-phase`, see `spec-workflow.md`). This rule decides _how_ any permitted
commit is authored and worded. The two are independent: a `commits: user` spec still means the
agent may make the specific commits that spec authorizes, and those commits follow this rule.
