# Plan: graph (+ gaps) → `features/tasks.yaml`

Input: `features/graph.yaml`, plus `features/gaps.yaml` for existing repos. The output is the dagRobin import file itself. No converter. Create the MINIMUM coherent set of tasks that brings the repo in line with the graph.

## Task contract

```yaml
- id: f001-login                       # kebab-case, never reused across rounds
  title: Login with email and password
  priority: 1                          # 1 = first
  deps: []                             # real implementation constraints only
  files: [src/auth/login.rs]           # write set
  tags: [feature:F-001, phase:feature] # phase: feature | harden | infra; infra tasks use feature:infra
  metadata:
    long-description: |                # complete spec; the worker has no other context
    check: cargo run -q -- login a@b.c pw | grep -q OK   # ONE binary command, exit 0 = done
```

`long-description` holds the behavior, inputs and outputs, the acceptance criteria covered, evidence and finding ids. The worker never rediscovers requirements. `check` runs via `sh -c` in the directory where `dagRobin verify` is called, so write its paths relative to the repo root. A multi-line `check: |` is fine.

## Checks per phase

- `phase:feature`: smoke check. Build, then the feature's main action responds: the CLI command prints its result, the HTTP route answers (start the server inside the check), or the page renders.
- `phase:harden`: write the failing test first. The check runs ONLY that test and greps its pass line, because a test filter that matches nothing exits 0 (`cargo test name`, `go test -run Name`): `cargo test --test login_rules -- --ignored --exact lockout | grep -q '1 passed'`.
- `phase:infra`: the setup works, e.g. `cargo clippy -q -- -D warnings`.

## Acceptance criteria

Every criterion of every feature maps to exactly one of two places: the feature task's smoke check, or a harden task in a later round. Record the split in the feature task's `long-description` as `smoke:` and `harden later:` lists. The harden round turns each `harden later` item into its own task.

## Findings → phase

- Fundamental contradictions, `BLOCKER`, `INCORRECT`, `INCOMPLETE` → `phase:feature`.
- `TEST_GAP` → `phase:harden`.
- `DOC_GAP`, `LEGACY`, `IMPROVEMENT` → `phase:harden`, ordered last. The check is a direct probe, e.g. `! grep -rq old_login src/`. These findings never go in a feature round.

Priority order: 1 resolve contradictions in fundamental behavior, 2 fix blockers, 3 unblock dependent features, 4 correct incorrect implementations, 5 complete missing functionality, 6 restore or add required tests, 7 sync docs, 8 remove clearly obsolete behavior, 9 justified improvements.

## Shape

- Tasks that can run independently stay independent (no deps), so they run in parallel. Deps follow real implementation constraints, not priority.
- Parallel tasks get disjoint `files`. If two overlap, add a dep or merge them into one task.
- No speculative refactors, new abstractions, unrelated cleanup, or redesign the graph does not require. Do not split trivial work, and do not bundle unrelated changes.
- Each task leaves its area valid and verifiable.
- Never change canonical behavior to match the code. If a task shows the graph may be wrong, the worker stops and reports a proposed spec change.
