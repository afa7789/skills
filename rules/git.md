# Git
- 1 feature = 1 commit: `feat(F-012): <behavior>` when a feature id exists.
- WIP commits are fine locally; squash before push: `git reset --soft $(git merge-base HEAD <base>) && git commit`.
- Never `--amend`. Never rewrite anything pushed or reviewed; fixes are new commits.
- Before any push the project gate exits 0 (lint + build + checks).
- Never push without an explicit request.
- Use the user's commit message verbatim. Never add Co-Authored-By or "Generated with" lines.
- Shared branch → merge; local branch → rebase freely. Conflicts: reconcile both sides, rerun the gate.
