---
description: Import a portable CLAUDART bundle (produced by /backup) into this project or machine — merges without ever overwriting an existing file.
---

The user's request after `/restore` is merging a bundle's content into the current project. Bundle validation, path rewriting, the merge classes, and the never-overwrite invariant all live in `.claude/scripts/claudart-restore.sh` — this command drives that script, it does not reimplement its merge logic.

1. Confirm the bundle location with the user (`--bundle DIR`), and the target if it isn't the current project (`--target DIR`).
2. Run `bash .claude/scripts/claudart-restore.sh --bundle <dir> [options]` **without `--apply` first** — this always runs the full rewrite + verification + shadow merge + shadow `knowledge-check.sh` gate and reports exactly what would happen, without writing anything. See `--help` for the full flag reference (`--mode full|graft`, `--rewrite-home`, `--allow-secrets`, `--allow-dirty`, `--stage-out DIR` to inspect the rewritten payload before merging).
3. Relay the dry-run report to the user: the merge plan (what's new, what collides, what would sidecar), and the shadow gate result. If the gate fails, nothing was written and nothing will be until the underlying issue is fixed — do not retry with `--apply` on a failed gate.
4. Only after the user reviews the plan, rerun with `--apply` to commit. The script takes backups before touching any pre-existing file and writes a `receipt.txt` alongside them.
5. After a successful `--apply`, relay the script's own routing-table message if it printed one — grafted or sidecared knowledge/rules need `/refactor-memory` and `/learn` follow-up; a divergent session gets parked under `.claude/.portability/conflicts/<epoch>/` for manual review, never auto-resolved.

Never pass `--apply` on the first run, and never pass `--allow-secrets` or `--allow-dirty` on the user's behalf — both bypass a safety rail the user should decide about explicitly.
