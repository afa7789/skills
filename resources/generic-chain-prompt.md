Do NOT explore, research, or read files on your own. Execute these skills in order:

## Phase 1 — Architect
Load /architect. Read {FILE_OR_CONTEXT} and plan the tasks for this project.

Write the plan to MULTI_AGENT_PLAN.md at the project root. Do NOT implement anything. We will delete this file after phase 2.

## Phase 2 — Task Splitter
Load /task-splitter. Split MULTI_AGENT_PLAN.md into dagRobin tasks.
Write YAML to /tmp/tasks-{PROJECT_NAME}.yaml first.
Then import:
  grep -qxF 'dagrobin.db' .gitignore 2>/dev/null || echo 'dagrobin.db' >> .gitignore
  dagRobin import /tmp/tasks-{PROJECT_NAME}.yaml
  dagRobin list
  dagRobin graph

delete file made in phase 1

## Phase 3 — Orchestrator Loop
Load /orchestrator. Manage {N_AGENTS} agents in a loop. Each agent loads /senior-developer.

Loop:
  1. dagRobin ready → find claimable tasks
  2. Distribute tasks evenly across {N_AGENTS} agents (launch in parallel)
  3. Each agent MUST:
     a. dagRobin claim <task-id> --metadata "agent=senior-dev-{N}"
     b. Do the work
     c. dagRobin update <task-id> --status done
  4. After all agents finish: dagRobin export .claude/tasks.yaml
  5. dagRobin ready → if more tasks, GOTO 1
  6. When no tasks remain → stop

Do NOT ask questions. Do NOT explore before Phase 1. Execute sequentially: architect → task-splitter → orchestrator loop.
```

---

## Examples

### Refactor UI components
```
Do NOT explore, research, or read files on your own. Execute these skills in order:

## Phase 1 — Architect
Load /architect. Read /path/to/project/.claude/iced.md and plan a refactor for /path/to/project.
Write the plan to MULTI_AGENT_PLAN.md at the project root. Do NOT implement anything.

## Phase 2 — Task Splitter
Load /task-splitter. Split MULTI_AGENT_PLAN.md into dagRobin tasks.
Write YAML to /tmp/tasks-my-project.yaml first.
Then import:
  grep -qxF 'dagrobin.db' .gitignore 2>/dev/null || echo 'dagrobin.db' >> .gitignore
  dagRobin import /tmp/tasks-my-project.yaml
  dagRobin list
  dagRobin graph

## Phase 3 — Orchestrator Loop
Load /orchestrator. Manage 3 agents in a loop. Each agent loads /senior-developer.

Loop:
  1. dagRobin ready → find claimable tasks
  2. Distribute tasks evenly across 3 agents (launch in parallel)
  3. Each agent MUST:
     a. dagRobin claim <task-id> --metadata "agent=senior-dev-{N}"
     b. Do the work
     c. dagRobin update <task-id> --status done
  4. After all agents finish: dagRobin export .claude/tasks.yaml
  5. dagRobin ready → if more tasks, GOTO 1
  6. When no tasks remain → stop

Do NOT ask questions. Do NOT explore before Phase 1. Execute sequentially: architect → task-splitter → orchestrator loop.
```

### Add feature from scratch
```
Do NOT explore, research, or read files on your own. Execute these skills in order:

## Phase 1 — Architect
Load /architect. The feature: "Add OAuth2 login with Google and GitHub providers".
Target project: /path/to/project.
Write the plan to MULTI_AGENT_PLAN.md at the project root. Do NOT implement anything.

## Phase 2 — Task Splitter
Load /task-splitter. Split MULTI_AGENT_PLAN.md into dagRobin tasks.
Write YAML to /tmp/tasks-oauth.yaml first.
Then import:
  grep -qxF 'dagrobin.db' .gitignore 2>/dev/null || echo 'dagrobin.db' >> .gitignore
  dagRobin import /tmp/tasks-oauth.yaml
  dagRobin list
  dagRobin graph

## Phase 3 — Orchestrator Loop
Load /orchestrator. Manage 2 agents in a loop. Each agent loads /builder.

Loop:
  1. dagRobin ready → find claimable tasks
  2. Distribute tasks evenly across 2 agents (launch in parallel)
  3. Each agent MUST:
     a. dagRobin claim <task-id> --metadata "agent=builder-{N}"
     b. Do the work
     c. dagRobin update <task-id> --status done
  4. After all agents finish: dagRobin export .claude/tasks.yaml
  5. dagRobin ready → if more tasks, GOTO 1
  6. When no tasks remain → stop

Do NOT ask questions. Do NOT explore before Phase 1. Execute sequentially: architect → task-splitter → orchestrator loop.
```

---

## Key principles

1. **"Do NOT explore"** at the top kills the tangent behavior
2. **Numbered phases** make the order unambiguous
3. **tmp folder for YAML** ensures the chain flows: architect → yaml file → dagRobin import → agents claim
4. **Explicit dagRobin commands** leave no room for improvisation
5. **"Execute sequentially"** at the end reinforces the constraint
6. **Each agent loads /skill** tells Claude exactly which skill to use per agent

## Placeholders reference

| Placeholder | What to fill |
|---|---|
| `{FILE_OR_CONTEXT}` | Path to context file, or inline description |
| `{TASK_TYPE}` | refactor, feature, bugfix, migration, etc. |
| `{PROJECT_PATH}` | Absolute path to the project |
| `{PROJECT_NAME}` | Short name for tmp file (kebab-case) |
| `{N_AGENTS}` | Number of parallel agents (2-5 recommended) |
| `/senior-developer` | Can swap for `/builder`, `/code-reviewer`, etc. |
