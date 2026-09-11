---
paths: ["**/*"]
description: How to read a result correctly — reading exit status, keeping a baseline valid, separating detection from attribution, and pinning what a gate actually means. The mechanics that decide whether evidence means what you think it means.
when_to_use: Before believing any command result, comparison, or baseline; before concluding a change caused a behaviour; before trusting a gate that passed. Read alongside evidence-gauntlet.md, which chooses the layers this rule teaches you to read.
tags: [verification, evidence, baselines, tooling, attribution]
level: law
authority: core
status: approved
since: 2026-09-03
stale_after: 2027-09-03T00:00:00Z
verified:
  - by: human:lapnd
    at: 2026-09-03T00:00:00Z
enforcer: judgement
layers_on: [ai-behavior, evidence-gauntlet]
load: auto
---

# Verification Mechanics

`evidence-gauntlet.md` decides **which layers to run**. This rule is about **whether the result you read means what you think it means**. Both are needed: a perfectly chosen gauntlet reported through a misread exit code proves nothing, and every failure catalogued below passed a check while being wrong.

The premise: the dangerous failure is never a loud error. It is a green result produced by something that never ran, a comparison against a baseline that quietly stopped applying, or a correct reproduction attached to the wrong cause.

## 1. Exit status — NEVER read `$?` after a pipeline

A shell pipeline's status is the **last** command's status. Piping a build, a test run, or a script into `tail`, `head`, `grep` or `sed` and then reading the status reports the formatter's success, not the work's.

- **YOU MUST** redirect the command's output to a file and capture its exit code on the command's own line, then read the file. Never `command | tail` followed by a status read.
- **NEVER** accept a success status for a long job that finished suspiciously fast. Open the output and find **positive evidence** — a pass count, a summary line, the artifact on disk. Absence of an error is not presence of a result.
- **Resolve the interpreter or binary before invoking it.** A launcher (`timeout`, `xargs`, `env`, `nohup`) that cannot find its target fails _itself_; through a pipe that failure is invisible. Confirm the executable exists rather than assuming it is on `PATH`.
- **NEVER** use a process-name search to decide whether a job is still running without excluding the search's own command line — it matches itself and reports RUNNING forever.
- **The same self-match kills, not just misreports.** NEVER pass a pattern to `pkill`/`pkill -f` that appears anywhere in a command you are about to run — the harness wraps a backgrounded command in a shell whose command line contains that command text verbatim, so the pattern matches its own launcher. The rationalization to refuse is _"the kill runs first, so ordering protects me"_: it does not, because the wrapper being matched is the one you are creating. Kill by PID taken from a prior `ps`, and NEVER put a kill and a launch in the same shell line (`.claude/lesson.md`, `pkill -f` entry).
- **An empty output file means the job never ran — check that before interpreting its exit code.** A job that failed produces output; a job that was killed or could not launch produces none. Read the size of the output before reasoning about the status, or a process-control failure gets attributed to the code under test.
- "File not found" and "content not present" share an exit code in most search tools. When a search claims something is missing, **confirm the path exists** before believing the absence — especially when it contradicts something you just did.

This has recurred three times in one session (`.claude/lesson.md` §10). It is not an attention problem; a status read through a pipe is structurally the wrong status. Treat the pattern as banned, not as something to be careful about.

Every bullet above is one shape: **the machinery around the job failed, and its failure was reported as the job's own result** — the formatter's status, the launcher that never launched, the search that matched itself, the kill that hit its own wrapper. So before believing any status, name which process produced it. IMPORTANT: when a result is about to be attributed to the code under test, that attribution is only valid once the harness has been excluded as the source — §3's detection-versus-attribution rule applied to your own tooling.

## 2. A baseline is a measurement of tree × environment × build state

`evidence-gauntlet.md` requires recording pre-existing failures as a baseline before claiming "no new failures". That baseline **expires**, silently, and comparing against an expired one manufactures phantom regressions.

- **YOU MUST record the baseline's preconditions inside the baseline artifact**: which tools were installed (a test that skips without a binary starts _running_, and possibly failing, once someone installs it), what build output was present, and the exact command and flags. A baseline that does not state its own preconditions is a trap for the next session.
- **IMPORTANT: gitignored build output is part of the state and `git status` will not warn you.** Staged dependencies, generated assets, compiled fixtures — a clean working tree says nothing about them. In this repo the specific instance is the umbrella chart's staged subcharts; see `.claude/knowledge/verification-gates.md`.
- **Compare in both directions.** A failure that _disappeared_ is exactly as suspicious as one that appeared, and means the same thing: an unexplained change. NEVER report only the new ones.
- **Both sides must be run with identical flags.** A coverage-enabled run and a coverage-disabled run are not a comparable pair.
- **When a comparison shows unexpected drift, re-run the baseline commit in the current environment** — a worktree at the base ref costs one command and converts speculation into a controlled two-way result. **NEVER** resolve drift by reasoning about which failures "look environmental"; that is the rationalization that lets a real regression through wearing the same clothes.

## 3. Detection is not attribution — they are separate experiments

Reproducing a failure proves the behaviour **exists**. It does not prove your change **caused** it. These feel like one step and are two.

- **YOU MUST run the same reproduction against the pre-change baseline before claiming your change introduced anything** — and before claiming you found a defect at all. This session produced a valid reproduction of a template nil-pointer, from which the wrong conclusion was drawn: the pre-change code had the same flaw two lines further down (`.claude/lesson.md` §11).
- The strongest form of an unchanged-behaviour claim is a **byte-diff of the output** old-vs-new across the real configurations, not a reading of the diff. Prefer producing that artifact over arguing from the source.
- This cuts both ways: **NEVER** dismiss a finding as pre-existing without running the baseline either. "It was probably already broken" is the mirror-image rationalization.
- **An alarming measurement is a reason to re-derive the measurement, not to act on it.** The louder the result, the more likely it is that the command, not the code, is what went wrong. When a command spans two repositories or working trees, **every** git invocation in it needs its own `-C` — including ones nested inside command substitution, where a missing one silently answers a question about the wrong tree (`.claude/lesson.md` §13). If an alarm was already raised to the user, the retraction must be as prominent as the alarm was.

## 4. Pin what a gate means, not merely what version produces it

`evidence-gauntlet.md` requires pinning dev-tool versions. **That is necessary and not sufficient.** A linter, formatter or type checker with no rule set declared in-repo means the gate's meaning is whatever the installed tool defaults to — and a version bump is precisely the event that silently redefines it.

- **YOU MUST declare the rule set explicitly in-repo, next to the version pin.** Verifiable by reading the config file: a tool invoked by CI with no corresponding configuration section is a finding.
- **Before adopting a new version of any gate tool, run the old and new versions against the declared configuration and diff the findings.** Identical output is what makes the adoption behaviour-preserving; anything else is a behaviour change that needs its own review.
- **NEVER widen a rule set as a side effect of an upgrade.** Adopting the tool and adopting its new opinions are two changes; land them separately so a reviewer can read each.
- **When you first touch a gate, run it and read its exit code before changing anything.** The baseline is a measurement, not an assumption. In this repo that single command surfaced a lint gate that had been red on `main` for a month (`.claude/lesson.md` §9).

## 5. A gate that cannot fail is not a gate

This extends `evidence-gauntlet.md` §6's negative-control requirement from home-grown checkers to **anything you are about to report as passing**.

- **NEVER report a green gate you have not seen go red.** Feed it a known-bad input, watch it fail, remove the input — and confirm the removal with a diff, not by eyeball.
- A check that scores "0 items to examine" is fail-open and must be treated as a failure of the check, not a pass of the subject.
- **Apply the same question to your verification harness, not only to the subject**: _if the thing I am checking for had actually happened, would this check have said so?_ A mutation runner that verified restores with `git diff` against `HEAD`, while the implementation under mutation was uncommitted, could never have detected a bad restore — and nothing in its output looked wrong (`.claude/lesson.md` §14). Diff against an explicit saved copy, which is correct whether or not the baseline is committed.

## Anti-Patterns

- Reading a status through a pipe, then reporting the job succeeded.
- Comparing against a recorded baseline without checking the conditions it was recorded under.
- Reporting only new failures from a comparison, never the disappeared ones.
- Concluding "my change broke this" or "this was already broken" without running the baseline.
- Treating a version pin as though it pinned the gate's meaning.
- Explaining away drift instead of re-running the base ref in the current environment.
