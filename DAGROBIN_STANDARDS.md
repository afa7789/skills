# dagRobin — Standards & Best Practices

dagRobin is a shared task database for coordinating multiple AI agents. It provides a single source of truth for task coordination.

## Installation

```bash
git clone https://github.com/afa7789/dagRobin.git
cd dagRobin
cargo build --release
cp target/release/dagRobin ~/.cargo/bin/dagRobin
```

## Core Commands

### Task Management
```bash
# Create tasks (3+ use import, 1-2 use add)
dagRobin import tasks.yaml           # From YAML file
dagRobin add <id> "Description" --priority 1 --deps <other-id>

# Query tasks
dagRobin ready                        # What's ready to work on?
dagRobin list                        # Show all tasks
dagRobin blocked                     # What's waiting on dependencies?

# Work on tasks
dagRobin claim <task-id> --metadata "agent=your-name"  # Claim before starting
dagRobin update <task-id> --status done                # Mark complete
dagRobin get <task-id>             # Check task details

# Visualization & Export
dagRobin graph                       # ASCII dependency graph
dagRobin graph --format mermaid     # Mermaid diagram
dagRobin export tasks.yaml          # Export to file
```

## Best Practices

### 1. ALWAYS gitignore the database
```bash
echo 'dagrobin.db' >> .gitignore
```

### 2. CLAIM is for workers only
- **Orchestrator** creates and assigns tasks, but NEVER claims them
- **Builder/Worker** claims a task before starting: `dagRobin claim <id> --metadata "agent=name"`
- If claim fails (exit code 1), another agent is working on it — pick a different task

### 3. Use meaningful task IDs
- `setup-db`, `implement-auth`, `write-api-tests` (kebab-case)
- Group related: `auth-*`, `api-*`, `ui-*`

### 4. Set proper dependencies
- Task B depends on Task A → `--deps task-a`
- Dependencies must be satisfied before task becomes "ready"

### 5. Assign realistic priorities
- `1` = highest/must-do-first
- `5` = nice-to-have

### 6. Include metadata for tracking
```yaml
- id: task-id
  title: Task title
  priority: 1
  deps: []
  files: [src/main.rs]     # Files this task touches
  tags: [backend, core]    # For filtering
  metadata: {}              # Extra info (agent, dates, etc)
```

### 7. Limit task count
- Max ~15-20 tasks per project
- Each task: 30-60 min of work

### 8. Export snapshots regularly
```bash
dagRobin export .claude/tasks-snapshot.yaml
```

## Task Lifecycle

```
Pending → InProgress (claimed) → Done
              ↓
         Blocked (waiting on deps)
```

## Multi-Agent Workflow

```bash
# Agent 1: Checks what's available
dagRobin ready

# Agent 1: Claims a task
dagRobin claim auth-worker --metadata "agent=claude"

# ... does work ...

# Agent 1: Marks done
dagRobin update auth-worker --status done

# Agent 2: Now sees auth-worker is done, can claim dependent task
dagRobin ready
dagRobin claim api-worker --metadata "agent=cowork"
```

## Integration with Claude Code

Add to `.claude/CLAUDE.md`:

```markdown
# Task Management

This project uses dagRobin for task coordination.

## Commands
- `dagRobin ready` - What can I work on?
- `dagRobin list` - Show all tasks
- `dagRobin claim <id> --metadata "agent=claude"` - Claim before working
- `dagRobin update <id> --status done` - Mark complete

## Rules
- NEVER work on a task without claiming first
- If claim fails, pick a different task
- ALWAYS update status to "done" when finished
```
