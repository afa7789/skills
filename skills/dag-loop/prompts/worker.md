You are in a git worktree for {scope}. Do only the task(s) listed below.

{tasks}

## Done

Run every task's check from the worktree root before committing; each check must exit 0.
Commit your work with a short message (`git add` + `git commit`).
Do not run dagRobin. Do not start other tasks. Do not merge, rebase or push. Then exit.
@@failure@@
## Previous attempt failed: {reason}

Its changes were discarded; this worktree starts from the latest main branch. Last output lines:

```
{tail}
```

Fix the cause, run every check again, then commit.
