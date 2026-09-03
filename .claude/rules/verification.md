## 1. Never trust a PASS until the check can FAIL

A verification that only passes has not proved that it works.

**Apply:** Every custom check needs a known-good case and at least one negative control. `0 items examined → PASS` is a failed check.

## 2. Verify the measurement before trusting the result

A command can succeed while checking the wrong thing: wrong path, worktree, pipeline exit code, input, or environment.

**Apply:** For surprising results, verify the command, working directory, inputs, exit code, and tool before interpreting the result.

## 3. Reproduce failures against the baseline

Finding a failure does not prove the current change caused it.

**Apply:** Reproduce on both `BASELINE` and `HEAD`. Attribute a regression only when the comparison proves it.

## 4. Treat test results as environment-dependent

Test results depend on the source tree, installed tools, dependencies, and build state.

**Apply:** When comparing results, ensure baseline and current state use the same relevant environment and build state.

## 5. A skipped test is not coverage

A test that always skips provides no evidence.

**Apply:** Verify that every required dependency exists in the environment where the test is expected to run. CI must fail clearly when a required dependency is missing.

## 6. Run the full suite after changing contracts

Targeted tests do not reveal all consumers of a changed interface.

**Apply:** After changing a contract, run targeted tests, the full suite, and search for fakes, mocks, adapters, and other implementations.

## 7. Test the seams

Two individually correct components can fail when connected.

**Apply:** After integrating related changes, exercise at least one real caller/integration path, not only isolated unit tests.
