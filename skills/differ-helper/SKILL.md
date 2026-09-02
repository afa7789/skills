---
name: differ-helper
description: Git diff analysis and duplicate removal workflow. Use to analyze git diffs, extract variables/functions/tests/imports, identify duplicates, check deprecated dependencies, and run lint/tests until stable.
---

You are a code analysis specialist using differ_helper to analyze git diffs.

## Prerequisites

1. RTK initialized in the target project (token-optimized output for git diff and lint):
   ```bash
   # In the project directory you will work on:
   rtk init
   ```

2. Rust installed:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

3. `differ_helper` installed (stable path — not `/tmp`, which is purged on reboot):
   ```bash
   command -v differ_helper >/dev/null || {
     git clone https://github.com/afa7789/differ_helper "$HOME/.local/src/differ_helper"
     cd "$HOME/.local/src/differ_helper" && make install && cd -
   }
   ```

4. Update to latest:
   ```bash
   cd "$HOME/.local/src/differ_helper" && git pull && make reinstall && cd -
   ```

## Task Coordination

Use dagRobin to track analysis steps:

```bash
dagRobin ready
dagRobin claim <task-id> -a analyzer
# ... do analysis ...
dagRobin update <task-id> --status done
```

---

## Workflow

### Step 1 — Extract names from the diff

Run differ_helper in the current repo:

```bash
differ_helper
```

This auto-detects where the current branch diverged from its upstream (e.g. origin/main).

You can also target a specific base:
```bash
differ_helper main
differ_helper origin/develop
differ_helper v1.2.0
```

Or pass a diff file directly:
```bash
differ_helper /path/to/diff.txt
```

The output contains: VARIABLES, FUNCTIONS, TESTS, IMPORTS, WARNINGS.

---

### Steps 2, 3, 4, 5 — Analyze in parallel

From the VARIABLES, FUNCTIONS, TESTS and IMPORTS lists, find:

- **Step 2 — variables:** duplicate concepts — same name across files, or one concept under several names
- **Step 3 — functions:** duplicated logic
- **Step 4 — tests:** duplicated tests
- **Step 5 — imports:** packages that are deprecated, archived, or vulnerable (name the modern alternative)

Report each as a WARNING with file paths.

---

### Step 6 — Remove duplicates

Using only the duplicates flagged in Steps 2-5:
1. Decide which version to keep (prefer more descriptive name or complete implementation)
2. Provide exact code changes to remove duplicates
3. List every file that must be updated

---

### Step 7 — Run lint and CI/CD

Run the project's lint/CI pipeline. Fix every style and format issue. The lint config must include a per-function complexity rule (`rules/engineering.md` §Measurable gates) — a project with no complexity gate is itself a finding. Fix complexity violations by simplifying control flow, not by splitting functions.

---

### Step 8 — Run tests

Run the full unit test suite. Report pass/fail with error messages. Fix failures and re-run.

---

### Loop

Repeat Steps 7 and 8 until:
1. Lint and CI pass with no warnings
2. All unit tests pass

---

## Action Rules

- **Simple fix** (drop-in replacement): Apply refactoring directly
- **Complex migration** (different API, touches many files): Report only, do NOT refactor

## Output Format

For each step, provide:
- What was analyzed
- Findings (with file paths)
- Warnings (duplicates, deprecated imports, etc.)
- Actions taken
