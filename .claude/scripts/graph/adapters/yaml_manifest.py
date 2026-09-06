"""graph.adapters.yaml_manifest — the architecture manifest parser. THIS DOCSTRING IS THE FORMAT SPEC.

Accepted YAML subset (anything else raises ValueError naming the line — fail closed, because a
parser that silently accepts out-of-subset input would let the manifest lie):

  * nested mappings            `key: value` / `key:` followed by an indented block
  * block sequences            `- scalar` or `- key: value` (+ further keys indented two more)
  * inline flow sequences      `[a, b, c]`  (scalars only)
  * scalars                    unquoted strings, "double"/'single' quoted, ints, floats, true/false
  * comments                   whole-line `# …` and trailing ` # …`
  * indentation                spaces only

Rejected on purpose: tabs, flow mappings `{a: 1}`, anchors/aliases, tags, multi-line/folded scalars,
documents (`---`), and any line that is neither a mapping entry nor a sequence item.

Manifest keys (version 1):
  version, project, profile (hexagonal|debug|library), layout{…}, domains[], usecases[],
  ports[] {name, direction in|out, domain|usecase, path}, adapters[] {name, port (scalar|list),
  path, datastore}, contracts[] {name, version, type, path}, mutation {<lang>: cmd, threshold},
  architecture {budget}, brief {max_bytes}, rules {forbid: [{from, to}]}.
"""

import re

from graph.core.graph import MANIFEST_VERSIONS


class ManifestError(ValueError):
    pass


def _lines(text):
    out = []
    for lineno, raw in enumerate(text.splitlines(), 1):
        if "\t" in raw:
            raise ManifestError("line %d: tabs are outside the YAML subset" % lineno)
        if raw.lstrip().startswith("#"):
            continue
        s = raw.split(" #", 1)[0].rstrip() if " #" in raw else raw.rstrip()
        if s.strip() == "---":
            raise ManifestError("line %d: document markers are outside the YAML subset" % lineno)
        if s.strip():
            out.append((lineno, len(s) - len(s.lstrip(" ")), s.strip()))
    return out


def scalar(tok, lineno=0):
    tok = tok.strip()
    if tok.startswith("{"):
        raise ManifestError("line %d: flow mappings are outside the YAML subset" % lineno)
    if tok.startswith("&") or tok.startswith("*") or tok.startswith("!"):
        raise ManifestError("line %d: anchors, aliases and tags are outside the YAML subset" % lineno)
    if tok in ("|", ">"):
        raise ManifestError("line %d: multi-line scalars are outside the YAML subset" % lineno)
    if tok.startswith("[") and tok.endswith("]"):
        inner = tok[1:-1].strip()
        return [scalar(p, lineno) for p in inner.split(",")] if inner else []
    if len(tok) >= 2 and tok[0] == tok[-1] and tok[0] in "\"'":
        return tok[1:-1]
    if re.fullmatch(r"-?\d+", tok):
        return int(tok)
    if re.fullmatch(r"-?\d+\.\d+", tok):
        return float(tok)
    if tok in ("true", "false"):
        return tok == "true"
    return tok


def _value_after_key(lines, pos, key_indent):
    if pos >= len(lines):
        return None, pos
    _, indent, body = lines[pos]
    if indent > key_indent or (indent == key_indent and body.startswith("- ")):
        return _parse_block(lines, pos, indent)
    return None, pos


def _map_entries(lines, pos, indent, into):
    while pos < len(lines) and lines[pos][1] == indent and not lines[pos][2].startswith("- "):
        lineno, _, body = lines[pos]
        if ":" not in body:
            raise ManifestError("line %d: not a mapping entry: %r" % (lineno, body))
        k, _, v = body.partition(":")
        k, v = k.strip(), v.strip()
        pos += 1
        if v == "":
            into[k], pos = _value_after_key(lines, pos, indent)
        else:
            into[k] = scalar(v, lineno)
    return pos


def _parse_block(lines, pos, indent):
    if lines[pos][2].startswith("- "):
        seq = []
        while pos < len(lines) and lines[pos][1] == indent and lines[pos][2].startswith("- "):
            lineno, _, body = lines[pos]
            item = body[2:].strip()
            pos += 1
            if ":" in item and not item.startswith("[") and not item.startswith("\"") and not item.startswith("'"):
                d = {}
                k, _, v = item.partition(":")
                k, v = k.strip(), v.strip()
                if v == "":
                    d[k], pos = _value_after_key(lines, pos, indent + 2)
                else:
                    d[k] = scalar(v, lineno)
                pos = _map_entries(lines, pos, indent + 2, d)
                seq.append(d)
            else:
                seq.append(scalar(item, lineno))
        return seq, pos
    d = {}
    pos = _map_entries(lines, pos, indent, d)
    return d, pos


def parse(text):
    lines = _lines(text)
    if not lines:
        return {}
    value, pos = _parse_block(lines, 0, lines[0][1])
    if pos != len(lines):
        raise ManifestError("line %d: unparsed trailing content %r" % (lines[pos][0], lines[pos][2]))
    if not isinstance(value, dict):
        raise ManifestError("line 1: the manifest root must be a mapping")
    version = value.get("version", 1)
    if version not in MANIFEST_VERSIONS:
        raise ManifestError("manifest version %r is not supported (known: %s)" % (version, sorted(MANIFEST_VERSIONS)))
    return value
