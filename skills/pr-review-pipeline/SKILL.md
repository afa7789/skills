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

## Phase 0 — Resolve PR Context

Determine what to review:

```bash
# If PR number provided:
rtk gh pr view <N> --json number,title,body,baseRefName,headRefName,files,additions,deletions

# If no number, use current branch:
rtk gh pr view --json number,title,body,baseRefName,headRefName,files,additions,deletions

# If no open PR exists for the branch, review the local diff against default branch:
BASE=$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')
rtk git diff "$BASE"...HEAD --stat
```

Capture:
- **PR title & body** (the spec for Stage 1)
- **Base branch** (for diff baseline)
- **Changed files list** (scope of review)
- **Additions / deletions** (size estimate)

---

## Phase 1 — Diff Analysis (differ-helper)

Run differ-helper against the PR's base:

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
1. **[Category]** `file:line` — <description and suggested fix>

## Suggestions (non-blocking)
1. `file:line` — <suggestion>

## What's Good
- <brief acknowledgment of strengths>
```

---

## Phase 5 — Post to PR (optional)

If the user requests it, post the review as a PR comment:

```bash
gh pr comment <N> --body-file .claude/PR_REVIEW.md
```

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
