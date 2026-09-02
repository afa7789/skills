```
Execute these phases in order; start Phase 1 immediately.

## Phase 1 — Architect
Dispatch the architect agent. Read {FILE_OR_CONTEXT} and plan the implementation for {PROJECT_PATH}.

Write the plan to .claude/PLAN.md. Do NOT implement anything.

## Phase 2 — Project Manager
Dispatch the project-manager agent. Read .claude/PLAN.md and decompose into minimal tasks.
Write tasks to .claude/tasks.yaml, then import:
  grep -qxF '.dagrobin/' .gitignore 2>/dev/null || echo '.dagrobin/' >> .gitignore
  dagRobin import .claude/tasks.yaml
  dagRobin list
  dagRobin graph

## Phase 3 — Orchestrator Loop
Dispatch the orchestrator agent. Manage {N_AGENTS} agents. Each agent is a builder.

Loop:
  1. dagRobin ready → find claimable tasks
  2. Identify parallel groups (no shared `uses` dependencies)
  3. Dispatch builders in background, one per parallel task (each in its own worktree)
  4. Each agent MUST:
     a. dagRobin claim <task-id> -a builder-{N}
     b. Do the work
     c. dagRobin update <task-id> --status done
  5. After batch completes: dagRobin ready
  6. If more tasks → GOTO 1
  7. When no tasks remain → stop

You are operating autonomously; the user is not watching and cannot answer mid-run. Proceed without asking on reversible actions. Execute sequentially: architect → project-manager → orchestrator loop.
```

---

## Examples

### Refactor UI components
```
Execute these phases in order; start Phase 1 immediately:

## Phase 1 — Architect
Dispatch the architect agent. Read /path/to/project/.claude/iced.md and plan a refactor for /path/to/project.
Write the plan to .claude/PLAN.md. Do NOT implement anything.

## Phase 2 — Project Manager
Dispatch the project-manager agent. Read .claude/PLAN.md and decompose into minimal tasks.
Write tasks to .claude/tasks.yaml, then import:
  grep -qxF '.dagrobin/' .gitignore 2>/dev/null || echo '.dagrobin/' >> .gitignore
  dagRobin import .claude/tasks.yaml
  dagRobin list
  dagRobin graph

## Phase 3 — Orchestrator Loop
Dispatch the orchestrator agent. Manage 3 agents. Each agent is a builder.

Loop:
  1. dagRobin ready → find claimable tasks
  2. Dispatch parallel builders in background
  3. Each agent MUST:
     a. dagRobin claim <task-id> -a builder-{N}
     b. Do the work
     c. dagRobin update <task-id> --status done
  4. After batch completes: dagRobin ready
  5. If more tasks → GOTO 1
  6. When no tasks remain → stop

You are operating autonomously; the user is not watching and cannot answer mid-run. Execute sequentially: architect → project-manager → orchestrator loop.
```

---

## Key principles

1. **Three phases** make the order unambiguous: plan → decompose → execute
2. **Minimal task schema** (`file`, `uses`, `description`) keeps tasks clean
3. **Background agents by default** for parallel execution
4. **dagRobin commands** leave no room for improvisation

## Placeholders reference

| Placeholder | What to fill |
|---|---|
| `{FILE_OR_CONTEXT}` | Path to context file, or inline description |
| `{PROJECT_PATH}` | Absolute path to the project |
| `{N_AGENTS}` | Number of parallel agents (2-5 recommended) |
