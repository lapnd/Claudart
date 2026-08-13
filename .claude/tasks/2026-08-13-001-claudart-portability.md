---
slug: claudart-portability
status: in-progress
created: 2026-08-13
updated: 2026-08-13
agent: claude
delegation: strategy-only
tags: [portability, backup, restore, knowledge, sessions]
---

# CLAUDART Portability — `/backup` and `/restore`

## Purpose

> "create import/export scripts to allow user import claude sessions/data and claudart data/memory of a project. There is a case that user work on same project but different machinine or different project but want ultikize sessions/knowldge/context of claude and claudart"
>
> Follow-up constraints from the same session, verbatim:
> "make sure to have merge ability when have same file, never override file"
> "smart/intelligent merge"
> "we import context/memory/database/knowdeldge only, no import key/token of claude ."

A user moving to a new machine, or starting a new project, can carry a CLAUDART project's _content_ with them — session transcripts, per-project memory, knowledge, rules, tasks, specs, and prompt history — as a self-describing bundle. They verify it works by running `/backup`, moving the bundle, running `/restore --apply` on the other side, and finding their sessions in `/resume` and their knowledge passing `knowledge-check.sh`.

## Context & Orientation

### Related Code

- `.claude/scripts/knowledge-check.sh` — **the style reference** for both new scripts (CLI shape, traps, `SEP` records, exit codes). Also the post-merge validator: it accepts `--root DIR` and `--layer`, which is what makes shadow-validation possible.
- `install.sh:188-195` — `is_template_path()`. Its exact `case` is reused to compute `provenance: template|state` per bundled project file. Also proves no installer change is needed for new `.claude/scripts/*` and `.claude/commands/*`.
- `install.sh:246-258` — `copy_tree`; walks only the source tree, so extra files in a target are never deleted.
- `tests/knowledge-check/run.sh` — the TAP-ish harness to clone: `pass()`/`fail()`, `materialize()`, `snapshot()`, `run_checker()` capturing `LAST_STATUS`, trap cleanup.
- `package.json:6` — `check:shell` is a **hardcoded file list**, not a glob. `package.json:9` — the `check` chain.
- `.claude/rules/knowledge-management.md` — frontmatter contract, route grammar, reachable-exactly-once invariant.
- `.claude/rules/task-management.md` — `YYYY-MM-DD-NNN-slug` naming, `slug:`↔filename invariant, index 100-line ceiling.
- `.claude/rules/spec-workflow.md:29-30` — spec folder invariant `foldername == <created>-<slug>`.

### Related Docs

- `/Users/administrator/.claude/plans/continue-glowing-swing.md` — **the approved plan; read it first.** Carries the full merge strategy table, the rewrite pair table, and the verification design.
- `CONTRIBUTING.md:46-56` — per-directory contract; synthetic-fixture rule; `npm run check` before PR.
- `INTEGRATE.md:28-48` — the "what CLAUDART contains" manifest to keep in sync.

### Memory Hints

Things a fresh session must not re-derive:

- **Environment is Bash 3.2.57 + BSD sed.** No `local`, no arrays, no `[[ ]]`, no `<<<`, no `+=`, no `mapfile`. **Never `sed -i`** — BSD requires an argument, GNU does not; write a temp file and `mv`. `-E` is portable for ERE; avoid `\+`, `\|`, `\?`.
- `jq` and `python3` exist on this machine but are **not guaranteed** on a target. The POSIX path is what ships and what gets tested. This is why the bundle carries `INVENTORY` (plain `cksum` format) in addition to `MANIFEST.json` — restore must never parse JSON in shell.
- **Never pipe into `while`** — no `pipefail`, so subshell variable loss is silent. Use `while … done <"$FILE"`.
- **`awk -v` processes backslash escapes in the value.** Pass paths via `ENVIRON`, not `-v`, or a path containing `\` is silently mangled.
- **Chained `sed -e` rescans prior output.** Since the home dir is always a strict prefix of the project path, chained expressions are a live corruption path. The rewrite must be a single-pass `index()` scanner that advances over the _input_.
- **The project-dir mangling is lossy** (`/`→`-`, and `-` is legal in paths). Never un-mangle. Resolve the target dir by observing a `"cwd":"<T>"` match on disk; compute only as fallback.
- **A `head -1` probe for `cwd` finds nothing.** Line 1 of every transcript is `{"type":"mode",…}`; the first `cwd` lands on line 3-4. Probe ~50 lines.
- **Secret-scan rules must all be length-constrained (≥20 trailing chars).** Measured: 0 false positives over ~100 MB, versus 24 false hits for a bare `sk-ant-` grep. Dropping a length constraint is the regression this feature's test suite exists to catch.
- **`bundle_id` must be content-derived**, 8 lowercase hex. It appears in sidecar filenames (so it must be a valid kebab slug per K112) and content-derivation is the entire basis of import idempotency. A random or timestamp id breaks re-import.
- Knowledge checker codes that matter when grafting: **K131** (unresolvable `sources:`), **K141** (dangling `related:`), **K205** (routed more than once), **K206** (unrouted review-needed = WARN, tolerable), **K112** (basename must equal `name:`), **K109/K110** (active needs `last_verified`+`sources|verify`; review-needed needs `status_note`).
- `.claude/rules/*` is **template-owned** — a grafted rule landing at a colliding basename would be eaten by a future `install.sh --upgrade`. Always sidecar those.
- A grafted rule is **inert** until registered in `.claude/CLAUDE.md`, which is a file we refuse to auto-merge. The report must emit a `/learn` action list.
- **Finding, already reported to the user, out of scope here:** live Google API keys at `~/.claude/projects/-Users-administrator-workspace-edt-cost-estimator/3c6838db-….jsonl:1812,1857` and `5218f0ad-….jsonl:732`; a JWT at `62f3b912-….jsonl:818`. Do not act on these; the user owns them. They are why the scanner exists.

**Delegation strategy (recorded, `strategy-only`):** the two scripts are separable once the bundle contract is frozen. Sensible split if fanning out — worker A owns `claudart-backup.sh`, worker B owns `claudart-restore.sh`, both against the frozen `INVENTORY`/`MANIFEST.json` contract in the plan; the parent owns `tests/portability/run.sh`, the Codex twins, and registration. Do not delegate the merge table or the rewrite scanner separately — they are one coherent design and splitting them invites divergence.

**Knowledge candidates (not yet promoted — awaiting `/checkpoint` or an immediate-promotion trigger):** the Claude Code user-scope data layout (mangled dir scheme, transcript line schema, which dirs are machine-local vs portable) is a durable descriptive fact about an external system, evidenced by this session's survey. It is a strong `knowledge/` candidate once the feature lands and the facts are proven by working code.

## Plan of Work

Build the export side first, because it defines the bundle contract that everything else consumes. Get `claudart-backup.sh` producing a bundle whose `INVENTORY` round-trips, whose `MANIFEST.json` parses, and whose secret gate fails closed. Then stand up the test harness with synthetic fixtures — including the `/w/demo-app` vs `/w/demo-app-backup` decoy that the rewrite work will later need — and lock the export behavior with assertions before touching import.

Then build `claudart-restore.sh` in its three phases. The rewrite scanner and its five verifications come first and are provable in isolation; the merge table sits on top; the shadow `knowledge-check.sh` run gates the commit phase. The never-overwrite invariant is not a step, it is an assertion applied across the whole suite.

Finish with the parity obligations this repo enforces mechanically — byte-identical Codex script twins, slash commands with their Codex skill mirrors, and the two hardcoded registration points in `package.json` — then documentation.

## Concrete Steps

- [x] (2026-08-13 02:05Z) Step 1 — Write `.claude/scripts/claudart-backup.sh`: CLI per the plan's usage block plus `--project-scope all|graft`, allow-list collection from exactly four sources, newline/control-byte and symlink refusals, `INVENTORY` + `MERGEPLAN` + `MANIFEST.json` emission, derived indexes quarantined into `project-derived/`/`user-derived/`, lineage read from `.claude/.portability/ledger.tsv` (deny `conflicts/**`), 12 length-constrained scan rules, staged build committed by a single final `mv`. (verify: `bash -n` passes; a manual run against this repo produces a bundle whose `find … -exec cksum` output matches `INVENTORY` exactly, whose `MERGEPLAN` path set equals `INVENTORY`'s with every entry carrying exactly one class from the closed set, and whose `MANIFEST.json` parses via `node -e 'JSON.parse(…)'`)
- [x] (2026-08-13 02:55Z) Step 1b — Add path-token discovery to `claudart-backup.sh`: harvest every `"cwd"` value with counts, detect all six encodings (raw, mangled, tilde, `file://`, JSON-escaped `\/`, percent-encoded `%2F`), classify each token into the seven classes, emit `PATHMAP` + `PATHMAP.files` + a `paths` block in `MANIFEST.json` carrying `rewrite_order`, and add `--alias-root PATH` (repeatable via a temp file; zero occurrences is a `usage_error`). Report foreign-root disclosure on stdout and in `README.txt`. (verify: on this repo `PATHMAP` lists the raw/mangled/tilde/`file://`/escaped/percent tokens with counts matching an independent `grep -c`, and `occurrence_total` equals the sum of `PATHMAP.files` counts)
- [x] (2026-08-13 04:40Z) Step 2 — Create `tests/portability/` harness + synthetic fixtures. **Deviation from the plan, deliberately:** fixtures are built **inline at runtime**, not shipped as files with `@@PROJECT_ROOT@@`/`@@MANGLED@@` placeholders. The mangled directory name derives from the temp root, so no committed fixture can carry the right name — inline construction removes the templating step entirely rather than working around it. Consequence: no `tests/portability/fixtures/**` exists, so the planned `.prettierignore` entry is unnecessary. (verify: `/bin/bash tests/portability/run.sh` reports `PASS: n assertions` with empty stderr)
- [ ] Step 3 — Write `.claude/scripts/claudart-restore.sh` phases Plan + Materialize: pre-flight refusals, the single-pass `index()` rewrite scanner with boundary anchoring, and all five verifications. (verify: a fixture round-trip shows identity multiset preserved, byte arithmetic exact, and the decoy paths byte-identical while real paths are rewritten)
- [ ] Step 4 — Implement the merge classes driven by `MERGEPLAN` (regenerate `tasks/index.md`/`specs/INDEX.md`/`MEMORY.md`; line-union `knowledge/INDEX.md`/`_maps/*`; 3-way on `keyed-unit` when the ledger supplies a base, else 2-way with honest conflicts), the git-lineage stand-down, the conflict-parking protocol under `.claude/.portability/conflicts/<epoch>/`, the shadow `knowledge-check.sh --root <stage>` gate, and phase Commit with backups + `receipt.txt` + ledger append. (verify: importing into a populated target leaves every pre-existing file's cksum unchanged except the MERGE allowlist; a curated `knowledge/INDEX.md` retains its hooks, ordering, and external routes verbatim)
- [ ] Step 5 — Add import + round-trip assertions, including the never-overwrite invariant across both modes and double-apply idempotency. (verify: `snapshot(after 1st --apply) == snapshot(after 2nd --apply)` byte for byte on both trees)
- [ ] Step 6 — Create `.claude/commands/{backup,restore}.md`, `.agents/skills/codex-{backup,restore}/SKILL.md`, and the byte-identical `.codex/scripts/` twins; register all four scripts + the runner in `package.json` `check:shell`, add `test:portability` to the `check` chain, add `tests/portability/fixtures/**` to `.prettierignore`. (verify: `cmp -s` passes on both twin pairs; `npm run check` passes end to end)
- [ ] Step 7 — **(Doc surfaces already mapped — see "Step 7 surface map" below; the drafted copy uses the WRONG command names and must be renamed before use.)** Update docs: `README.md`/`README_VI.md`, `docs/GUIDE.md` cheat sheet, `docs/WORKFLOW.md`/`_VI.md` commands section + directory tree, `INTEGRATE.md` manifest, `CONTRIBUTING.md` parity list, `.claude/commands/doctor.md` required-commands list (+ Codex twin), `CHANGELOG.md` `[Unreleased]`. (verify: `npm run check` passes; `grep -rl claudart-backup docs README.md INTEGRATE.md` shows every intended surface updated)

### Step 7 surface map (recorded early, 2026-08-13 04:55Z)

A design pass enumerated every documentation touch-point with line anchors. **Its drafted copy is unusable verbatim** — it was written before the naming decision and says `/bundle-export`, `/bundle-import`, `claudart-export.sh`, `claudart-import.sh`. The correct names are **`/backup`, `/restore`, `claudart-backup.sh`, `claudart-restore.sh`**. Rename throughout before adopting any of it.

Surfaces, in the order to patch them:

1. `docs/GUIDE.md` — flow diagram (~line 7-32), the "which command, when" cheat-sheet table (~line 33-53), and a new Part 6 appended after the current final step. **Verify the step numbering first**: the Token Audit block at ~line 317 sits inside Step 14, so the new steps may not be 15/16.
2. `README.md` — "What it solves" table row after `/doctor` (~line 52), and the Quick start fenced block (~line 79-88).
3. `README_VI.md` — the same two, mirrored; `CONTRIBUTING.md:35` requires it.
4. `docs/WORKFLOW.md` — Contents list (~line 7-25), Commands table (~line 264), and a new "Portability" section before `## Directory layout`; the directory-layout tree itself needs the new script paths.
5. `docs/WORKFLOW_VI.md` — mirrored, ASCII punctuation per the existing VI convention.
6. `INTEGRATE.md` — commands list (~line 34), the "what CLAUDART contains" manifest (~line 38), and the Codex list (~line 46).
7. `CHANGELOG.md` — `## [Unreleased]` → `### Added`.
8. `.claude/CLAUDE.md` — Core Commands list.
9. `CONTRIBUTING.md` — parity list, after the `knowledge-check.sh` bullet: the two script pairs are byte-identical copies that change as one unit, and `tests/portability/` fixtures are built inline and must stay synthetic.
10. `.claude/commands/doctor.md` (+ Codex twin) — required-commands list.

Run `npm run format:md:check` after patching: prettier owns markdown table alignment and will reflow any added rows.

### Step 2 evidence (2026-08-13 04:40Z)

- `/bin/bash tests/portability/run.sh` → **`PASS: 78 assertions`**, empty stderr.
- `npm run check` passes end to end: prettier + `check:shell` (now covering both `claudart-backup.sh` copies and the new runner) + knowledge fixtures + spec-workflow contract + `test:portability`.
- Registered at `package.json`: three files appended to the hardcoded `check:shell` list, `test:portability` script added, `&& npm run test:portability` appended to the `check` chain.
- `.codex/scripts/claudart-backup.sh` created; `cmp -s` confirms byte-identity (asserted in the suite, so it cannot silently drift).

**The harness paid for itself on its first run: 15 failures, all one root cause.** macOS `$TMPDIR` is `/var/folders/…`, a symlink to `/private/var/folders/…`. The script canonicalizes `--root` with `pwd -P`, so it computed a mangled directory name from `/private/var/...` while the fixture had created that directory from `/var/...`; every user-scope assertion (memory, sessions, history, cwd probe, NUL scan) cascaded from that single mismatch. Fixed by canonicalizing `TMP_ROOT` immediately after `mktemp`. Worth keeping in mind for the restore side: this is not an artifact of testing, it is the real **symlinked-project-path** case, and it is exactly what the `ALIAS_ROOT` class exists to handle — a user whose project is reached through a symlink will have `cwd` values that do not match the resolved root.

Coverage locked by the suite: CLI contract and refusals · bundle shape · router quarantine · **all 8 credential canaries asserted absent by content, not by path** · history filtering including the escaped-JSON canary · non-mutation of both source trees · `INVENTORY` round-trip · `MERGEPLAN` covering the exact `INVENTORY` path set with every entry carrying a known class · `PATHMAP`↔`PATHMAP.files` reconciliation · **PATHMAP project-root count matched against an independent `grep`** (the disjointness regression test) · `SELFTEST` cksum · `MANIFEST.json` parsing via `node` · selection flags · graft scope · **the NUL-bearing-file secret regression** · the bare-prefix false-positive control · dry run · symlink non-copying and non-exfiltration · cwd probe past line 1 · absent user-scope data · existing-`--out` refusal.

### Step 1 evidence (2026-08-13 02:05Z)

- `/bin/bash -n .claude/scripts/claudart-backup.sh` → `SYNTAX OK`
- Full export, `--sessions all`: `87 files, 10.6 MiB`, 3 sessions + 14 subagent files + 3 tool-results, `history: 47 of 1179 lines`, `secret scan: 12 rules, 0 findings`, exit 0, 8.1s
- INVENTORY round-trip: recomputed `find … -exec cksum` (excluding the 4 metadata files) `diff`-clean against `INVENTORY` → `PASS: inventory matches`
- `MANIFEST.json` parses: `node -e JSON.parse` → 66 inventory entries, `bundle_id = 2fc7af21`
- MERGEPLAN ↔ INVENTORY path sets: 66 = 66, `diff` clean → `PASS: path sets agree`
- Classification spot-check: `keyed-unit` correctly extracted frontmatter `name: ai-ros-absorbed-into-claudart` as the merge key; routers landed in `project-derived/`/`user-derived/` and are **absent** from `project/`
- Credential exclusion: `.claude/settings.local.json` recorded as `deny:config`, absent from bundle
- History filter: all 47 exported lines match `"project":"/Users/administrator/Claudart"` → `PASS: no foreign lines`
- Non-mutation of the project root: `diff` clean → `PASS`
- Secret gate, negative (prose containing `sk-ant-`, `sk-ant-oat01-`, `AIza`, `Bearer`, `eyJ` as discussion text): `secret scan: 12 rules, 0 findings`, exit 0 → the length constraints hold
- Secret gate, positive (synthetic `AIza`+35): `GOOGLE_API_KEY project/.claude/knowledge/leak.md:1`, `bundle withheld`, exit 1, and `[ -e out ]` false → `PASS: bundle withheld`
- Secret non-disclosure: `grep -q 'AIza0000'` over the full stdout+stderr of a failing run → no match → `PASS: secret bytes never printed`

### Step 1b evidence (2026-08-13 02:55Z)

- `/bin/bash -n` → `SYNTAX OK`. Full export now reports `path tokens: 6 tokens, 13398 occurrences, 1 distinct cwd`.
- PATHMAP contents: `PROJECT_ROOT raw ×4659 / uri ×2`, `PROJECTS_DIR mangled ×509`, `CLAUDE_HOME raw ×850 / tilde ×810`, `HOME raw ×6568`.
- **Count invariant reconciles**: `PATHMAP` occurrence total 13398 == `PATHMAP.files` per-file sum 13398 → `PASS`.
- **Independent verification**: a separate `grep -oh -F` over the bundle for the raw project root returned 4659, exactly matching PATHMAP → `PASS: PATHMAP count is accurate`.
- Unplanned end-to-end validation of the secret loop: the scanner flagged `GOOGLE_API_KEY user/sessions/ec9cb4d3-….jsonl:305` — the synthetic `AIza` key from the Step 1 smoke test, which Claude Code had since written into this session's live transcript. The gate withheld the bundle exactly as designed, on data that arrived by accident rather than by fixture.

### Step 1b CORRECTION (2026-08-13 03:30Z) — two shipped bugs, found by validating primitives against real data

I marked Step 1b verified on evidence that was **not sound**. A validation pass against the real corpus and toolchain found two defects in shipped code. Both are fixed; the original evidence lines above are superseded by this block.

**Bug 1 — `grep` silently skips NUL-bearing files (security-critical).** Isolated repro: a file whose first line contains a synthetic `AIza` key and whose second line contains a NUL byte returns **0 matches** without `-a` and **1 match** with it. Measured: **all 6** real transcript and tool-result files in this project contain NUL. On these particular files plain and `-a` happened to agree (284 == 284) because grep's binary detection is **read-buffer-position dependent** — so the failure is _intermittent_, not reproducible. A secret scanner reporting "0 findings" on a file it never read is false assurance, which is worse than no scanner. My Step 1 "0 findings, verified" claim was luck, not proof. Fix: `-a` on every payload-reading grep, plus `tr '\000' '\001'` (length-preserving, and `\001` appears in no path token) before any awk pass, since some awks truncate at NUL too.

**Bug 2 — independent per-token counting double-counted every nested token.** `HOME` (`/Users/administrator`) is a strict prefix of both `PROJECT_ROOT` and `CLAUDE_HOME`, so the reported `HOME=6568` silently included `PROJECT_ROOT=4659` and `CLAUDE_HOME=850`. My "count invariant reconciles → PASS" compared two numbers produced by the _same_ overlapping method: internally consistent, but not measuring what I claimed. Import rewrites disjointly, so its recount would have failed to reconcile on every single run — the invariant would have been worse than useless, it would have blocked every legitimate import.

Fix: register tokens first, count raw with `grep` (C-fast), then remove nesting arithmetically — `disjoint(A) = raw(A) − Σ k(A,B)·disjoint(B)` over longer tokens B, where `k(A,B)` is occurrences of A inside the _token string_ B. Exact, and it needs only the token strings, not the corpus. A first attempt at a character-by-character awk scanner was correct but **timed out past 2 minutes** on 10 MB × 13 tokens; the arithmetic version runs in ~19s.

**Re-verified after the fix**: `HOME` 6568 → **1079**, and the partition is provably exact — `1079 + 4819 + 4 + 862 = 6764`, matching an independent `grep -aoF` for `/Users/administrator` over the bundle exactly. Every occurrence is counted once, none lost. `PATHMAP` total 8133 == `PATHMAP.files` sum 8133.

Also applied: `umask 077` (transcripts are mode 0600 and must not be widened; verified bundle files are 600).

**Bug 3 — staging in `$TMPDIR` then `mv` to `$OUT` is a cross-device copy**, so the atomicity I claimed did not hold: `mv` degrades to copy+unlink across filesystems, and a `--sessions all` export can overflow a small `/tmp`. Fix: stage at `$OUT.partial`, a sibling of the destination, so finalize is a true same-filesystem rename; refuse if the staging path already exists; and extend `cleanup()` to remove it so a failed or withheld run never leaves a partial bundle someone could mistake for output. Verified: normal run → bundle exists, no `.partial` residue; withheld run → exit 1, no bundle **and** no `.partial` residue.

**Design-agent bugs already satisfied by the shipped code** (checked, no change needed): `awk -v` backslash mangling — the history needle already passes via `ENVIRON`; `grep -c` line-vs-occurrence undercount — already uses `grep -aoF | wc -l`; zero-match file never created — already handled by the `HISTORY_KEPT` check plus `rm -f`; source-mutates-during-export — all manifest numbers already derive from the staged copy. Still open: a `cksum` cross-platform self-test file (macOS↔Linux agreement is assumed, not verified) — deferred to the restore work, where import is the consumer that would be harmed.

### Both carried-forward gaps closed (2026-08-13 04:10Z)

- **`FOREIGN` detection now works, with zero false positives.** Sibling project directories under `$CLAUDE_HOME/projects/` are probed for their own `cwd` (first 50 lines), and both the raw path and the mangled dir name are registered. Result on this repo: 4 foreign roots — `workspace/RnD/ai-refactor`, `workspace/edt-cost-estimator`, `workspace/pulse`, `workspace/simx-robotic-ui` — every one verified to be a real directory. **Deliberately NOT done by regex over transcript prose**: that approach is what produced the bogus count of 83 earlier, most of them JSON config keys in tool output. Sibling dirs are ground truth; pattern-matching prose is not.
- **`SELFTEST` + `SELFTEST.cksum` added** (known content plus its checksum) so restore can prove its own `cksum` agrees with the exporter's before trusting `INVENTORY`. Verified: `1863966313 21` recomputes identically. This closes B12 (macOS↔Linux `cksum` agreement was assumed, never verified).
- **Cost**: token count rose 6 → 14, and full-export runtime 19s → 32s. Acceptable for a migration operation, but the per-file-per-token grep loop is the hot spot if it ever needs optimizing — batch the passes rather than reintroducing a character scanner.

**Rejected: a complete alternative `claudart-export.sh` offered by the design agent.** It was never executed (that role has no write access), and its `count_paths` is the character-by-character awk scanner already **measured timing out past 2 minutes** on 10 MB × 13 tokens. Swapping a verified, executed implementation for an unrun one would be a regression. Only two ideas were taken from it: the `SELFTEST` file and the foreign-root discovery direction (implemented differently, per above).

**One honest gap remains (not a defect, a limit to state):**

1. **`escaped` (`\/`) and `percent` (`%2F`) rows came back empty** even though 8 and 5 partial occurrences were measured earlier. Cause: those hits are fragments like `\/Users\/administrator\/…` that do not form a complete escaped _project root_ or _claude home_ token, so no full-token match exists. Consequence: a path form absent from PATHMAP is left verbatim by import — inert and safe, but **invisible to the count invariant**, which only reconciles tokens it knows about. Import must state this limit rather than imply total coverage.
   _(The second gap — cwd-only `FOREIGN` detection — was closed; see the block above.)_

## Validation & Acceptance

- [ ] `npm run check` passes (prettier + `bash -n` + knowledge fixtures + spec-workflow contract + `test:portability`)
- [ ] Never-overwrite invariant holds: every pre-existing target file is byte-identical after `--apply`, except the MERGE allowlist — asserted for both `full` and `graft` modes
- [ ] Double-apply idempotency: two consecutive `--apply` runs produce byte-identical snapshots of both trees; no sidecar created twice
- [ ] Round trip: backup a synthetic root → restore into a _different_ cwd → per-file line counts equal, memory intact, `knowledge-check.sh --root <repo>` exits 0
- [ ] Prefix hazard: `/w/demo-app-backup` and `-w-demo-app-backup` byte-identical in output while the real path is rewritten
- [ ] Secret false-positive regression: a fixture with bare `sk-ant-` / `sk-ant-oat01-` in prose exits 0 with zero findings
- [ ] Secret positive: bundle absent, exit 1, and the matched bytes absent from stderr, `SECRETS.txt`, and `MANIFEST.json`
- [ ] Every credential canary is absent from the bundle **by content**, not merely by path
- [ ] Both Codex script twins are byte-identical (`cmp -s`)
- [ ] Manual smoke test noted as outstanding: whether the real CLI re-anchors from a transcript's `cwd` on `/resume` (design is conservative either way)

## Decision Log

- **Decision** (2026-08-13, claude): Commands are `/backup` and `/restore`, not `/export` and `/import`.
  **Rationale**: `/export` is an existing Claude Code built-in (it exports the current conversation); a same-named project command would be confusing at best and silently shadowed at worst. User chose this naming from four options.
- **Decision** (2026-08-13, claude): Script mode flag is `--mode full|graft`, not `restore|graft`.
  **Rationale**: with the command named `/restore`, a `--mode restore` would read as "restore --mode restore". `full` names what it does.
- **Decision** (2026-08-13, claude): Bundle carries two manifests — `INVENTORY` (cksum format) and `MANIFEST.json`.
  **Rationale**: restore is Bash 3.2 with no guaranteed `jq`; forcing it to parse JSON in awk would be the worst structural choice available. Both are emitted from one in-memory inventory so they cannot disagree. Rejected: JSON-only (unparseable), cksum-only (no provenance).
- **Decision** (2026-08-13, claude): Collection is an **allow-list** of four sources, not a deny-list over `~/.claude`.
  **Rationale**: a deny-list encodes only the credential surfaces known in August 2026; a future Claude Code release adding `~/.claude/tokens.json` would slip past it. An allow-list means those paths are never opened at all.
- **Decision** (2026-08-13, claude): Rewriting is biased toward **under**-replacement via boundary anchoring.
  **Rationale**: a missed rewrite leaves a visibly stale path in historical output (inert, reportable); an over-replacement silently fabricates a real-looking path (data falsification). Asymmetric cost, so the guard is asymmetric.
- **Decision** (2026-08-13, claude): `--mode graft` hard-refuses sessions and history rather than gating them behind a flag.
  **Rationale**: grafting transcripts across projects rewrites every `cwd` to the target, manufacturing a history of work that never happened there. Rejected: exposing it with a warning.
- **Decision** (2026-08-13, claude): `~/.claude/plans/` is excluded entirely, not offered as a flag.
  **Rationale**: measured 1-of-5 attribution accuracy, and that single hit was incidental (a path inside an `rm -rf` example). The false-positive mode is "silently bundles another project's plan into something you are about to send". Durable plans belong in `.claude/tasks/` via `/plan`, which exports losslessly.
- **Decision** (2026-08-13, claude): `~/.claude.json` is never read or written.
  **Rationale**: 145 KB single-document JSON holding every project's config, MCP servers (where API keys live), and trust flags; editing it with sed/awk risks the user's entire CLI configuration. Unnecessary — Claude Code creates the `projects.<abs-path>` entry itself on first run.
- **Decision** (2026-08-13, claude): Semantic merge of prose is **not attempted**; those files sidecar and route to an agent command.
  **Rationale**: a shell script cannot reconcile two prose knowledge topics or two `CLAUDE.md` files. Mechanical merges (line-set unions with deterministic keys) in shell; judgment in `/refactor-memory`, `/learn`, `/checkpoint`. Pretending otherwise would silently destroy a knowledge base.
- **Decision** (2026-08-13, claude): Delegation recorded as `strategy-only`.
  **Rationale**: the two scripts separate cleanly once the bundle contract is frozen, but the rewrite scanner and merge table are one coherent design and must not be split across workers.
- **Decision** (2026-08-13, claude): Indexes are handled per-file, split between **regenerate** and **line-union** — not uniformly.
  **Rationale**: `tasks/index.md:1-2` and `specs/INDEX.md:1-2` declare themselves convenience caches over source-of-truth files, so regenerating them from the merged units is strictly better than textual merge — it removes the highest-conflict surface (two machines appending at the same place) for zero semantic loss. `memory/MEMORY.md` is likewise mechanical. **But `knowledge/INDEX.md` and `_maps/*.md` must NOT be regenerated**: `knowledge-management.md` requires preserving "curated titles, hooks, grouping, ordering, and external routes", and none of those are reconstructible from topic frontmatter. Regenerating them would silently destroy curation. Those stay line-union.
- **Decision** (2026-08-13, claude): Export assigns each file exactly one **merge class** from a closed set, carried in a `$SEP`-delimited `MERGEPLAN` sibling of `INVENTORY`.
  **Rationale**: import must never guess or re-derive merge semantics, and must never parse JSON in Bash 3.2. Classes: `unique` (UUID/dated identity — ~95% of bytes, needs no merge logic at all), `union-log`, `keyed-unit`, `derived-index`, `sectioned`, `template`, `singleton-state`.
- **Decision** (2026-08-13, claude): Derived indexes ship in a separate `project-derived/` / `user-derived/` subtree, not inside `project/`.
  **Rationale**: structural guarantee — a naive `cp -R bundle/project/. dest/` then cannot clobber a router. Same allow-list-beats-deny-list reasoning as the credential exclusion. They still ship, because import needs them to detect drift and to seed regeneration when the destination has none.
- **Decision** (2026-08-13, claude): Add a lineage ledger at `.claude/.portability/ledger.tsv` — **export reads it, import writes it**.
  **Rationale**: intelligent merge means _3-way_ merge, which needs a common ancestor. Without one, every sync is 2-way: clobber or ask the human. With it, unchanged-on-one-side auto-resolves and only genuine both-edited divergence surfaces. That is the difference between "works once" and "works as an ongoing two-machine workflow". The read/write split preserves export's read-only property. The ledger holds no absolute paths, hostnames, or wall-clock beyond epoch, so it is safe to commit — and better committed, since git then syncs lineage for free.
- **Decision** (2026-08-13, claude): When the destination's git history already contains the bundle's `git_head`, import **stands down for the project layer** and says so.
  **Rationale**: that is a git merge, and reimplementing git is out of scope. Refusing is the feature.
- **Decision** (2026-08-13 02:30Z, claude): **Export describes paths; import translates them.** Export performs zero rewriting and instead ships a `PATHMAP` + `PATHMAP.files` (token, class, encoding, per-file occurrence counts).
  **Rationale**: three benefits, all load-bearing. It preserves export's read-only guarantee and bundle determinism; it lets **one bundle target many destinations** (a pre-rewritten bundle is a restore artifact, not an import artifact — and the user asked for cross-project reuse, not just machine migration); and per-file counts give import a **count invariant** — rewrite, recount, compare, abort on mismatch. That converts "the rewrite probably worked" into "zero silent leftovers, provably". Rejected: rewriting at export time, which is simpler but single-destination and unverifiable.
- **Decision** (2026-08-13 02:30Z, claude): Path tokens are classified into `PROJECT_ROOT`, `PROJECT_SUBPATH`, `ALIAS_ROOT`, `CLAUDE_HOME`, `PROJECTS_DIR`, `HOME`, `FOREIGN` — and `FOREIGN` is **never** rewritten to the project root.
  **Rationale**: a project's transcripts reference ~9 other projects' roots. A blind home-level replace would silently rewrite unrelated projects' paths; a blind project-level replace would be outright data corruption. `PROJECTS_DIR` is **recomputed** via `tr '/' '-'` from the target root, never string-derived from the rewritten path, because mangling is lossy.
- **Decision** (2026-08-13 02:30Z, claude): The rewrite is **two-phase with sentinels**, most-specific-first, boundary-anchored.
  **Rationale**: phase 1 replaces each matched token with an unused sentinel, phase 2 expands sentinels to targets. Single-phase substitution can re-rewrite its own output when a target contains a source token; the sentinel makes that structurally impossible rather than statistically unlikely. Class order matters independently: rewriting `HOME` before `CLAUDE_HOME` leaves a half-translated path with a stale mangled tail. `rewrite_order` ships **in the bundle** so the two halves cannot drift.
- **Decision** (2026-08-13 02:30Z, claude): Report foreign-project disclosure explicitly in the success output and `README.txt`.
  **Rationale**: exporting transcripts discloses the existence and names of unrelated projects, several potentially client-identifying. That is not a credential, so the scanner will never flag it, and the no-redaction rule forbids scrubbing it — but it must not be invisible either. Naming it is the only honest option.
- **Decision** (2026-08-13, claude): No text-diff/patch engine, ever.
  **Rationale**: every merge class is _structural_ (union, key comparison, heading split, regeneration). None requires diff3. Hunk-level merging of markdown prose is git's job, and the git-lineage check above already routes there.

## Surprises & Discoveries

- (2026-08-13) Live credentials already exist in the local transcript store: 5 Google API keys and 4 JWTs across three `edt-cost-estimator` sessions. Reported to the user with file:line; out of scope for this task. This converted the secret scanner from a nice-to-have into the load-bearing feature.
- (2026-08-13) A naive `head -1` probe for `cwd` finds nothing — line 1 of every transcript is `{"type":"mode",…}` and the first `cwd` appears on line 3-4. Any directory-resolution code written from the obvious assumption would fail silently on every project.
- (2026-08-13) Chained `sed -e` expressions rescan prior output, and the home dir is always a strict prefix of the project path — so the obvious two-expression rewrite is a live corruption path, not a theoretical one. `~/.claude.json` on this machine has both `/Users/administrator` and `/Users/administrator/Claudart` as project keys.
- (2026-08-13) `.claude/**` is git-tracked in a CLAUDART project, so the project layer already travels via `git pull`. This demoted repo-layer import to opt-in and reframed the feature around the user-scope half, which has no transport at all.
- (2026-08-13) The repo already declares its own merge semantics in file headers: `tasks/index.md:1-2` and `specs/INDEX.md:1-2` both say the index is a _convenience cache_ and the unit files are source of truth. That reframed the highest-conflict surfaces from "merge carefully" to "don't merge at all — regenerate". A design that textually merges a declared cache is fighting the system's own contract.
- (2026-08-13) …but the same reasoning does **not** extend to `knowledge/INDEX.md`, which carries curated hooks, grouping, ordering, and external routes that no regeneration can reconstruct from frontmatter. A uniform "regenerate all indexes" rule would have silently destroyed curation. The split had to be per-file.
- (2026-08-13) Without a common ancestor, every sync is a 2-way merge — clobber or interrogate the human. Adding a git-committable lineage ledger (export reads, import writes) is what upgrades this from a one-shot migration tool to a repeatable two-machine workflow, because unchanged-on-one-side then auto-resolves.
- (2026-08-13 02:30Z) **`cwd` is not constant within a project — it is a per-record field that follows the working directory into subdirectories.** Measured: this project has 1 distinct `cwd`, but `-Users-administrator-workspace-edt-cost-estimator` has **7** (`/byoc/edt/terraform/providers/aws`, `/byoc/edt/helm`, `/dist`, …). A design assuming a single source path would have passed every test on this repo and corrupted a real one. Path handling must be N-token, not 1-token.
- (2026-08-13 02:30Z) **Paths appear in at least six encodings, and two of them were reported absent but are real.** Measured in this project: raw `/Users/administrator/Claudart` ×4511, mangled `-Users-administrator-Claudart` ×499, tilde `~/.claude` ×**782** (an order of magnitude above the first estimate), `file://` ×25, **JSON-escaped `\/Users` ×8**, and **percent-encoded `%2FUsers` ×5**. The last two were measured as zero by the design pass and are not — so a pure raw-byte substitution silently misses them. This is the exact failure shape that yields a "successful" import with quietly broken paths, and it is why the count invariant below is not optional.
- (2026-08-13 02:30Z) **A sloppy regex inflated my own foreign-root count to 83.** Most hits were `.claude.json` config keys captured in tool output (`…/devcontainer.lastModelUsage.claude-opus-4-7.inputTokens`), not filesystem paths. The real figure is ~9 distinct foreign project roots. Recorded because the mistake is instructive: any path-token classifier that admits `.` into the character class will over-match JSON key paths in transcript bodies.
- (2026-08-13 02:30Z) **Operational landmine:** project directory names begin with `-`, so `grep pattern -Users-…/x.jsonl` makes grep parse the filename as options and silently returns zero. Every command taking one of these paths needs `--` or an absolute path. A measurement pass hit this and reported false zeros before it was caught.
- (2026-08-13 02:05Z) **A live session store cannot be exported deterministically, and that is not a script defect.** Two back-to-back full exports produced different `bundle_id`s, and a before/after cksum snapshot of `~/.claude` showed a mutation. Diagnosis: the single differing file was this session's own transcript (`ec9cb4d3-….jsonl`), which Claude Code appends to continuously while the export runs. The script mutated nothing. Consequence for testing: **determinism and non-mutation assertions must run against a static `--claude-home` fixture, never the real home** — which is exactly why that flag exists. Consequence for users: a bundle is a point-in-time snapshot of a moving store; the `bundle_id` of two exports taken during active work will differ legitimately.
- (2026-08-13) An unconstrained `sk-ant-` grep produces 24 false positives on this corpus, precisely because the transcripts contain conversation _about_ secret scanning. Length constraints (≥20 trailing chars) reduced that to 0 across ~100 MB while still catching the real Google keys and JWTs.

## Outcomes & Retrospective

<!-- Filled when status flips to done or cancelled. -->
