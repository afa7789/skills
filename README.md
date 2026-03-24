# Skills for Claude Code and OpenCode

![imagem de skills](resources/image.png)

This repository contains **Agent Skills** that can be used with Claude Code and OpenCode. Skills are reusable instructions that AI agents can load when needed.

## What are Skills?

Skills are like "plugins" for your AI agent. Instead of writing the same instructions over and over, you create a skill once and the agent can load it when needed.

Example: Instead of explaining "how to do code review" every time, you create a `code-reviewer` skill with all the instructions. The agent just loads it and knows what to do.

Built with [dagRobin](https://github.com/afa7789/dagRobin) and [differ_helper](https://github.com/afa7789/differ_helper).

## dagRobin Integration

All skills are designed to work with **dagRobin** for multi-agent coordination. The workflow:

1. **task-splitter**: Decomposes large prompts into tasks
2. **dagRobin**: Creates and tracks tasks with dependencies
3. **architect/builder/senior-developer**: Claim tasks → work → done
4. **code-reviewer**: Reviews completed work
5. **differ-helper/estimator**: Analysis and estimation tasks

## How to Use Orchestrator

### Example 1: New Project from Scratch

```
Load the orchestrator skill

I want to build a Rust API with:
- PostgreSQL database
- JWT authentication
- User CRUD endpoints
- Product catalog
- Docker setup

Please create tasks and work on this until complete.
```

The orchestrator will:
1. Create `.claude/tasks.yaml` with all tasks
2. Create `.claude/TASKS.md` with descriptions
3. Create dagRobin tasks
4. Start the loop: execute → update → repeat

### Example 2: Existing Project with Plans

You already have plans in `.claude/`. First audit, then continue:

```
Load the audit skill

Audit this project and summarize what we have so far.
```

Then if you want to continue working:

```
Load the orchestrator skill

We already have tasks in .claude/tasks.yaml. Please continue from where we left off and finish the project.
```

### Example 3: Resume After Tokens Ran Out

```
Load the orchestrator skill

Check dagRobin for pending tasks and continue working on this project.
```

The orchestrator will:
1. Read current task status from YAML
2. Find ready tasks (dependencies met)
3. Continue the loop until done

## For Claude Code Users

Skills should be placed in `~/.claude/skills/<skill-name>/SKILL.md`

To use a skill in conversation:
```
Load the task-splitter skill
```

## For OpenCode Users

Skills can be placed in:
- Project level: `.opencode/skills/<skill-name>/SKILL.md`
- Global level: `~/.config/opencode/skills/<skill-name>/SKILL.md`

OpenCode also supports Claude-compatible paths:
- `.claude/skills/<skill-name>/SKILL.md`
- `~/.claude/skills/<skill-name>/SKILL.md`

To use a skill, the agent calls:
```
skill({ name: "task-splitter" })
```

## Available Skills

### task-splitter
Splits large prompts into dagRobin tasks and exports to Claude folders. Decompose requirements into actionable tasks with dependencies and priorities, then export task breakdown to `.claude/tasks/`. **Start here for new projects.**

### orchestrator
Orchestrates multiple agents to complete a project. Manages tasks in YAML + markdown, coordinates architect/builder/reviewer agents in a loop until complete. Uses dagRobin for coordination.

### dagrobin
Task coordination using dagRobin. Use dagRobin to manage tasks with dependencies, claim work, and track progress. Essential for multi-agent coordination.

### architect
Research & Planning specialist. Use to explore the codebase, analyze requirements, design architecture, and create plans before implementation begins.

### builder  
Core Implementation specialist. Use to implement features, write code, and make code changes based on an existing plan.

### senior-developer
Senior Developer specialist. Use for complex problem-solving, debugging difficult issues, and providing expert guidance.

### code-reviewer
Code Review specialist. Use when you need to review code changes, suggest improvements, identify bugs, and ensure code quality.

### project-manager
Converts specifications into actionable development tasks. Creates realistic task lists and focuses on scope management.

### differ-helper
Git diff analysis and duplicate removal workflow. Uses differ_helper tool to analyze git diffs, extract variables/functions/tests/imports, identify duplicates, check deprecated dependencies, and run lint/tests until stable.

### estimator
Multi-step project estimation with intermediate result saving. Uses differ_helper to analyze projects and saves progress at each step to separate files (paths.md, plan.md, steps.md, estimative.md) for later review. Ideal for long-running analyses.

### audit
Audits and summarizes Claude project files. Finds trash, outdated info, duplicates, and suggests what to clean up. Creates AUDIT.md with issues categorized by severity.

### summarizer
Summarizes and consolidates existing Claude files, plans, and tasks into a clean brief format. Use when project already has existing plans.

---

## Typical Workflow

### Starting a New Project

1. **Load task-splitter** skill
2. Paste your requirements prompt
3. Skill creates tasks in dagRobin + exports to `.claude/tasks/`

### Working on Tasks

1. Load **dagrobin** or any worker skill
2. Run `dagRobin ready` to see available tasks
3. Claim: `dagRobin update <id> --status in_progress --metadata "agent=claude"`
4. Do the work
5. Mark done: `dagRobin update <id> --status done`
6. Repeat

### Code Review

1. Load **code-reviewer** skill
2. Claim review task from dagRobin
3. Review changes
4. Mark done

### Analysis

1. Load **differ-helper** or **estimator** skill
2. Claim analysis task from dagRobin
3. Run differ_helper, save intermediate results
4. Mark done

---

## Adding dagRobin to Your Project

dagRobin is a shared task database. To use it in a project:

### 1. Install dagRobin

```bash
git clone https://github.com/afa7789/dagRobin.git
cd dagRobin
cargo build --release
cp target/release/dagRobin ~/.cargo/bin/dagRobin
```

### 2. Add to your project

Copy skills to your project's `.claude/skills/`:

```bash
mkdir -p .claude/skills/dagrobin
cp -r /path/to/skills/* .claude/skills/
```

Or use the sync script:

```bash
# Add to your paths.txt:
/path/to/your-project

./sync-skills.sh paths.txt
```

### 3. Initialize tasks

```bash
dagRobin add setup "Setup project" --priority 1
dagRobin add feature-a "Feature A" --deps setup --priority 2
dagRobin add feature-b "Feature B" --deps setup --priority 2
```

### 4. Use in agents

When starting work:
```bash
dagRobin ready           # See available tasks
dagRobin update <id> --status in_progress --metadata "agent=claude"
```

After finishing:
```bash
dagRobin update <id> --status done
```

### Shared Database

By default, dagRobin uses `dagrobin.db` in current directory. For shared access:
- All agents must use the same database file
- Use `--db /shared/path/dagrobin.db` to specify shared location
- Or place it in a git-tracked location

## Creating Your Own Skill

1. Create a folder: `<skill-name>/`
2. Create a file: `SKILL.md` inside it
3. Add frontmatter with name and description:

```yaml
---
name: my-skill
description: What this skill does
---
```

4. Add your instructions below

## Frontmatter Fields

- **name** (required): Skill identifier (lowercase, hyphens only)
- **description** (required): What the skill does (1-1024 chars)
- **license** (optional): License name
- **compatibility** (optional): Which agents can use it
- **metadata** (optional): Extra info as key-value pairs

## Skill Naming Rules

- 1-64 characters
- Lowercase letters and numbers
- Single hyphens only (no consecutive hyphens)
- Can't start or end with hyphen
- Must match folder name

## Sync Script

Use the `sync-skills.sh` script to sync skills to multiple locations at once.

### Usage

1. Create a file with the paths you want to sync to (one per line):

```text
# paths.txt
/Users/afa/Developer/my-project
~/.claude/skills
~/.config/opencode/skills
```

2. Run the script:

```bash
./sync-skills.sh paths.txt
```

### How it works

The script detects the target path format:
- If path contains `.claude/skills` → copies to `.claude/skills/<skill-name>/`
- If path contains `.opencode/skills` → copies to `.opencode/skills/<skill-name>/`
- Otherwise → copies to `<path>/skills/<skill-name>/`

## Manual Installation

To use these skills globally, copy the skill folders to your Claude Code skills directory:

```bash
cp -r skills/* ~/.claude/skills/
```

For OpenCode global skills:

```bash
cp -r skills/* ~/.config/opencode/skills/
```

For a specific project:

```bash
cp -r skills/* /path/to/your-project/.claude/skills/
```

## Skill Hierarchy

```
task-splitter     → Creates tasks in dagRobin
     ↓
dagrobin          → Manages task coordination
     ↓
architect         → Plans and designs
     ↓
builder           → Implements
senior-developer  → Helps with complex issues
code-reviewer     → Reviews
     ↓
differ-helper     → Analyzes diffs
estimator         → Estimates project scope
```

All skills use dagRobin for coordination!

---

## Scripts

### flatten-all.sh

Consolidates all plans, tasks, and markdown files from `.claude` folders into a single output file.

```bash
# Default: all markdown files
./scripts/flatten-all.sh

# Custom output
./scripts/flatten-all.sh -o my-output.md

# Filter by type
./scripts/flatten-all.sh -p plans      # Only PLAN*.md, TODO.md
./scripts/flatten-all.sh -p tasks     # Only *-tasks.md
./scripts/flatten-all.sh -p memory   # MEMORY.md, lessons.md
./scripts/flatten-all.sh -p agents     # Agent definitions
./scripts/flatten-all.sh -p skills    # Skill definitions
./scripts/flatten-all.sh -p dagrobin # dagRobin exports (*-paths.md, etc)

# Search in specific root
./scripts/flatten-all.sh -r /path/to/search

# Show help
./scripts/flatten-all.sh -h
```

**What it finds:**
- Global `~/.claude/` and `~/.config/opencode/`
- Project-level `.claude/` folders (walks up from current directory)
- Any `.claude` folder under search root

### sync-skills.sh

Syncs all skills to multiple locations from a paths file.

```bash
# Create a paths.txt file:
# /path/to/project1
# /path/to/project2
# ~/.claude/skills
# ~/.config/opencode/skills

# Run sync
./scripts/sync-skills.sh paths.txt
```
