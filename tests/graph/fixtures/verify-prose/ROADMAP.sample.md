# ROADMAP — verify lines that are not commands (negative control for VERIFY-NOT-COMMAND)

## Phase 1

- [ ] P1.1 Prose verify (verify: the script exits 0 and prints ok)
      node: spike/prose | kind: spike
      paths: a/
- [ ] P1.2 Bare scenario reference (verify: S39)
      node: spike/scenario-ref | kind: spike
      paths: b/
- [ ] P1.3 A real command (verify: bash -n a/x.sh)
      node: spike/real | kind: spike
      paths: c/

Phase validation: bash -n a/x.sh
