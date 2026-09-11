---
paths: ["**/*"]
description: Bounded routing, capture, schema, lifecycle, and validation contract for durable descriptive knowledge under `.claude/knowledge/`.
when_to_use: Whenever project knowledge is read, searched, created, updated, routed, normalized, or reviewed.
tags: [knowledge, memory, routing, validation]
level: law
authority: standard
status: approved
since: 2026-07-30
stale_after: 2027-07-30T00:00:00Z
verified:
  - by: human:lapnd
    at: 2026-07-30T00:00:00Z
enforcer: judgement
load: trigger
order: 70
trigger: "read before writing to `.claude/knowledge/` or routing beyond the root INDEX."
digest: "patch the existing owner, update topic + route atomically, run `bash .claude/scripts/knowledge-check.sh` after any mutation; never auto-delete knowledge."
---

# Knowledge Management

This rule is the semantic source of truth for `.claude/knowledge/`. Knowledge is durable descriptive fact, not task state or behavioral instruction.

## Retrieve With Progressive Disclosure

- Read `.claude/knowledge/index.md` first. Follow at most 2 matching `_maps/` routes, then at most 3 direct topics and 2 one-hop `related` topics.
- Rank direct topics by exact name/alias, typed scope or symbol, trigger, title/description/type, then source match. Treat non-`stable` material as context to verify, not current authority.
- For each topic, inspect frontmatter and the heading outline first, then the smallest relevant section. Read the full body only when those layers cannot answer the question.
- If routed context is still insufficient, search actual repository evidence with bounded `rg` and Git queries across knowledge, task/spec artifacts, JOURNAL, docs, and source. There is no recall command, and retrieval never writes or changes trust state.

## Capture And Route

Promote a claim only when it is descriptive, durable beyond the current work, current rather than proposed, and supported by evidence. A fact may be scoped to a path, component, platform, environment, or version; it need not apply project-wide.

- WIP, proposals, acceptance state, and task/spec chronology stay in the active task, spec, or `CONTEXT.md`.
- Behavioral conventions and recurring corrections belong in `.claude/rules/`, normally through `/learn`.
- Uncertain or conflicting observations stay as candidates in the owning work artifact, or make an existing owner `draft` with a `status_note` explaining the uncertainty; never present them as canonical fact.
- Do not auto-write after every exploration. Promote immediately only when the user asks in natural language, a verified correction is needed to avoid continuing from a known-wrong fact, confirmed source drift requires an owner trust/content update, or a lifecycle command reaches its promotion boundary. `/checkpoint` bulk-maintains remaining candidates and routing, but is not the only write gate.

Before writing, confirm `.claude/scripts/knowledge-check.sh` exists. A missing checker is a High-severity installation problem and blocks the mutation. Patch the existing canonical owner before creating a topic. Every mutation updates the topic and its reachable root/domain-map route atomically, preserves curated titles, hooks, grouping, ordering, and external routes, and then runs:

```bash
bash .claude/scripts/knowledge-check.sh
```

Bundle conformance is `okf validate .claude/knowledge` exiting 0 (non-strict; `--drift` not required) together with this checker exiting 0.

Never auto-delete knowledge or auto-promote an ambiguous unindexed file.

## Canonical Frontmatter

Topic frontmatter requires `name`, `description`, `type`, `status`, and `updated`. A `stable` topic also requires `last_verified`, at least one of `sources` or `verify`, `generated.by`/`generated.at`, and a `verified` list with at least one `human:<id>` actor. A `draft` or `deprecated` topic carries `status_note` explaining its trust state and next action or successor.

Optional fields are `aliases`, `triggers`, `scope`, `last_verified`, `sources`, `related`, `supersedes`, `verify`, `status_note`, `generated`, `verified`, `stale_after`, and `sensitivity`.

- Topic `type`: `domain`, `architecture`, `integration`, `glossary`, `reference`, or `agent-context`.
- `status`: `draft | stable | deprecated`, replacing the prior four-value vocabulary (`active` → `stable`, the under-review state → `draft`, `superseded`/`retired` → `deprecated`, keeping `supersedes` pointed at the successor).
- `sensitivity`: `public`, `internal`, or `restricted`.
- `name` is a bare lowercase kebab slug that exactly matches the file basename. `type`, `status`, `sensitivity`, `updated`, and `last_verified` are bare safe tokens or `YYYY-MM-DD` dates.
- `description`, `verify`, and `status_note` are one-line double-quoted strings.
- `sources` items are one-key mappings: `- resource: "<path-or-url>"`.
- `generated` is a mapping of `by` (the producing actor, `<kind>:<id>`, e.g. `claude-code/claude-fable-5-1`) and `at` (an ISO instant); `verified` is a block list of `{by, at}` entries using the same `<kind>:<id>` actor convention, and a `stable` topic needs at least one `human:<id>` entry.
- `stale_after` is optional: an absolute ISO instant after which the topic should be re-verified.
- `related` items are typed as `knowledge:<slug>` or `rule:<slug>`; `supersedes` items are `knowledge:<slug>`.
- `scope` items are typed selectors such as `path:<glob>`, `symbol:<name>`, `component:<name>`, `platform:<name>`, `environment:<name>`, or `version:<name>`.
- Every list uses its key on one line followed by two-space-indented block items, each double-quoted (the `sources`/`generated`/`verified` mapping items nest double-quoted scalars under their own keys); omit empty lists. Do not use flow lists, folded or multiline scalars, single quotes, inline comments, YAML anchors/tags, or unrecognized fields.
- `updated` is the date of the latest content edit. `last_verified` changes only when evidence is checked.

## Maps And Size Bounds

Every route is one line with no date:

```text
- [Title](relative.md) — <compact hook> · <type|map> · <status>
```

Domain maps live at `_maps/<domain>.md`, use the same metadata grammar with `type: map`, and allow only `stable` or `draft`; stable-map evidence requirements and draft `status_note` are the same as for topics. Maps do not use `related` or `supersedes`. Routing is root → domain map → topic only; maps never nest. Root may also preserve existing local external-document routes. Create domain maps when stable topics exceed 24 or the root router exceeds 1,200 visible words. A topic over 10 KiB is an outline/section-first split candidate, never an automatic split.

Every stable topic must be reachable from the root exactly once through a direct route or one domain map. A draft topic may remain unindexed while ownership is ambiguous; if routed for visibility, route it at most once and never present it as stable authority.
