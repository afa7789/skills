# Git Rebase & Conflict Rules

## Rebase vs Merge

| Situation | Action |
|---|---|
| Feature branch, not yet pushed / not shared | Rebase onto the updated base freely. |
| Feature branch already pushed, no one else based work on it | Rebase is fine; force-push with `--force-with-lease` (never bare `--force`). |
| Branch other people/agents have already pulled or branched from | Merge instead — rebasing rewrites commits out from under them. |
| Worktree branches inside a multi-agent run (see `agents/orchestrator.md`) | Merge (`--no-ff`), not rebase — these are ephemeral but concurrent; rebase mid-run invalidates a sibling worker's base. |

Never amend, never rebase -i (both forbidden globally). A rebase here means `git rebase <base>` replaying whole commits — not editing, squashing, or reordering them.

## Conflict Resolution — Mix, Don't Overwrite

A conflict is not "pick ours or theirs." Default to reconciling both sides:

1. **Assess** — `rtk git status` / `rtk git diff` to see the conflict markers.
2. **Investigate intent** — read each side's commit message and the originating task's `long-description` (or PR description). Never guess *why* a hunk exists.
3. **Reconcile** — keep both changes when they don't actually collide (e.g. two additions to the same file in different functions). When they truly collide (same lines, incompatible logic), favor the rebase/merge target's objective, but preserve the other side's intent if it can be folded in without contradicting it.
4. **Validate** — run the project's full verification gate (test runner + typechecker/build + linter, per `engineering.md` §Measurable gates). A resolution that fails checks is not resolved.
5. **Escalate only when blocked** — genuinely ambiguous intent, or changes that are semantically incompatible (not just textually overlapping). Flag for human review with a one-paragraph summary of both intents and the specific incompatibility. Do not invent new behavior to bridge them.

This mirrors `agents/orchestrator.md` §Resolving merge conflicts — that section is the worktree-merge instance of this same rule; this file is the general policy for any rebase or merge, worktree or not.

## Dispatch to a Subagent

Conflict resolution is implementation work — investigate, edit, re-run checks — so it goes to a subagent with edit access (`agents/builder.md`), never resolved by an orchestrator/coordinator role that only reads. Give the subagent:
- both commits' messages and diffs (or PR descriptions) for the conflicting hunks
- the originating task's `long-description` / spec for each side
- explicit instruction to follow the 5 steps above and report which hunks were merged vs. which side won vs. what got escalated

Keep resolution scoped to the conflicting files only — a conflict fix is not license to refactor the surrounding code.
