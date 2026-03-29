# Skills for Claude Code and OpenCode

![imagem de skills](resources/image.png)

This repository contains **Agent Skills** that can be used with Claude Code and OpenCode. Skills are reusable instructions that AI agents can load when needed.

## What are Skills?

Skills are like "plugins" for your AI agent. Instead of writing the same instructions over and over, you create a skill once and the agent can load it when needed.

Example: Instead of explaining "how to do code review" every time, you create a `code-reviewer` skill with all the instructions. The agent just loads it and knows what to do.

Built with [dagRobin](https://github.com/afa7789/dagRobin) and [differ_helper](https://github.com/afa7789/differ_helper).

## dagRobin Integration

All skills are designed to work with **dagRobin** for multi-agent coordination. The workflow varies by complexity:

### Complex Projects (full pipeline)
1. **planner**: Expands short prompt into full product spec
2. **task-splitter**: Decomposes spec into dagRobin tasks
3. **architect**: Makes technical decisions, creates plan
4. **builder**: Implements features with sprint contracts
5. **qa-evaluator**: Tests running app via Playwright, grades against criteria
6. **Build-Evaluate-Fix loop**: Builder fixes issues → QA re-evaluates (max 3 rounds)

### Medium Projects (architect + builder + review)
1. **architect**: Plans the work
2. **builder**: Implements
3. **code-reviewer**: Single review pass with weighted criteria

### Simple Tasks (builder only)
1. **builder**: Fixes the bug or makes the change

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

### RTK (Token Savings)

https://github.com/rtk-ai/rtk

reduce the amount of tokens used in 60-90% while developing:

```bash
# Install
brew install rtk

# config, and reset your claude code.
rtk init -g
```

That will install the PreToolUse hook (ex: `git status` → `rtk git status`).

```bash
rtk --version
rtk gain        # Ver economia de tokens
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

### planner
Expands short user prompts (1-4 sentences) into full product specifications with user stories, data models, and design direction. Focuses on product context, not implementation details. Outputs `.claude/PRODUCT_SPEC.md`. **Start here for complex projects from scratch.**

### task-splitter
Splits large prompts into dagRobin tasks and exports to Claude folders. Decompose requirements into actionable tasks with dependencies and priorities, then export task breakdown to `.claude/tasks/`. **Start here for projects with detailed requirements.**

### orchestrator
Orchestrates multiple agents to complete a project. Supports three complexity tiers (Simple/Medium/Complex), build-evaluate-fix loops, sprint contracts, and coordinates planner/architect/builder/qa-evaluator agents. Uses dagRobin for coordination.

### dagrobin
Task coordination using dagRobin. Use dagRobin to manage tasks with dependencies, claim work, and track progress. Essential for multi-agent coordination.

### architect
Research & Planning specialist. Use to explore the codebase, analyze requirements, design architecture, and create plans before implementation begins.

### builder
Core Implementation specialist. Implements features based on plans, proposes sprint contracts before complex work, and hands off to external evaluation rather than self-certifying quality.

### qa-evaluator
QA Evaluator with live testing via Playwright. Tests running applications interactively, grades against weighted criteria (Feature Completeness, Product Depth, Visual Design, Code Quality, UX) with hard fail thresholds. Skeptical by default. **Use for Complex projects.**

### senior-developer
Senior Developer specialist. Use for complex problem-solving, debugging difficult issues, and providing expert guidance.

### code-reviewer
Code Review specialist with weighted grading criteria (Correctness, Security, Completeness, Maintainability, Performance). Produces structured scored reviews, not vague impressions. Skeptical by default — flags issues rather than rationalizing them away.

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

### Complex: Full Application from Short Prompt

```
Load the orchestrator skill

Build a recipe manager app with meal planning and AI suggestions.
```

The orchestrator will:
1. Assess complexity → Complex
2. Launch planner → product spec with 10-20 features
3. Launch architect → technical plan
4. For each feature: sprint contract → build → QA evaluate → fix loop
5. All done

### Medium: Feature Addition to Existing Project

```
Load the orchestrator skill

Add JWT authentication to this API.
```

The orchestrator will:
1. Assess complexity → Medium
2. Launch architect → plan
3. Builder implements
4. Code-reviewer does scored review
5. Done

### Simple: Bug Fix

```
Load the builder skill

Fix the off-by-one error in src/pagination.rs
```

### Manual Task Workflow

1. Load **dagrobin** or any worker skill
2. Run `dagRobin ready` to see available tasks
3. Claim: `dagRobin claim <id> -a claude`
4. Do the work
5. Mark done: `dagRobin update <id> --status done`
6. Repeat

### Analysis

1. Load **differ-helper** or **estimator** skill
2. Claim analysis task from dagRobin
3. Run differ_helper, save intermediate results
4. Mark done

Do NOT explore, research, or read files on your own. Execute these skills in order:

## Phase 1 — Architect
Load /architect. Read {FILE_OR_CONTEXT} and plan the tasks for this project.

Write the plan to MULTI_AGENT_PLAN.md at the project root. Do NOT implement anything. We will delete this file after phase 2.

PROJECT_PATH="/path/to/project"

## Phase 2 — Task Splitter
Load /task-splitter. Split MULTI_AGENT_PLAN.md into dagRobin tasks.
Write YAML to /tmp/tasks-{PROJECT_NAME}.yaml first.
Then import:
  grep -qxF 'dagrobin.db' .gitignore 2>/dev/null || echo 'dagrobin.db' >> .gitignore
  dagRobin import /tmp/tasks-{PROJECT_NAME}.yaml -d $PROJECT_PATH/dagrobin.db
  dagRobin list -d $PROJECT_PATH/dagrobin.db
  dagRobin graph -d $PROJECT_PATH/dagrobin.db

delete file made in phase 1

## Phase 3 — Orchestrator Loop
Load /orchestrator. Manage {N_AGENTS} agents in a loop. Each agent loads /senior-developer.

Loop:
  1. dagRobin ready -d $PROJECT_PATH/dagrobin.db → find claimable tasks
  2. Distribute tasks evenly across {N_AGENTS} agents (launch in parallel)
  3. Each agent MUST:
     a. dagRobin claim <task-id> -a senior-dev-{N} -d $PROJECT_PATH/dagrobin.db
     b. Do the work
     c. dagRobin update <task-id> --status done -d $PROJECT_PATH/dagrobin.db
  4. After all agents finish: dagRobin export .claude/tasks.yaml -d $PROJECT_PATH/dagrobin.db
  5. dagRobin ready -d $PROJECT_PATH/dagrobin.db → if more tasks, GOTO 1
  6. When no tasks remain → stop

Do NOT ask questions. Do NOT explore before Phase 1. Execute sequentially: architect → task-splitter → orchestrator loop.
```

---

## Examples

### Refactor UI components
```
PROJECT_PATH="/path/to/project"

Do NOT explore, research, or read files on your own. Execute these skills in order:

## Phase 1 — Architect
Load /architect. Read /path/to/project/.claude/iced.md and plan a refactor for /path/to/project.
Write the plan to MULTI_AGENT_PLAN.md at the project root. Do NOT implement anything.

## Phase 2 — Task Splitter
Load /task-splitter. Split MULTI_AGENT_PLAN.md into dagRobin tasks.
Write YAML to /tmp/tasks-my-project.yaml first.
Then import:
  grep -qxF 'dagrobin.db' .gitignore 2>/dev/null || echo 'dagrobin.db' >> .gitignore
  dagRobin import /tmp/tasks-my-project.yaml -d $PROJECT_PATH/dagrobin.db
  dagRobin list -d $PROJECT_PATH/dagrobin.db
  dagRobin graph -d $PROJECT_PATH/dagrobin.db

## Phase 3 — Orchestrator Loop
Load /orchestrator. Manage 3 agents in a loop. Each agent loads /senior-developer.

Loop:
  1. dagRobin ready -d $PROJECT_PATH/dagrobin.db → find claimable tasks
  2. Distribute tasks evenly across 3 agents (launch in parallel)
  3. Each agent MUST:
     a. dagRobin claim <task-id> -a senior-dev-{N} -d $PROJECT_PATH/dagrobin.db
     b. Do the work
     c. dagRobin update <task-id> --status done -d $PROJECT_PATH/dagrobin.db
  4. After all agents finish: dagRobin export .claude/tasks.yaml -d $PROJECT_PATH/dagrobin.db
  5. dagRobin ready -d $PROJECT_PATH/dagrobin.db → if more tasks, GOTO 1
  6. When no tasks remain → stop

Do NOT ask questions. Do NOT explore before Phase 1. Execute sequentially: architect → task-splitter → orchestrator loop.
```

### Add feature from scratch
```
PROJECT_PATH="/path/to/project"

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
  dagRobin import /tmp/tasks-oauth.yaml -d $PROJECT_PATH/dagrobin.db
  dagRobin list -d $PROJECT_PATH/dagrobin.db
  dagRobin graph -d $PROJECT_PATH/dagrobin.db

## Phase 3 — Orchestrator Loop
Load /orchestrator. Manage 2 agents in a loop. Each agent loads /builder.

Loop:
  1. dagRobin ready -d $PROJECT_PATH/dagrobin.db → find claimable tasks
  2. Distribute tasks evenly across 2 agents (launch in parallel)
  3. Each agent MUST:
     a. dagRobin claim <task-id> -a builder-{N} -d $PROJECT_PATH/dagrobin.db
     b. Do the work
     c. dagRobin update <task-id> --status done -d $PROJECT_PATH/dagrobin.db
  4. After all agents finish: dagRobin export .claude/tasks.yaml -d $PROJECT_PATH/dagrobin.db
  5. dagRobin ready -d $PROJECT_PATH/dagrobin.db → if more tasks, GOTO 1
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
# Ensure gitignore
grep -qxF 'dagrobin.db' .gitignore 2>/dev/null || echo 'dagrobin.db' >> .gitignore

# Batch (3+ tasks): write .claude/tasks.yaml then import
dagRobin import .claude/tasks.yaml

# Single task (1-2): add directly
dagRobin add setup "Setup project" --priority 1
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

### Complex Project Pipeline (build-evaluate-fix loop)

```
planner           → Expands short prompt into product spec
     ↓
task-splitter     → Creates tasks in dagRobin
     ↓
architect         → Technical decisions and plan
     ↓
builder ←──────── → qa-evaluator
  │  Implements       Tests running app via Playwright
  │  feature          Grades against criteria
  │                   │
  │    ┌──────────────┘
  │    │ FAIL: specific feedback
  │    ▼
  └─ Fixes issues, resubmits (max 3 rounds)
       │
       │ PASS
       ▼
  Next feature...
     ↓
differ-helper     → Analyzes diffs
estimator         → Estimates project scope
```

### Medium Project Pipeline (single review pass)

```
architect → builder → code-reviewer (scored review)
```

### Simple Task Pipeline

```
builder (fix and done)
```

All skills use dagRobin for coordination!

---

## RTK (Rust Token Killer)

[RTK](https://github.com/rtk-ai/rtk) é um CLI proxy de alto desempenho que reduz o consumo de tokens de LLMs em 60-90% em comandos comuns de desenvolvimento. Um único binário Rust, zero dependências, <10ms de overhead.

### Instalação

```bash
# Via Homebrew (recomendado)
brew install rtk

# Ou via curl
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
```

### Configuração para OpenCode

```bash
rtk init -g --opencode
```

Isso cria `~/.config/opencode/plugins/rtk.ts` e usa o hook `tool.execute.before`.

### Comandos Úteis

```bash
# Verificar instalação
rtk --version
rtk init --show

# Ver economia de tokens
rtk gain

# Comandos direto
rtk ls .                    # Árvore de diretório otimizada
rtk read arquivo.rs         # Leitura inteligente
rtk git status              # Status compacto
rtk git diff                # Diff condensado
rtk cargo test              # Mostra apenas falhas
rtk grep "pattern" .        # Resultados agrupados
```

### Como Funciona

O RTK filtra e comprime a saída de comandos antes de chegar ao contexto do LLM:

```
Sem RTK:  Claude --git status--> shell --> git (~2,000 tokens)
Com RTK:  Claude --git status--> RTK --> git (~200 tokens)
```

Estratégias aplicadas:
1. **Smart Filtering** - Remove ruído (comentários, whitespace, boilerplate)
2. **Grouping** - Agrega itens similares
3. **Truncation** - Mantém contexto relevante
4. **Deduplication** - Colapsa linhas repetidas

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
