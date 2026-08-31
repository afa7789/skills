---
name: pr-review-pipeline
description: Automated PR review pipeline. Fetches PR context via gh, runs differ-helper for diff analysis, dispatches code-reviewer for two-stage review (spec compliance then quality), and produces a structured PR_REVIEW.md report. Trigger with "review PR", "/pr-review", or "PR review".
---

# PR Review Pipeline

End-to-end pull request review that combines diff analysis, spec compliance checks, and scored code quality grading into a single actionable report.

> **Trigger phrases:** "review PR", "PR review", "/pr-review", "review this PR", "review PR #N"

---

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| PR number or branch | User provides `#N` or current branch is used | yes (auto-detected) |
| Base branch | From PR metadata or default branch | auto |
| Spec / task description | `.claude/PLAN.md`, task description, or PR body | optional |

---

## Phase 0 — Resolve Branch Context

**Branch-first.** The code is all in the branch — git is the source of truth. PR metadata is only fetched when a PR number is given or posting is requested.

```bash
# Base branch (default branch unless user names another):
BASE=$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')

# Scope of review:
rtk git diff "origin/$BASE"...HEAD --stat

# Commits in the branch (understand INTENT, not just the diff):
rtk git log --oneline "origin/$BASE"..HEAD

# Recent history on changed files (spot drift from existing patterns,
# detect unfamiliar territory for the author):
rtk git diff "origin/$BASE"...HEAD --name-only | xargs -I{} git log --oneline -5 -- {} 2>/dev/null
```

Only if a PR number is provided (or `--post` requested):

```bash
rtk gh pr view <N> --json number,title,body,baseRefName,headRefName,additions,deletions
```

Capture:
- **Base branch** (diff baseline)
- **Changed files list** (scope of review)
- **Commit messages** (intent — feeds the Intent Cross-Check below)
- **PR title & body / spec** (the spec for Stage 1, when available)

### Intent Cross-Check

Cross-reference commit messages with the diff. A "small refactor" that touches critical logic (money, auth, state machines, migrations) gets the same scrutiny as a new feature — always. If a critical change has no WHY (no spec, no body, no commit rationale), flag it as a question instead of guessing.

---

## Phase 1 — Diff Analysis (differ-helper)

Run differ-helper against the branch's base:

```bash
differ_helper origin/<base_branch>
```

If differ-helper is not installed, fall back to manual analysis:

```bash
rtk git diff origin/<base_branch>...HEAD
```

Extract from the output:
- **VARIABLES** — new/changed variable names
- **FUNCTIONS** — new/changed function signatures
- **TESTS** — new/changed test names
- **IMPORTS** — new/changed dependencies
- **WARNINGS** — duplicates, deprecated imports

---

## Phase 2 — Stage 1: Spec Compliance

Before judging code quality, verify the diff delivers what was promised.

### Sources of truth (check in order)
1. PR body / description
2. Linked issue (if referenced)
3. `.claude/PLAN.md` or `.claude/PRODUCT_SPEC.md`
4. Task description from dagRobin (`dagRobin show <task-id>`)

### Checklist
- [ ] Every acceptance criterion in the spec has corresponding code changes
- [ ] No unrelated changes smuggled into the PR (scope creep)
- [ ] Edge cases mentioned in the spec are handled
- [ ] Tests cover the stated acceptance criteria

**If Stage 1 FAILS:** Report spec gaps and STOP. Do not proceed to Stage 2 — the code quality of an incomplete feature is irrelevant.

---

## Phase 3 — Stage 2: Code Quality

Score each criterion 1-10. Below threshold = **blocking issue**.

| Criterion | Weight | Threshold | FAIL signal |
|-----------|--------|-----------|-------------|
| Correctness | HIGH | 7 | Wrong results for valid input |
| Security | HIGH | 7 | Exploitable vulnerability |
| Completeness | MEDIUM | 6 | Critical path has no error handling |
| Maintainability | LOW | 5 | Code requires original author to explain |
| Performance | LOW | 5 | O(n^2)+ on hot path |
| Component Reusability | MEDIUM | 6 | 3+ copy-pasted UI patterns (N/A for backend) |

### Ponytail Lens + Wiring Lens

Read [`reference/ponytail-lens.md`](reference/ponytail-lens.md) in full and apply every tag to every changed file. Do not summarize or use a shortened checklist — the full tag set (including `wrapper:`, `types:`, `one-caller:`, `yagni:`, `wiring:`, `orphan:`) is what catches unnecessary wrappers, gratuitous casts/type assertions, wrong type extensions, and unreachable code. Report findings using the `<file>:L<line>: <tag> <what>. <replacement>.` format from that file.

### Domain Checklist

Read [`reference/review-checklist.md`](reference/review-checklist.md) and work through every section: security (race conditions, injection, authz, sensitive-data safety), architecture (Single Source of Truth is blocking), migrations, tests, performance (N+1, scheduled jobs). Skip a section only if the diff clearly has zero relevance to it — and say so explicitly in the report.

### What to check per file

For each changed file in the diff:
1. Read the file in full (not just the diff hunk — context matters)
2. Check imports for unused or deprecated packages
3. Verify error handling on all external calls
4. Look for hardcoded secrets, credentials, or PII
5. Check for race conditions in concurrent code
6. Verify test coverage of new code paths
7. Run the project linter with the complexity rule enabled (`rules/engineering.md` §Measurable gates) — non-zero exit is a blocking issue.

---

## Phase 4 — Produce Report

Write `.claude/PR_REVIEW.md`:

```markdown
# PR Review: <title> (#<number>)

**Branch:** <head> -> <base>
**Reviewed:** <date>
**Verdict:** APPROVE / REQUEST CHANGES / BLOCK

## Summary
<1-2 sentence overview of what this PR does and the review outcome>

## Diff Analysis (differ-helper)
- Variables: <count new/changed>
- Functions: <count new/changed>
- Tests: <count new/changed>
- Imports: <count new/changed>
- Warnings: <list any duplicates or deprecated imports>

## Stage 1: Spec Compliance
**Status:** PASS / FAIL

| Criterion | Status | Notes |
|-----------|--------|-------|
| Acceptance criteria met | PASS/FAIL | ... |
| No scope creep | PASS/FAIL | ... |
| Edge cases handled | PASS/FAIL | ... |
| Test coverage of spec | PASS/FAIL | ... |

## Stage 2: Code Quality
**Status:** PASS / FAIL

| Criterion | Score | Threshold | Status |
|-----------|-------|-----------|--------|
| Correctness | X/10 | 7 | PASS/FAIL |
| Security | X/10 | 7 | PASS/FAIL |
| Completeness | X/10 | 6 | PASS/FAIL |
| Maintainability | X/10 | 5 | PASS/FAIL |
| Performance | X/10 | 5 | PASS/FAIL |
| Component Reusability | X/10 | 6 | PASS/FAIL/N/A |

## Blocking Issues (must fix before merge)
1. **[Category]** `file:line` — <what is wrong, why it matters in this domain, and a concrete fix (code snippet when non-obvious)>

## Non-Blocking Issues (fix in this PR or immediately after)
1. `file:line` — <technical debt, test gaps, pattern violations>

## Nits (minor style/naming — skip section if none)
- <brief bullet>

## What's Good
- <specific acknowledgment — generic praise is useless>

## Risk Matrix

| Area | Status | Notes |
|------|--------|-------|
| Race conditions / concurrency | Safe / Needs review / BLOCKING | |
| Sensitive-data safety | Safe / Needs review / BLOCKING | |
| Auth / access control | Safe / Needs review / BLOCKING | |
| Migration safety | N/A / Safe / BLOCKING | |
| Single source of truth | Safe / Needs review / BLOCKING | |
| Test coverage | Adequate / Gaps found / BLOCKING | |
| Performance (N+1, unbounded) | Safe / Needs review / BLOCKING | |

## Skipped Checklist Sections
- <section> — <why the diff has zero relevance to it>
```

**Verdict rules:** any single blocking issue → REQUEST CHANGES, no exceptions. non-blocking/nits only → APPROVE with notes. Architecture/design decision needed → NEEDS DISCUSSION.

---

## Phase 5 — Post to PR (optional, only if a PR exists and the user requests it)

Two-step approach: the detailed review goes in a **comment** (fully deletable on the next run), and a minimal one-line review carries only the approve/request-changes status. This keeps the PR timeline clean across re-reviews.

```bash
REPO=$(gh pr view <N> --json headRepository --jq '.headRepository.nameWithOwner')

# 0. Cleanup: delete previous bot review comments, dismiss stale bot reviews
for comment_id in $(gh api "repos/$REPO/issues/<N>/comments" --paginate \
  --jq '[.[] | select(.user.login == "github-actions[bot]" and (.body | test("Risk Matrix|PR Review|Verdict"))) | .id] | .[]'); do
  gh api -X DELETE "repos/$REPO/issues/<N>/comments/$comment_id" 2>/dev/null || true
done
for review_id in $(gh api "repos/$REPO/pulls/<N>/reviews" --paginate \
  --jq '[.[] | select(.user.login == "github-actions[bot]" and (.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "COMMENTED")) | .id] | .[]'); do
  gh api -X PUT "repos/$REPO/pulls/<N>/reviews/$review_id/dismissals" \
    -f message="Superseded by newer review" 2>/dev/null || true
done

# 1. Detailed review as a deletable comment
gh pr comment <N> --body-file .claude/PR_REVIEW.md

# 2. Minimal review for status only — pick one by verdict:
gh pr review <N> --request-changes --body "Review: changes requested — see comment for details."  # any blocking issue
gh pr review <N> --comment        --body "Review: minor notes — see comment for details."        # non-blocking/nits only
gh pr review <N> --approve        --body "Review: approved — see comment for details."           # clean

# 3. Re-request original reviewers to notify them
REVIEWERS=$(gh pr view <N> --json reviewRequests --jq '[.reviewRequests[].login] | join(",")' 2>/dev/null)
[ -n "$REVIEWERS" ] && gh pr edit <N> --request-reviewer "$REVIEWERS" 2>/dev/null || true
```

Rules: only submit `gh pr review` (step 2) when running in CI (`$CI` set); locally, post the comment only or output the report. Cleanup (step 0) only matters for bot-authored re-reviews.

---

## Variants

| Flag | Effect |
|------|--------|
| `--quick` | Skip differ-helper, score only Correctness + Security + Completeness |
| `--deep` | Dispatch 3 independent code-reviewer agents in parallel, aggregate scores |
| `--post` | Auto-post the review as a PR comment after generating |
| `--fix` | After review, dispatch builder to fix blocking issues (build-evaluate-fix loop, max 3 rounds) |

---

## Multi-Reviewer Mode (`--deep`)

When `--deep` is requested, spawn 3 code-reviewer agents in parallel, each with a different focus:

1. **Correctness & Security focus** — prioritize finding bugs and vulnerabilities
2. **Architecture & Maintainability focus** — prioritize design quality and readability
3. **Completeness & Testing focus** — prioritize coverage gaps and edge cases

Aggregate their scores (mean) and merge their findings (union of blocking issues, deduplicated).

---

## Anti-Patterns

- Do NOT review by reading only the diff hunks — always read full files for context
- Do NOT soften feedback to be polite — be direct, specific, actionable
- Do NOT skip Stage 1 to jump to code quality — incomplete features get sent back immediately
- Do NOT approve with "minor issues" if any criterion is below threshold
- Do NOT guess at the spec — if no spec exists, ask the user or review the PR body as the spec
- Do NOT accept a second copy of a value an existing function already produces — automatic blocking (see Single Source of Truth in the checklist); "it's only two lines" is not mitigation
- Do NOT trust the PR/commit description over the diff — "small refactor" touching critical logic gets full scrutiny
- Do NOT skip a checklist section silently — skipping requires stating zero relevance in the report
