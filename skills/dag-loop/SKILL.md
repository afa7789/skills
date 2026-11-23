---
name: dag-loop
description: "Run or resume the dagRobin task DAG with an external bash driver: one git worktree and one headless agent run (claude, codex, opencode, pi, omp, hermes) per task, gated by the task's check. Triggers on \"run the tasks\", \"start the loop\", \"resume the DAG\", \"/dag-loop\"."
---

# dag-loop

The loop lives in `scripts/dag-loop.sh`, not in you. Start it, wait for it to exit, report. While it runs, do not
claim, update or verify dagRobin tasks yourself, and do not commit in the repo.

## Prerequisites

1. A git repo with at least one commit and no uncommitted changes to tracked files. Untracked files are ignored.
2. `dagRobin` ≥ 0.2.0 and `jq` on PATH. Tasks are imported into a project DB (`dagRobin init` + `dagRobin import
   tasks.yaml`, or an exported `DAGROBIN_DB`). The driver refuses the global DB.
3. Every task has `metadata.check` (exit 0 = done) and one `phase:feature|harden|infra` tag. A task missing either is
   blocked as `bad-contract` without running.
4. The host CLI is installed and logged in. Every adapter bypasses the host's permission prompts, so the user must
   agree to that before you start.
5. Checks run in a fresh worktree, so they cannot rely on untracked files (`node_modules`, `.env`).

## Start

```bash
bash <skill-dir>/scripts/dag-loop.sh --host claude [--slots 1] [--retries 2] [--timeout 1800] [--max-cost 2]
```

- A run can take hours. Start it in the background if your host can (otherwise ask the user to run it in a terminal)
  and wait for it to exit. Do not poll.
- `--slots N` runs up to N tasks at once whose `files` do not overlap.
- `--timeout` is seconds per host run. `--max-cost` is USD per run and is passed only to claude and omp.
- `ANTHROPIC_API_KEY` is removed from the host's environment unless `DAGLOOP_KEEP_API_KEY=1`.

Per task: claim → worktree `.worktrees/<id>` on branch `dagloop/<id>` → host runs `prompts/worker.md` and must make
at least one commit → check in the worktree → under a lock, squash-merge as `feat(F-001): <title>` (harden:
`test(F-001): …`, infra: `chore(infra): …`) → `dagRobin verify <id>` on main, which resets the driver's commit on
failure. A failure is retried from the new HEAD with the failure output in the prompt; when retries run out, the task
is marked Blocked.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | All tasks Done. |
| 3 | Nothing ready: the remaining tasks are Blocked or wait on deps. |
| 1 | Error: a precondition failed, dagRobin failed, or ready tasks are left after a host crash or timeout. |
| 130 | Interrupted. The tasks in flight went back to Pending. |

## Reading `.git/dag-loop.log`

The log gets one line per event, the same lines as stdout, and is appended across runs: `start …`,
`<id> attempt n/N by dagloop-<host>-<slot>`, `<id> attempt n failed: <reason>`, `<id> merged as <sha>`,
`<id> done | blocked: <reason> | returned to pending`, and a final `all tasks done` or `stopped: …`.

Reasons: `no-commit` (host exited 0 without committing), `crash` (exited non-zero without committing), `timeout`,
`check-failed` (in the worktree), `merge-conflict`, `verify-failed` (passed in the worktree, failed on main after the
merge), `main-tree-dirty` (someone edited tracked files in the main tree during the run).

The last run's files are in `.git/dag-loop.d/`: `<id>.prompt`, `.host.out`, `.check.out` and `.merge.out` (merge and
verify output).

## Blocked tasks

1. List them with `dagRobin list --format json | jq -r '.[] | select(.status=="Blocked") | "\(.id) \(.metadata.notes)"'`.
2. Read `.git/dag-loop.d/<id>.*.out` to see why each one failed.
3. Fix the cause: a wrong spec or check (`dagRobin update <id> --metadata "check:<cmd>"` or re-import), missing code,
   or a task too big for one run (split it).
4. Run `dagRobin update <id> --status pending`, then start the driver again.

`crash`, `timeout` and `main-tree-dirty` mean a host or environment fault, not a verdict on the task. If the last
attempt failed that way, the task stays Pending and the driver exits 1. Fix the host (login, credits, `--timeout`) or
commit the main tree, then rerun. After a `kill -9`, tasks stay InProgress: run `dagRobin update <id> --status pending`
on each and `rmdir .git/dag-loop.lock` if it exists.

## Report

After the driver exits, report the exit code, the done and blocked counts (`dagRobin status`), and each blocked id with
its reason. Do not fix blocked tasks unless the user asks.
