---
slug: output-limit-resilience
status: done
created: 2026-08-22
updated: 2026-08-22
agent: claude
delegation: none
tags: [context-limits, hooks, resilience, portability]
---

# Output-Limit Resilience: Detect, Prevent, Auto-Rotate Oversized Sessions

## Purpose

> "Có một vấn dê khi code là thỉnh thoảng bị quá output max token 32MB nên phiên lam việc bị dừng. Bạn hay tìm hiểu chiến lược thông minh nhất đề tự đông phát hiện, phòng ngữa, tự checkpoint/rotate và start continue session mới hiệu quả"

> "có, hãy đảm bảo nó hoạt động đúng, liên tục và hiệu qủa"

Sessions die unrecoverably when the serialized API request body crosses the hard 32MB cap
(base64 images and accumulated tool output inflate it far beyond token counts; auto-compact
counts tokens, not bytes, and a poisoned transcript fails again on every retry/resume).
After this change, CLAUDART projects have a mechanical guard that measures transcript growth
after every tool call, visibly warns at thresholds and instructs the agent to `/handoff` +
offer rotation **before** death, settings that pin the output/compaction knobs, a runbook for
already-dead sessions, and a test suite proving the guard fails closed. The user verifies by
running `npm run check`, reading the guard's warning in a real session, and following the
runbook steps.

## Context & Orientation

### Related Code

- `.claude/settings.local.json` — exists (permissions only); the new committed `.claude/settings.json` must not conflict with it. `.gitignore` ignores `settings.local.json` only, so project `settings.json` is committable.
- `.claude/scripts/knowledge-check.sh` — house style for fail-closed bash checkers (`set -u`, explicit exit codes); mirror its discipline.
- `.claude/scripts/claudart-backup.sh` — `is_template_path()` (~line 307) enumerates template families; `deny_path()` (~line 318) excludes `settings.json`/`settings.local.json` from bundles **by design** (credential safety).
- `install.sh` — `is_template_path()` at ~line 188-195 mirrors the backup script's list; both must gain `.claude/hooks/*` together.
- `package.json` — `check:shell` is an **explicit file list** (new scripts must be appended); test suites are `tests/<name>/run.sh` wired as `test:<name>` + chained into `check`.
- `tests/portability/run.sh` — existing suite covering backup/restore/install template behavior; extend for hooks.
- `.claude/rules/ai-behavior.md` §6 — output-hygiene rule ("never stream large command output"); gains image discipline + guard reference.
- `.claude/rules/spec-workflow.md` → Session Rotation — gains a numeric trigger alongside "context feels degraded".
- `.codex/guidelines/ai-behavior.md`, `.codex/guidelines/spec-workflow.md` — mirrors of the two rule files; per `knowledge/codex-mirror-pattern.md` the mirror is near-mechanical (paths + slash commands) — **diff before editing**.
- `docs/GUIDE.md` — user-facing docs; gains the resilience/runbook section.
- `~/.claude/settings.json` (user global, NOT in repo) — already configures a `statusLine` (`ccstatusline` via bunx). Project settings would **override** it; do not ship a project statusLine.

### Related Docs

- [Hooks reference](https://code.claude.com/docs/en/hooks.md) — stdin fields, exit-code semantics, settings shape, `once` handler field, 10K output cap.
- [Settings reference](https://code.claude.com/docs/en/settings-reference.md) — `env` block, `autoCompactEnabled`, `autoCompactWindow`, `statusLine`.
- [Errors reference](https://code.claude.com/docs/en/errors.md) — the 32MB request-body cap.
- [Tools reference](https://code.claude.com/docs/en/tools-reference.md) — Bash output truncation/spill, `BASH_MAX_OUTPUT_LENGTH`.
- [Env vars](https://code.claude.com/docs/en/env-vars.md) — `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`.
- GitHub #64520, #56691, #50321 — auto-compact silent-disable report; image-heavy 32MB deaths; compaction-failure death loop (community-sourced, verify at implementation).

### Memory Hints

**Harness facts established this session** (research delegated to a claude-code-guide agent,
round 1 + my direct doc fetches; round-2 verification was re-dispatched after an API-key
failure — append its answers here when they arrive):

- 32MB = API **request-body** cap, not a token limit. Images/PDFs (base64) are the #1 killer; token-based auto-compact cannot see them. Once one request exceeds it, every retry replays the same payload → session unrecoverable; `--resume` re-sends the poison. [docs errors.md; community #56691/#50321]
- PostToolUse hook contract: stdin JSON has common fields `session_id`, `transcript_path`, `cwd`, `hook_event_name` (+ tool fields). **Exit 0 + plain stdout is invisible to Claude** (debug log only). To inject context: print valid JSON `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "..."}}` (exit code then ignored), or **exit 2 with a message on stderr — shown to Claude** even though the tool already ran (documented warning path). Hook output strings capped at 10,000 chars. [docs hooks.md]
- Settings wiring shape: `"hooks": {"PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/context-guard.sh"}]}]}` — no `once:` field; dedup lives inside the guard (see Decision Log). Common handler fields include `type`, `if`, `timeout`, `statusMessage`, `once`. [docs hooks.md]
- `env` block in settings.json exports vars to every session and subprocesses (incl. Bash tool) [docs settings-reference.md]. Round-2 verified: `autoCompactWindow` = **token count** (100000–1000000, capped at the model's window; default unset = tuned per model); `autoCompactEnabled` = boolean, default `true`. Precedence: `CLAUDE_CODE_AUTO_COMPACT_WINDOW` env > `--autocompact` flag > setting. Caveat: when `autoCompactWindow` is set, statusline `used_percentage` (measured against the FULL model window) decouples from the compaction point. [docs settings-reference.md + env-vars.md]
- `BASH_MAX_OUTPUT_LENGTH` env var [docs env-vars.md]: "Maximum number of characters of bash output that Claude Code reads back into a command's result (**default: 30000; maximum: 150000**)". Past ~30K a valid result arrives as a session-file path + preview **regardless of this variable** (native file-spill); failure results cap at ~10K head-and-tail with no file path. [docs tools-reference.md]
- StatusLine `used_percentage` underreports vs internal warnings by ~10–19% (excludes overhead) [community #17959] — one more reason the guard measures transcript **bytes**, not percentages.
- Transcript path pattern: `~/.claude/projects/<munged-cwd>/<session-uuid>.jsonl`; hook stdin `transcript_path` gives it directly. Observed on this machine: sessions reach 2–4MB; project total 22MB.
- Installed CC version at planning time: **2.1.239**.
- Round-2 verification (claude-code-guide, 2026-08-22, raw-doc curl + GitHub API; local raw-page cache at `/tmp/ccdocs/*.md`): `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` still documented — percentage 1-100 of the auto-compact window, **lower-only** (higher values ignored), applies to main conversations and subagents, composes with the effective window. GitHub #64520 closed as duplicate of #64277, which was closed stale — **no official fix confirmation either way**; treat explicit compaction config as belt-and-suspenders and verify empirically on 2.1.239. PostToolUse stdin carries `tool_response` (same content the model receives in the tool_result block; parse only needed fields). Verbatim non-blocking injection: exit 0 + `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "..."}}`. `updatedToolOutput` exists but for built-in tools a value not matching the tool's output schema is silently ignored — do not rely on it.

**Design decisions baked into the steps** (do not relitigate without a Decision Log entry):

- Detection = PostToolUse guard statting `transcript_path` bytes. Token % is not delivered to PostToolUse; bytes are measurable everywhere and map directly to the 32MB body.
- Thresholds: warn at 8MB, act at 16MB (25%/50% of cap — large safety margin), env-overridable via `CLAUDART_GUARD_WARN_MB` / `CLAUDART_GUARD_ACT_MB`.
- Deduplication is internal to the guard via session-scoped marker files under TMPDIR — not the hooks `once:` field (see Decision Log 2026-08-22 08:40Z). A stateless per-call injection would pay an additionalContext token tax on every tool call for the rest of the session.
- Fail-**visible**, not fail-block: if the guard cannot measure (jq missing, no transcript_path, stat fails), it exits 2 with a one-line stderr reason so the degradation is seen; it NEVER exits 2 to block a tool and never fails silently. Negative control in tests proves the unhealthy path fires.
- No project `statusLine`: it would clobber the user's global ccstatusline. Docs carry an opt-in snippet instead.
- `deny_path()` keeping `settings.json` out of `/backup` bundles stays as-is (credential safety by design). Wiring travels via git (settings.json is committed); GUIDE documents the one manual step after a restore into a non-git target.
- Tier 2 per evidence-gauntlet: RED-first fixtures, scripted mutation pass persisted in-repo, branch-coverage checklist mapped to fixtures (bash has no diff-cover; the fixture×branch table in the test file IS the changed-line gate, defended by mutation).

- Codex-harness perspective (user-requested review of `.codex/`, 2026-08-22): repo `.codex/config.toml` carries harness-mechanical caps in each harness's own config (`[agents] max_concurrent_threads_per_session = 6`) — precedent for keeping Claude-mechanical wiring in `.claude/settings.json` rather than inventing a cross-harness abstraction. `.codex/AGENTS.md` confirms the behavioral half is already mirrored (`$codex-handoff` on near-full context; rotation at phase boundaries). Codex has **no** PostToolUse/transcript_path contract, so no mechanical guard exists there — the guidelines amendment (Step 7) is what gives Codex sessions the numeric triggers, and GUIDE documents this asymmetry in one line (Step 9). Global `~/.codex/` holds only skills; no config to conflict with.

**Delegation record**: harness-facts research delegated to claude-code-guide agent — round 1 (limits/hooks overview) and round 2 (exact units/defaults, #64520 status, verbatim contracts) both consumed into Memory Hints above; delegation closed. No coding delegation planned (`delegation: none`) — files are small and share design decisions.

**Knowledge candidate** (flag for `/checkpoint`, do not promote during this task): a
`reference` topic "claude-code-output-limits" holding the 32MB body cap, hook contract
facts, and knob defaults — durable, sourced, currently scattered across this file.

## Plan of Work

The work is a thin mechanical layer around machinery CLAUDART already has: `/handoff`,
`/checkpoint`, and spec Session Rotation exist but trigger on vibes. Order matters: facts
first (a wrong `autoCompactWindow` unit silently breaks compaction), then the guard
test-first so its failure modes are pinned before the script exists, then wiring, then the
documentation and portability surface so the mechanism ships intact to installed projects.
Rules are amended last so they can reference the verified, working guard rather than an
intended one.

Steps 2–4 follow the evidence-gauntlet loop for a Tier 2 change: every fixture test is
observed failing against a stub before the guard is implemented; a persisted mutation script
then proves the fixtures bite; the restore is verified with `git diff`, not by eye.

## Concrete Steps

- [x] (2026-08-22 09:05Z) Step 1 — Closed the round-2 fact gaps: autoCompactWindow is a token count (100K–1M, default unset), autoCompactEnabled default true, #64520 closed-as-duplicate/stale with no official fix statement, BASH_MAX_OUTPUT_LENGTH verbatim (default 30000 / max 150000), CLAUDE_AUTOCOMPACT_PCT_OVERRIDE still documented (1-100, lower-only), PostToolUse `tool_response` + verbatim additionalContext example confirmed. (verify: Memory Hints carry a citation per fact; no "pending" items remain — round-2 block recorded above with [docs]/[community] attributions; settings values chosen at Step 5 from these facts only)
- [x] (2026-08-22 10:05Z) Step 2 — RED observed: `bash tests/context-guard/run.sh` → "7 passed, 17 failed", exit 1, against a stub guard exiting 3. Every behavior assertion failed on content (missing hookSpecificOutput/additionalContext/level markers) or exit code; only vacuously-true negatives passed (empty-stdout asserts). red-verified for all 10 fixture cases T1–T10.
- [x] (2026-08-22 10:25Z) Step 3 — GREEN: `.claude/hooks/context-guard.sh` implemented (set -u, LC_ALL=C, explicit exit codes, jq-first dependency check, marker dedup degrading open). `bash tests/context-guard/run.sh` → "28 passed, 0 failed", exit 0 (suite grew to 28 asserts during mutation prep — T11/T12 boundary, T13 invalid-env cases added).
- [x] (2026-08-22 10:30Z) Step 4 — Mutation: `tests/context-guard/mutants.sh` (persisted, executable) applied 6 scripted mutants — M1/M2 boundary `-ge`→`-gt`, M3 die exits 0, M4 dedup disabled, M5 warn/act messages swapped, M6 threshold validation removed — every one killed ("6 killed, 0 survived", exit 0). Restore verified by `cmp` byte-compare against the pristine in-script copy (mutants.sh exits 3 on mismatch; it exited 0). Deviation from the planned `git diff` verify: the guard is untracked (`git status --porcelain` → `?? .claude/hooks/`), so `git diff` is vacuous for it — byte-compare against the pre-mutation copy is the stronger check and is what the script enforces.
- [x] (2026-08-22 13:13Z) Step 5 — Wired `.claude/settings.json`: explicit `autoCompactEnabled: true`, `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70`, `env.BASH_MAX_OUTPUT_LENGTH=30000`, and `hooks.PostToolUse` matcher `*` → `${CLAUDE_PROJECT_DIR}/.claude/hooks/context-guard.sh` (no `once:` — superseded by marker dedup, Decision Log 08:40Z). Created via the update-config skill flow after an earlier bare Write was user-rejected. Evidence: `jq .` → SYNTAX-OK; skill's schema extraction `jq -e '.hooks.PostToolUse[] | select(.matcher=="*") | …'` exit 0 printing the command string; live pipe-test with a real small transcript (`{"session_id":"pipetest-live","transcript_path":".../package.json"}`) → exit=0, silent stdout. `settings.local.json` holds only unrelated keys (`permissions.allow`, `disabledMcpjsonServers`) — no merge conflict. package.json wiring (check:shell list, test:context-guard, check chain) was completed with Steps 2–4.
- [x] (2026-08-22 13:13Z) Step 6 — Real execution proven in a fresh headless session (fresh process loads settings at startup — sidesteps the mid-session settings-watcher caveat for this session). Run 1: `claude -p 'Use the Bash tool to run exactly: true…' --allowedTools 'Bash(true)' --debug` → exit=0, reply "done", but stderr carried zero hook lines on CLI 2.1.239 (926 bytes, only model-recognition notices) — inconclusive stream, not treated as pass. Run 2 used the update-config skill's prescribed sentinel proof: temporarily prefixed the hook command with `echo "$(date -u …) claudart-guard-fired" >> /tmp/claudart-hook-sentinel.txt; `, reran the identical headless session → sentinel file received `2026-08-22T13:12:04Z claudart-guard-fired` — the project-settings PostToolUse hook executed end-to-end, guard stayed silent on a tiny transcript (correct under-threshold behavior), no hook-error notices. Cleanup: pristine copy restored byte-identical (`cmp` OK), jq syntax + schema revalidated, sentinel/temp files removed.
- [x] (2026-08-22 10:55Z) Step 7 — Rules amended: `.claude/rules/ai-behavior.md` §6 gains the base64/image-discipline bullet + obey-the-guard bullet (WARN ≥8MB / ACT ≥16MB); `.claude/rules/spec-workflow.md` Session Rotation gains the numeric-trigger bullet (WARN → offer at next boundary; ACT → rotate now; fallback statusline ≥75% / ~16MB). Mirrors applied after diffing (codex-mirror-pattern): `.codex/guidelines/ai-behavior.md` §5 and `.codex/guidelines/spec-workflow.md` Session Rotation, in each file's local convention (ASCII dashes in ai-behavior mirror, `$codex-handoff` command names). `npx prettier --check` green on all four.
- [x] (2026-08-22 10:55Z) Step 8 — Portability: `.claude/hooks/*` added to `is_template_path()` in THREE files — `install.sh`, `.claude/scripts/claudart-backup.sh`, and `.codex/scripts/claudart-backup.sh` (the Codex twin was missing from the plan's file list; the twins must stay byte-identical per the portability suite's twin check, so both got the same edit). `tests/portability/run.sh` extended: fixture plants `.claude/hooks/context-guard.sh` in the source project and asserts it lands in the bundle. `npm run test:portability` → 99 ok, 0 failed. Evidence: real backup MANIFEST.json contains `project/.claude/hooks/context-guard.sh`. Deviation from the planned verify wording: `--dry-run` prints counts, not file lists ("project layer: 80 files"), so MANIFEST grep + the suite assertion are the file-level proof. `deny_path()` untouched.
- [x] (2026-08-22 11:00Z) Step 9 — Docs: GUIDE.md gains "Step 10b — Session output-limit resilience (automatic)" after Step 10: death mechanism in two sentences, WARN/ACT threshold table, env tuning, why settings travel by git not bundles (+ re-wire note), dead-session runbook (ls transcript → resume+/compact under 16MB; else fresh /start), Codex-parity note. Deviation: no statusline opt-in snippet shipped — the section states the deliberate absence (percentages underreport 10–19%; a project statusline would clobber the user's global ccstatusline), which is more honest than a snippet we can't test against their setup. Prettier-fixed to repo style.
- [x] (2026-08-22 13:20Z) Step 10 — Final gauntlet, ONE fresh run after the last edit (`.prettierignore` + task-file prettier fix): `npm run check` → exit 0 (full chain: prettier, shell syntax incl. guard, knowledge, spec-workflow, portability, evidence-gauntlet, install-live-state, context-guard); `bash tests/context-guard/run.sh` → "28 passed, 0 failed", exit 0; `bash tests/context-guard/mutants.sh` → "6 killed, 0 survived", exit 0. First gauntlet attempt failed at prettier (`npm run check` exit 1): my task file had formatting drift, AND the vendored untracked `codex/` tree (72 files) was being swept by `format:md:check`'s `**/*.md` glob — fixed via `.prettierignore` entry `codex/` (third-party tree must never be reformatted), then the full gauntlet re-run fresh per the single-final-run rule.

## Validation & Acceptance

- [x] `npm run check` passes (prettier + shell syntax incl. new guard + full test chain incl. new suite) — final run exit 0 (Step 10, 13:20Z)
- [x] `bash tests/context-guard/run.sh` green, with the RED-first observation recorded before implementation existed — 28/28 final run; RED at Step 2 (17 failed vs stub, 10:05Z)
- [x] Mutation: ≥4/4 mutants killed, restore verified via `git diff` — 6/6 killed; restore verified via `cmp` byte-compare (git diff vacuous for the untracked guard; stronger substitute recorded at Step 4)
- [x] Negative control observed: unhealthy input produces a visible exit-2 stderr line (checker proven able to fail) — T6–T8 asserts 15–20 (missing path / invalid JSON / jq-missing all exit 2 naming cause)
- [x] Real-session evidence: fresh `claude -p` run shows the guard executing with no hook errors — sentinel proof `2026-08-22T13:12:04Z claudart-guard-fired` from project settings (Step 6; `--debug` stream carried no hook lines on 2.1.239, so the skill's sentinel method was used)
- [x] Rules + `.codex/guidelines/` mirrors amended; knowledge checker untouched (no knowledge writes this task) — Step 7; knowledge-check.sh not run because `.claude/knowledge/` was never mutated
- [x] `claudart-backup.sh --dry-run` lists `.claude/hooks/context-guard.sh`; `tests/portability` green — dry-run prints counts not lists (recorded Step 8 deviation); file-level proof is MANIFEST.json grep + suite assertion, 99 ok / 0 failed
- [x] GUIDE.md runbook section present and copy-runnable — "Step 10b — Session output-limit resilience (automatic)" (Step 9)

## Decision Log

- **Detection via PostToolUse transcript-bytes guard** (2026-08-22, claude): token % only reaches StatusLine; PreToolUse input rewriting is fragile and PostToolUse output rewriting has regression reports; bytes map directly to the 32MB body and are measurable in any hook. Rejected: statusline-based automation (clobbers user's global statusline), output-rewriting hooks (regressions #67442/#18534).
- **No project statusLine shipped** (2026-08-22, claude): user global `~/.claude/settings.json` already runs ccstatusline; project settings override it. Opt-in snippet documented instead.
- **`once: true` handler** (2026-08-22, claude): stateless per-call additionalContext would tax every remaining tool call; once-per-session matches the escalation semantics (thresholds only rise within a session).
- **Fail-visible exit-2 stderr** (2026-08-22, claude): documented PostToolUse warning channel; keeps the checker honest (degradation is seen, never silent) without ever blocking a tool.
- **Backup `deny_path()` unchanged** (2026-08-22, claude): settings exclusion is deliberate credential safety; wiring travels via git + documented restore note, not via bundles.
- **`delegation: none`** (2026-08-22, claude): small files sharing one design; fan-out overhead exceeds benefit. Research-only delegation recorded in Memory Hints.
- **Marker-file dedup replaces `once:`** (2026-08-22 08:40Z, claude): the hooks `once:` handler field's exact semantics are unverified and may mean "execute once per session", which would silence an under-threshold guard forever after call #1. The guard instead deduplicates internally with session-scoped markers under TMPDIR (per session + level), degrading open — re-firing rather than staying silent — if markers are unwritable. Rationale: own the behavior we depend on; `once:` stays out of the wiring.
- **Settings values: PCT override 70, no autoCompactWindow, BASH output pinned 30000** (2026-08-22 13:13Z, claude): `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70` compacts at 70% of the model-relative auto-compact window — lower-only per docs, composes with any model window, and avoids `autoCompactWindow`, whose token-count form decouples statusline `used_percentage` from the compaction point and risks _shrinking_ the effective window on large-context models. Rejected: setting `autoCompactWindow` (unit confusion + window-shrink risk); leaving compaction unset entirely (#64520/#64277 report silent auto-compact disable with no confirmed fix — explicit `autoCompactEnabled: true` is belt-and-suspenders). `BASH_MAX_OUTPUT_LENGTH=30000` pins the documented default so a future drift upward (max 150000) can't quietly let big tool outputs inflate the request body; native file-spill past ~30K is unaffected.

## Surprises & Discoveries

- (2026-08-22 08:40Z) The planning-time decision to use the hooks `once:` handler field rests on unverified semantics — if `once` means "execute this handler once per session", a guard that is silent on call #1 (under threshold) would never measure again, defeating the whole mechanism. Superseded in Decision Log: the guard deduplicates internally via session-scoped marker files instead; `once:` stays out of the wiring.
- (2026-08-22 10:20Z) User requested a review of the Codex harness (`.codex/`) for extra perspective mid-execution. Findings folded into Memory Hints: harness-mechanical caps belong in each harness's own config (`.codex/config.toml` precedent); the behavioral half is already mirrored; no Codex hook contract exists, so Codex parity is rules-only — documented as a deliberate asymmetry in GUIDE.
- (2026-08-22 10:45Z) The Codex guideline mirrors were ALREADY stale before this task: `.codex/guidelines/ai-behavior.md` lacks §3 Correct-Model-Over-Quick-Fix entirely (commit 127c3d0 never mirrored), and spec-workflow's scoped-gate text diverges. Not repaired here (out of scope, surgical-changes rule) — flagging for a future mirror-sync pass or `/learn`.
- (2026-08-22 11:00Z) The Write tool became persistently unavailable mid-execution (safety classifier timing out; Edit and Bash unaffected). Steps reordered to do all Edit-based work (7, 8, 9) first; Step 5's `settings.json` creation and the steps depending on it (6, 10) wait on the tool recovering. All reordered work still funnels into the single fresh final gauntlet (Step 10).
- (2026-08-22) `claudart-backup.sh` `deny_path()` excludes project `settings.json` from bundles by design — the portability story for hook wiring had to change from "rides in the bundle" to "rides in git + documented re-wire".
- (2026-08-22) The user already runs a global statusline (ccstatusline) — a shipped project statusline would silently override it; detection design moved fully to the PostToolUse guard.
- (2026-08-22) `check:shell` in package.json is an explicit file list, not a glob — new scripts silently escape shell-syntax checks unless appended.
- (2026-08-22) Round-2 research delegation died mid-run on an API key limit (403 total limit); user switched model and it was re-dispatched. Lesson candidate for /learn: delegation failures surface as task notifications, and re-dispatch must state what is already resolved to avoid shadow-running.
- (2026-08-22 13:20Z) The vendored `codex/` tree the user added mid-task broke `npm run check`: prettier's `**/*.md` glob swept 72 upstream files that must never be reformatted. Fixed with a `.prettierignore` entry (`codex/`). General lesson for /learn candidates: when a third-party tree lands in this repo, formatter ignores must land with it — the check suite is a glob and silently widens.
- (2026-08-22 13:13Z) `claude -p --debug` on CLI 2.1.239 emits no hook-execution lines to stderr for a silent-success hook — debug output cannot prove a healthy PostToolUse fired. The update-config skill's sentinel-prefix method is the reliable in-turn proof; recorded here because future wiring tasks will hit the same wall.

## Outcomes & Retrospective

**Shipped** (all evidence from the single final gauntlet run, 2026-08-22 13:20Z):

- `.claude/hooks/context-guard.sh` — PostToolUse guard measuring transcript bytes after every tool call; WARN ≥8MB (finish unit, prepare `/handoff`) and ACT ≥16MB (`/handoff` now, rotate before anything new), env-tunable via `CLAUDART_GUARD_WARN_MB`/`CLAUDART_GUARD_ACT_MB`, session-scoped marker dedup degrading open, fail-visible exit-2 on any unhealthy condition (jq-first check).
- `.claude/settings.json` — committed project settings: explicit `autoCompactEnabled`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70`, `BASH_MAX_OUTPUT_LENGTH=30000`, and the PostToolUse wiring. Travels by git; deliberately excluded from backup bundles (credential safety unchanged).
- Proof chain: RED 17-fail observed before implementation → 28/28 green → 6/6 mutants killed with cmp-verified restores → negative controls T6–T8/T13 → real-session sentinel firing (`13:12:04Z claudart-guard-fired`) → final fresh gauntlet all exit 0.
- Surface complete: rules (`ai-behavior.md` §6, spec-workflow Session Rotation) + Codex guideline mirrors + portability (hooks ship via install + backup template lists; portability suite 99 ok) + GUIDE "Step 10b" with dead-session runbook.

**Known gaps / deferred:**

- Interactive sessions started BEFORE `.claude/settings.json` existed may not activate the hook until `/hooks` is opened once or Claude Code restarts (settings-watcher caveat). Fresh sessions load it at startup — proven headless.
- Knowledge candidate `claude-code-output-limits` awaits `/checkpoint` promotion (flagged in Memory Hints, deliberately not promoted during the task).
- Pre-existing `.codex/guidelines/` staleness (ai-behavior §3 never mirrored; spec-workflow scoped-gate divergence) predates this task — flagged for a mirror-sync pass.
- Codex harness gets rules-only parity (no transcript contract there); no mechanical guard exists on that side by design.

**Lessons:** bytes-not-tokens is now enforced mechanically, not by discipline; sentinel-proof beats inconclusive `--debug`; vendored trees need `.prettierignore` entries the moment they land.
