---
name: tdd
description: Test-driven development on demand — red, green, refactor with binary evidence. Use for hardening tasks (phase:harden), bug fixes that need a reproducing test, business rules and edge cases, or when asked for TDD, "write the test first", "reproduce this bug with a test".
---

# TDD, on demand

Not the default. Feature work (RAD) proves itself with a smoke check. Reach for this skill when:
- a `phase:harden` task from `fdd` (business rule, edge case, acceptance criterion);
- a bug fix: reproduce first, then fix;
- branchy logic where a smoke check cannot see the failure;
- the user asks for TDD.

## Loop — one behavior at a time

1. **Name the behavior** in one sentence: given X, when Y, then Z. One test per behavior.
2. **Red.** Write the test and run ONLY it. It must fail for the right reason: the behavior's assertion,
   not an import error, typo or missing fixture. Keep the failing line.
3. **Green.** The least code that makes it pass. Rerun it; keep the pass line.
4. **Refactor** with the test green: remove the duplication you just made, fix names. Rerun.
5. **Wire the proof.** The task's `metadata.check` runs only this test and greps its pass line,
   because a filter that matches nothing exits 0:
   - `cargo test --test rules -- --exact lockout | grep -q '1 passed'`
   - `pytest tests/test_rules.py::test_lockout -q | grep -q '1 passed'`
   - `npx vitest run src/rules.test.ts -t lockout | grep -q 'Tests  1 passed'`
   - `go test ./rules -run '^TestLockout$' -v | grep -q -- '--- PASS: TestLockout'`
6. **Keep heavy tests out of the default CI run**: `#[ignore]`, `@pytest.mark.slow`, a separate
   vitest/jest project or a `test-hard` target. CI stays lint → build → smoke.

## Bug fix

1. Write the test that reproduces the report and watch it fail with the reported symptom.
2. Fix the root cause, not the symptom. The test passes. Run the neighbouring suite once.
3. Commit test and fix together: `fix(F-012): <behavior>` (or `test(F-012): ...` for a harden task).

## Good tests

- Assert observable behavior at a boundary (public function, HTTP, CLI, UI), never internals.
- Real collaborators where cheap (in-memory DB, temp dir). Mock only slow or external I/O, and never
  let a mock supply the answer under test.
- No test-only exports, no duplicate tests, no sleeps — wait on a condition.
- Deterministic: fixed clock, seed and data.
- Edge cases worth a test: empty, one, many, boundary ±1, invalid input at the trust boundary,
  concurrent writes to shared state.
- UI behavior (clicks, navigation, dialogs) → the `visual-test` skill records it and exits 0/1.

## Evidence

Report per behavior: test name, the red line, the green line, the check command.
No red line → it was not TDD; say so.
