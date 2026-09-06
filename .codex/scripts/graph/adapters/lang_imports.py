"""graph.adapters.lang_imports — how each language spells an import and how it resolves to a path
in this repository. The one file that knows a language: `IMPORT_PATTERNS` maps a source extension
to a function `text -> [import string]`, `RESOLVERS` maps it to `(Tree, rel_file, imp) ->
(target rel path or None, looks_in_repo)`. Adding a language is one row in each table; the
extractor (`fs_extract`) never learns a new word.

Only imports that LOOK in-repo are ever resolved; stdlib and third-party names return
`(None, False)` and are ignored upstream. An in-repo-looking import that resolves nowhere returns
`(None, True)` so the extractor can fail closed on it.
"""

import json
import os
import posixpath
import re

SOURCE_EXTS = (".go", ".py", ".ts", ".tsx", ".js", ".rs", ".java", ".kt", ".cs")

_GO_BLOCK = re.compile(r"^import\s*\(([^)]*)\)", re.M | re.S)
_GO_QUOTED = re.compile(r'"([^"\n]+)"')
_GO_SINGLE = re.compile(r'^import\s+(?:[\w.]+\s+)?"([^"\n]+)"', re.M)
_PY_FROM = re.compile(r"^\s*from\s+(\.*[\w.]*)\s+import\s", re.M)
_PY_IMPORT = re.compile(r"^\s*import\s+([\w.]+(?:\s*,\s*[\w.]+)*)", re.M)
_JS_ANY = re.compile(r"""(?:\bfrom\s*|\bimport\s*|\brequire\s*\(\s*|\bimport\s*\(\s*)['"]([^'"\n]+)['"]""")
_RS_USE = re.compile(r"^\s*(?:pub\s+)?use\s+((?:crate|super|self)(?:::\w+)*)", re.M)
_JVM_IMPORT = re.compile(r"^\s*import\s+(?:static\s+)?([\w.]+)", re.M)
_CS_USING = re.compile(r"^\s*using\s+(?:static\s+)?([\w.]+)\s*;", re.M)


def _go_imports(text):
    out = []
    for block in _GO_BLOCK.findall(text):
        out.extend(_GO_QUOTED.findall(block))
    out.extend(_GO_SINGLE.findall(text))
    return out


def _py_imports(text):
    out = [m for m in _PY_FROM.findall(text) if m]
    for group in _PY_IMPORT.findall(text):
        out.extend(part.strip() for part in group.split(",") if part.strip())
    return out


def _jvm_imports(text):
    return [m.rstrip(".") for m in _JVM_IMPORT.findall(text)]


IMPORT_PATTERNS = {
    ".go": _go_imports,
    ".py": _py_imports,
    ".ts": lambda t: _JS_ANY.findall(t),
    ".tsx": lambda t: _JS_ANY.findall(t),
    ".js": lambda t: _JS_ANY.findall(t),
    ".rs": lambda t: _RS_USE.findall(t),
    ".java": _jvm_imports,
    ".kt": _jvm_imports,
    ".cs": lambda t: _CS_USING.findall(t),
}


# -------------------------------------------------------------------------- resolvers
class Tree(object):
    """The facts a resolver needs about the tree: what exists, and the language roots."""

    def __init__(self, root, files, dirs):
        self.root = root
        self.files = set(files)
        self.dirs = dirs
        self.go_module = self._go_module()
        self.ts_paths = self._tsconfig()

    def _go_module(self):
        path = os.path.join(self.root, "go.mod")
        if not os.path.isfile(path):
            return None
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("module "):
                    return line.split(None, 1)[1].strip()
        return None

    def _tsconfig(self):
        """[(prefix, [target dirs])] from compilerOptions.baseUrl/paths; [] when unusable."""
        path = os.path.join(self.root, "tsconfig.json")
        if not os.path.isfile(path):
            return []
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                raw = re.sub(r"//[^\n]*", "", fh.read())
            cfg = json.loads(re.sub(r",(\s*[}\]])", r"\1", raw))
        except (OSError, ValueError):
            return []
        opts = cfg.get("compilerOptions") or {}
        base = (opts.get("baseUrl") or ".").strip("./") or ""
        out = []
        for pattern, targets in (opts.get("paths") or {}).items():
            out.append((pattern.rstrip("*").rstrip("/"),
                        [posixpath.normpath(posixpath.join(base, t.rstrip("*").rstrip("/"))).strip("./")
                         for t in targets]))
        out.append(("", [base]))
        return out

    def dir_exists(self, path):
        return path in self.dirs

    def file_exists(self, path):
        return path in self.files

    def package_at(self, path):
        """The repo path an import lands on: a source file, or the directory that holds it."""
        path = path.strip("/")
        if not path:
            return None
        if self.file_exists(path):
            return path
        for ext in SOURCE_EXTS:
            if self.file_exists(path + ext):
                return path + ext
        if self.dir_exists(path):
            return path
        return None


def _resolve_go(tree, rel_file, imp):
    mod = tree.go_module
    if mod:
        if imp == mod:
            return None, False
        if not imp.startswith(mod + "/"):
            return None, False
        rel = imp[len(mod) + 1:]
        return (rel if tree.dir_exists(rel) else None), True
    return (imp if tree.dir_exists(imp) else None), tree.dir_exists(imp.split("/", 1)[0])


def _resolve_py(tree, rel_file, imp):
    here = posixpath.dirname(rel_file)
    dots = len(imp) - len(imp.lstrip("."))
    rest = imp.lstrip(".")
    if dots:
        base = here
        for _ in range(dots - 1):
            base = posixpath.dirname(base)
        candidate = posixpath.join(base, rest.replace(".", "/")) if rest else base
        return _resolve_py_path(tree, candidate), True
    parts = imp.split(".")
    looks = tree.dir_exists(parts[0]) or tree.file_exists(parts[0] + ".py")
    if not looks:
        return None, False
    return _resolve_py_path(tree, "/".join(parts)), True


def _resolve_py_path(tree, path):
    path = posixpath.normpath(path).strip("/")
    if tree.file_exists(path + ".py"):
        return path + ".py"
    if tree.file_exists(path + "/__init__.py"):
        return path
    return path if tree.dir_exists(path) else None


_JS_EXTS = (".ts", ".tsx", ".js")


def _resolve_js_path(tree, path):
    path = posixpath.normpath(path).strip("/")
    if tree.file_exists(path):
        return path
    for ext in _JS_EXTS:
        if tree.file_exists(path + ext):
            return path + ext
    for ext in _JS_EXTS:
        if tree.file_exists(path + "/index" + ext):
            return path + "/index" + ext
    return path if tree.dir_exists(path) else None


def _resolve_js(tree, rel_file, imp):
    if imp.startswith("."):
        joined = posixpath.join(posixpath.dirname(rel_file), imp)
        return _resolve_js_path(tree, joined), True
    for prefix, targets in tree.ts_paths:
        if prefix and not (imp == prefix or imp.startswith(prefix + "/")):
            continue
        tail = imp[len(prefix):].lstrip("/") if prefix else imp
        for target in targets:
            candidate = posixpath.join(target, tail).strip("/")
            hit = _resolve_js_path(tree, candidate)
            if hit:
                return hit, True
            head = candidate.split("/", 1)[0]
            if prefix or tree.dir_exists(head):
                return None, True
    return None, False


def _resolve_rs(tree, rel_file, imp):
    head, _, rest = imp.partition("::")
    rest = rest.replace("::", "/")
    if head == "crate":
        base = "src" if tree.dir_exists("src") else ""
    elif head == "super":
        base = posixpath.dirname(posixpath.dirname(rel_file))
    else:
        base = posixpath.dirname(rel_file)
    candidate = posixpath.join(base, rest).strip("/") if rest else base
    if not candidate:
        return None, True
    candidate = posixpath.normpath(candidate)
    if tree.file_exists(candidate + ".rs"):
        return candidate + ".rs", True
    if tree.file_exists(candidate + "/mod.rs"):
        return candidate, True
    return (candidate if tree.dir_exists(candidate) else None), True


_JVM_ROOTS = ("src/main/java", "src/main/kotlin", "src/java", "src/kotlin", "src", "")


def _resolve_jvm(tree, rel_file, imp):
    """Best effort: an unmatched package is treated as third party, never as unresolved."""
    tail = imp.replace(".", "/")
    for source_root in _JVM_ROOTS:
        hit = tree.package_at(posixpath.join(source_root, tail).strip("/"))
        if hit:
            return hit, True
        parent = posixpath.dirname(posixpath.join(source_root, tail).strip("/"))
        if parent and tree.dir_exists(parent):
            return parent, True
    return None, False


RESOLVERS = {
    ".go": _resolve_go,
    ".py": _resolve_py,
    ".ts": _resolve_js,
    ".tsx": _resolve_js,
    ".js": _resolve_js,
    ".rs": _resolve_rs,
    ".java": _resolve_jvm,
    ".kt": _resolve_jvm,
    ".cs": _resolve_jvm,
}


