---
name: fdd
description: Feature-driven development, features first. Turn a brief or an existing repo into a canonical feature graph and a binary-checked dagRobin task DAG under features/. Use for "plan this project", "feature graph", "audit the repo against the spec", "gap analysis", "build the task DAG".
---

# FDD: feature graph → binary-checked DAG

This is Rapid Application Development: every feature works first. Business rules, edge cases and complex tests come after, as targeted tests kept out of the default CI run.

Every task carries ONE binary `metadata.check`. `dagRobin verify <id>` runs it and is the only way to close the task.

## Flow

| Repo | Steps |
|---|---|
| New | brief → graph → plan |
| Existing | discover → graph → gaps → plan |

The brief is the user's prompt or the output of the `prompt-refiner` skill. For each step, read its reference, write its artifact in the target project, and commit it before the next step.

| Step | Read | Writes |
|---|---|---|
| discover | `reference/discover.md` | `features/evidence.yaml` (existing repos only) |
| graph | `reference/graph.md` | `features/graph.yaml` (canonical) |
| gaps | `reference/gaps.md` | `features/gaps.yaml` (existing repos only) |
| plan | `reference/plan.md` | `features/tasks.yaml`: dagRobin import format, no converter |

## Load and hand off

```bash
dagRobin import features/tasks.yaml && bash <skill-dir>/scripts/check-dag.sh
```

- Exit 1 lists `task-id: reason` per offender. Before any work starts, fix `features/tasks.yaml` and reload with `dagRobin clear --yes --status Pending && dagRobin import features/tasks.yaml`, then re-check. The clear drops renamed or removed ids and keeps archived rounds.
- Exit 0 means the round is ready: hand off to the `dag-loop` skill.
- The script needs `jq`. `--max N` changes the 25-task cap and `--db PATH` selects the database.
- Re-importing an id resets it to Pending.
- Never use `import --replace`: it wipes the archived rounds that later deps rely on.

## Phases

Every task has exactly one `phase:` tag and one `feature:` tag.

- `phase:feature` (RAD): prefer ONE task per feature. The check is a smoke test: build, then the feature's main action responds (CLI command, HTTP route, page render). No unit tests are required. At most 25 non-Done tasks per round.
- `phase:harden`: only after every `phase:feature` task is Done. Each acceptance criterion, business rule or edge case becomes a failing-test-first task, and its check runs ONLY that test. Keep the test out of the default CI run the way the stack does it: `#[ignore]`, a `slow` marker, or a `test-hard` target. `DOC_GAP`, `LEGACY` and `IMPROVEMENT` findings also land here, with a direct probe as the check (`reference/plan.md`).
- `phase:infra`: setup work such as the workspace or lint config. Tag it `feature:infra`.

## Rounds

1. A round is the set of non-archived tasks. Each `features/tasks.yaml` holds one round, and git keeps the earlier ones.
2. If the graph needs more than 25 feature tasks, split it into several feature rounds by dependency layer.
3. When a round is done, run `dagRobin archive`, write the next round, import it and run `check-dag.sh`.
4. Task ids are never reused across rounds.

## Hard rules

- The graph is canonical. Never change it to match the code. If the graph is wrong, report a proposed spec change and stop the task.
- One task has one check, and exit 0 means done. A task without a check is not a task.
- Every acceptance criterion maps to a feature's smoke check or a later harden task (`reference/plan.md`).
- `check-dag.sh` must exit 0 before any work starts.
