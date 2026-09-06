"""law.core.agreement — the D9 two-pass classification agreement rate (LESSONS.md section 5).

Pure (D15): a list of already-parsed lesson dicts goes in, plain numbers and one formatted line
come out. Reading `.claude/lessons/<year>.jsonl` belongs to an adapter, not here.
"""

FIRST_PASS = 1
SECOND_PASS = 2

RATE_LINE = "agreement: %.2f (%d/%d)"


def rate(lessons):
    """(agree, pairs) over the sources carrying both extraction passes.

    A source with fewer than two records, or missing one of the two pass values, forms no pair
    (LESSONS.md section 5). Zero pairs is (0, 0) rather than a division error.
    """
    by_source = _passes_by_source(lessons)
    agree = 0
    pairs = 0
    for source in sorted(by_source):
        passes = by_source[source]
        if FIRST_PASS not in passes or SECOND_PASS not in passes:
            continue
        pairs += 1
        if passes[FIRST_PASS] == passes[SECOND_PASS]:
            agree += 1
    return (agree, pairs)


def format_rate(agree, pairs):
    """The exact stdout line of LESSONS.md section 5, two decimal places; 0.00 when pairs is 0."""
    ratio = agree / pairs if pairs else 0.0
    return RATE_LINE % (ratio, agree, pairs)


def _passes_by_source(lessons):
    """source -> {extraction_pass: candidate_law}; a later record for the same pass wins."""
    by_source = {}
    for lesson in lessons:
        passes = by_source.setdefault(lesson["source"], {})
        passes[lesson["extraction_pass"]] = lesson["candidate_law"]
    return by_source
