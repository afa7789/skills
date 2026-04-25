Do NOT explore, research, or read files on your own. Execute these phases in order:

## Phase 1 — Architect
Load /architect. Read {FILE_OR_CONTEXT} and plan the implementation for {PROJECT_PATH}.

Write the plan to .claude/PLAN.md. Do NOT implement anything.

## Phase 2 — Project Manager
Load /project-manager. Read .claude/PLAN.md and decompose into minimal tasks.
Write tasks to .claude/tasks.yaml, then import:
  grep -qxF 'dagrobin.db' .gitignore 2>/dev/null || echo 'dagrobin.db' >> .gitignore
  dagRobin import .claude/tasks.yaml
  dagRobin list
  dagRobin graph

## Phase 3 — Orchestrator Loop
Load /orchestrator. Manage {N_AGENTS} agents. Each agent loads /builder.

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

Do NOT ask questions. Do NOT explore before Phase 1. Execute sequentially: architect → project-manager → orchestrator loop.
```

---

## Examples

### Refactor UI components
```
Do NOT explore, research, or read files on your own. Execute these phases in order:

## Phase 1 — Architect
Load /architect. Read /path/to/project/.claude/iced.md and plan a refactor for /path/to/project.
Write the plan to .claude/PLAN.md. Do NOT implement anything.

## Phase 2 — Project Manager
Load /project-manager. Read .claude/PLAN.md and decompose into minimal tasks.
Write tasks to .claude/tasks.yaml, then import:
  grep -qxF 'dagrobin.db' .gitignore 2>/dev/null || echo 'dagrobin.db' >> .gitignore
  dagRobin import .claude/tasks.yaml
  dagRobin list
  dagRobin graph

## Phase 3 — Orchestrator Loop
Load /orchestrator. Manage 3 agents. Each agent loads /builder.

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

Do NOT ask questions. Execute sequentially: architect → project-manager → orchestrator loop.
```

---

## Key principles

1. **"Do NOT explore"** kills tangent behavior
2. **Three phases** make the order unambiguous: plan → decompose → execute
3. **Minimal task schema** (`file`, `uses`, `description`) keeps tasks clean
4. **Background agents by default** for parallel execution
5. **dagRobin commands** leave no room for improvisation

## Placeholders reference

| Placeholder | What to fill |
|---|---|
| `{FILE_OR_CONTEXT}` | Path to context file, or inline description |
| `{PROJECT_PATH}` | Absolute path to the project |
| `{N_AGENTS}` | Number of parallel agents (2-5 recommended) |
