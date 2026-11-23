---
name: review
description: "Review a PR, branch or diff: binary spec check (dagRobin task or features/graph.yaml, run its check), then bugs, trust boundaries, security and the ponytail lens. Read-only. Triggers on \"review PR\", \"review #12\", \"review this branch\", \"review the diff\", \"/review\"."
---

# Review

Two stages: spec (binary), then quality. Read-only. Post to the PR only when the user asks.

## Input

| Given | Do |
|---|---|
| PR number | `gh pr view <N> --json title,body,baseRefName,headRefOid,commits`; `gh pr diff <N>` |
| Nothing | Current branch: `BASE=$(git merge-base HEAD origin/<default>)`; `git diff $BASE...HEAD`; `git log --format=%B $BASE..HEAD` |
| Base, ref range or diff file | Use it as given. |

Read every changed file in full, not only the hunk.

## Stage 1 — Spec (binary)

1. Collect ids from commit messages and the PR body: `F-012` in `feat(F-012): ...`, `test(F-012): ...`. Task ids too.
2. Read each spec: `dagRobin get <id>`. Not in dagRobin → that feature's `acceptance_criteria` in `features/graph.yaml`.
3. Get the check: `dagRobin list --format json | jq -r '.[] | select(.id=="<id>") | .metadata.check'`. None → the project gate (test + typecheck + lint with complexity rule).
4. Run it from the repo root **on the PR head**. HEAD is not the PR head → `git fetch origin pull/<N>/head && git worktree add <tmp> FETCH_HEAD`, run there, then `git worktree remove <tmp>`. Never `gh pr checkout` over the user's tree.
5. Never `dagRobin verify`: it marks the task done.
6. Report per id: `PASS <id> — <command>` or `FAIL <id> — <command>` plus the last 20 output lines. Setup broke (missing deps, env, tool) → `NOT RUN <id> — <command>: <reason>`, never a FAIL, never APPROVE.
7. Acceptance criterion with no code or test behind it → `spec:` finding. Change outside every id's scope → `scope:` finding.

FAIL is a blocking finding. Continue to Stage 2, so one fix round covers both.
No ids found → say `no ids: reviewed against PR description` and judge the diff against the PR body.

## Stage 2 — Quality

Commit says "refactor" or "small" but touches money, auth, migrations or state machines → full scrutiny anyway.

1. Correctness (`bug:`): wrong result for valid input, unhandled error on an external call, off-by-one, check-then-act race on shared state.
2. Trust boundaries (`boundary:`): every external input (HTTP, CLI args, files, env, IPC, LLM output) validated before use. Every new endpoint or command has an auth guard.
3. Security (`security:`): injection (SQL, shell, path, template), secrets or PII in code or logs, raw errors returned to clients, non-CSPRNG randomness where an attacker benefits.
4. Ponytail + wiring: read `reference/ponytail.md`. Apply every tag to every changed file.

## Output

One line per finding:

```
<file>:<line> <tag>: <what>. <replacement>.
```

Order by severity: FAIL/`spec:`, `security:`, `bug:`, `boundary:`, `wiring:`/`orphan:`, other ponytail tags, then `(nit)` lines.
Then:

```
spec: PASS | FAIL | NOT RUN | no ids
verdict: APPROVE | CHANGES
net: -<N> lines possible
```

Any blocking finding → `CHANGES`. Nothing to cut → `net: Lean already.`

High-risk change (money, auth, crypto, migrations, concurrency) or cross-cutting change (many modules, public API) → suggest the `peer-review` skill for an independent panel.

## Post (only when asked)

```bash
gh pr comment <N> --body-file - <<'EOF'
<findings + verdict block>
EOF
gh pr review <N> --request-changes --body "CHANGES: see comment"   # or --approve --body "APPROVE: see comment"
```

Own PR → GitHub rejects `--approve` and `--request-changes`: post the comment only.
