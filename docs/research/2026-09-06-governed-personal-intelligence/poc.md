# POC Design — the smallest experiment that can validate the concept

Companion to [`README.md`](README.md). This is a _design_, not a plan; a `/spec` would freeze it. Nothing here should be built before the research conclusions in the README are accepted.

## 1. Hypotheses the POC must be able to falsify

| #   | Hypothesis                                                                                                                                                                                                                                                                        | Falsified if                                                                                                                                                                                                                                                                                                                                                   |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| H1  | A single canonical rule source can be **compiled** into every agent's native context format (Claude Code, Codex, Cursor, Gemini, Copilot) and into deterministic enforcers, with zero hand-maintained mirrors.                                                                    | Any target drifts from the source after two weeks of normal use, or a target needs hand edits the compiler cannot express.                                                                                                                                                                                                                                     |
| H2  | Encoding laws as **enforcers** (hooks, lint rules, check scripts) rather than prose measurably lowers per-session context cost _and_ raises compliance.                                                                                                                           | Boot-context tokens do not drop by ≥30% relative to the prose baseline, or violations caught deterministically are < violations caught by review.                                                                                                                                                                                                              |
| H3  | A **two-project** setup starts the second project non-zero: lessons and rules from project A are active in project B at first session, with no re-explanation.                                                                                                                    | The second project's first session re-derives ≥2 rules already present in the personal layer.                                                                                                                                                                                                                                                                  |
| H4  | An **evidence-tallied promotion ledger** produces rule promotions a human accepts at a higher rate than agent-judged `/learn` proposals, with the reviewer **blinded** to which pipeline produced each proposal (v2).                                                             | Acceptance rate of tallied proposals is not higher than the unassisted baseline over ≥10 blinded proposals.                                                                                                                                                                                                                                                    |
| H5  | Precedence + scope resolution is enough conflict handling for the norm corpus at this scale (< 200 rules), **and the conflict problem exists**: ≥3 real cross-level conflicts in the repo's history where plain conjunction gave the wrong answer (v2, council kill criterion 1). | ≥2 conflicts per month need ad-hoc adjudication the ladder cannot express. _Historical count done 2026-09-06: 3 hard collisions, all resolved at authoring time (`conflict-count.md`), so the POC builds compile-time declaration checking (`overrides:` / `supersedes_in_scope:` / `layers_on:`, fail-closed on undeclared overlap) and no runtime resolver._ |
| H6  | **Retirement works**: a deliberately wrong law planted at the start is degraded and surfaced for review within 30 days without any human noticing it by chance (v2, council).                                                                                                     | The planted law is still fully in force at day 30.                                                                                                                                                                                                                                                                                                             |
| H7  | **The layer pays for itself in the reviewer's own time**: net reviewer-hours (hours spent on proposals and re-verification minus hours saved re-explaining rules) are ≤ 0 over the four weeks (v2, council).                                                                      | Net reviewer-hours are positive, or the proposal queue in either project goes unreviewed past 30 days.                                                                                                                                                                                                                                                         |

If H1 and H2 fail, the concept is not worth pursuing in this form: the layer would be another prose dump. H3 is the cross-project claim. H4 can fail without killing the concept. H5's conflict count has been taken: precedence exists but is authoring-time, so the POC ships a declaration lint and no resolver. H6 and H7 are the council's additions: a promotion pipeline with no working retirement, or one that costs the reviewer more than it saves, fails even if every other hypothesis passes.

## 2. Scope fence (Must-NOT-Have)

- No database server, vector store, embedding pipeline, or graph DB. Files in Git only. Search is `rg` plus the routed index.
- No new rule language. Rules are Markdown with a YAML frontmatter schema validated by a fail-closed checker.
- No MCP server for _laws_ in the POC. The knowledge bundle may be served by `okf mcp` (user decision, README §8) because that binary already exists and was verified; laws reach agents only through compiled files. The POC proves the compile-and-distribute path first because it works for every agent today.
- No org layer. Two scopes only: personal and project. The org layer is the same mechanism with one more overlay; proving two proves the mechanism.
- No LLM-judged compliance auditing. Compliance evidence comes from enforcer exit codes and from the existing review gates.
- No autonomous rule promotion. The ledger _proposes_; a human merges.
- No autonomous deletion either (v2): retirement degrades and surfaces; only a human deprecates.
- No steps beyond README §15 step 3 until a committed evidence file carries real H1/H2 numbers (v2): the compiler enforces this itself.

## 3. Minimal shape

```
~/intelligence/                      # the personal state — one git repo, private
├── constitution.md                  # L1: ranked principles (exists today as rules/constitution.md)
├── laws/                            # L2: one rule per file, frontmatter schema below
│   ├── deterministic-first.md
│   ├── test-first.md
│   └── no-copyleft-deps.md
├── knowledge/                       # OKF v0.2 bundle (index.md, log.md, concepts); validated/searched/served by `okf`
├── budget.yaml                      # reviewer hours per month; the tally rate-limits proposals to it
├── lessons/                         # append-only: one JSONL line per lesson, with provenance
│   └── 2026.jsonl
├── proposals/                       # candidate laws generated from lessons; PR-reviewed
├── compile/                         # the compiler (bash/python; no deps)
│   ├── targets/claude-code.tmpl     # → .claude/CLAUDE.md fragment + .claude/rules/*.md
│   ├── targets/agents-md.tmpl       # → AGENTS.md (Codex, Gemini, Copilot, Cursor via agents.md)
│   └── enforcers/                   # → hooks, pre-commit, semgrep/OPA rules per law with an enforcer
└── ledger/                          # promotion tally: lesson → law → principle, with counts
```

A project adopts the layer with one command that (a) pulls the personal repo at a pinned revision, (b) applies the project's overlay (`.intelligence/overlay/` — the same schema, scope narrowed), (c) compiles targets and enforcers into the project's native locations, (d) installs the hooks. CLAUDART's `install.sh --upgrade` already does (a)+(c) for one target; the POC generalizes it.

### 3.1 Law frontmatter (the one schema the POC introduces)

```yaml
---
id: law/deterministic-first
level: law # constitution | law | convention
authority: standard # core | standard | provisional — deliberative weight, independent of enforcer; also the expiry tier (v2)
overrides: [] # law ids this law deliberately overrides where scopes overlap; the compiler fails on an undeclared overlap (v2)
status: approved # proposed | approved | draft (expired, awaiting re-verification) | deprecated | superseded
since: 2026-09-06
stale_after: 2027-09-06T00:00:00Z # OKF field; mandatory; approval + 12 months for enforced laws, + 6 for judgement (v2)
verified: # OKF field; the human merge IS the verification event (v2)
  - by: human:lapnd
    at: 2026-09-06T10:00:00Z
version: 3
derives_from: [constitution/5, constitution/11] # traceability upward
scope: ["**/*"] # paths, or a project/org selector
supersedes: []
evidence: # traceability downward
  lessons: [L-2026-014, L-2026-031, L-2026-047]
  projects: [claudart, project-b]
enforcer: hook:pre-tool-use/deterministic-first.sh # or `judgement` — never blank
not_covered: "Cannot see a repeated LLM task that never becomes a tool call." # what the enforcer misses (v2, optional until step 4)
digest: "If a task can be reliably scripted, create/reuse the script instead of re-asking an LLM."
---
```

Three fields carry the whole idea: `enforcer` (a law with no enforcer must say `judgement`, and the compiler treats those differently), `evidence` (a law points at the lessons that produced it, so promotion is auditable), and `stale_after` (a law that is never re-verified degrades on a clock that enforcement cannot silence). Expiry is fail-soft and tiered by `authority` (decided 2026-09-06): `core` never degrades below `block` and expiry only queues; `standard` degrades to `warn` after a 30-day grace; `provisional` degrades to `warn` at expiry. In every tier `status` flips to `draft`, one review-queue item is emitted, and a new `verified` entry by a `human:` actor resets the clock. Only a human deprecates.

### 3.2 Lesson record

```json
{
  "id": "L-2026-047",
  "ts": "2026-09-06T10:12:00Z",
  "project": "claudart",
  "source": "ledger:.claude/specs/2026-09-06-x/LEDGER.md#L212",
  "kind": "correction",
  "signal": "user-correction",
  "summary": "Agent re-asked the LLM to regenerate a sorted manifest three times; a script would have been deterministic.",
  "candidate_law": "law/deterministic-first",
  "matched_against": ["law/deterministic-first", "law/reuse-before-creating"],
  "extraction_pass": 1,
  "reviewed": false
}
```

Lessons are extracted by the existing `/learn`, `/checkpoint`, and spec `→ graduate:` flags — the POC does not add a new extraction step, it adds a _destination with a schema_. v2 changes: `signal` names the source class (`enforcer-exit | failed-gate | user-correction | self-flag`); `matched_against` records the law ids the extractor considered, retrieval-style, so a candidate is justified against the corpus rather than recalled; the former `confidence` number is gone (no producer, no consumer). On a sample of corrections a second, independent extraction pass runs and the two `candidate_law` values are compared: that is the classification-agreement metric, measured from the first week because the classification step is already live in `/learn`.

### 3.3 Promotion ledger

A script folds `lessons/*.jsonl` and reports, per candidate law: distinct provenance pointers (duplicates collapse), distinct projects, distinct sessions, signal mix, last seen, and whether an approved law already covers it. A candidate crossing the threshold (default: ≥3 de-duplicated lessons across ≥2 projects, at least one from a deterministic signal) generates a `proposals/<id>.md` PR draft, subject to the monthly rate in `budget.yaml`; a proposal carries `expires` (30 days) and closes as `expired` if unmerged. The same script runs the retirement side: it lists laws past `stale_after`, the counter-tally `enforcer_fired_then_human_completed_anyway` per law, and median proposal age. A human merges. **Nothing promotes itself, and nothing entrenches itself silently.**

## 4. Evaluation protocol

Run for four weeks across two real projects (this repo and one downstream project). _Compressed for the first run (2026-09-06, user asked for a two-day build): the spec mission `governed-intelligence-poc` measures H2 at the pinned baseline versus HEAD, H6 with a planted expired law, and classification agreement over 20 historical corrections extracted twice, on this repo plus a fresh scaffold; the four-week window remains the protocol for the real downstream project afterwards._

| Metric                        | How measured                                                                                                                                                              | Baseline                    | Target                                   |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- | ---------------------------------------- |
| Boot context (tokens)         | Count tokens of everything auto-loaded at session start, before and after compilation                                                                                     | current CLAUDE.md + imports | −30%                                     |
| Seeded-violation recall       | Plant N known violations per enforced law in a scratch branch; count how many the enforcer catches (v2; replaces catch-rate, whose denominator shrank as review degraded) | 0 (today: 1 hook)           | ≥ 90% of seeded violations               |
| Mirror drift                  | `diff` compiled targets vs regenerated targets weekly                                                                                                                     | manual Codex mirror         | 0 lines                                  |
| Cold-start reuse              | # rules active in project B's first session that came from the personal layer                                                                                             | 0                           | all approved laws                        |
| Promotion precision (blinded) | accepted proposals ÷ generated proposals, reviewer blinded to origin                                                                                                      | `/learn` unassisted         | higher                                   |
| Classification agreement      | share of sampled corrections where two independent extraction passes name the same `candidate_law` (v2)                                                                   | unknown                     | ≥ 0.9, else the tally input is untrusted |
| Retirement latency            | days from planting a deliberately wrong law to its degradation and appearance in the queue (v2, H6)                                                                       | never                       | ≤ 30                                     |
| Net reviewer-hours            | hours on proposals and re-verification minus hours saved re-explaining, from `budget.yaml` and a simple log (v2, H7)                                                      | —                           | ≤ 0                                      |
| Median proposal age           | age of open proposals, weekly (v2)                                                                                                                                        | —                           | < 14 days; none past `expires`           |
| Unresolved conflicts          | conflicts needing ad-hoc adjudication per month                                                                                                                           | —                           | ≤ 1                                      |

Every metric has a negative control: break a law on purpose in each project and confirm the enforcer fires (fail-closed proof), remove a lesson to confirm the tally drops, plant an expired `stale_after` and confirm the degradation event, and starve `budget.yaml` to confirm proposal generation stops.

## 5. Why this is the smallest experiment

- It reuses the existing constitution, rules, `/learn`, LEDGER and knowledge machinery unchanged.
- It introduces exactly one schema (law frontmatter, reusing OKF's trust and lifecycle fields rather than inventing them), one log (lessons), one budget file, one script family (compile + tally, where the tally also runs retirement), and one adoption command. The knowledge bundle's tooling is bought (`okf`), not built.
- It proves the cross-project claim with the minimum number of scopes (two) and the cross-agent claim with the minimum number of targets that have distinct formats (Claude Code native, and the `AGENTS.md` standard which covers Codex, Gemini, Copilot and Cursor).
- Every hypothesis has a falsifier and every metric has a negative control.

## 6. Evolution path after a successful POC

1. Add the org overlay (same schema, one more layer in the compile order).
2. Expose the compiled rule set and the routed knowledge index as an MCP server (read-only resources) so non-file-based agents can query the same layer.
3. Index `lessons/*.jsonl` and ledgers into a local SQLite FTS table for cross-project search — still no server.
4. Only if retrieval quality becomes the bottleneck at > ~1,000 knowledge topics: add embeddings behind the same router interface. This is the first point where a vector store earns its place.
