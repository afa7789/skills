---
name: dagrobin
description: Task coordination using dagRobin. Use dagRobin to manage tasks with dependencies, claim work, and track progress. Essential for multi-agent coordination.
---

You are a task coordination specialist using dagRobin.

## Prerequisites

Ensure dagRobin is installed:

```bash
git clone https://github.com/afa7789/dagRobin.git
cd dagRobin
cargo build --release
cp target/release/dagRobin ~/.cargo/bin/dagRobin
```

## First-Time Setup

**Always** ensure `dagrobin.db` is gitignored:

```bash
# Auto-add to .gitignore if not present
grep -qxF 'dagrobin.db' .gitignore 2>/dev/null || echo 'dagrobin.db' >> .gitignore
```

---

## dagRobin Basics

dagRobin is a shared task database for multiple AI agents. It prevents agents from stepping on each other.

### Core Commands

```bash
# Batch creation (3+ tasks): write YAML then import
dagRobin import tasks.yaml
dagRobin import tasks.yaml --merge    # Merge with existing tasks
dagRobin import tasks.yaml --replace  # Replace all existing tasks

# Single task (1-2 tasks): add directly
dagRobin add <task-id> "Task description" --priority 1 --deps <other-task-id>

# Export current tasks to YAML
dagRobin export tasks.yaml
dagRobin export tasks.yaml --status done  # Export only done tasks

# Show ready tasks (dependencies met, not in progress)
dagRobin ready

# List all tasks
dagRobin list

# Claim a task before working on it
dagRobin claim <task-id> --metadata "agent=your-name"

# Update task status
dagRobin update <task-id> --status done

# Visualize the task graph
dagRobin graph
```

---

## Workflow

### Step 0 — Check current state + ensure gitignore

```bash
grep -qxF 'dagrobin.db' .gitignore 2>/dev/null || echo 'dagrobin.db' >> .gitignore
dagRobin list
dagRobin ready
```

### Step 1 — Plan tasks via YAML import

For 3+ tasks, use YAML import instead of adding one by one:

1. Write a YAML file with all tasks:

```yaml
# .claude/tasks.yaml
- id: setup-db
  title: Setup database
  status: Pending
  priority: 1
  deps: []
  files: []
  tags: []
  metadata: {}

- id: build-api
  title: Build API endpoints
  status: Pending
  priority: 2
  deps: [setup-db]
  files: []
  tags: []
  metadata: {}

- id: write-tests
  title: Write tests
  status: Pending
  priority: 3
  deps: [build-api]
  files: []
  tags: []
  metadata: {}
```

2. Import in one command:

```bash
dagRobin import .claude/tasks.yaml
```

### Step 2 — Claim work

Before starting any task, ALWAYS claim it:

```bash
dagRobin claim <task-id> --metadata "agent=claude"
```

If this fails (exit code 1), another agent is working on it — pick another task.

### Step 3 — Do the work

Implement the feature, run tests, etc.

### Step 4 — Mark done

```bash
dagRobin update <task-id> --status done
```

### Step 5 — Check what's next

```bash
dagRobin ready
```

Repeat until all done.

### Step 6 — Export snapshot (optional)

Save current state for later reference:

```bash
dagRobin export .claude/tasks-snapshot.yaml
```

---

## Important Rules

1. **ALWAYS gitignore `dagrobin.db`** — Never commit the database
2. **Use YAML import for 3+ tasks** — `dagRobin add` is fine for 1-2 tasks
3. **ALWAYS claim before working** — Never work on a task without claiming it first
4. **Check ready before claiming** — Use `dagRobin ready` to see available tasks
5. **Use proper status values**: `pending`, `in_progress`, `done`, `blocked`
6. **Add metadata** — Include agent name so others know who's working on what
7. **Don't duplicate work** — If claim fails, another agent is on it

---

## Multi-Agent Coordination

When multiple agents are working:

- Agent A: `dagRobin ready` → claims task-1 → works → marks done
- Agent B: `dagRobin ready` → sees task-2 is now ready → claims → works

This prevents:
- Two agents working on the same task
- Agents working on tasks whose dependencies aren't met
- Losing track of who's doing what
