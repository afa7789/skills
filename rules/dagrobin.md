# dagRobin — Standards & Best Practices

dagRobin is a shared task database for coordinating multiple AI agents. It provides a single source of truth for task coordination.

## Installation

```bash
git clone https://github.com/afa7789/dagRobin.git
cd dagRobin
make install
```

## Project Setup — IMPORTANT

**Always initialize dagRobin in the project root before using it:**

```bash
cd /path/to/your/project
dagRobin init          # Creates .dagrobin/db in current directory
```

This enables **automatic project isolation** — dagRobin walks up from the current directory to find `.dagrobin/db`, so subagents in any subdirectory automatically use the correct project database.

### Database Resolution (priority order)
1. `-d` flag — explicit override
2. `$DAGROBIN_DB` env var — inherited by subprocesses/subagents automatically
3. Walk-up `.dagrobin/db` — searches from CWD upward (like git finds `.git/`)
4. Global fallback `~/.local/share/dagRobin/dagrobin.db`

### Debug which database is being used
```bash
dagRobin which-db     # Prints the resolved database path
```

### ALWAYS gitignore the database
```bash
echo '.dagrobin/' >> .gitignore
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
dagRobin claim <task-id> -a your-name  # Claim before starting
dagRobin update <task-id> --status done                # Mark complete
dagRobin get <task-id>             # Check task details

# Visualization & Export
dagRobin graph                       # ASCII dependency graph
dagRobin graph --format mermaid     # Mermaid diagram
dagRobin export tasks.yaml          # Export to file
```

## Best Practices

### 2. CLAIM is for workers only
- **Orchestrator** creates and assigns tasks, but NEVER claims them
- **Builder/Worker** claims a task before starting: `dagRobin claim <id> -a name`
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

### 6. Every task MUST have a complete description
```yaml
- file: src/auth/mod.rs
  uses: [src/db/mod.rs]           # read-only dependencies (optional, default: [])
  description: Implement JWT auth middleware
  metadata:
    long-description: |
      Axum middleware that extracts Bearer token from Authorization header.
      Decode JWT using jsonwebtoken crate with HS256 and JWT_SECRET from Config.
      Claims struct: { sub: String (user_id), exp: usize, role: String }.
      On valid token: inject Claims into request extensions.
      On missing/invalid token: return 401 with JSON { "error": "Unauthorized" }.
```

**Why:** Builders are subagents with NO access to the original conversation or spec. The `metadata.long-description` is their ONLY source of truth. A task without a complete long-description will be implemented by guessing — and guessing wrong.

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

## File-Level Coordination

The `files:` field enables conflict detection for parallel execution:

```bash
# Detect which files are touched by multiple tasks
dagRobin list --format json | jq -r '.[] | .id, .files[]'
```

**Before dispatching parallel agents:**

1. Extract all files from pending tasks
2. Identify overlaps (same file in 2+ tasks)
3. If overlap exists: make tasks sequential OR assign to same agent

**Example conflict detection:**
```bash
# Output:
# implement-auth    src/auth/mod.rs,src/main.rs
# fix-main-routing  src/main.rs
#
# CONFLICT: src/main.rs touched by both tasks
# RESOLUTION: fix-main-routing depends on implement-auth
```

## Multi-Agent Workflow

```bash
# Agent 1: Checks what's available
dagRobin ready

# Agent 1: Claims a task
dagRobin claim auth-worker -a claude

# ... does work ...

# Agent 1: Marks done
dagRobin update auth-worker --status done

# Agent 2: Now sees auth-worker is done, can claim dependent task
dagRobin ready
dagRobin claim api-worker -a coworker
```

## Integration with Claude Code

1. Run `dagRobin init` in the project root
2. Add `.dagrobin/` to `.gitignore`
3. No `-d` flag needed — walk-up discovery handles it automatically

Subagents inherit the project context because they run from subdirectories of the same project root.
