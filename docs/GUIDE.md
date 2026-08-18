<!-- AI agents: this is a human-oriented cookbook. The binding contracts live in .claude/rules/ and .codex/guidelines/ — read those, not this file, when acting. Read this file only when the user asks how to use CLAUDART itself. -->

# CLAUDART User Guide — The Flow, in Order

[WORKFLOW.md](WORKFLOW.md) is the manual (how the pieces work). This is the cookbook, organized **in the order you actually use things**: set up once, open each session the same way, size the work, execute, close the loop. Every Claude Code command has a Codex CLI twin — replace `/x` with `$codex-x`.

## The flow at a glance

```
ONCE PER PROJECT
  install.sh → /doctor → /refactor-memory → /doctor
  (no repo yet? /project-discovery first)

EVERY SESSION
  /start ──► size the work:
              │
              ├─ trivial (1-2 files) ──────► just ask, no command
              ├─ feature/fix (multi-file) ─► /plan → you say "go" → execute → awaiting-review → you confirm
              ├─ mission (demoable whole) ─► /spec → POC loop → "go" once → /spec-run (cheap session)
              └─ behavior-preserving ──────► /refactor → same as /spec with equivalence proof
              └─ must be proved ───────────► /prove    → red before green, then the gauntlet
              │
  while working:  /council for hard decisions · review agents before merge · /handoff if context fills
              │
  end of session: /checkpoint

WHEN THINGS LOOP OR DRIFT
  spec blocked ──► /spec-run again from a stronger session
  same correction twice ──► /learn
  memory feels off ──► /doctor → /refactor-memory → /doctor
  auto-compact too frequent ──► /optimize
```

## Cheat sheet — which command, when

| Your situation                                                  | Do this                                                   |
| --------------------------------------------------------------- | --------------------------------------------------------- |
| Setting up a project                                            | `install.sh` → `/doctor` → `/refactor-memory` → `/doctor` |
| Rough product idea, no repo yet                                 | `/project-discovery`                                      |
| Opening a session, any day                                      | `/start`                                                  |
| A quick fix, one or two files                                   | Just ask — no command needed                              |
| A feature or fix spanning several files or sessions             | `/plan <description>`                                     |
| A mission too big for one plan (a whole game, a feature system) | `/spec <mission>` → approve once → `/spec-run <slug>`     |
| A refactor or migration that must not change behavior           | `/refactor <mission>`                                     |
| A change you want proved, not just asserted                     | `/prove <change>`                                         |
| A spec got stuck on a cheap model                               | `/spec-run <slug>` again, from a stronger session         |
| A hard decision needs multiple perspectives                     | `/council <question>` (optional companion)                |
| Want a code / security / visual review                          | Ask for the agent by name (see Step 9)                    |
| Context window nearly full mid-investigation                    | `/handoff`, then resume fresh with `/start`               |
| Ending a productive session                                     | `/checkpoint`                                             |
| You corrected the agent twice for the same thing                | `/learn`                                                  |
| Setup feels broken or memory drifted                            | `/doctor` (→ `/refactor-memory` → `/doctor`)              |
| Auto-compact fires frequently / sessions feel token-hungry      | `/optimize`                                               |

---

# Part 1 — Once per project

## Step 1 — Install

```bash
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s --  --repo=lapnd/Claudart # --claude (default) · --codex · --both · --council
```

Add `--council` to also install the [Council of High Intelligence](https://github.com/0xNyk/council-of-high-intelligence) companion (`/council`, user scope — Step 8).

**Using a fork?** No source patching needed — the script resolves its source repo by precedence: `--repo=<owner/name>` flag → `CLAUDART_REPO` env → the checkout's own git origin when you run `bash install.sh` from a local clone → the built-in default. The download banner names which one won.

Then, inside Claude Code:

```
/doctor            # verify the install is healthy
/refactor-memory   # fold any existing CLAUDE.md content into the layered memory
/doctor            # confirm nothing drifted
```

From now on every session starts with `/start`.

## Step 2 — No repo yet? Discover first (optional)

```
you>  /project-discovery an app to track my kid's swim practice times
```

One highest-leverage question per turn, in your language, until the shape is clear — then it writes `docs/project/` discovery docs (scope, users, constraints, rejected options). `/spec` builds directly on that output. Skip this step when the project already exists.

---

# Part 2 — Every session

## Step 3 — Open with `/start`

```
you>  /start
```

The agent reads CONTEXT, the task/spec indexes, the knowledge router, and the last 3 commits, then reports:

```
## Session Ready
**Current focus:** JWT middleware rollout
**Active tasks:** add-jwt-middleware (in-progress, updated 2026-08-10)
**Start by:** resume add-jwt-middleware — step 3 is next
```

It will _offer_ to resume — it never auto-resumes. Say "resume" or tell it what to do instead.

## Step 4 — Size the work

This is the one judgment call the flow asks of you, and the agent will push back if you get it wrong:

- **One or two files, one sitting** → just ask (Step 5). No ceremony.
- **Several files or several sessions** → `/plan` (Step 6). Survives the terminal closing.
- **A demoable whole** — a game, a feature system, a client POC → `/spec` (Step 7). Approve once, execute across many cheap sessions.
- **A refactor/migration that must not change behavior** → `/refactor` (Step 7b). A spec with an equivalence proof bolted on.

---

# Part 3 — Executing, by size

## Step 5 — Quick fix (no ceremony)

> **you:** "the CORS header is missing on /api/health, fix it"

No command. The agent fixes it, runs the verify, done. If the session ends mid-flight, `/checkpoint` records a `(no task)` micro-handoff in CONTEXT so the next `/start` can pick it up.

## Step 6 — A planned feature (`/plan`)

```
you>  /plan add JWT middleware to the API
```

The agent explores read-only, then writes `.claude/tasks/2026-08-11-001-add-jwt-middleware.md` with steps like:

```markdown
- [ ] Step 1 — add jwt dependency + config loader in src/config/auth.ts (verify: app boots with AUTH_SECRET set) (tier: fast)
- [ ] Step 2 — middleware in src/middleware/jwt.ts rejecting missing/expired tokens (verify: curl without token → 401)
- [ ] Step 3 — wire into router, exclude /health (verify: npm test -- auth.spec.ts passes)
```

**Nothing is coded until you approve.** Approval is plain language: `go`, `approved`, `do it`, `ok làm đi`. "Looks good but move step 3 first" is _not_ approval — it's a revision request.

While executing, the agent ticks steps with timestamps and evidence. When everything passes it parks at **`awaiting-review`** and stops:

> "All steps and validation done. Task `add-jwt-middleware` is awaiting-review. Please verify and confirm to close."

You test it yourself. Then either **"approved"** (task archives to `tasks/done/`) or **"step 2 doesn't block expired tokens"** — the agent logs your report verbatim, flips back to in-progress, and fixes it. This loop repeating is the system working, not failing.

Days later, in a fresh session: `/start` surfaces the task, and the agent re-verifies completed steps against current code before continuing — commits may have landed in between.

## Step 7 — A mission (`/spec`, then `/spec-run`)

The mission flow is three moves in order: **author on a strong model → approve once → execute on a cheap one.**

### 7.1 Author (strong session)

```
you>  /spec build a tower-defense demo for the client meeting
```

The agent interviews you one question at a time, writes every settled decision into SPEC.md immediately, then builds a **POC artifact** — a self-contained HTML file you double-click. You react ("towers too small, waves too fast"), it revises, until you say "that's it". The POC is frozen as the reference the executor must match. Finally it writes a decision-complete ROADMAP and reports:

```
## Spec Ready for Review
**Folder**: .claude/specs/2026-08-11-tower-defense/
**POC**: artifacts/poc.html — open it and check it still matches your intent
**Scenarios**: 6 acceptance scenarios | **Roadmap**: 3 phases, 14 tasks
**Commit policy**: commits: user
**Runnable on**: standard — run /spec-run from a session of that tier
```

### 7.2 Approve once

Saying **"go"** here is a _standing approval_: the executor will run the whole roadmap without asking again until final review.

### 7.3 Execute (cheap session)

Open a **fresh session on the tier the spec recommends** — that's what "Runnable on: standard" is for:

```
you>  /model sonnet        # or any standard-tier model
you>  /start
you>  /spec-run tower-defense
```

The loop executes task after task, verifies each on a real surface (opening the page, comparing against your frozen POC), and logs evidence to the LEDGER. At each phase boundary it offers: _"checkpoint and rotate, or continue?"_ — rotating (fresh session, `/start`, `/spec-run` again) is the designed rhythm, not an interruption. You can also just kill the terminal anytime; the next session recovers from the files.

At the end it parks at **awaiting-final-review** with demo steps. You play the demo. "Confirmed" closes the mission; "the boss wave never spawns" (a defect against scenario S4) reopens exactly the responsible work.

### 7.4 If it gets stuck — escalate by rotating up

```
Spec tower-defense is blocked — LEDGER records: pathfinding rewrite failed
validation twice; no materially different approach found at this tier.
```

Escalation is **the same command from a stronger session** — nothing special to learn:

```
you>  /model opus
you>  /spec-run tower-defense
```

The strong session reads the diagnosis, finds a different approach, unblocks the task, then offers to rotate back down for the remaining routine work. (The executor also self-signals: two failed validations on one task below the strong tier triggers a rotation offer _before_ a third grind.)

## Step 7b — Behavior-preserving refactor (`/refactor`)

```
you>  /refactor migrate the auth module from callbacks to async/await, zero behavior change
```

Same three moves as Step 7, with the refactor overlay on the authoring step: it pins the **baseline** commit, writes `artifacts/behavior-contract.md` from the _pre-change_ code (every observable behavior, IDed B1/V1/…, cited to baseline file:line), maps the **blast radius** by grep (every call-site must end up migrated-with-evidence or explicitly out of scope), and turns equivalence into checkable ROADMAP verifies:

```markdown
- [ ] P2.3 migrate src/auth/session.ts call-sites (verify: differential worktree run — same
      login scenario on baseline vs head, diff of responses is empty)
- [ ] P3.1 delete legacy callback shims (verify: stale-reference sweep for `authCb` → zero hits)
```

Approval and execution are the normal `/spec-run` loop. Done means: old path removed, sweeps clean, zero behavior deltas beyond the ones SPEC enumerates. For a small single-file refactor the agent will tell you `/plan` is enough.

---

# Part 4 — While the work is running

These slot into any of the sizes above, at the moment they're needed.

## Step 8 — Deliberating a hard decision (`/council`, optional companion)

[Council of High Intelligence](https://github.com/0xNyk/council-of-high-intelligence) convenes up to 18 adversarial personas and produces a verdict with preserved dissent. Install via the `--council` install flag (Step 1) or as a plugin: `/plugin marketplace add 0xNyk/council-of-high-intelligence` → `/plugin install council@council-of-high-intelligence`.

Where it fits the flow:

- **During `/spec` drafting** (Step 7.1), when a mission decision is genuinely contested:

  ```
  you>  /council --triad architecture Should the tower-defense demo use canvas or DOM rendering?
  ```

  The one-line verdict lands in SPEC.md as a settled decision; rejected options go to Must-NOT-Have.

- **During `/plan`** (Step 6): record the verdict in the task's **Decision Log** with its dissent criterion ("revisit if bundle size exceeds 500KB").
- **In unblock mode** (Step 7.4): `/council --duo` on the two competing approaches is a fast way to generate the _materially different path_ the convergence rules demand; the verdict goes to NOTES → Decisions and the `replanned` LEDGER entry.
- **Routing verdicts into memory**: a verdict is a _decision_ — task Decision Log or spec NOTES while the work is live; a durable position graduates to `knowledge/` only through the usual capture gates. Never paste a full council transcript into any CLAUDART artifact — one line of outcome plus the dissent criterion is the durable part.

Cost note: the 18 personas run as standard-tier subagents (~650 tokens of always-on agent descriptions after install) and full deliberation is token-heavy by design — use `--quick` or `--duo` for anything that isn't genuinely high-stakes.

## Step 9 — Reviews (explicit request only)

Before a merge or a demo — three specialist agents ship with CLAUDART and **never run automatically**:

> "Run **clean-code-reviewer** on my working diff" — scope discipline + Clean Code triage (standard tier).
> "Run **security-auditor** before we merge this" — OWASP/CWE-mapped audit, writes `security-audit-<date>.md` (strong tier).
> "Have **ui-visual-critic** compare the screenshot against the POC" — adversarial design review (vision-heavy, quota-expensive).

Freshness rule: a verdict is anchored to the commit it reviewed — if you change the code afterwards, re-dispatch; don't keep the stale approval.

## Step 10 — Context window filling up (`/handoff`)

You're two hours into debugging, there's a working hypothesis, and context is nearly full:

```
you>  /handoff
```

It writes `.claude/HANDOFF.md` — objective, hypothesis, evidence as file:line, dead ends already ruled out, your constraints verbatim, and the exact next step. Close the session. The next `/start` offers the baton, re-verifies its evidence against current code, and consumes it. Don't use `/handoff` for spec work (the spec folder is already the baton) or as a session-end ritual (that's the next step).

---

# Part 5 — Closing the loop

## Step 11 — End the session (`/checkpoint`)

```
you>  /checkpoint
```

Rewrites CONTEXT.md to what's true _now_ (dropping what isn't), syncs the task/spec indexes, appends one-liners to the append-only JOURNAL, and flags knowledge candidates. Run it after meaningful work — it's what makes tomorrow's `/start` accurate.

## Step 12 — Teach the agent (`/learn`, when patterns repeat)

You corrected the agent twice this week for the same thing ("stop using Joi, we use Zod"). Or it made an unusual call you liked:

```
you>  /learn
```

It replays the session against the rules, names the rationalization behind each deviation, and writes durable rules like _"NEVER add Joi schemas, even when a file already imports Joi — this repo migrated to Zod (see src/validation/)"_. Behavioral lessons go to `rules/`; project facts route to `knowledge/`; it also checks whether any model-tier choice proved wrong (a "fast" task that needed escalation) and adjusts.

## Step 13 — Health maintenance (`/doctor`, when things feel off)

```
you>  /doctor
```

Read-only: runs the mechanical knowledge checker, then audits wiring, staleness, and misfiled content — it reports, never fixes. If it finds drift in the memory system, the repair loop is `/doctor` → `/refactor-memory` → `/doctor`. Run it after upgrading CLAUDART, or whenever `/start` output looks wrong.

**Upgrading CLAUDART** in an existing project: commit your tree, then rerun the installer with `--upgrade` (layers are auto-detected; add `--claude`/`--codex`/`--both` to override):

```bash
curl -fsSL https://raw.githubusercontent.com/lapnd/Claudart/main/install.sh | bash -s -- --upgrade
```

(On a fork, swap the URL's owner or append `--repo=<owner/name>` — same resolution rules as Step 1.)

It refreshes template-owned files (commands, rules, agents, skills, scripts) and **never touches live state** — CONTEXT, JOURNAL, tasks, specs, knowledge — or your evolved `CLAUDE.md`/`AGENTS.md` (reconcile those via [INTEGRATE.md](../INTEGRATE.md)). Review with `git diff`, then run `/doctor`.

## Step 14 — Sessions feel token-hungry (`/optimize`)

Auto-compact keeps firing mid-session, or work feels slower and more expensive than it should:

```
you>  /optimize
```

A read-only token audit in three passes — **boot cost** (everything a session loads before work starts: CLAUDE.md imports, agent descriptions, and crucially any parent/global `CLAUDE.md` files up the directory tree that don't belong to this project), **session behavior** (the same file read twice, whole-file reads where a grep would do, command output flooded inline, oversized subagent fan-out), and **memory hygiene** (CONTEXT near its ceiling, oversized knowledge topics or NOTES). It names the dominant cause and returns a ranked report:

```
## Token Audit — 2026-08-11
**Compaction diagnosis**: boot cost dominates — 2 workflow rules still @-imported
**Boot surface**: ~9k tokens (budget ~3k) — over

| # | Finding                                  | Est. cost      | Fix                        | Owner     |
| 1 | ~/CLAUDE.md carries another project's config | ~1.7k/session | move it aside              | you       |
| 2 | spec-workflow.md @-imported              | ~8.8k/session  | convert to trigger line    | apply-now |
| 3 | build output streamed inline, 4×         | ~2k each       | redirect + tail            | /learn    |
```

Nothing is changed until you approve the "apply now" subset; behavioral fixes route through `/learn` so they become rules, state trimming routes to `/checkpoint`, and user-level items (foreign parent files, unused MCP servers) come with the exact command for you to run. One built-in honesty rule: if the diagnosis is "long `/spec-run` sessions," the fix is rotating earlier — that's what rotation is for — not trimming.

---

## The three golden habits

1. **`/start` every session, `/checkpoint` after meaningful work.** The files remember so the agent doesn't have to.
2. **Approval is explicit.** The agent parks at `planning` and `awaiting-review` and waits for your words — enthusiasm is not a green light, and that's what keeps it safe to run autonomously in between.
3. **Plan expensive, execute cheap, escalate by rotating.** Author specs/plans on a strong model, run `/spec-run` on the tier the spec recommends, and punch through blocks with the same command from a stronger session.
