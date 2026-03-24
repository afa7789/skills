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

---

## dagRobin Basics

dagRobin is a shared task database for multiple AI agents. It prevents agents from stepping on each other.

### Core Commands

```bash
# Add a new task
dagRobin add <task-id> "Task description" --priority 1

# Add task with dependencies
dagRobin add <task-id> "Task description" --deps <other-task-id>

# Show ready tasks (dependencies met, not in progress)
dagRobin ready

# List all tasks
dagRobin list

# Claim a task before working on it
dagRobin update <task-id> --status in_progress --metadata "agent=your-name"

# Mark as done
dagRobin update <task-id> --status done

# Visualize the task graph
dagRobin graph
```

---

## Workflow

### Step 0 — Check current state

Always start by checking what tasks exist:

```bash
dagRobin list
dagRobin ready
```

### Step 1 — Plan tasks

If no tasks exist, create a plan:

```bash
dagRobin add setup-db "Setup database" --priority 1
dagRobin add build-api "Build API" --deps setup-db --priority 2
dagRobin add write-tests "Write tests" --deps build-api --priority 3
```

### Step 2 — Claim work

Before starting any task, ALWAYS claim it:

```bash
dagRobin update <task-id> --status in_progress --metadata "agent=claude"
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

---

## Important Rules

1. **ALWAYS claim before working** — Never work on a task without claiming it first
2. **Check ready before claiming** — Use `dagRobin ready` to see available tasks
3. **Use proper status values**: `pending`, `in_progress`, `done`, `blocked`
4. **Add metadata** — Include agent name so others know who's working on what
5. **Don't duplicate work** — If claim fails, another agent is on it

---

## Multi-Agent Coordination

When multiple agents are working:

- Agent A: `dagRobin ready` → claims task-1 → works → marks done
- Agent B: `dagRobin ready` → sees task-2 is now ready → claims → works

This prevents:
- Two agents working on the same task
- Agents working on tasks whose dependencies aren't met
- Losing track of who's doing what
