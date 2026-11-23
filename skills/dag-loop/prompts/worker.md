You are in a git worktree for task {id}: {title}. Do only this task.

## Spec

{spec}

## Files

{files}

## Done

Done = this command exits 0 when run from the worktree root:

```sh
{check}
```

Run it before committing. Commit your work with a short message (`git add` + `git commit`).
Do not run dagRobin. Do not start other tasks. Do not merge, rebase or push. Then exit.
@@failure@@
## Previous attempt failed: {reason}

Its changes were discarded; this worktree starts from the latest main branch. Last output lines:

```
{tail}
```

Fix the cause, run the check again, then commit.
