"""graph.adapters.fs_paths — resolve node path QUERIES against a real tree (D25) and classify
manifest changes (D33)."""

import glob
import os


def resolve_paths(root, g):
    """node -> set of files (relative to root) matched by the node's path queries."""
    out = {}
    for nid, n in g.nodes.items():
        files = set()
        for pat in n.paths:
            for hit in glob.glob(os.path.join(root, pat), recursive=True):
                if os.path.isfile(hit):
                    files.add(os.path.relpath(hit, root))
        out[nid] = files
    return out


def manifest_change_class(old, new):
    """D33: adding/removing a port, contract or domain is a scope change; adding an adapter is not."""
    def names(m, key):
        return set(x.get("name") for x in m.get(key, []) if isinstance(x, dict))
    needs, exec_level = [], []
    for key in ("ports", "contracts", "domains"):
        added, removed = names(new, key) - names(old, key), names(old, key) - names(new, key)
        if added or removed:
            needs.append("%s%s%s" % (key, " +" + ",".join(sorted(added)) if added else "",
                                     " -" + ",".join(sorted(removed)) if removed else ""))
    added = names(new, "adapters") - names(old, "adapters")
    if added:
        exec_level.append("adapters +" + ",".join(sorted(added)))
    return needs, exec_level
