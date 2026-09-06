# Lesson & Hours Record Contract

This document freezes the on-disk record shapes consumed and produced by
`claudart-law.sh lesson`, `claudart-law.sh hours`, `claudart-law.sh tally`, and
`claudart-law.sh agreement`. A later implementer turns this document into those
four commands without asking a clarifying question. It is a specification
only — it contains no executable code.

## 1. Lesson record (D7)

**Storage location**: `.claude/lessons/<year>.jsonl` — one JSON object per
line, UTF-8, no trailing comma, no trailing blank line requirement beyond the
final newline. A file may span multiple calendar years as multiple files
(`2026.jsonl`, `2027.jsonl`, …), selected by the `ts` of the record being
appended.

**Append path**: records are appended **only** through
`claudart-law.sh lesson`. A record must never be appended by a shell
redirect (`echo ... >> .claude/lessons/2026.jsonl`) from a command's prose or
from any other tool — the `lesson` subcommand is the sole writer and is
responsible for id assignment and key validation before the write.

### 1.1 Field table

The key set below is **closed**: a record carrying any key not in this table
is rejected. `confidence` is explicitly named as a forbidden key — no numeric
confidence score is part of this contract because no consumer of the lesson
log reads one.

| Key               | Type            | Required | Allowed values / format                                                                                                       | Example                                                   |
| ----------------- | --------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| `id`              | string          | yes      | `L-<year>-<nnn>`, zero-padded 3-digit sequence, unique within the year's file                                                 | `L-2026-001`                                              |
| `ts`              | string          | yes      | ISO 8601 timestamp with `Z` (UTC)                                                                                             | `2026-09-12T10:00:00Z`                                    |
| `project`         | string          | yes      | free-form project identifier, must match a `project` key in the budget file                                                   | `claudart`                                                |
| `source`          | string          | yes      | provenance pointer; conventionally `ledger:<path>#L<line>` but any stable, de-duplicable string is accepted                   | `ledger:.claude/specs/done/x/LEDGER.md#L212`              |
| `kind`            | string (enum)   | yes      | one of: `correction`, `failed-gate`, `retry`, `escalation`                                                                    | `correction`                                              |
| `signal`          | string (enum)   | yes      | one of: `enforcer-exit`, `failed-gate`, `user-correction`, `self-flag`                                                        | `user-correction`                                         |
| `summary`         | string          | yes      | one-line human-readable description of what was learned                                                                       | `"Agent re-asked before running the deterministic check"` |
| `candidate_law`   | string          | yes      | the candidate law id this lesson is evidence for                                                                              | `law/deterministic-first-scripts`                         |
| `matched_against` | array of string | yes      | law ids (existing rule/law paths) this lesson was checked against; empty array `[]` when none matched                         | `[]`                                                      |
| `extraction_pass` | integer         | yes      | which extraction pass produced this record; `1` or `2` in this contract's fixtures, but the field is an unconstrained integer | `1`                                                       |
| `reviewed`        | boolean         | yes      | whether a human has reviewed this lesson                                                                                      | `false`                                                   |

**Forbidden key**: `confidence` (or any key outside the eleven above) makes
the record invalid. The `lesson` subcommand's write path and any downstream
reader (`tally`, `agreement`) must reject a record carrying it rather than
silently drop the extra key or silently proceed without the missing key.

### 1.2 Worked example — one conformant lesson line

```json
{
  "id": "L-2026-001",
  "ts": "2026-09-12T10:00:00Z",
  "project": "claudart",
  "source": "ledger:.claude/specs/done/alpha/LEDGER.md#L120",
  "kind": "correction",
  "signal": "user-correction",
  "summary": "Agent re-asked the user instead of running the existing deterministic check script.",
  "candidate_law": "law/deterministic-first-scripts",
  "matched_against": [],
  "extraction_pass": 1,
  "reviewed": false
}
```

## 2. Hours record

**Storage location**: `.claude/reviewer-hours.jsonl` — one JSON object per
line, UTF-8, no trailing comma.

**Append path**: records are appended **only** through
`claudart-law.sh hours --minutes N --activity S`, which stamps `ts` at append
time. `tally` reads this file and reports the sum of `minutes` logged in the
current calendar month (converted to hours) as "reviewer-hours logged this
month".

### 2.1 Field table

| Key        | Type    | Required | Format / notes                                 | Example                |
| ---------- | ------- | -------- | ---------------------------------------------- | ---------------------- |
| `ts`       | string  | yes      | ISO 8601 timestamp with `Z` (UTC)              | `2026-09-15T14:30:00Z` |
| `minutes`  | integer | yes      | minutes of reviewer time spent, > 0            | `90`                   |
| `activity` | string  | yes      | free-form label for what the time was spent on | `"proposal review"`    |

### 2.2 Worked example — one conformant hours line

```json
{ "ts": "2026-09-15T14:30:00Z", "minutes": 90, "activity": "proposal review" }
```

## 3. De-duplication rule

Before any threshold counting or reporting, lessons are **de-duplicated by
`source`**: when two or more lesson records share the same `source` value,
they count as **one** lesson. Which single record's fields (e.g. `signal`,
`kind`) represent the de-duplicated entry is an implementation choice, but the
_count_ of de-duplicated lessons, the _set_ of distinct `project` values, and
the _presence_ of at least one non-`self-flag` `signal` are computed over the
full (pre-de-duplication) set of records sharing that `source`, unioned
across all sources — i.e. a `source` group contributes its `project` values
and its `signal` values to the union even though it contributes only one
lesson to the count.

## 4. Threshold rule (D8)

A candidate law (grouped by `candidate_law`) crosses the tally threshold when
**all three** of the following conditions hold, evaluated over its
de-duplicated lessons:

1. **Count**: the number of de-duplicated lessons (distinct `source` values)
   for this `candidate_law` is `>= 3`.
2. **Spread**: the number of distinct `project` values across those lessons
   is `>= 2`.
3. **Deterministic signal**: at least `1` lesson (pre- or post-de-duplication
   — a `source` group counts if any record in it qualifies) has a `signal`
   value that is **not** `self-flag` (i.e. `enforcer-exit`, `failed-gate`, or
   `user-correction`).

If a candidate fails **only** condition 3 (conditions 1 and 2 both hold), the
report's blocked-reason string for that candidate is exactly:

```
blocked: no deterministic signal
```

If a candidate fails condition 1 or condition 2, the blocked-reason string
names the actual counts and the unmet condition, in the form used by the
frozen report shape (§6), e.g.:

```
<n> lessons, 1 project (needs ≥2)
```

A candidate that crosses the threshold is written to `proposals/<candidate-law-id>.md`
(frontmatter `created`, `expires`, `candidate_law`, `lessons`; body = the
lesson summaries) **up to the monthly budget** (`max_proposals_per_month`
from the budget file). A candidate that crosses the threshold but is beyond
the remaining monthly budget is reported as blocked for budget reasons (not
as `blocked: no deterministic signal`), and is not written.

## 5. Agreement rule (D9)

**Pairing rule**: among lesson records that share the same `source`, a pair
is formed from the record with `extraction_pass: 1` and the record with
`extraction_pass: 2` for that `source`. A `source` with fewer than two
records, or without both pass values present, forms no pair and is excluded
from the agreement calculation.

**Agreement**: a pair agrees when the two records' `candidate_law` values are
identical (string equality). The agreement ratio is:

```
agreement = agree / pairs
```

where `pairs` is the total number of pairs formed and `agree` is the number
of those pairs whose `candidate_law` values are equal.

**Output format**: printed to stdout, exactly:

```
agreement: <r> (<agree>/<pairs>)
```

where `<r>` is `agree / pairs` formatted to exactly two decimal places
(e.g. `0.50`, `0.83`), and `<agree>`/`<pairs>` are printed as plain integers.
No trailing text, no trailing newline content beyond the line itself.

## 6. Report shape (`tally`)

`claudart-law.sh tally` prints a Markdown report with exactly the following
sections, in this order. `--json` emits the same data as a JSON document
instead of Markdown; no field in the JSON output has a value the Markdown
does not also show.

1. **Budget** — `hours_per_month`, `max_proposals_per_month`, proposals
   emitted this month over the monthly max, reviewer-hours logged this month.
2. **Proposals** — one line per candidate considered this run: `NEW
proposals/<id>.md — <candidate_law> · <n> lessons (<m> distinct sources) ·
projects: <list> · signals: <breakdown> · oldest <date>` for an emitted
   proposal, or `BLOCKED <candidate_law> — <reason>` for a candidate that did
   not cross the threshold or exceeded the remaining budget.
3. **Open proposals** — one line per still-open proposal file with its age
   and expiry date, followed by the median open-proposal age and the count
   expired this run.
4. **Retirement queue** — one line per law past its `stale_after` date, its
   tier, the date, its current `status`, and the marking decision (e.g.
   `⚠ marked in compiled block (grace over)` or `queued, text unchanged`),
   followed by the counter-tally line
   `counter-tally enforcer_fired_then_human_completed_anyway: <value>` (the
   field is always present; in a mission with no enforcers its value is
   `all 0 (no enforcers in this mission)`).
5. **Classification agreement** — `pairs compared: <n> · agree: <n> ·
agreement: <r>` using the same two-decimal formatting as §5.

See `artifacts/tally-report.example.md` for a full worked report matching
this section list and formatting exactly.

## 7. Validation summary (for implementers)

A record read from either JSONL file must be rejected (and the run must fail
loudly, never silently skip) when:

- it contains any key not in the closed key set for its record type (§1.1,
  §2.1) — `confidence` is the canonical example of a rejected key;
- it is missing any required key from that type's table;
- `kind` (lessons) is not one of the four enumerated values;
- `signal` (lessons) is not one of the four enumerated values;
- `matched_against` is present but is not an array;
- `extraction_pass` is present but is not an integer;
- `reviewed` is present but is not a boolean;
- `minutes` (hours) is not a positive integer.
