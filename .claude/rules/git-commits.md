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
- Never `--no-verify`.
- Never `git push` and never rewrite history unless the user asks in the current message. A
  blanket instruction ("do the right thing", "clean this up") is NOT that request: history
  rewriting is the one operation that needs a specific, current-message ask, precisely because
  its damage is invisible in the result.

## Branch, don't commit to `main` — what this repo actually does

Verifiable from `git log --first-parent --merges`: this repository works on branches and merges
them. 98 merge commits, branch names prefixed `feature/`, `fix/`, `chore/`, `refactor/`,
`release/`. The spec missions follow it too — P1.3, P1.5, P2.1, P2.2, P3.1, P4.1 and P4.2 each
landed as a `merge:` commit off an isolated worktree branch, which is `agent-delegation.md`'s
Worktree Lifecycle working as designed.

- **Implementation goes through a branch.** Any commit touching `src/`, `edt/`, `desktop/`,
  `scripts/` or CI config — anything `feat:`, `fix:`, `build:`, `perf:`, `refactor:` — is
  authored on a branch and merged. Checkable: a `feat:` commit touching `src/` whose first parent
  chain shows no merge is a violation.
- **Spec and memory bookkeeping may commit directly to `main`.** Roadmap ticks, LEDGER and NOTES
  entries, `CONTEXT.md`/`JOURNAL.md` checkpoints, rule and knowledge edits — `spec(...)`,
  `docs(...)`, `chore(claude)`. This is long-standing practice here (`a46c24c`, `83cd1c1`,
  `137a8de`, `3f5df51`), and branching a one-line checkbox flip buys nothing.

**NEVER justify a direct-to-`main` implementation commit on the grounds that recent history
already contains some.** That is the exact rationalization used in this workspace on 2026-08-30:
four implementation commits (`22aa357`, `1883426`, `4c88726`, `c8b6f53`) went straight to `main`,
and each one made the next look normal. Drift is not precedent. **YOU MUST read the workflow off
`git log --merges` before claiming a repo has one** — asserting it from the last handful of
commits is how a mistake gets promoted into a convention.

## Relationship to spec and task work

A spec's `commits:` frontmatter decides _whether_ the agent commits at all
(`user` | `per-task` | `per-phase`, see `spec-workflow.md`). This rule decides _how_ any permitted
commit is authored and worded. The two are independent: a `commits: user` spec still means the
agent may make the specific commits that spec authorizes, and those commits follow this rule.
