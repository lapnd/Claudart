---
name: codex-backup
description: Export a portable CLAUDART bundle — the project .codex/ layer plus this project's Codex session history — for moving to another machine or grafting into another project.
---

# Codex Backup

The user's request after `$codex-backup` is producing a portable bundle of this project's CLAUDART content: session transcripts, per-project memory, knowledge, rules, tasks, specs, and prompt history. Bundle format, path-token handling, and every safety rail (allow-list collection, secret scan, atomic write) live in `.codex/scripts/claudart-backup.sh` — this skill drives that script, it does not reimplement it.

1. Confirm the destination with the user if not stated (`--out DIR`, must not already exist).
2. Run `bash .codex/scripts/claudart-backup.sh --out <dir> [options]` — see `--help` for the full flag reference (`--sessions all|recent|none`, `--history yes|no`, `--project-scope all|graft`, `--alias-root`, `--archive`, `--dry-run`).
3. The script's own report is the source of truth: files included, secret-scan result, foreign project roots disclosed. Relay it to the user verbatim rather than summarizing away detail — especially the foreign-root disclosure and the secret-scan NOTE, both of which exist so nothing is silently hidden.
4. If the secret scan finds something, the bundle is withheld by default (exit 1). Do not pass `--allow-secrets` on the user's behalf — surface the findings and let them decide.
5. Point the user at `.codex/scripts/claudart-restore.sh` (or `$codex-restore`) as the next step, and mention the bundle's `README.txt` documents exactly what is and isn't inside.

Never read or bundle configuration/credentials yourself outside the script — collection is an allow-list enforced in the script, not something to second-guess by hand-copying files.
