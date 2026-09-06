# Evidence Gate

This document specifies the contract for the evidence file that gates
`claudart-law.sh compile` targets other than `claude-md`. It is a
specification only — it defines the file, the gate rule, and the exact
output strings a later implementer must produce. It does not implement
the gate.

## 1. File name and location

The gate reads a JSON evidence file from one of two locations, in this
order:

1. The path named by the `CL_EVIDENCE` environment variable, if that
   variable is set. This override wins whenever it is set, regardless of
   whether `.claude/law-evidence.json` also exists.
2. Otherwise, `.claude/law-evidence.json` at the repository root's
   `.claude/` directory.

If neither location resolves to a readable, valid file (see §2), the
evidence file is treated as **absent**.

## 2. Required keys

The evidence file MUST be a JSON object containing all four of the
following keys. A missing key, an unparsable file, or a key whose value
does not match its declared type makes the gate treat the entire evidence
file as **absent** — there is no partial credit for three valid keys and
one wrong one.

| Key                     | JSON type | Meaning                                                                                      |
| ----------------------- | --------- | -------------------------------------------------------------------------------------------- |
| `h1_zero_diff_days`     | number    | How many consecutive days the compiled `CLAUDE.md` law block has regenerated with zero diff. |
| `h2_boot_tokens_before` | number    | The always-loaded context cost, in tokens, before the law layer landed.                      |
| `h2_boot_tokens_after`  | number    | The always-loaded context cost, in tokens, after the law layer landed.                       |
| `recorded_at`           | string    | When the measurement was taken (ISO-8601 recommended; the gate only requires a string).      |

No other keys are required or given meaning by the gate. An implementer
MUST NOT add a numeric field to this contract without a producer (a
measurement script) and a consumer (a gate rule that reads it) — see the
project's `code-quality`/`engineering` rules on unsupported abstractions.

## 3. Gate rule

The gate is a function of two inputs: which `--target` was requested, and
whether a valid evidence file (per §2) is present. It produces one of four
behaviours:

| Target          | Evidence valid?                 | Behaviour                                                                                                                                                                                                                                       |
| --------------- | ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `claude-md`     | irrelevant                      | Proceed normally (see D10: regenerate/`--check` behaviour). The gate never applies to `claude-md`.                                                                                                                                              |
| not `claude-md` | no (absent or invalid)          | **Refuse** — see §4. Exit 2, stderr message, no file written.                                                                                                                                                                                   |
| not `claude-md` | yes                             | **Dry-run only** — see §5. Exit 0, single stdout line, no file written. There is no non-dry-run path for any target other than `claude-md` in this mission (see §6).                                                                            |
| not `claude-md` | yes, but `--dry-run` not passed | Same refusal as the "no evidence" row: without `--dry-run`, no emitter exists for this target regardless of evidence, so the compiler exits 2 with the same stderr message (§4). Evidence unlocks the dry-run path only, never a real emission. |

## 4. The exact refusal

When the gate refuses (target is not `claude-md`, and either no valid
evidence is present, or `--dry-run` was not passed):

- Exit code: **2**
- Message goes to **stderr**, not stdout.
- The message is verbatim, with no trailing punctuation added and no
  substitution:

```
target beyond README §15 step 3 requires .claude/law-evidence.json
```

## 5. The exact dry-run line

When the gate allows dry-run (target is not `claude-md`, valid evidence is
present, and `--dry-run` was passed):

- Exit code: **0**
- Stdout is **exactly** the following line, with `<name>` substituted by
  the requested target name, and **nothing else written to stdout**:

```
target: <name> (dry-run; no emitter in this mission)
```

For example, `--target agents-md --dry-run` with valid evidence prints
exactly:

```
target: agents-md (dry-run; no emitter in this mission)
```

## 6. Write-nothing guarantee

Neither the refusal path (§4) nor the dry-run path (§5) may create,
modify, or delete any file under `.claude/`. This is a testable property:

```
git status --porcelain .claude
```

must produce byte-identical output immediately before and immediately
after either path runs.

## 7. Scope fence

- No target other than `claude-md` has an emitter in this mission. There
  is no code path, present or planned within this mission, that writes
  AGENTS.md, `.cursor/rules`, a Codex mirror of laws, or any other output
  for a non-`claude-md` target.
- `--dry-run` for a non-`claude-md` target prints only the name line in
  §5 — it never previews, diffs, or describes content, because no content
  is ever produced.
- The gate is enforced by the compiler itself (`claudart-law.sh compile`),
  never by a roadmap entry, a comment, or reviewer discipline. The
  compiler must refuse mechanically per §3–§4 even if every human involved
  intends to add a second target responsibly.

## 8. Why this gate exists

Adding a second compile target is easy to justify in the moment and easy
to regret later: it multiplies the surface the compiler must keep correct
without multiplying the evidence that the first target is working. This
gate makes "expand to a second target" require recorded evidence — that
the `claude-md` block has been stable (`h1_zero_diff_days`) and that the
law layer's boot-token cost is known and accounted for
(`h2_boot_tokens_before`/`h2_boot_tokens_after`) — rather than momentum or
convenience. Until that evidence exists, the compiler mechanically refuses
to grow, so the decision to expand is made deliberately, once, with
numbers in hand, not accidentally through an unblocked code path.
