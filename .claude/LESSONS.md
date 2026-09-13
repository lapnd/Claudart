# LESSONS

Lessons that were paid for. Each one records what happened, what it cost, the
command that re-derives it, and which rung it landed on.

The ranking, strongest first:

1. **Mechanism** — the failure becomes impossible. Nothing to remember.
2. **Script** — a check that fires, plus one line saying how to run it.
3. **Rule** — prose, for judgement no program can express.
4. **Nothing** — the right answer most of the time.

A lesson that stops at **rule** must say why no mechanism could carry it.
A lesson at **script** is not closed until the check has been _shown to fail_ on
the defect it names; an enforcer never observed failing is decoration.

New lessons go at the top. `/learn` writes here; `/doctor` counts the rungs.

---

## The expensive rule is the one loaded in the wrong place, not the long one

**Cost:** measured across three downstream repositories — **15,671** tokens per
Markdown read in one, **4,826** per book page in another, both recovered by
changing a glob and nothing else.

`paths: ["**/*"]` is what a rule ends up with when a layer is copied into a new
project, and it silently means _load on the first file read, whatever that file
is_. Two symptoms, both measured, neither visible from reading the rules:

- One repo read its own ROADMAPs, SPECs and LEDGERs more than any source file,
  and reading a `.md` cost **77,467** tokens against **69,974** for a `.go` —
  because three rules about production code, security and frontend architecture
  loaded in full on every prose read. All thirteen of its rules carried `**/*`.
- Another is a static book generator: 992 HTML pages, 32 `.js`, 14 `.mjs`, one
  `.py`, no Go, no TypeScript, no Vue. It was loading a 95%-coverage bar,
  authentication, secrets management, OpenTelemetry, SOC 2 and hexagonal ports
  and adapters onto every one of those book pages. Both rule descriptions said
  they applied to "other languages in this workspace" — the workspace they were
  copied from, not the one they were sitting in.

Scope, do not delete, and prove the rule still fires where it should: after
narrowing, reading the build script stayed the most expensive read in the repo,
which is what distinguishes narrowing from disabling.

**Rung:** script for detection, rule for the fix. The detection needs no
judgement at all — if reading prose costs more than reading source, something is
scoped wrong, and the number says so without anyone reading a rule. Choosing the
correct glob does need judgement: it means deciding what the rule governs and
what this repository actually contains, which no program can decide.

**No enforcer on the universal glob itself, deliberately.** Hand-classified across
two repos, a rule matching every path was legitimate more often than not — 8 of 13
rules in one, 2 of 4 in the other — so a check that flagged every occurrence would
run at roughly 40% precision. By the gate two lessons below, an enforcer that fires
that often is wrong about the data. Measure instead of flagging.

**Re-derive:**

```bash
# a mis-scoped rule shows up as prose costing more than source
for p in .claude/CONTEXT.md src/main.go; do
  claude -p --model haiku --output-format json "read $p then reply with exactly: ok" \
    | jq --arg p "$p" -r '.usage.iterations[0] | "\($p) \(.input_tokens + .cache_read_input_tokens + .cache_creation_input_tokens)"'
done
grep -l 'paths: \["\*\*/\*"\]' .claude/rules/*.md   # the candidates, not the verdict
```

---

## One commit changed two things, so the cost landed on the wrong one

**Cost:** a wrong fix worth **24,503 tokens per light session**, reverted in
`257dec6` — then a wrong _explanation_ of it that stood in this file until an
external checker contradicted it.

Two files referenced the same rule, so I concluded it loaded twice and "fixed"
it. The fix regressed light sessions by 24,503 tokens. Measuring the import alone
showed a **6-token** difference, and I wrote that down as _the loader
deduplicates_. Both halves of that account were wrong.

`257dec6` changed two things at once. It rewrote `@.claude/rules/X.md` into plain
backticks, **and** it deleted `paths: ["**/*"]` from all six rules. A rule with no
`paths:` loads unconditionally at launch, so the deletion is what cost 24,503.
The import rewrite cost nothing — because that import had never worked.

A three-way fixture, two repetitions, variance under 3 tokens, settles it:

| `.claude/CLAUDE.md` contains    |      light session |
| ------------------------------- | -----------------: |
| no import at all                |             36,690 |
| `@.claude/rules/ai-behavior.md` | 36,704 &nbsp;(+14) |
| `@rules/ai-behavior.md`         |    37,800 (+1,110) |

**An `@` import resolves relative to the file containing it.** Written from
`.claude/CLAUDE.md`, `@.claude/rules/…` points at `.claude/.claude/rules/…` and
silently resolves to nothing. Every such import in this layer was dead; the rules
were reaching context only through their `paths:` glob on first file read, which
is why nobody noticed. Upstream found and fixed the same defect in
`e5abf05 fix(loading): repair Claude imports`.

A non-resolving import and a deduplicated one are indistinguishable by cost —
both show ~6 tokens — which is exactly why one measurement could not choose
between them, and why I picked the flattering reading.

Two measurement defects sat underneath the original error. Summing `usage` across
a run reports **145,942** where the true figure is **59,931** — a 2.4×
overstatement, since each iteration re-reports the cumulative prompt; only
`usage.iterations[0]` is the session's context cost. And comparing two repo states
in place attributes to the change whatever else moved between runs, which turned a
real **−1,219** into a reported "+328 increase".

**Rung:** script. Detection is fully mechanical and an enforcer already exists —
upstream's `doctor-check.sh` emits `D201 missing local import target`, which named
this defect in our tree on its first run and went silent once the imports were
made relative. Attribution is the part that needs judgement: change one thing per
measurement, or the number cannot say which half caused it.

**Re-derive:**

```bash
bash .claude/scripts/doctor-check.sh --layer claude | grep D201   # silent when correct
claude -p --output-format json 'reply with exactly: ok' \
  | jq '.usage.iterations[0].input_tokens'
```

---

## An enforcer that fires often is wrong about the data

**Cost:** three enforcers built and thrown away; one nearly shipped.

A ledger event-vocabulary check fired **109 times** across the 19-mission corpus.
The corpus was right and the check was wrong: ledger headings are narrative, not
a typed event stream. `delegated` alone appears 89 times, next to
`rotation-checkpoint` (28), `scope-change` (26) and a long tail of one-off names.
The structural fallback — require an `- Evidence:` line — measured worse:
**841 of 1028** entries do not carry one. Both were deleted rather than tuned,
because widening an enum to fit a corpus only defers the next false positive.

Same shape, three more times: a path-existence check produced **83** findings,
all false; `S302` fired **29** times on missions that had _completed
successfully_; and seven parser defects in `spec-check.sh` were visible only
against the corpus, never against a hand-written fixture.

Calibration is not optional polish. It moved this checker from **140** findings
to **24**, hand-classified at **zero** false positives.

**Rung:** script — calibration is now a step in `/learn`, and `/doctor` reports
the ratio.

**Re-derive:**

```bash
for R in <downstream>...; do bash .claude/scripts/spec-check.sh --root "$R" --layer claude; done \
  | cut -d'|' -f1,2 | sort | uniq -c | sort -rn
```

---

## A green suite proves nothing until a test has been seen to fail

**Cost:** a suite that passed **14 of 14** while two of its assertions were dead.

Fixing a false positive, I added a `[ -d ... ] || continue` guard that filtered
away exactly the case the assertion existed to catch. It kept passing. Nothing
distinguishes an assertion that holds from one that cannot fail except injecting
the defect and watching it fire.

Applied to the spec engine, this immediately paid: a healthy-baseline assertion
caught that `check_mission` still read `proves:` as the node supplier after the
same bug had been fixed in `disposition_for` — one half corrected, the other
silently left inverted, which reports implementations as ready before the tests
they depend on.

**Rung:** mechanism — every `S###` in `tests/spec-engine/run.sh` is a mutation,
and a healthy fixture must be silent or every mutation below it proves nothing.

**Re-derive:** `npm run test:spec-engine`

---

## Greedy `.*` across a repeated delimiter cuts at the last one

**Cost:** two separate false-positive classes, found weeks apart in the same file.

The pattern `sub(/^###.*— /, "", n)` applied to this heading:

```text
### 2026-09-13 02:13Z — task-completed P4.8 `adapter/x` — the SPA build is GREEN
```

cuts at the **second** em-dash and yields the id `SPA`, so the real task stays
open forever. POSIX awk has no lazy quantifier, so the fix is `index()` plus
`substr()`, not a cleverer regex.

**Rung:** rule. The defect is a property of the pattern, not of any one file, and
no check can flag every greedy match that happens to be wrong.

---

## Overlap is one rule of three, and both directions of the mistake cost real time

**Cost:** an agent-hour asserting a collision between two tasks whose real file
sets were 31 and 49 files with **zero** intersection; and two finished,
unmergeable tasks from assuming independence when ordering was skipped.

A dependency graph saying two tasks have no edge does not say they can run at
once. Rule 1 is file overlap, and it is measurable. Rule 2 is output dependency
— one task's result changes what another should produce. Rule 3 is ordering,
_including the plan's own phase order_. Neither of the last two is decidable by a
tool, and a clean overlap matrix is necessary, never sufficient.

Two corollaries, each paid for separately. A task declares the **query** that
finds its files, never a file list: a list is today's answer and rots in silence.
And the matcher fails **closed** on an empty match — an empty set means a wrong
pattern far more often than an empty task, and a silent empty set makes every
pair look disjoint.

**Rung:** script for rule 1, rule for rules 2 and 3. `disjoint.sh` prints its own
limits so it cannot be quoted as permission to fan out.

**Re-derive:**

```bash
bash .claude/scripts/disjoint.sh <repo> 'A:<glob>' 'B:<glob>'
```

---

## Serial is a decision that has to be justified

**Cost:** a wave of 39 predicted where 13 actually ran — a 3× over-report, with
20 of the 39 declaring no edges at all.

"I didn't see anything parallel" is not a finding. The over-report came from
reading "no `requires:` edge" as "ready", and the inverse error came from reading
`proves:` as the node supplier when `node:` is the identity — which inverts the
whole dependency map and schedules implementations ahead of the tests that must
fail first.

The fix is that no task is ever _silently_ in or out: every non-done task is
reported as `runnable`, `blocked`, `waiting: <unproven node>`, or `unmodelled`.
Against recorded ground truth the corrected scheduler predicts 19 where 13 ran,
with **13/13 matched, zero false negatives**, and all six extras explained by
named exclusions the tool now prints.

**Rung:** script. `next` prints the obligation whenever more than one task is
runnable, and The Loop requires a `wave-selected` LEDGER entry naming each
excluded task and its rule. Rules 2 and 3 stay prose because no tool decides
them.

**Calibration pending — read before trusting `S404`.** The shape check on
`wave-selected` entries was accepted with its corpus gate _unsatisfied_: the
event has **zero instances** across the 19 missions, so its false-positive rate
is unmeasurable rather than low. It ships as WARN for that reason. Once real
entries exist, re-run the calibration and hand-classify every finding before
promoting it or leaving it as is. An enforcer accepted on no evidence must say so
where the next reader will look.

**Re-derive:**

```bash
bash .claude/scripts/spec-check.sh next --root <downstream> --layer claude
grep -rc 'wave-selected' <downstream>/.claude/specs/   # calibration corpus size
```
