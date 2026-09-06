# Law Record Schema (frozen contract)

This document freezes the machine-readable schema for a "law" record — the frontmatter shape
consumed by the law engine's `validate` and `tally` commands. It states every field, vocabulary
term, default, and validation rule needed to implement a validator without further clarification.
Nothing here describes an implementation; `validate` and `tally` are separate nodes that consume
this contract.

A law record is a Markdown file with YAML frontmatter (delimited by `---` lines) followed by a
prose body. The frontmatter fields fall into two groups: the pre-existing rule-file fields
(`paths`, `description`, `when_to_use`, `tags`) and the law-engine fields defined below.

## 1. Field table

| field                 | required                                             | allowed vocabulary / type                                                                                                  | default                                | violation code (if invalid/missing)                                                                                              |
| --------------------- | ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `paths`               | optional                                             | flow or block list of glob strings                                                                                         | none                                   | —                                                                                                                                |
| `description`         | optional                                             | string                                                                                                                     | none                                   | —                                                                                                                                |
| `when_to_use`         | optional                                             | string                                                                                                                     | none                                   | —                                                                                                                                |
| `tags`                | optional                                             | flow or block list of strings                                                                                              | none                                   | —                                                                                                                                |
| `level`               | **required**                                         | `constitution \| law \| convention \| vendor-default`                                                                      | none                                   | `MISSING-FIELD` (absent); `BAD-VOCAB` (invalid)                                                                                  |
| `authority`           | **required**                                         | `core \| standard \| provisional`                                                                                          | none                                   | `MISSING-FIELD` (absent); `BAD-VOCAB` (invalid)                                                                                  |
| `status`              | **required**                                         | `proposed \| approved \| draft \| deprecated \| superseded`                                                                | none                                   | `MISSING-FIELD` (absent); `BAD-VOCAB` (invalid)                                                                                  |
| `since`               | **required**                                         | date (`YYYY-MM-DD`)                                                                                                        | none                                   | `MISSING-FIELD` (absent); `BAD-VOCAB` (unparseable)                                                                              |
| `stale_after`         | **required**                                         | absolute ISO 8601 instant (`YYYY-MM-DDTHH:MM:SSZ`)                                                                         | see Retirement table (D5) when derived | `MISSING-FIELD` (absent); `BAD-STALE-AFTER` (present but not an absolute ISO instant, e.g. a bare date or a relative expression) |
| `verified`            | **required**                                         | list of `{by, at}` mappings; `by` is `human:<id>` or `agent:<id>` (or any `<kind>:<id>` actor tag), `at` is an ISO instant | none                                   | `MISSING-FIELD` (absent); `APPROVED-WITHOUT-HUMAN` (see rule below)                                                              |
| `enforcer`            | **required**, never blank                            | `check:<path> \| hook:<path> \| judgement`                                                                                 | none                                   | `MISSING-FIELD` (absent or blank); `BAD-VOCAB` (does not match one of the three shapes)                                          |
| `overrides`           | optional                                             | one-line flow list of law ids                                                                                              | empty                                  | `OVERRIDES-CONSTITUTION`, `UNDECLARED-OVERLAP` (see D3 rule)                                                                     |
| `supersedes_in_scope` | optional                                             | one-line flow list of law ids                                                                                              | empty                                  | `UNDECLARED-OVERLAP` (see D3 rule)                                                                                               |
| `layers_on`           | optional                                             | one-line flow list of law ids                                                                                              | empty                                  | `BAD-LAYER`, `UNDECLARED-OVERLAP` (see D3 rule)                                                                                  |
| `load`                | **required**                                         | `always \| trigger \| auto \| never`                                                                                       | none                                   | `MISSING-FIELD` (absent); `BAD-VOCAB` (invalid)                                                                                  |
| `order`               | required for `always`/`trigger`; forbidden otherwise | int                                                                                                                        | none                                   | `MISSING-FIELD` (missing where required); `BAD-VOCAB` (present where forbidden, or non-integer)                                  |
| `trigger`             | required for `always`/`trigger`; forbidden otherwise | string (the trigger prose)                                                                                                 | none                                   | `MISSING-FIELD` (missing where required); `BAD-VOCAB` (present where forbidden)                                                  |
| `digest`              | required for `load: trigger`; forbidden otherwise    | string (the exact digest line as it appears in `CLAUDE.md`)                                                                | none                                   | `MISSING-FIELD` (missing where required); `BAD-VOCAB` (present where forbidden)                                                  |

Notes:

- `since`, `stale_after`, `verified[].at` are all absolute instants or dates as specified — none of
  them may be a relative expression (`+30d`, `now`, etc.).
- `overrides`, `supersedes_in_scope`, and `layers_on` are written as one-line flow lists even when
  every other new field is block-style (per D2). They may be empty (`[]`) or absent entirely —
  both mean "no relationship declared."
- `enforcer` accepts `judgement` verbatim, or `check:<path>` / `hook:<path>` with a non-empty
  `<path>`. A value like `check:` (empty path) counts as blank and is `MISSING-FIELD`.

## 2. `load` table

| `load` value | `order`   | `trigger` | `digest`  | reaches compiled `CLAUDE.md` block?                                                                                                        |
| ------------ | --------- | --------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `always`     | required  | required  | forbidden | yes — rendered as `See @.claude/rules/<id>.md <trigger>` in `order` (D10); the trigger text is the sentence tail                           |
| `trigger`    | required  | required  | required  | yes — imported as a trigger line with its digest                                                                                           |
| `auto`       | forbidden | forbidden | forbidden | no — loaded implicitly by the harness because the file carries no `paths:` key and has no `CLAUDE.md` line; not part of the compiled block |
| `never`      | forbidden | forbidden | forbidden | no — never reaches the compiled block (e.g. vendor-default records kept only as override targets)                                          |

A field present where its `load` value forbids it, or absent where required, is `MISSING-FIELD`
(absent-when-required) or `BAD-VOCAB` (present-when-forbidden).

## 3. Retirement table (D5 — fail-soft, tiered by `authority`)

| `authority`   | default `stale_after` offset from `since` (when derived) | grace period before compiled line is marked | marking behaviour once past grace                                                                                                                                                  |
| ------------- | -------------------------------------------------------- | ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `core`        | +12 months                                               | n/a — never visibly marked                  | compiled line renders **unchanged**; expiry is still reported as a queue item by `validate` (finding code `EXPIRED`), exit stays 0 for `EXPIRED` alone                             |
| `standard`    | +12 months                                               | 30 days past `stale_after`                  | compiled line has `⚠ expired <YYYY-MM-DD>, re-verification pending — ` inserted immediately after the em dash (`—`) of the law's `CLAUDE.md` line, once 30 days past `stale_after` |
| `provisional` | +6 months                                                | 0 days (marked at expiry)                   | compiled line carries the same `⚠ expired <YYYY-MM-DD>, re-verification pending — ` marking from the moment `stale_after` passes                                                   |

Marking string, exact and verbatim: `⚠ expired <YYYY-MM-DD>, re-verification pending — ` where
`<YYYY-MM-DD>` is the date `stale_after` fell on. It is inserted after the em dash (`—`) that
already separates the trigger clause from the digest in the law's compiled `CLAUDE.md` line.

Lifecycle:

- Past `stale_after`, a law is `EXPIRED`. `validate` reports it as a queue item; `validate`'s exit
  code stays **0** when `EXPIRED` is the only finding.
- `tally` (the write side) rewrites an `EXPIRED` law's `status` to `draft`. `validate` never writes.
- A new `verified` entry whose `by` is a `human:<id>` actor resets `status` to `approved` (a human
  edit clears expiry).
- These offsets apply only when `stale_after` is _derived_ (not explicitly authored). An explicit
  `stale_after` in the frontmatter always wins.

## 4. Overlap-declaration rule (D3 — compile-time only, no runtime resolver)

Two records are **overlap candidates** when both of the following hold:

1. Their `paths` globs **can overlap** (there exists at least one file path that both globs could
   match), **and**
2. They **share at least one `tags` entry**.

When two records are overlap candidates, at least one of them must declare a relationship toward
the other, in **one direction only** — the reverse direction is not required. A declaration in
either direction satisfies the rule; nothing requires both records to declare it.

- **Which keywords count**: `overrides`, `supersedes_in_scope`, or `layers_on`, each naming the
  other record's law id.
- **Failure**: if neither record names the other via any of the three keywords, validation fails
  closed with `UNDECLARED-OVERLAP` (exit nonzero).
- **Legal targets**:
  - `overrides` may target a record at the **same `level`**, or a record with `level: vendor-default`.
  - `overrides` targeting a record with `level: constitution` is illegal and produces
    `OVERRIDES-CONSTITUTION`, regardless of whether the pair was an overlap candidate.
  - A record with `level: convention` may only `layers_on` a record with `level: law`. A
    `convention` using `overrides` (or `layers_on` a non-`law` target) produces `BAD-LAYER`.
- There is **no runtime resolver**: precedence is established once, at validation/compile time, by
  these declared relationships — nothing is re-resolved when the compiled `CLAUDE.md` is loaded.

## 5. Budget table (D6 — `.claude/budget.yaml`)

| key                       | type    | default                                         | consumed by                                                                                                                             |
| ------------------------- | ------- | ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `project`                 | string  | (the lesson `project` value; no engine default) | both `tally` and `validate` (identifies which project's queue/budget this file governs)                                                 |
| `hours_per_month`         | number  | `4`                                             | `tally` (reviewer-capacity budget, informational to `validate`)                                                                         |
| `max_proposals_per_month` | integer | `4`                                             | `tally` (rate-limits proposal creation per calendar month)                                                                              |
| `proposal_expires_days`   | integer | `30`                                            | `tally` (renames an expired open proposal to `<id>.expired.md`)                                                                         |
| `queue_max_age_days`      | integer | `30`                                            | `validate` (fails closed with `QUEUE-STALE` when any open proposal, or any `EXPIRED` law, is older than this many days past its expiry) |

The template `budget.yaml.template` ships with the install; the live `.claude/budget.yaml` is
created from it on first `install.sh` run and is never overwritten thereafter.

`OVER-BUDGET` (see Finding-code table) fires when `tally` would create a proposal beyond
`max_proposals_per_month` for the current calendar month.

## 6. Finding-code table

| code                     | triggers when…                                                                                                              | emitted by | exit code effect                                                                        |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------- |
| `MISSING-FIELD`          | a required field (per Field table / `load` table) is absent, or a `load`-conditional field is missing where required        | `validate` | nonzero (1)                                                                             |
| `BAD-VOCAB`              | a field's value is not one of its allowed vocabulary/type, or a `load`-conditional field is present where forbidden         | `validate` | nonzero (1)                                                                             |
| `BAD-STALE-AFTER`        | `stale_after` is present but is not an absolute ISO instant (e.g. a bare date, a relative expression)                       | `validate` | nonzero (1)                                                                             |
| `UNDECLARED-OVERLAP`     | two records are overlap candidates (D3) and neither declares `overrides`/`supersedes_in_scope`/`layers_on` toward the other | `validate` | nonzero (1)                                                                             |
| `OVERRIDES-CONSTITUTION` | an `overrides:` entry names a record with `level: constitution`                                                             | `validate` | nonzero (1)                                                                             |
| `BAD-LAYER`              | a `level: convention` record declares `overrides` (of any target), or `layers_on` a target whose `level` is not `law`       | `validate` | nonzero (1)                                                                             |
| `APPROVED-WITHOUT-HUMAN` | `status: approved` and no entry in `verified` has a `by` matching `human:<id>`                                              | `validate` | nonzero (1)                                                                             |
| `EXPIRED`                | the current instant is past a law's `stale_after`                                                                           | `validate` | **exit stays 0 when `EXPIRED` is the only finding** — it is a queue item, not a failure |
| `QUEUE-STALE`            | any open proposal, or any `EXPIRED` law, is older than `queue_max_age_days` past its expiry                                 | `validate` | nonzero (1)                                                                             |
| `OVER-BUDGET`            | `tally` would create a proposal beyond `max_proposals_per_month` for the current calendar month                             | `tally`    | nonzero (1) (from `tally`)                                                              |

`EXPIRED` alone never fails `validate`; every other code in this table produces a nonzero exit
from the command that emits it. `QUEUE-STALE` specifically makes `validate`'s exit code **1**.

## 7. Exit-code table

| exit code | meaning                                                              |
| --------- | -------------------------------------------------------------------- |
| `0`       | clean — no findings (or only `EXPIRED` queue items)                  |
| `1`       | one or more findings reported (validation failed)                    |
| `2`       | usage error or runtime error (bad invocation, unreadable file, etc.) |

## 8. Parser acceptance note

The frontmatter parser accepts equivalent YAML shapes interchangeably:

- **Flow-style lists**: `tags: [a, b]`, `paths: ["**/*"]`.
- **Block-style lists**:
  ```yaml
  tags:
    - a
    - b
  ```
- **One-key mappings** inside a list, e.g. a `verified` entry written as:
  ```yaml
  verified:
    - by: human:x
      at: 2026-08-30T00:00:00Z
  ```
  is equivalent to the same mapping written flow-style: `- { by: human:x, at: 2026-08-30T00:00:00Z }`.

New law-engine fields (Field table, section 1) are written block-style, **except** that
`overrides`, `layers_on`, and `supersedes_in_scope` are always written as one-line flow lists
(e.g. `overrides: [vendor/harness-coauthor-trailer]`), per D2.

## 9. Worked example — a conformant record

`.claude/rules/git-commits.md` (a `law` that overrides a vendor default):

```yaml
---
paths: ["**/*"]
description: Commit authorship and message rules for this workspace.
when_to_use: Before any git commit in this workspace.
tags: [git, commits, authorship]
level: law
authority: standard
status: approved
since: 2026-08-30
stale_after: 2027-08-30T00:00:00Z
verified:
  - by: human:lapnd
    at: 2026-08-30T00:00:00Z
enforcer: judgement
overrides: [vendor/harness-coauthor-trailer]
layers_on: [constitution]
load: trigger
order: 90
trigger: "read before any `git commit` in this workspace."
digest: "use the repo's own configured `user.name`/`user.email` (never hardcode an identity); ..."
---
```

The vendor default it overrides, `.claude/rules/vendor/harness-coauthor-trailer.md`:

```yaml
---
paths: ["**/*"]
description: The harness's standing instruction to end commit messages with an AI Co-Authored-By trailer.
when_to_use: Recorded so that a project law can override it in data rather than prose.
tags: [git, commits, authorship]
level: vendor-default
authority: provisional
status: approved
since: 2026-09-06
stale_after: 2027-03-06T00:00:00Z
verified:
  - by: human:lapnd
    at: 2026-09-06T00:00:00Z
enforcer: judgement
load: never
---
```

`git-commits` is `level: law`, `overrides` targets a `vendor-default` (legal), and it also declares
`layers_on: [constitution]` — a `law` may `layers_on` a `constitution` record (only a `convention`
is restricted to `layers_on` a `law`). Both records carry `verified` with a `human:` actor and
`status: approved`, satisfying `APPROVED-WITHOUT-HUMAN`. Both carry `stale_after` as an absolute
ISO instant and a non-blank `enforcer`.
