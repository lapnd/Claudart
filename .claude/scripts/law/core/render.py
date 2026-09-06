"""law.core.render — the compiled `CLAUDE.md` law block (SCHEMA.md sections 2-3, SPEC D10).

Pure (D15): a mapping of law id -> parsed frontmatter and `today` go in, one string comes out.
Reading or rewriting `CLAUDE.md` — and the `<!-- laws:begin -->` / `<!-- laws:end -->` markers
themselves — belong to the target-writer adapter, never here.

The fixed lines below (preamble, intro sentence, both line templates) are owned by this function;
`artifacts/compiled-block.example.md` is the frozen reference they reproduce.
"""

from law.core import retirement

PREAMBLE = "See @.claude/CONTEXT.md for the current state of work (updated by /checkpoint)."

INTRO = (
    "The workflow rules below are deliberately **not auto-imported** (token hygiene). "
    "Read the rule file when its trigger fires, **before acting under it**. Until read, "
    "the digest after each trigger is binding:"
)

ALWAYS_LINE = "See @.claude/rules/%s.md %s"
TRIGGER_LINE = "- `.claude/rules/%s.md` — %s%s Digest: %s"


def block(laws, today):
    """The text BETWEEN the block markers: preamble, `always` lines, intro, `trigger` bullets.

    `load: auto` and `load: never` records contribute no line anywhere. Both rendered sections
    are ordered by `order` ascending (SCHEMA.md section 2).
    """
    lines = [PREAMBLE]
    lines += [_always(law_id, laws[law_id]) for law_id in _ordered(laws, "always")]
    lines += ["", INTRO, ""]
    lines += [_bullet(law_id, laws[law_id], today) for law_id in _ordered(laws, "trigger")]
    return "\n".join(lines)


def _ordered(laws, load):
    """The ids of every record with this `load` value, by `order` then id for a stable tie."""
    ids = [law_id for law_id in laws if laws[law_id].get("load") == load]
    return sorted(ids, key=lambda law_id: (laws[law_id]["order"], law_id))


def _always(law_id, record):
    return ALWAYS_LINE % (law_id, record["trigger"])


def _bullet(law_id, record, today):
    """The bullet form, with the expiry marking inserted immediately after its em dash.

    Only this form is markable: SCHEMA.md defines the marking as inserted after the em dash of
    the law's `CLAUDE.md` line, and an `always` line has no em dash to insert after.
    """
    should_mark, text = retirement.marking(record, today)
    mark = ""
    if should_mark:
        mark = text
    return TRIGGER_LINE % (law_id, mark, record["trigger"], record["digest"])
