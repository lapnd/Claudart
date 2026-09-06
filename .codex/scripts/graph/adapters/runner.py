"""graph.adapters.runner — the orchestrator runs a node's verify ITSELF (D30).

A worker's claimed exit code never reaches the log. The runner writes the command as the first
line of the evidence file and `[runner] exit N` as the last, so an empty or header-only file is
itself evidence that the job never ran (Lessons IV.13).
"""

import os
import subprocess


def run_verify(cmd, cwd, evidence_path, timeout_s=600):
    os.makedirs(os.path.dirname(evidence_path) or ".", exist_ok=True)
    with open(evidence_path, "w", encoding="utf-8") as fh:
        fh.write("$ %s\n(cwd %s)\n" % (cmd, cwd))
        fh.flush()
        try:
            proc = subprocess.run(cmd, shell=True, cwd=cwd, stdout=fh, stderr=subprocess.STDOUT, timeout=timeout_s)
            code = proc.returncode
        except subprocess.TimeoutExpired:
            code = 124
            fh.write("\n[runner] TIMEOUT after %ds\n" % timeout_s)
        fh.write("\n[runner] exit %d\n" % code)
    return code


def evidence_ok(rel_path, base):
    p = os.path.join(base, rel_path)
    return os.path.isfile(p) and os.path.getsize(p) > 0
